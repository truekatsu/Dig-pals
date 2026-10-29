# Rusty Shovel replacement

Source: user supplied Rusty_Shovel.fbx and PBR atlas. Gameplay scale: 3.3 (height 3.945 studs). Hand hold is 0.76 source meters. Imported pivot rotation is reset before use.

Mesh: 87169671105639
Diffuse upload: 101524437679882
Roughness upload: 99828948478004
Metallic upload: 110601777729907
Icon upload: 73230995952848

Studio: ReplicatedStorage.ShovelAssets.RustyShovelMesh retains the imported MeshPart and SurfaceAppearance. ShovelModelBuilder creates both the gameplay Tool and shop preview from it. The FileMesh fallback uses the same geometry and diffuse when the imported template is absent. RustyShovelAsset is the shared icon and visual configuration.

The icon is rendered from the supplied Blender source with render_icon.py. Original source assets are unchanged. Prior Studio scripts and templates are backed up under ServerStorage.RustyShovelBeforeModelSwap.

Validated in Studio: all seven shovel builders, Rusty Tool weld and non-colliding/massless parts, preview anchoring, gameplay mesh and diffuse preload, and new hotbar icon.
