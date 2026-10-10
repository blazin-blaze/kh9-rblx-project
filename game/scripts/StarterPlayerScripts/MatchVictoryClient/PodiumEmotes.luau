-- Pose anchored podium copies locally so R6/R15 limbs and accessories animate together.
local Podium={}
local cache=setmetatable({}, {__mode="k"})
local function build(model)
 local root=model:FindFirstChild("HumanoidRootPart")
 if not root then return end
 local edges={}
 local function add(part,edge) edges[part]=edges[part] or {}; table.insert(edges[part],edge) end
 for _,joint in ipairs(model:GetDescendants()) do
  if joint:IsA("Motor6D") or joint:IsA("Weld") then
   if joint.Part0 and joint.Part1 then
    local edge={joint=joint,a=joint.Part0,b=joint.Part1,c0=joint.C0,c1=joint.C1,motor=joint:IsA("Motor6D")}
    -- Some simple rigs bind ArmJoint at the limb center instead of the shoulder.
    if edge.motor and (joint.Name=="Left ArmJoint" or joint.Name=="Right ArmJoint") then
     edge.c0=edge.c0+Vector3.new(0,0.5,0)
     edge.c1=edge.c1+Vector3.new(0,0.5,0)
    end
    add(edge.a,edge); add(edge.b,edge)
   end
  elseif joint:IsA("AnimationConstraint") or joint:IsA("RigidConstraint") then
   local a0,a1=joint.Attachment0,joint.Attachment1
   local p0=a0 and a0:FindFirstAncestorWhichIsA("BasePart")
   local p1=a1 and a1:FindFirstAncestorWhichIsA("BasePart")
   if p0 and p1 then
    local edge={joint=joint,a=p0,b=p1,c0=p0.CFrame:ToObjectSpace(a0.WorldCFrame),c1=p1.CFrame:ToObjectSpace(a1.WorldCFrame),motor=joint:IsA("AnimationConstraint")}
    add(edge.a,edge); add(edge.b,edge)
   end
  elseif joint:IsA("WeldConstraint") and joint.Part0 and joint.Part1 then
   local edge={a=joint.Part0,b=joint.Part1,c0=joint.Part0.CFrame:ToObjectSpace(joint.Part1.CFrame),c1=CFrame.identity}
   add(edge.a,edge); add(edge.b,edge)
  end
 end
 local info={root=root,edges=edges,rank=model:GetAttribute("PodiumRank") or 1,count=#model:GetDescendants()}
 cache[model]=info
 return info
end
local function rotation(rank,name,time)
 local n=string.lower(name):gsub("%s","")
 if n=="leftarmjoint" then n="leftshoulder" elseif n=="rightarmjoint" then n="rightshoulder" end
 local wave=math.sin(time*2.5)
 if rank==1 then
  if n=="leftshoulder" then return CFrame.Angles(math.rad(8+wave*2),0,math.rad(-150-wave*3)) end
  if n=="rightshoulder" then return CFrame.Angles(math.rad(8-wave*2),0,math.rad(150+wave*3)) end
  if n=="leftelbow" or n=="rightelbow" then return CFrame.Angles(math.rad(12),0,0) end
  if n=="neck" then return CFrame.Angles(math.rad(8),0,0) end
 elseif rank==2 then
  if n=="leftshoulder" then return CFrame.Angles(math.rad(40),0,math.rad(65)) end
  if n=="rightshoulder" then return CFrame.Angles(math.rad(40),0,math.rad(-65)) end
  if n=="leftelbow" or n=="rightelbow" then return CFrame.Angles(math.rad(25),0,0) end
 elseif rank==3 then
  if n=="neck" then return CFrame.Angles(math.rad(-32-wave*2),0,0) end
  if n=="waist" then return CFrame.Angles(math.rad(-8),0,0) end
  if n=="leftshoulder" then return CFrame.Angles(math.rad(5),0,math.rad(8)) end
  if n=="rightshoulder" then return CFrame.Angles(math.rad(5),0,math.rad(-8)) end
 end
 return CFrame.identity
end
function Podium.Update(scene,time)
 local blend=math.clamp(time/0.85,0,1); blend=blend*blend*(3-2*blend)
 for _,model in ipairs(scene:GetChildren()) do
  if model:IsA("Model") and model:GetAttribute("PodiumRank") then
   local info=cache[model]
   if not info or info.count~=#model:GetDescendants() then info=build(model) end
   if info then
    local queue={info.root}; local visited={[info.root]=true}; local index=1
    while index<=#queue do
     local parent=queue[index]; index+=1
     for _,edge in ipairs(info.edges[parent] or {}) do
      local child=edge.a==parent and edge.b or edge.a
      if not visited[child] then
       visited[child]=true
       local c0=edge.c0
       if edge.motor then
        local offset=CFrame.identity:Lerp(rotation(info.rank,edge.joint.Name,time),blend)
        c0=CFrame.new(c0.Position)*offset*c0.Rotation
       end
       if edge.a==parent then child.CFrame=parent.CFrame*c0*edge.c1:Inverse()
       else child.CFrame=parent.CFrame*edge.c1*c0:Inverse() end
       table.insert(queue,child)
      end
     end
    end
    for _,obj in ipairs(model:GetDescendants()) do
     if obj:IsA("ParticleEmitter") and obj:GetAttribute("PodiumMagic") then obj.Enabled=info.rank==1 and blend>0.65 end
    end
   end
  end
 end
end
return Podium