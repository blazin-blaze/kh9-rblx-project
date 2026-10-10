-- StarterPlayer.StarterPlayerScripts.SpellForgeClient (LocalScript)
-- Draws everything AI-generated spells do. The server runs the spell's Luau in a sandbox
-- (ServerScriptService.VoiceArena.SpellFx) and streams draw ops through
-- ReplicatedStorage.VoiceArena.FxDraw. Unknown styles get a custom palette from their color.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local FX = require(script:WaitForChild("FXUtil"))
local Cam = require(script:WaitForChild("CameraFX"))

local localPlayer = Players.LocalPlayer
local draw = ReplicatedStorage:WaitForChild("VoiceArena"):WaitForChild("FxDraw")

local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local NEON, GLASS, FORCEFIELD = Enum.Material.Neon, Enum.Material.Glass, Enum.Material.ForceField
local TOP = Enum.NormalId.Top
local DEFAULT_COLOR = rgb(170, 120, 255)

---------------------------------------------------------------- palettes
local STYLES = {
	fire = { core = rgb(255, 248, 225), mid = rgb(255, 170, 50), edge = rgb(255, 90, 20), dark = rgb(200, 40, 10), tex = "fire", smoke = rgb(110, 95, 85), scorch = rgb(20, 16, 14), sound = "fire", impact = "explosion" },
	ice = { core = rgb(235, 252, 255), mid = rgb(140, 225, 255), edge = rgb(60, 150, 255), dark = rgb(30, 90, 200), tex = "sparkle", mist = rgb(230, 250, 255), crystal = true, patch = Enum.Material.Ice, debris = GLASS, sound = "ice", impact = "glass" },
	lightning = { core = rgb(250, 245, 255), mid = rgb(205, 170, 255), edge = rgb(130, 95, 255), dark = rgb(60, 40, 140), tex = "sparkle", arcs = true, scorch = rgb(15, 12, 20), sound = "zap", impact = "thunder" },
	water = { core = rgb(220, 245, 255), mid = rgb(80, 180, 255), edge = rgb(20, 100, 220), dark = rgb(10, 50, 140), tex = "sparkle", mist = rgb(200, 235, 255), debris = GLASS, patch = GLASS, sound = "water", impact = "water" },
	shadow = { core = rgb(210, 140, 255), mid = rgb(120, 50, 190), edge = rgb(45, 15, 80), dark = rgb(15, 5, 25), tex = "smoke", smoke = rgb(30, 15, 45), scorch = rgb(10, 5, 15), sound = "magic", impact = "explosion" },
	arcane = { core = rgb(255, 235, 255), mid = rgb(235, 110, 255), edge = rgb(140, 70, 255), dark = rgb(70, 30, 140), tex = "sparkle", sound = "magic", impact = "magic" },
	nature = { core = rgb(235, 255, 220), mid = rgb(120, 230, 90), edge = rgb(40, 150, 60), dark = rgb(20, 80, 30), tex = "sparkle", debris = Enum.Material.Grass, sound = "magic", impact = "impact" },
	holy = { core = rgb(255, 255, 245), mid = rgb(255, 225, 130), edge = rgb(255, 180, 60), dark = rgb(200, 120, 30), tex = "sparkle", sound = "heal", impact = "magic" },
	poison = { core = rgb(235, 255, 200), mid = rgb(150, 240, 60), edge = rgb(100, 40, 150), dark = rgb(40, 60, 20), tex = "smoke", smoke = rgb(110, 170, 50), sound = "magic", impact = "water" },
	rock = { core = rgb(220, 200, 170), mid = rgb(150, 120, 90), edge = rgb(90, 70, 55), dark = rgb(50, 40, 30), tex = "smoke", smoke = rgb(150, 130, 110), solid = true, debris = Enum.Material.Slate, sound = "whoosh", impact = "impact" },
	wind = { core = rgb(255, 255, 255), mid = rgb(215, 245, 235), edge = rgb(150, 220, 210), dark = rgb(90, 150, 140), tex = "smoke", mist = rgb(235, 255, 250), sound = "whoosh", impact = "whoosh" },
}
local ALIASES = {
	flame = "fire", flames = "fire", lava = "fire", magma = "fire", frost = "ice", freeze = "ice", snow = "ice", cold = "ice",
	electric = "lightning", electricity = "lightning", thunder = "lightning", storm = "lightning", shock = "lightning",
	dark = "shadow", darkness = "shadow", void = "shadow", magic = "arcane", light = "holy", sun = "holy", radiant = "holy",
	earth = "rock", stone = "rock", ground = "rock", air = "wind", acid = "poison", toxic = "poison", venom = "poison",
	leaf = "nature", plant = "nature", ocean = "water", aqua = "water",
}

-- Unknown style + color = a custom palette built from that color (the visual failsafe).
local function palette(style, color)
	local key = type(style) == "string" and (ALIASES[style] or style) or nil
	local base = key and STYLES[key]
	if not base and not color then base = STYLES.arcane end
	local p = table.clone(base or { tex = "sparkle", sound = "magic", impact = "impact" })
	if color then
		p.mid = color
		p.core = color:Lerp(WHITE, 0.65)
		p.edge = color:Lerp(BLACK, 0.25)
		p.dark = color:Lerp(BLACK, 0.6)
		if p.smoke then p.smoke = color:Lerp(rgb(90, 85, 85), 0.6) end
		if p.mist then p.mist = color:Lerp(WHITE, 0.7) end
	end
	return p
end

local SOUNDS = {
	fire = { "launch", 1.1, 0.8 }, explosion = { "shot", 0.45, 1.2 }, thunder = { "thunder", 1, 1.4 },
	ice = { "unsheath", 1.3, 0.8 }, glass = { "glass", 1, 1 }, whoosh = { "whoosh", 1, 0.8 },
	magic = { "ping", 0.6, 0.6 }, water = { "whoosh", 0.55, 0.9 }, impact = { "collide", 0.6, 1 },
	zap = { "slash", 1.8, 0.7 }, heal = { "ping", 1.4, 0.5 },
}
local function playSound(name, pos, volumeScale)
	local s = SOUNDS[name] or SOUNDS.magic
	FX.sound(FX.SND[s[1]], pos, s[3] * (volumeScale or 1), s[2])
	if name == "explosion" then FX.sound(FX.SND.collide, pos, 0.8, 0.5) end
