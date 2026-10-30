"""Independent FBX/GLB geometry round trip, evaluated against saved Blender source."""
import bpy,json,math,struct
from pathlib import Path
from mathutils import Vector,kdtree
OUT=Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(OUT/'RustyShovel_Oxide07.blend'))
source=next(o for o in bpy.context.scene.objects if o.type=='MESH')
positions=[source.matrix_world@v.co for v in source.data.vertices]
tree=kdtree.KDTree(len(positions))
for i,p in enumerate(positions):tree.insert(p,i)
tree.balance()
expected_tris=len(source.data.polygons)
assert expected_tris==5264
assert len(source.data.uv_layers)==1
assert all(p.area>1e-10 for p in source.data.polygons)
assert abs(source.dimensions.z-5.4)<1e-5
report={'source_triangles':expected_tris,'uv_layers':1,'texture_size':[2048,2048],'round_trips':{},'studio_gameplay_tested':False}
for ext in ('fbx','glb'):
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    if ext=='fbx':bpy.ops.import_scene.fbx(filepath=str(OUT/('RustyShovel_Oxide07.'+ext)))
    else:bpy.ops.import_scene.gltf(filepath=str(OUT/('RustyShovel_Oxide07.'+ext)))
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    assert len(meshes)==1
    obj=meshes[0]
    actual=[obj.matrix_world@v.co for v in obj.data.vertices]
    max_error=max(tree.find(p)[2] for p in actual)
    obj.data.calc_loop_triangles()
    assert len(obj.data.loop_triangles)==expected_tris
    assert len(obj.data.uv_layers)==1
    assert max_error<1e-4,(ext,max_error)
    report['round_trips'][ext]={'mesh_count':1,'triangles':len(obj.data.loop_triangles),'max_vertex_error':max_error,'uv_preserved':True,'material_count':len(obj.data.materials),'world_dimensions':list(obj.dimensions),'rotation_degrees':[math.degrees(x) for x in obj.rotation_euler]}
# Read raw GLB coordinates to verify the actual interchange file has the requested Y-up.
data=(OUT/'RustyShovel_Oxide07.glb').read_bytes()
n,kind=struct.unpack_from('<II',data,12)
gltf=json.loads(data[20:20+n])
prim=gltf['meshes'][0]['primitives'][0]
acc=gltf['accessors'][prim['attributes']['POSITION']]
assert abs(acc['max'][1]-acc['min'][1]-5.4)<1e-5
report['glb_raw_axis_bounds']={'min':acc['min'],'max':acc['max']}
assert len(gltf['materials'])==1
pbr=gltf['materials'][0]['pbrMetallicRoughness']
assert 'baseColorTexture' in pbr and 'metallicRoughnessTexture' in pbr
assert 'normalTexture' in gltf['materials'][0]
report['glb_embedded_pbr']=True
report['passed']=True
(OUT/'validation.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
