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

local function toggleShovelShop()
	if ShovelShopController.IsOpen() then
		ShovelShopController.ClosePanel()
	else
		InputController.CloseActiveModal()
		ShovelShopController.OpenPanel(nil)
	end
end

local function toggleInventory()
	if InventoryController.IsOpen() then
		InventoryController.ClosePanel()
	else
		InputController.CloseActiveModal()
		InventoryController.TogglePanel()
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

local function handleInputBegan(input: InputObject, gameProcessed: boolean)
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
	if key == Enum.KeyCode.B then
		toggleInventory()
	elseif key == Enum.KeyCode.P then
		togglePets()
	elseif key == Enum.KeyCode.I then
		toggleIndex()
	elseif key == Enum.KeyCode.Q then
		toggleQuests()
	elseif key == Enum.KeyCode.L then
		toggleLeaderboard()
	elseif key == Enum.KeyCode.S then
		toggleShovelShop()
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
	elseif key == Enum.KeyCode.DPadUp then
		toggleShovelShop()
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

	UserInputService.InputBegan:Connect(handleInputBegan)
end

return InputController
