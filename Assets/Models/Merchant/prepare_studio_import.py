"""Preserve Merchant geometry/UVs, merge by material, omit the render ground."""
import bpy, json, shutil
import runpy
from pathlib import Path
from mathutils import Vector
root=Path(r'D:/DigPals/Assets/Models/Merchant')
source=Path(r'D:/Models/Merchant')
bpy.ops.wm.open_mainfile(filepath=str(source/'Merchant.blend'),load_ui=False)
bpy.context.scene.cursor.location=(0,0,0)
runpy.run_path(str(root/'ground_merchant_props.py'))['ground_exterior_props']()
meshes=[o for o in bpy.data.objects if o.type=='MESH' and o.name!='Ground_Cobblestone']
groups={}
for o in meshes:
    assert len(o.data.materials)==1, o.name
    groups.setdefault(o.data.materials[0].name,[]).append(o)
metadata={'source':'Merchant.blend','excluded':['Ground_Cobblestone'],'anchors':{},'materials':{},'colliders':[]}
for o in meshes:
    if o.name in {'Counter_Top','Foundation_Base','NPC_Head','Counter_Bell'}:
        metadata['anchors'][o.name]={'position':list(o.matrix_world.translation),'size':list(o.dimensions)}
    if o.name.startswith(('Foundation_','Wall_','Pillar_')) or o.name in {'Counter_Front','Counter_Top'}:
        metadata['colliders'].append({'name':o.name,'matrix':[list(row) for row in o.matrix_world],'size':list(o.dimensions)})
for name,objects in groups.items():
    mat=bpy.data.materials[name]
    node=next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
    images=[]
    for n in mat.node_tree.nodes:
        if n.type=='TEX_IMAGE' and n.image:
            path=source/(Path(n.image.filepath.replace('\\','/')).name or n.image.name)
            (root/'Textures').mkdir(exist_ok=True)
            dest=root/'Textures'/path.name
            shutil.copy2(path,dest)
            n.image.filepath=str(dest)
            images.append(path.name)
    metadata['materials'][name]={'images':images,'color':list(node.inputs['Base Color'].default_value),'metallic':node.inputs['Metallic'].default_value,'emission':list(node.inputs['Emission Color'].default_value),'emission_strength':node.inputs['Emission Strength'].default_value}
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:
        world=o.matrix_world.copy();o.parent=None;o.matrix_world=world;o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.object.join()
    obj=bpy.context.object
    obj.name='Merchant_'+name.removeprefix('Mat_')
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    metadata['materials'][name]['object']=obj.name
export=[o for o in bpy.data.objects if o.type=='MESH' and o.name!='Ground_Cobblestone']
points=[o.matrix_world @ Vector(c) for o in export for c in o.bound_box]
metadata['bounds']={'min':[min(p[i]for p in points)for i in range(3)],'max':[max(p[i]for p in points)for i in range(3)]}
bpy.ops.object.select_all(action='DESELECT')
for o in export:o.select_set(True)
bpy.ops.export_scene.fbx(filepath=str(root/'Merchant_Studio.fbx'),use_selection=True,object_types={'MESH'},global_scale=1,apply_unit_scale=True,bake_space_transform=True,mesh_smooth_type='FACE',path_mode='COPY',embed_textures=True)
(root/'import_manifest.json').write_text(json.dumps(metadata,indent=2))
print(json.dumps({'meshes':len(export),'bounds':metadata['bounds'],'colliders':len(metadata['colliders']),'anchors':metadata['anchors']}))
