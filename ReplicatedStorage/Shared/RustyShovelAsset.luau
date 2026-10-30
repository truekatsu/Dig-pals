--!strict
-- Oxide No. 07 Blender mesh. Clone ShovelAssets/RustyShovelMesh to retain PBR.
-- Centered Y-up geometry; shared ShovelCarry owns every carry/hand offset.
return table.freeze({
 Version = "Oxide07BlenderV2",
 ModelId = "rbxassetid://112557336512404",
 MeshId = "rbxassetid://84345880591592",
 ColorMap = "rbxassetid://124721749732343",
 NormalMap = "rbxassetid://108764324809774",
 RoughnessMap = "rbxassetid://127714652644798",
 MetalnessMap = "rbxassetid://140360628984439",
 -- This Studio session cannot load texture pack 92971506321951.
 -- Keep the PBR source intact; show the verified albedo until it is available.
 UsePBR = false,
 Size = Vector3.new(1.524149169921875, 5.4, 0.348510093688965),
 Scale = 0.01, -- Raw FBX mesh was imported at 540 studs; albedo fallback only.
 Icon = "rbxassetid://86186130823192",
})
