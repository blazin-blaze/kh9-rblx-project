-- ServerScriptService.VoiceArena.MatchManager (Script)
-- Round loop: wait until 2+ players are ready (equipped a loadout in the "Set your spells" screen),
-- run an intermission countdown, then a last-player-standing match. Round state is published as
-- attributes on ReplicatedStorage.VoiceArena (MatchState, MatchTime, MatchText) and drawn by
-- StarterPlayerScripts.MatchHud. Fighters carry the player attribute InMatch; while a match runs,
-- Loadout.CastDef only lets fighters cast.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Loadout = require(script.Parent.Loadout)
local Intro = require(script.Parent.MatchIntro)
local ReadyZone = require(script.Parent.ReadyZone)
local Victory = require(script.Parent.MatchVictory)
local Ultimate = require(script.Parent.UltimateService)
local Transition = require(script.Parent.LogoTransition)

-- Solo test: with this script's SoloTest attribute ticked, one ready player is enough in Studio
-- playtests, so matches can be tried alone. A solo match runs until that player dies or resets.
-- Live servers always need 2. The attribute is read live, so it can be toggled mid-playtest.
local function minReady()
	return (RunService:IsStudio() and script:GetAttribute("SoloTest")) and 1 or 2
end
local INTERMISSION = 10 -- seconds; everyone must stay in the ready square
local RESULT_TIME = 5   -- seconds the winner is shown before the loop restarts
local RING_RADIUS = 55  -- fighters spawn within this many studs of Workspace.Maps.RingModel's center
local SPAWN_SPACING = 12 -- try to keep fighters at least this far apart

local folder = ReplicatedStorage:FindFirstChild("VoiceArena") or Instance.new("Folder")
folder.Name = "VoiceArena"; folder.Parent = ReplicatedStorage

-- state: "Waiting" | "Intermission" | "Match" | "Result"
-- time: server time the intermission ends at, or the match started at (workspace:GetServerTimeNow())
local function set(state, time, text)
	folder:SetAttribute("MatchState", state)
	folder:SetAttribute("MatchTime", time)
	folder:SetAttribute("MatchText", text)
end

local function readyPlayers()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if Loadout.IsEquipped(player) then table.insert(list, player) end
	end
	return list
end

local function sessionReady()
 local players=Players:GetPlayers()
 local all,inside,total,equipped=ReadyZone.Status(players,Loadout.IsEquipped)
 return all and total>=minReady(),inside,total,equipped
end

local function waitForPlayers()
 while true do
  local all,inside,total,equipped=sessionReady()
  if all then return end
  local text=string.format("%d/%d players ready",inside,total)
  if total<minReady() then text=text..string.format(" • Need %d players",minReady()) end
  set("Waiting",0,text)
  task.wait(0.2)
 end
end

-- Leaving, resetting or joining outside the square cancels the countdown.
local function intermission()
 local endsAt=workspace:GetServerTimeNow()+INTERMISSION
 while workspace:GetServerTimeNow()<endsAt do
  local all,inside,total=sessionReady()
  if not all then
   set("Waiting",0,string.format("%d/%d players ready",inside,total))
   return false
  end
  set("Intermission",endsAt,string.format("%d/%d players ready",inside,total))
  task.wait(0.1)
 end
 return sessionReady()
end

-- Random ground points above the ring, one per fighter. Only match spawns use these; every other
-- spawn (joining, being eliminated, after a match) stays at the normal SpawnLocation.
local function ringSpots(count)
	local maps = workspace:FindFirstChild("Maps")
	local ring = maps and maps:FindFirstChild("RingModel")
	if not ring then
		warn("[Match] Workspace.Maps.RingModel is missing; fighters spawn at the SpawnLocation")
		return nil
	end
	local center = ring:GetBoundingBox().Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local ignore = { ring }
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(ignore, player.Character) end
	end
	params.FilterDescendantsInstances = ignore
	local spots = {}
	for i = 1, count do
		local fallback
		for _ = 1, 20 do
			local angle = math.random() * 2 * math.pi
			local distance = RING_RADIUS * math.sqrt(math.random()) -- uniform over the circle
			local point = center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
			local hit = workspace:Raycast(point + Vector3.new(0, 60, 0), Vector3.new(0, -120, 0), params)
			if hit then
				fallback = fallback or hit.Position
				local spaced = true
				for _, other in ipairs(spots) do
					if (other - hit.Position).Magnitude < SPAWN_SPACING then spaced = false; break end
				end
				if spaced then fallback = hit.Position; break end
			end
		end
		spots[i] = fallback or center
	end
	return spots, center
