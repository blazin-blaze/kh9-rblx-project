-- ServerScriptService.VoiceArena.SpellConfig (ModuleScript)
return {
  BridgeUrl = "http://127.0.0.1:8787", -- Console helper on this PC; Studio playtests only.
  BridgeToken = "472d5c40354bb828f40425e12db348bee87ef7031087e2bcacea7306c2b0faa0", -- Must match BRIDGE_TOKEN in bridge/.env. SERVER ONLY.
  PollInterval = 0.15, -- Pause after each spell batch; idle polls wait up to 8 seconds.
  EnableStudioKeyboard = false, -- Spells are voice-only; keyboard casting is disabled.
  GlobalCooldown = 0.35,
  Flame = { Cooldown = 2, Damage = 20, BurnDamage = 4, BurnSeconds = 5, Speed = 100, Range = 110 },
  Freeze = { Cooldown = 7, Duration = 5, Speed = 90, Range = 100 },
  Wave = { Cooldown = 8, Duration = 5, Speed = 18, Width = 24, Height = 12, Depth = 5, PushSpeed = 30 },
  -- AI spells made in the loadout screen (SpellForge + SpellFx).
  Custom = { Cooldown = 4 },
  Gemini = {
    -- Tried in order until one answers; the first that works is remembered.
    Models = { "gemini-3.8-flash", "gemini-3-flash-preview", "gemini-flash-latest" },
    Thinking = "low",      -- Gemini 3 thinking level; set to nil to send no thinking config.
    MaxAttempts = 3,       -- Generate, then up to 2 repair rounds if the code fails validation.
    MinInterval = 2,       -- Seconds between generations per player.
    HedgeAfter = 10,       -- If a model hasn't answered after this many seconds, also ask the next one.
  },
  Ultimate = {
    ChargeSeconds = 10, Duration = 5, Range = 180,
    MinRadius = 1.5, MaxRadius = 6.5, MaxDamagePerSecond = 70,
    NoiseFloor = 0.008, FullPowerRms = 0.18, SampleTimeout = 0.4,
  },
}
