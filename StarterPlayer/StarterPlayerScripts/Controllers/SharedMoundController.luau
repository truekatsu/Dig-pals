--!strict
-- Client controller for Shared Rare Mound announcements, top-screen live event banner, and reward summary popup (Step 11)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local AssetIds = require(Shared:WaitForChild("AssetIds"))
local RarityConfig = require(Shared:WaitForChild("Config"):WaitForChild("Rarity"))

local LocalPlayer = Players.LocalPlayer

local SharedMoundController = {}

local screenGui: ScreenGui? = nil
local bannerFrame: Frame? = nil
local bannerTitle: TextLabel? = nil
local bannerSubtitle: TextLabel? = nil
local rewardModal: Frame? = nil
local rewardContentFrame: Frame? = nil

local currentMoundId: string? = nil
local currentMoundExpiresAt: number = 0
local currentMoundHP: number = 3000
local currentMoundMaxHP: number = 3000
local currentSpawnName: string = "Plain"
local bannerVisible: boolean = false
local started: boolean = false

local function formatTime(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local mins = math.floor(s / 60)
	local rem = s % 60
	return string.format("%d:%02d", mins, rem)
end

local function updateBannerText()
	if not bannerSubtitle then
		return
	end
	local now = workspace:GetServerTimeNow()
	local remainingSeconds = math.max(0, currentMoundExpiresAt - now)
	bannerSubtitle.Text = string.format(
		"Lokasi: %s | HP: %d/%d | Sisa: %s",
		currentSpawnName,
		math.ceil(currentMoundHP),
		math.ceil(currentMoundMaxHP),
		formatTime(remainingSeconds)
	)
end

local function showBanner(title: string, color: Color3?)
	if not bannerFrame or not bannerTitle then
		return
	end
	bannerVisible = true
	bannerTitle.Text = title
	if color then
		bannerTitle.TextColor3 = color
	end
	updateBannerText()
	bannerFrame.Visible = true
	TweenService:Create(bannerFrame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 48),
	}):Play()
end

local function hideBanner(delaySeconds: number?)
	local function doHide()
		if not bannerFrame then
			return
		end
		bannerVisible = false
		local tw = TweenService:Create(bannerFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 0, -80),
		})
		tw:Play()
		tw.Completed:Connect(function()
			if not bannerVisible and bannerFrame then
				bannerFrame.Visible = false
			end
		end)
	end

	if delaySeconds and delaySeconds > 0 then
		task.delay(delaySeconds, doHide)
	else
		doHide()
	end
end

