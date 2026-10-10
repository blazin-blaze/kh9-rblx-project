-- StarterPlayer.StarterPlayerScripts.MatchHud (LocalScript)
-- Round status at the top of the screen: ready count while waiting, the intermission countdown,
-- the match timer and the winner. Reads the attributes ServerScriptService.VoiceArena.MatchManager
-- sets on ReplicatedStorage.VoiceArena.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local state = ReplicatedStorage:WaitForChild("VoiceArena")

local TEXT = Color3.fromRGB(235, 242, 255)
local DIM = Color3.fromRGB(150, 160, 190)
local GOOD = Color3.fromRGB(110, 230, 150)
local WARN = Color3.fromRGB(255, 200, 90)

local function new(class, props, children)
	local inst = Instance.new(class)
	for k, v in props do if k ~= "Parent" then inst[k] = v end end
	for _, child in ipairs(children or {}) do child.Parent = inst end
	if props.Parent then inst.Parent = props.Parent end
	return inst
end
local function label(props)
	props.BackgroundTransparency = 1
	props.TextStrokeTransparency = props.TextStrokeTransparency or 0.5
	props.TextColor3 = props.TextColor3 or TEXT
	return new("TextLabel", props)
end

local gui = new("ScreenGui", { Name = "MatchHUD", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui") })
local holder = new("Frame", { Name = "MatchStatus", Size = UDim2.fromOffset(420, 80), AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 6), BackgroundTransparency = 1, Visible = false, Parent = gui }, {
	new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
})
local title = label({ LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 18), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = DIM,
	Parent = holder })
local timer = label({ LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 40), Font = Enum.Font.GothamBlack, TextSize = 36,
	TextStrokeTransparency = 0.35, Parent = holder })
local detail = label({ LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 20), Font = Enum.Font.GothamMedium, TextSize = 14, Parent = holder })

local function clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

RunService.Heartbeat:Connect(function()
	local current = state:GetAttribute("MatchState")
	local time = state:GetAttribute("MatchTime") or 0
	local now = workspace:GetServerTimeNow()
	holder.Visible = current ~= nil
	detail.Text = state:GetAttribute("MatchText") or ""
	detail.TextColor3 = TEXT
	if current == "Waiting" then
		title.Text = ""
		timer.Visible = false
	elseif current == "Intermission" then
		title.Text = "MATCH STARTS IN"
		timer.Visible = true
		timer.TextColor3 = WARN
		timer.Text = tostring(math.max(0, math.ceil(time - now)))
	elseif current == "Preparing" or current == "Intro" or current == "Victory" then
		holder.Visible = false
	elseif current == "Match" then
		local fighting = player:GetAttribute("InMatch") == true
		title.Text = fighting and "LAST ONE STANDING WINS" or "MATCH IN PROGRESS  /  SPECTATING"
		timer.Visible = true
		timer.TextColor3 = TEXT
		timer.Text = clock(now - time)
	elseif current == "Result" then
		title.Text = "MATCH OVER"
		timer.Visible = false
		detail.TextColor3 = GOOD
	end
end)
