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

local Items = {
	ExpectedCountsByRarity = ExpectedCountsByRarity,
	All = All,
}

return table.freeze(Items)
