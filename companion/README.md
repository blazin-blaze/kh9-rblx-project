# Voice Arena — local Studio console

Implemented in **kh9 roblox project** (place ID **73454620887951**). This version follows the console flow in your VoskStudioBridge reference: a double-click launcher, hidden API-key entry, native microphone capture, and a localhost Studio command queue.

## Run it

1. Double-click **Start.cmd** in this folder.
2. Paste your ElevenLabs Speech-to-Text API key at the hidden console prompt and press Enter. Nothing is shown while you type or paste. The console keeps the key in memory and does not save it.
3. Press **Play** in Roblox Studio. The console automatically selects the player when there is only one. If several players are running locally, choose the player number in the console.
4. In the game's **Set Your Spells** screen, name your 3 spells and pick a preset or describe an AI spell for each, then press **Begin**.
5. Keep the console open, aim with your mouse in Roblox, and say one of your spell names, then pause briefly.
6. Press **Ctrl+C** in the console to stop the microphone, ElevenLabs session, and local bridge.

## Custom spell names (Set Your Spells)

The game sends each player's 3 spell names to this console on every poll. The console then:

- passes the names to ElevenLabs Scribe as **keyterms**, so invented words like "Zorblax" are transcribed correctly (it reconnects automatically when the names change, because keyterms are set per session; if ElevenLabs rejects them, it carries on without them);
- casts when a confirmed phrase contains a name: exact words, two words joined together ("zor blax"), or, for names of 7+ letters, one misheard letter (two for 10+ letters). Short names must match exactly, so "frame" never casts "Flame";
- sends `{ spell, slot }`; the game resolves the spoken name to that player's slot.

Until a player presses Begin, the names are Flame, Freeze and Wave. In Studio, **F / G / H** cast slots 1 / 2 / 3 and **L** reopens the spell screen.

AI spells are written by Gemini against a sandboxed `fx` API (`ServerScriptService.VoiceArena.SpellFx`), validated with a dry run, repaired automatically if they fail, and replaced by an improvised spell if Gemini can't produce working code. The Gemini key lives in the server-only `ServerScriptService.VoiceArena.Secrets` module, and `ServerScriptService.LoadStringEnabled` must stay ticked.

The portable Windows x64 Python runtime and dependencies are included. No Python installation, npm command, browser, pairing code, publishing, or tunnel is needed. HTTP requests are already enabled in the Studio place. Save the place after reviewing the updates.

The game's HUD displays **Local voice console connected** and **Console microphone controls your player**. Respawns keep the selected player's identity and refresh the character life ID automatically. Restarting a playtest waits for the player to reconnect.

## Test without an API key

Double-click **Demo.cmd**, press Play in Studio, then type a spell name and press Enter:

```text
> Flame
[Spell] Flame
> Freeze
[Spell] Freeze
> Wave
[Spell] Wave
```

Demo mode uses the same spell filter and Studio HTTP path; it captures no audio and calls no cloud API. Type `quit` to exit. Run one helper at a time, since both launchers use port **8787**. Studio keyboard testing also remains available: **F** Flame, **G** Freeze, **H** Wave.

## Microphones and player selection

**ListMicrophones.cmd** lists Windows audio devices. The default input microphone is used unless you specify another device. The helper tries mono PCM16 at 16 kHz, falling back to another ElevenLabs-supported rate when needed.

From a command prompt in this folder, examples are:

```bat
Start.cmd --device 22
Start.cmd --player Player1
Start.cmd --device 22 --player Player1 --rate 48000
Demo.cmd --player Player2
```

One running console controls one player through one microphone. Other players can still participate using Studio test keys. This kit does not coordinate separate Studio game instances on separate PCs. To voice-control both players in one shared local server with separate microphones, a second independent microphone/recognition worker would need to be added.

## Spells

| Spell | Behavior | Cooldown |
| --- | --- | --- |
| Flame | Aimed fire projectile. 20 impact damage, then 4 damage per second for five seconds. Further hits refresh a single burn. | 2 seconds |
| Freeze | Aimed ice projectile. Immobilizes the target for five seconds and restores its original movement/anchor settings. Further hits refresh the freeze. | 7 seconds |
| Wave | Solid 24 × 12 × 5 stud water wall. Travels horizontally in the aimed direction at 18 studs/second for five seconds, pushes opponents, and blocks projectiles. | 8 seconds |

The original arena, cover, two spawns, practice target, and server-authoritative spell scripts are retained.

## Connection

```text
Windows microphone
  -> local Python console
  -> ElevenLabs Scribe v2 Realtime
  -> final transcript with an exact spell word
  -> localhost command queue
  <- Studio server's HttpService long poll
  -> server validates player/life/cooldown and executes the spell
```

The console binds only to **127.0.0.1:8787**. It serves JSON for the Studio connection and does not serve a website. Roblox's HttpService initiates the request; it does not expose an incoming HTTP endpoint. The server waits up to eight seconds for new commands and receives a spell immediately when the queue wakes, then pauses 0.15 seconds before the next request. Idle wait time does not delay a queued spell.

