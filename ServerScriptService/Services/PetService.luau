--!strict
-- Server-authoritative pet management, equipped pets, base assignment, release for coins, and pet attack DPS loop (Step 9)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local BaseConfig = require(Shared:WaitForChild("Config"):WaitForChild("Base"))
local PetsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Pets"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
local ShovelInventoryService = require(script.Parent:WaitForChild("ShovelInventoryService"))
local MoundService = require(script.Parent:WaitForChild("MoundService"))
local DigService = require(script.Parent:WaitForChild("DigService"))
local SharedMoundService = require(script.Parent:WaitForChild("SharedMoundService"))

export type EffectivePetStats = {
	Power: number,
	Speed: number,
	DigSpeed: number,
	Range: number,
	AttackInterval: number,
	MoveSpeed: number,
	ReleasePrice: number,
	BaseIncome: number,
}

export type EquipPetResult = {
	Success: boolean,
	Reason: string?,
	Message: string?,
	PetGuid: string?,
	EquippedCount: number?,
}

export type UnequipPetResult = {
	Success: boolean,
	Reason: string?,
	Message: string?,
	PetGuid: string?,
	EquippedCount: number?,
}

export type AssignBasePetResult = {
	Success: boolean,
	Reason: string?,
	Message: string?,
	PetGuid: string?,
	BasePetsCount: number?,
	MaxSlots: number?,
}

export type RemoveBasePetResult = {
	Success: boolean,
	Reason: string?,
	Message: string?,
	PetGuid: string?,
	BasePetsCount: number?,
}

export type ReleasePetResult = {
	Success: boolean,
	Reason: string?,
	Message: string?,
	PetGuid: string?,
	CoinsEarned: number?,
	RemainingPets: number?,
}

local PetService = {}

local started = false
local nextAttackTimeByUserId: { [number]: { [string]: number } } = {}
local dpsLogByUserId: { [number]: { TotalDamage: number, TotalAttacks: number, LastAttackAt: number } } = {}

-- Pure helper: compute effective stats from species & variant modifiers
function PetService.GetEffectiveStats(
	speciesId: string,
	variant: Types.PetVariantName,
	level: number?
): EffectivePetStats
	local speciesCfg = PetsConfig.Species[speciesId]
	assert(speciesCfg, "Invalid speciesId: " .. tostring(speciesId))

	local variantCfg = (PetsConfig.Variants :: any)[variant] or PetsConfig.Variants.Normal
	local petLevel = math.clamp(level or 1, 1, PetsConfig.MaxPetLevel)

	-- Power = species Power x variant PowerMultiplier
	local effectivePower = math.floor(speciesCfg.Power * variantCfg.PowerMultiplier)

	-- Dig Speed = species DigSpeed + variant DigSpeedBonus, clamped to max 10
	local rawDigSpeed = speciesCfg.DigSpeed + variantCfg.DigSpeedBonus
	local effectiveDigSpeed = math.min(PetsConfig.MaxEffectiveDigSpeed, rawDigSpeed)

	-- Speed and Range from species
	local effectiveSpeed = speciesCfg.Speed
	local effectiveRange = speciesCfg.Range

	-- Attack interval = 3.0 - 0.25 x DigSpeed
	local attackInterval = math.max(
		0.25,
		PetsConfig.BaseAttackInterval - (PetsConfig.AttackIntervalReductionPerDigSpeed * effectiveDigSpeed)
	)

	-- Movement speed = 6 + 2 x Speed
	local moveSpeed = PetsConfig.BaseMoveSpeedStuds + (PetsConfig.MoveSpeedPerStat * effectiveSpeed)

	-- Release price by rarity
	local releasePrice = PetsConfig.ReleasePriceByRarity[speciesCfg.Rarity] or 25

	-- Base income
	local baseIncome = speciesCfg.BaseIncome * variantCfg.IncomeMultiplier

	return {
		Power = effectivePower,
		Speed = effectiveSpeed,
		DigSpeed = effectiveDigSpeed,
		Range = effectiveRange,
		AttackInterval = attackInterval,
		MoveSpeed = moveSpeed,
		ReleasePrice = releasePrice,
		BaseIncome = baseIncome,
	}
end

-- Count total pets owned
function PetService.GetPetCount(profile: Types.PlayerProfile): number
	local count = 0
	if type(profile.Pets) == "table" then
		for _ in profile.Pets do
			count += 1
		end
	end
	return count
end

