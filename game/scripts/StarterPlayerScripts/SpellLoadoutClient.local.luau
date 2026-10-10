-- StarterPlayer.StarterPlayerScripts.SpellLoadoutClient (LocalScript)
-- "Set Your Spells" screen, drawn from the hand-illustrated design (chains, swirls, green flames).
-- For each of 3 slots the player names the spell (the word they'll say to cast it) and either
-- picks a preset or describes a new spell for Gemini to write. Next to Begin, the player can also
-- change the word that fires their ultimate. Press L to reopen.
-- Art: the background + button frames are uploaded images (IMAGES below); everything that
-- changes (names, dropdown text, prompts, status) is live text laid over the art.
-- Server side: ServerScriptService.VoiceArena.Loadout.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local function setChat(enabled) pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, enabled) end) end

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("VoiceArena")
local ForgeSpell = remotes:WaitForChild("ForgeSpell")
local TestSpell = remotes:WaitForChild("TestSpell")
local SetLoadout = remotes:WaitForChild("SetLoadout")

local IMAGES = {
	background = "rbxassetid://130625760200200",
	aiButton = "rbxassetid://129608199478784",
	dropdown = "rbxassetid://102999564625926",
	frame = "rbxassetid://139766576561517",
	glow = "rbxassetid://106049974797783",
}

-- Until the art is uploaded (ids still "IMG_..."), everything falls back to drawn frames so the screen still works.
local function hasArt(key) return not string.find(IMAGES[key], "IMG_", 1, true) end

local SERIF_BOLD = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)
local SERIF = Font.fromEnum(Enum.Font.Bodoni)
local C = {
	ink = Color3.fromRGB(246, 246, 240), soft = Color3.fromRGB(185, 228, 212), teal = Color3.fromRGB(80, 240, 190),
	panel = Color3.fromRGB(6, 18, 16), field = Color3.fromRGB(3, 10, 9), good = Color3.fromRGB(120, 255, 190),
	warn = Color3.fromRGB(255, 205, 110), bad = Color3.fromRGB(255, 130, 120), dimArt = Color3.fromRGB(125, 145, 140),
}
local PRESETS = {
	{ id = "Flame", label = "Flame Spell", info = "Aimed fireball. 20 damage, then burns for 5 seconds." },
	{ id = "Freeze", label = "Freeze Spell", info = "Ice bolt that freezes the target in place for 5 seconds." },
	{ id = "Wave", label = "Wave Spell", info = "A wall of water that sweeps forward, pushing enemies and blocking shots." },
	{ id = "Lightning", label = "Lightning", info = "A yellow lightning cone follows you for 3 seconds. Deals 2 damage every 0.1 seconds. 6 second cooldown." },
}
local DEFAULTS = { { name = "Flame", preset = 1 }, { name = "Freeze", preset = 2 }, { name = "Wave", preset = 3 } }
local HINT = "The word you'll say to cast it"
local DEFAULT_ULTIMATE = "Ultimate"

-- The art is laid out in "design pixels" (the source illustration is 2400 x 2048).
local DW, DH = 2400, 2048
local PANEL_W, PANEL_H = 1000, 1000 * DH / DW
local function at(x, y) return UDim2.fromScale(x / DW, y / DH) end
local function sz(w, h) return UDim2.fromScale(w / DW, h / DH) end
local CARD_X = { 231, 910, 1590 }      -- left edge of each card's white frame
local BTN_X = { 280, 957, 1637 }       -- left edge of the two buttons in each card
local BTN_W, AI_Y, AI_H, DD_Y, DD_H = 486, 909, 226, 1243, 222

local function new(class, props, children)
	local inst = Instance.new(class)
	for k, v in props do if k ~= "Parent" then inst[k] = v end end
	for _, child in ipairs(children or {}) do child.Parent = inst end
	if props.Parent then inst.Parent = props.Parent end
	return inst
