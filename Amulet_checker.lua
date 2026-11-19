--==================================================
-- Amulet Authenticity Checker UI
-- Tray1 - Tray9
--
-- GREEN  = REAL
-- RED    = FAKE
-- YELLOW = UNKNOWN
--
-- Detect:
-- MeshId + SurfaceAppearance
--
-- RightShift = Show / Hide UI
--==================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Plots = Workspace:WaitForChild("Plots")
local AmuletMeshes = ReplicatedStorage:WaitForChild("AmuletMeshes")

--==================================================
-- STOP OLD INSTANCE
--==================================================

getgenv().AmuletCheckerVersion =
    (getgenv().AmuletCheckerVersion or 0) + 1

local THIS_VERSION =
    getgenv().AmuletCheckerVersion

getgenv().AmuletCheckRunning = false

task.wait(0.15)

getgenv().AmuletCheckRunning = true

--==================================================
-- REMOVE OLD UI
--==================================================

local oldUI =
    PlayerGui:FindFirstChild("AmuletCheckerUI")

if oldUI then
    oldUI:Destroy()
end

--==================================================
-- CONFIG
--==================================================

local MAX_TRAY = 9
local CHECK_INTERVAL = 0.75

local HIGHLIGHT_NAME =
    "AmuletAuthenticityHighlight"

local Config = {
    Enabled = true
}

local COLORS = {
    Real = Color3.fromRGB(50, 255, 80),
    Fake = Color3.fromRGB(255, 60, 60),
    Unknown = Color3.fromRGB(255, 220, 40)
}

--==================================================
-- CLEAR OLD HIGHLIGHTS
--==================================================

local function clearHighlights()
    for _, obj in ipairs(Plots:GetDescendants()) do
        if obj:IsA("Highlight")
            and obj.Name == HIGHLIGHT_NAME then

            obj:Destroy()
        end
    end
end

clearHighlights()

--==================================================
-- ASSET ID NORMALIZE
--==================================================

local function normalizeAssetId(id)
    if id == nil then
        return ""
    end

    return tostring(id):gsub("%s+", "")
end

--==================================================
-- SURFACE SIGNATURE
--==================================================

local function getMeshSignature(mesh)
    if not mesh
        or not mesh:IsA("MeshPart") then

        return nil
    end

    local surface =
        mesh:FindFirstChildOfClass(
            "SurfaceAppearance"
        )

    local colorMap = ""
    local normalMap = ""
    local roughnessMap = ""
    local metalnessMap = ""

    if surface then
        colorMap =
            normalizeAssetId(
                surface.ColorMap
            )

        normalMap =
            normalizeAssetId(
                surface.NormalMap
            )

        roughnessMap =
            normalizeAssetId(
                surface.RoughnessMap
            )

        metalnessMap =
            normalizeAssetId(
                surface.MetalnessMap
            )
    end

    return table.concat({
        normalizeAssetId(mesh.MeshId),
        colorMap,
        normalMap,
        roughnessMap,
        metalnessMap
    }, "|")
end

--==================================================
-- CACHE
--
-- Signature -> Variant
-- MeshId -> list of Variants
--==================================================

local SignatureCache = {}
local MeshIdCache = {}

local function buildMeshCache()
    table.clear(SignatureCache)
    table.clear(MeshIdCache)

    local count = 0

    for _, obj in ipairs(
        AmuletMeshes:GetDescendants()
    ) do
        if obj:IsA("MeshPart") then
            count += 1

            local signature =
                getMeshSignature(obj)

            if signature then
                SignatureCache[signature] =
                    obj.Name
            end

            local meshId =
                normalizeAssetId(
                    obj.MeshId
                )

            if meshId ~= "" then
                MeshIdCache[meshId] =
                    MeshIdCache[meshId]
                    or {}

                table.insert(
                    MeshIdCache[meshId],
                    obj.Name
                )
            end
        end
    end

    print(
        "[Amulet Checker]",
        "Mesh cache loaded:",
        count
    )
end

buildMeshCache()

--==================================================
-- FIND VARIANT
--
-- 1. Mesh + Surface exact
-- 2. fallback MeshId
--==================================================

