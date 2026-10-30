--!strict
-- Temporarily suppress other HUD layers without losing their previous enabled states.
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local GuiService = game:GetService("GuiService")
local LocalPlayer = Players.LocalPlayer

local DigFocusController = {}
local active = false
local keptGui: ScreenGui? = nil
local previousGuis: { [ScreenGui]: boolean } = {}
local previousCore: { [Enum.CoreGuiType]: boolean } = {}
local connections: { RBXScriptConnection } = {}
local previousSelection: GuiObject? = nil

local function suppress(instance: Instance)
	if not active or not instance:IsA("ScreenGui") or instance == keptGui or previousGuis[instance] ~= nil then return end
	previousGuis[instance] = instance.Enabled
	instance.Enabled = false
	table.insert(connections, instance:GetPropertyChangedSignal("Enabled"):Connect(function()
		if active and instance.Enabled then instance.Enabled = false end
	end))
end

function DigFocusController.Enter(minigameGui: ScreenGui)
	if active then return end
	active = true
	keptGui = minigameGui
	previousSelection = GuiService.SelectedObject
	GuiService.SelectedObject = nil
	LocalPlayer:SetAttribute("DigMinigameActive", true)
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	table.insert(connections, playerGui.DescendantAdded:Connect(suppress))
	for _, instance in playerGui:GetDescendants() do suppress(instance) end
	for _, coreType in Enum.CoreGuiType:GetEnumItems() do
		if coreType == Enum.CoreGuiType.All then continue end
		local ok, enabled = pcall(function() return StarterGui:GetCoreGuiEnabled(coreType) end)
		if ok and type(enabled) == "boolean" then
			previousCore[coreType] = enabled
			if enabled then pcall(function() StarterGui:SetCoreGuiEnabled(coreType, false) end) end
		end
	end
end

function DigFocusController.Exit()
	if not active then return end
	active = false
	for _, connection in connections do connection:Disconnect() end
	table.clear(connections)
	for gui, enabled in previousGuis do
		if gui.Parent then gui.Enabled = enabled end
	end
	for coreType, enabled in previousCore do
		pcall(function() StarterGui:SetCoreGuiEnabled(coreType, enabled) end)
	end
	if previousSelection and previousSelection:IsDescendantOf(LocalPlayer.PlayerGui) then
		pcall(function() GuiService.SelectedObject = previousSelection end)
	end
	table.clear(previousGuis)
	table.clear(previousCore)
	keptGui, previousSelection = nil, nil
	LocalPlayer:SetAttribute("DigMinigameActive", false)
end

return DigFocusController
