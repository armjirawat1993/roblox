local DisLib 			= loadstring(game:HttpGet "https://raw.githubusercontent.com/blackxs0001s/Roblox/refs/heads/main/discord")()

local Players 			= game:GetService("Players")
local localPlayer 		= Players.LocalPlayer
local ArrPlayerNames 	= {}
for _, player in ipairs(Players:GetPlayers()) do
	table.insert(ArrPlayerNames, player.Name)
end

local UserWalkSpeedO 	= game.Players.LocalPlayer.Character.Humanoid.WalkSpeed
local UserHipHeightO 	= math.round(game.Players.LocalPlayer.Character.Humanoid.HipHeight)
local UserWalkSpeed 	= UserWalkSpeedO
local UserHipHeight 	= UserHipHeightO
if game.Players.LocalPlayer.Character.Humanoid.UseJumpPower then
	UserJumpHeightO = math.round(game.Players.LocalPlayer.Character.Humanoid.JumpPower)
	UserJumpHeight = math.round(game.Players.LocalPlayer.Character.Humanoid.JumpPower)
else
	UserJumpHeightO = math.round(game.Players.LocalPlayer.Character.Humanoid.JumpHeight)
	UserJumpHeight = math.round(game.Players.LocalPlayer.Character.Humanoid.JumpHeight)
end

local win = DisLib:Window("Fish Simulator by Me")

--------------------------------------------------------------------
------------------------------ Menu 1 ------------------------------
--------------------------------------------------------------------
local M1 	= win:Server("Main", "http://www.roblox.com/asset/?id=82639979583836")
--------------------------------------------------------------------
------------------------------- User -------------------------------
--------------------------------------------------------------------
local mUser = M1:Channel("User")
local sldr = mUser:Slider("Speed Walk ( Defalut "..UserWalkSpeedO.." )",0,500,UserWalkSpeedO,
    function(t)
        UserWalkSpeed 	= t
    end
)

local sldr2 = mUser:Slider("Jump Height ( Defalut "..UserJumpHeightO.." )",0,500,UserJumpHeightO,
    function(t)
        UserJumpHeight 	= t
    end
)

local sldr3 = mUser:Slider("HipHeight ( Defalut "..UserHipHeightO.." )",0,500,UserHipHeightO,
    function(t)
        UserHipHeight 	= t
    end
)

mUser:Button("Apply",
    function()
        game.Players.LocalPlayer.Character.Humanoid.WalkSpeed 	= UserWalkSpeed
        game.Players.LocalPlayer.Character.Humanoid.HipHeight 	= UserHipHeight
        game.Players.LocalPlayer.Character.Humanoid.JumpHeight 	= UserJumpHeight
        game.Players.LocalPlayer.Character.Humanoid.JumpPower 	= UserJumpHeight
    end
)

mUser:Button("Reset Default",
    function()
        game.Players.LocalPlayer.Character.Humanoid.WalkSpeed 	= UserWalkSpeedO
        game.Players.LocalPlayer.Character.Humanoid.HipHeight 	= UserHipHeightO
        game.Players.LocalPlayer.Character.Humanoid.JumpHeight 	= UserJumpHeightO
        game.Players.LocalPlayer.Character.Humanoid.JumpPower 	= UserJumpHeightO
		sldr:Change(UserWalkSpeedO)
		sldr2:Change(UserJumpHeightO)
		sldr3:Change(UserHipHeightO)
    end
)

mUser:Seperator()

local drop = mUser:Dropdown( "Teleport to User ",ArrPlayerNames,
    function(uname)
		local character 	= localPlayer.Character or localPlayer.CharacterAdded:Wait()
		local targetPlayer 	= Players:FindFirstChild(uname)
		if targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
			local targetHRP = targetPlayer.Character.HumanoidRootPart
			local myHRP 	= character:WaitForChild("HumanoidRootPart")
			myHRP.CFrame 	= targetHRP.CFrame + Vector3.new(2, 0, 0) -- ย้ายไปข้างๆ เป้าหมายเล็กน้อย
		else
			DisLib:Notification("Notification", "User not found", "Okay!")
		end
    end
)

