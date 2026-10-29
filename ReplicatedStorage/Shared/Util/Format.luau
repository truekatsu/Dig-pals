--!strict
-- Number and duration formatting utilities

local Format = {}

-- Currency display only; saved balances and remote payloads keep their existing schema.
function Format.Money(amount: number, compact: boolean?): string
	local value = math.max(0, math.floor(amount))
	if not compact then return "$" .. Format.Commas(value) end
	local suffixes = { "", "K", "M", "B", "T" }
	local tier = 1
	while value >= 999.95 and tier < #suffixes do
		value /= 1000
		tier += 1
	end
	if tier == 1 then return "$" .. tostring(value) end
	local digits = string.format("%.1f", value):gsub("%.0$", "")
	return "$" .. digits .. suffixes[tier]
end

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
