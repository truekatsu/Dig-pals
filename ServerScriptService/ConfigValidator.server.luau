--!strict
-- Validates all Dig Pals Config tables on server startup (Step 0)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConfigFolder = Shared:WaitForChild("Config")

local Rarity = require(ConfigFolder:WaitForChild("Rarity"))
local Shovels = require(ConfigFolder:WaitForChild("Shovels"))
local Mounds = require(ConfigFolder:WaitForChild("Mounds"))
local Eggs = require(ConfigFolder:WaitForChild("Eggs"))
local Pets = require(ConfigFolder:WaitForChild("Pets"))
local Items = require(ConfigFolder:WaitForChild("Items"))
local Base = require(ConfigFolder:WaitForChild("Base"))
local Economy = require(ConfigFolder:WaitForChild("Economy"))
local Quests = require(ConfigFolder:WaitForChild("Quests"))

local EPSILON = 1e-5

local passedCount = 0
local failedCount = 0

local function check(condition: boolean, label: string, detail: string?)
	if condition then
		passedCount += 1
		print(string.format("[ConfigValidator] PASS: %s", label))
	else
		failedCount += 1
		warn(string.format("[ConfigValidator] FAIL: %s (%s)", label, detail or "assertion failed"))
	end
end

local function checkWeightsSum100(weights: { [string]: number }, tableName: string)
	local sum = 0
	for _, w in weights do
		sum += w
	end
	local diff = math.abs(sum - 100)
	check(diff <= EPSILON, string.format("%s weights sum to 100%%", tableName), string.format("sum=%.4f", sum))
end

-- 1. Validate Rarity Order (5 rarities)
check(#Rarity.Order == 5, "Rarity count is 5", tostring(#Rarity.Order))

-- 2. Validate Shovels (5 shop shovels + 2 special shovels)
check(#Shovels.ShopOrder == 5, "Shop shovel count is 5", tostring(#Shovels.ShopOrder))
local actualShopCount = 0
for _, shovel in Shovels.All do
	if shovel.IsShopShovel then
		actualShopCount += 1
	end
end
check(actualShopCount == 5, "Shovels.All has exactly 5 shop shovels", tostring(actualShopCount))
check(Shovels.All.MossyShovel ~= nil and Shovels.All.MoonlitShovel ~= nil, "Special shovels (MossyShovel, MoonlitShovel) exist in Config")

-- 3. Validate Mounds probability tables
checkWeightsSum100(Mounds.SizeWeights, "Mounds.SizeWeights")
for _, sizeName in Mounds.SizeOrder do
	local sizeConfig = Mounds.Sizes[sizeName]
	check(sizeConfig ~= nil, string.format("Mounds.Sizes.%s exists", sizeName))
	if sizeConfig then
		checkWeightsSum100(sizeConfig.DropTypeWeights, string.format("Mounds.Sizes.%s.DropTypeWeights", sizeName))
		checkWeightsSum100(sizeConfig.RarityWeights, string.format("Mounds.Sizes.%s.RarityWeights", sizeName))
	end
end
checkWeightsSum100(Mounds.Shared.EggRarityWeights, "Mounds.Shared.EggRarityWeights")
checkWeightsSum100(Mounds.Shared.ItemRarityWeights, "Mounds.Shared.ItemRarityWeights")

-- 4. Validate Eggs probability tables
for eggId, eggConfig in Eggs.All do
	checkWeightsSum100(eggConfig.RarityWeights, string.format("Eggs.All.%s.RarityWeights", eggId))
	if eggConfig.SpeciesWeights then
		checkWeightsSum100(eggConfig.SpeciesWeights, string.format("Eggs.All.%s.SpeciesWeights", eggId))
	end
end

-- 5. Validate Pets (counts 6/8/5/4/2, variants sum to 100%, and every stat within rarity range)
checkWeightsSum100(Pets.VariantWeights, "Pets.VariantWeights")

local petCountsByRarity: { [string]: number } = {
	Common = 0,
	Uncommon = 0,
	Rare = 0,
	Epic = 0,
	Legendary = 0,
}

local statOutOfRangeErrors = 0
for speciesId, pet in Pets.Species do
	petCountsByRarity[pet.Rarity] = (petCountsByRarity[pet.Rarity] or 0) + 1
	local ranges = Pets.StatRangesByRarity[pet.Rarity]
	if not ranges then
		statOutOfRangeErrors += 1
		warn(string.format("[ConfigValidator] Unknown rarity %s on pet %s", pet.Rarity, speciesId))
	else
		local statsToVerify = {
			Power = pet.Power,
			Speed = pet.Speed,
			DigSpeed = pet.DigSpeed,
			Range = pet.Range,
			BaseIncome = pet.BaseIncome,
		}
		for statName, statValue in statsToVerify do
			local range = (ranges :: any)[statName]
			if statValue < range.Min or statValue > range.Max then
				statOutOfRangeErrors += 1
				warn(
					string.format(
						"[ConfigValidator] Pet %s (%s) stat %s=%s out of range [%d, %d]",
						speciesId,
						pet.Rarity,
						statName,
						tostring(statValue),
						range.Min,
						range.Max
					)
				)
			end
		end
	end
end

for _, rarityName in Rarity.Order do
	local expected = Pets.ExpectedCountsByRarity[rarityName]
	local actual = petCountsByRarity[rarityName] or 0
	check(
		actual == expected,
		string.format("Pet count for %s is %d", rarityName, expected),
		string.format("actual=%d", actual)
	)
end
check(statOutOfRangeErrors == 0, "All 25 pet species stats are within their rarity stat ranges", string.format("errors=%d", statOutOfRangeErrors))

-- 6. Validate Items (counts 6/5/4/3/2)
local itemCountsByRarity: { [string]: number } = {
	Common = 0,
	Uncommon = 0,
	Rare = 0,
	Epic = 0,
	Legendary = 0,
}
for _, item in Items.All do
	itemCountsByRarity[item.Rarity] = (itemCountsByRarity[item.Rarity] or 0) + 1
end
for _, rarityName in Rarity.Order do
	local expected = Items.ExpectedCountsByRarity[rarityName]
	local actual = itemCountsByRarity[rarityName] or 0
	check(
		actual == expected,
		string.format("Item count for %s is %d", rarityName, expected),
		string.format("actual=%d", actual)
	)
end

-- 7. Validate Base, Economy, and Quests
check(#Base.Levels == Base.MaxBaseLevel, "Base levels 1..5 configured", tostring(#Base.Levels))
check(#Economy.BagLevels == Economy.MaxBagLevel, "Bag levels 1..5 configured", tostring(#Economy.BagLevels))
check(#Quests.Pool == Quests.ExpectedPoolCount, "Daily quest pool has 8 quests", tostring(#Quests.Pool))
check(#Quests.StreakRewards == Quests.StreakLengthDays, "Login streak has 7 days configured", tostring(#Quests.StreakRewards))

print(
	string.format(
		"[ConfigValidator] SUMMARY: %d passed, %d failed.",
		passedCount,
		failedCount
	)
)
