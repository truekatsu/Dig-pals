--!strict
-- Centralized placeholder asset IDs and visual colors for Dig Pals

local AssetIds = {
	Sounds = {
		StrikePerfect = "rbxasset://sounds/electronicpingshort.wav",
		StrikeGood = "rbxasset://sounds/snap.mp3",
		StrikeMiss = "rbxasset://sounds/uianvil.wav",
		MoundBreak = "rbxasset://sounds/uianvil.wav",
		RareDrop = "rbxasset://sounds/electronicpingshort.wav",
		EggHatch = "rbxasset://sounds/snap.mp3",
		LevelUp = "rbxasset://sounds/electronicpingshort.wav",
		BaseUpgrade = "rbxasset://sounds/action_jump.mp3",
		CoinGain = "rbxasset://sounds/button_click.wav",
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
