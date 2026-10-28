--!strict
-- Client-side visual controller for personal mounds, click selection, and HP billboards (Step 3 & Step 4)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local AssetIds = require(Shared:WaitForChild("AssetIds"))
local MoundsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Mounds"))

local RAYCAST_DISTANCE = 500
local LocalPlayer = Players.LocalPlayer

export type MoundVisualPayload = {
	Id: string,
	Size: string,
	DisplayName: string?,
	Position: Vector3,
	HP: number,
	MaxHP: number,
	Scale: Vector3?,
	IsShared: boolean?,
}

export type MoundClickedCallback = (moundId: string, moundSize: string, moundPosition: Vector3) -> ()

type MoundVisualEntry = {
	Id: string,
	Size: string,
	Model: Model,
	PrimaryPart: Part,
	FillFrame: Frame,
	HPLabel: TextLabel,
	Highlight: Highlight,
	MaxHP: number,
	IsHovered: boolean,
}

local MoundVisuals = {}

local activeVisuals: { [string]: MoundVisualEntry } = {}
local clickCallbacks: { MoundClickedCallback } = {}
local selectedMoundId: string? = nil
local hoveredEntry: MoundVisualEntry? = nil
local containerFolder: Folder? = nil
local started = false

local function getContainerFolder(): Folder
	if containerFolder and containerFolder.Parent == workspace then
		return containerFolder
	end
	local existing = workspace:FindFirstChild("ClientMounds")
	if existing and existing:IsA("Folder") then
		containerFolder = existing
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "ClientMounds"
	folder.Parent = workspace
	containerFolder = folder
	return folder
end

local function refreshEntryHighlight(entry: MoundVisualEntry)
	local isSelected = (selectedMoundId == entry.Id)
	entry.Highlight.Enabled = isSelected or entry.IsHovered
	if isSelected then
		entry.Highlight.OutlineColor = Color3.fromRGB(255, 215, 65)
		entry.Highlight.FillColor = Color3.fromRGB(255, 215, 65)
		entry.Highlight.FillTransparency = 0.82
	else
		entry.Highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
		entry.Highlight.FillColor = Color3.fromRGB(255, 255, 255)
		entry.Highlight.FillTransparency = 0.88
	end
end

function MoundVisuals.SetSelectedMound(moundId: string?)
	selectedMoundId = moundId
	for _, entry in activeVisuals do
		refreshEntryHighlight(entry)
	end
end

function MoundVisuals.OnMoundClicked(callback: MoundClickedCallback)
	table.insert(clickCallbacks, callback)
end

function MoundVisuals.GetMoundPosition(moundId: string): (Vector3?, string?, boolean?)
	local entry = activeVisuals[moundId]
	if not entry then
		return nil, nil, false
	end
	local isShared = entry.Model:GetAttribute("IsShared") == true or entry.Size == "Shared"
	return entry.PrimaryPart.Position, entry.Size, isShared
end

function MoundVisuals.IsSharedMound(moundId: string): boolean
	local entry = activeVisuals[moundId]
	return entry ~= nil and (entry.Model:GetAttribute("IsShared") == true or entry.Size == "Shared")
end

