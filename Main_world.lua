--==================================================
-- [1] SERVICES
--==================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")


--==================================================
-- [2] CONFIG
--==================================================

-- เปลี่ยนเป็น Asset ID โลโก้ของคุณ
local LOGO_ASSET_ID = "rbxassetid://119090588699199"

local Config = {
	-- Walk Speed
	WalkSpeedEnabled = false,
	LockWalkSpeed = false,

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

	AutoClickInterval = 0.01,
	MinAutoClickInterval = 0.01,
	MaxAutoClickInterval = 1.00,

	AutoClickKey = Enum.KeyCode.G,

	-- Auto E
	AutoEEnabled = false,
	AutoEInterval = 0.01,
	AutoEHoldTime = 0.01,

	-- Crystals
	RemoveCrystalLightEnabled = true,
	RemoveLowPriceCrystalsEnabled = false,
	MinimumCrystalPrice = 10000000,
	CrystalScanInterval = 0.1,

	-- Boulder ESP
	BoulderESPEnabled = true,

}


--==================================================
-- [3] STATE
--==================================================

local UI = { State = {} }

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

local autoEThread = nil
local visibleEPrompts = {}

local crystalLoopThread = nil
local crystalOriginalBrightness = {}
local hiddenCrystalParts = {}

local boulderESPConnection = nil
local BOULDER_ESP_NAME = "MainWorldBoulderESP"

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


local Addons = {}

do
	--==================================================
	-- [10.4] AUTO E / CRYSTALS / BOULDER ESP
	--==================================================

	function Addons.setAutoEEnabled(enabled)
		Config.AutoEEnabled = enabled

		if autoEThread then
			task.cancel(autoEThread)
			autoEThread = nil
		end

		if not enabled then
			return
		end

		autoEThread = task.spawn(function()
			while not scriptClosed and Config.AutoEEnabled do
				local rootPart = getRootPart()
				local selectedPrompt = nil
				local selectedDistance = math.huge

				for prompt in pairs(visibleEPrompts) do
					if not prompt.Parent
						or not prompt.Enabled
						or prompt.KeyboardKeyCode ~= Enum.KeyCode.E then

						visibleEPrompts[prompt] = nil
					else
						local parent = prompt.Parent
						local position = nil

						if parent:IsA("Attachment") then
							position = parent.WorldPosition
						elseif parent:IsA("BasePart") then
							position = parent.Position
						end

						if rootPart and position then
							local distance =
								(position - rootPart.Position).Magnitude

							if distance < selectedDistance then
								selectedDistance = distance
								selectedPrompt = prompt
							end
						elseif not selectedPrompt then
							selectedPrompt = prompt
						end
					end
				end

				if selectedPrompt then
					pcall(function()
						selectedPrompt:InputHoldBegin()
						task.wait(math.max(
							selectedPrompt.HoldDuration,
							Config.AutoEHoldTime
						))

						if Config.AutoEEnabled
							and selectedPrompt.Parent then

							selectedPrompt:InputHoldEnd()
						end
					end)
				end

				task.wait(Config.AutoEInterval)
			end

			autoEThread = nil
		end)
	end

	addConnection(ProximityPromptService.PromptShown:Connect(function(
		prompt,
		_inputType
	)
		if prompt.KeyboardKeyCode == Enum.KeyCode.E then
			visibleEPrompts[prompt] = true
		end
	end))

	addConnection(ProximityPromptService.PromptHidden:Connect(function(prompt)
		visibleEPrompts[prompt] = nil
	end))

	local function getCrystalsFolder()
		local things = Workspace:FindFirstChild("Things")
		return things and things:FindFirstChild("Crystals")
	end

	function Addons.parseCrystalValue(value)
		if value == nil then
			return nil
		end

		if typeof(value) == "number" then
			return value
		end

		local valueText = tostring(value)
			:gsub(",", "")
			:gsub("%s+", "")
			:gsub("%$", "")
			:lower()

		local numberText = valueText:match("%-?%d+%.?%d*")
		local number = numberText and tonumber(numberText)

		if not number then
			return nil
		end

		if valueText:find("b", 1, true) then
			number *= 1000000000
		elseif valueText:find("m", 1, true) then
			number *= 1000000
		elseif valueText:find("k", 1, true) then
			number *= 1000
		end

		return number
	end

	local function getCrystalValue(crystal)
		if crystal:IsA("NumberValue")
			or crystal:IsA("IntValue")
			or crystal:IsA("StringValue") then

			return Addons.parseCrystalValue(crystal.Value)
		end

		for name, value in pairs(crystal:GetAttributes()) do
			local lower = string.lower(name)

			if lower:find("value", 1, true)
				or lower:find("price", 1, true)
				or lower == "worth"
				or lower == "cost" then

				local parsed = Addons.parseCrystalValue(value)

				if parsed then
					return parsed
				end
			end
		end

		for _, object in ipairs(crystal:GetDescendants()) do
			local lower = string.lower(object.Name)
			local relevant =
				lower:find("value", 1, true)
				or lower:find("price", 1, true)
				or lower == "worth"
				or lower == "cost"

			if relevant then
				if object:IsA("ValueBase") then
					local parsed = Addons.parseCrystalValue(object.Value)

					if parsed then
						return parsed
					end
				elseif object:IsA("TextLabel")
					or object:IsA("TextButton")
					or object:IsA("TextBox") then

					local parsed = Addons.parseCrystalValue(object.Text)

					if parsed then
						return parsed
					end
				end
			end
		end

		return Addons.parseCrystalValue(crystal.Name)
	end

	local function restoreCrystal(crystal)
		local saved = hiddenCrystalParts[crystal]

		if not saved then
			return
		end

		for object, value in pairs(saved) do
			if object and object.Parent then
				if object:IsA("BasePart") then
					object.LocalTransparencyModifier = value
				elseif object:IsA("ParticleEmitter")
					or object:IsA("Trail")
					or object:IsA("Beam") then

					object.Enabled = value
				end
			end
		end

		hiddenCrystalParts[crystal] = nil
	end

	local function hideCrystal(crystal)
		if hiddenCrystalParts[crystal] then
			return
		end

		local saved = {}
		hiddenCrystalParts[crystal] = saved

		for _, object in ipairs(crystal:GetDescendants()) do
			if object:IsA("BasePart") then
				saved[object] = object.LocalTransparencyModifier
				object.LocalTransparencyModifier = 1
			elseif object:IsA("ParticleEmitter")
				or object:IsA("Trail")
				or object:IsA("Beam") then

				saved[object] = object.Enabled
				object.Enabled = false
			end
		end
	end

	function Addons.restoreAllCrystals()
		for crystal in pairs(hiddenCrystalParts) do
			if crystal and crystal.Parent then
				restoreCrystal(crystal)
			end
		end

		table.clear(hiddenCrystalParts)
	end

	function Addons.applyCrystalLights()
		local folder = getCrystalsFolder()

		if not folder then
			return 0
		end

		local changed = 0

		for _, object in ipairs(folder:GetDescendants()) do
			if object.Name == "CrystalGlow"
				and object:IsA("Light") then

				if crystalOriginalBrightness[object] == nil then
					crystalOriginalBrightness[object] =
						object.Brightness
				end

				if Config.RemoveCrystalLightEnabled then
					object.Brightness = 0
					changed += 1
				end
			end
		end

		return changed
	end

	function Addons.restoreCrystalLights()
		for light, brightness in pairs(crystalOriginalBrightness) do
			if light and light.Parent then
				light.Brightness = brightness
			end
		end

		table.clear(crystalOriginalBrightness)
	end

	function Addons.applyLowPriceFilter()
		local folder = getCrystalsFolder()

		if not folder then
			return 0, 0, 0
		end

		local checked = 0
		local hidden = 0
		local noValue = 0

		for _, crystal in ipairs(folder:GetChildren()) do
			checked += 1

			local value = getCrystalValue(crystal)

			if value then
				if Config.RemoveLowPriceCrystalsEnabled
					and value < Config.MinimumCrystalPrice then

					hideCrystal(crystal)
					hidden += 1
				else
					restoreCrystal(crystal)
				end
			else
				noValue += 1
			end
		end

		return checked, hidden, noValue
	end

	local BOULDER_COLORS = {
		Color3.fromRGB(0, 200, 255),
		Color3.fromRGB(0, 255, 100),
		Color3.fromRGB(255, 230, 0),
		Color3.fromRGB(180, 0, 255),
		Color3.fromRGB(0, 80, 255),
		Color3.fromRGB(255, 70, 180),
	}

	local function getBouldersFolder()
		local mountain =
			Workspace:FindFirstChild("MountainDecorations")

		return mountain and mountain:FindFirstChild("Boulders")
	end

	local function addBoulderESP(container, index)
		if not Config.BoulderESPEnabled or not container then
			return
		end

		if not (
			container:IsA("Model")
			or container:IsA("Folder")
			or container:IsA("BasePart")
		) then
			return
		end

		local highlight =
			container:FindFirstChild(BOULDER_ESP_NAME)

		if not highlight then
			highlight = Instance.new("Highlight")
			highlight.Name = BOULDER_ESP_NAME
			highlight.Adornee = container
			highlight.FillTransparency = 0.45
			highlight.OutlineTransparency = 0
			highlight.DepthMode =
				Enum.HighlightDepthMode.AlwaysOnTop
			highlight.Parent = container
		end

		local color =
			BOULDER_COLORS[
				((index or 1) - 1) % #BOULDER_COLORS + 1
			]

		highlight.FillColor = color
		highlight.OutlineColor = color
		highlight.Enabled = true
	end

	local function removeBoulderESP()
		local folder = getBouldersFolder()

		if not folder then
			return
		end

		for _, object in ipairs(folder:GetDescendants()) do
			if object:IsA("Highlight")
				and object.Name == BOULDER_ESP_NAME then

				object:Destroy()
			end
		end
	end

	function Addons.scanBoulderESP()
		local folder = getBouldersFolder()

		if not folder then
			return 0
		end

		local list = folder:GetChildren()

		table.sort(list, function(a, b)
			return string.lower(a.Name)
				< string.lower(b.Name)
		end)

		for index, container in ipairs(list) do
			addBoulderESP(container, index)
		end

		return #list
	end

	function Addons.setBoulderESPEnabled(enabled)
		Config.BoulderESPEnabled = enabled

		if boulderESPConnection then
			boulderESPConnection:Disconnect()
			boulderESPConnection = nil
		end

		if not enabled then
			removeBoulderESP()
			return
		end

		Addons.scanBoulderESP()

		local folder = getBouldersFolder()

		if folder then
			boulderESPConnection =
				folder.ChildAdded:Connect(function(container)
					task.wait()
					addBoulderESP(container, #folder:GetChildren())
				end)
		end
	end

	function Addons.stopCrystalLoop()
		if crystalLoopThread then
			task.cancel(crystalLoopThread)
			crystalLoopThread = nil
		end
	end

	function Addons.startCrystalLoop()
		Addons.stopCrystalLoop()

		crystalLoopThread = task.spawn(function()
			while not scriptClosed do
				if Config.RemoveCrystalLightEnabled then
					Addons.applyCrystalLights()
				end

				if Config.RemoveLowPriceCrystalsEnabled then
					Addons.applyLowPriceFilter()
				end

				task.wait(Config.CrystalScanInterval)
			end
		end)
	end

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

UI.screenGui = Instance.new("ScreenGui")
UI.screenGui.Name = "ExampleTabMenu"
UI.screenGui.ResetOnSpawn = false
UI.screenGui.IgnoreGuiInset = true
UI.screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
UI.screenGui.DisplayOrder = 2147483647
UI.screenGui.Parent = playerGui

UI.mainFrame = Instance.new("Frame")
UI.mainFrame.Name = "MainFrame"
UI.mainFrame.Size = UDim2.fromOffset(540, 440)
UI.mainFrame.Position = UDim2.new(0.5, -270, 0.5, -220)
UI.mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 31)
UI.mainFrame.BorderSizePixel = 0
UI.mainFrame.Active = true
UI.mainFrame.ZIndex = 100
UI.mainFrame.Parent = UI.screenGui

