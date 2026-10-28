--!strict
-- Server-authoritative Shovel Shop catalog, non-sequential purchase [U], equip delegation, and world prompt setup (Step 7)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local ShovelsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Shovels"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
local ShovelInventoryService = require(script.Parent:WaitForChild("ShovelInventoryService"))

export type BuyShovelResult = {
	Success: boolean,
	Reason: string?,
	Message: string?,
	ShovelId: string?,
	Equipped: string?,
	Owned: { string }?,
	PricePaid: number?,
	Coins: number?,
}

local SHOP_MAX_INTERACT_DISTANCE = 26

local ShopService = {}

local shopAnchorParts: { BasePart } = {}
local started = false

function ShopService.GetShopCatalog(): { Types.ShovelConfig }
	local catalog: { Types.ShovelConfig } = {}
	for _, shovelId in ShovelsConfig.ShopOrder do
		local cfg = ShovelsConfig.All[shovelId]
		if cfg and cfg.IsShopShovel then
			table.insert(catalog, cfg)
		end
	end
	return catalog
end

-- Pure profile-level purchase logic.
-- Per Step 7 [U]: purchase order is NOT required (players may buy any shop shovel directly if Coins >= Price).
-- Special shovels (MossyShovel, MoonlitShovel) have IsShopShovel == false and cannot be bought here.
function ShopService.BuyShovelInProfile(
	profile: Types.PlayerProfile,
	shovelId: string,
	autoEquip: boolean?
): BuyShovelResult
	ShovelInventoryService.SanitizeProfileShovels(profile)

	if type(shovelId) ~= "string" or ShovelsConfig.All[shovelId] == nil then
		return {
			Success = false,
			Reason = "InvalidShovel",
			Message = "Shovel tidak valid.",
			Equipped = profile.Shovels.Equipped,
			Owned = table.clone(profile.Shovels.Owned),
			Coins = profile.Coins,
		}
	end

	local cfg = ShovelsConfig.All[shovelId]
	if not cfg.IsShopShovel then
		return {
			Success = false,
			Reason = "NotForSale",
			Message = "Shovel khusus ini tidak dijual di toko.",
			Equipped = profile.Shovels.Equipped,
			Owned = table.clone(profile.Shovels.Owned),
			Coins = profile.Coins,
		}
	end

	if table.find(profile.Shovels.Owned, shovelId) ~= nil then
		return {
			Success = false,
			Reason = "AlreadyOwned",
			Message = "Kamu sudah memiliki shovel ini.",
			ShovelId = shovelId,
			Equipped = profile.Shovels.Equipped,
			Owned = table.clone(profile.Shovels.Owned),
			PricePaid = 0,
			Coins = profile.Coins,
		}
	end

	local price = math.max(0, cfg.Price)
	if profile.Coins < price then
		return {
			Success = false,
			Reason = "InsufficientCoins",
			Message = string.format("Coin belum cukup! Butuh %d Coin.", price),
			Equipped = profile.Shovels.Equipped,
			Owned = table.clone(profile.Shovels.Owned),
			PricePaid = 0,
			Coins = profile.Coins,
		}
	end

	profile.Coins = math.max(0, profile.Coins - price)
	table.insert(profile.Shovels.Owned, shovelId)
	ShovelInventoryService.SanitizeProfileShovels(profile)

	local shouldEquip = if autoEquip == nil then true else autoEquip
	if shouldEquip then
		profile.Shovels.Equipped = shovelId
	end

	return {
		Success = true,
		ShovelId = shovelId,
		Equipped = profile.Shovels.Equipped,
		Owned = table.clone(profile.Shovels.Owned),
		PricePaid = price,
		Coins = profile.Coins,
	}
end

local function createShovelShopBillboard(parent: BasePart, studOffset: Vector3)
	local existing = parent:FindFirstChild("ShovelShopSignGui")
	if existing then
		existing:Destroy()
	end

	local bb = Instance.new("BillboardGui")
	bb.Name = "ShovelShopSignGui"
	bb.Adornee = parent
	bb.Size = UDim2.fromOffset(208, 50)
	bb.StudsOffset = studOffset
	bb.AlwaysOnTop = false
	bb.MaxDistance = 65
	bb.Parent = parent

	local bg = Instance.new("Frame")
	bg.Name = "Card"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(20, 30, 44)
	bg.BackgroundTransparency = 0.10
	bg.BorderSizePixel = 0
	bg.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = bg

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(82, 204, 255)
	stroke.Thickness = 1.8
	stroke.Parent = bg

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(6, 4)
	title.Size = UDim2.new(1, -12, 0, 22)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 14
	title.TextColor3 = Color3.fromRGB(108, 220, 255)
	title.Text = "SHOVEL SHOP"
	title.Parent = bg

	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.Position = UDim2.fromOffset(6, 25)
	sub.Size = UDim2.new(1, -12, 0, 18)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamBold
	sub.TextSize = 11
	sub.TextColor3 = Color3.fromRGB(220, 232, 248)
	sub.Text = "Beli & Pakai Sekop Baru"
	sub.Parent = bg
