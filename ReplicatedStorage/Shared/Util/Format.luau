--!strict
-- Number and duration formatting utilities

local Format = {}

function Format.Commas(value: number): string
	local rounded = math.floor(value)
	local formatted = tostring(rounded)
	while true do
		local nextFormatted, count = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		formatted = nextFormatted
		if count == 0 then
			break
		end
	end
	return formatted
end

function Format.Duration(seconds: number): string
	local clamped = math.max(0, math.ceil(seconds))
	local hours = math.floor(clamped / 3600)
	local mins = math.floor((clamped % 3600) / 60)
	local secs = clamped % 60
	if hours > 0 then
		return string.format("%02d:%02d:%02d", hours, mins, secs)
	end
	return string.format("%02d:%02d", mins, secs)
end

return table.freeze(Format)
