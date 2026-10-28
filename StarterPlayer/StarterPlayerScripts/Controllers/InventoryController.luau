--!strict
-- Responsive Hotbar, Side Category Menu, and Two-Column 3D Shovel Collection UI Controller

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local EconomyConfig = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))
local RarityConfig = require(Shared:WaitForChild("Config"):WaitForChild("Rarity"))
local ShovelsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Shovels"))
local ShovelModelBuilder = require(Shared:WaitForChild("ShovelModelBuilder"))

local LocalPlayer = Players.LocalPlayer

export type SideCategorySpec = {
	Id: string,
	Label: string,
	Order: number,
	BuildViewportModel: (() -> Model)?,
	IconImage: string?,
	OnActivated: () -> (),
}

local InventoryController = {}

-- Visual palette (PRD Section 8: charcoal panel, thin bright border, dark bluish-grey detail panel)
local COLORS = {
	SlotBg = Color3.fromRGB(26, 29, 38),
	SlotHover = Color3.fromRGB(38, 43, 56),
	SlotBorder = Color3.fromRGB(92, 102, 126),
	SlotActiveBorder = Color3.fromRGB(250, 204, 72),
	SlotEmptyBorder = Color3.fromRGB(64, 70, 88),

	PanelBg = Color3.fromRGB(24, 27, 36),
	PanelBorder = Color3.fromRGB(118, 132, 162),
	HeaderBg = Color3.fromRGB(30, 34, 46),
	ListBg = Color3.fromRGB(20, 23, 31),
	RowBg = Color3.fromRGB(31, 36, 48),
	RowHover = Color3.fromRGB(40, 47, 63),
	RowSelectedBg = Color3.fromRGB(44, 54, 76),
	RowSelectedBorder = Color3.fromRGB(245, 202, 74),

	DetailBg = Color3.fromRGB(31, 38, 52), -- Dark bluish-grey per PRD Section 8
	DetailViewportBg = Color3.fromRGB(22, 27, 38),
	StatTrackBg = Color3.fromRGB(18, 22, 30),

	StatPower = Color3.fromRGB(245, 148, 62),
	StatSpeed = Color3.fromRGB(72, 196, 248),
	StatLuck = Color3.fromRGB(82, 216, 132),

	EquipBtnReady = Color3.fromRGB(46, 178, 106),
	EquipBtnHover = Color3.fromRGB(58, 198, 120),
	EquipBtnEquipped = Color3.fromRGB(52, 64, 78),
	ErrorText = Color3.fromRGB(252, 108, 108),

	TextPrimary = Color3.fromRGB(244, 247, 252),
	TextSecondary = Color3.fromRGB(178, 188, 208),
	TextMuted = Color3.fromRGB(122, 132, 152),
}

-- State
local isLoaded = false
local ownedShovels: { string } = { EconomyConfig.StartingShovel }
local equippedShovelId: string = EconomyConfig.StartingShovel
local selectedShovelId: string = EconomyConfig.StartingShovel
local isToolActive: boolean = true
local isPanelOpen: boolean = false
local isEquipPending: boolean = false
local detailSpinYaw: number = 0
local isDraggingPreview: boolean = false
local lastDragX: number = 0
local started = false

-- UI references
local screenGui: ScreenGui? = nil
local uiScale: UIScale? = nil
local sideCategoriesFrame: Frame? = nil
local sideShovelsStroke: UIStroke? = nil
local hotbarFrame: Frame? = nil
local slot1Button: TextButton? = nil
local slot1Stroke: UIStroke? = nil
local slot1Viewport: ViewportFrame? = nil
local slot1NameLabel: TextLabel? = nil
local slot1RarityBar: Frame? = nil
local slot1RenderedShovelId: string? = nil

local slot2Button: TextButton? = nil
local slot2Stroke: UIStroke? = nil

local backdropButton: TextButton? = nil
local panelFrame: Frame? = nil
local ownedCountLabel: TextLabel? = nil
local shovelListScroll: ScrollingFrame? = nil
local rowButtonsById: { [string]: { Button: TextButton, Stroke: UIStroke, StatusBadge: TextLabel } } = {}

local detailScroll: ScrollingFrame? = nil
local detailViewport: ViewportFrame? = nil
local detailPreviewModel: Model? = nil
local detailPreviewShovelId: string? = nil
local detailNameLabel: TextLabel? = nil
local detailRarityBadge: TextLabel? = nil
local detailStatusBadge: TextLabel? = nil
local detailDescLabel: TextLabel? = nil
local powerValueLabel: TextLabel? = nil
local powerFillFrame: Frame? = nil
local speedValueLabel: TextLabel? = nil
local speedFillFrame: Frame? = nil
local luckValueLabel: TextLabel? = nil
local luckFillFrame: Frame? = nil
local errorBannerLabel: TextLabel? = nil
local equipActionButton: TextButton? = nil

local registeredCategories: { [string]: TextButton } = {}

local function getRarityColor(rarityName: string): Color3
	local info = (RarityConfig.ById :: any)[rarityName]
	if info and info.Color then
		return info.Color
	end
	return RarityConfig.ById.Common.Color
end

local function disableDefaultRobloxBackpack()
	task.spawn(function()
		for _ = 1, 15 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			end)
			if ok then
				break
			end
			task.wait(0.2)
		end
	end)
end

local function populateShovelViewport(viewport: ViewportFrame, shovelId: string, interactivePreview: boolean): Model
	for _, child in viewport:GetChildren() do
		if child:IsA("Model") or child:IsA("WorldModel") or child:IsA("Camera") then
			child:Destroy()
		end
	end

	viewport.Ambient = Color3.fromRGB(178, 186, 205)
	viewport.LightColor = Color3.fromRGB(255, 250, 238)
	viewport.LightDirection = Vector3.new(-0.6, -0.7, -0.8)

	local camera = Instance.new("Camera")
	camera.FieldOfView = 32
	local camDist = if interactivePreview then 7.45 else 6.25
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0, camDist), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local model = ShovelModelBuilder.ClonePreviewModel(shovelId)
	local baseOrientation = if interactivePreview
		then CFrame.Angles(math.rad(10), math.rad(22), math.rad(-36))
		else CFrame.Angles(math.rad(12), math.rad(24), math.rad(-42))
	model:PivotTo(baseOrientation)
	model.Parent = viewport
	return model
end

