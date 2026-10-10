"""Native microphone -> ElevenLabs Scribe -> localhost Roblox Studio spell queue."""
import argparse
import base64
from collections import Counter
import getpass
import hmac
import json
import os
import queue
import re
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlencode

ROOT = Path(__file__).resolve().parent
# Used until the player equips a loadout in Studio; the game then sends their spell and ultimate names.
DEFAULT_SPELLS = ("Flame", "Freeze", "Wave")
DEFAULT_ULTIMATE = "Ultimate"
NAME_RE = re.compile(r"[A-Za-z]{1,20}")
ERRORS = {"auth_error", "quota_exceeded", "transcriber_error", "input_error", "invalid_request",
          "error", "commit_throttled", "unaccepted_terms", "rate_limited", "queue_overflow",
          "resource_exhausted", "session_time_limit_exceeded", "chunk_size_exceeded",
          "insufficient_audio_activity"}
FATAL = {"auth_error", "quota_exceeded", "input_error", "invalid_request", "unaccepted_terms"}


def clean_spells(value):
    """The game's spell names for one player: up to 3 single words, letters only. None if invalid."""
    if not isinstance(value, list) or not 1 <= len(value) <= 3:
        return None
    if not all(isinstance(v, str) and NAME_RE.fullmatch(v) for v in value):
        return None
    return tuple(value)


def edit_distance(a, b):
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (ca != cb)))
        previous = current
    return previous[-1]


def fuzzy_limit(name):
    # Short names must match exactly ("frame" never casts "flame"); long made-up names
    # tolerate a misheard letter or two ("zorblux" still casts "Zorblax").
    return 2 if len(name) >= 10 else 1 if len(name) >= 7 else 0


def detect_spells(text, names=None):
    """Spell names spoken in text, in order, without repeats. Matches whole words, two adjacent
    words joined together (speech-to-text can split invented names: "zor blax"), and near-misses
    for long names. Words containing digits, underscores or non-English letters never match."""
    if not isinstance(text, str):
        return []
    lookup = {name.lower(): name for name in (names or DEFAULT_SPELLS)}
    tokens = [t for t in re.findall(r"\w+", text.lower())]
    candidates = []
    for i, token in enumerate(tokens):
        if token.isascii() and token.isalpha():
            candidates.append(token)
            nxt = tokens[i + 1] if i + 1 < len(tokens) else ""
            if nxt.isascii() and nxt.isalpha():
                candidates.append(token + nxt)
    found = []
    for word in candidates:
        if word in lookup:
            found.append(lookup[word])
            continue
        best = None
        for key, name in lookup.items():
            limit = fuzzy_limit(key)
            if limit and abs(len(key) - len(word)) <= limit and edit_distance(key, word) <= limit:
                best = name
                break
        if best:
            found.append(best)
    return list(dict.fromkeys(found))


def detect_commands(text, names=None, ultimate=DEFAULT_ULTIMATE):
    spells = detect_spells(text, names)
    if ultimate.lower() == DEFAULT_ULTIMATE.lower():
        # Preserve exact matching for the default word; "ultimately" must never fire it.
        matched = isinstance(text, str) and "ultimate" in re.findall(r"\w+", text.lower())
    else:
        # Custom names use the same split-word and long-name tolerance as ordinary spells.
        matched = bool(detect_spells(text, (ultimate,)))
    if matched:
        # Studio routes this canonical command to the death beam; it is never a spell slot.
        spells.append(DEFAULT_ULTIMATE)
    return list(dict.fromkeys(spells))


def spell_names(player):
    return tuple((player or {}).get("spells") or DEFAULT_SPELLS)


def ultimate_word(player):
    word = (player or {}).get("ultimate")
    return word if isinstance(word, str) and NAME_RE.fullmatch(word) and len(word) >= 3 else DEFAULT_ULTIMATE


def recognition_names(player):
    """All activation words, including the ultimate, for Scribe hints and change detection."""
    return (*spell_names(player), ultimate_word(player))


def loadout_summary(player):
    return f'Spell names: {", ".join(spell_names(player))}; ultimate word: {ultimate_word(player)}'


