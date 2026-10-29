--!strict
-- Authoritative Leaderboard Service: OrderedDataStores for Weekly Coins, All-Time Coins, and Strongest Pet (Step 13)

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local PetsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Pets"))

local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local LeaderboardService = {}

local PUBLISH_INTERVAL_SECONDS = 60 -- Keep shared stats current between display refreshes.
local REFRESH_INTERVAL_SECONDS = 15 * 60
local TOP_LIMIT = 10

local timeOverride: number? = nil
local started = false

-- In-memory fallback stores (used in Studio or when DataStore API access is disabled / 403)
local fallbackStores: { [string]: { [string]: number } } = {
	Leaderboard_Coins_Current = {},
	Leaderboard_Play_Time = {},
	Leaderboard_Coins_AllTime = {},
	Leaderboard_Strongest_Pet = {},
}

-- Username cache to avoid excessive UserService calls
local usernameCache: { [number]: string } = {}

-- Cached top 10 rankings per category
local cachedLeaderboards: {
	[Types.LeaderboardCategory]: {
		Entries: { Types.LeaderboardEntry },
		LastUpdated: number,
	},
} = {
	CurrentCoins = { Entries = {}, LastUpdated = 0 },
	PlayTime = { Entries = {}, LastUpdated = 0 },
	WeeklyCoins = { Entries = {}, LastUpdated = 0 },
	AllTimeCoins = { Entries = {}, LastUpdated = 0 },
	StrongestPet = { Entries = {}, LastUpdated = 0 },
}

-- Hub physical boards references
local hubBoardsFolder: Folder? = nil
local boardSurfaceGuis: { [Types.LeaderboardCategory]: SurfaceGui } = {}

function LeaderboardService.SetTimeOverride(timestamp: number?)
	timeOverride = timestamp
end

function LeaderboardService.GetCurrentTime(): number
	return timeOverride or os.time()
end

function LeaderboardService.GetNextRefreshTime(timestamp: number?): number
	local now = timestamp or os.time()
	return (math.floor(now / REFRESH_INTERVAL_SECONDS) + 1) * REFRESH_INTERVAL_SECONDS
end

-- Monday 00:00:00 UTC rollover calculation
-- 1970-01-01 was Thursday (Day 0). Day 4 was Monday 1970-01-05.
-- weekIndex = math.floor((dayIndex + 3) / 7)
function LeaderboardService.GetCurrentWeekId(): number
	local t = LeaderboardService.GetCurrentTime()
	local dayIndex = math.floor(t / 86400)
	return math.floor((dayIndex + 3) / 7)
end

function LeaderboardService.GetSecondsUntilWeeklyReset(): number
	local t = LeaderboardService.GetCurrentTime()
	local dayIndex = math.floor(t / 86400)
	local dayOfWeek = (dayIndex + 3) % 7 -- 0 = Monday, 6 = Sunday
	local daysUntilMonday = if dayOfWeek == 0 then 7 else (7 - dayOfWeek)
	local nextMondayDay = dayIndex + daysUntilMonday
	local nextMondayMidnight = nextMondayDay * 86400
	return math.max(0, nextMondayMidnight - t)
end

-- Power Score = Power x (1 + Dig Speed / 10) x pengali varian (PRD Line 337)
function LeaderboardService.CalculatePetPowerScore(
	speciesId: string,
	variant: Types.PetVariantName?
): number
	local speciesCfg = PetsConfig.Species[speciesId]
	if not speciesCfg then
		return 0
	end
	local vName = variant or "Normal"
	local variantCfg = (PetsConfig.Variants :: any)[vName] or PetsConfig.Variants.Normal
	local divisor = PetsConfig.PowerScoreDigSpeedDivisor or 10
	local score = speciesCfg.Power * (1 + (speciesCfg.DigSpeed / divisor)) * variantCfg.PowerScoreMultiplier
	return math.floor(score)
end

