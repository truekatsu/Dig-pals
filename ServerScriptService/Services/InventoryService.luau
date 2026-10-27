--!strict
-- Server-authoritative item bag, egg bag auto-sell, Merchant selling, and BagLevel upgrades (Step 6)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local EconomyConfig = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))
local BaseConfig = require(Shared:WaitForChild("Config"):WaitForChild("Base"))
local ItemsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Items"))
local EggsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Eggs"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local PlayerState = require(script.Parent:WaitForChild("PlayerState"))

export type SellResult = {
	Success: boolean,
	Reason: string?,
	Message: string?,
	SoldCount: number?,
	CoinsEarned: number?,
	Coins: number?,
	BagItemCount: number?,
	BagCapacity: number?,
}

export type UpgradeBagResult = {
	Success: boolean,
	Reason: string?,
	Message: string?,
	NewBagLevel: number?,
	NewCapacity: number?,
	CostPaid: number?,
	Coins: number?,
}

export type DropMutationTarget = {
	DropType: Types.MoundDropType,
	Id: string,
	DisplayName: string,
	Rarity: Types.RarityName,
	SellPrice: number,
	AutoSold: boolean,
	AutoSoldCoins: number,
}

local MERCHANT_MAX_INTERACT_DISTANCE = 26

local InventoryService = {}

local merchantAnchorParts: { BasePart } = {}
local started = false

function InventoryService.SanitizeInventory(profile: Types.PlayerProfile): boolean
	local changed = false

	-- Clamp BagLevel & BaseLevel within configured bounds
	local clampedBagLevel = math.clamp(math.floor(tonumber(profile.BagLevel) or 1), 1, EconomyConfig.MaxBagLevel)
	if profile.BagLevel ~= clampedBagLevel then
		profile.BagLevel = clampedBagLevel
		changed = true
	end

	local clampedBaseLevel = math.clamp(math.floor(tonumber(profile.BaseLevel) or 1), 1, BaseConfig.MaxBaseLevel)
	if profile.BaseLevel ~= clampedBaseLevel then
		profile.BaseLevel = clampedBaseLevel
		changed = true
	end

	-- Sanitize Items map ([itemId] = positive integer count)
	if type(profile.Items) ~= "table" then
		profile.Items = {}
		changed = true
	else
		for itemId, rawCount in profile.Items do
			local num = tonumber(rawCount)
			local intCount = if num then math.floor(num) else 0
			if type(itemId) ~= "string" or ItemsConfig.All[itemId] == nil or intCount <= 0 then
				profile.Items[itemId] = nil
				changed = true
			elseif intCount ~= rawCount then
				profile.Items[itemId] = intCount
				changed = true
			end
		end
	end

	-- Sanitize EggBag list ({ { Id: string, Rarity: RarityName } })
	if type(profile.EggBag) ~= "table" then
		profile.EggBag = {}
		changed = true
	else
		local eggsChanged = false
		local cleanedEggs: { Types.EggBagEntry } = {}
		for _, rawEntry in profile.EggBag :: { any } do
			if type(rawEntry) == "string" then
				local eggCfg = EggsConfig.All[rawEntry]
				if eggCfg then
					table.insert(cleanedEggs, {
						Id = eggCfg.Id,
						Rarity = eggCfg.Rarity,
					})
				end
				eggsChanged = true
			elseif type(rawEntry) == "table" and type(rawEntry.Id) == "string" then
				local eggCfg = EggsConfig.All[rawEntry.Id]
				if eggCfg then
					local validRarity: Types.RarityName = if type(rawEntry.Rarity) == "string"
						then (rawEntry.Rarity :: Types.RarityName)
						else eggCfg.Rarity
					if rawEntry.Rarity ~= validRarity then
						eggsChanged = true
					end
					table.insert(cleanedEggs, {
						Id = eggCfg.Id,
						Rarity = validRarity,
					})
				else
					eggsChanged = true
				end
			else
				eggsChanged = true
			end
		end
		if eggsChanged then
			profile.EggBag = cleanedEggs
			changed = true
		end
	end

	if profile.Coins < 0 then
		profile.Coins = 0
		changed = true
	end

	return changed
end

