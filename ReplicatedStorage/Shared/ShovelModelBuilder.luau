--!strict
-- Procedural 3D model & gameplay Tool builder for all 7 shovels and the Backpack UI icon.
-- Keeps ViewportFrame preview models strictly separate from gameplay Tools (zero scripts/physics in previews).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = script.Parent
local ShovelsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Shovels"))

local Carry = require(Shared:WaitForChild("Config"):WaitForChild("ShovelCarry"))
local ShovelModelBuilder = {}
type ImportedShovelAsset = {
 Version: string, MeshId: string, ColorMap: string, RoughnessMap: string,
 MetalnessMap: string, Icon: string, Scale: number, Size: Vector3, GripOffsetY: number, GripOffset: Vector3?,
}
local ImportedAssets: {[string]: ImportedShovelAsset} = {
 RustyShovel = require(Shared:WaitForChild("RustyShovelAsset")),
 StoneShovel = require(Shared:WaitForChild("StoneShovelAsset")),
 IronShovel = require(Shared:WaitForChild("IronShovelAsset")),
}

-- Clone the imported MeshPart to retain its PBR maps. The FileMesh path also
-- supports rebuilding from source when Studio templates have not been loaded.
local function createImportedVisual(shovelId: string, anchored: boolean): BasePart
 local asset = ImportedAssets[shovelId]
 local root = ReplicatedStorage:FindFirstChild("ShovelAssets")
 local template = root and root:FindFirstChild(shovelId .. "Mesh")
 local part: BasePart
 if template and template:IsA("MeshPart") then
  part = template:Clone()
 else
  local fallback = Instance.new("Part")
  local mesh = Instance.new("SpecialMesh")
  mesh.MeshType = Enum.MeshType.FileMesh
  mesh.MeshId = asset.MeshId
  mesh.TextureId = asset.ColorMap
  mesh.Scale = Vector3.one * asset.Scale
  mesh.Parent = fallback
  part = fallback
 end
 part.Name = shovelId .. "Visual"
 part.Size = asset.Size
 part.CFrame = CFrame.identity
 part.PivotOffset = CFrame.identity
 part.Color = Color3.new(1, 1, 1)
 part.Material = Enum.Material.SmoothPlastic
 part.Anchored = anchored
 part.CanCollide = false
 part.CanQuery = false
 part.CanTouch = false
 part.Massless = true
 part.CastShadow = false
 return part
end

type PartSpec = {
	Name: string,
	ClassName: string?, -- "Part" | "WedgePart"
	Shape: Enum.PartType?,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3,
	Material: Enum.Material,
	Reflectance: number?,
	Transparency: number?,
}

type ShovelVisualTheme = {
	ShaftColor: Color3,
	ShaftMaterial: Enum.Material,
	GripColor: Color3,
	GripMaterial: Enum.Material,
	CollarColor: Color3,
	CollarMaterial: Enum.Material,
	BladeColor: Color3,
	BladeMaterial: Enum.Material,
	BladeReflectance: number,
	AccentColor: Color3,
	AccentMaterial: Enum.Material,
	BladeWidth: number,
	BladeHeight: number,
	BladeThickness: number,
	WingStyle: "None" | "Riveted" | "StoneBound" | "GoldWings" | "DiamondProngs" | "MossVines" | "CrescentHorns",
}

