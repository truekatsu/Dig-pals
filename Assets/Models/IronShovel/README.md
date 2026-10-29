# Iron Shovel replacement

User-supplied Iron_Shovel.fbx and PBR atlas. Shared carry height: 5.4 studs. Source hand hold: Z=0.76m; mesh center (0.0095, 0.599, -0.011) in Roblox axes. Imported pivot rotation reset. Optional 3D GripOffset compensates for asymmetric bounds.

Roblox uploads:
- Mesh: 114977741903180
- Diffuse: 102852578306662
- Roughness: 83164652337082
- Metallic: 130463664697287
- Icon: 121468431182146

Studio template: ReplicatedStorage.ShovelAssets.IronShovelMesh with SurfaceAppearance. Shared/IronShovelAsset.luau supplies the builder and inventory icon. Icon generated from the supplied Blender source using render_icon.py, saved at Assets/Icons/icon_iron_shovel.png.

Prior Studio sources/templates are backed up under ServerStorage.BeforeIronShovelImport. Validated: mesh/diffuse preload, preview/Tool geometry, icon, 5.4-stud height, Rusty/Stone/Iron switching, two equip/stow cycles, swing recovery and respawn. Gameplay stats unchanged. Not published to live.
