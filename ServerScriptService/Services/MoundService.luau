--!strict
-- Authoritative server-wide mound spawning, raycast placement, cap enforcement, and idle despawn.

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
	DigFailed: boolean?,
}

local MoundService = {}

local activeMounds: { [string]: MoundInstance } = {}
local lastSpawnClock = 0
local rng = Random.new()
local started = false

local DEFAULT_STRUCTURE_CLEARANCE_STUDS = 6.0

local function getValleyFloor(): BasePart?
	local plain = workspace:FindFirstChild("Plain")
	if not plain then
		return nil
	end
	local terrainMesh = plain:FindFirstChild("TerrainMesh")
	local valleyFloor = terrainMesh and terrainMesh:FindFirstChild("ValleyFloor")
	if valleyFloor and valleyFloor:IsA("BasePart") then
		return valleyFloor
	end
	return nil
end

function MoundService.GetActiveMounds(): { [string]: MoundInstance }
	return activeMounds
end

-- Compatibility alias for existing callers. Mounds are no longer player-owned.
function MoundService.GetPlayerMounds(_userId: number): { [string]: MoundInstance }
	return activeMounds
end

function MoundService.GetActiveCount(_userId: number?): number
	local count = 0
	for _ in activeMounds do
		count += 1
	end
	return count
end

function MoundService.GetMound(_userId: number, moundId: string): MoundInstance?
	return activeMounds[moundId]
end

local function getObstacleOverlapParams(): OverlapParams
	local filterList: { Instance } = {}
	local valleyFloor = getValleyFloor()
	if valleyFloor then
		table.insert(filterList, valleyFloor)
	end
	local plain = workspace:FindFirstChild("Plain")
	local legacySpawnZone = plain and plain:FindFirstChild("SpawnZone")
	if legacySpawnZone then
		table.insert(filterList, legacySpawnZone)
	end
	-- Characters are temporary occupants, not map obstacles. They are checked separately
	-- while choosing a new spawn so walking up to an existing mound never despawns it.
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(filterList, player.Character)
		end
	end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = filterList
	return overlap
end

local function getGroundRaycastParams(): RaycastParams
	local filterList: { Instance } = {}
	local valleyFloor = getValleyFloor()
	if valleyFloor then
		table.insert(filterList, valleyFloor)
	end
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Include
	ray.FilterDescendantsInstances = filterList
	return ray
end

function MoundService.IsPositionForbidden(pos: Vector3, clearanceOverride: number?): (boolean, string?)
	local clearance = clearanceOverride or DEFAULT_STRUCTURE_CLEARANCE_STUDS
	local valleyFloor = getValleyFloor()
	if not valleyFloor then
		return true, "Forbidden:MissingValleyFloor"
	end

	-- Query the entire Workspace. Only the floor and the legacy invisible SpawnZone are ignored,
	-- so roads, buildings, props, water, characters, boundaries, and future map additions are
	-- automatically treated as obstacles without maintaining hard-coded exclusion rectangles.
	local overlap = getObstacleOverlapParams()
	local queryHeight = math.max(6, clearance)
	local queryCenter = pos + Vector3.new(0, queryHeight * 0.5, 0)
	local querySize = Vector3.new(clearance * 2, queryHeight, clearance * 2)
	local nearbyParts = workspace:GetPartBoundsInBox(CFrame.new(queryCenter), querySize, overlap)
	for _, part in ipairs(nearbyParts) do
		return true, "Forbidden:NearObstacle_" .. part.Name
	end

	-- Verify the center and perimeter remain on the flat playable floor.
	local groundRay = getGroundRaycastParams()
	local probeOffsets = {
		Vector3.zero,
		Vector3.new(clearance, 0, 0),
		Vector3.new(-clearance, 0, 0),
		Vector3.new(0, 0, clearance),
		Vector3.new(0, 0, -clearance),
	}
	for _, offset in ipairs(probeOffsets) do
		local probeHit = workspace:Raycast(pos + offset + Vector3.new(0, 50, 0), Vector3.new(0, -100, 0), groundRay)
		if not probeHit then
			return true, "Forbidden:PerimeterOffMesh"
		end
		if probeHit.Instance ~= valleyFloor then
			return true, "Forbidden:PerimeterNonGrass"
		end
		if probeHit.Normal.Y < 0.88 or math.abs(probeHit.Position.Y - pos.Y) > 0.75 then
			return true, "Forbidden:PerimeterSlopeOrHeight"
		end
	end

	return false, nil
end

local function getMoundRadius(sizeName: Types.MoundSizeName): number
	local sizeConfig = MoundsConfig.Sizes[sizeName] or MoundsConfig.Sizes.Small
	return math.max(sizeConfig.Scale.X, sizeConfig.Scale.Z) * 0.5
end

