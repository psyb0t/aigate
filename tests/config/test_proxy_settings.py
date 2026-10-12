"""Validate the generated proxy trust boundary."""

import json
import runpy
import unittest
from pathlib import Path
from unittest.mock import patch

BUILDER = runpy.run_path(
    str(Path(__file__).resolve().parents[2] / "litellm/build-config.py")
)


class ProxySettingsTest(unittest.TestCase):
    def test_defaults_trust_only_the_proxy_network(self):
        result = BUILDER["proxy_settings"]({})
        self.assertEqual(result["mcp_trusted_proxy_ranges"], ["172.30.255.240/29"])
        self.assertTrue(result["use_x_forwarded_for"])
        self.assertEqual(result["mcp_xff_num_trusted_hops"], 1)
        self.assertEqual(json.loads(json.dumps(result)), result)

    def test_narrow_private_overrides(self):
        result = BUILDER["proxy_settings"](
            {
                "AIGATE_PROXY_SUBNET": "10.200.1.0/29",
                "AIGATE_INGRESS_SUBNET": "10.200.2.0/29",
            }
        )
        self.assertEqual(result["mcp_trusted_proxy_ranges"], ["10.200.1.0/29"])

    def test_invalid_networks_fail_before_writing_configuration(self):
        cases = (
            {"AIGATE_PROXY_SUBNET": "0.0.0.0/0"},
            {"AIGATE_PROXY_SUBNET": "8.8.8.0/29"},
            {"AIGATE_PROXY_SUBNET": "172.16.0.0/12"},
            {"AIGATE_PROXY_SUBNET": "10.0.0.1/29"},
            {"AIGATE_PROXY_SUBNET": "bad\nconfig"},
            {"AIGATE_PROXY_SUBNET": "::/0"},
            {"AIGATE_PROXY_SUBNET": "127.0.0.0/29"},
            {"AIGATE_PROXY_SUBNET": "192.0.2.0/29"},
            {"AIGATE_INGRESS_SUBNET": "172.30.255.240/29"},
            {"AIGATE_INGRESS_SUBNET": ""},
        )
        for settings in cases:
            with self.subTest(settings=settings), self.assertRaises(ValueError):
                BUILDER["proxy_settings"](settings)

    def test_exported_compose_settings_override_env_file(self):
        with patch.dict("os.environ", {"AIGATE_PROXY_SUBNET": "10.200.3.0/29"}):
            result = BUILDER["proxy_settings"]({"AIGATE_PROXY_SUBNET": "10.200.1.0/29"})
        self.assertEqual(result["mcp_trusted_proxy_ranges"], ["10.200.3.0/29"])
