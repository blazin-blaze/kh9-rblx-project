-- StarterPlayer.StarterPlayerScripts.SpellLoadoutClient (LocalScript)
-- "Set your spells" screen. For each of 3 slots the player names the spell (the word they'll
-- say to cast it) and either picks a preset or describes a new spell for Gemini to write.
-- Press L to reopen. Server side: ServerScriptService.VoiceArena.Loadout.
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

local C = {
	bg = Color3.fromRGB(12, 16, 32), card = Color3.fromRGB(20, 26, 48), field = Color3.fromRGB(10, 13, 26),
	text = Color3.fromRGB(230, 236, 255), dim = Color3.fromRGB(140, 150, 185), accent = Color3.fromRGB(124, 92, 255),
	good = Color3.fromRGB(110, 230, 150), warn = Color3.fromRGB(255, 180, 80), bad = Color3.fromRGB(255, 105, 105),
	stroke = Color3.fromRGB(70, 78, 120),
}
local SLOT_ACCENTS = { Color3.fromRGB(255, 140, 60), Color3.fromRGB(110, 210, 255), Color3.fromRGB(90, 150, 255) }
local PRESETS = {
	{ id = "Flame", label = "Flame Spell", info = "Aimed fireball. 20 damage, then burns for 5 seconds." },
	{ id = "Freeze", label = "Freeze Spell", info = "Ice bolt that freezes the target in place for 5 seconds." },
	{ id = "Wave", label = "Wave Spell", info = "A wall of water that sweeps forward, pushing enemies and blocking shots." },
}
local DEFAULTS = { { name = "Flame", preset = 1 }, { name = "Ice", preset = 2 }, { name = "Wave", preset = 3 } }

local function new(class, props, children)
	local inst = Instance.new(class)
	for k, v in props do if k ~= "Parent" then inst[k] = v end end
	for _, child in ipairs(children or {}) do child.Parent = inst end
	if props.Parent then inst.Parent = props.Parent end
	return inst
end
local function corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r) }) end
local function stroke(color, thickness, transparency)
	return new("UIStroke", { Color = color, Thickness = thickness or 1, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end
local function label(props)
	props.BackgroundTransparency = 1
	props.Font = props.Font or Enum.Font.GothamMedium
	props.TextColor3 = props.TextColor3 or C.text
	props.TextWrapped = true
	return new("TextLabel", props)
end
local function button(props, children)
	props.AutoButtonColor = true
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or C.text
	props.BackgroundColor3 = props.BackgroundColor3 or C.field
	local b = new("TextButton", props, children)
	corner(10).Parent = b
	return b
end

---------------------------------------------------------------- layout
local gui = new("ScreenGui", { Name = "SpellLoadout", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = true, DisplayOrder = 10, Parent = player:WaitForChild("PlayerGui") })
local backdrop = new("TextButton", { Name = "Backdrop", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.45, Text = "", AutoButtonColor = false, Modal = true, Parent = gui })
local panel = new("Frame", { Name = "Panel", Size = UDim2.fromOffset(960, 600), AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = C.bg, Parent = gui }, { corner(18), stroke(Color3.fromRGB(90, 80, 160), 1.5, 0.35) })
local uiScale = new("UIScale", { Parent = panel })
label({ Text = "SET YOUR SPELLS", Font = Enum.Font.GothamBlack, TextSize = 32, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 18), Parent = panel })
label({ Text = "Name each spell. Its name is the word you'll say out loud to cast it.", TextSize = 15, TextColor3 = C.dim,
	Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 60), Parent = panel })
local footerStatus = label({ Text = "", TextSize = 14, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.fromOffset(640, 40), Position = UDim2.fromOffset(28, 540), Parent = panel })
local beginButton = button({ Text = "BEGIN", TextSize = 20, Font = Enum.Font.GothamBlack, BackgroundColor3 = C.accent,
	Size = UDim2.fromOffset(220, 46), Position = UDim2.fromOffset(712, 536), Parent = panel })
local toast = label({ Text = "", TextSize = 18, Font = Enum.Font.GothamBold, Size = UDim2.new(1, 0, 0, 30),
	Position = UDim2.new(0, 0, 0, 80), Visible = false, TextStrokeTransparency = 0.5, Parent = gui })

