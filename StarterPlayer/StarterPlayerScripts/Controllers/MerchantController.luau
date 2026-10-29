--!strict
local CurrencyStyle = require(script.Parent:WaitForChild("CurrencyStyle"))
-- Client UI controller for Hub & Base Item Merchant: per-item sell, sell all, and BagLevel upgrades (Step 6)

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local EconomyConfig = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))
local ItemsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Items"))
local RarityConfig = require(Shared:WaitForChild("Config"):WaitForChild("Rarity"))

local InventoryController = require(script.Parent:WaitForChild("InventoryController"))

local LocalPlayer = Players.LocalPlayer

local MerchantController = {}

local COLORS = {
	PanelBg = Color3.fromRGB(24, 27, 36),
	PanelBorder = Color3.fromRGB(118, 132, 162),
	HeaderBg = Color3.fromRGB(30, 34, 46),
	ListBg = Color3.fromRGB(20, 23, 31),
	RowBg = Color3.fromRGB(31, 36, 48),
	DetailBg = Color3.fromRGB(31, 38, 52),
	CardInnerBg = Color3.fromRGB(23, 28, 40),

	BtnSellOne = Color3.fromRGB(54, 118, 196),
	BtnSellStack = Color3.fromRGB(44, 168, 102),
	BtnSellAll = Color3.fromRGB(46, 178, 106),
	BtnUpgrade = Color3.fromRGB(232, 164, 44),
	BtnDisabled = Color3.fromRGB(50, 58, 74),

	TextPrimary = Color3.fromRGB(244, 247, 252),
	TextSecondary = Color3.fromRGB(178, 188, 208),
	TextMuted = Color3.fromRGB(122, 132, 152),
	TextGold = Color3.fromRGB(255, 220, 96),
	TextSuccess = Color3.fromRGB(112, 238, 154),
	TextError = Color3.fromRGB(252, 112, 112),
}

local MAX_OPEN_DISTANCE = 27

-- State
local isOpen = false
local isBusy = false
local activeAnchorPart: BasePart? = nil
local merchantTitle: string = "ITEM MERCHANT"
local itemsMap: { [string]: number } = {}
local coinsBalance: number = EconomyConfig.StartingCoins
local bagLevel: number = 1
local started = false

-- UI references
local screenGui: ScreenGui? = nil
local uiScale: UIScale? = nil
local backdropButton: TextButton? = nil
local panelFrame: Frame? = nil
local headerTitleLabel: TextLabel? = nil
local headerCoinsPill: TextLabel? = nil
local headerBagPill: TextLabel? = nil
local itemListScroll: ScrollingFrame? = nil
local emptyStateLabel: TextLabel? = nil

local summaryCountLabel: TextLabel? = nil
local summaryValueLabel: TextLabel? = nil
local sellAllButton: TextButton? = nil

local upgradeLevelLabel: TextLabel? = nil
local upgradeCapLabel: TextLabel? = nil
local upgradeBarFill: Frame? = nil
local upgradeCostLabel: TextLabel? = nil
local upgradeButton: TextButton? = nil
local statusBannerLabel: TextLabel? = nil

local function getRarityOrderIndex(rarityName: string): number
	local info = (RarityConfig.ById :: any)[rarityName]
	return if info then info.Index else 1
end

local function getRarityColor(rarityName: string): Color3
	local info = (RarityConfig.ById :: any)[rarityName]
	return if info then info.Color else RarityConfig.ById.Common.Color
end

local function updateResponsiveScale()
	if not uiScale then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local vp = cam.ViewportSize
	local scaleW = vp.X / 920
	local scaleH = vp.Y / 660
	uiScale.Scale = math.clamp(math.min(1, scaleW, scaleH), 0.55, 1.0)
end

local function setStatusBanner(message: string?, isError: boolean?)
	if not statusBannerLabel then
		return
	end
	if message and #message > 0 then
		statusBannerLabel.Text = message
		statusBannerLabel.TextColor3 = if isError then COLORS.TextError else COLORS.TextSuccess
		statusBannerLabel.Visible = true
	else
		statusBannerLabel.Text = ""
		statusBannerLabel.Visible = false
	end
end

local function computeBagTotals(): (number, number)
	local totalCount = 0
	local totalValue = 0
	for itemId, count in itemsMap do
		local cfg = ItemsConfig.All[itemId]
		if cfg and count > 0 then
			totalCount += count
			totalValue += count * cfg.SellPrice
		end
	end
	return totalCount, totalValue
end

