"""Exercise MCP address and OAuth origin resolution with the generated config."""

import os
import unittest
from unittest.mock import patch

import yaml
from fastapi import Request
from litellm.proxy.auth.ip_address_utils import IPAddressUtils


class ProxyHeadersTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open("/gateway-config.yaml", encoding="utf-8") as source:
            cls.settings = yaml.safe_load(source)["general_settings"]
        cls.proxy = str(
            IPAddressUtils.parse_trusted_proxy_networks(
                cls.settings["mcp_trusted_proxy_ranges"]
            )[0].network_address
            + 2
        )

    def request(self, peer, forwarded, proto="http"):
        return Request(
            {
                "type": "http",
                "method": "POST",
                "path": "/mcp/",
                "scheme": "http",
                "server": ("gateway.example.com", 4000),
                "query_string": b"",
                "client": (peer, 12345),
                "headers": [
                    (b"host", b"gateway.example.com"),
                    (b"x-forwarded-for", forwarded.encode()),
                    (b"x-forwarded-proto", proto.encode()),
                ],
            }
        )

    def test_real_ip_and_tailnet_classification(self):
        cases = (
            ("100.90.0.1", True),
            ("8.8.8.8", False),
            ("::1", True),
            ("2001:4860:4860::8888", False),
        )
        networks = IPAddressUtils.parse_internal_networks(
            self.settings["mcp_internal_ip_ranges"]
        )
        for address, expected in cases:
            with self.subTest(address=address):
                result = IPAddressUtils.get_mcp_client_ip(
                    self.request(self.proxy, address), self.settings
                )
                self.assertEqual(result, address)
                self.assertEqual(
                    IPAddressUtils.is_internal_ip(result, networks), expected
                )

    def test_prepended_internal_address_does_not_bypass_access_control(self):
        result = IPAddressUtils.get_mcp_client_ip(
            self.request(self.proxy, "127.0.0.1, 8.8.8.8"), self.settings
        )
        self.assertEqual(result, "8.8.8.8")
        self.assertFalse(IPAddressUtils.is_internal_ip(result))

    def test_untrusted_peer_cannot_select_a_private_ip(self):
        result = IPAddressUtils.get_mcp_client_ip(
            self.request("8.8.4.4", "127.0.0.1"), self.settings
        )
        self.assertEqual(result, "8.8.4.4")

    def test_malformed_headers_fail_closed(self):
        for forwarded in ("", "garbage", "127.0.0.1, invalid"):
            with self.subTest(forwarded=forwarded):
                result = IPAddressUtils.get_mcp_client_ip(
                    self.request(self.proxy, forwarded), self.settings
                )
                self.assertFalse(IPAddressUtils.is_internal_ip(result))

    def test_https_requires_the_trusted_hop_or_operator_origin(self):
        with patch.dict(os.environ, {"PROXY_BASE_URL": ""}):
            self.assertTrue(
                IPAddressUtils.is_request_https(
                    self.request(self.proxy, "8.8.8.8", "https"), self.settings
                )
            )
            self.assertFalse(
                IPAddressUtils.is_request_https(
                    self.request("8.8.4.4", "127.0.0.1", "https"), self.settings
                )
            )
        with patch.dict(os.environ, {"PROXY_BASE_URL": "https://gateway.example.com"}):
            self.assertTrue(
                IPAddressUtils.is_request_https(
                    self.request(self.proxy, "8.8.8.8"), self.settings
                )
            )
