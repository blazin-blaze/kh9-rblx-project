-- ServerScriptService.VoiceArena.SpellForge (ModuleScript)
-- Turns a player's spell description into Luau for the sandboxed `fx` API using Gemini.
-- Pipeline: Gemini (JSON output) -> SpellFx static check + compile -> dry run -> up to 2 repair
-- rounds with the exact error -> if Gemini still fails, an improvised spell built from keywords.
local HttpService = game:GetService("HttpService")
local Config = require(script.Parent.SpellConfig)
local Secrets = require(script.Parent.Secrets)
local Fx = require(script.Parent.SpellFx)

local Forge = {}
local cache = {}
local workingModel = nil
-- Models that just hit their rate limit / were overloaded / don't exist are skipped until this time.
local benchedUntil = {}
local function benchFor(status, message)
	if status == 429 then
		local seconds = tonumber(string.match(string.lower(message or ""), "retry in ([%d%.]+)s"))
		return math.clamp(seconds or 60, 10, 600)
	elseif status == 503 or status == 500 or status == 504 then
		return 30
	elseif status == 404 then
		return 3600
	elseif status == 0 and string.find(message or "", "reach", 1, true) then
		return 20
	end
end
local ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"
local LOADSTRING_HELP = "Roblox is blocking generated code. In Explorer select ServerScriptService, then tick LoadStringEnabled in Properties."

