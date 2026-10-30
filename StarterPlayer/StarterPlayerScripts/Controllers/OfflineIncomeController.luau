--!strict
local CurrencyStyle = require(script.Parent:WaitForChild("CurrencyStyle"))
-- Offline Income Summary Modal Controller (Step 10)
-- Displays offline earnings popup on join:
-- "min(detik offline, 43.200) x income x 0,10 dan tampilkan popup ringkasan."

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))

local LocalPlayer = Players.LocalPlayer

local OfflineIncomeController = {}

local screenGui: ScreenGui? = nil
local modalBackdrop: TextButton? = nil
local modalFrame: Frame? = nil
local uiScale: UIScale? = nil

local started = false

local function updateResponsiveScale()
	if not uiScale then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local vw = cam.ViewportSize.X
	local vh = cam.ViewportSize.Y
	local scaleX = vw / 1024
	local scaleY = vh / 640
	local scale = math.min(scaleX, scaleY)
	uiScale.Scale = math.clamp(scale, 0.72, 1.25)
end

function OfflineIncomeController.Close()
	if modalFrame and modalBackdrop then
		local t = TweenService:Create(modalFrame, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Size = UDim2.fromOffset(400, 240),
		})
		t:Play()
		t.Completed:Connect(function()
			modalFrame.Visible = false
			modalBackdrop.Visible = false
		end)
	end
end

function OfflineIncomeController.IsOpen(): boolean
	return modalFrame ~= nil and modalFrame.Visible == true
end

function OfflineIncomeController.Show(data: {
	OfflineSeconds: number,
	CappedSeconds: number,
	ActiveIncome: number,
	CoinsEarned: number,
})
	if not modalFrame or not modalBackdrop then
		return
	end

	local offlineSec = data.OfflineSeconds or 0
	local cappedSec = data.CappedSeconds or offlineSec
	local earned = data.CoinsEarned or 0
	local activeRate = data.ActiveIncome or 0

	local hours = math.floor(cappedSec / 3600)
	local mins = math.floor((cappedSec % 3600) / 60)

	local timeStr = if hours > 0 then string.format("%d jam %d menit", hours, mins) else string.format("%d menit", math.max(1, mins))

	local rewardLbl = modalFrame:FindFirstChild("RewardValue", true) :: TextLabel?
	if rewardLbl then
		rewardLbl.Text = string.format("+$%s", Format.Commas(earned))
	end

	local timeDesc = modalFrame:FindFirstChild("TimeDesc", true) :: TextLabel?
	if timeDesc then
		timeDesc.Text = string.format("Waktu offline terhitung: %s (Maks 12 jam)", timeStr)
	end

	local rateDesc = modalFrame:FindFirstChild("RateDesc", true) :: TextLabel?
	if rateDesc then
		rateDesc.Text = string.format("Rate Base: +$%s/dtk (Rate offline 10%%)", Format.Commas(activeRate))
	end

	modalBackdrop.Visible = true
	modalFrame.Visible = true
	modalFrame.Size = UDim2.fromOffset(420, 260)

	TweenService:Create(modalFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(500, 310),
	}):Play()
end

