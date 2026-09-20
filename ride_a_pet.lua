-- Find Egg - Group Select + Quantity + TP/Fly/Auto E + Auto Luck Range + Fly Speed + Cancel
-- Place this LocalScript in StarterPlayer > StarterPlayerScripts.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
local eggs = workspace:WaitForChild("RenderedEggs", 30)

if not eggs then
    warn("Find Egg: workspace.RenderedEggs missing")
    return
end

local playerGui = player:WaitForChild("PlayerGui")
local previousGui = playerGui:FindFirstChild("FindEggUI")
if previousGui then
    previousGui:Destroy()
end

local alive = true
local busy = false
local cancelled = false
local runId = 0
local highlighting = false

local selectedGroups = {}
local highlights = {}
local connections = {}
local shownPrompts = setmetatable({}, {__mode = "k"})
local stopActiveAutoE = nil

local movementMode = nil -- "TP" or "Fly"
local autoEEnabled = false
local autoModeEnabled = false
local currentRunSource = nil -- "manual" or "auto"
local autoProcessed = setmetatable({}, {__mode = "k"})
local autoScanScheduled = false

local MIN_FLY_SPEED = 300
local MAX_FLY_SPEED = 600
local FLY_SPEED_STEP = 25
local SPEED = 350

local COLORS = {
    panel = Color3.fromRGB(23, 29, 40),
    panel2 = Color3.fromRGB(16, 21, 30),
    row = Color3.fromRGB(42, 51, 66),
    blue = Color3.fromRGB(37, 153, 245),
    green = Color3.fromRGB(32, 178, 112),
    red = Color3.fromRGB(220, 72, 72),
    text = Color3.fromRGB(255, 255, 255),
    muted = Color3.fromRGB(183, 201, 220),
}

local rarityColors = {
    Common = Color3.fromRGB(225, 230, 235),
    Rare = Color3.fromRGB(50, 155, 255),
    Epic = Color3.fromRGB(180, 85, 255),
    Legendary = Color3.fromRGB(255, 195, 40),
    Mythic = Color3.fromRGB(255, 65, 110),
    Unknown = Color3.fromRGB(100, 255, 200),
}

local function make(className, props, parent)
    local object = Instance.new(className)
    for key, value in pairs(props) do
        object[key] = value
    end
    object.Parent = parent
    return object
end

local function addCorner(object, radius)
    make("UICorner", {CornerRadius = UDim.new(0, radius or 7)}, object)
end

local function button(text, size, position, parent, color)
    local object = make("TextButton", {
        Text = text,
        Size = size,
        Position = position,
        BackgroundColor3 = color or COLORS.blue,
        TextColor3 = COLORS.text,
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        BorderSizePixel = 0,
        AutoButtonColor = true,
    }, parent)
    addCorner(object, 7)
    return object
end

