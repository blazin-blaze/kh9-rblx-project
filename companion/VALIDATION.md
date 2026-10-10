# Console revision validation

- Nine Python tests passed for individual word delivery, cumulative-transcript deduplication, revised tentative spell rejection, filtering, final-only commands, queue expiry, retry ACKs, respawn invalidation, room isolation, long-poll wakeup, HTTP authentication, absence of a website, audio payloads, and simulated native microphone input through a real local WebSocket.
- The portable runtime successfully imports sounddevice 0.5.5 and websockets 17.2. Windows microphone enumeration succeeds. The default microphone supports mono PCM16 at 16000 Hz; checking format support did not record audio.
- The actual console Demo mode connected to kh9 roblox project through localhost HttpService. It automatically selected the live Studio player. The client HUD showed the local console connection and selected player without a pair code.
- After fixing the automated aiming setup, a typed Flame cast reduced the target from 500 HP to 460 HP, including all five burn ticks; its fire effect was cleaned up.
- A typed Freeze cast created the ice prison and frozen state. The frozen state cleared after five seconds.
- A typed Wave cast pushed the target approximately 43.49 studs; the wave was cleaned up after its five-second duration. The unchanged spell implementation's solidity was verified in the prior live test.
- The transport is guarded to Studio playtests and accepts only a loopback HTTP URL. API credentials are prompted inside the console and not saved by this version.

Live ElevenLabs transcription still requires the user's real API key and spoken audio. Tests used a simulated speech service, typed Demo input, and microphone format inspection.
