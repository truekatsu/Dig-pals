--!strict
local CurrencyStyle = require(script.Parent:WaitForChild("CurrencyStyle"))
-- Client UI controller for Base plots, incubator management, egg placement, speed-up, hatching celebration, and base upgrades (Step 8)

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local BaseConfig = require(Shared:WaitForChild("Config"):WaitForChild("Base"))
local EggsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Eggs"))
local PetsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Pets"))
local RarityConfig = require(Shared:WaitForChild("Config"):WaitForChild("Rarity"))

local InventoryController = require(script.Parent:WaitForChild("InventoryController"))
local MerchantController = require(script.Parent:WaitForChild("MerchantController"))
local ShovelShopController = require(script.Parent:WaitForChild("ShovelShopController"))

local LocalPlayer = Players.LocalPlayer

local BaseController = {}

local COLORS = {
	PanelBg = Color3.fromRGB(22, 27, 38),
	PanelBorder = Color3.fromRGB(96, 212, 255),
	HeaderBg = Color3.fromRGB(26, 34, 48),
	ListBg = Color3.fromRGB(18, 22, 32),
	RowBg = Color3.fromRGB(29, 36, 50),
	RowHover = Color3.fromRGB(38, 48, 66),
	DetailBg = Color3.fromRGB(28, 36, 52),

	BtnPrimary = Color3.fromRGB(46, 178, 106),
	BtnSpeedUp = Color3.fromRGB(238, 162, 42),
	BtnSell = Color3.fromRGB(54, 118, 196),
	BtnDisabled = Color3.fromRGB(48, 56, 72),

	TextPrimary = Color3.fromRGB(244, 248, 255),
	TextSecondary = Color3.fromRGB(178, 190, 212),
	TextMuted = Color3.fromRGB(122, 134, 156),
	TextGold = Color3.fromRGB(255, 220, 96),
	TextCyan = Color3.fromRGB(108, 220, 255),
	TextSuccess = Color3.fromRGB(112, 238, 154),
	TextError = Color3.fromRGB(252, 112, 112),
}

local MAX_OPEN_DISTANCE = 32

-- State
local isOpen = false
local isBusy = false
local activeSlotIndex = 1
local coinsBalance = 0
local baseLevel = 1
local eggBag: { { Id: string, Rarity: string } } = {}
local incubators: { [number]: { Id: string, Rarity: string, ReadyAt: number } } = {}
local petsMap: { [string]: any } = {}
local started = false

-- UI references
local screenGui: ScreenGui? = nil
local uiScale: UIScale? = nil
local backdropButton: TextButton? = nil
local panelFrame: Frame? = nil
local headerTitleLabel: TextLabel? = nil
local headerCoinsPill: TextLabel? = nil
local headerEggPill: TextLabel? = nil

local eggScrollFrame: ScrollingFrame? = nil
local emptyEggLabel: TextLabel? = nil

local activeSlotPane: Frame? = nil
local slotStatusTitle: TextLabel? = nil
local slotTimerLabel: TextLabel? = nil
local slotSpeedUpButton: TextButton? = nil
local slotHatchButton: TextButton? = nil
local statusBannerLabel: TextLabel? = nil

-- Celebration modal
local celebrationBackdrop: TextButton? = nil
local celebrationFrame: Frame? = nil
local celebrationSpeciesLabel: TextLabel? = nil
local celebrationRarityBadge: TextLabel? = nil
local celebrationVariantBadge: TextLabel? = nil
local celebrationStatsLabel: TextLabel? = nil

local function getRarityColor(rarityName: string): Color3
	local info = (RarityConfig.ById :: any)[rarityName]
	return if info then info.Color else RarityConfig.ById.Common.Color
end

local function formatRemainingTime(seconds: number): string
	if seconds <= 0 then
		return "00:00"
	end
	local m = math.floor(seconds / 60)
	local s = math.floor(seconds % 60)
	return string.format("%02d:%02d", m, s)
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

local function computeSpeedUpCost(entry: { Id: string, ReadyAt: number }, now: number): number
	if now >= entry.ReadyAt then
		return 0
	end
	local remainingSec = math.max(0, entry.ReadyAt - now)
	local remainingMin = math.ceil(remainingSec / 60)
	local eggCfg = EggsConfig.All[entry.Id]
	local rate = if eggCfg then eggCfg.SpeedUpCostPerMinute else 25
	return remainingMin * rate
end

