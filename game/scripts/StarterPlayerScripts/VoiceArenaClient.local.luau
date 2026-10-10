-- StarterPlayer.StarterPlayerScripts.VoiceArenaClient (LocalScript)
-- Mouse aim and the spell HUD (spells are cast by voice only): one circle per equipped spell. On cast a grey
-- clock-wipe overlay sweeps away with the seconds remaining on top; the ring pulses when ready.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local remotes = ReplicatedStorage:WaitForChild("VoiceArena")
local feedback, aim = remotes:WaitForChild("Feedback"), remotes:WaitForChild("Aim")

local ACCENTS = { Color3.fromRGB(255, 140, 60), Color3.fromRGB(110, 210, 255), Color3.fromRGB(90, 150, 255) }
local SIZE, GAP = 104, 26
local TEXT = Color3.fromRGB(235, 242, 255)
local DIM = Color3.fromRGB(150, 160, 190)
local BAD = Color3.fromRGB(255, 110, 110)

local function new(class, props, children)
	local inst = Instance.new(class)
	for k, v in props do if k ~= "Parent" then inst[k] = v end end
	for _, child in ipairs(children or {}) do child.Parent = inst end
	if props.Parent then inst.Parent = props.Parent end
	return inst
end
local function round() return new("UICorner", { CornerRadius = UDim.new(1, 0) }) end
local function tween(inst, t, props, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local gui = new("ScreenGui", { Name = "VoiceArenaHUD", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui") })
local width = SIZE * 3 + GAP * 2
local holder = new("Frame", { Name = "SpellBar", Size = UDim2.fromOffset(width + 40, SIZE + 74), AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -14), BackgroundTransparency = 1, Parent = gui })
local hudScale = new("UIScale", { Parent = holder })

-- status line: voice connection dot + text, and a message line for casts/errors
local statusRow = new("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Parent = holder })
local dot = new("Frame", { Size = UDim2.fromOffset(8, 8), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.5, -110, 0.5, 0),
	BackgroundColor3 = BAD, Parent = statusRow }, { round() })
local status = new("TextLabel", { Size = UDim2.new(0, 220, 1, 0), Position = UDim2.new(0.5, -96, 0, 0), BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left,
	Text = "VOICE OFFLINE  /  RUN START.CMD", TextStrokeTransparency = 0.6, Parent = statusRow })
local message = new("TextLabel", { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 20), BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = TEXT, Text = "", TextStrokeTransparency = 0.5, Parent = holder })

local slots = {}
local names = { "Flame", "Freeze", "Wave" } -- updated when the player equips a loadout

local function makeSlot(i)
	local accent = ACCENTS[i]
	local x = 20 + (i - 1) * (SIZE + GAP)
	local frame = new("Frame", { Name = "Spell" .. i, Size = UDim2.fromOffset(SIZE, SIZE), Position = UDim2.fromOffset(x, 48),
		BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, Parent = holder }, {
		round(),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, accent:Lerp(Color3.new(1, 1, 1), 0.15)),
			ColorSequenceKeypoint.new(0.55, accent:Lerp(Color3.new(0, 0, 0), 0.35)),
			ColorSequenceKeypoint.new(1, accent:Lerp(Color3.new(0, 0, 0), 0.7)),
		}) }),
	})
	local punch = new("UIScale", { Parent = frame })
	local ring = new("UIStroke", { Color = accent:Lerp(Color3.new(1, 1, 1), 0.45), Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = frame })

	local nameLabel = new("TextLabel", { Size = UDim2.new(0.84, 0, 0.36, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.47),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, Text = string.upper(names[i] or ""), TextColor3 = TEXT, TextScaled = true,
		TextStrokeTransparency = 0.45, ZIndex = 4, Parent = frame }, { new("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 8 }) })

	-- radial cooldown overlay: two half-circle clips, each revealing a rotating half-plane
	local overlay = new("CanvasGroup", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 3,
		Parent = frame }, { round() })
	local function half(position, rotPosition, childPosition)
		local clip = new("Frame", { Size = UDim2.fromScale(0.5, 1), Position = position, BackgroundTransparency = 1,
			ClipsDescendants = true, Parent = overlay })
		local rot = new("Frame", { Size = UDim2.fromOffset(SIZE * 2, SIZE * 2), AnchorPoint = Vector2.new(0.5, 0.5), Position = rotPosition,
			BackgroundTransparency = 1, Parent = clip })
		new("Frame", { Size = UDim2.fromScale(0.5, 1), Position = childPosition, BackgroundColor3 = Color3.fromRGB(58, 62, 74),
			BackgroundTransparency = 0.04, BorderSizePixel = 0, Parent = rot })
		return rot
	end
	local rightRot = half(UDim2.fromScale(0.5, 0), UDim2.fromScale(0, 0.5), UDim2.fromScale(0, 0))   -- 12 -> 6 o'clock
	local leftRot = half(UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.5), UDim2.fromScale(0.5, 0))   -- 6 -> 12 o'clock

	local timer = new("TextLabel", { Size = UDim2.fromScale(1, 0.42), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 32, TextColor3 = Color3.new(1, 1, 1), Text = "",
		TextStrokeTransparency = 0.35, Visible = false, ZIndex = 5, Parent = frame })

	local slot = { frame = frame, punch = punch, ring = ring, name = nameLabel, overlay = overlay,
		rightRot = rightRot, leftRot = leftRot, timer = timer, accent = accent, readyAt = 0, total = 1, cooling = false }
	slots[i] = slot
	return slot
end
for i = 1, 3 do makeSlot(i) end

local function setCooling(slot, cooling)
	if slot.cooling == cooling then return end
	slot.cooling = cooling
	slot.overlay.Visible = cooling
	slot.timer.Visible = cooling
	if cooling then
		tween(slot.name, 0.15, { Position = UDim2.fromScale(0.5, 0.72), Size = UDim2.new(0.7, 0, 0.2, 0), TextColor3 = Color3.fromRGB(200, 205, 220) })
		tween(slot.ring, 0.15, { Color = Color3.fromRGB(110, 116, 132), Thickness = 2 })
	else
		-- ready again: restore and pulse
		tween(slot.name, 0.2, { Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.new(0.84, 0, 0.36, 0), TextColor3 = TEXT })
		slot.ring.Color = Color3.new(1, 1, 1)
		slot.ring.Thickness = 7
		tween(slot.ring, 0.45, { Color = slot.accent:Lerp(Color3.new(1, 1, 1), 0.45), Thickness = 3 })
		slot.punch.Scale = 1.12
		tween(slot.punch, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		local pulse = new("Frame", { Size = UDim2.fromScale(1, 1), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1, ZIndex = 1, Parent = slot.frame }, { round(), new("UIStroke", { Color = slot.accent, Thickness = 3 }) })
		tween(pulse, 0.5, { Size = UDim2.fromScale(1.5, 1.5) })
		tween(pulse:FindFirstChildOfClass("UIStroke"), 0.5, { Transparency = 1 })
		task.delay(0.55, function() pulse:Destroy() end)
	end
end

local function setNames(list)
	names = list
	for i, slot in ipairs(slots) do
		slot.name.Text = string.upper(list[i] or "")
		slot.readyAt = 0
		setCooling(slot, false)
	end
end

local messageToken = 0
local function say(text, color)
	messageToken += 1
	local token = messageToken
	message.Text = text
	message.TextColor3 = color or TEXT
	message.TextTransparency = 0
	task.delay(3.5, function()
		if messageToken == token then tween(message, 0.5, { TextTransparency = 1 }) end
	end)
end

local function slotFor(event)
	if type(event.slot) == "number" and slots[event.slot] then return slots[event.slot] end
	for i, n in ipairs(names) do
		if type(event.spell) == "string" and string.lower(n) == string.lower(event.spell) then return slots[i] end
	end
	return nil
end

feedback.OnClientEvent:Connect(function(event)
	if event.kind == "bridge" then
		dot.BackgroundColor3 = event.connected and Color3.fromRGB(110, 230, 150) or BAD
		if event.connected then
			status.Text = event.voiceActive and "VOICE CONNECTED  /  MIC ACTIVE" or "VOICE CONNECTED  /  PICK PLAYER IN CONSOLE"
		else
			status.Text = "VOICE OFFLINE  /  RUN START.CMD"
		end
	elseif event.kind == "cast" then
		local slot = slotFor(event)
		if event.ok then
			if slot and type(event.value) == "number" and event.value > 0 then
				slot.total = event.value
				slot.readyAt = os.clock() + event.value
				setCooling(slot, true)
				slot.punch.Scale = 0.86
				tween(slot.punch, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			end
			say(string.upper(tostring(event.spell)) .. "!", slot and slot.accent)
		else
			say(tostring(event.value), BAD)
			if slot then
				slot.ring.Color = BAD
				tween(slot.ring, 0.4, { Color = slot.cooling and Color3.fromRGB(110, 116, 132) or slot.accent:Lerp(Color3.new(1, 1, 1), 0.45) })
				local base = slot.frame.Position
				for _, dx in ipairs({ -5, 5, -3, 3, 0 }) do
					slot.frame.Position = base + UDim2.fromOffset(dx, 0)
					task.wait(0.03)
				end
				slot.frame.Position = base
			end
		end
	elseif event.kind == "loadout" and type(event.names) == "table" then
		setNames(event.names)
		say("Say " .. table.concat(event.names, ", ") .. " to cast. Press L to change spells.")
	elseif event.kind == "note" then
		say(tostring(event.text), BAD)
	end
end)

local accumulated = 0
RunService.RenderStepped:Connect(function(dt)
	local camera = workspace.CurrentCamera
	if camera then hudScale.Scale = math.clamp((camera.ViewportSize.X - 20) / (width + 40), 0.55, 1) end
	-- cooldown sweep
	local now = os.clock()
	for _, slot in ipairs(slots) do
		local remaining = slot.readyAt - now
		if remaining > 0 then
			setCooling(slot, true)
			local angle = 360 * math.clamp(remaining / slot.total, 0, 1)
			slot.rightRot.Rotation = math.min(angle, 180)
			slot.leftRot.Rotation = math.clamp(angle - 180, 0, 180)
			slot.timer.Text = remaining >= 10 and string.format("%d", math.ceil(remaining)) or string.format("%.1f", remaining)
		elseif slot.cooling then
			setCooling(slot, false)
		end
	end
	-- mouse aim (10 times a second)
	accumulated += dt
	if accumulated < 0.1 then return end
	accumulated = 0
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local direction = mouse.Hit.Position - (root.Position + Vector3.new(0, 1, 0))
		if direction.Magnitude > 0.1 then aim:FireServer(direction.Unit) end
	end
end)
