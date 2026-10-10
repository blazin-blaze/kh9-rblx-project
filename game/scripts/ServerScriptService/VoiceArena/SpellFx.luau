-- ServerScriptService.VoiceArena.SpellFx (ModuleScript)
-- The sandboxed `fx` API that Gemini-written spells run against.
-- * Gemini's Luau only ever sees `fx` plus a few safe value types (Vector3, Color3, math...).
-- * The server owns gameplay: aiming, hits, damage caps and status effects.
-- * Every visual is streamed to clients through ReplicatedStorage.VoiceArena.FxDraw and
--   drawn by StarterPlayerScripts.SpellForgeClient.
-- * Failsafes: unknown fx functions are improvised from presets/primitives, bad arguments
--   fall back to sensible defaults, and loops/effects/time are budgeted so a spell can't hang.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Spells = require(script.Parent.SpellService)

local Fx = {}
local LIMITS = {
	codeLength = 6000, ops = 260, handles = 90, projectiles = 8, iterations = 4000,
	pause = 6, runtime = 10, damage = 45, heal = 30, shield = 4, blink = 30,
	range = 160, radius = 25, repeatCount = 24, particles = 150,
}
Fx.LIMITS = LIMITS

local folder = ReplicatedStorage:FindFirstChild("VoiceArena")
if not folder then
	folder = Instance.new("Folder"); folder.Name = "VoiceArena"; folder.Parent = ReplicatedStorage
end
local draw = folder:FindFirstChild("FxDraw") or Instance.new("RemoteEvent")
draw.Name = "FxDraw"; draw.Parent = folder

local STOP = "SpellForge:stop"

---------------------------------------------------------------- static checks
local BANNED = {}
for _, word in ipairs({ "game", "workspace", "Workspace", "script", "require", "getfenv", "setfenv",
	"loadstring", "rawset", "rawget", "rawequal", "setmetatable", "getmetatable", "debug", "coroutine",
	"_G", "shared", "Instance", "task", "wait", "spawn", "delay", "while", "repeat", "goto", "string",
	"os", "utf8", "buffer", "newproxy", "plugin", "pcall", "xpcall", "error", "collectgarbage", "gcinfo" }) do
	BANNED[word] = true
end
local BANNED_MEMBERS = { rep = true }

-- One pass over the source: skips strings/comments, rejects forbidden identifiers, and
-- injects `__tick()` after every `do` so no loop can run forever. Line numbers are kept.
local function scan(code)
	local out, problems, seen = {}, {}, {}
	local function problem(text) if not seen[text] then seen[text] = true; table.insert(problems, text) end end
	local i, n = 1, #code
	local prevSig, prev2 = "", ""
	while i <= n do
		local c = string.sub(code, i, i)
		if c == "-" and string.sub(code, i + 1, i + 1) == "-" then
			local level = string.match(code, "^%-%-%[(=*)%[", i)
			local stopAt
			if level then
				local close = "]" .. level .. "]"
				local e = string.find(code, close, i, true)
				stopAt = e and e + #close - 1 or n
				local body = string.sub(code, i, stopAt)
				table.insert(out, (string.gsub(body, "[^\n]", " ")))
			else
				local e = string.find(code, "\n", i, true)
				stopAt = e and e - 1 or n
			end
			i = stopAt + 1
		elseif c == "[" and string.match(code, "^%[=*%[", i) then
			local level = string.match(code, "^%[(=*)%[", i)
			local close = "]" .. level .. "]"
			local e = string.find(code, close, i, true)
			local stopAt = e and e + #close - 1 or n
			table.insert(out, string.sub(code, i, stopAt))
			i = stopAt + 1; prev2 = prevSig; prevSig = "s"
		elseif c == '"' or c == "'" then
			local j = i + 1
			while j <= n do
				local d = string.sub(code, j, j)
				if d == "\\" then j += 2
				elseif d == c or d == "\n" then break
				else j += 1 end
			end
			table.insert(out, string.sub(code, i, j))
			i = j + 1; prev2 = prevSig; prevSig = "s"
		elseif c == "`" then
			problem("use normal quotes instead of backtick strings")
			table.insert(out, c); i += 1
		elseif string.match(c, "[%a_]") then
			local word = string.match(code, "^[%a_][%w_]*", i)
			local member = (prevSig == "." and prev2 ~= ".") or prevSig == ":"
			if member then
				if BANNED_MEMBERS[word] then problem("`:" .. word .. "` is not allowed") end
			elseif BANNED[word] then
				problem("`" .. word .. "` is not allowed")
			elseif string.sub(word, 1, 2) == "__" then
				problem("names starting with __ are not allowed")
			end
			table.insert(out, word)
			if word == "do" and not member then table.insert(out, " __tick()") end
			i += #word; prev2 = prevSig; prevSig = "w"
		else
			table.insert(out, c)
			if not string.match(c, "%s") then prev2 = prevSig; prevSig = c end
			i += 1
		end
	end
	return table.concat(out), problems
