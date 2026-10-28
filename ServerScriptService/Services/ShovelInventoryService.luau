--!strict
-- Authoritative shovel ownership, equip validation, physical 3D Tool sync, respawn restoration, and StateSync broadcaster

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local EconomyConfig = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))
local ShovelsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Shovels"))
local ShovelModelBuilder = require(Shared:WaitForChild("ShovelModelBuilder"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local PlayerState = require(script.Parent:WaitForChild("PlayerState"))

export type EquipResult = {
	Success: boolean,
	Reason: string?,
	Message: string?,
	Equipped: string?,
	Owned: { string }?,
}

export type InventorySnapshot = {
	Loaded: boolean,
	OwnedShovels: { string },
	EquippedShovel: string,
	ToolActive: boolean,
	Coins: number,
	BagLevel: number,
	BaseLevel: number,
	Items: { [string]: number },
	EggBag: { Types.EggBagEntry },
	Incubators: { [number]: Types.IncubatorEntry },
	Pets: { [string]: Types.PetInstance },
	EquippedPets: { string },
	BasePets: { string },
	Index: { Pets: { [string]: boolean }, Items: { [string]: boolean } }?,
	Quests: { Day: number, List: { Types.QuestEntry } }?,
	Streak: { Day: number, LastClaim: number }?,
	Title: string?,
}

local ShovelInventoryService = {}

local toolDesiredActiveByUserId: { [number]: boolean } = {}
local swingBusyByUserId: { [number]: boolean } = {}
local started = false

local DEFAULT_GRIP = CFrame.new(0, 0.35, 0) * CFrame.Angles(math.rad(-75), 0, 0)
local SWING_GRIP = CFrame.new(0, 0.25, -0.25) * CFrame.Angles(math.rad(-130), 0, 0)

function ShovelInventoryService.SanitizeProfileShovels(profile: Types.PlayerProfile): boolean
	local changed = false
	if type(profile.Shovels) ~= "table" then
		profile.Shovels = {
			Owned = { EconomyConfig.StartingShovel },
			Equipped = EconomyConfig.StartingShovel,
		}
		return true
	end

	if type(profile.Shovels.Owned) ~= "table" then
		profile.Shovels.Owned = { EconomyConfig.StartingShovel }
		changed = true
	end

	local seen: { [string]: boolean } = {}
	local cleaned: { string } = {}
	for _, id in profile.Shovels.Owned do
		if type(id) == "string" and ShovelsConfig.All[id] ~= nil and not seen[id] then
			seen[id] = true
			table.insert(cleaned, id)
		else
			changed = true
		end
	end

	if not seen[EconomyConfig.StartingShovel] then
		table.insert(cleaned, 1, EconomyConfig.StartingShovel)
		seen[EconomyConfig.StartingShovel] = true
		changed = true
	end

	-- Keep deterministic order matching ShovelsConfig.AllOrder
	table.sort(cleaned, function(a: string, b: string): boolean
		local idxA = table.find(ShovelsConfig.AllOrder, a) or 999
		local idxB = table.find(ShovelsConfig.AllOrder, b) or 999
		return idxA < idxB
	end)

	profile.Shovels.Owned = cleaned

	local eq = profile.Shovels.Equipped
	if type(eq) ~= "string" or not seen[eq] then
		profile.Shovels.Equipped = EconomyConfig.StartingShovel
		changed = true
	end

	return changed
end

function ShovelInventoryService.EquipShovelInProfile(profile: Types.PlayerProfile, shovelId: string): EquipResult
	ShovelInventoryService.SanitizeProfileShovels(profile)

	if type(shovelId) ~= "string" or ShovelsConfig.All[shovelId] == nil then
		return {
			Success = false,
			Reason = "InvalidShovel",
			Message = "Shovel tidak valid.",
			Equipped = profile.Shovels.Equipped,
			Owned = table.clone(profile.Shovels.Owned),
		}
	end

	if table.find(profile.Shovels.Owned, shovelId) == nil then
		return {
			Success = false,
			Reason = "NotOwned",
			Message = "Kamu belum memiliki shovel ini.",
			Equipped = profile.Shovels.Equipped,
			Owned = table.clone(profile.Shovels.Owned),
		}
	end

	profile.Shovels.Equipped = shovelId
	return {
		Success = true,
		Equipped = shovelId,
		Owned = table.clone(profile.Shovels.Owned),
	}
end

local function findCharacterShovelTool(player: Player): Tool?
	local character = player.Character
	if character then
		for _, child in character:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("DigPalsShovelTool") == true then
				return child
			end
		end
	end
	return nil
end

local function findBackpackShovelTool(player: Player): Tool?
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, child in backpack:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("DigPalsShovelTool") == true then
				return child
			end
		end
	end
	return nil
end

local function destroyAllShovelTools(player: Player)
	local character = player.Character
	if character then
		for _, child in character:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("DigPalsShovelTool") == true then
				child:Destroy()
			end
		end
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, child in backpack:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("DigPalsShovelTool") == true then
				child:Destroy()
			end
		end
	end
end

function ShovelInventoryService.BuildSnapshot(player: Player, profile: Types.PlayerProfile): InventorySnapshot
	local held = findCharacterShovelTool(player) ~= nil
	local itemsCopy: { [string]: number } = {}
	for k, v in profile.Items do
		itemsCopy[k] = v
	end
	local eggsCopy: { Types.EggBagEntry } = {}
	for _, entry in profile.EggBag do
		if type(entry) == "table" and type(entry.Id) == "string" then
			table.insert(eggsCopy, {
				Id = entry.Id,
				Rarity = entry.Rarity,
			})
		end
	end
	local incubatorsCopy: { [number]: Types.IncubatorEntry } = {}
	if type(profile.Incubators) == "table" then
		for slotIdx, entry in profile.Incubators do
			if type(slotIdx) == "number" and type(entry) == "table" and type(entry.Id) == "string" then
				incubatorsCopy[slotIdx] = {
					Id = entry.Id,
					Rarity = entry.Rarity,
					ReadyAt = entry.ReadyAt,
				}
			end
		end
	end
	local petsCopy: { [string]: Types.PetInstance } = {}
	if type(profile.Pets) == "table" then
		for petId, pInst in profile.Pets do
			if type(petId) == "string" and type(pInst) == "table" and type(pInst.Species) == "string" then
				petsCopy[petId] = {
					Species = pInst.Species,
					Variant = pInst.Variant,
					Level = pInst.Level,
				}
			end
		end
	end
	local equippedPetsCopy: { string } = {}
	if type(profile.EquippedPets) == "table" then
		for _, guid in profile.EquippedPets do
			if type(guid) == "string" and profile.Pets[guid] ~= nil then
				table.insert(equippedPetsCopy, guid)
			end
		end
	end
	local basePetsCopy: { string } = {}
	if type(profile.BasePets) == "table" then
		for _, guid in profile.BasePets do
			if type(guid) == "string" and profile.Pets[guid] ~= nil then
				table.insert(basePetsCopy, guid)
			end
		end
	end
	return {
		Loaded = true,
		OwnedShovels = table.clone(profile.Shovels.Owned),
		EquippedShovel = profile.Shovels.Equipped,
		ToolActive = held,
		Coins = profile.Coins,
		TotalCoinsEarned = profile.TotalCoinsEarned or 0,
		BagLevel = profile.BagLevel,
		BaseLevel = profile.BaseLevel,
		Items = itemsCopy,
		EggBag = eggsCopy,
		Incubators = incubatorsCopy,
		Pets = petsCopy,
		EquippedPets = equippedPetsCopy,
		BasePets = basePetsCopy,
		Index = {
			Pets = if profile.Index and profile.Index.Pets then table.clone(profile.Index.Pets) else {},
			Items = if profile.Index and profile.Index.Items then table.clone(profile.Index.Items) else {},
		},
		Quests = {
			Day = if profile.Quests then (profile.Quests.Day or 0) else 0,
			List = if profile.Quests and profile.Quests.List then table.clone(profile.Quests.List) else {},
		},
		Streak = {
			Day = if profile.Streak then (profile.Streak.Day or 0) else 0,
			LastClaim = if profile.Streak then (profile.Streak.LastClaim or 0) else 0,
		},
		Tutorial = {
			Step = if profile.Tutorial then (profile.Tutorial.Step or 1) else 1,
			Done = if profile.Tutorial then (profile.Tutorial.Done == true) else false,
		},
		SandyGateUnlocked = profile.SandyGateUnlocked == true,
		Title = player:GetAttribute("Title") :: string?,
	}
end

function ShovelInventoryService.SendStateSync(player: Player)
	if player.Parent ~= Players then
		return
	end
	local profile = PlayerState.Get(player)
	if not profile then
		return
	end
	local held = findCharacterShovelTool(player) ~= nil
	player:SetAttribute("ShovelToolActive", held)
	Remotes.GetEvent("StateSync"):FireClient(player, ShovelInventoryService.BuildSnapshot(player, profile))
end

function ShovelInventoryService.SyncCharacterTool(player: Player)
	if player.Parent ~= Players then
		return
	end
	local profile = PlayerState.Get(player)
	if not profile then
		return
	end
	ShovelInventoryService.SanitizeProfileShovels(profile)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not character or not humanoid or humanoid.Health <= 0 or not backpack then
		return
	end

	local targetShovelId = profile.Shovels.Equipped
	local wantActive = toolDesiredActiveByUserId[player.UserId]
	if wantActive == nil then
		wantActive = true
		toolDesiredActiveByUserId[player.UserId] = true
	end

	local heldTool = findCharacterShovelTool(player)
	local packTool = findBackpackShovelTool(player)
	local existingTool = heldTool or packTool

	if existingTool and existingTool:GetAttribute("ShovelId") ~= targetShovelId then
		destroyAllShovelTools(player)
		existingTool = nil
		heldTool = nil
		packTool = nil
	end

	if not existingTool then
		local created = ShovelModelBuilder.CloneGameplayTool(targetShovelId)
		created.Equipped:Connect(function()
			player:SetAttribute("ShovelToolActive", true)
		end)
		created.Unequipped:Connect(function()
			task.defer(function()
				if player.Parent == Players then
					player:SetAttribute("ShovelToolActive", findCharacterShovelTool(player) ~= nil)
				end
			end)
		end)
		created.Parent = backpack
		existingTool = created
	end

	if wantActive then
		if existingTool.Parent ~= character then
			pcall(function()
				humanoid:EquipTool(existingTool)
			end)
		end
	else
		if existingTool.Parent == character then
			pcall(function()
				humanoid:UnequipTools()
			end)
		end
	end

	player:SetAttribute("ShovelToolActive", findCharacterShovelTool(player) ~= nil)
end

function ShovelInventoryService.IsShovelHeld(player: Player?): boolean
	if not player or player.Parent ~= Players then
		return false
	end
	return findCharacterShovelTool(player) ~= nil
end

function ShovelInventoryService.SetToolActive(player: Player, active: boolean)
	toolDesiredActiveByUserId[player.UserId] = active
	ShovelInventoryService.SyncCharacterTool(player)
	ShovelInventoryService.SendStateSync(player)
end

function ShovelInventoryService.EnsureShovelHeldForDig(player: Player?)
	if not player or player.Parent ~= Players then
		return
	end
	if not findCharacterShovelTool(player) then
		ShovelInventoryService.SetToolActive(player, true)
	end
end

function ShovelInventoryService.PlayStrikeSwing(player: Player?)
	if not player or player.Parent ~= Players then
		return
	end
	local userId = player.UserId
	if swingBusyByUserId[userId] then
		return
	end
	local tool = findCharacterShovelTool(player)
	if not tool then
		return
	end
	swingBusyByUserId[userId] = true
	TweenService:Create(tool, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Grip = SWING_GRIP,
	}):Play()
	task.delay(0.11, function()
		if tool and tool.Parent then
			TweenService:Create(tool, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Grip = DEFAULT_GRIP,
			}):Play()
		end
		swingBusyByUserId[userId] = nil
	end)
