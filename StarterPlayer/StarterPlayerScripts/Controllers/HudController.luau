--!strict
-- Persistent Simulator HUD: Coins counter, Bag capacity (e.g. 12/20), EggBag counter, and Drop/Auto-Sell notifications (Step 6)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local EconomyConfig = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))
local BaseConfig = require(Shared:WaitForChild("Config"):WaitForChild("Base"))
local RarityConfig = require(Shared:WaitForChild("Config"):WaitForChild("Rarity"))

local LocalPlayer = Players.LocalPlayer

local HudController = {}

local coinsValue: number = EconomyConfig.StartingCoins
local incomeValue: number = 0
local bagCountValue: number = 0
local bagCapacityValue: number = EconomyConfig.BagLevels[1].Capacity
local bagLevelValue: number = 1
local eggCountValue: number = 0
local eggCapacityValue: number = BaseConfig.BaseEggBagCapacity + 1

local dropToastVersion: number = 0
local started = false

-- UI references
local screenGui: ScreenGui? = nil
local uiScale: UIScale? = nil
local coinsTextLabel: TextLabel? = nil
local coinsScaleInst: UIScale? = nil
local incomeTextLabel: TextLabel? = nil
local bagTextLabel: TextLabel? = nil
local bagLevelBadge: TextLabel? = nil
local bagFillFrame: Frame? = nil
local bagStrokeInst: UIStroke? = nil
local eggTextLabel: TextLabel? = nil
local dropBannerContainer: Frame? = nil

local function updateResponsiveScale()
	if not uiScale then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local vp = cam.ViewportSize
	local scaleW = vp.X / 900
	local scaleH = vp.Y / 660
	uiScale.Scale = math.clamp(math.min(1, scaleW, scaleH), 0.55, 1.0)
end

local function refreshHudVisuals(animateCoinPop: boolean?)
	if coinsTextLabel then
		coinsTextLabel.Text = Format.Commas(coinsValue)
	end
	if incomeTextLabel then
		if incomeValue > 0 then
			incomeTextLabel.Text = string.format("+%s/dtk", Format.Commas(incomeValue))
			incomeTextLabel.Visible = true
		else
			incomeTextLabel.Visible = false
		end
	end
	if animateCoinPop and coinsScaleInst then
		coinsScaleInst.Scale = 1.12
		TweenService:Create(coinsScaleInst, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1.0,
		}):Play()
	end

	local isFull = bagCountValue >= bagCapacityValue
	local ratio = if bagCapacityValue > 0 then math.clamp(bagCountValue / bagCapacityValue, 0, 1) else 0

	if bagTextLabel then
		if isFull then
			bagTextLabel.Text = string.format("PENUH %d/%d", bagCountValue, bagCapacityValue)
			bagTextLabel.TextColor3 = Color3.fromRGB(255, 118, 118)
		else
			bagTextLabel.Text = string.format("Tas %d/%d", bagCountValue, bagCapacityValue)
			bagTextLabel.TextColor3 = Color3.fromRGB(244, 247, 252)
		end
	end

	if bagLevelBadge then
		bagLevelBadge.Text = string.format("Lv.%d", bagLevelValue)
	end

	if bagFillFrame then
		local fillColor = if isFull
			then Color3.fromRGB(238, 78, 84)
			elseif ratio >= 0.8 then Color3.fromRGB(246, 178, 60)
			else Color3.fromRGB(72, 198, 128)
		bagFillFrame.BackgroundColor3 = fillColor
		TweenService:Create(bagFillFrame, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(ratio, 1),
		}):Play()
	end

	if bagStrokeInst then
		bagStrokeInst.Color = if isFull
			then Color3.fromRGB(242, 92, 96)
			else Color3.fromRGB(98, 112, 142)
		bagStrokeInst.Thickness = if isFull then 2.2 else 1.5
	end

	if eggTextLabel then
		local eggFull = eggCountValue >= eggCapacityValue
		eggTextLabel.Text = string.format("Telur %d/%d", eggCountValue, eggCapacityValue)
		eggTextLabel.TextColor3 = if eggFull
			then Color3.fromRGB(255, 206, 98)
			else Color3.fromRGB(205, 214, 232)
	end
end

