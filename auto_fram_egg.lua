-- Egg Collector GUI
-- Toggle GUI: L

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local folder = workspace:WaitForChild("AreaEggSlotsClient")

local TOGGLE_KEY = Enum.KeyCode.L
local TELEPORT_TIME = 0.5
local DELAY_NEXT_ROUND = 1
local WAIT_BETWEEN_EGGS = 0.1
local EMPTY_CONFIRM_TIME = 1.5

-- ขอบเขต Zone ใช้ค่าแกน X จาก Position จุดเริ่มและจุดสิ้นสุด
local ZONES = {
	{Name = "First Zone", MinX = 576.90, MaxX = 619.76, Color = Color3.fromRGB(255, 230, 70)},
	{Name = "Lake", MinX = 703.63, MaxX = 772.56, Color = Color3.fromRGB(40, 170, 255)},
	{Name = "Desert", MinX = 895.85, MaxX = 966.46, Color = Color3.fromRGB(255, 145, 45)},
	{Name = "Jungle", MinX = 1145.36, MaxX = 1207.19, Color = Color3.fromRGB(45, 220, 90)},
	{Name = "Snow", MinX = 1422.21, MaxX = 1526.41, Color = Color3.fromRGB(190, 240, 255)},
	{Name = "Volcano", MinX = 1789.88, MaxX = 1920.64, Color = Color3.fromRGB(255, 55, 45)},
	{Name = "Abyss Ocean", MinX = 2195.42, MaxX = 2340.19, Color = Color3.fromRGB(35, 65, 210)},
	{Name = "Prehistoric", MinX = 2709.03, MaxX = 2840.94, Color = Color3.fromRGB(180, 90, 255)},
	{Name = "Cosmic", MinX = 3289.73, MaxX = 3456.04, Color = Color3.fromRGB(255, 70, 210)},
}

local selectedZones = {}
for _, zone in ipairs(ZONES) do
	selectedZones[zone.Name] = true
end

local running = false
local runToken = 0
local minimized = false
local scriptClosed = false
local promptData = {}
local eggHighlights = {}
local hideRenderedEnabled = false
local selectedSizeThreshold = 0
local autoFarmEnabled = false

local function isTransparencyObject(object)
	return object:IsA("BasePart")
		or object:IsA("Decal")
		or object:IsA("Texture")
end

local function getRenderedHideFolders()
	local folders = {}

	-- ใช้ GetChildren เพราะ Workspace มี PlacedEggRenders ชื่อซ้ำ 2 Folder
	for _, object in ipairs(Workspace:GetChildren()) do
		if object.Name == "ClientRenderedAssets"
			or object.Name == "PlacedEggRenders" then

			table.insert(folders, object)
		end
	end

	return folders
end

local function isInsideDirectRenderedModel(object)
	for _, targetFolder in ipairs(getRenderedHideFolders()) do
		local current = object

		while current and current.Parent ~= targetFolder do
			current = current.Parent
		end

		-- รับเฉพาะ Model ที่เป็นลูกโดยตรงของ Folder หลัก
		if current
			and current.Parent == targetFolder
			and current:IsA("Model") then

			return true
		end
	end

	return false
end

local function applyRenderedTransparency(object, transparency)
	if not isTransparencyObject(object)
		or not isInsideDirectRenderedModel(object) then

		return
	end

	object.Transparency = transparency
end

local function setRenderedHidden(enabled)
	hideRenderedEnabled = enabled
	local transparency = enabled and 1 or 0

	-- เลือกเฉพาะ Model ที่เป็นลูกโดยตรง ไม่ค้น Model ใน Folder ซ้อนอีกชั้น
	for _, targetFolder in ipairs(getRenderedHideFolders()) do
		for _, model in ipairs(targetFolder:GetChildren()) do
			if model:IsA("Model") then
				for _, object in ipairs(model:GetDescendants()) do
					if isTransparencyObject(object) then
						object.Transparency = transparency
					end
				end
			end
		end
	end
end

Workspace.DescendantAdded:Connect(function(object)
	task.defer(function()
		applyRenderedTransparency(
			object,
			hideRenderedEnabled and 1 or 0
		)
	end)
end)

local function getObjectPosition(object)
	if object:IsA("Model") then
		return object:GetPivot().Position
	elseif object:IsA("BasePart") then
		return object.Position
	end
	return nil
end

