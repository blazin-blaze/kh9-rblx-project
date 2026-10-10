-- Small toolkit for building client-side spell VFX (used by SpellForgeClient).
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local FX = {}

FX.TEX = {
	sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	spark = "rbxasset://textures/particles/fire_sparks_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	core = "rbxasset://textures/particles/explosion01_core_main.dds",
	shock = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
	burst = "rbxasset://textures/particles/explosion01_smoke_main.dds",
	implode = "rbxasset://textures/particles/explosion01_implosion_main.dds",
}

FX.SND = {
	whoosh = "rbxasset://sounds/Rocket whoosh 01.wav",
	launch = "rbxasset://sounds/Launching rocket.wav",
	shot = "rbxasset://sounds/Rocket shot.wav",
	collide = "rbxasset://sounds/collide.wav",
	ping = "rbxasset://sounds/electronicpingshort.wav",
	glass = "rbxasset://sounds/glassbreak.wav",
	thunder = "rbxasset://sounds/HalloweenThunder.wav",
	slash = "rbxasset://sounds/swordslash.wav",
	unsheath = "rbxasset://sounds/unsheath.wav",
}

local folder = workspace:FindFirstChild("SpellForge_Client")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "SpellForge_Client"
	folder.Parent = workspace
end
FX.folder = folder

local rng = Random.new()
function FX.rand(a, b) return rng:NextNumber(a, b) end
function FX.unit() return rng:NextUnitVector() end
function FX.nr(a, b) return NumberRange.new(a, b or a) end

function FX.nseq(...)
	local args = { ... }
	if #args == 1 then return NumberSequence.new(args[1]) end
	if #args == 2 then return NumberSequence.new(args[1], args[2]) end
	local kps = {}
	for i = 1, #args, 2 do table.insert(kps, NumberSequenceKeypoint.new(args[i], args[i + 1])) end
	return NumberSequence.new(kps)
end

