--!strict
-- Rarity configuration and Luck factor weights

local Types = require(script.Parent.Parent.Util.Types)

export type RarityInfo = {
	Id: Types.RarityName,
	DisplayName: string,
	Order: number,
	LuckFactor: number,
	Color: Color3,
}

local Order: { Types.RarityName } = {
	"Common",
	"Uncommon",
	"Rare",
	"Epic",
	"Legendary",
}

local ById: { [Types.RarityName]: RarityInfo } = {
	Common = {
		Id = "Common",
		DisplayName = "Common",
		Order = 1,
		LuckFactor = 0,
		Color = Color3.fromRGB(180, 185, 190),
	},
	Uncommon = {
		Id = "Uncommon",
		DisplayName = "Uncommon",
		Order = 2,
		LuckFactor = 0.5,
		Color = Color3.fromRGB(90, 200, 105),
	},
	Rare = {
		Id = "Rare",
		DisplayName = "Rare",
		Order = 3,
		LuckFactor = 1.0,
		Color = Color3.fromRGB(70, 155, 245),
	},
	Epic = {
		Id = "Epic",
		DisplayName = "Epic",
		Order = 4,
		LuckFactor = 2.0,
		Color = Color3.fromRGB(175, 95, 240),
	},
	Legendary = {
		Id = "Legendary",
		DisplayName = "Legendary",
		Order = 5,
		LuckFactor = 3.0,
		Color = Color3.fromRGB(255, 190, 45),
	},
}

local LuckFactors: { [string]: number } = {
	Common = 0,
	Uncommon = 0.5,
	Rare = 1.0,
	Epic = 2.0,
	Legendary = 3.0,
}

local Rarity = {
	Order = Order,
	ById = ById,
	LuckFactors = LuckFactors,
	IndexRewards = {
		ItemRarityLuckBonus = 0.03,
		PetRarityIncomeBonus = 0.03,
		CompleteAllTitle = "Master Excavator",
	},
}

return table.freeze(Rarity)
