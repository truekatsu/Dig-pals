import bpy

print("ARM_OBJECTS:", [o.name for o in bpy.data.objects if o.type == 'ARMATURE'])
print("MESH_OBJECTS:", [o.name for o in bpy.data.objects if o.type == 'MESH'])
print("ACTIONS:", [a.name for a in bpy.data.actions])

arm = bpy.data.objects.get('DPM_Chick_Rig')
if not arm:
    for o in bpy.data.objects:
        if o.type == 'ARMATURE':
            arm = o
            break

if arm:
    print("BONES:", [b.name for b in arm.data.bones])