end

-- Returns a compiled function, or nil + a readable error ("LOADSTRING_DISABLED" if Roblox blocks it).
function Fx.Compile(code)
	if type(code) ~= "string" or not string.find(code, "%S") then return nil, "The spell has no code" end
	if #code > LIMITS.codeLength then
		return nil, "The code is too long (max " .. LIMITS.codeLength .. " characters)"
	end
	local instrumented, problems = scan(code)
	if #problems > 0 then return nil, "Rule violation: " .. table.concat(problems, "; ") end
	local ok, fn, err = pcall(loadstring, instrumented, "=GeminiSpell")
	if not ok then return nil, "LOADSTRING_DISABLED" end
	if not fn then return nil, "Syntax error: " .. tostring(err) end
	return fn
end

---------------------------------------------------------------- value helpers
local NAMED_COLORS = {
	red = Color3.fromRGB(255, 60, 50), orange = Color3.fromRGB(255, 140, 30), yellow = Color3.fromRGB(255, 225, 60),
	green = Color3.fromRGB(60, 230, 90), lime = Color3.fromRGB(170, 255, 60), cyan = Color3.fromRGB(70, 230, 255),
	teal = Color3.fromRGB(30, 200, 180), blue = Color3.fromRGB(60, 120, 255), navy = Color3.fromRGB(30, 50, 160),
	purple = Color3.fromRGB(160, 80, 255), violet = Color3.fromRGB(190, 110, 255), magenta = Color3.fromRGB(255, 60, 220),
	pink = Color3.fromRGB(255, 120, 200), white = Color3.fromRGB(255, 255, 255), black = Color3.fromRGB(25, 20, 30),
	gray = Color3.fromRGB(150, 150, 160), grey = Color3.fromRGB(150, 150, 160), gold = Color3.fromRGB(255, 200, 50),
	silver = Color3.fromRGB(210, 215, 225), brown = Color3.fromRGB(130, 85, 50),
}
local handles = setmetatable({}, { __mode = "k" }) -- handle proxy -> data

local function finite(x) return x == x and x ~= math.huge and x ~= -math.huge end
local function num(v, default, lo, hi)
	v = tonumber(v)
	if v == nil or not finite(v) then v = default end
	if v == nil then return nil end
	if lo and v < lo then v = lo end
	if hi and v > hi then v = hi end
	return v
end
local function vec(v, default)
	local t = typeof(v)
	local result
	if t == "Vector3" then result = v
	elseif t == "CFrame" then result = v.Position
	elseif t == "table" then
		local h = handles[v]
		if h then return h.pos end
		local x, y, z = tonumber(v.X or v.x or v[1]), tonumber(v.Y or v.y or v[2]), tonumber(v.Z or v.z or v[3])
		if x and y and z then result = Vector3.new(x, y, z) end
	end
	if result and finite(result.X) and finite(result.Y) and finite(result.Z) and result.Magnitude < 1e5 then
		return result
	end
	return default
end
local function color(v, default)
	local t = typeof(v)
	if t == "Color3" then return v end
	if t == "BrickColor" then return v.Color end
	if t == "string" then return NAMED_COLORS[string.lower(v)] or default end
	if t == "table" and not handles[v] then
		local r, g, b = tonumber(v.R or v.r or v[1]), tonumber(v.G or v.g or v[2]), tonumber(v.B or v.b or v[3])
		if r and g and b then
			if r > 1 or g > 1 or b > 1 then return Color3.fromRGB(math.clamp(r, 0, 255), math.clamp(g, 0, 255), math.clamp(b, 0, 255)) end
			return Color3.new(math.clamp(r, 0, 1), math.clamp(g, 0, 1), math.clamp(b, 0, 1))
		end
	end
	return default
end
local function size3(v, default)
	local n = tonumber(v)
	if n and finite(n) then local s = math.clamp(n, 0.05, 60); return Vector3.new(s, s, s) end
	local s = vec(v, nil)
	if s then return Vector3.new(math.clamp(math.abs(s.X), 0.05, 60), math.clamp(math.abs(s.Y), 0.05, 60), math.clamp(math.abs(s.Z), 0.05, 60)) end
	return default
end
local function dirOf(v, default)
	local d = vec(v, nil)
	if d and d.Magnitude > 1e-3 then return d.Unit end
	return default
end
local function str(v, default)
	if type(v) == "string" then return string.lower(string.sub(v, 1, 32)) end
	return default
end
local function isOpts(v) return type(v) == "table" and not handles[v] and vec(v, nil) == nil and color(v, nil) == nil end

