local Players =
	game:GetService("Players")

local UserInputService =
	game:GetService("UserInputService")

local ProximityPromptService =
	game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local AUTO_E_INTERVAL = 0.01
local TRIGGER_HOLD_TIME = 0.01

local eHeld = false
local autoEToggled = false
local autoEThread = nil
local visiblePrompts = {}
local scriptRunning = true

-- ลบ GUI เก่าป้องกันซ้ำ
local oldGui = playerGui:FindFirstChild("AutoEStatusGui")

if oldGui then
	oldGui:Destroy()
end

-- สร้าง GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoEStatusGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.fromOffset(220, 105)
mainFrame.Position = UDim2.new(0.5, -110, 0.15, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 8)
mainCorner.Parent = mainFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -45, 0, 34)
titleLabel.Position = UDim2.fromOffset(10, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Auto E"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextSize = 16
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = mainFrame

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.fromOffset(34, 34)
closeButton.Position = UDim2.new(1, -34, 0, 0)
closeButton.BackgroundTransparency = 1
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(255, 90, 90)
closeButton.TextSize = 18
closeButton.Font = Enum.Font.GothamBold
closeButton.Parent = mainFrame

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -20, 0, 30)
statusLabel.Position = UDim2.fromOffset(10, 35)
statusLabel.BackgroundColor3 = Color3.fromRGB(170, 55, 55)
statusLabel.BorderSizePixel = 0
statusLabel.Text = "Auto E: OFF"
statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
statusLabel.TextSize = 14
statusLabel.Font = Enum.Font.GothamBold
statusLabel.Parent = mainFrame

local statusCorner = Instance.new("UICorner")
statusCorner.CornerRadius = UDim.new(0, 6)
statusCorner.Parent = statusLabel

local infoLabel = Instance.new("TextLabel")
infoLabel.Size = UDim2.new(1, -20, 0, 28)
infoLabel.Position = UDim2.fromOffset(10, 70)
infoLabel.BackgroundTransparency = 1
infoLabel.Text = "กด R เปิด/ปิด | กด E ค้าง"
infoLabel.TextColor3 = Color3.fromRGB(190, 190, 190)
infoLabel.TextSize = 12
infoLabel.Font = Enum.Font.Gotham
infoLabel.Parent = mainFrame

local function updateStatus()
	if not scriptRunning then
		return
	end

	if autoEToggled then
		statusLabel.Text = "Auto E: ON"
		statusLabel.BackgroundColor3 =
			Color3.fromRGB(45, 170, 90)
	elseif eHeld then
		statusLabel.Text = "Auto E: E HELD"
		statusLabel.BackgroundColor3 =
			Color3.fromRGB(210, 140, 40)
	else
		statusLabel.Text = "Auto E: OFF"
		statusLabel.BackgroundColor3 =
			Color3.fromRGB(170, 55, 55)
	end
end

local function isValidPrompt(prompt)
	return scriptRunning
		and prompt
		and prompt.Parent
		and prompt.Enabled
		and prompt.KeyboardKeyCode == Enum.KeyCode.E
end

local function getActivePrompt()
	for prompt in pairs(visiblePrompts) do
		if isValidPrompt(prompt) then
			return prompt
		else
			visiblePrompts[prompt] = nil
		end
	end

	return nil
end

local promptShownConnection
local promptHiddenConnection
local inputBeganConnection
local inputEndedConnection

promptShownConnection =
	ProximityPromptService.PromptShown:Connect(function(
		prompt,
		inputType
	)
		if not scriptRunning then
			return
		end

		if prompt.KeyboardKeyCode == Enum.KeyCode.E then
			visiblePrompts[prompt] = true
		end
	end)

promptHiddenConnection =
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		visiblePrompts[prompt] = nil
	end)

local function activatePrompt(prompt)
	if not isValidPrompt(prompt) then
		return
	end

	prompt:InputHoldBegin()

	local holdTime = math.max(
		prompt.HoldDuration,
		TRIGGER_HOLD_TIME
	)

	task.wait(holdTime)

	if scriptRunning
		and prompt
		and prompt.Parent then

		prompt:InputHoldEnd()
	end
end

local function shouldAutoERun()
	return scriptRunning
		and (eHeld or autoEToggled)
end

local function stopAutoEThread()
	if autoEThread then
		task.cancel(autoEThread)
		autoEThread = nil
	end
end

local function updateAutoE()
	updateStatus()

	if shouldAutoERun() then
		if autoEThread then
			return
		end

		autoEThread = task.spawn(function()
			while shouldAutoERun() do
				local prompt = getActivePrompt()

				if prompt then
					local success, errorMessage = pcall(
						activatePrompt,
						prompt
					)

					if not success then
						warn(
							"Auto E error:",
							errorMessage
						)
					end
				end

				task.wait(AUTO_E_INTERVAL)
			end

			autoEThread = nil
		end)
	else
		stopAutoEThread()
	end
end

inputBeganConnection =
	UserInputService.InputBegan:Connect(function(
		input,
		gameProcessed
	)
		if not scriptRunning then
			return
		end

		if UserInputService:GetFocusedTextBox() then
			return
		end

		if input.KeyCode == Enum.KeyCode.E then
			eHeld = true
			updateAutoE()
			return
		end

		if input.KeyCode == Enum.KeyCode.R then
			autoEToggled = not autoEToggled
			updateAutoE()
		end
	end)

inputEndedConnection =
	UserInputService.InputEnded:Connect(function(
		input,
		gameProcessed
	)
		if not scriptRunning then
			return
		end

		if input.KeyCode == Enum.KeyCode.E then
			eHeld = false
			updateAutoE()
		end
	end)

closeButton.MouseButton1Click:Connect(function()
	scriptRunning = false
	eHeld = false
	autoEToggled = false

	stopAutoEThread()

	table.clear(visiblePrompts)

	if promptShownConnection then
		promptShownConnection:Disconnect()
	end

	if promptHiddenConnection then
		promptHiddenConnection:Disconnect()
	end

	if inputBeganConnection then
		inputBeganConnection:Disconnect()
	end

	if inputEndedConnection then
		inputEndedConnection:Disconnect()
	end

	screenGui:Destroy()
end)

updateStatus()