end

local function casterRoot(userId)
	local plr = userId and Players:GetPlayerByUserId(userId)
	local char = plr and plr.Character
	return char and char:FindFirstChild("HumanoidRootPart"), char, plr
end

---------------------------------------------------------------- shared pieces
local function addTrail(part, halfWidth, lifetime, color)
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, halfWidth, 0); a0.Parent = part
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -halfWidth, 0); a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = lifetime
	trail.Color = color
	trail.Transparency = FX.nseq(0, 0.05, 1, 1)
	trail.WidthScale = FX.nseq(0, 1, 1, 0)
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.FaceCamera = true
	trail.MinLength = 0.05
	trail.Parent = part
	return trail
end

local function spike(base, dir, length, width, delayTime, hold, p)
	local cf = FX.lookAt(base + dir * length * 0.5, base + dir * length) * CFrame.Angles(0, 0, math.pi / 4)
	local shell, core
	if p.crystal or p.debris == GLASS then
		shell = FX.part({ Size = Vector3.one * 0.1, CFrame = cf, Material = GLASS, Color = p.mid, Transparency = 0.2, Reflectance = 0.35 })
		core = FX.part({ Size = Vector3.one * 0.05, CFrame = cf, Color = p.core })
	elseif p.solid then
		shell = FX.part({ Size = Vector3.one * 0.1, CFrame = cf, Material = Enum.Material.Slate, Color = p.mid })
	else
		shell = FX.part({ Size = Vector3.one * 0.1, CFrame = cf, Color = p.mid, Transparency = 0.1 })
		core = FX.part({ Size = Vector3.one * 0.05, CFrame = cf, Color = p.core })
	end
	FX.tween(shell, 0.16, { Size = Vector3.new(width, width, length) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, delayTime)
	if core then
		FX.tween(core, 0.16, { Size = Vector3.new(width * 0.35, width * 0.35, length * 0.85) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, delayTime)
	end
	task.delay(delayTime + hold, function()
		if shell.Parent then
			FX.shards(shell.Position, dir, 3, { color = p.mid, material = shell.Material, transparency = shell.Transparency,
				reflectance = shell.Reflectance, speed = 22, life = 1.1, size = width * 0.4, spread = 1.4 })
			shell:Destroy()
		end
		if core then core:Destroy() end
	end)
end

---------------------------------------------------------------- lightning bolts
local function jagged(a, b, depth, roughness)
	local pts = { a, b }
	local delta = b - a
	local len = delta.Magnitude
	if len < 1e-3 then
		local out = {}
		for i = 1, 2 ^ depth + 1 do out[i] = a end
		return out
	end
	local dir = delta / len
	local disp = len * roughness
	for _ = 1, depth do
		local nextPts = { pts[1] }
		for i = 1, #pts - 1 do
			local r = FX.unit()
			r -= dir * r:Dot(dir)
			table.insert(nextPts, (pts[i] + pts[i + 1]) / 2 + r * FX.rand(-disp, disp))
			table.insert(nextPts, pts[i + 1])
		end
		pts = nextPts
		disp *= 0.5
	end
	return pts
end

local function newBolt(depth, coreWidth, glowWidth, coreColor, glowColor)
	local holder = FX.part({ Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.identity })
	local bolt = { depth = depth, holder = holder, atts = {}, beams = {} }
	for i = 1, 2 ^ depth + 1 do
		local a = Instance.new("Attachment"); a.Parent = holder
		bolt.atts[i] = a
	end
	for i = 1, #bolt.atts - 1 do
		for _, spec in ipairs({ { coreWidth, coreColor, 0, 4 }, { glowWidth, glowColor, 0.5, 2 } }) do
			local b = Instance.new("Beam")
			b.Attachment0, b.Attachment1 = bolt.atts[i], bolt.atts[i + 1]
			b.Width0, b.Width1 = spec[1], spec[1]
			b.Color = ColorSequence.new(spec[2])
			b.Transparency = NumberSequence.new(spec[3])
			b.Brightness = spec[4]
			b.LightEmission = 1
			b.LightInfluence = 0
			b.FaceCamera = true
			b.Segments = 1
			b.Parent = holder
			table.insert(bolt.beams, { b, spec[3] })
		end
	end
	return bolt
end

local function shape(bolt, a, b, roughness)
	for i, p in ipairs(jagged(a, b, bolt.depth, roughness)) do bolt.atts[i].Position = p end
end

local function setAlpha(bolt, alpha)
	for _, entry in ipairs(bolt.beams) do
		entry[1].Transparency = NumberSequence.new(1 - (1 - entry[2]) * alpha)
	end
end

-- Flicker a set of bolts: strike, restrikes, fade. reshape() re-randomizes them each flash.
local function flicker(bolts, light, reshape)
	local t0 = os.clock()
	for i, at in ipairs({ 0, 0.05, 0.1, 0.16, 0.23, 0.31 }) do
		while os.clock() - t0 < at do RunService.RenderStepped:Wait() end
		reshape()
		local alpha = (i % 2 == 0) and 0.45 or (1 - (i - 1) * 0.1)
		for _, b in ipairs(bolts) do setAlpha(b, alpha) end
		if light then light.Brightness = 20 * alpha end
	end
	local fadeStart = os.clock()
	while os.clock() - fadeStart < 0.2 do
		local k = 1 - (os.clock() - fadeStart) / 0.2
		for _, b in ipairs(bolts) do setAlpha(b, 0.7 * k) end
		if light then light.Brightness = 10 * k end
		RunService.RenderStepped:Wait()
	end
	for _, b in ipairs(bolts) do b.holder:Destroy() end
end

local function groundArcs(pos, normal, p, scale)
	local arcs = {}
	for i = 1, 5 do arcs[i] = newBolt(3, 0.14 * scale, 0.6 * scale, p.core, p.mid) end
	local basis = FX.alignY(pos, normal)
	task.spawn(flicker, arcs, nil, function()
		for _, arc in ipairs(arcs) do
			local ang = FX.rand(0, math.pi * 2)
			local out = basis:VectorToWorldSpace(Vector3.new(math.cos(ang), 0, math.sin(ang)))
			shape(arc, pos, pos + out * FX.rand(3, 8) * scale + normal * 0.2, 0.25)
		end
	end)
end

---------------------------------------------------------------- big impact
local function burst(pos, normal, p, scale)
	normal = (normal and normal.Magnitude > 1e-3) and normal.Unit or Vector3.yAxis
	scale = math.clamp(scale or 1, 0.4, 3)
	FX.pop(pos, p.core, 1.5 * scale, 12 * scale, 0.18)
	FX.pop(pos, p.mid, 2.5 * scale, 16 * scale, 0.32, nil, 0.1)
	FX.pop(pos, p.edge, 4 * scale, 24 * scale, 0.6, FORCEFIELD)
	FX.ring(pos, normal, p.mid, 3 * scale, 32 * scale, 0.5)
	task.delay(0.07, function() FX.ring(pos, normal, p.core, 2 * scale, 22 * scale, 0.4, 0.2) end)

	local a = FX.anchor(FX.alignY(pos, normal), 5)
	if not p.crystal then
		FX.emitter(a, { Texture = FX.TEX.core, Speed = FX.nr(0), Lifetime = FX.nr(0.3, 0.5), Size = FX.nseq(0, 6 * scale, 1, 15 * scale),
			Transparency = FX.nseq(0, 0, 1, 1), Color = FX.cseq(p.core, p.mid, p.edge), LightEmission = 1, Rotation = FX.nr(0, 360) }):Emit(5)
	end
	FX.emitter(a, { Texture = FX.TEX[p.tex] or FX.TEX.sparkle, EmissionDirection = TOP, SpreadAngle = Vector2.new(85, 85),
		Speed = FX.nr(18 * scale, 45 * scale), Drag = 5, Lifetime = FX.nr(0.35, 0.8),
		Size = FX.nseq(0, (p.tex == "sparkle" and 0.8 or 3.5) * scale, 1, 0.5), Transparency = FX.nseq(0, 0, 0.7, 0.4, 1, 1),
		Color = FX.cseq(p.core, p.mid, p.edge), LightEmission = 1, Rotation = FX.nr(0, 360), RotSpeed = FX.nr(-200, 200) }):Emit(math.floor(60 * scale))
	FX.emitter(a, { Texture = FX.TEX.spark, EmissionDirection = TOP, SpreadAngle = Vector2.new(90, 90),
		Speed = FX.nr(25 * scale, 70 * scale), Drag = 1, Lifetime = FX.nr(0.5, 1.3), Size = FX.nseq(0, 0.45, 1, 0),
		Color = FX.cseq(p.core, p.mid), LightEmission = 1, Acceleration = Vector3.new(0, -45, 0) }):Emit(math.floor(70 * scale))
	if p.smoke or p.mist then
		FX.emitter(a, { Texture = FX.TEX.burst, EmissionDirection = TOP, SpreadAngle = Vector2.new(75, 75),
			Speed = FX.nr(4 * scale, 12 * scale), Drag = 1.5, Lifetime = FX.nr(1.3, 2.3), Size = FX.nseq(0, 2.5 * scale, 1, 9 * scale),
			Transparency = FX.nseq(0, 0.65, 0.3, 0.7, 1, 1), Color = FX.cseq(p.mid, p.smoke or p.mist),
			LightEmission = p.mist and 0.3 or 0.1, Acceleration = Vector3.new(0, p.mist and -2 or 5, 0),
			Rotation = FX.nr(0, 360), RotSpeed = FX.nr(-30, 30) }):Emit(math.floor(12 * scale))
	end
	local linger = FX.emitter(a, { Texture = FX.TEX.sparkle, Rate = 30 * scale, SpreadAngle = Vector2.new(180, 180),
		Speed = FX.nr(1, 5), Lifetime = FX.nr(0.8, 1.6), Size = FX.nseq(0, 0.4, 1, 0), Color = FX.cseq(p.core, p.edge),
		LightEmission = 1, Acceleration = Vector3.new(0, p.mist and -4 or 3, 0) })
	task.delay(1.4, function() linger.Enabled = false end)

	if p.crystal then
		for i = 1, math.floor(9 * scale) do
			spike(pos - normal * 0.3, (normal * 1.3 + FX.unit()).Unit, FX.rand(2.5, 6) * scale, FX.rand(0.7, 1.3) * scale, i * 0.01, 0.7, p)
		end
	end
	if p.arcs then groundArcs(pos, normal, p, scale) end
	FX.shards(pos + normal * 0.5, normal, math.floor(10 * scale), {
		color = p.mid, material = p.debris, transparency = p.debris == GLASS and 0.15 or 0,
		reflectance = p.debris == GLASS and 0.4 or 0, speed = 50 * scale, life = 1.6, size = 0.5 * scale, spread = 1.1 })

	local g = FX.ground(pos, 10)
	if g then
		local gp = g.Position + g.Normal * 0.03
		if p.scorch then FX.disk(gp, g.Normal, 8 * scale, p.scorch, Enum.Material.SmoothPlastic, 0.15, 2.5, 1.5) end
		if p.patch then FX.disk(gp, g.Normal, 10 * scale, p.mid, p.patch, 0.15, 2.2, 1.3) end
		FX.disk(gp + g.Normal * 0.02, g.Normal, 6 * scale, p.mid, NEON, 0.25, 0.15, 1)
	end
	FX.flashLight(pos, p.mid, 12, 35 * scale, 0.8)
	playSound(p.impact, pos, math.min(1.3, scale))
	local prox = Cam.shakeAt(pos, 0.85 * math.min(scale, 1.5), 70 * scale)
	if prox > 0 then
		Cam.grade({ tint = p.mid:Lerp(WHITE, 0.6), brightness = 0.22 * prox, contrast = 0.2 * prox, bloom = prox,
			blur = 4 * prox, attack = 0.02, hold = 0.04, release = 0.5 })
		Cam.kick("fov", -4 * prox, 0.03, 0.02, 0.45)
	end
end

---------------------------------------------------------------- projectiles
local projectiles = {}
local function key(op) return tostring(op.cast) .. ":" .. tostring(op.id) end

local function retire(k)
	local st = projectiles[k]
	if not st then return end
	projectiles[k] = nil
	for _, e in ipairs(st.emitters) do e.Enabled = false end
	for _, part in ipairs(st.solids) do part.Transparency = 1; Debris:AddItem(part, 1.6) end
	st.light.Enabled = false
	st.loop:Stop()
end

local function buildProjectile(op)
	local p = palette(op.style, op.color)
	local s = op.size or 1.6
	local cf = FX.lookAt(op.from, op.from + op.dir)
	local core, shell
	if p.solid then
		core = FX.part({ Size = Vector3.one * s * 0.95, CFrame = cf, Color = p.mid, Material = Enum.Material.Slate })
		shell = FX.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * s * 1.35, CFrame = cf, Color = p.edge, Material = FORCEFIELD })
	elseif p.crystal then
		core = FX.part({ Size = Vector3.new(s * 0.3, s * 0.3, s * 2.6), CFrame = cf, Color = p.core })
		shell = FX.part({ Size = Vector3.new(s * 0.7, s * 0.7, s * 2.1), CFrame = cf, Color = p.mid, Material = GLASS, Transparency = 0.2, Reflectance = 0.4 })
	else
		core = FX.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * s * 0.6, CFrame = cf, Color = p.core })
		shell = FX.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * s, CFrame = cf, Color = p.mid, Transparency = 0.25 })
	end
	local aura = FX.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * s * 1.8, CFrame = cf, Color = p.edge, Material = FORCEFIELD })
	local att = Instance.new("Attachment"); att.Parent = core
	local emitters = {
		FX.emitter(att, { Texture = FX.TEX[p.tex] or FX.TEX.sparkle, Rate = 120, Lifetime = FX.nr(0.3, 0.6), Speed = FX.nr(1, 3),
			SpreadAngle = Vector2.new(180, 180), Size = FX.nseq(0, s * (p.tex == "sparkle" and 0.6 or 1.4), 1, s * 0.2),
			Transparency = FX.nseq(0, 0.1, 0.7, 0.5, 1, 1), Color = FX.cseq(p.core, p.mid, p.edge), LightEmission = 1,
			Rotation = FX.nr(0, 360), RotSpeed = FX.nr(-200, 200), Drag = 3 }),
		FX.emitter(att, { Texture = FX.TEX.spark, Rate = 60, Lifetime = FX.nr(0.3, 0.7), Speed = FX.nr(6, 15),
			SpreadAngle = Vector2.new(180, 180), Size = FX.nseq(0, 0.3, 1, 0), Color = FX.cseq(p.core, p.mid), LightEmission = 1,
			Acceleration = Vector3.new(0, p.solid and -30 or -15, 0) }),
	}
	if p.smoke or p.mist then
		table.insert(emitters, FX.emitter(att, { Texture = FX.TEX.smoke, Rate = 40, Lifetime = FX.nr(0.8, 1.4), Speed = FX.nr(0.5, 1.5),
			SpreadAngle = Vector2.new(180, 180), Size = FX.nseq(0, s * 0.6, 1, s * 2.6), Transparency = FX.nseq(0, 0.65, 1, 1),
			Color = ColorSequence.new(p.smoke or p.mist), Rotation = FX.nr(0, 360), RotSpeed = FX.nr(-40, 40),
			Acceleration = Vector3.new(0, 2, 0), LightEmission = p.mist and 0.3 or 0 }))
	end
	addTrail(shell, math.max(0.3, s * 0.5), 0.3, FX.cseq(p.core, p.mid, p.edge))
	local light = Instance.new("PointLight")
	light.Color, light.Brightness, light.Range, light.Shadows = p.mid, 5, 10 + s * 5, false
	light.Parent = core
	local loop = Instance.new("Sound")
	loop.SoundId, loop.Looped, loop.Volume, loop.PlaybackSpeed = FX.SND.whoosh, true, 0.45, p.crystal and 1.4 or 0.9
	loop.RollOffMinDistance = 15
	loop.Parent = core
	loop:Play()
	local _, casterChar = casterRoot(op.caster)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { FX.folder, casterChar }
	playSound(p.sound, op.from, 0.8)
	return {
		from = op.from, dir = op.dir, speed = op.speed or 90, gravity = op.gravity or 0, start = os.clock(),
		pos = op.from, params = params, size = s, spin = p.crystal or p.solid,
		core = core, shell = shell, aura = aura, light = light, loop = loop, emitters = emitters, solids = { core, shell, aura },
	}
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for k, st in projectiles do
		local t = now - st.start
		if not st.parked then
			local target = st.from + st.dir * st.speed * t + Vector3.new(0, -st.gravity, 0) * (0.5 * t * t)
			local move = target - st.pos
			if move.Magnitude > 1e-3 then
				local hit = workspace:Spherecast(st.pos, math.max(0.4, st.size * 0.5), move, st.params)
				if hit then target = hit.Position; st.parked = now end
				st.vel = move.Unit
			end
			st.pos = target
		end
		local cf = FX.lookAt(st.pos, st.pos + (st.vel or st.dir))
		if st.spin then cf *= CFrame.Angles(0, 0, now * 14) end
		local pulse = 1 + math.sin(now * 30) * 0.08
		st.core.CFrame, st.shell.CFrame, st.aura.CFrame = cf, cf, cf
		st.aura.Size = Vector3.one * st.size * 1.8 * pulse
		st.light.Brightness = 5 + math.noise(now * 15, st.size) * 4
		if (st.parked and now - st.parked > 0.6) or t > 7 then retire(k) end
	end
