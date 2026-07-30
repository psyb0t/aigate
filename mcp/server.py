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
SEARXNG_URL = os.environ.get("SEARXNG_URL", "")

HYBRIDS3_URL = os.environ.get("HYBRIDS3_URL", "http://hybrids3:8080")
HYBRIDS3_KEY = os.environ.get("HYBRIDS3_UPLOAD_KEY", "")
HYBRIDS3_BUCKET = os.environ.get("HYBRIDS3_BUCKET", "uploads")
PUBLIC_BASE_URL = os.environ.get("PUBLIC_BASE_URL", "")

# piston — sandboxed code execution. In-network base URL skips the
# nginx bearer-auth check (the mcp service is on aigate-internal and
# can hit piston:2000 directly). The aigate-side guard is that the
# /mcp/ endpoint itself is bearer-auth-gated, so an unauthenticated
# caller can't reach this tool to drive piston.
PISTON_URL = os.environ.get("PISTON_URL", "")

# talkies — CPU + CUDA. Used for the merged /v1/audio/voices endpoint
# below: the upstream talkies exposes a voice-listing API that LiteLLM
# does not route (it's not OpenAI-standard). We aggregate whatever's
# enabled and translate each voice's upstream model name into the
# matching LiteLLM alias(es) so a caller can go straight from voice
# pick to /v1/audio/speech without a second lookup.
TALKIES_URL = os.environ.get("TALKIES_URL", "")
TALKIES_CUDA_URL = os.environ.get("TALKIES_CUDA_URL", "")
TALKIES_AUTH_TOKEN = os.environ.get("TALKIES_AUTH_TOKEN", "")
TALKIES_CUDA_AUTH_TOKEN = os.environ.get("TALKIES_CUDA_AUTH_TOKEN", "")

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
    "local-talkies-cuda-kokoro-tts",
    "local-talkies-kokoro-tts",
    "local-talkies-cuda-qwen3-tts",
    "openai-tts-1",
]


def log(msg):
    print(f"{PREFIX} {msg}", flush=True)


def _talkies_headers(is_cuda: bool) -> dict[str, str]:
    token = TALKIES_CUDA_AUTH_TOKEN if is_cuda else TALKIES_AUTH_TOKEN
    return {"Authorization": f"Bearer {token}"} if token else {}


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
log(f"SearXNG:      {SEARXNG_URL or '(disabled)'}")
log(f"piston:       {PISTON_URL or '(disabled)'}")

if not image_models and not tts_models and not SEARXNG_URL and not PISTON_URL:
    log("ERROR: no image/TTS models and no SearXNG and no piston — nothing to serve")
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


# ── Tool: search_web ────────────────────────────────────────────

if SEARXNG_URL:
    @mcp.tool(
        name="search_web",
        description=(
            "Search the web using SearXNG (aggregates Google, Bing, DuckDuckGo, Wikipedia). "
            "Returns a list of results with title, url, and snippet. "
            "Use this to find current information, verify facts, or research topics. "
            "Returns JSON with a 'results' array."
        ),
    )
    async def search_web(
        query: str,
        num_results: int = 10,
    ) -> list[TextContent]:
        # Cap num_results so a callerlike "give me 100000 results" can't
        # explode the response payload or thrash SearXNG. SearXNG itself
        # serves ~10 per page; this slice is over whatever it returned.
        num_results = max(1, min(num_results, 100))
        params = {
            "q": query,
            "format": "json",
            "pageno": "1",
        }
        try:
            async with httpx.AsyncClient(timeout=30) as client:
                resp = await client.get(
                    f"{SEARXNG_URL}/search",
                    params=params,
                )
                resp.raise_for_status()
                data = resp.json()
        except Exception as exc:
            return [
                TextContent(
                    type="text",
                    text=json.dumps({"error": str(exc)}),
                )
            ]

        raw = data.get("results", [])[:num_results]
        results = [
            {
                "title": r.get("title", ""),
                "url": r.get("url", ""),
                "snippet": r.get("content", ""),
                "engine": r.get("engine", ""),
            }
            for r in raw
        ]
        return [
            TextContent(
                type="text",
                text=json.dumps({"query": query, "results": results}),
            )
        ]

else:
    log("SEARXNG_URL not set — search_web tool disabled")


# ── Tool: execute_code ──────────────────────────────────────────

