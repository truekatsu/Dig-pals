--!strict
-- Client controller for Leaderboard modal (Weekly Coins, All-Time Coins, Strongest Pet) (Step 13)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))

local LocalPlayer = Players.LocalPlayer

local LeaderboardController = {}

local screenGui: ScreenGui? = nil
local modalFrame: Frame? = nil
local contentScroll: ScrollingFrame? = nil
local tabButtons: { [Types.LeaderboardCategory]: TextButton } = {}
local activeCategory: Types.LeaderboardCategory = "WeeklyCoins"
local isOpen = false
local started = false

local cachedData: {
	WeeklyCoins: { Types.LeaderboardEntry },
	AllTimeCoins: { Types.LeaderboardEntry },
	StrongestPet: { Types.LeaderboardEntry },
	LastUpdated: number,
} = {
	WeeklyCoins = {},
	AllTimeCoins = {},
	StrongestPet = {},
	LastUpdated = 0,
}

local categoryConfig: {
	[Types.LeaderboardCategory]: {
		Title: string,
		Subtitle: string,
		TabLabel: string,
		ScoreSuffix: string,
		AccentColor: Color3,
	},
} = {
	WeeklyCoins = {
		Title = "TOP COIN MINGGUAN",
		Subtitle = "Reset Otomatis Setiap Senin 00:00 UTC",
		TabLabel = "MINGGUAN",
		ScoreSuffix = "Coin",
		AccentColor = Color3.fromRGB(255, 215, 65),
	},
	AllTimeCoins = {
		Title = "TOP COIN SEPANJANG MASA",
		Subtitle = "Akumulasi Seluruh Coin yang Pernah Didapat",
		TabLabel = "SEMUA MASA",
		ScoreSuffix = "Coin",
		AccentColor = Color3.fromRGB(80, 225, 120),
	},
	StrongestPet = {
		Title = "PET TERKUAT",
		Subtitle = "Power Score = Power x (1 + DigSpeed/10) x Varian",
		TabLabel = "PET TERKUAT",
		ScoreSuffix = "Power",
		AccentColor = Color3.fromRGB(110, 185, 255),
	},
}

function LeaderboardController.IsOpen(): boolean
	return isOpen
end

local function updateResponsiveScale(uiScale: UIScale)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local vp = cam.ViewportSize
	local scaleW = vp.X / 900
	local scaleH = vp.Y / 660
	uiScale.Scale = math.clamp(math.min(1, scaleW, scaleH), 0.55, 1.0)
end

