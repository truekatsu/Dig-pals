--!strict
-- Main tutorial objectives and daily side quests, in a compact scrollable HUD.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local Config = require(Shared:WaitForChild("Config"):WaitForChild("Quests"))
local Tutorial = require(script.Parent:WaitForChild("TutorialController"))
local SuperWaffles = require(Shared:WaitForChild("Util"):WaitForChild("QuestTitleFont"))
local Tracker = {}
local started, received = false, false
local signature = ""
local gui: ScreenGui? = nil
local panel: Frame? = nil
local scroll: ScrollingFrame? = nil
local entries: {any} = {}
local mayorEntries: {any} = {}
local mayorSignature = ""
local contentHeight, elementCount = 0, 0
local mainStep, mainDone, mainKnown = 1, false, false
local definitions: {[string]: any} = {}
local ROW_HEIGHT, SECTION_HEIGHT, GAP = 42, 14, 3
local MAIN_COLOR = Color3.fromRGB(255, 210, 119)
local SIDE_COLOR = Color3.fromRGB(113, 229, 161)
local _, _, MAIN_COUNT = Tutorial.GetQuestObjective(1)
for _, definition in Config.Pool do definitions[definition.Id] = definition end

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function label(parent: Instance, name: string, text: string, size: number, bold: boolean): TextLabel
	local item = Instance.new("TextLabel")
	item.Name = name
	item.BackgroundTransparency = 1
	item.Text = text
	item.Font = if bold then Enum.Font.BuilderSansBold else Enum.Font.BuilderSansMedium
	item.TextSize = size
	item.TextColor3 = Color3.fromRGB(248, 248, 242)
	item.TextStrokeTransparency = 0.38
	item.TextStrokeColor3 = Color3.fromRGB(15, 19, 25)
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextTruncate = Enum.TextTruncate.AtEnd
	item.Parent = parent
	return item
end

local function place(item: GuiObject, height: number)
	elementCount += 1
	contentHeight += height + (if elementCount > 1 then GAP else 0)
	item.LayoutOrder = elementCount
	item.Size = UDim2.new(1, -6, 0, height)
	item.Parent = scroll
end

local function openDetails()
	require(script.Parent:WaitForChild("QuestStreakController")).OpenQuests()
end

local function updateVisibility()
	if not panel then return end
	local modal = player:GetAttribute("ActiveShopModal")
	panel.Visible = player:GetAttribute("DigMinigameActive") ~= true and (modal == nil or modal == "")
end

local function updateLayout()
	local screen, frame, list = gui, panel, scroll
	if not screen or not frame or not list then return end
	local bounds = screen.AbsoluteSize
	local top = if bounds.Y < 420 then 16 else 28
	local baseButtonTop = bounds.Y * 0.5 - 26
	local available = math.max(ROW_HEIGHT + SECTION_HEIGHT, baseButtonTop - top - 18)
	-- At most three quest rows plus both section dividers; smaller screens scroll earlier.
	local budget = ROW_HEIGHT * 3 + SECTION_HEIGHT * 2 + GAP * 4
	local listHeight = math.min(math.max(SECTION_HEIGHT, contentHeight), available, budget)
	frame.Position = UDim2.fromOffset(12, top)
	frame.Size = UDim2.fromOffset(math.clamp(bounds.X * 0.18, 160, 216), listHeight + 8)
	list.Size = UDim2.new(1, 0, 0, listHeight)
	list.CanvasSize = UDim2.fromOffset(0, contentHeight)
	list.ScrollingEnabled = contentHeight > listHeight
	list.ScrollBarThickness = if list.ScrollingEnabled then 3 else 0
	list.CanvasPosition = Vector2.new(0, math.min(list.CanvasPosition.Y, math.max(0, contentHeight - listHeight)))
end

local function section(name: string, text: string, color: Color3)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	place(frame, SECTION_HEIGHT)
	local title = label(frame, "Heading", text, 12, true)
	title.Size = UDim2.fromOffset(if mainDone and name == "MainSection" then 140 else 94, SECTION_HEIGHT)
	title.TextColor3 = color
	SuperWaffles.Apply(title, 14)
	local line = Instance.new("Frame")
	line.Name = "Divider"
	local inset = if mainDone and name == "MainSection" then 146 else 100
	line.Position = UDim2.new(0, inset, 0.5, 0)
	line.Size = UDim2.new(1, -inset - 4, 0, 1)
	line.BackgroundColor3 = color
	line.BackgroundTransparency = 0.45
	line.BorderSizePixel = 0
	line.Parent = frame
