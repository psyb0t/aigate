"""Subprocess supervisor — at most one `llama-server` child at a time.

llama-server holds the entire model in memory (RAM on CPU image, VRAM on CUDA
image); switching models means killing the current subprocess, waiting for
memory to drain, then spawning a new one. This module owns that lifecycle and
exposes a single async method `ensure(model_id)` that the FastAPI handlers
call before proxying.

Mirrors the surface area of vllm-wrap's Supervisor so the LiteLLM
resource_manager can drive both backends with the same DELETE /api/ps/
{model_id} call. The only meaningful differences are:

  - Subprocess argv is built from `llama-server -m <gguf> [--mmproj <mmproj>]
    --host 127.0.0.1 --port N <llama_server_args>` instead of
    `vllm serve <local_path> --host 127.0.0.1 --port N <vllm_args>`.
  - llama-server's health endpoint is /health (same as vllm — handy).
"""

from __future__ import annotations

import asyncio
import logging
import os
import shutil
import signal
import subprocess
import time
from typing import Any

import httpx

from . import config


log = logging.getLogger("llamacpp_wrap.supervisor")


class SupervisorError(RuntimeError):
    pass


# ── auto ctx-size resolution ──────────────────────────────────────────────
#
# Model entries may set `--ctx-size auto` in `llama_server_args` to let the
# supervisor probe free GPU VRAM / system RAM at spawn time and pick the
# largest `--ctx-size` value that fits, capped at the model's trained
# `max_ctx_size` (per-model field). Constants below are the operator-tunable
# knobs that govern the math — overrideable via env so deployments with
# unusual memory budgets (other CUDA tenants, dedicated containers, etc.)
# can dial them in without rebuilding the image.

# Floor: never pick a smaller ctx than this. If the probe says we don't have
# room, we'd rather fail loudly at load-time than serve a 1K-context model.
_CTX_FLOOR_DEFAULT = 16384

# Safety margin subtracted from probed free memory before dividing by the
# per-token KV cost. Covers CUDA graph allocation, batch buffers, Mamba-SSM
# state, mmproj scratch, and other overhead the per-token formula doesn't
# capture. Conservative default — bigger margin = smaller chosen ctx but
# less risk of OOM-at-first-request.
_CTX_SAFETY_MARGIN_DEFAULT_BYTES = 1 * 1024 * 1024 * 1024  # 1 GiB

# Per-model registry fields used here (all optional — missing fields fall
# back to the conservative defaults below):
#   max_ctx_size           model's trained context ceiling. Going past
#                          this wastes memory without benefit. For Surya
#                          OCR 2 (qwen3_5_text) the model card declares
#                          max_position_embeddings=262144.
#   kv_bytes_per_token     per-token KV cache cost in bytes. For pure-
#                          attention transformers: 2(K+V) * n_layers *
#                          n_kv_heads * head_dim * sizeof(fp16/cache_dtype).
#                          For hybrid Mamba+attention models (Surya, Qwen3
#                          .5 generation): count only full-attention layers
#                          — linear/Mamba blocks have constant state.
#   weights_estimate_bytes total memory consumed by model weights + mmproj
#                          when fully loaded. Used to budget what's left
#                          for the KV cache. If missing, falls back to
#                          file-size-on-disk.

_CTX_FALLBACK_KV_BYTES_PER_TOKEN = 16 * 1024  # 16 KiB — conservative
_CTX_FALLBACK_MAX_CTX_SIZE = 16384


def _ctx_floor() -> int:
    raw = os.environ.get("LLAMACPP_WRAP_CTX_FLOOR", "").strip()
    if not raw:
        return _CTX_FLOOR_DEFAULT
    try:
        return max(1024, int(raw))
    except ValueError:
        log.warning(
            "LLAMACPP_WRAP_CTX_FLOOR=%r is not an int; falling back to %d",
            raw,
            _CTX_FLOOR_DEFAULT,
        )
        return _CTX_FLOOR_DEFAULT


