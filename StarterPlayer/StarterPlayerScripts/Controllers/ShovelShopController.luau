--!strict
-- Client UI controller for Hub Shovel Shop: 5 shop shovels with 3D previews, stats comparison, non-sequential purchase [U], and equip (Step 7)

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local EconomyConfig = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))
local RarityConfig = require(Shared:WaitForChild("Config"):WaitForChild("Rarity"))
local ShovelsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Shovels"))
local ShovelModelBuilder = require(Shared:WaitForChild("ShovelModelBuilder"))

local InventoryController = require(script.Parent:WaitForChild("InventoryController"))
local MerchantController = require(script.Parent:WaitForChild("MerchantController"))

local LocalPlayer = Players.LocalPlayer

local ShovelShopController = {}

local COLORS = {
	PanelBg = Color3.fromRGB(22, 27, 38),
	PanelBorder = Color3.fromRGB(96, 178, 232),
	HeaderBg = Color3.fromRGB(26, 34, 48),
	ListBg = Color3.fromRGB(18, 22, 32),
	RowBg = Color3.fromRGB(29, 36, 50),
	RowHover = Color3.fromRGB(38, 48, 66),
	RowSelectedBg = Color3.fromRGB(40, 56, 82),
	RowSelectedBorder = Color3.fromRGB(96, 212, 255),

	DetailBg = Color3.fromRGB(28, 36, 52),
	ViewportBg = Color3.fromRGB(18, 24, 36),
	StatTrackBg = Color3.fromRGB(15, 19, 28),

	StatPower = Color3.fromRGB(245, 148, 62),
	StatSpeed = Color3.fromRGB(72, 196, 248),
	StatLuck = Color3.fromRGB(82, 216, 132),

	BtnBuy = Color3.fromRGB(38, 168, 224),
	BtnEquip = Color3.fromRGB(46, 178, 106),
	BtnDisabled = Color3.fromRGB(48, 56, 72),

	BadgeEquippedBg = Color3.fromRGB(38, 142, 86),
	BadgeOwnedBg = Color3.fromRGB(48, 68, 96),
	BadgePriceAffordableBg = Color3.fromRGB(58, 48, 22),
	BadgePriceLockedBg = Color3.fromRGB(52, 38, 44),

	TextPrimary = Color3.fromRGB(244, 248, 255),
	TextSecondary = Color3.fromRGB(178, 190, 212),
	TextMuted = Color3.fromRGB(122, 134, 156),
	TextCyan = Color3.fromRGB(108, 220, 255),
	TextGold = Color3.fromRGB(255, 220, 96),
	TextSuccess = Color3.fromRGB(112, 238, 154),
	TextError = Color3.fromRGB(252, 112, 112),
}

local MAX_OPEN_DISTANCE = 27

-- State
local isOpen = false
local isBusy = false
local activeAnchorPart: BasePart? = nil
local ownedShovels: { string } = { EconomyConfig.StartingShovel }
local equippedShovelId: string = EconomyConfig.StartingShovel
local selectedShovelId: string = "StoneShovel"
local coinsBalance: number = EconomyConfig.StartingCoins
local detailSpinYaw: number = 0
local isDraggingPreview: boolean = false
local lastDragX: number = 0
local started = false

-- UI references
local screenGui: ScreenGui? = nil
local uiScale: UIScale? = nil
local backdropButton: TextButton? = nil
local panelFrame: Frame? = nil
local headerOwnedPill: TextLabel? = nil
local headerCoinsPill: TextLabel? = nil
local shopListScroll: ScrollingFrame? = nil
local rowRefsById: {
	[string]: {
		Button: TextButton,
		Stroke: UIStroke,
		Badge: TextLabel,
	},
} = {}

local detailViewport: ViewportFrame? = nil
local detailPreviewModel: Model? = nil
local detailPreviewShovelId: string? = nil
local detailNameLabel: TextLabel? = nil
local detailRarityBadge: TextLabel? = nil
local detailPriceOrStateLabel: TextLabel? = nil
local detailDescLabel: TextLabel? = nil

local powerValueLabel: TextLabel? = nil
local powerFillFrame: Frame? = nil
local speedValueLabel: TextLabel? = nil
local speedFillFrame: Frame? = nil
local luckValueLabel: TextLabel? = nil
local luckFillFrame: Frame? = nil

local statusBannerLabel: TextLabel? = nil
local actionButton: TextButton? = nil

local function getRarityColor(rarityName: string): Color3
	local info = (RarityConfig.ById :: any)[rarityName]
	return if info then info.Color else RarityConfig.ById.Common.Color
end

local function isShovelOwned(shovelId: string): boolean
	return table.find(ownedShovels, shovelId) ~= nil
end

local function countOwnedShopShovels(): number
	local count = 0
	for _, shovelId in ShovelsConfig.ShopOrder do
		if isShovelOwned(shovelId) then
			count += 1
		end
	end
	return count
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
	local scaleW = vp.X / 940
	local scaleH = vp.Y / 680
	uiScale.Scale = math.clamp(math.min(1, scaleW, scaleH), 0.72, 1.0)
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