end
local function tween(inst, t, props, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end
local function text(props, children)
	props.BackgroundTransparency = 1
	props.FontFace = props.FontFace or SERIF
	props.TextColor3 = props.TextColor3 or C.ink
	props.TextWrapped = true
	return new("TextLabel", props, children)
end

-- An ornate button: glow behind + framed art + live label. `selected` keeps it lit.
local function ornateButton(parent, props)
	-- Anchored at its centre so the hover/press UIScale grows and shrinks evenly from the middle.
	local sizeU, posU = props.Size, props.Position
	local holder = new("Frame", { Size = sizeU, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = posU + UDim2.new(sizeU.X.Scale / 2, sizeU.X.Offset / 2, sizeU.Y.Scale / 2, sizeU.Y.Offset / 2), BackgroundTransparency = 1, ZIndex = props.ZIndex or 2,
		Visible = props.Visible ~= false, Parent = parent })
	local glow = new("ImageLabel", { Image = IMAGES.glow, Size = UDim2.fromScale(1.25, 1.7), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1, ImageTransparency = 1, ZIndex = holder.ZIndex, Parent = holder })
	local button = new("ImageButton", { Image = props.Image or IMAGES.frame, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		AutoButtonColor = false, ZIndex = holder.ZIndex + 1, Parent = holder })
	if props.Slice then
		button.ScaleType = Enum.ScaleType.Slice
		button.SliceCenter = Rect.new(64, 34, 422, 188)
		button.SliceScale = props.Slice
	end
	local scale = new("UIScale", { Parent = holder })
	local stroke
	if string.find(button.Image, "IMG_", 1, true) then
		button.Image = ""
		button.BackgroundTransparency = 0.1
		button.BackgroundColor3 = C.field
		new("UICorner", { CornerRadius = UDim.new(0, 10), Parent = button })
		stroke = new("UIStroke", { Color = C.ink, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = button })
		props.Text = props.Text or props.FallbackText
		if props.Chevron then
			text({ Text = "▼", FontFace = SERIF_BOLD, TextScaled = true, Size = UDim2.fromScale(0.1, 0.3), AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.86, 0.5), ZIndex = holder.ZIndex + 2, Parent = holder })
		end
	end
	local label
	if props.Text then
		label = text({ Text = props.Text, FontFace = props.FontFace or SERIF_BOLD, TextScaled = true, Size = props.TextSize or UDim2.fromScale(0.68, 0.46),
			AnchorPoint = Vector2.new(0.5, 0.5), Position = props.TextPosition or UDim2.fromScale(0.5, 0.5),
			TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Center, ZIndex = holder.ZIndex + 2, Parent = holder },
			nil)
		new("UITextSizeConstraint", { MaxTextSize = props.MaxText or 26, MinTextSize = 8, Parent = label })
	end
	local obj = { holder = holder, button = button, glow = glow, label = label, scale = scale, selected = props.Selected ~= false,
		dimmable = props.Dimmable == true, hovered = false }
	local function refresh()
		local lit = obj.selected or obj.hovered
		tween(button, 0.15, { ImageColor3 = (obj.dimmable and not obj.selected and not obj.hovered) and C.dimArt or Color3.new(1, 1, 1) })
		tween(glow, 0.2, { ImageTransparency = (obj.dimmable and obj.selected) and 0.25 or (obj.hovered and 0.5 or 1) })
		if label then tween(label, 0.15, { TextTransparency = (obj.dimmable and not lit) and 0.35 or 0 }) end
		if stroke then tween(stroke, 0.15, { Color = ((obj.dimmable and obj.selected) or obj.hovered) and C.teal or C.ink,
			Thickness = (obj.dimmable and obj.selected) and 3 or 2 }) end
	end
	obj.refresh = refresh
	button.MouseEnter:Connect(function() obj.hovered = true; tween(scale, 0.15, { Scale = 1.04 }, Enum.EasingStyle.Back); refresh() end)
	button.MouseLeave:Connect(function() obj.hovered = false; tween(scale, 0.15, { Scale = 1 }); refresh() end)
	button.MouseButton1Down:Connect(function() tween(scale, 0.08, { Scale = 0.96 }) end)
	button.MouseButton1Up:Connect(function() tween(scale, 0.15, { Scale = obj.hovered and 1.04 or 1 }, Enum.EasingStyle.Back) end)
	function obj.setSelected(value) obj.selected = value; refresh() end
	refresh()
	return obj
