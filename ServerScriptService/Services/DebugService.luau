--!strict
-- Authoritative Debug & Telemetry Service for Dig Pals (Step 16)
-- Only active for configured Owner UserId in Studio or testing server.
-- Enforces zero client trust, provides debug commands, and logs gameplay telemetry.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local EconomyConfig = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))
local PetsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Pets"))
local EggsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Eggs"))

local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local ShovelInventoryService = require(script.Parent:WaitForChild("ShovelInventoryService"))

local DebugService = {}
local started = false

-- Test server detection: Studio or private test place
local isTestEnvironment = RunService:IsStudio() or game.PlaceId == 0

function DebugService.IsAuthorized(player: Player): boolean
	if not isTestEnvironment then
		return false
	end
	return EconomyConfig.OwnerUserIds[player.UserId] == true
end

function DebugService.AddCoins(player: Player, amount: number): (boolean, string?)
	if not DebugService.IsAuthorized(player) then
		return false, "Unauthorized"
	end
	if type(amount) ~= "number" or amount ~= amount or math.abs(amount) == math.huge then
		return false, "InvalidAmount"
	end

	local mutated = PlayerState.Mutate(player, function(profile: Types.PlayerProfile)
		profile.Coins = math.max(0, math.floor(profile.Coins + amount))
		profile.TotalCoinsEarned = math.max(profile.TotalCoinsEarned, profile.Coins)
	end)
	if mutated then
		DataService.SavePlayer(player)
		ShovelInventoryService.SendStateSync(player)
		print(string.format("[DebugService] User %s (%d) added %d coins", player.Name, player.UserId, amount))
		return true, nil
	end
	return false, "MutateFailed"
end

function DebugService.SetCoins(player: Player, amount: number): (boolean, string?)
	if not DebugService.IsAuthorized(player) then
		return false, "Unauthorized"
	end
	if type(amount) ~= "number" or amount < 0 or amount ~= amount or math.abs(amount) == math.huge then
		return false, "InvalidAmount"
	end

	local mutated = PlayerState.Mutate(player, function(profile: Types.PlayerProfile)
		profile.Coins = math.floor(amount)
		profile.TotalCoinsEarned = math.max(profile.TotalCoinsEarned, profile.Coins)
	end)
	if mutated then
		DataService.SavePlayer(player)
		ShovelInventoryService.SendStateSync(player)
		print(string.format("[DebugService] User %s (%d) set coins to %d", player.Name, player.UserId, amount))
		return true, nil
	end
	return false, "MutateFailed"
end

function DebugService.GiveEgg(player: Player, eggId: string, rarity: string?): (boolean, string?)
	if not DebugService.IsAuthorized(player) then
		return false, "Unauthorized"
	end
	if not EggsConfig.All[eggId] then
		return false, "InvalidEggId"
	end

	local mutated = PlayerState.Mutate(player, function(profile: Types.PlayerProfile)
		table.insert(profile.EggBag, {
			Id = eggId,
			Rarity = (rarity or "Common") :: Types.RarityName,
		})
	end)
	if mutated then
		DataService.SavePlayer(player)
		ShovelInventoryService.SendStateSync(player)
		print(string.format("[DebugService] User %s (%d) received egg %s (%s)", player.Name, player.UserId, eggId, rarity or "Common"))
		return true, nil
	end
	return false, "MutateFailed"
end

