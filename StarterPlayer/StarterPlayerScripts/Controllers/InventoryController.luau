--!strict
-- MASTER HOTBAR & INVENTORY UI SYSTEM FOR DIG PALS
-- Nine-slot expedition hotbar, shovel locker, and three-category field bag.
-- Native Roblox UI components, responsive layout, smooth TweenService animations, and clean state management.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local InventoryController = {}
local MenuIcons = require(script.Parent:WaitForChild("MenuIcons"))

-- ============================================================================
-- 1. CONFIGURATION & ASSET IDS
-- ============================================================================
export type AssetConfigType = {
	Hotbar: {
		DiamondShovel: string,
		RustyShovel: string,
		StoneShovel: string,
		IronShovel: string,
		GoldenShovel: string,
		MossyShovel: string,
		MoonlitShovel: string,
		ShovelSilhouette: string,
		BackpackSilhouette: string,
		Shovel: string,
		Backpack: string,
		CardDiamondShovelFull: string,
		CardShovelFull: string,
		CardItemsFull: string,
	},
	Tabs: {
		Items: string,
		Shovel: string,
		Eggs: string,
		Pet: string,
	},
	CloseButton: string,
}

local ASSETS: AssetConfigType = {
	Hotbar = {
		DiamondShovel = "rbxassetid://91702610144104",
		RustyShovel = "rbxassetid://97280527431570",
		StoneShovel = "rbxassetid://133034591088020",
		IronShovel = "rbxassetid://97280527431570",
		GoldenShovel = "rbxassetid://100895397684604",
		MossyShovel = "rbxassetid://103006088766240",
		MoonlitShovel = "rbxassetid://133100007987104",
		ShovelSilhouette = "rbxassetid://84922947564946",
		BackpackSilhouette = "rbxassetid://109542587138207",
		Shovel = MenuIcons.Shovel,
		Backpack = MenuIcons.Bag,
		CardDiamondShovelFull = "rbxassetid://139957201917755",
		CardShovelFull = "rbxassetid://93638470629241",
		CardItemsFull = "rbxassetid://107111835155021",
	},
	Tabs = {
		Items = MenuIcons.Items,
		Shovel = MenuIcons.Shovel,
		Eggs = MenuIcons.Eggs,
		Pet = MenuIcons.Pet,
	},
	CloseButton = "rbxassetid://125212219786214",
}

-- Shovel configuration & visual styling for Hotbar Slot 1 dynamic sync
local SHOVEL_CONFIGS: {
	[string]: {
		DisplayName: string,
		Icon: string,
		TextColor: Color3,
	},
} = {
	RustyShovel = {
		DisplayName = "Rusty Shovel",
		Icon = "rbxassetid://97280527431570",
		TextColor = Color3.fromRGB(235, 185, 130),
	},
	StoneShovel = {
		DisplayName = "Stone Shovel",
		Icon = "rbxassetid://133034591088020",
		TextColor = Color3.fromRGB(215, 220, 230),
	},
	IronShovel = {
		DisplayName = "Iron Shovel",
		Icon = "rbxassetid://97280527431570",
		TextColor = Color3.fromRGB(195, 225, 255),
	},
	GoldenShovel = {
		DisplayName = "Golden Shovel",
		Icon = "rbxassetid://100895397684604",
		TextColor = Color3.fromRGB(255, 220, 65),
	},
	DiamondShovel = {
		DisplayName = "Diamond Shovel",
		Icon = "rbxassetid://91702610144104",
		TextColor = Color3.fromRGB(70, 230, 255),
	},
	MossyShovel = {
		DisplayName = "Mossy Shovel",
		Icon = "rbxassetid://103006088766240",
		TextColor = Color3.fromRGB(125, 245, 155),
	},
	MoonlitShovel = {
		DisplayName = "Moonlit Shovel",
		Icon = "rbxassetid://133100007987104",
		TextColor = Color3.fromRGB(220, 190, 255),
	},
}

-- Visual Palette matching reference images (95%+ visual similarity)
local COLORS = {
	-- Hotbar Card Colors
	CardBgNormal = Color3.fromRGB(80, 123, 141),
	CardBgNormalGradient = Color3.fromRGB(43, 76, 91),
	CardBgSelectedDiamond = Color3.fromRGB(255, 205, 86),
	CardBgSelectedGradient = Color3.fromRGB(206, 128, 38),
	CardBorderNormal = Color3.fromRGB(10, 8, 8),
	CardBorderSelected = Color3.fromRGB(255, 231, 139), -- Electric Cyan
	CardGlowCyan = Color3.fromRGB(255, 231, 139),

	-- Badge Colors
	BadgeBg = Color3.fromRGB(16, 16, 18),
	BadgeBorder = Color3.fromRGB(60, 60, 68),
	BadgeText = Color3.fromRGB(255, 255, 255),

	-- Hotbar Text Colors
	TextDiamondShovel = Color3.fromRGB(70, 230, 255),
	TextShovel = Color3.fromRGB(255, 255, 255),
	TextItems = Color3.fromRGB(254, 227, 128),

	-- Main Inventory Panel Colors
	PanelBg = Color3.fromRGB(255, 243, 211),
	PanelBgGradient = Color3.fromRGB(230, 211, 166),
	PanelBorder = Color3.fromRGB(16, 12, 14),
	PanelRim = Color3.fromRGB(255, 252, 232),
	ContentBg = Color3.fromRGB(247, 235, 205),
	ContentBorder = Color3.fromRGB(32, 28, 30),
	ScrollbarTrack = Color3.fromRGB(75, 75, 90),

	-- Tab Inactive Colors
	TabInactiveBg = Color3.fromRGB(70, 101, 114),
	TabInactiveBorder = Color3.fromRGB(18, 20, 24),
	TabInactiveText = Color3.fromRGB(255, 255, 255),

	-- Tab Active Colors (Blue Gradient & Cyan Glow)
	TabActiveGradientTop = Color3.fromRGB(67, 185, 157),
	TabActiveGradientBottom = Color3.fromRGB(27, 127, 115),
	TabActiveBorder = Color3.fromRGB(22, 47, 51),
	TabActiveText = Color3.fromRGB(255, 255, 255),

	-- Close Button Red Gradient
	CloseRedTop = Color3.fromRGB(245, 60, 60),
	CloseRedBottom = Color3.fromRGB(175, 25, 25),
	CloseBorder = Color3.fromRGB(255, 140, 140),
}

