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

local UPDATE_INTERVAL_SECONDS = 300 -- 5 minutes per PRD
local REFRESH_INTERVAL_SECONDS = 300 -- 5 minutes per PRD
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

local usingMemoryFallback = false

local function saveToOrderedStore(storeName: string, key: string, value: number): boolean
	local val = math.max(0, math.floor(value))

	if not fallbackStores[storeName] then
		fallbackStores[storeName] = {}
	end
	fallbackStores[storeName][key] = val

	if usingMemoryFallback or not canPerformUpdateAsync() then
		return true
	end

	local ok, err = pcall(function()
		local ods = DataStoreService:GetOrderedDataStore(storeName)
		ods:SetAsync(key, val)
	end)

	if not ok then
		if RunService:IsStudio() then
			usingMemoryFallback = true
			print("[LeaderboardService] DataStore API disabled in Studio. Switched to in-memory fallback.")
		else
			warn(string.format("[LeaderboardService] Failed to set %s for key %s: %s", storeName, key, tostring(err)))
			return false
		end
	end
	return true
end

local function getTopFromOrderedStore(storeName: string, limit: number): { { Key: string, Value: number } }
	local results: { { Key: string, Value: number } } = {}

	local didDataStoreSucceed = false
	if not usingMemoryFallback and canPerformGetSortedAsync() then
		local ok, pages = pcall(function()
			local ods = DataStoreService:GetOrderedDataStore(storeName)
			return ods:GetSortedAsync(false, limit)
		end)

		if ok and pages then
			local pageOk, page = pcall(function()
				return pages:GetCurrentPage()
			end)
			if pageOk and page then
				for _, entry in ipairs(page) do
					table.insert(results, {
						Key = entry.key,
						Value = entry.value,
					})
				end
				didDataStoreSucceed = true
			end
		else
			if RunService:IsStudio() then
				usingMemoryFallback = true
			end
		end
	end

	if not didDataStoreSucceed then
		-- Fallback store slice (sorted descending)
		local store = fallbackStores[storeName] or {}
		local list: { { Key: string, Value: number } } = {}
		for k, v in pairs(store) do
			table.insert(list, { Key = k, Value = v })
		end
		table.sort(list, function(a, b)
			return a.Value > b.Value
		end)
		for i = 1, math.min(limit, #list) do
			table.insert(results, list[i])
		end
	end

	return results
end

function LeaderboardService.ResolvePlayerName(userId: number): string
	if usernameCache[userId] then
		return usernameCache[userId]
	end

	local online = Players:GetPlayerByUserId(userId)
	if online then
		local name = online.DisplayName or online.Name
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
	local profile = PlayerState.Get(player)
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
			FormattedScore = formatCoins(item.Value),
			ExtraInfo = "Total Coin Saat Ini",
		})
	end
	cachedLeaderboards.CurrentCoins = {
		Entries = currentCoinsEntries,
		LastUpdated = now,
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
		LastUpdated = now,
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
			FormattedScore = Format.Commas(item.Value) .. " Coin",
			ExtraInfo = "Mingguan",
		})
	end
	cachedLeaderboards.WeeklyCoins = {
		Entries = weeklyEntries,
		LastUpdated = now,
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
			FormattedScore = Format.Commas(item.Value) .. " Coin",
			ExtraInfo = "Sepanjang Masa",
		})
	end
	cachedLeaderboards.AllTimeCoins = {
		Entries = allTimeEntries,
		LastUpdated = now,
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
		LastUpdated = now,
	}

	LeaderboardService.UpdateHubBoardVisuals()

	Remotes.GetEvent("LeaderboardUpdated"):FireAllClients({
		CurrentCoins = currentCoinsEntries,
		PlayTime = playTimeEntries,
		WeeklyCoins = weeklyEntries,
		AllTimeCoins = allTimeEntries,
		StrongestPet = petEntries,
		LastUpdated = now,
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

local function createSegmentedPillar(parent: Instance, cframe: CFrame, height: number, radius: number)
	local numSegments = 8
	local segHeight = height / numSegments
	local ringHeight = 0.12

	for i = 1, numSegments do
		local yOffset = -height / 2 + (i - 0.5) * segHeight
		local seg = Instance.new("Part")
		seg.Name = "PillarSeg_" .. i
		seg.Shape = Enum.PartType.Cylinder
		seg.Size = Vector3.new(segHeight - ringHeight, radius * 2, radius * 2)
		seg.CFrame = cframe * CFrame.new(0, yOffset, 0) * CFrame.Angles(0, 0, math.rad(90))
		seg.Material = Enum.Material.SmoothPlastic
		seg.Color = Color3.fromRGB(36, 54, 88)
		seg.Anchored = true
		seg.CanCollide = true
		seg.Parent = parent

		if i < numSegments then
			local ringY = yOffset + segHeight / 2
			local ring = Instance.new("Part")
			ring.Name = "PillarRing_" .. i
			ring.Shape = Enum.PartType.Cylinder
			ring.Size = Vector3.new(ringHeight, (radius + 0.08) * 2, (radius + 0.08) * 2)
			ring.CFrame = cframe * CFrame.new(0, ringY, 0) * CFrame.Angles(0, 0, math.rad(90))
			ring.Material = Enum.Material.Neon
			ring.Color = Color3.fromRGB(225, 238, 255)
			ring.Anchored = true
			ring.CanCollide = true
			ring.Parent = parent
		end
	end

	local cap = Instance.new("Part")
	cap.Name = "PillarCap"
	cap.Shape = Enum.PartType.Ball
	cap.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	cap.CFrame = cframe * CFrame.new(0, height / 2, 0)
	cap.Material = Enum.Material.SmoothPlastic
	cap.Color = Color3.fromRGB(45, 68, 110)
	cap.Anchored = true
	cap.CanCollide = true
	cap.Parent = parent
end

local function buildSingleBoardModel(
	parent: Instance,
	name: string,
	cframe: CFrame,
	boardTitle: string,
	iconEmoji: string,
	accentColor: Color3,
	category: Types.LeaderboardCategory
): SurfaceGui
	local model = Instance.new("Model")
	model.Name = name

	local boardWidth = 8.6
	local boardHeight = 11.0
	local boardThickness = 0.6
	local pillarRadius = 0.75
	local pillarOffset = boardWidth / 2 + pillarRadius + 0.1

	-- Pedestal Base
	local base1 = Instance.new("Part")
	base1.Name = "BaseLower"
	base1.Size = Vector3.new(boardWidth + 3.2, 0.4, 2.8)
	base1.CFrame = cframe * CFrame.new(0, 0.2, 0)
	base1.Material = Enum.Material.SmoothPlastic
	base1.Color = Color3.fromRGB(28, 38, 54)
	base1.Anchored = true
	base1.CanCollide = true
	base1.Parent = model

	local base2 = Instance.new("Part")
	base2.Name = "BaseUpper"
	base2.Size = Vector3.new(boardWidth + 2.6, 0.3, 2.4)
	base2.CFrame = cframe * CFrame.new(0, 0.55, 0)
	base2.Material = Enum.Material.SmoothPlastic
	base2.Color = Color3.fromRGB(38, 52, 74)
	base2.Anchored = true
	base2.CanCollide = true
	base2.Parent = model

	-- Main Backing Board
	local boardCenterY = 0.7 + boardHeight / 2
	local boardPart = Instance.new("Part")
	boardPart.Name = "BoardStand"
	boardPart.Size = Vector3.new(boardWidth, boardHeight, boardThickness)
	boardPart.CFrame = cframe * CFrame.new(0, boardCenterY, 0)
	boardPart.Material = Enum.Material.SmoothPlastic
	boardPart.Color = Color3.fromRGB(14, 20, 32)
	boardPart.Anchored = true
	boardPart.CanCollide = true
	boardPart.Parent = model

	-- Pillars on Left (-X local) and Right (+X local)
	createSegmentedPillar(model, cframe * CFrame.new(-pillarOffset, boardCenterY, 0), boardHeight, pillarRadius)
	createSegmentedPillar(model, cframe * CFrame.new(pillarOffset, boardCenterY, 0), boardHeight, pillarRadius)

	-- Header Ribbon Banner
	local bannerCenterY = boardCenterY + boardHeight / 2 + 1.2

	-- Glowing White Ribbon Backdrop
	local bannerBack = Instance.new("Part")
	bannerBack.Name = "BannerBackAura"
	bannerBack.Size = Vector3.new(boardWidth + 2.0, 2.0, 0.3)
	bannerBack.CFrame = cframe * CFrame.new(0, bannerCenterY, 0)
	bannerBack.Material = Enum.Material.Neon
	bannerBack.Color = Color3.fromRGB(240, 248, 255)
	bannerBack.Anchored = true
	bannerBack.CanCollide = false
	bannerBack.Parent = model

	-- Swallowtail ribbon notch wings on Left and Right ends
	local wingWidth = 1.2
	local wingHeight = 2.0
	local wingThickness = 0.25
	local zOffset = (boardWidth + 2.0) / 2

	local leftWingTop = Instance.new("WedgePart")
	leftWingTop.Name = "RibbonNotch_LT"
	leftWingTop.Size = Vector3.new(wingThickness, wingHeight / 2, wingWidth)
	leftWingTop.CFrame = cframe * CFrame.new(-zOffset - wingWidth / 2, bannerCenterY + wingHeight / 4, 0) * CFrame.Angles(math.rad(180), 0, math.rad(90))
	leftWingTop.Material = Enum.Material.Neon
	leftWingTop.Color = Color3.fromRGB(240, 248, 255)
	leftWingTop.Anchored = true
	leftWingTop.CanCollide = false
	leftWingTop.Parent = model

	local leftWingBottom = Instance.new("WedgePart")
	leftWingBottom.Name = "RibbonNotch_LB"
	leftWingBottom.Size = Vector3.new(wingThickness, wingHeight / 2, wingWidth)
	leftWingBottom.CFrame = cframe * CFrame.new(-zOffset - wingWidth / 2, bannerCenterY - wingHeight / 4, 0) * CFrame.Angles(0, 0, math.rad(90))
	leftWingBottom.Material = Enum.Material.Neon
	leftWingBottom.Color = Color3.fromRGB(240, 248, 255)
	leftWingBottom.Anchored = true
	leftWingBottom.CanCollide = false
	leftWingBottom.Parent = model

	local rightWingTop = Instance.new("WedgePart")
	rightWingTop.Name = "RibbonNotch_RT"
	rightWingTop.Size = Vector3.new(wingThickness, wingHeight / 2, wingWidth)
	rightWingTop.CFrame = cframe * CFrame.new(zOffset + wingWidth / 2, bannerCenterY + wingHeight / 4, 0) * CFrame.Angles(math.rad(180), 0, math.rad(-90))
	rightWingTop.Material = Enum.Material.Neon
	rightWingTop.Color = Color3.fromRGB(240, 248, 255)
	rightWingTop.Anchored = true
	rightWingTop.CanCollide = false
	rightWingTop.Parent = model

	local rightWingBottom = Instance.new("WedgePart")
	rightWingBottom.Name = "RibbonNotch_RB"
	rightWingBottom.Size = Vector3.new(wingThickness, wingHeight / 2, wingWidth)
	rightWingBottom.CFrame = cframe * CFrame.new(zOffset + wingWidth / 2, bannerCenterY - wingHeight / 4, 0) * CFrame.Angles(0, 0, math.rad(-90))
	rightWingBottom.Material = Enum.Material.Neon
	rightWingBottom.Color = Color3.fromRGB(240, 248, 255)
	rightWingBottom.Anchored = true
	rightWingBottom.CanCollide = false
	rightWingBottom.Parent = model

	-- Front Banner Face
	local bannerFront = Instance.new("Part")
	bannerFront.Name = "BannerFront"
	bannerFront.Size = Vector3.new(boardWidth + 0.6, 1.6, 0.4)
	bannerFront.CFrame = cframe * CFrame.new(0, bannerCenterY, -0.2)
	bannerFront.Material = Enum.Material.SmoothPlastic
	bannerFront.Color = Color3.fromRGB(20, 32, 54)
	bannerFront.Anchored = true
	bannerFront.CanCollide = true
	bannerFront.Parent = model

	-- SurfaceGui on Banner
	local bannerGui = Instance.new("SurfaceGui")
	bannerGui.Name = "BannerGui"
	bannerGui.Face = Enum.NormalId.Front
	bannerGui.CanvasSize = Vector2.new(900, 160)
	bannerGui.LightInfluence = 0
	bannerGui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	bannerGui.Parent = bannerFront

	local bannerFrame = Instance.new("Frame")
	bannerFrame.Size = UDim2.fromScale(1, 1)
	bannerFrame.BackgroundColor3 = Color3.fromRGB(18, 28, 48)
	bannerFrame.BorderSizePixel = 0
	bannerFrame.Parent = bannerGui

	local bCorner = Instance.new("UICorner")
	bCorner.CornerRadius = UDim.new(0, 18)
	bCorner.Parent = bannerFrame

	local bStroke = Instance.new("UIStroke")
	bStroke.Color = Color3.fromRGB(80, 160, 240)
	bStroke.Thickness = 3
	bStroke.Parent = bannerFrame

	local bannerTitle = Instance.new("TextLabel")
	bannerTitle.Size = UDim2.fromScale(1, 1)
	bannerTitle.BackgroundTransparency = 1
	bannerTitle.Font = Enum.Font.GothamBlack
	bannerTitle.TextSize = 44
	bannerTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	bannerTitle.Text = string.format("%s  %s  %s", iconEmoji, boardTitle, iconEmoji)
	bannerTitle.Parent = bannerFrame

	-- ProximityPrompt for interaction
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ViewLeaderboardPrompt"
	prompt.ActionText = "Buka Papan Peringkat"
	prompt.ObjectText = boardTitle
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = boardPart

	prompt.Triggered:Connect(function(player: Player)
		Remotes.GetEvent("LeaderboardUpdated"):FireClient(player, LeaderboardService.GetCachedLeaderboards())
	end)

	-- Main SurfaceGui on Board
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "LeaderboardDisplay"
	surfaceGui.Face = Enum.NormalId.Front
	surfaceGui.CanvasSize = Vector2.new(860, 1140)
	surfaceGui.LightInfluence = 0
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surfaceGui.Parent = boardPart

	local bgFrame = Instance.new("Frame")
	bgFrame.Name = "BackgroundFrame"
	bgFrame.Size = UDim2.new(1, -20, 1, -20)
	bgFrame.Position = UDim2.fromOffset(10, 10)
	bgFrame.BackgroundColor3 = Color3.fromRGB(15, 22, 36)
	bgFrame.BackgroundTransparency = 0.1
	bgFrame.BorderSizePixel = 0
	bgFrame.Parent = surfaceGui

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 16)
	bgCorner.Parent = bgFrame

	local bgStroke = Instance.new("UIStroke")
	bgStroke.Color = Color3.fromRGB(60, 110, 180)
	bgStroke.Thickness = 3
	bgStroke.Parent = bgFrame

	local rowsContainer = Instance.new("Frame")
	rowsContainer.Name = "RowsContainer"
	rowsContainer.Size = UDim2.new(1, -24, 1, -32)
	rowsContainer.Position = UDim2.fromOffset(12, 16)
	rowsContainer.BackgroundTransparency = 1
	rowsContainer.Parent = bgFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = rowsContainer

	for rank = 1, TOP_LIMIT do
		local row = Instance.new("Frame")
		row.Name = "Row_" .. rank
		row.Size = UDim2.new(1, 0, 0, 96)
		row.BackgroundColor3 = Color3.fromRGB(22, 34, 54)
		row.BorderSizePixel = 0
		row.LayoutOrder = rank
		row.Parent = rowsContainer

		local rCorner = Instance.new("UICorner")
		rCorner.CornerRadius = UDim.new(0, 10)
		rCorner.Parent = row

		local rStroke = Instance.new("UIStroke")
		rStroke.Color = Color3.fromRGB(50, 85, 140)
		rStroke.Thickness = 1.5
		rStroke.Parent = row

		-- Rank label
		local rankLbl = Instance.new("TextLabel")
		rankLbl.Name = "RankLabel"
		rankLbl.Position = UDim2.fromOffset(14, 0)
		rankLbl.Size = UDim2.fromOffset(56, 96)
		rankLbl.BackgroundTransparency = 1
		rankLbl.Font = Enum.Font.GothamBlack
		rankLbl.TextSize = 28
		rankLbl.Text = "#" .. rank
		rankLbl.TextXAlignment = Enum.TextXAlignment.Left
		if rank <= 3 then
			rankLbl.TextColor3 = Color3.fromRGB(255, 35, 65)
		else
			rankLbl.TextColor3 = Color3.fromRGB(255, 175, 25)
		end
		rankLbl.Parent = row

		-- Avatar Headshot Icon
		local avatarImg = Instance.new("ImageLabel")
		avatarImg.Name = "AvatarImage"
		avatarImg.Position = UDim2.fromOffset(78, 14)
		avatarImg.Size = UDim2.fromOffset(68, 68)
		avatarImg.BackgroundColor3 = Color3.fromRGB(30, 44, 70)
		avatarImg.BorderSizePixel = 0
		avatarImg.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
		avatarImg.Parent = row

		local aCorner = Instance.new("UICorner")
		aCorner.CornerRadius = UDim.new(0, 10)
		aCorner.Parent = avatarImg

		local aStroke = Instance.new("UIStroke")
		aStroke.Color = Color3.fromRGB(70, 110, 165)
		aStroke.Thickness = 1
		aStroke.Parent = avatarImg

		-- Player Handle
		local nameLbl = Instance.new("TextLabel")
		nameLbl.Name = "PlayerName"
		nameLbl.Position = UDim2.fromOffset(160, 0)
		nameLbl.Size = UDim2.new(1, -380, 1, 0)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.TextSize = 26
		nameLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.Text = "---"
		nameLbl.Parent = row

		-- Score Label
		local scoreLbl = Instance.new("TextLabel")
		scoreLbl.Name = "ScoreLabel"
		scoreLbl.Position = UDim2.new(1, -210, 0, 0)
		scoreLbl.Size = UDim2.fromOffset(196, 96)
		scoreLbl.BackgroundTransparency = 1
		scoreLbl.Font = Enum.Font.GothamBlack
		scoreLbl.TextSize = 26
		scoreLbl.TextColor3 = Color3.fromRGB(0, 195, 255)
		scoreLbl.TextXAlignment = Enum.TextXAlignment.Right
		scoreLbl.Text = "---"
		scoreLbl.Parent = row
	end

	model.Parent = parent
	boardSurfaceGuis[category] = surfaceGui
	return surfaceGui
end

function LeaderboardService.EnsureHubBoards()
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
		"TOTAL COINS",
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
		usernameCache[player.UserId] = player.DisplayName or player.Name
	end)

	-- Save player stats on leave (budget safe)
	Players.PlayerRemoving:Connect(function(player: Player)
		LeaderboardService.UpdatePlayerStats(player)
	end)

	-- Initial refresh
	task.spawn(function()
		task.wait(2.0)
		for _, player in ipairs(Players:GetPlayers()) do
			LeaderboardService.UpdatePlayerStats(player)
		end
		LeaderboardService.RefreshLeaderboards()
	end)

	-- Background updater: every 5 minutes (300s) per PRD
	task.spawn(function()
		while true do
			task.wait(UPDATE_INTERVAL_SECONDS)
			for _, player in ipairs(Players:GetPlayers()) do
				LeaderboardService.UpdatePlayerStats(player)
			end
			LeaderboardService.RefreshLeaderboards()
		end
	end)
end

return LeaderboardService
