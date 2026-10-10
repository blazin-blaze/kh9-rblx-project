-- ServerScriptService.VoiceArena.Loadout (ModuleScript)
-- Each player equips 3 spells at the start: a name (the word they say) + a preset or an AI spell.
-- Remotes (ReplicatedStorage.VoiceArena): ForgeSpell, TestSpell, SetLoadout (RemoteFunctions).
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local Config = require(script.Parent.SpellConfig)
local Spells = require(script.Parent.SpellService)
local Fx = require(script.Parent.SpellFx)
local Forge = require(script.Parent.SpellForge)

local Loadout = {}
local PRESETS = { Flame = true, Freeze = true, Wave = true }
local DEFAULT = {
	{ name = "Flame", kind = "preset", preset = "Flame" },
	{ name = "Freeze", kind = "preset", preset = "Freeze" },
	{ name = "Wave", kind = "preset", preset = "Wave" },
}
local COMMON = {}
for _, w in ipairs({ "the", "and", "yes", "yeah", "okay", "stop", "hello", "hey", "like", "what", "you",
	"this", "that", "with", "have", "just", "now", "then", "there", "here", "go", "no", "um", "uh", "so" }) do
	COMMON[w] = true
end
local MAX_FORGED = 20

local loadouts, forged, forgedOrder, forging, lastForge, cooldowns, globalCooldowns = {}, {}, {}, {}, {}, {}, {}
local feedback, getDirection

local function normalize(s) return string.lower((string.gsub(tostring(s), "[^%a]", ""))) end

