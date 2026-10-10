-- Roblox microphone loudness only; spoken commands still come from the ElevenLabs companion.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local SoundService=game:GetService("SoundService")
local player=Players.LocalPlayer
local folder=ReplicatedStorage:WaitForChild("VoiceArena")
local remote=folder:WaitForChild("UltimateVolume")
local audioFolder=Instance.new("Folder"); audioFolder.Name="UltimateVoiceAnalysis"; audioFolder.Parent=SoundService
local analyzer=Instance.new("AudioAnalyzer"); analyzer.SpectrumEnabled=false; analyzer.Parent=audioFolder
local wire=Instance.new("Wire"); wire.TargetInstance=analyzer; wire.Parent=audioFolder
local input
local function bind()
 local fallback
 for _,v in player:GetChildren() do
  if v:IsA("AudioDeviceInput") then
   if v.Name~="UltimateMicrophone" then input=v; wire.SourceInstance=v; return end
   fallback=v
  end
 end
 input=fallback; wire.SourceInstance=input
end
bind()
player.ChildAdded:Connect(function(v) if v:IsA("AudioDeviceInput") then bind() end end)
player.ChildRemoved:Connect(function(v) if v==input then bind() end end)
local function new(class,props)
 local v=Instance.new(class)
 for key,value in props do if key~="Parent" then v[key]=value end end
 v.Parent=props.Parent
 return v
end
-- Panel drawn from the illustrated "Ultimate" design: chain-bordered slate panel, ornate bars with a star
-- and swirls. Art is three uploaded images (ART below); live text and both bar fills are drawn on top.
-- Until the images are uploaded (ids still "IMG_..."), a drawn stand-in with the same layout is used.
local ART={
 panel="rbxassetid://103168572806421",
 frame="rbxassetid://98626378771434",
 fill="rbxassetid://103357868572437",
 glow="rbxassetid://106049974797783",
}
local HAS_ART=not string.find(ART.panel..ART.frame..ART.fill,"IMG_",1,true)
local SERIF=Font.fromEnum(Enum.Font.Garamond)
local INK=Color3.fromRGB(246,246,242)
local DW,DH=619,454 -- design pixels of the source illustration
local function at(x,y) return UDim2.fromScale(x/DW,y/DH) end
local function sz(w,h) return UDim2.fromScale(w/DW,h/DH) end
-- the bar frame image is a 490x117 crop; its fill area runs x 39..461, y 21..56 inside it
local BW,BH,FX0,FX1,FY0,FY1=490,117,39,461,21,56

local gui=new("ScreenGui",{Name="UltimateHUD",ResetOnSpawn=false,Parent=player:WaitForChild("PlayerGui")})
local panel=new("ImageLabel",{Name="Ultimate",Image=HAS_ART and ART.panel or "",Size=UDim2.fromOffset(340,340*DH/DW),
 Position=UDim2.new(0,14,1,-218),AnchorPoint=Vector2.new(0,1),BackgroundTransparency=1,ZIndex=2,Parent=gui})
local scale=new("UIScale",{Parent=panel})
local glow=new("ImageLabel",{Name="ReadyGlow",Image=ART.glow,ImageColor3=Color3.fromRGB(90,255,225),ImageTransparency=1,
 Size=UDim2.fromScale(1.35,1.5),AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),BackgroundTransparency=1,
 ZIndex=1,Parent=panel})
if not HAS_ART then
 local inner=new("Frame",{Size=sz(520,345),Position=at(50,55),BackgroundColor3=Color3.fromRGB(51,51,51),ZIndex=2,Parent=panel})
 new("UICorner",{CornerRadius=UDim.new(0,10),Parent=inner})
 new("UIStroke",{Color=INK,Thickness=3,Parent=inner})
end
local function text(name,props)
 local t=new("TextLabel",{Name=name,BackgroundTransparency=1,FontFace=props.font or SERIF,TextScaled=true,
  TextColor3=props.color or INK,TextXAlignment=props.align or Enum.TextXAlignment.Left,Text=props.text or "",
  Position=props.pos,Size=props.size,ZIndex=props.z or 5,TextStrokeTransparency=props.stroke or 1,Parent=props.parent or panel})
 new("UITextSizeConstraint",{MaxTextSize=props.max or 40,MinTextSize=props.min or 6,Parent=t})
 return t
end
text("Title",{text="- Ultimate -",pos=at(110,66),size=sz(400,66),align=Enum.TextXAlignment.Center,max=34})
text("ChargeLabel",{text="Charge Time",pos=at(60,132),size=sz(260,46),max=24})
text("PowerLabel",{text="Volume Power",pos=at(60,250),size=sz(280,46),max=24})

