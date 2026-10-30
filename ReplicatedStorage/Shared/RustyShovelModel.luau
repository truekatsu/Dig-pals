--!strict
-- Starter shovel: plain timber, an open D grip, and a weathered iron spade.
-- All geometry is local to the hand hold. +Y is the grip; -Y is the blade.
local RustyShovelModel = {}
RustyShovelModel.Version = "WeatheredRustyV3"

function RustyShovelModel.GetPartSpecs(): {any}
	local specs = {}
	local wood = Color3.fromRGB(108, 78, 49)
	local rust = Color3.fromRGB(127, 83, 54)
	local darkRust = Color3.fromRGB(94, 65, 44)
	local iron = Color3.fromRGB(101, 99, 87)
	local function part(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, className: string?)
		table.insert(specs, {Name = name, Size = size, CFrame = cf, Color = color, Material = material, ClassName = className})
	end
	part("Handle", Vector3.new(.19, 2.55, .19), CFrame.identity, wood, Enum.Material.Wood)
	part("GripSocket", Vector3.new(.27, .24, .24), CFrame.new(0, 1.25, 0), darkRust, Enum.Material.Metal)
	part("GripBase", Vector3.new(.50, .12, .21), CFrame.new(0, 1.31, 0), darkRust, Enum.Material.Metal)
	part("GripLeft", Vector3.new(.12, .51, .19), CFrame.new(-.27, 1.56, 0) * CFrame.Angles(0, 0, math.rad(12)), rust, Enum.Material.Metal)
	part("GripRight", Vector3.new(.12, .51, .19), CFrame.new(.27, 1.56, 0) * CFrame.Angles(0, 0, math.rad(-12)), rust, Enum.Material.Metal)
	part("GripTop", Vector3.new(.73, .18, .23), CFrame.new(0, 1.85, 0), wood, Enum.Material.Wood)
	part("BladeSocket", Vector3.new(.29, .62, .27), CFrame.new(0, -1.07, 0), darkRust, Enum.Material.CorrodedMetal)
	part("Blade", Vector3.new(1.16, .85, .13), CFrame.new(0, -1.30, 0), rust, Enum.Material.CorrodedMetal)
	-- Mirrored wedges taper the lower edge to the familiar spade point.
	part("BladeTipLeft", Vector3.new(.13, .55, .58), CFrame.new(-.29, -2.0, 0) * CFrame.Angles(0, -math.pi / 2, 0) * CFrame.Angles(math.pi, 0, 0), rust, Enum.Material.CorrodedMetal, "WedgePart")
	part("BladeTipRight", Vector3.new(.13, .55, .58), CFrame.new(.29, -2.0, 0) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(math.pi, 0, 0), rust, Enum.Material.CorrodedMetal, "WedgePart")
	part("LeftFootRest", Vector3.new(.48, .10, .26), CFrame.new(-.34, -.87, 0), iron, Enum.Material.Metal)
	part("RightFootRest", Vector3.new(.48, .10, .26), CFrame.new(.34, -.87, 0), iron, Enum.Material.Metal)
	-- Built-in corrosion supplies fine irregular pitting instead of square patches.
	-- Narrow exposed cutting edges and a small socket pin keep the wear functional.
	for _, side in {-1, 1} do
		part("WornEdgeLeft" .. side, Vector3.new(.018, .77, .009), CFrame.new(-.287, -1.997, side * .070) * CFrame.Angles(0, 0, math.rad(46.5)), iron, Enum.Material.Metal)
		part("WornEdgeRight" .. side, Vector3.new(.014, .58, .009), CFrame.new(.22, -2.06, side * .070) * CFrame.Angles(0, 0, math.rad(-46.5)), iron, Enum.Material.Metal)
		part("SocketPin" .. side, Vector3.new(.075, .075, .025), CFrame.new(0, -1.10, side * .141), iron, Enum.Material.Metal)
		specs[#specs].Shape = Enum.PartType.Ball
	end
	return specs
end

return table.freeze(RustyShovelModel)