function InventoryService.GetBagCapacity(profile: Types.PlayerProfile): number
	local levelInfo = EconomyConfig.BagLevels[profile.BagLevel] or EconomyConfig.BagLevels[1]
	return levelInfo.Capacity
end

function InventoryService.GetBagItemCount(profile: Types.PlayerProfile): number
	local total = 0
	for itemId, count in profile.Items do
		if ItemsConfig.All[itemId] ~= nil and count > 0 then
			total += count
		end
	end
	return total
end

function InventoryService.IsBagFull(profile: Types.PlayerProfile): boolean
	return InventoryService.GetBagItemCount(profile) >= InventoryService.GetBagCapacity(profile)
end

function InventoryService.IsPlayerBagFull(player: Player?): boolean
	if not player then
		return false
	end
	local profile = PlayerState.Get(player)
	if not profile then
		return false
	end
	return InventoryService.IsBagFull(profile)
end

function InventoryService.GetEggBagCapacity(profile: Types.PlayerProfile): number
	return BaseConfig.BaseEggBagCapacity + profile.BaseLevel
end

-- Adds a single rolled drop to a player's profile.
-- Per Step 6 [U]: drops from an in-progress mound ALWAYS enter Items even if count exceeds BagCapacity;
-- Eggs enter EggBag up to (4 + BaseLevel), otherwise auto-sell at Config price with notification metadata.
function InventoryService.AddDropToProfile(profile: Types.PlayerProfile, drop: DropMutationTarget)
	if drop.DropType == "Item" then
		local itemCfg = ItemsConfig.All[drop.Id]
		if not itemCfg then
			return
		end
		profile.Items[itemCfg.Id] = (profile.Items[itemCfg.Id] or 0) + 1
		if profile.Index and profile.Index.Items then
			profile.Index.Items[itemCfg.Id] = true
		end
		drop.SellPrice = itemCfg.SellPrice
		drop.AutoSold = false
		drop.AutoSoldCoins = 0
	elseif drop.DropType == "Egg" then
		local eggCfg = EggsConfig.All[drop.Id]
		if not eggCfg then
			return
		end
		local eggCapacity = InventoryService.GetEggBagCapacity(profile)
		if #profile.EggBag < eggCapacity then
			table.insert(profile.EggBag, {
				Id = eggCfg.Id,
				Rarity = eggCfg.Rarity,
			})
			drop.SellPrice = eggCfg.SellPrice
			drop.AutoSold = false
			drop.AutoSoldCoins = 0
		else
			local autoSellCoins = math.max(0, eggCfg.SellPrice)
			profile.Coins = math.max(0, profile.Coins + autoSellCoins)
			profile.TotalCoinsEarned += autoSellCoins
			drop.SellPrice = eggCfg.SellPrice
			drop.AutoSold = true
			drop.AutoSoldCoins = autoSellCoins
		end
	end
end

function InventoryService.SellItemInProfile(
	profile: Types.PlayerProfile,
	itemId: string,
	count: number
): SellResult
	InventoryService.SanitizeInventory(profile)

	if type(itemId) ~= "string" or ItemsConfig.All[itemId] == nil then
		return {
			Success = false,
			Reason = "InvalidItem",
			Message = "Item tidak valid.",
		}
	end

	if type(count) ~= "number" or count ~= count or math.floor(count) ~= count or count < 1 then
		return {
			Success = false,
			Reason = "InvalidCount",
			Message = "Jumlah jual tidak valid.",
		}
	end

	local ownedCount = profile.Items[itemId] or 0
	if ownedCount <= 0 then
		return {
			Success = false,
			Reason = "ItemNotOwned",
			Message = "Kamu tidak memiliki item ini di tas.",
		}
	end

	if count > ownedCount then
		return {
			Success = false,
			Reason = "InsufficientQuantity",
			Message = string.format("Jumlah item di tas hanya %d.", ownedCount),
		}
	end

	local itemCfg = ItemsConfig.All[itemId]
	local unitPrice = math.max(0, itemCfg.SellPrice)
	local earned = count * unitPrice

	local remaining = ownedCount - count
	if remaining > 0 then
		profile.Items[itemId] = remaining
	else
		profile.Items[itemId] = nil
	end

	profile.Coins = math.max(0, profile.Coins + earned)
	profile.TotalCoinsEarned += earned

	return {
		Success = true,
		SoldCount = count,
		CoinsEarned = earned,
		Coins = profile.Coins,
		BagItemCount = InventoryService.GetBagItemCount(profile),
		BagCapacity = InventoryService.GetBagCapacity(profile),
	}