local function populateViewportWithShovel(viewport: ViewportFrame, shovelId: string, cameraDist: number): Model
	for _, child in viewport:GetChildren() do
		if child:IsA("WorldModel") or child:IsA("Model") or child:IsA("Camera") then
			child:Destroy()
		end
	end

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport

	local preview = ShovelModelBuilder.ClonePreviewModel(shovelId)
	preview:PivotTo(CFrame.Angles(math.rad(10), math.rad(22), math.rad(-36)))
	preview.Parent = worldModel

	local cam = Instance.new("Camera")
	cam.FieldOfView = 36
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 0.05, cameraDist), Vector3.new(0, 0.02, 0))
	cam.Parent = viewport
	viewport.CurrentCamera = cam

	return preview
end

local function formatDelta(diff: number, fmt: string, invertGood: boolean?): string
	if math.abs(diff) < 1e-4 then
		return ""
	end
	local sign = if diff > 0 then "+" else ""
	local good = if invertGood then (diff < 0) else (diff > 0)
	local tag = string.format(" (%s" .. fmt .. ")", sign, diff)
	if good then
		return tag
	end
	return tag
end

local function refreshHeaderAndRowBadges()
	if headerOwnedPill then
		headerOwnedPill.Text = string.format("Koleksi Toko: %d / %d", countOwnedShopShovels(), #ShovelsConfig.ShopOrder)
	end
	if headerCoinsPill then
		headerCoinsPill.Text = string.format("%s Coin", Format.Commas(coinsBalance))
	end

	for _, shovelId in ShovelsConfig.ShopOrder do
		local refs = rowRefsById[shovelId]
		local cfg = ShovelsConfig.All[shovelId]
		if refs and cfg then
			local selected = (selectedShovelId == shovelId)
			local owned = isShovelOwned(shovelId)
			local equipped = (equippedShovelId == shovelId)

			refs.Button.BackgroundColor3 = if selected then COLORS.RowSelectedBg else COLORS.RowBg
			refs.Stroke.Color = if selected then COLORS.RowSelectedBorder else getRarityColor(cfg.Rarity)
			refs.Stroke.Thickness = if selected then 2.0 else 1.1
			refs.Stroke.Transparency = if selected then 0 else 0.45

			if equipped then
				refs.Badge.Text = "DIPAKAI"
				refs.Badge.BackgroundColor3 = COLORS.BadgeEquippedBg
				refs.Badge.TextColor3 = COLORS.TextPrimary
			elseif owned then
				refs.Badge.Text = "DIMILIKI"
				refs.Badge.BackgroundColor3 = COLORS.BadgeOwnedBg
				refs.Badge.TextColor3 = COLORS.TextSecondary
			else
				local canAfford = coinsBalance >= cfg.Price
				refs.Badge.Text = string.format("%s C", Format.Commas(cfg.Price))
				refs.Badge.BackgroundColor3 = if canAfford
					then COLORS.BadgePriceAffordableBg
					else COLORS.BadgePriceLockedBg
				refs.Badge.TextColor3 = if canAfford then COLORS.TextGold else COLORS.TextError
			end
		end
	end
end

local function refreshDetailPane()
	local cfg = ShovelsConfig.All[selectedShovelId] or ShovelsConfig.All.RustyShovel
	local eqCfg = ShovelsConfig.All[equippedShovelId] or ShovelsConfig.All.RustyShovel
	local rarityColor = getRarityColor(cfg.Rarity)
	local owned = isShovelOwned(cfg.Id)
	local equipped = (equippedShovelId == cfg.Id)

	if detailViewport and detailPreviewShovelId ~= cfg.Id then
		detailPreviewModel = populateViewportWithShovel(detailViewport, cfg.Id, 5.6)
		detailPreviewShovelId = cfg.Id
		detailSpinYaw = 0
	end

	if detailNameLabel then
		detailNameLabel.Text = cfg.DisplayName
		detailNameLabel.TextColor3 = rarityColor
	end

	if detailRarityBadge then
		detailRarityBadge.Text = string.upper(cfg.Rarity)
		detailRarityBadge.BackgroundColor3 = rarityColor
	end

	if detailPriceOrStateLabel then
		if equipped then
			detailPriceOrStateLabel.Text = "Status: Sedang Dipakai"
			detailPriceOrStateLabel.TextColor3 = COLORS.TextSuccess
		elseif owned then
			detailPriceOrStateLabel.Text = "Status: Sudah Dimiliki"
			detailPriceOrStateLabel.TextColor3 = COLORS.TextCyan
		elseif cfg.Price <= 0 then
			detailPriceOrStateLabel.Text = "Sekop Awal (Gratis)"
			detailPriceOrStateLabel.TextColor3 = COLORS.TextSecondary
		else
			local canAfford = coinsBalance >= cfg.Price
			detailPriceOrStateLabel.Text = string.format("Harga: %s Coin", Format.Commas(cfg.Price))
			detailPriceOrStateLabel.TextColor3 = if canAfford then COLORS.TextGold else COLORS.TextError
		end
	end

	if detailDescLabel then
		detailDescLabel.Text = cfg.Description
	end

	-- Stat bars compared against ShovelsConfig.MaxStats + delta vs currently equipped shovel
	local maxStats = ShovelsConfig.MaxStats
	local powerRatio = math.clamp(cfg.Power / maxStats.Power, 0.06, 1)
	local digRate = 1 / math.max(0.1, cfg.DigSpeed)
	local speedRatio = math.clamp(digRate / maxStats.DigRate, 0.06, 1)
	local luckRatio = math.clamp(cfg.Luck / maxStats.Luck, 0.06, 1)

	if powerValueLabel then
		local deltaStr = if cfg.Id ~= eqCfg.Id then formatDelta(cfg.Power - eqCfg.Power, "%d", false) else ""
		powerValueLabel.Text = string.format("%d%s", cfg.Power, deltaStr)
	end
	if powerFillFrame then
		powerFillFrame.Size = UDim2.fromScale(powerRatio, 1)
	end

	if speedValueLabel then
		local deltaStr = if cfg.Id ~= eqCfg.Id then formatDelta(cfg.DigSpeed - eqCfg.DigSpeed, "%.2fs", true) else ""
		speedValueLabel.Text = string.format("%.2fs%s", cfg.DigSpeed, deltaStr)
	end
	if speedFillFrame then
		speedFillFrame.Size = UDim2.fromScale(speedRatio, 1)
	end

	if luckValueLabel then
		local deltaStr = if cfg.Id ~= eqCfg.Id then formatDelta(cfg.Luck - eqCfg.Luck, "%.2fx", false) else ""
		luckValueLabel.Text = string.format("%.2fx%s", cfg.Luck, deltaStr)
	end
	if luckFillFrame then
		luckFillFrame.Size = UDim2.fromScale(luckRatio, 1)
	end

	if actionButton then
		if isBusy then
			actionButton.Text = "MEMPROSES..."
			actionButton.BackgroundColor3 = COLORS.BtnDisabled
			actionButton.TextColor3 = COLORS.TextSecondary
			actionButton.Active = false
			actionButton.AutoButtonColor = false
		elseif equipped then
			actionButton.Text = "SEDANG DIPAKAI"
			actionButton.BackgroundColor3 = COLORS.BtnDisabled
			actionButton.TextColor3 = COLORS.TextSecondary
			actionButton.Active = false
			actionButton.AutoButtonColor = false
		elseif owned then
			actionButton.Text = "PAKAI SHOVEL"
			actionButton.BackgroundColor3 = COLORS.BtnEquip
			actionButton.TextColor3 = COLORS.TextPrimary
			actionButton.Active = true
			actionButton.AutoButtonColor = true
		elseif coinsBalance >= cfg.Price then
			actionButton.Text = string.format("BELI & PAKAI (%s Coin)", Format.Commas(cfg.Price))
			actionButton.BackgroundColor3 = COLORS.BtnBuy
			actionButton.TextColor3 = COLORS.TextPrimary
			actionButton.Active = true
			actionButton.AutoButtonColor = true
		else
			actionButton.Text = string.format("COIN KURANG (%s Coin)", Format.Commas(cfg.Price))
			actionButton.BackgroundColor3 = COLORS.BtnDisabled
			actionButton.TextColor3 = COLORS.TextMuted
			actionButton.Active = false
			actionButton.AutoButtonColor = false
		end
	end
end

local function refreshAllShopVisuals()
	refreshHeaderAndRowBadges()
	refreshDetailPane()
end

local function applySnapshotPayload(payload: any)
	if type(payload) ~= "table" then
		return
	end

	if type(payload.Coins) == "number" then
		coinsBalance = payload.Coins
	end

	if type(payload.OwnedShovels) == "table" and #payload.OwnedShovels > 0 then
		local nextOwned: { string } = {}
		for _, id in payload.OwnedShovels do
			if type(id) == "string" and ShovelsConfig.All[id] ~= nil then
				table.insert(nextOwned, id)
			end
		end
		if #nextOwned > 0 then
			ownedShovels = nextOwned
		end
	end

	if type(payload.EquippedShovel) == "string" and ShovelsConfig.All[payload.EquippedShovel] ~= nil then
		equippedShovelId = payload.EquippedShovel
	end

	refreshAllShopVisuals()
end

function ShovelShopController.IsOpen(): boolean
	return isOpen
end

function ShovelShopController.SelectShovel(shovelId: string)
	if ShovelsConfig.All[shovelId] == nil then
		return
	end
	selectedShovelId = shovelId
	setStatusBanner(nil)
	refreshAllShopVisuals()
end

function ShovelShopController.OpenPanel(anchorPart: BasePart?)
	if InventoryController.IsOpen() then
		InventoryController.ClosePanel()
	end
	if MerchantController.IsOpen() then
		MerchantController.ClosePanel()
	end

	activeAnchorPart = anchorPart
	isOpen = true
	LocalPlayer:SetAttribute("ActiveShopModal", "ShovelShop")
	setStatusBanner(nil)

	-- Default selection to next unowned shop shovel if available, else currently equipped
	local chosenDefault: string? = nil
	for _, shovelId in ShovelsConfig.ShopOrder do
		if not isShovelOwned(shovelId) then
			chosenDefault = shovelId
			break
		end
	end
	selectedShovelId = chosenDefault or equippedShovelId

	if backdropButton then
		backdropButton.Visible = true
	end
	if panelFrame then
		panelFrame.Visible = true
	end

	refreshAllShopVisuals()

	task.spawn(function()
		local ok, snapshot = pcall(function()
			return Remotes.GetFunction("GetInventoryState"):InvokeServer()
		end)
		if ok and type(snapshot) == "table" then
			applySnapshotPayload(snapshot)
		end
	end)
end

function ShovelShopController.ClosePanel()
	if not isOpen then
		return
	end
	isOpen = false
	if LocalPlayer:GetAttribute("ActiveShopModal") == "ShovelShop" then
		LocalPlayer:SetAttribute("ActiveShopModal", "")
	end
	isDraggingPreview = false
	activeAnchorPart = nil
	if backdropButton then
		backdropButton.Visible = false
	end
	if panelFrame then
		panelFrame.Visible = false
	end
end

function ShovelShopController.RequestBuyOrEquipSelected()
	if isBusy then
		return
	end
	local targetId = selectedShovelId
	local cfg = ShovelsConfig.All[targetId]
	if not cfg then
		return
	end

	if equippedShovelId == targetId then
		return
	end

	isBusy = true
	setStatusBanner(nil)
	refreshAllShopVisuals()

	if isShovelOwned(targetId) then
		local ok, result = pcall(function()
			return Remotes.GetFunction("EquipShovel"):InvokeServer(targetId)
		end)
		isBusy = false
		if ok and type(result) == "table" and result.Success == true then
			if type(result.Equipped) == "string" then
				equippedShovelId = result.Equipped
			end
			if type(result.Owned) == "table" then
				ownedShovels = result.Owned
			end
			setStatusBanner(string.format("%s sekarang dipakai!", cfg.DisplayName), false)
		else
			local errMsg = if ok and type(result) == "table" and type(result.Message) == "string"
				then result.Message
				else "Gagal memakai shovel."
			setStatusBanner(errMsg, true)
		end
	else
		local ok, result = pcall(function()
			return Remotes.GetFunction("BuyShovel"):InvokeServer(targetId)
		end)
		isBusy = false
		if ok and type(result) == "table" and result.Success == true then
			if type(result.Coins) == "number" then
				coinsBalance = result.Coins
			end
			if type(result.Owned) == "table" then
				ownedShovels = result.Owned
			end
			if type(result.Equipped) == "string" then
				equippedShovelId = result.Equipped
			end
			setStatusBanner(string.format("Berhasil membeli & memakai %s!", cfg.DisplayName), false)
		else
			local errMsg = if ok and type(result) == "table" and type(result.Message) == "string"
				then result.Message
				else "Pembelian shovel ditolak."
			setStatusBanner(errMsg, true)
		end
	end

	refreshAllShopVisuals()
end

local function createStatBarRow(
	parent: Instance,
	order: number,
	labelTitle: string,
	barColor: Color3
): (TextLabel, Frame)
	local row = Instance.new("Frame")
	row.Name = "StatRow_" .. tostring(order)
	row.Size = UDim2.new(1, 0, 0, 32)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Parent = parent

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Position = UDim2.fromOffset(0, 0)
	nameLbl.Size = UDim2.new(0.48, 0, 0, 16)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = Enum.Font.GothamBold
	nameLbl.TextSize = 12
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.TextColor3 = COLORS.TextSecondary
	nameLbl.Text = labelTitle
	nameLbl.Parent = row

	local valLbl = Instance.new("TextLabel")
	valLbl.Name = "ValueLabel"
	valLbl.AnchorPoint = Vector2.new(1, 0)
	valLbl.Position = UDim2.fromScale(1, 0)
	valLbl.Size = UDim2.new(0.52, 0, 0, 16)
	valLbl.BackgroundTransparency = 1
	valLbl.Font = Enum.Font.GothamBlack
	valLbl.TextSize = 12
	valLbl.TextXAlignment = Enum.TextXAlignment.Right
	valLbl.TextColor3 = COLORS.TextPrimary
	valLbl.Text = "-"
	valLbl.Parent = row

	local track = Instance.new("Frame")
	track.Position = UDim2.fromOffset(0, 20)
	track.Size = UDim2.new(1, 0, 0, 8)
	track.BackgroundColor3 = COLORS.StatTrackBg
	track.BorderSizePixel = 0
	track.Parent = row

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0.25, 1)
	fill.BackgroundColor3 = barColor
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	return valLbl, fill
end