local function renderEntries()
	if not contentScroll then
		return
	end
	contentScroll:ClearAllChildren()

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = contentScroll

	local cfg = categoryConfig[activeCategory]
	local entries = cachedData[activeCategory] or {}

	if #entries == 0 then
		local emptyMsg = Instance.new("TextLabel")
		emptyMsg.Size = UDim2.new(1, 0, 0, 120)
		emptyMsg.BackgroundTransparency = 1
		emptyMsg.Font = Enum.Font.GothamBold
		emptyMsg.TextSize = 16
		emptyMsg.TextColor3 = Color3.fromRGB(160, 170, 190)
		emptyMsg.Text = "Belum ada data peringkat untuk kategori ini."
		emptyMsg.Parent = contentScroll
		return
	end

	for _, entry in ipairs(entries) do
		local card = Instance.new("Frame")
		card.Name = "RankCard_" .. tostring(entry.Rank)
		card.Size = UDim2.new(1, -8, 0, 56)
		card.BackgroundColor3 = if entry.UserId == LocalPlayer.UserId
			then Color3.fromRGB(36, 46, 68)
			elseif entry.Rank % 2 == 0 then Color3.fromRGB(24, 28, 38)
			else Color3.fromRGB(20, 24, 32)
		card.BorderSizePixel = 0
		card.LayoutOrder = entry.Rank
		card.Parent = contentScroll

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 10)
		cardCorner.Parent = card

		local cardStroke = Instance.new("UIStroke")
		cardStroke.Color = if entry.UserId == LocalPlayer.UserId
			then Color3.fromRGB(90, 180, 255)
			elseif entry.Rank == 1 then Color3.fromRGB(245, 195, 55)
			elseif entry.Rank == 2 then Color3.fromRGB(190, 200, 215)
			elseif entry.Rank == 3 then Color3.fromRGB(205, 130, 75)
			else Color3.fromRGB(48, 56, 74)
		cardStroke.Thickness = if entry.UserId == LocalPlayer.UserId or entry.Rank <= 3 then 1.6 else 1.0
		cardStroke.Parent = card

		-- Rank badge
		local badge = Instance.new("Frame")
		badge.Name = "Badge"
		badge.Position = UDim2.fromOffset(10, 8)
		badge.Size = UDim2.fromOffset(40, 40)
		badge.BorderSizePixel = 0
		badge.Parent = card

		local badgeCorner = Instance.new("UICorner")
		badgeCorner.CornerRadius = UDim.new(0, 8)
		badgeCorner.Parent = badge

		local rankLbl = Instance.new("TextLabel")
		rankLbl.Size = UDim2.fromScale(1, 1)
		rankLbl.BackgroundTransparency = 1
		rankLbl.Font = Enum.Font.GothamBlack
		rankLbl.TextSize = 16
		rankLbl.Text = "#" .. tostring(entry.Rank)
		rankLbl.Parent = badge

		if entry.Rank == 1 then
			badge.BackgroundColor3 = Color3.fromRGB(245, 195, 55)
			rankLbl.TextColor3 = Color3.fromRGB(40, 28, 6)
		elseif entry.Rank == 2 then
			badge.BackgroundColor3 = Color3.fromRGB(190, 200, 215)
			rankLbl.TextColor3 = Color3.fromRGB(28, 32, 40)
		elseif entry.Rank == 3 then
			badge.BackgroundColor3 = Color3.fromRGB(205, 130, 75)
			rankLbl.TextColor3 = Color3.fromRGB(40, 20, 10)
		else
			badge.BackgroundColor3 = Color3.fromRGB(36, 42, 56)
			rankLbl.TextColor3 = Color3.fromRGB(170, 180, 200)
		end

		-- Player Name
		local nameLbl = Instance.new("TextLabel")
		nameLbl.Name = "PlayerName"
		nameLbl.Position = UDim2.fromOffset(62, 8)
		nameLbl.Size = UDim2.new(1, -260, 0, 40)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.TextSize = 16
		nameLbl.TextColor3 = if entry.UserId == LocalPlayer.UserId
			then Color3.fromRGB(130, 210, 255)
			else Color3.fromRGB(244, 247, 252)
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.Text = entry.PlayerName .. (if entry.UserId == LocalPlayer.UserId then " (KAMU)" else "")
		nameLbl.Parent = card

		-- Score
		local scoreLbl = Instance.new("TextLabel")
		scoreLbl.Name = "Score"
		scoreLbl.Position = UDim2.new(1, -190, 0, 8)
		scoreLbl.Size = UDim2.fromOffset(178, 40)
		scoreLbl.BackgroundTransparency = 1
		scoreLbl.Font = Enum.Font.GothamBlack
		scoreLbl.TextSize = 16
		scoreLbl.TextColor3 = cfg.AccentColor
		scoreLbl.TextXAlignment = Enum.TextXAlignment.Right
		scoreLbl.Text = Format.Commas(entry.Score) .. " " .. cfg.ScoreSuffix
		scoreLbl.Parent = card
	end
end

local function updateTabStyles()
	for cat, btn in pairs(tabButtons) do
		local isAct = (cat == activeCategory)
		local cfg = categoryConfig[cat]
		btn.BackgroundColor3 = if isAct then cfg.AccentColor else Color3.fromRGB(28, 34, 46)
		btn.TextColor3 = if isAct then Color3.fromRGB(20, 24, 32) else Color3.fromRGB(180, 190, 210)
	end
end