local function fit()
	local camera = workspace.CurrentCamera
	if camera then
		local v = camera.ViewportSize
		uiScale.Scale = math.clamp(math.min((v.X - 24) / 960, (v.Y - 24) / 600), 0.45, 1.25)
	end
end
fit()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(fit)
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit) end

---------------------------------------------------------------- code viewer
local viewer = new("Frame", { Name = "CodeViewer", Size = UDim2.fromOffset(760, 470), AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(8, 10, 20), Visible = false, ZIndex = 50, Parent = panel },
	{ corner(14), stroke(C.accent, 1.5, 0.2) })
local viewerTitle = label({ Text = "", Font = Enum.Font.GothamBlack, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, -140, 0, 28), Position = UDim2.fromOffset(20, 14), ZIndex = 51, Parent = viewer })
local viewerInfo = label({ Text = "", TextSize = 13, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, -40, 0, 34), Position = UDim2.fromOffset(20, 42), ZIndex = 51, Parent = viewer })
local viewerClose = button({ Text = "CLOSE", TextSize = 14, Size = UDim2.fromOffset(100, 32), Position = UDim2.new(1, -120, 0, 14),
	BackgroundColor3 = C.card, ZIndex = 52, Parent = viewer })
local scroller = new("ScrollingFrame", { Size = UDim2.new(1, -40, 1, -100), Position = UDim2.fromOffset(20, 84),
	BackgroundColor3 = Color3.fromRGB(14, 17, 32), ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(), ZIndex = 51, Parent = viewer }, { corner(8) })
local codeText = label({ Text = "", Font = Enum.Font.Code, TextSize = 14, TextColor3 = Color3.fromRGB(190, 255, 210),
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, -20, 0, 0),
	Position = UDim2.fromOffset(10, 8), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 52, Parent = scroller })
viewerClose.Activated:Connect(function() viewer.Visible = false end)

---------------------------------------------------------------- cards
local cards = {}
local CARD_W, CARD_H, GAP = 290, 440, 20
local startX = (960 - (CARD_W * 3 + GAP * 2)) / 2

local function setMode(card, mode)
	card.mode = mode
	local aiOn = mode == "custom"
	card.aiStroke.Color = aiOn and card.accent or C.stroke
	card.aiStroke.Thickness = aiOn and 2 or 1
	card.aiStroke.Transparency = aiOn and 0 or 0.5
	card.ddStroke.Color = aiOn and C.stroke or card.accent
	card.ddStroke.Thickness = aiOn and 1 or 2
	card.ddStroke.Transparency = aiOn and 0.5 or 0
	card.aiArea.Visible = aiOn
	card.presetInfo.Visible = not aiOn
	card.list.Visible = false
end

local function setPreset(card, index)
	card.preset = index
	card.dropdown.Text = "   " .. PRESETS[index].label
	card.presetInfo.Text = PRESETS[index].info
	setMode(card, "preset")
end

local function setHint(card, text, color)
	card.hint.Text = text
	card.hint.TextColor3 = color or C.dim
end

local function validateName(text)
	local clean = string.gsub(string.gsub(text or "", "^%s+", ""), "%s+$", "")
	if clean == "" then return nil, "Give this spell a name" end
	if not string.match(clean, "^%a+$") then return nil, "One word, letters only" end
	if #clean < 3 or #clean > 20 then return nil, "Use 3 to 20 letters" end
	return clean