local THEMES: { [string]: ShovelVisualTheme } = {
	RustyShovel = {
		ShaftColor = Color3.fromRGB(132, 94, 62),
		ShaftMaterial = Enum.Material.Wood,
		GripColor = Color3.fromRGB(138, 78, 54),
		GripMaterial = Enum.Material.CorrodedMetal,
		CollarColor = Color3.fromRGB(125, 72, 50),
		CollarMaterial = Enum.Material.CorrodedMetal,
		BladeColor = Color3.fromRGB(154, 92, 64),
		BladeMaterial = Enum.Material.CorrodedMetal,
		BladeReflectance = 0.02,
		AccentColor = Color3.fromRGB(98, 64, 46),
		AccentMaterial = Enum.Material.Metal,
		BladeWidth = 1.12,
		BladeHeight = 1.25,
		BladeThickness = 0.14,
		WingStyle = "None",
	},
	StoneShovel = {
		ShaftColor = Color3.fromRGB(186, 146, 102),
		ShaftMaterial = Enum.Material.Wood,
		GripColor = Color3.fromRGB(112, 78, 52),
		GripMaterial = Enum.Material.SmoothPlastic,
		CollarColor = Color3.fromRGB(92, 64, 44),
		CollarMaterial = Enum.Material.Fabric,
		BladeColor = Color3.fromRGB(134, 142, 150),
		BladeMaterial = Enum.Material.Slate,
		BladeReflectance = 0.0,
		AccentColor = Color3.fromRGB(102, 196, 114),
		AccentMaterial = Enum.Material.SmoothPlastic,
		BladeWidth = 1.26,
		BladeHeight = 1.32,
		BladeThickness = 0.22,
		WingStyle = "StoneBound",
	},
	IronShovel = {
		ShaftColor = Color3.fromRGB(96, 68, 48),
		ShaftMaterial = Enum.Material.Wood,
		GripColor = Color3.fromRGB(188, 198, 212),
		GripMaterial = Enum.Material.Metal,
		CollarColor = Color3.fromRGB(165, 176, 192),
		CollarMaterial = Enum.Material.Metal,
		BladeColor = Color3.fromRGB(206, 216, 228),
		BladeMaterial = Enum.Material.Metal,
		BladeReflectance = 0.22,
		AccentColor = Color3.fromRGB(78, 162, 245),
		AccentMaterial = Enum.Material.SmoothPlastic,
		BladeWidth = 1.18,
		BladeHeight = 1.38,
		BladeThickness = 0.15,
		WingStyle = "Riveted",
	},
	GoldenShovel = {
		ShaftColor = Color3.fromRGB(138, 34, 46),
		ShaftMaterial = Enum.Material.SmoothPlastic,
		GripColor = Color3.fromRGB(246, 196, 54),
		GripMaterial = Enum.Material.Metal,
		CollarColor = Color3.fromRGB(252, 208, 72),
		CollarMaterial = Enum.Material.Metal,
		BladeColor = Color3.fromRGB(248, 198, 52),
		BladeMaterial = Enum.Material.Metal,
		BladeReflectance = 0.32,
		AccentColor = Color3.fromRGB(245, 58, 88),
		AccentMaterial = Enum.Material.Neon,
		BladeWidth = 1.28,
		BladeHeight = 1.42,
		BladeThickness = 0.16,
		WingStyle = "GoldWings",
	},
	DiamondShovel = {
		ShaftColor = Color3.fromRGB(52, 64, 88),
		ShaftMaterial = Enum.Material.Metal,
		GripColor = Color3.fromRGB(82, 224, 255),
		GripMaterial = Enum.Material.Glass,
		CollarColor = Color3.fromRGB(190, 238, 255),
		CollarMaterial = Enum.Material.Metal,
		BladeColor = Color3.fromRGB(74, 218, 255),
		BladeMaterial = Enum.Material.Ice,
		BladeReflectance = 0.28,
		AccentColor = Color3.fromRGB(145, 248, 255),
		AccentMaterial = Enum.Material.Neon,
		BladeWidth = 1.32,
		BladeHeight = 1.48,
		BladeThickness = 0.18,
		WingStyle = "DiamondProngs",
	},
	MossyShovel = {
		ShaftColor = Color3.fromRGB(104, 76, 48),
		ShaftMaterial = Enum.Material.Wood,
		GripColor = Color3.fromRGB(82, 168, 88),
		GripMaterial = Enum.Material.LeafyGrass,
		CollarColor = Color3.fromRGB(92, 182, 98),
		CollarMaterial = Enum.Material.LeafyGrass,
		BladeColor = Color3.fromRGB(116, 152, 126),
		BladeMaterial = Enum.Material.Slate,
		BladeReflectance = 0.05,
		AccentColor = Color3.fromRGB(68, 238, 138),
		AccentMaterial = Enum.Material.Neon,
		BladeWidth = 1.26,
		BladeHeight = 1.40,
		BladeThickness = 0.18,
		WingStyle = "MossVines",
	},
	MoonlitShovel = {
		ShaftColor = Color3.fromRGB(44, 48, 92),
		ShaftMaterial = Enum.Material.Metal,
		GripColor = Color3.fromRGB(198, 210, 255),
		GripMaterial = Enum.Material.Metal,
		CollarColor = Color3.fromRGB(162, 146, 255),
		CollarMaterial = Enum.Material.Metal,
		BladeColor = Color3.fromRGB(212, 222, 255),
		BladeMaterial = Enum.Material.Glass,
		BladeReflectance = 0.30,
		AccentColor = Color3.fromRGB(178, 145, 255),
		AccentMaterial = Enum.Material.Neon,
		BladeWidth = 1.34,
		BladeHeight = 1.50,
		BladeThickness = 0.17,
		WingStyle = "CrescentHorns",
	},
}