local function buildShopRows()
	if not shopListScroll then
		return
	end
	for _, child in shopListScroll:GetChildren() do
		if child:IsA("GuiButton") or child:IsA("Frame") then
			child:Destroy()
		end
	end
	table.clear(rowRefsById)

	for index, shovelId in ShovelsConfig.ShopOrder do
		local cfg = ShovelsConfig.All[shovelId]
		if cfg then
			local rarityColor = getRarityColor(cfg.Rarity)

			local row = Instance.new("TextButton")
			row.Name = "ShopRow_" .. cfg.Id
			row.Size = UDim2.new(1, -6, 0, 72)
			row.BackgroundColor3 = COLORS.RowBg
			row.BorderSizePixel = 0
			row.AutoButtonColor = false
			row.Text = ""
			row.LayoutOrder = index
			row.Parent = shopListScroll

			local rowCorner = Instance.new("UICorner")
			rowCorner.CornerRadius = UDim.new(0, 10)
			rowCorner.Parent = row

			local rowStroke = Instance.new("UIStroke")
			rowStroke.Color = rarityColor
			rowStroke.Thickness = 1.1
			rowStroke.Transparency = 0.45
			rowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			rowStroke.Parent = row

			local thumbVp = Instance.new("ViewportFrame")
			thumbVp.Name = "ThumbViewport"
			thumbVp.AnchorPoint = Vector2.new(0, 0.5)
			thumbVp.Position = UDim2.new(0, 8, 0.5, 0)
			thumbVp.Size = UDim2.fromOffset(52, 52)
			thumbVp.BackgroundColor3 = COLORS.ViewportBg
			thumbVp.BorderSizePixel = 0
			thumbVp.Ambient = Color3.fromRGB(185, 195, 215)
			thumbVp.LightColor = Color3.fromRGB(255, 252, 240)
			thumbVp.LightDirection = Vector3.new(-1, -1, -1)
			thumbVp.Parent = row

			local thumbCorner = Instance.new("UICorner")
			thumbCorner.CornerRadius = UDim.new(0, 8)
			thumbCorner.Parent = thumbVp

			local thumbStroke = Instance.new("UIStroke")
			thumbStroke.Color = rarityColor
			thumbStroke.Thickness = 1.2
			thumbStroke.Transparency = 0.35
			thumbStroke.Parent = thumbVp

			populateViewportWithShovel(thumbVp, cfg.Id, 5.5)

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Name = "ShovelName"
			nameLbl.Position = UDim2.fromOffset(68, 12)
			nameLbl.Size = UDim2.new(1, -166, 0, 22)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Font = Enum.Font.GothamBold
			nameLbl.TextSize = 15
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
			nameLbl.TextColor3 = rarityColor
			nameLbl.Text = cfg.DisplayName
			nameLbl.Parent = row

			local statsSub = Instance.new("TextLabel")
			statsSub.Name = "StatsSummary"
			statsSub.Position = UDim2.fromOffset(68, 36)
			statsSub.Size = UDim2.new(1, -166, 0, 18)
			statsSub.BackgroundTransparency = 1
			statsSub.Font = Enum.Font.GothamMedium
			statsSub.TextSize = 11
			statsSub.TextXAlignment = Enum.TextXAlignment.Left
			statsSub.TextTruncate = Enum.TextTruncate.AtEnd
			statsSub.TextColor3 = COLORS.TextSecondary
			statsSub.Text = string.format("Pwr %d • %.2fs • Luck %.2fx", cfg.Power, cfg.DigSpeed, cfg.Luck)
			statsSub.Parent = row

			local statusBadge = Instance.new("TextLabel")
			statusBadge.Name = "StatusBadge"
			statusBadge.AnchorPoint = Vector2.new(1, 0.5)
			statusBadge.Position = UDim2.new(1, -10, 0.5, 0)
			statusBadge.Size = UDim2.fromOffset(82, 26)
			statusBadge.BackgroundColor3 = COLORS.BadgeOwnedBg
			statusBadge.BorderSizePixel = 0
			statusBadge.Font = Enum.Font.GothamBlack
			statusBadge.TextSize = 11
			statusBadge.TextColor3 = COLORS.TextPrimary
			statusBadge.Text = "DIMILIKI"
			statusBadge.Parent = row

			local badgeCorner = Instance.new("UICorner")
			badgeCorner.CornerRadius = UDim.new(0, 7)
			badgeCorner.Parent = statusBadge

			row.MouseEnter:Connect(function()
				if selectedShovelId ~= cfg.Id then
					row.BackgroundColor3 = COLORS.RowHover
				end
			end)
			row.MouseLeave:Connect(function()
				if selectedShovelId ~= cfg.Id then
					row.BackgroundColor3 = COLORS.RowBg
				end
			end)
			row.Activated:Connect(function()
				ShovelShopController.SelectShovel(cfg.Id)
			end)

			rowRefsById[cfg.Id] = {
				Button = row,
				Stroke = rowStroke,
				Badge = statusBadge,
			}
		end
	end
