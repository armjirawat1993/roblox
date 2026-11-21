local P=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")

local LP=P.LocalPlayer
local GUI=LP:WaitForChild("PlayerGui")
local Plots=workspace:WaitForChild("Plots")
local Meshes=RS:WaitForChild("AmuletMeshes")
local E=getgenv()

E.AmuletVer=(E.AmuletVer or 0)+1
local VER=E.AmuletVer

local Fake,Cache,Info,Last={},{},{},{}
local ON=true
local HL="AmuletAuthenticityHighlight"

local COL={
	["แท้"]=Color3.fromRGB(40,255,90),
	["ปลอม"]=Color3.fromRGB(255,50,50),
	["?"]=Color3.fromRGB(255,220,40)
}

local function up(v)return string.upper(tostring(v or ""))end
local function aid(v)return tostring(v or ""):gsub("%s+","")end

local function sig(m)
	local s=m:FindFirstChildOfClass("SurfaceAppearance")
	return table.concat({
		aid(m.MeshId),
		s and aid(s.ColorMap) or "",
		s and aid(s.NormalMap) or "",
		s and aid(s.RoughnessMap) or "",
		s and aid(s.MetalnessMap) or ""
	},"|")
end

local function loadFake()
	table.clear(Fake)
	local lab=RS:FindFirstChild("AmuletLab")
	if not lab then return false end

	local function add(v)
		if type(v)=="string" then Fake[up(v)]=true end
	end

	local function scan(t,seen)
		if type(t)~="table" then return end
		seen=seen or {}
		if seen[t] then return end
		seen[t]=true

		for k,v in pairs(t) do
			local n=type(k)=="string" and k:lower() or ""

			if n=="fake" and type(v)=="string" then add(v) end

			if (n=="fakes" or n=="fakerevisionvariants") and type(v)=="table" then
				for a,b in pairs(v) do
					if type(b)=="string" then add(b)
					elseif b==true and type(a)=="string" then add(a) end
				end
			end

			if type(v)=="table" then scan(v,seen) end
		end
	end

	local ok,t=pcall(require,lab)
	if ok then scan(t) end

	if type(decompile)=="function" then
		local ok2,src=pcall(decompile,lab)
		if ok2 and type(src)=="string" then
			for v in src:gmatch('Fake%s*=%s*"([^"]+)"') do add(v) end
			for v in src:gmatch('\\"Fake\\"%s*:%s*\\"([^\\"]+)\\"') do add(v) end
		end
	end

	return next(Fake)~=nil
end

local function loadMesh()
	table.clear(Cache)
	table.clear(Info)

	for _,o in ipairs(Meshes:GetDescendants()) do
		if o:IsA("MeshPart") then
			local n,m=up(o.Name),aid(o.MeshId)
			Cache[m]=Cache[m] or {}
			table.insert(Cache[m],n)
			Info[n]=sig(o)
		end
	end
end

local Ready=loadFake()
loadMesh()

local function findVariant(body,model)
	local list=Cache[aid(body.MeshId)]
	if not list or #list==0 then return nil,"NO_MESH" end
	if #list==1 then return list[1],"MESH" end

	local s=sig(body)
	local hit={}

	for _,v in ipairs(list) do
		if Info[v]==s then table.insert(hit,v) end
	end

	if #hit==1 then return hit[1],"SURFACE" end

	local base=up(model)
	local real,fake={},{}

	for _,v in ipairs(list) do
		table.insert(Fake[v] and fake or real,v)
	end

	for _,v in ipairs(real) do
		if v==base then return v,"BASE" end
	end

	for _,v in ipairs(real) do
		if v==base.."_F0" then return v,"F0" end
	end

	if #real==1 then return real[1],"REAL" end
	if #real==0 and #fake>0 then return fake[1],"FAKE" end

	return nil,"UNKNOWN"
end

local function clearHL()
	for _,o in ipairs(Plots:GetDescendants()) do
		if o:IsA("Highlight") and o.Name==HL then o:Destroy() end
	end
end

local function setHL(tray,r)
	local h=tray:FindFirstChild(HL)
	if not h then
		h=Instance.new("Highlight")
		h.Name=HL
		h.Adornee=tray
		h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
		h.FillTransparency=.55
		h.Parent=tray
	end
	h.FillColor=COL[r]
	h.OutlineColor=COL[r]
end

clearHL()

local old=GUI:FindFirstChild("AmuletCheckerUI")
if old then old:Destroy() end

local SG=Instance.new("ScreenGui")
SG.Name="AmuletCheckerUI"
SG.ResetOnSpawn=false
SG.Parent=GUI

local Main=Instance.new("Frame")
Main.Size=UDim2.fromOffset(240,105)
Main.Position=UDim2.new(.5,-120,.2,0)
Main.BackgroundColor3=Color3.fromRGB(24,24,28)
Main.BorderSizePixel=0
Main.Parent=SG

