--!strict
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local CAS = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config.Sprint)
local Remotes = require(Shared.Util.Remotes)
local InputController = require(script.Parent.InputController)
local player = Players.LocalPlayer
local Controller = {}
local started = false
local shiftKeys: {[Enum.KeyCode]: boolean} = {}
local toggled = false
local focused = true
local lastSent = false
local lastSendTime = 0
local button: TextButton?
local gui: ScreenGui?
local stroke: UIStroke?

local function blocked(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return not focused or GuiService.MenuIsOpen or UIS:GetFocusedTextBox() ~= nil
		or not humanoid or humanoid.Health <= 0 or humanoid.Sit or humanoid.PlatformStand
		or character:GetAttribute("MovementLocked") == true
		or player:GetAttribute("DigMinigameActive") == true or InputController.IsAnyModalOpen()
end

local function desired(): boolean
	return not blocked() and (toggled or next(shiftKeys) ~= nil)
end

local function refresh()
	local enabled = desired()
	if button then
		button.Text = if enabled then "LARI ON" else "LARI"
		button.BackgroundColor3 = if enabled then Color3.fromRGB(36, 139, 157) else Color3.fromRGB(28, 45, 57)
		button.Visible = UIS.TouchEnabled and not blocked()
	end
	if stroke then stroke.Color = if enabled then Color3.fromRGB(255, 215, 102) else Color3.fromRGB(137, 185, 195) end
	if enabled ~= lastSent or os.clock() - lastSendTime >= Config.RequestInterval then
		lastSent, lastSendTime = enabled, os.clock()
		Remotes.GetEvent("SetSprinting"):FireServer(enabled)
	end
end

local function reset()
	table.clear(shiftKeys)
	toggled = false
	refresh()
end

local function createButton()
	local screen = Instance.new("ScreenGui")
	screen.Name = "SprintGui"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 12
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	local touch = Instance.new("TextButton")
	touch.Name = "RunToggle"
	touch.AnchorPoint = Vector2.new(0.5, 0.5)
	touch.Size = UDim2.fromOffset(70, 70)
	touch.Position = UDim2.new(1, -90, 1, -190)
	touch.TextColor3 = Color3.fromRGB(255, 245, 211)
	touch.Font = Enum.Font.GothamBold
	touch.TextSize = 12
	touch.TextYAlignment = Enum.TextYAlignment.Bottom
	touch.AutoButtonColor = true
	touch.BorderSizePixel = 0
	touch.Parent = screen
	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0, 9)
	padding.Parent = touch
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = touch
	local outline = Instance.new("UIStroke")
	outline.Thickness = 2
	outline.Parent = touch
	-- A simple running figure made from UI shapes; no external icon dependency.
	local function line(name: string, x: number, y: number, width: number, height: number, angle: number, round: boolean?)
		local part = Instance.new("Frame")
		part.Name = name
		part.AnchorPoint = Vector2.new(0.5, 0.5)
		part.Position = UDim2.fromOffset(x, y)
		part.Size = UDim2.fromOffset(width, height)
		part.Rotation = angle
		part.BackgroundColor3 = Color3.fromRGB(255, 245, 211)
		part.BorderSizePixel = 0
		part.Parent = touch
		local radius = Instance.new("UICorner")
		radius.CornerRadius = UDim.new(if round then 0.5 else 0, if round then 0 else 2)
		radius.Parent = part
	end
	line("Head", 40, 12, 9, 9, 0, true)
	line("Body", 34, 26, 5, 19, 25)
	line("ArmBack", 25, 23, 15, 4, -35)
	line("ArmFront", 43, 27, 14, 4, 22)
	line("LegBack", 25, 40, 19, 4, -48)
	line("LegFront", 40, 39, 18, 4, 45)
	button, gui, stroke = touch, screen, outline
	touch.Activated:Connect(function()
		if blocked() then return end
		toggled = not toggled
		refresh()
	end)
	screen.Parent = player:WaitForChild("PlayerGui")
end

local function layout()
	if not button or not gui then return end
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local touchGui = pg and pg:FindFirstChild("TouchGui")
	local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
	local view = gui.AbsoluteSize
	-- JumpButton can briefly retain the previous orientation's coordinates.
	button.Position = UDim2.new(1, -90, 1, -190)
	if jump and jump:IsA("GuiObject") and jump.Visible and jump.AbsoluteSize.X > 0 then
		local pos, size = jump.AbsolutePosition, jump.AbsoluteSize
		local origin = gui.AbsolutePosition
		if pos.X >= view.X or pos.Y >= view.Y then return end
		button.Position = UDim2.fromOffset(
			math.clamp(pos.X + size.X * 0.5 - origin.X, 42, math.max(42, view.X - 42)),
			math.clamp(pos.Y - 48 - origin.Y, 42, math.max(42, view.Y - 42)))
	end
end

function Controller.Start()
	if started then return end
	started = true
	createButton()
	if gui then gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout) end
	CAS:BindActionAtPriority("DigPalsSprint", function(_, state, input)
		if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			shiftKeys[input.KeyCode] = nil
		elseif state == Enum.UserInputState.Begin and not blocked() then
			shiftKeys[input.KeyCode] = true
		end
		refresh()
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift)
	UIS.WindowFocusReleased:Connect(function() focused = false reset() end)
	UIS.WindowFocused:Connect(function() focused = true end)
	UIS.TextBoxFocused:Connect(reset)
	GuiService.MenuOpened:Connect(reset)
	player.CharacterAdded:Connect(reset)
	player.CharacterRemoving:Connect(reset)
	player:GetAttributeChangedSignal("DigMinigameActive"):Connect(function()
		if player:GetAttribute("DigMinigameActive") then reset() end
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.1 then return end
		elapsed = 0
		if blocked() then table.clear(shiftKeys) toggled = false end
		layout()
		refresh()
	end)
	refresh()
end

return Controller