local function findVariant(meshPart)
    if not meshPart
        or not meshPart:IsA("MeshPart") then

        return nil, "INVALID"
    end

    -- exact signature
    local signature =
        getMeshSignature(meshPart)

    if signature
        and SignatureCache[signature] then

        return SignatureCache[signature],
            "SIGNATURE"
    end

    -- fallback MeshId
    local meshId =
        normalizeAssetId(
            meshPart.MeshId
        )

    local variants =
        MeshIdCache[meshId]

    if variants
        and #variants == 1 then

        return variants[1],
            "MESH"
    end

    -- ถ้า MeshId ตรงหลาย Variant
    -- แต่ Surface ไม่ตรง ไม่ควรเดา
    if variants
        and #variants > 1 then

        return nil,
            "AMBIGUOUS"
    end

    return nil,
        "UNKNOWN"
end

--==================================================
-- FAKE DETECTION
--
-- หลัก:
-- Model r2 + Variant R2 = REAL
-- Model r2 + Variant R2_F3 = FAKE
-- Model c1 + Variant C1F = FAKE
-- Model c2 + Variant C2S = FAKE
--==================================================

local function normalizeModelName(value)
    if value == nil then
        return ""
    end

    return string.upper(
        tostring(value)
    )
end

local function isFakeVariant(
    model,
    variant
)
    if not model or not variant then
        return nil
    end

    local base =
        normalizeModelName(model)

    local actual =
        normalizeModelName(variant)

    -- exact base model = genuine
    if actual == base then
        return false
    end

    -- explicitly obvious fake formats
    if string.match(
        actual,
        "_F%d+"
    ) then
        return true
    end

    -- เช่น C1F / C2F / C6F
    if string.match(
        actual,
        "^" .. base .. "F%d*$"
    ) then
        return true
    end

    -- เช่น C2S
    -- หาก variant ไม่ตรง base
    -- ให้ถือว่าเป็น variant ดัดแปลง
    return true
end

--==================================================
-- FIND PLAYER PLOT
--==================================================

local OWNER_ID_ATTRIBUTES = {
    "OwnerUserId",
    "UserId",
    "PlayerUserId",
    "OwnerId",
    "PlotOwnerUserId"
}

local OWNER_NAME_ATTRIBUTES = {
    "Owner",
    "OwnerName",
    "PlayerName"
}

local function isMyPlot(plot)

    -- UserId attributes
    for _, attrName in ipairs(
        OWNER_ID_ATTRIBUTES
    ) do
        local value =
            plot:GetAttribute(
                attrName
            )

        if value ~= nil
            and tonumber(value)
                == LocalPlayer.UserId then

            return true
        end
    end

    -- Name attributes
    for _, attrName in ipairs(
        OWNER_NAME_ATTRIBUTES
    ) do
        local value =
            plot:GetAttribute(
                attrName
            )

        if value ~= nil then
            value =
                tostring(value)

            if value
                    == LocalPlayer.Name
                or value
                    == LocalPlayer.DisplayName then

                return true
            end
        end
    end

    -- ObjectValue
    for _, name in ipairs({
        "Owner",
        "Player",
        "PlotOwner"
    }) do
        local obj =
            plot:FindFirstChild(
                name
            )

        if obj
            and obj:IsA(
                "ObjectValue"
            )
            and obj.Value
                == LocalPlayer then

            return true
        end
    end

    return false
end

--==================================================
-- PLOT POSITION
--==================================================

local function getPlotPosition(plot)
    if plot:IsA("Model") then
        local ok, pivot =
            pcall(function()
                return plot:GetPivot()
            end)

        if ok and pivot then
            return pivot.Position
        end
    end

    local part =
        plot:FindFirstChildWhichIsA(
            "BasePart",
            true
        )

    if part then
        return part.Position
    end

    return nil
end

--==================================================
-- FIND MY PLOT
--
-- Owner -> nearest fallback
--==================================================

local function findMyPlot()

    -- Owner detection
    for _, plot in ipairs(
        Plots:GetChildren()
    ) do
        if isMyPlot(plot) then
            return plot, "Owner"
        end
    end

    -- nearest plot
    local character =
        LocalPlayer.Character

    local root =
        character
        and character:FindFirstChild(
            "HumanoidRootPart"
        )

    if not root then
        return nil, "NoCharacter"
    end

    local closestPlot = nil
    local closestDistance =
        math.huge

    for _, plot in ipairs(
        Plots:GetChildren()
    ) do
        local position =
            getPlotPosition(plot)

        if position then
            local distance =
                (
                    root.Position
                    - position
                ).Magnitude

            if distance
                < closestDistance then

                closestDistance =
                    distance

                closestPlot =
                    plot
            end
        end
    end

    if closestPlot then
        return closestPlot,
            "Nearest"
    end

    return nil,
        "NotFound"
