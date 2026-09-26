"""Subprocess supervisor — at most one `vllm serve` child at a time.

vLLM holds the entire model in VRAM; switching models means killing the
current subprocess, waiting for VRAM to drain, then spawning a new one.
This module owns that lifecycle and exposes a single async method
`ensure(model_id)` that the FastAPI handlers call before proxying.

The supervisor also tracks last-used time so a background sweeper can
kill an idle subprocess after a configurable TTL.
"""

from __future__ import annotations

import asyncio
import logging
import os
import signal
import time
from typing import Any

import httpx

from . import config


log = logging.getLogger("vllm_wrap.supervisor")


class SupervisorError(RuntimeError):
    pass


class Supervisor:
    def __init__(self, registry: dict[str, dict]) -> None:
        self._registry = registry
        self._lock = asyncio.Lock()
        self._proc: asyncio.subprocess.Process | None = None
        self._current_model: str | None = None
        self._last_used: float | None = None
        # Tracks request leases so we don't kill the subprocess mid-request
        # (e.g. idle-sweeper firing while a long transcription is streaming).
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

        Kills any other subprocess first, then spawns `vllm serve` for the
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
        extra_args: list[str] = list(entry.get("vllm_args", []))

        # Pull container downloaded files flat under MODELS_DIR/<repo>. Pass
        # that local path to `vllm serve` instead of the HF repo string so it
        # loads from disk without any HF cache lookup.
        local_path = config.MODELS_DIR / repo
        if not local_path.exists():
            raise SupervisorError(
                f"model {model_id!r} not found at {local_path} — "
                f"vllm-cuda-pull must download it first"
            )

        cmd = [
            "vllm",
            "serve",
            str(local_path),
            "--host", "127.0.0.1",
            "--port", str(config.SUBPROCESS_PORT),
            "--served-model-name", model_id,
        ]
        if config.DEVICE in ("cpu", "cuda"):
            cmd.extend(["--device", config.DEVICE])
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
                        f"vllm subprocess exited during boot (rc="
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
            f"vllm subprocess did not become healthy in {config.LOAD_TIMEOUT_SECONDS}s"
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
