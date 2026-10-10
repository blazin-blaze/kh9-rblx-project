-- Server-authoritative ultimate; microphone RMS is sampled locally by UltimateClient.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")
local Debris=game:GetService("Debris")
local Config=require(script.Parent.SpellConfig).Ultimate
local Locks=require(script.Parent.MovementLocks)
local Service={}
local states={}
local folder, getDirection
local effects=workspace:FindFirstChild("VoiceArenaEffects") or Instance.new("Folder")
effects.Name="VoiceArenaEffects"; effects.Parent=workspace
local function now() return workspace:GetServerTimeNow() end
local function alive(character)
 local h=character and character:FindFirstChildOfClass("Humanoid")
 local root=character and character:FindFirstChild("HumanoidRootPart")
 if h and root and h.Health>0 then return h,root end
end
local function modelOf(part)
 local model=part:FindFirstAncestorOfClass("Model")
 while model and not model:FindFirstChildOfClass("Humanoid") do
  model=model.Parent and model.Parent:FindFirstAncestorOfClass("Model")
 end
 return model
end
local function visual(name,color,shape)
 local p=Instance.new("Part")
 p.Name=name; p.Shape=shape or Enum.PartType.Cylinder
 p.Anchored=true; p.CanCollide=false; p.CanTouch=false; p.CanQuery=false
 p.CastShadow=false; p.Material=Enum.Material.Neon; p.Color=color
 p.Size=Vector3.one*0.1; p.Parent=effects
 return p
end
local function finish(player,state)
 if not state.active then return end
 local active=state.active
 state.active=nil
 Locks.Release(active.character,"Ultimate")
 active.character:SetAttribute("UltimateChanneling",false)
 for _,p in active.visuals do
  TweenService:Create(p,TweenInfo.new(0.3),{Transparency=1,Size=Vector3.one*0.1}):Play()
  Debris:AddItem(p,0.35)
 end
 if player.Parent then
  player:SetAttribute("UltimateActive",false)
  player:SetAttribute("UltimatePower",0)
  player:SetAttribute("UltimateEndsAt",0)
  state.readyAt=now()+Config.ChargeSeconds
  player:SetAttribute("UltimateReadyAt",state.readyAt)
 end
end
function Service.Cancel(player)
 local state=states[player]
 if state then finish(player,state) end
end
function Service.Sample(player,character,rms)
 local state=states[player]
 if not state or character~=player.Character or not alive(character) then return end
 if type(rms)~="number" or rms~=rms or rms<0 or rms>1 then return end
 local time=now()
 if time-(state.lastPacket or 0)<0.06 then return end
 state.lastPacket=time
 state.rms=rms
end
local function ensureInput(player)
 -- Prefer Roblox's default input. The fallback only feeds the local analyzer, never speakers.
 if player:FindFirstChildWhichIsA("AudioDeviceInput") then return end
 local input=Instance.new("AudioDeviceInput")
 input.Name="UltimateMicrophone"; input.Player=player; input.Parent=player
end
local function added(player)
 local state={readyAt=now()+Config.ChargeSeconds,rms=0,lastPacket=0}
 states[player]=state
 player:SetAttribute("UltimateChargeSeconds",Config.ChargeSeconds)
 player:SetAttribute("UltimateReadyAt",state.readyAt)
 player:SetAttribute("UltimateActive",false)
 local function characterAdded(character)
  finish(player,state)
  state.rms=0; state.lastPacket=0
  state.readyAt=now()+Config.ChargeSeconds
  player:SetAttribute("UltimateReadyAt",state.readyAt)
  player:SetAttribute("UltimateActive",false)
  player:SetAttribute("UltimatePower",0)
  player:SetAttribute("UltimateEndsAt",0)
  task.spawn(function()
   local h=character:WaitForChild("Humanoid",10)
   if h and player.Character==character then
    h.Died:Connect(function() if state.active and state.active.character==character then finish(player,state) end end)
   end
  end)
 end
 player.CharacterAdded:Connect(characterAdded)
 if player.Character then characterAdded(player.Character) end
 -- Allow the engine time to create its default voice input.
 task.delay(2,function() if player.Parent then ensureInput(player) end end)
end
function Service.Init(remoteFolder,directionGetter)
 folder=remoteFolder; getDirection=directionGetter
 local remote=folder:FindFirstChild("UltimateVolume") or Instance.new("RemoteEvent")
 remote.Name="UltimateVolume"; remote.Parent=folder
 remote.OnServerEvent:Connect(Service.Sample)
 folder:SetAttribute("UltimateNoiseFloor",Config.NoiseFloor)
 folder:SetAttribute("UltimateFullPowerRms",Config.FullPowerRms)
 for _,player in Players:GetPlayers() do added(player) end
 Players.PlayerAdded:Connect(added)
 Players.PlayerRemoving:Connect(function(player) Service.Cancel(player); states[player]=nil end)
