"""Redis-backed hardware locks shared by every LiteLLM worker process.

LiteLLM runs several worker processes (``--num_workers``). An
``asyncio.Semaphore`` only serializes requests inside one process, so the
resource manager uses one Redis lock per hardware class instead: at most one
CUDA job and one CPU job run across all workers.

A lock is a single key set with ``SET NX PX``. The holder stores a random token
in it, refreshes the expiry while it holds the lock, and deletes it only when
the stored token is still its own. A worker that crashes stops refreshing, so
its lock expires after ``RESOURCE_LOCK_TTL_SECONDS`` instead of blocking the
hardware forever. A holder that never releases (a missed hook) stops refreshing
after ``RESOURCE_LOCK_MAX_HOLD_SECONDS``.

Without Redis the lock cannot be taken and the caller gets an error. Running
the request unlocked would put two models on one GPU.
"""

import asyncio
import logging
import os
import secrets
import time
from typing import Optional

import redis.asyncio as aioredis

logger = logging.getLogger("litellm.proxy")

REDIS_HOST_ENV = "RESOURCE_LOCK_REDIS_HOST"
REDIS_PORT_ENV = "RESOURCE_LOCK_REDIS_PORT"
REDIS_DB_ENV = "RESOURCE_LOCK_REDIS_DB"
REDIS_USERNAME_ENV = "RESOURCE_LOCK_REDIS_USERNAME"
REDIS_PASSWORD_ENV = "RESOURCE_LOCK_REDIS_PASSWORD"
TTL_SECONDS_ENV = "RESOURCE_LOCK_TTL_SECONDS"
MAX_HOLD_SECONDS_ENV = "RESOURCE_LOCK_MAX_HOLD_SECONDS"
POLL_SECONDS_ENV = "RESOURCE_LOCK_POLL_SECONDS"

KEY_PREFIX = "aigate:hwlock:"
DEFAULT_REDIS_HOST = "redis"
DEFAULT_REDIS_PORT = 6379
DEFAULT_REDIS_DB = 0
DEFAULT_TTL_SECONDS = 60.0
DEFAULT_MAX_HOLD_SECONDS = 86400.0
DEFAULT_POLL_SECONDS = 0.2
_REFRESH_FRACTION = 3
_TOKEN_BYTES = 16

# Delete the key only while it still holds this caller's token.
_RELEASE_SCRIPT = """
if redis.call("GET", KEYS[1]) == ARGV[1] then
    return redis.call("DEL", KEYS[1])
end
return 0
"""

# Extend the expiry only while the key still holds this caller's token.
_REFRESH_SCRIPT = """
if redis.call("GET", KEYS[1]) == ARGV[1] then
    return redis.call("PEXPIRE", KEYS[1], ARGV[2])
end
return 0
"""


class HardwareLockUnavailable(RuntimeError):
    """The lock store rejected the request or cannot be reached."""


def _positive_float_env(name: str, default: float) -> float:
    raw = os.environ.get(name, "")
    if not raw:
        return default
    try:
        value = float(raw)
    except ValueError:
        logger.warning(
            "[hardware_lock] invalid number, using default",
            extra={"env": name, "value": raw, "default": default, "reason": "not_a_number"},
        )
        return default
    if value <= 0:
        logger.warning(
            "[hardware_lock] non-positive number, using default",
            extra={"env": name, "value": raw, "default": default, "reason": "not_positive"},
        )
        return default
    return value