local function showRewardPopup(summary: any)
	if not screenGui or type(summary) ~= "table" then
		return
	end

	if rewardModal then
		rewardModal:Destroy()
		rewardModal = nil
	end

	local modal = Instance.new("Frame")
	modal.Name = "RewardModal"
	modal.Size = UDim2.fromScale(1, 1)
	modal.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	modal.BackgroundTransparency = 1
	modal.BorderSizePixel = 0
	modal.ZIndex = 50
	modal.Parent = screenGui
	rewardModal = modal

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromOffset(460, 420)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.BackgroundColor3 = Color3.fromRGB(26, 26, 34)
	card.BorderSizePixel = 0
	card.Parent = modal

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 14)
	cardCorner.Parent = card

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = Color3.fromRGB(255, 205, 70)
	cardStroke.Thickness = 2
	cardStroke.Parent = card

	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Size = UDim2.new(1, -24, 0, 36)
	header.Position = UDim2.fromOffset(12, 14)
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.GothamBlack
	header.TextSize = 20
	header.TextColor3 = Color3.fromRGB(255, 215, 75)
	header.Text = "[*] HADIAH GUNDUKAN LANGKA [*]"
	header.Parent = card

	local contribRatio = tonumber(summary.ContributionRatio) or 0
	local damageDealt = tonumber(summary.DamageDealt) or 0
	local isTop = summary.IsTopContributor == true

	local statsLabel = Instance.new("TextLabel")
	statsLabel.Name = "StatsLabel"
	statsLabel.Size = UDim2.new(1, -24, 0, 24)
	statsLabel.Position = UDim2.fromOffset(12, 50)
	statsLabel.BackgroundTransparency = 1
	statsLabel.Font = Enum.Font.GothamMedium
	statsLabel.TextSize = 13
	statsLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
	statsLabel.Text = string.format("Kontribusi: %d HP (%.1f%%)", math.floor(damageDealt), contribRatio * 100)
	statsLabel.Parent = card

	if isTop then
		local topBadge = Instance.new("TextLabel")
		topBadge.Name = "TopBadge"
		topBadge.Size = UDim2.new(1, -24, 0, 22)
		topBadge.Position = UDim2.fromOffset(12, 74)
		topBadge.BackgroundTransparency = 1
		topBadge.Font = Enum.Font.GothamBold
		topBadge.TextSize = 13
		topBadge.TextColor3 = Color3.fromRGB(255, 230, 90)
		topBadge.Text = "[TOP KONTRIBUTOR! +1 BONUS ROLL TELUR]"
		topBadge.Parent = card
	end

	local listScroll = Instance.new("ScrollingFrame")
	listScroll.Name = "RewardList"
	listScroll.Size = UDim2.new(1, -24, 0, 230)
	listScroll.Position = UDim2.fromOffset(12, if isTop then 102 else 80)
	listScroll.BackgroundTransparency = 1
	listScroll.BorderSizePixel = 0
	listScroll.ScrollBarThickness = 4
	listScroll.Parent = card

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = listScroll

	local function addRewardRow(labelText: string, rarityName: string, iconColor: Color3)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 36)
		row.BackgroundColor3 = Color3.fromRGB(36, 36, 46)
		row.BorderSizePixel = 0
		row.Parent = listScroll

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 8)
		rowCorner.Parent = row

		local dot = Instance.new("Frame")
		dot.Size = UDim2.fromOffset(12, 12)
		dot.Position = UDim2.fromOffset(10, 12)
		dot.BackgroundColor3 = iconColor
		dot.BorderSizePixel = 0
		dot.Parent = row

		local dotCorner = Instance.new("UICorner")
		dotCorner.CornerRadius = UDim.new(1, 0)
		dotCorner.Parent = dot

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -36, 1, 0)
		nameLabel.Position = UDim2.fromOffset(30, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 13
		nameLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Text = string.format("%s (%s)", labelText, rarityName)
		nameLabel.Parent = row
	end

	if type(summary.EggDrops) == "table" then
		for _, egg in ipairs(summary.EggDrops) do
			local rCfg = RarityConfig.ById[egg.Rarity]
			local color = if rCfg then rCfg.Color else Color3.fromRGB(200, 200, 200)
			addRewardRow(tostring(egg.DisplayName or egg.Id), tostring(egg.Rarity or "Uncommon"), color)
		end
	end

	if type(summary.ItemDrops) == "table" then
		for _, item in ipairs(summary.ItemDrops) do
			local rCfg = RarityConfig.ById[item.Rarity]
			local color = if rCfg then rCfg.Color else Color3.fromRGB(200, 200, 200)
			addRewardRow(tostring(item.DisplayName or item.Id), tostring(item.Rarity or "Common"), color)
		end
	end

	if type(summary.SpecialShovelsWon) == "table" then
		for _, shovelId in ipairs(summary.SpecialShovelsWon) do
			addRewardRow("[SPECIAL SHOVEL] " .. shovelId, "Legendary", Color3.fromRGB(255, 120, 50))
		end
	end

	local claimBtn = Instance.new("TextButton")
	claimBtn.Name = "ClaimButton"
	claimBtn.Size = UDim2.new(1, -24, 0, 42)
	claimBtn.Position = UDim2.new(0, 12, 1, -54)
	claimBtn.BackgroundColor3 = Color3.fromRGB(50, 185, 95)
	claimBtn.BorderSizePixel = 0
	claimBtn.Font = Enum.Font.GothamBlack
	claimBtn.TextSize = 15
	claimBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	claimBtn.Text = "KLAIM HADIAH"
	claimBtn.Parent = card

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 10)
	btnCorner.Parent = claimBtn

	claimBtn.MouseButton1Click:Connect(function()
		if rewardModal then
			rewardModal:Destroy()
			rewardModal = nil
		end
	end)
end

