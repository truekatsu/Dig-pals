--!strict
-- Egg configuration (incubation durations, speed-up rates, sell prices, and hatch weights)

local Types = require(script.Parent.Parent.Util.Types)

local RarityEggByTier: { [Types.RarityName]: string } = {
	Common = "CommonEgg",
	Uncommon = "UncommonEgg",
	Rare = "RareEgg",
	Epic = "EpicEgg",
	Legendary = "LegendaryEgg",
}

local All: { [string]: Types.EggConfig } = {
	StarterEgg = {
		Id = "StarterEgg",
		DisplayName = "Starter Egg",
		Rarity = "Common",
		IncubationSeconds = 20,
		SpeedUpCostPerMinute = 10,
		SellPrice = 0,
		RarityWeights = {
			Common = 100,
			Uncommon = 0,
			Rare = 0,
			Epic = 0,
			Legendary = 0,
		},
		SpeciesWeights = {
			Dog = 50,
			Cat = 50,
		},
	},
	CommonEgg = {
		Id = "CommonEgg",
		DisplayName = "Common Egg",
		Rarity = "Common",
		IncubationSeconds = 60,
		SpeedUpCostPerMinute = 25,
		SellPrice = 30,
		RarityWeights = {
			Common = 80,
			Uncommon = 17,
			Rare = 2.5,
			Epic = 0.4,
			Legendary = 0.1,
		},
	},
	UncommonEgg = {
		Id = "UncommonEgg",
		DisplayName = "Uncommon Egg",
		Rarity = "Uncommon",
		IncubationSeconds = 180,
		SpeedUpCostPerMinute = 40,
		SellPrice = 90,
		RarityWeights = {
			Common = 35,
			Uncommon = 50,
			Rare = 12,
			Epic = 2.5,
			Legendary = 0.5,
		},
	},
	RareEgg = {
		Id = "RareEgg",
		DisplayName = "Rare Egg",
		Rarity = "Rare",
		IncubationSeconds = 480,
		SpeedUpCostPerMinute = 75,
		SellPrice = 280,
		RarityWeights = {
			Common = 10,
			Uncommon = 30,
			Rare = 45,
			Epic = 13,
			Legendary = 2,
		},
	},
	EpicEgg = {
		Id = "EpicEgg",
		DisplayName = "Epic Egg",
		Rarity = "Epic",
		IncubationSeconds = 1200,
		SpeedUpCostPerMinute = 150,
		SellPrice = 900,
		RarityWeights = {
			Common = 0,
			Uncommon = 15,
			Rare = 35,
			Epic = 42,
			Legendary = 8,
		},
	},
	LegendaryEgg = {
		Id = "LegendaryEgg",
		DisplayName = "Legendary Egg",
		Rarity = "Legendary",
		IncubationSeconds = 2700,
		SpeedUpCostPerMinute = 300,
		SellPrice = 3000,
		RarityWeights = {
			Common = 0,
			Uncommon = 0,
			Rare = 25,
			Epic = 50,
			Legendary = 25,
		},
	},
}

local Eggs = {
	RarityEggByTier = RarityEggByTier,
	All = All,
}

return table.freeze(Eggs)
