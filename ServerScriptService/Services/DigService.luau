--!strict
-- Server-authoritative timing bar sessions, range & cooldown validation, and strike damage (Step 4)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))
local Weighted = require(Shared:WaitForChild("Util"):WaitForChild("Weighted"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local MoundsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Mounds"))
local ShovelsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Shovels"))
local EconomyConfig = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))

local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
local MoundService = require(script.Parent:WaitForChild("MoundService"))
local ShovelInventoryService = require(script.Parent:WaitForChild("ShovelInventoryService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))

export type StrikeSession = {
	UserId: number,
	MoundId: string,
	StartTime: number,
	LastStrikeTime: number,
}

export type StrikeOutcome = {
	Success: boolean,
	Reason: string?,
	Grade: Types.StrikeGrade?,
	Damage: number?,
	RemainingHP: number?,
	MaxHP: number?,
	Cleared: boolean?,
}

export type MoundClearedCallback = (player: Player?, userId: number, mound: MoundService.MoundInstance) -> ()

local DigService = {}

local activeSessionsByUserId: { [number]: StrikeSession } = {}
local moundClearedCallbacks: { MoundClearedCallback } = {}
local started = false

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

local function isWithinDigRange(playerPos: Vector3, moundPos: Vector3): boolean
	local dx = playerPos.X - moundPos.X
	local dz = playerPos.Z - moundPos.Z
	local horizontalDist = math.sqrt(dx * dx + dz * dz)
	return horizontalDist <= MoundsConfig.DigRangeStuds
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

function DigService.OnMoundCleared(callback: MoundClearedCallback)
	table.insert(moundClearedCallbacks, callback)
end

function DigService.GetSession(userId: number): StrikeSession?
	return activeSessionsByUserId[userId]
end

function DigService.CancelSession(userId: number)
	activeSessionsByUserId[userId] = nil
end

function DigService.StartSession(
	userId: number,
	player: Player?,
	moundId: string,
	serverNowOverride: number?,
	playerPosOverride: Vector3?
): (boolean, string?, StrikeSession?)
	local mound = MoundService.GetMound(userId, moundId)
	if not mound or mound.HP <= 0 then
		return false, "MoundNotFound", nil
	end

	local playerPos = playerPosOverride or getPlayerCharacterPosition(player)
	if not playerPos or not isWithinDigRange(playerPos, mound.Position) then
		return false, "OutOfRange", nil
	end

	local now = serverNowOverride or workspace:GetServerTimeNow()
	local existing = activeSessionsByUserId[userId]
	if existing and existing.MoundId == moundId then
		return true, nil, existing
	end

	-- Step 6: Block starting a NEW mound when Item Bag is full; an already active mound above continues freely
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

	local session: StrikeSession = {
		UserId = userId,
		MoundId = moundId,
		StartTime = now,
		LastStrikeTime = if existing then existing.LastStrikeTime else 0,
	}
	activeSessionsByUserId[userId] = session
	MoundService.TouchMound(userId, moundId)

	if player and player.Parent == Players then
		ShovelInventoryService.EnsureShovelHeldForDig(player)
		local sizeConfig = MoundsConfig.Sizes[mound.Size] or MoundsConfig.Sizes.Small
		local shovel = getEquippedShovelConfig(player)
		Remotes.GetEvent("StrikeResult"):FireClient(player, {
			Event = "SessionStarted",
			MoundId = moundId,
			MoundSize = mound.Size,
			StartTime = session.StartTime,
			Speed = sizeConfig.Timing.Speed,
			GoodWidth = sizeConfig.Timing.GoodWidth,
			PerfectWidth = sizeConfig.Timing.PerfectWidth,
			Cooldown = shovel.DigSpeed,
		})
	end

	return true, nil, session
end

function DigService.ExecuteStrike(
	userId: number,
	player: Player?,
	moundId: string,
	serverNowOverride: number?,
	playerPosOverride: Vector3?,
	latencyToleranceOverride: number?,
	profileOverride: Types.PlayerProfile?
): StrikeOutcome
	local mound = MoundService.GetMound(userId, moundId)
	if not mound or mound.HP <= 0 then
		return {
			Success = false,
			Reason = "MoundNotFound",
		}
	end

	local playerPos = playerPosOverride or getPlayerCharacterPosition(player)
	if not playerPos or not isWithinDigRange(playerPos, mound.Position) then
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
	local session = activeSessionsByUserId[userId]
	if not session or session.MoundId ~= moundId then
		local okStart, errReason, createdSession = DigService.StartSession(userId, player, moundId, serverNow, playerPos)
		if not okStart or not createdSession then
			return {
				Success = false,
				Reason = errReason or "SessionStartFailed",
			}
		end
		session = createdSession
	end

	local shovel = getEquippedShovelConfig(player, profileOverride)
	if session.LastStrikeTime > 0 and (serverNow - session.LastStrikeTime) < shovel.DigSpeed then
		return {
			Success = false,
			Reason = "Cooldown",
		}
	end

	local sizeConfig = MoundsConfig.Sizes[mound.Size] or MoundsConfig.Sizes.Small
	local timing = sizeConfig.Timing
	local elapsed = math.max(0, serverNow - session.StartTime)
	local tolerance = if latencyToleranceOverride ~= nil
		then latencyToleranceOverride
		else MoundsConfig.LatencyToleranceSeconds

	local grade, hitPos = Weighted.EvaluateStrikeWithLatency(
		elapsed,
		timing.Speed,
		timing.GoodWidth,
		timing.PerfectWidth,
		tolerance
	)

	local multiplier = (MoundsConfig.StrikeDamageMultipliers :: any)[grade] or 0.25
	local damage = shovel.Power * multiplier

	if grade == "Perfect" then
		mound.PerfectCount += 1
	elseif grade == "Good" then
		mound.GoodCount += 1
	else
		mound.MissCount += 1
	end

	session.LastStrikeTime = serverNow
	mound.HP = math.max(0, mound.HP - damage)
	MoundService.TouchMound(userId, moundId)

	print(
		string.format(
			"[DigService] Strike | UserId=%d | Mound=%s (%s) | Pos=%.3f | Grade=%s | Damage=%.2f | HP=%.2f/%d",
			userId,
			mound.Id,
			mound.Size,
			hitPos,
			grade,
			damage,
			mound.HP,
			mound.MaxHP
		)
	)

	local cleared = mound.HP <= 0

	if player and player.Parent == Players then
		ShovelInventoryService.EnsureShovelHeldForDig(player)
		ShovelInventoryService.PlayStrikeSwing(player)
		Remotes.GetEvent("MoundUpdated"):FireClient(player, mound.Id, mound.HP, mound.MaxHP)
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
		})
	end

	if cleared then
		activeSessionsByUserId[userId] = nil
		for _, callback in moundClearedCallbacks do
			local ok, err = pcall(callback, player, userId, mound)
			if not ok then
				warn(string.format("[DigService] Error in MoundClearedCallback: %s", tostring(err)))
			end
		end
		MoundService.DespawnMound(userId, mound.Id, "Cleared")
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

function DigService.Start()
	if started then
		return
	end
	started = true

	Remotes.OnServerEvent("StartDig", function(player: Player, moundId: string)
		DigService.StartSession(player.UserId, player, moundId)
	end)

	Remotes.OnServerEvent("CancelDig", function(player: Player)
		DigService.CancelSession(player.UserId)
	end)

	Remotes.OnServerEvent("Strike", function(player: Player, moundId: string)
		DigService.ExecuteStrike(player.UserId, player, moundId)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		activeSessionsByUserId[player.UserId] = nil
	end)
end

return DigService
