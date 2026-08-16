-- Character + Find Egg UI

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local FLY_RETURN_LEFT = CFrame.new(
	544.8623657226562,
	70.28306579589844,
	-320.2812194824219
)

local FLY_RETURN_RIGHT = CFrame.new(
	546.082763671875,
	70.28306579589844,
	-425.8914794921875
)

local VOLCANO_RETURN_WAYPOINT = CFrame.new(
	1570.1673583984375,
	69.53539276123047,
	-296.7453918457031
)

local ABYSS_COSMIC_RETURN_WAYPOINT = CFrame.new(
	1520.081298828125,
	69.53531646728516,
	-429.0282287597656
)

local ZONES = {
	{Name = "First Zone", MinX = 576.90, MaxX = 619.76},
	{Name = "Lake", MinX = 703.63, MaxX = 772.56},
	{Name = "Desert", MinX = 895.85, MaxX = 966.46},
	{Name = "Jungle", MinX = 1145.36, MaxX = 1207.19},
	{Name = "Snow", MinX = 1422.21, MaxX = 1526.41},
	{Name = "Volcano", MinX = 1789.88, MaxX = 1920.64},
	{Name = "Abyss Ocean", MinX = 2195.42, MaxX = 2340.19},
	{Name = "Prehistoric", MinX = 2709.03, MaxX = 2840.94},
	{Name = "Cosmic", MinX = 3289.73, MaxX = 3456.04},
}

local ZONE_RETURN_WAYPOINTS = {
	["Volcano"] = VOLCANO_RETURN_WAYPOINT,
	["Prehistoric"] = VOLCANO_RETURN_WAYPOINT,
	["Abyss Ocean"] = ABYSS_COSMIC_RETURN_WAYPOINT,
	["Cosmic"] = ABYSS_COSMIC_RETURN_WAYPOINT,
}

local selectedZones = {}
for _, zone in ipairs(ZONES) do
	selectedZones[zone.Name] = true
end

local SIZE_FILTERS = {0, 1, 1.5, 2, 2.5, 3}
local selectedHitboxSize = 2

local Config = {
	ToggleKey = Enum.KeyCode.L,
	WalkSpeedEnabled = false,
	LockWalkSpeed = false,
	WalkSpeed = 50,
	NormalWalkSpeed = 16,
	MinWalkSpeed = 16,
	MaxWalkSpeed = 500,
	InfiniteJump = false,
	NoclipEnabled = false,
	ManualFlyEnabled = false,
	ManualFlySpeed = 60,
	MinManualFlySpeed = 10,
	MaxManualFlySpeed = 500,
	InstantPrompt = false,
	HideAnimalsEnabled = false,
	FindEggEnabled = false,
	FindEggMode = "FLY",
	FindEggSpeed = 700,
	MinFindEggSpeed = 250,
	MaxFindEggSpeed = 700,
	ArrivalDistance = 3,
	EggArrivalDistance = 1,
	CollectWaitTime = 0.35,
	TargetRetryDelay = 0.15,
	TargetRetryLimit = 5,
	ReturnWaitTime = 0.25,
}

local UI = { State = {} }
local connections = {}
local scriptClosed = false
local walkLockConnection
local flyConnection
local flyVelocity
local flyGyro
local findEggRunId = 0
local findEggThread
local noclipOriginal = {}
local noclipConnection
local promptOriginal = {}
local hiddenAnimalTransparency = {}
local hideAnimalsConnection

local function addConnection(connection)
	table.insert(connections, connection)
	return connection
end

