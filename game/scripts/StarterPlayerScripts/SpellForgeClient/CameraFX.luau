-- Layered camera effects on top of the normal Roblox camera: trauma shake, kicks
-- (FOV punch, push/pull, roll, pitch) and screen grades. Offsets are undone before the
-- default camera runs each frame, so they never drift or fight player control.
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local CameraFX = {}
local trauma = 0
local kicks, grades = {}, {}
local lastOffset = CFrame.identity
local lastFov = 0

local cc = Instance.new("ColorCorrectionEffect")
cc.Name = "SpellForge_Grade"
cc.Parent = Lighting
local blur = Instance.new("BlurEffect")
blur.Name = "SpellForge_Blur"
blur.Size = 0
blur.Parent = Lighting
local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
local bloomBase, bloomTouched = 0, false

local function envelope(k, t)
	if t < k.attack then return math.sin((t / k.attack) * math.pi / 2) end
	t -= k.attack
	if t < k.hold then return 1 end
	t -= k.hold
	if t < k.release then local x = 1 - t / k.release; return x * x end
	return nil
end

function CameraFX.shake(amount) trauma = math.min(1, trauma + amount) end

function CameraFX.proximity(pos, radius)
	local cam = workspace.CurrentCamera
	if not cam then return 0 end
	return math.clamp(1 - (cam.CFrame.Position - pos).Magnitude / radius, 0, 1)
end

function CameraFX.shakeAt(pos, amount, radius)
	local p = CameraFX.proximity(pos, radius)
	if p > 0 then CameraFX.shake(amount * math.sqrt(p)) end
	return p
end

function CameraFX.kick(kind, amount, attack, hold, release)
	table.insert(kicks, { kind = kind, amount = amount, start = os.clock(),
		attack = attack or 0.05, hold = hold or 0, release = release or 0.4 })
end

function CameraFX.grade(opts)
	opts.start = os.clock() + (opts.delay or 0)
	opts.attack = opts.attack or 0.03
	opts.hold = opts.hold or 0
	opts.release = opts.release or 0.4
	table.insert(grades, opts)
end

RunService:BindToRenderStep("SpellForge_CameraUndo", Enum.RenderPriority.Camera.Value - 1, function()
	local cam = workspace.CurrentCamera
	if cam and lastOffset ~= CFrame.identity then cam.CFrame = cam.CFrame * lastOffset:Inverse() end
	lastOffset = CFrame.identity
end)

RunService:BindToRenderStep("SpellForge_Camera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local cam = workspace.CurrentCamera
	if not cam then return end
	local now = os.clock()
	local fov, push, roll, pitch = 0, 0, 0, 0
	for i = #kicks, 1, -1 do
		local k = kicks[i]
		local e = envelope(k, now - k.start)
		if not e then table.remove(kicks, i) else
			local v = k.amount * e
			if k.kind == "fov" then fov += v elseif k.kind == "push" then push += v
			elseif k.kind == "roll" then roll += v elseif k.kind == "pitch" then pitch += v end
		end
	end
	if fov ~= 0 or lastFov ~= 0 then
		cam.FieldOfView = math.clamp(cam.FieldOfView - lastFov + fov, 5, 115)
		lastFov = fov
	end
	trauma = math.max(0, trauma - dt * 1.7)
	local s = trauma * trauma
	local offset = CFrame.identity
	if s > 1e-4 then
		local t = now * 26
		offset = CFrame.new(math.noise(t, 1.3) * s * 1.6, math.noise(t, 2.7) * s * 1.6, 0)
			* CFrame.Angles(math.noise(t, 4.1) * s * math.rad(9), math.noise(t, 5.9) * s * math.rad(9), math.noise(t, 7.3) * s * math.rad(12))
	end
	if push ~= 0 or roll ~= 0 or pitch ~= 0 then
		offset = CFrame.new(0, 0, -push) * CFrame.Angles(math.rad(pitch), 0, math.rad(roll)) * offset
	end
	if offset ~= CFrame.identity then
		cam.CFrame = cam.CFrame * offset
		lastOffset = offset
	end
	local b, c, sat, bl, bloomAdd = 0, 0, 0, 0, 0
	local tr, tg, tb = 0, 0, 0
	for i = #grades, 1, -1 do
		local g = grades[i]
		local age = now - g.start
		if age >= 0 then
			local e = envelope(g, age)
			if not e then table.remove(grades, i) else
				b += (g.brightness or 0) * e
				c += (g.contrast or 0) * e
				sat += (g.saturation or 0) * e
				bl += (g.blur or 0) * e
				bloomAdd += (g.bloom or 0) * e
				if g.tint then
					tr += (g.tint.R - 1) * e; tg += (g.tint.G - 1) * e; tb += (g.tint.B - 1) * e
				end
			end
		end
	end
	cc.Brightness = b
	cc.Contrast = c
	cc.Saturation = math.max(sat, -1)
	cc.TintColor = Color3.new(math.clamp(1 + tr, 0, 1), math.clamp(1 + tg, 0, 1), math.clamp(1 + tb, 0, 1))
	blur.Size = bl
	if bloom and bloom.Parent then
		if bloomAdd > 0.001 then
			if not bloomTouched then bloomBase = bloom.Intensity; bloomTouched = true end
			bloom.Intensity = bloomBase + bloomAdd * math.clamp(0.6 / math.max(bloomBase, 0.1), 0.15, 1)
		elseif bloomTouched then
			bloom.Intensity = bloomBase; bloomTouched = false
		end
	end
end)

return CameraFX
