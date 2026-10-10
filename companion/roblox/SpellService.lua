-- ServerScriptService.VoiceArena.SpellService (ModuleScript)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Config = require(script.Parent.SpellConfig)
local Service = {}
local freezes, burns, cooldowns, globalCooldowns = {}, {}, {}, {}
local effects = workspace:FindFirstChild("VoiceArenaEffects") or Instance.new("Folder")
effects.Name = "VoiceArenaEffects"
effects.Parent = workspace

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
local function burst(position, color)
  local p = part("SpellImpact", Vector3.one, color, CFrame.new(position))
  p.Shape = Enum.PartType.Ball
  TweenService:Create(p, TweenInfo.new(0.35), { Size = Vector3.new(7,7,7), Transparency = 1 }):Play()
  Debris:AddItem(p, 0.4)
end
local function targetFrom(hit)
  local model = hit:FindFirstAncestorOfClass("Model")
  while model and not model:FindFirstChildOfClass("Humanoid") do model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model") end
  return model
end
local function enemy(caster, character)
  return character and character ~= caster.Character and alive(character) ~= nil
end
local function flame(character)
  local h, root = alive(character)
  if not h then return end
  h:TakeDamage(Config.Flame.Damage)
  -- Recasting refreshes one burn; it never multiplies ticking tasks.
  if burns[h] then burns[h].untilTime = os.clock() + Config.Flame.BurnSeconds; return end
  local fire = Instance.new("Fire")
  fire.Name = "VoiceBurn"; fire.Size = 6; fire.Heat = 5; fire.Parent = root
  local state = { untilTime = os.clock() + Config.Flame.BurnSeconds }
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
    fire:Destroy(); burns[h] = nil
  end)
end
local function freeze(character)
  local h, root = alive(character)
  if not h then return end
  if freezes[h] then freezes[h].untilTime = os.clock() + Config.Freeze.Duration; return end
  local ice = part("FrozenPrison", Vector3.new(5,7,5), Color3.fromRGB(130,220,255), root.CFrame)
  ice.Material = Enum.Material.Ice; ice.Transparency = 0.35
  local state = { untilTime = os.clock() + Config.Freeze.Duration, anchored = root.Anchored,
    walk = h.WalkSpeed, jumpPower = h.JumpPower, jumpHeight = h.JumpHeight, rotate = h.AutoRotate }
  freezes[h] = state
  character:SetAttribute("VoiceFrozen", true)
  root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero
  root.Anchored = true; h.WalkSpeed = 0; h.JumpPower = 0; h.JumpHeight = 0; h.AutoRotate = false
  task.spawn(function()
    while h.Parent and root.Parent and h.Health > 0 and os.clock() < state.untilTime do task.wait(0.05) end
    if root.Parent then root.Anchored = state.anchored end
    if h.Parent then h.WalkSpeed = state.walk; h.JumpPower = state.jumpPower; h.JumpHeight = state.jumpHeight; h.AutoRotate = state.rotate end
    if character.Parent then character:SetAttribute("VoiceFrozen", false) end
    ice:Destroy(); freezes[h] = nil
  end)
end
local function projectile(player, direction, spell)
  local _, root = alive(player.Character)
  if not root then return end
  local cfg = Config[spell]
  local color = spell == "Flame" and Color3.fromRGB(255,115,35) or Color3.fromRGB(135,225,255)
  local position = root.Position + Vector3.new(0,1,0) + direction * 2
  local orb = part(spell .. "Bolt", Vector3.new(2,2,2), color, CFrame.new(position))
  orb.Shape = Enum.PartType.Ball
  local light = Instance.new("PointLight"); light.Color = color; light.Range = 12; light.Brightness = 3; light.Parent = orb
  if spell == "Flame" then local f = Instance.new("Fire"); f.Size = 3; f.Heat = 0; f.Parent = orb end
  local params = RaycastParams.new()
  params.FilterType = Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances = {player.Character, effects}
  -- Include solid waves as blockers while excluding cosmetic effects.
  params.FilterDescendantsInstances = {player.Character, orb}
  params.RespectCanCollide = false
  local traveled = 0
  task.spawn(function()
    while orb.Parent and traveled < cfg.Range do
      local dt = RunService.Heartbeat:Wait()
      local distance = math.min(cfg.Speed * dt, cfg.Range - traveled)
      local step = direction * distance
      local hit = workspace:Spherecast(position, 0.8, step, params)
      if hit then
        local character = targetFrom(hit.Instance)
        if enemy(player, character) then if spell == "Flame" then flame(character) else freeze(character) end end
        burst(hit.Position, color); break
      end
      position += step; traveled += distance; orb.Position = position
    end
    orb:Destroy()
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
  local wall = part("WaveWall", size, Color3.fromRGB(35,175,230), CFrame.lookAt(position, position + horizontal), true)
  wall.Material = Enum.Material.Glass; wall.Transparency = 0.3
  local crest = part("WaveFoam", Vector3.new(cfg.Width,1.4,cfg.Depth+1), Color3.fromRGB(210,255,255), wall.CFrame * CFrame.new(0,cfg.Height/2,0))
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
        crest.CFrame = wall.CFrame * CFrame.new(0,cfg.Height/2,0)
        pushInside()
      end
      elapsed = os.clock() - started
    end
    wall:Destroy(); crest:Destroy()
    for targetRoot in pairs(pushed) do if targetRoot.Parent and not targetRoot.Anchored then pcall(function() targetRoot:SetNetworkOwnershipAuto() end) end end
  end)
end
function Service.Cast(player, spell, direction)
  local cfg = Config[spell]
  if type(cfg) ~= "table" or not (spell == "Flame" or spell == "Freeze" or spell == "Wave") then return false, "Unknown spell" end
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
  if spell == "Wave" then wave(player, direction) else projectile(player, direction, spell) end
  return true, cfg.Cooldown
end
Players.PlayerRemoving:Connect(function(player) cooldowns[player] = nil; globalCooldowns[player] = nil end)
return Service