local function buildShovelPartSpecs(shovelId: string): { PartSpec }
	local theme = THEMES[shovelId] or THEMES.RustyShovel
	local specs: { PartSpec } = {}

	-- 1. Main central shaft (Handle) along Y axis
	table.insert(specs, {
		Name = "Handle",
		Size = Vector3.new(0.20, 2.25, 0.20),
		CFrame = CFrame.new(0, 0.38, 0),
		Color = theme.ShaftColor,
		Material = theme.ShaftMaterial,
		Reflectance = 0.04,
	})

	-- 2. D-Grip at top (Y ~ +1.50 .. +1.88)
	table.insert(specs, {
		Name = "GripBase",
		Size = Vector3.new(0.68, 0.16, 0.22),
		CFrame = CFrame.new(0, 1.52, 0),
		Color = theme.GripColor,
		Material = theme.GripMaterial,
		Reflectance = 0.1,
	})
	table.insert(specs, {
		Name = "GripPostL",
		Size = Vector3.new(0.14, 0.36, 0.20),
		CFrame = CFrame.new(-0.27, 1.70, 0),
		Color = theme.GripColor,
		Material = theme.GripMaterial,
	})
	table.insert(specs, {
		Name = "GripPostR",
		Size = Vector3.new(0.14, 0.36, 0.20),
		CFrame = CFrame.new(0.27, 1.70, 0),
		Color = theme.GripColor,
		Material = theme.GripMaterial,
	})
	table.insert(specs, {
		Name = "GripBar",
		Size = Vector3.new(0.72, 0.16, 0.22),
		CFrame = CFrame.new(0, 1.88, 0),
		Color = theme.GripColor,
		Material = theme.GripMaterial,
		Reflectance = 0.12,
	})

	-- 3. Socket collar between shaft and blade (Y ~ -0.68)
	table.insert(specs, {
		Name = "Collar",
		Size = Vector3.new(0.36, 0.34, 0.28),
		CFrame = CFrame.new(0, -0.68, 0),
		Color = theme.CollarColor,
		Material = theme.CollarMaterial,
		Reflectance = 0.15,
	})

	-- 4. Upper spade body + central spine + pointed tip wedges (Y ~ -0.82 .. -1.95)
	local bw = theme.BladeWidth
	local bh = theme.BladeHeight
	local bt = theme.BladeThickness
	local upperH = bh * 0.62
	local tipH = bh * 0.38
	local upperCenterY = -0.78 - (upperH * 0.5)
	local tipCenterY = -0.78 - upperH - (tipH * 0.5)

	table.insert(specs, {
		Name = "BladeBody",
		Size = Vector3.new(bw, upperH, bt),
		CFrame = CFrame.new(0, upperCenterY, 0),
		Color = theme.BladeColor,
		Material = theme.BladeMaterial,
		Reflectance = theme.BladeReflectance,
	})

	-- Shoulder step lip at top of blade
	table.insert(specs, {
		Name = "BladeShoulder",
		Size = Vector3.new(bw + 0.08, 0.14, bt + 0.06),
		CFrame = CFrame.new(0, -0.80, 0),
		Color = theme.CollarColor,
		Material = theme.CollarMaterial,
		Reflectance = theme.BladeReflectance,
	})

	-- Central reinforcing spine ridge
	table.insert(specs, {
		Name = "BladeSpine",
		Size = Vector3.new(0.22, upperH * 0.85, bt + 0.08),
		CFrame = CFrame.new(0, upperCenterY + 0.05, 0),
		Color = theme.CollarColor,
		Material = theme.CollarMaterial,
		Reflectance = theme.BladeReflectance,
	})

	-- Pointed V-tip using two symmetrical WedgeParts
	-- WedgePart sloped face connects +Y/-Z; rotating around Z/X forms clean spade point
	table.insert(specs, {
		Name = "BladeTipLeft",
		ClassName = "WedgePart",
		Size = Vector3.new(bt, tipH, bw * 0.5),
		CFrame = CFrame.new(-bw * 0.25, tipCenterY, 0) * CFrame.Angles(0, math.rad(90), math.rad(180)),
		Color = theme.BladeColor,
		Material = theme.BladeMaterial,
		Reflectance = theme.BladeReflectance,
	})
	table.insert(specs, {
		Name = "BladeTipRight",
		ClassName = "WedgePart",
		Size = Vector3.new(bt, tipH, bw * 0.5),
		CFrame = CFrame.new(bw * 0.25, tipCenterY, 0) * CFrame.Angles(0, math.rad(-90), math.rad(180)),
		Color = theme.BladeColor,
		Material = theme.BladeMaterial,
		Reflectance = theme.BladeReflectance,
	})

	-- 5. Bespoke silhouette details per shovel tier
	if theme.WingStyle == "StoneBound" then
		table.insert(specs, {
			Name = "LeatherWrap1",
			Size = Vector3.new(0.28, 0.14, 0.28),
			CFrame = CFrame.new(0, 0.15, 0),
			Color = theme.CollarColor,
			Material = Enum.Material.Fabric,
		})
		table.insert(specs, {
			Name = "StoneChiselEdge",
			Size = Vector3.new(bw * 0.86, 0.14, bt + 0.05),
			CFrame = CFrame.new(0, upperCenterY - 0.18, 0),
			Color = Color3.fromRGB(168, 176, 184),
			Material = Enum.Material.Slate,
		})
	elseif theme.WingStyle == "Riveted" then
		table.insert(specs, {
			Name = "SteelGuard",
			Size = Vector3.new(bw + 0.24, 0.14, 0.28),
			CFrame = CFrame.new(0, -0.72, 0),
			Color = theme.GripColor,
			Material = Enum.Material.Metal,
			Reflectance = 0.25,
		})
		table.insert(specs, {
			Name = "CoreBadge",
			Size = Vector3.new(0.24, 0.24, bt + 0.12),
			CFrame = CFrame.new(0, -0.96, 0) * CFrame.Angles(0, 0, math.rad(45)),
			Color = theme.AccentColor,
			Material = theme.AccentMaterial,
		})
	elseif theme.WingStyle == "GoldWings" then
		table.insert(specs, {
			Name = "GoldWingL",
			Size = Vector3.new(0.48, 0.18, 0.24),
			CFrame = CFrame.new(-0.56, -0.68, 0) * CFrame.Angles(0, 0, math.rad(24)),
			Color = theme.CollarColor,
			Material = Enum.Material.Metal,
			Reflectance = 0.35,
		})
		table.insert(specs, {
			Name = "GoldWingR",
			Size = Vector3.new(0.48, 0.18, 0.24),
			CFrame = CFrame.new(0.56, -0.68, 0) * CFrame.Angles(0, 0, math.rad(-24)),
			Color = theme.CollarColor,
			Material = Enum.Material.Metal,
			Reflectance = 0.35,
		})
		table.insert(specs, {
			Name = "RubyCore",
			Size = Vector3.new(0.28, 0.28, bt + 0.14),
			CFrame = CFrame.new(0, -0.95, 0) * CFrame.Angles(0, 0, math.rad(45)),
			Color = theme.AccentColor,
			Material = Enum.Material.Neon,
		})
	elseif theme.WingStyle == "DiamondProngs" then
		table.insert(specs, {
			Name = "CrystalProngL",
			Size = Vector3.new(0.18, 0.62, 0.20),
			CFrame = CFrame.new(-0.66, -0.62, 0) * CFrame.Angles(0, 0, math.rad(32)),
			Color = theme.AccentColor,
			Material = Enum.Material.Neon,
		})
		table.insert(specs, {
			Name = "CrystalProngR",
			Size = Vector3.new(0.18, 0.62, 0.20),
			CFrame = CFrame.new(0.66, -0.62, 0) * CFrame.Angles(0, 0, math.rad(-32)),
			Color = theme.AccentColor,
			Material = Enum.Material.Neon,
		})
		table.insert(specs, {
			Name = "DiamondCore",
			Size = Vector3.new(0.32, 0.44, bt + 0.14),
			CFrame = CFrame.new(0, -1.05, 0) * CFrame.Angles(0, 0, math.rad(45)),
			Color = theme.AccentColor,
			Material = Enum.Material.Neon,
		})
	elseif theme.WingStyle == "MossVines" then
		table.insert(specs, {
			Name = "VineBand1",
			Size = Vector3.new(0.30, 0.18, 0.30),
			CFrame = CFrame.new(0, 0.55, 0) * CFrame.Angles(0, 0, math.rad(14)),
			Color = theme.GripColor,
			Material = Enum.Material.LeafyGrass,
		})
		table.insert(specs, {
			Name = "VineBand2",
			Size = Vector3.new(0.32, 0.20, 0.30),
			CFrame = CFrame.new(0, -0.18, 0) * CFrame.Angles(0, 0, math.rad(-16)),
			Color = theme.GripColor,
			Material = Enum.Material.LeafyGrass,
		})
		table.insert(specs, {
			Name = "EmeraldRune",
			Size = Vector3.new(0.28, 0.36, bt + 0.14),
			CFrame = CFrame.new(0, -1.02, 0) * CFrame.Angles(0, 0, math.rad(45)),
			Color = theme.AccentColor,
			Material = Enum.Material.Neon,
		})
	elseif theme.WingStyle == "CrescentHorns" then
		table.insert(specs, {
			Name = "MoonHornL",
			Size = Vector3.new(0.20, 0.68, 0.20),
			CFrame = CFrame.new(-0.68, -0.52, 0) * CFrame.Angles(0, 0, math.rad(42)),
			Color = theme.AccentColor,
			Material = Enum.Material.Neon,
		})
		table.insert(specs, {
			Name = "MoonHornR",
			Size = Vector3.new(0.20, 0.68, 0.20),
			CFrame = CFrame.new(0.68, -0.52, 0) * CFrame.Angles(0, 0, math.rad(-42)),
			Color = theme.AccentColor,
			Material = Enum.Material.Neon,
		})
		table.insert(specs, {
			Name = "StarlightCore",
			Size = Vector3.new(0.34, 0.34, bt + 0.15),
			CFrame = CFrame.new(0, -1.0, 0) * CFrame.Angles(0, 0, math.rad(45)),
			Color = Color3.fromRGB(235, 225, 255),
			Material = Enum.Material.Neon,
		})
	end

	return specs
