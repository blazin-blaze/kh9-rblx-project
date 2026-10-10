-- ServerScriptService.VoiceArena.SpellConfig (ModuleScript)
return {
  BridgeUrl = "http://127.0.0.1:8787", -- Console helper on this PC; Studio playtests only.
  BridgeToken = "kh9-localhost-bridge-dev-token-v1", -- Must match BRIDGE_TOKEN in bridge/.env. SERVER ONLY.
  PollInterval = 0.15, -- Pause after each spell batch; idle polls wait up to 8 seconds.
  EnableStudioKeyboard = false, -- Spells are voice-only; keyboard casting is disabled.
  GlobalCooldown = 0.35,
  Flame = { Cooldown = 2, Damage = 20, BurnDamage = 4, BurnSeconds = 5, Speed = 100, Range = 110 },
  Freeze = { Cooldown = 7, Duration = 10, Speed = 90, Range = 100 },
  Wave = { Cooldown = 8, Duration = 5, Speed = 20, Width = 36, Height = 12, Depth = 5, PushSpeed = 30 },
  -- HitPadding: studs added to the cone's radius for the target's body width, so targets close to the
  -- caster (where the cone is thin) or at its edge still get hit.
  Lightning = { Cooldown = 6, Duration = 3, Range = 30, Radius = 15, TickSeconds = 0.1, TickDamage = 5, HitPadding = 1.5 },
  Deflect = { Cooldown = 10, Duration = 3, Radius = 6 },
  -- AI spells made in the loadout screen (SpellForge + SpellFx).
  Custom = { Cooldown = 4 },
  Gemini = {
    -- Tried in order until one answers; the first that works is remembered. Each model has its own
    -- Google quota, so the Flash-Lite backups keep spells working when the bigger models are rate-limited
    -- (429) or overloaded (503). A model that fails that way is benched for a while (see SpellForge).
    Models = {
      "gemini-3.8-flash", "gemini-3.5-flash", "gemini-3-flash-preview", "gemini-3.7-flash", -- best quality
      "gemini-3.5-flash-lite", "gemini-flash-lite-latest", "gemini-3.1-flash-lite",          -- lower-tier backups
    },
    Thinking = "low",      -- Gemini 3 thinking level; set to nil to send no thinking config.
    MaxAttempts = 3,       -- Generate, then up to 2 repair rounds if the code fails validation.
    MinInterval = 2,       -- Seconds between generations per player.
    HedgeAfter = 10,       -- If a model hasn't answered after this many seconds, also ask the next one.
  },
  Ultimate = {
    ChargeSeconds = 10, Duration = 5, Range = 180,
    TurnSpeedDegrees = 45, -- Slow beam steering: a 90-degree turn takes two seconds.
    MinRadius = 0.4, MaxRadius = 12, MaxDamagePerSecond = 70,
    NoiseFloor = 0.008, FullPowerRms = 0.18, SampleTimeout = 0.4,
  },
}
