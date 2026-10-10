-- StarterPlayer.StarterPlayerScripts.LogoTransitionClient (LocalScript)
-- Draws the "Incantation" logo transition that ServerScriptService.VoiceArena.LogoTransition starts
-- (lobby -> match intro, victory podium -> lobby): fade to dark, the logo writes itself on, fade out.
-- Roblox can't play GIFs, so the animation is 30 frames packed into 3 sprite sheets (512x187 frames,
-- 2 across x 5 down), stepped through with ImageRectOffset, then a sharp final logo is crossfaded in.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local player = Players.LocalPlayer
local folder = game:GetService("ReplicatedStorage"):WaitForChild("VoiceArena")

local SHEETS = { "rbxassetid://100198640938540", "rbxassetid://127697636498263", "rbxassetid://72721481161201" }
local FINAL = "rbxassetid://73093625414311"
local FRAMES, FW, FH, COLS, PER_SHEET = 30, 512, 187, 2, 10
local LOGO_CENTER_X = 0.548 -- the finished logo's visual centre across the frame (left side holds the sweep-in stroke)
local BACKDROP = Color3.fromRGB(11, 17, 18)
local WHOOSH_IN = "rbxassetid://9126228631"  -- Pro Sound Effects: whoosh, zoom in and out
local WHOOSH_OUT = "rbxassetid://9126229267" -- Pro Sound Effects: quick whoosh by
local HAS_ART = not string.find(table.concat(SHEETS) .. FINAL, "IMG_", 1, true)

local gui = Instance.new("ScreenGui")
gui.Name = "LogoTransition"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1500 -- above the match intro (1000) and victory (1100) cinematics
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local backdrop = Instance.new("Frame")
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = BACKDROP
backdrop.BorderSizePixel = 0
backdrop.Parent = gui

local logo = Instance.new("Frame")
logo.Name = "Logo"
logo.BackgroundTransparency = 1
logo.AnchorPoint = Vector2.new(LOGO_CENTER_X, 0.5)
logo.Position = UDim2.fromScale(0.5, 0.48)
logo.Size = UDim2.fromScale(0.62, 0.62)
logo.ZIndex = 2
logo.Parent = gui
local aspect = Instance.new("UIAspectRatioConstraint")
aspect.AspectRatio = FW / FH
aspect.Parent = logo
local maxSize = Instance.new("UISizeConstraint")
maxSize.MaxSize = Vector2.new(1100, 1100 * FH / FW)
maxSize.Parent = logo

local sprite = Instance.new("ImageLabel")
sprite.BackgroundTransparency = 1
sprite.Size = UDim2.fromScale(1, 1)
sprite.ImageRectSize = Vector2.new(FW, FH)
sprite.ZIndex = 2
sprite.Parent = logo
local final = Instance.new("ImageLabel")
final.BackgroundTransparency = 1
final.Size = UDim2.fromScale(1, 1)
final.Image = FINAL
final.ZIndex = 3
final.Parent = logo
local stand = Instance.new("TextLabel") -- shown only until the logo images are uploaded
stand.BackgroundTransparency = 1
stand.Size = UDim2.fromScale(0.84, 0.6)
stand.AnchorPoint = Vector2.new(0.5, 0.5)
stand.Position = UDim2.fromScale(LOGO_CENTER_X, 0.4)
stand.FontFace = Font.fromEnum(Enum.Font.Garamond)
stand.Text = "Incantation"
stand.TextScaled = true
stand.TextColor3 = Color3.new(1, 1, 1)
stand.Visible = not HAS_ART
stand.ZIndex = 3
stand.Parent = logo
sprite.Visible = HAS_ART
final.Visible = HAS_ART

local function sound(id, volume)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.Parent = SoundService
	return s
end
local whooshIn, whooshOut = sound(WHOOSH_IN, 0.8), sound(WHOOSH_OUT, 0.55)

-- Load every frame up front so the first transition never stalls mid-animation.
task.spawn(function()
	local list = { whooshIn, whooshOut }
	if HAS_ART then
		for _, id in ipairs(SHEETS) do
			local probe = Instance.new("ImageLabel")
			probe.Image = id
			table.insert(list, probe)
		end
		table.insert(list, final)
	end
	pcall(function() ContentProvider:PreloadAsync(list) end)
end)

local function showFrame(i)
	i = math.clamp(i, 1, FRAMES)
	local sheet = math.floor((i - 1) / PER_SHEET) + 1
	local k = (i - 1) % PER_SHEET
	sprite.Image = SHEETS[sheet]
	sprite.ImageRectOffset = Vector2.new((k % COLS) * FW, math.floor(k / COLS) * FH)
end

local current, revealPlayed
local function step()
	if not current then return end
	local t = workspace:GetServerTimeNow()
	local fadeIn = folder:GetAttribute("LogoFadeIn") or 0.35
	local draw = folder:GetAttribute("LogoDraw") or 2
	local fadeOut = folder:GetAttribute("LogoFadeOut") or 0.45
	local reveal = folder:GetAttribute("LogoTransitionReveal") or (current + fadeIn + draw + 0.3)
	local elapsed = t - current
	if t >= reveal + fadeOut then
		current = nil
		gui.Enabled = false
		RunService:UnbindFromRenderStep("LogoTransition")
		return
	end
	gui.Enabled = true -- stay on even if a cinematic script hides other screens
	-- dark backdrop: fade in, hold, fade out from the reveal time
	local opacity = t < reveal and math.clamp(elapsed / fadeIn, 0, 1) or 1 - math.clamp((t - reveal) / fadeOut, 0, 1)
	backdrop.BackgroundTransparency = 1 - opacity
	-- logo: write-on frames, then crossfade to the sharp final logo
	local drawn = math.clamp((elapsed - fadeIn * 0.6) / draw, 0, 1)
	showFrame(math.floor(drawn * FRAMES) + 1)
	local settle = math.clamp((elapsed - fadeIn * 0.6 - draw) / 0.2, 0, 1)
	local logoAlpha = math.min(opacity, math.clamp(elapsed / (fadeIn * 0.6), 0, 1))
	sprite.ImageTransparency = 1 - logoAlpha * (1 - settle)
	final.ImageTransparency = 1 - logoAlpha * settle
	stand.TextTransparency = 1 - logoAlpha * drawn
	if t >= reveal and not revealPlayed then
		revealPlayed = true
		whooshOut:Play()
	end
end

local function begin()
	local start = folder:GetAttribute("LogoTransitionStart")
	if type(start) ~= "number" then return end
	local now = workspace:GetServerTimeNow()
	local reveal = folder:GetAttribute("LogoTransitionReveal") or start + 2.65
	if now > reveal + (folder:GetAttribute("LogoFadeOut") or 0.45) then return end -- already over (late join)
	current, revealPlayed = start, false
	gui.Enabled = true
	if now - start < 0.5 then whooshIn:Play() end
	RunService:UnbindFromRenderStep("LogoTransition")
	RunService:BindToRenderStep("LogoTransition", Enum.RenderPriority.Last.Value, step)
	step()
end
folder:GetAttributeChangedSignal("LogoTransitionId"):Connect(begin)
if folder:GetAttribute("LogoTransitionId") then begin() end
