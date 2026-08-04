-- ObjectFinder.client.lua
-- ใช้สำหรับทดสอบในเกม Roblox Studio ที่คุณเป็นเจ้าของเท่านั้น
-- วางไฟล์นี้เป็น LocalScript ที่:
-- StarterPlayer > StarterPlayerScripts > ObjectFinder.client.lua

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")

if not RunService:IsClient() then
	warn("ObjectFinder ต้องรันจาก LocalScript ฝั่ง Client")
	return
end

local player = Players.LocalPlayer

if not player then
	warn("ไม่พบ LocalPlayer กรุณาวางสคริปต์ใน StarterPlayerScripts")
	return
end

local CONFIG = {
	SearchInterval = 0.25,
	RuneKeyword = "rune",
	AboveDistance = 0,
	AutoEInterval = 0.01,
	AutoEHoldTime = 0.01,
	AutoClickInterval = 0.01,

}


local state = {
	runeEnabled = false,
	boulderEnabled = false,
	crystalEnabled = false,
	crystalPriceEnabled = false,

	minimumLuck = 20,
	minimumPrice = 10_000_000,

	currentMode = nil,
	currentTarget = nil,
	currentTargetLuck = nil,
	currentTargetPrice = nil,

	modeIndex = 0,
	lastSearch = 0,
	minimized = false,
	closed = false,
}

-- Character utilities

local function getCharacter()
	local character = player.Character

	if not character then
		return nil, nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	return character, humanoid, rootPart
end

-- Utility state: เปิดอัตโนมัติเมื่อ Finder อย่างน้อยหนึ่งโหมดเป็น ON
local utilityState = {
	active = false,
	originalCollisions = {},
	originalPrompts = {},
	originalPlatformStand = nil,
}

local function hasAnyFinderEnabled()
	return state.runeEnabled
		or state.boulderEnabled
		or state.crystalEnabled
		or state.crystalPriceEnabled
end

local function setPromptInstant(prompt)
	if not prompt:IsA("ProximityPrompt") then
		return
	end

	if utilityState.originalPrompts[prompt] == nil then
		utilityState.originalPrompts[prompt] = {
			HoldDuration = prompt.HoldDuration,
			RequiresLineOfSight = prompt.RequiresLineOfSight,
		}
	end

	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
end

local function restorePrompt(prompt, saved)
	if prompt and prompt.Parent and saved then
		prompt.HoldDuration = saved.HoldDuration
		prompt.RequiresLineOfSight = saved.RequiresLineOfSight
	end
end

local function enableUtilities()
	if utilityState.active then
		return
	end

	utilityState.active = true

	local character, humanoid = getCharacter()

	if humanoid then
		utilityState.originalPlatformStand = humanoid.PlatformStand
		humanoid.PlatformStand = true
	end

	if character then
		for _, object in ipairs(character:GetDescendants()) do
			if object:IsA("BasePart") then
				if utilityState.originalCollisions[object] == nil then
					utilityState.originalCollisions[object] = object.CanCollide
				end

				object.CanCollide = false
			end
		end
	end

	for _, object in ipairs(Workspace:GetDescendants()) do
		if object:IsA("ProximityPrompt") then
			setPromptInstant(object)
		end
	end
end

local function disableUtilities()
	if not utilityState.active then
		return
	end

	utilityState.active = false

	for part, originalCanCollide in pairs(utilityState.originalCollisions) do
		if part and part.Parent then
			part.CanCollide = originalCanCollide
		end
	end

	table.clear(utilityState.originalCollisions)

	for prompt, saved in pairs(utilityState.originalPrompts) do
		restorePrompt(prompt, saved)
	end

	table.clear(utilityState.originalPrompts)

	local _, humanoid, rootPart = getCharacter()

	if humanoid then
		humanoid.PlatformStand =
			utilityState.originalPlatformStand == true

		if not humanoid.PlatformStand then
			humanoid:ChangeState(
				Enum.HumanoidStateType.GettingUp
			)
		end
	end

	if rootPart then
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end

	utilityState.originalPlatformStand = nil
end

local function updateUtilities()
	if hasAnyFinderEnabled() then
		enableUtilities()
	else
		disableUtilities()
	end
end



local function isValidTarget(object)
	return object ~= nil
		and object.Parent ~= nil
		and object:IsDescendantOf(Workspace)
end