local function isTooCloseToAnyMound(candidate: Vector3, candidateRadius: number): boolean
	for _, existing in activeMounds do
		local existingRadius = getMoundRadius(existing.Size)
		local delta = Vector2.new(candidate.X - existing.Position.X, candidate.Z - existing.Position.Z)
		if delta.Magnitude < candidateRadius + existingRadius + MoundsConfig.MoundGapStuds then
			return true
		end
	end
	return false
end

local function isTooCloseToAnyCharacter(candidate: Vector3, candidateRadius: number): boolean
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if rootPart and rootPart:IsA("BasePart") then
			local delta = Vector2.new(candidate.X - rootPart.Position.X, candidate.Z - rootPart.Position.Z)
			if delta.Magnitude < candidateRadius + 4 then
				return true
			end
		end
	end
	return false
end

local function findValidGroundPosition(moundSize: Types.MoundSizeName): Vector3?
	local valleyFloor = getValleyFloor()
	if not valleyFloor then
		warn("[MoundService] Workspace.Plain.TerrainMesh.ValleyFloor is missing!")
		return nil
	end

	local radius = getMoundRadius(moundSize)
	local clearance = radius + MoundsConfig.ObstacleClearanceStuds
	local edgeMargin = clearance + MoundsConfig.SpawnEdgeMarginStuds
	local floorPos = valleyFloor.Position
	local floorSize = valleyFloor.Size
	local halfX = math.max(1, floorSize.X * 0.5 - edgeMargin)
	local halfZ = math.max(1, floorSize.Z * 0.5 - edgeMargin)
	local minX, maxX = floorPos.X - halfX, floorPos.X + halfX
	local minZ, maxZ = floorPos.Z - halfZ, floorPos.Z + halfZ
	local groundRay = getGroundRaycastParams()

	-- Uniformly search the entire playable floor instead of restricting spawns to the
	-- player's vicinity or two fixed fields. Collision and perimeter checks decide validity.
	for _ = 1, MoundsConfig.SpawnSearchAttempts do
		local candidateX = rng:NextNumber(minX, maxX)
		local candidateZ = rng:NextNumber(minZ, maxZ)
		local rayOrigin = Vector3.new(candidateX, floorPos.Y + 100, candidateZ)
		local hit = workspace:Raycast(rayOrigin, Vector3.new(0, -200, 0), groundRay)
		if hit and hit.Instance == valleyFloor and hit.Normal.Y >= 0.88 then
			local isForbidden = MoundService.IsPositionForbidden(hit.Position, clearance)
			if not isForbidden
				and not isTooCloseToAnyMound(hit.Position, radius)
				and not isTooCloseToAnyCharacter(hit.Position, radius)
			then
				return hit.Position
			end
		end
	end

	return nil
end

local function findValidGroundPositionNear(referencePosition: Vector3, moundSize: Types.MoundSizeName): Vector3?
	local valleyFloor = getValleyFloor()
	if not valleyFloor then return nil end
	local radius = getMoundRadius(moundSize)
	local clearance = radius + MoundsConfig.ObstacleClearanceStuds
	local groundRay = getGroundRaycastParams()
	local startAngle = rng:NextNumber(0, math.pi * 2)
	for _, distance in { 10, 14, 18, 22, 26, 30 } do
		for directionIndex = 0, 11 do
			local angle = startAngle + directionIndex * math.pi / 6
			local probe = referencePosition + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
			local hit = workspace:Raycast(probe + Vector3.new(0, 80, 0), Vector3.new(0, -160, 0), groundRay)
			if hit and hit.Instance == valleyFloor and hit.Normal.Y >= 0.88 then
				local forbidden = MoundService.IsPositionForbidden(hit.Position, clearance)
				if not forbidden
					and not isTooCloseToAnyMound(hit.Position, radius)
					and not isTooCloseToAnyCharacter(hit.Position, radius)
				then
					return hit.Position
				end
			end
		end
	end
	return nil
end

local function makePayload(mound: MoundInstance): { [string]: any }
	local sizeConfig = MoundsConfig.Sizes[mound.Size] or MoundsConfig.Sizes.Small
	return {
		Id = mound.Id,
		Size = mound.Size,
		DisplayName = sizeConfig.DisplayName,
		Position = mound.Position,
		HP = mound.HP,
		MaxHP = mound.MaxHP,
		Scale = sizeConfig.Scale,
		IsShared = false,
	}
end

local function sendActiveMoundsToPlayer(player: Player)
	for _, mound in activeMounds do
		Remotes.GetEvent("MoundSpawned"):FireClient(player, makePayload(mound))
	end
end

