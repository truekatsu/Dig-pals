--!strict
local Config = require(script.Parent.Parent.Config.DigMinigame)
local Mounds = require(script.Parent.Parent.Config.Mounds)

export type Attempt = {
	ShovelId: string,
	StartTime: number,
	Speed: number,
	GoodWidth: number,
	PerfectWidth: number,
	ZoneCenter: number,
	Misses: number,
	MaxMisses: number,
	Failed: boolean,
}

local DigTiming = {}
local rng = Random.new()

function DigTiming.NextZone(previous: number?, goodWidth: number): number
	local margin = goodWidth * 0.5 + Config.ZoneEdgeMargin
	local center = rng:NextNumber(margin, 1 - margin)
	if previous and math.abs(center - previous) < Config.MinimumZoneShift then
		center = if previous >= 0.5 then margin else 1 - margin
	end
	return center
end

function DigTiming.New(shovelId: string, sizeName: string, now: number, misses: number?): Attempt
	local shovel = Config.Shovels[shovelId] or Config.Shovels.RustyShovel
	local size = (Mounds.Sizes :: any)[sizeName] or Mounds.Shared
	local timing = size.Timing
	return {
		ShovelId = shovelId,
		StartTime = now,
		Speed = timing.Speed * shovel.SpeedMultiplier,
		GoodWidth = timing.GoodWidth,
		PerfectWidth = timing.PerfectWidth,
		ZoneCenter = DigTiming.NextZone(nil, timing.GoodWidth),
		Misses = misses or 0,
		MaxMisses = shovel.MaxMisses,
		Failed = false,
	}
end

function DigTiming.RecordStrike(attempt: Attempt, grade: string): boolean
	if grade == "Miss" then attempt.Misses += 1 end
	attempt.Failed = attempt.Misses >= attempt.MaxMisses
	attempt.ZoneCenter = DigTiming.NextZone(attempt.ZoneCenter, attempt.GoodWidth)
	return attempt.Failed
end

return table.freeze(DigTiming)
