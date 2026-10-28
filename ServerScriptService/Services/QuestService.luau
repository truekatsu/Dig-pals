--!strict
-- Authoritative Quest & Login Streak Service: 3 daily quests from pool of 8, UTC 00:00 reset, and 7-day progressive streak (Step 12)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local QuestsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Quests"))
local EggsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Eggs"))

local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
local ShovelInventoryService = require(script.Parent:WaitForChild("ShovelInventoryService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local DataService = require(script.Parent:WaitForChild("DataService"))

export type ClaimQuestResult = {
	Success: boolean,
	QuestId: string?,
	RewardCoins: number?,
	RewardEggId: string?,
	ErrorReason: string?,
}

export type ClaimStreakResult = {
	Success: boolean,
	Day: number?,
	RewardCoins: number?,
	RewardEggId: string?,
	ErrorReason: string?,
}

export type StreakStatus = {
	CanClaim: boolean,
	CurrentDay: number,
	TodayStreakDay: number,
	LastClaimDay: number,
	DaysUntilReset: number,
	StreakBroken: boolean,
	Rewards: { [number]: QuestsConfig.StreakReward },
}

local QuestService = {}

local timeOverride: number? = nil
local activePerfectStreakByUserId: { [number]: number } = {}
local started = false

local questDefById: { [string]: QuestsConfig.QuestDefinition } = {}
for _, def in ipairs(QuestsConfig.Pool) do
	questDefById[def.Id] = def
end

function QuestService.SetTimeOverride(timestamp: number?)
	timeOverride = timestamp
end

function QuestService.GetCurrentTime(): number
	return timeOverride or os.time()
end

function QuestService.GetCurrentUtcDay(): number
	local t = QuestService.GetCurrentTime()
	return math.floor(t / 86400)
end

function QuestService.GetSecondsUntilUtcMidnight(): number
	local t = QuestService.GetCurrentTime()
	local dayStart = math.floor(t / 86400) * 86400
	local nextMidnight = dayStart + 86400
	return math.max(0, nextMidnight - t)
end

local function ensureQuestsTable(profile: Types.PlayerProfile, userId: number)
	if type(profile.Quests) ~= "table" then
		profile.Quests = { Day = 0, List = {} }
	end

	local currentDay = QuestService.GetCurrentUtcDay()
	if profile.Quests.Day ~= currentDay or not profile.Quests.List or #profile.Quests.List == 0 then
		profile.Quests.Day = currentDay
		profile.Quests.List = {}

		-- Deterministically pick 3 distinct quests based on userId + day
		local poolCopy = table.clone(QuestsConfig.Pool)
		local rng = Random.new(math.abs(userId + (currentDay * 7919)))

		for _ = 1, math.min(QuestsConfig.DailyQuestCount, #poolCopy) do
			local idx = rng:NextInteger(1, #poolCopy)
			local chosenDef = poolCopy[idx]
			table.remove(poolCopy, idx)

			table.insert(profile.Quests.List, {
				Id = chosenDef.Id,
				Progress = 0,
				Claimed = false,
			})
		end
	end
end

local function ensureStreakTable(profile: Types.PlayerProfile)
	if type(profile.Streak) ~= "table" then
		profile.Streak = { Day = 0, LastClaim = 0 }
	end
end

function QuestService.EnsureProfileQuests(profile: Types.PlayerProfile, userId: number)
	ensureQuestsTable(profile, userId)
	ensureStreakTable(profile)
end

function QuestService.GetStreakStatus(profile: Types.PlayerProfile): StreakStatus
	ensureStreakTable(profile)
	local currentDay = QuestService.GetCurrentUtcDay()
	local lastClaim = profile.Streak.LastClaim or 0
	local storedDay = profile.Streak.Day or 0

	local canClaim = false
	local streakBroken = false
	local todayStreakDay = 1

	if lastClaim == 0 then
		-- First time player
		canClaim = true
		todayStreakDay = 1
	elseif lastClaim == currentDay then
		-- Already claimed today
		canClaim = false
		todayStreakDay = storedDay
	elseif lastClaim == currentDay - 1 then
		-- Consecutively logged in yesterday: advance day
		canClaim = true
		todayStreakDay = if storedDay >= QuestsConfig.StreakLengthDays then 1 else storedDay + 1
	else
		-- Missed at least one day: streak breaks!
		canClaim = true
		streakBroken = true
		todayStreakDay = 1
	end

	return {
		CanClaim = canClaim,
		CurrentDay = currentDay,
		TodayStreakDay = todayStreakDay,
		LastClaimDay = lastClaim,
		DaysUntilReset = if canClaim then 0 else 1,
		StreakBroken = streakBroken,
		Rewards = QuestsConfig.StreakRewards,
	}
end

function QuestService.RecordProgressForProfile(
	profile: Types.PlayerProfile,
	userId: number,
	eventType: string,
	amount: number?
): boolean
	ensureQuestsTable(profile, userId)
	local amt = amount or 1
	local changed = false

	if eventType == "PerfectStrike" then
		local streak = (activePerfectStreakByUserId[userId] or 0) + 1
		activePerfectStreakByUserId[userId] = streak
		amt = streak
	elseif eventType == "BreakPerfectStreak" then
		activePerfectStreakByUserId[userId] = 0
		return false
	end

	for _, qEntry in ipairs(profile.Quests.List) do
		if not qEntry.Claimed then
			local def = questDefById[qEntry.Id]
			if def and def.EventType == eventType then
				local oldProg = qEntry.Progress
				if def.EventType == "PerfectStreak" then
					qEntry.Progress = math.min(def.Target, math.max(qEntry.Progress, amt))
				else
					qEntry.Progress = math.min(def.Target, qEntry.Progress + amt)
				end
				if qEntry.Progress ~= oldProg then
					changed = true
					print(string.format("[QuestService] User %d progress on %s: %d/%d", userId, def.Id, qEntry.Progress, def.Target))
				end
			end
		end
	end

	return changed
end

function QuestService.RecordProgress(
	player: Player,
	eventType: string,
	amount: number?,
	metadata: any?
)
	local profile = PlayerState.Get(player)
	if not profile then
		return
	end

	local changed = false
	PlayerState.Mutate(player, function(mutableProfile: Types.PlayerProfile)
		changed = QuestService.RecordProgressForProfile(mutableProfile, player.UserId, eventType, amount)
	end)

	if changed then
		ShovelInventoryService.SendStateSync(player)
	end
end

function QuestService.ClaimQuestForProfile(
	profile: Types.PlayerProfile,
	userId: number,
	questId: string
): ClaimQuestResult
	ensureQuestsTable(profile, userId)
	local targetEntry: Types.QuestEntry? = nil
	for _, q in ipairs(profile.Quests.List) do
		if q.Id == questId then
			targetEntry = q
			break
		end
	end

	if not targetEntry then
		return { Success = false, ErrorReason = "QuestNotFound" }
	end

	if targetEntry.Claimed then
		return { Success = false, ErrorReason = "AlreadyClaimed" }
	end

	local def = questDefById[questId]
	if not def then
		return { Success = false, ErrorReason = "InvalidQuestDefinition" }
	end

	if targetEntry.Progress < def.Target then
		return { Success = false, ErrorReason = "TargetNotReached" }
	end

	local rewardCoins = def.RewardCoins or 0
	local rewardEggId = def.RewardEggId

	targetEntry.Claimed = true

	if rewardCoins > 0 then
		profile.Coins = math.max(0, profile.Coins + rewardCoins)
		profile.TotalCoinsEarned = math.max(0, profile.TotalCoinsEarned + rewardCoins)
		local LeaderboardService = require(script.Parent:WaitForChild("LeaderboardService"))
		LeaderboardService.RecordCoinsEarned(profile, rewardCoins)
	end

	if rewardEggId and EggsConfig.All[rewardEggId] then
		InventoryService.AddDropToProfile(profile, {
			DropType = "Egg",
			Id = rewardEggId,
			DisplayName = EggsConfig.All[rewardEggId].DisplayName,
			Rarity = EggsConfig.All[rewardEggId].Rarity,
			SellPrice = EggsConfig.All[rewardEggId].SellPrice,
			AutoSold = false,
			AutoSoldCoins = 0,
		})
	end

	return {
		Success = true,
		QuestId = questId,
		RewardCoins = rewardCoins,
		RewardEggId = rewardEggId,
	}
end

function QuestService.ClaimQuest(player: Player, questId: string): ClaimQuestResult
	local profile = PlayerState.Get(player)
	if not profile then
		return { Success = false, ErrorReason = "ProfileNotLoaded" }
	end

	local result: ClaimQuestResult = { Success = false }
	PlayerState.Mutate(player, function(mutableProfile: Types.PlayerProfile)
		result = QuestService.ClaimQuestForProfile(mutableProfile, player.UserId, questId)
	end)

	if result.Success then
		ShovelInventoryService.SendStateSync(player)
		DataService.SavePlayer(player)
		print(string.format("[QuestService] %s claimed Quest %s (+%d Coins, Egg: %s)", player.Name, questId, result.RewardCoins or 0, tostring(result.RewardEggId)))
	end

	return result
end

function QuestService.ClaimStreakForProfile(
	profile: Types.PlayerProfile
): ClaimStreakResult
	local status = QuestService.GetStreakStatus(profile)
	if not status.CanClaim then
		return { Success = false, ErrorReason = "AlreadyClaimedToday" }
	end

	local streakDay = status.TodayStreakDay
	local reward = QuestsConfig.StreakRewards[streakDay]
	if not reward then
		return { Success = false, ErrorReason = "InvalidStreakReward" }
	end

	local rewardCoins = reward.RewardCoins or 0
	local rewardEggId = reward.RewardEggId
	local currentDay = status.CurrentDay

	ensureStreakTable(profile)
	profile.Streak.Day = streakDay
	profile.Streak.LastClaim = currentDay

	if rewardCoins > 0 then
		profile.Coins = math.max(0, profile.Coins + rewardCoins)
		profile.TotalCoinsEarned = math.max(0, profile.TotalCoinsEarned + rewardCoins)
		local LeaderboardService = require(script.Parent:WaitForChild("LeaderboardService"))
		LeaderboardService.RecordCoinsEarned(profile, rewardCoins)
	end

	if rewardEggId and EggsConfig.All[rewardEggId] then
		InventoryService.AddDropToProfile(profile, {
			DropType = "Egg",
			Id = rewardEggId,
			DisplayName = EggsConfig.All[rewardEggId].DisplayName,
			Rarity = EggsConfig.All[rewardEggId].Rarity,
			SellPrice = EggsConfig.All[rewardEggId].SellPrice,
			AutoSold = false,
			AutoSoldCoins = 0,
		})
	end

	return {
		Success = true,
		Day = streakDay,
		RewardCoins = rewardCoins,
		RewardEggId = rewardEggId,
	}
end

function QuestService.ClaimStreak(player: Player): ClaimStreakResult
	local profile = PlayerState.Get(player)
	if not profile then
		return { Success = false, ErrorReason = "ProfileNotLoaded" }
	end

	local result: ClaimStreakResult = { Success = false }
	PlayerState.Mutate(player, function(mutableProfile: Types.PlayerProfile)
		result = QuestService.ClaimStreakForProfile(mutableProfile)
	end)

	if result.Success then
		ShovelInventoryService.SendStateSync(player)
		DataService.SavePlayer(player)
		print(string.format("[QuestService] %s claimed Day %d Login Streak (+%d Coins, Egg: %s)", player.Name, result.Day or 0, result.RewardCoins or 0, tostring(result.RewardEggId)))
	end

	return result
end

function QuestService.Start()
	if started then
		return
	end
	started = true

	Remotes.OnServerInvoke("ClaimQuest", function(player: Player, questId: string): ClaimQuestResult
		if type(questId) ~= "string" then
			return { Success = false, ErrorReason = "InvalidArguments" }
		end
		return QuestService.ClaimQuest(player, questId)
	end)

	Remotes.OnServerInvoke("ClaimStreak", function(player: Player): ClaimStreakResult
		return QuestService.ClaimStreak(player)
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		local profile = PlayerState.Get(player)
		if profile then
			QuestService.EnsureProfileQuests(profile, player.UserId)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		activePerfectStreakByUserId[player.UserId] = nil
	end)
end

return QuestService