UI.mainCorner = Instance.new("UICorner")
UI.mainCorner.CornerRadius = UDim.new(0, 12)
UI.mainCorner.Parent = UI.mainFrame

UI.mainStroke = Instance.new("UIStroke")
UI.mainStroke.Color = Color3.fromRGB(80, 80, 95)
UI.mainStroke.Thickness = 1
UI.mainStroke.Parent = UI.mainFrame


--==================================================
-- [13] TITLE BAR
--==================================================

UI.titleBar = Instance.new("Frame")
UI.titleBar.Name = "TitleBar"
UI.titleBar.Size = UDim2.new(1, 0, 0, 48)
UI.titleBar.BackgroundColor3 = Color3.fromRGB(36, 36, 44)
UI.titleBar.BorderSizePixel = 0
UI.titleBar.Active = true
UI.titleBar.ZIndex = 101
UI.titleBar.Parent = UI.mainFrame

UI.titleCorner = Instance.new("UICorner")
UI.titleCorner.CornerRadius = UDim.new(0, 12)
UI.titleCorner.Parent = UI.titleBar

UI.titleBottomFix = Instance.new("Frame")
UI.titleBottomFix.Size = UDim2.new(1, 0, 0, 12)
UI.titleBottomFix.Position = UDim2.new(0, 0, 1, -12)
UI.titleBottomFix.BackgroundColor3 = Color3.fromRGB(36, 36, 44)
UI.titleBottomFix.BorderSizePixel = 0
UI.titleBottomFix.Parent = UI.titleBar

UI.titleLogo = Instance.new("ImageLabel")
UI.titleLogo.Name = "TitleLogo"
UI.titleLogo.Size = UDim2.fromOffset(34, 34)
UI.titleLogo.Position = UDim2.fromOffset(9, 7)
UI.titleLogo.BackgroundTransparency = 1
UI.titleLogo.Image = LOGO_ASSET_ID
UI.titleLogo.ScaleType = Enum.ScaleType.Fit
UI.titleLogo.ZIndex = 102
UI.titleLogo.Parent = UI.titleBar

