# Permanent relay at voice-relay.blazinblaze.net

The relay URL is printed after `HTTPS RELAY:` in the host console and appears in the game's **Voice Connect** panel. Temporary `trycloudflare.com` URLs change whenever the tunnel restarts. A named Cloudflare Tunnel routes your own hostname to the local relay, keeping the address the same across restarts. See [Cloudflare's tunnel setup guide](https://developers.cloudflare.com/tunnel/get-started/).

The host is configured for **https://voice-relay.blazinblaze.net**. Public HTTPS health and two independent companion command routes were verified on October 11, 2026. The instructions below describe how to recreate that setup; other players only need TeamTest.cmd, the URL, and their own pairing code.

## One-time Cloudflare setup

1. In the [Cloudflare dashboard](https://dash.cloudflare.com/), select the account containing **blazinblaze.net**, then open **Networking → Tunnels**. Some accounts show this under **Zero Trust → Networks → Tunnels / Connectors**. Create a **cloudflared** tunnel named **kh9-voice-relay**.
2. Choose Windows. Copy the tunnel's installation command. **You do not need to run the service installer**; your companion already includes cloudflared. The tunnel token is the long `eyJ...` value in that command. [Cloudflare token instructions](https://developers.cloudflare.com/tunnel/reference/tunnel-tokens/).
3. On the host PC, run **companion\ConfigureStableRelay.cmd**. Accept **https://voice-relay.blazinblaze.net** and paste the tunnel token or the full installation command into the hidden prompt. It saves the token in a Git-ignored local file. This is separate from your ElevenLabs key and from VOICE_RELAY_SERVER_TOKEN; do not paste it into chat or Roblox.
4. Add a **Published application** route in that tunnel. Use subdomain **voice-relay**, domain **blazinblaze.net**, and Service URL **http://127.0.0.1:8790**. If the dashboard presents separate fields, choose Type **HTTP** and URL **127.0.0.1:8790**. Leave the path empty. The existing relay authenticates game and companion requests; the route needs to accept those API clients without an interactive browser login.
5. If Cloudflare requires a connected tunnel before adding the route, run **StopRelay.cmd** once, then **HostRelay.cmd**, and finish step 4 while it runs. It waits up to 10 minutes for the route and DNS updates. If it times out, finish the route and run HostRelay again; the configured permanent hostname stays the same.

## Switch the game and companions once

1. After the setup above, run **StopRelay.cmd**, then **HostRelay.cmd**. HostRelay now automatically uses the configured named tunnel. It confirms that the public hostname reaches this exact relay before publishing the new game config.
2. In Roblox Creator Dashboard → your experience → Secrets, change **VOICE_RELAY_SERVER_TOKEN → Domain** to **voice-relay.blazinblaze.net**. Keep the existing value; RelaySecretSetup.cmd can copy it locally if needed. You can skip updating the temporary hostname when switching directly to this permanent one.
3. The host updates the generated **VoiceRelayConfig** with the permanent URL. Commit/save the synced scripts and publish to the shared kh9 place. If Studio isn't syncing, copy the contents of **companion\bridge\VoiceRelayConfig.generated.luau** into **ServerScriptService.VoiceArena.VoiceRelayConfig**. Restart Team Test.
4. Each computer runs **TeamTest.cmd**, enters **https://voice-relay.blazinblaze.net**, and pairs with its own avatar's current code. Other computers may still remember the old temporary URL until they enter this new one.

After this switch, ordinary host restarts keep the same relay URL and Roblox secret domain. Keep the host PC awake and HostRelay running during gameplay. A permanent hostname does not keep the local relay running when its host is off.

## Files and modes

- **ConfigureStableRelay.cmd**: one-time hostname and hidden Cloudflare token setup.
- **HostRelay.cmd**: automatically selects the permanent tunnel when configured; otherwise retains the existing quick tunnel.
- **HostRelay.cmd --quick**: explicitly use a temporary tunnel again. This also requires switching the game config and Roblox secret domain back to its newly printed hostname.
- **StopRelay.cmd**: stop this PC's relay and tunnel.

The tunnel token is stored in **companion\bridge\cloudflare-tunnel.token**; local hostname settings are in **cloudflare.local.json**. Both are ignored by Git. The token is passed to cloudflared through its [token-file option](https://developers.cloudflare.com/tunnel/reference/run-parameters/), so it does not appear in process command-line arguments. The existing Roblox server credential remains in the ignored host settings and Roblox Secrets store; it is never embedded in game source.

If network DNS still remembers the hostname as missing, the host and companion retry its hostname lookup using Cloudflare DNS over HTTPS. This applies only to the relay connection and preserves HTTPS hostname/certificate checks. System network settings are unchanged.
