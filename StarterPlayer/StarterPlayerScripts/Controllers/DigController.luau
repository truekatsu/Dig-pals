--!strict
-- Client controller for click-to-start digging minigame, jump suppression, strike feedback, and full-bag lock (Steps 4-6)

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Weighted = require(Shared:WaitForChild("Util"):WaitForChild("Weighted"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local AssetIds = require(Shared:WaitForChild("AssetIds"))
local MoundsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Mounds"))
local ShovelsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Shovels"))
local DigTiming = require(Shared:WaitForChild("Util"):WaitForChild("DigTiming"))

local MoundVisuals = require(script.Parent:WaitForChild("MoundVisuals"))
local InventoryController = require(script.Parent:WaitForChild("InventoryController"))
local HudController = require(script.Parent:WaitForChild("HudController"))
local MerchantController = require(script.Parent:WaitForChild("MerchantController"))
local ShovelShopController = require(script.Parent:WaitForChild("ShovelShopController"))
local FxController = require(script.Parent:WaitForChild("FxController"))
local InputController = require(script.Parent:WaitForChild("InputController"))
local DigFocusController = require(script.Parent:WaitForChild("DigFocusController"))

local LocalPlayer = Players.LocalPlayer

local DigController = {}

local STRIKE_ACTION_NAME = "DigPalsMinigameStrikeAction"
local CANCEL_ACTION_NAME = "DigPalsMinigameCancelAction"

local activeMoundId: string? = nil
local activeMoundSize: string = "Small"
local bagFullLockedMoundId: string? = nil
local sessionStartTime: number = 0
local barSpeed: number = MoundsConfig.Sizes.Small.Timing.Speed
local goodWidth: number = MoundsConfig.Sizes.Small.Timing.GoodWidth
local perfectWidth: number = MoundsConfig.Sizes.Small.Timing.PerfectWidth
local nextAllowedStrikeTime: number = 0
local feedbackVersion: number = 0
local zoneCenter = 0.5
local misses = 0
local maxMisses = 3
local sessionReady = false
local awaitingStrike = false
local started = false

-- UI references
local screenGui: ScreenGui? = nil
local hudContainer: Frame? = nil
local timingBarTrack: Frame? = nil
local goodZoneFrame: Frame? = nil
local perfectZoneFrame: Frame? = nil
local indicatorFrame: Frame? = nil
local digButton: TextButton? = nil
local feedbackLabel: TextLabel? = nil
local hintToastLabel: TextLabel? = nil
local resolveFill: Frame? = nil
local resolveHeart: TextLabel? = nil
local resolveLabel: TextLabel? = nil

local function updateResolve()
	local ratio = math.clamp(1 - misses / maxMisses, 0, 1)
	if resolveFill then resolveFill.Size = UDim2.fromScale(ratio, 1) end
	if resolveHeart then resolveHeart.Position = UDim2.fromScale(ratio, 0.5) end
	if resolveLabel then resolveLabel.Text = string.format("%d MISS TERSISA", math.max(0, maxMisses - misses)) end
end

local function isAnyModalOpen(): boolean
	return InputController.IsAnyModalOpen()
end

local function isShovelHeld(): boolean
	if LocalPlayer:GetAttribute("ShovelToolActive") == true then
		return true
	end
	local character = LocalPlayer.Character
	if character then
		for _, child in character:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("DigPalsShovelTool") == true then
				return true
			end
		end
	end
	return false
end

local function getEquippedShovelCooldown(): number
	local equippedId = LocalPlayer:GetAttribute("EquippedShovel")
	if type(equippedId) == "string" and ShovelsConfig.All[equippedId] then
		return ShovelsConfig.All[equippedId].DigSpeed
	end
	return ShovelsConfig.All.RustyShovel.DigSpeed
end

local function setCharacterJumpEnabled(enabled: boolean)
	local character = LocalPlayer.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, enabled)
		if not enabled then
			humanoid.Jump = false
		end
	end
end

local function updateZoneLayout()
	if not goodZoneFrame or not perfectZoneFrame then
		return
	end
	goodZoneFrame.Size = UDim2.fromScale(goodWidth, 1)
	goodZoneFrame.Position = UDim2.fromScale(zoneCenter - (goodWidth * 0.5), 0)

	perfectZoneFrame.Size = UDim2.fromScale(perfectWidth, 1)
	perfectZoneFrame.Position = UDim2.fromScale(zoneCenter - (perfectWidth * 0.5), 0)
end

local function applyMinigame(state: any)
	if type(state) ~= "table" then return end
	sessionStartTime = state.StartTime
	barSpeed, goodWidth, perfectWidth = state.Speed, state.GoodWidth, state.PerfectWidth
	zoneCenter, misses, maxMisses = state.ZoneCenter, state.Misses, state.MaxMisses
	updateZoneLayout()
	updateResolve()
end

local function applyMoundTimingConfig(sizeName: string)
	if sizeName == "Shared" or sizeName == "Rare" then
		local timing = MoundsConfig.Shared.Timing
		barSpeed = timing.Speed
		goodWidth = timing.GoodWidth
		perfectWidth = timing.PerfectWidth
		updateZoneLayout()
		return
	end
	local sizeConfig = (MoundsConfig.Sizes :: any)[sizeName] or MoundsConfig.Sizes.Small
	barSpeed = sizeConfig.Timing.Speed
	goodWidth = sizeConfig.Timing.GoodWidth
	perfectWidth = sizeConfig.Timing.PerfectWidth
	updateZoneLayout()
end

local function showHintToast(message: string, color: Color3?)
	if not hintToastLabel then
		return
	end
	hintToastLabel.Text = message
	hintToastLabel.TextColor3 = color or Color3.fromRGB(255, 225, 130)
	hintToastLabel.TextTransparency = 0
	hintToastLabel.BackgroundTransparency = 1

	task.delay(1.8, function()
		if hintToastLabel and hintToastLabel.Text == message then
			TweenService:Create(hintToastLabel, TweenInfo.new(0.4), {
				TextTransparency = 1,
				BackgroundTransparency = 1,
			}):Play()
		end
	end)
end

local function clearBagFullLockedState()
	if not bagFullLockedMoundId then
		return
	end
	bagFullLockedMoundId = nil
	if not activeMoundId then
		MoundVisuals.SetSelectedMound(nil)
		if hudContainer then
			hudContainer.Visible = false
		end
		if feedbackLabel then
			feedbackLabel.Visible = false
		end
	end
end

local function showBagFullLockedState(moundId: string, moundSize: string)
	DigFocusController.Exit()
	MoundVisuals.SetDiggingMound(nil)
	activeMoundId = nil
	bagFullLockedMoundId = moundId
	applyMoundTimingConfig(moundSize)
	MoundVisuals.SetSelectedMound(moundId)

	if timingBarTrack then
		timingBarTrack.Visible = false
	end
	if digButton then
		digButton.Active = false
		digButton.AutoButtonColor = false
		digButton.BackgroundColor3 = Color3.fromRGB(146, 52, 58)
		digButton.Text = "TAS PENUH"
	end
	if feedbackLabel then
		feedbackVersion += 1
		feedbackLabel.Visible = true
		feedbackLabel.TextColor3 = Color3.fromRGB(255, 132, 132)
		feedbackLabel.Text = "Tas penuh! Jual item di Merchant."
		feedbackLabel.TextTransparency = 0
		feedbackLabel.BackgroundTransparency = 0.2
	end
	if hudContainer then
		hudContainer.Visible = true
	end
	showHintToast("Tas penuh! Kunjungi Item Merchant di Hub atau Base.")
end

local function handleMinigameAction(
	_actionName: string,
	inputState: Enum.UserInputState,
	_inputObject: InputObject
): Enum.ContextActionResult
	if not activeMoundId then
		return Enum.ContextActionResult.Pass
	end
	if inputState == Enum.UserInputState.Begin then
		DigController.AttemptStrike()
	end
	return Enum.ContextActionResult.Sink
end

local function bindMinigameControls()
	setCharacterJumpEnabled(false)
	ContextActionService:BindActionAtPriority(
		CANCEL_ACTION_NAME,
		function(_, state)
			if not activeMoundId then return Enum.ContextActionResult.Pass end
			if state == Enum.UserInputState.Begin then DigController.StopMinigame(true) end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value + 501,
		Enum.KeyCode.X,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.Escape
	)
	ContextActionService:BindActionAtPriority(
		STRIKE_ACTION_NAME,
		handleMinigameAction,
		false,
		Enum.ContextActionPriority.High.Value + 500,
		Enum.KeyCode.Space,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.ButtonR2
	)
end

local function unbindMinigameControls()
	ContextActionService:UnbindAction(STRIKE_ACTION_NAME)
	ContextActionService:UnbindAction(CANCEL_ACTION_NAME)
	setCharacterJumpEnabled(true)
end

function DigController.StopMinigame(notifyServer: boolean)
	DigFocusController.Exit()
	unbindMinigameControls()
	sessionReady, awaitingStrike = false, false
	MoundVisuals.SetDiggingMound(nil)
	bagFullLockedMoundId = nil
	if not activeMoundId then
		if hudContainer then
			hudContainer.Visible = false
		end
		return
	end
	activeMoundId = nil
	MoundVisuals.SetSelectedMound(nil)

	if hudContainer then
		hudContainer.Visible = false
	end
	if feedbackLabel then
		feedbackLabel.Visible = false
	end

	if notifyServer then
		Remotes.GetEvent("CancelDig"):FireServer()
	end
end

local function isCharacterWithinRangeOf(targetPos: Vector3?, maxDistance: number?): boolean
	if not targetPos then
		return false
	end
	local character = LocalPlayer.Character
	if not character then
		return false
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end
	local dx = rootPart.Position.X - targetPos.X
	local dz = rootPart.Position.Z - targetPos.Z
	local horizDist = math.sqrt(dx * dx + dz * dz)
	local limit = maxDistance or MoundsConfig.DigRangeStuds
	return horizDist <= limit
end

function DigController.StartMinigameOnMound(moundId: string, moundSize: string, moundPos: Vector3)
	if isAnyModalOpen() then
		return
	end

	-- Inverted logic: Shovel MUST be held to dig; cannot dig without shovel
	if not isShovelHeld() then
		showHintToast("Pegang sekop terlebih dahulu untuk menggali! [Tekan 1]")
		return
	end

	local isShared = (moundSize == "Shared" or moundSize == "Rare" or MoundVisuals.IsSharedMound(moundId))
	local allowedRange = if isShared
		then (MoundsConfig.Shared.Scale.X * 0.5) + MoundsConfig.DigRangeStuds
		else MoundsConfig.DigRangeStuds

	if not isCharacterWithinRangeOf(moundPos, allowedRange) then
		showHintToast("Gundukan terlalu jauh!!", Color3.fromRGB(113, 205, 255))
		return
	end

	-- If already digging THIS mound, clicking it again triggers a strike (even if bag became full mid-mound)
	if activeMoundId == moundId then
		DigController.AttemptStrike()
		return
	end

	-- Step 6: Block starting a NEW mound when Item Bag is full; disable Gali button with "Tas penuh" message
	if HudController.IsBagFull() then
		unbindMinigameControls()
		showBagFullLockedState(moundId, moundSize)
		return
	end

	bagFullLockedMoundId = nil
	activeMoundId = moundId
	sessionReady, awaitingStrike = false, false
	MoundVisuals.SetDiggingMound(nil)
	activeMoundSize = moundSize
	sessionStartTime = workspace:GetServerTimeNow()
	applyMoundTimingConfig(moundSize)
	local equipped = LocalPlayer:GetAttribute("EquippedShovel")
	applyMinigame(DigTiming.New(if type(equipped) == "string" then equipped else "RustyShovel", moundSize, sessionStartTime))
	MoundVisuals.SetSelectedMound(moundId)
	bindMinigameControls()

	if timingBarTrack then
		timingBarTrack.Visible = true
	end
	if digButton then
		digButton.Active = true
		digButton.AutoButtonColor = true
	end
	if feedbackLabel then
		feedbackLabel.Text = ""
		feedbackLabel.Visible = false
	end
	if hudContainer then
		hudContainer.Visible = true
	end

	if screenGui then DigFocusController.Enter(screenGui) end
	Remotes.GetEvent("StartDig"):FireServer(moundId)
end

function DigController.AttemptStrike()
	if not activeMoundId or not sessionReady or awaitingStrike or isAnyModalOpen() then
		return
	end

	if not isShovelHeld() then
		showHintToast("Pegang sekop terlebih dahulu untuk menggali! [Tekan 1]")
		return
	end

	local serverNow = workspace:GetServerTimeNow()
	if serverNow < nextAllowedStrikeTime then
		return
	end
	nextAllowedStrikeTime = serverNow + getEquippedShovelCooldown()
	awaitingStrike = true
	Remotes.GetEvent("Strike"):FireServer(activeMoundId)
end

local function showStrikeFeedback(grade: string, damage: number)
	if not feedbackLabel then
		return
	end

	feedbackVersion += 1
	local currentVersion = feedbackVersion

	local color = AssetIds.Colors.ZoneMiss
	local labelText = "MISS!"
	if grade == "Perfect" then
		color = AssetIds.Colors.ZonePerfect
		labelText = string.format("PERFECT! (-%d HP)", math.floor(damage))
		FxController.PlayPerfectStrikeFx()
	elseif grade == "Good" then
		color = AssetIds.Colors.ZoneGood
		labelText = string.format("GOOD (-%d HP)", math.floor(damage))
	end

	feedbackLabel.Visible = true
	feedbackLabel.TextColor3 = color
	feedbackLabel.Text = labelText
	feedbackLabel.TextTransparency = 0
	feedbackLabel.BackgroundTransparency = 1

	task.delay(0.75, function()
		if feedbackVersion == currentVersion and feedbackLabel then
			TweenService:Create(feedbackLabel, TweenInfo.new(0.25), {
				TextTransparency = 1,
				BackgroundTransparency = 1,
			}):Play()
		end
	end)
end

local function createDigUI()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("DigTimingGui")
	if existing then existing:Destroy() end
	local gui = Instance.new("ScreenGui")
	gui.Name = "DigTimingGui"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	screenGui = gui
	gui.AncestryChanged:Connect(function()
		if gui.Parent == nil and activeMoundId then DigController.StopMinigame(true) end
	end)

	local toast = Instance.new("TextLabel")
	toast.Name = "HintToast"
	toast.AnchorPoint = Vector2.new(0.5, 1)
	toast.Position = UDim2.new(0.5, 0, 1, -268)
	toast.Size = UDim2.new(0.9, 0, 0, 32)
	toast.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
	toast.BackgroundTransparency = 1
	toast.Font = Enum.Font.GothamBold
	toast.TextSize = 15
	toast.TextColor3 = Color3.fromRGB(255, 225, 130)
	toast.TextStrokeTransparency = 0
	toast.TextTransparency = 1
	toast.Text = ""
	toast.Parent = gui
	hintToastLabel = toast

	local container = Instance.new("Frame")
	container.Name = "DigContainer"
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.new(0.5, 0, 1, -104)
	container.Size = UDim2.new(0.84, 0, 0, 154)
	container.BackgroundTransparency = 1
	container.Visible = false
	container.Parent = gui
	hudContainer = container
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(920, 154)
	limit.Parent = container

	local feedback = Instance.new("TextLabel")
	feedback.Name = "FeedbackLabel"
	feedback.AnchorPoint = Vector2.new(0.5, 0)
	feedback.Position = UDim2.fromScale(0.5, 0)
	feedback.Size = UDim2.new(1, 0, 0, 26)
	feedback.BackgroundTransparency = 1
	feedback.Font = Enum.Font.GothamBlack
	feedback.TextSize = 18
	feedback.TextColor3 = Color3.new(1, 1, 1)
	feedback.TextStrokeTransparency = 0
	feedback.Text = ""
	feedback.Visible = false
	feedback.Parent = container
	feedbackLabel = feedback

	local track = Instance.new("Frame")
	track.Name = "TimingBarTrack"
	track.Position = UDim2.fromOffset(0, 36)
	track.Size = UDim2.new(1, 0, 0, 58)
	track.BackgroundColor3 = Color3.fromRGB(13, 13, 15)
	track.BackgroundTransparency = 0.08
	track.BorderSizePixel = 0
	track.Parent = container
	timingBarTrack = track
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = track
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(93, 96, 93)
	stroke.Thickness = 2
	stroke.Parent = track

	local goodZone = Instance.new("Frame")
	goodZone.Name = "GoodZone"
	goodZone.BackgroundColor3 = Color3.fromRGB(105, 95, 60)
	goodZone.BackgroundTransparency = 0.32
	goodZone.BorderSizePixel = 0
	goodZone.ZIndex = 2
	goodZone.Parent = track
	goodZoneFrame = goodZone
	local perfectZone = Instance.new("Frame")
	perfectZone.Name = "PerfectZone"
	perfectZone.BackgroundColor3 = Color3.fromRGB(228, 196, 99)
	perfectZone.BackgroundTransparency = 0.16
	perfectZone.BorderSizePixel = 0
	perfectZone.ZIndex = 3
	perfectZone.Parent = track
	perfectZoneFrame = perfectZone

	local indicator = Instance.new("Frame")
	indicator.Name = "Indicator"
	indicator.AnchorPoint = Vector2.new(0.5, 0.5)
	indicator.Position = UDim2.fromScale(0, 0.5)
	indicator.Size = UDim2.fromOffset(10, 76)
	indicator.BackgroundColor3 = Color3.fromRGB(224, 236, 233)
	indicator.BorderSizePixel = 0
	indicator.ZIndex = 5
	indicator.Parent = track
	indicatorFrame = indicator
	local indCorner = Instance.new("UICorner")
	indCorner.CornerRadius = UDim.new(1, 0)
	indCorner.Parent = indicator
	local indStroke = Instance.new("UIStroke")
	indStroke.Color = Color3.fromRGB(32, 39, 37)
	indStroke.Thickness = 2
	indStroke.Parent = indicator

	local rail = Instance.new("Frame")
	rail.Name = "ResolveTrack"
	rail.Position = UDim2.new(0, 12, 0, 115)
	rail.Size = UDim2.new(1, -24, 0, 8)
	rail.BackgroundColor3 = Color3.fromRGB(23, 23, 25)
	rail.BorderSizePixel = 0
	rail.Parent = container
	local railCorner = Instance.new("UICorner")
	railCorner.CornerRadius = UDim.new(1, 0)
	railCorner.Parent = rail
	local fill = Instance.new("Frame")
	fill.Name = "ResolveFill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(213, 66, 70)
	fill.BorderSizePixel = 0
	fill.Parent = rail
	resolveFill = fill
	local fillCorner = railCorner:Clone()
	fillCorner.Parent = fill
	local heart = Instance.new("TextLabel")
	heart.Name = "ResolveHeart"
	heart.AnchorPoint = Vector2.new(0.5, 0.5)
	heart.Size = UDim2.fromOffset(36, 36)
	heart.BackgroundTransparency = 1
	heart.Font = Enum.Font.GothamBlack
	heart.Text = "♥"
	heart.TextSize = 34
	heart.TextColor3 = Color3.fromRGB(255, 76, 82)
	heart.TextStrokeTransparency = 0.35
	heart.ZIndex = 4
	heart.Parent = rail
	resolveHeart = heart
	local remaining = Instance.new("TextLabel")
	remaining.Name = "MissesLeft"
	remaining.Position = UDim2.fromOffset(0, 136)
	remaining.Size = UDim2.new(0.5, 0, 0, 18)
	remaining.BackgroundTransparency = 1
	remaining.Font = Enum.Font.GothamBold
	remaining.TextSize = 11
	remaining.TextColor3 = Color3.fromRGB(255, 176, 178)
	remaining.TextStrokeTransparency = 0
	remaining.TextXAlignment = Enum.TextXAlignment.Left
	remaining.Parent = container
	resolveLabel = remaining

	-- The whole wide bar is the touch/mouse target; keyboard and controller still use the same action.
	local button = Instance.new("TextButton")
	button.Name = "DigButton"
	button.Position = UDim2.fromOffset(0, 28)
	button.Size = UDim2.new(1, 0, 0, 74)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.TextColor3 = Color3.new(1, 1, 1)
	button.AutoButtonColor = false
	button.ZIndex = 8
	button.Parent = container
	digButton = button
	local hint = Instance.new("TextLabel")
	hint.Name = "InputHint"
	hint.AnchorPoint = Vector2.new(1, 0)
	hint.Position = UDim2.new(1, 0, 0, 136)
	hint.Size = UDim2.new(0.5, 0, 0, 18)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamBold
	hint.TextSize = 11
	hint.TextColor3 = Color3.fromRGB(235, 235, 230)
	hint.TextStrokeTransparency = 0
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.Text = "GALI · SPACE / TAP"
	hint.Parent = container
	button.Activated:Connect(function()
		if button.Active then DigController.AttemptStrike() end
	end)
	local exitButton = Instance.new("TextButton")
	exitButton.Name = "ExitDigButton"
	exitButton.AnchorPoint = Vector2.new(1, 1)
	exitButton.Position = UDim2.new(1, 0, 0, -4)
	exitButton.Size = UDim2.fromOffset(120, 44)
	exitButton.BackgroundTransparency = 1
	exitButton.Font = Enum.Font.GothamBold
	exitButton.Text = "KELUAR [X]"
	exitButton.TextSize = 13
	exitButton.TextColor3 = Color3.fromRGB(235, 235, 230)
	exitButton.TextStrokeTransparency = 0
	exitButton.Parent = container
	exitButton.Activated:Connect(function() DigController.StopMinigame(true) end)
	updateZoneLayout()
	updateResolve()
end
function DigController.Start()
	if started then
		return
	end
	started = true

	createDigUI()

	MoundVisuals.OnMoundClicked(function(moundId: string, moundSize: string, moundPos: Vector3)
		DigController.StartMinigameOnMound(moundId, moundSize, moundPos)
	end)

	LocalPlayer.CharacterAdded:Connect(function()
		DigController.StopMinigame(true)
	end)
	LocalPlayer.CharacterRemoving:Connect(function()
		DigController.StopMinigame(true)
	end)

	Remotes.GetEvent("MoundDespawned").OnClientEvent:Connect(function(moundId: string)
		if activeMoundId == moundId then
			DigController.StopMinigame(false)
		elseif bagFullLockedMoundId == moundId then
			clearBagFullLockedState()
		end
	end)

	Remotes.GetEvent("StrikeResult").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.Event == "SessionStarted" then
			if payload.MoundId == activeMoundId then
				sessionReady, awaitingStrike = true, false
				MoundVisuals.SetDiggingMound(activeMoundId)
				sessionStartTime = tonumber(payload.StartTime) or workspace:GetServerTimeNow()
				barSpeed = tonumber(payload.Speed) or barSpeed
				goodWidth = tonumber(payload.GoodWidth) or goodWidth
				perfectWidth = tonumber(payload.PerfectWidth) or perfectWidth
				updateZoneLayout()
				applyMinigame(payload.Minigame)
			end
		elseif payload.Event == "StrikeHit" then
			if payload.MoundId ~= activeMoundId then return end
			awaitingStrike = false
			applyMinigame(payload.Minigame)
			local grade = tostring(payload.Grade or "Miss")
			local damage = tonumber(payload.Damage) or 0
			if type(payload.NextStrikeAllowedAt) == "number" then
				nextAllowedStrikeTime = payload.NextStrikeAllowedAt
			end
			showStrikeFeedback(grade, damage)
			if payload.Cleared == true then
				task.delay(0.35, function()
					if activeMoundId == payload.MoundId then
						DigController.StopMinigame(false)
					end
				end)
			end
		elseif payload.Event == "DigFailed" then
			if payload.MoundId ~= activeMoundId then return end
			DigController.StopMinigame(false)
			showHintToast("Gagal! Klik mound untuk mulai dari 0.")
		elseif payload.Event == "Rejected" then
			if payload.MoundId ~= activeMoundId then return end
			awaitingStrike = false
			if payload.Reason == "BagFull" then
				unbindMinigameControls()
				showBagFullLockedState(tostring(payload.MoundId or ""), activeMoundSize)
			elseif payload.Reason ~= "Cooldown" then
				DigController.StopMinigame(false)
			end
		end
	end)

	-- Inverted logic: If player puts away / unequips shovel while digging, cancel minigame immediately
	LocalPlayer:GetAttributeChangedSignal("ShovelToolActive"):Connect(function()
		if activeMoundId and not isShovelHeld() then
			DigController.StopMinigame(true)
			showHintToast("Penggalian dibatalkan karena sekop dilepas.")
		end
	end)
	LocalPlayer:GetAttributeChangedSignal("EquippedShovel"):Connect(function()
		if activeMoundId then DigController.StopMinigame(true) end
	end)

	-- Direct click/tap input for minigame strikes with shovel in hand
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or isAnyModalOpen() then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if activeMoundId and isShovelHeld() then
				DigController.AttemptStrike()
			end
		end
	end)

	-- Hook Shovel Tool.Activated on Character for native tool click integration
	local function hookCharacterTools(char: Model)
		for _, child in ipairs(char:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("DigPalsShovelTool") == true then
				child.Activated:Connect(function()
					if activeMoundId and isShovelHeld() and not isAnyModalOpen() then
						DigController.AttemptStrike()
					end
				end)
			end
		end
		char.ChildAdded:Connect(function(child)
			if child:IsA("Tool") and child:GetAttribute("DigPalsShovelTool") == true then
				child.Activated:Connect(function()
					if activeMoundId and isShovelHeld() and not isAnyModalOpen() then
						DigController.AttemptStrike()
					end
				end)
			end
		end)
	end

	if LocalPlayer.Character then
		hookCharacterTools(LocalPlayer.Character)
	end
	LocalPlayer.CharacterAdded:Connect(hookCharacterTools)

	RunService.RenderStepped:Connect(function()
		if bagFullLockedMoundId then
			local lockedPos = MoundVisuals.GetMoundPosition(bagFullLockedMoundId)
			if not lockedPos or not isCharacterWithinRangeOf(lockedPos) or not HudController.IsBagFull() or isAnyModalOpen() then
				clearBagFullLockedState()
			end
			return
		end

		if not activeMoundId then
			return
		end
		local character = LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			DigController.StopMinigame(true)
			return
		end

		if isAnyModalOpen() then
			DigController.StopMinigame(true)
			return
		end

		local moundPos, moundSize, isShared = MoundVisuals.GetMoundPosition(activeMoundId)
		local allowedRange = if isShared
			then (MoundsConfig.Shared.Scale.X * 0.5) + MoundsConfig.DigRangeStuds
			else MoundsConfig.DigRangeStuds
		if not moundPos or not isCharacterWithinRangeOf(moundPos, allowedRange) then
			DigController.StopMinigame(true)
			return
		end

		setCharacterJumpEnabled(false)

		if indicatorFrame and digButton then
			local now = workspace:GetServerTimeNow()
			local elapsed = math.max(0, now - sessionStartTime)
			local pos = Weighted.IndicatorPos(elapsed, barSpeed)
			indicatorFrame.Position = UDim2.fromScale(pos, 0.5)

			local onCooldown = now < nextAllowedStrikeTime or awaitingStrike or not sessionReady
			indicatorFrame.BackgroundTransparency = if onCooldown then 0.45 else 0
			digButton.Text = ""
			if hudContainer then
				local hint = hudContainer:FindFirstChild("InputHint")
				if hint and hint:IsA("TextLabel") then
					hint.Text = if not sessionReady then "MENYIAPKAN..." elseif onCooldown then "TUNGGU..." else "GALI · SPACE / TAP"
				end
			end
		end
	end)
end

return DigController