local c=Instance.new("UICorner")
c.CornerRadius=UDim.new(0,8)
c.Parent=Main

local Title=Instance.new("TextLabel")
Title.Size=UDim2.new(1,-12,0,26)
Title.Position=UDim2.fromOffset(6,2)
Title.BackgroundTransparency=1
Title.Text="Amulet Checker"
Title.TextColor3=Color3.new(1,1,1)
Title.Font=Enum.Font.GothamBold
Title.TextSize=14
Title.TextXAlignment=Enum.TextXAlignment.Left
Title.Active=true
Title.Parent=Main

local Toggle=Instance.new("TextButton")
Toggle.Size=UDim2.new(1,-12,0,28)
Toggle.Position=UDim2.fromOffset(6,30)
Toggle.BorderSizePixel=0
Toggle.TextColor3=Color3.new(1,1,1)
Toggle.Font=Enum.Font.GothamBold
Toggle.TextSize=12
Toggle.Parent=Main

local tc=Instance.new("UICorner")
tc.CornerRadius=UDim.new(0,6)
tc.Parent=Toggle

local Result=Instance.new("TextLabel")
Result.Size=UDim2.new(1,-12,0,20)
Result.Position=UDim2.fromOffset(6,61)
Result.BackgroundTransparency=1
Result.TextColor3=Color3.new(1,1,1)
Result.Font=Enum.Font.Gotham
Result.TextSize=11
Result.TextXAlignment=Enum.TextXAlignment.Left
Result.Parent=Main

local Legend=Instance.new("TextLabel")
Legend.Size=UDim2.new(1,-12,0,18)
Legend.Position=UDim2.fromOffset(6,82)
Legend.BackgroundTransparency=1
Legend.Text="เขียว=แท้  แดง=ปลอม  เหลือง=?"
Legend.TextColor3=Color3.fromRGB(160,160,165)
Legend.Font=Enum.Font.Gotham
Legend.TextSize=9
Legend.TextXAlignment=Enum.TextXAlignment.Left
Legend.Parent=Main

local function toggleUI()
	Toggle.Text="Checker : "..(ON and "ON" or "OFF")
	Toggle.BackgroundColor3=ON and Color3.fromRGB(35,145,70) or Color3.fromRGB(150,45,45)
end
toggleUI()

local function check(plot,tray,i)
	local body=tray:FindFirstChild("Body")
	if not body or not body:IsA("MeshPart") then return end

	local model=tray:GetAttribute("AmuletModel")
	local v,method=findVariant(body,model)
	local r="?"

	if v and Ready then r=Fake[v] and "ปลอม" or "แท้" end

	setHL(tray,r)

	local key=plot.Name.."/Tray"..i
	local state=tostring(v).."|"..r

	if Last[key]~=state then
		Last[key]=state
		print(key,"Model=",model or "?","Variant=",v or "?","Detect=",method,"Result=",r)
	end

	return r
end

local function update()
	if not ON then return end

	local real,fake,unk=0,0,0

	for p=1,5 do
		local plot=Plots:FindFirstChild("Plot"..p)

		if plot then
			local shop=plot:FindFirstChild("ShopScene")
			local counter=shop and shop:FindFirstChild("Counter")

			if counter then
				for t=1,9 do
					local tray=counter:FindFirstChild("Tray"..t)

					if tray then
						local r=check(plot,tray,t)

						if r=="แท้" then real+=1
						elseif r=="ปลอม" then fake+=1
						elseif r then unk+=1 end
					end
				end
			end
		end
	end

	Result.Text="แท้ "..real.." | ปลอม "..fake.." | ? "..unk
end

Toggle.Activated:Connect(function()
	ON=not ON
	toggleUI()

	if ON then
		Ready=loadFake()
		loadMesh()
		table.clear(Last)
		update()
	else
		clearHL()
	end
end)

local drag,start,pos

Title.InputBegan:Connect(function(i)
	if i.UserInputType==Enum.UserInputType.MouseButton1 then
		drag=true
		start=i.Position
		pos=Main.Position
	end
end)

UIS.InputChanged:Connect(function(i)
	if drag and i.UserInputType==Enum.UserInputType.MouseMovement then
		local d=i.Position-start
		Main.Position=UDim2.new(
			pos.X.Scale,pos.X.Offset+d.X,
			pos.Y.Scale,pos.Y.Offset+d.Y
		)
	end
end)

UIS.InputEnded:Connect(function(i)
	if i.UserInputType==Enum.UserInputType.MouseButton1 then drag=false end
end)

UIS.InputBegan:Connect(function(i,gp)
	if not gp and i.KeyCode==Enum.KeyCode.RightShift then
		Main.Visible=not Main.Visible
	end
end)

update()

task.spawn(function()
	while E.AmuletVer==VER do
		pcall(update)
		task.wait(.75)
	end
end)

print("[Amulet Checker] Started")