local function buildUI()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("LeaderboardGui")
	if existing and existing:IsA("ScreenGui") then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "LeaderboardGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 16
	gui.IgnoreGuiInset = false
	gui.Parent = playerGui
	screenGui = gui

	local uiScale = Instance.new("UIScale")
	uiScale.Name = "ResponsiveScale"
	uiScale.Parent = gui
	updateResponsiveScale(uiScale)

	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			updateResponsiveScale(uiScale)
		end)
	end

	-- Backdrop
	local backdrop = Instance.new("Frame")
	backdrop.Name = "ModalBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.55
	backdrop.Visible = false
	backdrop.Parent = gui
	modalFrame = backdrop

	-- Card frame
	local modal = Instance.new("Frame")
	modal.Name = "LeaderboardModal"
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.Size = UDim2.fromOffset(680, 560)
	modal.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
	modal.BorderSizePixel = 0
	modal.Parent = backdrop

	local mCorner = Instance.new("UICorner")
	mCorner.CornerRadius = UDim.new(0, 16)
	mCorner.Parent = modal

	local mStroke = Instance.new("UIStroke")
	mStroke.Color = Color3.fromRGB(60, 72, 98)
	mStroke.Thickness = 2
	mStroke.Parent = modal

	-- Header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 60)
	header.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
	header.BorderSizePixel = 0
	header.Parent = modal

	local hCorner = Instance.new("UICorner")
	hCorner.CornerRadius = UDim.new(0, 16)
	hCorner.Parent = header

	local headerTitle = Instance.new("TextLabel")
	headerTitle.Name = "Title"
	headerTitle.Position = UDim2.fromOffset(20, 10)
	headerTitle.Size = UDim2.new(1, -120, 0, 24)
	headerTitle.BackgroundTransparency = 1
	headerTitle.Font = Enum.Font.GothamBlack
	headerTitle.TextSize = 20
	headerTitle.TextColor3 = Color3.fromRGB(248, 250, 255)
	headerTitle.TextXAlignment = Enum.TextXAlignment.Left
	headerTitle.Text = "PAPAN PERINGKAT"
	headerTitle.Parent = header

	local headerSub = Instance.new("TextLabel")
	headerSub.Name = "Subtitle"
	headerSub.Position = UDim2.fromOffset(20, 34)
	headerSub.Size = UDim2.new(1, -120, 0, 18)
	headerSub.BackgroundTransparency = 1
	headerSub.Font = Enum.Font.Gotham
	headerSub.TextSize = 12
	headerSub.TextColor3 = Color3.fromRGB(160, 175, 205)
	headerSub.TextXAlignment = Enum.TextXAlignment.Left
	headerSub.Text = "Diperbarui otomatis tiap 5 menit (Top 10)"
	headerSub.Parent = header

	-- Close button (touch target >= 44px)
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -14, 0.5, 0)
	closeBtn.Size = UDim2.fromOffset(44, 44)
	closeBtn.BackgroundColor3 = Color3.fromRGB(44, 52, 70)
	closeBtn.BorderSizePixel = 0
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.TextSize = 20
	closeBtn.TextColor3 = Color3.fromRGB(240, 244, 252)
	closeBtn.Text = "X"
	closeBtn.Parent = header

	local cCorner = Instance.new("UICorner")
	cCorner.CornerRadius = UDim.new(0, 10)
	cCorner.Parent = closeBtn

	closeBtn.Activated:Connect(function()
		LeaderboardController.Close()
	end)

	-- Tabs container
	local tabsFrame = Instance.new("Frame")
	tabsFrame.Name = "Tabs"
	tabsFrame.Position = UDim2.fromOffset(20, 72)
	tabsFrame.Size = UDim2.new(1, -40, 0, 44)
	tabsFrame.BackgroundTransparency = 1
	tabsFrame.Parent = modal

	local tabsLayout = Instance.new("UIListLayout")
	tabsLayout.FillDirection = Enum.FillDirection.Horizontal
	tabsLayout.Padding = UDim.new(0, 10)
	tabsLayout.Parent = tabsFrame

	local categories: { Types.LeaderboardCategory } = { "WeeklyCoins", "AllTimeCoins", "StrongestPet" }
	for _, cat in ipairs(categories) do
		local cfg = categoryConfig[cat]
		local tabBtn = Instance.new("TextButton")
		tabBtn.Name = "Tab_" .. cat
		tabBtn.Size = UDim2.new(0.333, -7, 1, 0)
		tabBtn.BackgroundColor3 = Color3.fromRGB(28, 34, 46)
		tabBtn.BorderSizePixel = 0
		tabBtn.Font = Enum.Font.GothamBlack
		tabBtn.TextSize = 13
		tabBtn.TextColor3 = Color3.fromRGB(180, 190, 210)
		tabBtn.Text = cfg.TabLabel
		tabBtn.Parent = tabsFrame

		local tCorner = Instance.new("UICorner")
		tCorner.CornerRadius = UDim.new(0, 8)
		tCorner.Parent = tabBtn

		tabBtn.Activated:Connect(function()
			activeCategory = cat
			updateTabStyles()
			renderEntries()
		end)

		tabButtons[cat] = tabBtn
	end

	-- Subtitle banner for active category
	local activeBanner = Instance.new("Frame")
	activeBanner.Name = "ActiveBanner"
	activeBanner.Position = UDim2.fromOffset(20, 124)
	activeBanner.Size = UDim2.new(1, -40, 0, 32)
	activeBanner.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
	activeBanner.BorderSizePixel = 0
	activeBanner.Parent = modal

	local abCorner = Instance.new("UICorner")
	abCorner.CornerRadius = UDim.new(0, 6)
	abCorner.Parent = activeBanner

	local activeBannerText = Instance.new("TextLabel")
	activeBannerText.Name = "BannerText"
	activeBannerText.Position = UDim2.fromOffset(12, 0)
	activeBannerText.Size = UDim2.new(1, -24, 1, 0)
	activeBannerText.BackgroundTransparency = 1
	activeBannerText.Font = Enum.Font.GothamBold
	activeBannerText.TextSize = 12
	activeBannerText.TextColor3 = Color3.fromRGB(190, 205, 230)
	activeBannerText.TextXAlignment = Enum.TextXAlignment.Left
	activeBannerText.Text = "Peringkat 10 Teratas Pemain"
	activeBannerText.Parent = activeBanner

	-- Content Scroll (Top 10)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "ContentScroll"
	scroll.Position = UDim2.fromOffset(20, 164)
	scroll.Size = UDim2.new(1, -40, 1, -180)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Color3.fromRGB(68, 80, 108)
	scroll.CanvasSize = UDim2.fromOffset(0, 620)
	scroll.Parent = modal
	contentScroll = scroll

	updateTabStyles()
