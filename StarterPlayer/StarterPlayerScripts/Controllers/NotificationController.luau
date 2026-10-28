--!strict
-- Centralized Bounded Notification Queue for Dig Pals (Step 15)
-- Prevents notification stacking with an enforced maximum queue, auto-eviction, smooth animations, and responsive scaling.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RarityConfig = require(Shared:WaitForChild("Config"):WaitForChild("Rarity"))

local LocalPlayer = Players.LocalPlayer

local NotificationController = {}

local MAX_VISIBLE_NOTIFICATIONS = 4
local CARD_LIFETIME_SECONDS = 3.2

type NotificationCard = {
	Frame: Frame,
	IsDismissing: boolean,
	CreatedTime: number,
}

local activeCards: { NotificationCard } = {}
local screenGui: ScreenGui? = nil
local containerFrame: Frame? = nil
local uiScale: UIScale? = nil
local started = false

local function getRarityColor(rarityName: string?): Color3
	local info = (RarityConfig.ById :: any)[rarityName or "Common"]
	if info and info.Color then
		return info.Color
	end
	return Color3.fromRGB(180, 190, 205)
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
	uiScale.Scale = math.clamp(math.min(1, scaleW, scaleH), 0.65, 1.0)
end

local function dismissCard(card: NotificationCard, animate: boolean)
	if card.IsDismissing then
		return
	end
	card.IsDismissing = true

	local idx = table.find(activeCards, card)
	if idx then
		table.remove(activeCards, idx)
	end

	if animate and card.Frame and card.Frame.Parent then
		local stroke = card.Frame:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.2), {
				Transparency = 1,
			}):Play()
		end

		local tween = TweenService:Create(card.Frame, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
			Position = card.Frame.Position - UDim2.fromOffset(0, 20),
			Size = UDim2.fromOffset(card.Frame.Size.X.Offset, 0),
		})
		tween:Play()
		for _, desc in ipairs(card.Frame:GetDescendants()) do
			if desc:IsA("TextLabel") then
				TweenService:Create(desc, TweenInfo.new(0.2), {
					TextTransparency = 1,
					TextStrokeTransparency = 1,
				}):Play()
			elseif desc:IsA("Frame") then
				TweenService:Create(desc, TweenInfo.new(0.2), {
					BackgroundTransparency = 1,
				}):Play()
			end
		end
		tween.Completed:Connect(function()
			card.Frame:Destroy()
		end)
	else
		if card.Frame then
			card.Frame:Destroy()
		end
	end
end

function NotificationController.Notify(title: string, message: string, rarity: string?, iconText: string?)
	if not containerFrame then
		return
	end

	-- Enforce queue limit: if at maximum, immediately dismiss oldest card
	while #activeCards >= MAX_VISIBLE_NOTIFICATIONS do
		dismissCard(activeCards[1], false)
	end

	local rarityColor = getRarityColor(rarity)

	local card = Instance.new("Frame")
	card.Name = "NotifCard"
	card.Size = UDim2.fromOffset(330, 48)
	card.BackgroundColor3 = Color3.fromRGB(22, 26, 36)
	card.BackgroundTransparency = 0.08
	card.BorderSizePixel = 0
	card.ClipsDescendants = true
	card.Parent = containerFrame

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 10)
	cardCorner.Parent = card

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = rarityColor
	cardStroke.Thickness = 1.6
	cardStroke.Parent = card

	-- Left accent bar
	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Position = UDim2.fromOffset(0, 0)
	accent.Size = UDim2.new(0, 6, 1, 0)
	accent.BackgroundColor3 = rarityColor
	accent.BorderSizePixel = 0
	accent.Parent = card

	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(0, 4)
	accentCorner.Parent = accent

	-- Left badge / icon text
	local badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.Position = UDim2.fromOffset(12, 7)
	badge.Size = UDim2.fromOffset(34, 34)
	badge.BackgroundColor3 = Color3.fromRGB(34, 40, 56)
	badge.BorderSizePixel = 0
	badge.Font = Enum.Font.GothamBlack
	badge.TextSize = 12
	badge.TextColor3 = rarityColor
	badge.Text = iconText or "INFO"
	badge.Parent = card

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 8)
	badgeCorner.Parent = badge

	-- Title label
	local titleLbl = Instance.new("TextLabel")
	titleLbl.Name = "Title"
	titleLbl.Position = UDim2.fromOffset(54, 5)
	titleLbl.Size = UDim2.new(1, -62, 0, 18)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Font = Enum.Font.GothamBlack
	titleLbl.TextSize = 13
	titleLbl.TextColor3 = Color3.fromRGB(250, 252, 255)
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.TextTruncate = Enum.TextTruncate.AtEnd
	titleLbl.Text = title
	titleLbl.Parent = card

	-- Message label
	local msgLbl = Instance.new("TextLabel")
	msgLbl.Name = "Message"
	msgLbl.Position = UDim2.fromOffset(54, 23)
	msgLbl.Size = UDim2.new(1, -62, 0, 18)
	msgLbl.BackgroundTransparency = 1
	msgLbl.Font = Enum.Font.GothamMedium
	msgLbl.TextSize = 11
	msgLbl.TextColor3 = Color3.fromRGB(195, 205, 225)
	msgLbl.TextXAlignment = Enum.TextXAlignment.Left
	msgLbl.TextTruncate = Enum.TextTruncate.AtEnd
	msgLbl.Text = message
	msgLbl.Parent = card

	-- Entry animation: Scale & slide pop
	local cardScale = Instance.new("UIScale")
	cardScale.Scale = 0.8
	cardScale.Parent = card

	TweenService:Create(cardScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1.0,
	}):Play()

	local cardObj: NotificationCard = {
		Frame = card,
		IsDismissing = false,
		CreatedTime = os.clock(),
	}
	table.insert(activeCards, cardObj)

	-- Schedule auto dismissal
	task.delay(CARD_LIFETIME_SECONDS, function()
		dismissCard(cardObj, true)
	end)
end

function NotificationController.ShowDropAlert(itemName: string, count: number, rarity: string, dropType: string)
	local title = if dropType == "Egg" then "TELUR DITEMUKAN!" else "ITEM DIGALI!"
	local msg = string.format("%dx %s (%s)", count, itemName, rarity)
	local badgeText = if dropType == "Egg" then "EGG" else "DROP"
	NotificationController.Notify(title, msg, rarity, badgeText)
end

function NotificationController.ShowAlert(message: string, alertType: string?)
	local title = if alertType == "Error" then "PERINGATAN" else "INFO"
	local rarity = if alertType == "Error" then "Epic" else "Common"
	NotificationController.Notify(title, message, rarity, if alertType == "Error" then "!" else "i")
end

function NotificationController.Start()
	if started then
		return
	end
	started = true

	local gui = Instance.new("ScreenGui")
	gui.Name = "DigPalsNotificationGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 18 -- Visible above standard HUD, below modals
	gui.IgnoreGuiInset = true

	local scaleInst = Instance.new("UIScale")
	scaleInst.Parent = gui
	uiScale = scaleInst

	local container = Instance.new("Frame")
	container.Name = "NotificationQueue"
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.Position = UDim2.new(0.5, 0, 0, 16)
	container.Size = UDim2.fromOffset(340, 240)
	container.BackgroundTransparency = 1
	container.Parent = gui
	containerFrame = container

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	listLayout.Padding = UDim.new(0, 6)
	listLayout.Parent = container

	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	gui.Parent = playerGui
	screenGui = gui

	local function bindCameraViewport()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveScale)
			updateResponsiveScale()
		end
	end
	bindCameraViewport()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCameraViewport)
end

return NotificationController