mUser:Button(
    "Update User",
    function()
	 	drop:Clear()
		local Players 	= game:GetService("Players")
		for _, player in ipairs(Players:GetPlayers()) do
       		drop:Add(player.Name)
		end
    end
)

--------------------------------------------------------------------
----------------------------- END User -----------------------------
--------------------------------------------------------------------

--------------------------------------------------------------------
------------------------------- Fish -------------------------------
--------------------------------------------------------------------

local mFish = M1:Channel("Fish")
local nFish = ""
local nColor = Color3.fromRGB(255, 1, 1)

local modelNames = {
	"MobyWood",
	"BigGreatWhiteShark",
	"NeonGreatWhiteShark",
	"NeonKillerWhale",
	"GreatWhiteShark",
	"KillerWhale",
}
local dropF 	= mFish:Dropdown("Pick Fish ",modelNames,
    function(t)
		if fn_searchModelName(t) == 1 then
			nFish = t
		else
			DisLib:Notification("Notification",t.."not found", "Okay!")
		end
		
    end
)
dropF:Clear()
mFish:Button("Update Fish",
    function()
        dropF:Clear()
        local ArrModels = fn_checkModelsExist(modelNames)
        
        if #ArrModels > 0 then
            for _, name in ipairs(ArrModels) do
                dropF:Add(name)
            end
        else
            DisLib:Notification("Notification", "❌ ไม่พบ Fish", "Okay!")
        end
    end
)

mFish:Colorpicker("Highlight Color",Color3.fromRGB(255, 1, 1),
    function(t)
        nColor	= t
    end
)

mFish:Button("Search",
    function()
	 	if nFish ~= "" then
			fn_HighlightsByModelNames(nFish)
		else	 
			DisLib:Notification("Notification", "❌ Fish not found", "Okay!")
		end
    end
)

mFish:Button("Clear",
    function()
	 	fn_removeHighlightsByModelNames(modelNames)
    end
)


--------------------------------------------------------------------
----------------------------- END Fish -----------------------------
--------------------------------------------------------------------

----------------------------------------------------------------
----------------------------- Boat -----------------------------
----------------------------------------------------------------

local mBoat 			= M1:Channel("Boat")
local UserBoatSpeed 	= 20

local sldr = mBoat:Slider("Speed Boat ",0,500,UserBoatSpeed,
    function(t)
        UserBoatSpeed 	= t
    end
)
mBoat:Button("Apply",
    function()
		local boat = workspace:FindFirstChild(game.Players.LocalPlayer.Name.."'s Boat")
		if boat then
			local controller = boat:FindFirstChild("Controller")
			if controller then
				local seat = controller:FindFirstChildWhichIsA("VehicleSeat")
				if seat then
					seat.MaxSpeed 	= UserBoatSpeed
					seat.TurnSpeed 	= 2
					
				end
			end
		else
			DisLib:Notification("Notification", "❌ Boat not found", "Okay!")
		end
    end
)
----------------------------------------------------------------
--------------------------- END Boat ---------------------------
----------------------------------------------------------------

-------------------------------------------------------------------
----------------------------- Islands -----------------------------
-------------------------------------------------------------------
local mTowe 			= M1:Channel("Islands TP")

mTowe:Button("Port Jackson",
    function()
		fn_teleport(CFrame.new(76.69, 42.00, 51.71))
    end
)
mTowe:Seperator()
mTowe:Button("Monster's Borough Main",
    function()
		fn_teleport(CFrame.new(-3216.83, 42.77, 2731.75))
    end
)

mTowe:Button("Monster's Borough 1",
    function()
		fn_teleport(CFrame.new(-1746.78, 96.74, 1068.57))
    end
)

