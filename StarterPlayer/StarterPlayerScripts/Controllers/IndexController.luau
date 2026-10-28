--!strict
-- Client controller for Pet & Item Index modal, discovery silhouettes, and completion milestone celebrations (Step 12)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local RarityConfig = require(Shared:WaitForChild("Config"):WaitForChild("Rarity"))
local ItemsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Items"))
local PetsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Pets"))

local LocalPlayer = Players.LocalPlayer

local IndexController = {}

local screenGui: ScreenGui? = nil
local modalFrame: Frame? = nil
local contentScroll: ScrollingFrame? = nil
local itemsTabBtn: TextButton? = nil
local petsTabBtn: TextButton? = nil
local activeTab: string = "Items"
local isOpen: boolean = false
local started: boolean = false

local alertModal: Frame? = nil

local latestIndexData: any = nil

local itemsByRarity: { [Types.RarityName]: { Types.ItemConfig } } = {
	Common = {},
	Uncommon = {},
	Rare = {},
	Epic = {},
	Legendary = {},
}

local petsByRarity: { [Types.RarityName]: { Types.PetSpeciesConfig } } = {
	Common = {},
	Uncommon = {},
	Rare = {},
	Epic = {},
	Legendary = {},
}

for _, itemCfg in pairs(ItemsConfig.All) do
	local bucket = itemsByRarity[itemCfg.Rarity]
	if bucket then
		table.insert(bucket, itemCfg)
	end
end

for _, speciesCfg in pairs(PetsConfig.Species) do
	local bucket = petsByRarity[speciesCfg.Rarity]
	if bucket then
		table.insert(bucket, speciesCfg)
	end
end

for _, b in pairs(itemsByRarity) do
	table.sort(b, function(x, y) return x.Id < y.Id end)
end
for _, b in pairs(petsByRarity) do
	table.sort(b, function(x, y) return x.Id < y.Id end)
end

function IndexController.IsOpen(): boolean
	return isOpen
end

local function showAlertPopup(titleText: string, messageText: string, highlightColor: Color3)
	if not screenGui then
		return
	end

	if alertModal then
		alertModal:Destroy()
		alertModal = nil
	end

	local modal = Instance.new("Frame")
	modal.Name = "IndexAlertModal"
	modal.Size = UDim2.fromScale(1, 1)
	modal.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	modal.BackgroundTransparency = 0.4
	modal.BorderSizePixel = 0
	modal.ZIndex = 60
	modal.Parent = screenGui
	alertModal = modal

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromOffset(420, 240)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
	card.BorderSizePixel = 0
	card.Parent = modal

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = highlightColor
	stroke.Thickness = 2.5
	stroke.Parent = card

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -24, 0, 36)
	title.Position = UDim2.fromOffset(12, 16)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 18
	title.TextColor3 = highlightColor
	title.Text = titleText
	title.Parent = card

	local msg = Instance.new("TextLabel")
	msg.Name = "Message"
	msg.Size = UDim2.new(1, -32, 0, 70)
	msg.Position = UDim2.fromOffset(16, 58)
	msg.BackgroundTransparency = 1
	msg.Font = Enum.Font.GothamMedium
	msg.TextSize = 14
	msg.TextColor3 = Color3.fromRGB(240, 240, 250)
	msg.TextWrapped = true
	msg.Text = messageText
	msg.Parent = card

	local okBtn = Instance.new("TextButton")
	okBtn.Name = "OkButton"
	okBtn.Size = UDim2.new(1, -32, 0, 42)
	okBtn.Position = UDim2.new(0, 16, 1, -56)
	okBtn.BackgroundColor3 = Color3.fromRGB(50, 180, 95)
	okBtn.BorderSizePixel = 0
	okBtn.Font = Enum.Font.GothamBlack
	okBtn.TextSize = 15
	okBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	okBtn.Text = "LANJUT"
	okBtn.Parent = card

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 8)
	btnCorner.Parent = okBtn

	okBtn.MouseButton1Click:Connect(function()
		if alertModal then
			alertModal:Destroy()
			alertModal = nil
		end
	end)