-- ============================================================================
-- 2. STATE (SINGLE SOURCE OF TRUTH)
-- ============================================================================
local selectedSlot: number = 1 -- 1: Equipped Shovel, 2: Shovel, 3: Items
local activeCategory: string = "Items" -- "Items", "Shovel", "Eggs", "Pet"
local isInventoryOpen: boolean = false
local started: boolean = false
local currentEquippedShovelId: string = "RustyShovel"

-- UI Instance References
local screenGui: ScreenGui? = nil
local hotbarContainer: Frame? = nil
local hotbarScale: UIScale? = nil

-- Hotbar Slot References
type SlotComponents = {
	Button: ImageButton,
	Stroke: UIStroke,
	GlowStroke: UIStroke?,
	GlowFrame: Frame?,
	BgGradient: UIGradient,
	BadgeFrame: Frame,
	BadgeLabel: TextLabel,
	Icon: ImageLabel,
	NameLabel: TextLabel,
	NameStroke: UIStroke,
}
local slotComponentsByNumber: { [number]: SlotComponents } = {}

-- Inventory Modal References
local modalBackdrop: TextButton? = nil
local inventoryPanel: Frame? = nil
local inventoryScale: UIScale? = nil
local closeButton: ImageButton? = nil
local activeCloseTween: Tween? = nil

type TabComponents = {
	Button: ImageButton,
	Stroke: UIStroke,
	Gradient: UIGradient,
	GlowFrame: Frame?,
	Icon: ImageLabel,
	Label: TextLabel,
}
local tabComponentsByName: { [string]: TabComponents } = {}
local categoryContainersByName: { [string]: ScrollingFrame } = {}

-- Optional callback hook for external systems
local onSlotSelectedHook: ((slotNumber: number) -> ())? = nil
local onCategoryChangedHook: ((category: string) -> ())? = nil

-- Forward declarations of local helper functions
local resolveUI: () -> ()
local equipToolForSlot: (slotNumber: number) -> ()

-- ============================================================================
-- 3. TOOL INTEGRATION (DYNAMIC EQUIPPED SHOVEL SYNC)
-- ============================================================================
function InventoryController.SyncEquippedShovel(targetShovelId: string?)
	resolveUI()
	local id = targetShovelId or LocalPlayer:GetAttribute("EquippedShovel")
	if typeof(id) ~= "string" or id == "" then
		id = "RustyShovel"
	end

	currentEquippedShovelId = id

	local cfg = SHOVEL_CONFIGS[id]
	if not cfg then
		local displayName = id
		pcall(function()
			local Shared = ReplicatedStorage:FindFirstChild("Shared")
			local ShovelsMod = Shared and Shared:FindFirstChild("Config") and Shared.Config:FindFirstChild("Shovels")
			if ShovelsMod then
				local sCfg = require(ShovelsMod) :: any
				if sCfg.All and sCfg.All[id] then
					displayName = sCfg.All[id].DisplayName or id
				end
			end
		end)
		cfg = {
			DisplayName = displayName,
			Icon = ASSETS.Hotbar.RustyShovel,
			TextColor = Color3.fromRGB(255, 255, 255),
		}
	end

	local comp1 = slotComponentsByNumber[1]
	if comp1 then
		comp1.NameLabel.Text = cfg.DisplayName
		comp1.NameLabel.TextColor3 = cfg.TextColor
		comp1.Icon.Image = cfg.Icon
	elseif hotbarContainer then
		local slot1Btn = (hotbarContainer:FindFirstChild("Slot1_EquippedShovel") or hotbarContainer:FindFirstChild("Slot1_DiamondShovel")) :: ImageButton?
		if slot1Btn then
			local nameLbl = slot1Btn:FindFirstChild("SlotName") :: TextLabel?
			local iconImg = slot1Btn:FindFirstChild("SlotIcon") :: ImageLabel?
			if nameLbl then
				nameLbl.Text = cfg.DisplayName
				nameLbl.TextColor3 = cfg.TextColor
			end
			if iconImg then
				iconImg.Image = cfg.Icon
			end
		end
	end

	-- If Slot 1 is currently selected, ensure character equips this shovel tool
	if selectedSlot == 1 then
		equipToolForSlot(1)
	end
end

function equipToolForSlot(slotNumber: number)
	if slotNumber == 1 then
		local shovelId = currentEquippedShovelId or LocalPlayer:GetAttribute("EquippedShovel") or "RustyShovel"
		local character = LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")

		if humanoid and backpack then
			local targetTool: Tool? = nil
			-- Search Backpack
			for _, item in ipairs(backpack:GetChildren()) do
				if item:IsA("Tool") and (item:GetAttribute("ShovelId") == shovelId or item.Name == shovelId or item:GetAttribute("DigPalsShovelTool") == true) then
					targetTool = item
					break
				end
			end
			-- Search Character
			if not targetTool and character then
				for _, item in ipairs(character:GetChildren()) do
					if item:IsA("Tool") and (item:GetAttribute("ShovelId") == shovelId or item.Name == shovelId or item:GetAttribute("DigPalsShovelTool") == true) then
						targetTool = item
						break
					end
				end
			end

			if targetTool and targetTool:IsA("Tool") and targetTool.Parent == backpack then
				pcall(function()
					humanoid:EquipTool(targetTool)
				end)
			end
		end
	end

	if onSlotSelectedHook then
		pcall(onSlotSelectedHook, slotNumber)
	end
end