local function getObjectZone(object)
	local position = getObjectPosition(object)
	if not position then
		return nil
	end

	for _, zone in ipairs(ZONES) do
		local minX = math.min(zone.MinX, zone.MaxX)
		local maxX = math.max(zone.MinX, zone.MaxX)
		if position.X >= minX and position.X <= maxX then
			return zone
		end
	end

	return nil
end

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

local function setupPrompt(prompt)
	if scriptClosed or not prompt:IsA("ProximityPrompt") or promptData[prompt] then
		return
	end

	local data = {}
	promptData[prompt] = data
	makePromptInstant(prompt)

	data.HoldConnection = prompt:GetPropertyChangedSignal("HoldDuration"):Connect(function()
		if not scriptClosed and prompt.Parent and prompt.HoldDuration ~= 0 then
			prompt.HoldDuration = 0
		end
	end)

	data.DestroyConnection = prompt.Destroying:Connect(function()
		local currentData = promptData[prompt]
		if currentData then
			if currentData.HoldConnection then
				currentData.HoldConnection:Disconnect()
			end
			if currentData.DestroyConnection then
				currentData.DestroyConnection:Disconnect()
			end
			promptData[prompt] = nil
		end
	end)
end

local activePromptTriggers = setmetatable({}, {__mode = "k"})

local function triggerPromptInstant(prompt)
	if not prompt or not prompt.Parent or not prompt.Enabled then
		return
	end
	if activePromptTriggers[prompt] then
		return
	end

	activePromptTriggers[prompt] = true

	makePromptInstant(prompt)

	if fireproximityprompt then
		-- รูปแบบ argument ที่ 3 ช่วยข้ามการจำลองเวลาค้าง
		local success = pcall(function()
			fireproximityprompt(prompt, 0, true)
		end)

		if not success then
			pcall(function()
				fireproximityprompt(prompt, 0)
			end)
		end
	else
		-- Fallback กรณี executor ไม่มี fireproximityprompt
		pcall(function()
			prompt:InputHoldBegin()
			task.wait()
			prompt:InputHoldEnd()
		end)
	end

	activePromptTriggers[prompt] = nil
end

-- ใช้ Instant Prompt แบบเดียวกับ Main_world.lua และครอบคลุมทั้ง Workspace
for _, object in ipairs(Workspace:GetDescendants()) do
	if object:IsA("ProximityPrompt") then
		setupPrompt(object)
	end
end

Workspace.DescendantAdded:Connect(function(object)
	if object:IsA("ProximityPrompt") then
		task.defer(setupPrompt, object)
	end
end)

ProximityPromptService.PromptShown:Connect(function(prompt)
	if prompt:IsDescendantOf(folder) then
		makePromptInstant(prompt)
	end
end)

-- เมื่อผู้เล่นเริ่มกด E ให้จบ Prompt ทันทีโดยไม่ต้องรอวงโหลด
ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
	if prompt:IsDescendantOf(folder) then
		task.defer(triggerPromptInstant, prompt)
	end
end)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "EggCollectorGUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local function removeEggESP(egg)
	local highlight = eggHighlights[egg]
	if highlight then
		highlight:Destroy()
		eggHighlights[egg] = nil
	end
	if egg and egg.Parent then
		local existing = egg:FindFirstChild("EggZoneESP")
		if existing and existing:IsA("Highlight") then
			existing:Destroy()
		end
	end
end

local function addEggESP(egg)
	if not egg or not egg.Parent then
		return
	end
	if not egg:IsA("Model") and not egg:IsA("BasePart") then
		return
	end

	local zone = getObjectZone(egg)
	if not zone then
		removeEggESP(egg)
		return
	end

	removeEggESP(egg)
	local highlight = Instance.new("Highlight")
	highlight.Name = "EggZoneESP"
	highlight.Adornee = egg
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = zone.Color
	highlight.OutlineColor = zone.Color
	highlight.FillTransparency = 0.45
	highlight.OutlineTransparency = 0
	highlight.Parent = egg
	eggHighlights[egg] = highlight
end

-- เปิด ESP ไข่ทั้งหมดทันทีเมื่อรัน โดยแต่ละ Zone ใช้คนละสี
for _, object in ipairs(folder:GetChildren()) do
	addEggESP(object)
end

folder.ChildAdded:Connect(function(object)
	task.defer(addEggESP, object)
end)

