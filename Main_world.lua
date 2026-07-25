--==================================================
-- [1] SERVICES
--==================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")


--==================================================
-- [2] CONFIG
--==================================================

-- เปลี่ยนเป็น Asset ID โลโก้ของคุณ
local LOGO_ASSET_ID = "rbxassetid://1234567890"

local Config = {
	-- Walk Speed
	WalkSpeedEnabled = false,
	LockWalkSpeed = true,

	WalkSpeed = 50,
	NormalWalkSpeed = 16,

	MinWalkSpeed = 16,
	MaxWalkSpeed = 500,

	-- Infinite Jump
	InfiniteJump = false,

	-- Fly
	FlyEnabled = false,
	FlySpeed = 60,

	MinFlySpeed = 10,
	MaxFlySpeed = 500,

	-- Prompt
	InstantPrompt = false,
	
	-- Noclip
	NoclipEnabled = false,
	-- GUI
	ToggleKey = Enum.KeyCode.RightShift,
	
	-- Damage / Auto Attack
	AutoAttackEnabled = false,
	
	LockAttackRadius = true,
	AttackRadius = 25,
	LockedAttackRadius = 25,
	MinAttackRadius = 3,
	MaxAttackRadius = 50,

	AttackInterval = 0.35,
	MinAttackInterval = 0.05,
	MaxAttackInterval = 1,

	MaxAttackTargets = 20,
	OnlyNPC = true,
	-- Auto Click
	AutoClickEnabled = false,

	AutoClickInterval = 0.10,
	MinAutoClickInterval = 0.01,
	MaxAutoClickInterval = 1.00,

	AutoClickKey = Enum.KeyCode.G,
	
}


--==================================================
-- [3] STATE
--==================================================

local scriptClosed = false
local selectedPlayerName = nil

local connections = {}
local promptData = {}

local walkSpeedConnection = nil

local flyConnection = nil
local flyVelocity = nil
local flyGyro = nil

local savedPositions = {}
local nextPositionId = 0

local autoAttackConnection = nil
local lastAutoAttackTime = 0
local radiusLockConnection = nil

local autoClickConnection = nil
local lastAutoClickTime = 0

local Noclip = {
	Connection = nil,
	OriginalStates = {},
}
--==================================================
-- [4] CONNECTION MANAGER
--==================================================

local function addConnection(connection)
	table.insert(connections, connection)
	return connection
end

local function disconnectAllConnections()
	for _, connection in ipairs(connections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end

	table.clear(connections)
end


--==================================================
-- [5] CHARACTER HELPERS
--==================================================

local function getCharacter()
	return player.Character
end

local function getHumanoid()
	local character = getCharacter()

	if not character then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

local function getRootPart()
	local character = getCharacter()

	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

--==================================================
-- [5.1] NOCLIP
--==================================================

function Noclip:Apply()
	local character = getCharacter()

	if not character then
		return
	end

	for _, object in ipairs(character:GetDescendants()) do
		if object:IsA("BasePart") then
			if self.OriginalStates[object] == nil then
				self.OriginalStates[object] =
					object.CanCollide
			end

			object.CanCollide = false
		end
	end
end

function Noclip:Stop()
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end

	for part, originalCanCollide in pairs(self.OriginalStates) do
		if part and part.Parent then
			part.CanCollide = originalCanCollide
		end
	end

	table.clear(self.OriginalStates)
end

function Noclip:Start()
	if scriptClosed then
		return
	end

	self:Stop()

	Config.NoclipEnabled = true
	self:Apply()

	self.Connection = RunService.Stepped:Connect(function()
		if scriptClosed or not Config.NoclipEnabled then
			return
		end

		self:Apply()
	end)
end

function Noclip:SetEnabled(enabled)
	Config.NoclipEnabled = enabled

	if enabled then
		self:Start()
	else
		self:Stop()
	end
end

--==================================================
-- [6] WALK SPEED
--==================================================

local function disconnectWalkSpeedLock()
	if walkSpeedConnection then
		walkSpeedConnection:Disconnect()
		walkSpeedConnection = nil
	end
end

local function getTargetWalkSpeed()
	if Config.WalkSpeedEnabled then
		return Config.WalkSpeed
	end

	return Config.NormalWalkSpeed
end

local function applyWalkSpeed()
	if scriptClosed then
		return
	end

	local humanoid = getHumanoid()

	if humanoid then
		humanoid.WalkSpeed = getTargetWalkSpeed()
	end
end

local function setupWalkSpeedLock(character)
	if scriptClosed then
		return
	end

	local humanoid = character:WaitForChild("Humanoid")

	disconnectWalkSpeedLock()
	applyWalkSpeed()

	walkSpeedConnection =
		humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			if scriptClosed or not Config.LockWalkSpeed then
				return
			end

			local targetSpeed = getTargetWalkSpeed()

			if humanoid.WalkSpeed ~= targetSpeed then
				humanoid.WalkSpeed = targetSpeed
			end
		end)
end


--==================================================
-- [7] INFINITE JUMP
--==================================================

addConnection(UserInputService.JumpRequest:Connect(function()
	if scriptClosed or not Config.InfiniteJump then
		return
	end

	local humanoid = getHumanoid()

	if humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end))


--==================================================
-- [8] FLY
--==================================================

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

	local humanoid = getHumanoid()

	if humanoid then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
	end
end

local function startFly()
	if scriptClosed then
		return
	end

	stopFly()

	local rootPart = getRootPart()
	local humanoid = getHumanoid()

	if not rootPart or not humanoid then
		Config.FlyEnabled = false
		return
	end

	humanoid.PlatformStand = true
	humanoid.AutoRotate = false

	flyVelocity = Instance.new("BodyVelocity")
	flyVelocity.Name = "MenuFlyVelocity"
	flyVelocity.MaxForce = Vector3.new(
		math.huge,
		math.huge,
		math.huge
	)
	flyVelocity.P = 10000
	flyVelocity.Velocity = Vector3.zero
	flyVelocity.Parent = rootPart

	flyGyro = Instance.new("BodyGyro")
	flyGyro.Name = "MenuFlyGyro"
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
		if scriptClosed or not Config.FlyEnabled then
			return
		end

		rootPart = getRootPart()
		humanoid = getHumanoid()

		if not rootPart or not humanoid then
			stopFly()
			return
		end

		if not flyVelocity or not flyVelocity.Parent then
			return
		end

		if not flyGyro or not flyGyro.Parent then
			return
		end

		local camera = Workspace.CurrentCamera

		if not camera then
			return
		end

		local direction = Vector3.zero

		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			direction += camera.CFrame.LookVector
		end

		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			direction -= camera.CFrame.LookVector
		end

		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			direction -= camera.CFrame.RightVector
		end

		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			direction += camera.CFrame.RightVector
		end

		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			direction += Vector3.new(0, 1, 0)
		end

		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl) then

			direction -= Vector3.new(0, 1, 0)
		end

		if direction.Magnitude > 0 then
			direction = direction.Unit
		end

		flyVelocity.Velocity =
			direction * Config.FlySpeed

		local lookVector = camera.CFrame.LookVector

		local flatLook = Vector3.new(
			lookVector.X,
			0,
			lookVector.Z
		)

		if flatLook.Magnitude > 0.001 then
			flyGyro.CFrame = CFrame.lookAt(
				rootPart.Position,
				rootPart.Position + flatLook.Unit
			)
		end
	end)
end

local function setFlyEnabled(enabled)
	Config.FlyEnabled = enabled

	if enabled then
		-- เปิด Noclip พร้อม Fly
		Noclip:SetEnabled(true)

		startFly()
	else
		-- ปิด Fly ก่อน
		stopFly()

		-- ปิด Noclip พร้อม Fly
		Noclip:SetEnabled(false)
	end
end


--==================================================
-- [9] INSTANT PROXIMITY PROMPT
--==================================================

local function setupPrompt(prompt)
	if scriptClosed then
		return
	end

	if not prompt:IsA("ProximityPrompt") then
		return
	end

	if promptData[prompt] then
		return
	end

	local data = {
		OriginalDuration = prompt.HoldDuration,
		HoldConnection = nil,
		DestroyConnection = nil,
	}

	promptData[prompt] = data

	if Config.InstantPrompt then
		prompt.HoldDuration = 0
	end

	data.HoldConnection =
		prompt:GetPropertyChangedSignal("HoldDuration"):Connect(function()
			if scriptClosed then
				return
			end

			if Config.InstantPrompt
				and prompt.HoldDuration ~= 0 then

				prompt.HoldDuration = 0
			end
		end)

	data.DestroyConnection = prompt.Destroying:Connect(function()
		local currentData = promptData[prompt]

		if not currentData then
			return
		end

		if currentData.HoldConnection then
			currentData.HoldConnection:Disconnect()
		end

		if currentData.DestroyConnection then
			currentData.DestroyConnection:Disconnect()
		end

		promptData[prompt] = nil
	end)