-- ============================================================================
-- 4. RESPONSIVE UISCALE MANAGEMENT & RESILIENT UI RESOLVER
-- ============================================================================
function resolveUI()
	local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end
	local gui = playerGui:FindFirstChild("DigPalsUI") :: ScreenGui?
	if not gui then
		return
	end
	screenGui = gui

	if not hotbarContainer or not hotbarContainer.Parent then
		hotbarContainer = gui:FindFirstChild("HotbarContainer") :: Frame?
		if hotbarContainer then
			hotbarScale = hotbarContainer:FindFirstChild("HotbarScale") :: UIScale?
		end
	end

	if hotbarContainer then
		for slotNum = 1, 3 do
			if not slotComponentsByNumber[slotNum] or not slotComponentsByNumber[slotNum].Button.Parent then
				local btn = hotbarContainer:FindFirstChild("Slot" .. slotNum .. "_EquippedShovel")
					or hotbarContainer:FindFirstChild("Slot" .. slotNum .. "_DiamondShovel")
					or hotbarContainer:FindFirstChild("Slot" .. slotNum .. "_Shovel")
					or hotbarContainer:FindFirstChild("Slot" .. slotNum .. "_Items")
				if btn and btn:IsA("ImageButton") then
					local stroke = btn:FindFirstChildOfClass("UIStroke")
					local grad = btn:FindFirstChildOfClass("UIGradient")
					local glow = btn:FindFirstChild("SelectionGlow") :: Frame?
					local glowStroke = glow and glow:FindFirstChildOfClass("UIStroke")
					local badge = btn:FindFirstChild("NumberBadge") :: Frame?
					local badgeLbl = badge and badge:FindFirstChild("BadgeNumber") :: TextLabel?
					local icon = btn:FindFirstChild("SlotIcon") :: ImageLabel?
					local nameLbl = btn:FindFirstChild("SlotName") :: TextLabel?
					local nameStroke = nameLbl and nameLbl:FindFirstChildOfClass("UIStroke")
					if stroke and grad and badge and badgeLbl and icon and nameLbl and nameStroke then
						slotComponentsByNumber[slotNum] = {
							Button = btn,
							Stroke = stroke,
							GlowStroke = glowStroke,
							GlowFrame = glow,
							BgGradient = grad,
							BadgeFrame = badge,
							BadgeLabel = badgeLbl,
							Icon = icon,
							NameLabel = nameLbl,
							NameStroke = nameStroke,
						}
					end
				end
			end
		end
	end

	if not modalBackdrop or not modalBackdrop.Parent then
		modalBackdrop = gui:FindFirstChild("ModalBackdrop") :: TextButton?
	end

	if not inventoryPanel or not inventoryPanel.Parent then
		inventoryPanel = gui:FindFirstChild("InventoryPanel") :: Frame?
		if inventoryPanel then
			inventoryScale = inventoryPanel:FindFirstChild("InventoryScale") :: UIScale?
			local contentArea = inventoryPanel:FindFirstChild("ContentArea")
			if contentArea then
				for _, cat in ipairs({ "Items", "Shovel", "Eggs", "Pet" }) do
					local c = contentArea:FindFirstChild(cat .. "Content")
					if c and c:IsA("ScrollingFrame") then
						categoryContainersByName[cat] = c
					end
				end
			end
			local navBar = inventoryPanel:FindFirstChild("NavigationBar")
			if navBar then
				for _, cat in ipairs({ "Items", "Shovel", "Eggs", "Pet" }) do
					local tabBtn = navBar:FindFirstChild(cat .. "Tab")
					if tabBtn and tabBtn:IsA("ImageButton") then
						local stroke = tabBtn:FindFirstChildOfClass("UIStroke")
						local grad = tabBtn:FindFirstChildOfClass("UIGradient")
						local glow = tabBtn:FindFirstChild("ActiveGlow") :: Frame?
						local icon = tabBtn:FindFirstChild("TabIcon") :: ImageLabel?
						local lbl = tabBtn:FindFirstChild("TabLabel") :: TextLabel?
						if stroke and grad and icon and lbl then
							tabComponentsByName[cat] = {
								Button = tabBtn,
								Stroke = stroke,
								Gradient = grad,
								GlowFrame = glow,
								Icon = icon,
								Label = lbl,
							}
						end
					end
				end
			end
		end
	end
end

local function updateResponsiveLayout()
	resolveUI()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
	local vw = vp.X
	local vh = vp.Y

	if hotbarScale then
		local factorX = math.clamp((vw - 28) / 790, 0.25, 1)
		local factorY = math.clamp(vh / 600, 0.4, 1)
		hotbarScale.Scale = math.min(factorX, factorY)
	end

	if inventoryScale then
		local factorX = math.clamp((vw - 24) / 1100, 0.25, 1.05)
		local factorY = math.clamp((vh - 40) / 750, 0.25, 1.05)
		inventoryScale.Scale = math.min(factorX, factorY)
	end
end

-- ============================================================================
-- 5. VISUAL UPDATE FUNCTIONS
-- ============================================================================
function InventoryController.UpdateHotbarAppearance()
	resolveUI()
	for slotNum, comp in pairs(slotComponentsByNumber) do
		local isSelected = (slotNum == selectedSlot)

		if isSelected then
			comp.Stroke.Color = COLORS.CardBorderSelected
			comp.Stroke.Thickness = 4.0
			comp.Button.BackgroundColor3 = COLORS.CardBgSelectedDiamond
			comp.BgGradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, COLORS.CardBgSelectedDiamond),
				ColorSequenceKeypoint.new(1, COLORS.CardBgSelectedGradient),
			})

			if comp.GlowFrame then
				comp.GlowFrame.Visible = true
			end

			pcall(function()
				local popTween = TweenService:Create(comp.Button, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = UDim2.fromOffset(76, 82),
				})
				popTween:Play()
			end)
		else
			comp.Stroke.Color = COLORS.CardBorderNormal
			comp.Stroke.Thickness = 3.5
			comp.Button.BackgroundColor3 = COLORS.CardBgNormal
			comp.BgGradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, COLORS.CardBgNormal),
				ColorSequenceKeypoint.new(1, COLORS.CardBgNormalGradient),
			})

			if comp.GlowFrame then
				comp.GlowFrame.Visible = false
			end

			pcall(function()
				local resetTween = TweenService:Create(comp.Button, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = UDim2.fromOffset(76, 82),
				})
				resetTween:Play()
			end)
		end
	end
end

