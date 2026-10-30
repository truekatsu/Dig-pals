--!strict
-- Two permanent destination buttons, styled to match the adventure hotbar.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Remotes"))
local AudioController = require(script.Parent:WaitForChild("AudioController"))
local LocalPlayer = Players.LocalPlayer
local TeleportController = {}

local screenGui: ScreenGui? = nil
local buttonRow: Frame? = nil
local viewportConnection: RBXScriptConnection? = nil
local currentZone: "Hub" | "Base" = "Hub"
local isDebounced = false
local started = false

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function updatePosition()
	if not buttonRow then return end
	local camera = workspace.CurrentCamera
	if not camera then return end
	local inset = GuiService:GetGuiInset()
	local y = if camera.ViewportSize.X < 640 then math.max(inset.Y, 36) + 4
		else math.max(6, math.floor((inset.Y - 44) * 0.5))
	buttonRow.Position = UDim2.new(0.5, 0, 0, y)
end

function TeleportController.SetZone(zone: "Hub" | "Base")
	currentZone = zone
end

local function teleport(destination: "Base" | "Hub")
	if isDebounced then return end
	local character = LocalPlayer.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then return end
	isDebounced = true
	AudioController.PlayClick()
	Remotes.GetEvent(if destination == "Base" then "TeleportToBase" else "TeleportToHub"):FireServer()
	task.delay(1.2, function()
		isDebounced = false
	end)
end

function TeleportController.TeleportToBase()
	teleport("Base")
end

function TeleportController.TeleportToHub()
	teleport("Hub")
end

-- Preserve the existing keyboard shortcut while both destinations stay visible.
function TeleportController.Toggle()
	if currentZone == "Base" then TeleportController.TeleportToHub()
	else TeleportController.TeleportToBase() end
end

local function iconPart(parent: Instance, name: string, x: number, y: number, width: number, height: number): Frame
	local part = Instance.new("Frame")
	part.Name = name
	part.Position = UDim2.fromOffset(x, y)
	part.Size = UDim2.fromOffset(width, height)
	part.BackgroundColor3 = Color3.fromRGB(255, 248, 225)
	part.BorderSizePixel = 0
	part.ZIndex = 3
	part.Parent = parent
	return part
end

local function drawIcon(parent: Instance, isBase: boolean)
	local icon = Instance.new("Frame")
	icon.Name = if isBase then "HouseIcon" else "PlazaIcon"
	icon.BackgroundTransparency = 1
	icon.Position = UDim2.fromOffset(10, 10)
	icon.Size = UDim2.fromOffset(26, 26)
	icon.Parent = parent
	if isBase then
		local roof = iconPart(icon, "Roof", 6, 1, 16, 16)
		roof.Rotation = 45
		round(roof, 2)
		local body = iconPart(icon, "House", 3, 10, 22, 15)
		body.ZIndex = 4
		round(body, 2)
		local door = iconPart(icon, "Door", 11, 16, 6, 9)
		door.ZIndex = 5
		door.BackgroundColor3 = Color3.fromRGB(132, 78, 25)
	else
		iconPart(icon, "Roof", 1, 1, 24, 4)
		iconPart(icon, "UpperStep", 4, 6, 18, 2)
		for i = 0, 2 do iconPart(icon, "Column" .. i, 4 + i * 7, 9, 4, 12) end
		iconPart(icon, "LowerStep", 1, 22, 24, 4)
	end
end