end

local function scanPrompts()
	for _, object in ipairs(Workspace:GetDescendants()) do
		if object:IsA("ProximityPrompt") then
			setupPrompt(object)

			if Config.InstantPrompt then
				object.HoldDuration = 0
			end
		end
	end
end

local function setInstantPrompt(enabled)
	Config.InstantPrompt = enabled

	if enabled then
		scanPrompts()

		for prompt in pairs(promptData) do
			if prompt.Parent then
				prompt.HoldDuration = 0
			end
		end
	else
		for prompt, data in pairs(promptData) do
			if prompt.Parent then
				prompt.HoldDuration =
					data.OriginalDuration
			end
		end
	end
end

addConnection(Workspace.DescendantAdded:Connect(function(object)
	if scriptClosed then
		return
	end

	if object:IsA("ProximityPrompt") then
		setupPrompt(object)
	end
end))

scanPrompts()


--==================================================
-- [10] TELEPORT TO PLAYER
--==================================================

local function teleportToPlayer(targetPlayer)
	if not targetPlayer then
		return false, "ไม่พบผู้เล่นเป้าหมาย"
	end

	if targetPlayer == player then
		return false, "ไม่สามารถเลือกตัวเองได้"
	end

	local localRoot = getRootPart()

	local targetCharacter = targetPlayer.Character
	local targetRoot = targetCharacter
		and targetCharacter:FindFirstChild("HumanoidRootPart")

	if not localRoot then
		return false, "ไม่พบตัวละครของเรา"
	end

	if not targetRoot then
		return false, "ไม่พบตัวละครเป้าหมาย"
	end

	-- วาร์ปไปด้านหลังเป้าหมาย 4 studs
	localRoot.CFrame =
		targetRoot.CFrame * CFrame.new(0, 0, 4)

	return true,
		"Teleport ไปหา " .. targetPlayer.Name .. " แล้ว"
end

--==================================================
-- [10.1] TELEPORT TO SAVED POSITION
--==================================================

local function teleportToCFrame(targetCFrame)
	local rootPart = getRootPart()

	if not rootPart then
		return false, "ไม่พบตัวละครของเรา"
	end

	if typeof(targetCFrame) ~= "CFrame" then
		return false, "ข้อมูลตำแหน่งไม่ถูกต้อง"
	end

	-- ยกขึ้นเล็กน้อย ป้องกันติดพื้น
	rootPart.CFrame = targetCFrame * CFrame.new(0, 2, 0)
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero

	return true, "Teleport สำเร็จ"
end

--==================================================
-- [10.2] AUTO ATTACK / DAMAGE AREA
--==================================================

local function getEquippedTool()
	local character = getCharacter()

	if not character then
		return nil
	end

	return character:FindFirstChildOfClass("Tool")
end

local function isValidAttackTarget(model, humanoid)
	local character = getCharacter()

	if not model or not humanoid then
		return false
	end

	if model == character then
		return false
	end

	if humanoid.Health <= 0 then
		return false
	end

	if Config.OnlyNPC then
		local targetPlayer = Players:GetPlayerFromCharacter(model)

		if targetPlayer then
			return false
		end
	end

	return true
end

local function getNearbyAttackTargets()
	local character = getCharacter()
	local rootPart = getRootPart()

	if not character or not rootPart then
		return {}
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {
		character,
	}
	overlapParams.MaxParts = 250

	local nearbyParts = Workspace:GetPartBoundsInRadius(
		rootPart.Position,
		Config.AttackRadius,
		overlapParams
	)

	local targets = {}
	local foundHumanoids = {}

	for _, part in ipairs(nearbyParts) do
		local model = part:FindFirstAncestorOfClass("Model")

		local humanoid = model
			and model:FindFirstChildOfClass("Humanoid")

		if isValidAttackTarget(model, humanoid)
			and not foundHumanoids[humanoid] then

			foundHumanoids[humanoid] = true

			table.insert(targets, {
				Model = model,
				Humanoid = humanoid,
			})

			if #targets >= Config.MaxAttackTargets then
				break
			end
		end
	end

	return targets
end

local function performAutoAttack()
	if scriptClosed or not Config.AutoAttackEnabled then
		return
	end

	local tool = getEquippedTool()

	-- ทำงานเฉพาะตอนถืออาวุธหรือ Tool
	if not tool then
		return
	end

	local targets = getNearbyAttackTargets()

	if #targets == 0 then
		return
	end

	tool:Activate()
end

local function stopAutoAttack()
	Config.AutoAttackEnabled = false

	if autoAttackConnection then
		autoAttackConnection:Disconnect()
		autoAttackConnection = nil
	end
end

local function startAutoAttack()
	if autoAttackConnection then
		autoAttackConnection:Disconnect()
		autoAttackConnection = nil
	end

	Config.AutoAttackEnabled = true
	lastAutoAttackTime = 0

	autoAttackConnection = RunService.Heartbeat:Connect(function()
		if scriptClosed or not Config.AutoAttackEnabled then
			return
		end

		local currentTime = os.clock()

		if currentTime - lastAutoAttackTime
			< Config.AttackInterval then

			return
		end

		lastAutoAttackTime = currentTime

		performAutoAttack()
	end)
end

local function setAutoAttackEnabled(enabled)
	if enabled then
		startAutoAttack()
	else
		stopAutoAttack()
	end
end

local function stopRadiusLock()
	if radiusLockConnection then
		radiusLockConnection:Disconnect()
		radiusLockConnection = nil
	end
end

local function startRadiusLock()
	stopRadiusLock()

	Config.LockAttackRadius = true
	Config.LockedAttackRadius = Config.AttackRadius

	radiusLockConnection = RunService.Heartbeat:Connect(function()
		if scriptClosed or not Config.LockAttackRadius then
			return
		end

		if Config.AttackRadius ~= Config.LockedAttackRadius then
			Config.AttackRadius =
				Config.LockedAttackRadius
		end
	end)
end

local function setRadiusLockEnabled(enabled)
	Config.LockAttackRadius = enabled

	if enabled then
		Config.LockedAttackRadius = Config.AttackRadius
		startRadiusLock()
	else
		stopRadiusLock()
	end
end

--==================================================
-- [10.3] AUTO CLICK
--==================================================

local function performAutoClick()
	if scriptClosed or not Config.AutoClickEnabled then
		return
	end

	local tool = getEquippedTool()

	-- ทำงานเฉพาะตอนถือ Tool
	if not tool then
		return
	end

	tool:Activate()
end

local function stopAutoClick()
	Config.AutoClickEnabled = false

	if autoClickConnection then
		autoClickConnection:Disconnect()
		autoClickConnection = nil
	end
end

local function startAutoClick()
	if autoClickConnection then
		autoClickConnection:Disconnect()
		autoClickConnection = nil
	end

	Config.AutoClickEnabled = true
	lastAutoClickTime = 0

	autoClickConnection = RunService.Heartbeat:Connect(function()
		if scriptClosed or not Config.AutoClickEnabled then
			return
		end

		local currentTime = os.clock()

		if currentTime - lastAutoClickTime
			< Config.AutoClickInterval then

			return
		end

		lastAutoClickTime = currentTime
		performAutoClick()
	end)
end

local function setAutoClickEnabled(enabled)
	if enabled then
		startAutoClick()
	else
		stopAutoClick()
	end
end

local function toggleAutoClick()
	setAutoClickEnabled(
		not Config.AutoClickEnabled
	)
end

--==================================================
-- [11] REMOVE OLD GUI
--==================================================

local oldGui = playerGui:FindFirstChild("ExampleTabMenu")

if oldGui then
	oldGui:Destroy()
end


--==================================================
-- [12] GUI ROOT
--==================================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ExampleTabMenu"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.fromOffset(540, 440)
mainFrame.Position = UDim2.new(0.5, -270, 0.5, -220)
mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 31)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 12)
mainCorner.Parent = mainFrame

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(80, 80, 95)
mainStroke.Thickness = 1
mainStroke.Parent = mainFrame


--==================================================
-- [13] TITLE BAR
--==================================================