end

-- Dark inset field with a thin chalk-white border, matching the art's line work.
local function inset(props, children)
	props.BackgroundColor3 = props.BackgroundColor3 or C.field
	props.BackgroundTransparency = props.BackgroundTransparency or 0.08
	local class = props.Class or "Frame"
	props.Class = nil
	local f = new(class, props, children)
	new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = f })
	new("UIStroke", { Color = C.ink, Thickness = 2, Transparency = 0.15, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = f })
	return f
end

---------------------------------------------------------------- layout
local gui = new("ScreenGui", { Name = "SpellLoadout", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = true, DisplayOrder = 10, Parent = player:WaitForChild("PlayerGui") })
local backdrop = new("TextButton", { Name = "Backdrop", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.35, Text = "", AutoButtonColor = false, Modal = true, Parent = gui })
local panel = new("ImageLabel", { Name = "Panel", Image = IMAGES.background, Size = UDim2.fromOffset(PANEL_W, PANEL_H),
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(8, 26, 22),
	BackgroundTransparency = 0, Parent = gui })
local uiScale = new("UIScale", { Parent = panel })
if hasArt("background") then
	panel.BackgroundTransparency = 1
else
	panel.Image = ""
	new("UICorner", { CornerRadius = UDim.new(0, 18), Parent = panel })
	new("UIStroke", { Color = C.ink, Thickness = 3, Parent = panel })
	text({ Text = "Set Your Spells", FontFace = SERIF_BOLD, TextScaled = true, Size = sz(1400, 190), AnchorPoint = Vector2.new(0.5, 0),
		Position = at(1200, 230), ZIndex = 2, Parent = panel })
	for i = 1, 3 do
		new("Frame", { Size = sz(580, 1290), Position = at(CARD_X[i], 470), BackgroundTransparency = 1, ZIndex = 1, Parent = panel },
			{ new("UIStroke", { Color = C.ink, Thickness = 2, Transparency = 0.3 }), new("UICorner", { CornerRadius = UDim.new(0, 12) }) })
		text({ Text = "Activation Word", FontFace = SERIF_BOLD, TextScaled = true, Size = sz(500, 80), Position = at(CARD_X[i] + 40, 545),
			ZIndex = 2, Parent = panel })
		text({ Text = "- OR -", FontFace = SERIF_BOLD, TextScaled = true, Size = sz(300, 70), Position = at(CARD_X[i] + 140, 1155),
			ZIndex = 2, Parent = panel })
	end
end

local footerStatus = text({ Text = "", TextSize = 17, TextColor3 = C.soft, TextXAlignment = Enum.TextXAlignment.Left,
	Size = sz(640, 90), Position = at(250, 1820), ZIndex = 3, Parent = panel })
local beginButton = ornateButton(panel, { Text = "Begin", Position = at(980, 1806), Size = sz(440, 122), Slice = 0.45, MaxText = 30,
	TextSize = UDim2.fromScale(0.6, 0.5) })
-- Ultimate word, right of Begin in the strip under the cards: the cards' "Activation Word" caption and
-- name-box style on one line. Problems with it are reported in footerStatus, left of Begin.
text({ Text = "Ultimate Word", FontFace = SERIF_BOLD, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Right,
	Size = sz(300, 64), Position = at(1470, 1836), ZIndex = 3, Parent = panel },
	{ new("UITextSizeConstraint", { MaxTextSize = 22, MinTextSize = 8 }) })
local ultimateBox = new("TextBox", { Name = "UltimateWord", Text = DEFAULT_ULTIMATE, PlaceholderText = "Name it", FontFace = SERIF_BOLD,
	TextScaled = true, TextColor3 = C.ink, PlaceholderColor3 = Color3.fromRGB(110, 140, 132), BackgroundTransparency = 1,
	ClearTextOnFocus = false, Size = sz(370, 96), Position = at(1790, 1818), ZIndex = 3, Parent = panel },
	{ new("UITextSizeConstraint", { MaxTextSize = 40, MinTextSize = 12 }) })
local ultimateLine = new("Frame", { Size = sz(330, 4), AnchorPoint = Vector2.new(0.5, 0), Position = at(1975, 1910), BackgroundColor3 = C.teal,
	BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3, Parent = panel })