local function destinationButton(parent: Frame, name: string, label: string, isBase: boolean, callback: () -> ())
	local button = Instance.new("TextButton")
	button.Name = name
	button.LayoutOrder = if isBase then 1 else 2
	button.Size = UDim2.fromOffset(118, 44)
	button.BackgroundColor3 = Color3.new(1, 1, 1)
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = false
	button.Selectable = true
	button.Parent = parent
	round(button, 10)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(17, 20, 24)
	stroke.Thickness = 2.5
	stroke.Parent = button
	local gradient = Instance.new("UIGradient")
	gradient.Color = if isBase then ColorSequence.new(Color3.fromRGB(255, 205, 86), Color3.fromRGB(206, 128, 38))
		else ColorSequence.new(Color3.fromRGB(80, 150, 168), Color3.fromRGB(43, 76, 91))
	gradient.Rotation = 90
	gradient.Parent = button

	local rim = Instance.new("Frame")
	rim.Name = "InnerRim"
	rim.Position = UDim2.fromOffset(3, 3)
	rim.Size = UDim2.new(1, -6, 1, -6)
	rim.BackgroundTransparency = 1
	rim.Parent = button
	round(rim, 8)
	local rimStroke = Instance.new("UIStroke")
	rimStroke.Color = if isBase then Color3.fromRGB(255, 231, 139) else Color3.fromRGB(152, 215, 223)
	rimStroke.Transparency = 0.2
	rimStroke.Thickness = 1.2
	rimStroke.Parent = rim
	drawIcon(button, isBase)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(42, 0)
	title.Size = UDim2.new(1, -48, 1, 0)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 16
	title.Text = label
	title.TextColor3 = Color3.fromRGB(255, 250, 233)
	title.TextStrokeColor3 = Color3.fromRGB(31, 23, 16)
	title.TextStrokeTransparency = 0
	title.ZIndex = 4
	title.Parent = button

	local scale = Instance.new("UIScale")
	scale.Parent = button
	local function animate(value: number)
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = value }):Play()
	end
	button.MouseEnter:Connect(function()
		rimStroke.Transparency = 0
		animate(1.04)
	end)
	button.MouseLeave:Connect(function()
		rimStroke.Transparency = 0.2
		animate(1)
	end)
	button.MouseButton1Down:Connect(function() animate(0.96) end)
	button.MouseButton1Up:Connect(function() animate(1) end)
	button.Activated:Connect(callback)
end

local function buildGui()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("TeleportTopbarGui")
	if existing then existing:Destroy() end
	local oldTest = playerGui:FindFirstChild("TestTopbarGui")
	if oldTest then oldTest:Destroy() end
	local gui = Instance.new("ScreenGui")
	gui.Name = "TeleportTopbarGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 15
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	screenGui = gui

	local row = Instance.new("Frame")
	row.Name = "DestinationButtons"
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Size = UDim2.fromOffset(246, 44)
	row.BackgroundTransparency = 1
	row.Parent = gui
	buttonRow = row
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	destinationButton(row, "BaseButton", "BASE", true, TeleportController.TeleportToBase)
	destinationButton(row, "PlazaButton", "PLAZA", false, TeleportController.TeleportToHub)
	updatePosition()
end

function TeleportController.Start()
	if started then return end
	started = true
	local zone = LocalPlayer:GetAttribute("CurrentZone")
	if zone == "Base" or zone == "Hub" then currentZone = zone end
	buildGui()
	LocalPlayer.CharacterAdded:Connect(function()
		task.wait(0.2)
		if not screenGui or screenGui.Parent ~= LocalPlayer:FindFirstChild("PlayerGui") then buildGui() end
		local updated = LocalPlayer:GetAttribute("CurrentZone")
		if updated == "Base" or updated == "Hub" then currentZone = updated end
	end)
	local function connectCamera()
		if viewportConnection then viewportConnection:Disconnect() end
		local camera = workspace.CurrentCamera
		if camera then viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updatePosition) end
		updatePosition()
	end
	connectCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(connectCamera)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(updatePosition)
	LocalPlayer:GetAttributeChangedSignal("CurrentZone"):Connect(function()
		local updated = LocalPlayer:GetAttribute("CurrentZone")
		if updated == "Base" or updated == "Hub" then currentZone = updated end
	end)

	-- Walking back from a plot also keeps the existing toggle shortcut in sync.
	task.spawn(function()
		while started do
			task.wait(1)
			local character = LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root or not root:IsA("BasePart") then continue end
			local plotName = LocalPlayer:GetAttribute("AssignedPlot")
			local plots = workspace:FindFirstChild("BasePlots")
			local plot = if plots and type(plotName) == "string" then plots:FindFirstChild(plotName) else nil
			local ground = plot and (plot:FindFirstChild(tostring(plotName) .. "_Ground") or plot:FindFirstChild("Ground"))
			if ground and ground:IsA("BasePart") and (root.Position - ground.Position).Magnitude < 45 then
				currentZone = "Base"
			elseif root.Position.Z < 60 then
				currentZone = "Hub"
			end
		end
	end)
end

return TeleportController