end

local function instantiateSpecPart(spec: PartSpec, anchored: boolean): BasePart
	local className = spec.ClassName or "Part"
	local part = Instance.new(className) :: BasePart
	part.Name = spec.Name
	if part:IsA("Part") and spec.Shape then
		part.Shape = spec.Shape
	end
	part.Size = spec.Size
	part.CFrame = spec.CFrame
	part.Color = spec.Color
	part.Material = spec.Material
	part.Reflectance = spec.Reflectance or 0
	part.Transparency = spec.Transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = anchored
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	return part
end

function ShovelModelBuilder.BuildPreviewModel(shovelId: string): Model
	local model = Instance.new("Model")
	model.Name = shovelId
	model:SetAttribute("ShovelId", shovelId)

	local asset = ImportedAssets[shovelId]
 if asset then
  local visual = createImportedVisual(shovelId, true)
  visual.Parent = model
  model.PrimaryPart = visual
  model:SetAttribute("VisualVersion", asset.Version)
  return model
 end

 local specs = buildShovelPartSpecs(shovelId)
	local handlePart: BasePart? = nil
	for _, spec in specs do
		local part = instantiateSpecPart(spec, true)
		part.Parent = model
		if spec.Name == "Handle" then
			handlePart = part
		end
	end
	if handlePart then
		model.PrimaryPart = handlePart
	end
	return model
