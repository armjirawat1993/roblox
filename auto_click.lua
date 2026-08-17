local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local oldGui = playerGui:FindFirstChild("AutoClickGui")
if oldGui then
    oldGui:Destroy()
end

local enabled = false
local clickDelay = 0.01
local pressDuration = 0.01

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoClickGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local toggleButton = Instance.new("TextButton")
toggleButton.Size = UDim2.fromOffset(150, 45)
toggleButton.Position = UDim2.fromOffset(20, 80)
toggleButton.BackgroundColor3 = Color3.fromRGB(40, 170, 80)
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.Text = "Auto Click: OFF [G]"
toggleButton.TextScaled = true
toggleButton.Font = Enum.Font.GothamBold
toggleButton.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = toggleButton

local function updateButton()
    if enabled then
        toggleButton.Text = "Auto Click: ON [G]"
        toggleButton.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
    else
        toggleButton.Text = "Auto Click: OFF [G]"
        toggleButton.BackgroundColor3 = Color3.fromRGB(40, 170, 80)
    end
end

local function toggleAutoClick()
    enabled = not enabled
    updateButton()
end

toggleButton.MouseButton1Click:Connect(toggleAutoClick)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then
        return
    end

    if input.KeyCode == Enum.KeyCode.G then
        toggleAutoClick()
    end
end)

local function autoClick()
    local character = player.Character
    local tool = character and character:FindFirstChildOfClass("Tool")

    -- ใช้งาน Tool ที่กำลังถือ
    if tool then
        tool:Activate()
    end

    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end

    -- หาตำแหน่งกึ่งกลางหน้าจอ
    local viewportSize = camera.ViewportSize
    local centerX = math.floor(viewportSize.X / 2)
    local centerY = math.floor(viewportSize.Y / 2)

    -- กดเมาส์ซ้ายตรงกลางหน้าจอ
    VirtualInputManager:SendMouseButtonEvent(
        centerX,
        centerY,
        0,
        true,
        game,
        0
    )

    task.wait(pressDuration)

    -- ปล่อยเมาส์ซ้ายตรงกลางหน้าจอ
    VirtualInputManager:SendMouseButtonEvent(
        centerX,
        centerY,
        0,
        false,
        game,
        0
    )
end

task.spawn(function()
    while screenGui.Parent do
        if enabled then
            autoClick()
            task.wait(clickDelay)
        else
            task.wait(0.05)
        end
    end
end)
