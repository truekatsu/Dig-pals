"""Correct exterior support heights in a copy; export only five affected materials."""
import bpy, json, shutil
import runpy
from pathlib import Path
from mathutils import Vector
root=Path(r'D:/DigPals/Assets/Models/Merchant')
source=Path(r'D:/Models/Merchant')
bpy.ops.wm.open_mainfile(filepath=str(source/'Merchant.blend'),load_ui=False)
bpy.context.scene.cursor.location=(0,0,0)

runpy.run_path(str(root/'ground_merchant_props.py'))['ground_exterior_props']()

report=[]
for prefix,top in [('ExtSack_1',2),('ExtSack_2',2),('ExtCrystal_Amethyst',2),('ExtCrystal_GoldOre',1)]:
    meshes=[o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith(prefix+'_')]
    pts=[o.matrix_world@Vector(v)for o in meshes for v in o.bound_box]
    low=min(v.z for v in pts)
    report.append({'group':prefix,'bottom':low,'support_top':top,'gap':low-top,
        'min':[min(p[i]for p in pts)for i in range(3)],'max':[max(p[i]for p in pts)for i in range(3)]})
    assert abs(low-top)<.001,(prefix,low,top)

names={'Mat_Stone','Mat_Timber','Mat_AntiqueGold','Mat_AmethystGlow','Mat_BrightGold'}
groups={}
for o in bpy.data.objects:
    if o.type=='MESH' and o.name!='Ground_Cobblestone' and len(o.data.materials)==1 and o.data.materials[0].name in names:
        groups.setdefault(o.data.materials[0].name,[]).append(o)
export=[]
for name,objects in groups.items():
    for n in bpy.data.materials[name].node_tree.nodes:
        if n.type=='TEX_IMAGE' and n.image:
            p=source/(Path(n.image.filepath.replace('\\','/')).name or n.image.name)
            n.image.filepath=str(root/'Textures'/p.name)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:
        world=o.matrix_world.copy();o.parent=None;o.matrix_world=world;o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.object.join()
    obj=bpy.context.object;obj.name='Merchant_'+name.removeprefix('Mat_')
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    export.append(obj)
bpy.ops.object.select_all(action='DESELECT')
for o in export:o.select_set(True)
bpy.ops.export_scene.fbx(filepath=str(root/'Merchant_GroundedProps.fbx'),use_selection=True,object_types={'MESH'},global_scale=1,apply_unit_scale=True,bake_space_transform=True,mesh_smooth_type='FACE',path_mode='COPY',embed_textures=True)
(root/'grounded_props_report.json').write_text(json.dumps(report,indent=2))
print(json.dumps({'meshes':len(export),'support_checks':report}))
