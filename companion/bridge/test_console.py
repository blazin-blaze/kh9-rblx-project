import base64
import json
import os
import tempfile
from pathlib import Path
import threading
import time
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from console_bridge import ArenaStore, WordReceiver, audio_message, detect_commands, detect_spells, handler_for, stream_session, websocket_url

ROSTER = [{"userId": -1, "name": "Player1", "life": "life1"}]


def register(store):
    store.poll("studio", ROSTER)
    store.select(store.roster()[0])


class ConsoleTests(unittest.TestCase):
    def test_missing_default_env_is_created_for_local_studio(self):
        import console_bridge
        original_root = console_bridge.ROOT
        original_override = os.environ.pop("VOICE_ARENA_TOKEN_FILE", None)
        try:
            with tempfile.TemporaryDirectory() as directory:
                console_bridge.ROOT = Path(directory)
                self.assertEqual(console_bridge.bridge_token(), console_bridge.DEFAULT_BRIDGE_TOKEN)
                self.assertIn(
                    f"BRIDGE_TOKEN={console_bridge.DEFAULT_BRIDGE_TOKEN}",
                    (Path(directory) / ".env").read_text(encoding="utf-8"),
                )
        finally:
            console_bridge.ROOT = original_root
            if original_override is not None:
                os.environ["VOICE_ARENA_TOKEN_FILE"] = original_override

    def test_ultimate_is_reserved_exact_command_with_any_loadout(self):
        store = ArenaStore()
        roster = [{**ROSTER[0], "spells": ["Zorblax", "Ice", "Wave"]}]
        store.poll("studio", roster)
        store.select(store.roster()[0])
        self.assertEqual(store.event({"message_type": "partial_transcript", "text": "ultimate!"}), [])
        self.assertEqual(store.event({"message_type": "committed_transcript", "text": "ultimates ultimately ultimato ultimate2 _ultimate"}), [])
        self.assertEqual(store.event({"message_type": "committed_transcript", "text": "ULTIMATE!"}), ["Ultimate"])
        command = store.poll("studio", roster)["commands"][0]
        self.assertEqual(command["spell"], "Ultimate")
        self.assertNotIn("slot", command)
        self.assertEqual(command["life"], "life1")
        self.assertEqual(detect_commands("ultimate", ("Flame", "Freeze", "Wave")), ["Ultimate"])


    def test_individual_words_ignore_cumulative_replays_and_cast_only_confirmed_words(self):
        store = ArenaStore()
        register(store)
        output = []
        words = WordReceiver(store, output=lambda line, **kwargs: output.append(line))
        words.event({"message_type": "partial_transcript", "text": "hello Flame"})
        words.event({"message_type": "partial_transcript", "text": "hello Flame"})
        words.event({"message_type": "partial_transcript", "text": "hello Flame Freeze"})
        self.assertEqual(output, ["[Word tentative] hello", "[Word tentative] flame", "[Word tentative] freeze"])
        self.assertEqual(store.poll("studio", ROSTER)["commands"], [])
        words.event({"message_type": "committed_transcript", "text": "Hello Flame Freeze!"})
        self.assertEqual(output[-2:], ["[Spell] Flame", "[Spell] Freeze"])
        self.assertEqual([c["spell"] for c in store.poll("studio", ROSTER)["commands"]], ["Flame", "Freeze"])
        words.event({"message_type": "committed_transcript_with_timestamps", "text": "Hello Flame Freeze!"})
        self.assertEqual(len(output), 5)
        words.event({"message_type": "committed_transcript", "text": "hello hello wave"})
        self.assertEqual(output[-4:], ["[Word] hello", "[Word] hello", "[Word] wave", "[Spell] Wave"])

    def test_revised_tentative_spell_does_not_cast(self):
        store = ArenaStore()
        register(store)
        output = []
        words = WordReceiver(store, output=lambda line, **kwargs: output.append(line))
        words.event({"message_type": "partial_transcript", "text": "flame"})
        words.event({"message_type": "committed_transcript", "text": "frame"})
        self.assertEqual(output, ["[Word tentative] flame", "[Word] frame"])
        self.assertEqual(store.poll("studio", ROSTER)["commands"], [])

    def test_exact_spell_words(self):
        self.assertEqual(detect_spells("FLAME! Freeze, wave flame"), ["Flame", "Freeze", "Wave"])
        self.assertEqual(detect_spells("flames heatwave freezer flame2 _wave 波wave"), [])
        self.assertEqual(detect_spells(None), [])

    def test_custom_spell_names_from_the_game(self):
        store = ArenaStore()
        roster = [{**ROSTER[0], "spells": ["Zorblax", "Ice", "Wave"]}]
        store.poll("studio", roster)
        store.select(store.roster()[0])
        self.assertEqual(store.event({"message_type": "committed_transcript", "text": "Flame!"}), [])
        self.assertEqual(store.event({"message_type": "committed_transcript", "text": "zorblax"}), ["Zorblax"])
        self.assertEqual(store.event({"message_type": "committed_transcript", "text": "ice"}), ["Ice"])
        commands = store.poll("studio", roster)["commands"]
        self.assertEqual([(c["spell"], c["slot"]) for c in commands], [("Zorblax", 1), ("Ice", 2)])

    def test_name_matching_rules(self):
        names = ("Zorblax", "Ice", "Thunderstrike")
        self.assertEqual(detect_spells("ZOR BLAX now", names), ["Zorblax"])          # split by speech-to-text
        self.assertEqual(detect_spells("zorblux", names), ["Zorblax"])               # one letter misheard
        self.assertEqual(detect_spells("thundrstrik", names), ["Thunderstrike"])     # long names allow two
        self.assertEqual(detect_spells("nice dice mice", names), [])                 # short names are exact only
        self.assertEqual(detect_spells("zorblax2 _ice", names), [])
        self.assertEqual(detect_spells("ice then zorblax", names), ["Ice", "Zorblax"])

    def test_invalid_spell_lists_fall_back_to_defaults(self):
        store = ArenaStore()
        for bad in (["two words"], ["x" * 21], [1, 2], ["a", "b", "c", "d"], "Zorblax"):
            store.poll("studio", [{**ROSTER[0], "spells": bad}])
            store.select(store.roster()[0])
            self.assertEqual(store.event({"message_type": "committed_transcript", "text": "wave"}), ["Wave"])
            store.last_spell.clear()

    def test_finals_only_ack_and_spam_gate(self):
        store = ArenaStore()
        register(store)
        self.assertEqual(store.event({"message_type": "partial_transcript", "text": "Flame"}), [])
        self.assertEqual(store.event({"message_type": "committed_transcript_with_timestamps", "text": "Flame"}), [])
        self.assertEqual(store.event({"message_type": "committed_transcript", "text": "Flame"}), ["Flame"])
        self.assertEqual(store.event({"message_type": "committed_transcript", "text": "Flame"}), [])
        response = store.poll("studio", ROSTER)
        command = response["commands"][0]
        self.assertEqual(command["userId"], -1)
        self.assertTrue(response["players"][0]["voiceActive"])
        self.assertNotIn("mono", command)
        self.assertEqual(store.poll("studio", ROSTER)["commands"][0]["id"], command["id"])
        self.assertEqual(store.poll("studio", ROSTER, [command["id"]])["commands"], [])

    def test_expiry_respawn_leave_and_room_isolation(self):
        now = [100.0]
        store = ArenaStore(clock=lambda: now[0], wall=lambda: now[0])
        register(store)
        store.event({"message_type": "committed_transcript", "text": "Wave"})
        now[0] += 2.6
        self.assertEqual(store.poll("studio", ROSTER)["commands"], [])
        store.event({"message_type": "committed_transcript", "text": "Freeze"})
        respawn = [{**ROSTER[0], "life": "life2"}]
        self.assertEqual(store.poll("studio", respawn)["commands"], [])
        store.event({"message_type": "committed_transcript", "text": "Flame"})
        self.assertEqual(store.poll("studio", respawn)["commands"][0]["life"], "life2")
        self.assertEqual(store.poll("another-studio", ROSTER)["commands"], [])
        store.poll("studio", [])
        self.assertIsNone(store.selected_player())
        self.assertEqual(store.event({"message_type": "committed_transcript", "text": "Wave"}), [])
        now[0] += 31
        self.assertEqual(store.roster(), [])

    def test_long_poll_wakes_for_spell_only(self):
        store = ArenaStore()
        register(store)
        results = []
        worker = threading.Thread(target=lambda: results.append(store.poll("studio", ROSTER, wait=1)))
        worker.start()
        time.sleep(0.05)
        store.event({"message_type": "partial_transcript", "text": "Flame"})
        store.event({"message_type": "committed_transcript", "text": "hello there"})
        time.sleep(0.05)
        self.assertEqual(results, [])
        store.event({"message_type": "committed_transcript", "text": "Flame"})
        worker.join(0.5)
        self.assertFalse(worker.is_alive())
        self.assertEqual(results[0]["commands"][0]["spell"], "Flame")

    def test_audio_payload_and_api_parameters(self):
        raw = bytes(3200)
        payload = json.loads(audio_message(raw, 16000))
        self.assertEqual(base64.b64decode(payload["audio_base_64"]), raw)
        self.assertEqual(payload["sample_rate"], 16000)
        self.assertEqual(payload["message_type"], "input_audio_chunk")
        self.assertIn("audio_format=pcm_48000", websocket_url(48000))
        self.assertIn("commit_strategy=vad", websocket_url(16000))
        url = websocket_url(16000, ["Zorblax", "Ice", "Ice"])
        self.assertIn("keyterms=Zorblax", url)
        self.assertEqual(url.count("keyterms=Ice"), 1)
        self.assertNotIn("keyterms", websocket_url(16000))

    def test_http_auth_and_absent_website(self):
        store, token = ArenaStore(), "test-transport-token-" * 3
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(store, token))
        server.daemon_threads = True
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        base = f"http://127.0.0.1:{server.server_port}"
        try:
            with urllib.request.urlopen(base + "/health") as response:
                self.assertEqual(json.load(response)["mode"], "console")
            with self.assertRaises(urllib.error.HTTPError) as error:
                urllib.request.urlopen(base + "/")
            self.assertEqual(error.exception.code, 404)
            body = json.dumps({"session": "studio", "players": ROSTER, "ack": []}).encode()
            with self.assertRaises(urllib.error.HTTPError) as error:
                urllib.request.urlopen(urllib.request.Request(base + "/v1/poll", body))
            self.assertEqual(error.exception.code, 401)
            request = urllib.request.Request(base + "/v1/poll", body, {"Authorization": "Bearer " + token})
            with urllib.request.urlopen(request) as response:
                self.assertEqual(json.load(response)["players"][0]["userId"], -1)
        finally:
            server.shutdown()
            server.server_close()
            worker.join(1)

    def test_native_capture_path_with_simulated_audio_and_scribe(self):
        from websockets.sync.server import serve
        from websockets.sync.client import connect
        store, stop = ArenaStore(), threading.Event()
        register(store)
        errors, audio_seen = [], []

        def scribe(ws):
            try:
                payload = json.loads(ws.recv(timeout=2))
                audio_seen.append(payload)
                ws.send(json.dumps({"message_type": "partial_transcript", "text": "Freeze"}))
                ws.send(json.dumps({"message_type": "committed_transcript", "text": "Freeze"}))
                while not stop.wait(0.05):
                    pass
            except Exception as error:
                errors.append(error)

        class FakeInputStream:
            def __init__(self, **settings):
                self.settings = settings
            def __enter__(self):
                self.settings["callback"](bytes(3200), 1600, None, None)
                return self
            def __exit__(self, *args):
                pass

        class FakeSoundDevice:
            RawInputStream = FakeInputStream

        with serve(scribe, "127.0.0.1", 0) as server:
            server_worker = threading.Thread(target=server.serve_forever, daemon=True)
            server_worker.start()
            url = f"ws://127.0.0.1:{server.socket.getsockname()[1]}"
            with connect(url) as ws:
                def run_capture():
                    try:
                        stream_session(ws, FakeSoundDevice, None, 16000, store, stop)
                    except Exception as error:
                        errors.append(error)
                capture = threading.Thread(target=run_capture)
                capture.start()
                deadline = time.monotonic() + 2
                while not store.poll("studio", ROSTER)["commands"] and time.monotonic() < deadline:
                    time.sleep(0.02)
                result = store.poll("studio", ROSTER)
                stop.set()
                capture.join(2)
                self.assertFalse(capture.is_alive())
                self.assertEqual(errors, [])
                self.assertEqual(result["commands"][0]["spell"], "Freeze")
                self.assertEqual(audio_seen[0]["message_type"], "input_audio_chunk")
                self.assertEqual(len(base64.b64decode(audio_seen[0]["audio_base_64"])), 3200)
            server.shutdown()
            server_worker.join(1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