function InventoryController.UpdateInventoryContent()
	resolveUI()
	for tabName, tabComp in pairs(tabComponentsByName) do
		local isActive = (tabName == activeCategory)

		if isActive then
			tabComp.Button.BackgroundColor3 = COLORS.TabActiveGradientTop
			tabComp.Gradient.Enabled = true
			tabComp.Gradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, COLORS.TabActiveGradientTop),
				ColorSequenceKeypoint.new(1, COLORS.TabActiveGradientBottom),
			})
			tabComp.Stroke.Color = COLORS.TabActiveBorder
			tabComp.Stroke.Thickness = 3.0
			tabComp.Label.TextColor3 = COLORS.TabActiveText

			if tabComp.GlowFrame then
				tabComp.GlowFrame.Visible = true
			end

			pcall(function()
				TweenService:Create(tabComp.Button, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = UDim2.new(tabComp.Button.Size.X.Scale, tabComp.Button.Size.X.Offset, 0, 48),
				}):Play()
			end)
		else
			tabComp.Button.BackgroundColor3 = COLORS.TabInactiveBg
			tabComp.Gradient.Enabled = false
			tabComp.Stroke.Color = COLORS.TabInactiveBorder
			tabComp.Stroke.Thickness = 2.0
			tabComp.Label.TextColor3 = COLORS.TabInactiveText

			if tabComp.GlowFrame then
				tabComp.GlowFrame.Visible = false
			end

			pcall(function()
				TweenService:Create(tabComp.Button, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = UDim2.new(tabComp.Button.Size.X.Scale, tabComp.Button.Size.X.Offset, 0, 44),
				}):Play()
			end)
		end
	end

	for catName, container in pairs(categoryContainersByName) do
		local shouldBeVisible = (catName == activeCategory)
		container.Visible = shouldBeVisible
	end

	if InventoryController.RefreshCollection then InventoryController.RefreshCollection() end
	if onCategoryChangedHook then
		pcall(onCategoryChangedHook, activeCategory)
	end
end

-- ============================================================================
-- 6. NAVIGATION & PUBLIC CONTROLLER API
-- ============================================================================
function InventoryController.SelectHotbarSlot(slotNumber: number)
	if slotNumber < 1 or slotNumber > 9 then
		return
	end

	if slotNumber > 3 then return end
	selectedSlot = slotNumber
	InventoryController.UpdateHotbarAppearance()

	if slotNumber == 1 then
		equipToolForSlot(1)
		if isInventoryOpen then
			InventoryController.CloseInventory()
		end
	elseif slotNumber == 2 then
		InventoryController.OpenInventory("Shovel")
	elseif slotNumber == 3 then
		InventoryController.OpenInventory("Items")
	end
end

function InventoryController.SetActiveCategory(category: string)
	if category ~= "Items" and category ~= "Shovel" and category ~= "Eggs" and category ~= "Pet" then
		return
	end

	activeCategory = category
	InventoryController.UpdateInventoryContent()
end

function InventoryController.OpenInventory(category: string?)
	resolveUI()

	if activeCloseTween then
		activeCloseTween:Cancel()
		activeCloseTween = nil
	end

	if category then
		activeCategory = category
	end

	isInventoryOpen = true
	LocalPlayer:SetAttribute("ActiveShopModal", "Inventory")

	if modalBackdrop then
		modalBackdrop.Visible = true
	end

	if inventoryPanel then
		inventoryPanel.Visible = true
		inventoryPanel.Position = UDim2.fromScale(0.5, 0.48)
	end

	InventoryController.UpdateInventoryContent()
end

function InventoryController.CloseInventory()
	resolveUI()

	if not isInventoryOpen then
		return
	end

	isInventoryOpen = false
	if LocalPlayer:GetAttribute("ActiveShopModal") == "Inventory" then
		LocalPlayer:SetAttribute("ActiveShopModal", "")
	end

	if activeCloseTween then
		activeCloseTween:Cancel()
		activeCloseTween = nil
	end

	if inventoryPanel then
		pcall(function()
			local closeTween = TweenService:Create(inventoryPanel, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromScale(0.5, 0.52),
			})
			activeCloseTween = closeTween
			closeTween:Play()
			closeTween.Completed:Connect(function()
				if not isInventoryOpen then
					if inventoryPanel then
						inventoryPanel.Visible = false
					end
					if modalBackdrop then
						modalBackdrop.Visible = false
					end
				end
				if activeCloseTween == closeTween then
					activeCloseTween = nil
				end
			end)
		end)
	else
		if modalBackdrop then
			modalBackdrop.Visible = false
		end
	end

	InventoryController.UpdateHotbarAppearance()
end

-- Aliases for backwards compatibility with existing DigPals controllers
function InventoryController.IsOpen(): boolean
	return isInventoryOpen
end

function InventoryController.OpenPanel()
	InventoryController.OpenInventory("Items")
end

function InventoryController.ClosePanel()
	InventoryController.CloseInventory()
end

function InventoryController.TogglePanel()
	if isInventoryOpen then
		InventoryController.CloseInventory()
	else
		InventoryController.OpenInventory("Items")
	end
end

function InventoryController.GetActiveCategory(): string
	return activeCategory
end

function InventoryController.GetSelectedSlot(): number
	return selectedSlot
end

function InventoryController.SetSlotSelectedHook(fn: (slotNumber: number) -> ())
	onSlotSelectedHook = fn
end

function InventoryController.SetCategoryChangedHook(fn: (category: string) -> ())
	onCategoryChangedHook = fn
end

function InventoryController.RegisterSideCategory(_spec: any)
	-- Retained as safe no-op for controller compatibility
end

