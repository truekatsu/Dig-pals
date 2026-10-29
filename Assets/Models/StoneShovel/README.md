# Stone Shovel replacement

Source: user-supplied Stone_Shovel.fbx and PBR atlas. Source hand hold: Z=0.76m; bounds center: Z=0.5835m. Imported pivot rotation reset. Shared carry defaults normalize gameplay height to 5.4 studs.

Roblox uploads:
- Mesh: 125264999160707
- Diffuse: 115549124119397
- Roughness: 91745339205419
- Metallic: 109451120725857
- Icon: 109747416026820

Studio template: ReplicatedStorage.ShovelAssets.StoneShovelMesh, with SurfaceAppearance. Shared/StoneShovelAsset.luau defines geometry and icon used by the builder, shop, Tool and inventory. Rendered icon: Assets/Icons/icon_stone_shovel.png, generated with render_icon.py from the supplied Blender model.

Prior Studio sources and templates: ServerStorage.BeforeStoneShovelImport.
Validated: mesh/diffuse preload, preview geometry, Tool icon, equip/stow cycles, swing recovery, respawn and shared carry defaults. No gameplay stat changes. Not published to live.
