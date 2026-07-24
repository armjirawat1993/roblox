--// Player Utility Menu
--// วางเป็น LocalScript ใน:
--// StarterPlayer > StarterPlayerScripts

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ป้องกัน GUI ซ้ำ
local oldGui = playerGui:FindFirstChild("PlayerUtilityMenu")

if oldGui then
	oldGui:Destroy()
end

--==================================================
-- Config
--==================================================

local PromptConfig = {
	Enabled = false,
	DefaultHoldDurations = {},
	Connection = nil,
}

local BoulderESPConfig = {
	Enabled = false,
	Connection = nil,
	Highlights = {},
	Folder = nil,
}

local AutoClickConfig = {
	Enabled = false,
	Interval = 0.1,
	MinInterval = 0.01,
	MaxInterval = 10,
	ToggleKey = Enum.KeyCode.F,
	Thread = nil,
}

--==================================================
-- ฟังก์ชันช่วยเหลือ
--==================================================

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = parent

	return corner
end

--==================================================
-- ระบบ ProximityPrompt
--==================================================

local function applyPrompt(object)
	if not object:IsA("ProximityPrompt") then
		return
	end

	if PromptConfig.DefaultHoldDurations[object] == nil then
		PromptConfig.DefaultHoldDurations[object] =
			object.HoldDuration
	end

	if PromptConfig.Enabled then
		object.HoldDuration = 0
	end
end

local function enablePrompt()
	if PromptConfig.Enabled then
		return
	end

	PromptConfig.Enabled = true

	for _, object in ipairs(Workspace:GetDescendants()) do
		applyPrompt(object)
	end

	if not PromptConfig.Connection then
		PromptConfig.Connection =
			Workspace.DescendantAdded:Connect(function(object)
				if PromptConfig.Enabled then
					applyPrompt(object)
				end
			end)
	end
end

local function disablePrompt()
	PromptConfig.Enabled = false

	for object, originalDuration in pairs(
		PromptConfig.DefaultHoldDurations
	) do
		if object and object.Parent then
			object.HoldDuration = originalDuration
		end
	end

	table.clear(PromptConfig.DefaultHoldDurations)

	if PromptConfig.Connection then
		PromptConfig.Connection:Disconnect()
		PromptConfig.Connection = nil
	end
end

local function togglePrompt(enabled)
	if enabled then
		enablePrompt()
	else
		disablePrompt()
	end
end

--==================================================
-- ระบบ ESP หิน
--==================================================

local function getBouldersFolder()
	if BoulderESPConfig.Folder
		and BoulderESPConfig.Folder.Parent then

		return BoulderESPConfig.Folder
	end

	local mountainDecorations =
		Workspace:FindFirstChild("MountainDecorations")

	if not mountainDecorations then
		warn("ไม่พบ Workspace.MountainDecorations")
		return nil
	end

	local boulders =
		mountainDecorations:FindFirstChild("Boulders")

	if not boulders then
		warn("ไม่พบ Workspace.MountainDecorations.Boulders")
		return nil
	end

	BoulderESPConfig.Folder = boulders

	return boulders
end

local function addBoulderESP(object)
	if not BoulderESPConfig.Enabled then
		return
	end

	if not object:IsA("Model")
		and not object:IsA("BasePart") then

		return
	end

	local oldHighlight = object:FindFirstChild("BlueESP")

	if oldHighlight then
		BoulderESPConfig.Highlights[object] = oldHighlight
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "BlueESP"
	highlight.Adornee = object

	highlight.FillColor = Color3.fromRGB(0, 120, 255)
	highlight.FillTransparency = 0.45

	highlight.OutlineColor = Color3.fromRGB(0, 200, 255)
	highlight.OutlineTransparency = 0

	highlight.DepthMode =
		Enum.HighlightDepthMode.AlwaysOnTop

	highlight.Enabled = true
	highlight.Parent = object

	BoulderESPConfig.Highlights[object] = highlight
end

local function removeBoulderESP()
	for object, highlight in pairs(
		BoulderESPConfig.Highlights
	) do
		if highlight and highlight.Parent then
			highlight:Destroy()
		end

		BoulderESPConfig.Highlights[object] = nil
	end

	local boulders = getBouldersFolder()

	if boulders then
		for _, object in ipairs(boulders:GetChildren()) do
			local highlight = object:FindFirstChild("BlueESP")

			if highlight then
				highlight:Destroy()
			end
		end
	end
end

