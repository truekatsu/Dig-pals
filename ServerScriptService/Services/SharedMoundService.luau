--!strict
-- Authoritative Shared Rare Mound Spawning, Multiplayer Concurrent Digging, and Contribution-based Rewards (Step 11)

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))
local Weighted = require(Shared:WaitForChild("Util"):WaitForChild("Weighted"))
local DigTiming = require(Shared:WaitForChild("Util"):WaitForChild("DigTiming"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local MoundsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Mounds"))
local ShovelsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Shovels"))
local EggsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Eggs"))
local ItemsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Items"))
local EconomyConfig = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))
local RarityConfig = require(Shared:WaitForChild("Config"):WaitForChild("Rarity"))
local AssetIds = require(Shared:WaitForChild("AssetIds"))

local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
local ShovelInventoryService = require(script.Parent:WaitForChild("ShovelInventoryService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))

export type SharedStrikeSession = {
	UserId: number,
	StartTime: number,
	LastStrikeTime: number,
	Attempt: DigTiming.Attempt,
}

export type SharedMoundInstance = {
	Id: string,
	SpawnPointName: string,
	Position: Vector3,
	HP: number,
	MaxHP: number,
	Scale: Vector3,
	SpawnedAt: number,
	ExpiresAt: number,
	IsActive: boolean,
	Cleared: boolean,
	RewardDistributed: boolean,
	Contributions: { [number]: number },
	PlayerStrikes: { [number]: { Perfect: number, Good: number, Miss: number } },
	Sessions: { [number]: SharedStrikeSession },
	AttemptMisses: { [number]: number },
}

export type UserRewardSummary = {
	UserId: number,
	PlayerName: string,
	DamageDealt: number,
	ContributionRatio: number,
	IsTopContributor: boolean,
	EggDrops: { any },
	ItemDrops: { any },
	SpecialShovelsWon: { string },
}

local SharedMoundService = {}

local activeSharedMound: SharedMoundInstance? = nil
local nextSpawnClock: number = 0
local serverRng = Random.new()
local started = false

local itemsByRarity: { [Types.RarityName]: { Types.ItemConfig } } = {
	Common = {},
	Uncommon = {},
	Rare = {},
	Epic = {},
	Legendary = {},
}

local function buildItemPools()
	for _, rarityName in RarityConfig.Order do
		itemsByRarity[rarityName] = {}
	end
	for _, itemConfig in ItemsConfig.All do
		local bucket = itemsByRarity[itemConfig.Rarity]
		if bucket then
			table.insert(bucket, itemConfig)
		end
	end
	for _, bucket in itemsByRarity do
		table.sort(bucket, function(a: Types.ItemConfig, b: Types.ItemConfig): boolean
			return a.Id < b.Id
		end)
	end
end

buildItemPools()

local function computeIndexLuckBonus(profile: Types.PlayerProfile?): number
	if not profile or not profile.Index or not profile.Index.Items then
		return 0
	end
	local discoveredItems = profile.Index.Items
	local bonus = 0
	for _, rarityName in RarityConfig.Order do
		local pool = itemsByRarity[rarityName]
		if pool and #pool > 0 then
			local allFound = true
			for _, itemConfig in pool do
				if not discoveredItems[itemConfig.Id] then
					allFound = false
					break
				end
			end
			if allFound then
				bonus += RarityConfig.IndexRewards.ItemRarityLuckBonus
			end
		end
	end
	return bonus
end

local function getMoundInteractionRadius(scale: Vector3): number
	return (scale.X * 0.5) + MoundsConfig.DigRangeStuds
end

local function isWithinSharedMoundRange(playerPos: Vector3, moundPos: Vector3, scale: Vector3): boolean
	local dx = playerPos.X - moundPos.X
	local dz = playerPos.Z - moundPos.Z
	local horizontalDist = math.sqrt(dx * dx + dz * dz)
	return horizontalDist <= getMoundInteractionRadius(scale)
end

local function getPlayerCharacterPosition(player: Player?): Vector3?
	if not player then
		return nil
	end
	local character = player.Character
	if not character then
		return nil
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart.Position
	end
	return nil
end

local function getEquippedShovelConfig(player: Player?, profileOverride: Types.PlayerProfile?): Types.ShovelConfig
	local profile = profileOverride or (if player then PlayerState.Get(player) else nil)
	if profile and profile.Shovels and profile.Shovels.Equipped then
		local configured = ShovelsConfig.All[profile.Shovels.Equipped]
		if configured then
			return configured
		end
	end
	return ShovelsConfig.All[EconomyConfig.StartingShovel] or ShovelsConfig.All.RustyShovel
end

function SharedMoundService.GetActiveMound(): SharedMoundInstance?
	return activeSharedMound
end

function SharedMoundService.IsSharedMound(moundId: string): boolean
	if not activeSharedMound then
		return false
	end
	return activeSharedMound.Id == moundId
end

function SharedMoundService.GetRemainingSeconds(): number
	if not activeSharedMound or not activeSharedMound.IsActive then
		return 0
	end
	local now = workspace:GetServerTimeNow()
	return math.max(0, activeSharedMound.ExpiresAt - now)
end

function SharedMoundService.SetNextSpawnTime(timeClock: number)
	nextSpawnClock = timeClock
end

function SharedMoundService.GetNextSpawnTime(): number
	return nextSpawnClock
end

function SharedMoundService.GetSpawnPoints(): { { Name: string, Position: Vector3 } }
	local points = {}
	local plain = workspace:FindFirstChild("Plain")
	local spawnFolder = plain and plain:FindFirstChild("SharedMoundSpawns")
	if not spawnFolder and plain then
		spawnFolder = Instance.new("Folder")
		spawnFolder.Name = "SharedMoundSpawns"
		spawnFolder.Parent = plain
	end
	if spawnFolder and #spawnFolder:GetChildren() == 0 then
		local defaults = {
			SharedSpawn01 = Vector3.new(-75.0, 0.0, -25.0),
			SharedSpawn02 = Vector3.new(-80.0, 0.0, 35.0),
			SharedSpawn03 = Vector3.new(75.0, 0.0, 45.0),
			SharedSpawn04 = Vector3.new(95.0, 0.0, -45.0),
			SharedSpawn05 = Vector3.new(-95.0, 0.0, 10.0),
		}
		for name, pos in pairs(defaults) do
			local p = Instance.new("Part")
			p.Name = name
			p.Position = pos
			p.Size = Vector3.new(4, 1, 4)
			p.Anchored = true
			p.CanCollide = false
			p.Transparency = 1
			p.Parent = spawnFolder
		end
	end
	if spawnFolder then
		for _, child in ipairs(spawnFolder:GetChildren()) do
			if child:IsA("BasePart") then
				table.insert(points, { Name = child.Name, Position = child.Position })
			end
		end
	end
	table.sort(points, function(a, b)
		return a.Name < b.Name
	end)
	return points
end

function SharedMoundService.SpawnSharedMound(
	pointIndex: number?,
	serverNowOverride: number?
): SharedMoundInstance?
	if activeSharedMound and activeSharedMound.IsActive then
		return activeSharedMound
	end

	local spawnPoints = SharedMoundService.GetSpawnPoints()
	if #spawnPoints == 0 then
		warn("[SharedMoundService] No SharedMoundSpawns parts found in Workspace.Plain!")
		return nil
	end

	local chosenPoint
	if pointIndex and spawnPoints[pointIndex] then
		chosenPoint = spawnPoints[pointIndex]
	else
		chosenPoint = spawnPoints[serverRng:NextInteger(1, #spawnPoints)]
	end

	local now = serverNowOverride or workspace:GetServerTimeNow()
	local groundPos = chosenPoint.Position

	-- Raycast down to find ground surface
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	local plain = workspace:FindFirstChild("Plain")
	if plain then
		local terrainMesh = plain:FindFirstChild("TerrainMesh")
		if terrainMesh then
			raycastParams.FilterDescendantsInstances = { terrainMesh }
		end
	end

	local hit = workspace:Raycast(chosenPoint.Position + Vector3.new(0, 10, 0), Vector3.new(0, -30, 0), raycastParams)
	if hit then
		groundPos = hit.Position
	end

	local MoundService = require(script.Parent:WaitForChild("MoundService"))
	local isForbidden, reason = MoundService.IsPositionForbidden(groundPos, 10.0)
	if isForbidden then
		warn("[SharedMoundService] Chosen spawn point " .. chosenPoint.Name .. " is forbidden (" .. tostring(reason) .. "), finding alternative...")
		for _, altPoint in ipairs(spawnPoints) do
			if altPoint ~= chosenPoint then
				local altHit = workspace:Raycast(altPoint.Position + Vector3.new(0, 10, 0), Vector3.new(0, -30, 0), raycastParams)
				local altPos = altHit and altHit.Position or altPoint.Position
				local altForbidden = MoundService.IsPositionForbidden(altPos, 10.0)
				if not altForbidden then
					chosenPoint = altPoint
					groundPos = altPos
					isForbidden = false
					break
				end
			end
		end
		if isForbidden then
			warn("[SharedMoundService] All SharedMoundSpawns are currently forbidden! Aborting spawn.")
			return nil
		end
	end

	local moundId = string.format("SharedMound_%d", os.time())
	local duration = MoundsConfig.Shared.DurationSeconds

	local mound: SharedMoundInstance = {
		Id = moundId,
		SpawnPointName = chosenPoint.Name,
		Position = groundPos,
		HP = MoundsConfig.Shared.HP,
		MaxHP = MoundsConfig.Shared.HP,
		Scale = MoundsConfig.Shared.Scale,
		SpawnedAt = now,
		ExpiresAt = now + duration,
		IsActive = true,
		Cleared = false,
		RewardDistributed = false,
		Contributions = {},
		PlayerStrikes = {},
		Sessions = {},
		AttemptMisses = {},
	}

	activeSharedMound = mound

	-- Broadcast MoundSpawned to all clients so they render 3D visual and billboard
	Remotes.GetEvent("MoundSpawned"):FireAllClients({
		Id = mound.Id,
		Size = "Shared",
		DisplayName = MoundsConfig.Shared.DisplayName,
		Position = mound.Position,
		HP = mound.HP,
		MaxHP = mound.MaxHP,
		Scale = mound.Scale,
		IsShared = true,
		ExpiresAt = mound.ExpiresAt,
	})

	-- Broadcast notification alert to entire server
	Remotes.GetEvent("SharedMoundAlert"):FireAllClients({
		Event = "Spawned",
		MoundId = mound.Id,
		Position = mound.Position,
		SpawnPointName = mound.SpawnPointName,
		HP = mound.HP,
		MaxHP = mound.MaxHP,
		ExpiresAt = mound.ExpiresAt,
		Duration = duration,
		Message = string.format("Gundukan Langka telah muncul di %s! HP: 3,000 (Hilang dalam 4 menit)", mound.SpawnPointName),
	})

	print(string.format("[SharedMoundService] Rare Mound spawned at %s (%s) with %d HP, expires in %ds", mound.SpawnPointName, tostring(groundPos), mound.HP, duration))
	return mound
end

function SharedMoundService.DespawnSharedMound(reason: string?)
	if not activeSharedMound then
		return
	end
	local mound = activeSharedMound
	mound.IsActive = false
	activeSharedMound = nil

	local despawnReason = reason or "Expired"
	Remotes.GetEvent("MoundDespawned"):FireAllClients(mound.Id, despawnReason)

	if despawnReason == "Expired" then
		Remotes.GetEvent("SharedMoundAlert"):FireAllClients({
			Event = "Expired",
			MoundId = mound.Id,
			Message = "Gundukan Langka telah menghilang.",
		})
		print(string.format("[SharedMoundService] Rare Mound %s expired without being cleared.", mound.Id))
	end
end

function SharedMoundService.StartSession(
	userId: number,
	player: Player?,
	moundId: string,
	serverNowOverride: number?,
	playerPosOverride: Vector3?
): (boolean, string?, SharedStrikeSession?)
	local mound = activeSharedMound
	if not mound or not mound.IsActive or mound.Id ~= moundId or mound.HP <= 0 then
		return false, "MoundNotFound", nil
	end

	local playerPos = playerPosOverride or getPlayerCharacterPosition(player)
	if not playerPos or not isWithinSharedMoundRange(playerPos, mound.Position, mound.Scale) then
		return false, "OutOfRange", nil
	end

	local now = serverNowOverride or workspace:GetServerTimeNow()
	local existing = mound.Sessions[userId]

	-- Step 6: Block starting a NEW mound when Item Bag is full
	if player and InventoryService.IsPlayerBagFull(player) then
		if player.Parent == Players then
			Remotes.GetEvent("StrikeResult"):FireClient(player, {
				Event = "Rejected",
				MoundId = moundId,
				Reason = "BagFull",
			})
		end
		return false, "BagFull", nil
	end

	-- Inverted logic: Player must be holding/using their shovel to dig
	if player and player.Parent == Players then
		if not ShovelInventoryService.IsShovelHeld(player) then
			Remotes.GetEvent("StrikeResult"):FireClient(player, {
				Event = "Rejected",
				MoundId = moundId,
				Reason = "ShovelNotHeld",
			})
			return false, "ShovelNotHeld", nil
		end
	end

	local shovel = getEquippedShovelConfig(player)
	local session: SharedStrikeSession = {
		UserId = userId,
		StartTime = now,
		LastStrikeTime = if existing then existing.LastStrikeTime else 0,
		Attempt = DigTiming.New(shovel.Id, "Shared", now, mound.AttemptMisses[userId]),
	}
	mound.Sessions[userId] = session

	if player and player.Parent == Players then
		ShovelInventoryService.EnsureShovelHeldForDig(player)
		local shovel = getEquippedShovelConfig(player)
		local timing = MoundsConfig.Shared.Timing
		Remotes.GetEvent("StrikeResult"):FireClient(player, {
			Event = "SessionStarted",
			MoundId = moundId,
			MoundSize = "Shared",
			StartTime = session.StartTime,
			Speed = session.Attempt.Speed,
			GoodWidth = timing.GoodWidth,
			PerfectWidth = timing.PerfectWidth,
			Cooldown = shovel.DigSpeed,
			Minigame = session.Attempt,
		})
	end

	return true, nil, session
end

function SharedMoundService.HasSession(userId: number): boolean
	return activeSharedMound ~= nil and activeSharedMound.Sessions[userId] ~= nil
end

function SharedMoundService.CancelSession(userId: number)
	if activeSharedMound then
		activeSharedMound.Sessions[userId] = nil
	end
end

function SharedMoundService.ExecuteStrike(
	userId: number,
	player: Player?,
	moundId: string,
	serverNowOverride: number?,
	playerPosOverride: Vector3?,
	latencyToleranceOverride: number?,
	profileOverride: Types.PlayerProfile?
): any
	local mound = activeSharedMound
	if not mound or not mound.IsActive or mound.Id ~= moundId or mound.HP <= 0 then
		return {
			Success = false,
			Reason = "MoundNotFound",
		}
	end

	local playerPos = playerPosOverride or getPlayerCharacterPosition(player)
	if not playerPos or not isWithinSharedMoundRange(playerPos, mound.Position, mound.Scale) then
		if player and player.Parent == Players then
			Remotes.GetEvent("StrikeResult"):FireClient(player, {
				Event = "Rejected",
				MoundId = moundId,
				Reason = "OutOfRange",
			})
		end
		return {
			Success = false,
			Reason = "OutOfRange",
		}
	end

	local serverNow = serverNowOverride or workspace:GetServerTimeNow()
	local session = mound.Sessions[userId]
	if not session then
		if player then return { Success = false, Reason = "SessionRequired" } end
		local okStart, errReason, createdSession = SharedMoundService.StartSession(userId, player, moundId, serverNow, playerPos)
		if not okStart or not createdSession then
			return {
				Success = false,
				Reason = errReason or "SessionStartFailed",
			}
		end
		session = createdSession
	end
	if session.Attempt.Failed then return { Success = false, Reason = "DigFailed" } end

	local shovel = getEquippedShovelConfig(player, profileOverride)
	if session.Attempt.ShovelId ~= shovel.Id then return { Success = false, Reason = "ShovelChanged" } end
	if player and player.Parent == Players then
		if not ShovelInventoryService.IsShovelHeld(player) then
			return {
				Success = false,
				Reason = "ShovelNotHeld",
			}
		end
	end
	if session.LastStrikeTime > 0 and (serverNow - session.LastStrikeTime) < shovel.DigSpeed then
		return {
			Success = false,
			Reason = "Cooldown",
		}
	end

	local timing = session.Attempt
	local elapsed = math.max(0, serverNow - session.StartTime)
	local tolerance = if latencyToleranceOverride ~= nil
		then latencyToleranceOverride
		else MoundsConfig.LatencyToleranceSeconds

	local grade, hitPos = Weighted.EvaluateStrikeWithLatency(
		elapsed,
		timing.Speed,
		timing.GoodWidth,
		timing.PerfectWidth,
		tolerance,
		timing.ZoneCenter
	)

	local multiplier = (MoundsConfig.StrikeDamageMultipliers :: any)[grade] or 0
	local damage = shovel.Power * multiplier

	local strikes = mound.PlayerStrikes[userId]
	if not strikes then
		strikes = { Perfect = 0, Good = 0, Miss = 0 }
		mound.PlayerStrikes[userId] = strikes
	end

	if grade == "Perfect" then
		strikes.Perfect += 1
	elseif grade == "Good" then
		strikes.Good += 1
	else
		strikes.Miss += 1
	end

	session.LastStrikeTime = serverNow
	local failed = DigTiming.RecordStrike(session.Attempt, grade)
	mound.AttemptMisses[userId] = if failed then 0 else session.Attempt.Misses
	if failed then
		-- Shared HP and earned contribution belong to everyone; only this player's attempt ends.
		if player and player.Parent == Players then
			ShovelInventoryService.PlayStrikeSwing(player)
			Remotes.GetEvent("StrikeResult"):FireClient(player, {
				Event = "DigFailed", MoundId = mound.Id, RemainingHP = mound.HP,
				MaxHP = mound.MaxHP, Minigame = session.Attempt,
			})
		end
		return { Success = true, Failed = true, Grade = grade, Damage = 0, RemainingHP = mound.HP, MaxHP = mound.MaxHP, Cleared = false }
	end
	mound.HP = math.max(0, mound.HP - damage)
	mound.Contributions[userId] = (mound.Contributions[userId] or 0) + damage

	print(
		string.format(
			"[SharedMoundService] Strike | UserId=%d | Pos=%.3f | Grade=%s | Damage=%.2f | HP=%.2f/%d | Contrib=%.1f",
			userId,
			hitPos,
			grade,
			damage,
			mound.HP,
			mound.MaxHP,
			mound.Contributions[userId]
		)
	)

	local cleared = mound.HP <= 0

	if player and player.Parent == Players then
		ShovelInventoryService.EnsureShovelHeldForDig(player)
		ShovelInventoryService.PlayStrikeSwing(player)
		Remotes.GetEvent("StrikeResult"):FireClient(player, {
			Event = "StrikeHit",
			MoundId = mound.Id,
			Grade = grade,
			Damage = damage,
			RemainingHP = mound.HP,
			MaxHP = mound.MaxHP,
			Cleared = cleared,
			Cooldown = shovel.DigSpeed,
			NextStrikeAllowedAt = serverNow + shovel.DigSpeed,
			Minigame = session.Attempt,
		})
	end

	-- Broadcast authoritative HP update to all players
	Remotes.GetEvent("MoundUpdated"):FireAllClients(mound.Id, mound.HP, mound.MaxHP)

	if cleared then
		SharedMoundService.CompleteSharedMound(mound)
	end

	return {
		Success = true,
		Grade = grade,
		Damage = damage,
		RemainingHP = mound.HP,
		MaxHP = mound.MaxHP,
		Cleared = cleared,
	}
end

function SharedMoundService.ApplyPetDamage(
	player: Player?,
	userId: number,
	petGuid: string,
	damage: number
): (boolean, number, boolean)
	local mound = activeSharedMound
	if not mound or not mound.IsActive or mound.HP <= 0 then
		return false, 0, false
	end

	if damage <= 0 then
		return false, mound.HP, false
	end

	mound.HP = math.max(0, mound.HP - damage)
	mound.Contributions[userId] = (mound.Contributions[userId] or 0) + damage

	print(
		string.format(
			"[SharedMoundService] PetAttack | UserId=%d | Pet=%s | Dmg=%.1f | HP=%.2f/%d | Contrib=%.1f",
			userId,
			petGuid,
			damage,
			mound.HP,
			mound.MaxHP,
			mound.Contributions[userId]
		)
	)

	local cleared = mound.HP <= 0

	if player and player.Parent == Players then
		Remotes.GetEvent("PetAttackVisual"):FireClient(player, petGuid, mound.Id, damage)
	end

	Remotes.GetEvent("MoundUpdated"):FireAllClients(mound.Id, mound.HP, mound.MaxHP)

	if cleared then
		SharedMoundService.CompleteSharedMound(mound)
	end

	return true, mound.HP, cleared
end

function SharedMoundService.CalculateRewardsForUser(
	userId: number,
	playerName: string,
	profile: Types.PlayerProfile,
	totalDamage: number,
	maxHp: number,
	isTopContributor: boolean,
	rngOverride: Random?
): UserRewardSummary
	local rng = rngOverride or serverRng
	local equippedShovelId = if profile.Shovels and profile.Shovels.Equipped
		then profile.Shovels.Equipped
		else EconomyConfig.StartingShovel
	local shovelConfig = ShovelsConfig.All[equippedShovelId] or ShovelsConfig.All.RustyShovel

	local indexLuckBonus = computeIndexLuckBonus(profile)
	local effectiveLuck = math.min(
		MoundsConfig.MaxEffectiveLuck,
		(shovelConfig.Luck + indexLuckBonus) * MoundsConfig.Shared.RewardLuckMultiplier
	)

	-- 1. Egg rolls: 2 rolls base + 1 bonus if top contributor
	local eggRollCount = MoundsConfig.Shared.RewardEggRolls
	if isTopContributor then
		eggRollCount += MoundsConfig.Shared.TopContributorBonusEggRolls
	end

	local eggDrops = {}
	local adjustedEggWeights = Weighted.ApplyLuck(MoundsConfig.Shared.EggRarityWeights, effectiveLuck)

	for _ = 1, eggRollCount do
		local chosenRarityRaw = Weighted.Pick(adjustedEggWeights, rng)
		local chosenRarity: Types.RarityName = if chosenRarityRaw == "Common" then "Uncommon" else (chosenRarityRaw :: Types.RarityName)
		local eggId = EggsConfig.RarityEggByTier[chosenRarity] or "UncommonEgg"
		local eggCfg = EggsConfig.All[eggId] or EggsConfig.All.UncommonEgg
		local drop = {
			DropType = "Egg",
			Id = eggCfg.Id,
			DisplayName = eggCfg.DisplayName,
			Rarity = chosenRarity,
			SellPrice = eggCfg.SellPrice,
			AutoSold = false,
			AutoSoldCoins = 0,
		}
		table.insert(eggDrops, drop)
	end

	-- 2. Item roll: 1 roll
	local itemDrops = {}
	local adjustedItemWeights = Weighted.ApplyLuck(MoundsConfig.Shared.ItemRarityWeights, effectiveLuck)
	for _ = 1, MoundsConfig.Shared.RewardItemRolls do
		local chosenRarityRaw = Weighted.Pick(adjustedItemWeights, rng)
		local chosenRarity: Types.RarityName = if RarityConfig.ById[chosenRarityRaw :: Types.RarityName]
			then (chosenRarityRaw :: Types.RarityName)
			else "Common"
		local pool = itemsByRarity[chosenRarity] or itemsByRarity.Common
		local itemCfg = pool[rng:NextInteger(1, #pool)]
		local drop = {
			DropType = "Item",
			Id = itemCfg.Id,
			DisplayName = itemCfg.DisplayName,
			Rarity = chosenRarity,
			SellPrice = itemCfg.SellPrice,
			AutoSold = false,
			AutoSoldCoins = 0,
		}
		table.insert(itemDrops, drop)
	end

	-- 3. Special Shovels: 0.5% Mossy, 0.2% Moonlit
	local specialShovelsWon: { string } = {}
	if rng:NextNumber() < MoundsConfig.Shared.SpecialShovelDropChances.MossyShovel then
		table.insert(specialShovelsWon, "MossyShovel")
	end
	if rng:NextNumber() < MoundsConfig.Shared.SpecialShovelDropChances.MoonlitShovel then
		table.insert(specialShovelsWon, "MoonlitShovel")
	end

	return {
		UserId = userId,
		PlayerName = playerName,
		DamageDealt = totalDamage,
		ContributionRatio = totalDamage / maxHp,
		IsTopContributor = isTopContributor,
		EggDrops = eggDrops,
		ItemDrops = itemDrops,
		SpecialShovelsWon = specialShovelsWon,
	}
end

function SharedMoundService.DistributeRewards(
	mound: SharedMoundInstance,
	rngOverride: Random?
): { [number]: UserRewardSummary }
	local rng = rngOverride or serverRng
	local minDamageThreshold = mound.MaxHP * MoundsConfig.Shared.MinContributionRatio
	local summaries: { [number]: UserRewardSummary } = {}

	-- Determine top contributor among ALL contributors
	local topUserId: number? = nil
	local maxDamage = 0
	for uId, dmg in mound.Contributions do
		if dmg > maxDamage then
			maxDamage = dmg
			topUserId = uId
		end
	end

	for userId, totalDamage in mound.Contributions do
		if totalDamage >= minDamageThreshold then
			local player = Players:GetPlayerByUserId(userId)
			local profile = if player then PlayerState.Get(player) else nil
			local isTop = (userId == topUserId)
			local playerName = if player then player.Name else string.format("Player_%d", userId)

			if player and profile then
				local summary = SharedMoundService.CalculateRewardsForUser(
					userId,
					playerName,
					profile,
					totalDamage,
					mound.MaxHP,
					isTop,
					rng
				)

				PlayerState.Mutate(player, function(mutableProfile: Types.PlayerProfile)
					for _, eggDrop in summary.EggDrops do
						InventoryService.AddDropToProfile(mutableProfile, eggDrop)
					end
					local IndexService = require(script.Parent:WaitForChild("IndexService"))
					for _, itemDrop in summary.ItemDrops do
						InventoryService.AddDropToProfile(mutableProfile, itemDrop)
						IndexService.RegisterItemDiscovery(player, mutableProfile, itemDrop.Id)
					end
				end)

				local QuestService = require(script.Parent:WaitForChild("QuestService"))
				QuestService.RecordProgress(player, "MoundCleared", 1)
				QuestService.RecordProgress(player, "MediumOrLargeMoundCleared", 1)
				for _, itemDrop in summary.ItemDrops do
					if itemDrop.Rarity == "Rare" or itemDrop.Rarity == "Epic" or itemDrop.Rarity == "Legendary" then
						QuestService.RecordProgress(player, "RareOrHigherItemFound", 1)
					end
				end

				for _, shovelId in summary.SpecialShovelsWon do
					ShovelInventoryService.GrantShovel(player, shovelId)
					print(string.format("[SharedMoundService] %s won special shovel %s!", player.Name, shovelId))
				end

				summaries[userId] = summary

				Remotes.GetEvent("SharedMoundAlert"):FireClient(player, {
					Event = "Reward",
					Summary = summary,
				})
			end
		else
			print(
				string.format(
					"[SharedMoundService] UserId %d dealt %.1f damage (< %.1f / 3%% min threshold) - 0 rewards.",
					userId,
					totalDamage,
					minDamageThreshold
				)
			)
		end
	end

	return summaries
end

function SharedMoundService.CompleteSharedMound(mound: SharedMoundInstance, rngOverride: Random?)
	if mound.RewardDistributed then
		return
	end
	mound.RewardDistributed = true
	mound.IsActive = false
	mound.Cleared = true

	local summaries = SharedMoundService.DistributeRewards(mound, rngOverride)

	local topUserId: number? = nil
	local topDamage = 0
	for uId, dmg in mound.Contributions do
		if dmg > topDamage then
			topDamage = dmg
			topUserId = uId
		end
	end

	local topName = "None"
	local topRatio = 0
	if topUserId then
		local topP = Players:GetPlayerByUserId(topUserId)
		topName = if topP then topP.Name else string.format("Player_%d", topUserId)
		topRatio = math.clamp(topDamage / mound.MaxHP, 0, 1)
	end

	Remotes.GetEvent("MoundDespawned"):FireAllClients(mound.Id, "Cleared")

	Remotes.GetEvent("SharedMoundAlert"):FireAllClients({
		Event = "Cleared",
		MoundId = mound.Id,
		TopContributor = topName,
		TopContributionPercent = math.floor(topRatio * 100),
		Message = string.format("Gundukan Langka berhasil dihancurkan! Top Damager: %s (%d%%)", topName, math.floor(topRatio * 100)),
	})

	print(string.format("[SharedMoundService] Rare Mound %s cleared! Top contributor: %s (%d damage)", mound.Id, topName, topDamage))
	activeSharedMound = nil
end

function SharedMoundService.Start()
	if started then
		return
	end
	started = true

	local now = workspace:GetServerTimeNow()
	nextSpawnClock = now + MoundsConfig.Shared.SpawnIntervalSeconds

	-- Late-joining player: send active shared mound if exists
	Players.PlayerAdded:Connect(function(player: Player)
		local mound = activeSharedMound
		if mound and mound.IsActive and mound.HP > 0 then
			Remotes.GetEvent("MoundSpawned"):FireClient(player, {
				Id = mound.Id,
				Size = "Shared",
				DisplayName = MoundsConfig.Shared.DisplayName,
				Position = mound.Position,
				HP = mound.HP,
				MaxHP = mound.MaxHP,
				Scale = mound.Scale,
				IsShared = true,
				ExpiresAt = mound.ExpiresAt,
			})

			Remotes.GetEvent("SharedMoundAlert"):FireClient(player, {
				Event = "Spawned",
				MoundId = mound.Id,
				Position = mound.Position,
				SpawnPointName = mound.SpawnPointName,
				HP = mound.HP,
				MaxHP = mound.MaxHP,
				ExpiresAt = mound.ExpiresAt,
				Duration = math.max(0, mound.ExpiresAt - workspace:GetServerTimeNow()),
				Message = string.format("Gundukan Langka sedang aktif di %s! HP: %d (Sisa waktu)", mound.SpawnPointName, math.ceil(mound.HP)),
			})
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		if activeSharedMound then
			activeSharedMound.Sessions[player.UserId] = nil
		end
	end)

	-- 1-second server lifecycle loop
	task.spawn(function()
		while true do
			task.wait(1.0)
			local serverNow = workspace:GetServerTimeNow()

			if activeSharedMound and activeSharedMound.IsActive then
				if serverNow >= activeSharedMound.ExpiresAt then
					SharedMoundService.DespawnSharedMound("Expired")
					nextSpawnClock = serverNow + MoundsConfig.Shared.SpawnIntervalSeconds
				end
			else
				if serverNow >= nextSpawnClock then
					SharedMoundService.SpawnSharedMound()
					nextSpawnClock = serverNow + MoundsConfig.Shared.SpawnIntervalSeconds
				end
			end
		end
	end)
end

return SharedMoundService
