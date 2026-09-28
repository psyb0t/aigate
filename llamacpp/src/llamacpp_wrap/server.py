"""FastAPI app — OpenAI-compatible chat / completions / embeddings.

Mirrors the vllm-wrap surface so the LiteLLM resource manager can drive every
aigate VRAM-consumer with the same DELETE /api/ps/{model_id} call. Endpoints:

  GET    /healthz                          unauthenticated liveness
  GET    /v1/models                        list configured model_ids
  GET    /api/ps                           list currently loaded model_ids (0 or 1)
  DELETE /api/ps/{model_id}                kill the subprocess if model is loaded
  POST   /unload                           kill the subprocess unconditionally
  POST   /v1/chat/completions              proxied to llama-server (stream-capable)
  POST   /v1/completions                   proxied to llama-server (stream-capable)
  POST   /v1/embeddings                    proxied to llama-server

Only one `llama-server` subprocess is alive at a time — switching models means
killing it and spawning a new one. The supervisor enforces this.
"""

from __future__ import annotations

import asyncio
import json
import logging
from contextlib import asynccontextmanager
from typing import Any
from urllib.parse import unquote

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, Response, StreamingResponse

from . import config
from . import handlers
from ._net import allow_private_fetch, is_blocked_host
from .logging import configure as configure_logging
from .supervisor import Supervisor, SupervisorError


log = logging.getLogger("llamacpp_wrap.server")


REGISTRY = config.load_registry()
SUPERVISOR = Supervisor(REGISTRY)


async def _idle_sweeper() -> None:
    """Kill the subprocess if idle longer than LLAMACPP_WRAP_MODEL_TTL."""
    while True:
        try:
            await asyncio.sleep(config.SWEEPER_INTERVAL_SECONDS)
            ttl = config.MODEL_IDLE_TIMEOUT_SECONDS
            if ttl <= 0:
                continue
            current = SUPERVISOR.loaded()
            if current is None:
                continue
            last = SUPERVISOR.last_used_secs_ago()
            if last is None or last < ttl:
                continue
            log.info(
                "idle sweeper: unloading %s (idle %.1fs >= %.1fs)",
                current,
                last,
                ttl,
            )
            try:
                await SUPERVISOR.unload()
            except Exception:  # noqa: BLE001
                log.exception("idle sweeper: unload failed")
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001
            log.exception("idle sweeper iteration failed")


_sweeper_task: asyncio.Task[None] | None = None


@asynccontextmanager
async def _lifespan(_app: FastAPI):
    log.info(
        "llamacpp starting: device=%s models=%s ttl=%.0fs subprocess_port=%d",
        config.DEVICE or "(auto)",
        list(REGISTRY.keys()),
        config.MODEL_IDLE_TIMEOUT_SECONDS,
        config.SUBPROCESS_PORT,
    )

    if config.PRELOAD:
        if config.PRELOAD in REGISTRY:
            log.info("preload: %s", config.PRELOAD)
            try:
                await SUPERVISOR.ensure(config.PRELOAD)
            except Exception:  # noqa: BLE001
                log.exception("preload %s failed", config.PRELOAD)
        else:
            log.warning("preload: unknown model %s — skipping", config.PRELOAD)

    global _sweeper_task
    _sweeper_task = asyncio.create_task(_idle_sweeper(), name="llamacpp-sweeper")
    try:
        yield
    finally:
        if _sweeper_task is not None:
            _sweeper_task.cancel()
            try:
                await _sweeper_task
            except (asyncio.CancelledError, Exception):
                pass
        try:
            await SUPERVISOR.unload()
        except Exception:  # noqa: BLE001
            log.exception("shutdown unload failed")


app = FastAPI(
    title="llamacpp",
    description=(
        "llama.cpp wrapper — supervises a single `llama-server` subprocess and "
        "proxies OpenAI-compat /v1/chat/completions, /v1/completions, and "
        "/v1/embeddings. Lazy spawn on first request; idle-kill after "
        "LLAMACPP_WRAP_MODEL_TTL. Vision models (mmproj) supported."
    ),
    lifespan=_lifespan,
)