local function enableBoulderESP()
	if BoulderESPConfig.Enabled then
		return
	end

	local boulders = getBouldersFolder()

	if not boulders then
		return
	end

	BoulderESPConfig.Enabled = true

	for _, object in ipairs(boulders:GetChildren()) do
		addBoulderESP(object)
	end

	if not BoulderESPConfig.Connection then
		BoulderESPConfig.Connection =
			boulders.ChildAdded:Connect(function(object)
				task.wait()

				if BoulderESPConfig.Enabled then
					addBoulderESP(object)
				end
			end)
	end
end

local function disableBoulderESP()
	BoulderESPConfig.Enabled = false

	if BoulderESPConfig.Connection then
		BoulderESPConfig.Connection:Disconnect()
		BoulderESPConfig.Connection = nil
	end

	removeBoulderESP()
end

local function toggleBoulderESP(enabled)
	if enabled then
		enableBoulderESP()
	else
		disableBoulderESP()
	end
end

--==================================================
-- ระบบ Auto Click Tool
--==================================================

local function performMouseAction()
	local character = player.Character

	if not character then
		return
	end

	local tool = character:FindFirstChildOfClass("Tool")

	if tool then
		tool:Activate()
	end
end

local function updateAutoClickInterval(value)
	value = tonumber(value)

	if not value then
		return false
	end

	value = math.clamp(
		value,
		AutoClickConfig.MinInterval,
		AutoClickConfig.MaxInterval
	)

	value = math.floor(value * 1000 + 0.5) / 1000

	AutoClickConfig.Interval = value

	return true
end

local function enableAutoClick()
	if AutoClickConfig.Enabled then
		return
	end

	AutoClickConfig.Enabled = true

	AutoClickConfig.Thread = task.spawn(function()
		while AutoClickConfig.Enabled do
			local success, errorMessage =
				pcall(performMouseAction)

			if not success then
				warn("Auto Click error:", errorMessage)
			end

			task.wait(AutoClickConfig.Interval)
		end
	end)
end

local function disableAutoClick()
	AutoClickConfig.Enabled = false

	if AutoClickConfig.Thread then
		task.cancel(AutoClickConfig.Thread)
		AutoClickConfig.Thread = nil
	end
end

local function toggleAutoClick(enabled)
	if enabled then
		enableAutoClick()
	else
		disableAutoClick()
	end
end

-- คลิกเมาส์จริงแล้ว Activate Tool
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType ==
		Enum.UserInputType.MouseButton1 then

		performMouseAction()
	end
end)

--==================================================
-- สร้าง GUI
--==================================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PlayerUtilityMenu"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.fromOffset(370, 475)
mainFrame.Position = UDim2.new(0.5, -185, 0.5, -237)
mainFrame.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui

addCorner(mainFrame, 12)

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(65, 70, 85)
mainStroke.Thickness = 1
mainStroke.Parent = mainFrame

--==================================================
-- Title Bar
--==================================================

local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 46)
titleBar.BackgroundColor3 = Color3.fromRGB(32, 35, 43)
titleBar.BorderSizePixel = 0
titleBar.Active = true
titleBar.Parent = mainFrame

addCorner(titleBar, 12)

local titleFix = Instance.new("Frame")
titleFix.Size = UDim2.new(1, 0, 0, 12)
titleFix.Position = UDim2.new(0, 0, 1, -12)
titleFix.BackgroundColor3 = titleBar.BackgroundColor3
titleFix.BorderSizePixel = 0
titleFix.Parent = titleBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -105, 1, 0)
titleLabel.Position = UDim2.fromOffset(16, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBold
titleLabel.Text = "PLAYER UTILITY"
titleLabel.TextColor3 = Color3.fromRGB(245, 245, 245)
titleLabel.TextSize = 16
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

local minimizeButton = Instance.new("TextButton")
minimizeButton.Size = UDim2.fromOffset(34, 30)
minimizeButton.Position = UDim2.new(1, -78, 0.5, -15)
minimizeButton.BackgroundColor3 = Color3.fromRGB(60, 64, 77)
minimizeButton.BorderSizePixel = 0
minimizeButton.Font = Enum.Font.GothamBold
minimizeButton.Text = "—"
minimizeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
minimizeButton.TextSize = 18
minimizeButton.Parent = titleBar

addCorner(minimizeButton, 7)

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.fromOffset(34, 30)
closeButton.Position = UDim2.new(1, -40, 0.5, -15)
closeButton.BackgroundColor3 = Color3.fromRGB(190, 58, 58)
closeButton.BorderSizePixel = 0
closeButton.Font = Enum.Font.GothamBold
closeButton.Text = "×"
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.TextSize = 20
closeButton.Parent = titleBar

addCorner(closeButton, 7)

--==================================================
-- Content
--==================================================

local contentFrame = Instance.new("ScrollingFrame")
contentFrame.Name = "ContentFrame"
contentFrame.Size = UDim2.new(1, -24, 1, -68)
contentFrame.Position = UDim2.fromOffset(12, 56)
contentFrame.BackgroundTransparency = 1
contentFrame.BorderSizePixel = 0
contentFrame.ScrollBarThickness = 4
contentFrame.ScrollBarImageColor3 =
	Color3.fromRGB(100, 105, 120)
contentFrame.CanvasSize = UDim2.fromOffset(0, 365)
contentFrame.Parent = mainFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 12)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = contentFrame

