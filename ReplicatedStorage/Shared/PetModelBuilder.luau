--!strict
-- PetModelBuilder: Builds and manages visual pet models for followers and base roamers.
-- Supports imported 3D mesh models (e.g. Cat) with procedural fallback for unimported species.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PetsConfig = require(script.Parent:WaitForChild("Config"):WaitForChild("Pets"))
local RarityConfig = require(script.Parent:WaitForChild("Config"):WaitForChild("Rarity"))

local PetAssets = ReplicatedStorage:WaitForChild("PetAssets")
local PetModels = PetAssets:WaitForChild("PetModels")

local PetModelBuilder = {}

local SPECIES_EMOJIS: { [string]: string } = {
	Dog = utf8.char(0x1F436),
	Cat = utf8.char(0x1F431),
	Mole = utf8.char(0x1F439),
	Bunny = utf8.char(0x1F430),
	Hamster = utf8.char(0x1F439),
	Chick = utf8.char(0x1F424),
	Fox = utf8.char(0x1F98A),
	Badger = utf8.char(0x1F9A1),
	Hedgehog = utf8.char(0x1F994),
	Ferret = utf8.char(0x1F9A6),
	Raccoon = utf8.char(0x1F99D),
	Turtle = utf8.char(0x1F422),
	Beetle = utf8.char(0x1FAB2),
	Piglet = utf8.char(0x1F437),
	Armadillo = utf8.char(0x1F6E1),
	Pangolin = utf8.char(0x1F98E),
	Boar = utf8.char(0x1F417),
	Owl = utf8.char(0x1F989),
	Chameleon = utf8.char(0x1F98E),
	CrystalFox = utf8.char(0x1F48E),
	MagmaHound = utf8.char(0x1F525),
	EarthGolem = utf8.char(0x1F5FF),
	RuneBear = utf8.char(0x1F43B),
	TerraDragon = utf8.char(0x1F432),
	CelestialGriffin = utf8.char(0x1F985),
}

local function getRarityColor(rarityName: string): Color3
	local info = (RarityConfig.ById :: any)[rarityName]
	return if info then info.Color else RarityConfig.ById.Common.Color
end

local function addVariantEffects(root: BasePart, variant: string)
	if variant == "Golden" then
		local attachment = Instance.new("Attachment")
		attachment.Name = "VariantAttachment"
		attachment.Parent = root

		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxassetid://1084991219" -- sparkle/star
		emitter.Rate = 6
		emitter.Lifetime = NumberRange.new(0.6, 1.2)
		emitter.Speed = NumberRange.new(0.5, 1.5)
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Parent = attachment
	elseif variant == "Shiny" then
		local attachment = Instance.new("Attachment")
		attachment.Name = "VariantAttachment"
		attachment.Parent = root

		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxassetid://1084991219"
		emitter.Rate = 9
		emitter.Lifetime = NumberRange.new(0.8, 1.4)
		emitter.Speed = NumberRange.new(0.8, 2.0)
		emitter.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 120, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 220, 255)),
		})
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Parent = attachment
	end
end

