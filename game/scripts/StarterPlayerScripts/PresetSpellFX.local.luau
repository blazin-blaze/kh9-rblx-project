-- StarterPlayer.StarterPlayerScripts.PresetSpellFX (LocalScript)
-- Cinematic visuals, sound and camera work for the preset spells (Flame, Freeze, Wave).
-- The server (ServerScriptService.VoiceArena.SpellService) owns all gameplay and fires
-- ReplicatedStorage.VoiceArena.PresetFx; this script only draws.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")

local forge = script.Parent:WaitForChild("SpellForgeClient")
local FX = require(forge:WaitForChild("FXUtil"))
local Cam = require(forge:WaitForChild("CameraFX"))
local localPlayer = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("VoiceArena"):WaitForChild("PresetFx")

local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local NEON, GLASS, FORCEFIELD = Enum.Material.Neon, Enum.Material.Glass, Enum.Material.ForceField
local TOP = Enum.NormalId.Top
local BALL, CYL = Enum.PartType.Ball, Enum.PartType.Cylinder
local BACK, OUT = Enum.EasingStyle.Back, Enum.EasingDirection.Out

---------------------------------------------------------------- sound
local SFX = {
	fireCast = 7106659874, fireBlast = 2741718865, fireTravel = 9114428742, fireBoom = 139900006476219,
	fireImpact = 139321522575273, boom = 138533090376585, fireLoop = 134764135613302, flameDash = 86457257192248,
	-- Ice foley courtesy of Pro Sound Effects: block cracks and ice shattering.
	iceCast = 9114858588, iceCrackle = 9114858583, iceShatter = 9114855870,
	surge1 = 9120606857, surge3 = 9120607089, waveLoop = 135677767817157, poolSplash = 9117822527,
	splash5 = 9119482201, splash1 = 9119481909, slam = 91288569991875, summon = 99963459517796,
}
for k, v in SFX do SFX[k] = "rbxassetid://" .. v end
task.spawn(function()
	local list = {}
	for _, id in SFX do local s = Instance.new("Sound"); s.SoundId = id; table.insert(list, s) end
	pcall(function() ContentProvider:PreloadAsync(list) end)
end)

local function play(id, where, volume, speed, opts)
	opts = opts or {}
	local life = opts.life or 8
	local parent = where
	if typeof(where) == "Vector3" then parent = FX.anchor(where, life) end
	if not parent then return nil end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 1
	s.PlaybackSpeed = speed or 1
	s.RollOffMinDistance = opts.near or 25
	s.RollOffMaxDistance = opts.far or 600
	s.Looped = opts.loop == true
	s.Parent = parent
	if opts.start then s.TimePosition = opts.start end
	s:Play()
	if not opts.loop then Debris:AddItem(s, life) end
	return s
end
local function fadeSound(s, t)
	if s and s.Parent then FX.tween(s, t, { Volume = 0 }); Debris:AddItem(s, t + 0.05) end
end

local function isLocal(userId) return userId == localPlayer.UserId end
local function rootOf(model) return model and model:FindFirstChild("HumanoidRootPart") end
local function bodyParts(model)
	local list = {}
	if not model then return list end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 0.9 and d.Size.Magnitude < 8
			and not d:FindFirstAncestorWhichIsA("Accessory") then
			table.insert(list, d)
		end
	end
	return list
end

local function addTrail(part, halfWidth, lifetime, color, transparency)
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, halfWidth, 0); a0.Parent = part
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -halfWidth, 0); a1.Parent = part
	local t = Instance.new("Trail")
	t.Attachment0, t.Attachment1 = a0, a1
	t.Lifetime = lifetime
	t.Color = color
	t.Transparency = transparency or FX.nseq(0, 0.05, 1, 1)
	t.WidthScale = FX.nseq(0, 1, 1, 0)
	t.LightEmission = 1
	t.LightInfluence = 0
	t.FaceCamera = true
	t.MinLength = 0.05
	t.Parent = part
	return t
end

