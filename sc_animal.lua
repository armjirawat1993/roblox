
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Config = {
    FlySpeed = 40,
    MinFlySpeed = 10,
    MaxFlySpeed = 200,
    ToggleKey = Enum.KeyCode.RightShift,
    ESPColor = Color3.fromRGB(70, 245, 255),
    AutoFarmClickInterval = 0.01,
    AutoFarmBehindDistance = 5, -- เพิ่มจาก 3 เป็น 5 studs
    AutoFarmMode = "Fly", -- fixed Fly mode
    AutoFarmEnabled = false,
    AutoFarmFlySpeed = 40,
    AutoFarmMinFlySpeed = 10,
    AutoFarmMaxFlySpeed = 200,
    AutoAttackEnabled = false,
    AutoAttackInterval = 0.30,
    AutoAttackMinInterval = 0.05,
    AutoAttackMaxInterval = 1.00,
    PlayerESPEnabled = false,
    PlayerNameEnabled = false,
    PlayerESPColor = Color3.fromRGB(255, 80, 80),
    PlayerFlyEnabled = false,
    PlayerNoClipEnabled = false,
    AtkPlayerEnabled = false,
    AtkPlayerNearbyEnabled = false,
    AtkPlayerSide = "Behind", -- fixed behind
    AtkPlayerDistance = 3,
    MinAtkPlayerDistance = 1,
    MaxAtkPlayerDistance = 6,
    RemoveLightingEffects = false,
    BrightLightingEnabled = false,
}

local State = {
    Closed = false,
    DraggingWindow = false,
    WindowDragStart = nil,
    WindowStartPosition = nil,
    SelectedNPCGroups = {},
    SelectedFarmGroups = {},
    AutoFarmWorker = nil,
    AutoFarmActiveTween = nil,
    DraggingAutoFarmSlider = false,
    AutoAttackWorker = nil,
    DraggingAutoAttackSlider = false,
    SelectedPlayers = {},
    PlayerESPObjects = {},
    PlayerFlyWorker = nil,
    PlayerFlyBodyVelocity = nil,
    PlayerFlyBodyGyro = nil,
    DraggingPlayerFlySlider = false,
    PlayerNoClipWorker = nil,
    PlayerNoClipOriginal = {},
    AtkPlayerWorker = nil,
    NearbyAtkTargetUserId = nil,
    AtkPlayerActiveTween = nil,
    DraggingAtkPlayerDistanceSlider = false,
    LightingEffectBackup = {},
    LightingOriginal = nil,
}

local UI = {}
local connections = {}
local refreshAtkPlayerList

local function addConnection(connection)
    table.insert(connections, connection)
    return connection
end

local function getCharacter()
    return player.Character
end

local function getRootPart()
    local character = getCharacter()
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function getGuiParent()
    local ok, hidden = pcall(function()
        if typeof(gethui) == "function" then
            return gethui()
        end
        return nil
    end)

    if ok and hidden then
        return hidden
    end

    local canCore = pcall(function()
        local probe = Instance.new("Folder")
        probe.Parent = CoreGui
        probe:Destroy()
    end)

    if canCore then
        return CoreGui
    end

    return playerGui
end

local function destroyOldGui(parent)
    if not parent then return end
    local old = parent:FindFirstChild("AnimalWorldUI") or parent:FindFirstChild("FeralAmberTigerUI")
    if old then old:Destroy() end
end

local guiParent = getGuiParent()
destroyOldGui(playerGui)
destroyOldGui(CoreGui)
destroyOldGui(guiParent)

local function isRemovableLightingEffect(object)
    return object:IsA("PostEffect")
        or object:IsA("Atmosphere")
        or object:IsA("Sky")
end

local function backupAndRemoveLightingEffect(object)
    if not object or object.Parent ~= Lighting or not isRemovableLightingEffect(object) then
        return
    end

    local ok, clone = pcall(function()
        return object:Clone()
    end)

    if ok and clone then
        table.insert(State.LightingEffectBackup, clone)
    end

    pcall(function() object:Destroy() end)
end

local function setRemoveLightingEffects(enabled)
    Config.RemoveLightingEffects = enabled and true or false

    if Config.RemoveLightingEffects then
        State.LightingEffectBackup = {}
        for _, object in ipairs(Lighting:GetChildren()) do
            backupAndRemoveLightingEffect(object)
        end
    else
        for _, clone in ipairs(State.LightingEffectBackup) do
            if clone then
                local exists = false
                for _, current in ipairs(Lighting:GetChildren()) do
                    if current.ClassName == clone.ClassName and current.Name == clone.Name then
                        exists = true
                        break
                    end
                end
                if not exists then
                    pcall(function() clone.Parent = Lighting end)
                else
                    pcall(function() clone:Destroy() end)
                end
            end
        end
        State.LightingEffectBackup = {}
    end

    if UI.effectToggle then
        UI.effectToggle.Text = Config.RemoveLightingEffects and "ON" or "OFF"
        UI.effectToggle.BackgroundColor3 = Config.RemoveLightingEffects
            and Color3.fromRGB(45, 170, 95)
            or Color3.fromRGB(75, 75, 88)
    end
end

local function setBrightLighting(enabled)
    Config.BrightLightingEnabled = enabled and true or false

    if Config.BrightLightingEnabled then
        if not State.LightingOriginal then
            State.LightingOriginal = {
                Brightness = Lighting.Brightness,
                Ambient = Lighting.Ambient,
                OutdoorAmbient = Lighting.OutdoorAmbient,
            }
        end
        Lighting.Brightness = 3
        Lighting.Ambient = Color3.fromRGB(175, 175, 175)
        Lighting.OutdoorAmbient = Color3.fromRGB(175, 175, 175)
    elseif State.LightingOriginal then
        Lighting.Brightness = State.LightingOriginal.Brightness
        Lighting.Ambient = State.LightingOriginal.Ambient
        Lighting.OutdoorAmbient = State.LightingOriginal.OutdoorAmbient
        State.LightingOriginal = nil
    end

    if UI.brightnessToggle then
        UI.brightnessToggle.Text = Config.BrightLightingEnabled and "ON" or "OFF"
        UI.brightnessToggle.BackgroundColor3 = Config.BrightLightingEnabled
            and Color3.fromRGB(45, 170, 95)
            or Color3.fromRGB(75, 75, 88)
    end
end

local NPC_ESP_NAME = "FeralTigerNPCESP"
local npcESPHighlights = {}

local function getFeralNPCFolder()
    return workspace:FindFirstChild("FeralNPCs")
end

local function getNPCGroups()
    local groups = {}
    local folder = getFeralNPCFolder()
    if not folder then
        return groups
    end

    for _, object in ipairs(folder:GetChildren()) do
        if object:IsA("Model") then
            local name = object.Name
            groups[name] = groups[name] or {}
            table.insert(groups[name], object)
        end
    end

    return groups
end

local function removeNPCESP(model)
    local highlight = npcESPHighlights[model]
    if highlight then
        pcall(function() highlight:Destroy() end)
        npcESPHighlights[model] = nil
    end

    if model and model.Parent then
        local existing = model:FindFirstChild(NPC_ESP_NAME)
        if existing and existing:IsA("Highlight") then
            existing:Destroy()
        end
    end
end

local function applyNPCESP(model)
    if not model or not model.Parent or not model:IsA("Model") then
        return
    end
    if not State.SelectedNPCGroups[model.Name] then
        removeNPCESP(model)
        return
    end

    local highlight = model:FindFirstChild(NPC_ESP_NAME)
    if not highlight then
        highlight = Instance.new("Highlight")
        highlight.Name = NPC_ESP_NAME
        highlight.Parent = model
    end

    highlight.Adornee = model
    highlight.Enabled = true
    highlight.FillColor = Config.ESPColor
    highlight.FillTransparency = 0.65
    highlight.OutlineColor = Config.ESPColor
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    npcESPHighlights[model] = highlight
end

local function refreshNPCESP()
    local folder = getFeralNPCFolder()

    for model in pairs(npcESPHighlights) do
        if not model.Parent
            or not folder
            or not model:IsDescendantOf(folder)
            or not State.SelectedNPCGroups[model.Name] then
            removeNPCESP(model)
        end
    end

    if not folder then
        return
    end

    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") and State.SelectedNPCGroups[model.Name] then
            applyNPCESP(model)
        end
    end
end

local function clearNPCESP()
    local models = {}
    for model in pairs(npcESPHighlights) do
        table.insert(models, model)
    end
    for _, model in ipairs(models) do
        removeNPCESP(model)
    end
end

local function sameColor(a, b)
    return math.abs(a.R - b.R) < 0.001
        and math.abs(a.G - b.G) < 0.001
        and math.abs(a.B - b.B) < 0.001
end

local setAutoAttackEnabled

local PLAYER_ESP_NAME = "FeralTigerPlayerESP"
local PLAYER_NAME_GUI = "FeralTigerPlayerName"

local function getPlayerRoot(plr)
    local character = plr and plr.Character
    if not character then return nil end
    return character:FindFirstChild("HumanoidRootPart")
        or character.PrimaryPart
        or character:FindFirstChildWhichIsA("BasePart", true)
end

local function isPlayerAlive(plr)
    if not plr or plr == player then return false end
    local character = plr.Character
    if not character or not character.Parent then return false end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health > 0 and getPlayerRoot(plr) ~= nil
end

local function removePlayerHighlight(plr)
    local character = plr and plr.Character
    if character then
        local oldH = character:FindFirstChild(PLAYER_ESP_NAME)
        if oldH then oldH:Destroy() end
    end
    local data = State.PlayerESPObjects[plr]
    if data then data.Highlight = nil end
end

local function removePlayerName(plr)
    local character = plr and plr.Character
    if character then
        local oldN = character:FindFirstChild(PLAYER_NAME_GUI)
        if oldN then oldN:Destroy() end
    end
    local data = State.PlayerESPObjects[plr]
    if data then data.Billboard = nil end
end

local function removePlayerESP(plr)
    removePlayerHighlight(plr)
    removePlayerName(plr)
    State.PlayerESPObjects[plr] = nil
end

local function applyPlayerESP(plr)
    if not isPlayerAlive(plr) then
        removePlayerESP(plr)
        return
    end

    local character = plr.Character
    local root = getPlayerRoot(plr)
    if not character or not root then return end

    State.PlayerESPObjects[plr] = State.PlayerESPObjects[plr] or {}
    local data = State.PlayerESPObjects[plr]

    if Config.PlayerESPEnabled then
        local highlight = character:FindFirstChild(PLAYER_ESP_NAME)
        if not highlight then
            highlight = Instance.new("Highlight")
            highlight.Name = PLAYER_ESP_NAME
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.FillTransparency = 0.55
            highlight.OutlineTransparency = 0
            highlight.Parent = character
        end
        highlight.FillColor = Config.PlayerESPColor
        highlight.OutlineColor = Config.PlayerESPColor
        data.Highlight = highlight
    else
        removePlayerHighlight(plr)
    end

    if Config.PlayerNameEnabled then
        local billboard = character:FindFirstChild(PLAYER_NAME_GUI)
        if not billboard then
            billboard = Instance.new("BillboardGui")
            billboard.Name = PLAYER_NAME_GUI
            billboard.Adornee = character:FindFirstChild("Head") or root
            billboard.Size = UDim2.fromOffset(230, 62)
            billboard.StudsOffset = Vector3.new(0, 4.5, 0)
            billboard.AlwaysOnTop = true
            billboard.MaxDistance = 1000
            billboard.Parent = character

            local label = Instance.new("TextLabel")
            label.Name = "Label"
            label.Size = UDim2.fromScale(1, 1)
            label.BackgroundTransparency = 1
            label.TextColor3 = Color3.new(1,1,1)
            label.TextStrokeTransparency = 0
            label.TextSize = 14
            label.Font = Enum.Font.GothamBold
            label.Parent = billboard
        end

        local label = billboard:FindFirstChild("Label")
        if label then
            local species = character:GetAttribute("Species") or character.Name
            local myRoot = getPlayerRoot(player)
            local distanceText = "-- m"
            if myRoot and root then
                local distanceStuds = (myRoot.Position - root.Position).Magnitude
                local distanceMeters = distanceStuds * 0.28
                distanceText = string.format("%.1f m", distanceMeters)
            end
            label.Text = plr.Name .. "\n" .. tostring(species) .. "  •  " .. distanceText
            label.TextColor3 = Config.PlayerESPColor
        end
        data.Billboard = billboard
    else
        removePlayerName(plr)
    end

    if not Config.PlayerESPEnabled and not Config.PlayerNameEnabled then
        State.PlayerESPObjects[plr] = nil
    end
end

local function refreshPlayerESP()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player then
            applyPlayerESP(plr)
        end
    end
    for plr in pairs(State.PlayerESPObjects) do
        if not plr.Parent then
            removePlayerESP(plr)
        end
    end
end

local function clearPlayerESP()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player then removePlayerHighlight(plr) end
    end
end

local function clearPlayerNames()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player then removePlayerName(plr) end
    end
end

local function setPlayerESPEnabled(enabled)
    Config.PlayerESPEnabled = enabled == true
    refreshPlayerESP()
    if UI.playerESPToggle then
        UI.playerESPToggle.Text = Config.PlayerESPEnabled and "ON" or "OFF"
        UI.playerESPToggle.BackgroundColor3 = Config.PlayerESPEnabled and Color3.fromRGB(45,170,95) or Color3.fromRGB(75,75,88)
    end
end

local function setPlayerNameEnabled(enabled)
    Config.PlayerNameEnabled = enabled == true
    refreshPlayerESP()
    if UI.playerNameToggle then
        UI.playerNameToggle.Text = Config.PlayerNameEnabled and "ON" or "OFF"
        UI.playerNameToggle.BackgroundColor3 = Config.PlayerNameEnabled and Color3.fromRGB(45,170,95) or Color3.fromRGB(75,75,88)
    end
end

local function stopPlayerFly()
    if State.PlayerFlyWorker then
        task.cancel(State.PlayerFlyWorker)
        State.PlayerFlyWorker = nil
    end
    if State.PlayerFlyBodyVelocity then pcall(function() State.PlayerFlyBodyVelocity:Destroy() end) end
    if State.PlayerFlyBodyGyro then pcall(function() State.PlayerFlyBodyGyro:Destroy() end) end
    State.PlayerFlyBodyVelocity = nil
    State.PlayerFlyBodyGyro = nil