UI.titleLabel = Instance.new("TextLabel")
UI.titleLabel.Size = UDim2.new(1, -150, 1, 0)
UI.titleLabel.Position = UDim2.fromOffset(50, 0)
UI.titleLabel.BackgroundTransparency = 1
UI.titleLabel.Text = "Main World"
UI.titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
UI.titleLabel.TextSize = 19
UI.titleLabel.Font = Enum.Font.GothamBold
UI.titleLabel.TextXAlignment = Enum.TextXAlignment.Left
UI.titleLabel.ZIndex = 102
UI.titleLabel.Parent = UI.titleBar

-- ปุ่มย่อ
UI.minimizeButton = Instance.new("TextButton")
UI.minimizeButton.Name = "MinimizeButton"
UI.minimizeButton.Size = UDim2.fromOffset(36, 30)
UI.minimizeButton.Position = UDim2.new(1, -84, 0, 9)
UI.minimizeButton.BackgroundColor3 = Color3.fromRGB(65, 65, 77)
UI.minimizeButton.BorderSizePixel = 0
UI.minimizeButton.Text = "—"
UI.minimizeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
UI.minimizeButton.TextSize = 20
UI.minimizeButton.Font = Enum.Font.GothamBold
UI.minimizeButton.ZIndex = 102
UI.minimizeButton.Parent = UI.titleBar

UI.minimizeCorner = Instance.new("UICorner")
UI.minimizeCorner.CornerRadius = UDim.new(0, 7)
UI.minimizeCorner.Parent = UI.minimizeButton

-- ปุ่มปิดอยู่ขวาสุด
UI.closeButton = Instance.new("TextButton")
UI.closeButton.Name = "CloseButton"
UI.closeButton.Size = UDim2.fromOffset(36, 30)
UI.closeButton.Position = UDim2.new(1, -43, 0, 9)
UI.closeButton.BackgroundColor3 = Color3.fromRGB(190, 55, 60)
UI.closeButton.BorderSizePixel = 0
UI.closeButton.Text = "X"
UI.closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
UI.closeButton.TextSize = 15
UI.closeButton.Font = Enum.Font.GothamBold
UI.closeButton.ZIndex = 102
UI.closeButton.Parent = UI.titleBar

UI.closeCorner = Instance.new("UICorner")
UI.closeCorner.CornerRadius = UDim.new(0, 7)
UI.closeCorner.Parent = UI.closeButton


--==================================================
-- [14] SIDEBAR AND CONTENT AREA
--==================================================

UI.sidebar = Instance.new("Frame")
UI.sidebar.Name = "Sidebar"
UI.sidebar.Size = UDim2.fromOffset(130, 392)
UI.sidebar.Position = UDim2.fromOffset(0, 48)
UI.sidebar.BackgroundColor3 = Color3.fromRGB(31, 31, 38)
UI.sidebar.BorderSizePixel = 0
UI.sidebar.Parent = UI.mainFrame

UI.contentFrame = Instance.new("Frame")
UI.contentFrame.Name = "ContentFrame"
UI.contentFrame.Size = UDim2.new(1, -130, 1, -48)
UI.contentFrame.Position = UDim2.fromOffset(130, 48)
UI.contentFrame.BackgroundTransparency = 1
UI.contentFrame.ClipsDescendants = true
UI.contentFrame.Parent = UI.mainFrame


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
	tabButton.Parent = UI.sidebar

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
	page.Parent = UI.contentFrame

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

	return tabButton, pageContent
end

local characterTab, characterContent =
	createTab("Character", 1)

local worldTab, worldContent =
	createTab("Teleport", 2)

local positionTab, positionContent =
	createTab("Position", 3)

local damageTab, damageContent =
	createTab("Auto Damage", 4)

local autoClickTab, autoClickContent =
	createTab("Auto Click", 5)

local crystalsTab, crystalsContent =
	createTab("Crystals", 6)

local findCrystalsTab, findCrystalsContent =
	createTab("Find Crystals", 7)

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

	return label, slider, fill, knob
end


--==================================================
-- [17] CHARACTER TAB GUI
--==================================================

UI.characterTitle = Instance.new("TextLabel")
UI.characterTitle.Size = UDim2.new(1, 0, 0, 35)
UI.characterTitle.BackgroundTransparency = 1
UI.characterTitle.Text = "Character"
UI.characterTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
UI.characterTitle.TextSize = 20
UI.characterTitle.Font = Enum.Font.GothamBold
UI.characterTitle.TextXAlignment = Enum.TextXAlignment.Left
UI.characterTitle.LayoutOrder = 1
UI.characterTitle.Parent = characterContent

UI.walkSpeedButton = createPageButton(
	characterContent,
	"Walk Speed: OFF",
	2
)

local walkSpeedLabel,
	walkSlider,
	walkFill,
	walkKnob = createSliderGroup(
		characterContent,
		"Walk Speed: " .. Config.WalkSpeed,
		3
	)

UI.lockWalkSpeedButton = createPageButton(
	characterContent,
	"Lock Walk Speed: ON",
	4
)

UI.infiniteJumpButton = createPageButton(
	characterContent,
	"Infinite Jump: OFF",
	5
)

UI.instantPromptButton = createPageButton(
	characterContent,
	"Instant Prompt: OFF",
	6
)

Noclip.Button = createPageButton(
	characterContent,
	"Noclip: OFF",
	7
)
UI.flyButton = createPageButton(
	characterContent,
	"Fly: OFF",
	8
)

local flySpeedLabel,
	flySpeedSlider,
	flyFill,
	flyKnob = createSliderGroup(
		characterContent,
		"Fly Speed: " .. Config.FlySpeed,
		9
	)

UI.flyInfoLabel = Instance.new("TextLabel")
UI.flyInfoLabel.Size = UDim2.new(1, 0, 0, 65)
UI.flyInfoLabel.BackgroundTransparency = 1
UI.flyInfoLabel.Text =
	"Fly Controls\nW A S D = เคลื่อนที่\nSpace = ขึ้น | Ctrl = ลง"
UI.flyInfoLabel.TextColor3 = Color3.fromRGB(165, 165, 175)
UI.flyInfoLabel.TextSize = 13
UI.flyInfoLabel.Font = Enum.Font.Gotham
UI.flyInfoLabel.TextWrapped = true
UI.flyInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
UI.flyInfoLabel.LayoutOrder = 10
UI.flyInfoLabel.Parent = characterContent


--==================================================
-- [18] CHARACTER GUI UPDATE
--==================================================