# ── liveness + introspection ──────────────────────────────────────────────


@app.get("/healthz")
def healthz() -> dict[str, Any]:
    return {
        "ok": True,
        "device": config.DEVICE or None,
        "models": list(REGISTRY.keys()),
        "loaded": SUPERVISOR.loaded(),
    }


@app.get("/v1/models")
def list_models() -> dict[str, Any]:
    return {
        "object": "list",
        "data": [
            {"id": mid, "object": "model", "owned_by": "llamacpp"}
            for mid in REGISTRY.keys()
        ],
    }


@app.get("/api/ps")
def list_loaded() -> dict[str, Any]:
    loaded = SUPERVISOR.loaded()
    if loaded is None:
        return {"models": []}
    return {
        "models": [
            {
                "id": loaded,
                "repo": REGISTRY[loaded]["repo"],
                "loaded": True,
                "idle_seconds": SUPERVISOR.last_used_secs_ago(),
            }
        ]
    }


@app.delete("/api/ps/{model_id:path}")
async def unload_one(model_id: str) -> JSONResponse:
    decoded = unquote(model_id)
    if decoded not in REGISTRY:
        return JSONResponse(
            {"detail": f"unknown model {decoded!r}"}, status_code=404
        )
    if SUPERVISOR.loaded() != decoded:
        return JSONResponse({"detail": "not loaded"}, status_code=404)
    await SUPERVISOR.unload()
    return JSONResponse({"unloaded": decoded}, status_code=200)


@app.post("/unload")
async def unload_all() -> dict[str, Any]:
    killed = await SUPERVISOR.unload()
    return {"unloaded": [killed] if killed else []}


# ── proxied OpenAI endpoints ──────────────────────────────────────────────


async def _handle_json_request(
    request: Request,
    *,
    path: str,
    endpoint_name: str,
) -> Response:
    """Common path for chat / completions / embeddings — JSON body w/ `model`."""
    body = await request.body()
    try:
        payload = json.loads(body)
    except (ValueError, TypeError) as exc:
        raise HTTPException(status_code=400, detail=f"invalid JSON: {exc}") from exc

    model_id = payload.get("model")
    if not isinstance(model_id, str) or not model_id:
        raise HTTPException(status_code=400, detail="missing 'model' field")

    entry = REGISTRY.get(model_id)
    if entry is None:
        raise HTTPException(
            status_code=404,
            detail=f"unknown model {model_id!r}; configured: {list(REGISTRY.keys())}",
        )
    if endpoint_name not in entry.get("endpoints", []):
        raise HTTPException(
            status_code=400,
            detail=f"model {model_id!r} does not support /v1/{path.split('/')[-1]}",
        )

    payload = _drop_null_top_level_fields(payload)

    try:
        await SUPERVISOR.ensure(model_id)
    except SupervisorError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    # If this model declares an orchestration handler (in models.{cpu,cuda}
    # .json), give it first crack at the request. The handler can do
    # whatever per-modality routing it wants (PDF rasterization + per-page
    # loop for Surya OCR; future: audio chunking; etc.) and either return
    # a Response (short-circuit) or return None (fall through to the
    # default one-shot proxy).
    handler = handlers.get(entry.get("handler"))
    if handler is not None:
        async def _forward(p: dict) -> Response:
            return await _proxy_one_payload(request, path, p)

        handler_resp = await handler.handle(
            request=request, payload=payload, forward=_forward
        )
        if handler_resp is not None:
            return handler_resp

    # Default path — llama-server's mtmd vision pipeline accepts data:
    # URLs only and does NOT fetch http(s):// URLs from the OpenAI
    # `image_url.url` field. The OpenAI wire spec allows both, so we
    # transparently fetch any http(s)://... URL here and rewrite it to
    # a data: URL before forwarding. Anything else (data:..., empty,
    # malformed) is left untouched.
    _, payload = await _rewrite_image_urls_to_data(payload)
    body = json.dumps(payload).encode("utf-8")

    is_stream = bool(payload.get("stream"))
    return await _do_proxy(
        request,
        path=path,
        body=body,
        content_type="application/json",
        is_stream=is_stream,
    )


