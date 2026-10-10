local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")
local remote=game:GetService("ReplicatedStorage"):WaitForChild("VoiceArena"):WaitForChild("PresetFx")
local bubbles={}
remote.OnClientEvent:Connect(function(op)
 if type(op)~="table" or op.op~="deflect_cast" or not op.target then return end
 local old=bubbles[op.target]
 if old then old.part:Destroy() end
 local p=Instance.new("Part")
 p.Name="DeflectBubbleFX"; p.Shape=Enum.PartType.Ball
 p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CanTouch=false; p.CastShadow=false
 p.Material=Enum.Material.ForceField; p.Color=Color3.fromRGB(110,210,255); p.Transparency=.35
 p.Size=Vector3.one*.1
 local root=op.target:FindFirstChild("HumanoidRootPart")
 if root then p.CFrame=root.CFrame end
 p.Parent=workspace
 TweenService:Create(p,TweenInfo.new(.16,Enum.EasingStyle.Back),{Size=Vector3.one*op.radius*2}):Play()
 bubbles[op.target]={part=p,endsAt=op.endsAt,radius=op.radius}
end)
RunService.RenderStepped:Connect(function()
 local now=workspace:GetServerTimeNow()
 for character,st in pairs(bubbles) do
  local root=character:FindFirstChild("HumanoidRootPart")
  local h=character:FindFirstChildOfClass("Humanoid")
  if not root or not character.Parent or not h or h.Health<=0 or now>=st.endsAt then
   st.part:Destroy(); bubbles[character]=nil
  else
   st.part.CFrame=CFrame.new(root.Position)*CFrame.Angles(0,now*.8,now*.2)
   st.part.Transparency=.35+math.sin(now*9)*.07
  end
 end
end)
