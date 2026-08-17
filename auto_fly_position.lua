local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local oldGui = playerGui:FindFirstChild("FlyRouteGui")
if oldGui then oldGui:Destroy() end

local points = {}
local running = false
local minimized = false
local closed = false
local loopForever = false
local flySpeed = 300
local rounds = 1
local ARRIVE_DISTANCE = 1

local flyVelocity
local flyGyro
local noclipConnection
local originalCollisions = {}
local stopRoute

local function getCharacterParts()
	local character = player.Character or player.CharacterAdded:Wait()
	return character,
		character:WaitForChild("HumanoidRootPart"),
		character:FindFirstChildOfClass("Humanoid")
end

local function startNoclip()
	if noclipConnection then noclipConnection:Disconnect() end
	noclipConnection = RunService.Stepped:Connect(function()
		if not running then return end
		local character = player.Character
		if not character then return end
		for _, object in ipairs(character:GetDescendants()) do
			if object:IsA("BasePart") then
				if originalCollisions[object] == nil then
					originalCollisions[object] = object.CanCollide
				end
				object.CanCollide = false
			end
		end
	end)
end

local function stopNoclip()
	if noclipConnection then
		noclipConnection:Disconnect()
		noclipConnection = nil
	end
	for part, originalState in pairs(originalCollisions) do
		if part and part.Parent then part.CanCollide = originalState end
	end
	table.clear(originalCollisions)
end

-- ใช้ระบบเดียวกับ Fly ใน Main_world(4).lua
local function createFlyForce()
	local _, rootPart, humanoid = getCharacterParts()
	if not rootPart or not humanoid then return nil end

	if flyVelocity then flyVelocity:Destroy() end
	if flyGyro then flyGyro:Destroy() end

	humanoid.PlatformStand = true
	humanoid.AutoRotate = false
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero

	flyVelocity = Instance.new("BodyVelocity")
	flyVelocity.Name = "RouteFlyVelocity"
	flyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	flyVelocity.P = 10000
	flyVelocity.Velocity = Vector3.zero
	flyVelocity.Parent = rootPart

	flyGyro = Instance.new("BodyGyro")
	flyGyro.Name = "RouteFlyGyro"
	flyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
	flyGyro.P = 10000
	flyGyro.D = 100
	flyGyro.CFrame = rootPart.CFrame
	flyGyro.Parent = rootPart

	return rootPart, humanoid
end

local function removeFlyForce()
	if flyVelocity then flyVelocity:Destroy(); flyVelocity = nil end
	if flyGyro then flyGyro:Destroy(); flyGyro = nil end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if rootPart then
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end
	if humanoid then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

local gui = Instance.new("ScreenGui")
gui.Name = "FlyRouteGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(410, 525)
main.Position = UDim2.new(0.5, -205, 0.5, -262)
main.BackgroundColor3 = Color3.fromRGB(22, 25, 31)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -100, 0, 48)
title.Position = UDim2.fromOffset(15, 0)
title.BackgroundTransparency = 1
title.Text = "Fly Route Manager"
title.TextColor3 = Color3.new(1, 1, 1)
title.TextSize = 17
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = main

local function button(text, x, y, w, h, color, parent)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(w, h)
	b.Position = UDim2.fromOffset(x, y)
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextSize = 13
	b.Font = Enum.Font.GothamBold
	b.Parent = parent or main
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
	return b
end

local function input(placeholder, x, y, w, value)
	local box = Instance.new("TextBox")
	box.Size = UDim2.fromOffset(w, 34)
	box.Position = UDim2.fromOffset(x, y)
	box.BackgroundColor3 = Color3.fromRGB(44, 49, 59)
	box.BorderSizePixel = 0
	box.PlaceholderText = placeholder
	box.Text = value or ""
	box.TextColor3 = Color3.new(1, 1, 1)
	box.TextSize = 13
	box.Font = Enum.Font.Gotham
	box.ClearTextOnFocus = false
	box.Parent = main
	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 7)
	return box
end

local minimize = button("—", 324, 9, 38, 30, Color3.fromRGB(225, 145, 45))
local close = button("X", 367, 9, 34, 30, Color3.fromRGB(210, 65, 65))

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.fromOffset(386, 135)
list.Position = UDim2.fromOffset(12, 55)
list.BackgroundColor3 = Color3.fromRGB(31, 35, 43)
list.BorderSizePixel = 0
list.ScrollBarThickness = 5
list.CanvasSize = UDim2.new()
list.Parent = main
Instance.new("UICorner", list).CornerRadius = UDim.new(0, 8)
local layout = Instance.new("UIListLayout", list)
layout.Padding = UDim.new(0, 4)

local xBox = input("X", 12, 200, 86)
local yBox = input("Y", 104, 200, 86)
local zBox = input("Z", 196, 200, 86)
local addXYZ = button("ADD XYZ", 288, 200, 110, 34, Color3.fromRGB(55, 125, 220))
local addCurrent = button("ADD CURRENT", 12, 242, 180, 36, Color3.fromRGB(39, 174, 96))
local removeLast = button("REMOVE LAST", 198, 242, 120, 36, Color3.fromRGB(225, 145, 45))
local clear = button("CLEAR", 324, 242, 74, 36, Color3.fromRGB(210, 65, 65))

