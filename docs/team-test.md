# Multiplayer voice spells in Team Test

The HTTPS relay lets every player use a separate ElevenLabs console and microphone while joining the same game. The existing spells, avatar-facing aim, AI generation, ultimate loudness, movement, cooldowns, and match rules are unchanged.

## Host once, connect on every computer

1. On one Windows PC, double-click `companion/HostRelay.cmd`. It starts the relay on loopback port **8790** and exposes only that service through a temporary HTTPS Cloudflare Tunnel. The first launch downloads the official cloudflared executable and verifies its SHA-256. Keep this PC awake and the host running throughout the match.
2. On the host PC, double-click **RelaySecretSetup.cmd**. It copies the relay's credential to your clipboard and shows the current domain. In **Creator Dashboard → kh9 roblox project → Secrets → Create Secret**, set Name to **VOICE_RELAY_SERVER_TOKEN**, paste the copied Value, and set Domain to the printed hostname. This is the relay credential, not an ElevenLabs key. Roblox's game Secrets store is available to **Team Test**, and prevents script source from exposing the credential.
3. Before starting Team Test, apply the generated ModuleScript `companion/bridge/VoiceRelayConfig.generated.luau` as `ServerScriptService.VoiceArena.VoiceRelayConfig`. It contains the relay URL and the **secret's name**, never the credential. The host also writes the equivalent ignored repo file under `game/scripts/ServerScriptService/VoiceArena`. If Studio syncs repo files, this module updates automatically. Otherwise copy the generated module's contents into Studio. Save/commit the changed scripts to your shared place so Team Test runs the updated version. This does not require making the game public.
4. The host starts **Team Test**. Other collaborators join that same session through Studio's Play control.
5. Each player opens **Voice Connect** in the upper-right corner of the game. It shows the relay URL and **that player's** five-minute pairing code.
6. Each player double-clicks `companion/TeamTest.cmd` on their own computer. Enter their ElevenLabs key at the hidden prompt, the shared relay URL, and their own pairing code. The URL is remembered locally; API keys, pairing codes, and client credentials are kept in memory.
7. Equip spells normally. The console follows your three activation names and your custom ultimate word automatically. Every recognized word still prints on its own line. The Voice Connect panel collapses once the game confirms your microphone connection.

Only the host needs the tunnel. Every companion makes outbound HTTPS connections to the same relay. Players do not need port forwarding, a website, a local Studio server, or their own tunnel. One companion binds to one player's UserId and game session; choosing a username never grants control of another player.

## Launchers

- `HostRelay.cmd`: start the shared relay and HTTPS tunnel on one PC.
- `StopRelay.cmd`: stop this PC's host and tunnel. Ctrl+C in HostRelay's console also stops them.
- `RelaySecretSetup.cmd`: copy the existing host credential for the owner's one-time Roblox Secrets-store setup; it never puts the credential in game source.
- `TeamTest.cmd`: microphone + ElevenLabs + paired multiplayer relay.
- `TeamTestDemo.cmd`: same pairing and game-command path, but type spell names without an API key or microphone.
- `Start.cmd` / `Demo.cmd`: existing direct localhost mode. For this mode, set `VoiceRelayConfig.Enabled = false` before starting a solo Studio playtest.

Optional arguments:

```bat
TeamTest.cmd --relay https://your-host.trycloudflare.com --device 22
TeamTestDemo.cmd --relay https://your-host.trycloudflare.com
HostRelay.cmd --port 8790
```

## Restarts and reconnecting

Cloudflare's temporary hostname changes whenever HostRelay starts a new tunnel. The generated Studio config and `companion/team-relay.json` update to the new URL. Apply the new config before restarting Team Test, **update the secret's allowed Domain** in Creator Dashboard to the new hostname, and tell the other players to enter the new URL. The host credential stays the same between restarts. A stable domain/named tunnel can replace the temporary tunnel later without changing spell mechanics or the relay protocol.

