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
			Message = string.format("Uang belum cukup! Butuh $%d untuk upgrade ke Lv.%d.", cost, curLevel + 1),
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

-- Clean up sign billboard on plot (base text removed per user request)
local function updatePlotSign(plotFolder: Folder, ownerPlayer: Player?, baseLevel: number?)
	local signPart = BaseService.GetPlotSignBoard(plotFolder)
	if signPart then
		local existing = signPart:FindFirstChild("PlotSignGui")
		if existing then
			existing:Destroy()
		end
	end

	local plotName = plotFolder.Name
	local textPart = plotFolder:FindFirstChild("Text_" .. plotName)
	if textPart then
		local signGui = textPart:FindFirstChild("SignGui")
		if signGui then
			signGui:Destroy()
		end
	end
end

-- Clean up incubator station models and return pad on the plot (removed per user request)
local function refreshPlotIncubatorStation(plotFolder: Folder, player: Player, profile: Types.PlayerProfile)
	local containerName = "IncubatorStationContainer"
	local existing = plotFolder:FindFirstChild(containerName)
	if existing then
		existing:Destroy()
	end

	local returnPad = plotFolder:FindFirstChild("ReturnToHubPad")
	if returnPad then
		returnPad:Destroy()
	end
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
		player:SetAttribute("CurrentZone", "Base")
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
		player:SetAttribute("CurrentZone", "Hub")
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

		local returnPad = plotFolder:FindFirstChild("ReturnToHubPad")
		if returnPad then
			returnPad:Destroy()
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

-- Clean up any legacy Hub Teleport Pad (teleport is now handled via Topbar UI)
function BaseService.EnsureHubTeleportPad()
	local plain = workspace:FindFirstChild("Plain")
	local parentContainer = plain or workspace

	local existing = parentContainer:FindFirstChild("HubBaseTeleportPad")
	if existing then
		existing:Destroy()
	end
	hubTeleportPad = nil
	return nil
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

	Remotes.OnServerEvent("TeleportToHub", function(player: Player)
		BaseService.TeleportPlayerToHub(player)
	end)

	Remotes.OnServerInvoke("UpgradeBase", function(player: Player): UpgradeBaseResult
		return BaseService.UpgradeBase(player)
	end)
end

return BaseService
