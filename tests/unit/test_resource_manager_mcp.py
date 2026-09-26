"""Resource manager MCP tests: group mapping and lock lifetime per tool call.

Run through tests/unit/run.sh. The competing-group unloads target service
hostnames that do not exist on the test network, so they fail fast and are
logged, as they would be for a disabled service.
"""

import os
import unittest

import redis.asyncio as aioredis

os.environ.setdefault("RESOURCE_LOCK_REDIS_HOST", os.environ["TEST_REDIS_HOST"])
os.environ.setdefault("RESOURCE_LOCK_REDIS_USERNAME", "litellm")
os.environ.setdefault("RESOURCE_LOCK_REDIS_PASSWORD", os.environ["TEST_LITELLM_REDIS_PASSWORD"])

import hardware_lock  # noqa: E402
import resource_manager as rm  # noqa: E402
from hardware_lock import HardwareLocks  # noqa: E402
from litellm.proxy._experimental.mcp_server.mcp_server_manager import (  # noqa: E402
    MCPServerManager,
)

CUDA_KEY = HardwareLocks.key("CUDA")
CPU_KEY = HardwareLocks.key("CPU")


class ToolFailed(Exception):
    """Raised by the fake MCP tool to simulate a failing tool call."""


async def _is_held(client: aioredis.Redis, key: str) -> bool:
    # GET, not EXISTS: the litellm ACL user may only run the lock's commands.
    return await client.get(key) is not None


class MCPGroupTest(unittest.TestCase):
    def test_inference_tools_map_to_hardware_groups(self) -> None:
        cases = [
            ("decidealot_cuda", "system_one", "cuda-decidealot"),
            ("decidealot", "system_one", "cpu-decidealot"),
            ("predictalot_cuda", "forecast_univariate_chronos_2", "cuda-predictalot"),
            ("predictalot", "forecast_univariate_chronos_2", "cpu-predictalot"),
            ("Decidealot-CUDA", "system_one", "cuda-decidealot"),
        ]
        for server, tool, want in cases:
            with self.subTest(server=server, tool=tool):
                self.assertEqual(rm._mcp_group(server, tool), want)

    def test_admin_and_unknown_calls_skip_the_lock(self) -> None:
        cases = [
            ("decidealot_cuda", "list_models"),
            ("decidealot_cuda", "unload_models"),
            ("predictalot_cuda", "list_univariate_models"),
            ("predictalot_cuda", "get_model_info"),
            ("audiolla_cuda", "transcribe"),
            (None, "system_one"),
            ("", "system_one"),
        ]
        for server, tool in cases:
            with self.subTest(server=server, tool=tool):
                self.assertIsNone(rm._mcp_group(server, tool))


class MCPLockLifetimeTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.inspect = aioredis.Redis(
            host=os.environ["TEST_REDIS_HOST"],
            username="litellm",
            password=os.environ["TEST_LITELLM_REDIS_PASSWORD"],
            decode_responses=True,
        )
        await self.inspect.delete(CUDA_KEY, CPU_KEY)
        self._saved_call_tool = MCPServerManager.call_tool
        self.addCleanup(setattr, MCPServerManager, "call_tool", self._saved_call_tool)
        # Each test runs on its own event loop. The process-wide lock client
        # must be rebuilt on this loop, as one LiteLLM worker would build it.
        hardware_lock._locks = None

    async def asyncTearDown(self) -> None:
        await self.inspect.delete(CUDA_KEY, CPU_KEY)
        await self.inspect.aclose()
        if hardware_lock._locks is not None:
            await hardware_lock._locks._client.aclose()
            hardware_lock._locks = None

    def _install_tool(self, outcome: str) -> list:
        """Replace the real call_tool with one that runs the pre-call hook the
        way LiteLLM does, records which locks were held, then finishes with
        the given outcome. The resource manager patch then wraps it."""
        seen: list = []
        inspect = self.inspect

        async def fake_call_tool(self, server_name, name, *args, **kwargs):
            await rm.proxy_handler_instance.async_pre_call_hook(
                None, None, {rm._MCP_TOOL_NAME_KEY: name}, rm._MCP_CALL_TYPE
            )
            seen.append((await _is_held(inspect, CUDA_KEY), await _is_held(inspect, CPU_KEY)))
            if outcome == "error":
                raise ToolFailed("tool failed")
            return "ok"

        MCPServerManager.call_tool = fake_call_tool
        rm._patch_mcp_call_tool()
        return seen

    async def test_cuda_inference_tool_holds_cuda_lock_until_it_returns(self) -> None:
        seen = self._install_tool("ok")
        result = await MCPServerManager.call_tool(object(), "decidealot_cuda", "system_one", {})
        self.assertEqual(result, "ok")
        self.assertEqual(seen, [(True, False)])
        self.assertFalse(await _is_held(self.inspect, CUDA_KEY))

    async def test_lock_is_released_when_the_tool_fails(self) -> None:
        seen = self._install_tool("error")
        with self.assertRaises(ToolFailed):
            await MCPServerManager.call_tool(object(), "predictalot", "forecast_univariate_chronos_2", {})
        self.assertEqual(seen, [(False, True)])
        self.assertFalse(await _is_held(self.inspect, CPU_KEY))

    async def test_admin_tool_takes_no_lock(self) -> None:
        seen = self._install_tool("ok")
        await MCPServerManager.call_tool(object(), "decidealot_cuda", "unload_models", {})
        self.assertEqual(seen, [(False, False)])


if __name__ == "__main__":
    unittest.main()