-- Equip Pet in profile (max 3)
function PetService.EquipPetInProfile(
	profile: Types.PlayerProfile,
	petGuid: string
): EquipPetResult
	if type(profile.Pets) ~= "table" or profile.Pets[petGuid] == nil then
		return {
			Success = false,
			Reason = "PetNotFound",
			Message = "Pet tidak ditemukan di dalam Tas Pet.",
		}
	end

	if type(profile.EquippedPets) ~= "table" then
		profile.EquippedPets = {}
	end

	if table.find(profile.EquippedPets, petGuid) ~= nil then
		return {
			Success = false,
			Reason = "AlreadyEquipped",
			Message = "Pet ini sudah digunakan.",
		}
	end

	if type(profile.BasePets) == "table" and table.find(profile.BasePets, petGuid) ~= nil then
		return {
			Success = false,
			Reason = "PetInBase",
			Message = "Pet sedang ditugaskan di Base. Tarik dari base terlebih dahulu.",
		}
	end

	if #profile.EquippedPets >= PetsConfig.MaxEquippedPets then
		return {
			Success = false,
			Reason = "MaxEquippedReached",
			Message = string.format("Maksimal %d pet dapat digunakan sekaligus.", PetsConfig.MaxEquippedPets),
		}
	end

	table.insert(profile.EquippedPets, petGuid)

	return {
		Success = true,
		PetGuid = petGuid,
		EquippedCount = #profile.EquippedPets,
	}
end

-- Unequip Pet in profile
function PetService.UnequipPetInProfile(
	profile: Types.PlayerProfile,
	petGuid: string
): UnequipPetResult
	if type(profile.EquippedPets) ~= "table" then
		return {
			Success = false,
			Reason = "NotEquipped",
			Message = "Pet tidak sedang digunakan.",
		}
	end

	local idx = table.find(profile.EquippedPets, petGuid)
	if not idx then
		return {
			Success = false,
			Reason = "NotEquipped",
			Message = "Pet tidak sedang digunakan.",
		}
	end

	table.remove(profile.EquippedPets, idx)

	return {
		Success = true,
		PetGuid = petGuid,
		EquippedCount = #profile.EquippedPets,
	}
end