folder.ChildRemoved:Connect(function(object)
	removeEggESP(object)
end)

-- บางเกมเขียน HoldDuration กลับ จึงบังคับ Instant ตลอดเวลาที่ GUI ทำงาน
task.spawn(function()
	while screenGui.Parent do
		for _, object in ipairs(folder:GetDescendants()) do
			if object:IsA("ProximityPrompt") then
				makePromptInstant(object)
			end
		end

		-- บังคับค่า 1 ตอน ON และค่า 0 ตอน OFF รวมทุก Model ใน Folder ย่อย
		setRenderedHidden(hideRenderedEnabled)
		task.wait(0.1)
	end
end)

-- Logo ที่แสดงแทนหน้าต่างเมื่อพับ
local logoButton = Instance.new("TextButton")
logoButton.Name = "EggCollectorLogo"
logoButton.Size = UDim2.fromOffset(62, 62)
logoButton.Position = UDim2.new(0.5, -31, 0.5, -31)
logoButton.BackgroundColor3 = Color3.fromRGB(35, 42, 57)
logoButton.BorderSizePixel = 0
logoButton.Font = Enum.Font.GothamBold
logoButton.Text = "EGG"
logoButton.TextColor3 = Color3.fromRGB(255, 230, 70)
logoButton.TextSize = 16
logoButton.Visible = false
logoButton.Active = true
logoButton.Draggable = true
logoButton.Parent = screenGui

local logoCorner = Instance.new("UICorner")
logoCorner.CornerRadius = UDim.new(1, 0)
logoCorner.Parent = logoButton

local logoStroke = Instance.new("UIStroke")
logoStroke.Color = Color3.fromRGB(75, 135, 255)
logoStroke.Thickness = 2
logoStroke.Parent = logoButton

local logoGradient = Instance.new("UIGradient")
logoGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(49, 60, 82)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(21, 25, 34)),
})
logoGradient.Rotation = 45
logoGradient.Parent = logoButton

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.fromOffset(330, 305)
main.Position = UDim2.new(0.5, -165, 0.5, -152)
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

local toggleButton = Instance.new("TextButton")
toggleButton.Size = UDim2.new(0.5, -4, 0, 42)
toggleButton.Position = UDim2.fromOffset(0, 0)
toggleButton.BackgroundColor3 = Color3.fromRGB(45, 175, 105)
toggleButton.Font = Enum.Font.GothamBold
toggleButton.Text = "เริ่มเก็บ"
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.TextSize = 14
toggleButton.Parent = content

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 8)
toggleCorner.Parent = toggleButton

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 0, 27)
statusLabel.Position = UDim2.fromOffset(0, 50)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Gotham
statusLabel.Text = "สถานะ: ปิด"
statusLabel.TextColor3 = Color3.fromRGB(170, 180, 200)
statusLabel.TextSize = 13
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = content

local keyLabel = Instance.new("TextLabel")
keyLabel.Size = UDim2.new(1, 0, 0, 23)
keyLabel.Position = UDim2.fromOffset(0, 80)
keyLabel.BackgroundTransparency = 1
keyLabel.Font = Enum.Font.Gotham
keyLabel.Text = "L = พับเป็น Logo / เปิดหน้าต่าง"
keyLabel.TextColor3 = Color3.fromRGB(105, 150, 245)
keyLabel.TextSize = 12
keyLabel.TextXAlignment = Enum.TextXAlignment.Left
keyLabel.Parent = content

local zoneButton = Instance.new("TextButton")
zoneButton.Size = UDim2.new(1, 0, 0, 38)
zoneButton.Position = UDim2.fromOffset(0, 110)
zoneButton.BackgroundColor3 = Color3.fromRGB(64, 105, 190)
zoneButton.Font = Enum.Font.GothamBold
zoneButton.TextColor3 = Color3.fromRGB(255, 255, 255)
zoneButton.TextSize = 14
zoneButton.Parent = content

local zoneButtonCorner = Instance.new("UICorner")
zoneButtonCorner.CornerRadius = UDim.new(0, 8)
zoneButtonCorner.Parent = zoneButton

