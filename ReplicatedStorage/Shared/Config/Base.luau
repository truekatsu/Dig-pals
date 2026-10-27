--!strict
-- Base configuration (plot levels, incubator slots, base pet slots, egg bag base capacity)

local Types = require(script.Parent.Parent.Util.Types)

local Levels: { [number]: Types.BaseLevelConfig } = {
	[1] = {
		Level = 1,
		UpgradeCost = 0,
		IncubatorSlots = 1,
		PetSlots = 2,
		PlotScale = Vector3.new(30, 1, 30),
	},
	[2] = {
		Level = 2,
		UpgradeCost = 800,
		IncubatorSlots = 2,
		PetSlots = 4,
		PlotScale = Vector3.new(36, 1, 36),
	},
	[3] = {
		Level = 3,
		UpgradeCost = 3500,
		IncubatorSlots = 3,
		PetSlots = 6,
		PlotScale = Vector3.new(42, 1, 42),
	},
	[4] = {
		Level = 4,
		UpgradeCost = 15000,
		IncubatorSlots = 4,
		PetSlots = 8,
		PlotScale = Vector3.new(48, 1, 48),
	},
	[5] = {
		Level = 5,
		UpgradeCost = 60000,
		IncubatorSlots = 5,
		PetSlots = 10,
		PlotScale = Vector3.new(56, 1, 56),
	},
}

local Base = {
	MaxPlots = 8,
	MaxBaseLevel = 5,
	BaseEggBagCapacity = 4, -- Total EggBag capacity = BaseEggBagCapacity + BaseLevel
	Levels = Levels,
}

return table.freeze(Base)
