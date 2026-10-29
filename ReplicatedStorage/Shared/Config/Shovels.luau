--!strict
-- Shovel configuration (5 shop shovels + 2 special shared mound shovels)

local RustyAsset = require(script.Parent.Parent:WaitForChild("RustyShovelAsset"))

local StoneAsset = require(script.Parent.Parent:WaitForChild("StoneShovelAsset"))

local IronAsset = require(script.Parent.Parent:WaitForChild("IronShovelAsset"))

local Types = require(script.Parent.Parent.Util.Types)

local ShopOrder: { string } = {
	"RustyShovel",
	"StoneShovel",
	"IronShovel",
	"GoldenShovel",
	"DiamondShovel",
}

local SpecialOrder: { string } = {
	"MossyShovel",
	"MoonlitShovel",
}

local AllOrder: { string } = {
	"RustyShovel",
	"StoneShovel",
	"IronShovel",
	"GoldenShovel",
	"MossyShovel",
	"DiamondShovel",
	"MoonlitShovel",
}

local MaxStats = {
	Power = 140,
	DigRate = 2.0,
	Luck = 2.5,
}

local All: { [string]: Types.ShovelConfig } = {
	RustyShovel = {
		Id = "RustyShovel",
		DisplayName = "Rusty Shovel",
		Description = "Sekop kayu tua berbilah besi karat. Sederhana namun andal untuk mulai menggali di Plain Grass.",
		Rarity = "Common",
		Price = 0,
		Power = 10,
		DigSpeed = 1.0,
		Luck = 1.0,
		IsShopShovel = true,
		ToolName = "RustyShovel",
		Icon = RustyAsset.Icon,
	},
	StoneShovel = {
		Id = "StoneShovel",
		DisplayName = "Stone Shovel",
		Description = "Sekop batu pahat tebal dengan gagang kayu kukuh. Memberikan daya gali lebih kuat dan ayunan lebih sigap.",
		Rarity = "Uncommon",
		Price = 400,
		Power = 18,
		DigSpeed = 0.9,
		Luck = 1.2,
		IsShopShovel = true,
		ToolName = "StoneShovel",
		Icon = StoneAsset.Icon,
	},
	IronShovel = {
		Id = "IronShovel",
		DisplayName = "Iron Shovel",
		Description = "Sekop baja tempa berpelindung paku keling. Menghancurkan tanah keras dengan cepat dan membuka syarat area berikutnya.",
		Rarity = "Rare",
		Price = 2500,
		Power = 32,
		DigSpeed = 0.8,
		Luck = 1.5,
		IsShopShovel = true,
		ToolName = "IronShovel",
		Icon = IronAsset.Icon,
	},
	GoldenShovel = {
		Id = "GoldenShovel",
		DisplayName = "Golden Shovel",
		Description = "Sekop berlapis emas murni berhias permata merah yang meningkatkan peluang menemukan item dan telur langka.",
		Rarity = "Epic",
		Price = 12000,
		Power = 60,
		DigSpeed = 0.7,
		Luck = 1.85,
		IsShopShovel = true,
		ToolName = "GoldenShovel",
		Icon = "rbxassetid://6034509993",
	},
	DiamondShovel = {
		Id = "DiamondShovel",
		DisplayName = "Diamond Shovel",
		Description = "Sekop kristal berlian berinti energi sian. Tajam, sangat cepat, dan memaksimalkan keberuntungan penggalian.",
		Rarity = "Legendary",
		Price = 50000,
		Power = 110,
		DigSpeed = 0.6,
		Luck = 2.2,
		IsShopShovel = true,
		ToolName = "DiamondShovel",
		Icon = "rbxassetid://6034509993",
	},
	MossyShovel = {
		Id = "MossyShovel",
		DisplayName = "Mossy Shovel",
		Description = "Sekop relik akar kuno berselimut lumut zamrud dari Rare Mound. Memancarkan aura keberuntungan alam.",
		Rarity = "Epic",
		Price = 0,
		Power = 75,
		DigSpeed = 0.65,
		Luck = 2.0,
		IsShopShovel = false,
		ToolName = "MossyShovel",
		Icon = "rbxassetid://6034509993",
	},
	MoonlitShovel = {
		Id = "MoonlitShovel",
		DisplayName = "Moonlit Shovel",
		Description = "Sekop legendaris bulan sabit bercahaya bintang dari Rare Mound. Kekuatan, kecepatan, dan hoki tertinggi.",
		Rarity = "Legendary",
		Price = 0,
		Power = 140,
		DigSpeed = 0.55,
		Luck = 2.5,
		IsShopShovel = false,
		ToolName = "MoonlitShovel",
		Icon = "rbxassetid://6034509993",
	},
}

local Shovels = {
	ShopOrder = ShopOrder,
	SpecialOrder = SpecialOrder,
	AllOrder = AllOrder,
	MaxStats = table.freeze(MaxStats),
	All = All,
}

return table.freeze(Shovels)
