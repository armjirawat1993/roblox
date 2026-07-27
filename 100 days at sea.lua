local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--==================================================
-- ตั้งค่า
--==================================================

local LOGO_ASSET_ID = "rbxassetid://1234567890"

local HEAD_ITEM_NAMES = {
    -- Wood
	"Pallet",
	"Plank",
	"Stool",
	"Chair1",
	"BrokenCrate",
	"BrokenCrate2",
    -- Oil
	"OilTank",
	"GasCan1",
	"JerryCan1",
    -- Metal
	"CarBattery",
	"Propellor",
	"ScrapMetal",
	"Engine",
    -- Food
	"Stew1",
	"Potato1",
	"Sushi1",
    -- Goo
	"GhostGoo",
    -- Aline
	"AlienWood",
	"AlienMetal",
	"Fruit",
    -- Box Coin
	"Metal",
    -- Coin
	"Union",
}

local FOOD_NAMES = {
	Stew1 = true,
	Potato1 = true,
	Sushi1 = true,
	Orange1 = true,
	LobsterTail1 = true,
	FishandChips = true,
	Calamari = true,
	Jam1 = true,
	Unagi = true,
	ButteredBass = true,
}

local COOKING_POT_ITEM_NAMES = FOOD_NAMES

local HeadBringConfig = {
	SelectedNames = {},
	-- ตำแหน่งเหนือหัว
	HeadOffset = Vector3.new(3, 4, 0),
}

local AutoPizzaConfig = {
	Enabled = false,
	AmountPerCycle = 3,
	Interval = 5,
	SearchRadius = 50,
	YOffset = 3,
	Thread = nil,
}

local AutoCookingPotConfig = {
	Enabled = false,
	AmountPerCycle = 3,
	Interval = 5,
	SearchRadius = 50,
	YOffset = 3,
	Thread = nil,
}

local GraphicsConfig = {
	Enabled = false,
	Saved = false,
	OriginalProperties = {},
	OriginalEffects = {},
}

local optionButtons = {}

--==================================================
-- ป้องกัน GUI ซ้ำ
--==================================================

local oldGui = playerGui:FindFirstChild("ItemUtilityMenuGui")

if oldGui then
	oldGui:Destroy()
end

--==================================================
-- ฟังก์ชันช่วยเหลือ
--==================================================

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = parent

	return corner
end

local function addStroke(parent)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(65, 70, 85)
	stroke.Thickness = 1
	stroke.Parent = parent

	return stroke
end

local function getCharacter()
	return player.Character or player.CharacterAdded:Wait()
end

local function getHead()
	local character = getCharacter()

	return character:FindFirstChild("Head")
end

local function getDebrisField()
	local debrisField = Workspace:FindFirstChild("DebrisField")

	if not debrisField then
		warn("ไม่พบ Workspace.DebrisField")
		return nil
	end

	return debrisField
end

local function getObjectPosition(object)
	if object:IsA("BasePart") then
		return object.Position
	end

	if object:IsA("Model") then
		return object:GetPivot().Position
	end

	return nil
end

local function stopPartPhysics(part)
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
end

local function prepareObject(object)
	if object:IsA("BasePart") then
		stopPartPhysics(object)
		return
	end

	if object:IsA("Model") then
		for _, descendant in ipairs(object:GetDescendants()) do
			if descendant:IsA("BasePart") then
				stopPartPhysics(descendant)
			end
		end
	end
end

-- ใช้สำหรับ Tab ดึง Item มาตรงหัว
local function moveObject(object, targetCFrame)
	if not object or not object.Parent then
		return false
	end

	prepareObject(object)

	if object:IsA("Model") then
		object:PivotTo(targetCFrame)
		return true
	end

	if object:IsA("BasePart") then
		object.CFrame = targetCFrame
		return true
	end

	return false
end

local function findObjectsByName(objectName)
	local debrisField = getDebrisField()

	if not debrisField then
		return {}
	end

	local results = {}

	for _, object in ipairs(debrisField:GetDescendants()) do
		if object.Name == objectName
			and (
				object:IsA("Model")
				or object:IsA("BasePart")
			) then

			table.insert(results, object)
		end
	end

	return results
end

--==================================================
-- ระบบดึง Item มาตรงหัว
--==================================================

local function getSelectedNames()
	local results = {}

	for _, itemName in ipairs(HEAD_ITEM_NAMES) do
		if HeadBringConfig.SelectedNames[itemName] then
			table.insert(results, itemName)
		end
	end

	return results
end

local function countSelectedObjects()
	local total = 0

	for _, itemName in ipairs(getSelectedNames()) do
		total += #findObjectsByName(itemName)
	end

	return total
end

local function bringSelectedItems(moveAll)
	local selectedNames = getSelectedNames()

	if #selectedNames == 0 then
		return 0, 0
	end

	local head = getHead()

	if not head then
		warn("ไม่พบ Head ของตัวละคร")
		return 0, 0
	end

	-- ทุกชิ้นซ้อนตำแหน่งเดียวกัน
	local targetCFrame = CFrame.new(
		head.Position + HeadBringConfig.HeadOffset
	)

	local movedCount = 0
	local missingCount = 0

	for _, itemName in ipairs(selectedNames) do
		local matchingObjects = findObjectsByName(itemName)

		if #matchingObjects == 0 then
			missingCount += 1
		else
			for _, object in ipairs(matchingObjects) do
				if moveObject(object, targetCFrame) then
					movedCount += 1
				end

				-- อย่างละหนึ่งชิ้น
				if not moveAll then
					break
				end
			end
		end
	end

	return movedCount, missingCount
end

--==================================================
-- ระบบ Pizza Oven
--==================================================

local function getCraftedFolder()
	local spawnIsland = Workspace:FindFirstChild("SpawnIsland")

	if not spawnIsland then
		warn("ไม่พบ Workspace.SpawnIsland")
		return nil
	end

	local crafted = spawnIsland:FindFirstChild("Crafted")

	if not crafted then
		warn("ไม่พบ Workspace.SpawnIsland.Crafted")
		return nil
	end

	return crafted
end

