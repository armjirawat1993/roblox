local Workspace = game:GetService("Workspace")

local boulders = Workspace
	:WaitForChild("MountainDecorations")
	:WaitForChild("Boulders")

local ESP_NAME = "BoulderESP"

local ESP_COLORS = {
	Color3.fromRGB(0, 200, 255),   -- 1 ฟ้า
	Color3.fromRGB(0, 255, 100),   -- 2 เขียว
	Color3.fromRGB(255, 230, 0),   -- 3 เหลือง
	Color3.fromRGB(180, 0, 255),   -- 4 ม่วง
	Color3.fromRGB(0, 80, 255),    -- 5 น้ำเงิน
	Color3.fromRGB(255, 70, 180),  -- 6 ชมพู
}

local nameColorMap = {}
local nextColorIndex = 1

local function getColorByName(objectName)
	-- ชื่อซ้ำใช้สีเดิม ไม่นับลำดับใหม่
	if nameColorMap[objectName] then
		return nameColorMap[objectName]
	end

	local color = ESP_COLORS[nextColorIndex]

	nameColorMap[objectName] = color

	nextColorIndex += 1

	if nextColorIndex > #ESP_COLORS then
		nextColorIndex = 1
	end

	return color
end

local function makeVisible(container)
	if container:IsA("BasePart") then
		container.Transparency = 0
	end

	for _, object in ipairs(container:GetDescendants()) do
		if object:IsA("BasePart") then
			object.Transparency = 0
		end
	end
end

local function addESP(container)
	if not container then
		return
	end

	makeVisible(container)

	local color = getColorByName(container.Name)

	local highlight = container:FindFirstChild(ESP_NAME)

	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name = ESP_NAME
		highlight.Adornee = container
		highlight.FillTransparency = 0.45
		highlight.OutlineTransparency = 0
		highlight.DepthMode =
			Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = container
	end

	highlight.FillColor = color
	highlight.OutlineColor = color
end

-- เรียงชื่อก่อน เพื่อให้ลำดับสีคงที่
local containers = boulders:GetChildren()

table.sort(containers, function(a, b)
	return string.lower(a.Name) < string.lower(b.Name)
end)

for _, container in ipairs(containers) do
	if container:IsA("Model")
		or container:IsA("Folder")
		or container:IsA("BasePart") then

		addESP(container)
	end
end

-- รองรับ Object ที่เพิ่มเข้ามาใหม่
boulders.ChildAdded:Connect(function(container)
	task.wait()

	if container:IsA("Model")
		or container:IsA("Folder")
		or container:IsA("BasePart") then

		addESP(container)
	end
end)