end

function ShovelModelBuilder.BuildBagPreviewModel(): Model
	local model = Instance.new("Model")
	model.Name = "BagPreview"

	local bagSpecs: { PartSpec } = {
		-- Main leather backpack body
		{
			Name = "BagBody",
			Size = Vector3.new(1.85, 1.95, 1.05),
			CFrame = CFrame.new(0, -0.22, 0),
			Color = Color3.fromRGB(164, 106, 62),
			Material = Enum.Material.SmoothPlastic,
		},
		-- Top leather flap
		{
			Name = "BagFlap",
			Size = Vector3.new(1.94, 0.62, 1.14),
			CFrame = CFrame.new(0, 0.56, 0.02),
			Color = Color3.fromRGB(118, 72, 42),
			Material = Enum.Material.SmoothPlastic,
		},
		-- Front pocket
		{
			Name = "FrontPocket",
			Size = Vector3.new(1.32, 0.88, 0.32),
			CFrame = CFrame.new(0, -0.46, 0.58),
			Color = Color3.fromRGB(138, 86, 48),
			Material = Enum.Material.SmoothPlastic,
		},
		-- Left & Right straps
		{
			Name = "StrapL",
			Size = Vector3.new(0.20, 1.45, 0.16),
			CFrame = CFrame.new(-0.52, 0.05, 0.56),
			Color = Color3.fromRGB(86, 52, 32),
			Material = Enum.Material.SmoothPlastic,
		},
		{
			Name = "StrapR",
			Size = Vector3.new(0.20, 1.45, 0.16),
			CFrame = CFrame.new(0.52, 0.05, 0.56),
			Color = Color3.fromRGB(86, 52, 32),
			Material = Enum.Material.SmoothPlastic,
		},
		-- Gold center buckle
		{
			Name = "GoldBuckle",
			Size = Vector3.new(0.42, 0.34, 0.20),
			CFrame = CFrame.new(0, 0.26, 0.62),
			Color = Color3.fromRGB(248, 202, 64),
			Material = Enum.Material.Metal,
			Reflectance = 0.25,
		},
		-- Mini shovel silhouette peeking diagonally out of the top of the bag!
		{
			Name = "MiniShovelShaft",
			Size = Vector3.new(0.18, 1.45, 0.18),
			CFrame = CFrame.new(0.48, 1.05, -0.10) * CFrame.Angles(0, 0, math.rad(-26)),
			Color = Color3.fromRGB(214, 174, 124),
			Material = Enum.Material.Wood,
		},
		{
			Name = "MiniShovelHead",
			Size = Vector3.new(0.68, 0.72, 0.14),
			CFrame = CFrame.new(0.76, 1.62, -0.10) * CFrame.Angles(0, 0, math.rad(-26)),
			Color = Color3.fromRGB(245, 202, 68),
			Material = Enum.Material.Metal,
			Reflectance = 0.28,
		},
	}

	local primary: BasePart? = nil
	for _, spec in bagSpecs do
		local p = instantiateSpecPart(spec, true)
		p.Parent = model
		if spec.Name == "BagBody" then
			primary = p
		end
	end
	if primary then
		model.PrimaryPart = primary
	end
	return model
