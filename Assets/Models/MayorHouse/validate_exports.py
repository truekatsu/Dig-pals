import bpy, os, json
root=os.path.dirname(os.path.abspath(__file__))
report={}
for name in ('MayorHouse_Architecture.fbx','Mayor_NPC.fbx'):
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.fbx(filepath=os.path.join(root,name))
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    points=[o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
    bounds=[[round(min(p[i] for p in points),3),round(max(p[i] for p in points),3)] for i in range(3)] if points else []
    triangles=[sum(max(0,len(p.vertices)-2) for p in o.data.polygons) for o in meshes]
    report[name]={'meshes':len(meshes),'vertices':sum(len(o.data.vertices) for o in meshes),'polygons':sum(len(o.data.polygons) for o in meshes),'max_triangles_per_mesh':max(triangles,default=0),'world_bounds_xyz':bounds,'passed':bool(meshes and points)}
with open(os.path.join(root,'validation.json'),'w',encoding='utf8') as f: json.dump(report,f,indent=2)
print('ROUNDTRIP',json.dumps(report))
if not all(x['passed'] for x in report.values()): raise RuntimeError('FBX validation failed')