-- ============================================================================
-- 7. NATIVE UI BUILDER
-- ============================================================================
local function buildDigPalsUI()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")

	local existing = playerGui:FindFirstChild("DigPalsUI") or playerGui:FindFirstChild("InventoryGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "DigPalsUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 20
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	screenGui = gui

	-- ------------------------------------------------------------------------
	-- PART 1: HOTBAR CONTAINER (3 Horizontal Slots)
	-- ------------------------------------------------------------------------
	local hotbar = Instance.new("Frame")
	hotbar.Name = "HotbarContainer"
	hotbar.AnchorPoint = Vector2.new(0.5, 1)
	hotbar.Position = UDim2.new(0.5, 0, 1, -22)
	hotbar.Size = UDim2.fromOffset(778, 88)
	hotbar.BackgroundTransparency = 1
	hotbar.BorderSizePixel = 0
	hotbar.ZIndex = 10
	hotbar.Parent = gui
	hotbarContainer = hotbar

	local hbScale = Instance.new("UIScale")
	hbScale.Name = "HotbarScale"
	hbScale.Scale = 1
	hbScale.Parent = hotbar
	hotbarScale = hbScale

	local hbLayout = Instance.new("UIListLayout")
	hbLayout.Name = "CardListLayout"
	hbLayout.FillDirection = Enum.FillDirection.Horizontal
	hbLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	hbLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	hbLayout.SortOrder = Enum.SortOrder.LayoutOrder
	hbLayout.Padding = UDim.new(0, 10)
	hbLayout.Parent = hotbar

	-- Define 3 Slot Configurations
	local initialShovelId = LocalPlayer:GetAttribute("EquippedShovel") or "RustyShovel"
	if typeof(initialShovelId) ~= "string" or initialShovelId == "" then
		initialShovelId = "RustyShovel"
	end
	currentEquippedShovelId = initialShovelId
	local initialCfg = SHOVEL_CONFIGS[initialShovelId] or SHOVEL_CONFIGS.RustyShovel

	local slotConfigs = {
		[1] = {
			Name = "Slot1_EquippedShovel",
			Number = 1,
			Title = initialCfg.DisplayName,
			TitleColor = initialCfg.TextColor,
			IconAsset = initialCfg.Icon,
			IconSize = UDim2.fromOffset(136, 108),
			IconPos = UDim2.new(0.5, 0, 0.42, 0),
		},
		[2] = {
			Name = "Slot2_Shovel",
			Number = 2,
			Title = "Shovels",
			TitleColor = COLORS.TextShovel,
			IconAsset = ASSETS.Hotbar.Shovel,
			IconSize = UDim2.fromOffset(128, 108),
			IconPos = UDim2.new(0.5, 0, 0.44, 0),
		},
		[3] = {
			Name = "Slot3_Items",
			Number = 3,
			Title = "Bag",
			TitleColor = COLORS.TextItems,
			IconAsset = ASSETS.Hotbar.Backpack,
			IconSize = UDim2.fromOffset(120, 106),
			IconPos = UDim2.new(0.5, 0, 0.44, 0),
		},
	}

	for slotNum = 1, 3 do
		local cfg = slotConfigs[slotNum]

		local cardBtn = Instance.new("ImageButton")
		cardBtn.Name = cfg.Name
		cardBtn.LayoutOrder = slotNum
		cardBtn.Size = UDim2.fromOffset(76, 82)
		cardBtn.BackgroundColor3 = COLORS.CardBgNormal
		cardBtn.BorderSizePixel = 0
		cardBtn.AutoButtonColor = false
		cardBtn.ZIndex = 11
		cardBtn.Parent = hotbar

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 16)
		cardCorner.Parent = cardBtn

		local cardStroke = Instance.new("UIStroke")
		cardStroke.Color = COLORS.CardBorderNormal
		cardStroke.Thickness = 3.5
		cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		cardStroke.Parent = cardBtn

		local cardGradient = Instance.new("UIGradient")
		cardGradient.Rotation = 45
		cardGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, COLORS.CardBgNormal),
			ColorSequenceKeypoint.new(1, COLORS.CardBgNormalGradient),
		})
		cardGradient.Parent = cardBtn

		-- Outer Cyan Glow Frame for selected state
		local glowFrame = Instance.new("Frame")
		glowFrame.Name = "SelectionGlow"
		glowFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		glowFrame.Position = UDim2.fromScale(0.5, 0.5)
		glowFrame.Size = UDim2.new(1, 8, 1, 8)
		glowFrame.BackgroundTransparency = 1
		glowFrame.Visible = (slotNum == selectedSlot)
		glowFrame.ZIndex = 10
		glowFrame.Parent = cardBtn

		local glowCorner = Instance.new("UICorner")
		glowCorner.CornerRadius = UDim.new(0, 18)
		glowCorner.Parent = glowFrame

		local glowStroke = Instance.new("UIStroke")
		glowStroke.Color = COLORS.CardGlowCyan
		glowStroke.Thickness = 2.5
		glowStroke.Transparency = 0.35
		glowStroke.Parent = glowFrame

		-- Number Badge (Top-left)
		local badge = Instance.new("Frame")
		badge.Name = "NumberBadge"
		badge.Position = UDim2.fromOffset(12, 12)
		badge.Size = UDim2.fromOffset(36, 36)
		badge.BackgroundColor3 = COLORS.BadgeBg
		badge.BorderSizePixel = 0
		badge.ZIndex = 14
		badge.Parent = cardBtn

		local badgeCorner = Instance.new("UICorner")
		badgeCorner.CornerRadius = UDim.new(0, 8)
		badgeCorner.Parent = badge

		local badgeStroke = Instance.new("UIStroke")
		badgeStroke.Color = COLORS.BadgeBorder
		badgeStroke.Thickness = 2.0
		badgeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		badgeStroke.Parent = badge

		local badgeLbl = Instance.new("TextLabel")
		badgeLbl.Name = "BadgeNumber"
		badgeLbl.Size = UDim2.fromScale(1, 1)
		badgeLbl.BackgroundTransparency = 1
		badgeLbl.Font = Enum.Font.GothamBlack
		badgeLbl.TextSize = 20
		badgeLbl.TextColor3 = COLORS.BadgeText
		badgeLbl.Text = tostring(cfg.Number)
		badgeLbl.Parent = badge

		-- 3D Stylized Cartoon Icon
		local iconImg = Instance.new("ImageLabel")
		iconImg.Name = "SlotIcon"
		iconImg.AnchorPoint = Vector2.new(0.5, 0.5)
		iconImg.Position = cfg.IconPos
		iconImg.Size = cfg.IconSize
		iconImg.BackgroundTransparency = 1
		iconImg.Image = cfg.IconAsset
		iconImg.ScaleType = Enum.ScaleType.Fit
		iconImg.ZIndex = 13
		iconImg.Parent = cardBtn

		-- Bottom Text Label
		local nameLbl = Instance.new("TextLabel")
		nameLbl.Name = "SlotName"
		nameLbl.AnchorPoint = Vector2.new(0.5, 1)
		nameLbl.Position = UDim2.new(0.5, 0, 1, -12)
		nameLbl.Size = UDim2.new(1, -8, 0, 32)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Font = Enum.Font.GothamBlack
		nameLbl.TextSize = if slotNum == 1 then 18 else 23
		nameLbl.TextWrapped = false
		nameLbl.TextTruncate = Enum.TextTruncate.None
		nameLbl.TextColor3 = cfg.TitleColor
		nameLbl.Text = cfg.Title
		nameLbl.ZIndex = 14
		nameLbl.Parent = cardBtn

		local nameStroke = Instance.new("UIStroke")
		nameStroke.Color = Color3.fromRGB(0, 0, 0)
		nameStroke.Thickness = 2.8
		nameStroke.Parent = nameLbl

		slotComponentsByNumber[slotNum] = {
			Button = cardBtn,
			Stroke = cardStroke,
			GlowStroke = glowStroke,
			GlowFrame = glowFrame,
			BgGradient = cardGradient,
			BadgeFrame = badge,
			BadgeLabel = badgeLbl,
			Icon = iconImg,
			NameLabel = nameLbl,
			NameStroke = nameStroke,
		}

		cardBtn.Activated:Connect(function()
			InventoryController.SelectHotbarSlot(slotNum)
		end)
	end

	-- ------------------------------------------------------------------------
	-- PART 2: MAIN INVENTORY PANEL (Modal & 4 Navigation Tabs)
	-- ------------------------------------------------------------------------
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "ModalBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.Visible = false
	backdrop.ZIndex = 25
	backdrop.Parent = gui
	modalBackdrop = backdrop

	backdrop.Activated:Connect(function()
		InventoryController.CloseInventory()
	end)

	local panel = Instance.new("Frame")
	panel.Name = "InventoryPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.48)
	panel.Size = UDim2.new(0.85, 0, 0.74, 0)
	panel.BackgroundColor3 = COLORS.PanelBg
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.Active = true
	panel.Visible = false
	panel.ZIndex = 30
	panel.Parent = gui
	inventoryPanel = panel

	local panelScale = Instance.new("UIScale")
	panelScale.Name = "InventoryScale"
	panelScale.Scale = 1
	panelScale.Parent = panel
	inventoryScale = panelScale

	local panelSizeLimit = Instance.new("UISizeConstraint")
	panelSizeLimit.Name = "PanelSizeConstraint"
	panelSizeLimit.MinSize = Vector2.new(500, 340)
	panelSizeLimit.MaxSize = Vector2.new(1040, 620)
	panelSizeLimit.Parent = panel

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 18)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = COLORS.PanelBorder
	panelStroke.Thickness = 4.0
	panelStroke.Parent = panel

	local panelGradient = Instance.new("UIGradient")
	panelGradient.Rotation = 90
	panelGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, COLORS.PanelBg),
		ColorSequenceKeypoint.new(1, COLORS.PanelBgGradient),
	})
	panelGradient.Parent = panel

	-- Subtle Decorative Textured Rim (Reference Image 1 inner border styling)
	local rim = Instance.new("Frame")
	rim.Name = "BorderTrim"
	rim.AnchorPoint = Vector2.new(0.5, 0.5)
	rim.Position = UDim2.fromScale(0.5, 0.5)
	rim.Size = UDim2.new(1, -8, 1, -8)
	rim.BackgroundTransparency = 1
	rim.BorderSizePixel = 0
	rim.ZIndex = 31
	rim.Parent = panel

	local rimCorner = Instance.new("UICorner")
	rimCorner.CornerRadius = UDim.new(0, 16)
	rimCorner.Parent = rim

	local rimStroke = Instance.new("UIStroke")
	rimStroke.Color = COLORS.PanelRim
	rimStroke.Thickness = 2.0
	rimStroke.Transparency = 0.5
	rimStroke.Parent = rim

	-- ------------------------------------------------------------------------
	-- PART 3: NAVIGATION BAR & 4 TABS (Items, Shovel, Eggs, Pet)
	-- ------------------------------------------------------------------------
	local navBar = Instance.new("Frame")
	navBar.Name = "NavigationBar"
	navBar.Position = UDim2.fromOffset(20, 16)
	navBar.Size = UDim2.new(1, -90, 0, 52)
	navBar.BackgroundTransparency = 1
	navBar.BorderSizePixel = 0
	navBar.ZIndex = 33
	navBar.Parent = panel

	local navLayout = Instance.new("UIListLayout")
	navLayout.Name = "TabLayout"
	navLayout.FillDirection = Enum.FillDirection.Horizontal
	navLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	navLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	navLayout.Padding = UDim.new(0, 10)
	navLayout.SortOrder = Enum.SortOrder.LayoutOrder
	navLayout.Parent = navBar

	local tabConfigs = {
		[1] = {
			Id = "Items",
			Order = 1,
			Title = "Bag",
			IconAsset = ASSETS.Tabs.Items,
			Width = 162,
			IconSize = UDim2.fromOffset(36, 32),
		},
		[2] = {
			Id = "Shovel",
			Order = 2,
			Title = "Shovels",
			IconAsset = ASSETS.Tabs.Shovel,
			Width = 160,
			IconSize = UDim2.fromOffset(36, 32),
		},
		[3] = {
			Id = "Eggs",
			Order = 3,
			Title = "Eggs",
			IconAsset = ASSETS.Tabs.Eggs,
			Width = 152,
			IconSize = UDim2.fromOffset(34, 32),
		},
		[4] = {
			Id = "Pet",
			Order = 4,
			Title = "Pet",
			IconAsset = ASSETS.Tabs.Pet,
			Width = 142,
			IconSize = UDim2.fromOffset(34, 32),
		},
	}

	for _, tCfg in ipairs(tabConfigs) do
		local tabBtn = Instance.new("ImageButton")
		tabBtn.Name = tCfg.Id .. "Tab"
		tabBtn.LayoutOrder = tCfg.Order
		tabBtn.Size = UDim2.fromOffset(tCfg.Width, 46)
		tabBtn.BackgroundColor3 = COLORS.TabInactiveBg
		tabBtn.BorderSizePixel = 0
		tabBtn.AutoButtonColor = false
		tabBtn.ZIndex = 34
		tabBtn.Parent = navBar

		local tabCorner = Instance.new("UICorner")
		tabCorner.CornerRadius = UDim.new(0, 12)
		tabCorner.Parent = tabBtn

		local tabStroke = Instance.new("UIStroke")
		tabStroke.Color = COLORS.TabInactiveBorder
		tabStroke.Thickness = 2.0
		tabStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		tabStroke.Parent = tabBtn

		local tabGradient = Instance.new("UIGradient")
		tabGradient.Rotation = 90
		tabGradient.Enabled = false
		tabGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, COLORS.TabActiveGradientTop),
			ColorSequenceKeypoint.new(1, COLORS.TabActiveGradientBottom),
		})
		tabGradient.Parent = tabBtn

		-- Cyan Glow for active tab
		local tabGlow = Instance.new("Frame")
		tabGlow.Name = "ActiveGlow"
		tabGlow.AnchorPoint = Vector2.new(0.5, 0.5)
		tabGlow.Position = UDim2.fromScale(0.5, 0.5)
		tabGlow.Size = UDim2.new(1, 6, 1, 6)
		tabGlow.BackgroundTransparency = 1
		tabGlow.Visible = false
		tabGlow.ZIndex = 33
		tabGlow.Parent = tabBtn

		local tgCorner = Instance.new("UICorner")
		tgCorner.CornerRadius = UDim.new(0, 14)
		tgCorner.Parent = tabGlow

		local tgStroke = Instance.new("UIStroke")
		tgStroke.Color = COLORS.TabActiveBorder
		tgStroke.Thickness = 2.0
		tgStroke.Transparency = 0.4
		tgStroke.Parent = tabGlow

		-- Left Icon inside Tab
		local tabIcon = Instance.new("ImageLabel")
		tabIcon.Name = "TabIcon"
		tabIcon.AnchorPoint = Vector2.new(0, 0.5)
		tabIcon.Position = UDim2.new(0, 12, 0.5, 0)
		tabIcon.Size = tCfg.IconSize
		tabIcon.Size = UDim2.fromOffset(34, 34)
		tabIcon.BackgroundTransparency = 1
		tabIcon.Image = tCfg.IconAsset
		tabIcon.ScaleType = Enum.ScaleType.Fit
		tabIcon.ZIndex = 35
		tabIcon.Parent = tabBtn

		-- Text Label inside Tab
		local tabLbl = Instance.new("TextLabel")
		tabLbl.Name = "TabLabel"
		tabLbl.AnchorPoint = Vector2.new(0, 0.5)
		tabLbl.Position = UDim2.new(0, 52, 0.5, 0)
		tabLbl.Size = UDim2.new(1, -58, 1, 0)
		tabLbl.BackgroundTransparency = 1
		tabLbl.Font = Enum.Font.GothamBlack
		tabLbl.TextSize = 19
		tabLbl.TextColor3 = COLORS.TabInactiveText
		tabLbl.TextXAlignment = Enum.TextXAlignment.Left
		tabLbl.Text = tCfg.Title
		tabLbl.ZIndex = 35
		tabLbl.Parent = tabBtn

		local tabLblStroke = Instance.new("UIStroke")
		tabLblStroke.Color = Color3.fromRGB(0, 0, 0)
		tabLblStroke.Thickness = 2.2
		tabLblStroke.Parent = tabLbl

		tabComponentsByName[tCfg.Id] = {
			Button = tabBtn,
			Stroke = tabStroke,
			Gradient = tabGradient,
			GlowFrame = tabGlow,
			Icon = tabIcon,
			Label = tabLbl,
		}

		tabBtn.Activated:Connect(function()
			InventoryController.SetActiveCategory(tCfg.Id)
		end)
	end

	-- ------------------------------------------------------------------------
	-- PART 4: CLOSE BUTTON (Red 45-degree Rotated Diamond)
	-- ------------------------------------------------------------------------
	local closeBtn = Instance.new("ImageButton")
	closeBtn.Name = "CloseButton"
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.new(1, -16, 0, 16)
	closeBtn.Size = UDim2.fromOffset(48, 48)
	closeBtn.Rotation = 45 -- Rotated 45 degrees diamond
	closeBtn.BackgroundColor3 = COLORS.CloseRedTop
	closeBtn.BorderSizePixel = 0
	closeBtn.AutoButtonColor = true
	closeBtn.ZIndex = 40
	closeBtn.Parent = panel
	closeButton = closeBtn

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 9)
	closeCorner.Parent = closeBtn

	local closeStroke = Instance.new("UIStroke")
	closeStroke.Color = COLORS.CloseBorder
	closeStroke.Thickness = 2.5
	closeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	closeStroke.Parent = closeBtn

	local closeGradient = Instance.new("UIGradient")
	closeGradient.Rotation = 90
	closeGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, COLORS.CloseRedTop),
		ColorSequenceKeypoint.new(1, COLORS.CloseRedBottom),
	})
	closeGradient.Parent = closeBtn

	-- White "X" TextLabel with counter-rotation (-45 deg) so it stays perfectly upright
	local xLbl = Instance.new("TextLabel")
	xLbl.Name = "XSymbol"
	xLbl.AnchorPoint = Vector2.new(0.5, 0.5)
	xLbl.Position = UDim2.fromScale(0.5, 0.5)
	xLbl.Size = UDim2.fromScale(1, 1)
	xLbl.Rotation = -45
	xLbl.BackgroundTransparency = 1
	xLbl.Font = Enum.Font.GothamBlack
	xLbl.TextSize = 25
	xLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	xLbl.Text = "X"
	xLbl.ZIndex = 41
	xLbl.Parent = closeBtn

	local xStroke = Instance.new("UIStroke")
	xStroke.Color = Color3.fromRGB(60, 10, 10)
	xStroke.Thickness = 2.2
	xStroke.Parent = xLbl

	closeBtn.Activated:Connect(function()
		InventoryController.CloseInventory()
	end)

	-- ------------------------------------------------------------------------
	-- PART 5: CONTENT AREA & 4 DEDICATED CATEGORY CONTAINERS
	-- ------------------------------------------------------------------------
	local contentArea = Instance.new("Frame")
	contentArea.Name = "ContentArea"
	contentArea.Position = UDim2.fromOffset(16, 76)
	contentArea.Size = UDim2.new(1, -32, 1, -92)
	contentArea.BackgroundColor3 = COLORS.ContentBg
	contentArea.BackgroundTransparency = 0.25
	contentArea.BorderSizePixel = 0
	contentArea.ZIndex = 32
	contentArea.Parent = panel

	local contentCorner = Instance.new("UICorner")
	contentCorner.CornerRadius = UDim.new(0, 12)
	contentCorner.Parent = contentArea

	local contentStroke = Instance.new("UIStroke")
	contentStroke.Color = COLORS.ContentBorder
	contentStroke.Thickness = 2.0
	contentStroke.Parent = contentArea

	-- Build 4 dedicated ScrollingFrames (ItemsContent, ShovelContent, EggsContent, PetContent)
	local categories = { "Items", "Shovel", "Eggs", "Pet" }
	for _, catName in ipairs(categories) do
		local scroll = Instance.new("ScrollingFrame")
		scroll.Name = catName .. "Content"
		scroll.Size = UDim2.fromScale(1, 1)
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.ScrollBarThickness = 6
		scroll.ScrollBarImageColor3 = COLORS.ScrollbarTrack
		scroll.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
		scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		scroll.Visible = (catName == activeCategory)
		scroll.ZIndex = 33
		scroll.Parent = contentArea

		local sPad = Instance.new("UIPadding")
		sPad.PaddingTop = UDim.new(0, 12)
		sPad.PaddingBottom = UDim.new(0, 12)
		sPad.PaddingLeft = UDim.new(0, 14)
		sPad.PaddingRight = UDim.new(0, 14)
		sPad.Parent = scroll

		categoryContainersByName[catName] = scroll
	end

	-- Initialize responsive scale & layout
	updateResponsiveLayout()
	InventoryController.UpdateHotbarAppearance()
	InventoryController.UpdateInventoryContent()
