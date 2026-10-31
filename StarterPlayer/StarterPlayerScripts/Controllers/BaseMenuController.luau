--!strict
-- Left-edge Base management menu: base pets, passive income, and persistent upgrades.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseConfig = require(Shared:WaitForChild("Config"):WaitForChild("Base"))
local PetsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Pets"))
local RarityConfig = require(Shared:WaitForChild("Config"):WaitForChild("Rarity"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))

local LocalPlayer = Players.LocalPlayer
local BaseMenuController = {}

local COLORS = {
	Panel = Color3.fromRGB(250, 229, 181),
	PanelDeep = Color3.fromRGB(242, 220, 170),
	Card = Color3.fromRGB(248, 231, 191),
	CardAlt = Color3.fromRGB(244, 225, 182),
	Gold = Color3.fromRGB(255, 184, 67),
	GoldBright = Color3.fromRGB(120, 91, 40),
	Blue = Color3.fromRGB(70, 102, 116),
	Green = Color3.fromRGB(17, 137, 103),
	Red = Color3.fromRGB(218, 75, 82),
	Muted = Color3.fromRGB(151, 136, 99),
	Text = Color3.fromRGB(38, 41, 42),
	Subtext = Color3.fromRGB(105, 98, 80),
	Outline = Color3.fromRGB(38, 43, 43),
}

local started = false
local isOpen = false
local isBusy = false
local activeTab = "Pets"
local latestState: any = nil
local ownedPets: { [string]: Types.PetInstance } = {}
local equippedPets: { string } = {}
local basePets: { string } = {}
local baseLevel = 1
local coins = 0

local screenGui: ScreenGui? = nil
local edgeButton: TextButton? = nil
local edgeLevel: TextLabel? = nil
local backdrop: TextButton? = nil
local panel: Frame? = nil
local panelScale: UIScale? = nil
local content: Frame? = nil
local petsTab: TextButton? = nil
local upgradeTab: TextButton? = nil
local statusLabel: TextLabel? = nil

local function corner(parent: Instance, radius: number)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, radius)
	value.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?)
	local value = Instance.new("UIStroke")
	value.Color = color
	value.Thickness = thickness
	value.Transparency = transparency or 0
	value.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	value.Parent = parent
end

local function label(parent: Instance, text: string, size: number, color: Color3, bold: boolean?): TextLabel
	local value = Instance.new("TextLabel")
	value.BackgroundTransparency = 1
	value.Font = if bold then Enum.Font.GothamBlack else Enum.Font.GothamMedium
	value.Text = text
	value.TextSize = size
	value.TextColor3 = color
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.Parent = parent
	return value
end

local function makeButton(parent: Instance, text: string, color: Color3): TextButton
	local value = Instance.new("TextButton")
	value.AutoButtonColor = false
	value.BackgroundColor3 = color
	value.BorderSizePixel = 0
	value.Font = Enum.Font.GothamBlack
	value.Text = text
	value.TextColor3 = COLORS.Text
	value.TextSize = 14
	value.Parent = parent
	corner(value, 10)
	stroke(value, color:Lerp(Color3.new(1, 1, 1), 0.28), 2, 0.2)
	return value
end

local function contains(list: { string }, guid: string): boolean
	return table.find(list, guid) ~= nil
end

local function maxPetSlots(level: number): number
	local cfg = BaseConfig.Levels[math.clamp(level, 1, BaseConfig.MaxBaseLevel)]
	return if cfg then cfg.PetSlots else 2
end

local function petIncome(pet: Types.PetInstance): number
	local species = PetsConfig.Species[pet.Species]
	if not species then return 0 end
	local variant = (PetsConfig.Variants :: any)[pet.Variant] or PetsConfig.Variants.Normal
	local levelBonus = 1 + PetsConfig.LevelIncomeBonusPerLevel * (math.clamp(pet.Level or 1, 1, PetsConfig.MaxPetLevel) - 1)
	return math.floor(species.BaseIncome * levelBonus * variant.IncomeMultiplier)
end

local function setStatus(message: string?, isError: boolean?)
	if not statusLabel then return end
	statusLabel.Text = message or ""
	statusLabel.TextColor3 = if isError then Color3.fromRGB(255, 120, 120) else Color3.fromRGB(120, 240, 166)
	statusLabel.Visible = message ~= nil and message ~= ""
end