class HardwareLocks:
    """Named Redis locks with token ownership, refresh, and a hold ceiling."""

    def __init__(
        self,
        client: aioredis.Redis,
        ttl_seconds: float,
        max_hold_seconds: float,
        poll_seconds: float,
    ) -> None:
        self._client = client
        self._ttl_ms = int(ttl_seconds * 1000)
        self._refresh_seconds = ttl_seconds / _REFRESH_FRACTION
        self._max_hold_seconds = max_hold_seconds
        self._poll_seconds = poll_seconds
        self._release_script = client.register_script(_RELEASE_SCRIPT)
        self._refresh_script = client.register_script(_REFRESH_SCRIPT)
        self._refreshers: dict[str, asyncio.Task] = {}

    @staticmethod
    def key(name: str) -> str:
        return f"{KEY_PREFIX}{name}"

    async def acquire(self, name: str) -> str:
        """Wait until the named lock is free, take it, and return its token.

        Raises HardwareLockUnavailable when Redis rejects or drops the request.
        """
        key = self.key(name)
        token = secrets.token_hex(_TOKEN_BYTES)
        while True:
            try:
                is_taken = await self._client.set(key, token, nx=True, px=self._ttl_ms)
            except aioredis.RedisError as e:
                raise HardwareLockUnavailable(f"take lock {key}") from e
            if is_taken:
                break
            await asyncio.sleep(self._poll_seconds)
        self._refreshers[token] = asyncio.create_task(self._refresh(key, token))
        return token

    async def release(self, name: str, token: str) -> bool:
        """Release the named lock if this token still holds it.

        Returns False when the lock had already expired or passed to another
        holder, or when Redis could not be reached. In that last case the key
        still expires on its own, because refreshing has stopped.
        """
        refresher = self._refreshers.pop(token, None)
        if refresher is not None:
            refresher.cancel()
        key = self.key(name)
        try:
            deleted = await self._release_script(keys=[key], args=[token])
        except aioredis.RedisError as e:
            logger.warning(
                "[hardware_lock] release failed, lock will expire on its own",
                extra={"lock": key, "error": str(e), "reason": "redis_error"},
            )
            return False
        if not deleted:
            # Normal when a second release hook runs for the same request. A
            # lock lost mid-hold is logged as an error by the refresher.
            logger.debug(
                "[hardware_lock] lock was not held at release",
                extra={"lock": key, "reason": "already_released"},
            )
        return bool(deleted)

    async def _refresh(self, key: str, token: str) -> None:
        deadline = time.monotonic() + self._max_hold_seconds
        while True:
            await asyncio.sleep(self._refresh_seconds)
            if time.monotonic() >= deadline:
                logger.error(
                    "[hardware_lock] hold ceiling reached, letting the lock expire",
                    extra={"lock": key, "reason": "max_hold_exceeded"},
                )
                return
            try:
                is_kept = await self._refresh_script(keys=[key], args=[token, self._ttl_ms])
            except aioredis.RedisError as e:
                logger.warning(
                    "[hardware_lock] refresh failed, retrying",
                    extra={"lock": key, "error": str(e), "reason": "redis_error"},
                )
                continue
            if not is_kept:
                logger.error(
                    "[hardware_lock] lock lost while held",
                    extra={"lock": key, "reason": "expired_or_taken"},
                )
                return


_locks: Optional[HardwareLocks] = None


def _int_env(name: str, default: int) -> int:
    raw = os.environ.get(name, "")
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        logger.warning(
            "[hardware_lock] invalid integer, using default",
            extra={"env": name, "value": raw, "default": default, "reason": "not_an_integer"},
        )
        return default


def get_locks() -> HardwareLocks:
    """Return this process's lock client, built from the environment.

    Connection settings are separate variables rather than a URL, so a password
    with URL-reserved characters needs no escaping.
    """
    global _locks
    if _locks is not None:
        return _locks
    client = aioredis.Redis(
        host=os.environ.get(REDIS_HOST_ENV) or DEFAULT_REDIS_HOST,
        port=_int_env(REDIS_PORT_ENV, DEFAULT_REDIS_PORT),
        db=_int_env(REDIS_DB_ENV, DEFAULT_REDIS_DB),
        username=os.environ.get(REDIS_USERNAME_ENV) or None,
        password=os.environ.get(REDIS_PASSWORD_ENV) or None,
        decode_responses=True,
    )
    _locks = HardwareLocks(
        client,
        ttl_seconds=_positive_float_env(TTL_SECONDS_ENV, DEFAULT_TTL_SECONDS),
        max_hold_seconds=_positive_float_env(MAX_HOLD_SECONDS_ENV, DEFAULT_MAX_HOLD_SECONDS),
        poll_seconds=_positive_float_env(POLL_SECONDS_ENV, DEFAULT_POLL_SECONDS),
    )
    return _locks
