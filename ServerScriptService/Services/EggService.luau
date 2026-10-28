--!strict
-- Server-authoritative Egg incubation, speed-up calculation, hatching with shovel Luck, variant rolls, and egg sales (Step 8)

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))
local Weighted = require(Shared:WaitForChild("Util"):WaitForChild("Weighted"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local BaseConfig = require(Shared:WaitForChild("Config"):WaitForChild("Base"))
local EggsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Eggs"))
local PetsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Pets"))
local ShovelsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Shovels"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
local ShovelInventoryService = require(script.Parent:WaitForChild("ShovelInventoryService"))

export type PlaceEggResult = {
	Success: boolean,
	Reason: string?,
	Message: string?,
	SlotIndex: number?,
	EggId: string?,
	ReadyAt: number?,
}

export type SpeedUpResult = {
	Success: boolean,
	Reason: string?,
	Message: string?,
	SlotIndex: number?,
	CostPaid: number?,
	CoinsRemaining: number?,
	ReadyAt: number?,
}

export type HatchResult = {
	Success: boolean,
	Reason: string?,
	Message: string?,
	SlotIndex: number?,
	PetGuid: string?,
	Species: string?,
	Variant: Types.PetVariantName?,
	Rarity: Types.RarityName?,
	Level: number?,
}

export type SellEggResult = {
	Success: boolean,
	Reason: string?,
	Message: string?,
	EggId: string?,
	CoinsEarned: number?,
	CoinsRemaining: number?,
}

export type EggSimulationReport = {
	EggId: string,
	TotalRolls: number,
	RarityCounts: { [Types.RarityName]: number },
	RarityPercentages: { [Types.RarityName]: number },
	VariantCounts: { [Types.PetVariantName]: number },
	VariantPercentages: { [Types.PetVariantName]: number },
}

local EggService = {}
local started = false

-- Pure helper: Get max incubator slots for a base level
function EggService.GetMaxIncubatorSlots(baseLevel: number): number
	local cfg = BaseConfig.Levels[baseLevel] or BaseConfig.Levels[1]
	return cfg.IncubatorSlots
end

-- Pure helper: Compute speed-up cost in Coins for an active incubator
function EggService.ComputeSpeedUpCost(entry: Types.IncubatorEntry, now: number): number
	if now >= entry.ReadyAt then
		return 0
	end
	local remainingSec = math.max(0, entry.ReadyAt - now)
	local remainingMin = math.ceil(remainingSec / 60)
	local eggCfg = EggsConfig.All[entry.Id]
	local rate = if eggCfg then eggCfg.SpeedUpCostPerMinute else 25
	return remainingMin * rate
end

-- Pure helper: Roll pet species within a rarity
function EggService.PickSpeciesForRarity(eggId: string, rarity: Types.RarityName, rng: Random): string
	if eggId == "StarterEgg" then
		-- Starter Egg has explicit species weights in Config (Dog 50%, Cat 50%)
		local starterCfg = EggsConfig.All.StarterEgg
		local weights = starterCfg.SpeciesWeights
		local raw = Weighted.Pick(weights, rng)
		return if raw and #raw > 0 then raw else "Dog"
	end

	-- For standard eggs: uniform roll among all species configured for that rarity
	local candidates: { string } = {}
	for speciesId, speciesCfg in PetsConfig.Species do
		if speciesCfg.Rarity == rarity then
			table.insert(candidates, speciesId)
		end
	end
	table.sort(candidates) -- deterministic ordering before picking

	if #candidates == 0 then
		return "Dog"
	end
	local index = rng:NextInteger(1, #candidates)
	return candidates[index]
end

-- Pure helper: Roll variant (Golden 5%, Shiny 1%, Normal 94% -- TANPA Luck per PRD)
function EggService.RollVariant(rng: Random): Types.PetVariantName
	local roll = rng:NextInteger(1, 100)
	if roll <= 1 then
		return "Shiny"
	elseif roll <= 6 then
		return "Golden"
	else
		return "Normal"
	end
end

-- Pure helper: Count current pets in profile
function EggService.GetPetCount(profile: Types.PlayerProfile): number
	local count = 0
	for _, _ in profile.Pets do
		count += 1
	end
	return count
end

-- Place egg from EggBag into incubator slot
function EggService.PlaceEggInIncubatorInProfile(
	profile: Types.PlayerProfile,
	eggBagIndex: number,
	slotIndex: number,
	nowOverride: number?
): PlaceEggResult
	local maxSlots = EggService.GetMaxIncubatorSlots(profile.BaseLevel)
	if slotIndex < 1 or slotIndex > maxSlots then
		return {
			Success = false,
			Reason = "InvalidSlot",
			Message = string.format("Slot inkubator tidak valid (tersedia 1-%d).", maxSlots),
		}
	end

	if profile.Incubators[slotIndex] ~= nil then
		return {
			Success = false,
			Reason = "SlotOccupied",
			Message = "Slot inkubator ini sudah terisi telur.",
		}
	end

	local eggEntry = profile.EggBag[eggBagIndex]
	if not eggEntry then
		return {
			Success = false,
			Reason = "EggNotFound",
			Message = "Telur tidak ditemukan di Tas Telur.",
		}
	end

	local eggCfg = EggsConfig.All[eggEntry.Id]
	if not eggCfg then
		return {
			Success = false,
			Reason = "InvalidEgg",
			Message = "Konfigurasi telur tidak valid.",
		}
	end

	local now = nowOverride or os.time()
	local readyAt = now + eggCfg.IncubationSeconds

	-- Remove from EggBag
	table.remove(profile.EggBag, eggBagIndex)

	-- Place in Incubator
	profile.Incubators[slotIndex] = {
		Id = eggEntry.Id,
		Rarity = eggEntry.Rarity,
		ReadyAt = readyAt,
	}

	return {
		Success = true,
		SlotIndex = slotIndex,
		EggId = eggEntry.Id,
		ReadyAt = readyAt,
	}
end

-- Speed up incubator with coins
function EggService.SpeedUpIncubatorInProfile(
	profile: Types.PlayerProfile,
	slotIndex: number,
	nowOverride: number?
): SpeedUpResult
	local entry = profile.Incubators[slotIndex]
	if not entry then
		return {
			Success = false,
			Reason = "SlotEmpty",
			Message = "Tidak ada telur di slot inkubator ini.",
		}
	end

	local now = nowOverride or os.time()
	local cost = EggService.ComputeSpeedUpCost(entry, now)

	if cost == 0 or now >= entry.ReadyAt then
		return {
			Success = true,
			SlotIndex = slotIndex,
			CostPaid = 0,
			CoinsRemaining = profile.Coins,
			ReadyAt = entry.ReadyAt,
			Message = "Telur sudah siap ditetaskan!",
		}
	end

	if profile.Coins < cost then
		return {
			Success = false,
			Reason = "InsufficientCoins",
			Message = string.format("Coin belum cukup untuk mempercepat! Butuh %d Coin.", cost),
		}
	end

	profile.Coins = math.max(0, profile.Coins - cost)
	entry.ReadyAt = now

	return {
		Success = true,
		SlotIndex = slotIndex,
		CostPaid = cost,
		CoinsRemaining = profile.Coins,
		ReadyAt = now,
	}
end

-- Hatch incubator when ready
function EggService.HatchIncubatorInProfile(
	profile: Types.PlayerProfile,
	slotIndex: number,
	nowOverride: number?,
	shovelLuckOverride: number?,
	rngOverride: Random?
): HatchResult
	local entry = profile.Incubators[slotIndex]
	if not entry then
		return {
			Success = false,
			Reason = "SlotEmpty",
			Message = "Tidak ada telur di slot inkubator ini.",
		}
	end

	local now = nowOverride or os.time()
	if now < entry.ReadyAt then
		local remaining = entry.ReadyAt - now
		return {
			Success = false,
			Reason = "NotReady",
			Message = string.format("Telur belum siap ditetaskan (%d detik tersisa).", remaining),
		}
	end

	-- Check pet bag capacity (max 60)
	if EggService.GetPetCount(profile) >= PetsConfig.MaxPetBagCapacity then
		return {
			Success = false,
			Reason = "PetBagFull",
			Message = string.format("Tas Pet penuh (maks %d). Lepas pet terlebih dahulu.", PetsConfig.MaxPetBagCapacity),
		}
	end

	local eggCfg = EggsConfig.All[entry.Id]
	if not eggCfg then
		return {
			Success = false,
			Reason = "InvalidEgg",
			Message = "Konfigurasi telur tidak ditemukan.",
		}
	end

	local rng = rngOverride or Random.new()

	-- Determine shovel Luck [U]: Luck of currently equipped shovel applies to egg hatch rarity weights
	local shovelLuck = shovelLuckOverride
	if shovelLuck == nil then
		local equippedShovelId = profile.Shovels and profile.Shovels.Equipped
		local shovelCfg = equippedShovelId and ShovelsConfig.All[equippedShovelId]
		shovelLuck = if shovelCfg then shovelCfg.Luck else 1.0
	end

	-- Apply luck to egg's rarity weights
	local adjustedWeights = Weighted.ApplyLuck(eggCfg.RarityWeights, shovelLuck :: number)
	local rolledRarityRaw = Weighted.Pick(adjustedWeights, rng)
	local rolledRarity: Types.RarityName = if rolledRarityRaw and #rolledRarityRaw > 0
		then (rolledRarityRaw :: Types.RarityName)
		else "Common"

	-- Pick species uniformly within that rarity
	local species = EggService.PickSpeciesForRarity(entry.Id, rolledRarity, rng)

	-- Roll variant (Normal 94%, Golden 5%, Shiny 1% without luck)
	local variant = EggService.RollVariant(rng)

	-- Create new pet instance
	local petGuid = "Pet_" .. HttpService:GenerateGUID(false)
	profile.Pets[petGuid] = {
		Species = species,
		Variant = variant,
		Level = 1,
	}

	-- Add to index
	if not profile.Index then
		profile.Index = { Pets = {}, Items = {} }
	end
	if not profile.Index.Pets then
		profile.Index.Pets = {}
	end
	profile.Index.Pets[species] = true

	-- Clear incubator slot
	profile.Incubators[slotIndex] = nil

	return {
		Success = true,
		SlotIndex = slotIndex,
		PetGuid = petGuid,
		Species = species,
		Variant = variant,
		Rarity = rolledRarity,
		Level = 1,
	}
end

-- Sell egg directly from EggBag
function EggService.SellEggInProfile(
	profile: Types.PlayerProfile,
	eggBagIndex: number
): SellEggResult
	local entry = profile.EggBag[eggBagIndex]
	if not entry then
		return {
			Success = false,
			Reason = "EggNotFound",
			Message = "Telur tidak ditemukan di Tas Telur.",
		}
	end

	local eggCfg = EggsConfig.All[entry.Id]
	local sellPrice = if eggCfg then eggCfg.SellPrice else 0

	table.remove(profile.EggBag, eggBagIndex)
	profile.Coins = math.max(0, profile.Coins + sellPrice)
	profile.TotalCoinsEarned = math.max(0, profile.TotalCoinsEarned + sellPrice)

	return {
		Success = true,
		EggId = entry.Id,
		CoinsEarned = sellPrice,
		CoinsRemaining = profile.Coins,
	}
end

-- Monte Carlo simulation of N hatches for an egg type and Luck value
function EggService.SimulateHatches(
	eggId: string,
	luck: number,
	totalRolls: number,
	seed: number?
): EggSimulationReport
	local rng = Random.new(seed or 42)
	local eggCfg = EggsConfig.All[eggId] or EggsConfig.All.CommonEgg
	local adjustedWeights = Weighted.ApplyLuck(eggCfg.RarityWeights, luck)

	local rarityCounts: { [Types.RarityName]: number } = {
		Common = 0,
		Uncommon = 0,
		Rare = 0,
		Epic = 0,
		Legendary = 0,
	}
	local variantCounts: { [Types.PetVariantName]: number } = {
		Normal = 0,
		Golden = 0,
		Shiny = 0,
	}

	for _ = 1, totalRolls do
		local rRaw = Weighted.Pick(adjustedWeights, rng)
		local r: Types.RarityName = if rRaw and #rRaw > 0 then (rRaw :: Types.RarityName) else "Common"
		rarityCounts[r] = (rarityCounts[r] or 0) + 1

		local v = EggService.RollVariant(rng)
		variantCounts[v] = (variantCounts[v] or 0) + 1
	end

	local rarityPct: { [Types.RarityName]: number } = {}
	for k, v in rarityCounts do
		rarityPct[k] = (v / totalRolls) * 100
	end

	local variantPct: { [Types.PetVariantName]: number } = {}
	for k, v in variantCounts do
		variantPct[k] = (v / totalRolls) * 100
	end

	return {
		EggId = eggId,
		TotalRolls = totalRolls,
		RarityCounts = rarityCounts,
		RarityPercentages = rarityPct,
		VariantCounts = variantCounts,
		VariantPercentages = variantPct,
	}
end

-- Server remote wrappers
function EggService.Start()
	if started then
		return
	end
	started = true

	Remotes.OnServerInvoke("PlaceEggInIncubator", function(player: Player, eggBagIndex: number, slotIndex: number): PlaceEggResult
		local result: PlaceEggResult = { Success = false, Reason = "Unknown" }
		local mutated = PlayerState.Mutate(player, function(profile: Types.PlayerProfile)
			result = EggService.PlaceEggInIncubatorInProfile(profile, eggBagIndex, slotIndex)
		end)
		if mutated and result.Success then
			DataService.SavePlayer(player)
			ShovelInventoryService.SendStateSync(player)
		end
		return result
	end)

	Remotes.OnServerInvoke("SpeedUpIncubator", function(player: Player, slotIndex: number): SpeedUpResult
		local result: SpeedUpResult = { Success = false, Reason = "Unknown" }
		local mutated = PlayerState.Mutate(player, function(profile: Types.PlayerProfile)
			result = EggService.SpeedUpIncubatorInProfile(profile, slotIndex)
		end)
		if mutated and result.Success then
			DataService.SavePlayer(player)
			ShovelInventoryService.SendStateSync(player)
		end
		return result
	end)

	Remotes.OnServerInvoke("HatchIncubator", function(player: Player, slotIndex: number): HatchResult
		local result: HatchResult = { Success = false, Reason = "Unknown" }
		local mutated = PlayerState.Mutate(player, function(profile: Types.PlayerProfile)
			result = EggService.HatchIncubatorInProfile(profile, slotIndex)
		end)
		if mutated and result.Success then
			DataService.SavePlayer(player)
			ShovelInventoryService.SendStateSync(player)

			local IndexService = require(script.Parent:WaitForChild("IndexService"))
			local QuestService = require(script.Parent:WaitForChild("QuestService"))
			local TutorialService = require(script.Parent:WaitForChild("TutorialService"))
			if result.Species then
				local profile = PlayerState.Get(player)
				if profile then
					IndexService.RegisterPetDiscovery(player, profile, result.Species)
					TutorialService.OnEggHatched(player, profile, result.Species)
				end
			end
			QuestService.RecordProgress(player, "EggHatched", 1)
		end
		return result
	end)

	Remotes.OnServerInvoke("SellEgg", function(player: Player, eggBagIndex: number): SellEggResult
		local result: SellEggResult = { Success = false, Reason = "Unknown" }
		local mutated = PlayerState.Mutate(player, function(profile: Types.PlayerProfile)
			result = EggService.SellEggInProfile(profile, eggBagIndex)
		end)
		if mutated and result.Success then
			DataService.SavePlayer(player)
			ShovelInventoryService.SendStateSync(player)
		end
		return result
	end)
end

return EggService
