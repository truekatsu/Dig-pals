--!strict
-- Client controller & responsive UI for Pet Bag, Pet Equip (max 3), Assign/Remove from Base, and Release for Coins (Step 9)

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))
local BaseConfig = require(Shared:WaitForChild("Config"):WaitForChild("Base"))
local PetsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Pets"))
local RarityConfig = require(Shared:WaitForChild("Config"):WaitForChild("Rarity"))

local InventoryController = require(script.Parent:WaitForChild("InventoryController"))
local MerchantController = require(script.Parent:WaitForChild("MerchantController"))
local ShovelShopController = require(script.Parent:WaitForChild("ShovelShopController"))
local BaseController = require(script.Parent:WaitForChild("BaseController"))

local LocalPlayer = Players.LocalPlayer

local PetBagController = {}

local COLORS = {
	PanelBg = Color3.fromRGB(22, 27, 38),
	PanelBorder = Color3.fromRGB(255, 175, 64),
	HeaderBg = Color3.fromRGB(26, 34, 48),
	ListBg = Color3.fromRGB(18, 22, 32),
	RowBg = Color3.fromRGB(29, 36, 50),
	RowSelected = Color3.fromRGB(44, 56, 78),
	RowHover = Color3.fromRGB(36, 46, 64),
	DetailBg = Color3.fromRGB(28, 36, 52),

	BtnPrimary = Color3.fromRGB(46, 178, 106),
	BtnPrimaryHover = Color3.fromRGB(60, 204, 124),
	BtnSecondary = Color3.fromRGB(54, 134, 230),
	BtnSecondaryHover = Color3.fromRGB(72, 154, 250),
	BtnDanger = Color3.fromRGB(224, 76, 76),
	BtnDangerHover = Color3.fromRGB(244, 96, 96),
	BtnDisabled = Color3.fromRGB(70, 78, 92),

	TextPrimary = Color3.fromRGB(244, 247, 252),
	TextSecondary = Color3.fromRGB(168, 182, 202),
	TextMuted = Color3.fromRGB(116, 130, 150),

	GoldenGlow = Color3.fromRGB(255, 215, 64),
	ShinyGlow = Color3.fromRGB(170, 110, 255),
}

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

local isOpen = false
local isBusy = false
local selectedPetGuid: string? = nil
local activeFilter = "ALL" -- "ALL" | "EQUIPPED" | "BASE" | "BAG"

-- Local player cache from StateSync
local ownedPets: { [string]: Types.PetInstance } = {}
local equippedPetGuids: { string } = {}
local basePetGuids: { string } = {}
local baseLevel = 1

-- GUI Element references
local screenGui: ScreenGui? = nil
local uiScale: UIScale? = nil
local backdropButton: TextButton? = nil
local panelFrame: Frame? = nil
local petScrollFrame: ScrollingFrame? = nil
local emptyLabel: TextLabel? = nil

local totalPillLabel: TextLabel? = nil
local equippedPillLabel: TextLabel? = nil
local basePillLabel: TextLabel? = nil

-- Right detail pane references
local detailSpeciesLabel: TextLabel? = nil
local detailRarityBadge: TextLabel? = nil
local detailVariantBadge: TextLabel? = nil
local detailEmojiLabel: TextLabel? = nil
local detailStatsLabel: TextLabel? = nil
local detailStatusBanner: TextLabel? = nil

local equipButton: TextButton? = nil
local baseButton: TextButton? = nil
local releaseButton: TextButton? = nil
local levelUpButton: TextButton? = nil

local function getRarityColor(rarityName: string): Color3
	local info = (RarityConfig.ById :: any)[rarityName]
	return if info then info.Color else RarityConfig.ById.Common.Color
end

local function computeEffectiveStats(speciesId: string, variant: Types.PetVariantName, level: number?)
	local speciesCfg = PetsConfig.Species[speciesId]
	if not speciesCfg then
		return nil
	end
	local variantCfg = (PetsConfig.Variants :: any)[variant] or PetsConfig.Variants.Normal

	local safeLevel = math.clamp(level or 1, 1, PetsConfig.MaxPetLevel)
	local effPower = math.floor(speciesCfg.Power * variantCfg.PowerMultiplier)
	local effDigSpeed = math.min(PetsConfig.MaxEffectiveDigSpeed, speciesCfg.DigSpeed + variantCfg.DigSpeedBonus)
	local effSpeed = speciesCfg.Speed
	local effRange = speciesCfg.Range
	local interval = math.max(0.25, PetsConfig.BaseAttackInterval - (PetsConfig.AttackIntervalReductionPerDigSpeed * effDigSpeed))
	local moveSpeed = PetsConfig.BaseMoveSpeedStuds + (PetsConfig.MoveSpeedPerStat * effSpeed)
	local releasePrice = PetsConfig.ReleasePriceByRarity[speciesCfg.Rarity] or 25
	local levelBonus = 1.0 + (PetsConfig.LevelIncomeBonusPerLevel * (safeLevel - 1))
	local income = math.floor(speciesCfg.BaseIncome * levelBonus * variantCfg.IncomeMultiplier)

	return {
		SpeciesCfg = speciesCfg,
		VariantCfg = variantCfg,
		Power = effPower,
		DigSpeed = effDigSpeed,
		Speed = effSpeed,
		Range = effRange,
		Interval = interval,
		MoveSpeed = moveSpeed,
		ReleasePrice = releasePrice,
		Income = income,
		Level = safeLevel,
	}
end

local function getLevelUpCost(speciesId: string, currentLevel: number): (number?, string?)
	local speciesCfg = PetsConfig.Species[speciesId]
	if not speciesCfg then
		return nil, "InvalidSpecies"
	end
	local safeLevel = currentLevel or 1
	if safeLevel >= PetsConfig.MaxPetLevel then
		return nil, "MaxLevelReached"
	end
	local baseCost = PetsConfig.LevelUpBaseCostByRarity[speciesCfg.Rarity] or 40
	local cost = math.floor(baseCost * (PetsConfig.LevelUpCostGrowthFactor ^ (safeLevel - 1)))
	return math.max(1, cost), nil
end

