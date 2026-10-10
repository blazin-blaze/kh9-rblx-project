-- ServerScriptService.VoiceArena.VoiceArenaServer (Script)
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(script.Parent.SpellConfig)
local relayModule = script.Parent:FindFirstChild("VoiceRelayConfig")
local RelayConfig = relayModule and require(relayModule) or { Enabled = false }
local relayMode = RelayConfig.Enabled == true
if not RunService:IsStudio() and not relayMode then
  warn("VoiceArena requires the HTTPS relay for a shared Team Test session.")
  return
end
local Spells = require(script.Parent.SpellService)
local folder = ReplicatedStorage:FindFirstChild("VoiceArena") or Instance.new("Folder")
folder.Name = "VoiceArena"; folder.Parent = ReplicatedStorage
local function remote(name)
  local r = folder:FindFirstChild(name) or Instance.new("RemoteEvent")
  r.Name = name; r.Parent = folder; return r
end
local feedback, testRemote = remote("Feedback"), remote("StudioCast")
local lives, voiceActive = {}, {}
local session = game.JobId ~= "" and game.JobId or HttpService:GenerateGUID(false)
local bridgeUrl = relayMode and string.gsub(RelayConfig.Url or "", "/+$", "") or (Config.BridgeUrl or "http://127.0.0.1:8787")
local bridgeToken = not relayMode and Config.BridgeToken or nil
if relayMode then
  assert(string.match(bridgeUrl, "^https://[%w%.%-]+:?%d*$") and #bridgeUrl <= 250, "VoiceArena relay requires an HTTPS base URL")
  assert(type(RelayConfig.SecretName) == "string" and #RelayConfig.SecretName > 0, "VoiceArena relay requires a Roblox Secrets store name")
else
  assert(string.match(bridgeUrl, "^http://127%.0%.0%.1:%d+$"), "Local voice mode requires a loopback console URL")
end
folder:SetAttribute("VoiceRelayEnabled", relayMode)
local connected = false
local pairings, resetPairings, lastPairRequest = {}, {}, {}
if relayMode then
  local pairingRemote = folder:FindFirstChild("GetVoicePairing") or Instance.new("RemoteFunction")
  pairingRemote.Name = "GetVoicePairing"; pairingRemote.Parent = folder
  pairingRemote.OnServerInvoke = function(player, reset)
    local now = os.clock()
    if reset == true and now - (lastPairRequest[player] or -math.huge) >= 3 then
      lastPairRequest[player] = now
      resetPairings[player.UserId] = true
      pairings[player] = nil
    end
    local info = pairings[player] or {}
    return { url = bridgeUrl, connected = connected, voiceActive = voiceActive[player] or false,
      code = info.code or "", expiresIn = math.max(0, (info.expiresAt or 0) - now) }
  end
end
local function state(player)
  feedback:FireClient(player, { kind = "bridge", connected = connected, voiceActive = voiceActive[player] or false,
    configured = bridgeUrl ~= "", relay = relayMode, studio = RunService:IsStudio() and Config.EnableStudioKeyboard })
end
local function characterAdded(player)
  lives[player] = HttpService:GenerateGUID(false); voiceActive[player] = nil
  task.delay(1, function() if player.Parent then state(player) end end)
end
local function playerAdded(player)
  player.CharacterAdded:Connect(function() characterAdded(player) end)
  if player.Character then characterAdded(player) end
end
Players.PlayerAdded:Connect(playerAdded)
for _, player in ipairs(Players:GetPlayers()) do playerAdded(player) end
Players.PlayerRemoving:Connect(function(player)
  lives[player] = nil; voiceActive[player] = nil
  pairings[player] = nil; lastPairRequest[player] = nil; resetPairings[player.UserId] = nil
end)
-- Every spell reads the avatar's server-observed facing; cursor and camera position cannot steer casts.
local function facingDirection(player)
  local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
  return root and root.CFrame.LookVector or nil
end
-- Spell loadouts: names are the voice activation words; slots hold a preset or an AI spell.
local Loadout = require(script.Parent.Loadout)
Loadout.Init(folder, feedback, facingDirection)
local Ultimate = require(script.Parent.UltimateService)
Ultimate.Init(folder, facingDirection)
-- ref: a spoken name or slot number; slot is a fallback when the name no longer matches.
-- The bridge sends "Ultimate" when it hears a player's own ultimate word (Loadout.UltimateWord).
local function cast(player, ref, slot)
  if folder:GetAttribute("MatchState") == "Victory" then return end
  if type(ref) == "string" and string.lower(ref) == "ultimate" then
    local ok, value = Ultimate.Cast(player)
    feedback:FireClient(player, { kind = "cast", spell = "Ultimate", ok = ok, value = value })
    return
  end
  local direction = facingDirection(player)
  if not direction then return end
  local def, index = Loadout.Resolve(player, ref)
  if not def and slot then def, index = Loadout.Resolve(player, slot) end
  if not def then
    feedback:FireClient(player, { kind = "cast", spell = tostring(ref), ok = false, value = "No spell called " .. tostring(ref) })
    return
  end
  local ok, value = Loadout.CastDef(player, def, direction)
  feedback:FireClient(player, { kind = "cast", spell = def.name, slot = index, ok = ok, value = value })
end
local lastTest = {}
testRemote.OnServerEvent:Connect(function(player, spell)
  if not RunService:IsStudio() or not Config.EnableStudioKeyboard or (type(spell) ~= "string" and type(spell) ~= "number") then return end
  local now = os.clock()
  if now - (lastTest[player] or 0) < 0.1 then return end
  lastTest[player] = now; cast(player, spell)
end)
Players.PlayerRemoving:Connect(function(p) lastTest[p] = nil end)

task.spawn(function()
  local ack, processed = {}, {}
  local failures = 0
  while true do
    if bridgeUrl == "" or bridgeToken == "" then
      connected = false; task.wait(2); continue
    end
    local roster = {}
    for _, player in ipairs(Players:GetPlayers()) do
      table.insert(roster, { userId = player.UserId, name = player.Name, life = lives[player] or "loading", spells = Loadout.Names(player),
        ultimate = Loadout.UltimateWord(player) })
    end
    local resets = {}
    for userId in pairs(resetPairings) do table.insert(resets, userId) end
    local ok, data = pcall(function()
      local authorization = relayMode and HttpService:GetSecret(RelayConfig.SecretName):AddPrefix("Bearer ") or ("Bearer " .. bridgeToken)
      local response = HttpService:RequestAsync({
        Url = bridgeUrl .. (relayMode and "/v1/game/poll" or "/v1/poll"), Method = "POST",
        Headers = { ["content-type"] = "application/json", ["authorization"] = authorization },
        Body = HttpService:JSONEncode({ session = session, players = roster, ack = ack, waitSeconds = 8,
          serverTimeMs = DateTime.now().UnixTimestampMillis, resetPairings = resets }),
        Timeout = 12,
      })
      if not response.Success then error("Bridge HTTP " .. response.StatusCode) end
      local decoded = HttpService:JSONDecode(response.Body)
      assert(type(decoded) == "table" and type(decoded.players) == "table" and type(decoded.commands) == "table", "Invalid bridge response")
      return decoded
    end)
    if ok then
      local wasConnected = connected; connected = true; failures = 0; ack = {}
      for _, userId in ipairs(resets) do resetPairings[userId] = nil end
      for _, info in ipairs(data.players) do
        if type(info) == "table" and type(info.userId) == "number" and type(info.voiceActive) == "boolean" then
          local player = Players:GetPlayerByUserId(info.userId)
          if relayMode and player and type(info.pairCode) == "string" and #info.pairCode <= 20 then
            local ttl = type(info.pairExpiresIn) == "number" and math.clamp(info.pairExpiresIn, 0, 300) or 0
            pairings[player] = { code = info.pairCode, expiresAt = os.clock() + ttl }
          end
          if player and (voiceActive[player] ~= info.voiceActive or not wasConnected) then voiceActive[player] = info.voiceActive; state(player) end
        end
      end
      for index, command in ipairs(data.commands) do
        if index > 128 then break end
        if type(command) == "table" and type(command.id) == "string" and #command.id <= 100 then
          table.insert(ack, command.id)
          if not processed[command.id] then
            processed[command.id] = os.clock()
            local player = type(command.userId) == "number" and Players:GetPlayerByUserId(command.userId)
            -- The relay stamps commands using this game server's poll clock; PC clocks may differ.
            local age = type(command.createdAt) == "number" and DateTime.now().UnixTimestampMillis - command.createdAt or math.huge
            local slot = type(command.slot) == "number" and command.slot or nil
            local spoken = type(command.spell) == "string" and command.spell or nil
            if player and lives[player] == command.life and (spoken or slot) and
              age >= -1000 and age < 2500 then
                print("[VoiceArena command] " .. tostring(spoken or ("slot " .. tostring(slot))))
                cast(player, spoken or slot, slot)
              end
          end
        end
      end
      for id, time in pairs(processed) do if os.clock() - time > 60 then processed[id] = nil end end
    else
      failures += 1
      if connected or failures == 1 then
        warn(relayMode and "[VoiceArena] HTTPS relay unavailable; check HostRelay.cmd, VoiceRelayConfig, the VOICE_RELAY_SERVER_TOKEN secret, and HTTP permission." or "[VoiceArena] Bridge unavailable; verify URL, token, HTTP permission, and running service.")
        connected = false
        for _, player in ipairs(Players:GetPlayers()) do
          voiceActive[player] = false
          state(player)
        end
      end
    end
    task.wait(ok and Config.PollInterval or math.min(8, 2 ^ math.min(failures,3)))
  end
end)