local hideRenderedButton = Instance.new("TextButton")
hideRenderedButton.Size = UDim2.new(1, 0, 0, 38)
hideRenderedButton.Position = UDim2.fromOffset(0, 155)
hideRenderedButton.BackgroundColor3 = Color3.fromRGB(55, 61, 75)
hideRenderedButton.Font = Enum.Font.GothamBold
hideRenderedButton.Text = "ซ่อนสัตว์และไข่: OFF"
hideRenderedButton.TextColor3 = Color3.fromRGB(255, 255, 255)
hideRenderedButton.TextSize = 14
hideRenderedButton.Parent = content

local hideRenderedCorner = Instance.new("UICorner")
hideRenderedCorner.CornerRadius = UDim.new(0, 8)
hideRenderedCorner.Parent = hideRenderedButton

local sizeFilterButton = Instance.new("TextButton")
sizeFilterButton.Size = UDim2.new(1, 0, 0, 38)
sizeFilterButton.Position = UDim2.fromOffset(0, 200)
sizeFilterButton.BackgroundColor3 = Color3.fromRGB(110, 75, 175)
sizeFilterButton.Font = Enum.Font.GothamBold
sizeFilterButton.Text = "Filter Hitbox Size: > 0"
sizeFilterButton.TextColor3 = Color3.fromRGB(255, 255, 255)
sizeFilterButton.TextSize = 14
sizeFilterButton.Parent = content

local sizeFilterCorner = Instance.new("UICorner")
sizeFilterCorner.CornerRadius = UDim.new(0, 8)
sizeFilterCorner.Parent = sizeFilterButton

local autoFarmButton = Instance.new("TextButton")
autoFarmButton.Size = UDim2.new(0.5, -4, 0, 42)
autoFarmButton.Position = UDim2.new(0.5, 4, 0, 0)
autoFarmButton.BackgroundColor3 = Color3.fromRGB(55, 61, 75)
autoFarmButton.Font = Enum.Font.GothamBold
autoFarmButton.Text = "Auto Farm: OFF"
autoFarmButton.TextColor3 = Color3.fromRGB(255, 255, 255)
autoFarmButton.TextSize = 14
autoFarmButton.Parent = content

local autoFarmCorner = Instance.new("UICorner")
autoFarmCorner.CornerRadius = UDim.new(0, 8)
autoFarmCorner.Parent = autoFarmButton

local sizeFilterPanel = Instance.new("Frame")
sizeFilterPanel.Name = "SizeFilterPanel"
sizeFilterPanel.Size = UDim2.fromOffset(150, 256)
sizeFilterPanel.Position = UDim2.new(0, -160, 0, 110)
sizeFilterPanel.BackgroundColor3 = Color3.fromRGB(22, 25, 32)
sizeFilterPanel.BorderSizePixel = 0
sizeFilterPanel.Visible = false
sizeFilterPanel.Parent = main

local sizePanelCorner = Instance.new("UICorner")
sizePanelCorner.CornerRadius = UDim.new(0, 10)
sizePanelCorner.Parent = sizeFilterPanel

local sizePanelStroke = Instance.new("UIStroke")
sizePanelStroke.Color = Color3.fromRGB(165, 100, 235)
sizePanelStroke.Thickness = 1.5
sizePanelStroke.Parent = sizeFilterPanel

local sizeTitle = Instance.new("TextLabel")
sizeTitle.Size = UDim2.new(1, 0, 0, 34)
sizeTitle.BackgroundTransparency = 1
sizeTitle.Font = Enum.Font.GothamBold
sizeTitle.Text = "เลือกขนาดไข่"
sizeTitle.TextColor3 = Color3.fromRGB(240, 244, 255)
sizeTitle.TextSize = 13
sizeTitle.Parent = sizeFilterPanel

local sizeOptionButtons = {}

local function refreshSizeFilterUI()
	sizeFilterButton.Text = string.format(
		"Filter Hitbox Size: > %g",
		selectedSizeThreshold
	)

	for threshold, button in pairs(sizeOptionButtons) do
		local selected = threshold == selectedSizeThreshold
		button.Text = (selected and "[✓] " or "[ ] ") .. "> " .. threshold
		button.BackgroundColor3 = selected
			and Color3.fromRGB(105, 65, 165)
			or Color3.fromRGB(48, 53, 65)
	end
end