end

local function startPlayerFly()
    stopPlayerFly()
    if State.Closed or not Config.PlayerFlyEnabled then return end

    State.PlayerFlyWorker = task.spawn(function()
        while not State.Closed and Config.PlayerFlyEnabled do
            local root = getRootPart()
            local character = getCharacter()
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if root and humanoid and humanoid.Health > 0 then
                local bv = Instance.new("BodyVelocity")
                bv.Name = "TigerUI_PlayerFlyVelocity"
                bv.MaxForce = Vector3.new(1e9,1e9,1e9)
                bv.P = 1e4
                bv.Velocity = Vector3.zero
                bv.Parent = root

                local bg = Instance.new("BodyGyro")
                bg.Name = "TigerUI_PlayerFlyGyro"
                bg.MaxTorque = Vector3.new(1e9,1e9,1e9)
                bg.P = 1e4
                bg.CFrame = root.CFrame
                bg.Parent = root

                State.PlayerFlyBodyVelocity = bv
                State.PlayerFlyBodyGyro = bg

                while Config.PlayerFlyEnabled and not State.Closed and root.Parent and humanoid.Health > 0 do
                    local camera = Workspace.CurrentCamera
                    local move = Vector3.zero
                    if camera then
                        local cf = camera.CFrame
                        local forward = cf.LookVector
                        local right = cf.RightVector
                        if forward.Magnitude > 0.01 then forward = forward.Unit end
                        if right.Magnitude > 0.01 then right = right.Unit end

                        if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += forward end
                        if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= forward end
                        if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += right end
                        if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= right end
                        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.new(0,1,0) end
                        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then move -= Vector3.new(0,1,0) end

                        if move.Magnitude > 0 then move = move.Unit end
                        bv.Velocity = move * Config.FlySpeed
                        bg.CFrame = CFrame.lookAt(root.Position, root.Position + cf.LookVector)
                    else
                        bv.Velocity = Vector3.zero
                    end
                    task.wait()
                end

                if bv.Parent then bv:Destroy() end
                if bg.Parent then bg:Destroy() end
                State.PlayerFlyBodyVelocity = nil
                State.PlayerFlyBodyGyro = nil
            else
                task.wait(0.2)
            end
        end
        State.PlayerFlyWorker = nil
    end)
end

local function setPlayerFlyEnabled(enabled)
    Config.PlayerFlyEnabled = enabled == true
    if Config.PlayerFlyEnabled then startPlayerFly() else stopPlayerFly() end
    if UI.playerFlyToggle then
        UI.playerFlyToggle.Text = Config.PlayerFlyEnabled and "ON" or "OFF"
        UI.playerFlyToggle.BackgroundColor3 = Config.PlayerFlyEnabled and Color3.fromRGB(45,170,95) or Color3.fromRGB(75,75,88)
    end
end

State.stopPlayerNoClip = function()
    if State.PlayerNoClipWorker then
        task.cancel(State.PlayerNoClipWorker)
        State.PlayerNoClipWorker = nil
    end

    for part, oldCanCollide in pairs(State.PlayerNoClipOriginal) do
        if typeof(part) == "Instance" and part.Parent and part:IsA("BasePart") then
            pcall(function() part.CanCollide = oldCanCollide end)
        end
    end
    table.clear(State.PlayerNoClipOriginal)
end

State.startPlayerNoClip = function()
    State.stopPlayerNoClip()
    if State.Closed or not Config.PlayerNoClipEnabled then return end

    State.PlayerNoClipWorker = task.spawn(function()
        while not State.Closed and Config.PlayerNoClipEnabled do
            local character = getCharacter()
            if character then
                for _, obj in ipairs(character:GetDescendants()) do
                    if obj:IsA("BasePart") then
                        if State.PlayerNoClipOriginal[obj] == nil then
                            State.PlayerNoClipOriginal[obj] = obj.CanCollide
                        end
                        obj.CanCollide = false
                    end
                end
            end
            task.wait(0.12)
        end
        State.PlayerNoClipWorker = nil
    end)
end

State.setPlayerNoClipEnabled = function(enabled)
    Config.PlayerNoClipEnabled = enabled == true
    if Config.PlayerNoClipEnabled then
        State.startPlayerNoClip()
    else
        State.stopPlayerNoClip()
    end

    if UI.playerNoClipToggle then
        UI.playerNoClipToggle.Text = Config.PlayerNoClipEnabled and "ON" or "OFF"
        UI.playerNoClipToggle.BackgroundColor3 = Config.PlayerNoClipEnabled and Color3.fromRGB(45,170,95) or Color3.fromRGB(75,75,88)
    end
end

local function hasSelectedPlayer()
    for userId, enabled in pairs(State.SelectedPlayers) do
        if enabled then
            local plr = Players:GetPlayerByUserId(tonumber(userId))
            if plr and isPlayerAlive(plr) then return true end
        end
    end
    return false
end

local function getNearestAlivePlayer()
    local root = getRootPart()
    if not root then return nil end

    local best, bestDist = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and isPlayerAlive(plr) then
            local pr = getPlayerRoot(plr)
            if pr then
                local d = (pr.Position - root.Position).Magnitude
                if d < bestDist then
                    best, bestDist = plr, d
                end
            end
        end
    end
    return best
end

local function getNearestSelectedPlayer()
    local root = getRootPart()
    if not root then return nil end
    local best, bestDist = nil, math.huge
    for userId, enabled in pairs(State.SelectedPlayers) do
        if enabled then
            local plr = Players:GetPlayerByUserId(tonumber(userId))
            if plr and isPlayerAlive(plr) then
                local pr = getPlayerRoot(plr)
                if pr then
                    local d = (pr.Position - root.Position).Magnitude
                    if d < bestDist then best, bestDist = plr, d end
                end
            end
        end
    end
    return best
end

local function getNearbyAtkPlayer()
    if not Config.AtkPlayerNearbyEnabled then return nil end

    local current = State.NearbyAtkTargetUserId
        and Players:GetPlayerByUserId(State.NearbyAtkTargetUserId) or nil

    if current and isPlayerAlive(current) then
        return current
    end

    State.NearbyAtkTargetUserId = nil
    local nextPlayer = getNearestAlivePlayer()
    table.clear(State.SelectedPlayers)
    State.NearbyAtkTargetUserId = nil

    if nextPlayer then
        State.NearbyAtkTargetUserId = nextPlayer.UserId
        State.SelectedPlayers[tostring(nextPlayer.UserId)] = true
    end

    if refreshAtkPlayerList then
        task.defer(refreshAtkPlayerList)
    end

    return nextPlayer
end

local function getAtkPlayerTarget()
    if Config.AtkPlayerNearbyEnabled then
        return getNearbyAtkPlayer()
    end
    return getNearestSelectedPlayer()
end

local function cancelAtkPlayerTween()
    if State.AtkPlayerActiveTween then
        pcall(function() State.AtkPlayerActiveTween:Cancel() end)
        State.AtkPlayerActiveTween = nil
    end
end

local function stopAtkPlayer()
    if State.AtkPlayerWorker then
        task.cancel(State.AtkPlayerWorker)
        State.AtkPlayerWorker = nil
    end
    cancelAtkPlayerTween()
end

local function startAtkPlayer()
    stopAtkPlayer()
    if State.Closed or not Config.AtkPlayerEnabled then return end

    State.AtkPlayerWorker = task.spawn(function()
        while not State.Closed and Config.AtkPlayerEnabled do
            local targetPlayer = getAtkPlayerTarget()
            local root = getRootPart()
            local targetRoot = targetPlayer and getPlayerRoot(targetPlayer)

            if root and targetRoot then
                local z = Config.AtkPlayerDistance
                local attach = targetRoot.CFrame * CFrame.new(0, 0, z)
                local targetPos = targetRoot.Position
                local delta = attach.Position - root.Position
                local dist = delta.Magnitude
                local dt = RunService.Heartbeat:Wait()
                dt = math.clamp(dt, 1 / 240, 0.1)
                local step = math.max(Config.FlySpeed, 1) * dt

                cancelAtkPlayerTween()
                local newPos
                if dist <= step or dist <= 0.001 then
                    newPos = attach.Position
                else
                    newPos = root.Position + delta.Unit * step
                end

                root.CFrame = CFrame.lookAt(newPos, targetPos)
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            else
                task.wait(0.08)
            end
        end
        State.AtkPlayerWorker = nil
    end)
end

local function updateAtkPlayerNearbyButton()
    if UI.atkPlayerNearbyToggle then
        UI.atkPlayerNearbyToggle.Text = Config.AtkPlayerNearbyEnabled and "ON" or "OFF"
        UI.atkPlayerNearbyToggle.BackgroundColor3 = Config.AtkPlayerNearbyEnabled
            and Color3.fromRGB(45,170,95) or Color3.fromRGB(75,75,88)
    end
end

local function setAtkPlayerEnabled(enabled)
    Config.AtkPlayerEnabled = enabled == true
    if Config.AtkPlayerEnabled then
        setAutoAttackEnabled(true)
        startAtkPlayer()
    else
        stopAtkPlayer()
        if Config.AtkPlayerNearbyEnabled then
            Config.AtkPlayerNearbyEnabled = false
            State.NearbyAtkTargetUserId = nil
            table.clear(State.SelectedPlayers)
        end
        updateAtkPlayerNearbyButton()
        setAutoAttackEnabled(false)
    end
    if UI.atkPlayerToggle then
        UI.atkPlayerToggle.Text = Config.AtkPlayerEnabled and "ON" or "OFF"
        UI.atkPlayerToggle.BackgroundColor3 = Config.AtkPlayerEnabled and Color3.fromRGB(45,170,95) or Color3.fromRGB(75,75,88)
    end
end

local function setAtkPlayerNearbyEnabled(enabled)
    Config.AtkPlayerNearbyEnabled = enabled == true
    State.NearbyAtkTargetUserId = nil
    table.clear(State.SelectedPlayers)

    if Config.AtkPlayerNearbyEnabled then
        getNearbyAtkPlayer()
        setAtkPlayerEnabled(true)
    else
        setAtkPlayerEnabled(false)
    end

    updateAtkPlayerNearbyButton()
    if refreshAtkPlayerList then task.defer(refreshAtkPlayerList) end
end

local WolfActions = ReplicatedStorage:FindFirstChild("WolfActions")
local CombatConfig = require(
    ReplicatedStorage:WaitForChild("FeralWorld"):WaitForChild("CombatConfig")
)

local function isAttackTargetAlive(model)
    if not model or not model.Parent or not model:IsA("Model") then
        return false
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health > 0
end

local function getNearestAttackTarget()
    if Config.AtkPlayerEnabled then
        local selected = getAtkPlayerTarget()
        if selected and selected.Character and isPlayerAlive(selected) then
            return selected.Character
        end
        return nil
    end

    local folder = workspace:FindFirstChild("FeralNPCs")
    local root = getRootPart()
    if not folder or not root then
        return nil
    end

    local bestTarget = nil
    local bestDistance = math.huge

    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") and isAttackTargetAlive(model) then
            local targetPart = model:FindFirstChild("HumanoidRootPart")
                or model.PrimaryPart
                or model:FindFirstChildWhichIsA("BasePart", true)

            if targetPart then
                local distance = (targetPart.Position - root.Position).Magnitude
                if distance < bestDistance then
                    bestDistance = distance
                    bestTarget = model
                end
            end
        end
    end

    return bestTarget
end

local function biteAttack(target)
    local character = player.Character
    if not character or not target or not isAttackTargetAlive(target) then
        return false
    end

    if not WolfActions or not WolfActions.Parent then
        WolfActions = ReplicatedStorage:FindFirstChild("WolfActions")
    end
    if not WolfActions then
        return false
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return false
    end

    if character:GetAttribute("FeralTumbleAt")
        or character:GetAttribute("FeralVenomDown")
        or character:GetAttribute("WolfRest") then
        return false
    end

    local serverTime = Workspace:GetServerTimeNow()
    character:SetAttribute("WolfBiteAt", serverTime)
    WolfActions:FireServer("Bite", serverTime)

    task.delay(CombatConfig.HIT_DELAY or 0.27, function()
        if not character.Parent or not isAttackTargetAlive(target) then
            return
        end

        WolfActions:FireServer("BiteHit", {
            t = serverTime,
            m = target,
        })

        local feralBiteLocal = player:FindFirstChild("FeralBiteLocal")
        if feralBiteLocal then
            feralBiteLocal:Fire(target)
        end
    end)

    return true
end

local function stopAutoAttack()
    if State.AutoAttackWorker then
        task.cancel(State.AutoAttackWorker)
        State.AutoAttackWorker = nil
    end
end

local function startAutoAttack()
    stopAutoAttack()

    if State.Closed or not Config.AutoAttackEnabled then
        return
    end

    State.AutoAttackWorker = task.spawn(function()
        while not State.Closed and Config.AutoAttackEnabled do
            local target = getNearestAttackTarget()
            if target then
                biteAttack(target)
            end
            task.wait(math.max(Config.AutoAttackInterval, 0.01))
        end
        State.AutoAttackWorker = nil
    end)
end

setAutoAttackEnabled = function(enabled)
    Config.AutoAttackEnabled = enabled == true

    if Config.AutoAttackEnabled then
        startAutoAttack()
    else
        stopAutoAttack()
    end

    if UI.autoAttackToggle then
        UI.autoAttackToggle.Text = Config.AutoAttackEnabled and "ON" or "OFF"
        UI.autoAttackToggle.BackgroundColor3 = Config.AutoAttackEnabled
            and Color3.fromRGB(45, 170, 95)
            or Color3.fromRGB(75, 75, 88)
    end
end

