--!strict
-- Area 1 (Plain Grass) & BasePlots Workspace geometry manifest reconstructed from map.blend (8,178 parts)

local MapManifest = {
	SpawnPoint = Vector3.new(0, 1.2, 0),
	SpawnZone = {
		Path = "Workspace.Plain.SpawnZone",
		Position = Vector3.new(10, -0.5, -5),
		Size = Vector3.new(290, 1, 185),
	},
	Hub = {
		Path = "Workspace.Plain.Hub",
		SignBoard = "PlainGrassSign_Board",
		Leaderboard = "Leaderboard_Board",
		TutorialSign = "TutorialSign_Board",
	},
	Merchant = {
		Path = "Workspace.Plain.Merchant",
		ItemMerchantFloor = Vector3.new(-20.0, 0.25, -92.0),
		ItemMerchantCounter = Vector3.new(-20.0, 1.95, -86.5),
		ShovelShopFloor = Vector3.new(20.0, 0.25, -92.0),
		ShovelShopCounter = Vector3.new(20.0, 1.95, -86.5),
	},
	SharedMoundSpawns = {
		Path = "Workspace.Plain.SharedMoundSpawns",
		Points = {
			SharedSpawn01 = Vector3.new(0.0, 3.0, 48.0),
			SharedSpawn02 = Vector3.new(-65.0, 3.0, -10.0),
			SharedSpawn03 = Vector3.new(65.0, 3.0, -10.0),
			SharedSpawn04 = Vector3.new(-35.0, 3.0, -70.0),
			SharedSpawn05 = Vector3.new(35.0, 3.0, -70.0),
		},
	},
	SandyGate = {
		Path = "Workspace.Plain.SandyGate",
		SignPosition = Vector3.new(207.47, 5.75, -65.0),
	},
	BasePlots = {
		Path = "Workspace.BasePlots",
		PlotGrounds = {
			Plot1 = Vector3.new(-108.0, 0.25, 138.0),
			Plot2 = Vector3.new(-68.0, 0.25, 161.0),
			Plot3 = Vector3.new(-24.0, 0.25, 173.0),
			Plot4 = Vector3.new(24.0, 0.25, 173.0),
			Plot5 = Vector3.new(68.0, 0.25, 161.0),
			Plot6 = Vector3.new(108.0, 0.25, 138.0),
		},
	},
}

return table.freeze(MapManifest)
