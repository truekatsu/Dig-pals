--!strict
-- Persistent coin wallet and drop notifications. Bag data remains available to gameplay.

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
local coinCluster: Frame? = nil
local dropScale: UIScale? = nil
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
	if dropScale then dropScale.Scale = uiScale.Scale end
	if coinCluster then
		-- On narrow screens place the wallet above the centered hotbar.
		coinCluster.Position = UDim2.new(0, 20, 1, if vp.X < 1120 then -114 else -24)
	end
end

local function refreshHudVisuals(animateCoinPop: boolean?)
	if coinsTextLabel then
		coinsTextLabel.Text = Format.Money(coinsValue, true)
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
				"Tas Telur Penuh! Otomatis dijual +$%s",
				Format.Commas(tonumber(drop.AutoSoldCoins) or 0)
			)
		else
			subLabel.TextColor3 = rarityColor
			if drop.DropType == "Item" and type(drop.Weight) == "number" then
				subLabel.Text = string.format("%.2f kg • %s | Nilai: $%s", drop.Weight, tostring(drop.WeightClass or "Wajar"), Format.Commas(tonumber(drop.SellPrice) or 0))
			else
				subLabel.Text = string.format("%s | Nilai Jual: $%s", rarityName, Format.Commas(tonumber(drop.SellPrice) or 0))
			end
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

	-- Bottom-left wallet; capacity indicators are intentionally omitted.
	local cluster = Instance.new("Frame")
	cluster.Name = "BottomLeftWallet"
	cluster.AnchorPoint = Vector2.new(0, 1)
	cluster.Position = UDim2.new(0, 20, 1, -24)
	cluster.Size = UDim2.fromOffset(260, 64)
	cluster.BackgroundTransparency = 1
	cluster.Parent = gui
	coinCluster = cluster
	scaleInst.Parent = cluster

	local clusterLayout = Instance.new("UIListLayout")
	clusterLayout.SortOrder = Enum.SortOrder.LayoutOrder
	clusterLayout.Padding = UDim.new(0, 7)
	clusterLayout.Parent = cluster

	-- 1. Coins Pill
	local coinsCard = Instance.new("Frame")
	coinsCard.Name = "CoinsPill"
	coinsCard.Size = UDim2.fromOffset(260, 64)
	coinsCard.BackgroundColor3 = Color3.fromRGB(255, 239, 196)
	coinsCard.BackgroundTransparency = 1
	coinsCard.BorderSizePixel = 0
	coinsCard.LayoutOrder = 1
	coinsCard.Parent = cluster

	local cScale = Instance.new("UIScale")
	cScale.Parent = coinsCard
	coinsScaleInst = cScale

	local coinsLbl = Instance.new("TextLabel")
	coinsLbl.Name = "CoinsValue"
	coinsLbl.Position = UDim2.fromOffset(6, 0)
	coinsLbl.Size = UDim2.new(1, -12, 0, 56)
	coinsLbl.BackgroundTransparency = 1
	coinsLbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
	coinsLbl.TextSize = 48
	coinsLbl.TextScaled = true
	coinsLbl.TextXAlignment = Enum.TextXAlignment.Left
	coinsLbl.TextColor3 = Color3.fromRGB(115, 239, 0)
	coinsLbl.TextStrokeTransparency = 1
	coinsLbl.Text = "$0"
	coinsLbl.Parent = coinsCard
	local cashOutline = Instance.new("UIStroke")
	cashOutline.Color = Color3.fromRGB(9, 22, 7)
	cashOutline.Thickness = 4
	cashOutline.LineJoinMode = Enum.LineJoinMode.Round
	cashOutline.Parent = coinsLbl
	local valueLimit = Instance.new("UITextSizeConstraint")
	valueLimit.MinTextSize = 24
	valueLimit.MaxTextSize = 48
	valueLimit.Parent = coinsLbl
	coinsTextLabel = coinsLbl

	local incomeLbl = Instance.new("TextLabel")
	incomeLbl.Name = "IncomePerSecond"
	incomeLbl.AnchorPoint = Vector2.new(0, 0)
	incomeLbl.Position = UDim2.fromOffset(10, 53)
	incomeLbl.Size = UDim2.new(1, -20, 0, 16)
	incomeLbl.BackgroundTransparency = 1
	incomeLbl.Font = Enum.Font.GothamBold
	incomeLbl.TextSize = 11
	incomeLbl.TextColor3 = Color3.fromRGB(160, 242, 183)
	incomeLbl.TextStrokeColor3 = Color3.fromRGB(26, 44, 49)
	incomeLbl.TextStrokeTransparency = 0
	incomeLbl.TextXAlignment = Enum.TextXAlignment.Left
	incomeLbl.Text = "+0/dtk"
	incomeLbl.Visible = false
	incomeLbl.Parent = coinsCard
	incomeTextLabel = incomeLbl

	-- Top-center Drop Notification Feed
	local dropContainer = Instance.new("Frame")
	dropContainer.Name = "DropBannerContainer"
	dropContainer.AnchorPoint = Vector2.new(0.5, 0)
	dropContainer.Position = UDim2.new(0.5, 0, 0, 14)
	dropContainer.Size = UDim2.fromOffset(346, 190)
	dropContainer.BackgroundTransparency = 1
	dropContainer.Parent = gui
	local feedScale = Instance.new("UIScale")
	feedScale.Parent = dropContainer
	dropScale = feedScale
	dropBannerContainer = dropContainer

	local dropListLayout = Instance.new("UIListLayout")
	dropListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	dropListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	dropListLayout.Padding = UDim.new(0, 6)
	dropListLayout.Parent = dropContainer

	updateResponsiveScale()
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
