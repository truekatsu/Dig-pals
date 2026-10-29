--!strict
-- Imported from Assets/Models/RustyShovel/Rusty_Shovel.fbx.
-- One shared definition for gameplay, shop previews, inventory, and hotbar.
return table.freeze({
 Version = "BatteredShovelV1",
 MeshId = "rbxassetid://87169671105639",
 ColorMap = "rbxassetid://101524437679882",
 RoughnessMap = "rbxassetid://99828948478004",
 MetalnessMap = "rbxassetid://110601777729907",
 Icon = "rbxassetid://73230995952848",
 Scale = 3.3,
 Size = Vector3.new(0.924, 3.94515, 0.2178),
 -- Source hand hold: 0.76m; mesh bounds center: 0.59775m.
 GripOffsetY = (0.59775 - 0.76) * 3.3,
})