end

--==================================================
-- HIGHLIGHT
--==================================================

local function getHighlight(tray)
    local highlight =
        tray:FindFirstChild(
            HIGHLIGHT_NAME
        )

    if highlight
        and highlight:IsA(
            "Highlight"
        ) then

        highlight.Adornee =
            tray

        return highlight
    end

    highlight =
        Instance.new("Highlight")

    highlight.Name =
        HIGHLIGHT_NAME

    highlight.Adornee =
        tray

    highlight.DepthMode =
        Enum.HighlightDepthMode
            .AlwaysOnTop

    highlight.FillTransparency =
        0.55

    highlight.OutlineTransparency =
        0

    highlight.Parent =
        tray

    return highlight
end

local function removeHighlight(tray)
    if not tray then
        return
    end

    local highlight =
        tray:FindFirstChild(
            HIGHLIGHT_NAME
        )

    if highlight then
        highlight:Destroy()
    end
end

local function setHighlightColor(
    highlight,
    color
)
    highlight.FillColor =
        color

    highlight.OutlineColor =
        color
end

--==================================================
-- STATE
--==================================================

local LastResults = {}

local RealCount = 0
local FakeCount = 0
local UnknownCount = 0

local LastPlot = nil

--==================================================
-- UI
--==================================================

local ScreenGui =
    Instance.new("ScreenGui")

ScreenGui.Name =
    "AmuletCheckerUI"

ScreenGui.ResetOnSpawn =
    false

ScreenGui.IgnoreGuiInset =
    true

ScreenGui.Parent =
    PlayerGui

--==================================================
-- MAIN
--==================================================

local Main =
    Instance.new("Frame")

Main.Name =
    "Main"

Main.Size =
    UDim2.fromOffset(
        285,
        205
    )

Main.Position =
    UDim2.new(
        0.5,
        -142,
        0.25,
        0
    )

Main.BackgroundColor3 =
    Color3.fromRGB(
        25,
        25,
        28
    )

Main.BorderSizePixel =
    0

Main.Parent =
    ScreenGui

local MainCorner =
    Instance.new("UICorner")

MainCorner.CornerRadius =
    UDim.new(
        0,
        10
    )

MainCorner.Parent =
    Main

--==================================================
-- TITLE
--==================================================

local Title =
    Instance.new("TextLabel")

Title.Size =
    UDim2.new(
        1,
        -20,
        0,
        35
    )

Title.Position =
    UDim2.fromOffset(
        10,
        4
    )

Title.BackgroundTransparency =
    1

Title.Text =
    "Amulet Checker"

Title.TextColor3 =
    Color3.fromRGB(
        255,
        255,
        255
    )

Title.TextSize =
    17

Title.Font =
    Enum.Font.GothamBold

Title.TextXAlignment =
    Enum.TextXAlignment.Left

Title.Parent =
    Main

--==================================================
-- PLOT STATUS
--==================================================

local Status =
    Instance.new("TextLabel")

Status.Size =
    UDim2.new(
        1,
        -20,
        0,
        24
    )

Status.Position =
    UDim2.fromOffset(
        10,
        39
    )

Status.BackgroundTransparency =
    1

Status.Text =
    "Plot : Searching..."

Status.TextColor3 =
    Color3.fromRGB(
        190,
        190,
        195
    )

Status.TextSize =
    13

Status.Font =
    Enum.Font.Gotham

Status.TextXAlignment =
    Enum.TextXAlignment.Left

Status.Parent =
    Main

--==================================================
-- TOGGLE
--==================================================

local Toggle =
    Instance.new("TextButton")

Toggle.Size =
    UDim2.new(
        1,
        -20,
        0,
        38
    )

Toggle.Position =
    UDim2.fromOffset(
        10,
        69
    )

Toggle.BorderSizePixel =
    0

Toggle.TextSize =
    14

Toggle.Font =
    Enum.Font.GothamBold

Toggle.TextColor3 =
    Color3.fromRGB(
        255,
        255,
        255
    )