end

-- Normalize every model to the common character proportion, around its hand hold.
local function applyCarryDefaults(tool: Tool): Tool
 if tool:GetAttribute("CarryVersion") == Carry.Version then return tool end
 local handle = tool:FindFirstChild("Handle") :: BasePart
 local bounds = Instance.new("Model")
 for _, child in tool:GetChildren() do child.Parent = bounds end
 local height = bounds:GetExtentsSize().Y
 local factor = Carry.Height / math.max(height, 0.01)
 local origin = handle.CFrame
 -- Remove/recreate welds after scaling to avoid stale relative offsets.
 for _, child in bounds:GetDescendants() do
  if child:IsA("WeldConstraint") then child:Destroy() end
 end
 for _, part in bounds:GetDescendants() do
  if part:IsA("BasePart") then
   local relative = origin:ToObjectSpace(part.CFrame)
   part.Size *= factor
   part.CFrame = CFrame.new(relative.Position * factor) * relative.Rotation
   for _, mesh in part:GetChildren() do
    if mesh:IsA("SpecialMesh") and mesh.MeshType == Enum.MeshType.FileMesh then mesh.Scale *= factor end
   end
  end
 end
 for _, child in bounds:GetChildren() do child.Parent = tool end
 bounds:Destroy()
 for _, part in tool:GetDescendants() do
  if part:IsA("BasePart") and part ~= handle then
   local weld = Instance.new("WeldConstraint")
   weld.Part0 = handle
   weld.Part1 = part
   weld.Parent = part
  end
 end
 tool.Grip = Carry.IdleGrip
 tool:SetAttribute("CarryVersion", Carry.Version)
 return tool