local function updateCharacterInterface()
	if scriptClosed then
		return
	end

	setButtonState(
		UI.walkSpeedButton,
		"Walk Speed",
		Config.WalkSpeedEnabled
	)

	setButtonState(
		UI.lockWalkSpeedButton,
		"Lock Walk Speed",
		Config.LockWalkSpeed
	)

	setButtonState(
		UI.infiniteJumpButton,
		"Infinite Jump",
		Config.InfiniteJump
	)
	setButtonState(
		Noclip.Button,
		"Noclip",
		Config.NoclipEnabled
	)

	setButtonState(
		UI.instantPromptButton,
		"Instant Prompt",
		Config.InstantPrompt
	)
	setButtonState(
		UI.flyButton,
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
	local width = flySpeedSlider.AbsoluteSize.X

	if width <= 0 then
		return
	end

	local percent = math.clamp(
		(position.X - flySpeedSlider.AbsolutePosition.X) / width,
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

UI.State.draggingWalkSlider = false
UI.State.draggingFlySlider = false

local function beginWalkSlider(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		UI.State.draggingWalkSlider = true
		setWalkSpeedFromPosition(input.Position)
	end
end

local function beginFlySlider(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		UI.State.draggingFlySlider = true
		setFlySpeedFromPosition(input.Position)
	end
end

addConnection(walkSlider.InputBegan:Connect(beginWalkSlider))
addConnection(walkKnob.InputBegan:Connect(beginWalkSlider))

addConnection(flySpeedSlider.InputBegan:Connect(beginFlySlider))
addConnection(flyKnob.InputBegan:Connect(beginFlySlider))

addConnection(UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then

		return
	end

	if UI.State.draggingWalkSlider then
		setWalkSpeedFromPosition(input.Position)
	end

	if UI.State.draggingFlySlider then
		setFlySpeedFromPosition(input.Position)
	end
end))

addConnection(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		UI.State.draggingWalkSlider = false
		UI.State.draggingFlySlider = false
	end
end))


--==================================================
-- [21] CHARACTER BUTTON EVENTS
--==================================================

addConnection(UI.walkSpeedButton.MouseButton1Click:Connect(function()
	Config.WalkSpeedEnabled =
		not Config.WalkSpeedEnabled

	applyWalkSpeed()
	updateCharacterInterface()
end))

addConnection(UI.lockWalkSpeedButton.MouseButton1Click:Connect(function()
	Config.LockWalkSpeed =
		not Config.LockWalkSpeed

	applyWalkSpeed()
	updateCharacterInterface()
end))

addConnection(UI.infiniteJumpButton.MouseButton1Click:Connect(function()
	Config.InfiniteJump =
		not Config.InfiniteJump

	updateCharacterInterface()
end))

addConnection(UI.flyButton.MouseButton1Click:Connect(function()
	setFlyEnabled(not Config.FlyEnabled)
	updateCharacterInterface()
end))

addConnection(UI.instantPromptButton.MouseButton1Click:Connect(function()
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

UI.worldTitle = Instance.new("TextLabel")
UI.worldTitle.Size = UDim2.new(1, 0, 0, 35)
UI.worldTitle.BackgroundTransparency = 1
UI.worldTitle.Text = "Teleport to Player"
UI.worldTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
UI.worldTitle.TextSize = 20
UI.worldTitle.Font = Enum.Font.GothamBold
UI.worldTitle.TextXAlignment = Enum.TextXAlignment.Left
UI.worldTitle.LayoutOrder = 1
UI.worldTitle.Parent = worldContent

UI.playerListFrame = Instance.new("ScrollingFrame")
UI.playerListFrame.Name = "PlayerList"
UI.playerListFrame.Size = UDim2.new(1, 0, 0, 230)
UI.playerListFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 43)
UI.playerListFrame.BorderSizePixel = 0
UI.playerListFrame.ScrollBarThickness = 5
UI.playerListFrame.ScrollBarImageColor3 =
	Color3.fromRGB(110, 110, 125)
UI.playerListFrame.AutomaticCanvasSize =
	Enum.AutomaticSize.Y
UI.playerListFrame.CanvasSize = UDim2.fromOffset(0, 0)
UI.playerListFrame.ScrollingDirection =
	Enum.ScrollingDirection.Y
UI.playerListFrame.LayoutOrder = 2
UI.playerListFrame.Parent = worldContent

UI.playerListCorner = Instance.new("UICorner")
UI.playerListCorner.CornerRadius = UDim.new(0, 8)
UI.playerListCorner.Parent = UI.playerListFrame

UI.playerListLayout = Instance.new("UIListLayout")
UI.playerListLayout.Padding = UDim.new(0, 6)
UI.playerListLayout.SortOrder = Enum.SortOrder.Name
UI.playerListLayout.Parent = UI.playerListFrame

UI.playerListPadding = Instance.new("UIPadding")
UI.playerListPadding.PaddingTop = UDim.new(0, 8)
UI.playerListPadding.PaddingBottom = UDim.new(0, 8)
UI.playerListPadding.PaddingLeft = UDim.new(0, 8)
UI.playerListPadding.PaddingRight = UDim.new(0, 8)
UI.playerListPadding.Parent = UI.playerListFrame

UI.teleportButton = createPageButton(
	worldContent,
	"Teleport",
	3
)

UI.refreshButton = createPageButton(
	worldContent,
	"Refresh Player List",
	4
)

UI.statusLabel = Instance.new("TextLabel")
UI.statusLabel.Size = UDim2.new(1, 0, 0, 45)
UI.statusLabel.BackgroundTransparency = 1
UI.statusLabel.Text = "ยังไม่ได้เลือกผู้เล่น"
UI.statusLabel.TextColor3 = Color3.fromRGB(175, 175, 185)
UI.statusLabel.TextSize = 13
UI.statusLabel.Font = Enum.Font.Gotham
UI.statusLabel.TextWrapped = true
UI.statusLabel.TextXAlignment = Enum.TextXAlignment.Left
UI.statusLabel.LayoutOrder = 5
UI.statusLabel.Parent = worldContent


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
	for _, child in ipairs(UI.playerListFrame:GetChildren()) do
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
		button.Parent = UI.playerListFrame

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 7)
		corner.Parent = button

		playerButtons[targetPlayer.Name] = button

		button.MouseButton1Click:Connect(function()
			selectedPlayerName = targetPlayer.Name

			UI.statusLabel.Text =
				"เลือก: "
				.. targetPlayer.DisplayName
				.. " (@"
				.. targetPlayer.Name
				.. ")"

			UI.statusLabel.TextColor3 =
				Color3.fromRGB(175, 175, 185)

			updatePlayerButtonStyles()
		end)
	end

	if #availablePlayers == 0 then
		selectedPlayerName = nil
		UI.statusLabel.Text =
			"ไม่พบผู้เล่นคนอื่นในเซิร์ฟเวอร์"
	end
end


--==================================================
-- [24] WORLD BUTTON EVENTS
--==================================================

addConnection(UI.teleportButton.MouseButton1Click:Connect(function()
	if not selectedPlayerName then
		UI.statusLabel.Text = "กรุณาเลือกผู้เล่นก่อน"
		UI.statusLabel.TextColor3 =
			Color3.fromRGB(235, 100, 100)
		return
	end

	local targetPlayer =
		Players:FindFirstChild(selectedPlayerName)

	local success, message =
		teleportToPlayer(targetPlayer)

	UI.statusLabel.Text = message

	if success then
		UI.statusLabel.TextColor3 =
			Color3.fromRGB(90, 220, 130)
	else
		UI.statusLabel.TextColor3 =
			Color3.fromRGB(235, 100, 100)
	end
end))

addConnection(UI.refreshButton.MouseButton1Click:Connect(function()
	selectedPlayerName = nil

	UI.statusLabel.Text = "กำลังรีเฟรชรายชื่อ..."
	UI.statusLabel.TextColor3 =
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

UI.positionTitle = Instance.new("TextLabel")
UI.positionTitle.Size = UDim2.new(1, 0, 0, 35)
UI.positionTitle.BackgroundTransparency = 1
UI.positionTitle.Text = "Saved Positions"
UI.positionTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
UI.positionTitle.TextSize = 20
UI.positionTitle.Font = Enum.Font.GothamBold
UI.positionTitle.TextXAlignment = Enum.TextXAlignment.Left
UI.positionTitle.LayoutOrder = 1
UI.positionTitle.Parent = positionContent

-- กลุ่มเพิ่มจุดใหม่
UI.addPositionGroup = Instance.new("Frame")
UI.addPositionGroup.Size = UDim2.new(1, 0, 0, 96)
UI.addPositionGroup.BackgroundColor3 = Color3.fromRGB(35, 35, 43)
UI.addPositionGroup.BorderSizePixel = 0
UI.addPositionGroup.LayoutOrder = 2
UI.addPositionGroup.Parent = positionContent

UI.addPositionCorner = Instance.new("UICorner")
UI.addPositionCorner.CornerRadius = UDim.new(0, 8)
UI.addPositionCorner.Parent = UI.addPositionGroup

UI.positionNameInput = Instance.new("TextBox")
UI.positionNameInput.Name = "PositionNameInput"
UI.positionNameInput.Size = UDim2.new(1, -20, 0, 38)
UI.positionNameInput.Position = UDim2.fromOffset(10, 9)
UI.positionNameInput.BackgroundColor3 = Color3.fromRGB(52, 52, 63)
UI.positionNameInput.BorderSizePixel = 0
UI.positionNameInput.Text = ""
UI.positionNameInput.PlaceholderText = "ชื่อจุด เช่น บ้าน, ร้านค้า, จุดเกิด"
UI.positionNameInput.PlaceholderColor3 = Color3.fromRGB(145, 145, 155)
UI.positionNameInput.TextColor3 = Color3.fromRGB(255, 255, 255)
UI.positionNameInput.TextSize = 14
UI.positionNameInput.Font = Enum.Font.Gotham
UI.positionNameInput.ClearTextOnFocus = false
UI.positionNameInput.Parent = UI.addPositionGroup

UI.positionNameCorner = Instance.new("UICorner")
UI.positionNameCorner.CornerRadius = UDim.new(0, 7)
UI.positionNameCorner.Parent = UI.positionNameInput

UI.addPositionButton = Instance.new("TextButton")
UI.addPositionButton.Name = "AddPositionButton"
UI.addPositionButton.Size = UDim2.new(1, -20, 0, 34)
UI.addPositionButton.Position = UDim2.fromOffset(10, 54)
UI.addPositionButton.BackgroundColor3 = Color3.fromRGB(40, 165, 90)
UI.addPositionButton.BorderSizePixel = 0
UI.addPositionButton.Text = "Add Current Position"
UI.addPositionButton.TextColor3 = Color3.fromRGB(255, 255, 255)
UI.addPositionButton.TextSize = 14
UI.addPositionButton.Font = Enum.Font.GothamBold
UI.addPositionButton.Parent = UI.addPositionGroup

UI.addPositionButtonCorner = Instance.new("UICorner")
UI.addPositionButtonCorner.CornerRadius = UDim.new(0, 7)
UI.addPositionButtonCorner.Parent = UI.addPositionButton

UI.positionStatusLabel = Instance.new("TextLabel")
UI.positionStatusLabel.Size = UDim2.new(1, 0, 0, 35)
UI.positionStatusLabel.BackgroundTransparency = 1
UI.positionStatusLabel.Text = "ยังไม่มีจุดที่บันทึก"
UI.positionStatusLabel.TextColor3 = Color3.fromRGB(175, 175, 185)
UI.positionStatusLabel.TextSize = 13
UI.positionStatusLabel.Font = Enum.Font.Gotham
UI.positionStatusLabel.TextWrapped = true
UI.positionStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
UI.positionStatusLabel.LayoutOrder = 3
UI.positionStatusLabel.Parent = positionContent

-- Container แสดงรายการจุด
UI.positionList = Instance.new("Frame")
UI.positionList.Name = "PositionList"
UI.positionList.Size = UDim2.new(1, 0, 0, 0)
UI.positionList.AutomaticSize = Enum.AutomaticSize.Y
UI.positionList.BackgroundTransparency = 1
UI.positionList.LayoutOrder = 4
UI.positionList.Parent = positionContent

UI.positionListLayout = Instance.new("UIListLayout")
UI.positionListLayout.Padding = UDim.new(0, 8)
UI.positionListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UI.positionListLayout.Parent = UI.positionList

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
		UI.positionStatusLabel.Text = "ยังไม่มีจุดที่บันทึก"
		UI.positionStatusLabel.TextColor3 =
			Color3.fromRGB(175, 175, 185)
	else
		UI.positionStatusLabel.Text =
			"บันทึกทั้งหมด " .. tostring(count) .. " จุด"

		UI.positionStatusLabel.TextColor3 =
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
	row.Parent = UI.positionList

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

		UI.positionStatusLabel.Text =
			"แก้ชื่อเป็น \"" .. newName .. "\" แล้ว"

		UI.positionStatusLabel.TextColor3 =
			Color3.fromRGB(90, 220, 130)
	end)

	goButton.MouseButton1Click:Connect(function()
		local savedData = findSavedPositionById(data.Id)

		if not savedData then
			UI.positionStatusLabel.Text = "ไม่พบจุดนี้"
			UI.positionStatusLabel.TextColor3 =
				Color3.fromRGB(235, 100, 100)
			return
		end

		local success, message =
			teleportToCFrame(savedData.CFrame)

		if success then
			UI.positionStatusLabel.Text =
				message .. ": " .. savedData.Name

			UI.positionStatusLabel.TextColor3 =
				Color3.fromRGB(90, 220, 130)
		else
			UI.positionStatusLabel.Text = message
			UI.positionStatusLabel.TextColor3 =
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

		UI.positionStatusLabel.Text =
			"ลบ \"" .. deletedName .. "\" แล้ว"

		UI.positionStatusLabel.TextColor3 =
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

addConnection(UI.addPositionButton.MouseButton1Click:Connect(function()
	local rootPart = getRootPart()

	if not rootPart then
		UI.positionStatusLabel.Text =
			"ไม่พบ HumanoidRootPart ของตัวละคร"

		UI.positionStatusLabel.TextColor3 =
			Color3.fromRGB(235, 100, 100)

		return
	end

	local enteredName = string.gsub(
		UI.positionNameInput.Text,
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

	UI.positionNameInput.Text = ""

	refreshPositionList()

	UI.positionStatusLabel.Text =
		"เพิ่มจุด \"" .. enteredName .. "\" แล้ว"

	UI.positionStatusLabel.TextColor3 =
		Color3.fromRGB(90, 220, 130)
end))

addConnection(UI.positionNameInput.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		UI.addPositionButton:Activate()
	end
end))

--==================================================
-- [24.4] DAMAGE TAB GUI
--==================================================

UI.damageTitle = Instance.new("TextLabel")
UI.damageTitle.Size = UDim2.new(1, 0, 0, 35)
UI.damageTitle.BackgroundTransparency = 1
UI.damageTitle.Text = "Damage / Auto Attack"
UI.damageTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
UI.damageTitle.TextSize = 20
UI.damageTitle.Font = Enum.Font.GothamBold
UI.damageTitle.TextXAlignment = Enum.TextXAlignment.Left
UI.damageTitle.LayoutOrder = 1
UI.damageTitle.Parent = damageContent

UI.autoAttackButton = createPageButton(
	damageContent,
	"Auto Attack: OFF",
	2
)

local attackRadiusLabel,
	attackRadiusSlider,
	attackRadiusFill,
	attackRadiusKnob = createSliderGroup(
		damageContent,
		"Attack Radius: " .. Config.AttackRadius,
		3
	)

local attackSpeedLabel,
	attackSpeedSlider,
	attackSpeedFill,
	attackSpeedKnob = createSliderGroup(
		damageContent,
		"Attack Interval: " .. Config.AttackInterval,
		4
	)

UI.onlyNPCButton = createPageButton(
	damageContent,
	"Only NPC: ON",
	5
)

UI.lockRadiusButton = createPageButton(
	damageContent,
	"Lock Radius: ON",
	5
)


UI.damageInfoLabel = Instance.new("TextLabel")
UI.damageInfoLabel.Size = UDim2.new(1, 0, 0, 90)
UI.damageInfoLabel.BackgroundTransparency = 1
UI.damageInfoLabel.Text =
	"Auto Attack จะทำงานเฉพาะตอนถือ Tool\n"
	.. "Radius = ระยะตรวจหาเป้าหมาย\n"
	.. "Interval ต่ำ = โจมตีเร็วขึ้น"
UI.damageInfoLabel.TextColor3 = Color3.fromRGB(165, 165, 175)
UI.damageInfoLabel.TextSize = 13
UI.damageInfoLabel.Font = Enum.Font.Gotham
UI.damageInfoLabel.TextWrapped = true
UI.damageInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
UI.damageInfoLabel.LayoutOrder = 6
UI.damageInfoLabel.Parent = damageContent

local function updateDamageInterface()
	if scriptClosed then
		return
	end

	setButtonState(
		UI.autoAttackButton,
		"Auto Attack",
		Config.AutoAttackEnabled
	)

	setButtonState(
		UI.onlyNPCButton,
		"Only NPC",
		Config.OnlyNPC
	)

	setButtonState(
		UI.lockRadiusButton,
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

UI.State.draggingAttackRadiusSlider = false
UI.State.draggingAttackSpeedSlider = false

local function beginAttackRadiusSlider(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		UI.State.draggingAttackRadiusSlider = true
		setAttackRadiusFromPosition(input.Position)
	end
end

local function beginAttackSpeedSlider(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		UI.State.draggingAttackSpeedSlider = true
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

	if UI.State.draggingAttackRadiusSlider then
		setAttackRadiusFromPosition(input.Position)
	end

	if UI.State.draggingAttackSpeedSlider then
		setAttackSpeedFromPosition(input.Position)
	end
end))

addConnection(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		UI.State.draggingAttackRadiusSlider = false
		UI.State.draggingAttackSpeedSlider = false
	end
end))

addConnection(UI.autoAttackButton.MouseButton1Click:Connect(function()
	setAutoAttackEnabled(
		not Config.AutoAttackEnabled
	)

	updateDamageInterface()
end))

addConnection(UI.onlyNPCButton.MouseButton1Click:Connect(function()
	Config.OnlyNPC = not Config.OnlyNPC

	updateDamageInterface()
end))

addConnection(UI.lockRadiusButton.MouseButton1Click:Connect(function()
	setRadiusLockEnabled(
		not Config.LockAttackRadius
	)

	updateDamageInterface()
end))


--==================================================
-- [24.5] AUTO CLICK TAB GUI
--==================================================

UI.autoClickTitle = Instance.new("TextLabel")
UI.autoClickTitle.Size = UDim2.new(1, 0, 0, 35)
UI.autoClickTitle.BackgroundTransparency = 1
UI.autoClickTitle.Text = "Auto Click"
UI.autoClickTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
UI.autoClickTitle.TextSize = 20
UI.autoClickTitle.Font = Enum.Font.GothamBold
UI.autoClickTitle.TextXAlignment = Enum.TextXAlignment.Left
UI.autoClickTitle.LayoutOrder = 1
UI.autoClickTitle.Parent = autoClickContent

UI.autoClickButton = createPageButton(
	autoClickContent,
	"Auto Click: OFF",
	2
)

local autoClickSpeedLabel,
	autoClickSpeedSlider,
	autoClickSpeedFill,
	autoClickSpeedKnob = createSliderGroup(
	autoClickContent,
	"Click Interval: "
		.. string.format("%.2f", Config.AutoClickInterval),
	3
)

UI.autoClickInfoLabel = Instance.new("TextLabel")
UI.autoClickInfoLabel.Size = UDim2.new(1, 0, 0, 90)
UI.autoClickInfoLabel.BackgroundTransparency = 1
UI.autoClickInfoLabel.Text =
	"กด G เพื่อเปิดหรือปิด Auto Click\n"
	.. "ทำงานเฉพาะตอนถือ Tool\n"
	.. "0.01 = คลิกเร็วที่สุด"
UI.autoClickInfoLabel.TextColor3 =
	Color3.fromRGB(165, 165, 175)
UI.autoClickInfoLabel.TextSize = 13
UI.autoClickInfoLabel.Font = Enum.Font.Gotham
UI.autoClickInfoLabel.TextWrapped = true
UI.autoClickInfoLabel.TextXAlignment =
	Enum.TextXAlignment.Left
UI.autoClickInfoLabel.LayoutOrder = 4
UI.autoClickInfoLabel.Parent = autoClickContent

local function updateAutoClickInterface()
	if scriptClosed then
		return
	end

	setButtonState(
		UI.autoClickButton,
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

UI.State.draggingAutoClickSlider = false

local function beginAutoClickSlider(input)
	if input.UserInputType
			== Enum.UserInputType.MouseButton1
		or input.UserInputType
			== Enum.UserInputType.Touch then

		UI.State.draggingAutoClickSlider = true
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

	if UI.State.draggingAutoClickSlider then
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

		UI.State.draggingAutoClickSlider = false
	end
end))

addConnection(UI.autoClickButton.MouseButton1Click:Connect(function()
	toggleAutoClick()
	updateAutoClickInterface()
end))


do
	--==================================================
	-- [24.6] AUTO E / CRYSTALS / FIND CRYSTALS GUI
	--==================================================

	local autoEButton = createPageButton(
		autoClickContent,
		"Auto E: OFF",
		5
	)

	local autoEInfoLabel = Instance.new("TextLabel")
	autoEInfoLabel.Size = UDim2.new(1, 0, 0, 58)
	autoEInfoLabel.BackgroundTransparency = 1
	autoEInfoLabel.Text =
		"Auto E กด ProximityPrompt ปุ่ม E อัตโนมัติ\n"
		.. "กด R เพื่อเปิด/ปิด | Interval: "
		.. string.format("%.2f", Config.AutoEInterval)
	autoEInfoLabel.TextColor3 =
		Color3.fromRGB(165, 165, 175)
	autoEInfoLabel.TextSize = 13
	autoEInfoLabel.Font = Enum.Font.Gotham
	autoEInfoLabel.TextWrapped = true
	autoEInfoLabel.TextXAlignment =
		Enum.TextXAlignment.Left
	autoEInfoLabel.LayoutOrder = 6
	autoEInfoLabel.Parent = autoClickContent

	function Addons.updateAutoEInterface()
		setButtonState(
			autoEButton,
			"Auto E",
			Config.AutoEEnabled
		)
	end

	addConnection(autoEButton.MouseButton1Click:Connect(function()
		Addons.setAutoEEnabled(not Config.AutoEEnabled)
		Addons.updateAutoEInterface()
	end))

	local crystalsTitle = Instance.new("TextLabel")
	crystalsTitle.Size = UDim2.new(1, 0, 0, 35)
	crystalsTitle.BackgroundTransparency = 1
	crystalsTitle.Text = "Crystals"
	crystalsTitle.TextColor3 =
		Color3.fromRGB(255, 255, 255)
	crystalsTitle.TextSize = 20
	crystalsTitle.Font = Enum.Font.GothamBold
	crystalsTitle.TextXAlignment =
		Enum.TextXAlignment.Left
	crystalsTitle.LayoutOrder = 1
	crystalsTitle.Parent = crystalsContent

	local removeLightButton = createPageButton(
		crystalsContent,
		"Remove Crystal Light: ON",
		2
	)

	local removeLowPriceButton = createPageButton(
		crystalsContent,
		"Remove Low Price Crystals: OFF",
		3
	)

	local crystalPriceInput = Instance.new("TextBox")
	crystalPriceInput.Size = UDim2.new(1, 0, 0, 42)
	crystalPriceInput.BackgroundColor3 =
		Color3.fromRGB(52, 52, 63)
	crystalPriceInput.BorderSizePixel = 0
	crystalPriceInput.Text =
		tostring(Config.MinimumCrystalPrice)
	crystalPriceInput.PlaceholderText =
		"ราคาขั้นต่ำ เช่น 10000000 หรือ 10M"
	crystalPriceInput.TextColor3 =
		Color3.fromRGB(255, 255, 255)
	crystalPriceInput.PlaceholderColor3 =
		Color3.fromRGB(145, 145, 155)
	crystalPriceInput.TextSize = 14
	crystalPriceInput.Font = Enum.Font.Gotham
	crystalPriceInput.ClearTextOnFocus = false
	crystalPriceInput.LayoutOrder = 4
	crystalPriceInput.Parent = crystalsContent

	Instance.new("UICorner", crystalPriceInput).CornerRadius =
		UDim.new(0, 8)

	local applyPriceButton = createPageButton(
		crystalsContent,
		"Apply Minimum Price",
		5
	)

	local crystalStatus = Instance.new("TextLabel")
	crystalStatus.Size = UDim2.new(1, 0, 0, 65)
	crystalStatus.BackgroundTransparency = 1
	crystalStatus.Text =
		"Remove Light: ON | Low Price: OFF"
	crystalStatus.TextColor3 =
		Color3.fromRGB(175, 175, 185)
	crystalStatus.TextSize = 13
	crystalStatus.Font = Enum.Font.Gotham
	crystalStatus.TextWrapped = true
	crystalStatus.TextXAlignment =
		Enum.TextXAlignment.Left
	crystalStatus.LayoutOrder = 6
	crystalStatus.Parent = crystalsContent

	function Addons.updateCrystalsInterface()
		setButtonState(
			removeLightButton,
			"Remove Crystal Light",
			Config.RemoveCrystalLightEnabled
		)

		setButtonState(
			removeLowPriceButton,
			"Remove Low Price Crystals",
			Config.RemoveLowPriceCrystalsEnabled
		)
	end

	local function applyPriceInput()
		local value = Addons.parseCrystalValue(crystalPriceInput.Text)

		if not value then
			crystalStatus.Text = "กรุณากรอกราคาที่ถูกต้อง"
			crystalStatus.TextColor3 =
				Color3.fromRGB(235, 100, 100)
			return
		end

		Config.MinimumCrystalPrice =
			math.max(0, math.floor(value))

		crystalPriceInput.Text =
			tostring(Config.MinimumCrystalPrice)

		local checked, hidden, noValue =
			Addons.applyLowPriceFilter()

		crystalStatus.Text = string.format(
			"ตรวจ %d | ซ่อน %d | ไม่พบค่า %d",
			checked,
			hidden,
			noValue
		)

		crystalStatus.TextColor3 =
			Color3.fromRGB(90, 220, 130)
	end

	addConnection(removeLightButton.MouseButton1Click:Connect(function()
		Config.RemoveCrystalLightEnabled =
			not Config.RemoveCrystalLightEnabled

		if Config.RemoveCrystalLightEnabled then
			local changed = Addons.applyCrystalLights()
			crystalStatus.Text =
				"ปิดแสง Crystal: "
				.. tostring(changed)
		else
			Addons.restoreCrystalLights()
			crystalStatus.Text = "คืนค่าแสง Crystal แล้ว"
		end

		Addons.updateCrystalsInterface()
	end))

	addConnection(removeLowPriceButton.MouseButton1Click:Connect(function()
		Config.RemoveLowPriceCrystalsEnabled =
			not Config.RemoveLowPriceCrystalsEnabled

		if Config.RemoveLowPriceCrystalsEnabled then
			applyPriceInput()
		else
			Addons.restoreAllCrystals()
			crystalStatus.Text =
				"คืนค่า Crystal ที่ซ่อนแล้ว"
		end

		Addons.updateCrystalsInterface()
	end))

	addConnection(applyPriceButton.MouseButton1Click:Connect(
		applyPriceInput
	))

	addConnection(crystalPriceInput.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			applyPriceInput()
		end
	end))

	local findCrystalsTitle = Instance.new("TextLabel")
	findCrystalsTitle.Size = UDim2.new(1, 0, 0, 35)
	findCrystalsTitle.BackgroundTransparency = 1
	findCrystalsTitle.Text = "Find Crystals"
	findCrystalsTitle.TextColor3 =
		Color3.fromRGB(255, 255, 255)
	findCrystalsTitle.TextSize = 20
	findCrystalsTitle.Font = Enum.Font.GothamBold
	findCrystalsTitle.TextXAlignment =
		Enum.TextXAlignment.Left
	findCrystalsTitle.LayoutOrder = 1
	findCrystalsTitle.Parent = findCrystalsContent

	local boulderESPButton = createPageButton(
		findCrystalsContent,
		"Boulder ESP: ON",
		2
	)

	local boulderESPStatus = Instance.new("TextLabel")
	boulderESPStatus.Size = UDim2.new(1, 0, 0, 70)
	boulderESPStatus.BackgroundTransparency = 1
	boulderESPStatus.Text =
		"Highlight หินใน MountainDecorations > Boulders"
	boulderESPStatus.TextColor3 =
		Color3.fromRGB(175, 175, 185)
	boulderESPStatus.TextSize = 13
	boulderESPStatus.Font = Enum.Font.Gotham
	boulderESPStatus.TextWrapped = true
	boulderESPStatus.TextXAlignment =
		Enum.TextXAlignment.Left
	boulderESPStatus.LayoutOrder = 3
	boulderESPStatus.Parent = findCrystalsContent

	function Addons.updateFindCrystalsInterface()
		setButtonState(
			boulderESPButton,
			"Boulder ESP",
			Config.BoulderESPEnabled
		)
	end

	addConnection(boulderESPButton.MouseButton1Click:Connect(function()
		Addons.setBoulderESPEnabled(not Config.BoulderESPEnabled)

		if Config.BoulderESPEnabled then
			boulderESPStatus.Text =
				"เปิด Boulder ESP แล้ว: "
				.. tostring(Addons.scanBoulderESP())
				.. " Object"
		else
			boulderESPStatus.Text =
				"ปิด Boulder ESP แล้ว"
		end

		Addons.updateFindCrystalsInterface()
	end))

end

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
	Addons.updateAutoEInterface()
end))