function DebugService.GivePet(player: Player, species: string, variant: string?): (boolean, string?)
	if not DebugService.IsAuthorized(player) then
		return false, "Unauthorized"
	end
	local specCfg = PetsConfig.All[species]
	if not specCfg then
		return false, "InvalidSpecies"
	end

	local vName = variant or "Normal"
	local vInfo = (PetsConfig.Variants :: any)[vName] or PetsConfig.Variants.Normal
	local guid = HttpService:GenerateGUID(false)

	local pet: Types.PetInstance = {
		Guid = guid,
		Species = species,
		Variant = vName :: Types.PetVariantName,
		Level = 1,
		Power = specCfg.BasePower * vInfo.PowerMult,
		Speed = specCfg.BaseSpeed * vInfo.SpeedMult,
		DigSpeed = specCfg.BaseDigSpeed * vInfo.DigSpeedMult,
		Range = specCfg.BaseRange,
		AttackInterval = specCfg.BaseAttackInterval,
	}

	local mutated = PlayerState.Mutate(player, function(profile: Types.PlayerProfile)
		profile.Pets[guid] = pet
	end)
	if mutated then
		local IndexService = require(script.Parent:WaitForChild("IndexService"))
		local prof = PlayerState.Get(player)
		if prof then
			IndexService.RegisterPetDiscovery(player, prof, species)
		end
		DataService.SavePlayer(player)
		ShovelInventoryService.SendStateSync(player)
		print(string.format("[DebugService] User %s (%d) received pet %s (%s, GUID=%s)", player.Name, player.UserId, species, vName, guid))
		return true, guid
	end
	return false, "MutateFailed"
end

function DebugService.SkipIncubator(player: Player, slotIndex: number): (boolean, string?)
	if not DebugService.IsAuthorized(player) then
		return false, "Unauthorized"
	end
	local mutated = PlayerState.Mutate(player, function(profile: Types.PlayerProfile)
		local entry = profile.Incubators[slotIndex]
		if entry then
			entry.EndTime = workspace:GetServerTimeNow() - 1
		end
	end)
	if mutated then
		ShovelInventoryService.SendStateSync(player)
		print(string.format("[DebugService] User %s (%d) skipped incubator slot %d", player.Name, player.UserId, slotIndex))
		return true, nil
	end
	return false, "MutateFailed"
end

function DebugService.SpawnRareMound(player: Player?): (boolean, string?)
	if player and not DebugService.IsAuthorized(player) then
		return false, "Unauthorized"
	end
	local SharedMoundService = require(script.Parent:WaitForChild("SharedMoundService"))
	local m = SharedMoundService.SpawnSharedMound()
	if m then
		print("[DebugService] Force spawned Gundukan Langka (Shared Mound)")
		return true, nil
	end
	return false, "SpawnFailed"
end

function DebugService.SetQuestDay(player: Player, dayOffset: number): (boolean, string?)
	if not DebugService.IsAuthorized(player) then
		return false, "Unauthorized"
	end
	local mutated = PlayerState.Mutate(player, function(profile: Types.PlayerProfile)
		if profile.Quests then
			profile.Quests.Day = math.max(0, profile.Quests.Day + dayOffset)
		end
		if profile.Streak then
			profile.Streak.LastClaim = math.max(0, profile.Streak.LastClaim - (math.abs(dayOffset) * 86400))
		end
	end)
	if mutated then
		DataService.SavePlayer(player)
		ShovelInventoryService.SendStateSync(player)
		print(string.format("[DebugService] User %s (%d) adjusted quest day offset %d", player.Name, player.UserId, dayOffset))
		return true, nil
	end
	return false, "MutateFailed"
end

function DebugService.UnlockSandyGate(player: Player): (boolean, string?)
	if not DebugService.IsAuthorized(player) then
		return false, "Unauthorized"
	end
	local mutated = PlayerState.Mutate(player, function(profile: Types.PlayerProfile)
		profile.SandyGateUnlocked = true
	end)
	if mutated then
		player:SetAttribute("SandyGateUnlocked", true)
		DataService.SavePlayer(player)
		ShovelInventoryService.SendStateSync(player)
		print(string.format("[DebugService] User %s (%d) force unlocked Sandy Gate", player.Name, player.UserId))
		return true, nil
	end
	return false, "MutateFailed"
end

-- Telemetry logging functions
function DebugService.OnIronShovelAcquired(player: Player, profile: Types.PlayerProfile)
	if profile.IronShovelTime ~= nil then
		return
	end
	local now = os.time()
	profile.IronShovelTime = now
	local created = profile.CreatedAt or now
	local elapsedSec = math.max(0, now - created)
	local elapsedMin = elapsedSec / 60
	print(string.format("[Telemetry] IRON_SHOVEL_ACQUIRED | Player=%s (%d) | TimeToIronShovel=%.1f min (%d sec)",
		player.Name, player.UserId, elapsedMin, elapsedSec))
