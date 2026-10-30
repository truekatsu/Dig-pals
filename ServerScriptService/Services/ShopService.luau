--!strict
-- Server-authoritative Shovel Shop catalog, non-sequential purchase [U], equip delegation, and world prompt setup (Step 7)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Util"):WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local ShovelsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Shovels"))
local ShovelkeeperModelBuilder = require(Shared:WaitForChild("ShovelkeeperModelBuilder"))
local ShovelModelBuilder = require(Shared:WaitForChild("ShovelModelBuilder"))

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
			Message = string.format("Uang belum cukup! Butuh $%d.", price),
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

local function attachShovelShopPrompt(anchorPart: BasePart, promptOffset: Vector3, actionText: string?, objectText: string?)
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
	prompt.ObjectText = objectText or "The Shovelkeeper"
	prompt.ActionText = actionText or "Bicara"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.Parent = att

	if not table.find(shopAnchorParts, anchorPart) then
		table.insert(shopAnchorParts, anchorPart)
	end
end

function ShopService.EnsureShovelShopWorldPrompts()
	table.clear(shopAnchorParts)
	local plain = workspace:FindFirstChild("Plain")
	local merchant = plain and plain:FindFirstChild("Merchant")
	if not merchant then return end
	-- Remove the former bell/counter interaction and register the NPC instead.
	for _, item in merchant:GetDescendants() do
		if item.Name == "ShovelShopPromptAttachment" or item.Name == "ShovelShopProximityPrompt" or item.Name == "ShovelShopSignGui" then
			item:Destroy()
		elseif item:IsA("BasePart") and item:GetAttribute("DigPalsShovelShopNode") then
			item:SetAttribute("DigPalsShovelShopNode", nil)
		end
	end
	local shop = merchant:FindFirstChild("TheShovelkeeper")
	local npc = shop and shop:FindFirstChild("ShovelkeeperNPC")
	local head = npc and npc:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		head.CanQuery = true
		attachShovelShopPrompt(head, Vector3.zero, "Bicara", "")
		local prompt = head.ShovelShopPromptAttachment:FindFirstChildOfClass("ProximityPrompt")
		if prompt then prompt.Style = Enum.ProximityPromptStyle.Custom end
		if not head:FindFirstChild("ShovelkeeperTalkClick") then
			local click = Instance.new("ClickDetector")
			click.Name = "ShovelkeeperTalkClick"
			click.MaxActivationDistance = 14
			click.Parent = head
		end
	end
	local counter = merchant:FindFirstChild("ShovelShop_Counter")
	if counter and counter:IsA("BasePart") then
		counter:SetAttribute("DigPalsShovelShopNode", true)
		table.insert(shopAnchorParts, counter)
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

	local plain = workspace:FindFirstChild("Plain")
	local merchant = plain and plain:FindFirstChild("Merchant")
	local shop = merchant and merchant:FindFirstChild("TheShovelkeeper")
	if shop and shop:IsA("Model") then
		ShovelkeeperModelBuilder.EnsureForShop(shop)
		ShovelModelBuilder.EnsureRustyDisplayModels(shop)
	end
	ShopService.EnsureShovelShopWorldPrompts()

	-- Dynamic listener so importing The Shovelkeeper at runtime or in studio links the bell immediately
	workspace.DescendantAdded:Connect(function(desc)
		if desc.Name == "DeskBell" or desc.Name == "Counter_Bell" then
			task.wait(0.1)
			ShopService.EnsureShovelShopWorldPrompts()
		end
	end)

	Remotes.OnServerInvoke("BuyShovel", function(player: Player, shovelId: string): BuyShovelResult
		return ShopService.BuyShovel(player, shovelId, false)
	end)
end

return ShopService
