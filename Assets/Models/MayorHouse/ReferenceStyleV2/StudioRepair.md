# Studio wall and entrance repair

The placed `Workspace.Plain.MayorHouse` now uses `SolidArchitecture` for walls, floor, frames and trim, rebuilt from the Blender Architecture collection. Door_Leaf and Door_Plank objects are omitted. Original imported Architecture meshes are preserved in `ServerStorage.MayorHouse_OriginalArchitecture` for recovery.

Rear gable siding closes the original missing rear triangle. Front lower and middle beams are split around the entry; side wall infills close the gaps between the original doorway and its jambs. The entrance remains open. Preserve these changes when reimporting the source FBX, which still includes the original door.

The front entry infills extend up to the eaves/header so the two openings above the jambs are closed. The imported `Exterior_Decor_Material_0` gold mesh is replaced with individual gold decorations excluding `Door_Handle`; the original gold mesh is preserved alongside the original Architecture meshes in ServerStorage.

Blender coordinate mapping at this placement: scale 2.48141575 studs/unit; world origin (0, 0, -196.53482); world XYZ = origin + (-BlenderX, BlenderZ, -BlenderY) * scale.
