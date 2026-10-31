--!strict
-- Client-side visual controller for server-wide mounds, click selection, and HP billboards.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local MoundsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Mounds"))
local MoundAssets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Mounds")

local RAYCAST_DISTANCE = 500
local LocalPlayer = Players.LocalPlayer
local MOUND_TEMPLATE_NAMES: { [string]: string } = {
	Small = "SmallMound",
	Medium = "MediumMound",
	Large = "LargeMound",
	Shared = "LargeMound",
}

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
	Billboard: BillboardGui,
	TrailFrame: Frame,
	FillTween: Tween?,
	TrailTween: Tween?,
	HitVersion: number,
	LastHP: number,
	Highlight: Highlight,
	MaxHP: number,
	IsHovered: boolean,
}

local MoundVisuals = {}

local activeVisuals: { [string]: MoundVisualEntry } = {}
local despawnedMoundIds: { [string]: boolean } = {}
local clickCallbacks: { MoundClickedCallback } = {}
local selectedMoundId: string? = nil
local diggingMoundId: string? = nil
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

-- Selection/hover alone never reveals health. Only a confirmed dig session does.
function MoundVisuals.SetDiggingMound(moundId: string?)
	diggingMoundId = moundId
	for id, entry in activeVisuals do
		local enabled = id == moundId
		if not enabled and entry.Billboard.Enabled then
			entry.HitVersion += 1
			if entry.FillTween then entry.FillTween:Cancel() end
			if entry.TrailTween then entry.TrailTween:Cancel() end
			local ratio = if entry.MaxHP > 0 then math.clamp(entry.LastHP / entry.MaxHP, 0, 1) else 0
			entry.FillFrame.Size = UDim2.fromScale(ratio, 1)
			entry.TrailFrame.Size = UDim2.fromScale(ratio, 1)
		end
		if enabled and not entry.Billboard.Enabled then
			local scale = entry.Billboard.Container:FindFirstChildOfClass("UIScale")
			if scale then
				scale.Scale = 0.92
				TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			end
		end
		entry.Billboard.Enabled = enabled
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

-- Use the live dig registry, never map decoration. Keep a valid target locked.
function MoundVisuals.GetTutorialMound(position: Vector3, preferredId: string?): (string?, Model?, Vector3?)
	local function isEligible(entry: MoundVisualEntry): boolean
		return entry.Size == "Small" and entry.LastHP > 0
			and entry.Model:GetAttribute("IsShared") ~= true
			and entry.Model:IsDescendantOf(workspace)
			and entry.PrimaryPart.Parent == entry.Model
	end
	local preferred = if preferredId then activeVisuals[preferredId] else nil
	if preferred and isEligible(preferred) then
		return preferred.Id, preferred.Model, preferred.PrimaryPart.Position
	end
	local nearest: MoundVisualEntry? = nil
	local distance = math.huge
	for _, entry in activeVisuals do
		if isEligible(entry) then
			local candidateDistance = (entry.PrimaryPart.Position - position).Magnitude
			if candidateDistance < distance then
				nearest, distance = entry, candidateDistance
			end
		end
	end
	if nearest then return nearest.Id, nearest.Model, nearest.PrimaryPart.Position end
	return nil, nil, nil
end

