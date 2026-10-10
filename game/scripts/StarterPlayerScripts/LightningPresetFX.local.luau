-- StarterPlayer.StarterPlayerScripts.LightningPresetFX (LocalScript)
-- Client-only visuals for the Lightning preset. The server (ServerScriptService.VoiceArena.SpellService)
-- owns the cone and the damage ticks and announces lightning_cast, lightning_hit (one per damage tick per
-- target) and lightning_end on ReplicatedStorage.VoiceArena.PresetFx.
-- Look: a storm of forking, tapering bolts (glow / yellow / white-hot core) that re-forms every few
-- frames inside the exact gameplay cone, a charged orb at the caster's hands streaming sparks, arcs
-- crawling over the caster, ground strikes at the cone's far end, and on every hit a bolt that locks
-- onto the target with a spark burst and a body flash. Thunderclap, camera shake and screen flash on cast.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local remote=game:GetService("ReplicatedStorage"):WaitForChild("VoiceArena"):WaitForChild("PresetFx")
local forge=script.Parent:WaitForChild("SpellForgeClient")
local FX=require(forge:WaitForChild("FXUtil"))
local CameraFX=require(forge:WaitForChild("CameraFX"))
local player=Players.LocalPlayer
local rng=Random.new()
local function r(a,b) return rng:NextNumber(a,b) end

local WHITE=Color3.fromRGB(255,255,240)
local YELLOW=Color3.fromRGB(255,220,20)
local AMBER=Color3.fromRGB(255,160,0)
local HALO=Color3.fromRGB(255,236,110)
local SCORCH=Color3.fromRGB(28,22,12)
-- Each bolt segment is three stacked parts: a soft glow, the yellow bolt, and a white-hot core.
local LAYERS={
 {color=HALO,width=0.75,transparency=0.82},
 {color=YELLOW,width=0.28,transparency=0.15},
 {color=WHITE,width=0.11,transparency=0},
}
local BOLTS,SEGMENTS=12,7      -- main bolts filling the cone
local FORKS,FORK_SEGMENTS=6,3  -- side branches split off the first main bolts
local ARCS,ARC_SEGMENTS=4,3    -- small arcs crawling over the caster's body
local REROLL=0.045             -- seconds between new bolt shapes (the flicker rate)
-- The caster's body centre in cone space: the cone starts at root*(0, 0.6, -2), same as the server.
local BODY=Vector3.new(0,-0.6,2)

local active={}
local lastFlash=setmetatable({},{__mode="k"})

---------------------------------------------------------------- bolt geometry (in cone space)
-- A point `spread` of the way out from the cone's axis at `depth`, jittered, never outside the cone.
local function inCone(st,depth,angle,spread,jitter)
 local radius=depth/st.range*st.radius
 local x=math.cos(angle)*radius*spread+r(-jitter,jitter)
 local y=math.sin(angle)*radius*spread+r(-jitter,jitter)
 local d=math.sqrt(x*x+y*y)
 if d>radius and d>0 then x*=radius/d; y*=radius/d end
 return Vector3.new(x,y,-depth)
end

-- A jagged line of `segments` segments, each with a part per layer from `firstLayer` up.
local function newLine(st,segments,firstLayer)
 local line={firstLayer=firstLayer}
 for s=1,segments do
  local seg={}
  for l=firstLayer,#LAYERS do
   local p=Instance.new("Part")
   p.Anchored=true; p.CanCollide=false; p.CanTouch=false; p.CanQuery=false; p.CastShadow=false
   p.Material=Enum.Material.Neon; p.Color=LAYERS[l].color; p.Transparency=1; p.Size=Vector3.one*0.1
   p.Parent=st.model
   seg[l]=p
   table.insert(st.parts,p)
  end
  line[s]=seg
 end
 return line
end

