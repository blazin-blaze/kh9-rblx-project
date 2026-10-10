-- StarterPlayer.StarterPlayerScripts.DeathBeamFX (LocalScript)
-- Draws every player's ultimate "death beam" locally, every frame, from the attributes that
-- ServerScriptService.VoiceArena.UltimateService publishes on the caster's character:
--   UltimateChanneling (bool), BeamPower (0..1 voice power), BeamRadius (hitbox radius), BeamLength.
-- The beam leaves the caster's chest along the AVATAR's facing and flares out from the hands, so it
-- never starts at (or swallows) the camera. Every layer scales with voice power. Visual only:
-- damage, range and steering are all server-side.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local RANGE = 180
local TAU = math.pi * 2

local C = {
	core = Color3.fromRGB(150, 255, 238),
	bright = Color3.fromRGB(40, 225, 205),
	turq = Color3.fromRGB(0, 128, 122),
	deep = Color3.fromRGB(0, 82, 96),
	haze = Color3.fromRGB(20, 230, 215), -- ForceField shell colour
	shell = Color3.fromRGB(0, 60, 72),
	rock = Color3.fromRGB(58, 64, 68),
}
local SOUND = {
	loop = "rbxassetid://133964855452065",   -- Laser Beam Loop V3
	charge = "rbxassetid://9125974640",      -- energy charge-up
	boom = "rbxassetid://138533090376585",   -- launch boom
	fade = "rbxassetid://9120606857",        -- power-down surge
}
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local fxFolder = Instance.new("Folder")
fxFolder.Name = "DeathBeamFX"
fxFolder.Parent = workspace

local function new(class, props)
	local inst = Instance.new(class)
	for k, v in props do if k ~= "Parent" then inst[k] = v end end
	if props.Parent then inst.Parent = props.Parent end
	return inst
end
local function tween(inst, t, props, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end
local function lerp(a, b, t) return a + (b - a) * t end
local function fxPart(shape, color, transparency, material, parent)
	return new("Part", { Shape = shape or Enum.PartType.Block, Color = color, Transparency = transparency or 0,
		Material = material or Enum.Material.Neon, Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		CastShadow = false, Size = Vector3.one * 0.2, Parent = parent or fxFolder })
end
local function look(pos, dir) -- CFrame at pos facing dir, safe for straight up/down
	local up = math.abs(dir.Y) > 0.95 and Vector3.xAxis or Vector3.yAxis
	return CFrame.lookAt(pos, pos + dir, up)
end
local function along(center, dir) -- cylinder parts run along their X axis
	return look(center, dir) * CFrame.Angles(0, math.pi / 2, 0)
end
local function flatten(v)
	v = Vector3.new(v.X, 0, v.Z)
	return v.Magnitude > 1e-3 and v.Unit or Vector3.new(0, 0, -1)
end
local function basis(dir)
	local right = dir:Cross(Vector3.yAxis)
	right = right.Magnitude > 1e-3 and right.Unit or Vector3.xAxis
	return right, right:Cross(dir).Unit
end
local function sound(id, parent, volume, speed, looped)
	local s = new("Sound", { SoundId = id, Volume = volume or 1, PlaybackSpeed = speed or 1, Looped = looped or false,
		RollOffMaxDistance = 400, RollOffMinDistance = 18, Parent = parent })
	s:Play()
	if not looped then Debris:AddItem(s, 8) end
	return s
end
local function soundAt(id, position, volume, speed)
	local holder = fxPart(Enum.PartType.Block, C.core, 1)
	holder.Position = position
	sound(id, holder, volume, speed)
	Debris:AddItem(holder, 6)
end

---------------------------------------------------------------- ray helpers
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
local function humanoidModel(part)
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then return model end
		model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model")
	end
end
local function baseIgnore(caster)
	local ignore = { fxFolder, caster }
	local effects = workspace:FindFirstChild("VoiceArenaEffects")
	if effects then table.insert(ignore, effects) end
	return ignore
end
-- Same rule as the server: the beam passes through characters and stops at the first solid wall.
local function castBeam(origin, dir, caster)
	local ignore = baseIgnore(caster)
	for _ = 1, 6 do
		rayParams.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(origin, dir * RANGE, rayParams)
		if not hit then return RANGE, nil end
		local model = humanoidModel(hit.Instance)
		if not model then return hit.Distance, hit end
		table.insert(ignore, model)
	end
	return RANGE, nil
end
local function groundBelow(root, caster)
	rayParams.FilterDescendantsInstances = baseIgnore(caster)
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), rayParams)
	return hit and hit.Position
