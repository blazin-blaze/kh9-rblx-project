-- Pop-in victory banner, black transition, then a podium pullback.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local PodiumEmotes=require(script:WaitForChild("PodiumEmotes"))
local Input=game:GetService("ContextActionService")
local player=Players.LocalPlayer
local folder=game:GetService("ReplicatedStorage"):WaitForChild("VoiceArena")
local gui=Instance.new("ScreenGui"); gui.Name="VictoryCinematic"; gui.IgnoreGuiInset=true; gui.ResetOnSpawn=false; gui.DisplayOrder=1100; gui.Enabled=false; gui.Parent=player:WaitForChild("PlayerGui")
local function frame(size,pos)
 local f=Instance.new("Frame"); f.Size=size; f.Position=pos; f.BorderSizePixel=0; f.BackgroundColor3=Color3.new(); f.Parent=gui; return f
end
local top=frame(UDim2.fromScale(1,0.1),UDim2.fromScale(0,0))
local bottom=frame(UDim2.fromScale(1,0.1),UDim2.fromScale(0,0.9))
local fade=frame(UDim2.fromScale(1,1),UDim2.fromScale(0,0)); fade.ZIndex=10
local text=Instance.new("TextLabel"); text.AnchorPoint=Vector2.new(0.5,0.5); text.Position=UDim2.fromScale(0.5,0.43); text.Size=UDim2.fromScale(0.75,0.18)
text.BackgroundTransparency=1; text.Font=Enum.Font.GothamBlack; text.Text="VICTORY"; text.TextScaled=true; text.TextColor3=Color3.fromRGB(255,216,100); text.TextStrokeColor3=Color3.fromRGB(80,44,8); text.TextStrokeTransparency=0.3; text.ZIndex=2; text.Parent=gui
local constraint=Instance.new("UITextSizeConstraint"); constraint.MaxTextSize=100; constraint.Parent=text
local scale=Instance.new("UIScale"); scale.Parent=text
local active=false
local saved,hidden
local function restore()
 if not active then return end
 active=false; RunService:UnbindFromRenderStep("VictoryCinematic"); gui.Enabled=false
 Input:UnbindAction("VictoryCinematicMovement")
 for screen,enabled in pairs(hidden or {}) do if screen.Parent then screen.Enabled=enabled end end
 local camera=workspace.CurrentCamera
 if camera and saved then
  camera.CameraType=saved.kind; camera.FieldOfView=saved.fov
  camera.CameraSubject=(player.Character and player.Character:FindFirstChildOfClass("Humanoid")) or saved.subject
 end
 saved=nil; hidden=nil
end
local function begin()
 if folder:GetAttribute("MatchState")~="Victory" then restore(); return end
 if active then return end
 local start=folder:GetAttribute("VictoryStart")
 local a,b=folder:GetAttribute("VictoryFrom"),folder:GetAttribute("VictoryTo")
 local camera=workspace.CurrentCamera
 if not camera or type(start)~="number" or typeof(a)~="CFrame" or typeof(b)~="CFrame" then return end
 local duration=folder:GetAttribute("VictoryDuration") or 7.5
 saved={kind=camera.CameraType,fov=camera.FieldOfView,subject=camera.CameraSubject,cframe=camera.CFrame}
 hidden={}
 for _,screen in ipairs(player.PlayerGui:GetChildren()) do
  if screen:IsA("ScreenGui") and screen~=gui and screen.Name~="LogoTransition" then hidden[screen]=screen.Enabled; screen.Enabled=false end
 end
 Input:BindActionAtPriority("VictoryCinematicMovement",function() return Enum.ContextActionResult.Sink end,false,3000,unpack(Enum.PlayerActions:GetEnumItems()))
 active=true; gui.Enabled=true
 RunService:BindToRenderStep("VictoryCinematic",Enum.RenderPriority.Camera.Value+20,function()
  local cam=workspace.CurrentCamera
  if not cam then return end
  local t=workspace:GetServerTimeNow()-start
  if folder:GetAttribute("MatchState")~="Victory" or t>duration+1 then restore(); return end
  cam.CameraType=Enum.CameraType.Scriptable
  local scene=workspace:FindFirstChild("VictoryPodium")
  if scene then PodiumEmotes.Update(scene,math.max(0,t-1.8)) end
  local x=math.clamp(t/0.45,0,1)
  -- Back-out easing produces a quick overshoot and settle.
  local u=x-1
  scale.Scale=0.3+0.7*(1+2.70158*u*u*u+1.70158*u*u)
  text.Visible=t>=0 and t<1.5
  text.TextTransparency=math.clamp((t-1)/0.45,0,1)
  text.TextStrokeTransparency=0.3+text.TextTransparency*0.7
  top.Visible=t>=1.5; bottom.Visible=t>=1.5
  if t<1.5 then
   cam.CFrame=saved.cframe
   fade.BackgroundTransparency=1-math.clamp((t-1)/0.5,0,1)
  else
   local progress=math.clamp((t-1.8)/(duration-2.3),0,1)
   progress=progress*progress*(3-2*progress)
   cam.CFrame=a:Lerp(b,progress); cam.FieldOfView=48+10*progress
   local opacity=math.max(1-math.clamp((t-1.8)/0.4,0,1),math.clamp((t-(duration-0.4))/0.4,0,1))
   fade.BackgroundTransparency=1-opacity
  end
 end)
end
folder:GetAttributeChangedSignal("MatchState"):Connect(begin)
local retryAt=0
RunService.Heartbeat:Connect(function()
 if not active and folder:GetAttribute("MatchState")=="Victory" and os.clock()>retryAt then retryAt=os.clock()+0.1; begin() end
end)
script.Destroying:Connect(restore)
begin()