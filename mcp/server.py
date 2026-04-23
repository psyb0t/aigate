#!/usr/bin/env python3
"""aigate MCP server — image generation and TTS via LiteLLM."""

import base64
import json
import os
import re
import sys
import time
import uuid

import httpx

from mcp.server.fastmcp import FastMCP
from mcp.types import TextContent

PREFIX = "[mcp]"

LITELLM_URL = os.environ.get("LITELLM_URL", "http://litellm:4000")
LITELLM_KEY = os.environ.get("LITELLM_MASTER_KEY", "")
HF_TOKEN = os.environ.get("HF_TOKEN", "")
PORT = int(os.environ.get("PORT", "8000"))

HYBRIDS3_URL = os.environ.get("HYBRIDS3_URL", "http://hybrids3:8080")
HYBRIDS3_KEY = os.environ.get("HYBRIDS3_UPLOAD_KEY", "")
HYBRIDS3_BUCKET = os.environ.get("HYBRIDS3_BUCKET", "uploads")
PUBLIC_BASE_URL = os.environ.get("PUBLIC_BASE_URL", "")

HF_INFERENCE_BASE = "https://router.huggingface.co/hf-inference/models"

MIME_TO_EXT = {
    "audio/mpeg": "mp3",
    "audio/wav": "wav",
    "audio/ogg": "ogg",
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
}

IMAGE_PATTERNS = [
    re.compile(r"^hf-flux-"),
    re.compile(r"^hf-sd-"),
    re.compile(r"^openai-dall-e-"),
    re.compile(r"^openai-gpt-image-"),
    re.compile(r"^local-sdcpp-"),
]

IMAGE_DEFAULT_ORDER = [
    "hf-flux-schnell",
    "local-sdcpp-cuda-flux-schnell",
    "local-sdcpp-cpu-sd-turbo",
    "openai-dall-e-3",
]
TTS_DEFAULT_ORDER = [
    "local-speaches-kokoro-tts",
    "local-qwen3-cuda-tts",
    "openai-tts-1",
]


def log(msg):
    print(f"{PREFIX} {msg}", flush=True)


def discover_models(max_retries=30, base_delay=2.0):
    """Query LiteLLM /model/info for image and TTS models.

    Returns (image_models, tts_models) where each is a dict
    mapping display name to litellm model path.
    """
    headers = {"Authorization": f"Bearer {LITELLM_KEY}"}
    for attempt in range(max_retries):
        try:
            resp = httpx.get(
                f"{LITELLM_URL}/model/info",
                headers=headers,
                timeout=10,
            )
            resp.raise_for_status()
            data = resp.json().get("data", [])

            image_models = {}
            tts_models = {}
            for entry in data:
                name = entry.get("model_name", "")
                mode = entry.get("model_info", {}).get("mode", "")
                litellm_model = entry.get("litellm_params", {}).get(
                    "model", ""
                )

                if mode == "image_generation":
                    image_models[name] = litellm_model
                    continue
                if mode == "audio_speech":
                    tts_models[name] = litellm_model
                    continue
                if any(p.match(name) for p in IMAGE_PATTERNS):
                    image_models[name] = litellm_model

            return image_models, tts_models
        except Exception as exc:
            delay = min(base_delay * (2**attempt), 30)
            log(
                f"LiteLLM not ready "
                f"(attempt {attempt + 1}/{max_retries}): "
                f"{exc}, retrying in {delay:.0f}s"
            )
            time.sleep(delay)

    log(
        "WARNING: could not reach LiteLLM after retries, "
        "starting with no models"
    )
    return {}, {}


def pick_default(available, preference):
    for name in preference:
        if name in available:
            return name
    return next(iter(available), None)


def _hf_model_id(litellm_model):
    """Extract 'org/model' from 'huggingface/org/model'."""
    return litellm_model.removeprefix("huggingface/")