end

function InventoryService.SellAllItemsInProfile(profile: Types.PlayerProfile): SellResult
	InventoryService.SanitizeInventory(profile)

	local totalSold = 0
	local totalEarned = 0

	for itemId, count in profile.Items do
		local itemCfg = ItemsConfig.All[itemId]
		if itemCfg and count > 0 then
			local unitPrice = math.max(0, itemCfg.SellPrice)
			totalSold += count
			totalEarned += count * unitPrice
		end
	end

	if totalSold <= 0 then
		return {
			Success = false,
			Reason = "BagEmpty",
			Message = "Tas kamu masih kosong.",
			SoldCount = 0,
			CoinsEarned = 0,
			Coins = profile.Coins,
			BagItemCount = 0,
			BagCapacity = InventoryService.GetBagCapacity(profile),
		}
	end

	table.clear(profile.Items)
	profile.Coins = math.max(0, profile.Coins + totalEarned)
	profile.TotalCoinsEarned += totalEarned

	return {
		Success = true,
		SoldCount = totalSold,
		CoinsEarned = totalEarned,
		Coins = profile.Coins,
		BagItemCount = 0,
		BagCapacity = InventoryService.GetBagCapacity(profile),
	}
end

function InventoryService.UpgradeBagInProfile(profile: Types.PlayerProfile): UpgradeBagResult
	InventoryService.SanitizeInventory(profile)

	if profile.BagLevel >= EconomyConfig.MaxBagLevel then
		local maxCap = InventoryService.GetBagCapacity(profile)
		return {
			Success = false,
			Reason = "MaxLevelReached",
			Message = "Kapasitas tas sudah mencapai level maksimal!",
			NewBagLevel = profile.BagLevel,
			NewCapacity = maxCap,
			CostPaid = 0,
			Coins = profile.Coins,
		}
	end

	local nextLevel = profile.BagLevel + 1
	local nextConfig = EconomyConfig.BagLevels[nextLevel]
	if not nextConfig then
		return {
			Success = false,
			Reason = "ConfigMissing",
			Message = "Konfigurasi level tas tidak ditemukan.",
		}
	end

	local cost = math.max(0, nextConfig.UpgradeCost)
	if profile.Coins < cost then
		return {
			Success = false,
			Reason = "InsufficientCoins",
			Message = string.format("Coin belum cukup! Butuh %d Coin.", cost),
			NewBagLevel = profile.BagLevel,
			NewCapacity = InventoryService.GetBagCapacity(profile),
			CostPaid = 0,
			Coins = profile.Coins,
		}
	end

	profile.Coins = math.max(0, profile.Coins - cost)
	profile.BagLevel = nextLevel

	return {
		Success = true,
		NewBagLevel = nextLevel,
		NewCapacity = nextConfig.Capacity,
		CostPaid = cost,
		Coins = profile.Coins,
	}
end

local function createMerchantBillboard(parent: BasePart, titleText: string, subText: string, studOffset: Vector3)
	local existing = parent:FindFirstChild("MerchantSignGui")
	if existing then
		existing:Destroy()
	end

	local bb = Instance.new("BillboardGui")
	bb.Name = "MerchantSignGui"
	bb.Adornee = parent
	bb.Size = UDim2.fromOffset(200, 50)
	bb.StudsOffset = studOffset
	bb.AlwaysOnTop = false
	bb.MaxDistance = 65
	bb.Parent = parent

	local bg = Instance.new("Frame")
	bg.Name = "Card"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
	bg.BackgroundTransparency = 0.12
	bg.BorderSizePixel = 0
	bg.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = bg

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(250, 204, 72)
	stroke.Thickness = 1.8
	stroke.Parent = bg

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(6, 4)
	title.Size = UDim2.new(1, -12, 0, 22)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 14
	title.TextColor3 = Color3.fromRGB(255, 216, 92)
	title.Text = titleText
	title.Parent = bg

	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.Position = UDim2.fromOffset(6, 25)
	sub.Size = UDim2.new(1, -12, 0, 18)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamBold
	sub.TextSize = 11
	sub.TextColor3 = Color3.fromRGB(220, 228, 244)
	sub.Text = subText
	sub.Parent = bg