addConnection(crystalsTab.MouseButton1Click:Connect(function()
	showTab("Crystals")
	Addons.updateCrystalsInterface()
end))

addConnection(findCrystalsTab.MouseButton1Click:Connect(function()
	showTab("Find Crystals")
	Addons.updateFindCrystalsInterface()
end))


--==================================================
-- [26] MINIMIZE LOGO
--==================================================

UI.logoButton = Instance.new("ImageButton")
UI.logoButton.Name = "LogoButton"
UI.logoButton.Size = UDim2.fromOffset(62, 62)
UI.logoButton.AnchorPoint = Vector2.new(0.5, 0)
UI.logoButton.Position = UDim2.new(0.5, 0, 0, 100)
UI.logoButton.BackgroundColor3 = Color3.fromRGB(25, 25, 31)
UI.logoButton.BorderSizePixel = 0
UI.logoButton.Image = LOGO_ASSET_ID
UI.logoButton.ScaleType = Enum.ScaleType.Fit
UI.logoButton.Visible = false
UI.logoButton.Active = true
UI.logoButton.ZIndex = 1000
UI.logoButton.Parent = UI.screenGui

UI.logoCorner = Instance.new("UICorner")
UI.logoCorner.CornerRadius = UDim.new(1, 0)
UI.logoCorner.Parent = UI.logoButton

