--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local CAS = game:GetService("ContextActionService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local PromptService = game:GetService("ProximityPromptService")
local PopupMotion = require(script.Parent:WaitForChild("PopupMotion"))
local CameraFocus = require(script.Parent:WaitForChild("NpcInteractionCamera"))
local InputGuard = require(script.Parent:WaitForChild("NpcInputGuard"))
local player = Players.LocalPlayer
local Dialogue = {}
type Choice = {Text: string, Selected: () -> ()}
type DialogueDetails = {Title: string, Body: string}
local gui: ScreenGui? = nil
local anchor: BasePart? = nil
local owner: string? = nil
local prompts: {[ProximityPrompt]: BillboardGui} = {}
local choicesNow: {Choice} = {}
local buttons: {TextButton} = {}
local selectedIndex = 1
local promptsPreviouslyEnabled: boolean? = nil
local choiceTweens: {[Instance]: Tween} = {}

local function animateChoice(button: TextButton, emphasized: boolean)
	local previous = choiceTweens[button]
	if previous then previous:Cancel() end
	local info = TweenInfo.new(if emphasized then 0.22 else 0.16,
		if emphasized then Enum.EasingStyle.Back else Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(button, info, {TextSize = if emphasized then 20 else 17})
	local padding = button:FindFirstChildOfClass("UIPadding")
	if padding then
		local previousPadding = choiceTweens[padding]
		if previousPadding then previousPadding:Cancel() end
		local slide = TweenService:Create(padding, info, {PaddingLeft = UDim.new(0, if emphasized then 12 else 6)})
		choiceTweens[padding] = slide
		slide.Completed:Connect(function()
			if choiceTweens[padding] == slide then choiceTweens[padding] = nil end
		end)
		slide:Play()
	end
	choiceTweens[button] = tween
	tween.Completed:Connect(function()
		if choiceTweens[button] == tween then choiceTweens[button] = nil end
	end)
	tween:Play()
end

local function selectIndex(index: number)
	if #buttons == 0 then return end
	selectedIndex = ((index - 1) % #buttons) + 1
	for i, button in buttons do
		local selected = i == selectedIndex
		animateChoice(button, selected)
		button.BackgroundColor3 = if selected then Color3.fromRGB(110, 82, 36) else Color3.fromRGB(37, 34, 32)
		button.BackgroundTransparency = if selected then 0.96 else 1
		button.TextColor3 = if selected then Color3.fromRGB(255, 235, 174) else Color3.fromRGB(255, 250, 239)
	end
end

function Dialogue.Close(ownerName: string?)
	if ownerName and owner ~= ownerName then return end
	local closingGui, closingOwner = gui, owner
	gui, anchor, owner = nil, nil, nil
	for _, tween in choiceTweens do tween:Cancel() end
	table.clear(choiceTweens)
	choicesNow, buttons = {}, {}
	InputGuard.SetActive(false)
	if promptsPreviouslyEnabled ~= nil then
		PromptService.Enabled = promptsPreviouslyEnabled
		promptsPreviouslyEnabled = nil
	end
	if closingGui then
		local list = closingGui:FindFirstChild("Choices")
		if list and list:IsA("GuiObject") then PopupMotion.Play(list, nil, false) end
		task.delay(0.5, function() closingGui:Destroy() end)
	end
	if closingOwner then
		CameraFocus.End(closingOwner)
		if player:GetAttribute("ActiveShopModal") == closingOwner then player:SetAttribute("ActiveShopModal", "") end
	end
end

function Dialogue.IsOpen(ownerName: string?): boolean
	return gui ~= nil and (ownerName == nil or owner == ownerName)
end

local function activateChoice(index: number)
	if not gui then return end
	local choice = choicesNow[index]
	if not choice then return end
	-- Close synchronously before callbacks can yield or open another panel.
	Dialogue.Close()
	choice.Selected()
end

function Dialogue.Open(target: BasePart, choices: {Choice}, ownerName: string?, details: DialogueDetails?)
	Dialogue.Close()
	if #choices == 0 then return end
	anchor, owner = target, ownerName or "ShovelkeeperDialogue"
	choicesNow = choices
	selectedIndex = 1
	InputGuard.SetActive(true)
	-- Native proximity prompts otherwise take E before the dialogue can confirm.
	promptsPreviouslyEnabled = PromptService.Enabled
	PromptService.Enabled = false
	player:SetAttribute("ActiveShopModal", owner)
	CameraFocus.Begin(target, owner :: string)
	local screen = Instance.new("ScreenGui")
	screen.Name = "NpcDialogueGui"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 35
	local contentWidth = 0
	for index, choice in choices do
		local text = (if UIS.KeyboardEnabled and index <= 9 then "[" .. index .. "]  " else "") .. choice.Text
		contentWidth = math.max(contentWidth, TextService:GetTextSize(text, 20, Enum.Font.GothamBold, Vector2.new(1000, 30)).X + 18)
	end
	local detailsHeight = if details then 72 else 0
	if details then contentWidth = math.max(contentWidth, 300) end
	local list = Instance.new("Frame")
	list.Name = "Choices"
	list.AnchorPoint = Vector2.new(0, 0.5)
	list.Position = UDim2.fromScale(0.63, 0.5)
	list.Size = UDim2.new(0.82, 0, 0, #choices * 30 + math.max(0, #choices - 1) * 2 + detailsHeight)
	list.Visible = false
	list.Active = true
	list.BackgroundColor3 = Color3.fromRGB(24, 23, 24)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Parent = screen
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = list
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(math.ceil(contentWidth), 1000)
	constraint.Parent = list
	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.Position = UDim2.fromOffset(0, detailsHeight)
	rows.Size = UDim2.new(1, 0, 1, -detailsHeight)
	rows.BackgroundTransparency = 1
	rows.Parent = list
	if details then
		local heading = Instance.new("TextLabel")
		heading.Name = "OfferTitle"
		heading.Position = UDim2.fromOffset(6, 0)
		heading.Size = UDim2.new(1, -12, 0, 22)
		heading.BackgroundTransparency = 1
		heading.Font = Enum.Font.BuilderSansBold
		heading.TextSize = 18
		heading.TextColor3 = Color3.fromRGB(255, 229, 162)
		heading.TextStrokeTransparency = 0.2
		heading.TextXAlignment = Enum.TextXAlignment.Left
		heading.Text = details.Title
		heading.Parent = list
		local body = Instance.new("TextLabel")
		body.Name = "OfferDescription"
		body.Position = UDim2.fromOffset(6, 25)
		body.Size = UDim2.new(1, -12, 0, 42)
		body.BackgroundTransparency = 1
		body.Font = Enum.Font.BuilderSansMedium
		body.TextSize = 13
		body.TextColor3 = Color3.fromRGB(250, 247, 235)
		body.TextStrokeTransparency = 0.25
		body.TextWrapped = true
		body.TextXAlignment = Enum.TextXAlignment.Left
		body.TextYAlignment = Enum.TextYAlignment.Top
		body.Text = details.Body
		body.Parent = list
	end
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = rows
	for index, choice in choices do
		local button = Instance.new("TextButton")
		button.Name = "Choice" .. index
		button.LayoutOrder = index
		button.Size = UDim2.fromOffset(0, 30)
		button.AutomaticSize = Enum.AutomaticSize.X
		button.AutoButtonColor = false
		button.Selectable = false
		button.BorderSizePixel = 0
		button.Text = (if UIS.KeyboardEnabled and index <= 9 then "[" .. index .. "]  " else "") .. choice.Text
		button.TextSize = 17
		button.TextStrokeTransparency = 0.2
		button.Font = Enum.Font.GothamBold
		button.TextXAlignment = Enum.TextXAlignment.Left
		button.Parent = rows
		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 12)
		rowCorner.Parent = button
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 6)
		padding.PaddingRight = UDim.new(0, 6)
		padding.Parent = button
		table.insert(buttons, button)
		button.MouseEnter:Connect(function()
			if gui == screen then selectIndex(index) end
		end)
		button.MouseLeave:Connect(function()
			if gui == screen then animateChoice(button, false) end
		end)
		button.Activated:Connect(function()
			if gui == screen then activateChoice(index) end
		end)
	end
	gui = screen
	screen.Parent = player:WaitForChild("PlayerGui")
	selectIndex(1)
	PopupMotion.Play(list, nil, true)
end

local numberKeys: {[Enum.KeyCode]: number} = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.Two] = 2, [Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.Three] = 3, [Enum.KeyCode.KeypadThree] = 3,
	[Enum.KeyCode.Four] = 4, [Enum.KeyCode.KeypadFour] = 4,
	[Enum.KeyCode.Five] = 5, [Enum.KeyCode.KeypadFive] = 5,
	[Enum.KeyCode.Six] = 6, [Enum.KeyCode.KeypadSix] = 6,
	[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.KeypadSeven] = 7,
	[Enum.KeyCode.Eight] = 8, [Enum.KeyCode.KeypadEight] = 8,
	[Enum.KeyCode.Nine] = 9, [Enum.KeyCode.KeypadNine] = 9,
}
local capturedKeys = {}
for _, key in Enum.KeyCode:GetEnumItems() do
	if key ~= Enum.KeyCode.Unknown then table.insert(capturedKeys, key) end