mTowe:Button("Monster's Borough 2",
    function()
		fn_teleport(CFrame.new(-1164.55, 47.52, 3136.97))
    end
)
mTowe:Seperator()
mTowe:Button("Eruption Island Lv 10",
    function()
		fn_teleport(CFrame.new(2715.40, 46.64, 1534.48))
    end
)
mTowe:Seperator()
mTowe:Button("Shadow Isles Lv 20",
    function()
		
    end
)
mTowe:Seperator()
mTowe:Button("Ancient Shores Lv 30",
    function()
		
    end
)
mTowe:Seperator()
mTowe:Button("Pharaoh's Dunes Lv 40",
    function()
		
    end
)


--------------------------------------------------------------------
--------------------------- Treasure Box ---------------------------
--------------------------------------------------------------------

local mTBox 			= M1:Channel("Treasure Box TP")

mTBox:Label("Port Jackson")
mTBox:Button("Box 1",
    function()
		fn_teleport(CFrame.new(-44.13, 55.31, -133.46))
    end
)

mTBox:Button("Box 2",
    function()
		fn_teleport(CFrame.new(129.15, 70.30, -264.53))
    end
)
mTowe:Seperator()

mTBox:Label("Monsters Borough")
mTBox:Button("Box 1",
    function()
		fn_teleport(CFrame.new(-3338.72, 88.20, 2672.83))
    end
)
mTBox:Button("Box 2",
    function()
		fn_teleport(CFrame.new(-3356.51, 118.58, 2817.70))
    end
)
mTBox:Button("Box 3",
    function()
		fn_teleport(CFrame.new(-883.11, 49.37, 3052.88))
    end
)
mTBox:Button("Box 4",
    function()
		fn_teleport(CFrame.new(-3207.50, 46.84, 2623.74))
    end
)
mTBox:Button("Box 5",
    function()
		fn_teleport(CFrame.new(-3110.15, 41.16, 2911.64))
    end
)
mTowe:Seperator()
mTBox:Label("Eruption Island LV 10")
mTBox:Button("Box 1",
    function()
		fn_teleport(CFrame.new(2782.10, 55.34, 1413.70))
    end
)
mTBox:Button("Box 2 ",
    function()
		fn_teleport(CFrame.new(2912.51, 186.27, 1865.74))
    end
)
mTowe:Seperator()
mTBox:Label("ShadowIsle's LV 20")
mTBox:Button("Box 1",
    function()
		
    end
)
mTBox:Button("Box 2 ",
    function()
		
    end
)
mTBox:Button("Box 3 ",
    function()
		
    end
)
mTowe:Seperator()
mTBox:Label("Ancient Shores LV 40")
mTBox:Button("Box 1",
    function()
		
    end
)
mTBox:Button("Box 2 ",
    function()
		
    end
)
------------------------------------------------------------------------
--------------------------- END Treasure Box ---------------------------
------------------------------------------------------------------------


------------------------------------------------------------------------
---------------------------- Treasure Ship -----------------------------
------------------------------------------------------------------------
local mTSBox 	= M1:Channel("Treasure Ship TP")

local modelSNames = {
	"ShipModel1",
	"ShipModel2",
	"ShipModel3",
	"ShipModel4",
	"ShipModel5",
	"ShipModel6",
}
local dropS 	= mTSBox:Dropdown("Pick Ship ",modelSNames,
    function(t)
		if fn_searchModelName(t) == 1 then
			local PosBox  = fn_searchModelSub(t, "Chest_")
			if PosBox ~= nil then
				fn_teleport(PosBox)
			end
			
		else
			DisLib:Notification("Notification",t.."not found", "Okay!")
		end
		
    end
)
dropS:Clear()
mTSBox:Button("Search Ship",
    function()
        dropS:Clear()
        local ArrModels = fn_checkModelsExist(modelSNames)
        
        if #ArrModels > 0 then
            for _, name in ipairs(ArrModels) do
                dropS:Add(name)
            end
        else
            DisLib:Notification("Notification", "❌ ไม่พบ Ship", "Okay!")
        end
    end
)
mTowe:Seperator()

