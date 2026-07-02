"""
CUDA/CPU resource manager for LiteLLM proxy.

Enforces two things:
1. Mutual exclusion — only one CUDA job (and one CPU job) at a time via
   asyncio.Semaphore(1).  A chat completion on ollama-cuda blocks until
   an in-flight sdcpp-cuda image generation finishes, and vice-versa.
2. Competing-group unload — before the request proceeds, all other groups
   on the same hardware are told to free VRAM/RAM.

Groups (CUDA):
  cuda-llm          : local-ollama-cuda-* models
  cuda-img          : local-sdcpp-cuda-* (sd.cpp image generation)
  cuda-stt-talkies  : local-talkies-cuda-*  (ASR + Kokoro TTS + Qwen3-TTS)
  cuda-vllm         : local-vllm-cuda-*  (text LLMs + embeddings via vllm serve)
  cuda-llamacpp     : local-llamacpp-cuda-*  (vision-VLM serving via llama-server + mmproj)

Groups (CPU):
  cpu-llm           : local-ollama-cpu-* models   (unload frees RAM)
  cpu-img           : local-sdcpp-cpu-* (sd.cpp image generation)
  cpu-stt-talkies   : local-talkies-*
  cpu-vllm          : local-vllm-*  (text LLMs + embeddings via vllm serve)
  cpu-llamacpp      : local-llamacpp-*  (vision-VLM serving via llama-server + mmproj)

Each group is unloaded before a request lands on a competing group (so
qwen3-tts frees VRAM before talkies-cuda needs it, etc.). Within a service,
the wrapper handles its own intra-service eviction (only one model resident
at a time).

Kokoro (CPU + CUDA TTS) is intentionally NOT in any group — Kokoro-FastAPI
has no unload endpoint and the model is tiny (~80MB VRAM), so it coexists
without needing cross-service eviction.

Unloading uses DELETE /api/ps/{model_id} where supported (talkies), which
evicts the model from memory but keeps weights on disk — next request
auto-reloads.
"""

import asyncio
import logging
import os
from typing import Optional

import httpx

from litellm.integrations.custom_logger import CustomLogger

logger = logging.getLogger("litellm.proxy")

# ---------------------------------------------------------------------------
# Model → group mapping
# ---------------------------------------------------------------------------

_CUDA_LLM_PREFIX = "local-ollama-cuda-"
_CPU_LLM_PREFIX = "local-ollama-cpu-"

_CUDA_IMG_PREFIX = "local-sdcpp-cuda-"
_CPU_IMG_PREFIX = "local-sdcpp-cpu-"

# talkies — unified ASR (whisper + parakeet + canary). Both CPU and CUDA
# variants share `local-talkies-` prefix; CUDA adds `cuda-` infix.
_TALKIES_CUDA_PREFIX = "local-talkies-cuda-"
_TALKIES_CPU_PREFIX = "local-talkies-"

# vllm — supervised single-model vllm serve (text LLM + embeddings).
# CUDA prefix must be checked before CPU (longer prefix wins).
_VLLM_CUDA_PREFIX = "local-vllm-cuda-"
_VLLM_CPU_PREFIX = "local-vllm-"

# llamacpp — supervised single-model llama-server (vision-VLM serving via
# mmproj). Same prefix-checking caveat as vllm.
_LLAMACPP_CUDA_PREFIX = "local-llamacpp-cuda-"
_LLAMACPP_CPU_PREFIX = "local-llamacpp-"

_ALL_CUDA_GROUPS = {
    "cuda-llm",
    "cuda-img",
    "cuda-stt-talkies",
    "cuda-vllm",
    "cuda-llamacpp",
    # Direct-HTTP CUDA services (not routed via LiteLLM completions):
    # audiolla + flickies expose their own HTTP APIs through nginx.
    # No `local-audiolla-*` / `local-flickies-*` model_name is defined
    # so `_get_group()` never returns these — they only appear here as
    # COMPETING groups so LiteLLM-routed calls (talkies / ollama / vllm /
    # llamacpp / sdcpp) evict them before allocating VRAM. Without this
    # a LatentSync or Wav2Lip session hoarding 7+ GiB of VRAM OOM-kills
    # talkies-cuda the moment it tries to load a Whisper model.
    "cuda-audiolla",
    "cuda-flickies",
}
_ALL_CPU_GROUPS = {
    "cpu-llm",
    "cpu-img",
    "cpu-stt-talkies",
    "cpu-vllm",
    "cpu-llamacpp",
    "cpu-audiolla",
    "cpu-flickies",
}