def _ctx_safety_margin_bytes() -> int:
    raw = os.environ.get("LLAMACPP_WRAP_CTX_SAFETY_MARGIN_BYTES", "").strip()
    if not raw:
        return _CTX_SAFETY_MARGIN_DEFAULT_BYTES
    try:
        return max(0, int(raw))
    except ValueError:
        log.warning(
            "LLAMACPP_WRAP_CTX_SAFETY_MARGIN_BYTES=%r is not an int; "
            "falling back to %d",
            raw,
            _CTX_SAFETY_MARGIN_DEFAULT_BYTES,
        )
        return _CTX_SAFETY_MARGIN_DEFAULT_BYTES


def _probe_free_cuda_vram_bytes() -> int | None:
    """Returns free VRAM on the first visible GPU in bytes, or None when
    nvidia-smi isn't reachable. Single-GPU assumption — if the container
    sees multiple GPUs llama.cpp uses the first one by default and the
    probe matches that. Multi-GPU layouts would need a per-device probe.
    """
    if shutil.which("nvidia-smi") is None:
        return None
    try:
        out = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=memory.free",
                "--format=csv,noheader,nounits",
                "-i", "0",
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        log.warning("nvidia-smi probe failed: %s", exc)
        return None
    line = out.stdout.strip().splitlines()
    if not line:
        return None
    try:
        mib = int(line[0].strip())
    except ValueError:
        log.warning("nvidia-smi returned unparseable %r", line[0])
        return None
    return mib * 1024 * 1024


def _probe_free_ram_bytes() -> int | None:
    """Returns MemAvailable from /proc/meminfo in bytes, or None if it
    isn't readable (e.g. on a non-Linux host or a container without
    /proc)."""
    try:
        with open("/proc/meminfo", "r", encoding="utf-8") as fh:
            for raw in fh:
                if raw.startswith("MemAvailable:"):
                    parts = raw.split()
                    return int(parts[1]) * 1024
    except OSError as exc:
        log.warning("/proc/meminfo probe failed: %s", exc)
    return None


def _gguf_size_on_disk(repo_dir: Any, entry: dict) -> int:
    """Sum the bytes-on-disk of the model's GGUF + mmproj GGUF (if any).
    Lossy proxy for actual loaded weight memory — useful as a floor when
    `weights_estimate_bytes` isn't declared on the model entry."""
    total = 0
    for key in ("gguf_file", "mmproj_file"):
        name = entry.get(key)
        if not name:
            continue
        try:
            total += (repo_dir / name).stat().st_size
        except OSError:
            pass
    return total


def _resolve_auto_ctx_size(
    *,
    extra_args: list[str],
    entry: dict,
    repo_dir: Any,
    device: str,
) -> list[str]:
    """Substitute every `--ctx-size auto` in `extra_args` with a computed
    integer value based on free memory + the model's per-token KV cost +
    its trained max. Returns a new list (does NOT mutate the input).

    If the probe fails or required model fields are missing, falls back
    to `_CTX_FALLBACK_MAX_CTX_SIZE` and logs a warning. We never silently
    pick a tiny ctx — that surprise belongs as a config issue, not a
    runtime mystery.
    """
    new_args: list[str] = list(extra_args)
    i = 0
    while i < len(new_args):
        if (
            new_args[i] == "--ctx-size"
            and i + 1 < len(new_args)
            and new_args[i + 1].lower() == "auto"
        ):
            chosen = _compute_ctx_size(
                entry=entry,
                repo_dir=repo_dir,
                device=device,
            )
            log.info(
                "ctx-size auto → %d (model_id=%s)",
                chosen,
                entry.get("repo", "?"),
            )
            new_args[i + 1] = str(chosen)
            i += 2
            continue
        i += 1
    return new_args


# ── auto thread count ─────────────────────────────────────────────────────
#
# `--threads auto` resolves to the CPUs this container may actually use: the
# cgroup v2 quota in /sys/fs/cgroup/cpu.max, capped by the scheduler affinity.
# llama.cpp's own `-1` counts host cores and ignores the quota. With more
# threads than quota, CFS throttles the workers at every sync point and
# decoding slows by an order of magnitude.

