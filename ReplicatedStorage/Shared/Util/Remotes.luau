--!strict
--[[
	Centralized RemoteEvent & RemoteFunction registry, argument type validator,
	per-player per-remote rate limiter, and security violation tracker (Step 2).

	DOCUMENTED REMOTES:
	=========================================================================================
	Name                    | Kind           | Caller          | Arguments                         | RateLimit/s
	------------------------|----------------|-----------------|-----------------------------------|------------
	-- Digging & Mounds (Steps 3-5, 11)
	MoundSpawned            | RemoteEvent    | Server -> Client| (moundData: table)                | N/A
	MoundUpdated            | RemoteEvent    | Server -> Client| (moundId: string, hp: number, maxHp: number) | N/A
	MoundDespawned          | RemoteEvent    | Server -> Client| (moundId: string, reason: string) | N/A
	StartDig                | RemoteEvent    | Client -> Server| (moundId: string)                 | 10
	CancelDig               | RemoteEvent    | Client -> Server| ()                                | 10
	Strike                  | RemoteEvent    | Client -> Server| (moundId: string)                 | 10
	StrikeResult            | RemoteEvent    | Server -> Client| (resultData: table)               | N/A
	DropNotification        | RemoteEvent    | Server -> Client| (dropsList: table)                | N/A

	-- Inventory & Merchant (Step 6)
	SellItem                | RemoteFunction | Client -> Server| (itemId: string, count: posInt)   | 10
	SellAllItems            | RemoteFunction | Client -> Server| ()                                | 5
	UpgradeBag              | RemoteFunction | Client -> Server| ()                                | 5

	-- Shovel Shop & Shovel Inventory (Step 7 & Inventory PRD)
	BuyShovel               | RemoteFunction | Client -> Server| (shovelId: string)                | 5
	EquipShovel             | RemoteFunction | Client -> Server| (shovelId: string)                | 10
	GetInventoryState       | RemoteFunction | Client -> Server| ()                                | 5
	SetShovelToolActive     | RemoteEvent    | Client -> Server| (active: boolean)                 | 10

	-- Base & Incubators (Step 8)
	TeleportToBase          | RemoteEvent    | Client -> Server| ()                                | 5
	UpgradeBase             | RemoteFunction | Client -> Server| ()                                | 5
	PlaceEggInIncubator     | RemoteFunction | Client -> Server| (eggIndex: posInt, slotIndex: posInt) | 10
	SpeedUpIncubator        | RemoteFunction | Client -> Server| (slotIndex: posInt)               | 5
	HatchIncubator          | RemoteFunction | Client -> Server| (slotIndex: posInt)               | 10
	SellEgg                 | RemoteFunction | Client -> Server| (eggIndex: posInt)                | 10

	-- Pets & Passive Income (Steps 9-10)
	EquipPet                | RemoteFunction | Client -> Server| (petGuid: string)                 | 10
	UnequipPet              | RemoteFunction | Client -> Server| (petGuid: string)                 | 10
	AssignPetToBase         | RemoteFunction | Client -> Server| (petGuid: string)                 | 10
	RemovePetFromBase       | RemoteFunction | Client -> Server| (petGuid: string)                 | 10
	LevelUpPet              | RemoteFunction | Client -> Server| (petGuid: string)                 | 10
	ReleasePet              | RemoteFunction | Client -> Server| (petGuid: string)                 | 10
	OfflineIncomeSummary    | RemoteEvent    | Server -> Client| (summaryData: table)              | N/A
	PetAttackVisual         | RemoteEvent    | Server -> Client| (petGuid: string, moundId: string, damage: number) | N/A

	-- Shared Mound, Index, Quests, Streak, Tutorial, Sandy Gate (Steps 11-14)
	SharedMoundAlert        | RemoteEvent    | Server -> Client| (alertData: table)                | N/A
	IndexAlert              | RemoteEvent    | Server -> Client| (alertData: table)                | N/A
	GetIndexData            | RemoteFunction | Client -> Server| ()                                | 5
	ClaimQuest              | RemoteFunction | Client -> Server| (questId: string)                 | 5
	ClaimStreak             | RemoteFunction | Client -> Server| ()                                | 5
	GetLeaderboards         | RemoteFunction | Client -> Server| ()                                | 5
	LeaderboardUpdated      | RemoteEvent    | Server -> Client| (payload: table)                  | N/A
	UnlockSandyGate         | RemoteFunction | Client -> Server| ()                                | 5
	AdvanceTutorial         | RemoteEvent    | Client -> Server| (step: posInt)                    | 5
	StateSync               | RemoteEvent    | Server -> Client| (statePayload: table)             | N/A
	=========================================================================================
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))

