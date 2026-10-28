--!strict
-- Authoritative Tutorial Service & Sandy Gate unlock validation (Step 14)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local ShovelsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Shovels"))
local EggsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Eggs"))

local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local ShovelInventoryService = require(script.Parent:WaitForChild("ShovelInventoryService"))

export type UnlockGateResult = {
	Success: boolean,
	Reason: string?,
	Message: string?,
}

local TutorialService = {}

local SANDY_GATE_COST = 10000
local IRON_SHOVEL_INDEX = 3 -- "IronShovel" in ShovelsConfig.AllOrder

local started = false

local function ensureTutorialTable(profile: Types.PlayerProfile)
	if type(profile.Tutorial) ~= "table" then
		profile.Tutorial = { Step = 1, Done = false }
	end
	if profile.Tutorial.Step == nil then
		profile.Tutorial.Step = 1
	end
	if profile.Tutorial.Done == nil then
		profile.Tutorial.Done = false
	end
end

function TutorialService.GetTutorialStatus(profile: Types.PlayerProfile?): (number, boolean)
	if not profile then
		return 1, false
	end
	ensureTutorialTable(profile)
	return profile.Tutorial.Step, profile.Tutorial.Done
end

function TutorialService.AdvanceStepForProfile(
	profile: Types.PlayerProfile,
	expectedStep: number
): boolean
	ensureTutorialTable(profile)
	if profile.Tutorial.Done then
		return false
	end
	if profile.Tutorial.Step ~= expectedStep then
		return false
	end

	if expectedStep < 5 then
		profile.Tutorial.Step = expectedStep + 1
	else
		profile.Tutorial.Step = 5
		profile.Tutorial.Done = true
	end
	return true
end

function TutorialService.CompleteTutorialForProfile(profile: Types.PlayerProfile): boolean
	ensureTutorialTable(profile)
	if profile.Tutorial.Done then
		return false
	end
	profile.Tutorial.Step = 5
	profile.Tutorial.Done = true
	return true
end

function TutorialService.AdvanceTutorialStep(player: Player, fromStep: number): boolean
	local profile = PlayerState.Get(player)
	if not profile then
		return false
	end

	local advanced = false
	PlayerState.Mutate(player, function(mutableProfile: Types.PlayerProfile)
		advanced = TutorialService.AdvanceStepForProfile(mutableProfile, fromStep)
	end)

	if advanced then
		ShovelInventoryService.SendStateSync(player)
		DataService.SavePlayer(player)
		print(string.format("[TutorialService] Player %s advanced tutorial: Step %d -> %d (Done: %s)",
			player.Name, fromStep, profile.Tutorial.Step, tostring(profile.Tutorial.Done)))
	end
	return advanced
end

function TutorialService.CompleteTutorial(player: Player): boolean
	local profile = PlayerState.Get(player)
	if not profile then
		return false
	end

	local completed = false
	PlayerState.Mutate(player, function(mutableProfile: Types.PlayerProfile)
		completed = TutorialService.CompleteTutorialForProfile(mutableProfile)
	end)

	if completed then
		ShovelInventoryService.SendStateSync(player)
		DataService.SavePlayer(player)
		print(string.format("[TutorialService] Player %s completed tutorial!", player.Name))
	end
	return completed
end

-- Checks if player owns Iron Shovel or any higher tier (Iron, Golden, Mossy, Diamond, Moonlit)
function TutorialService.HasIronShovelOrHigher(profile: Types.PlayerProfile?): boolean
	if not profile or not profile.Shovels or not profile.Shovels.Owned then
		return false
	end
	for _, ownedId in ipairs(profile.Shovels.Owned) do
		local idx = table.find(ShovelsConfig.AllOrder, ownedId)
		if idx and idx >= IRON_SHOVEL_INDEX then
			return true
		end
	end
	return false
end

function TutorialService.UnlockSandyGateForProfile(
	profile: Types.PlayerProfile
): (boolean, string?, string?)
	if profile.SandyGateUnlocked == true then
		return false, "AlreadyUnlocked", "Gerbang Sandy sudah terbuka."
	end

	local hasShovel = TutorialService.HasIronShovelOrHigher(profile)
	if not hasShovel then
		return false, "NeedIronShovel", "Kamu membutuhkan Iron Shovel atau lebih tinggi untuk membuka Gerbang Sandy!"
	end

	local currentCoins = profile.Coins or 0
	if currentCoins < SANDY_GATE_COST then
		return false, "NotEnoughCoins", string.format("Koin tidak cukup! Membutuhkan %s Coin (Koinmu: %s).",
			"10.000", tostring(currentCoins))
	end

	profile.Coins = math.max(0, currentCoins - SANDY_GATE_COST)
	profile.SandyGateUnlocked = true

	return true, nil, "Gerbang Sandy Berhasil Dibuka! Selamat datang di area gurun."
end

