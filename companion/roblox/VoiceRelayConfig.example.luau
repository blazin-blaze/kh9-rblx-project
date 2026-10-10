-- Copy to ServerScriptService.VoiceArena.VoiceRelayConfig (ModuleScript).
-- HostRelay.cmd generates a configured version. Add the credential to Roblox's Secrets store.
return {
  Enabled = false, -- false preserves Start.cmd / Demo.cmd and local Studio playtests.
  Url = "https://YOUR-RELAY.trycloudflare.com",
  SecretName = "VOICE_RELAY_SERVER_TOKEN", -- Creator Dashboard > your game > Secrets; not an ElevenLabs key.
}