class WordReceiver:
    """Turn cumulative Scribe text into individual word events, without replaying words."""
    def __init__(self, store, output=print):
        self.store, self.output = store, output
        self.logged = set()

    def event(self, event):
        kind = event.get("message_type")
        if kind not in {"partial_transcript", "committed_transcript"}:
            return
        text = event.get("text", "")
        if not isinstance(text, str):
            return
        final = kind == "committed_transcript"
        counts = Counter()
        for word in re.findall(r"\w+(?:['’]\w+)*", text.lower()):
            counts[word] += 1
            occurrence = (word, counts[word])
            if occurrence not in self.logged:
                self.logged.add(occurrence)
                self.output(f'[{"Word" if final else "Word tentative"}] {word}', flush=True)
        if final:
            # The whole confirmed phrase goes to the spell filter so split names ("zor blax") still match.
            for spell in self.store.event({"message_type": "committed_transcript", "text": text}):
                self.output(f"[Spell] {spell}", flush=True)
            self.logged.clear()


DEFAULT_BRIDGE_TOKEN = "kh9-localhost-bridge-dev-token-v1"

def bridge_token():
    """Load a user override, or create the public loopback-only development config."""
    configured = os.environ.get("VOICE_ARENA_TOKEN_FILE")
    token_file = Path(configured) if configured else ROOT / ".env"
    if not token_file.exists():
        if configured:
            raise ValueError(f"Configured token file does not exist: {token_file}")
        token_file.write_text(
            "# Created automatically for a local Roblox Studio playtest.\n"
            "# This token protects only the loopback connection.\n"
            f"BRIDGE_TOKEN={DEFAULT_BRIDGE_TOKEN}\n",
            encoding="utf-8",
        )
        print("Created bridge/.env for local Studio use.", flush=True)
    for line in token_file.read_text(encoding="utf-8-sig").splitlines():
        if line.startswith("BRIDGE_TOKEN="):
            token = line.partition("=")[2].strip()
            if len(token) >= 16:
                return token
    raise ValueError(
        f"Missing BRIDGE_TOKEN in {token_file}. Set one there and use the same value in SpellConfig.BridgeToken."
    )


class ArenaStore:
    def __init__(self, clock=time.monotonic, wall=time.time):
        self.clock, self.wall = clock, wall
        self.condition = threading.Condition()
        self.rooms = {}
        self.selected = None
        self.version = 0
        self.last_spell = {}

    def _cleanup(self):
        now = self.clock()
        for session, room in list(self.rooms.items()):
            if now - room["updated"] > 30:
                del self.rooms[session]
            else:
                room["commands"] = [c for c in room["commands"] if now - c["mono"] < 2.5]

    def roster(self):
        with self.condition:
            self._cleanup()
            return [{**p, "session": session} for session, r in self.rooms.items() for p in r["players"].values()]

    def select(self, player):
        with self.condition:
            self.selected = (player["session"], player["userId"])
            self.last_spell.clear()
            self.version += 1
            self.condition.notify_all()

    def selected_player(self):
        with self.condition:
            self._cleanup()
            if not self.selected:
                return None
            session, user_id = self.selected
            player = self.rooms.get(session, {}).get("players", {}).get(user_id)
            return {**player, "session": session} if player else None

    def poll(self, session, players, ack=None, wait=0):
        if not isinstance(session, str) or not 1 <= len(session) <= 100 or not isinstance(players, list) or len(players) > 32:
            raise ValueError("Invalid roster")
        ack = ack or []
        if not isinstance(ack, list) or len(ack) > 256 or any(not isinstance(i, str) for i in ack):
            raise ValueError("Invalid ACK")
        for p in players:
            if (not isinstance(p, dict) or type(p.get("userId")) is not int or
                    not isinstance(p.get("name"), str) or not 1 <= len(p["name"]) <= 100 or
                    not isinstance(p.get("life"), str) or not 1 <= len(p["life"]) <= 100):
                raise ValueError("Invalid player")
        if not isinstance(wait, (int, float)) or not 0 <= wait <= 8:
            raise ValueError("Invalid wait")
        with self.condition:
            self._cleanup()
            if session not in self.rooms and len(self.rooms) >= 16:
                raise ValueError("Room limit")
            room = self.rooms.setdefault(session, {"players": {}, "commands": [], "updated": self.clock()})
            # "spells" is optional (older game builds omit it); invalid lists fall back to the defaults.
            roster = {p["userId"]: {**{k: p[k] for k in ("userId", "name", "life")},
                                    "spells": clean_spells(p.get("spells")),
                                    "ultimate": ultimate_word(p)} for p in players}
            changed = roster != room["players"]
            room["players"] = roster
            room["updated"] = self.clock()
            acknowledged = set(ack)
            room["commands"] = [c for c in room["commands"] if c["id"] not in acknowledged and
                                roster.get(c["userId"], {}).get("life") == c["life"]]
            self.condition.notify_all()
            version, deadline = self.version, self.clock() + wait
            while not changed and not room["commands"] and version == self.version and self.clock() < deadline:
                self.condition.wait(timeout=max(0, deadline - self.clock()))
            room["updated"] = self.clock()
            self._cleanup()
            return {"players": [{"userId": p["userId"], "voiceActive": self.selected == (session, p["userId"])}
                                for p in roster.values()],
                    "commands": [{k: v for k, v in c.items() if k != "mono"} for c in room["commands"]]}

    def event(self, event):
        if event.get("message_type") != "committed_transcript":
            return []
        with self.condition:
            player = self.selected_player()
            if not player:
                return []
            room = self.rooms[player["session"]]
            names = spell_names(player)
            emitted = []
            for spell in detect_commands(event.get("text"), names, ultimate_word(player)):
                now = self.clock()
                if now - self.last_spell.get(spell, -float("inf")) < 0.75 or len(room["commands"]) >= 128:
                    continue
                self.last_spell[spell] = now
                # The game resolves the spoken name to the player's slot; slot is a fallback.
                command = {"id": str(uuid.uuid4()), "userId": player["userId"], "life": player["life"],
                           "spell": spell,
                           "createdAt": round(self.wall() * 1000), "mono": now}
                if spell != "Ultimate":
                    command["slot"] = names.index(spell) + 1
                room["commands"].append(command)
                emitted.append(spell)
            if emitted:
                self.condition.notify_all()
            return emitted


