-- Roblox Item Finder G
-- Path: workspace > Zones > [All Zone Models] > SpawnZone > [Items]

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local VIM = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local zonesFolder = workspace:WaitForChild("Zones")

local TOGGLE_KEY = Enum.KeyCode.L
local WARP_OFFSET = Vector3.zero
local ITEM_DELAY = 0.15
local E_SPAM_DELAY = 0.01
local LOOP_DELAY = 0.5
local BACKPACK_FULL_DELAY = 1

local character, rootPart
local selected, itemGroups, buttons = {}, {}, {}
local collecting, eSpamRunning, looping = false, false, false
local findAllMode, continuousToken = false, 0
local programClosed = false

local function updateCharacter()
	character = player.Character or player.CharacterAdded:Wait()
	rootPart = character:WaitForChild("HumanoidRootPart")
end

updateCharacter()
player.CharacterAdded:Connect(updateCharacter)

local old = player.PlayerGui:FindFirstChild("ItemFinderG")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "ItemFinderG"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player.PlayerGui

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(410, 520)
main.Position = UDim2.new(0.5, -205, 0.5, -260)
main.BackgroundColor3 = Color3.fromRGB(18, 22, 27)
main.BorderSizePixel = 0
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)

local stroke = Instance.new("UIStroke", main)
stroke.Color = Color3.fromRGB(41, 181, 98)
stroke.Thickness = 1.5

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 48)
header.BackgroundColor3 = Color3.fromRGB(27, 33, 39)
header.BorderSizePixel = 0
header.Parent = main
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 12)

local headerFix = Instance.new("Frame")
headerFix.Size = UDim2.new(1, 0, 0, 12)
headerFix.Position = UDim2.new(0, 0, 1, -12)
headerFix.BackgroundColor3 = header.BackgroundColor3
headerFix.BorderSizePixel = 0
headerFix.Parent = header

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -100, 1, 0)
title.Position = UDim2.fromOffset(15, 0)
title.BackgroundTransparency = 1
title.Text = "G  ITEM FINDER"
title.TextColor3 = Color3.fromRGB(240, 245, 242)
title.TextSize = 17
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local function makeButton(parent, text, position, size, color)
	local button = Instance.new("TextButton")
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextSize = 14
	button.Font = Enum.Font.GothamBold
	button.AutoButtonColor = true
	button.Parent = parent
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)
	return button
end

local minimize = makeButton(header, "_", UDim2.new(1, -82, 0, 7), UDim2.fromOffset(34, 34), Color3.fromRGB(46, 151, 85))
local close = makeButton(header, "X", UDim2.new(1, -42, 0, 7), UDim2.fromOffset(34, 34), Color3.fromRGB(190, 65, 65))

local logo = makeButton(gui, "G", UDim2.new(0, 18, 0.5, -28), UDim2.fromOffset(56, 56), Color3.fromRGB(24, 176, 82))
logo.TextSize = 28
logo.Visible = false

local search = Instance.new("TextBox")
search.Size = UDim2.new(1, -24, 0, 38)
search.Position = UDim2.fromOffset(12, 108)
search.BackgroundColor3 = Color3.fromRGB(29, 35, 42)
search.BorderSizePixel = 0
search.PlaceholderText = "ค้นหาชื่อ Item..."
search.Text = ""
search.TextColor3 = Color3.new(1, 1, 1)
search.PlaceholderColor3 = Color3.fromRGB(140, 145, 150)
search.TextSize = 14
search.Font = Enum.Font.Gotham
search.ClearTextOnFocus = false
search.Parent = main
Instance.new("UICorner", search).CornerRadius = UDim.new(0, 8)

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -24, 0, 244)
list.Position = UDim2.fromOffset(12, 156)
list.BackgroundColor3 = Color3.fromRGB(23, 28, 34)
list.BorderSizePixel = 0
list.ScrollBarThickness = 5
list.ScrollBarImageColor3 = Color3.fromRGB(34, 190, 92)
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = main
Instance.new("UICorner", list).CornerRadius = UDim.new(0, 8)

