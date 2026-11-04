--!strict
-- Server-authoritative, persistent, opt-in Mayor quests; daily quests remain independent.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"):WaitForChild("MayorQuests"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local Inventory = require(script.Parent:WaitForChild("ShovelInventoryService"))
local Service = {}
local started = false
local snapshot: any = nil
local tuningCache: {[string]: {Target: number, RewardCoins: number}} = {}
local busy: {[Player]: boolean} = {}
local definitions: {[string]: any} = {}
for _, definition in Config.Pool do definitions[definition.Id] = definition end

local function state(profile: any): any
	if type(profile.MayorQuests) ~= "table" then profile.MayorQuests = {Entries = {}} end
	if type(profile.MayorQuests.Entries) ~= "table" then profile.MayorQuests.Entries = {} end
	return profile.MayorQuests.Entries
end

local function tuning(definition: any): (number, number)
	local cached = tuningCache[definition.Id]
	if cached then return cached.Target, cached.RewardCoins end
	local target, reward = definition.Target, definition.RewardCoins
	if snapshot then
		local ok, value = pcall(function() return snapshot:GetValue(definition.TargetConfigKey) end)
		if ok and type(value) == "number" and value == value and value >= 1 and value <= 10000 then target = math.floor(value) end
		ok, value = pcall(function() return snapshot:GetValue(definition.RewardConfigKey) end)
		if ok and type(value) == "number" and value == value and value >= 0 and value <= 100000 then reward = math.floor(value) end
	end
	tuningCache[definition.Id] = {Target = target, RewardCoins = reward}
	return target, reward
end

function Service.GetMayorAnchor(): BasePart?
	local plain = workspace:FindFirstChild("Plain")
	local house = plain and plain:FindFirstChild("MayorHouse")
	local mayor = house and house:FindFirstChild("Mayor")
	local head = mayor and mayor:FindFirstChild("Head")
	return if head and head:IsA("BasePart") then head else nil
end

function Service.IsNearMayor(player: Player): boolean
	local head = Service.GetMayorAnchor()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local prompt = head and head:FindFirstChildWhichIsA("ProximityPrompt", true)
	return head ~= nil and prompt ~= nil and root ~= nil and root:IsA("BasePart")
		and humanoid ~= nil and humanoid.Health > 0
		and (root.Position - head.Position).Magnitude <= prompt.MaxActivationDistance + 2
end

function Service.BuildSnapshot(profile: any): any
	local entries = if type(profile.MayorQuests) == "table" and type(profile.MayorQuests.Entries) == "table" then profile.MayorQuests.Entries else {}
	local list = {}
	for _, definition in Config.Pool do
		local entry = entries[definition.Id]
		local target, reward = tuning(definition)
		if type(entry) == "table" then target, reward = entry.Target, entry.RewardCoins end
		table.insert(list, {
			Id = definition.Id, DisplayName = definition.DisplayName,
			Description = string.format(definition.DescriptionFormat, target),
			Target = target, RewardCoins = reward,
			Progress = if type(entry) == "table" then math.clamp(tonumber(entry.Progress) or 0, 0, target) else 0,
			Accepted = type(entry) == "table", Claimed = type(entry) == "table" and entry.Claimed == true,
		})
	end
	return {List = list}
end

function Service.AcceptForProfile(profile: any, questId: string): any
	local definition = definitions[questId]
	if not definition then return {Success = false, Reason = "UnknownQuest", Message = "Quest tidak ditemukan."} end
	local entries = state(profile)
	if entries[questId] then return {Success = false, Reason = "AlreadyAccepted", Message = "Quest ini sudah diterima."} end
	local target, reward = tuning(definition)
	-- Freeze target and reward at acceptance; live tuning never moves an active goal.
	entries[questId] = {Id = questId, Progress = 0, Target = target, RewardCoins = reward, Claimed = false}
	return {Success = true, Message = "Quest Mayor diterima! Lihat progres di Side Quest."}
end

function Service.RecordProgressForProfile(profile: any, eventType: string, amount: number?): boolean
	local value = amount or 1
	if value ~= value or value <= 0 or value == math.huge then return false end
	local changed = false
	for questId, entry in state(profile) do
		local definition = definitions[questId]
		if definition and definition.EventType == eventType and not entry.Claimed then
			local previous = entry.Progress
			entry.Progress = math.clamp(previous + value, 0, entry.Target)
			changed = changed or entry.Progress ~= previous
		end
	end
	return changed
