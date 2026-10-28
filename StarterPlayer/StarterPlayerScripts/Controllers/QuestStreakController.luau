--!strict
-- Client controller for Daily Quests (pool of 8, pick 3 daily) and 7-day Login Streak modals (Step 12)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local QuestsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Quests"))
local EggsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Eggs"))

local LocalPlayer = Players.LocalPlayer

local QuestStreakController = {}

local screenGui: ScreenGui? = nil
local modalFrame: Frame? = nil
local questsTabBtn: TextButton? = nil
local streakTabBtn: TextButton? = nil
local questsContainer: Frame? = nil
local streakContainer: Frame? = nil
local countdownLabel: TextLabel? = nil
local activeTab: string = "Quests"
local isOpen: boolean = false
local started: boolean = false

local latestSnapshot: any = nil

local questDefById: { [string]: QuestsConfig.QuestDefinition } = {}
for _, def in ipairs(QuestsConfig.Pool) do
	questDefById[def.Id] = def
end

function QuestStreakController.IsOpen(): boolean
	return isOpen
end

local function formatRemainingTime(): string
	local now = os.time()
	local dayStart = math.floor(now / 86400) * 86400
	local nextMidnight = dayStart + 86400
	local rem = math.max(0, nextMidnight - now)

	local hrs = math.floor(rem / 3600)
	local mins = math.floor((rem % 3600) / 60)
	local secs = rem % 60
	return string.format("%02d:%02d:%02d", hrs, mins, secs)
end

