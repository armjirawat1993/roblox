local P = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local LP = P.LocalPlayer
local GUI = LP:WaitForChild("PlayerGui")
local Plots = workspace:WaitForChild("Plots")
local Meshes = RS:WaitForChild("AmuletMeshes")

local ENV = getgenv()
ENV.AmuletCheckerVersion = (ENV.AmuletCheckerVersion or 0) + 1
local VER = ENV.AmuletCheckerVersion

local Fake = {}
local MeshCache = {}
local VariantInfo = {}
local Last = {}

local Enabled = true
local HL = "AmuletAuthenticityHighlight"

local C = {
	Real = Color3.fromRGB(40,255,90),
	Fake = Color3.fromRGB(255,50,50),
	Unknown = Color3.fromRGB(255,220,40)
}

local function up(v)
	return string.upper(tostring(v or ""))
end

local function id(v)
	return tostring(v or ""):gsub("%s+","")
end

local function count(t)
	local n = 0

	for _ in pairs(t) do
		n += 1
	end

	return n
end

local function sig(m)
	if not m or not m:IsA("MeshPart") then
		return nil
	end

	local s = m:FindFirstChildOfClass("SurfaceAppearance")

	return table.concat({
		id(m.MeshId),
		s and id(s.ColorMap) or "",
		s and id(s.NormalMap) or "",
		s and id(s.RoughnessMap) or "",
		s and id(s.MetalnessMap) or ""
	},"|")
end

--==================================================
-- LOAD FAKE CATALOG
--==================================================

local function loadFake()
	table.clear(Fake)

	local lab = RS:FindFirstChild("AmuletLab")

	if not lab then
		warn("[Amulet] AmuletLab not found")
		return false
	end

	local function add(v)
		if type(v) == "string" then
			Fake[up(v)] = true
		end
	end

	local function scan(t, seen)
		if type(t) ~= "table" then
			return
		end

		seen = seen or {}

		if seen[t] then
			return
		end

		seen[t] = true

		for k, v in pairs(t) do
			local n = type(k) == "string"
				and k:lower()
				or ""

			if n == "fake"
				and type(v) == "string" then

				add(v)
			end

			if (n == "fakes"
				or n == "fakerevisionvariants")
				and type(v) == "table" then

				for a, b in pairs(v) do
					if type(b) == "string" then
						add(b)

					elseif b == true
						and type(a) == "string" then

						add(a)
					end
				end
			end

			if type(v) == "table" then
				scan(v, seen)
			end
		end
	end

	local ok, data = pcall(require, lab)

	if ok then
		scan(data)
	end

	if type(decompile) == "function" then
		local ok2, src = pcall(decompile, lab)

		if ok2 and type(src) == "string" then

			for v in src:gmatch(
				'Fake%s*=%s*"([^"]+)"'
			) do
				add(v)
			end

			for v in src:gmatch(
				'\\"Fake\\"%s*:%s*\\"([^\\"]+)\\"'
			) do
				add(v)
			end
		end
	end

	print(
		"[Amulet] Fake Catalog:",
		count(Fake)
	)

	return count(Fake) > 0
end

--==================================================
-- LOAD MESH CACHE
--==================================================

local function loadMeshes()
	table.clear(MeshCache)
	table.clear(VariantInfo)

	for _, o in ipairs(
		Meshes:GetDescendants()
	) do

		if o:IsA("MeshPart") then
			local n = up(o.Name)
			local mid = id(o.MeshId)

			MeshCache[mid] =
				MeshCache[mid]
				or {}

			table.insert(
				MeshCache[mid],
				n
			)

			VariantInfo[n] = {
				Sig = sig(o)
			}
		end
	end
end

local FakeReady = loadFake()

loadMeshes()

--==================================================
-- FIND VARIANT
--==================================================

local function findVariant(body, model)
	local list =
		MeshCache[
			id(body.MeshId)
		]

	if not list
		or #list == 0 then

		return nil, "NO_MESH"
	end

	if #list == 1 then
		return list[1], "MESH"
	end

	local s = sig(body)
	local match = {}

	for _, v in ipairs(list) do

		if VariantInfo[v]
			and VariantInfo[v].Sig == s then

			table.insert(
				match,
				v
			)
		end
	end

	if #match == 1 then
		return match[1], "SURFACE"
	end

	local base = up(model)

	local real = {}
	local fake = {}

	for _, v in ipairs(list) do

		if Fake[v] then

			table.insert(
				fake,
				v
			)

		else

			table.insert(
				real,
				v
			)
		end
	end

	for _, v in ipairs(real) do
		if v == base then
			return v, "BASE"
		end
	end

	for _, v in ipairs(real) do
		if v == base .. "_F0" then
			return v, "F0"
		end
	end

	if #real == 1 then
		return real[1], "REAL_UNIQUE"
	end

	if #real == 0
		and #fake > 0 then

		return fake[1], "ALL_FAKE"
	end

	return nil, "UNKNOWN"