local function updateAutoAttackSliderVisual()
    if not UI.autoAttackSpeedFill or not UI.autoAttackSpeedKnob or not UI.autoAttackSpeedLabel then
        return
    end

    local minValue = Config.AutoAttackMinInterval
    local maxValue = Config.AutoAttackMaxInterval
    local percent = 1 - ((Config.AutoAttackInterval - minValue) / (maxValue - minValue))
    percent = math.clamp(percent, 0, 1)

    UI.autoAttackSpeedFill.Size = UDim2.fromScale(percent, 1)
    UI.autoAttackSpeedKnob.Position = UDim2.new(percent, 0, 0.5, 0)
    UI.autoAttackSpeedLabel.Text = string.format(
        "Attack Speed: %.2fs  (%.1f atk/s)",
        Config.AutoAttackInterval,
        1 / math.max(Config.AutoAttackInterval, 0.01)
    )
end

local function setAutoAttackIntervalFromX(x)
    if not UI.autoAttackSpeedSlider then
        return
    end

    local absPos = UI.autoAttackSpeedSlider.AbsolutePosition.X
    local absSize = UI.autoAttackSpeedSlider.AbsoluteSize.X
    if absSize <= 0 then
        return
    end

    local percent = math.clamp((x - absPos) / absSize, 0, 1)
    local minValue = Config.AutoAttackMinInterval
    local maxValue = Config.AutoAttackMaxInterval

    Config.AutoAttackInterval = maxValue - (maxValue - minValue) * percent
    Config.AutoAttackInterval = math.floor(Config.AutoAttackInterval * 100 + 0.5) / 100
    updateAutoAttackSliderVisual()
end

local function getNPCPrimaryPart(model)
    if not model or not model.Parent or not model:IsA("Model") then
        return nil
    end

    return model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart", true)
end

local function isFarmTargetAlive(model)
    if not model or not model.Parent or not State.SelectedFarmGroups[model.Name] then
        return false
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health <= 0 then
        return false
    end

    return getNPCPrimaryPart(model) ~= nil
end

local function getNearestSelectedFarmTarget()
    local folder = getFeralNPCFolder()
    local root = getRootPart()
    if not folder or not root then
        return nil
    end

    local bestModel = nil
    local bestDistance = math.huge

    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") and isFarmTargetAlive(model) then
            local targetPart = getNPCPrimaryPart(model)
            if targetPart then
                local distance = (targetPart.Position - root.Position).Magnitude
                if distance < bestDistance then
                    bestDistance = distance
                    bestModel = model
                end
            end
        end
    end

    return bestModel
end

local function hasSelectedFarmGroup()
    for _, enabled in pairs(State.SelectedFarmGroups) do
        if enabled then
            return true
        end
    end
    return false
end

local function cancelAutoFarmTween()
    if State.AutoFarmActiveTween then
        pcall(function()
            State.AutoFarmActiveTween:Cancel()
        end)
        State.AutoFarmActiveTween = nil
    end
end

local function stopAutoFarm()
    if State.AutoFarmWorker then
        task.cancel(State.AutoFarmWorker)
        State.AutoFarmWorker = nil
    end
    cancelAutoFarmTween()
end

local function attackFarmTarget(target)
    return biteAttack(target)
end

local function startAutoFarm()
    stopAutoFarm()

    if State.Closed or not Config.AutoFarmEnabled or not hasSelectedFarmGroup() then
        return
    end

    State.AutoFarmWorker = task.spawn(function()
        local target = nil
        while not State.Closed and Config.AutoFarmEnabled and hasSelectedFarmGroup() do
            local root = getRootPart()
            if not target or not isFarmTargetAlive(target) then
                target = getNearestSelectedFarmTarget()
            end

            if root and target then
                local targetPart = getNPCPrimaryPart(target)
                if targetPart and targetPart.Parent then
                    local behindCFrame = targetPart.CFrame * CFrame.new(0, 0, Config.AutoFarmBehindDistance)
                    local destination = CFrame.lookAt(behindCFrame.Position, targetPart.Position)

                    local dt = RunService.Heartbeat:Wait()
                    dt = math.clamp(dt, 1 / 240, 0.1)

                    if not targetPart.Parent then
                        continue
                    end

                    behindCFrame = targetPart.CFrame * CFrame.new(0, 0, Config.AutoFarmBehindDistance)
                    local delta = behindCFrame.Position - root.Position
                    local distance = delta.Magnitude
                    local step = math.max(Config.FlySpeed, 1) * dt

                    cancelAutoFarmTween()
                    local newPos
                    if distance <= step or distance <= 0.001 then
                        newPos = behindCFrame.Position
                    else
                        newPos = root.Position + delta.Unit * step
                    end

                    root.CFrame = CFrame.lookAt(newPos, targetPart.Position)
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                else
                    task.wait(0.03)
                end
            else
                task.wait(0.1)
            end
        end

        State.AutoFarmWorker = nil
    end)
end

local function syncAutoFarmSelectionToESP()
    for name in pairs(State.SelectedFarmGroups) do
        State.SelectedNPCGroups[name] = State.SelectedFarmGroups[name] == true
    end

    refreshNPCESP()

end

local function refreshAutoFarmState()
    if Config.AutoFarmEnabled and hasSelectedFarmGroup() then
        startAutoFarm()
    else
        stopAutoFarm()
    end
end

local function setAutoFarmEnabled(enabled)
    Config.AutoFarmEnabled = enabled == true

    if Config.AutoFarmEnabled then
        setAutoAttackEnabled(true)

        syncAutoFarmSelectionToESP()

        refreshAutoFarmState()
    else
        stopAutoFarm()
        setAutoAttackEnabled(false)
    end

    if UI.autoFarmToggle then
        UI.autoFarmToggle.Text = Config.AutoFarmEnabled and "ON" or "OFF"
        UI.autoFarmToggle.BackgroundColor3 = Config.AutoFarmEnabled
            and Color3.fromRGB(45, 170, 95)
            or Color3.fromRGB(75, 75, 88)
    end
end

local function updateAutoFarmSliderVisual()
    if not UI.autoFarmSpeedFill or not UI.autoFarmSpeedKnob or not UI.autoFarmSpeedLabel then return end

    local percent = (Config.FlySpeed - Config.MinFlySpeed)
        / (Config.MaxFlySpeed - Config.MinFlySpeed)
    percent = math.clamp(percent, 0, 1)

    UI.autoFarmSpeedFill.Size = UDim2.fromScale(percent, 1)
    UI.autoFarmSpeedKnob.Position = UDim2.new(percent, 0, 0.5, 0)
    UI.autoFarmSpeedLabel.Text = "Fly Speed (Shared): " .. tostring(Config.FlySpeed)
end

local function setAutoFarmFlySpeedFromX(x)
    local slider = UI.autoFarmSpeedSlider
    if not slider then return end

    local width = slider.AbsoluteSize.X
    if width <= 0 then return end

    local percent = math.clamp((x - slider.AbsolutePosition.X) / width, 0, 1)
    local value = Config.MinFlySpeed + (Config.MaxFlySpeed - Config.MinFlySpeed) * percent
    Config.FlySpeed = math.floor(value + 0.5)
    Config.AutoFarmFlySpeed = Config.FlySpeed
    updateAutoFarmSliderVisual()
    if UI.playerFlySpeedLabel then UI.playerFlySpeedLabel.Text = "Fly Speed (Shared): " .. tostring(Config.FlySpeed) end
end

UI.screenGui = Instance.new("ScreenGui")
UI.screenGui.Name = "AnimalWorldUI"
UI.screenGui.ResetOnSpawn = false
UI.screenGui.IgnoreGuiInset = true
UI.screenGui.DisplayOrder = 999999
UI.screenGui.Parent = guiParent

UI.main = Instance.new("Frame")
UI.main.Size = UDim2.fromOffset(500, 390)
UI.main.Position = UDim2.new(0.5, -250, 0.5, -195)
UI.main.BackgroundColor3 = Color3.fromRGB(27, 27, 32)
UI.main.BorderSizePixel = 0
UI.main.Active = true
UI.main.Parent = UI.screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 13)
mainCorner.Parent = UI.main

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(115, 82, 42)
mainStroke.Thickness = 1.5
mainStroke.Parent = UI.main

UI.titleBar = Instance.new("Frame")
UI.titleBar.Size = UDim2.new(1, 0, 0, 54)
UI.titleBar.BackgroundColor3 = Color3.fromRGB(38, 34, 31)
UI.titleBar.BorderSizePixel = 0
UI.titleBar.Active = true
UI.titleBar.Parent = UI.main

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 13)
titleCorner.Parent = UI.titleBar

local titleFix = Instance.new("Frame")
titleFix.Size = UDim2.new(1, 0, 0, 14)
titleFix.Position = UDim2.new(0, 0, 1, -14)
titleFix.BackgroundColor3 = UI.titleBar.BackgroundColor3
titleFix.BorderSizePixel = 0
titleFix.Parent = UI.titleBar

UI.tigerLogo = Instance.new("TextLabel")
UI.tigerLogo.Size = UDim2.fromOffset(42, 42)
UI.tigerLogo.Position = UDim2.fromOffset(8, 6)
UI.tigerLogo.BackgroundColor3 = Color3.fromRGB(235, 143, 42)
UI.tigerLogo.BorderSizePixel = 0
UI.tigerLogo.Text = "🐯"
UI.tigerLogo.TextSize = 26
UI.tigerLogo.Font = Enum.Font.GothamBold
UI.tigerLogo.Parent = UI.titleBar

local tigerCorner = Instance.new("UICorner")
tigerCorner.CornerRadius = UDim.new(1, 0)
tigerCorner.Parent = UI.tigerLogo

UI.title = Instance.new("TextLabel")
UI.title.Size = UDim2.new(1, -150, 1, 0)
UI.title.Position = UDim2.fromOffset(60, 0)
UI.title.BackgroundTransparency = 1
UI.title.Text = "Animal world"
UI.title.TextColor3 = Color3.fromRGB(255, 242, 220)
UI.title.TextSize = 19
UI.title.Font = Enum.Font.GothamBold
UI.title.TextXAlignment = Enum.TextXAlignment.Left
UI.title.Parent = UI.titleBar

UI.minimize = Instance.new("TextButton")
UI.minimize.Size = UDim2.fromOffset(36, 30)
UI.minimize.Position = UDim2.new(1, -82, 0, 12)
UI.minimize.BackgroundColor3 = Color3.fromRGB(70, 64, 58)
UI.minimize.BorderSizePixel = 0
UI.minimize.Text = "—"
UI.minimize.TextColor3 = Color3.new(1, 1, 1)
UI.minimize.TextSize = 20
UI.minimize.Font = Enum.Font.GothamBold
UI.minimize.Parent = UI.titleBar

local minCorner = Instance.new("UICorner")
minCorner.CornerRadius = UDim.new(0, 7)
minCorner.Parent = UI.minimize

UI.close = Instance.new("TextButton")
UI.close.Size = UDim2.fromOffset(36, 30)
UI.close.Position = UDim2.new(1, -42, 0, 12)
UI.close.BackgroundColor3 = Color3.fromRGB(190, 60, 60)
UI.close.BorderSizePixel = 0
UI.close.Text = "X"
UI.close.TextColor3 = Color3.new(1, 1, 1)
UI.close.TextSize = 14
UI.close.Font = Enum.Font.GothamBold
UI.close.Parent = UI.titleBar

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 7)
closeCorner.Parent = UI.close

UI.sidebar = Instance.new("Frame")
UI.sidebar.Size = UDim2.fromOffset(125, 286)
UI.sidebar.Position = UDim2.fromOffset(0, 54)
UI.sidebar.BackgroundColor3 = Color3.fromRGB(32, 32, 38)
UI.sidebar.BorderSizePixel = 0
UI.sidebar.Parent = UI.main

UI.autoAttackTab = Instance.new("TextButton")
UI.autoAttackTab.Size = UDim2.new(1, -16, 0, 42)
UI.autoAttackTab.Position = UDim2.fromOffset(8, 12)
UI.autoAttackTab.BackgroundColor3 = Color3.fromRGB(65, 65, 78)
UI.autoAttackTab.BorderSizePixel = 0
UI.autoAttackTab.Text = "Auto Atk"
UI.autoAttackTab.TextColor3 = Color3.new(1, 1, 1)
UI.autoAttackTab.TextSize = 14
UI.autoAttackTab.Font = Enum.Font.GothamBold
UI.autoAttackTab.Parent = UI.sidebar

UI.autoAttackTabCorner = Instance.new("UICorner")
UI.autoAttackTabCorner.CornerRadius = UDim.new(0, 8)
UI.autoAttackTabCorner.Parent = UI.autoAttackTab

UI.espTab = Instance.new("TextButton")
UI.espTab.Size = UDim2.new(1, -16, 0, 42)
UI.espTab.Position = UDim2.fromOffset(8, 62)
UI.espTab.BackgroundColor3 = Color3.fromRGB(65, 65, 78)
UI.espTab.BorderSizePixel = 0
UI.espTab.Text = "NPC"
UI.espTab.TextColor3 = Color3.new(1, 1, 1)
UI.espTab.TextSize = 14
UI.espTab.Font = Enum.Font.GothamBold
UI.espTab.Parent = UI.sidebar

UI.espTabCorner = Instance.new("UICorner")
UI.espTabCorner.CornerRadius = UDim.new(0, 8)
UI.espTabCorner.Parent = UI.espTab

UI.autoFarmTab = Instance.new("TextButton")
UI.autoFarmTab.Size = UDim2.new(1, -16, 0, 42)
UI.autoFarmTab.Position = UDim2.fromOffset(8, 112)
UI.autoFarmTab.BackgroundColor3 = Color3.fromRGB(65, 65, 78)
UI.autoFarmTab.BorderSizePixel = 0
UI.autoFarmTab.Text = "Auto Farm"
UI.autoFarmTab.TextColor3 = Color3.new(1, 1, 1)
UI.autoFarmTab.TextSize = 14
UI.autoFarmTab.Font = Enum.Font.GothamBold
UI.autoFarmTab.Parent = UI.sidebar
UI.autoFarmTab.Visible = false

UI.autoFarmTabCorner = Instance.new("UICorner")
UI.autoFarmTabCorner.CornerRadius = UDim.new(0, 8)
UI.autoFarmTabCorner.Parent = UI.autoFarmTab

