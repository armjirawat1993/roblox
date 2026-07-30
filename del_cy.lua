local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local crystalsFolder = Workspace
	:WaitForChild("Things")
	:WaitForChild("Crystals")

local currentMinValue = 10000000
local running = true
local autoDeleteEnabled = true

-- ลบหน้าต่างเก่า
local oldGui = playerGui:FindFirstChild("CrystalValueRemover")

if oldGui then
	oldGui:Destroy()
end

-- GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CrystalValueRemover"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.fromOffset(290, 205)
mainFrame.Position = UDim2.new(0.5, -145, 0.5, -102)
mainFrame.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = screenGui

Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -50, 0, 38)
title.Position = UDim2.fromOffset(12, 0)
title.BackgroundTransparency = 1
title.Text = "Crystal Remover"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextSize = 16
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = mainFrame

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.fromOffset(38, 38)
closeButton.Position = UDim2.new(1, -38, 0, 0)
closeButton.BackgroundTransparency = 1
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(255, 80, 80)
closeButton.TextSize = 18
closeButton.Font = Enum.Font.GothamBold
closeButton.Parent = mainFrame

local valueLabel = Instance.new("TextLabel")
valueLabel.Size = UDim2.new(1, -24, 0, 24)
valueLabel.Position = UDim2.fromOffset(12, 40)
valueLabel.BackgroundTransparency = 1
valueLabel.Text = "ลบ Crystal ที่มีค่าต่ำกว่า"
valueLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
valueLabel.TextSize = 13
valueLabel.Font = Enum.Font.Gotham
valueLabel.TextXAlignment = Enum.TextXAlignment.Left
valueLabel.Parent = mainFrame

local valueBox = Instance.new("TextBox")
valueBox.Size = UDim2.new(1, -24, 0, 36)
valueBox.Position = UDim2.fromOffset(12, 67)
valueBox.BackgroundColor3 = Color3.fromRGB(45, 45, 53)
valueBox.BorderSizePixel = 0
valueBox.Text = tostring(currentMinValue)
valueBox.PlaceholderText = "ตัวอย่าง 50000000"
valueBox.TextColor3 = Color3.fromRGB(255, 255, 255)
valueBox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
valueBox.TextSize = 14
valueBox.Font = Enum.Font.Gotham
valueBox.ClearTextOnFocus = false
valueBox.Parent = mainFrame

Instance.new("UICorner", valueBox).CornerRadius = UDim.new(0, 6)

local confirmButton = Instance.new("TextButton")
confirmButton.Size = UDim2.new(1, -24, 0, 36)
confirmButton.Position = UDim2.fromOffset(12, 111)
confirmButton.BackgroundColor3 = Color3.fromRGB(45, 145, 240)
confirmButton.BorderSizePixel = 0
confirmButton.Text = "ยืนยันและลบทันที"
confirmButton.TextColor3 = Color3.fromRGB(255, 255, 255)
confirmButton.TextSize = 14
confirmButton.Font = Enum.Font.GothamBold
confirmButton.Parent = mainFrame

Instance.new("UICorner", confirmButton).CornerRadius = UDim.new(0, 6)

local toggleButton = Instance.new("TextButton")
toggleButton.Size = UDim2.new(0.48, -6, 0, 34)
toggleButton.Position = UDim2.fromOffset(12, 155)
toggleButton.BackgroundColor3 = Color3.fromRGB(45, 170, 90)
toggleButton.BorderSizePixel = 0
toggleButton.Text = "Auto: ON"
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.TextSize = 13
toggleButton.Font = Enum.Font.GothamBold
toggleButton.Parent = mainFrame

Instance.new("UICorner", toggleButton).CornerRadius = UDim.new(0, 6)

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(0.52, -6, 0, 34)
statusLabel.Position = UDim2.new(0.48, 6, 0, 155)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "พร้อมทำงาน"
statusLabel.TextColor3 = Color3.fromRGB(190, 190, 190)
statusLabel.TextSize = 12
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextWrapped = true
statusLabel.Parent = mainFrame

-- แปลงข้อความเป็นตัวเลข
local function parseNumber(value)
	if value == nil then
		return nil
	end

	if typeof(value) == "number" then
		return value
	end

	local text = tostring(value)

	-- ลบ comma, ช่องว่าง และตัวอักษรที่ไม่ใช่ตัวเลข
	text = text:gsub(",", "")
	text = text:gsub("%s+", "")

	local directNumber = tonumber(text)

	if directNumber then
		return directNumber
	end

	-- รองรับข้อความ เช่น "$50,000,000" หรือ "Value: 50000000"
	local extracted = text:match("%-?%d+%.?%d*")

	if extracted then
		return tonumber(extracted)
	end

	return nil