local function clearContent()
	if not content then return end
	for _, child in content:GetChildren() do
		if not child:IsA("UICorner") and not child:IsA("UIStroke") then child:Destroy() end
	end
end

local function refreshEdgeButton()
	-- The compact edge button intentionally contains only its name.
end

local function renderPets()
	clearContent()
	if not content then return end
	local slots = maxPetSlots(baseLevel)
	local summary = Instance.new("Frame")
	summary.Position = UDim2.fromOffset(10, 10)
	summary.Size = UDim2.new(1, -20, 0, 62)
	summary.BackgroundColor3 = COLORS.CardAlt
	summary.BorderSizePixel = 0
	summary.Parent = content
	corner(summary, 12)
	stroke(summary, COLORS.Blue, 2, 0.35)
	local title = label(summary, string.format("PET DI BASE  %d/%d", #basePets, slots), 17, COLORS.Text, true)
	title.Position = UDim2.fromOffset(16, 8)
	title.Size = UDim2.new(0.55, 0, 0, 23)
	local income = tonumber(LocalPlayer:GetAttribute("IncomePerSecond")) or 0
	local incomeLabel = label(summary, string.format("Passive income:  $%s / detik", Format.Commas(income)), 13, COLORS.GoldBright, true)
	incomeLabel.Position = UDim2.fromOffset(16, 34)
	incomeLabel.Size = UDim2.new(0.7, 0, 0, 20)
	local hint = label(summary, "Taruh pet untuk menghasilkan koin otomatis.", 12, COLORS.Subtext, false)
	hint.AnchorPoint = Vector2.new(1, 0.5)
	hint.Position = UDim2.new(1, -14, 0.5, 0)
	hint.Size = UDim2.new(0.42, 0, 0, 38)
	hint.TextWrapped = true
	hint.TextXAlignment = Enum.TextXAlignment.Right

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "PetList"
	scroll.Position = UDim2.fromOffset(10, 82)
	scroll.Size = UDim2.new(1, -20, 1, -92)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = COLORS.Gold
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = content
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = scroll

	local guids = {}
	for guid in ownedPets do table.insert(guids, guid) end
	table.sort(guids, function(a, b)
		local aBase, bBase = contains(basePets, a), contains(basePets, b)
		if aBase ~= bBase then return aBase end
		local aPet, bPet = ownedPets[a], ownedPets[b]
		return (aPet and aPet.Species or a) < (bPet and bPet.Species or b)
	end)
	if #guids == 0 then
		local empty = label(scroll, "Belum ada pet. Tetaskan telur untuk mendapatkan pet.", 15, COLORS.Subtext, true)
		empty.Size = UDim2.new(1, -10, 0, 80)
		empty.TextXAlignment = Enum.TextXAlignment.Center
		return
	end

	for order, guid in guids do
		local pet = ownedPets[guid]
		local species = pet and PetsConfig.Species[pet.Species]
		if pet and species then
			local inBase = contains(basePets, guid)
			local equipped = contains(equippedPets, guid)
			local row = Instance.new("Frame")
			row.Name = "Pet_" .. guid
			row.LayoutOrder = order
			row.Size = UDim2.new(1, -8, 0, 78)
			row.BackgroundColor3 = if inBase then Color3.fromRGB(32, 62, 55) else COLORS.Card
			row.BorderSizePixel = 0
			row.Parent = scroll
			corner(row, 12)
			local rarity = (RarityConfig.ById :: any)[species.Rarity]
			stroke(row, if rarity then rarity.Color else COLORS.Muted, 2, 0.35)
			local icon = label(row, string.upper(string.sub(species.DisplayName, 1, 2)), 18, COLORS.GoldBright, true)
			icon.Position = UDim2.fromOffset(12, 13)
			icon.Size = UDim2.fromOffset(48, 48)
			icon.TextXAlignment = Enum.TextXAlignment.Center
			icon.BackgroundTransparency = 0
			icon.BackgroundColor3 = COLORS.PanelDeep
			corner(icon, 10)
			local name = label(row, species.DisplayName, 16, COLORS.Text, true)
			name.Position = UDim2.fromOffset(72, 10)
			name.Size = UDim2.new(1, -250, 0, 24)
			local detail = label(row, string.format("%s  •  Lv.%d  •  +$%s/detik", pet.Variant, pet.Level or 1, Format.Commas(petIncome(pet))), 12, COLORS.Subtext, false)
			detail.Position = UDim2.fromOffset(72, 37)
			detail.Size = UDim2.new(1, -250, 0, 20)
			local stateText = if inBase then "PASSIVE" elseif equipped then "MENGIKUTI" else "TERSEDIA"
			local state = label(row, stateText, 10, if inBase then Color3.fromRGB(115, 245, 165) else COLORS.GoldBright, true)
			state.Position = UDim2.fromOffset(72, 57)
			state.Size = UDim2.new(1, -250, 0, 14)
			local actionText = if inBase then "TARIK" elseif equipped then "SEDANG IKUT" elseif #basePets >= slots then "BASE PENUH" else "TARUH"
			local enabled = not isBusy and (inBase or (not equipped and #basePets < slots))
			local action = makeButton(row, actionText, if enabled then (if inBase then COLORS.Red else COLORS.Green) else COLORS.Muted)
			action.AnchorPoint = Vector2.new(1, 0.5)
			action.Position = UDim2.new(1, -12, 0.5, 0)
			action.Size = UDim2.fromOffset(140, 42)
			action.Active = enabled
			action.TextTransparency = if enabled then 0 else 0.25
			if enabled then
				action.Activated:Connect(function()
					if isBusy then return end
					isBusy = true
					setStatus("Memproses pet...", false)
					renderPets()
					task.spawn(function()
						local ok, response = pcall(function()
							return Remotes.GetFunction(if inBase then "RemovePetFromBase" else "AssignPetToBase"):InvokeServer(guid)
						end)
						isBusy = false
						if ok and type(response) == "table" and response.Success == true then
							setStatus(if inBase then "Pet berhasil ditarik dari Base." else "Pet menghasilkan passive income di Base.", false)
						else
							setStatus(if ok and type(response) == "table" then tostring(response.Message or response.Reason or "Gagal mengatur pet.") else "Server tidak merespons.", true)
						end
						renderPets()
					end)
				end)
			end
		end
	end
end

local function statLine(parent: Instance, y: number, name: string, currentValue: string, nextValue: string?)
	local line = label(parent, name, 13, COLORS.Subtext, true)
	line.Position = UDim2.fromOffset(18, y)
	line.Size = UDim2.new(0.48, 0, 0, 22)
	local value = label(parent, if nextValue then currentValue .. "  →  " .. nextValue else currentValue, 14, if nextValue then COLORS.GoldBright else COLORS.Text, true)
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.new(1, -18, 0, y)
	value.Size = UDim2.new(0.5, 0, 0, 22)
	value.TextXAlignment = Enum.TextXAlignment.Right
end

local function renderUpgrade()
	clearContent()
	if not content then return end
	local current = BaseConfig.Levels[baseLevel]
	local nextCfg = BaseConfig.Levels[baseLevel + 1]
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 14)
	card.Size = UDim2.new(0.86, 0, 0, 280)
	card.BackgroundColor3 = COLORS.Card
	card.BorderSizePixel = 0
	card.Parent = content
	corner(card, 16)
	stroke(card, COLORS.Gold, 3, 0.15)
	local heading = label(card, string.format("BASE LEVEL %d", baseLevel), 25, COLORS.GoldBright, true)
	heading.Position = UDim2.fromOffset(18, 16)
	heading.Size = UDim2.new(1, -36, 0, 34)
	heading.TextXAlignment = Enum.TextXAlignment.Center
	local wallet = label(card, string.format("Saldo: $%s", Format.Commas(coins)), 14, COLORS.Text, true)
	wallet.Position = UDim2.fromOffset(18, 54)
	wallet.Size = UDim2.new(1, -36, 0, 24)
	wallet.TextXAlignment = Enum.TextXAlignment.Center
	if current then
		statLine(card, 92, "Slot Pet", tostring(current.PetSlots), nextCfg and tostring(nextCfg.PetSlots))
		statLine(card, 124, "Slot Inkubator", tostring(current.IncubatorSlots), nextCfg and tostring(nextCfg.IncubatorSlots))
		statLine(card, 156, "Kapasitas Egg Bag", tostring(BaseConfig.BaseEggBagCapacity + baseLevel), nextCfg and tostring(BaseConfig.BaseEggBagCapacity + baseLevel + 1))
		statLine(card, 188, "Ukuran Area", string.format("%dx%d", current.PlotScale.X, current.PlotScale.Z), nextCfg and string.format("%dx%d", nextCfg.PlotScale.X, nextCfg.PlotScale.Z))
	end
	local buttonText = if nextCfg then string.format("UPGRADE KE LV.%d  •  $%s", baseLevel + 1, Format.Commas(nextCfg.UpgradeCost)) else "LEVEL MAKSIMAL"
	local canUpgrade = nextCfg ~= nil and not isBusy
	local upgrade = makeButton(card, buttonText, if canUpgrade then COLORS.Green else COLORS.Muted)
	upgrade.Position = UDim2.fromOffset(18, 226)
	upgrade.Size = UDim2.new(1, -36, 0, 42)
	upgrade.Active = canUpgrade
	if canUpgrade then
		upgrade.Activated:Connect(function()
			if isBusy then return end
			isBusy = true
			setStatus("Memproses upgrade Base...", false)
			renderUpgrade()
			task.spawn(function()
				local ok, response = pcall(function()
					return Remotes.GetFunction("UpgradeBase"):InvokeServer()
				end)
				isBusy = false
				if ok and type(response) == "table" and response.Success == true then
					baseLevel = tonumber(response.NewBaseLevel) or baseLevel
					coins = tonumber(response.Coins) or coins
					setStatus(string.format("Base berhasil naik ke Level %d!", baseLevel), false)
					pcall(function() require(script.Parent:WaitForChild("AudioController")).PlayBaseUpgrade() end)
				else
					setStatus(if ok and type(response) == "table" then tostring(response.Message or response.Reason or "Upgrade gagal.") else "Server tidak merespons.", true)
				end
				refreshEdgeButton()
				renderUpgrade()
			end)
		end)
	end
end

local function render()
	refreshEdgeButton()
	if petsTab and upgradeTab then
		petsTab.BackgroundColor3 = if activeTab == "Pets" then COLORS.Green else COLORS.Blue
		upgradeTab.BackgroundColor3 = if activeTab == "Upgrade" then COLORS.Green else COLORS.Blue
		petsTab.TextColor3 = Color3.fromRGB(255, 248, 225)
		upgradeTab.TextColor3 = Color3.fromRGB(255, 248, 225)
	end
	if activeTab == "Pets" then renderPets() else renderUpgrade() end
end

local function applySnapshot(snapshot: any)
	if type(snapshot) ~= "table" then return end
	latestState = snapshot
	if type(snapshot.Pets) == "table" then ownedPets = snapshot.Pets end
	if type(snapshot.EquippedPets) == "table" then equippedPets = snapshot.EquippedPets end
	if type(snapshot.BasePets) == "table" then basePets = snapshot.BasePets end
	if type(snapshot.BaseLevel) == "number" then baseLevel = math.clamp(math.floor(snapshot.BaseLevel), 1, BaseConfig.MaxBaseLevel) end
	if type(snapshot.Coins) == "number" then coins = math.max(0, math.floor(snapshot.Coins)) end
	refreshEdgeButton()
	if isOpen then render() end
end

local function updateScale()
	if not panelScale or not workspace.CurrentCamera then return end
	local vp = workspace.CurrentCamera.ViewportSize
	panelScale.Scale = math.clamp(math.min(vp.X / 900, vp.Y / 620), 0.62, 1)
end

local function closeOtherMenus()
	local controllers = script.Parent
	for _, entry in {
		{ "InventoryController", "CloseInventory" },
		{ "IndexController", "Close" },
		{ "QuestStreakController", "Close" },
		{ "LeaderboardController", "Close" },
		{ "MerchantController", "ClosePanel" },
		{ "ShovelShopController", "ClosePanel" },
		{ "OfflineIncomeController", "Close" },
	} do
		pcall(function()
			local controller = require(controllers:WaitForChild(entry[1]))
			local closeMethod = controller[entry[2]]
			if type(closeMethod) == "function" then closeMethod() end
		end)
	end
end

local function buildUI()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild("BaseMenuGui")
	if old then old:Destroy() end
	local gui = Instance.new("ScreenGui")
	gui.Name = "BaseMenuGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 24
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	screenGui = gui

	local edge = makeButton(gui, "Base", COLORS.Gold)
	edge.Name = "BaseEdgeButton"
	edge.AnchorPoint = Vector2.new(0, 0.5)
	edge.Position = UDim2.new(0, 10, 0.5, -8)
	edge.Size = UDim2.fromOffset(82, 36)
	edge.TextColor3 = COLORS.Outline
	edge.TextSize = 15
	edge.Text = "Base"
	edgeButton = edge
	edge.Activated:Connect(function() BaseMenuController.Toggle() end)

	local shade = Instance.new("TextButton")
	shade.Name = "Backdrop"
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.fromRGB(4, 7, 12)
	shade.BackgroundTransparency = 0.3
	shade.BorderSizePixel = 0
	shade.Text = ""
	shade.Visible = false
	shade.ZIndex = 10
	shade.Parent = gui
	backdrop = shade
	shade.Activated:Connect(function() BaseMenuController.Close() end)

	local card = Instance.new("Frame")
	card.Name = "BasePanel"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(700, 430)
	card.BackgroundColor3 = COLORS.Panel
	card.BorderSizePixel = 0
	card.Visible = false
	card.ZIndex = 11
	card.Parent = gui
	panel = card
	corner(card, 18)
	stroke(card, COLORS.Outline, 2, 0)
	local scale = Instance.new("UIScale")
	scale.Parent = card
	panelScale = scale
	updateScale()
	if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale) end

	local close = makeButton(card, "X", COLORS.Red)
	close.Position = UDim2.new(1, -52, 0, 10)
	close.Size = UDim2.fromOffset(40, 40)
	stroke(close, COLORS.Outline, 2, 0)
	close.Activated:Connect(function() BaseMenuController.Close() end)

	local tabs = Instance.new("Frame")
	tabs.Position = UDim2.fromOffset(12, 10)
	tabs.Size = UDim2.new(1, -70, 0, 40)
	tabs.BackgroundTransparency = 1
	tabs.Parent = card
	local petButton = makeButton(tabs, "PET DI BASE", COLORS.Blue)
	petButton.Size = UDim2.fromOffset(170, 40)
	petsTab = petButton
	local upgradeButton = makeButton(tabs, "UPGRADE BASE", COLORS.PanelDeep)
	upgradeButton.Position = UDim2.fromOffset(178, 0)
	upgradeButton.Size = UDim2.fromOffset(170, 40)
	upgradeTab = upgradeButton
	petButton.Activated:Connect(function() activeTab = "Pets"; setStatus(nil); render() end)
	upgradeButton.Activated:Connect(function() activeTab = "Upgrade"; setStatus(nil); render() end)

	local body = Instance.new("Frame")
	body.Name = "Content"
	body.Position = UDim2.fromOffset(12, 60)
	body.Size = UDim2.new(1, -24, 1, -94)
	body.BackgroundColor3 = COLORS.Card
	body.BackgroundTransparency = 0
	body.Parent = card
	content = body
	corner(body, 12)
	stroke(body, COLORS.Outline, 2, 0)
	local status = label(card, "", 12, COLORS.Green, true)
	status.Position = UDim2.new(0, 18, 1, -30)
	status.Size = UDim2.new(1, -36, 0, 20)
	status.TextXAlignment = Enum.TextXAlignment.Center
	status.Visible = false
	statusLabel = status
	refreshEdgeButton()
end

function BaseMenuController.IsOpen(): boolean return isOpen end

function BaseMenuController.Open()
	if not panel then buildUI() end
	closeOtherMenus()
	isOpen = true
	setStatus(nil)
	if backdrop then backdrop.Visible = true end
	if panel then
		panel.Visible = true
		panel.Position = UDim2.fromScale(0.5, 0.53)
		TweenService:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.5) }):Play()
	end
	render()
end

function BaseMenuController.Close()
	isOpen = false
	if backdrop then backdrop.Visible = false end
	if panel then panel.Visible = false end
end

function BaseMenuController.Toggle()
	if isOpen then BaseMenuController.Close() else BaseMenuController.Open() end
end

function BaseMenuController.Start()
	if started then return end
	started = true
	buildUI()
	Remotes.GetEvent("StateSync").OnClientEvent:Connect(applySnapshot)
	LocalPlayer:GetAttributeChangedSignal("IncomePerSecond"):Connect(function()
		if isOpen and activeTab == "Pets" then renderPets() end
	end)
	LocalPlayer:GetAttributeChangedSignal("Coins"):Connect(function()
		coins = tonumber(LocalPlayer:GetAttribute("Coins")) or coins
		if isOpen and activeTab == "Upgrade" then renderUpgrade() end
	end)
	task.spawn(function()
		local ok, snapshot = pcall(function() return Remotes.GetFunction("GetInventoryState"):InvokeServer() end)
		if ok then applySnapshot(snapshot) end
	end)
end

return BaseMenuController