local fileNameBox = input("TXT file name", 12, 290, 142, "fly_positions")
local saveButton = button("SAVE TXT", 160, 290, 115, 34, Color3.fromRGB(55, 125, 220))
local loadButton = button("LOAD TXT", 281, 290, 117, 34, Color3.fromRGB(125, 90, 210))

local speedBox = input("Speed", 12, 336, 115, "300")
local roundBox = input("Rounds", 133, 336, 115, "1")
local loopButton = button("LOOP: OFF", 254, 336, 144, 34, Color3.fromRGB(44, 49, 59))
local startButton = button("START", 12, 382, 188, 42, Color3.fromRGB(39, 174, 96))
local stopButton = button("STOP", 210, 382, 188, 42, Color3.fromRGB(210, 65, 65))

local status = Instance.new("TextLabel")
status.Size = UDim2.fromOffset(386, 58)
status.Position = UDim2.fromOffset(12, 436)
status.BackgroundColor3 = Color3.fromRGB(31, 35, 43)
status.BorderSizePixel = 0
status.Text = "Ready | Press K to minimize"
status.TextColor3 = Color3.fromRGB(180, 185, 195)
status.TextSize = 12
status.TextWrapped = true
status.Font = Enum.Font.Gotham
status.Parent = main
Instance.new("UICorner", status).CornerRadius = UDim.new(0, 8)

local logo = button("G", 20, 80, 55, 55, Color3.fromRGB(30, 190, 85), gui)
logo.TextSize = 30
logo.Font = Enum.Font.GothamBlack
logo.Visible = false
logo.Active = true
logo.Draggable = true
Instance.new("UIStroke", logo).Color = Color3.fromRGB(220, 255, 230)

local function setStatus(text, color)
	if closed then return end
	status.Text = text
	status.TextColor3 = color or Color3.fromRGB(180, 185, 195)
end