end

--==================================================
-- HIGHLIGHT
--==================================================

local function setHL(tray, result)
	local h =
		tray:FindFirstChild(HL)

	if not h then

		h = Instance.new("Highlight")
		h.Name = HL
		h.Adornee = tray

		h.DepthMode =
			Enum.HighlightDepthMode.AlwaysOnTop

		h.FillTransparency = 0.55

		h.Parent = tray
	end

	local color

	if result == "แท้" then
		color = C.Real

	elseif result == "ปลอม" then
		color = C.Fake

	else
		color = C.Unknown
	end

	h.FillColor = color
	h.OutlineColor = color
end

local function clearHL()
	for _, o in ipairs(
		Plots:GetDescendants()
	) do

		if o:IsA("Highlight")
			and o.Name == HL then

			o:Destroy()
		end
	end
end

clearHL()

--==================================================
-- REMOVE OLD UI
--==================================================

local oldUI =
	GUI:FindFirstChild(
		"AmuletCheckerUI"
	)

if oldUI then
	oldUI:Destroy()
end

--==================================================
-- UI
--==================================================

local SG =
	Instance.new(
		"ScreenGui"
	)

SG.Name =
	"AmuletCheckerUI"

SG.ResetOnSpawn =
	false

SG.Parent =
	GUI

local Main =
	Instance.new(
		"Frame"
	)

Main.Size =
	UDim2.fromOffset(
		300,
		150
	)

Main.Position =
	UDim2.new(
		0.5,
		-150,
		0.2,
		0
	)

Main.BackgroundColor3 =
	Color3.fromRGB(
		24,
		24,
		28
	)

Main.BorderSizePixel =
	0

Main.Parent =
	SG

local corner =
	Instance.new(
		"UICorner"
	)

corner.CornerRadius =
	UDim.new(
		0,
		10
	)

corner.Parent =
	Main

local Title =
	Instance.new(
		"TextLabel"
	)

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
		5
	)

Title.BackgroundTransparency =
	1

Title.Text =
	"Amulet Checker"

Title.TextColor3 =
	Color3.new(
		1,
		1,
		1
	)

Title.Font =
	Enum.Font.GothamBold

Title.TextSize =
	17

Title.TextXAlignment =
	Enum.TextXAlignment.Left

Title.Active =
	true

Title.Parent =
	Main

local Toggle =
	Instance.new(
		"TextButton"
	)

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
		45
	)

Toggle.BorderSizePixel =
	0

Toggle.TextColor3 =
	Color3.new(
		1,
		1,
		1
	)

Toggle.Font =
	Enum.Font.GothamBold

Toggle.TextSize =
	14

Toggle.Parent =
	Main

local toggleCorner =
	Instance.new(
		"UICorner"
	)

toggleCorner.CornerRadius =
	UDim.new(
		0,
		7
	)

toggleCorner.Parent =
	Toggle

local Result =
	Instance.new(
		"TextLabel"
	)

Result.Size =
	UDim2.new(
		1,
		-20,
		0,
		30
	)

Result.Position =
	UDim2.fromOffset(
		10,
		90
	)

Result.BackgroundTransparency =
	1

Result.TextColor3 =
	Color3.new(
		1,
		1,
		1
	)

Result.Font =
	Enum.Font.Gotham

Result.TextSize =
	13

Result.TextXAlignment =
	Enum.TextXAlignment.Left

Result.Parent =
	Main

local Info =
	Instance.new(
		"TextLabel"
	)

Info.Size =
	UDim2.new(
		1,
		-20,
		0,
		25
	)

Info.Position =
	UDim2.fromOffset(
		10,
		120
	)

Info.BackgroundTransparency =
	1

Info.Text =
	"เขียว=แท้ | แดง=ปลอม | เหลือง=?"

Info.TextColor3 =
	Color3.fromRGB(
		160,
		160,
		165
	)