function TutorialService.UnlockSandyGate(player: Player): UnlockGateResult
	local profile = PlayerState.Get(player)
	if not profile then
		return { Success = false, Reason = "ProfileNotLoaded", Message = "Profil pemain belum siap." }
	end

	local success = false
	local reason: string? = nil
	local message: string? = nil

	PlayerState.Mutate(player, function(mutableProfile: Types.PlayerProfile)
		success, reason, message = TutorialService.UnlockSandyGateForProfile(mutableProfile)
	end)

	if success then
		player:SetAttribute("SandyGateUnlocked", true)
		ShovelInventoryService.SendStateSync(player)
		DataService.SavePlayer(player)
		print(string.format("[TutorialService] Player %s unlocked Sandy Gate for %d Coins!", player.Name, SANDY_GATE_COST))
	end

	return {
		Success = success,
		Reason = reason,
		Message = message,
	}
end

-- =====================================================================
-- Hook Handlers for Gameplay Actions
-- =====================================================================

function TutorialService.OnMoundCleared(
	player: Player,
	profile: Types.PlayerProfile,
	isPetInvolved: boolean?
)
	ensureTutorialTable(profile)
	if profile.Tutorial.Done then
		return
	end

	-- Step 1: Dig small mound -> advance to Step 2
	if profile.Tutorial.Step == 1 then
		TutorialService.AdvanceTutorialStep(player, 1)
	-- Step 4: Equip pet and dig with it -> advance to Step 5
	elseif profile.Tutorial.Step == 4 then
		local hasEquippedPet = profile.EquippedPets and #profile.EquippedPets > 0
		if hasEquippedPet or isPetInvolved then
			TutorialService.AdvanceTutorialStep(player, 4)
		end
	end
end

function TutorialService.OnItemSold(player: Player, profile: Types.PlayerProfile)
	ensureTutorialTable(profile)
	if profile.Tutorial.Done then
		return
	end

	-- Step 2: Sell item to merchant -> advance to Step 3
	if profile.Tutorial.Step == 2 then
		TutorialService.AdvanceTutorialStep(player, 2)
	end
end

function TutorialService.OnEggHatched(
	player: Player,
	profile: Types.PlayerProfile,
	speciesId: string
)
	ensureTutorialTable(profile)
	if profile.Tutorial.Done then
		return
	end

	-- Step 3: Hatch Starter Egg -> advance to Step 4
	if profile.Tutorial.Step == 3 then
		TutorialService.AdvanceTutorialStep(player, 3)
	end
end

-- =====================================================================
-- Physical Sandy Gate & Coming Soon Placeholder Setup
-- =====================================================================