local function buildUI()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("SharedMoundGui")
	if existing and existing:IsA("ScreenGui") then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "SharedMoundGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	screenGui = gui

	local banner = Instance.new("Frame")
	banner.Name = "EventBanner"
	banner.Size = UDim2.fromOffset(380, 58)
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, -80)
	banner.BackgroundColor3 = Color3.fromRGB(24, 20, 30)
	banner.BackgroundTransparency = 0.15
	banner.BorderSizePixel = 0
	banner.Visible = false
	banner.Parent = gui
	bannerFrame = banner

	local bannerCorner = Instance.new("UICorner")
	bannerCorner.CornerRadius = UDim.new(0, 10)
	bannerCorner.Parent = banner

	local bannerStroke = Instance.new("UIStroke")
	bannerStroke.Color = Color3.fromRGB(255, 200, 60)
	bannerStroke.Thickness = 1.8
	bannerStroke.Parent = banner

	local title = Instance.new("TextLabel")
	title.Name = "BannerTitle"
	title.Size = UDim2.new(1, -16, 0, 22)
	title.Position = UDim2.fromOffset(8, 6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 14
	title.TextColor3 = Color3.fromRGB(255, 215, 75)
	title.Text = "[*] GUNDUKAN LANGKA AKTIF [*]"
	title.Parent = banner
	bannerTitle = title

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "BannerSubtitle"
	subtitle.Size = UDim2.new(1, -16, 0, 20)
	subtitle.Position = UDim2.fromOffset(8, 28)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.TextSize = 12
	subtitle.TextColor3 = Color3.fromRGB(225, 225, 235)
	subtitle.Text = "Lokasi: Plain | HP: 3000/3000 | Sisa: 4:00"
	subtitle.Parent = banner
	bannerSubtitle = subtitle
end

function SharedMoundController.ShowRewardPopup(summary: any)
	showRewardPopup(summary)
end

function SharedMoundController.Start()
	if started then
		return
	end
	started = true

	buildUI()

	-- Tick loop for countdown timer in banner
	task.spawn(function()
		while true do
			task.wait(1.0)
			if bannerVisible and currentMoundExpiresAt > 0 then
				updateBannerText()
			end
		end
	end)

	Remotes.GetEvent("SharedMoundAlert").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end

		if payload.Event == "Spawned" then
			currentMoundId = tostring(payload.MoundId or "")
			currentMoundHP = tonumber(payload.HP) or 3000
			currentMoundMaxHP = tonumber(payload.MaxHP) or 3000
			currentMoundExpiresAt = tonumber(payload.ExpiresAt) or (workspace:GetServerTimeNow() + 240)
			currentSpawnName = tostring(payload.SpawnPointName or "Plain")
			showBanner("[*] GUNDUKAN LANGKA AKTIF [*]", Color3.fromRGB(255, 215, 75))
		elseif payload.Event == "Cleared" then
			currentMoundHP = 0
			local topName = tostring(payload.TopContributor or "None")
			local topPct = tonumber(payload.TopContributionPercent) or 0
			if bannerTitle and bannerSubtitle then
				bannerTitle.Text = "[v] GUNDUKAN LANGKA HANCUR! [v]"
				bannerTitle.TextColor3 = Color3.fromRGB(95, 235, 125)
				bannerSubtitle.Text = string.format("Top Damager: %s (%d%%)", topName, topPct)
			end
			hideBanner(5.0)
		elseif payload.Event == "Expired" then
			if bannerTitle and bannerSubtitle then
				bannerTitle.Text = "[-] GUNDUKAN LANGKA HILANG [-]"
				bannerTitle.TextColor3 = Color3.fromRGB(220, 100, 100)
				bannerSubtitle.Text = "Waktu habis gundukan telah hilang."
			end
			hideBanner(3.0)
		elseif payload.Event == "Reward" then
			if type(payload.Summary) == "table" then
				showRewardPopup(payload.Summary)
			end
		end
	end)

	Remotes.GetEvent("MoundUpdated").OnClientEvent:Connect(function(moundId: string, currentHp: number, maxHp: number)
		if currentMoundId and moundId == currentMoundId then
			currentMoundHP = currentHp
			currentMoundMaxHP = maxHp
			updateBannerText()
		end
	end)
end

return SharedMoundController
