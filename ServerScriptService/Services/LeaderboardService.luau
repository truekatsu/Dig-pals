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

local LeaderboardService = {}

local UPDATE_INTERVAL_SECONDS = 300 -- 5 minutes per PRD
local REFRESH_INTERVAL_SECONDS = 300 -- 5 minutes per PRD
local TOP_LIMIT = 10

local timeOverride: number? = nil
local started = false

-- In-memory fallback stores (used in Studio or when DataStore API access is disabled / 403)
local fallbackStores: { [string]: { [string]: number } } = {
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

function LeaderboardService.UpdateProfileStats(
	userId: number,
	username: string?,
	profile: Types.PlayerProfile
): boolean
	if username then
		usernameCache[userId] = username
	end

	local allTimeCoins = profile.TotalCoinsEarned or 0
	local weeklyCoins = LeaderboardService.GetWeeklyCoins(profile)
	local strongestPetScore = LeaderboardService.GetPlayerStrongestPetScore(profile)

	local uidKey = tostring(userId)
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

	-- 1. Weekly Coins
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

	-- 2. All-Time Coins
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

	-- 3. Strongest Pet
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
		WeeklyCoins = weeklyEntries,
		AllTimeCoins = allTimeEntries,
		StrongestPet = petEntries,
		LastUpdated = now,
	})

	return {
		WeeklyCoins = weeklyEntries,
		AllTimeCoins = allTimeEntries,
		StrongestPet = petEntries,
	}
end

function LeaderboardService.GetCachedLeaderboards(): any
	return {
		WeeklyCoins = cachedLeaderboards.WeeklyCoins.Entries,
		AllTimeCoins = cachedLeaderboards.AllTimeCoins.Entries,
		StrongestPet = cachedLeaderboards.StrongestPet.Entries,
		LastUpdated = math.max(
			cachedLeaderboards.WeeklyCoins.LastUpdated,
			cachedLeaderboards.AllTimeCoins.LastUpdated,
			cachedLeaderboards.StrongestPet.LastUpdated
		),
	}
end

-- =====================================================================
-- Physical Hub Leaderboard 3D Visuals & SurfaceGuis
-- =====================================================================

