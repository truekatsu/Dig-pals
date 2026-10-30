--!strict
-- Client-side smooth visual pet followers, formations, attack dashes, effects, and base roamers (Multi-Player)
-- Displays equipped and base pets for both the local player and all other players in the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local PetsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Pets"))
local PetModelBuilder = require(Shared:WaitForChild("PetModelBuilder"))

local LocalPlayer = Players.LocalPlayer

local PetVisualController = {}

export type PetSummary = {
	Guid: string,
	Species: string,
	Variant: Types.PetVariantName,
	Level: number,
}

type VisualPetState = {
	Guid: string,
	OwnerUserId: number,
	OwnerPlayer: Player,
	Species: string,
	Variant: Types.PetVariantName,
	Level: number,
	Speed: number,
	MoveSpeed: number,
	GroundOffset: number,
	Model: Model,
	RootPart: BasePart,
	CurrentPos: Vector3,
	TargetPos: Vector3,
	IsAttacking: boolean,
	AttackTargetPos: Vector3?,
	AttackStartedAt: number,
	AnimTracks: { [string]: AnimationTrack }?,
	CurrentAnim: string?,
}

type BasePetVisualState = {
	Guid: string,
	OwnerUserId: number,
	OwnerPlayer: Player,
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
	AnimTracks: { [string]: AnimationTrack }?,
	CurrentAnim: string?,
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

-- Visual state tables (keyed by petGuid)
local activeVisuals: { [string]: VisualPetState } = {}
local activeBaseVisuals: { [string]: BasePetVisualState } = {}

-- Per-player tracking of active GUIDs
local playerEquippedGuids: { [number]: { string } } = {}
local playerBaseGuids: { [number]: { string } } = {}

-- Local player cache from StateSync
local localOwnedPets: { [string]: Types.PetInstance } = {}
local localEquippedGuids: { string } = {}
local localBaseGuids: { string } = {}

local started = false

-- Safe JSON parsing for public pet attributes
local function parsePublicPetsAttribute(player: Player, attributeName: string): { PetSummary }
	local raw = player:GetAttribute(attributeName)
	if type(raw) ~= "string" or #raw == 0 then
		return {}
	end
	local ok, list = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if ok and type(list) == "table" then
		return list
	end
	return {}
end

local function getPlayerEquippedSummaries(player: Player): { PetSummary }
	if player == LocalPlayer and #localEquippedGuids > 0 then
		local list: { PetSummary } = {}
		for _, guid in ipairs(localEquippedGuids) do
			local p = localOwnedPets[guid]
			if p then
				table.insert(list, {
					Guid = guid,
					Species = p.Species,
					Variant = p.Variant or "Normal",
					Level = p.Level or 1,
				})
			end
		end
		if #list > 0 then
			return list
		end
	end
	return parsePublicPetsAttribute(player, "PublicEquippedPets")
end

local function getPlayerBaseSummaries(player: Player): { PetSummary }
	if player == LocalPlayer and #localBaseGuids > 0 then
		local list: { PetSummary } = {}
		for _, guid in ipairs(localBaseGuids) do
			local p = localOwnedPets[guid]
			if p then
				table.insert(list, {
					Guid = guid,
					Species = p.Species,
					Variant = p.Variant or "Normal",
					Level = p.Level or 1,
				})
			end
		end
		if #list > 0 then
			return list
		end
	end
	return parsePublicPetsAttribute(player, "PublicBasePets")
end

local function getPlayerPlotGround(player: Player): BasePart?
	local assignedPlot = player:GetAttribute("AssignedPlot")
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

	-- Fallback: check plots with OwnerUserId == player.UserId
	for _, folder in ipairs(basePlots:GetChildren()) do
		if folder:IsA("Folder") and folder:GetAttribute("OwnerUserId") == player.UserId then
			for _, child in ipairs(folder:GetChildren()) do
				if child:IsA("BasePart") and string.find(child.Name, "_Ground$") then
					return child
				end
			end
		end
	end

	return nil
end

local function getOwnerDisplayName(player: Player): string?
	if player == LocalPlayer then
		return nil
	end
	return player.DisplayName or player.Name
end

local function setupPetAnimations(model: Model): { [string]: AnimationTrack }?
	local animController = model:FindFirstChildOfClass("AnimationController")
	local animator = animController and animController:FindFirstChildOfClass("Animator")
	local animsFolder = model:FindFirstChild("Animations")
	if not (animator and animsFolder) then
		return nil
	end

	local tracks: { [string]: AnimationTrack } = {}
	for _, anim in ipairs(animsFolder:GetChildren()) do
		if anim:IsA("Animation") and #anim.AnimationId > 0 then
			local ok, track = pcall(function()
				return animator:LoadAnimation(anim)
			end)
			if ok and track then
				if anim.Name == "Idle" or anim.Name == "Walk" then
					track.Looped = true
				elseif anim.Name == "Digging" then
					track.Looped = false
				end
				tracks[anim.Name] = track
			end
		end
	end

	if tracks.Idle then
		tracks.Idle:Play(0.2)
	end

	return tracks
end

local function setPetAnimation(visual: { AnimTracks: { [string]: AnimationTrack }?, CurrentAnim: string? }, targetAnim: string)
	if not visual.AnimTracks then
		return
	end
	if visual.CurrentAnim == targetAnim then
		return
	end

	local prev = if visual.CurrentAnim then visual.AnimTracks[visual.CurrentAnim] else nil
	local nextTrack = visual.AnimTracks[targetAnim]

	if prev and prev ~= nextTrack then
		prev:Stop(0.2)
	end
	if nextTrack and not nextTrack.IsPlaying then
		nextTrack:Play(0.2)
	end
	visual.CurrentAnim = targetAnim
end

local function getGroundOffset(model: Model, root: BasePart): number
	local bottom = math.huge
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			for _, x in {-1, 1} do
				for _, y in {-1, 1} do
					for _, z in {-1, 1} do
						local corner = part.CFrame:PointToWorldSpace(part.Size * Vector3.new(x, y, z) * 0.5)
						bottom = math.min(bottom, corner.Y)
					end
				end
			end
		end
	end
	return if bottom == math.huge then root.Size.Y * 0.5 else root.Position.Y - bottom
end

local function groundPosition(position: Vector3, offset: number): Vector3
	local ignore: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	for _, name in {"ClientPetVisuals", "ClientBasePetVisuals", "ClientMounds", "ActiveMounds"} do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local hit = workspace:Raycast(position + Vector3.new(0, 12, 0), Vector3.new(0, -120, 0), params)
	return if hit then Vector3.new(position.X, hit.Position.Y + offset + 0.03, position.Z) else position
end

-- Synchronize equipped follower pets for a given player
local function syncPlayerEquippedPets(player: Player, petSummaries: { PetSummary }?)
	if not petSummaries then
		petSummaries = getPlayerEquippedSummaries(player)
	end

	local userId = player.UserId
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

	-- If character is not present yet, wait for CharacterAdded
	if not rootPart then
		return
	end

	local newGuids: { string } = {}
	local activeGuids: { [string]: boolean } = {}
	local playerPos = rootPart.Position
	local ownerName = getOwnerDisplayName(player)

	for _, summary in ipairs(petSummaries) do
		local guid = summary.Guid
		table.insert(newGuids, guid)
		activeGuids[guid] = true

		local existing = activeVisuals[guid]
		if not existing then
			local speciesCfg = PetsConfig.Species[summary.Species]
			local speed = if speciesCfg then speciesCfg.Speed else 2
			local moveSpeed = PetsConfig.BaseMoveSpeedStuds + (PetsConfig.MoveSpeedPerStat * speed)

			local spawnPos = playerPos + Vector3.new(math.random(-3, 3), 1, math.random(-3, 3))
			local model, root = PetModelBuilder.BuildPet(
				guid,
				summary.Species,
				summary.Variant,
				summary.Level,
				spawnPos,
				ownerName
			)

			if petVisualFolder then
				model.Parent = petVisualFolder
			end

			local animTracks = setupPetAnimations(model)
			local groundOffset = getGroundOffset(model, root)
			local grounded = groundPosition(root.Position, groundOffset)
			root.CFrame = CFrame.new(grounded) * root.CFrame.Rotation

			activeVisuals[guid] = {
				Guid = guid,
				OwnerUserId = userId,
				OwnerPlayer = player,
				Species = summary.Species,
				Variant = summary.Variant,
				Level = summary.Level,
				Speed = speed,
				MoveSpeed = moveSpeed,
				GroundOffset = groundOffset,
				Model = model,
				RootPart = root,
				CurrentPos = root.Position,
				TargetPos = root.Position,
				IsAttacking = false,
				AttackTargetPos = nil,
				AttackStartedAt = 0,
				AnimTracks = animTracks,
				CurrentAnim = if animTracks and animTracks.Idle then "Idle" else nil,
			}
		end
	end

	-- Remove unequipped
	local oldGuids = playerEquippedGuids[userId] or {}
	for _, oldGuid in ipairs(oldGuids) do
		if not activeGuids[oldGuid] then
			local visual = activeVisuals[oldGuid]
			if visual then
				if visual.AnimTracks then
					for _, track in pairs(visual.AnimTracks) do
						track:Stop(0)
					end
				end
				if visual.Model then
					visual.Model:Destroy()
				end
				activeVisuals[oldGuid] = nil
			end
		end
	end

	playerEquippedGuids[userId] = newGuids
end

-- Synchronize base roaming pets for a given player
local function syncPlayerBasePets(player: Player, petSummaries: { PetSummary }?)
	if not petSummaries then
		petSummaries = getPlayerBaseSummaries(player)
	end

	local userId = player.UserId
	local newGuids: { string } = {}
	local activeGuids: { [string]: boolean } = {}
	local ground = getPlayerPlotGround(player)
	local ownerName = getOwnerDisplayName(player)

	for _, summary in ipairs(petSummaries) do
		local guid = summary.Guid
		table.insert(newGuids, guid)
		activeGuids[guid] = true

		local existing = activeBaseVisuals[guid]
		if not existing then
			local speciesCfg = PetsConfig.Species[summary.Species]
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

			local model, root = PetModelBuilder.BuildPet(
				"Base_" .. guid,
				summary.Species,
				summary.Variant,
				summary.Level,
				spawnPos,
				ownerName
			)

			if basePetVisualFolder then
				model.Parent = basePetVisualFolder
			end

			local animTracks = setupPetAnimations(model)

			activeBaseVisuals[guid] = {
				Guid = guid,
				OwnerUserId = userId,
				OwnerPlayer = player,
				Species = summary.Species,
				Variant = summary.Variant,
				Level = summary.Level,
				Speed = speed,
				MoveSpeed = moveSpeed,
				Model = model,
				RootPart = root,
				CurrentPos = root.Position,
				TargetPos = root.Position,
				NextMoveTime = os.clock() + math.random(2, 5),
				GroundPart = ground,
				AnimTracks = animTracks,
				CurrentAnim = if animTracks and animTracks.Idle then "Idle" else nil,
			}
		else
			if ground and (not existing.GroundPart or existing.GroundPart ~= ground) then
				existing.GroundPart = ground
			end
		end
	end

	-- Remove unassigned base pets
	local oldGuids = playerBaseGuids[userId] or {}
	for _, oldGuid in ipairs(oldGuids) do
		if not activeGuids[oldGuid] then
			local visual = activeBaseVisuals[oldGuid]
			if visual then
				if visual.AnimTracks then
					for _, track in pairs(visual.AnimTracks) do
						track:Stop(0)
					end
				end
				if visual.Model then
					visual.Model:Destroy()
				end
				activeBaseVisuals[oldGuid] = nil
			end
		end
	end

	playerBaseGuids[userId] = newGuids
end

local function setupPlayer(player: Player)
	local userId = player.UserId

	player.CharacterAdded:Connect(function(char)
		local hrp = char:WaitForChild("HumanoidRootPart", 5) :: BasePart?
		if hrp then
			syncPlayerEquippedPets(player)
		end
	end)

	player.CharacterRemoving:Connect(function()
		local guids = playerEquippedGuids[userId]
		if guids then
			for _, guid in ipairs(guids) do
				local visual = activeVisuals[guid]
				if visual then
					if visual.AnimTracks then
						for _, track in pairs(visual.AnimTracks) do
							track:Stop(0)
						end
					end
					if visual.Model then
						visual.Model:Destroy()
					end
					activeVisuals[guid] = nil
				end
			end
		end
	end)

	player:GetAttributeChangedSignal("PublicEquippedPets"):Connect(function()
		syncPlayerEquippedPets(player)
	end)

	player:GetAttributeChangedSignal("PublicBasePets"):Connect(function()
		syncPlayerBasePets(player)
	end)

	player:GetAttributeChangedSignal("AssignedPlot"):Connect(function()
		syncPlayerBasePets(player)
	end)

	task.spawn(function()
		syncPlayerEquippedPets(player)
		syncPlayerBasePets(player)
	end)
end

local function cleanupPlayer(player: Player)
	local userId = player.UserId

	local eqGuids = playerEquippedGuids[userId]
	if eqGuids then
		for _, guid in ipairs(eqGuids) do
			local visual = activeVisuals[guid]
			if visual then
				if visual.AnimTracks then
					for _, track in pairs(visual.AnimTracks) do
						track:Stop(0)
					end
				end
				if visual.Model then
					visual.Model:Destroy()
				end
				activeVisuals[guid] = nil
			end
		end
		playerEquippedGuids[userId] = nil
	end

	local bGuids = playerBaseGuids[userId]
	if bGuids then
		for _, guid in ipairs(bGuids) do
			local visual = activeBaseVisuals[guid]
			if visual then
				if visual.AnimTracks then
					for _, track in pairs(visual.AnimTracks) do
						track:Stop(0)
					end
				end
				if visual.Model then
					visual.Model:Destroy()
				end
				activeBaseVisuals[guid] = nil
			end
		end
		playerBaseGuids[userId] = nil
	end
end

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
		localOwnedPets = payload.Pets
	end
	if type(payload.EquippedPets) == "table" then
		localEquippedGuids = payload.EquippedPets
	end
	if type(payload.BasePets) == "table" then
		localBaseGuids = payload.BasePets
	end

	syncPlayerEquippedPets(LocalPlayer)
	syncPlayerBasePets(LocalPlayer)
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

	-- Listen for local player's StateSync
	Remotes.GetEvent("StateSync").OnClientEvent:Connect(function(payload: any)
		PetVisualController.ApplySnapshot(payload)
	end)

	-- Listen for PetAttackVisual (broadcast to all clients)
	Remotes.GetEvent("PetAttackVisual").OnClientEvent:Connect(function(petGuid: string, moundId: string, damage: number)
		local visual = activeVisuals[petGuid]
		if not visual then
			return
		end

		local activeMoundsFolder = workspace:FindFirstChild("ClientMounds") or workspace:FindFirstChild("ActiveMounds")
		local moundModel = activeMoundsFolder and activeMoundsFolder:FindFirstChild(moundId)
		local moundPos = if moundModel and moundModel:IsA("Model") and moundModel.PrimaryPart
			then moundModel.PrimaryPart.Position
			else nil

		if moundPos then
			visual.IsAttacking = true
			local away = Vector3.new(visual.CurrentPos.X - moundPos.X, 0, visual.CurrentPos.Z - moundPos.Z)
			if away.Magnitude < 0.01 then
				away = Vector3.new(1, 0, 0)
			end
			local moundRadius = if moundModel and moundModel:IsA("Model") and moundModel.PrimaryPart
				then math.max(moundModel.PrimaryPart.Size.X, moundModel.PrimaryPart.Size.Z) * 0.5
				else 2
			visual.AttackTargetPos = moundPos + away.Unit * (moundRadius + 1.1)
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

	-- Setup player tracking for all current and future players
	for _, player in ipairs(Players:GetPlayers()) do
		setupPlayer(player)
	end
	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(cleanupPlayer)

	-- Frame movement loop (RenderStepped)
	RunService.RenderStepped:Connect(function(dt: number)
		local now = os.clock()

		-- 1. Equipped pets follow their respective player
		for userId, guids in pairs(playerEquippedGuids) do
			local player = Players:GetPlayerByUserId(userId)
			if not player then
				continue
			end

			local character = player.Character
			if not character then
				continue
			end

			local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not rootPart then
				continue
			end

			local charCFrame = rootPart.CFrame
			local totalEquipped = math.clamp(#guids, 1, 3)
			local offsets = FORMATION_OFFSETS[totalEquipped] or FORMATION_OFFSETS[1]

			for idx, guid in ipairs(guids) do
				local visual = activeVisuals[guid]
				if visual and visual.RootPart and visual.RootPart.Parent then
					local targetPos: Vector3
					local targetLook: Vector3
					local species = PetsConfig.Species[visual.Species]
					local leash = if species then species.Range else 14

					-- Return immediately when player moves or teleports beyond leash
					local fromPlayer = visual.CurrentPos - rootPart.Position
					if fromPlayer.Magnitude > leash then
						visual.CurrentPos = rootPart.Position + fromPlayer.Unit * leash
						visual.IsAttacking = false
						visual.AttackTargetPos = nil
					end

					if visual.IsAttacking and visual.AttackTargetPos then
						-- Dash towards mound attack target
						targetPos = visual.AttackTargetPos
						targetLook = (targetPos - visual.CurrentPos).Unit
					else
						-- Formation following avatar
						local offset = offsets[idx] or Vector3.new(2.5, 0.8, 2.0)
						local formationPos = (charCFrame * CFrame.new(offset.X, 0, offset.Z)).Position
						targetPos = formationPos
						targetLook = charCFrame.LookVector
					end

					local targetOffset = targetPos - rootPart.Position
					if targetOffset.Magnitude > leash then
						targetPos = rootPart.Position + targetOffset.Unit * leash
					end
					targetPos = groundPosition(targetPos, visual.GroundOffset)
					local maxMove = visual.MoveSpeed * dt
					local diff = targetPos - visual.CurrentPos
					local dist = diff.Magnitude

					local nextPos = if dist <= maxMove then targetPos else visual.CurrentPos + (diff.Unit * maxMove)
					local leashOffset = nextPos - rootPart.Position
					if leashOffset.Magnitude > leash then
						nextPos = rootPart.Position + leashOffset.Unit * leash
					end
					nextPos = groundPosition(nextPos, visual.GroundOffset)
					visual.CurrentPos = nextPos

					-- Animation state
					if visual.AnimTracks then
						if visual.IsAttacking then
							setPetAnimation(visual, "Digging")
						elseif dist > 0.15 then
							setPetAnimation(visual, "Walk")
						else
							setPetAnimation(visual, "Idle")
						end
					end

					-- Smooth orientation
					local lookDelta = Vector3.new(targetPos.X - visual.CurrentPos.X, 0, targetPos.Z - visual.CurrentPos.Z)
					targetLook = Vector3.new(targetLook.X, 0, targetLook.Z)
					local lookDir = if lookDelta.Magnitude > 0.05 then lookDelta.Unit else targetLook
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
		end

		-- 2. Base pets roaming in their respective player's plot ground
		for _, visual in pairs(activeBaseVisuals) do
			if visual and visual.RootPart and visual.RootPart.Parent then
				local ground = visual.GroundPart
				if not ground or not ground.Parent then
					ground = getPlayerPlotGround(visual.OwnerPlayer)
					visual.GroundPart = ground
				end

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

				if visual.AnimTracks then
					if dist > 0.2 then
						setPetAnimation(visual, "Walk")
					else
						setPetAnimation(visual, "Idle")
					end
				end

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