if PISTON_URL:
    # Description is intentionally LLM-prompted — these strings shape
    # how the model decides to invoke the tool. Concrete examples +
    # language list + return-shape doc help a lot.
    # Language list is intentionally NOT hardcoded into the description —
    # the available set depends on PISTON_LANGUAGES at image build time and
    # would otherwise drift the moment an operator adds or removes a runtime.
    # If the model picks an unavailable language, the runtime guard below
    # returns the actual installed list in its error message — that's the
    # source of truth.
    _exec_desc = (
        "Execute code in a sandboxed environment via piston. Use this when "
        "you need to RUN code (compute a result, transform data, verify an "
        "algorithm, parse text, generate a result deterministically) rather "
        "than guess at it. Returns the program's stdout, stderr, exit code, "
        "and runtime metrics. The sandbox has NO network access by default "
        "(outbound HTTP/DNS will fail). Wall-clock and memory are hard-"
        "capped; long-running infinite loops are killed.\n\n"
        "If you don't know which `language` value to pass: try `python` "
        "first — it's installed in every aigate deployment. If the runtime "
        "isn't installed, the error response will include the available "
        "languages list; pick from there. Use a language name (e.g. "
        "`python`, `javascript`, `node`, `go`) — version is resolved "
        "automatically.\n\n"
        "Common pitfalls: (1) the sandbox has no filesystem you can persist "
        "to between calls — each invocation is fresh. (2) `stdin` is "
        "available if you pass it. (3) `print()` / `console.log()` etc. is "
        "how you get output back; the return value of expressions is NOT "
        "captured automatically.\n\n"
        "Returns JSON: {language, version, stdout, stderr, exit_code, "
        "cpu_time_ms, wall_time_ms, memory_bytes, signal?}."
    )

    @mcp.tool(name="execute_code", description=_exec_desc)
    async def execute_code(
        language: str,
        source: str,
        stdin: str = "",
        args: list[str] | None = None,
    ) -> list[TextContent]:
        # Resolve the language version dynamically by hitting
        # /api/v2/runtimes — piston requires both `language` and
        # `version` on the execute call, but the model only needs to
        # know the language name. We pick the latest installed version
        # of the requested language (or alias).
        try:
            async with httpx.AsyncClient(timeout=30) as client:
                rt_resp = await client.get(f"{PISTON_URL}/api/v2/runtimes")
                rt_resp.raise_for_status()
                runtimes = rt_resp.json()
        except Exception as exc:
            return [TextContent(type="text", text=json.dumps({
                "error": f"could not list piston runtimes: {exc}",
            }))]

        lang_lower = language.lower().strip()
        matched = None
        for rt in runtimes:
            if rt.get("language", "").lower() == lang_lower:
                matched = rt
                break
            for alias in rt.get("aliases", []) or []:
                if alias.lower() == lang_lower:
                    matched = rt
                    break
            if matched:
                break

        if matched is None:
            available = sorted({rt["language"] for rt in runtimes})
            return [TextContent(type="text", text=json.dumps({
                "error": (
                    f"language {language!r} is not installed. Available: "
                    f"{available}"
                ),
            }))]

        body = {
            "language": matched["language"],
            "version": matched["version"],
            "files": [{"content": source}],
        }
        if stdin:
            body["stdin"] = stdin
        if args:
            body["args"] = list(args)

        try:
            async with httpx.AsyncClient(timeout=120) as client:
                exec_resp = await client.post(
                    f"{PISTON_URL}/api/v2/execute",
                    json=body,
                )
                exec_resp.raise_for_status()
                payload = exec_resp.json()
        except httpx.HTTPStatusError as exc:
            return [TextContent(type="text", text=json.dumps({
                "error": f"piston HTTP {exc.response.status_code}",
                "body": exc.response.text[:1000],
            }))]
        except Exception as exc:
            return [TextContent(type="text", text=json.dumps({
                "error": f"piston call failed: {exc}",
            }))]

        run = payload.get("run") or {}
        result = {
            "language": payload.get("language", matched["language"]),
            "version": payload.get("version", matched["version"]),
            "stdout": run.get("stdout", ""),
            "stderr": run.get("stderr", ""),
            "exit_code": run.get("code"),
            "signal": run.get("signal"),
            "cpu_time_ms": run.get("cpu_time"),
            "wall_time_ms": run.get("wall_time"),
            "memory_bytes": run.get("memory"),
        }
        compile_block = payload.get("compile")
        if compile_block:
            result["compile_stderr"] = compile_block.get("stderr", "")
            result["compile_exit_code"] = compile_block.get("code")
        return [TextContent(type="text", text=json.dumps(result))]

else:
    log("PISTON_URL not set — execute_code tool disabled")