local function createPetTagBillboard(
	parentPart: BasePart,
	species: string,
	variant: string,
	level: number,
	rarityColor: Color3,
	yOffset: number
): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PetTag"
	billboard.Size = UDim2.fromOffset(130, 48)
	billboard.StudsOffset = Vector3.new(0, yOffset, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 64
	billboard.Parent = parentPart

	local speciesCfg = PetsConfig.Species[species]
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 12
	nameLabel.TextColor3 = rarityColor
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.TextStrokeColor3 = Color3.fromRGB(10, 12, 16)

	local emoji = SPECIES_EMOJIS[species] or "🐾"
	local variantPrefix = if variant == "Golden" then "[GOLDEN] " elseif variant == "Shiny" then "[SHINY] " else ""
	nameLabel.Text = string.format("%s%s %s", variantPrefix, emoji, if speciesCfg then speciesCfg.DisplayName else species)
	nameLabel.Parent = billboard

	local lvLabel = Instance.new("TextLabel")
	lvLabel.Position = UDim2.new(0, 0, 0.5, 0)
	lvLabel.Size = UDim2.new(1, 0, 0.5, 0)
	lvLabel.BackgroundTransparency = 1
	lvLabel.Font = Enum.Font.GothamMedium
	lvLabel.TextSize = 10
	lvLabel.TextColor3 = Color3.fromRGB(240, 244, 250)
	lvLabel.TextStrokeTransparency = 0.5
	lvLabel.Text = "Lv." .. tostring(level)
	lvLabel.Parent = billboard

	return billboard
end

-- Procedural fallback model for species without a 3D mesh
local function createProceduralModel(
	guid: string,
	species: string,
	variant: string,
	level: number,
	spawnPos: Vector3
): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "PetVisual_" .. guid

	local root = Instance.new("Part")
	root.Name = "RootPart"
	root.Size = Vector3.new(1.6, 1.6, 1.6)
	root.Position = spawnPos
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.CastShadow = true
	root.Material = Enum.Material.SmoothPlastic

	local speciesCfg = PetsConfig.Species[species]
	local rarityColor = if speciesCfg then getRarityColor(speciesCfg.Rarity) else Color3.fromRGB(220, 220, 220)

	if variant == "Golden" then
		root.Color = Color3.fromRGB(255, 215, 60)
		root.Material = Enum.Material.Neon
	elseif variant == "Shiny" then
		root.Color = Color3.fromRGB(180, 120, 255)
		root.Material = Enum.Material.Neon
	else
		root.Color = rarityColor
	end

	root.Parent = model
	model.PrimaryPart = root

	local faceAccent = Instance.new("Part")
	faceAccent.Name = "FaceAccent"
	faceAccent.Size = Vector3.new(1.2, 0.6, 0.2)
	faceAccent.CFrame = root.CFrame * CFrame.new(0, 0.1, -0.81)
	faceAccent.Color = Color3.fromRGB(28, 32, 42)
	faceAccent.Material = Enum.Material.SmoothPlastic
	faceAccent.Anchored = false
	faceAccent.CanCollide = false
	faceAccent.CanTouch = false
	faceAccent.CanQuery = false
	faceAccent.Massless = true
	faceAccent.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = faceAccent
	weld.Parent = root

	addVariantEffects(root, variant)
	createPetTagBillboard(root, species, variant, level, rarityColor, 1.8)

	return model, root
end

-- Builds a pet visual model (uses imported template if available, else procedural fallback)
function PetModelBuilder.BuildPet(
	guid: string,
	species: string,
	variant: string,
	level: number,
	spawnPos: Vector3
): (Model, BasePart)
	local template = PetModels:FindFirstChild(species)
	if not template or not template:IsA("Model") then
		return createProceduralModel(guid, species, variant, level, spawnPos)
	end

	local model = template:Clone()
	model.Name = "PetVisual_" .. guid

	local root = model.PrimaryPart
	if not root then
		root = model:FindFirstChild("RootPart") :: BasePart?
			or model:FindFirstChildWhichIsA("BasePart")
	end

	if not root then
		return createProceduralModel(guid, species, variant, level, spawnPos)
	end

	model.PrimaryPart = root
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false

	-- Weld all child mesh parts to RootPart so moving RootPart moves everything
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") and desc ~= root then
			desc.Anchored = false
			desc.CanCollide = false
			desc.CanTouch = false
			desc.CanQuery = false
			desc.Massless = true
			local existingWeld = desc:FindFirstChildOfClass("WeldConstraint")
			if not existingWeld then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = desc
				weld.Parent = root
			end
		end
	end

	-- Move to spawn position
	model:PivotTo(CFrame.new(spawnPos))

	-- Variant styling
	local speciesCfg = PetsConfig.Species[species]
	local rarityColor = if speciesCfg then getRarityColor(speciesCfg.Rarity) else Color3.fromRGB(220, 220, 220)

	if variant == "Golden" then
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Color = Color3.fromRGB(255, 215, 60)
			end
		end
	elseif variant == "Shiny" then
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Color = Color3.fromRGB(200, 150, 255)
			end
		end
	end

	addVariantEffects(root, variant)

	-- Calculate top offset for billboard
	local extents = model:GetExtentsSize()
	local tagYOffset = math.max(1.8, (extents.Y * 0.5) + 0.8)
	createPetTagBillboard(root, species, variant, level, rarityColor, tagYOffset)

	return model, root
end

return PetModelBuilder