local function populateBagViewport(viewport: ViewportFrame)
	for _, child in viewport:GetChildren() do
		if child:IsA("Model") or child:IsA("WorldModel") or child:IsA("Camera") then
			child:Destroy()
		end
	end

	viewport.Ambient = Color3.fromRGB(185, 190, 206)
	viewport.LightColor = Color3.fromRGB(255, 248, 232)
	viewport.LightDirection = Vector3.new(-0.5, -0.6, -0.85)

	local camera = Instance.new("Camera")
	camera.FieldOfView = 32
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0.22, 5.6), Vector3.new(0.08, 0.22, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local bagModel = ShovelModelBuilder.CloneBagPreviewModel()
	bagModel:PivotTo(CFrame.Angles(math.rad(10), math.rad(-24), 0))
	bagModel.Parent = viewport
end

local function setErrorMessage(msg: string?)
	if not errorBannerLabel then
		return
	end
	if msg and #msg > 0 then
		errorBannerLabel.Text = msg
		errorBannerLabel.Visible = true
	else
		errorBannerLabel.Text = ""
		errorBannerLabel.Visible = false
	end
end

local function refreshHotbarVisuals()
	local cfg = ShovelsConfig.All[equippedShovelId] or ShovelsConfig.All[EconomyConfig.StartingShovel]
	local rarityColor = getRarityColor(cfg.Rarity)

	if slot1Viewport and slot1RenderedShovelId ~= cfg.Id then
		populateShovelViewport(slot1Viewport, cfg.Id, false)
		slot1RenderedShovelId = cfg.Id
	end

	if slot1NameLabel then
		slot1NameLabel.Text = if isLoaded then string.gsub(cfg.DisplayName, " Shovel$", "") else "..."
		slot1NameLabel.TextColor3 = rarityColor
	end

	if slot1RarityBar then
		slot1RarityBar.BackgroundColor3 = rarityColor
	end

	if slot1Stroke and slot1Button then
		if isToolActive then
			slot1Stroke.Color = COLORS.SlotActiveBorder
			slot1Stroke.Thickness = 2.5
			slot1Button.BackgroundColor3 = Color3.fromRGB(36, 41, 56)
		else
			slot1Stroke.Color = COLORS.SlotBorder
			slot1Stroke.Thickness = 1.5
			slot1Button.BackgroundColor3 = COLORS.SlotBg
		end
	end

	if slot2Stroke and slot2Button then
		if isPanelOpen then
			slot2Stroke.Color = COLORS.SlotActiveBorder
			slot2Stroke.Thickness = 2.5
			slot2Button.BackgroundColor3 = Color3.fromRGB(36, 41, 56)
		else
			slot2Stroke.Color = COLORS.SlotBorder
			slot2Stroke.Thickness = 1.5
			slot2Button.BackgroundColor3 = COLORS.SlotBg
		end
	end

	if sideShovelsStroke then
		sideShovelsStroke.Color = if isPanelOpen then COLORS.SlotActiveBorder else COLORS.PanelBorder
		sideShovelsStroke.Thickness = if isPanelOpen then 2.2 else 1.5
	end
end

local function refreshDetailPanel()
	local cfg = ShovelsConfig.All[selectedShovelId]
		or ShovelsConfig.All[equippedShovelId]
		or ShovelsConfig.All[EconomyConfig.StartingShovel]
	local rarityColor = getRarityColor(cfg.Rarity)
	local isOwned = table.find(ownedShovels, cfg.Id) ~= nil
	local isEquipped = (cfg.Id == equippedShovelId)

	if detailViewport and detailPreviewShovelId ~= cfg.Id then
		detailPreviewModel = populateShovelViewport(detailViewport, cfg.Id, true)
		detailPreviewShovelId = cfg.Id
		detailSpinYaw = 0
	end

	if detailNameLabel then
		detailNameLabel.Text = cfg.DisplayName
		detailNameLabel.TextColor3 = rarityColor
	end

	if detailRarityBadge then
		detailRarityBadge.Text = string.upper(cfg.Rarity)
		detailRarityBadge.TextColor3 = rarityColor
		local stroke = detailRarityBadge:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = rarityColor
		end
	end

	if detailStatusBadge then
		if isEquipped then
			detailStatusBadge.Text = "DIPAKAI"
			detailStatusBadge.BackgroundColor3 = Color3.fromRGB(38, 128, 78)
			detailStatusBadge.TextColor3 = Color3.fromRGB(220, 255, 232)
		elseif isOwned then
			detailStatusBadge.Text = "DIMILIKI"
			detailStatusBadge.BackgroundColor3 = Color3.fromRGB(52, 62, 82)
			detailStatusBadge.TextColor3 = COLORS.TextSecondary
		else
			detailStatusBadge.Text = "TERKUNCI"
			detailStatusBadge.BackgroundColor3 = Color3.fromRGB(78, 44, 48)
			detailStatusBadge.TextColor3 = Color3.fromRGB(255, 185, 185)
		end
	end

	if detailDescLabel then
		detailDescLabel.Text = cfg.Description
	end

	-- Normalized stat progress bars (PRD Section 4)
	local powerRatio = math.clamp(cfg.Power / ShovelsConfig.MaxStats.Power, 0.06, 1)
	local digRate = if cfg.DigSpeed > 0 then (1 / cfg.DigSpeed) else 1.0
	local speedRatio = math.clamp(digRate / ShovelsConfig.MaxStats.DigRate, 0.06, 1)
	local luckRatio = math.clamp(cfg.Luck / ShovelsConfig.MaxStats.Luck, 0.06, 1)

	if powerValueLabel then
		powerValueLabel.Text = tostring(cfg.Power)
	end
	if powerFillFrame then
		TweenService:Create(powerFillFrame, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(powerRatio, 1),
		}):Play()
	end

	if speedValueLabel then
		speedValueLabel.Text = string.format("%.2f/dtk (%.2fs)", digRate, cfg.DigSpeed)
	end
	if speedFillFrame then
		TweenService:Create(speedFillFrame, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(speedRatio, 1),
		}):Play()
	end

	if luckValueLabel then
		luckValueLabel.Text = string.format("%.2fx", cfg.Luck)
	end
	if luckFillFrame then
		TweenService:Create(luckFillFrame, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(luckRatio, 1),
		}):Play()
	end

	if equipActionButton then
		if isEquipped then
			equipActionButton.Text = "DIPAKAI"
			equipActionButton.BackgroundColor3 = COLORS.EquipBtnEquipped
			equipActionButton.TextColor3 = Color3.fromRGB(185, 205, 195)
			equipActionButton.AutoButtonColor = false
			equipActionButton.Active = false
		elseif isEquipPending then
			equipActionButton.Text = "MEMAKAI..."
			equipActionButton.BackgroundColor3 = COLORS.EquipBtnEquipped
			equipActionButton.TextColor3 = COLORS.TextSecondary
			equipActionButton.AutoButtonColor = false
			equipActionButton.Active = false
		elseif isOwned then
			equipActionButton.Text = "PAKAI"
			equipActionButton.BackgroundColor3 = COLORS.EquipBtnReady
			equipActionButton.TextColor3 = COLORS.TextPrimary
			equipActionButton.AutoButtonColor = true
			equipActionButton.Active = true
		else
			equipActionButton.Text = "BELUM DIMILIKI"
			equipActionButton.BackgroundColor3 = COLORS.EquipBtnEquipped
			equipActionButton.TextColor3 = COLORS.TextMuted
			equipActionButton.AutoButtonColor = false
			equipActionButton.Active = false
		end
	end
end

