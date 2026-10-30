--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer
local Dialogue = {}
local gui: ScreenGui? = nil
local anchor: BasePart? = nil
local owner: string? = nil
local prompts: {[ProximityPrompt]: BillboardGui} = {}

function Dialogue.Close(ownerName: string?)
	if ownerName and owner ~= ownerName then return end
	if gui then gui:Destroy() gui = nil end
	anchor = nil
	if player:GetAttribute("ActiveShopModal") == owner then player:SetAttribute("ActiveShopModal", "") end
	owner = nil
end

function Dialogue.IsOpen(ownerName: string?): boolean
	return gui ~= nil and (ownerName == nil or owner == ownerName)
end

function Dialogue.Open(target: BasePart, choices: {{Text: string, Selected: () -> ()}}, ownerName: string?)
	Dialogue.Close()
anchor, owner = target, ownerName or "ShovelkeeperDialogue"
	player:SetAttribute("ActiveShopModal", owner)
	local screen = Instance.new("ScreenGui")
	screen.Name = "NpcDialogueGui"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 35
	local list = Instance.new("Frame")
	list.Name = "Choices"
	list.AnchorPoint = Vector2.new(0.5, 1)
	list.Position = UDim2.fromScale(0.5, 0.79)
	list.Size = UDim2.new(0.88, 0, 0, #choices * 48)
	list.BackgroundColor3 = Color3.fromRGB(25, 23, 26)
	list.BackgroundTransparency = 0.55
	list.BorderSizePixel = 0
	list.Parent = screen
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(520, 1000)
	constraint.Parent = list
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	for index, choice in choices do
		local button = Instance.new("TextButton")
		button.Name = "Choice" .. index
		button.LayoutOrder = index
		button.Size = UDim2.new(1, 0, 0, 48)
		button.BackgroundColor3 = Color3.fromRGB(204, 166, 84)
		button.BackgroundTransparency = 1
		button.BorderSizePixel = 0
		button.Text = choice.Text
		button.TextSize = 20
		button.Font = Enum.Font.GothamMedium
		button.TextColor3 = Color3.fromRGB(255, 248, 231)
		button.TextStrokeTransparency = 0.5
		button.TextXAlignment = Enum.TextXAlignment.Left
		button.Parent = list
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 20)
		padding.PaddingRight = UDim.new(0, 12)
		padding.Parent = button
		button.MouseEnter:Connect(function() button.BackgroundTransparency = 0.75 end)
		button.MouseLeave:Connect(function() button.BackgroundTransparency = 1 end)
		button.Activated:Connect(function()
			Dialogue.Close()
			choice.Selected()
		end)
	end
	gui = screen
	screen.Parent = player:WaitForChild("PlayerGui")
end

function Dialogue.HidePrompt(prompt: ProximityPrompt)
	local old = prompts[prompt]
	if old then old:Destroy() prompts[prompt] = nil end
end

function Dialogue.ShowPrompt(prompt: ProximityPrompt)
	Dialogue.HidePrompt(prompt)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NpcTalkHint"
	billboard.Adornee = prompt.Parent
	billboard.Size = UDim2.fromOffset(140, 44)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 1.6, 0)
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
