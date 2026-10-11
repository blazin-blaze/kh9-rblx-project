"""Per-player relay adapter for the existing ElevenLabs console and word receiver."""
import json
import threading
import time
import uuid
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request

from relay_dns import NoRedirect, relay_opener

from console_bridge import detect_commands, loadout_summary, spell_names, ultimate_word


class RelayClientError(RuntimeError):
    def __init__(self, status, message):
        self.status = status
        super().__init__(message)


def validate_url(url, allow_local=False):
    url = url.strip().rstrip("/")
    parsed = urlsplit(url)
    local = allow_local and parsed.scheme == "http" and parsed.hostname == "127.0.0.1"
    if ((parsed.scheme != "https" and not local) or not parsed.hostname or parsed.username or parsed.password or
            parsed.path or parsed.query or parsed.fragment):
        raise ValueError("Enter the relay's HTTPS base URL, without a path")
    return url


class RelayHTTP:
    def __init__(self, url, allow_local=False):
        self.url = validate_url(url, allow_local)
        self.opener = relay_opener(self.url)

    def post(self, path, data, token=None):
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = "Bearer " + token
        request = Request(self.url + path, json.dumps(data, allow_nan=False).encode(), headers)
        try:
            with self.opener.open(request, timeout=5) as response:
                result = json.load(response)
                if not isinstance(result, dict):
                    raise RelayClientError(502, "Invalid relay response")
                return result
        except HTTPError as error:
            try:
                message = json.load(error).get("error", "Relay request failed")
            except (ValueError, AttributeError):
                message = "Relay request failed"
            raise RelayClientError(error.code, message) from None
        except (URLError, TimeoutError, OSError):
            raise RelayClientError(503, "Relay unavailable; check the host computer and HTTPS URL") from None
        except ValueError:
            raise RelayClientError(502, "Relay returned an invalid response") from None


class RelayArenaStore:
    def __init__(self, url, code, stop, allow_local=False):
        self.http = RelayHTTP(url, allow_local)
        self.condition = threading.Condition()
        self.version = 0
        self.stop = stop
        self.last_spell = {}
        self.player, self.token, self.updated = None, None, 0
        self.invalid = False
        paired = self.http.post("/v1/pair", {"code": code})
        self.token = paired["token"]
        self._update(paired["player"])
        print(f'Paired with {self.player["name"]} (UserId {self.player["userId"]}).', flush=True)
        print(loadout_summary(self.player), flush=True)
        self.worker = threading.Thread(target=self._heartbeat, daemon=True)
        self.worker.start()

    def _update(self, player):
        with self.condition:
            if self.player != player:
                self.last_spell.clear()
            self.player, self.updated = player, time.monotonic()
            self.condition.notify_all()

    def _heartbeat(self):
        offline = False
        while not self.stop.wait(0.75):
            try:
                self._update(self.http.post("/v1/client/state", {}, self.token)["player"])
                if offline:
                    print("Relay reconnected.", flush=True)
                    offline = False
            except RelayClientError as error:
                if error.status == 401:
                    self.invalid = True
                    with self.condition:
                        self.player = None
                    print(str(error), flush=True)
                    return
                if not offline:
                    print(str(error) + ". Microphone pauses if the connection stays unavailable.", flush=True)
                    offline = True

    def selected_player(self):
        with self.condition:
            if self.player and time.monotonic() - self.updated < 5:
                return dict(self.player)
            return None

    def ensure_selected(self, preference=None):
        if self.invalid:
            raise RuntimeError("Pairing ended. Restart TeamTest.cmd with the new code shown in the game.")
        while not self.selected_player() and not self.stop.wait(0.25):
            if self.invalid:
                raise RuntimeError("Pairing ended. Restart TeamTest.cmd with a new code.")

    def event(self, event):
        if event.get("message_type") != "committed_transcript":
            return []
        player = self.selected_player()
        if not player:
            return []
        emitted = []
        for spell in detect_commands(event.get("text"), spell_names(player), ultimate_word(player)):
            now = time.monotonic()
            if now - self.last_spell.get(spell, -float("inf")) < 0.75:
                continue
            command = {"id": str(uuid.uuid4()), "spell": spell, "revision": player["revision"], "ageMs": 0}
            for attempt in range(2):
                command["ageMs"] = (time.monotonic() - now) * 1000
                if command["ageMs"] >= 1500:
                    break
                try:
                    result = self.http.post("/v1/client/command", command, self.token)
                    if result.get("ok") and not result.get("debounced"):
                        self.last_spell[spell] = time.monotonic()
                        emitted.append(spell)
                    break
                except RelayClientError as error:
                    if error.status == 409:
                        print("Character or spell names changed; say the spell again.", flush=True)
                        break
                    if error.status < 500 or attempt == 1:
                        print(str(error), flush=True)
                        break
        return emitted

    def close(self):
        self.worker.join(6)
        try:
            self.http.post("/v1/client/unpair", {}, self.token)
        except RelayClientError:
            pass
