-- Stages fighters and publishes synchronized camera shots before combat.
local Players = game:GetService("Players")
local Ultimate = require(script.Parent.UltimateService)
local Intro = {}
local OPENING_SHOT = 2.2
local SHOT_ONE, SHOT_TWO, OUTRO = 2, 3, 0.4
local TOTAL = OPENING_SHOT * 2 + SHOT_ONE + SHOT_TWO + OUTRO
local serial = 0

function Intro.Play(folder, fighters, spots, center, ready)
 local maps = workspace:FindFirstChild("Maps")
 local ring = maps and maps:FindFirstChild("RingModel")
 center = center or (ring and ring:GetBoundingBox().Position) or Vector3.new(0, 5, 0)
 local focusMarker = maps and maps:FindFirstChild("MatchIntroFocus", true)
 local focus = focusMarker and (focusMarker:IsA("BasePart") and focusMarker.Position or focusMarker:IsA("Model") and focusMarker:GetPivot().Position)
 local statue
 local nearest=math.huge
 if maps then
  for _,obj in ipairs(maps:GetDescendants()) do
   if obj.Name=="patung" and obj:IsA("BasePart") then
    local distance=(obj.Position-center).Magnitude
    if distance<nearest then statue=obj; nearest=distance end
   end
  end
 end
 focus = focus or (statue and statue.Position) or center + Vector3.new(0, 3, 0)
 local shotFrom,shotTo
 if statue and not focusMarker then
  -- The giant patung faces the arena. Start at its chest, then reveal the ring below.
  local toward=Vector3.new(center.X-focus.X,0,center.Z-focus.Z).Unit
  local side=Vector3.new(toward.Z,0,-toward.X)
  local scale=statue.Size.Y/336
  shotFrom=CFrame.lookAt(focus+toward*140*scale+side*30*scale+Vector3.new(0,60*scale,0),focus+Vector3.new(0,90*scale,0))
  shotTo=CFrame.lookAt(center+toward*140+side*118+Vector3.new(0,137,0),center-toward*95+Vector3.new(0,160,0))
 else
  shotFrom=CFrame.lookAt(focus+Vector3.new(0,7,22),focus)
  shotTo=CFrame.lookAt(focus+Vector3.new(18,48,105),center)
 end
 local staged, protections = {}, {}
 for _, p in ipairs(Players:GetPlayers()) do Ultimate.Cancel(p) end
 local lineup = {}
 for _, p in ipairs(ready) do
  local char = fighters[p]
  local root = char and char:FindFirstChild("HumanoidRootPart")
  local h = char and char:FindFirstChildOfClass("Humanoid")
  if root and h and h.Health > 0 then table.insert(lineup, p) end
 end
 local spacing = math.min(8, 36 / math.max(1, #lineup - 1))
 local half = (#lineup - 1) * spacing / 2
 local base = center + Vector3.new(0, 0, 35)
 local params = RaycastParams.new()
 params.FilterType = Enum.RaycastFilterType.Exclude
 params.RespectCanCollide = true
 local ignore = {}
 for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(ignore, p.Character) end end
 params.FilterDescendantsInstances = ignore
 for i, p in ipairs(lineup) do
  local char = fighters[p]
  local root = char.HumanoidRootPart
  local h = char:FindFirstChildOfClass("Humanoid")
  staged[p] = {root=root, anchored=root.Anchored, auto=h.AutoRotate, humanoid=h}
  local at = base + Vector3.new((i-1)*spacing-half, 0, 0)
  local ground = workspace:Raycast(at+Vector3.new(0,60,0), Vector3.new(0,-120,0),params)
  at = Vector3.new(at.X, ground and ground.Position.Y or center.Y, at.Z) + Vector3.new(0,h.HipHeight+root.Size.Y/2,0)
  char:PivotTo(CFrame.lookAt(at, at+Vector3.zAxis))
  root.AssemblyLinearVelocity=Vector3.zero
  root.AssemblyAngularVelocity=Vector3.zero
  root.Anchored=true
  h.AutoRotate=false
  local shield=Instance.new("ForceField")
  shield.Name="MatchIntroProtection"; shield.Visible=false; shield.Parent=char
  table.insert(protections,shield)
 end
 local y = #lineup>0 and fighters[lineup[1]].HumanoidRootPart.Position.Y+1 or center.Y+4
 -- A short fixed track keeps the camera on the fighters for the full three seconds.
 local left = Vector3.new(base.X-8,y,base.Z)
 local right = Vector3.new(base.X+8,y,base.Z)
 -- Two brief establishing shots: skull waterfall, then the glowing arena runes.
 folder:SetAttribute("IntroOpeningDuration", OPENING_SHOT)
 folder:SetAttribute("IntroOpening1From", CFrame.lookAt(center+Vector3.new(-100,60,70),center+Vector3.new(-130,40,-60)))
 folder:SetAttribute("IntroOpening1To", CFrame.lookAt(center+Vector3.new(-83,65,66),center+Vector3.new(-130,45,-60)))
 folder:SetAttribute("IntroOpening2From", CFrame.lookAt(center+Vector3.new(-50,18,10),center+Vector3.new(0,2,0)))
 folder:SetAttribute("IntroOpening2To", CFrame.lookAt(center+Vector3.new(-35,22,24),center+Vector3.new(0,2,0)))
 folder:SetAttribute("IntroShot1From", shotFrom)
 folder:SetAttribute("IntroShot1To", shotTo)
 folder:SetAttribute("IntroShot2From", CFrame.lookAt(left+Vector3.new(0,0.5,18),left))
 folder:SetAttribute("IntroShot2To", CFrame.lookAt(right+Vector3.new(0,0.5,18),right))
 folder:SetAttribute("IntroShot1Duration",SHOT_ONE)
 folder:SetAttribute("IntroShot2Duration",SHOT_TWO)
 folder:SetAttribute("IntroDuration",TOTAL)
 serial+=1
 folder:SetAttribute("IntroId",serial)
 local start=workspace:GetServerTimeNow()+0.6
 folder:SetAttribute("IntroStart",start)
 folder:SetAttribute("MatchState","Intro")
 print("[MatchIntro] Started: "..tostring(#lineup).." fighters")
 folder:SetAttribute("MatchText","MEET THE CHALLENGERS")
 folder:SetAttribute("MatchTime",start+TOTAL)
 local ok,err=pcall(function()
  while workspace:GetServerTimeNow()<start+TOTAL do task.wait(0.1) end
 end)
 -- Always release the exact characters staged, even after a reset or disconnect.
 for i,p in ipairs(ready) do
  local held=staged[p]
  local char=fighters[p]
  if held then
   if p.Character==char and char.Parent and held.humanoid.Health>0 and spots then
    local at=spots[i]+Vector3.new(0,4,0)
    local target=Vector3.new(center.X,at.Y,center.Z)
    if (target-at).Magnitude<1 then target=at-Vector3.zAxis end
    char:PivotTo(CFrame.lookAt(at,target))
   end
   if held.root.Parent then
    held.root.AssemblyLinearVelocity=Vector3.zero
    held.root.AssemblyAngularVelocity=Vector3.zero
    held.root.Anchored=held.anchored
   end
   if held.humanoid.Parent then held.humanoid.AutoRotate=held.auto end
  end
 end
 for _,shield in ipairs(protections) do shield:Destroy() end
 print("[MatchIntro] Finished; releasing fighters")
 if not ok then warn("[MatchIntro] "..tostring(err)) end
end
return Intro