local function getObjectTopPosition(object)
	if not object then
		return nil
	end

	if object:IsA("BasePart") then
		return object.Position
			+ Vector3.new(0, object.Size.Y * 0.5, 0)
	end

	if object:IsA("Model") then
		local success, boundingCFrame, boundingSize = pcall(function()
			local cf, size = object:GetBoundingBox()
			return cf, size
		end)

		if success and boundingCFrame and boundingSize then
			return boundingCFrame.Position
				+ Vector3.new(0, boundingSize.Y * 0.5, 0)
		end
	end

	local parts = {}

	for _, descendant in ipairs(object:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	if #parts == 0 then
		return nil
	end

	local minX = math.huge
	local minY = math.huge
	local minZ = math.huge
	local maxX = -math.huge
	local maxY = -math.huge
	local maxZ = -math.huge

	for _, part in ipairs(parts) do
		local half = part.Size * 0.5
		local minPos = part.Position - half
		local maxPos = part.Position + half

		minX = math.min(minX, minPos.X)
		minY = math.min(minY, minPos.Y)
		minZ = math.min(minZ, minPos.Z)

		maxX = math.max(maxX, maxPos.X)
		maxY = math.max(maxY, maxPos.Y)
		maxZ = math.max(maxZ, maxPos.Z)
	end

	return Vector3.new(
		(minX + maxX) * 0.5,
		maxY,
		(minZ + maxZ) * 0.5
	)
end

local function clearTarget()
	state.currentMode = nil
	state.currentTarget = nil
	state.currentTargetLuck = nil
	state.currentTargetPrice = nil
end

-- Rune finder

local function findNearestRune(origin)
	local nearestTarget = nil
	local nearestDistance = math.huge

	for _, object in ipairs(Workspace:GetDescendants()) do
		if object:IsA("BasePart") or object:IsA("Model") then
			local lowerName = string.lower(object.Name)

			if string.find(
				lowerName,
				CONFIG.RuneKeyword,
				1,
				true
			) then
				local position = getObjectTopPosition(object)

				if position then
					local distance = (position - origin).Magnitude

					if distance < nearestDistance then
						nearestDistance = distance
						nearestTarget = object
					end
				end
			end
		end
	end

	return nearestTarget
end

-- Boulder finder

local function getBouldersFolder()
	local mountainDecorations =
		Workspace:FindFirstChild("MountainDecorations")

	if not mountainDecorations then
		return nil
	end

	return mountainDecorations:FindFirstChild("Boulders")
end

local function findNearestBoulder(origin)
	local bouldersFolder = getBouldersFolder()

	if not bouldersFolder then
		return nil
	end

	local nearestTarget = nil
	local nearestDistance = math.huge

	for _, object in ipairs(bouldersFolder:GetChildren()) do
		local position = getObjectTopPosition(object)

		if position then
			local distance = (position - origin).Magnitude

			if distance < nearestDistance then
				nearestDistance = distance
				nearestTarget = object
			end
		end
	end

	return nearestTarget
end

-- Crystal utilities

local function getCrystalsFolder()
	local things = Workspace:FindFirstChild("Things")

	if not things then
		return nil
	end

	return things:FindFirstChild("Crystals")
end

-- Crystal luck finder

local function parseLuck(value)
	if value == nil then
		return nil
	end

	if typeof(value) == "number" then
		return tonumber(value)
	end

	local text = tostring(value)

	-- ลบ RichText เช่น <font>Luck: +82%</font>
	text = text:gsub("<[^>]->", "")
	text = text:gsub("\194\160", " ")
	text = text:gsub("%s+", " ")

	-- รูปแบบหลัก: Luck: +82%
	local numberText = text:match(
		"[Ll][Uu][Cc][Kk]%s*:%s*%+?%s*(%-?%d+%.?%d*)%s*%%"
	)

	-- Fallback: +82%
	if not numberText then
		numberText = text:match(
			"%+%s*(%d+%.?%d*)%s*%%"
		)
	end

	-- Fallback: 82%
	if not numberText then
		numberText = text:match(
			"(%-?%d+%.?%d*)%s*%%"
		)
	end

	return numberText and tonumber(numberText) or nil
end

local function readLuckObject(object)
	if not object then
		return nil
	end

	if object:IsA("TextLabel")
		or object:IsA("TextButton")
		or object:IsA("TextBox") then

		return parseLuck(object.Text)
	end

	if object:IsA("StringValue")
		or object:IsA("NumberValue")
		or object:IsA("IntValue") then

		return parseLuck(object.Value)
	end

	return nil
end

local function getCrystalLuck(crystal)
	if not crystal then
		return nil
	end

	-- โครงสร้างหลัก:
	-- Workspace > Things > Crystals > CrystalObject
	-- > CrystalHover > LuckBoosy
	local crystalHover =
		crystal:FindFirstChild("CrystalHover", true)

	if crystalHover then
		local exactNames = {
			"LuckBoosy",
			"LuckBoost",
			"LuckBoostText",
		}

		for _, objectName in ipairs(exactNames) do
			local luckObject =
				crystalHover:FindFirstChild(objectName, true)

			local luck = readLuckObject(luckObject)

			if luck ~= nil then
				return luck
			end
		end

		-- ชื่อ Object อาจต่างกัน แต่ Text ยังเป็น Luck: +82%
		for _, object in ipairs(crystalHover:GetDescendants()) do
			local luck = readLuckObject(object)

			if luck ~= nil then
				return luck
			end
		end
	end

	-- Fallback: ค้นทั้ง Crystal
	for _, object in ipairs(crystal:GetDescendants()) do
		local lowerName = string.lower(object.Name)

		if lowerName == "luckboosy"
			or lowerName == "luckboost"
			or lowerName == "luckboosttext"
			or lowerName:find("luck", 1, true) then

			local luck = readLuckObject(object)

			if luck ~= nil then
				return luck
			end
		end
	end

	return nil
end

local function findCrystalByLuck(origin, minimumLuck)
	local crystalsFolder = getCrystalsFolder()

	if not crystalsFolder then
		return nil, nil
	end

	local bestCrystal = nil
	local bestLuck = -math.huge
	local bestDistance = math.huge

	for _, crystal in ipairs(crystalsFolder:GetChildren()) do
		local luck = getCrystalLuck(crystal)
		local position = getObjectTopPosition(crystal)

		if luck
			and position
			and luck >= minimumLuck then

			local distance = (position - origin).Magnitude

			if luck > bestLuck
				or (
					luck == bestLuck
					and distance < bestDistance
				) then

				bestCrystal = crystal
				bestLuck = luck
				bestDistance = distance
			end
		end
	end

	return bestCrystal, bestLuck
end

-- Crystal price finder

local function parsePrice(value)
	if type(value) == "number" then
		return value
	end

	if type(value) ~= "string" then
		return nil
	end

	local cleaned = value
		:gsub(",", "")
		:gsub("%s+", "")
		:gsub("%$", "")
		:lower()

	local numberText =
		cleaned:match("%-?%d+%.?%d*")

	if not numberText then
		return nil
	end

	local number = tonumber(numberText)

	if not number then
		return nil
	end

	if cleaned:find("b", 1, true) then
		number *= 1_000_000_000
	elseif cleaned:find("m", 1, true) then
		number *= 1_000_000
	elseif cleaned:find("k", 1, true) then
		number *= 1_000
	end

	return number
end

local function readValueFromObject(object)
	if not object then
		return nil
	end

	if object:IsA("IntValue")
		or object:IsA("NumberValue") then

		return tonumber(object.Value)
	end

	if object:IsA("StringValue") then
		return parsePrice(object.Value)
	end

	if object:IsA("TextLabel")
		or object:IsA("TextButton")
		or object:IsA("TextBox") then

		return parsePrice(object.Text)
	end

	return nil
end

local function getCrystalPrice(crystal)
	if not crystal then
		return nil
	end

	-- กรณี Crystal เองเป็น ValueBase
	local directValue = readValueFromObject(crystal)

	if directValue then
		return directValue
	end

	-- Attribute บน Crystal
	local attributeNames = {
		"Price",
		"Value",
		"CrystalPrice",
		"CrystalValue",
		"SellPrice",
	}

	for _, attributeName in ipairs(attributeNames) do
		local parsed =
			parsePrice(crystal:GetAttribute(attributeName))

		if parsed then
			return parsed
		end
	end

	-- Object ลูกภายใน Crystal
	local candidateNames = {
		"Price",
		"Value",
		"CrystalPrice",
		"CrystalValue",
		"SellPrice",
	}

	for _, candidateName in ipairs(candidateNames) do
		local priceObject =
			crystal:FindFirstChild(candidateName, true)

		local parsed = readValueFromObject(priceObject)

		if parsed then
			return parsed
		end
	end

	-- ค้น ValueBase หรือข้อความที่มีชื่อเกี่ยวกับราคา
	for _, descendant in ipairs(crystal:GetDescendants()) do
		local lowerName = string.lower(descendant.Name)

		if lowerName == "price"
			or lowerName == "value"
			or lowerName == "crystalprice"
			or lowerName == "crystalvalue"
			or lowerName == "sellprice" then

			local parsed = readValueFromObject(descendant)

			if parsed then
				return parsed
			end
		end
	end

	-- กรณีชื่อ Crystal เป็นราคา
	return parsePrice(crystal.Name)
end

local function findCrystalByPrice(origin, minimumPrice)
	local crystalsFolder = getCrystalsFolder()

	if not crystalsFolder then
		return nil, nil
	end

	local bestCrystal = nil
	local bestPrice = math.huge
	local bestDistance = math.huge

	for _, crystal in ipairs(crystalsFolder:GetChildren()) do
		local price = getCrystalPrice(crystal)
		local position = getObjectTopPosition(crystal)

		if price
			and position
			and price >= minimumPrice then

			local distance = (position - origin).Magnitude

			-- เลือกราคาที่ต่ำที่สุดแต่ยังผ่านขั้นต่ำ
			-- หากราคาเท่ากัน เลือกชิ้นที่ใกล้ที่สุด
			if price < bestPrice
				or (
					price == bestPrice
					and distance < bestDistance
				) then

				bestCrystal = crystal
				bestPrice = price
				bestDistance = distance
			end
		end
	end

	return bestCrystal, bestPrice
end

-- Mode controls

local function disableAllModes()
	state.runeEnabled = false
	state.boulderEnabled = false
	state.crystalEnabled = false
	state.crystalPriceEnabled = false
	state.modeIndex = 0

	clearTarget()
end

local function setRuneEnabled(enabled)
	state.runeEnabled = enabled

	if not enabled and state.currentMode == "Rune" then
		clearTarget()
	end
end

local function setBoulderEnabled(enabled)
	state.boulderEnabled = enabled

	if not enabled and state.currentMode == "Boulder" then
		clearTarget()
	end
end

local function setCrystalEnabled(enabled)
	state.crystalEnabled = enabled

	if not enabled and state.currentMode == "Crystal" then
		clearTarget()
	end
end

local function setCrystalPriceEnabled(enabled)
	state.crystalPriceEnabled = enabled

	if not enabled and state.currentMode == "CrystalPrice" then
		clearTarget()
	end
end

local function isModeEnabled(mode)
	if mode == "Rune" then
		return state.runeEnabled
	end

	if mode == "Boulder" then
		return state.boulderEnabled
	end

	if mode == "Crystal" then
		return state.crystalEnabled
	end

	if mode == "CrystalPrice" then
		return state.crystalPriceEnabled
	end

	return false
end

local MODE_ORDER = {
	"Rune",
	"Boulder",
	"Crystal",
	"CrystalPrice",
}

local function getNextEnabledMode()
	for _ = 1, #MODE_ORDER do
		state.modeIndex =
			state.modeIndex % #MODE_ORDER + 1

		local mode = MODE_ORDER[state.modeIndex]

		if isModeEnabled(mode) then
			return mode
		end
	end

	return nil
end


-- Auto E
-- เปิดอัตโนมัติเมื่อ Finder อย่างน้อยหนึ่งโหมดเป็น ON

local autoEState = {
	running = false,
	thread = nil,
	visiblePrompts = {},
}

local function isValidEPrompt(prompt)
	return prompt ~= nil
		and prompt.Parent ~= nil
		and prompt.Enabled
		and prompt.KeyboardKeyCode == Enum.KeyCode.E
end

local function getActiveEPrompt()
	local nearestPrompt = nil
	local nearestDistance = math.huge
	local _, _, rootPart = getCharacter()

	for prompt in pairs(autoEState.visiblePrompts) do
		if not isValidEPrompt(prompt) then
			autoEState.visiblePrompts[prompt] = nil
		else
			local promptParent = prompt.Parent
			local promptPosition = nil

			if promptParent:IsA("Attachment") then
				promptPosition = promptParent.WorldPosition
			elseif promptParent:IsA("BasePart") then
				promptPosition = promptParent.Position
			end

			if rootPart and promptPosition then
				local distance =
					(promptPosition - rootPart.Position).Magnitude

				if distance < nearestDistance then
					nearestDistance = distance
					nearestPrompt = prompt
				end
			elseif not nearestPrompt then
				nearestPrompt = prompt
			end
		end
	end

	return nearestPrompt
end

local function activateEPrompt(prompt)
	if not isValidEPrompt(prompt) then
		return
	end

	local success, errorMessage = pcall(function()
		prompt:InputHoldBegin()

		local holdTime = math.max(
			prompt.HoldDuration,
			CONFIG.AutoEHoldTime
		)

		task.wait(holdTime)

		if autoEState.running
			and prompt
			and prompt.Parent then

			prompt:InputHoldEnd()
		end
	end)

	if not success then
		warn("Auto E error:", errorMessage)
	end
end

local function stopAutoE()
	autoEState.running = false

	if autoEState.thread then
		task.cancel(autoEState.thread)
		autoEState.thread = nil
	end
end

local function startAutoE()
	if autoEState.running then
		return
	end

	autoEState.running = true

	autoEState.thread = task.spawn(function()
		while autoEState.running do
			local prompt = getActiveEPrompt()

			if prompt then
				activateEPrompt(prompt)
			end

			task.wait(CONFIG.AutoEInterval)
		end

		autoEState.thread = nil
	end)
end

local function updateAutoE()
	if hasAnyFinderEnabled() then
		startAutoE()
	else
		stopAutoE()
	end
end

ProximityPromptService.PromptShown:Connect(function(
	prompt,
	_inputType
)
	if prompt.KeyboardKeyCode == Enum.KeyCode.E then
		autoEState.visiblePrompts[prompt] = true
	end
end)

ProximityPromptService.PromptHidden:Connect(function(prompt)
	autoEState.visiblePrompts[prompt] = nil
end)


-- Auto Click
-- ทำงานเฉพาะตอน Boulder Finder เปิดอยู่ และตัวละครกำลังถือ Tool

local autoClickState = {
	running = false,
	thread = nil,
}

local function getEquippedTool()
	local character = player.Character

	if not character then
		return nil
	end

	for _, object in ipairs(character:GetChildren()) do
		if object:IsA("Tool") then
			return object
		end
	end

	return nil
end

local function stopAutoClick()
	autoClickState.running = false

	if autoClickState.thread then
		task.cancel(autoClickState.thread)
		autoClickState.thread = nil
	end
end

local function startAutoClick()
	if autoClickState.running then
		return
	end

	autoClickState.running = true

	autoClickState.thread = task.spawn(function()
		while autoClickState.running do
			if not state.boulderEnabled then
				break
			end

			local tool = getEquippedTool()

			if tool and tool.Enabled then
				local success, errorMessage = pcall(function()
					tool:Activate()
				end)

				if not success then
					warn("Auto Click error:", errorMessage)
				end
			end

			task.wait(CONFIG.AutoClickInterval)
		end

		autoClickState.running = false
		autoClickState.thread = nil
	end)
end

local function updateAutoClick()
	if state.boulderEnabled then
		startAutoClick()
	else
		stopAutoClick()
	end
end

-- GUI

local playerGui = player:WaitForChild("PlayerGui")

local oldGui =
	playerGui:FindFirstChild("ObjectFinderGui")

if oldGui then
	oldGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ObjectFinderGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.ZIndexBehavior =
	Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.fromOffset(330, 420)
mainFrame.Position =
	UDim2.new(0, 30, 0.5, -210)
mainFrame.BackgroundColor3 =
	Color3.fromRGB(30, 30, 35)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 10)
