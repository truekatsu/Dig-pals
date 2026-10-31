--!strict
-- Item configuration (20 items: 6 Common, 5 Uncommon, 4 Rare, 3 Epic, 2 Legendary)

local Types = require(script.Parent.Parent.Util.Types)

local ExpectedCountsByRarity: { [Types.RarityName]: number } = {
	Common = 6,
	Uncommon = 5,
	Rare = 4,
	Epic = 3,
	Legendary = 2,
}

local All: { [string]: Types.ItemConfig } = {
	-- Common (6)
	Pebble = {
		Id = "Pebble",
		DisplayName = "Pebble",
		Rarity = "Common",
		SellPrice = 10,
	},
	ClayLump = {
		Id = "ClayLump",
		DisplayName = "Clay Lump",
		Rarity = "Common",
		SellPrice = 12,
	},
	TwistedRoot = {
		Id = "TwistedRoot",
		DisplayName = "Twisted Root",
		Rarity = "Common",
		SellPrice = 14,
	},
	OldBottleCap = {
		Id = "OldBottleCap",
		DisplayName = "Old Bottle Cap",
		Rarity = "Common",
		SellPrice = 15,
	},
	RustyNail = {
		Id = "RustyNail",
		DisplayName = "Rusty Nail",
		Rarity = "Common",
		SellPrice = 16,
	},
	CrackedShell = {
		Id = "CrackedShell",
		DisplayName = "Cracked Shell",
		Rarity = "Common",
		SellPrice = 18,
	},

	-- Uncommon (5)
	CopperCoin = {
		Id = "CopperCoin",
		DisplayName = "Copper Coin",
		Rarity = "Uncommon",
		SellPrice = 35,
	},
	QuartzShard = {
		Id = "QuartzShard",
		DisplayName = "Quartz Shard",
		Rarity = "Uncommon",
		SellPrice = 40,
	},
	FossilLeaf = {
		Id = "FossilLeaf",
		DisplayName = "Fossil Leaf",
		Rarity = "Uncommon",
		SellPrice = 45,
	},
	BronzeButton = {
		Id = "BronzeButton",
		DisplayName = "Bronze Button",
		Rarity = "Uncommon",
		SellPrice = 50,
	},
	AmberDrop = {
		Id = "AmberDrop",
		DisplayName = "Amber Drop",
		Rarity = "Uncommon",
		SellPrice = 55,
	},

	-- Rare (4)
	SilverRing = {
		Id = "SilverRing",
		DisplayName = "Silver Ring",
		Rarity = "Rare",
		SellPrice = 120,
	},
	AmethystGeode = {
		Id = "AmethystGeode",
		DisplayName = "Amethyst Geode",
		Rarity = "Rare",
		SellPrice = 140,
	},
	AncientPottery = {
		Id = "AncientPottery",
		DisplayName = "Ancient Pottery",
		Rarity = "Rare",
		SellPrice = 160,
	},
	JadeFigurine = {
		Id = "JadeFigurine",
		DisplayName = "Jade Figurine",
		Rarity = "Rare",
		SellPrice = 180,
	},

	-- Epic (3)
	GoldenChalice = {
		Id = "GoldenChalice",
		DisplayName = "Golden Chalice",
		Rarity = "Epic",
		SellPrice = 420,
	},
	RubyHeart = {
		Id = "RubyHeart",
		DisplayName = "Ruby Heart",
		Rarity = "Epic",
		SellPrice = 500,
	},
	DinoTooth = {
		Id = "DinoTooth",
		DisplayName = "Dino Tooth",
		Rarity = "Epic",
		SellPrice = 600,
	},

	-- Legendary (2)
	RoyalCrown = {
		Id = "RoyalCrown",
		DisplayName = "Royal Crown",
		Rarity = "Legendary",
		SellPrice = 1500,
	},
	MeteorCore = {
		Id = "MeteorCore",
		DisplayName = "Meteor Core",
		Rarity = "Legendary",
		SellPrice = 2000,
	},
}

-- Kilograms at the ordinary/reference size. Each owned item rolls and persists its own weight.
local DefaultWeights: { [string]: number } = {
	Pebble = 0.80, ClayLump = 1.10, TwistedRoot = 0.70, OldBottleCap = 0.25, RustyNail = 0.35, CrackedShell = 0.60,
	CopperCoin = 0.45, QuartzShard = 1.30, FossilLeaf = 0.90, BronzeButton = 0.35, AmberDrop = 1.00,
	SilverRing = 0.20, AmethystGeode = 2.40, AncientPottery = 1.80, JadeFigurine = 1.50,
	GoldenChalice = 2.20, RubyHeart = 1.40, DinoTooth = 2.50, RoyalCrown = 3.00, MeteorCore = 6.00,
}
local RarityDefaultWeights: { [string]: number } = {
	Common = 0.80,
	Uncommon = 1.20,
	Rare = 1.80,
	Epic = 2.80,
	Legendary = 5.00,
}

for itemId, item in All do
	local defaultWeight = DefaultWeights[itemId] or RarityDefaultWeights[item.Rarity] or 1
	item.DefaultWeight = defaultWeight
	item.NormalMaxWeight = defaultWeight * 1.5
	item.MaxWeight = defaultWeight * 4
end

local function roundWeight(value: number): number
	return math.max(0.01, math.floor(value * 100 + 0.5) / 100)
end

local function rollWeight(itemId: string, rng: Random?): number
	local item = All[itemId]
	if not item then return 1 end
	local randomObj = rng or Random.new()
	local defaultWeight = item.DefaultWeight or 1
	local roll = randomObj:NextNumber()
	local ratio: number
	if roll < 0.95 then
		ratio = randomObj:NextNumber(0.7, 1.5)
	elseif roll < 0.995 then
		ratio = randomObj:NextNumber(1.5, 2.4)
	else
		ratio = randomObj:NextNumber(2.4, 4.0)
	end
	return roundWeight(defaultWeight * ratio)
end

local function getSellPrice(itemId: string, weight: number?): number
	local item = All[itemId]
	if not item then return 0 end
	local defaultWeight = item.DefaultWeight or 1
	local safeWeight = math.clamp(tonumber(weight) or defaultWeight, defaultWeight * 0.5, item.MaxWeight or defaultWeight * 4)
	local ratio = safeWeight / defaultWeight
	local multiplier = if ratio <= 1.5 then math.max(0.5, ratio) else 1.5 * (1 + (ratio - 1.5) * 3.5)
	return math.max(1, math.floor(item.SellPrice * multiplier + 0.5))
end

local function getWeightClass(itemId: string, weight: number?): string
	local item = All[itemId]
	if not item then return "Wajar" end
	local value = tonumber(weight) or item.DefaultWeight or 1
	if value > (item.DefaultWeight or 1) * 2.4 then return "Raksasa" end
	if value > (item.NormalMaxWeight or math.huge) then return "Berat Langka" end
	return "Wajar"
end

local function getModelScale(itemId: string, weight: number?): number
	local item = All[itemId]
	if not item then return 1 end
	local defaultWeight = item.DefaultWeight or 1
	local ratio = math.max(0.1, (tonumber(weight) or defaultWeight) / defaultWeight)
	return math.clamp(ratio ^ 0.4, 0.75, 1.9)
end

local Items = {
	ExpectedCountsByRarity = ExpectedCountsByRarity,
	All = All,
	RollWeight = rollWeight,
	GetSellPrice = getSellPrice,
	GetWeightClass = getWeightClass,
	GetModelScale = getModelScale,
}

return table.freeze(Items)
