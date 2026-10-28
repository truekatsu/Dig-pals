--!strict
-- Authoritative Index Service: tracks pet/item discoveries, rarity completion bonuses, and Master Excavator title (Step 12)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local RarityConfig = require(Shared:WaitForChild("Config"):WaitForChild("Rarity"))
local ItemsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Items"))
local PetsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Pets"))

export type RarityCompletionStatus = {
	Rarity: Types.RarityName,
	Discovered: number,
	Total: number,
	IsComplete: boolean,
}

export type IndexProgressSummary = {
	Items: {
		TotalDiscovered: number,
		TotalItems: number,
		LuckBonus: number,
		Rarities: { [Types.RarityName]: RarityCompletionStatus },
		CompletedRarityCount: number,
	},
	Pets: {
		TotalDiscovered: number,
		TotalPets: number,
		IncomeBonus: number,
		Rarities: { [Types.RarityName]: RarityCompletionStatus },
		CompletedRarityCount: number,
	},
	IsAllComplete: boolean,
	Title: string?,
}

local IndexService = {}

local itemsByRarity: { [Types.RarityName]: { Types.ItemConfig } } = {
	Common = {},
	Uncommon = {},
	Rare = {},
	Epic = {},
	Legendary = {},
}

local petsByRarity: { [Types.RarityName]: { Types.PetSpeciesConfig } } = {
	Common = {},
	Uncommon = {},
	Rare = {},
	Epic = {},
	Legendary = {},
}

local totalItemCount = 0
local totalPetCount = 0
local started = false

local function initPools()
	for _, r in ipairs(RarityConfig.Order) do
		itemsByRarity[r] = {}
		petsByRarity[r] = {}
	end

	for _, itemCfg in pairs(ItemsConfig.All) do
		local bucket = itemsByRarity[itemCfg.Rarity]
		if bucket then
			table.insert(bucket, itemCfg)
			totalItemCount += 1
		end
	end

	for _, speciesCfg in pairs(PetsConfig.Species) do
		local bucket = petsByRarity[speciesCfg.Rarity]
		if bucket then
			table.insert(bucket, speciesCfg)
			totalPetCount += 1
		end
	end

	for _, bucket in pairs(itemsByRarity) do
		table.sort(bucket, function(a, b)
			return a.Id < b.Id
		end)
	end

	for _, bucket in pairs(petsByRarity) do
		table.sort(bucket, function(a, b)
			return a.Id < b.Id
		end)
	end
end

initPools()

local function ensureIndexTables(profile: Types.PlayerProfile)
	if type(profile.Index) ~= "table" then
		profile.Index = { Pets = {}, Items = {} }
	end
	if type(profile.Index.Pets) ~= "table" then
		profile.Index.Pets = {}
	end
	if type(profile.Index.Items) ~= "table" then
		profile.Index.Items = {}
	end
	local raw = profile.Index :: any
	if type(raw.NotifiedRarities) ~= "table" then
		raw.NotifiedRarities = { Items = {}, Pets = {}, All = false }
	end
end

function IndexService.IsItemRarityComplete(profile: Types.PlayerProfile?, rarity: Types.RarityName): (boolean, number, number)
	if not profile or not profile.Index or not profile.Index.Items then
		return false, 0, #itemsByRarity[rarity]
	end
	local pool = itemsByRarity[rarity]
	if not pool or #pool == 0 then
		return false, 0, 0
	end
	local discovered = 0
	for _, item in ipairs(pool) do
		if profile.Index.Items[item.Id] then
			discovered += 1
		end
	end
	return discovered == #pool, discovered, #pool
end

function IndexService.IsPetRarityComplete(profile: Types.PlayerProfile?, rarity: Types.RarityName): (boolean, number, number)
	if not profile or not profile.Index or not profile.Index.Pets then
		return false, 0, #petsByRarity[rarity]
	end
	local pool = petsByRarity[rarity]
	if not pool or #pool == 0 then
		return false, 0, 0
	end
	local discovered = 0
	for _, pet in ipairs(pool) do
		if profile.Index.Pets[pet.Id] then
			discovered += 1
		end
	end
	return discovered == #pool, discovered, #pool