local function buildSingleBoardModel(
	parent: Instance,
	name: string,
	cframe: CFrame,
	title: string,
	subtitle: string,
	accentColor: Color3,
	category: Types.LeaderboardCategory
): SurfaceGui
	local boardModel = Instance.new("Model")
	boardModel.Name = name

	-- Main backing board part
	local boardPart = Instance.new("Part")
	boardPart.Name = "BoardStand"
	boardPart.Size = Vector3.new(1.2, 9.5, 7.8)
	boardPart.CFrame = cframe
	boardPart.Anchored = true
	boardPart.CanCollide = true
	boardPart.Material = Enum.Material.Slate
	boardPart.Color = Color3.fromRGB(24, 28, 38)
	boardPart.Parent = boardModel

	-- Border frame
	local border = Instance.new("SelectionBox")
	border.Adornee = boardPart
	border.Color3 = accentColor
	border.LineThickness = 0.05
	border.Parent = boardPart

	-- ProximityPrompt for interaction
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ViewLeaderboardPrompt"
	prompt.ActionText = "Buka Papan Peringkat"
	prompt.ObjectText = title
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = boardPart

	prompt.Triggered:Connect(function(player: Player)
		Remotes.GetEvent("LeaderboardUpdated"):FireClient(player, LeaderboardService.GetCachedLeaderboards())
	end)

	-- SurfaceGui on the front face (Left face relative to orientation)
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "LeaderboardDisplay"
	surfaceGui.Face = Enum.NormalId.Left
	surfaceGui.CanvasSize = Vector2.new(780, 950)
	surfaceGui.PixelsPerStud = 50
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surfaceGui.LightInfluence = 0.2
	surfaceGui.Parent = boardPart

	-- Header Frame
	local headerFrame = Instance.new("Frame")
	headerFrame.Name = "Header"
	headerFrame.Size = UDim2.new(1, 0, 0, 110)
	headerFrame.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
	headerFrame.BorderSizePixel = 0
	headerFrame.Parent = surfaceGui

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 10)
	headerCorner.Parent = headerFrame

	local accentBar = Instance.new("Frame")
	accentBar.Name = "AccentBar"
	accentBar.Position = UDim2.new(0, 0, 1, -4)
	accentBar.Size = UDim2.new(1, 0, 0, 4)
	accentBar.BackgroundColor3 = accentColor
	accentBar.BorderSizePixel = 0
	accentBar.Parent = headerFrame

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Position = UDim2.fromOffset(16, 12)
	titleLabel.Size = UDim2.new(1, -32, 0, 36)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextSize = 26
	titleLabel.TextColor3 = accentColor
	titleLabel.Text = title
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.Parent = headerFrame

	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "Subtitle"
	subLabel.Position = UDim2.fromOffset(16, 52)
	subLabel.Size = UDim2.new(1, -32, 0, 22)
	subLabel.BackgroundTransparency = 1
	subLabel.Font = Enum.Font.GothamBold
	subLabel.TextSize = 15
	subLabel.TextColor3 = Color3.fromRGB(190, 200, 220)
	subLabel.Text = subtitle
	subLabel.TextXAlignment = Enum.TextXAlignment.Center
	subLabel.Parent = headerFrame

	local refreshNotice = Instance.new("TextLabel")
	refreshNotice.Name = "RefreshNotice"
	refreshNotice.Position = UDim2.fromOffset(16, 78)
	refreshNotice.Size = UDim2.new(1, -32, 0, 20)
	refreshNotice.BackgroundTransparency = 1
	refreshNotice.Font = Enum.Font.Gotham
	refreshNotice.TextSize = 13
	refreshNotice.TextColor3 = Color3.fromRGB(140, 150, 170)
	refreshNotice.Text = "Refresh otomatis tiap 5 menit"
	refreshNotice.TextXAlignment = Enum.TextXAlignment.Center
	refreshNotice.Parent = headerFrame

	-- Table Columns Header
	local colHeader = Instance.new("Frame")
	colHeader.Name = "ColumnHeader"
	colHeader.Position = UDim2.fromOffset(10, 118)
	colHeader.Size = UDim2.new(1, -20, 0, 32)
	colHeader.BackgroundColor3 = Color3.fromRGB(28, 34, 46)
	colHeader.BorderSizePixel = 0
	colHeader.Parent = surfaceGui

	local colCorner = Instance.new("UICorner")
	colCorner.CornerRadius = UDim.new(0, 6)
	colCorner.Parent = colHeader

	local rCol = Instance.new("TextLabel")
	rCol.Size = UDim2.fromOffset(60, 32)
	rCol.BackgroundTransparency = 1
	rCol.Font = Enum.Font.GothamBlack
	rCol.TextSize = 14
	rCol.TextColor3 = Color3.fromRGB(170, 180, 200)
	rCol.Text = "RANK"
	rCol.Parent = colHeader

	local nameCol = Instance.new("TextLabel")
	nameCol.Position = UDim2.fromOffset(70, 0)
	nameCol.Size = UDim2.new(1, -270, 1, 0)
	nameCol.BackgroundTransparency = 1
	nameCol.Font = Enum.Font.GothamBlack
	nameCol.TextSize = 14
	nameCol.TextColor3 = Color3.fromRGB(170, 180, 200)
	nameCol.Text = "PEMAIN"
	nameCol.TextXAlignment = Enum.TextXAlignment.Left
	nameCol.Parent = colHeader

	local valCol = Instance.new("TextLabel")
	valCol.Position = UDim2.new(1, -190, 0, 0)
	valCol.Size = UDim2.fromOffset(180, 32)
	valCol.BackgroundTransparency = 1
	valCol.Font = Enum.Font.GothamBlack
	valCol.TextSize = 14
	valCol.TextColor3 = Color3.fromRGB(170, 180, 200)
	valCol.Text = "SKOR"
	valCol.TextXAlignment = Enum.TextXAlignment.Right
	valCol.Parent = colHeader

	-- Rows Container
	local rowsContainer = Instance.new("Frame")
	rowsContainer.Name = "RowsContainer"
	rowsContainer.Position = UDim2.fromOffset(10, 156)
	rowsContainer.Size = UDim2.new(1, -20, 0, 780)
	rowsContainer.BackgroundTransparency = 1
	rowsContainer.Parent = surfaceGui

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = rowsContainer

	for rank = 1, TOP_LIMIT do
		local row = Instance.new("Frame")
		row.Name = "Row_" .. tostring(rank)
		row.Size = UDim2.new(1, 0, 0, 68)
		row.BackgroundColor3 = if rank % 2 == 0 then Color3.fromRGB(24, 28, 38) else Color3.fromRGB(20, 24, 32)
		row.BorderSizePixel = 0
		row.LayoutOrder = rank
		row.Parent = rowsContainer

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 8)
		rowCorner.Parent = row

		-- Rank badge
		local badge = Instance.new("Frame")
		badge.Name = "Badge"
		badge.Position = UDim2.fromOffset(8, 14)
		badge.Size = UDim2.fromOffset(42, 40)
		badge.BorderSizePixel = 0
		badge.Parent = row

		local bCorner = Instance.new("UICorner")
		bCorner.CornerRadius = UDim.new(0, 8)
		bCorner.Parent = badge

		local rankLbl = Instance.new("TextLabel")
		rankLbl.Name = "RankLabel"
		rankLbl.Size = UDim2.fromScale(1, 1)
		rankLbl.BackgroundTransparency = 1
		rankLbl.Font = Enum.Font.GothamBlack
		rankLbl.TextSize = 18
		rankLbl.Text = "#" .. tostring(rank)
		rankLbl.Parent = badge

		if rank == 1 then
			badge.BackgroundColor3 = Color3.fromRGB(245, 195, 55)
			rankLbl.TextColor3 = Color3.fromRGB(40, 28, 6)
		elseif rank == 2 then
			badge.BackgroundColor3 = Color3.fromRGB(190, 200, 215)
			rankLbl.TextColor3 = Color3.fromRGB(28, 32, 40)
		elseif rank == 3 then
			badge.BackgroundColor3 = Color3.fromRGB(205, 130, 75)
			rankLbl.TextColor3 = Color3.fromRGB(40, 20, 10)
		else
			badge.BackgroundColor3 = Color3.fromRGB(36, 42, 56)
			rankLbl.TextColor3 = Color3.fromRGB(170, 180, 200)
		end

		-- Player Name
		local pName = Instance.new("TextLabel")
		pName.Name = "PlayerName"
		pName.Position = UDim2.fromOffset(60, 12)
		pName.Size = UDim2.new(1, -260, 0, 44)
		pName.BackgroundTransparency = 1
		pName.Font = Enum.Font.GothamBold
		pName.TextSize = 18
		pName.TextColor3 = Color3.fromRGB(240, 244, 252)
		pName.TextXAlignment = Enum.TextXAlignment.Left
		pName.TextTruncate = Enum.TextTruncate.AtEnd
		pName.Text = "---"
		pName.Parent = row

		-- Score
		local scoreLbl = Instance.new("TextLabel")
		scoreLbl.Name = "ScoreLabel"
		scoreLbl.Position = UDim2.new(1, -190, 0, 12)
		scoreLbl.Size = UDim2.fromOffset(180, 44)
		scoreLbl.BackgroundTransparency = 1
		scoreLbl.Font = Enum.Font.GothamBlack
		scoreLbl.TextSize = 18
		scoreLbl.TextColor3 = accentColor
		scoreLbl.TextXAlignment = Enum.TextXAlignment.Right
		scoreLbl.Text = "---"
		scoreLbl.Parent = row
	end

	boardModel.Parent = parent
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
		hubBoardsFolder = existing
		return
	end

	local container = Instance.new("Folder")
	container.Name = "LeaderboardBoards"
	container.Parent = hub
	hubBoardsFolder = container

	-- Three boards aligned facing inward from East boundary of SpawnPlaza (X = 23.5)
	-- Board 1: Weekly Coins
	buildSingleBoardModel(
		container,
		"Board_WeeklyCoins",
		CFrame.new(23.5, 5.2, -9.5) * CFrame.Angles(0, math.rad(-90), 0),
		"TOTAL COIN MINGGUAN",
		"Reset Otomatis Setiap Senin 00:00 UTC",
		Color3.fromRGB(255, 215, 65),
		"WeeklyCoins"
	)

	-- Board 2: All-Time Coins
	buildSingleBoardModel(
		container,
		"Board_AllTimeCoins",
		CFrame.new(23.5, 5.2, 0) * CFrame.Angles(0, math.rad(-90), 0),
		"TOTAL COIN SEPANJANG MASA",
		"Akumulasi Seluruh Coin yang Pernah Didapat",
		Color3.fromRGB(80, 225, 120),
		"AllTimeCoins"
	)

	-- Board 3: Strongest Pet
	buildSingleBoardModel(
		container,
		"Board_StrongestPet",
		CFrame.new(23.5, 5.2, 9.5) * CFrame.Angles(0, math.rad(-90), 0),
		"PET TERKUAT",
		"Power Score = Power x (1 + DigSpeed/10) x Varian",
		Color3.fromRGB(110, 185, 255),
		"StrongestPet"
	)

	LeaderboardService.UpdateHubBoardVisuals()
end

function LeaderboardService.UpdateHubBoardVisuals()
	for category, sGui in pairs(boardSurfaceGuis) do
		local cached = cachedLeaderboards[category]
		if cached and sGui then
			local rowsContainer = sGui:FindFirstChild("RowsContainer")
			if rowsContainer then
				for rank = 1, TOP_LIMIT do
					local row = rowsContainer:FindFirstChild("Row_" .. tostring(rank))
					if row then
						local nameLbl = row:FindFirstChild("PlayerName") :: TextLabel?
						local scoreLbl = row:FindFirstChild("ScoreLabel") :: TextLabel?

						local entry = cached.Entries[rank]
						if entry then
							if nameLbl then
								nameLbl.Text = entry.PlayerName
							end
							if scoreLbl then
								scoreLbl.Text = entry.FormattedScore
							end
						else
							if nameLbl then
								nameLbl.Text = "---"
							end
							if scoreLbl then
								scoreLbl.Text = "---"
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