end)

---------------------------------------------------------------- handles (primitives)
local handles = {}
local function fadeHandle(k, t)
	local h = handles[k]
	if not h then return end
	handles[k] = nil
	for _, part in ipairs(h.parts) do
		if part.Parent then FX.tween(part, t, { Transparency = 1 }); Debris:AddItem(part, t + 0.05) end
	end
end
local function register(op, parts)
	local k = key(op)
	local h = { parts = parts, timed = op.duration ~= nil, cast = op.cast }
	handles[k] = h
	if op.duration then task.delay(op.duration, function() if handles[k] == h then fadeHandle(k, 0.25) end end) end
	task.delay(15, function() if handles[k] == h then fadeHandle(k, 0.2) end end)
end
local function withLight(part, color, size)
	if size >= 1.5 then
		local l = Instance.new("PointLight")
		l.Color, l.Brightness, l.Range, l.Shadows = color, 1.2, math.min(24, size * 2.5), false
		l.Parent = part
	end
end
-- Neon brightness scales with color, and many arenas use strong bloom: tone primitives down
-- so a bright yellow block reads as a glowing object instead of a white-out.
local function glow(color) return color:Lerp(BLACK, 0.32) end
local PARTICLE_TEX = { sparkle = "sparkle", fire = "fire", flame = "fire", smoke = "smoke", spark = "spark", sparks = "spark", burst = "burst", explosion = "core" }

