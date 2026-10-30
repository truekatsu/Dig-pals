# Oxide No. 07 — Rusty Shovel

Original Blender model for DigPals: a cupped, pointed iron blade, worn cutting bevel, rolled foot steps, pinned socket, aged timber shaft, old leather repair binding, and a D grip with remnants of faded green paint. Rust is a mixture of dark oxide, orange corrosion and exposed iron. The small asymmetric nick is deliberate.

No reference image was supplied. A numerical 95% similarity claim cannot be assessed. The supplied mesh and texture maps preserve the authored geometry and surface detail during import; lighting and tone mapping in Studio will affect its appearance.

## Files

- `RustyShovel_Oxide07.fbx`: primary Roblox import, one mesh and one material.
- `RustyShovel_Oxide07.glb`: alternative import with embedded PBR maps.
- `RustyShovel_Oxide07.blend`: editable source with packed textures and preview lighting.
- `RustyShovel_Color.png`: sRGB albedo, with no baked lighting.
- `RustyShovel_Normal.png`: tangent-space normal map.
- `RustyShovel_Roughness.png`: linear roughness.
- `RustyShovel_Metalness.png`: linear metalness; oxidized regions are mostly nonmetallic.
- `Preview_Hero.png`, `Preview_Front.png`, `Preview_Back.png`: renders of the actual exported asset.
- `asset_manifest.json`: measured geometry and export information.
- `build_rusty_shovel.py`: deterministic Blender generation, baking and export script.

## Roblox Studio import

1. Use **File > Import**, then choose the FBX. Inspect the preview orientation before importing. GLB is also supplied if automatic material transfer works better in your Studio version.
2. Use a **SurfaceAppearance** under the imported MeshPart. Assign the four supplied maps to **ColorMap**, **NormalMap**, **RoughnessMap**, and **MetalnessMap**. Keep MeshPart Color white. Use the complete atlas without altering its UV layout. Upload the maps under the same creator as the game.
3. The authored height is **5.4**, blade at local **-Y**, top grip at **+Y** in the Y-up export. Set the final imported height to **5.4 studs**, scaling the entire model uniformly if Studio applies a different file-unit conversion. Reset the imported pivot rotation; check blade-down orientation before creating a Tool.
4. This is a visual asset. In DigPals, register its imported MeshPart as a visual template and extend the imported-asset path in `ReplicatedStorage/Shared/ShovelModelBuilder.luau` if replacing the native Rusty model. The current RustyShovel entry is native geometry; merely importing an FBX does not replace it. Retain SurfaceAppearance when cloning the template.
5. Build gameplay Tools only through `ShovelModelBuilder.BuildGameplayTool` / `CloneGameplayTool`. Let shared `ShovelCarry` determine the height, idle/swing grips, shoulder alignment, two-hand targets, and held/back poses. Put the identity-rotation Handle at the intended hand contact. The upper right-hand contact is Y=1.6, lower left-hand contact Y=-0.55; no model-specific carry offsets are supplied.
6. If activating this visual, bump its template VisualVersion to `Oxide07BlenderV1` or clear stale VisualVersion/CarryVersion attributes so EnsureAssets rebuilds it. Back visuals must be cosmetic models with no Tool, scripts, collision, touch, query, or mass.
7. Verify equip/unequip, switching, respawn, dig return, R15/R6 arm restoration, and a single held/back visual in Studio before release.

This package does not change the active game scripts or existing Rusty asset. It has not been uploaded or published. Blender export round-trip validation is provided separately; Studio gameplay verification remains pending activation.

References: [Roblox Importer](https://create.roblox.com/docs/studio/importer), [PBR textures and SurfaceAppearance](https://create.roblox.com/docs/art/modeling/surface-appearance).

## Rebuild

Run Blender in background mode with `--factory-startup --python build_rusty_shovel.py`. It rebakes all maps; add `-- --reuse-textures` only when re-exporting unchanged geometry/materials. The source uses Blender Z-up while modeling; FBX and GLB exports are configured Y-up. All mesh object transforms are applied and the source origin is at the shared visual center. Preview lights and camera are excluded from exports.

`validation.json` confirms both exports return one mesh, one material, 5,264 triangles and a UV layer. Maximum vertex deviation after re-import: FBX less than 0.000001 model units, GLB zero. The GLB's raw position bounds confirm +Y up and a 5.4-unit height. Embedded GLB color, normal and metal/roughness textures are present. This validates file geometry, not a percentage match to an unspecified visual reference or gameplay inside Studio.
