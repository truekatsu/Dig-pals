# Shovelkeeper NPC

The shopkeeper is built from native Roblox parts by
`ReplicatedStorage/Shared/ShovelkeeperModelBuilder.luau`.

- Appearance: tilted top hat, purple hatband, sunglasses, moustache, dark suit,
  gold lapels and cuffs, and a faceted blue crystal held over the counter.
- Placement: `Workspace.Plain.Merchant.TheShovelkeeper.ShovelkeeperNPC`.
  The builder derives its position from the shop floor and counter, facing the entrance.
- All figure geometry is anchored and has collision, touch, and query disabled.
  The crystal is decorative; the NPC creates no gameplay Tools or embedded scripts.
- `ShopService.Start` ensures one NPC exists and preserves the existing desk bell interaction.
- To rebuild the figure after an appearance edit, bump the builder's `VERSION`
  or clear the existing NPC model's `VisualVersion` attribute, then call `EnsureForShop`.

The account's equipped shovel and the shared shovel carry pipeline are independent of this NPC.