local function refreshRightSlotPane()
	if not activeSlotPane then
		return
	end

	local now = os.time()
	local entry = incubators[activeSlotIndex]

	if headerTitleLabel then
		headerTitleLabel.Text = string.format("INKUBATOR #%d", activeSlotIndex)
	end
	if headerCoinsPill then
		headerCoinsPill.Text = Format.Money(coinsBalance)
	end
	local eggCap = BaseConfig.BaseEggBagCapacity + baseLevel
	if headerEggPill then
		headerEggPill.Text = string.format("Telur %d/%d", #eggBag, eggCap)
	end

	if not entry then
		-- Slot is empty: show prompt to pick an egg from the left list
		if slotStatusTitle then
			slotStatusTitle.Text = "Inkubator Kosong"
			slotStatusTitle.TextColor3 = COLORS.TextSecondary
		end
		if slotTimerLabel then
			slotTimerLabel.Text = "Pilih salah satu telur dari daftar di sebelah kiri untuk mulai mengerami."
			slotTimerLabel.TextColor3 = COLORS.TextMuted
		end
		if slotSpeedUpButton then
			slotSpeedUpButton.Visible = false
		end
		if slotHatchButton then
			slotHatchButton.Visible = false
		end
	else
		local eggCfg = EggsConfig.All[entry.Id]
		local eggName = if eggCfg then eggCfg.DisplayName else entry.Id
		local remaining = math.max(0, entry.ReadyAt - now)
		local isReady = (remaining <= 0)

		if slotStatusTitle then
			slotStatusTitle.Text = string.format("%s (%s)", eggName, entry.Rarity)
			slotStatusTitle.TextColor3 = getRarityColor(entry.Rarity)
		end

		if slotTimerLabel then
			if isReady then
				slotTimerLabel.Text = "WAKTU INKUBASI SELESAI! TELUR SIAP DITETASKAN."
				slotTimerLabel.TextColor3 = COLORS.TextSuccess
			else
				slotTimerLabel.Text = string.format("Sisa Waktu: %s", formatRemainingTime(remaining))
				slotTimerLabel.TextColor3 = COLORS.TextGold
			end
		end

		if slotSpeedUpButton then
			if isReady then
				slotSpeedUpButton.Visible = false
			else
				local cost = computeSpeedUpCost(entry, now)
				local canAfford = coinsBalance >= cost
				slotSpeedUpButton.Text = if isBusy
					then "MEMPROSES..."
					else string.format("PERCEPAT ($%s)", Format.Commas(cost))
				slotSpeedUpButton.BackgroundColor3 = if canAfford then COLORS.BtnSpeedUp else COLORS.BtnDisabled
				slotSpeedUpButton.TextColor3 = if canAfford then Color3.fromRGB(36, 24, 6) else COLORS.TextMuted
				slotSpeedUpButton.Active = canAfford and not isBusy
				slotSpeedUpButton.Visible = true
			end
		end

		if slotHatchButton then
			if isReady then
				slotHatchButton.Text = if isBusy then "MEMPROSES..." else "TETASKAN SEKARANG!"
				slotHatchButton.BackgroundColor3 = if isBusy then COLORS.BtnDisabled else COLORS.BtnPrimary
				slotHatchButton.Active = not isBusy
				slotHatchButton.Visible = true
			else
				slotHatchButton.Visible = false
			end
		end
	end
end

local function rebuildEggBagList()
	if not eggScrollFrame then
		return
	end

	for _, child in eggScrollFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	if emptyEggLabel then
		emptyEggLabel.Visible = (#eggBag == 0)
	end

	local isSlotOccupied = (incubators[activeSlotIndex] ~= nil)

	for eggBagIndex, rawEntry in eggBag do
		local eggId = if type(rawEntry) == "table" and (rawEntry :: any).Id ~= nil then tostring((rawEntry :: any).Id) else tostring(rawEntry)
		local cfg = EggsConfig.All[eggId]
		local eggRarity = if type(rawEntry) == "table" and (rawEntry :: any).Rarity ~= nil then tostring((rawEntry :: any).Rarity) else (if cfg then cfg.Rarity else "Common")
		local rarityColor = getRarityColor(eggRarity)
		local durationMin = if cfg then math.ceil(cfg.IncubationSeconds / 60) else 1
		local sellPrice = if cfg then cfg.SellPrice else 0

		local row = Instance.new("Frame")
		row.Name = "EggRow_" .. eggBagIndex
		row.Size = UDim2.new(1, -6, 0, 72)
		row.BackgroundColor3 = COLORS.RowBg
		row.BorderSizePixel = 0
		row.LayoutOrder = eggBagIndex
		row.Parent = eggScrollFrame

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 10)
		rowCorner.Parent = row

		local rowStroke = Instance.new("UIStroke")
		rowStroke.Color = rarityColor
		rowStroke.Thickness = 1.2
		rowStroke.Transparency = 0.4
		rowStroke.Parent = row

		local eggBadge = Instance.new("TextLabel")
		eggBadge.Name = "EggBadge"
		eggBadge.AnchorPoint = Vector2.new(0, 0.5)
		eggBadge.Position = UDim2.new(0, 8, 0.5, 0)
		eggBadge.Size = UDim2.fromOffset(48, 48)
		eggBadge.BackgroundColor3 = Color3.fromRGB(22, 28, 40)
		eggBadge.BorderSizePixel = 0
		eggBadge.Font = Enum.Font.GothamBlack
		eggBadge.TextSize = 22
		eggBadge.Text = "[Egg]"
		eggBadge.Parent = row

		local eggBadgeCorner = Instance.new("UICorner")
		eggBadgeCorner.CornerRadius = UDim.new(0, 8)
		eggBadgeCorner.Parent = eggBadge

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Name = "EggName"
		nameLbl.Position = UDim2.fromOffset(64, 12)
		nameLbl.Size = UDim2.new(1, -210, 0, 22)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.TextSize = 14
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.TextColor3 = rarityColor
		nameLbl.Text = if cfg then cfg.DisplayName else eggId
		nameLbl.Parent = row

		local subLbl = Instance.new("TextLabel")
		subLbl.Name = "EggSub"
		subLbl.Position = UDim2.fromOffset(64, 36)
		subLbl.Size = UDim2.new(1, -210, 0, 18)
		subLbl.BackgroundTransparency = 1
		subLbl.Font = Enum.Font.GothamMedium
		subLbl.TextSize = 11
		subLbl.TextXAlignment = Enum.TextXAlignment.Left
		subLbl.TextColor3 = COLORS.TextSecondary
		subLbl.Text = string.format("%s | Durasi %d mnt", eggRarity, durationMin)
		subLbl.Parent = row

		-- Place button (only active if incubator slot is currently empty)
		local placeBtn = Instance.new("TextButton")
		placeBtn.Name = "PlaceButton"
		placeBtn.AnchorPoint = Vector2.new(1, 0.5)
		placeBtn.Position = UDim2.new(1, -74, 0.5, 0)
		placeBtn.Size = UDim2.fromOffset(68, 44)
		placeBtn.BackgroundColor3 = if isSlotOccupied then COLORS.BtnDisabled else COLORS.BtnPrimary
		placeBtn.BorderSizePixel = 0
		placeBtn.Font = Enum.Font.GothamBlack
		placeBtn.TextSize = 11
		placeBtn.TextColor3 = if isSlotOccupied then COLORS.TextMuted else COLORS.TextPrimary
		placeBtn.Text = "TARUH"
		placeBtn.Active = not isSlotOccupied and not isBusy
		placeBtn.Parent = row

		local pCorner = Instance.new("UICorner")
		pCorner.CornerRadius = UDim.new(0, 8)
		pCorner.Parent = placeBtn

		placeBtn.Activated:Connect(function()
			if not isSlotOccupied and not isBusy then
				task.spawn(function()
					BaseController.RequestPlaceEgg(eggBagIndex)
				end)
			end
		end)

		-- Sell Egg button
		local sellBtn = Instance.new("TextButton")
		sellBtn.Name = "SellButton"
		sellBtn.AnchorPoint = Vector2.new(1, 0.5)
		sellBtn.Position = UDim2.new(1, -6, 0.5, 0)
		sellBtn.Size = UDim2.fromOffset(62, 44)
		sellBtn.BackgroundColor3 = COLORS.BtnSell
		sellBtn.BorderSizePixel = 0
		sellBtn.Font = Enum.Font.GothamBlack
		sellBtn.TextSize = 10
		sellBtn.TextColor3 = COLORS.TextPrimary
		sellBtn.Text = string.format("Jual\n+%s", Format.Commas(sellPrice))
		sellBtn.Active = not isBusy
		sellBtn.Parent = row

		local sCorner = Instance.new("UICorner")
		sCorner.CornerRadius = UDim.new(0, 8)
		sCorner.Parent = sellBtn

		sellBtn.Activated:Connect(function()
			if not isBusy then
				task.spawn(function()
					BaseController.RequestSellEgg(eggBagIndex)
				end)
			end
		end)
	end

	refreshRightSlotPane()
end

function BaseController.IsOpen(): boolean
	return isOpen
end

function BaseController.OpenIncubatorModal(_slotIndex: number)
	-- Egg selection and placement now use Items > Eggs and the carried egg.
end

function BaseController.CloseIncubatorModal()
	if not isOpen then
		return
	end
	isOpen = false
	setStatusBanner(nil, false)

	if backdropButton then
		backdropButton.Visible = false
	end
	if panelFrame then
		panelFrame.Visible = false
	end
end

function BaseController.ShowCelebration(
	species: string,
	rarity: string,
	variant: string
)
	local speciesCfg = PetsConfig.Species[species]
	local rarityColor = getRarityColor(rarity)
	local varCfg = (PetsConfig.Variants :: any)[variant]

	if celebrationSpeciesLabel then
		celebrationSpeciesLabel.Text = if speciesCfg then speciesCfg.DisplayName else species
		celebrationSpeciesLabel.TextColor3 = rarityColor
	end

	if celebrationRarityBadge then
		celebrationRarityBadge.Text = string.upper(rarity)
		celebrationRarityBadge.BackgroundColor3 = rarityColor
	end

	if celebrationVariantBadge then
		if variant == "Shiny" then
			celebrationVariantBadge.Text = "[*] SHINY (+125% STAT)"
			celebrationVariantBadge.BackgroundColor3 = Color3.fromRGB(158, 88, 255)
			celebrationVariantBadge.Visible = true
		elseif variant == "Golden" then
			celebrationVariantBadge.Text = "  GOLDEN (+50% STAT)"
			celebrationVariantBadge.BackgroundColor3 = Color3.fromRGB(245, 188, 48)
			celebrationVariantBadge.Visible = true
		else
			celebrationVariantBadge.Text = "NORMAL"
			celebrationVariantBadge.BackgroundColor3 = Color3.fromRGB(68, 78, 102)
			celebrationVariantBadge.Visible = false
		end
	end

	if celebrationStatsLabel and speciesCfg then
		local mult = if varCfg then varCfg.PowerMultiplier else 1.0
		local power = math.floor(speciesCfg.Power * mult)
		local speed = speciesCfg.Speed
		local digSpeed = speciesCfg.DigSpeed + (if varCfg then varCfg.DigSpeedBonus else 0)
		local range = speciesCfg.Range
		local income = math.floor(speciesCfg.BaseIncome * (if varCfg then varCfg.IncomeMultiplier else 1.0))

		celebrationStatsLabel.Text = string.format(
			"Power %d  |  Speed %d  |  Jeda Gali %d  |  Range %d studs  |  Income +$%d/dtk",
			power, speed, digSpeed, range, income
		)
	end

	if celebrationBackdrop then
		celebrationBackdrop.Visible = true
	end
	if celebrationFrame then
		celebrationFrame.Visible = true
	end
end

function BaseController.CloseCelebration()
	if celebrationBackdrop then
		celebrationBackdrop.Visible = false
	end
	if celebrationFrame then
		celebrationFrame.Visible = false
	end
end

function BaseController.RequestPlaceEgg(eggBagIndex: number)
	if isBusy then
		return
	end
	isBusy = true
	setStatusBanner(nil, false)
	rebuildEggBagList()

	local ok, response = pcall(function()
		return Remotes.GetFunction("PlaceEggInIncubator"):InvokeServer(eggBagIndex, activeSlotIndex)
	end)

	isBusy = false

	if ok and type(response) == "table" and response.Success == true then
		setStatusBanner("Telur berhasil ditaruh ke inkubator!", false)
	else
		local msg = if ok and type(response) == "table" and type(response.Message) == "string"
			then response.Message
			else "Gagal menaruh telur."
		setStatusBanner(msg, true)
	end

	rebuildEggBagList()
end

function BaseController.RequestSpeedUp()
	if isBusy then
		return
	end
	isBusy = true
	setStatusBanner(nil, false)
	refreshRightSlotPane()

	local ok, response = pcall(function()
		return Remotes.GetFunction("SpeedUpIncubator"):InvokeServer(activeSlotIndex)
	end)

	isBusy = false

	if ok and type(response) == "table" and response.Success == true then
		setStatusBanner("Inkubasi berhasil dipercepat! Telur siap ditetaskan.", false)
	else
		local msg = if ok and type(response) == "table" and type(response.Message) == "string"
			then response.Message
			else "Gagal mempercepat inkubasi."
		setStatusBanner(msg, true)
	end

	refreshRightSlotPane()
end

function BaseController.RequestHatch()
	if isBusy then
		return
	end
	isBusy = true
	setStatusBanner(nil, false)
	refreshRightSlotPane()

	local ok, response = pcall(function()
		return Remotes.GetFunction("HatchIncubator"):InvokeServer(activeSlotIndex)
	end)

	isBusy = false

	if ok and type(response) == "table" and response.Success == true then
		local species = tostring(response.Species or "Dog")
		local rarity = tostring(response.Rarity or "Common")
		local variant = tostring(response.Variant or "Normal")
		BaseController.CloseIncubatorModal()
		BaseController.ShowCelebration(species, rarity, variant)
	else
		local msg = if ok and type(response) == "table" and type(response.Message) == "string"
			then response.Message
			else "Gagal menetaskan telur."
		setStatusBanner(msg, true)
		refreshRightSlotPane()
	end
end

function BaseController.RequestSellEgg(eggBagIndex: number)
	if isBusy then
		return
	end
	isBusy = true
	setStatusBanner(nil, false)
	rebuildEggBagList()

	local ok, response = pcall(function()
		return Remotes.GetFunction("SellEgg"):InvokeServer(eggBagIndex)
	end)

	isBusy = false

	if ok and type(response) == "table" and response.Success == true then
		local earned = tonumber(response.CoinsEarned) or 0
		setStatusBanner(string.format("Telur terjual (+$%s)!", Format.Commas(earned)), false)
	else
		local msg = if ok and type(response) == "table" and type(response.Message) == "string"
			then response.Message
			else "Gagal menjual telur."
		setStatusBanner(msg, true)
	end

	rebuildEggBagList()
end

function BaseController.ApplySnapshot(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if type(payload.Coins) == "number" then
		coinsBalance = payload.Coins
	end
	if type(payload.BaseLevel) == "number" then
		baseLevel = payload.BaseLevel
	end
	if type(payload.EggBag) == "table" then
		eggBag = payload.EggBag
	end
	if type(payload.Incubators) == "table" then
		incubators = payload.Incubators
	end
	if type(payload.Pets) == "table" then
		petsMap = payload.Pets
	end

	if isOpen then
		rebuildEggBagList()
	end
end

local function buildIncubatorGui()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("IncubatorGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "IncubatorGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 16
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
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.Visible = false
	backdrop.ZIndex = 8
	backdrop.Parent = gui
	backdropButton = backdrop

	backdrop.Activated:Connect(function()
		BaseController.CloseIncubatorModal()
	end)

	local panel = Instance.new("Frame")
	panel.Name = "IncubatorPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.44, 0)
	panel.Size = UDim2.fromOffset(768, 480)
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
	titleLbl.Text = "INKUBATOR #1"
	titleLbl.ZIndex = 12
	titleLbl.Parent = header
	headerTitleLabel = titleLbl

	local eggPill = Instance.new("TextLabel")
	eggPill.Name = "EggPill"
	eggPill.AnchorPoint = Vector2.new(1, 0.5)
	eggPill.Position = UDim2.new(1, -188, 0.5, 0)
	eggPill.Size = UDim2.fromOffset(132, 28)
	eggPill.BackgroundColor3 = Color3.fromRGB(34, 48, 68)
	eggPill.BorderSizePixel = 0
	eggPill.Font = Enum.Font.GothamBold
	eggPill.TextSize = 12
	eggPill.TextColor3 = COLORS.TextSecondary
	eggPill.Text = "Telur 0/5"
	eggPill.ZIndex = 12
	eggPill.Parent = header
	headerEggPill = eggPill

	local eggPillCorner = Instance.new("UICorner")
	eggPillCorner.CornerRadius = UDim.new(1, 0)
	eggPillCorner.Parent = eggPill

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
	coinsPill.Text = "$0"
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
		BaseController.CloseIncubatorModal()
	end)

	-- Left Column: Eggs in EggBag
	local leftFrame = Instance.new("Frame")
	leftFrame.Name = "LeftEggList"
	leftFrame.Position = UDim2.fromOffset(14, 62)
	leftFrame.Size = UDim2.new(0.54, -18, 1, -76)
	leftFrame.BackgroundColor3 = COLORS.ListBg
	leftFrame.BorderSizePixel = 0
	leftFrame.ZIndex = 11
	leftFrame.Parent = panel

	local leftCorner = Instance.new("UICorner")
	leftCorner.CornerRadius = UDim.new(0, 11)
	leftCorner.Parent = leftFrame

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "EggListScroll"
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = Color3.fromRGB(96, 178, 232)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.ZIndex = 12
	scroll.Parent = leftFrame
	eggScrollFrame = scroll

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
	emptyLbl.Size = UDim2.new(0.85, 0, 0, 80)
	emptyLbl.BackgroundTransparency = 1
	emptyLbl.Font = Enum.Font.GothamMedium
	emptyLbl.TextSize = 13
	emptyLbl.TextWrapped = true
	emptyLbl.TextColor3 = COLORS.TextMuted
	emptyLbl.Text = "Tas Telur kamu masih kosong.\nGali gundukan tanah di Dig Field untuk menemukan telur baru!"
	emptyLbl.ZIndex = 12
	emptyLbl.Parent = leftFrame
	emptyEggLabel = emptyLbl

	-- Right Column: Active Slot Actions (Status, Countdown, Speed Up, Hatch)
	local rightFrame = Instance.new("Frame")
	rightFrame.Name = "RightSlotPane"
	rightFrame.AnchorPoint = Vector2.new(1, 0)
	rightFrame.Position = UDim2.new(1, -14, 0, 62)
	rightFrame.Size = UDim2.new(0.46, -18, 1, -76)
	rightFrame.BackgroundColor3 = COLORS.DetailBg
	rightFrame.BorderSizePixel = 0
	rightFrame.ZIndex = 11
	rightFrame.Parent = panel
	activeSlotPane = rightFrame

	local rightCorner = Instance.new("UICorner")
	rightCorner.CornerRadius = UDim.new(0, 11)
	rightCorner.Parent = rightFrame

	local rightStroke = Instance.new("UIStroke")
	rightStroke.Color = Color3.fromRGB(68, 92, 128)
	rightStroke.Thickness = 1.2
	rightStroke.Parent = rightFrame

	-- 3D Egg silhouette display
	local eggIconBox = Instance.new("Frame")
	eggIconBox.Name = "EggIconBox"
	eggIconBox.Position = UDim2.fromOffset(14, 14)
	eggIconBox.Size = UDim2.new(1, -28, 0, 130)
	eggIconBox.BackgroundColor3 = Color3.fromRGB(18, 24, 36)
	eggIconBox.BorderSizePixel = 0
	eggIconBox.ZIndex = 12
	eggIconBox.Parent = rightFrame

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(0, 10)
	iconCorner.Parent = eggIconBox

	local bigEggEmoji = Instance.new("TextLabel")
	bigEggEmoji.AnchorPoint = Vector2.new(0.5, 0.5)
	bigEggEmoji.Position = UDim2.fromScale(0.5, 0.5)
	bigEggEmoji.Size = UDim2.fromOffset(80, 80)
	bigEggEmoji.BackgroundTransparency = 1
	bigEggEmoji.Font = Enum.Font.GothamBlack
	bigEggEmoji.TextSize = 58
	bigEggEmoji.Text = "[Egg]"
	bigEggEmoji.ZIndex = 13
	bigEggEmoji.Parent = eggIconBox

	local sTitle = Instance.new("TextLabel")
	sTitle.Name = "SlotStatusTitle"
	sTitle.Position = UDim2.fromOffset(14, 154)
	sTitle.Size = UDim2.new(1, -28, 0, 24)
	sTitle.BackgroundTransparency = 1
	sTitle.Font = Enum.Font.GothamBlack
	sTitle.TextSize = 16
	sTitle.TextXAlignment = Enum.TextXAlignment.Left
	sTitle.TextTruncate = Enum.TextTruncate.AtEnd
	sTitle.TextColor3 = COLORS.TextPrimary
	sTitle.Text = "Inkubator Kosong"
	sTitle.ZIndex = 12
	sTitle.Parent = rightFrame
	slotStatusTitle = sTitle

	local sTimer = Instance.new("TextLabel")
	sTimer.Name = "SlotTimerLabel"
	sTimer.Position = UDim2.fromOffset(14, 182)
	sTimer.Size = UDim2.new(1, -28, 0, 48)
	sTimer.BackgroundTransparency = 1
	sTimer.Font = Enum.Font.GothamBold
	sTimer.TextSize = 13
	sTimer.TextWrapped = true
	sTimer.TextXAlignment = Enum.TextXAlignment.Left
	sTimer.TextYAlignment = Enum.TextYAlignment.Top
	sTimer.TextColor3 = COLORS.TextGold
	sTimer.Text = "Pilih salah satu telur dari daftar di sebelah kiri."
	sTimer.ZIndex = 12
	sTimer.Parent = rightFrame
	slotTimerLabel = sTimer

	local sBanner = Instance.new("TextLabel")
	sBanner.Name = "StatusBanner"
	sBanner.AnchorPoint = Vector2.new(0.5, 1)
	sBanner.Position = UDim2.new(0.5, 0, 1, -66)
	sBanner.Size = UDim2.new(1, -28, 0, 20)
	sBanner.BackgroundTransparency = 1
	sBanner.Font = Enum.Font.GothamBold
	sBanner.TextSize = 11
	sBanner.TextTruncate = Enum.TextTruncate.AtEnd
	sBanner.TextColor3 = COLORS.TextSuccess
	sBanner.Text = ""
	sBanner.Visible = false
	sBanner.ZIndex = 12
	sBanner.Parent = rightFrame
	statusBannerLabel = sBanner

	-- Action Button 1: Speed Up
	local speedUpBtn = Instance.new("TextButton")
	speedUpBtn.Name = "SpeedUpButton"
	speedUpBtn.AnchorPoint = Vector2.new(0.5, 1)
	speedUpBtn.Position = UDim2.new(0.5, 0, 1, -12)
	speedUpBtn.Size = UDim2.new(1, -28, 0, 46)
	speedUpBtn.BackgroundColor3 = COLORS.BtnSpeedUp
	speedUpBtn.BorderSizePixel = 0
	speedUpBtn.Font = Enum.Font.GothamBlack
	speedUpBtn.TextSize = 14
	speedUpBtn.TextColor3 = Color3.fromRGB(36, 24, 6)
	speedUpBtn.Text = "PERCEPAT ($25)"
	speedUpBtn.Visible = false
	speedUpBtn.ZIndex = 12
	speedUpBtn.Parent = rightFrame
	slotSpeedUpButton = speedUpBtn

	local spCorner = Instance.new("UICorner")
	spCorner.CornerRadius = UDim.new(0, 10)
	spCorner.Parent = speedUpBtn

	speedUpBtn.Activated:Connect(function()
		if speedUpBtn.Active then
			task.spawn(function()
				BaseController.RequestSpeedUp()
			end)
		end
	end)

	-- Action Button 2: Hatch Now
	local hatchBtn = Instance.new("TextButton")
	hatchBtn.Name = "HatchButton"
	hatchBtn.AnchorPoint = Vector2.new(0.5, 1)
	hatchBtn.Position = UDim2.new(0.5, 0, 1, -12)
	hatchBtn.Size = UDim2.new(1, -28, 0, 46)
	hatchBtn.BackgroundColor3 = COLORS.BtnPrimary
	hatchBtn.BorderSizePixel = 0
	hatchBtn.Font = Enum.Font.GothamBlack
	hatchBtn.TextSize = 15
	hatchBtn.TextColor3 = COLORS.TextPrimary
	hatchBtn.Text = "TETASKAN SEKARANG!"
	hatchBtn.Visible = false
	hatchBtn.ZIndex = 12
	hatchBtn.Parent = rightFrame
	slotHatchButton = hatchBtn

	local hCorner = Instance.new("UICorner")
	hCorner.CornerRadius = UDim.new(0, 10)
	hCorner.Parent = hatchBtn

	hatchBtn.Activated:Connect(function()
		if hatchBtn.Active then
			task.spawn(function()
				BaseController.RequestHatch()
			end)
		end
	end)

	-- =========================================================================
	-- Celebration Modal (Hatch Result Pop-up)
	-- =========================================================================
	local celebBackdrop = Instance.new("TextButton")
	celebBackdrop.Name = "CelebrationBackdrop"
	celebBackdrop.Size = UDim2.fromScale(1, 1)
	celebBackdrop.BackgroundColor3 = Color3.fromRGB(6, 8, 14)
	celebBackdrop.BackgroundTransparency = 0.35
	celebBackdrop.BorderSizePixel = 0
	celebBackdrop.AutoButtonColor = false
	celebBackdrop.Text = ""
	celebBackdrop.Visible = false
	celebBackdrop.ZIndex = 25
	celebBackdrop.Parent = gui
	celebrationBackdrop = celebBackdrop

	local celebFrame = Instance.new("Frame")
	celebFrame.Name = "CelebrationFrame"
	celebFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	celebFrame.Position = UDim2.fromScale(0.5, 0.5)
	celebFrame.Size = UDim2.fromOffset(480, 360)
	celebFrame.BackgroundColor3 = Color3.fromRGB(24, 30, 44)
	celebFrame.BorderSizePixel = 0
	celebFrame.Visible = false
	celebFrame.ZIndex = 26
	celebFrame.Parent = gui
	celebrationFrame = celebFrame

	local celebCorner = Instance.new("UICorner")
	celebCorner.CornerRadius = UDim.new(0, 16)
	celebCorner.Parent = celebFrame

	local celebStroke = Instance.new("UIStroke")
	celebStroke.Color = Color3.fromRGB(255, 220, 96)
	celebStroke.Thickness = 2.2
	celebStroke.Parent = celebFrame

	local cHeader = Instance.new("TextLabel")
	cHeader.Name = "CelebrationTitle"
	cHeader.Position = UDim2.fromOffset(0, 20)
	cHeader.Size = UDim2.new(1, 0, 0, 26)
	cHeader.BackgroundTransparency = 1
	cHeader.Font = Enum.Font.GothamBlack
	cHeader.TextSize = 20
	cHeader.TextColor3 = Color3.fromRGB(255, 224, 96)
	cHeader.Text = "PET BARU DITETASKAN!"
	cHeader.ZIndex = 27
	cHeader.Parent = celebFrame

	local cPetIcon = Instance.new("TextLabel")
	cPetIcon.Position = UDim2.fromOffset(0, 52)
	cPetIcon.Size = UDim2.new(1, 0, 0, 70)
	cPetIcon.BackgroundTransparency = 1
	cPetIcon.Font = Enum.Font.GothamBlack
	cPetIcon.TextSize = 56
	cPetIcon.Text = " "
	cPetIcon.ZIndex = 27
	cPetIcon.Parent = celebFrame

	local cSpecies = Instance.new("TextLabel")
	cSpecies.Name = "SpeciesName"
	cSpecies.Position = UDim2.fromOffset(0, 126)
	cSpecies.Size = UDim2.new(1, 0, 0, 28)
	cSpecies.BackgroundTransparency = 1
	cSpecies.Font = Enum.Font.GothamBlack
	cSpecies.TextSize = 24
	cSpecies.TextColor3 = Color3.fromRGB(255, 255, 255)
	cSpecies.Text = "Terra Dragon"
	cSpecies.ZIndex = 27
	cSpecies.Parent = celebFrame
	celebrationSpeciesLabel = cSpecies

	local cRarity = Instance.new("TextLabel")
	cRarity.Name = "RarityBadge"
	cRarity.AnchorPoint = Vector2.new(0.5, 0)
	cRarity.Position = UDim2.new(0.5, -60, 0, 160)
	cRarity.Size = UDim2.fromOffset(90, 22)
	cRarity.BackgroundColor3 = RarityConfig.ById.Legendary.Color
	cRarity.BorderSizePixel = 0
	cRarity.Font = Enum.Font.GothamBlack
	cRarity.TextSize = 11
	cRarity.TextColor3 = Color3.fromRGB(255, 255, 255)
	cRarity.Text = "LEGENDARY"
	cRarity.ZIndex = 27
	cRarity.Parent = celebFrame
	celebrationRarityBadge = cRarity

	local cRCorner = Instance.new("UICorner")
	cRCorner.CornerRadius = UDim.new(0, 7)
	cRCorner.Parent = cRarity

	local cVariant = Instance.new("TextLabel")
	cVariant.Name = "VariantBadge"
	cVariant.AnchorPoint = Vector2.new(0.5, 0)
	cVariant.Position = UDim2.new(0.5, 54, 0, 160)
	cVariant.Size = UDim2.fromOffset(130, 22)
	cVariant.BackgroundColor3 = Color3.fromRGB(245, 188, 48)
	cVariant.BorderSizePixel = 0
	cVariant.Font = Enum.Font.GothamBlack
	cVariant.TextSize = 10
	cVariant.TextColor3 = Color3.fromRGB(255, 255, 255)
	cVariant.Text = "  GOLDEN (+50%)"
	cVariant.ZIndex = 27
	cVariant.Parent = celebFrame
	celebrationVariantBadge = cVariant

	local cVCorner = Instance.new("UICorner")
	cVCorner.CornerRadius = UDim.new(0, 7)
	cVCorner.Parent = cVariant

	local cStats = Instance.new("TextLabel")
	cStats.Name = "StatsLabel"
	cStats.Position = UDim2.fromOffset(16, 194)
	cStats.Size = UDim2.new(1, -32, 0, 60)
	cStats.BackgroundTransparency = 1
	cStats.Font = Enum.Font.GothamMedium
	cStats.TextSize = 12
	cStats.TextWrapped = true
	cStats.TextColor3 = COLORS.TextSecondary
	cStats.Text = "Power 140 | Speed 8 | Jeda Gali 9 | Range 35 | Income +$160/dtk"
	cStats.ZIndex = 27
	cStats.Parent = celebFrame
	celebrationStatsLabel = cStats

	local okBtn = Instance.new("TextButton")
	okBtn.Name = "ContinueButton"
	okBtn.AnchorPoint = Vector2.new(0.5, 1)
	okBtn.Position = UDim2.new(0.5, 0, 1, -18)
	okBtn.Size = UDim2.fromOffset(200, 44)
	okBtn.BackgroundColor3 = COLORS.BtnPrimary
	okBtn.BorderSizePixel = 0
	okBtn.Font = Enum.Font.GothamBlack
	okBtn.TextSize = 14
	okBtn.TextColor3 = COLORS.TextPrimary
	okBtn.Text = "LANJUTKAN"
	okBtn.ZIndex = 27
	okBtn.Parent = celebFrame

	local okCorner = Instance.new("UICorner")
	okCorner.CornerRadius = UDim.new(0, 10)
	okCorner.Parent = okBtn

	okBtn.Activated:Connect(function()
		BaseController.CloseCelebration()
	end)
end

function BaseController.Start()
	if started then
		return
	end
	started = true

	local attrCoins = LocalPlayer:GetAttribute("Coins")
	if type(attrCoins) == "number" then
		coinsBalance = attrCoins
	end
	local attrBaseLv = LocalPlayer:GetAttribute("BaseLevel")
	if type(attrBaseLv) == "number" then
		baseLevel = attrBaseLv
	end

	-- The legacy incubator picker has been removed.

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
			if isOpen then
				refreshRightSlotPane()
			end
		end
	end)

	LocalPlayer:GetAttributeChangedSignal("BaseLevel"):Connect(function()
		local lv = LocalPlayer:GetAttribute("BaseLevel")
		if type(lv) == "number" then
			baseLevel = lv
			if isOpen then
				refreshRightSlotPane()
			end
		end
	end)

	Remotes.GetEvent("StateSync").OnClientEvent:Connect(function(payload: any)
		BaseController.ApplySnapshot(payload)
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, playerWhoTriggered: Player)
		if playerWhoTriggered ~= LocalPlayer then
			return
		end
		local slotAttr = prompt:GetAttribute("DigPalsIncubatorSlot")
		if type(slotAttr) == "number" then
			-- Legacy station prompts no longer open the removed picker.
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, _gameProcessed: boolean)
		if UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			if celebrationFrame and celebrationFrame.Visible then
				BaseController.CloseCelebration()
			elseif isOpen then
				BaseController.CloseIncubatorModal()
			end
		end
	end)

	-- Ticking countdown in right slot pane
	task.spawn(function()
		while true do
			task.wait(1)
			if isOpen then
				refreshRightSlotPane()
			end
		end
	end)

	task.spawn(function()
		local ok, initialSnapshot = pcall(function()
			return Remotes.GetFunction("GetInventoryState"):InvokeServer()
		end)
		if ok and type(initialSnapshot) == "table" then
			BaseController.ApplySnapshot(initialSnapshot)
		end
	end)
end

return BaseController