end

local function buildShovelShopGui()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("ShovelShopGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "ShovelShopGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 15
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
		ShovelShopController.ClosePanel()
	end)

	local panel = Instance.new("Frame")
	panel.Name = "ShovelShopPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.44, 0)
	panel.Size = UDim2.fromOffset(776, 496)
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
	panelStroke.Thickness = 1.8
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
	titleLbl.TextColor3 = COLORS.TextCyan
	titleLbl.Text = "SHOVEL SHOP"
	titleLbl.ZIndex = 12
	titleLbl.Parent = header

	local ownedPill = Instance.new("TextLabel")
	ownedPill.Name = "OwnedPill"
	ownedPill.AnchorPoint = Vector2.new(1, 0.5)
	ownedPill.Position = UDim2.new(1, -188, 0.5, 0)
	ownedPill.Size = UDim2.fromOffset(144, 28)
	ownedPill.BackgroundColor3 = Color3.fromRGB(34, 48, 68)
	ownedPill.BorderSizePixel = 0
	ownedPill.Font = Enum.Font.GothamBold
	ownedPill.TextSize = 12
	ownedPill.TextColor3 = COLORS.TextSecondary
	ownedPill.Text = "Koleksi Toko: 1 / 5"
	ownedPill.ZIndex = 12
	ownedPill.Parent = header
	headerOwnedPill = ownedPill

	local ownedPillCorner = Instance.new("UICorner")
	ownedPillCorner.CornerRadius = UDim.new(1, 0)
	ownedPillCorner.Parent = ownedPill

	local coinsPill = Instance.new("TextLabel")
	coinsPill.Name = "CoinsPill"
	coinsPill.AnchorPoint = Vector2.new(1, 0.5)
	coinsPill.Position = UDim2.new(1, -58, 0.5, 0)
	coinsPill.Size = UDim2.fromOffset(122, 28)
	coinsPill.BackgroundColor3 = Color3.fromRGB(48, 42, 24)
	coinsPill.BorderSizePixel = 0
	coinsPill.Font = Enum.Font.GothamBlack
	coinsPill.TextSize = 12
	coinsPill.TextColor3 = COLORS.TextGold
	coinsPill.Text = "100 Coin"
	coinsPill.ZIndex = 12
	coinsPill.Parent = header
	headerCoinsPill = coinsPill

	local coinsPillCorner = Instance.new("UICorner")
	coinsPillCorner.CornerRadius = UDim.new(1, 0)
	coinsPillCorner.Parent = coinsPill

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -10, 0.5, 0)
	closeBtn.Size = UDim2.fromOffset(38, 38)
	closeBtn.BackgroundColor3 = Color3.fromRGB(205, 68, 76)
	closeBtn.BorderSizePixel = 0
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.TextSize = 16
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Text = "X"
	closeBtn.ZIndex = 12
	closeBtn.Parent = header

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 9)
	closeCorner.Parent = closeBtn

	closeBtn.Activated:Connect(function()
		ShovelShopController.ClosePanel()
	end)

	-- Left Column: 5 Shop Shovels
	local leftContainer = Instance.new("Frame")
	leftContainer.Name = "LeftShopList"
	leftContainer.Position = UDim2.fromOffset(14, 62)
	leftContainer.Size = UDim2.new(0.52, -18, 1, -76)
	leftContainer.BackgroundColor3 = COLORS.ListBg
	leftContainer.BorderSizePixel = 0
	leftContainer.ZIndex = 11
	leftContainer.Parent = panel

	local leftCorner = Instance.new("UICorner")
	leftCorner.CornerRadius = UDim.new(0, 11)
	leftCorner.Parent = leftContainer

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "ShovelList"
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = Color3.fromRGB(96, 148, 198)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.ZIndex = 12
	scroll.Parent = leftContainer
	shopListScroll = scroll

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

	-- Right Column: 3D Preview, Stats, & Buy/Equip Action
	local rightPane = Instance.new("Frame")
	rightPane.Name = "RightDetailPane"
	rightPane.AnchorPoint = Vector2.new(1, 0)
	rightPane.Position = UDim2.new(1, -14, 0, 62)
	rightPane.Size = UDim2.new(0.48, -18, 1, -76)
	rightPane.BackgroundColor3 = COLORS.DetailBg
	rightPane.BorderSizePixel = 0
	rightPane.ZIndex = 11
	rightPane.Parent = panel

	local rightCorner = Instance.new("UICorner")
	rightCorner.CornerRadius = UDim.new(0, 11)
	rightCorner.Parent = rightPane

	local rightStroke = Instance.new("UIStroke")
	rightStroke.Color = Color3.fromRGB(68, 92, 128)
	rightStroke.Thickness = 1.2
	rightStroke.Parent = rightPane

	-- 3D Viewport Preview Box
	local vpFrame = Instance.new("ViewportFrame")
	vpFrame.Name = "PreviewViewport"
	vpFrame.Position = UDim2.fromOffset(14, 12)
	vpFrame.Size = UDim2.new(1, -28, 0, 134)
	vpFrame.BackgroundColor3 = COLORS.ViewportBg
	vpFrame.BorderSizePixel = 0
	vpFrame.Ambient = Color3.fromRGB(190, 200, 220)
	vpFrame.LightColor = Color3.fromRGB(255, 252, 242)
	vpFrame.LightDirection = Vector3.new(-1, -1, -1)
	vpFrame.Active = true
	vpFrame.ZIndex = 12
	vpFrame.Parent = rightPane
	detailViewport = vpFrame

	local vpCorner = Instance.new("UICorner")
	vpCorner.CornerRadius = UDim.new(0, 10)
	vpCorner.Parent = vpFrame

	local vpHint = Instance.new("TextLabel")
	vpHint.AnchorPoint = Vector2.new(1, 1)
	vpHint.Position = UDim2.new(1, -8, 1, -4)
	vpHint.Size = UDim2.fromOffset(120, 16)
	vpHint.BackgroundTransparency = 1
	vpHint.Font = Enum.Font.GothamMedium
	vpHint.TextSize = 10
	vpHint.TextXAlignment = Enum.TextXAlignment.Right
	vpHint.TextColor3 = COLORS.TextMuted
	vpHint.Text = "Geser untuk putar 3D"
	vpHint.ZIndex = 13
	vpHint.Parent = vpFrame

	vpFrame.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			isDraggingPreview = true
			lastDragX = input.Position.X
		end
	end)
	vpFrame.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			isDraggingPreview = false
		end
	end)

	-- Title + Rarity Badge
	local dName = Instance.new("TextLabel")
	dName.Name = "DetailName"
	dName.Position = UDim2.fromOffset(14, 152)
	dName.Size = UDim2.new(1, -112, 0, 24)
	dName.BackgroundTransparency = 1
	dName.Font = Enum.Font.GothamBlack
	dName.TextSize = 18
	dName.TextXAlignment = Enum.TextXAlignment.Left
	dName.TextTruncate = Enum.TextTruncate.AtEnd
	dName.TextColor3 = COLORS.TextPrimary
	dName.Text = "Stone Shovel"
	dName.ZIndex = 12
	dName.Parent = rightPane
	detailNameLabel = dName

	local rBadge = Instance.new("TextLabel")
	rBadge.Name = "RarityBadge"
	rBadge.AnchorPoint = Vector2.new(1, 0)
	rBadge.Position = UDim2.new(1, -14, 0, 154)
	rBadge.Size = UDim2.fromOffset(86, 20)
	rBadge.BackgroundColor3 = RarityConfig.ById.Uncommon.Color
	rBadge.BorderSizePixel = 0
	rBadge.Font = Enum.Font.GothamBlack
	rBadge.TextSize = 10
	rBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
	rBadge.Text = "UNCOMMON"
	rBadge.ZIndex = 12
	rBadge.Parent = rightPane
	detailRarityBadge = rBadge

	local rBadgeCorner = Instance.new("UICorner")
	rBadgeCorner.CornerRadius = UDim.new(0, 6)
	rBadgeCorner.Parent = rBadge

	local priceState = Instance.new("TextLabel")
	priceState.Name = "PriceOrStateLabel"
	priceState.Position = UDim2.fromOffset(14, 176)
	priceState.Size = UDim2.new(1, -28, 0, 18)
	priceState.BackgroundTransparency = 1
	priceState.Font = Enum.Font.GothamBold
	priceState.TextSize = 12
	priceState.TextXAlignment = Enum.TextXAlignment.Left
	priceState.TextColor3 = COLORS.TextGold
	priceState.Text = "Harga: 400 Coin"
	priceState.ZIndex = 12
	priceState.Parent = rightPane
	detailPriceOrStateLabel = priceState

	local desc = Instance.new("TextLabel")
	desc.Name = "Description"
	desc.Position = UDim2.fromOffset(14, 196)
	desc.Size = UDim2.new(1, -28, 0, 34)
	desc.BackgroundTransparency = 1
	desc.Font = Enum.Font.GothamMedium
	desc.TextSize = 11
	desc.TextWrapped = true
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextColor3 = COLORS.TextSecondary
	desc.Text = ""
	desc.ZIndex = 12
	desc.Parent = rightPane
	detailDescLabel = desc

	-- Stats Container
	local statsBox = Instance.new("Frame")
	statsBox.Name = "StatsBox"
	statsBox.Position = UDim2.fromOffset(14, 234)
	statsBox.Size = UDim2.new(1, -28, 0, 108)
	statsBox.BackgroundTransparency = 1
	statsBox.ZIndex = 12
	statsBox.Parent = rightPane

	local statsLayout = Instance.new("UIListLayout")
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Padding = UDim.new(0, 5)
	statsLayout.Parent = statsBox

	powerValueLabel, powerFillFrame = createStatBarRow(statsBox, 1, "Power (Damage)", COLORS.StatPower)
	speedValueLabel, speedFillFrame = createStatBarRow(statsBox, 2, "Jeda Gali (Cooldown)", COLORS.StatSpeed)
	luckValueLabel, luckFillFrame = createStatBarRow(statsBox, 3, "Luck", COLORS.StatLuck)

	-- Status Banner
	local sBanner = Instance.new("TextLabel")
	sBanner.Name = "StatusBanner"
	sBanner.AnchorPoint = Vector2.new(0.5, 1)
	sBanner.Position = UDim2.new(0.5, 0, 1, -62)
	sBanner.Size = UDim2.new(1, -28, 0, 18)
	sBanner.BackgroundTransparency = 1
	sBanner.Font = Enum.Font.GothamBold
	sBanner.TextSize = 11
	sBanner.TextTruncate = Enum.TextTruncate.AtEnd
	sBanner.TextColor3 = COLORS.TextSuccess
	sBanner.Text = ""
	sBanner.Visible = false
	sBanner.ZIndex = 12
	sBanner.Parent = rightPane
	statusBannerLabel = sBanner

	-- Primary Action Button (Buy & Equip / Equip / Equipped / Insufficient Coins)
	local actBtn = Instance.new("TextButton")
	actBtn.Name = "ActionButton"
	actBtn.AnchorPoint = Vector2.new(0.5, 1)
	actBtn.Position = UDim2.new(0.5, 0, 1, -12)
	actBtn.Size = UDim2.new(1, -28, 0, 46)
	actBtn.BackgroundColor3 = COLORS.BtnBuy
	actBtn.BorderSizePixel = 0
	actBtn.Font = Enum.Font.GothamBlack
	actBtn.TextSize = 14
	actBtn.TextColor3 = COLORS.TextPrimary
	actBtn.Text = "BELI & PAKAI"
	actBtn.ZIndex = 12
	actBtn.Parent = rightPane
	actionButton = actBtn

	local actCorner = Instance.new("UICorner")
	actCorner.CornerRadius = UDim.new(0, 10)
	actCorner.Parent = actBtn

	actBtn.Activated:Connect(function()
		if actBtn.Active then
			task.spawn(function()
				ShovelShopController.RequestBuyOrEquipSelected()
			end)
		end
	end)

	buildShopRows()
	refreshAllShopVisuals()