--==================================================
-- Prompt Section
--==================================================

local promptSection = Instance.new("Frame")
promptSection.Name = "PromptSection"
promptSection.Size = UDim2.new(1, -6, 0, 92)
promptSection.BackgroundColor3 = Color3.fromRGB(31, 34, 41)
promptSection.BorderSizePixel = 0
promptSection.LayoutOrder = 1
promptSection.Parent = contentFrame

addCorner(promptSection, 10)

local promptTitle = Instance.new("TextLabel")
promptTitle.Size = UDim2.new(1, -140, 0, 28)
promptTitle.Position = UDim2.fromOffset(14, 12)
promptTitle.BackgroundTransparency = 1
promptTitle.Font = Enum.Font.GothamSemibold
promptTitle.Text = "กด Prompt ทันที"
promptTitle.TextColor3 = Color3.fromRGB(245, 245, 245)
promptTitle.TextSize = 14
promptTitle.TextXAlignment = Enum.TextXAlignment.Left
promptTitle.Parent = promptSection

local promptDescription = Instance.new("TextLabel")
promptDescription.Size = UDim2.new(1, -140, 0, 36)
promptDescription.Position = UDim2.fromOffset(14, 40)
promptDescription.BackgroundTransparency = 1
promptDescription.Font = Enum.Font.Gotham
promptDescription.Text =
	"ตั้ง HoldDuration เป็น 0\nรวม Prompt ที่เกิดใหม่"
promptDescription.TextColor3 =
	Color3.fromRGB(145, 150, 163)
promptDescription.TextSize = 11
promptDescription.TextXAlignment = Enum.TextXAlignment.Left
promptDescription.TextYAlignment = Enum.TextYAlignment.Top
promptDescription.Parent = promptSection

local promptToggleButton = Instance.new("TextButton")
promptToggleButton.Size = UDim2.fromOffset(100, 38)
promptToggleButton.Position = UDim2.new(1, -114, 0.5, -19)
promptToggleButton.BackgroundColor3 =
	Color3.fromRGB(70, 73, 84)
promptToggleButton.BorderSizePixel = 0
promptToggleButton.Font = Enum.Font.GothamBold
promptToggleButton.Text = "ปิด"
promptToggleButton.TextColor3 =
	Color3.fromRGB(255, 255, 255)
promptToggleButton.TextSize = 13
promptToggleButton.Parent = promptSection

addCorner(promptToggleButton, 8)

--==================================================
-- Boulder ESP Section
--==================================================

local boulderESPSection = Instance.new("Frame")
boulderESPSection.Name = "BoulderESPSection"
boulderESPSection.Size = UDim2.new(1, -6, 0, 92)
boulderESPSection.BackgroundColor3 =
	Color3.fromRGB(31, 34, 41)
boulderESPSection.BorderSizePixel = 0
boulderESPSection.LayoutOrder = 2
boulderESPSection.Parent = contentFrame

addCorner(boulderESPSection, 10)

local boulderESPTitle = Instance.new("TextLabel")
boulderESPTitle.Size = UDim2.new(1, -140, 0, 28)
boulderESPTitle.Position = UDim2.fromOffset(14, 12)
boulderESPTitle.BackgroundTransparency = 1
boulderESPTitle.Font = Enum.Font.GothamSemibold
boulderESPTitle.Text = "ESP หิน"
boulderESPTitle.TextColor3 = Color3.fromRGB(245, 245, 245)
boulderESPTitle.TextSize = 14
boulderESPTitle.TextXAlignment = Enum.TextXAlignment.Left
boulderESPTitle.Parent = boulderESPSection

