--!strict
-- Shared balance defaults. A session snapshots these values so timing never changes mid-attempt.
local shovels: { [string]: { SpeedMultiplier: number, MaxMisses: number } } = {
		RustyShovel = { SpeedMultiplier = 1.60, MaxMisses = 3 },
		StoneShovel = { SpeedMultiplier = 1.35, MaxMisses = 4 },
		IronShovel = { SpeedMultiplier = 1.12, MaxMisses = 5 },
		GoldenShovel = { SpeedMultiplier = 0.95, MaxMisses = 6 },
		MossyShovel = { SpeedMultiplier = 0.82, MaxMisses = 7 },
		DiamondShovel = { SpeedMultiplier = 0.70, MaxMisses = 8 },
		MoonlitShovel = { SpeedMultiplier = 0.60, MaxMisses = 9 },
}

return table.freeze({
	ZoneEdgeMargin = 0.04,
	MinimumZoneShift = 0.16,
	Shovels = shovels,
})