local function disconnectAll()
	for _, connection in ipairs(connections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	table.clear(connections)
end

local function getCharacter()
	return player.Character
end

local function getHumanoid()
	local character = getCharacter()
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function getRootPart()
	local character = getCharacter()
	return character and character:FindFirstChild("HumanoidRootPart")
end

-- Walk Speed
local function applyWalkSpeed()
	local humanoid = getHumanoid()
	if humanoid then
		if Config.FindEggEnabled then
			humanoid.WalkSpeed = Config.FindEggSpeed
		else
			humanoid.WalkSpeed = Config.WalkSpeedEnabled
				and Config.WalkSpeed
				or Config.NormalWalkSpeed
		end
	end
end

local function refreshWalkSpeedLock()
	Config.LockWalkSpeed =
		Config.WalkSpeedEnabled or Config.FindEggEnabled

	if walkLockConnection then
		walkLockConnection:Disconnect()
		walkLockConnection = nil
	end

	applyWalkSpeed()

	if Config.LockWalkSpeed then
		walkLockConnection = RunService.Heartbeat:Connect(applyWalkSpeed)
	end
end

local function setWalkSpeedEnabled(enabled)
	Config.WalkSpeedEnabled = enabled
	refreshWalkSpeedLock()
end

-- Infinite Jump
addConnection(UserInputService.JumpRequest:Connect(function()
	if not scriptClosed and Config.InfiniteJump then
		local humanoid = getHumanoid()
		if humanoid then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end
end))

-- Noclip
local function applyNoclip()
	local character = getCharacter()
	if not character then
		return
	end
	for _, object in ipairs(character:GetDescendants()) do
		if object:IsA("BasePart") then
			if noclipOriginal[object] == nil then
				noclipOriginal[object] = object.CanCollide
			end
			object.CanCollide = false
		end
	end
end

local function setNoclipEnabled(enabled)
	Config.NoclipEnabled = enabled
	if noclipConnection then
		noclipConnection:Disconnect()
		noclipConnection = nil
	end
	if enabled then
		applyNoclip()
		noclipConnection = RunService.Stepped:Connect(applyNoclip)
	else
		for part, canCollide in pairs(noclipOriginal) do
			if part and part.Parent then
				part.CanCollide = canCollide
			end
		end
		table.clear(noclipOriginal)
	end
end

-- Instant Prompt
local function applyPrompt(prompt)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	if promptOriginal[prompt] == nil then
		promptOriginal[prompt] = prompt.HoldDuration
	end
	prompt.HoldDuration = 0
end

local function setInstantPromptEnabled(enabled)
	Config.InstantPrompt = enabled
	if enabled then
		for _, object in ipairs(Workspace:GetDescendants()) do
			applyPrompt(object)
		end
	else
		for prompt, duration in pairs(promptOriginal) do
			if prompt and prompt.Parent then
				prompt.HoldDuration = duration
			end
		end
		table.clear(promptOriginal)
	end
end

addConnection(Workspace.DescendantAdded:Connect(function(object)
	if Config.InstantPrompt then
		applyPrompt(object)
	end
end))

-- Hide: ซ่อนชิ้นส่วนภาพภายใน Model ระดับแรกของ ClientRenderedAssets
local function hideAnimalVisual(object)
	if not object then
		return 0
	end

	if not (
		object:IsA("BasePart")
		or object:IsA("Decal")
		or object:IsA("Texture")
	) then
		return 0
	end

	if hiddenAnimalTransparency[object] == nil then
		hiddenAnimalTransparency[object] = object.Transparency
		object.Transparency = 1
		return 1
	end

	object.Transparency = 1
	return 0
end

local function hideAnimalContainer(container)
	if not container then
		return 0
	end

	local hiddenCount = hideAnimalVisual(container)
	for _, descendant in ipairs(container:GetDescendants()) do
		hiddenCount += hideAnimalVisual(descendant)
	end

	return hiddenCount
end

local function setHideAnimalsEnabled(enabled)
	Config.HideAnimalsEnabled = enabled

	if hideAnimalsConnection then
		hideAnimalsConnection:Disconnect()
		hideAnimalsConnection = nil
	end

	if not enabled then
		for object, originalTransparency in pairs(
			hiddenAnimalTransparency
		) do
			if object and object.Parent then
				object.Transparency = originalTransparency
			end
		end
		table.clear(hiddenAnimalTransparency)
		return 0
	end

	local folder = Workspace:FindFirstChild("ClientRenderedAssets")
	if not folder then
		return 0
	end

	local hiddenCount = 0
	for _, object in ipairs(folder:GetChildren()) do
		hiddenCount += hideAnimalContainer(object)
	end

	hideAnimalsConnection = folder.DescendantAdded:Connect(function(object)
		if Config.HideAnimalsEnabled then
			hideAnimalVisual(object)
		end
	end)

	return hiddenCount
end

local function pressEOnce()
	pcall(function()
		VirtualInputManager:SendKeyEvent(
			true,
			Enum.KeyCode.E,
			false,
			game
		)
		task.wait(0.05)
		VirtualInputManager:SendKeyEvent(
			false,
			Enum.KeyCode.E,
			false,
			game
		)
	end)
end

-- Manual Fly
local function stopManualFly()
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

local function startManualFly()
	stopManualFly()
	local root = getRootPart()
	local humanoid = getHumanoid()
	if not root or not humanoid then
		Config.ManualFlyEnabled = false
		return
	end

	humanoid.PlatformStand = true
	humanoid.AutoRotate = false
	flyVelocity = Instance.new("BodyVelocity")
	flyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	flyVelocity.Velocity = Vector3.zero
	flyVelocity.Parent = root
	flyGyro = Instance.new("BodyGyro")
	flyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
	flyGyro.P = 9000
	flyGyro.CFrame = root.CFrame
	flyGyro.Parent = root

	flyConnection = RunService.RenderStepped:Connect(function()
		if scriptClosed or not Config.ManualFlyEnabled or not root.Parent then
			stopManualFly()
			return
		end
		local camera = Workspace.CurrentCamera
		local direction = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then direction += camera.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then direction -= camera.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then direction -= camera.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then direction += camera.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then direction += Vector3.yAxis end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then direction -= Vector3.yAxis end
		flyVelocity.Velocity = direction.Magnitude > 0
			and direction.Unit * Config.ManualFlySpeed
			or Vector3.zero
		flyGyro.CFrame = CFrame.lookAt(root.Position, root.Position + camera.CFrame.LookVector)
	end)
end

local function setManualFlyEnabled(enabled)
	Config.ManualFlyEnabled = enabled
	if enabled then
		startManualFly()
	else
		stopManualFly()
	end
end

-- Find Egg
local function getObjectPosition(object)
	if not object then
		return nil
	end

	if object:IsA("BasePart") then
		return object.Position
	end
	if object:IsA("Model") then
		local ok, pivot = pcall(object.GetPivot, object)
		if ok then
			return pivot.Position
		end
	end
end

local function getZoneFromPosition(position)
	if not position then
		return nil
	end

	for zoneIndex, zone in ipairs(ZONES) do
		if position.X >= zone.MinX and position.X <= zone.MaxX then
			return zoneIndex, zone.Name
		end
	end

	return nil
end

local function getHitboxSize(object)
	if not object then
		return nil
	end

	local hitbox = object.Name == "Hitbox"
		and object:IsA("BasePart")
		and object
		or object:FindFirstChild("Hitbox", true)

	if not hitbox or not hitbox:IsA("BasePart") then
		return nil
	end

	return math.max(
		hitbox.Size.X,
		hitbox.Size.Y,
		hitbox.Size.Z
	)
end

local function hasEggHighlight(object)
	if not object then
		return false
	end

	if object:FindFirstChildWhichIsA("Highlight", true) then
		return true
	end

	-- รองรับกรณี Object ใช้ชื่อ Hilight/Highlight
	for _, descendant in ipairs(object:GetDescendants()) do
		local name = string.lower(descendant.Name)
		if name == "hilight" or name == "highlight" then
			return true
		end
	end

	return false
end

local function getAllEggs()
	local folder = Workspace:FindFirstChild("AreaEggSlotsClient")
	local eggRecords = {}
	if not folder then
		return {}
	end

	for _, object in ipairs(folder:GetChildren()) do
		if object:IsA("Model") or object:IsA("BasePart") then
			local position = getObjectPosition(object)
			local hitboxSize = getHitboxSize(object)
			local hasHighlight = hasEggHighlight(object)

			if position and hitboxSize then

				for zoneIndex, zone in ipairs(ZONES) do
					if selectedZones[zone.Name]
						and position.X >= zone.MinX
						and position.X <= zone.MaxX
						and hitboxSize > selectedHitboxSize then

						table.insert(eggRecords, {
							Object = object,
							HasHighlight = hasHighlight,
							Size = hitboxSize,
							ZoneIndex = zoneIndex,
						})
						break
					end
				end
			end
		end
	end

	table.sort(eggRecords, function(a, b)
		-- ไข่ที่มี Highlight ต้องมาก่อนเสมอ
		if a.HasHighlight ~= b.HasHighlight then
			return a.HasHighlight
		end

		-- ภายในแต่ละกลุ่ม เรียงขนาดใหญ่ไปเล็ก
		if a.Size ~= b.Size then
			return a.Size > b.Size
		end

		-- หากขนาดเท่ากัน ให้ Zone หลังสุดมาก่อน
		if a.ZoneIndex ~= b.ZoneIndex then
			return a.ZoneIndex > b.ZoneIndex
		end

		return a.Object.Name < b.Object.Name
	end)

	local eggs = {}
	for _, record in ipairs(eggRecords) do
		table.insert(eggs, record.Object)
	end

	return eggs
end

local function runToCFrame(targetCFrame, runId, arrivalDistance)
	local root = getRootPart()
	local humanoid = getHumanoid()
	if not root or not humanoid then
		return false
	end

	local targetPosition = targetCFrame.Position
	local reachDistance = arrivalDistance or Config.ArrivalDistance
	local startingDistance = (targetPosition - root.Position).Magnitude
	local timeout = math.max(
		15,
		(startingDistance / Config.FindEggSpeed) * 4 + 5
	)
	local startedAt = os.clock()
	local lastMoveAt = 0
	humanoid.WalkSpeed = Config.FindEggSpeed
	humanoid:MoveTo(targetPosition)

	while Config.FindEggEnabled and runId == findEggRunId and root.Parent do
		local offset = targetPosition - root.Position
		local distance = offset.Magnitude
		if distance <= reachDistance then
			root.AssemblyLinearVelocity = Vector3.zero
			humanoid:MoveTo(root.Position)
			return true
		end

		if os.clock() - startedAt >= timeout then
			humanoid:MoveTo(root.Position)
			return false
		end

		if os.clock() - lastMoveAt >= 0.25 then
			humanoid.WalkSpeed = Config.FindEggSpeed
			humanoid:MoveTo(targetPosition)
			lastMoveAt = os.clock()
		end

		RunService.Heartbeat:Wait()
	end

	humanoid:MoveTo(root.Position)
	return false
end

local function getLowFlyY(position, root, humanoid)
	local character = getCharacter()
	local eggFolder = Workspace:FindFirstChild("AreaEggSlotsClient")
	local excluded = {}
	if character then table.insert(excluded, character) end
	if eggFolder then table.insert(excluded, eggFolder) end
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = excluded
	raycastParams.IgnoreWater = false

	local origin = Vector3.new(position.X, position.Y + 100, position.Z)
	local result = Workspace:Raycast(
		origin,
		Vector3.new(0, -500, 0),
		raycastParams
	)

	if not result then
		return position.Y
	end

	-- ลดระดับบินลงจากค่าเดิมอีก 2 studs
	return result.Position.Y
		+ humanoid.HipHeight
		+ (root.Size.Y / 2)
		- 1
end

local function flyLowToCFrame(targetCFrame, runId, arrivalDistance)
	local root = getRootPart()
	local humanoid = getHumanoid()
	if not root or not humanoid then
		return false
	end

	local targetPosition = targetCFrame.Position
	local reachDistance = arrivalDistance or Config.ArrivalDistance
	humanoid:MoveTo(root.Position)
	humanoid.AutoRotate = false

	while Config.FindEggEnabled and runId == findEggRunId and root.Parent do
		local flatOffset = Vector3.new(
			targetPosition.X - root.Position.X,
			0,
			targetPosition.Z - root.Position.Z
		)
		local distance = flatOffset.Magnitude

		if distance <= reachDistance then
			local finalY = getLowFlyY(targetPosition, root, humanoid)
			root.AssemblyLinearVelocity = Vector3.zero
			root.CFrame = CFrame.new(
				targetPosition.X,
				finalY,
				targetPosition.Z
			)
			humanoid.AutoRotate = true
			return true
		end

		local deltaTime = RunService.Heartbeat:Wait()
		local step = math.min(distance, Config.FindEggSpeed * deltaTime)
		local flatDirection = flatOffset.Unit
		local nextFlatPosition = Vector3.new(
			root.Position.X + flatDirection.X * step,
			root.Position.Y,
			root.Position.Z + flatDirection.Z * step
		)
		local nextY = getLowFlyY(nextFlatPosition, root, humanoid)
		local nextPosition = Vector3.new(
			nextFlatPosition.X,
			nextY,
			nextFlatPosition.Z
		)
		local lookAt = nextPosition + Vector3.new(
			flatDirection.X,
			0,
			flatDirection.Z
		)

		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = CFrame.lookAt(nextPosition, lookAt)
	end

	humanoid.AutoRotate = true
	return false
end

local function moveToCFrame(targetCFrame, runId, arrivalDistance)
	if Config.FindEggMode == "FLY" then
		return flyLowToCFrame(targetCFrame, runId, arrivalDistance)
	end

	return runToCFrame(targetCFrame, runId, arrivalDistance)
end

local function stopFindEgg()
	Config.FindEggEnabled = false
	findEggRunId += 1
	refreshWalkSpeedLock()
	local humanoid = getHumanoid()
	local root = getRootPart()
	if humanoid and root then
		humanoid:MoveTo(root.Position)
	end
end

local function startFindEgg(onProgress, onFinished)
	stopFindEgg()
	setManualFlyEnabled(false)
	setInstantPromptEnabled(true)
	local eggs = getAllEggs()
	local humanoid = getHumanoid()
	if not humanoid then
		onFinished(false, "ไม่พบ Character")
		return
	end
	if #eggs == 0 then
		onFinished(false, "ไม่พบ Object ใน Zone ที่เลือก")
		return
	end

	Config.FindEggEnabled = true
	refreshWalkSpeedLock()
	findEggRunId += 1
	local runId = findEggRunId
	findEggThread = task.spawn(function()
		local restoreWalkSpeed = Config.WalkSpeedEnabled
			and Config.WalkSpeed
			or Config.NormalWalkSpeed
		humanoid.AutoRotate = true

		for index, egg in ipairs(eggs) do
			if not Config.FindEggEnabled or runId ~= findEggRunId then break end
			if egg and egg.Parent then
				local targetName = egg.Name
				local _, targetZoneName = getZoneFromPosition(
					getObjectPosition(egg)
				)
				local attempts = 0
				local returnCFrame = index % 2 == 1
					and FLY_RETURN_LEFT
					or FLY_RETURN_RIGHT
				local side = index % 2 == 1 and "ซ้าย" or "ขวา"

				while Config.FindEggEnabled
					and runId == findEggRunId
					and egg
					and egg.Parent
					and attempts < Config.TargetRetryLimit do

					attempts += 1
					local moveText = Config.FindEggMode == "FLY"
						and "กำลังบินไป"
						or "กำลังวิ่งไป"

					if attempts > 1 then
						moveText = "หาไข่ใบเดิมใหม่ ครั้งที่ "
							.. tostring(attempts)
					end

					onProgress(
					index,
					#eggs,
					moveText,
					targetName,
					egg,
					"Egg Target"
				)
					local position = getObjectPosition(egg)
					if not position
						or not moveToCFrame(
							CFrame.new(position),
							runId,
							Config.EggArrivalDistance
						) then
						break
					end

					onProgress(
					index,
					#eggs,
					"กำลังเก็บ",
					targetName,
					egg,
					"Collect Egg"
				)
					task.wait(0.05)
					pressEOnce()
					task.wait(Config.CollectWaitTime)

					-- เลือกจุดพักกลางตามกลุ่ม Zone
					local zoneWaypoint =
						ZONE_RETURN_WAYPOINTS[targetZoneName]
					if zoneWaypoint then
						local waypointLabel =
							(targetZoneName == "Abyss Ocean"
								or targetZoneName == "Cosmic")
							and "Abyss/Cosmic Waypoint"
							or "Volcano/Prehistoric Waypoint"
						onProgress(
							index,
							#eggs,
							"กำลังไปจุดพักกลาง " .. targetZoneName,
							targetName,
							egg,
							waypointLabel
						)
						if not moveToCFrame(
							zoneWaypoint,
							runId
						) then
							break
						end
					end

					-- กลับถึงจุดพักก่อน แล้วจึงตรวจไข่เป้าหมาย
					local returnText = Config.FindEggMode == "FLY"
						and "กำลังบินกลับจุด "
						or "กำลังวิ่งกลับจุด "
					onProgress(
					index,
					#eggs,
					returnText .. side,
					targetName,
					egg,
					"Return " .. side
				)
					if not moveToCFrame(returnCFrame, runId) then
						break
					end
					task.wait(Config.ReturnWaitTime)

					if egg and egg.Parent then
						onProgress(
							index,
							#eggs,
							"กลับถึงจุดแล้ว ไข่เดิมยังอยู่ กำลังเก็บใหม่",
							targetName,
							egg,
							"Retry Egg Target"
						)
						task.wait(Config.TargetRetryDelay)
					else
						break
					end
				end
			end
		end

		if humanoid and humanoid.Parent then
			humanoid.WalkSpeed = restoreWalkSpeed
		end
		local completed = Config.FindEggEnabled and runId == findEggRunId
		if completed then
			Config.FindEggEnabled = false
			refreshWalkSpeedLock()
		end
		if runId == findEggRunId then
			findEggThread = nil
			onFinished(completed, completed and "เก็บครบทุก Object แล้ว" or "หยุดแล้ว")
		end
	end)
end

-- GUI
local oldGui = playerGui:FindFirstChild("CharacterFindEggUI")
if oldGui then oldGui:Destroy() end

UI.ScreenGui = Instance.new("ScreenGui")
UI.ScreenGui.Name = "CharacterFindEggUI"
UI.ScreenGui.ResetOnSpawn = false
UI.ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
UI.ScreenGui.Parent = playerGui

UI.LogoButton = Instance.new("TextButton")
UI.LogoButton.Name = "LogoButton"
UI.LogoButton.Size = UDim2.fromOffset(62, 62)
UI.LogoButton.AnchorPoint = Vector2.new(0.5, 0)
UI.LogoButton.Position = UDim2.new(0.5, 0, 0, 100)
UI.LogoButton.BackgroundColor3 = Color3.fromRGB(255, 205, 35)
UI.LogoButton.BorderSizePixel = 0
UI.LogoButton.Text = "EGG"
UI.LogoButton.TextColor3 = Color3.fromRGB(255, 255, 255)
UI.LogoButton.TextSize = 17
UI.LogoButton.Font = Enum.Font.GothamBold
UI.LogoButton.Visible = false
UI.LogoButton.Active = true
UI.LogoButton.ZIndex = 1000
UI.LogoButton.Parent = UI.ScreenGui
Instance.new("UICorner", UI.LogoButton).CornerRadius = UDim.new(1, 0)

local logoStroke = Instance.new("UIStroke")
logoStroke.Color = Color3.fromRGB(220, 165, 20)
logoStroke.Thickness = 2
logoStroke.Parent = UI.LogoButton

local logoPadding = Instance.new("UIPadding")
logoPadding.PaddingTop = UDim.new(0, 7)
logoPadding.PaddingBottom = UDim.new(0, 7)
logoPadding.PaddingLeft = UDim.new(0, 7)
logoPadding.PaddingRight = UDim.new(0, 7)
logoPadding.Parent = UI.LogoButton

UI.Main = Instance.new("Frame")
UI.Main.Size = UDim2.fromOffset(440, 620)
UI.Main.Position = UDim2.new(0.5, -220, 0.5, -310)
UI.Main.BackgroundColor3 = Color3.fromRGB(28, 28, 35)
UI.Main.BorderSizePixel = 0
UI.Main.Active = true
UI.Main.Parent = UI.ScreenGui
Instance.new("UICorner", UI.Main).CornerRadius = UDim.new(0, 12)

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 50)
titleBar.BackgroundColor3 = Color3.fromRGB(37, 37, 46)
titleBar.BorderSizePixel = 0
titleBar.Active = true
titleBar.Parent = UI.Main
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -110, 1, 0)
title.Position = UDim2.fromOffset(18, 0)
title.BackgroundTransparency = 1
title.Text = "EGG"
title.TextColor3 = Color3.new(1, 1, 1)
title.TextSize = 18
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = titleBar