-- Shapes a line along `points` (cone space), tapering toward the tip; hidden lines go fully transparent.
local function shape(st,line,points,width,visible)
 for s,seg in ipairs(line) do
  local a,b=points[s],points[s+1]
  local length=math.max((b-a).Magnitude,0.05)
  local cf=FX.lookAt((a+b)/2,b)
  local taper=width*(1-0.5*(s-1)/#line)
  for l=line.firstLayer,#LAYERS do
   local layer=LAYERS[l]
   local w=layer.width*taper
   local p=seg[l]
   p.Size=Vector3.new(w,w,length+w*0.5) -- a little overlap so the joints don't gap
   p.Transparency=visible and layer.transparency or 1
   st.localCF[p]=cf
  end
 end
end

local function reroll(st)
 for i,bolt in ipairs(st.bolts) do
  local angle=r(0,math.pi*2)
  local spread=i<=8 and r(0.65,1) or r(0.05,0.6)
  local reach=r(0.75,1)*st.range
  local points={Vector3.new(r(-0.15,0.15),r(-0.15,0.15),0)}
  for k=1,SEGMENTS do
   local depth=k/SEGMENTS*reach
   points[k+1]=inCone(st,depth,angle+r(-0.12,0.12),spread,depth/st.range*st.radius*0.22)
  end
  bolt.points=points
  shape(st,bolt.line,points,r(0.7,1.3),rng:NextNumber()>0.18)
 end
 for f,fork in ipairs(st.forks) do
  local start=st.bolts[f].points[rng:NextInteger(3,5)]
  local angle=math.atan2(start.Y,start.X)+r(-0.9,0.9)
  local points={start}
  for k=1,FORK_SEGMENTS do
   points[k+1]=inCone(st,math.min(st.range,-start.Z+k*st.range*0.08),angle,r(0.8,1.05),0.6)
  end
  shape(st,fork.line,points,r(0.4,0.7),rng:NextNumber()>0.3)
 end
 for _,arc in ipairs(st.arcs) do
  local a=rng:NextNumber()<0.5 and Vector3.zero or BODY+Vector3.new(r(-1.6,1.6),r(-2.2,1.8),r(-0.8,0.8))
  local b=BODY+Vector3.new(r(-1.6,1.6),r(-2.2,1.8),r(-0.8,0.8))
  local points={a}
  for k=1,ARC_SEGMENTS-1 do points[k+1]=a:Lerp(b,k/ARC_SEGMENTS)+Vector3.new(r(-0.4,0.4),r(-0.4,0.4),r(-0.4,0.4)) end
  points[ARC_SEGMENTS+1]=b
  shape(st,arc.line,points,r(0.35,0.6),rng:NextNumber()>0.25)
 end
 st.light.Brightness=r(1.5,3.5)
 st.tipLight.Brightness=r(0.5,2)
 st.highlight.OutlineTransparency=r(0.1,0.7)
 st.shell.Transparency=r(0,0.3)
end

-- Moves every bolt part along with the caster: one BulkMoveTo per storm per frame.
local function place(st,basis)
 for i,p in ipairs(st.parts) do st.world[i]=basis*st.localCF[p] end
 workspace:BulkMoveTo(st.parts,st.world,Enum.BulkMoveMode.FireCFrameChanged)
end

---------------------------------------------------------------- one-off effects (world space)
-- A short-lived jagged bolt from a to b that fades out over `life` seconds.
local function flashBolt(a,b,width,life)
 local length=(b-a).Magnitude
 if length<0.2 then return end
 local n=math.clamp(math.floor(length/3.5),2,8)
 local jag=math.min(1.6,length*0.12)
 local frame=FX.lookAt(a,b)
 local prev=a
 for k=1,n do
  local point=a:Lerp(b,k/n)
  if k<n then point+=frame.RightVector*r(-jag,jag)+frame.UpVector*r(-jag,jag) end
  local cf=FX.lookAt((prev+point)/2,point)
  local len=(point-prev).Magnitude
  for _,layer in ipairs(LAYERS) do
   local w=layer.width*width
   local p=FX.part({Size=Vector3.new(w,w,len+w*0.5),CFrame=cf,Color=layer.color,Transparency=layer.transparency})
   FX.tween(p,life,{Transparency=1},Enum.EasingStyle.Quad,Enum.EasingDirection.In)
   FX.debris(p,life+0.05)
  end
  prev=point
 end
end

-- See-through flash on a struck body (FX.highlight starts nearly opaque, which hides the target at 5 hits/s).
local function bodyFlash(target)
 local h=Instance.new("Highlight")
 h.Adornee=target; h.FillColor=WHITE; h.FillTransparency=0.55; h.OutlineColor=YELLOW; h.OutlineTransparency=0
 h.DepthMode=Enum.HighlightDepthMode.Occluded; h.Parent=FX.folder
 FX.tween(h,0.18,{FillTransparency=1,OutlineTransparency=1},nil,nil,0.03)
 FX.debris(h,0.3)
end

local function sparks(pos,normal,count)
 local a=FX.anchor(FX.alignY(pos,normal),1)
 FX.emitter(a,{Texture=FX.TEX.spark,EmissionDirection=Enum.NormalId.Top,SpreadAngle=Vector2.new(70,70),
  Speed=FX.nr(18,40),Lifetime=FX.nr(0.2,0.45),Drag=4,Acceleration=Vector3.new(0,-40,0),
  Size=FX.nseq(0,0.35,1,0),Color=FX.cseq(WHITE,YELLOW,AMBER),LightEmission=1,Brightness=3}):Emit(count)
end

-- A bolt from the cone's far end down into the floor, with a flash, a shockwave ring and a scorch mark.
local function groundStrike(st,basis)
 local top=basis*inCone(st,r(0.55,1)*st.range,r(0,math.pi*2),r(0.3,1),0)
 local hit=FX.ground(top,40)
 if not hit then return end
 flashBolt(top,hit.Position,r(0.5,0.8),0.14)
 FX.pop(hit.Position,WHITE,0.6,r(3,5),0.18)
 FX.ring(hit.Position,hit.Normal,YELLOW,1,r(7,11),0.35)
 sparks(hit.Position,hit.Normal,10)
 if rng:NextNumber()<0.5 then
  FX.disk(hit.Position+hit.Normal*0.05,hit.Normal,r(3,5),SCORCH,Enum.Material.SmoothPlastic,0.35,1,1.2)
 end
end

---------------------------------------------------------------- cast / hit / end
local function retire(id,fade)
 local st=active[id]
 if not st then return end
 active[id]=nil
 if not fade then st.model:Destroy(); return end
 for _,e in ipairs(st.emitters) do e.Enabled=false end
 for _,p in ipairs(st.parts) do if p.Transparency<1 then FX.tween(p,0.18,{Transparency=1}) end end
 FX.tween(st.orb,0.2,{Size=Vector3.one*0.1,Transparency=1})
 FX.tween(st.shell,0.25,{Size=Vector3.one*6,Transparency=1})
 FX.tween(st.light,0.25,{Brightness=0})
 FX.tween(st.tipLight,0.25,{Brightness=0})
 st.highlight:Destroy()
 FX.pop(st.orb.Position,WHITE,1.5,6,0.2)
 FX.debris(st.model,0.8)
end

local function cast(op)
 retire(op.id)
 local character=op.target
 local root=typeof(character)=="Instance" and character:FindFirstChild("HumanoidRootPart")
 if not root then return end
 local basis=root.CFrame*CFrame.new(0,0.6,-2)
 local model=Instance.new("Model")
 model.Name="LightningStormFX"
 local st={model=model,target=character,endsAt=op.endsAt,range=op.range,radius=op.radius,
  parts={},localCF={},world={},bolts={},forks={},arcs={},
  nextChange=0,nextStrike=0,nextCrackle=0,started=os.clock()}
 for i=1,BOLTS do st.bolts[i]={line=newLine(st,SEGMENTS,1)} end
 for i=1,FORKS do st.forks[i]={line=newLine(st,FORK_SEGMENTS,1)} end
 for i=1,ARCS do st.arcs[i]={line=newLine(st,ARC_SEGMENTS,2)} end
 -- charged orb at the hands, with a crackling shell, sparks streaming down the cone and two lights
 st.orb=FX.part({Shape=Enum.PartType.Ball,Size=Vector3.one*1.3,CFrame=basis,Color=WHITE,Parent=model})
 st.shell=FX.part({Shape=Enum.PartType.Ball,Size=Vector3.one*3.4,CFrame=basis,Color=YELLOW,
  Material=Enum.Material.ForceField,Parent=model})
 local attachment=Instance.new("Attachment")
 attachment.Parent=st.orb
 st.emitters={
  FX.emitter(attachment,{Texture=FX.TEX.sparkle,Rate=150,EmissionDirection=Enum.NormalId.Front,
   SpreadAngle=Vector2.new(22,22),Speed=FX.nr(40,85),Lifetime=FX.nr(0.2,0.4),Drag=2,Size=FX.nseq(0,0.9,1,0),
   Color=FX.cseq(WHITE,YELLOW,AMBER),LightEmission=1,Brightness=4,Rotation=FX.nr(0,360),RotSpeed=FX.nr(-300,300)}),
  FX.emitter(attachment,{Texture=FX.TEX.spark,Rate=70,SpreadAngle=Vector2.new(180,180),Speed=FX.nr(6,16),
   Lifetime=FX.nr(0.15,0.35),Drag=3,Size=FX.nseq(0,0.3,1,0),Color=FX.cseq(WHITE,YELLOW),LightEmission=1,Brightness=3}),
 }
 st.light=Instance.new("PointLight")
 st.light.Color=YELLOW; st.light.Range=16; st.light.Brightness=2.5; st.light.Shadows=false; st.light.Parent=st.orb
 st.tip=FX.part({Size=Vector3.one*0.2,Transparency=1,CFrame=basis*CFrame.new(0,0,-st.range*0.85),Parent=model})
 st.tipLight=Instance.new("PointLight")
 st.tipLight.Color=YELLOW; st.tipLight.Range=18; st.tipLight.Brightness=1; st.tipLight.Shadows=false; st.tipLight.Parent=st.tip
 -- the caster glows while channeling
 st.highlight=Instance.new("Highlight")
 st.highlight.Adornee=character; st.highlight.FillColor=YELLOW; st.highlight.FillTransparency=0.88
 st.highlight.OutlineColor=WHITE; st.highlight.OutlineTransparency=0.35
 st.highlight.DepthMode=Enum.HighlightDepthMode.Occluded; st.highlight.Parent=model
 model.Parent=FX.folder
 active[op.id]=st
 reroll(st)
 place(st,basis)
 -- the thunderclap
 local muzzle=basis.Position
 FX.sound(FX.SND.thunder,root,1.1,r(0.95,1.1),6)
 FX.sound(FX.SND.ping,root,0.6,0.7,2)
 FX.pop(muzzle,WHITE,1,8,0.3)
 FX.pop(muzzle,YELLOW,2,14,0.45,Enum.Material.ForceField,0.1)
 FX.flashLight(muzzle,YELLOW,6,40,0.4)
 local floor=FX.ground(root.Position,8)
 if floor then
  FX.ring(floor.Position,floor.Normal,YELLOW,2,26,0.5)
  FX.ring(floor.Position,floor.Normal,WHITE,1,14,0.3)
 end
 local near=CameraFX.shakeAt(muzzle,0.45,80)
 if near>0 then
  CameraFX.grade({brightness=0.25*near,contrast=0.2*near,bloom=0.5*near,tint=Color3.fromRGB(255,246,205),attack=0.02,release=0.35})
 end
 if character==player.Character then CameraFX.kick("fov",7,0.05,0.15,0.45) end
end

-- One server damage tick: a bolt locks onto the struck body part.
local function hit(op)
 local target=op.target
 if typeof(target)~="Instance" or typeof(op.pos)~="Vector3" then return end
 local st=active[op.id]
 local from=st and st.orb.Position or op.pos+Vector3.new(0,8,0)
 flashBolt(from,op.pos,r(1,1.4),0.12)
 flashBolt(from,op.pos,r(0.4,0.6),0.09)
 FX.pop(op.pos,WHITE,0.8,r(3,4.5),0.16)
 sparks(op.pos,from-op.pos,8)
 local now=os.clock()
 if now-(lastFlash[target] or 0)>0.2 then
  lastFlash[target]=now
  bodyFlash(target)
  FX.sound(FX.SND.ping,op.pos,0.45,r(1.2,1.8),1)
  if target==player.Character then
   CameraFX.shake(0.25)
   CameraFX.grade({brightness=0.22,contrast=0.1,tint=Color3.fromRGB(255,244,190),attack=0.01,release=0.2})
  end
 end
end

remote.OnClientEvent:Connect(function(op)
 if type(op)~="table" then return end
 if op.op=="lightning_cast" then cast(op)
 elseif op.op=="lightning_hit" then hit(op)
 elseif op.op=="lightning_end" then retire(op.id,true) end
end)

RunService.RenderStepped:Connect(function()
 local time=workspace:GetServerTimeNow()
 local now=os.clock()
 for id,st in pairs(active) do
  local root=st.target:FindFirstChild("HumanoidRootPart")
  local h=st.target:FindFirstChildOfClass("Humanoid")
  if time>=st.endsAt or not st.target.Parent or not root or not h or h.Health<=0 then
   retire(id,true)
  else
   local basis=root.CFrame*CFrame.new(0,0.6,-2)
   if now>=st.nextChange then st.nextChange=now+REROLL; reroll(st) end
   place(st,basis)
   local t=now-st.started
   st.orb.CFrame=basis
   st.orb.Size=Vector3.one*(1.2+0.25*math.sin(t*40))
   st.shell.CFrame=basis*CFrame.Angles(t*6,t*9,0)
   st.tip.CFrame=basis*CFrame.new(0,0,-st.range*0.85)
   if now>=st.nextStrike then st.nextStrike=now+r(0.07,0.16); groundStrike(st,basis) end
   if now>=st.nextCrackle then st.nextCrackle=now+r(0.12,0.22); FX.sound(FX.SND.ping,st.orb,0.22,r(1.5,2.8),1) end
  end
 end
end)
