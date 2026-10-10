-- Builds a temporary podium from match avatar snapshots and plays a synchronized ending.
local Players=game:GetService("Players")
local Locks=require(script.Parent.MovementLocks)
local Ultimate=require(script.Parent.UltimateService)
local Victory={}
local GOLD=Color3.fromRGB(255,207,82)
local TOTAL=7.5
function Victory.Capture(character)
 if not character then return nil end
 local archivable=character.Archivable
 character.Archivable=true
 local ok,copy=pcall(character.Clone,character)
 character.Archivable=archivable
 if not ok or not copy then return nil end
 for _,obj in ipairs(copy:GetDescendants()) do
  if obj:IsA("BaseScript") or obj:IsA("Tool") or obj:IsA("ForceField") then obj:Destroy()
  elseif obj:IsA("BasePart") then obj.Anchored=true; obj.CanCollide=false; obj.CanTouch=false; obj.CanQuery=false end
 end
 local h=copy:FindFirstChildOfClass("Humanoid")
 if h then h.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None end
 return copy
end
local function magicJet(avatar,side,ice)
 local hand=avatar:FindFirstChild(side.."Hand") or avatar:FindFirstChild(side.."LowerArm") or avatar:FindFirstChild(side.." Arm") or avatar:FindFirstChild(side.."UpperArm")
 if not hand then return end
 local nozzle=Instance.new("Attachment"); nozzle.Name=ice and "VictoryIce" or "VictoryFire"
 nozzle.CFrame=CFrame.new(0,-hand.Size.Y/2,0)*CFrame.Angles(0,0,math.pi); nozzle.Parent=hand
 local emitter=Instance.new("ParticleEmitter"); emitter.Name=ice and "IceShards" or "FlameJet"
 emitter.Texture=ice and "rbxasset://textures/particles/sparkles_main.dds" or "rbxasset://textures/particles/fire_main.dds"
 emitter.EmissionDirection=Enum.NormalId.Top; emitter.Rate=ice and 65 or 85
 emitter.Speed=NumberRange.new(14,23); emitter.Lifetime=NumberRange.new(0.45,0.8)
 emitter.SpreadAngle=Vector2.new(9,9); emitter.LightEmission=1
 emitter.Rotation=NumberRange.new(0,360); emitter.RotSpeed=NumberRange.new(-90,90)
 emitter.Color=ice and ColorSequence.new(Color3.fromRGB(220,255,255),Color3.fromRGB(45,160,255))
  or ColorSequence.new(Color3.fromRGB(255,230,100),Color3.fromRGB(255,55,10))
 emitter.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,ice and 0.65 or 1.5),NumberSequenceKeypoint.new(0.4,ice and 0.45 or 2),NumberSequenceKeypoint.new(1,0)})
 emitter.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.15),NumberSequenceKeypoint.new(0.6,0.1),NumberSequenceKeypoint.new(1,1)})
 emitter.Enabled=false; emitter:SetAttribute("PodiumMagic",true); emitter.Parent=nozzle
 if ice then
  local mist=emitter:Clone(); mist.Name="FrostMist"; mist.Texture="rbxasset://textures/particles/smoke_main.dds"
  mist.Rate=25; mist.Speed=NumberRange.new(10,16); mist.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0.6),NumberSequenceKeypoint.new(1,2.5)})
  mist.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.65),NumberSequenceKeypoint.new(1,1)})
  mist.Parent=nozzle
 end
 local glow=Instance.new("PointLight"); glow.Color=ice and Color3.fromRGB(100,200,255) or Color3.fromRGB(255,110,35)
 glow.Brightness=1.5; glow.Range=8; glow.Parent=nozzle
end
function Victory.Cleanup(templates)
 for _,model in pairs(templates) do model:Destroy() end