local minimizeButton = Instance.new("TextButton")
minimizeButton.Size = UDim2.fromOffset(36, 30)
minimizeButton.Position = UDim2.new(1, -84, 0, 10)
minimizeButton.Text = "—"
minimizeButton.TextSize = 18
minimizeButton.TextColor3 = Color3.new(1, 1, 1)
minimizeButton.BackgroundColor3 = Color3.fromRGB(65, 65, 77)
minimizeButton.BorderSizePixel = 0
minimizeButton.Parent = titleBar
Instance.new("UICorner", minimizeButton).CornerRadius = UDim.new(0, 7)

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.fromOffset(36, 30)
closeButton.Position = UDim2.new(1, -43, 0, 10)
closeButton.Text = "X"
closeButton.TextSize = 14
closeButton.Font = Enum.Font.GothamBold
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.BackgroundColor3 = Color3.fromRGB(190, 55, 60)
closeButton.BorderSizePixel = 0
closeButton.Parent = titleBar
Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0, 7)

local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 95, 1, -145)
sidebar.Position = UDim2.fromOffset(10, 57)
sidebar.BackgroundColor3 = Color3.fromRGB(34, 34, 42)
sidebar.BorderSizePixel = 0
sidebar.Parent = UI.Main
Instance.new("UICorner", sidebar).CornerRadius = UDim.new(0, 10)