end

-- ค้นหาค่าของ Crystal
local function getCrystalValue(crystal)
	-- กรณี Crystal เองเป็น Value Object
	if crystal:IsA("NumberValue")
		or crystal:IsA("IntValue")
		or crystal:IsA("StringValue") then

		return parseNumber(crystal.Value)
	end

	-- ตรวจ Attribute ทั้งหมด
	for attributeName, attributeValue in pairs(crystal:GetAttributes()) do
		local lowerName = string.lower(attributeName)

		if lowerName == "value"
			or lowerName == "price"
			or lowerName == "worth"
			or lowerName == "amount"
			or lowerName == "cost" then

			local number = parseNumber(attributeValue)

			if number then
				return number
			end
		end
	end

	-- ตรวจ Object ลูกทั้งหมด
	for _, object in ipairs(crystal:GetDescendants()) do
		if object:IsA("NumberValue")
			or object:IsA("IntValue")
			or object:IsA("StringValue") then

			local lowerName = string.lower(object.Name)

			-- ให้ความสำคัญกับชื่อที่เกี่ยวกับราคา
			if lowerName == "value"
				or lowerName == "price"
				or lowerName == "worth"
				or lowerName == "amount"
				or lowerName == "cost"
				or lowerName:find("value")
				or lowerName:find("price") then

				local number = parseNumber(object.Value)

				if number then
					return number
				end
			end
		end
	end

	-- หากไม่พบชื่อเฉพาะ ให้ใช้ Value Object ตัวเลขตัวแรก
	for _, object in ipairs(crystal:GetDescendants()) do
		if object:IsA("NumberValue") or object:IsA("IntValue") then
			return object.Value
		end

		if object:IsA("StringValue") then
			local number = parseNumber(object.Value)

			if number then
				return number
			end
		end
	end

	return nil
end

local function deleteLowValueCrystals()
	local deletedCount = 0
	local checkedCount = 0
	local noValueCount = 0

	-- สร้างรายการก่อนลบ ป้องกัน loop เพี้ยน
	local crystals = crystalsFolder:GetChildren()

	for _, crystal in ipairs(crystals) do
		if crystal and crystal.Parent == crystalsFolder then
			checkedCount += 1

			local crystalValue = getCrystalValue(crystal)

			if crystalValue then
				print(
					"[Crystal Remover]",
					crystal.Name,
					"Value:",
					crystalValue
				)

				if crystalValue < currentMinValue then
					deletedCount += 1
					crystal:Destroy()
				end
			else
				noValueCount += 1
				warn(
					"[Crystal Remover] ไม่พบ Value ใน",
					crystal:GetFullName()
				)
			end
		end
	end

	statusLabel.Text = string.format(
		"ตรวจ %d | ลบ %d | ไม่พบค่า %d",
		checkedCount,
		deletedCount,
		noValueCount
	)

	return deletedCount
end

local function applyInputValue()
	local newValue = parseNumber(valueBox.Text)

	if not newValue then
		statusLabel.Text = "กรุณากรอกตัวเลข"
		statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
		valueBox.Text = tostring(currentMinValue)
		return false
	end

	currentMinValue = newValue
	valueBox.Text = tostring(currentMinValue)
	statusLabel.TextColor3 = Color3.fromRGB(190, 190, 190)

	return true
end

confirmButton.MouseButton1Click:Connect(function()
	if applyInputValue() then
		deleteLowValueCrystals()
	end
end)

-- กด Enter ในช่องก็ยืนยันและลบทันที
valueBox.FocusLost:Connect(function(enterPressed)
	if enterPressed and applyInputValue() then
		deleteLowValueCrystals()
	end
end)

toggleButton.MouseButton1Click:Connect(function()
	autoDeleteEnabled = not autoDeleteEnabled

	if autoDeleteEnabled then
		toggleButton.Text = "Auto: ON"
		toggleButton.BackgroundColor3 = Color3.fromRGB(45, 170, 90)
	else
		toggleButton.Text = "Auto: OFF"
		toggleButton.BackgroundColor3 = Color3.fromRGB(175, 65, 65)
	end
end)

closeButton.MouseButton1Click:Connect(function()
	running = false
	autoDeleteEnabled = false
	screenGui:Destroy()
end)

-- ตรวจทุก 0.5 วินาที
task.spawn(function()
	while running do
		task.wait(0.5)

		if autoDeleteEnabled
			and crystalsFolder
			and crystalsFolder.Parent then

			deleteLowValueCrystals()
		end
	end
end)