end
function Service.Cast(player)
 local state=states[player]
 if not state then return false,"Ultimate is loading" end
 if state.active then return false,"Ultimate is already firing" end
 if folder:GetAttribute("MatchState")=="Match" and not player:GetAttribute("InMatch") then
  return false,"A match is in progress. Wait for the next one"
 end
 local h,root=alive(player.Character)
 if not h then return false,"Respawn first" end
 if player.Character:GetAttribute("VoiceFrozen") then return false,"You are frozen" end
 if root.Anchored then return false,"You cannot fire while immobilized" end
 local remaining=state.readyAt-now()
 if remaining>0 then return false,string.format("Ultimate ready in %.1fs",remaining) end
 local active={character=player.Character,root=root,h=h,endsAt=now()+Config.Duration,
  power=0,damageTime=0,updateTime=0,visuals={},direction=getDirection(player) or root.CFrame.LookVector,
  inMatch=folder:GetAttribute("MatchState")=="Match"}
 active.outer=visual("UltimateDeathBeam",Color3.fromRGB(175,65,255))
 active.outer.Transparency=0.4
 active.core=visual("UltimateBeamCore",Color3.fromRGB(250,220,255))
 active.muzzle=visual("UltimateMuzzle",Color3.fromRGB(200,100,255),Enum.PartType.Ball)
 active.tip=visual("UltimateImpact",Color3.fromRGB(245,175,255),Enum.PartType.Ball)
 active.visuals={active.outer,active.core,active.muzzle,active.tip}
 local light=Instance.new("PointLight"); light.Color=active.outer.Color; light.Range=20; light.Brightness=2
 light.Parent=active.muzzle
 Locks.Acquire(active.character,"Ultimate")
 active.character:SetAttribute("UltimateChanneling",true)
 state.active=active
 player:SetAttribute("UltimateActive",true)
 player:SetAttribute("UltimateEndsAt",active.endsAt)
 player:SetAttribute("UltimateReadyAt",active.endsAt+Config.ChargeSeconds)
 return true,Config.Duration
end
local function update(player,state,dt,time)
 local active=state.active
 local h,root=alive(active.character)
 if not h or player.Character~=active.character or active.character:GetAttribute("VoiceFrozen") or
  time>=active.endsAt or (active.inMatch and folder:GetAttribute("MatchState")~="Match") or
  (folder:GetAttribute("MatchState")=="Match" and not player:GetAttribute("InMatch")) then
  finish(player,state); return
 end
 local fresh=time-state.lastPacket<=Config.SampleTimeout
 local rms=fresh and state.rms or 0
 local power=math.clamp((rms-Config.NoiseFloor)/(Config.FullPowerRms-Config.NoiseFloor),0,1)^0.55
 active.power+=(power-active.power)*(1-math.exp(-dt*14))
 if not fresh then active.power=0 end
 active.damageTime+=dt; active.updateTime+=dt
 if active.updateTime<0.1 then return end
 local elapsed=math.min(active.damageTime,0.2)
 active.damageTime=0; active.updateTime=0
 local direction=getDirection(player) or active.direction
 active.direction=direction
 -- Keep weak beams thin; grow strongly as voice power rises. Collision uses the same radius.
 local radius=Config.MinRadius+(Config.MaxRadius-Config.MinRadius)*active.power^1.4
 local origin=root.Position+Vector3.new(0,1,0)+direction*2
 local fullCenter=origin+direction*Config.Range/2
 local overlap=OverlapParams.new()
 overlap.FilterType=Enum.RaycastFilterType.Exclude
 overlap.FilterDescendantsInstances={active.character,effects}
 local candidates,seen,ignore={}, {}, {active.character,effects}
 for _,part in workspace:GetPartBoundsInBox(CFrame.lookAt(fullCenter,fullCenter+direction),
  Vector3.new(radius*2+4,radius*2+4,Config.Range),overlap) do
  local model=modelOf(part)
  if model and not seen[model] then
   seen[model]=true
   local targetH,targetRoot=alive(model)
   if targetH then table.insert(candidates,{model,targetH,targetRoot}); table.insert(ignore,model) end
  end
 end
 local params=RaycastParams.new()
 params.FilterType=Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances=ignore
 params.RespectCanCollide=true
 local obstruction=workspace:Raycast(origin,direction*Config.Range,params)
 local length=obstruction and obstruction.Distance or Config.Range
 length=math.max(0.1,length)
 local endpoint=origin+direction*length
 local center=origin+direction*length/2
 local cf=CFrame.lookAt(center,endpoint)*CFrame.Angles(0,math.pi/2,0)
 active.outer.Size=Vector3.new(length,radius*2,radius*2); active.outer.CFrame=cf
 active.core.Size=Vector3.new(length,radius*0.65,radius*0.65); active.core.CFrame=cf
 active.muzzle.Size=Vector3.one*radius*2.3; active.muzzle.Position=origin
 active.tip.Size=Vector3.one*radius*2; active.tip.Position=endpoint
 active.outer.Transparency=0.78-active.power*0.6
 active.core.Transparency=0.45-active.power*0.4
 local light=active.muzzle:FindFirstChildOfClass("PointLight")
 if light then light.Brightness=0.5+active.power*4; light.Range=8+active.power*32 end
 player:SetAttribute("UltimatePower",active.power)
 for _,target in candidates do
  local model,targetH,targetRoot=table.unpack(target)
  local relative=targetRoot.Position-origin
  local along=relative:Dot(direction)
  local radial=(relative-direction*along).Magnitude
  local targetPlayer=Players:GetPlayerFromCharacter(model)
  local spectator=targetPlayer and folder:GetAttribute("MatchState")=="Match" and not targetPlayer:GetAttribute("InMatch")
  if not spectator and along>=0 and along<=length and radial<=radius+1.5 and active.power>0.005 then
   -- Center-line obstruction stops the beam; this extra ray prevents wider edges hitting through walls.
   local cover=workspace:Raycast(origin,relative,params)
   if not cover or cover.Distance>=relative.Magnitude-0.1 then
    targetH:TakeDamage(Config.MaxDamagePerSecond*active.power*elapsed)
   end
  end
 end
end
RunService.Heartbeat:Connect(function(dt)
 local time=now()
 for player,state in states do
  if state.active then
   local ok,err=pcall(update,player,state,dt,time)
   if not ok then warn("[Ultimate] "..tostring(err)); finish(player,state) end
  end
 end
end)
return Service