local contentFrame = Instance.new("Frame")
contentFrame.Size = UDim2.new(1, -120, 1, -150)
contentFrame.Position = UDim2.fromOffset(110, 60)
contentFrame.BackgroundTransparency = 1
contentFrame.ClipsDescendants = true
contentFrame.Parent = UI.Main

UI.GlobalStatusFrame = Instance.new("Frame")
UI.GlobalStatusFrame.Name = "FindEggGlobalStatus"
UI.GlobalStatusFrame.Size = UDim2.new(1, -20, 0, 72)
UI.GlobalStatusFrame.Position = UDim2.new(0, 10, 1, -82)
UI.GlobalStatusFrame.BackgroundColor3 = Color3.fromRGB(34, 34, 42)
UI.GlobalStatusFrame.BorderSizePixel = 0
UI.GlobalStatusFrame.Parent = UI.Main
Instance.new("UICorner", UI.GlobalStatusFrame).CornerRadius = UDim.new(0, 9)

UI.GlobalStatusLabel = Instance.new("TextLabel")
UI.GlobalStatusLabel.Size = UDim2.new(1, -16, 1, -10)
UI.GlobalStatusLabel.Position = UDim2.fromOffset(8, 5)
UI.GlobalStatusLabel.BackgroundTransparency = 1
UI.GlobalStatusLabel.Text =
	"Status: Ready | Egg: - | 0/0\n"
	.. "Size: - | Zone: - | Destination: -"