local function renderQuests()
	if not questsContainer then
		return
	end
	questsContainer:ClearAllChildren()

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = questsContainer

	local questsList = if latestSnapshot and latestSnapshot.Quests and latestSnapshot.Quests.List then latestSnapshot.Quests.List else {}

	if #questsList == 0 then
		local emptyLabel = Instance.new("TextLabel")
		emptyLabel.Size = UDim2.fromScale(1, 0.5)
		emptyLabel.BackgroundTransparency = 1
		emptyLabel.Font = Enum.Font.GothamMedium
		emptyLabel.TextSize = 14
		emptyLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
		emptyLabel.Text = "Memuat Quest harian..."
		emptyLabel.Parent = questsContainer
		return
	end

	for orderIdx, qEntry in ipairs(questsList) do
		local def = questDefById[qEntry.Id]
		local target = if def then def.Target else 1
		local progress = math.min(target, qEntry.Progress or 0)
		local isClaimed = qEntry.Claimed == true
		local isComplete = (progress >= target) and not isClaimed

		local card = Instance.new("Frame")
		card.Name = "QuestCard_" .. tostring(qEntry.Id)
		card.Size = UDim2.new(1, -8, 0, 95)
		card.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
		card.BorderSizePixel = 0
		card.LayoutOrder = orderIdx
		card.Parent = questsContainer

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 10)
		cardCorner.Parent = card

		local cardStroke = Instance.new("UIStroke")
		cardStroke.Color = if isComplete then Color3.fromRGB(255, 215, 65) else Color3.fromRGB(50, 50, 62)
		cardStroke.Thickness = if isComplete then 1.5 else 1
		cardStroke.Parent = card

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, -150, 0, 22)
		title.Position = UDim2.fromOffset(14, 10)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBold
		title.TextSize = 14
		title.TextColor3 = Color3.fromRGB(255, 235, 140)
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Text = if def then def.DisplayName else qEntry.Id
		title.Parent = card

		local desc = Instance.new("TextLabel")
		desc.Size = UDim2.new(1, -150, 0, 18)
		desc.Position = UDim2.fromOffset(14, 32)
		desc.BackgroundTransparency = 1
		desc.Font = Enum.Font.GothamMedium
		desc.TextSize = 12
		desc.TextColor3 = Color3.fromRGB(200, 200, 210)
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.Text = if def then def.Description else ""
		desc.Parent = card

		local barBg = Instance.new("Frame")
		barBg.Size = UDim2.new(1, -150, 0, 12)
		barBg.Position = UDim2.fromOffset(14, 56)
		barBg.BackgroundColor3 = Color3.fromRGB(48, 48, 60)
		barBg.BorderSizePixel = 0
		barBg.Parent = card

		local bCorner = Instance.new("UICorner")
		bCorner.CornerRadius = UDim.new(0, 6)
		bCorner.Parent = barBg

		local fill = Instance.new("Frame")
		local ratio = math.clamp(progress / target, 0, 1)
		fill.Size = UDim2.fromScale(ratio, 1)
		fill.BackgroundColor3 = if isComplete then Color3.fromRGB(90, 220, 110) else Color3.fromRGB(75, 150, 240)
		fill.BorderSizePixel = 0
		fill.Parent = barBg

		local fCorner = Instance.new("UICorner")
		fCorner.CornerRadius = UDim.new(0, 6)
		fCorner.Parent = fill

		local progLabel = Instance.new("TextLabel")
		progLabel.Size = UDim2.new(1, -150, 0, 16)
		progLabel.Position = UDim2.fromOffset(14, 72)
		progLabel.BackgroundTransparency = 1
		progLabel.Font = Enum.Font.GothamMedium
		progLabel.TextSize = 11
		progLabel.TextColor3 = Color3.fromRGB(180, 180, 195)
		progLabel.TextXAlignment = Enum.TextXAlignment.Left
		progLabel.Text = string.format("Progress: %d / %d", progress, target)
		progLabel.Parent = card

		local rewardText = ""
		if def then
			if def.RewardCoins > 0 then
				rewardText = string.format("+%d Coins", def.RewardCoins)
			elseif def.RewardEggId then
				rewardText = string.format("+1 %s", tostring(EggsConfig.All[def.RewardEggId] and EggsConfig.All[def.RewardEggId].DisplayName or def.RewardEggId))
			end
		end

		local rewardLbl = Instance.new("TextLabel")
		rewardLbl.Size = UDim2.fromOffset(120, 20)
		rewardLbl.Position = UDim2.new(1, -134, 0, 14)
		rewardLbl.BackgroundTransparency = 1
		rewardLbl.Font = Enum.Font.GothamBold
		rewardLbl.TextSize = 12
		rewardLbl.TextColor3 = Color3.fromRGB(255, 215, 80)
		rewardLbl.Text = rewardText
		rewardLbl.Parent = card

		local actionBtn = Instance.new("TextButton")
		actionBtn.Size = UDim2.fromOffset(116, 36)
		actionBtn.Position = UDim2.new(1, -130, 0, 42)
		actionBtn.BorderSizePixel = 0
		actionBtn.Font = Enum.Font.GothamBlack
		actionBtn.TextSize = 13
		actionBtn.Parent = card

		local aCorner = Instance.new("UICorner")
		aCorner.CornerRadius = UDim.new(0, 8)
		aCorner.Parent = actionBtn

		if isClaimed then
			actionBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
			actionBtn.TextColor3 = Color3.fromRGB(140, 140, 150)
			actionBtn.Text = "DIKLAIM [v]"
			actionBtn.Active = false
		elseif isComplete then
			actionBtn.BackgroundColor3 = Color3.fromRGB(50, 185, 95)
			actionBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			actionBtn.Text = "KLAIM"
			actionBtn.Active = true

			actionBtn.MouseButton1Click:Connect(function()
				actionBtn.Active = false
				actionBtn.Text = "Mengklaim..."
				local res = Remotes.GetFunction("ClaimQuest"):InvokeServer(qEntry.Id)
				if type(res) == "table" and res.Success then
					actionBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
					actionBtn.TextColor3 = Color3.fromRGB(140, 140, 150)
					actionBtn.Text = "DIKLAIM [v]"
				else
					actionBtn.Active = true
					actionBtn.Text = "KLAIM"
				end
			end)
		else
			actionBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
			actionBtn.TextColor3 = Color3.fromRGB(160, 160, 175)
			actionBtn.Text = string.format("%d / %d", progress, target)
			actionBtn.Active = false
		end
	end
end

