--!strict
-- Player profile persistence service with session locking, autosave, and Studio fallback (Step 1)

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))
local Economy = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))

type StoredRecord = {
	Profile: Types.PlayerProfile,
	Meta: {
		SessionJobId: string?,
		SessionLockTime: number,
	},
}

type ActiveSession = {
	UserId: number,
	SessionId: string,
	Profile: Types.PlayerProfile,
	SessionStartTime: number?,
}

local DataService = {}

local activeSessions: { [number]: ActiveSession } = {}
local memoryFallbackStore: { [string]: StoredRecord } = {}
local usingMemoryFallback = false
local dataStore: DataStore? = nil
local isShuttingDown = false
local started = false

local profileLoadedCallbacks: { (player: Player, profile: Types.PlayerProfile) -> () } = {}
local profileRemovingCallbacks: { (player: Player, profile: Types.PlayerProfile) -> () } = {}

local serverSessionPrefix = if game.JobId ~= "" then game.JobId else "Studio_" .. HttpService:GenerateGUID(false)

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy: { [any]: any } = {}
	for k, v in value :: any do
		copy[deepCopy(k)] = deepCopy(v)
	end
	return (copy :: any) :: T
end

function DataService.CreateDefaultProfile(): Types.PlayerProfile
	return {
		SchemaVersion = Economy.SchemaVersion,
		Coins = Economy.StartingCoins,
		TotalCoinsEarned = 0,
		Shovels = {
			Owned = { Economy.StartingShovel },
			Equipped = Economy.StartingShovel,
		},
		BagLevel = Economy.StartingBagLevel,
		BaseLevel = Economy.StartingBaseLevel,
		Items = {},
		EggBag = {
			{
				Id = "StarterEgg",
				Rarity = "Common",
			},
		},
		Incubators = {},
		Pets = {},
		EquippedPets = {},
		BasePets = {},
		Index = {
			Pets = {},
			Items = {},
		},
		Quests = {
			Day = 0,
			List = {},
		},
		Streak = {
			Day = 0,
			LastClaim = 0,
		},
		Tutorial = {
			Step = 1,
			Done = false,
		},
		SandyGateUnlocked = false,
		WeeklyCoins = {
			Week = 0,
			Coins = 0,
		},
		CreatedAt = os.time(),
		TotalPlayTime = 0,
		LegendaryCount = 0,
		LastSeen = os.time(),
	}
end

local function reconcileTable(target: { [any]: any }, template: { [any]: any })
	for k, defaultVal in template do
		if target[k] == nil then
			target[k] = deepCopy(defaultVal)
		elseif type(target[k]) == "table" and type(defaultVal) == "table" then
			reconcileTable(target[k], defaultVal)
		end
	end
end

function DataService.ReconcileProfile(rawProfile: any): Types.PlayerProfile
	local defaultProfile = DataService.CreateDefaultProfile()
	if type(rawProfile) ~= "table" then
		return defaultProfile
	end
	local copy = deepCopy(rawProfile)
	reconcileTable(copy, defaultProfile :: any)
	return copy :: Types.PlayerProfile
end

local function getStoreKey(userId: number): string
	return "Player_" .. tostring(userId)
end

local function initDataStore()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Economy.DataStoreName)
	end)
	if ok and result then
		dataStore = result
	else
		usingMemoryFallback = true
		warn(string.format("[DataService] Could not get DataStore (%s). Falling back to in-memory store.", tostring(result)))
	end
end

