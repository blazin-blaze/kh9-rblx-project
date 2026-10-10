-- ServerScriptService.VoiceArena.ArenaBarrier (Script)
-- Circular wall around Workspace.Maps.RingModel that keeps fighters in the arena. It only exists
-- while a match runs (MatchState == "Match" on ReplicatedStorage.VoiceArena, set by MatchManager);
-- outside matches anyone can walk in and out. The walls only collide with characters: CanQuery and
-- CanTouch are off so spell raycasts and hitboxes pass through.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SEGMENTS = 64      -- wall pieces around the circle
local WALL_HEIGHT = 60   -- studs above the ring's base
local WALL_THICKNESS = 2
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
local function update()
	setActive(state:GetAttribute("MatchState") == "Match")
end
update()
barrier.Parent = workspace
state:GetAttributeChangedSignal("MatchState"):Connect(update)