Toggle.Parent =
    Main

local ToggleCorner =
    Instance.new("UICorner")

ToggleCorner.CornerRadius =
    UDim.new(
        0,
        7
    )

ToggleCorner.Parent =
    Toggle

--==================================================
-- RESULT
--==================================================

local Result =
    Instance.new("TextLabel")

Result.Size =
    UDim2.new(
        1,
        -20,
        0,
        28
    )

Result.Position =
    UDim2.fromOffset(
        10,
        113
    )

Result.BackgroundTransparency =
    1

Result.Text =
    "แท้ 0 | ปลอม 0 | ? 0"

Result.TextColor3 =
    Color3.fromRGB(
        220,
        220,
        225
    )

Result.TextSize =
    13

Result.Font =
    Enum.Font.Gotham

Result.TextXAlignment =
    Enum.TextXAlignment.Left

Result.Parent =
    Main

--==================================================
-- LEGEND
--==================================================

local Legend =
    Instance.new("TextLabel")

Legend.Size =
    UDim2.new(
        1,
        -20,
        0,
        45
    )

Legend.Position =
    UDim2.fromOffset(
        10,
        145
    )

Legend.BackgroundTransparency =
    1

Legend.Text =
    "เขียว = แท้\nแดง = ปลอม   เหลือง = ไม่ทราบ"

Legend.TextColor3 =
    Color3.fromRGB(
        150,
        150,
        155
    )

Legend.TextSize =
    11

Legend.Font =
    Enum.Font.Gotham

Legend.TextXAlignment =
    Enum.TextXAlignment.Left

Legend.TextYAlignment =
    Enum.TextYAlignment.Top

Legend.Parent =
    Main

--==================================================
-- TOGGLE UI
--==================================================

local function refreshToggleUI()

    if Config.Enabled then
        Toggle.Text =
            "Amulet Check : ON"

        Toggle.BackgroundColor3 =
            Color3.fromRGB(
                35,
                150,
                70
            )
    else
        Toggle.Text =
            "Amulet Check : OFF"

        Toggle.BackgroundColor3 =
            Color3.fromRGB(
                150,
                45,
                45
            )

        Status.Text =
            "Checker : OFF"

        Result.Text =
            "แท้ 0 | ปลอม 0 | ? 0"
    end
end

refreshToggleUI()

--==================================================
-- CHECK ONE TRAY
--==================================================

local function checkTray(
    tray,
    trayIndex
)
    local body =
        tray:FindFirstChild(
            "Body"
        )

    if not body
        or not body:IsA(
            "MeshPart"
        ) then

        removeHighlight(tray)

        LastResults[trayIndex] =
            "EMPTY"

        return
    end

    local model =
        tray:GetAttribute(
            "AmuletModel"
        )

    local variant,
        detectMethod =
        findVariant(body)

    -- UNKNOWN
    if not variant then
        UnknownCount += 1

        local highlight =
            getHighlight(tray)

        setHighlightColor(
            highlight,
            COLORS.Unknown
        )

        local key =
            tostring(model)
            .. "|UNKNOWN|"
            .. tostring(
                detectMethod
            )

        if LastResults[trayIndex]
            ~= key then

            LastResults[trayIndex] =
                key

            print(
                "[Tray"
                    .. trayIndex
                    .. "]",
                "Model =",
                model or "?",
                "| Variant = UNKNOWN",
                "| Detect =",
                detectMethod,
                "| Result = ไม่ทราบ"
            )
        end

        return
    end

    -- REAL / FAKE
    local fake =
        isFakeVariant(
            model,
            variant
        )

    if fake == nil then
        UnknownCount += 1

        local highlight =
            getHighlight(tray)

        setHighlightColor(
            highlight,
            COLORS.Unknown
        )

        return
    end

    local highlight =
        getHighlight(tray)

    local status

    if fake then
        FakeCount += 1

        status =
            "ปลอม"

        setHighlightColor(
            highlight,
            COLORS.Fake
        )
    else
        RealCount += 1

        status =
            "แท้"

        setHighlightColor(
            highlight,
            COLORS.Real
        )
    end

    local key =
        tostring(model)
        .. "|"
        .. tostring(variant)
        .. "|"
        .. status

    if LastResults[trayIndex]
        ~= key then

        LastResults[trayIndex] =
            key

        print(
            "[Tray"
                .. trayIndex
                .. "]",
            "Model =",
            model or "?",
            "| Variant =",
            variant,
            "| Detect =",
            detectMethod,
            "| Result =",
            status
        )
    end