local function syncFromAttributes(animateCoins: boolean?)
	local attrCoins = LocalPlayer:GetAttribute("Coins")
	local prevCoins = coinsValue
	if type(attrCoins) == "number" then
		coinsValue = attrCoins
	end

	local attrIncome = LocalPlayer:GetAttribute("IncomePerSecond")
	if type(attrIncome) == "number" then
		incomeValue = attrIncome
	end

	local attrBagCount = LocalPlayer:GetAttribute("BagItemCount")
	if type(attrBagCount) == "number" then
		bagCountValue = attrBagCount
	end

	local attrBagCap = LocalPlayer:GetAttribute("BagCapacity")
	if type(attrBagCap) == "number" then
		bagCapacityValue = attrBagCap
	end

	local attrBagLv = LocalPlayer:GetAttribute("BagLevel")
	if type(attrBagLv) == "number" then
		bagLevelValue = attrBagLv
	end

	local attrEggCount = LocalPlayer:GetAttribute("EggCount")
	if type(attrEggCount) == "number" then
		eggCountValue = attrEggCount
	end

	local attrEggCap = LocalPlayer:GetAttribute("EggCapacity")
	if type(attrEggCap) == "number" then
		eggCapacityValue = attrEggCap
	end

	refreshHudVisuals(animateCoins and coinsValue ~= prevCoins)
end

function HudController.ShowDropSummary(summary: any)
	if not dropBannerContainer or type(summary) ~= "table" or type(summary.Drops) ~= "table" then
		return
	end

	dropToastVersion += 1
	local currentToastVersion = dropToastVersion

	for _, child in dropBannerContainer:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	local timingPct = math.floor((tonumber(summary.TimingScore) or 0) * 100 + 0.5)
	local effLuck = tonumber(summary.EffectiveLuck) or 1.0

	local headerPill = Instance.new("Frame")
	headerPill.Name = "HeaderPill"
	headerPill.Size = UDim2.fromOffset(316, 28)
	headerPill.BackgroundColor3 = Color3.fromRGB(28, 32, 44)
	headerPill.BorderSizePixel = 0
	headerPill.LayoutOrder = 0
	headerPill.Parent = dropBannerContainer

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(1, 0)
	headerCorner.Parent = headerPill

	local headerStroke = Instance.new("UIStroke")
	headerStroke.Color = Color3.fromRGB(255, 205, 70)
	headerStroke.Thickness = 1.8
	headerStroke.Parent = headerPill

	local headerText = Instance.new("TextLabel")
	headerText.Size = UDim2.fromScale(1, 1)
	headerText.BackgroundTransparency = 1
	headerText.Font = Enum.Font.GothamBlack
	headerText.TextSize = 12
	headerText.TextColor3 = Color3.fromRGB(255, 225, 110)
	headerText.TextStrokeTransparency = 0.35
	headerText.Text = string.format("HASIL GALIAN | TIMING %d%% | LUCK %.2fx", timingPct, effLuck)
	headerText.Parent = headerPill

	local headerScale = Instance.new("UIScale")
	headerScale.Scale = 0.78
	headerScale.Parent = headerPill
	TweenService:Create(headerScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1.0,
	}):Play()

	for index, drop in summary.Drops do
		local rarityName = tostring(drop.Rarity or "Common")
		local rarityInfo = (RarityConfig.ById :: any)[rarityName] or RarityConfig.ById.Common
		local rarityColor: Color3 = rarityInfo.Color

		local card = Instance.new("Frame")
		card.Name = "DropCard_" .. tostring(index)
		card.Size = UDim2.fromOffset(338, 46)
		card.BackgroundColor3 = Color3.fromRGB(32, 37, 50)
		card.BorderSizePixel = 0
		card.LayoutOrder = index
		card.Parent = dropBannerContainer

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 11)
		cardCorner.Parent = card

		local cardStroke = Instance.new("UIStroke")
		cardStroke.Color = rarityColor
		cardStroke.Thickness = 2.2
		cardStroke.Parent = card

		local badge = Instance.new("TextLabel")
		badge.Name = "TypeBadge"
		badge.AnchorPoint = Vector2.new(0, 0.5)
		badge.Position = UDim2.new(0, 8, 0.5, 0)
		badge.Size = UDim2.fromOffset(54, 28)
		badge.BackgroundColor3 = rarityColor
		badge.Font = Enum.Font.GothamBlack
		badge.TextSize = 11
		badge.TextColor3 = Color3.fromRGB(255, 255, 255)
		badge.TextStrokeTransparency = 0.35
		badge.Text = if drop.DropType == "Egg" then "TELUR" else "ITEM"
		badge.Parent = card

		local badgeCorner = Instance.new("UICorner")
		badgeCorner.CornerRadius = UDim.new(0, 7)
		badgeCorner.Parent = badge

		local titleLabel = Instance.new("TextLabel")
		titleLabel.Name = "Title"
		titleLabel.Position = UDim2.fromOffset(70, 5)
		titleLabel.Size = UDim2.fromOffset(258, 19)
		titleLabel.BackgroundTransparency = 1
		titleLabel.Font = Enum.Font.GothamBlack
		titleLabel.TextSize = 14
		titleLabel.TextXAlignment = Enum.TextXAlignment.Left
		titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
		titleLabel.TextColor3 = Color3.fromRGB(248, 250, 255)
		titleLabel.Text = string.format("+1 %s", tostring(drop.DisplayName or drop.Id))
		titleLabel.Parent = card

		local subLabel = Instance.new("TextLabel")
		subLabel.Name = "SubLabel"
		subLabel.Position = UDim2.fromOffset(70, 24)
		subLabel.Size = UDim2.fromOffset(258, 16)
		subLabel.BackgroundTransparency = 1
		subLabel.Font = Enum.Font.GothamBold
		subLabel.TextSize = 11
		subLabel.TextXAlignment = Enum.TextXAlignment.Left
		subLabel.TextTruncate = Enum.TextTruncate.AtEnd
		if drop.AutoSold then
			subLabel.TextColor3 = Color3.fromRGB(255, 212, 92)
			subLabel.Text = string.format(
				"Tas Telur Penuh! Otomatis dijual +%s Coin",
				Format.Commas(tonumber(drop.AutoSoldCoins) or 0)
			)
		else
			subLabel.TextColor3 = rarityColor
			subLabel.Text = string.format(
				"%s | Nilai Jual: %s Coin",
				rarityName,
				Format.Commas(tonumber(drop.SellPrice) or 0)
			)
		end
		subLabel.Parent = card

		local cardScale = Instance.new("UIScale")
		cardScale.Scale = 0.7
		cardScale.Parent = card
		TweenService:Create(
			cardScale,
			TweenInfo.new(0.26 + (index * 0.05), Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1.0 }
		):Play()
	end

	task.delay(3.4, function()
		if dropToastVersion == currentToastVersion and dropBannerContainer then
			for _, child in dropBannerContainer:GetChildren() do
				if not child:IsA("UIListLayout") then
					child:Destroy()
				end
			end
		end
	end)