def _get_group(model: str) -> Optional[str]:
    if model.startswith(_CUDA_LLM_PREFIX):
        return "cuda-llm"
    if model.startswith(_CPU_LLM_PREFIX):
        return "cpu-llm"
    if model.startswith(_CUDA_IMG_PREFIX):
        return "cuda-img"
    if model.startswith(_CPU_IMG_PREFIX):
        return "cpu-img"
    # talkies CUDA must be checked before CPU (longer prefix wins)
    if model.startswith(_TALKIES_CUDA_PREFIX):
        return "cuda-stt-talkies"
    if model.startswith(_TALKIES_CPU_PREFIX):
        return "cpu-stt-talkies"
    if model.startswith(_VLLM_CUDA_PREFIX):
        return "cuda-vllm"
    if model.startswith(_VLLM_CPU_PREFIX):
        return "cpu-vllm"
    # llamacpp CUDA must be checked before CPU (longer prefix wins)
    if model.startswith(_LLAMACPP_CUDA_PREFIX):
        return "cuda-llamacpp"
    if model.startswith(_LLAMACPP_CPU_PREFIX):
        return "cpu-llamacpp"
    return None


# ---------------------------------------------------------------------------
# Unload actions per group
# ---------------------------------------------------------------------------


async def _unload_cuda_llm():
    """Tell ollama-cuda to unload all currently loaded models."""
    logger.warning("[resource_manager] unloading cuda-llm models")
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            r = await client.get("http://ollama-cuda:11434/api/ps")
            models = r.json().get("models", [])
            if not models:
                logger.warning("[resource_manager] cuda-llm: no models loaded")
                return
            for m in models:
                name = m["name"]
                logger.warning("[resource_manager] cuda-llm: unloading %s", name)
                await client.post(
                    "http://ollama-cuda:11434/api/generate",
                    json={"model": name, "keep_alive": 0, "stream": False},
                )
                logger.warning("[resource_manager] cuda-llm: unloaded %s", name)
        except Exception as e:
            logger.warning("[resource_manager] cuda-llm unload error: %s", e)


async def _unload_cpu_llm():
    """Tell ollama CPU to unload all currently loaded models."""
    logger.warning("[resource_manager] unloading cpu-llm models")
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            r = await client.get("http://ollama:11434/api/ps")
            models = r.json().get("models", [])
            if not models:
                logger.warning("[resource_manager] cpu-llm: no models loaded")
                return
            for m in models:
                name = m["name"]
                logger.warning("[resource_manager] cpu-llm: unloading %s", name)
                await client.post(
                    "http://ollama:11434/api/generate",
                    json={"model": name, "keep_alive": 0, "stream": False},
                )
                logger.warning("[resource_manager] cpu-llm: unloaded %s", name)
        except Exception as e:
            logger.warning("[resource_manager] cpu-llm unload error: %s", e)


_SDCPP_CUDA_URL = "http://sdcpp-cuda:7234"
_SDCPP_CPU_URL = "http://sdcpp:7234"


async def _unload_cuda_img():
    """Tell sdcpp-cuda wrapper to unload the model context and free VRAM."""
    logger.warning("[resource_manager] unloading cuda-img (sdcpp-cuda)")
    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            r = await client.post(f"{_SDCPP_CUDA_URL}/sdcpp/v1/unload")
            logger.warning(
                "[resource_manager] cuda-img unloaded, status=%s", r.status_code
            )
        except Exception as e:
            logger.warning("[resource_manager] cuda-img unload error: %s", e)


async def _unload_cpu_img():
    """Tell sdcpp wrapper to unload the model context and free RAM."""
    logger.warning("[resource_manager] unloading cpu-img (sdcpp)")
    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            r = await client.post(f"{_SDCPP_CPU_URL}/sdcpp/v1/unload")
            logger.warning(
                "[resource_manager] cpu-img unloaded, status=%s", r.status_code
            )
        except Exception as e:
            logger.warning("[resource_manager] cpu-img unload error: %s", e)


# Model-key extraction for sdcpp preload. LiteLLM aliases follow the
# `local-sdcpp-{cuda,cpu}-<model-key>` shape — strip the prefix to get
# what sdcpp's /sdcpp/v1/load endpoint expects.
_SDCPP_CUDA_PREFIX = "local-sdcpp-cuda-"
_SDCPP_CPU_PREFIX = "local-sdcpp-cpu-"