local padding = Instance.new("UIPadding", list)
padding.PaddingTop = UDim.new(0, 6)
padding.PaddingBottom = UDim.new(0, 6)
padding.PaddingLeft = UDim.new(0, 6)
padding.PaddingRight = UDim.new(0, 6)

local layout = Instance.new("UIListLayout", list)
layout.Padding = UDim.new(0, 5)
layout.SortOrder = Enum.SortOrder.LayoutOrder

local findButton = makeButton(main, "REFRESH", UDim2.fromOffset(12, 60), UDim2.new(1, -24, 0, 38), Color3.fromRGB(51, 111, 220))
local warpButton = makeButton(main, "WARP", UDim2.fromOffset(12, 411), UDim2.new(0.34, -12, 0, 42), Color3.fromRGB(32, 167, 91))
local loopButton = makeButton(main, "LOOP", UDim2.new(0.34, 4, 0, 411), UDim2.new(0.33, -8, 0, 42), Color3.fromRGB(125, 79, 196))
local findAllButton = makeButton(main, "FIND ALL", UDim2.new(0.67, 0, 0, 411), UDim2.new(0.33, -12, 0, 42), Color3.fromRGB(205, 125, 39))

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -24, 0, 44)
status.Position = UDim2.fromOffset(12, 464)
status.BackgroundColor3 = Color3.fromRGB(27, 33, 39)
status.BorderSizePixel = 0
status.Text = "พร้อมใช้งาน | กด L เพื่อซ่อน/แสดง"
status.TextColor3 = Color3.fromRGB(188, 196, 190)
status.TextSize = 12
status.TextWrapped = true
status.Font = Enum.Font.Gotham
status.Parent = main
Instance.new("UICorner", status).CornerRadius = UDim.new(0, 8)

-- Drag main window
local dragging, dragStart, startPos
header.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging, dragStart, startPos = true, input.Position, main.Position
	end
end)
header.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
end)
UIS.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local d = input.Position - dragStart
		main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
	end
end)

local function getPosition(item)
	if not item or not item.Parent then return nil end
	if item:IsA("Model") then
		-- ใช้กึ่งกลาง Bounding Box แทน Pivot ที่อาจอยู่ตรงหัวของ Item
		local success, boxCFrame = pcall(function()
			return item:GetBoundingBox()
		end)
		if success and boxCFrame then return boxCFrame.Position end
		return item:GetPivot().Position
	end
	if item:IsA("BasePart") then return item.Position end
	local part = item:FindFirstChildWhichIsA("BasePart", true)
	return part and part.Position or nil
end

local function getPrompt(item)
	if not item or not item.Parent then return nil end
	if item:IsA("ProximityPrompt") then return item end
	return item:FindFirstChildWhichIsA("ProximityPrompt", true)
end

local function getBackpackValueObject()
	-- Path ปกติของ LocalPlayer
	local mainGui = player:FindFirstChild("PlayerGui")
		and player.PlayerGui:FindFirstChild("MainScreenGui")
	local currencies = mainGui and mainGui:FindFirstChild("Currencies")
	local backpack = currencies and currencies:FindFirstChild("Backpack")
	local value = backpack and backpack:FindFirstChild("Value")
	if value then return value end

	-- Fallback ตาม Path: workspace > Players > UserId/Name > PlayerGui
	local workspacePlayers = workspace:FindFirstChild("Players")
	local workspacePlayer = workspacePlayers and (
		workspacePlayers:FindFirstChild(tostring(player.UserId))
		or workspacePlayers:FindFirstChild(player.Name)
	)
	local workspaceGui = workspacePlayer and workspacePlayer:FindFirstChild("PlayerGui")
	local fallbackMain = workspaceGui and workspaceGui:FindFirstChild("MainScreenGui")
	local fallbackCurrencies = fallbackMain and fallbackMain:FindFirstChild("Currencies")
	local fallbackBackpack = fallbackCurrencies and fallbackCurrencies:FindFirstChild("Backpack")
	return fallbackBackpack and fallbackBackpack:FindFirstChild("Value") or nil