local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 48)
titleBar.BackgroundColor3 = Color3.fromRGB(36, 36, 44)
titleBar.BorderSizePixel = 0
titleBar.Active = true
titleBar.Parent = mainFrame

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 12)
titleCorner.Parent = titleBar

local titleBottomFix = Instance.new("Frame")
titleBottomFix.Size = UDim2.new(1, 0, 0, 12)
titleBottomFix.Position = UDim2.new(0, 0, 1, -12)
titleBottomFix.BackgroundColor3 = Color3.fromRGB(36, 36, 44)
titleBottomFix.BorderSizePixel = 0
titleBottomFix.Parent = titleBar

local titleLogo = Instance.new("ImageLabel")
titleLogo.Name = "TitleLogo"
titleLogo.Size = UDim2.fromOffset(34, 34)
titleLogo.Position = UDim2.fromOffset(9, 7)
titleLogo.BackgroundTransparency = 1
titleLogo.Image = LOGO_ASSET_ID
titleLogo.ScaleType = Enum.ScaleType.Fit
titleLogo.Parent = titleBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -150, 1, 0)
titleLabel.Position = UDim2.fromOffset(50, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Example Tab Menu"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextSize = 19
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

-- ปุ่มย่อ
local minimizeButton = Instance.new("TextButton")
minimizeButton.Name = "MinimizeButton"
minimizeButton.Size = UDim2.fromOffset(36, 30)
minimizeButton.Position = UDim2.new(1, -84, 0, 9)
minimizeButton.BackgroundColor3 = Color3.fromRGB(65, 65, 77)
minimizeButton.BorderSizePixel = 0
minimizeButton.Text = "—"
minimizeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
minimizeButton.TextSize = 20
minimizeButton.Font = Enum.Font.GothamBold
minimizeButton.Parent = titleBar

local minimizeCorner = Instance.new("UICorner")
minimizeCorner.CornerRadius = UDim.new(0, 7)
minimizeCorner.Parent = minimizeButton

-- ปุ่มปิดอยู่ขวาสุด
local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.Size = UDim2.fromOffset(36, 30)
closeButton.Position = UDim2.new(1, -43, 0, 9)
closeButton.BackgroundColor3 = Color3.fromRGB(190, 55, 60)
closeButton.BorderSizePixel = 0
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.TextSize = 15
closeButton.Font = Enum.Font.GothamBold
closeButton.Parent = titleBar

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 7)
closeCorner.Parent = closeButton


--==================================================
-- [14] SIDEBAR AND CONTENT AREA
--==================================================

local sidebar = Instance.new("Frame")
sidebar.Name = "Sidebar"
sidebar.Size = UDim2.fromOffset(130, 392)
sidebar.Position = UDim2.fromOffset(0, 48)
sidebar.BackgroundColor3 = Color3.fromRGB(31, 31, 38)
sidebar.BorderSizePixel = 0
sidebar.Parent = mainFrame

local contentFrame = Instance.new("Frame")
contentFrame.Name = "ContentFrame"
contentFrame.Size = UDim2.new(1, -130, 1, -48)
contentFrame.Position = UDim2.fromOffset(130, 48)
contentFrame.BackgroundTransparency = 1
contentFrame.ClipsDescendants = true
contentFrame.Parent = mainFrame


--==================================================
-- [15] TAB SYSTEM
--==================================================

local pages = {}
local tabButtons = {}

local function createTab(tabName, order)
	local tabButton = Instance.new("TextButton")
	tabButton.Name = tabName .. "TabButton"
	tabButton.Size = UDim2.new(1, -16, 0, 42)
	tabButton.Position = UDim2.fromOffset(
		8,
		10 + ((order - 1) * 50)
	)
	tabButton.BackgroundColor3 = Color3.fromRGB(56, 56, 68)
	tabButton.BorderSizePixel = 0
	tabButton.Text = tabName
	tabButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	tabButton.TextSize = 14
	tabButton.Font = Enum.Font.GothamBold
	tabButton.Parent = sidebar

	local tabCorner = Instance.new("UICorner")
	tabCorner.CornerRadius = UDim.new(0, 8)
	tabCorner.Parent = tabButton

	-- หน้า Scroll
	local page = Instance.new("ScrollingFrame")
	page.Name = tabName .. "Page"
	page.Size = UDim2.new(1, 0, 1, 0)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 5
	page.ScrollBarImageColor3 = Color3.fromRGB(110, 110, 125)
	page.ScrollingDirection = Enum.ScrollingDirection.Y
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.CanvasSize = UDim2.fromOffset(0, 0)
	page.Visible = false
	page.Parent = contentFrame

	-- Content ภายในหน้า Scroll
	local pageContent = Instance.new("Frame")
	pageContent.Name = "Content"
	pageContent.Size = UDim2.new(1, -8, 0, 0)
	pageContent.AutomaticSize = Enum.AutomaticSize.Y
	pageContent.BackgroundTransparency = 1
	pageContent.Parent = page

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.Padding = UDim.new(0, 10)
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Parent = pageContent

	local contentPadding = Instance.new("UIPadding")
	contentPadding.PaddingTop = UDim.new(0, 12)
	contentPadding.PaddingBottom = UDim.new(0, 18)
	contentPadding.PaddingLeft = UDim.new(0, 15)
	contentPadding.PaddingRight = UDim.new(0, 15)
	contentPadding.Parent = pageContent

	pages[tabName] = page
	tabButtons[tabName] = tabButton

	return page, tabButton, pageContent
end

local characterPage, characterTab, characterContent =
	createTab("Character", 1)

local worldPage, worldTab, worldContent =
	createTab("Teleport", 2)

local positionPage, positionTab, positionContent =
	createTab("Position", 3)

local damagePage, damageTab, damageContent =
	createTab("Auto Damage", 4)

local autoClickPage, autoClickTab, autoClickContent =
	createTab("Auto Click", 5)

local function showTab(tabName)
	for name, page in pairs(pages) do
		page.Visible = name == tabName
	end

	for name, button in pairs(tabButtons) do
		if name == tabName then
			button.BackgroundColor3 =
				Color3.fromRGB(55, 135, 220)
		else
			button.BackgroundColor3 =
				Color3.fromRGB(56, 56, 68)
		end
	end
end


--==================================================
-- [16] GUI HELPERS
--==================================================

local function createPageButton(parent, text, layoutOrder)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 0, 42)
	button.BackgroundColor3 = Color3.fromRGB(70, 70, 82)
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextSize = 15
	button.Font = Enum.Font.GothamBold
	button.LayoutOrder = layoutOrder
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	return button
end

local function setButtonState(button, label, enabled)
	if enabled then
		button.Text = label .. ": ON"
		button.BackgroundColor3 =
			Color3.fromRGB(40, 165, 90)
	else
		button.Text = label .. ": OFF"
		button.BackgroundColor3 =
			Color3.fromRGB(70, 70, 82)
	end
end

local function createSliderGroup(
	parent,
	labelText,
	layoutOrder
)
	local group = Instance.new("Frame")
	group.Size = UDim2.new(1, 0, 0, 58)
	group.BackgroundTransparency = 1
	group.LayoutOrder = layoutOrder
	group.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 25)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.TextColor3 = Color3.fromRGB(230, 230, 235)
	label.TextSize = 14
	label.Font = Enum.Font.GothamMedium
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = group

	local slider = Instance.new("Frame")
	slider.Size = UDim2.new(1, 0, 0, 12)
	slider.Position = UDim2.fromOffset(0, 37)
	slider.BackgroundColor3 = Color3.fromRGB(62, 62, 72)
	slider.BorderSizePixel = 0
	slider.Active = true
	slider.Parent = group

	local sliderCorner = Instance.new("UICorner")
	sliderCorner.CornerRadius = UDim.new(1, 0)
	sliderCorner.Parent = slider

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(55, 135, 220)
	fill.BorderSizePixel = 0
	fill.Parent = slider

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local knob = Instance.new("TextButton")
	knob.Size = UDim2.fromOffset(22, 22)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.new(0, 0, 0.5, 0)
	knob.BackgroundColor3 = Color3.fromRGB(245, 245, 250)
	knob.BorderSizePixel = 0
	knob.Text = ""
	knob.AutoButtonColor = false
	knob.Parent = slider

	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob

	return group, label, slider, fill, knob
end


--==================================================
-- [17] CHARACTER TAB GUI
--==================================================