local function performUpdateAsync(key: string, transformFn: (oldRecord: StoredRecord?) -> StoredRecord?): (boolean, StoredRecord?, string?)
	if not usingMemoryFallback and dataStore ~= nil then
		local store = dataStore
		local ok, result = pcall(function()
			return store:UpdateAsync(key, function(oldValue: any)
				return transformFn(oldValue :: StoredRecord?)
			end)
		end)
		if ok then
			return true, result :: StoredRecord?, nil
		end

		local errMsg = tostring(result)
		if RunService:IsStudio() then
			usingMemoryFallback = true
			warn(
				string.format(
					"[DataService] DataStore UpdateAsync unavailable in Studio (%s). Switching to in-memory fallback store.",
					errMsg
				)
			)
		else
			return false, nil, errMsg
		end
	end

	-- In-memory fallback with identical atomic UpdateAsync semantics
	local current = memoryFallbackStore[key]
	local currentCopy = if current ~= nil then deepCopy(current) else nil
	local okTransform, updated = pcall(transformFn, currentCopy)
	if not okTransform then
		return false, nil, tostring(updated)
	end
	if updated ~= nil then
		memoryFallbackStore[key] = deepCopy(updated)
		return true, deepCopy(updated), nil
	end
	return true, nil, nil
end

function DataService.AcquireProfileLock(
	userId: number,
	sessionId: string,
	skipRetryWait: boolean?
): (boolean, Types.PlayerProfile?, string?)
	local key = getStoreKey(userId)
	local maxAttempts = Economy.SessionLockRetryAttempts

	for attempt = 1, maxAttempts do
		local lockedByOther = false
		local now = os.time()

		local ok, updatedRecord, errMsg = performUpdateAsync(key, function(oldRecord: StoredRecord?): StoredRecord?
			if oldRecord ~= nil and type(oldRecord) == "table" and type(oldRecord.Meta) == "table" then
				local holder = oldRecord.Meta.SessionJobId
				local lockTime = oldRecord.Meta.SessionLockTime or 0
				if holder ~= nil and holder ~= sessionId and (now - lockTime) < Economy.SessionLockExpireSeconds then
					lockedByOther = true
					return nil
				end
			end

			local reconciled = if oldRecord ~= nil and oldRecord.Profile ~= nil
				then DataService.ReconcileProfile(oldRecord.Profile)
				else DataService.CreateDefaultProfile()

			return {
				Profile = reconciled,
				Meta = {
					SessionJobId = sessionId,
					SessionLockTime = now,
				},
			}
		end)

		if not ok then
			return false, nil, errMsg or "DataStore error"
		end

		if not lockedByOther and updatedRecord ~= nil then
			return true, updatedRecord.Profile, nil
		end

		if attempt < maxAttempts and not skipRetryWait then
			task.wait(Economy.SessionLockRetryDelaySeconds)
		end
	end

	return false, nil, "SessionLockActive"
end

function DataService.SaveProfileSession(
	userId: number,
	sessionId: string,
	profile: Types.PlayerProfile,
	releaseLock: boolean
): (boolean, string?)
	local key = getStoreKey(userId)
	local now = os.time()
	local lockConflict = false

	local session = activeSessions[userId]
	if session and session.SessionStartTime then
		local elapsed = now - session.SessionStartTime
		session.SessionStartTime = now
		profile.TotalPlayTime = (profile.TotalPlayTime or 0) + elapsed
	end

	local snapshot = deepCopy(profile)
	snapshot.LastSeen = now

	local ok, _, errMsg = performUpdateAsync(key, function(oldRecord: StoredRecord?): StoredRecord?
		if oldRecord ~= nil and type(oldRecord) == "table" and type(oldRecord.Meta) == "table" then
			local holder = oldRecord.Meta.SessionJobId
			local lockTime = oldRecord.Meta.SessionLockTime or 0
			if holder ~= nil and holder ~= sessionId and (now - lockTime) < Economy.SessionLockExpireSeconds then
				lockConflict = true
				return nil
			end
		end

		return {
			Profile = snapshot,
			Meta = {
				SessionJobId = if releaseLock then nil else sessionId,
				SessionLockTime = if releaseLock then 0 else now,
			},
		}
	end)

	if not ok then
		warn(string.format("[DataService] Failed to save profile for UserId %d: %s", userId, tostring(errMsg)))
		return false, errMsg
	end

	if lockConflict then
		warn(string.format("[DataService] Session lock conflict while saving UserId %d", userId))
		return false, "SessionLockConflict"
	end

	return true, nil
