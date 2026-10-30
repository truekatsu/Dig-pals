--!strict
-- Unified Input Controller for PC Keyboard Shortcuts and Gamepad Support (Step 15)
-- Enables quick access to all panels, escape/cancel modal closing, and console gamepad bindings.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Controllers = script.Parent
local InventoryController = require(Controllers:WaitForChild("InventoryController"))
local PetBagController = require(Controllers:WaitForChild("PetBagController"))
local ShovelShopController = require(Controllers:WaitForChild("ShovelShopController"))
local IndexController = require(Controllers:WaitForChild("IndexController"))
local QuestStreakController = require(Controllers:WaitForChild("QuestStreakController"))
local LeaderboardController = require(Controllers:WaitForChild("LeaderboardController"))
local BaseController = require(Controllers:WaitForChild("BaseController"))
local MerchantController = require(Controllers:WaitForChild("MerchantController"))
local OfflineIncomeController = require(Controllers:WaitForChild("OfflineIncomeController"))

local InputController = {}
local started = false

local function isTextInputActive(): boolean
	return UserInputService:GetFocusedTextBox() ~= nil
end

function InputController.CloseActiveModal(): boolean
	if IndexController.IsOpen() then
		IndexController.Close()
		return true
	elseif QuestStreakController.IsOpen() then
		QuestStreakController.Close()
		return true
	elseif LeaderboardController.IsOpen() then
		LeaderboardController.Close()
		return true
	elseif PetBagController.IsOpen() then
		PetBagController.Close()
		return true
	elseif InventoryController.IsOpen() then
		InventoryController.ClosePanel()
		return true
	elseif ShovelShopController.IsOpen() then
		ShovelShopController.ClosePanel()
		return true
	elseif MerchantController.IsOpen() then
		MerchantController.ClosePanel()
		return true
	elseif BaseController.IsOpen() then
		BaseController.CloseIncubatorModal()
		BaseController.CloseCelebration()
		return true
	elseif OfflineIncomeController.IsOpen() then
		OfflineIncomeController.Close()
		return true
	end
	return false
end

function InputController.IsAnyModalOpen(): boolean
	return IndexController.IsOpen()
		or QuestStreakController.IsOpen()
		or LeaderboardController.IsOpen()
		or PetBagController.IsOpen()
		or InventoryController.IsOpen()
		or ShovelShopController.IsOpen()
		or MerchantController.IsOpen()
		or BaseController.IsOpen()
		or OfflineIncomeController.IsOpen()
end

local function toggleInventory()
	if InventoryController.IsOpen() then
		InventoryController.CloseInventory()
	else
		InputController.CloseActiveModal()
		InventoryController.OpenInventory("Items")
	end
end

local function togglePets()
	if PetBagController.IsOpen() then
		PetBagController.Close()
	else
		InputController.CloseActiveModal()
		PetBagController.Toggle()
	end
end

local function toggleIndex()
	if IndexController.IsOpen() then
		IndexController.Close()
	else
		InputController.CloseActiveModal()
		IndexController.Toggle()
	end
end

local function toggleQuests()
	if QuestStreakController.IsOpen() then
		QuestStreakController.Close()
	else
		InputController.CloseActiveModal()
		QuestStreakController.Toggle()
	end
end

local function toggleLeaderboard()
	if LeaderboardController.IsOpen() then
		LeaderboardController.Close()
	else
		InputController.CloseActiveModal()
		LeaderboardController.Toggle()
	end
end

local hotbarKeys = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.Two] = 2, [Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.Three] = 3, [Enum.KeyCode.KeypadThree] = 3,
	[Enum.KeyCode.Four] = 4, [Enum.KeyCode.KeypadFour] = 4,
	[Enum.KeyCode.Five] = 5, [Enum.KeyCode.KeypadFive] = 5,
	[Enum.KeyCode.Six] = 6, [Enum.KeyCode.KeypadSix] = 6,
	[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.KeypadSeven] = 7,
	[Enum.KeyCode.Eight] = 8, [Enum.KeyCode.KeypadEight] = 8,
	[Enum.KeyCode.Nine] = 9, [Enum.KeyCode.KeypadNine] = 9,
}

local function handleInputBegan(input: InputObject, gameProcessed: boolean)
	-- DigController owns strike/cancel input while every other game panel is hidden.
	if Players.LocalPlayer:GetAttribute("DigMinigameActive") == true then return end
	if isTextInputActive() then
		return
	end

	local key = input.KeyCode

	-- Escape / Gamepad Button B closes active modal
	if key == Enum.KeyCode.Escape or key == Enum.KeyCode.ButtonB then
		if InputController.CloseActiveModal() then
			return
		end
	end

	-- Do not handle panel hotkeys if game already consumed input (unless it was a modal close)
	if gameProcessed then
		return
	end

	-- PC Keyboard Shortcuts
	if hotbarKeys[key] then
		InventoryController.SelectHotbarSlot(hotbarKeys[key])
	elseif key == Enum.KeyCode.B then
		toggleInventory()
	elseif key == Enum.KeyCode.I then
		toggleIndex()
	elseif key == Enum.KeyCode.Q then
		toggleQuests()
	end

	-- Gamepad Buttons
	if key == Enum.KeyCode.ButtonX then
		-- Xbox X / PS Square: Toggle Item Bag
		toggleInventory()
	elseif key == Enum.KeyCode.ButtonY then
		-- Xbox Y / PS Triangle: Toggle Pet Bag
		togglePets()
	elseif key == Enum.KeyCode.ButtonSelect then
		-- Xbox View / PS Share: Toggle Quests
		toggleQuests()
	elseif key == Enum.KeyCode.DPadRight then
		toggleIndex()
	elseif key == Enum.KeyCode.DPadLeft then
		toggleLeaderboard()
	end
end

function InputController.Start()
	if started then
		return
	end
	started = true

	-- These keys are intentionally inactive for gameplay; text fields still accept typing.
	ContextActionService:BindActionAtPriority(
		"DisabledGameplayShortcuts",
		function()
			return if isTextInputActive() then Enum.ContextActionResult.Pass else Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.R, Enum.KeyCode.T, Enum.KeyCode.L, Enum.KeyCode.P
	)
	UserInputService.InputBegan:Connect(handleInputBegan)
end

return InputController
