local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

if not RunService:IsClient() then
	warn("ObjectFinder ต้องรันจาก LocalScript ฝั่ง Client")
	return
end

local player = Players.LocalPlayer

if not player then
	warn("ไม่พบ LocalPlayer กรุณาวางสคริปต์ใน StarterPlayerScripts")
	return
end

local playerGui = player:WaitForChild("PlayerGui")

local function removeSellGui()
	for _, object in ipairs(playerGui:GetDescendants()) do
		if object.Name == "Sell" then
			object:Destroy()
		end
	end
end

removeSellGui()

playerGui.DescendantAdded:Connect(function(object)
	if object.Name == "Sell" then
		task.defer(function()
			if object and object.Parent then
				object:Destroy()
			end
		end)
	end
end)


local CONFIG = {
	SearchInterval = 0.25,
	RuneKeyword = "rune",
	AboveDistance = 0,
	AutoEInterval = 0.01,
	AutoEHoldTime = 0.01,
	AutoClickInterval = 0.01,

	-- การเคลื่อนที่ของ Finder ทุกโหมด
	FinderFlySpeed = 150,
	FinderFlyStopDistance = 1.5,

	-- ระยะเหนือ Boulder
	BoulderAboveDistance = 0,

	-- ปิด Boulder Finder เมื่อค้นหาไม่เจอติดต่อกัน
	BoulderMaxMisses = 3,

	-- Auto Sell Navigation
	SellPosition = Vector3.new(-49.969, 29.178, 1067.431),
	SellFlySpeed = 130,
	SellStopDistance = 2,
	SellCheckInterval = 0.25,

	-- Delay ระบบขาย
	SellArrivalDelay = 1.0,
	SellConfirmDelay = 1.0,
	SellReturnDelay = 1.0,
	SellOptionKey = 1,
	SellOptionPressDelay = 1.0,
	-- จำนวนรอบกดเลข 1 (ตั้งเป็น 3 หรือ 4 ได้)
	SellOptionPressCount = 4, 
	SellOptionPressInterval = 0.15,
}


