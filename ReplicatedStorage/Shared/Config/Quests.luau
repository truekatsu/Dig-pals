--!strict
-- Daily Quests (pool of 8, pick 3 daily) and 7-day Login Streak configuration

export type QuestDefinition = {
	Id: string,
	DisplayName: string,
	Description: string,
	EventType: string,
	Target: number,
	RewardCoins: number,
	RewardEggId: string?,
}

export type StreakReward = {
	Day: number,
	RewardCoins: number,
	RewardEggId: string?,
}

local Pool: { QuestDefinition } = {
	{
		Id = "DigMounds15",
		DisplayName = "Excavator Duty",
		Description = "Dig 15 mounds",
		EventType = "MoundCleared",
		Target = 15,
		RewardCoins = 250,
		RewardEggId = nil,
	},
	{
		Id = "PerfectStreak5",
		DisplayName = "Sharp Timing",
		Description = "Land 5 Perfect strikes in a row",
		EventType = "PerfectStreak",
		Target = 5,
		RewardCoins = 300,
		RewardEggId = nil,
	},
	{
		Id = "SellItems1000Coins",
		DisplayName = "Merchant Trader",
		Description = "Sell items worth $1,000",
		EventType = "CoinsFromSellingItems",
		Target = 1000,
		RewardCoins = 0,
		RewardEggId = "UncommonEgg",
	},
	{
		Id = "HatchEgg1",
		DisplayName = "New Friend",
		Description = "Hatch 1 egg in an incubator",
		EventType = "EggHatched",
		Target = 1,
		RewardCoins = 350,
		RewardEggId = nil,
	},
	{
		Id = "DigMediumOrLarge5",
		DisplayName = "Deep Digger",
		Description = "Clear 5 Medium or Large mounds",
		EventType = "MediumOrLargeMoundCleared",
		Target = 5,
		RewardCoins = 400,
		RewardEggId = nil,
	},
	{
		Id = "PerfectStrikes20",
		DisplayName = "Master Striker",
		Description = "Land 20 Perfect strikes total",
		EventType = "PerfectStrikeTotal",
		Target = 20,
		RewardCoins = 0,
		RewardEggId = "UncommonEgg",
	},
	{
		Id = "FindRareOrHigherItem1",
		DisplayName = "Treasure Hunter",
		Description = "Find 1 Rare or higher item",
		EventType = "RareOrHigherItemFound",
		Target = 1,
		RewardCoins = 500,
		RewardEggId = nil,
	},
	{
		Id = "LevelUpPet1",
		DisplayName = "Pet Trainer",
		Description = "Level up any pet 1 time",
		EventType = "PetLeveledUp",
		Target = 1,
		RewardCoins = 300,
		RewardEggId = nil,
	},
}

local StreakRewards: { [number]: StreakReward } = {
	[1] = { Day = 1, RewardCoins = 100, RewardEggId = nil },
	[2] = { Day = 2, RewardCoins = 200, RewardEggId = "CommonEgg" },
	[3] = { Day = 3, RewardCoins = 350, RewardEggId = nil },
	[4] = { Day = 4, RewardCoins = 500, RewardEggId = "UncommonEgg" },
	[5] = { Day = 5, RewardCoins = 750, RewardEggId = nil },
	[6] = { Day = 6, RewardCoins = 1000, RewardEggId = "UncommonEgg" },
	[7] = { Day = 7, RewardCoins = 1500, RewardEggId = "RareEgg" },
}

local Quests = {
	DailyQuestCount = 3,
	ExpectedPoolCount = 8,
	StreakLengthDays = 7,
	Pool = Pool,
	StreakRewards = StreakRewards,
}

return table.freeze(Quests)
