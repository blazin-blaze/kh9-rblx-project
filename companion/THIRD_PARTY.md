# Portable runtime and dependencies

The Windows x64 Python runtime and selected libraries were copied from the user-provided VoskStudioBridge reference into this separate package. The reference folder was not modified. No Vosk recognition model is included or used here.

- Python 3.12.10: https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip — PSF license included in runtime/LICENSE.txt.
- sounddevice 0.5.5: https://pypi.org/project/sounddevice/ — MIT; metadata/license under runtime/Lib/site-packages/sounddevice-0.5.5.dist-info, with PortAudio binaries/licenses under _sounddevice_data.
- websockets 17.2: https://pypi.org/project/websockets/ — BSD; metadata/license under runtime/Lib/site-packages/websockets-17.2.dist-info.
- cffi 2.1.1 and pycparser 3.1: supporting packages for native microphone access; included metadata/license files are under their corresponding dist-info directories.

The console architecture and bounded audio-streaming flow follow the existing scribe_bridge.py reference. The new command queue, Studio player binding, and integration with Flame/Freeze/Wave are implemented for this package.