local ULTIMATE_PREFIX = "Ultimate word: "
local function setUltimateProblem(message)
	if message then
		footerStatus.Text = ULTIMATE_PREFIX .. message
		footerStatus.TextColor3 = C.bad
	elseif string.sub(footerStatus.Text, 1, #ULTIMATE_PREFIX) == ULTIMATE_PREFIX then
		footerStatus.Text = ""
	end
end

local toast = text({ Text = "", TextSize = 22, FontFace = SERIF_BOLD, Size = UDim2.new(1, 0, 0, 30),
	Position = UDim2.new(0, 0, 0, 136), Visible = false, TextStrokeTransparency = 0.4, Parent = gui }) -- just under MatchHud's intermission text

local function fit()
	local camera = workspace.CurrentCamera
	if camera then
		local v = camera.ViewportSize
		uiScale.Scale = math.clamp(math.min((v.X - 24) / PANEL_W, (v.Y - 24) / PANEL_H), 0.4, 1.3)
	end
end
fit()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(fit)
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit) end

---------------------------------------------------------------- code viewer
local viewer = inset({ Name = "CodeViewer", Size = UDim2.fromScale(0.8, 0.66), AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.55), BackgroundColor3 = Color3.fromRGB(4, 14, 12), BackgroundTransparency = 0.02,
	Visible = false, ZIndex = 50, Parent = panel })
local viewerTitle = text({ Text = "", FontFace = SERIF_BOLD, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, -170, 0, 32), Position = UDim2.fromOffset(22, 14), ZIndex = 51, Parent = viewer })
local viewerInfo = text({ Text = "", TextSize = 16, TextColor3 = C.soft, TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, -44, 0, 36), Position = UDim2.fromOffset(22, 48), ZIndex = 51, Parent = viewer })
local viewerClose = ornateButton(viewer, { Text = "Close", Size = UDim2.fromOffset(130, 46), Position = UDim2.new(1, -150, 0, 8),
	Slice = 0.22, ZIndex = 52, MaxText = 18 })
local scroller = inset({ Class = "ScrollingFrame", Size = UDim2.new(1, -44, 1, -104), Position = UDim2.fromOffset(22, 88),
	BackgroundColor3 = Color3.fromRGB(2, 8, 7), ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(), ZIndex = 51, Parent = viewer })
local codeText = text({ Text = "", FontFace = Font.fromEnum(Enum.Font.Code), TextSize = 14, TextColor3 = Color3.fromRGB(190, 255, 220),
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, -20, 0, 0),
	Position = UDim2.fromOffset(10, 8), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 52, Parent = scroller })
viewerClose.button.Activated:Connect(function() viewer.Visible = false end)

---------------------------------------------------------------- cards
local cards = {}

local function setMode(card, mode)
	card.mode = mode
	local aiOn = mode == "custom"
	card.ai.setSelected(aiOn)
	card.dd.setSelected(not aiOn)
	card.aiArea.Visible = aiOn
	card.presetInfo.Visible = not aiOn
	card.list.Visible = false
end

local function setPreset(card, index)
	card.preset = index
	card.dd.label.Text = PRESETS[index].label
	card.presetInfo.Text = PRESETS[index].info
	setMode(card, "preset")
end

local function setHint(card, message, color)
	card.hint.Text = message
	card.hint.TextColor3 = color or C.soft
end

local function validateName(value)
	local clean = string.gsub(string.gsub(value or "", "^%s+", ""), "%s+$", "")
	if clean == "" then return nil, "Give this spell a name" end
	if not string.match(clean, "^%a+$") then return nil, "One word, letters only" end
	if #clean < 3 or #clean > 20 then return nil, "Use 3 to 20 letters" end
	return clean
end

ultimateBox.Focused:Connect(function() tween(ultimateLine, 0.2, { BackgroundTransparency = 0.2 }) end)
ultimateBox.FocusLost:Connect(function()
	tween(ultimateLine, 0.2, { BackgroundTransparency = 1 })
	local clean, err = validateName(ultimateBox.Text)
	if clean then ultimateBox.Text = clean end
	setUltimateProblem(err)
end)

