--!strict
-- Client controller for Onboarding Tutorial (steps 1-5, directional guidance, and top guide banner) (Step 14)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))

local LocalPlayer = Players.LocalPlayer

local TutorialController = {}

local screenGui: ScreenGui? = nil
local bannerFrame: Frame? = nil
local stepBadge: TextLabel? = nil
local instructionLabel: TextLabel? = nil
local finishButton: TextButton? = nil

local pointerModel: Part? = nil
local pointerAttachment: Attachment? = nil
local pointerBillboard: BillboardGui? = nil

local currentStep: number = 1
local isDone: boolean = false
local started: boolean = false

local stepInstructions = {
	[1] = {
		Badge = "LANGKAH 1 / 5",
		Text = "Gali gundukan kecil pertama kamu menggunakan Rusty Shovel!",
		TargetName = "SmallMound",
	},
	[2] = {
		Badge = "LANGKAH 2 / 5",
		Text = "Bagus! Bawa hasil galianmu dan jual ke Merchant di Hub atau Base!",
		TargetName = "ItemMerchant",
	},
	[3] = {
		Badge = "LANGKAH 3 / 5",
		Text = "Pergi ke Base kamu (lewat Teleport Pad) & taruh Telur Starter di inkubator!",
		TargetName = "TeleportPad",
	},
	[4] = {
		Badge = "LANGKAH 4 / 5",
		Text = "Buka Pet Bag (tombol PETS), equip pet barumu, lalu gali gundukan bersama!",
		TargetName = "EquipPetAndDig",
	},
	[5] = {
		Badge = "LANGKAH 5 / 5",
		Text = "Hebat! Kunjungi Shovel Shop untuk Stone Shovel & cek Quest Harian (tombol QUEST)!",
		TargetName = "ShovelShopAndQuest",
	},
}

local function findCurrentTargetPosition(): Vector3?
	local plain = workspace:FindFirstChild("Plain")
	if not plain then
		return nil
	end

	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local myPos = if root then root.Position else Vector3.zero

	if currentStep == 1 or currentStep == 4 then
		-- Nearest small mound
		local digField = plain:FindFirstChild("DigField")
		local nearestPos: Vector3? = nil
		local nearestDist = math.huge
		if digField then
			for _, moundPart in ipairs(digField:GetChildren()) do
				if moundPart:IsA("BasePart") then
					local dist = (moundPart.Position - myPos).Magnitude
					if dist < nearestDist then
						nearestDist = dist
						nearestPos = moundPart.Position + Vector3.new(0, 4.5, 0)
					end
				end
			end
		end
		return nearestPos or (myPos + Vector3.new(0, 5, 15))
	elseif currentStep == 2 then
		-- Hub Item Merchant
		local merchantFolder = plain:FindFirstChild("Merchant")
		local hubCounter = merchantFolder and merchantFolder:FindFirstChild("ItemMerchant_Counter") :: BasePart?
		if hubCounter then
			return hubCounter.Position + Vector3.new(0, 5, 0)
		end
		return Vector3.new(-20, 7, -86.5)
	elseif currentStep == 3 then
		-- HubBaseTeleportPad
		local pad = plain:FindFirstChild("HubBaseTeleportPad") :: BasePart?
		if pad then
			return pad.Position + Vector3.new(0, 4, 0)
		end
		return Vector3.new(0, 4, -28)
	elseif currentStep == 5 then
		-- Shovel Shop / Hub Plaza area
		return Vector3.new(0, 6, 0)
	end

	return nil
end