local characterTitle = Instance.new("TextLabel")
characterTitle.Size = UDim2.new(1, 0, 0, 35)
characterTitle.BackgroundTransparency = 1
characterTitle.Text = "Character"
characterTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
characterTitle.TextSize = 20
characterTitle.Font = Enum.Font.GothamBold
characterTitle.TextXAlignment = Enum.TextXAlignment.Left
characterTitle.LayoutOrder = 1
characterTitle.Parent = characterContent

local walkSpeedButton = createPageButton(
	characterContent,
	"Walk Speed: OFF",
	2
)

local walkSpeedGroup,
	walkSpeedLabel,
	walkSlider,
	walkFill,
	walkKnob = createSliderGroup(
		characterContent,
		"Walk Speed: " .. Config.WalkSpeed,
		3
	)

local lockWalkSpeedButton = createPageButton(
	characterContent,
	"Lock Walk Speed: ON",
	4
)

local infiniteJumpButton = createPageButton(
	characterContent,
	"Infinite Jump: OFF",
	5
)

local instantPromptButton = createPageButton(
	characterContent,
	"Instant Prompt: OFF",
	6
)

Noclip.Button = createPageButton(
	characterContent,
	"Noclip: OFF",
	7
)
local flyButton = createPageButton(
	characterContent,
	"Fly: OFF",
	8
)

local flySpeedGroup,
	flySpeedLabel,
	flySlider,
	flyFill,
	flyKnob = createSliderGroup(
		characterContent,
		"Fly Speed: " .. Config.FlySpeed,
		9
	)

local flyInfoLabel = Instance.new("TextLabel")
flyInfoLabel.Size = UDim2.new(1, 0, 0, 65)
flyInfoLabel.BackgroundTransparency = 1
flyInfoLabel.Text =
	"Fly Controls\nW A S D = เคลื่อนที่\nSpace = ขึ้น | Ctrl = ลง"
flyInfoLabel.TextColor3 = Color3.fromRGB(165, 165, 175)
flyInfoLabel.TextSize = 13
flyInfoLabel.Font = Enum.Font.Gotham
flyInfoLabel.TextWrapped = true
flyInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
flyInfoLabel.LayoutOrder = 10
flyInfoLabel.Parent = characterContent


--==================================================
-- [18] CHARACTER GUI UPDATE
--==================================================

local function updateCharacterInterface()
	if scriptClosed then
		return
	end

	setButtonState(
		walkSpeedButton,
		"Walk Speed",
		Config.WalkSpeedEnabled
	)

	setButtonState(
		lockWalkSpeedButton,
		"Lock Walk Speed",
		Config.LockWalkSpeed
	)

	setButtonState(
		infiniteJumpButton,
		"Infinite Jump",
		Config.InfiniteJump
	)
	setButtonState(
		Noclip.Button,
		"Noclip",
		Config.NoclipEnabled
	)

	setButtonState(
		instantPromptButton,
		"Instant Prompt",
		Config.InstantPrompt
	)
	setButtonState(
		flyButton,
		"Fly",
		Config.FlyEnabled
	)


	walkSpeedLabel.Text =
		"Walk Speed: " .. tostring(Config.WalkSpeed)

	flySpeedLabel.Text =
		"Fly Speed: " .. tostring(Config.FlySpeed)
end


--==================================================
-- [19] SLIDER FUNCTIONS
--==================================================

local function updateSliderVisual(
	value,
	minValue,
	maxValue,
	fill,
	knob
)
	local percent = math.clamp(
		(value - minValue) / (maxValue - minValue),
		0,
		1
	)

	fill.Size = UDim2.fromScale(percent, 1)
	knob.Position = UDim2.new(percent, 0, 0.5, 0)
end

local function updateWalkSlider()
	updateSliderVisual(
		Config.WalkSpeed,
		Config.MinWalkSpeed,
		Config.MaxWalkSpeed,
		walkFill,
		walkKnob
	)
end

local function updateFlySlider()
	updateSliderVisual(
		Config.FlySpeed,
		Config.MinFlySpeed,
		Config.MaxFlySpeed,
		flyFill,
		flyKnob
	)
end

local function setWalkSpeedFromPosition(position)
	local width = walkSlider.AbsoluteSize.X

	if width <= 0 then
		return
	end

	local percent = math.clamp(
		(position.X - walkSlider.AbsolutePosition.X) / width,
		0,
		1
	)

	local value =
		Config.MinWalkSpeed
		+ (
			Config.MaxWalkSpeed
			- Config.MinWalkSpeed
		) * percent

	Config.WalkSpeed = math.floor(value + 0.5)

	updateWalkSlider()
	updateCharacterInterface()

	if Config.WalkSpeedEnabled then
		applyWalkSpeed()
	end
end

local function setFlySpeedFromPosition(position)
	local width = flySlider.AbsoluteSize.X

	if width <= 0 then
		return
	end

	local percent = math.clamp(
		(position.X - flySlider.AbsolutePosition.X) / width,
		0,
		1
	)

	local value =
		Config.MinFlySpeed
		+ (
			Config.MaxFlySpeed
			- Config.MinFlySpeed
		) * percent

	Config.FlySpeed = math.floor(value + 0.5)

	updateFlySlider()
	updateCharacterInterface()
end


--==================================================
-- [20] SLIDER INPUT
--==================================================

local draggingWalkSlider = false
local draggingFlySlider = false

local function beginWalkSlider(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		draggingWalkSlider = true
		setWalkSpeedFromPosition(input.Position)
	end
end

local function beginFlySlider(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		draggingFlySlider = true
		setFlySpeedFromPosition(input.Position)
	end
end

addConnection(walkSlider.InputBegan:Connect(beginWalkSlider))
addConnection(walkKnob.InputBegan:Connect(beginWalkSlider))

addConnection(flySlider.InputBegan:Connect(beginFlySlider))
addConnection(flyKnob.InputBegan:Connect(beginFlySlider))

addConnection(UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then

		return
	end

	if draggingWalkSlider then
		setWalkSpeedFromPosition(input.Position)
	end

	if draggingFlySlider then
		setFlySpeedFromPosition(input.Position)
	end
end))

addConnection(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		draggingWalkSlider = false
		draggingFlySlider = false
	end
end))


--==================================================
-- [21] CHARACTER BUTTON EVENTS
--==================================================

addConnection(walkSpeedButton.MouseButton1Click:Connect(function()
	Config.WalkSpeedEnabled =
		not Config.WalkSpeedEnabled

	applyWalkSpeed()
	updateCharacterInterface()
end))

addConnection(lockWalkSpeedButton.MouseButton1Click:Connect(function()
	Config.LockWalkSpeed =
		not Config.LockWalkSpeed

	applyWalkSpeed()
	updateCharacterInterface()
end))

addConnection(infiniteJumpButton.MouseButton1Click:Connect(function()
	Config.InfiniteJump =
		not Config.InfiniteJump

	updateCharacterInterface()
end))

addConnection(flyButton.MouseButton1Click:Connect(function()
	setFlyEnabled(not Config.FlyEnabled)
	updateCharacterInterface()
end))

addConnection(instantPromptButton.MouseButton1Click:Connect(function()
	setInstantPrompt(not Config.InstantPrompt)
	updateCharacterInterface()
end))

addConnection(Noclip.Button.MouseButton1Click:Connect(function()
	Noclip:SetEnabled(not Config.NoclipEnabled)
	updateCharacterInterface()
end))

--==================================================
-- [22] WORLD TAB GUI
--==================================================

local worldTitle = Instance.new("TextLabel")
worldTitle.Size = UDim2.new(1, 0, 0, 35)
worldTitle.BackgroundTransparency = 1
worldTitle.Text = "Teleport to Player"
worldTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
worldTitle.TextSize = 20
worldTitle.Font = Enum.Font.GothamBold
worldTitle.TextXAlignment = Enum.TextXAlignment.Left
worldTitle.LayoutOrder = 1
worldTitle.Parent = worldContent

local playerListFrame = Instance.new("ScrollingFrame")
playerListFrame.Name = "PlayerList"
playerListFrame.Size = UDim2.new(1, 0, 0, 230)
playerListFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 43)
playerListFrame.BorderSizePixel = 0
playerListFrame.ScrollBarThickness = 5
playerListFrame.ScrollBarImageColor3 =
	Color3.fromRGB(110, 110, 125)
playerListFrame.AutomaticCanvasSize =
	Enum.AutomaticSize.Y
playerListFrame.CanvasSize = UDim2.fromOffset(0, 0)
playerListFrame.ScrollingDirection =
	Enum.ScrollingDirection.Y
playerListFrame.LayoutOrder = 2
playerListFrame.Parent = worldContent