local function refreshList()
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("TextLabel") then child:Destroy() end
	end
	for index, point in ipairs(points) do
		local row = Instance.new("TextLabel")
		row.Size = UDim2.new(1, -6, 0, 27)
		row.BackgroundColor3 = Color3.fromRGB(44, 49, 59)
		row.BorderSizePixel = 0
		row.Text = string.format("%d.  X %.2f   Y %.2f   Z %.2f", index, point.X, point.Y, point.Z)
		row.TextColor3 = Color3.new(1, 1, 1)
		row.TextSize = 12
		row.Font = Enum.Font.Code
		row.LayoutOrder = index
		row.Parent = list
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)
	end
	list.CanvasSize = UDim2.fromOffset(0, #points * 31)
end

local function getTxtFileName()
	local name = tostring(fileNameBox.Text or "")
	name = name:gsub("%.txt$", "")
	name = name:gsub("[^%w_%-]", "_")
	if name == "" then name = "fly_positions" end
	fileNameBox.Text = name
	return name .. ".txt"
end

local function savePositionsToTxt()
	if type(writefile) ~= "function" then
		setStatus("Executor does not support writefile", Color3.fromRGB(255, 100, 100))
		return
	end
	if #points == 0 then
		setStatus("No positions to save", Color3.fromRGB(255, 180, 80))
		return
	end

	local lines = {"FLY_ROUTE_V1"}
	for _, point in ipairs(points) do
		table.insert(lines, string.format("%.10f,%.10f,%.10f", point.X, point.Y, point.Z))
	end

	local fileName = getTxtFileName()
	local success, errorMessage = pcall(writefile, fileName, table.concat(lines, "\n"))
	if success then
		setStatus(string.format("Saved %d positions: workspace/%s", #points, fileName), Color3.fromRGB(100, 235, 145))
	else
		setStatus("Save failed: " .. tostring(errorMessage), Color3.fromRGB(255, 100, 100))
	end
end

local function loadPositionsFromTxt()
	if type(readfile) ~= "function" then
		setStatus("Executor does not support readfile", Color3.fromRGB(255, 100, 100))
		return
	end

	local fileName = getTxtFileName()
	if type(isfile) == "function" and not isfile(fileName) then
		setStatus("File not found: workspace/" .. fileName, Color3.fromRGB(255, 100, 100))
		return
	end

	local success, content = pcall(readfile, fileName)
	if not success then
		setStatus("Load failed: " .. tostring(content), Color3.fromRGB(255, 100, 100))
		return
	end

	local loadedPoints = {}
	for line in tostring(content):gmatch("[^\r\n]+") do
		local xText, yText, zText = line:match("^%s*([^,]+)%s*,%s*([^,]+)%s*,%s*([^,]+)%s*$")
		local x, y, z = tonumber(xText), tonumber(yText), tonumber(zText)
		if x and y and z then
			table.insert(loadedPoints, Vector3.new(x, y, z))
		end
	end

	if #loadedPoints == 0 then
		setStatus("No valid positions found in " .. fileName, Color3.fromRGB(255, 100, 100))
		return
	end

	if running then stopRoute("Stopped before loading") end
	table.clear(points)
	for _, point in ipairs(loadedPoints) do table.insert(points, point) end
	refreshList()
	setStatus(string.format("Loaded %d positions: workspace/%s", #points, fileName), Color3.fromRGB(100, 235, 145))
end

local function toggleMinimize()
	minimized = not minimized
	main.Visible = not minimized
	logo.Visible = minimized
end

-- BodyVelocity จะพยุงแกน Y ตลอด จึงไม่ตก และหยุดนิ่งเมื่อถึงจุด
local function flyTo(target)
	local _, rootPart = getCharacterParts()
	if not flyVelocity or not flyVelocity.Parent or not flyGyro or not flyGyro.Parent then
		rootPart = createFlyForce()
	end
	if not rootPart then return false end

	while running and not closed do
		if not rootPart.Parent then return false end
		if not flyVelocity or not flyVelocity.Parent then return false end
		if not flyGyro or not flyGyro.Parent then return false end

		local difference = target - rootPart.Position
		local distance = difference.Magnitude
		if distance <= ARRIVE_DISTANCE then
			rootPart.CFrame = CFrame.new(target) * rootPart.CFrame.Rotation
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero
			flyVelocity.Velocity = Vector3.zero
			flyGyro.CFrame = rootPart.CFrame
			return true
		end

		local direction = difference.Unit
		-- ลดความเร็วก่อนถึงเป้าหมาย ป้องกันกระชากและสั่นข้ามจุด
		local currentSpeed = math.min(flySpeed, math.max(12, distance * 5))
		flyVelocity.Velocity = direction * currentSpeed

		local flatDirection = Vector3.new(direction.X, 0, direction.Z)
		if flatDirection.Magnitude > 0.001 then
			flyGyro.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + flatDirection.Unit)
		end
		RunService.Heartbeat:Wait()
	end
	return false
end

stopRoute = function(message)
	running = false
	removeFlyForce()
	stopNoclip()
	setStatus(message or "Stopped")
end

local function startRoute()
	if running then return end
	if #points == 0 then setStatus("Please add a position", Color3.fromRGB(255, 100, 100)); return end
	flySpeed = math.max(1, tonumber(speedBox.Text) or 300)
	rounds = math.max(1, math.floor(tonumber(roundBox.Text) or 1))
	speedBox.Text = tostring(flySpeed)
	roundBox.Text = tostring(rounds)
	running = true
	startNoclip()
	if not createFlyForce() then
		stopRoute("Character is not ready")
		return
	end

	task.spawn(function()
		local currentRound = 1
		while running and not closed do
			for index, target in ipairs(points) do
				if not running then break end
				setStatus(string.format("Round %d | Position %d/%d", currentRound, index, #points), Color3.fromRGB(100, 235, 145))
				if not flyTo(target) then break end
				task.wait(0.15)
			end
			if not running then break end
			if not loopForever and currentRound >= rounds then break end
			currentRound += 1
		end
		if running then stopRoute("Completed") else stopRoute("Stopped") end
	end)
end

addCurrent.MouseButton1Click:Connect(function()
	local _, rootPart = getCharacterParts()
	table.insert(points, rootPart.Position)
	refreshList()
	setStatus("Added current position #" .. #points)
end)

addXYZ.MouseButton1Click:Connect(function()
	local x, y, z = tonumber(xBox.Text), tonumber(yBox.Text), tonumber(zBox.Text)
	if not x or not y or not z then setStatus("X, Y, Z must be numbers", Color3.fromRGB(255, 100, 100)); return end
	table.insert(points, Vector3.new(x, y, z))
	xBox.Text, yBox.Text, zBox.Text = "", "", ""
	refreshList()
end)

removeLast.MouseButton1Click:Connect(function()
	if #points > 0 then table.remove(points); refreshList() end
end)

clear.MouseButton1Click:Connect(function()
	if running then stopRoute("Stopped and cleared") end
	table.clear(points)
	refreshList()
end)

saveButton.MouseButton1Click:Connect(savePositionsToTxt)
loadButton.MouseButton1Click:Connect(loadPositionsFromTxt)

loopButton.MouseButton1Click:Connect(function()
	loopForever = not loopForever
	loopButton.Text = loopForever and "LOOP: ON" or "LOOP: OFF"
	loopButton.BackgroundColor3 = loopForever and Color3.fromRGB(39, 174, 96) or Color3.fromRGB(44, 49, 59)
end)

startButton.MouseButton1Click:Connect(startRoute)
stopButton.MouseButton1Click:Connect(function() stopRoute("Stopped by user") end)
minimize.MouseButton1Click:Connect(toggleMinimize)
logo.MouseButton1Click:Connect(toggleMinimize)

close.MouseButton1Click:Connect(function()
	closed = true
	stopRoute()
	gui:Destroy()
end)

UserInputService.InputBegan:Connect(function(key, processed)
	if not processed and not closed and key.KeyCode == Enum.KeyCode.K then
		toggleMinimize()
	end
end)

player.CharacterAdded:Connect(function()
	if running then stopRoute("Character respawned — press START again") end
end)

refreshList()