local function createBillboard(
	parentPart: Part,
	titleText: string,
	hp: number,
	maxHp: number,
	isShared: boolean?
): (Frame, TextLabel)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "MoundBillboard"
	billboard.Size = if isShared then UDim2.fromOffset(175, 54) else UDim2.fromOffset(145, 50)
	billboard.StudsOffset = Vector3.new(0, (parentPart.Size.Y * 0.5) + 2.3, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = if isShared then 250 else 90
	billboard.Parent = parentPart

	local bg = Instance.new("Frame")
	bg.Name = "Container"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	bg.BackgroundTransparency = 0.2
	bg.BorderSizePixel = 0
	bg.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = bg

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -8, 0, 18)
	title.Position = UDim2.fromOffset(4, 3)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.TextColor3 = if isShared then Color3.fromRGB(255, 220, 80) else Color3.fromRGB(255, 240, 200)
	title.Text = if isShared then "[RARE] " .. titleText else titleText
	title.Parent = bg

	local barBg = Instance.new("Frame")
	barBg.Name = "BarBackground"
	barBg.Size = UDim2.new(1, -12, 0, 18)
	barBg.Position = UDim2.fromOffset(6, 25)
	barBg.BackgroundColor3 = Color3.fromRGB(50, 50, 58)
	barBg.BorderSizePixel = 0
	barBg.Parent = bg

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 6)
	barCorner.Parent = barBg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	local ratio = if maxHp > 0 then math.clamp(hp / maxHp, 0, 1) else 0
	fill.Size = UDim2.fromScale(ratio, 1)
	fill.BackgroundColor3 = if isShared then Color3.fromRGB(240, 180, 50) else Color3.fromRGB(95, 210, 105)
	fill.BorderSizePixel = 0
	fill.Parent = barBg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = fill

	local hpLabel = Instance.new("TextLabel")
	hpLabel.Name = "HPLabel"
	hpLabel.Size = UDim2.fromScale(1, 1)
	hpLabel.BackgroundTransparency = 1
	hpLabel.Font = Enum.Font.GothamBold
	hpLabel.TextSize = 11
	hpLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	hpLabel.TextStrokeTransparency = 0.5
	hpLabel.Text = string.format("%d / %d HP", math.ceil(hp), math.ceil(maxHp))
	hpLabel.ZIndex = 2
	hpLabel.Parent = barBg

	return fill, hpLabel
end

function MoundVisuals.SpawnMound(data: MoundVisualPayload)
	MoundVisuals.RemoveMound(data.Id)

	local sizeConfig = (MoundsConfig.Sizes :: any)[data.Size] or MoundsConfig.Sizes.Small
	local scale: Vector3 = data.Scale or sizeConfig.Scale
	local displayName: string = data.DisplayName or sizeConfig.DisplayName

	local model = Instance.new("Model")
	model.Name = data.Id
	model:SetAttribute("MoundId", data.Id)
	model:SetAttribute("MoundSize", data.Size)
	model:SetAttribute("IsShared", data.IsShared == true)

	local basePart = Instance.new("Part")
	basePart.Name = "MoundPart"
	basePart.Anchored = true
	basePart.CanCollide = true
	basePart.Material = Enum.Material.Ground
	basePart.Color = if data.IsShared then AssetIds.Colors.MoundShared else AssetIds.Colors.MoundPersonal
	basePart.Size = scale
	basePart.Position = data.Position + Vector3.new(0, scale.Y * 0.4, 0)
	basePart:SetAttribute("MoundId", data.Id)
	basePart.Parent = model

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = basePart

	local highlight = Instance.new("Highlight")
	highlight.Name = "SelectionHighlight"
	highlight.Adornee = model
	highlight.OutlineTransparency = 0.1
	highlight.FillTransparency = 0.88
	highlight.Enabled = false
	highlight.Parent = model

	-- NOTE: Roblox never forwards clicks to ClickDetectors while a Tool is held, so mound clicks are handled
	-- by MoundVisuals.Start() via a character-ignoring cursor raycast (works with and without the shovel held).
	model.PrimaryPart = basePart
	local fillFrame, hpLabel = createBillboard(basePart, displayName, data.HP, data.MaxHP, data.IsShared == true)
	model.Parent = getContainerFolder()

	local entry: MoundVisualEntry = {
		Id = data.Id,
		Size = data.Size,
		Model = model,
		PrimaryPart = basePart,
		FillFrame = fillFrame,
		HPLabel = hpLabel,
		Highlight = highlight,
		MaxHP = data.MaxHP,
		IsHovered = false,
	}
	activeVisuals[data.Id] = entry
	refreshEntryHighlight(entry)
end

