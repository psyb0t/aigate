"""The zero-TTL workaround uses LiteLLM's real management-cache implementation."""

import unittest

import yaml
from litellm.proxy.common_utils.user_api_key_cache import (
    UserApiKeyCache,
    get_management_object_ttl,
)


class AuthCacheTTLTest(unittest.IsolatedAsyncioTestCase):
    async def test_virtual_key_object_is_not_retained_between_requests(self):
        with open("/gateway-config.yaml", encoding="utf-8") as source:
            ttl = yaml.safe_load(source)["general_settings"]["user_api_key_cache_ttl"]
        self.assertEqual(ttl, 0)
        cache = UserApiKeyCache()
        cache.update_cache_ttl(default_in_memory_ttl=ttl, default_redis_ttl=ttl)
        key = "a" * 64
        await cache.async_set_cache(
            key=key,
            value={"models": ["test-model"]},
            ttl=get_management_object_ttl(cache),
        )
        self.assertIsNone(await cache.async_get_cache(key=key))