UI.GlobalStatusLabel.TextColor3 = Color3.fromRGB(230, 230, 235)
UI.GlobalStatusLabel.TextSize = 11
UI.GlobalStatusLabel.Font = Enum.Font.Gotham
UI.GlobalStatusLabel.TextWrapped = true
UI.GlobalStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
UI.GlobalStatusLabel.TextYAlignment = Enum.TextYAlignment.Center
UI.GlobalStatusLabel.Parent = UI.GlobalStatusFrame

local pages = {}
local tabButtons = {}

local function createTab(name, order)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, -16, 0, 42)
	button.Position = UDim2.fromOffset(8, 10 + (order - 1) * 50)
	button.BackgroundColor3 = Color3.fromRGB(56, 56, 68)
	button.BorderSizePixel = 0
	button.Text = name
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextSize = 14
	button.Font = Enum.Font.GothamBold
	button.Parent = sidebar
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)

	local page = Instance.new("ScrollingFrame")
	page.Size = UDim2.new(1, 0, 1, 0)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.CanvasSize = UDim2.new()
	page.ScrollBarThickness = 5
	page.Visible = false
	page.Parent = contentFrame

	local content = Instance.new("Frame")
	content.Size = UDim2.new(1, -8, 0, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.BackgroundTransparency = 1
	content.Parent = page
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = content
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 15)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = content
	pages[name], tabButtons[name] = page, button
	return button, content
end

local characterTab, characterContent = createTab("Character", 1)
local findEggTab, findEggContent = createTab("Find Egg", 2)
local zonesTab, zonesContent = createTab("Zones", 3)
local sizeTab, sizeContent = createTab("Size", 4)
local hideTab, hideContent = createTab("Hide", 5)

local function showTab(name)
	for pageName, page in pairs(pages) do page.Visible = pageName == name end
	for buttonName, button in pairs(tabButtons) do
		button.BackgroundColor3 = buttonName == name
			and Color3.fromRGB(55, 135, 220)
			or Color3.fromRGB(56, 56, 68)
	end
end

local function createButton(parent, text, order)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 0, 42)
	button.BackgroundColor3 = Color3.fromRGB(56, 56, 68)
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextSize = 14
	button.Font = Enum.Font.GothamBold
	button.LayoutOrder = order
	button.Parent = parent
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)
	return button
end

local function setButtonState(button, label, enabled)
	button.Text = label .. (enabled and ": ON" or ": OFF")
	button.BackgroundColor3 = enabled
		and Color3.fromRGB(40, 165, 90)
		or Color3.fromRGB(56, 56, 68)
end

local function createSlider(parent, text, order)
	local group = Instance.new("Frame")
	group.Size = UDim2.new(1, 0, 0, 62)
	group.BackgroundTransparency = 1
	group.LayoutOrder = order
	group.Parent = parent
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 24)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextSize = 13
	label.Font = Enum.Font.Gotham
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = group
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 8)
	bar.Position = UDim2.fromOffset(0, 39)
	bar.BackgroundColor3 = Color3.fromRGB(60, 60, 72)
	bar.BorderSizePixel = 0
	bar.Active = true
	bar.Parent = group
	Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(55, 135, 220)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
	local knob = Instance.new("TextButton")
	knob.Size = UDim2.fromOffset(18, 18)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0, 0.5)
	knob.Text = ""
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BorderSizePixel = 0
	knob.Parent = bar
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
	return label, bar, fill, knob
end

local function setSliderVisual(value, minValue, maxValue, fill, knob)
	local percent = math.clamp((value - minValue) / (maxValue - minValue), 0, 1)
	fill.Size = UDim2.fromScale(percent, 1)
	knob.Position = UDim2.fromScale(percent, 0.5)
end

local function bindSlider(bar, knob, setter)
	local dragging = false
	local function update(position)
		local width = bar.AbsoluteSize.X
		if width > 0 then
			setter(math.clamp((position.X - bar.AbsolutePosition.X) / width, 0, 1))
		end
	end
	local function begin(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			update(input.Position)
		end
	end
	addConnection(bar.InputBegan:Connect(begin))
	addConnection(knob.InputBegan:Connect(begin))
	addConnection(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			update(input.Position)
		end
	end))
	addConnection(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end))
end

-- Character page
local characterTitle = Instance.new("TextLabel")
characterTitle.Size = UDim2.new(1, 0, 0, 35)
characterTitle.BackgroundTransparency = 1
characterTitle.Text = "Character"
characterTitle.TextColor3 = Color3.new(1, 1, 1)
characterTitle.TextSize = 20
characterTitle.Font = Enum.Font.GothamBold
characterTitle.TextXAlignment = Enum.TextXAlignment.Left
characterTitle.LayoutOrder = 1
characterTitle.Parent = characterContent

