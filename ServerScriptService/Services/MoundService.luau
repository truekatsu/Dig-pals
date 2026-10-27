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

local MIN_MOUND_SEPARATION_STUDS = 6
local EDGE_MARGIN_STUDS = 4

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

local function getPlainSurfaceInstances(plain: Instance, spawnZone: BasePart): { Instance }
	local list: { Instance } = {}
	for _, child in plain:GetChildren() do
		if child ~= spawnZone and child.Name ~= "DigBounds" and child.Name ~= "SharedMoundSpawns" then
			table.insert(list, child)
		end
	end
	return list
end

local function findValidGroundPosition(userId: number, referencePosition: Vector3?): Vector3?
	local spawnZone = getSpawnZonePart()
	if not spawnZone then
		warn("[MoundService] Workspace.Plain.SpawnZone BasePart is missing!")
		return nil
	end

	local plain = spawnZone.Parent
	local hasTerrainMesh = plain ~= nil and plain:FindFirstChild("TerrainMesh") ~= nil

	local zonePos = spawnZone.Position
	local zoneSize = spawnZone.Size
	local halfX = math.max(1, (zoneSize.X * 0.5) - EDGE_MARGIN_STUDS)
	local halfZ = math.max(1, (zoneSize.Z * 0.5) - EDGE_MARGIN_STUDS)
	local minX, maxX = zonePos.X - halfX, zonePos.X + halfX
	local minZ, maxZ = zonePos.Z - halfZ, zonePos.Z + halfZ

	local center = referencePosition or zonePos
	local centerX = math.clamp(center.X, minX, maxX)
	local centerZ = math.clamp(center.Z, minZ, maxZ)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	if hasTerrainMesh and plain then
		rayParams.FilterDescendantsInstances = getPlainSurfaceInstances(plain, spawnZone)
	else
		rayParams.FilterDescendantsInstances = { spawnZone }
	end

	local userMounds = ensureUserTable(userId)
	local radius = MoundsConfig.SpawnRadiusStuds

	for _ = 1, 28 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = math.sqrt(rng:NextNumber(0, 1)) * radius
		local candidateX = math.clamp(centerX + math.cos(angle) * dist, minX, maxX)
		local candidateZ = math.clamp(centerZ + math.sin(angle) * dist, minZ, maxZ)

		local rayOrigin = Vector3.new(candidateX, zonePos.Y + 100, candidateZ)
		local rayDirection = Vector3.new(0, -200, 0)
		local hit = workspace:Raycast(rayOrigin, rayDirection, rayParams)

		if hit then
			local validSurface = true
			if hasTerrainMesh then
				-- Only spawn personal mounds on open walkable grass (never on SpawnPlaza, cobblestone roads, shops, pond, or steep cliffs)
				if hit.Instance.Material ~= Enum.Material.LeafyGrass or hit.Normal.Y < 0.85 or hit.Position.Y > 6.0 then
					validSurface = false
				end
			end

			if validSurface then
				local hitPos = hit.Position
				local tooClose = false
				for _, existing in userMounds do
					if (existing.Position - hitPos).Magnitude < MIN_MOUND_SEPARATION_STUDS then
						tooClose = true
						break
					end
				end
				if not tooClose then
					return hitPos
				end
			end
		end
	end

	-- Fallback raycast on open grass offset if center was on paved SpawnPlaza
	local fallbackX = if math.abs(centerX) < 28 and math.abs(centerZ) < 28 then math.clamp(-38, minX, maxX) else centerX
	local fallbackZ = if math.abs(centerX) < 28 and math.abs(centerZ) < 28 then math.clamp(12, minZ, maxZ) else centerZ
	local fallbackOrigin = Vector3.new(fallbackX, zonePos.Y + 100, fallbackZ)
	local fallbackHit = workspace:Raycast(fallbackOrigin, Vector3.new(0, -200, 0), rayParams)
	if fallbackHit then
		return fallbackHit.Position
	end

	return Vector3.new(fallbackX, zonePos.Y + (zoneSize.Y * 0.5), fallbackZ)
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