end

local function renderContent()
	if not contentScroll then
		return
	end
	contentScroll:ClearAllChildren()

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 14)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = contentScroll

	local profileData = latestIndexData
	local discoveredItems = if profileData and profileData.Index and profileData.Index.Items then profileData.Index.Items else {}
	local discoveredPets = if profileData and profileData.Index and profileData.Index.Pets then profileData.Index.Pets else {}

	if activeTab == "Items" then
		for orderIdx, rarity in ipairs(RarityConfig.Order) do
			local pool = itemsByRarity[rarity]
			local discCount = 0
			for _, it in ipairs(pool) do
				if discoveredItems[it.Id] then
					discCount += 1
				end
			end
			local isComplete = (discCount == #pool)

			local section = Instance.new("Frame")
			section.Name = "Section_" .. rarity
			section.Size = UDim2.new(1, -8, 0, 140)
			section.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
			section.BorderSizePixel = 0
			section.LayoutOrder = orderIdx
			section.Parent = contentScroll

			local sCorner = Instance.new("UICorner")
			sCorner.CornerRadius = UDim.new(0, 10)
			sCorner.Parent = section

			local sStroke = Instance.new("UIStroke")
			sStroke.Color = if isComplete then Color3.fromRGB(255, 215, 65) else Color3.fromRGB(55, 55, 68)
			sStroke.Thickness = if isComplete then 1.5 else 1
			sStroke.Parent = section

			local sHeader = Instance.new("TextLabel")
			sHeader.Size = UDim2.new(1, -20, 0, 26)
			sHeader.Position = UDim2.fromOffset(10, 6)
			sHeader.BackgroundTransparency = 1
			sHeader.Font = Enum.Font.GothamBold
			sHeader.TextSize = 13
			sHeader.TextColor3 = RarityConfig.ById[rarity].Color
			sHeader.TextXAlignment = Enum.TextXAlignment.Left
			sHeader.Text = string.format("%s Items (%d/%d)%s", rarity, discCount, #pool, if isComplete then " - [SELESAI +0.03 Luck]" else "")
			sHeader.Parent = section

			local grid = Instance.new("Frame")
			grid.Size = UDim2.new(1, -20, 0, 92)
			grid.Position = UDim2.fromOffset(10, 36)
			grid.BackgroundTransparency = 1
			grid.Parent = section

			local gLayout = Instance.new("UIGridLayout")
			gLayout.CellSize = UDim2.fromOffset(90, 84)
			gLayout.CellPadding = UDim2.fromOffset(8, 8)
			gLayout.SortOrder = Enum.SortOrder.LayoutOrder
			gLayout.Parent = grid

			for _, it in ipairs(pool) do
				local isFound = discoveredItems[it.Id] == true
				local card = Instance.new("Frame")
				card.BackgroundColor3 = if isFound then Color3.fromRGB(42, 42, 54) else Color3.fromRGB(26, 26, 32)
				card.BorderSizePixel = 0
				card.Parent = grid

				local cCorner = Instance.new("UICorner")
				cCorner.CornerRadius = UDim.new(0, 6)
				cCorner.Parent = card

				local cStroke = Instance.new("UIStroke")
				cStroke.Color = if isFound then RarityConfig.ById[rarity].Color else Color3.fromRGB(45, 45, 55)
				cStroke.Thickness = 1
				cStroke.Parent = card

				local lbl = Instance.new("TextLabel")
				lbl.Size = UDim2.new(1, -4, 0, 36)
				lbl.Position = UDim2.fromOffset(2, 6)
				lbl.BackgroundTransparency = 1
				lbl.Font = Enum.Font.GothamBold
				lbl.TextSize = 11
				lbl.TextWrapped = true
				lbl.TextColor3 = if isFound then Color3.fromRGB(240, 240, 245) else Color3.fromRGB(120, 120, 130)
				lbl.Text = if isFound then it.DisplayName else "???"
				lbl.Parent = card

				local valLbl = Instance.new("TextLabel")
				valLbl.Size = UDim2.new(1, -4, 0, 20)
				valLbl.Position = UDim2.fromOffset(2, 56)
				valLbl.BackgroundTransparency = 1
				valLbl.Font = Enum.Font.GothamMedium
				valLbl.TextSize = 10
				valLbl.TextColor3 = if isFound then Color3.fromRGB(255, 215, 90) else Color3.fromRGB(90, 90, 100)
				valLbl.Text = if isFound then string.format("%d Coins", it.SellPrice) else "Terkunci"
				valLbl.Parent = card
			end
		end
	else
		for orderIdx, rarity in ipairs(RarityConfig.Order) do
			local pool = petsByRarity[rarity]
			local discCount = 0
			for _, pt in ipairs(pool) do
				if discoveredPets[pt.Id] then
					discCount += 1
				end
			end
			local isComplete = (discCount == #pool)

			local section = Instance.new("Frame")
			section.Name = "Section_" .. rarity
			section.Size = UDim2.new(1, -8, 0, 140)
			section.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
			section.BorderSizePixel = 0
			section.LayoutOrder = orderIdx
			section.Parent = contentScroll

			local sCorner = Instance.new("UICorner")
			sCorner.CornerRadius = UDim.new(0, 10)
			sCorner.Parent = section

			local sStroke = Instance.new("UIStroke")
			sStroke.Color = if isComplete then Color3.fromRGB(255, 215, 65) else Color3.fromRGB(55, 55, 68)
			sStroke.Thickness = if isComplete then 1.5 else 1
			sStroke.Parent = section

			local sHeader = Instance.new("TextLabel")
			sHeader.Size = UDim2.new(1, -20, 0, 26)
			sHeader.Position = UDim2.fromOffset(10, 6)
			sHeader.BackgroundTransparency = 1
			sHeader.Font = Enum.Font.GothamBold
			sHeader.TextSize = 13
			sHeader.TextColor3 = RarityConfig.ById[rarity].Color
			sHeader.TextXAlignment = Enum.TextXAlignment.Left
			sHeader.Text = string.format("%s Pets (%d/%d)%s", rarity, discCount, #pool, if isComplete then " - [SELESAI +3% Income]" else "")
			sHeader.Parent = section

			local grid = Instance.new("Frame")
			grid.Size = UDim2.new(1, -20, 0, 92)
			grid.Position = UDim2.fromOffset(10, 36)
			grid.BackgroundTransparency = 1
			grid.Parent = section

			local gLayout = Instance.new("UIGridLayout")
			gLayout.CellSize = UDim2.fromOffset(90, 84)
			gLayout.CellPadding = UDim2.fromOffset(8, 8)
			gLayout.SortOrder = Enum.SortOrder.LayoutOrder
			gLayout.Parent = grid

			for _, pt in ipairs(pool) do
				local isFound = discoveredPets[pt.Id] == true
				local card = Instance.new("Frame")
				card.BackgroundColor3 = if isFound then Color3.fromRGB(42, 42, 54) else Color3.fromRGB(26, 26, 32)
				card.BorderSizePixel = 0
				card.Parent = grid

				local cCorner = Instance.new("UICorner")
				cCorner.CornerRadius = UDim.new(0, 6)
				cCorner.Parent = card

				local cStroke = Instance.new("UIStroke")
				cStroke.Color = if isFound then RarityConfig.ById[rarity].Color else Color3.fromRGB(45, 45, 55)
				cStroke.Thickness = 1
				cStroke.Parent = card

				local lbl = Instance.new("TextLabel")
				lbl.Size = UDim2.new(1, -4, 0, 36)
				lbl.Position = UDim2.fromOffset(2, 6)
				lbl.BackgroundTransparency = 1
				lbl.Font = Enum.Font.GothamBold
				lbl.TextSize = 11
				lbl.TextWrapped = true
				lbl.TextColor3 = if isFound then Color3.fromRGB(240, 240, 245) else Color3.fromRGB(120, 120, 130)
				lbl.Text = if isFound then pt.DisplayName else "???"
				lbl.Parent = card

				local valLbl = Instance.new("TextLabel")
				valLbl.Size = UDim2.new(1, -4, 0, 20)
				valLbl.Position = UDim2.fromOffset(2, 56)
				valLbl.BackgroundTransparency = 1
				valLbl.Font = Enum.Font.GothamMedium
				valLbl.TextSize = 10
				valLbl.TextColor3 = if isFound then Color3.fromRGB(120, 235, 130) else Color3.fromRGB(90, 90, 100)
				valLbl.Text = if isFound then string.format("+%d/dtk", pt.BaseIncome) else "Terkunci"
				valLbl.Parent = card
			end
		end
	end
end

local function buildUI()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("IndexGui")
	if existing and existing:IsA("ScreenGui") then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "IndexGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	screenGui = gui

	local modal = Instance.new("Frame")
	modal.Name = "IndexModal"
	modal.Size = UDim2.fromScale(1, 1)
	modal.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	modal.BackgroundTransparency = 0.5
	modal.BorderSizePixel = 0
	modal.Visible = false
	modal.Parent = gui
	modalFrame = modal

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromOffset(620, 520)
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
		local scaleH = vp.Y / 580
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
	header.Text = "[*] KOLEKSI & INDEX [*]"
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
		IndexController.Close()
	end)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleStatusLabel"
	titleLabel.Size = UDim2.new(1, -40, 0, 24)
	titleLabel.Position = UDim2.fromOffset(20, 50)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 13
	titleLabel.TextColor3 = Color3.fromRGB(255, 230, 110)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Text = "Gelar: Master Excavator (Lengkapi 100% Index untuk Membuka)"
	titleLabel.Parent = card

	local tabContainer = Instance.new("Frame")
	tabContainer.Name = "TabContainer"
	tabContainer.Size = UDim2.new(1, -40, 0, 44)
	tabContainer.Position = UDim2.fromOffset(20, 78)
	tabContainer.BackgroundTransparency = 1
	tabContainer.Parent = card

	local itemBtn = Instance.new("TextButton")
	itemBtn.Name = "ItemTab"
	itemBtn.Size = UDim2.new(0.5, -4, 1, 0)
	itemBtn.Position = UDim2.fromOffset(0, 0)
	itemBtn.BackgroundColor3 = Color3.fromRGB(48, 48, 62)
	itemBtn.BorderSizePixel = 0
	itemBtn.Font = Enum.Font.GothamBlack
	itemBtn.TextSize = 14
	itemBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	itemBtn.Text = "ITEMS (20)"
	itemBtn.Parent = tabContainer
	itemsTabBtn = itemBtn

	local iCorner = Instance.new("UICorner")
	iCorner.CornerRadius = UDim.new(0, 8)
	iCorner.Parent = itemBtn

	local petBtn = Instance.new("TextButton")
	petBtn.Name = "PetTab"
	petBtn.Size = UDim2.new(0.5, -4, 1, 0)
	petBtn.Position = UDim2.new(0.5, 4, 0, 0)
	petBtn.BackgroundColor3 = Color3.fromRGB(32, 32, 42)
	petBtn.BorderSizePixel = 0
	petBtn.Font = Enum.Font.GothamBlack
	petBtn.TextSize = 14
	petBtn.TextColor3 = Color3.fromRGB(180, 180, 190)
	petBtn.Text = "PETS (25)"
	petBtn.Parent = tabContainer
	petsTabBtn = petBtn

	local pCorner = Instance.new("UICorner")
	pCorner.CornerRadius = UDim.new(0, 8)
	pCorner.Parent = petBtn

	itemBtn.MouseButton1Click:Connect(function()
		activeTab = "Items"
		itemBtn.BackgroundColor3 = Color3.fromRGB(48, 48, 62)
		itemBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		petBtn.BackgroundColor3 = Color3.fromRGB(32, 32, 42)
		petBtn.TextColor3 = Color3.fromRGB(180, 180, 190)
		renderContent()
	end)

	petBtn.MouseButton1Click:Connect(function()
		activeTab = "Pets"
		petBtn.BackgroundColor3 = Color3.fromRGB(48, 48, 62)
		petBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		itemBtn.BackgroundColor3 = Color3.fromRGB(32, 32, 42)
		itemBtn.TextColor3 = Color3.fromRGB(180, 180, 190)
		renderContent()
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "ContentScroll"
	scroll.Size = UDim2.new(1, -40, 0, 380)
	scroll.Position = UDim2.fromOffset(20, 124)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new(0, 0, 0, 750)
	scroll.Parent = card
	contentScroll = scroll
end

function IndexController.Open()
	if not modalFrame then
		buildUI()
	end
	isOpen = true
	if modalFrame then
		modalFrame.Visible = true
	end
	renderContent()
end

function IndexController.Close()
	isOpen = false
	if modalFrame then
		modalFrame.Visible = false
	end
end

function IndexController.Toggle()
	if isOpen then
		IndexController.Close()
	else
		IndexController.Open()
	end
end

function IndexController.Start()
	if started then
		return
	end
	started = true

	buildUI()

	local Controllers = script.Parent
	local InventoryController = require(Controllers:WaitForChild("InventoryController"))
	InventoryController.RegisterSideCategory({
		Id = "Index",
		Order = 3,
		IconText = "IDX",
		Label = "INDEX",
		OnActivated = function()
			IndexController.Toggle()
		end,
	})

	ContextActionService:BindAction(
		"ToggleIndexModalKey",
		function(_actionName, inputState, inputObject)
			if inputState == Enum.UserInputState.Begin then
				if inputObject.KeyCode == Enum.KeyCode.Four or inputObject.KeyCode == Enum.KeyCode.KeypadFour then
					IndexController.Toggle()
					return Enum.ContextActionResult.Sink
				elseif inputObject.KeyCode == Enum.KeyCode.Escape and isOpen then
					IndexController.Close()
					return Enum.ContextActionResult.Sink
				end
			end
			return Enum.ContextActionResult.Pass
		end,
		false,
		Enum.KeyCode.Four,
		Enum.KeyCode.KeypadFour,
		Enum.KeyCode.Escape
	)

	Remotes.GetEvent("StateSync").OnClientEvent:Connect(function(snapshot: any)
		if type(snapshot) == "table" then
			latestIndexData = snapshot
			if isOpen then
				renderContent()
			end
		end
	end)

	Remotes.GetEvent("IndexAlert").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.Type == "ItemRarityComplete" then
			showAlertPopup(
				"[*] RARITY ITEM LENGKAP! [*]",
				tostring(payload.Message or "Semua item ditemukan!"),
				Color3.fromRGB(255, 215, 65)
			)
		elseif payload.Type == "PetRarityComplete" then
			showAlertPopup(
				"[*] RARITY PET LENGKAP! [*]",
				tostring(payload.Message or "Semua pet ditemukan!"),
				Color3.fromRGB(90, 225, 120)
			)
		elseif payload.Type == "AllComplete" then
			showAlertPopup(
				"[*] SELURUH INDEX LENGKAP! [*]",
				tostring(payload.Message or "Gelar Master Excavator Dibuka!"),
				Color3.fromRGB(255, 190, 45)
			)
		end
	end)
end

return IndexController