For a **solo Studio test using the relay**, add the same name/value/domain under **File → Experience Settings → Security → Local Secrets**. Local playtests use Local Secrets; Team Test uses the game-level Creator Dashboard Secrets store. Direct localhost Start.cmd mode needs neither of these secrets.

Pairing survives avatar respawns and loadout changes while the companion stays connected. Commands for an old character or old loadout are discarded. Leaving the game, restarting Team Test, restarting the relay, or going offline for 30 seconds invalidates pairing; restart TeamTest.cmd with the new code. **New Pairing Code** in the game revokes the existing companion and generates a fresh code. Stop the previous console before pairing a replacement.

## Troubleshooting

- **Relay offline:** ensure HostRelay is running, the generated ModuleScript matches the current URL, the correct Secrets store contains VOICE_RELAY_SERVER_TOKEN with that hostname allowed, and Studio's Allow HTTP Requests setting is enabled. Check `companion/bridge/tunnel.log` and the Studio Output window. “Can't find secret with given key” means the required game/local secret is missing.
- **Wrong code/expired code:** use the code shown for your avatar in the current shared session. If another console already claimed it, stop that console or click New Pairing Code.
- **Companion paired but no cast:** inspect confirmed words and the normal game's cooldown/status feedback. Custom names are sent from the game, and a loadout change reconnects ElevenLabs keyterms automatically.
- **Only one PC can join:** everyone must join the same Team Test session in the same shared place. Separate solo playtests are separate rooms even when they share the relay.
- **Ultimate beam is weak:** the existing Roblox microphone/voice chat RMS requirement still applies. ElevenLabs triggers the name, while Roblox measures loudness.
- **Tunnel fails on hackathon Wi-Fi:** the host needs outbound Cloudflare tunnel connectivity. The host uses HTTP/2 to avoid depending on QUIC/UDP. Check firewall/proxy policies or use a network that permits the tunnel.

## Credentials and protocol

`VoiceRelayConfig` contains only a URL and the name **VOICE_RELAY_SERVER_TOKEN**. The randomly generated credential is stored in Roblox's Secrets store and the host's ignored `relay.local.json`; it is never in game source, ReplicatedStorage, or Git. The server uses `HttpService:GetSecret():AddPrefix("Bearer ")` directly in the authentication header. Pairing returns a separate random per-player credential, which cannot read another player's loadout or register a game server. The public localhost development token is never used to authenticate the shared relay.

The game polls `/v1/game/poll` with its roster, loadouts, ultimate words, character life IDs, ACKs, and clock. Companions pair through `/v1/pair`, refresh their own state through `/v1/client/state`, and send matched commands to `/v1/client/command`. The relay derives identity from the pairing credential, validates the current loadout revision, stamps commands using the game server's clock, caps queues, debounces duplicates, and expires commands after 2.5 seconds. ACKs and command IDs preserve retry deduplication. The game retains authoritative spell, cooldown, direction, and character-life checks.

Microphone audio and the ElevenLabs API key go directly from each companion to ElevenLabs. The relay receives only matched spell commands and game state, and keeps them in memory. It serves JSON, not a website. Pairing credentials and transcripts are not logged. The tunnel log contains operational connection messages only.

## Verification

All 32 Python tests passed, covering the existing individual-word and speech path plus two independent companion clients, per-player/per-room isolation, custom ultimate routing, ACK/deduplication/TTL, clock differences between PCs, respawn and rename invalidation, pairing reset and expiry, authenticated HTTP endpoints, and long-poll wakeup. The live public HTTPS tunnel also passed a two-companion test: one custom ultimate and one custom spell routed to their respective test players. Actual multi-computer Team Test and live ElevenLabs audio must be exercised after the Roblox secret is configured and the updated shared place is saved.

References: [Roblox Team Test](https://create.roblox.com/docs/studio/testing-modes), [Roblox HTTP requests](https://create.roblox.com/docs/cloud-services/http-service), [Cloudflare Quick Tunnels](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/).