UI.playerTab = Instance.new("TextButton")
UI.playerTab.Size = UDim2.new(1, -16, 0, 42)
UI.playerTab.Position = UDim2.fromOffset(8, 112)
UI.playerTab.BackgroundColor3 = Color3.fromRGB(65, 65, 78)
UI.playerTab.BorderSizePixel = 0
UI.playerTab.Text = "Player"
UI.playerTab.TextColor3 = Color3.new(1,1,1)
UI.playerTab.TextSize = 14
UI.playerTab.Font = Enum.Font.GothamBold
UI.playerTab.Parent = UI.sidebar
local playerTabCorner = Instance.new("UICorner")
playerTabCorner.CornerRadius = UDim.new(0,8)
playerTabCorner.Parent = UI.playerTab

UI.atkPlayerTab = Instance.new("TextButton")
UI.atkPlayerTab.Size = UDim2.new(1, -16, 0, 42)
UI.atkPlayerTab.Position = UDim2.fromOffset(8, 162)
UI.atkPlayerTab.BackgroundColor3 = Color3.fromRGB(65, 65, 78)
UI.atkPlayerTab.BorderSizePixel = 0
UI.atkPlayerTab.Text = "Atk Player"
UI.atkPlayerTab.TextColor3 = Color3.new(1,1,1)
UI.atkPlayerTab.TextSize = 14
UI.atkPlayerTab.Font = Enum.Font.GothamBold
UI.atkPlayerTab.Parent = UI.sidebar
local atkPlayerTabCorner = Instance.new("UICorner")
atkPlayerTabCorner.CornerRadius = UDim.new(0,8)
atkPlayerTabCorner.Parent = UI.atkPlayerTab

UI.effectTab = Instance.new("TextButton")
UI.effectTab.Size = UDim2.new(1, -16, 0, 42)
UI.effectTab.Position = UDim2.fromOffset(8, 212)
UI.effectTab.BackgroundColor3 = Color3.fromRGB(65, 65, 78)
UI.effectTab.BorderSizePixel = 0
UI.effectTab.Text = "Effect"
UI.effectTab.TextColor3 = Color3.new(1,1,1)
UI.effectTab.TextSize = 14
UI.effectTab.Font = Enum.Font.GothamBold
UI.effectTab.Parent = UI.sidebar
local effectTabCorner = Instance.new("UICorner")
effectTabCorner.CornerRadius = UDim.new(0,8)
effectTabCorner.Parent = UI.effectTab

UI.effectContent = Instance.new("Frame")
UI.effectContent.Size = UDim2.new(1, -125, 1, -54)
UI.effectContent.Position = UDim2.fromOffset(125, 54)
UI.effectContent.BackgroundTransparency = 1
UI.effectContent.Visible = false
UI.effectContent.Parent = UI.main

UI.effectToggleLabel = Instance.new("TextLabel")
UI.effectToggleLabel.Size = UDim2.new(1, -150, 0, 42)
UI.effectToggleLabel.Position = UDim2.fromOffset(16, 20)
UI.effectToggleLabel.BackgroundTransparency = 1
UI.effectToggleLabel.Text = "Remove Lighting Effects"
UI.effectToggleLabel.TextColor3 = Color3.new(1,1,1)
UI.effectToggleLabel.TextSize = 14
UI.effectToggleLabel.Font = Enum.Font.GothamBold
UI.effectToggleLabel.TextXAlignment = Enum.TextXAlignment.Left
UI.effectToggleLabel.Parent = UI.effectContent

UI.effectToggle = Instance.new("TextButton")
UI.effectToggle.Size = UDim2.fromOffset(100, 38)
UI.effectToggle.Position = UDim2.new(1, -116, 0, 22)
UI.effectToggle.BackgroundColor3 = Color3.fromRGB(75,75,88)
UI.effectToggle.BorderSizePixel = 0
UI.effectToggle.Text = "OFF"
UI.effectToggle.TextColor3 = Color3.new(1,1,1)
UI.effectToggle.TextSize = 14
UI.effectToggle.Font = Enum.Font.GothamBold
UI.effectToggle.Parent = UI.effectContent
local effectToggleCorner = Instance.new("UICorner")
effectToggleCorner.CornerRadius = UDim.new(0,8)
effectToggleCorner.Parent = UI.effectToggle

UI.brightnessToggleLabel = Instance.new("TextLabel")
UI.brightnessToggleLabel.Size = UDim2.new(1, -150, 0, 42)
UI.brightnessToggleLabel.Position = UDim2.fromOffset(16, 76)
UI.brightnessToggleLabel.BackgroundTransparency = 1
UI.brightnessToggleLabel.Text = "Bright Lighting"
UI.brightnessToggleLabel.TextColor3 = Color3.new(1,1,1)
UI.brightnessToggleLabel.TextSize = 14
UI.brightnessToggleLabel.Font = Enum.Font.GothamBold
UI.brightnessToggleLabel.TextXAlignment = Enum.TextXAlignment.Left
UI.brightnessToggleLabel.Parent = UI.effectContent

UI.brightnessToggle = Instance.new("TextButton")
UI.brightnessToggle.Size = UDim2.fromOffset(100, 38)
UI.brightnessToggle.Position = UDim2.new(1, -116, 0, 78)
UI.brightnessToggle.BackgroundColor3 = Color3.fromRGB(75,75,88)
UI.brightnessToggle.BorderSizePixel = 0
UI.brightnessToggle.Text = "OFF"
UI.brightnessToggle.TextColor3 = Color3.new(1,1,1)
UI.brightnessToggle.TextSize = 14
UI.brightnessToggle.Font = Enum.Font.GothamBold
UI.brightnessToggle.Parent = UI.effectContent
local brightnessToggleCorner = Instance.new("UICorner")
brightnessToggleCorner.CornerRadius = UDim.new(0,8)
brightnessToggleCorner.Parent = UI.brightnessToggle

UI.autoAttackContent = Instance.new("Frame")
UI.autoAttackContent.Size = UDim2.new(1, -125, 1, -54)
UI.autoAttackContent.Position = UDim2.fromOffset(125, 54)
UI.autoAttackContent.BackgroundTransparency = 1
UI.autoAttackContent.Visible = false
UI.autoAttackContent.Parent = UI.main

UI.autoAttackInfo = Instance.new("TextLabel")
UI.autoAttackInfo.Size = UDim2.new(1, -32, 0, 44)
UI.autoAttackInfo.Position = UDim2.fromOffset(16, 18)
UI.autoAttackInfo.BackgroundTransparency = 1
UI.autoAttackInfo.Text = "โจมตี NPC ที่อยู่ใกล้ที่สุดอัตโนมัติด้วย Bite / BiteHit"
UI.autoAttackInfo.TextColor3 = Color3.fromRGB(175, 175, 185)
UI.autoAttackInfo.TextSize = 12
UI.autoAttackInfo.Font = Enum.Font.Gotham
UI.autoAttackInfo.TextWrapped = true
UI.autoAttackInfo.TextXAlignment = Enum.TextXAlignment.Left
UI.autoAttackInfo.Parent = UI.autoAttackContent

UI.autoAttackToggleLabel = Instance.new("TextLabel")
UI.autoAttackToggleLabel.Size = UDim2.new(1, -150, 0, 42)
UI.autoAttackToggleLabel.Position = UDim2.fromOffset(16, 72)
UI.autoAttackToggleLabel.BackgroundTransparency = 1
UI.autoAttackToggleLabel.Text = "Auto Attack"
UI.autoAttackToggleLabel.TextColor3 = Color3.new(1, 1, 1)
UI.autoAttackToggleLabel.TextSize = 14
UI.autoAttackToggleLabel.Font = Enum.Font.GothamBold
UI.autoAttackToggleLabel.TextXAlignment = Enum.TextXAlignment.Left
UI.autoAttackToggleLabel.Parent = UI.autoAttackContent

UI.autoAttackToggle = Instance.new("TextButton")
UI.autoAttackToggle.Size = UDim2.fromOffset(100, 38)
UI.autoAttackToggle.Position = UDim2.new(1, -116, 0, 74)
UI.autoAttackToggle.BackgroundColor3 = Color3.fromRGB(75, 75, 88)
UI.autoAttackToggle.BorderSizePixel = 0
UI.autoAttackToggle.Text = "OFF"
UI.autoAttackToggle.TextColor3 = Color3.new(1, 1, 1)
UI.autoAttackToggle.TextSize = 14
UI.autoAttackToggle.Font = Enum.Font.GothamBold
UI.autoAttackToggle.Parent = UI.autoAttackContent

UI.autoAttackToggleCorner = Instance.new("UICorner")
UI.autoAttackToggleCorner.CornerRadius = UDim.new(0, 8)
UI.autoAttackToggleCorner.Parent = UI.autoAttackToggle

UI.autoAttackSpeedLabel = Instance.new("TextLabel")
UI.autoAttackSpeedLabel.Size = UDim2.new(1, -32, 0, 28)
UI.autoAttackSpeedLabel.Position = UDim2.fromOffset(16, 134)
UI.autoAttackSpeedLabel.BackgroundTransparency = 1
UI.autoAttackSpeedLabel.TextColor3 = Color3.fromRGB(235, 220, 195)
UI.autoAttackSpeedLabel.TextSize = 13
UI.autoAttackSpeedLabel.Font = Enum.Font.GothamMedium
UI.autoAttackSpeedLabel.TextXAlignment = Enum.TextXAlignment.Left
UI.autoAttackSpeedLabel.Parent = UI.autoAttackContent

UI.autoAttackSpeedSlider = Instance.new("Frame")
UI.autoAttackSpeedSlider.Size = UDim2.new(1, -40, 0, 8)
UI.autoAttackSpeedSlider.Position = UDim2.fromOffset(20, 174)
UI.autoAttackSpeedSlider.BackgroundColor3 = Color3.fromRGB(62, 62, 74)
UI.autoAttackSpeedSlider.BorderSizePixel = 0
UI.autoAttackSpeedSlider.Active = true
UI.autoAttackSpeedSlider.Parent = UI.autoAttackContent

UI.autoAttackSliderCorner = Instance.new("UICorner")
UI.autoAttackSliderCorner.CornerRadius = UDim.new(1, 0)
UI.autoAttackSliderCorner.Parent = UI.autoAttackSpeedSlider

UI.autoAttackSpeedFill = Instance.new("Frame")
UI.autoAttackSpeedFill.Size = UDim2.fromScale(0, 1)
UI.autoAttackSpeedFill.BackgroundColor3 = Color3.fromRGB(220, 135, 40)
UI.autoAttackSpeedFill.BorderSizePixel = 0
UI.autoAttackSpeedFill.Parent = UI.autoAttackSpeedSlider

UI.autoAttackFillCorner = Instance.new("UICorner")
UI.autoAttackFillCorner.CornerRadius = UDim.new(1, 0)
UI.autoAttackFillCorner.Parent = UI.autoAttackSpeedFill

UI.autoAttackSpeedKnob = Instance.new("TextButton")
UI.autoAttackSpeedKnob.Size = UDim2.fromOffset(18, 18)
UI.autoAttackSpeedKnob.AnchorPoint = Vector2.new(0.5, 0.5)
UI.autoAttackSpeedKnob.Position = UDim2.new(0, 0, 0.5, 0)
UI.autoAttackSpeedKnob.BackgroundColor3 = Color3.fromRGB(255, 220, 165)
UI.autoAttackSpeedKnob.BorderSizePixel = 0
UI.autoAttackSpeedKnob.Text = ""
UI.autoAttackSpeedKnob.Parent = UI.autoAttackSpeedSlider

UI.autoAttackKnobCorner = Instance.new("UICorner")
UI.autoAttackKnobCorner.CornerRadius = UDim.new(1, 0)
UI.autoAttackKnobCorner.Parent = UI.autoAttackSpeedKnob

UI.autoAttackHint = Instance.new("TextLabel")
UI.autoAttackHint.Size = UDim2.new(1, -32, 0, 44)
UI.autoAttackHint.Position = UDim2.fromOffset(16, 194)
UI.autoAttackHint.BackgroundTransparency = 1
UI.autoAttackHint.Text = "เลื่อนไปขวา = โจมตีเร็วขึ้น | ค่าเริ่มต้น 0.30s"
UI.autoAttackHint.TextColor3 = Color3.fromRGB(150, 150, 160)
UI.autoAttackHint.TextSize = 11
UI.autoAttackHint.Font = Enum.Font.Gotham
UI.autoAttackHint.TextWrapped = true
UI.autoAttackHint.TextXAlignment = Enum.TextXAlignment.Left
UI.autoAttackHint.Parent = UI.autoAttackContent

UI.espContent = Instance.new("ScrollingFrame")
UI.espContent.Size = UDim2.new(1, -125, 1, -54)
UI.espContent.Position = UDim2.fromOffset(125, 54)
UI.espContent.BackgroundTransparency = 1
UI.espContent.BorderSizePixel = 0
UI.espContent.ScrollBarThickness = 5
UI.espContent.AutomaticCanvasSize = Enum.AutomaticSize.Y
UI.espContent.CanvasSize = UDim2.fromOffset(0, 0)
UI.espContent.Visible = false
UI.espContent.Parent = UI.main

UI.espPadding = Instance.new("UIPadding")
UI.espPadding.PaddingTop = UDim.new(0, 16)
UI.espPadding.PaddingLeft = UDim.new(0, 16)
UI.espPadding.PaddingRight = UDim.new(0, 16)
UI.espPadding.PaddingBottom = UDim.new(0, 16)
UI.espPadding.Parent = UI.espContent

UI.espLayout = Instance.new("UIListLayout")
UI.espLayout.Padding = UDim.new(0, 10)
UI.espLayout.SortOrder = Enum.SortOrder.LayoutOrder
UI.espLayout.Parent = UI.espContent

UI.espGroupLabel = Instance.new("TextLabel")
UI.espGroupLabel.Size = UDim2.new(1, -8, 0, 26)
UI.espGroupLabel.BackgroundTransparency = 1
UI.espGroupLabel.Text = "NPC Groups"
UI.espGroupLabel.TextColor3 = Color3.fromRGB(225,225,230)
UI.espGroupLabel.TextSize = 14
UI.espGroupLabel.Font = Enum.Font.GothamBold
UI.espGroupLabel.TextXAlignment = Enum.TextXAlignment.Left
UI.espGroupLabel.LayoutOrder = 5
UI.espGroupLabel.Parent = UI.espContent
UI.espGroupLabel.Visible = false

