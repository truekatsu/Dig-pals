--!strict
-- Authoritative Passive Income Service (Step 10)
-- Handles:
-- 1. Base pet active income per second (sum of base pets income = BaseIncome * (1 + 0.20 * (Level - 1)) * VariantMultiplier)
-- 2. Authoritative 1s tick adding income to Coins and TotalCoinsEarned
-- 3. Pet leveling with coins: cost = BaseCost * (1.2 ^ (Level - 1)), max Lv 20
-- 4. Offline income calculation: min(offlineSeconds, 43200) * activeIncome * 0.10 on join

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Util.Types)
local PetsConfig = require(ReplicatedStorage.Shared.Config.Pets)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)
local ShovelInventoryService = require(script.Parent.ShovelInventoryService)

local PassiveIncomeService = {}

local started = false
local tickConnection: RBXScriptConnection? = nil

-- Pure helper: Calculate active income for an individual pet instance
function PassiveIncomeService.CalculatePetIncome(speciesId: string, variant: Types.PetVariantName, level: number): number
	local speciesCfg = PetsConfig.Species[speciesId]
	if not speciesCfg then
		return 0
	end

	local variantCfg = PetsConfig.Variants[variant]
	local variantMult = if variantCfg then variantCfg.IncomeMultiplier else 1.0
	local safeLevel = math.clamp(level or 1, 1, PetsConfig.MaxPetLevel)
	local levelBonus = 1.0 + (PetsConfig.LevelIncomeBonusPerLevel * (safeLevel - 1))

	return math.floor(speciesCfg.BaseIncome * levelBonus * variantMult)
end

-- Pure helper: Calculate total active base pet income per second for a profile
function PassiveIncomeService.CalculatePlayerIncome(profile: Types.PlayerProfile): number
	if type(profile) ~= "table" or type(profile.BasePets) ~= "table" or type(profile.Pets) ~= "table" then
		return 0
	end

	local totalIncome = 0
	for _, petGuid in ipairs(profile.BasePets) do
		local pet = profile.Pets[petGuid]
		if pet and type(pet.Species) == "string" then
			local petIncome = PassiveIncomeService.CalculatePetIncome(pet.Species, pet.Variant, pet.Level)
			totalIncome += petIncome
		end
	end

	local IndexService = require(script.Parent:WaitForChild("IndexService"))
	local petBonus = IndexService.ComputePetIndexIncomeBonus(profile)
	if petBonus > 0 then
		totalIncome = math.floor(totalIncome * (1 + petBonus))
	end

	return totalIncome
end

-- Pure helper: Calculate level up cost for a pet
function PassiveIncomeService.GetLevelUpCost(speciesId: string, currentLevel: number): (number?, string?)
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

-- Mutation: Level up pet by petGuid in profile
export type LevelUpResult = {
	Success: boolean,
	PetGuid: string?,
	NewLevel: number?,
	NextCost: number?,
	CoinsSpent: number?,
	ErrorReason: string?,
}

function PassiveIncomeService.LevelUpPetInProfile(profile: Types.PlayerProfile, petGuid: string): LevelUpResult
	if type(profile) ~= "table" or type(profile.Pets) ~= "table" then
		return { Success = false, ErrorReason = "InvalidProfile" }
	end

	local pet = profile.Pets[petGuid]
	if not pet then
		return { Success = false, ErrorReason = "PetNotFound" }
	end

	local currentLevel = pet.Level or 1
	if currentLevel >= PetsConfig.MaxPetLevel then
		return { Success = false, ErrorReason = "MaxLevelReached" }
	end

	local cost, err = PassiveIncomeService.GetLevelUpCost(pet.Species, currentLevel)
	if not cost or err then
		return { Success = false, ErrorReason = err or "CostCalculationFailed" }
	end

	local playerCoins = profile.Coins or 0
	if playerCoins < cost then
		return { Success = false, ErrorReason = "InsufficientCoins" }
	end

	-- Apply transaction
	profile.Coins = playerCoins - cost
	pet.Level = currentLevel + 1

	local nextCost, _ = PassiveIncomeService.GetLevelUpCost(pet.Species, pet.Level)

	return {
		Success = true,
		PetGuid = petGuid,
		NewLevel = pet.Level,
		NextCost = nextCost,
		CoinsSpent = cost,
	}
end

-- Pure helper: Calculate offline income reward
export type OfflineIncomeResult = {
	OfflineSeconds: number,
	CappedSeconds: number,
	ActiveIncome: number,
	CoinsEarned: number,
}