for index, threshold in ipairs({0, 1, 1.5, 2, 2.5, 3}) do
	local option = Instance.new("TextButton")
	option.Size = UDim2.new(1, -12, 0, 31)
	option.Position = UDim2.fromOffset(6, 35 + (index - 1) * 36)
	option.BorderSizePixel = 0
	option.Font = Enum.Font.GothamMedium
	option.TextColor3 = Color3.fromRGB(255, 255, 255)
	option.TextSize = 13
	option.Parent = sizeFilterPanel

	local optionCorner = Instance.new("UICorner")
	optionCorner.CornerRadius = UDim.new(0, 6)
	optionCorner.Parent = option

	sizeOptionButtons[threshold] = option
	option.MouseButton1Click:Connect(function()
		selectedSizeThreshold = threshold
		sizeFilterPanel.Visible = false
		refreshSizeFilterUI()
	end)
end

sizeFilterButton.MouseButton1Click:Connect(function()
	sizeFilterPanel.Visible = not sizeFilterPanel.Visible
end)

refreshSizeFilterUI()

local zonePanel = Instance.new("Frame")
zonePanel.Name = "ZonePanel"
zonePanel.Size = UDim2.fromOffset(250, 375)
zonePanel.Position = UDim2.new(1, 10, 0, 0)
zonePanel.BackgroundColor3 = Color3.fromRGB(22, 25, 32)
zonePanel.BorderSizePixel = 0
zonePanel.Visible = false
zonePanel.Parent = main

local zonePanelCorner = Instance.new("UICorner")
zonePanelCorner.CornerRadius = UDim.new(0, 10)
zonePanelCorner.Parent = zonePanel

local zonePanelStroke = Instance.new("UIStroke")
zonePanelStroke.Color = Color3.fromRGB(75, 135, 255)
zonePanelStroke.Thickness = 1.5
zonePanelStroke.Parent = zonePanel

local zoneTitle = Instance.new("TextLabel")
zoneTitle.Size = UDim2.new(1, -20, 0, 38)
zoneTitle.Position = UDim2.fromOffset(10, 5)
zoneTitle.BackgroundTransparency = 1
zoneTitle.Font = Enum.Font.GothamBold
zoneTitle.Text = "เลือก Zone (เลือกได้หลายโซน)"
zoneTitle.TextColor3 = Color3.fromRGB(240, 244, 255)
zoneTitle.TextSize = 14
zoneTitle.TextXAlignment = Enum.TextXAlignment.Left
zoneTitle.Parent = zonePanel

local selectAllButton = Instance.new("TextButton")
selectAllButton.Size = UDim2.new(0.5, -13, 0, 32)
selectAllButton.Position = UDim2.fromOffset(10, 44)
selectAllButton.BackgroundColor3 = Color3.fromRGB(45, 175, 105)
selectAllButton.Font = Enum.Font.GothamBold
selectAllButton.Text = "เลือกทั้งหมด"
selectAllButton.TextColor3 = Color3.fromRGB(255, 255, 255)
selectAllButton.TextSize = 12
selectAllButton.Parent = zonePanel

local clearAllButton = Instance.new("TextButton")
clearAllButton.Size = UDim2.new(0.5, -13, 0, 32)
clearAllButton.Position = UDim2.new(0.5, 3, 0, 44)
clearAllButton.BackgroundColor3 = Color3.fromRGB(180, 65, 75)
clearAllButton.Font = Enum.Font.GothamBold
clearAllButton.Text = "ยกเลิกทั้งหมด"
clearAllButton.TextColor3 = Color3.fromRGB(255, 255, 255)
clearAllButton.TextSize = 12
clearAllButton.Parent = zonePanel

for _, button in ipairs({selectAllButton, clearAllButton}) do
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 7)
	corner.Parent = button
end