end

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
	local accent = SLOT_ACCENTS[i]
	local frame = new("Frame", { Name = "Card" .. i, Size = UDim2.fromOffset(CARD_W, CARD_H),
		Position = UDim2.fromOffset(startX + (i - 1) * (CARD_W + GAP), 92), BackgroundColor3 = C.card, Parent = panel },
		{ corner(14), stroke(accent, 1, 0.6) })
	local card = { index = i, frame = frame, accent = accent }
	label({ Text = "SPELL " .. i, Font = Enum.Font.GothamBlack, TextSize = 13, TextColor3 = accent,
		Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 12), Parent = frame })
	label({ Text = "ACTIVATION WORD", Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C.dim,
		Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 34), Parent = frame })
	card.nameBox = new("TextBox", { Text = DEFAULTS[i].name, PlaceholderText = "Say this word", Font = Enum.Font.GothamBlack,
		TextSize = 30, TextColor3 = C.text, PlaceholderColor3 = Color3.fromRGB(80, 88, 120), BackgroundColor3 = C.field,
		ClearTextOnFocus = false, Size = UDim2.new(1, -32, 0, 48), Position = UDim2.fromOffset(16, 52), Parent = frame },
		{ corner(10), stroke(C.stroke, 1, 0.4) })
	card.hint = label({ Text = "The word you'll say to cast it", TextSize = 12, TextColor3 = C.dim,
		Size = UDim2.new(1, -20, 0, 16), Position = UDim2.fromOffset(10, 104), Parent = frame })

	card.aiButton = button({ Text = "CREATE YOUR OWN SPELL WITH AI", TextSize = 12, Size = UDim2.new(1, -32, 0, 38),
		Position = UDim2.fromOffset(16, 126), Parent = frame })
	card.aiStroke = stroke(C.stroke, 1, 0.5); card.aiStroke.Parent = card.aiButton
	label({ Text = "or", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.dim,
		Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 170), Parent = frame })
	card.dropdown = button({ Text = "", TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -32, 0, 38),
		Position = UDim2.fromOffset(16, 190), Parent = frame })
	label({ Text = "v", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.dim, Size = UDim2.fromOffset(30, 38),
		Position = UDim2.new(1, -34, 0, 0), Parent = card.dropdown })
	card.ddStroke = stroke(C.stroke, 1, 0.5); card.ddStroke.Parent = card.dropdown

	card.list = new("Frame", { Size = UDim2.new(1, -32, 0, #PRESETS * 36 + 8), Position = UDim2.fromOffset(16, 230),
		BackgroundColor3 = Color3.fromRGB(28, 34, 62), Visible = false, ZIndex = 20, Parent = frame }, { corner(10), stroke(accent, 1, 0.3) })
	for p, preset in ipairs(PRESETS) do
		local option = button({ Text = "   " .. preset.label, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = Color3.fromRGB(28, 34, 62), Size = UDim2.new(1, -8, 0, 34), Position = UDim2.fromOffset(4, 4 + (p - 1) * 36),
			ZIndex = 21, Parent = card.list })
		option.Activated:Connect(function() setPreset(card, p) end)
	end

	card.presetInfo = label({ Text = "", TextSize = 13, TextColor3 = C.dim, TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -40, 0, 140), Position = UDim2.fromOffset(20, 244), Parent = frame })

	card.aiArea = new("Frame", { Size = UDim2.new(1, -32, 0, 150), Position = UDim2.fromOffset(16, 238), BackgroundTransparency = 1, Parent = frame })
	card.prompt = new("TextBox", { Text = "", PlaceholderText = "Describe your spell, e.g. \"a green fireball that splits into three\"",
		Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = C.text, PlaceholderColor3 = Color3.fromRGB(95, 104, 140),
		TextWrapped = true, MultiLine = true, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, BackgroundColor3 = C.field, Size = UDim2.new(1, 0, 0, 62), Parent = card.aiArea },
		{ corner(8), stroke(C.stroke, 1, 0.4), new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 6) }) })
	card.generate = button({ Text = "GENERATE", TextSize = 13, BackgroundColor3 = C.accent, Size = UDim2.new(0.64, -4, 0, 30),
		Position = UDim2.fromOffset(0, 68), Parent = card.aiArea })
	card.codeButton = button({ Text = "CODE", TextSize = 12, BackgroundColor3 = C.field, Size = UDim2.new(0.36, -4, 0, 30),
		Position = UDim2.new(0.64, 4, 0, 68), Visible = false, Parent = card.aiArea })
	card.aiStatus = label({ Text = "Gemini writes the Luau for your spell.", TextSize = 12, TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, 48), Position = UDim2.fromOffset(0, 102), Parent = card.aiArea })

	card.test = button({ Text = "TRY IT", TextSize = 13, BackgroundColor3 = Color3.fromRGB(32, 40, 72), Size = UDim2.new(1, -32, 0, 32),
		Position = UDim2.fromOffset(16, CARD_H - 44), Parent = frame })

	-- wiring
	card.aiButton.Activated:Connect(function() setMode(card, "custom") end)
	card.dropdown.Activated:Connect(function()
		if card.mode ~= "preset" then setMode(card, "preset") end
		card.list.Visible = not card.list.Visible
	end)
	card.nameBox.FocusLost:Connect(function()
		local clean, err = validateName(card.nameBox.Text)
		if clean then card.nameBox.Text = clean; setHint(card, "The word you'll say to cast it") else setHint(card, err, C.bad) end
	end)
	card.codeButton.Activated:Connect(function()
		if not card.code then return end
		viewerTitle.Text = "GEMINI LUAU  /  " .. string.upper(card.title or "AI SPELL")
		viewerInfo.Text = card.description or ""
		codeText.Text = card.code
		viewer.Visible = true
	end)
	card.generate.Activated:Connect(function()
		if card.forging then return end
		local prompt = card.prompt.Text
		if #string.gsub(prompt, "%s", "") < 3 then
			card.aiStatus.Text = "Describe your spell first."
			card.aiStatus.TextColor3 = C.bad
			return
		end
		card.forging = true
		card.generate.Text = "WRITING..."
		card.generate.AutoButtonColor = false
		card.aiStatus.TextColor3 = C.dim
		local started = os.clock()
		task.spawn(function()
			while card.forging do
				local dots = string.rep(".", math.floor((os.clock() - started) * 3) % 4)
				card.aiStatus.Text = string.format("Gemini is writing your spell%s (%ds)", dots, math.floor(os.clock() - started))
				task.wait(0.1)
			end
		end)
		local ok, result = pcall(function()
			return ForgeSpell:InvokeServer(i, validateName(card.nameBox.Text) or "", prompt)
		end)
		card.forging = false
		card.generate.Text = "GENERATE"
		card.generate.AutoButtonColor = true
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
		card.codeButton.Visible = true
		setMode(card, "custom")
		if result.fallback then
			card.aiStatus.Text = "BACKUP SPELL: Gemini's version didn't work, so an improvised " .. tostring(result.element) .. " spell was made. Try generating again for a custom one."
			card.aiStatus.TextColor3 = C.warn
		else
			card.aiStatus.Text = string.format("READY: %s. %s", tostring(result.title), tostring(result.description))
			card.aiStatus.TextColor3 = C.good
		end
	end)
	card.test.Activated:Connect(function()
		local def, err = definition(card)
		if not def then setHint(card, err, C.bad); return end
		def.name = validateName(card.nameBox.Text) or ("Spell " .. i)
		closePanel(true)
		toast.Text = "Testing " .. def.name .. "..."
		toast.TextColor3 = card.accent
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
	TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Position = UDim2.fromScale(0.5, 0.5) }):Play()
end
function closePanel(keepToast)
	open = false
	setChat(true)
	panel.Visible = false
	backdrop.Visible = false
	viewer.Visible = false
	if not keepToast then toast.Visible = false end
end

beginButton.Activated:Connect(function()
	local slots, problems = {}, false
	for i, card in ipairs(cards) do
		local clean, nameErr = validateName(card.nameBox.Text)
		local def, defErr = definition(card)
		if not clean then setHint(card, nameErr, C.bad); problems = true
		elseif not def then setHint(card, defErr, C.bad); problems = true
		else setHint(card, "The word you'll say to cast it") end
		slots[i] = def or { name = card.nameBox.Text, kind = "preset", preset = "Flame" }
		slots[i].name = card.nameBox.Text
	end
	if problems then footerStatus.Text = "Fix the highlighted spells first."; footerStatus.TextColor3 = C.bad; return end
	footerStatus.Text = "Equipping..."
	footerStatus.TextColor3 = C.dim
	local ok, result = pcall(function() return SetLoadout:InvokeServer(slots) end)
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
		return
	end
	footerStatus.Text = ""
	closePanel()
	toast.Text = "Equipped: " .. table.concat(result.names, "  /  ") .. ".  Say a name to cast. Press L to change spells."
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
