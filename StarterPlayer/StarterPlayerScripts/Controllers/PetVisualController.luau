--!strict
-- Client-side smooth visual pet followers, hovering formations, attack dashes, and effects (Step 9)
-- PRD: "Visual (client): pet mengikuti pemain dalam Range, bergerak ke gundukan target dengan kecepatan 6 + 2 x Speed studs/detik. Tanpa fisika, tanpa timing."

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local PetsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Pets"))
local RarityConfig = require(Shared:WaitForChild("Config"):WaitForChild("Rarity"))

local LocalPlayer = Players.LocalPlayer

local PetVisualController = {}

type VisualPetState = {
	Guid: string,
	Species: string,
	Variant: Types.PetVariantName,
	Level: number,
	Speed: number,
	MoveSpeed: number,
	Model: Model,
	RootPart: BasePart,
	CurrentPos: Vector3,
	TargetPos: Vector3,
	IsAttacking: boolean,
	AttackTargetPos: Vector3?,
	AttackStartedAt: number,
}

type BasePetVisualState = {
	Guid: string,
	Species: string,
	Variant: Types.PetVariantName,
	Level: number,
	Speed: number,
	MoveSpeed: number,
	Model: Model,
	RootPart: BasePart,
	CurrentPos: Vector3,
	TargetPos: Vector3,
	NextMoveTime: number,
	GroundPart: BasePart?,
}

local SPECIES_EMOJIS: { [string]: string } = {
	Dog = utf8.char(0x1F436),
	Cat = utf8.char(0x1F431),
	Mole = utf8.char(0x1F439),
	Bunny = utf8.char(0x1F430),
	Hamster = utf8.char(0x1F439),
	Chick = utf8.char(0x1F424),
	Fox = utf8.char(0x1F98A),
	Badger = utf8.char(0x1F9A1),
	Hedgehog = utf8.char(0x1F994),
	Ferret = utf8.char(0x1F9A6),
	Raccoon = utf8.char(0x1F99D),
	Turtle = utf8.char(0x1F422),
	Beetle = utf8.char(0x1FAB2),
	Piglet = utf8.char(0x1F437),
	Armadillo = utf8.char(0x1F6E1),
	Pangolin = utf8.char(0x1F98E),
	Boar = utf8.char(0x1F417),
	Owl = utf8.char(0x1F989),
	Chameleon = utf8.char(0x1F98E),
	CrystalFox = utf8.char(0x1F48E),
	MagmaHound = utf8.char(0x1F525),
	EarthGolem = utf8.char(0x1F5FF),
	RuneBear = utf8.char(0x1F43B),
	TerraDragon = utf8.char(0x1F432),
	CelestialGriffin = utf8.char(0x1F985),
}

local FORMATION_OFFSETS = {
	[1] = {
		Vector3.new(2.8, 0.8, 2.2),
	},
	[2] = {
		Vector3.new(-2.8, 0.8, 2.2),
		Vector3.new(2.8, 0.8, 2.2),
	},
	[3] = {
		Vector3.new(-3.0, 0.8, 2.0),
		Vector3.new(3.0, 0.8, 2.0),
		Vector3.new(0, 1.5, 3.2),
	},
}

local petVisualFolder: Folder? = nil
local basePetVisualFolder: Folder? = nil
local activeVisuals: { [string]: VisualPetState } = {}
local activeBaseVisuals: { [string]: BasePetVisualState } = {}
local ownedPets: { [string]: Types.PetInstance } = {}
local equippedPetGuids: { string } = {}
local basePetGuids: { string } = {}
local started = false

local function getRarityColor(rarityName: string): Color3
	local info = (RarityConfig.ById :: any)[rarityName]
	return if info then info.Color else RarityConfig.ById.Common.Color
end

