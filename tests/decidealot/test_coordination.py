"""Admission ordering and failure proof against the real Redis lock store."""

import asyncio
import os
import unittest
from contextlib import asynccontextmanager

import httpx
import redis.asyncio as aioredis
from coordinator import CoordinatedSupervisor, CoordinationSettings
from decidealot.app import create_app
from decidealot.errors import ProviderUnavailableError
from decidealot.providers import ProviderResponse
from decidealot.settings import Settings
from fastapi.testclient import TestClient
from hardware_lock import HardwareLocks, HardwareLockUnavailable
from pydantic import ValidationError

_hardware = "CUDA"


class Lifecycle:
    def __init__(self):
        self.calls = []
        self.ready = True

    async def start(self):
        self.ready = True

    async def stop(self):
        self.ready = False

    async def unload_all(self):
        return ()

    @asynccontextmanager
    async def acquire(self, provider):
        self.calls.append(provider)
        yield


class ReplyProvider:
    def __init__(self, observer=None):
        self.observer = observer
        self.calls = 0

    async def forward(self, payload, request_id):
        self.calls += 1
        if self.observer is not None:
            await self.observer()
        return ProviderResponse(
            200,
            {
                "model": payload["model"],
                "answers": {"ok": {"type": "noul", "noul": 0.9}},
                "usage": {"input_tokens": 1, "output_tokens": 0},
            },
        )


def request(model):
    return {
        "model": model,
        "state": "synthetic input",
        "questions": {
            "ok": {"type": "noul", "instructions": "The input is synthetic."},
        },
    }


class CoordinationTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.redis = aioredis.Redis(
            host=os.environ["TEST_REDIS_HOST"],
            username="litellm",
            password=os.environ["TEST_LITELLM_REDIS_PASSWORD"],
            decode_responses=True,
        )
        await self.redis.delete(HardwareLocks.key("CUDA"), HardwareLocks.key("CPU"))
        self.locks = HardwareLocks(
            self.redis, ttl_seconds=1, max_hold_seconds=60, poll_seconds=0.01
        )
        self.lifecycle = Lifecycle()
        self.unloads = []

    async def asyncTearDown(self):
        await self.redis.delete(HardwareLocks.key("CUDA"), HardwareLocks.key("CPU"))
        await self.redis.aclose()

    def coordinator(self, device="cuda", handler=None, **settings):
        settings.setdefault("clm_embeddings_url", "http://litellm:4000/v1/embeddings")
        settings.setdefault("clm_embeddings_model", "local-llamacpp-cuda-qwen3-8b")

        async def unload(req):
            self.assertEqual(req.method, "POST")
            self.assertEqual(str(req.url), "http://llamacpp-cuda:8000/unload")
            self.assertIsNotNone(await self.redis.get(HardwareLocks.key("CUDA")))
            self.assertEqual(self.lifecycle.calls, [])
            self.unloads.append(req)
            return httpx.Response(200, json={"unloaded": ["qwen3-8b"]})

        return CoordinatedSupervisor(
            self.lifecycle,
            Settings(clm_enabled=True, **settings).model_copy(
                update={"device": device}
            ),
            CoordinationSettings(),
            self.locks,
            httpx.AsyncClient(transport=httpx.MockTransport(handler or unload)),
        )

    async def test_cuda_evicts_encoder_before_loading_and_holds_lock_through_inference(
        self,
    ):
        coordinator = self.coordinator()
        async with coordinator.acquire("laya"):
            self.assertEqual(self.lifecycle.calls, ["laya"])
            self.assertEqual(len(self.unloads), 1)
            self.assertIsNotNone(await self.redis.get(HardwareLocks.key("CUDA")))
        self.assertIsNone(await self.redis.get(HardwareLocks.key("CUDA")))
        await coordinator.stop()

    async def test_cpu_does_not_unload_cuda_encoder(self):
        coordinator = self.coordinator(device="cpu")
        async with coordinator.acquire("von"):
            self.assertIsNotNone(await self.redis.get(HardwareLocks.key("CPU")))
            self.assertIsNone(await self.redis.get(HardwareLocks.key("CUDA")))
        self.assertEqual(self.unloads, [])
        await coordinator.stop()

    async def test_clm_nested_encoder_lock_has_no_outer_deadlock(self):
        coordinator = self.coordinator()
        async with coordinator.acquire("clm"):
            token = await asyncio.wait_for(self.locks.acquire("CUDA"), 1)
            await self.locks.release("CUDA", token)
        self.assertEqual(self.unloads, [])
        await coordinator.stop()

    async def test_local_swap_waits_out_clm_without_holding_its_encoder_lock(self):
        coordinator = self.coordinator(clm_parallel_with_local_models=True)
        entered = asyncio.Event()

        async def local_request():
            async with coordinator.acquire("laya"):
                entered.set()

        async with coordinator.acquire("clm"):
            task = asyncio.create_task(local_request())
            await asyncio.sleep(0.05)
            self.assertFalse(entered.is_set())
            self.assertEqual(self.unloads, [])
            token = await asyncio.wait_for(self.locks.acquire("CUDA"), 1)
            await self.locks.release("CUDA", token)
        self.lifecycle.calls.clear()
        await asyncio.wait_for(task, 1)
        self.assertTrue(entered.is_set())
        await coordinator.stop()

    async def test_remote_embeddings_do_not_trigger_local_encoder_unload(self):
        coordinator = self.coordinator(
            clm_embeddings_url="https://encoder.example/v1/embeddings"
        )
        async with coordinator.acquire("laya"):
            self.assertEqual(self.unloads, [])
        await coordinator.stop()

    async def test_eviction_failures_never_load_provider_and_release_lock(self):
        cases = [
            httpx.Response(503),
            httpx.Response(409),
            httpx.Response(200, json=None),
            httpx.Response(200, json={}),
            httpx.Response(200, text="bad json"),
        ]
        for response in cases:
            with self.subTest(response=response.status_code, body=response.content):
                coordinator = self.coordinator(handler=lambda _, reply=response: reply)
                with self.assertRaises(ProviderUnavailableError):
                    async with coordinator.acquire("laya"):
                        self.fail("provider must not run")
                self.assertEqual(self.lifecycle.calls, [])
                self.assertIsNone(await self.redis.get(HardwareLocks.key("CUDA")))
                await coordinator.stop()

    async def test_cancellation_releases_lock(self):
        started = asyncio.Event()

        async def unload(req):
            started.set()
            await asyncio.Event().wait()

        coordinator = self.coordinator(handler=unload)

        async def run():
            async with coordinator.acquire("laya"):
                self.fail("cancelled request must not load")

        task = asyncio.create_task(run())
        await started.wait()
        task.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await task
        self.assertIsNone(await self.redis.get(HardwareLocks.key("CUDA")))
        await coordinator.stop()

    async def test_encoder_timeout_fails_before_provider_load(self):
        def timeout(req):
            raise httpx.ReadTimeout("encoder timed out", request=req)

        coordinator = self.coordinator(handler=timeout)
        with self.assertRaises(ProviderUnavailableError):
            async with coordinator.acquire("von"):
                self.fail("provider must not run")
        self.assertEqual(self.lifecycle.calls, [])
        self.assertIsNone(await self.redis.get(HardwareLocks.key("CUDA")))
        await coordinator.stop()

    async def test_inference_failure_releases_lock(self):
        coordinator = self.coordinator()
        with self.assertRaisesRegex(RuntimeError, "inference failed"):
            async with coordinator.acquire("laya"):
                raise RuntimeError("inference failed")
        self.assertIsNone(await self.redis.get(HardwareLocks.key("CUDA")))
        await coordinator.stop()

    async def test_lock_store_failure_never_unloads_or_loads(self):
        class UnavailableLocks:
            async def acquire(self, hardware):
                raise HardwareLockUnavailable("store unavailable")

        coordinator = self.coordinator()
        coordinator._locks = UnavailableLocks()
        with self.assertRaises(ProviderUnavailableError):
            async with coordinator.acquire("laya"):
                self.fail("provider must not run without admission")
        self.assertEqual(self.unloads, [])
        self.assertEqual(self.lifecycle.calls, [])
        await coordinator.stop()

    async def test_held_litellm_lock_blocks_eviction_until_released(self):
        token = await self.locks.acquire("CUDA")
        coordinator = self.coordinator()
        entered = asyncio.Event()

        async def run():
            async with coordinator.acquire("laya"):
                entered.set()

        task = asyncio.create_task(run())
        await asyncio.sleep(0.05)
        self.assertEqual(self.unloads, [])
        self.assertFalse(entered.is_set())
        await self.locks.release("CUDA", token)
        await asyncio.wait_for(task, 1)
        self.assertTrue(entered.is_set())
        await coordinator.stop()