end

function ShovelModelBuilder.BuildGameplayTool(shovelId: string): Tool
	local cfg = ShovelsConfig.All[shovelId] or ShovelsConfig.All.RustyShovel
	local tool = Instance.new("Tool")
	tool.Name = cfg.ToolName
	tool.ToolTip = cfg.DisplayName
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ManualActivationOnly = false
	tool:SetAttribute("DigPalsShovelTool", true)
	tool:SetAttribute("ShovelId", shovelId)
	-- Shared diagonal carry and swing origin for every shovel
	tool.Grip = Carry.IdleGrip

 tool.TextureId = cfg.Icon
 local asset = ImportedAssets[shovelId]
 if asset then
  tool.TextureId = asset.Icon
  local handle = Instance.new("Part")
  handle.Name = "Handle"
  handle.Size = Vector3.new(0.18, 0.5, 0.18)
  handle.Transparency = 1
  handle.CanCollide = false
  handle.CanQuery = false
  handle.CanTouch = false
  handle.Massless = true
  handle.Parent = tool
  local visual = createImportedVisual(shovelId, false)
  visual.CFrame = CFrame.new(asset.GripOffset or Vector3.new(0, asset.GripOffsetY, 0))
  visual.Parent = tool
  local weld = Instance.new("WeldConstraint")
  weld.Part0 = handle
  weld.Part1 = visual
  weld.Parent = visual
  tool:SetAttribute("VisualVersion", asset.Version)
  return applyCarryDefaults(tool)
 end

 local specs = buildShovelPartSpecs(shovelId)
	local handlePart: BasePart? = nil
	local otherParts: { BasePart } = {}

	for _, spec in specs do
		local part = instantiateSpecPart(spec, false)
		part.Parent = tool
		if spec.Name == "Handle" then
			handlePart = part
		else
			table.insert(otherParts, part)
		end
	end

	if handlePart then
		for _, other in otherParts do
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handlePart
			weld.Part1 = other
			weld.Parent = other
		end
	end

	return applyCarryDefaults(tool)
