--!strict
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Dialogue = require(script.Parent:WaitForChild("NpcDialogue"))
local Guard = require(script.Parent:WaitForChild("NpcInputGuard"))
local Notifications = require(script.Parent:WaitForChild("NotificationController"))
local Tracker = require(script.Parent:WaitForChild("QuestTrackerController"))
local player = Players.LocalPlayer
local Controller = {}
local started, busy = false, false
local generation = 0
local bound: {[Instance]: boolean} = setmetatable({}, {__mode = "k"}) :: any

local function near(target: BasePart): boolean
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local prompt = target:FindFirstChildWhichIsA("ProximityPrompt", true)
	return target.Parent ~= nil and root ~= nil and root:IsA("BasePart") and prompt ~= nil
		and (root.Position - target.Position).Magnitude <= prompt.MaxActivationDistance + 2
end

local function transact(remote: string, questId: string)
	if busy then return end
	busy = true
	local ok, result = pcall(function() return Remotes.GetFunction(remote):InvokeServer(questId) end)
	busy = false
	if ok and type(result) == "table" then
		Notifications.ShowAlert(result.Message or "Interaksi selesai.", if result.Success then nil else "Error")
	else
		Notifications.ShowAlert("Mayor belum bisa merespons. Coba lagi.", "Error")
	end
end

local function showOffer(target: BasePart, offer: any)
	local complete = offer.Progress >= offer.Target
	local choices: {any} = {}
	if not offer.Accepted then
		table.insert(choices, {Text = "Terima quest", Selected = function() transact("AcceptMayorQuest", offer.Id) end})
	elseif complete and not offer.Claimed then
		table.insert(choices, {Text = "Klaim hadiah", Selected = function() transact("ClaimMayorQuest", offer.Id) end})
	else
		table.insert(choices, {Text = "Lanjutkan petualangan", Selected = function() end})
	end
	table.insert(choices, {Text = "Kembali", Selected = function() Controller.OpenDialogue(target) end})
	local body = offer.Description .. string.format("\nHadiah: $%d", offer.RewardCoins)
	if offer.Accepted then body ..= string.format("  ·  Progres: %d/%d", offer.Progress, offer.Target) end
	Dialogue.Open(target, choices, "MayorDialogue", {Title = offer.DisplayName, Body = body})
end

function Controller.OpenDialogue(target: BasePart)
	if busy or Guard.IsPromptBlocked() or player:GetAttribute("DigMinigameActive") == true or not near(target) then return end
	generation += 1
	local token = generation
	busy = true
	local ok, result = pcall(function() return Remotes.GetFunction("GetMayorQuestState"):InvokeServer() end)
	busy = false
	local modal = player:GetAttribute("ActiveShopModal")
	if token ~= generation or not near(target) or (modal ~= nil and modal ~= "" and modal ~= "MayorDialogue") then return end
	if not ok or type(result) ~= "table" or not result.Success then
		Notifications.ShowAlert(if ok and type(result) == "table" then result.Message or "Quest belum tersedia." else "Mayor belum bisa merespons.", "Error")
		return
	end
	Tracker.ApplySnapshot({MayorQuests = result.MayorQuests})
	local choices: {any} = {}
	for _, offer in result.MayorQuests.List do
		if not offer.Claimed then
			table.insert(choices, {
				Text = (if not offer.Accepted then "Tawaran: " elseif offer.Progress >= offer.Target then "Selesai: " else "Progres: ") .. offer.DisplayName,
				Selected = function() showOffer(target, offer) end,
			})
		end
	end
	table.insert(choices, {Text = "Sampai jumpa", Selected = function() end})
	Dialogue.Open(target, choices, "MayorDialogue", {
		Title = "Mayor",
		Body = if #choices > 1 then "Ada tugas untuk membantu warga.\nPilih quest untuk melihat target dan hadiahnya." else "Semua tugas Mayor sudah selesai.\nTerima kasih sudah membantu warga!",
	})
end

function Controller.Start()
	if started then return end
	started = true
	local function isMayorPrompt(prompt: ProximityPrompt): boolean
		return prompt.Name == "MayorProximityPrompt"
	end
	ProximityPromptService.PromptShown:Connect(function(prompt)
		if isMayorPrompt(prompt) then Dialogue.ShowPrompt(prompt) end
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		if isMayorPrompt(prompt) then Dialogue.HidePrompt(prompt) end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who ~= player or not isMayorPrompt(prompt) then return end
		local attachment = prompt.Parent
		local head = if attachment and attachment:IsA("Attachment") then attachment.Parent else attachment
		if head and head:IsA("BasePart") then Controller.OpenDialogue(head) end
	end)
	local function bind(item: Instance)
		if item:IsA("ClickDetector") and item.Name == "MayorTalkClick" and not bound[item] then
			bound[item] = true
			item.MouseClick:Connect(function(who)
				local head = item.Parent
				if who == player and head and head:IsA("BasePart") then Controller.OpenDialogue(head) end
			end)
		end
	end
	workspace.DescendantAdded:Connect(bind)
	for _, item in workspace:GetDescendants() do bind(item) end
end

return Controller