local playerListCorner = Instance.new("UICorner")
playerListCorner.CornerRadius = UDim.new(0, 8)
playerListCorner.Parent = playerListFrame

local playerListLayout = Instance.new("UIListLayout")
playerListLayout.Padding = UDim.new(0, 6)
playerListLayout.SortOrder = Enum.SortOrder.Name
playerListLayout.Parent = playerListFrame

local playerListPadding = Instance.new("UIPadding")
playerListPadding.PaddingTop = UDim.new(0, 8)
playerListPadding.PaddingBottom = UDim.new(0, 8)
playerListPadding.PaddingLeft = UDim.new(0, 8)
playerListPadding.PaddingRight = UDim.new(0, 8)
playerListPadding.Parent = playerListFrame

local teleportButton = createPageButton(
	worldContent,
	"Teleport",
	3
)

local refreshButton = createPageButton(
	worldContent,
	"Refresh Player List",
	4
)

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 0, 45)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "ยังไม่ได้เลือกผู้เล่น"
statusLabel.TextColor3 = Color3.fromRGB(175, 175, 185)
statusLabel.TextSize = 13
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextWrapped = true
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.LayoutOrder = 5
statusLabel.Parent = worldContent


--==================================================
-- [23] WORLD PLAYER LIST
--==================================================

local playerButtons = {}

local function updatePlayerButtonStyles()
	for playerName, button in pairs(playerButtons) do
		if playerName == selectedPlayerName then
			button.BackgroundColor3 =
				Color3.fromRGB(55, 135, 220)
		else
			button.BackgroundColor3 =
				Color3.fromRGB(62, 62, 74)
		end
	end
end

local function refreshPlayerList()
	for _, child in ipairs(playerListFrame:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	table.clear(playerButtons)

	local availablePlayers = {}

	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer ~= player then
			table.insert(availablePlayers, targetPlayer)
		end
	end

	table.sort(availablePlayers, function(a, b)
		return string.lower(a.Name)
			< string.lower(b.Name)
	end)

	for _, targetPlayer in ipairs(availablePlayers) do
		local button = Instance.new("TextButton")
		button.Name = targetPlayer.Name
		button.Size = UDim2.new(1, 0, 0, 38)
		button.BackgroundColor3 =
			Color3.fromRGB(62, 62, 74)
		button.BorderSizePixel = 0

		button.Text =
			targetPlayer.DisplayName
			.. "  (@"
			.. targetPlayer.Name
			.. ")"

		button.TextColor3 =
			Color3.fromRGB(255, 255, 255)
		button.TextSize = 14
		button.Font = Enum.Font.GothamMedium
		button.Parent = playerListFrame

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 7)
		corner.Parent = button

		playerButtons[targetPlayer.Name] = button

		button.MouseButton1Click:Connect(function()
			selectedPlayerName = targetPlayer.Name

			statusLabel.Text =
				"เลือก: "
				.. targetPlayer.DisplayName
				.. " (@"
				.. targetPlayer.Name
				.. ")"

			statusLabel.TextColor3 =
				Color3.fromRGB(175, 175, 185)

			updatePlayerButtonStyles()
		end)
	end

	if #availablePlayers == 0 then
		selectedPlayerName = nil
		statusLabel.Text =
			"ไม่พบผู้เล่นคนอื่นในเซิร์ฟเวอร์"
	end
end


--==================================================
-- [24] WORLD BUTTON EVENTS
--==================================================

addConnection(teleportButton.MouseButton1Click:Connect(function()
	if not selectedPlayerName then
		statusLabel.Text = "กรุณาเลือกผู้เล่นก่อน"
		statusLabel.TextColor3 =
			Color3.fromRGB(235, 100, 100)
		return
	end

	local targetPlayer =
		Players:FindFirstChild(selectedPlayerName)

	local success, message =
		teleportToPlayer(targetPlayer)

	statusLabel.Text = message

	if success then
		statusLabel.TextColor3 =
			Color3.fromRGB(90, 220, 130)
	else
		statusLabel.TextColor3 =
			Color3.fromRGB(235, 100, 100)
	end
end))

addConnection(refreshButton.MouseButton1Click:Connect(function()
	selectedPlayerName = nil

	statusLabel.Text = "กำลังรีเฟรชรายชื่อ..."
	statusLabel.TextColor3 =
		Color3.fromRGB(175, 175, 185)

	refreshPlayerList()
end))

addConnection(Players.PlayerAdded:Connect(function()
	refreshPlayerList()
end))

addConnection(Players.PlayerRemoving:Connect(function(leavingPlayer)
	if selectedPlayerName == leavingPlayer.Name then
		selectedPlayerName = nil
	end

	refreshPlayerList()
end))

--==================================================
-- [24.1] POSITION TAB GUI
--==================================================

local positionTitle = Instance.new("TextLabel")
positionTitle.Size = UDim2.new(1, 0, 0, 35)
positionTitle.BackgroundTransparency = 1
positionTitle.Text = "Saved Positions"
positionTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
positionTitle.TextSize = 20
positionTitle.Font = Enum.Font.GothamBold
positionTitle.TextXAlignment = Enum.TextXAlignment.Left
positionTitle.LayoutOrder = 1
positionTitle.Parent = positionContent

-- กลุ่มเพิ่มจุดใหม่
local addPositionGroup = Instance.new("Frame")
addPositionGroup.Size = UDim2.new(1, 0, 0, 96)
addPositionGroup.BackgroundColor3 = Color3.fromRGB(35, 35, 43)
addPositionGroup.BorderSizePixel = 0
addPositionGroup.LayoutOrder = 2
addPositionGroup.Parent = positionContent

local addPositionCorner = Instance.new("UICorner")
addPositionCorner.CornerRadius = UDim.new(0, 8)
addPositionCorner.Parent = addPositionGroup

local positionNameInput = Instance.new("TextBox")
positionNameInput.Name = "PositionNameInput"
positionNameInput.Size = UDim2.new(1, -20, 0, 38)
positionNameInput.Position = UDim2.fromOffset(10, 9)
positionNameInput.BackgroundColor3 = Color3.fromRGB(52, 52, 63)
positionNameInput.BorderSizePixel = 0
positionNameInput.Text = ""
positionNameInput.PlaceholderText = "ชื่อจุด เช่น บ้าน, ร้านค้า, จุดเกิด"
positionNameInput.PlaceholderColor3 = Color3.fromRGB(145, 145, 155)
positionNameInput.TextColor3 = Color3.fromRGB(255, 255, 255)
positionNameInput.TextSize = 14
positionNameInput.Font = Enum.Font.Gotham
positionNameInput.ClearTextOnFocus = false
positionNameInput.Parent = addPositionGroup

local positionNameCorner = Instance.new("UICorner")
positionNameCorner.CornerRadius = UDim.new(0, 7)
positionNameCorner.Parent = positionNameInput

local addPositionButton = Instance.new("TextButton")
addPositionButton.Name = "AddPositionButton"
addPositionButton.Size = UDim2.new(1, -20, 0, 34)
addPositionButton.Position = UDim2.fromOffset(10, 54)
addPositionButton.BackgroundColor3 = Color3.fromRGB(40, 165, 90)
addPositionButton.BorderSizePixel = 0
addPositionButton.Text = "Add Current Position"
addPositionButton.TextColor3 = Color3.fromRGB(255, 255, 255)
addPositionButton.TextSize = 14
addPositionButton.Font = Enum.Font.GothamBold
addPositionButton.Parent = addPositionGroup

local addPositionButtonCorner = Instance.new("UICorner")
addPositionButtonCorner.CornerRadius = UDim.new(0, 7)
addPositionButtonCorner.Parent = addPositionButton

local positionStatusLabel = Instance.new("TextLabel")
positionStatusLabel.Size = UDim2.new(1, 0, 0, 35)
positionStatusLabel.BackgroundTransparency = 1
positionStatusLabel.Text = "ยังไม่มีจุดที่บันทึก"
positionStatusLabel.TextColor3 = Color3.fromRGB(175, 175, 185)
positionStatusLabel.TextSize = 13
positionStatusLabel.Font = Enum.Font.Gotham
positionStatusLabel.TextWrapped = true
positionStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
positionStatusLabel.LayoutOrder = 3
positionStatusLabel.Parent = positionContent

-- Container แสดงรายการจุด
local positionList = Instance.new("Frame")
positionList.Name = "PositionList"
positionList.Size = UDim2.new(1, 0, 0, 0)
positionList.AutomaticSize = Enum.AutomaticSize.Y
positionList.BackgroundTransparency = 1
positionList.LayoutOrder = 4
positionList.Parent = positionContent

