--!strict
-- Native Roblox geometry for the Shovelkeeper, with no external textures or accessory dependencies.
local Builder = {}
local VERSION = 1
local COLORS = {
	Suit = Color3.fromRGB(27, 26, 43),
	Vest = Color3.fromRGB(49, 35, 67),
	Pants = Color3.fromRGB(25, 25, 39),
	Black = Color3.fromRGB(16, 16, 24),
	Skin = Color3.fromRGB(166, 111, 79),
	Gold = Color3.fromRGB(239, 191, 65),
	GoldDark = Color3.fromRGB(183, 126, 39),
	Cream = Color3.fromRGB(244, 233, 207),
	Purple = Color3.fromRGB(100, 55, 135),
	Lens = Color3.fromRGB(34, 47, 66),
}

local function segmentFrame(a: Vector3, b: Vector3): CFrame
	local y = (b - a).Unit
	local reference = if math.abs(y:Dot(Vector3.zAxis)) > 0.95 then Vector3.xAxis else Vector3.zAxis
	local x = y:Cross(reference).Unit
	return CFrame.fromMatrix((a + b) * 0.5, x, y, x:Cross(y))
end

function Builder.EnsureForShop(shop: Model): Model
	local previous = shop:FindFirstChild("ShovelkeeperNPC")
	if previous and previous:IsA("Model") and previous:GetAttribute("VisualVersion") == VERSION then return previous end

	local counter = shop:FindFirstChild("Counter_Top") :: BasePart?
	local floor = shop:FindFirstChild("Shop_Floor") :: BasePart?
	assert(counter and floor, "The Shovelkeeper needs its counter and floor")
	local shopPivot = shop:GetPivot()
	local back = shopPivot.RightVector
	local origin = counter.Position + back * (counter.Size.X * 0.5 + 1.1)
	origin = Vector3.new(origin.X, floor.Position.Y + floor.Size.Y * 0.5, origin.Z)
	local placement = CFrame.lookAt(origin, origin - back, shopPivot.UpVector)

	local model = Instance.new("Model")
	model.Name = "ShovelkeeperNPC"
	model:SetAttribute("VisualVersion", VERSION)
	model:SetAttribute("DisplayName", "The Shovelkeeper")

	local function part(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local function block(name: string, size: Vector3, position: Vector3, color: Color3): Part
		return part(name, size, CFrame.new(position), color)
	end
	local function bar(name: string, a: Vector3, b: Vector3, width: number, depth: number, color: Color3): Part
		return part(name, Vector3.new(width, (b - a).Magnitude, depth), segmentFrame(a, b), color)
	end
	local function disc(name: string, cf: CFrame, radius: number, height: number, color: Color3): Part
		local p = part(name, Vector3.new(height, radius * 2, radius * 2), cf * CFrame.Angles(0, 0, math.pi * 0.5), color)
		p.Shape = Enum.PartType.Cylinder
		return p
	end
	-- Two thin wedges form a real triangular face; the crystal stays faceted from every angle.
	local function triangle(name: string, a: Vector3, b: Vector3, c: Vector3, color: Color3, thickness: number)
		local ab, ac, bc = (a-b).Magnitude, (a-c).Magnitude, (b-c).Magnitude
		if ab >= ac and ab >= bc then a, b, c = c, a, b
		elseif ac >= ab and ac >= bc then a, b, c = b, a, c end
		local along = (c - b).Unit
		local foot = b + along * (a - b):Dot(along)
		local altitude = (a - foot).Magnitude
		if altitude < 0.0001 then return end
		local up = (a - foot).Unit
		for i, endpoint in {b, c} do
			local length = (foot - endpoint).Magnitude
			if length < 0.0001 then continue end
			local z = (foot - endpoint).Unit
			local p = Instance.new("WedgePart")
			p.Name = name .. i
			p.Size = Vector3.new(thickness, altitude, length)
			p.CFrame = CFrame.fromMatrix((foot + endpoint) * 0.5 + up * altitude * 0.5, up:Cross(z), up, z)
			p.Color = color
			p.Material = Enum.Material.SmoothPlastic
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.Parent = model
		end
	end

	-- Classic block proportions, with a tailored vest and a pair of solid shoes.
	block("LeftLeg", Vector3.new(1.08, 2.05, 1.06), Vector3.new(-0.61, 1.17, 0), COLORS.Pants)
	block("RightLeg", Vector3.new(1.08, 2.05, 1.06), Vector3.new(0.61, 1.17, 0), COLORS.Pants)
	block("LeftShoe", Vector3.new(1.14, 0.38, 1.34), Vector3.new(-0.61, 0.2, -0.12), COLORS.Black)
	block("RightShoe", Vector3.new(1.14, 0.38, 1.34), Vector3.new(0.61, 0.2, -0.12), COLORS.Black)
	block("Torso", Vector3.new(2.5, 2.2, 1.12), Vector3.new(0, 3.25, 0), COLORS.Suit)
	block("Waistcoat", Vector3.new(1.6, 1.85, 0.12), Vector3.new(0, 3.22, -0.6), COLORS.Vest)
	block("WaistSeam", Vector3.new(2.4, 0.09, 0.06), Vector3.new(0, 2.22, -0.6), COLORS.Black)
	triangle("LeftLapel", Vector3.new(-1.05,4.32,-0.69), Vector3.new(-0.12,4.28,-0.69), Vector3.new(-0.32,3.25,-0.69), COLORS.Gold, 0.045)
	triangle("RightLapel", Vector3.new(1.05,4.32,-0.69), Vector3.new(0.12,4.28,-0.69), Vector3.new(0.32,3.25,-0.69), COLORS.GoldDark, 0.045)
	triangle("LeftCollar", Vector3.new(-0.5,4.4,-0.72), Vector3.new(0,4.16,-0.75), Vector3.new(-0.22,3.99,-0.74), COLORS.Cream, 0.04)
	triangle("RightCollar", Vector3.new(0.5,4.4,-0.72), Vector3.new(0,4.16,-0.75), Vector3.new(0.22,3.99,-0.74), COLORS.Cream, 0.04)
	block("TieKnot", Vector3.new(0.27,0.27,0.12), Vector3.new(0,4.08,-0.77), COLORS.Black)
	bar("Tie", Vector3.new(0,3.92,-0.77), Vector3.new(0,3.32,-0.77), 0.23, 0.1, COLORS.Black)
	for i = 1, 3 do
		local button = block("VestButton"..i, Vector3.new(0.11,0.11,0.08), Vector3.new(0.48,3.65-(i-1)*0.37,-0.72), COLORS.Gold)
		button.Shape = Enum.PartType.Ball
	end

	-- Bent arms present the crystal over the back edge of the shop counter.
	local shoulders = { Vector3.new(-1.5,4.06,0), Vector3.new(1.5,4.06,0) }
	local elbows = { Vector3.new(-1.75,3.22,-0.38), Vector3.new(1.75,3.31,-0.38) }
	local wrists = { Vector3.new(-0.66,3.93,-1.38), Vector3.new(0.66,3.82,-1.43) }
	for i = 1, 2 do
		bar("UpperArm"..i, shoulders[i], elbows[i], 0.92, 0.94, COLORS.Suit)
		local sleeve = bar("Forearm"..i, elbows[i], wrists[i], 0.88, 0.9, COLORS.Suit)
		part("GoldCuff"..i, Vector3.new(0.93,0.14,0.95), sleeve.CFrame * CFrame.new(0,sleeve.Size.Y*0.5-0.16,0), COLORS.Gold)
		block("Hand"..i, Vector3.new(0.68,0.63,0.66), wrists[i] + Vector3.new(if i==1 then 0.08 else -0.08,0,-0.07), COLORS.Skin)
	end

	block("Neck", Vector3.new(0.72,0.3,0.72), Vector3.new(0,4.4,0), COLORS.Skin)
	local head = block("Head", Vector3.new(1.88,1.8,1.7), Vector3.new(0,5.27,0), COLORS.Skin)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Parent = head
	-- Solid framed sunglasses, small highlights, a nose, and a curled moustache.
	for _, side in {-1,1} do
		block("GlassesFrame"..side, Vector3.new(0.79,0.45,0.15), Vector3.new(side*0.42,5.55,-0.84), COLORS.Black)
		block("GlassesLens"..side, Vector3.new(0.61,0.29,0.035), Vector3.new(side*0.42,5.55,-0.928), COLORS.Lens)
		local shine = block("LensGlint"..side, Vector3.new(0.37,0.035,0.015), Vector3.new(side*0.42-0.05,5.63,-0.953), Color3.fromRGB(110,139,165))
		shine.Transparency = 0.28
		block("GlassesArm"..side, Vector3.new(0.09,0.1,0.79), Vector3.new(side*0.9,5.58,-0.47), COLORS.Black)
	end
	block("GlassesBridge", Vector3.new(0.22,0.1,0.12), Vector3.new(0,5.59,-0.91), COLORS.Black)
	block("Nose", Vector3.new(0.24,0.28,0.24), Vector3.new(0,5.22,-0.88), COLORS.Skin)
	local moustache = {Vector3.new(-0.44,4.98,-0.92),Vector3.new(-0.27,5.08,-0.98),Vector3.new(0,4.99,-1.0),Vector3.new(0.27,5.08,-0.98),Vector3.new(0.44,4.98,-0.92)}
	for i = 1, #moustache - 1 do bar("Moustache"..i,moustache[i],moustache[i+1],0.1,0.08,COLORS.Black) end

	-- A tilted top hat echoes the purple awning and the shop's gold trim.
	local hat = CFrame.new(0,6.19,0.03) * CFrame.Angles(math.rad(-4),0,math.rad(9))
	disc("HatBrim", hat, 1.48, 0.15, COLORS.Black)
	disc("HatBrimEdge", hat * CFrame.new(0,-0.025,0), 1.5, 0.06, COLORS.Vest)
	disc("HatCrown", hat * CFrame.new(0,0.66,0), 1.02, 1.18, COLORS.Black)
	disc("HatBand", hat * CFrame.new(0,0.21,0), 1.035, 0.19, COLORS.Purple)
	disc("HatBandGold", hat * CFrame.new(0,0.32,0), 1.043, 0.045, COLORS.Gold)
	part("HatPin", Vector3.new(0.14,0.18,0.07), hat * CFrame.new(0.37,0.21,-0.98), COLORS.Gold)

	local top = Vector3.new(0,4.95,-1.45)
	local bottom = Vector3.new(0,3.45,-1.45)
	local ring = {Vector3.new(-0.58,4.22,-1.45),Vector3.new(0,4.22,-1.86),Vector3.new(0.58,4.22,-1.45),Vector3.new(0,4.22,-1.04)}
	local gemColors = {Color3.fromRGB(24,65,210),Color3.fromRGB(44,116,251),Color3.fromRGB(20,47,155),Color3.fromRGB(65,143,255)}
	for i = 1, 4 do
		local j = i % 4 + 1
		triangle("CrystalUpper"..i,top,ring[i],ring[j],gemColors[i],0.012)
		triangle("CrystalLower"..i,bottom,ring[j],ring[i],gemColors[j]:Lerp(Color3.new(0,0,0),0.1),0.012)
	end
	local gemLightAnchor = block("CrystalLightAnchor", Vector3.new(0.1,0.1,0.1), Vector3.new(0,4.2,-1.65), Color3.new(1,1,1))
	gemLightAnchor.Transparency = 1
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(75,132,255)
	glow.Brightness = 0.45
	glow.Range = 5
	glow.Shadows = false
	glow.Parent = gemLightAnchor
	local fill = block("PortraitFill", Vector3.new(0.1,0.1,0.1), Vector3.new(0,5.7,-2.7), Color3.new(1,1,1))
	fill.Transparency = 1
	local fillLight = Instance.new("PointLight")
	fillLight.Color = Color3.fromRGB(190,209,255)
	fillLight.Brightness = 0.55
	fillLight.Range = 7
	fillLight.Shadows = false
	fillLight.Parent = fill

	local oldHead = shop:FindFirstChild("NPC_Head")
	local oldTag = oldHead and oldHead:FindFirstChild("MerchantNameTag")
	if not oldTag and previous then oldTag = previous:FindFirstChild("MerchantNameTag",true) end
	if oldTag and oldTag:IsA("BillboardGui") then
		local tag = oldTag:Clone()
		tag.Adornee = head
		tag.Size = UDim2.fromOffset(190,42)
		tag.StudsOffset = Vector3.new(0,3.1,0)
		tag.MaxDistance = 45
		tag.AlwaysOnTop = false
		for _, label in tag:GetDescendants() do
			if label:IsA("TextLabel") then
				label.TextScaled = false
				label.TextSize = if label.Name=="SubLabel" then 10 else 13
			end
		end
		tag.Parent = head
	end

	model.WorldPivot = CFrame.identity
	model:PivotTo(placement)
	-- Replace only the previous merchant figure. The desk, building and shop prompt stay in place.
	if previous then previous:Destroy() end
	for _, old in shop:GetChildren() do
		if old.Name:sub(1,4)=="NPC_" then old:Destroy() end
	end
	model.Parent = shop
	return model
end

return Builder