mainCorner.Parent = mainFrame

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(75, 75, 88)
mainStroke.Thickness = 1
mainStroke.Parent = mainFrame

local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 42)
titleBar.BackgroundColor3 =
	Color3.fromRGB(42, 42, 49)
titleBar.BorderSizePixel = 0
titleBar.Parent = mainFrame

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 10)
titleCorner.Parent = titleBar

local titleFix = Instance.new("Frame")
titleFix.Size = UDim2.new(1, 0, 0, 10)
titleFix.Position = UDim2.new(0, 0, 1, -10)
titleFix.BackgroundColor3 =
	titleBar.BackgroundColor3
titleFix.BorderSizePixel = 0
titleFix.Parent = titleBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -90, 1, 0)
titleLabel.Position = UDim2.fromOffset(14, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Workspace Object Finder"
titleLabel.TextColor3 =
	Color3.fromRGB(245, 245, 245)
titleLabel.TextSize = 16
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment =
	Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

local minimizeButton = Instance.new("TextButton")
minimizeButton.Size = UDim2.fromOffset(34, 28)
minimizeButton.Position =
	UDim2.new(1, -74, 0, 7)
minimizeButton.BackgroundColor3 =
	Color3.fromRGB(65, 65, 73)
minimizeButton.Text = "—"
minimizeButton.TextColor3 =
	Color3.fromRGB(255, 255, 255)
minimizeButton.TextSize = 18
minimizeButton.Font = Enum.Font.GothamBold
minimizeButton.Parent = titleBar

local minimizeCorner = Instance.new("UICorner")
minimizeCorner.CornerRadius = UDim.new(0, 6)
minimizeCorner.Parent = minimizeButton

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.fromOffset(34, 28)
closeButton.Position =
	UDim2.new(1, -38, 0, 7)
closeButton.BackgroundColor3 =
	Color3.fromRGB(170, 55, 55)
closeButton.Text = "×"
closeButton.TextColor3 =
	Color3.fromRGB(255, 255, 255)
closeButton.TextSize = 20
closeButton.Font = Enum.Font.GothamBold
closeButton.Parent = titleBar

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 6)
closeCorner.Parent = closeButton