UI.espGroupList = Instance.new("Frame")
UI.espGroupList.Size = UDim2.new(1, -8, 0, 0)
UI.espGroupList.AutomaticSize = Enum.AutomaticSize.Y
UI.espGroupList.BackgroundTransparency = 1
UI.espGroupList.LayoutOrder = 6
UI.espGroupList.Parent = UI.espContent
UI.espGroupList.Visible = false

UI.espGroupListLayout = Instance.new("UIListLayout")
UI.espGroupListLayout.Padding = UDim.new(0, 7)
UI.espGroupListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UI.espGroupListLayout.Parent = UI.espGroupList

local function refreshNPCGroupList()
    for _, child in ipairs(UI.espGroupList:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end

    local groups = getNPCGroups()
    local names = {}
    for name in pairs(groups) do
        table.insert(names, name)
    end
    table.sort(names, function(a,b) return string.lower(a) < string.lower(b) end)

    if #names == 0 then
        UI.espGroupLabel.Text = "NPC Groups (0)"
        return
    end
    UI.espGroupLabel.Text = "NPC Groups (" .. tostring(#names) .. ")"

    for index, name in ipairs(names) do
        local count = #groups[name]
        local button = Instance.new("TextButton")
        button.Name = "NPCGroup_" .. name
        button.Size = UDim2.new(1, 0, 0, 38)
        button.BackgroundColor3 = State.SelectedNPCGroups[name]
            and Color3.fromRGB(45,170,95)
            or Color3.fromRGB(62,62,74)
        button.BorderSizePixel = 0
        button.Text = (State.SelectedNPCGroups[name] and "☑ " or "☐ ")
            .. name .. "  (x" .. tostring(count) .. ")"
        button.TextColor3 = Color3.new(1,1,1)
        button.TextSize = 13
        button.Font = Enum.Font.GothamMedium
        button.TextXAlignment = Enum.TextXAlignment.Left
        button.LayoutOrder = index
        button.Parent = UI.espGroupList

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 12)
        pad.Parent = button
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = button

        addConnection(button.Activated:Connect(function()
            local selected = not State.SelectedNPCGroups[name]
            State.SelectedNPCGroups[name] = selected
            State.SelectedFarmGroups[name] = selected
            refreshNPCESP()
            refreshNPCGroupList()
        end))
    end
end

UI.autoFarmContent = Instance.new("ScrollingFrame")
UI.autoFarmContent.Size = UDim2.new(1, -125, 1, -54)
UI.autoFarmContent.Position = UDim2.fromOffset(125, 54)
UI.autoFarmContent.BackgroundTransparency = 1
UI.autoFarmContent.BorderSizePixel = 0
UI.autoFarmContent.ScrollBarThickness = 5
UI.autoFarmContent.AutomaticCanvasSize = Enum.AutomaticSize.Y
UI.autoFarmContent.CanvasSize = UDim2.fromOffset(0, 0)
UI.autoFarmContent.Visible = false
UI.autoFarmContent.Parent = UI.main

UI.autoFarmPadding = Instance.new("UIPadding")
UI.autoFarmPadding.PaddingTop = UDim.new(0, 16)
UI.autoFarmPadding.PaddingLeft = UDim.new(0, 16)
UI.autoFarmPadding.PaddingRight = UDim.new(0, 16)
UI.autoFarmPadding.PaddingBottom = UDim.new(0, 16)
UI.autoFarmPadding.Parent = UI.autoFarmContent

UI.autoFarmLayout = Instance.new("UIListLayout")
UI.autoFarmLayout.Padding = UDim.new(0, 10)
UI.autoFarmLayout.SortOrder = Enum.SortOrder.LayoutOrder
UI.autoFarmLayout.Parent = UI.autoFarmContent

UI.autoFarmToggleFrame = Instance.new("Frame")
UI.autoFarmToggleFrame.Size = UDim2.new(1, -8, 0, 42)
UI.autoFarmToggleFrame.BackgroundTransparency = 1
UI.autoFarmToggleFrame.LayoutOrder = 7
UI.autoFarmToggleFrame.Parent = UI.espContent

UI.autoFarmToggleLabel = Instance.new("TextLabel")
UI.autoFarmToggleLabel.Size = UDim2.new(1, -120, 1, 0)
UI.autoFarmToggleLabel.BackgroundTransparency = 1
UI.autoFarmToggleLabel.Text = "Auto Farm"
UI.autoFarmToggleLabel.TextColor3 = Color3.new(1, 1, 1)
UI.autoFarmToggleLabel.TextSize = 14
UI.autoFarmToggleLabel.Font = Enum.Font.GothamBold
UI.autoFarmToggleLabel.TextXAlignment = Enum.TextXAlignment.Left
UI.autoFarmToggleLabel.Parent = UI.autoFarmToggleFrame

UI.autoFarmToggle = Instance.new("TextButton")
UI.autoFarmToggle.Size = UDim2.fromOffset(100, 38)
UI.autoFarmToggle.Position = UDim2.new(1, -100, 0.5, -19)
UI.autoFarmToggle.BackgroundColor3 = Color3.fromRGB(75, 75, 88)
UI.autoFarmToggle.BorderSizePixel = 0
UI.autoFarmToggle.Text = "OFF"
UI.autoFarmToggle.TextColor3 = Color3.new(1, 1, 1)
UI.autoFarmToggle.TextSize = 14
UI.autoFarmToggle.Font = Enum.Font.GothamBold
UI.autoFarmToggle.Parent = UI.autoFarmToggleFrame

UI.autoFarmToggleCorner = Instance.new("UICorner")
UI.autoFarmToggleCorner.CornerRadius = UDim.new(0, 8)
UI.autoFarmToggleCorner.Parent = UI.autoFarmToggle

UI.autoFarmSpeedGroup = Instance.new("Frame")
UI.autoFarmSpeedGroup.Size = UDim2.new(1, -8, 0, 62)
UI.autoFarmSpeedGroup.BackgroundTransparency = 1
UI.autoFarmSpeedGroup.LayoutOrder = 8
UI.autoFarmSpeedGroup.Parent = UI.espContent

UI.autoFarmSpeedLabel = Instance.new("TextLabel")
UI.autoFarmSpeedLabel.Size = UDim2.new(1, 0, 0, 26)
UI.autoFarmSpeedLabel.BackgroundTransparency = 1
UI.autoFarmSpeedLabel.Text = "Farm Fly Speed: 40"
UI.autoFarmSpeedLabel.TextColor3 = Color3.fromRGB(225,225,230)
UI.autoFarmSpeedLabel.TextSize = 14
UI.autoFarmSpeedLabel.Font = Enum.Font.GothamMedium
UI.autoFarmSpeedLabel.TextXAlignment = Enum.TextXAlignment.Left
UI.autoFarmSpeedLabel.Parent = UI.autoFarmSpeedGroup

UI.autoFarmSpeedSlider = Instance.new("Frame")
UI.autoFarmSpeedSlider.Size = UDim2.new(1, 0, 0, 12)
UI.autoFarmSpeedSlider.Position = UDim2.fromOffset(0, 40)
UI.autoFarmSpeedSlider.BackgroundColor3 = Color3.fromRGB(62,62,72)
UI.autoFarmSpeedSlider.BorderSizePixel = 0
UI.autoFarmSpeedSlider.Active = true
UI.autoFarmSpeedSlider.Parent = UI.autoFarmSpeedGroup

UI.autoFarmSpeedSliderCorner = Instance.new("UICorner")
UI.autoFarmSpeedSliderCorner.CornerRadius = UDim.new(1,0)
UI.autoFarmSpeedSliderCorner.Parent = UI.autoFarmSpeedSlider

UI.autoFarmSpeedFill = Instance.new("Frame")
UI.autoFarmSpeedFill.Size = UDim2.fromScale(0,1)
UI.autoFarmSpeedFill.BackgroundColor3 = Color3.fromRGB(220,135,40)
UI.autoFarmSpeedFill.BorderSizePixel = 0
UI.autoFarmSpeedFill.Parent = UI.autoFarmSpeedSlider

UI.autoFarmSpeedFillCorner = Instance.new("UICorner")
UI.autoFarmSpeedFillCorner.CornerRadius = UDim.new(1,0)
UI.autoFarmSpeedFillCorner.Parent = UI.autoFarmSpeedFill

UI.autoFarmSpeedKnob = Instance.new("TextButton")
UI.autoFarmSpeedKnob.Size = UDim2.fromOffset(22,22)
UI.autoFarmSpeedKnob.AnchorPoint = Vector2.new(0.5,0.5)
UI.autoFarmSpeedKnob.Position = UDim2.new(0,0,0.5,0)
UI.autoFarmSpeedKnob.BackgroundColor3 = Color3.fromRGB(255,242,220)
UI.autoFarmSpeedKnob.BorderSizePixel = 0
UI.autoFarmSpeedKnob.Text = ""
UI.autoFarmSpeedKnob.AutoButtonColor = false
UI.autoFarmSpeedKnob.Parent = UI.autoFarmSpeedSlider

UI.autoFarmSpeedKnobCorner = Instance.new("UICorner")
UI.autoFarmSpeedKnobCorner.CornerRadius = UDim.new(1,0)
UI.autoFarmSpeedKnobCorner.Parent = UI.autoFarmSpeedKnob

UI.autoFarmGroupLabel = Instance.new("TextLabel")
UI.autoFarmGroupLabel.Size = UDim2.new(1, -8, 0, 26)
UI.autoFarmGroupLabel.BackgroundTransparency = 1
UI.autoFarmGroupLabel.Text = "NPC Groups"
UI.autoFarmGroupLabel.TextColor3 = Color3.fromRGB(225,225,230)
UI.autoFarmGroupLabel.TextSize = 14
UI.autoFarmGroupLabel.Font = Enum.Font.GothamBold
UI.autoFarmGroupLabel.TextXAlignment = Enum.TextXAlignment.Left
UI.autoFarmGroupLabel.LayoutOrder = 9
UI.autoFarmGroupLabel.Parent = UI.espContent

UI.autoFarmGroupList = Instance.new("ScrollingFrame")
UI.autoFarmGroupList.Size = UDim2.new(1, -8, 0, 190)
UI.autoFarmGroupList.BackgroundColor3 = Color3.fromRGB(38, 38, 48)
UI.autoFarmGroupList.BackgroundTransparency = 0.15
UI.autoFarmGroupList.BorderSizePixel = 0
UI.autoFarmGroupList.ScrollBarThickness = 5
UI.autoFarmGroupList.ScrollBarImageColor3 = Color3.fromRGB(220, 135, 40)
UI.autoFarmGroupList.AutomaticCanvasSize = Enum.AutomaticSize.Y
UI.autoFarmGroupList.CanvasSize = UDim2.fromOffset(0, 0)
UI.autoFarmGroupList.ScrollingDirection = Enum.ScrollingDirection.Y
UI.autoFarmGroupList.LayoutOrder = 10
UI.autoFarmGroupList.Parent = UI.espContent

local autoFarmGroupListCorner = Instance.new("UICorner")
autoFarmGroupListCorner.CornerRadius = UDim.new(0, 9)
autoFarmGroupListCorner.Parent = UI.autoFarmGroupList

local autoFarmGroupListPadding = Instance.new("UIPadding")
autoFarmGroupListPadding.PaddingTop = UDim.new(0, 7)
autoFarmGroupListPadding.PaddingBottom = UDim.new(0, 7)
autoFarmGroupListPadding.PaddingLeft = UDim.new(0, 7)
autoFarmGroupListPadding.PaddingRight = UDim.new(0, 7)
autoFarmGroupListPadding.Parent = UI.autoFarmGroupList

UI.autoFarmGroupListLayout = Instance.new("UIListLayout")
UI.autoFarmGroupListLayout.Padding = UDim.new(0, 7)
UI.autoFarmGroupListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UI.autoFarmGroupListLayout.Parent = UI.autoFarmGroupList

local function refreshAutoFarmGroupList()
    for _, child in ipairs(UI.autoFarmGroupList:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end

    local groups = getNPCGroups()
    local names = {}
    for name in pairs(groups) do
        table.insert(names, name)
    end
    table.sort(names, function(a,b) return string.lower(a) < string.lower(b) end)

    UI.autoFarmGroupLabel.Text = "NPC Groups (" .. tostring(#names) .. ")"

    for index, name in ipairs(names) do
        local count = #groups[name]
        local button = Instance.new("TextButton")
        button.Name = "AutoFarmGroup_" .. name
        button.Size = UDim2.new(1, 0, 0, 38)
        button.BackgroundColor3 = State.SelectedFarmGroups[name]
            and Color3.fromRGB(45,170,95)
            or Color3.fromRGB(62,62,74)
        button.BorderSizePixel = 0
        button.Text = (State.SelectedFarmGroups[name] and "☑ " or "☐ ")
            .. name .. "  (x" .. tostring(count) .. ")"
        button.TextColor3 = Color3.new(1,1,1)
        button.TextSize = 13
        button.Font = Enum.Font.GothamMedium
        button.TextXAlignment = Enum.TextXAlignment.Left
        button.LayoutOrder = index
        button.Parent = UI.autoFarmGroupList

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 12)
        pad.Parent = button

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = button

        addConnection(button.Activated:Connect(function()
            local selected = not State.SelectedFarmGroups[name]
            State.SelectedFarmGroups[name] = selected
            State.SelectedNPCGroups[name] = selected
            refreshNPCESP()
            refreshAutoFarmGroupList()
            refreshAutoFarmState()
        end))
    end
end

UI.npcESPColorLabel = Instance.new("TextLabel")
UI.npcESPColorLabel.Size = UDim2.new(1, -8, 0, 26)
UI.npcESPColorLabel.BackgroundTransparency = 1
UI.npcESPColorLabel.Text = "NPC ESP Color"
UI.npcESPColorLabel.TextColor3 = Color3.fromRGB(225,225,230)
UI.npcESPColorLabel.TextSize = 14
UI.npcESPColorLabel.Font = Enum.Font.GothamBold
UI.npcESPColorLabel.TextXAlignment = Enum.TextXAlignment.Left
UI.npcESPColorLabel.LayoutOrder = 5
UI.npcESPColorLabel.Parent = UI.espContent

UI.npcESPColorFrame = Instance.new("Frame")
UI.npcESPColorFrame.Size = UDim2.new(1, -8, 0, 40)
UI.npcESPColorFrame.BackgroundTransparency = 1
UI.npcESPColorFrame.LayoutOrder = 6
UI.npcESPColorFrame.Parent = UI.espContent
UI.npcESPColorButtons = {}

local npcColorChoices = {
    {"Cyan", Color3.fromRGB(70, 245, 255)},
    {"Purple", Color3.fromRGB(180, 95, 255)},
    {"Orange", Color3.fromRGB(255, 165, 70)},
    {"White", Color3.fromRGB(255, 255, 255)},
}

for i, data in ipairs(npcColorChoices) do
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(34, 34)
    b.Position = UDim2.fromOffset((i - 1) * 42, 3)
    b.BackgroundColor3 = data[2]
    b.BorderSizePixel = 0
    b.Text = ""
    b.Parent = UI.npcESPColorFrame
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(1,0)
    c.Parent = b
    local st = Instance.new("UIStroke")
    st.Color = Color3.fromRGB(255,255,255)
    st.Thickness = data[2] == Config.ESPColor and 3 or 1
    st.Parent = b
    table.insert(UI.npcESPColorButtons, {Button=b, Color=data[2], Stroke=st})
    addConnection(b.Activated:Connect(function()
        Config.ESPColor = data[2]
        for _, x in ipairs(UI.npcESPColorButtons) do
            x.Stroke.Thickness = x.Color == Config.ESPColor and 3 or 1
        end
        refreshNPCESP()
    end))
end

local updatePlayerFlySpeedVisuals
local function showPage(pageName)
    local autoAttack = pageName == "AutoAttack"
    local esp = pageName == "ESP"
    local autoFarm = false
    local playerPage = pageName == "Player"
    local atkPlayer = pageName == "AtkPlayer"
    local effectPage = pageName == "Effect"

    UI.autoAttackContent.Visible = autoAttack
    UI.espContent.Visible = esp
    UI.autoFarmContent.Visible = false
    UI.playerContent.Visible = playerPage
    UI.atkPlayerContent.Visible = atkPlayer
    UI.effectContent.Visible = effectPage

    UI.autoAttackTab.BackgroundColor3 = autoAttack and Color3.fromRGB(220,135,40) or Color3.fromRGB(65,65,78)
    UI.espTab.BackgroundColor3 = esp and Color3.fromRGB(220,135,40) or Color3.fromRGB(65,65,78)
    UI.autoFarmTab.BackgroundColor3 = Color3.fromRGB(65,65,78)
    UI.playerTab.BackgroundColor3 = playerPage and Color3.fromRGB(220,135,40) or Color3.fromRGB(65,65,78)
    UI.atkPlayerTab.BackgroundColor3 = atkPlayer and Color3.fromRGB(220,135,40) or Color3.fromRGB(65,65,78)
    UI.effectTab.BackgroundColor3 = effectPage and Color3.fromRGB(220,135,40) or Color3.fromRGB(65,65,78)

    if autoAttack then
        updateAutoAttackSliderVisual()
        if UI.autoAttackToggle then
            UI.autoAttackToggle.Text = Config.AutoAttackEnabled and "ON" or "OFF"
            UI.autoAttackToggle.BackgroundColor3 = Config.AutoAttackEnabled
                and Color3.fromRGB(45, 170, 95)
                or Color3.fromRGB(75, 75, 88)
        end
    elseif esp then
        refreshAutoFarmGroupList()
        refreshNPCESP()
        updateAutoFarmSliderVisual()
        if UI.autoFarmToggle then
            UI.autoFarmToggle.Text = Config.AutoFarmEnabled and "ON" or "OFF"
            UI.autoFarmToggle.BackgroundColor3 = Config.AutoFarmEnabled
                and Color3.fromRGB(45, 170, 95)
                or Color3.fromRGB(75, 75, 88)
        end
    elseif playerPage then
        setPlayerESPEnabled(Config.PlayerESPEnabled)
        setPlayerNameEnabled(Config.PlayerNameEnabled)
        setPlayerFlyEnabled(Config.PlayerFlyEnabled)
        updatePlayerFlySpeedVisuals()
    elseif atkPlayer then
        refreshAtkPlayerList()
        updatePlayerFlySpeedVisuals()
        if UI.atkPlayerToggle then
            UI.atkPlayerToggle.Text = Config.AtkPlayerEnabled and "ON" or "OFF"
            UI.atkPlayerToggle.BackgroundColor3 = Config.AtkPlayerEnabled
                and Color3.fromRGB(45, 170, 95)
                or Color3.fromRGB(75, 75, 88)
        end
    elseif effectPage then
        setRemoveLightingEffects(Config.RemoveLightingEffects)
        setBrightLighting(Config.BrightLightingEnabled)
    end
end

UI.playerContent = Instance.new("ScrollingFrame")
UI.playerContent.Size = UDim2.new(1, -125, 1, -54)
UI.playerContent.Position = UDim2.fromOffset(125,54)
UI.playerContent.BackgroundTransparency = 1
UI.playerContent.BorderSizePixel = 0
UI.playerContent.ScrollBarThickness = 5
UI.playerContent.AutomaticCanvasSize = Enum.AutomaticSize.Y
UI.playerContent.CanvasSize = UDim2.fromOffset(0,0)
UI.playerContent.Visible = false
UI.playerContent.Parent = UI.main

local playerPad = Instance.new("UIPadding")
playerPad.PaddingTop = UDim.new(0,16)
playerPad.PaddingLeft = UDim.new(0,16)
playerPad.PaddingRight = UDim.new(0,16)
playerPad.PaddingBottom = UDim.new(0,16)
playerPad.Parent = UI.playerContent
local playerList = Instance.new("UIListLayout")
playerList.Padding = UDim.new(0,10)
playerList.SortOrder = Enum.SortOrder.LayoutOrder
playerList.Parent = UI.playerContent

local function makeRow(parent, title, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1,0,0,42)
    row.BackgroundTransparency = 1
    row.LayoutOrder = order
    row.Parent = parent
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1,-115,1,0)
    label.BackgroundTransparency = 1
    label.Text = title
    label.TextColor3 = Color3.new(1,1,1)
    label.TextSize = 14
    label.Font = Enum.Font.GothamBold
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row
    return row, label
end

local espRow = makeRow(UI.playerContent, "ESP Player ทั้งหมด", 6)
UI.playerESPToggle = Instance.new("TextButton")
UI.playerESPToggle.Size = UDim2.fromOffset(100,38)
UI.playerESPToggle.Position = UDim2.new(1,-100,0,2)
UI.playerESPToggle.BackgroundColor3 = Color3.fromRGB(75,75,88)
UI.playerESPToggle.BorderSizePixel = 0
UI.playerESPToggle.Text = "OFF"
UI.playerESPToggle.TextColor3 = Color3.new(1,1,1)
UI.playerESPToggle.Font = Enum.Font.GothamBold
UI.playerESPToggle.TextSize = 14
UI.playerESPToggle.Parent = espRow
local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,8); c.Parent = UI.playerESPToggle

