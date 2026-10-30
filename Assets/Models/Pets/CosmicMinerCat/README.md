# DigPals Cosmic Miner Cat

Stylized, Roblox-ready companion pet created in Blender 5.2.3 LTS. The design uses a midnight/indigo body, copper miner harness and goggles, cyan crystal lenses, illuminated whiskers, and a segmented nebula tail.

## Deliverables

- `DigPals_CosmicMinerCat.blend` — editable master rig, materials, preview setup, and all three actions.
- `DigPals_CosmicMinerCat_Rig.fbx` — clean rig export without animation.
- `Animations/Cat_Idle.fbx` — 49 frames at 24 FPS, looped.
- `Animations/Cat_Walk.fbx` — 25 frames at 24 FPS, looped.
- `Animations/Cat_Digging.fbx` — 37 frames at 24 FPS, non-looping.
- `Preview_Hero.png` and `Preview_Digging.png` — visual checks from the final Blender file.

## Roblox import profile

- One skinned mesh: `DPM_CosmicMinerCat_Mesh`
- One armature: `DPM_Cat_Rig`
- 10 deform bones, no generated leaf bones
- 7,206 vertices / 7,624 polygons
- Approximate size at Roblox's 1 m = 3.571 studs conversion: **1.99 W x 4.40 L x 3.20 H studs**
- Blender local +Z is up; the cat faces local -Y. FBX export is `Forward -Z / Up Y`.
- Scale is baked; do not add a corrective rotation or non-uniform scale after import.

Import `DigPals_CosmicMinerCat_Rig.fbx` with Roblox Studio's 3D Importer. Keep the generated armature hierarchy, then import each animation FBX through Animation Editor for the imported rig. The files contain baked transforms at 24 FPS and do not require Blender constraints or drivers.

The Blender materials are procedural Principled materials with preserved primitive UVs. Roblox will import the material slots and colors; for the brightest in-game crystal effect, map `Crystal_Cyan` and `Nebula_Accent` to Neon or an equivalent SurfaceAppearance after import.

## Validation

All four FBX files were re-imported into temporary Blender scenes after export. Every file returned exactly one mesh, one armature, 10 bones, 7,206 vertices, and 7,624 polygons. Animation round-trip ranges were detected for idle, walk, and digging. No live Roblox publish or upload was performed.
