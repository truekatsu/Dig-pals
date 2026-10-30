--!strict
-- Shared visual source plus simple walkable collisions for the imported Merchant.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Asset = require(script.Parent:WaitForChild("MerchantAsset"))
local Builder = {}

local function vec(v: {number}): Vector3
	return Vector3.new(v[1], v[2], v[3])
end

local function anchor(parent: Instance, name: string, position: Vector3): BasePart
	local old = parent:FindFirstChild(name)
	if old and not old:IsA("BasePart") then old:Destroy(); old = nil end
	local part = (old or Instance.new("Part")) :: BasePart
	part.Name = name
	part.Size = Vector3.one
	part.CFrame = CFrame.new(position)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part:SetAttribute("MerchantCompatibilityAnchor", true)
	part.Parent = parent
	return part
end

function Builder.Build(): Model
	local model = Instance.new("Model")
	model.Name = "TheMerchant"
	model:SetAttribute("VisualVersion", Asset.Version)
	model:SetAttribute("MerchantBuilding", true)
	local assets = ReplicatedStorage:FindFirstChild("MerchantAssets")
	local templates = assets and assets:FindFirstChild("MeshTemplates")
	for _, spec in Asset.Parts do
		local template = templates and templates:FindFirstChild(spec.name)
		local part: BasePart
		if template and template:IsA("MeshPart") and template.MeshId == spec.mesh then
			part = template:Clone()
		else
			local fallback = Instance.new("Part")
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.FileMesh
			mesh.MeshId = spec.mesh
			mesh.TextureId = if spec.texture ~= "" then spec.texture else spec.colorMap
			mesh.Scale = vec(spec.size) / vec(spec.native)
			mesh.Parent = fallback
			part = fallback
		end
		part.Name = spec.name
		part.Size = vec(spec.size)
		part.CFrame = Asset.Pivot * CFrame.new(table.unpack(spec.cf))
		part.Color = Color3.new(spec.color[1], spec.color[2], spec.color[3])
		part.Material = Enum.Material[spec.material]
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Parent = model
	end
	local collisions = Instance.new("Folder")
	collisions.Name = "Collisions"
	collisions.Parent = model
	for _, spec in Asset.Colliders do
		local part = Instance.new("Part")
		part.Name = spec.name
		part.Size = vec(spec.size)
		part.CFrame = Asset.Pivot * CFrame.new(vec(spec.pos))
		part.Transparency = 1
		part.Anchored = true
		part.CanCollide = true
		part.CanTouch = false
		part.Parent = collisions
	end
	for _, x in {-22, 22} do
		-- Lamps remain at the original facade height.
		local lamp = anchor(model, "ExteriorLamp" .. x, Asset.Pivot:PointToWorldSpace(Vector3.new(x, 11, 16.5)))
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 230, 181)
		light.Range = 14
		light.Brightness = 1.2
		light.Shadows = true
		light.Parent = lamp
	end
	-- The imported base starts 0.6 studs above this map's ground. Close the
	-- underside with matching stone footings while preserving floors and stairs.
	local supports = Instance.new("Folder")
	supports.Name = "GroundSupports"
	supports.Parent = model
	local stoneTexture = ""
	for _, spec in Asset.Parts do
		if spec.name == "Merchant_Stone" then stoneTexture = spec.texture; break end
	end
	for _, spec in {
		{Name = "FoundationFooting", Size = Vector3.new(48, .6, 32), Offset = Vector3.new(0, -.3, 0)},
		{Name = "CratePedestalFooting", Size = Vector3.new(3.8, .6, 3.8), Offset = Vector3.new(-21.4, -.3, 17)},
	} do
		local part = Instance.new("Part")
		part.Name = spec.Name
		part.Size = spec.Size
		part.CFrame = Asset.Pivot * CFrame.new(spec.Offset)
		part.Anchored = true
		part.CanTouch = false
		part.Material = Enum.Material.Concrete
		part.Color = Color3.fromRGB(145, 145, 145)
		for _, face in {Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right} do
			local texture = Instance.new("Texture")
			texture.Texture = stoneTexture
			texture.Face = face
			texture.StudsPerTileU = 9.6
			texture.StudsPerTileV = .85
			texture.Parent = part
		end
		part.Parent = supports
	end
	model.WorldPivot = Asset.Pivot
	return model
end

function Builder.EnsureForWorld(folder: Instance): Model
	local existing = folder:FindFirstChild("TheMerchant")
	if existing and (not existing:IsA("Model") or existing:GetAttribute("VisualVersion") ~= Asset.Version) then
		existing:Destroy()
		existing = nil
	end
	if folder:GetAttribute("MerchantBuildingVersion") ~= Asset.Version then
		-- Legacy stall pieces are all on the negative-X side. The central plaza,
		-- road underlay, Shovelkeeper building, and its interaction anchor stay.
		for _, child in folder:GetChildren() do
			local legacyPart = child:IsA("BasePart") and child.Position.X < -5
				and (child.Name == "Part" or child.Name == "ItemMerchant_Counter"
					or child.Name == "ItemMerchant_Floor" or child.Name == "MerchantApproach")
			if child.Name == "StallFrame_Left" or child.Name == "StallHeader_SellItem"
				or legacyPart then
				child:Destroy()
			end
		end
	end
	local model: Model
	if existing and existing:IsA("Model") then model = existing else
		model = Builder.Build()
		model.Parent = folder
	end
	anchor(folder, "ItemMerchant_Counter", Asset.Pivot:PointToWorldSpace(Asset.CounterOffset))
	anchor(folder, "ItemMerchant_Floor", Asset.Pivot:PointToWorldSpace(Asset.FloorOffset))
	local approach = folder:FindFirstChild("MerchantApproach")
	if not approach then
		local part = Instance.new("Part")
		part.Name = "MerchantApproach"
		part.Size = Vector3.new(38, .6, 1.5)
		part.CFrame = Asset.Pivot * CFrame.new(0, -.3, 20.45)
		part.Anchored = true
		part.Material = Enum.Material.Cobblestone
		part.Color = Color3.fromRGB(178, 183, 188)
		local plaza = folder:FindFirstChild("PlazaToko")
		if plaza and plaza:IsA("BasePart") then
			part.Material, part.Color = plaza.Material, plaza.Color
			for _, child in plaza:GetChildren() do
				if child:IsA("Texture") then child:Clone().Parent = part end
			end
		end
		part.Parent = folder
	end
	folder:SetAttribute("MerchantBuildingVersion", Asset.Version)
	return model
end

return Builder