local walkButton = createButton(characterContent, "Walk Speed: OFF", 2)
local walkLabel, walkBar, walkFill, walkKnob = createSlider(characterContent, "Walk Speed", 3)
local jumpButton = createButton(characterContent, "Infinite Jump: OFF", 4)
local noclipButton = createButton(characterContent, "Noclip: OFF", 5)
local promptButton = createButton(characterContent, "Instant Prompt: OFF", 6)
local flyButton = createButton(characterContent, "Fly: OFF", 7)
local flyLabel, flyBar, flyFill, flyKnob = createSlider(characterContent, "Fly Speed", 8)

local function updateCharacterUI()
	setButtonState(walkButton, "Walk Speed + Lock", Config.WalkSpeedEnabled)
	setButtonState(jumpButton, "Infinite Jump", Config.InfiniteJump)
	setButtonState(noclipButton, "Noclip", Config.NoclipEnabled)
	setButtonState(promptButton, "Instant Prompt", Config.InstantPrompt)
	setButtonState(flyButton, "Fly", Config.ManualFlyEnabled)
	walkLabel.Text = "Walk Speed: " .. Config.WalkSpeed
	flyLabel.Text = "Fly Speed: " .. Config.ManualFlySpeed
	setSliderVisual(Config.WalkSpeed, Config.MinWalkSpeed, Config.MaxWalkSpeed, walkFill, walkKnob)
	setSliderVisual(Config.ManualFlySpeed, Config.MinManualFlySpeed, Config.MaxManualFlySpeed, flyFill, flyKnob)
end

bindSlider(walkBar, walkKnob, function(percent)
	Config.WalkSpeed = math.floor(Config.MinWalkSpeed + (Config.MaxWalkSpeed - Config.MinWalkSpeed) * percent + 0.5)
	applyWalkSpeed()
	updateCharacterUI()
end)

bindSlider(flyBar, flyKnob, function(percent)
	Config.ManualFlySpeed = math.floor(Config.MinManualFlySpeed + (Config.MaxManualFlySpeed - Config.MinManualFlySpeed) * percent + 0.5)
	updateCharacterUI()
end)

addConnection(walkButton.MouseButton1Click:Connect(function()
	setWalkSpeedEnabled(not Config.WalkSpeedEnabled)
	updateCharacterUI()
end))
addConnection(jumpButton.MouseButton1Click:Connect(function()
	Config.InfiniteJump = not Config.InfiniteJump
	updateCharacterUI()
end))
addConnection(noclipButton.MouseButton1Click:Connect(function()
	setNoclipEnabled(not Config.NoclipEnabled)
	updateCharacterUI()
end))
addConnection(promptButton.MouseButton1Click:Connect(function()
	setInstantPromptEnabled(not Config.InstantPrompt)
	updateCharacterUI()
end))
addConnection(flyButton.MouseButton1Click:Connect(function()
	setManualFlyEnabled(not Config.ManualFlyEnabled)
	updateCharacterUI()
end))

-- Find Egg page
local eggTitle = characterTitle:Clone()
eggTitle.Text = "Find Egg"
eggTitle.Parent = findEggContent
local eggButton = createButton(findEggContent, "Find Egg: OFF", 2)
local eggModeButton = createButton(findEggContent, "Mode: FLY", 3)
local eggSpeedLabel, eggSpeedBar, eggSpeedFill, eggSpeedKnob = createSlider(findEggContent, "Move Speed", 4)
local eggStatus = Instance.new("TextLabel")
eggStatus.Size = UDim2.new(1, 0, 0, 95)
eggStatus.BackgroundTransparency = 1
eggStatus.Text = "พร้อมค้นหา AreaEggSlotsClient\nรอบที่ 1 กลับซ้าย | รอบที่ 2 กลับขวา"
eggStatus.TextColor3 = Color3.fromRGB(175, 175, 185)
eggStatus.TextSize = 13
eggStatus.Font = Enum.Font.Gotham
eggStatus.TextWrapped = true
eggStatus.TextXAlignment = Enum.TextXAlignment.Left
eggStatus.LayoutOrder = 5
eggStatus.Parent = findEggContent

local function updateEggUI()
	setButtonState(eggButton, "Find Egg", Config.FindEggEnabled)
	eggModeButton.Text = "Mode: " .. Config.FindEggMode
	eggModeButton.BackgroundColor3 = Config.FindEggMode == "FLY"
		and Color3.fromRGB(130, 80, 210)
		or Color3.fromRGB(45, 145, 210)
	eggSpeedLabel.Text = "Move Speed: " .. Config.FindEggSpeed
	setSliderVisual(Config.FindEggSpeed, Config.MinFindEggSpeed, Config.MaxFindEggSpeed, eggSpeedFill, eggSpeedKnob)
end

local function updateGlobalStatus(
	index,
	total,
	action,
	name,
	egg,
	destination
)
	local size = getHitboxSize(egg)
	local eggPosition = getObjectPosition(egg)
	local _, zoneName = getZoneFromPosition(
		eggPosition
	)
	local sizeText = "-"
	local destinationText = destination or "-"
	local destinationPosition

	if size then
		sizeText = string.format("%.2f", size)
		sizeText = sizeText:gsub("0+$", ""):gsub("%.$", "")
	end

	if destination == "Volcano/Prehistoric Waypoint" then
		destinationPosition = VOLCANO_RETURN_WAYPOINT.Position
	elseif destination == "Abyss/Cosmic Waypoint" then
		destinationPosition = ABYSS_COSMIC_RETURN_WAYPOINT.Position
	elseif destination == "Return ซ้าย" then
		destinationPosition = FLY_RETURN_LEFT.Position
	elseif destination == "Return ขวา" then
		destinationPosition = FLY_RETURN_RIGHT.Position
	elseif eggPosition then
		destinationPosition = eggPosition
	end

	if destinationPosition then
		destinationText = string.format(
			"%s (%.1f, %.1f, %.1f)",
			destinationText,
			destinationPosition.X,
			destinationPosition.Y,
			destinationPosition.Z
		)
	end

	UI.GlobalStatusLabel.Text = string.format(
		"Status: %s | Egg: %s | %d/%d\n"
			.. "Size: %s | Zone: %s | Destination: %s",
		action or "Ready",
		name or "-",
		index or 0,
		total or 0,
		sizeText,
		zoneName or "-",
		destinationText
	)
end

