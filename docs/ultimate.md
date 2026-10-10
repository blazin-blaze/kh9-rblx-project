# Ultimate death beam

Run `companion/Start.cmd`, join the Studio playtest, equip your spells, and wait for the purple ULTIMATE HUD to say READY. Say **ultimate**, then sustain your voice for the five-second beam. Aim with the mouse while your character stays in place. The next ten-second charge starts when the beam finishes. Respawning also starts a fresh ten-second charge.

The companion recognizes the exact reserved word `ultimate` with any three-spell loadout. Ultimate does not consume a loadout slot and cannot be assigned as a custom spell name. Tentative transcription never activates it. Restart the companion after updating its code.

## Roblox microphone

`UltimateClient` connects the local player's `AudioDeviceInput` to an `AudioAnalyzer` through a `Wire`. It reads RMS volume locally, with spectrum analysis disabled, and sends a small RMS sample to the server ten times per second. It uses Roblox's default input when present; a measurement-only input is created if the engine has not provided one. The fallback is not connected to speakers.

Keep `VoiceChatService.UseAudioApi` set to Enabled. Enable microphone/voice chat in the experience's Communication settings, use an eligible account, and unmute Roblox's microphone. The HUD explicitly shows when it is waiting for audio or when the input is muted. Normal Studio test accounts and some local test modes may not have usable voice input; use a Studio session with microphone access. The presence of an AudioDeviceInput alone does not prove live capture is working.

ElevenLabs handles the activation word only; Roblox handles loudness. No Roblox microphone audio is sent by this ultimate feature to the companion. If Roblox supplies no volume, the visible beam remains at minimum size and does no damage.

## Tuning

`game/scripts/ServerScriptService/VoiceArena/SpellConfig.luau` contains `Ultimate` settings:

- ChargeSeconds: 10; Duration: 5.
- Range: 180 studs; radius: 0.4 to 12 studs (0.8 to 24 studs across). Size scales with power raised to 1.4, keeping weaker beams thin. The core, glow, muzzle, impact orb, and collision radius all follow the live size; stronger beams also emit brighter light.
- MaxDamagePerSecond: 70, scaled by microphone power.
- NoiseFloor: 0.008; FullPowerRms: 0.18. Adjust these for the microphone used in the demo. Full strength does not require uncomfortable screaming.
- SampleTimeout: 0.4 seconds. Missing samples immediately reduce power to zero after this interval.

The server validates numeric range and finite samples, rejects samples for an old character, caps packet rate, caps power, owns cooldowns and collision checks, and prevents casting other spells during the channel. Because Roblox AudioAnalyzer values exist only on the client, reported loudness remains client-supplied and is not an anti-cheat proof of actual speech.

The beam damages living Humanoid models, including test dummies, and can pierce multiple targets until blocked by the arena or a solid Wave. Additional sight checks keep the wide beam from damaging through cover. Existing match rules exclude spectators. Death, respawn, leaving a match, or Freeze interrupts the channel. Shared MovementLocks preserve movement correctly when Freeze overlaps the ultimate.

## Validation

The companion's 13 tests cover the new exact Ultimate command, rejection of tentative text and similar words, custom loadouts, character-life routing, normal spell matching, and HTTP behavior.

Controlled runtime tests in Studio verified: zero silence damage; approximately 25.9 damage at RMS 0.03 versus 75.7 damage at RMS 0.18 over equal 1.1-second intervals; zero damage through cover; stale samples reaching zero power; caster immobility; repeated-cast rejection; a five-second lifetime; movement restoration; and a fresh ten-second cooldown. Loudness values in these gameplay checks were simulated. Real human microphone sensitivity must be checked using the HUD meter.

Canonical game sources are in `game/scripts`. The old `companion/roblox` files and `companion/install-studio.lua` are historical snapshots; do not reinstall those over the current Studio scripts.

Official API references: https://create.roblox.com/docs/reference/engine/classes/AudioAnalyzer and https://create.roblox.com/docs/reference/engine/classes/VoiceChatService.
