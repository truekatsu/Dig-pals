# Rusty Shovel — Oxide No. 07 integration

The active Rusty geometry is now the Blender mesh `rbxassetid://84345880591592`, visual version `Oxide07BlenderV2`. `RustyShovelAsset.luau` records the four uploaded PBR maps and normalized 5.4-stud dimensions. `ShovelModelBuilder` routes Rusty through its imported visual path, cloning `ReplicatedStorage.ShovelAssets.RustyShovelMesh` with UVs and SurfaceAppearance intact. The importer originally produced a 540-stud mesh; the active template is uniformly scaled by 0.01 and has identity CFrame/PivotOffset. No Rusty-specific carry/grip offset was added. Shared `DiagonalCarryV4`, IdleGrip, SwingGrip and hand targets remain authoritative.

Studio backup: `ServerStorage.BeforeOxide07RustySwap`. The four Shovelkeeper rack models, gameplay Tool, and preview template use the new visual version. The old native module remains historical source only. The existing 2D icon asset is retained.

Studio gameplay QA passed: equip, swing and idle recovery, unequip with a safe single back cosmetic, reequip without duplicates, Stone/Rusty switching, and respawn. R15 client IK targets remain Y=1.6 / -0.55 with full weight and active Animator tracks. No place publishing was performed.

Material fallback: asset-ID SurfaceAppearance renders gray in this Studio session, although all four images exist and UVs are valid. Texture pack `92971506321951` fails to load. Albedo on TextureID renders correctly; a temporary SurfaceAppearance generated with EditableImages also rendered correctly. After explicit user approval, the normalized model was uploaded through Studio's Save to Roblox dialog as model asset `112557336512404` (Off Sale). Re-inserting it retained the same failing texture pack. The place/game was not published. `UsePBR = false` currently makes the shared imported visual builder put the cloned SurfaceAppearance inside a `PBRSource` folder and display the verified color atlas through TextureID. The canonical MeshPart retains its original PBR material. No UVs or map assets were replaced. When texture-pack delivery is healthy, set UsePBR to true and bump VisualVersion to rebuild the templates. Temporary inspection objects were removed.

## Previous native version (historical)

The active model is `ReplicatedStorage/Shared/RustyShovelModel.luau`, version `WeatheredRustyV3`: 18 native parts, a worn timber shaft and D grip, a plain pointed iron blade, built-in CorrodedMetal pitting, narrow worn cutting edges, and a small socket pin. The old square rust patches are removed. No imported mesh, image texture, glow, or decorative accessories are required.

`ShovelModelBuilder` builds the gameplay Tool and all 3D previews from these same specs. The common `ShovelCarry` pipeline scales gameplay Tools and back cosmetics to 5.4 studs, with an identity Handle at the hand hold, +Y toward the top grip, and -Y toward the blade. The Rusty visual version invalidates older templates without changing other shovels.

`RustyShovelAsset.luau` supplies icon `rbxassetid://86186130823192`. The transparent icon at `Assets/Icons/icon_rusty_shovel.png` is rendered by `render_native_icon.py` from `native_geometry.json`, an export of the Roblox specs. Its procedural shader approximates Roblox's built-in corrosion. Regenerate the JSON when changing geometry, then run the renderer with Blender in background mode. The earlier FBX, textures, and Blender renderer are retained only as historical source files and are no longer used by the game.

Studio backups of the previous sources, templates, and imported mesh are under `ServerStorage.BeforeSimpleRustyV2`. The earlier `RustyShovelBeforeModelSwap` backup is also preserved. The pose and material revision is backed up under `ServerStorage.BeforeRustyGripRevision`. These backups are not active visual sources.

Validated in Studio: 5.4-stud Tool height, equip/unequip, switching Stone to Rusty, safe cosmetic back model, shared dig swing recovery, respawn, and a single held or back visual. Changes are local to Studio; the place has not been published.