async def _upload_to_storage(data_bytes, content_type, prefix):
    """Upload bytes to hybrids3, return public URL or None."""
    if not HYBRIDS3_KEY or not PUBLIC_BASE_URL:
        return None

    ext = MIME_TO_EXT.get(content_type, "bin")
    key = f"mcp/{prefix}/{uuid.uuid4().hex[:12]}.{ext}"

    try:
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.put(
                f"{HYBRIDS3_URL}/storage/" f"{HYBRIDS3_BUCKET}/{key}",
                headers={
                    "Authorization": f"Bearer {HYBRIDS3_KEY}",
                    "Content-Type": content_type,
                },
                content=data_bytes,
            )
            resp.raise_for_status()
    except Exception as exc:
        log(f"WARNING: upload to storage failed: {exc}")
        return None

    return f"{PUBLIC_BASE_URL}/storage/" f"{HYBRIDS3_BUCKET}/{key}"


# ── Model discovery ─────────────────────────────────────────────

image_models, tts_models = discover_models()
image_default = pick_default(image_models, IMAGE_DEFAULT_ORDER)
tts_default = pick_default(tts_models, TTS_DEFAULT_ORDER)

image_names = sorted(image_models.keys())
tts_names = sorted(tts_models.keys())

log(f"Image models: {image_names or '(none)'}")
log(f"TTS models:   {tts_names or '(none)'}")
log(f"Defaults:     image={image_default}, tts={tts_default}")

if not image_models and not tts_models:
    log("ERROR: no image or TTS models available " "— nothing to serve")
    sys.exit(1)


# ── Server ──────────────────────────────────────────────────────

mcp = FastMCP(
    name="aigate-mcp",
    host="0.0.0.0",
    port=PORT,
)


@mcp.custom_route("/health", methods=["GET"])
async def health(_request):
    from starlette.responses import PlainTextResponse  # noqa: E402

    return PlainTextResponse("ok")


def _litellm_headers():
    return {
        "Authorization": f"Bearer {LITELLM_KEY}",
        "Content-Type": "application/json",
    }


async def _generate_hf(model_id, prompt):
    """Call HF Inference API directly — returns raw bytes."""
    url = f"{HF_INFERENCE_BASE}/{model_id}"
    headers = {"Authorization": f"Bearer {HF_TOKEN}"}
    async with httpx.AsyncClient(timeout=1800) as client:
        resp = await client.post(
            url,
            headers=headers,
            json={"inputs": prompt},
        )
        resp.raise_for_status()
    ct = resp.headers.get("content-type", "image/jpeg")
    return resp.content, ct


async def _generate_openai_images(model, prompt, size):
    """Call LiteLLM OpenAI-compatible image gen endpoint.
    Returns list of (bytes, content_type) tuples.
    """
    async with httpx.AsyncClient(timeout=1800) as client:
        resp = await client.post(
            f"{LITELLM_URL}/v1/images/generations",
            headers=_litellm_headers(),
            json={
                "model": model,
                "prompt": prompt,
                "size": size,
                "n": 1,
                "response_format": "b64_json",
            },
        )
        resp.raise_for_status()
        body = resp.json()

    results = []
    for item in body.get("data", []):
        b64 = item.get("b64_json")
        url = item.get("url")

        if b64:
            raw = base64.b64decode(b64)
            results.append((raw, "image/png", None))
        elif url:
            async with httpx.AsyncClient(timeout=60) as cl:
                img_resp = await cl.get(url)
                img_resp.raise_for_status()
                ct = img_resp.headers.get("content-type", "image/png")
                results.append((img_resp.content, ct, None))

        revised = item.get("revised_prompt")
        if revised:
            results.append((None, None, revised))
    return results


# ── Tool: generate_image ────────────────────────────────────────