end

local function findShopAnchorFromPrompt(prompt: ProximityPrompt): BasePart?
	local cur: Instance? = prompt.Parent
	while cur and cur ~= workspace do
		if cur:IsA("BasePart") and cur:GetAttribute("DigPalsShovelShopNode") == true then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

function ShovelShopController.Start()
	if started then
		return
	end
	started = true

	local attrCoins = LocalPlayer:GetAttribute("Coins")
	if type(attrCoins) == "number" then
		coinsBalance = attrCoins
	end
	local attrEquipped = LocalPlayer:GetAttribute("EquippedShovel")
	if type(attrEquipped) == "string" and ShovelsConfig.All[attrEquipped] ~= nil then
		equippedShovelId = attrEquipped
	end

	buildShovelShopGui()

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
			refreshAllShopVisuals()
		end
	end)

	LocalPlayer:GetAttributeChangedSignal("EquippedShovel"):Connect(function()
		local eq = LocalPlayer:GetAttribute("EquippedShovel")
		if type(eq) == "string" and ShovelsConfig.All[eq] ~= nil then
			equippedShovelId = eq
			if not isShovelOwned(eq) then
				table.insert(ownedShovels, eq)
			end
			refreshAllShopVisuals()
		end
	end)

	Remotes.GetEvent("StateSync").OnClientEvent:Connect(function(payload: any)
		applySnapshotPayload(payload)
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, playerWhoTriggered: Player)
		if playerWhoTriggered ~= LocalPlayer then
			return
		end
		local anchor = findShopAnchorFromPrompt(prompt)
		if anchor then
			ShovelShopController.OpenPanel(anchor)
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, _gameProcessed: boolean)
		if UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape and isOpen then
			ShovelShopController.ClosePanel()
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if
			isDraggingPreview
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			local dx = input.Position.X - lastDragX
			lastDragX = input.Position.X
			detailSpinYaw += dx * 0.014
		end
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		if not isOpen then
			return
		end
		-- Mutual exclusion if player opened ShovelInventoryPanel or MerchantPanel
		if InventoryController.IsOpen() or MerchantController.IsOpen() then
			ShovelShopController.ClosePanel()
			return
		end
		if activeAnchorPart and activeAnchorPart.Parent ~= nil then
			local char = LocalPlayer.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local dx = root.Position.X - activeAnchorPart.Position.X
				local dz = root.Position.Z - activeAnchorPart.Position.Z
				if math.sqrt(dx * dx + dz * dz) > MAX_OPEN_DISTANCE then
					ShovelShopController.ClosePanel()
					return
				end
			end
		end
		if detailPreviewModel then
			if not isDraggingPreview then
				detailSpinYaw += dt * 0.65
			end
			local yaw = if isDraggingPreview then detailSpinYaw else math.sin(detailSpinYaw) * 0.35
			detailPreviewModel:PivotTo(CFrame.Angles(math.rad(10), math.rad(22) + yaw, math.rad(-36)))
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

return ShovelShopController