async def _proxy_one_payload(
    request: Request,
    path: str,
    payload: dict,
) -> Response:
    """Helper handed to model handlers as the `forward` callable.

    Takes a fully-resolved payload (the handler is responsible for any
    modality-specific pre-processing) and runs the same image-URL
    rewriting + non-streamed proxy that the default path uses, returning
    the raw fastapi Response with the upstream body so the handler can
    parse it.
    """
    _, payload = await _rewrite_image_urls_to_data(payload)
    payload = _drop_null_top_level_fields(payload)
    body = json.dumps(payload).encode("utf-8")
    return await _do_proxy(
        request,
        path=path,
        body=body,
        content_type="application/json",
        is_stream=False,
    )


def _drop_null_top_level_fields(payload: dict[str, Any]) -> dict[str, Any]:
    """Remove optional JSON nulls that current llama-server rejects."""
    return {key: value for key, value in payload.items() if value is not None}


# Upper bound on the size of any single fetched image. Keeps a hostile or
# misconfigured upstream from making the wrapper buffer hundreds of MB.
_IMAGE_FETCH_MAX_BYTES = 32 * 1024 * 1024
_IMAGE_FETCH_TIMEOUT_SECONDS = 30.0


def _ext_to_mime(url: str, content_type: str | None) -> str:
    """Best-effort image MIME. Trust an explicit Content-Type from upstream
    when it's a real image/* type; otherwise fall back to URL extension."""
    if content_type:
        ct = content_type.split(";", 1)[0].strip().lower()
        if ct.startswith("image/"):
            return ct
    lower = url.lower().split("?", 1)[0]
    for ext, mime in (
        (".png", "image/png"),
        (".jpg", "image/jpeg"),
        (".jpeg", "image/jpeg"),
        (".gif", "image/gif"),
        (".webp", "image/webp"),
        (".bmp", "image/bmp"),
    ):
        if lower.endswith(ext):
            return mime
    return "image/png"


async def _fetch_as_data_url(url: str, client: httpx.AsyncClient) -> str:
    """GET `url`, base64-encode the body, return a `data:<mime>;base64,...`
    string. Raises `HTTPException` on fetch errors so the caller's outer
    handler turns into a 4xx/5xx with a readable detail.

    SSRF guard: refuses any URL whose host resolves to a private / loopback /
    link-local / reserved IP range unless
    LLAMACPP_WRAP_ALLOW_PRIVATE_IMAGE_URLS=true is set.
    """
    import base64
    from urllib.parse import urlparse

    if not allow_private_fetch():
        parsed = urlparse(url)
        if parsed.scheme not in ("http", "https"):
            raise HTTPException(
                status_code=400,
                detail=f"image_url scheme {parsed.scheme!r} not allowed",
            )
        host = parsed.hostname or ""
        if not host:
            raise HTTPException(
                status_code=400,
                detail=f"image_url {url!r} has no host",
            )
        blocked, reason = is_blocked_host(host)
        if blocked:
            raise HTTPException(status_code=400, detail=reason)

    try:
        r = await client.get(
            url,
            timeout=_IMAGE_FETCH_TIMEOUT_SECONDS,
            follow_redirects=True,
        )
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=400,
            detail=f"could not fetch image_url {url!r}: {exc}",
        ) from exc
    if r.status_code != 200:
        raise HTTPException(
            status_code=400,
            detail=f"image_url {url!r} returned HTTP {r.status_code}",
        )
    data = r.content
    if len(data) > _IMAGE_FETCH_MAX_BYTES:
        raise HTTPException(
            status_code=413,
            detail=(
                f"image_url {url!r} body is {len(data)} bytes; max is "
                f"{_IMAGE_FETCH_MAX_BYTES}"
            ),
        )
    mime = _ext_to_mime(url, r.headers.get("content-type"))
    return f"data:{mime};base64,{base64.b64encode(data).decode('ascii')}"