end
CAS:BindActionAtPriority("NpcDialogueInput", function(_, state: Enum.UserInputState, input: InputObject)
	if not gui then
		if state == Enum.UserInputState.Begin then InputGuard.BeginUncaptured(input) end
		return if InputGuard.WasConsumed(input) then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
	end
	if UIS:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
	InputGuard.Capture(input)
	if state == Enum.UserInputState.Begin then
		local key = input.KeyCode
		if key == Enum.KeyCode.Up or key == Enum.KeyCode.W or key == Enum.KeyCode.DPadUp then
			selectIndex(selectedIndex - 1)
		elseif key == Enum.KeyCode.Down or key == Enum.KeyCode.S or key == Enum.KeyCode.DPadDown then
			selectIndex(selectedIndex + 1)
		elseif numberKeys[key] then
			activateChoice(numberKeys[key])
		elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter or key == Enum.KeyCode.E or key == Enum.KeyCode.ButtonA then
			activateChoice(selectedIndex)
		elseif key == Enum.KeyCode.X or key == Enum.KeyCode.Backspace or key == Enum.KeyCode.Escape or key == Enum.KeyCode.ButtonB then
			Dialogue.Close()
		end
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.ContextActionPriority.High.Value + 100,
	table.unpack(capturedKeys))