end

function ShovelInventoryService.EquipShovel(player: Player, shovelId: string): EquipResult
	local profile = PlayerState.Get(player)
	if not profile then
		return {
			Success = false,
			Reason = "ProfileNotLoaded",
			Message = "Data pemain sedang dimuat, coba sesaat lagi.",
		}
	end

	local result: EquipResult = {
		Success = false,
		Reason = "Unknown",
	}

	local mutated = PlayerState.Mutate(player, function(prof: Types.PlayerProfile)
		result = ShovelInventoryService.EquipShovelInProfile(prof, shovelId)
	end)

	if not mutated then
		return {
			Success = false,
			Reason = "MutateFailed",
			Message = "Gagal memperbarui shovel aktif.",
		}
	end

	if result.Success then
		toolDesiredActiveByUserId[player.UserId] = true
		ShovelInventoryService.SyncCharacterTool(player)
		ShovelInventoryService.SendStateSync(player)
		DataService.SavePlayer(player)
	end

	return result
end

function ShovelInventoryService.GrantShovel(player: Player, shovelId: string, autoEquip: boolean?): boolean
	if ShovelsConfig.All[shovelId] == nil then
		return false
	end
	local profile = PlayerState.Get(player)
	if not profile then
		return false
	end

	local ok = PlayerState.Mutate(player, function(prof: Types.PlayerProfile)
		ShovelInventoryService.SanitizeProfileShovels(prof)
		if table.find(prof.Shovels.Owned, shovelId) == nil then
			table.insert(prof.Shovels.Owned, shovelId)
			ShovelInventoryService.SanitizeProfileShovels(prof)
		end
		if autoEquip then
			prof.Shovels.Equipped = shovelId
		end
	end)

	if ok then
		if autoEquip then
			toolDesiredActiveByUserId[player.UserId] = true
		end
		ShovelInventoryService.SyncCharacterTool(player)
		ShovelInventoryService.SendStateSync(player)
		DataService.SavePlayer(player)
	end
	return ok