local function createBillboard(
	parentPart: Part,
	titleText: string,
	hp: number,
	maxHp: number,
	isShared: boolean?
): (Frame, TextLabel, BillboardGui, Frame)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "MoundBillboard"
	billboard.Enabled = false
	billboard.Size = UDim2.fromOffset(188, 62)
	billboard.StudsOffset = Vector3.new(0, (parentPart.Size.Y * 0.5) + 2.3, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = if isShared then 110 else 70
	billboard.Parent = parentPart

	local bg = Instance.new("Frame")
	bg.Name = "Container"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundTransparency = 1
	bg.BorderSizePixel = 0
	bg.Parent = billboard

	Instance.new("UIScale").Parent = bg
	local heart = Instance.new("TextLabel")
	heart.Name = "Heart"
	heart.Position = UDim2.fromOffset(8, 5)
	heart.Size = UDim2.fromOffset(22, 22)
	heart.BackgroundTransparency = 1
	heart.Font = Enum.Font.GothamBlack
	heart.Text = "♥"
	heart.TextSize = 20
	heart.TextColor3 = Color3.fromRGB(255, 121, 114)
	heart.Parent = bg

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -44, 0, 22)
	title.Position = UDim2.fromOffset(34, 5)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextSize = 14
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.TextColor3 = if isShared then Color3.fromRGB(255, 220, 80) else Color3.fromRGB(255, 240, 200)
	title.TextStrokeColor3 = Color3.fromRGB(16, 28, 31)
	title.TextStrokeTransparency = 0.1
	title.Text = titleText
	title.Parent = bg

	local barBg = Instance.new("Frame")
	barBg.Name = "BarBackground"
	barBg.Size = UDim2.new(1, -16, 0, 21)
	barBg.Position = UDim2.fromOffset(8, 33)
	barBg.BackgroundColor3 = Color3.fromRGB(12, 29, 33)
	barBg.BorderSizePixel = 0
	barBg.Parent = bg

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 6)
	barCorner.Parent = barBg
	local trail = Instance.new("Frame")
	trail.Name = "DamageTrail"
	trail.Size = UDim2.fromScale(if maxHp > 0 then math.clamp(hp / maxHp, 0, 1) else 0, 1)
	trail.BackgroundColor3 = Color3.fromRGB(255, 207, 110)
	trail.BorderSizePixel = 0
	trail.ZIndex = 2
	trail.Parent = barBg
	local trailCorner = Instance.new("UICorner")
	trailCorner.CornerRadius = UDim.new(0, 6)
	trailCorner.Parent = trail

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	local ratio = if maxHp > 0 then math.clamp(hp / maxHp, 0, 1) else 0
	fill.Size = UDim2.fromScale(ratio, 1)
	fill.BackgroundColor3 = Color3.fromRGB(66, 199, 151)
	fill.ZIndex = 3
	fill.BorderSizePixel = 0
	fill.Parent = barBg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = fill

	local hpLabel = Instance.new("TextLabel")
	hpLabel.Name = "HPLabel"
	hpLabel.Size = UDim2.fromScale(1, 1)
	hpLabel.BackgroundTransparency = 1
	hpLabel.Font = Enum.Font.FredokaOne
	hpLabel.TextSize = 13
	hpLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	hpLabel.TextStrokeTransparency = 0.15
	hpLabel.TextStrokeColor3 = Color3.fromRGB(16, 44, 39)
	hpLabel.Text = string.format("%d / %d HP", math.ceil(hp), math.ceil(maxHp))
	hpLabel.ZIndex = 4
	hpLabel.Parent = barBg

	return fill, hpLabel, billboard, trail
end

local function getVisualBounds(model: Model): (Vector3?, Vector3?)
	local minimum = Vector3.new(math.huge, math.huge, math.huge)
	local maximum = Vector3.new(-math.huge, -math.huge, -math.huge)
	local found = false
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and not string.find(string.lower(descendant.Name), "particles", 1, true) then
			found = true
			local half = descendant.Size * 0.5
			for _, xSign in { -1, 1 } do
				for _, ySign in { -1, 1 } do
					for _, zSign in { -1, 1 } do
						local point = descendant.CFrame:PointToWorldSpace(Vector3.new(
							half.X * xSign,
							half.Y * ySign,
							half.Z * zSign
						))
						minimum = Vector3.new(
							math.min(minimum.X, point.X),
							math.min(minimum.Y, point.Y),
							math.min(minimum.Z, point.Z)
						)
						maximum = Vector3.new(
							math.max(maximum.X, point.X),
							math.max(maximum.Y, point.Y),
							math.max(maximum.Z, point.Z)
						)
					end
				end
			end
		end
	end
	if not found then return nil, nil end
	return minimum, maximum
end