end

local function ensureChildFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

function ShovelModelBuilder.EnsureAssets(): Folder
	local root = ensureChildFolder(ReplicatedStorage, "ShovelAssets")
	local previewsFolder = ensureChildFolder(root, "ShovelPreviews")
	local uiPreviewsFolder = ensureChildFolder(root, "UIPreviews")
	local toolsFolder = ensureChildFolder(root, "ShovelTools")

 for _, folder in { previewsFolder, toolsFolder } do
  for id, asset in ImportedAssets do
   local old = folder:FindFirstChild(id)
   if old and old:GetAttribute("VisualVersion") ~= asset.Version then
    old:Destroy()
   end
  end
 end

	for _, shovelId in ShovelsConfig.AllOrder do
		if not previewsFolder:FindFirstChild(shovelId) then
			local preview = ShovelModelBuilder.BuildPreviewModel(shovelId)
			preview.Parent = previewsFolder
		end
		local oldTool = toolsFolder:FindFirstChild(shovelId)
  if oldTool and oldTool:GetAttribute("CarryVersion") ~= Carry.Version then oldTool:Destroy() end
  if not toolsFolder:FindFirstChild(shovelId) then
			local tool = ShovelModelBuilder.BuildGameplayTool(shovelId)
			tool.Name = shovelId
			tool.Parent = toolsFolder
		end
	end

	if not uiPreviewsFolder:FindFirstChild("BagPreview") then
		local bagPreview = ShovelModelBuilder.BuildBagPreviewModel()
		bagPreview.Parent = uiPreviewsFolder
	end

	return root
end

function ShovelModelBuilder.ClonePreviewModel(shovelId: string): Model
	local root = ReplicatedStorage:FindFirstChild("ShovelAssets")
	local previews = root and root:FindFirstChild("ShovelPreviews")
	local template = previews and previews:FindFirstChild(shovelId)
	if template and template:IsA("Model") then
		return template:Clone()
	end
	return ShovelModelBuilder.BuildPreviewModel(shovelId)
end

function ShovelModelBuilder.CloneBagPreviewModel(): Model
	local root = ReplicatedStorage:FindFirstChild("ShovelAssets")
	local uiPreviews = root and root:FindFirstChild("UIPreviews")
	local template = uiPreviews and uiPreviews:FindFirstChild("BagPreview")
	if template and template:IsA("Model") then
		return template:Clone()
	end
	return ShovelModelBuilder.BuildBagPreviewModel()
end

function ShovelModelBuilder.CloneGameplayTool(shovelId: string): Tool
	local root = ReplicatedStorage:FindFirstChild("ShovelAssets")
	local tools = root and root:FindFirstChild("ShovelTools")
	local template = tools and tools:FindFirstChild(shovelId)
	if template and template:IsA("Tool") then
		local cloned = template:Clone()
		local cfg = ShovelsConfig.All[shovelId]
		if cfg then
			cloned.Name = cfg.ToolName
   cloned.TextureId = cfg.Icon
		end
		return applyCarryDefaults(cloned)
	end
	return ShovelModelBuilder.BuildGameplayTool(shovelId)
end

return ShovelModelBuilder