export type ValidatorFn = (value: any) -> boolean
export type RemoteKind = "RemoteEvent" | "RemoteFunction"
export type RemoteDirection = "ClientToServer" | "ServerToClient"

export type RemoteSpec = {
	Name: string,
	Kind: RemoteKind,
	Direction: RemoteDirection,
	RateLimitPerSecond: number,
	Validators: { ValidatorFn },
	Description: string,
}

export type ViolationSummary = {
	TotalCount: number,
	ByReason: { [string]: number },
	ByRemote: { [string]: number },
	LastViolationAt: number,
	LastRemote: string,
	LastReason: string,
}

local DEFAULT_RATE_LIMIT = Economy.Security.DefaultRemoteRateLimitPerSecond

local Validators = {}

function Validators.String(value: any): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
end

function Validators.Number(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

function Validators.PositiveInt(value: any): boolean
	return type(value) == "number"
		and value == value
		and math.abs(value) ~= math.huge
		and math.floor(value) == value
		and value >= 1
end

function Validators.NonNegativeInt(value: any): boolean
	return type(value) == "number"
		and value == value
		and math.abs(value) ~= math.huge
		and math.floor(value) == value
		and value >= 0
end

function Validators.Boolean(value: any): boolean
	return type(value) == "boolean"
end

function Validators.Optional(inner: ValidatorFn): ValidatorFn
	return function(value: any): boolean
		if value == nil then
			return true
		end
		return inner(value)
	end
end

local Specs: { [string]: RemoteSpec } = {
	-- Digging & Mounds (Steps 3-5, 11)
	MoundSpawned = {
		Name = "MoundSpawned",
		Kind = "RemoteEvent",
		Direction = "ServerToClient",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = {},
		Description = "Server -> Client: Notifies client of a spawned personal or shared mound.",
	},
	MoundUpdated = {
		Name = "MoundUpdated",
		Kind = "RemoteEvent",
		Direction = "ServerToClient",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = {},
		Description = "Server -> Client: Updates remaining HP of a mound.",
	},
	MoundDespawned = {
		Name = "MoundDespawned",
		Kind = "RemoteEvent",
		Direction = "ServerToClient",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = {},
		Description = "Server -> Client: Notifies client that a mound expired or was cleared.",
	},
	StartDig = {
		Name = "StartDig",
		Kind = "RemoteEvent",
		Direction = "ClientToServer",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = { Validators.String },
		Description = "Client -> Server: Starts digging a mound by moundId (string).",
	},
	CancelDig = {
		Name = "CancelDig",
		Kind = "RemoteEvent",
		Direction = "ClientToServer",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = {},
		Description = "Client -> Server: Cancels the active digging session.",
	},
	Strike = {
		Name = "Strike",
		Kind = "RemoteEvent",
		Direction = "ClientToServer",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = { Validators.String },
		Description = "Client -> Server: Sends a timing bar strike for moundId (string).",
	},
	StrikeResult = {
		Name = "StrikeResult",
		Kind = "RemoteEvent",
		Direction = "ServerToClient",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = {},
		Description = "Server -> Client: Sends authoritative strike grade (Perfect/Good/Miss) and damage.",
	},
	DropNotification = {
		Name = "DropNotification",
		Kind = "RemoteEvent",
		Direction = "ServerToClient",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = {},
		Description = "Server -> Client: Sends list of drops obtained when a mound breaks.",
	},

	-- Inventory & Merchant (Step 6)
	SellItem = {
		Name = "SellItem",
		Kind = "RemoteFunction",
		Direction = "ClientToServer",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = { Validators.String, Validators.PositiveInt },
		Description = "Client -> Server: Sells a specific quantity of itemId (string, positiveInt).",
	},
	SellAllItems = {
		Name = "SellAllItems",
		Kind = "RemoteFunction",
		Direction = "ClientToServer",
		RateLimitPerSecond = 5,
		Validators = {},
		Description = "Client -> Server: Sells all items currently in the player's bag.",
	},
	UpgradeBag = {
		Name = "UpgradeBag",
		Kind = "RemoteFunction",
		Direction = "ClientToServer",
		RateLimitPerSecond = 5,
		Validators = {},
		Description = "Client -> Server: Purchases the next BagLevel upgrade.",
	},

	-- Shovel Shop (Step 7)
	BuyShovel = {
		Name = "BuyShovel",
		Kind = "RemoteFunction",
		Direction = "ClientToServer",
		RateLimitPerSecond = 5,
		Validators = { Validators.String },
		Description = "Client -> Server: Purchases shovelId (string) from the Shovel Shop.",
	},
	EquipShovel = {
		Name = "EquipShovel",
		Kind = "RemoteFunction",
		Direction = "ClientToServer",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = { Validators.String },
		Description = "Client -> Server: Equips an owned shovelId (string).",
	},
	GetInventoryState = {
		Name = "GetInventoryState",
		Kind = "RemoteFunction",
		Direction = "ClientToServer",
		RateLimitPerSecond = 5,
		Validators = {},
		Description = "Client -> Server: Fetches authoritative initial shovel and inventory state once profile is loaded.",
	},
	SetShovelToolActive = {
		Name = "SetShovelToolActive",
		Kind = "RemoteEvent",
		Direction = "ClientToServer",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = { Validators.Boolean },
		Description = "Client -> Server: Equips or stows the player's active Shovel Tool in Character/Backpack.",
	},

	-- Base & Incubators (Step 8)
	TeleportToBase = {
		Name = "TeleportToBase",
		Kind = "RemoteEvent",
		Direction = "ClientToServer",
		RateLimitPerSecond = 5,
		Validators = {},
		Description = "Client -> Server: Teleports the player to their assigned Base plot.",
	},
	UpgradeBase = {
		Name = "UpgradeBase",
		Kind = "RemoteFunction",
		Direction = "ClientToServer",
		RateLimitPerSecond = 5,
		Validators = {},
		Description = "Client -> Server: Purchases the next BaseLevel upgrade.",
	},
	PlaceEggInIncubator = {
		Name = "PlaceEggInIncubator",
		Kind = "RemoteFunction",
		Direction = "ClientToServer",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = { Validators.PositiveInt, Validators.PositiveInt },
		Description = "Client -> Server: Places egg at eggBagIndex into incubator slotIndex (posInt, posInt).",
	},
	SpeedUpIncubator = {
		Name = "SpeedUpIncubator",
		Kind = "RemoteFunction",
		Direction = "ClientToServer",
		RateLimitPerSecond = 5,
		Validators = { Validators.PositiveInt },
		Description = "Client -> Server: Pays coins to speed up incubator at slotIndex (posInt).",
	},
	HatchIncubator = {
		Name = "HatchIncubator",
		Kind = "RemoteFunction",
		Direction = "ClientToServer",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = { Validators.PositiveInt },
		Description = "Client -> Server: Hatches a ready egg at incubator slotIndex (posInt).",
	},
	SellEgg = {
		Name = "SellEgg",
		Kind = "RemoteFunction",
		Direction = "ClientToServer",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = { Validators.PositiveInt },
		Description = "Client -> Server: Sells an egg from EggBag at eggBagIndex (posInt).",
	},

	-- Pets & Passive Income (Steps 9-10)
	EquipPet = {
		Name = "EquipPet",
		Kind = "RemoteFunction",
		Direction = "ClientToServer",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = { Validators.String },
		Description = "Client -> Server: Equips pet by petGuid (string).",
	},
	UnequipPet = {
		Name = "UnequipPet",
		Kind = "RemoteFunction",
		Direction = "ClientToServer",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = { Validators.String },
		Description = "Client -> Server: Unequips active pet by petGuid (string).",
	},
	AssignPetToBase = {
		Name = "AssignPetToBase",
		Kind = "RemoteFunction",
		Direction = "ClientToServer",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = { Validators.String },
		Description = "Client -> Server: Assigns pet by petGuid (string) to Base plot.",
	},
	RemovePetFromBase = {
		Name = "RemovePetFromBase",
		Kind = "RemoteFunction",
		Direction = "ClientToServer",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = { Validators.String },
		Description = "Client -> Server: Removes pet by petGuid (string) from Base plot.",
	},
	LevelUpPet = {
		Name = "LevelUpPet",
		Kind = "RemoteFunction",
		Direction = "ClientToServer",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = { Validators.String },
		Description = "Client -> Server: Levels up pet by petGuid (string) using coins.",
	},
	ReleasePet = {
		Name = "ReleasePet",
		Kind = "RemoteFunction",
		Direction = "ClientToServer",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = { Validators.String },
		Description = "Client -> Server: Releases pet by petGuid (string) for coins.",
	},
	OfflineIncomeSummary = {
		Name = "OfflineIncomeSummary",
		Kind = "RemoteEvent",
		Direction = "ServerToClient",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = {},
		Description = "Server -> Client: Sends offline passive income popup summary on join.",
	},
	PetAttackVisual = {
		Name = "PetAttackVisual",
		Kind = "RemoteEvent",
		Direction = "ServerToClient",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = {},
		Description = "Server -> Client: Notifies client when an equipped pet strikes a mound (petGuid, moundId, damage).",
	},

	-- Shared Mound, Index, Quests, Streak, Tutorial, Sandy Gate (Steps 11-14)
	SharedMoundAlert = {
		Name = "SharedMoundAlert",
		Kind = "RemoteEvent",
		Direction = "ServerToClient",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = {},
		Description = "Server -> Client: Broadcasts Rare Mound spawn and expiration notifications.",
	},
	IndexAlert = {
		Name = "IndexAlert",
		Kind = "RemoteEvent",
		Direction = "ServerToClient",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = {},
		Description = "Server -> Client: Notifies client when a new item/pet is discovered or a rarity set is completed.",
	},
	GetIndexData = {
		Name = "GetIndexData",
		Kind = "RemoteFunction",
		Direction = "ClientToServer",
		RateLimitPerSecond = 5,
		Validators = {},
		Description = "Client -> Server: Fetches complete index discovery and completion stats.",
	},
	ClaimQuest = {
		Name = "ClaimQuest",
		Kind = "RemoteFunction",
		Direction = "ClientToServer",
		RateLimitPerSecond = 5,
		Validators = { Validators.String },
		Description = "Client -> Server: Claims daily quest reward for questId (string).",
	},
	ClaimStreak = {
		Name = "ClaimStreak",
		Kind = "RemoteFunction",
		Direction = "ClientToServer",
		RateLimitPerSecond = 5,
		Validators = {},
		Description = "Client -> Server: Claims daily login streak reward.",
	},
	GetLeaderboards = {
		Name = "GetLeaderboards",
		Kind = "RemoteFunction",
		Direction = "ClientToServer",
		RateLimitPerSecond = 5,
		Validators = {},
		Description = "Client -> Server: Fetches cached top 10 leaderboard rankings for all categories.",
	},
	LeaderboardUpdated = {
		Name = "LeaderboardUpdated",
		Kind = "RemoteEvent",
		Direction = "ServerToClient",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = {},
		Description = "Server -> Client: Broadcasts updated leaderboard top 10 data when refreshed.",
	},
	UnlockSandyGate = {
		Name = "UnlockSandyGate",
		Kind = "RemoteFunction",
		Direction = "ClientToServer",
		RateLimitPerSecond = 5,
		Validators = {},
		Description = "Client -> Server: Unlocks Sandy Gate if player owns IronShovel+ and 10,000 coins.",
	},
	AdvanceTutorial = {
		Name = "AdvanceTutorial",
		Kind = "RemoteEvent",
		Direction = "ClientToServer",
		RateLimitPerSecond = 5,
		Validators = { Validators.PositiveInt },
		Description = "Client -> Server: Advances onboarding tutorial step (posInt).",
	},
	StateSync = {
		Name = "StateSync",
		Kind = "RemoteEvent",
		Direction = "ServerToClient",
		RateLimitPerSecond = DEFAULT_RATE_LIMIT,
		Validators = {},
		Description = "Server -> Client: Synchronizes profile data for client UI panels.",
	},
}

local Remotes = {
	Validators = Validators,
	Specs = Specs,
}

-- Per-userId rate limit state: rateBuckets[userId][remoteName] = { windowStart: number, count: number }
local rateBuckets: { [number]: { [string]: { WindowStart: number, Count: number } } } = {}

-- Per-userId security violation log
local violationsByUserId: { [number]: ViolationSummary } = {}

local function getRemotesFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if folder and folder:IsA("Folder") then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = "Remotes"
	created.Parent = ReplicatedStorage
	return created
end

local function recordViolation(userId: number, playerName: string, remoteName: string, reason: string)
	local summary = violationsByUserId[userId]
	if not summary then
		summary = {
			TotalCount = 0,
			ByReason = {},
			ByRemote = {},
			LastViolationAt = os.time(),
			LastRemote = remoteName,
			LastReason = reason,
		}
		violationsByUserId[userId] = summary
	end

	summary.TotalCount += 1
	summary.ByReason[reason] = (summary.ByReason[reason] or 0) + 1
	summary.ByRemote[remoteName] = (summary.ByRemote[remoteName] or 0) + 1
	summary.LastViolationAt = os.time()
	summary.LastRemote = remoteName
	summary.LastReason = reason

	print(
		string.format(
			"[RemotesSecurity] Violation recorded | Player=%s (%d) | Remote=%s | Reason=%s | TotalViolations=%d",
			playerName,
			userId,
			remoteName,
			reason,
			summary.TotalCount
		)
	)
end

function Remotes.CheckRateLimit(userId: number, playerName: string, remoteName: string, nowClock: number?): boolean
	local spec = Specs[remoteName]
	local maxPerSec = if spec then spec.RateLimitPerSecond else DEFAULT_RATE_LIMIT
	local now = nowClock or os.clock()

	local userBuckets = rateBuckets[userId]
	if not userBuckets then
		userBuckets = {}
		rateBuckets[userId] = userBuckets
	end

	local bucket = userBuckets[remoteName]
	if not bucket or (now - bucket.WindowStart) >= 1.0 then
		userBuckets[remoteName] = {
			WindowStart = now,
			Count = 1,
		}
		return true
	end

	bucket.Count += 1
	if bucket.Count > maxPerSec then
		recordViolation(userId, playerName, remoteName, "RateLimitExceeded")
		return false
	end

	return true
end

function Remotes.ValidateArgs(userId: number, playerName: string, remoteName: string, ...: any): boolean
	local spec = Specs[remoteName]
	if not spec then
		recordViolation(userId, playerName, remoteName, "UnknownRemote")
		return false
	end

	if spec.Direction ~= "ClientToServer" then
		recordViolation(userId, playerName, remoteName, "InvalidDirection")
		return false
	end

	local argCount = select("#", ...)
	local validators = spec.Validators

	if argCount > #validators then
		recordViolation(userId, playerName, remoteName, "TooManyArguments")
		return false
	end

	for i, validator in validators do
		local argVal = select(i, ...)
		local ok, isValid = pcall(validator, argVal)
		if not ok or not isValid then
			recordViolation(userId, playerName, remoteName, string.format("InvalidArgument_%d", i))
			return false
		end
	end

	return true
end

function Remotes.ValidateAndThrottle(
	userId: number,
	playerName: string,
	remoteName: string,
	nowClock: number?,
	...: any
): (boolean, string?)
	if not Remotes.CheckRateLimit(userId, playerName, remoteName, nowClock) then
		return false, "RateLimitExceeded"
	end
	if not Remotes.ValidateArgs(userId, playerName, remoteName, ...) then
		return false, "InvalidArguments"
	end
	return true, nil
end

function Remotes.GetViolationSummary(userId: number): ViolationSummary
	local existing = violationsByUserId[userId]
	if existing then
		return existing
	end
	return {
		TotalCount = 0,
		ByReason = {},
		ByRemote = {},
		LastViolationAt = 0,
		LastRemote = "",
		LastReason = "",
	}
end

function Remotes.ResetViolations(userId: number)
	violationsByUserId[userId] = nil
	rateBuckets[userId] = nil
end

function Remotes.EnsureAll(): Folder
	local folder = getRemotesFolder()
	for remoteName, spec in Specs do
		local existing = folder:FindFirstChild(remoteName)
		if not existing then
			local instance = Instance.new(spec.Kind)
			instance.Name = remoteName
			instance.Parent = folder
		end
	end
	return folder
end

function Remotes.GetEvent(remoteName: string): RemoteEvent
	local spec = Specs[remoteName]
	assert(spec and spec.Kind == "RemoteEvent", "Invalid RemoteEvent name: " .. tostring(remoteName))
	local folder = getRemotesFolder()
	local existing = folder:FindFirstChild(remoteName)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local created = Instance.new("RemoteEvent")
	created.Name = remoteName
	created.Parent = folder
	return created
end

function Remotes.GetFunction(remoteName: string): RemoteFunction
	local spec = Specs[remoteName]
	assert(spec and spec.Kind == "RemoteFunction", "Invalid RemoteFunction name: " .. tostring(remoteName))
	local folder = getRemotesFolder()
	local existing = folder:FindFirstChild(remoteName)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	local created = Instance.new("RemoteFunction")
	created.Name = remoteName
	created.Parent = folder
	return created
end

function Remotes.OnServerEvent(remoteName: string, handler: (player: Player, ...any) -> ()): RBXScriptConnection
	local remoteEvent = Remotes.GetEvent(remoteName)
	return remoteEvent.OnServerEvent:Connect(function(player: Player, ...: any)
		local allowed = Remotes.ValidateAndThrottle(player.UserId, player.Name, remoteName, nil, ...)
		if not allowed then
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(string.format("[Remotes] Handler error in %s for %s: %s", remoteName, player.Name, tostring(err)))
		end
	end)
end

function Remotes.OnServerInvoke(remoteName: string, handler: (player: Player, ...any) -> any)
	local remoteFunction = Remotes.GetFunction(remoteName)
	remoteFunction.OnServerInvoke = function(player: Player, ...: any): any
		local allowed, rejectReason = Remotes.ValidateAndThrottle(player.UserId, player.Name, remoteName, nil, ...)
		if not allowed then
			return {
				Success = false,
				Reason = rejectReason or "Rejected",
			}
		end
		local ok, result = pcall(handler, player, ...)
		if not ok then
			warn(string.format("[Remotes] Invoke error in %s for %s: %s", remoteName, player.Name, tostring(result)))
			return {
				Success = false,
				Reason = "InternalServerError",
			}
		end
		return result
	end
end

if RunService:IsServer() then
	Players.PlayerRemoving:Connect(function(player: Player)
		rateBuckets[player.UserId] = nil
	end)
end

return Remotes