end

local function setupDebugShovelCommand()
	local existing = TextChatService:FindFirstChild("DebugGiveShovelCommand")
	if existing and existing:IsA("TextChatCommand") then
		return
	end
	local cmd = Instance.new("TextChatCommand")
	cmd.Name = "DebugGiveShovelCommand"
	cmd.PrimaryAlias = "/giveshovel"
	cmd.Parent = TextChatService
	cmd.Triggered:Connect(function(textSource: TextSource, unfilteredText: string)
		local player = Players:GetPlayerByUserId(textSource.UserId)
		if not player or not PlayerState.IsAuthorizedForDebug(player) then
			return
		end
		local trimmed = string.gsub(unfilteredText, "^%s*(.-)%s*$", "%1")
		local parts = string.split(trimmed, " ")
		local arg = parts[2] or ""
		if string.lower(arg) == "all" then
			for _, id in ShovelsConfig.AllOrder do
				ShovelInventoryService.GrantShovel(player, id, false)
			end
			print(string.format("[ShovelInventoryService] Granted ALL 7 shovels to %s", player.Name))
		elseif ShovelsConfig.All[arg] ~= nil then
			ShovelInventoryService.GrantShovel(player, arg, false)
			print(string.format("[ShovelInventoryService] Granted %s to %s", arg, player.Name))
		end
	end)