local function buildGui()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("OfflineIncomeGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "OfflineIncomeGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 25
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	screenGui = gui

	local scaleInst = Instance.new("UIScale")
	scaleInst.Name = "ResponsiveScale"
	scaleInst.Scale = 1
	scaleInst.Parent = gui
	uiScale = scaleInst
	updateResponsiveScale()

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "ModalBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(6, 8, 14)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.Visible = false
	backdrop.ZIndex = 30
	backdrop.Parent = gui
	modalBackdrop = backdrop

	backdrop.Activated:Connect(function()
		OfflineIncomeController.Close()
	end)

	local modal = Instance.new("Frame")
	modal.Name = "ModalFrame"
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.new(0.5, 0, 0.48, 0)
	modal.Size = UDim2.fromOffset(500, 310)
	modal.BackgroundColor3 = Color3.fromRGB(22, 28, 40)
	modal.BorderSizePixel = 0
	modal.Visible = false
	modal.Active = true
	modal.ZIndex = 32
	modal.Parent = gui
	modalFrame = modal

	local mCorner = Instance.new("UICorner")
	mCorner.CornerRadius = UDim.new(0, 16)
	mCorner.Parent = modal

	local mStroke = Instance.new("UIStroke")
	mStroke.Color = Color3.fromRGB(255, 195, 60)
	mStroke.Thickness = 2
	mStroke.Parent = modal

	-- Header Title
	local titleLbl = Instance.new("TextLabel")
	titleLbl.Name = "Title"
	titleLbl.AnchorPoint = Vector2.new(0.5, 0)
	titleLbl.Position = UDim2.new(0.5, 0, 0, 18)
	titleLbl.Size = UDim2.new(1, -30, 0, 26)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Font = Enum.Font.GothamBlack
	titleLbl.TextSize = 20
	titleLbl.TextColor3 = Color3.fromRGB(255, 224, 100)
	titleLbl.Text = "SELAMAT DATANG KEMBALI!"
	titleLbl.Parent = modal

	-- Subtitle
	local subLbl = Instance.new("TextLabel")
	subLbl.Name = "Subtitle"
	subLbl.AnchorPoint = Vector2.new(0.5, 0)
	subLbl.Position = UDim2.new(0.5, 0, 0, 48)
	subLbl.Size = UDim2.new(1, -30, 0, 18)
	subLbl.BackgroundTransparency = 1
	subLbl.Font = Enum.Font.GothamMedium
	subLbl.TextSize = 13
	subLbl.TextColor3 = Color3.fromRGB(180, 195, 215)
	subLbl.Text = "Pet di base-mu tetap bekerja saat kamu offline!"
	subLbl.Parent = modal

	-- Reward Box
	local rewardCard = Instance.new("Frame")
	rewardCard.Name = "RewardCard"
	rewardCard.AnchorPoint = Vector2.new(0.5, 0)
	rewardCard.Position = UDim2.new(0.5, 0, 0, 76)
	rewardCard.Size = UDim2.new(1, -40, 0, 72)
	rewardCard.BackgroundColor3 = Color3.fromRGB(16, 21, 30)
	rewardCard.BorderSizePixel = 0
	rewardCard.Parent = modal

	local rCorner = Instance.new("UICorner")
	rCorner.CornerRadius = UDim.new(0, 12)
	rCorner.Parent = rewardCard

	local rStroke = Instance.new("UIStroke")
	rStroke.Color = Color3.fromRGB(245, 185, 45)
	rStroke.Thickness = 1.6
	rStroke.Parent = rewardCard

	local rewardVal = Instance.new("TextLabel")
	rewardVal.Name = "RewardValue"
	rewardVal.Size = UDim2.fromScale(1, 1)
	rewardVal.BackgroundTransparency = 1
	rewardVal.Font = Enum.Font.GothamBlack
	rewardVal.TextSize = 28
	rewardVal.TextColor3 = Color3.fromRGB(255, 220, 70)
	rewardVal.Text = "+$0"
	rewardVal.Parent = rewardCard
	CurrencyStyle.Apply(rewardVal)

	-- Stats Breakdown lines
	local timeLbl = Instance.new("TextLabel")
	timeLbl.Name = "TimeDesc"
	timeLbl.AnchorPoint = Vector2.new(0.5, 0)
	timeLbl.Position = UDim2.new(0.5, 0, 0, 160)
	timeLbl.Size = UDim2.new(1, -40, 0, 18)
	timeLbl.BackgroundTransparency = 1
	timeLbl.Font = Enum.Font.GothamBold
	timeLbl.TextSize = 13
	timeLbl.TextColor3 = Color3.fromRGB(220, 230, 245)
	timeLbl.Text = "Waktu offline terhitung: 0 menit (Maks 12 jam)"
	timeLbl.Parent = modal

	local rateLbl = Instance.new("TextLabel")
	rateLbl.Name = "RateDesc"
	rateLbl.AnchorPoint = Vector2.new(0.5, 0)
	rateLbl.Position = UDim2.new(0.5, 0, 0, 182)
	rateLbl.Size = UDim2.new(1, -40, 0, 18)
	rateLbl.BackgroundTransparency = 1
	rateLbl.Font = Enum.Font.GothamMedium
	rateLbl.TextSize = 12
	rateLbl.TextColor3 = Color3.fromRGB(150, 170, 195)
	rateLbl.Text = "Rate Base: +$0/dtk (Rate offline 10%)"
	rateLbl.Parent = modal

	-- Claim Button
	local claimBtn = Instance.new("TextButton")
	claimBtn.Name = "ClaimButton"
	claimBtn.AnchorPoint = Vector2.new(0.5, 1)
	claimBtn.Position = UDim2.new(0.5, 0, 1, -18)
	claimBtn.Size = UDim2.new(1, -40, 0, 46)
	claimBtn.BackgroundColor3 = Color3.fromRGB(46, 178, 106)
	claimBtn.BorderSizePixel = 0
	claimBtn.Font = Enum.Font.GothamBlack
	claimBtn.TextSize = 16
	claimBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	claimBtn.Text = "KLAIM UANG"
	claimBtn.Parent = modal

	local cCorner = Instance.new("UICorner")
	cCorner.CornerRadius = UDim.new(0, 10)
	cCorner.Parent = claimBtn

	claimBtn.MouseEnter:Connect(function()
		claimBtn.BackgroundColor3 = Color3.fromRGB(60, 204, 124)
	end)
	claimBtn.MouseLeave:Connect(function()
		claimBtn.BackgroundColor3 = Color3.fromRGB(46, 178, 106)
	end)
	claimBtn.Activated:Connect(function()
		OfflineIncomeController.Close()
	end)
end

function OfflineIncomeController.Start()
	if started then
		return
	end
	started = true

	buildGui()

	local function bindCameraViewport()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveScale)
			updateResponsiveScale()
		end
	end
	bindCameraViewport()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCameraViewport)

	-- Listen for OfflineIncomeSummary
	Remotes.GetEvent("OfflineIncomeSummary").OnClientEvent:Connect(function(data: any)
		if type(data) == "table" and type(data.CoinsEarned) == "number" and data.CoinsEarned > 0 then
			OfflineIncomeController.Show(data)
		end
	end)
end

return OfflineIncomeController