local function refreshRightSummaryAndHeader()
	local totalCount, totalValue = computeBagTotals()
	local curBagCfg = EconomyConfig.BagLevels[bagLevel] or EconomyConfig.BagLevels[1]
	local bagCap = curBagCfg.Capacity

	if headerTitleLabel then
		headerTitleLabel.Text = merchantTitle
	end
	if headerCoinsPill then
		headerCoinsPill.Text = Format.Money(coinsBalance)
	end
	if headerBagPill then
		headerBagPill.Text = string.format("Tas %d/%d | Lv.%d", totalCount, bagCap, bagLevel)
	end

	if summaryCountLabel then
		summaryCountLabel.Text = string.format("Total di Tas: %d / %d Item", totalCount, bagCap)
	end
	if summaryValueLabel then
		summaryValueLabel.Text = string.format("Total Nilai Jual: +$%s", Format.Commas(totalValue))
	end

	if sellAllButton then
		if isBusy then
			sellAllButton.Text = "MEMPROSES..."
			sellAllButton.BackgroundColor3 = COLORS.BtnDisabled
			sellAllButton.TextColor3 = COLORS.TextSecondary
			sellAllButton.Active = false
			sellAllButton.AutoButtonColor = false
		elseif totalCount > 0 then
			sellAllButton.Text = string.format("JUAL SEMUA (+$%s)", Format.Commas(totalValue))
			sellAllButton.BackgroundColor3 = COLORS.BtnSellAll
			sellAllButton.TextColor3 = COLORS.TextPrimary
			sellAllButton.Active = true
			sellAllButton.AutoButtonColor = true
		else
			sellAllButton.Text = "TAS MASIH KOSONG"
			sellAllButton.BackgroundColor3 = COLORS.BtnDisabled
			sellAllButton.TextColor3 = COLORS.TextMuted
			sellAllButton.Active = false
			sellAllButton.AutoButtonColor = false
		end
	end

	-- Upgrade Bag Card
	local maxLv = EconomyConfig.MaxBagLevel
	if upgradeLevelLabel then
		upgradeLevelLabel.Text = string.format("Level Tas Saat Ini: Lv.%d / %d", bagLevel, maxLv)
	end
	if upgradeBarFill then
		upgradeBarFill.Size = UDim2.fromScale(math.clamp(bagLevel / maxLv, 0.1, 1), 1)
	end

	if bagLevel >= maxLv then
		if upgradeCapLabel then
			upgradeCapLabel.Text = string.format("Kapasitas Maksimal: %d Item", bagCap)
		end
		if upgradeCostLabel then
			upgradeCostLabel.Text = "Semua level tas sudah terbuka!"
			upgradeCostLabel.TextColor3 = COLORS.TextSuccess
		end
		if upgradeButton then
			upgradeButton.Text = "LEVEL MAKSIMAL"
			upgradeButton.BackgroundColor3 = COLORS.BtnDisabled
			upgradeButton.TextColor3 = COLORS.TextSecondary
			upgradeButton.Active = false
			upgradeButton.AutoButtonColor = false
		end
	else
		local nextCfg = EconomyConfig.BagLevels[bagLevel + 1]
		local cost = if nextCfg then nextCfg.UpgradeCost else 0
		local nextCap = if nextCfg then nextCfg.Capacity else bagCap
		local canAfford = coinsBalance >= cost

		if upgradeCapLabel then
			upgradeCapLabel.Text = string.format("Kapasitas: %d Item  ->  %d Item", bagCap, nextCap)
		end
		if upgradeCostLabel then
			upgradeCostLabel.Text = string.format("Biaya Upgrade: $%s", Format.Commas(cost))
			upgradeCostLabel.TextColor3 = if canAfford then COLORS.TextGold else COLORS.TextError
		end
		if upgradeButton then
			if isBusy then
				upgradeButton.Text = "MEMPROSES..."
				upgradeButton.BackgroundColor3 = COLORS.BtnDisabled
				upgradeButton.TextColor3 = COLORS.TextSecondary
				upgradeButton.Active = false
				upgradeButton.AutoButtonColor = false
			elseif canAfford then
				upgradeButton.Text = string.format("UPGRADE TAS ($%s)", Format.Commas(cost))
				upgradeButton.BackgroundColor3 = COLORS.BtnUpgrade
				upgradeButton.TextColor3 = Color3.fromRGB(36, 24, 6)
				upgradeButton.Active = true
				upgradeButton.AutoButtonColor = true
			else
				upgradeButton.Text = string.format("UANG KURANG ($%s)", Format.Commas(cost))
				upgradeButton.BackgroundColor3 = COLORS.BtnDisabled
				upgradeButton.TextColor3 = COLORS.TextMuted
				upgradeButton.Active = false
				upgradeButton.AutoButtonColor = false
			end
		end
	end
end