end

-- ============================================================================
-- 8. INPUT BINDINGS (KEYBOARD, MOUSE, TOUCH, GAMEPAD)
-- ============================================================================
local function bindInputEvents()
	local function isTextInputActive(): boolean
		return UserInputService:GetFocusedTextBox() ~= nil
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if isTextInputActive() then
			return
		end

		local key = input.KeyCode

		-- Escape / Gamepad Button B closes inventory if open
		if key == Enum.KeyCode.Escape or key == Enum.KeyCode.ButtonB then
			if isInventoryOpen then
				InventoryController.CloseInventory()
				return
			end
		end

		if gameProcessed then
			return
		end

		-- Keyboard Key 1: Diamond Shovel
		if key == Enum.KeyCode.One or key == Enum.KeyCode.KeypadOne then
			InventoryController.SelectHotbarSlot(1)
		-- Keyboard Key 2: Shovel (Opens Shovel tab)
		elseif key == Enum.KeyCode.Two or key == Enum.KeyCode.KeypadTwo then
			InventoryController.SelectHotbarSlot(2)
		-- Keyboard Key 3: Items (Opens Items tab)
		elseif key == Enum.KeyCode.Three or key == Enum.KeyCode.KeypadThree then
			InventoryController.SelectHotbarSlot(3)
		-- Keyboard Key B: Toggle Inventory on Items tab
		elseif key == Enum.KeyCode.B then
			InventoryController.TogglePanel()
		end
	end)
