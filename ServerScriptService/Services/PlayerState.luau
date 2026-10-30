--!strict
-- Authoritative player state accessor, mutator, change signals, and attribute replication (Step 1)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))
local Economy = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))
local Base = require(Shared:WaitForChild("Config"):WaitForChild("Base"))

local DataService = require(script.Parent:WaitForChild("DataService"))

export type StateChangedCallback = (player: Player, profile: Types.PlayerProfile) -> ()

local PlayerState = {}

local listeners: { StateChangedCallback } = {}
local started = false

local function computeBagItemCount(items: { [string]: number }): number
	local total = 0
	for _, count in items do
		if count > 0 then
			total += count
		end
	end
	return total
end

function PlayerState.SyncAttributes(player: Player, profile: Types.PlayerProfile)
	local bagLevelInfo = Economy.BagLevels[profile.BagLevel] or Economy.BagLevels[1]
	local bagCapacity = bagLevelInfo.Capacity
	local bagItemCount = computeBagItemCount(profile.Items)
	local eggCapacity = Base.BaseEggBagCapacity + profile.BaseLevel

	player:SetAttribute("Coins", profile.Coins)
	player:SetAttribute("TotalCoinsEarned", profile.TotalCoinsEarned)
	player:SetAttribute("BagItemCount", bagItemCount)
	player:SetAttribute("BagCapacity", bagCapacity)
	player:SetAttribute("BagLevel", profile.BagLevel)
	player:SetAttribute("BaseLevel", profile.BaseLevel)
	player:SetAttribute("EggCount", #profile.EggBag)
	player:SetAttribute("EggCapacity", eggCapacity)
	player:SetAttribute("EquippedShovel", profile.Shovels.Equipped)
	player:SetAttribute("SandyGateUnlocked", profile.SandyGateUnlocked == true)
	if profile.Tutorial then
		player:SetAttribute("TutorialStep", profile.Tutorial.Step or 1)
		player:SetAttribute("TutorialDone", profile.Tutorial.Done == true)
	end

	-- Replicate public summaries of equipped and base pets for other players to see
	local publicEquipped = {}
	if type(profile.EquippedPets) == "table" and type(profile.Pets) == "table" then
		for _, guid in ipairs(profile.EquippedPets) do
			local p = profile.Pets[guid]
			if p then
				table.insert(publicEquipped, {
					Guid = guid,
					Species = p.Species,
					Variant = p.Variant or "Normal",
					Level = p.Level or 1,
				})
			end
		end
	end
	player:SetAttribute("PublicEquippedPets", HttpService:JSONEncode(publicEquipped))

	local publicBase = {}
	if type(profile.BasePets) == "table" and type(profile.Pets) == "table" then
		for _, guid in ipairs(profile.BasePets) do
			local p = profile.Pets[guid]
			if p then
				table.insert(publicBase, {
					Guid = guid,
					Species = p.Species,
					Variant = p.Variant or "Normal",
					Level = p.Level or 1,
				})
			end
		end
	end
	player:SetAttribute("PublicBasePets", HttpService:JSONEncode(publicBase))
end

local function notifyListeners(player: Player, profile: Types.PlayerProfile)
	PlayerState.SyncAttributes(player, profile)
	for _, listener in listeners do
		task.spawn(listener, player, profile)
	end
end

function PlayerState.Get(player: Player): Types.PlayerProfile?
	return DataService.GetProfile(player)
end

function PlayerState.Mutate(player: Player, fn: (profile: Types.PlayerProfile) -> ()): boolean
	local profile = DataService.GetProfile(player)
	if not profile then
		return false
	end

	local ok, err = pcall(fn, profile)
	if not ok then
		warn(string.format("[PlayerState] Error in Mutate for %s: %s", player.Name, tostring(err)))
		return false
	end

	-- Clamp Coins so they can never be negative
	if profile.Coins < 0 then
		profile.Coins = 0
	end

	notifyListeners(player, profile)
	return true
end

function PlayerState.OnChanged(callback: StateChangedCallback): () -> ()
	table.insert(listeners, callback)
	return function()
		local index = table.find(listeners, callback)
		if index then
			table.remove(listeners, index)
		end
	end
end

function PlayerState.IsAuthorizedForDebug(player: Player): boolean
	return RunService:IsStudio() or Economy.OwnerUserIds[player.UserId] == true
end

function PlayerState.DebugAddCoins(player: Player, delta: number): boolean
	if not PlayerState.IsAuthorizedForDebug(player) then
		warn(string.format("[PlayerState] Unauthorized debug coin attempt by %s (%d)", player.Name, player.UserId))
		return false
	end

	local mutated = PlayerState.Mutate(player, function(profile: Types.PlayerProfile)
		local nextCoins = math.max(0, math.floor(profile.Coins + delta))
		local gained = math.max(0, nextCoins - profile.Coins)
		profile.Coins = nextCoins
		profile.TotalCoinsEarned += gained
	end)
	if mutated then
		DataService.SavePlayer(player)
	end
	return mutated
end

function PlayerState.DebugSetCoins(player: Player, amount: number): boolean
	if not PlayerState.IsAuthorizedForDebug(player) then
		warn(string.format("[PlayerState] Unauthorized debug coin attempt by %s (%d)", player.Name, player.UserId))
		return false
	end

	local mutated = PlayerState.Mutate(player, function(profile: Types.PlayerProfile)
		profile.Coins = math.max(0, math.floor(amount))
	end)
	if mutated then
		DataService.SavePlayer(player)
	end
	return mutated
end

local function handleDebugCommandText(player: Player, rawText: string)
	if not PlayerState.IsAuthorizedForDebug(player) then
		return
	end
	local trimmed = string.gsub(rawText, "^%s*(.-)%s*$", "%1")
	local parts = string.split(trimmed, " ")
	local cmd = string.lower(parts[1] or "")
	local argNum = tonumber(parts[2])

	if cmd == "/addcoins" and argNum ~= nil then
		PlayerState.DebugAddCoins(player, argNum)
		local current = PlayerState.Get(player)
		print(
			string.format(
				"[PlayerState] Debug /addcoins %d -> %s now has %d Coins",
				argNum,
				player.Name,
				if current then current.Coins else -1
			)
		)
	elseif cmd == "/setcoins" and argNum ~= nil then
		PlayerState.DebugSetCoins(player, argNum)
		local current = PlayerState.Get(player)
		print(
			string.format(
				"[PlayerState] Debug /setcoins %d -> %s now has %d Coins",
				argNum,
				player.Name,
				if current then current.Coins else -1
			)
		)
	end
end

local function setupTextChatCommands()
	local function ensureCommand(name: string, alias: string)
		local existing = TextChatService:FindFirstChild(name)
		if existing and existing:IsA("TextChatCommand") then
			return
		end
		local cmd = Instance.new("TextChatCommand")
		cmd.Name = name
		cmd.PrimaryAlias = alias
		cmd.Parent = TextChatService
		cmd.Triggered:Connect(function(textSource: TextSource, unfilteredText: string)
			local player = Players:GetPlayerByUserId(textSource.UserId)
			if player then
				handleDebugCommandText(player, unfilteredText)
			end
		end)
	end

	ensureCommand("DebugAddCoinsCommand", "/addcoins")
	ensureCommand("DebugSetCoinsCommand", "/setcoins")
end

function PlayerState.Start()
	if started then
		return
	end
	started = true

	setupTextChatCommands()

	DataService.OnProfileLoaded(function(player: Player, profile: Types.PlayerProfile)
		PlayerState.SyncAttributes(player, profile)
		print(
			string.format(
				"[PlayerState] Loaded profile for %s (%d) | Coins=%d | Bag=%d/%d | Shovel=%s",
				player.Name,
				player.UserId,
				profile.Coins,
				player:GetAttribute("BagItemCount") :: number,
				player:GetAttribute("BagCapacity") :: number,
				profile.Shovels.Equipped
			)
		)
		for _, listener in listeners do
			task.spawn(listener, player, profile)
		end
	end)
end

return PlayerState
