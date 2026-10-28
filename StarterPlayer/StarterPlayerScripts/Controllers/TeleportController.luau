--!strict
-- Topbar Teleport UI Controller (aligned with Roblox logo/unibar at the top)
-- Replaces legacy 3D HubBaseTeleportPad with a persistent, responsive Topbar Pill button.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))

local AudioController = require(script.Parent:WaitForChild("AudioController"))
local NotificationController = require(script.Parent:WaitForChild("NotificationController"))

local LocalPlayer = Players.LocalPlayer

local TeleportController = {}

local COLORS = {
	BaseStroke = Color3.fromRGB(72, 196, 248),
	BaseHoverStroke = Color3.fromRGB(140, 235, 255),
	BaseBadge = Color3.fromRGB(30, 95, 160),
	BaseSub = Color3.fromRGB(108, 220, 255),

	HubStroke = Color3.fromRGB(246, 198, 68),
	HubHoverStroke = Color3.fromRGB(255, 230, 130),
	HubBadge = Color3.fromRGB(150, 110, 20),
	HubSub = Color3.fromRGB(255, 220, 96),

	BgNormal = Color3.fromRGB(24, 28, 38),
	BgHover = Color3.fromRGB(34, 42, 58),
	BgPressed = Color3.fromRGB(16, 20, 28),
}

local screenGui: ScreenGui? = nil
local pillButton: TextButton? = nil
local pillStroke: UIStroke? = nil
local iconBadge: Frame? = nil
local iconTextLabel: TextLabel? = nil
local titleLabel: TextLabel? = nil
local subLabel: TextLabel? = nil
local buttonScale: UIScale? = nil

local isDebounced = false
local currentZone: "Hub" | "Base" = "Hub"
local started = false

local function updatePosition()
	if not pillButton then
		return
	end

	local insetTop, _ = GuiService:GetGuiInset()
	local topInsetY = insetTop.Y
	local pillY = math.max(4, math.floor((topInsetY - 36) / 2))

	pillButton.AnchorPoint = Vector2.new(0.5, 0)
	pillButton.Position = UDim2.new(0.5, 0, 0, pillY)
end

local function refreshVisuals()
	if not pillButton or not pillStroke or not iconBadge or not iconTextLabel or not titleLabel or not subLabel then
		return
	end

	if currentZone == "Base" then
		-- When at Base, the button offers teleport back to HUB
		titleLabel.Text = "KE HUB"
		subLabel.Text = "Plaza Utama"
		subLabel.TextColor3 = COLORS.HubSub
		iconTextLabel.Text = "🏛️"
		iconBadge.BackgroundColor3 = COLORS.HubBadge
		pillStroke.Color = COLORS.HubStroke
	else
		-- When at Hub (or elsewhere), the button offers teleport to BASE
		titleLabel.Text = "KE BASE"
		subLabel.Text = "Inkubator & Pet"
		subLabel.TextColor3 = COLORS.BaseSub
		iconTextLabel.Text = "🌀"
		iconBadge.BackgroundColor3 = COLORS.BaseBadge
		pillStroke.Color = COLORS.BaseStroke
	end
end

function TeleportController.SetZone(zone: "Hub" | "Base")
	if currentZone == zone then
		return
	end
	currentZone = zone
	refreshVisuals()
end

function TeleportController.TeleportToBase()
	if isDebounced then
		return
	end
	isDebounced = true
	task.delay(1.2, function()
		isDebounced = false
	end)

	AudioController.PlayClick()
	NotificationController.Notify("Teleporting", "Menuju ke Base pribadi...", "Rare", "BASE")
	Remotes.GetEvent("TeleportToBase"):FireServer()
	TeleportController.SetZone("Base")
end

function TeleportController.TeleportToHub()
	if isDebounced then
		return
	end
	isDebounced = true
	task.delay(1.2, function()
		isDebounced = false
	end)

	AudioController.PlayClick()
	NotificationController.Notify("Teleporting", "Kembali ke Hub Plaza...", "Rare", "HUB")
	Remotes.GetEvent("TeleportToHub"):FireServer()
	TeleportController.SetZone("Hub")
end

function TeleportController.Toggle()
	if currentZone == "Base" then
		TeleportController.TeleportToHub()
	else
		TeleportController.TeleportToBase()
	end
end

