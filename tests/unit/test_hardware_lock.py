"""Hardware lock tests against a real Redis started with aigate's ACL.

Run through tests/unit/run.sh, which starts the throwaway Redis and runs this
suite inside the LiteLLM image with the production callbacks mounted.
"""

import asyncio
import os
import signal
import subprocess
import sys
import time
import unittest

import redis
import redis.asyncio as aioredis

from hardware_lock import HardwareLocks, HardwareLockUnavailable

REDIS_HOST = os.environ["TEST_REDIS_HOST"]
REDIS_PORT = int(os.environ.get("TEST_REDIS_PORT", "6379"))
LITELLM_PASSWORD = os.environ["TEST_LITELLM_REDIS_PASSWORD"]
PROXQ_PASSWORD = os.environ["TEST_PROXQ_REDIS_PASSWORD"]

LOCK = "CUDA"
OTHER_LOCK = "CPU"
SHORT_TTL = 0.6
POLL = 0.05
WAIT_TIMEOUT = 5.0

# Holds the lock from a separate process until killed. It stands in for a
# second LiteLLM worker.
_HOLDER_SCRIPT = """
import asyncio, os, sys
import redis.asyncio as aioredis
from hardware_lock import HardwareLocks

async def main():
    client = aioredis.Redis(
        host=os.environ["TEST_REDIS_HOST"],
        port=int(os.environ.get("TEST_REDIS_PORT", "6379")),
        username="litellm",
        password=os.environ["TEST_LITELLM_REDIS_PASSWORD"],
        decode_responses=True,
    )
    locks = HardwareLocks(client, ttl_seconds=float(sys.argv[2]), max_hold_seconds=3600, poll_seconds=0.05)
    await locks.acquire(sys.argv[1])
    print("held", flush=True)
    await asyncio.sleep(3600)

asyncio.run(main())
"""


def _client(username: str, password: str) -> aioredis.Redis:
    return aioredis.Redis(
        host=REDIS_HOST,
        port=REDIS_PORT,
        username=username,
        password=password,
        decode_responses=True,
    )


class HardwareLockTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self._clients: list[aioredis.Redis] = []
        self.inspect = _client("litellm", LITELLM_PASSWORD)
        await self.inspect.delete(HardwareLocks.key(LOCK), HardwareLocks.key(OTHER_LOCK))

    async def asyncTearDown(self) -> None:
        await self.inspect.delete(HardwareLocks.key(LOCK), HardwareLocks.key(OTHER_LOCK))
        await self.inspect.aclose()
        for client in self._clients:
            await client.aclose()

    def _locks(self, ttl: float = SHORT_TTL, max_hold: float = 3600.0) -> HardwareLocks:
        client = _client("litellm", LITELLM_PASSWORD)
        self._clients.append(client)
        return HardwareLocks(
            client,
            ttl_seconds=ttl,
            max_hold_seconds=max_hold,
            poll_seconds=POLL,
        )

    async def test_acquire_and_release(self) -> None:
        locks = self._locks()
        token = await locks.acquire(LOCK)
        self.assertEqual(await self.inspect.get(HardwareLocks.key(LOCK)), token)
        self.assertTrue(await locks.release(LOCK, token))
        self.assertIsNone(await self.inspect.get(HardwareLocks.key(LOCK)))

    async def test_second_holder_waits_for_release(self) -> None:
        first, second = self._locks(), self._locks()
        token = await first.acquire(LOCK)
        waiter = asyncio.create_task(second.acquire(LOCK))
        await asyncio.sleep(SHORT_TTL * 2)
        self.assertFalse(waiter.done(), "second holder took a held lock")
        await first.release(LOCK, token)
        second_token = await asyncio.wait_for(waiter, WAIT_TIMEOUT)
        await second.release(LOCK, second_token)

    async def test_cuda_and_cpu_locks_are_independent(self) -> None:
        locks = self._locks()
        cuda = await locks.acquire(LOCK)
        cpu = await asyncio.wait_for(locks.acquire(OTHER_LOCK), WAIT_TIMEOUT)
        await locks.release(LOCK, cuda)
        await locks.release(OTHER_LOCK, cpu)

    async def test_refresh_keeps_lock_past_ttl(self) -> None:
        locks = self._locks()
        token = await locks.acquire(LOCK)
        await asyncio.sleep(SHORT_TTL * 4)
        self.assertEqual(await self.inspect.get(HardwareLocks.key(LOCK)), token)
        await locks.release(LOCK, token)

    async def test_release_with_stale_token_keeps_new_holder(self) -> None:
        locks = self._locks()
        await self.inspect.set(HardwareLocks.key(LOCK), "someone-else", px=60000)
        self.assertFalse(await locks.release(LOCK, "stale-token"))
        self.assertEqual(await self.inspect.get(HardwareLocks.key(LOCK)), "someone-else")

    async def test_hold_ceiling_lets_leaked_lock_expire(self) -> None:
        locks = self._locks(ttl=SHORT_TTL, max_hold=SHORT_TTL)
        await locks.acquire(LOCK)
        await asyncio.sleep(SHORT_TTL * 4)
        self.assertIsNone(await self.inspect.get(HardwareLocks.key(LOCK)))

    async def test_other_process_holds_until_killed_then_lock_expires(self) -> None:
        holder = subprocess.Popen(
            [sys.executable, "-c", _HOLDER_SCRIPT, LOCK, str(SHORT_TTL)],
            stdout=subprocess.PIPE,
            text=True,
        )
        try:
            self.assertEqual(holder.stdout.readline().strip(), "held")
            locks = self._locks()
            waiter = asyncio.create_task(locks.acquire(LOCK))
            await asyncio.sleep(SHORT_TTL * 3)
            self.assertFalse(waiter.done(), "lock held by another process was taken")

            started = time.monotonic()
            holder.send_signal(signal.SIGKILL)
            token = await asyncio.wait_for(waiter, WAIT_TIMEOUT)
            self.assertLess(time.monotonic() - started, SHORT_TTL * 4)
            await locks.release(LOCK, token)
        finally:
            holder.kill()
            holder.wait()
            holder.stdout.close()

    async def test_unreachable_redis_raises(self) -> None:
        client = aioredis.Redis(host=REDIS_HOST, port=1, socket_connect_timeout=1)
        self._clients.append(client)
        locks = HardwareLocks(
            client,
            ttl_seconds=SHORT_TTL,
            max_hold_seconds=3600,
            poll_seconds=POLL,
        )
        with self.assertRaises(HardwareLockUnavailable):
            await locks.acquire(LOCK)

    async def test_wrong_password_raises(self) -> None:
        client = _client("litellm", "wrong-password")
        self._clients.append(client)
        locks = HardwareLocks(
            client,
            ttl_seconds=SHORT_TTL,
            max_hold_seconds=3600,
            poll_seconds=POLL,
        )
        with self.assertRaises(HardwareLockUnavailable):
            await locks.acquire(LOCK)


class RedisACLTest(unittest.TestCase):
    def _sync(self, username: str, password: str) -> redis.Redis:
        client = redis.Redis(
            host=REDIS_HOST,
            port=REDIS_PORT,
            username=username,
            password=password,
            decode_responses=True,
        )
        self.addCleanup(client.close)
        return client

    def test_default_user_is_disabled(self) -> None:
        client = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, password=PROXQ_PASSWORD)
        self.addCleanup(client.close)
        with self.assertRaises(redis.AuthenticationError):
            client.ping()

    def test_litellm_user_stays_on_lock_keys(self) -> None:
        client = self._sync("litellm", LITELLM_PASSWORD)
        self.assertTrue(client.set(HardwareLocks.key("acl-check"), "1", px=1000))
        with self.assertRaises(redis.exceptions.NoPermissionError):
            client.set("asynq:acl-check", "1")
        with self.assertRaises(redis.exceptions.NoPermissionError):
            client.flushall()

    def test_proxq_user_stays_on_queue_keys(self) -> None:
        client = self._sync("proxq", PROXQ_PASSWORD)
        self.assertTrue(client.set("asynq:acl-check", "1", px=1000))
        self.assertTrue(client.set("proxq:acl-check", "1", px=1000))
        with self.assertRaises(redis.exceptions.NoPermissionError):
            client.get(HardwareLocks.key(LOCK))
        with self.assertRaises(redis.exceptions.NoPermissionError):
            client.flushall()


if __name__ == "__main__":
    unittest.main()
