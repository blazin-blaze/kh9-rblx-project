-- Four synchronized cinematic shots; gameplay camera is restored on exit.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local player=Players.LocalPlayer
local folder=game:GetService("ReplicatedStorage"):WaitForChild("VoiceArena")
local input=game:GetService("ContextActionService")
local gui=Instance.new("ScreenGui")
gui.Name="MatchCinematic"; gui.IgnoreGuiInset=true; gui.ResetOnSpawn=false; gui.DisplayOrder=1000
gui.Parent=player:WaitForChild("PlayerGui"); gui.Enabled=false
local function frame(size,pos)
 local f=Instance.new("Frame"); f.Size=size; f.Position=pos; f.BorderSizePixel=0; f.BackgroundColor3=Color3.new(); f.Parent=gui
 return f
end
frame(UDim2.fromScale(1,0.1),UDim2.fromScale(0,0))
frame(UDim2.fromScale(1,0.1),UDim2.fromScale(0,0.9))
local fade=frame(UDim2.fromScale(1,1),UDim2.fromScale(0,0)); fade.ZIndex=3
local title=Instance.new("TextLabel")
title.Size=UDim2.fromScale(1,0.07); title.Position=UDim2.fromScale(0,0.91); title.BackgroundTransparency=1
title.Font=Enum.Font.GothamBold; title.TextSize=20; title.TextColor3=Color3.fromRGB(220,255,245)
title.Visible=false
title.Parent=gui
local active, savedCamera, hidden=false,nil,{}
local function restore()
 if not active then return end
 active=false
 RunService:UnbindFromRenderStep("MatchCinematic")
 gui.Enabled=false
 for screen,enabled in pairs(hidden) do if screen.Parent then screen.Enabled=enabled end end
 hidden={}
 local cam=workspace.CurrentCamera
 if cam and savedCamera then
  cam.CameraType=savedCamera.kind
  cam.FieldOfView=savedCamera.fov
  local h=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
  cam.CameraSubject=h or savedCamera.subject
 end
 input:UnbindAction("MatchCinematicMovement")
 savedCamera=nil
end
local function begin()
 if folder:GetAttribute("MatchState")~="Intro" then restore(); return end
 local cam=workspace.CurrentCamera
 local a,b,c,d=folder:GetAttribute("IntroShot1From"),folder:GetAttribute("IntroShot1To"),folder:GetAttribute("IntroShot2From"),folder:GetAttribute("IntroShot2To")
 local start=folder:GetAttribute("IntroStart")
 local opening=folder:GetAttribute("IntroOpeningDuration") or 0
 local o1,o2,o3,o4=folder:GetAttribute("IntroOpening1From"),folder:GetAttribute("IntroOpening1To"),folder:GetAttribute("IntroOpening2From"),folder:GetAttribute("IntroOpening2To")
 if opening>0 and (typeof(o1)~="CFrame" or typeof(o2)~="CFrame" or typeof(o3)~="CFrame" or typeof(o4)~="CFrame") then return end
 if not cam or typeof(a)~="CFrame" or typeof(b)~="CFrame" or typeof(c)~="CFrame" or typeof(d)~="CFrame" or type(start)~="number" then return end
 restore()
 savedCamera={kind=cam.CameraType,subject=cam.CameraSubject,fov=cam.FieldOfView}
 input:BindActionAtPriority("MatchCinematicMovement",function() return Enum.ContextActionResult.Sink end,false,3000,unpack(Enum.PlayerActions:GetEnumItems()))
 for _,screen in ipairs(player.PlayerGui:GetChildren()) do
  if screen:IsA("ScreenGui") and screen~=gui and screen.Name~="LogoTransition" then hidden[screen]=screen.Enabled; screen.Enabled=false end
 end
 active=true; gui.Enabled=true; cam.CameraType=Enum.CameraType.Scriptable
 local t1=folder:GetAttribute("IntroShot1Duration") or 2
 local t2=folder:GetAttribute("IntroShot2Duration") or 3
 local duration=folder:GetAttribute("IntroDuration") or opening*2+t1+t2+0.4
 RunService:BindToRenderStep("MatchCinematic",Enum.RenderPriority.Camera.Value+10,function()
  local camera=workspace.CurrentCamera
  if not camera then return end
  local t=workspace:GetServerTimeNow()-start
  if folder:GetAttribute("MatchState")~="Intro" or t>duration+2 then restore(); return end
  camera.CameraType=Enum.CameraType.Scriptable
  local mainTime=t-opening*2
  if opening>0 and t<opening then
   local x=math.clamp(t/opening,0,1)
   camera.CFrame=o1:Lerp(o2,x); camera.FieldOfView=60
   title.Text="THE FALLS"
  elseif opening>0 and t<opening*2 then
   local x=math.clamp((t-opening)/opening,0,1)
   camera.CFrame=o3:Lerp(o4,x); camera.FieldOfView=58
   title.Text="THE RUNE CIRCLE"
  elseif mainTime<t1 then
   local x=math.clamp(mainTime/t1,0,1); x=x*x*(3-2*x)
   camera.CFrame=a:Lerp(b,x); camera.FieldOfView=58+10*x
   title.Text="THE GUARDIAN"
  else
   local x=math.clamp((mainTime-t1)/t2,0,1)
   camera.CFrame=c:Lerp(d,x); camera.FieldOfView=50
   title.Text="THE CHALLENGERS"
  end
  local opacity=math.max(math.clamp(1-t/0.3,0,1),math.clamp((t-(duration-0.4))/0.4,0,1))
  for _,cut in ipairs({opening,opening*2,opening*2+t1}) do
   if cut>0 then opacity=math.max(opacity,math.clamp(1-math.abs(t-cut)/0.15,0,1)) end
  end
  fade.BackgroundTransparency=1-opacity
 end)
end
folder:GetAttributeChangedSignal("MatchState"):Connect(begin)
folder:GetAttributeChangedSignal("IntroStart"):Connect(function() if folder:GetAttribute("MatchState")=="Intro" then begin() end end)
-- Retry when camera or shot attributes replicate after the phase change.
local retryAt=0
RunService.Heartbeat:Connect(function()
 if not active and folder:GetAttribute("MatchState")=="Intro" and os.clock()>=retryAt then
  retryAt=os.clock()+0.1
  begin()
 end
end)
script.Destroying:Connect(restore)
begin()