Info.Font =
	Enum.Font.Gotham

Info.TextSize =
	11

Info.TextXAlignment =
	Enum.TextXAlignment.Left

Info.Parent =
	Main

local function updateToggle()

	Toggle.Text =
		"Amulet Check : "
		.. (
			Enabled
			and "ON"
			or "OFF"
		)

	if Enabled then

		Toggle.BackgroundColor3 =
			Color3.fromRGB(
				35,
				145,
				70
			)

	else

		Toggle.BackgroundColor3 =
			Color3.fromRGB(
				150,
				45,
				45
			)
	end
end

updateToggle()

--==================================================
-- CHECK TRAY
--==================================================

local function checkTray(
	plot,
	tray,
	i
)

	local body =
		tray:FindFirstChild(
			"Body"
		)

	if not body
		or not body:IsA(
			"MeshPart"
		) then

		return nil
	end

	local model =
		tray:GetAttribute(
			"AmuletModel"
		)

	local variant,
		detect =
		findVariant(
			body,
			model
		)

	local result =
		"?"

	if variant
		and FakeReady then

		if Fake[variant] then
			result = "ปลอม"
		else
			result = "แท้"
		end
	end

	setHL(
		tray,
		result
	)

	local key =
		plot.Name
		.. "/Tray"
		.. i

	local state =
		tostring(model)
		.. "|"
		.. tostring(variant)
		.. "|"
		.. result

	if Last[key]
		~= state then

		Last[key] =
			state

		print(
			key,
			"| Model =",
			model or "?",
			"| Variant =",
			variant or "?",
			"| Detect =",
			detect,
			"| Result =",
			result
		)
	end

	return result
end

--==================================================
-- UPDATE
--==================================================

local function update()

	if not Enabled then
		return
	end

	local real =
		0

	local fake =
		0

	local unknown =
		0

	for p = 1, 5 do

		local plot =
			Plots:FindFirstChild(
				"Plot" .. p
			)

		if plot then

			local shop =
				plot:FindFirstChild(
					"ShopScene"
				)

			local counter =
				shop
				and shop:
					FindFirstChild(
						"Counter"
					)

			if counter then

				for t = 1, 9 do

					local tray =
						counter:
							FindFirstChild(
								"Tray"
								.. t
							)

					if tray then

						local r =
							checkTray(
								plot,
								tray,
								t
							)

						if r == "แท้" then

							real += 1

						elseif r == "ปลอม" then

							fake += 1

						elseif r then

							unknown += 1
						end
					end
				end
			end
		end
	end

	Result.Text =
		"แท้ "
		.. real
		.. " | ปลอม "
		.. fake
		.. " | ? "
		.. unknown
end

--==================================================
-- TOGGLE
--==================================================

Toggle.Activated:Connect(function()

	Enabled =
		not Enabled

	updateToggle()

	if Enabled then

		FakeReady =
			loadFake()

		loadMeshes()

		table.clear(
			Last
		)

		update()

	else

		clearHL()
	end
end)

--==================================================
-- DRAG
--==================================================

local drag =
	false

local start =
	nil

local pos =
	nil

Title.InputBegan:Connect(function(i)

	if i.UserInputType
		== Enum.UserInputType.MouseButton1 then

		drag =
			true

		start =
			i.Position

		pos =
			Main.Position
	end
end)

UIS.InputChanged:Connect(function(i)

	if drag
		and i.UserInputType
			== Enum.UserInputType.MouseMovement then

		local d =
			i.Position
			- start

		Main.Position =
			UDim2.new(

				pos.X.Scale,
				pos.X.Offset + d.X,

				pos.Y.Scale,
				pos.Y.Offset + d.Y
			)
	end
end)

UIS.InputEnded:Connect(function(i)

	if i.UserInputType
		== Enum.UserInputType.MouseButton1 then

		drag =
			false
	end
end)

--==================================================
-- RIGHT SHIFT
--==================================================

UIS.InputBegan:Connect(function(i, gp)

	if gp then
		return
	end

	if i.KeyCode
		== Enum.KeyCode.RightShift then

		Main.Visible =
			not Main.Visible
	end
end)

--==================================================
-- START
--==================================================

update()

task.spawn(function()

	while ENV.AmuletCheckerVersion
		== VER do

		pcall(
			update
		)

		task.wait(
			0.75
		)
	end
end)

print(
	"[Amulet Checker] Started"
)
