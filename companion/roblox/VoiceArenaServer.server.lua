-- ServerScriptService.VoiceArena.VoiceArenaServer (Script)
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(script.Parent.SpellConfig)
if not RunService:IsStudio() then
  warn("VoiceArena console bridge runs only in local Studio playtests.")
  return
end
local Spells = require(script.Parent.SpellService)
local folder = ReplicatedStorage:FindFirstChild("VoiceArena") or Instance.new("Folder")
folder.Name = "VoiceArena"; folder.Parent = ReplicatedStorage
local function remote(name)
  local r = folder:FindFirstChild(name) or Instance.new("RemoteEvent")
  r.Name = name; r.Parent = folder; return r
end
local aimRemote, feedback, testRemote = remote("Aim"), remote("Feedback"), remote("StudioCast")
local aims, lastAim, lives, voiceActive = {}, {}, {}, {}
local session = game.JobId ~= "" and game.JobId or HttpService:GenerateGUID(false)
local bridgeUrl = Config.BridgeUrl or "http://127.0.0.1:8787"
assert(string.match(bridgeUrl,"^http://127%.0%.0%.1:%d+$"), "VoiceArena requires a loopback console URL")
local connected = false
local function state(player)
  feedback:FireClient(player, { kind = "bridge", connected = connected, voiceActive = voiceActive[player] or false,
    configured = bridgeUrl ~= "", studio = RunService:IsStudio() and Config.EnableStudioKeyboard })
end
local function characterAdded(player)
  lives[player] = HttpService:GenerateGUID(false); aims[player] = nil; voiceActive[player] = nil
  task.delay(1, function() if player.Parent then state(player) end end)
end
local function playerAdded(player)
  player.CharacterAdded:Connect(function() characterAdded(player) end)
  if player.Character then characterAdded(player) end
end
Players.PlayerAdded:Connect(playerAdded)
for _, player in ipairs(Players:GetPlayers()) do playerAdded(player) end
Players.PlayerRemoving:Connect(function(player)
  aims[player] = nil; lastAim[player] = nil; lives[player] = nil; voiceActive[player] = nil
end)
aimRemote.OnServerEvent:Connect(function(player, direction)
  local now = os.clock()
  if now - (lastAim[player] or 0) < 0.08 then return end
  lastAim[player] = now
  if typeof(direction) ~= "Vector3" then return end
  for _, v in ipairs({direction.X,direction.Y,direction.Z}) do if v ~= v or math.abs(v) > 2 then return end end
  if direction.Magnitude < 0.5 or direction.Magnitude > 1.5 then return end
  aims[player] = { direction = direction.Unit, at = now }
end)
local function cast(player, spell)
  local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
  if not root then return end
  local aim = aims[player]
  local direction = aim and os.clock() - aim.at < 1 and aim.direction or root.CFrame.LookVector
  local ok, value = Spells.Cast(player, spell, direction)
  feedback:FireClient(player, { kind = "cast", spell = spell, ok = ok, value = value })
end
local lastTest = {}
testRemote.OnServerEvent:Connect(function(player, spell)
  if not RunService:IsStudio() or not Config.EnableStudioKeyboard or type(spell) ~= "string" then return end
  local now = os.clock()
  if now - (lastTest[player] or 0) < 0.1 then return end
  lastTest[player] = now; cast(player, spell)
end)
Players.PlayerRemoving:Connect(function(p) lastTest[p] = nil end)

task.spawn(function()
  local ack, processed = {}, {}
  local failures = 0
  while true do
    if bridgeUrl == "" or Config.BridgeToken == "" then
      connected = false; task.wait(2); continue
    end
    local roster = {}
    for _, player in ipairs(Players:GetPlayers()) do
      table.insert(roster, { userId = player.UserId, name = player.Name, life = lives[player] or "loading" })
    end
    local ok, data = pcall(function()
      local response = HttpService:RequestAsync({
        Url = bridgeUrl .. "/v1/poll", Method = "POST",
        Headers = { ["content-type"] = "application/json", ["authorization"] = "Bearer " .. Config.BridgeToken },
        Body = HttpService:JSONEncode({ session = session, players = roster, ack = ack, waitSeconds = 8 }),
        Timeout = 12,
      })
      if not response.Success then error("Bridge HTTP " .. response.StatusCode) end
      local decoded = HttpService:JSONDecode(response.Body)
      assert(type(decoded) == "table" and type(decoded.players) == "table" and type(decoded.commands) == "table", "Invalid bridge response")
      return decoded
    end)
    if ok then
      local wasConnected = connected; connected = true; failures = 0; ack = {}
      for _, info in ipairs(data.players) do
        if type(info) == "table" and type(info.userId) == "number" and type(info.voiceActive) == "boolean" then
          local player = Players:GetPlayerByUserId(info.userId)
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
            -- Both processes run on this PC. Measure command age, not the idle long-poll duration.
            local age = type(command.createdAt) == "number" and DateTime.now().UnixTimestampMillis - command.createdAt or math.huge
            if player and lives[player] == command.life and type(command.spell) == "string" and
              age >= -1000 and age < 2500 then
                print("[VoiceArena command] " .. command.spell)
                cast(player, command.spell)
              end
          end
        end
      end
      for id, time in pairs(processed) do if os.clock() - time > 60 then processed[id] = nil end end
    else
      failures += 1
      if connected or failures == 1 then
        warn("[VoiceArena] Bridge unavailable; verify URL, token, HTTP permission, and running service.")
        connected = false
        for _, player in ipairs(Players:GetPlayers()) do state(player) end
      end
    end
    task.wait(ok and Config.PollInterval or math.min(8, 2 ^ math.min(failures,3)))
  end
end)