local function refreshRowHighlights()
	for shovelId, entry in rowButtonsById do
		local isSelected = (shovelId == selectedShovelId)
		local isEquipped = (shovelId == equippedShovelId)

		entry.Button.BackgroundColor3 = if isSelected then COLORS.RowSelectedBg else COLORS.RowBg
		entry.Stroke.Color = if isSelected
			then COLORS.RowSelectedBorder
			elseif isEquipped then Color3.fromRGB(78, 178, 118)
			else Color3.fromRGB(62, 70, 90)
		entry.Stroke.Thickness = if isSelected then 2.2 else 1.2

		if isEquipped then
			entry.StatusBadge.Text = "DIPAKAI"
			entry.StatusBadge.BackgroundColor3 = Color3.fromRGB(38, 128, 78)
			entry.StatusBadge.TextColor3 = Color3.fromRGB(224, 255, 234)
		else
			entry.StatusBadge.Text = "DIMILIKI"
			entry.StatusBadge.BackgroundColor3 = Color3.fromRGB(48, 56, 74)
			entry.StatusBadge.TextColor3 = COLORS.TextSecondary
		end
	end
end

local function rebuildShovelList()
	if not shovelListScroll then
		return
	end

	for _, child in shovelListScroll:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	table.clear(rowButtonsById)

	if ownedCountLabel then
		ownedCountLabel.Text = string.format("%d Milik", #ownedShovels)
	end

	-- Ensure selectedShovelId stays valid within ownedShovels
	if table.find(ownedShovels, selectedShovelId) == nil then
		selectedShovelId = equippedShovelId
	end

	for index, shovelId in ownedShovels do
		local cfg = ShovelsConfig.All[shovelId]
		if cfg then
			local rarityColor = getRarityColor(cfg.Rarity)

			local row = Instance.new("TextButton")
			row.Name = "ShovelRow_" .. cfg.Id
			row.Size = UDim2.new(1, -6, 0, 68)
			row.BackgroundColor3 = COLORS.RowBg
			row.BorderSizePixel = 0
			row.AutoButtonColor = false
			row.Text = ""
			row.LayoutOrder = index
			row.Parent = shovelListScroll

			local rowCorner = Instance.new("UICorner")
			rowCorner.CornerRadius = UDim.new(0, 10)
			rowCorner.Parent = row

			local rowStroke = Instance.new("UIStroke")
			rowStroke.Color = Color3.fromRGB(62, 70, 90)
			rowStroke.Thickness = 1.2
			rowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			rowStroke.Parent = row

			local thumbBg = Instance.new("Frame")
			thumbBg.Name = "ThumbBg"
			thumbBg.AnchorPoint = Vector2.new(0, 0.5)
			thumbBg.Position = UDim2.new(0, 8, 0.5, 0)
			thumbBg.Size = UDim2.fromOffset(52, 52)
			thumbBg.BackgroundColor3 = Color3.fromRGB(22, 26, 36)
			thumbBg.BorderSizePixel = 0
			thumbBg.Parent = row

			local thumbCorner = Instance.new("UICorner")
			thumbCorner.CornerRadius = UDim.new(0, 8)
			thumbCorner.Parent = thumbBg

			local thumbStroke = Instance.new("UIStroke")
			thumbStroke.Color = rarityColor
			thumbStroke.Thickness = 1.2
			thumbStroke.Transparency = 0.35
			thumbStroke.Parent = thumbBg

			local vp = Instance.new("ViewportFrame")
			vp.Name = "Viewport"
			vp.Size = UDim2.fromScale(1, 1)
			vp.BackgroundTransparency = 1
			vp.Parent = thumbBg
			populateShovelViewport(vp, cfg.Id, false)

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Name = "NameLabel"
			nameLbl.Position = UDim2.fromOffset(68, 10)
			nameLbl.Size = UDim2.new(1, -152, 0, 22)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Font = Enum.Font.GothamBold
			nameLbl.TextSize = 15
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
			nameLbl.TextColor3 = rarityColor
			nameLbl.Text = cfg.DisplayName
			nameLbl.Parent = row

			local rarityLbl = Instance.new("TextLabel")
			rarityLbl.Name = "RarityLabel"
			rarityLbl.Position = UDim2.fromOffset(68, 34)
			rarityLbl.Size = UDim2.new(1, -152, 0, 18)
			rarityLbl.BackgroundTransparency = 1
			rarityLbl.Font = Enum.Font.GothamMedium
			rarityLbl.TextSize = 12
			rarityLbl.TextXAlignment = Enum.TextXAlignment.Left
			rarityLbl.TextColor3 = COLORS.TextSecondary
			rarityLbl.Text = string.format("%s | Power %d", cfg.Rarity, cfg.Power)
			rarityLbl.Parent = row

			local statusBadge = Instance.new("TextLabel")
			statusBadge.Name = "StatusBadge"
			statusBadge.AnchorPoint = Vector2.new(1, 0.5)
			statusBadge.Position = UDim2.new(1, -10, 0.5, 0)
			statusBadge.Size = UDim2.fromOffset(72, 24)
			statusBadge.BackgroundColor3 = Color3.fromRGB(48, 56, 74)
			statusBadge.BorderSizePixel = 0
			statusBadge.Font = Enum.Font.GothamBlack
			statusBadge.TextSize = 11
			statusBadge.TextColor3 = COLORS.TextSecondary
			statusBadge.Text = "DIMILIKI"
			statusBadge.Parent = row

			local badgeCorner = Instance.new("UICorner")
			badgeCorner.CornerRadius = UDim.new(0, 6)
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
				InventoryController.SelectShovelInPanel(cfg.Id)
			end)

			rowButtonsById[cfg.Id] = {
				Button = row,
				Stroke = rowStroke,
				StatusBadge = statusBadge,
			}
		end
	end

	refreshRowHighlights()
	refreshDetailPanel()
end

local function applyInventoryPayload(payload: any)
	if type(payload) ~= "table" then
		return
	end

	if payload.Loaded == true then
		isLoaded = true
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

	if type(payload.ToolActive) == "boolean" then
		isToolActive = payload.ToolActive
	end

	rebuildShovelList()
	refreshHotbarVisuals()
end

function InventoryController.IsOpen(): boolean
	return isPanelOpen
end

function InventoryController.GetState(): {
	Loaded: boolean,
	IsOpen: boolean,
	EquippedShovel: string,
	SelectedShovel: string,
	OwnedShovels: { string },
	ToolActive: boolean,
}
	return {
		Loaded = isLoaded,
		IsOpen = isPanelOpen,
		EquippedShovel = equippedShovelId,
		SelectedShovel = selectedShovelId,
		OwnedShovels = table.clone(ownedShovels),
		ToolActive = isToolActive,
	}
end