end

function Service.RecordProgress(player: Player, eventType: string, amount: number?): boolean
	local changed = false
	PlayerState.Mutate(player, function(profile: any) changed = Service.RecordProgressForProfile(profile, eventType, amount) end)
	return changed
end

function Service.ClaimForProfile(profile: any, questId: string): any
	local entry = state(profile)[questId]
	if not definitions[questId] or not entry then return {Success = false, Reason = "NotAccepted", Message = "Terima quest dari Mayor dahulu."} end
	if entry.Claimed then return {Success = false, Reason = "AlreadyClaimed", Message = "Hadiah sudah diklaim."} end
	if entry.Progress < entry.Target then return {Success = false, Reason = "Incomplete", Message = "Quest belum selesai."} end
	entry.Claimed = true
	profile.Coins = (profile.Coins or 0) + entry.RewardCoins
	profile.TotalCoinsEarned = (profile.TotalCoinsEarned or 0) + entry.RewardCoins
	require(script.Parent:WaitForChild("LeaderboardService")).RecordCoinsEarned(profile, entry.RewardCoins)
	return {Success = true, RewardCoins = entry.RewardCoins, Message = string.format("Quest Mayor selesai! +$%d", entry.RewardCoins)}
end

local function action(player: Player, questId: string, accept: boolean): any
	if not Service.IsNearMayor(player) then return {Success = false, Reason = "TooFar", Message = "Temui Mayor untuk menerima quest atau mengambil hadiah."} end
	if busy[player] then return {Success = false, Reason = "Busy", Message = "Tunggu interaksi sebelumnya selesai."} end
	busy[player] = true
	local ok, result = xpcall(function()
		local result = {Success = false, Reason = "ProfileNotReady", Message = "Profil belum siap."}
		local mutated = PlayerState.Mutate(player, function(profile: any)
			result = if accept then Service.AcceptForProfile(profile, questId) else Service.ClaimForProfile(profile, questId)
		end)
		if mutated and result.Success then
			Inventory.SendStateSync(player)
			DataService.SavePlayer(player)
		end
		return result
	end, debug.traceback)
	busy[player] = nil
	if not ok then warn("[MayorQuestService] " .. tostring(result)); return {Success = false, Reason = "InternalError", Message = "Interaksi gagal. Coba lagi."} end
	return result
end

function Service.Start()
	if started then return end
	started = true
	local head = Service.GetMayorAnchor()
	if head then
		local prompt = head:FindFirstChildWhichIsA("ProximityPrompt", true)
		if prompt then
			prompt.Style = Enum.ProximityPromptStyle.Custom
			prompt.ActionText, prompt.ObjectText = "Bicara", "Mayor"
			local click = head:FindFirstChild("MayorTalkClick")
			if not click then click = Instance.new("ClickDetector"); click.Name = "MayorTalkClick"; click.Parent = head end
			if click:IsA("ClickDetector") then click.MaxActivationDistance = prompt.MaxActivationDistance end
		end
	end
	Remotes.OnServerInvoke("GetMayorQuestState", function(player: Player)
		if not Service.IsNearMayor(player) then return {Success = false, Reason = "TooFar", Message = "Kamu terlalu jauh dari Mayor."} end
		local profile = PlayerState.Get(player)
		if not profile then return {Success = false, Message = "Profil belum siap."} end
		return {Success = true, MayorQuests = Service.BuildSnapshot(profile)}
	end)
	Remotes.OnServerInvoke("AcceptMayorQuest", function(player: Player, questId: string) return action(player, questId, true) end)
	Remotes.OnServerInvoke("ClaimMayorQuest", function(player: Player, questId: string) return action(player, questId, false) end)
	DataService.OnProfileLoaded(function(player: Player, profile: any)
		state(profile)
		Inventory.SendStateSync(player)
	end)
	Players.PlayerRemoving:Connect(function(player) busy[player] = nil end)
	task.spawn(function()
		local ok, config = pcall(function() return game:GetService("ConfigService"):GetConfigAsync() end)
		if not ok then warn("[MayorQuestService] Live configs unavailable; using quest defaults."); return end
		snapshot = config
		table.clear(tuningCache)
		config.UpdateAvailable:Connect(function()
			local refreshed = pcall(function() config:Refresh() end)
			if refreshed then table.clear(tuningCache) end
		end)
	end)
end

return Service