local nameRow = makeRow(UI.playerContent, "ชื่อบนหัว Player", 7)
UI.playerNameToggle = Instance.new("TextButton")
UI.playerNameToggle.Size = UDim2.fromOffset(100,38)
UI.playerNameToggle.Position = UDim2.new(1,-100,0,2)
UI.playerNameToggle.BackgroundColor3 = Color3.fromRGB(75,75,88)
UI.playerNameToggle.BorderSizePixel = 0
UI.playerNameToggle.Text = "OFF"
UI.playerNameToggle.TextColor3 = Color3.new(1,1,1)
UI.playerNameToggle.Font = Enum.Font.GothamBold
UI.playerNameToggle.TextSize = 14
UI.playerNameToggle.Parent = nameRow
local nc = Instance.new("UICorner"); nc.CornerRadius = UDim.new(0,8); nc.Parent = UI.playerNameToggle

UI.playerESPColorLabel = Instance.new("TextLabel")
UI.playerESPColorLabel.Size = UDim2.new(1,0,0,26)
UI.playerESPColorLabel.BackgroundTransparency = 1
UI.playerESPColorLabel.Text = "ESP Color"
UI.playerESPColorLabel.TextColor3 = Color3.fromRGB(225,225,230)
UI.playerESPColorLabel.TextSize = 14
UI.playerESPColorLabel.Font = Enum.Font.GothamBold
UI.playerESPColorLabel.TextXAlignment = Enum.TextXAlignment.Left
UI.playerESPColorLabel.LayoutOrder = 8
UI.playerESPColorLabel.Parent = UI.playerContent

UI.playerESPColorFrame = Instance.new("Frame")
UI.playerESPColorFrame.Size = UDim2.new(1,0,0,40)
UI.playerESPColorFrame.BackgroundTransparency = 1
UI.playerESPColorFrame.LayoutOrder = 9
UI.playerESPColorFrame.Parent = UI.playerContent
UI.playerESPColorButtons = {}
local playerColors = {
    {"Red", Color3.fromRGB(255,70,70)},
    {"Yellow", Color3.fromRGB(255,220,70)},
    {"Green", Color3.fromRGB(70,220,110)},
    {"Blue", Color3.fromRGB(70,140,255)},
}
for i, data in ipairs(playerColors) do
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0.25,-6,1,0)
    b.Position = UDim2.new((i-1)*0.25, (i-1)*8, 0,0)
    b.BackgroundColor3 = data[2]
    b.BorderSizePixel = 0
    b.Text = data[1]
    b.TextColor3 = Color3.new(1,1,1)
    b.TextSize = 11
    b.Font = Enum.Font.GothamBold
    b.Parent = UI.playerESPColorFrame
    local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0,8); bc.Parent = b
    local st = Instance.new("UIStroke"); st.Color = Color3.new(1,1,1); st.Thickness = 1; st.Parent = b
    table.insert(UI.playerESPColorButtons, {Button=b, Color=data[2], Stroke=st})
    addConnection(b.Activated:Connect(function()
        Config.PlayerESPColor = data[2]
        refreshPlayerESP()
        for _, x in ipairs(UI.playerESPColorButtons) do
            x.Stroke.Thickness = x.Color == Config.PlayerESPColor and 3 or 1
        end
    end))
end

local flyRow = makeRow(UI.playerContent, "Fly", 1)
UI.playerFlyToggle = Instance.new("TextButton")
UI.playerFlyToggle.Size = UDim2.fromOffset(100,38)
UI.playerFlyToggle.Position = UDim2.new(1,-100,0,2)
UI.playerFlyToggle.BackgroundColor3 = Color3.fromRGB(75,75,88)
UI.playerFlyToggle.BorderSizePixel = 0
UI.playerFlyToggle.Text = "OFF"
UI.playerFlyToggle.TextColor3 = Color3.new(1,1,1)
UI.playerFlyToggle.Font = Enum.Font.GothamBold
UI.playerFlyToggle.TextSize = 14
UI.playerFlyToggle.Parent = flyRow
local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0,8); fc.Parent = UI.playerFlyToggle

local noClipRow = makeRow(UI.playerContent, "No Clip", 2)
UI.playerNoClipToggle = Instance.new("TextButton")
UI.playerNoClipToggle.Size = UDim2.fromOffset(100,38)
UI.playerNoClipToggle.Position = UDim2.new(1,-100,0,2)
UI.playerNoClipToggle.BackgroundColor3 = Color3.fromRGB(75,75,88)
UI.playerNoClipToggle.BorderSizePixel = 0
UI.playerNoClipToggle.Text = "OFF"
UI.playerNoClipToggle.TextColor3 = Color3.new(1,1,1)
UI.playerNoClipToggle.Font = Enum.Font.GothamBold
UI.playerNoClipToggle.TextSize = 14
UI.playerNoClipToggle.Parent = noClipRow
local ncc = Instance.new("UICorner"); ncc.CornerRadius = UDim.new(0,8); ncc.Parent = UI.playerNoClipToggle

UI.playerFlySpeedLabel = Instance.new("TextLabel")
UI.playerFlySpeedLabel.Size = UDim2.new(1,0,0,26)
UI.playerFlySpeedLabel.BackgroundTransparency = 1
UI.playerFlySpeedLabel.Text = "Fly Speed (Shared): " .. tostring(Config.FlySpeed)
UI.playerFlySpeedLabel.TextColor3 = Color3.fromRGB(225,225,230)
UI.playerFlySpeedLabel.TextSize = 14
UI.playerFlySpeedLabel.Font = Enum.Font.GothamMedium
UI.playerFlySpeedLabel.TextXAlignment = Enum.TextXAlignment.Left
UI.playerFlySpeedLabel.LayoutOrder = 3
UI.playerFlySpeedLabel.Parent = UI.playerContent

UI.playerFlySpeedSlider = Instance.new("Frame")
UI.playerFlySpeedSlider.Size = UDim2.new(1,0,0,12)
UI.playerFlySpeedSlider.BackgroundColor3 = Color3.fromRGB(62,62,72)
UI.playerFlySpeedSlider.BorderSizePixel = 0
UI.playerFlySpeedSlider.Active = true
UI.playerFlySpeedSlider.LayoutOrder = 4
UI.playerFlySpeedSlider.Parent = UI.playerContent
local psc = Instance.new("UICorner"); psc.CornerRadius = UDim.new(1,0); psc.Parent = UI.playerFlySpeedSlider
UI.playerFlySpeedFill = Instance.new("Frame")
UI.playerFlySpeedFill.BackgroundColor3 = Color3.fromRGB(220,135,40)
UI.playerFlySpeedFill.BorderSizePixel = 0
UI.playerFlySpeedFill.Size = UDim2.fromScale(0,1)
UI.playerFlySpeedFill.Parent = UI.playerFlySpeedSlider
local pfc = Instance.new("UICorner"); pfc.CornerRadius = UDim.new(1,0); pfc.Parent = UI.playerFlySpeedFill
UI.playerFlySpeedKnob = Instance.new("TextButton")
UI.playerFlySpeedKnob.Size = UDim2.fromOffset(22,22)
UI.playerFlySpeedKnob.AnchorPoint = Vector2.new(0.5,0.5)
UI.playerFlySpeedKnob.Position = UDim2.new(0,0,0.5,0)
UI.playerFlySpeedKnob.BackgroundColor3 = Color3.fromRGB(255,242,220)
UI.playerFlySpeedKnob.BorderSizePixel = 0
UI.playerFlySpeedKnob.Text = ""
UI.playerFlySpeedKnob.Parent = UI.playerFlySpeedSlider
local pkc = Instance.new("UICorner"); pkc.CornerRadius = UDim.new(1,0); pkc.Parent = UI.playerFlySpeedKnob