local function editDistance(a, b)
	local prev = {}
	for j = 0, #b do prev[j] = j end
	for i = 1, #a do
		local cur = { [0] = i }
		for j = 1, #b do
			local cost = string.sub(a, i, i) == string.sub(b, j, j) and 0 or 1
			cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
		end
		prev = cur
	end
	return prev[#b]
end

local function tooSimilar(a, b)
	a, b = normalize(a), normalize(b)
	local d = editDistance(a, b)
	local shortest = math.min(#a, #b)
	return d == 0 or (shortest <= 6 and d <= 1) or (shortest > 6 and d <= 2)
end

function Loadout.ValidateName(raw)
	if type(raw) ~= "string" then return nil, "Give this spell a name" end
	local clean = (string.gsub(string.gsub(raw, "^%s+", ""), "%s+$", ""))
	if clean == "" then return nil, "Give this spell a name" end
	if not string.match(clean, "^%a+$") then return nil, "One word, letters only" end
	if #clean < 3 or #clean > 20 then return nil, "Use 3 to 20 letters" end
	if COMMON[string.lower(clean)] then return nil, "Too common a word. Pick something more unique" end
	return clean
end

function Loadout.Get(player)
	return loadouts[player] or DEFAULT
end

function Loadout.Names(player)
	local names = {}
	for i, slot in ipairs(Loadout.Get(player)) do names[i] = slot.name end
	return names
end

-- value: slot number (1-3) or a spoken name. Returns def, slotIndex.
function Loadout.Resolve(player, value)
	local slots = Loadout.Get(player)
	if type(value) == "number" then
		local i = math.floor(value)
		return slots[i], i
	end
	if type(value) == "string" then
		local key = normalize(value)
		for i, slot in ipairs(slots) do
			if normalize(slot.name) == key then return slot, i end
		end
	end
	return nil
end

local function sanitizeDef(player, s, name)
	if type(s) ~= "table" then return nil, "Pick a spell" end
	if s.kind == "preset" then
		if type(s.preset) ~= "string" or not PRESETS[s.preset] then return nil, "Pick a spell from the list" end
		return { name = name, kind = "preset", preset = s.preset }
	elseif s.kind == "custom" then
		local spell = type(s.spellId) == "string" and forged[player] and forged[player][s.spellId]
		if not spell then return nil, "Generate your AI spell first" end
		return { name = name, kind = "custom", spellId = s.spellId, title = spell.title }
	end
	return nil, "Pick a spell"
end

local function validDirection(direction)
	if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.5 or direction.Magnitude > 1.5 then return false end
	for _, v in ipairs({ direction.X, direction.Y, direction.Z }) do
		if v ~= v or math.abs(v) > 1.5 then return false end
	end
	return true
end

function Loadout.CastDef(player, def, direction)
	if def.kind == "preset" then
		return Spells.Cast(player, def.preset, direction)
	end
	local spell = forged[player] and forged[player][def.spellId]
	if not spell then return false, "That AI spell is missing. Generate it again" end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false, "Respawn first" end
	if character:GetAttribute("VoiceFrozen") then return false, "You are frozen" end
	if not validDirection(direction) then return false, "Aim unavailable" end
	local now = os.clock()
	cooldowns[player] = cooldowns[player] or {}
	local readyAt = cooldowns[player][def.spellId] or 0
	local label = def.name or spell.title
	if now < readyAt then return false, string.format("%s ready in %.1fs", label, readyAt - now) end
	if now < (globalCooldowns[player] or 0) then return false, "Speak one spell at a time" end
	cooldowns[player][def.spellId] = now + Config.Custom.Cooldown
	globalCooldowns[player] = now + Config.GlobalCooldown
	task.spawn(function()
		local ok, err, log = Fx.Run(player, spell.code, direction.Unit)
		for _, line in ipairs(log or {}) do print("[SpellForge] " .. label .. ": " .. line) end
		if not ok then
			warn("[SpellForge] " .. label .. " fizzled: " .. tostring(err))
			if feedback then feedback:FireClient(player, { kind = "note", text = label .. " fizzled: " .. tostring(err) }) end
		end
	end)
	return true, Config.Custom.Cooldown
end

local function remember(player, result, prompt)
	forged[player] = forged[player] or {}
	forgedOrder[player] = forgedOrder[player] or {}
	local id = HttpService:GenerateGUID(false)
	forged[player][id] = { code = result.code, title = result.title, description = result.description,
		element = result.element, prompt = prompt }
	table.insert(forgedOrder[player], id)
	-- Forget the oldest unequipped spells so memory stays bounded.
	while #forgedOrder[player] > MAX_FORGED do
		local oldest = table.remove(forgedOrder[player], 1)
		local inUse = false
		for _, slot in ipairs(Loadout.Get(player)) do if slot.spellId == oldest then inUse = true end end
		if inUse then table.insert(forgedOrder[player], oldest) break end
		forged[player][oldest] = nil
	end
	return id
end

function Loadout.Init(folder, feedbackRemote, directionGetter)
	feedback, getDirection = feedbackRemote, directionGetter
	local function remoteFunction(name)
		local r = folder:FindFirstChild(name)
		if r and not r:IsA("RemoteFunction") then r:Destroy(); r = nil end
		r = r or Instance.new("RemoteFunction")
		r.Name = name
		r.Parent = folder
		return r
	end

	remoteFunction("ForgeSpell").OnServerInvoke = function(player, _slot, name, prompt)
		if forging[player] then return { ok = false, error = "Already making a spell. Wait for it to finish" } end
		local since = os.clock() - (lastForge[player] or -math.huge)
		if since < Config.Gemini.MinInterval then return { ok = false, error = "Give it a second, then try again" } end
		if type(prompt) ~= "string" then return { ok = false, error = "Describe your spell first" } end
		forging[player], lastForge[player] = true, os.clock()
		local okCall, result = pcall(Forge.Generate, player, type(name) == "string" and string.sub(name, 1, 20) or "", prompt)
		forging[player] = nil
		if not okCall then
			warn("[SpellForge] " .. tostring(result))
			return { ok = false, error = "Spell forge crashed: " .. tostring(result) }
		end
		if not result.ok then return result end
		if not player.Parent then return { ok = false, error = "Player left" } end
		local id = remember(player, result, prompt)
		return { ok = true, spellId = id, title = result.title, description = result.description, element = result.element,
			code = result.code, fallback = result.fallback == true, note = result.note, attempts = result.attempts }
	end

	remoteFunction("TestSpell").OnServerInvoke = function(player, s)
		local def, err = sanitizeDef(player, s, type(s) == "table" and type(s.name) == "string" and string.sub(s.name, 1, 20) or "Test")
		if not def then return { ok = false, error = err } end
		local direction = getDirection(player)
		if not direction then return { ok = false, error = "Respawn first" } end
		local ok, value = Loadout.CastDef(player, def, direction)
		return { ok = ok, value = value }
	end

	remoteFunction("SetLoadout").OnServerInvoke = function(player, slots)
		if type(slots) ~= "table" then return { ok = false, errors = { ["1"] = "Invalid loadout" } } end
		local defs, errors = {}, {}
		for i = 1, 3 do
			local s = slots[i]
			local name, nameErr = Loadout.ValidateName(type(s) == "table" and s.name or nil)
			if not name then
				errors[tostring(i)] = nameErr
			else
				local def, defErr = sanitizeDef(player, s, name)
				if def then defs[i] = def else errors[tostring(i)] = defErr end
			end
		end
		for i = 1, 3 do
			for j = i + 1, 3 do
				if defs[i] and defs[j] and not errors[tostring(j)] and tooSimilar(defs[i].name, defs[j].name) then
					errors[tostring(j)] = string.format("Too close to \"%s\". The voice system could mix them up", defs[i].name)
				end
			end
		end
		if next(errors) then return { ok = false, errors = errors } end
		loadouts[player] = defs
		local names = Loadout.Names(player)
		print("[VoiceArena] " .. player.Name .. " equipped: " .. table.concat(names, ", "))
		feedback:FireClient(player, { kind = "loadout", names = names })
		return { ok = true, names = names }
	end
end

Players.PlayerRemoving:Connect(function(player)
	loadouts[player], forged[player], forgedOrder[player], forging[player] = nil, nil, nil, nil
	lastForge[player], cooldowns[player], globalCooldowns[player] = nil, nil, nil
end)

return Loadout
