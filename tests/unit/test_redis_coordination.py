"""Redis coordination uses production ACLs and separate publisher/subscriber clients."""

import os
import unittest

import redis

CHANNELS = (
    "aigate:cache:litellm_proxy.auth_cache_invalidation",
    "aigate:cache:litellm_proxy.config_change",
)


class RedisCoordinationTest(unittest.TestCase):
    def setUp(self):
        self.client = redis.Redis(
            host=os.environ["TEST_REDIS_HOST"],
            username="litellm",
            password=os.environ["TEST_LITELLM_REDIS_PASSWORD"],
            decode_responses=True,
        )
        self.addCleanup(self.client.close)

    def test_coordination_reaches_other_worker(self):
        for channel in CHANNELS:
            with self.subTest(channel=channel), self.client.pubsub() as subscriber:
                subscriber.subscribe(channel)
                self.assertEqual(subscriber.get_message(timeout=3)["type"], "subscribe")
                self.assertEqual(self.client.publish(channel, "invalidate-test-key"), 1)
                message = subscriber.get_message(timeout=3)
                self.assertEqual(message["data"], "invalidate-test-key")
                subscriber.unsubscribe(channel)
                self.assertEqual(
                    subscriber.get_message(timeout=3)["type"], "unsubscribe"
                )

    def test_unrelated_channels_remain_denied(self):
        for channel in ("asynq:notifications", "unrelated", "aigate:cache:other"):
            with self.subTest(channel=channel):
                with self.assertRaises(redis.exceptions.NoPermissionError):
                    self.client.publish(channel, "test")
                with self.client.pubsub() as subscriber:
                    subscriber.subscribe(channel)
                    with self.assertRaises(redis.exceptions.NoPermissionError):
                        subscriber.get_message(timeout=3)

    def test_admin_and_queue_access_remain_denied(self):
        for command in (("FLUSHALL",), ("ACL", "LIST"), ("SET", "asynq:test", "x")):
            with self.subTest(command=command):
                with self.assertRaises(redis.exceptions.NoPermissionError):
                    self.client.execute_command(*command)