async def _rewrite_image_urls_to_data(payload: dict) -> tuple[bool, dict]:
    """Walk an OpenAI chat completions payload, replace any `image_url.url`
    that uses http(s):// with a data: URL containing the fetched bytes.
    Returns (changed, payload). All fetches run concurrently."""
    messages = payload.get("messages")
    if not isinstance(messages, list):
        return False, payload

    # Collect every (parent_dict, key, original_url) pair that needs fetching.
    refs: list[tuple[dict, str, str]] = []
    for msg in messages:
        if not isinstance(msg, dict):
            continue
        content = msg.get("content")
        if not isinstance(content, list):
            continue
        for item in content:
            if not isinstance(item, dict):
                continue
            if item.get("type") != "image_url":
                continue
            iu = item.get("image_url")
            if not isinstance(iu, dict):
                continue
            url = iu.get("url")
            if not isinstance(url, str):
                continue
            if not (url.startswith("http://") or url.startswith("https://")):
                continue
            refs.append((iu, "url", url))

    if not refs:
        return False, payload

    async with httpx.AsyncClient() as client:
        results = await asyncio.gather(
            *(_fetch_as_data_url(url, client) for (_, _, url) in refs),
            return_exceptions=True,
        )

    for (iu, key, original), result in zip(refs, results):
        if isinstance(result, BaseException):
            raise result
        iu[key] = result
    return True, payload


@app.post("/v1/chat/completions")
async def chat_completions(request: Request) -> Response:
    return await _handle_json_request(
        request, path="/v1/chat/completions", endpoint_name="chat"
    )


@app.post("/v1/completions")
async def completions(request: Request) -> Response:
    return await _handle_json_request(
        request, path="/v1/completions", endpoint_name="completions"
    )


@app.post("/v1/embeddings")
async def embeddings(request: Request) -> Response:
    return await _handle_json_request(
        request, path="/v1/embeddings", endpoint_name="embeddings"
    )


async def _do_proxy(
    request: Request,
    *,
    path: str,
    body: bytes,
    content_type: str,
    is_stream: bool,
) -> Response:
    upstream = f"http://127.0.0.1:{config.SUBPROCESS_PORT}{path}"
    headers = {
        k: v
        for k, v in request.headers.items()
        if k.lower() not in ("host", "content-length", "connection")
    }
    headers["content-type"] = content_type

    timeout = httpx.Timeout(config.REQUEST_TIMEOUT_SECONDS, connect=10.0)

    lease = SUPERVISOR.lease()
    lease.__enter__()

    if is_stream:
        client = httpx.AsyncClient(timeout=timeout)
        try:
            upstream_req = client.build_request(
                "POST", upstream, content=body, headers=headers
            )
            upstream_resp = await client.send(upstream_req, stream=True)
        except Exception:
            lease.__exit__(None, None, None)
            await client.aclose()
            raise

        async def _iter():
            try:
                async for chunk in upstream_resp.aiter_raw():
                    yield chunk
            finally:
                await upstream_resp.aclose()
                await client.aclose()
                lease.__exit__(None, None, None)

        return StreamingResponse(
            _iter(),
            status_code=upstream_resp.status_code,
            media_type=upstream_resp.headers.get("content-type"),
        )

    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            r = await client.post(upstream, content=body, headers=headers)
        return Response(
            content=r.content,
            status_code=r.status_code,
            media_type=r.headers.get("content-type"),
        )
    finally:
        lease.__exit__(None, None, None)


def main() -> int:
    configure_logging()
    import uvicorn

    log.info("llamacpp: starting on %s:%d", config.HOST, config.PORT)
    uvicorn.run(app, host=config.HOST, port=config.PORT, log_config=None)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
