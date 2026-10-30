--!strict
-- Five-step onboarding with a client-only animated blue trail to live gameplay targets.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Remotes"))
local MoundVisuals = require(script.Parent:WaitForChild("MoundVisuals"))
local LocalPlayer = Players.LocalPlayer
local TutorialController = {}

local BLUE = Color3.fromRGB(72, 173, 255)
local INK = Color3.fromRGB(16, 29, 47)
local ARROW_COUNT = 32
local ARROW_SPACING = 5.5

type TrailArrow = { Part: Part, Gui: BillboardGui, Label: TextLabel }
local arrows: { TrailArrow } = {}
local guideFolder: Folder? = nil
local targetHighlight: Highlight? = nil
local marker: Part? = nil
local markerGui: BillboardGui? = nil
local markerLabel: TextLabel? = nil
local targetPosition: Vector3? = nil
local targetMoundId: string? = nil

local banner: Frame? = nil
local title: TextLabel? = nil
local instruction: TextLabel? = nil
local action: TextButton? = nil
local currentStep = 1
local isDone = false
local started = false
local hasEquippedPet = false
local refreshElapsed = 0
local completionRequested = false

local steps = {
	{ Title = "Gali Small Mound", Text = "Pegang sekop, lalu klik gundukan." },
	{ Title = "Jual hasil galian", Text = "Jual item ke Item Merchant." },
	{ Title = "Tetaskan Starter Egg", Text = "Pilih telur di Items > Eggs, lalu taruh di Base." },
	{ Title = "Gali bersama pet", Text = "Equip pet di PETS, lalu gali." },
	{ Title = "Kunjungi Shovel Shop", Text = "Datangi Shovel Shop untuk menyelesaikan tutorial." },
}

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function textLabel(parent: Instance, name: string, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = size
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function cosmeticPart(name: string, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Anchored = true
	part.Transparency = 1
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

local function clearGuidance()
	if guideFolder then guideFolder:Destroy() end
	guideFolder, targetHighlight, marker, markerGui, markerLabel = nil, nil, nil, nil, nil
	table.clear(arrows)
	targetPosition, targetMoundId = nil, nil
end

local function ensureGuidance()
	if guideFolder and guideFolder.Parent then return end
	local folder = Instance.new("Folder")
	folder.Name = "TutorialGuidance"
	guideFolder = folder
	for i = 1, ARROW_COUNT do
		local part = cosmeticPart("TrailArrow" .. i, folder)
		local gui = Instance.new("BillboardGui")
		gui.Name = "ArrowGui"
		gui.Size = UDim2.new(1.8, 4, 1.8, 4)
		gui.AlwaysOnTop = false
		gui.LightInfluence = 0
		gui.MaxDistance = 180
		gui.Enabled = false
		gui.Parent = part
		local label = textLabel(gui, "Arrow", 24, BLUE)
		label.Size = UDim2.fromScale(1, 1)
		label.Text = "▶"
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextStrokeColor3 = INK
		label.TextStrokeTransparency = 0.05
		table.insert(arrows, { Part = part, Gui = gui, Label = label })
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "TutorialTargetHighlight"
	highlight.FillColor = BLUE
	highlight.FillTransparency = 0.9
	highlight.OutlineColor = BLUE
	highlight.OutlineTransparency = 0.12
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	highlight.Parent = folder
	targetHighlight = highlight
	marker = cosmeticPart("TargetMarker", folder)
	local gui = Instance.new("BillboardGui")
	gui.Name = "TargetGui"
	gui.Size = UDim2.fromOffset(180, 46)
	gui.StudsOffset = Vector3.new(0, 2.2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 180
	gui.Enabled = false
	gui.Parent = marker
	markerGui = gui
	local label = textLabel(gui, "TargetLabel", 13, BLUE)
	label.Size = UDim2.fromScale(1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextStrokeColor3 = INK
	label.TextStrokeTransparency = 0
	markerLabel = label
	folder.Parent = workspace
end

local function refreshUI()
	if not banner then return end
	banner.Visible = not isDone
	if isDone then clearGuidance(); return end
	local info = steps[currentStep]
	if title then title.Text = info.Title end
	if instruction then instruction.Text = info.Text end
	if action then
		action.Visible = currentStep == 4
		action.Text = if currentStep == 3 then (if LocalPlayer:GetAttribute("CurrentZone") == "Base" then "EGGS" else "KE BASE")
			else "BUKA PETS"
	end
end

local function refreshTarget(root: BasePart)
	local position: Vector3? = nil
	local adornee: Instance? = nil
	local label = ""
	local hint = steps[currentStep].Text
	if currentStep == 1 or currentStep == 4 then
		-- Re-evaluate every refresh so the guide always points to the closest live Small Mound.
		local id, model, moundPosition = MoundVisuals.GetTutorialMound(root.Position, nil)
		targetMoundId = id
		position, adornee, label = moundPosition, model, "SMALL MOUND"
		if not position then hint = "Menunggu Small Mound..."
		elseif currentStep == 4 and not hasEquippedPet then hint = "Buka PETS dan equip pet dahulu." end
	elseif currentStep == 2 or currentStep == 5 then
		local plain = workspace:FindFirstChild("Plain")
		local merchants = plain and plain:FindFirstChild("Merchant")
		local counter = merchants and merchants:FindFirstChild(if currentStep == 2 then "ItemMerchant_Counter" else "ShovelShop_Counter")
		if counter and counter:IsA("BasePart") then position, adornee = counter.Position, counter end
		label = if currentStep == 2 then "ITEM MERCHANT" else "SHOVEL SHOP"
	elseif currentStep == 3 then
		local plotName = LocalPlayer:GetAttribute("AssignedPlot")
		local plots = workspace:FindFirstChild("BasePlots")
		local plot = if plots and type(plotName) == "string" then plots:FindFirstChild(plotName) else nil
		local ground = plot and plot:FindFirstChild(tostring(plotName) .. "_Ground")
		if ground and ground:IsA("BasePart") then
			local sign = plot and plot:FindFirstChild(tostring(plotName) .. "_SignBoard")
			position = if sign and sign:IsA("BasePart") then sign.Position + Vector3.new(0, 0, -5) else ground.Position
		end
		label = "BASE KAMU"
		hint = if LocalPlayer:GetAttribute("CurrentZone") == "Base" then "Pilih telur di Items > Eggs, lalu klik area Base." else "Pilih telur di Items > Eggs, lalu menuju Base."
	end
	targetPosition = position
	if currentStep == 5 and position and not completionRequested then
		local delta = Vector2.new(root.Position.X - position.X, root.Position.Z - position.Z)
		if delta.Magnitude <= 18 then
			completionRequested = true
			Remotes.GetEvent("AdvanceTutorial"):FireServer(5)
		end
	end
	if instruction then instruction.Text = hint end
	if targetHighlight then
		targetHighlight.Adornee = adornee
		targetHighlight.Enabled = adornee ~= nil
	end
	if marker and markerGui and markerLabel then
		markerGui.Enabled = position ~= nil
		if position then marker.Position = position end
		markerLabel.Text = label .. "\n▼"
	end
	if guideFolder then
		guideFolder:SetAttribute("TargetMoundId", targetMoundId)
		guideFolder:SetAttribute("TargetKind", label)
	end
end

local function renderTrail()
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local camera = workspace.CurrentCamera
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 or not camera or not targetPosition then
		for _, arrow in arrows do arrow.Gui.Enabled = false end
		if markerGui then markerGui.Enabled = false end
		return
	end
	local origin = root.Position - Vector3.new(0, 0.65, 0)
	local destination = targetPosition + Vector3.new(0, 0.65, 0)
	local delta = destination - origin
	local length = delta.Magnitude
	if length < 0.01 then return end
	local direction = delta.Unit
	local phase = (os.clock() * 2.3) % ARROW_SPACING
	for i, arrow in arrows do
		local distance = 2.5 + (i - 1) * ARROW_SPACING + phase
		local visible = distance < length - 1.5
		if visible then
			local pos = origin + direction * distance
			local screen = camera:WorldToViewportPoint(pos)
			local nextScreen = camera:WorldToViewportPoint(pos + direction)
			visible = screen.Z > 0 and nextScreen.Z > 0
			arrow.Part.Position = pos
			arrow.Label.Rotation = math.deg(math.atan2(nextScreen.Y - screen.Y, nextScreen.X - screen.X))
		end
		arrow.Gui.Enabled = visible
	end
end

local function buildUI()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("TutorialGui")
	if existing then existing:Destroy() end
	local gui = Instance.new("ScreenGui")
	gui.Name = "TutorialGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 14
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	local card = Instance.new("Frame")
	card.Name = "TutorialBanner"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 50)
	card.Size = UDim2.new(0.9, 0, 0, 92)
	card.BackgroundTransparency = 1
	card.BorderSizePixel = 0
	card.Parent = gui
	banner = card
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(520, 92)
	limit.Parent = card
	title = textLabel(card, "Title", 22, Color3.fromRGB(246, 250, 255))
	title.Position = UDim2.fromOffset(0, 0)
	title.Size = UDim2.new(1, 0, 0, 28)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextStrokeColor3 = INK
	title.TextStrokeTransparency = 0
	title.TextScaled = true
	local titleLimit = Instance.new("UITextSizeConstraint")
	titleLimit.MaxTextSize = 22
	titleLimit.Parent = title
	instruction = textLabel(card, "Instruction", 15, Color3.fromRGB(230, 241, 255))
	instruction.Position = UDim2.fromOffset(0, 30)
	instruction.Size = UDim2.new(1, 0, 0, 22)
	instruction.TextXAlignment = Enum.TextXAlignment.Center
	instruction.TextStrokeColor3 = INK
	instruction.TextStrokeTransparency = 0
	instruction.TextScaled = true
	local instructionLimit = Instance.new("UITextSizeConstraint")
	instructionLimit.MaxTextSize = 15
	instructionLimit.Parent = instruction
	action = Instance.new("TextButton")
	action.Name = "ActionButton"
	action.AnchorPoint = Vector2.new(0.5, 0)
	action.Position = UDim2.new(0.5, 0, 0, 60)
	action.Size = UDim2.fromOffset(112, 29)
	action.BackgroundColor3 = BLUE
	action.BorderSizePixel = 0
	action.Font = Enum.Font.GothamBold
	action.TextColor3 = INK
	action.TextSize = 11
	action.Parent = card
	round(action, 7)
	action.Activated:Connect(function()
		if currentStep == 3 then
			if LocalPlayer:GetAttribute("CurrentZone") == "Base" then
				require(script.Parent:WaitForChild("InventoryController")).OpenInventory("Eggs")
			else
				require(script.Parent:WaitForChild("TeleportController")).TeleportToBase()
			end
		elseif currentStep == 4 then
			require(script.Parent:WaitForChild("PetBagController")).Open()
		end
	end)
end

local function applyTutorial(step: any, done: any)
	if type(step) == "number" and step == step then
		local nextStep = math.clamp(math.floor(step), 1, 5)
		if nextStep ~= currentStep then
			targetMoundId = nil
			targetPosition = nil
			completionRequested = false
		end
		currentStep = nextStep
	end
	if type(done) == "boolean" then isDone = done end
	refreshElapsed = 1
	refreshUI()
end

function TutorialController.GetStep(): (number, boolean)
	return currentStep, isDone
end

function TutorialController.Start()
	if started then return end
	started = true
	local legacy = workspace:FindFirstChild("TutorialPointer")
	if legacy then legacy:Destroy() end
	local stale = workspace:FindFirstChild("TutorialGuidance")
	if stale then stale:Destroy() end
	buildUI()
	local function syncAttributes()
		applyTutorial(LocalPlayer:GetAttribute("TutorialStep"), LocalPlayer:GetAttribute("TutorialDone"))
	end
	LocalPlayer:GetAttributeChangedSignal("TutorialStep"):Connect(syncAttributes)
	LocalPlayer:GetAttributeChangedSignal("TutorialDone"):Connect(syncAttributes)
	LocalPlayer:GetAttributeChangedSignal("CurrentZone"):Connect(refreshUI)
	LocalPlayer.CharacterRemoving:Connect(clearGuidance)
	LocalPlayer:GetAttributeChangedSignal("DigMinigameActive"):Connect(function()
		if LocalPlayer:GetAttribute("DigMinigameActive") == true then clearGuidance()
		else refreshElapsed = 1 end
	end)
	Remotes.GetEvent("StateSync").OnClientEvent:Connect(function(snapshot: any)
		if type(snapshot) ~= "table" then return end
		if type(snapshot.EquippedPets) == "table" then hasEquippedPet = #snapshot.EquippedPets > 0 end
		if type(snapshot.Tutorial) == "table" then applyTutorial(snapshot.Tutorial.Step, snapshot.Tutorial.Done) end
	end)
	syncAttributes()
	RunService.RenderStepped:Connect(function(dt)
		if isDone or LocalPlayer:GetAttribute("DigMinigameActive") == true then return end
		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			ensureGuidance()
			refreshElapsed += dt
			if refreshElapsed >= 0.2 then
				refreshElapsed = 0
				refreshTarget(root)
			end
		end
		renderTrail()
	end)
end

return TutorialController
