# DigPals Comet Miner Dog

A chibi mining companion designed to pair with Cosmic Miner Cat. It has a broad chest, floppy ears, a cream muzzle and paws, copper goggles, a crystal backpack, and a glowing comet tail.

## Files

- `DigPals_CometMinerDog.blend`: editable Blender 5.2.3 LTS source with rig, materials, animation actions, and preview lighting.
- `DigPals_CometMinerDog_Rig.fbx`: skinned model without animation.
- `Animations/Dog_Idle.fbx`: 49 frames at 24 FPS; loop.
- `Animations/Dog_Walk.fbx`: 25 frames at 24 FPS; loop.
- `Animations/Dog_Digging.fbx`: 37 frames at 24 FPS; one shot.
- `Preview_Hero.png`, `Preview_Digging.png`: rendered visual checks.
- `build_dog.py`, `validate_dog.py`: reproducible build and FBX round-trip validation.

## Roblox import

Import the rig FBX with Studio's 3D Importer, preserving the generated armature hierarchy. Import each animation FBX through Animation Editor for that rig. The model has one skinned mesh, 11 bones, no leaf bones, 10,944 vertices, and 11,710 polygons. At approximately 1 meter = 3.571 studs, its bounding size is **2.54 W × 4.90 L × 2.87 H studs**. Local +Z is up in Blender and the dog faces -Y; FBX uses Forward -Z / Up Y. Transforms and animation are baked at export.

The 11 material slots and primitive UVs survive the FBX round-trip. Roblox may render emission differently from Blender; set `Comet_Crystal_Cyan` and `Comet_Crystal_Violet` to Neon or a suitable SurfaceAppearance for the intended luminous look. The preview pedestal, camera, and lights are excluded from every FBX.

`validation.json` records successful Blender re-import of all four FBX files, including mesh, materials, armature, bones, and action ranges. This does not replace a visual check in Roblox Studio after import. Nothing was published to a live experience.
