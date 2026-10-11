"""Configure a permanent Cloudflare Tunnel hostname for the local spell relay."""
import getpass
import json
import re
from pathlib import Path
from urllib.parse import urlsplit

from relay_client import validate_url

ROOT = Path(__file__).resolve().parent
DEFAULT_URL = "https://voice-relay.blazinblaze.net"
SETTINGS = "cloudflare.local.json"
TOKEN_FILE = "cloudflare-tunnel.token"


def stable_url(value):
    value = value.strip()
    if "://" not in value:
        value = "https://" + value
    url = validate_url(value)
    parsed = urlsplit(url)
    if parsed.port is not None or not re.fullmatch(r"[a-z0-9][a-z0-9.-]*\.[a-z]{2,}", parsed.hostname or ""):
        raise ValueError("Enter a public HTTPS hostname without a port")
    return "https://" + parsed.hostname


def tunnel_token(value):
    value = value.strip()
    if re.fullmatch(r"[A-Za-z0-9_+/=-]{64,10000}", value):
        return value
    match = re.search(r"(?<![\w])eyJ[A-Za-z0-9_+/=-]{61,9997}(?![\w])", value)
    if match:
        return match.group(0)
    raise ValueError("Paste the Cloudflare Tunnel token or its installation command, not an ElevenLabs key")


def save_settings(url, token):
    url, token = stable_url(url), tunnel_token(token)
    (ROOT / TOKEN_FILE).write_text(token + "\n", encoding="utf-8")
    (ROOT / SETTINGS).write_text(json.dumps({"url": url}) + "\n", encoding="utf-8")
    return url


def load_settings(force_quick=False):
    path = ROOT / SETTINGS
    if force_quick or not path.exists():
        return None
    url = stable_url(json.loads(path.read_text(encoding="utf-8"))["url"])
    token_file = ROOT / TOKEN_FILE
    if not token_file.exists():
        raise ValueError("Run ConfigureStableRelay.cmd to enter the Cloudflare Tunnel token")
    tunnel_token(token_file.read_text(encoding="utf-8"))
    return {"url": url, "token_file": token_file}


def main():
    print("PERMANENT VOICE RELAY SETUP", flush=True)
    print("In Cloudflare > Networking > Tunnels, create a cloudflared tunnel named kh9-voice-relay.", flush=True)
    print("Copy its tunnel token from the installation command. This is separate from both ElevenLabs and the Roblox relay secret.", flush=True)
    url = stable_url(input(f"Permanent HTTPS relay URL [{DEFAULT_URL}]: ").strip() or DEFAULT_URL)
    token = getpass.getpass("Cloudflare Tunnel token or install command (hidden): ")
    url = save_settings(url, token)
    print("Saved locally; the tunnel token is ignored by Git and never written into Roblox scripts.", flush=True)
    print(f"In Cloudflare add a Published application route for {urlsplit(url).hostname}.", flush=True)
    print("Service URL: http://127.0.0.1:8790", flush=True)
    print("Then run StopRelay.cmd once, followed by HostRelay.cmd. It will use the permanent tunnel automatically.", flush=True)
    print("Cloudflare may require a connected tunnel before you can finish the route. Start HostRelay.cmd while adding it; the host waits up to 10 minutes for route/DNS updates.", flush=True)
    print("Once the host confirms the permanent URL, set the Roblox relay secret's Domain to this hostname, save the generated game config, and restart Team Test.", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, EOFError) as error:
        print(f"Stable relay setup: {error}", flush=True)
        raise SystemExit(1)
    except KeyboardInterrupt:
        print("Setup cancelled.", flush=True)
