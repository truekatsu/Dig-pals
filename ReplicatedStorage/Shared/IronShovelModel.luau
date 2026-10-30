--!strict
-- Working iron spade: the Rusty silhouette refined toward the supplied reference.
local RustyModel = require(script.Parent:WaitForChild("RustyShovelModel"))
local Asset = require(script.Parent:WaitForChild("IronShovelAsset"))
local IronModel = {}
IronModel.Version = "ForgedIronV2"

function IronModel.GetPartSpecs(): {any}
	local definition = Asset.Material
	local materialService = game:GetService("MaterialService")
	if not materialService:FindFirstChild(definition.Name) then
		local material = Instance.new("MaterialVariant")
		material.Name = definition.Name
		material.BaseMaterial = Enum.Material.Metal
		material.ColorMap = definition.ColorMap
		material.NormalMap = definition.NormalMap
		material.RoughnessMap = definition.RoughnessMap
		material.MetalnessMap = definition.MetalnessMap
		material.StudsPerTile = definition.StudsPerTile
		material.MaterialPattern = Enum.MaterialPattern.Organic
		material.Parent = materialService
	end
	local specs = {}
	local iron = Color3.fromRGB(159, 161, 158)
	local wood = Color3.fromRGB(128, 89, 45)
	local function part(name: string, size: Vector3, cf: CFrame, color: Color3, className: string?)
		table.insert(specs, {Name=name, Size=size, CFrame=cf, Color=color,
			Material=Enum.Material.Metal, ClassName=className})
	end
	for _, spec in RustyModel.GetPartSpecs() do
		if spec.Name:find("WornEdge") or spec.Name:find("SocketPin") then continue end
		spec.Color = iron
		spec.Material = Enum.Material.Metal
		if spec.Name == "Handle" then
			-- Invisible unrotated hand hold; the separate cylindrical shaft is visual.
			spec.Size = Vector3.new(.16, .5, .16)
			spec.Transparency = 1
		elseif spec.Name == "GripTop" then
			spec.Color, spec.Material, spec.Shape = wood, Enum.Material.Wood, Enum.PartType.Cylinder
		elseif spec.Name == "Blade" then
			spec.Size = Vector3.new(1.16, .85, .16)
		elseif spec.Name == "BladeTipLeft" or spec.Name == "BladeTipRight" then
			local sign = if spec.Name == "BladeTipLeft" then -1 else 1
			spec.Size = Vector3.new(.16, .46, .42)
			spec.CFrame = CFrame.new(sign * .37, -1.955, 0) * CFrame.Angles(0, sign * math.pi / 2, 0) * CFrame.Angles(math.pi, 0, 0)
		elseif spec.Name == "BladeSocket" then
			spec.Size = Vector3.new(.29, .9, .26)
			spec.CFrame = CFrame.new(0, -1.08, 0)
		end
		table.insert(specs, spec)
	end
	part("WoodShaft", Vector3.new(2.55, .19, .19), CFrame.Angles(0, 0, math.pi / 2), wood)
	specs[#specs].Material = Enum.Material.Wood
	specs[#specs].Shape = Enum.PartType.Cylinder
	part("BladeTipCenter", Vector3.new(.32, .46, .16), CFrame.new(0, -1.955, 0), iron)
	for _, sign in {-1, 1} do
		part("SocketTaper" .. sign, Vector3.new(.26, .3, .145), CFrame.new(sign * .0725, -1.68, 0) * CFrame.Angles(0, sign * math.pi / 2, 0) * CFrame.Angles(math.pi, 0, 0), iron, "WedgePart")
		for _, face in {-1, 1} do
			part("CuttingEdge" .. sign .. "_" .. face, Vector3.new(.016, .61, .009), CFrame.new(sign * .37, -1.955, face * .085) * CFrame.Angles(0, 0, math.rad(-sign * 42.4)), Color3.fromRGB(182, 184, 179))
		end
	end
	for _, spec in specs do
		if spec.Material == Enum.Material.Metal and not spec.Name:find("CuttingEdge") then
			spec.Color = Color3.fromRGB(210, 213, 208)
			spec.MaterialVariant = definition.Name
		end
	end
	return specs
end

return table.freeze(IronModel)