# ── Custom HTTP route: GET /v1/audio/voices (merged talkies CPU+CUDA) ────────

from starlette.requests import Request as StarletteRequest  # noqa: E402
from starlette.responses import JSONResponse  # noqa: E402

@mcp.custom_route("/v1/audio/voices", methods=["GET"])
async def list_voices(_request: StarletteRequest) -> JSONResponse:
    """Aggregate /v1/audio/voices from talkies CPU + CUDA (whichever is
    configured) and pair each voice with the LiteLLM alias(es) that
    route to its upstream model. Output shape:

      {
        "voices": [
          {
            "voice": "<voice-name>",
            "upstream_model": "<talkies-side model name>",
            "model_aliases": ["<litellm-alias>", ...],
            "default": <bool>
          },
          ...
        ]
      }

    `model_aliases` is sorted; empty if the upstream model has no
    matching LiteLLM alias (shouldn't happen for the shipped config but
    is safe to ignore client-side).
    """
    # 1) Pull voices from each enabled upstream. Skip the ones the
    #    operator hasn't configured. Tolerate per-upstream errors so a
    #    flaky CUDA box doesn't kill the merged list when CPU is fine.
    voices_by_upstream: dict[str, list[dict]] = {}
    errors: list[str] = []
    async with httpx.AsyncClient(timeout=10) as client:
        for label, base, is_cuda in (
            ("cpu", TALKIES_URL, False),
            ("cuda", TALKIES_CUDA_URL, True),
        ):
            if not base:
                continue
            try:
                r = await client.get(
                    f"{base}/v1/audio/voices",
                    headers=_talkies_headers(is_cuda),
                )
                r.raise_for_status()
                for v in r.json().get("voices", []):
                    name = v.get("voice")
                    model = v.get("model")
                    if not name or not model:
                        continue
                    voices_by_upstream.setdefault(model, []).append({
                        "voice": name,
                        "default": bool(v.get("default", False)),
                    })
            except Exception as exc:
                errors.append(f"talkies-{label}: {exc}")

        # 2) Build upstream_model -> [LiteLLM alias] map via /v1/model/info.
        #    Each litellm_params.model is shaped like "openai/qwen3-tts-0.6b";
        #    strip the leading provider tag to recover the upstream name.
        alias_map: dict[str, list[str]] = {}
        try:
            info = await client.get(
                f"{LITELLM_URL}/v1/model/info",
                headers={"Authorization": f"Bearer {LITELLM_KEY}"},
            )
            info.raise_for_status()
            for m in info.json().get("data", []):
                params = m.get("litellm_params") or {}
                upstream = (params.get("model") or "").split("/", 1)[-1]
                alias = m.get("model_name")
                if upstream and alias:
                    alias_map.setdefault(upstream, []).append(alias)
        except Exception as exc:
            errors.append(f"litellm model/info: {exc}")

    # 3) Merge + dedupe per (voice, upstream_model). A voice can appear in
    #    BOTH CPU and CUDA — collapse to one entry; the alias list will
    #    naturally contain both CPU and CUDA aliases.
    seen: set[tuple[str, str]] = set()
    out: list[dict] = []
    for upstream, items in voices_by_upstream.items():
        aliases = sorted(set(alias_map.get(upstream, [])))
        for it in items:
            key = (it["voice"], upstream)
            if key in seen:
                continue
            seen.add(key)
            out.append({
                "voice": it["voice"],
                "upstream_model": upstream,
                "model_aliases": aliases,
                "default": it["default"],
            })

    # Sort: kokoro voices first (the always-on CPU+CUDA family), then
    # qwen3-tts family, then anything else. Within a family, by voice
    # name. Stable + predictable for clients.
    def _sortkey(v: dict) -> tuple:
        m = v["upstream_model"]
        family = (
            0 if m.startswith("kokoro") else
            1 if m.startswith("qwen3-tts") else
            2
        )
        return (family, m, v["voice"])
    out.sort(key=_sortkey)

    payload: dict = {"voices": out}
    if errors:
        payload["errors"] = errors
    return JSONResponse(payload)