_CGROUP_CPU_MAX = "/sys/fs/cgroup/cpu.max"


def _available_cpus() -> int:
    count = len(os.sched_getaffinity(0))
    try:
        with open(_CGROUP_CPU_MAX, encoding="ascii") as f:
            quota, period = f.read().split()[:2]
    except (OSError, ValueError):
        return count
    if quota == "max":
        return count
    return max(1, min(count, int(quota) // int(period)))


def _resolve_auto_threads(extra_args: list[str]) -> list[str]:
    """Substitute every `--threads auto` in `extra_args` with the usable CPU
    count. Returns a new list (does NOT mutate the input)."""
    new_args: list[str] = list(extra_args)
    for i in range(len(new_args) - 1):
        if new_args[i] == "--threads" and new_args[i + 1].lower() == "auto":
            chosen = _available_cpus()
            log.info("threads auto → %d", chosen)
            new_args[i + 1] = str(chosen)
    return new_args


def _compute_ctx_size(*, entry: dict, repo_dir: Any, device: str) -> int:
    """Compute the largest sane `--ctx-size` for this model + this hardware.

    Math:
        free_for_kv  = probed_free_mem - weights_estimate - safety_margin
        max_tokens   = free_for_kv // kv_bytes_per_token
        chosen       = clamp(max_tokens, floor, model_max_ctx)
        chosen       = chosen rounded down to a multiple of 1024
    """
    floor = _ctx_floor()
    safety = _ctx_safety_margin_bytes()
    max_ctx = int(entry.get("max_ctx_size") or _CTX_FALLBACK_MAX_CTX_SIZE)
    kv_per_tok = int(
        entry.get("kv_bytes_per_token") or _CTX_FALLBACK_KV_BYTES_PER_TOKEN
    )
    if kv_per_tok <= 0:
        log.warning(
            "model %r has non-positive kv_bytes_per_token=%d; using fallback %d",
            entry.get("repo", "?"),
            kv_per_tok,
            _CTX_FALLBACK_KV_BYTES_PER_TOKEN,
        )
        kv_per_tok = _CTX_FALLBACK_KV_BYTES_PER_TOKEN
    weights = int(
        entry.get("weights_estimate_bytes")
        or _gguf_size_on_disk(repo_dir, entry)
        or 0
    )

    if device == "cuda":
        free_mem = _probe_free_cuda_vram_bytes()
        source = "CUDA VRAM"
    else:
        free_mem = _probe_free_ram_bytes()
        source = "system RAM"

    if free_mem is None:
        log.warning(
            "could not probe free %s; falling back to ctx=%d", source, max_ctx
        )
        return _round_down_to_kib(max(min(max_ctx, floor * 2), floor))

    free_for_kv = free_mem - weights - safety
    if free_for_kv <= 0:
        log.warning(
            "probed free %s (%d B) is below weights (%d B) + safety (%d B) "
            "by %d B; falling back to ctx floor=%d",
            source,
            free_mem,
            weights,
            safety,
            -free_for_kv,
            floor,
        )
        return _round_down_to_kib(floor)

    max_tokens = free_for_kv // kv_per_tok
    chosen = min(max_tokens, max_ctx)
    chosen = max(chosen, floor)
    chosen = _round_down_to_kib(chosen)
    log.info(
        "ctx-size auto math: free=%.2f GiB, weights=%.2f GiB, safety=%.2f GiB, "
        "kv_per_tok=%d B → headroom for %d tokens; model_max=%d, floor=%d, "
        "chosen=%d",
        free_mem / 1024**3,
        weights / 1024**3,
        safety / 1024**3,
        kv_per_tok,
        max_tokens,
        max_ctx,
        floor,
        chosen,
    )
    return chosen


def _round_down_to_kib(n: int) -> int:
    """Round n down to the nearest multiple of 1024. llama.cpp accepts any
    positive --ctx-size but multiples of 1024 keep batch allocation clean."""
    return max(1024, (int(n) // 1024) * 1024)


class Supervisor:
    def __init__(self, registry: dict[str, dict]) -> None:
        self._registry = registry
        self._lock = asyncio.Lock()
        self._proc: asyncio.subprocess.Process | None = None
        self._current_model: str | None = None
        self._last_used: float | None = None
        # Tracks request leases so we don't kill the subprocess mid-request
        # (e.g. idle-sweeper firing while a long OCR pass is streaming).
        self._inflight = 0
        self._inflight_drained = asyncio.Event()
        self._inflight_drained.set()

    # ── public API ─────────────────────────────────────────────────────────

    def loaded(self) -> str | None:
        """Return the model_id currently loaded, or None."""
        return self._current_model

    def last_used_secs_ago(self) -> float | None:
        if self._last_used is None:
            return None
        # A running request counts as use. Without this the idle sweeper
        # measures from the request's start and kills the subprocess under a
        # request that runs longer than the idle TTL.
        if self._inflight > 0:
            return 0.0
        return time.monotonic() - self._last_used

    async def ensure(self, model_id: str) -> None:
        """Make sure `model_id` is the currently loaded subprocess.

        Kills any other subprocess first, then spawns `llama-server` for the
        requested model and waits for /health. Idempotent if the requested
        model is already loaded.
        """
        if model_id not in self._registry:
            raise SupervisorError(
                f"unknown model {model_id!r}; configured: {list(self._registry)}"
            )

        async with self._lock:
            if self._current_model == model_id and self._proc is not None:
                if self._proc.returncode is None:
                    return
                log.warning(
                    "subprocess for %s exited unexpectedly (rc=%s); respawning",
                    model_id,
                    self._proc.returncode,
                )
                self._proc = None
                self._current_model = None

            if self._proc is not None:
                await self._kill_locked()

            await self._spawn_locked(model_id)

    async def unload(self) -> str | None:
        """Kill the current subprocess. Returns the model_id that was killed."""
        async with self._lock:
            killed = self._current_model
            if self._proc is not None:
                await self._kill_locked()
            return killed

    def lease(self) -> "_Lease":
        """Block the idle sweeper for the duration of a request."""
        return _Lease(self)

    def mark_used(self) -> None:
        self._last_used = time.monotonic()

    # ── internals (called with self._lock held) ────────────────────────────

    async def _spawn_locked(self, model_id: str) -> None:
        entry = self._registry[model_id]
        repo = entry["repo"]
        gguf_file = entry["gguf_file"]
        mmproj_file = entry.get("mmproj_file")
        extra_args: list[str] = list(entry.get("llama_server_args", []))

        # Pull container deposited files under MODELS_DIR/<repo>/<file>. Pass
        # the absolute paths to llama-server.
        repo_dir = config.MODELS_DIR / repo
        gguf_path = repo_dir / gguf_file
        if not gguf_path.exists():
            raise SupervisorError(
                f"model {model_id!r} gguf not found at {gguf_path} — "
                f"llamacpp-pull must download {repo} first"
            )

        # Resolve any `--ctx-size auto` sentinel in the model's
        # llama_server_args against current free VRAM/RAM. Runs once per
        # spawn — recomputed on every model swap so sibling-evicted
        # services that just freed memory get their headroom counted in.
        extra_args = _resolve_auto_ctx_size(
            extra_args=extra_args,
            entry=entry,
            repo_dir=repo_dir,
            device=config.DEVICE or "cpu",
        )
        extra_args = _resolve_auto_threads(extra_args)

        cmd = [
            str(config.SERVER_BIN),
            "-m", str(gguf_path),
            "--host", "127.0.0.1",
            "--port", str(config.SUBPROCESS_PORT),
            "--alias", model_id,
            "--jinja",
        ]

        if mmproj_file:
            mmproj_path = repo_dir / mmproj_file
            if not mmproj_path.exists():
                raise SupervisorError(
                    f"model {model_id!r} mmproj not found at {mmproj_path} — "
                    f"llamacpp-pull must download {repo} (including the "
                    f"vision projector) first"
                )
            cmd.extend(["--mmproj", str(mmproj_path)])

        # If the model entry requested an embedding endpoint, llama-server
        # needs the --embeddings flag at boot. (Chat / completions need no
        # special flag.)
        endpoints = entry.get("endpoints", [])
        if "embeddings" in endpoints:
            cmd.append("--embeddings")

        cmd.extend(extra_args)

        log.info("spawning: %s", " ".join(cmd))
        env = os.environ.copy()
        env.setdefault("HF_HUB_OFFLINE", "1")

        self._proc = await asyncio.create_subprocess_exec(
            *cmd,
            env=env,
            stdout=None,
            stderr=None,
            preexec_fn=os.setsid,
        )
        self._current_model = model_id

        try:
            await self._wait_for_health()
        except Exception as exc:
            log.error("subprocess for %s failed to become healthy: %s", model_id, exc)
            await self._kill_locked()
            raise

        self._last_used = time.monotonic()
        log.info("subprocess for %s is healthy on port %d", model_id, config.SUBPROCESS_PORT)

    async def _wait_for_health(self) -> None:
        deadline = time.monotonic() + config.LOAD_TIMEOUT_SECONDS
        url = f"http://127.0.0.1:{config.SUBPROCESS_PORT}/health"
        async with httpx.AsyncClient(timeout=5.0) as client:
            while time.monotonic() < deadline:
                if self._proc is None or self._proc.returncode is not None:
                    raise SupervisorError(
                        f"llama-server subprocess exited during boot (rc="
                        f"{self._proc.returncode if self._proc else 'none'})"
                    )
                try:
                    r = await client.get(url)
                    if r.status_code == 200:
                        return
                except (httpx.ConnectError, httpx.ReadError, httpx.RemoteProtocolError):
                    pass
                except httpx.HTTPError as e:
                    log.debug("health probe error: %s", e)
                await asyncio.sleep(1.0)
        raise SupervisorError(
            f"llama-server subprocess did not become healthy in "
            f"{config.LOAD_TIMEOUT_SECONDS}s"
        )

    async def _kill_locked(self) -> None:
        proc = self._proc
        model = self._current_model
        if proc is None:
            self._current_model = None
            return

        if self._inflight > 0:
            log.info(
                "waiting for %d in-flight request(s) to drain before killing %s",
                self._inflight,
                model,
            )
            try:
                await asyncio.wait_for(self._inflight_drained.wait(), timeout=30.0)
            except asyncio.TimeoutError:
                log.warning(
                    "in-flight drain timed out; killing %s anyway", model
                )

        log.info("killing subprocess for %s (pid=%s)", model, proc.pid)
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        except ProcessLookupError:
            pass

        try:
            await asyncio.wait_for(proc.wait(), timeout=20.0)
        except asyncio.TimeoutError:
            log.warning("SIGTERM timeout; SIGKILLing subprocess for %s", model)
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            except ProcessLookupError:
                pass
            try:
                await asyncio.wait_for(proc.wait(), timeout=10.0)
            except asyncio.TimeoutError:
                log.error("subprocess for %s did not die after SIGKILL", model)

        self._proc = None
        self._current_model = None
        self._last_used = None
        log.info("subprocess for %s killed", model)


class _Lease:
    def __init__(self, sup: Supervisor) -> None:
        self._sup = sup

    def __enter__(self) -> "_Lease":
        self._sup._inflight += 1
        self._sup._inflight_drained.clear()
        return self

    def __exit__(self, *exc: Any) -> None:
        self._sup._inflight -= 1
        if self._sup._inflight <= 0:
            self._sup._inflight = 0
            self._sup._inflight_drained.set()
        self._sup.mark_used()
