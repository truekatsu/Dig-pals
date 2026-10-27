--!strict
-- Client controller for click-to-start digging minigame, jump suppression, strike feedback, and full-bag lock (Steps 4-6)

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Weighted = require(Shared:WaitForChild("Util"):WaitForChild("Weighted"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local AssetIds = require(Shared:WaitForChild("AssetIds"))
local MoundsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Mounds"))
local ShovelsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Shovels"))

local MoundVisuals = require(script.Parent:WaitForChild("MoundVisuals"))
local InventoryController = require(script.Parent:WaitForChild("InventoryController"))
local HudController = require(script.Parent:WaitForChild("HudController"))
local MerchantController = require(script.Parent:WaitForChild("MerchantController"))
local ShovelShopController = require(script.Parent:WaitForChild("ShovelShopController"))

local LocalPlayer = Players.LocalPlayer

local DigController = {}

local STRIKE_ACTION_NAME = "DigPalsMinigameStrikeAction"

local activeMoundId: string? = nil
local activeMoundSize: string = "Small"
local bagFullLockedMoundId: string? = nil
local sessionStartTime: number = 0
local barSpeed: number = MoundsConfig.Sizes.Small.Timing.Speed
local goodWidth: number = MoundsConfig.Sizes.Small.Timing.GoodWidth
local perfectWidth: number = MoundsConfig.Sizes.Small.Timing.PerfectWidth
local nextAllowedStrikeTime: number = 0
local feedbackVersion: number = 0
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

local function isAnyModalOpen(): boolean
	return InventoryController.IsOpen() or MerchantController.IsOpen() or ShovelShopController.IsOpen()
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
	goodZoneFrame.Position = UDim2.fromScale(0.5 - (goodWidth * 0.5), 0)

	perfectZoneFrame.Size = UDim2.fromScale(perfectWidth, 1)
	perfectZoneFrame.Position = UDim2.fromScale(0.5 - (perfectWidth * 0.5), 0)
end

local function applyMoundTimingConfig(sizeName: string)
	local sizeConfig = (MoundsConfig.Sizes :: any)[sizeName] or MoundsConfig.Sizes.Small
	barSpeed = sizeConfig.Timing.Speed
	goodWidth = sizeConfig.Timing.GoodWidth
	perfectWidth = sizeConfig.Timing.PerfectWidth
	updateZoneLayout()
end

local function showHintToast(message: string)
	if not hintToastLabel then
		return
	end
	hintToastLabel.Text = message
	hintToastLabel.TextTransparency = 0
	hintToastLabel.BackgroundTransparency = 0.25

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
	setCharacterJumpEnabled(true)
end

function DigController.StopMinigame(notifyServer: boolean)
	bagFullLockedMoundId = nil
	if not activeMoundId then
		if hudContainer then
			hudContainer.Visible = false
		end
		return
	end
	activeMoundId = nil
	MoundVisuals.SetSelectedMound(nil)
	unbindMinigameControls()

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

local function isCharacterWithinRangeOf(targetPos: Vector3): boolean
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
	return horizDist <= MoundsConfig.DigRangeStuds
end

function DigController.StartMinigameOnMound(moundId: string, moundSize: string, moundPos: Vector3)
	if isAnyModalOpen() then
		return
	end
	if not isCharacterWithinRangeOf(moundPos) then
		showHintToast("Dekati gundukan dulu (maks 8 studs) lalu klik!")
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
	activeMoundSize = moundSize
	sessionStartTime = workspace:GetServerTimeNow()
	applyMoundTimingConfig(moundSize)
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

	Remotes.GetEvent("StartDig"):FireServer(moundId)
end

function DigController.AttemptStrike()
	if not activeMoundId or isAnyModalOpen() then
		return
	end
	local serverNow = workspace:GetServerTimeNow()
	if serverNow < nextAllowedStrikeTime then
		return
	end
	nextAllowedStrikeTime = serverNow + getEquippedShovelCooldown()
	Remotes.GetEvent("Strike"):FireServer(activeMoundId)
end

local function showStrikeFeedback(grade: string, damage: number)
	if not feedbackLabel then
		return
	end

	feedbackVersion += 1
	local currentVersion = feedbackVersion

	local color = AssetIds.Colors.ZoneMiss
	local labelText = string.format("MISS (-%.1f HP)", damage)
	if grade == "Perfect" then
		color = AssetIds.Colors.ZonePerfect
		labelText = string.format("PERFECT! (-%d HP)", math.floor(damage))
	elseif grade == "Good" then
		color = AssetIds.Colors.ZoneGood
		labelText = string.format("GOOD (-%d HP)", math.floor(damage))
	end

	feedbackLabel.Visible = true
	feedbackLabel.TextColor3 = color
	feedbackLabel.Text = labelText
	feedbackLabel.TextTransparency = 0
	feedbackLabel.BackgroundTransparency = 0.25

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
	if existing and existing:IsA("ScreenGui") then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "DigTimingGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	screenGui = gui

	local toast = Instance.new("TextLabel")
	toast.Name = "HintToast"
	toast.AnchorPoint = Vector2.new(0.5, 1)
	toast.Position = UDim2.new(0.5, 0, 1, -242)
	toast.Size = UDim2.fromOffset(330, 32)
	toast.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
	toast.BackgroundTransparency = 1
	toast.Font = Enum.Font.GothamBold
	toast.TextSize = 14
	toast.TextColor3 = Color3.fromRGB(255, 225, 130)
	toast.TextTransparency = 1
	toast.Text = ""
	toast.Parent = gui
	hintToastLabel = toast

	local toastCorner = Instance.new("UICorner")
	toastCorner.CornerRadius = UDim.new(0, 8)
	toastCorner.Parent = toast

	local container = Instance.new("Frame")
	container.Name = "DigContainer"
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.new(0.5, 0, 1, -98)
	container.Size = UDim2.fromOffset(320, 134)
	container.BackgroundTransparency = 1
	container.Visible = false
	container.Parent = gui
	hudContainer = container

	local feedback = Instance.new("TextLabel")
	feedback.Name = "FeedbackLabel"
	feedback.AnchorPoint = Vector2.new(0.5, 0)
	feedback.Position = UDim2.fromScale(0.5, 0)
	feedback.Size = UDim2.fromOffset(290, 28)
	feedback.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
	feedback.BackgroundTransparency = 1
	feedback.Font = Enum.Font.GothamBlack
	feedback.TextSize = 15
	feedback.TextColor3 = Color3.fromRGB(255, 255, 255)
	feedback.TextStrokeTransparency = 0.2
	feedback.Text = ""
	feedback.Visible = false
	feedback.Parent = container
	feedbackLabel = feedback

	local fbCorner = Instance.new("UICorner")
	fbCorner.CornerRadius = UDim.new(0, 8)
	fbCorner.Parent = feedback

	local track = Instance.new("Frame")
	track.Name = "TimingBarTrack"
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.Position = UDim2.new(0.5, 0, 0, 36)
	track.Size = UDim2.fromOffset(290, 26)
	track.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
	track.BorderSizePixel = 0
	track.Parent = container
	timingBarTrack = track

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 8)
	trackCorner.Parent = track

	local trackStroke = Instance.new("UIStroke")
	trackStroke.Color = Color3.fromRGB(210, 210, 225)
	trackStroke.Thickness = 2
	trackStroke.Parent = track

	local goodZone = Instance.new("Frame")
	goodZone.Name = "GoodZone"
	goodZone.BackgroundColor3 = AssetIds.Colors.ZoneGood
	goodZone.BorderSizePixel = 0
	goodZone.ZIndex = 2
	goodZone.Parent = track
	goodZoneFrame = goodZone

	local perfectZone = Instance.new("Frame")
	perfectZone.Name = "PerfectZone"
	perfectZone.BackgroundColor3 = AssetIds.Colors.ZonePerfect
	perfectZone.BorderSizePixel = 0
	perfectZone.ZIndex = 3
	perfectZone.Parent = track
	perfectZoneFrame = perfectZone

	local indicator = Instance.new("Frame")
	indicator.Name = "Indicator"
	indicator.AnchorPoint = Vector2.new(0.5, 0.5)
	indicator.Position = UDim2.fromScale(0.5, 0.5)
	indicator.Size = UDim2.fromOffset(6, 34)
	indicator.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	indicator.BorderSizePixel = 0
	indicator.ZIndex = 5
	indicator.Parent = track
	indicatorFrame = indicator

	local indCorner = Instance.new("UICorner")
	indCorner.CornerRadius = UDim.new(0, 3)
	indCorner.Parent = indicator

	local button = Instance.new("TextButton")
	button.Name = "DigButton"
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, 0)
	button.Size = UDim2.fromOffset(210, 56) -- >= 44px height for mobile ergonomics
	button.BackgroundColor3 = Color3.fromRGB(235, 155, 45)
	button.Font = Enum.Font.GothamBlack
	button.TextSize = 20
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextStrokeTransparency = 0.4
	button.Text = "GALI [Space / Tap]"
	button.AutoButtonColor = true
	button.Parent = container
	digButton = button

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 12)
	btnCorner.Parent = button

	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = Color3.fromRGB(255, 230, 160)
	btnStroke.Thickness = 2
	btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	btnStroke.Parent = button

	button.Activated:Connect(function()
		if button.Active then
			DigController.AttemptStrike()
		end
	end)

	updateZoneLayout()
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
		if activeMoundId then
			task.defer(function()
				setCharacterJumpEnabled(false)
			end)
		end
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
				sessionStartTime = tonumber(payload.StartTime) or workspace:GetServerTimeNow()
				barSpeed = tonumber(payload.Speed) or barSpeed
				goodWidth = tonumber(payload.GoodWidth) or goodWidth
				perfectWidth = tonumber(payload.PerfectWidth) or perfectWidth
				updateZoneLayout()
			end
		elseif payload.Event == "StrikeHit" then
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
		elseif payload.Event == "Rejected" then
			if payload.Reason == "BagFull" then
				unbindMinigameControls()
				showBagFullLockedState(tostring(payload.MoundId or ""), activeMoundSize)
			elseif payload.Reason == "OutOfRange" then
				DigController.StopMinigame(false)
			end
		end
	end)

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

		local moundPos = MoundVisuals.GetMoundPosition(activeMoundId)
		if not moundPos or not isCharacterWithinRangeOf(moundPos) then
			DigController.StopMinigame(true)
			return
		end

		setCharacterJumpEnabled(false)

		if indicatorFrame and digButton then
			local now = workspace:GetServerTimeNow()
			local elapsed = math.max(0, now - sessionStartTime)
			local pos = Weighted.IndicatorPos(elapsed, barSpeed)
			indicatorFrame.Position = UDim2.fromScale(pos, 0.5)

			local onCooldown = now < nextAllowedStrikeTime
			if onCooldown then
				local rem = math.max(0, nextAllowedStrikeTime - now)
				digButton.BackgroundColor3 = Color3.fromRGB(110, 110, 120)
				digButton.Text = string.format("WAIT %.1fs", rem)
			else
				digButton.BackgroundColor3 = Color3.fromRGB(235, 155, 45)
				digButton.Text = "GALI [Space / Tap]"
			end
		end
	end)
end

return DigController