function LeaderboardService.GetPlayerStrongestPetScore(
	profile: Types.PlayerProfile?
): (number, string?, string?)
	if not profile or not profile.Pets then
		return 0, nil, nil
	end
	local maxScore = 0
	local bestSpecies: string? = nil
	local bestVariant: string? = nil
	for _, pet in pairs(profile.Pets) do
		local score = LeaderboardService.CalculatePetPowerScore(pet.Species, pet.Variant)
		if score > maxScore then
			maxScore = score
			bestSpecies = pet.Species
			bestVariant = pet.Variant
		end
	end
	return maxScore, bestSpecies, bestVariant
end

function LeaderboardService.GetWeeklyCoins(profile: Types.PlayerProfile?): number
	if not profile then
		return 0
	end
	local weekId = LeaderboardService.GetCurrentWeekId()
	local wData = profile.WeeklyCoins
	if wData and wData.Week == weekId then
		return wData.Coins or 0
	end
	return 0
end

function LeaderboardService.RecordCoinsEarned(
	profile: Types.PlayerProfile,
	amount: number
)
	if amount <= 0 then
		return
	end
	local weekId = LeaderboardService.GetCurrentWeekId()
	if not profile.WeeklyCoins or profile.WeeklyCoins.Week ~= weekId then
		profile.WeeklyCoins = {
			Week = weekId,
			Coins = amount,
		}
	else
		profile.WeeklyCoins.Coins = (profile.WeeklyCoins.Coins or 0) + amount
	end
end

local function getWeeklyStoreName(weekId: number?): string
	local wid = weekId or LeaderboardService.GetCurrentWeekId()
	return "Leaderboard_Coins_Weekly_" .. tostring(wid)
end

local function canPerformUpdateAsync(): boolean
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementSortedAsync)
	end)
	return ok and budget > 0
end

local function canPerformGetSortedAsync(): boolean
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetSortedAsync)
	end)
	return ok and budget > 0
end

-- Studio preview never publishes test scores to production OrderedDataStores.
local usingMemoryFallback = RunService:IsStudio()
local globalResults: { [string]: { { Key: string, Value: number } } } = {}
local readTimes: { [string]: number } = {}
local readModes: { [string]: string } = {}
local pendingScores: { [string]: { [string]: number } } = {}
local trackedProfiles: { [number]: Types.PlayerProfile } = {}
local lastWarnings: { [string]: number } = {}
local flushing = false

local function reportStoreFailure(name: string, err: any)
 if os.clock() - (lastWarnings[name] or -60) >= 60 then
  lastWarnings[name] = os.clock()
  warn(string.format("[LeaderboardService] Global ranking unavailable for %s: %s", name, tostring(err)))
 end
end

local function flushPendingScores()
 if flushing or usingMemoryFallback then return end
 flushing = true
 for storeName, scores in pairs(pendingScores) do
  for key, value in pairs(scores) do
   if not canPerformUpdateAsync() then flushing = false return end
   local ok, err = pcall(function()
    local store = DataStoreService:GetOrderedDataStore(storeName)
    if storeName == "Leaderboard_Play_Time" then
     store:UpdateAsync(key, function(previous: number?) return math.max(previous or 0, value) end)
    else
     store:SetAsync(key, value)
    end
   end)
   if ok then
    if scores[key] == value then scores[key] = nil end
   else
    reportStoreFailure(storeName, err)
   end
  end
 end
 flushing = false
end

local function saveToOrderedStore(storeName: string, key: string, value: number): boolean
 local val = math.max(0, math.floor(value))
 if usingMemoryFallback then
  fallbackStores[storeName] = fallbackStores[storeName] or {}
  fallbackStores[storeName][key] = val
  return true
 end
 pendingScores[storeName] = pendingScores[storeName] or {}
 pendingScores[storeName][key] = val
 task.defer(flushPendingScores)
 return true
end