local function updateResponsiveScale()
	if not uiScale then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local vw = cam.ViewportSize.X
	local vh = cam.ViewportSize.Y
	local scaleX = vw / 1024
	local scaleY = vh / 640
	local scale = math.min(scaleX, scaleY)
	uiScale.Scale = math.clamp(scale, 0.55, 1.25)
end

local function setStatusMessage(msg: string?, isError: boolean)
	if not detailStatusBanner then
		return
	end
	if not msg or msg == "" then
		detailStatusBanner.Text = ""
		detailStatusBanner.Visible = false
	else
		detailStatusBanner.Text = msg
		detailStatusBanner.TextColor3 = if isError then Color3.fromRGB(255, 102, 102) else Color3.fromRGB(110, 240, 160)
		detailStatusBanner.Visible = true
	end
end

-- Refresh right detail pane based on selected pet
local function refreshDetailPane()
	if not selectedPetGuid or not ownedPets[selectedPetGuid] then
		if detailSpeciesLabel then
			detailSpeciesLabel.Text = "PILIH PET"
			detailSpeciesLabel.TextColor3 = COLORS.TextSecondary
		end
		if detailRarityBadge then
			detailRarityBadge.Visible = false
		end
		if detailVariantBadge then
			detailVariantBadge.Visible = false
		end
		if detailEmojiLabel then
			detailEmojiLabel.Text = "PET"
		end
		if detailStatsLabel then
			detailStatsLabel.Text = "Pilih salah satu pet dari daftar di sebelah kiri untuk melihat statistik, equip, atau taruh di base."
		end
		if equipButton then
			equipButton.Visible = false
		end
		if baseButton then
			baseButton.Visible = false
		end
		if releaseButton then
			releaseButton.Visible = false
		end
		if levelUpButton then
			levelUpButton.Visible = false
		end
		return
	end

	local pet = ownedPets[selectedPetGuid]
	local stats = computeEffectiveStats(pet.Species, pet.Variant, pet.Level)
	if not stats then
		return
	end

	local rarityColor = getRarityColor(stats.SpeciesCfg.Rarity)
	local isEquipped = (table.find(equippedPetGuids, selectedPetGuid) ~= nil)
	local isInBase = (table.find(basePetGuids, selectedPetGuid) ~= nil)

	if detailSpeciesLabel then
		detailSpeciesLabel.Text = stats.SpeciesCfg.DisplayName
		detailSpeciesLabel.TextColor3 = rarityColor
	end

	if detailRarityBadge then
		detailRarityBadge.Text = string.upper(stats.SpeciesCfg.Rarity)
		detailRarityBadge.BackgroundColor3 = rarityColor
		detailRarityBadge.Visible = true
	end

	if detailVariantBadge then
		if pet.Variant == "Golden" then
			detailVariantBadge.Text = "GOLDEN (+50%)"
			detailVariantBadge.BackgroundColor3 = COLORS.GoldenGlow
			detailVariantBadge.TextColor3 = Color3.fromRGB(20, 16, 8)
			detailVariantBadge.Visible = true
		elseif pet.Variant == "Shiny" then
			detailVariantBadge.Text = "SHINY (+125%)"
			detailVariantBadge.BackgroundColor3 = COLORS.ShinyGlow
			detailVariantBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
			detailVariantBadge.Visible = true
		else
			detailVariantBadge.Visible = false
		end
	end

	if detailEmojiLabel then
		detailEmojiLabel.Text = SPECIES_EMOJIS[pet.Species] or "PET"
	end

	if detailStatsLabel then
		local variantPowerBonus = if pet.Variant == "Golden" then " (x1.5)" elseif pet.Variant == "Shiny" then " (x2.25)" else ""
		local variantDigBonus = if stats.VariantCfg.DigSpeedBonus > 0 then string.format(" (+%d)", stats.VariantCfg.DigSpeedBonus) else ""

		detailStatsLabel.Text = string.format(
			"Power: %d%s\nDig Speed: %d/10%s (Jeda: %.2fs)\nMove Speed: %d studs/dtk\nJangkauan (Range): %d studs\nIncome: +$%d/dtk\nLevel: %d/20",
			stats.Power,
			variantPowerBonus,
			stats.DigSpeed,
			variantDigBonus,
			stats.Interval,
			stats.MoveSpeed,
			stats.Range,
			stats.Income,
			pet.Level or 1
		)
	end

	-- 0. Level Up button
	if levelUpButton then
		levelUpButton.Visible = true
		local currentLevel = pet.Level or 1
		local cost, err = getLevelUpCost(pet.Species, currentLevel)
		local playerCoins = LocalPlayer:GetAttribute("Coins") or 0

		if currentLevel >= PetsConfig.MaxPetLevel then
			levelUpButton.Text = "MAX LEVEL (Lv. 20)"
			levelUpButton.BackgroundColor3 = COLORS.BtnDisabled
			levelUpButton.Active = false
		elseif cost and playerCoins < cost then
			levelUpButton.Text = string.format("LEVEL UP (Lv. %d -> %d) - $%s", currentLevel, currentLevel + 1, Format.Commas(cost))
			levelUpButton.BackgroundColor3 = COLORS.BtnDisabled
			levelUpButton.Active = false
		elseif cost then
			levelUpButton.Text = string.format("LEVEL UP (Lv. %d -> %d) - $%s", currentLevel, currentLevel + 1, Format.Commas(cost))
			levelUpButton.BackgroundColor3 = Color3.fromRGB(46, 178, 106)
			levelUpButton.Active = not isBusy
		end
	end

	-- 1. Equip / Unequip button
	if equipButton then
		equipButton.Visible = true
		if isEquipped then
			equipButton.Text = "LEPAS EQUIP"
			equipButton.BackgroundColor3 = COLORS.BtnSecondary
			equipButton.Active = not isBusy
		elseif isInBase then
			equipButton.Text = "DI BASE (Tarik Dulu)"
			equipButton.BackgroundColor3 = COLORS.BtnDisabled
			equipButton.Active = false
		elseif #equippedPetGuids >= PetsConfig.MaxEquippedPets then
			equipButton.Text = string.format("EQUIP PENUH (%d/%d)", #equippedPetGuids, PetsConfig.MaxEquippedPets)
			equipButton.BackgroundColor3 = COLORS.BtnDisabled
			equipButton.Active = false
		else
			equipButton.Text = string.format("EQUIP PET (%d/%d)", #equippedPetGuids, PetsConfig.MaxEquippedPets)
			equipButton.BackgroundColor3 = COLORS.BtnPrimary
			equipButton.Active = not isBusy
		end
	end

	-- 2. Base Assign / Remove button
	local maxBaseSlots = if BaseConfig.Levels[baseLevel] then BaseConfig.Levels[baseLevel].PetSlots else 2
	if baseButton then
		baseButton.Visible = true
		if isInBase then
			baseButton.Text = "TARIK DARI BASE"
			baseButton.BackgroundColor3 = COLORS.BtnSecondary
			baseButton.Active = not isBusy
		elseif isEquipped then
			baseButton.Text = "SEDANG EQUIP (Lepas Dulu)"
			baseButton.BackgroundColor3 = COLORS.BtnDisabled
			baseButton.Active = false
		elseif #basePetGuids >= maxBaseSlots then
			baseButton.Text = string.format("BASE PENUH (%d/%d)", #basePetGuids, maxBaseSlots)
			baseButton.BackgroundColor3 = COLORS.BtnDisabled
			baseButton.Active = false
		else
			baseButton.Text = string.format("TARUH KE BASE (%d/%d)", #basePetGuids, maxBaseSlots)
			baseButton.BackgroundColor3 = COLORS.BtnPrimary
			baseButton.Active = not isBusy
		end
	end

	-- 3. Release button (PRD 8.5)
	if releaseButton then
		releaseButton.Visible = true
		if isEquipped or isInBase then
			releaseButton.Text = "LEPAS PET (Lepas Equip/Base Dulu)"
			releaseButton.BackgroundColor3 = COLORS.BtnDisabled
			releaseButton.Active = false
		else
			releaseButton.Text = string.format("LEPAS PET (+$%s)", Format.Commas(stats.ReleasePrice))
			releaseButton.BackgroundColor3 = COLORS.BtnDanger
			releaseButton.Active = not isBusy
		end
	end
end

-- Rebuild the scroll list of pets
local function rebuildPetList()
	if not petScrollFrame then
		return
	end

	for _, child in petScrollFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- Update header pills
	local totalPets = 0
	for _ in ownedPets do
		totalPets += 1
	end

	local maxBaseSlots = if BaseConfig.Levels[baseLevel] then BaseConfig.Levels[baseLevel].PetSlots else 2

	if totalPillLabel then
		totalPillLabel.Text = string.format("Pet %d/%d", totalPets, PetsConfig.MaxPetBagCapacity)
	end
	if equippedPillLabel then
		equippedPillLabel.Text = string.format("Dipakai %d/%d", #equippedPetGuids, PetsConfig.MaxEquippedPets)
	end
	if basePillLabel then
		basePillLabel.Text = string.format("Di Base %d/%d", #basePetGuids, maxBaseSlots)
	end

	if emptyLabel then
		emptyLabel.Visible = (totalPets == 0)
	end

	-- Sort pets: Equipped first, then Base, then Rarity descending, then Name
	local petList: { { Guid: string, Pet: Types.PetInstance } } = {}
	for guid, pet in ownedPets do
		table.insert(petList, { Guid = guid, Pet = pet })
	end

	local rarityOrder: { [Types.RarityName]: number } = {
		Legendary = 5,
		Epic = 4,
		Rare = 3,
		Uncommon = 2,
		Common = 1,
	}

	table.sort(petList, function(a, b)
		local aEquipped = (table.find(equippedPetGuids, a.Guid) ~= nil)
		local bEquipped = (table.find(equippedPetGuids, b.Guid) ~= nil)
		if aEquipped ~= bEquipped then
			return aEquipped
		end

		local aBase = (table.find(basePetGuids, a.Guid) ~= nil)
		local bBase = (table.find(basePetGuids, b.Guid) ~= nil)
		if aBase ~= bBase then
			return aBase
		end

		local aCfg = PetsConfig.Species[a.Pet.Species]
		local bCfg = PetsConfig.Species[b.Pet.Species]
		local aRarity = if aCfg then (rarityOrder[aCfg.Rarity] or 1) else 1
		local bRarity = if bCfg then (rarityOrder[bCfg.Rarity] or 1) else 1
		if aRarity ~= bRarity then
			return aRarity > bRarity
		end

		return a.Pet.Species < b.Pet.Species
	end)

	-- If selectedPetGuid is invalid, default to first pet
	if selectedPetGuid == nil or ownedPets[selectedPetGuid] == nil then
		if #petList > 0 then
			selectedPetGuid = petList[1].Guid
		else
			selectedPetGuid = nil
		end
	end

	local renderOrder = 0
	for _, entry in petList do
		local guid = entry.Guid
		local pet = entry.Pet
		local isEquipped = (table.find(equippedPetGuids, guid) ~= nil)
		local isInBase = (table.find(basePetGuids, guid) ~= nil)

		-- Filter matching
		if activeFilter == "EQUIPPED" and not isEquipped then
			continue
		elseif activeFilter == "BASE" and not isInBase then
			continue
		elseif activeFilter == "BAG" and (isEquipped or isInBase) then
			continue
		end

		renderOrder += 1
		local stats = computeEffectiveStats(pet.Species, pet.Variant, pet.Level)
		local rarityColor = if stats then getRarityColor(stats.SpeciesCfg.Rarity) else COLORS.TextSecondary
		local isSelected = (guid == selectedPetGuid)

		local row = Instance.new("TextButton")
		row.Name = "PetRow_" .. guid
		row.Size = UDim2.new(1, -6, 0, 68)
		row.BackgroundColor3 = if isSelected then COLORS.RowSelected else COLORS.RowBg
		row.BorderSizePixel = 0
		row.LayoutOrder = renderOrder
		row.AutoButtonColor = true
		row.Text = ""
		row.Parent = petScrollFrame

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 10)
		rowCorner.Parent = row

		local rowStroke = Instance.new("UIStroke")
		rowStroke.Color = if isSelected then COLORS.PanelBorder else Color3.fromRGB(44, 54, 72)
		rowStroke.Thickness = if isSelected then 2 else 1
		rowStroke.Parent = row

		-- Emoji / Icon Box
		local iconBox = Instance.new("Frame")
		iconBox.Name = "IconBox"
		iconBox.Size = UDim2.fromOffset(50, 50)
		iconBox.Position = UDim2.fromOffset(8, 9)
		iconBox.BackgroundColor3 = Color3.fromRGB(18, 24, 34)
		iconBox.BorderSizePixel = 0
		iconBox.Parent = row

		local iconCorner = Instance.new("UICorner")
		iconCorner.CornerRadius = UDim.new(0, 8)
		iconCorner.Parent = iconBox

		local iconStroke = Instance.new("UIStroke")
		iconStroke.Color = rarityColor
		iconStroke.Thickness = 1.5
		iconStroke.Parent = iconBox

		local iconLabel = Instance.new("TextLabel")
		iconLabel.Size = UDim2.fromScale(1, 1)
		iconLabel.BackgroundTransparency = 1
		iconLabel.Font = Enum.Font.GothamBold
		iconLabel.TextSize = 26
		iconLabel.Text = SPECIES_EMOJIS[pet.Species] or "PET"
		iconLabel.Parent = iconBox

		-- Species Name
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "SpeciesName"
		nameLabel.Position = UDim2.fromOffset(66, 12)
		nameLabel.Size = UDim2.new(1, -160, 0, 18)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 14
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextColor3 = rarityColor
		nameLabel.Text = if stats then stats.SpeciesCfg.DisplayName else pet.Species
		nameLabel.Parent = row

		-- Sub meta: Power & DigSpeed & Variant
		local metaLabel = Instance.new("TextLabel")
		metaLabel.Name = "MetaLabel"
		metaLabel.Position = UDim2.fromOffset(66, 36)
		metaLabel.Size = UDim2.new(1, -160, 0, 16)
		metaLabel.BackgroundTransparency = 1
		metaLabel.Font = Enum.Font.GothamMedium
		metaLabel.TextSize = 11
		metaLabel.TextXAlignment = Enum.TextXAlignment.Left
		metaLabel.TextColor3 = COLORS.TextSecondary

		local variantTag = if pet.Variant == "Golden" then "[GOLDEN] " elseif pet.Variant == "Shiny" then "[SHINY] " else ""
		metaLabel.Text = string.format("%sLv. %d | Power %d | Dig %d", variantTag, pet.Level or 1, stats and stats.Power or 0, stats and stats.DigSpeed or 0)
		metaLabel.Parent = row

		-- Status Pill Badge
		local statusBadge = Instance.new("TextLabel")
		statusBadge.Name = "StatusBadge"
		statusBadge.AnchorPoint = Vector2.new(1, 0.5)
		statusBadge.Position = UDim2.new(1, -10, 0.5, 0)
		statusBadge.Size = UDim2.fromOffset(80, 26)
		statusBadge.BorderSizePixel = 0
		statusBadge.Font = Enum.Font.GothamBlack
		statusBadge.TextSize = 10
		statusBadge.Parent = row

		local badgeCorner = Instance.new("UICorner")
		badgeCorner.CornerRadius = UDim.new(0, 6)
		badgeCorner.Parent = statusBadge

		if isEquipped then
			statusBadge.BackgroundColor3 = COLORS.BtnPrimary
			statusBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
			statusBadge.Text = "DIPAKAI"
		elseif isInBase then
			statusBadge.BackgroundColor3 = COLORS.BtnSecondary
			statusBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
			statusBadge.Text = "DI BASE"
		else
			statusBadge.BackgroundColor3 = Color3.fromRGB(36, 44, 58)
			statusBadge.TextColor3 = COLORS.TextMuted
			statusBadge.Text = "DI TAS"
		end

		row.Activated:Connect(function()
			selectedPetGuid = guid
			setStatusMessage(nil, false)
			rebuildPetList()
		end)
	end

	refreshDetailPane()
end

function PetBagController.IsOpen(): boolean
	return isOpen
end

function PetBagController.Open()
	if InventoryController.IsOpen() then
		InventoryController.ClosePanel()
	end
	if MerchantController.IsOpen() then
		MerchantController.ClosePanel()
	end
	if ShovelShopController.IsOpen() then
		ShovelShopController.ClosePanel()
	end
	if BaseController.IsOpen() then
		BaseController.CloseIncubatorModal()
	end

	isOpen = true
	setStatusMessage(nil, false)

	if backdropButton then
		backdropButton.Visible = true
	end
	if panelFrame then
		panelFrame.Visible = true
	end

	rebuildPetList()
end

function PetBagController.Close()
	if not isOpen then
		return
	end
	isOpen = false
	setStatusMessage(nil, false)

	if backdropButton then
		backdropButton.Visible = false
	end
	if panelFrame then
		panelFrame.Visible = false
	end
end

function PetBagController.Toggle()
	if isOpen then
		PetBagController.Close()
	else
		PetBagController.Open()
	end
end

-- Apply state sync snapshot payload
function PetBagController.ApplySnapshot(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if type(payload.BaseLevel) == "number" then
		baseLevel = payload.BaseLevel
	end
	if type(payload.Pets) == "table" then
		ownedPets = payload.Pets
	end
	if type(payload.EquippedPets) == "table" then
		equippedPetGuids = payload.EquippedPets
	end
	if type(payload.BasePets) == "table" then
		basePetGuids = payload.BasePets
	end

	if isOpen then
		rebuildPetList()
	end
end

-- Remote actions
function PetBagController.RequestEquip()
	if isBusy or not selectedPetGuid then
		return
	end
	isBusy = true
	setStatusMessage(nil, false)
	rebuildPetList()

	local ok, response = pcall(function()
		return Remotes.GetFunction("EquipPet"):InvokeServer(selectedPetGuid)
	end)

	isBusy = false

	if ok and type(response) == "table" and response.Success == true then
		setStatusMessage("Pet berhasil digunakan!", false)
	else
		local msg = if ok and type(response) == "table" and type(response.Message) == "string"
			then response.Message
			else "Gagal menggunakan pet."
		setStatusMessage(msg, true)
	end

	rebuildPetList()
end

function PetBagController.RequestUnequip()
	if isBusy or not selectedPetGuid then
		return
	end
	isBusy = true
	setStatusMessage(nil, false)
	rebuildPetList()

	local ok, response = pcall(function()
		return Remotes.GetFunction("UnequipPet"):InvokeServer(selectedPetGuid)
	end)

	isBusy = false

	if ok and type(response) == "table" and response.Success == true then
		setStatusMessage("Pet berhasil dilepas dari equip.", false)
	else
		local msg = if ok and type(response) == "table" and type(response.Message) == "string"
			then response.Message
			else "Gagal melepas pet."
		setStatusMessage(msg, true)
	end

	rebuildPetList()
end

function PetBagController.RequestAssignBase()
	if isBusy or not selectedPetGuid then
		return
	end
	isBusy = true
	setStatusMessage(nil, false)
	rebuildPetList()

	local ok, response = pcall(function()
		return Remotes.GetFunction("AssignPetToBase"):InvokeServer(selectedPetGuid)
	end)

	isBusy = false

	if ok and type(response) == "table" and response.Success == true then
		setStatusMessage("Pet berhasil ditugaskan di Base!", false)
	else
		local msg = if ok and type(response) == "table" and type(response.Message) == "string"
			then response.Message
			else "Gagal menaruh pet di base."
		setStatusMessage(msg, true)
	end

	rebuildPetList()
end

function PetBagController.RequestRemoveBase()
	if isBusy or not selectedPetGuid then
		return
	end
	isBusy = true
	setStatusMessage(nil, false)
	rebuildPetList()

	local ok, response = pcall(function()
		return Remotes.GetFunction("RemovePetFromBase"):InvokeServer(selectedPetGuid)
	end)

	isBusy = false

	if ok and type(response) == "table" and response.Success == true then
		setStatusMessage("Pet berhasil ditarik dari Base.", false)
	else
		local msg = if ok and type(response) == "table" and type(response.Message) == "string"
			then response.Message
			else "Gagal menarik pet dari base."
		setStatusMessage(msg, true)
	end

	rebuildPetList()
end

function PetBagController.RequestRelease()
	if isBusy or not selectedPetGuid then
		return
	end
	isBusy = true
	setStatusMessage(nil, false)
	rebuildPetList()

	local ok, response = pcall(function()
		return Remotes.GetFunction("ReleasePet"):InvokeServer(selectedPetGuid)
	end)

	isBusy = false

	if ok and type(response) == "table" and response.Success == true then
		local coins = tonumber(response.CoinsEarned) or 0
		setStatusMessage(string.format("Pet berhasil dilepas (+$%s)!", Format.Commas(coins)), false)
		selectedPetGuid = nil
	else
		local msg = if ok and type(response) == "table" and type(response.Message) == "string"
			then response.Message
			else "Gagal melepaskan pet."
		setStatusMessage(msg, true)
	end

	rebuildPetList()
end

function PetBagController.RequestLevelUp()
	if isBusy or not selectedPetGuid then
		return
	end
	local pet = ownedPets[selectedPetGuid]
	if not pet then
		return
	end

	isBusy = true
	setStatusMessage("Menaikkan level pet...", false)
	rebuildPetList()

	local ok, response = pcall(function()
		return Remotes.GetFunction("LevelUpPet"):InvokeServer(selectedPetGuid)
	end)

	isBusy = false

	if ok and type(response) == "table" and response.Success == true then
		local newLv = response.NewLevel or ((pet.Level or 1) + 1)
		pet.Level = newLv
		setStatusMessage(string.format("Level up berhasil! Pet kini Lv. %d", newLv), false)
	else
		local reason = if ok and type(response) == "table" and response.ErrorReason then response.ErrorReason else "Gagal level up"
		local msg = if reason == "InsufficientCoins" then "Uang tidak cukup untuk level up!"
			elseif reason == "MaxLevelReached" then "Pet sudah mencapai level maksimal (Lv. 20)!"
			else reason
		setStatusMessage(msg, true)
	end

	rebuildPetList()
end

-- Build GUI modal
local function buildPetBagGui()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("PetBagGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "PetBagGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 18
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	screenGui = gui

	local scaleInst = Instance.new("UIScale")
	scaleInst.Name = "ResponsiveScale"
	scaleInst.Scale = 1
	scaleInst.Parent = gui
	uiScale = scaleInst
	updateResponsiveScale()

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "ModalBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.Visible = false
	backdrop.ZIndex = 8
	backdrop.Parent = gui
	backdropButton = backdrop

	backdrop.Activated:Connect(function()
		PetBagController.Close()
	end)

	local panel = Instance.new("Frame")
	panel.Name = "PetBagPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.45, 0)
	panel.Size = UDim2.fromOffset(780, 500)
	panel.BackgroundColor3 = COLORS.PanelBg
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Active = true
	panel.ZIndex = 10
	panel.Parent = gui
	panelFrame = panel

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 14)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = COLORS.PanelBorder
	panelStroke.Thickness = 1.8
	panelStroke.Parent = panel

	-- Header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 52)
	header.BackgroundColor3 = COLORS.HeaderBg
	header.BorderSizePixel = 0
	header.Parent = panel

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 14)
	headerCorner.Parent = header

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(20, 0)
	title.Size = UDim2.new(0, 160, 1, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = COLORS.TextPrimary
	title.Text = "TAS PET"
	title.Parent = header

	local totalPill = Instance.new("TextLabel")
	totalPill.Name = "TotalPill"
	totalPill.Position = UDim2.fromOffset(190, 12)
	totalPill.Size = UDim2.fromOffset(100, 28)
	totalPill.BackgroundColor3 = Color3.fromRGB(36, 44, 60)
	totalPill.Font = Enum.Font.GothamBold
	totalPill.TextSize = 12
	totalPill.TextColor3 = COLORS.TextPrimary
	totalPill.Text = "Pet 0/60"
	totalPill.Parent = header
	totalPillLabel = totalPill

	local tpCorner = Instance.new("UICorner")
	tpCorner.CornerRadius = UDim.new(0, 8)
	tpCorner.Parent = totalPill

	local eqPill = Instance.new("TextLabel")
	eqPill.Name = "EquippedPill"
	eqPill.Position = UDim2.fromOffset(300, 12)
	eqPill.Size = UDim2.fromOffset(105, 28)
	eqPill.BackgroundColor3 = Color3.fromRGB(24, 76, 50)
	eqPill.Font = Enum.Font.GothamBold
	eqPill.TextSize = 12
	eqPill.TextColor3 = Color3.fromRGB(110, 240, 160)
	eqPill.Text = "Dipakai 0/3"
	eqPill.Parent = header
	equippedPillLabel = eqPill

	local eqCorner = Instance.new("UICorner")
	eqCorner.CornerRadius = UDim.new(0, 8)
	eqCorner.Parent = eqPill

	local basePill = Instance.new("TextLabel")
	basePill.Name = "BasePill"
	basePill.Position = UDim2.fromOffset(415, 12)
	basePill.Size = UDim2.fromOffset(105, 28)
	basePill.BackgroundColor3 = Color3.fromRGB(24, 56, 92)
	basePill.Font = Enum.Font.GothamBold
	basePill.TextSize = 12
	basePill.TextColor3 = Color3.fromRGB(130, 195, 255)
	basePill.Text = "Di Base 0/2"
	basePill.Parent = header
	basePillLabel = basePill

	local bpCorner = Instance.new("UICorner")
	bpCorner.CornerRadius = UDim.new(0, 8)
	bpCorner.Parent = basePill

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -10, 0.5, 0)
	closeBtn.Size = UDim2.fromOffset(44, 44)
	closeBtn.BackgroundColor3 = Color3.fromRGB(44, 52, 68)
	closeBtn.BorderSizePixel = 0
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.TextColor3 = COLORS.TextPrimary
	closeBtn.Text = "X"
	closeBtn.Parent = header

	local cbCorner = Instance.new("UICorner")
	cbCorner.CornerRadius = UDim.new(0, 8)
	cbCorner.Parent = closeBtn

	closeBtn.Activated:Connect(function()
		PetBagController.Close()
	end)

	-- Filter Buttons Row
	local filterBar = Instance.new("Frame")
	filterBar.Name = "FilterBar"
	filterBar.Position = UDim2.fromOffset(16, 62)
	filterBar.Size = UDim2.new(0, 420, 0, 32)
	filterBar.BackgroundTransparency = 1
	filterBar.Parent = panel

	local filterLayout = Instance.new("UIListLayout")
	filterLayout.FillDirection = Enum.FillDirection.Horizontal
	filterLayout.Padding = UDim.new(0, 8)
	filterLayout.Parent = filterBar

	local function createFilterTab(name: string, filterKey: string, text: string)
		local tabBtn = Instance.new("TextButton")
		tabBtn.Name = "Tab_" .. name
		tabBtn.Size = UDim2.fromOffset(98, 30)
		tabBtn.BackgroundColor3 = if activeFilter == filterKey then COLORS.BtnSecondary else COLORS.RowBg
		tabBtn.Font = Enum.Font.GothamBold
		tabBtn.TextSize = 11
		tabBtn.TextColor3 = COLORS.TextPrimary
		tabBtn.Text = text
		tabBtn.Parent = filterBar

		local tc = Instance.new("UICorner")
		tc.CornerRadius = UDim.new(0, 6)
		tc.Parent = tabBtn

		tabBtn.Activated:Connect(function()
			activeFilter = filterKey
			for _, c in filterBar:GetChildren() do
				if c:IsA("TextButton") then
					c.BackgroundColor3 = COLORS.RowBg
				end
			end
			tabBtn.BackgroundColor3 = COLORS.BtnSecondary
			rebuildPetList()
		end)
	end

	createFilterTab("All", "ALL", "Semua")
	createFilterTab("Equipped", "EQUIPPED", "Dipakai")
	createFilterTab("Base", "BASE", "Di Base")
	createFilterTab("Bag", "BAG", "Di Tas")

	-- Left column: Pet list scroll
	local leftFrame = Instance.new("Frame")
	leftFrame.Name = "LeftPetList"
	leftFrame.Position = UDim2.fromOffset(16, 102)
	leftFrame.Size = UDim2.new(0, 420, 1, -118)
	leftFrame.BackgroundColor3 = COLORS.ListBg
	leftFrame.BorderSizePixel = 0
	leftFrame.Parent = panel

	local leftCorner = Instance.new("UICorner")
	leftCorner.CornerRadius = UDim.new(0, 10)
	leftCorner.Parent = leftFrame

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "PetListScroll"
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = Color3.fromRGB(72, 88, 116)
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = leftFrame
	petScrollFrame = scroll

	local listPad = Instance.new("UIPadding")
	listPad.PaddingTop = UDim.new(0, 8)
	listPad.PaddingBottom = UDim.new(0, 8)
	listPad.PaddingLeft = UDim.new(0, 8)
	listPad.PaddingRight = UDim.new(0, 8)
	listPad.Parent = scroll

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 6)
	listLayout.Parent = scroll

	local empty = Instance.new("TextLabel")
	empty.Name = "EmptyState"
	empty.Size = UDim2.new(1, -20, 0, 80)
	empty.Position = UDim2.new(0, 10, 0.4, -40)
	empty.BackgroundTransparency = 1
	empty.Font = Enum.Font.GothamMedium
	empty.TextSize = 13
	empty.TextColor3 = COLORS.TextMuted
	empty.TextWrapped = true
	empty.Text = "Tas Pet kamu masih kosong.\nTetaskan telur di Inkubator Base untuk mendapatkan pet baru!"
	empty.Visible = false
	empty.Parent = leftFrame
	emptyLabel = empty

	-- Right column: Selected Pet Details
	local rightFrame = Instance.new("Frame")
	rightFrame.Name = "RightDetailPane"
	rightFrame.Position = UDim2.fromOffset(450, 62)
	rightFrame.Size = UDim2.new(1, -466, 1, -78)
	rightFrame.BackgroundColor3 = COLORS.DetailBg
	rightFrame.BorderSizePixel = 0
	rightFrame.Parent = panel

	local rightCorner = Instance.new("UICorner")
	rightCorner.CornerRadius = UDim.new(0, 10)
	rightCorner.Parent = rightFrame

	local rightStroke = Instance.new("UIStroke")
	rightStroke.Color = Color3.fromRGB(48, 60, 80)
	rightStroke.Thickness = 1.2
	rightStroke.Parent = rightFrame

	-- Emoji preview card
	local previewBox = Instance.new("Frame")
	previewBox.Name = "PreviewBox"
	previewBox.AnchorPoint = Vector2.new(0.5, 0)
	previewBox.Position = UDim2.new(0.5, 0, 0, 14)
	previewBox.Size = UDim2.fromOffset(72, 72)
	previewBox.BackgroundColor3 = Color3.fromRGB(18, 24, 34)
	previewBox.BorderSizePixel = 0
	previewBox.Parent = rightFrame

	local pbCorner = Instance.new("UICorner")
	pbCorner.CornerRadius = UDim.new(0, 12)
	pbCorner.Parent = previewBox

	local pbStroke = Instance.new("UIStroke")
	pbStroke.Color = COLORS.PanelBorder
	pbStroke.Thickness = 1.8
	pbStroke.Parent = previewBox

	local emojiLbl = Instance.new("TextLabel")
	emojiLbl.Name = "EmojiLabel"
	emojiLbl.Size = UDim2.fromScale(1, 1)
	emojiLbl.BackgroundTransparency = 1
	emojiLbl.Font = Enum.Font.GothamBold
	emojiLbl.TextSize = 38
	emojiLbl.Text = "PET"
	emojiLbl.Parent = previewBox
	detailEmojiLabel = emojiLbl

	-- Species Name
	local spLabel = Instance.new("TextLabel")
	spLabel.Name = "SpeciesName"
	spLabel.AnchorPoint = Vector2.new(0.5, 0)
	spLabel.Position = UDim2.new(0.5, 0, 0, 92)
	spLabel.Size = UDim2.new(1, -20, 0, 22)
	spLabel.BackgroundTransparency = 1
	spLabel.Font = Enum.Font.GothamBlack
	spLabel.TextSize = 18
	spLabel.TextColor3 = COLORS.TextPrimary
	spLabel.Text = "PILIH PET"
	spLabel.Parent = rightFrame
	detailSpeciesLabel = spLabel

	-- Badges (Rarity & Variant)
	local badgeContainer = Instance.new("Frame")
	badgeContainer.Name = "Badges"
	badgeContainer.AnchorPoint = Vector2.new(0.5, 0)
	badgeContainer.Position = UDim2.new(0.5, 0, 0, 118)
	badgeContainer.Size = UDim2.new(1, -20, 0, 22)
	badgeContainer.BackgroundTransparency = 1
	badgeContainer.Parent = rightFrame

	local badgeLayout = Instance.new("UIListLayout")
	badgeLayout.FillDirection = Enum.FillDirection.Horizontal
	badgeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	badgeLayout.Padding = UDim.new(0, 6)
	badgeLayout.Parent = badgeContainer

	local rBadge = Instance.new("TextLabel")
	rBadge.Name = "RarityBadge"
	rBadge.Size = UDim2.fromOffset(80, 20)
	rBadge.BorderSizePixel = 0
	rBadge.Font = Enum.Font.GothamBlack
	rBadge.TextSize = 10
	rBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
	rBadge.Text = "COMMON"
	rBadge.Visible = false
	rBadge.Parent = badgeContainer
	detailRarityBadge = rBadge

	local rbCorner = Instance.new("UICorner")
	rbCorner.CornerRadius = UDim.new(0, 6)
	rbCorner.Parent = rBadge

	local vBadge = Instance.new("TextLabel")
	vBadge.Name = "VariantBadge"
	vBadge.Size = UDim2.fromOffset(130, 20)
	vBadge.BorderSizePixel = 0
	vBadge.Font = Enum.Font.GothamBlack
	vBadge.TextSize = 10
	vBadge.Text = "GOLDEN"
	vBadge.Visible = false
	vBadge.Parent = badgeContainer
	detailVariantBadge = vBadge

	local vbCorner = Instance.new("UICorner")
	vbCorner.CornerRadius = UDim.new(0, 6)
	vbCorner.Parent = vBadge

	-- Stats Card Box
	local statsBox = Instance.new("Frame")
	statsBox.Name = "StatsBox"
	statsBox.AnchorPoint = Vector2.new(0.5, 0)
	statsBox.Position = UDim2.new(0.5, 0, 0, 146)
	statsBox.Size = UDim2.new(1, -24, 0, 130)
	statsBox.BackgroundColor3 = Color3.fromRGB(20, 25, 36)
	statsBox.BorderSizePixel = 0
	statsBox.Parent = rightFrame

	local sbCorner = Instance.new("UICorner")
	sbCorner.CornerRadius = UDim.new(0, 8)
	sbCorner.Parent = statsBox

	local sbPad = Instance.new("UIPadding")
	sbPad.PaddingTop = UDim.new(0, 8)
	sbPad.PaddingBottom = UDim.new(0, 8)
	sbPad.PaddingLeft = UDim.new(0, 12)
	sbPad.PaddingRight = UDim.new(0, 12)
	sbPad.Parent = statsBox

	local statsLbl = Instance.new("TextLabel")
	statsLbl.Name = "StatsLabel"
	statsLbl.Size = UDim2.fromScale(1, 1)
	statsLbl.BackgroundTransparency = 1
	statsLbl.Font = Enum.Font.GothamMedium
	statsLbl.TextSize = 11.5
	statsLbl.TextXAlignment = Enum.TextXAlignment.Left
	statsLbl.TextYAlignment = Enum.TextYAlignment.Top
	statsLbl.TextColor3 = COLORS.TextPrimary
	statsLbl.Text = "Pilih pet untuk melihat statistik."
	statsLbl.Parent = statsBox
	detailStatsLabel = statsLbl

	-- Status banner
	local statusBanner = Instance.new("TextLabel")
	statusBanner.Name = "StatusBanner"
	statusBanner.AnchorPoint = Vector2.new(0.5, 0)
	statusBanner.Position = UDim2.new(0.5, 0, 0, 282)
	statusBanner.Size = UDim2.new(1, -24, 0, 22)
	statusBanner.BackgroundTransparency = 1
	statusBanner.Font = Enum.Font.GothamBold
	statusBanner.TextSize = 11
	statusBanner.TextColor3 = Color3.fromRGB(110, 240, 160)
	statusBanner.Text = ""
	statusBanner.Visible = false
	statusBanner.Parent = rightFrame
	detailStatusBanner = statusBanner

	-- Action buttons container
	local actionsFrame = Instance.new("Frame")
	actionsFrame.Name = "Actions"
	actionsFrame.AnchorPoint = Vector2.new(0.5, 1)
	actionsFrame.Position = UDim2.new(0.5, 0, 1, -12)
	actionsFrame.Size = UDim2.new(1, -24, 0, 154)
	actionsFrame.BackgroundTransparency = 1
	actionsFrame.Parent = rightFrame

	local actionsLayout = Instance.new("UIListLayout")
	actionsLayout.Padding = UDim.new(0, 6)
	actionsLayout.Parent = actionsFrame

	-- 0. Level Up Button
	local lvBtn = Instance.new("TextButton")
	lvBtn.Name = "LevelUpButton"
	lvBtn.Size = UDim2.new(1, 0, 0, 34)
	lvBtn.BackgroundColor3 = Color3.fromRGB(46, 178, 106)
	lvBtn.BorderSizePixel = 0
	lvBtn.Font = Enum.Font.GothamBlack
	lvBtn.TextSize = 12
	lvBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	lvBtn.Text = "LEVEL UP"
	lvBtn.Visible = false
	lvBtn.Parent = actionsFrame
	levelUpButton = lvBtn

	local lvbCorner = Instance.new("UICorner")
	lvbCorner.CornerRadius = UDim.new(0, 8)
	lvbCorner.Parent = lvBtn

	lvBtn.Activated:Connect(function()
		PetBagController.RequestLevelUp()
	end)

	-- 1. Equip Button
	local eqBtn = Instance.new("TextButton")
	eqBtn.Name = "EquipButton"
	eqBtn.Size = UDim2.new(1, 0, 0, 34)
	eqBtn.BackgroundColor3 = COLORS.BtnPrimary
	eqBtn.BorderSizePixel = 0
	eqBtn.Font = Enum.Font.GothamBlack
	eqBtn.TextSize = 12
	eqBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	eqBtn.Text = "EQUIP PET"
	eqBtn.Visible = false
	eqBtn.Parent = actionsFrame
	equipButton = eqBtn

	local eqbCorner = Instance.new("UICorner")
	eqbCorner.CornerRadius = UDim.new(0, 8)
	eqbCorner.Parent = eqBtn

	eqBtn.Activated:Connect(function()
		if not selectedPetGuid then
			return
		end
		local isEquipped = (table.find(equippedPetGuids, selectedPetGuid) ~= nil)
		if isEquipped then
			PetBagController.RequestUnequip()
		else
			PetBagController.RequestEquip()
		end
	end)

	-- 2. Base Button
	local bsBtn = Instance.new("TextButton")
	bsBtn.Name = "BaseButton"
	bsBtn.Size = UDim2.new(1, 0, 0, 34)
	bsBtn.BackgroundColor3 = COLORS.BtnSecondary
	bsBtn.BorderSizePixel = 0
	bsBtn.Font = Enum.Font.GothamBlack
	bsBtn.TextSize = 12
	bsBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	bsBtn.Text = "TARUH KE BASE"
	bsBtn.Visible = false
	bsBtn.Parent = actionsFrame
	baseButton = bsBtn

	local bsbCorner = Instance.new("UICorner")
	bsbCorner.CornerRadius = UDim.new(0, 8)
	bsbCorner.Parent = bsBtn

	bsBtn.Activated:Connect(function()
		if not selectedPetGuid then
			return
		end
		local isInBase = (table.find(basePetGuids, selectedPetGuid) ~= nil)
		if isInBase then
			PetBagController.RequestRemoveBase()
		else
			PetBagController.RequestAssignBase()
		end
	end)

	-- 3. Release Button
	local relBtn = Instance.new("TextButton")
	relBtn.Name = "ReleaseButton"
	relBtn.Size = UDim2.new(1, 0, 0, 32)
	relBtn.BackgroundColor3 = COLORS.BtnDanger
	relBtn.BorderSizePixel = 0
	relBtn.Font = Enum.Font.GothamBold
	relBtn.TextSize = 11
	relBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	relBtn.Text = "LEPAS PET (+$25)"
	relBtn.Visible = false
	relBtn.Parent = actionsFrame
	releaseButton = relBtn

	local relCorner = Instance.new("UICorner")
	relCorner.CornerRadius = UDim.new(0, 8)
	relCorner.Parent = relBtn

	relBtn.Activated:Connect(function()
		PetBagController.RequestRelease()
	end)
end

function PetBagController.Start()
	buildPetBagGui()

	-- Bind viewport resize
	local function bindCameraViewport()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveScale)
			updateResponsiveScale()
		end
	end
	bindCameraViewport()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCameraViewport)

	-- Listen for StateSync
	Remotes.GetEvent("StateSync").OnClientEvent:Connect(function(payload: any)
		PetBagController.ApplySnapshot(payload)
	end)

	-- Register Side Category button "Pets"
	InventoryController.RegisterSideCategory({
		Id = "Pets",
		Order = 2,
		IconText = "PET",
		Label = "PETS",
		OnActivated = function()
			PetBagController.Toggle()
		end,
	})

	-- Initial state fetch
	task.spawn(function()
		local ok, snap = pcall(function()
			return Remotes.GetFunction("GetInventoryState"):InvokeServer()
		end)
		if ok and type(snap) == "table" then
			PetBagController.ApplySnapshot(snap)
		end
	end)
end

return PetBagController