local function createMoundAt(chosenSize: Types.MoundSizeName, groundPos: Vector3, nowTimestamp: number?): MoundInstance
	local sizeConfig = MoundsConfig.Sizes[chosenSize] or MoundsConfig.Sizes.Small
	local now = nowTimestamp or os.time()
	local moundId = "Mound_" .. HttpService:GenerateGUID(false)
	local mound: MoundInstance = {
		Id = moundId,
		OwnerUserId = 0,
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
	activeMounds[moundId] = mound
	Remotes.GetEvent("MoundSpawned"):FireAllClients(makePayload(mound))
	return mound
end

function MoundService.SpawnMound(nowTimestamp: number?): MoundInstance?
	if MoundService.GetActiveCount() >= MoundsConfig.MaxActivePerServer then
		return nil
	end

	local chosenSize = Weighted.Pick(MoundsConfig.SizeWeights, rng) :: Types.MoundSizeName
	-- Keep at least one easy target available for players doing the first tutorial objective.
	local hasSmall = false
	for _, activeMound in activeMounds do
		if activeMound.Size == "Small" and activeMound.HP > 0 then
			hasSmall = true
			break
		end
	end
	if not hasSmall then chosenSize = "Small" end

	local groundPos = findValidGroundPosition(chosenSize)
	if not groundPos then
		return nil
	end

	return createMoundAt(chosenSize, groundPos, nowTimestamp)
end

-- Keep onboarding actionable without changing the shared 24-mound server cap.
function MoundService.EnsureTutorialMound(player: Player): MoundInstance?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return nil end
	local nearest: MoundInstance? = nil
	local nearestDistance = math.huge
	for _, mound in activeMounds do
		if mound.Size == "Small" and mound.HP > 0 then
			local delta = Vector2.new(mound.Position.X - root.Position.X, mound.Position.Z - root.Position.Z)
			if delta.Magnitude < nearestDistance then
				nearest, nearestDistance = mound, delta.Magnitude
			end
		end
	end
	if nearest and nearestDistance <= 32 then return nearest end
	if MoundService.GetActiveCount() >= MoundsConfig.MaxActivePerServer then return nearest end
	local groundPos = findValidGroundPositionNear(root.Position, "Small")
	if not groundPos then return nearest end
	return createMoundAt("Small", groundPos, os.time())
end

-- Compatibility wrapper retained for tests and older services. Identity and reference
-- position are intentionally ignored because normal mounds belong to the server.
function MoundService.SpawnMoundForUser(
	_userId: number,
	_player: Player?,
	_referencePosition: Vector3?,
	nowTimestamp: number?
): MoundInstance?
	return MoundService.SpawnMound(nowTimestamp)
end

function MoundService.DespawnMound(_userId: number, moundId: string, reason: string): boolean
	if not activeMounds[moundId] then return false end
	activeMounds[moundId] = nil
	Remotes.GetEvent("MoundDespawned"):FireAllClients(moundId, reason)

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

	local toRemove: { string } = {}
	for moundId, mound in activeMounds do
		if (now - mound.LastInteractedAt) >= MoundsConfig.DespawnIdleSeconds then
			table.insert(toRemove, moundId)
		end
	end
	for _, moundId in toRemove do
		if MoundService.DespawnMound(0, moundId, "Expired") then
			despawnedCount += 1
		end
	end

	return despawnedCount
end

function MoundService.ClearAllMounds(reason: string?)
	local ids: { string } = {}
	for moundId in activeMounds do table.insert(ids, moundId) end
	for _, moundId in ids do MoundService.DespawnMound(0, moundId, reason or "Reset") end
end

-- Legacy test helper. Player departure must never call this function.
function MoundService.ClearUserMounds(_userId: number)
	MoundService.ClearAllMounds("Reset")
end

function MoundService.AuditActiveMounds(_userId: number?): number
	local removedCount = 0
	local toRemove: { string } = {}
	for moundId, mound in activeMounds do
		local clearance = getMoundRadius(mound.Size) + MoundsConfig.ObstacleClearanceStuds
		local isForbidden = MoundService.IsPositionForbidden(mound.Position, clearance)
		if isForbidden then
			table.insert(toRemove, moundId)
		end
	end
	for _, moundId in toRemove do
		if MoundService.DespawnMound(0, moundId, "ForbiddenLocation") then
			removedCount += 1
		end
	end

	return removedCount
end

local function setupPlayer(player: Player)
	task.delay(2, function()
		if player.Parent == Players then sendActiveMoundsToPlayer(player) end
	end)
	player.CharacterAdded:Connect(function()
		task.delay(1, function()
			if player.Parent == Players then sendActiveMoundsToPlayer(player) end
		end)
	end)
end

function MoundService.Start()
	if started then
		return
	end
	started = true
	lastSpawnClock = os.clock() - MoundsConfig.SpawnIntervalSeconds

	Players.PlayerAdded:Connect(setupPlayer)

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

			local activeCount = MoundService.GetActiveCount()
			if #Players:GetPlayers() > 0 and activeCount < MoundsConfig.MaxActivePerServer then
				if (nowClock - lastSpawnClock) >= MoundsConfig.SpawnIntervalSeconds then
					local spawned = MoundService.SpawnMound(nowEpoch)
					if spawned then
						lastSpawnClock = nowClock
					end
				end
			else
				-- A replacement gets the full interval after a mound is cleared.
				lastSpawnClock = nowClock
			end
		end
	end)
end

return MoundService