def handler_for(store, token):
    auth_warning_at = [-float("inf")]
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def respond(self, status, payload):
            data = json.dumps(payload).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            try:
                self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError):
                pass

        def do_GET(self):
            if self.path == "/health":
                return self.respond(200, {"ok": True, "mode": "console", "studioOnly": True})
            self.respond(404, {"error": "No browser UI. Run Start.cmd."})

        def do_POST(self):
            if self.path != "/v1/poll":
                return self.respond(404, {"error": "Not found"})
            if not hmac.compare_digest(self.headers.get("Authorization", ""), "Bearer " + token):
                now = time.monotonic()
                if now - auth_warning_at[0] >= 15:
                    auth_warning_at[0] = now
                    print("Studio reached the console, but its bridge token does not match. "
                          "Check LocalConfig.cmd, bridge/.env, and SpellConfig.BridgeToken "
                          "(not the ElevenLabs API key).", flush=True)
                return self.respond(401, {"error": "Unauthorized"})
            try:
                self.connection.settimeout(12)
                size = int(self.headers.get("Content-Length", "0"))
                if not 0 < size <= 65536:
                    return self.respond(413, {"error": "Invalid body size"})
                request = json.loads(self.rfile.read(size))
                data = store.poll(request.get("session"), request.get("players"), request.get("ack"), request.get("waitSeconds", 0))
                self.respond(200, data)
            except (ValueError, TypeError, AttributeError, OSError):
                self.respond(400, {"error": "Invalid poll"})
    return Handler


class ScribeError(RuntimeError):
    def __init__(self, kind):
        self.kind = kind
        super().__init__(f"ElevenLabs event: {kind}. Check Speech-to-Text access, credits, and settings.")


def websocket_url(rate, keyterms=None):
    params = [("model_id", "scribe_v2_realtime"), ("audio_format", f"pcm_{rate}"), ("language_code", "en"),
              ("commit_strategy", "vad"), ("vad_silence_threshold_secs", "0.4"), ("keepalive_interval_ms", 1000)]
    # Keyterm prompting biases Scribe toward the spell names, so invented words like "Zorblax"
    # are transcribed correctly. Realtime allows up to 50 terms of at most 20 characters.
    for term in list(dict.fromkeys(keyterms or []))[:50]:
        if isinstance(term, str) and 0 < len(term) <= 20:
            params.append(("keyterms", term))
    return "wss://api.elevenlabs.io/v1/speech-to-text/realtime?" + urlencode(params)


def audio_message(chunk, rate):
    return json.dumps({"message_type": "input_audio_chunk", "audio_base_64": base64.b64encode(chunk).decode("ascii"),
                       "sample_rate": rate, "commit": False})


