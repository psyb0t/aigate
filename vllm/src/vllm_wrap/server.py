"""FastAPI app — OpenAI-compatible chat/completions/embeddings.

Endpoints (mirror the speaches / talkies surface so the LiteLLM resource
manager can drive every aigate VRAM consumer with the same
DELETE /api/ps/{model_id} call):

  GET    /healthz                          unauthenticated liveness
  GET    /v1/models                        list configured model_ids
  GET    /api/ps                           list currently loaded model_ids (0 or 1)
  DELETE /api/ps/{model_id}                kill the subprocess if model is loaded
  POST   /unload                           kill the subprocess unconditionally
  POST   /v1/chat/completions              proxied to vllm serve (stream-capable)
  POST   /v1/completions                   proxied to vllm serve (stream-capable)
  POST   /v1/embeddings                    proxied to vllm serve

Only one `vllm serve` subprocess is alive at a time — vLLM holds the whole
model in VRAM and switching means restart. The supervisor enforces this.
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
from .logging import configure as configure_logging
from .supervisor import Supervisor, SupervisorError


log = logging.getLogger("vllm_wrap.server")


REGISTRY = config.load_registry()
SUPERVISOR = Supervisor(REGISTRY)


async def _idle_sweeper() -> None:
    """Kill the subprocess if idle longer than VLLM_WRAP_MODEL_TTL."""
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
        "vllm starting: models=%s ttl=%.0fs subprocess_port=%d",
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
    _sweeper_task = asyncio.create_task(_idle_sweeper(), name="vllm-sweeper")
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
    title="vllm",
    description=(
        "vLLM wrapper — supervises a single `vllm serve` subprocess and proxies "
        "OpenAI-compat /v1/chat/completions, /v1/completions, and /v1/embeddings. "
        "Lazy spawn on first request; idle-kill after VLLM_WRAP_MODEL_TTL."
    ),
    lifespan=_lifespan,
)


# ── liveness + introspection ──────────────────────────────────────────────


@app.get("/healthz")
def healthz() -> dict[str, Any]:
    return {
        "ok": True,
        "models": list(REGISTRY.keys()),
        "loaded": SUPERVISOR.loaded(),
    }


@app.get("/v1/models")
def list_models() -> dict[str, Any]:
    return {
        "object": "list",
        "data": [
            {"id": mid, "object": "model", "owned_by": "vllm"}
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
    """Common path for chat/completions/embeddings — JSON body with `model` field."""
    body = await request.body()
    try:
        payload = json.loads(body)
    except (ValueError, TypeError) as exc:
        raise HTTPException(status_code=400, detail=f"invalid JSON: {exc}") from exc
    if not isinstance(payload, dict):
        raise HTTPException(status_code=400, detail="JSON body must be an object")

    # OpenAI clients send unset optional fields as null (LiteLLM sends
    # "encoding_format": null). vLLM validates those fields as literals and
    # rejects null, so unset fields are dropped before forwarding.
    payload = {key: value for key, value in payload.items() if value is not None}
    body = json.dumps(payload).encode()

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

    try:
        await SUPERVISOR.ensure(model_id)
    except SupervisorError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    is_stream = bool(payload.get("stream"))
    return await _do_proxy(
        request,
        path=path,
        body=body,
        content_type="application/json",
        is_stream=is_stream,
    )


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

    log.info("vllm: starting on %s:%d", config.HOST, config.PORT)
    uvicorn.run(app, host=config.HOST, port=config.PORT, log_config=None)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