end

function DebugService.OnFirstHatch(player: Player, profile: Types.PlayerProfile, species: string)
	if profile.FirstHatchTime ~= nil then
		return
	end
	local now = os.time()
	profile.FirstHatchTime = now
	local created = profile.CreatedAt or now
	local elapsedSec = math.max(0, now - created)
	local elapsedMin = elapsedSec / 60
	print(string.format("[Telemetry] FIRST_EGG_HATCHED | Player=%s (%d) | TimeToFirstHatch=%.1f min (%d sec) | Species=%s",
		player.Name, player.UserId, elapsedMin, elapsedSec, species))
end

function DebugService.OnLegendaryObtained(player: Player, profile: Types.PlayerProfile, source: string, id: string)
	local now = os.time()
	profile.LegendaryCount = (profile.LegendaryCount or 0) + 1
	local created = profile.CreatedAt or now
	local playHours = math.max(0.01, (now - created) / 3600)
	local ratePerHour = (profile.LegendaryCount :: number) / playHours
	print(string.format("[Telemetry] LEGENDARY_OBTAINED | Player=%s (%d) | Source=%s | Id=%s | TotalLegendary=%d | PlayHours=%.2f | Rate=%.2f/hr",
		player.Name, player.UserId, source, id, profile.LegendaryCount :: number, playHours, ratePerHour))
end

function DebugService.Start()
	if started then
		return
	end
	started = true

	Remotes.OnServerInvoke("DebugAction", function(player: Player, action: string, payload: any): any
		if not DebugService.IsAuthorized(player) then
			warn(string.format("[Security] Unauthorized DebugAction '%s' attempted by %s (%d)", action, player.Name, player.UserId))
			return {
				Success = false,
				Reason = "Unauthorized",
				Message = "Perintah debug hanya tersedia untuk Owner di Studio / server testing.",
			}
		end

		if action == "AddCoins" then
			local amount = if type(payload) == "table" then tonumber(payload.Amount) else tonumber(payload)
			local success, reason = DebugService.AddCoins(player, amount or 1000)
			return { Success = success, Reason = reason }
		elseif action == "SetCoins" then
			local amount = if type(payload) == "table" then tonumber(payload.Amount) else tonumber(payload)
			local success, reason = DebugService.SetCoins(player, amount or 0)
			return { Success = success, Reason = reason }
		elseif action == "GiveEgg" then
			local eggId = if type(payload) == "table" then tostring(payload.EggId or "StarterEgg") else tostring(payload or "StarterEgg")
			local rarity = if type(payload) == "table" then payload.Rarity else nil
			local success, reason = DebugService.GiveEgg(player, eggId, rarity)
			return { Success = success, Reason = reason }
		elseif action == "GivePet" then
			local species = if type(payload) == "table" then tostring(payload.Species or "Dog") else tostring(payload or "Dog")
			local variant = if type(payload) == "table" then payload.Variant else nil
			local success, petGuid = DebugService.GivePet(player, species, variant)
			return { Success = success, Reason = petGuid }
		elseif action == "SkipIncubator" then
			local slot = if type(payload) == "table" then tonumber(payload.SlotIndex) else tonumber(payload)
			local success, reason = DebugService.SkipIncubator(player, slot or 1)
			return { Success = success, Reason = reason }
		elseif action == "SpawnRareMound" then
			local success, reason = DebugService.SpawnRareMound(player)
			return { Success = success, Reason = reason }
		elseif action == "SetQuestDay" then
			local offset = if type(payload) == "table" then tonumber(payload.DayOffset) else tonumber(payload)
			local success, reason = DebugService.SetQuestDay(player, offset or 1)
			return { Success = success, Reason = reason }
		elseif action == "UnlockSandyGate" then
			local success, reason = DebugService.UnlockSandyGate(player)
			return { Success = success, Reason = reason }
		end

		return {
			Success = false,
			Reason = "UnknownAction",
		}
	end)
end

return DebugService
