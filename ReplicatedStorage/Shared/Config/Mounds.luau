--!strict
-- Mound configuration (personal mounds 5.1 & timing/shared mounds 5.3)

local Types = require(script.Parent.Parent.Util.Types)

local SizeOrder: { Types.MoundSizeName } = {
	"Small",
	"Medium",
	"Large",
}

local SizeWeights: { [string]: number } = {
	Small = 60,
	Medium = 30,
	Large = 10,
}

local Sizes: { [Types.MoundSizeName]: Types.MoundSizeConfig } = {
	Small = {
		Id = "Small",
		DisplayName = "Small Mound",
		HP = 50,
		RollCount = 1,
		Scale = Vector3.new(4, 2, 4),
		DropTypeWeights = {
			Egg = 15,
			Item = 85,
		},
		RarityWeights = {
			Common = 70,
			Uncommon = 20,
			Rare = 7,
			Epic = 2.5,
			Legendary = 0.5,
		},
		Timing = {
			Speed = 0.8,
			GoodWidth = 0.30,
			PerfectWidth = 0.10,
		},
	},
	Medium = {
		Id = "Medium",
		DisplayName = "Medium Mound",
		HP = 150,
		RollCount = 2,
		Scale = Vector3.new(6, 3, 6),
		DropTypeWeights = {
			Egg = 25,
			Item = 75,
		},
		RarityWeights = {
			Common = 50,
			Uncommon = 30,
			Rare = 13,
			Epic = 5.5,
			Legendary = 1.5,
		},
		Timing = {
			Speed = 1.1,
			GoodWidth = 0.25,
			PerfectWidth = 0.08,
		},
	},
	Large = {
		Id = "Large",
		DisplayName = "Large Mound",
		HP = 400,
		RollCount = 3,
		Scale = Vector3.new(8, 4, 8),
		DropTypeWeights = {
			Egg = 40,
			Item = 60,
		},
		RarityWeights = {
			Common = 30,
			Uncommon = 35,
			Rare = 22,
			Epic = 10,
			Legendary = 3,
		},
		Timing = {
			Speed = 1.4,
			GoodWidth = 0.20,
			PerfectWidth = 0.06,
		},
	},
}

local Shared = {
	DisplayName = "Rare Mound",
	SpawnIntervalSeconds = 720,
	DurationSeconds = 240,
	SpawnPointCount = 5,
	HP = 3000,
	Scale = Vector3.new(12, 6, 12),
	MinContributionRatio = 0.03,
	RewardEggRolls = 2,
	TopContributorBonusEggRolls = 1,
	RewardItemRolls = 1,
	RewardLuckMultiplier = 1.5,
	EggRarityWeights = {
		Common = 0,
		Uncommon = 55,
		Rare = 30,
		Epic = 12,
		Legendary = 3,
	},
	ItemRarityWeights = {
		Common = 20,
		Uncommon = 35,
		Rare = 28,
		Epic = 13,
		Legendary = 4,
	},
	SpecialShovelDropChances = {
		MossyShovel = 0.005,
		MoonlitShovel = 0.002,
	},
	Timing = {
		Speed = 1.6,
		GoodWidth = 0.18,
		PerfectWidth = 0.05,
	},
}

local Mounds = {
	MaxActivePerPlayer = 6,
	SpawnIntervalSeconds = 8,
	SpawnRadiusStuds = 80,
	DespawnIdleSeconds = 180,
	DigRangeStuds = 8,
	LatencyToleranceSeconds = 0.12,
	StrikeDamageMultipliers = {
		Perfect = 2.0,
		Good = 1.0,
		Miss = 0,
	},
	TimingScoreGoodWeight = 0.5,
	TimingScoreLuckMultiplier = 0.25,
	MaxEffectiveLuck = 5.0,
	SizeOrder = SizeOrder,
	SizeWeights = SizeWeights,
	Sizes = Sizes,
	Shared = Shared,
}

return table.freeze(Mounds)