-- An ornate bar: grey track + gradient fill (both cut to the bar's slanted shape) under the line-art frame.
-- set(f) reveals the fill from the star end to the pointed tip.
local function bar(x,y,c0,c1)
 local box=new("Frame",{Position=at(x,y),Size=sz(BW,BH),BackgroundTransparency=1,ZIndex=3,Parent=panel})
 local bar={box=box}
 local gradient
 if HAS_ART then
  new("ImageLabel",{Image=ART.fill,ImageColor3=Color3.fromRGB(101,101,101),Size=UDim2.fromScale(1,1),
   BackgroundTransparency=1,ZIndex=3,Parent=box})
  local fill=new("ImageLabel",{Image=ART.fill,Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ZIndex=4,Parent=box})
  gradient=new("UIGradient",{Color=ColorSequence.new(c0,c1),Parent=fill})
  new("ImageLabel",{Image=ART.frame,Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ZIndex=5,Parent=box})
  function bar.set(f)
   f=math.clamp(f,0,1)
   if f<=0.001 then gradient.Transparency=NumberSequence.new(1) return end
   local t=math.clamp((FX0+f*(FX1-FX0))/BW,0.002,0.997)
   gradient.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(t,0),
    NumberSequenceKeypoint.new(t+0.002,1),NumberSequenceKeypoint.new(1,1)})
  end
 else
  local track=new("Frame",{Position=UDim2.fromScale(FX0/BW,FY0/BH),Size=UDim2.fromScale((FX1-FX0)/BW,(FY1-FY0)/BH),
   BackgroundColor3=Color3.fromRGB(101,101,101),ZIndex=3,Parent=box})
  new("UICorner",{CornerRadius=UDim.new(0.5,0),Parent=track})
  new("UIStroke",{Color=INK,Thickness=3,Parent=track})
  local fill=new("Frame",{Size=UDim2.fromScale(0,1),BackgroundColor3=Color3.new(1,1,1),ZIndex=4,Parent=track})
  new("UICorner",{CornerRadius=UDim.new(0.5,0),Parent=fill})
  new("UIGradient",{Color=ColorSequence.new(c0,c1),Parent=fill})
  function bar.set(f) fill.Size=UDim2.fromScale(math.clamp(f,0,1),1) end
 end
 -- live status text sits inside the bar
 bar.label=text("Status",{parent=box,font=Font.fromEnum(Enum.Font.GothamBold),max=13,min=6,stroke=0.2,
  pos=UDim2.fromScale((FX0+44)/BW,(FY0+2)/BH),size=UDim2.fromScale((FX1-FX0-70)/BW,(FY1-FY0-4)/BH),z=6})
 -- fixed 11px text that steps down only when a long status line wouldn't fit in the bar
 local label=bar.label
 label.TextScaled=false
 label.TextWrapped=false
 label:FindFirstChildOfClass("UITextSizeConstraint"):Destroy()
 local TextService=game:GetService("TextService")
 local function fit()
  local width=label.AbsoluteSize.X/math.max(scale.Scale,0.01)
  local size=11
  while size>7 and TextService:GetTextSize(label.Text,size,Enum.Font.GothamBold,Vector2.new(1e4,100)).X>width do size-=1 end
  label.TextSize=size
 end
 label:GetPropertyChangedSignal("Text"):Connect(fit)
 label:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
 return bar
end
local chargeBar=bar(64,171,Color3.fromRGB(115,240,220),Color3.fromRGB(100,212,150))
local powerBar=bar(75,287,Color3.fromRGB(120,225,255),Color3.fromRGB(185,255,235))
local stateText=chargeBar.label
local micText=powerBar.label
local hint=text("Hint",{pos=at(108,362),size=sz(292,28),font=Font.fromEnum(Enum.Font.GothamMedium),max=11,
 color=Color3.fromRGB(205,215,212)})
-- the player's ultimate word, set by Loadout when they press Begin in the "Set Your Spells" screen
local function word() return player:GetAttribute("UltimateWord") or "Ultimate" end
hint.Text="Say "..word()..", then sustain your voice"
local accumulated=0
local heardAt=0
RunService.RenderStepped:Connect(function(dt)
 local camera=workspace.CurrentCamera
 if camera then scale.Scale=math.clamp((camera.ViewportSize.X-32)/700,0.7,1) end
 local rms=input and not input.Muted and analyzer.RmsLevel or 0
 if rms~=rms then rms=0 end
 rms=math.clamp(rms,0,1)
 local floor=folder:GetAttribute("UltimateNoiseFloor") or 0.008
 local ceiling=folder:GetAttribute("UltimateFullPowerRms") or 0.18
 local measured=math.clamp((rms-floor)/(ceiling-floor),0,1)^0.55
 if measured>0.01 then heardAt=os.clock() end
 accumulated+=dt
 if accumulated>=0.1 then
  accumulated=0
  if player.Character then remote:FireServer(player.Character,rms) end
 end
 local time=workspace:GetServerTimeNow()
 local active=player:GetAttribute("UltimateActive")
 local remaining=math.max(0,(player:GetAttribute(active and "UltimateEndsAt" or "UltimateReadyAt") or time+10)-time)
 local charge=player:GetAttribute("UltimateChargeSeconds") or 10
 local power=active and (player:GetAttribute("UltimatePower") or 0) or measured
 powerBar.set(power)
 if active then
  stateText.Text=string.format("FIRING  %.1fs  /  %d%% POWER",remaining,math.floor(power*100+0.5))
  chargeBar.set(remaining/5)
  hint.Text="Louder = bigger beam. Turn with WASD to sweep"
 elseif remaining>0 then
  stateText.Text=string.format("CHARGING  %.1fs",remaining)
  chargeBar.set(1-remaining/charge)
  hint.Text="Say "..word().." when the charge is full"
 else
  stateText.Text='READY  /  SAY "'..string.upper(word())..'!"'
  chargeBar.set(1)
  hint.Text="Say "..word()..", then sustain your voice"
 end
 glow.ImageTransparency=remaining==0 and not active and (0.55+0.25*math.sin(os.clock()*4)) or (active and 0.45 or 1)
 if not input then micText.Text="Waiting for Roblox microphone"
 elseif input.Muted then micText.Text="Roblox microphone muted — unmute voice"
 elseif os.clock()-heardAt<10 and heardAt>0 then micText.Text=string.format("ROBLOX MIC  /  %d%%",math.floor(measured*100+0.5))
 else micText.Text="Waiting for mic audio — check voice settings" end
end)
