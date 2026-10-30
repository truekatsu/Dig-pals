import bpy, json, os

root=os.path.dirname(os.path.abspath(__file__))
files=[
    ('DigPals_CometMinerDog_Rig.fbx',None),
    ('Animations/Dog_Idle.fbx',49),
    ('Animations/Dog_Walk.fbx',25),
    ('Animations/Dog_Digging.fbx',37),
]
results={}
for relative,frames in files:
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    before=set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=os.path.join(root,relative))
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    rigs=[o for o in bpy.context.scene.objects if o.type=='ARMATURE']
    actions=[a for a in bpy.data.actions if a not in before]
    data={
      'meshes':len(meshes),'armatures':len(rigs),
      'bones':sum(len(o.data.bones) for o in rigs),
      'vertices':sum(len(o.data.vertices) for o in meshes),
      'polygons':sum(len(o.data.polygons) for o in meshes),
      'materials':sum(len(o.data.materials) for o in meshes),
      'animation_ranges':[[float(x) for x in a.frame_range] for a in actions],
    }
    data['passed']=data['meshes']==1 and data['armatures']==1 and data['bones']==11 and data['vertices']>0 and data['polygons']>0 and (frames is None or any(round(r[1]-r[0])==frames-1 for r in data['animation_ranges']))
    results[relative]=data
    for a in actions: bpy.data.actions.remove(a)
report={'asset':'DigPals Comet Miner Dog','blender_version':bpy.app.version_string,'roundtrip':results,'all_passed':all(x['passed'] for x in results.values()),'published_to_roblox':False}
with open(os.path.join(root,'validation.json'),'w',encoding='utf-8') as f: json.dump(report,f,indent=2)
print('DOG_VALIDATION',json.dumps(report))
if not report['all_passed']: raise RuntimeError('FBX roundtrip validation failed')