local gui = make("ScreenGui", {
    Name = "FindEggUI",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local highlightFolder = make("Folder", {Name = "FindEggHighlights"}, workspace)

local panel = make("Frame", {
    Size = UDim2.fromOffset(370, 660),
    Position = UDim2.new(0.5, -185, 0.5, -330),
    BackgroundColor3 = COLORS.panel,
    BorderSizePixel = 0,
}, gui)
addCorner(panel, 12)

local titleBar = make("TextLabel", {
    Text = "E | Find Egg - Group Mode",
    Active = true,
    Size = UDim2.new(1, -100, 0, 44),
    Position = UDim2.fromOffset(14, 0),
    BackgroundTransparency = 1,
    TextColor3 = COLORS.text,
    Font = Enum.Font.GothamBold,
    TextSize = 17,
    TextXAlignment = Enum.TextXAlignment.Left,
}, panel)

local minimize = button("−", UDim2.fromOffset(32, 28), UDim2.new(1, -80, 0, 9), panel)
local close = button("×", UDim2.fromOffset(32, 28), UDim2.new(1, -42, 0, 9), panel, COLORS.red)

local logo = button("E", UDim2.fromOffset(54, 54), UDim2.new(0.5, -27, 0.5, -27), gui)
logo.TextSize = 30
logo.Visible = false

local dragInput = nil
local dragStart = nil
local panelStart = nil

local logoInput = nil
local logoDragStart = nil
local logoPositionStart = nil
local logoWasDragged = false

table.insert(connections, titleBar.InputBegan:Connect(function(input)
    if dragInput then
        return
    end

    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
        dragStart = input.Position
        panelStart = panel.Position
    end
end))

table.insert(connections, UserInputService.InputChanged:Connect(function(input)
    if dragInput and panel.Visible then
        local mouse = dragInput.UserInputType == Enum.UserInputType.MouseButton1
        if (mouse and input.UserInputType == Enum.UserInputType.MouseMovement) or input == dragInput then
            local delta = input.Position - dragStart
            panel.Position = UDim2.new(
                panelStart.X.Scale,
                panelStart.X.Offset + delta.X,
                panelStart.Y.Scale,
                panelStart.Y.Offset + delta.Y
            )
        end
    end

    if logoInput and logo.Visible then
        local mouse = logoInput.UserInputType == Enum.UserInputType.MouseButton1
        if (mouse and input.UserInputType == Enum.UserInputType.MouseMovement) or input == logoInput then
            local delta = input.Position - logoDragStart
            if delta.Magnitude >= 6 then
                logoWasDragged = true
            end

            if logoWasDragged then
                logo.Position = UDim2.new(
                    logoPositionStart.X.Scale,
                    logoPositionStart.X.Offset + delta.X,
                    logoPositionStart.Y.Scale,
                    logoPositionStart.Y.Offset + delta.Y
                )
            end
        end
    end
end))

table.insert(connections, UserInputService.InputEnded:Connect(function(input)
    if input == dragInput then
        dragInput = nil
    end

    if input == logoInput then
        logoInput = nil
    end
end))

table.insert(connections, UserInputService.WindowFocusReleased:Connect(function()
    dragInput = nil
    logoInput = nil
    logoWasDragged = true
end))

table.insert(connections, logo.InputBegan:Connect(function(input)
    if logoInput then
        return
    end

    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        logoInput = input
        logoDragStart = input.Position
        logoPositionStart = logo.Position
        logoWasDragged = false
    end
end))

local function hidePanel()
    panel.Visible = false
    logo.Visible = true
end

minimize.Activated:Connect(hidePanel)

logo.Activated:Connect(function(input)
    if logoWasDragged and input and (
        input.UserInputType == Enum.UserInputType.MouseButton1 or
        input.UserInputType == Enum.UserInputType.Touch
    ) then
        return
    end

    panel.Visible = true
    logo.Visible = false
end)

local findEgg = button("Find Egg / Refresh", UDim2.new(1, -24, 0, 32), UDim2.fromOffset(12, 48), panel)
local selectAll = button("Select All Groups", UDim2.fromOffset(166, 30), UDim2.fromOffset(12, 90), panel)
local clearAll = button("Clear Groups", UDim2.fromOffset(166, 30), UDim2.fromOffset(192, 90), panel)

local list = make("ScrollingFrame", {
    Size = UDim2.new(1, -24, 1, -478),
    Position = UDim2.fromOffset(12, 130),
    BackgroundColor3 = COLORS.panel2,
    BorderSizePixel = 0,
    ScrollBarThickness = 5,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasSize = UDim2.new(),
}, panel)
addCorner(list, 7)
make("UIListLayout", {
    Padding = UDim.new(0, 5),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, list)

local quantityValue = 1

local quantityFrame = make("Frame", {
    Size = UDim2.new(1, -24, 0, 34),
    Position = UDim2.new(0, 12, 1, -340),
    BackgroundTransparency = 1,
}, panel)

local quantityLabel = make("TextLabel", {
    Text = "จำนวน / กลุ่ม",
    Size = UDim2.fromOffset(118, 32),
    Position = UDim2.fromOffset(0, 1),
    BackgroundTransparency = 1,
    TextColor3 = COLORS.muted,
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextXAlignment = Enum.TextXAlignment.Left,
}, quantityFrame)

local quantityMinus = button("−", UDim2.fromOffset(38, 32), UDim2.fromOffset(122, 1), quantityFrame, COLORS.row)

local quantityBox = make("TextBox", {
    Text = "1",
    Size = UDim2.fromOffset(82, 32),
    Position = UDim2.fromOffset(166, 1),
    BackgroundColor3 = COLORS.panel2,
    TextColor3 = COLORS.text,
    PlaceholderText = "1",
    ClearTextOnFocus = false,
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Center,
    BorderSizePixel = 0,
}, quantityFrame)
addCorner(quantityBox, 7)

local quantityPlus = button("+", UDim2.fromOffset(38, 32), UDim2.fromOffset(254, 1), quantityFrame, COLORS.row)

local quantityMaxLabel = make("TextLabel", {
    Text = "/ 1",
    Size = UDim2.fromOffset(48, 32),
    Position = UDim2.fromOffset(298, 1),
    BackgroundTransparency = 1,
    TextColor3 = COLORS.muted,
    Font = Enum.Font.Gotham,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Right,
}, quantityFrame)

local espButton = button("ESP Border: OFF", UDim2.new(1, -24, 0, 30), UDim2.new(0, 12, 1, -300), panel)

local optionFrame = make("Frame", {
    Size = UDim2.new(1, -24, 0, 34),
    Position = UDim2.new(0, 12, 1, -262),
    BackgroundTransparency = 1,
}, panel)

local function checkbox(text, x, width)
    local object = button("[ ] " .. text, UDim2.fromOffset(width, 32), UDim2.fromOffset(x, 1), optionFrame, COLORS.row)
    object.TextSize = 13
    return object
end

local tpCheck = checkbox("TP", 0, 104)
local flyCheck = checkbox("Fly", 112, 104)
local autoECheck = checkbox("Auto E", 224, 122)

local flySpeedFrame = make("Frame", {
    Size = UDim2.new(1, -24, 0, 34),
    Position = UDim2.new(0, 12, 1, -222),
    BackgroundTransparency = 1,
}, panel)

local flySpeedLabel = make("TextLabel", {
    Text = "Fly Speed",
    Size = UDim2.fromOffset(82, 32),
    Position = UDim2.fromOffset(0, 1),
    BackgroundTransparency = 1,
    TextColor3 = COLORS.muted,
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
}, flySpeedFrame)

local flySpeedMinus = button("−", UDim2.fromOffset(38, 32), UDim2.fromOffset(86, 1), flySpeedFrame, COLORS.row)

local flySpeedBox = make("TextBox", {
    Text = tostring(SPEED),
    Size = UDim2.fromOffset(70, 32),
    Position = UDim2.fromOffset(130, 1),
    BackgroundColor3 = COLORS.panel2,
    TextColor3 = COLORS.text,
    PlaceholderText = "350",
    ClearTextOnFocus = false,
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextXAlignment = Enum.TextXAlignment.Center,
    BorderSizePixel = 0,
}, flySpeedFrame)
addCorner(flySpeedBox, 7)

local flySpeedPlus = button("+", UDim2.fromOffset(38, 32), UDim2.fromOffset(206, 1), flySpeedFrame, COLORS.row)

local flySpeedRangeLabel = make("TextLabel", {
    Text = "300 - 600",
    Size = UDim2.fromOffset(96, 32),
    Position = UDim2.fromOffset(248, 1),
    BackgroundTransparency = 1,
    TextColor3 = COLORS.muted,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Right,
}, flySpeedFrame)

local autoRangeFrame = make("Frame", {
    Size = UDim2.new(1, -24, 0, 34),
    Position = UDim2.new(0, 12, 1, -182),
    BackgroundTransparency = 1,
}, panel)

local autoRangeLabel = make("TextLabel", {
    Text = "Auto Luck",
    Size = UDim2.fromOffset(72, 32),
    Position = UDim2.fromOffset(0, 1),
    BackgroundTransparency = 1,
    TextColor3 = COLORS.muted,
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
}, autoRangeFrame)

local autoMinBox = make("TextBox", {
    Text = "500B",
    Size = UDim2.fromOffset(88, 32),
    Position = UDim2.fromOffset(76, 1),
    BackgroundColor3 = COLORS.panel2,
    TextColor3 = COLORS.text,
    PlaceholderText = "500B",
    ClearTextOnFocus = false,
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextXAlignment = Enum.TextXAlignment.Center,
    BorderSizePixel = 0,
}, autoRangeFrame)
addCorner(autoMinBox, 7)

local autoRangeMiddle = make("TextLabel", {
    Text = "≤ Luck ≤",
    Size = UDim2.fromOffset(80, 32),
    Position = UDim2.fromOffset(168, 1),
    BackgroundTransparency = 1,
    TextColor3 = COLORS.muted,
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Center,
}, autoRangeFrame)

local autoMaxBox = make("TextBox", {
    Text = "1T",
    Size = UDim2.fromOffset(92, 32),
    Position = UDim2.fromOffset(252, 1),
    BackgroundColor3 = COLORS.panel2,
    TextColor3 = COLORS.text,
    PlaceholderText = "1T",
    ClearTextOnFocus = false,
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextXAlignment = Enum.TextXAlignment.Center,
    BorderSizePixel = 0,
}, autoRangeFrame)
addCorner(autoMaxBox, 7)

local autoButton = button("AUTO: OFF", UDim2.new(1, -24, 0, 30), UDim2.new(0, 12, 1, -142), panel, COLORS.row)

local startButton = button("START", UDim2.fromOffset(166, 32), UDim2.new(0, 12, 1, -104), panel, COLORS.green)
local cancelButton = button("CANCEL", UDim2.fromOffset(166, 32), UDim2.new(0, 192, 1, -104), panel, COLORS.red)
cancelButton.AutoButtonColor = false

local status = make("TextLabel", {
    Text = "Manual: select group(s) and START | Auto: set Luck range and press AUTO",
    Size = UDim2.new(1, -24, 0, 58),
    Position = UDim2.new(0, 12, 1, -66),
    BackgroundTransparency = 1,
    TextColor3 = COLORS.muted,
    TextSize = 12,
    Font = Enum.Font.Gotham,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
}, panel)

local function updateModeButtons()
    local tpOn = movementMode == "TP"
    local flyOn = movementMode == "Fly"

    tpCheck.Text = (tpOn and "[✓] " or "[ ] ") .. "TP"
    flyCheck.Text = (flyOn and "[✓] " or "[ ] ") .. "Fly"
    autoECheck.Text = (autoEEnabled and "[✓] " or "[ ] ") .. "Auto E"

    tpCheck.BackgroundColor3 = tpOn and COLORS.blue or COLORS.row
    flyCheck.BackgroundColor3 = flyOn and COLORS.blue or COLORS.row
    autoECheck.BackgroundColor3 = autoEEnabled and COLORS.blue or COLORS.row
end

local function updateAutoButton()
    if autoModeEnabled then
        autoButton.Text = "AUTO: ON"
        autoButton.BackgroundColor3 = COLORS.green
    else
        autoButton.Text = "AUTO: OFF"
        autoButton.BackgroundColor3 = COLORS.row
    end
end

local function updateRunButtons()
    if busy then
        startButton.Text = "WORKING..."
        startButton.BackgroundColor3 = COLORS.row
        startButton.AutoButtonColor = false

        cancelButton.Text = "CANCEL"
        cancelButton.BackgroundColor3 = COLORS.red
        cancelButton.AutoButtonColor = true
    else
        startButton.Text = "START"
        startButton.BackgroundColor3 = COLORS.green
        startButton.AutoButtonColor = true

        cancelButton.Text = "CANCEL"
        cancelButton.BackgroundColor3 = COLORS.row
        cancelButton.AutoButtonColor = false
    end
end

local function setFlySpeed(value)
    local numeric = tonumber(value) or SPEED
    numeric = math.floor(numeric + 0.5)
    SPEED = math.clamp(numeric, MIN_FLY_SPEED, MAX_FLY_SPEED)
    flySpeedBox.Text = tostring(SPEED)
    return SPEED
end

updateModeButtons()
updateAutoButton()
updateRunButtons()

local function parseRarity(value)
    if typeof(value) ~= "string" then
        return nil
    end

    local words = value:gsub("(%l)(%u)", "%1 %2"):lower()
    for word in words:gmatch("%a+") do
        for rarity in pairs(rarityColors) do
            if rarity ~= "Unknown" and word == rarity:lower() then
                return rarity
            end
        end
    end

    return nil
end

local function ownRarity(object)
    for _, key in ipairs({"Rarity", "rarity", "Tier", "Type", "EggType"}) do
        local rarity = parseRarity(object:GetAttribute(key))
        if rarity then
            return rarity
        end

        local valueObject = object:FindFirstChild(key)
        if valueObject and valueObject:IsA("StringValue") then
            rarity = parseRarity(valueObject.Value)
            if rarity then
                return rarity
            end
        end
    end

    return parseRarity(object.Name)
end

local function rarityOf(object)
    local current = object
    while current and current ~= eggs do
        local rarity = ownRarity(current)
        if rarity then
            return rarity
        end
        current = current.Parent
    end

    return "Unknown"
end

local function getLuckText(object)
    -- Normal path: Object -> Handle -> EggLuck -> Luck
    -- Recursive fallback helps when the game inserts an extra UI/container layer.
    local handle = object:FindFirstChild("Handle") or object:FindFirstChild("Handle", true)
    local eggLuck = handle and (handle:FindFirstChild("EggLuck") or handle:FindFirstChild("EggLuck", true))
    local luckObject = eggLuck and (eggLuck:FindFirstChild("Luck") or eggLuck:FindFirstChild("Luck", true))

    if luckObject then
        -- Read .Text generically so this works with TextLabel/TextButton/TextBox
        -- and remains tolerant of compatible UI objects.
        local okText, rawText = pcall(function()
            return luckObject.Text
        end)
        if okText then
            local text = tostring(rawText or ""):match("^%s*(.-)%s*$")
            if text ~= "" then
                return text
            end
        end

        if luckObject:IsA("StringValue") then
            local text = tostring(luckObject.Value or ""):match("^%s*(.-)%s*$")
            if text ~= "" then
                return text
            end
        end
    end

    return "Unknown"
end

local function getGroupKey(object)
    return getLuckText(object)
end

local function getGroupDisplayName(groupKey, objects)
    local objectName = "Egg"
    if objects and objects[1] then
        objectName = objects[1].Name
    end

    return string.format("%s (%s)", objectName, groupKey)
end


local LUCK_SUFFIX_MULTIPLIER = {
    [""] = 1,
    K = 1e3,
    M = 1e6,
    B = 1e9,
    T = 1e12,
    QA = 1e15,
    QI = 1e18,
    SX = 1e21,
    SP = 1e24,
    OC = 1e27,
    NO = 1e30,
    DC = 1e33,
}

local function luckToNumber(luckText)
    if not luckText or luckText == "Unknown" then
        return -math.huge
    end

    local normalized = tostring(luckText):upper():gsub(",", ""):gsub("%s+", "")
    local numberText, suffix = normalized:match("^([%+%-]?[%d%.]+)([%a]*)$")
    local numberValue = tonumber(numberText)

    if not numberValue then
        return -math.huge
    end

    local multiplier = LUCK_SUFFIX_MULTIPLIER[suffix]
    if not multiplier then
        return -math.huge
    end

    return numberValue * multiplier
end

local function cleanLuckInput(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function parseAutoRange()
    local minText = cleanLuckInput(autoMinBox.Text)
    local maxText = cleanLuckInput(autoMaxBox.Text)
    local minValue = luckToNumber(minText)
    local maxValue = luckToNumber(maxText)

    if minText == "" or minValue == -math.huge then
        return nil, nil, "Invalid Min Luck"
    end

    if maxText == "" or maxValue == -math.huge then
        return nil, nil, "Invalid Max Luck"
    end

    if minValue > maxValue then
        return nil, nil, "Min Luck must be <= Max Luck"
    end

    return minValue, maxValue, nil, minText, maxText
end

local function objectLuckNumber(object)
    return luckToNumber(getLuckText(object))
end

local function sortGroupNamesByLuckDesc(names, groups)
    table.sort(names, function(a, b)
        local luckA = luckToNumber(a)
        local luckB = luckToNumber(b)

        if luckA ~= luckB then
            return luckA > luckB
        end

        local displayA = getGroupDisplayName(a, groups[a]):lower()
        local displayB = getGroupDisplayName(b, groups[b]):lower()
        return displayA < displayB
    end)
end

local function getGroups()
    local groups = {}

    for _, object in ipairs(eggs:GetChildren()) do
        local groupKey = getGroupKey(object)
        groups[groupKey] = groups[groupKey] or {}
        table.insert(groups[groupKey], object)
    end

    return groups
end

local function getQuantityMax()
    local groups = getGroups()
    local maxCount = 0
    local hasSelected = false

    for groupName, objects in pairs(groups) do
        if selectedGroups[groupName] then
            hasSelected = true
            if #objects > maxCount then
                maxCount = #objects
            end
        end
    end

    if not hasSelected then
        for _, objects in pairs(groups) do
            if #objects > maxCount then
                maxCount = #objects
            end
        end
    end

    return math.max(1, maxCount)
end

local function setQuantity(value)
    local maxCount = getQuantityMax()
    local number = tonumber(value) or quantityValue or 1
    number = math.floor(number)
    number = math.clamp(number, 1, maxCount)

    quantityValue = number
    quantityBox.Text = tostring(number)
    quantityMaxLabel.Text = "/ " .. tostring(maxCount)
end

local function refreshQuantityLimit()
    setQuantity(quantityValue)
end

local function countSelectedGroups()
    local count = 0
    for _, enabled in pairs(selectedGroups) do
        if enabled then
            count += 1
        end
    end
    return count
end

local function clearHighlightsFor(object)
    local group = highlights[object]
    if not group then
        return
    end

    for _, h in ipairs(group) do
        if h and h.Parent then
            h:Destroy()
        end
    end
    highlights[object] = nil
end

local function syncHighlights()
    local wanted = {}
    local groupsSelected = countSelectedGroups() > 0

    local function collect(object)
        if object:IsA("BasePart") then
            wanted[object] = rarityOf(object)
            return
        end

        if object:IsA("Model") and object:FindFirstChildWhichIsA("BasePart", true) then
            if rarityColors[object.Name] then
                for _, child in ipairs(object:GetChildren()) do
                    collect(child)
                end
            else
                wanted[object] = rarityOf(object)
            end
            return
        end

        for _, child in ipairs(object:GetChildren()) do
            collect(child)
        end
    end

    if highlighting then
        for _, object in ipairs(eggs:GetChildren()) do
            if not groupsSelected or selectedGroups[getGroupKey(object)] then
                collect(object)
            end
        end
    end

    for object in pairs(highlights) do
        if not wanted[object] then
            clearHighlightsFor(object)
        end
    end

    local count = 0
    for object, rarity in pairs(wanted) do
        count += 1

        if not highlights[object] then
            highlights[object] = {
                make("Highlight", {
                    Name = "EggRarityESP",
                    Adornee = object,
                    Enabled = true,
                    FillTransparency = 1,
                    OutlineTransparency = 0,
                    OutlineColor = rarityColors[rarity],
                    DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
                }, highlightFolder),
            }
        end

        highlights[object][1].OutlineColor = rarityColors[rarity]
    end

    if highlighting then
        espButton.Text = string.format(
            "ESP Border: ON (%d • %s)",
            count,
            groupsSelected and "Selected Groups" or "All"
        )
    else
        espButton.Text = "ESP Border: OFF"
    end
end

local function refreshGroups(resetScroll)
    local groups = getGroups()

    for groupName in pairs(selectedGroups) do
        if not groups[groupName] then
            selectedGroups[groupName] = nil
        end
    end

    refreshQuantityLimit()

    for _, child in ipairs(list:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end

    local names = {}
    for groupName in pairs(groups) do
        table.insert(names, groupName)
    end

    sortGroupNamesByLuckDesc(names, groups)

    for index, groupName in ipairs(names) do
        local objectCount = #groups[groupName]
        local isSelected = selectedGroups[groupName] == true
        local displayName = getGroupDisplayName(groupName, groups[groupName])

        local row = button(
            string.format("%s  %s  (%dx)", isSelected and "SELECTED" or "SELECT", displayName, objectCount),
            UDim2.new(1, -8, 0, 34),
            UDim2.new(),
            list,
            isSelected and COLORS.blue or COLORS.row
        )

        row.LayoutOrder = index
        row.TextTruncate = Enum.TextTruncate.AtEnd
        row.TextXAlignment = Enum.TextXAlignment.Left
        row.Text = "  " .. row.Text

        row.Activated:Connect(function()
            if busy then
                status.Text = "Cancel current run before changing selected groups"
                return
            end

            selectedGroups[groupName] = not selectedGroups[groupName] or nil
            refreshGroups(false)
        end)
    end

    if resetScroll then
        list.CanvasPosition = Vector2.zero
    end

    syncHighlights()
end

local function isRunCancelled(thisRunId)
    return not alive or cancelled or runId ~= thisRunId
end

local function getCharacterParts()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")

    if not character or not humanoid or not root or humanoid.Health <= 0 then
        return nil, nil, nil
    end

    return character, humanoid, root
end

local function positionOf(object)
    if object:IsA("Attachment") then
        return object.WorldPosition
    end

    if object:IsA("BasePart") then
        return object.Position
    end

    if object:IsA("Model") and object:FindFirstChildWhichIsA("BasePart", true) then
        local bounds = object:GetBoundingBox()
        return bounds.Position
    end

    local part = object:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil
end

local function promptPosition(prompt)
    local parent = prompt.Parent
    if not parent then
        return nil
    end

    if parent:IsA("Attachment") or parent:IsA("BasePart") then
        return positionOf(parent)
    end

    if parent:IsA("Model") then
        if parent.PrimaryPart then
            return parent.PrimaryPart.Position
        end

        local part = parent:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end

    local part = parent:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil
end

local function getTargetPrompt(object)
    local candidates = object:GetDescendants()
    if object:IsA("ProximityPrompt") then
        table.insert(candidates, object)
    end

    for _, item in ipairs(candidates) do
        if item:IsA("ProximityPrompt") and item.Enabled and item.KeyboardKeyCode == Enum.KeyCode.E then
            local position = promptPosition(item)
            if position and item.MaxActivationDistance > 0 then
                return item
            end
        end
    end

    return nil
end

local function findNearestVisiblePrompt(root, preferredPrompt)
    local bestPrompt = nil
    local bestDistance = math.huge

    local function consider(prompt)
        if not prompt or not prompt.Parent or not prompt.Enabled then
            return
        end

        if prompt.KeyboardKeyCode ~= Enum.KeyCode.E or prompt.MaxActivationDistance <= 0 then
            return
        end

        local position = promptPosition(prompt)
        if not position then
            return
        end

        local distance = (position - root.Position).Magnitude
        if distance <= prompt.MaxActivationDistance and distance < bestDistance then
            bestPrompt = prompt
            bestDistance = distance
        end
    end

    consider(preferredPrompt)

    for prompt in pairs(shownPrompts) do
        if not prompt.Parent then
            shownPrompts[prompt] = nil
        else
            consider(prompt)
        end
    end

    return bestPrompt
end

local function waitCancelable(seconds, thisRunId)
    local deadline = os.clock() + seconds

    while os.clock() < deadline do
        if isRunCancelled(thisRunId) then
            return false
        end

        task.wait(math.min(0.03, math.max(0, deadline - os.clock())))
    end

    return not isRunCancelled(thisRunId)
end

local function moveCharacter(character, root, destination, mode, thisRunId)
    if isRunCancelled(thisRunId) then
        return false, "Cancelled"
    end

    local function place(cframe)
        character:PivotTo(cframe * root.CFrame:ToObjectSpace(character:GetPivot()))
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end

    if mode == "TP" then
        place(destination)
        return not isRunCancelled(thisRunId), isRunCancelled(thisRunId) and "Cancelled" or "TP completed"
    end

    local start = root.CFrame
    local distance = (destination.Position - start.Position).Magnitude
    local travelTime = distance / SPEED

    if travelTime > 60 then
        return false, "Flight exceeds 60 seconds"
    end

    if travelTime <= 0 then
        place(destination)
        return true, "Fly completed"
    end

    local elapsed = 0
    while elapsed < travelTime do
        if isRunCancelled(thisRunId) then
            return false, "Cancelled"
        end

        elapsed += RunService.Heartbeat:Wait()
        local alpha = math.min(elapsed / travelTime, 1)
        place(start:Lerp(destination, alpha))
    end

    return true, "Fly completed"
end

local function performAutoE(root, preferredPrompt, thisRunId)
    local promptData = {}
    local heldPrompt = nil
    local instantEnabled = true

    local function setupPrompt(prompt)
        if promptData[prompt] then
            return
        end

        local data = {
            OriginalDuration = prompt.HoldDuration,
        }
        promptData[prompt] = data

        data.HoldConnection = prompt:GetPropertyChangedSignal("HoldDuration"):Connect(function()
            if alive and instantEnabled and prompt.Parent and prompt.HoldDuration ~= 0 then
                prompt.HoldDuration = 0
            end
        end)

        prompt.HoldDuration = 0
    end

    local function cleanup()
        instantEnabled = false

        if heldPrompt then
            pcall(function()
                heldPrompt:InputHoldEnd()
            end)
            heldPrompt = nil
        end

        for prompt, data in pairs(promptData) do
            if data.HoldConnection then
                data.HoldConnection:Disconnect()
            end

            pcall(function()
                if prompt.Parent then
                    prompt.HoldDuration = data.OriginalDuration
                end
            end)
        end

        table.clear(promptData)
    end

    stopActiveAutoE = cleanup

    local deadline = os.clock() + 4
    local attempted = false
    local lastError = nil

    while os.clock() < deadline and not attempted do
        if isRunCancelled(thisRunId) then
            cleanup()
            if stopActiveAutoE == cleanup then
                stopActiveAutoE = nil
            end
            return false, "Cancelled"
        end

        local prompt = findNearestVisiblePrompt(root, preferredPrompt)
        if prompt then
            setupPrompt(prompt)
            status.Text = "Auto E: " .. prompt.Name

            local ok, err = pcall(function()
                heldPrompt = prompt
                prompt:InputHoldBegin()

                local holdTime = math.max(prompt.HoldDuration, 0.01)
                if not waitCancelable(holdTime, thisRunId) then
                    error("Cancelled")
                end

                prompt:InputHoldEnd()
                heldPrompt = nil
            end)

            if ok then
                attempted = true
            else
                lastError = tostring(err)
                if lastError == "Cancelled" or lastError:find("Cancelled", 1, true) then
                    cleanup()
                    if stopActiveAutoE == cleanup then
                        stopActiveAutoE = nil
                    end
                    return false, "Cancelled"
                end
            end
        end

        if not attempted then
            if not waitCancelable(0.05, thisRunId) then
                cleanup()
                if stopActiveAutoE == cleanup then
                    stopActiveAutoE = nil
                end
                return false, "Cancelled"
            end
        end
    end

    cleanup()
    if stopActiveAutoE == cleanup then
        stopActiveAutoE = nil
    end

    if attempted then
        return true, "Auto E sent"
    end

    return false, lastError or "No visible E prompt found"
end

local function visitObject(object, mode, useAutoE, returnOrigin, thisRunId)
    local character, humanoid, root = getCharacterParts()
    if not character then
        return false, "Character unavailable"
    end

    if root.Anchored or humanoid.SeatPart then
        return false, "Stand up and unanchor the character first"
    end

    if object.Parent ~= eggs then
        return false, "Target removed"
    end

    local targetPrompt = useAutoE and getTargetPrompt(object) or nil
    local targetPosition = targetPrompt and promptPosition(targetPrompt) or positionOf(object)

    if not targetPosition then
        return false, "No loaded target position"
    end

    local oldAutoRotate = humanoid.AutoRotate
    local oldPlatformStand = humanoid.PlatformStand
    local hoverConnection = nil

    local function valid()
        return player.Character == character and character.Parent and root.Parent and humanoid.Parent and humanoid.Health > 0
    end

    local function restoreCharacterState()
        if hoverConnection then
            hoverConnection:Disconnect()
            hoverConnection = nil
        end

        pcall(function()
            if root.Parent then
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end
        end)

        pcall(function()
            if humanoid.Parent then
                humanoid.AutoRotate = oldAutoRotate
                humanoid.PlatformStand = oldPlatformStand
            end
        end)
    end

    humanoid.AutoRotate = false
    humanoid.PlatformStand = true

    local offset = targetPrompt and math.min(2, targetPrompt.MaxActivationDistance * 0.5) or 3
    local destination = CFrame.new(targetPosition + Vector3.new(0, 0, offset))

    local moved, moveMessage = moveCharacter(character, root, destination, mode, thisRunId)
    if not moved then
        restoreCharacterState()
        return false, moveMessage
    end

    if not valid() then
        restoreCharacterState()
        return false, "Character changed or died"
    end

    if useAutoE then
        hoverConnection = RunService.Heartbeat:Connect(function()
            if not isRunCancelled(thisRunId) and valid() then
                character:PivotTo(destination * root.CFrame:ToObjectSpace(character:GetPivot()))
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end
        end)

        if not waitCancelable(0.15, thisRunId) then
            restoreCharacterState()
            return false, "Cancelled"
        end

        local interacted, interactMessage = performAutoE(root, targetPrompt, thisRunId)

        if hoverConnection then
            hoverConnection:Disconnect()
            hoverConnection = nil
        end

        if isRunCancelled(thisRunId) then
            restoreCharacterState()
            return false, "Cancelled"
        end

        if returnOrigin and valid() then
            status.Text = mode .. ": returning to start"
            local returned, returnMessage = moveCharacter(character, root, returnOrigin, mode, thisRunId)
            if not returned then
                restoreCharacterState()
                return false, returnMessage
            end
        end

        restoreCharacterState()

        if interacted then
            return true, interactMessage
        end

        return false, interactMessage
    end

    restoreCharacterState()
    return true, moveMessage
end

local function buildQueue(quantityLimit)
    local queue = {}
    local groups = getGroups()
    local names = {}

    for groupName in pairs(groups) do
        if selectedGroups[groupName] then
            table.insert(names, groupName)
        end
    end

    sortGroupNamesByLuckDesc(names, groups)

    for _, groupName in ipairs(names) do
        local objects = groups[groupName]
        local takeCount = math.min(quantityLimit, #objects)

        for index = 1, takeCount do
            table.insert(queue, objects[index])
        end
    end

    return queue
end

local function buildAutoQueue(minLuck, maxLuck)
    local queue = {}

    for _, object in ipairs(eggs:GetChildren()) do
        if object.Parent == eggs and not autoProcessed[object] then
            local luckNumber = objectLuckNumber(object)
            if luckNumber >= minLuck and luckNumber <= maxLuck then
                table.insert(queue, object)
            end
        end
    end

    table.sort(queue, function(a, b)
        local luckA = objectLuckNumber(a)
        local luckB = objectLuckNumber(b)

        if luckA ~= luckB then
            return luckA > luckB
        end

        return a.Name:lower() < b.Name:lower()
    end)

    return queue
end

local scheduleAutoScan

local function runAutoRange()
    if not alive or not autoModeEnabled or busy then
        return
    end

    if movementMode ~= "TP" and movementMode ~= "Fly" then
        autoModeEnabled = false
        updateAutoButton()
        status.Text = "AUTO stopped: choose TP or Fly first"
        return
    end

    local minLuck, maxLuck, rangeError, minText, maxText = parseAutoRange()
    if rangeError then
        autoModeEnabled = false
        updateAutoButton()
        status.Text = "AUTO stopped: " .. rangeError
        return
    end

    local queue = buildAutoQueue(minLuck, maxLuck)
    if #queue == 0 then
        status.Text = string.format("AUTO ON | waiting for %s <= Luck <= %s", minText, maxText)
        return
    end

    local character, _, root = getCharacterParts()
    if not character or not root then
        status.Text = "AUTO ON | waiting: character unavailable"
        task.delay(0.5, function()
            if alive and autoModeEnabled and scheduleAutoScan then
                scheduleAutoScan()
            end
        end)
        return
    end

    busy = true
    currentRunSource = "auto"
    cancelled = false
    runId += 1
    local thisRunId = runId
    local startOrigin = root.CFrame
    updateRunButtons()

    local successCount = 0
    local lastMessage = ""

    for index, object in ipairs(queue) do
        if isRunCancelled(thisRunId) or not autoModeEnabled then
            lastMessage = "Cancelled"
            break
        end

        -- Each instance is attempted once while AUTO remains enabled.
        -- A newly spawned/replaced instance can be processed normally.
        autoProcessed[object] = true

        local luckText = getLuckText(object)
        status.Text = string.format(
            "AUTO %s %d/%d: %s (%s)%s",
            movementMode,
            index,
            #queue,
            object.Name,
            luckText,
            autoEEnabled and " + Auto E" or ""
        )

        local callOk, success, message = pcall(
            visitObject,
            object,
            movementMode,
            autoEEnabled,
            autoEEnabled and startOrigin or nil,
            thisRunId
        )

        if not callOk then
            message = tostring(success)
            success = false
        end

        if success then
            successCount += 1
        end

        lastMessage = tostring(message or "")
        if not success and lastMessage ~= "Cancelled" then
            warn("Find Egg AUTO: " .. lastMessage)
        end

        if isRunCancelled(thisRunId) or not autoModeEnabled then
            lastMessage = "Cancelled"
            break
        end

        if not waitCancelable(0.12, thisRunId) then
            lastMessage = "Cancelled"
            break
        end
    end

    if runId == thisRunId then
        busy = false
        currentRunSource = nil
        updateRunButtons()

        if autoModeEnabled and not cancelled then
            status.Text = string.format(
                "AUTO ON | completed %d/%d | waiting for %s <= Luck <= %s",
                successCount,
                #queue,
                minText,
                maxText
            )
            task.defer(function()
                if alive and autoModeEnabled and scheduleAutoScan then
                    scheduleAutoScan()
                end
            end)
        else
            status.Text = string.format("AUTO stopped | completed %d/%d | %s", successCount, #queue, lastMessage)
        end
    end
end

scheduleAutoScan = function()
    if not alive or not autoModeEnabled or autoScanScheduled then
        return
    end

    autoScanScheduled = true
    task.defer(function()
        autoScanScheduled = false
        if alive and autoModeEnabled and not busy then
            runAutoRange()
        end
    end)
end

local function runSelected()
    if busy then
        return
    end

    if autoModeEnabled then
        status.Text = "Turn AUTO OFF before manual START"
        return
    end

    if movementMode ~= "TP" and movementMode ~= "Fly" then
        status.Text = "Choose TP or Fly first"
        return
    end

    setQuantity(quantityBox.Text)
    local queue = buildQueue(quantityValue)
    if #queue == 0 then
        status.Text = "Select at least one group first"
        return
    end

    local character, _, root = getCharacterParts()
    if not character or not root then
        status.Text = "Character unavailable"
        return
    end

    busy = true
    currentRunSource = "manual"
    cancelled = false
    runId += 1
    local thisRunId = runId
    local startOrigin = root.CFrame

    updateRunButtons()

    local successCount = 0
    local lastMessage = ""

    for index, object in ipairs(queue) do
        if isRunCancelled(thisRunId) then
            lastMessage = "Cancelled"
            break
        end

        status.Text = string.format(
            "%s %d/%d: %s%s",
            movementMode,
            index,
            #queue,
            object.Name,
            autoEEnabled and " + Auto E" or ""
        )
        status.Text = status.Text .. string.format(" | Qty/group: %d", quantityValue)

        local callOk, success, message = pcall(
            visitObject,
            object,
            movementMode,
            autoEEnabled,
            autoEEnabled and startOrigin or nil,
            thisRunId
        )

        if not callOk then
            message = tostring(success)
            success = false
        end

        if success then
            successCount += 1
        end

        lastMessage = tostring(message or "")

        if not success and lastMessage ~= "Cancelled" then
            warn("Find Egg: " .. lastMessage)
        end

        if isRunCancelled(thisRunId) then
            lastMessage = "Cancelled"
            break
        end

        if not waitCancelable(0.12, thisRunId) then
            lastMessage = "Cancelled"
            break
        end
    end

    if runId == thisRunId then
        busy = false
        currentRunSource = nil
        updateRunButtons()

        if cancelled then
            status.Text = string.format("Cancelled | completed %d/%d | Qty/group %d", successCount, #queue, quantityValue)
        else
            status.Text = string.format("Done %d/%d | Qty/group %d | %s", successCount, #queue, quantityValue, lastMessage)
        end
    end
end

local function cancelCurrentRun()
    local hadAuto = autoModeEnabled
    if hadAuto then
        autoModeEnabled = false
        updateAutoButton()
    end

    if not busy then
        status.Text = hadAuto and "AUTO stopped" or "Nothing is running"
        return
    end

    cancelled = true

    if stopActiveAutoE then
        pcall(stopActiveAutoE)
        stopActiveAutoE = nil
    end

    status.Text = hadAuto and "Cancelling... AUTO OFF" or "Cancelling..."
end

quantityMinus.Activated:Connect(function()
    if busy then
        status.Text = "Cancel current run before changing quantity"
        return
    end

    setQuantity(quantityValue - 1)
end)

quantityPlus.Activated:Connect(function()
    if busy then
        status.Text = "Cancel current run before changing quantity"
        return
    end

    setQuantity(quantityValue + 1)
end)

quantityBox.FocusLost:Connect(function()
    if busy then
        quantityBox.Text = tostring(quantityValue)
        return
    end

    setQuantity(quantityBox.Text)
end)

quantityBox:GetPropertyChangedSignal("Text"):Connect(function()
    if quantityBox:IsFocused() then
        local cleaned = quantityBox.Text:gsub("[^0-9]", "")
        if cleaned ~= quantityBox.Text then
            quantityBox.Text = cleaned
        end
    end
end)

flySpeedMinus.Activated:Connect(function()
    if busy then
        status.Text = "Cancel current run before changing Fly Speed"
        return
    end

    setFlySpeed(SPEED - FLY_SPEED_STEP)
    status.Text = string.format("Fly Speed: %d (range %d-%d)", SPEED, MIN_FLY_SPEED, MAX_FLY_SPEED)
end)

flySpeedPlus.Activated:Connect(function()
    if busy then
        status.Text = "Cancel current run before changing Fly Speed"
        return
    end

    setFlySpeed(SPEED + FLY_SPEED_STEP)
    status.Text = string.format("Fly Speed: %d (range %d-%d)", SPEED, MIN_FLY_SPEED, MAX_FLY_SPEED)
end)

flySpeedBox.FocusLost:Connect(function()
    if busy then
        flySpeedBox.Text = tostring(SPEED)
        return
    end

    setFlySpeed(flySpeedBox.Text)
    status.Text = string.format("Fly Speed: %d (range %d-%d)", SPEED, MIN_FLY_SPEED, MAX_FLY_SPEED)
end)

flySpeedBox:GetPropertyChangedSignal("Text"):Connect(function()
    if flySpeedBox:IsFocused() then
        local cleaned = flySpeedBox.Text:gsub("[^0-9]", "")
        if cleaned ~= flySpeedBox.Text then
            flySpeedBox.Text = cleaned
        end
    end
end)

findEgg.Activated:Connect(function()
    refreshGroups(true)
    if not busy then
        local groups = getGroups()
        local groupCount = 0
        local objectCount = 0

        for _, objects in pairs(groups) do
            groupCount += 1
            objectCount += #objects
        end

        status.Text = string.format("Refreshed: %d groups / %d objects", groupCount, objectCount)
    end
end)

selectAll.Activated:Connect(function()
    if busy then
        status.Text = "Cancel current run before changing selected groups"
        return
    end

    table.clear(selectedGroups)
    for groupName in pairs(getGroups()) do
        selectedGroups[groupName] = true
    end
    refreshGroups(false)
end)

clearAll.Activated:Connect(function()
    if busy then
        status.Text = "Cancel current run before changing selected groups"
        return
    end

    table.clear(selectedGroups)
    refreshGroups(false)
end)

espButton.Activated:Connect(function()
    highlighting = not highlighting
    syncHighlights()
end)

tpCheck.Activated:Connect(function()
    if busy then
        status.Text = "Cancel current run before changing TP/Fly"
        return
    end

    movementMode = movementMode == "TP" and nil or "TP"
    updateModeButtons()
    if autoModeEnabled then scheduleAutoScan() end
end)

flyCheck.Activated:Connect(function()
    if busy then
        status.Text = "Cancel current run before changing TP/Fly"
        return
    end

    movementMode = movementMode == "Fly" and nil or "Fly"
    updateModeButtons()
    if autoModeEnabled then scheduleAutoScan() end
end)

autoECheck.Activated:Connect(function()
    if busy then
        status.Text = "Cancel current run before changing Auto E"
        return
    end

    autoEEnabled = not autoEEnabled
    updateModeButtons()
    if autoModeEnabled then scheduleAutoScan() end
end)

local function normalizeAutoRangeBoxes()
    autoMinBox.Text = cleanLuckInput(autoMinBox.Text):upper()
    autoMaxBox.Text = cleanLuckInput(autoMaxBox.Text):upper()

    local _, _, rangeError = parseAutoRange()
    if rangeError then
        status.Text = rangeError
        return false
    end

    if autoModeEnabled then
        scheduleAutoScan()
    end
    return true
end

autoMinBox.FocusLost:Connect(normalizeAutoRangeBoxes)
autoMaxBox.FocusLost:Connect(normalizeAutoRangeBoxes)

autoButton.Activated:Connect(function()
    if autoModeEnabled then
        autoModeEnabled = false
        updateAutoButton()

        if busy and currentRunSource == "auto" then
            cancelled = true
            if stopActiveAutoE then
                pcall(stopActiveAutoE)
                stopActiveAutoE = nil
            end
            status.Text = "Stopping AUTO..."
        else
            status.Text = "AUTO OFF"
        end
        return
    end

    if busy then
        status.Text = "Cancel current run before enabling AUTO"
        return
    end

    if movementMode ~= "TP" and movementMode ~= "Fly" then
        status.Text = "Choose TP or Fly before AUTO"
        return
    end

    if not normalizeAutoRangeBoxes() then
        return
    end

    table.clear(autoProcessed)
    cancelled = false
    autoModeEnabled = true
    updateAutoButton()
    scheduleAutoScan()
end)

startButton.Activated:Connect(runSelected)
cancelButton.Activated:Connect(cancelCurrentRun)

table.insert(connections, ProximityPromptService.PromptShown:Connect(function(prompt)
    shownPrompts[prompt] = true
end))

table.insert(connections, ProximityPromptService.PromptHidden:Connect(function(prompt)
    shownPrompts[prompt] = nil
end))

local refreshScheduled = false
local function scheduleRefresh()
    if refreshScheduled then
        return
    end

    refreshScheduled = true
    task.defer(function()
        refreshScheduled = false
        if alive then
            refreshGroups(false)
            if autoModeEnabled and scheduleAutoScan then
                scheduleAutoScan()
            end
        end
    end)
end

-- RenderedEggs can stream in gradually. An object may be parented first,
-- then Handle -> EggLuck -> Luck (and Luck.Text) can arrive a little later.
-- Refresh grouping whenever descendants change so temporary Unknown groups
-- automatically become their real Luck groups (for example 1T).
local luckTextConnections = setmetatable({}, {__mode = "k"})

local function watchLuckText(instance)
    if not instance or instance.Name ~= "Luck" or luckTextConnections[instance] then
        return
    end

    local canReadText = pcall(function()
        local _ = instance.Text
    end)

    if not canReadText then
        return
    end

    local ok, connection = pcall(function()
        return instance:GetPropertyChangedSignal("Text"):Connect(scheduleRefresh)
    end)

    if ok and connection then
        luckTextConnections[instance] = connection
        table.insert(connections, connection)
    end
end

-- Watch Luck labels that already exist when this LocalScript starts.
for _, descendant in ipairs(eggs:GetDescendants()) do
    watchLuckText(descendant)
end

table.insert(connections, eggs.ChildAdded:Connect(scheduleRefresh))
table.insert(connections, eggs.ChildRemoved:Connect(scheduleRefresh))
table.insert(connections, eggs.DescendantAdded:Connect(function(descendant)
    watchLuckText(descendant)
    scheduleRefresh()

    if highlighting then
        syncHighlights()
    end
end))
table.insert(connections, eggs.DescendantRemoving:Connect(function()
    scheduleRefresh()

    if highlighting then
        task.defer(syncHighlights)
    end
end))

local rarityElapsed = 0
table.insert(connections, RunService.Heartbeat:Connect(function(dt)
    if not highlighting then
        rarityElapsed = 0
        return
    end

    rarityElapsed += dt
    if rarityElapsed >= 1 then
        rarityElapsed = 0
        syncHighlights()
    end
end))

close.Activated:Connect(function()
    cancelCurrentRun()
    alive = false
    gui:Destroy()
end)

gui.Destroying:Connect(function()
    alive = false
    autoModeEnabled = false
    cancelled = true
    runId += 1

    if stopActiveAutoE then
        pcall(stopActiveAutoE)
        stopActiveAutoE = nil
    end

    for _, connection in ipairs(connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    if highlightFolder and highlightFolder.Parent then
        highlightFolder:Destroy()
    end
end)

refreshGroups(true)
