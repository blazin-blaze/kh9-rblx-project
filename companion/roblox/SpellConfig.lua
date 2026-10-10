-- ServerScriptService.VoiceArena.SpellConfig (ModuleScript)
return {
  BridgeUrl = "http://127.0.0.1:8787", -- Console helper on this PC; Studio playtests only.
  BridgeToken = "472d5c40354bb828f40425e12db348bee87ef7031087e2bcacea7306c2b0faa0", -- Must match BRIDGE_TOKEN in bridge/.env. SERVER ONLY.
  PollInterval = 0.15, -- Pause after each spell batch; idle polls wait up to 8 seconds.
  EnableStudioKeyboard = true, -- F/G/H are accepted only in Studio.
  GlobalCooldown = 0.35,
  Flame = { Cooldown = 2, Damage = 20, BurnDamage = 4, BurnSeconds = 5, Speed = 100, Range = 110 },
  Freeze = { Cooldown = 7, Duration = 5, Speed = 90, Range = 100 },
  Wave = { Cooldown = 8, Duration = 5, Speed = 18, Width = 24, Height = 12, Depth = 5, PushSpeed = 30 },
}