local contentFrame = Instance.new("Frame")
contentFrame.Name = "Content"
contentFrame.Size =
	UDim2.new(1, -20, 1, -55)
contentFrame.Position =
	UDim2.fromOffset(10, 50)
contentFrame.BackgroundTransparency = 1
contentFrame.Parent = mainFrame

local function createToggleButton(text, yPosition)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 0, 42)
	button.Position =
		UDim2.fromOffset(0, yPosition)
	button.BackgroundColor3 =
		Color3.fromRGB(65, 65, 73)
	button.TextColor3 =
		Color3.fromRGB(255, 255, 255)
	button.TextSize = 14
	button.Font = Enum.Font.GothamSemibold
	button.Text = text
	button.Parent = contentFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	return button
end

local runeButton =
	createToggleButton("Rune Finder: OFF", 0)

local boulderButton =
	createToggleButton("Boulders Finder: OFF", 49)

local crystalButton =
	createToggleButton("Crystal Luck Finder: OFF", 98)

local crystalPriceButton =
	createToggleButton("Crystal Price Finder: OFF", 147)

local luckLabel = Instance.new("TextLabel")
luckLabel.Size = UDim2.fromOffset(120, 38)
luckLabel.Position = UDim2.fromOffset(0, 198)
luckLabel.BackgroundTransparency = 1
luckLabel.Text = "Minimum Luck (%)"
luckLabel.TextColor3 =
	Color3.fromRGB(225, 225, 230)