end

local function getBackpackText()
	local value = getBackpackValueObject()
	if not value then return nil end

	if value:IsA("TextLabel") or value:IsA("TextButton") or value:IsA("TextBox") then
		return value.Text
	end

	local success, result = pcall(function()
		return value.Text
	end)
	return success and tostring(result) or nil
end

local function isBackpackFull()
	local text = getBackpackText()
	if not text then return false, nil, nil end

	local current, maximum = text:match("(%d+)%s*/%s*(%d+)")
	current, maximum = tonumber(current), tonumber(maximum)
	return current and maximum and maximum > 0 and current >= maximum, current, maximum
end

local function instantAllPrompts()
	local count = 0
	for _, object in ipairs(zonesFolder:GetDescendants()) do
		if object:IsA("ProximityPrompt") then
			pcall(function()
				object.HoldDuration = 0
				object.MaxActivationDistance = math.max(object.MaxActivationDistance, 25)
			end)
			count += 1
		end
	end
	return count
end

local function pressE()
	if programClosed then return end
	VIM:SendKeyEvent(true, Enum.KeyCode.E, false, game)
	VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game)
end

local function startESpam()
	if eSpamRunning then return end
	eSpamRunning = true
	task.spawn(function()
		while eSpamRunning and gui.Parent do
			pressE()
			task.wait(E_SPAM_DELAY)
		end
	end)
end

local function stopESpam()
	eSpamRunning = false
end

local function activate(item)
	local prompt = getPrompt(item)
	if prompt then
		pcall(function() prompt.HoldDuration = 0 end)
		if typeof(fireproximityprompt) == "function" then
			pcall(function() fireproximityprompt(prompt) end)
		else
			pressE()
		end
	else
		pressE()
	end
end

local function scanItems()
	itemGroups = {}
	for _, object in ipairs(zonesFolder:GetDescendants()) do
		if object.Name == "SpawnZone" then
			for _, item in ipairs(object:GetChildren()) do
				if getPosition(item) then
					itemGroups[item.Name] = itemGroups[item.Name] or {}
					table.insert(itemGroups[item.Name], item)
				end
			end
		end
	end
end

local function selectedCount()
	local n = 0
	for _, value in pairs(selected) do if value then n += 1 end end
	return n
end

local function updateItemButton(name)
	local button = buttons[name]
	if not button then return end
	button.BackgroundColor3 = selected[name] and Color3.fromRGB(35, 156, 85) or Color3.fromRGB(34, 41, 49)
	button.Text = (selected[name] and "✓  " or "○  ") .. name
end

local function rebuildList()
	for _, button in pairs(buttons) do button:Destroy() end
	buttons = {}
	local names = {}
	for name in pairs(itemGroups) do table.insert(names, name) end
	table.sort(names, function(a, b) return a:lower() < b:lower() end)
	for _, name in ipairs(names) do
		local button = makeButton(list, name, UDim2.new(), UDim2.new(1, 0, 0, 36), Color3.fromRGB(34, 41, 49))
		button.TextXAlignment = Enum.TextXAlignment.Left
		local pad = Instance.new("UIPadding", button)
		pad.PaddingLeft = UDim.new(0, 12)
		buttons[name] = button
		updateItemButton(name)
		button.Activated:Connect(function()
			selected[name] = not selected[name]
			updateItemButton(name)
			status.Text = string.format("เลือกแล้ว %d ชนิด | E spam 0.01: %s", selectedCount(), eSpamRunning and "ON" or "OFF")
		end)
	end
end