local function definition(card)
	local name = validateName(card.nameBox.Text) or ""
	if card.mode == "custom" then
		if not card.spellId then return nil, "Generate your AI spell first" end
		return { name = name, kind = "custom", spellId = card.spellId }
	end
	return { name = name, kind = "preset", preset = PRESETS[card.preset].id }
end

local closePanel, openPanel

local function makeCard(i)
	local cx, bx = CARD_X[i], BTN_X[i]
	local card = { index = i }

	-- activation word (the spoken name), written where the design shows "Flame / Freeze / Wave"
	card.nameBox = new("TextBox", { Text = DEFAULTS[i].name, PlaceholderText = "Name it", FontFace = SERIF_BOLD, TextScaled = true,
		TextColor3 = C.ink, PlaceholderColor3 = Color3.fromRGB(110, 140, 132), BackgroundTransparency = 1, ClearTextOnFocus = false,
		Size = sz(500, 150), Position = at(cx + 40, 668), ZIndex = 3, Parent = panel },
		{ new("UITextSizeConstraint", { MaxTextSize = 64, MinTextSize = 14 }) })
	local underline = new("Frame", { Size = sz(360, 4), AnchorPoint = Vector2.new(0.5, 0), Position = at(cx + 290, 826), BackgroundColor3 = C.teal,
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3, Parent = panel })
	card.nameBox.Focused:Connect(function() tween(underline, 0.2, { BackgroundTransparency = 0.2 }) end)
	card.hint = text({ Text = HINT, TextSize = 15, TextColor3 = C.soft, Size = sz(540, 60), Position = at(cx + 20, 838), ZIndex = 3, Parent = panel })

	-- "Create your own spell with AI"  - OR -  "[preset] v"
	card.ai = ornateButton(panel, { Image = IMAGES.aiButton, Position = at(bx, AI_Y), Size = sz(BTN_W, AI_H), Dimmable = true, Selected = false,
		FallbackText = "Create your own spell with AI" })
	card.dd = ornateButton(panel, { Image = IMAGES.dropdown, Position = at(bx, DD_Y), Size = sz(BTN_W, DD_H), Dimmable = true,
		Text = "Flame Spell", TextXAlignment = Enum.TextXAlignment.Left, TextSize = UDim2.fromScale(0.58, 0.34),
		TextPosition = UDim2.fromScale(0.42, 0.5), MaxText = 21, Chevron = true })

	-- preset list drops open below the dropdown
	card.list = inset({ Size = sz(BTN_W - 40, #PRESETS * 92 + 20), Position = at(bx + 20, DD_Y + DD_H - 6), Visible = false, ZIndex = 20,
		BackgroundColor3 = Color3.fromRGB(4, 16, 14), BackgroundTransparency = 0.02, Parent = panel })
	for p, preset in ipairs(PRESETS) do
		local option = new("TextButton", { Text = preset.label, FontFace = SERIF_BOLD, TextSize = 19, TextColor3 = C.ink,
			BackgroundColor3 = Color3.fromRGB(20, 60, 50), BackgroundTransparency = 1, AutoButtonColor = false,
			Size = UDim2.new(1, -12, 0, 34), Position = UDim2.new(0, 6, 0, 5 + (p - 1) * 38), ZIndex = 21, Parent = card.list },
			{ new("UICorner", { CornerRadius = UDim.new(0, 6) }) })
		option.MouseEnter:Connect(function() tween(option, 0.12, { BackgroundTransparency = 0.2, TextColor3 = C.teal }) end)
		option.MouseLeave:Connect(function() tween(option, 0.12, { BackgroundTransparency = 1, TextColor3 = C.ink }) end)
		option.Activated:Connect(function() setPreset(card, p) end)
	end

	-- lower area: preset description above the flames, or the AI prompt panel over them
	card.presetInfo = text({ Text = "", TextSize = 15, TextColor3 = C.soft, TextStrokeTransparency = 0.5, Size = sz(500, 130),
		Position = at(cx + 40, 1470), ZIndex = 3, Parent = panel })
	card.aiArea = inset({ Size = sz(560, 262), Position = at(cx + 10, 1444), BackgroundColor3 = Color3.fromRGB(3, 12, 11),
		BackgroundTransparency = 0.12, Visible = false, ZIndex = 4, Parent = panel })
	card.prompt = inset({ Class = "TextBox", Text = "", PlaceholderText = "Describe it, e.g. \"a green fireball that splits in three\"",
		FontFace = SERIF, TextSize = 13, TextColor3 = C.ink, PlaceholderColor3 = Color3.fromRGB(110, 140, 132), TextWrapped = true,
		MultiLine = true, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		BackgroundColor3 = C.field, Size = UDim2.new(0.92, 0, 0.44, 0), Position = UDim2.fromScale(0.04, 0.04), ZIndex = 5, Parent = card.aiArea },
		{ new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 4) }) })
	card.generate = ornateButton(card.aiArea, { Text = "Generate", Position = UDim2.fromScale(0.03, 0.51), Size = UDim2.fromScale(0.6, 0.26),
		Slice = 0.22, ZIndex = 5, MaxText = 17 })
	card.codeButton = ornateButton(card.aiArea, { Text = "Code", Position = UDim2.fromScale(0.66, 0.51), Size = UDim2.fromScale(0.31, 0.26),
		Slice = 0.22, ZIndex = 5, MaxText = 15, Visible = false })
	card.aiStatus = text({ Text = "Gemini writes the Luau for your spell.", TextScaled = true, TextColor3 = C.soft,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.fromScale(0.92, 0.2), Position = UDim2.fromScale(0.04, 0.79), ZIndex = 5, Parent = card.aiArea },
		{ new("UITextSizeConstraint", { MaxTextSize = 13, MinTextSize = 7 }) })

	card.test = ornateButton(panel, { Text = "Try It", Position = at(cx + 175, 1708), Size = sz(230, 78), Slice = 0.2, MaxText = 17, ZIndex = 4 })

	-- wiring
	card.ai.button.Activated:Connect(function() setMode(card, "custom") end)
	card.dd.button.Activated:Connect(function()
		if card.mode ~= "preset" then setMode(card, "preset") end
		card.list.Visible = not card.list.Visible
	end)
	card.nameBox.FocusLost:Connect(function()
		tween(underline, 0.2, { BackgroundTransparency = 1 })
		local clean, err = validateName(card.nameBox.Text)
		if clean then card.nameBox.Text = clean; setHint(card, HINT) else setHint(card, err, C.bad) end
	end)
	card.codeButton.button.Activated:Connect(function()
		if not card.code then return end
		viewerTitle.Text = "Gemini Luau  -  " .. (card.title or "AI Spell")
		viewerInfo.Text = card.description or ""
		codeText.Text = card.code
		viewer.Visible = true
	end)
	card.generate.button.Activated:Connect(function()
		if card.forging then return end
		local prompt = card.prompt.Text
		if #string.gsub(prompt, "%s", "") < 3 then
			card.aiStatus.Text = "Describe your spell first."
			card.aiStatus.TextColor3 = C.bad
			return
		end
		card.forging = true
		card.generate.label.Text = "Writing..."
		card.aiStatus.TextColor3 = C.soft
		local started = os.clock()
		task.spawn(function()
			while card.forging do
				local dots = string.rep(".", math.floor((os.clock() - started) * 3) % 4)
				card.aiStatus.Text = string.format("Gemini is writing your spell%s (%ds)", dots, math.floor(os.clock() - started))
				card.generate.glow.ImageTransparency = 0.35 + math.sin(os.clock() * 6) * 0.25
				task.wait(0.05)
			end
			card.generate.refresh()
		end)
		local ok, result = pcall(function()
			return ForgeSpell:InvokeServer(i, validateName(card.nameBox.Text) or "", prompt)
		end)
		card.forging = false
		card.generate.label.Text = "Generate"
		if not ok or type(result) ~= "table" then
			card.aiStatus.Text = "Couldn't reach the server. Try again."
			card.aiStatus.TextColor3 = C.bad
			return
		end
		if not result.ok then
			card.aiStatus.Text = tostring(result.error or "Something went wrong.")
			card.aiStatus.TextColor3 = C.bad
			return
		end
		card.spellId, card.code, card.title, card.description = result.spellId, result.code, result.title, result.description
		card.codeButton.holder.Visible = true
		setMode(card, "custom")
		if result.fallback then
			card.aiStatus.Text = "Backup spell: Gemini's version didn't work, so an improvised " .. tostring(result.element) .. " spell was made."
			card.aiStatus.TextColor3 = C.warn
		else
			card.aiStatus.Text = string.format("Ready: %s. %s", tostring(result.title), tostring(result.description))
			card.aiStatus.TextColor3 = C.good
		end
	end)
	card.test.button.Activated:Connect(function()
		local def, err = definition(card)
		if not def then setHint(card, err, C.bad); return end
		def.name = validateName(card.nameBox.Text) or ("Spell " .. i)
		closePanel(true)
		toast.Text = "Testing " .. def.name .. "..."
		toast.TextColor3 = C.teal
		toast.Visible = true
		task.wait(0.35)
		local ok, result = pcall(function() return TestSpell:InvokeServer(def) end)
		if ok and type(result) == "table" and not result.ok then
			toast.Text = tostring(result.error or result.value)
			toast.TextColor3 = C.bad
		end
		task.wait(3)
		toast.Visible = false
		openPanel()
	end)

	setPreset(card, DEFAULTS[i].preset)
	cards[i] = card
	return card