local function renderStreak()
	if not streakContainer then
		return
	end
	streakContainer:ClearAllChildren()

	local streakData = if latestSnapshot and latestSnapshot.Streak then latestSnapshot.Streak else { Day = 0, LastClaim = 0 }
	local currentUtcDay = math.floor(os.time() / 86400)
	local lastClaim = streakData.LastClaim or 0
	local storedDay = streakData.Day or 0

	local canClaim = false
	local todayStreakDay = 1

	if lastClaim == 0 then
		canClaim = true
		todayStreakDay = 1
	elseif lastClaim == currentUtcDay then
		canClaim = false
		todayStreakDay = storedDay
	elseif lastClaim == currentUtcDay - 1 then
		canClaim = true
		todayStreakDay = if storedDay >= QuestsConfig.StreakLengthDays then 1 else storedDay + 1
	else
		canClaim = true
		todayStreakDay = 1
	end

	local topInfo = Instance.new("TextLabel")
	topInfo.Size = UDim2.new(1, -8, 0, 36)
	topInfo.Position = UDim2.fromOffset(4, 0)
	topInfo.BackgroundTransparency = 1
	topInfo.Font = Enum.Font.GothamMedium
	topInfo.TextSize = 13
	topInfo.TextColor3 = Color3.fromRGB(220, 220, 235)
	topInfo.TextXAlignment = Enum.TextXAlignment.Left
	topInfo.Text = string.format("Streak Saat Ini: Hari %d / 7 | Status: %s", storedDay, if canClaim then "Bisa Diklaim Hari Ini!" else "Sudah Diklaim Hari Ini (Kembali besok)")
	topInfo.Parent = streakContainer

	local grid = Instance.new("Frame")
	grid.Size = UDim2.new(1, -8, 0, 260)
	grid.Position = UDim2.fromOffset(4, 42)
	grid.BackgroundTransparency = 1
	grid.Parent = streakContainer

	local gLayout = Instance.new("UIGridLayout")
	gLayout.CellSize = UDim2.fromOffset(134, 118)
	gLayout.CellPadding = UDim2.fromOffset(10, 10)
	gLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gLayout.Parent = grid

	for dayIdx = 1, QuestsConfig.StreakLengthDays do
		local reward = QuestsConfig.StreakRewards[dayIdx]
		local isPast = (storedDay >= dayIdx and lastClaim == currentUtcDay) or (storedDay > dayIdx and canClaim)
		local isToday = (dayIdx == todayStreakDay)
		local isLocked = not isPast and not (isToday and canClaim)

		local card = Instance.new("Frame")
		card.Name = "DayCard_" .. dayIdx
		card.BackgroundColor3 = if isToday and canClaim then Color3.fromRGB(42, 38, 56) elseif isPast then Color3.fromRGB(28, 28, 36) else Color3.fromRGB(22, 22, 28)
		card.BorderSizePixel = 0
		card.LayoutOrder = dayIdx
		card.Parent = grid

		local cCorner = Instance.new("UICorner")
		cCorner.CornerRadius = UDim.new(0, 8)
		cCorner.Parent = card

		local cStroke = Instance.new("UIStroke")
		cStroke.Color = if isToday and canClaim then Color3.fromRGB(255, 215, 65) elseif isPast then Color3.fromRGB(70, 180, 95) else Color3.fromRGB(45, 45, 55)
		cStroke.Thickness = if isToday and canClaim then 2 else 1
		cStroke.Parent = card

		local dHeader = Instance.new("TextLabel")
		dHeader.Size = UDim2.new(1, -8, 0, 20)
		dHeader.Position = UDim2.fromOffset(4, 6)
		dHeader.BackgroundTransparency = 1
		dHeader.Font = Enum.Font.GothamBlack
		dHeader.TextSize = 12
		dHeader.TextColor3 = if isToday and canClaim then Color3.fromRGB(255, 220, 80) elseif isPast then Color3.fromRGB(110, 220, 130) else Color3.fromRGB(160, 160, 170)
		dHeader.Text = string.format("HARI %d", dayIdx)
		dHeader.Parent = card

		local rewCoins = string.format("+%d Coins", reward.RewardCoins)
		local rCoinLbl = Instance.new("TextLabel")
		rCoinLbl.Size = UDim2.new(1, -8, 0, 18)
		rCoinLbl.Position = UDim2.fromOffset(4, 28)
		rCoinLbl.BackgroundTransparency = 1
		rCoinLbl.Font = Enum.Font.GothamBold
		rCoinLbl.TextSize = 12
		rCoinLbl.TextColor3 = Color3.fromRGB(255, 215, 75)
		rCoinLbl.Text = rewCoins
		rCoinLbl.Parent = card

		local eggTxt = if reward.RewardEggId then ("+ " .. tostring(EggsConfig.All[reward.RewardEggId] and EggsConfig.All[reward.RewardEggId].DisplayName or reward.RewardEggId)) else ""
		local rEggLbl = Instance.new("TextLabel")
		rEggLbl.Size = UDim2.new(1, -8, 0, 16)
		rEggLbl.Position = UDim2.fromOffset(4, 48)
		rEggLbl.BackgroundTransparency = 1
		rEggLbl.Font = Enum.Font.GothamMedium
		rEggLbl.TextSize = 10
		rEggLbl.TextColor3 = Color3.fromRGB(120, 220, 255)
		rEggLbl.Text = eggTxt
		rEggLbl.Parent = card

		local statusLbl = Instance.new("TextLabel")
		statusLbl.Size = UDim2.new(1, -8, 0, 24)
		statusLbl.Position = UDim2.new(0, 4, 1, -28)
		statusLbl.BackgroundTransparency = 1
		statusLbl.Font = Enum.Font.GothamBold
		statusLbl.TextSize = 10
		statusLbl.Parent = card

		if isPast then
			statusLbl.TextColor3 = Color3.fromRGB(90, 210, 110)
			statusLbl.Text = "DIKLAIM [v]"
		elseif isToday and canClaim then
			statusLbl.TextColor3 = Color3.fromRGB(255, 230, 90)
			statusLbl.Text = "HARI INI!"
		else
			statusLbl.TextColor3 = Color3.fromRGB(120, 120, 130)
			statusLbl.Text = "Terkunci"
		end
	end

	local claimTodayBtn = Instance.new("TextButton")
	claimTodayBtn.Name = "ClaimStreakButton"
	claimTodayBtn.Size = UDim2.new(1, -8, 0, 44)
	claimTodayBtn.Position = UDim2.new(0, 4, 1, -50)
	claimTodayBtn.BorderSizePixel = 0
	claimTodayBtn.Font = Enum.Font.GothamBlack
	claimTodayBtn.TextSize = 15
	claimTodayBtn.Parent = streakContainer

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 10)
	btnCorner.Parent = claimTodayBtn

	if canClaim then
		claimTodayBtn.BackgroundColor3 = Color3.fromRGB(50, 185, 95)
		claimTodayBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		claimTodayBtn.Text = string.format("KLAIM HADIAH HARI %d", todayStreakDay)
		claimTodayBtn.Active = true

		claimTodayBtn.MouseButton1Click:Connect(function()
			claimTodayBtn.Active = false
			claimTodayBtn.Text = "Mengklaim Hadiah..."
			local res = Remotes.GetFunction("ClaimStreak"):InvokeServer()
			if type(res) == "table" and res.Success then
				claimTodayBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
				claimTodayBtn.TextColor3 = Color3.fromRGB(140, 140, 150)
				claimTodayBtn.Text = "SUDAH DIKLAIM HARI INI [v]"
				renderStreak()
			else
				claimTodayBtn.Active = true
				claimTodayBtn.Text = string.format("KLAIM HADIAH HARI %d", todayStreakDay)
			end
		end)
	else
		claimTodayBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
		claimTodayBtn.TextColor3 = Color3.fromRGB(140, 140, 150)
		claimTodayBtn.Text = "SUDAH DIKLAIM HARI INI [v]"
		claimTodayBtn.Active = false
	end