---------------------------------------------------------------- op handlers
local H = {}

function H.castfx(op)
	local p = palette(nil, op.color)
	FX.pop(op.pos, p.core, 0.8, 3.5, 0.15)
	FX.pop(op.pos, p.mid, 1.5, 6, 0.3, FORCEFIELD)
	FX.ring(op.pos, op.dir or Vector3.zAxis, p.mid, 1.5, 9, 0.3)
	local a = FX.anchor(op.pos, 2)
	FX.emitter(a, { Texture = FX.TEX.sparkle, SpreadAngle = Vector2.new(180, 180), Speed = FX.nr(6, 16), Drag = 3,
		Lifetime = FX.nr(0.3, 0.7), Size = FX.nseq(0, 0.5, 1, 0), Color = FX.cseq(p.core, p.mid), LightEmission = 1 }):Emit(25)
	FX.flashLight(op.pos, p.mid, 6, 18, 0.35)
	FX.sound(FX.SND.ping, op.pos, 0.4, 0.5)
	if op.caster == localPlayer.UserId then
		Cam.kick("fov", 6, 0.05, 0.03, 0.45)
		Cam.kick("push", -0.8, 0.05, 0.02, 0.4)
		Cam.shake(0.22)
	end
end

function H.projectile(op) projectiles[key(op)] = buildProjectile(op) end