end

function IndexService.ComputeItemIndexLuckBonus(profile: Types.PlayerProfile?): number
	if not profile or not profile.Index or not profile.Index.Items then
		return 0
	end
	local bonus = 0
	for _, rarity in ipairs(RarityConfig.Order) do
		local isComplete = IndexService.IsItemRarityComplete(profile, rarity)
		if isComplete then
			bonus += RarityConfig.IndexRewards.ItemRarityLuckBonus
		end
	end
	return bonus
end

function IndexService.ComputePetIndexIncomeBonus(profile: Types.PlayerProfile?): number
	if not profile or not profile.Index or not profile.Index.Pets then
		return 0
	end
	local bonus = 0
	for _, rarity in ipairs(RarityConfig.Order) do
		local isComplete = IndexService.IsPetRarityComplete(profile, rarity)
		if isComplete then
			bonus += RarityConfig.IndexRewards.PetRarityIncomeBonus
		end
	end
	return bonus
end

function IndexService.IsAllComplete(profile: Types.PlayerProfile?): boolean
	if not profile then
		return false
	end
	for _, rarity in ipairs(RarityConfig.Order) do
		if not IndexService.IsItemRarityComplete(profile, rarity) then
			return false
		end
		if not IndexService.IsPetRarityComplete(profile, rarity) then
			return false
		end
	end
	return true
end