---------------------------------------------------------------- status effects
local slows = setmetatable({}, { __mode = "k" })
local function slow(h, seconds)
	local s = slows[h]
	if s then s.untilTime = math.max(s.untilTime, os.clock() + seconds); return end
	s = { untilTime = os.clock() + seconds, original = h.WalkSpeed, speed = h.WalkSpeed * 0.45 }
	slows[h] = s
	h.WalkSpeed = s.speed
	task.spawn(function()
		while h.Parent and h.Health > 0 and os.clock() < s.untilTime do task.wait(0.1) end
		if h.Parent and h.WalkSpeed == s.speed then h.WalkSpeed = s.original end
		slows[h] = nil
	end)
end
local function push(root, h, horizontal, speed, upSpeed)
	if root.Anchored then return end
	local flat = Vector3.new(horizontal.X, 0, horizontal.Z)
	flat = flat.Magnitude > 1e-3 and flat.Unit or Vector3.zero
	pcall(function() root:SetNetworkOwner(nil) end)
	pcall(function() h:ChangeState(Enum.HumanoidStateType.FallingDown) end)
	root.AssemblyLinearVelocity = flat * speed + Vector3.new(0, upSpeed, 0)
	task.delay(0.9, function()
		if root.Parent and not root.Anchored then pcall(function() root:SetNetworkOwnershipAuto() end) end
	end)
end
local function applyStatus(model, h, root, status, fromPos)
	if type(status) ~= "string" then return end
	status = string.lower(status)
	if status == "burn" or status == "fire" or status == "ignite" then Spells.Burn(model, 3)
	elseif status == "freeze" or status == "frozen" or status == "stun" then Spells.Freeze(model, 2)
	elseif status == "slow" or status == "chill" then slow(h, 3)
	elseif status == "knockback" or status == "push" then push(root, h, root.Position - fromPos, 60, 25)
	elseif status == "launch" or status == "lift" or status == "knockup" then push(root, h, Vector3.zero, 0, 65)
	elseif status == "pull" then push(root, h, fromPos - root.Position, 45, 14)
	end
end

---------------------------------------------------------------- handle proxies
local handleMeta
handleMeta = {
	__index = function(self, key)
		local d = handles[self]
		if not d then return nil end
		key = string.lower(tostring(key))
		if key == "position" or key == "pos" then return d.pos end
		if key == "size" then return d.size end
		if key == "color" then return d.color end
		return nil
	end,
	__newindex = function(self, key, value)
		local d = handles[self]
		if not d then return end
		key = string.lower(tostring(key))
		if key == "position" or key == "pos" then
			local p = vec(value, nil)
			if p then d.pos = p; d.send({ op = "move", id = d.id, pos = p, t = 0 }) end
		elseif key == "size" then
			local s = size3(value, nil)
			if s then d.size = s; d.send({ op = "tween", id = d.id, t = 0, size = s }) end
		elseif key == "color" then
			local c = color(value, nil)
			if c then d.color = c; d.send({ op = "color", id = d.id, color = c, t = 0 }) end
		elseif key == "transparency" then
			d.send({ op = "tween", id = d.id, t = 0, transparency = num(value, 0, 0, 1) })
		end
	end,
	__tostring = function() return "FxHandle" end,
	__metatable = "locked",
}

---------------------------------------------------------------- the runner
local function characterOf(player)
	local c = player and player.Character
	return c, c and c:FindFirstChildOfClass("Humanoid"), c and c:FindFirstChild("HumanoidRootPart")
end

local function humanoidModel(part, caster)
	local model = part and part:FindFirstAncestorOfClass("Model")
	while model and not model:FindFirstChildOfClass("Humanoid") do
		model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model")
	end
	if not model or model == caster then return nil end
	local h, r = model:FindFirstChildOfClass("Humanoid"), model:FindFirstChild("HumanoidRootPart")
	if h and r and h.Health > 0 then return model, h, r end
	return nil
end

local castCounter = 0