local boulderESPDescription = Instance.new("TextLabel")
boulderESPDescription.Size = UDim2.new(1, -140, 0, 36)
boulderESPDescription.Position = UDim2.fromOffset(14, 40)
boulderESPDescription.BackgroundTransparency = 1
boulderESPDescription.Font = Enum.Font.Gotham
boulderESPDescription.Text =
	"Highlight สีฟ้า\nมองเห็นทะลุสิ่งกีดขวาง"
boulderESPDescription.TextColor3 =
	Color3.fromRGB(145, 150, 163)
boulderESPDescription.TextSize = 11
boulderESPDescription.TextXAlignment =
	Enum.TextXAlignment.Left
boulderESPDescription.TextYAlignment =
	Enum.TextYAlignment.Top
boulderESPDescription.Parent = boulderESPSection

local boulderESPToggleButton = Instance.new("TextButton")
boulderESPToggleButton.Size = UDim2.fromOffset(100, 38)
boulderESPToggleButton.Position =
	UDim2.new(1, -114, 0.5, -19)
boulderESPToggleButton.BackgroundColor3 =
	Color3.fromRGB(70, 73, 84)
boulderESPToggleButton.BorderSizePixel = 0
boulderESPToggleButton.Font = Enum.Font.GothamBold
boulderESPToggleButton.Text = "ปิด"
boulderESPToggleButton.TextColor3 =
	Color3.fromRGB(255, 255, 255)
boulderESPToggleButton.TextSize = 13
boulderESPToggleButton.Parent = boulderESPSection

addCorner(boulderESPToggleButton, 8)

--==================================================
-- Auto Click Section
--==================================================

local autoClickSection = Instance.new("Frame")
autoClickSection.Name = "AutoClickSection"
autoClickSection.Size = UDim2.new(1, -6, 0, 145)
autoClickSection.BackgroundColor3 =
	Color3.fromRGB(31, 34, 41)
autoClickSection.BorderSizePixel = 0
autoClickSection.LayoutOrder = 3
autoClickSection.Parent = contentFrame

addCorner(autoClickSection, 10)

local autoClickTitle = Instance.new("TextLabel")
autoClickTitle.Size = UDim2.new(1, -140, 0, 28)
autoClickTitle.Position = UDim2.fromOffset(14, 10)
autoClickTitle.BackgroundTransparency = 1
autoClickTitle.Font = Enum.Font.GothamSemibold
autoClickTitle.Text = "Auto Click Tool"
autoClickTitle.TextColor3 = Color3.fromRGB(245, 245, 245)
autoClickTitle.TextSize = 14
autoClickTitle.TextXAlignment = Enum.TextXAlignment.Left
autoClickTitle.Parent = autoClickSection

local autoClickDescription = Instance.new("TextLabel")
autoClickDescription.Size = UDim2.new(1, -140, 0, 20)
autoClickDescription.Position = UDim2.fromOffset(14, 38)
autoClickDescription.BackgroundTransparency = 1
autoClickDescription.Font = Enum.Font.Gotham
autoClickDescription.Text = "ปุ่มลัดเปิด–ปิด: F"
autoClickDescription.TextColor3 =
	Color3.fromRGB(145, 150, 163)
autoClickDescription.TextSize = 11
autoClickDescription.TextXAlignment =
	Enum.TextXAlignment.Left
autoClickDescription.Parent = autoClickSection

local autoClickToggleButton = Instance.new("TextButton")
autoClickToggleButton.Size = UDim2.fromOffset(100, 38)
autoClickToggleButton.Position = UDim2.new(1, -114, 0, 14)
autoClickToggleButton.BackgroundColor3 =
	Color3.fromRGB(70, 73, 84)
autoClickToggleButton.BorderSizePixel = 0
autoClickToggleButton.Font = Enum.Font.GothamBold
autoClickToggleButton.Text = "ปิด"
autoClickToggleButton.TextColor3 =
	Color3.fromRGB(255, 255, 255)
autoClickToggleButton.TextSize = 13
autoClickToggleButton.Parent = autoClickSection

addCorner(autoClickToggleButton, 8)

local intervalLabel = Instance.new("TextLabel")
intervalLabel.Size = UDim2.fromOffset(90, 30)
intervalLabel.Position = UDim2.fromOffset(14, 78)
intervalLabel.BackgroundTransparency = 1
intervalLabel.Font = Enum.Font.GothamMedium
intervalLabel.Text = "Interval:"
intervalLabel.TextColor3 = Color3.fromRGB(220, 220, 225)
intervalLabel.TextSize = 13
intervalLabel.TextXAlignment = Enum.TextXAlignment.Left
intervalLabel.Parent = autoClickSection