function FX.cseq(...)
	local cs = { ... }
	if #cs == 1 then return ColorSequence.new(cs[1]) end
	local kps = {}
	for i, c in cs do table.insert(kps, ColorSequenceKeypoint.new((i - 1) / (#cs - 1), c)) end
	return ColorSequence.new(kps)
end

function FX.lookAt(from, to)
	local dir = to - from
	if dir.Magnitude < 1e-4 then return CFrame.new(from) end
	local up = math.abs(dir.Unit.Y) > 0.98 and Vector3.zAxis or Vector3.yAxis
	return CFrame.lookAt(from, to, up)
end

-- CFrame whose UpVector (Y) is `normal`
function FX.alignY(pos, normal)
	normal = (normal and normal.Magnitude > 1e-3) and normal.Unit or Vector3.yAxis
	local ref = math.abs(normal.Y) > 0.95 and Vector3.xAxis or Vector3.yAxis
	local right = ref:Cross(normal).Unit
	local back = right:Cross(normal).Unit
	return CFrame.fromMatrix(pos, right, normal, back)
end

function FX.part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local parent = folder
	if props.Shape then p.Shape = props.Shape end
	for k, v in props do
		if k == "Parent" then parent = v elseif k ~= "Shape" then p[k] = v end
	end
	p.Parent = parent
	return p
end

function FX.tween(inst, t, props, style, dir, delayTime)
	local tw = TweenService:Create(inst, TweenInfo.new(math.max(t, 0), style or Enum.EasingStyle.Quad,
		dir or Enum.EasingDirection.Out, 0, false, delayTime or 0), props)
	tw:Play()
	return tw
end

function FX.debris(inst, t) Debris:AddItem(inst, t) end

function FX.anchor(where, life)
	local cf = typeof(where) == "Vector3" and CFrame.new(where) or where
	local p = FX.part({ Size = Vector3.one * 0.2, Transparency = 1, CFrame = cf })
	local a = Instance.new("Attachment")
	a.Parent = p
	if life then Debris:AddItem(p, life) end
	return a, p
end

function FX.emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.LightInfluence = 0
	e.LockedToPart = false
	for k, v in props do e[k] = v end
	e.Parent = parent
	return e
end

function FX.sound(id, where, volume, speed, life)
	local parent = where
	if typeof(where) == "Vector3" then parent = FX.anchor(where, life or 6) end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 1
	s.PlaybackSpeed = speed or 1
	s.RollOffMinDistance = 20
	s.RollOffMaxDistance = 500
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, life or 6)
	return s
end

function FX.flashLight(pos, color, brightness, range, t)
	local a = FX.anchor(pos, t + 0.2)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	l.Parent = a
	FX.tween(l, t, { Brightness = 0, Range = range * 0.4 })
	return l
end

function FX.pop(pos, color, size0, size1, t, material, transparency0, style)
	local b = FX.part({
		Shape = Enum.PartType.Ball, Size = Vector3.one * size0, CFrame = CFrame.new(pos),
		Color = color, Material = material or Enum.Material.Neon, Transparency = transparency0 or 0,
	})
	FX.tween(b, t, { Size = Vector3.one * size1, Transparency = 1 }, style or Enum.EasingStyle.Quad)
	Debris:AddItem(b, t + 0.05)
	return b
end

function FX.ring(pos, normal, color, size0, size1, t, transparency0)
	local a = FX.anchor(FX.alignY(pos, normal), t + 0.3)
	local e = FX.emitter(a, {
		Texture = FX.TEX.shock,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Top,
		Speed = FX.nr(0.01),
		SpreadAngle = Vector2.zero,
		Lifetime = FX.nr(t),
		Size = FX.nseq(size0, size1),
		Transparency = FX.nseq(0, transparency0 or 0, 0.6, 0.35, 1, 1),
		Color = ColorSequence.new(color),
		LightEmission = 1,
		Brightness = 2,
		Rotation = FX.nr(0, 360),
		ZOffset = 0.5,
	})
	e:Emit(1)
	return e
end

function FX.disk(pos, normal, diameter, color, material, transparency, fadeDelay, fadeTime)
	local cf = FX.alignY(pos, normal) * CFrame.Angles(0, 0, math.pi / 2)
	local d = FX.part({
		Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, diameter, diameter),
		CFrame = cf, Color = color, Material = material or Enum.Material.SmoothPlastic,
		Transparency = transparency or 0,
	})
	FX.tween(d, fadeTime, { Transparency = 1 }, Enum.EasingStyle.Linear, nil, fadeDelay)
	Debris:AddItem(d, fadeDelay + fadeTime + 0.1)
	return d
end

function FX.characters()
	local list = { folder }
	for _, plr in Players:GetPlayers() do
		if plr.Character then table.insert(list, plr.Character) end
	end
	return list
end

function FX.ground(pos, depth)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = FX.characters()
	local hit = workspace:Raycast(pos + Vector3.new(0, 1, 0), Vector3.new(0, -(depth or 10), 0), params)
	local model = hit and hit.Instance:FindFirstAncestorWhichIsA("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then return nil end
	return hit
end

-- opts: color, material, speed, life, size, spread, transparency, collide, reflectance
function FX.shards(pos, normal, count, opts)
	for _ = 1, count do
		local dir = (normal + FX.unit() * (opts.spread or 1)).Unit
		local s = opts.size or 0.5
		local p = FX.part({
			Anchored = false,
			Size = Vector3.new(s * FX.rand(0.4, 1), s * FX.rand(0.4, 1), s * FX.rand(1, 2.2)),
			CFrame = FX.lookAt(pos, pos + dir),
			Color = opts.color,
			Material = opts.material or Enum.Material.Neon,
			Transparency = opts.transparency or 0,
			Reflectance = opts.reflectance or 0,
			CanCollide = opts.collide ~= false,
		})
		p.AssemblyLinearVelocity = dir * FX.rand(opts.speed * 0.45, opts.speed)
		p.AssemblyAngularVelocity = FX.unit() * FX.rand(5, 25)
		local life = FX.rand(opts.life * 0.6, opts.life)
		FX.tween(p, 0.35, { Transparency = 1, Size = p.Size * 0.2 }, nil, nil, math.max(life - 0.35, 0))
		Debris:AddItem(p, life)
	end
end

function FX.highlight(model, fill, outline, t)
	local h = Instance.new("Highlight")
	h.FillColor = fill
	h.OutlineColor = outline
	h.FillTransparency = 0.1
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Adornee = model
	h.Parent = folder
	FX.tween(h, t, { FillTransparency = 1, OutlineTransparency = 1 }, nil, nil, 0.05)
	Debris:AddItem(h, t + 0.15)
	return h
end

return FX