function InventoryController.OpenPanel()
	isPanelOpen = true
	setErrorMessage(nil)
	if table.find(ownedShovels, selectedShovelId) == nil then
		selectedShovelId = equippedShovelId
	end
	if backdropButton then
		backdropButton.Visible = true
	end
	if panelFrame then
		panelFrame.Visible = true
	end
	if detailScroll then
		detailScroll.CanvasPosition = Vector2.zero
	end
	refreshRowHighlights()
	refreshDetailPanel()
	refreshHotbarVisuals()
	task.defer(function()
		if detailScroll then
			detailScroll.CanvasPosition = Vector2.zero
		end
	end)
end

function InventoryController.ClosePanel()
	if not isPanelOpen then
		return
	end
	isPanelOpen = false
	isDraggingPreview = false
	setErrorMessage(nil)
	if backdropButton then
		backdropButton.Visible = false
	end
	if panelFrame then
		panelFrame.Visible = false
	end
	refreshHotbarVisuals()
end

function InventoryController.TogglePanel()
	if isPanelOpen then
		InventoryController.ClosePanel()
	else
		InventoryController.OpenPanel()
	end
end

function InventoryController.ActivateSlot1()
	local nextActive = not isToolActive
	isToolActive = nextActive
	refreshHotbarVisuals()
	Remotes.GetEvent("SetShovelToolActive"):FireServer(nextActive)
end

function InventoryController.SelectShovelInPanel(shovelId: string)
	if ShovelsConfig.All[shovelId] == nil then
		return
	end
	selectedShovelId = shovelId
	setErrorMessage(nil)
	if detailScroll then
		detailScroll.CanvasPosition = Vector2.zero
	end
	refreshRowHighlights()
	refreshDetailPanel()
	task.defer(function()
		if detailScroll then
			detailScroll.CanvasPosition = Vector2.zero
		end
	end)
end

function InventoryController.RequestEquipShovel(shovelId: string): (boolean, string?)
	if isEquipPending then
		return false, "Permintaan sedang diproses."
	end
	if shovelId == equippedShovelId then
		return true, nil
	end

	isEquipPending = true
	setErrorMessage(nil)
	refreshDetailPanel()

	local ok, response = pcall(function()
		return Remotes.GetFunction("EquipShovel"):InvokeServer(shovelId)
	end)

	isEquipPending = false

	if not ok or type(response) ~= "table" then
		local errMsg = "Gagal menghubungi server. Coba lagi."
		setErrorMessage(errMsg)
		refreshDetailPanel()
		return false, errMsg
	end

	if response.Success == true and type(response.Equipped) == "string" then
		equippedShovelId = response.Equipped
		isToolActive = true
		if type(response.Owned) == "table" and #response.Owned > 0 then
			ownedShovels = response.Owned
		end
		setErrorMessage(nil)
		rebuildShovelList()
		refreshHotbarVisuals()
		return true, nil
	else
		local errMsg = tostring(response.Message or response.Reason or "Tidak dapat memakai shovel ini.")
		setErrorMessage(errMsg)
		refreshRowHighlights()
		refreshDetailPanel()
		refreshHotbarVisuals()
		return false, errMsg
	end
end

function InventoryController.RegisterSideCategory(spec: SideCategorySpec): TextButton?
	if not sideCategoriesFrame then
		return nil
	end
	local existing = registeredCategories[spec.Id]
	if existing then
		existing:Destroy()
	end

	local btn = Instance.new("TextButton")
	btn.Name = spec.Id .. "Button"
	btn.Size = UDim2.fromOffset(66, 70)
	btn.BackgroundColor3 = COLORS.SlotBg
	btn.BackgroundTransparency = 0.08
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.LayoutOrder = spec.Order
	btn.Parent = sideCategoriesFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.PanelBorder
	stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = btn

	if spec.BuildViewportModel then
		local vp = Instance.new("ViewportFrame")
		vp.Name = "IconViewport"
		vp.AnchorPoint = Vector2.new(0.5, 0)
		vp.Position = UDim2.new(0.5, 0, 0, 4)
		vp.Size = UDim2.fromOffset(44, 42)
		vp.BackgroundTransparency = 1
		vp.Parent = btn

		vp.Ambient = Color3.fromRGB(185, 190, 206)
		vp.LightColor = Color3.fromRGB(255, 248, 232)
		vp.LightDirection = Vector3.new(-0.5, -0.6, -0.85)
		local cam = Instance.new("Camera")
		cam.FieldOfView = 32
		cam.CFrame = CFrame.lookAt(Vector3.new(0, 0.22, 5.6), Vector3.new(0.08, 0.22, 0))
		cam.Parent = vp
		vp.CurrentCamera = cam

		local mdl = spec.BuildViewportModel()
		mdl:PivotTo(CFrame.Angles(math.rad(10), math.rad(-24), 0))
		mdl.Parent = vp
	elseif spec.IconImage then
		local img = Instance.new("ImageLabel")
		img.Name = "IconImage"
		img.AnchorPoint = Vector2.new(0.5, 0)
		img.Position = UDim2.new(0.5, 0, 0, 8)
		img.Size = UDim2.fromOffset(34, 34)
		img.BackgroundTransparency = 1
		img.Image = spec.IconImage
		img.Parent = btn
	elseif (spec :: any).IconText then
		local iconLbl = Instance.new("TextLabel")
		iconLbl.Name = "IconText"
		iconLbl.AnchorPoint = Vector2.new(0.5, 0)
		iconLbl.Position = UDim2.new(0.5, 0, 0, 8)
		iconLbl.Size = UDim2.fromOffset(48, 30)
		iconLbl.BackgroundTransparency = 1
		iconLbl.Font = Enum.Font.GothamBlack
		iconLbl.TextSize = 14
		iconLbl.TextColor3 = Color3.fromRGB(255, 215, 80)
		iconLbl.Text = tostring((spec :: any).IconText)
		iconLbl.Parent = btn
	end

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Label"
	lbl.AnchorPoint = Vector2.new(0.5, 1)
	lbl.Position = UDim2.new(0.5, 0, 1, -5)
	lbl.Size = UDim2.new(1, -6, 0, 16)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextSize = 12
	lbl.TextColor3 = COLORS.TextPrimary
	lbl.TextStrokeTransparency = 0.45
	lbl.Text = spec.Label or (spec :: any).LabelText or spec.Id or ""
	lbl.Parent = btn

	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = COLORS.SlotHover
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = COLORS.SlotBg
	end)
	btn.Activated:Connect(function()
		spec.OnActivated()
	end)

	registeredCategories[spec.Id] = btn
	return btn
end