-- Raycasts from a screen position (same coordinate space as InputObject.Position / Mouse.X,Y) and returns the
-- mound entry under the cursor. The local character (and its held Tool) plus pet visuals are ignored so the
-- equipped shovel can never block or swallow the click.
local function getMoundEntryAtScreenPoint(screenX: number, screenY: number): MoundVisualEntry?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ignore: { Instance } = {}
	local character = Players.LocalPlayer.Character
	if character then
		table.insert(ignore, character)
	end
	for _, folderName in { "ClientPetVisuals", "ClientBasePetVisuals" } do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			table.insert(ignore, folder)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore

	local ray = camera:ScreenPointToRay(screenX, screenY)
	local result = workspace:Raycast(ray.Origin, ray.Direction * RAYCAST_DISTANCE, params)
	if not result then
		return nil
	end
	local moundId = result.Instance:GetAttribute("MoundId")
	if not moundId and result.Instance.Parent then
		moundId = result.Instance.Parent:GetAttribute("MoundId")
	end
	if type(moundId) ~= "string" then
		return nil
	end
	return activeVisuals[moundId]
end

function MoundVisuals.GetHoveredMound(): (string?, string?, Vector3?)
	if hoveredEntry and activeVisuals[hoveredEntry.Id] == hoveredEntry then
		return hoveredEntry.Id, hoveredEntry.Size, hoveredEntry.PrimaryPart.Position
	end
	return nil, nil, nil
end

local function setHoveredEntry(newEntry: MoundVisualEntry?)
	if hoveredEntry == newEntry then
		return
	end
	if hoveredEntry then
		hoveredEntry.IsHovered = false
		if activeVisuals[hoveredEntry.Id] == hoveredEntry then
			refreshEntryHighlight(hoveredEntry)
		end
	end
	hoveredEntry = newEntry
	if hoveredEntry then
		hoveredEntry.IsHovered = true
		refreshEntryHighlight(hoveredEntry)
	end
end

function MoundVisuals.UpdateMoundHP(moundId: string, currentHp: number, maxHp: number?)
	local entry = activeVisuals[moundId]
	if not entry then
		return
	end
	local effectiveMax = maxHp or entry.MaxHP
	entry.MaxHP = effectiveMax
	local ratio = if effectiveMax > 0 then math.clamp(currentHp / effectiveMax, 0, 1) else 0
	entry.FillFrame.Size = UDim2.fromScale(ratio, 1)
	entry.HPLabel.Text = string.format("%d / %d HP", math.max(0, math.ceil(currentHp)), math.ceil(effectiveMax))
end

function MoundVisuals.RemoveMound(moundId: string)
	local entry = activeVisuals[moundId]
	if not entry then
		return
	end
	activeVisuals[moundId] = nil
	if selectedMoundId == moundId then
		selectedMoundId = nil
	end
	entry.Model:Destroy()
end

function MoundVisuals.Start()
	if started then
		return
	end
	started = true

	getContainerFolder()

	Remotes.GetEvent("MoundSpawned").OnClientEvent:Connect(function(payload: any)
		if type(payload) == "table" and type(payload.Id) == "string" then
			MoundVisuals.SpawnMound(payload :: MoundVisualPayload)
		end
	end)

	Remotes.GetEvent("MoundUpdated").OnClientEvent:Connect(function(moundId: string, currentHp: number, maxHp: number)
		if type(moundId) == "string" and type(currentHp) == "number" then
			MoundVisuals.UpdateMoundHP(moundId, currentHp, maxHp)
		end
	end)

	Remotes.GetEvent("MoundDespawned").OnClientEvent:Connect(function(moundId: string, _reason: string)
		if type(moundId) == "string" then
			MoundVisuals.RemoveMound(moundId)
		end
	end)

	-- Raycast click detection that works seamlessly whether a shovel tool is held or not
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local entry = getMoundEntryAtScreenPoint(input.Position.X, input.Position.Y)
			if entry then
				for _, cb in clickCallbacks do
					task.spawn(cb, entry.Id, entry.Size, entry.PrimaryPart.Position)
				end
			end
		end
	end)

	-- Hover detection for desktop cursors
	UserInputService.InputChanged:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			setHoveredEntry(nil)
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			local entry = getMoundEntryAtScreenPoint(input.Position.X, input.Position.Y)
			setHoveredEntry(entry)
		end
	end)
end

return MoundVisuals