mTSBox:Button("TP Box",
    function()
        local PosBox = fn_SearchModelInFolder(workspace:FindFirstChild("RandomChests"),"Chest_")
        if PosBox ~= nil then
			fn_teleport(PosBox)
        end
    end
)


----------------------------------------------------------------------------
---------------------------- END Treasure Ship -----------------------------
----------------------------------------------------------------------------

-----------------------------------------------------------------
---------------------------- Effect -----------------------------
-----------------------------------------------------------------
local mEffect 	= M1:Channel("Effect")


mEffect:Button("Clear effect",
    function()
       	local lighting = game:GetService("Lighting")
		-- 🔹 ปิดหมอกแบบธรรมดา
		lighting.FogStart = 100000
		lighting.FogEnd = 100000
		lighting.FogColor = Color3.fromRGB(255, 255, 255)

		-- 🔹 ปิด Atmosphere
		local atmosphere = lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then
			atmosphere.Density = 0
			atmosphere.Haze = 0
		end

		-- 🔹 ลบ Effects ทั้งหมด (Bloom, Blur, SunRays ฯลฯ)
		for _, v in ipairs(lighting:GetChildren()) do
			if v:IsA("PostEffect") then
				v:Destroy()
			end
		end
    end
)


---------------------------------------------------------------------
---------------------------- END Effect -----------------------------
---------------------------------------------------------------------



--------------------------------------------------------------------
------------------------------- TEST -------------------------------
--------------------------------------------------------------------

local mTest = M1:Channel("TEST")


mTest:Button("Update Location", function()
	local character = game.Players.LocalPlayer.Character
	if character and character:FindFirstChild("HumanoidRootPart") then
		local pos 		= character.HumanoidRootPart.Position
		local strPos 	= string.format("CFrame.new(%.2f, %.2f, %.2f)", pos.X, pos.Y, pos.Z)
		if setclipboard then
			setclipboard(strPos)
			DisLib:Notification("Copied!", strPos, "OK")
		else
			DisLib:Notification("Error", "❌ setclipboard ไม่รองรับ", "OK")
		end
	end
end)


mTest:Textbox(
    "Gun power",
    "Type here!",
    true,
    function(t)
        print(t)
    end
)

mTest:Label("This is just a label.")

mTest:Bind(
    "Kill bind",
    Enum.KeyCode.Q,
    function()
        DisLib:ToggleUI()
    end
)




--------------------------------------------------------------------
----------------------------- END Boat -----------------------------
--------------------------------------------------------------------

--------------------------------------------------------------------
---------------------------- END Menu 1 ----------------------------
--------------------------------------------------------------------


----------------------------------------------------------------------
------------------------------ Function ------------------------------
----------------------------------------------------------------------

function fn_teleport(position)
	local player = game.Players.LocalPlayer
	local character = player.Character or player.CharacterAdded:Wait()
	local hrp = character:FindFirstChild("HumanoidRootPart")
	
	if hrp then
		if typeof(position) == "Vector3" then
			hrp.CFrame = CFrame.new(position)
		elseif typeof(position) == "CFrame" then
			hrp.CFrame = position
		else
			return
		end
	else
		DisLib:Notification("❌ Error", "ไม่พบตัวละคร", "OK")
	end
end



function fn_searchModelName(modelName)
	if not modelName or modelName == "" then
		return 0
	end
	local model = workspace:FindFirstChild(modelName, true)
	if model and model:IsA("Model") then
		return 1
	else
		return 0
	end
end

