local Workspace = game:GetService("Workspace")

local function setupPrompt(object)
	if object:IsA("ProximityPrompt") then
		object.HoldDuration = 0
	end
end

for _, object in ipairs(Workspace:GetDescendants()) do
	setupPrompt(object)
end

Workspace.DescendantAdded:Connect(setupPrompt)