local function createStatRow(
	parent: Instance,
	rowName: string,
	labelText: string,
	fillColor: Color3,
	layoutOrder: number
): (TextLabel, Frame)
	local container = Instance.new("Frame")
	container.Name = rowName
	container.Size = UDim2.new(1, 0, 0, 34)
	container.BackgroundTransparency = 1
	container.LayoutOrder = layoutOrder
	container.Parent = parent

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Name = "StatTitle"
	titleLbl.Position = UDim2.fromOffset(0, 0)
	titleLbl.Size = UDim2.new(0.62, 0, 0, 17)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Font = Enum.Font.GothamBold
	titleLbl.TextSize = 12
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.TextColor3 = COLORS.TextSecondary
	titleLbl.Text = labelText
	titleLbl.Parent = container

	local valLbl = Instance.new("TextLabel")
	valLbl.Name = "StatValue"
	valLbl.AnchorPoint = Vector2.new(1, 0)
	valLbl.Position = UDim2.fromScale(1, 0)
	valLbl.Size = UDim2.new(0.38, 0, 0, 17)
	valLbl.BackgroundTransparency = 1
	valLbl.Font = Enum.Font.GothamBlack
	valLbl.TextSize = 12
	valLbl.TextXAlignment = Enum.TextXAlignment.Right
	valLbl.TextColor3 = fillColor
	valLbl.Text = "-"
	valLbl.Parent = container

	local track = Instance.new("Frame")
	track.Name = "BarTrack"
	track.Position = UDim2.fromOffset(0, 20)
	track.Size = UDim2.new(1, 0, 0, 10)
	track.BackgroundColor3 = COLORS.StatTrackBg
	track.BorderSizePixel = 0
	track.Parent = container

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "BarFill"
	fill.Size = UDim2.fromScale(0.1, 1)
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	return valLbl, fill
end

local function createHotbarSlotBase(parent: Instance, name: string, slotNum: number, isEmptySlot: boolean): (TextButton, UIStroke)
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = UDim2.fromOffset(68, 68)
	btn.BackgroundColor3 = COLORS.SlotBg
	btn.BackgroundTransparency = if isEmptySlot then 0.32 else 0.08
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.LayoutOrder = slotNum
	btn.Active = not isEmptySlot
	btn.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 11)
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = if isEmptySlot then COLORS.SlotEmptyBorder else COLORS.SlotBorder
	stroke.Thickness = if isEmptySlot then 1.2 else 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = btn

	local numLbl = Instance.new("TextLabel")
	numLbl.Name = "SlotNumber"
	numLbl.Position = UDim2.fromOffset(6, 4)
	numLbl.Size = UDim2.fromOffset(16, 14)
	numLbl.BackgroundTransparency = 1
	numLbl.Font = Enum.Font.GothamBlack
	numLbl.TextSize = 12
	numLbl.TextXAlignment = Enum.TextXAlignment.Left
	numLbl.TextColor3 = if isEmptySlot then COLORS.TextMuted else COLORS.TextSecondary
	numLbl.Text = tostring(slotNum)
	numLbl.ZIndex = 4
	numLbl.Parent = btn

	return btn, stroke
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
	local scaleW = vp.X / 900
	local scaleH = vp.Y / 660
	uiScale.Scale = math.clamp(math.min(1, scaleW, scaleH), 0.72, 1.0)
end