local function cloneMoundVisual(sizeName: string, targetScale: Vector3, groundPosition: Vector3): Model
	local templateName = MOUND_TEMPLATE_NAMES[sizeName] or MOUND_TEMPLATE_NAMES.Small
	local template = MoundAssets:FindFirstChild(templateName)
	assert(template and template:IsA("Model"), string.format("Missing mound template %s", templateName))
	local visual = template:Clone()
	visual.Name = "MoundVisual"

	local sourceDiameter = template:GetAttribute("SourceDiameter")
	local targetDiameter = math.max(targetScale.X, targetScale.Z)
	if type(sourceDiameter) == "number" and sourceDiameter > 0 then
		visual:ScaleTo(targetDiameter / sourceDiameter)
	end
	local minimum, maximum = getVisualBounds(visual)
	if minimum and maximum then
		local groundCenter = Vector3.new(
			(minimum.X + maximum.X) * 0.5,
			minimum.Y,
			(minimum.Z + maximum.Z) * 0.5
		)
		visual:PivotTo(CFrame.new(groundPosition - groundCenter) * visual:GetPivot())
	end
	local dustHost: BasePart? = nil
	for _, descendant in visual:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			local lowerName = string.lower(descendant.Name)
			if descendant:IsA("MeshPart") then
				descendant.DoubleSided = true
				if string.find(lowerName, "dirt", 1, true) then
					-- The baked FBX atlases contain opaque black gutters, so Roblox materials give a clean result.
					descendant.TextureID = ""
					descendant.Color = Color3.fromRGB(137, 94, 62)
					descendant.Material = Enum.Material.Ground
				elseif string.find(lowerName, "rocks", 1, true) then
					descendant.TextureID = ""
					descendant.Color = Color3.fromRGB(111, 100, 87)
					descendant.Material = Enum.Material.Rock
				end
			end
			if string.find(lowerName, "particles", 1, true) then
				-- FBX particle cards do not retain their alpha texture in Studio and render as dark polygons.
				descendant.Transparency = 1
			elseif string.find(lowerName, "dirt", 1, true) then
				dustHost = descendant
			end
		end
	end
	if dustHost then
		local particleScale = math.clamp(targetDiameter / 4, 1, 3)
		local dust = Instance.new("ParticleEmitter")
		dust.Name = "MoundDust"
		dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
		dust.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 218, 145)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(132, 89, 55)),
		})
		dust.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.28),
			NumberSequenceKeypoint.new(0.72, 0.5),
			NumberSequenceKeypoint.new(1, 1),
		})
		dust.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.11 * particleScale),
			NumberSequenceKeypoint.new(0.55, 0.19 * particleScale),
			NumberSequenceKeypoint.new(1, 0.08 * particleScale),
		})
		dust.Lifetime = NumberRange.new(0.75, 1.25)
		dust.Rate = 0.65 * particleScale
		dust.Speed = NumberRange.new(0.35 * particleScale, 0.75 * particleScale)
		dust.Acceleration = Vector3.new(0, 0.75, 0)
		dust.Drag = 1.5
		dust.SpreadAngle = Vector2.new(55, 55)
		dust.Rotation = NumberRange.new(0, 360)
		dust.RotSpeed = NumberRange.new(-45, 45)
		dust.EmissionDirection = Enum.NormalId.Top
		dust.LightInfluence = 0.55
		dust.Parent = dustHost
	end
	return visual
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
	basePart.CanTouch = false
	basePart.CanQuery = true
	basePart.Transparency = 1
	basePart.Shape = Enum.PartType.Ball
	basePart.Size = Vector3.new(scale.X * 0.9, math.max(1, scale.Y * 0.65), scale.Z * 0.9)
	basePart.Position = data.Position + Vector3.new(0, basePart.Size.Y * 0.42, 0)
	basePart:SetAttribute("MoundId", data.Id)
	basePart.Parent = model

	local visual = cloneMoundVisual(data.Size, scale, data.Position)
	visual.Parent = model

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
	local fillFrame, hpLabel, billboard, trail = createBillboard(basePart, displayName, data.HP, data.MaxHP, data.IsShared == true)
	model.Parent = getContainerFolder()

	local entry: MoundVisualEntry = {
		Id = data.Id,
		Size = data.Size,
		Model = model,
		PrimaryPart = basePart,
		FillFrame = fillFrame,
		HPLabel = hpLabel,
		Billboard = billboard,
		TrailFrame = trail,
		FillTween = nil,
		TrailTween = nil,
		HitVersion = 0,
		LastHP = data.HP,
		Highlight = highlight,
		MaxHP = data.MaxHP,
		IsHovered = false,
	}
	activeVisuals[data.Id] = entry
	billboard.Enabled = diggingMoundId == data.Id
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
	entry.HitVersion += 1
	local version = entry.HitVersion
	if entry.FillTween then entry.FillTween:Cancel() end
	if entry.TrailTween then entry.TrailTween:Cancel() end
	local color = if ratio <= 0.25 then Color3.fromRGB(242, 104, 91)
		elseif ratio <= 0.5 then Color3.fromRGB(243, 187, 69)
		else Color3.fromRGB(66, 199, 151)
	if entry.Billboard.Enabled then
		entry.FillTween = TweenService:Create(entry.FillFrame, TweenInfo.new(0.16, Enum.EasingStyle.Quad), {
			Size = UDim2.fromScale(ratio, 1), BackgroundColor3 = color,
		})
		entry.FillTween:Play()
		if currentHp < entry.LastHP then
			task.delay(0.18, function()
				if activeVisuals[moundId] ~= entry or entry.HitVersion ~= version or not entry.Billboard.Enabled then return end
				entry.TrailTween = TweenService:Create(entry.TrailFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(ratio, 1) })
				entry.TrailTween:Play()
			end)
		else
			entry.TrailFrame.Size = UDim2.fromScale(ratio, 1)
		end
	else
		entry.FillFrame.Size = UDim2.fromScale(ratio, 1)
		entry.FillFrame.BackgroundColor3 = color
		entry.TrailFrame.Size = UDim2.fromScale(ratio, 1)
	end
	entry.LastHP = currentHp
	entry.HPLabel.Text = string.format("%d / %d HP", math.max(0, math.ceil(currentHp)), math.ceil(effectiveMax))
end

function MoundVisuals.RemoveMound(moundId: string)
	local entry = activeVisuals[moundId]
	if not entry then
		return
	end
	activeVisuals[moundId] = nil
	if entry.FillTween then entry.FillTween:Cancel() end
	if entry.TrailTween then entry.TrailTween:Cancel() end
	if diggingMoundId == moundId then diggingMoundId = nil end
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
		if type(payload) == "table" and type(payload.Id) == "string" and not despawnedMoundIds[payload.Id] then
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
			despawnedMoundIds[moundId] = true
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
