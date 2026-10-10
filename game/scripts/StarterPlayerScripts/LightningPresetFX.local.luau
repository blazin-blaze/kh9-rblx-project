-- Client-only pooled bolts; server owns the cone and damage ticks.
local RunService=game:GetService("RunService")
local remote=game:GetService("ReplicatedStorage"):WaitForChild("VoiceArena"):WaitForChild("PresetFx")
local active={}
local rng=Random.new()
local YELLOW=Color3.fromRGB(255,220,20)
local CORE=Color3.fromRGB(255,255,180)
local function retire(id)
 local st=active[id]
 if st then active[id]=nil; st.model:Destroy() end
end
remote.OnClientEvent:Connect(function(op)
 if type(op)~="table" then return end
 if op.op=="lightning_end" then retire(op.id); return end
 if op.op~="lightning_cast" or not op.target then return end
 retire(op.id)
 local model=Instance.new("Model"); model.Name="LightningConeFX"
 local st={model=model,target=op.target,endsAt=op.endsAt,range=op.range,radius=op.radius,
  segments={},paths={},nextChange=0}
 -- Ten branching, jagged bolts with bright cores and yellow halos.
 for bolt=1,10 do
  st.paths[bolt]={}
  st.segments[bolt]={}
  for segment=1,7 do
   local pair={}
   for layer=1,2 do
    local p=Instance.new("Part")
    p.Name=layer==1 and "YellowArc" or "ElectricCore"
    p.Anchored=true; p.CanCollide=false; p.CanTouch=false; p.CanQuery=false; p.CastShadow=false
    p.Material=Enum.Material.Neon; p.Color=layer==1 and YELLOW or CORE
    p.Transparency=layer==1 and .35 or .05
    p.Size=Vector3.new(.1,.1,.1); p.Parent=model; pair[layer]=p
   end
   st.segments[bolt][segment]=pair
  end
 end
 local glow=Instance.new("Part")
 glow.Name="Muzzle"; glow.Anchored=true; glow.CanCollide=false; glow.CanTouch=false; glow.CanQuery=false
 glow.Transparency=1; glow.Size=Vector3.one; glow.Parent=model; st.glow=glow
 local light=Instance.new("PointLight"); light.Color=YELLOW; light.Range=16; light.Brightness=3; light.Parent=glow
 st.light=light
 model.Parent=workspace
 active[op.id]=st
end)
RunService.RenderStepped:Connect(function()
 local time=workspace:GetServerTimeNow()
 for id,st in pairs(active) do
  local root=st.target:FindFirstChild("HumanoidRootPart")
  local h=st.target:FindFirstChildOfClass("Humanoid")
  if time>=st.endsAt or not st.target.Parent or not root or not h or h.Health<=0 then
   retire(id)
  else
   local basis=root.CFrame*CFrame.new(0,.6,-2)
   if time>=st.nextChange then
    st.nextChange=time+.045
    st.light.Brightness=rng:NextNumber(2,5)
    for bolt=1,10 do
     local angle=rng:NextNumber(0,math.pi*2)
     local spread=bolt<=6 and rng:NextNumber(.7,1) or rng:NextNumber(.1,.65)
     local path=st.paths[bolt]
     path[1]=Vector3.zero
     for point=1,7 do
      local depth=point/7*st.range
      local radius=depth/st.range*st.radius
      local jitter=point==7 and 0 or radius*.2
      local x=math.cos(angle)*radius*spread+rng:NextNumber(-jitter,jitter)
      local y=math.sin(angle)*radius*spread+rng:NextNumber(-jitter,jitter)
      -- Keep every bolt inside the same cone used for gameplay.
      local distance=math.sqrt(x*x+y*y)
      if distance>radius then x*=radius/distance; y*=radius/distance end
      path[point+1]=Vector3.new(x,y,-depth)
     end
    end
   end
   st.glow.CFrame=basis
   for bolt=1,10 do
    local path=st.paths[bolt]
    for segment=1,7 do
     local a=basis:PointToWorldSpace(path[segment])
     local b=basis:PointToWorldSpace(path[segment+1])
     local cf=CFrame.lookAt((a+b)/2,b)
     local length=(b-a).Magnitude
     local pair=st.segments[bolt][segment]
     pair[1].Size=Vector3.new(.32,.32,length); pair[1].CFrame=cf
     pair[2].Size=Vector3.new(.095,.095,length); pair[2].CFrame=cf
    end
   end
  end
 end
end)