async def _preload_sdcpp(base_url: str, model_key: str) -> None:
    """POST /sdcpp/v1/load?model=<key> and block until sdcpp has the model
    loaded.

    Why this exists: sdcpp's image-gen handler `TryLockModel`-s on every
    POST /v1/images/generations. If the model isn't loaded yet, the FIRST
    call triggers an ~19s load while holding the lock — any concurrent
    call within that window returns 503 "another load or generation in
    progress". LiteLLM router responds to a 503 by retrying (num_retries=3)
    and walking the fallback chain, every attempt hits the same lock,
    every attempt 503s, and the whole storm ends with LiteLLM returning
    HTTP 200 + empty `data` because image-gen fallback-exhaustion masks
    the upstream error.

    Pre-loading inside the resource_manager's pre_call hook (while we still
    hold the cuda-img/cpu-img semaphore) means by the time LiteLLM
    dispatches the actual image-gen call the backend is already warm and
    the call succeeds on attempt 1. No 503, no fallback storm, no empty-
    data response. Behaves as a no-op (~ms) when the requested model is
    already loaded.

    Failures here are LOGGED, not raised. If preload fails (model missing,
    weights corrupt, GPU OOM), letting LiteLLM call the backend anyway
    surfaces the real upstream error rather than blocking the request
    forever.
    """
    async with httpx.AsyncClient(timeout=180.0) as client:
        try:
            r = await client.post(
                f"{base_url}/sdcpp/v1/load",
                params={"model": model_key},
            )
            if r.status_code == 200:
                logger.warning(
                    "[resource_manager] sdcpp preloaded model=%s body=%s",
                    model_key, r.text[:200],
                )
            else:
                logger.warning(
                    "[resource_manager] sdcpp preload non-200 model=%s status=%s body=%s",
                    model_key, r.status_code, r.text[:200],
                )
        except Exception as e:
            logger.warning(
                "[resource_manager] sdcpp preload error model=%s base=%s: %s",
                model_key, base_url, e,
            )


def _sdcpp_key_for(model: str, group: str) -> tuple[str, str] | None:
    """Map a LiteLLM model alias to (sdcpp base URL, sdcpp model key).
    Returns None if the alias doesn't match the expected sdcpp shape."""
    if group == "cuda-img" and model.startswith(_SDCPP_CUDA_PREFIX):
        return _SDCPP_CUDA_URL, model[len(_SDCPP_CUDA_PREFIX):]
    if group == "cpu-img" and model.startswith(_SDCPP_CPU_PREFIX):
        return _SDCPP_CPU_URL, model[len(_SDCPP_CPU_PREFIX):]
    return None


# talkies — unified ASR + TTS; DELETE /api/ps/{model_id} per model. Lists
# must stay in sync with the model_name set in
# litellm/config/providers/talkies{,-cuda}.yaml (which mirrors the
# talkies image's enabled ENABLE_<MODEL> flag set). When adding a model
# upstream, also add it here so the resource_manager actually evicts it.
_TALKIES_CUDA_URL = "http://talkies-cuda:8000"
_TALKIES_CPU_URL = "http://talkies:8000"
_TALKIES_CUDA_MODELS = [
    "whisper-large-v3",
    "whisper-large-v3-turbo",
    "parakeet-tdt-0.6b-v3",
    "canary-180m-flash",
    "canary-1b-flash",
    "canary-qwen-2.5b",
    "nemotron-3.5-asr-0.6b",
    "kokoro-82m",
    "kokoro-82m-nvidia",
    "qwen3-tts-0.6b",
    "qwen3-tts-1.7b",
    "qwen3-tts-0.6b-custom",
    "qwen3-tts-1.7b-custom",
    "qwen3-tts-1.7b-design",
]
_TALKIES_CPU_MODELS = [
    "whisper-large-v3",
    "whisper-large-v3-turbo",
    "canary-180m-flash",
    "nemotron-3.5-asr-0.6b",
    "kokoro-82m",
    "kokoro-82m-nvidia",
]