bindSlider(eggSpeedBar, eggSpeedKnob, function(percent)
	Config.FindEggSpeed = math.floor(Config.MinFindEggSpeed + (Config.MaxFindEggSpeed - Config.MinFindEggSpeed) * percent + 0.5)
	updateEggUI()
end)

addConnection(eggModeButton.MouseButton1Click:Connect(function()
	if Config.FindEggEnabled then
		stopFindEgg()
		eggStatus.Text = "หยุด Find Egg เพื่อเปลี่ยนโหมดแล้ว"
		updateGlobalStatus(0, 0, "Stopped", "-", nil, "Mode Changed")
	end

	Config.FindEggMode = Config.FindEggMode == "RUN"
		and "FLY"
		or "RUN"
	updateEggUI()
end))

addConnection(eggButton.MouseButton1Click:Connect(function()
	if Config.FindEggEnabled then
		stopFindEgg()
		eggStatus.Text = "หยุด Find Egg แล้ว"
		updateGlobalStatus(0, 0, "Stopped", "-", nil, "-")
		updateEggUI()
		return
	end
	eggStatus.TextColor3 = Color3.fromRGB(175, 175, 185)
	startFindEgg(
		function(index, total, action, name, egg, destination)
			eggStatus.Text = string.format("รอบ %d/%d | %s\nObject: %s", index, total, action, name)
			updateGlobalStatus(
				index,
				total,
				action,
				name,
				egg,
				destination
			)
		end,
		function(completed, message)
			eggStatus.Text = message
			eggStatus.TextColor3 = completed
				and Color3.fromRGB(90, 220, 130)
				or Color3.fromRGB(235, 130, 100)
			updateGlobalStatus(
				0,
				0,
				message,
				"-",
				nil,
				completed and "Completed" or "Stopped"
			)
			updateEggUI()
		end
	)
	updateEggUI()
end))

-- Zones page
local zonesTitle = characterTitle:Clone()
zonesTitle.Text = "Select Egg Zones"
zonesTitle.Parent = zonesContent

local zoneActions = Instance.new("Frame")
zoneActions.Size = UDim2.new(1, 0, 0, 42)
zoneActions.BackgroundTransparency = 1
zoneActions.LayoutOrder = 2
zoneActions.Parent = zonesContent

local selectAllZonesButton = createButton(
	zoneActions,
	"Select All",
	1
)
selectAllZonesButton.Size = UDim2.new(0.5, -5, 1, 0)
selectAllZonesButton.Position = UDim2.fromOffset(0, 0)

local clearAllZonesButton = createButton(
	zoneActions,
	"Clear All",
	2
)
clearAllZonesButton.Size = UDim2.new(0.5, -5, 1, 0)
clearAllZonesButton.Position = UDim2.new(0.5, 5, 0, 0)

local zonesStatus = Instance.new("TextLabel")
zonesStatus.Size = UDim2.new(1, 0, 0, 34)
zonesStatus.BackgroundTransparency = 1
zonesStatus.TextColor3 = Color3.fromRGB(175, 175, 185)
zonesStatus.TextSize = 13
zonesStatus.Font = Enum.Font.Gotham
zonesStatus.TextXAlignment = Enum.TextXAlignment.Left
zonesStatus.LayoutOrder = 3
zonesStatus.Parent = zonesContent

local zonesScroll = Instance.new("ScrollingFrame")
zonesScroll.Name = "ZoneSelectionScroll"
zonesScroll.Size = UDim2.new(1, 0, 0, 300)
zonesScroll.BackgroundColor3 = Color3.fromRGB(34, 34, 42)
zonesScroll.BorderSizePixel = 0
zonesScroll.ScrollBarThickness = 6
zonesScroll.ScrollBarImageColor3 = Color3.fromRGB(110, 110, 125)
zonesScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
zonesScroll.CanvasSize = UDim2.new()
zonesScroll.ScrollingDirection = Enum.ScrollingDirection.Y
zonesScroll.LayoutOrder = 4
zonesScroll.Parent = zonesContent
Instance.new("UICorner", zonesScroll).CornerRadius = UDim.new(0, 8)

local zoneListContent = Instance.new("Frame")
zoneListContent.Size = UDim2.new(1, -12, 0, 0)
zoneListContent.AutomaticSize = Enum.AutomaticSize.Y
zoneListContent.BackgroundTransparency = 1
zoneListContent.Parent = zonesScroll

local zoneListLayout = Instance.new("UIListLayout")
zoneListLayout.Padding = UDim.new(0, 8)
zoneListLayout.SortOrder = Enum.SortOrder.LayoutOrder
zoneListLayout.Parent = zoneListContent

local zoneListPadding = Instance.new("UIPadding")
zoneListPadding.PaddingTop = UDim.new(0, 8)
zoneListPadding.PaddingBottom = UDim.new(0, 8)
zoneListPadding.PaddingLeft = UDim.new(0, 8)
zoneListPadding.PaddingRight = UDim.new(0, 4)
zoneListPadding.Parent = zoneListContent

local zoneButtons = {}

local function updateZonesUI()
	local selectedCount = 0
	for _, zone in ipairs(ZONES) do
		local selected = selectedZones[zone.Name] == true
		if selected then selectedCount += 1 end
		local button = zoneButtons[zone.Name]
		if button then
			setButtonState(button, zone.Name, selected)
		end
	end
	zonesStatus.Text = string.format(
		"Selected: %d/%d Zones",
		selectedCount,
		#ZONES
	)
end

local function stopFindEggForZoneChange()
	if Config.FindEggEnabled then
		stopFindEgg()
		eggStatus.Text = "หยุด Find Egg เนื่องจากมีการเปลี่ยน Zone"
		updateGlobalStatus(0, 0, "Stopped", "-", nil, "Zone Changed")
		updateEggUI()
	end
end

for index, zone in ipairs(ZONES) do
	local button = createButton(
		zoneListContent,
		zone.Name .. ": ON",
		index
	)
	zoneButtons[zone.Name] = button

	addConnection(button.MouseButton1Click:Connect(function()
		stopFindEggForZoneChange()
		selectedZones[zone.Name] = not selectedZones[zone.Name]
		updateZonesUI()
	end))
end

addConnection(selectAllZonesButton.MouseButton1Click:Connect(function()
	stopFindEggForZoneChange()
	for _, zone in ipairs(ZONES) do
		selectedZones[zone.Name] = true
	end
	updateZonesUI()
end))

addConnection(clearAllZonesButton.MouseButton1Click:Connect(function()
	stopFindEggForZoneChange()
	for _, zone in ipairs(ZONES) do
		selectedZones[zone.Name] = false
	end
	updateZonesUI()
end))