end

local function buildHudGui()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("HudGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "HudGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 8
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	screenGui = gui

	local scaleInst = Instance.new("UIScale")
	scaleInst.Name = "ResponsiveScale"
	scaleInst.Scale = 1
	scaleInst.Parent = gui
	uiScale = scaleInst
	updateResponsiveScale()

	-- Top-left status cluster (Coins, Bag Capacity, Egg Bag)
	local cluster = Instance.new("Frame")
	cluster.Name = "TopLeftStatus"
	cluster.Position = UDim2.fromOffset(14, 12)
	cluster.Size = UDim2.fromOffset(192, 134)
	cluster.BackgroundTransparency = 1
	cluster.Parent = gui

	local clusterLayout = Instance.new("UIListLayout")
	clusterLayout.SortOrder = Enum.SortOrder.LayoutOrder
	clusterLayout.Padding = UDim.new(0, 7)
	clusterLayout.Parent = cluster

	-- 1. Coins Pill
	local coinsCard = Instance.new("Frame")
	coinsCard.Name = "CoinsPill"
	coinsCard.Size = UDim2.fromOffset(186, 40)
	coinsCard.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
	coinsCard.BackgroundTransparency = 0.08
	coinsCard.BorderSizePixel = 0
	coinsCard.LayoutOrder = 1
	coinsCard.Parent = cluster

	local cScale = Instance.new("UIScale")
	cScale.Parent = coinsCard
	coinsScaleInst = cScale

	local coinsCorner = Instance.new("UICorner")
	coinsCorner.CornerRadius = UDim.new(0, 12)
	coinsCorner.Parent = coinsCard

	local coinsStroke = Instance.new("UIStroke")
	coinsStroke.Color = Color3.fromRGB(246, 198, 68)
	coinsStroke.Thickness = 1.6
	coinsStroke.Parent = coinsCard

	local coinIcon = Instance.new("TextLabel")
	coinIcon.Name = "CoinIcon"
	coinIcon.AnchorPoint = Vector2.new(0, 0.5)
	coinIcon.Position = UDim2.new(0, 8, 0.5, 0)
	coinIcon.Size = UDim2.fromOffset(26, 26)
	coinIcon.BackgroundColor3 = Color3.fromRGB(248, 194, 48)
	coinIcon.BorderSizePixel = 0
	coinIcon.Font = Enum.Font.GothamBlack
	coinIcon.TextSize = 14
	coinIcon.TextColor3 = Color3.fromRGB(62, 42, 8)
	coinIcon.Text = "C"
	coinIcon.Parent = coinsCard

	local coinIconCorner = Instance.new("UICorner")
	coinIconCorner.CornerRadius = UDim.new(1, 0)
	coinIconCorner.Parent = coinIcon

	local coinsLbl = Instance.new("TextLabel")
	coinsLbl.Name = "CoinsValue"
	coinsLbl.Position = UDim2.fromOffset(42, 0)
	coinsLbl.Size = UDim2.new(1, -112, 1, 0)
	coinsLbl.BackgroundTransparency = 1
	coinsLbl.Font = Enum.Font.GothamBlack
	coinsLbl.TextSize = 17
	coinsLbl.TextXAlignment = Enum.TextXAlignment.Left
	coinsLbl.TextColor3 = Color3.fromRGB(255, 224, 102)
	coinsLbl.Text = "100"
	coinsLbl.Parent = coinsCard
	coinsTextLabel = coinsLbl

	local incomeLbl = Instance.new("TextLabel")
	incomeLbl.Name = "IncomePerSecond"
	incomeLbl.AnchorPoint = Vector2.new(1, 0.5)
	incomeLbl.Position = UDim2.new(1, -8, 0.5, 0)
	incomeLbl.Size = UDim2.fromOffset(66, 20)
	incomeLbl.BackgroundTransparency = 1
	incomeLbl.Font = Enum.Font.GothamBold
	incomeLbl.TextSize = 11
	incomeLbl.TextColor3 = Color3.fromRGB(80, 227, 120)
	incomeLbl.TextXAlignment = Enum.TextXAlignment.Right
	incomeLbl.Text = "+0/dtk"
	incomeLbl.Visible = false
	incomeLbl.Parent = coinsCard
	incomeTextLabel = incomeLbl

	-- 2. Bag Capacity Pill (e.g. Tas 12/20 + Lv.1 + fill bar)
	local bagCard = Instance.new("Frame")
	bagCard.Name = "BagPill"
	bagCard.Size = UDim2.fromOffset(186, 44)
	bagCard.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
	bagCard.BackgroundTransparency = 0.08
	bagCard.BorderSizePixel = 0
	bagCard.LayoutOrder = 2
	bagCard.Parent = cluster

	local bagCorner = Instance.new("UICorner")
	bagCorner.CornerRadius = UDim.new(0, 12)
	bagCorner.Parent = bagCard

	local bStroke = Instance.new("UIStroke")
	bStroke.Color = Color3.fromRGB(98, 112, 142)
	bStroke.Thickness = 1.5
	bStroke.Parent = bagCard
	bagStrokeInst = bStroke

	local bagLbl = Instance.new("TextLabel")
	bagLbl.Name = "BagValue"
	bagLbl.Position = UDim2.fromOffset(12, 4)
	bagLbl.Size = UDim2.new(1, -60, 0, 22)
	bagLbl.BackgroundTransparency = 1
	bagLbl.Font = Enum.Font.GothamBlack
	bagLbl.TextSize = 14
	bagLbl.TextXAlignment = Enum.TextXAlignment.Left
	bagLbl.TextColor3 = Color3.fromRGB(244, 247, 252)
	bagLbl.Text = "Tas 0/20"
	bagLbl.Parent = bagCard
	bagTextLabel = bagLbl

	local lvBadge = Instance.new("TextLabel")
	lvBadge.Name = "BagLevelBadge"
	lvBadge.AnchorPoint = Vector2.new(1, 0)
	lvBadge.Position = UDim2.new(1, -8, 0, 6)
	lvBadge.Size = UDim2.fromOffset(40, 18)
	lvBadge.BackgroundColor3 = Color3.fromRGB(44, 52, 72)
	lvBadge.BorderSizePixel = 0
	lvBadge.Font = Enum.Font.GothamBold
	lvBadge.TextSize = 11
	lvBadge.TextColor3 = Color3.fromRGB(190, 204, 232)
	lvBadge.Text = "Lv.1"
	lvBadge.Parent = bagCard
	bagLevelBadge = lvBadge

	local lvCorner = Instance.new("UICorner")
	lvCorner.CornerRadius = UDim.new(0, 5)
	lvCorner.Parent = lvBadge

	local barTrack = Instance.new("Frame")
	barTrack.Name = "BarTrack"
	barTrack.Position = UDim2.fromOffset(10, 30)
	barTrack.Size = UDim2.new(1, -20, 0, 7)
	barTrack.BackgroundColor3 = Color3.fromRGB(16, 19, 26)
	barTrack.BorderSizePixel = 0
	barTrack.Parent = bagCard

	local barTrackCorner = Instance.new("UICorner")
	barTrackCorner.CornerRadius = UDim.new(1, 0)
	barTrackCorner.Parent = barTrack

	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = Color3.fromRGB(72, 198, 128)
	barFill.BorderSizePixel = 0
	barFill.Parent = barTrack
	bagFillFrame = barFill

	local barFillCorner = Instance.new("UICorner")
	barFillCorner.CornerRadius = UDim.new(1, 0)
	barFillCorner.Parent = barFill

	-- 3. Egg Bag Pill (Click to open Incubator)
	local eggCard = Instance.new("TextButton")
	eggCard.Name = "EggPill"
	eggCard.Size = UDim2.fromOffset(146, 30)
	eggCard.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
	eggCard.BackgroundTransparency = 0.14
	eggCard.BorderSizePixel = 0
	eggCard.Text = ""
	eggCard.AutoButtonColor = true
	eggCard.LayoutOrder = 3
	eggCard.Parent = cluster

	local eggCorner = Instance.new("UICorner")
	eggCorner.CornerRadius = UDim.new(0, 9)
	eggCorner.Parent = eggCard

	local eggStroke = Instance.new("UIStroke")
	eggStroke.Color = Color3.fromRGB(82, 94, 120)
	eggStroke.Thickness = 1.2
	eggStroke.Parent = eggCard

	local eggLbl = Instance.new("TextLabel")
	eggLbl.Name = "EggValue"
	eggLbl.Position = UDim2.fromOffset(10, 0)
	eggLbl.Size = UDim2.new(1, -16, 1, 0)
	eggLbl.BackgroundTransparency = 1
	eggLbl.Font = Enum.Font.GothamBold
	eggLbl.TextSize = 12
	eggLbl.TextXAlignment = Enum.TextXAlignment.Left
	eggLbl.TextColor3 = Color3.fromRGB(205, 214, 232)
	eggLbl.Text = "Telur 0/5"
	eggLbl.Parent = eggCard
	eggTextLabel = eggLbl

	eggCard.Activated:Connect(function()
		local controllers = script.Parent
		local baseCtrl = controllers and controllers:FindFirstChild("BaseController")
		if baseCtrl then
			local BaseController = require(baseCtrl)
			BaseController.OpenIncubatorModal(1)
		end
	end)

	-- Top-center Drop Notification Feed
	local dropContainer = Instance.new("Frame")
	dropContainer.Name = "DropBannerContainer"
	dropContainer.AnchorPoint = Vector2.new(0.5, 0)
	dropContainer.Position = UDim2.new(0.5, 0, 0, 14)
	dropContainer.Size = UDim2.fromOffset(346, 190)
	dropContainer.BackgroundTransparency = 1
	dropContainer.Parent = gui
	dropBannerContainer = dropContainer

	local dropListLayout = Instance.new("UIListLayout")
	dropListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	dropListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	dropListLayout.Padding = UDim.new(0, 6)
	dropListLayout.Parent = dropContainer

	syncFromAttributes(false)
end

function HudController.IsBagFull(): boolean
	return bagCountValue >= bagCapacityValue
end

function HudController.GetBagStatus(): (number, number)
	return bagCountValue, bagCapacityValue
end

function HudController.Start()
	if started then
		return
	end
	started = true

	buildHudGui()

	local function bindCameraViewport()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveScale)
			updateResponsiveScale()
		end
	end
	bindCameraViewport()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCameraViewport)

	for _, attrName in { "Coins", "BagItemCount", "BagCapacity", "BagLevel", "EggCount", "EggCapacity", "IncomePerSecond" } do
		LocalPlayer:GetAttributeChangedSignal(attrName):Connect(function()
			syncFromAttributes(attrName == "Coins")
		end)
	end

	Remotes.GetEvent("StateSync").OnClientEvent:Connect(function(payload: any)
		if type(payload) == "table" then
			if type(payload.Coins) == "number" then
				local changed = payload.Coins ~= coinsValue
				coinsValue = payload.Coins
				refreshHudVisuals(changed)
			end
		end
		syncFromAttributes(false)
	end)

	Remotes.GetEvent("DropNotification").OnClientEvent:Connect(function(summary: any)
		HudController.ShowDropSummary(summary)
	end)
end

return HudController