end

local function bindPlayerCharacter(player: Player)
	if toolDesiredActiveByUserId[player.UserId] == nil then
		toolDesiredActiveByUserId[player.UserId] = true
	end

	local function onCharacterAdded(character: Model)
		task.spawn(function()
			local humanoid = character:WaitForChild("Humanoid", 10)
			if not humanoid or player.Parent ~= Players then
				return
			end
			-- Wait until profile is loaded before restoring active shovel Tool
			local startWait = os.clock()
			while player.Parent == Players and not PlayerState.Get(player) and (os.clock() - startWait) < 10 do
				task.wait(0.1)
			end
			if player.Parent == Players and player.Character == character then
				task.wait(0.05)
				ShovelInventoryService.SyncCharacterTool(player)
				ShovelInventoryService.SendStateSync(player)
			end
		end)
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

function ShovelInventoryService.Start()
	if started then
		return
	end
	started = true

	ShovelModelBuilder.EnsureAssets()
	setupDebugShovelCommand()

	DataService.OnProfileLoaded(function(player: Player, profile: Types.PlayerProfile)
		local changed = ShovelInventoryService.SanitizeProfileShovels(profile)
		if changed then
			PlayerState.SyncAttributes(player, profile)
		end
		ShovelInventoryService.SyncCharacterTool(player)
		ShovelInventoryService.SendStateSync(player)
	end)

	PlayerState.OnChanged(function(player: Player, _profile: Types.PlayerProfile)
		ShovelInventoryService.SendStateSync(player)
	end)

	Players.PlayerAdded:Connect(bindPlayerCharacter)
	for _, player in Players:GetPlayers() do
		bindPlayerCharacter(player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		toolDesiredActiveByUserId[player.UserId] = nil
		swingBusyByUserId[player.UserId] = nil
	end)

	Remotes.OnServerInvoke("GetInventoryState", function(player: Player): any
		local startWait = os.clock()
		while player.Parent == Players and not PlayerState.Get(player) and (os.clock() - startWait) < 10 do
			task.wait(0.1)
		end
		local profile = PlayerState.Get(player)
		if not profile then
			return {
				Loaded = false,
				OwnedShovels = { EconomyConfig.StartingShovel },
				EquippedShovel = EconomyConfig.StartingShovel,
				ToolActive = false,
				Coins = 0,
				BagLevel = 1,
				BaseLevel = 1,
				Items = {},
				EggBag = {},
				Incubators = {},
				Pets = {},
				EquippedPets = {},
				BasePets = {},
			}
		end
		return ShovelInventoryService.BuildSnapshot(player, profile)
	end)

	Remotes.OnServerInvoke("EquipShovel", function(player: Player, shovelId: string): EquipResult
		return ShovelInventoryService.EquipShovel(player, shovelId)
	end)

	Remotes.OnServerEvent("SetShovelToolActive", function(player: Player, active: boolean)
		ShovelInventoryService.SetToolActive(player, active)
	end)
end

return ShovelInventoryService
