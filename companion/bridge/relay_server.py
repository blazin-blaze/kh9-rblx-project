"""Authenticated, in-memory multiplayer spell relay. Expose only through an HTTPS tunnel."""
import argparse
import hashlib
import hmac
import json
import math
import secrets
import threading
import time
import uuid
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from console_bridge import ArenaStore, DEFAULT_ULTIMATE, detect_commands, spell_names, ultimate_word

PAIR_TTL = 300
CLIENT_TTL = 30
ACTIVE_TTL = 6
CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


class RelayError(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message


def player_revision(player):
    data = [player["life"], spell_names(player), ultimate_word(player)]
    return hashlib.sha256(json.dumps(data, separators=(",", ":")).encode()).hexdigest()[:24]


class RelayStore(ArenaStore):
    def __init__(self, clock=time.monotonic, wall=time.time):
        super().__init__(clock, wall)
        self.pairings, self.clients = {}, {}
        self.attempts = deque()

    def _cleanup(self):
        super()._cleanup()
        now = self.clock()
        for token, client in list(self.clients.items()):
            if (now - client["seen"] > CLIENT_TTL or
                    client["userId"] not in self.rooms.get(client["session"], {}).get("players", {})):
                del self.clients[token]
        for key in list(self.pairings):
            if key[1] not in self.rooms.get(key[0], {}).get("players", {}):
                del self.pairings[key]

    def _client_for(self, session, user_id):
        return next((c for c in self.clients.values() if (c["session"], c["userId"]) == (session, user_id)), None)

    def _pairing(self, session, user_id):
        key = (session, user_id)
        if self._client_for(*key):
            self.pairings.pop(key, None)
            return None
        pair = self.pairings.get(key)
        if not pair or pair["expires"] <= self.clock():
            existing = {p["code"] for p in self.pairings.values()}
            while True:
                code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(10))
                if code not in existing:
                    break
            pair = {"code": code, "expires": self.clock() + PAIR_TTL}
            self.pairings[key] = pair
        return pair

    def game_poll(self, request):
        session, players = request.get("session"), request.get("players")
        wait = request.get("waitSeconds", 8)
        server_time = request.get("serverTimeMs")
        resets = request.get("resetPairings", [])
        if (type(server_time) not in (int, float) or not math.isfinite(server_time) or
                server_time <= 0 or type(wait) not in (int, float) or not math.isfinite(wait) or not 0 <= wait <= 8 or
                not isinstance(resets, list) or len(resets) > 32 or any(type(v) is not int for v in resets)):
            raise ValueError("Invalid poll settings")
        with self.condition:
            old = self.rooms.get(session, {}).get("players", {}).copy() if isinstance(session, str) else {}
            super().poll(session, players, request.get("ack"), wait=0)
            room = self.rooms[session]
            # Commands use the game server's clock, never a companion PC's clock.
            room["gameTimeMs"], room["gameMono"] = server_time, self.clock()
            roster_changed = old != room["players"]
            for user_id in resets:
                for token, client in list(self.clients.items()):
                    if (client["session"], client["userId"]) == (session, user_id):
                        del self.clients[token]
                self.pairings.pop((session, user_id), None)
            for user_id in room["players"]:
                self._pairing(session, user_id)
            # A rename or respawn invalidates queued commands rather than falling back to an old slot.
            room["commands"] = [c for c in room["commands"] if
                                c.get("revision") == player_revision(room["players"][c["userId"]])]
            version, deadline = self.version, self.clock() + wait
            self.condition.notify_all()
            while not roster_changed and not resets and not room["commands"] and version == self.version and self.clock() < deadline:
                self.condition.wait(timeout=max(0, deadline - self.clock()))
            room["updated"] = self.clock()
            self._cleanup()
            result = []
            for user_id in room["players"]:
                client = self._client_for(session, user_id)
                pair = self._pairing(session, user_id)
                result.append({"userId": user_id, "voiceActive": bool(client and self.clock() - client["seen"] < ACTIVE_TTL),
                               "pairCode": pair["code"] if pair else "",
                               "pairExpiresIn": max(0, pair["expires"] - self.clock()) if pair else 0})
            return {"players": result, "commands": [{k: v for k, v in c.items() if k not in {"mono", "revision"}}
                                                      for c in room["commands"]]}

    def pair(self, raw_code):
        if not isinstance(raw_code, str) or len(raw_code) > 30:
            raise RelayError(400, "Enter the pairing code shown in the game")
        code = raw_code.upper().replace("-", "").replace(" ", "")
        with self.condition:
            self._cleanup()
            now = self.clock()
            while self.attempts and self.attempts[0] < now - 60:
                self.attempts.popleft()
            if len(self.attempts) >= 120:
                raise RelayError(429, "Too many pairing attempts; wait a minute")
            self.attempts.append(now)
            key = next((k for k, p in self.pairings.items() if p["expires"] > now and hmac.compare_digest(p["code"], code)), None)
            if not key:
                raise RelayError(404, "Pairing code expired or not found; check the code in the game")
            token = secrets.token_urlsafe(32)
            self.clients[token] = {"session": key[0], "userId": key[1], "seen": now,
                                   "lastSpell": {}, "seenIds": {}}
            del self.pairings[key]
            self.version += 1
            self.condition.notify_all()
            return {"token": token, "player": self._snapshot(self.clients[token])}

    def _authenticate(self, token):
        self._cleanup()
        client = self.clients.get(token)
        if not client:
            raise RelayError(401, "Pairing ended. Get a new code from the game")
        if self.clock() - client["seen"] >= ACTIVE_TTL:
            self.version += 1
            self.condition.notify_all()
        client["seen"] = self.clock()
        return client

    def _snapshot(self, client):
        player = self.rooms[client["session"]]["players"][client["userId"]]
        return {**player, "session": client["session"], "revision": player_revision(player)}

    def client_state(self, token):
        with self.condition:
            return {"player": self._snapshot(self._authenticate(token))}

    def unpair(self, token):
        with self.condition:
            client = self.clients.pop(token, None)
            if client:
                room = self.rooms.get(client["session"])
                if room:
                    room["commands"] = [c for c in room["commands"] if c["userId"] != client["userId"]]
            self.version += 1
            self.condition.notify_all()
            return {"ok": True}

    def command(self, token, request):
        command_id, spell = request.get("id"), request.get("spell")
        age = request.get("ageMs", 0)
        if (not isinstance(command_id, str) or not 1 <= len(command_id) <= 100 or not isinstance(spell, str) or
                type(age) not in (int, float) or not math.isfinite(age) or not 0 <= age < 1500):
            raise RelayError(400, "Invalid or stale command")
        with self.condition:
            client = self._authenticate(token)
            player = self._snapshot(client)
            if request.get("revision") != player["revision"]:
                raise RelayError(409, "Loadout or character changed; refresh before casting")
            now = self.clock()
            client["seenIds"] = {k: v for k, v in client["seenIds"].items() if now - v < 60}
            if command_id in client["seenIds"]:
                return {"ok": True, "duplicate": True}
            names = spell_names(player)
            if spell != DEFAULT_ULTIMATE and spell not in names:
                raise RelayError(400, "Spell is not in this player's loadout")
            room = self.rooms[client["session"]]
            if len(room["commands"]) >= 128 or len(client["seenIds"]) >= 512:
                raise RelayError(429, "Command queue full")
            if now - client["lastSpell"].get(spell, -float("inf")) < 0.75:
                return {"ok": True, "debounced": True}
            client["lastSpell"][spell], client["seenIds"][command_id] = now, now
            command = {"id": command_id, "userId": player["userId"], "life": player["life"], "spell": spell,
                       "revision": player["revision"], "mono": now - age / 1000,
                       "createdAt": round(room["gameTimeMs"] + (now - room["gameMono"]) * 1000 - age)}
            if spell != DEFAULT_ULTIMATE:
                command["slot"] = names.index(spell) + 1
            room["commands"].append(command)
            self.version += 1
            self.condition.notify_all()
            return {"ok": True}