end

local function questRow(name: string, titleText: string, descriptionText: string, progressText: string, ratio: number, color: Color3, complete: boolean, isSide: boolean)
	local row = Instance.new("TextButton")
	row.Name = name
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.AutoButtonColor = false
	row.Text = ""
	place(row, ROW_HEIGHT)
	local star = label(row, "QuestStar", "★", 15, true)
	star.Position = UDim2.fromOffset(2, 0)
	star.Size = UDim2.fromOffset(19, 18)
	star.TextColor3 = color
	local title = label(row, "Title", titleText, 16, true)
	title.Position = UDim2.fromOffset(23, 0)
	title.Size = UDim2.new(1, -26, 0, 18)
	SuperWaffles.Apply(title, 18)
	local description = label(row, "Description", descriptionText, 11, false)
	description.Position = UDim2.fromOffset(3, 18)
	description.Size = UDim2.new(1, -21, 0, 13)
	description.TextColor3 = if complete then SIDE_COLOR else Color3.fromRGB(235, 239, 242)
	local marker = label(row, "ObjectiveMarker", if complete then "◆" else "◇", 13, true)
	marker.Position = UDim2.new(1, -18, 0, 16)
	marker.Size = UDim2.fromOffset(15, 16)
	marker.TextColor3 = if complete then SIDE_COLOR else color
	local progress = label(row, "Progress", progressText, 10, false)
	progress.Position = UDim2.new(0, 3, 0, 29)
	progress.Size = UDim2.new(1, -6, 0, 10)
	progress.TextXAlignment = Enum.TextXAlignment.Center
	local bar = Instance.new("Frame")
	bar.Name = "ProgressTrack"
	bar.Position = UDim2.new(0, 3, 1, -3)
	bar.Size = UDim2.new(1, -6, 0, 3)
	bar.BackgroundColor3 = Color3.fromRGB(38, 47, 43)
	bar.BackgroundTransparency = 0.2
	bar.BorderSizePixel = 0
	bar.Parent = row
	round(bar, 3)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = bar
	round(fill, 3)
	if isSide then row.Activated:Connect(openDetails) end
end

local function render()
	local list = scroll
	if not list then return end
	local previousPosition = list.CanvasPosition
	for _, child in list:GetChildren() do if child:IsA("GuiObject") then child:Destroy() end end
	contentHeight, elementCount = 0, 0
	section("MainSection", if mainDone then "MAIN QUEST · SELESAI" else "MAIN QUEST", MAIN_COLOR)
	if mainKnown and not mainDone then
		local title, description = Tutorial.GetQuestObjective(mainStep)
		questRow("MainQuest_Current", title, description, string.format("Langkah %d/%d", mainStep, MAIN_COUNT),
			(mainStep - 1) / MAIN_COUNT, MAIN_COLOR, false, false)
	elseif not mainKnown then
		local loading = label(list, "MainLoading", "Memuat main quest...", 12, false)
		place(loading, 24)
	end
	section("SideSection", "SIDE QUEST", SIDE_COLOR)
	local sideCount = 0
	for _, entry in mayorEntries do
		if entry.Accepted == true and entry.Claimed ~= true then
			sideCount += 1
			local target = math.max(1, tonumber(entry.Target) or 1)
			local progress = math.clamp(tonumber(entry.Progress) or 0, 0, target)
			questRow("MayorQuest_" .. entry.Id, entry.DisplayName or entry.Id,
				if progress >= target then "Siap diklaim · temui Mayor" else "Mayor · " .. (entry.Description or ""),
				string.format("%d/%d", progress, target), progress / target, SIDE_COLOR, progress >= target, false)
		end
	end
	for _, entry in entries do
		if entry.Claimed == true then continue end
		sideCount += 1
		local definition = definitions[entry.Id]
		local target = math.max(1, if definition then definition.Target else tonumber(entry.Target) or 1)
		local progress = math.clamp(tonumber(entry.Progress) or 0, 0, target)
		local complete = progress >= target
		questRow("Quest_" .. entry.Id, if definition then definition.DisplayName else entry.Id,
			if complete then "Siap diklaim · buka Quest" elseif definition then definition.Description else "",
			string.format("%d/%d", progress, target), progress / target, SIDE_COLOR, complete, true)
	end
	if sideCount == 0 then
		local empty = label(list, "SideEmpty", if received then "Semua side quest selesai!" else "Memuat side quest...", 12, false)
		place(empty, 28)
	end
	list.CanvasPosition = previousPosition
	updateLayout()