local intervalTextBox = Instance.new("TextBox")
intervalTextBox.Size = UDim2.fromOffset(90, 36)
intervalTextBox.Position = UDim2.fromOffset(88, 74)
intervalTextBox.BackgroundColor3 =
	Color3.fromRGB(44, 47, 56)
intervalTextBox.BorderSizePixel = 0
intervalTextBox.ClearTextOnFocus = false
intervalTextBox.Font = Enum.Font.GothamSemibold
intervalTextBox.PlaceholderText = "0.01"
intervalTextBox.Text = tostring(AutoClickConfig.Interval)
intervalTextBox.TextColor3 =
	Color3.fromRGB(255, 255, 255)
intervalTextBox.TextSize = 13
intervalTextBox.Parent = autoClickSection

addCorner(intervalTextBox, 8)

local intervalApplyButton = Instance.new("TextButton")
intervalApplyButton.Size = UDim2.fromOffset(94, 36)
intervalApplyButton.Position =
	UDim2.new(1, -108, 0, 74)
intervalApplyButton.BackgroundColor3 =
	Color3.fromRGB(46, 120, 220)
intervalApplyButton.BorderSizePixel = 0
intervalApplyButton.Font = Enum.Font.GothamBold
intervalApplyButton.Text = "ปรับใช้"
intervalApplyButton.TextColor3 =
	Color3.fromRGB(255, 255, 255)
intervalApplyButton.TextSize = 13
intervalApplyButton.Parent = autoClickSection

addCorner(intervalApplyButton, 8)

local intervalInfoLabel = Instance.new("TextLabel")
intervalInfoLabel.Size = UDim2.new(1, -28, 0, 20)
intervalInfoLabel.Position = UDim2.fromOffset(14, 116)
intervalInfoLabel.BackgroundTransparency = 1
intervalInfoLabel.Font = Enum.Font.Gotham
intervalInfoLabel.Text =
	"ต่ำสุด 0.01 วินาที | ปัจจุบัน: "
	.. AutoClickConfig.Interval
intervalInfoLabel.TextColor3 =
	Color3.fromRGB(130, 135, 148)
intervalInfoLabel.TextSize = 10
intervalInfoLabel.TextXAlignment =
	Enum.TextXAlignment.Left
intervalInfoLabel.Parent = autoClickSection

--==================================================
-- Logo ตอนย่อ
--==================================================

local logoButton = Instance.new("TextButton")
logoButton.Name = "LogoButton"
logoButton.Size = UDim2.fromOffset(60, 60)
logoButton.Position = mainFrame.Position
logoButton.BackgroundColor3 = Color3.fromRGB(46, 120, 220)
logoButton.BorderSizePixel = 0
logoButton.Font = Enum.Font.GothamBlack
logoButton.Text = "P"
logoButton.TextColor3 = Color3.fromRGB(255, 255, 255)
logoButton.TextSize = 26
logoButton.Visible = false
logoButton.Active = true
logoButton.Parent = screenGui

local logoCorner = Instance.new("UICorner")
logoCorner.CornerRadius = UDim.new(1, 0)
logoCorner.Parent = logoButton

local logoStroke = Instance.new("UIStroke")
logoStroke.Color = Color3.fromRGB(105, 170, 255)
logoStroke.Thickness = 2
logoStroke.Parent = logoButton

--==================================================
-- ระบบลาก GUI
--==================================================

local function makeDraggable(guiObject, dragHandle)
	local dragging = false
	local dragStart
	local startPosition
	local currentDragInput

	dragHandle.InputBegan:Connect(function(input)
		if input.UserInputType ==
				Enum.UserInputType.MouseButton1
			or input.UserInputType ==
				Enum.UserInputType.Touch then

			dragging = true
			dragStart = input.Position
			startPosition = guiObject.Position

			input.Changed:Connect(function()
				if input.UserInputState ==
					Enum.UserInputState.End then

					dragging = false
				end
			end)
		end
	end)

	dragHandle.InputChanged:Connect(function(input)
		if input.UserInputType ==
				Enum.UserInputType.MouseMovement
			or input.UserInputType ==
				Enum.UserInputType.Touch then

			currentDragInput = input
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and input == currentDragInput then
			local delta = input.Position - dragStart

			guiObject.Position = UDim2.new(
				startPosition.X.Scale,
				startPosition.X.Offset + delta.X,
				startPosition.Y.Scale,
				startPosition.Y.Offset + delta.Y
			)
		end
	end)
