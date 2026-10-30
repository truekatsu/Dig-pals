# Golden Shovel replacement

User-supplied Golden_Shovel.fbx and PBR atlas. Shared carry height: 5.4 studs. Source hand hold: Z=0.76m; mesh center (0, 0.5875, -0.011) in Roblox axes. Imported pivot rotation reset. GripOffset compensates for asymmetric bounds.

Roblox uploads:
- Mesh: Built from Golden_Shovel.blend (318 verts, 493 tris) via EditableMesh / MeshPart in ReplicatedStorage.ShovelAssets.GoldenShovelMesh
- Diffuse / ColorMap: 86951685279254
- Roughness: 84090128320842
- Metallic: 110757668081817
- Icon: 125427949135991

Studio template: ReplicatedStorage.ShovelAssets.GoldenShovelMesh with SurfaceAppearance. Shared/GoldenShovelAsset.luau supplies the builder, config, and inventory icon. Icon generated from the supplied Blender source using render_icon.py, saved at Assets/Icons/icon_golden_shovel.png.

Prior Studio sources/templates are backed up under ServerStorage.BeforeGoldenShovelImport. Validated: mesh/diffuse preload, preview/Tool geometry, icon, 5.4-stud height, equip/stow cycles, swing recovery and respawn. Gameplay stats unchanged. Not published to live.