local positionListLayout = Instance.new("UIListLayout")
positionListLayout.Padding = UDim.new(0, 8)
positionListLayout.SortOrder = Enum.SortOrder.LayoutOrder
positionListLayout.Parent = positionList

--==================================================
-- [24.2] POSITION DATA AND LIST
--==================================================

local positionRows = {}

local function getDefaultPositionName()
	return "Position " .. tostring(#savedPositions + 1)
end

local function findSavedPositionById(positionId)
	for index, data in ipairs(savedPositions) do
		if data.Id == positionId then
			return data, index
		end
	end

	return nil, nil
end

local function updatePositionStatus()
	local count = #savedPositions

	if count == 0 then
		positionStatusLabel.Text = "ยังไม่มีจุดที่บันทึก"
		positionStatusLabel.TextColor3 =
			Color3.fromRGB(175, 175, 185)
	else
		positionStatusLabel.Text =
			"บันทึกทั้งหมด " .. tostring(count) .. " จุด"

		positionStatusLabel.TextColor3 =
			Color3.fromRGB(175, 175, 185)
	end
end

local function clearPositionRows()
	for _, row in pairs(positionRows) do
		if row then
			row:Destroy()
		end
	end

	table.clear(positionRows)
end

local refreshPositionList

local function createPositionRow(data, layoutOrder)
	local row = Instance.new("Frame")
	row.Name = "Position_" .. tostring(data.Id)
	row.Size = UDim2.new(1, 0, 0, 94)
	row.BackgroundColor3 = Color3.fromRGB(35, 35, 43)
	row.BorderSizePixel = 0
	row.LayoutOrder = layoutOrder
	row.Parent = positionList

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 8)
	rowCorner.Parent = row

	-- ช่องชื่อ สามารถแก้ไขได้
	local nameInput = Instance.new("TextBox")
	nameInput.Name = "NameInput"
	nameInput.Size = UDim2.new(1, -20, 0, 35)
	nameInput.Position = UDim2.fromOffset(10, 8)
	nameInput.BackgroundColor3 = Color3.fromRGB(52, 52, 63)
	nameInput.BorderSizePixel = 0
	nameInput.Text = data.Name
	nameInput.PlaceholderText = "ชื่อจุด"
	nameInput.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameInput.PlaceholderColor3 = Color3.fromRGB(145, 145, 155)
	nameInput.TextSize = 14
	nameInput.Font = Enum.Font.GothamMedium
	nameInput.ClearTextOnFocus = false
	nameInput.Parent = row

	local nameCorner = Instance.new("UICorner")
	nameCorner.CornerRadius = UDim.new(0, 7)
	nameCorner.Parent = nameInput

	-- ปุ่ม Teleport
	local goButton = Instance.new("TextButton")
	goButton.Name = "TeleportButton"
	goButton.Size = UDim2.new(0.58, -15, 0, 34)
	goButton.Position = UDim2.fromOffset(10, 51)
	goButton.BackgroundColor3 = Color3.fromRGB(55, 135, 220)
	goButton.BorderSizePixel = 0
	goButton.Text = "Teleport"
	goButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	goButton.TextSize = 14
	goButton.Font = Enum.Font.GothamBold
	goButton.Parent = row

	local goCorner = Instance.new("UICorner")
	goCorner.CornerRadius = UDim.new(0, 7)
	goCorner.Parent = goButton

	-- ปุ่มลบ
	local deleteButton = Instance.new("TextButton")
	deleteButton.Name = "DeleteButton"
	deleteButton.Size = UDim2.new(0.42, -15, 0, 34)
	deleteButton.Position = UDim2.new(0.58, 5, 0, 51)
	deleteButton.BackgroundColor3 = Color3.fromRGB(190, 55, 60)
	deleteButton.BorderSizePixel = 0
	deleteButton.Text = "Delete"
	deleteButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	deleteButton.TextSize = 14
	deleteButton.Font = Enum.Font.GothamBold
	deleteButton.Parent = row

	local deleteCorner = Instance.new("UICorner")
	deleteCorner.CornerRadius = UDim.new(0, 7)
	deleteCorner.Parent = deleteButton

	-- แก้ไขชื่อเมื่อกดออกจาก TextBox
	nameInput.FocusLost:Connect(function()
		local savedData = findSavedPositionById(data.Id)

		if not savedData then
			return
		end

		local newName = string.gsub(
			nameInput.Text,
			"^%s*(.-)%s*$",
			"%1"
		)

		if newName == "" then
			nameInput.Text = savedData.Name
			return
		end

		savedData.Name = newName
		nameInput.Text = newName

		positionStatusLabel.Text =
			"แก้ชื่อเป็น \"" .. newName .. "\" แล้ว"

		positionStatusLabel.TextColor3 =
			Color3.fromRGB(90, 220, 130)
	end)

	goButton.MouseButton1Click:Connect(function()
		local savedData = findSavedPositionById(data.Id)

		if not savedData then
			positionStatusLabel.Text = "ไม่พบจุดนี้"
			positionStatusLabel.TextColor3 =
				Color3.fromRGB(235, 100, 100)
			return
		end

		local success, message =
			teleportToCFrame(savedData.CFrame)

		if success then
			positionStatusLabel.Text =
				message .. ": " .. savedData.Name

			positionStatusLabel.TextColor3 =
				Color3.fromRGB(90, 220, 130)
		else
			positionStatusLabel.Text = message
			positionStatusLabel.TextColor3 =
				Color3.fromRGB(235, 100, 100)
		end
	end)

	deleteButton.MouseButton1Click:Connect(function()
		local savedData, savedIndex =
			findSavedPositionById(data.Id)

		if not savedData or not savedIndex then
			return
		end

		local deletedName = savedData.Name

		table.remove(savedPositions, savedIndex)

		refreshPositionList()

		positionStatusLabel.Text =
			"ลบ \"" .. deletedName .. "\" แล้ว"

		positionStatusLabel.TextColor3 =
			Color3.fromRGB(235, 120, 120)
	end)

	positionRows[data.Id] = row
end

refreshPositionList = function()
	clearPositionRows()

	for index, data in ipairs(savedPositions) do
		createPositionRow(data, index)
	end

	updatePositionStatus()
end

--==================================================
-- [24.3] ADD CURRENT POSITION
--==================================================

addConnection(addPositionButton.MouseButton1Click:Connect(function()
	local rootPart = getRootPart()

	if not rootPart then
		positionStatusLabel.Text =
			"ไม่พบ HumanoidRootPart ของตัวละคร"

		positionStatusLabel.TextColor3 =
			Color3.fromRGB(235, 100, 100)

		return
	end

	local enteredName = string.gsub(
		positionNameInput.Text,
		"^%s*(.-)%s*$",
		"%1"
	)

	if enteredName == "" then
		enteredName = getDefaultPositionName()
	end

	nextPositionId += 1

	table.insert(savedPositions, {
		Id = nextPositionId,
		Name = enteredName,
		CFrame = rootPart.CFrame,
	})

	positionNameInput.Text = ""

	refreshPositionList()

	positionStatusLabel.Text =
		"เพิ่มจุด \"" .. enteredName .. "\" แล้ว"

	positionStatusLabel.TextColor3 =
		Color3.fromRGB(90, 220, 130)
end))

addConnection(positionNameInput.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		addPositionButton:Activate()
	end
end))

--==================================================
-- [24.4] DAMAGE TAB GUI
--==================================================

local damageTitle = Instance.new("TextLabel")
damageTitle.Size = UDim2.new(1, 0, 0, 35)
damageTitle.BackgroundTransparency = 1
damageTitle.Text = "Damage / Auto Attack"
damageTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
damageTitle.TextSize = 20
damageTitle.Font = Enum.Font.GothamBold
damageTitle.TextXAlignment = Enum.TextXAlignment.Left
damageTitle.LayoutOrder = 1
damageTitle.Parent = damageContent

local autoAttackButton = createPageButton(
	damageContent,
	"Auto Attack: OFF",
	2
)

local attackRadiusGroup,
	attackRadiusLabel,
	attackRadiusSlider,
	attackRadiusFill,
	attackRadiusKnob = createSliderGroup(
		damageContent,
		"Attack Radius: " .. Config.AttackRadius,
		3
	)