def stream_session(ws, sd, device, rate, store, stop, terms=None):
    chunks = queue.Queue(maxsize=5)
    local_stop, overflow = threading.Event(), threading.Event()
    errors = queue.Queue()
    words = WordReceiver(store)

    def callback(indata, frames, time_info, status):
        if status:
            overflow.set()
        try:
            chunks.put_nowait((time.monotonic(), bytes(indata)))
        except queue.Full:
            overflow.set()

    def sender():
        try:
            while not stop.is_set() and not local_stop.is_set():
                if overflow.is_set():
                    raise RuntimeError("Microphone buffer overflow")
                try:
                    captured, chunk = chunks.get(timeout=0.1)
                except queue.Empty:
                    continue
                if time.monotonic() - captured > 0.5:
                    raise RuntimeError("Audio backlog")
                ws.send(audio_message(chunk, rate))
        except Exception as error:
            errors.put(error)
            local_stop.set()

    worker = threading.Thread(target=sender, daemon=True)
    try:
        with sd.RawInputStream(samplerate=rate, blocksize=int(rate * 0.1), device=device,
                               dtype="int16", channels=1, callback=callback):
            names = ", ".join(terms or recognition_names(store.selected_player()))
            print(f"MICROPHONE ACTIVE. Say {names}; pause briefly. Ctrl+C stops.", flush=True)
            worker.start()
            while not stop.is_set():
                player = store.selected_player()
                if not player:
                    print("Studio player disconnected. Microphone paused until the playtest returns.", flush=True)
                    return
                if terms is not None and recognition_names(player) != tuple(terms):
                    # Keyterms are fixed per ElevenLabs session, so reconnect with the new names.
                    print(f'{loadout_summary(player)}. Reconnecting to listen for the updated words.', flush=True)
                    return
                if not errors.empty():
                    raise errors.get()
                try:
                    event = json.loads(ws.recv(timeout=0.1))
                except TimeoutError:
                    continue
                except Exception:
                    if stop.is_set():
                        break
                    raise
                kind = event.get("message_type", "")
                if kind in ERRORS or kind.endswith("_error"):
                    raise ScribeError(kind)
                words.event(event)
    finally:
        local_stop.set()
        ws.close()
        if worker.ident is not None:
            worker.join(2)


def select_player(store, preference=None):
    if hasattr(store, "ensure_selected"):
        return store.ensure_selected(preference)
    print("Waiting for Roblox Studio. Press Play in kh9 roblox project…", flush=True)
    while True:
        roster = store.roster()
        if preference is not None:
            roster = [p for p in roster if p["name"].casefold() == preference.casefold() or str(p["userId"]) == preference]
        if len(roster) == 1:
            chosen = roster[0]
            break
        if len(roster) > 1:
            print("Choose the player controlled by this microphone:", flush=True)
            for index, p in enumerate(roster, 1):
                print(f'{index}. {p["name"]} (UserId {p["userId"]})')
            try:
                index = int(input("Player number: ")) - 1
                if 0 <= index < len(roster):
                    chosen = roster[index]
                    break
            except ValueError:
                pass
        time.sleep(0.25)
    store.select(chosen)
    print(f'Controlling {chosen["name"]} (UserId {chosen["userId"]}). Respawns reconnect automatically.', flush=True)
    print(f'{loadout_summary(chosen)} (change them in the game\'s Set Your Spells screen).', flush=True)


