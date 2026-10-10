-- ServerScriptService.VoiceArena.SpellService (ModuleScript)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Config = require(script.Parent.SpellConfig)
local Locks = require(script.Parent.MovementLocks)
local Service = {}
local freezes, burns, cooldowns, globalCooldowns = {}, {}, {}, {}
local effects = workspace:FindFirstChild("VoiceArenaEffects") or Instance.new("Folder")
effects.Name = "VoiceArenaEffects"
effects.Parent = workspace
-- Visuals for the preset spells are drawn on every client by StarterPlayerScripts.PresetSpellFX.
-- The server keeps all gameplay (hits, damage, burn, freeze, wave push) and just announces events.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remoteFolder = ReplicatedStorage:FindFirstChild("VoiceArena") or Instance.new("Folder")
remoteFolder.Name = "VoiceArena"; remoteFolder.Parent = ReplicatedStorage
local presetFx = remoteFolder:FindFirstChild("PresetFx") or Instance.new("RemoteEvent")
presetFx.Name = "PresetFx"; presetFx.Parent = remoteFolder
local fxCounter = 0
local function fx(op) presetFx:FireAllClients(op) end

local function alive(character)
  if not character then return end
  local h = character:FindFirstChildOfClass("Humanoid")
  local root = character:FindFirstChild("HumanoidRootPart")
  if h and root and h.Health > 0 then return h, root end
end
local function part(name, size, color, cf, solid)
  local p = Instance.new("Part")
  p.Name = name; p.Size = size; p.Color = color; p.CFrame = cf
  p.Anchored = true; p.CanCollide = solid or false; p.CanTouch = false
  p.CanQuery = solid or false; p.Material = Enum.Material.Neon
  p.Parent = effects
  return p
end
local function targetFrom(hit)
  local model = hit:FindFirstAncestorOfClass("Model")
  while model and not model:FindFirstChildOfClass("Humanoid") do model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model") end
  return model
end
local function enemy(caster, character)
  return character and character ~= caster.Character and alive(character) ~= nil
end
local function flame(character, impactDamage, burnSeconds)
  local h, root = alive(character)
  if not h then return end
  burnSeconds = burnSeconds or Config.Flame.BurnSeconds
  if (impactDamage or Config.Flame.Damage) > 0 then h:TakeDamage(impactDamage or Config.Flame.Damage) end
  -- Recasting refreshes one burn; it never multiplies ticking tasks.
  if burns[h] then
    burns[h].untilTime = math.max(burns[h].untilTime, os.clock() + burnSeconds)
    fx({ op = "burn", target = character, duration = burns[h].untilTime - os.clock() })
    return
  end
  local state = { untilTime = os.clock() + burnSeconds }
  fx({ op = "burn", target = character, duration = burnSeconds })
  burns[h] = state
  task.spawn(function()
    local nextTick = os.clock() + 1
    while h.Parent and h.Health > 0 and root.Parent do
      task.wait(math.max(0, nextTick - os.clock()))
      if not h.Parent or h.Health <= 0 or not root.Parent then break end
      -- Tick at t=1,2,3,4,5 (including the fifth second).
      if nextTick > state.untilTime + 0.02 then break end
      h:TakeDamage(Config.Flame.BurnDamage)
      nextTick += 1
      if nextTick > state.untilTime + 0.02 then break end
    end
    fx({ op = "burnend", target = character }); burns[h] = nil
  end)
end
local function freeze(character, duration)
  local h, root = alive(character)
  if not h then return end
  duration = duration or Config.Freeze.Duration
  if freezes[h] then
    freezes[h].untilTime = math.max(freezes[h].untilTime, os.clock() + duration)
    fx({ op = "freeze", target = character, duration = freezes[h].untilTime - os.clock() })
    return
  end
  fx({ op = "freeze", target = character, duration = duration })
  local state = { untilTime = os.clock() + duration }
  freezes[h] = state
  character:SetAttribute("VoiceFrozen", true)
  Locks.Acquire(character, "Freeze")
  task.spawn(function()
    while h.Parent and root.Parent and h.Health > 0 and os.clock() < state.untilTime do task.wait(0.05) end
    Locks.Release(character, "Freeze")
    if character.Parent then character:SetAttribute("VoiceFrozen", false) end
    fx({ op = "thaw", target = character }); freezes[h] = nil
  end)