end

-- Every spawn outside a match (joining, being eliminated, after a match) is put on the
-- Workspace.Maps.SpawnLocation pad. Roblox lifts a character above whatever blocks its spawn
-- point, including other players on the pad, which could leave players far above the map.
local function placeAtSpawn(player, character)
	-- Match spawns go above the ring instead. CharacterAdded can run before or after runMatch places
	-- the character, so check both the player's InMatch and the character's MatchSpawn mark.
	if player:GetAttribute("InMatch") or character:GetAttribute("MatchSpawn") then return end
	local maps = workspace:FindFirstChild("Maps")
	local spawn = maps and maps:FindFirstChild("SpawnLocation")
	if not spawn then return end
	if not character:WaitForChild("HumanoidRootPart", 5) or player.Character ~= character then return end
	if character:GetAttribute("MatchSpawn") then return end
	local spread = math.max(0, math.min(spawn.Size.X, spawn.Size.Z) / 2 - 2)
	local at = spawn.Position + Vector3.new(math.random() * 2 - 1, 0, math.random() * 2 - 1) * spread
		+ Vector3.new(0, spawn.Size.Y / 2 + 3, 0)
	character:PivotTo(CFrame.new(at) * character:GetPivot().Rotation)
end
local function trackSpawns(player)
	player.CharacterAdded:Connect(function(character) placeAtSpawn(player, character) end)
	if player.Character then task.spawn(placeAtSpawn, player, player.Character) end
end
Players.PlayerAdded:Connect(trackSpawns)
for _, player in ipairs(Players:GetPlayers()) do trackSpawns(player) end

local function standing(player, character)
	if not player.Parent or not character or not character.Parent or player.Character ~= character then return false end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Respawns every ready player above the ring, then waits until at most one is left. Returns the winner or nil.
