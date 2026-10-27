--!strict
-- Server-authoritative Base plots management, plot assignment, level upgrades 1-5, incubator station visuals, and hub teleport pad (Step 8)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local BaseConfig = require(Shared:WaitForChild("Config"):WaitForChild("Base"))
local EggsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Eggs"))
local RarityConfig = require(Shared:WaitForChild("Config"):WaitForChild("Rarity"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
local ShovelInventoryService = require(script.Parent:WaitForChild("ShovelInventoryService"))
local EggService = require(script.Parent:WaitForChild("EggService"))

export type UpgradeBaseResult = {
	Success: boolean,
	Reason: string?,
	Message: string?,
	NewBaseLevel: number?,
	IncubatorSlots: number?,
	PetSlots: number?,
	CostPaid: number?,
	Coins: number?,
}

local BaseService = {}

local assignedPlotsByUserId: { [number]: string } = {}
local assignedUsersByPlotName: { [string]: number } = {}
local hubTeleportPad: BasePart? = nil
local started = false

-- Base plot ground positions & metadata
local PLOT_NAMES = { "Plot1", "Plot2", "Plot3", "Plot4", "Plot5", "Plot6" }

function BaseService.GetAssignedPlotName(player: Player): string?
	return assignedPlotsByUserId[player.UserId]
end

function BaseService.GetAssignedPlotFolder(player: Player): Folder?
	local plotName = BaseService.GetAssignedPlotName(player)
	if not plotName then
		return nil
	end
	local basePlots = workspace:FindFirstChild("BasePlots")
	return basePlots and basePlots:FindFirstChild(plotName) :: Folder?
end

function BaseService.GetPlotGround(plotFolder: Folder): BasePart?
	for _, child in plotFolder:GetChildren() do
		if child:IsA("BasePart") and string.find(child.Name, "_Ground$") then
			return child
		end
	end
	return nil
end

function BaseService.GetPlotSignBoard(plotFolder: Folder): BasePart?
	for _, child in plotFolder:GetChildren() do
		if child:IsA("BasePart") and string.find(child.Name, "_SignBoard$") then
			return child
		end
	end
	return nil
end

-- Pure profile upgrade logic
function BaseService.UpgradeBaseInProfile(profile: Types.PlayerProfile): UpgradeBaseResult
	local curLevel = profile.BaseLevel
	if curLevel >= BaseConfig.MaxBaseLevel then
		return {
			Success = false,
			Reason = "MaxLevelReached",
			Message = "Base sudah mencapai level maksimal (Lv.5).",
			NewBaseLevel = curLevel,
			Coins = profile.Coins,
		}
	end

	local nextCfg = BaseConfig.Levels[curLevel + 1]
	if not nextCfg then
		return {
			Success = false,
			Reason = "ConfigNotFound",
			Message = "Konfigurasi level berikutnya tidak ditemukan.",
			NewBaseLevel = curLevel,
			Coins = profile.Coins,
		}
	end

	local cost = nextCfg.UpgradeCost
	if profile.Coins < cost then
		return {
			Success = false,
			Reason = "InsufficientCoins",
			Message = string.format("Coin belum cukup! Butuh %d Coin untuk upgrade ke Lv.%d.", cost, curLevel + 1),
			NewBaseLevel = curLevel,
			Coins = profile.Coins,
		}
	end

	profile.Coins = math.max(0, profile.Coins - cost)
	profile.BaseLevel = curLevel + 1

	return {
		Success = true,
		NewBaseLevel = profile.BaseLevel,
		IncubatorSlots = nextCfg.IncubatorSlots,
		PetSlots = nextCfg.PetSlots,
		CostPaid = cost,
		Coins = profile.Coins,
	}
end

-- Update sign billboard on plot
local function updatePlotSign(plotFolder: Folder, ownerPlayer: Player?, baseLevel: number?)
	local signPart = BaseService.GetPlotSignBoard(plotFolder)
	if not signPart then
		return
	end

	local existing = signPart:FindFirstChild("PlotSignGui")
	if existing then
		existing:Destroy()
	end

	local bb = Instance.new("BillboardGui")
	bb.Name = "PlotSignGui"
	bb.Adornee = signPart
	bb.Size = UDim2.fromOffset(220, 54)
	bb.StudsOffset = Vector3.new(0, 3.2, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 80
	bb.Parent = signPart

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(24, 30, 44)
	bg.BackgroundTransparency = 0.12
	bg.BorderSizePixel = 0
	bg.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = bg

	local stroke = Instance.new("UIStroke")
	stroke.Color = if ownerPlayer then Color3.fromRGB(96, 212, 255) else Color3.fromRGB(118, 132, 162)
	stroke.Thickness = 1.8
	stroke.Parent = bg

	local title = Instance.new("TextLabel")
	title.Name = "OwnerTitle"
	title.Position = UDim2.fromOffset(6, 4)
	title.Size = UDim2.new(1, -12, 0, 24)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 14
	title.TextColor3 = if ownerPlayer then Color3.fromRGB(255, 224, 96) else Color3.fromRGB(185, 195, 215)
	title.Text = if ownerPlayer then string.format("%s's Base", ownerPlayer.DisplayName) else "Base Plot Kosong"
	title.Parent = bg

	local sub = Instance.new("TextLabel")
	sub.Name = "LevelSub"
	sub.Position = UDim2.fromOffset(6, 26)
	sub.Size = UDim2.new(1, -12, 0, 20)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamBold
	sub.TextSize = 11
	sub.TextColor3 = Color3.fromRGB(120, 235, 165)
	local lv = baseLevel or 1
	local cfg = BaseConfig.Levels[lv] or BaseConfig.Levels[1]
	sub.Text = if ownerPlayer
		then string.format("Level %d • %d Inkubator • %d Pet", lv, cfg.IncubatorSlots, cfg.PetSlots)
		else "Tersedia untuk pemain"
	sub.Parent = bg
end

-- Build or refresh incubator station models on the assigned plot
local function refreshPlotIncubatorStation(plotFolder: Folder, player: Player, profile: Types.PlayerProfile)
	local ground = BaseService.GetPlotGround(plotFolder)
	if not ground then
		return
	end

	local containerName = "IncubatorStationContainer"
	local existing = plotFolder:FindFirstChild(containerName)
	if existing then
		existing:Destroy()
	end

	local station = Instance.new("Model")
	station.Name = containerName
	station.Parent = plotFolder

	local maxSlots = EggService.GetMaxIncubatorSlots(profile.BaseLevel)
	local groundPos = ground.Position

	-- Position the 1..5 incubator pods in an orderly arc/row inside the plot
	local spacing = 6.2
	local startX = -((maxSlots - 1) * spacing * 0.5)

	for slotIndex = 1, maxSlots do
		local pod = Instance.new("Model")
		pod.Name = "IncubatorPod_" .. slotIndex
		pod.Parent = station

		local localOffset = Vector3.new(startX + (slotIndex - 1) * spacing, 0.45, -7.5)
		local worldPos = groundPos + localOffset

		local pedestal = Instance.new("Part")
		pedestal.Name = "Pedestal"
		pedestal.Shape = Enum.PartType.Cylinder
		pedestal.Size = Vector3.new(0.9, 3.2, 3.2)
		pedestal.CFrame = CFrame.new(worldPos) * CFrame.Angles(0, 0, math.rad(90))
		pedestal.Color = Color3.fromRGB(44, 52, 70)
		pedestal.Material = Enum.Material.SmoothPlastic
		pedestal.Anchored = true
		pedestal.CanCollide = true
		pedestal.Parent = pod
		pod.PrimaryPart = pedestal

		local glowRing = Instance.new("Part")
		glowRing.Name = "GlowRing"
		glowRing.Shape = Enum.PartType.Cylinder
		glowRing.Size = Vector3.new(0.2, 3.4, 3.4)
		glowRing.CFrame = CFrame.new(worldPos + Vector3.new(0, 0.45, 0)) * CFrame.Angles(0, 0, math.rad(90))
		glowRing.Material = Enum.Material.Neon
		glowRing.Anchored = true
		glowRing.CanCollide = false
		glowRing.Parent = pod

		local glass = Instance.new("Part")
		glass.Name = "GlassDome"
		glass.Shape = Enum.PartType.Cylinder
		glass.Size = Vector3.new(2.4, 2.6, 2.6)
		glass.CFrame = CFrame.new(worldPos + Vector3.new(0, 1.7, 0)) * CFrame.Angles(0, 0, math.rad(90))
		glass.Color = Color3.fromRGB(180, 225, 255)
		glass.Transparency = 0.65
		glass.Material = Enum.Material.Glass
		glass.Anchored = true
		glass.CanCollide = false
		glass.Parent = pod

		local eggEntry = profile.Incubators[slotIndex]
		local isOccupied = (eggEntry ~= nil)

		glowRing.Color = if isOccupied
			then (RarityConfig.ById[eggEntry.Rarity] and RarityConfig.ById[eggEntry.Rarity].Color or Color3.fromRGB(96, 212, 255))
			else Color3.fromRGB(72, 88, 118)

		-- Egg placeholder model inside glass dome
		if isOccupied and eggEntry then
			local eggPart = Instance.new("Part")
			eggPart.Name = "IncubatingEgg"
			eggPart.Shape = Enum.PartType.Ball
			eggPart.Size = Vector3.new(1.3, 1.7, 1.3)
			eggPart.CFrame = CFrame.new(worldPos + Vector3.new(0, 1.6, 0))
			local rarityCfg = RarityConfig.ById[eggEntry.Rarity]
			eggPart.Color = if rarityCfg then rarityCfg.Color else Color3.fromRGB(240, 240, 240)
			eggPart.Material = Enum.Material.SmoothPlastic
			eggPart.Anchored = true
			eggPart.CanCollide = false
			eggPart.Parent = pod
		end

		-- Billboard status & timer
		local bb = Instance.new("BillboardGui")
		bb.Name = "StatusBillboard"
		bb.Adornee = pedestal
		bb.Size = UDim2.fromOffset(150, 48)
		bb.StudsOffset = Vector3.new(0, 3.8, 0)
		bb.AlwaysOnTop = false
		bb.MaxDistance = 50
		bb.Parent = pod

		local statusBg = Instance.new("Frame")
		statusBg.Size = UDim2.fromScale(1, 1)
		statusBg.BackgroundColor3 = Color3.fromRGB(20, 26, 38)
		statusBg.BackgroundTransparency = 0.15
		statusBg.BorderSizePixel = 0
		statusBg.Parent = bb

		local statusCorner = Instance.new("UICorner")
		statusCorner.CornerRadius = UDim.new(0, 8)
		statusCorner.Parent = statusBg

		local slotLabel = Instance.new("TextLabel")
		slotLabel.Name = "SlotLabel"
		slotLabel.Position = UDim2.fromOffset(4, 3)
		slotLabel.Size = UDim2.new(1, -8, 0, 18)
		slotLabel.BackgroundTransparency = 1
		slotLabel.Font = Enum.Font.GothamBlack
		slotLabel.TextSize = 12
		slotLabel.TextColor3 = Color3.fromRGB(255, 220, 96)
		slotLabel.Text = string.format("Inkubator #%d", slotIndex)
		slotLabel.Parent = statusBg

		local timerLabel = Instance.new("TextLabel")
		timerLabel.Name = "TimerLabel"
		timerLabel.Position = UDim2.fromOffset(4, 22)
		timerLabel.Size = UDim2.new(1, -8, 0, 18)
		timerLabel.BackgroundTransparency = 1
		timerLabel.Font = Enum.Font.GothamBold
		timerLabel.TextSize = 11
		timerLabel.TextColor3 = if isOccupied then Color3.fromRGB(112, 238, 154) else Color3.fromRGB(160, 172, 196)
		timerLabel.Text = if isOccupied
			then (if os.time() >= eggEntry.ReadyAt then "SIAP DITETASKAN!" else "Sedang Inkubasi...")
			else "Kosong"
		timerLabel.Parent = statusBg

		-- ProximityPrompt for interaction
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "IncubatorPrompt"
		prompt.ObjectText = string.format("Inkubator #%d", slotIndex)
		prompt.ActionText = if isOccupied
			then (if os.time() >= eggEntry.ReadyAt then "Tetaskan Pet" else "Kelola Inkubasi")
			else "Taruh Telur"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		prompt.Parent = pedestal

		prompt:SetAttribute("DigPalsIncubatorSlot", slotIndex)
		prompt:SetAttribute("DigPalsPlotName", plotFolder.Name)
	end

	-- Return pad to Hub
	local returnPad = Instance.new("Part")
	returnPad.Name = "ReturnToHubPad"
	returnPad.Shape = Enum.PartType.Cylinder
	returnPad.Size = Vector3.new(0.35, 5.0, 5.0)
	returnPad.CFrame = CFrame.new(groundPos + Vector3.new(0, 0.2, 14.5)) * CFrame.Angles(0, 0, math.rad(90))
	returnPad.Color = Color3.fromRGB(46, 178, 106)
	returnPad.Material = Enum.Material.Neon
	returnPad.Anchored = true
	returnPad.CanCollide = false
	returnPad.Parent = station

	local returnPrompt = Instance.new("ProximityPrompt")
	returnPrompt.Name = "ReturnPrompt"
	returnPrompt.ObjectText = "Teleport Pad"
	returnPrompt.ActionText = "Kembali ke Hub"
	returnPrompt.KeyboardKeyCode = Enum.KeyCode.E
	returnPrompt.HoldDuration = 0
	returnPrompt.MaxActivationDistance = 9
	returnPrompt.RequiresLineOfSight = false
	returnPrompt.Parent = returnPad

	returnPrompt.Triggered:Connect(function(triggeringPlayer: Player)
		if triggeringPlayer == player then
			BaseService.TeleportPlayerToHub(triggeringPlayer)
		end
	end)
end

-- Teleport player to their assigned base plot
function BaseService.TeleportPlayerToBase(player: Player): boolean
	local plotFolder = BaseService.GetAssignedPlotFolder(player)
	if not plotFolder then
		return false
	end

	local signPart = BaseService.GetPlotSignBoard(plotFolder)
	local groundPart = BaseService.GetPlotGround(plotFolder)
	local targetPos: Vector3? = nil

	if signPart then
		targetPos = signPart.Position + Vector3.new(0, 1.0, -5.0)
	elseif groundPart then
		targetPos = groundPart.Position + Vector3.new(0, 3.5, 12.0)
	end

	if not targetPos then
		return false
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		hrp.CFrame = CFrame.new(targetPos) * CFrame.Angles(0, math.rad(180), 0)
		return true
	end
	return false
end

-- Teleport player back to Hub Plaza
function BaseService.TeleportPlayerToHub(player: Player): boolean
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		hrp.CFrame = CFrame.new(0, 3.5, 0)
		return true
	end
	return false
end

-- Assign a free plot to the player upon joining
function BaseService.AssignPlot(player: Player): string?
	if assignedPlotsByUserId[player.UserId] then
		return assignedPlotsByUserId[player.UserId]
	end

	local basePlots = workspace:FindFirstChild("BasePlots")
	if not basePlots then
		warn("[BaseService] Workspace.BasePlots folder not found!")
		return nil
	end

	local chosenName: string? = nil
	for _, plotName in PLOT_NAMES do
		if assignedUsersByPlotName[plotName] == nil then
			chosenName = plotName
			break
		end
	end

	if not chosenName then
		warn(string.format("[BaseService] All %d plots are occupied! Cannot assign plot for %s", #PLOT_NAMES, player.Name))
		return nil
	end

	assignedPlotsByUserId[player.UserId] = chosenName
	assignedUsersByPlotName[chosenName] = player.UserId
	player:SetAttribute("AssignedPlot", chosenName)

	local plotFolder = basePlots:FindFirstChild(chosenName)
	if plotFolder and plotFolder:IsA("Folder") then
		plotFolder:SetAttribute("OwnerUserId", player.UserId)
		plotFolder:SetAttribute("OwnerName", player.Name)
		local profile = PlayerState.Get(player)
		local baseLv = if profile then profile.BaseLevel else 1
		updatePlotSign(plotFolder, player, baseLv)
		if profile then
			refreshPlotIncubatorStation(plotFolder, player, profile)
		end
	end

	print(string.format("[BaseService] Assigned %s to %s (%d)", chosenName, player.Name, player.UserId))
	return chosenName
end

-- Release plot when player leaves
function BaseService.FreePlot(player: Player)
	local plotName = assignedPlotsByUserId[player.UserId]
	if not plotName then
		return
	end

	assignedPlotsByUserId[player.UserId] = nil
	assignedUsersByPlotName[plotName] = nil
	player:SetAttribute("AssignedPlot", nil)

	local basePlots = workspace:FindFirstChild("BasePlots")
	local plotFolder = basePlots and basePlots:FindFirstChild(plotName)
	if plotFolder and plotFolder:IsA("Folder") then
		plotFolder:SetAttribute("OwnerUserId", nil)
		plotFolder:SetAttribute("OwnerName", nil)
		updatePlotSign(plotFolder, nil, 1)

		local station = plotFolder:FindFirstChild("IncubatorStationContainer")
		if station then
			station:Destroy()
		end
	end

	print(string.format("[BaseService] Released %s from %s (%d)", plotName, player.Name, player.UserId))
end

-- Server upgrade request
function BaseService.UpgradeBase(player: Player): UpgradeBaseResult
	local result: UpgradeBaseResult = {
		Success = false,
		Reason = "Unknown",
	}

	local mutated = PlayerState.Mutate(player, function(profile: Types.PlayerProfile)
		result = BaseService.UpgradeBaseInProfile(profile)
	end)

	if not mutated then
		return {
			Success = false,
			Reason = "MutateFailed",
			Message = "Gagal memproses upgrade base.",
		}
	end

	if result.Success then
		DataService.SavePlayer(player)
		ShovelInventoryService.SendStateSync(player)
		local plotFolder = BaseService.GetAssignedPlotFolder(player)
		local profile = PlayerState.Get(player)
		if plotFolder and profile then
			updatePlotSign(plotFolder, player, profile.BaseLevel)
			refreshPlotIncubatorStation(plotFolder, player, profile)
		end
	end

	return result
end

-- Setup Hub Teleport Pad to player's Base
function BaseService.EnsureHubTeleportPad()
	if hubTeleportPad and hubTeleportPad.Parent ~= nil then
		return hubTeleportPad
	end

	local plain = workspace:FindFirstChild("Plain")
	local parentContainer = plain or workspace

	local existing = parentContainer:FindFirstChild("HubBaseTeleportPad")
	if existing and existing:IsA("BasePart") then
		hubTeleportPad = existing
		return existing
	end

	local pad = Instance.new("Part")
	pad.Name = "HubBaseTeleportPad"
	pad.Shape = Enum.PartType.Cylinder
	pad.Size = Vector3.new(0.4, 6.0, 6.0)
	pad.CFrame = CFrame.new(0, 0.25, -28) * CFrame.Angles(0, 0, math.rad(90))
	pad.Color = Color3.fromRGB(72, 196, 248)
	pad.Material = Enum.Material.Neon
	pad.Anchored = true
	pad.CanCollide = false
	pad.Parent = parentContainer
	hubTeleportPad = pad

	local bb = Instance.new("BillboardGui")
	bb.Name = "PadSign"
	bb.Adornee = pad
	bb.Size = UDim2.fromOffset(170, 46)
	bb.StudsOffset = Vector3.new(0, 3.2, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 60
	bb.Parent = pad

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(20, 28, 42)
	bg.BackgroundTransparency = 0.15
	bg.BorderSizePixel = 0
	bg.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 9)
	corner.Parent = bg

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(96, 212, 255)
	stroke.Thickness = 1.6
	stroke.Parent = bg

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(4, 3)
	title.Size = UDim2.new(1, -8, 0, 20)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 13
	title.TextColor3 = Color3.fromRGB(108, 220, 255)
	title.Text = "TELEPORT KE BASE"
	title.Parent = bg

	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.Position = UDim2.fromOffset(4, 23)
	sub.Size = UDim2.new(1, -8, 0, 18)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamBold
	sub.TextSize = 11
	sub.TextColor3 = Color3.fromRGB(220, 235, 255)
	sub.Text = "Inkubator & Pet Pribadi"
	sub.Parent = bg

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TeleportToBasePrompt"
	prompt.ObjectText = "Base Pribadi"
	prompt.ActionText = "Masuk ke Base"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 11
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad

	prompt.Triggered:Connect(function(player: Player)
		BaseService.TeleportPlayerToBase(player)
	end)

	return pad
end

function BaseService.Start()
	if started then
		return
	end
	started = true

	BaseService.EnsureHubTeleportPad()

	local function ensurePlayerPlot(player: Player)
		local profile = PlayerState.Get(player)
		if profile and not BaseService.GetAssignedPlotName(player) then
			local plotName = BaseService.AssignPlot(player)
			local plotFolder = plotName and BaseService.GetAssignedPlotFolder(player)
			if plotFolder then
				refreshPlotIncubatorStation(plotFolder, player, profile)
			end
		end
	end

	-- Assign plot when player's profile is loaded
	DataService.OnProfileLoaded(function(player: Player, profile: Types.PlayerProfile)
		ensurePlayerPlot(player)
	end)

	PlayerState.OnChanged(function(player: Player, profile: Types.PlayerProfile)
		if not BaseService.GetAssignedPlotName(player) then
			ensurePlayerPlot(player)
		else
			local plotFolder = BaseService.GetAssignedPlotFolder(player)
			if plotFolder then
				updatePlotSign(plotFolder, player, profile.BaseLevel)
				refreshPlotIncubatorStation(plotFolder, player, profile)
			end
		end
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(function()
			local startWait = os.clock()
			while player.Parent == Players and not PlayerState.Get(player) and (os.clock() - startWait) < 10 do
				task.wait(0.2)
			end
			ensurePlayerPlot(player)
		end)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		BaseService.FreePlot(player)
	end)

	Remotes.OnServerEvent("TeleportToBase", function(player: Player)
		BaseService.TeleportPlayerToBase(player)
	end)

	Remotes.OnServerInvoke("UpgradeBase", function(player: Player): UpgradeBaseResult
		return BaseService.UpgradeBase(player)
	end)
end

return BaseService