end

---------------------------------------------------------------- beam layers
-- A layer is a long cylinder plus a stretched-sphere "nose" whose back half tapers smoothly from a
-- point at the hands out to full width `flare` studs later (no stepped discs).
local function newLayer(color, transparency, parent, material)
	local layer = { main = fxPart(Enum.PartType.Cylinder, color, transparency, material, parent) }
	layer.nose = fxPart(Enum.PartType.Block, color, transparency, material, parent)
	new("SpecialMesh", { MeshType = Enum.MeshType.Sphere, Parent = layer.nose })
	return layer
end
local function layerParts(layer)
	return { layer.main, layer.nose }
end
local function placeLayer(layer, origin, dir, length, flare, radius, transparency)
	flare = math.min(flare, length)
	local width = radius * 2
	layer.nose.Size = Vector3.new(width, width, math.max(flare * 2, 0.1))
	layer.nose.CFrame = look(origin + dir * flare, dir)
	layer.nose.Transparency = transparency
	local rest = length - flare
	layer.main.Size = Vector3.new(math.max(rest, 0.05), width, width)
	layer.main.CFrame = along(origin + dir * (flare + rest / 2), dir)
	layer.main.Transparency = rest > 0.05 and transparency or 1
end

-- The outer glow is camera-facing Beams with a scrolling smoke texture: soft edges, a smooth taper
-- from the hands, and energy that visibly flows down the beam.
local function newHaze(folder)
	local holder = fxPart(Enum.PartType.Block, C.core, 1, nil, folder)
	holder.CFrame = CFrame.new()
	local h = { holder = holder, beams = {} }
	h.a0 = new("Attachment", { Parent = holder })
	h.a1 = new("Attachment", { Parent = holder })
	h.a2 = new("Attachment", { Parent = holder })
	for _, spec in ipairs({
		{ width = 2.9, speed = 1.4, color = C.turq, transparency = 0.1 },
		{ width = 2.0, speed = -3, color = C.bright, transparency = 0 },
	}) do
		for seg = 1, 2 do
			local b = new("Beam", { Attachment0 = seg == 1 and h.a0 or h.a1, Attachment1 = seg == 1 and h.a1 or h.a2,
				Texture = SMOKE, TextureMode = Enum.TextureMode.Wrap, TextureSpeed = spec.speed, LightEmission = 1,
				LightInfluence = 0, Color = ColorSequence.new(spec.color), Transparency = NumberSequence.new(spec.transparency),
				FaceCamera = true, Segments = 1, Parent = holder })
			table.insert(h.beams, { beam = b, spec = spec, seg = seg })
		end
	end
	return h
end
local function placeHaze(h, origin, dir, length, flare, r, fade)
	flare = math.min(flare, length)
	h.a0.Position = origin
	h.a1.Position = origin + dir * flare
	h.a2.Position = origin + dir * length
	for _, item in ipairs(h.beams) do
		local w = r * item.spec.width
		local b = item.beam
		b.Width0 = item.seg == 1 and w * 0.1 or w
		b.Width1 = w
		b.TextureLength = math.max(w * 1.2, 1)
		b.Transparency = NumberSequence.new(lerp(item.spec.transparency, 1, fade))
	end