end

--==================================================
-- UPDATE
--==================================================

local function update()

    if not Config.Enabled then
        return
    end

    RealCount = 0
    FakeCount = 0
    UnknownCount = 0

    local plot,
        method =
        findMyPlot()

    if not plot then
        Status.Text =
            "Plot : Not found"

        return
    end

    if LastPlot ~= plot then
        LastPlot = plot

        table.clear(
            LastResults
        )

        print(
            "================================"
        )

        print(
            "[Amulet Checker]",
            "MY PLOT =",
            plot.Name
        )

        print(
            "[Amulet Checker]",
            "Detect =",
            method
        )

        print(
            "================================"
        )
    end

    Status.Text =
        "Plot : "
        .. plot.Name
        .. " ["
        .. method
        .. "]"

    local shopScene =
        plot:FindFirstChild(
            "ShopScene"
        )

    local counter =
        shopScene
        and shopScene:FindFirstChild(
            "Counter"
        )

    if not counter then
        Status.Text =
            "Counter : Not found"

        return
    end

    for i = 1, MAX_TRAY do
        local tray =
            counter:FindFirstChild(
                "Tray" .. i
            )

        if tray then
            checkTray(
                tray,
                i
            )
        else
            LastResults[i] =
                "NO_TRAY"
        end
    end

    Result.Text =
        "แท้ "
        .. RealCount
        .. " | ปลอม "
        .. FakeCount
        .. " | ? "
        .. UnknownCount
end

--==================================================
-- TOGGLE
--==================================================

Toggle.Activated:Connect(
    function()

        Config.Enabled =
            not Config.Enabled

        refreshToggleUI()

        if Config.Enabled then

            table.clear(
                LastResults
            )

            buildMeshCache()

            update()
        else
            clearHighlights()
        end
    end
)

--==================================================
-- DRAG UI
--==================================================

local dragging = false
local dragStart = nil
local startPosition = nil

Title.InputBegan:Connect(
    function(input)

        if input.UserInputType
                == Enum.UserInputType
                    .MouseButton1
            or input.UserInputType
                == Enum.UserInputType
                    .Touch then

            dragging = true

            dragStart =
                input.Position

            startPosition =
                Main.Position
        end
    end
)

UserInputService.InputChanged:Connect(
    function(input)

        if not dragging
            or not dragStart
            or not startPosition then

            return
        end

        if input.UserInputType
                == Enum.UserInputType
                    .MouseMovement
            or input.UserInputType
                == Enum.UserInputType
                    .Touch then

            local delta =
                input.Position
                - dragStart

            Main.Position =
                UDim2.new(
                    startPosition.X.Scale,
                    startPosition.X.Offset
                        + delta.X,

                    startPosition.Y.Scale,
                    startPosition.Y.Offset
                        + delta.Y
                )
        end
    end
)

UserInputService.InputEnded:Connect(
    function(input)

        if input.UserInputType
                == Enum.UserInputType
                    .MouseButton1
            or input.UserInputType
                == Enum.UserInputType
                    .Touch then

            dragging = false
            dragStart = nil
            startPosition = nil
        end
    end
)

--==================================================
-- RIGHT SHIFT
--==================================================

UserInputService.InputBegan:Connect(
    function(input, processed)

        if processed then
            return
        end

        if input.KeyCode
            == Enum.KeyCode.RightShift then

            Main.Visible =
                not Main.Visible
        end
    end
)

--==================================================
-- FIRST RUN
--==================================================

update()

--==================================================
-- MAIN LOOP
--==================================================

task.spawn(function()

    while
        getgenv().AmuletCheckRunning
        and getgenv().AmuletCheckerVersion
            == THIS_VERSION
    do

        if Config.Enabled then

            local ok, err =
                pcall(update)

            if not ok then
                warn(
                    "[Amulet Checker Error]",
                    err
                )
            end
        end

        task.wait(
            CHECK_INTERVAL
        )
    end

    print(
        "[Amulet Checker]",
        "Old instance stopped"
    )
end)

print(
    "[Amulet Checker]",
    "Started | Tray1-Tray9"
)