luckLabel.TextSize = 13
luckLabel.Font = Enum.Font.Gotham
luckLabel.TextXAlignment =
	Enum.TextXAlignment.Left
luckLabel.Parent = contentFrame

local luckInput = Instance.new("TextBox")
luckInput.Size = UDim2.new(1, -130, 0, 38)
luckInput.Position =
	UDim2.fromOffset(130, 198)
luckInput.BackgroundColor3 =
	Color3.fromRGB(48, 48, 56)
luckInput.TextColor3 =
	Color3.fromRGB(255, 255, 255)
luckInput.PlaceholderColor3 =
	Color3.fromRGB(150, 150, 160)
luckInput.PlaceholderText = "เช่น 20"
luckInput.Text = tostring(state.minimumLuck)
luckInput.ClearTextOnFocus = false
luckInput.TextSize = 14
luckInput.Font = Enum.Font.Gotham
luckInput.Parent = contentFrame

local luckCorner = Instance.new("UICorner")
luckCorner.CornerRadius = UDim.new(0, 8)
luckCorner.Parent = luckInput

local priceLabel = Instance.new("TextLabel")
priceLabel.Size = UDim2.fromOffset(120, 38)
priceLabel.Position = UDim2.fromOffset(0, 243)
priceLabel.BackgroundTransparency = 1
priceLabel.Text = "Minimum Price"
priceLabel.TextColor3 =
	Color3.fromRGB(225, 225, 230)