local function updatePointerVisual()
	if isDone then
		if pointerModel then
			pointerModel.Transparency = 1
			if pointerBillboard then
				pointerBillboard.Enabled = false
			end
		end
		return
	end

	local targetPos = findCurrentTargetPosition()
	if not targetPos then
		if pointerBillboard then
			pointerBillboard.Enabled = false
		end
		return
	end

	if not pointerModel or pointerModel.Parent == nil then
		local part = Instance.new("Part")
		part.Name = "TutorialPointer"
		part.Size = Vector3.new(1.5, 1.5, 1.5)
		part.Anchored = true
		part.CanCollide = false
		part.CastShadow = false
		part.Transparency = 1
		part.Parent = workspace
		pointerModel = part

		local bb = Instance.new("BillboardGui")
		bb.Name = "PointerGui"
		bb.Size = UDim2.fromOffset(80, 80)
		bb.StudsOffset = Vector3.new(0, 1.5, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 250
		bb.Parent = part
		pointerBillboard = bb

		local arrow = Instance.new("TextLabel")
		arrow.Name = "Arrow"
		arrow.Size = UDim2.fromScale(1, 1)
		arrow.BackgroundTransparency = 1
		arrow.Font = Enum.Font.GothamBlack
		arrow.TextSize = 34
		arrow.TextColor3 = Color3.fromRGB(255, 220, 60)
		arrow.TextStrokeColor3 = Color3.fromRGB(30, 20, 0)
		arrow.TextStrokeTransparency = 0.2
		arrow.Text = "V"
		arrow.Parent = bb
	end

	if pointerModel and targetPos then
		pointerModel.CFrame = CFrame.new(targetPos)
		if pointerBillboard then
			pointerBillboard.Enabled = true
		end
	end
end

local function updateBannerUI()
	if not bannerFrame then
		return
	end

	if isDone then
		bannerFrame.Visible = false
		if pointerBillboard then
			pointerBillboard.Enabled = false
		end
		return
	end

	bannerFrame.Visible = true
	local info = stepInstructions[currentStep] or stepInstructions[1]

	if stepBadge then
		stepBadge.Text = info.Badge
	end
	if instructionLabel then
		instructionLabel.Text = info.Text
	end
	if finishButton then
		finishButton.Visible = (currentStep == 5)
	end
end

local function buildUI()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("TutorialGui")
	if existing and existing:IsA("ScreenGui") then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "TutorialGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 14
	gui.IgnoreGuiInset = false
	gui.Parent = playerGui
	screenGui = gui

	-- Top Guide Banner
	local banner = Instance.new("Frame")
	banner.Name = "TutorialBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 54)
	banner.Size = UDim2.fromOffset(560, 64)
	banner.BackgroundColor3 = Color3.fromRGB(22, 26, 36)
	banner.BackgroundTransparency = 0.08
	banner.BorderSizePixel = 0
	banner.Visible = not isDone
	banner.Parent = gui
	bannerFrame = banner

	local bCorner = Instance.new("UICorner")
	bCorner.CornerRadius = UDim.new(0, 12)
	bCorner.Parent = banner

	local bStroke = Instance.new("UIStroke")
	bStroke.Color = Color3.fromRGB(255, 215, 65)
	bStroke.Thickness = 2
	bStroke.Parent = banner

	-- Step Badge
	local badge = Instance.new("TextLabel")
	badge.Name = "StepBadge"
	badge.Position = UDim2.fromOffset(14, 10)
	badge.Size = UDim2.fromOffset(116, 22)
	badge.BackgroundColor3 = Color3.fromRGB(248, 195, 48)
	badge.BorderSizePixel = 0
	badge.Font = Enum.Font.GothamBlack
	badge.TextSize = 11
	badge.TextColor3 = Color3.fromRGB(36, 24, 6)
	badge.Text = "LANGKAH 1 / 5"
	badge.Parent = banner
	stepBadge = badge

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 6)
	badgeCorner.Parent = badge

	-- Instruction Text
	local instLbl = Instance.new("TextLabel")
	instLbl.Name = "Instruction"
	instLbl.Position = UDim2.fromOffset(14, 34)
	instLbl.Size = UDim2.new(1, -140, 0, 24)
	instLbl.BackgroundTransparency = 1
	instLbl.Font = Enum.Font.GothamBold
	instLbl.TextSize = 13
	instLbl.TextColor3 = Color3.fromRGB(246, 248, 255)
	instLbl.TextXAlignment = Enum.TextXAlignment.Left
	instLbl.TextTruncate = Enum.TextTruncate.AtEnd
	instLbl.Text = stepInstructions[1].Text
	instLbl.Parent = banner
	instructionLabel = instLbl

	-- Finish Button (Step 5)
	local finishBtn = Instance.new("TextButton")
	finishBtn.Name = "FinishButton"
	finishBtn.AnchorPoint = Vector2.new(1, 0.5)
	finishBtn.Position = UDim2.new(1, -12, 0.5, 0)
	finishBtn.Size = UDim2.fromOffset(108, 40)
	finishBtn.BackgroundColor3 = Color3.fromRGB(72, 198, 128)
	finishBtn.BorderSizePixel = 0
	finishBtn.Font = Enum.Font.GothamBlack
	finishBtn.TextSize = 13
	finishBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	finishBtn.Text = "SELESAI"
	finishBtn.Visible = false
	finishBtn.Parent = banner
	finishButton = finishBtn

	local fCorner = Instance.new("UICorner")
	fCorner.CornerRadius = UDim.new(0, 8)
	fCorner.Parent = finishBtn

	finishBtn.Activated:Connect(function()
		Remotes.GetEvent("AdvanceTutorial"):FireServer(5)
		isDone = true
		updateBannerUI()
	end)

	updateBannerUI()
end

function TutorialController.GetStep(): (number, boolean)
	return currentStep, isDone
end

function TutorialController.Start()
	if started then
		return
	end
	started = true

	local attrStep = LocalPlayer:GetAttribute("TutorialStep")
	local attrDone = LocalPlayer:GetAttribute("TutorialDone")
	if type(attrStep) == "number" then
		currentStep = attrStep
	end
	if type(attrDone) == "boolean" then
		isDone = attrDone
	end

	buildUI()

	LocalPlayer:GetAttributeChangedSignal("TutorialStep"):Connect(function()
		local nextStep = LocalPlayer:GetAttribute("TutorialStep")
		if type(nextStep) == "number" then
			currentStep = nextStep
			updateBannerUI()
			updatePointerVisual()
		end
	end)

	LocalPlayer:GetAttributeChangedSignal("TutorialDone"):Connect(function()
		local doneVal = LocalPlayer:GetAttribute("TutorialDone")
		if type(doneVal) == "boolean" then
			isDone = doneVal
			updateBannerUI()
			updatePointerVisual()
		end
	end)

	Remotes.GetEvent("StateSync").OnClientEvent:Connect(function(snapshot: any)
		if type(snapshot) == "table" and type(snapshot.Tutorial) == "table" then
			local t = snapshot.Tutorial
			if type(t.Step) == "number" then
				currentStep = t.Step
			end
			if type(t.Done) == "boolean" then
				isDone = t.Done
			end
			updateBannerUI()
			updatePointerVisual()
		end
	end)

	-- Pointer update heartbeat (every 0.5s)
	task.spawn(function()
		while not isDone do
			task.wait(0.5)
			if not isDone then
				updatePointerVisual()
			end
		end
	end)
end

return TutorialController