end

function LeaderboardController.Open(category: Types.LeaderboardCategory?)
	if not started then
		LeaderboardController.Start()
	end
	if category then
		activeCategory = category
	end
	updateTabStyles()
	isOpen = true
	if modalFrame then
		modalFrame.Visible = true
	end
	renderEntries()

	-- Fetch fresh data
	task.spawn(function()
		local ok, data = pcall(function()
			return Remotes.GetFunction("GetLeaderboards"):InvokeServer()
		end)
		if ok and type(data) == "table" then
			if data.WeeklyCoins then
				cachedData.WeeklyCoins = data.WeeklyCoins
			end
			if data.AllTimeCoins then
				cachedData.AllTimeCoins = data.AllTimeCoins
			end
			if data.StrongestPet then
				cachedData.StrongestPet = data.StrongestPet
			end
			if data.LastUpdated then
				cachedData.LastUpdated = data.LastUpdated
			end
			if isOpen then
				renderEntries()
			end
		end
	end)
end

function LeaderboardController.Close()
	isOpen = false
	if modalFrame then
		modalFrame.Visible = false
	end
end

function LeaderboardController.Toggle(category: Types.LeaderboardCategory?)
	if isOpen then
		if category and category ~= activeCategory then
			LeaderboardController.Open(category)
		else
			LeaderboardController.Close()
		end
	else
		LeaderboardController.Open(category)
	end
end

function LeaderboardController.Start()
	if started then
		return
	end
	started = true

	buildUI()

	-- Register side category button "RANK" in InventoryController
	local Controllers = script.Parent
	local InventoryController = require(Controllers:WaitForChild("InventoryController"))
	InventoryController.RegisterSideCategory({
		Id = "Leaderboard",
		Order = 6,
		IconText = "TOP",
		Label = "RANK",
		OnActivated = function()
			LeaderboardController.Toggle()
		end,
	})

	-- Bind key [6] and Escape
	ContextActionService:BindAction(
		"ToggleLeaderboardKey",
		function(_actionName, inputState, inputObject)
			if inputState == Enum.UserInputState.Begin then
				if inputObject.KeyCode == Enum.KeyCode.Six or inputObject.KeyCode == Enum.KeyCode.KeypadSix then
					LeaderboardController.Toggle()
					return Enum.ContextActionResult.Sink
				elseif inputObject.KeyCode == Enum.KeyCode.Escape and isOpen then
					LeaderboardController.Close()
					return Enum.ContextActionResult.Sink
				end
			end
			return Enum.ContextActionResult.Pass
		end,
		false,
		Enum.KeyCode.Six,
		Enum.KeyCode.KeypadSix,
		Enum.KeyCode.Escape
	)

	-- Listen for server refresh broadcast
	Remotes.GetEvent("LeaderboardUpdated").OnClientEvent:Connect(function(payload: any)
		if type(payload) == "table" then
			if payload.WeeklyCoins then
				cachedData.WeeklyCoins = payload.WeeklyCoins
			end
			if payload.AllTimeCoins then
				cachedData.AllTimeCoins = payload.AllTimeCoins
			end
			if payload.StrongestPet then
				cachedData.StrongestPet = payload.StrongestPet
			end
			if payload.LastUpdated then
				cachedData.LastUpdated = payload.LastUpdated
			end
			if isOpen then
				renderEntries()
			end
		end
	end)
end

return LeaderboardController
