--!strict
-- Server-authoritative mound drop calculations, Timing Score, Effective Luck, and 100k roll simulator (Step 5)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))
local Weighted = require(Shared:WaitForChild("Util"):WaitForChild("Weighted"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local RarityConfig = require(Shared:WaitForChild("Config"):WaitForChild("Rarity"))
local MoundsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Mounds"))
local ItemsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Items"))
local EggsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Eggs"))
local ShovelsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Shovels"))
local EconomyConfig = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))
local BaseConfig = require(Shared:WaitForChild("Config"):WaitForChild("Base"))

local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
local MoundService = require(script.Parent:WaitForChild("MoundService"))
local DigService = require(script.Parent:WaitForChild("DigService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))

export type DropEntry = {
	DropType: Types.MoundDropType,
	Id: string,
	DisplayName: string,
	Rarity: Types.RarityName,
	SellPrice: number,
	AutoSold: boolean,
	AutoSoldCoins: number,
}

export type MoundDropSummary = {
	MoundId: string,
	MoundSize: Types.MoundSizeName,
	TimingScore: number,
	EffectiveLuck: number,
	PerfectCount: number,
	GoodCount: number,
	MissCount: number,
	Drops: { DropEntry },
}

export type SimulationReport = {
	MoundSize: Types.MoundSizeName,
	EffectiveLuck: number,
	TotalRolls: number,
	DropTypeCounts: { [string]: number },
	DropTypePercentages: { [string]: number },
	RarityCounts: { [string]: number },
	RarityPercentages: { [string]: number },
	ExpectedRarityPercentages: { [string]: number },
}

local DropService = {}

local serverRng = Random.new()
local itemsByRarity: { [Types.RarityName]: { Types.ItemConfig } } = {
	Common = {},
	Uncommon = {},
	Rare = {},
	Epic = {},
	Legendary = {},
}
local lastDropSummaryByUserId: { [number]: MoundDropSummary } = {}
local started = false

local function buildRarityPools()
	for _, rarityName in RarityConfig.Order do
		itemsByRarity[rarityName] = {}
	end
	for _, itemConfig in ItemsConfig.All do
		local bucket = itemsByRarity[itemConfig.Rarity]
		if bucket then
			table.insert(bucket, itemConfig)
		end
	end
	for _, bucket in itemsByRarity do
		table.sort(bucket, function(a: Types.ItemConfig, b: Types.ItemConfig): boolean
			return a.Id < b.Id
		end)
	end
end

buildRarityPools()

-- Timing Score = (Perfect + 0.5 * Good) / totalPlayerStrikes
function DropService.ComputeTimingScore(perfectCount: number, goodCount: number, missCount: number): number
	local p = math.max(0, perfectCount)
	local g = math.max(0, goodCount)
	local m = math.max(0, missCount)
	local totalStrikes = p + g + m
	if totalStrikes <= 0 then
		return 0
	end
	local rawScore = (p + (MoundsConfig.TimingScoreGoodWeight * g)) / totalStrikes
	return math.clamp(rawScore, 0, 1)
end

-- Effective Luck = min(5.0, (shovelLuck + bonusLuck) * (1 + 0.25 * TimingScore))
function DropService.ComputeEffectiveLuck(shovelLuck: number, timingScore: number, bonusLuck: number?): number
	local baseLuck = math.max(0, shovelLuck + (bonusLuck or 0))
	local clampedScore = math.clamp(timingScore, 0, 1)
	local effective = baseLuck * (1 + (MoundsConfig.TimingScoreLuckMultiplier * clampedScore))
	return math.min(MoundsConfig.MaxEffectiveLuck, effective)
end

function DropService.ComputeIndexLuckBonus(profile: Types.PlayerProfile?): number
	if not profile or not profile.Index or not profile.Index.Items then
		return 0
	end
	local discoveredItems = profile.Index.Items
	local bonus = 0
	for _, rarityName in RarityConfig.Order do
		local pool = itemsByRarity[rarityName]
		if pool and #pool > 0 then
			local allFound = true
			for _, itemConfig in pool do
				if not discoveredItems[itemConfig.Id] then
					allFound = false
					break
				end
			end
			if allFound then
				bonus += RarityConfig.IndexRewards.ItemRarityLuckBonus
			end
		end
	end
	return bonus
end

local function pickUniformItemInRarity(rarity: Types.RarityName, rng: Random): Types.ItemConfig
	local pool = itemsByRarity[rarity]
	if not pool or #pool == 0 then
		pool = itemsByRarity.Common
	end
	local index = rng:NextInteger(1, #pool)
	return pool[index]
end

local function pickEggForRarity(rarity: Types.RarityName): Types.EggConfig
	local eggId = EggsConfig.RarityEggByTier[rarity] or "CommonEgg"
	return EggsConfig.All[eggId] or EggsConfig.All.CommonEgg
end

function DropService.RollSingleDrop(
	moundSize: Types.MoundSizeName,
	effectiveLuck: number,
	rng: Random?
): DropEntry
	local randomObj = rng or serverRng
	local sizeConfig = MoundsConfig.Sizes[moundSize] or MoundsConfig.Sizes.Small
	local clampedLuck = math.clamp(effectiveLuck, 0, MoundsConfig.MaxEffectiveLuck)

	local dropTypeRaw = Weighted.Pick(sizeConfig.DropTypeWeights, randomObj)
	local dropType: Types.MoundDropType = if dropTypeRaw == "Egg" then "Egg" else "Item"

	local adjustedRarityWeights = Weighted.ApplyLuck(sizeConfig.RarityWeights, clampedLuck)
	local rarityRaw = Weighted.Pick(adjustedRarityWeights, randomObj)
	local rarity: Types.RarityName = if RarityConfig.ById[rarityRaw :: Types.RarityName]
		then (rarityRaw :: Types.RarityName)
		else "Common"

	if dropType == "Egg" then
		local eggConfig = pickEggForRarity(rarity)
		return {
			DropType = "Egg",
			Id = eggConfig.Id,
			DisplayName = eggConfig.DisplayName,
			Rarity = rarity,
			SellPrice = eggConfig.SellPrice,
			AutoSold = false,
			AutoSoldCoins = 0,
		}
	else
		local itemConfig = pickUniformItemInRarity(rarity, randomObj)
		return {
			DropType = "Item",
			Id = itemConfig.Id,
			DisplayName = itemConfig.DisplayName,
			Rarity = rarity,
			SellPrice = itemConfig.SellPrice,
			AutoSold = false,
			AutoSoldCoins = 0,
		}
	end
end

function DropService.RollMoundDrops(
	moundSize: Types.MoundSizeName,
	effectiveLuck: number,
	rng: Random?
): { DropEntry }
	local sizeConfig = MoundsConfig.Sizes[moundSize] or MoundsConfig.Sizes.Small
	local drops: { DropEntry } = {}
	for _ = 1, sizeConfig.RollCount do
		table.insert(drops, DropService.RollSingleDrop(moundSize, effectiveLuck, rng))
	end
	return drops
end

function DropService.ProcessClearedMound(
	player: Player?,
	userId: number,
	mound: MoundService.MoundInstance,
	rngOverride: Random?,
	profileOverride: Types.PlayerProfile?
): MoundDropSummary
	local profile = profileOverride or (if player then PlayerState.Get(player) else nil)
	local equippedShovelId = if profile and profile.Shovels and profile.Shovels.Equipped
		then profile.Shovels.Equipped
		else EconomyConfig.StartingShovel
	local shovelConfig = ShovelsConfig.All[equippedShovelId] or ShovelsConfig.All.RustyShovel

	local timingScore = DropService.ComputeTimingScore(mound.PerfectCount, mound.GoodCount, mound.MissCount)
	local indexLuckBonus = DropService.ComputeIndexLuckBonus(profile)
	local effectiveLuck = DropService.ComputeEffectiveLuck(shovelConfig.Luck, timingScore, indexLuckBonus)
	local drops = DropService.RollMoundDrops(mound.Size, effectiveLuck, rngOverride)

	if player and profile then
		local IndexService = require(script.Parent:WaitForChild("IndexService"))
		local QuestService = require(script.Parent:WaitForChild("QuestService"))

		PlayerState.Mutate(player, function(mutableProfile: Types.PlayerProfile)
			for _, drop in drops do
				InventoryService.AddDropToProfile(mutableProfile, drop)
				if drop.DropType == "Item" then
					IndexService.RegisterItemDiscovery(player, mutableProfile, drop.Id)
					if drop.Rarity == "Rare" or drop.Rarity == "Epic" or drop.Rarity == "Legendary" then
						QuestService.RecordProgress(player, "RareOrHigherItemFound", 1)
					end
				end
			end
		end)

		QuestService.RecordProgress(player, "MoundCleared", 1)
		if mound.Size == "Medium" or mound.Size == "Large" then
			QuestService.RecordProgress(player, "MediumOrLargeMoundCleared", 1)
		end

		local TutorialService = require(script.Parent:WaitForChild("TutorialService"))
		local prof = PlayerState.Get(player)
		if prof then
			TutorialService.OnMoundCleared(player, prof, false)
		end
	end

	local summary: MoundDropSummary = {
		MoundId = mound.Id,
		MoundSize = mound.Size,
		TimingScore = timingScore,
		EffectiveLuck = effectiveLuck,
		PerfectCount = mound.PerfectCount,
		GoodCount = mound.GoodCount,
		MissCount = mound.MissCount,
		Drops = drops,
	}
	lastDropSummaryByUserId[userId] = summary

	local dropDescList: { string } = {}
	for _, d in drops do
		local autoSoldTag = if d.AutoSold then string.format(" [AutoSold +%d]", d.AutoSoldCoins) else ""
		table.insert(dropDescList, string.format("%s:%s (%s)%s", d.DropType, d.Id, d.Rarity, autoSoldTag))
	end

	print(
		string.format(
			"[DropService] MoundCleared | UserId=%d | Size=%s | Strikes P/G/M=%d/%d/%d | Score=%.2f | Luck=%.3f | Drops=[%s]",
			userId,
			mound.Size,
			mound.PerfectCount,
			mound.GoodCount,
			mound.MissCount,
			timingScore,
			effectiveLuck,
			table.concat(dropDescList, ", ")
		)
	)

	if player and player.Parent == Players then
		Remotes.GetEvent("DropNotification"):FireClient(player, summary)
	end

	return summary
end

function DropService.GetLastDropSummary(userId: number): MoundDropSummary?
	return lastDropSummaryByUserId[userId]
end

-- Runs an N-roll Monte Carlo simulation for a mound size and Luck value
function DropService.SimulateRolls(
	moundSize: Types.MoundSizeName,
	effectiveLuck: number,
	totalRolls: number,
	seed: number?
): SimulationReport
	local rng = Random.new(seed or 123456)
	local sizeConfig = MoundsConfig.Sizes[moundSize] or MoundsConfig.Sizes.Small
	local clampedLuck = math.clamp(effectiveLuck, 0, MoundsConfig.MaxEffectiveLuck)
	local expectedProbs = Weighted.ApplyLuck(sizeConfig.RarityWeights, clampedLuck)

	local dropTypeCounts: { [string]: number } = {
		Item = 0,
		Egg = 0,
	}
	local rarityCounts: { [string]: number } = {
		Common = 0,
		Uncommon = 0,
		Rare = 0,
		Epic = 0,
		Legendary = 0,
	}

	for _ = 1, totalRolls do
		local drop = DropService.RollSingleDrop(moundSize, clampedLuck, rng)
		dropTypeCounts[drop.DropType] = (dropTypeCounts[drop.DropType] or 0) + 1
		rarityCounts[drop.Rarity] = (rarityCounts[drop.Rarity] or 0) + 1
	end

	local dropTypePercentages: { [string]: number } = {}
	for k, count in dropTypeCounts do
		dropTypePercentages[k] = (count / totalRolls) * 100
	end

	local rarityPercentages: { [string]: number } = {}
	local expectedRarityPercentages: { [string]: number } = {}
	for _, rarityName in RarityConfig.Order do
		rarityPercentages[rarityName] = ((rarityCounts[rarityName] or 0) / totalRolls) * 100
		expectedRarityPercentages[rarityName] = (expectedProbs[rarityName] or 0) * 100
	end

	return {
		MoundSize = moundSize,
		EffectiveLuck = clampedLuck,
		TotalRolls = totalRolls,
		DropTypeCounts = dropTypeCounts,
		DropTypePercentages = dropTypePercentages,
		RarityCounts = rarityCounts,
		RarityPercentages = rarityPercentages,
		ExpectedRarityPercentages = expectedRarityPercentages,
	}
end

function DropService.Start()
	if started then
		return
	end
	started = true

	DigService.OnMoundCleared(function(player: Player?, userId: number, mound: MoundService.MoundInstance)
		DropService.ProcessClearedMound(player, userId, mound)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		lastDropSummaryByUserId[player.UserId] = nil
	end)
end

return DropService