local SYSTEM = [==[
You are SpellForge, the spell designer for a Roblox voice-magic arena. A player describes a spell; you write a short Luau script that performs it using ONLY the `fx` API below. The script runs on the game server inside a sandbox the moment the player speaks the spell's name. Make it look spectacular and feel fair.

Reply with JSON: {"title": a 1-3 word spell name idea, "element": one style word, "description": one sentence a player would read describing what the spell does in-game, "code": the Luau code}.

HARD RULES (code that breaks them is rejected)
- Only these globals exist: fx, math, Vector3, Color3, CFrame, pairs, ipairs, tonumber, tostring, type, typeof, select, unpack, table. Never use game, workspace, Instance, task, wait, string, require, pcall, print-debugging, or backtick strings.
- No while or repeat loops. Use numeric for loops with small bounds (for i = 1, 8 do) or fx:Repeat(n, function(i) ... end).
- 5 to 45 lines. Total fx:Pause time at most 5 seconds. The whole spell should finish within 6 seconds.
- Use `local` for every variable. No recursion.
- The engine caps damage at 45 per enemy per cast. Aim for 15-35 total damage so spells feel fair.
- Always call methods with a colon: fx:Explosion(...), never fx.Explosion(...).

CONTEXT
fx.origin     Vector3  point just in front of the caster's chest
fx.direction  Vector3  unit aim direction (where the player is aiming)
fx.caster     Vector3  caster's position
fx.right, fx.up  Vector3  unit vectors relative to the aim

STEP 1: PREFER PRESET EFFECTS. They are polished and include visuals, sound, camera shake and optional damage.
Common opts for presets: style (string), color (Color3, tints the style), damage (number), status (string), radius (number)
  styles: "fire", "ice", "lightning", "water", "shadow", "arcane", "nature", "holy", "poison", "rock", "wind"
  statuses: "burn", "freeze", "slow", "knockback", "launch", "pull"
fx:Projectile(opts) -> hitPosition, hitEnemy     yields until impact. opts extra: speed (20-180, default 90), size (0.4-6), range (<=160), gravity (0-1 makes it arc), from (Vector3), to (Vector3 target) or direction. damage hits the enemy struck; add radius for splash.
fx:Explosion(position, opts)        big blast; damage hits everyone within radius (default 8)
fx:Lightning(from, to, opts)        instant jagged bolt (from defaults to fx.origin, to defaults to the aim point); damage hits what it strikes
fx:SkyStrike(position, opts)        lightning from the sky onto a point
fx:Nova(position, opts)             expanding shockwave ring on the ground (position defaults to the caster)
fx:Spikes(position, opts)           spikes erupt from the ground. opts.count (<=16), opts.height (2-16), opts.radius (spread)
fx:Aura(opts)                       glowing aura around the caster. opts.duration (<=6), opts.color, opts.style
fx:Shield(seconds, color)           caster is invulnerable for up to 4 s inside a bubble
fx:Heal(amount, color)              heal the caster (up to 30)
fx:Blink(distance, color) -> Vector3   teleport the caster forward (up to 30 studs)
fx:Shake(intensity 0-1, position)   camera shake for nearby players
fx:Flash(color, intensity 0-1)      screen flash
fx:Sound(name, position)            names: fire, explosion, thunder, ice, glass, whoosh, magic, water, impact, zap, heal

STEP 2: IF NO PRESET FITS THE IDEA, BUILD YOUR OWN EFFECT FROM PRIMITIVES.
Primitives are visual only; use fx:Damage for gameplay. Ball/Block/Beam return a handle you can animate.
fx:Ball(position, size, color, duration?) -> handle     glowing sphere (size = diameter)
fx:Block(position, size, color, duration?) -> handle    glowing box (size number or Vector3)
fx:Beam(from, to, width, color, duration?) -> handle    glowing beam between two points
fx:Ring(position, radius, color, duration?)             flat expanding ring
fx:Particles(position, {color=Color3, texture="sparkle"|"fire"|"smoke"|"spark"|"burst", count=1-150, speed=0-120, size=, lifetime=})
fx:Spark(position, color, count)
fx:Light(position, color, range, duration)
fx:Move(handle, position, time)                         glide a handle to a position
fx:Tween(handle, time, size, transparency?)            resize and/or fade a handle (transparency 1 = invisible)
fx:Color(handle, color, time)
fx:Destroy(handle)
Handles without a duration fade out automatically when the spell ends.

GAMEPLAY AND HELPERS
fx:Aim(range?) -> Vector3            the point the player is aiming at (default range 100)
fx:FindEnemy(range?) -> Vector3|nil  nearest enemy roughly in front of the caster
fx:Damage(position, radius, amount, status?) -> number of enemies hit
fx:Forward(distance) -> Vector3      fx.origin + fx.direction * distance
fx:Ground(position) -> Vector3       the floor point under a position
fx:PositionOf(handle) -> Vector3
fx:Pause(seconds)
fx:Async(function() ... end)         run part of the spell at the same time as the rest. fx:Projectile waits until it lands, so wrap projectiles in fx:Async to fire several at once (max 12)
fx:Repeat(count, function(i) ... end)    count <= 24
fx:Random(min, max) -> number
fx:Log(text)

DESIGN TIPS
- Readable from far away: big shapes, bright colors, a clear wind-up and a satisfying impact.
- Combine presets, e.g. a Projectile followed by an Explosion at the hit position.
- Respect the colors, elements and behaviour the player asked for (a "green fireball" is style "fire" with a green color).
- If the idea has no matching preset (a swarm of bees, a giant hand, a black hole, a dragon), compose it from primitives and finish with fx:Damage.

EXAMPLES
-- "a fireball that explodes"
local hit = fx:Projectile({ style = "fire", speed = 100, size = 2 })
fx:Explosion(hit, { style = "fire", radius = 10, damage = 25, status = "burn" })

-- "a green lightning bolt that keeps glowing for 2 seconds"
local green = Color3.fromRGB(60, 255, 120)
local target = fx:Lightning(fx.origin, fx:Aim(90), { color = green, damage = 25 })
local glow = fx:Ball(target, 4, green)
fx:Pause(2)
fx:Tween(glow, 0.4, 8, 1)

-- "a fireball that splits into three when it hits"
local orange = Color3.fromRGB(255, 120, 30)
local hit = fx:Projectile({ style = "fire", color = orange, size = 2.2, damage = 15 })
fx:Explosion(hit, { style = "fire", radius = 7, damage = 8, status = "burn" })
for i = 1, 3 do
	local angle = math.rad(-40 + (i - 1) * 40)
	local dir = (fx.direction * math.cos(angle) + fx.right * math.sin(angle) + Vector3.new(0, 0.25, 0)).Unit
	fx:Async(function()
		local landed = fx:Projectile({ from = hit + Vector3.new(0, 1, 0), direction = dir, style = "fire", size = 1.1, speed = 70, range = 30, gravity = 0.3, damage = 6 })
		fx:Explosion(landed, { style = "fire", radius = 4, damage = 4 })
	end)
end

-- "rain of ice shards"
local center = fx:Aim(70)
for i = 1, 6 do
	local spot = center + Vector3.new(fx:Random(-8, 8), 0, fx:Random(-8, 8))
	fx:Spikes(spot, { style = "ice", count = 3, height = 6, damage = 6, status = "slow" })
	fx:Pause(0.15)
end

-- "a swarm of golden bees" (no preset fits, so primitives)
local target = fx:FindEnemy(80) or fx:Aim(60)
local gold = Color3.fromRGB(255, 200, 40)
local bees = {}
for i = 1, 10 do
	local start = fx.origin + Vector3.new(fx:Random(-3, 3), fx:Random(-1, 3), fx:Random(-3, 3))
	bees[i] = fx:Ball(start, 0.6, gold)
end
for i = 1, 10 do
	fx:Move(bees[i], target + Vector3.new(fx:Random(-2, 2), fx:Random(0, 3), fx:Random(-2, 2)), 0.6 + i * 0.05)
end
fx:Pause(0.8)
fx:Sound("zap", target)
fx:Spark(target, gold, 40)
fx:Damage(target, 7, 22, "slow")
]==]

