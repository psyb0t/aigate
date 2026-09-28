"""Public HTTP contract tests for the llama.cpp OpenAI wrapper."""

from __future__ import annotations

import json
import unittest
from typing import Any
from unittest.mock import AsyncMock

import httpx
from fastapi.responses import JSONResponse

from llamacpp_wrap import server


class _Supervisor:
    async def ensure(self, _model_id: str) -> None:
        return None


class ServerTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self._registry = server.REGISTRY
        self._supervisor = server.SUPERVISOR
        self._proxy = server._do_proxy
        self.forwarded: dict[str, Any] | None = None
        server.REGISTRY = {
            "embedding-test": {
                "repo": "test/embedding",
                "gguf_file": "weights.gguf",
                "endpoints": ["embeddings"],
            }
        }
        server.SUPERVISOR = _Supervisor()

        async def proxy(_request: Any, **kwargs: Any) -> JSONResponse:
            self.forwarded = json.loads(kwargs["body"])
            return JSONResponse({"object": "list", "data": []})

        server._do_proxy = AsyncMock(side_effect=proxy)
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=server.app),
            base_url="http://testserver",
        )

    async def asyncTearDown(self) -> None:
        await self.client.aclose()
        server.REGISTRY = self._registry
        server.SUPERVISOR = self._supervisor
        server._do_proxy = self._proxy

    async def test_embeddings_omits_null_optional_fields_upstream(self) -> None:
        response = await self.client.post(
            "/v1/embeddings",
            json={
                "model": "embedding-test",
                "input": "typed decision input",
                "encoding_format": None,
            },
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            self.forwarded,
            {"model": "embedding-test", "input": "typed decision input"},
        )