function fn_searchModelSub(parentName, prefix)
	local parentModel = workspace:FindFirstChild(parentName)
	if not parentModel then
		DisLib:Notification("Notification", "❌ ไม่พบโมเดลหลัก:", "Okay!")
		return nil
	end

	for _, obj in ipairs(parentModel:GetChildren()) do
		-- ตรวจชื่อขึ้นต้นด้วย prefix เช่น "Chest_"
		if obj:IsA("Model") and string.sub(obj.Name, 1, #prefix) == prefix then
			-- 🔹 ค้นหา Part เพื่อหาตำแหน่ง
			local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
			if not part then
				DisLib:Notification("Notification", "❌ ไม่มี Part ใน Model:", "Okay!")
				return nil
			end
			-- 🔹 Highlight
			for _, c in ipairs(obj:GetChildren()) do
				if c:IsA("Highlight") then c:Destroy() end
			end
			local hl = Instance.new("Highlight")
			hl.Adornee = obj
			hl.FillColor = Color3.fromRGB(255, 0, 0)
			hl.OutlineColor = Color3.new(1, 1, 1)
			hl.Parent = obj

			-- 🔹 Teleport
			local hrp = game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.CFrame = part.CFrame + Vector3.new(2, 0, 0)
			end

			return CFrame.new(part.Position)
		end
	end

	DisLib:Notification("Notification", "❌ ไม่พบโมเดลรอง:", "Okay!")
	return nil
end


function fn_HighlightsByModelNames(modelName)
	if modelName ~= "" then
		for _, model in ipairs(workspace:GetDescendants()) do
			if model:IsA("Model") and model.Name == modelName then
				-- 🔹 ลบ Highlight เดิมถ้ามี
				for _, child in ipairs(model:GetChildren()) do
					if child:IsA("Highlight") then
						child:Destroy()
					end
				end

				-- 🔹 เพิ่ม Highlight ใหม่
				local highlight = Instance.new("Highlight")
				highlight.Adornee = model
				highlight.FillColor = nColor
				highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
				highlight.Parent = model
			end
		end
	else	 
		DisLib:Notification("Notification", "❌ Fish not found", "Okay!")
	end
end


function fn_SearchModelInFolder(folder, namePrefix)
	if not folder or not folder:IsA("Instance") then
		DisLib:Notification("Notification", "❌ Folder ไม่ถูกต้อง", "Okay!")
		return nil
	end

	for _, obj in ipairs(folder:GetChildren()) do
		if typeof(obj.Name) == "string" and string.sub(obj.Name, 1, #namePrefix) == namePrefix then
			-- ถ้าเป็น BasePart หรืออยู่ใน Model
			local part = nil
			if obj:IsA("BasePart") then
				part = obj
			elseif obj:IsA("Model") then
				part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
			end

			if part then
				for _, c in ipairs(obj:GetChildren()) do
					if c:IsA("Highlight") then c:Destroy() end
				end

				-- 🔹 เพิ่ม Highlight
				local hl = Instance.new("Highlight")
				hl.Adornee = obj
				hl.FillColor = Color3.fromRGB(255, 0, 0)
				hl.OutlineColor = Color3.fromRGB(255, 255, 255)
				hl.Parent = obj
				local offset = Vector3.new(0, 10, 0)
				
				return CFrame.new(part.Position + offset)
			else
				DisLib:Notification("Notification", "⚠️ ไม่มี BasePart", "Okay!")
			end
		end
	end
	DisLib:Notification("Notification", "❌ ไม่พบ "..namePrefix, "Okay!")
	return nil
end




function fn_removeHighlightsByModelNames(nameArray)
	local removedCount = 0

	for _, targetName in ipairs(nameArray) do
		for _, model in ipairs(workspace:GetDescendants()) do
			if model:IsA("Model") and model.Name == targetName then
				for _, child in ipairs(model:GetChildren()) do
					if child:IsA("Highlight") then
						child:Destroy()
						removedCount += 1
					end
				end
			end
		end
	end

	if removedCount == 0 then
		DisLib:Notification("Notification", "❌ Highlight not found", "Okay!")
	else
		DisLib:Notification("Notification", "✅ Clear success", "Okay!")
	end
end

function fn_checkModelsExist(modelNames)
	local foundNames = {}
	local nameSet = {}

	for _, name in ipairs(modelNames) do
		nameSet[name] = true
	end

	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("Model") and nameSet[obj.Name] then
			if not table.find(foundNames, obj.Name) then
				table.insert(foundNames, obj.Name)
			end
		end
	end
	
	return foundNames
end