local function rebuildItemRows()
	if not itemListScroll then
		return
	end

	for _, child in itemListScroll:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local sortedEntries: { { Config: any, Count: number } } = {}
	for itemId, count in itemsMap do
		local cfg = ItemsConfig.All[itemId]
		if cfg and count > 0 then
			table.insert(sortedEntries, {
				Config = cfg,
				Count = count,
			})
		end
	end

	table.sort(sortedEntries, function(a, b): boolean
		local rA = getRarityOrderIndex(a.Config.Rarity)
		local rB = getRarityOrderIndex(b.Config.Rarity)
		if rA ~= rB then
			return rA > rB
		end
		if a.Config.SellPrice ~= b.Config.SellPrice then
			return a.Config.SellPrice > b.Config.SellPrice
		end
		return a.Config.Id < b.Config.Id
	end)

	if emptyStateLabel then
		emptyStateLabel.Visible = (#sortedEntries == 0)
	end

	for index, entry in sortedEntries do
		local cfg = entry.Config
		local count = entry.Count
		local rarityColor = getRarityColor(cfg.Rarity)
		local unitPrice = cfg.SellPrice
		local stackValue = count * unitPrice

		local row = Instance.new("Frame")
		row.Name = "ItemRow_" .. cfg.Id
		row.Size = UDim2.new(1, -6, 0, 68)
		row.BackgroundColor3 = COLORS.RowBg
		row.BorderSizePixel = 0
		row.LayoutOrder = index
		row.Parent = itemListScroll

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 10)
		rowCorner.Parent = row

		local rowStroke = Instance.new("UIStroke")
		rowStroke.Color = rarityColor
		rowStroke.Thickness = 1.2
		rowStroke.Transparency = 0.45
		rowStroke.Parent = row

		local qtyBadge = Instance.new("TextLabel")
		qtyBadge.Name = "QtyBadge"
		qtyBadge.AnchorPoint = Vector2.new(0, 0.5)
		qtyBadge.Position = UDim2.new(0, 8, 0.5, 0)
		qtyBadge.Size = UDim2.fromOffset(48, 48)
		qtyBadge.BackgroundColor3 = Color3.fromRGB(22, 26, 36)
		qtyBadge.BorderSizePixel = 0
		qtyBadge.Font = Enum.Font.GothamBlack
		qtyBadge.TextSize = 15
		qtyBadge.TextColor3 = rarityColor
		qtyBadge.Text = string.format("x%d", count)
		qtyBadge.Parent = row

		local qtyCorner = Instance.new("UICorner")
		qtyCorner.CornerRadius = UDim.new(0, 8)
		qtyCorner.Parent = qtyBadge

		local qtyStroke = Instance.new("UIStroke")
		qtyStroke.Color = rarityColor
		qtyStroke.Thickness = 1.2
		qtyStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		qtyStroke.Parent = qtyBadge

		local rightReserve = if count > 1 then 176 else 96

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Name = "ItemName"
		nameLbl.Position = UDim2.fromOffset(64, 10)
		nameLbl.Size = UDim2.new(1, -(64 + rightReserve), 0, 22)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.TextSize = 15
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.TextColor3 = rarityColor
		nameLbl.Text = cfg.DisplayName
		nameLbl.Parent = row

		local subLbl = Instance.new("TextLabel")
		subLbl.Name = "PriceInfo"
		subLbl.Position = UDim2.fromOffset(64, 34)
		subLbl.Size = UDim2.new(1, -(64 + rightReserve), 0, 18)
		subLbl.BackgroundTransparency = 1
		subLbl.Font = Enum.Font.GothamMedium
		subLbl.TextSize = 11
		subLbl.TextXAlignment = Enum.TextXAlignment.Left
		subLbl.TextTruncate = Enum.TextTruncate.AtEnd
		subLbl.TextColor3 = COLORS.TextSecondary
		subLbl.Text = string.format("%s | $%s", cfg.Rarity, Format.Commas(unitPrice))
		subLbl.Parent = row

		local sellOneBtn = Instance.new("TextButton")
		sellOneBtn.Name = "SellOneButton"
		sellOneBtn.AnchorPoint = Vector2.new(1, 0.5)
		sellOneBtn.Position = if count > 1 then UDim2.new(1, -92, 0.5, 0) else UDim2.new(1, -8, 0.5, 0)
		sellOneBtn.Size = if count > 1 then UDim2.fromOffset(76, 44) else UDim2.fromOffset(82, 44)
		sellOneBtn.BackgroundColor3 = COLORS.BtnSellOne
		sellOneBtn.BorderSizePixel = 0
		sellOneBtn.Font = Enum.Font.GothamBlack
		sellOneBtn.TextSize = 11
		sellOneBtn.TextColor3 = COLORS.TextPrimary
		sellOneBtn.Text = string.format("Jual 1\n+%s", Format.Commas(unitPrice))
		sellOneBtn.Active = not isBusy
		sellOneBtn.Parent = row

		local s1Corner = Instance.new("UICorner")
		s1Corner.CornerRadius = UDim.new(0, 8)
		s1Corner.Parent = sellOneBtn

		sellOneBtn.Activated:Connect(function()
			if not isBusy then
				task.spawn(function()
					MerchantController.RequestSellItem(cfg.Id, 1)
				end)
			end
		end)

		if count > 1 then
			local sellStackBtn = Instance.new("TextButton")
			sellStackBtn.Name = "SellStackButton"
			sellStackBtn.AnchorPoint = Vector2.new(1, 0.5)
			sellStackBtn.Position = UDim2.new(1, -8, 0.5, 0)
			sellStackBtn.Size = UDim2.fromOffset(78, 44)
			sellStackBtn.BackgroundColor3 = COLORS.BtnSellStack
			sellStackBtn.BorderSizePixel = 0
			sellStackBtn.Font = Enum.Font.GothamBlack
			sellStackBtn.TextSize = 11
			sellStackBtn.TextColor3 = COLORS.TextPrimary
			sellStackBtn.Text = string.format("Jual x%d\n+%s", count, Format.Commas(stackValue))
			sellStackBtn.Active = not isBusy
			sellStackBtn.Parent = row

			local sStackCorner = Instance.new("UICorner")
			sStackCorner.CornerRadius = UDim.new(0, 8)
			sStackCorner.Parent = sellStackBtn

			sellStackBtn.Activated:Connect(function()
				if not isBusy then
					task.spawn(function()
						MerchantController.RequestSellItem(cfg.Id, count)
					end)
				end
			end)
		end
	end

	refreshRightSummaryAndHeader()
