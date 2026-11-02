--!strict
-- Mayor quests are separate, one-time tasks. ConfigService overrides apply to new offers.
return table.freeze({
	Pool = {
		{
			Id = "MayorTownHelp",
			DisplayName = "Helping the Town",
			EventType = "MoundCleared",
			DescriptionFormat = "Gali %d gundukan untuk membantu warga.",
			Target = 5,
			RewardCoins = 150,
			TargetConfigKey = "MayorTownHelpTarget",
			RewardConfigKey = "MayorTownHelpRewardCoins",
		},
	},
})