end

local function renderActiveTab()
	if activeTab == "Quests" then
		if questsContainer then questsContainer.Visible = true end
		if streakContainer then streakContainer.Visible = false end
		renderQuests()
	else
		if questsContainer then questsContainer.Visible = false end
		if streakContainer then streakContainer.Visible = true end
		renderStreak()
	end
end

local function buildUI()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("QuestStreakGui")
	if existing and existing:IsA("ScreenGui") then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "QuestStreakGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	screenGui = gui

	local modal = Instance.new("Frame")
	modal.Name = "QuestStreakModal"
	modal.Size = UDim2.fromScale(1, 1)
	modal.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	modal.BackgroundTransparency = 0.5
	modal.BorderSizePixel = 0
	modal.Visible = false
	modal.Parent = gui
	modalFrame = modal

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromOffset(620, 500)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
	card.BorderSizePixel = 0
	card.Parent = modal

	local uiScale = Instance.new("UIScale")
	uiScale.Parent = card

	local function updateResponsiveScale()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local vp = cam.ViewportSize
		local scaleW = vp.X / 680
		local scaleH = vp.Y / 560
		uiScale.Scale = math.clamp(math.min(1, scaleW, scaleH), 0.55, 1.0)
	end
	updateResponsiveScale()
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveScale)
	end

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 14)
	cardCorner.Parent = card

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = Color3.fromRGB(255, 205, 75)
	cardStroke.Thickness = 2
	cardStroke.Parent = card

	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Size = UDim2.new(1, -68, 0, 36)
	header.Position = UDim2.fromOffset(20, 14)
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.GothamBlack
	header.TextSize = 20
	header.TextColor3 = Color3.fromRGB(255, 215, 75)
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Text = "[*] QUEST & LOGIN STREAK [*]"
	header.Parent = card

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.fromOffset(44, 44)
	closeBtn.Position = UDim2.new(1, -54, 0, 10)
	closeBtn.BackgroundColor3 = Color3.fromRGB(50, 40, 50)
	closeBtn.BorderSizePixel = 0
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.TextSize = 18
	closeBtn.TextColor3 = Color3.fromRGB(255, 120, 120)
	closeBtn.Text = "X"
	closeBtn.Parent = card

	local cCorner = Instance.new("UICorner")
	cCorner.CornerRadius = UDim.new(0, 8)
	cCorner.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		QuestStreakController.Close()
	end)

	local timeLabel = Instance.new("TextLabel")
	timeLabel.Name = "CountdownLabel"
	timeLabel.Size = UDim2.new(1, -40, 0, 22)
	timeLabel.Position = UDim2.fromOffset(20, 48)
	timeLabel.BackgroundTransparency = 1
	timeLabel.Font = Enum.Font.GothamMedium
	timeLabel.TextSize = 12
	timeLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
	timeLabel.TextXAlignment = Enum.TextXAlignment.Left
	timeLabel.Text = string.format("Reset Quest dalam: %s (00:00 UTC)", formatRemainingTime())
	timeLabel.Parent = card
	countdownLabel = timeLabel

	local tabContainer = Instance.new("Frame")
	tabContainer.Name = "TabContainer"
	tabContainer.Size = UDim2.new(1, -40, 0, 44)
	tabContainer.Position = UDim2.fromOffset(20, 74)
	tabContainer.BackgroundTransparency = 1
	tabContainer.Parent = card

	local qBtn = Instance.new("TextButton")
	qBtn.Name = "QuestsTab"
	qBtn.Size = UDim2.new(0.5, -4, 1, 0)
	qBtn.Position = UDim2.fromOffset(0, 0)
	qBtn.BackgroundColor3 = Color3.fromRGB(48, 48, 62)
	qBtn.BorderSizePixel = 0
	qBtn.Font = Enum.Font.GothamBlack
	qBtn.TextSize = 14
	qBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	qBtn.Text = "QUEST HARIAN (3)"
	qBtn.Parent = tabContainer
	questsTabBtn = qBtn

	local qCorner = Instance.new("UICorner")
	qCorner.CornerRadius = UDim.new(0, 8)
	qCorner.Parent = qBtn

	local sBtn = Instance.new("TextButton")
	sBtn.Name = "StreakTab"
	sBtn.Size = UDim2.new(0.5, -4, 1, 0)
	sBtn.Position = UDim2.new(0.5, 4, 0, 0)
	sBtn.BackgroundColor3 = Color3.fromRGB(32, 32, 42)
	sBtn.BorderSizePixel = 0
	sBtn.Font = Enum.Font.GothamBlack
	sBtn.TextSize = 14
	sBtn.TextColor3 = Color3.fromRGB(180, 180, 190)
	sBtn.Text = "LOGIN STREAK 7 HARI"
	sBtn.Parent = tabContainer
	streakTabBtn = sBtn

	local sCorner = Instance.new("UICorner")
	sCorner.CornerRadius = UDim.new(0, 8)
	sCorner.Parent = sBtn

	qBtn.MouseButton1Click:Connect(function()
		activeTab = "Quests"
		qBtn.BackgroundColor3 = Color3.fromRGB(48, 48, 62)
		qBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		sBtn.BackgroundColor3 = Color3.fromRGB(32, 32, 42)
		sBtn.TextColor3 = Color3.fromRGB(180, 180, 190)
		renderActiveTab()
	end)

	sBtn.MouseButton1Click:Connect(function()
		activeTab = "Streak"
		sBtn.BackgroundColor3 = Color3.fromRGB(48, 48, 62)
		sBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		qBtn.BackgroundColor3 = Color3.fromRGB(32, 32, 42)
		qBtn.TextColor3 = Color3.fromRGB(180, 180, 190)
		renderActiveTab()
	end)

	local qFrame = Instance.new("Frame")
	qFrame.Name = "QuestsContainer"
	qFrame.Size = UDim2.new(1, -40, 0, 360)
	qFrame.Position = UDim2.fromOffset(20, 120)
	qFrame.BackgroundTransparency = 1
	qFrame.Parent = card
	questsContainer = qFrame

	local sFrame = Instance.new("Frame")
	sFrame.Name = "StreakContainer"
	sFrame.Size = UDim2.new(1, -40, 0, 360)
	sFrame.Position = UDim2.fromOffset(20, 120)
	sFrame.BackgroundTransparency = 1
	sFrame.Visible = false
	sFrame.Parent = card
	streakContainer = sFrame