# ── Custom HTTP route: POST /v1/audio/speech (full-param passthrough) ────────
#
# LiteLLM's /v1/audio/speech handler (litellm/main.py::speech()) only
# forwards {model, input, voice, response_format, speed, instructions}
# — matching OpenAI's official TTS API. qwen3-tts and other richer
# backends accept additional sampling knobs (temperature, top_k, top_p,
# repetition_penalty, max_new_tokens, do_sample) that LiteLLM silently
# drops from **kwargs before dispatch.
#
# This route intercepts /v1/audio/speech BEFORE LiteLLM (nginx routes
# it here rather than to litellm) and:
#   - for `local-talkies-*` model aliases: resolves the alias to its
#     upstream model name via LiteLLM's /v1/model/info map, picks the
#     right talkies host (CPU vs CUDA), and forwards the ENTIRE request
#     body verbatim so every knob talkies accepts reaches it.
#   - for anything else (openai / groq / etc.): proxies to LiteLLM
#     untouched so the standard fallback chain still applies for cloud
#     TTS routes.

from starlette.responses import Response  # noqa: E402


async def _resolve_talkies_target(
    client: httpx.AsyncClient, alias: str,
) -> tuple[str, str] | None:
    """Look up (upstream_model, base_url) for a local-talkies-* alias.

    Returns None if the alias isn't a local-talkies route (caller
    should fall back to LiteLLM). Uses /v1/model/info to translate
    the alias into its upstream model name — same mechanism as
    list_voices.
    """
    if not alias.startswith("local-talkies-"):
        return None
    is_cuda = alias.startswith("local-talkies-cuda-")
    base = TALKIES_CUDA_URL if is_cuda else TALKIES_URL
    if not base:
        return None
    try:
        info = await client.get(
            f"{LITELLM_URL}/v1/model/info",
            headers={"Authorization": f"Bearer {LITELLM_KEY}"},
        )
        info.raise_for_status()
        for m in info.json().get("data", []):
            if m.get("model_name") != alias:
                continue
            upstream = (
                (m.get("litellm_params") or {}).get("model", "")
                .split("/", 1)[-1]
            )
            if upstream:
                return upstream, base
    except Exception:
        return None
    return None


async def _proxy_response(r: httpx.Response) -> Response:
    """Wrap an httpx response as a Starlette Response preserving body
    bytes + content-type + status."""
    return Response(
        content=r.content,
        status_code=r.status_code,
        media_type=r.headers.get("content-type"),
    )


@mcp.custom_route("/v1/audio/speech", methods=["POST"])
async def speech(request: StarletteRequest) -> Response:
    """Passthrough /v1/audio/speech that forwards every body field to
    the resolved backend.

    - local-talkies-* aliases → direct to talkies (CPU or CUDA),
      alias rewritten to its upstream model name, all body fields
      preserved (temperature, top_k, top_p, repetition_penalty,
      max_new_tokens, do_sample, ...).
    - anything else → proxy to LiteLLM untouched (cloud TTS keeps
      the standard fallback chain).
    """
    try:
        body = await request.json()
    except Exception:
        return JSONResponse(
            {"error": "invalid JSON body"}, status_code=400,
        )

    model = body.get("model", "")
    if not model:
        return JSONResponse(
            {"error": "model is required"}, status_code=400,
        )

    inbound_auth = request.headers.get("authorization", "")
    is_cuda = model.startswith("local-talkies-cuda-")

    async with httpx.AsyncClient(timeout=300) as client:
        target = await _resolve_talkies_target(client, model)
        if target is not None:
            upstream_model, base = target
            body_out = {**body, "model": upstream_model}
            headers = {
                "Content-Type": "application/json",
                **_talkies_headers(is_cuda),
            }
            try:
                r = await client.post(
                    f"{base}/v1/audio/speech",
                    json=body_out,
                    headers=headers,
                )
            except Exception as exc:
                return JSONResponse(
                    {"error": f"talkies unreachable: {exc}"},
                    status_code=502,
                )
            return await _proxy_response(r)

        proxy_headers: dict[str, str] = {
            "Content-Type": "application/json",
            "Authorization": inbound_auth or f"Bearer {LITELLM_KEY}",
        }
        try:
            r = await client.post(
                f"{LITELLM_URL}/v1/audio/speech",
                json=body,
                headers=proxy_headers,
            )
        except Exception as exc:
            return JSONResponse(
                {"error": f"litellm unreachable: {exc}"},
                status_code=502,
            )
        return await _proxy_response(r)