-- Create procedural stylized pet model for local visual display
local function createProceduralPetModel(
	guid: string,
	species: string,
	variant: Types.PetVariantName,
	level: number,
	spawnPos: Vector3
): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "PetVisual_" .. guid

	local root = Instance.new("Part")
	root.Name = "RootPart"
	root.Size = Vector3.new(1.6, 1.6, 1.6)
	root.Position = spawnPos
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.CastShadow = true
	root.Material = Enum.Material.SmoothPlastic

	local speciesCfg = PetsConfig.Species[species]
	local rarityColor = if speciesCfg then getRarityColor(speciesCfg.Rarity) else Color3.fromRGB(220, 220, 220)

	if variant == "Golden" then
		root.Color = Color3.fromRGB(255, 215, 60)
		root.Material = Enum.Material.Neon
	elseif variant == "Shiny" then
		root.Color = Color3.fromRGB(180, 120, 255)
		root.Material = Enum.Material.Neon
	else
		root.Color = rarityColor
	end

	root.Parent = model
	model.PrimaryPart = root

	-- Add inner cute eyes/face mesh or accent
	local faceAccent = Instance.new("Part")
	faceAccent.Name = "FaceAccent"
	faceAccent.Size = Vector3.new(1.2, 0.6, 0.2)
	faceAccent.CFrame = root.CFrame * CFrame.new(0, 0.1, -0.81)
	faceAccent.Color = Color3.fromRGB(28, 32, 42)
	faceAccent.Material = Enum.Material.SmoothPlastic
	faceAccent.Anchored = true
	faceAccent.CanCollide = false
	faceAccent.CanTouch = false
	faceAccent.CanQuery = false
	faceAccent.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = faceAccent
	weld.Parent = root

	-- Variant particle aura
	if variant == "Golden" then
		local attachment = Instance.new("Attachment")
		attachment.Parent = root

		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxassetid://1084991219" -- sparkle/star
		emitter.Rate = 6
		emitter.Lifetime = NumberRange.new(0.6, 1.2)
		emitter.Speed = NumberRange.new(0.5, 1.5)
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Parent = attachment
	elseif variant == "Shiny" then
		local attachment = Instance.new("Attachment")
		attachment.Parent = root

		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxassetid://1084991219"
		emitter.Rate = 9
		emitter.Lifetime = NumberRange.new(0.8, 1.4)
		emitter.Speed = NumberRange.new(0.8, 2.0)
		emitter.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 120, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 220, 255)),
		})
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Parent = attachment
	end

	-- Billboard label
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PetTag"
	billboard.Size = UDim2.fromOffset(130, 48)
	billboard.StudsOffset = Vector3.new(0, 1.8, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 64
	billboard.Parent = root

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 12
	nameLabel.TextColor3 = rarityColor
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.TextStrokeColor3 = Color3.fromRGB(10, 12, 16)

	local emoji = SPECIES_EMOJIS[species] or "PET"
	local variantPrefix = if variant == "Golden" then "[GOLDEN] " elseif variant == "Shiny" then "[SHINY] " else ""
	nameLabel.Text = string.format("%s%s %s", variantPrefix, emoji, if speciesCfg then speciesCfg.DisplayName else species)
	nameLabel.Parent = billboard

	local lvLabel = Instance.new("TextLabel")
	lvLabel.Position = UDim2.new(0, 0, 0.5, 0)
	lvLabel.Size = UDim2.new(1, 0, 0.5, 0)
	lvLabel.BackgroundTransparency = 1
	lvLabel.Font = Enum.Font.GothamMedium
	lvLabel.TextSize = 10
	lvLabel.TextColor3 = Color3.fromRGB(240, 244, 250)
	lvLabel.TextStrokeTransparency = 0.5
	lvLabel.Text = "Lv." .. tostring(level)
	lvLabel.Parent = billboard

	if petVisualFolder then
		model.Parent = petVisualFolder
	else
		model.Parent = workspace
	end

	return model, root
end

-- Synchronize active visual models with equipped pets list
local function syncVisualPets()
	local activeGuids: { [string]: boolean } = {}

	local character = LocalPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local playerPos = if rootPart then rootPart.Position else Vector3.new(0, 5, 0)

	for _, guid in equippedPetGuids do
		activeGuids[guid] = true
		local petData = ownedPets[guid]
		if petData and not activeVisuals[guid] then
			local speciesCfg = PetsConfig.Species[petData.Species]
			local speed = if speciesCfg then speciesCfg.Speed else 2
			local moveSpeed = PetsConfig.BaseMoveSpeedStuds + (PetsConfig.MoveSpeedPerStat * speed)

			local model, root = createProceduralPetModel(
				guid,
				petData.Species,
				petData.Variant,
				petData.Level,
				playerPos + Vector3.new(math.random(-3, 3), 1, math.random(-3, 3))
			)

			activeVisuals[guid] = {
				Guid = guid,
				Species = petData.Species,
				Variant = petData.Variant,
				Level = petData.Level,
				Speed = speed,
				MoveSpeed = moveSpeed,
				Model = model,
				RootPart = root,
				CurrentPos = root.Position,
				TargetPos = root.Position,
				IsAttacking = false,
				AttackTargetPos = nil,
				AttackStartedAt = 0,
			}
		end
	end

	-- Remove unequipped
	for guid, visual in pairs(activeVisuals) do
		if not activeGuids[guid] then
			if visual.Model then
				visual.Model:Destroy()
			end
			activeVisuals[guid] = nil
		end
	end
end

-- Helper: Find assigned base plot ground for local player
local function getLocalPlotGround(): BasePart?
	local assignedPlot = LocalPlayer:GetAttribute("AssignedPlot")
	local basePlots = workspace:FindFirstChild("BasePlots")
	if not basePlots then
		return nil
	end

	if type(assignedPlot) == "string" and #assignedPlot > 0 then
		local plotFolder = basePlots:FindFirstChild(assignedPlot)
		if plotFolder and plotFolder:IsA("Folder") then
			for _, child in ipairs(plotFolder:GetChildren()) do
				if child:IsA("BasePart") and string.find(child.Name, "_Ground$") then
					return child
				end
			end
		end
	end

	-- Fallback: check plots with OwnerUserId == LocalPlayer.UserId
	for _, folder in ipairs(basePlots:GetChildren()) do
		if folder:IsA("Folder") and folder:GetAttribute("OwnerUserId") == LocalPlayer.UserId then
			for _, child in ipairs(folder:GetChildren()) do
				if child:IsA("BasePart") and string.find(child.Name, "_Ground$") then
					return child
				end
			end
		end
	end

	return nil
end

-- Synchronize active base roaming pets
local function syncBasePets()
	local activeGuids: { [string]: boolean } = {}
	local ground = getLocalPlotGround()

	for _, guid in ipairs(basePetGuids) do
		activeGuids[guid] = true
		local petData = ownedPets[guid]
		if petData and not activeBaseVisuals[guid] then
			local speciesCfg = PetsConfig.Species[petData.Species]
			local speed = if speciesCfg then speciesCfg.Speed else 2
			local moveSpeed = PetsConfig.BaseMoveSpeedStuds + (PetsConfig.MoveSpeedPerStat * speed)

			local spawnPos = Vector3.new(0, 5, 0)
			if ground then
				local halfW = math.max(4, (ground.Size.X / 2) - 6)
				local halfD = math.max(4, (ground.Size.Z / 2) - 6)
				local gx = (math.random() - 0.5) * 2 * halfW
				local gz = (math.random() - 0.5) * 2 * halfD
				spawnPos = Vector3.new(ground.Position.X + gx, ground.Position.Y + (ground.Size.Y / 2) + 1.2, ground.Position.Z + gz)
			end

			local model, root = createProceduralPetModel(
				"Base_" .. guid,
				petData.Species,
				petData.Variant,
				petData.Level,
				spawnPos
			)

			if basePetVisualFolder then
				model.Parent = basePetVisualFolder
			end

			activeBaseVisuals[guid] = {
				Guid = guid,
				Species = petData.Species,
				Variant = petData.Variant,
				Level = petData.Level,
				Speed = speed,
				MoveSpeed = moveSpeed,
				Model = model,
				RootPart = root,
				CurrentPos = root.Position,
				TargetPos = root.Position,
				NextMoveTime = os.clock() + math.random(2, 5),
				GroundPart = ground,
			}
		end
	end

	-- Remove unassigned base pets
	for guid, visual in pairs(activeBaseVisuals) do
		if not activeGuids[guid] then
			if visual.Model then
				visual.Model:Destroy()
			end
			activeBaseVisuals[guid] = nil
		end
	end
end

-- Play damage hit effect at mound position
local function spawnHitEffect(pos: Vector3, damage: number)
	local part = Instance.new("Part")
	part.Size = Vector3.new(0.5, 0.5, 0.5)
	part.Position = pos + Vector3.new(0, 1.2, 0)
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(100, 32)
	bb.StudsOffset = Vector3.new(0, 1.5, 0)
	bb.AlwaysOnTop = true
	bb.Parent = part

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextSize = 16
	lbl.TextColor3 = Color3.fromRGB(255, 215, 64)
	lbl.TextStrokeTransparency = 0.2
	lbl.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
	lbl.Text = string.format("-%d", math.floor(damage))
	lbl.Parent = bb

	local tween = TweenService:Create(
		lbl,
		TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	)
	local moveTween = TweenService:Create(
		part,
		TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = part.Position + Vector3.new(0, 2.5, 0) }
	)
	tween:Play()
	moveTween:Play()

	task.delay(0.9, function()
		part:Destroy()
	end)