end

makeDraggable(mainFrame, titleBar)
makeDraggable(logoButton, logoButton)

--==================================================
-- อัปเดตสถานะปุ่ม
--==================================================

local function updatePromptToggleUI()
	if PromptConfig.Enabled then
		promptToggleButton.Text = "เปิด"
		promptToggleButton.BackgroundColor3 =
			Color3.fromRGB(45, 170, 95)
	else
		promptToggleButton.Text = "ปิด"
		promptToggleButton.BackgroundColor3 =
			Color3.fromRGB(70, 73, 84)
	end
end

local function updateBoulderESPToggleUI()
	if BoulderESPConfig.Enabled then
		boulderESPToggleButton.Text = "เปิด"
		boulderESPToggleButton.BackgroundColor3 =
			Color3.fromRGB(45, 170, 95)
	else
		boulderESPToggleButton.Text = "ปิด"
		boulderESPToggleButton.BackgroundColor3 =
			Color3.fromRGB(70, 73, 84)
	end
end

local function updateAutoClickToggleUI()
	if AutoClickConfig.Enabled then
		autoClickToggleButton.Text = "เปิด"
		autoClickToggleButton.BackgroundColor3 =
			Color3.fromRGB(45, 170, 95)
	else
		autoClickToggleButton.Text = "ปิด"
		autoClickToggleButton.BackgroundColor3 =
			Color3.fromRGB(70, 73, 84)
	end
end

local function applyAutoClickInterval()
	local success =
		updateAutoClickInterval(intervalTextBox.Text)

	if success then
		intervalTextBox.Text =
			tostring(AutoClickConfig.Interval)

		intervalInfoLabel.Text =
			"ต่ำสุด 0.01 วินาที | ปัจจุบัน: "
			.. AutoClickConfig.Interval

		intervalTextBox.BackgroundColor3 =
			Color3.fromRGB(44, 47, 56)
	else
		intervalTextBox.Text =
			tostring(AutoClickConfig.Interval)

		intervalTextBox.BackgroundColor3 =
			Color3.fromRGB(130, 55, 55)
	end
end

--==================================================
-- Events
--==================================================

promptToggleButton.MouseButton1Click:Connect(function()
	togglePrompt(not PromptConfig.Enabled)
	updatePromptToggleUI()
end)

boulderESPToggleButton.MouseButton1Click:Connect(function()
	toggleBoulderESP(not BoulderESPConfig.Enabled)
	updateBoulderESPToggleUI()
end)

autoClickToggleButton.MouseButton1Click:Connect(function()
	toggleAutoClick(not AutoClickConfig.Enabled)
	updateAutoClickToggleUI()
end)

intervalApplyButton.MouseButton1Click:Connect(
	applyAutoClickInterval
)

intervalTextBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		applyAutoClickInterval()
	end
end)

intervalTextBox:GetPropertyChangedSignal("Text"):Connect(
	function()
		local filtered =
			intervalTextBox.Text:gsub("[^0-9%.]", "")

		local firstDot = filtered:find("%.")

		if firstDot then
			local beforeDot =
				filtered:sub(1, firstDot)

			local afterDot =
				filtered
					:sub(firstDot + 1)
					:gsub("%.", "")

			filtered = beforeDot .. afterDot
		end

		if intervalTextBox.Text ~= filtered then
			intervalTextBox.Text = filtered
		end
	end
)

-- กด G เปิด–ปิด Auto Click
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if UserInputService:GetFocusedTextBox() then
		return
	end

	if input.KeyCode == AutoClickConfig.ToggleKey then
		toggleAutoClick(not AutoClickConfig.Enabled)
		updateAutoClickToggleUI()
	end
end)

minimizeButton.MouseButton1Click:Connect(function()
	logoButton.Position = mainFrame.Position
	mainFrame.Visible = false
	logoButton.Visible = true
end)

logoButton.MouseButton1Click:Connect(function()
	mainFrame.Position = logoButton.Position
	logoButton.Visible = false
	mainFrame.Visible = true
end)

closeButton.MouseButton1Click:Connect(function()
	togglePrompt(false)
	toggleBoulderESP(false)
	toggleAutoClick(false)

	screenGui:Destroy()
end)

--==================================================
-- เริ่มต้น UI
--==================================================

updatePromptToggleUI()
updateBoulderESPToggleUI()
updateAutoClickToggleUI()