local attackSpeedGroup,
	attackSpeedLabel,
	attackSpeedSlider,
	attackSpeedFill,
	attackSpeedKnob = createSliderGroup(
		damageContent,
		"Attack Interval: " .. Config.AttackInterval,
		4
	)

local onlyNPCButton = createPageButton(
	damageContent,
	"Only NPC: ON",
	5
)

local lockRadiusButton = createPageButton(
	damageContent,
	"Lock Radius: ON",
	5
)


local damageInfoLabel = Instance.new("TextLabel")
damageInfoLabel.Size = UDim2.new(1, 0, 0, 90)
damageInfoLabel.BackgroundTransparency = 1
damageInfoLabel.Text =
	"Auto Attack จะทำงานเฉพาะตอนถือ Tool\n"
	.. "Radius = ระยะตรวจหาเป้าหมาย\n"
	.. "Interval ต่ำ = โจมตีเร็วขึ้น"
damageInfoLabel.TextColor3 = Color3.fromRGB(165, 165, 175)
damageInfoLabel.TextSize = 13
damageInfoLabel.Font = Enum.Font.Gotham
damageInfoLabel.TextWrapped = true
damageInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
damageInfoLabel.LayoutOrder = 6
damageInfoLabel.Parent = damageContent

local function updateDamageInterface()
	if scriptClosed then
		return
	end

	setButtonState(
		autoAttackButton,
		"Auto Attack",
		Config.AutoAttackEnabled
	)

	setButtonState(
		onlyNPCButton,
		"Only NPC",
		Config.OnlyNPC
	)
	
	setButtonState(
		lockRadiusButton,
		"Lock Radius",
		Config.LockAttackRadius
	)
	attackRadiusLabel.Text =
		"Attack Radius: "
		.. tostring(Config.AttackRadius)

	attackSpeedLabel.Text =
		"Attack Interval: "
		.. string.format("%.2f", Config.AttackInterval)
end


local function updateAttackRadiusSlider()
	updateSliderVisual(
		Config.AttackRadius,
		Config.MinAttackRadius,
		Config.MaxAttackRadius,
		attackRadiusFill,
		attackRadiusKnob
	)
end

local function updateAttackSpeedSlider()
	updateSliderVisual(
		Config.AttackInterval,
		Config.MinAttackInterval,
		Config.MaxAttackInterval,
		attackSpeedFill,
		attackSpeedKnob
	)
end

local function setAttackRadiusFromPosition(position)
	local width = attackRadiusSlider.AbsoluteSize.X

	if width <= 0 then
		return
	end

	local percent = math.clamp(
		(position.X - attackRadiusSlider.AbsolutePosition.X) / width,
		0,
		1
	)

	local value =
		Config.MinAttackRadius
		+ (
			Config.MaxAttackRadius
			- Config.MinAttackRadius
		) * percent

	Config.AttackRadius = math.floor(value + 0.5)

	if Config.LockAttackRadius then
		Config.LockedAttackRadius = Config.AttackRadius
	end

	updateAttackRadiusSlider()
	updateDamageInterface()
end

local function setAttackSpeedFromPosition(position)
	local width = attackSpeedSlider.AbsoluteSize.X

	if width <= 0 then
		return
	end

	local percent = math.clamp(
		(
			position.X
			- attackSpeedSlider.AbsolutePosition.X
		) / width,
		0,
		1
	)

	local value =
		Config.MinAttackInterval
		+ (
			Config.MaxAttackInterval
			- Config.MinAttackInterval
		) * percent

	-- เก็บทศนิยม 2 ตำแหน่ง
	Config.AttackInterval =
		math.floor(value * 100 + 0.5) / 100

	updateAttackSpeedSlider()
	updateDamageInterface()
end

local draggingAttackRadiusSlider = false
local draggingAttackSpeedSlider = false

local function beginAttackRadiusSlider(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		draggingAttackRadiusSlider = true
		setAttackRadiusFromPosition(input.Position)
	end
end

local function beginAttackSpeedSlider(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		draggingAttackSpeedSlider = true
		setAttackSpeedFromPosition(input.Position)
	end
end

addConnection(
	attackRadiusSlider.InputBegan:Connect(
		beginAttackRadiusSlider
	)
)

addConnection(
	attackRadiusKnob.InputBegan:Connect(
		beginAttackRadiusSlider
	)
)

addConnection(
	attackSpeedSlider.InputBegan:Connect(
		beginAttackSpeedSlider
	)
)

addConnection(
	attackSpeedKnob.InputBegan:Connect(
		beginAttackSpeedSlider
	)
)

addConnection(UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then

		return
	end

	if draggingAttackRadiusSlider then
		setAttackRadiusFromPosition(input.Position)
	end

	if draggingAttackSpeedSlider then
		setAttackSpeedFromPosition(input.Position)
	end
end))

addConnection(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		draggingAttackRadiusSlider = false
		draggingAttackSpeedSlider = false
	end
end))

addConnection(autoAttackButton.MouseButton1Click:Connect(function()
	setAutoAttackEnabled(
		not Config.AutoAttackEnabled
	)

	updateDamageInterface()
end))

addConnection(onlyNPCButton.MouseButton1Click:Connect(function()
	Config.OnlyNPC = not Config.OnlyNPC

	updateDamageInterface()
end))

addConnection(lockRadiusButton.MouseButton1Click:Connect(function()
	setRadiusLockEnabled(
		not Config.LockAttackRadius
	)

	updateDamageInterface()
end))


--==================================================
-- [24.5] AUTO CLICK TAB GUI
--==================================================

local autoClickTitle = Instance.new("TextLabel")
autoClickTitle.Size = UDim2.new(1, 0, 0, 35)
autoClickTitle.BackgroundTransparency = 1
autoClickTitle.Text = "Auto Click"
autoClickTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
autoClickTitle.TextSize = 20
autoClickTitle.Font = Enum.Font.GothamBold
autoClickTitle.TextXAlignment = Enum.TextXAlignment.Left
autoClickTitle.LayoutOrder = 1
autoClickTitle.Parent = autoClickContent

local autoClickButton = createPageButton(
	autoClickContent,
	"Auto Click: OFF",
	2
)

local autoClickSpeedGroup,
	autoClickSpeedLabel,
	autoClickSpeedSlider,
	autoClickSpeedFill,
	autoClickSpeedKnob = createSliderGroup(
	autoClickContent,
	"Click Interval: "
		.. string.format("%.2f", Config.AutoClickInterval),
	3
)

local autoClickInfoLabel = Instance.new("TextLabel")
autoClickInfoLabel.Size = UDim2.new(1, 0, 0, 90)
autoClickInfoLabel.BackgroundTransparency = 1
autoClickInfoLabel.Text =
	"กด G เพื่อเปิดหรือปิด Auto Click\n"
	.. "ทำงานเฉพาะตอนถือ Tool\n"
	.. "0.01 = คลิกเร็วที่สุด"
autoClickInfoLabel.TextColor3 =
	Color3.fromRGB(165, 165, 175)
autoClickInfoLabel.TextSize = 13
autoClickInfoLabel.Font = Enum.Font.Gotham
autoClickInfoLabel.TextWrapped = true
autoClickInfoLabel.TextXAlignment =
	Enum.TextXAlignment.Left
autoClickInfoLabel.LayoutOrder = 4
autoClickInfoLabel.Parent = autoClickContent

local function updateAutoClickInterface()
	if scriptClosed then
		return
	end

	setButtonState(
		autoClickButton,
		"Auto Click",
		Config.AutoClickEnabled
	)

	autoClickSpeedLabel.Text =
		"Click Interval: "
		.. string.format(
			"%.2f",
			Config.AutoClickInterval
		)
end

local function updateAutoClickSlider()
	updateSliderVisual(
		Config.AutoClickInterval,
		Config.MinAutoClickInterval,
		Config.MaxAutoClickInterval,
		autoClickSpeedFill,
		autoClickSpeedKnob
	)
end

local function setAutoClickSpeedFromPosition(position)
	local width = autoClickSpeedSlider.AbsoluteSize.X

	if width <= 0 then
		return
	end

	local percent = math.clamp(
		(
			position.X
			- autoClickSpeedSlider.AbsolutePosition.X
		) / width,
		0,
		1
	)

	local value =
		Config.MinAutoClickInterval
		+ (
			Config.MaxAutoClickInterval
			- Config.MinAutoClickInterval
		) * percent

	Config.AutoClickInterval =
		math.floor(value * 100 + 0.5) / 100

	Config.AutoClickInterval = math.clamp(
		Config.AutoClickInterval,
		Config.MinAutoClickInterval,
		Config.MaxAutoClickInterval
	)

	updateAutoClickSlider()
	updateAutoClickInterface()