async def _unload_via_api_ps(base_url: str, group: str, model_ids: list) -> None:
    """Unload models from a service exposing DELETE /api/ps/{model_id}
    (talkies). Parallel — one slow upstream shouldn't block the other
    unloads.
    """
    async with httpx.AsyncClient(timeout=10.0) as client:
        async def _one(model_id: str) -> None:
            encoded = model_id.replace("/", "%2F")
            try:
                r = await client.delete(f"{base_url}/api/ps/{encoded}")
                if r.status_code == 200:
                    logger.warning(
                        "[resource_manager] %s: unloaded %s", group, model_id
                    )
                elif r.status_code == 404:
                    logger.warning(
                        "[resource_manager] %s: %s not loaded, skipping",
                        group,
                        model_id,
                    )
                else:
                    logger.warning(
                        "[resource_manager] %s: unload %s status=%s",
                        group,
                        model_id,
                        r.status_code,
                    )
            except Exception as e:
                logger.warning(
                    "[resource_manager] %s: unload error for %s: %s", group, model_id, e
                )

        await asyncio.gather(*(_one(mid) for mid in model_ids), return_exceptions=True)


async def _unload_cuda_stt_talkies():
    """Unload CUDA STT models from talkies-cuda to free VRAM."""
    logger.warning("[resource_manager] unloading cuda-stt-talkies models")
    await _unload_via_api_ps(
        _TALKIES_CUDA_URL, "cuda-stt-talkies", _TALKIES_CUDA_MODELS
    )


async def _unload_cpu_stt_talkies():
    """Unload CPU STT models from talkies to free RAM."""
    logger.warning("[resource_manager] unloading cpu-stt-talkies models")
    await _unload_via_api_ps(
        _TALKIES_CPU_URL, "cpu-stt-talkies", _TALKIES_CPU_MODELS
    )


# vllm-cuda — supervised single-model wrapper. Same /api/ps surface as
# talkies, so reuse _unload_via_api_ps. The wrapper enforces only-one-model
# resident internally; this just nudges it to free VRAM when something else
# needs CUDA. Model IDs must match the wrapper's models.json slugs.
_VLLM_CUDA_URL = "http://vllm-cuda:8000"
_VLLM_CPU_URL = "http://vllm:8000"
_VLLM_MODELS = [
    "nomic-embed-v2",
    "qwen3-0.6b",
]


async def _unload_cuda_vllm():
    """Unload CUDA vllm models to free VRAM."""
    logger.warning("[resource_manager] unloading cuda-vllm models")
    await _unload_via_api_ps(
        _VLLM_CUDA_URL, "cuda-vllm", _VLLM_MODELS
    )


async def _unload_cpu_vllm():
    """Unload CPU vllm models to free RAM."""
    logger.warning("[resource_manager] unloading cpu-vllm models")
    await _unload_via_api_ps(
        _VLLM_CPU_URL, "cpu-vllm", _VLLM_MODELS
    )


# llamacpp — same /api/ps surface as vllm + talkies. Wrapper enforces only-one
# -model resident internally; this just nudges it to free RAM/VRAM when
# something else needs the hardware. Model IDs must match the wrapper's
# models.{cpu,cuda}.json slugs.
_LLAMACPP_CUDA_URL = "http://llamacpp-cuda:8000"
_LLAMACPP_CPU_URL = "http://llamacpp:8000"
_LLAMACPP_MODELS = [
    "surya-ocr-2",
]


async def _unload_cuda_llamacpp():
    """Unload CUDA llamacpp models to free VRAM."""
    logger.warning("[resource_manager] unloading cuda-llamacpp models")
    await _unload_via_api_ps(
        _LLAMACPP_CUDA_URL, "cuda-llamacpp", _LLAMACPP_MODELS
    )


async def _unload_cpu_llamacpp():
    """Unload CPU llamacpp models to free RAM."""
    logger.warning("[resource_manager] unloading cpu-llamacpp models")
    await _unload_via_api_ps(
        _LLAMACPP_CPU_URL, "cpu-llamacpp", _LLAMACPP_MODELS
    )


# audiolla — POST /v1/unload evicts every loaded engine at once. Same
# contract on CPU and CUDA image. No enumeration needed — audiolla
# handles the walk internally and returns {"unloaded": [<slugs>]}.
_AUDIOLLA_CUDA_URL = "http://audiolla-cuda:8000"
_AUDIOLLA_CPU_URL = "http://audiolla:8000"


def _aigate_bearer_headers() -> dict:
    """Bearer token for services that gate their APIs behind AIGATE_TOKEN
    (audiolla, flickies). Absent env → no header, upstream returns 401
    which we log and move on."""
    tok = os.environ.get("AIGATE_TOKEN", "")
    return {"Authorization": f"Bearer {tok}"} if tok else {}