function PassiveIncomeService.CalculateOfflineIncome(
	lastSeen: number,
	nowTimestamp: number,
	activeIncome: number
): OfflineIncomeResult
	local offlineSeconds = math.max(0, nowTimestamp - (lastSeen or nowTimestamp))
	local cappedSeconds = math.min(offlineSeconds, 43200) -- Max 12 hours (43,200s)

	if offlineSeconds < 60 or activeIncome <= 0 then
		return {
			OfflineSeconds = offlineSeconds,
			CappedSeconds = cappedSeconds,
			ActiveIncome = activeIncome,
			CoinsEarned = 0,
		}
	end

	local coinsEarned = math.floor(cappedSeconds * activeIncome * 0.10)
	return {
		OfflineSeconds = offlineSeconds,
		CappedSeconds = cappedSeconds,
		ActiveIncome = activeIncome,
		CoinsEarned = coinsEarned,
	}
end

-- Process offline income on player join
function PassiveIncomeService.ProcessPlayerJoin(player: Player, profile: Types.PlayerProfile)
	local now = os.time()
	local lastSeen = profile.LastSeen or now
	local activeIncome = PassiveIncomeService.CalculatePlayerIncome(profile)

	player:SetAttribute("IncomePerSecond", activeIncome)

	local offlineResult = PassiveIncomeService.CalculateOfflineIncome(lastSeen, now, activeIncome)
	if offlineResult.CoinsEarned > 0 then
		profile.Coins = (profile.Coins or 0) + offlineResult.CoinsEarned
		profile.TotalCoinsEarned = (profile.TotalCoinsEarned or 0) + offlineResult.CoinsEarned
		local LeaderboardService = require(script.Parent:WaitForChild("LeaderboardService"))
		LeaderboardService.RecordCoinsEarned(profile, offlineResult.CoinsEarned)
		player:SetAttribute("Coins", profile.Coins)

		-- Notify client with offline summary
		Remotes.GetEvent("OfflineIncomeSummary"):FireClient(player, {
			OfflineSeconds = offlineResult.OfflineSeconds,
			CappedSeconds = offlineResult.CappedSeconds,
			ActiveIncome = offlineResult.ActiveIncome,
			CoinsEarned = offlineResult.CoinsEarned,
		})

		print(
			string.format(
				"[PassiveIncome] Awarded %d offline coins to %s (%d) for %ds offline (%d/s rate)",
				offlineResult.CoinsEarned,
				player.Name,
				player.UserId,
				offlineResult.CappedSeconds,
				activeIncome
			)
		)
	end

	profile.LastSeen = now
end

-- 1-second server tick for active passive income
local function onSecondTick()
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = PlayerState.Get(player)
		if profile then
			local income = PassiveIncomeService.CalculatePlayerIncome(profile)
			player:SetAttribute("IncomePerSecond", income)

			if income > 0 then
				profile.Coins = (profile.Coins or 0) + income
				profile.TotalCoinsEarned = (profile.TotalCoinsEarned or 0) + income
				local LeaderboardService = require(script.Parent:WaitForChild("LeaderboardService"))
				LeaderboardService.RecordCoinsEarned(profile, income)
				player:SetAttribute("Coins", profile.Coins)
			end
		end
	end
end

function PassiveIncomeService.Start()
	if started then
		return
	end
	started = true

	-- Register LevelUpPet RemoteFunction
	Remotes.OnServerInvoke("LevelUpPet", function(player: Player, petGuid: any): any
		if type(petGuid) ~= "string" or #petGuid == 0 then
			return { Success = false, ErrorReason = "InvalidPetGuid" }
		end

		local profile = PlayerState.Get(player)
		if not profile then
			return { Success = false, ErrorReason = "ProfileNotLoaded" }
		end

		local result = PassiveIncomeService.LevelUpPetInProfile(profile, petGuid)
		if result.Success then
			-- Recalculate income attribute immediately if pet was in base
			local newIncome = PassiveIncomeService.CalculatePlayerIncome(profile)
			player:SetAttribute("IncomePerSecond", newIncome)
			player:SetAttribute("Coins", profile.Coins)

			-- Sync updated state
			PlayerState.SyncAttributes(player, profile)
			ShovelInventoryService.SendStateSync(player)

			local QuestService = require(script.Parent:WaitForChild("QuestService"))
			QuestService.RecordProgress(player, "PetLeveledUp", 1)

			print(
				string.format(
					"[PassiveIncome] %s leveled up %s to Lv.%d for %d Coins (Remaining Coins: %d)",
					player.Name,
					petGuid,
					result.NewLevel or 0,
					result.CoinsSpent or 0,
					profile.Coins
				)
			)
		end

		return result
	end)

	-- Handle player join offline income
	DataService.OnProfileLoaded(function(player: Player, profile: Types.PlayerProfile)
		PassiveIncomeService.ProcessPlayerJoin(player, profile)
	end)

	-- Start authoritative 1-second interval loop
	task.spawn(function()
		while true do
			task.wait(1.0)
			onSecondTick()
		end
	end)
end

return table.freeze(PassiveIncomeService)
