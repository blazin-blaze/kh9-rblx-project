-- StarterPlayer.StarterPlayerScripts.VoiceArenaClient (LocalScript)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local remotes = ReplicatedStorage:WaitForChild("VoiceArena")
local feedback, aim, test = remotes:WaitForChild("Feedback"), remotes:WaitForChild("Aim"), remotes:WaitForChild("StudioCast")
local gui = Instance.new("ScreenGui"); gui.Name = "VoiceArenaHUD"; gui.ResetOnSpawn = false; gui.Parent = player:WaitForChild("PlayerGui")
local panel = Instance.new("Frame"); panel.Size = UDim2.new(0,450,0,180); panel.Position = UDim2.new(0.5,-225,1,-194)
panel.BackgroundColor3 = Color3.fromRGB(10,18,35); panel.BackgroundTransparency = 0.08; panel.Parent = gui
Instance.new("UICorner",panel).CornerRadius = UDim.new(0,14)
local stroke = Instance.new("UIStroke",panel); stroke.Color = Color3.fromRGB(65,100,135); stroke.Transparency = 0.4
local scale = Instance.new("UIScale",panel)
local function label(text, y, height, size, color)
  local l = Instance.new("TextLabel"); l.Size = UDim2.new(1,-24,0,height); l.Position = UDim2.fromOffset(12,y)
  l.BackgroundTransparency = 1; l.Text = text; l.TextSize = size; l.Font = Enum.Font.GothamMedium
  l.TextColor3 = color or Color3.fromRGB(220,235,255); l.TextWrapped = true; l.Parent = panel; return l
end
label("VOICE ARENA  /  KNIGHT HACKS IX",8,24,14,Color3.fromRGB(145,226,236))
local status = label("Waiting for the local voice console",35,24,13)
local source = label("Run Start.cmd and enter your ElevenLabs key",61,24,13)
local spells = label("FLAME   ·   FREEZE   ·   WAVE",90,29,17)
local message = label("Aim with your mouse. Say one spell, then pause.",127,38,12)
local cooldowns, studio = {}, false
local names = { "Flame", "Freeze", "Wave" } -- updated when the player equips a loadout
feedback.OnClientEvent:Connect(function(event)
  if event.kind == "bridge" then
    studio = event.studio
    status.Text = event.connected and "Local voice console connected" or "Voice console offline — run Start.cmd"
    source.Text = event.voiceActive and "Console microphone controls your player" or "Select your player in the console"
    if studio then message.Text = "Studio testing: F / G / H cast spells 1 / 2 / 3. L changes spells." end
  elseif event.kind == "cast" then
    if event.ok then cooldowns[event.spell] = os.clock() + event.value; message.Text = event.spell .. " cast!"
    else message.Text = tostring(event.value) end
  elseif event.kind == "loadout" and type(event.names) == "table" then
    names = event.names
    cooldowns = {}
    message.Text = "Say " .. table.concat(names, ", ") .. " to cast. Press L to change spells."
  elseif event.kind == "note" then
    message.Text = tostring(event.text)
  end
end)
UserInputService.InputBegan:Connect(function(input, handled)
  if handled or not studio or UserInputService:GetFocusedTextBox() then return end
  local slot = ({ [Enum.KeyCode.F] = 1, [Enum.KeyCode.G] = 2, [Enum.KeyCode.H] = 3 })[input.KeyCode]
  if slot then test:FireServer(slot) end
end)
local accumulated = 0
RunService.RenderStepped:Connect(function(dt)
  local camera = workspace.CurrentCamera
  if camera then scale.Scale = math.min(1, (camera.ViewportSize.X-20)/450) end
  accumulated += dt
  if accumulated < 0.1 then return end
  accumulated = 0
  local character = player.Character
  local root = character and character:FindFirstChild("HumanoidRootPart")
  if root then
    local direction = mouse.Hit.Position - (root.Position + Vector3.new(0,1,0))
    if direction.Magnitude > 0.1 then aim:FireServer(direction.Unit) end
  end
  local texts = {}
  for _, spell in ipairs(names) do
    local remaining = math.max(0,(cooldowns[spell] or 0)-os.clock())
    table.insert(texts, remaining > 0 and string.format("%s %.1fs",spell,remaining) or (spell .. " READY"))
  end
  spells.Text = table.concat(texts,"  ·  ")
end)