async def _unload_via_bulk(base_url: str, group: str) -> None:
    """Unload every engine via POST /v1/unload (audiolla contract)."""
    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            r = await client.post(
                f"{base_url}/v1/unload", headers=_aigate_bearer_headers()
            )
            if r.status_code == 200:
                unloaded = r.json().get("unloaded", [])
                if unloaded:
                    logger.warning(
                        "[resource_manager] %s: unloaded %s", group, unloaded
                    )
                else:
                    logger.warning(
                        "[resource_manager] %s: no engines were loaded", group
                    )
            else:
                logger.warning(
                    "[resource_manager] %s: unload status=%s", group, r.status_code
                )
        except Exception as e:
            logger.warning("[resource_manager] %s unload error: %s", group, e)


async def _unload_cuda_audiolla():
    """Evict every engine loaded on audiolla-cuda to free VRAM."""
    logger.warning("[resource_manager] unloading cuda-audiolla engines")
    await _unload_via_bulk(_AUDIOLLA_CUDA_URL, "cuda-audiolla")


async def _unload_cpu_audiolla():
    """Evict every engine loaded on audiolla to free RAM."""
    logger.warning("[resource_manager] unloading cpu-audiolla engines")
    await _unload_via_bulk(_AUDIOLLA_CPU_URL, "cpu-audiolla")


# flickies — no bulk unload endpoint. Enumerate loaded engines via
# GET /v1/engines then DELETE /v1/engines/{slug} for each with
# `loaded: true`. Slugs match the engine catalog: wav2lip, wav2lip-gan,
# latentsync-1.5, gfpgan (as of flickies v0.3.0). When new engines land
# upstream they'll appear automatically since we enumerate live rather
# than hard-code slugs.
_FLICKIES_CUDA_URL = "http://flickies-cuda:8000"
_FLICKIES_CPU_URL = "http://flickies:8000"


async def _unload_via_engines_delete(base_url: str, group: str) -> None:
    """Enumerate GET /v1/engines, DELETE the ones marked loaded."""
    headers = _aigate_bearer_headers()
    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            r = await client.get(f"{base_url}/v1/engines", headers=headers)
            if r.status_code != 200:
                logger.warning(
                    "[resource_manager] %s: list engines status=%s",
                    group,
                    r.status_code,
                )
                return
            engines = r.json().get("engines", [])
            loaded = [e["slug"] for e in engines if e.get("loaded")]
            if not loaded:
                logger.warning(
                    "[resource_manager] %s: no engines were loaded", group
                )
                return

            async def _one(slug: str) -> None:
                try:
                    dr = await client.delete(
                        f"{base_url}/v1/engines/{slug}", headers=headers
                    )
                    if dr.status_code == 200:
                        logger.warning(
                            "[resource_manager] %s: unloaded %s", group, slug
                        )
                    else:
                        logger.warning(
                            "[resource_manager] %s: unload %s status=%s",
                            group,
                            slug,
                            dr.status_code,
                        )
                except Exception as inner:
                    logger.warning(
                        "[resource_manager] %s: unload error for %s: %s",
                        group,
                        slug,
                        inner,
                    )

            await asyncio.gather(
                *(_one(slug) for slug in loaded), return_exceptions=True
            )
        except Exception as e:
            logger.warning("[resource_manager] %s unload error: %s", group, e)


async def _unload_cuda_flickies():
    """Evict every engine loaded on flickies-cuda to free VRAM."""
    logger.warning("[resource_manager] unloading cuda-flickies engines")
    await _unload_via_engines_delete(_FLICKIES_CUDA_URL, "cuda-flickies")


async def _unload_cpu_flickies():
    """Evict every engine loaded on flickies to free RAM."""
    logger.warning("[resource_manager] unloading cpu-flickies engines")
    await _unload_via_engines_delete(_FLICKIES_CPU_URL, "cpu-flickies")


_UNLOAD_FNS = {
    "cuda-llm": _unload_cuda_llm,
    "cuda-img": _unload_cuda_img,
    "cuda-stt-talkies": _unload_cuda_stt_talkies,
    "cuda-vllm": _unload_cuda_vllm,
    "cuda-llamacpp": _unload_cuda_llamacpp,
    "cuda-audiolla": _unload_cuda_audiolla,
    "cuda-flickies": _unload_cuda_flickies,
    "cpu-llm": _unload_cpu_llm,
    "cpu-img": _unload_cpu_img,
    "cpu-stt-talkies": _unload_cpu_stt_talkies,
    "cpu-vllm": _unload_cpu_vllm,
    "cpu-llamacpp": _unload_cpu_llamacpp,
    "cpu-audiolla": _unload_cpu_audiolla,
    "cpu-flickies": _unload_cpu_flickies,
}