-- Floor under a point, skipping every character/NPC (including the one standing there).
local function groundHit(pos, depth, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = FX.characters()
	if ignore then table.insert(list, ignore) end
	params.FilterDescendantsInstances = list
	for _ = 1, 4 do
		local hit = workspace:Raycast(pos + Vector3.new(0, 1, 0), Vector3.new(0, -(depth or 10), 0), params)
		if not hit then return nil end
		local model = hit.Instance:FindFirstAncestorWhichIsA("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then
			table.insert(list, model)
			params.FilterDescendantsInstances = list
		else
			return hit
		end
	end
	return nil
end

-- Thin glowing cracks radiating across the floor.
local function cracks(pos, normal, color, count, minLen, maxLen, fadeDelay)
	local basis = FX.alignY(pos, normal)
	for i = 1, count do
		local ang = (i / count) * math.pi * 2 + FX.rand(-0.3, 0.3)
		local out = basis:VectorToWorldSpace(Vector3.new(math.cos(ang), 0, math.sin(ang)))
		local len = FX.rand(minLen, maxLen)
		local mid = pos + out * (len / 2 + 0.6) + normal * 0.05
		local crack = FX.part({ Size = Vector3.new(FX.rand(0.18, 0.35), 0.05, len), CFrame = CFrame.lookAt(mid, mid + out, normal), Color = color })
		FX.tween(crack, 1.2, { Transparency = 1, Size = Vector3.new(0.05, 0.05, len) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, fadeDelay or 0.4)
		Debris:AddItem(crack, (fadeDelay or 0.4) + 1.3)
	end
end

---------------------------------------------------------------- shared projectile flight
local flights = {}
RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for key, st in flights do
		local t = now - st.start
		if not st.parked then
			local target = st.from + st.dir * st.speed * t
			if (target - st.from).Magnitude >= st.range then target = st.from + st.dir * st.range; st.parked = now end
			local move = target - st.pos
			if move.Magnitude > 1e-3 then
				local hit = workspace:Spherecast(st.pos, 0.8, move, st.params)
				if hit then target = hit.Position; st.parked = now end
			end
			st.pos = target
		end
		st.update(st, now, t)
		if (st.parked and now - st.parked > 0.5) or t > 4 then
			flights[key] = nil
			st.retire(st)
		end
	end
end)

local function startFlight(key, op, state)
	local casterPlayer = Players:GetPlayerByUserId(op.caster or 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { FX.folder, casterPlayer and casterPlayer.Character }
	state.from, state.dir, state.speed, state.range = op.from, op.dir, op.speed or 90, op.range or 110
	state.pos, state.start, state.params = op.from, os.clock(), params
	flights[key] = state
end
local function endFlight(key)
	local st = flights[key]
	if st then flights[key] = nil; st.retire(st) end
end

---------------------------------------------------------------- FLAME
local F = {
	hot = rgb(255, 250, 230), yellow = rgb(255, 205, 70), orange = rgb(255, 125, 25), red = rgb(220, 45, 10),
	ember = rgb(255, 150, 40), smoke = rgb(70, 60, 55), smokeDark = rgb(35, 30, 28), char = rgb(22, 16, 14),
}
local FIRE_SEQ = FX.cseq(F.hot, F.yellow, F.orange, F.red)

local function fireEmitter(parent, rate, size, extra)
	local props = {
		Texture = FX.TEX.fire, Rate = rate, Lifetime = FX.nr(0.25, 0.55), Speed = FX.nr(1, 4),
		SpreadAngle = Vector2.new(180, 180), Size = FX.nseq(0, size, 0.5, size * 0.65, 1, size * 0.08),
		Transparency = FX.nseq(0, 0.05, 0.6, 0.35, 1, 1), Color = FIRE_SEQ, LightEmission = 1,
		Rotation = FX.nr(0, 360), RotSpeed = FX.nr(-250, 250), Drag = 4, ZOffset = 0.5,
	}
	for k, v in extra or {} do props[k] = v end
	return FX.emitter(parent, props)
end

local function burningChunk(pos, dir, speed)
	local p = FX.part({ Anchored = false, CanCollide = true, Material = Enum.Material.Basalt, Color = rgb(55, 32, 22),
		Size = Vector3.new(FX.rand(0.5, 1.1), FX.rand(0.4, 0.9), FX.rand(0.5, 1.2)),
		CFrame = CFrame.new(pos) * CFrame.Angles(FX.rand(0, 6), FX.rand(0, 6), FX.rand(0, 6)) })
	p.AssemblyLinearVelocity = dir * speed
	p.AssemblyAngularVelocity = FX.unit() * FX.rand(6, 20)
	local a = Instance.new("Attachment"); a.Parent = p
	fireEmitter(a, 70, 1.5, { Speed = FX.nr(0, 1), Lifetime = FX.nr(0.2, 0.4) })
	FX.emitter(a, { Texture = FX.TEX.smoke, Rate = 25, Lifetime = FX.nr(0.8, 1.3), Speed = FX.nr(0, 1),
		Size = FX.nseq(0, 0.6, 1, 2.6), Transparency = FX.nseq(0, 0.55, 1, 1), Color = ColorSequence.new(F.smoke) })
	local l = Instance.new("PointLight"); l.Color = F.orange; l.Brightness = 2; l.Range = 8; l.Shadows = false; l.Parent = p
	local life = FX.rand(1.6, 2.6)
	FX.tween(p, 0.4, { Transparency = 1, Size = p.Size * 0.3 }, nil, nil, life - 0.4)
	Debris:AddItem(p, life)
end

local function flameCast(op)
	local muzzle, dir = op.from, op.dir
	-- muzzle blast
	FX.pop(muzzle, F.hot, 1, 7, 0.16)
	FX.pop(muzzle, F.yellow, 1.5, 9, 0.28, nil, 0.1)
	FX.pop(muzzle, F.red, 2, 12, 0.45, FORCEFIELD)
	FX.ring(muzzle, dir, F.orange, 2, 18, 0.35)
	task.delay(0.06, function() FX.ring(muzzle + dir * 2, dir, F.yellow, 1.5, 12, 0.3, 0.2) end)
	local a = FX.anchor(FX.alignY(muzzle, dir), 3)
	fireEmitter(a, 0, 4, { EmissionDirection = TOP, SpreadAngle = Vector2.new(28, 28), Speed = FX.nr(20, 55), Drag = 6,
		Lifetime = FX.nr(0.2, 0.5) }):Emit(60)
	FX.emitter(a, { Texture = FX.TEX.spark, EmissionDirection = TOP, SpreadAngle = Vector2.new(50, 50), Speed = FX.nr(30, 80),
		Drag = 2, Lifetime = FX.nr(0.3, 0.9), Size = FX.nseq(0, 0.5, 1, 0), Color = FX.cseq(F.hot, F.orange), LightEmission = 1,
		Acceleration = Vector3.new(0, -40, 0) }):Emit(70)
	FX.emitter(a, { Texture = FX.TEX.smoke, SpreadAngle = Vector2.new(180, 180), Speed = FX.nr(3, 8), Drag = 3,
		Lifetime = FX.nr(0.8, 1.4), Size = FX.nseq(0, 2, 1, 7), Transparency = FX.nseq(0, 0.6, 1, 1),
		Color = ColorSequence.new(F.smoke), Acceleration = Vector3.new(0, 4, 0) }):Emit(14)
	FX.flashLight(muzzle, F.orange, 14, 40, 0.45)
	-- fire ring flaring around the caster's feet
	local g = groundHit(op.from, 8)
	if g then
		FX.ring(g.Position + g.Normal * 0.3, g.Normal, F.orange, 3, 22, 0.5)
		FX.disk(g.Position + g.Normal * 0.03, g.Normal, 6, F.orange, NEON, 0.35, 0.05, 0.5)
		local fa = FX.anchor(FX.alignY(g.Position, g.Normal), 2)
		fireEmitter(fa, 0, 2.5, { EmissionDirection = TOP, SpreadAngle = Vector2.new(85, 5), Speed = FX.nr(10, 18), Drag = 5 }):Emit(40)
	end
	play(SFX.fireCast, muzzle, 1.4, 1)
	play(SFX.fireBlast, muzzle, 0.6, 1.15)
	if isLocal(op.caster) then
		Cam.kick("fov", 10, 0.05, 0.05, 0.55)
		Cam.kick("push", -1.6, 0.05, 0.04, 0.5)
		Cam.kick("pitch", 3, 0.04, 0, 0.35)
		Cam.shake(0.4)
		Cam.grade({ tint = rgb(255, 222, 190), brightness = 0.08, contrast = 0.12, bloom = 0.6, release = 0.45 })
	else
		Cam.shakeAt(muzzle, 0.35, 50)
	end

	-- the fireball
	local cf = FX.lookAt(op.from, op.from + dir)
	local core = FX.part({ Shape = BALL, Size = Vector3.one * 1.3, CFrame = cf, Color = F.hot })
	local shell = FX.part({ Shape = BALL, Size = Vector3.one * 2.3, CFrame = cf, Color = F.orange, Transparency = 0.25 })
	local aura = FX.part({ Shape = BALL, Size = Vector3.one * 3.8, CFrame = cf, Color = F.red, Material = FORCEFIELD })
	local att = Instance.new("Attachment"); att.Parent = core
	local emitters = {
		fireEmitter(att, 240, 3.4),
		FX.emitter(att, { Texture = FX.TEX.core, Rate = 25, Lifetime = FX.nr(0.15, 0.25), Speed = FX.nr(0), LockedToPart = true,
			Size = FX.nseq(0, 4.5, 1, 3), Transparency = FX.nseq(0, 0.35, 1, 1), Color = FX.cseq(F.yellow, F.orange), LightEmission = 1,
			Rotation = FX.nr(0, 360) }),
		FX.emitter(att, { Texture = FX.TEX.smoke, Rate = 60, Lifetime = FX.nr(1, 1.8), Speed = FX.nr(0.5, 2), SpreadAngle = Vector2.new(180, 180),
			Size = FX.nseq(0, 1.5, 1, 6.5), Transparency = FX.nseq(0, 0.55, 1, 1), Color = FX.cseq(F.smoke, F.smokeDark),
			Rotation = FX.nr(0, 360), RotSpeed = FX.nr(-40, 40), Acceleration = Vector3.new(0, 3, 0) }),
		FX.emitter(att, { Texture = FX.TEX.spark, Rate = 110, Lifetime = FX.nr(0.3, 0.8), Speed = FX.nr(8, 20), SpreadAngle = Vector2.new(180, 180),
			Size = FX.nseq(0, 0.35, 1, 0), Color = FX.cseq(F.yellow, F.orange), LightEmission = 1, Acceleration = Vector3.new(0, -30, 0) }),
		FX.emitter(att, { Texture = FX.TEX.sparkle, Rate = 40, Lifetime = FX.nr(1, 1.6), Speed = FX.nr(1, 4), SpreadAngle = Vector2.new(180, 180),
			Size = FX.nseq(0, 0.3, 1, 0), Color = FX.cseq(F.yellow, F.red), LightEmission = 1, Acceleration = Vector3.new(0, -4, 0), Drag = 1 }),
	}
	addTrail(shell, 1.1, 0.35, FX.cseq(F.yellow, F.orange, F.red))
	local orbs = {}
	for i = 1, 3 do
		local orb = FX.part({ Shape = BALL, Size = Vector3.one * 0.55, CFrame = cf, Color = F.yellow })
		addTrail(orb, 0.25, 0.4, FX.cseq(F.hot, F.orange))
		orbs[i] = orb
	end
	local light = Instance.new("PointLight"); light.Color = F.orange; light.Brightness = 6; light.Range = 24; light.Shadows = false; light.Parent = core
	local travel = play(SFX.fireTravel, core, 1.1, 1, { life = 7, near = 15 })
	local lastTrail = 0
	startFlight("flame" .. op.id, op, {
		update = function(st, now)
			local look = FX.lookAt(Vector3.zero, st.dir) - Vector3.zero
			local c = CFrame.new(st.pos) * look
			local pulse = 1 + math.sin(now * 32) * 0.09
			core.CFrame, shell.CFrame = c, c
			shell.Size = Vector3.one * 2.3 * pulse
			aura.CFrame = c * CFrame.Angles(0, 0, now * 6)
			aura.Size = Vector3.one * 3.8 * (2 - pulse)
			for i, orb in ipairs(orbs) do
				local ang = now * 15 + i * math.pi * 2 / 3
				orb.CFrame = c * CFrame.new(math.cos(ang) * 1.9, math.sin(ang) * 1.9, 0)
			end
			light.Brightness = 6 + math.noise(now * 18, 0.5) * 6
			-- scorch a trail of flames on the floor beneath it
			if not st.parked and now - lastTrail > 0.09 then
				lastTrail = now
				local g2 = groundHit(st.pos, 9)
				if g2 then
					local ta = FX.anchor(FX.alignY(g2.Position, g2.Normal), 1.6)
					local e = fireEmitter(ta, 30, 1.8, { EmissionDirection = TOP, SpreadAngle = Vector2.new(15, 15), Speed = FX.nr(2, 5) })
					task.delay(0.5, function() e.Enabled = false end)
				end
			end
		end,
		retire = function()
			for _, e in ipairs(emitters) do e.Enabled = false end
			for _, p in ipairs({ core, shell, aura, orbs[1], orbs[2], orbs[3] }) do p.Transparency = 1; Debris:AddItem(p, 1.6) end
			light.Enabled = false
			fadeSound(travel, 0.25)
		end,
	})
end

local function flameImpact(op)
	endFlight("flame" .. op.id)
	local pos = op.pos
	local n = (op.normal and op.normal.Magnitude > 0.1) and op.normal.Unit or Vector3.yAxis
	local scale = op.hit and 1 or 0.55
	-- the fireball
	FX.pop(pos, F.hot, 2 * scale, 18 * scale, 0.16)
	FX.pop(pos, F.yellow, 3 * scale, 24 * scale, 0.3, nil, 0.05)
	FX.pop(pos, F.orange, 4 * scale, 30 * scale, 0.5, nil, 0.3)
	FX.pop(pos, F.red, 6 * scale, 40 * scale, 0.85, FORCEFIELD)
	FX.ring(pos, n, F.orange, 3, 46 * scale, 0.5)
	task.delay(0.07, function() FX.ring(pos, n, F.yellow, 2, 32 * scale, 0.42, 0.15) end)
	task.delay(0.14, function() FX.ring(pos, n, F.hot, 1, 22 * scale, 0.35, 0.3) end)
	local a = FX.anchor(FX.alignY(pos, n), 6)
	FX.emitter(a, { Texture = FX.TEX.core, Speed = FX.nr(0), Lifetime = FX.nr(0.35, 0.6), Size = FX.nseq(0, 8 * scale, 1, 24 * scale),
		Transparency = FX.nseq(0, 0, 1, 1), Color = FIRE_SEQ, LightEmission = 1, Rotation = FX.nr(0, 360) }):Emit(8)
	fireEmitter(a, 0, 5 * scale, { EmissionDirection = TOP, SpreadAngle = Vector2.new(85, 85), Speed = FX.nr(25 * scale, 65 * scale),
		Drag = 6, Lifetime = FX.nr(0.35, 0.9) }):Emit(math.floor(90 * scale))
	-- rising mushroom column
	local column = fireEmitter(a, 140 * scale, 6 * scale, { EmissionDirection = TOP, SpreadAngle = Vector2.new(20, 20),
		Speed = FX.nr(14, 26), Drag = 2, Lifetime = FX.nr(0.5, 0.9), Acceleration = Vector3.new(0, 20, 0) })
	task.delay(0.35, function() column.Enabled = false end)
	FX.emitter(a, { Texture = FX.TEX.burst, EmissionDirection = TOP, SpreadAngle = Vector2.new(70, 70), Speed = FX.nr(5, 14),
		Drag = 1.5, Lifetime = FX.nr(1.6, 3), Size = FX.nseq(0, 3 * scale, 1, 16 * scale), Transparency = FX.nseq(0, 0.6, 0.3, 0.65, 1, 1),
		Color = FX.cseq(F.orange, rgb(110, 95, 85), rgb(70, 66, 64)), LightEmission = 0.12, Acceleration = Vector3.new(0, 7, 0),
		Rotation = FX.nr(0, 360), RotSpeed = FX.nr(-30, 30) }):Emit(math.floor(16 * scale))
	FX.emitter(a, { Texture = FX.TEX.spark, EmissionDirection = TOP, SpreadAngle = Vector2.new(90, 90), Speed = FX.nr(35, 90),
		Drag = 1, Lifetime = FX.nr(0.6, 1.6), Size = FX.nseq(0, 0.55, 1, 0), Color = FX.cseq(F.hot, F.yellow, F.orange),
		LightEmission = 1, Acceleration = Vector3.new(0, -45, 0) }):Emit(math.floor(130 * scale))
	local embers = FX.emitter(a, { Texture = FX.TEX.sparkle, Rate = 45 * scale, SpreadAngle = Vector2.new(180, 180), Speed = FX.nr(1, 6),
		Lifetime = FX.nr(1.2, 2.4), Size = FX.nseq(0, 0.45, 1, 0), Color = FX.cseq(F.yellow, F.red), LightEmission = 1,
		Acceleration = Vector3.new(0, 5, 0) })
	task.delay(1.8, function() embers.Enabled = false end)
	for _ = 1, math.floor(12 * scale) do
		burningChunk(pos + n * 0.8, (n * 1.2 + FX.unit()).Unit, FX.rand(30, 60) * scale)
	end
	-- scorched, cracked, burning ground
	local g = groundHit(pos, 12)
	if g then
		local gp, gn = g.Position + g.Normal * 0.03, g.Normal
		FX.disk(gp, gn, 12 * scale, F.char, Enum.Material.Basalt, 0.05, 4, 2)
		FX.disk(gp + gn * 0.02, gn, 7 * scale, F.orange, NEON, 0.15, 0.3, 1.4)
		cracks(gp + gn * 0.03, gn, F.orange, 8, 3 * scale, 8 * scale, 0.5)
		for _ = 1, math.floor(7 * scale) do
			local off = FX.alignY(gp, gn):VectorToWorldSpace(Vector3.new(FX.rand(-6, 6), 0, FX.rand(-6, 6)) * scale)
			local fa = FX.anchor(FX.alignY(gp + off, gn), 3.5)
			local e = fireEmitter(fa, 28, 2.6, { EmissionDirection = TOP, SpreadAngle = Vector2.new(12, 12), Speed = FX.nr(2, 6),
				Lifetime = FX.nr(0.4, 0.8) })
			task.delay(FX.rand(1.6, 2.6), function() e.Enabled = false end)
		end
	end
	FX.flashLight(pos + n * 2, F.orange, 20, 70 * scale, 1.1)
	play(SFX.fireBoom, pos, 1.7 * scale + 0.3, 1)
	play(SFX.fireImpact, pos, 1.1, 1)
	play(SFX.boom, pos, 0.55, 0.8)
	local p = Cam.shakeAt(pos, 1.25 * scale, 95)
	if p > 0 then
		Cam.grade({ tint = rgb(255, 205, 165), brightness = 0.32 * p, contrast = 0.3 * p, saturation = 0.15 * p,
			bloom = 1.4 * p, blur = 9 * p, attack = 0.02, hold = 0.05, release = 0.6 })
		Cam.kick("fov", -7 * p, 0.03, 0.03, 0.5)
		Cam.kick("push", 1.3 * p, 0.03, 0, 0.45)
	end
end

-- Burning status: the whole body is on fire for the burn duration.
local burning = {}
local function burn(op)
	local model = op.target
	local root = rootOf(model)
	if not root then return end
	local untilTime = os.clock() + (op.duration or 5)
	local st = burning[model]
	if st then st.untilTime = math.max(st.untilTime, untilTime); return end
	st = { untilTime = untilTime, emitters = {}, parts = {} }
	burning[model] = st
	for _, part in ipairs(bodyParts(model)) do
		local e = fireEmitter(part, 42, 2.8, { EmissionDirection = TOP, SpreadAngle = Vector2.new(20, 20), Speed = FX.nr(2, 6),
			Lifetime = FX.nr(0.3, 0.6), Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			Acceleration = Vector3.new(0, 6, 0) })
		table.insert(st.emitters, e)
	end
	local a = Instance.new("Attachment"); a.Parent = root
	st.attachment = a
	table.insert(st.emitters, FX.emitter(a, { Texture = FX.TEX.smoke, Rate = 18, Lifetime = FX.nr(1.2, 2), Speed = FX.nr(2, 4),
		EmissionDirection = TOP, SpreadAngle = Vector2.new(20, 20), Size = FX.nseq(0, 2, 1, 6), Transparency = FX.nseq(0, 0.6, 1, 1),
		Color = FX.cseq(F.smoke, F.smokeDark), Acceleration = Vector3.new(0, 4, 0) }))
	table.insert(st.emitters, FX.emitter(a, { Texture = FX.TEX.sparkle, Rate = 30, Lifetime = FX.nr(0.8, 1.4), Speed = FX.nr(3, 7),
		SpreadAngle = Vector2.new(180, 180), Size = FX.nseq(0, 0.35, 1, 0), Color = FX.cseq(F.yellow, F.red), LightEmission = 1,
		Acceleration = Vector3.new(0, 6, 0) }))
	local light = Instance.new("PointLight"); light.Color = F.orange; light.Range = 14; light.Shadows = false; light.Parent = a
	local hl = Instance.new("Highlight")
	hl.FillColor, hl.OutlineColor = F.orange, F.yellow
	hl.FillTransparency, hl.OutlineTransparency = 0.6, 0.2
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Adornee = model
	hl.Parent = FX.folder
	st.highlight = hl
	st.sound = play(SFX.fireLoop, root, 0.6, 1, { loop = true, near = 12 })
	play(SFX.flameDash, root, 0.6, 1.2)
	local start = os.clock()
	local lastTick = start
	st.conn = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		light.Brightness = 3 + math.noise(now * 14, 3.3) * 3
		hl.FillTransparency = 0.55 + math.sin(now * 16) * 0.12
		if now - lastTick >= 1 then
			lastTick = now
			FX.pop(root.Position, F.orange, 2, 7, 0.25, nil, 0.3)
			if model == localPlayer.Character then
				Cam.grade({ tint = rgb(255, 170, 130), brightness = 0.07, contrast = 0.1, attack = 0.03, release = 0.35 })
				Cam.shake(0.15)
			end
		end
	end)
	if model == localPlayer.Character then
		Cam.shake(0.5)
		Cam.grade({ tint = rgb(255, 160, 120), brightness = 0.15, contrast = 0.2, blur = 4, attack = 0.03, hold = 0.1, release = 0.6 })
	end
end
local function burnEnd(op)
	local st = burning[op.target]
	if not st then return end
	burning[op.target] = nil
	if st.conn then st.conn:Disconnect() end
	for _, e in ipairs(st.emitters) do e.Enabled = false; Debris:AddItem(e, 1.5) end
	if st.attachment then Debris:AddItem(st.attachment, 2.2) end
	if st.highlight then FX.tween(st.highlight, 0.4, { FillTransparency = 1, OutlineTransparency = 1 }); Debris:AddItem(st.highlight, 0.5) end
	fadeSound(st.sound, 0.5)
	local root = rootOf(op.target)
	if root then
		local a = FX.anchor(root.Position, 3)
		FX.emitter(a, { Texture = FX.TEX.smoke, SpreadAngle = Vector2.new(180, 180), Speed = FX.nr(2, 6), Drag = 2,
			Lifetime = FX.nr(1, 1.8), Size = FX.nseq(0, 2, 1, 6), Transparency = FX.nseq(0, 0.5, 1, 1), Color = ColorSequence.new(F.smoke),
			Acceleration = Vector3.new(0, 4, 0) }):Emit(16)
	end
end

---------------------------------------------------------------- FREEZE
local I = {
	frost = rgb(232, 250, 255), ice = rgb(140, 222, 255), deep = rgb(50, 140, 255), dark = rgb(25, 70, 160), mist = rgb(220, 240, 255),
}
local ICE_SEQ = FX.cseq(I.frost, I.ice, I.deep)
local DIAMOND = CFrame.Angles(0, 0, math.pi / 4)

local function crystal(cf, size, delayTime, growTime)
	local shell = FX.part({ Size = Vector3.one * 0.1, CFrame = cf * DIAMOND, Material = GLASS, Color = I.ice, Transparency = 0.18, Reflectance = 0.4 })
	local core = FX.part({ Size = Vector3.one * 0.05, CFrame = cf * DIAMOND, Color = I.frost })
	FX.tween(shell, growTime, { Size = size }, BACK, OUT, delayTime)
	FX.tween(core, growTime, { Size = Vector3.new(size.X * 0.32, size.Y * 0.32, size.Z * 0.85) }, BACK, OUT, delayTime)
	return shell, core
end

local function shatter(part, core, count, speed)
	if part and part.Parent then
		FX.shards(part.Position, part.CFrame.LookVector, count, { color = I.ice, material = GLASS, transparency = 0.15,
			reflectance = 0.45, speed = speed or 28, life = 1.4, size = math.clamp(part.Size.Magnitude * 0.12, 0.25, 0.7), spread = 1.5 })
		part:Destroy()
	end
	if core and core.Parent then core:Destroy() end
end

local function spike(base, dir, length, width, delayTime, hold)
	local cf = FX.lookAt(base + dir * length * 0.5, base + dir * length)
	local shell, core = crystal(cf, Vector3.new(width, width, length), delayTime, 0.16)
	task.delay(delayTime + hold, function() shatter(shell, core, 3) end)
end

local function frostCast(op)
	local muzzle, dir = op.from, op.dir
	FX.pop(muzzle, I.frost, 1, 6, 0.18)
	FX.pop(muzzle, I.ice, 2, 10, 0.4, FORCEFIELD)
	FX.ring(muzzle, dir, I.ice, 2, 15, 0.38)
	task.delay(0.06, function() FX.ring(muzzle + dir * 2, dir, I.frost, 1.5, 10, 0.32, 0.2) end)
	local a = FX.anchor(FX.alignY(muzzle, dir), 3)
	FX.emitter(a, { Texture = FX.TEX.sparkle, EmissionDirection = TOP, SpreadAngle = Vector2.new(35, 35), Speed = FX.nr(18, 50), Drag = 4,
		Lifetime = FX.nr(0.4, 0.9), Size = FX.nseq(0, 0.8, 1, 0), Color = ICE_SEQ, LightEmission = 1 }):Emit(70)
	FX.emitter(a, { Texture = FX.TEX.smoke, SpreadAngle = Vector2.new(180, 180), Speed = FX.nr(4, 12), Drag = 4,
		Lifetime = FX.nr(0.9, 1.6), Size = FX.nseq(0, 2, 1, 7), Transparency = FX.nseq(0, 0.45, 1, 1), Color = ColorSequence.new(I.mist),
		LightEmission = 0.35, Acceleration = Vector3.new(0, -2, 0) }):Emit(20)
	FX.flashLight(muzzle, I.ice, 10, 32, 0.5)
	-- frost nova + crown of crystals around the caster
	local g = groundHit(op.from, 8)
	if g then
		local gp, gn = g.Position, g.Normal
		FX.ring(gp + gn * 0.2, gn, I.frost, 3, 28, 0.6)
		FX.disk(gp + gn * 0.03, gn, 10, I.ice, Enum.Material.Ice, 0.15, 1.2, 1.2)
		cracks(gp + gn * 0.04, gn, I.ice, 8, 2, 5, 0.6)
		local basis = FX.alignY(gp, gn)
		for i = 1, 10 do
			local ang = i / 10 * math.pi * 2
			local out = basis:VectorToWorldSpace(Vector3.new(math.cos(ang), 0, math.sin(ang)))
			spike(gp + out * 3.4, (gn * 1.6 + out).Unit, FX.rand(2.2, 3.8), 0.8, i * 0.012, 0.45)
		end
		local ma = FX.anchor(FX.alignY(gp, gn), 3)
		FX.emitter(ma, { Texture = FX.TEX.smoke, EmissionDirection = TOP, SpreadAngle = Vector2.new(88, 5), Speed = FX.nr(10, 18), Drag = 4,
			Lifetime = FX.nr(0.8, 1.3), Size = FX.nseq(0, 2, 1, 6), Transparency = FX.nseq(0, 0.5, 1, 1), Color = ColorSequence.new(I.mist),
			LightEmission = 0.3 }):Emit(26)
	end
	play(SFX.iceCast, muzzle, 0.7, 1.25, { near = 15, far = 100 })
	if isLocal(op.caster) then
		Cam.kick("fov", 8, 0.05, 0.04, 0.5)
		Cam.kick("push", -1.1, 0.05, 0.03, 0.45)
		Cam.kick("roll", (math.random() < 0.5 and -1 or 1) * 3, 0.05, 0, 0.4)
		Cam.shake(0.32)
		Cam.grade({ tint = rgb(200, 230, 255), saturation = -0.25, brightness = 0.06, release = 0.55 })
	else
		Cam.shakeAt(muzzle, 0.3, 50)
	end

	-- the crystal lance
	local cf = FX.lookAt(op.from, op.from + dir)
	local shell = FX.part({ Size = Vector3.new(1.2, 1.2, 3.8), CFrame = cf, Material = GLASS, Color = I.ice, Transparency = 0.18, Reflectance = 0.45 })
	local core = FX.part({ Size = Vector3.new(0.45, 0.45, 4.8), CFrame = cf, Color = I.frost })
	local tip = FX.part({ Size = Vector3.new(0.7, 0.7, 1.6), CFrame = cf, Color = I.ice })
	local ring = FX.part({ Shape = BALL, Size = Vector3.one * 2.8, CFrame = cf, Color = I.deep, Material = FORCEFIELD })
	local orbiters = {}
	for i = 1, 4 do
		orbiters[i] = FX.part({ Size = Vector3.new(0.35, 0.35, 1.3), CFrame = cf, Material = GLASS, Color = I.ice, Transparency = 0.1, Reflectance = 0.5 })
		addTrail(orbiters[i], 0.15, 0.3, FX.cseq(I.frost, I.ice))
	end
	local att = Instance.new("Attachment"); att.Parent = core
	local emitters = {
		FX.emitter(att, { Texture = FX.TEX.smoke, Rate = 80, Lifetime = FX.nr(0.7, 1.3), Speed = FX.nr(0.5, 2), SpreadAngle = Vector2.new(180, 180),
			Size = FX.nseq(0, 1.3, 1, 5), Transparency = FX.nseq(0, 0.45, 1, 1), Color = FX.cseq(I.frost, I.ice), LightEmission = 0.4,
			Rotation = FX.nr(0, 360), RotSpeed = FX.nr(-60, 60), Drag = 2 }),
		FX.emitter(att, { Texture = FX.TEX.sparkle, Rate = 110, Lifetime = FX.nr(0.5, 1), Speed = FX.nr(1, 5), SpreadAngle = Vector2.new(180, 180),
			Size = FX.nseq(0, 0.65, 1, 0), Color = ICE_SEQ, LightEmission = 1, Rotation = FX.nr(0, 360) }),
		FX.emitter(att, { Texture = FX.TEX.sparkle, Rate = 45, Lifetime = FX.nr(1, 1.8), Speed = FX.nr(0.5, 2), SpreadAngle = Vector2.new(180, 180),
			Size = FX.nseq(0, 0.25, 1, 0.1), Color = ColorSequence.new(I.frost), LightEmission = 0.6, Acceleration = Vector3.new(0, -6, 0), Drag = 1 }),
	}
	addTrail(core, 0.8, 0.45, FX.cseq(I.frost, I.ice, I.deep))
	local light = Instance.new("PointLight"); light.Color = I.ice; light.Brightness = 5; light.Range = 18; light.Shadows = false; light.Parent = core
	local loop = Instance.new("Sound")
	loop.SoundId, loop.Looped, loop.Volume, loop.PlaybackSpeed, loop.RollOffMinDistance = SFX.iceCrackle, true, 0.18, 1.15, 10
	loop.RollOffMaxDistance = 80
	loop.Parent = core
	loop:Play()
	local lastShed, lastFrost = 0, 0
	startFlight("freeze" .. op.id, op, {
		update = function(st, now)
			local look = FX.lookAt(Vector3.zero, st.dir) - Vector3.zero
			local c = CFrame.new(st.pos) * look * CFrame.Angles(0, 0, now * 14)
			shell.CFrame = c * DIAMOND
			core.CFrame = c * DIAMOND
			tip.CFrame = c * CFrame.new(0, 0, -2.6) * DIAMOND
			ring.CFrame = c * CFrame.new(0, 0, 0.8)
			ring.Size = Vector3.one * (2.6 + math.sin(now * 25) * 0.35)
			for i, o in ipairs(orbiters) do
				local ang = now * 12 + i * math.pi / 2
				o.CFrame = c * CFrame.new(math.cos(ang) * 1.6, math.sin(ang) * 1.6, 0.6) * DIAMOND
			end
			if not st.parked and now - lastShed > 0.035 then
				lastShed = now
				local s = FX.part({ Anchored = false, Size = Vector3.new(0.18, 0.18, FX.rand(0.3, 0.6)), Material = GLASS, Color = I.ice,
					Reflectance = 0.4, Transparency = 0.1,
					CFrame = c * CFrame.new(FX.rand(-0.6, 0.6), FX.rand(-0.6, 0.6), 1.5) * CFrame.Angles(FX.rand(0, 6), FX.rand(0, 6), 0) })
				s.AssemblyLinearVelocity = FX.unit() * 6 + Vector3.new(0, 2, 0)
				FX.tween(s, 0.5, { Transparency = 1, Size = s.Size * 0.3 }, nil, nil, 0.15)
				Debris:AddItem(s, 0.7)
			end
			-- a frozen trail across the floor
			if not st.parked and now - lastFrost > 0.1 then
				lastFrost = now
				local g2 = groundHit(st.pos, 9)
				if g2 then FX.disk(g2.Position + g2.Normal * 0.03, g2.Normal, FX.rand(2.5, 4), I.ice, Enum.Material.Ice, 0.25, 1.4, 1) end
			end
		end,
		retire = function()
			for _, e in ipairs(emitters) do e.Enabled = false end
			local parts = { shell, core, tip, ring }
			for _, o in ipairs(orbiters) do table.insert(parts, o) end
			for _, p in ipairs(parts) do p.Transparency = 1; Debris:AddItem(p, 1.6) end
			light.Enabled = false
			loop:Stop()
		end,
	})
end

local function frostImpact(op)
	endFlight("freeze" .. op.id)
	local pos = op.pos
	local n = (op.normal and op.normal.Magnitude > 0.1) and op.normal.Unit or Vector3.yAxis
	local scale = op.hit and 1 or 0.6
	FX.pop(pos, I.frost, 1.5, 12 * scale, 0.2)
	FX.pop(pos, I.ice, 3, 20 * scale, 0.55, FORCEFIELD)
	FX.ring(pos, n, I.frost, 2, 36 * scale, 0.55)
	task.delay(0.08, function() FX.ring(pos, n, I.deep, 2, 24 * scale, 0.45, 0.2) end)
	for i = 1, math.floor(15 * scale) do
		spike(pos - n * 0.3, (n * 1.3 + FX.unit()).Unit, FX.rand(3, 7.5) * scale, FX.rand(0.8, 1.5) * scale, i * 0.01, 0.8 + FX.rand(0, 0.25))
	end
	local a = FX.anchor(FX.alignY(pos, n), 5)
	FX.emitter(a, { Texture = FX.TEX.sparkle, EmissionDirection = TOP, SpreadAngle = Vector2.new(90, 90), Speed = FX.nr(15, 55), Drag = 3,
		Lifetime = FX.nr(0.5, 1.4), Size = FX.nseq(0, 0.9, 1, 0), Color = ICE_SEQ, LightEmission = 1, Rotation = FX.nr(0, 360) }):Emit(math.floor(110 * scale))
	FX.emitter(a, { Texture = FX.TEX.burst, EmissionDirection = TOP, SpreadAngle = Vector2.new(85, 85), Speed = FX.nr(6, 18), Drag = 3,
		Lifetime = FX.nr(1.4, 2.6), Size = FX.nseq(0, 3, 1, 12 * scale), Transparency = FX.nseq(0, 0.4, 1, 1), Color = FX.cseq(I.frost, I.ice),
		LightEmission = 0.3, Rotation = FX.nr(0, 360), RotSpeed = FX.nr(-30, 30), Acceleration = Vector3.new(0, -2, 0) }):Emit(math.floor(30 * scale))
	local snow = FX.emitter(a, { Texture = FX.TEX.sparkle, Rate = 55 * scale, SpreadAngle = Vector2.new(180, 180), Speed = FX.nr(1, 5),
		Lifetime = FX.nr(1.2, 2.2), Size = FX.nseq(0, 0.3, 1, 0.1), Color = ColorSequence.new(I.frost), LightEmission = 0.7,
		Acceleration = Vector3.new(0, -4, 0), Drag = 1 })
	task.delay(2, function() snow.Enabled = false end)
	local g = groundHit(pos, 12)
	if g then
		local gp, gn = g.Position + g.Normal * 0.03, g.Normal
		FX.disk(gp, gn, 13 * scale, I.ice, Enum.Material.Ice, 0.05, 3, 1.5)
		FX.disk(gp + gn * 0.02, gn, 8 * scale, I.frost, NEON, 0.3, 0.1, 0.9)
		cracks(gp + gn * 0.04, gn, I.ice, 9, 3 * scale, 7 * scale, 1)
	end
	FX.flashLight(pos, I.ice, 14, 45, 0.9)
	play(SFX.iceShatter, pos, 0.85, 0.95, { near = 15, far = 120 })
	local p = Cam.shakeAt(pos, 0.85 * scale, 70)
	if p > 0 then
		Cam.grade({ tint = rgb(175, 220, 255), saturation = -0.4 * p, contrast = 0.28 * p, brightness = 0.14 * p, blur = 6 * p,
			bloom = p, attack = 0.02, hold = 0.06, release = 0.75 })
		Cam.kick("fov", -6 * p, 0.03, 0.03, 0.5)
	end
end

-- Frozen status: the target is sealed inside a jagged ice crystal for the full duration.
local frozen = {}
local function freeze(op)
	local model = op.target
	local root = rootOf(model)
	if not root then return end
	local duration = op.duration or 5
	local st = frozen[model]
	if st then st.untilTime = math.max(st.untilTime, os.clock() + duration); return end
	st = { untilTime = os.clock() + duration, parts = {}, followers = {}, emitters = {} }
	frozen[model] = st
	-- ice skin over every limb
	for _, part in ipairs(bodyParts(model)) do
		local shellPart = FX.part({ Size = part.Size + Vector3.one * 0.45, CFrame = part.CFrame, Material = GLASS, Color = I.ice,
			Transparency = 1, Reflectance = 0.35 })
		FX.tween(shellPart, 0.18, { Transparency = 0.28 })
		table.insert(st.parts, shellPart)
		table.insert(st.followers, { shellPart, part, CFrame.identity })
	end
	-- jagged crystal cluster encasing the body
	for i = 1, 12 do
		local yaw = i / 12 * math.pi * 2 + FX.rand(-0.2, 0.2)
		local localCF = CFrame.new(0, FX.rand(-2.4, 1.6), 0) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(FX.rand(10, 65)), 0, 0)
			* CFrame.new(0, 0, -FX.rand(1, 1.8))
		local len = FX.rand(3.2, 5.8)
		local shellPart, corePart = crystal(root.CFrame * localCF, Vector3.new(FX.rand(0.6, 1.05), FX.rand(0.6, 1.05), len), i * 0.015, 0.2)
		table.insert(st.parts, shellPart); table.insert(st.parts, corePart)
		table.insert(st.followers, { shellPart, root, localCF * DIAMOND })
		table.insert(st.followers, { corePart, root, localCF * DIAMOND })
	end
	-- frozen ground around the feet
	local g = groundHit(root.Position, 8, model)
	if g then
		local gp, gn = g.Position + g.Normal * 0.03, g.Normal
		local patch = FX.part({ Shape = CYL, Size = Vector3.new(0.08, 9, 9), Material = Enum.Material.Ice, Color = I.ice, Transparency = 0.1,
			CFrame = FX.alignY(gp, gn) * CFrame.Angles(0, 0, math.pi / 2) })
		table.insert(st.parts, patch)
		local basis = FX.alignY(gp, gn)
		for i = 1, 7 do
			local ang = i / 7 * math.pi * 2
			local out = basis:VectorToWorldSpace(Vector3.new(math.cos(ang), 0, math.sin(ang)))
			local sp, cp = crystal(FX.lookAt(gp + out * 2.6, gp + out * 3.2 + gn * 2.4), Vector3.new(0.6, 0.6, FX.rand(1.4, 2.4)), i * 0.02, 0.16)
			table.insert(st.parts, sp); table.insert(st.parts, cp)
		end
		FX.ring(gp + gn * 0.2, gn, I.frost, 2, 22, 0.55)
	end
	local a = Instance.new("Attachment"); a.Parent = root
	st.attachment = a
	table.insert(st.emitters, FX.emitter(a, { Texture = FX.TEX.smoke, Rate = 22, Lifetime = FX.nr(1.2, 2), Speed = FX.nr(0.5, 1.5),
		SpreadAngle = Vector2.new(180, 180), Size = FX.nseq(0, 2.5, 1, 6), Transparency = FX.nseq(0, 0.6, 1, 1), Color = ColorSequence.new(I.mist),
		Acceleration = Vector3.new(0, -2.5, 0), LightEmission = 0.3 }))
	table.insert(st.emitters, FX.emitter(a, { Texture = FX.TEX.sparkle, Rate = 30, Lifetime = FX.nr(0.6, 1.3), Speed = FX.nr(1, 3),
		SpreadAngle = Vector2.new(180, 180), Size = FX.nseq(0, 0.55, 1, 0), Color = ICE_SEQ, LightEmission = 1 }))
	local light = Instance.new("PointLight"); light.Color = I.ice; light.Brightness = 2.5; light.Range = 14; light.Shadows = false; light.Parent = a
	local hl = Instance.new("Highlight")
	hl.FillColor, hl.OutlineColor = I.ice, I.frost
	hl.FillTransparency, hl.OutlineTransparency = 0.8, 0.1
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Adornee = model
	hl.Parent = FX.folder
	st.highlight = hl
	FX.pop(root.Position, I.frost, 2, 11, 0.25, nil, 0.2)
	st.creak = play(SFX.iceCrackle, root, 0.18, 0.9, { loop = true, near = 10, far = 60 })
	st.conn = RunService.RenderStepped:Connect(function()
		for _, f in ipairs(st.followers) do
			if f[1].Parent and f[2].Parent then f[1].CFrame = f[2].CFrame * f[3] end
		end
	end)
	if model == localPlayer.Character then
		Cam.shake(0.45)
		local remaining = st.untilTime - os.clock()
		Cam.grade({ tint = rgb(170, 215, 255), saturation = -0.55, contrast = 0.2, brightness = 0.05, blur = 5,
			attack = 0.15, hold = math.max(0, remaining - 0.6), release = 0.6 })
		Cam.kick("fov", -6, 0.15, math.max(0, remaining - 0.6), 0.6)
	end
end

local function thaw(op)
	local st = frozen[op.target]
	if not st then return end
	frozen[op.target] = nil
	if st.conn then st.conn:Disconnect() end
	for _, e in ipairs(st.emitters) do e.Enabled = false end
	if st.attachment then Debris:AddItem(st.attachment, 2) end
	if st.highlight then FX.tween(st.highlight, 0.3, { FillTransparency = 1, OutlineTransparency = 1 }); Debris:AddItem(st.highlight, 0.4) end
	fadeSound(st.creak, 0.2)
	for i, part in ipairs(st.parts) do
		if part.Material == GLASS then shatter(part, nil, 2, 32) else
			FX.tween(part, 0.3, { Transparency = 1 }); Debris:AddItem(part, 0.35)
		end
	end
	local root = rootOf(op.target)
	local pos = root and root.Position
	if pos then
		FX.pop(pos, I.frost, 3, 13, 0.25, nil, 0.25)
		FX.ring(pos, Vector3.yAxis, I.ice, 2, 20, 0.45)
		local a = FX.anchor(pos, 3)
		FX.emitter(a, { Texture = FX.TEX.sparkle, SpreadAngle = Vector2.new(180, 180), Speed = FX.nr(10, 30), Drag = 3,
			Lifetime = FX.nr(0.5, 1.1), Size = FX.nseq(0, 0.7, 1, 0), Color = ICE_SEQ, LightEmission = 1 }):Emit(60)
		FX.emitter(a, { Texture = FX.TEX.smoke, SpreadAngle = Vector2.new(180, 180), Speed = FX.nr(4, 10), Drag = 3,
			Lifetime = FX.nr(0.8, 1.4), Size = FX.nseq(0, 2, 1, 6), Transparency = FX.nseq(0, 0.5, 1, 1), Color = ColorSequence.new(I.mist),
			LightEmission = 0.3 }):Emit(16)
		play(SFX.iceShatter, pos, 0.65, 1.1, { near = 15, far = 100 })
		Cam.shakeAt(pos, 0.4, 40)
	end
end

---------------------------------------------------------------- WAVE
local W = {
	deep = rgb(8, 45, 105), body = rgb(18, 85, 165), light = rgb(55, 150, 215), foam = rgb(215, 235, 245), spray = rgb(170, 205, 230),
	skin = rgb(25, 105, 185),
}
local waves = {}

local function waterSplash(pos, dir, scale, sound)
	FX.pop(pos, W.foam, 1, 8 * scale, 0.25, nil, 0.3)
	FX.ring(pos, Vector3.yAxis, W.foam, 2, 20 * scale, 0.5)
	local a = FX.anchor(FX.alignY(pos, (Vector3.yAxis * 1.5 + (dir or Vector3.zero)).Unit), 4)
	FX.emitter(a, { Texture = FX.TEX.sparkle, EmissionDirection = TOP, SpreadAngle = Vector2.new(55, 55), Speed = FX.nr(20 * scale, 45 * scale),
		Lifetime = FX.nr(0.6, 1.3), Size = FX.nseq(0, 0.6, 1, 0.2), Color = FX.cseq(W.foam, W.light), LightEmission = 0.5,
		Acceleration = Vector3.new(0, -60, 0), Drag = 0.5 }):Emit(math.floor(80 * scale))
	FX.emitter(a, { Texture = FX.TEX.smoke, EmissionDirection = TOP, SpreadAngle = Vector2.new(70, 70), Speed = FX.nr(8, 20),
		Lifetime = FX.nr(0.7, 1.4), Size = FX.nseq(0, 2.5 * scale, 1, 8 * scale), Transparency = FX.nseq(0, 0.45, 1, 1),
		Color = FX.cseq(W.foam, W.spray), LightEmission = 0, Acceleration = Vector3.new(0, -14, 0), Drag = 2 }):Emit(math.floor(30 * scale))
	if sound then play(sound, pos, 1.2, FX.rand(0.9, 1.1)) end
end

local function wedge(props)
	local w = Instance.new("WedgePart")
	w.Anchored, w.CanCollide, w.CanTouch, w.CanQuery, w.CastShadow = true, false, false, false, false
	w.TopSurface, w.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in props do w[k] = v end
	w.Parent = FX.folder
	return w
end

-- A breaking wave: sloped water body, a curling lip, shimmering surface, foam and spray.
-- Local space: origin on the floor under the wall's center, forward = -Z.
local function buildWaveRig(op)
	local size = op.size or Vector3.new(24, 12, 5)
	local width, height, depth = size.X, size.Y, size.Z
	local rig = { parts = {}, emitters = {}, offsets = {} }
	local function add(part, offset, bob)
		table.insert(rig.parts, part)
		rig.offsets[part] = { offset = offset, bob = bob or 0, phase = FX.rand(0, 6) }
		return part
	end
	-- Side profile of a breaking wave, built from overlapping cylinders (axis = width) so every
	-- silhouette is rounded and liquid. (z, y, diameter) in units of height/12; forward is -Z.
	local u = height / 12
	local PROFILE = {
		{ 12, 0.9, 2.2 }, { 9.6, 1.7, 3.6 }, { 7.2, 2.9, 5.2 }, { 4.9, 4.2, 6.6 }, { 2.7, 5.6, 7.6 },
		{ 0.8, 6.7, 7.8 }, { -0.9, 3.7, 6.6 }, { 2.2, 1.9, 4.6 }, { -1.6, 1.3, 3 },
	}
	for i, p in ipairs(PROFILE) do
		local shade = math.clamp(p[2] / 7, 0, 1)
		add(FX.part({ Shape = CYL, Size = Vector3.new(width * (1 - i * 0.004), p[3] * u, p[3] * u), Material = GLASS,
			Color = W.deep:Lerp(W.body, shade), Transparency = 0.06, Reflectance = 0.2 }), CFrame.new(0, p[2] * u, p[1] * u), 0.12)
	end
	-- the crest and the curling lip, thrown forward and down
	local cy, cz, r = 8.7 * u, -1.1 * u, 2.6 * u
	for k = 0, 7 do
		local a = k / 7 * math.rad(175)
		local d = (3.8 - k * 0.32) * u
		local y = cy + math.cos(a) * r
		local z = cz - math.sin(a) * r * 1.2
		add(FX.part({ Shape = CYL, Size = Vector3.new(width * (1 - k * 0.012), d, d), Material = GLASS,
			Color = W.body:Lerp(W.light, k / 7), Transparency = 0.08 + k * 0.03, Reflectance = 0.25 }), CFrame.new(0, y, z), 0.3)
	end
	-- foam riding the crest + whitewater at the base
	for k = 0, 4 do
		local a = math.rad(-15 + k * 32)
		local d = (1.6 - k * 0.15) * u
		add(FX.part({ Shape = CYL, Size = Vector3.new(width * 1.02, d, d), Material = Enum.Material.SmoothPlastic, Color = W.foam,
			Transparency = 0.08 + k * 0.08 }), CFrame.new(0, cy + math.cos(a) * (r + 1.3 * u), cz - math.sin(a) * (r + 1.3 * u) * 1.2), 0.45)
	end
	add(FX.part({ Shape = CYL, Size = Vector3.new(width * 1.06, 1.6 * u, 1.6 * u), Material = Enum.Material.SmoothPlastic, Color = W.foam,
		Transparency = 0.2 }), CFrame.new(0, 0.5 * u, -3.2 * u), 0.12)
	-- emitter carriers
	local crest = add(FX.part({ Size = Vector3.new(width, 1.5, 2), Transparency = 1 }), CFrame.new(0, cy + r, cz - r * 0.4))
	local lip = add(FX.part({ Size = Vector3.new(width, 1, 1), Transparency = 1 }), CFrame.new(0, cy - r * 0.3, cz - r * 1.25))
	local base = add(FX.part({ Size = Vector3.new(width * 1.05, 1, 2.5), Transparency = 1 }), CFrame.new(0, 0.6, -3.6 * u))
	local back = add(FX.part({ Size = Vector3.new(width, 1, 6 * u), Transparency = 1 }), CFrame.new(0, 4 * u, 7 * u))
	local inner = add(FX.part({ Size = Vector3.new(width * 0.9, 6 * u, 5 * u), Transparency = 1 }), CFrame.new(0, 4 * u, 3 * u))
	local function boxEmitter(part, props)
		props.Shape = Enum.ParticleEmitterShape.Box
		props.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		local e = FX.emitter(part, props)
		table.insert(rig.emitters, e)
		return e
	end
	-- spray blasting off the crest
	boxEmitter(crest, { Texture = FX.TEX.smoke, Rate = 280, Lifetime = FX.nr(0.7, 1.3), Speed = FX.nr(10, 24), EmissionDirection = Enum.NormalId.Front,
		SpreadAngle = Vector2.new(40, 40), Size = FX.nseq(0, 2.2, 1, 8), Transparency = FX.nseq(0, 0.5, 1, 1), Color = FX.cseq(W.foam, W.spray),
		LightEmission = 0, Acceleration = Vector3.new(0, -14, 0), Drag = 1.5, Rotation = FX.nr(0, 360), RotSpeed = FX.nr(-80, 80) })
	boxEmitter(crest, { Texture = FX.TEX.sparkle, Rate = 220, Lifetime = FX.nr(0.6, 1.3), Speed = FX.nr(16, 36), EmissionDirection = Enum.NormalId.Front,
		SpreadAngle = Vector2.new(45, 45), Size = FX.nseq(0, 0.65, 1, 0.15), Color = FX.cseq(W.foam, W.light), LightEmission = 0.15,
		Acceleration = Vector3.new(0, -60, 0) })
	-- water pouring off the lip
	boxEmitter(lip, { Texture = FX.TEX.sparkle, Rate = 160, Lifetime = FX.nr(0.4, 0.8), Speed = FX.nr(2, 6), EmissionDirection = Enum.NormalId.Bottom,
		SpreadAngle = Vector2.new(15, 15), Size = FX.nseq(0, 0.5, 1, 0.2), Color = FX.cseq(W.foam, W.light), LightEmission = 0.4,
		Acceleration = Vector3.new(0, -70, 0) })
	boxEmitter(lip, { Texture = FX.TEX.smoke, Rate = 70, Lifetime = FX.nr(0.4, 0.8), Speed = FX.nr(4, 10), EmissionDirection = Enum.NormalId.Bottom,
		SpreadAngle = Vector2.new(20, 20), Size = FX.nseq(0, 1.6, 1, 4), Transparency = FX.nseq(0, 0.5, 1, 1), Color = ColorSequence.new(W.foam),
		LightEmission = 0, Acceleration = Vector3.new(0, -30, 0) })
	-- churning whitewater along the front
	boxEmitter(base, { Texture = FX.TEX.smoke, Rate = 150, Lifetime = FX.nr(0.6, 1.1), Speed = FX.nr(5, 14), EmissionDirection = Enum.NormalId.Front,
		SpreadAngle = Vector2.new(70, 25), Size = FX.nseq(0, 3.5, 1, 9), Transparency = FX.nseq(0, 0.45, 1, 1), Color = FX.cseq(W.foam, W.spray),
		LightEmission = 0, Drag = 2, Rotation = FX.nr(0, 360), RotSpeed = FX.nr(-50, 50) })
	-- mist trailing behind
	boxEmitter(back, { Texture = FX.TEX.smoke, Rate = 45, Lifetime = FX.nr(1.2, 2), Speed = FX.nr(1, 4), EmissionDirection = TOP,
		SpreadAngle = Vector2.new(40, 40), Size = FX.nseq(0, 4, 1, 12), Transparency = FX.nseq(0, 0.75, 1, 1), Color = ColorSequence.new(W.spray),
		LightEmission = 0, Rotation = FX.nr(0, 360) })
	-- bubbles inside the body
	boxEmitter(inner, { Texture = FX.TEX.sparkle, Rate = 60, Lifetime = FX.nr(0.8, 1.4), Speed = FX.nr(1, 3), EmissionDirection = TOP,
		SpreadAngle = Vector2.new(20, 20), Size = FX.nseq(0, 0.4, 1, 0.1), Color = ColorSequence.new(W.foam), LightEmission = 0.7,
		Acceleration = Vector3.new(0, 5, 0) })
	local light = Instance.new("PointLight"); light.Color = W.light; light.Brightness = 3; light.Range = 30; light.Shadows = false
	light.Brightness = 2
	light.Parent = inner
	rig.light = light
	rig.loop = play(SFX.waveLoop, inner, 1.5, 0.9, { loop = true, near = 30 })
	return rig
end

local function waveCast(op)
	local dir = op.dir
	local size = op.size or Vector3.new(24, 12, 5)
	local groundCenter = op.from - Vector3.new(0, size.Y / 2, 0)
	-- the water erupts out of the ground
	waterSplash(groundCenter, dir, 1.4)
	for i = -2, 2 do
		local p = groundCenter + dir:Cross(Vector3.yAxis).Unit * (i * size.X / 5)
		local a = FX.anchor(FX.alignY(p, Vector3.yAxis), 3)
		FX.emitter(a, { Texture = FX.TEX.sparkle, EmissionDirection = TOP, SpreadAngle = Vector2.new(15, 15), Speed = FX.nr(30, 55),
			Lifetime = FX.nr(0.6, 1.1), Size = FX.nseq(0, 0.7, 1, 0.2), Color = FX.cseq(W.foam, W.light), LightEmission = 0.5,
			Acceleration = Vector3.new(0, -70, 0) }):Emit(30)
	end
	play(SFX.surge3, groundCenter, 1.8, 0.9)
	play(SFX.splash5, groundCenter, 1.2, 0.85)
	play(SFX.summon, groundCenter, 0.5, 0.8)
	if isLocal(op.caster) then
		Cam.kick("fov", 12, 0.08, 0.1, 0.7)
		Cam.kick("push", 1.6, 0.08, 0.1, 0.6)
		Cam.shake(0.45)
		Cam.grade({ tint = rgb(190, 225, 255), saturation = 0.1, contrast = 0.12, brightness = 0.05, release = 0.7 })
	end

	local rig = buildWaveRig(op)
	waves[op.id] = rig
	local basis = CFrame.lookAt(groundCenter, groundCenter + dir)
	local start = os.clock()
	local duration = op.duration or 5
	local speed = op.speed or 18
	local lastWet, lastSurge, lastRumble = 0, start, 0
	rig.conn = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local t = math.min(now - start, duration)
		local rise = math.clamp((now - start) / 0.4, 0, 1)
		rise = 1 - (1 - rise) ^ 3
		local cf = basis + dir * speed * t
		rig.cf = cf
		for _, part in ipairs(rig.parts) do
			local o = rig.offsets[part]
			local bob = math.sin(now * 5 + o.phase) * o.bob
			part.CFrame = cf * CFrame.new(0, -size.Y * (1 - rise), 0) * o.offset * CFrame.new(0, bob, 0)
		end
		rig.light.Brightness = 3 + math.sin(now * 7) * 0.8
		-- wet, foamy ground left behind
		if now - lastWet > 0.15 then
			lastWet = now
			local behind = cf.Position + dir * 1
			local g = groundHit(behind + Vector3.new(0, 2, 0), 8)
			if g then
				local wet = FX.part({ Size = Vector3.new(size.X * 0.9, 0.05, 4.5), CFrame = CFrame.lookAt(g.Position + g.Normal * 0.04, g.Position + g.Normal * 0.04 + dir, g.Normal),
					Material = GLASS, Color = W.deep, Transparency = 0.6, Reflectance = 0.35 })
				FX.tween(wet, 2.2, { Transparency = 1 }, Enum.EasingStyle.Linear, nil, 0.4)
				Debris:AddItem(wet, 2.7)
			end
		end
		if now - lastSurge > 1.6 then
			lastSurge = now
			play(SFX.surge1, cf.Position + Vector3.new(0, size.Y / 2, 0), 1.2, FX.rand(0.85, 1))
		end
		if now - lastRumble > 0.2 then
			lastRumble = now
			Cam.shakeAt(cf.Position, 0.12, 45)
		end
	end)
	task.delay(duration + 1.5, function()
		if waves[op.id] == rig then waves[op.id] = nil; if rig.conn then rig.conn:Disconnect() end end
	end)
