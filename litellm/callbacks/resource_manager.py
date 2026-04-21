"""
CUDA/CPU resource manager for LiteLLM proxy.

Before each request, unloads competing model groups to free VRAM/RAM.

Groups (CUDA):
  cuda-llm : ollama-cuda-* models
  cuda-tts : local-qwen3-cuda-tts
  cuda-stt : local-speaches-cuda-*

Groups (CPU):
  cpu-llm : ollama-cpu-* models   (unload frees RAM)
  cpu-tts : local-speaches-kokoro-tts
  cpu-stt : local-speaches-whisper-*, local-speaches-parakeet-*

When a request arrives for group X, all competing groups on the same
hardware (CUDA or CPU) are unloaded concurrently before the request proceeds.

Speaches unloading uses DELETE /api/ps/{model_id} which evicts the model
from memory but keeps it on disk — next request auto-reloads it.
"""

import asyncio
import logging
from typing import Optional

import httpx
from litellm.integrations.custom_logger import CustomLogger

logger = logging.getLogger("litellm.proxy")

# ---------------------------------------------------------------------------
# Model → group mapping
# ---------------------------------------------------------------------------

_CUDA_LLM_PREFIX = "ollama-cuda-"
_CPU_LLM_PREFIX = "ollama-cpu-"

_CUDA_TTS = {"local-qwen3-cuda-tts"}
_CUDA_STT = {"local-speaches-cuda-whisper-distil-large-v3", "local-speaches-cuda-parakeet-tdt-0.6b"}

_CPU_TTS = {"local-speaches-kokoro-tts"}
_CPU_STT = {"local-speaches-whisper-distil-large-v3", "local-speaches-parakeet-tdt-0.6b"}

_ALL_CUDA_GROUPS = {"cuda-llm", "cuda-tts", "cuda-stt"}
_ALL_CPU_GROUPS = {"cpu-llm", "cpu-tts", "cpu-stt"}


def _get_group(model: str) -> Optional[str]:
    if model.startswith(_CUDA_LLM_PREFIX):
        return "cuda-llm"
    if model.startswith(_CPU_LLM_PREFIX):
        return "cpu-llm"
    if model in _CUDA_TTS:
        return "cuda-tts"
    if model in _CUDA_STT:
        return "cuda-stt"
    if model in _CPU_TTS:
        return "cpu-tts"
    if model in _CPU_STT:
        return "cpu-stt"
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


async def _unload_cuda_tts():
    """Tell qwen3-cuda-tts to release VRAM."""
    logger.warning("[resource_manager] unloading cuda-tts (qwen3-cuda-tts)")
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            r = await client.post("http://qwen3-cuda-tts:8000/unload")
            logger.warning("[resource_manager] cuda-tts unloaded, status=%s", r.status_code)
        except Exception as e:
            logger.warning("[resource_manager] cuda-tts unload error: %s", e)


_SPEACHES_CUDA_URL = "http://speaches-cuda:8000"
_SPEACHES_CPU_URL = "http://speaches:8000"

# HuggingFace model IDs loaded by each speaches instance
_SPEACHES_CUDA_STT_MODELS = [
    "Systran/faster-distil-whisper-large-v3",
    "istupakov/parakeet-tdt-0.6b-v2-onnx",
]
_SPEACHES_CPU_TTS_MODELS = [
    "speaches-ai/Kokoro-82M-v1.0-ONNX-int8",
]
_SPEACHES_CPU_STT_MODELS = [
    "Systran/faster-distil-whisper-large-v3",
    "istupakov/parakeet-tdt-0.6b-v2-onnx",
]


async def _unload_speaches_models(base_url: str, group: str, model_ids: list) -> None:
    """Unload models from a speaches instance via DELETE /api/ps/{model_id}."""
    async with httpx.AsyncClient(timeout=10.0) as client:
        for model_id in model_ids:
            encoded = model_id.replace("/", "%2F")
            try:
                r = await client.delete(f"{base_url}/api/ps/{encoded}")
                if r.status_code == 200:
                    logger.warning("[resource_manager] %s: unloaded %s", group, model_id)
                elif r.status_code == 404:
                    logger.warning("[resource_manager] %s: %s not loaded, skipping", group, model_id)
                else:
                    logger.warning("[resource_manager] %s: unload %s status=%s", group, model_id, r.status_code)
            except Exception as e:
                logger.warning("[resource_manager] %s: unload error for %s: %s", group, model_id, e)


async def _unload_cuda_stt():
    """Unload CUDA STT models from speaches-cuda to free VRAM."""
    logger.warning("[resource_manager] unloading cuda-stt models")
    await _unload_speaches_models(_SPEACHES_CUDA_URL, "cuda-stt", _SPEACHES_CUDA_STT_MODELS)


async def _unload_cpu_tts():
    """Unload CPU TTS models from speaches to free RAM."""
    logger.warning("[resource_manager] unloading cpu-tts models")
    await _unload_speaches_models(_SPEACHES_CPU_URL, "cpu-tts", _SPEACHES_CPU_TTS_MODELS)


async def _unload_cpu_stt():
    """Unload CPU STT models from speaches to free RAM."""
    logger.warning("[resource_manager] unloading cpu-stt models")
    await _unload_speaches_models(_SPEACHES_CPU_URL, "cpu-stt", _SPEACHES_CPU_STT_MODELS)


_UNLOAD_FNS = {
    "cuda-llm": _unload_cuda_llm,
    "cuda-tts": _unload_cuda_tts,
    "cuda-stt": _unload_cuda_stt,
    "cpu-llm": _unload_cpu_llm,
    "cpu-tts": _unload_cpu_tts,
    "cpu-stt": _unload_cpu_stt,
}


# ---------------------------------------------------------------------------
# LiteLLM CustomLogger
# ---------------------------------------------------------------------------


class ResourceManager(CustomLogger):
    """
    Unloads competing resource groups before routing each request.
    Failures are logged but never block the request.
    """

    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):  # noqa: ARG002
        model: str = data.get("model", "")
        group = _get_group(model)

        logger.warning("[resource_manager] pre_call: model=%s call_type=%s group=%s",
                       model, call_type, group)

        if group is None:
            return data

        if group in _ALL_CUDA_GROUPS:
            competing = _ALL_CUDA_GROUPS - {group}
        else:
            competing = _ALL_CPU_GROUPS - {group}

        logger.warning("[resource_manager] group=%s unloading competing: %s", group, competing)

        results = await asyncio.gather(
            *[_UNLOAD_FNS[g]() for g in competing],
            return_exceptions=True,
        )

        for g, result in zip(competing, results):
            if isinstance(result, Exception):
                logger.warning("[resource_manager] unload error group=%s: %s", g, result)

        logger.warning("[resource_manager] done for model=%s", model)
        return data


# LiteLLM proxy loads this when config references the module
proxy_handler_instance = ResourceManager()