end

---------------------------------------------------------------- one beam
local beams = {}

local function makeBeam(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local folder = new("Folder", { Name = character.Name, Parent = fxFolder })
	local st = { character = character, root = root, folder = folder, t0 = os.clock(), power = 0, radius = 0.4, extend = 0,
		pulses = {}, nextPulse = 0, nextArc = 0, nextRing = 0, nextMark = 0, nextRock = 0, nextGround = 0,
		isLocal = character == player.Character }
	st.haze = newHaze(folder)
	st.body = newLayer(C.turq, 0.45, folder)
	st.core = newLayer(C.core, 0.05, folder)
	st.muzzle = fxPart(Enum.PartType.Ball, C.bright, 0, nil, folder)
	st.muzzleGlow = fxPart(Enum.PartType.Ball, C.haze, 0.2, Enum.Material.ForceField, folder)
	st.tip = fxPart(Enum.PartType.Ball, C.bright, 0, nil, folder)
	st.tipGlow = fxPart(Enum.PartType.Ball, C.haze, 0.2, Enum.Material.ForceField, folder)
	st.ground = fxPart(Enum.PartType.Cylinder, C.haze, 1, Enum.Material.ForceField, folder)
	st.light = new("PointLight", { Color = C.bright, Range = 16, Brightness = 2, Shadows = false, Parent = st.muzzle })
	st.tipLight = new("PointLight", { Color = C.bright, Range = 20, Brightness = 3, Shadows = false, Parent = st.tip })

	-- two counter-spinning rune circles around the hands
	st.circles = {}
	for c, spec in ipairs({ { n = 32, speed = 2.4, scale = 1, at = 0.12 }, { n = 22, speed = -3.6, scale = 0.62, at = 0.55 } }) do
		local ring = { spec = spec, blocks = {} }
		for k = 1, spec.n do ring.blocks[k] = fxPart(Enum.PartType.Block, k % 3 == 0 and C.core or C.bright, 0.1, nil, folder) end
		st.circles[c] = ring
	end
	-- twin energy helices wound around the beam, racing outward
	st.helix = {}
	for strand = 1, 2 do
		for k = 1, 14 do
			table.insert(st.helix, { part = fxPart(Enum.PartType.Block, C.core, 0.2, nil, folder), strand = strand, k = k })
		end
	end

	st.beamSparks = new("ParticleEmitter", { Texture = SPARK, Color = ColorSequence.new(C.core, C.bright), LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.25, 0.55), Speed = NumberRange.new(3, 10), SpreadAngle = Vector2.new(180, 180),
		Drag = 4, Rate = 0, Parent = st.body.main })
	local muzzleAtt = new("Attachment", { Parent = st.muzzle })
	st.muzzleSparks = new("ParticleEmitter", { Texture = SPARK, Color = ColorSequence.new(C.core, C.turq), LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.15, 0.35), Speed = NumberRange.new(18, 42), SpreadAngle = Vector2.new(40, 40),
		EmissionDirection = Enum.NormalId.Front, Drag = 3, Rate = 0, Parent = muzzleAtt })
	local tipAtt = new("Attachment", { Parent = st.tip })
	st.tipSparks = new("ParticleEmitter", { Texture = SPARK, Color = ColorSequence.new(C.core, C.bright), LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.35, 0.8), Speed = NumberRange.new(25, 70), SpreadAngle = Vector2.new(75, 75),
		Acceleration = Vector3.new(0, -70, 0), EmissionDirection = Enum.NormalId.Front, Drag = 1.5, Rate = 0, Parent = tipAtt })
	st.tipSmoke = new("ParticleEmitter", { Texture = SMOKE, Color = ColorSequence.new(C.turq, C.haze), LightEmission = 0.6,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 9) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(6, 16), SpreadAngle = Vector2.new(60, 60),
		RotSpeed = NumberRange.new(-90, 90), Rotation = NumberRange.new(0, 360), EmissionDirection = Enum.NormalId.Front,
		Rate = 0, Parent = tipAtt })
	st.auraAtt = new("Attachment", { Name = "DeathBeamAura", Position = Vector3.new(0, -2.6, 0), Parent = root })
	st.aura = new("ParticleEmitter", { Texture = SPARK, Color = ColorSequence.new(C.bright, C.turq), LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(6, 14), SpreadAngle = Vector2.new(25, 25),
		EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, 8, 0), Rate = 0, Parent = st.auraAtt })
	st.highlight = new("Highlight", { Adornee = character, FillColor = C.turq, FillTransparency = 0.85, OutlineColor = C.bright,
		OutlineTransparency = 0.15, DepthMode = Enum.HighlightDepthMode.Occluded, Parent = folder })

	st.loop = sound(SOUND.loop, st.muzzle, 0.45, 0.85, true)
	st.roar = sound(SOUND.loop, st.tip, 0, 0.55, true)
	sound(SOUND.charge, st.muzzle, 0.9, 1)
	sound(SOUND.boom, st.muzzle, 0.8, 0.8)
	return st
