-- Egg Collector GUI
-- Toggle GUI: L

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local folder = workspace:WaitForChild("AreaEggSlotsClient")

local TOGGLE_KEY = Enum.KeyCode.L
local TELEPORT_TIME = 0.5
local DELAY_NEXT_ROUND = 1
local WAIT_BETWEEN_EGGS = 0.1

local running = false
local runToken = 0
local minimized = false
local guiVisible = true

local oldGui = playerGui:FindFirstChild("EggCollectorGUI")
if oldGui then
	oldGui:Destroy()
end

local function getCharacterParts()
	local character = player.Character or player.CharacterAdded:Wait()
	local rootPart = character:WaitForChild("HumanoidRootPart")
	return character, rootPart
end

local function makePromptInstant(prompt)
	if not prompt or not prompt:IsA("ProximityPrompt") then
		return
	end

	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = math.max(prompt.MaxActivationDistance, 15)
end

for _, object in ipairs(folder:GetDescendants()) do
	if object:IsA("ProximityPrompt") then
		makePromptInstant(object)
	end
end

folder.DescendantAdded:Connect(function(object)
	if object:IsA("ProximityPrompt") then
		task.defer(makePromptInstant, object)
	end
end)

ProximityPromptService.PromptShown:Connect(function(prompt)
	if prompt:IsDescendantOf(folder) then
		makePromptInstant(prompt)
	end
end)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "EggCollectorGUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.fromOffset(330, 245)
main.Position = UDim2.new(0.5, -165, 0.5, -122)
main.BackgroundColor3 = Color3.fromRGB(22, 25, 32)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 10)
mainCorner.Parent = main

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(75, 135, 255)
mainStroke.Thickness = 1.5
mainStroke.Parent = main

local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 44)
header.BackgroundColor3 = Color3.fromRGB(33, 38, 49)
header.BorderSizePixel = 0
header.Parent = main

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 10)
headerCorner.Parent = header

local headerFix = Instance.new("Frame")
headerFix.Size = UDim2.new(1, 0, 0, 10)
headerFix.Position = UDim2.new(0, 0, 1, -10)
headerFix.BackgroundColor3 = header.BackgroundColor3
headerFix.BorderSizePixel = 0
headerFix.Parent = header

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -90, 1, 0)
title.Position = UDim2.fromOffset(14, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.Text = "EGG COLLECTOR"
title.TextColor3 = Color3.fromRGB(240, 244, 255)
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local minimizeButton = Instance.new("TextButton")
minimizeButton.Size = UDim2.fromOffset(34, 28)
minimizeButton.Position = UDim2.new(1, -76, 0, 8)
minimizeButton.BackgroundColor3 = Color3.fromRGB(55, 61, 75)
minimizeButton.Text = "—"
minimizeButton.Font = Enum.Font.GothamBold
minimizeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
minimizeButton.TextSize = 17
minimizeButton.Parent = header

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.fromOffset(34, 28)
closeButton.Position = UDim2.new(1, -38, 0, 8)
closeButton.BackgroundColor3 = Color3.fromRGB(190, 60, 70)
closeButton.Text = "X"
closeButton.Font = Enum.Font.GothamBold
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.TextSize = 14
closeButton.Parent = header

for _, button in ipairs({minimizeButton, closeButton}) do
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button
end

local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.new(1, -28, 1, -58)
content.Position = UDim2.fromOffset(14, 51)
content.BackgroundTransparency = 1
content.Parent = main

local countLabel = Instance.new("TextLabel")
countLabel.Size = UDim2.new(1, 0, 0, 25)
countLabel.BackgroundTransparency = 1
countLabel.Font = Enum.Font.GothamMedium
countLabel.Text = "จำนวนไข่ที่ต้องการเก็บ"
countLabel.TextColor3 = Color3.fromRGB(215, 220, 235)
countLabel.TextSize = 14
countLabel.TextXAlignment = Enum.TextXAlignment.Left
countLabel.Parent = content

local countInput = Instance.new("TextBox")
countInput.Size = UDim2.new(1, 0, 0, 38)
countInput.Position = UDim2.fromOffset(0, 29)
countInput.BackgroundColor3 = Color3.fromRGB(38, 43, 54)
countInput.ClearTextOnFocus = false
countInput.Font = Enum.Font.Gotham
countInput.PlaceholderText = "ใส่จำนวนไข่"
countInput.Text = "10"
countInput.TextColor3 = Color3.fromRGB(255, 255, 255)
countInput.PlaceholderColor3 = Color3.fromRGB(130, 138, 155)
countInput.TextSize = 15
countInput.Parent = content

local inputCorner = Instance.new("UICorner")
inputCorner.CornerRadius = UDim.new(0, 7)
inputCorner.Parent = countInput

local toggleButton = Instance.new("TextButton")
toggleButton.Size = UDim2.new(1, 0, 0, 42)
toggleButton.Position = UDim2.fromOffset(0, 77)
toggleButton.BackgroundColor3 = Color3.fromRGB(45, 175, 105)
toggleButton.Font = Enum.Font.GothamBold
toggleButton.Text = "เริ่มหาและเก็บไข่"
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.TextSize = 15
toggleButton.Parent = content

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 8)
toggleCorner.Parent = toggleButton

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 0, 27)
statusLabel.Position = UDim2.fromOffset(0, 126)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Gotham
statusLabel.Text = "สถานะ: ปิด"
statusLabel.TextColor3 = Color3.fromRGB(170, 180, 200)
statusLabel.TextSize = 13
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = content