end

function DataService.GetProfile(player: Player): Types.PlayerProfile?
	local session = activeSessions[player.UserId]
	if session then
		return session.Profile
	end
	return nil
end

function DataService.OnProfileLoaded(callback: (player: Player, profile: Types.PlayerProfile) -> ())
	table.insert(profileLoadedCallbacks, callback)
	for _, player in Players:GetPlayers() do
		local session = activeSessions[player.UserId]
		if session then
			task.spawn(callback, player, session.Profile)
		end
	end
end

function DataService.OnProfileRemoving(callback: (player: Player, profile: Types.PlayerProfile) -> ())
	table.insert(profileRemovingCallbacks, callback)
end

function DataService.LoadPlayer(player: Player): boolean
	local userId = player.UserId
	local sessionId = string.format("%s_%d", serverSessionPrefix, userId)

	local ok, profile, errReason = DataService.AcquireProfileLock(userId, sessionId, false)
	if not ok or profile == nil then
		warn(string.format("[DataService] Failed to load profile for %s (%d): %s", player.Name, userId, tostring(errReason)))
		pcall(function()
			player:Kick("Failed to load your Dig Pals data or profile is open in another session. Please rejoin.")
		end)
		return false
	end

	if player.Parent ~= Players then
		-- Player left during async load; release lock immediately
		DataService.SaveProfileSession(userId, sessionId, profile, true)
		return false
	end

	activeSessions[userId] = {
		UserId = userId,
		SessionId = sessionId,
		Profile = profile,
		SessionStartTime = os.time(),
	}

	for _, callback in profileLoadedCallbacks do
		task.spawn(callback, player, profile)
	end

	return true
end

function DataService.ReleasePlayer(player: Player)
	local userId = player.UserId
	local session = activeSessions[userId]
	if not session then
		return
	end

	for _, callback in profileRemovingCallbacks do
		pcall(callback, player, session.Profile)
	end

	activeSessions[userId] = nil
	DataService.SaveProfileSession(userId, session.SessionId, session.Profile, true)
end

function DataService.SavePlayer(player: Player): boolean
	local session = activeSessions[player.UserId]
	if not session then
		return false
	end
	local ok = DataService.SaveProfileSession(session.UserId, session.SessionId, session.Profile, false)
	return ok
end

function DataService.GetTotalPlayTime(userId: number): number
	local session = activeSessions[userId]
	if not session then
		return 0
	end
	local now = os.time()
	local elapsed = if session.SessionStartTime then (now - session.SessionStartTime) else 0
	return (session.Profile.TotalPlayTime or 0) + elapsed
end

function DataService.IsUsingMemoryFallback(): boolean
	return usingMemoryFallback
end

function DataService.Start()
	if started then
		return
	end
	started = true

	Players.PlayerAdded:Connect(function(player: Player)
		DataService.LoadPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		if not isShuttingDown then
			DataService.ReleasePlayer(player)
		end
	end)

	initDataStore()

	for _, player in Players:GetPlayers() do
		task.spawn(function()
			DataService.LoadPlayer(player)
		end)
	end

	-- Autosave loop every Economy.AutoSaveIntervalSeconds (60s)
	task.spawn(function()
		while not isShuttingDown do
			task.wait(Economy.AutoSaveIntervalSeconds)
			if isShuttingDown then
				break
			end
			for _, session in activeSessions do
				task.spawn(function()
					DataService.SaveProfileSession(session.UserId, session.SessionId, session.Profile, false)
				end)
			end
		end
	end)

	game:BindToClose(function()
		isShuttingDown = true
		local remaining = 0
		for _, session in activeSessions do
			remaining += 1
			task.spawn(function()
				DataService.SaveProfileSession(session.UserId, session.SessionId, session.Profile, true)
				remaining -= 1
			end)
		end
		activeSessions = {}

		local startWait = os.clock()
		while remaining > 0 and (os.clock() - startWait) < 25 do
			task.wait(0.05)
		end
	end)
end

return DataService