local zoneList = Instance.new("ScrollingFrame")
zoneList.Size = UDim2.new(1, -20, 1, -91)
zoneList.Position = UDim2.fromOffset(10, 83)
zoneList.BackgroundColor3 = Color3.fromRGB(30, 34, 43)
zoneList.BorderSizePixel = 0
zoneList.ScrollBarThickness = 5
zoneList.CanvasSize = UDim2.fromOffset(0, #ZONES * 36 + 8)
zoneList.Parent = zonePanel

local zoneListCorner = Instance.new("UICorner")
zoneListCorner.CornerRadius = UDim.new(0, 8)
zoneListCorner.Parent = zoneList

local zoneButtons = {}

local function countSelectedZones()
	local count = 0
	for _, zone in ipairs(ZONES) do
		if selectedZones[zone.Name] then
			count += 1
		end
	end
	return count
end

local function refreshZoneUI()
	local selectedCount = countSelectedZones()
	zoneButton.Text = string.format("เลือก Zone: %d/%d", selectedCount, #ZONES)

	for zoneName, button in pairs(zoneButtons) do
		local selected = selectedZones[zoneName]
		button.Text = (selected and "[✓] " or "[ ] ") .. zoneName
		button.BackgroundColor3 = selected
			and Color3.fromRGB(54, 115, 90)
			or Color3.fromRGB(48, 53, 65)
	end
end

for index, zone in ipairs(ZONES) do
	local zoneOption = Instance.new("TextButton")
	zoneOption.Size = UDim2.new(1, -10, 0, 31)
	zoneOption.Position = UDim2.fromOffset(5, 4 + (index - 1) * 36)
	zoneOption.BorderSizePixel = 0
	zoneOption.Font = Enum.Font.GothamMedium
	zoneOption.TextColor3 = Color3.fromRGB(245, 245, 250)
	zoneOption.TextSize = 13
	zoneOption.TextXAlignment = Enum.TextXAlignment.Left
	zoneOption.Parent = zoneList

	local optionPadding = Instance.new("UIPadding")
	optionPadding.PaddingLeft = UDim.new(0, 10)
	optionPadding.Parent = zoneOption

	local optionCorner = Instance.new("UICorner")
	optionCorner.CornerRadius = UDim.new(0, 6)
	optionCorner.Parent = zoneOption

	zoneButtons[zone.Name] = zoneOption
	zoneOption.MouseButton1Click:Connect(function()
		selectedZones[zone.Name] = not selectedZones[zone.Name]
		refreshZoneUI()
	end)
end

zoneButton.MouseButton1Click:Connect(function()
	zonePanel.Visible = not zonePanel.Visible
	sizeFilterPanel.Visible = false
end)

selectAllButton.MouseButton1Click:Connect(function()
	for _, zone in ipairs(ZONES) do
		selectedZones[zone.Name] = true
	end
	refreshZoneUI()
end)

clearAllButton.MouseButton1Click:Connect(function()
	for _, zone in ipairs(ZONES) do
		selectedZones[zone.Name] = false
	end
	refreshZoneUI()
end)

refreshZoneUI()

local function updateRunningUI()
	if running then
		toggleButton.Text = "หยุดเก็บ"
		toggleButton.BackgroundColor3 = Color3.fromRGB(200, 65, 75)
	else
		toggleButton.Text = "เริ่มเก็บ"
		toggleButton.BackgroundColor3 = Color3.fromRGB(45, 175, 105)
	end
end

local function updateAutoFarmUI()
	if autoFarmEnabled then
		autoFarmButton.Text = "Auto Farm: ON"
		autoFarmButton.BackgroundColor3 = Color3.fromRGB(45, 175, 105)
	else
		autoFarmButton.Text = "Auto Farm: OFF"
		autoFarmButton.BackgroundColor3 = Color3.fromRGB(55, 61, 75)
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

	if egg:IsA("Model") then
		eggCFrame = egg:GetBoundingBox()
	elseif egg:IsA("BasePart") then
		eggCFrame = egg.CFrame
	else
		return false
	end

	-- วาร์ปเข้าศูนย์กลางไข่โดยตรง ป้องกันไข่ใหญ่ดันตัวออกนอกแมพ
	local teleportCFrame = CFrame.new(eggCFrame.Position)
	local prompts = {}

	for _, object in ipairs(egg:GetDescendants()) do
		if object:IsA("ProximityPrompt") then
			makePromptInstant(object)
			table.insert(prompts, object)
		end
	end

	local currentZone = getObjectZone(egg)
	statusLabel.Text = string.format(
		"สถานะ: %s | ใบที่ %d - %s",
		currentZone and currentZone.Name or "Unknown Zone",
		index,
		egg.Name
	)

	-- ล็อกตำแหน่ง 2 ช่วงต่อเฟรมเพื่อกันเกมดึงตัวกลับ
	local function lockAtEgg()
		if running
			and token == runToken
			and rootPart.Parent
			and egg.Parent then

			rootPart.CFrame = teleportCFrame
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero
		end
	end

	lockAtEgg()
	local steppedLock = RunService.Stepped:Connect(lockAtEgg)
	local heartbeatLock = RunService.Heartbeat:Connect(lockAtEgg)
	RunService.Heartbeat:Wait()

	local startTime = os.clock()
	while running and token == runToken and os.clock() - startTime < TELEPORT_TIME do
		if not rootPart.Parent or not egg.Parent then
			break
		end

		rootPart.CFrame = teleportCFrame

		for _, prompt in ipairs(prompts) do
			if prompt.Parent and prompt.Enabled then
				makePromptInstant(prompt)
				triggerPromptInstant(prompt)
			end
		end

		pressE()
		-- pressE มี yield 0.01 อยู่แล้ว จึงวนรอบต่อทันทีโดยไม่หน่วงเพิ่ม
	end

	steppedLock:Disconnect()
	heartbeatLock:Disconnect()

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

local function findEggHitbox(egg)
	if egg:IsA("BasePart") and string.lower(egg.Name) == "hitbox" then
		return egg
	end

	for _, object in ipairs(egg:GetDescendants()) do
		if object:IsA("BasePart")
			and string.lower(object.Name) == "hitbox" then

			return object
		end
	end
	return nil
end

local function getHitboxSizeData(egg)
	local hitbox = findEggHitbox(egg)
	if not hitbox then
		return 0, 0
	end

	local size = hitbox.Size
	local maxSize = math.max(size.X, size.Y, size.Z)
	local volume = size.X * size.Y * size.Z
	return maxSize, volume
end

local function getSortedSelectedEggs()
	local eggs = {}
	local eggSortData = {}
	local originalIndex = 0

	for _, object in ipairs(folder:GetChildren()) do
		if object:IsA("Model") or object:IsA("BasePart") then
			originalIndex += 1
			local zone = getObjectZone(object)
			if zone and selectedZones[zone.Name] then
				local maxSize, volume = getHitboxSizeData(object)
				if maxSize > selectedSizeThreshold then
					eggSortData[object] = {
						MaxSize = maxSize,
						Volume = volume,
						OriginalIndex = originalIndex,
					}
					table.insert(eggs, object)
				end
			end
		end
	end


	-- รวมไข่จากทุก Zone ที่เลือก แล้วเรียง Size ใหญ่ที่สุดก่อนแบบ Global
	table.sort(eggs, function(eggA, eggB)
		local dataA = eggSortData[eggA]
		local dataB = eggSortData[eggB]

		if dataA.MaxSize ~= dataB.MaxSize then
			return dataA.MaxSize > dataB.MaxSize
		end
		if dataA.Volume ~= dataB.Volume then
			return dataA.Volume > dataB.Volume
		end
		return dataA.OriginalIndex < dataB.OriginalIndex
	end)

	return eggs
end

local function startCollecting(continuousMode)
	local selectedZoneCount = countSelectedZones()
	if selectedZoneCount == 0 then
		statusLabel.Text = "สถานะ: กรุณาเลือกอย่างน้อย 1 Zone"
		return false
	end

	local _, rootPart = getCharacterParts()
	local originalCFrame = rootPart.CFrame
	local eggs = getSortedSelectedEggs()

	if #eggs == 0 and not continuousMode then
		statusLabel.Text = string.format(
			"สถานะ: ไม่พบไข่ Size > %g ใน Zone ที่เลือก",
			selectedSizeThreshold
		)
		return false
	end

	running = true
	runToken += 1
	local token = runToken
	local collectedCount = 0
	local completedBecauseEmpty = false
	updateRunningUI()
	if #eggs > 0 then
		statusLabel.Text = string.format(
			"สถานะ: พบ %d ใบ | %d Zone | Size > %g",
			#eggs,
			selectedZoneCount,
			selectedSizeThreshold
		)
	else
		statusLabel.Text = "สถานะ: Auto Farm รอไข่เกิดใหม่..."
	end

	task.spawn(function()
		while running and token == runToken do
			if not rootPart.Parent then
				statusLabel.Text = "สถานะ: ตัวละครหาย หยุดเก็บไข่"
				break
			end

			-- สแกนใหม่ทุกครั้ง ป้องกันรายการเดิมหมดอายุเมื่อไข่ถูกลบ/สร้างใหม่
			eggs = getSortedSelectedEggs()

			if #eggs == 0 then
				if continuousMode then
					statusLabel.Text = string.format(
						"สถานะ: Auto Farm รอไข่ Size > %g...",
						selectedSizeThreshold
					)
					task.wait(0.25)
					continue
				end

				statusLabel.Text = "สถานะ: กำลังตรวจยืนยันว่าไข่หมด..."
				local emptyStart = os.clock()
				local foundNewEgg = false

				while running
					and token == runToken
					and os.clock() - emptyStart < EMPTY_CONFIRM_TIME do

					task.wait(0.15)
					if #getSortedSelectedEggs() > 0 then
						foundNewEgg = true
						break
					end
				end

				if not foundNewEgg then
					completedBecauseEmpty = true
					break
				end
				continue
			end

			local egg = eggs[1]
			local collected = collectEgg(
				egg,
				collectedCount + 1,
				token,
				rootPart,
				originalCFrame
			)

			if collected then
				collectedCount += 1
			else
				-- Object อาจถูกผู้เล่นอื่นเก็บก่อน ให้ข้ามและสแกนใหม่
				task.wait(0.05)
			end

			if running and token == runToken then
				local delayStart = os.clock()
				while running
					and token == runToken
					and os.clock() - delayStart < DELAY_NEXT_ROUND do

					rootPart.CFrame = originalCFrame
					task.wait(0.05)
				end
			end
		end

		forceReturn(rootPart, originalCFrame)

		if token == runToken then
			running = false
			if continuousMode then
				autoFarmEnabled = false
				updateAutoFarmUI()
			end
			updateRunningUI()
			if completedBecauseEmpty then
				statusLabel.Text = string.format(
					"สถานะ: ไข่ใน Zone ที่เลือกหมดแล้ว เก็บ %d รอบ",
					collectedCount
				)
			end
		end
	end)

	return true
end

toggleButton.MouseButton1Click:Connect(function()
	if running then
		autoFarmEnabled = false
		updateAutoFarmUI()
		stopCollecting("สถานะ: หยุดโดยผู้ใช้")
	else
		startCollecting(false)
	end
end)

autoFarmButton.MouseButton1Click:Connect(function()
	if autoFarmEnabled then
		autoFarmEnabled = false
		updateAutoFarmUI()
		stopCollecting("สถานะ: ปิด Auto Farm")
		return
	end

	if running then
		stopCollecting("สถานะ: เปลี่ยนเป็น Auto Farm")
	end

	autoFarmEnabled = true
	updateAutoFarmUI()

	if not startCollecting(true) then
		autoFarmEnabled = false
		updateAutoFarmUI()
	end
end)

hideRenderedButton.MouseButton1Click:Connect(function()
	setRenderedHidden(not hideRenderedEnabled)

	if hideRenderedEnabled then
		hideRenderedButton.Text = "ซ่อนสัตว์และไข่: ON"
		hideRenderedButton.BackgroundColor3 = Color3.fromRGB(45, 175, 105)
	else
		hideRenderedButton.Text = "ซ่อนสัตว์และไข่: OFF"
		hideRenderedButton.BackgroundColor3 = Color3.fromRGB(55, 61, 75)
	end
end)

local function minimizeToLogo()
	if minimized then
		return
	end

	minimized = true
	zonePanel.Visible = false
	sizeFilterPanel.Visible = false
	logoButton.Position = main.Position
	main.Visible = false
	logoButton.Visible = true
end

local function restoreFromLogo()
	if not minimized then
		return
	end

	minimized = false
	main.Position = logoButton.Position
	logoButton.Visible = false
	main.Visible = true
end

minimizeButton.MouseButton1Click:Connect(minimizeToLogo)
logoButton.MouseButton1Click:Connect(restoreFromLogo)

closeButton.MouseButton1Click:Connect(function()
	scriptClosed = true
	autoFarmEnabled = false
	stopCollecting("สถานะ: ปิดโปรแกรม")
	setRenderedHidden(false)

	for egg in pairs(eggHighlights) do
		removeEggESP(egg)
	end

	for prompt, data in pairs(promptData) do
		if data.HoldConnection then
			data.HoldConnection:Disconnect()
		end
		if data.DestroyConnection then
			data.DestroyConnection:Disconnect()
		end
		promptData[prompt] = nil
	end

	screenGui:Destroy()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == TOGGLE_KEY and screenGui.Parent then
		if minimized then
			restoreFromLogo()
		else
			minimizeToLogo()
		end
	end
end)

updateRunningUI()
updateAutoFarmUI()
