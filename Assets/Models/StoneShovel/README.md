# Native Stone Shovel

`ReplicatedStorage/Shared/StoneShovelModel.luau` builds the `HandhewnStoneV2` visual from the same D-grip, wooden shaft, and pointed-spade silhouette as the native Rusty Shovel. The blade is thicker, uses a rough gray stone PBR material, and has three small haft bindings. Rust strips and socket rivets are excluded. Stone has 15 native parts and no imported mesh dependency.

`StoneShovelAsset.luau` contains the icon (`rbxassetid://100739219715761`) and the reproducible `DigPalsStoneShovelRockV1` material maps: color, normal, roughness, and metalness. `StoneShovelModel.GetPartSpecs` ensures the MaterialVariant under MaterialService. It tiles every 1.6 studs. The selected material comes from the first generated DigPalsStoneShovel variant; the alternative samples remain in Studio's AssistantMaterials library.

`ShovelModelBuilder` registers both Rusty and Stone in the native-model table, builds gameplay Tools and previews from the same specs, and invalidates old visual versions. Its shared carry normalization supplies the 5.4-stud default height and the approved DiagonalCarryV4 pose for held, back, and swing recovery. No per-shovel grip offsets or gameplay-stat changes are introduced.

The previous imported mesh, sources, Tool, and preview are preserved under `ServerStorage.BeforeNativeStoneShovel`. Older FBX/PBR files in this directory and `ServerStorage.BeforeStoneShovelImport` are historical source assets, no longer the active Stone visual.

`native_geometry.json` exports the Roblox part specs. `render_native_icon.py` renders the transparent `Assets/Icons/icon_stone_shovel.png` with a procedural rough-rock shader approximating the in-game surface. Run it with Blender in background mode after geometry changes.

Validated in Studio: material recreation from the saved PBR definition, 5.4-stud Tool height, held and back visuals, Rusty/Stone switching, shared strike recovery, arm restoration on unequip, respawn without duplicate visuals, and the matching hotbar icon. No gameplay stats were changed. The place has not been published live.
