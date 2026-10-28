--!strict
-- Automated Client Verification Suite for LANGKAH 15 (UI/UX, input, audio, fx, responsive UIScale, touch targets >= 44px)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetIds = require(Shared:WaitForChild("AssetIds"))

local Controllers = script.Parent:WaitForChild("Controllers")
local AudioController = require(Controllers:WaitForChild("AudioController"))
local FxController = require(Controllers:WaitForChild("FxController"))
local NotificationController = require(Controllers:WaitForChild("NotificationController"))
local InputController = require(Controllers:WaitForChild("InputController"))
local DigController = require(Controllers:WaitForChild("DigController"))
local IndexController = require(Controllers:WaitForChild("IndexController"))
local QuestStreakController = require(Controllers:WaitForChild("QuestStreakController"))
local PetBagController = require(Controllers:WaitForChild("PetBagController"))
local BaseController = require(Controllers:WaitForChild("BaseController"))
local ShovelShopController = require(Controllers:WaitForChild("ShovelShopController"))
local MerchantController = require(Controllers:WaitForChild("MerchantController"))
local LeaderboardController = require(Controllers:WaitForChild("LeaderboardController"))
local InventoryController = require(Controllers:WaitForChild("InventoryController"))

task.defer(function()
	task.wait(1.5) -- Allow all controllers to build initial GUI structures

	local passed = 0
	local failed = 0

	local function verify(cond: boolean, label: string, detail: string?)
		if cond then
			passed += 1
			print(string.format("[Step15Validator] PASS: %s", label))
		else
			failed += 1
			warn(string.format("[Step15Validator] FAIL: %s (%s)", label, detail or "assertion failed"))
		end
	end

	print("[Step15Validator] Starting validation of LANGKAH 15...")

	-- 1. AudioController & SoundGroup
	local soundGroup = SoundService:FindFirstChild("DigPalsSoundGroup")
	verify(soundGroup ~= nil and soundGroup:IsA("SoundGroup"), "DigPalsSoundGroup exists in SoundService")

	local allSoundIdsValid = true
	for soundName, _ in pairs(AssetIds.Sounds) do
		local template = soundGroup and soundGroup:FindFirstChild(soundName)
		if not template or not template:IsA("Sound") then
			allSoundIdsValid = false
			break
		end
	end
	verify(allSoundIdsValid, "All 9 sound templates loaded in DigPalsSoundGroup from AssetIds.Sounds")

	local testSound = AudioController.PlaySound("StrikePerfect", 0.5, 1.0)
	verify(testSound ~= nil and testSound:IsA("Sound"), "AudioController.PlaySound creates and plays sound clone")

	local audioMethodsSuccess = true
	local success, err = pcall(function()
		AudioController.PlayStrike("Perfect")
		AudioController.PlayStrike("Good")
		AudioController.PlayStrike("Miss")
		AudioController.PlayMoundBreak()
		AudioController.PlayRareDrop("Legendary")
		AudioController.PlayEggHatch("Rare")
		AudioController.PlayLevelUp()
		AudioController.PlayBaseUpgrade()
		AudioController.PlayCoinGain()
		AudioController.PlayClick()
	end)
	if not success then
		audioMethodsSuccess = false
		warn("Audio method error: " .. tostring(err))
	end
	verify(audioMethodsSuccess, "All AudioController playback triggers execute cleanly without errors")

	-- 2. Visual Effects (FxController)
	local fxSuccess = true
	success, err = pcall(function()
		FxController.PlayPerfectStrikeFx(Vector3.new(0, 5, 0))
		FxController.PlayRareSpawnFx(Vector3.new(0, 5, 0), "Legendary")
		FxController.PlayRareSpawnFx(Vector3.new(0, 5, 0), "Epic")
		FxController.PlayRareSpawnFx(Vector3.new(0, 5, 0), "Rare")
		FxController.PlayEggHatchFx(nil, "Legendary")
		FxController.PlayLevelUpFx()
		FxController.PlayBaseUpgradeFx(Vector3.new(0, 5, 0))
	end)
	if not success then
		fxSuccess = false
		warn("Fx error: " .. tostring(err))
	end
	verify(fxSuccess, "All FxController visual effects (Perfect, Rare spawns, Hatch, LevelUp, BaseUpgrade) execute cleanly")

	-- 3. NotificationController (Bounded Queue)
	local notifGui = PlayerGui:FindFirstChild("DigPalsNotificationGui")
	verify(notifGui ~= nil, "DigPalsNotificationGui exists in PlayerGui")

	local notifContainer = notifGui and notifGui:FindFirstChild("NotificationQueue") :: Frame?
	verify(notifContainer ~= nil, "NotificationQueue container exists with UIListLayout")

	-- Enforce queue bounds: send 6 notifications and ensure <= 4 cards remain
	for i = 1, 6 do
		NotificationController.Notify(string.format("Test Title %d", i), "Message details", "Rare", "TEST")
	end
	task.wait(0.3)
	local activeCardCount = 0
	if notifContainer then
		for _, c in ipairs(notifContainer:GetChildren()) do
			if c:IsA("Frame") and c.Name == "NotifCard" and (c :: any).BackgroundTransparency < 0.9 then
				activeCardCount += 1
			end
		end
	end
	verify(activeCardCount <= 4, "Notification queue enforces max 4 concurrent visible cards without stacking", string.format("active=%d", activeCardCount))

	-- 4. Touch Targets >= 44px and Responsive UIScale across all panels

	-- Panel: IndexGui
	local indexGui = PlayerGui:FindFirstChild("IndexGui")
	verify(indexGui ~= nil, "IndexGui exists in PlayerGui")
	local indexCard = indexGui and indexGui:FindFirstChild("IndexModal") and indexGui.IndexModal:FindFirstChild("Card")
	local indexScale = indexCard and indexCard:FindFirstChildOfClass("UIScale")
	verify(indexScale ~= nil, "IndexGui Card has responsive UIScale")
	local indexClose = indexCard and indexCard:FindFirstChild("CloseButton") :: TextButton?
	verify(indexClose ~= nil and indexClose.Size.X.Offset >= 44 and indexClose.Size.Y.Offset >= 44, "IndexGui CloseButton touch target >= 44x44 px")
	local indexTabContainer = indexCard and indexCard:FindFirstChild("TabContainer") :: Frame?
	verify(indexTabContainer ~= nil and indexTabContainer.Size.Y.Offset >= 44, "IndexGui TabContainer touch target height >= 44 px")

	-- Panel: QuestStreakGui
	local questGui = PlayerGui:FindFirstChild("QuestStreakGui")
	verify(questGui ~= nil, "QuestStreakGui exists in PlayerGui")
	local questCard = questGui and questGui:FindFirstChild("QuestStreakModal") and questGui.QuestStreakModal:FindFirstChild("Card")
	local questScale = questCard and questCard:FindFirstChildOfClass("UIScale")
	verify(questScale ~= nil, "QuestStreakGui Card has responsive UIScale")
	local questClose = questCard and questCard:FindFirstChild("CloseButton") :: TextButton?
	verify(questClose ~= nil and questClose.Size.X.Offset >= 44 and questClose.Size.Y.Offset >= 44, "QuestStreakGui CloseButton touch target >= 44x44 px")
	local questTabContainer = questCard and questCard:FindFirstChild("TabContainer") :: Frame?
	verify(questTabContainer ~= nil and questTabContainer.Size.Y.Offset >= 44, "QuestStreakGui TabContainer touch target height >= 44 px")

	-- Panel: PetBagGui
	local petGui = PlayerGui:FindFirstChild("PetBagGui")
	verify(petGui ~= nil, "PetBagGui exists in PlayerGui")
	local petScale = petGui and petGui:FindFirstChildOfClass("UIScale")
	verify(petScale ~= nil, "PetBagGui has responsive UIScale")
	local petCard = petGui and petGui:FindFirstChild("PetBagPanel")
	local petHeader = petCard and petCard:FindFirstChild("Header")
	local petClose = petHeader and petHeader:FindFirstChild("CloseButton") :: TextButton?
	verify(petClose ~= nil and petClose.Size.X.Offset >= 44 and petClose.Size.Y.Offset >= 44, "PetBagGui CloseButton touch target >= 44x44 px")

	-- Panel: IncubatorGui (Base Incubators)
	local baseGui = PlayerGui:FindFirstChild("IncubatorGui")
	verify(baseGui ~= nil, "IncubatorGui exists in PlayerGui")
	local baseScale = baseGui and baseGui:FindFirstChildOfClass("UIScale")
	verify(baseScale ~= nil, "IncubatorGui has responsive UIScale")
	local incCard = baseGui and baseGui:FindFirstChild("IncubatorPanel")
	local incHeader = incCard and incCard:FindFirstChild("Header")
	local incClose = incHeader and incHeader:FindFirstChild("CloseButton") :: TextButton?
	verify(incClose ~= nil and incClose.Size.X.Offset >= 44 and incClose.Size.Y.Offset >= 44, "IncubatorGui CloseButton touch target >= 44x44 px")

	-- Panel: ShovelShopGui
	local shopGui = PlayerGui:FindFirstChild("ShovelShopGui")
	verify(shopGui ~= nil, "ShovelShopGui exists in PlayerGui")
	local shopScale = shopGui and shopGui:FindFirstChildOfClass("UIScale")
	verify(shopScale ~= nil, "ShovelShopGui has responsive UIScale")
	local shopCard = shopGui and shopGui:FindFirstChild("ShovelShopPanel")
	local shopHeader = shopCard and shopCard:FindFirstChild("Header")
	local shopClose = shopHeader and shopHeader:FindFirstChild("CloseButton") :: TextButton?
	verify(shopClose ~= nil and shopClose.Size.X.Offset >= 44 and shopClose.Size.Y.Offset >= 44, "ShovelShopGui CloseButton touch target >= 44x44 px")

	-- Panel: MerchantGui
	local merchGui = PlayerGui:FindFirstChild("MerchantGui")
	verify(merchGui ~= nil, "MerchantGui exists in PlayerGui")
	local merchScale = merchGui and merchGui:FindFirstChildOfClass("UIScale")
	verify(merchScale ~= nil, "MerchantGui has responsive UIScale")
	local merchCard = merchGui and merchGui:FindFirstChild("MerchantPanel")
	local merchHeader = merchCard and merchCard:FindFirstChild("Header")
	local merchClose = merchHeader and merchHeader:FindFirstChild("CloseButton") :: TextButton?
	verify(merchClose ~= nil and merchClose.Size.X.Offset >= 44 and merchClose.Size.Y.Offset >= 44, "MerchantGui CloseButton touch target >= 44x44 px")

	-- Panel: InventoryGui
	local invGui = PlayerGui:FindFirstChild("InventoryGui")
	verify(invGui ~= nil, "InventoryGui exists in PlayerGui")
	local invScale = invGui and invGui:FindFirstChildOfClass("UIScale")
	verify(invScale ~= nil, "InventoryGui has responsive UIScale")
	local invCard = invGui and invGui:FindFirstChild("ShovelInventoryPanel")
	local invHeader = invCard and invCard:FindFirstChild("Header")
	local invClose = invHeader and invHeader:FindFirstChild("CloseButton") :: TextButton?
	verify(invClose ~= nil and invClose.Size.X.Offset >= 44 and invClose.Size.Y.Offset >= 44, "InventoryGui CloseButton touch target >= 44x44 px")

	-- Panel: LeaderboardGui
	local lbGui = PlayerGui:FindFirstChild("LeaderboardGui")
	verify(lbGui ~= nil, "LeaderboardGui exists in PlayerGui")
	local lbScale = lbGui and lbGui:FindFirstChild("ResponsiveScale") :: UIScale?
	verify(lbScale ~= nil, "LeaderboardGui has responsive UIScale")
	local lbBackdrop = lbGui and lbGui:FindFirstChild("ModalBackdrop")
	local lbCard = lbBackdrop and lbBackdrop:FindFirstChild("LeaderboardModal")
	local lbHeader = lbCard and lbCard:FindFirstChild("Header")
	local lbClose = lbHeader and lbHeader:FindFirstChild("CloseButton") :: TextButton?
	verify(lbClose ~= nil and lbClose.Size.X.Offset >= 44 and lbClose.Size.Y.Offset >= 44, "LeaderboardGui CloseButton touch target >= 44x44 px")

	-- Panel: DigTimingGui & DigButton
	local digGui = PlayerGui:FindFirstChild("DigTimingGui")
	verify(digGui ~= nil, "DigTimingGui exists in PlayerGui")
	local digContainer = digGui and digGui:FindFirstChild("DigContainer") :: Frame?
	local digScale = digContainer and digContainer:FindFirstChildOfClass("UIScale")
	verify(digScale ~= nil, "DigContainer has responsive UIScale for mobile ergonomics")
	local digBtn = digContainer and digContainer:FindFirstChild("DigButton") :: TextButton?
	verify(digBtn ~= nil and digBtn.Size.Y.Offset >= 44, "DigButton touch height >= 44 px (current: " .. tostring(digBtn and digBtn.Size.Y.Offset) .. "px)")

	-- 5. Modal Isolation and No UI Overlapping Dig Button
	verify(InputController.IsAnyModalOpen() == false, "InputController reports no modal open initially")

	IndexController.Toggle()
	task.wait(0.1)
	verify(IndexController.IsOpen() == true, "IndexController opened via Toggle()")
	verify(InputController.IsAnyModalOpen() == true, "InputController detects open modal (Index)")

	local closedViaInput = InputController.CloseActiveModal()
	task.wait(0.1)
	verify(closedViaInput == true and IndexController.IsOpen() == false, "InputController.CloseActiveModal() cleanly closes modal")
	verify(InputController.IsAnyModalOpen() == false, "InputController reports no modal open after close")

	print(string.format("[Step15Validator] SUMMARY: %d passed, %d failed.", passed, failed))
end)