search:GetPropertyChangedSignal("Text"):Connect(function()
	local keyword = search.Text:lower()
	for name, button in pairs(buttons) do
		button.Visible = keyword == "" or name:lower():find(keyword, 1, true) ~= nil
	end
end)

findButton.Activated:Connect(function()
	findButton.Text = "REFRESHING..."
	local promptCount = instantAllPrompts()
	scanItems()
	rebuildList()
	-- REFRESH ใช้รีเฟรชรายการเท่านั้น ไม่เปิด E spam ค้างไว้
	if not collecting and not looping then
		stopESpam()
	end
	local types = 0
	for _ in pairs(itemGroups) do types += 1 end
	status.Text = string.format("พบ %d ชนิด | Prompt %d | พร้อมเก็บ", types, promptCount)
	findButton.Text = "REFRESH"
end)

local function getItemPriority(itemName)
	-- ตัวอย่าง: 90_world = 90, 87_Abyss = 87
	return tonumber(tostring(itemName):match("^%s*(%d+)")) or -math.huge
end

local function findHighestPriorityUnvisited(visited)
	local bestItem, bestPriority, bestDistance
	for _, zone in ipairs(zonesFolder:GetDescendants()) do
		if zone.Name == "SpawnZone" then
			for _, item in ipairs(zone:GetChildren()) do
				if (findAllMode or selected[item.Name]) and not visited[item] then
					local pos = getPosition(item)
					if pos then
						local priority = getItemPriority(item.Name)
						local distance = (rootPart.Position - pos).Magnitude
						if not bestItem
							or priority > bestPriority
							or (priority == bestPriority and distance < bestDistance) then
							bestItem = item
							bestPriority = priority
							bestDistance = distance
						end
					end
				end
			end
		end
	end
	return bestItem
end

local function collectOneRound(original)
	collecting = true
	startESpam()
	local visited, count = {}, 0

	while collecting and not programClosed do
		local item = findHighestPriorityUnvisited(visited)
		if not item then break end
		visited[item] = true
		local pos = getPosition(item)
		if pos then
			status.Text = string.format("กำลังเก็บ %s | %d", item.Name, count + 1)
			rootPart.CFrame = CFrame.new(pos + WARP_OFFSET)
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero
			task.wait(0.05)
			activate(item)
			count += 1
			task.wait(ITEM_DELAY)

			local full, current, maximum = isBackpackFull()
			if full and rootPart and rootPart.Parent then
				status.Text = string.format("กระเป๋าเต็ม %d/%d | กลับจุดเดิมและรอ %.0f วินาที", current, maximum, BACKPACK_FULL_DELAY)
				rootPart.CFrame = original
				rootPart.AssemblyLinearVelocity = Vector3.zero
				rootPart.AssemblyAngularVelocity = Vector3.zero
				task.wait(BACKPACK_FULL_DELAY)
			end
		end
	end

	if programClosed then return count end

	if rootPart and rootPart.Parent then
		rootPart.CFrame = original
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end

	-- กลับถึงจุดเดิมแล้ว สแกนใหม่เหมือนกด REFRESH เพื่อรีเซ็ต Item
	instantAllPrompts()
	scanItems()
	rebuildList()
	collecting = false
	return count
end

warpButton.Activated:Connect(function()
	if looping then
		status.Text = "กำลังเปิด Loop อยู่ กด LOOP: ON เพื่อหยุด"
		return
	end
	if collecting then
		collecting = false
		return
	end
	if selectedCount() == 0 then
		status.Text = "กรุณาเลือก Item อย่างน้อย 1 รายการ"
		return
	end
	if not rootPart or not rootPart.Parent then updateCharacter() end

	warpButton.Text = "STOP"
	warpButton.BackgroundColor3 = Color3.fromRGB(190, 65, 65)
	local count = collectOneRound(rootPart.CFrame)
	if programClosed then return end
	stopESpam()
	warpButton.Text = "WARP"
	warpButton.BackgroundColor3 = Color3.fromRGB(32, 167, 91)
	status.Text = string.format("หา Item ไม่เจอแล้ว | เก็บ %d | กลับจุดเดิมแล้ว", count)
end)