function H.impact(op)
	retire(key(op))
	burst(op.pos, op.normal, palette(op.style, op.color), math.clamp((op.size or 1.6) / 1.6, 0.6, 2.4))
end

function H.explosion(op)
	burst(op.pos, Vector3.yAxis, palette(op.style, op.color), (op.radius or 8) / 8)
end

function H.lightning(op)
	local glow = op.color or rgb(205, 170, 255)
	local core = glow:Lerp(WHITE, 0.8)
	local w = op.width or 1
	local a, b = op.from, op.to
	local len = (b - a).Magnitude
	local dir = len > 1e-3 and (b - a) / len or Vector3.zAxis
	local main = newBolt(len > 50 and 6 or 5, 0.4 * w, 1.8 * w, core, glow)
	local branches = {}
	for i = 1, math.clamp(math.floor(len / 14), 2, 6) do branches[i] = newBolt(4, 0.16 * w, 0.8 * w, core, glow) end
	local all = { main }
	for _, br in ipairs(branches) do table.insert(all, br) end
	local p = palette("lightning", op.color)
	FX.pop(a, core, 1, 5, 0.15)
	FX.pop(a, glow, 2, 8, 0.3, FORCEFIELD)
	FX.pop(b, core, 1.5, 12, 0.14)
	FX.pop(b, glow, 3, 18, 0.45, FORCEFIELD)
	FX.ring(b, -dir, glow, 3, 34, 0.45)
	local ia = FX.anchor(b, 3)
	FX.emitter(ia, { Texture = FX.TEX.spark, SpreadAngle = Vector2.new(180, 180), Speed = FX.nr(30, 80), Drag = 1.5,
		Lifetime = FX.nr(0.4, 1), Size = FX.nseq(0, 0.5, 1, 0), Color = FX.cseq(core, glow), LightEmission = 1,
		Acceleration = Vector3.new(0, -50, 0) }):Emit(80)
	local g = FX.ground(b, 8)
	if g then groundArcs(g.Position, g.Normal, p, 1) end
	local strobe = FX.anchor(b + Vector3.new(0, 2, 0), 1.2)
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Shadows, light.Brightness = glow, 60, false, 20
	light.Parent = strobe
	FX.sound(FX.SND.thunder, b, 1.4, 1)
	FX.sound(FX.SND.slash, a, 0.6, 1.8)
	local prox = math.max(Cam.shakeAt(b, 0.9, 100), Cam.proximity(a, 100), 0.3)
	Cam.grade({ tint = glow:Lerp(WHITE, 0.7), brightness = 0.5 * prox, contrast = 0.35 * prox, saturation = -0.5, bloom = 1.4 * prox, attack = 0.015, hold = 0.03, release = 0.3 })
	Cam.grade({ brightness = 0.3 * prox, contrast = 0.2 * prox, saturation = -0.3, bloom = 0.7 * prox, attack = 0.01, hold = 0.02, release = 0.2, delay = 0.16 })
	if op.caster == localPlayer.UserId then
		Cam.shake(0.5)
		Cam.kick("fov", 12, 0.03, 0.04, 0.5)
		Cam.kick("roll", (math.random() < 0.5 and -1 or 1) * 3.5, 0.03, 0, 0.45)
	end
	flicker(all, light, function()
		local pts = jagged(a, b, main.depth, 0.11)
		for i, pt in ipairs(pts) do main.atts[i].Position = pt end
		for _, br in ipairs(branches) do
			local start = pts[math.clamp(math.floor(#pts * FX.rand(0.12, 0.85)), 1, #pts)]
			shape(br, start, start + (dir + FX.unit() * 0.9).Unit * len * FX.rand(0.1, 0.28), 0.2)
		end
	end)
end

function H.skystrike(op)
	local glow = op.color or rgb(205, 170, 255)
	local core = glow:Lerp(WHITE, 0.8)
	local pos = op.pos
	local top = pos + Vector3.new(FX.rand(-15, 15), 140, FX.rand(-15, 15))
	local sky = newBolt(6, 0.7, 3.4, core, glow)
	local p = palette("lightning", op.color)
	burst(pos, Vector3.yAxis, p, math.clamp((op.radius or 6) / 7, 0.6, 2))
	local strobe = FX.anchor(pos + Vector3.new(0, 3, 0), 1.2)
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Shadows, light.Brightness = glow, 70, false, 20
	light.Parent = strobe
	local prox = math.max(Cam.proximity(pos, 120), 0.25)
	Cam.grade({ tint = glow:Lerp(WHITE, 0.7), brightness = 0.55 * prox, contrast = 0.35 * prox, saturation = -0.5, bloom = 1.4 * prox, attack = 0.015, hold = 0.03, release = 0.3 })
	flicker({ sky }, light, function() shape(sky, top, pos, 0.07) end)
end

function H.nova(op)
	local p = palette(op.style, op.color)
	local r = op.radius or 14
	local g = FX.ground(op.pos + Vector3.new(0, 1, 0), 8)
	local n = g and g.Normal or Vector3.yAxis
	local gp = g and g.Position or op.pos
	local disc = FX.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 2, 2),
		CFrame = FX.alignY(gp + n * 0.3, n) * CFrame.Angles(0, 0, math.pi / 2), Color = p.mid, Transparency = 0.15 })
	FX.tween(disc, 0.45, { Size = Vector3.new(0.4, r * 2, r * 2), Transparency = 1 }, Enum.EasingStyle.Quart)
	Debris:AddItem(disc, 0.5)
	local wall = FX.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 2, 2),
		CFrame = FX.alignY(gp + n * 1.5, n) * CFrame.Angles(0, 0, math.pi / 2), Color = p.edge, Material = FORCEFIELD })
	FX.tween(wall, 0.5, { Size = Vector3.new(4, r * 2.1, r * 2.1), Transparency = 1 }, Enum.EasingStyle.Quart)
	Debris:AddItem(wall, 0.55)
	FX.ring(gp + n * 0.4, n, p.mid, 4, r * 2.4, 0.55)
	task.delay(0.06, function() FX.ring(gp + n * 0.6, n, p.core, 2, r * 1.8, 0.45, 0.2) end)
	FX.pop(gp + n * 1.5, p.core, 2, r * 0.6, 0.25)
	FX.pop(gp + n * 1.5, p.edge, 3, r * 1.2, 0.5, FORCEFIELD)
	local a = FX.anchor(FX.alignY(gp + n, n), 4)
	FX.emitter(a, { Texture = FX.TEX[p.tex] or FX.TEX.sparkle, EmissionDirection = TOP, SpreadAngle = Vector2.new(88, 88),
		Speed = FX.nr(r * 1.5, r * 3), Drag = 4, Lifetime = FX.nr(0.4, 0.9), Size = FX.nseq(0, p.tex == "sparkle" and 0.8 or 3, 1, 0.4),
		Transparency = FX.nseq(0, 0, 0.7, 0.4, 1, 1), Color = FX.cseq(p.core, p.mid, p.edge), LightEmission = 1,
		Rotation = FX.nr(0, 360), Acceleration = Vector3.new(0, -10, 0) }):Emit(70)
	FX.emitter(a, { Texture = FX.TEX.spark, EmissionDirection = TOP, SpreadAngle = Vector2.new(88, 88), Speed = FX.nr(30, 70),
		Drag = 1, Lifetime = FX.nr(0.5, 1.1), Size = FX.nseq(0, 0.45, 1, 0), Color = FX.cseq(p.core, p.mid), LightEmission = 1,
		Acceleration = Vector3.new(0, -40, 0) }):Emit(60)
	if p.scorch then FX.disk(gp + n * 0.03, n, r * 1.2, p.scorch, Enum.Material.SmoothPlastic, 0.2, 2, 1.5) end
	if p.patch then FX.disk(gp + n * 0.03, n, r * 1.6, p.mid, p.patch, 0.2, 2, 1.3) end
	if p.crystal then
		for i = 1, 10 do
			local ang = i / 10 * math.pi * 2
			local out = FX.alignY(gp, n):VectorToWorldSpace(Vector3.new(math.cos(ang), 0, math.sin(ang)))
			spike(gp + out * r * 0.7, (n * 1.6 + out).Unit, FX.rand(2, 4), 0.8, i * 0.015, 0.5, p)
		end
	end
	FX.flashLight(gp + n * 2, p.mid, 12, r * 3, 0.7)
	playSound(p.impact, gp)
	local prox = Cam.shakeAt(gp, 0.7, r * 5)
	if prox > 0 then Cam.grade({ tint = p.mid:Lerp(WHITE, 0.6), brightness = 0.18 * prox, contrast = 0.15 * prox, bloom = 0.8 * prox, release = 0.5 }) end