end

local function applySnapshotPayload(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if type(payload.Coins) == "number" then
		coinsBalance = payload.Coins
	end
	if type(payload.BagLevel) == "number" then
		bagLevel = payload.BagLevel
	end
	if type(payload.Items) == "table" then
		local nextItems: { [string]: number } = {}
		for k, v in payload.Items do
			if type(k) == "string" and type(v) == "number" and v > 0 and ItemsConfig.All[k] ~= nil then
				nextItems[k] = math.floor(v)
			end
		end
		itemsMap = nextItems
	end

	rebuildItemRows()
end

function MerchantController.IsOpen(): boolean
	return isOpen
end

function MerchantController.OpenPanel(anchorPart: BasePart?, customTitle: string?)
	if InventoryController.IsOpen() then
		InventoryController.ClosePanel()
	end

	isOpen = true
	LocalPlayer:SetAttribute("ActiveShopModal", "Merchant")
	activeAnchorPart = anchorPart
	merchantTitle = customTitle or "ITEM MERCHANT"
	setStatusBanner(nil, false)

	if backdropButton then
		backdropButton.Visible = true
	end
	if panelFrame then
		panelFrame.Visible = true
	end

	rebuildItemRows()
end

function MerchantController.ClosePanel()
	if not isOpen then
		return
	end
	isOpen = false
	if LocalPlayer:GetAttribute("ActiveShopModal") == "Merchant" then
		LocalPlayer:SetAttribute("ActiveShopModal", "")
	end
	activeAnchorPart = nil
	setStatusBanner(nil, false)

	if backdropButton then
		backdropButton.Visible = false
	end
	if panelFrame then
		panelFrame.Visible = false
	end
end

function MerchantController.RequestSellItem(itemId: string, count: number): (boolean, string?)
	if isBusy then
		return false, "Sedang memproses..."
	end
	isBusy = true
	refreshRightSummaryAndHeader()

	local ok, response = pcall(function()
		return Remotes.GetFunction("SellItem"):InvokeServer(itemId, count)
	end)

	isBusy = false

	if not ok or type(response) ~= "table" then
		local msg = "Gagal menghubungi Merchant."
		setStatusBanner(msg, true)
		refreshRightSummaryAndHeader()
		return false, msg
	end

	if response.Success == true then
		local earned = tonumber(response.CoinsEarned) or 0
		local sold = tonumber(response.SoldCount) or count
		local cfg = ItemsConfig.All[itemId]
		local name = if cfg then cfg.DisplayName else itemId
		setStatusBanner(string.format("Terjual %dx %s (+$%s)!", sold, name, Format.Commas(earned)), false)
		refreshRightSummaryAndHeader()
		return true, nil
	else
		local errMsg = tostring(response.Message or response.Reason or "Gagal menjual item.")
		setStatusBanner(errMsg, true)
		refreshRightSummaryAndHeader()
		return false, errMsg
	end
end

function MerchantController.RequestSellAll(): (boolean, string?)
	if isBusy then
		return false, "Sedang memproses..."
	end
	isBusy = true
	refreshRightSummaryAndHeader()

	local ok, response = pcall(function()
		return Remotes.GetFunction("SellAllItems"):InvokeServer()
	end)

	isBusy = false

	if not ok or type(response) ~= "table" then
		local msg = "Gagal menghubungi Merchant."
		setStatusBanner(msg, true)
		refreshRightSummaryAndHeader()
		return false, msg
	end

	if response.Success == true then
		local earned = tonumber(response.CoinsEarned) or 0
		local sold = tonumber(response.SoldCount) or 0
		setStatusBanner(string.format("Berhasil menjual %d item (+$%s)!", sold, Format.Commas(earned)), false)
		refreshRightSummaryAndHeader()
		return true, nil
	else
		local errMsg = tostring(response.Message or response.Reason or "Gagal menjual semua item.")
		setStatusBanner(errMsg, true)
		refreshRightSummaryAndHeader()
		return false, errMsg
	end
end

function MerchantController.RequestUpgradeBag(): (boolean, string?)
	if isBusy then
		return false, "Sedang memproses..."
	end
	isBusy = true
	refreshRightSummaryAndHeader()

	local ok, response = pcall(function()
		return Remotes.GetFunction("UpgradeBag"):InvokeServer()
	end)

	isBusy = false

	if not ok or type(response) ~= "table" then
		local msg = "Gagal menghubungi server."
		setStatusBanner(msg, true)
		refreshRightSummaryAndHeader()
		return false, msg
	end

	if response.Success == true then
		local newLv = tonumber(response.NewBagLevel) or bagLevel
		local newCap = tonumber(response.NewCapacity) or 40
		bagLevel = newLv
		setStatusBanner(string.format("Tas naik ke Level %d (Kapasitas %d Item)!", newLv, newCap), false)
		refreshRightSummaryAndHeader()
		return true, nil
	else
		local errMsg = tostring(response.Message or response.Reason or "Gagal upgrade tas.")
		setStatusBanner(errMsg, true)
		refreshRightSummaryAndHeader()
		return false, errMsg
	end
end

local function buildMerchantGui()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("MerchantGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "MerchantGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 11
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	screenGui = gui

	local scaleInst = Instance.new("UIScale")
	scaleInst.Name = "ResponsiveScale"
	scaleInst.Scale = 1
	scaleInst.Parent = gui
	uiScale = scaleInst
	updateResponsiveScale()

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "ModalBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
	backdrop.BackgroundTransparency = 0.45
	backdrop.BorderSizePixel = 0
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.Visible = false
	backdrop.ZIndex = 8
	backdrop.Parent = gui
	backdropButton = backdrop

	backdrop.Activated:Connect(function()
		MerchantController.ClosePanel()
	end)

	local panel = Instance.new("Frame")
	panel.Name = "MerchantPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.44, 0)
	panel.Size = UDim2.fromOffset(768, 484)
	panel.BackgroundColor3 = COLORS.PanelBg
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Active = true
	panel.ZIndex = 10
	panel.Parent = gui
	panelFrame = panel

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 14)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = COLORS.PanelBorder
	panelStroke.Thickness = 1.6
	panelStroke.Parent = panel

	-- Header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 50)
	header.BackgroundColor3 = COLORS.HeaderBg
	header.BorderSizePixel = 0
	header.ZIndex = 11
	header.Parent = panel

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 14)
	headerCorner.Parent = header

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Name = "Title"
	titleLbl.Position = UDim2.fromOffset(18, 0)
	titleLbl.Size = UDim2.fromOffset(250, 50)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Font = Enum.Font.GothamBlack
	titleLbl.TextSize = 18
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.TextColor3 = COLORS.TextGold
	titleLbl.Text = "ITEM MERCHANT"
	titleLbl.ZIndex = 12
	titleLbl.Parent = header
	headerTitleLabel = titleLbl

	local bagPill = Instance.new("TextLabel")
	bagPill.Name = "BagPill"
	bagPill.AnchorPoint = Vector2.new(1, 0.5)
	bagPill.Position = UDim2.new(1, -184, 0.5, 0)
	bagPill.Size = UDim2.fromOffset(132, 28)
	bagPill.BackgroundColor3 = Color3.fromRGB(40, 46, 64)
	bagPill.BorderSizePixel = 0
	bagPill.Font = Enum.Font.GothamBold
	bagPill.TextSize = 12
	bagPill.TextColor3 = COLORS.TextSecondary
	bagPill.Text = "Tas 0/20 | Lv.1"
	bagPill.ZIndex = 12
	bagPill.Parent = header
	headerBagPill = bagPill

	local bagPillCorner = Instance.new("UICorner")
	bagPillCorner.CornerRadius = UDim.new(1, 0)
	bagPillCorner.Parent = bagPill

	local coinsPill = Instance.new("TextLabel")
	coinsPill.Name = "CoinsPill"
	coinsPill.AnchorPoint = Vector2.new(1, 0.5)
	coinsPill.Position = UDim2.new(1, -58, 0.5, 0)
	coinsPill.Size = UDim2.fromOffset(118, 28)
	coinsPill.BackgroundColor3 = Color3.fromRGB(48, 42, 24)
	coinsPill.BorderSizePixel = 0
	coinsPill.Font = Enum.Font.GothamBlack
	coinsPill.TextSize = 12
	coinsPill.TextColor3 = COLORS.TextGold
	coinsPill.Text = "$100"
	coinsPill.ZIndex = 12
	coinsPill.Parent = header
	headerCoinsPill = coinsPill
	CurrencyStyle.Balance(coinsPill)

	local coinsPillCorner = Instance.new("UICorner")
	coinsPillCorner.CornerRadius = UDim.new(1, 0)
	coinsPillCorner.Parent = coinsPill

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -10, 0.5, 0)
	closeBtn.Size = UDim2.fromOffset(44, 44)
	closeBtn.BackgroundColor3 = Color3.fromRGB(205, 68, 76)
	closeBtn.BorderSizePixel = 0
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.TextSize = 18
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Text = "X"
	closeBtn.ZIndex = 12
	closeBtn.Parent = header

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 9)
	closeCorner.Parent = closeBtn

	closeBtn.Activated:Connect(function()
		MerchantController.ClosePanel()
	end)

	-- Left Column: Owned Item List
	local listContainer = Instance.new("Frame")
	listContainer.Name = "LeftListContainer"
	listContainer.Position = UDim2.fromOffset(14, 62)
	listContainer.Size = UDim2.new(0.54, -18, 1, -76)
	listContainer.BackgroundColor3 = COLORS.ListBg
	listContainer.BorderSizePixel = 0
	listContainer.ZIndex = 11
	listContainer.Parent = panel

	local listCorner = Instance.new("UICorner")
	listCorner.CornerRadius = UDim.new(0, 11)
	listCorner.Parent = listContainer

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "ItemList"
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = Color3.fromRGB(110, 124, 156)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.ZIndex = 12
	scroll.Parent = listContainer
	itemListScroll = scroll

	local listPad = Instance.new("UIPadding")
	listPad.PaddingTop = UDim.new(0, 8)
	listPad.PaddingBottom = UDim.new(0, 8)
	listPad.PaddingLeft = UDim.new(0, 8)
	listPad.PaddingRight = UDim.new(0, 8)
	listPad.Parent = scroll

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 7)
	listLayout.Parent = scroll

	local emptyLbl = Instance.new("TextLabel")
	emptyLbl.Name = "EmptyState"
	emptyLbl.AnchorPoint = Vector2.new(0.5, 0.5)
	emptyLbl.Position = UDim2.fromScale(0.5, 0.5)
	emptyLbl.Size = UDim2.new(0.84, 0, 0, 72)
	emptyLbl.BackgroundTransparency = 1
	emptyLbl.Font = Enum.Font.GothamMedium
	emptyLbl.TextSize = 14
	emptyLbl.TextWrapped = true
	emptyLbl.TextColor3 = COLORS.TextMuted
	emptyLbl.Text = "Tas item kamu masih kosong.\nGali gundukan tanah di Plain Grass lalu kembali ke sini untuk menjual hasil galian!"
	emptyLbl.ZIndex = 12
	emptyLbl.Parent = listContainer
	emptyStateLabel = emptyLbl

	-- Right Column: Sell All & Upgrade Bag Cards
	local rightCol = Instance.new("Frame")
	rightCol.Name = "RightActions"
	rightCol.AnchorPoint = Vector2.new(1, 0)
	rightCol.Position = UDim2.new(1, -14, 0, 62)
	rightCol.Size = UDim2.new(0.46, -18, 1, -76)
	rightCol.BackgroundColor3 = COLORS.DetailBg
	rightCol.BorderSizePixel = 0
	rightCol.ZIndex = 11
	rightCol.Parent = panel

	local rightCorner = Instance.new("UICorner")
	rightCorner.CornerRadius = UDim.new(0, 11)
	rightCorner.Parent = rightCol

	local rightStroke = Instance.new("UIStroke")
	rightStroke.Color = Color3.fromRGB(70, 84, 112)
	rightStroke.Thickness = 1.2
	rightStroke.Parent = rightCol

	local rightPad = Instance.new("UIPadding")
	rightPad.PaddingTop = UDim.new(0, 12)
	rightPad.PaddingBottom = UDim.new(0, 12)
	rightPad.PaddingLeft = UDim.new(0, 14)
	rightPad.PaddingRight = UDim.new(0, 14)
	rightPad.Parent = rightCol

	local rightLayout = Instance.new("UIListLayout")
	rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rightLayout.Padding = UDim.new(0, 10)
	rightLayout.Parent = rightCol

	-- Card 1: Sell All Summary
	local sellCard = Instance.new("Frame")
	sellCard.Name = "SellAllCard"
	sellCard.Size = UDim2.new(1, 0, 0, 152)
	sellCard.BackgroundColor3 = COLORS.CardInnerBg
	sellCard.BorderSizePixel = 0
	sellCard.LayoutOrder = 1
	sellCard.Parent = rightCol

	local sellCardCorner = Instance.new("UICorner")
	sellCardCorner.CornerRadius = UDim.new(0, 10)
	sellCardCorner.Parent = sellCard

	local sellTitle = Instance.new("TextLabel")
	sellTitle.Position = UDim2.fromOffset(12, 10)
	sellTitle.Size = UDim2.new(1, -24, 0, 20)
	sellTitle.BackgroundTransparency = 1
	sellTitle.Font = Enum.Font.GothamBlack
	sellTitle.TextSize = 14
	sellTitle.TextXAlignment = Enum.TextXAlignment.Left
	sellTitle.TextColor3 = COLORS.TextPrimary
	sellTitle.Text = "JUAL CEPAT SEMUA ITEM"
	sellTitle.Parent = sellCard

	local sCount = Instance.new("TextLabel")
	sCount.Name = "SummaryCount"
	sCount.Position = UDim2.fromOffset(12, 36)
	sCount.Size = UDim2.new(1, -24, 0, 18)
	sCount.BackgroundTransparency = 1
	sCount.Font = Enum.Font.GothamMedium
	sCount.TextSize = 12
	sCount.TextXAlignment = Enum.TextXAlignment.Left
	sCount.TextColor3 = COLORS.TextSecondary
	sCount.Text = "Total di Tas: 0 / 20 Item"
	sCount.Parent = sellCard
	summaryCountLabel = sCount

	local sVal = Instance.new("TextLabel")
	sVal.Name = "SummaryValue"
	sVal.Position = UDim2.fromOffset(12, 58)
	sVal.Size = UDim2.new(1, -24, 0, 20)
	sVal.BackgroundTransparency = 1
	sVal.Font = Enum.Font.GothamBlack
	sVal.TextSize = 14
	sVal.TextXAlignment = Enum.TextXAlignment.Left
	sVal.TextColor3 = COLORS.TextGold
	sVal.Text = "Total Nilai Jual: +$0"
	sVal.Parent = sellCard
	summaryValueLabel = sVal

	local sAllBtn = Instance.new("TextButton")
	sAllBtn.Name = "SellAllButton"
	sAllBtn.AnchorPoint = Vector2.new(0.5, 1)
	sAllBtn.Position = UDim2.new(0.5, 0, 1, -12)
	sAllBtn.Size = UDim2.new(1, -24, 0, 46)
	sAllBtn.BackgroundColor3 = COLORS.BtnDisabled
	sAllBtn.BorderSizePixel = 0
	sAllBtn.Font = Enum.Font.GothamBlack
	sAllBtn.TextSize = 14
	sAllBtn.TextColor3 = COLORS.TextMuted
	sAllBtn.Text = "TAS MASIH KOSONG"
	sAllBtn.Parent = sellCard
	sellAllButton = sAllBtn

	local sAllCorner = Instance.new("UICorner")
	sAllCorner.CornerRadius = UDim.new(0, 10)
	sAllCorner.Parent = sAllBtn

	sAllBtn.Activated:Connect(function()
		if sAllBtn.Active then
			task.spawn(function()
				MerchantController.RequestSellAll()
			end)
		end
	end)

	-- Card 2: Upgrade Bag Capacity
	local upgCard = Instance.new("Frame")
	upgCard.Name = "UpgradeBagCard"
	upgCard.Size = UDim2.new(1, 0, 0, 190)
	upgCard.BackgroundColor3 = COLORS.CardInnerBg
	upgCard.BorderSizePixel = 0
	upgCard.LayoutOrder = 2
	upgCard.Parent = rightCol

	local upgCorner = Instance.new("UICorner")
	upgCorner.CornerRadius = UDim.new(0, 10)
	upgCorner.Parent = upgCard

	local upgTitle = Instance.new("TextLabel")
	upgTitle.Position = UDim2.fromOffset(12, 10)
	upgTitle.Size = UDim2.new(1, -24, 0, 20)
	upgTitle.BackgroundTransparency = 1
	upgTitle.Font = Enum.Font.GothamBlack
	upgTitle.TextSize = 14
	upgTitle.TextXAlignment = Enum.TextXAlignment.Left
	upgTitle.TextColor3 = COLORS.TextPrimary
	upgTitle.Text = "UPGRADE KAPASITAS TAS"
	upgTitle.Parent = upgCard

	local uLv = Instance.new("TextLabel")
	uLv.Name = "UpgradeLevel"
	uLv.Position = UDim2.fromOffset(12, 34)
	uLv.Size = UDim2.new(1, -24, 0, 18)
	uLv.BackgroundTransparency = 1
	uLv.Font = Enum.Font.GothamBold
	uLv.TextSize = 12
	uLv.TextXAlignment = Enum.TextXAlignment.Left
	uLv.TextColor3 = COLORS.TextSecondary
	uLv.Text = "Level Tas Saat Ini: Lv.1 / 5"
	uLv.Parent = upgCard
	upgradeLevelLabel = uLv

	local uTrack = Instance.new("Frame")
	uTrack.Position = UDim2.fromOffset(12, 58)
	uTrack.Size = UDim2.new(1, -24, 0, 9)
	uTrack.BackgroundColor3 = Color3.fromRGB(14, 18, 26)
	uTrack.BorderSizePixel = 0
	uTrack.Parent = upgCard

	local uTrackCorner = Instance.new("UICorner")
	uTrackCorner.CornerRadius = UDim.new(1, 0)
	uTrackCorner.Parent = uTrack

	local uFill = Instance.new("Frame")
	uFill.Name = "LevelFill"
	uFill.Size = UDim2.fromScale(0.2, 1)
	uFill.BackgroundColor3 = COLORS.BtnUpgrade
	uFill.BorderSizePixel = 0
	uFill.Parent = uTrack
	upgradeBarFill = uFill

	local uFillCorner = Instance.new("UICorner")
	uFillCorner.CornerRadius = UDim.new(1, 0)
	uFillCorner.Parent = uFill

	local uCap = Instance.new("TextLabel")
	uCap.Name = "UpgradeCap"
	uCap.Position = UDim2.fromOffset(12, 74)
	uCap.Size = UDim2.new(1, -24, 0, 20)
	uCap.BackgroundTransparency = 1
	uCap.Font = Enum.Font.GothamBlack
	uCap.TextSize = 13
	uCap.TextXAlignment = Enum.TextXAlignment.Left
	uCap.TextColor3 = Color3.fromRGB(116, 214, 255)
	uCap.Text = "Kapasitas: 20 Item  ->  40 Item"
	uCap.Parent = upgCard
	upgradeCapLabel = uCap

	local uCost = Instance.new("TextLabel")
	uCost.Name = "UpgradeCost"
	uCost.Position = UDim2.fromOffset(12, 96)
	uCost.Size = UDim2.new(1, -24, 0, 18)
	uCost.BackgroundTransparency = 1
	uCost.Font = Enum.Font.GothamBold
	uCost.TextSize = 12
	uCost.TextXAlignment = Enum.TextXAlignment.Left
	uCost.TextColor3 = COLORS.TextGold
	uCost.Text = "Biaya Upgrade: $300"
	uCost.Parent = upgCard
	upgradeCostLabel = uCost

	local upgBtn = Instance.new("TextButton")
	upgBtn.Name = "UpgradeBagButton"
	upgBtn.AnchorPoint = Vector2.new(0.5, 1)
	upgBtn.Position = UDim2.new(0.5, 0, 1, -12)
	upgBtn.Size = UDim2.new(1, -24, 0, 46)
	upgBtn.BackgroundColor3 = COLORS.BtnDisabled
	upgBtn.BorderSizePixel = 0
	upgBtn.Font = Enum.Font.GothamBlack
	upgBtn.TextSize = 14
	upgBtn.TextColor3 = COLORS.TextMuted
	upgBtn.Text = "UPGRADE TAS ($300)"
	upgBtn.Parent = upgCard
	upgradeButton = upgBtn

	local upgBtnCorner = Instance.new("UICorner")
	upgBtnCorner.CornerRadius = UDim.new(0, 10)
	upgBtnCorner.Parent = upgBtn

	upgBtn.Activated:Connect(function()
		if upgBtn.Active then
			task.spawn(function()
				MerchantController.RequestUpgradeBag()
			end)
		end
	end)

	-- Status Feedback Banner
	local banner = Instance.new("TextLabel")
	banner.Name = "StatusBanner"
	banner.Size = UDim2.new(1, 0, 0, 26)
	banner.BackgroundTransparency = 1
	banner.Font = Enum.Font.GothamBold
	banner.TextSize = 12
	banner.TextWrapped = true
	banner.TextColor3 = COLORS.TextSuccess
	banner.Text = ""
	banner.Visible = false
	banner.LayoutOrder = 3
	banner.Parent = rightCol
	statusBannerLabel = banner

	rebuildItemRows()
