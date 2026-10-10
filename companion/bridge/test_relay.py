import json
import threading
import tempfile
import time
import unittest
from pathlib import Path
from http.server import ThreadingHTTPServer
from unittest.mock import patch

from relay_server import RelayError, RelayStore, handler_for_relay
from relay_client import RelayArenaStore, RelayClientError, RelayHTTP, validate_url

P1 = {"userId": 101, "name": "Alice", "life": "alice1", "spells": ["Flame", "Freeze", "Wave"], "ultimate": "Nova"}
P2 = {"userId": 202, "name": "Bob", "life": "bob1", "spells": ["Zorblax", "Ice", "Wave"], "ultimate": "Eclipse"}


def poll(store, players=None, session="room", **kwargs):
    return store.game_poll({"session": session, "players": [P1, P2] if players is None else players,
                            "waitSeconds": 0, "serverTimeMs": 100000, **kwargs})


def pair(store, response, index=0):
    return store.pair(response["players"][index]["pairCode"])


def command(store, paired, spell="Flame", identifier="cast1", **kwargs):
    return store.command(paired["token"], {"id": identifier, "spell": spell,
                                         "revision": paired["player"]["revision"], **kwargs})


class RelayTests(unittest.TestCase):
    def test_generated_studio_config_uses_secret_name_without_exposing_credential(self):
        import host_relay
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "companion/bridge"
            root.mkdir(parents=True)
            game = Path(directory) / "game/scripts/ServerScriptService/VoiceArena"
            game.mkdir(parents=True)
            with patch.object(host_relay, "ROOT", root):
                host_relay.write_config("https://relay.example.com", "must-never-be-in-source")
            for path in (root / "VoiceRelayConfig.generated.luau", game / "VoiceRelayConfig.luau"):
                source = path.read_text()
                self.assertIn('SecretName = "VOICE_RELAY_SERVER_TOKEN"', source)
                self.assertNotIn("must-never-be-in-source", source)
                self.assertNotIn("ServerToken", source)

    def test_two_players_cast_independently_and_ultimate_has_no_slot(self):
        store = RelayStore()
        roster = poll(store)
        a, b = pair(store, roster), pair(store, roster, 1)
        command(store, a)
        command(store, b, "Ultimate", "cast2")
        result = poll(store)
        self.assertEqual([(c["userId"], c["spell"]) for c in result["commands"]], [(101, "Flame"), (202, "Ultimate")])
        self.assertEqual(result["commands"][0]["slot"], 1)
        self.assertNotIn("slot", result["commands"][1])
        self.assertTrue(all(p["voiceActive"] for p in result["players"]))
        self.assertTrue(all(not p["pairCode"] for p in result["players"]))

    def test_pair_codes_are_one_use_and_do_not_reveal_other_players(self):
        store = RelayStore()
        roster = poll(store)
        code = roster["players"][0]["pairCode"]
        a = store.pair(code[:5] + "-" + code[5:])
        self.assertEqual(a["player"]["name"], "Alice")
        self.assertNotIn("players", store.client_state(a["token"]))
        with self.assertRaises(RelayError) as error:
            store.pair(code)
        self.assertEqual(error.exception.status, 404)
        with self.assertRaises(RelayError):
            store.client_state("invented-token")
        with self.assertRaises(RelayError):
            command(store, a, "Zorblax")

    def test_rooms_and_authenticated_identity_are_isolated(self):
        store = RelayStore()
        a = pair(store, poll(store))
        other = pair(store, poll(store, session="other"))
        command(store, a, userId=202, session="other", life="bob1")
        self.assertEqual(poll(store, session="other")["commands"], [])
        cast = poll(store)["commands"][0]
        self.assertEqual((cast["userId"], cast["life"]), (101, "alice1"))
        command(store, other)
        self.assertEqual(poll(store, session="other")["commands"][0]["userId"], 101)

    def test_retry_deduplication_ack_and_expiry(self):
        now = [0.0]
        store = RelayStore(clock=lambda: now[0])
        a = pair(store, poll(store))
        command(store, a)
        self.assertTrue(command(store, a)["duplicate"])
        result = poll(store)
        self.assertEqual(len(result["commands"]), 1)
        self.assertEqual(poll(store, ack=["cast1"])["commands"], [])
        now[0] += 1
        command(store, a, identifier="cast2")
        now[0] += 2.6
        self.assertEqual(poll(store)["commands"], [])

    def test_clock_uses_game_time_even_if_host_clock_differs(self):
        now = [10.0]
        store = RelayStore(clock=lambda: now[0], wall=lambda: 900000000)
        roster = poll(store, serverTimeMs=123456)
        a = pair(store, roster)
        now[0] += 8
        command(store, a, ageMs=250)
        result = poll(store, serverTimeMs=131456)
        self.assertEqual(result["commands"][0]["createdAt"], 131206)

    def test_respawn_and_name_changes_invalidate_old_commands_and_refresh_client(self):
        store = RelayStore()
        a = pair(store, poll(store))
        command(store, a)
        changed = [{**P1, "life": "alice2", "ultimate": "Thunderstrike"}, P2]
        self.assertEqual(poll(store, changed)["commands"], [])
        current = store.client_state(a["token"])["player"]
        self.assertEqual((current["life"], current["ultimate"]), ("alice2", "Thunderstrike"))
        with self.assertRaises(RelayError) as error:
            command(store, a, identifier="stale")
        self.assertEqual(error.exception.status, 409)
        a["player"] = current
        command(store, a, "Ultimate", "new-life")
        self.assertEqual(poll(store, changed)["commands"][0]["life"], "alice2")

    def test_reset_unpair_leave_and_rejoin_revoke_tokens(self):
        store = RelayStore()
        a = pair(store, poll(store))
        result = poll(store, resetPairings=[101])
        with self.assertRaises(RelayError):
            store.client_state(a["token"])
        a = pair(store, result)
        store.unpair(a["token"])
        with self.assertRaises(RelayError):
            store.client_state(a["token"])
        a = pair(store, poll(store))
        poll(store, [P2])
        with self.assertRaises(RelayError):
            store.client_state(a["token"])
        self.assertTrue(poll(store)["players"][0]["pairCode"])

    def test_disconnect_pauses_then_expires_pairing(self):
        now = [0.0]
        store = RelayStore(clock=lambda: now[0])
        a = pair(store, poll(store))
        now[0] = 7
        self.assertFalse(poll(store)["players"][0]["voiceActive"])
        store.client_state(a["token"])
        self.assertTrue(poll(store)["players"][0]["voiceActive"])
        now[0] = 38
        self.assertTrue(poll(store)["players"][0]["pairCode"])
        with self.assertRaises(RelayError):
            store.client_state(a["token"])

    def test_invalid_payloads_and_stale_commands_rejected(self):
        store = RelayStore()
        a = pair(store, poll(store))
        for age in (-1, 1500, float("nan"), float("inf"), "old"):
            with self.assertRaises(RelayError):
                command(store, a, ageMs=age)
        for wait in (-1, 9, float("nan"), True):
            with self.assertRaises(ValueError):
                poll(store, waitSeconds=wait)
        for url in ("http://example.com", "https://user:secret@a.com", "https://a.com/path", "https://a.com?q=1"):
            with self.assertRaises(ValueError):
                validate_url(url)

    def test_long_poll_wakes_for_another_computer_command(self):
        store = RelayStore()
        a = pair(store, poll(store))
        result = []
        worker = threading.Thread(target=lambda: result.append(poll(store, waitSeconds=2)))
        worker.start()
        time.sleep(0.05)
        command(store, a)
        worker.join(1)
        self.assertFalse(worker.is_alive())
        self.assertEqual(result[0]["commands"][0]["spell"], "Flame")

    def test_http_game_auth_and_two_companion_adapters(self):
        store, token = RelayStore(), "game-server-private-token-" * 3
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for_relay(store, token))
        server.daemon_threads = True
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        base = f"http://127.0.0.1:{server.server_port}"
        http = RelayHTTP(base, allow_local=True)
        stopping = threading.Event()
        clients = []
        try:
            body = {"session": "room", "players": [P1, P2], "serverTimeMs": 100000, "waitSeconds": 0}
            with self.assertRaises(RelayClientError) as error:
                http.post("/v1/game/poll", body, "wrong-token")
            self.assertEqual(error.exception.status, 401)
            roster = http.post("/v1/game/poll", body, token)
            with patch("builtins.print"):
                clients = [RelayArenaStore(base, p["pairCode"], stopping, allow_local=True) for p in roster["players"]]
                self.assertEqual(clients[0].event({"message_type": "partial_transcript", "text": "Nova"}), [])
                self.assertEqual(clients[0].event({"message_type": "committed_transcript", "text": "Nova"}), ["Ultimate"])
                self.assertEqual(clients[1].event({"message_type": "committed_transcript", "text": "ZOR BLAX"}), ["Zorblax"])
            result = http.post("/v1/game/poll", body, token)
            self.assertEqual([(c["userId"], c["spell"]) for c in result["commands"]], [(101, "Ultimate"), (202, "Zorblax")])
            self.assertNotIn("slot", result["commands"][0])
            self.assertEqual(result["commands"][1]["slot"], 1)
            # Heartbeat fetches updated names without changing the authenticated player.
            body["players"] = [{**P1, "ultimate": "Thunderstrike"}, P2]
            http.post("/v1/game/poll", body, token)
            deadline = time.monotonic() + 2
            while clients[0].selected_player()["ultimate"] != "Thunderstrike" and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertEqual(clients[0].selected_player()["ultimate"], "Thunderstrike")
        finally:
            stopping.set()
            for client in clients:
                client.close()
            server.shutdown(); server.server_close(); worker.join(1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
