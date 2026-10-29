# Shovel model rules

For every new or replacement shovel, use the shared carry pipeline:

- Keep `ReplicatedStorage/Shared/Config/ShovelCarry.luau` as the common default for size, held pose, back pose, hand targets, and animation blend.
- Build gameplay Tools through `ShovelModelBuilder.BuildGameplayTool` / `CloneGameplayTool`. All Tools receive a 5.4-stud default height and the same carry convention automatically. Do not add per-shovel grip constants.
- Model convention: local +Y points towards the top grip; local -Y points towards the blade. Reset imported pivot rotation. Put the Tool Handle at the intended hand hold, with no rotation. Preserve mesh UVs and PBR materials.
- `ShovelCarryService` attaches the selected active Tool diagonally in front, and displays the selected shovel diagonally across the back when unequipped. Back models are cosmetics only, without Tool instances, scripts, collision, touch, query, or mass.
- `ShovelCarry.client.luau` applies two-hand R15 IK / R6 shoulder poses to all visible players. Preserve walk/jump animation and restore arms when put away.
- Keep dig swing and return poses based on the shared IdleGrip and SwingGrip. Never restore an older hardcoded Tool.Grip after a strike.
- When changing model geometry, clear stale `CarryVersion`/`VisualVersion` template attributes or bump their version so `EnsureAssets` rebuilds it.
- Verify equip/unequip, switching shovels, respawn, dig swing recovery, and no duplicate back/held models in Studio. Do not publish to live unless requested.