UI.logoStroke = Instance.new("UIStroke")
UI.logoStroke.Color = Color3.fromRGB(90, 90, 105)
UI.logoStroke.Thickness = 2
UI.logoStroke.Parent = UI.logoButton

UI.logoPadding = Instance.new("UIPadding")
UI.logoPadding.PaddingTop = UDim.new(0, 7)
UI.logoPadding.PaddingBottom = UDim.new(0, 7)
UI.logoPadding.PaddingLeft = UDim.new(0, 7)
UI.logoPadding.PaddingRight = UDim.new(0, 7)
UI.logoPadding.Parent = UI.logoButton

local function minimizeMenu()
	if scriptClosed then
		return
	end

	UI.mainFrame.Visible = false

	-- จัดโลโก้ไว้กึ่งกลางด้านบนทุกครั้งที่ย่อ
	UI.logoButton.AnchorPoint = Vector2.new(0.5, 0)
	UI.logoButton.Position = UDim2.new(0.5, 0, 0, 100)

	UI.logoButton.Visible = true
end

local function restoreMenu()
	if scriptClosed then
		return
	end

	UI.mainFrame.Visible = true
	UI.logoButton.Visible = false
end


--==================================================
-- [27] DRAG MAIN WINDOW
--==================================================

UI.State.draggingWindow = false
UI.State.windowDragStart = nil
UI.State.windowStartPosition = nil