priceLabel.TextSize = 13
priceLabel.Font = Enum.Font.Gotham
priceLabel.TextXAlignment =
	Enum.TextXAlignment.Left
priceLabel.Parent = contentFrame

local priceInput = Instance.new("TextBox")
priceInput.Size = UDim2.new(1, -130, 0, 38)
priceInput.Position =
	UDim2.fromOffset(130, 243)
priceInput.BackgroundColor3 =
	Color3.fromRGB(48, 48, 56)
priceInput.TextColor3 =
	Color3.fromRGB(255, 255, 255)
priceInput.PlaceholderColor3 =
	Color3.fromRGB(150, 150, 160)
priceInput.PlaceholderText = "ขั้นต่ำ 10000000"
priceInput.Text = tostring(state.minimumPrice)
priceInput.ClearTextOnFocus = false
priceInput.TextSize = 14
priceInput.Font = Enum.Font.Gotham
priceInput.Parent = contentFrame

local priceCorner = Instance.new("UICorner")
priceCorner.CornerRadius = UDim.new(0, 8)
priceCorner.Parent = priceInput

local statusLabel = Instance.new("TextLabel")
statusLabel.Position =
	UDim2.fromOffset(0, 289)
statusLabel.Size =
	UDim2.new(1, 0, 0, 68)
statusLabel.BackgroundColor3 =
	Color3.fromRGB(38, 38, 44)
statusLabel.TextColor3 =
	Color3.fromRGB(210, 210, 215)
statusLabel.TextSize = 12
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextWrapped = true
statusLabel.Text = "Status: Ready"
statusLabel.Parent = contentFrame

local statusCorner = Instance.new("UICorner")
statusCorner.CornerRadius = UDim.new(0, 8)
statusCorner.Parent = statusLabel

-- Minimized logo

local logoButton = Instance.new("TextButton")
logoButton.Name = "LogoButton"
logoButton.Size = UDim2.fromOffset(58, 58)
logoButton.Position = mainFrame.Position
logoButton.BackgroundColor3 =
	Color3.fromRGB(42, 42, 49)
logoButton.BorderSizePixel = 0
logoButton.Text = "OF"
logoButton.TextColor3 =
	Color3.fromRGB(255, 255, 255)
logoButton.TextSize = 18
logoButton.Font = Enum.Font.GothamBold
logoButton.Visible = false
logoButton.Active = true
logoButton.Draggable = true
logoButton.Parent = screenGui

local logoCorner = Instance.new("UICorner")
logoCorner.CornerRadius = UDim.new(1, 0)
logoCorner.Parent = logoButton

local logoStroke = Instance.new("UIStroke")
logoStroke.Thickness = 2
logoStroke.Color =
	Color3.fromRGB(100, 100, 115)
logoStroke.Parent = logoButton

-- GUI update functions