local function buildInventoryGui()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("InventoryGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "InventoryGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 10
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	screenGui = gui

	local scaleInst = Instance.new("UIScale")
	scaleInst.Name = "ResponsiveScale"
	scaleInst.Scale = 1
	scaleInst.Parent = gui
	uiScale = scaleInst
	updateResponsiveScale()

	-- 1. SideCategories (Left side, extensible for future Pets & Eggs)
	local sideFrame = Instance.new("Frame")
	sideFrame.Name = "SideCategories"
	sideFrame.AnchorPoint = Vector2.new(0, 0.5)
	sideFrame.Position = UDim2.new(0, 14, 0.5, 0)
	sideFrame.Size = UDim2.fromOffset(70, 420)
	sideFrame.BackgroundTransparency = 1
	sideFrame.ZIndex = 9
	sideFrame.Parent = gui
	sideCategoriesFrame = sideFrame

	local sideLayout = Instance.new("UIListLayout")
	sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sideLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	sideLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	sideLayout.Padding = UDim.new(0, 10)
	sideLayout.Parent = sideFrame

	local shovelsCatBtn = InventoryController.RegisterSideCategory({
		Id = "Shovels",
		Label = "Shovels",
		Order = 1,
		BuildViewportModel = function()
			return ShovelModelBuilder.CloneBagPreviewModel()
		end,
		OnActivated = function()
			InventoryController.TogglePanel()
		end,
	})
	if shovelsCatBtn then
		sideShovelsStroke = shovelsCatBtn:FindFirstChildOfClass("UIStroke")
	end

	-- 2. Hotbar (Bottom center, safe margin above screen edge)
	local hb = Instance.new("Frame")
	hb.Name = "Hotbar"
	hb.AnchorPoint = Vector2.new(0.5, 1)
	hb.Position = UDim2.new(0.5, 0, 1, -14)
	hb.Size = UDim2.fromOffset(384, 72)
	hb.BackgroundTransparency = 1
	hb.ZIndex = 9
	hb.Parent = gui
	hotbarFrame = hb

	local hbLayout = Instance.new("UIListLayout")
	hbLayout.FillDirection = Enum.FillDirection.Horizontal
	hbLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	hbLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	hbLayout.SortOrder = Enum.SortOrder.LayoutOrder
	hbLayout.Padding = UDim.new(0, 8)
	hbLayout.Parent = hb

	-- Slot 1: Active Shovel
	local s1Btn, s1Stroke = createHotbarSlotBase(hb, "Slot1_Shovel", 1, false)
	slot1Button = s1Btn
	slot1Stroke = s1Stroke

	local s1Vp = Instance.new("ViewportFrame")
	s1Vp.Name = "ShovelViewport"
	s1Vp.AnchorPoint = Vector2.new(0.5, 0.5)
	s1Vp.Position = UDim2.new(0.5, 0, 0.44, 0)
	s1Vp.Size = UDim2.fromOffset(54, 48)
	s1Vp.BackgroundTransparency = 1
	s1Vp.ZIndex = 2
	s1Vp.Parent = s1Btn
	slot1Viewport = s1Vp

	local s1Name = Instance.new("TextLabel")
	s1Name.Name = "ItemName"
	s1Name.AnchorPoint = Vector2.new(0.5, 1)
	s1Name.Position = UDim2.new(0.5, 0, 1, -5)
	s1Name.Size = UDim2.new(1, -8, 0, 14)
	s1Name.BackgroundTransparency = 1
	s1Name.Font = Enum.Font.GothamBold
	s1Name.TextSize = 10
	s1Name.TextTruncate = Enum.TextTruncate.AtEnd
	s1Name.TextColor3 = COLORS.TextPrimary
	s1Name.Text = "Rusty"
	s1Name.ZIndex = 3
	s1Name.Parent = s1Btn
	slot1NameLabel = s1Name

	local s1Rarity = Instance.new("Frame")
	s1Rarity.Name = "RarityAccent"
	s1Rarity.AnchorPoint = Vector2.new(0.5, 1)
	s1Rarity.Position = UDim2.new(0.5, 0, 1, -2)
	s1Rarity.Size = UDim2.new(0.66, 0, 0, 2)
	s1Rarity.BorderSizePixel = 0
	s1Rarity.BackgroundColor3 = RarityConfig.ById.Common.Color
	s1Rarity.ZIndex = 3
	s1Rarity.Parent = s1Btn
	slot1RarityBar = s1Rarity

	s1Btn.MouseEnter:Connect(function()
		if not isToolActive then
			s1Btn.BackgroundColor3 = COLORS.SlotHover
		end
	end)
	s1Btn.MouseLeave:Connect(function()
		refreshHotbarVisuals()
	end)
	s1Btn.Activated:Connect(function()
		InventoryController.ActivateSlot1()
	end)

	-- Slot 2: Bag / Shovel Collection
	local s2Btn, s2Stroke = createHotbarSlotBase(hb, "Slot2_Bag", 2, false)
	slot2Button = s2Btn
	slot2Stroke = s2Stroke

	local s2Vp = Instance.new("ViewportFrame")
	s2Vp.Name = "BagViewport"
	s2Vp.AnchorPoint = Vector2.new(0.5, 0.5)
	s2Vp.Position = UDim2.new(0.5, 0, 0.43, 0)
	s2Vp.Size = UDim2.fromOffset(50, 46)
	s2Vp.BackgroundTransparency = 1
	s2Vp.ZIndex = 2
	s2Vp.Parent = s2Btn
	populateBagViewport(s2Vp)

	local s2Name = Instance.new("TextLabel")
	s2Name.Name = "ItemName"
	s2Name.AnchorPoint = Vector2.new(0.5, 1)
	s2Name.Position = UDim2.new(0.5, 0, 1, -5)
	s2Name.Size = UDim2.new(1, -8, 0, 14)
	s2Name.BackgroundTransparency = 1
	s2Name.Font = Enum.Font.GothamBold
	s2Name.TextSize = 10
	s2Name.TextColor3 = COLORS.TextPrimary
	s2Name.Text = "Bag"
	s2Name.ZIndex = 3
	s2Name.Parent = s2Btn

	s2Btn.MouseEnter:Connect(function()
		if not isPanelOpen then
			s2Btn.BackgroundColor3 = COLORS.SlotHover
		end
	end)
	s2Btn.MouseLeave:Connect(function()
		refreshHotbarVisuals()
	end)
	s2Btn.Activated:Connect(function()
		InventoryController.TogglePanel()
	end)

	-- Slots 3..5: Clean reserved empty slots (no fake items!)
	for emptyIdx = 3, 5 do
		createHotbarSlotBase(hb, string.format("Slot%d_Empty", emptyIdx), emptyIdx, true)
	end

	-- 3. Modal Backdrop (absorbs clicks while open & closes panel when clicking outside)
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
		InventoryController.ClosePanel()
	end)

	-- 4. ShovelInventoryPanel (Two-column center modal)
	local panel = Instance.new("Frame")
	panel.Name = "ShovelInventoryPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.44, 0)
	panel.Size = UDim2.fromOffset(720, 488)
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

	-- Header Bar
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 48)
	header.BackgroundColor3 = COLORS.HeaderBg
	header.BorderSizePixel = 0
	header.ZIndex = 11
	header.Parent = panel

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 14)
	headerCorner.Parent = header

	local headerTitle = Instance.new("TextLabel")
	headerTitle.Name = "Title"
	headerTitle.Position = UDim2.fromOffset(18, 0)
	headerTitle.Size = UDim2.fromOffset(260, 48)
	headerTitle.BackgroundTransparency = 1
	headerTitle.Font = Enum.Font.GothamBlack
	headerTitle.TextSize = 18
	headerTitle.TextXAlignment = Enum.TextXAlignment.Left
	headerTitle.TextColor3 = COLORS.TextPrimary
	headerTitle.Text = "KOLEKSI SHOVEL"
	headerTitle.ZIndex = 12
	headerTitle.Parent = header

	local countPill = Instance.new("TextLabel")
	countPill.Name = "OwnedCount"
	countPill.AnchorPoint = Vector2.new(1, 0.5)
	countPill.Position = UDim2.new(1, -58, 0.5, 0)
	countPill.Size = UDim2.fromOffset(88, 26)
	countPill.BackgroundColor3 = Color3.fromRGB(42, 48, 66)
	countPill.BorderSizePixel = 0
	countPill.Font = Enum.Font.GothamBold
	countPill.TextSize = 12
	countPill.TextColor3 = COLORS.TextSecondary
	countPill.Text = "1 Milik"
	countPill.ZIndex = 12
	countPill.Parent = header
	ownedCountLabel = countPill

	local countCorner = Instance.new("UICorner")
	countCorner.CornerRadius = UDim.new(1, 0)
	countCorner.Parent = countPill

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -12, 0.5, 0)
	closeBtn.Size = UDim2.fromOffset(34, 34)
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
		InventoryController.ClosePanel()
	end)

	-- Left Column: ShovelList (~48% width)
	local listFrame = Instance.new("ScrollingFrame")
	listFrame.Name = "ShovelList"
	listFrame.Position = UDim2.fromOffset(14, 60)
	listFrame.Size = UDim2.new(0.47, -18, 1, -74)
	listFrame.BackgroundColor3 = COLORS.ListBg
	listFrame.BorderSizePixel = 0
	listFrame.ScrollBarThickness = 5
	listFrame.ScrollBarImageColor3 = Color3.fromRGB(110, 124, 156)
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	listFrame.ZIndex = 11
	listFrame.Parent = panel
	shovelListScroll = listFrame

	local listCorner = Instance.new("UICorner")
	listCorner.CornerRadius = UDim.new(0, 11)
	listCorner.Parent = listFrame

	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingTop = UDim.new(0, 8)
	listPadding.PaddingBottom = UDim.new(0, 8)
	listPadding.PaddingLeft = UDim.new(0, 8)
	listPadding.PaddingRight = UDim.new(0, 8)
	listPadding.Parent = listFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 7)
	listLayout.Parent = listFrame

	-- Right Column: ShovelDetail (~51% width, dark bluish-grey)
	local detailFrame = Instance.new("ScrollingFrame")
	detailFrame.Name = "ShovelDetail"
	detailFrame.AnchorPoint = Vector2.new(1, 0)
	detailFrame.Position = UDim2.new(1, -14, 0, 60)
	detailFrame.Size = UDim2.new(0.53, -18, 1, -74)
	detailFrame.BackgroundColor3 = COLORS.DetailBg
	detailFrame.BorderSizePixel = 0
	detailFrame.ScrollBarThickness = 4
	detailFrame.ScrollBarImageColor3 = Color3.fromRGB(110, 124, 156)
	detailFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	detailFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	detailFrame.ZIndex = 11
	detailFrame.Parent = panel
	detailScroll = detailFrame

	local detailCorner = Instance.new("UICorner")
	detailCorner.CornerRadius = UDim.new(0, 11)
	detailCorner.Parent = detailFrame

	local detailStroke = Instance.new("UIStroke")
	detailStroke.Color = Color3.fromRGB(70, 84, 112)
	detailStroke.Thickness = 1.2
	detailStroke.Parent = detailFrame

	local detailPad = Instance.new("UIPadding")
	detailPad.PaddingTop = UDim.new(0, 10)
	detailPad.PaddingBottom = UDim.new(0, 10)
	detailPad.PaddingLeft = UDim.new(0, 14)
	detailPad.PaddingRight = UDim.new(0, 14)
	detailPad.Parent = detailFrame

	local detailLayout = Instance.new("UIListLayout")
	detailLayout.SortOrder = Enum.SortOrder.LayoutOrder
	detailLayout.Padding = UDim.new(0, 6)
	detailLayout.Parent = detailFrame

	-- Detail Item 1: Large 3D Shovel Preview
	local previewCard = Instance.new("Frame")
	previewCard.Name = "PreviewContainer"
	previewCard.Size = UDim2.new(1, 0, 0, 128)
	previewCard.BackgroundColor3 = COLORS.DetailViewportBg
	previewCard.BorderSizePixel = 0
	previewCard.LayoutOrder = 1
	previewCard.Parent = detailFrame

	local previewCorner = Instance.new("UICorner")
	previewCorner.CornerRadius = UDim.new(0, 10)
	previewCorner.Parent = previewCard

	local previewStroke = Instance.new("UIStroke")
	previewStroke.Color = Color3.fromRGB(58, 70, 96)
	previewStroke.Thickness = 1
	previewStroke.Parent = previewCard

	local bigVp = Instance.new("ViewportFrame")
	bigVp.Name = "LargePreviewViewport"
	bigVp.Size = UDim2.fromScale(1, 1)
	bigVp.BackgroundTransparency = 1
	bigVp.Active = true
	bigVp.Parent = previewCard
	detailViewport = bigVp

	local dragHint = Instance.new("TextLabel")
	dragHint.Name = "DragHint"
	dragHint.AnchorPoint = Vector2.new(1, 1)
	dragHint.Position = UDim2.new(1, -8, 1, -4)
	dragHint.Size = UDim2.fromOffset(110, 14)
	dragHint.BackgroundTransparency = 1
	dragHint.Font = Enum.Font.GothamMedium
	dragHint.TextSize = 10
	dragHint.TextXAlignment = Enum.TextXAlignment.Right
	dragHint.TextColor3 = COLORS.TextMuted
	dragHint.Text = "Geser untuk putar 3D"
	dragHint.Parent = previewCard

	bigVp.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			isDraggingPreview = true
			lastDragX = input.Position.X
		end
	end)
	bigVp.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			isDraggingPreview = false
		end
	end)

	-- Detail Item 2: Shovel Name
	local dName = Instance.new("TextLabel")
	dName.Name = "ShovelName"
	dName.Size = UDim2.new(1, 0, 0, 24)
	dName.BackgroundTransparency = 1
	dName.Font = Enum.Font.GothamBlack
	dName.TextSize = 20
	dName.TextXAlignment = Enum.TextXAlignment.Left
	dName.TextColor3 = COLORS.TextPrimary
	dName.Text = "Rusty Shovel"
	dName.LayoutOrder = 2
	dName.Parent = detailFrame
	detailNameLabel = dName

	-- Detail Item 3 & 4: Rarity + Ownership/Active Status Row
	local metaRow = Instance.new("Frame")
	metaRow.Name = "MetaRow"
	metaRow.Size = UDim2.new(1, 0, 0, 24)
	metaRow.BackgroundTransparency = 1
	metaRow.LayoutOrder = 3
	metaRow.Parent = detailFrame

	local metaLayout = Instance.new("UIListLayout")
	metaLayout.FillDirection = Enum.FillDirection.Horizontal
	metaLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	metaLayout.SortOrder = Enum.SortOrder.LayoutOrder
	metaLayout.Padding = UDim.new(0, 8)
	metaLayout.Parent = metaRow

	local rBadge = Instance.new("TextLabel")
	rBadge.Name = "RarityBadge"
	rBadge.Size = UDim2.fromOffset(92, 22)
	rBadge.BackgroundColor3 = Color3.fromRGB(24, 29, 40)
	rBadge.BorderSizePixel = 0
	rBadge.Font = Enum.Font.GothamBlack
	rBadge.TextSize = 11
	rBadge.TextColor3 = RarityConfig.ById.Common.Color
	rBadge.Text = "COMMON"
	rBadge.LayoutOrder = 1
	rBadge.Parent = metaRow
	detailRarityBadge = rBadge

	local rCorner = Instance.new("UICorner")
	rCorner.CornerRadius = UDim.new(0, 6)
	rCorner.Parent = rBadge

	local rStroke = Instance.new("UIStroke")
	rStroke.Color = RarityConfig.ById.Common.Color
	rStroke.Thickness = 1.2
	rStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rStroke.Parent = rBadge

	local sBadge = Instance.new("TextLabel")
	sBadge.Name = "StatusBadge"
	sBadge.Size = UDim2.fromOffset(86, 22)
	sBadge.BackgroundColor3 = Color3.fromRGB(38, 128, 78)
	sBadge.BorderSizePixel = 0
	sBadge.Font = Enum.Font.GothamBlack
	sBadge.TextSize = 11
	sBadge.TextColor3 = Color3.fromRGB(224, 255, 234)
	sBadge.Text = "DIPAKAI"
	sBadge.LayoutOrder = 2
	sBadge.Parent = metaRow
	detailStatusBadge = sBadge

	local sCorner = Instance.new("UICorner")
	sCorner.CornerRadius = UDim.new(0, 6)
	sCorner.Parent = sBadge

	-- Detail Item 5: Short Description
	local desc = Instance.new("TextLabel")
	desc.Name = "Description"
	desc.Size = UDim2.new(1, 0, 0, 32)
	desc.AutomaticSize = Enum.AutomaticSize.Y
	desc.BackgroundTransparency = 1
	desc.Font = Enum.Font.GothamMedium
	desc.TextSize = 12
	desc.TextWrapped = true
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextColor3 = COLORS.TextSecondary
	desc.Text = ""
	desc.LayoutOrder = 4
	desc.Parent = detailFrame
	detailDescLabel = desc

	-- Detail Item 6: Statistics with Normalized Progress Bars
	local statsBox = Instance.new("Frame")
	statsBox.Name = "StatsContainer"
	statsBox.Size = UDim2.new(1, 0, 0, 112)
	statsBox.BackgroundTransparency = 1
	statsBox.LayoutOrder = 5
	statsBox.Parent = detailFrame

	local statsLayout = Instance.new("UIListLayout")
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Padding = UDim.new(0, 5)
	statsLayout.Parent = statsBox

	powerValueLabel, powerFillFrame =
		createStatRow(statsBox, "PowerStat", "Kekuatan Penggalian", COLORS.StatPower, 1)
	speedValueLabel, speedFillFrame =
		createStatRow(statsBox, "SpeedStat", "Kecepatan Penggalian", COLORS.StatSpeed, 2)
	luckValueLabel, luckFillFrame =
		createStatRow(statsBox, "LuckStat", "Keberuntungan (Luck)", COLORS.StatLuck, 3)

	-- Error Banner (shown only on failed equip)
	local errLbl = Instance.new("TextLabel")
	errLbl.Name = "ErrorBanner"
	errLbl.Size = UDim2.new(1, 0, 0, 20)
	errLbl.BackgroundTransparency = 1
	errLbl.Font = Enum.Font.GothamBold
	errLbl.TextSize = 12
	errLbl.TextColor3 = COLORS.ErrorText
	errLbl.TextXAlignment = Enum.TextXAlignment.Center
	errLbl.Text = ""
	errLbl.Visible = false
	errLbl.LayoutOrder = 6
	errLbl.Parent = detailFrame
	errorBannerLabel = errLbl

	-- Detail Item 7: Wide PAKAI / DIPAKAI Button
	local eqBtn = Instance.new("TextButton")
	eqBtn.Name = "EquipButton"
	eqBtn.Size = UDim2.new(1, 0, 0, 40)
	eqBtn.BackgroundColor3 = COLORS.EquipBtnEquipped
	eqBtn.BorderSizePixel = 0
	eqBtn.Font = Enum.Font.GothamBlack
	eqBtn.TextSize = 15
	eqBtn.TextColor3 = COLORS.TextPrimary
	eqBtn.Text = "DIPAKAI"
	eqBtn.LayoutOrder = 7
	eqBtn.Parent = detailFrame
	equipActionButton = eqBtn

	local eqCorner = Instance.new("UICorner")
	eqCorner.CornerRadius = UDim.new(0, 10)
	eqCorner.Parent = eqBtn

	eqBtn.MouseEnter:Connect(function()
		if eqBtn.Active then
			eqBtn.BackgroundColor3 = COLORS.EquipBtnHover
		end
	end)
	eqBtn.MouseLeave:Connect(function()
		refreshDetailPanel()
	end)
	eqBtn.Activated:Connect(function()
		if eqBtn.Active then
			task.spawn(function()
				InventoryController.RequestEquipShovel(selectedShovelId)
			end)
		end
	end)

	rebuildShovelList()
	refreshHotbarVisuals()