end

function H.spikes(op)
	local p = palette(op.style or "rock", op.color)
	local count, r, height = op.count or 7, op.radius or 5, op.height or 6
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = FX.characters()
	FX.ring(op.pos + Vector3.new(0, 0.3, 0), Vector3.yAxis, p.mid, 2, r * 3, 0.5)
	for i = 1, count do
		local offset = i == 1 and Vector3.zero or Vector3.new(FX.rand(-r, r), 0, FX.rand(-r, r))
		local base = op.pos + offset
		local hit = workspace:Raycast(base + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0), params)
		if hit then base = hit.Position end
		local tilt = (Vector3.yAxis * 2.2 + offset.Unit * (offset.Magnitude > 0 and 0.5 or 0) + FX.unit() * 0.25).Unit
		spike(base - tilt * 0.6, tilt, height * FX.rand(0.6, 1.15), math.max(0.8, height * 0.22), i * 0.025, 0.9, p)
	end
	local a = FX.anchor(op.pos, 3)
	FX.emitter(a, { Texture = FX.TEX.smoke, EmissionDirection = TOP, SpreadAngle = Vector2.new(80, 80), Speed = FX.nr(4, 10),
		Drag = 2, Lifetime = FX.nr(0.8, 1.4), Size = FX.nseq(0, 2, 1, 6), Transparency = FX.nseq(0, 0.55, 1, 1),
		Color = ColorSequence.new(p.smoke or p.mist or p.dark:Lerp(WHITE, 0.5)) }):Emit(16)
	FX.emitter(a, { Texture = FX.TEX.spark, EmissionDirection = TOP, SpreadAngle = Vector2.new(70, 70), Speed = FX.nr(20, 50),
		Lifetime = FX.nr(0.4, 0.9), Size = FX.nseq(0, 0.4, 1, 0), Color = FX.cseq(p.core, p.mid), LightEmission = 1,
		Acceleration = Vector3.new(0, -50, 0) }):Emit(40)
	FX.flashLight(op.pos + Vector3.new(0, 2, 0), p.mid, 8, 25, 0.6)
	playSound(p.crystal and "glass" or "impact", op.pos)
	FX.sound(FX.SND.collide, op.pos, 0.9, 0.6)
	Cam.shakeAt(op.pos, 0.6, 60)