class HTTPContractTest(unittest.TestCase):
    def test_rest_batch_and_auth_reach_injected_admission(self):
        lifecycle = Lifecycle()
        unloads = []

        class Locks:
            async def acquire(self, hardware):
                return "test-token"

            async def release(self, hardware, token):
                return True

        def unload(req):
            unloads.append(req)
            return httpx.Response(200, json={"unloaded": []})

        settings = Settings(
            api_key="operator-secret",
            clm_enabled=True,
            clm_embeddings_url="http://litellm:4000/v1/embeddings",
            clm_embeddings_model="local-llamacpp-cuda-qwen3-8b",
        ).model_copy(update={"device": "cuda"})
        coordinated = CoordinatedSupervisor(
            lifecycle,
            settings,
            CoordinationSettings(),
            Locks(),
            httpx.AsyncClient(transport=httpx.MockTransport(unload)),
        )
        app = create_app(
            settings,
            providers={
                "laya": ReplyProvider(),
                "von": ReplyProvider(),
                "clm": ReplyProvider(),
            },
            supervisor=coordinated,
        )
        with TestClient(app, base_url="http://127.0.0.1:8080") as client:
            self.assertEqual(
                client.post("/v1/systemone", json=request("laya")).status_code, 401
            )
            self.assertEqual(unloads, [])
            headers = {"Authorization": "Bearer operator-secret"}
            response = client.post(
                "/v1/systemone/batch",
                headers=headers,
                json={"requests": [request("clm"), request("laya"), request("von")]},
            )
            self.assertEqual(response.status_code, 200, response.text)
            self.assertEqual(len(response.json()["results"]), 3)
            self.assertEqual(len(unloads), 2)
            self.assertEqual(lifecycle.calls, ["clm", "laya", "von"])

            mcp_headers = {
                **headers,
                "Accept": "application/json, text/event-stream",
                "Content-Type": "application/json",
            }
            initialized = client.post(
                "/mcp",
                headers=mcp_headers,
                json={
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "initialize",
                    "params": {
                        "protocolVersion": "2025-11-25",
                        "capabilities": {},
                        "clientInfo": {"name": "coordination-test", "version": "1"},
                    },
                },
            )
            self.assertEqual(initialized.status_code, 200, initialized.text)
            mcp_headers["Mcp-Session-Id"] = initialized.headers["Mcp-Session-Id"]
            notification = client.post(
                "/mcp",
                headers=mcp_headers,
                json={"jsonrpc": "2.0", "method": "notifications/initialized"},
            )
            self.assertIn(notification.status_code, (200, 202))
            for identifier, model in enumerate(("laya", "clm"), start=2):
                result = client.post(
                    "/mcp",
                    headers=mcp_headers,
                    json={
                        "jsonrpc": "2.0",
                        "id": identifier,
                        "method": "tools/call",
                        "params": {"name": "system_one", "arguments": request(model)},
                    },
                )
                self.assertEqual(result.status_code, 200, result.text)
                self.assertFalse(result.json()["result"]["isError"])
            self.assertEqual(len(unloads), 3)
            self.assertEqual(lifecycle.calls[-2:], ["laya", "clm"])

    def test_config_rejects_invalid_timeout_and_url(self):
        for value in (0, -1, 301, float("inf")):
            with self.subTest(value=value), self.assertRaises(ValidationError):
                CoordinationSettings(unload_timeout_seconds=value)
        with self.assertRaises(ValidationError):
            CoordinationSettings(encoder_url="file:///etc/passwd")