local SCHEMA = {
	type = "OBJECT",
	properties = {
		title = { type = "STRING" },
		element = { type = "STRING" },
		description = { type = "STRING" },
		code = { type = "STRING" },
	},
	required = { "title", "description", "code" },
	propertyOrdering = { "title", "element", "description", "code" },
}

local function trim(s) return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", "")) end

local function cleanCode(code)
	code = string.gsub(code, "^%s*```[%w]*%s*\n", "")
	code = string.gsub(code, "\n%s*```%s*$", "")
	return code
end

local function extractText(decoded)
	local candidate = type(decoded) == "table" and type(decoded.candidates) == "table" and decoded.candidates[1]
	local parts = candidate and candidate.content and candidate.content.parts
	if type(parts) ~= "table" then
		local reason = candidate and candidate.finishReason
		if not reason and type(decoded) == "table" and decoded.promptFeedback then reason = decoded.promptFeedback.blockReason end
		return nil, "Gemini returned no spell" .. (reason and (" (" .. tostring(reason) .. ")") or "")
	end
	local pieces = {}
	for _, part in ipairs(parts) do
		if type(part.text) == "string" and not part.thought then table.insert(pieces, part.text) end
	end
	return table.concat(pieces)
end

local function request(model, contents, thinking)
	local generationConfig = {
		responseMimeType = "application/json",
		responseSchema = SCHEMA,
		temperature = 0.9,
		maxOutputTokens = 8192,
	}
	if thinking then generationConfig.thinkingConfig = { thinkingLevel = thinking } end
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = string.format(ENDPOINT, model),
			Method = "POST",
			Headers = { ["content-type"] = "application/json", ["x-goog-api-key"] = Secrets.GeminiApiKey },
			Body = HttpService:JSONEncode({
				systemInstruction = { parts = { { text = SYSTEM } } },
				contents = contents,
				generationConfig = generationConfig,
			}),
			Timeout = 45,
		})
	end)
	if not ok then return nil, "Couldn't reach Gemini: " .. tostring(response), 0 end
	if not response.Success then
		local message = response.Body
		pcall(function() message = HttpService:JSONDecode(response.Body).error.message end)
		return nil, string.format("Gemini HTTP %d: %s", response.StatusCode, string.sub(tostring(message), 1, 220)), response.StatusCode
	end
	local okJson, decoded = pcall(function() return HttpService:JSONDecode(response.Body) end)
	if not okJson then return nil, "Gemini sent an unreadable response", 0 end
	local text, err = extractText(decoded)
	if not text then return nil, err, 0 end
	local okSpell, spell = pcall(function() return HttpService:JSONDecode(text) end)
	if not okSpell or type(spell) ~= "table" then return nil, "Gemini's answer wasn't valid spell JSON", 0 end
	return spell, text, 200
end

