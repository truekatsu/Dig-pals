--!strict
-- Main client bootstrapper for Dig Pals (MoundVisuals, HudController, InventoryController, MerchantController, & DigController)

local Controllers = script.Parent:WaitForChild("Controllers")
local MoundVisuals = require(Controllers:WaitForChild("MoundVisuals"))
local HudController = require(Controllers:WaitForChild("HudController"))
local InventoryController = require(Controllers:WaitForChild("InventoryController"))
local MerchantController = require(Controllers:WaitForChild("MerchantController"))
local DigController = require(Controllers:WaitForChild("DigController"))

MoundVisuals.Start()
HudController.Start()
InventoryController.Start()
MerchantController.Start()
DigController.Start()