end

local function findMerchantAnchorFromPrompt(prompt: ProximityPrompt): BasePart?
	local cur: Instance? = prompt.Parent
	while cur and cur ~= workspace do
		if cur:IsA("BasePart") and cur:GetAttribute("DigPalsMerchantNode") == true then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

function MerchantController.Start()
	if started then
		return
	end
	started = true

	local attrCoins = LocalPlayer:GetAttribute("Coins")
	if type(attrCoins) == "number" then
		coinsBalance = attrCoins
	end
	local attrBagLv = LocalPlayer:GetAttribute("BagLevel")
	if type(attrBagLv) == "number" then
		bagLevel = attrBagLv
	end

	buildMerchantGui()

	local function bindCameraViewport()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveScale)
			updateResponsiveScale()
		end
	end
	bindCameraViewport()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCameraViewport)

	LocalPlayer:GetAttributeChangedSignal("Coins"):Connect(function()
		local c = LocalPlayer:GetAttribute("Coins")
		if type(c) == "number" then
			coinsBalance = c
			refreshRightSummaryAndHeader()
		end
	end)

	LocalPlayer:GetAttributeChangedSignal("BagLevel"):Connect(function()
		local lv = LocalPlayer:GetAttribute("BagLevel")
		if type(lv) == "number" then
			bagLevel = lv
			refreshRightSummaryAndHeader()
		end
	end)

	Remotes.GetEvent("StateSync").OnClientEvent:Connect(function(payload: any)
		applySnapshotPayload(payload)
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, playerWhoTriggered: Player)
		if playerWhoTriggered ~= LocalPlayer then
			return
		end
		local anchor = findMerchantAnchorFromPrompt(prompt)
		if anchor then
			local loc = tostring(anchor:GetAttribute("MerchantLocation") or "Hub")
			local title = if string.find(loc, "^Base") then "BASE MERCHANT" else "ITEM MERCHANT"
			MerchantController.OpenPanel(anchor, title)
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, _gameProcessed: boolean)
		if UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape and isOpen then
			MerchantController.ClosePanel()
		end
	end)

	RunService.Heartbeat:Connect(function()
		if not isOpen then
			return
		end
		-- Mutual exclusion if player opened ShovelInventoryPanel or ShovelShopPanel
		if InventoryController.IsOpen() or LocalPlayer:GetAttribute("ActiveShopModal") == "ShovelShop" then
			MerchantController.ClosePanel()
			return
		end
		if activeAnchorPart and activeAnchorPart.Parent ~= nil then
			local char = LocalPlayer.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local dx = root.Position.X - activeAnchorPart.Position.X
				local dz = root.Position.Z - activeAnchorPart.Position.Z
				if math.sqrt(dx * dx + dz * dz) > MAX_OPEN_DISTANCE then
					MerchantController.ClosePanel()
				end
			end
		end
	end)

	task.spawn(function()
		local ok, initialSnapshot = pcall(function()
			return Remotes.GetFunction("GetInventoryState"):InvokeServer()
		end)
		if ok and type(initialSnapshot) == "table" then
			applySnapshotPayload(initialSnapshot)
		end
	end)
end

return MerchantController