UI.atkPlayerContent = Instance.new("ScrollingFrame")
UI.atkPlayerContent.Size = UDim2.new(1,-125,1,-54)
UI.atkPlayerContent.Position = UDim2.fromOffset(125,54)
UI.atkPlayerContent.BackgroundTransparency = 1
UI.atkPlayerContent.BorderSizePixel = 0
UI.atkPlayerContent.ScrollBarThickness = 5
UI.atkPlayerContent.AutomaticCanvasSize = Enum.AutomaticSize.Y
UI.atkPlayerContent.CanvasSize = UDim2.fromOffset(0,0)
UI.atkPlayerContent.Visible = false
UI.atkPlayerContent.Parent = UI.main
local atkPad = Instance.new("UIPadding"); atkPad.PaddingTop=UDim.new(0,16); atkPad.PaddingLeft=UDim.new(0,16); atkPad.PaddingRight=UDim.new(0,16); atkPad.PaddingBottom=UDim.new(0,16); atkPad.Parent=UI.atkPlayerContent
local atkList = Instance.new("UIListLayout"); atkList.Padding=UDim.new(0,9); atkList.SortOrder=Enum.SortOrder.LayoutOrder; atkList.Parent=UI.atkPlayerContent

local atkToggleRow = makeRow(UI.atkPlayerContent, "Fly + Auto Atk Player", 2)
UI.atkPlayerToggle = Instance.new("TextButton")
UI.atkPlayerToggle.Size = UDim2.fromOffset(100,38)
UI.atkPlayerToggle.Position = UDim2.new(1,-100,0,2)
UI.atkPlayerToggle.BackgroundColor3 = Color3.fromRGB(75,75,88)
UI.atkPlayerToggle.BorderSizePixel = 0
UI.atkPlayerToggle.Text = "OFF"
UI.atkPlayerToggle.TextColor3 = Color3.new(1,1,1)
UI.atkPlayerToggle.Font = Enum.Font.GothamBold
UI.atkPlayerToggle.TextSize = 14
UI.atkPlayerToggle.Parent = atkToggleRow
local atc = Instance.new("UICorner"); atc.CornerRadius=UDim.new(0,8); atc.Parent=UI.atkPlayerToggle

local atkNearbyRow = makeRow(UI.atkPlayerContent, "Atk Player ใกล้ตัว", 3)
UI.atkPlayerNearbyToggle = Instance.new("TextButton")
UI.atkPlayerNearbyToggle.Size = UDim2.fromOffset(100,38)
UI.atkPlayerNearbyToggle.Position = UDim2.new(1,-100,0,2)
UI.atkPlayerNearbyToggle.BackgroundColor3 = Color3.fromRGB(75,75,88)
UI.atkPlayerNearbyToggle.BorderSizePixel = 0
UI.atkPlayerNearbyToggle.Text = "OFF"
UI.atkPlayerNearbyToggle.TextColor3 = Color3.new(1,1,1)
UI.atkPlayerNearbyToggle.Font = Enum.Font.GothamBold
UI.atkPlayerNearbyToggle.TextSize = 14
UI.atkPlayerNearbyToggle.Parent = atkNearbyRow
local atnc = Instance.new("UICorner"); atnc.CornerRadius=UDim.new(0,8); atnc.Parent=UI.atkPlayerNearbyToggle

UI.atkPlayerDistanceLabel = Instance.new("TextLabel")
UI.atkPlayerDistanceLabel.Size = UDim2.new(1, -32, 0, 26)
UI.atkPlayerDistanceLabel.BackgroundTransparency = 1
UI.atkPlayerDistanceLabel.Text = "Atk Player Distance: " .. tostring(Config.AtkPlayerDistance) .. " studs"
UI.atkPlayerDistanceLabel.TextColor3 = Color3.fromRGB(225,225,230)
UI.atkPlayerDistanceLabel.TextSize = 14
UI.atkPlayerDistanceLabel.Font = Enum.Font.GothamMedium
UI.atkPlayerDistanceLabel.TextXAlignment = Enum.TextXAlignment.Left
UI.atkPlayerDistanceLabel.Position = UDim2.fromOffset(16, 242)
UI.atkPlayerDistanceLabel.Parent = UI.autoAttackContent

UI.atkPlayerDistanceSlider = Instance.new("Frame")
UI.atkPlayerDistanceSlider.Size = UDim2.new(1, -40, 0, 12)
UI.atkPlayerDistanceSlider.BackgroundColor3 = Color3.fromRGB(62,62,72)
UI.atkPlayerDistanceSlider.BorderSizePixel = 0
UI.atkPlayerDistanceSlider.Active = true
UI.atkPlayerDistanceSlider.Position = UDim2.fromOffset(20, 280)
UI.atkPlayerDistanceSlider.Parent = UI.autoAttackContent
local adsc=Instance.new("UICorner"); adsc.CornerRadius=UDim.new(1,0); adsc.Parent=UI.atkPlayerDistanceSlider
UI.atkPlayerDistanceFill = Instance.new("Frame")
UI.atkPlayerDistanceFill.Size = UDim2.fromScale(0,1)
UI.atkPlayerDistanceFill.BackgroundColor3 = Color3.fromRGB(220,135,40)
UI.atkPlayerDistanceFill.BorderSizePixel = 0
UI.atkPlayerDistanceFill.Parent = UI.atkPlayerDistanceSlider
local adsfc=Instance.new("UICorner"); adsfc.CornerRadius=UDim.new(1,0); adsfc.Parent=UI.atkPlayerDistanceFill
UI.atkPlayerDistanceKnob = Instance.new("TextButton")
UI.atkPlayerDistanceKnob.Size = UDim2.fromOffset(22,22)
UI.atkPlayerDistanceKnob.AnchorPoint = Vector2.new(0.5,0.5)
UI.atkPlayerDistanceKnob.Position = UDim2.new(0,0,0.5,0)
UI.atkPlayerDistanceKnob.BackgroundColor3 = Color3.fromRGB(255,242,220)
UI.atkPlayerDistanceKnob.BorderSizePixel = 0
UI.atkPlayerDistanceKnob.Text = ""
UI.atkPlayerDistanceKnob.Parent = UI.atkPlayerDistanceSlider
local adskc=Instance.new("UICorner"); adskc.CornerRadius=UDim.new(1,0); adskc.Parent=UI.atkPlayerDistanceKnob

UI.atkPlayerListLabel = Instance.new("TextLabel")
UI.atkPlayerListLabel.Size = UDim2.new(1,0,0,26)
UI.atkPlayerListLabel.BackgroundTransparency = 1
UI.atkPlayerListLabel.Text = "Players"
UI.atkPlayerListLabel.TextColor3 = Color3.fromRGB(225,225,230)
UI.atkPlayerListLabel.TextSize = 14
UI.atkPlayerListLabel.Font = Enum.Font.GothamBold
UI.atkPlayerListLabel.TextXAlignment = Enum.TextXAlignment.Left
UI.atkPlayerListLabel.LayoutOrder = 8
UI.atkPlayerListLabel.Parent = UI.atkPlayerContent

UI.atkPlayerSearch = Instance.new("TextBox")
UI.atkPlayerSearch.Size = UDim2.new(1,0,0,38)
UI.atkPlayerSearch.BackgroundColor3 = Color3.fromRGB(48,48,60)
UI.atkPlayerSearch.BorderSizePixel = 0
UI.atkPlayerSearch.ClearTextOnFocus = false
UI.atkPlayerSearch.PlaceholderText = "Search player..."
UI.atkPlayerSearch.PlaceholderColor3 = Color3.fromRGB(145,145,155)
UI.atkPlayerSearch.Text = ""
UI.atkPlayerSearch.TextColor3 = Color3.fromRGB(245,245,248)
UI.atkPlayerSearch.TextSize = 13
UI.atkPlayerSearch.Font = Enum.Font.GothamMedium
UI.atkPlayerSearch.TextXAlignment = Enum.TextXAlignment.Left
UI.atkPlayerSearch.LayoutOrder = 9
UI.atkPlayerSearch.Parent = UI.atkPlayerContent
local apsp=Instance.new("UIPadding"); apsp.PaddingLeft=UDim.new(0,12); apsp.PaddingRight=UDim.new(0,12); apsp.Parent=UI.atkPlayerSearch
local apsc=Instance.new("UICorner"); apsc.CornerRadius=UDim.new(0,8); apsc.Parent=UI.atkPlayerSearch

UI.atkPlayerList = Instance.new("ScrollingFrame")
UI.atkPlayerList.Size = UDim2.new(1,0,0,190)
UI.atkPlayerList.BackgroundColor3 = Color3.fromRGB(38,38,48)
UI.atkPlayerList.BackgroundTransparency = 0.15
UI.atkPlayerList.BorderSizePixel = 0
UI.atkPlayerList.ScrollBarThickness = 5
UI.atkPlayerList.ScrollBarImageColor3 = Color3.fromRGB(220,135,40)
UI.atkPlayerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
UI.atkPlayerList.CanvasSize = UDim2.fromOffset(0,0)
UI.atkPlayerList.ScrollingDirection = Enum.ScrollingDirection.Y
UI.atkPlayerList.LayoutOrder = 10
UI.atkPlayerList.Parent = UI.atkPlayerContent
local aplc=Instance.new("UICorner"); aplc.CornerRadius=UDim.new(0,9); aplc.Parent=UI.atkPlayerList
local app=Instance.new("UIPadding"); app.PaddingTop=UDim.new(0,7); app.PaddingBottom=UDim.new(0,7); app.PaddingLeft=UDim.new(0,7); app.PaddingRight=UDim.new(0,7); app.Parent=UI.atkPlayerList
local apl=Instance.new("UIListLayout"); apl.Padding=UDim.new(0,7); apl.SortOrder=Enum.SortOrder.LayoutOrder; apl.Parent=UI.atkPlayerList

local function updateAtkPlayerDistanceVisuals()
    local range = math.max(0.001, Config.MaxAtkPlayerDistance - Config.MinAtkPlayerDistance)
    local percent = math.clamp((Config.AtkPlayerDistance - Config.MinAtkPlayerDistance) / range, 0, 1)
    if UI.atkPlayerDistanceFill then UI.atkPlayerDistanceFill.Size = UDim2.fromScale(percent, 1) end
    if UI.atkPlayerDistanceKnob then UI.atkPlayerDistanceKnob.Position = UDim2.new(percent, 0, 0.5, 0) end
    if UI.atkPlayerDistanceLabel then UI.atkPlayerDistanceLabel.Text = "Atk Player Distance: " .. tostring(Config.AtkPlayerDistance) .. " studs" end
end

local function setAtkPlayerDistanceFromSlider(x)
    local slider = UI.atkPlayerDistanceSlider
    if not slider or slider.AbsoluteSize.X <= 0 then return end
    local percent = math.clamp((x - slider.AbsolutePosition.X) / slider.AbsoluteSize.X, 0, 1)
    Config.AtkPlayerDistance = math.floor(Config.MinAtkPlayerDistance + (Config.MaxAtkPlayerDistance - Config.MinAtkPlayerDistance) * percent + 0.5)
    updateAtkPlayerDistanceVisuals()
end

updatePlayerFlySpeedVisuals = function()
    local percent = math.clamp((Config.FlySpeed-Config.MinFlySpeed)/(Config.MaxFlySpeed-Config.MinFlySpeed),0,1)
    if UI.playerFlySpeedFill then UI.playerFlySpeedFill.Size = UDim2.fromScale(percent,1) end
    if UI.playerFlySpeedKnob then UI.playerFlySpeedKnob.Position = UDim2.new(percent,0,0.5,0) end
    if UI.playerFlySpeedLabel then UI.playerFlySpeedLabel.Text = "Fly Speed (Shared): " .. tostring(Config.FlySpeed) end
end

local function setSharedFlySpeedFromSlider(slider, x)
    if not slider or slider.AbsoluteSize.X <= 0 then return end
    local percent = math.clamp((x-slider.AbsolutePosition.X)/slider.AbsoluteSize.X,0,1)
    Config.FlySpeed = math.floor(Config.MinFlySpeed + (Config.MaxFlySpeed-Config.MinFlySpeed)*percent + 0.5)
    Config.AutoFarmFlySpeed = Config.FlySpeed
    updateAutoFarmSliderVisual()
    updatePlayerFlySpeedVisuals()
end