Every recognized word is displayed on its own console line, rather than as a sentence. New words from live partials appear as `[Word tentative]`; confirmed words that have not already appeared are printed as `[Word]`. Repeated cumulative partials and their final transcript do not reprint the same word occurrence. Actual repeated words still get separate lines. Each confirmed word is sent separately through the spell filter. Ordinary words and tentative guesses do not queue commands. Only confirmed exact words Flame, Freeze, or Wave cast. Case and punctuation are ignored; “flames” and “heatwave” do not match. Say one spell per utterance to allow the server's global cooldown.

Commands expire after 2.5 seconds. ACKs and server deduplication prevent duplicate delivery, and a character life ID rejects commands from a previous respawn. The transport token in `bridge/.env` matches the server-only `SpellConfig` module; it is separate from the ElevenLabs key and is already configured. The console does not read an ElevenLabs key from that file.

The Studio reader exits outside Studio and only accepts a loopback URL. The key remains in the console process and is sent only to ElevenLabs for authentication. While the microphone is active, audio is streamed to ElevenLabs and consumes your account's API usage. This helper does not record audio or save transcripts to disk.

## Sources and reinstalling

- `bridge/console_bridge.py`: console prompt, microphone capture, ElevenLabs connection, spell filtering, and localhost HTTP queue.
- `roblox/SpellConfig.lua`: server-only localhost URL/token and spell settings.
- `roblox/SpellService.lua`: spell mechanics and visuals.
- `roblox/VoiceArenaServer.server.lua`: Studio-only HTTP reader, player validation, deduplication, and aim handling.
- `roblox/VoiceArenaClient.client.lua`: mouse aim, HUD, and Studio test keys.
- `install-studio.lua`: run its contents in Studio's Command Bar in edit mode to restore the four scripts. It creates the arena only if missing.

Local source edits do not automatically update Studio; the current changes were applied through MCP. The installer restores this package's settings, so preserve any custom configuration first.

## Verification

Nine automated Python tests passed: individual word delivery, cumulative-transcript deduplication, tentative-word revisions, exact matching, final-only casting, ACK/retry handling, debounce, TTL, respawn/leave invalidation, room isolation, spell-only long-poll wakeup, HTTP authentication, absence of a browser UI, correct audio payload, and simulated native microphone audio through the ElevenLabs WebSocket protocol.

The portable runtime imports successfully, the microphone device list works, and the default microphone accepts mono PCM16 at 16 kHz. Device checking did not capture audio. The prior live Studio spell tests verified all three mechanics.

Live console-to-Studio delivery was exercised with Demo mode. Real ElevenLabs transcription remains to be exercised with your key and spoken audio.

## Troubleshooting

- **Port already in use:** close the old Vosk/Scribe/browser helper or previous console with Ctrl+C. The older reference defaults to 8765; this new kit uses 8787.
- **Waiting for Studio:** press Play in the matching place and ensure Allow HTTP Requests is enabled. If you used `--player`, check that name/UserId.
- **Voice console offline:** verify Start.cmd is running and the game's bridge URL/token match the supplied configuration. Failures back off up to eight seconds.
- **API error:** use a key with Speech-to-Text/Scribe Realtime access and sufficient credits. The console stops on authentication/configuration/quota failures and retries transient failures with fresh audio.
- **Microphone error:** run ListMicrophones.cmd, select an input device with `--device`, and allow microphone access for desktop apps in Windows settings.
- **No spell:** inspect the final transcript, pause briefly after the spell name, and check the game's cooldown feedback. Cover and moving waves can block projectiles.

References: [ElevenLabs Realtime API](https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime), [Roblox HTTP requests](https://create.roblox.com/docs/cloud-services/http-service). See THIRD_PARTY.md for runtime and dependency licenses.

## Repository location and local configuration

This folder is the working companion source for `kh9-rblx-project`. Edit companion code here from now on.

`Start.cmd` and `Demo.cmd` optionally load an ignored `LocalConfig.cmd`. On the current PC it sets `VOICE_ARENA_TOKEN_FILE` to the existing credential file outside the repository. That file was retained at `C:\Users\joshu\Documents\Codex\2026-10-10\x20\outputs\voice-arena\bridge\.env`; do not delete it while this configuration is in use.

On another PC, copy `bridge/.env.example` to the ignored `bridge/.env` and provide the private token matching Studio's `SpellConfig.BridgeToken`. The ElevenLabs API key is still entered at the hidden console prompt and is not saved.

## Ultimate

Say **ultimate** when the game HUD is ready. This reserved command works alongside any loadout. Roblox microphone RMS controls the five-second death beam; ElevenLabs recognizes the activation word. See [Ultimate setup and tuning](../docs/ultimate.md). Restart this console after updating.

## First run from GitHub

No .env file is needed before the first launch. Start.cmd automatically creates bridge/.env with the repository loopback-only Studio development token. Enter your ElevenLabs key only at the hidden prompt; it is never saved. If you change BRIDGE_TOKEN, use the same value in the game server-only SpellConfig.BridgeToken.