# ---------------------------------------------------------------------------
# Hardware semaphores — one CUDA job, one CPU job at a time
# ---------------------------------------------------------------------------

_cuda_sem = asyncio.Semaphore(1)
_cpu_sem = asyncio.Semaphore(1)

_METADATA_KEY = "_resource_manager_holds_sem"

# Contextvar tracks the held-semaphore for the current request task. Survives
# the trip from pre_call_hook → handler → log_success_event, including paths
# where LiteLLM's standard-logging chain dies mid-flight (e.g. trying to
# pydantic-serialize a Response subclass) and never invokes the release hook.
# Both the raw-text response patch AND the standard log_success_event read
# this and use sentinel-clearing so we never double-release.
import contextvars  # noqa: E402

_held_hw: contextvars.ContextVar[Optional[str]] = contextvars.ContextVar(
    "resource_manager_held_hw", default=None
)


def _get_sem(group: str) -> Optional[asyncio.Semaphore]:
    if group in _ALL_CUDA_GROUPS:
        return _cuda_sem
    if group in _ALL_CPU_GROUPS:
        return _cpu_sem
    return None


# ---------------------------------------------------------------------------
# LiteLLM CustomLogger
# ---------------------------------------------------------------------------


class ResourceManager(CustomLogger):
    """
    Enforces single-job-per-hardware via semaphore, then unloads competing
    resource groups before routing. Failures are logged but never block.
    """

    async def async_pre_call_hook(
        self, user_api_key_dict, cache, data, call_type
    ):  # noqa: ARG002
        model: str = data.get("model", "")
        group = _get_group(model)

        logger.warning(
            "[resource_manager] pre_call: model=%s call_type=%s group=%s",
            model,
            call_type,
            group,
        )

        # Inference paths have no business being killed by some 10-minute
        # default. CPU transcriptions can take hours; long-context LLM
        # completions can take many minutes. Override LiteLLM's hardcoded
        # 600s default whenever the client didn't explicitly pass one.
        if data.get("timeout") in (None, 600, 600.0):
            data["timeout"] = 86400

        if group is None:
            return data

        sem = _get_sem(group)
        if sem is not None:
            hw = "CUDA" if group in _ALL_CUDA_GROUPS else "CPU"
            logger.warning(
                "[resource_manager] acquiring %s semaphore for group=%s", hw, group
            )
            await sem.acquire()
            logger.warning(
                "[resource_manager] acquired %s semaphore for group=%s", hw, group
            )
            data.setdefault("metadata", {})[_METADATA_KEY] = hw
            _held_hw.set(hw)

        # From here on the semaphore is HELD. Any exception (including
        # CancelledError on a client disconnect) must release it — LiteLLM's
        # async_log_failure_event is not guaranteed to fire on every cancel
        # path. The contextvar is already set so _release_sem() does the
        # right thing.
        try:
            if group in _ALL_CUDA_GROUPS:
                competing = _ALL_CUDA_GROUPS - {group}
            else:
                competing = _ALL_CPU_GROUPS - {group}

            logger.warning(
                "[resource_manager] group=%s unloading competing: %s", group, competing
            )

            # NOTE: asyncio.gather(..., return_exceptions=True) suppresses
            # exceptions raised INSIDE the child coroutines but NOT a
            # CancelledError delivered to the gather itself (i.e. the outer
            # task is cancelled). That path is covered by the surrounding
            # try/except below.
            results = await asyncio.gather(
                *[_UNLOAD_FNS[g]() for g in competing],
                return_exceptions=True,
            )

            for g, result in zip(competing, results):
                if isinstance(result, Exception):
                    logger.warning(
                        "[resource_manager] unload error group=%s: %s", g, result
                    )

            # For sdcpp (cuda-img / cpu-img), block here until the backend
            # has the requested model loaded. See _preload_sdcpp() docstring
            # for why — without this, LiteLLM's image-gen retry+fallback
            # chain races the model-swap window and the caller gets HTTP 200
            # + empty data instead of a real image. This is the only group
            # where we pre-warm — other groups (talkies/vllm/llamacpp) own
            # their own load lifecycles via lazy spawn + idle TTL and don't
            # need an explicit ack-wait here.
            sdcpp_target = _sdcpp_key_for(model, group)
            if sdcpp_target is not None:
                base_url, model_key = sdcpp_target
                await _preload_sdcpp(base_url, model_key)

            logger.warning("[resource_manager] done for model=%s", model)
            return data
        except BaseException:
            # BaseException — covers asyncio.CancelledError on Python 3.8+
            # where it is no longer an Exception subclass. Release the
            # semaphore via the contextvar path so a cancelled-mid-pre-call
            # request doesn't deadlock the hardware group permanently.
            self._release_sem({})
            raise

    async def async_log_success_event(
        self, kwargs, response_obj, start_time, end_time
    ):  # noqa: ARG002
        self._release_sem(kwargs)

    async def async_log_failure_event(
        self, kwargs, response_obj, start_time, end_time
    ):  # noqa: ARG002
        self._release_sem(kwargs)

    @staticmethod
    def _release_sem(kwargs):
        # Prefer the contextvar (set in pre_call_hook on the same async task)
        # over kwargs.litellm_params.metadata — LiteLLM doesn't always
        # propagate user-set data.metadata into kwargs.litellm_params.metadata,
        # but the contextvar follows the task naturally.
        hw = _held_hw.get()
        if hw is None:
            hw = (kwargs.get("litellm_params") or {}).get("metadata", {}).get(_METADATA_KEY)
        if hw is None:
            return
        sem = _cuda_sem if hw == "CUDA" else _cpu_sem
        # Clear contextvar BEFORE release so a concurrent path can't see the
        # same hw and double-release.
        _held_hw.set(None)
        try:
            sem.release()
            logger.warning("[resource_manager] released %s semaphore", hw)
        except ValueError:
            # Already released (e.g. raw-text path beat us to it). No-op.
            pass


