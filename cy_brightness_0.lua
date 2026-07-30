local Workspace = game:GetService("Workspace")

local crystalsFolder = Workspace
	:WaitForChild("Things")
	:WaitForChild("Crystals")

while task.wait(0.5) do
	for _, object in ipairs(crystalsFolder:GetDescendants()) do
		if object.Name == "CrystalGlow" then
			-- รองรับ PointLight, SpotLight และ SurfaceLight
			if object:IsA("Light") then
				object.Brightness = 0
			end
		end
	end
end