# ── Unload endpoints ────────────────────────────────────────────
#
# POST /v1/unload/cuda + POST /v1/unload/cpu + POST /v1/unload
# fan out to every service on the given hardware class and evict
# whatever's loaded. Same eviction contract as
# litellm/callbacks/resource_manager.py's competing-group unload —
# but exposed as a plain HTTP endpoint so operators / scripts /
# oncall can free VRAM without piggybacking on a fake LLM call.
#
# The endpoint set was added because resource_manager only fires
# from inside LiteLLM's async_pre_call_hook — direct-HTTP services
# (audiolla, flickies) or manual VRAM cleanup after a bad run
# needed a first-class way in.
#
# Auth: gated at the nginx layer via the same bearer as /mcp/.
# Each downstream call carries its own bearer where required
# (audiolla + flickies read AIGATE_TOKEN).

OLLAMA_CUDA_URL = os.environ.get("OLLAMA_CUDA_URL", "http://ollama-cuda:11434")
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://ollama:11434")
SDCPP_CUDA_URL = os.environ.get("SDCPP_CUDA_URL", "http://sdcpp-cuda:7234")
SDCPP_URL = os.environ.get("SDCPP_URL", "http://sdcpp:7234")
VLLM_CUDA_URL = os.environ.get("VLLM_CUDA_URL", "http://vllm-cuda:8000")
VLLM_URL = os.environ.get("VLLM_URL", "http://vllm:8000")
LLAMACPP_CUDA_URL = os.environ.get("LLAMACPP_CUDA_URL", "http://llamacpp-cuda:8000")
LLAMACPP_URL = os.environ.get("LLAMACPP_URL", "http://llamacpp:8000")
AUDIOLLA_CUDA_URL = os.environ.get("AUDIOLLA_CUDA_URL", "http://audiolla-cuda:8000")
AUDIOLLA_URL = os.environ.get("AUDIOLLA_URL", "http://audiolla:8000")
FLICKIES_CUDA_URL = os.environ.get("FLICKIES_CUDA_URL", "http://flickies-cuda:8000")
FLICKIES_URL = os.environ.get("FLICKIES_URL", "http://flickies:8000")
AIGATE_TOKEN = os.environ.get("AIGATE_TOKEN", "")


def _bearer_headers() -> dict:
    return {"Authorization": f"Bearer {AIGATE_TOKEN}"} if AIGATE_TOKEN else {}


async def _unload_ollama(client: httpx.AsyncClient, base: str) -> dict:
    """Ollama: GET /api/ps, POST /api/generate {keep_alive:0} per model."""
    try:
        r = await client.get(f"{base}/api/ps")
        r.raise_for_status()
        models = r.json().get("models", [])
        if not models:
            return {"status": "empty", "unloaded": []}
        unloaded = []
        for m in models:
            name = m["name"]
            await client.post(
                f"{base}/api/generate",
                json={"model": name, "keep_alive": 0, "stream": False},
            )
            unloaded.append(name)
        return {"status": "ok", "unloaded": unloaded}
    except Exception as exc:
        return {"status": "error", "error": str(exc)}


async def _unload_sdcpp(client: httpx.AsyncClient, base: str) -> dict:
    """sd.cpp: POST /sdcpp/v1/unload (single-slot, one-shot)."""
    try:
        r = await client.post(f"{base}/sdcpp/v1/unload")
        return {"status": "ok", "http": r.status_code}
    except Exception as exc:
        return {"status": "error", "error": str(exc)}


async def _unload_api_ps(
    client: httpx.AsyncClient, base: str, headers: dict[str, str] | None = None,
) -> dict:
    """talkies / vllm / llamacpp: GET /api/ps, DELETE /api/ps/{model}."""
    try:
        r = await client.get(f"{base}/api/ps", headers=headers)
        r.raise_for_status()
        models = r.json().get("models", [])
        if not models:
            return {"status": "empty", "unloaded": []}
        unloaded = []
        for m in models:
            mid = m if isinstance(m, str) else m.get("id") or m.get("name")
            if not mid:
                continue
            encoded = mid.replace("/", "%2F")
            await client.delete(f"{base}/api/ps/{encoded}", headers=headers)
            unloaded.append(mid)
        return {"status": "ok", "unloaded": unloaded}
    except Exception as exc:
        return {"status": "error", "error": str(exc)}


async def _unload_talkies_cpu(client: httpx.AsyncClient, base: str) -> dict:
    return await _unload_api_ps(client, base, _talkies_headers(False))


async def _unload_talkies_cuda(client: httpx.AsyncClient, base: str) -> dict:
    return await _unload_api_ps(client, base, _talkies_headers(True))


