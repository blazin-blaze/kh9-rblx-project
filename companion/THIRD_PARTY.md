# Portable runtime and dependencies

- cloudflared 2026.10.0: https://github.com/cloudflare/cloudflared/releases/tag/2026.10.0 — Apache-2.0. HostRelay.cmd downloads the Windows amd64 executable when needed and verifies SHA-256 `86aee4017b26625cee8484c113558f48effa4cd47f7aa05fcf425604e5d2b23c`. Official license: https://github.com/cloudflare/cloudflared/blob/2026.10.0/LICENSE. The downloaded binary is ignored by Git.

The Windows x64 Python runtime and selected libraries were copied from the user-provided VoskStudioBridge reference into this separate package. The reference folder was not modified. No Vosk recognition model is included or used here.

- Python 3.12.10: https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip — PSF license included in runtime/LICENSE.txt.
- sounddevice 0.5.5: https://pypi.org/project/sounddevice/ — MIT; metadata/license under runtime/Lib/site-packages/sounddevice-0.5.5.dist-info, with PortAudio binaries/licenses under _sounddevice_data.
- websockets 17.2: https://pypi.org/project/websockets/ — BSD; metadata/license under runtime/Lib/site-packages/websockets-17.2.dist-info.
- cffi 2.1.1 and pycparser 3.1: supporting packages for native microphone access; included metadata/license files are under their corresponding dist-info directories.

The console architecture and bounded audio-streaming flow follow the existing scribe_bridge.py reference. The new command queue, Studio player binding, and integration with Flame/Freeze/Wave are implemented for this package.