def recognize(api_key, store, stop, device=None, requested_rate=None, preference=None):
    import sounddevice as sd
    from websockets.sync.client import connect
    from websockets.exceptions import InvalidStatus
    rates = [requested_rate] if requested_rate else [16000, 48000, 44100, 24000, 22050, 8000]
    rate = None
    for candidate in rates:
        try:
            sd.check_input_settings(device=device, channels=1, dtype="int16", samplerate=candidate)
            rate = candidate
            break
        except sd.PortAudioError:
            continue
    if rate is None:
        raise RuntimeError("Cannot open this microphone. Run ListMicrophones.cmd and choose --device NUMBER.")
    print(f'Microphone: {sd.query_devices(device, "input")["name"]}; mono PCM16 at {rate} Hz.', flush=True)
    failures = 0
    use_keyterms = True
    while not stop.is_set():
        if not store.selected_player():
            select_player(store, preference)
        terms = recognition_names(store.selected_player())
        sent_keyterms = use_keyterms
        try:
            url = websocket_url(rate, terms if sent_keyterms else None)
            with connect(url, additional_headers={"xi-api-key": api_key}, open_timeout=10,
                         close_timeout=2, ping_interval=10, ping_timeout=5, compression=None, max_queue=16) as ws:
                first = json.loads(ws.recv(timeout=10))
                if first.get("message_type") != "session_started":
                    raise ScribeError(first.get("message_type", "invalid_request"))
                # Each reconnect starts fresh audio. No offline recordings are replayed.
                stream_session(ws, sd, device, rate, store, stop, terms)
                failures = 0
        except ScribeError as error:
            if sent_keyterms and error.kind in {"invalid_request", "input_error"}:
                use_keyterms = False
                print("ElevenLabs rejected the spell-name keyterms; continuing without them.", flush=True)
                continue
            print(str(error), flush=True)
            if error.kind in FATAL:
                raise
            failures += 1
        except InvalidStatus as error:
            status = error.response.status_code
            if sent_keyterms and status in {400, 422}:
                use_keyterms = False
                print(f"ElevenLabs HTTP {status} with spell-name keyterms; continuing without them.", flush=True)
                continue
            if status in {400, 401, 403}:
                raise RuntimeError(f"ElevenLabs HTTP {status}: check API key and Scribe access.") from None
            failures += 1
            print(f"ElevenLabs HTTP {status}; reconnecting.", flush=True)
        except Exception as error:
            failures += 1
            print(f"Speech connection ended ({type(error).__name__}); reconnecting with fresh audio.", flush=True)
        if failures >= 5:
            raise RuntimeError("Five speech connection failures. Check the microphone/network and restart.")
        if not stop.is_set() and failures:
            stop.wait(min(2 ** (failures - 1), 8))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--demo", action="store_true", help="Type spells; no microphone, key, or cloud calls")
    parser.add_argument("--devices", action="store_true", help="List microphone device numbers")
    parser.add_argument("--device", type=int, help="Input microphone device number")
    parser.add_argument("--player", help="Studio player name or UserId; prompts when ambiguous")
    parser.add_argument("--rate", type=int, choices=[8000, 16000, 22050, 24000, 44100, 48000])
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--team-test", action="store_true", help="Pair your microphone with a player through the shared HTTPS relay")
    parser.add_argument("--relay", help="HTTPS relay base URL (implies --team-test)")
    parser.add_argument("--pair", help="Temporary pairing code from the game's Voice Connect panel")
    args = parser.parse_args()
    if args.devices:
        import sounddevice as sd
        print(sd.query_devices())
        return
    api_key = ""
    print("KNIGHT HACKS IX — " + ("TEAM TEST VOICE CONSOLE" if args.team_test or args.relay else "LOCAL STUDIO VOICE CONSOLE"), flush=True)
    if not args.demo:
        print("While active, microphone audio is sent to ElevenLabs Scribe Realtime.", flush=True)
        api_key = getpass.getpass("ElevenLabs API key (hidden; not saved): ").strip()
        if not api_key:
            raise ValueError("Enter an ElevenLabs Speech-to-Text API key.")
    stop, server = threading.Event(), None
    if args.team_test or args.relay:
        from relay_client import RelayArenaStore, validate_url
        settings = ROOT.parent / "team-relay.json"
        saved = json.loads(settings.read_text()).get("url", "") if settings.exists() else ""
        url = validate_url(args.relay or input(f'HTTPS relay URL [{saved}]: ').strip() or saved)
        settings.write_text(json.dumps({"url": url}) + "\n", encoding="utf-8")
        code = args.pair or input("Pairing code from your game's Voice Connect panel: ").strip()
        store = RelayArenaStore(url, code, stop)
        print(f"Shared relay: {url}", flush=True)
    else:
        token = bridge_token()
        store = ArenaStore()
        try:
            server = ThreadingHTTPServer(("127.0.0.1", args.port), handler_for(store, token))
        except OSError:
            raise RuntimeError(f"Port {args.port} is already in use. Stop the old helper before starting this console.") from None
        server.daemon_threads = True
        threading.Thread(target=server.serve_forever, daemon=True).start()
        print(f"Studio connection: http://127.0.0.1:{server.server_port} (loopback only)", flush=True)
    try:
        select_player(store, args.player)
        if args.demo:
            words = WordReceiver(store)
            print("DEMO: type a spell name, then Enter. Type quit to stop. No microphone or API calls.", flush=True)
            shown = None
            while not stop.is_set():
                names = recognition_names(store.selected_player())
                if names != shown:
                    print(loadout_summary(store.selected_player()), flush=True)
                    shown = names
                text = input("> ")
                if text.strip().lower() in {"quit", "exit"}:
                    break
                if not store.selected_player():
                    select_player(store, args.player)
                words.event({"message_type": "committed_transcript", "text": text})
        else:
            recognize(api_key, store, stop, args.device, args.rate, args.player)
    except (KeyboardInterrupt, EOFError):
        print("\nStopping microphone and Studio connection.", flush=True)
    finally:
        stop.set()
        with store.condition:
            store.version += 1
            store.condition.notify_all()
        if server:
            server.shutdown()
            server.server_close()
        else:
            store.close()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nStopped.")
    except (ValueError, RuntimeError) as error:
        print(f"Error: {error}", flush=True)
        raise SystemExit(1)