function Dialogue.HidePrompt(prompt: ProximityPrompt)
	local old = prompts[prompt]
	if old then old:Destroy() prompts[prompt] = nil end
end

local function getChestOffset(prompt: ProximityPrompt): Vector3
	local model = prompt:FindFirstAncestorWhichIsA("Model")
	if model then
		local name = model.Name:lower()
		if name:find("shovelkeeper") or name:find("shovel") then
			return Vector3.new(0, -1.45, 0)
		elseif name:find("merchant") then
			return Vector3.new(0, -1.25, 0)
		end
	end
	return Vector3.new(0, -1.35, 0)
end

function Dialogue.ShowPrompt(prompt: ProximityPrompt)
	Dialogue.HidePrompt(prompt)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NpcTalkHint"
	billboard.Adornee = prompt.Parent
	billboard.Size = UDim2.fromOffset(140, 44)
	billboard.StudsOffsetWorldSpace = getChestOffset(prompt)
	billboard.AlwaysOnTop = true
	billboard.Active = true
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundTransparency = 1
	button.Text = if UIS.TouchEnabled then "Bicara" else "[E] Bicara"
	button.Font = Enum.Font.GothamBold
	button.TextSize = 18
	button.TextColor3 = Color3.fromRGB(255, 232, 155)
	button.TextStrokeTransparency = 0.3
	button.Parent = billboard
	button.Activated:Connect(function() prompt:InputHoldBegin() prompt:InputHoldEnd() end)
	billboard.Parent = player:WaitForChild("PlayerGui")
	prompts[prompt] = billboard
end

-- Keep choices beside the NPC as the interaction camera settles.
RunService.RenderStepped:Connect(function()
	local screen, target, camera = gui, anchor, workspace.CurrentCamera
	if not screen or not target or not camera then return end
	local list = screen:FindFirstChild("Choices")
	if not list or not list:IsA("Frame") then return end
	local point = camera:WorldToScreenPoint(target.Position)
	local bounds = screen.AbsoluteSize
	local size = list.AbsoluteSize
	local gap = math.clamp(bounds.X * 0.1, 48, 120)
	local x = point.X + gap
	if x + size.X > bounds.X - 12 then x = point.X - gap - size.X end
	x = math.clamp(x, 12, math.max(12, bounds.X - size.X - 12))
	local y = math.clamp(point.Y + 24, size.Y * 0.5 + 12, math.max(size.Y * 0.5 + 12, bounds.Y - size.Y * 0.5 - 12))
	list.Position = UDim2.fromOffset(math.round(x), math.round(y))
end)

RunService.Heartbeat:Connect(function()
	local modal = player:GetAttribute("ActiveShopModal")
	for _, hint in prompts do hint.Enabled = not Dialogue.IsOpen() and (modal == nil or modal == "") end
	if not gui then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not anchor or not anchor.Parent or not root or not root:IsA("BasePart") or not humanoid
		or humanoid.Health <= 0 or (root.Position - anchor.Position).Magnitude > 18
		or player:GetAttribute("DigMinigameActive") == true or player:GetAttribute("ActiveShopModal") ~= owner then
		Dialogue.Close()
	end
end)
player.CharacterRemoving:Connect(function() Dialogue.Close() end)

return Dialogue