function IndexService.GetIndexProgress(profile: Types.PlayerProfile?): IndexProgressSummary
	local itemRarities: { [Types.RarityName]: RarityCompletionStatus } = {}
	local totalItemDiscovered = 0
	local completedItemRarities = 0

	for _, rarity in ipairs(RarityConfig.Order) do
		local isComp, disc, total = IndexService.IsItemRarityComplete(profile, rarity)
		itemRarities[rarity] = {
			Rarity = rarity,
			Discovered = disc,
			Total = total,
			IsComplete = isComp,
		}
		totalItemDiscovered += disc
		if isComp then
			completedItemRarities += 1
		end
	end

	local petRarities: { [Types.RarityName]: RarityCompletionStatus } = {}
	local totalPetDiscovered = 0
	local completedPetRarities = 0

	for _, rarity in ipairs(RarityConfig.Order) do
		local isComp, disc, total = IndexService.IsPetRarityComplete(profile, rarity)
		petRarities[rarity] = {
			Rarity = rarity,
			Discovered = disc,
			Total = total,
			IsComplete = isComp,
		}
		totalPetDiscovered += disc
		if isComp then
			completedPetRarities += 1
		end
	end

	local allComplete = (completedItemRarities == #RarityConfig.Order) and (completedPetRarities == #RarityConfig.Order)

	return {
		Items = {
			TotalDiscovered = totalItemDiscovered,
			TotalItems = totalItemCount,
			LuckBonus = completedItemRarities * RarityConfig.IndexRewards.ItemRarityLuckBonus,
			Rarities = itemRarities,
			CompletedRarityCount = completedItemRarities,
		},
		Pets = {
			TotalDiscovered = totalPetDiscovered,
			TotalPets = totalPetCount,
			IncomeBonus = completedPetRarities * RarityConfig.IndexRewards.PetRarityIncomeBonus,
			Rarities = petRarities,
			CompletedRarityCount = completedPetRarities,
		},
		IsAllComplete = allComplete,
		Title = if allComplete then RarityConfig.IndexRewards.CompleteAllTitle else nil,
	}
end

function IndexService.RegisterItemDiscovery(
	player: Player?,
	profile: Types.PlayerProfile,
	itemId: string
): (boolean, { string }, boolean)
	ensureIndexTables(profile)
	local isNew = not profile.Index.Items[itemId]
	profile.Index.Items[itemId] = true

	local newlyCompleted: { string } = {}
	local raw = profile.Index :: any

	if isNew then
		for _, rarity in ipairs(RarityConfig.Order) do
			if not raw.NotifiedRarities.Items[rarity] then
				local isComp = IndexService.IsItemRarityComplete(profile, rarity)
				if isComp then
					raw.NotifiedRarities.Items[rarity] = true
					table.insert(newlyCompleted, rarity)

					if player and player.Parent == Players then
						Remotes.GetEvent("IndexAlert"):FireClient(player, {
							Type = "ItemRarityComplete",
							Rarity = rarity,
							BonusText = string.format("+%.2f Luck Permanen", RarityConfig.IndexRewards.ItemRarityLuckBonus),
							Message = string.format("Index Selesai: Semua Item %s Ditemukan! (+%.2f Luck)", rarity, RarityConfig.IndexRewards.ItemRarityLuckBonus),
						})
					end
					print(string.format("[IndexService] Player %s completed Item Rarity: %s (+%.2f Luck)", if player then player.Name else "Test", rarity, RarityConfig.IndexRewards.ItemRarityLuckBonus))
				end
			end
		end
	end

	local allComp = IndexService.IsAllComplete(profile)
	if allComp and not raw.NotifiedRarities.All then
		raw.NotifiedRarities.All = true
		local title = RarityConfig.IndexRewards.CompleteAllTitle
		if player then
			player:SetAttribute("Title", title)
			if player.Parent == Players then
				Remotes.GetEvent("IndexAlert"):FireClient(player, {
					Type = "AllComplete",
					Title = title,
					Message = string.format("Luar Biasa! Seluruh Index Lengkap! Gelar Dibuka: %s", title),
				})
			end
		end
		print(string.format("[IndexService] Player %s unlocked Title: %s!", if player then player.Name else "Test", title))
	end

	return isNew, newlyCompleted, allComp
end

function IndexService.RegisterPetDiscovery(
	player: Player?,
	profile: Types.PlayerProfile,
	speciesId: string
): (boolean, { string }, boolean)
	ensureIndexTables(profile)
	local isNew = not profile.Index.Pets[speciesId]
	profile.Index.Pets[speciesId] = true

	local newlyCompleted: { string } = {}
	local raw = profile.Index :: any

	if isNew then
		for _, rarity in ipairs(RarityConfig.Order) do
			if not raw.NotifiedRarities.Pets[rarity] then
				local isComp = IndexService.IsPetRarityComplete(profile, rarity)
				if isComp then
					raw.NotifiedRarities.Pets[rarity] = true
					table.insert(newlyCompleted, rarity)

					local pct = math.floor(RarityConfig.IndexRewards.PetRarityIncomeBonus * 100)
					if player and player.Parent == Players then
						Remotes.GetEvent("IndexAlert"):FireClient(player, {
							Type = "PetRarityComplete",
							Rarity = rarity,
							BonusText = string.format("+%d%% Income Permanen", pct),
							Message = string.format("Index Selesai: Semua Pet %s Ditemukan! (+%d%% Income)", rarity, pct),
						})
					end
					print(string.format("[IndexService] Player %s completed Pet Rarity: %s (+%d%% Income)", if player then player.Name else "Test", rarity, pct))
				end
			end
		end
	end

	local allComp = IndexService.IsAllComplete(profile)
	if allComp and not raw.NotifiedRarities.All then
		raw.NotifiedRarities.All = true
		local title = RarityConfig.IndexRewards.CompleteAllTitle
		if player then
			player:SetAttribute("Title", title)
			if player.Parent == Players then
				Remotes.GetEvent("IndexAlert"):FireClient(player, {
					Type = "AllComplete",
					Title = title,
					Message = string.format("Luar Biasa! Seluruh Index Lengkap! Gelar Dibuka: %s", title),
				})
			end
		end
		print(string.format("[IndexService] Player %s unlocked Title: %s!", if player then player.Name else "Test", title))
	end

	return isNew, newlyCompleted, allComp
end

function IndexService.Start()
	if started then
		return
	end
	started = true

	Remotes.OnServerInvoke("GetIndexData", function(player: Player)
		local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
		local profile = PlayerState.Get(player)
		if not profile then
			return nil
		end
		return IndexService.GetIndexProgress(profile)
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
		local profile = PlayerState.Get(player)
		if profile and IndexService.IsAllComplete(profile) then
			player:SetAttribute("Title", RarityConfig.IndexRewards.CompleteAllTitle)
		end
	end)
end

return IndexService