function TutorialService.EnsureSandyGateInWorkspace()
	local plain = workspace:FindFirstChild("Plain")
	if not plain then
		return
	end
	local sandyGateFolder = plain:FindFirstChild("SandyGate")
	if not sandyGateFolder then
		return
	end

	local portcullis = sandyGateFolder:FindFirstChild("SandyGate_Portcullis") :: BasePart?
	if portcullis then
		portcullis.Anchored = true
		portcullis.CanCollide = true
	end

	local padlock = sandyGateFolder:FindFirstChild("SandyGate_Padlock") :: BasePart?
	local signboard = sandyGateFolder:FindFirstChild("GateSign_Board") :: BasePart?

	-- Setup signboard SurfaceGui
	if signboard and not signboard:FindFirstChild("GateSignDisplay") then
		local sGui = Instance.new("SurfaceGui")
		sGui.Name = "GateSignDisplay"
		sGui.Face = Enum.NormalId.Front
		sGui.CanvasSize = Vector2.new(680, 280)
		sGui.PixelsPerStud = 50
		sGui.LightInfluence = 0.2
		sGui.Parent = signboard

		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
		frame.BorderSizePixel = 0
		frame.Parent = sGui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = frame

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 195, 60)
		stroke.Thickness = 2
		stroke.Parent = frame

		local title = Instance.new("TextLabel")
		title.Position = UDim2.fromOffset(10, 12)
		title.Size = UDim2.new(1, -20, 0, 38)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBlack
		title.TextSize = 24
		title.TextColor3 = Color3.fromRGB(255, 215, 75)
		title.Text = "GERBANG AREA SANDY"
		title.Parent = frame

		local req1 = Instance.new("TextLabel")
		req1.Position = UDim2.fromOffset(10, 56)
		req1.Size = UDim2.new(1, -20, 0, 26)
		req1.BackgroundTransparency = 1
		req1.Font = Enum.Font.GothamBold
		req1.TextSize = 15
		req1.TextColor3 = Color3.fromRGB(240, 245, 255)
		req1.Text = "Syarat 1: Memiliki Iron Shovel atau Lebih Tinggi"
		req1.Parent = frame

		local req2 = Instance.new("TextLabel")
		req2.Position = UDim2.fromOffset(10, 86)
		req2.Size = UDim2.new(1, -20, 0, 26)
		req2.BackgroundTransparency = 1
		req2.Font = Enum.Font.GothamBold
		req2.TextSize = 15
		req2.TextColor3 = Color3.fromRGB(240, 245, 255)
		req2.Text = "Syarat 2: Membayar 10.000 Coin"
		req2.Parent = frame

		local status = Instance.new("TextLabel")
		status.Name = "StatusLabel"
		status.Position = UDim2.fromOffset(10, 120)
		status.Size = UDim2.new(1, -20, 0, 32)
		status.BackgroundTransparency = 1
		status.Font = Enum.Font.GothamBlack
		status.TextSize = 18
		status.TextColor3 = Color3.fromRGB(255, 100, 100)
		status.Text = "[TERKUNCI] Dekati Padlock untuk Buka"
		status.Parent = frame
	end

	-- Setup ProximityPrompt on Padlock
	local promptPart = padlock or signboard
	if promptPart and not promptPart:FindFirstChild("UnlockSandyGatePrompt") then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "UnlockSandyGatePrompt"
		prompt.ObjectText = "Gerbang Sandy"
		prompt.ActionText = "Buka Gerbang (10,000 Coin & Iron Shovel+)"
		prompt.HoldDuration = 1.0
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt.Parent = promptPart

		prompt.Triggered:Connect(function(player: Player)
			local result = TutorialService.UnlockSandyGate(player)
			if not result.Success then
				Remotes.GetEvent("StateSync"):FireClient(player, {
					NotificationMessage = result.Message or "Syarat belum terpenuhi!",
				})
			end
		end)
	end

	-- Ensure Coming Soon Placeholder in LockedArea_Sand
	local lockedSand = sandyGateFolder:FindFirstChild("LockedArea_Sand") :: BasePart?
	if lockedSand and not lockedSand:FindFirstChild("ComingSoonBillboard") then
		local bb = Instance.new("BillboardGui")
		bb.Name = "ComingSoonBillboard"
		bb.Size = UDim2.fromOffset(400, 140)
		bb.StudsOffset = Vector3.new(0, 8, 0)
		bb.AlwaysOnTop = false
		bb.MaxDistance = 80
		bb.Parent = lockedSand

		local card = Instance.new("Frame")
		card.Size = UDim2.fromScale(1, 1)
		card.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
		card.BackgroundTransparency = 0.15
		card.BorderSizePixel = 0
		card.Parent = bb

		local cCorner = Instance.new("UICorner")
		cCorner.CornerRadius = UDim.new(0, 12)
		cCorner.Parent = card

		local cStroke = Instance.new("UIStroke")
		cStroke.Color = Color3.fromRGB(245, 195, 65)
		cStroke.Thickness = 2
		cStroke.Parent = card

		local csTitle = Instance.new("TextLabel")
		csTitle.Position = UDim2.fromOffset(10, 10)
		csTitle.Size = UDim2.new(1, -20, 0, 36)
		csTitle.BackgroundTransparency = 1
		csTitle.Font = Enum.Font.GothamBlack
		csTitle.TextSize = 22
		csTitle.TextColor3 = Color3.fromRGB(255, 215, 65)
		csTitle.Text = "AREA SANDY - COMING SOON!"
		csTitle.Parent = card

		local csDesc = Instance.new("TextLabel")
		csDesc.Position = UDim2.fromOffset(10, 50)
		csDesc.Size = UDim2.new(1, -20, 0, 70)
		csDesc.BackgroundTransparency = 1
		csDesc.Font = Enum.Font.GothamBold
		csDesc.TextSize = 13
		csDesc.TextColor3 = Color3.fromRGB(230, 235, 245)
		csDesc.TextWrapped = true
		csDesc.Text = "Area gurun pasir dengan gundukan baru dan harta misterius sedang dalam tahap pengembangan (v2)."
		csDesc.Parent = card
	end
end

-- =====================================================================
-- Lifecycle & Remotes
-- =====================================================================

function TutorialService.Start()
	if started then
		return
	end
	started = true

	TutorialService.EnsureSandyGateInWorkspace()

	Remotes.OnServerInvoke("UnlockSandyGate", function(player: Player)
		return TutorialService.UnlockSandyGate(player)
	end)

	Remotes.GetEvent("AdvanceTutorial").OnServerEvent:Connect(function(player: Player, step: any)
		if type(step) == "number" then
			if step >= 5 then
				TutorialService.CompleteTutorial(player)
			else
				TutorialService.AdvanceTutorialStep(player, step)
			end
		end
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		local profile = PlayerState.Get(player)
		if profile then
			ensureTutorialTable(profile)
			player:SetAttribute("TutorialStep", profile.Tutorial.Step or 1)
			player:SetAttribute("TutorialDone", profile.Tutorial.Done == true)
			player:SetAttribute("SandyGateUnlocked", profile.SandyGateUnlocked == true)
		end
	end)
end

return TutorialService
