local templates=game:GetService("ServerStorage"):WaitForChild("SpellTestDummyTemplates")
local folder=workspace:WaitForChild("SpellTestDummies")
local prompt=workspace.Maps:FindFirstChild("ResetTestDummies",true)
local generations={}
local function connect(dummy)
 local humanoid=dummy:FindFirstChildOfClass("Humanoid")
 local root=dummy:FindFirstChild("HumanoidRootPart")
 if root then pcall(function() root:SetNetworkOwner(nil) end) end
 humanoid.Died:Connect(function()
  local name=dummy.Name
  local generation=generations[name]
  task.delay(5,function()
   if dummy.Parent and generations[name]==generation then
    local template=templates:FindFirstChild(name)
    if template then
     dummy:Destroy()
     local replacement=template:Clone()
     replacement.Parent=folder
     connect(replacement)
    end
   end
  end)
 end)
end
local function reset()
 for _,template in templates:GetChildren() do
  generations[template.Name]=(generations[template.Name] or 0)+1
  local old=folder:FindFirstChild(template.Name)
  if old then old:Destroy() end
  local dummy=template:Clone()
  dummy.Parent=folder
  connect(dummy)
 end
end
for _,dummy in folder:GetChildren() do generations[dummy.Name]=1 connect(dummy) end
if prompt then prompt.Triggered:Connect(reset) end
task.spawn(function()
 while folder.Parent do
  task.wait(2)
  for _,dummy in folder:GetChildren() do
   local root=dummy:FindFirstChild("HumanoidRootPart")
   local home=dummy:GetAttribute("HomeCFrame")
   if root and home and root.Position.Y<home.Position.Y-80 then
    local template=templates:FindFirstChild(dummy.Name)
    if template then
     generations[dummy.Name]=(generations[dummy.Name] or 0)+1
     dummy:Destroy()
     local replacement=template:Clone()
     replacement.Parent=folder
     connect(replacement)
    end
   end
  end
 end
end)