-- Runs spell code. options.dry = true validates without visuals, damage or waiting.
-- Returns ok, errorMessage, logLines.
function Fx.Run(player, code, direction, options)
	options = options or {}
	local dry = options.dry == true
	if not dry and folder:GetAttribute("MatchState") == "Victory" then return false, "A cinematic is playing", {} end
	local fn, compileErr = Fx.Compile(code)
	if not fn then return false, compileErr, {} end
	local character, humanoid, root = characterOf(player)
	if not dry and not (humanoid and root and humanoid.Health > 0) then return false, "Respawn first", {} end

	castCounter += 1
	local castId = castCounter
	local casterPos = root and root.Position or Vector3.new(0, 5, 0)
	direction = dirOf(direction, root and root.CFrame.LookVector or Vector3.new(0, 0, -1))
	local origin = casterPos + Vector3.new(0, 1, 0) + direction * 2
	local right = direction:Cross(Vector3.yAxis)
	right = right.Magnitude > 1e-3 and right.Unit or Vector3.xAxis
	local up = right:Cross(direction).Unit
	local deadline = os.clock() + LIMITS.runtime
	local ops, iterations, pauseUsed, projectiles, handleCount, nextId = 0, 0, 0, 0, 0, 0
	local healUsed, shieldUsed = 0, 0
	local pending, asyncCount = 0, 0
	local damageTaken = {}
	local log = {}

	local function stop(reason) error(STOP .. " " .. reason, 0) end
	local function tick()
		ops += 1
		if ops > LIMITS.ops then stop("used too many effects") end
		if not dry then
			if os.clock() > deadline then stop("ran too long") end
			if humanoid and humanoid.Health <= 0 then stop("ended because the caster died") end
		end
	end
	local function loopTick()
		iterations += 1
		if iterations > LIMITS.iterations then stop("ran a loop too many times") end
		if not dry and os.clock() > deadline then stop("ran too long") end
	end
	local function send(op)
		if dry then return end
		op.cast = castId
		draw:FireAllClients(op)
	end
	local function newId() nextId += 1; return nextId end
	local function note(text)
		if #log < 25 then table.insert(log, text) end
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }
	local function aimPoint(range, from, dir)
		from, dir = from or origin, dir or direction
		local hit = workspace:Raycast(from, dir * range, rayParams)
		return hit and hit.Position or from + dir * range, hit
	end
	local function ground(pos)
		local hit = workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -40, 0), rayParams)
		if hit and not humanoidModel(hit.Instance, character) then return hit.Position end
		return pos
	end
	local function enemiesIn(pos, radius)
		local list, found = {}, {}
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Exclude
		overlap.FilterDescendantsInstances = { character }
		for _, part in ipairs(workspace:GetPartBoundsInRadius(pos, radius, overlap)) do
			local model, h, r = humanoidModel(part, character)
			if model and not found[model] then
				found[model] = true
				table.insert(list, { model, h, r })
			end
		end
		return list
	end
	local function hurt(model, h, r, amount, status, fromPos)
		if dry then return end
		local used = damageTaken[h] or 0
		local allowed = math.max(0, math.min(amount or 0, LIMITS.damage - used))
		if allowed > 0 then h:TakeDamage(allowed); damageTaken[h] = used + allowed end
		applyStatus(model, h, r, status, fromPos)
	end
	local function damageArea(pos, radius, amount, status, skip)
		local list = enemiesIn(pos, radius)
		for _, e in ipairs(list) do
			if e[1] ~= skip then hurt(e[1], e[2], e[3], amount, status, pos) end
		end
		return #list
	end
	local function presetArgs(position, opts, defaultPos)
		if opts == nil and isOpts(position) then opts = position; position = opts.position or opts.at end
		opts = type(opts) == "table" and not handles[opts] and opts or {}
		return vec(position, nil) or defaultPos(), opts
	end
	local function maybeDamage(opts, pos, radius, skip)
		local dmg = num(opts.damage, 0, 0, LIMITS.damage)
		if dmg > 0 or type(opts.status) == "string" then
			return damageArea(pos, num(opts.radius, radius, 1, LIMITS.radius), dmg, opts.status, skip)
		end
		return 0
	end
	local function makeHandle(kind, pos, size, col)
		handleCount += 1
		if handleCount > LIMITS.handles then stop("created too many objects") end
		local h = setmetatable({}, handleMeta)
		local id = newId()
		handles[h] = { id = id, pos = pos, size = size, color = col, kind = kind, send = send }
		return h, id
	end

	local api = {}

	-------------------------------------------------- preset effects
	function api.Projectile(opts)
		opts = isOpts(opts) and opts or {}
		projectiles += 1
		if projectiles > LIMITS.projectiles then stop("fired too many projectiles") end
		local from = vec(opts.from or opts.origin or opts.start or opts.position, origin)
		local target = vec(opts.to or opts.target, nil)
		local dir = target and dirOf(target - from, direction) or dirOf(opts.direction, direction)
		local speed = num(opts.speed, 90, 20, 180)
		local range = num(opts.range, 120, 5, LIMITS.range)
		local size = num(opts.size, 1.6, 0.4, 6)
		local gravity = num(opts.gravity, 0, 0, 1) * workspace.Gravity * 0.5
		local style, col = str(opts.style or opts.element, nil), color(opts.color, nil)
		local id = newId()
		send({ op = "projectile", id = id, from = from, dir = dir, speed = speed, range = range, size = size,
			gravity = gravity, style = style, color = col, caster = player.UserId })
		local hitPos, hitNormal, hitModel, hitH, hitR
		if dry then
			hitPos = aimPoint(math.min(range, 60), from, dir)
		else
			local accel = Vector3.new(0, -gravity, 0)
			local radius = math.max(0.4, size * 0.5)
			local t, last = 0, from
			while true do
				t += RunService.Heartbeat:Wait()
				if os.clock() > deadline then stop("ran too long") end
				local pos = from + dir * speed * t + accel * (0.5 * t * t)
				local step = pos - last
				if step.Magnitude > 1e-4 then
					local hit = workspace:Spherecast(last, radius, step, rayParams)
					if hit then
						hitPos, hitNormal = hit.Position, hit.Normal
						hitModel, hitH, hitR = humanoidModel(hit.Instance, character)
						break
					end
				end
				last = pos
				if speed * t >= range or t > 6 then hitPos = pos; break end
			end
		end
		send({ op = "impact", id = id, pos = hitPos, normal = hitNormal, style = style, color = col, size = size, hit = hitModel ~= nil })
		local dmg = num(opts.damage, 0, 0, LIMITS.damage)
		if dmg > 0 or type(opts.status) == "string" then
			if hitModel then hurt(hitModel, hitH, hitR, dmg, opts.status, hitPos - dir * 2) end
			local radius = num(opts.radius, 0, 0, LIMITS.radius)
			if radius > 0 then damageArea(hitPos, radius, dmg, opts.status, hitModel) end
		end
		return hitPos, hitModel ~= nil
	end

	function api.Explosion(position, opts)
		local pos
		pos, opts = presetArgs(position, opts, function() return aimPoint(80) end)
		local radius = num(opts.radius or opts.size, 8, 2, LIMITS.radius)
		send({ op = "explosion", pos = pos, radius = radius, style = str(opts.style or opts.element), color = color(opts.color) })
		return maybeDamage(opts, pos, radius)
	end

	function api.Lightning(from, to, opts)
		if opts == nil and isOpts(to) then opts = to; to = nil end
		if opts == nil and to == nil and isOpts(from) then opts = from; from = opts.from; to = opts.to end
		opts = type(opts) == "table" and opts or {}
		local a = vec(from, origin)
		local b = vec(to, nil) or aimPoint(100)
		local delta = b - a
		local hit = delta.Magnitude > 0.1 and workspace:Raycast(a, delta, rayParams)
		if hit then b = hit.Position end
		send({ op = "lightning", from = a, to = b, color = color(opts.color), width = num(opts.width, 1, 0.2, 4), caster = player.UserId })
		local model, h, r
		if hit then model, h, r = humanoidModel(hit.Instance, character) end
		local dmg = num(opts.damage, 0, 0, LIMITS.damage)
		if model and (dmg > 0 or opts.status) then hurt(model, h, r, dmg, opts.status, a) end
		maybeDamage(opts, b, 4, model)
		return b
	end

	function api.SkyStrike(position, opts)
		local pos
		pos, opts = presetArgs(position, opts, function() return aimPoint(90) end)
		pos = ground(pos)
		send({ op = "skystrike", pos = pos, color = color(opts.color), radius = num(opts.radius, 6, 2, LIMITS.radius) })
		return maybeDamage(opts, pos, 6)
	end

	function api.Nova(position, opts)
		local pos
		pos, opts = presetArgs(position, opts, function() return casterPos end)
		local radius = num(opts.radius or opts.size, 14, 3, LIMITS.radius)
		send({ op = "nova", pos = ground(pos), radius = radius, style = str(opts.style or opts.element), color = color(opts.color) })
		return maybeDamage(opts, pos, radius)
	end

	function api.Spikes(position, opts)
		local pos
		pos, opts = presetArgs(position, opts, function() return aimPoint(70) end)
		pos = ground(pos)
		local radius = num(opts.radius, 5, 1, 16)
		send({ op = "spikes", pos = pos, radius = radius, count = math.floor(num(opts.count, 7, 1, 16)),
			height = num(opts.height, 6, 2, 16), style = str(opts.style or opts.element), color = color(opts.color) })
		return maybeDamage(opts, pos, radius + 2)
	end

	function api.Aura(opts)
		opts = isOpts(opts) and opts or { color = opts }
		send({ op = "aura", caster = player.UserId, color = color(opts.color), style = str(opts.style or opts.element),
			duration = num(opts.duration, 3, 0.3, 6), radius = num(opts.radius, 6, 2, 14) })
	end

	function api.Shield(seconds, col)
		if isOpts(seconds) then col = seconds.color; seconds = seconds.duration or seconds.seconds end
		local s = math.min(num(seconds, 2, 0.2, LIMITS.shield), LIMITS.shield - shieldUsed)
		if s <= 0 then return end
		shieldUsed += s
		send({ op = "shield", caster = player.UserId, duration = s, color = color(col) })
		if not dry and character then
			local ff = Instance.new("ForceField")
			ff.Visible = false
			ff.Parent = character
			task.delay(s, function() ff:Destroy() end)
		end
	end

	function api.Heal(amount, col)
		if isOpts(amount) then col = amount.color; amount = amount.amount end
		local a = math.min(num(amount, 15, 0, LIMITS.heal), LIMITS.heal - healUsed)
		if a <= 0 then return end
		healUsed += a
		send({ op = "heal", caster = player.UserId, color = color(col), amount = a })
		if not dry and humanoid and humanoid.Health > 0 then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + a)
		end
	end

	function api.Blink(distance, col)
		if isOpts(distance) then col = distance.color; distance = distance.distance end
		local d = num(distance, 15, 2, LIMITS.blink)
		local flat = Vector3.new(direction.X, 0, direction.Z)
		flat = flat.Magnitude > 1e-3 and flat.Unit or Vector3.new(0, 0, -1)
		local from = root and root.Position or casterPos
		local hit = workspace:Raycast(from, flat * d, rayParams)
		local dest = hit and hit.Position - flat * 3 or from + flat * d
		send({ op = "blink", from = from, to = dest, color = color(col), caster = player.UserId })
		if not dry and character and root then
			character:PivotTo(CFrame.lookAt(dest, dest + flat))
			casterPos = dest
			origin = dest + Vector3.new(0, 1, 0) + direction * 2
		end
		return dest
	end

	function api.Shake(intensity, position)
		send({ op = "shake", intensity = num(intensity, 0.5, 0, 1), pos = vec(position, nil) })
	end

	function api.Flash(col, intensity, position)
		send({ op = "flash", color = color(col, Color3.new(1, 1, 1)), intensity = num(intensity, 0.5, 0, 1), pos = vec(position, nil) })
	end

	function api.Sound(name, position)
		send({ op = "sound", name = str(name, "magic"), pos = vec(position, casterPos) })
	end

	-------------------------------------------------- primitives (custom effects)
	function api.Ball(position, size, col, duration)
		if isOpts(position) then
			local o = position
			position, size, col, duration = o.position, o.size, o.color, o.duration
		end
		local pos = vec(position, origin)
		local s = size3(size, Vector3.new(2, 2, 2))
		local c = color(col, Color3.fromRGB(170, 120, 255))
		local h, id = makeHandle("ball", pos, s, c)
		send({ op = "ball", id = id, pos = pos, size = s, color = c, duration = num(duration, nil, 0.05, 8) })
		return h
	end

	function api.Block(position, size, col, duration)
		if isOpts(position) then
			local o = position
			position, size, col, duration = o.position, o.size, o.color, o.duration
		end
		local pos = vec(position, origin)
		local s = size3(size, Vector3.new(2, 2, 2))
		local c = color(col, Color3.fromRGB(170, 120, 255))
		local h, id = makeHandle("block", pos, s, c)
		send({ op = "block", id = id, pos = pos, size = s, color = c, duration = num(duration, nil, 0.05, 8),
			look = direction })
		return h
	end

	function api.Beam(from, to, width, col, duration)
		if isOpts(from) then
			local o = from
			from, to, width, col, duration = o.from, o.to, o.width, o.color, o.duration
		end
		local a = vec(from, origin)
		local b = vec(to, nil) or aimPoint(80)
		local c = color(col, Color3.fromRGB(170, 120, 255))
		local h, id = makeHandle("beam", (a + b) / 2, nil, c)
		send({ op = "beam", id = id, from = a, to = b, width = num(width, 0.6, 0.05, 8), color = c,
			duration = num(duration, nil, 0.05, 8) })
		return h
	end

	function api.Ring(position, radius, col, duration)
		if isOpts(position) then
			local o = position
			position, radius, col, duration = o.position, o.radius, o.color, o.duration
		end
		send({ op = "ring", pos = vec(position, casterPos), radius = num(radius, 8, 0.5, 40),
			color = color(col, Color3.fromRGB(170, 120, 255)), duration = num(duration, 0.6, 0.1, 4) })
	end

	function api.Particles(position, opts)
		if opts == nil and isOpts(position) then opts = position; position = opts.position end
		if not isOpts(opts) then opts = { color = opts } end
		send({ op = "particles", pos = vec(position, origin), color = color(opts.color, Color3.fromRGB(170, 120, 255)),
			texture = str(opts.texture, "sparkle"), count = math.floor(num(opts.count or opts.amount, 30, 1, LIMITS.particles)),
			speed = num(opts.speed, 15, -120, 120), size = num(opts.size, 0.6, 0.05, 12), lifetime = num(opts.lifetime, 0.8, 0.1, 4) })
	end

	function api.Spark(position, col, count)
		api.Particles(position, { color = col, count = count or 25, texture = "sparkle", speed = 20 })
	end

	function api.Light(position, col, range, duration)
		send({ op = "light", pos = vec(position, origin), color = color(col, Color3.new(1, 1, 1)),
			range = num(range, 16, 2, 60), duration = num(duration, 0.6, 0.05, 8) })
	end

	function api.Move(h, position, time)
		local d = handles[h]
		if not d then note("fx:Move was given something that isn't an fx object"); return end
		local pos = vec(position, nil)
		if not pos then return end
		d.pos = pos
		send({ op = "move", id = d.id, pos = pos, t = num(time, 0.3, 0, 6) })
	end

	function api.Tween(h, time, size, transparency)
		local d = handles[h]
		if not d then note("fx:Tween was given something that isn't an fx object"); return end
		local s = size3(size, nil)
		if s then d.size = s end
		send({ op = "tween", id = d.id, t = num(time, 0.3, 0, 6), size = s, transparency = num(transparency, nil, 0, 1) })
	end

	function api.Color(h, col, time)
		local d = handles[h]
		if not d then return end
		local c = color(col, nil)
		if not c then return end
		d.color = c
		send({ op = "color", id = d.id, color = c, t = num(time, 0.3, 0, 6) })
	end

	function api.Destroy(h)
		local d = handles[h]
		if d then send({ op = "destroy", id = d.id }) end
	end
	api.Remove = api.Destroy

	-------------------------------------------------- flow + helpers
	function api.Pause(seconds)
		local s = math.min(num(seconds, 0.1, 0, 3), LIMITS.pause - pauseUsed)
		if s <= 0 then return end
		pauseUsed += s
		if not dry then task.wait(s) end
	end
	api.Wait = api.Pause

	function api.Repeat(count, fn)
		if type(count) == "function" and fn == nil then count, fn = 1, count end
		if type(fn) ~= "function" then return end
		for i = 1, math.floor(num(count, 1, 0, LIMITS.repeatCount)) do
			loopTick()
			fn(i)
		end
	end

	-- Runs part of the spell at the same time as the rest (e.g. several projectiles at once).
	function api.Async(fn)
		if type(fn) ~= "function" then return end
		asyncCount += 1
		if asyncCount > 12 then stop("started too many async effects") end
		if dry then fn(); return end
		pending += 1
		task.spawn(function()
			local ok, err = pcall(fn)
			pending -= 1
			if not ok then
				local message = tostring(err)
				if string.sub(message, 1, #STOP) ~= STOP then note("an async part failed: " .. message) end
			end
		end)
	end

	function api.Random(a, b)
		a, b = num(a, 0), num(b, nil)
		if b == nil then a, b = 0, a end
		if a > b then a, b = b, a end
		return a + math.random() * (b - a)
	end

	function api.Aim(range)
		return (aimPoint(num(range, 100, 1, LIMITS.range)))
	end

	function api.FindEnemy(range)
		local r = num(range, 80, 5, LIMITS.range)
		local best, bestDist
		for _, e in ipairs(enemiesIn(casterPos, r)) do
			local offset = e[3].Position - casterPos
			local dist = offset.Magnitude
			if dist > 0.5 and offset.Unit:Dot(direction) > 0.3 and (not bestDist or dist < bestDist) then
				best, bestDist = e[3].Position, dist
			end
		end
		return best
	end

	function api.Damage(position, radius, amount, status)
		if isOpts(position) then
			local o = position
			position, radius, amount, status = o.position, o.radius, o.damage or o.amount, o.status
		end
		local pos = vec(position, nil) or aimPoint(80)
		return damageArea(pos, num(radius, 6, 0.5, LIMITS.radius), num(amount, 10, 0, LIMITS.damage), status)
	end

	function api.Forward(distance)
		return origin + direction * num(distance, 10, -LIMITS.range, LIMITS.range)
	end

	function api.Ground(position)
		return ground(vec(position, nil) or aimPoint(80))
	end

	function api.PositionOf(h)
		local d = handles[h]
		return d and d.pos or vec(h, nil)
	end

	function api.Log(...)
		local parts = {}
		for i = 1, math.min(select("#", ...), 8) do parts[i] = tostring((select(i, ...))) end
		note("log: " .. string.sub(table.concat(parts, " "), 1, 200))
	end

	-------------------------------------------------- build the fx object
	local fx = {}
	local lowerNames = {}
	local function wrap(name, f)
		return function(first, ...)
			tick()
			if first == fx then return f(...) end
			return f(first, ...)
		end
	end
	for name, f in pairs(api) do
		fx[name] = wrap(name, f)
		lowerNames[string.lower(name)] = fx[name]
	end
	fx.origin, fx.direction, fx.forward = origin, direction, direction
	fx.caster, fx.position = casterPos, casterPos
	fx.right, fx.up = right, up

	-- FAILSAFE: Gemini called an effect that doesn't exist (e.g. fx:Tornado). Map it to the
	-- closest preset by name, or build a custom effect out of primitives, instead of crashing.
	local function improvise(name)
		return wrap(name, function(...)
			local pos, col, number
			for i = 1, select("#", ...) do
				local a = select(i, ...)
				if type(a) == "table" and not handles[a] and isOpts(a) then
					pos = pos or vec(a.position or a.at or a.to or a.target, nil)
					col = col or color(a.color, nil)
				end
				pos = pos or vec(a, nil)
				col = col or (typeof(a) == "Color3" and a) or nil
				number = number or (type(a) == "number" and a) or nil
			end
			pos = pos or aimPoint(60)
			col = col or Color3.fromRGB(170, 120, 255)
			local lname = string.lower(name)
			local function has(...)
				for _, k in ipairs({ ... }) do if string.find(lname, k, 1, true) then return true end end
				return false
			end
			local made, result
			if has("heal", "regen", "cure", "restore") then api.Heal(number or 15, col); made = "a heal"
			elseif has("shield", "barrier", "protect", "guard", "armor") then api.Shield(number or 2, col); made = "a shield"
			elseif has("teleport", "blink", "dash", "warp") then result = api.Blink(number or 15, col); made = "a blink"
			elseif has("bolt", "lightning", "thunder", "zap", "shock", "electr", "laser", "ray") then
				result = api.Lightning(origin, pos, { color = col }); made = "a lightning bolt"
			elseif has("spike", "shard", "crystal", "pillar", "thorn") then api.Spikes(pos, { color = col }); made = "spikes"
			elseif has("nova", "ring", "pulse", "shockwave", "wave", "stomp", "quake") then api.Nova(pos, { color = col }); made = "a shockwave"
			elseif has("explo", "blast", "boom", "burst", "bomb", "meteor", "detonate") then api.Explosion(pos, { color = col }); made = "an explosion"
			elseif has("shoot", "fire", "launch", "throw", "cast", "missile", "orb") then
				result = api.Projectile({ color = col, to = pos }); made = "a projectile"
			elseif has("shake") then api.Shake(0.6, pos); made = "camera shake"
			elseif has("flash") then api.Flash(col, 0.6); made = "a flash"
			elseif has("sound", "play", "sfx", "noise") then api.Sound("magic", pos); made = "a sound"
			elseif has("wait", "sleep", "delay") then api.Pause(number or 0.3); made = "a pause"
			else
				-- Nothing matches: compose a brand-new effect from primitives.
				local core = api.Ball(pos, 3, col)
				api.Tween(core, 0.35, 7, 1)
				api.Ring(pos, 9, col, 0.6)
				api.Particles(pos, { color = col, texture = "sparkle", count = 45, speed = 18 })
				api.Light(pos, col, 18, 0.6)
				result = core
				made = "a custom glow burst"
			end
			note(("fx:%s doesn't exist, so it was improvised as %s"):format(name, made))
			return result
		end)
	end
	setmetatable(fx, {
		__index = function(_, key)
			if type(key) ~= "string" then return nil end
			local known = lowerNames[string.lower(key)]
			if known then return known end
			local lower = string.lower(key)
			if lower == "target" or lower == "aimpoint" then return aimPoint(100) end
			if lower == "look" or lower == "lookvector" then return direction end
			return improvise(key)
		end,
	})

	local mathCopy = table.clone(math)
	local env = {
		fx = fx, math = mathCopy,
		Vector3 = { new = Vector3.new, zero = Vector3.zero, one = Vector3.one, xAxis = Vector3.xAxis, yAxis = Vector3.yAxis, zAxis = Vector3.zAxis },
		Color3 = { new = Color3.new, fromRGB = Color3.fromRGB, fromHSV = Color3.fromHSV, fromHex = Color3.fromHex },
		CFrame = { new = CFrame.new, Angles = CFrame.Angles, lookAt = CFrame.lookAt, fromAxisAngle = CFrame.fromAxisAngle, identity = CFrame.identity },
		pairs = pairs, ipairs = ipairs, next = next, tonumber = tonumber, tostring = tostring, type = type,
		typeof = typeof, select = select, unpack = table.unpack,
		table = { insert = table.insert, remove = table.remove, unpack = table.unpack, concat = table.concat, find = table.find, clear = table.clear },
		print = function(...) api.Log(...) end,
		__tick = loopTick,
	}
	setfenv(fn, env)

	if not dry then
		send({ op = "castfx", pos = origin, dir = direction, caster = player.UserId, color = options.color })
	end
	local ok, runErr = pcall(fn)
	if not dry then
		while pending > 0 and os.clock() < deadline + 0.5 do task.wait(0.05) end
	end
	send({ op = "end" })
	if not ok then
		local message = tostring(runErr)
		if string.sub(message, 1, #STOP) == STOP then
			local reason = string.sub(message, #STOP + 2)
			if dry then return false, "The spell " .. reason .. ". Use fewer effects and shorter loops.", log end
			note("stopped early: the spell " .. reason)
			return true, nil, log
		end
		return false, "Runtime error: " .. message, log
	end
	return true, nil, log
end

function Fx.Validate(player, code)
	return Fx.Run(player, code, nil, { dry = true })
end

return Fx