end

local function waveHit(op)
	waterSplash(op.pos, op.dir, 1, SFX.poolSplash)
	if op.target == localPlayer.Character then
		Cam.shake(0.75)
		Cam.grade({ tint = rgb(160, 205, 255), saturation = -0.15, brightness = 0.1, contrast = 0.15, blur = 8, attack = 0.04, hold = 0.2, release = 0.8 })
		Cam.kick("roll", (math.random() < 0.5 and -1 or 1) * 6, 0.06, 0.05, 0.6)
	end
end

local function waveEnd(op)
	local rig = waves[op.id]
	waves[op.id] = nil
	local size = op.size or Vector3.new(24, 12, 5)
	local center = rig and rig.cf and rig.cf.Position or (op.pos - Vector3.new(0, size.Y / 2, 0))
	if rig then
		if rig.conn then rig.conn:Disconnect() end
		for _, e in ipairs(rig.emitters) do e.Enabled = false end
		fadeSound(rig.loop, 0.6)
		-- the wave crashes down
		for _, part in ipairs(rig.parts) do
			if part.Transparency < 1 then
				FX.tween(part, 0.55, { CFrame = part.CFrame * CFrame.new(0, -size.Y * 0.6, -2), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
			Debris:AddItem(part, 1.8)
		end
	end
	local front = center + op.dir * 3
	waterSplash(front + Vector3.new(0, 1, 0), op.dir, 1.8)
	local right = op.dir:Cross(Vector3.yAxis).Unit
	for i = -2, 2 do
		waterSplash(front + right * (i * size.X / 5) + Vector3.new(0, 1, 0), op.dir, 0.8)
	end
	local g = groundHit(front + Vector3.new(0, 3, 0), 10)
	if g then
		local foam = FX.part({ Shape = CYL, Size = Vector3.new(0.1, 4, 4), Material = Enum.Material.SmoothPlastic, Color = W.foam, Transparency = 0.2,
			CFrame = FX.alignY(g.Position + g.Normal * 0.05, g.Normal) * CFrame.Angles(0, 0, math.pi / 2) })
		FX.tween(foam, 1.2, { Size = Vector3.new(0.1, size.X * 1.3, size.X * 1.3), Transparency = 1 }, Enum.EasingStyle.Quart)
		Debris:AddItem(foam, 1.3)
	end
	play(SFX.splash1, front, 1.6, 0.8)
	play(SFX.surge1, front, 1.3, 0.75)
	play(SFX.slam, front, 0.4, 1.3)
	Cam.shakeAt(front, 0.7, 70)
end

---------------------------------------------------------------- dispatch
local handlers = {
	flame_cast = flameCast, flame_impact = flameImpact, burn = burn, burnend = burnEnd,
	freeze_cast = frostCast, freeze_impact = frostImpact, freeze = freeze, thaw = thaw,
	wave_cast = waveCast, wave_hit = waveHit, wave_end = waveEnd,
}
remote.OnClientEvent:Connect(function(op)
	if type(op) ~= "table" then return end
	local handler = handlers[op.op]
	if not handler then return end
	task.spawn(function()
		local ok, err = pcall(handler, op)
		if not ok then warn("[PresetSpellFX] " .. tostring(op.op) .. ": " .. tostring(err)) end
	end)
end)
