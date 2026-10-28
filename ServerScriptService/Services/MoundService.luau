--!strict
-- Authoritative personal mound spawning, raycast placement, cap enforcement, and idle despawn (Step 3)

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))
local Weighted = require(Shared:WaitForChild("Util"):WaitForChild("Weighted"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local MoundsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Mounds"))

export type MoundInstance = {
	Id: string,
	OwnerUserId: number,
	Size: Types.MoundSizeName,
	Position: Vector3,
	HP: number,
	MaxHP: number,
	CreatedAt: number,
	LastInteractedAt: number,
	PerfectCount: number,
	GoodCount: number,
	MissCount: number,
}

local MoundService = {}

local moundsByUserId: { [number]: { [string]: MoundInstance } } = {}
local lastSpawnClockByUserId: { [number]: number } = {}
local rng = Random.new()
local started = false

local MIN_MOUND_SEPARATION_STUDS = 6.0
local EDGE_MARGIN_STUDS = 4.0
local REQUIRED_STRUCTURE_CLEARANCE_STUDS = 8.0 -- Largest mound scale is (8, 4, 8) -> radius 4.0 studs. 8.0 clearance guarantees at least 4.0 studs margin to any road/base/shop

-- Analytical Exclusion Zones
local FORBIDDEN_BASE_MAX_Z = 85.0 -- BasePlots start at Z = 107.1; Z >= 85 gives 22+ studs clearance
local FORBIDDEN_SHOP_MIN_X = -55.0
local FORBIDDEN_SHOP_MAX_X = 55.0
local FORBIDDEN_SHOP_MAX_Z = -24.0 -- Covers shops (Z in [-141, -77]) AND front cobblestone plaza/walkway down to SpawnPlaza
local FORBIDDEN_SPAWN_PLAZA_RADIUS = 30.0 -- Full circular coverage of SpawnPlaza and surrounding curbs
local FORBIDDEN_BASE_PATH_HALF_WIDTH = 26.0 -- South walkway leading from SpawnPlaza (Z = 0) towards BasePlots (Z = 85)
local FORBIDDEN_BASE_PATH_MIN_Z = 0.0
local FORBIDDEN_BASE_PATH_MAX_Z = 85.0
local FORBIDDEN_LEADERBOARD_MIN_X = -55.0
local FORBIDDEN_LEADERBOARD_MAX_X = -25.0
local FORBIDDEN_LEADERBOARD_MIN_Z = -70.0
local FORBIDDEN_LEADERBOARD_MAX_Z = -24.0
local FORBIDDEN_POND_MIN_X = 120.0
local FORBIDDEN_POND_MAX_X = 185.0
local FORBIDDEN_POND_MIN_Z = -170.0
local FORBIDDEN_POND_MAX_Z = -115.0

local SAFE_DIG_FIELDS = {
	{ minX = -110.0, maxX = -50.0, minZ = -50.0, maxZ = 40.0 }, -- West open field
	{ minX = 50.0, maxX = 110.0, minZ = -50.0, maxZ = 40.0 },   -- East open field
}

local function getSpawnZonePart(): BasePart?
	local plain = workspace:FindFirstChild("Plain")
	if not plain then
		return nil
	end
	local spawnZone = plain:FindFirstChild("SpawnZone")
	if spawnZone and spawnZone:IsA("BasePart") then
		return spawnZone
	end

	-- Self-heal invisible DigField bounding box if missing from Workspace.Plain
	local created = Instance.new("Part")
	created.Name = "SpawnZone"
	created.Size = Vector3.new(290, 2, 138)
	created.Position = Vector3.new(0, 0, -7.5)
	created.Anchored = true
	created.CanCollide = false
	created.CanTouch = false
	created.CanQuery = false
	created.CastShadow = false
	created.Transparency = 1
	created.Parent = plain
	return created
end

local function ensureUserTable(userId: number): { [string]: MoundInstance }
	local existing = moundsByUserId[userId]
	if existing then
		return existing
	end
	local created: { [string]: MoundInstance } = {}
	moundsByUserId[userId] = created
	return created
end

function MoundService.GetPlayerMounds(userId: number): { [string]: MoundInstance }
	return ensureUserTable(userId)
end

function MoundService.GetActiveCount(userId: number): number
	local userMounds = moundsByUserId[userId]
	if not userMounds then
		return 0
	end
	local count = 0
	for _ in userMounds do
		count += 1
	end
	return count
end

function MoundService.GetMound(userId: number, moundId: string): MoundInstance?
	local userMounds = moundsByUserId[userId]
	if not userMounds then
		return nil
	end
	return userMounds[moundId]
end

local function getStructureOverlapParams(): OverlapParams
	local plain = workspace:FindFirstChild("Plain")
	local basePlots = workspace:FindFirstChild("BasePlots")
	local filterList: { Instance } = {}
	if plain then
		for _, name in { "TerrainMesh", "Road_PondPath", "Merchant", "Hub", "SandyGate", "PondGarden", "CrystalGrove" } do
			local folder = plain:FindFirstChild(name)
			if folder then
				table.insert(filterList, folder)
			end
		end
	end
	if basePlots then
		table.insert(filterList, basePlots)
	end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = filterList
	return overlap
end

local function getGroundRaycastParams(): RaycastParams
	local plain = workspace:FindFirstChild("Plain")
	local basePlots = workspace:FindFirstChild("BasePlots")
	local filterList: { Instance } = {}
	if plain then
		local terrainMesh = plain:FindFirstChild("TerrainMesh")
		if terrainMesh then
			local valleyFloor = terrainMesh:FindFirstChild("ValleyFloor")
			if valleyFloor then
				table.insert(filterList, valleyFloor)
			else
				table.insert(filterList, terrainMesh)
			end
		else
			table.insert(filterList, plain)
		end
	end
	if basePlots then
		table.insert(filterList, basePlots)
	end
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Include
	ray.FilterDescendantsInstances = filterList
	return ray
end

function MoundService.IsPositionForbidden(pos: Vector3, clearanceOverride: number?): (boolean, string?)
	local clearance = clearanceOverride or REQUIRED_STRUCTURE_CLEARANCE_STUDS

	-- 1. Analytical 2D bounds check
	-- Base: strict rejection anywhere near BasePlots (Z >= 85)
	if pos.Z >= FORBIDDEN_BASE_MAX_Z then
		return true, "Forbidden:BaseZone"
	end

	-- Shops & Shop Front Approach: anywhere north of SpawnPlaza within X in [-55, 55]
	if pos.Z <= FORBIDDEN_SHOP_MAX_Z and pos.X >= FORBIDDEN_SHOP_MIN_X and pos.X <= FORBIDDEN_SHOP_MAX_X then
		return true, "Forbidden:ShopAndFrontApproach"
	end

	-- Spawn Plaza: circular hub exclusion
	if (pos.X * pos.X + pos.Z * pos.Z) < (FORBIDDEN_SPAWN_PLAZA_RADIUS * FORBIDDEN_SPAWN_PLAZA_RADIUS) then
		return true, "Forbidden:SpawnPlaza"
	end

	-- South Walkway to BasePlots
	if math.abs(pos.X) <= FORBIDDEN_BASE_PATH_HALF_WIDTH and pos.Z >= FORBIDDEN_BASE_PATH_MIN_Z and pos.Z <= FORBIDDEN_BASE_PATH_MAX_Z then
		return true, "Forbidden:BasePath"
	end

	-- Leaderboards Plaza
	if pos.X >= FORBIDDEN_LEADERBOARD_MIN_X and pos.X <= FORBIDDEN_LEADERBOARD_MAX_X and pos.Z >= FORBIDDEN_LEADERBOARD_MIN_Z and pos.Z <= FORBIDDEN_LEADERBOARD_MAX_Z then
		return true, "Forbidden:LeaderboardPlaza"
	end

	-- Pond Garden & Crystals
	if pos.X >= FORBIDDEN_POND_MIN_X and pos.X <= FORBIDDEN_POND_MAX_X and pos.Z >= FORBIDDEN_POND_MIN_Z and pos.Z <= FORBIDDEN_POND_MAX_Z then
		return true, "Forbidden:PondGarden"
	end

	-- 2. Physical 3D Spatial Clearance Check (ensures NO part of the mound touches any road, curb, base, or shop)
	local overlap = getStructureOverlapParams()
	local nearbyParts = workspace:GetPartBoundsInRadius(pos, clearance, overlap)
	for _, part in ipairs(nearbyParts) do
		if part.Name ~= "ValleyFloor" and part.Material ~= Enum.Material.LeafyGrass then
			return true, "Forbidden:NearObstacle_" .. part.Name
		end
	end

	-- 3. Perimeter 4-probe ground verification (offset 4.2 studs, guaranteeing edges sit on level grass)
	local groundRay = getGroundRaycastParams()
	local probeOffsets = {
		Vector3.new(4.2, 0, 0),
		Vector3.new(-4.2, 0, 0),
		Vector3.new(0, 0, 4.2),
		Vector3.new(0, 0, -4.2),
	}
	for _, offset in ipairs(probeOffsets) do
		local probeHit = workspace:Raycast(pos + offset + Vector3.new(0, 50, 0), Vector3.new(0, -100, 0), groundRay)
		if not probeHit then
			return true, "Forbidden:PerimeterOffMesh"
		end
		if probeHit.Instance.Name ~= "ValleyFloor" and probeHit.Instance.Material ~= Enum.Material.LeafyGrass then
			return true, "Forbidden:PerimeterNonGrass"
		end
		if probeHit.Normal.Y < 0.88 or probeHit.Position.Y > 1.0 then
			return true, "Forbidden:PerimeterSlopeOrHeight"
		end
	end

	return false, nil
end

local function findValidGroundPosition(userId: number, referencePosition: Vector3?): Vector3?
	local spawnZone = getSpawnZonePart()
	if not spawnZone then
		warn("[MoundService] Workspace.Plain.SpawnZone BasePart is missing!")
		return nil
	end

	local zonePos = spawnZone.Position
	local zoneSize = spawnZone.Size
	local halfX = math.max(1, (zoneSize.X * 0.5) - EDGE_MARGIN_STUDS)
	local halfZ = math.max(1, (zoneSize.Z * 0.5) - EDGE_MARGIN_STUDS)
	local minX, maxX = zonePos.X - halfX, zonePos.X + halfX
	local minZ, maxZ = zonePos.Z - halfZ, zonePos.Z + halfZ

	local center = referencePosition or zonePos
	local centerX = math.clamp(center.X, minX, maxX)
	local centerZ = math.clamp(center.Z, minZ, maxZ)

	local groundRay = getGroundRaycastParams()
	local userMounds = ensureUserTable(userId)
	local radius = MoundsConfig.SpawnRadiusStuds

	-- Pass 1: Local candidate generation around referencePosition (up to 35 attempts)
	for _ = 1, 35 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = math.sqrt(rng:NextNumber(0, 1)) * radius
		local candidateX = math.clamp(centerX + math.cos(angle) * dist, minX, maxX)
		local candidateZ = math.clamp(centerZ + math.sin(angle) * dist, minZ, maxZ)

		local rayOrigin = Vector3.new(candidateX, zonePos.Y + 60, candidateZ)
		local hit = workspace:Raycast(rayOrigin, Vector3.new(0, -120, 0), groundRay)

		if hit and hit.Instance.Name == "ValleyFloor" and hit.Instance.Material == Enum.Material.LeafyGrass and hit.Normal.Y >= 0.88 and hit.Position.Y <= 1.0 then
			local isForbidden = MoundService.IsPositionForbidden(hit.Position, REQUIRED_STRUCTURE_CLEARANCE_STUDS)
			if not isForbidden then
				local tooClose = false
				for _, existing in userMounds do
					if (existing.Position - hit.Position).Magnitude < MIN_MOUND_SEPARATION_STUDS then
						tooClose = true
						break
					end
				end
				if not tooClose then
					return hit.Position
				end
			end
		end
	end

	-- Pass 2: Safe open grass dig fields fallback (if player is on road, inside shop, or in base)
	for _ = 1, 30 do
		local field = SAFE_DIG_FIELDS[rng:NextInteger(1, #SAFE_DIG_FIELDS)]
		local candidateX = rng:NextNumber(field.minX, field.maxX)
		local candidateZ = rng:NextNumber(field.minZ, field.maxZ)

		local rayOrigin = Vector3.new(candidateX, zonePos.Y + 60, candidateZ)
		local hit = workspace:Raycast(rayOrigin, Vector3.new(0, -120, 0), groundRay)

		if hit and hit.Instance.Name == "ValleyFloor" and hit.Instance.Material == Enum.Material.LeafyGrass and hit.Normal.Y >= 0.88 and hit.Position.Y <= 1.0 then
			local isForbidden = MoundService.IsPositionForbidden(hit.Position, REQUIRED_STRUCTURE_CLEARANCE_STUDS)
			if not isForbidden then
				local tooClose = false
				for _, existing in userMounds do
					if (existing.Position - hit.Position).Magnitude < MIN_MOUND_SEPARATION_STUDS then
						tooClose = true
						break
					end
				end
				if not tooClose then
					return hit.Position
				end
			end
		end
	end

	return nil
end

local function getCharacterPosition(player: Player?): Vector3?
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

function MoundService.SpawnMoundForUser(
	userId: number,
	player: Player?,
	referencePosition: Vector3?,
	nowTimestamp: number?
): MoundInstance?
	if MoundService.GetActiveCount(userId) >= MoundsConfig.MaxActivePerPlayer then
		return nil
	end

	local refPos = referencePosition or getCharacterPosition(player)
	local groundPos = findValidGroundPosition(userId, refPos)
	if not groundPos then
		return nil
	end

	local chosenSize = Weighted.Pick(MoundsConfig.SizeWeights, rng) :: Types.MoundSizeName
	local sizeConfig = MoundsConfig.Sizes[chosenSize] or MoundsConfig.Sizes.Small
	local now = nowTimestamp or os.time()
	local moundId = "Mound_" .. HttpService:GenerateGUID(false)

	local mound: MoundInstance = {
		Id = moundId,
		OwnerUserId = userId,
		Size = sizeConfig.Id,
		Position = groundPos,
		HP = sizeConfig.HP,
		MaxHP = sizeConfig.HP,
		CreatedAt = now,
		LastInteractedAt = now,
		PerfectCount = 0,
		GoodCount = 0,
		MissCount = 0,
	}

	local userMounds = ensureUserTable(userId)
	userMounds[moundId] = mound

	if player and player.Parent == Players then
		Remotes.GetEvent("MoundSpawned"):FireClient(player, {
			Id = mound.Id,
			Size = mound.Size,
			DisplayName = sizeConfig.DisplayName,
			Position = mound.Position,
			HP = mound.HP,
			MaxHP = mound.MaxHP,
			Scale = sizeConfig.Scale,
			IsShared = false,
		})
	end

	return mound
end

function MoundService.DespawnMound(userId: number, moundId: string, reason: string): boolean
	local userMounds = moundsByUserId[userId]
	if not userMounds or not userMounds[moundId] then
		return false
	end

	userMounds[moundId] = nil

	local player = Players:GetPlayerByUserId(userId)
	if player then
		Remotes.GetEvent("MoundDespawned"):FireClient(player, moundId, reason)
	end

	return true
end

function MoundService.TouchMound(userId: number, moundId: string, nowTimestamp: number?)
	local mound = MoundService.GetMound(userId, moundId)
	if mound then
		mound.LastInteractedAt = nowTimestamp or os.time()
	end
end

function MoundService.CheckIdleDespawns(nowTimestamp: number?): number
	local now = nowTimestamp or os.time()
	local despawnedCount = 0

	for userId, userMounds in moundsByUserId do
		local toRemove: { string } = {}
		for moundId, mound in userMounds do
			if (now - mound.LastInteractedAt) >= MoundsConfig.DespawnIdleSeconds then
				table.insert(toRemove, moundId)
			end
		end
		for _, moundId in toRemove do
			if MoundService.DespawnMound(userId, moundId, "Expired") then
				despawnedCount += 1
			end
		end
	end

	return despawnedCount
end

function MoundService.ClearUserMounds(userId: number)
	moundsByUserId[userId] = nil
	lastSpawnClockByUserId[userId] = nil
end

function MoundService.AuditActiveMounds(userId: number?): number
	local removedCount = 0
	local targetUsers = if userId then { [userId] = moundsByUserId[userId] } else moundsByUserId

	for uId, userMounds in targetUsers do
		if userMounds then
			local toRemove: { string } = {}
			for moundId, mound in userMounds do
				local isForbidden = MoundService.IsPositionForbidden(mound.Position, REQUIRED_STRUCTURE_CLEARANCE_STUDS)
				if isForbidden then
					table.insert(toRemove, moundId)
				end
			end
			for _, moundId in toRemove do
				if MoundService.DespawnMound(uId, moundId, "ForbiddenLocation") then
					removedCount += 1
				end
			end
		end
	end

	return removedCount
end

local function setupPlayer(player: Player)
	local userId = player.UserId
	ensureUserTable(userId)
	-- Allow first mound to spawn as soon as the character loads
	lastSpawnClockByUserId[userId] = os.clock() - MoundsConfig.SpawnIntervalSeconds
end

function MoundService.Start()
	if started then
		return
	end
	started = true

	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(function(player: Player)
		MoundService.ClearUserMounds(player.UserId)
	end)

	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end

	-- Main spawn and idle-despawn loop
	task.spawn(function()
		while true do
			task.wait(1)
			local nowClock = os.clock()
			local nowEpoch = os.time()

			MoundService.CheckIdleDespawns(nowEpoch)
			MoundService.AuditActiveMounds()

			for _, player in Players:GetPlayers() do
				local userId = player.UserId
				local activeCount = MoundService.GetActiveCount(userId)
				if activeCount < MoundsConfig.MaxActivePerPlayer then
					local lastSpawn = lastSpawnClockByUserId[userId] or 0
					if (nowClock - lastSpawn) >= MoundsConfig.SpawnIntervalSeconds then
						local charPos = getCharacterPosition(player)
						if charPos then
							local spawned = MoundService.SpawnMoundForUser(userId, player, charPos, nowEpoch)
							if spawned then
								lastSpawnClockByUserId[userId] = nowClock
							end
						end
					end
				else
					-- Keep timer fresh while at max capacity so replacement after digging waits 8s
					lastSpawnClockByUserId[userId] = nowClock
				end
			end
		end
	end)
end

return MoundService