end

local draggingAutoClickSlider = false

local function beginAutoClickSlider(input)
	if input.UserInputType
			== Enum.UserInputType.MouseButton1
		or input.UserInputType
			== Enum.UserInputType.Touch then

		draggingAutoClickSlider = true
		setAutoClickSpeedFromPosition(input.Position)
	end
end

addConnection(
	autoClickSpeedSlider.InputBegan:Connect(
		beginAutoClickSlider
	)
)

addConnection(
	autoClickSpeedKnob.InputBegan:Connect(
		beginAutoClickSlider
	)
)

addConnection(UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType
			~= Enum.UserInputType.MouseMovement
		and input.UserInputType
			~= Enum.UserInputType.Touch then

		return
	end

	if draggingAutoClickSlider then
		setAutoClickSpeedFromPosition(
			input.Position
		)
	end
end))

addConnection(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType
			== Enum.UserInputType.MouseButton1
		or input.UserInputType
			== Enum.UserInputType.Touch then

		draggingAutoClickSlider = false
	end
end))

addConnection(autoClickButton.MouseButton1Click:Connect(function()
	toggleAutoClick()
	updateAutoClickInterface()
end))

--==================================================
-- [25] TAB EVENTS
--==================================================

addConnection(characterTab.MouseButton1Click:Connect(function()
	showTab("Character")
end))

addConnection(worldTab.MouseButton1Click:Connect(function()
	showTab("Teleport")
end))

addConnection(positionTab.MouseButton1Click:Connect(function()
	showTab("Position")
	refreshPositionList()
end))

addConnection(damageTab.MouseButton1Click:Connect(function()
	showTab("Auto Damage")

	updateAttackRadiusSlider()
	updateAttackSpeedSlider()
	updateDamageInterface()
end))


addConnection(autoClickTab.MouseButton1Click:Connect(function()
	showTab("Auto Click")

	updateAutoClickSlider()
	updateAutoClickInterface()
end))


--==================================================
-- [26] MINIMIZE LOGO
--==================================================

local logoButton = Instance.new("ImageButton")
logoButton.Name = "LogoButton"
logoButton.Size = UDim2.fromOffset(62, 62)
logoButton.AnchorPoint = Vector2.new(0.5, 0)
logoButton.Position = UDim2.new(0.5, 0, 0, 100)
logoButton.BackgroundColor3 = Color3.fromRGB(25, 25, 31)
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
logoStroke.Color = Color3.fromRGB(90, 90, 105)
logoStroke.Thickness = 2
logoStroke.Parent = logoButton

local logoPadding = Instance.new("UIPadding")
logoPadding.PaddingTop = UDim.new(0, 7)
logoPadding.PaddingBottom = UDim.new(0, 7)
logoPadding.PaddingLeft = UDim.new(0, 7)
logoPadding.PaddingRight = UDim.new(0, 7)
logoPadding.Parent = logoButton

local function minimizeMenu()
	if scriptClosed then
		return
	end

	mainFrame.Visible = false

	-- จัดโลโก้ไว้กึ่งกลางด้านบนทุกครั้งที่ย่อ
	logoButton.AnchorPoint = Vector2.new(0.5, 0)
	logoButton.Position = UDim2.new(0.5, 0, 0, 100)

	logoButton.Visible = true
end

local function restoreMenu()
	if scriptClosed then
		return
	end

	mainFrame.Visible = true
	logoButton.Visible = false
end


--==================================================
-- [27] DRAG MAIN WINDOW
--==================================================

local draggingWindow = false
local windowDragStart = nil
local windowStartPosition = nil

addConnection(titleBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		draggingWindow = true
		windowDragStart = input.Position
		windowStartPosition = mainFrame.Position
	end
end))

addConnection(UserInputService.InputChanged:Connect(function(input)
	if not draggingWindow then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then

		return
	end

	local delta = input.Position - windowDragStart

	mainFrame.Position = UDim2.new(
		windowStartPosition.X.Scale,
		windowStartPosition.X.Offset + delta.X,
		windowStartPosition.Y.Scale,
		windowStartPosition.Y.Offset + delta.Y
	)
end))

addConnection(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		draggingWindow = false
	end
end))


--==================================================
-- [28] DRAG LOGO
--==================================================

local draggingLogo = false
local logoDragStart = nil
local logoStartPosition = nil
local logoWasDragged = false

addConnection(logoButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		draggingLogo = true
		logoWasDragged = false
		logoDragStart = input.Position
		logoStartPosition = logoButton.Position
	end
end))

addConnection(UserInputService.InputChanged:Connect(function(input)
	if not draggingLogo then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then

		return
	end

	local delta = input.Position - logoDragStart

	if delta.Magnitude > 5 then
		logoWasDragged = true
	end

	logoButton.Position = UDim2.new(
		logoStartPosition.X.Scale,
		logoStartPosition.X.Offset + delta.X,
		logoStartPosition.Y.Scale,
		logoStartPosition.Y.Offset + delta.Y
	)
end))

addConnection(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		draggingLogo = false
	end
end))


--==================================================
-- [29] CLOSE SCRIPT
--==================================================

local function closeScript()
	if scriptClosed then
		return
	end

	scriptClosed = true

	Config.WalkSpeedEnabled = false
	Config.LockWalkSpeed = false
	Config.InfiniteJump = false
	Config.FlyEnabled = false
	Config.InstantPrompt = false
	
	Config.NoclipEnabled = false
	Noclip:Stop()

	stopFly()
	disconnectWalkSpeedLock()
	
	Config.AutoAttackEnabled = false
	stopAutoAttack()
	
	Config.LockAttackRadius = false
	stopRadiusLock()
	
	Config.AutoClickEnabled = false
	stopAutoClick()

	local humanoid = getHumanoid()

	if humanoid then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
		humanoid.WalkSpeed = Config.NormalWalkSpeed
	end

	for prompt, data in pairs(promptData) do
		if data.HoldConnection then
			data.HoldConnection:Disconnect()
		end

		if data.DestroyConnection then
			data.DestroyConnection:Disconnect()
		end

		if prompt.Parent then
			prompt.HoldDuration =
				data.OriginalDuration
		end

		promptData[prompt] = nil
	end

	disconnectAllConnections()

	if screenGui then
		screenGui:Destroy()
	end
end


--==================================================
-- [30] WINDOW EVENTS
--==================================================

addConnection(minimizeButton.MouseButton1Click:Connect(function()
	minimizeMenu()
end))

addConnection(logoButton.MouseButton1Click:Connect(function()
	if not logoWasDragged then
		restoreMenu()
	end
end))

addConnection(closeButton.MouseButton1Click:Connect(function()
	closeScript()
end))

addConnection(UserInputService.InputBegan:Connect(function(
	input,
	gameProcessed
)
	if scriptClosed or gameProcessed then
		return
	end

	if input.KeyCode == Config.ToggleKey then
		if mainFrame.Visible then
			minimizeMenu()
		else
			restoreMenu()
		end

		return
	end

	if UserInputService:GetFocusedTextBox() then
		return
	end

	if input.KeyCode == Config.AutoClickKey then
		toggleAutoClick()
		updateAutoClickInterface()
	end
end))


--==================================================
-- [31] CHARACTER RESPAWN
--==================================================

addConnection(player.CharacterAdded:Connect(function(character)
	if scriptClosed then
		return
	end

	local resumeFly = Config.FlyEnabled
	local resumeNoclip = Config.NoclipEnabled

	Config.FlyEnabled = false
	stopFly()

	Config.NoclipEnabled = false
	Noclip:Stop()

	setupWalkSpeedLock(character)

	task.wait(0.7)

	if scriptClosed then
		return
	end

	if resumeNoclip then
		Noclip:SetEnabled(true)
	end

	if resumeFly then
		setFlyEnabled(true)
	end

	updateCharacterInterface()
end))


--==================================================
-- [32] START SCRIPT
--==================================================

if player.Character then
	task.spawn(
		setupWalkSpeedLock,
		player.Character
	)
end

task.defer(function()
	if scriptClosed then
		return
	end

	showTab("Character")

	updateWalkSlider()
	updateFlySlider()
	updateCharacterInterface()

	refreshPlayerList()
	refreshPositionList()
	
	updateAttackRadiusSlider()
	updateAttackSpeedSlider()
	updateDamageInterface()
	
	updateAutoClickSlider()
	updateAutoClickInterface()
end)