end

local function attachMerchantPrompt(
	anchorPart: BasePart,
	locationKind: string,
	objectText: string,
	actionText: string,
	promptOffset: Vector3
)
	anchorPart:SetAttribute("DigPalsMerchantNode", true)
	anchorPart:SetAttribute("MerchantLocation", locationKind)

	local existingAtt = anchorPart:FindFirstChild("MerchantPromptAttachment")
	if existingAtt then
		existingAtt:Destroy()
	end
	local oldPrompt = anchorPart:FindFirstChildOfClass("ProximityPrompt")
	if oldPrompt then
		oldPrompt:Destroy()
	end

	local att = Instance.new("Attachment")
	att.Name = "MerchantPromptAttachment"
	att.Position = promptOffset
	att.Parent = anchorPart

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "MerchantProximityPrompt"
	prompt.ObjectText = objectText
	prompt.ActionText = actionText
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.Parent = att

	table.insert(merchantAnchorParts, anchorPart)
end

local function ensureBasePlotMerchantKiosk(plotModel: Instance, plotIndex: number)
	local groundName = string.format("Plot%d_Ground", plotIndex)
	local ground = plotModel:FindFirstChild(groundName)
	if not ground or not ground:IsA("BasePart") then
		return
	end

	local existingKiosk = plotModel:FindFirstChild("BaseMerchant")
	local kioskModel: Model
	local chestBase: BasePart

	if existingKiosk and existingKiosk:IsA("Model") then
		kioskModel = existingKiosk
		local found = kioskModel:FindFirstChild("MerchantChest")
		if found and found:IsA("BasePart") then
			chestBase = found
		else
			existingKiosk:Destroy()
			return ensureBasePlotMerchantKiosk(plotModel, plotIndex)
		end
	else
		if existingKiosk then
			existingKiosk:Destroy()
		end

		-- Place compact kiosk inside front-corner of plot, leaving plot center clear for Step 8
		local frontDir = ground.CFrame.RightVector
		local sideDir = ground.CFrame.LookVector
		local groundTopY = ground.Position.Y + (ground.Size.Y * 0.5)
		local kioskPos = Vector3.new(ground.Position.X, groundTopY, ground.Position.Z)
			+ (frontDir * 13.5)
			+ (sideDir * 13.5)
		local lookTarget = Vector3.new(ground.Position.X, groundTopY, ground.Position.Z) + (frontDir * 8.0)
		local baseCf = CFrame.lookAt(kioskPos, lookTarget)

		kioskModel = Instance.new("Model")
		kioskModel.Name = "BaseMerchant"

		local platform = Instance.new("Part")
		platform.Name = "Pedestal"
		platform.Size = Vector3.new(4.2, 0.4, 3.2)
		platform.Color = Color3.fromRGB(122, 118, 128)
		platform.Material = Enum.Material.Cobblestone
		platform.Anchored = true
		platform.CanCollide = true
		platform.CFrame = baseCf * CFrame.new(0, 0.2, 0)
		platform.Parent = kioskModel

		local body = Instance.new("Part")
		body.Name = "MerchantChest"
		body.Size = Vector3.new(3.2, 2.1, 2.2)
		body.Color = Color3.fromRGB(132, 84, 46)
		body.Material = Enum.Material.WoodPlanks
		body.Anchored = true
		body.CanCollide = true
		body.CFrame = baseCf * CFrame.new(0, 1.45, 0)
		body.Parent = kioskModel
		chestBase = body

		local trim = Instance.new("Part")
		trim.Name = "GoldTrim"
		trim.Size = Vector3.new(3.32, 0.35, 2.32)
		trim.Color = Color3.fromRGB(238, 188, 58)
		trim.Material = Enum.Material.SmoothPlastic
		trim.Anchored = true
		trim.CanCollide = false
		trim.CFrame = baseCf * CFrame.new(0, 2.35, 0)
		trim.Parent = kioskModel

		local clasp = Instance.new("Part")
		clasp.Name = "CoinClasp"
		clasp.Size = Vector3.new(0.65, 0.75, 0.2)
		clasp.Color = Color3.fromRGB(252, 208, 72)
		clasp.Material = Enum.Material.Neon
		clasp.Anchored = true
		clasp.CanCollide = false
		clasp.CFrame = baseCf * CFrame.new(0, 1.95, -1.12)
		clasp.Parent = kioskModel

		kioskModel.PrimaryPart = body
		kioskModel.Parent = plotModel
	end

	createMerchantBillboard(chestBase, "BASE MERCHANT", "Jual Item & Upgrade Tas", Vector3.new(0, 2.8, 0))
	attachMerchantPrompt(
		chestBase,
		string.format("BasePlot%d", plotIndex),
		"Base Merchant",
		"Jual Item & Upgrade Tas",
		Vector3.new(0, 0.8, 0)
	)