local function resetContinuousButtons()
	loopButton.Text = "LOOP"
	loopButton.BackgroundColor3 = Color3.fromRGB(125, 79, 196)
	findAllButton.Text = "FIND ALL"
	findAllButton.BackgroundColor3 = Color3.fromRGB(205, 125, 39)
end

local function stopContinuous()
	continuousToken += 1
	looping = false
	findAllMode = false
	collecting = false
	resetContinuousButtons()
	status.Text = "กำลังหยุดและกลับจุดเดิม..."
end

local function startContinuous(allItems)
	if looping then
		stopContinuous()
		return
	end
	if not allItems and selectedCount() == 0 then
		status.Text = "กรุณาเลือก Item อย่างน้อย 1 รายการ"
		return
	end
	if not rootPart or not rootPart.Parent then updateCharacter() end

	continuousToken += 1
	local myToken = continuousToken
	looping = true
	findAllMode = allItems
	resetContinuousButtons()
	if allItems then
		findAllButton.Text = "ALL: ON"
		findAllButton.BackgroundColor3 = Color3.fromRGB(30, 181, 91)
	else
		loopButton.Text = "LOOP: ON"
		loopButton.BackgroundColor3 = Color3.fromRGB(30, 181, 91)
	end
	startESpam()
	local original = rootPart.CFrame

	task.spawn(function()
		local round = 0
		while looping and myToken == continuousToken and not programClosed do
			round += 1
			instantAllPrompts()
			scanItems()
			status.Text = string.format("%s รอบ %d | กำลังค้นหา...", allItems and "Find All" or "Loop", round)
			local count = collectOneRound(original)
			if programClosed or myToken ~= continuousToken then return end
			status.Text = string.format("%s รอบ %d | เก็บ %d | REFRESH แล้ว", allItems and "Find All" or "Loop", round, count)
			if looping then task.wait(LOOP_DELAY) end
		end

		if rootPart and rootPart.Parent then
			rootPart.CFrame = original
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero
		end
		if myToken == continuousToken then
			collecting = false
			findAllMode = false
			stopESpam()
			if not programClosed then
				resetContinuousButtons()
				status.Text = "หยุดแล้ว | กลับจุดเดิมและ REFRESH แล้ว"
			end
		end
	end)
end

loopButton.Activated:Connect(function()
	startContinuous(false)
end)

findAllButton.Activated:Connect(function()
	startContinuous(true)
end)

local minimized = false

local function setMinimized(value)
	if programClosed then return end
	minimized = value == true

	-- ต้องเปิด ScreenGui ไว้ ไม่เช่นนั้น Logo จะถูกซ่อนไปด้วย
	gui.Enabled = true
	main.Visible = not minimized
	logo.Visible = minimized
end

local function toggleMinimized()
	setMinimized(not minimized)
end

minimize.Activated:Connect(function()
	setMinimized(true)
end)

logo.Activated:Connect(function()
	setMinimized(false)
end)

close.Activated:Connect(function()
	if programClosed then return end
	programClosed = true
	continuousToken += 1
	looping = false
	findAllMode = false
	collecting = false
	stopESpam()
	gui.Enabled = false
	gui:Destroy()

	-- ถ้ารันผ่าน LocalScript ให้ลบตัว Script ด้วย
	pcall(function()
		if script and script:IsA("LocalScript") then
			script:Destroy()
		end
	end)
end)

UIS.InputBegan:Connect(function(input, processed)
	if not programClosed and input.KeyCode == TOGGLE_KEY then
		-- ใช้ Function เดียวกับปุ่ม - ด้านบน
		toggleMinimized()
	end
end)

scanItems()
rebuildList()