async def _unload_audiolla(client: httpx.AsyncClient, base: str) -> dict:
    """audiolla: POST /v1/unload evicts every loaded engine."""
    try:
        r = await client.post(f"{base}/v1/unload", headers=_bearer_headers())
        if r.status_code != 200:
            return {"status": "error", "http": r.status_code}
        return {"status": "ok", "unloaded": r.json().get("unloaded", [])}
    except Exception as exc:
        return {"status": "error", "error": str(exc)}


async def _unload_flickies(client: httpx.AsyncClient, base: str) -> dict:
    """flickies: enumerate GET /v1/engines, DELETE loaded ones."""
    try:
        headers = _bearer_headers()
        r = await client.get(f"{base}/v1/engines", headers=headers)
        r.raise_for_status()
        engines = r.json().get("engines", [])
        loaded = [e["slug"] for e in engines if e.get("loaded")]
        if not loaded:
            return {"status": "empty", "unloaded": []}
        unloaded = []
        for slug in loaded:
            dr = await client.delete(
                f"{base}/v1/engines/{slug}", headers=headers,
            )
            if dr.status_code == 200:
                unloaded.append(slug)
        return {"status": "ok", "unloaded": unloaded}
    except Exception as exc:
        return {"status": "error", "error": str(exc)}


# Per-hardware-class fan-out plan. (label, url, unload_fn).
_UNLOAD_PLAN_CUDA = [
    ("ollama-cuda", OLLAMA_CUDA_URL, _unload_ollama),
    ("sdcpp-cuda", SDCPP_CUDA_URL, _unload_sdcpp),
    ("talkies-cuda", TALKIES_CUDA_URL, _unload_talkies_cuda),
    ("vllm-cuda", VLLM_CUDA_URL, _unload_api_ps),
    ("llamacpp-cuda", LLAMACPP_CUDA_URL, _unload_api_ps),
    ("audiolla-cuda", AUDIOLLA_CUDA_URL, _unload_audiolla),
    ("flickies-cuda", FLICKIES_CUDA_URL, _unload_flickies),
]
_UNLOAD_PLAN_CPU = [
    ("ollama", OLLAMA_URL, _unload_ollama),
    ("sdcpp", SDCPP_URL, _unload_sdcpp),
    ("talkies", TALKIES_URL, _unload_talkies_cpu),
    ("vllm", VLLM_URL, _unload_api_ps),
    ("llamacpp", LLAMACPP_URL, _unload_api_ps),
    ("audiolla", AUDIOLLA_URL, _unload_audiolla),
    ("flickies", FLICKIES_URL, _unload_flickies),
]


async def _run_unload_plan(plan: list) -> dict:
    """Fan out concurrent unloads across a plan; return per-service outcome."""
    results: dict = {}
    async with httpx.AsyncClient(timeout=30) as client:
        async def _one(label: str, url: str, fn) -> None:
            if not url:
                results[label] = {"status": "skipped", "reason": "no url"}
                return
            results[label] = await fn(client, url)
        import asyncio as _asyncio
        await _asyncio.gather(
            *(_one(label, url, fn) for label, url, fn in plan),
            return_exceptions=True,
        )
    return results


@mcp.custom_route("/v1/unload/cuda", methods=["POST"])
async def unload_cuda(_request: StarletteRequest) -> JSONResponse:
    """Evict every model / engine loaded on any CUDA service.

    Fans out concurrently to ollama-cuda, sdcpp-cuda, talkies-cuda,
    vllm-cuda, llamacpp-cuda, audiolla-cuda, flickies-cuda. Returns
    a per-service outcome map. Services with an empty URL env are
    skipped. Per-service errors do not fail the whole call.
    """
    return JSONResponse({"class": "cuda",
                         "results": await _run_unload_plan(_UNLOAD_PLAN_CUDA)})


@mcp.custom_route("/v1/unload/cpu", methods=["POST"])
async def unload_cpu(_request: StarletteRequest) -> JSONResponse:
    """CPU counterpart of /v1/unload/cuda — same fan-out shape."""
    return JSONResponse({"class": "cpu",
                         "results": await _run_unload_plan(_UNLOAD_PLAN_CPU)})


@mcp.custom_route("/v1/unload", methods=["POST"])
async def unload_all(_request: StarletteRequest) -> JSONResponse:
    """Convenience — evict both CPU and CUDA in one call."""
    cuda = await _run_unload_plan(_UNLOAD_PLAN_CUDA)
    cpu = await _run_unload_plan(_UNLOAD_PLAN_CPU)
    return JSONResponse({"cuda": cuda, "cpu": cpu})


# ── Main ────────────────────────────────────────────────────────

if __name__ == "__main__":
    mcp.run(transport="streamable-http")