-- Hedged requests: start with the model that last worked; if it hasn't answered after
-- Config.Gemini.HedgeAfter seconds (or it failed), also ask the next model. First answer wins.
local function callGemini(contents)
	-- Ready models first (the last one that worked leads), benched ones last as a final resort.
	local order, benched = {}, {}
	local now = os.clock()
	local function add(model)
		if table.find(order, model) or table.find(benched, model) then return end
		table.insert((benchedUntil[model] or 0) > now and benched or order, model)
	end
	if workingModel and table.find(Config.Gemini.Models, workingModel) then add(workingModel) end
	for _, model in ipairs(Config.Gemini.Models) do add(model) end
	table.move(benched, 1, #benched, #order + 1, order)
	local result, resultInfo
	local launched, finished, nextIndex = 0, 0, 1
	local lastErr, fatal = "Gemini didn't answer", false
	local function launch()
		local model = order[nextIndex]
		nextIndex += 1
		launched += 1
		task.spawn(function()
			local spell, info, status = request(model, contents, Config.Gemini.Thinking)
			if not spell and status == 400 and Config.Gemini.Thinking and string.find(string.lower(info), "think") then
				spell, info, status = request(model, contents, nil) -- this model doesn't take a thinking level
			end
			finished += 1
			if spell then
				if not result then
					result, resultInfo = spell, info
					if workingModel ~= model then print("[SpellForge] Using Gemini model " .. model) end
					workingModel = model
					benchedUntil[model] = nil
				end
			else
				lastErr = info
				warn("[SpellForge] " .. model .. ": " .. info)
				local bench = benchFor(status, info)
				if bench then
					benchedUntil[model] = os.clock() + bench
					if workingModel == model then workingModel = nil end
				end
				if status == 401 or status == 403 then fatal = true end -- bad key: other models won't help
			end
		end)
	end
	launch()
	local lastLaunch = os.clock()
	while not result and not fatal do
		local allFailed = finished >= launched
		if allFailed or os.clock() - lastLaunch >= (Config.Gemini.HedgeAfter or 10) then
			if nextIndex <= #order then
				launch()
				lastLaunch = os.clock()
			elseif allFailed then
				break
			end
		end
		task.wait(0.1)
	end
	if result then return result, resultInfo end
	workingModel = nil
	return nil, lastErr
end

---------------------------------------------------------------- failsafe spell
local STYLE_WORDS = {
	{ "fire", { "fire", "flame", "burn", "lava", "magma", "inferno", "heat", "ember", "phoenix", "dragon" } },
	{ "ice", { "ice", "frost", "freez", "snow", "cold", "glacier", "blizzard", "chill", "crystal" } },
	{ "lightning", { "lightning", "thunder", "electric", "shock", "storm", "zap", "spark", "volt" } },
	{ "water", { "water", "wave", "ocean", "tide", "rain", "bubble", "aqua", "sea" } },
	{ "shadow", { "shadow", "dark", "void", "black hole", "night", "curse", "death", "necro" } },
	{ "nature", { "nature", "leaf", "vine", "plant", "tree", "forest", "flower", "bee" } },
	{ "holy", { "holy", "light", "sun", "angel", "divine", "radiant", "heaven", "gold" } },
	{ "poison", { "poison", "toxic", "acid", "venom", "plague", "slime" } },
	{ "rock", { "rock", "stone", "earth", "boulder", "meteor", "quake", "ground" } },
	{ "wind", { "wind", "air", "tornado", "gust", "hurricane", "cyclone" } },
}
local COLOR_WORDS = {
	{ "red", "255, 60, 50" }, { "orange", "255, 140, 30" }, { "yellow", "255, 225, 60" }, { "green", "60, 230, 90" },
	{ "cyan", "70, 230, 255" }, { "blue", "60, 120, 255" }, { "purple", "160, 80, 255" }, { "pink", "255, 120, 200" },
	{ "white", "255, 255, 255" }, { "black", "40, 25, 50" }, { "gold", "255, 200, 50" },
}

function Forge.Improvise(prompt)
	local p = " " .. string.lower(prompt) .. " "
	local style = "arcane"
	for _, entry in ipairs(STYLE_WORDS) do
		for _, word in ipairs(entry[2]) do
			if string.find(p, word, 1, true) then style = entry[1]; break end
		end
		if style ~= "arcane" then break end
	end
	local colorExpr = "nil"
	for _, entry in ipairs(COLOR_WORDS) do
		if string.find(p, entry[1], 1, true) then colorExpr = "Color3.fromRGB(" .. entry[2] .. ")"; break end
	end
	local function has(...)
		for _, w in ipairs({ ... }) do if string.find(p, w, 1, true) then return true end end
		return false
	end
	local code, description
	if has("heal", "regenerat", "restore", "health") then
		code = ("fx:Aura({ style = %q, color = %s, duration = 2 })\nfx:Heal(25, %s)\nfx:Nova(fx.caster, { style = %q, color = %s, radius = 10 })"):format(style, colorExpr, colorExpr, style, colorExpr)
		description = "Heals you and bursts with light."
	elseif has("shield", "protect", "barrier", "block", "defen") then
		code = ("fx:Shield(3, %s)\nfx:Nova(fx.caster, { style = %q, color = %s, radius = 12, damage = 10, status = \"knockback\" })"):format(colorExpr, style, colorExpr)
		description = "Wraps you in a protective bubble and pushes enemies away."
	elseif has("teleport", "dash", "blink", "warp") then
		code = ("local landing = fx:Blink(22, %s)\nfx:Nova(landing, { style = %q, color = %s, radius = 10, damage = 18 })"):format(colorExpr, style, colorExpr)
		description = "Teleports you forward and blasts the landing spot."
	elseif has("rain", "meteor", "storm", "sky", "strike") then
		code = ("local center = fx:Aim(80)\nfor i = 1, 5 do\n\tlocal spot = center + Vector3.new(fx:Random(-8, 8), 0, fx:Random(-8, 8))\n\tfx:SkyStrike(spot, { color = %s, damage = 8 })\n\tfx:Explosion(spot, { style = %q, color = %s, radius = 6 })\n\tfx:Pause(0.2)\nend"):format(colorExpr, style, colorExpr)
		description = "Calls strikes down from the sky around your target."
	elseif has("spike", "wall", "pillar", "eruption", "ground", "earth") then
		code = ("local spot = fx:Aim(70)\nfx:Spikes(spot, { style = %q, color = %s, count = 9, height = 8, radius = 6, damage = 25, status = \"launch\" })"):format(style, colorExpr)
		description = "Spikes erupt from the ground where you aim."
	elseif has("around me", "nova", "pulse", "aura", "ring", "explode around") then
		code = ("fx:Aura({ style = %q, color = %s, duration = 1 })\nfx:Pause(0.3)\nfx:Nova(fx.caster, { style = %q, color = %s, radius = 16, damage = 25, status = \"knockback\" })"):format(style, colorExpr, style, colorExpr)
		description = "A shockwave blasts outward from you."
	else
		code = ("local hit = fx:Projectile({ style = %q, color = %s, speed = 95, size = 2.2 })\nfx:Explosion(hit, { style = %q, color = %s, radius = 9, damage = 25 })"):format(style, colorExpr, style, colorExpr)
		description = "Hurls a magic projectile that explodes on impact."
	end
	return { code = code, title = "Improvised " .. style, element = style, description = description }
end

---------------------------------------------------------------- main entry
-- Returns { ok, code, title, description, element, attempts, fallback, note } or { ok = false, error }.
function Forge.Generate(player, name, prompt)
	if type(prompt) ~= "string" then return { ok = false, error = "Describe your spell first" } end
	prompt = trim(string.sub(prompt, 1, 400))
	if #prompt < 3 then return { ok = false, error = "Describe your spell first" } end
	if type(Secrets.GeminiApiKey) ~= "string" or Secrets.GeminiApiKey == "" then
		return { ok = false, error = "Add a Gemini API key to ServerScriptService.VoiceArena.Secrets" }
	end
	local key = string.lower(prompt)
	if cache[key] then return cache[key] end

	local contents = { {
		role = "user",
		parts = { { text = string.format("Spell name (the word the player will say): %s\nWhat the player wants the spell to do: %s",
			name ~= "" and name or "(not chosen yet)", prompt) } },
	} }
	local lastErr
	for attempt = 1, Config.Gemini.MaxAttempts do
		local spell, raw = callGemini(contents)
		if not spell then lastErr = raw; break end
		local code = type(spell.code) == "string" and cleanCode(spell.code) or ""
		local ok, err = Fx.Validate(player, code)
		if err == "LOADSTRING_DISABLED" then return { ok = false, error = LOADSTRING_HELP } end
		if ok then
			local result = {
				ok = true, code = code, attempts = attempt,
				title = type(spell.title) == "string" and string.sub(spell.title, 1, 40) or "AI Spell",
				element = type(spell.element) == "string" and string.sub(spell.element, 1, 20) or "arcane",
				description = type(spell.description) == "string" and string.sub(spell.description, 1, 200) or prompt,
			}
			cache[key] = result
			print(string.format("[SpellForge] \"%s\" ready after %d attempt(s)", result.title, attempt))
			return result
		end
		lastErr = err
		warn(string.format("[SpellForge] Attempt %d failed validation: %s", attempt, tostring(err)))
		table.insert(contents, { role = "model", parts = { { text = raw } } })
		table.insert(contents, { role = "user", parts = { { text =
			"The engine rejected that spell with this error:\n" .. tostring(err) ..
			"\nFix the code. Follow every hard rule, only use the documented fx API, and reply in the same JSON format." } } })
	end

	-- FAILSAFE: Gemini was unreachable or its code kept failing. Build a spell from keywords.
	local fallback = Forge.Improvise(prompt)
	local ok, err = Fx.Validate(player, fallback.code)
	if err == "LOADSTRING_DISABLED" then return { ok = false, error = LOADSTRING_HELP } end
	if not ok then return { ok = false, error = "Couldn't build a spell: " .. tostring(lastErr or err) } end
	fallback.ok = true
	fallback.fallback = true
	fallback.attempts = 0
	fallback.note = lastErr
	warn("[SpellForge] Using an improvised spell instead. Reason: " .. tostring(lastErr))
	return fallback
end

return Forge
