--!strict
-- Weighted probability, Luck calculation, and deterministic timing bar math utilities

local Rarity = require(script.Parent.Parent.Config.Rarity)
local Types = require(script.Parent.Parent.Util.Types)

local Weighted = {}

local defaultRandom = Random.new()

-- Position 0..1 of the indicator, t = seconds since the bar started, speed = bar lengths per second
function Weighted.IndicatorPos(t: number, speed: number): number
	local clampedT = math.max(0, t)
	local x = (clampedT * speed) % 2
	return if x <= 1 then x else 2 - x
end

function Weighted.GradeAtPosition(pos: number, goodWidth: number, perfectWidth: number, zoneCenter: number?): Types.StrikeGrade
	local distFromCenter = math.abs(pos - (zoneCenter or 0.5))
	if distFromCenter <= (perfectWidth * 0.5) then
		return "Perfect"
	elseif distFromCenter <= (goodWidth * 0.5) then
		return "Good"
	end
	return "Miss"
end

-- Evaluates the best strike grade achievable within [t - latencyTolerance, t]
function Weighted.EvaluateStrikeWithLatency(
	elapsedSeconds: number,
	speed: number,
	goodWidth: number,
	perfectWidth: number,
	latencyToleranceSeconds: number,
	zoneCenter: number?
): (Types.StrikeGrade, number)
	local tMax = math.max(0, elapsedSeconds)
	local tolerance = math.max(0, latencyToleranceSeconds)
	if tolerance <= 0 then
		local pos = Weighted.IndicatorPos(tMax, speed)
		return Weighted.GradeAtPosition(pos, goodWidth, perfectWidth, zoneCenter), pos
	end

	local tMin = math.max(0, tMax - tolerance)
	local sampleCount = 24
	local bestDist = math.huge
	local bestPos = Weighted.IndicatorPos(tMax, speed)

	for i = 0, sampleCount do
		local alpha = i / sampleCount
		local sampleT = tMin + (tMax - tMin) * alpha
		local pos = Weighted.IndicatorPos(sampleT, speed)
		local dist = math.abs(pos - (zoneCenter or 0.5))
		if dist < bestDist then
			bestDist = dist
			bestPos = pos
		end
	end

	return Weighted.GradeAtPosition(bestPos, goodWidth, perfectWidth, zoneCenter), bestPos
end

function Weighted.Sum(weights: { [string]: number }): number
	local total = 0
	for _, weight in weights do
		total += weight
	end
	return total
end

function Weighted.ApplyLuck(weights: { [string]: number }, luck: number): { [string]: number }
	local out: { [string]: number } = {}
	local total = 0
	for rarity, w in weights do
		local factor = Rarity.LuckFactors[rarity] or 0
		local multiplier = 1 + (luck - 1) * factor
		local adjusted = math.max(0, w * multiplier)
		out[rarity] = adjusted
		total += adjusted
	end
	if total > 0 then
		for rarity, w in out do
			out[rarity] = w / total
		end
	end
	return out
end

function Weighted.Pick(weights: { [string]: number }, rng: Random?): string
	local randomObj = rng or defaultRandom
	local total = 0
	for _, w in weights do
		if w > 0 then
			total += w
		end
	end

	if total <= 0 then
		for key in weights do
			return key
		end
		return ""
	end

	local roll = randomObj:NextNumber(0, total)
	local cumulative = 0
	local fallbackKey = ""

	for key, w in weights do
		if w > 0 then
			fallbackKey = key
			cumulative += w
			if roll <= cumulative then
				return key
			end
		end
	end

	return fallbackKey
end

return table.freeze(Weighted)