end
local function projectile(player, direction, spell)
  local _, root = alive(player.Character)
  if not root then return end
  local cfg = Config[spell]
  local position = root.Position + Vector3.new(0,1,0) + direction * 2
  local kind = string.lower(spell)
  fxCounter += 1
  local id = fxCounter
  fx({ op = kind .. "_cast", id = id, from = position, dir = direction, speed = cfg.Speed, range = cfg.Range, caster = player.UserId })
  -- The projectile itself is invisible on the server; solid waves still block it.
  local params = RaycastParams.new()
  params.FilterType = Enum.RaycastFilterType.Exclude
  params.FilterDescendantsInstances = {player.Character}
  params.RespectCanCollide = false
  local traveled = 0
  task.spawn(function()
    local hitPos, hitNormal, target
    while traveled < cfg.Range do
      local dt = RunService.Heartbeat:Wait()
      local distance = math.min(cfg.Speed * dt, cfg.Range - traveled)
      local step = direction * distance
      local hit = workspace:Spherecast(position, 0.8, step, params)
      if hit then
        hitPos, hitNormal = hit.Position, hit.Normal
        local character = targetFrom(hit.Instance)
        if enemy(player, character) then target = character end
        break
      end
      position += step; traveled += distance
    end
    fx({ op = kind .. "_impact", id = id, pos = hitPos or position, normal = hitNormal, hit = hitPos ~= nil, target = target })
    if target then if spell == "Flame" then flame(target) else freeze(target) end end
  end)
end
local function wave(player, direction)
  local _, root = alive(player.Character)
  if not root then return end
  -- A water wall remains upright and moves across the arena floor.
  local horizontal = Vector3.new(direction.X,0,direction.Z)
  if horizontal.Magnitude < 0.1 then horizontal = Vector3.new(root.CFrame.LookVector.X,0,root.CFrame.LookVector.Z) end
  horizontal = horizontal.Unit
  local cfg = Config.Wave
  local position = root.Position + horizontal * 7 + Vector3.new(0,3,0)
  local size = Vector3.new(cfg.Width, cfg.Height, cfg.Depth)
  -- Invisible solid wall (blocks projectiles); clients draw the actual wave around it.
  local wall = part("WaveWall", size, Color3.fromRGB(35,175,230), CFrame.lookAt(position, position + horizontal), true)
  wall.Transparency = 1; wall.CastShadow = false
  fxCounter += 1
  local waveId = fxCounter
  fx({ op = "wave_cast", id = waveId, from = position, dir = horizontal, speed = cfg.Speed, duration = cfg.Duration, size = size, caster = player.UserId })
  local overlap = OverlapParams.new(); overlap.FilterType = Enum.RaycastFilterType.Exclude
  overlap.FilterDescendantsInstances = {effects, player.Character}
  local started = os.clock()
  local pushed = {}
  local function pushInside()
    local seen = {}
    for _, hit in ipairs(workspace:GetPartBoundsInBox(wall.CFrame, size + Vector3.new(2,0,4), overlap)) do
      local character = targetFrom(hit)
      if character and not seen[character] and enemy(player, character) then
        seen[character] = true
        local h, targetRoot = alive(character)
        if h and not targetRoot.Anchored then
          if not pushed[targetRoot] then
            pushed[targetRoot] = true
            pcall(function() targetRoot:SetNetworkOwner(nil) end)
            fx({ op = "wave_hit", pos = targetRoot.Position, dir = horizontal, target = character })
          end
          -- Move caught targets ahead of the obstacle, with an arena raycast to avoid shoving through walls.
          local localPosition = wall.CFrame:PointToObjectSpace(targetRoot.Position)
          local ahead = wall.CFrame:PointToWorldSpace(Vector3.new(localPosition.X,localPosition.Y,-cfg.Depth/2-3))
          local displacement = ahead - targetRoot.Position
          local ray = RaycastParams.new(); ray.FilterType = Enum.RaycastFilterType.Exclude
          ray.FilterDescendantsInstances = {effects, character, player.Character}
          local blocker = workspace:Raycast(targetRoot.Position, displacement, ray)
          if not blocker then targetRoot.CFrame += displacement end
          targetRoot.AssemblyLinearVelocity = horizontal * cfg.PushSpeed + Vector3.new(0,math.max(2,targetRoot.AssemblyLinearVelocity.Y),0)
        end
      end
    end
  end
  task.spawn(function()
    local elapsed = 0
    while wall.Parent and elapsed < cfg.Duration do
      local dt = RunService.Heartbeat:Wait()
      dt = math.min(dt, cfg.Duration - elapsed)
      -- Substep to keep the swept obstacle from skipping targets on slow frames.
      local steps = math.max(1, math.ceil(dt * cfg.Speed / 1.5))
      for _ = 1, steps do
        position += horizontal * cfg.Speed * dt / steps
        wall.CFrame = CFrame.lookAt(position, position + horizontal)
        pushInside()
      end
      elapsed = os.clock() - started
    end
    fx({ op = "wave_end", id = waveId, pos = position, dir = horizontal, size = size })
    wall:Destroy()
    for targetRoot in pairs(pushed) do if targetRoot.Parent and not targetRoot.Anchored then pcall(function() targetRoot:SetNetworkOwnershipAuto() end) end end
  end)
