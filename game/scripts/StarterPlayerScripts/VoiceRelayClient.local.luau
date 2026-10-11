-- A player's private pairing code for the shared voice relay; no casting or microphone changes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local folder = ReplicatedStorage:WaitForChild("VoiceArena")
while folder:GetAttribute("VoiceRelayEnabled") == nil do task.wait(0.1) end
if not folder:GetAttribute("VoiceRelayEnabled") then return end
local remote = folder:WaitForChild("GetVoicePairing")
local function make(class, props)
  local item = Instance.new(class)
  for key, value in pairs(props) do item[key] = value end
  return item
end
local gui = make("ScreenGui", { Name = "VoiceRelayPairing", ResetOnSpawn = false, DisplayOrder = 20, Parent = player:WaitForChild("PlayerGui") })
local button = make("TextButton", { Name = "VoiceConnect", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
  Size = UDim2.fromOffset(154, 32), BackgroundColor3 = Color3.fromRGB(15, 40, 43), TextColor3 = Color3.fromRGB(130, 255, 230),
  Text = "VOICE CONNECT", Font = Enum.Font.GothamBold, TextSize = 12, Parent = gui })
make("UICorner", { CornerRadius = UDim.new(0, 8), Parent = button })
local panel = make("Frame", { Name = "PairingPanel", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 54),
  Size = UDim2.fromOffset(330, 230), BackgroundColor3 = Color3.fromRGB(12, 25, 29), Visible = true, Parent = gui })
make("UICorner", { CornerRadius = UDim.new(0, 10), Parent = panel })
local function label(name, text, y, height, size)
  return make("TextLabel", { Name = name, Position = UDim2.fromOffset(14, y), Size = UDim2.new(1, -28, 0, height),
    BackgroundTransparency = 1, TextColor3 = Color3.fromRGB(225, 242, 238), Font = Enum.Font.Gotham,
    TextSize = size or 13, TextWrapped = true, Text = text, Parent = panel })
end
label("Instructions", "Run TeamTest.cmd on your computer.\nEnter this relay URL and your pairing code.", 10, 42)
local url = make("TextBox", { Name = "RelayUrl", Position = UDim2.fromOffset(14, 58), Size = UDim2.new(1, -28, 0, 34),
  BackgroundColor3 = Color3.fromRGB(23, 44, 49), TextColor3 = Color3.fromRGB(190, 240, 231), Font = Enum.Font.Code,
  TextSize = 11, TextEditable = false, ClearTextOnFocus = false, Text = "Connecting...", Parent = panel })
local code = label("PairCode", "WAITING FOR RELAY", 99, 38, 23)
code.Font = Enum.Font.GothamBold
local status = label("PairStatus", "Connecting to the relay host...", 140, 32)
local reset = make("TextButton", { Name = "ResetPairing", Position = UDim2.fromOffset(14, 183), Size = UDim2.new(1, -28, 0, 32),
  BackgroundColor3 = Color3.fromRGB(26, 68, 66), TextColor3 = Color3.fromRGB(225, 255, 249), Text = "NEW PAIRING CODE",
  Font = Enum.Font.GothamBold, TextSize = 12, Parent = panel })
make("UICorner", { CornerRadius = UDim.new(0, 7), Parent = reset })
local pairedBefore = false
local function refresh(force)
  local ok, info = pcall(function() return remote:InvokeServer(force == true) end)
  if not ok or type(info) ~= "table" then status.Text = "Relay connection unavailable"; return end
  url.Text = info.url or ""
  button.Text = info.voiceActive and "MIC CONNECTED" or "VOICE CONNECT"
  if info.voiceActive then
    code.Text = "MIC CONNECTED"
    status.Text = "Your console controls your avatar."
    if not pairedBefore then panel.Visible = false; pairedBefore = true end
  elseif info.connected and type(info.code) == "string" and #info.code > 0 then
    code.Text = info.code:sub(1, 5) .. "-" .. info.code:sub(6)
    status.Text = string.format("Your code expires in %d seconds.", math.floor(info.expiresIn or 0))
    pairedBefore = false
  elseif info.connected then
    code.Text = "MIC CONNECTING"
    status.Text = "Waiting for your console. Use New Pairing Code to reconnect."
  else
    code.Text = "RELAY OFFLINE"
    status.Text = info.statusMessage or "Ask the host to check HostRelay.cmd."
  end
end
button.Activated:Connect(function() panel.Visible = not panel.Visible; if panel.Visible then refresh(false) end end)
reset.Activated:Connect(function() pairedBefore = false; code.Text = "REQUESTING..."; refresh(true) end)
task.spawn(function()
  while gui.Parent do refresh(false); task.wait(2) end
end)