-- Assign Pet to Base in profile
function PetService.AssignBasePetInProfile(
	profile: Types.PlayerProfile,
	petGuid: string
): AssignBasePetResult
	if type(profile.Pets) ~= "table" or profile.Pets[petGuid] == nil then
		return {
			Success = false,
			Reason = "PetNotFound",
			Message = "Pet tidak ditemukan di dalam Tas Pet.",
		}
	end

	if type(profile.EquippedPets) == "table" and table.find(profile.EquippedPets, petGuid) ~= nil then
		return {
			Success = false,
			Reason = "PetEquipped",
			Message = "Pet sedang digunakan (Equipped). Lepas equip terlebih dahulu.",
		}
	end

	if type(profile.BasePets) ~= "table" then
		profile.BasePets = {}
	end

	if table.find(profile.BasePets, petGuid) ~= nil then
		return {
			Success = false,
			Reason = "AlreadyInBase",
			Message = "Pet sudah berada di Base.",
		}
	end

	local baseLv = math.clamp(profile.BaseLevel or 1, 1, 5)
	local levelCfg = BaseConfig.Levels[baseLv]
	local maxSlots = if levelCfg then levelCfg.PetSlots else 2

	if #profile.BasePets >= maxSlots then
		return {
			Success = false,
			Reason = "BaseSlotsFull",
			Message = string.format("Slot pet Base penuh (%d/%d). Upgrade Base untuk menambah slot.", #profile.BasePets, maxSlots),
		}
	end

	table.insert(profile.BasePets, petGuid)

	return {
		Success = true,
		PetGuid = petGuid,
		BasePetsCount = #profile.BasePets,
		MaxSlots = maxSlots,
	}
end

-- Remove Pet from Base in profile
function PetService.RemoveBasePetInProfile(
	profile: Types.PlayerProfile,
	petGuid: string
): RemoveBasePetResult
	if type(profile.BasePets) ~= "table" then
		return {
			Success = false,
			Reason = "NotInBase",
			Message = "Pet tidak sedang berada di Base.",
		}
	end

	local idx = table.find(profile.BasePets, petGuid)
	if not idx then
		return {
			Success = false,
			Reason = "NotInBase",
			Message = "Pet tidak sedang berada di Base.",
		}
	end

	table.remove(profile.BasePets, idx)

	return {
		Success = true,
		PetGuid = petGuid,
		BasePetsCount = #profile.BasePets,
	}
end

-- Release Pet for Coins in profile (PRD 8.5)
function PetService.ReleasePetInProfile(
	profile: Types.PlayerProfile,
	petGuid: string
): ReleasePetResult
	if type(profile.Pets) ~= "table" or profile.Pets[petGuid] == nil then
		return {
			Success = false,
			Reason = "PetNotFound",
			Message = "Pet tidak ditemukan di dalam Tas Pet.",
		}
	end

	if type(profile.EquippedPets) == "table" and table.find(profile.EquippedPets, petGuid) ~= nil then
		return {
			Success = false,
			Reason = "PetEquipped",
			Message = "Pet sedang digunakan (Equipped). Lepas equip terlebih dahulu sebelum melepaskan pet.",
		}
	end

	if type(profile.BasePets) == "table" and table.find(profile.BasePets, petGuid) ~= nil then
		return {
			Success = false,
			Reason = "PetInBase",
			Message = "Pet sedang berada di Base. Tarik dari base terlebih dahulu sebelum melepaskan pet.",
		}
	end

	local petData = profile.Pets[petGuid]
	local stats = PetService.GetEffectiveStats(petData.Species, petData.Variant, petData.Level)
	local earnedCoins = stats.ReleasePrice

	profile.Coins = math.max(0, profile.Coins + earnedCoins)
	profile.TotalCoinsEarned += earnedCoins
	profile.Pets[petGuid] = nil

	return {
		Success = true,
		PetGuid = petGuid,
		CoinsEarned = earnedCoins,
		RemainingPets = PetService.GetPetCount(profile),
	}
end

type MoundTarget = {
	Id: string,
	Size: string,
	Position: Vector3,
}

-- Find closest active mound (personal or shared) within range of player position
local function findClosestMoundInRange(
	userId: number,
	avatarPos: Vector3,
	range: number
): (MoundTarget?, number)
	local mounds = MoundService.GetPlayerMounds(userId)
	local closest: MoundTarget? = nil
	local closestDist = range + 0.001

	for _, mound in mounds do
		if mound.HP > 0 then
			local dist = (mound.Position - avatarPos).Magnitude
			if dist <= range and dist < closestDist then
				closest = { Id = mound.Id, Size = mound.Size, Position = mound.Position }
				closestDist = dist
			end
		end
	end

	local sharedMound = SharedMoundService.GetActiveMound()
	if sharedMound and sharedMound.IsActive and sharedMound.HP > 0 then
		local effectiveRange = range + (sharedMound.Scale.X * 0.5)
		local dist = (sharedMound.Position - avatarPos).Magnitude
		if dist <= effectiveRange and dist < closestDist then
			closest = { Id = sharedMound.Id, Size = "Shared", Position = sharedMound.Position }
			closestDist = dist
		end
	end

	return closest, closestDist
end

-- Process one player's equipped pet attacks in the single per-player loop cadence
function PetService.ProcessPlayerPetAttacks(
	player: Player,
	profile: Types.PlayerProfile,
	nowClock: number
)
	local userId = player.UserId
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	local avatarPos = rootPart.Position
	local equipped = profile.EquippedPets
	if not equipped or #equipped == 0 then
		return
	end

	local userNextAttacks = nextAttackTimeByUserId[userId]
	if not userNextAttacks then
		userNextAttacks = {}
		nextAttackTimeByUserId[userId] = userNextAttacks
	end

	for _, petGuid in equipped do
		local petData = profile.Pets[petGuid]
		if petData then
			local stats = PetService.GetEffectiveStats(petData.Species, petData.Variant, petData.Level)
			local nextTime = userNextAttacks[petGuid] or 0

			if nowClock >= nextTime then
				local targetMound, dist = findClosestMoundInRange(userId, avatarPos, stats.Range)
				if targetMound then
					-- Mound is in Range: attack!
					local ok, remainingHP, cleared = DigService.ApplyPetDamage(
						player,
						userId,
						targetMound.Id,
						stats.Power,
						petGuid
					)

					if ok then
						userNextAttacks[petGuid] = nowClock + stats.AttackInterval

						local dpsLog = dpsLogByUserId[userId]
						if not dpsLog then
							dpsLog = { TotalDamage = 0, TotalAttacks = 0, LastAttackAt = nowClock }
							dpsLogByUserId[userId] = dpsLog
						end
						dpsLog.TotalDamage += stats.Power
						dpsLog.TotalAttacks += 1
						dpsLog.LastAttackAt = nowClock

						print(
							string.format(
								"[PetService] PetAttack | UserId=%d | Pet=%s (%s %s) | Mound=%s (%s) | Dist=%.1f/%.1f | Dmg=%.1f | RemHP=%.1f | Interval=%.2fs",
								userId,
								petGuid,
								petData.Species,
								petData.Variant,
								targetMound.Id,
								targetMound.Size,
								dist,
								stats.Range,
								stats.Power,
								remainingHP,
								stats.AttackInterval
							)
						)
					end
				else
					-- No mound in range: do NOT attack (idle until mound is in range)
					-- Next check will happen next tick without consuming attack cooldown
				end
			end
		end
	end
end

-- Get DPS summary for testing & verification
function PetService.GetPlayerDpsSummary(userId: number): { TotalDamage: number, TotalAttacks: number, LastAttackAt: number }?
	return dpsLogByUserId[userId]
end

function PetService.Start()
	if started then
		return
	end
	started = true

	-- Register Remotes
	Remotes.OnServerInvoke("EquipPet", function(player: Player, petGuid: string): EquipPetResult
		local result: EquipPetResult = { Success = false, Reason = "Unknown" }
		local mutated = PlayerState.Mutate(player, function(profile: Types.PlayerProfile)
			result = PetService.EquipPetInProfile(profile, petGuid)
		end)
		if mutated and result.Success then
			DataService.SavePlayer(player)
			ShovelInventoryService.SendStateSync(player)
		end
		return result
	end)

	Remotes.OnServerInvoke("UnequipPet", function(player: Player, petGuid: string): UnequipPetResult
		local result: UnequipPetResult = { Success = false, Reason = "Unknown" }
		local mutated = PlayerState.Mutate(player, function(profile: Types.PlayerProfile)
			result = PetService.UnequipPetInProfile(profile, petGuid)
		end)
		if mutated and result.Success then
			DataService.SavePlayer(player)
			ShovelInventoryService.SendStateSync(player)
		end
		return result
	end)

	Remotes.OnServerInvoke("AssignPetToBase", function(player: Player, petGuid: string): AssignBasePetResult
		local result: AssignBasePetResult = { Success = false, Reason = "Unknown" }
		local mutated = PlayerState.Mutate(player, function(profile: Types.PlayerProfile)
			result = PetService.AssignBasePetInProfile(profile, petGuid)
		end)
		if mutated and result.Success then
			DataService.SavePlayer(player)
			ShovelInventoryService.SendStateSync(player)
		end
		return result
	end)

	Remotes.OnServerInvoke("RemovePetFromBase", function(player: Player, petGuid: string): RemoveBasePetResult
		local result: RemoveBasePetResult = { Success = false, Reason = "Unknown" }
		local mutated = PlayerState.Mutate(player, function(profile: Types.PlayerProfile)
			result = PetService.RemoveBasePetInProfile(profile, petGuid)
		end)
		if mutated and result.Success then
			DataService.SavePlayer(player)
			ShovelInventoryService.SendStateSync(player)
		end
		return result
	end)

	Remotes.OnServerInvoke("ReleasePet", function(player: Player, petGuid: string): ReleasePetResult
		local result: ReleasePetResult = { Success = false, Reason = "Unknown" }
		local mutated = PlayerState.Mutate(player, function(profile: Types.PlayerProfile)
			result = PetService.ReleasePetInProfile(profile, petGuid)
		end)
		if mutated and result.Success then
			DataService.SavePlayer(player)
			ShovelInventoryService.SendStateSync(player)
		end
		return result
	end)

	-- Clean up on player leaving
	Players.PlayerRemoving:Connect(function(player: Player)
		nextAttackTimeByUserId[player.UserId] = nil
		dpsLogByUserId[player.UserId] = nil
	end)

	-- Single authoritative per-player loop cadence (PRD: "satu loop per pemain, bukan per pet")
	-- We iterate all active players every 0.1s tick
	task.spawn(function()
		while true do
			task.wait(0.1)
			local nowClock = os.clock()
			for _, player in Players:GetPlayers() do
				local profile = PlayerState.Get(player)
				if profile then
					PetService.ProcessPlayerPetAttacks(player, profile, nowClock)
				end
			end
		end
	end)
end

return PetService