# ---------------------------------------------------------------------------
# LiteLLM transcription patches — make all internal STT services return
# proper OpenAI-shaped responses regardless of requested format.
#
# By default LiteLLM:
#   1. Rewrites response_format=text|json → verbose_json on the REQUEST side
#      ("ensures 'duration' is received - used for cost calculation"). This
#      clobbers the client's choice of `text` vs `json` and can confuse
#      backends that handle each format natively.
#   2. Wraps raw-text RESPONSES (srt/vtt/text) into a JSON envelope
#      `{"text": "<raw body>", "usage": null}` instead of passing them
#      through as the correct Content-Type body the OpenAI HTTP API
#      specifies (text/plain, application/x-subrip, text/vtt).
#
# Both behaviours are wrong for talkies — it implements the full OpenAI
# shape natively. The patches below:
#   - skip request rewrite for `local-talkies-*` so client format passes
#     through to the backend
#   - intercept the response and, when format is text/srt/vtt, return a
#     FastAPI PlainTextResponse with the proper media_type so the client
#     sees raw body bytes instead of a JSON envelope
# ---------------------------------------------------------------------------

# Substring match against the *backend* model name (i.e. after the
# `openai/` prefix is stripped — e.g. `whisper-large-v3`, `canary-180m-flash`,
# `parakeet-tdt-0.6b-v3`). All talkies ASR models match.
_NATIVE_FORMAT_SUBSTRINGS = (
    "parakeet",
    "whisper",
    "canary",
)

_RAW_TEXT_FORMATS = {
    "text": "text/plain; charset=utf-8",
    "srt": "application/x-subrip; charset=utf-8",
    "vtt": "text/vtt; charset=utf-8",
}


def _is_native_format_model(model: str | None) -> bool:
    model_lc = (model or "").lower()
    return any(s in model_lc for s in _NATIVE_FORMAT_SUBSTRINGS)


def _patch_whisper_transformation_request() -> None:
    try:
        from litellm.llms.openai.transcriptions.whisper_transformation import (
            OpenAIWhisperAudioTranscriptionConfig,
        )
        from litellm.llms.base_llm.audio_transcription.transformation import (
            AudioTranscriptionRequestData,
        )
    except Exception as e:  # noqa: BLE001
        logger.warning(
            "[resource_manager] whisper_transformation request-patch skipped (import failed): %s",
            e,
        )
        return

    _orig = OpenAIWhisperAudioTranscriptionConfig.transform_audio_transcription_request

    def _patched(self, model, audio_file, optional_params, litellm_params):
        if _is_native_format_model(model):
            data = {"model": model, "file": audio_file, **optional_params}
            return AudioTranscriptionRequestData(data=data)
        return _orig(self, model, audio_file, optional_params, litellm_params)

    OpenAIWhisperAudioTranscriptionConfig.transform_audio_transcription_request = _patched
    logger.warning(
        "[resource_manager] patched OpenAIWhisperAudioTranscriptionConfig: skip "
        "verbose_json rewrite for models matching %s",
        _NATIVE_FORMAT_SUBSTRINGS,
    )