end

function InventoryController.Start()
	if started then
		return
	end
	started = true

	disableDefaultRobloxBackpack()

	-- Seed initial attributes if already replicated before server roundtrip completes
	local attrEquipped = LocalPlayer:GetAttribute("EquippedShovel")
	if type(attrEquipped) == "string" and ShovelsConfig.All[attrEquipped] ~= nil then
		equippedShovelId = attrEquipped
		selectedShovelId = attrEquipped
	end
	local attrActive = LocalPlayer:GetAttribute("ShovelToolActive")
	if type(attrActive) == "boolean" then
		isToolActive = attrActive
	end

	buildInventoryGui()

	--Viewport resize listener for responsive scaling
	local function bindCameraViewport()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveScale)
			updateResponsiveScale()
		end
	end
	bindCameraViewport()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCameraViewport)

	-- Live attribute & StateSync listeners
	LocalPlayer:GetAttributeChangedSignal("EquippedShovel"):Connect(function()
		local eq = LocalPlayer:GetAttribute("EquippedShovel")
		if type(eq) == "string" and ShovelsConfig.All[eq] ~= nil then
			equippedShovelId = eq
			if table.find(ownedShovels, eq) == nil then
				table.insert(ownedShovels, eq)
			end
			rebuildShovelList()
			refreshHotbarVisuals()
		end
	end)

	LocalPlayer:GetAttributeChangedSignal("ShovelToolActive"):Connect(function()
		local act = LocalPlayer:GetAttribute("ShovelToolActive")
		if type(act) == "boolean" then
			isToolActive = act
			refreshHotbarVisuals()
		end
	end)

	Remotes.GetEvent("StateSync").OnClientEvent:Connect(function(payload: any)
		applyInventoryPayload(payload)
	end)

	LocalPlayer.CharacterAdded:Connect(function()
		disableDefaultRobloxBackpack()
		task.defer(function()
			refreshHotbarVisuals()
		end)
	end)

	-- Keyboard shortcuts: 1 (Slot 1 Shovel), 2 (Slot 2 Bag/Shovels), Escape (Close Panel)
	-- Bound at high priority via ContextActionService so Roblox CoreGui BackpackScript does not swallow 1 & 2.
	ContextActionService:BindActionAtPriority(
		"DigPalsHotbarShortcuts",
		function(_actionName: string, inputState: Enum.UserInputState, inputObject: InputObject)
			if UserInputService:GetFocusedTextBox() ~= nil then
				return Enum.ContextActionResult.Pass
			end

			local keyCode = inputObject.KeyCode
			if keyCode == Enum.KeyCode.One or keyCode == Enum.KeyCode.KeypadOne then
				if inputState == Enum.UserInputState.Begin and not isPanelOpen then
					InventoryController.ActivateSlot1()
				end
				return Enum.ContextActionResult.Sink
			elseif keyCode == Enum.KeyCode.Two or keyCode == Enum.KeyCode.KeypadTwo then
				if inputState == Enum.UserInputState.Begin then
					InventoryController.TogglePanel()
				end
				return Enum.ContextActionResult.Sink
			elseif keyCode == Enum.KeyCode.Escape then
				if isPanelOpen then
					if inputState == Enum.UserInputState.Begin then
						InventoryController.ClosePanel()
					end
					return Enum.ContextActionResult.Sink
				end
				return Enum.ContextActionResult.Pass
			end

			return Enum.ContextActionResult.Pass
		end,
		false,
		Enum.ContextActionPriority.High.Value + 200,
		Enum.KeyCode.One,
		Enum.KeyCode.KeypadOne,
		Enum.KeyCode.Two,
		Enum.KeyCode.KeypadTwo,
		Enum.KeyCode.Escape
	)

	-- Fallback Escape listener in case CoreGui intercepts Escape before ContextActionService
	UserInputService.InputBegan:Connect(function(input: InputObject, _gameProcessed: boolean)
		if UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape and isPanelOpen then
			InventoryController.ClosePanel()
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

	-- Gentle 3D preview turntable & drag update when panel is open
	RunService.RenderStepped:Connect(function(dt: number)
		if not isPanelOpen or not detailPreviewModel then
			return
		end
		if not isDraggingPreview then
			detailSpinYaw += dt * 0.65
		end
		local yaw = math.sin(detailSpinYaw) * 0.35
		if isDraggingPreview then
			yaw = detailSpinYaw
		end
		detailPreviewModel:PivotTo(
			CFrame.Angles(math.rad(10), math.rad(22) + yaw, math.rad(-36))
		)
	end)

	-- Request authoritative initial state once profile is loaded on server
	task.spawn(function()
		local ok, initialPayload = pcall(function()
			return Remotes.GetFunction("GetInventoryState"):InvokeServer()
		end)
		if ok and type(initialPayload) == "table" then
			applyInventoryPayload(initialPayload)
		end
	end)
end

return InventoryController