end
function Victory.Play(folder,winner,eliminated,templates)
 folder:SetAttribute("VictoryStart",nil)
 folder:SetAttribute("MatchState","Victory")
 local scene=Instance.new("Folder"); scene.Name="VictoryPodium"
 local held,shields={},{}
 local ok,err=xpcall(function()
  for _,p in ipairs(Players:GetPlayers()) do
   Ultimate.Cancel(p)
   local char=p.Character
   if char and Locks.Acquire(char,"Victory") then
    table.insert(held,char)
    local shield=Instance.new("ForceField"); shield.Visible=false; shield.Name="VictoryProtection"; shield.Parent=char
    table.insert(shields,shield)
   end
  end
  local maps=workspace:FindFirstChild("Maps")
  local ring=maps and maps:FindFirstChild("RingModel")
  local center=ring and ring:GetBoundingBox().Position or Vector3.new(0,5,0)
  local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Exclude
  local ignore={}
  for _,p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(ignore,p.Character) end end
  params.FilterDescendantsInstances=ignore; params.RespectCanCollide=true
  local ground=workspace:Raycast(center+Vector3.new(0,60,0),Vector3.new(0,-120,0),params)
  local floor=ground and ground.Position or center
  local podium={winner}
  for i=#eliminated,1,-1 do
   local p=eliminated[i]
   if p~=winner and templates[p] then table.insert(podium,p) end
   if #podium==3 then break end
  end
  local positions={Vector3.zero,Vector3.new(-9,0,2),Vector3.new(9,0,2)}
  for rank,p in ipairs(podium) do
   local template=templates[p]
   local avatar=template and template:Clone() or Victory.Capture(p.Character)
   if avatar then
    avatar.Name=tostring(rank).."_"..p.Name
    avatar:SetAttribute("PodiumRank",rank)
    if rank==1 then magicJet(avatar,"Left",false); magicJet(avatar,"Right",true) end
    local root=avatar:FindFirstChild("HumanoidRootPart")
    local h=avatar:FindFirstChildOfClass("Humanoid")
    local height=root and ((h and h.HipHeight or 2)+root.Size.Y/2) or 3
    if h and h.RigType==Enum.HumanoidRigType.R6 then
     local leg=avatar:FindFirstChild("Left Leg")
     height+=leg and leg.Size.Y or 2
    end
    local at=floor+positions[rank]+Vector3.new(0,height,0)
    local desired=CFrame.lookAt(at,at+Vector3.zAxis)
    avatar:PivotTo(root and desired*root.CFrame:Inverse()*avatar:GetPivot() or desired)
    avatar.Parent=scene
   end
  end
  local function bar(a,b,width)
   local part=Instance.new("Part"); part.Name="GoldRune"
   part.Anchored=true; part.CanCollide=false; part.CanTouch=false; part.CanQuery=false; part.CastShadow=false
   part.Material=Enum.Material.Neon; part.Color=GOLD
   part.Size=Vector3.new(width,0.07,(b-a).Magnitude)
   part.CFrame=CFrame.lookAt((a+b)/2,b); part.Parent=scene
  end
  local origin=floor+Vector3.new(0,0.18,0)
  for _,radius in ipairs({5.5,7}) do
   for i=0,63 do
    local a=i*math.pi*2/64; local b=(i+1)*math.pi*2/64
    bar(origin+Vector3.new(math.cos(a)*radius,0,math.sin(a)*radius),origin+Vector3.new(math.cos(b)*radius,0,math.sin(b)*radius),0.12)
   end
   task.wait()
  end
  -- Twelve angular runes and a six-point arcane star inside the concentric rings.
  for i=0,11 do
   local a=i*math.pi/6
   local radial=Vector3.new(math.cos(a),0,math.sin(a))
   local tangent=Vector3.new(-math.sin(a),0,math.cos(a))
   local p=origin+radial*6.2
   bar(p-radial*0.4,p+radial*0.4,0.12)
   bar(p+radial*0.4,p+tangent*0.32,0.12)
   bar(p,p-radial*0.28-tangent*0.32,0.12)
  end
  for i=0,5 do
   local a=i*math.pi/3; local b=(i+2)*math.pi/3
   bar(origin+Vector3.new(math.cos(a)*4.5,0,math.sin(a)*4.5),origin+Vector3.new(math.cos(b)*4.5,0,math.sin(b)*4.5),0.1)
  end
  local lamp=Instance.new("Part"); lamp.Name="ArcaneGlow"; lamp.Size=Vector3.one*0.1
  lamp.Transparency=1; lamp.Anchored=true; lamp.CanCollide=false; lamp.CanQuery=false; lamp.CFrame=CFrame.new(origin+Vector3.new(0,0.5,0)); lamp.Parent=scene
  local light=Instance.new("PointLight"); light.Color=GOLD; light.Range=20; light.Brightness=2; light.Parent=lamp
  -- Hide the podium until the screen has faded to black.
  local start=workspace:GetServerTimeNow()+0.5
  folder:SetAttribute("VictoryWinner",winner.DisplayName)
  folder:SetAttribute("VictoryFrom",CFrame.lookAt(floor+Vector3.new(0,7,22),floor+Vector3.new(0,3,0)))
  folder:SetAttribute("VictoryTo",CFrame.lookAt(floor+Vector3.new(13,23,49),floor+Vector3.new(0,2,0)))
  folder:SetAttribute("VictoryDuration",TOTAL)
  folder:SetAttribute("VictoryStart",start)
  folder:SetAttribute("MatchText",winner.DisplayName.." wins!")
  folder:SetAttribute("MatchTime",start+TOTAL)
  folder:SetAttribute("MatchState","Victory")
  print("[Victory] "..winner.Name.." wins; podium has "..#podium.." players")
  while workspace:GetServerTimeNow()<start+1.5 do task.wait(0.05) end
  -- Move the real characters while the screen is black. Only podium copies remain in the arena.
  local spawn=maps and maps:FindFirstChild("SpawnLocation")
  if spawn then
   local players=Players:GetPlayers()
   local columns=math.max(1,math.ceil(math.sqrt(#players)))
   for i,p in ipairs(players) do
    local char=p.Character
    local root=char and char:FindFirstChild("HumanoidRootPart")
    local h=char and char:FindFirstChildOfClass("Humanoid")
    if root and h then
     local height=h.HipHeight+root.Size.Y/2
     if h.RigType==Enum.HumanoidRigType.R6 then
      local leg=char:FindFirstChild("Left Leg")
      height+=leg and leg.Size.Y or 2
     end
     local x=((i-1)%columns-(columns-1)/2)*4
     local z=(math.floor((i-1)/columns)-(math.ceil(#players/columns)-1)/2)*4
     local at=spawn.Position+Vector3.new(x,spawn.Size.Y/2+height+0.2,z)
     local target=CFrame.new(at)*root.CFrame.Rotation
     char:PivotTo(target*root.CFrame:Inverse()*char:GetPivot())
     root.AssemblyLinearVelocity=Vector3.zero
     root.AssemblyAngularVelocity=Vector3.zero
     char:SetAttribute("MatchSpawn",nil)
    end
    p:SetAttribute("InMatch",nil)
   end
  end
  scene.Parent=workspace
  while workspace:GetServerTimeNow()<start+TOTAL do task.wait(0.05) end
 end,debug.traceback)
 scene:Destroy()
 for _,shield in ipairs(shields) do shield:Destroy() end
 for _,char in ipairs(held) do Locks.Release(char,"Victory") end
 Victory.Cleanup(templates)
 if not ok then warn("[Victory] "..tostring(err)) end
end
return Victory