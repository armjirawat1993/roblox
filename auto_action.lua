local UserInputService =
	game:GetService("UserInputService")

local ProximityPromptService =
	game:GetService("ProximityPromptService")

local AUTO_E_INTERVAL = 0.08
local TRIGGER_HOLD_TIME = 0.03

local eHeld = false
local autoEToggled = false
local autoEThread = nil
local visiblePrompts = {}

local function isValidPrompt(prompt)
	return prompt
		and prompt.Parent
		and prompt.Enabled
		and prompt.KeyboardKeyCode == Enum.KeyCode.E
end

local function getActivePrompt()
	for prompt in pairs(visiblePrompts) do
		if isValidPrompt(prompt) then
			return prompt
		else
			visiblePrompts[prompt] = nil
		end
	end

	return nil
end

ProximityPromptService.PromptShown:Connect(function(
	prompt,
	inputType
)
	if prompt.KeyboardKeyCode == Enum.KeyCode.E then
		visiblePrompts[prompt] = true
	end
end)

ProximityPromptService.PromptHidden:Connect(function(prompt)
	visiblePrompts[prompt] = nil
end)

local function activatePrompt(prompt)
	if not isValidPrompt(prompt) then
		return
	end

	prompt:InputHoldBegin()

	local holdTime = math.max(
		prompt.HoldDuration,
		TRIGGER_HOLD_TIME
	)

	task.wait(holdTime)

	if prompt and prompt.Parent then
		prompt:InputHoldEnd()
	end
end

local function shouldAutoERun()
	return eHeld or autoEToggled
end

local function stopAutoEThread()
	if autoEThread then
		task.cancel(autoEThread)
		autoEThread = nil
	end
end

local function updateAutoE()
	if shouldAutoERun() then
		if autoEThread then
			return
		end

		autoEThread = task.spawn(function()
			while shouldAutoERun() do
				local prompt = getActivePrompt()

				if prompt then
					local success, errorMessage = pcall(
						activatePrompt,
						prompt
					)

					if not success then
						warn(
							"Auto E error:",
							errorMessage
						)
					end
				end

				task.wait(AUTO_E_INTERVAL)
			end

			autoEThread = nil
		end)
	else
		stopAutoEThread()
	end
end

UserInputService.InputBegan:Connect(function(
	input,
	gameProcessed
)
	if UserInputService:GetFocusedTextBox() then
		return
	end

	-- กด E ค้าง
	if input.KeyCode == Enum.KeyCode.E then
		eHeld = true
		updateAutoE()
		return
	end

	-- กด R เพื่อเปิดหรือปิด Auto E
	if input.KeyCode == Enum.KeyCode.R then
		-- ป้องกันการสลับหลายครั้งจากการกดค้าง
		if input.UserInputState ~= Enum.UserInputState.Begin then
			return
		end

		autoEToggled = not autoEToggled

		if autoEToggled then
			print("Auto E: ON")
		else
			print("Auto E: OFF")
		end

		updateAutoE()
	end
end)

UserInputService.InputEnded:Connect(function(
	input,
	gameProcessed
)
	if input.KeyCode == Enum.KeyCode.E then
		eHeld = false
		updateAutoE()
	end
end)