class _RawTextTranscription:
    """Sentinel that satisfies both LiteLLM's `isinstance(_, TranscriptionResponse)`
    type check and FastAPI's `isinstance(_, Response)` short-circuit.

    LiteLLM's `litellm.main.atranscription` hard-asserts the upstream call
    returns a TranscriptionResponse. FastAPI returns Response subclasses as
    raw HTTP bodies (bypassing JSON serialization). A class that is BOTH
    lets us pass through raw SRT/VTT/text bodies end-to-end without
    rewriting LiteLLM's router or proxy layer.

    Built lazily at first use so the imports happen inside the proxy process.
    """

    _cls = None

    @classmethod
    def make(cls, raw_text: str, media_type: str):
        if cls._cls is None:
            from litellm.types.utils import TranscriptionResponse
            from starlette.responses import PlainTextResponse

            class _Hybrid(PlainTextResponse, TranscriptionResponse):
                def __init__(self, raw_text: str, media_type: str):  # noqa: D401
                    PlainTextResponse.__init__(
                        self, content=raw_text, media_type=media_type
                    )
                    # LiteLLM's success logger pokes at pydantic internals
                    # (__pydantic_extra__, __pydantic_fields_set__, etc.)
                    # when constructing the standard_logging_payload. Without
                    # these, the success-call hook chain blows up with an
                    # AttributeError and never releases the semaphore.
                    object.__setattr__(self, "text", raw_text)
                    object.__setattr__(self, "usage", None)
                    object.__setattr__(self, "_hidden_params", {})
                    object.__setattr__(self, "__pydantic_extra__", {})
                    object.__setattr__(self, "__pydantic_fields_set__", set())
                    object.__setattr__(self, "__pydantic_private__", None)

                def __setattr__(self, name, value):
                    # Bypass pydantic validation (LiteLLM mutates ._hidden_params)
                    object.__setattr__(self, name, value)

            cls._cls = _Hybrid
        return cls._cls(raw_text, media_type)


def _patch_handler_for_raw_text_response() -> None:
    """Make async_audio_transcriptions return a hybrid PlainTextResponse /
    TranscriptionResponse for raw-text formats (text/srt/vtt). The hybrid
    passes LiteLLM's internal isinstance check AND, because it is also a
    starlette Response, gets returned as a raw HTTP body by FastAPI with
    the proper media_type — no JSON wrapping.
    """
    try:
        from litellm.llms.openai.transcriptions.handler import OpenAIAudioTranscription
    except Exception as e:  # noqa: BLE001
        logger.warning(
            "[resource_manager] handler raw-text patch skipped (import failed): %s",
            e,
        )
        return

    _orig_async = OpenAIAudioTranscription.async_audio_transcriptions

    async def _patched_async(self, audio_file, data, model_response, timeout, *args, **kwargs):
        result = await _orig_async(
            self, audio_file, data, model_response, timeout, *args, **kwargs
        )

        fmt = (data.get("response_format") or "").lower()
        media_type = _RAW_TEXT_FORMATS.get(fmt)
        if media_type is None:
            return result

        if not _is_native_format_model(data.get("model")):
            return result

        raw = getattr(result, "text", None)
        if not isinstance(raw, str):
            return result

        # FastAPI returns Response subclasses straight through without
        # invoking LiteLLM's post-call logging hooks reliably (the standard
        # logging payload chokes on non-pydantic responses anyway). Release
        # the semaphore manually via the contextvar; clearing the var first
        # prevents the standard hook from double-releasing if it does fire.
        hw = _held_hw.get()
        if hw is not None:
            _held_hw.set(None)
            sem = _cuda_sem if hw == "CUDA" else _cpu_sem
            try:
                sem.release()
                logger.warning(
                    "[resource_manager] released %s semaphore (raw-text path)", hw
                )
            except ValueError:
                pass
        # Also drop the metadata marker for belt-and-suspenders.
        meta = data.get("metadata") or {}
        meta.pop(_METADATA_KEY, None)

        return _RawTextTranscription.make(raw, media_type)

    OpenAIAudioTranscription.async_audio_transcriptions = _patched_async
    logger.warning(
        "[resource_manager] patched OpenAIAudioTranscription.async_audio_transcriptions: "
        "return hybrid Response/TranscriptionResponse for text/srt/vtt on native-format models"
    )


_patch_whisper_transformation_request()
_patch_handler_for_raw_text_response()


# LiteLLM proxy loads this when config references the module
proxy_handler_instance = ResourceManager()