local function findCraftedMachine(namePrefix)
	local crafted = getCraftedFolder()

	if not crafted then
		return nil
	end

	for _, object in ipairs(crafted:GetChildren()) do
		if string.sub(object.Name, 1, #namePrefix) == namePrefix then
			return object
		end
	end

	for _, object in ipairs(crafted:GetDescendants()) do
		if string.sub(object.Name, 1, #namePrefix) == namePrefix then
			return object
		end
	end

	warn("ไม่พบ Object ที่ชื่อขึ้นต้นด้วย " .. namePrefix)

	return nil
end

local function getPizzaOven()
	return findCraftedMachine("Pizza Oven:")
end

local function getCookingPot()
	return findCraftedMachine("Cooking Pot:")
end

local function getMachineStoreBlock(machine)
	if not machine then
		return nil
	end

	local storeBlock = machine:FindFirstChild(
		"StoreBlock",
		true
	)

	if not storeBlock then
		warn(
			"ไม่พบ StoreBlock ภายใน:",
			machine:GetFullName()
		)

		return nil
	end

	if storeBlock:IsA("BasePart") then
		return storeBlock
	end

	if storeBlock:IsA("Model") then
		return storeBlock.PrimaryPart
			or storeBlock:FindFirstChildWhichIsA(
				"BasePart",
				true
			)
	end

	warn("StoreBlock ไม่มี BasePart")

	return nil
end

local function isFoodObject(object)
	if not FOOD_NAMES[object.Name] then
		return false
	end

	return object:IsA("Model")
		or object:IsA("BasePart")
end

local function findItemsAroundMachine(
	machine,
	storeBlock,
	allowedNames,
	config
)
	local debrisField = getDebrisField()

	if not debrisField
		or not machine
		or not storeBlock then

		return {}
	end

	local machinePosition = getObjectPosition(machine)

	if not machinePosition then
		warn("ไม่สามารถหาตำแหน่งเครื่องได้")
		return {}
	end

	local found = {}

	for _, object in ipairs(debrisField:GetDescendants()) do
		local validType =
			object:IsA("Model")
			or object:IsA("BasePart")

		local validName =
			allowedNames[object.Name] == true

		if validType and validName then
			local objectPosition =
				getObjectPosition(object)

			if objectPosition then
				local distance =
					(
						objectPosition
						- machinePosition
					).Magnitude

				-- ดึงทุก Item ที่อยู่ในระยะ 20 studs
				-- รวมถึง Item ที่ค้างอยู่เหนือเครื่อง
				if distance <= config.SearchRadius then
					table.insert(found, {
						Object = object,
						Distance = distance,
					})
				end
			end
		end
	end

	table.sort(found, function(a, b)
		return a.Distance < b.Distance
	end)

	local results = {}

	for _, data in ipairs(found) do
		table.insert(results, data.Object)
	end

	return results
end

local function bringMachineItemsCycle(
	machineGetter,
	allowedNames,
	config
)
	local machine = machineGetter()

	if not machine then
		return 0
	end

	local storeBlock = getMachineStoreBlock(machine)

	if not storeBlock then
		return 0
	end

	local availableItems =
		findItemsAroundMachine(
			machine,
			storeBlock,
			allowedNames,
			config
		)

	if #availableItems == 0 then
		return 0
	end

	-- ใช้ตำแหน่งเดียวกับระบบดึง Item มาตรงหัว
	-- ทุก Item จะซ้อนกันที่ตำแหน่งเดียวกัน
	local targetCFrame = CFrame.new(
		storeBlock.Position
		+ Vector3.new(
			0,
			config.YOffset,
			0
		)
	)

	local movedCount = 0

	for _, object in ipairs(availableItems) do
		if movedCount >= config.AmountPerCycle then
			break
		end

		if moveObject(object, targetCFrame) then
			movedCount += 1
		end
	end

	return movedCount
end

local function bringPizzaCycle()
	return bringMachineItemsCycle(
		getPizzaOven,
		FOOD_NAMES,
		AutoPizzaConfig
	)
end

local function bringCookingPotCycle()
	return bringMachineItemsCycle(
		getCookingPot,
		COOKING_POT_ITEM_NAMES,
		AutoCookingPotConfig
	)
end

local function enableAutoMachine(config, cycleFunction, name)
	if config.Enabled then
		return
	end

	config.Enabled = true

	local success, result = pcall(cycleFunction)

	if not success then
		warn(name .. " Auto Bring error:", result)
	end

	config.Thread = task.spawn(function()
		while config.Enabled do
			task.wait(config.Interval)

			if not config.Enabled then
				break
			end

			local cycleSuccess, cycleResult =
				pcall(cycleFunction)

			if not cycleSuccess then
				warn(
					name .. " Auto Bring error:",
					cycleResult
				)
			end
		end
	end)
end

local function disableAutoMachine(config)
	config.Enabled = false

	if config.Thread then
		task.cancel(config.Thread)
		config.Thread = nil
	end
end

local function enableAutoPizza()
	enableAutoMachine(
		AutoPizzaConfig,
		bringPizzaCycle,
		"Pizza Oven"
	)
end
local function enableAutoCookingPot()
	enableAutoMachine(
		AutoCookingPotConfig,
		bringCookingPotCycle,
		"Cooking Pot"
	)
end

local function disableAutoCookingPot()
	disableAutoMachine(AutoCookingPotConfig)
end

local function toggleAutoCookingPot(enabled)
	if enabled then
		enableAutoCookingPot()
	else
		disableAutoCookingPot()
	end
end

local function disableAutoPizza()
	disableAutoMachine(AutoPizzaConfig)
end

local function toggleAutoPizza(enabled)
	if enabled then
		enableAutoPizza()
	else
		disableAutoPizza()
	end
end

--==================================================
-- ระบบ Graphics
--==================================================

local function saveOriginalGraphics()
	if GraphicsConfig.Saved then
		return
	end

	GraphicsConfig.Saved = true
	GraphicsConfig.OriginalProperties = {
		FogEnd = Lighting.FogEnd,
		FogStart = Lighting.FogStart,
		ClockTime = Lighting.ClockTime,
		Brightness = Lighting.Brightness,
		GlobalShadows = Lighting.GlobalShadows,
		ExposureCompensation = Lighting.ExposureCompensation,
	}

	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Atmosphere")
			or child:IsA("BlurEffect")
			or child:IsA("SunRaysEffect")
			or child:IsA("Sky") then

			table.insert(
				GraphicsConfig.OriginalEffects,
				child:Clone()
			)
		end
	end
end

local function removeGraphicsEffects()
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Atmosphere")
			or child:IsA("BlurEffect")
			or child:IsA("SunRaysEffect")
			or child:IsA("Sky") then

			child:Destroy()
		end
	end
end

local function createDefaultSky()
	-- ไม่สร้าง Skybox แบบกำหนด Texture
	-- เมื่อไม่มี Sky object Roblox จะใช้ท้องฟ้าเริ่มต้นที่สว่างกว่า
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Sky") then
			child:Destroy()
		end
	end
end

local function enableGraphicsMode()
	saveOriginalGraphics()
	removeGraphicsEffects()
	createDefaultSky()

	Lighting.FogEnd = 100000
	Lighting.FogStart = 0
	Lighting.ClockTime = 14
	Lighting.Brightness = 2
	Lighting.GlobalShadows = false
	Lighting.ExposureCompensation = 0.5

	GraphicsConfig.Enabled = true
end

local function disableGraphicsMode()
	if not GraphicsConfig.Saved then
		GraphicsConfig.Enabled = false
		return
	end

	removeGraphicsEffects()

	for _, savedEffect in ipairs(GraphicsConfig.OriginalEffects) do
		savedEffect:Clone().Parent = Lighting
	end

	local original = GraphicsConfig.OriginalProperties
	Lighting.FogEnd = original.FogEnd
	Lighting.FogStart = original.FogStart
	Lighting.ClockTime = original.ClockTime
	Lighting.Brightness = original.Brightness
	Lighting.GlobalShadows = original.GlobalShadows
	Lighting.ExposureCompensation = original.ExposureCompensation

	GraphicsConfig.Enabled = false
end

local function toggleGraphicsMode(enabled)
	if enabled then
		enableGraphicsMode()
	else
		disableGraphicsMode()
	end
end

--==================================================
-- สร้าง GUI
--==================================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ItemUtilityMenuGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.fromOffset(390, 440)
mainFrame.Position = UDim2.new(0.5, -195, 0.5, -220)
mainFrame.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui

addCorner(mainFrame, 12)
addStroke(mainFrame)

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
titleLabel.Text = "ITEM UTILITY"
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
-- Tab Bar
--==================================================

local tabBar = Instance.new("Frame")
tabBar.Name = "TabBar"
tabBar.Size = UDim2.new(1, -24, 0, 42)
tabBar.Position = UDim2.fromOffset(12, 56)
tabBar.BackgroundColor3 = Color3.fromRGB(31, 34, 41)
tabBar.BorderSizePixel = 0
tabBar.Parent = mainFrame

addCorner(tabBar, 9)

local headTabButton = Instance.new("TextButton")
headTabButton.Name = "HeadTabButton"
headTabButton.Size = UDim2.new(0.25, -5, 1, -8)
headTabButton.Position = UDim2.fromOffset(4, 4)
headTabButton.BackgroundColor3 = Color3.fromRGB(46, 120, 220)
headTabButton.BorderSizePixel = 0
headTabButton.Font = Enum.Font.GothamBold
headTabButton.Text = "ดึง Item"
headTabButton.TextColor3 = Color3.fromRGB(255, 255, 255)
headTabButton.TextSize = 13
headTabButton.Parent = tabBar

addCorner(headTabButton, 7)

local pizzaTabButton = Instance.new("TextButton")
pizzaTabButton.Name = "PizzaTabButton"
pizzaTabButton.Size = UDim2.new(0.25, -5, 1, -8)
pizzaTabButton.Position = UDim2.new(0.25, 1, 0, 4)
pizzaTabButton.BackgroundColor3 = Color3.fromRGB(55, 58, 68)
pizzaTabButton.BorderSizePixel = 0
pizzaTabButton.Font = Enum.Font.GothamBold
pizzaTabButton.Text = "Pizza Oven"
pizzaTabButton.TextColor3 = Color3.fromRGB(220, 220, 225)
pizzaTabButton.TextSize = 13
pizzaTabButton.Parent = tabBar

addCorner(pizzaTabButton, 7)

local cookingPotTabButton = Instance.new("TextButton")
cookingPotTabButton.Name = "CookingPotTabButton"
cookingPotTabButton.Size = UDim2.new(0.25, -5, 1, -8)
cookingPotTabButton.Position = UDim2.new(0.5, 2, 0, 4)
cookingPotTabButton.BackgroundColor3 =
	Color3.fromRGB(55, 58, 68)
cookingPotTabButton.BorderSizePixel = 0
cookingPotTabButton.Font = Enum.Font.GothamBold
cookingPotTabButton.Text = "Cooking Pot"
cookingPotTabButton.TextColor3 =
	Color3.fromRGB(220, 220, 225)
cookingPotTabButton.TextSize = 12
cookingPotTabButton.Parent = tabBar

addCorner(cookingPotTabButton, 7)

local graphicsTabButton = Instance.new("TextButton")
graphicsTabButton.Name = "GraphicsTabButton"
graphicsTabButton.Size = UDim2.new(0.25, -5, 1, -8)
graphicsTabButton.Position = UDim2.new(0.75, 0, 0, 4)
graphicsTabButton.BackgroundColor3 = Color3.fromRGB(55, 58, 68)
graphicsTabButton.BorderSizePixel = 0
graphicsTabButton.Font = Enum.Font.GothamBold
graphicsTabButton.Text = "Graphics"
graphicsTabButton.TextColor3 = Color3.fromRGB(220, 220, 225)
graphicsTabButton.TextSize = 12
graphicsTabButton.Parent = tabBar

addCorner(graphicsTabButton, 7)

--==================================================
-- Content Container
--==================================================

local contentContainer = Instance.new("Frame")
contentContainer.Name = "ContentContainer"
contentContainer.Size = UDim2.new(1, -24, 1, -120)
contentContainer.Position = UDim2.fromOffset(12, 108)
contentContainer.BackgroundTransparency = 1
contentContainer.Parent = mainFrame

--==================================================
-- Tab 1: ดึง Item
--==================================================

local headTab = Instance.new("Frame")
headTab.Name = "HeadTab"
headTab.Size = UDim2.fromScale(1, 1)
headTab.BackgroundColor3 = Color3.fromRGB(31, 34, 41)
headTab.BorderSizePixel = 0
headTab.Visible = true
headTab.Parent = contentContainer

addCorner(headTab, 10)

local dropdownButton = Instance.new("TextButton")
dropdownButton.Name = "DropdownButton"
dropdownButton.Size = UDim2.new(1, -28, 0, 42)
dropdownButton.Position = UDim2.fromOffset(14, 14)
dropdownButton.BackgroundColor3 = Color3.fromRGB(43, 46, 56)
dropdownButton.BorderSizePixel = 0
dropdownButton.Font = Enum.Font.GothamMedium
dropdownButton.Text = "เลือก Item หลายรายการ ▼"
dropdownButton.TextColor3 = Color3.fromRGB(235, 235, 240)
dropdownButton.TextSize = 14
dropdownButton.TextXAlignment = Enum.TextXAlignment.Left
dropdownButton.Parent = headTab

addCorner(dropdownButton, 8)

local dropdownButtonPadding = Instance.new("UIPadding")
dropdownButtonPadding.PaddingLeft = UDim.new(0, 12)
dropdownButtonPadding.Parent = dropdownButton

local headStatusLabel = Instance.new("TextLabel")
headStatusLabel.Size = UDim2.new(1, -28, 0, 44)
headStatusLabel.Position = UDim2.fromOffset(14, 68)
headStatusLabel.BackgroundTransparency = 1
headStatusLabel.Font = Enum.Font.Gotham
headStatusLabel.Text = "ยังไม่ได้เลือก Item"
headStatusLabel.TextColor3 = Color3.fromRGB(150, 155, 170)
headStatusLabel.TextSize = 12
headStatusLabel.TextWrapped = true
headStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
headStatusLabel.TextYAlignment = Enum.TextYAlignment.Top
headStatusLabel.Parent = headTab

local bringOneButton = Instance.new("TextButton")
bringOneButton.Size = UDim2.new(0.5, -21, 0, 40)
bringOneButton.Position = UDim2.fromOffset(14, 122)
bringOneButton.BackgroundColor3 = Color3.fromRGB(46, 120, 220)
bringOneButton.BorderSizePixel = 0
bringOneButton.Font = Enum.Font.GothamBold
bringOneButton.Text = "ดึงอย่างละ 1 ชิ้น"
bringOneButton.TextColor3 = Color3.fromRGB(255, 255, 255)
bringOneButton.TextSize = 12
bringOneButton.Parent = headTab

addCorner(bringOneButton, 8)

local bringAllButton = Instance.new("TextButton")
bringAllButton.Size = UDim2.new(0.5, -21, 0, 40)
bringAllButton.Position = UDim2.new(0.5, 7, 0, 122)
bringAllButton.BackgroundColor3 = Color3.fromRGB(45, 170, 95)
bringAllButton.BorderSizePixel = 0
bringAllButton.Font = Enum.Font.GothamBold
bringAllButton.Text = "ดึงทั้งหมด"
bringAllButton.TextColor3 = Color3.fromRGB(255, 255, 255)
bringAllButton.TextSize = 12
bringAllButton.Parent = headTab

addCorner(bringAllButton, 8)

local headResultLabel = Instance.new("TextLabel")
headResultLabel.Size = UDim2.new(1, -28, 0, 60)
headResultLabel.Position = UDim2.fromOffset(14, 176)
headResultLabel.BackgroundTransparency = 1
headResultLabel.Font = Enum.Font.Gotham
headResultLabel.Text = ""
headResultLabel.TextColor3 = Color3.fromRGB(135, 180, 255)
headResultLabel.TextSize = 11
headResultLabel.TextWrapped = true
headResultLabel.TextXAlignment = Enum.TextXAlignment.Left
headResultLabel.TextYAlignment = Enum.TextYAlignment.Top
headResultLabel.Parent = headTab

--==================================================
-- Multi Dropdown
--==================================================

local dropdownList = Instance.new("Frame")
dropdownList.Name = "DropdownList"
dropdownList.Size = UDim2.new(1, -28, 0, 270)
dropdownList.Position = UDim2.fromOffset(14, 60)
dropdownList.BackgroundColor3 = Color3.fromRGB(35, 38, 46)
dropdownList.BorderSizePixel = 0
dropdownList.Visible = false
dropdownList.ZIndex = 30
dropdownList.Parent = headTab

addCorner(dropdownList, 8)
addStroke(dropdownList)

local dropdownHeader = Instance.new("Frame")
dropdownHeader.Size = UDim2.new(1, 0, 0, 42)
dropdownHeader.BackgroundColor3 = Color3.fromRGB(40, 43, 52)
dropdownHeader.BorderSizePixel = 0
dropdownHeader.ZIndex = 31
dropdownHeader.Parent = dropdownList

addCorner(dropdownHeader, 8)

local selectAllButton = Instance.new("TextButton")
selectAllButton.Size = UDim2.fromOffset(105, 30)
selectAllButton.Position = UDim2.fromOffset(7, 6)
selectAllButton.BackgroundColor3 = Color3.fromRGB(45, 170, 95)
selectAllButton.BorderSizePixel = 0
selectAllButton.Font = Enum.Font.GothamBold
selectAllButton.Text = "เลือกทั้งหมด"
selectAllButton.TextColor3 = Color3.fromRGB(255, 255, 255)
selectAllButton.TextSize = 11
selectAllButton.ZIndex = 32
selectAllButton.Parent = dropdownHeader

addCorner(selectAllButton, 6)

local clearAllButton = Instance.new("TextButton")
clearAllButton.Size = UDim2.fromOffset(105, 30)
clearAllButton.Position = UDim2.fromOffset(118, 6)
clearAllButton.BackgroundColor3 = Color3.fromRGB(160, 65, 65)
clearAllButton.BorderSizePixel = 0
clearAllButton.Font = Enum.Font.GothamBold
clearAllButton.Text = "ยกเลิกทั้งหมด"
clearAllButton.TextColor3 = Color3.fromRGB(255, 255, 255)
clearAllButton.TextSize = 11
clearAllButton.ZIndex = 32
clearAllButton.Parent = dropdownHeader

addCorner(clearAllButton, 6)

local doneButton = Instance.new("TextButton")
doneButton.Size = UDim2.fromOffset(94, 30)
doneButton.Position = UDim2.new(1, -101, 0, 6)
doneButton.BackgroundColor3 = Color3.fromRGB(46, 120, 220)
doneButton.BorderSizePixel = 0
doneButton.Font = Enum.Font.GothamBold
doneButton.Text = "เสร็จสิ้น"
doneButton.TextColor3 = Color3.fromRGB(255, 255, 255)
doneButton.TextSize = 11
doneButton.ZIndex = 32
doneButton.Parent = dropdownHeader

addCorner(doneButton, 6)

local dropdownScroll = Instance.new("ScrollingFrame")
dropdownScroll.Size = UDim2.new(1, -10, 1, -52)
dropdownScroll.Position = UDim2.fromOffset(5, 47)
dropdownScroll.BackgroundTransparency = 1
dropdownScroll.BorderSizePixel = 0
dropdownScroll.ScrollBarThickness = 4
dropdownScroll.ScrollBarImageColor3 = Color3.fromRGB(110, 115, 130)
dropdownScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
dropdownScroll.CanvasSize = UDim2.fromOffset(0, 0)
dropdownScroll.ZIndex = 31
dropdownScroll.Parent = dropdownList

local dropdownLayout = Instance.new("UIListLayout")
dropdownLayout.Padding = UDim.new(0, 4)
dropdownLayout.SortOrder = Enum.SortOrder.LayoutOrder
dropdownLayout.Parent = dropdownScroll

local dropdownPadding = Instance.new("UIPadding")
dropdownPadding.PaddingTop = UDim.new(0, 5)
dropdownPadding.PaddingBottom = UDim.new(0, 5)
dropdownPadding.PaddingLeft = UDim.new(0, 5)
dropdownPadding.PaddingRight = UDim.new(0, 5)
dropdownPadding.Parent = dropdownScroll

--==================================================
-- Tab 2: Pizza Oven
--==================================================

local pizzaTab = Instance.new("Frame")
pizzaTab.Name = "PizzaTab"
pizzaTab.Size = UDim2.fromScale(1, 1)
pizzaTab.BackgroundColor3 = Color3.fromRGB(31, 34, 41)
pizzaTab.BorderSizePixel = 0
pizzaTab.Visible = false
pizzaTab.Parent = contentContainer

addCorner(pizzaTab, 10)

local pizzaTitle = Instance.new("TextLabel")
pizzaTitle.Size = UDim2.new(1, -140, 0, 28)
pizzaTitle.Position = UDim2.fromOffset(14, 14)
pizzaTitle.BackgroundTransparency = 1
pizzaTitle.Font = Enum.Font.GothamSemibold
pizzaTitle.Text = "ดึงอาหารรอบ Pizza Oven"
pizzaTitle.TextColor3 = Color3.fromRGB(245, 245, 245)
pizzaTitle.TextSize = 14
pizzaTitle.TextXAlignment = Enum.TextXAlignment.Left
pizzaTitle.Parent = pizzaTab

local pizzaDescription = Instance.new("TextLabel")
pizzaDescription.Size = UDim2.new(1, -28, 0, 66)
pizzaDescription.Position = UDim2.fromOffset(14, 48)
pizzaDescription.BackgroundTransparency = 1
pizzaDescription.Font = Enum.Font.Gotham
pizzaDescription.Text =
	"ค้นหาอาหารภายในระยะ 20 studs\n"
	.. "ดึงครั้งละ 3 ชิ้น ทุก 10 วินาที\n"
	.. "วางซ้อนเหนือ StoreBlock"
pizzaDescription.TextColor3 = Color3.fromRGB(145, 150, 163)
pizzaDescription.TextSize = 11
pizzaDescription.TextWrapped = true
pizzaDescription.TextXAlignment = Enum.TextXAlignment.Left
pizzaDescription.TextYAlignment = Enum.TextYAlignment.Top
pizzaDescription.Parent = pizzaTab

local pizzaToggleButton = Instance.new("TextButton")
pizzaToggleButton.Size = UDim2.fromOffset(100, 38)
pizzaToggleButton.Position = UDim2.new(1, -114, 0, 16)
pizzaToggleButton.BackgroundColor3 = Color3.fromRGB(70, 73, 84)
pizzaToggleButton.BorderSizePixel = 0
pizzaToggleButton.Font = Enum.Font.GothamBold
pizzaToggleButton.Text = "ปิด"
pizzaToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
pizzaToggleButton.TextSize = 13
pizzaToggleButton.Parent = pizzaTab

addCorner(pizzaToggleButton, 8)

local pizzaStatusLabel = Instance.new("TextLabel")
pizzaStatusLabel.Size = UDim2.new(1, -28, 0, 42)
pizzaStatusLabel.Position = UDim2.fromOffset(14, 120)
pizzaStatusLabel.BackgroundTransparency = 1
pizzaStatusLabel.Font = Enum.Font.GothamMedium
pizzaStatusLabel.Text = "สถานะ: ปิด"
pizzaStatusLabel.TextColor3 = Color3.fromRGB(170, 175, 190)
pizzaStatusLabel.TextSize = 12
pizzaStatusLabel.TextWrapped = true
pizzaStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
pizzaStatusLabel.TextYAlignment = Enum.TextYAlignment.Top
pizzaStatusLabel.Parent = pizzaTab

local bringNowButton = Instance.new("TextButton")
bringNowButton.Size = UDim2.new(0.5, -21, 0, 40)
bringNowButton.Position = UDim2.fromOffset(14, 176)
bringNowButton.BackgroundColor3 = Color3.fromRGB(46, 120, 220)
bringNowButton.BorderSizePixel = 0
bringNowButton.Font = Enum.Font.GothamBold
bringNowButton.Text = "ดึงทันที 3 ชิ้น"
bringNowButton.TextColor3 = Color3.fromRGB(255, 255, 255)
bringNowButton.TextSize = 12
bringNowButton.Parent = pizzaTab

addCorner(bringNowButton, 8)

local resetPizzaButton = Instance.new("TextButton")
resetPizzaButton.Size = UDim2.new(0.5, -21, 0, 40)
resetPizzaButton.Position = UDim2.new(0.5, 7, 0, 176)
resetPizzaButton.BackgroundColor3 = Color3.fromRGB(145, 90, 45)
resetPizzaButton.BorderSizePixel = 0
resetPizzaButton.Font = Enum.Font.GothamBold
resetPizzaButton.Text = "รีเซ็ตรายการ"
resetPizzaButton.TextColor3 = Color3.fromRGB(255, 255, 255)
resetPizzaButton.TextSize = 12
resetPizzaButton.Parent = pizzaTab

addCorner(resetPizzaButton, 8)

local foodListLabel = Instance.new("TextLabel")
foodListLabel.Size = UDim2.new(1, -28, 0, 90)
foodListLabel.Position = UDim2.fromOffset(14, 230)
foodListLabel.BackgroundTransparency = 1
foodListLabel.Font = Enum.Font.Gotham
foodListLabel.Text =
	"รายการ: Stew1, Potato1, Sushi1, Orange1,\n"
	.. "LobsterTail1, FishandChips, Calamari,\n"
	.. "Jam1, Unagi"
foodListLabel.TextColor3 = Color3.fromRGB(130, 135, 148)
foodListLabel.TextSize = 10
foodListLabel.TextWrapped = true
foodListLabel.TextXAlignment = Enum.TextXAlignment.Left
foodListLabel.TextYAlignment = Enum.TextYAlignment.Top
foodListLabel.Parent = pizzaTab

--==================================================
-- Tab 3: Cooking Pot
--==================================================

local cookingPotTab = Instance.new("Frame")
cookingPotTab.Name = "CookingPotTab"
cookingPotTab.Size = UDim2.fromScale(1, 1)
cookingPotTab.BackgroundColor3 =
	Color3.fromRGB(31, 34, 41)
cookingPotTab.BorderSizePixel = 0
cookingPotTab.Visible = false
cookingPotTab.Parent = contentContainer

addCorner(cookingPotTab, 10)

local cookingPotTitle = Instance.new("TextLabel")
cookingPotTitle.Size = UDim2.new(1, -140, 0, 28)
cookingPotTitle.Position = UDim2.fromOffset(14, 14)
cookingPotTitle.BackgroundTransparency = 1
cookingPotTitle.Font = Enum.Font.GothamSemibold
cookingPotTitle.Text = "ดึง Item รอบ Cooking Pot"
cookingPotTitle.TextColor3 =
	Color3.fromRGB(245, 245, 245)
cookingPotTitle.TextSize = 14
cookingPotTitle.TextXAlignment =
	Enum.TextXAlignment.Left
cookingPotTitle.Parent = cookingPotTab

local cookingPotDescription = Instance.new("TextLabel")
cookingPotDescription.Size = UDim2.new(1, -28, 0, 66)
cookingPotDescription.Position = UDim2.fromOffset(14, 48)
cookingPotDescription.BackgroundTransparency = 1
cookingPotDescription.Font = Enum.Font.Gotham
cookingPotDescription.Text =
	"ค้นหา Item ภายในระยะ 20 studs\n"
	.. "ดึงครั้งละ 3 ชิ้น ทุก 10 วินาที\n"
	.. "วางซ้อนเหนือ StoreBlock"
cookingPotDescription.TextColor3 =
	Color3.fromRGB(145, 150, 163)
cookingPotDescription.TextSize = 11
cookingPotDescription.TextWrapped = true
cookingPotDescription.TextXAlignment =
	Enum.TextXAlignment.Left
cookingPotDescription.TextYAlignment =
	Enum.TextYAlignment.Top
cookingPotDescription.Parent = cookingPotTab

local cookingPotToggleButton = Instance.new("TextButton")
cookingPotToggleButton.Size = UDim2.fromOffset(100, 38)
cookingPotToggleButton.Position =
	UDim2.new(1, -114, 0, 16)
cookingPotToggleButton.BackgroundColor3 =
	Color3.fromRGB(70, 73, 84)
cookingPotToggleButton.BorderSizePixel = 0
cookingPotToggleButton.Font = Enum.Font.GothamBold
cookingPotToggleButton.Text = "ปิด"
cookingPotToggleButton.TextColor3 =
	Color3.fromRGB(255, 255, 255)
cookingPotToggleButton.TextSize = 13
cookingPotToggleButton.Parent = cookingPotTab

addCorner(cookingPotToggleButton, 8)

local cookingPotStatusLabel = Instance.new("TextLabel")
cookingPotStatusLabel.Size = UDim2.new(1, -28, 0, 42)
cookingPotStatusLabel.Position = UDim2.fromOffset(14, 120)
cookingPotStatusLabel.BackgroundTransparency = 1
cookingPotStatusLabel.Font = Enum.Font.GothamMedium
cookingPotStatusLabel.Text = "สถานะ: ปิด"
cookingPotStatusLabel.TextColor3 =
	Color3.fromRGB(170, 175, 190)
cookingPotStatusLabel.TextSize = 12
cookingPotStatusLabel.TextWrapped = true
cookingPotStatusLabel.TextXAlignment =
	Enum.TextXAlignment.Left
cookingPotStatusLabel.TextYAlignment =
	Enum.TextYAlignment.Top
cookingPotStatusLabel.Parent = cookingPotTab

local cookingPotBringNowButton = Instance.new("TextButton")
cookingPotBringNowButton.Size =
	UDim2.new(0.5, -21, 0, 40)
cookingPotBringNowButton.Position =
	UDim2.fromOffset(14, 176)
cookingPotBringNowButton.BackgroundColor3 =
	Color3.fromRGB(46, 120, 220)
cookingPotBringNowButton.BorderSizePixel = 0
cookingPotBringNowButton.Font = Enum.Font.GothamBold
cookingPotBringNowButton.Text = "ดึงทันที 3 ชิ้น"
cookingPotBringNowButton.TextColor3 =
	Color3.fromRGB(255, 255, 255)
cookingPotBringNowButton.TextSize = 12
cookingPotBringNowButton.Parent = cookingPotTab

addCorner(cookingPotBringNowButton, 8)

local cookingPotResetButton = Instance.new("TextButton")
cookingPotResetButton.Size =
	UDim2.new(0.5, -21, 0, 40)
cookingPotResetButton.Position =
	UDim2.new(0.5, 7, 0, 176)
cookingPotResetButton.BackgroundColor3 =
	Color3.fromRGB(145, 90, 45)
cookingPotResetButton.BorderSizePixel = 0
cookingPotResetButton.Font = Enum.Font.GothamBold
cookingPotResetButton.Text = "รีเซ็ตรายการ"
cookingPotResetButton.TextColor3 =
	Color3.fromRGB(255, 255, 255)
cookingPotResetButton.TextSize = 12
cookingPotResetButton.Parent = cookingPotTab

addCorner(cookingPotResetButton, 8)


--==================================================
-- Tab 4: Graphics
--==================================================

local graphicsTab = Instance.new("Frame")
graphicsTab.Name = "GraphicsTab"
graphicsTab.Size = UDim2.fromScale(1, 1)
graphicsTab.BackgroundColor3 = Color3.fromRGB(31, 34, 41)
graphicsTab.BorderSizePixel = 0
graphicsTab.Visible = false
graphicsTab.Parent = contentContainer

addCorner(graphicsTab, 10)

local graphicsTitle = Instance.new("TextLabel")
graphicsTitle.Size = UDim2.new(1, -140, 0, 28)
graphicsTitle.Position = UDim2.fromOffset(14, 14)
graphicsTitle.BackgroundTransparency = 1
graphicsTitle.Font = Enum.Font.GothamSemibold
graphicsTitle.Text = "Graphics Optimization"
graphicsTitle.TextColor3 = Color3.fromRGB(245, 245, 245)
graphicsTitle.TextSize = 14
graphicsTitle.TextXAlignment = Enum.TextXAlignment.Left
graphicsTitle.Parent = graphicsTab

local graphicsDescription = Instance.new("TextLabel")
graphicsDescription.Size = UDim2.new(1, -28, 0, 112)
graphicsDescription.Position = UDim2.fromOffset(14, 48)
graphicsDescription.BackgroundTransparency = 1
graphicsDescription.Font = Enum.Font.Gotham
graphicsDescription.Text =
	"• Remove Fog / Atmosphere / Blur / Sun Rays\n"
	.. "• ใช้ท้องฟ้าเริ่มต้นแบบสว่าง ไม่มี Galaxy\n"
	.. "• ClockTime = 14, Brightness = 2\n"
	.. "• GlobalShadows = false"
graphicsDescription.TextColor3 = Color3.fromRGB(145, 150, 163)
graphicsDescription.TextSize = 11
graphicsDescription.TextWrapped = true
graphicsDescription.TextXAlignment = Enum.TextXAlignment.Left
graphicsDescription.TextYAlignment = Enum.TextYAlignment.Top
graphicsDescription.Parent = graphicsTab

local graphicsToggleButton = Instance.new("TextButton")
graphicsToggleButton.Size = UDim2.fromOffset(100, 38)
graphicsToggleButton.Position = UDim2.new(1, -114, 0, 16)
graphicsToggleButton.BackgroundColor3 = Color3.fromRGB(70, 73, 84)
graphicsToggleButton.BorderSizePixel = 0
graphicsToggleButton.Font = Enum.Font.GothamBold
graphicsToggleButton.Text = "ปิด"
graphicsToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
graphicsToggleButton.TextSize = 13
graphicsToggleButton.Parent = graphicsTab

addCorner(graphicsToggleButton, 8)

local graphicsStatusLabel = Instance.new("TextLabel")
graphicsStatusLabel.Size = UDim2.new(1, -28, 0, 42)
graphicsStatusLabel.Position = UDim2.fromOffset(14, 170)
graphicsStatusLabel.BackgroundTransparency = 1
graphicsStatusLabel.Font = Enum.Font.GothamMedium
graphicsStatusLabel.Text = "สถานะ: ปิด"
graphicsStatusLabel.TextColor3 = Color3.fromRGB(170, 175, 190)
graphicsStatusLabel.TextSize = 12
graphicsStatusLabel.TextWrapped = true
graphicsStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
graphicsStatusLabel.TextYAlignment = Enum.TextYAlignment.Top
graphicsStatusLabel.Parent = graphicsTab

local applyGraphicsButton = Instance.new("TextButton")
applyGraphicsButton.Size = UDim2.new(1, -28, 0, 40)
applyGraphicsButton.Position = UDim2.fromOffset(14, 224)
applyGraphicsButton.BackgroundColor3 = Color3.fromRGB(46, 120, 220)
applyGraphicsButton.BorderSizePixel = 0
applyGraphicsButton.Font = Enum.Font.GothamBold
applyGraphicsButton.Text = "ใช้ค่ากราฟิกอีกครั้ง"
applyGraphicsButton.TextColor3 = Color3.fromRGB(255, 255, 255)
applyGraphicsButton.TextSize = 12
applyGraphicsButton.Parent = graphicsTab

addCorner(applyGraphicsButton, 8)

--==================================================
-- Logo ตอนย่อ
--==================================================

local logoButton = Instance.new("ImageButton")
logoButton.Name = "LogoButton"
logoButton.Size = UDim2.fromOffset(60, 60)
logoButton.Position = mainFrame.Position
logoButton.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
logoButton.BorderSizePixel = 0
logoButton.Image = LOGO_ASSET_ID
logoButton.ScaleType = Enum.ScaleType.Fit
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
-- อัปเดต UI Tab ดึง Item
--==================================================

local function updateHeadSelectionUI()
	local selectedNames = getSelectedNames()
	local selectedCount = #selectedNames

	if selectedCount == 0 then
		dropdownButton.Text = "เลือก Item หลายรายการ ▼"
		headStatusLabel.Text = "ยังไม่ได้เลือก Item"
		headStatusLabel.TextColor3 =
			Color3.fromRGB(150, 155, 170)

	elseif selectedCount == 1 then
		local objectCount =
			#findObjectsByName(selectedNames[1])

		dropdownButton.Text = selectedNames[1] .. " ✓"

		headStatusLabel.Text = string.format(
			"เลือก %s | พบ %d ชิ้น",
			selectedNames[1],
			objectCount
		)

		headStatusLabel.TextColor3 =
			Color3.fromRGB(80, 210, 130)
	else
		dropdownButton.Text = string.format(
			"เลือกแล้ว %d รายการ ▼",
			selectedCount
		)

		headStatusLabel.Text = string.format(
			"เลือก %d รายการ | พบรวม %d ชิ้น",
			selectedCount,
			countSelectedObjects()
		)

		headStatusLabel.TextColor3 =
			Color3.fromRGB(80, 210, 130)
	end

	for itemName, button in pairs(optionButtons) do
		if HeadBringConfig.SelectedNames[itemName] then
			button.Text = "✓  " .. itemName
			button.BackgroundColor3 =
				Color3.fromRGB(45, 140, 85)
		else
			button.Text = "     " .. itemName
			button.BackgroundColor3 =
				Color3.fromRGB(45, 48, 58)
		end
	end
end

--==================================================
-- สร้างตัวเลือก Item
--==================================================

for index, itemName in ipairs(HEAD_ITEM_NAMES) do
	local optionButton = Instance.new("TextButton")
	optionButton.Name = itemName .. "Option"
	optionButton.Size = UDim2.new(1, -4, 0, 34)
	optionButton.BackgroundColor3 = Color3.fromRGB(45, 48, 58)
	optionButton.BorderSizePixel = 0
	optionButton.Font = Enum.Font.GothamMedium
	optionButton.Text = "     " .. itemName
	optionButton.TextColor3 = Color3.fromRGB(235, 235, 240)
	optionButton.TextSize = 13
	optionButton.TextXAlignment = Enum.TextXAlignment.Left
	optionButton.LayoutOrder = index
	optionButton.ZIndex = 32
	optionButton.Parent = dropdownScroll

	addCorner(optionButton, 6)

	local optionPadding = Instance.new("UIPadding")
	optionPadding.PaddingLeft = UDim.new(0, 10)
	optionPadding.Parent = optionButton

	optionButtons[itemName] = optionButton

	optionButton.MouseButton1Click:Connect(function()
		local selected =
			HeadBringConfig.SelectedNames[itemName]

		if selected then
			HeadBringConfig.SelectedNames[itemName] = nil
		else
			HeadBringConfig.SelectedNames[itemName] = true
		end

		updateHeadSelectionUI()
	end)
end

--==================================================
-- อัปเดต UI Pizza
--==================================================

local function updatePizzaUI()
	if AutoPizzaConfig.Enabled then
		pizzaToggleButton.Text = "เปิด"
		pizzaToggleButton.BackgroundColor3 =
			Color3.fromRGB(45, 170, 95)

		pizzaStatusLabel.Text = string.format(
			"สถานะ: เปิด | ระยะ %d | ครั้งละ %d ชิ้น ทุก %d วิ",
			AutoPizzaConfig.SearchRadius,
			AutoPizzaConfig.AmountPerCycle,
			AutoPizzaConfig.Interval
		)

		pizzaStatusLabel.TextColor3 =
			Color3.fromRGB(80, 210, 130)
	else
		pizzaToggleButton.Text = "ปิด"
		pizzaToggleButton.BackgroundColor3 =
			Color3.fromRGB(70, 73, 84)

		pizzaStatusLabel.Text = "สถานะ: ปิด"
		pizzaStatusLabel.TextColor3 =
			Color3.fromRGB(170, 175, 190)
	end
end


--==================================================
-- อัปเดต UI Cooking
--==================================================
local function updateCookingPotUI()
	if AutoCookingPotConfig.Enabled then
		cookingPotToggleButton.Text = "เปิด"
		cookingPotToggleButton.BackgroundColor3 =
			Color3.fromRGB(45, 170, 95)

		cookingPotStatusLabel.Text = string.format(
			"สถานะ: เปิด | ระยะ %d | ครั้งละ %d ชิ้น ทุก %d วิ",
			AutoCookingPotConfig.SearchRadius,
			AutoCookingPotConfig.AmountPerCycle,
			AutoCookingPotConfig.Interval
		)

		cookingPotStatusLabel.TextColor3 =
			Color3.fromRGB(80, 210, 130)
	else
		cookingPotToggleButton.Text = "ปิด"
		cookingPotToggleButton.BackgroundColor3 =
			Color3.fromRGB(70, 73, 84)

		cookingPotStatusLabel.Text = "สถานะ: ปิด"
		cookingPotStatusLabel.TextColor3 =
			Color3.fromRGB(170, 175, 190)
	end
end


--==================================================
-- อัปเดต UI Graphics
--==================================================

local function updateGraphicsUI()
	if GraphicsConfig.Enabled then
		graphicsToggleButton.Text = "เปิด"
		graphicsToggleButton.BackgroundColor3 =
			Color3.fromRGB(45, 170, 95)

		graphicsStatusLabel.Text =
			"สถานะ: เปิด | Fog และ Effect ถูกปิดแล้ว"

		graphicsStatusLabel.TextColor3 =
			Color3.fromRGB(80, 210, 130)
	else
		graphicsToggleButton.Text = "ปิด"
		graphicsToggleButton.BackgroundColor3 =
			Color3.fromRGB(70, 73, 84)

		graphicsStatusLabel.Text =
			"สถานะ: ปิด | ใช้ค่ากราฟิกเดิม"

		graphicsStatusLabel.TextColor3 =
			Color3.fromRGB(170, 175, 190)
	end
end

--==================================================
-- สลับ Tab
--==================================================

local function openTab(tabName)
	dropdownList.Visible = false

	headTab.Visible = tabName == "Head"
	pizzaTab.Visible = tabName == "Pizza"
	cookingPotTab.Visible = tabName == "CookingPot"
	graphicsTab.Visible = tabName == "Graphics"

	local inactiveBackground =
		Color3.fromRGB(55, 58, 68)

	local inactiveText =
		Color3.fromRGB(220, 220, 225)

	local activeBackground =
		Color3.fromRGB(46, 120, 220)

	local activeText =
		Color3.fromRGB(255, 255, 255)

	headTabButton.BackgroundColor3 =
		tabName == "Head"
		and activeBackground
		or inactiveBackground

	headTabButton.TextColor3 =
		tabName == "Head"
		and activeText
		or inactiveText

	pizzaTabButton.BackgroundColor3 =
		tabName == "Pizza"
		and activeBackground
		or inactiveBackground

	pizzaTabButton.TextColor3 =
		tabName == "Pizza"
		and activeText
		or inactiveText

	cookingPotTabButton.BackgroundColor3 =
		tabName == "CookingPot"
		and activeBackground
		or inactiveBackground

	cookingPotTabButton.TextColor3 =
		tabName == "CookingPot"
		and activeText
		or inactiveText

	graphicsTabButton.BackgroundColor3 =
		tabName == "Graphics"
		and activeBackground
		or inactiveBackground

	graphicsTabButton.TextColor3 =
		tabName == "Graphics"
		and activeText
		or inactiveText
end

--==================================================
-- Events Tab ดึง Item
--==================================================

dropdownButton.MouseButton1Click:Connect(function()
	dropdownList.Visible = not dropdownList.Visible
end)

doneButton.MouseButton1Click:Connect(function()
	dropdownList.Visible = false
end)

selectAllButton.MouseButton1Click:Connect(function()
	for _, itemName in ipairs(HEAD_ITEM_NAMES) do
		HeadBringConfig.SelectedNames[itemName] = true
	end

	updateHeadSelectionUI()
end)

clearAllButton.MouseButton1Click:Connect(function()
	table.clear(HeadBringConfig.SelectedNames)
	updateHeadSelectionUI()
end)

bringOneButton.MouseButton1Click:Connect(function()
	local movedCount, missingCount =
		bringSelectedItems(false)

	if movedCount > 0 then
		headResultLabel.Text = string.format(
			"ดึงอย่างละ 1 ชิ้น รวม %d ชิ้น%s",
			movedCount,
			missingCount > 0
				and string.format(
					" | ไม่พบ %d รายการ",
					missingCount
				)
				or ""
		)

		headResultLabel.TextColor3 =
			Color3.fromRGB(80, 210, 130)
	else
		headResultLabel.Text =
			"กรุณาเลือก Item หรือไม่พบ Object"

		headResultLabel.TextColor3 =
			Color3.fromRGB(230, 100, 100)
	end
end)

bringAllButton.MouseButton1Click:Connect(function()
	local movedCount, missingCount =
		bringSelectedItems(true)

	if movedCount > 0 then
		headResultLabel.Text = string.format(
			"ดึง Object ทั้งหมดรวม %d ชิ้น%s",
			movedCount,
			missingCount > 0
				and string.format(
					" | ไม่พบ %d รายการ",
					missingCount
				)
				or ""
		)

		headResultLabel.TextColor3 =
			Color3.fromRGB(80, 210, 130)
	else
		headResultLabel.Text =
			"กรุณาเลือก Item หรือไม่พบ Object"

		headResultLabel.TextColor3 =
			Color3.fromRGB(230, 100, 100)
	end
end)

--==================================================
-- Events Pizza Oven
--==================================================

pizzaToggleButton.MouseButton1Click:Connect(function()
	toggleAutoPizza(not AutoPizzaConfig.Enabled)
	updatePizzaUI()
end)

bringNowButton.MouseButton1Click:Connect(function()
	local success, movedOrError = pcall(bringPizzaCycle)

	if not success then
		pizzaStatusLabel.Text =
			"เกิดข้อผิดพลาด: " .. tostring(movedOrError)

		pizzaStatusLabel.TextColor3 =
			Color3.fromRGB(230, 100, 100)

		warn("Pizza bring now error:", movedOrError)
		return
	end

	if movedOrError > 0 then
		pizzaStatusLabel.Text = string.format(
			"ดึงอาหารรอบ Pizza Oven แล้ว %d ชิ้น",
			movedOrError
		)

		pizzaStatusLabel.TextColor3 =
			Color3.fromRGB(80, 210, 130)
	else
		pizzaStatusLabel.Text =
			"ไม่พบอาหารในระยะ 20 studs หรือไม่พบ StoreBlock"

		pizzaStatusLabel.TextColor3 =
			Color3.fromRGB(230, 170, 80)
	end
end)

resetPizzaButton.MouseButton1Click:Connect(function()

	pizzaStatusLabel.Text =
		"รีเซ็ตแล้ว สามารถตรวจ Item เดิมอีกครั้ง"

	pizzaStatusLabel.TextColor3 =
		Color3.fromRGB(230, 170, 80)
end)
--==================================================
-- Events Coocking Pot
--==================================================
cookingPotToggleButton.MouseButton1Click:Connect(function()
	toggleAutoCookingPot(
		not AutoCookingPotConfig.Enabled
	)

	updateCookingPotUI()
end)

cookingPotBringNowButton.MouseButton1Click:Connect(function()
	local success, movedOrError =
		pcall(bringCookingPotCycle)

	if not success then
		cookingPotStatusLabel.Text =
			"เกิดข้อผิดพลาด: " .. tostring(movedOrError)

		cookingPotStatusLabel.TextColor3 =
			Color3.fromRGB(230, 100, 100)

		warn("Cooking Pot bring now error:", movedOrError)
		return
	end

	if movedOrError > 0 then
		cookingPotStatusLabel.Text = string.format(
			"ดึง Item รอบ Cooking Pot แล้ว %d ชิ้น",
			movedOrError
		)

		cookingPotStatusLabel.TextColor3 =
			Color3.fromRGB(80, 210, 130)
	else
		cookingPotStatusLabel.Text =
			"ไม่พบ Item ในระยะ 20 studs หรือไม่พบ StoreBlock"

		cookingPotStatusLabel.TextColor3 =
			Color3.fromRGB(230, 170, 80)
	end
end)

cookingPotResetButton.MouseButton1Click:Connect(function()

	cookingPotStatusLabel.Text =
		"รีเซ็ตแล้ว สามารถตรวจ Item เดิมอีกครั้ง"

	cookingPotStatusLabel.TextColor3 =
		Color3.fromRGB(230, 170, 80)
end)
--==================================================
-- Events Graphics
--==================================================

graphicsToggleButton.MouseButton1Click:Connect(function()
	toggleGraphicsMode(not GraphicsConfig.Enabled)
	updateGraphicsUI()
end)

applyGraphicsButton.MouseButton1Click:Connect(function()
	enableGraphicsMode()
	updateGraphicsUI()

	graphicsStatusLabel.Text =
		"ใช้ค่ากราฟิกเรียบร้อยแล้ว"
end)

--==================================================
-- Events หลัก
--==================================================

headTabButton.MouseButton1Click:Connect(function()
	openTab("Head")
end)

pizzaTabButton.MouseButton1Click:Connect(function()
	openTab("Pizza")
end)

cookingPotTabButton.MouseButton1Click:Connect(function()
	openTab("CookingPot")
end)

graphicsTabButton.MouseButton1Click:Connect(function()
	openTab("Graphics")
end)

minimizeButton.MouseButton1Click:Connect(function()
	dropdownList.Visible = false

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
	disableAutoPizza()
	disableAutoCookingPot()

	if GraphicsConfig.Enabled then
		disableGraphicsMode()
	end

	screenGui:Destroy()
end)

--==================================================
-- ระบบลาก GUI
--==================================================

local function makeDraggable(guiObject, dragHandle)
	local dragging = false
	local dragStart
	local startPosition
	local currentDragInput

	dragHandle.InputBegan:Connect(function(input)
		if input.UserInputType
				== Enum.UserInputType.MouseButton1
			or input.UserInputType
				== Enum.UserInputType.Touch then

			dragging = true
			dragStart = input.Position
			startPosition = guiObject.Position

			input.Changed:Connect(function()
				if input.UserInputState
					== Enum.UserInputState.End then

					dragging = false
				end
			end)
		end
	end)

	dragHandle.InputChanged:Connect(function(input)
		if input.UserInputType
				== Enum.UserInputType.MouseMovement
			or input.UserInputType
				== Enum.UserInputType.Touch then

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
-- เริ่มต้น
--==================================================

updateHeadSelectionUI()
updatePizzaUI()
updateCookingPotUI()
openTab("Head")
