--!strict
-- Economy, bag levels, passive/offline income, sandy gate, and global system constants

local Types = require(script.Parent.Parent.Util.Types)

local BagLevels: { [number]: Types.BagLevelConfig } = {
	[1] = {
		Level = 1,
		Capacity = 20,
		UpgradeCost = 0,
	},
	[2] = {
		Level = 2,
		Capacity = 40,
		UpgradeCost = 300,
	},
	[3] = {
		Level = 3,
		Capacity = 70,
		UpgradeCost = 1200,
	},
	[4] = {
		Level = 4,
		Capacity = 110,
		UpgradeCost = 5000,
	},
	[5] = {
		Level = 5,
		Capacity = 160,
		UpgradeCost = 20000,
	},
}

local Economy = {
	SchemaVersion = 1,
	DataStoreName = "DigPalsPlayerData_v1",
	StartingCoins = 100,
	StartingShovel = "RustyShovel",
	StartingBagLevel = 1,
	StartingBaseLevel = 1,
	AutoSaveIntervalSeconds = 60,
	SessionLockExpireSeconds = 180,
	SessionLockRetryAttempts = 3,
	SessionLockRetryDelaySeconds = 1,
	PassiveIncomeTickSeconds = 1,
	OfflineIncomeMaxSeconds = 43200, -- 12 hours
	OfflineIncomeMultiplier = 0.10, -- 10% of active income
	MaxBagLevel = 5,
	BagLevels = BagLevels,
	SandyGate = {
		RequiredShovel = "IronShovel",
		UnlockCost = 10000,
	},
	Leaderboard = {
		UpdateIntervalSeconds = 300,
		DisplayTopCount = 10,
	},
	Security = {
		DefaultRemoteRateLimitPerSecond = 10,
	},
	OwnerUserIds = {
		[8535886514] = true,
	},
	-- Account-specific inventory entitlement; ordinary starting inventories stay unchanged.
	AllShovelsUserIds = {
		[8535886514] = true, -- truekatsu13
	},
}

return table.freeze(Economy)