local function getTopFromOrderedStore(storeName: string, limit: number): { { Key: string, Value: number } }
 if usingMemoryFallback then
  local result = {}
  for key, value in pairs(fallbackStores[storeName] or {}) do table.insert(result, { Key = key, Value = value }) end
  table.sort(result, function(a, b) return if a.Value == b.Value then a.Key < b.Key else a.Value > b.Value end)
  while #result > limit do table.remove(result) end
  readModes[storeName], readTimes[storeName] = "StudioPreview", os.time()
  return result
 end
 if canPerformGetSortedAsync() then
  local ok, page = pcall(function()
   local store = DataStoreService:GetOrderedDataStore(storeName)
   return store:GetSortedAsync(false, limit):GetCurrentPage()
  end)
  if ok then
   local result = {}
   for _, entry in ipairs(page) do
    if tonumber(entry.key) and tonumber(entry.key) > 0 then table.insert(result, { Key = entry.key, Value = entry.value }) end
   end
   globalResults[storeName], readTimes[storeName], readModes[storeName] = result, os.time(), "Global"
   return result
  end
  reportStoreFailure(storeName, page)
 end
 -- Never replace a global ranking with only the current server's players.
 readModes[storeName] = if globalResults[storeName] then "CachedGlobal" else "Unavailable"
 return globalResults[storeName] or {}
end

function LeaderboardService.ResolvePlayerName(userId: number): string
	if usernameCache[userId] then
		return usernameCache[userId]
	end

	local online = Players:GetPlayerByUserId(userId)
	if online then
		local name = online.Name
		usernameCache[userId] = name
		return name
	end

	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and name and name ~= "" then
		usernameCache[userId] = name
		return name
	end

	return string.format("Player_%d", userId)
end