addConnection(UI.titleBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		UI.State.draggingWindow = true
		UI.State.windowDragStart = input.Position
		UI.State.windowStartPosition = UI.mainFrame.Position
	end
end))

addConnection(UserInputService.InputChanged:Connect(function(input)
	if not UI.State.draggingWindow then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then

		return
	end

	local delta = input.Position - UI.State.windowDragStart

	UI.mainFrame.Position = UDim2.new(
		UI.State.windowStartPosition.X.Scale,
		UI.State.windowStartPosition.X.Offset + delta.X,
		UI.State.windowStartPosition.Y.Scale,
		UI.State.windowStartPosition.Y.Offset + delta.Y
	)
end))

addConnection(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		UI.State.draggingWindow = false
	end
end))


--==================================================
-- [28] DRAG LOGO
--==================================================

UI.State.draggingLogo = false
UI.State.logoDragStart = nil
UI.State.logoStartPosition = nil
UI.State.logoWasDragged = false

addConnection(UI.logoButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		UI.State.draggingLogo = true
		UI.State.logoWasDragged = false
		UI.State.logoDragStart = input.Position
		UI.State.logoStartPosition = UI.logoButton.Position
	end
end))

addConnection(UserInputService.InputChanged:Connect(function(input)
	if not UI.State.draggingLogo then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then

		return
	end

	local delta = input.Position - UI.State.logoDragStart

	if delta.Magnitude > 5 then
		UI.State.logoWasDragged = true
	end

	UI.logoButton.Position = UDim2.new(
		UI.State.logoStartPosition.X.Scale,
		UI.State.logoStartPosition.X.Offset + delta.X,
		UI.State.logoStartPosition.Y.Scale,
		UI.State.logoStartPosition.Y.Offset + delta.Y
	)
end))