end

local function applyMain(step: any, done: any): boolean
	if type(step) ~= "number" or step ~= step then return false end
	local nextStep = math.max(mainStep, math.clamp(math.floor(step), 1, MAIN_COUNT))
	local nextDone = mainDone or done == true
	local changed = not mainKnown or nextStep ~= mainStep or nextDone ~= mainDone
	mainKnown, mainStep, mainDone = true, nextStep, nextDone
	return changed
end

function Tracker.ApplySnapshot(snapshot: any)
	if type(snapshot) ~= "table" then return end
	local changed = false
	if type(snapshot.MayorQuests) == "table" and type(snapshot.MayorQuests.List) == "table" then
		local parts = {}
		for _, entry in snapshot.MayorQuests.List do
			if type(entry) == "table" and type(entry.Id) == "string" then
				table.insert(parts, entry.Id .. ":" .. tostring(entry.Progress) .. ":" .. tostring(entry.Accepted) .. ":" .. tostring(entry.Claimed) .. ":" .. tostring(entry.Target) .. ":" .. tostring(entry.RewardCoins))
			end
		end
		local nextSignature = table.concat(parts, "|")
		if nextSignature ~= mayorSignature then
			mayorSignature, mayorEntries, changed = nextSignature, snapshot.MayorQuests.List, true
		end
	end
	if type(snapshot.Tutorial) == "table" then changed = applyMain(snapshot.Tutorial.Step, snapshot.Tutorial.Done) or changed end
	local quests = snapshot.Quests
	if type(quests) == "table" and type(quests.List) == "table" and (#quests.List > 0 or (tonumber(quests.Day) or 0) > 0) then
		local parts = {tostring(quests.Day)}
		for _, entry in quests.List do
			if type(entry) == "table" and type(entry.Id) == "string" then
				table.insert(parts, entry.Id .. ":" .. tostring(entry.Progress) .. ":" .. tostring(entry.Claimed))
			end
		end
		local nextSignature = table.concat(parts, "|")
		if not received or nextSignature ~= signature then
			received, signature, changed = true, nextSignature, true
			entries = {}
			for _, entry in quests.List do
				if type(entry) == "table" and type(entry.Id) == "string" then table.insert(entries, entry) end
			end
		end
	end
	if changed then render() end
end

function Tracker.Start()
	if started then return end
	started = true
	local screen = Instance.new("ScreenGui")
	screen.Name = "QuestTrackerGui"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 7
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
	local frame = Instance.new("Frame")
	frame.Name = "Tracker"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = screen
	panel = frame
	local list = Instance.new("ScrollingFrame")
	list.Name = "QuestList"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.CanvasSize = UDim2.new()
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.VerticalScrollBarPosition = Enum.VerticalScrollBarPosition.Left
	list.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	list.ScrollBarImageColor3 = SIDE_COLOR
	list.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	list.Active = true
	list.Parent = frame
	scroll = list
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, GAP)
	layout.Parent = list
	Remotes.GetEvent("StateSync").OnClientEvent:Connect(Tracker.ApplySnapshot)
	local function syncMain()
		if applyMain(player:GetAttribute("TutorialStep"), player:GetAttribute("TutorialDone")) then render() end
	end
	player:GetAttributeChangedSignal("TutorialStep"):Connect(syncMain)
	player:GetAttributeChangedSignal("TutorialDone"):Connect(syncMain)
	player:GetAttributeChangedSignal("ActiveShopModal"):Connect(updateVisibility)
	player:GetAttributeChangedSignal("DigMinigameActive"):Connect(updateVisibility)
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateLayout)
	syncMain()
	render()
	updateVisibility()
	task.spawn(function()
		for _ = 1, 12 do
			task.wait(0.5)
			if received then return end
			if player:GetAttribute("Coins") ~= nil then break end
		end
		if received then return end
		local ok, snapshot = pcall(function() return Remotes.GetFunction("GetInventoryState"):InvokeServer() end)
		if ok and not received then Tracker.ApplySnapshot(snapshot) end
	end)
end

return Tracker