end

local function attachShovelShopPrompt(anchorPart: BasePart, promptOffset: Vector3)
	anchorPart:SetAttribute("DigPalsShovelShopNode", true)

	local existingAtt = anchorPart:FindFirstChild("ShovelShopPromptAttachment")
	if existingAtt then
		existingAtt:Destroy()
	end
	local oldPrompt = anchorPart:FindFirstChildOfClass("ProximityPrompt")
	if oldPrompt then
		oldPrompt:Destroy()
	end

	local att = Instance.new("Attachment")
	att.Name = "ShovelShopPromptAttachment"
	att.Position = promptOffset
	att.Parent = anchorPart

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShovelShopProximityPrompt"
	prompt.ObjectText = "Shovel Shop"
	prompt.ActionText = "Buka Toko Sekop"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.Parent = att

	table.insert(shopAnchorParts, anchorPart)
end

function ShopService.EnsureShovelShopWorldPrompts()
	table.clear(shopAnchorParts)

	local plain = workspace:FindFirstChild("Plain")
	local merchantFolder = plain and plain:FindFirstChild("Merchant")
	local shopCounter = merchantFolder and merchantFolder:FindFirstChild("ShovelShop_Counter")
	if shopCounter and shopCounter:IsA("BasePart") then
		local oldBillboard = shopCounter:FindFirstChild("ShovelShopSignGui")
		if oldBillboard then
			oldBillboard:Destroy()
		end
		attachShovelShopPrompt(shopCounter, Vector3.new(0, 1.8, 0))
	end
end

function ShopService.GetShopAnchorCount(): number
	return #shopAnchorParts
end

function ShopService.IsPlayerNearShovelShop(player: Player, posOverride: Vector3?): boolean
	local pos = posOverride
	if not pos then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			pos = root.Position
		end
	end
	if not pos then
		return false
	end

	for _, part in shopAnchorParts do
		if part.Parent ~= nil then
			local dx = pos.X - part.Position.X
			local dz = pos.Z - part.Position.Z
			local horizDist = math.sqrt(dx * dx + dz * dz)
			if horizDist <= SHOP_MAX_INTERACT_DISTANCE then
				return true
			end
		end
	end
	return false
end

function ShopService.BuyShovel(
	player: Player,
	shovelId: string,
	bypassProximityForTest: boolean?
): BuyShovelResult
	if not bypassProximityForTest and not ShopService.IsPlayerNearShovelShop(player) then
		return {
			Success = false,
			Reason = "TooFarFromShop",
			Message = "Dekati Shovel Shop di Hub terlebih dahulu.",
		}
	end

	local profile = PlayerState.Get(player)
	if not profile then
		return {
			Success = false,
			Reason = "ProfileNotLoaded",
			Message = "Data pemain sedang dimuat.",
		}
	end

	local result: BuyShovelResult = {
		Success = false,
		Reason = "Unknown",
	}

	local mutated = PlayerState.Mutate(player, function(prof: Types.PlayerProfile)
		result = ShopService.BuyShovelInProfile(prof, shovelId, true)
	end)

	if not mutated then
		return {
			Success = false,
			Reason = "MutateFailed",
			Message = "Gagal memproses pembelian shovel.",
		}
	end

	if result.Success then
		ShovelInventoryService.SetToolActive(player, true)
		DataService.SavePlayer(player)

		if shovelId == "IronShovel" then
			local DebugService = require(script.Parent:WaitForChild("DebugService"))
			local prof = PlayerState.Get(player)
			if prof then
				DebugService.OnIronShovelAcquired(player, prof)
			end
		end
	end

	return result
end

function ShopService.EquipShovel(player: Player, shovelId: string): ShovelInventoryService.EquipResult
	return ShovelInventoryService.EquipShovel(player, shovelId)
end

function ShopService.Start()
	if started then
		return
	end
	started = true

	ShopService.EnsureShovelShopWorldPrompts()

	Remotes.OnServerInvoke("BuyShovel", function(player: Player, shovelId: string): BuyShovelResult
		return ShopService.BuyShovel(player, shovelId, false)
	end)
end

return ShopService
