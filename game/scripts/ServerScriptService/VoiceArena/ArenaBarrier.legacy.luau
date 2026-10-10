-- ServerScriptService.VoiceArena.ArenaBarrier (Script)
-- Circular wall around Workspace.Maps.RingModel that keeps fighters in the arena. It only exists
-- while a match runs (MatchState == "Match" on ReplicatedStorage.VoiceArena, set by MatchManager);
-- outside matches anyone can walk in and out. The walls only collide with characters: CanQuery and
-- CanTouch are off so spell raycasts and hitboxes pass through. Walls can still be beaten by jumping
-- over, dashes, knockback or exploits, so the server also pulls any fighter (InMatch) who ends up
-- outside back in.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SEGMENTS = 64      -- wall pieces around the circle
local WALL_HEIGHT = 60   -- studs above the ring's base
local WALL_THICKNESS = 2
local PULL_BACK = 6      -- fighters past the edge are placed this many studs inside it
local VISIBLE = 0.75     -- wall transparency during a match

local state = ReplicatedStorage:WaitForChild("VoiceArena")
local ring = workspace:WaitForChild("Maps"):WaitForChild("RingModel")
local ringCFrame, ringSize = ring:GetBoundingBox()
local center = ringCFrame.Position
local radius = math.min(ringSize.X, ringSize.Z) / 2
local baseY = center.Y - ringSize.Y / 2

local barrier = Instance.new("Folder")
barrier.Name = "ArenaBarrier"
local width = 2 * (radius + WALL_THICKNESS / 2) * math.tan(math.pi / SEGMENTS) + 0.5 -- slight overlap, no gaps
for i = 1, SEGMENTS do
	local angle = (i - 0.5) / SEGMENTS * 2 * math.pi
	local at = center + Vector3.new(math.cos(angle) * (radius + WALL_THICKNESS / 2), 0, math.sin(angle) * (radius + WALL_THICKNESS / 2))
	at = Vector3.new(at.X, baseY + WALL_HEIGHT / 2, at.Z)
	local wall = Instance.new("Part")
	wall.Name = "Wall"
	wall.Anchored = true
	wall.CanQuery = false
	wall.CanTouch = false
	wall.CastShadow = false
	wall.Material = Enum.Material.ForceField
	wall.Color = Color3.fromRGB(120, 170, 255)
	wall.Size = Vector3.new(width, WALL_HEIGHT, WALL_THICKNESS)
	wall.CFrame = CFrame.lookAt(at, Vector3.new(center.X, at.Y, center.Z))
	wall.Parent = barrier
end

local function setActive(active)
	for _, wall in ipairs(barrier:GetChildren()) do
		wall.CanCollide = active
		wall.Transparency = active and VISIBLE or 1
	end
end
setActive(false)
barrier.Parent = workspace

local active = false
RunService.Heartbeat:Connect(function()
	local now = state:GetAttribute("MatchState") == "Match"
	if now ~= active then
		active = now
		setActive(now)
	end
	if not active then return end
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if player:GetAttribute("InMatch") and root then
			local offset = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
			if offset.Magnitude > radius - 1 then
				local inside = center + offset.Unit * (radius - PULL_BACK)
				local y = math.max(root.Position.Y, baseY + 4)
				character:PivotTo(CFrame.new(inside.X, y, inside.Z) * character:GetPivot().Rotation)
				root.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end
end)
