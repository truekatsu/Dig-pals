--!strict
-- Centralized type definitions for Dig Pals

export type RarityName = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"
export type PetVariantName = "Normal" | "Golden" | "Shiny"
export type MoundSizeName = "Small" | "Medium" | "Large"
export type StrikeGrade = "Perfect" | "Good" | "Miss"

export type StatRange = {
	Min: number,
	Max: number,
}

export type ShovelConfig = {
	Id: string,
	DisplayName: string,
	Description: string,
	Rarity: RarityName,
	Price: number,
	Power: number,
	DigSpeed: number,
	Luck: number,
	IsShopShovel: boolean,
	ToolName: string,
	Icon: string,
}

export type TimingBarConfig = {
	Speed: number,
	GoodWidth: number,
	PerfectWidth: number,
}

export type MoundSizeConfig = {
	Id: MoundSizeName,
	DisplayName: string,
	HP: number,
	RollCount: number,
	Scale: Vector3,
	DropTypeWeights: { [string]: number },
	RarityWeights: { [string]: number },
	EggRarityWeights: { [string]: number }?,
	Timing: TimingBarConfig,
}

export type EggConfig = {
	Id: string,
	DisplayName: string,
	Rarity: RarityName,
	IncubationSeconds: number,
	SpeedUpCostPerMinute: number,
	SellPrice: number,
	RarityWeights: { [string]: number },
	SpeciesWeights: { [string]: number }?,
}

export type PetSpeciesConfig = {
	Id: string,
	DisplayName: string,
	Rarity: RarityName,
	Power: number,
	Speed: number,
	DigSpeed: number,
	Range: number,
	BaseIncome: number,
}

export type PetVariantConfig = {
	Id: PetVariantName,
	DisplayName: string,
	Weight: number,
	PowerMultiplier: number,
	IncomeMultiplier: number,
	DigSpeedBonus: number,
	PowerScoreMultiplier: number,
}

export type ItemConfig = {
	Id: string,
	DisplayName: string,
	Rarity: RarityName,
	SellPrice: number,
	DefaultWeight: number?,
	NormalMaxWeight: number?,
	MaxWeight: number?,
}

export type BaseLevelConfig = {
	Level: number,
	UpgradeCost: number,
	IncubatorSlots: number,
	PetSlots: number,
	PlotScale: Vector3,
}

export type BagLevelConfig = {
	Level: number,
	Capacity: number,
	UpgradeCost: number,
}

export type EggBagEntry = {
	Id: string,
	Rarity: RarityName,
}

export type IncubatorEntry = {
	Placement: {X: number, Z: number}?,
	Id: string,
	Rarity: RarityName,
	ReadyAt: number,
}

export type PetInstance = {
	Species: string,
	Variant: PetVariantName,
	Level: number,
}

export type QuestEntry = {
	Id: string,
	Progress: number,
	Claimed: boolean,
}

export type PlayerProfile = {
	SchemaVersion: number,
	Coins: number,
	TotalCoinsEarned: number,
	Shovels: {
		Owned: { string },
		Equipped: string,
	},
	BagLevel: number,
	BaseLevel: number,
	Items: { [string]: number },
	ItemWeights: { [string]: { number } },
	EggBag: { EggBagEntry },
	Incubators: { [number]: IncubatorEntry },
	Pets: { [string]: PetInstance },
	EquippedPets: { string },
	BasePets: { string },
	Index: {
		Pets: { [string]: boolean },
		Items: { [string]: boolean },
	},
	Quests: {
		Day: number,
		List: { QuestEntry },
	},
	Streak: {
		Day: number,
		LastClaim: number,
	},
	Tutorial: {
		Step: number,
		Done: boolean,
	},
	SandyGateUnlocked: boolean?,
	WeeklyCoins: {
		Week: number,
		Coins: number,
	}?,
	CreatedAt: number?,
	TotalPlayTime: number?,
	FirstHatchTime: number?,
	IronShovelTime: number?,
	LegendaryCount: number?,
	LastSeen: number,
}

export type LeaderboardCategory = "CurrentCoins" | "PlayTime" | "WeeklyCoins" | "AllTimeCoins" | "StrongestPet"

export type LeaderboardEntry = {
	Rank: number,
	UserId: number,
	PlayerName: string,
	Score: number,
	FormattedScore: string,
	ExtraInfo: string?,
}

return {}