-- Size page: เลือกตัวกรองได้ครั้งละหนึ่งค่า
local sizeTitle = characterTitle:Clone()
sizeTitle.Text = "Hitbox Size Filter"
sizeTitle.Parent = sizeContent

local sizeStatus = Instance.new("TextLabel")
sizeStatus.Size = UDim2.new(1, 0, 0, 52)
sizeStatus.BackgroundTransparency = 1
sizeStatus.TextColor3 = Color3.fromRGB(175, 175, 185)
sizeStatus.TextSize = 13
sizeStatus.Font = Enum.Font.Gotham
sizeStatus.TextWrapped = true
sizeStatus.TextXAlignment = Enum.TextXAlignment.Left
sizeStatus.LayoutOrder = 2
sizeStatus.Parent = sizeContent

local sizeButtons = {}

local function formatSize(value)
	if value % 1 == 0 then
		return tostring(math.floor(value))
	end
	return tostring(value)
end

local function updateSizeUI()
	for _, value in ipairs(SIZE_FILTERS) do
		local button = sizeButtons[value]
		if button then
			setButtonState(
				button,
				"Hitbox Size > " .. formatSize(value),
				selectedHitboxSize == value
			)
		end
	end

	sizeStatus.Text =
		"Selected: Hitbox Size > "
		.. formatSize(selectedHitboxSize)
		.. "\nเรียงขนาดใหญ่ไปเล็ก และ Zone หลังสุดไปหน้าสุด"
end

for index, value in ipairs(SIZE_FILTERS) do
	local button = createButton(
		sizeContent,
		"Hitbox Size > " .. formatSize(value),
		2 + index
	)
	sizeButtons[value] = button

	addConnection(button.MouseButton1Click:Connect(function()
		if Config.FindEggEnabled then
			stopFindEgg()
			eggStatus.Text =
				"หยุด Find Egg เนื่องจากเปลี่ยน Size Filter"
			updateGlobalStatus(
				0,
				0,
				"Stopped",
				"-",
				nil,
				"Size Filter Changed"
			)
			updateEggUI()
		end

		selectedHitboxSize = value
		updateSizeUI()
	end))
end

-- Hide page
local hideTitle = characterTitle:Clone()
hideTitle.Text = "Hide Animals"
hideTitle.Parent = hideContent

local hideAnimalsButton = createButton(
	hideContent,
	"Hide Animals: OFF",
	2
)

local hideStatus = Instance.new("TextLabel")
hideStatus.Size = UDim2.new(1, 0, 0, 90)
hideStatus.BackgroundTransparency = 1
hideStatus.Text =
	"Path: Workspace > ClientRenderedAssets\n"
	.. "ซ่อนชิ้นส่วนภาพภายใน Model ระดับแรก"
hideStatus.TextColor3 = Color3.fromRGB(175, 175, 185)
hideStatus.TextSize = 13
hideStatus.Font = Enum.Font.Gotham
hideStatus.TextWrapped = true
hideStatus.TextXAlignment = Enum.TextXAlignment.Left
hideStatus.LayoutOrder = 3
hideStatus.Parent = hideContent

local function updateHideUI()
	setButtonState(
		hideAnimalsButton,
		"Hide Animals",
		Config.HideAnimalsEnabled
	)
end

addConnection(hideAnimalsButton.MouseButton1Click:Connect(function()
	local enabled = not Config.HideAnimalsEnabled
	local changed = setHideAnimalsEnabled(enabled)

	if enabled then
		hideStatus.Text = string.format(
			"Hide ON | ซ่อน %d ชิ้นส่วน\n"
				.. "BasePart/Decal/Texture ภายใน Model ระดับแรก",
			changed
		)
	else
		hideStatus.Text =
			"Hide OFF | คืนค่า Transparency เดิมแล้ว"
	end

	updateHideUI()
end))

addConnection(characterTab.MouseButton1Click:Connect(function()
	showTab("Character")
	updateCharacterUI()
end))
addConnection(findEggTab.MouseButton1Click:Connect(function()
	showTab("Find Egg")
	updateEggUI()
end))
addConnection(zonesTab.MouseButton1Click:Connect(function()
	showTab("Zones")
	updateZonesUI()
end))
addConnection(sizeTab.MouseButton1Click:Connect(function()
	showTab("Size")
	updateSizeUI()
end))
addConnection(hideTab.MouseButton1Click:Connect(function()
	showTab("Hide")
	updateHideUI()
end))

-- Drag / minimize / close
local draggingWindow = false
local dragStart
local startPosition
addConnection(titleBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		draggingWindow = true
		dragStart = input.Position
		startPosition = UI.Main.Position
	end
end))
addConnection(UserInputService.InputChanged:Connect(function(input)
	if draggingWindow and (input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - dragStart
		UI.Main.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
	end
end))
addConnection(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then draggingWindow = false end
end))

addConnection(minimizeButton.MouseButton1Click:Connect(function()
	UI.Main.Visible = false
	UI.LogoButton.Visible = true
end))

addConnection(UI.LogoButton.MouseButton1Click:Connect(function()
	UI.LogoButton.Visible = false
	UI.Main.Visible = true
end))

local function closeScript()
	if scriptClosed then return end
	scriptClosed = true
	stopFindEgg()
	setManualFlyEnabled(false)
	setWalkSpeedEnabled(false)
	Config.InfiniteJump = false
	setNoclipEnabled(false)
	setInstantPromptEnabled(false)
	setHideAnimalsEnabled(false)
	disconnectAll()
	UI.ScreenGui:Destroy()
end

addConnection(closeButton.MouseButton1Click:Connect(closeScript))
addConnection(UserInputService.InputBegan:Connect(function(input, processed)
	if scriptClosed or processed then return end
	if input.KeyCode == Config.ToggleKey then
		local showMain = not UI.Main.Visible
		UI.Main.Visible = showMain
		UI.LogoButton.Visible = not showMain
	end
end))

addConnection(player.CharacterAdded:Connect(function()
	stopFindEgg()
	stopManualFly()
	task.wait(0.7)
	applyWalkSpeed()
	if Config.NoclipEnabled then setNoclipEnabled(true) end
	Config.ManualFlyEnabled = false
	updateCharacterUI()
	updateEggUI()
end))

showTab("Character")
updateCharacterUI()
updateEggUI()
updateZonesUI()
updateSizeUI()
updateHideUI()
