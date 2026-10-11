import json
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch

import configure_stable_relay as setup
import host_relay
from relay_server import RelayStore, handler_for_relay

TOKEN = "eyJ" + "A" * 128


class StableRelayTests(unittest.TestCase):
    def test_setup_normalizes_install_command_and_keeps_token_out_of_settings(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(setup, "ROOT", Path(directory)):
            self.assertEqual(setup.save_settings("voice-relay.blazinblaze.net", "cloudflared.exe service install " + TOKEN), setup.DEFAULT_URL)
            settings = (Path(directory) / setup.SETTINGS).read_text()
            self.assertNotIn(TOKEN, settings)
            self.assertEqual((Path(directory) / setup.TOKEN_FILE).read_text().strip(), TOKEN)
            saved = setup.load_settings()
            self.assertEqual(saved["url"], setup.DEFAULT_URL)
            self.assertEqual(saved["token_file"], Path(directory) / setup.TOKEN_FILE)
            self.assertIsNone(setup.load_settings(force_quick=True))

    def test_missing_configuration_preserves_existing_quick_mode(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(setup, "ROOT", Path(directory)):
            self.assertIsNone(setup.load_settings())
            (Path(directory) / setup.SETTINGS).write_text(json.dumps({"url": setup.DEFAULT_URL}))
            with self.assertRaises(ValueError):
                setup.load_settings()

    def test_hostname_validation_and_short_api_keys_rejected(self):
        for url in ("http://relay.example.com", "https://user:pass@relay.example.com", "https://relay.example.com/path", "https://relay.example.com:443", "https://relay.example.com?x=1"):
            with self.assertRaises(ValueError):
                setup.stable_url(url)
        self.assertEqual(setup.stable_url("HTTPS://VOICE-RELAY.BLAZINBLAZE.NET/"), setup.DEFAULT_URL)
        with self.assertRaises(ValueError):
            setup.tunnel_token("not-an-api-key-to-save")

    def test_named_command_does_not_expose_tunnel_token_in_arguments(self):
        stable = {"url": setup.DEFAULT_URL, "token_file": Path("private.token")}
        named = host_relay.tunnel_command(Path("cloudflared.exe"), 8790, stable)
        self.assertEqual(named[-3:], ["run", "--token-file", "private.token"])
        self.assertNotIn(TOKEN, " ".join(named))
        self.assertNotIn("--url", named)
        self.assertEqual(host_relay.tunnel_command(Path("cloudflared.exe"), 8790)[-2:], ["--url", "http://127.0.0.1:8790"])

    def test_route_health_confirms_this_host_without_credentials(self):
        handler = handler_for_relay(RelayStore(), "host-credential-not-sent-by-health-check")
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            url = f"http://127.0.0.1:{server.server_port}"
            self.assertTrue(host_relay.verify_route(url, handler.instance_id))
            self.assertFalse(host_relay.verify_route(url, "other-relay-instance"))
        finally:
            server.shutdown()
            server.server_close()
            worker.join(1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