local state = {
	runeEnabled = false,
	boulderEnabled = false,
	crystalEnabled = false,
	crystalPriceEnabled = false,

	autoSellEnabled = false,
	sellActive = false,
	sellReturning = false,
	sellWaitingForSale = false,
	sellArrivalStartedAt = nil,
	sellCompletedAt = nil,
	sellPromptTriggered = false,
	sellPromptTriggeredAt = nil,
	sellOptionPressed = false,
	sellOptionPressCurrent = 0,
	sellAutoEAllowed = false,
	sellAutoEWasRunning = false,
	sellStartedWithFly = false,
	sellStartCFrame = nil,
	lastSellCheck = 0,

	minimumLuck = 20,
	minimumPrice = 10_000_000,

	-- เลือกได้ทีละแบบ: วาป หรือ บินไป
	teleportToTargetEnabled = true,
	flyToTargetEnabled = false,

	boulderMissCount = 0,
	hoverCFrame = nil,

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

-- BodyVelocity / BodyGyro Fly Stabilizer

local utilityState

local flyVelocity = nil
local flyGyro = nil
local flyConnection = nil

local function stopFly()
	if flyConnection then
		flyConnection:Disconnect()
		flyConnection = nil
	end

	if flyVelocity then
		flyVelocity:Destroy()
		flyVelocity = nil
	end

	if flyGyro then
		flyGyro:Destroy()
		flyGyro = nil
	end

	local _, humanoid, rootPart = getCharacter()

	if humanoid then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
		humanoid:ChangeState(
			Enum.HumanoidStateType.GettingUp
		)
	end

	if rootPart then
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end
end

local function startFly()
	if state.closed then
		return
	end

	stopFly()

	local _, humanoid, rootPart = getCharacter()

	if not rootPart or not humanoid then
		return
	end

	humanoid.PlatformStand = true
	humanoid.AutoRotate = false

	flyVelocity = Instance.new("BodyVelocity")
	flyVelocity.Name = "ObjectFinderFlyVelocity"
	flyVelocity.MaxForce = Vector3.new(
		math.huge,
		math.huge,
		math.huge
	)
	flyVelocity.P = 10000
	flyVelocity.Velocity = Vector3.zero
	flyVelocity.Parent = rootPart

	flyGyro = Instance.new("BodyGyro")
	flyGyro.Name = "ObjectFinderFlyGyro"
	flyGyro.MaxTorque = Vector3.new(
		math.huge,
		math.huge,
		math.huge
	)
	flyGyro.P = 10000
	flyGyro.D = 100
	flyGyro.CFrame = rootPart.CFrame
	flyGyro.Parent = rootPart

	flyConnection = RunService.RenderStepped:Connect(function()
		if state.closed
			or not utilityState.active then

			return
		end

		local _, currentHumanoid, currentRoot =
			getCharacter()

		if not currentRoot or not currentHumanoid then
			stopFly()
			return
		end

		if not flyVelocity
			or not flyVelocity.Parent
			or not flyGyro
			or not flyGyro.Parent then

			return
		end

		currentHumanoid.PlatformStand = true
		currentHumanoid.AutoRotate = false

		-- BodyVelocity เป็นตัวพยุงไม่ให้ตก
		flyVelocity.Velocity = Vector3.zero

		local lookVector =
			currentRoot.CFrame.LookVector

		local flatLook = Vector3.new(
			lookVector.X,
			0,
			lookVector.Z
		)

		if flatLook.Magnitude > 0.001 then
			flyGyro.CFrame = CFrame.lookAt(
				currentRoot.Position,
				currentRoot.Position
					+ flatLook.Unit,
				Vector3.yAxis
			)
		end

		currentRoot.AssemblyLinearVelocity =
			Vector3.zero

		currentRoot.AssemblyAngularVelocity =
			Vector3.zero
	end)
end

-- Utility state: เปิดอัตโนมัติเมื่อ Finder อย่างน้อยหนึ่งโหมดเป็น ON
utilityState = {
	active = false,
	originalCollisions = {},
	originalPrompts = {},
	originalPlatformStand = nil,
}

local function hasFinderModeEnabled()
	return state.runeEnabled
		or state.boulderEnabled
		or state.crystalEnabled
		or state.crystalPriceEnabled
end

local function hasAnyFinderEnabled()
	return hasFinderModeEnabled()
		or state.sellActive
		or state.sellWaitingForSale
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

	startFly()
end

local function disableUtilities()
	if not utilityState.active then
		stopFly()
		return
	end

	utilityState.active = false
	stopFly()

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
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
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

local function getObjectBehindPosition(object, distance)
	if not object then
		return nil
	end

	distance = distance or 4

	local pivotCFrame = nil
	local sizeY = 0

	if object:IsA("BasePart") then
		pivotCFrame = object.CFrame
		sizeY = object.Size.Y
	elseif object:IsA("Model") then
		local success, result = pcall(function()
			return object:GetPivot()
		end)

		if success then
			pivotCFrame = result
		end

		local boxSuccess, _, boxSize = pcall(function()
			local cf, size = object:GetBoundingBox()
			return cf, size
		end)

		if boxSuccess and boxSize then
			sizeY = boxSize.Y
		end
	else
		local firstPart =
			object:FindFirstChildWhichIsA("BasePart", true)

		if firstPart then
			pivotCFrame = firstPart.CFrame
			sizeY = firstPart.Size.Y
		end
	end

	if not pivotCFrame then
		return getObjectTopPosition(object)
	end

	local behindPosition =
		pivotCFrame.Position
		- pivotCFrame.LookVector * distance

	return behindPosition
		+ Vector3.new(0, math.max(2, sizeY * 0.15), 0)
end

local function getUprightCFrame(position, lookDirection)
	local flatDirection = Vector3.new(
		lookDirection and lookDirection.X or 0,
		0,
		lookDirection and lookDirection.Z or -1
	)

	if flatDirection.Magnitude < 0.001 then
		flatDirection = Vector3.new(0, 0, -1)
	else
		flatDirection = flatDirection.Unit
	end

	return CFrame.lookAt(
		position,
		position + flatDirection,
		Vector3.yAxis
	)
end

local function holdCharacterPosition(rootPart)
	if not rootPart then
		return
	end

	if not state.hoverCFrame then
		local currentPosition = rootPart.Position

		state.hoverCFrame = getUprightCFrame(
			Vector3.new(
				currentPosition.X,
				currentPosition.Y,
				currentPosition.Z
			),
			rootPart.CFrame.LookVector
		)
	end

	rootPart.CFrame = state.hoverCFrame
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
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

	local nearestCrystal = nil
	local nearestLuck = nil
	local nearestDistance = math.huge

	for _, crystal in ipairs(crystalsFolder:GetChildren()) do
		local luck = getCrystalLuck(crystal)
		local position = getObjectTopPosition(crystal)

		if luck
			and position
			and luck >= minimumLuck then

			local distance = (position - origin).Magnitude

			if distance < nearestDistance then
				nearestCrystal = crystal
				nearestLuck = luck
				nearestDistance = distance
			end
		end
	end

	return nearestCrystal, nearestLuck
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

	local nearestCrystal = nil
	local nearestPrice = nil
	local nearestDistance = math.huge

	for _, crystal in ipairs(crystalsFolder:GetChildren()) do
		local price = getCrystalPrice(crystal)
		local position = getObjectTopPosition(crystal)

		if price
			and position
			and price >= minimumPrice then

			local distance = (position - origin).Magnitude

			if distance < nearestDistance then
				nearestCrystal = crystal
				nearestPrice = price
				nearestDistance = distance
			end
		end
	end

	return nearestCrystal, nearestPrice
end

-- Mode controls

local function disableAllModes()
	state.runeEnabled = false
	state.boulderEnabled = false
	state.crystalEnabled = false
	state.crystalPriceEnabled = false
	state.autoSellEnabled = false
	state.sellActive = false
	state.sellReturning = false
	state.sellWaitingForSale = false
	state.sellArrivalStartedAt = nil
	state.sellCompletedAt = nil
	state.sellPromptTriggered = false
	state.sellPromptTriggeredAt = nil
	state.sellOptionPressed = false
	state.sellOptionPressCurrent = 0
	state.sellAutoEAllowed = false
	state.sellAutoEWasRunning = false
	state.sellStartedWithFly = false
	state.sellStartCFrame = nil
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
	state.boulderMissCount = 0

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

local function registerBoulderSearchResult(foundTarget)
	if foundTarget then
		state.boulderMissCount = 0
		return false
	end

	state.boulderMissCount += 1

	if state.boulderMissCount < CONFIG.BoulderMaxMisses then
		return false
	end

	state.boulderMissCount = 0
	setBoulderEnabled(false)

	return true
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



-- Keyboard auto click
-- รองรับเลข 0-9 เช่น autoclick(1)

local numberKeyMap = {
	[0] = Enum.KeyCode.Zero,
	[1] = Enum.KeyCode.One,
	[2] = Enum.KeyCode.Two,
	[3] = Enum.KeyCode.Three,
	[4] = Enum.KeyCode.Four,
	[5] = Enum.KeyCode.Five,
	[6] = Enum.KeyCode.Six,
	[7] = Enum.KeyCode.Seven,
	[8] = Enum.KeyCode.Eight,
	[9] = Enum.KeyCode.Nine,
}

local virtualKeyMap = {
	[0] = 0x30,
	[1] = 0x31,
	[2] = 0x32,
	[3] = 0x33,
	[4] = 0x34,
	[5] = 0x35,
	[6] = 0x36,
	[7] = 0x37,
	[8] = 0x38,
	[9] = 0x39,
}

local function autoclick(btn)
	btn = tonumber(btn)

	local keyCode = numberKeyMap[btn]
	local virtualKey = virtualKeyMap[btn]

	if not keyCode or not virtualKey then
		warn("autoclick: รองรับเฉพาะเลข 0-9")
		return false
	end

	local success, errorMessage = pcall(function()
		-- Executor บางตัวรองรับ keypress/keyrelease และกด Hotbar ได้ตรงกว่า
		if typeof(keypress) == "function"
			and typeof(keyrelease) == "function" then

			keypress(virtualKey)
			task.wait(0.05)
			keyrelease(virtualKey)
			return
		end

		-- Fallback สำหรับสภาพแวดล้อมที่รองรับ VirtualInputManager
		VirtualInputManager:SendKeyEvent(
			true,
			keyCode,
			false,
			game
		)

		task.wait(0.05)

		VirtualInputManager:SendKeyEvent(
			false,
			keyCode,
			false,
			game
		)
	end)

	if not success then
		warn("autoclick error:", errorMessage)
		return false
	end

	return true
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
	-- ระหว่างกระบวนการ Auto Sell ให้ Auto E ทำงานเฉพาะตอนถึงจุดขายแล้วเท่านั้น
	if state.sellActive or state.sellWaitingForSale then
		if state.sellAutoEAllowed then
			startAutoE()
		else
			stopAutoE()
		end
		return
	end

	if hasFinderModeEnabled() then
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
mainFrame.Size = UDim2.fromOffset(330, 570)
mainFrame.Position =
	UDim2.new(0, 30, 0.5, -285)
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

-- ปุ่มโหมดการเคลื่อนที่อยู่แถวบนสุด แบ่งครึ่งซ้าย/ขวา
local teleportModeButton =
	createToggleButton("Teleport: ON", 0)
teleportModeButton.Size = UDim2.new(0.5, -4, 0, 42)
teleportModeButton.Position = UDim2.fromOffset(0, 0)

local flyModeButton =
	createToggleButton("Fly: OFF", 0)
flyModeButton.Size = UDim2.new(0.5, -4, 0, 42)
flyModeButton.Position = UDim2.new(0.5, 4, 0, 0)

local runeButton =
	createToggleButton("Rune Finder: OFF", 49)

local boulderButton =
	createToggleButton("Boulders Finder: OFF", 98)

local crystalButton =
	createToggleButton("Crystal Luck Finder: OFF", 147)

local crystalPriceButton =
	createToggleButton("Crystal Price Finder: OFF", 196)

-- Auto Sell และ Sell Now อยู่แถวเดียวกัน
local autoSellButton =
	createToggleButton("Auto Sell: OFF", 245)
autoSellButton.Size = UDim2.new(0.5, -4, 0, 42)
autoSellButton.Position = UDim2.fromOffset(0, 245)

local sellNowButton =
	createToggleButton("Sell Now", 245)
sellNowButton.Size = UDim2.new(0.5, -4, 0, 42)
sellNowButton.Position = UDim2.new(0.5, 4, 0, 245)

local luckLabel = Instance.new("TextLabel")
luckLabel.Size = UDim2.fromOffset(120, 38)
luckLabel.Position = UDim2.fromOffset(0, 294)
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
	UDim2.fromOffset(130, 294)
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
priceLabel.Position = UDim2.fromOffset(0, 339)
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
	UDim2.fromOffset(130, 339)
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
	UDim2.fromOffset(0, 385)
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

-- Auto Sell Navigation helpers

local function getBagTextObject()
	-- โครงสร้างเป้าหมาย:
	-- Players > LocalPlayer > ExplorerHud > BackpackPanel > Value
	-- บางเกมอาจเก็บ ExplorerHud ไว้ใน PlayerGui จึงรองรับทั้งสองตำแหน่ง
	local explorerHud = player:FindFirstChild("ExplorerHud")

	if not explorerHud then
		explorerHud = playerGui:FindFirstChild("ExplorerHud", true)
	end

	if not explorerHud then
		return nil
	end

	local backpackPanel = explorerHud:FindFirstChild("BackpackPanel", true)

	if not backpackPanel then
		return nil
	end

	local valueObject = backpackPanel:FindFirstChild("Value", true)

	if valueObject
		and (
			valueObject:IsA("TextLabel")
			or valueObject:IsA("TextButton")
			or valueObject:IsA("TextBox")
		) then

		return valueObject
	end

	return nil
end

local function isBagFull()
	local valueObject = getBagTextObject()

	if not valueObject then
		return false
	end

	local normalized = tostring(valueObject.Text):upper()

	-- รองรับ FULL, FULL!, BAG FULL, 100/FULL และข้อความอื่นที่มีคำว่า FULL
	return string.find(normalized, "FULL", 1, true) ~= nil
end

local function beginSellNavigation()
	if state.sellActive or state.sellWaitingForSale then
		return
	end

	local _, _, rootPart = getCharacter()

	if not rootPart then
		return
	end

	state.sellStartedWithFly =
		utilityState.active
		or hasFinderModeEnabled()

	state.sellStartCFrame = rootPart.CFrame
	state.sellActive = true
	state.sellReturning = false
	state.sellWaitingForSale = false
	state.sellArrivalStartedAt = nil
	state.sellCompletedAt = nil
	state.sellPromptTriggered = false
	state.sellPromptTriggeredAt = nil
	state.sellOptionPressed = false
	state.sellOptionPressCurrent = 0
	state.sellAutoEAllowed = false

	-- จำสถานะ Auto E ก่อนเริ่มขาย เพื่อเปิดกลับเมื่อกลับถึงจุดเดิม
	state.sellAutoEWasRunning =
		autoEState.running
		or hasFinderModeEnabled()

	-- ทั้ง Auto Sell และปุ่ม Sell Now จะปิด Auto E ระหว่างเดินทาง
	stopAutoE()

	state.hoverCFrame = getUprightCFrame(
		rootPart.Position,
		rootPart.CFrame.LookVector
	)
	clearTarget()
	updateUtilities()
end


local function cancelSellNavigation(reason)
	if not state.sellActive and not state.sellWaitingForSale then
		return false
	end

	-- ปิด Auto Sell เพื่อป้องกันเริ่มขายซ้ำทันที หากกระเป๋ายัง FULL
	state.autoSellEnabled = false

	local _, _, rootPart = getCharacter()

	-- กลับไปยังตำแหน่งก่อนเริ่มขายทันที
	if rootPart and state.sellStartCFrame then
		rootPart.CFrame = state.sellStartCFrame
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end

	state.sellActive = false
	state.sellReturning = false
	state.sellWaitingForSale = false
	state.sellArrivalStartedAt = nil
	state.sellCompletedAt = nil
	state.sellPromptTriggered = false
	state.sellPromptTriggeredAt = nil
	state.sellOptionPressed = false
	state.sellOptionPressCurrent = 0
	state.sellAutoEAllowed = false

	local shouldRestoreAutoE =
		state.sellAutoEWasRunning
		or hasFinderModeEnabled()

	local shouldKeepFly =
		state.sellStartedWithFly
		or hasFinderModeEnabled()

	state.sellAutoEWasRunning = false
	state.sellStartedWithFly = false
	state.sellStartCFrame = nil

	if rootPart then
		state.hoverCFrame = rootPart.CFrame
	else
		state.hoverCFrame = nil
	end

	if shouldKeepFly then
		updateUtilities()
	else
		disableUtilities()
		stopFly()
		state.hoverCFrame = nil
	end

	if shouldRestoreAutoE then
		startAutoE()
	else
		updateAutoE()
	end

	if statusLabel then
		statusLabel.Text =
			"Status: ยกเลิกการขายแล้ว"
			.. (reason and (" (" .. tostring(reason) .. ")") or "")
	end

	return true
end


-- GUI update functions

-- สีประจำปุ่ม: OFF เป็นสีเข้ม และ ON เป็นสีสว่าง
local BUTTON_COLORS = {
	TeleportOn = Color3.fromRGB(35, 125, 205),
	TeleportOff = Color3.fromRGB(42, 61, 78),
	FlyOn = Color3.fromRGB(125, 75, 205),
	FlyOff = Color3.fromRGB(58, 46, 78),

	RuneOn = Color3.fromRGB(145, 70, 205),
	RuneOff = Color3.fromRGB(65, 46, 78),
	BoulderOn = Color3.fromRGB(205, 115, 45),
	BoulderOff = Color3.fromRGB(78, 58, 42),
	CrystalLuckOn = Color3.fromRGB(35, 155, 165),
	CrystalLuckOff = Color3.fromRGB(40, 70, 73),
	CrystalPriceOn = Color3.fromRGB(190, 145, 35),
	CrystalPriceOff = Color3.fromRGB(78, 68, 40),

	AutoSellOn = Color3.fromRGB(45, 150, 80),
	AutoSellOff = Color3.fromRGB(43, 73, 55),
	SellReady = Color3.fromRGB(185, 75, 55),
	SellBusy = Color3.fromRGB(205, 135, 45),
}

local function updateButtons()
	if state.runeEnabled then
		runeButton.Text = "Rune Finder: ON"
		runeButton.BackgroundColor3 =
			BUTTON_COLORS.RuneOn
	else
		runeButton.Text = "Rune Finder: OFF"
		runeButton.BackgroundColor3 =
			BUTTON_COLORS.RuneOff
	end

	if state.boulderEnabled then
		boulderButton.Text =
			"Boulders Finder: ON"
		boulderButton.BackgroundColor3 =
			BUTTON_COLORS.BoulderOn
	else
		boulderButton.Text =
			"Boulders Finder: OFF"
		boulderButton.BackgroundColor3 =
			BUTTON_COLORS.BoulderOff
	end

	if state.crystalEnabled then
		crystalButton.Text =
			"Crystal Luck: ON (≥ "
			.. tostring(state.minimumLuck)
			.. "%)"

		crystalButton.BackgroundColor3 =
			BUTTON_COLORS.CrystalLuckOn
	else
		crystalButton.Text =
			"Crystal Luck Finder: OFF"
		crystalButton.BackgroundColor3 =
			BUTTON_COLORS.CrystalLuckOff
	end

	if state.crystalPriceEnabled then
		crystalPriceButton.Text =
			"Crystal Price: ON (≥ "
			.. tostring(state.minimumPrice)
			.. ")"

		crystalPriceButton.BackgroundColor3 =
			BUTTON_COLORS.CrystalPriceOn
	else
		crystalPriceButton.Text =
			"Crystal Price Finder: OFF"
		crystalPriceButton.BackgroundColor3 =
			BUTTON_COLORS.CrystalPriceOff
	end

	teleportModeButton.Text = state.teleportToTargetEnabled
		and "Teleport: ON"
		or "Teleport: OFF"
	teleportModeButton.BackgroundColor3 = state.teleportToTargetEnabled
		and BUTTON_COLORS.TeleportOn
		or BUTTON_COLORS.TeleportOff

	flyModeButton.Text = state.flyToTargetEnabled
		and "Fly: ON"
		or "Fly: OFF"
	flyModeButton.BackgroundColor3 = state.flyToTargetEnabled
		and BUTTON_COLORS.FlyOn
		or BUTTON_COLORS.FlyOff

	if state.sellActive or state.sellWaitingForSale then
		autoSellButton.Text = "Cancel Auto Sell"
		autoSellButton.BackgroundColor3 =
			BUTTON_COLORS.SellBusy
	else
		if state.autoSellEnabled then
			autoSellButton.Text = "Auto Sell: ON"
			autoSellButton.BackgroundColor3 =
				BUTTON_COLORS.AutoSellOn
		else
			autoSellButton.Text = "Auto Sell: OFF"
			autoSellButton.BackgroundColor3 =
				BUTTON_COLORS.AutoSellOff
		end
	end

	if state.sellActive or state.sellWaitingForSale then
		sellNowButton.Text = "Cancel Sell"
		sellNowButton.BackgroundColor3 =
			BUTTON_COLORS.SellBusy
	else
		sellNowButton.Text = "Sell Now"
		sellNowButton.BackgroundColor3 =
			BUTTON_COLORS.SellReady
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

teleportModeButton.MouseButton1Click:Connect(function()
	state.teleportToTargetEnabled = not state.teleportToTargetEnabled

	if state.teleportToTargetEnabled then
		state.flyToTargetEnabled = false
	elseif not state.flyToTargetEnabled then
		state.flyToTargetEnabled = true
	end

	state.hoverCFrame = nil
	updateButtons()
end)

flyModeButton.MouseButton1Click:Connect(function()
	state.flyToTargetEnabled = not state.flyToTargetEnabled

	if state.flyToTargetEnabled then
		state.teleportToTargetEnabled = false
	elseif not state.teleportToTargetEnabled then
		state.teleportToTargetEnabled = true
	end

	state.hoverCFrame = nil
	updateButtons()
end)

autoSellButton.MouseButton1Click:Connect(function()
	if state.sellActive or state.sellWaitingForSale then
		cancelSellNavigation("Auto Sell")
		updateButtons()
		return
	end

	state.autoSellEnabled =
		not state.autoSellEnabled

	updateButtons()

	statusLabel.Text =
		state.autoSellEnabled
		and "Status: Auto Sell รอกระเป๋า FULL!"
		or "Status: Auto Sell ปิดแล้ว"
end)

sellNowButton.MouseButton1Click:Connect(function()
	if state.sellActive or state.sellWaitingForSale then
		cancelSellNavigation("Sell Now")
		updateButtons()
		return
	end

	beginSellNavigation()
	updateButtons()
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
	stopFly()
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
		startFly()
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
		humanoid.AutoRotate = false
	end

	if rootPart
		and (
			not flyVelocity
			or not flyVelocity.Parent
			or not flyGyro
			or not flyGyro.Parent
		) then

		startFly()
	end

	if rootPart then
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero

		if hasAnyFinderEnabled()
			and not state.currentTarget
			and not state.sellActive then

			holdCharacterPosition(rootPart)
		end
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

RunService.Heartbeat:Connect(function(deltaTime)
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

	-- ตรวจ Auto Sell
	if state.autoSellEnabled
		and not state.sellActive
		and not state.sellWaitingForSale then

		local now = os.clock()

		if now - state.lastSellCheck
			>= CONFIG.SellCheckInterval then

			state.lastSellCheck = now

			if isBagFull() then
				beginSellNavigation()
				updateButtons()
			end
		end
	end

	-- เมื่อถึงจุดขาย รอ 1 วินาที แล้วใช้ Auto E เดิม
	-- หลังจากนั้นรอให้ FULL! หาย แล้วกลับจุดเดิม
	if state.sellWaitingForSale then
		holdCharacterPosition(rootPart)

		local now = os.clock()
		local arrivalElapsed =
			state.sellArrivalStartedAt
			and (now - state.sellArrivalStartedAt)
			or 0

		if arrivalElapsed < CONFIG.SellArrivalDelay then
			statusLabel.Text =
				"Status: ถึงจุดขายแล้ว รอ Auto E "
				.. string.format(
					"%.1f",
					CONFIG.SellArrivalDelay
						- arrivalElapsed
				)
				.. " วินาที"

			return
		end

		if not state.sellPromptTriggered then
			state.sellPromptTriggered = true
			state.sellPromptTriggeredAt = now
			state.sellAutoEAllowed = true
			updateAutoE()

			task.spawn(function()
				local prompt = getActiveEPrompt()

				if prompt then
					activateEPrompt(prompt)
				else
					warn("Auto Sell: ไม่พบ ProximityPrompt ปุ่ม E")
				end

				-- กด E เสร็จแล้วปิด Auto E เพื่อไม่ให้กดซ้ำระหว่างเลือกเมนูขาย
				state.sellAutoEAllowed = false
				updateAutoE()

				task.wait(CONFIG.SellOptionPressDelay)

				if state.sellWaitingForSale
					and not state.sellOptionPressed then

					state.sellOptionPressed = true
					state.sellOptionPressCurrent = 0

					for pressIndex = 1, CONFIG.SellOptionPressCount do
						if not state.sellWaitingForSale then
							break
						end

						state.sellOptionPressCurrent = pressIndex
						statusLabel.Text =
							"Status: รอกดตัวเลข | Auto "
							.. tostring(CONFIG.SellOptionKey)
							.. " รอบ "
							.. tostring(pressIndex)
							.. "/"
							.. tostring(CONFIG.SellOptionPressCount)

						autoclick(CONFIG.SellOptionKey)

						if pressIndex < CONFIG.SellOptionPressCount then
							task.wait(CONFIG.SellOptionPressInterval)
						end
					end
				end
			end)

			statusLabel.Text = "Status: เปิด Auto E ที่จุดขาย"
			return
		end

		local promptElapsed =
			state.sellPromptTriggeredAt
			and (now - state.sellPromptTriggeredAt)
			or 0

		if promptElapsed < CONFIG.SellConfirmDelay then
			statusLabel.Text =
				"Status: Auto E แล้ว รอ "
				.. string.format(
					"%.1f",
					CONFIG.SellConfirmDelay
						- promptElapsed
				)
				.. " วินาที"

			return
		end

		statusLabel.Text =
			state.sellOptionPressed
			and "Status: กดตัวเลือกขายเลข "
				.. tostring(CONFIG.SellOptionKey)
			or "Status: รอกดตัวเลือกขาย"

		if not isBagFull() then
			if not state.sellCompletedAt then
				state.sellCompletedAt = now
			end

			local completedElapsed =
				now - state.sellCompletedAt

			if completedElapsed
				>= CONFIG.SellReturnDelay then

				state.sellWaitingForSale = false
				state.sellActive = true
				state.sellReturning = true
				updateButtons()
			else
				statusLabel.Text =
					"Status: ขายสำเร็จ กำลังกลับใน "
					.. string.format(
						"%.1f",
						CONFIG.SellReturnDelay
							- completedElapsed
					)
					.. " วินาที"
			end
		else
			state.sellCompletedAt = nil
		end

		return
	end

	-- ให้ Sell Navigation มีลำดับความสำคัญสูงสุด
	if state.sellActive then
		local destination

		if state.sellReturning
			and state.sellStartCFrame then

			destination = state.sellStartCFrame.Position
		else
			destination = CONFIG.SellPosition
		end

		local offset =
			destination - rootPart.Position

		local distance = offset.Magnitude

		if distance > CONFIG.SellStopDistance then
			local moveDistance = math.min(
				distance,
				CONFIG.SellFlySpeed * deltaTime
			)

			local nextPosition =
				rootPart.Position
				+ offset.Unit * moveDistance

			rootPart.CFrame = getUprightCFrame(
				nextPosition,
				offset
			)

			state.hoverCFrame = rootPart.CFrame

			statusLabel.Text =
				state.sellReturning
				and (
					"Status: กำลังกลับจุดเดิม | "
					.. string.format("%.1f", distance)
				)
				or (
					"Status: กำลังไปจุดขาย | "
					.. string.format("%.1f", distance)
				)
		else
			if state.sellReturning then
				rootPart.CFrame =
					state.sellStartCFrame

				state.sellActive = false
				state.sellReturning = false
				state.sellWaitingForSale = false
				state.sellArrivalStartedAt = nil
				state.sellCompletedAt = nil
				state.sellPromptTriggered = false
				state.sellPromptTriggeredAt = nil
				state.sellOptionPressed = false
				state.sellOptionPressCurrent = 0
				state.sellAutoEAllowed = false

				-- เปิด Auto E กลับตามสถานะก่อนกด Sell Now/ก่อน Auto Sell เริ่ม
				local shouldRestoreAutoE =
					state.sellAutoEWasRunning
					or hasFinderModeEnabled()

				state.sellAutoEWasRunning = false

				if shouldRestoreAutoE then
					startAutoE()
				else
					updateAutoE()
				end

				state.hoverCFrame = rootPart.CFrame
				state.sellStartCFrame = nil

				local shouldKeepFly =
					state.sellStartedWithFly
					or hasFinderModeEnabled()

				state.sellStartedWithFly = false

				if shouldKeepFly then
					updateUtilities()
				else
					disableUtilities()
					stopFly()
					state.hoverCFrame = nil
				end

				statusLabel.Text =
					shouldKeepFly
					and "Status: ขายสำเร็จ กลับจุดเดิม และคง Fly ไว้"
					or "Status: ขายสำเร็จ กลับจุดเดิม และปิด Fly แล้ว"
			else
				rootPart.CFrame = getUprightCFrame(
					CONFIG.SellPosition,
					rootPart.CFrame.LookVector
				)

				state.hoverCFrame = rootPart.CFrame
				state.sellActive = false
				state.sellWaitingForSale = true
				state.sellArrivalStartedAt = os.clock()
				state.sellCompletedAt = nil
				state.sellPromptTriggered = false
				state.sellPromptTriggeredAt = nil
				state.sellOptionPressed = false
				state.sellOptionPressCurrent = 0
				state.sellAutoEAllowed = false
				updateAutoE()

				statusLabel.Text =
					"Status: ถึงจุดขายแล้ว กำลังรอเปิด Auto E"
			end

			updateButtons()
		end

		rootPart.AssemblyLinearVelocity =
			Vector3.zero

		rootPart.AssemblyAngularVelocity =
			Vector3.zero

		return
	end

	if countEnabledModes() == 0 then
		statusLabel.Text = "Status: Ready"
		state.hoverCFrame = nil
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

			if nextMode == "Boulder" then
				local autoDisabled =
					registerBoulderSearchResult(target)

				if autoDisabled then
					updateButtons()
					updateUtilities()
					updateAutoE()
					updateAutoClick()

					statusLabel.Text =
						"Status: ไม่พบ Boulder ครบ "
						.. tostring(CONFIG.BoulderMaxMisses)
						.. " ครั้ง\nBoulders Finder: OFF"

					clearTarget()
					break
				end
			end

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

	if not state.currentTarget
		and countEnabledModes() == 0 then

		return
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

		holdCharacterPosition(rootPart)
		return
	end

	local targetPosition =
		getObjectTopPosition(state.currentTarget)

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

	statusLabel.Text ..= state.flyToTargetEnabled
		and "\nMovement: Fly"
		or "\nMovement: Teleport"

	local heightOffset = state.currentMode == "Boulder"
		and CONFIG.BoulderAboveDistance
		or CONFIG.AboveDistance

	local destination = targetPosition
		+ Vector3.new(0, heightOffset, 0)

	if state.flyToTargetEnabled then
		local offset = destination - rootPart.Position
		local distance = offset.Magnitude

		if distance > CONFIG.FinderFlyStopDistance then
			local moveDistance = math.min(
				distance,
				CONFIG.FinderFlySpeed * deltaTime
			)

			local nextPosition = rootPart.Position
				+ offset.Unit * moveDistance

			rootPart.CFrame = getUprightCFrame(
				nextPosition,
				offset
			)
		else
			rootPart.CFrame = getUprightCFrame(
				destination,
				rootPart.CFrame.LookVector
			)
		end
	else
		rootPart.CFrame = getUprightCFrame(
			destination,
			rootPart.CFrame.LookVector
		)
	end

	state.hoverCFrame = rootPart.CFrame

	if flyGyro and flyGyro.Parent then
		flyGyro.CFrame = rootPart.CFrame
	end

	rootPart.AssemblyLinearVelocity =
		Vector3.zero

	rootPart.AssemblyAngularVelocity =
		Vector3.zero
end)