def handler_for_relay(store, server_token, stop_callback=None, stop_token=None):
    host_instance_id = uuid.uuid4().hex
    class Handler(BaseHTTPRequestHandler):
        instance_id = host_instance_id
        def log_message(self, *args):
            pass  # Never log codes, tokens, or request bodies.

        def respond(self, status, payload):
            data = json.dumps(payload, allow_nan=False).encode()
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
                return self.respond(200, {"ok": True, "mode": "relay", "protocol": 1, "instanceId": self.instance_id})
            self.respond(404, {"error": "No website; run TeamTest.cmd"})

        def do_POST(self):
            try:
                self.connection.settimeout(12)
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= 65536:
                    raise RelayError(413, "Invalid body size")
                token = self.headers.get("Authorization", "").removeprefix("Bearer ")
                if self.path == "/v1/host/stop" and stop_callback and stop_token:
                    if not hmac.compare_digest(token, stop_token):
                        raise RelayError(401, "Invalid host credential")
                    self.rfile.read(length)
                    self.respond(200, {"ok": True})
                    stop_callback()
                    return
                if self.path == "/v1/game/poll" and not hmac.compare_digest(token, server_token):
                    raise RelayError(401, "Invalid game server credential")
                if self.path not in {"/v1/game/poll", "/v1/pair", "/v1/client/state", "/v1/client/command", "/v1/client/unpair"}:
                    raise RelayError(404, "Not found")
                request = json.loads(self.rfile.read(length))
                if not isinstance(request, dict):
                    raise RelayError(400, "Expected an object")
                if self.path == "/v1/game/poll":
                    result = store.game_poll(request)
                elif self.path == "/v1/pair":
                    result = store.pair(request.get("code"))
                elif self.path == "/v1/client/state":
                    result = store.client_state(token)
                elif self.path == "/v1/client/command":
                    result = store.command(token, request)
                else:
                    result = store.unpair(token)
                self.respond(200, result)
            except RelayError as error:
                self.respond(error.status, {"error": error.message})
            except (ValueError, TypeError, AttributeError, OSError):
                self.respond(400, {"error": "Invalid request"})
    return Handler


def load_secret(path):
    if path.exists():
        token = json.loads(path.read_text())["serverToken"]
        if not isinstance(token, str) or len(token) < 32:
            raise ValueError("Invalid relay server credential")
        return token
    token = secrets.token_urlsafe(48)
    path.write_text(json.dumps({"serverToken": token}) + "\n", encoding="utf-8")
    return token


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8790)
    args = parser.parse_args()
    token = load_secret(Path(__file__).with_name("relay.local.json"))
    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler_for_relay(RelayStore(), token))
    server.daemon_threads = True
    print(f"Relay listening on 127.0.0.1:{args.port}. Use HostRelay.cmd for HTTPS.", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