local function updateButtons()
	if state.runeEnabled then
		runeButton.Text = "Rune Finder: ON"
		runeButton.BackgroundColor3 =
			Color3.fromRGB(45, 135, 80)
	else
		runeButton.Text = "Rune Finder: OFF"
		runeButton.BackgroundColor3 =
			Color3.fromRGB(65, 65, 73)
	end

	if state.boulderEnabled then
		boulderButton.Text =
			"Boulders Finder: ON"
		boulderButton.BackgroundColor3 =
			Color3.fromRGB(45, 135, 80)
	else
		boulderButton.Text =
			"Boulders Finder: OFF"
		boulderButton.BackgroundColor3 =
			Color3.fromRGB(65, 65, 73)
	end

	if state.crystalEnabled then
		crystalButton.Text =
			"Crystal Luck: ON (≥ "
			.. tostring(state.minimumLuck)
			.. "%)"

		crystalButton.BackgroundColor3 =
			Color3.fromRGB(45, 135, 80)
	else
		crystalButton.Text =
			"Crystal Luck Finder: OFF"
		crystalButton.BackgroundColor3 =
			Color3.fromRGB(65, 65, 73)
	end

	if state.crystalPriceEnabled then
		crystalPriceButton.Text =
			"Crystal Price: ON (≥ "
			.. tostring(state.minimumPrice)
			.. ")"

		crystalPriceButton.BackgroundColor3 =
			Color3.fromRGB(45, 135, 80)
	else
		crystalPriceButton.Text =
			"Crystal Price Finder: OFF"
		crystalPriceButton.BackgroundColor3 =
			Color3.fromRGB(65, 65, 73)
	end
end

local function applyLuckInput()
	local number = tonumber(luckInput.Text)

	if not number then
		luckInput.Text =
			tostring(state.minimumLuck)

		statusLabel.Text =
			"Status: ค่า Luck ต้องเป็นตัวเลข"

		return
	end

	state.minimumLuck = math.max(0, number)
	luckInput.Text = tostring(state.minimumLuck)

	clearTarget()
	updateButtons()

	statusLabel.Text =
		"Status: Minimum Luck = "
		.. tostring(state.minimumLuck)
		.. "%"
end

local function applyPriceInput()
	local parsed = parsePrice(priceInput.Text)

	if not parsed then
		priceInput.Text =
			tostring(state.minimumPrice)

		statusLabel.Text =
			"Status: ราคาต้องเป็นตัวเลข"

		return
	end

	state.minimumPrice =
		math.max(10_000_000, math.floor(parsed))

	priceInput.Text =
		tostring(state.minimumPrice)

	clearTarget()
	updateButtons()

	statusLabel.Text =
		"Status: Minimum Price = "
		.. tostring(state.minimumPrice)
end

runeButton.MouseButton1Click:Connect(function()
	setRuneEnabled(not state.runeEnabled)
	updateButtons()
	updateUtilities()
	updateAutoE()
end)

boulderButton.MouseButton1Click:Connect(function()
	setBoulderEnabled(not state.boulderEnabled)
	updateButtons()
	updateUtilities()
	updateAutoE()
	updateAutoClick()
end)

crystalButton.MouseButton1Click:Connect(function()
	setCrystalEnabled(not state.crystalEnabled)
	updateButtons()
	updateUtilities()
	updateAutoE()
end)

crystalPriceButton.MouseButton1Click:Connect(function()
	setCrystalPriceEnabled(
		not state.crystalPriceEnabled
	)
	updateButtons()
	updateUtilities()
	updateAutoE()
end)

luckInput.FocusLost:Connect(function()
	applyLuckInput()
end)

priceInput.FocusLost:Connect(function()
	applyPriceInput()
end)

local function minimizeToLogo()
	if state.closed then
		return
	end

	state.minimized = true
	logoButton.Position = mainFrame.Position
	mainFrame.Visible = false
	logoButton.Visible = true
end

local function restoreFromLogo()
	if state.closed then
		return
	end

	state.minimized = false
	mainFrame.Position = logoButton.Position
	logoButton.Visible = false
	mainFrame.Visible = true
end

minimizeButton.MouseButton1Click:Connect(
	minimizeToLogo
)

logoButton.MouseButton1Click:Connect(
	restoreFromLogo
)

closeButton.MouseButton1Click:Connect(function()
	state.closed = true
	disableAllModes()
	disableUtilities()
	stopAutoE()
	stopAutoClick()
	table.clear(autoEState.visiblePrompts)
	screenGui:Destroy()
end)

updateButtons()


-- บังคับ Noclip/Fly และ Instant Prompt ระหว่างที่ Finder เปิดอยู่

Workspace.DescendantAdded:Connect(function(object)
	if utilityState.active
		and object:IsA("ProximityPrompt") then

		setPromptInstant(object)
	end
end)

player.CharacterAdded:Connect(function()
	task.wait(0.5)

	if hasAnyFinderEnabled() then
		utilityState.active = false
		table.clear(utilityState.originalCollisions)
		utilityState.originalPlatformStand = nil
		enableUtilities()
	end

	if state.boulderEnabled then
		stopAutoClick()
		startAutoClick()
	end
end)