if image_models:
    _img_models_str = ", ".join(image_names)
    _img_desc = (
        f"Generate an image from a text description. "
        f"Returns JSON with prompt, model, size, and url. "
        f"Present the result to the user in a friendly way: "
        f"show the image as a clickable/inline link, "
        f"mention what was generated and which model was used. "
        f"Available models: {_img_models_str}. "
        f"Default: {image_default}. "
        f"If the user mentions a model but it is not clear "
        f"which one they mean, ask them to clarify."
    )

    @mcp.tool(name="generate_image", description=_img_desc)
    async def generate_image(
        prompt: str,
        model: str = image_default or "",
        size: str = "1024x1024",
    ) -> list[TextContent]:
        if model not in image_models:
            return [
                TextContent(
                    type="text",
                    text=json.dumps({
                        "error": f"unknown model '{model}'",
                        "available_models": image_names,
                    }),
                )
            ]

        litellm_model = image_models[model]

        if litellm_model.startswith("huggingface/"):
            model_id = _hf_model_id(litellm_model)
            img_bytes, ct = await _generate_hf(model_id, prompt)
            url = await _upload_to_storage(img_bytes, ct, "images")
            result = {
                "prompt": prompt,
                "model": model,
                "size": size,
                "url": url,
            }
            return [
                TextContent(type="text", text=json.dumps(result))
            ]

        raw_results = await _generate_openai_images(model, prompt, size)
        if not raw_results:
            return [
                TextContent(
                    type="text",
                    text=json.dumps({"error": "no image data returned"}),
                )
            ]

        urls = []
        revised_prompt = None
        for img_bytes, ct, revised in raw_results:
            if img_bytes:
                url = await _upload_to_storage(img_bytes, ct, "images")
                urls.append(url)
            if revised:
                revised_prompt = revised

        result = {
            "prompt": prompt,
            "model": model,
            "size": size,
            "urls": urls,
        }
        if revised_prompt:
            result["revised_prompt"] = revised_prompt
        return [
            TextContent(type="text", text=json.dumps(result))
        ]

else:
    log("No image models — generate_image tool disabled")


# ── Tool: generate_tts ──────────────────────────────────────────

if tts_models:
    _tts_models_str = ", ".join(tts_names)
    _tts_desc = (
        f"Convert text to speech audio. "
        f"Returns JSON with text, model, voice, speed, and url. "
        f"Present the result to the user in a friendly way: "
        f"show the audio as a clickable/playable link, "
        f"mention the voice and model used. "
        f"Available models: {_tts_models_str}. "
        f"Default: {tts_default}. "
        f"Common voices: alloy, echo, shimmer, nova, "
        f"fable, onyx. "
        f"The local Kokoro model also supports af_heart. "
        f"If the user mentions a model but it is not clear "
        f"which one they mean, ask them to clarify."
    )

    @mcp.tool(name="generate_tts", description=_tts_desc)
    async def generate_tts(
        text: str,
        model: str = tts_default or "",
        voice: str = "alloy",
        speed: float = 1.0,
    ) -> list[TextContent]:
        if model not in tts_models:
            return [
                TextContent(
                    type="text",
                    text=json.dumps({
                        "error": f"unknown model '{model}'",
                        "available_models": tts_names,
                    }),
                )
            ]

        async with httpx.AsyncClient(timeout=1800) as client:
            resp = await client.post(
                f"{LITELLM_URL}/v1/audio/speech",
                headers=_litellm_headers(),
                json={
                    "model": model,
                    "input": text,
                    "voice": voice,
                    "speed": speed,
                },
            )
            resp.raise_for_status()
            audio_bytes = resp.content

        url = await _upload_to_storage(audio_bytes, "audio/mpeg", "tts")

        result = {
            "text": text,
            "model": model,
            "voice": voice,
            "speed": speed,
            "url": url,
        }
        return [
            TextContent(type="text", text=json.dumps(result))
        ]

else:
    log("No TTS models — generate_tts tool disabled")


# ── Main ────────────────────────────────────────────────────────

if __name__ == "__main__":
    mcp.run(transport="streamable-http")