refreshAtkPlayerList = function()
    for _, child in ipairs(UI.atkPlayerList:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end

    local query = ""
    if UI.atkPlayerSearch then
        query = string.lower(UI.atkPlayerSearch.Text or "")
        query = string.gsub(query, "^%s*(.-)%s*$", "%1")
    end

    local list = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player then
            local username = string.lower(plr.Name or "")
            local displayName = string.lower(plr.DisplayName or "")
            if query == ""
                or string.find(username, query, 1, true)
                or string.find(displayName, query, 1, true) then
                table.insert(list, plr)
            end
        end
    end

    table.sort(list, function(a,b)
        return string.lower(a.Name) < string.lower(b.Name)
    end)

    UI.atkPlayerListLabel.Text = "Players (" .. tostring(#list) .. ")"

    for i, plr in ipairs(list) do
        local key = tostring(plr.UserId)
        local selected = State.SelectedPlayers[key] == true
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1,0,0,38)
        b.BackgroundColor3 = selected and Color3.fromRGB(45,170,95) or Color3.fromRGB(62,62,74)
        b.BorderSizePixel = 0
        local species = plr.Character and (plr.Character:GetAttribute("Species") or plr.Character.Name) or "No Character"
        local display = plr.DisplayName and plr.DisplayName ~= plr.Name and (plr.DisplayName .. " (@" .. plr.Name .. ")") or plr.Name
        b.Text = (selected and "☑ " or "☐ ") .. display .. "  [" .. tostring(species) .. "]"
        b.TextColor3 = Color3.new(1,1,1)
        b.TextSize = 13
        b.Font = Enum.Font.GothamMedium
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.LayoutOrder = i
        b.Parent = UI.atkPlayerList
        local bp=Instance.new("UIPadding"); bp.PaddingLeft=UDim.new(0,12); bp.Parent=b
        local bc=Instance.new("UICorner"); bc.CornerRadius=UDim.new(0,8); bc.Parent=b
        addConnection(b.Activated:Connect(function()
            local wasSelected = State.SelectedPlayers[key] == true
            Config.AtkPlayerNearbyEnabled = false
            State.NearbyAtkTargetUserId = nil
            updateAtkPlayerNearbyButton()
            table.clear(State.SelectedPlayers)
            if not wasSelected then
                State.SelectedPlayers[key] = true
            end
            refreshAtkPlayerList()
            if Config.AtkPlayerEnabled then startAtkPlayer() end
        end))
    end
end

addConnection(UI.atkPlayerSearch:GetPropertyChangedSignal("Text"):Connect(function()
    refreshAtkPlayerList()
end))

UI.logoButton = Instance.new("TextButton")
UI.logoButton.Size = UDim2.fromOffset(58, 58)
UI.logoButton.Position = UDim2.new(0.5, -29, 0, 90)
UI.logoButton.BackgroundColor3 = Color3.fromRGB(235, 143, 42)
UI.logoButton.BorderSizePixel = 0
UI.logoButton.Text = "🐯"
UI.logoButton.TextSize = 30
UI.logoButton.Font = Enum.Font.GothamBold
UI.logoButton.Visible = false
UI.logoButton.ZIndex = 999999
UI.logoButton.Parent = UI.screenGui

local logoCorner = Instance.new("UICorner")
logoCorner.CornerRadius = UDim.new(1, 0)
logoCorner.Parent = UI.logoButton

for _, gui in ipairs(UI.screenGui:GetDescendants()) do
    if gui:IsA("GuiButton") then
        gui.Active = true
        gui.Selectable = true
    end
end

addConnection(UI.autoAttackTab.Activated:Connect(function()
    showPage("AutoAttack")
end))

addConnection(UI.espTab.Activated:Connect(function()
    showPage("ESP")
end))

addConnection(UI.autoFarmTab.Activated:Connect(function()
    showPage("ESP")
end))

addConnection(UI.playerTab.Activated:Connect(function()
    showPage("Player")
end))

addConnection(UI.atkPlayerTab.Activated:Connect(function()
    showPage("AtkPlayer")
end))

addConnection(UI.effectTab.Activated:Connect(function()
    showPage("Effect")
end))

addConnection(UI.effectToggle.Activated:Connect(function()
    setRemoveLightingEffects(not Config.RemoveLightingEffects)
end))

addConnection(UI.brightnessToggle.Activated:Connect(function()
    setBrightLighting(not Config.BrightLightingEnabled)
end))

addConnection(Lighting.ChildAdded:Connect(function(object)
    if Config.RemoveLightingEffects and isRemovableLightingEffect(object) then
        task.defer(function()
            if Config.RemoveLightingEffects and object.Parent == Lighting then
                backupAndRemoveLightingEffect(object)
            end
        end)
    end
end))

local npcRefreshQueued = false
local function queueNPCRefresh()
    if npcRefreshQueued or State.Closed then return end
    npcRefreshQueued = true
    task.delay(0.12, function()
        npcRefreshQueued = false
        if State.Closed then return end
        refreshNPCGroupList()
        refreshNPCESP()
        refreshAutoFarmGroupList()
    end)
end

local npcFolderForEvents = getFeralNPCFolder()
if npcFolderForEvents then
    addConnection(npcFolderForEvents.ChildAdded:Connect(function(object)
        if object:IsA("Model") then queueNPCRefresh() end
    end))
    addConnection(npcFolderForEvents.ChildRemoved:Connect(function(object)
        if object:IsA("Model") then queueNPCRefresh() end
    end))
end

local function bindAtkPlayerDeath(plr, character)
    if plr == player or not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
        or character:WaitForChild("Humanoid", 5)
    if not humanoid then return end

    addConnection(humanoid.Died:Connect(function()
        local key = tostring(plr.UserId)
        State.SelectedPlayers[key] = nil
        if State.NearbyAtkTargetUserId == plr.UserId then
            State.NearbyAtkTargetUserId = nil
        end
        if refreshAtkPlayerList then task.defer(refreshAtkPlayerList) end
    end))
end

addConnection(Players.PlayerAdded:Connect(function(plr)
    addConnection(plr.CharacterAdded:Connect(function(character)
        task.wait(0.2)
        bindAtkPlayerDeath(plr, character)
        refreshPlayerESP()
        refreshAtkPlayerList()
    end))
    task.defer(refreshAtkPlayerList)
task.defer(updateAtkPlayerDistanceVisuals)
end))

addConnection(Players.PlayerRemoving:Connect(function(plr)
    removePlayerESP(plr)
    State.SelectedPlayers[tostring(plr.UserId)] = nil
    if State.NearbyAtkTargetUserId == plr.UserId then State.NearbyAtkTargetUserId = nil end
    task.defer(refreshAtkPlayerList)
end))

for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= player then
        if plr.Character then
            task.defer(bindAtkPlayerDeath, plr, plr.Character)
        end
        addConnection(plr.CharacterAdded:Connect(function(character)
            task.wait(0.2)
            bindAtkPlayerDeath(plr, character)
            refreshPlayerESP()
            refreshAtkPlayerList()
        end))
    end
end

local playerNameAccum = 0
addConnection(RunService.Heartbeat:Connect(function(dt)
    if not Config.PlayerNameEnabled then return end
    playerNameAccum += dt
    if playerNameAccum < 0.10 then return end
    playerNameAccum = 0

    local myRoot = getPlayerRoot(player)
    if not myRoot then return end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and isPlayerAlive(plr) then
            local character = plr.Character
            local targetRoot = getPlayerRoot(plr)
            if character and targetRoot then
                local billboard = character:FindFirstChild(PLAYER_NAME_GUI)
                local label = billboard and billboard:FindFirstChild("Label")
                if label then
                    local species = character:GetAttribute("Species") or character.Name
                    local distanceMeters = (myRoot.Position - targetRoot.Position).Magnitude * 0.28
                    label.Text = plr.Name .. "\n" .. tostring(species) .. "  •  " .. string.format("%.1f m", distanceMeters)
                    label.TextColor3 = Config.PlayerESPColor
                end
            end
        end
    end
end))

addConnection(UI.autoAttackToggle.Activated:Connect(function()
    setAutoAttackEnabled(not Config.AutoAttackEnabled)
end))

addConnection(UI.autoFarmToggle.Activated:Connect(function()
    setAutoFarmEnabled(not Config.AutoFarmEnabled)
end))

addConnection(UI.playerESPToggle.Activated:Connect(function()
    setPlayerESPEnabled(not Config.PlayerESPEnabled)
end))

addConnection(UI.playerNameToggle.Activated:Connect(function()
    setPlayerNameEnabled(not Config.PlayerNameEnabled)
end))

addConnection(UI.playerFlyToggle.Activated:Connect(function()
    setPlayerFlyEnabled(not Config.PlayerFlyEnabled)
end))

addConnection(UI.playerNoClipToggle.Activated:Connect(function()
    State.setPlayerNoClipEnabled(not Config.PlayerNoClipEnabled)
end))

addConnection(UI.atkPlayerToggle.Activated:Connect(function()
    setAtkPlayerEnabled(not Config.AtkPlayerEnabled)
end))

addConnection(UI.atkPlayerNearbyToggle.Activated:Connect(function()
    setAtkPlayerNearbyEnabled(not Config.AtkPlayerNearbyEnabled)
end))

local function beginAtkPlayerDistanceSlider(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        State.DraggingAtkPlayerDistanceSlider = true
        setAtkPlayerDistanceFromSlider(input.Position.X)
    end
end
addConnection(UI.atkPlayerDistanceSlider.InputBegan:Connect(beginAtkPlayerDistanceSlider))
addConnection(UI.atkPlayerDistanceKnob.InputBegan:Connect(beginAtkPlayerDistanceSlider))

local function beginPlayerFlySlider(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        State.DraggingPlayerFlySlider = true
        setSharedFlySpeedFromSlider(UI.playerFlySpeedSlider, input.Position.X)
    end
end
addConnection(UI.playerFlySpeedSlider.InputBegan:Connect(beginPlayerFlySlider))
addConnection(UI.playerFlySpeedKnob.InputBegan:Connect(beginPlayerFlySlider))

local function beginAutoAttackSlider(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        State.DraggingAutoAttackSlider = true
        setAutoAttackIntervalFromX(input.Position.X)
    end
end

addConnection(UI.autoAttackSpeedSlider.InputBegan:Connect(beginAutoAttackSlider))
addConnection(UI.autoAttackSpeedKnob.InputBegan:Connect(beginAutoAttackSlider))

local function beginAutoFarmSlider(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        State.DraggingAutoFarmSlider = true
        setAutoFarmFlySpeedFromX(input.Position.X)
    end
end

addConnection(UI.autoFarmSpeedSlider.InputBegan:Connect(beginAutoFarmSlider))
addConnection(UI.autoFarmSpeedKnob.InputBegan:Connect(beginAutoFarmSlider))

addConnection(UserInputService.InputChanged:Connect(function(input)
    if State.DraggingAutoFarmSlider and (
        input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
    ) then
        setAutoFarmFlySpeedFromX(input.Position.X)
    end

    if State.DraggingAutoAttackSlider and (
        input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
    ) then
        setAutoAttackIntervalFromX(input.Position.X)
    end

    if State.DraggingPlayerFlySlider and (
        input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
    ) then
        setSharedFlySpeedFromSlider(UI.playerFlySpeedSlider, input.Position.X)
    end

    if State.DraggingAtkPlayerDistanceSlider and (
        input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
    ) then
        setAtkPlayerDistanceFromSlider(input.Position.X)
    end

    if State.DraggingWindow and (
        input == State.WindowDragInput
        or input.UserInputType == Enum.UserInputType.Touch
    ) then
        local delta = input.Position - State.WindowDragStart
        UI.main.Position = UDim2.new(
            State.WindowStartPosition.X.Scale,
            State.WindowStartPosition.X.Offset + delta.X,
            State.WindowStartPosition.Y.Scale,
            State.WindowStartPosition.Y.Offset + delta.Y
        )
    end
end))

addConnection(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        State.DraggingAutoFarmSlider = false
        State.DraggingAutoAttackSlider = false
        State.DraggingPlayerFlySlider = false
        State.DraggingAtkPlayerDistanceSlider = false
        State.DraggingWindow = false
    end
end))

local function beginWindowDrag(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    State.DraggingWindow = true
    State.WindowDragStart = input.Position
    State.WindowStartPosition = UI.main.Position
    State.WindowDragInput = input

    addConnection(input.Changed:Connect(function()
        if input.UserInputState == Enum.UserInputState.End then
            State.DraggingWindow = false
            State.WindowDragInput = nil
        end
    end))
end

UI.titleBar.Active = true
titleFix.Active = true
UI.tigerLogo.Active = true
UI.title.Active = true

addConnection(UI.titleBar.InputBegan:Connect(beginWindowDrag))
addConnection(titleFix.InputBegan:Connect(beginWindowDrag))
addConnection(UI.tigerLogo.InputBegan:Connect(beginWindowDrag))
addConnection(UI.title.InputBegan:Connect(beginWindowDrag))

addConnection(UserInputService.InputChanged:Connect(function(input)
    if not State.DraggingWindow then return end

    if input.UserInputType == Enum.UserInputType.MouseMovement then
        State.WindowDragInput = input
    end
end))

local function minimize()
    UI.main.Visible = false
    UI.logoButton.Visible = true
end

local function restore()
    UI.main.Visible = true
    UI.logoButton.Visible = false
end

addConnection(UI.minimize.Activated:Connect(minimize))
addConnection(UI.logoButton.Activated:Connect(restore))

addConnection(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if State.Closed then return end
    if UserInputService:GetFocusedTextBox() then return end

    if input.KeyCode == Config.ToggleKey then
        if UI.main.Visible then
            minimize()
        else
            restore()
        end
    end
end))

local function closeScript()
    if State.Closed then return end
    State.Closed = true
    stopAutoAttack()
    stopAutoFarm()
    stopPlayerFly()
    State.stopPlayerNoClip()
    stopAtkPlayer()
    if Config.BrightLightingEnabled then setBrightLighting(false) end
    table.clear(State.SelectedFarmGroups)
    table.clear(State.SelectedPlayers)
    clearNPCESP()
    clearPlayerESP()
    clearPlayerNames()

    for _, connection in ipairs(connections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    table.clear(connections)

    if UI.screenGui then
        UI.screenGui:Destroy()
    end
end

addConnection(UI.close.Activated:Connect(closeScript))

player.CharacterAdded:Connect(function()
    cancelAutoFarmTween()
    cancelAtkPlayerTween()
    if Config.PlayerFlyEnabled then task.defer(startPlayerFly) end
    if Config.PlayerNoClipEnabled then task.defer(State.startPlayerNoClip) end
end)

task.defer(refreshNPCGroupList)
task.defer(refreshAutoFarmGroupList)
task.defer(updateAutoFarmSliderVisual)
task.defer(function() setAutoFarmEnabled(Config.AutoFarmEnabled) end)
task.defer(updateAutoAttackSliderVisual)
task.defer(refreshAtkPlayerList)
task.defer(updatePlayerFlySpeedVisuals)
task.defer(refreshPlayerESP)
setAutoAttackEnabled(false)
showPage("AutoAttack")