RunService.Stepped:Connect(function()
	if not utilityState.active then
		return
	end

	local character, humanoid, rootPart =
		getCharacter()

	if not character then
		return
	end

	-- Noclip
	for _, object in ipairs(character:GetDescendants()) do
		if object:IsA("BasePart") then
			if utilityState.originalCollisions[object] == nil then
				utilityState.originalCollisions[object] =
					object.CanCollide
			end

			object.CanCollide = false
		end
	end

	-- Fly/Hover สำหรับระบบวาร์ป
	if humanoid then
		humanoid.PlatformStand = true
	end

	if rootPart then
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end
end)

-- Main finder loop

local function findTargetForMode(mode, origin)
	if mode == "Rune" then
		return findNearestRune(origin), nil
	end

	if mode == "Boulder" then
		return findNearestBoulder(origin), nil
	end

	if mode == "Crystal" then
		return findCrystalByLuck(
			origin,
			state.minimumLuck
		)
	end

	if mode == "CrystalPrice" then
		return findCrystalByPrice(
			origin,
			state.minimumPrice
		)
	end

	return nil, nil
end

local function countEnabledModes()
	local count = 0

	if state.runeEnabled then
		count += 1
	end

	if state.boulderEnabled then
		count += 1
	end

	if state.crystalEnabled then
		count += 1
	end

	if state.crystalPriceEnabled then
		count += 1
	end

	return count
end

RunService.Heartbeat:Connect(function()
	if state.closed then
		return
	end

	local _, humanoid, rootPart =
		getCharacter()

	if not humanoid
		or humanoid.Health <= 0
		or not rootPart then
		return
	end

	if countEnabledModes() == 0 then
		statusLabel.Text = "Status: Ready"
		clearTarget()
		return
	end

	if state.currentMode
		and not isModeEnabled(state.currentMode) then

		clearTarget()
	end

	if state.currentTarget
		and not isValidTarget(state.currentTarget) then

		clearTarget()
	end

	if not state.currentTarget then
		local now = os.clock()

		if now - state.lastSearch
			< CONFIG.SearchInterval then

			return
		end

		state.lastSearch = now

		local checkedModes = 0
		local maximumChecks = #MODE_ORDER

		while checkedModes < maximumChecks do
			checkedModes += 1

			local nextMode =
				getNextEnabledMode()

			if not nextMode then
				statusLabel.Text =
					"Status: ไม่มีโหมดที่เปิดอยู่"

				return
			end

			local target, extraValue =
				findTargetForMode(
					nextMode,
					rootPart.Position
				)

			if target then
				state.currentMode = nextMode
				state.currentTarget = target
				state.currentTargetLuck = nil
				state.currentTargetPrice = nil

				if nextMode == "Crystal" then
					state.currentTargetLuck =
						extraValue

				elseif nextMode == "CrystalPrice" then
					state.currentTargetPrice =
						extraValue
				end

				break
			end
		end
	end

	if not state.currentTarget then
		local enabledNames = {}

		if state.runeEnabled then
			table.insert(enabledNames, "Rune")
		end

		if state.boulderEnabled then
			table.insert(enabledNames, "Boulder")
		end

		if state.crystalEnabled then
			table.insert(
				enabledNames,
				"Crystal Luck ≥ "
					.. tostring(state.minimumLuck)
					.. "%"
			)
		end

		if state.crystalPriceEnabled then
			table.insert(
				enabledNames,
				"Crystal Price ≥ "
					.. tostring(state.minimumPrice)
			)
		end

		statusLabel.Text =
			"Status: ไม่พบเป้าหมาย\n"
			.. table.concat(enabledNames, ", ")

		return
	end

	local targetPosition =
		getObjectTopPosition(
			state.currentTarget
		)

	if not targetPosition then
		clearTarget()
		return
	end

	if state.currentMode == "CrystalPrice" then
		statusLabel.Text =
			"Mode: Crystal Price"
			.. "\nTarget: "
			.. state.currentTarget.Name
			.. " | Price: "
			.. tostring(
				state.currentTargetPrice or "?"
			)

	elseif state.currentMode == "Crystal" then
		statusLabel.Text =
			"Mode: Crystal Luck"
			.. "\nTarget: "
			.. state.currentTarget.Name
			.. " | Luck: +"
			.. tostring(
				state.currentTargetLuck or "?"
			)
			.. "%"

	else
		statusLabel.Text =
			"Mode: "
			.. tostring(state.currentMode)
			.. "\nTarget: "
			.. state.currentTarget.Name
	end

	-- ค้างเหนือ Object จน Object ถูกลบ
	rootPart.CFrame = CFrame.new(
		targetPosition
			+ Vector3.new(
				0,
				CONFIG.AboveDistance,
				0
			)
	)

	rootPart.AssemblyLinearVelocity =
		Vector3.zero

	rootPart.AssemblyAngularVelocity =
		Vector3.zero
end)