end

function InventoryService.EnsureMerchantWorldPrompts()
	table.clear(merchantAnchorParts)

	-- 1. Hub Item Merchant (Workspace.Plain.Merchant.ItemMerchant_Counter)
	local plain = workspace:FindFirstChild("Plain")
	local merchantFolder = plain and plain:FindFirstChild("Merchant")
	local hubCounter = merchantFolder and merchantFolder:FindFirstChild("ItemMerchant_Counter")
	if hubCounter and hubCounter:IsA("BasePart") then
		createMerchantBillboard(hubCounter, "ITEM MERCHANT", "Jual Hasil Galian & Upgrade Tas", Vector3.new(0, 4.4, 0))
		attachMerchantPrompt(
			hubCounter,
			"Hub",
			"Item Merchant",
			"Buka Toko Jual & Tas",
			Vector3.new(0, 1.8, 0)
		)
	end

	-- 2. Base Merchants inside Plot1..Plot6 (Workspace.BasePlots)
	local basePlots = workspace:FindFirstChild("BasePlots")
	if basePlots then
		for plotIndex = 1, 6 do
			local plotModel = basePlots:FindFirstChild("Plot" .. tostring(plotIndex))
			if plotModel then
				ensureBasePlotMerchantKiosk(plotModel, plotIndex)
			end
		end
	end
end

function InventoryService.GetMerchantAnchorCount(): number
	return #merchantAnchorParts
end

function InventoryService.IsPlayerNearMerchant(player: Player, posOverride: Vector3?): boolean
	local pos = posOverride
	if not pos then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			pos = root.Position
		end
	end
	if not pos then
		return false
	end

	for _, part in merchantAnchorParts do
		if part.Parent ~= nil then
			local dx = pos.X - part.Position.X
			local dz = pos.Z - part.Position.Z
			local horizDist = math.sqrt(dx * dx + dz * dz)
			if horizDist <= MERCHANT_MAX_INTERACT_DISTANCE then
				return true
			end
		end
	end
	return false
end

function InventoryService.SellItem(
	player: Player,
	itemId: string,
	count: number,
	bypassProximityForTest: boolean?
): SellResult
	if not bypassProximityForTest and not InventoryService.IsPlayerNearMerchant(player) then
		return {
			Success = false,
			Reason = "TooFarFromMerchant",
			Message = "Dekati Item Merchant di Hub atau Base terlebih dahulu.",
		}
	end

	local profile = PlayerState.Get(player)
	if not profile then
		return {
			Success = false,
			Reason = "ProfileNotLoaded",
			Message = "Data pemain sedang dimuat.",
		}
	end

	local result: SellResult = {
		Success = false,
		Reason = "Unknown",
	}

	local mutated = PlayerState.Mutate(player, function(prof: Types.PlayerProfile)
		result = InventoryService.SellItemInProfile(prof, itemId, count)
	end)

	if not mutated then
		return {
			Success = false,
			Reason = "MutateFailed",
			Message = "Gagal memproses penjualan item.",
		}
	end

	return result
end

function InventoryService.SellAllItems(player: Player, bypassProximityForTest: boolean?): SellResult
	if not bypassProximityForTest and not InventoryService.IsPlayerNearMerchant(player) then
		return {
			Success = false,
			Reason = "TooFarFromMerchant",
			Message = "Dekati Item Merchant di Hub atau Base terlebih dahulu.",
		}
	end

	local profile = PlayerState.Get(player)
	if not profile then
		return {
			Success = false,
			Reason = "ProfileNotLoaded",
			Message = "Data pemain sedang dimuat.",
		}
	end

	local result: SellResult = {
		Success = false,
		Reason = "Unknown",
	}

	local mutated = PlayerState.Mutate(player, function(prof: Types.PlayerProfile)
		result = InventoryService.SellAllItemsInProfile(prof)
	end)

	if not mutated then
		return {
			Success = false,
			Reason = "MutateFailed",
			Message = "Gagal menjual isi tas.",
		}
	end

	return result