end

-- Launch: a shockwave across the floor, light rushing into the hands, then a flash.
local function startBurst(st, origin, dir, groundPos)
	if groundPos then
		local ring = fxPart(Enum.PartType.Cylinder, C.bright, 0.35)
		ring.Size = Vector3.new(0.3, 4, 4)
		ring.CFrame = CFrame.new(groundPos + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		tween(ring, 0.8, { Size = Vector3.new(0.3, 70, 70), Transparency = 1 }, Enum.EasingStyle.Quart)
		Debris:AddItem(ring, 0.9)
	end
	local right, up = basis(dir)
	for k = 1, 16 do
		local a = k / 16 * TAU
		local spark = fxPart(Enum.PartType.Ball, C.core, 0)
		spark.Size = Vector3.one * 0.6
		spark.Position = origin + (right * math.cos(a) + up * math.sin(a)) * 9 + dir * 3
		tween(spark, 0.28, { Position = origin, Size = Vector3.one * 0.1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(spark, 0.3)
	end
	local flash = fxPart(Enum.PartType.Ball, C.core, 0)
	flash.Size = Vector3.one * 2
	flash.Position = origin + dir
	tween(flash, 0.45, { Size = Vector3.one * 14, Transparency = 1 }, Enum.EasingStyle.Quart)
	Debris:AddItem(flash, 0.5)
end

-- Power-down: every layer pinches to a thread and vanishes.
local function collapse(st)
	for _, item in ipairs(st.haze.beams) do tween(item.beam, 0.3, { Width0 = 0, Width1 = 0 }, Enum.EasingStyle.Quart, Enum.EasingDirection.In) end
	for _, layer in ipairs({ st.body, st.core }) do
		local main, nose = layer.main, layer.nose
		tween(main, 0.3, { Size = Vector3.new(main.Size.X, 0.05, 0.05), Transparency = 1 }, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
		tween(nose, 0.3, { Size = Vector3.new(0.05, 0.05, nose.Size.Z), Transparency = 1 }, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
	end
	for _, p in ipairs({ st.muzzle, st.muzzleGlow, st.tip, st.tipGlow, st.ground }) do
		tween(p, 0.3, { Transparency = 1, Size = Vector3.one * 0.1 })
	end
	for _, ring in ipairs(st.circles) do for _, b in ipairs(ring.blocks) do tween(b, 0.3, { Transparency = 1 }) end end
	for _, h in ipairs(st.helix) do tween(h.part, 0.2, { Transparency = 1 }) end
	for _, e in ipairs({ st.beamSparks, st.muzzleSparks, st.tipSparks, st.tipSmoke, st.aura }) do e.Rate = 0 end
	tween(st.loop, 0.35, { Volume = 0 })
	tween(st.roar, 0.35, { Volume = 0 })
	tween(st.highlight, 0.4, { FillTransparency = 1, OutlineTransparency = 1 })
	if st.lastOrigin then
		soundAt(SOUND.fade, st.lastOrigin, 0.6, 1.1)
		local pop = fxPart(Enum.PartType.Ball, C.core, 0.2)
		pop.Size = Vector3.one * 1.5
		pop.Position = st.lastOrigin
		tween(pop, 0.35, { Size = Vector3.one * 9, Transparency = 1 }, Enum.EasingStyle.Quart)
		Debris:AddItem(pop, 0.4)
	end
	task.delay(0.6, function()
		st.folder:Destroy()
		if st.auraAtt then st.auraAtt:Destroy() end
	end)
end

-- Returns how hard this beam should shake / grade / widen the local camera.
local function update(st, dt, now)
	local character, root = st.character, st.root
	st.power = lerp(st.power, character:GetAttribute("BeamPower") or 0, 1 - math.exp(-dt * 10))
	st.radius = lerp(st.radius, character:GetAttribute("BeamRadius") or 0.4, 1 - math.exp(-dt * 10))
	st.extend = math.min(1, st.extend + dt / 0.18)
	local p = st.power
	local r = math.max(st.radius, 0.35)
	local t = now - st.t0
	local flicker = 1 + 0.07 * math.sin(t * 61) + 0.05 * math.sin(t * 37.3)

	local dir = flatten(root.CFrame.LookVector)
	local origin = root.Position + Vector3.new(0, 0.6, 0) + dir * 2.2
	local fullLength, hit = castBeam(origin, dir, character)
	local length = math.max(0.1, fullLength * st.extend)
	local blocked = hit ~= nil and st.extend >= 1
	local endpoint = origin + dir * length
	local flare = math.clamp(r * 2.6, 1.5, 32)
	local right, up = basis(dir)
	st.lastOrigin = origin
	if now >= st.nextGround then
		st.nextGround = now + 0.25
		st.groundPos = groundBelow(root, character)
	end
	if not st.started then
		st.started = true
		startBurst(st, origin, dir, st.groundPos)
	end

	-- If a camera ends up inside the beam (a victim, or the caster turning toward their own camera),
	-- thin the big layers for that viewer so it never blankets the screen.
	local camera = workspace.CurrentCamera
	local inside, near = 0, 0
	if camera then
		local rel = camera.CFrame.Position - origin
		local a = rel:Dot(dir)
		if a > -3 and a < length + 3 then
			local axis = (rel - dir * a).Magnitude
			inside = math.clamp(1 - (axis - r * 1.4) / (r * 0.8 + 3), 0, 1)
			near = math.clamp(1 - axis / 60, 0, 1)
		else
			near = math.clamp(1 - rel.Magnitude / 60, 0, 1)
		end
	end

	placeHaze(st.haze, origin, dir, length, flare, r * flicker, math.clamp(inside + (1 - p) * 0.25, 0, 1))
	placeLayer(st.body, origin, dir, length, flare, r * 0.8 * flicker, lerp(0.55 - 0.2 * p, 0.95, inside))
	placeLayer(st.core, origin, dir, length, flare, r * 0.34 * (2 - flicker), lerp(0.1, 0.75, inside))

	-- hands: hot core, glow, light
	local muzzleSize = math.min(1 + r * 0.45, 5) * flicker
	st.muzzle.Size = Vector3.one * muzzleSize * 0.55
	st.muzzle.CFrame = look(origin, dir)
	st.muzzleGlow.Size = Vector3.one * muzzleSize
	st.muzzleGlow.Position = origin + dir * muzzleSize * 0.3
	st.muzzleGlow.Transparency = lerp(0.35 - 0.2 * p, 1, inside)
	st.light.Range = 10 + 40 * p
	st.light.Brightness = 1.5 + 5 * p

	-- rune circles
	for _, ring in ipairs(st.circles) do
		local spec = ring.spec
		local R = (1.2 + r * 0.62) * spec.scale
		local center = origin + dir * (spec.at * flare + 0.6)
		local bs = 0.1 + R * 0.025
		for k, b in ipairs(ring.blocks) do
			local a = k / spec.n * TAU + t * spec.speed
			local radial = right * math.cos(a) + up * math.sin(a)
			local tangent = -right * math.sin(a) + up * math.cos(a)
			local pos = center + radial * R
			b.Size = Vector3.new(bs, bs, R * TAU / spec.n * 0.7)
			b.CFrame = CFrame.lookAt(pos, pos + tangent, dir)
			b.Transparency = lerp(0.3 + 0.4 * (1 - p), 1, inside * 0.6)
		end
	end

	-- helices
	local helixR = r + 0.3
	local hs = 0.2 + r * 0.035
	for _, h in ipairs(st.helix) do
		local frac = ((h.k - 1) / 14 + t * 0.7) % 1
		local d = flare * 0.6 + frac * math.max(length - flare * 0.6, 0)
		local a = d * 0.3 + t * 7 + (h.strand - 1) * math.pi
		local radial = right * math.cos(a) + up * math.sin(a)
		local tangent = (-right * math.sin(a) + up * math.cos(a)) * helixR * 0.3 + dir -- d(position)/d(distance)
		local pos = origin + dir * d + radial * helixR
		h.part.Size = Vector3.new(hs, hs, 1 + r * 0.55)
		h.part.CFrame = CFrame.lookAt(pos, pos + tangent)
		h.part.Transparency = lerp(0.15 + 0.5 * (1 - p) + 0.35 * frac ^ 3, 1, inside)
	end

	-- shock pulses racing down the beam
	if st.extend >= 1 and now >= st.nextPulse then
		st.nextPulse = now + lerp(0.16, 0.07, p)
		table.insert(st.pulses, { part = fxPart(Enum.PartType.Cylinder, C.haze, 0.2, Enum.Material.ForceField, st.folder), d = flare })
	end
	for i = #st.pulses, 1, -1 do
		local pulse = st.pulses[i]
		pulse.d += dt * (160 + 120 * p)
		if pulse.d > length then
			pulse.part:Destroy()
			table.remove(st.pulses, i)
		else
			local w = r * 2 * 1.35
			pulse.part.Size = Vector3.new(0.6 + r * 0.25, w, w)
			pulse.part.CFrame = along(origin + dir * pulse.d, dir)
			pulse.part.Transparency = lerp(0.2 + 0.7 * (pulse.d / length), 1, inside)
		end
	end

	-- lightning crackling off the beam once it's strong
	if p > 0.4 and st.extend >= 1 and now >= st.nextArc then
		st.nextArc = now + lerp(0.12, 0.03, math.clamp((p - 0.4) / 0.6, 0, 1))
		for _ = 1, (p > 0.8 and 2 or 1) do
			local a = math.random() * TAU
			local radial = right * math.cos(a) + up * math.sin(a)
			local point = origin + dir * (math.random() * length) + radial * r * 0.8
			for _ = 1, math.random(3, 5) do
				local jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * (1 + r * 0.3)
				local nextPoint = point + radial * (0.8 + r * 0.25) * math.random() + dir * (math.random() - 0.5) * (2 + r) + jitter
				local seg = fxPart(Enum.PartType.Block, C.core, 0, nil, st.folder)
				seg.Size = Vector3.new(0.1 + r * 0.012, 0.1 + r * 0.012, (nextPoint - point).Magnitude)
				seg.CFrame = CFrame.lookAt((point + nextPoint) / 2, nextPoint)
				Debris:AddItem(seg, 0.06 + math.random() * 0.05)
				point = nextPoint
			end
		end
	end

	-- impact
	local normal = hit and hit.Normal or -dir
	local tipSize = blocked and math.min(1.5 + r * 1.4, 16) or math.min(1 + r * 0.8, 8)
	st.tip.Size = Vector3.one * tipSize * 0.6 * flicker
	st.tip.CFrame = look(endpoint, normal)
	st.tip.Transparency = blocked and lerp(0, 0.8, inside) or 0.35
	st.tipGlow.Size = Vector3.one * tipSize * 1.05 * (2 - flicker)
	st.tipGlow.Position = endpoint
	st.tipGlow.Transparency = lerp(blocked and 0.15 or 0.6, 1, inside)
	st.tipLight.Range = blocked and (14 + 46 * p) or 8
	st.tipLight.Brightness = blocked and (2 + 6 * p) or 1
	st.tipSparks.Rate = blocked and (40 + 260 * p) or 0
	st.tipSmoke.Rate = blocked and (6 + 30 * p) or 0
	st.roar.Volume = blocked and (0.15 + 0.5 * p) or 0
	if blocked and now >= st.nextRing then
		st.nextRing = now + lerp(0.35, 0.15, p)
		local ring = fxPart(Enum.PartType.Cylinder, C.bright, 0.3, nil, st.folder)
		ring.Size = Vector3.new(0.2, 1, 1)
		ring.CFrame = along(endpoint + normal * 0.2, normal)
		tween(ring, 0.5, { Size = Vector3.new(0.2, r * 5 + 8, r * 5 + 8), Transparency = 1 }, Enum.EasingStyle.Quart)
		Debris:AddItem(ring, 0.55)
	end
	-- glowing scorch marks trail across whatever the beam sweeps over
	if blocked and now >= st.nextMark then
		st.nextMark = now + 0.08
		local w = r * 1.5 + 1
		local mark = fxPart(Enum.PartType.Cylinder, C.bright, 0.25)
		mark.Size = Vector3.new(0.12, w, w)
		mark.CFrame = along(endpoint + normal * 0.06, normal)
		tween(mark, 0.4, { Color = C.deep })
		task.delay(0.4, function()
			if mark.Parent then tween(mark, 2.6, { Transparency = 1, Color = C.haze, Size = Vector3.new(0.12, w * 0.6, w * 0.6) }) end
		end)
		Debris:AddItem(mark, 3.2)
	end

	-- caster: aura, highlight, glowing ground sigil, rocks torn up by the power
	local ground = st.groundPos
	if ground then
		local w = 6 + 10 * p + math.sin(t * 9) * 0.6
		st.ground.Size = Vector3.new(0.3, w, w)
		st.ground.CFrame = CFrame.new(ground + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, t * 0.8, math.pi / 2)
		st.ground.Transparency = 0.5 - 0.3 * p
	else
		st.ground.Transparency = 1
	end
	if ground and p > 0.3 and now >= st.nextRock then
		st.nextRock = now + lerp(0.3, 0.06, math.clamp((p - 0.3) / 0.7, 0, 1))
		local side = math.random() < 0.5 and 1 or -1
		local a = math.atan2(dir.Z, dir.X) + side * (0.25 + math.random() * 1.45)
		local dist = 4 + math.random() * (3 + 5 * p)
		local s = 0.35 + math.random() * (0.4 + 0.7 * p)
		local rock = fxPart(Enum.PartType.Block, C.rock, 0, Enum.Material.Slate, st.folder)
		rock.Size = Vector3.new(s, s * (0.6 + math.random() * 0.6), s)
		local start = CFrame.new(ground + Vector3.new(math.cos(a) * dist, 0, math.sin(a) * dist)) * CFrame.Angles(math.random() * TAU, math.random() * TAU, 0)
		rock.CFrame = start
		tween(rock, 1.3, { CFrame = CFrame.new(0, 3 + math.random() * 6 * p, 0) * start * CFrame.Angles(math.random() * 3, math.random() * 3, 0) }, Enum.EasingStyle.Sine)
		task.delay(1.0, function() if rock.Parent then tween(rock, 0.3, { Transparency = 1 }) end end)
		Debris:AddItem(rock, 1.4)
	end
	st.highlight.FillTransparency = 0.85 - 0.25 * p
	st.beamSparks.Rate = st.extend >= 1 and math.min(20 + length * r * 0.25 * (0.3 + p), 500) or 0
	st.muzzleSparks.Rate = 30 + 220 * p
	st.aura.Rate = 15 + 110 * p
	st.loop.Volume = 0.35 + 0.6 * p
	st.loop.PlaybackSpeed = 0.8 + 0.4 * p

	local kick = t < 0.35 and (0.35 - t) * 3 or 0
	local shake = (st.isLocal and 1 or near) * (0.12 + 0.88 * p ^ 1.3) + kick
	local grade = st.isLocal and p or math.max(inside, near * 0.5) * p
	local fov = st.isLocal and (3 + 9 * p) or 0
	return shake, grade, fov
end

---------------------------------------------------------------- camera: shake, FOV push, turquoise grade
local shake, fovBoost, baseFov = 0, 0, nil
local grade = Lighting:FindFirstChild("DeathBeamGrade")
if grade then grade:Destroy() end
grade = new("ColorCorrectionEffect", { Name = "DeathBeamGrade", Enabled = false, Parent = Lighting })
local TINT = Color3.fromRGB(196, 255, 246)

RunService:BindToRenderStep("DeathBeamShake", Enum.RenderPriority.Camera.Value + 1, function()
	local camera = workspace.CurrentCamera
	if not camera or shake < 0.002 then return end
	local t = os.clock()
	local s = math.min(shake, 1.6)
	camera.CFrame = camera.CFrame
		* CFrame.new(math.noise(t * 18, 1) * 0.35 * s, math.noise(t * 18, 2) * 0.35 * s, 0)
		* CFrame.Angles(math.noise(t * 22, 3) * 0.012 * s, math.noise(t * 22, 4) * 0.012 * s, math.noise(t * 15, 5) * 0.02 * s)
end)

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	for _, plr in ipairs(Players:GetPlayers()) do
		local character = plr.Character
		if character and character:GetAttribute("UltimateChanneling") and not beams[character] then
			local st = makeBeam(character)
			if st then beams[character] = st end
		end
	end
	local shakeTarget, gradeTarget, fovTarget = 0, 0, 0
	for character, st in beams do
		if character.Parent and st.root.Parent and character:GetAttribute("UltimateChanneling") then
			local ok, s, g, f = pcall(update, st, dt, now)
			if ok then
				shakeTarget = math.max(shakeTarget, s)
				gradeTarget = math.max(gradeTarget, g)
				fovTarget = math.max(fovTarget, f)
			else
				warn("[DeathBeamFX] " .. tostring(s))
				beams[character] = nil
				pcall(collapse, st)
			end
		else
			beams[character] = nil
			pcall(collapse, st)
		end
	end
	local k = 1 - math.exp(-dt * 8)
	shake = lerp(shake, shakeTarget, k)
	fovBoost = lerp(fovBoost, fovTarget, k)
	local g = lerp(grade.Enabled and grade.Contrast / 0.15 or 0, gradeTarget, k)
	grade.Enabled = g > 0.01
	grade.Contrast = 0.15 * g
	grade.Saturation = 0.2 * g
	grade.Brightness = 0.03 * g
	grade.TintColor = Color3.new(1, 1, 1):Lerp(TINT, g)
	local camera = workspace.CurrentCamera
	if camera then
		if fovBoost > 0.05 then
			baseFov = baseFov or camera.FieldOfView
			camera.FieldOfView = baseFov + fovBoost
		elseif baseFov then
			camera.FieldOfView = baseFov
			baseFov = nil
		end
	end
end)
