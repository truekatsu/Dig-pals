# Native Iron Shovel

`IronShovelModel.luau`, version `ForgedIronV2`, uses the native Rusty silhouette with the supplied aged-iron shovel reference: a cylindrical timber shaft, wooden D-grip crossbar, iron grip frame, wide spade with a short flat tip, extended tapered socket, and narrow cutting edges. There are 20 native parts, including the invisible unrotated Handle at the shared hand hold.

`IronShovelAsset.luau` records icon `rbxassetid://75407507066499` and the `DigPalsIronShovelSteelV1` PBR material definition (color, normal, roughness, metalness; 2-stud tiling). The user confirmed worn iron rather than stone. The material is recreated automatically when missing. Alternate generated samples remain in Studio's AssistantMaterials library.

The shared `ShovelModelBuilder` native registry builds previews and gameplay Tools, invalidates older Iron visuals, and applies the same nominal 5.4-stud `DiagonalCarryV4` carry convention. There are no per-shovel grip constants or gameplay-stat changes. Hand targets, back cosmetics, two-hand animation, and strike recovery remain shared.

Old imported sources, mesh, Tool, and preview are backed up under `ServerStorage.BeforeNativeIronShovel`. Earlier FBX/PBR files and `ServerStorage.BeforeIronShovelImport` remain historical assets and are not the active Iron visual.

`native_geometry.json` is an export of the native part specs. `render_native_icon.py` renders the transparent icon with cylindrical geometry, wood grain, and an approximate worn-metal shader. The actual in-game surface uses the saved PBR maps.

Validated in Studio: identity Handle, nominal 5.4-stud height (within 0.01 studs), PBR material recreation, Rusty/Stone/Iron switching, safe cosmetic back model, arm restoration, shared strike recovery, respawn without duplicate visuals, and updated Tool/preview asset versions. The inventory/hotbar icon definition is updated to the new render. The old imported mesh is absent from active world and asset templates. The place has not been published live.