local keyLabel = Instance.new("TextLabel")
keyLabel.Size = UDim2.new(1, 0, 0, 23)
keyLabel.Position = UDim2.fromOffset(0, 153)
keyLabel.BackgroundTransparency = 1
keyLabel.Font = Enum.Font.Gotham
keyLabel.Text = "L = ซ่อน / แสดงหน้าต่าง"
keyLabel.TextColor3 = Color3.fromRGB(105, 150, 245)
keyLabel.TextSize = 12
keyLabel.TextXAlignment = Enum.TextXAlignment.Left
keyLabel.Parent = content

local function updateRunningUI()
	if running then
		toggleButton.Text = "หยุดเก็บไข่"
		toggleButton.BackgroundColor3 = Color3.fromRGB(200, 65, 75)
	else
		toggleButton.Text = "เริ่มหาและเก็บไข่"
		toggleButton.BackgroundColor3 = Color3.fromRGB(45, 175, 105)
	end
end

local function pressE()
	VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
	task.wait(0.01)
	VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
end

local function forceReturn(rootPart, returnCFrame)
	VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
	if rootPart and rootPart.Parent and returnCFrame then
		rootPart.CFrame = returnCFrame
	end
end

local function collectEgg(egg, index, token, rootPart, originalCFrame)
	if not running or token ~= runToken or not egg or not egg.Parent or not rootPart.Parent then
		return false
	end

	local eggCFrame
	local eggSize

	if egg:IsA("Model") then
		eggCFrame, eggSize = egg:GetBoundingBox()
	elseif egg:IsA("BasePart") then
		eggCFrame = egg.CFrame
		eggSize = egg.Size
	else
		return false
	end

	local frontPosition = (eggCFrame * CFrame.new(0, 0, -(eggSize.Z / 2 + 1))).Position
	local teleportCFrame = CFrame.lookAt(frontPosition, eggCFrame.Position)
	local prompts = {}

	for _, object in ipairs(egg:GetDescendants()) do
		if object:IsA("ProximityPrompt") then
			makePromptInstant(object)
			table.insert(prompts, object)
		end
	end

	statusLabel.Text = string.format("สถานะ: กำลังเก็บใบที่ %d - %s", index, egg.Name)
	rootPart.CFrame = teleportCFrame
	task.wait(0.03)

	local startTime = os.clock()
	while running and token == runToken and os.clock() - startTime < TELEPORT_TIME do
		if not rootPart.Parent or not egg.Parent then
			break
		end

		rootPart.CFrame = teleportCFrame

		for _, prompt in ipairs(prompts) do
			if prompt.Parent and prompt.Enabled then
				makePromptInstant(prompt)
				if fireproximityprompt then
					fireproximityprompt(prompt, 0)
				end
			end
		end

		pressE()
		task.wait(0.03)
	end

	forceReturn(rootPart, originalCFrame)
	task.wait(WAIT_BETWEEN_EGGS)
	return running and token == runToken
end

local function stopCollecting(message)
	running = false
	runToken += 1
	updateRunningUI()
	statusLabel.Text = message or "สถานะ: หยุดแล้ว"
	VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
end

local function startCollecting()
	local requestedCount = tonumber(countInput.Text)
	if not requestedCount or requestedCount < 1 then
		statusLabel.Text = "สถานะ: กรุณาใส่จำนวนไข่ตั้งแต่ 1 ขึ้นไป"
		return
	end

	requestedCount = math.floor(requestedCount)
	countInput.Text = tostring(requestedCount)

	local _, rootPart = getCharacterParts()
	local originalCFrame = rootPart.CFrame
	local eggs = {}

	for _, object in ipairs(folder:GetChildren()) do
		if object:IsA("Model") or object:IsA("BasePart") then
			table.insert(eggs, object)
		end
	end

	if #eggs == 0 then
		statusLabel.Text = "สถานะ: ไม่พบไข่ใน AreaEggSlotsClient"
		return
	end

	local amountToCollect = math.min(requestedCount, #eggs)
	running = true
	runToken += 1
	local token = runToken
	updateRunningUI()

	task.spawn(function()
		for index = 1, amountToCollect do
			if not running or token ~= runToken then
				break
			end

			local collected = collectEgg(
				eggs[index],
				index,
				token,
				rootPart,
				originalCFrame
			)

			if not collected then
				break
			end

			if index < amountToCollect then
				statusLabel.Text = string.format(
					"สถานะ: จบรอบ %d/%d พัก %.1f วินาที",
					index,
					amountToCollect,
					DELAY_NEXT_ROUND
				)

				local delayStart = os.clock()
				while running and token == runToken and os.clock() - delayStart < DELAY_NEXT_ROUND do
					if not rootPart.Parent then
						break
					end
					rootPart.CFrame = originalCFrame
					task.wait(0.05)
				end
			end
		end

		forceReturn(rootPart, originalCFrame)

		if token == runToken then
			running = false
			updateRunningUI()
			statusLabel.Text = string.format("สถานะ: เก็บครบแล้ว %d ใบ", amountToCollect)
		end
	end)
end

toggleButton.MouseButton1Click:Connect(function()
	if running then
		stopCollecting("สถานะ: หยุดโดยผู้ใช้")
	else
		startCollecting()
	end
end)

minimizeButton.MouseButton1Click:Connect(function()
	minimized = not minimized
	content.Visible = not minimized
	main.Size = minimized and UDim2.fromOffset(330, 44) or UDim2.fromOffset(330, 245)
	minimizeButton.Text = minimized and "+" or "—"
end)

closeButton.MouseButton1Click:Connect(function()
	stopCollecting("สถานะ: ปิดโปรแกรม")
	screenGui:Destroy()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == TOGGLE_KEY and screenGui.Parent then
		guiVisible = not guiVisible
		main.Visible = guiVisible
	end
end)

updateRunningUI()
