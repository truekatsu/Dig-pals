--!strict
-- Same starter-shovel silhouette as Rusty, with a thick, rough stone spade.
local RustyModel = require(script.Parent:WaitForChild("RustyShovelModel"))
local Asset = require(script.Parent:WaitForChild("StoneShovelAsset"))
local StoneModel = {}
StoneModel.Version = "HandhewnStoneV2"

function StoneModel.GetPartSpecs(): {any}
	local definition = Asset.Material
	local materialService = game:GetService("MaterialService")
	if not materialService:FindFirstChild(definition.Name) then
		local material = Instance.new("MaterialVariant")
		material.Name = definition.Name
		material.BaseMaterial = Enum.Material.Granite
		material.ColorMap = definition.ColorMap
		material.NormalMap = definition.NormalMap
		material.RoughnessMap = definition.RoughnessMap
		material.MetalnessMap = definition.MetalnessMap
		material.StudsPerTile = definition.StudsPerTile
		material.MaterialPattern = Enum.MaterialPattern.Organic
		material.Parent = materialService
	end
	local specs = {}
	for _, spec in RustyModel.GetPartSpecs() do
		-- Stone has no metal cutting strips, rust patches, or socket rivets.
		if spec.Name:find("WornEdge") or spec.Name:find("SocketPin") then continue end
		if spec.Name == "Handle" or spec.Name == "GripTop" then
			spec.Color = Color3.fromRGB(119, 89, 57)
		elseif spec.Name == "GripBase" or spec.Name == "GripLeft" or spec.Name == "GripRight" then
			spec.Color = Color3.fromRGB(101, 75, 49)
			spec.Material = Enum.Material.Wood
		elseif spec.Name == "Blade" then
			spec.Size = Vector3.new(1.16, .85, .28)
			spec.Color = Color3.fromRGB(210, 216, 220)
			spec.Material = Enum.Material.Granite
			spec.MaterialVariant = definition.Name
		elseif spec.Name == "BladeTipLeft" or spec.Name == "BladeTipRight" then
			spec.Size = Vector3.new(.28, .55, .58)
			spec.Color = Color3.fromRGB(210, 216, 220)
			spec.Material = Enum.Material.Granite
			spec.MaterialVariant = definition.Name
		elseif spec.Name == "LeftFootRest" or spec.Name == "RightFootRest" then
			spec.Size = Vector3.new(.48, .13, .30)
			spec.Color = Color3.fromRGB(103, 113, 124)
			spec.Material = Enum.Material.Slate
		else
			spec.Color = Color3.fromRGB(104, 114, 124)
			spec.Material = Enum.Material.Slate
		end
		table.insert(specs, spec)
	end
	-- Small bindings make the stone head read as a simple hafted slab.
	for i = 0, 2 do
		table.insert(specs, {
			Name = "StoneBinding" .. i,
			Size = Vector3.new(.33, .065, .32),
			CFrame = CFrame.new(0, -.87 - i * .12, 0),
			Color = Color3.fromRGB(111, 91, 64),
			Material = Enum.Material.Fabric,
		})
	end
	return specs
end

return table.freeze(StoneModel)