end

function QuestStreakController.OpenQuests()
	if not modalFrame then
		buildUI()
	end
	activeTab = "Quests"
	if questsTabBtn and streakTabBtn then
		questsTabBtn.BackgroundColor3 = Color3.fromRGB(48, 48, 62)
		questsTabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		streakTabBtn.BackgroundColor3 = Color3.fromRGB(32, 32, 42)
		streakTabBtn.TextColor3 = Color3.fromRGB(180, 180, 190)
	end
	isOpen = true
	if modalFrame then
		modalFrame.Visible = true
	end
	renderActiveTab()
end

function QuestStreakController.OpenStreak()
	if not modalFrame then
		buildUI()
	end
	activeTab = "Streak"
	if questsTabBtn and streakTabBtn then
		streakTabBtn.BackgroundColor3 = Color3.fromRGB(48, 48, 62)
		streakTabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		questsTabBtn.BackgroundColor3 = Color3.fromRGB(32, 32, 42)
		questsTabBtn.TextColor3 = Color3.fromRGB(180, 180, 190)
	end
	isOpen = true
	if modalFrame then
		modalFrame.Visible = true
	end
	renderActiveTab()
end

function QuestStreakController.Close()
	isOpen = false
	if modalFrame then
		modalFrame.Visible = false
	end
