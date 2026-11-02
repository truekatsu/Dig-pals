--!strict
-- Shared arbitration for NPC keys and legacy UserInputService listeners.
local Guard = {}
local active = false
local consumed: {[InputObject]: boolean} = setmetatable({}, {__mode = "k"}) :: any

function Guard.SetActive(value: boolean)
	active = value
end

function Guard.Capture(input: InputObject)
	consumed[input] = true
end

function Guard.BeginUncaptured(input: InputObject)
	consumed[input] = nil
end

function Guard.IsPromptBlocked(): boolean
	return active
end

function Guard.WasConsumed(input: InputObject): boolean
	return consumed[input] == true
end

function Guard.IsBlocked(input: InputObject): boolean
	-- Keep the selecting key consumed even if it closes or replaces the dialogue.
	return active or Guard.WasConsumed(input)
end

game:GetService("UserInputService").InputBegan:Connect(function(input: InputObject)
	if not active and not consumed[input] then Guard.BeginUncaptured(input) end
end)

return Guard
