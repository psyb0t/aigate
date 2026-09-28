"""Env-driven config — parsed at import time, fail-fast on bad input."""

from __future__ import annotations

import json
import os
from pathlib import Path


def _int_env(name: str, default: int) -> int:
    raw = os.environ.get(name, "").strip()
    if raw == "":
        return default
    try:
        return int(raw)
    except ValueError as exc:
        raise ValueError(f"{name}={raw!r} is not an integer") from exc


def _float_env(name: str, default: float) -> float:
    raw = os.environ.get(name, "").strip()
    if raw == "":
        return default
    try:
        return float(raw)
    except ValueError as exc:
        raise ValueError(f"{name}={raw!r} is not a number") from exc


def _list_env(name: str) -> list[str]:
    raw = os.environ.get(name, "")
    return [s.strip() for s in raw.split(",") if s.strip()]


HOST: str = os.environ.get("LLAMACPP_WRAP_HOST", "0.0.0.0")
PORT: int = _int_env("LLAMACPP_WRAP_PORT", 8000)

# "cuda" or "cpu". Informational only (the actual GPU offload is controlled
# per-model via the `--n-gpu-layers` flag in `llama_server_args`); kept here
# so /healthz can report which image flavour is running.
DEVICE: str = os.environ.get("LLAMACPP_WRAP_DEVICE", "").strip().lower()

# Internal port the supervised `llama-server` subprocess listens on (loopback).
SUBPROCESS_PORT: int = _int_env("LLAMACPP_WRAP_SUBPROCESS_PORT", 18000)

# Absolute path of the `llama-server` binary inside the base image. Both the
# CPU and CUDA upstream images put it at /app/llama-server (their ENTRYPOINT
# is exactly that path); the env var lets us override for unusual rebuilds.
SERVER_BIN: Path = Path(
    os.environ.get("LLAMACPP_WRAP_SERVER_BIN", "/app/llama-server")
).resolve()

MODELS_FILE: Path = Path(
    os.environ.get("LLAMACPP_WRAP_MODELS_FILE", "/app/models.json")
).resolve()

DATA_DIR: Path = Path(
    os.environ.get("LLAMACPP_WRAP_DATA_DIR", "/data")
).resolve()

# Models live under MODELS_DIR/<repo>, mirroring the Hugging Face repository
# path. The pull sidecar fetches only declared, checksum-pinned GGUF artifacts.
# Other services that bind-mount the same path can load the weights directly.
MODELS_DIR: Path = Path(
    os.environ.get("LLAMACPP_WRAP_MODELS_DIR", str(DATA_DIR / "models"))
).resolve()

# Idle TTL: kill the subprocess if no requests for this many seconds.
# -1 disables the sweeper (process stays loaded until /unload or shutdown).
MODEL_IDLE_TIMEOUT_SECONDS: float = _float_env("LLAMACPP_WRAP_MODEL_TTL", 600.0)
SWEEPER_INTERVAL_SECONDS: float = _float_env("LLAMACPP_WRAP_SWEEPER_INTERVAL", 60.0)

# Subprocess boot: how long to wait for llama-server's /health to return 200.
# Vision models with mmproj take noticeably longer than text-only on first
# load, so default is generous.
LOAD_TIMEOUT_SECONDS: float = _float_env("LLAMACPP_WRAP_LOAD_TIMEOUT", 600.0)
# Per-request proxy timeout (long generations / large image embedding work).
REQUEST_TIMEOUT_SECONDS: float = _float_env("LLAMACPP_WRAP_REQUEST_TIMEOUT", 300.0)

# Pre-warm the subprocess at startup with this model_id (optional).
PRELOAD: str = os.environ.get("LLAMACPP_WRAP_PRELOAD", "").strip()

# Pre-download these HF repos at entrypoint time (comma-separated model_ids
# resolved via models.json — the entrypoint script does this BEFORE the
# wrapper starts so the supervisor never blocks on the network).
PREFETCH: list[str] = _list_env("LLAMACPP_WRAP_PREFETCH")


def load_registry() -> dict[str, dict]:
    """Read models.json and return {model_id: {repo, gguf_file, ...}}."""
    if not MODELS_FILE.exists():
        raise FileNotFoundError(f"models.json not found at {MODELS_FILE}")
    with MODELS_FILE.open("r", encoding="utf-8") as fh:
        raw = json.load(fh)
    if not isinstance(raw, dict) or "models" not in raw:
        raise ValueError(f"{MODELS_FILE}: expected top-level object with 'models' key")
    models = raw["models"]
    if not isinstance(models, dict) or not models:
        raise ValueError(f"{MODELS_FILE}: 'models' must be a non-empty object")
    for model_id, entry in models.items():
        if not isinstance(entry, dict):
            raise ValueError(f"{MODELS_FILE}: model {model_id!r} entry must be an object")
        if "repo" not in entry or not isinstance(entry["repo"], str):
            raise ValueError(f"{MODELS_FILE}: model {model_id!r} missing string 'repo'")
        if "gguf_file" not in entry or not isinstance(entry["gguf_file"], str):
            raise ValueError(
                f"{MODELS_FILE}: model {model_id!r} missing string 'gguf_file'"
            )
        mmproj = entry.get("mmproj_file")
        if mmproj is not None and not isinstance(mmproj, str):
            raise ValueError(
                f"{MODELS_FILE}: model {model_id!r} 'mmproj_file' must be a string or null"
            )
        args = entry.get("llama_server_args", [])
        if not isinstance(args, list) or not all(isinstance(a, str) for a in args):
            raise ValueError(
                f"{MODELS_FILE}: model {model_id!r} 'llama_server_args' must be a list of strings"
            )
        endpoints = entry.get("endpoints", ["chat"])
        if not isinstance(endpoints, list) or not endpoints:
            raise ValueError(
                f"{MODELS_FILE}: model {model_id!r} 'endpoints' must be a non-empty list"
            )
        allowed = ("chat", "completions", "embeddings")
        for ep in endpoints:
            if ep not in allowed:
                raise ValueError(
                    f"{MODELS_FILE}: model {model_id!r} endpoint {ep!r} must be "
                    f"one of {allowed}"
                )
        # Optional per-model orchestration handler. None / missing → default
        # one-shot proxy path. A string name resolves to a registered
        # Handler implementation in `llamacpp_wrap.handlers`.
        handler = entry.get("handler")
        if handler is not None and not isinstance(handler, str):
            raise ValueError(
                f"{MODELS_FILE}: model {model_id!r} 'handler' must be a string or null"
            )
        # Optional auto-ctx-size knobs (used when llama_server_args contains
        # `--ctx-size auto`). All optional; missing fields fall back to
        # conservative defaults in `supervisor._compute_ctx_size`.
        for field in (
            "max_ctx_size",
            "kv_bytes_per_token",
            "weights_estimate_bytes",
        ):
            value = entry.get(field)
            if value is None:
                continue
            if not isinstance(value, int) or isinstance(value, bool):
                raise ValueError(
                    f"{MODELS_FILE}: model {model_id!r} {field!r} must be an int"
                )
            if value <= 0:
                raise ValueError(
                    f"{MODELS_FILE}: model {model_id!r} {field!r} must be positive"
                )
    return models