-- `transition` (optional): the logo transition covering lobby -> intro. Fighters are respawned while the
-- screen is dark, and the intro is started so its first shot lines up with the logo fading out.
local function runMatch(transition)
	set("Preparing", 0, "Preparing the arena")
	local fighters = {} -- player -> the character they fight with; dying or respawning eliminates them
 local eliminated, recorded, templates, connections = {}, {}, {}, {}
 local function record(player)
  if fighters[player] and not recorded[player] then
   recorded[player]=true
   table.insert(eliminated,player)
  end
 end
	local ready = readyPlayers()
	local spots, center = ringSpots(#ready)
	for i, player in ipairs(ready) do
		player:SetAttribute("InMatch", true)
		local ok, err = pcall(player.LoadCharacter, player)
		if ok and player.Parent then
			fighters[player] = player.Character
    templates[player] = Victory.Capture(player.Character)
    local h=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if h then table.insert(connections,h.Died:Connect(function() record(player) end)) end
    table.insert(connections,player.CharacterAdded:Connect(function() record(player) end))
			if player.Character then player.Character:SetAttribute("MatchSpawn", true) end
			if spots and player.Character then
				-- Drop in just above the ground, facing the ring's center.
				local at = spots[i] + Vector3.new(0, 4, 0)
				local facing = Vector3.new(center.X, at.Y, center.Z)
				if (facing - at).Magnitude < 1 then facing = at + Vector3.new(0, 0, -1) end
				player.Character:PivotTo(CFrame.lookAt(at, facing))
			end
		else
			player:SetAttribute("InMatch", nil)
			if not ok then warn("[Match] Couldn't spawn " .. player.Name .. ": " .. tostring(err)) end
		end
	end
	if transition then
		local INTRO_LEAD = 0.6 -- Intro.Play starts its cameras this long after it's called
		Transition.HoldUntil(folder, transition, workspace:GetServerTimeNow() + INTRO_LEAD)
		Transition.WaitUntil(transition.revealAt - INTRO_LEAD)
	end
	Intro.Play(folder, fighters, spots, center, ready)
 for player,character in pairs(fighters) do
  if standing(player,character) then Ultimate.ResetCharge(player) end
 end
	local solo = next(fighters) ~= nil and next(fighters, next(fighters)) == nil
	local debugMoveOrigins = {}
 for player,character in pairs(fighters) do
  local root=character:FindFirstChild("HumanoidRootPart")
  if root then debugMoveOrigins[player]=root.Position end
 end
 local startedAt = workspace:GetServerTimeNow()
	print("[Match] Started" .. (solo and " (solo)" or ""))
	while true do
		local left = {}
		for player, character in pairs(fighters) do
			if standing(player, character) then
				table.insert(left, player)
			else
				record(player)
				fighters[player] = nil
				if player.Parent then player:SetAttribute("InMatch", nil) end
				print("[Match] " .. player.Name .. " is out")
			end
		end
		set("Match", startedAt, string.format("%d %s left", #left, #left == 1 and "player" or "players"))
		local debugMovementWin=false
  if RunService:IsStudio() and script:GetAttribute("DebugVictoryOnMove") and #left==1 then
   local player=left[1]
   local character=fighters[player]
   local root=character and character:FindFirstChild("HumanoidRootPart")
   local origin=debugMoveOrigins[player]
   if root and origin then
    local delta=root.Position-origin
    local velocity=root.AssemblyLinearVelocity
    debugMovementWin=Vector3.new(delta.X,0,delta.Z).Magnitude>0.1
     and Vector3.new(velocity.X,0,velocity.Z).Magnitude>0.5
   end
  end
  if debugMovementWin then print("[Match] Debug movement victory: "..left[1].Name) end
  if debugMovementWin or #left <= (solo and 0 or 1) then
   for _,connection in ipairs(connections) do connection:Disconnect() end
   return left[1],eliminated,templates
  end
		RunService.Heartbeat:Wait()
	end
end

while true do
	waitForPlayers()
	if intermission() then
		-- lobby -> intro: logo transition; the arena is set up while the screen is dark
		local transition = Transition.Begin(folder)
		Transition.WaitUntil(transition.blackAt)
		local winner,eliminated,templates = runMatch(transition)
  if winner then
   -- victory podium -> lobby: be fully dark the moment the podium ends (VictoryStart + VictoryDuration)
   folder:SetAttribute("VictoryStart", nil)
   task.spawn(function()
    local waited = os.clock()
    while not folder:GetAttribute("VictoryStart") and os.clock() - waited < 15 do task.wait(0.05) end
    local start = folder:GetAttribute("VictoryStart")
    if not start then return end
    Transition.WaitUntil(start + (folder:GetAttribute("VictoryDuration") or 7.5) - Transition.FadeIn)
    if folder:GetAttribute("MatchState") == "Victory" then Transition.Begin(folder) end
   end)
   Victory.Play(folder,winner,eliminated,templates)
  else
   Victory.Cleanup(templates)
  end
		for _, player in ipairs(Players:GetPlayers()) do player:SetAttribute("InMatch", nil) end
		local text = winner and (winner.DisplayName .. " wins!") or "Nobody survived. It's a draw"
		print("[Match] " .. text)
		set("Result", 0, text)
		task.wait(RESULT_TIME)
		-- Fresh character (full health, no burn/freeze) before the next round.
		if winner and winner.Parent then pcall(winner.LoadCharacter, winner) end
	end
end
