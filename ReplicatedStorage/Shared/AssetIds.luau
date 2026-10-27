--!strict
-- Centralized placeholder asset IDs and visual colors for Dig Pals

local AssetIds = {
	Sounds = {
		StrikePerfect = "rbxassetid://9119713951",
		StrikeGood = "rbxassetid://9119713520",
		StrikeMiss = "rbxassetid://9119720940",
		MoundBreak = "rbxassetid://9114221580",
		RareDrop = "rbxassetid://9119707219",
		EggHatch = "rbxassetid://9119707015",
		LevelUp = "rbxassetid://9119706773",
		BaseUpgrade = "rbxassetid://9119706511",
		CoinGain = "rbxassetid://9119706183",
	},
	Icons = {
		Coin = "rbxassetid://6034973115",
		Bag = "rbxassetid://6034767621",
		Shovel = "rbxassetid://6034509993",
		Egg = "rbxassetid://6034287594",
		Pet = "rbxassetid://6034287525",
		Quest = "rbxassetid://6034996695",
		Index = "rbxassetid://6034989545",
	},
	Colors = {
		MoundPersonal = Color3.fromRGB(138, 94, 59),
		MoundShared = Color3.fromRGB(212, 160, 56),
		ZoneGood = Color3.fromRGB(85, 200, 110),
		ZonePerfect = Color3.fromRGB(255, 215, 65),
		ZoneMiss = Color3.fromRGB(220, 75, 75),
	},
}

return table.freeze(AssetIds)