end

-- Follows a player's root part for `duration`, calling update(cf, t) each frame.
local function follow(userId, duration, update, finish)
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local root = casterRoot(userId)
		local t = os.clock() - start
		if not root or t > duration then
			conn:Disconnect()
			if finish then finish(root) end
			return
		end
		update(root.CFrame, t)
	end)
end

function H.aura(op)
	local p = palette(op.style, op.color)
	local root = casterRoot(op.caster)
	if not root then return end
	local r = op.radius or 6
	local ball = FX.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * r * 0.9, CFrame = root.CFrame, Color = p.mid, Material = FORCEFIELD, Transparency = 0.2 })
	local holder = FX.part({ Size = Vector3.new(r * 0.8, r * 0.9, r * 0.8), CFrame = root.CFrame, Transparency = 1 })
	FX.emitter(holder, { Texture = FX.TEX[p.tex] or FX.TEX.sparkle, Rate = 60, Lifetime = FX.nr(0.6, 1.2), Speed = FX.nr(1, 3),
		SpreadAngle = Vector2.new(20, 20), EmissionDirection = TOP, Size = FX.nseq(0, p.tex == "sparkle" and 0.6 or 1.6, 1, 0),
		Transparency = FX.nseq(0, 0.2, 1, 1), Color = FX.cseq(p.core, p.mid, p.edge), LightEmission = 1,
		Acceleration = Vector3.new(0, 6, 0), Rotation = FX.nr(0, 360) })
	local light = Instance.new("PointLight")
	light.Color, light.Brightness, light.Range, light.Shadows = p.mid, 3, r * 3, false
	light.Parent = holder
	FX.ring(root.Position - Vector3.new(0, 2.8, 0), Vector3.yAxis, p.mid, 2, r * 2.5, 0.6)
	playSound(p.sound, root.Position, 0.7)
	follow(op.caster, op.duration or 3, function(cf, t)
		ball.CFrame = cf
		holder.CFrame = cf
		ball.Size = Vector3.one * r * (0.9 + math.sin(t * 6) * 0.05)
	end, function()
		FX.tween(ball, 0.3, { Transparency = 1 }); Debris:AddItem(ball, 0.35)
		for _, e in ipairs(holder:GetChildren()) do if e:IsA("ParticleEmitter") then e.Enabled = false end end
		Debris:AddItem(holder, 1.5)
	end)
end

function H.shield(op)
	local p = palette(op.style or "holy", op.color)
	local root = casterRoot(op.caster)
	if not root then return end
	local bubble = FX.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2, CFrame = root.CFrame, Color = p.mid, Material = FORCEFIELD })
	local inner = FX.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2, CFrame = root.CFrame, Color = p.core, Transparency = 0.88 })
	FX.tween(bubble, 0.25, { Size = Vector3.one * 9 }, Enum.EasingStyle.Back)
	FX.tween(inner, 0.25, { Size = Vector3.one * 8.6 }, Enum.EasingStyle.Back)
	FX.pop(root.Position, p.core, 2, 10, 0.25)
	FX.sound(FX.SND.ping, root.Position, 0.7, 0.8)
	follow(op.caster, op.duration or 2, function(cf, t)
		bubble.CFrame, inner.CFrame = cf, cf
		inner.Transparency = 0.85 + math.sin(t * 8) * 0.04
	end, function(r)
		local pos = bubble.Position
		FX.pop(pos, p.core, 8, 12, 0.25, nil, 0.4)
		FX.shards(pos, Vector3.yAxis, 10, { color = p.mid, material = GLASS, transparency = 0.3, speed = 25, life = 1, size = 0.5, spread = 2 })
		FX.sound(FX.SND.glass, pos, 0.6, 1.3)
		bubble:Destroy(); inner:Destroy()
	end)
end

function H.heal(op)
	local color = op.color or rgb(110, 255, 150)
	local p = palette(nil, color)
	local root = casterRoot(op.caster)
	if not root then return end
	local feet = root.Position - Vector3.new(0, 2.8, 0)
	FX.ring(feet, Vector3.yAxis, p.mid, 2, 14, 0.6)
	FX.pop(root.Position, p.core, 2, 8, 0.3, nil, 0.3)
	local holder = FX.part({ Size = Vector3.new(4, 5, 4), CFrame = root.CFrame, Transparency = 1 })
	local e = FX.emitter(holder, { Texture = FX.TEX.sparkle, Rate = 70, Lifetime = FX.nr(0.8, 1.3), Speed = FX.nr(2, 5),
		EmissionDirection = TOP, SpreadAngle = Vector2.new(15, 15), Size = FX.nseq(0, 0.7, 1, 0), Color = FX.cseq(p.core, p.mid),
		LightEmission = 1, Acceleration = Vector3.new(0, 4, 0) })
	FX.flashLight(root.Position, p.mid, 6, 20, 1)
	playSound("heal", root.Position)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(120, 40); bb.AlwaysOnTop = true; bb.StudsOffset = Vector3.new(0, 3, 0); bb.Adornee = holder; bb.Parent = holder
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1); label.BackgroundTransparency = 1; label.Font = Enum.Font.GothamBlack; label.TextScaled = true
	label.Text = "+" .. tostring(math.floor(op.amount or 0)); label.TextColor3 = p.mid; label.TextStrokeTransparency = 0.4; label.Parent = bb
	FX.tween(bb, 1.2, { StudsOffset = Vector3.new(0, 6, 0) })
	FX.tween(label, 1.2, { TextTransparency = 1, TextStrokeTransparency = 1 }, nil, nil, 0.3)
	if op.caster == localPlayer.UserId then Cam.grade({ tint = p.mid:Lerp(WHITE, 0.7), brightness = 0.08, release = 0.8 }) end
	follow(op.caster, 1.2, function(cf) holder.CFrame = cf end, function()
		e.Enabled = false
		Debris:AddItem(holder, 1.5)
	end)