local function formatPlayTime(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s >= 3600 then
		local h = math.floor(s / 3600)
		local m = math.floor((s % 3600) / 60)
		return string.format("%dh %dm", h, m)
	else
		local m = math.floor(s / 60)
		local sec = s % 60
		return string.format("%dm %ds", m, sec)
	end
end

local function formatCoins(val: number): string
	if val >= 1_000_000_000 then
		return string.format("%.1fB", val / 1_000_000_000):gsub("%.0B", "B")
	elseif val >= 1_000_000 then
		return string.format("%.1fM", val / 1_000_000):gsub("%.0M", "M")
	elseif val >= 1_000 then
		return string.format("%.1fK", val / 1_000):gsub("%.0K", "K")
	else
		return tostring(math.floor(val))
	end
end

function LeaderboardService.UpdateProfileStats(
	userId: number,
	username: string?,
	profile: Types.PlayerProfile
): boolean
 -- Only profiles loaded for real connected players may enter the global index.
 if trackedProfiles[userId] ~= profile then
  local player = Players:GetPlayerByUserId(userId)
  if not player or PlayerState.Get(player) ~= profile then return false end
  trackedProfiles[userId] = profile
 end
	if username then
		usernameCache[userId] = username
	end

	local currentCoins = profile.Coins or 0
	local allTimeCoins = profile.TotalCoinsEarned or 0
	local weeklyCoins = LeaderboardService.GetWeeklyCoins(profile)
	local strongestPetScore = LeaderboardService.GetPlayerStrongestPetScore(profile)
	local playTime = profile.TotalPlayTime or 0
	if userId and userId > 0 then
		local livePlayTime = DataService.GetTotalPlayTime(userId)
		if livePlayTime > playTime then
			playTime = livePlayTime
		end
	end

	local uidKey = tostring(userId)
	saveToOrderedStore("Leaderboard_Coins_Current", uidKey, currentCoins)
	saveToOrderedStore("Leaderboard_Play_Time", uidKey, playTime)
	saveToOrderedStore("Leaderboard_Coins_AllTime", uidKey, allTimeCoins)
	saveToOrderedStore(getWeeklyStoreName(), uidKey, weeklyCoins)
	saveToOrderedStore("Leaderboard_Strongest_Pet", uidKey, strongestPetScore)

	return true
end

function LeaderboardService.UpdatePlayerStats(player: Player): boolean
	local profile = trackedProfiles[player.UserId] or PlayerState.Get(player)
	if not profile then
		return false
	end
	return LeaderboardService.UpdateProfileStats(player.UserId, player.Name, profile)
end

function LeaderboardService.RefreshLeaderboards(): { [Types.LeaderboardCategory]: { Types.LeaderboardEntry } }
	local now = LeaderboardService.GetCurrentTime()

	-- 1. Current Coins
	local rawCurrentCoins = getTopFromOrderedStore("Leaderboard_Coins_Current", TOP_LIMIT)
	local currentCoinsEntries: { Types.LeaderboardEntry } = {}
	for rank, item in ipairs(rawCurrentCoins) do
		local uid = tonumber(item.Key) or 0
		local pName = LeaderboardService.ResolvePlayerName(uid)
		table.insert(currentCoinsEntries, {
			Rank = rank,
			UserId = uid,
			PlayerName = pName,
			Score = item.Value,
			FormattedScore = Format.Money(item.Value, true),
			ExtraInfo = "Total Uang Saat Ini",
		})
	end
	cachedLeaderboards.CurrentCoins = {
		Entries = currentCoinsEntries,
		LastUpdated = readTimes["Leaderboard_Coins_Current"] or 0,
	}

	-- 2. Play Time
	local rawPlayTime = getTopFromOrderedStore("Leaderboard_Play_Time", TOP_LIMIT)
	local playTimeEntries: { Types.LeaderboardEntry } = {}
	for rank, item in ipairs(rawPlayTime) do
		local uid = tonumber(item.Key) or 0
		local pName = LeaderboardService.ResolvePlayerName(uid)
		table.insert(playTimeEntries, {
			Rank = rank,
			UserId = uid,
			PlayerName = pName,
			Score = item.Value,
			FormattedScore = formatPlayTime(item.Value),
			ExtraInfo = "Total Waktu Bermain",
		})
	end
	cachedLeaderboards.PlayTime = {
		Entries = playTimeEntries,
		LastUpdated = readTimes["Leaderboard_Play_Time"] or 0,
	}

	-- 3. Weekly Coins
	local weeklyName = getWeeklyStoreName()
	local rawWeekly = getTopFromOrderedStore(weeklyName, TOP_LIMIT)
	local weeklyEntries: { Types.LeaderboardEntry } = {}
	for rank, item in ipairs(rawWeekly) do
		local uid = tonumber(item.Key) or 0
		local pName = LeaderboardService.ResolvePlayerName(uid)
		table.insert(weeklyEntries, {
			Rank = rank,
			UserId = uid,
			PlayerName = pName,
			Score = item.Value,
			FormattedScore = Format.Money(item.Value, true),
			ExtraInfo = "Mingguan",
		})
	end
	cachedLeaderboards.WeeklyCoins = {
		Entries = weeklyEntries,
		LastUpdated = readTimes[getWeeklyStoreName()] or 0,
	}

	-- 4. All-Time Coins
	local rawAllTime = getTopFromOrderedStore("Leaderboard_Coins_AllTime", TOP_LIMIT)
	local allTimeEntries: { Types.LeaderboardEntry } = {}
	for rank, item in ipairs(rawAllTime) do
		local uid = tonumber(item.Key) or 0
		local pName = LeaderboardService.ResolvePlayerName(uid)
		table.insert(allTimeEntries, {
			Rank = rank,
			UserId = uid,
			PlayerName = pName,
			Score = item.Value,
			FormattedScore = Format.Money(item.Value, true),
			ExtraInfo = "Sepanjang Masa",
		})
	end
	cachedLeaderboards.AllTimeCoins = {
		Entries = allTimeEntries,
		LastUpdated = readTimes["Leaderboard_Coins_AllTime"] or 0,
	}

	-- 5. Strongest Pet
	local rawPets = getTopFromOrderedStore("Leaderboard_Strongest_Pet", TOP_LIMIT)
	local petEntries: { Types.LeaderboardEntry } = {}
	for rank, item in ipairs(rawPets) do
		local uid = tonumber(item.Key) or 0
		local pName = LeaderboardService.ResolvePlayerName(uid)
		table.insert(petEntries, {
			Rank = rank,
			UserId = uid,
			PlayerName = pName,
			Score = item.Value,
			FormattedScore = Format.Commas(item.Value) .. " Power",
			ExtraInfo = "Power Score",
		})
	end
	cachedLeaderboards.StrongestPet = {
		Entries = petEntries,
		LastUpdated = readTimes["Leaderboard_Strongest_Pet"] or 0,
	}

	LeaderboardService.UpdateHubBoardVisuals()

	Remotes.GetEvent("LeaderboardUpdated"):FireAllClients({
		CurrentCoins = currentCoinsEntries,
		PlayTime = playTimeEntries,
		WeeklyCoins = weeklyEntries,
		AllTimeCoins = allTimeEntries,
		StrongestPet = petEntries,
		LastUpdated = LeaderboardService.GetCachedLeaderboards().LastUpdated,
	})

	return {
		CurrentCoins = currentCoinsEntries,
		PlayTime = playTimeEntries,
		WeeklyCoins = weeklyEntries,
		AllTimeCoins = allTimeEntries,
		StrongestPet = petEntries,
	}
end

function LeaderboardService.GetCachedLeaderboards(): any
	return {
		CurrentCoins = cachedLeaderboards.CurrentCoins.Entries,
		PlayTime = cachedLeaderboards.PlayTime.Entries,
		WeeklyCoins = cachedLeaderboards.WeeklyCoins.Entries,
		AllTimeCoins = cachedLeaderboards.AllTimeCoins.Entries,
		StrongestPet = cachedLeaderboards.StrongestPet.Entries,
		LastUpdated = math.max(
			cachedLeaderboards.CurrentCoins.LastUpdated,
			cachedLeaderboards.PlayTime.LastUpdated,
			cachedLeaderboards.WeeklyCoins.LastUpdated,
			cachedLeaderboards.AllTimeCoins.LastUpdated,
			cachedLeaderboards.StrongestPet.LastUpdated
		),
	}
end

-- =====================================================================
-- Physical Hub Leaderboard 3D Visuals & SurfaceGuis
-- =====================================================================

local WoodBoard = require(script.Parent:WaitForChild("WoodLeaderboardBoard"))
local function buildSingleBoardModel(parent: Instance, name: string, cframe: CFrame, boardTitle: string, _iconEmoji: string, _accentColor: Color3, category: Types.LeaderboardCategory): SurfaceGui
 local surface = WoodBoard.Build(parent, name, cframe, boardTitle, category, TOP_LIMIT)
 boardSurfaceGuis[category] = surface
 return surface
end

function LeaderboardService.EnsureHubBoards()
	table.clear(boardSurfaceGuis)
	local plain = workspace:FindFirstChild("Plain")
	if not plain then
		return
	end
	local hub = plain:FindFirstChild("Hub")
	if not hub then
		return
	end

	local existing = hub:FindFirstChild("LeaderboardBoards")
	if existing and existing:IsA("Folder") then
		existing:Destroy()
	end

	local container = Instance.new("Folder")
	container.Name = "LeaderboardBoards"
	container.Parent = hub
	hubBoardsFolder = container

	-- Board 1: Current Coins (Left Green Line)
	-- Placed along the cobblestone curb at X = -23.5, Z = 13.5, facing +X (towards Hub center)
	local cfLeft = CFrame.lookAt(Vector3.new(-23.5, 0.7, 13.5), Vector3.new(-23.5 + 1, 0.7, 13.5))
	buildSingleBoardModel(
		container,
		"Board_CurrentCoins",
		cfLeft,
		"TOTAL UANG",
		"💵",
		Color3.fromRGB(80, 225, 120),
		"CurrentCoins"
	)

	-- Board 2: Play Time (Right Green Line)
	-- Placed along the cobblestone curb at X = -23.5, Z = -13.5, facing +X (towards Hub center)
	local cfRight = CFrame.lookAt(Vector3.new(-23.5, 0.7, -13.5), Vector3.new(-23.5 + 1, 0.7, -13.5))
	buildSingleBoardModel(
		container,
		"Board_PlayTime",
		cfRight,
		"PLAY TIME",
		"⏱️",
		Color3.fromRGB(0, 195, 255),
		"PlayTime"
	)

	LeaderboardService.UpdateHubBoardVisuals()
end

function LeaderboardService.UpdateHubBoardVisuals()
	for category, sGui in pairs(boardSurfaceGuis) do
		local cached = cachedLeaderboards[category]
		if cached and sGui then
			local bgFrame = sGui:FindFirstChild("BackgroundFrame")
			local rowsContainer = bgFrame and bgFrame:FindFirstChild("RowsContainer")
			if rowsContainer then
				for rank = 1, TOP_LIMIT do
					local row = rowsContainer:FindFirstChild("Row_" .. tostring(rank))
					if row then
						local nameLbl = row:FindFirstChild("PlayerName") :: TextLabel?
						local scoreLbl = row:FindFirstChild("ScoreLabel") :: TextLabel?
						local avatarImg = row:FindFirstChild("AvatarImage") :: ImageLabel?

						local entry = cached.Entries[rank]
						if entry then
							if nameLbl then
								nameLbl.Text = "@" .. entry.PlayerName
							end
							if scoreLbl then
								scoreLbl.Text = entry.FormattedScore
							end
							if avatarImg then
								avatarImg.Visible = true
								if entry.UserId and entry.UserId > 0 then
									avatarImg.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", entry.UserId)
								else
									avatarImg.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
								end
							end
						else
							if nameLbl then
								nameLbl.Text = "---"
							end
							if scoreLbl then
								scoreLbl.Text = "---"
							end
							if avatarImg then
								avatarImg.Visible = false
								avatarImg.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
							end
						end
					end
				end
			end
		end
	end
end

-- =====================================================================
-- Lifecycle & Schedulers
-- =====================================================================

function LeaderboardService.Start()
	if started then
		return
	end
	started = true

	LeaderboardService.EnsureHubBoards()

	-- RemoteFunction to fetch top rankings
	Remotes.OnServerInvoke("GetLeaderboards", function(_player: Player)
		return LeaderboardService.GetCachedLeaderboards()
	end)

	-- Cache username on PlayerAdded
	Players.PlayerAdded:Connect(function(player: Player)
		usernameCache[player.UserId] = player.Name
	end)

	-- Save player stats on leave (budget safe)
	Players.PlayerRemoving:Connect(function(player: Player)
		LeaderboardService.UpdatePlayerStats(player)
  trackedProfiles[player.UserId] = nil
	end)

 DataService.OnProfileLoaded(function(player: Player, profile: Types.PlayerProfile)
  trackedProfiles[player.UserId] = profile
  LeaderboardService.UpdatePlayerStats(player)
 end)
 task.spawn(function()
  while true do task.wait(5) flushPendingScores() end
 end)
 game:BindToClose(function()
  for _, player in Players:GetPlayers() do LeaderboardService.UpdatePlayerStats(player) end
  task.spawn(flushPendingScores)
  local deadline = os.clock() + 25
  while os.clock() < deadline do
   local pending = false
   for _, values in pairs(pendingScores) do if next(values) then pending = true break end end
   if not pending then break end
   if not flushing then task.spawn(flushPendingScores) end
   task.wait(.2)
  end
 end)

	-- Initial refresh
	task.spawn(function()
		task.wait(2.0)
		for _, player in ipairs(Players:GetPlayers()) do
			LeaderboardService.UpdatePlayerStats(player)
		end
		LeaderboardService.RefreshLeaderboards()
	end)

	-- Publishing does not redraw the boards or broadcast a ranking refresh.
	task.spawn(function()
		while true do
			task.wait(PUBLISH_INTERVAL_SECONDS)
			for _, player in ipairs(Players:GetPlayers()) do
				LeaderboardService.UpdatePlayerStats(player)
			end
		end
	end)

	-- Every server redraws at real-world quarter hours: :00, :15, :30, :45.
	task.spawn(function()
		local nextRefreshAt = LeaderboardService.GetNextRefreshTime()
		while true do
			task.wait(math.clamp(nextRefreshAt - os.time(), 0.1, 30))
			if os.time() >= nextRefreshAt then
				LeaderboardService.RefreshLeaderboards()
				nextRefreshAt = LeaderboardService.GetNextRefreshTime()
			end
		end
	end)
end

return LeaderboardService