end

function PetVisualController.ApplySnapshot(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if type(payload.Pets) == "table" then
		ownedPets = payload.Pets
	end
	if type(payload.EquippedPets) == "table" then
		equippedPetGuids = payload.EquippedPets
	end
	if type(payload.BasePets) == "table" then
		basePetGuids = payload.BasePets
	end

	syncVisualPets()
	syncBasePets()
end

function PetVisualController.Start()
	if started then
		return
	end
	started = true

	local folder = workspace:FindFirstChild("ClientPetVisuals")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ClientPetVisuals"
		folder.Parent = workspace
	end
	petVisualFolder = folder :: Folder

	local baseFolder = workspace:FindFirstChild("ClientBasePetVisuals")
	if not baseFolder then
		baseFolder = Instance.new("Folder")
		baseFolder.Name = "ClientBasePetVisuals"
		baseFolder.Parent = workspace
	end
	basePetVisualFolder = baseFolder :: Folder

	-- Listen for StateSync
	Remotes.GetEvent("StateSync").OnClientEvent:Connect(function(payload: any)
		PetVisualController.ApplySnapshot(payload)
	end)

	-- Listen for PetAttackVisual
	Remotes.GetEvent("PetAttackVisual").OnClientEvent:Connect(function(petGuid: string, moundId: string, damage: number)
		local visual = activeVisuals[petGuid]
		if not visual then
			return
		end

		local activeMoundsFolder = workspace:FindFirstChild("ActiveMounds")
		local moundModel = activeMoundsFolder and activeMoundsFolder:FindFirstChild(moundId)
		local moundPos = if moundModel and moundModel:IsA("Model") and moundModel.PrimaryPart
			then moundModel.PrimaryPart.Position
			else nil

		if moundPos then
			visual.IsAttacking = true
			visual.AttackTargetPos = moundPos + Vector3.new(0, 0.8, 0)
			visual.AttackStartedAt = os.clock()
			spawnHitEffect(moundPos, damage)

			task.delay(0.65, function()
				if visual and visual.IsAttacking then
					visual.IsAttacking = false
					visual.AttackTargetPos = nil
				end
			end)
		end
	end)

	-- Frame movement loop (RenderStepped)
	RunService.RenderStepped:Connect(function(dt: number)
		local character = LocalPlayer.Character
		if not character then
			return
		end

		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then
			return
		end

		local charCFrame = rootPart.CFrame
		local totalEquipped = math.clamp(#equippedPetGuids, 1, 3)
		local offsets = FORMATION_OFFSETS[totalEquipped] or FORMATION_OFFSETS[1]

		local now = os.clock()

		for idx, guid in ipairs(equippedPetGuids) do
			local visual = activeVisuals[guid]
			if visual and visual.RootPart and visual.RootPart.Parent then
				local targetPos: Vector3
				local targetLook: Vector3

				if visual.IsAttacking and visual.AttackTargetPos then
					-- Dash towards mound attack target
					targetPos = visual.AttackTargetPos
					targetLook = (targetPos - visual.CurrentPos).Unit
				else
					-- Formation following avatar
					local offset = offsets[idx] or Vector3.new(2.5, 0.8, 2.0)
					local hoverY = math.sin((now * 3.2) + (idx * 1.5)) * 0.35
					local formationPos = (charCFrame * CFrame.new(offset)).Position + Vector3.new(0, hoverY, 0)
					targetPos = formationPos
					targetLook = charCFrame.LookVector
				end

				-- Speed: 6 + 2 x Speed studs/sec
				local maxMove = visual.MoveSpeed * dt
				local diff = targetPos - visual.CurrentPos
				local dist = diff.Magnitude

				local nextPos = if dist <= maxMove then targetPos else visual.CurrentPos + (diff.Unit * maxMove)
				visual.CurrentPos = nextPos

				-- Smooth orientation
				local lookDir = if dist > 0.05 then (targetPos - visual.CurrentPos).Unit else targetLook
				if lookDir.Magnitude > 0.01 then
					local cf = CFrame.lookAt(nextPos, nextPos + lookDir)
					visual.RootPart.CFrame = cf
					local face = visual.Model:FindFirstChild("FaceAccent") :: BasePart?
					if face then
						face.CFrame = cf * CFrame.new(0, 0.1, -0.81)
					end
				else
					visual.RootPart.Position = nextPos
				end
			end
		end

		-- Base pets roaming in plot
		for _, visual in pairs(activeBaseVisuals) do
			if visual and visual.RootPart and visual.RootPart.Parent then
				local ground = visual.GroundPart or getLocalPlotGround()
				visual.GroundPart = ground

				if ground and (now >= visual.NextMoveTime or (visual.TargetPos - visual.CurrentPos).Magnitude < 0.6) then
					local halfW = math.max(4, (ground.Size.X / 2) - 6)
					local halfD = math.max(4, (ground.Size.Z / 2) - 6)
					local gx = (math.random() - 0.5) * 2 * halfW
					local gz = (math.random() - 0.5) * 2 * halfD
					local targetY = ground.Position.Y + (ground.Size.Y / 2) + 1.2
					visual.TargetPos = Vector3.new(ground.Position.X + gx, targetY, ground.Position.Z + gz)
					visual.NextMoveTime = now + math.random(3, 7)
				end

				local moveDiff = visual.TargetPos - visual.CurrentPos
				local dist = moveDiff.Magnitude
				local maxStep = visual.MoveSpeed * dt * 0.7
				local nextPos = if dist <= maxStep then visual.TargetPos else visual.CurrentPos + (moveDiff.Unit * maxStep)
				local hoverBob = math.sin((now * 3.0) + (string.byte(visual.Guid, #visual.Guid) or 1)) * 0.15
				local finalPos = nextPos + Vector3.new(0, hoverBob, 0)
				visual.CurrentPos = nextPos

				if dist > 0.1 then
					local lookDir = moveDiff.Unit
					local cf = CFrame.lookAt(finalPos, finalPos + lookDir)
					visual.RootPart.CFrame = cf
					local face = visual.Model:FindFirstChild("FaceAccent") :: BasePart?
					if face then
						face.CFrame = cf * CFrame.new(0, 0.1, -0.81)
					end
				else
					visual.RootPart.Position = finalPos
				end
			end
		end
	end)
end

return PetVisualController
