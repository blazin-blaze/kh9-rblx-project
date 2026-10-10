import json
from pathlib import Path
from urllib.request import Request, urlopen

root = Path(__file__).resolve().parent
try:
    state = json.loads((root / "host-state.json").read_text())
    token = json.loads((root / "relay.local.json").read_text())["hostStopToken"]
    request = Request(f'http://127.0.0.1:{state["port"]}/v1/host/stop', b'{}',
                      {"Content-Type": "application/json", "Authorization": "Bearer " + token})
    with urlopen(request, timeout=5):
        print("Stopping this computer's relay host and HTTPS tunnel.")
except (OSError, ValueError, KeyError):
    print("No running relay host found on this computer.")