end

function H.blink(op)
	local p = palette(op.style, op.color or rgb(150, 200, 255))
	for _, pos in ipairs({ op.from, op.to }) do
		FX.pop(pos, p.core, 2, 7, 0.2)
		FX.pop(pos, p.mid, 3, 10, 0.35, FORCEFIELD)
		local a = FX.anchor(pos, 2)
		FX.emitter(a, { Texture = FX.TEX.sparkle, SpreadAngle = Vector2.new(180, 180), Speed = FX.nr(8, 20), Drag = 3,
			Lifetime = FX.nr(0.3, 0.8), Size = FX.nseq(0, 0.6, 1, 0), Color = FX.cseq(p.core, p.mid), LightEmission = 1 }):Emit(35)
	end
	local len = (op.to - op.from).Magnitude
	if len > 0.5 then
		local streak = FX.part({ Size = Vector3.new(1.2, 1.2, len), CFrame = FX.lookAt((op.from + op.to) / 2, op.to), Color = p.mid, Transparency = 0.2 })
		FX.tween(streak, 0.3, { Size = Vector3.new(0.05, 0.05, len), Transparency = 1 })
		Debris:AddItem(streak, 0.35)
	end
	FX.sound(FX.SND.whoosh, op.to, 0.9, 1.4)
	if op.caster == localPlayer.UserId then Cam.kick("fov", 14, 0.03, 0.05, 0.5) end
end

function H.shake(op)
	if op.pos then Cam.shakeAt(op.pos, op.intensity or 0.5, 90) else Cam.shake(op.intensity or 0.5) end
end

function H.flash(op)
	local prox = op.pos and Cam.proximity(op.pos, 120) or 1
	local k = (op.intensity or 0.5) * prox
	Cam.grade({ tint = (op.color or WHITE):Lerp(WHITE, 0.4), brightness = 0.45 * k, contrast = 0.2 * k, bloom = k, attack = 0.02, hold = 0.05, release = 0.35 })
end

function H.sound(op) playSound(op.name, op.pos) end

function H.ball(op)
	local s = op.size.X
	local part = FX.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * s, CFrame = CFrame.new(op.pos), Color = glow(op.color), Transparency = 1 })
	withLight(part, op.color, s)
	FX.tween(part, 0.12, { Transparency = 0.08 })
	register(op, { part })
end

function H.block(op)
	local part = FX.part({ Size = op.size, CFrame = FX.lookAt(op.pos, op.pos + (op.look or Vector3.zAxis)), Color = glow(op.color), Transparency = 1 })
	withLight(part, op.color, math.max(op.size.X, op.size.Y, op.size.Z))
	FX.tween(part, 0.12, { Transparency = 0.08 })
	register(op, { part })
end

function H.beam(op)
	local len = (op.to - op.from).Magnitude
	local cf = FX.lookAt((op.from + op.to) / 2, op.to)
	local core = FX.part({ Size = Vector3.new(op.width, op.width, len), CFrame = cf, Color = glow(op.color:Lerp(WHITE, 0.25)) })
	local glow = FX.part({ Size = Vector3.new(op.width * 2.4, op.width * 2.4, len), CFrame = cf, Color = op.color, Material = FORCEFIELD })
	withLight(core, op.color, 2)
	register(op, { core, glow })
end

function H.ring(op)
	FX.ring(op.pos, Vector3.yAxis, op.color, op.radius * 0.3, op.radius * 2, op.duration or 0.6)
end

function H.particles(op)
	local a = FX.anchor(op.pos, (op.lifetime or 1) + 1)
	local tex = FX.TEX[PARTICLE_TEX[op.texture] or "sparkle"]
	local speed = op.speed or 15
	FX.emitter(a, { Texture = tex, SpreadAngle = Vector2.new(180, 180), Speed = FX.nr(math.min(speed * 0.4, speed), math.max(speed * 0.4, speed)),
		Drag = 2, Lifetime = FX.nr((op.lifetime or 0.8) * 0.6, op.lifetime or 0.8),
		Size = FX.nseq(0, op.size or 0.6, 1, 0), Transparency = FX.nseq(0, 0, 0.7, 0.3, 1, 1),
		Color = FX.cseq(op.color:Lerp(WHITE, 0.5), op.color), LightEmission = 1, Rotation = FX.nr(0, 360) }):Emit(op.count or 30)
end

function H.light(op) FX.flashLight(op.pos, op.color, 6, op.range or 16, op.duration or 0.6) end

function H.move(op)
	local h = handles[key(op)]
	if not h or not h.parts[1].Parent then return end
	local delta = op.pos - h.parts[1].Position
	for _, part in ipairs(h.parts) do
		local target = part.CFrame + delta
		if (op.t or 0) <= 0 then part.CFrame = target else FX.tween(part, op.t, { CFrame = target }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut) end
	end
end

function H.tween(op)
	local h = handles[key(op)]
	if not h then return end
	local t = op.t or 0.3
	for i, part in ipairs(h.parts) do
		local props = {}
		if op.size and i == 1 then props.Size = part.Shape == Enum.PartType.Ball and Vector3.one * op.size.X or op.size end
		if op.transparency then props.Transparency = op.transparency end
		if next(props) then
			if t <= 0 then for k, v in props do part[k] = v end else FX.tween(part, t, props) end
		end
	end
end

function H.color(op)
	local h = handles[key(op)]
	if not h then return end
	for _, part in ipairs(h.parts) do
		local c = part.Material == NEON and glow(op.color) or op.color
		if (op.t or 0) <= 0 then part.Color = c else FX.tween(part, op.t, { Color = c }) end
		local l = part:FindFirstChildOfClass("PointLight")
		if l then l.Color = op.color end
	end
end

function H.destroy(op) fadeHandle(key(op), 0.15) end

H["end"] = function(op)
	for k, h in handles do
		if h.cast == op.cast and not h.timed then fadeHandle(k, 0.4) end
	end
end

draw.OnClientEvent:Connect(function(op)
	if type(op) ~= "table" then return end
	local handler = H[op.op]
	if not handler then return end
	task.spawn(function()
		local ok, err = pcall(handler, op)
		if not ok then warn("[SpellForge FX] " .. tostring(op.op) .. ": " .. tostring(err)) end
	end)
end)