end

function QuestStreakController.Toggle(tabName: string?)
	if isOpen then
		if tabName and tabName ~= activeTab then
			if tabName == "Quests" then
				QuestStreakController.OpenQuests()
			else
				QuestStreakController.OpenStreak()
			end
		else
			QuestStreakController.Close()
		end
	else
		if tabName == "Streak" then
			QuestStreakController.OpenStreak()
		else
			QuestStreakController.OpenQuests()
		end
	end
end

function QuestStreakController.Start()
	if started then
		return
	end
	started = true

	buildUI()

	local Controllers = script.Parent
	local InventoryController = require(Controllers:WaitForChild("InventoryController"))
	InventoryController.RegisterSideCategory({
		Id = "Quests",
		Order = 4,
		IconText = "QST",
		Label = "QUEST",
		OnActivated = function()
			QuestStreakController.Toggle("Quests")
		end,
	})

	InventoryController.RegisterSideCategory({
		Id = "Streak",
		Order = 5,
		IconText = "DAY",
		Label = "STREAK",
		OnActivated = function()
			QuestStreakController.Toggle("Streak")
		end,
	})

	ContextActionService:BindAction(
		"ToggleQuestModalKey",
		function(_actionName, inputState, inputObject)
			if inputState == Enum.UserInputState.Begin then
				if inputObject.KeyCode == Enum.KeyCode.Five or inputObject.KeyCode == Enum.KeyCode.KeypadFive then
					QuestStreakController.Toggle("Quests")
					return Enum.ContextActionResult.Sink
				elseif inputObject.KeyCode == Enum.KeyCode.Escape and isOpen then
					QuestStreakController.Close()
					return Enum.ContextActionResult.Sink
				end
			end
			return Enum.ContextActionResult.Pass
		end,
		false,
		Enum.KeyCode.Five,
		Enum.KeyCode.KeypadFive,
		Enum.KeyCode.Escape
	)

	task.spawn(function()
		while true do
			task.wait(1.0)
			if isOpen and countdownLabel then
				countdownLabel.Text = string.format("Reset Quest dalam: %s (00:00 UTC)", formatRemainingTime())
			end
		end
	end)

	Remotes.GetEvent("StateSync").OnClientEvent:Connect(function(snapshot: any)
		if type(snapshot) == "table" then
			latestSnapshot = snapshot
			if isOpen then
				renderActiveTab()
			end
		end
	end)
end

return QuestStreakController