local function buildGui()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("TeleportTopbarGui")
	if existing then
		existing:Destroy()
	end

	-- Also remove test gui if present
	local testGui = playerGui:FindFirstChild("TestTopbarGui")
	if testGui then
		testGui:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "TeleportTopbarGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 15
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	screenGui = gui

	local btn = Instance.new("TextButton")
	btn.Name = "TeleportPill"
	btn.AnchorPoint = Vector2.new(0.5, 0)
	btn.Size = UDim2.fromOffset(140, 36)
	btn.BackgroundColor3 = COLORS.BgNormal
	btn.BackgroundTransparency = 0.12
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.Parent = gui
	pillButton = btn

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = btn
	buttonScale = scale

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.BaseStroke
	stroke.Thickness = 1.6
	stroke.Parent = btn
	pillStroke = stroke

	-- Left Icon Badge (circle)
	local badge = Instance.new("Frame")
	badge.Name = "IconBadge"
	badge.Size = UDim2.fromOffset(26, 26)
	badge.AnchorPoint = Vector2.new(0, 0.5)
	badge.Position = UDim2.new(0, 5, 0.5, 0)
	badge.BackgroundColor3 = COLORS.BaseBadge
	badge.BorderSizePixel = 0
	badge.Parent = btn
	iconBadge = badge

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(1, 0)
	badgeCorner.Parent = badge

	local iconLbl = Instance.new("TextLabel")
	iconLbl.Name = "IconText"
	iconLbl.Size = UDim2.fromScale(1, 1)
	iconLbl.BackgroundTransparency = 1
	iconLbl.Font = Enum.Font.GothamBlack
	iconLbl.TextSize = 14
	iconLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	iconLbl.Text = "🌀"
	iconLbl.Parent = badge
	iconTextLabel = iconLbl

	-- Right Text Column
	local textCol = Instance.new("Frame")
	textCol.Name = "TextCol"
	textCol.Position = UDim2.fromOffset(36, 0)
	textCol.Size = UDim2.new(1, -40, 1, 0)
	textCol.BackgroundTransparency = 1
	textCol.Parent = btn

	local tLbl = Instance.new("TextLabel")
	tLbl.Name = "Title"
	tLbl.Position = UDim2.fromOffset(0, 3)
	tLbl.Size = UDim2.new(1, 0, 0, 16)
	tLbl.BackgroundTransparency = 1
	tLbl.Font = Enum.Font.GothamBlack
	tLbl.TextSize = 12
	tLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	tLbl.TextXAlignment = Enum.TextXAlignment.Left
	tLbl.Text = "KE BASE"
	tLbl.Parent = textCol
	titleLabel = tLbl

	local sLbl = Instance.new("TextLabel")
	sLbl.Name = "Sub"
	sLbl.Position = UDim2.fromOffset(0, 19)
	sLbl.Size = UDim2.new(1, 0, 0, 13)
	sLbl.BackgroundTransparency = 1
	sLbl.Font = Enum.Font.GothamBold
	sLbl.TextSize = 9
	sLbl.TextColor3 = COLORS.BaseSub
	sLbl.TextXAlignment = Enum.TextXAlignment.Left
	sLbl.Text = "Inkubator & Pet"
	sLbl.Parent = textCol
	subLabel = sLbl

	-- Animations & Interactions
	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = COLORS.BgHover
		local targetStroke = if currentZone == "Base" then COLORS.HubHoverStroke else COLORS.BaseHoverStroke
		pillStroke.Color = targetStroke
		pillStroke.Thickness = 2.0
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = 1.04,
		}):Play()
	end)

	btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = COLORS.BgNormal
		local normalStroke = if currentZone == "Base" then COLORS.HubStroke else COLORS.BaseStroke
		pillStroke.Color = normalStroke
		pillStroke.Thickness = 1.6
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = 1.0,
		}):Play()
	end)

	btn.MouseButton1Down:Connect(function()
		btn.BackgroundColor3 = COLORS.BgPressed
		scale.Scale = 0.95
	end)

	btn.MouseButton1Up:Connect(function()
		btn.BackgroundColor3 = COLORS.BgHover
		scale.Scale = 1.04
	end)

	btn.Activated:Connect(function()
		TeleportController.Toggle()
	end)

	updatePosition()
	refreshVisuals()
end

function TeleportController.Start()
	if started then
		return
	end
	started = true

	buildGui()

	-- Rebuild on character respawn / PlayerGui recreation
	LocalPlayer.CharacterAdded:Connect(function()
		task.wait(0.2)
		buildGui()
	end)

	-- Update position when viewport / GuiInset changes
	local function onViewportChanged()
		updatePosition()
	end
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(onViewportChanged)
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local newCam = workspace.CurrentCamera
		if newCam then
			newCam:GetPropertyChangedSignal("ViewportSize"):Connect(onViewportChanged)
			updatePosition()
		end
	end)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(onViewportChanged)

	-- Listen for CurrentZone attribute changes from server
	LocalPlayer:GetAttributeChangedSignal("CurrentZone"):Connect(function()
		local zone = LocalPlayer:GetAttribute("CurrentZone")
		if zone == "Base" or zone == "Hub" then
			TeleportController.SetZone(zone)
		end
	end)

	-- Periodically check distance to assigned plot for 100% accurate location sync
	task.spawn(function()
		while true do
			task.wait(1.0)
			local char = LocalPlayer.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				local plotName = LocalPlayer:GetAttribute("AssignedPlot")
				local basePlots = workspace:FindFirstChild("BasePlots")
				local plotFolder = basePlots and plotName and basePlots:FindFirstChild(plotName)
				local ground = plotFolder and (plotFolder:FindFirstChild(plotName .. "_Ground") or plotFolder:FindFirstChild("Ground")) :: BasePart?
				if ground then
					local dist = (hrp.Position - ground.Position).Magnitude
					if dist < 45 then
						TeleportController.SetZone("Base")
					elseif hrp.Position.Z < 60 then
						TeleportController.SetZone("Hub")
					end
				else
					if hrp.Position.Z < 60 then
						TeleportController.SetZone("Hub")
					end
				end
			end
		end
	end)
end

return TeleportController