addConnection(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		UI.State.draggingLogo = false
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

	stopAutoAttack()

	Config.LockAttackRadius = false
	stopRadiusLock()

	stopAutoClick()

	Addons.setAutoEEnabled(false)
	table.clear(visibleEPrompts)

	Config.RemoveCrystalLightEnabled = false
	Config.RemoveLowPriceCrystalsEnabled = false
	Addons.stopCrystalLoop()
	Addons.restoreCrystalLights()
	Addons.restoreAllCrystals()

	Addons.setBoulderESPEnabled(false)

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

	if UI.screenGui then
		UI.screenGui:Destroy()
	end
end


--==================================================
-- [30] WINDOW EVENTS
--==================================================

addConnection(UI.minimizeButton.MouseButton1Click:Connect(function()
	minimizeMenu()
end))

addConnection(UI.logoButton.MouseButton1Click:Connect(function()
	if not UI.State.logoWasDragged then
		restoreMenu()
	end
end))

addConnection(UI.closeButton.MouseButton1Click:Connect(function()
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
		if UI.mainFrame.Visible then
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
		return
	end

	-- กด R เพื่อเปิด/ปิด Auto E
	if input.KeyCode == Enum.KeyCode.R then
		Addons.setAutoEEnabled(not Config.AutoEEnabled)
		Addons.updateAutoEInterface()
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
	Addons.updateAutoEInterface()

	Addons.updateCrystalsInterface()
	Addons.updateFindCrystalsInterface()

	if Config.RemoveCrystalLightEnabled then
		Addons.applyCrystalLights()
	end

	if Config.BoulderESPEnabled then
		Addons.setBoulderESPEnabled(true)
	end

	Addons.startCrystalLoop()
end)
