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
local gui=new("ScreenGui",{Name="UltimateHUD",ResetOnSpawn=false,Parent=player:WaitForChild("PlayerGui")})
local panel=new("Frame",{Name="Ultimate",Size=UDim2.fromOffset(270,132),Position=UDim2.new(0,18,1,-224),
 AnchorPoint=Vector2.new(0,1),BackgroundColor3=Color3.fromRGB(22,15,36),BackgroundTransparency=0.1,Parent=gui})
new("UICorner",{CornerRadius=UDim.new(0,14),Parent=panel})
local stroke=new("UIStroke",{Color=Color3.fromRGB(170,85,255),Thickness=2,Parent=panel})
local scale=new("UIScale",{Parent=panel})
local function label(name,y,height,size,color)
 return new("TextLabel",{Name=name,Position=UDim2.fromOffset(14,y),Size=UDim2.new(1,-28,0,height),
  BackgroundTransparency=1,TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.GothamBold,
  TextSize=size,TextColor3=color or Color3.fromRGB(240,230,255),Text="",Parent=panel})
end
label("Title",8,20,15).Text="ULTIMATE  /  DEATH BEAM"
local stateText=label("State",30,20,14)
local function bar(y,color)
 local bg=new("Frame",{Position=UDim2.fromOffset(14,y),Size=UDim2.new(1,-28,0,7),
  BackgroundColor3=Color3.fromRGB(55,42,74),BorderSizePixel=0,Parent=panel})
 new("UICorner",{CornerRadius=UDim.new(1,0),Parent=bg})
 local fill=new("Frame",{Size=UDim2.fromScale(0,1),BackgroundColor3=color,BorderSizePixel=0,Parent=bg})
 new("UICorner",{CornerRadius=UDim.new(1,0),Parent=fill})
 return fill
end
local chargeBar=bar(55,Color3.fromRGB(190,100,255))
local micText=label("Mic",68,18,11,Color3.fromRGB(190,180,215))
local powerBar=bar(90,Color3.fromRGB(255,160,235))
local hint=label("Hint",101,23,11,Color3.fromRGB(180,165,200))
hint.Text="Say ultimate, then sustain your voice"
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
 powerBar.Size=UDim2.fromScale(power,1)
 if active then
  stateText.Text=string.format("FIRING  %.1fs  /  %d%% POWER",remaining,math.floor(power*100+0.5))
  chargeBar.Size=UDim2.fromScale(math.clamp(remaining/5,0,1),1)
  hint.Text="Hold your voice; aim with your mouse"
 elseif remaining>0 then
  stateText.Text=string.format("CHARGING  %.1fs",remaining)
  chargeBar.Size=UDim2.fromScale(math.clamp(1-remaining/charge,0,1),1)
  hint.Text="Say ultimate when the charge is full"
 else
  stateText.Text='READY  /  SAY "ULTIMATE!"'
  chargeBar.Size=UDim2.fromScale(1,1)
  hint.Text="Say ultimate, then sustain your voice"
 end
 stroke.Transparency=remaining==0 and not active and (0.15+0.25*math.sin(os.clock()*4)) or 0
 if not input then micText.Text="Waiting for Roblox microphone"
 elseif input.Muted then micText.Text="Roblox microphone muted — unmute voice"
 elseif os.clock()-heardAt<10 and heardAt>0 then micText.Text=string.format("ROBLOX MIC  /  %d%%",math.floor(measured*100+0.5))
 else micText.Text="Waiting for mic audio — check voice settings" end
end)