end

-- ============================================================================
-- 9. INITIALIZATION & LIFECYCLE
-- ============================================================================
function InventoryController.Start()
	if started then
		return
	end
	started = true

	-- Disable default Roblox backpack to prevent conflict with custom 3-slot hotbar
	task.defer(function()
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
	end)

	buildDigPalsUI()
	-- InputController owns keyboard bindings; avoid duplicate B toggles.
	require(script.Parent:WaitForChild("AdventureInventoryUI")).Mount(InventoryController, screenGui, SHOVEL_CONFIGS)

	-- Attribute change listener for dynamic shovel synchronization
	local function onShovelAttrChanged()
		local eq = LocalPlayer:GetAttribute("EquippedShovel")
		if typeof(eq) == "string" and eq ~= "" then
			InventoryController.SyncEquippedShovel(eq)
		end
	end
	LocalPlayer:GetAttributeChangedSignal("EquippedShovel"):Connect(onShovelAttrChanged)
	onShovelAttrChanged()

	-- StateSync listener to keep hotbar in sync with server state
	pcall(function()
		local Shared = ReplicatedStorage:FindFirstChild("Shared")
		local RemotesUtil = Shared and Shared:FindFirstChild("Util") and Shared.Util:FindFirstChild("Remotes")
		if RemotesUtil then
			local Remotes = require(RemotesUtil) :: any
			local syncEv = Remotes.GetEvent("StateSync")
			if syncEv then
				syncEv.OnClientEvent:Connect(function(snapshot: any)
					if snapshot and type(snapshot.EquippedShovel) == "string" then
						InventoryController.SyncEquippedShovel(snapshot.EquippedShovel)
					end
				end)
			end
		end
	end)

	-- Viewport size change listener for responsive scaling
	local function hookCamera()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveLayout)
			updateResponsiveLayout()
		end
	end
	hookCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera)

	-- Respawn preservation
	LocalPlayer.CharacterAdded:Connect(function()
		task.wait(0.2)
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		-- Re-equip active tool if slot 1 was selected
		if selectedSlot == 1 then
			equipToolForSlot(1)
		end
	end)
end

return InventoryController