end
local function lightning(player)
  local character=player.Character
  local _,root=alive(character)
  if not root then return end
  local cfg=Config.Lightning
  local inMatch=remoteFolder:GetAttribute("MatchState")=="Match"
  fxCounter+=1
  local id=fxCounter
  local endsAt=workspace:GetServerTimeNow()+cfg.Duration
  fx({op="lightning_cast",id=id,target=character,caster=player.UserId,endsAt=endsAt,range=cfg.Range,radius=cfg.Radius})
  local overlap=OverlapParams.new()
  overlap.FilterType=Enum.RaycastFilterType.Exclude
  overlap.FilterDescendantsInstances={character,effects}
  local ray=RaycastParams.new()
  ray.FilterType=Enum.RaycastFilterType.Exclude
  ray.RespectCanCollide=true
  task.spawn(function()
    while workspace:GetServerTimeNow()<endsAt do
      local phase=remoteFolder:GetAttribute("MatchState")
      if not player.Parent or player.Character~=character or not alive(character)
        or character:GetAttribute("VoiceFrozen") or phase=="Preparing" or phase=="Intro" or phase=="Victory"
        or (inMatch and (phase~="Match" or not player:GetAttribute("InMatch"))) then break end
      local basis=root.CFrame*CFrame.new(0,0.6,-2)
      local seen={}
      for _,hit in ipairs(workspace:GetPartBoundsInBox(basis*CFrame.new(0,0,-cfg.Range/2),
        Vector3.new(cfg.Radius*2,cfg.Radius*2,cfg.Range),overlap)) do
        local target=targetFrom(hit)
        if target and not seen[target] and enemy(player,target) then
          seen[target]=true
          local h,targetRoot=alive(target)
          local targetPlayer=Players:GetPlayerFromCharacter(target)
          local spectator=phase=="Match" and targetPlayer and not targetPlayer:GetAttribute("InMatch")
          local friendly=targetPlayer and not player.Neutral and not targetPlayer.Neutral and targetPlayer.Team==player.Team
          local point=basis:PointToObjectSpace(targetRoot.Position)
          local depth=-point.Z
          local radius=depth/cfg.Range*cfg.Radius
          if not spectator and not friendly and depth>=0 and depth<=cfg.Range
            and point.X*point.X+point.Y*point.Y<=radius*radius then
            ray.FilterDescendantsInstances={character,effects,target}
            if not workspace:Raycast(basis.Position,targetRoot.Position-basis.Position,ray) then
              h:TakeDamage(cfg.TickDamage)
            end
          end
        end
      end
      task.wait(cfg.TickSeconds)
    end
    fx({op="lightning_end",id=id})
  end)
end
function Service.Cast(player, spell, direction)
  if remoteFolder:GetAttribute("MatchState") == "Victory" then return false, "A cinematic is playing" end
  local cfg = Config[spell]
  if type(cfg) ~= "table" or not (spell == "Flame" or spell == "Freeze" or spell == "Wave" or spell == "Lightning") then return false, "Unknown spell" end
  local h = alive(player.Character)
  if not h then return false, "Respawn first" end
  if player.Character:GetAttribute("VoiceFrozen") then return false, "You are frozen" end
  if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.5 or direction.Magnitude > 1.5 then return false, "Aim unavailable" end
  for _, v in ipairs({direction.X,direction.Y,direction.Z}) do if v ~= v or math.abs(v) > 1.5 then return false, "Invalid aim" end end
  local now = os.clock()
  cooldowns[player] = cooldowns[player] or {}
  local readyAt = cooldowns[player][spell] or 0
  if now < readyAt then return false, string.format("%s ready in %.1fs",spell,readyAt-now) end
  if now < (globalCooldowns[player] or 0) then return false, "Speak one spell at a time" end
  cooldowns[player][spell] = now + cfg.Cooldown; globalCooldowns[player] = now + Config.GlobalCooldown
  direction = direction.Unit
  if spell == "Lightning" then lightning(player)
  elseif spell == "Wave" then wave(player, direction) else projectile(player, direction, spell) end
  return true, cfg.Cooldown
end
-- Status effects reused by AI-generated spells (SpellFx). Burn adds no impact damage.
function Service.Burn(character, seconds) flame(character, 0, seconds) end
function Service.Freeze(character, seconds) freeze(character, seconds) end
Players.PlayerRemoving:Connect(function(player) cooldowns[player] = nil; globalCooldowns[player] = nil end)
return Service