end

function InventoryService.UpgradeBag(player: Player, bypassProximityForTest: boolean?): UpgradeBagResult
	if not bypassProximityForTest and not InventoryService.IsPlayerNearMerchant(player) then
		return {
			Success = false,
			Reason = "TooFarFromMerchant",
			Message = "Dekati Item Merchant di Hub atau Base terlebih dahulu.",
		}
	end

	local profile = PlayerState.Get(player)
	if not profile then
		return {
			Success = false,
			Reason = "ProfileNotLoaded",
			Message = "Data pemain sedang dimuat.",
		}
	end

	local result: UpgradeBagResult = {
		Success = false,
		Reason = "Unknown",
	}

	local mutated = PlayerState.Mutate(player, function(prof: Types.PlayerProfile)
		result = InventoryService.UpgradeBagInProfile(prof)
	end)

	if not mutated then
		return {
			Success = false,
			Reason = "MutateFailed",
			Message = "Gagal meng-upgrade kapasitas tas.",
		}
	end

	if result.Success then
		DataService.SavePlayer(player)
	end

	return result
end

local function setupDebugBagCommands()
	local existing = TextChatService:FindFirstChild("DebugGiveItemCommand")
	if existing and existing:IsA("TextChatCommand") then
		return
	end

	local cmd = Instance.new("TextChatCommand")
	cmd.Name = "DebugGiveItemCommand"
	cmd.PrimaryAlias = "/giveitem"
	cmd.Parent = TextChatService

	cmd.Triggered:Connect(function(textSource: TextSource, unfilteredText: string)
		local player = Players:GetPlayerByUserId(textSource.UserId)
		if not player or not PlayerState.IsAuthorizedForDebug(player) then
			return
		end
		local trimmed = string.gsub(unfilteredText, "^%s*(.-)%s*$", "%1")
		local parts = string.split(trimmed, " ")
		local argId = parts[2] or "Pebble"
		local argCount = math.clamp(math.floor(tonumber(parts[3]) or 1), 1, 200)

		if string.lower(argId) == "fill" then
			PlayerState.Mutate(player, function(prof: Types.PlayerProfile)
				local cap = InventoryService.GetBagCapacity(prof)
				local cur = InventoryService.GetBagItemCount(prof)
				local needed = math.max(0, cap - cur)
				if needed > 0 then
					prof.Items["Pebble"] = (prof.Items["Pebble"] or 0) + needed
					prof.Index.Items["Pebble"] = true
				end
			end)
			print(string.format("[InventoryService] Filled bag to capacity for %s", player.Name))
		elseif ItemsConfig.All[argId] ~= nil then
			PlayerState.Mutate(player, function(prof: Types.PlayerProfile)
				prof.Items[argId] = (prof.Items[argId] or 0) + argCount
				prof.Index.Items[argId] = true
			end)
			print(string.format("[InventoryService] Granted %dx %s to %s", argCount, argId, player.Name))
		end
	end)
end

function InventoryService.Start()
	if started then
		return
	end
	started = true

	InventoryService.EnsureMerchantWorldPrompts()
	setupDebugBagCommands()

	DataService.OnProfileLoaded(function(player: Player, profile: Types.PlayerProfile)
		local changed = InventoryService.SanitizeInventory(profile)
		if changed then
			PlayerState.SyncAttributes(player, profile)
		end
	end)

	Remotes.OnServerInvoke("SellItem", function(player: Player, itemId: string, count: number): SellResult
		return InventoryService.SellItem(player, itemId, count, false)
	end)

	Remotes.OnServerInvoke("SellAllItems", function(player: Player): SellResult
		return InventoryService.SellAllItems(player, false)
	end)

	Remotes.OnServerInvoke("UpgradeBag", function(player: Player): UpgradeBagResult
		return InventoryService.UpgradeBag(player, false)
	end)
end

return InventoryService