end
for i = 1, 3 do makeCard(i) end

---------------------------------------------------------------- open / close / begin
local open = false
function openPanel()
	open = true
	setChat(false)
	gui.Enabled = true
	panel.Visible = true
	backdrop.Visible = true
	panel.Position = UDim2.fromScale(0.5, 0.53)
	panel.ImageTransparency = 0.4
	tween(panel, 0.3, { Position = UDim2.fromScale(0.5, 0.5), ImageTransparency = 0 })
end
function closePanel(keepToast)
	open = false
	setChat(true)
	panel.Visible = false
	backdrop.Visible = false
	viewer.Visible = false
	if not keepToast then toast.Visible = false end
end

beginButton.button.Activated:Connect(function()
	local slots, problems = {}, false
	for i, card in ipairs(cards) do
		local clean, nameErr = validateName(card.nameBox.Text)
		local def, defErr = definition(card)
		if not clean then setHint(card, nameErr, C.bad); problems = true
		elseif not def then setHint(card, defErr, C.bad); problems = true
		else setHint(card, HINT) end
		slots[i] = def or { name = card.nameBox.Text, kind = "preset", preset = "Flame" }
		slots[i].name = card.nameBox.Text
	end
	if problems then footerStatus.Text = "Fix the highlighted spells first."; footerStatus.TextColor3 = C.bad; return end
	local ultimate, ultimateErr = validateName(ultimateBox.Text)
	if not ultimate then setUltimateProblem(ultimateErr); return end
	footerStatus.Text = "Equipping..."
	footerStatus.TextColor3 = C.soft
	local ok, result = pcall(function() return SetLoadout:InvokeServer(slots, ultimate) end)
	if not ok or type(result) ~= "table" then
		footerStatus.Text = "Couldn't reach the server. Try again."
		footerStatus.TextColor3 = C.bad
		return
	end
	if not result.ok then
		for key, message in pairs(result.errors or {}) do
			local card = cards[tonumber(key)]
			if card then setHint(card, message, C.bad) end
		end
		footerStatus.Text = "Fix the highlighted spells first."
		footerStatus.TextColor3 = C.bad
		local errors = result.errors or {}
		if errors.ultimate and not (errors["1"] or errors["2"] or errors["3"]) then setUltimateProblem(errors.ultimate) end
		return
	end
	footerStatus.Text = ""
	closePanel()
	toast.Text = "Equipped: " .. table.concat(result.names, "  /  ") .. ".  Ultimate: " .. tostring(result.ultimate or ultimate)
		.. ".  Say a name to cast. Press L to change spells."
	toast.TextColor3 = C.good
	toast.Visible = true
	task.delay(5, function() if not open then toast.Visible = false end end)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.L then
		if open then closePanel() else openPanel() end
	end
end)

openPanel()
