import bpy, json
from pathlib import Path
from mathutils import Vector
bpy.ops.wm.open_mainfile(filepath=r'D:/Models/Merchant/Merchant.blend',load_ui=False)
out=[]
for o in bpy.data.objects:
    if o.type!='MESH': continue
    pts=[o.matrix_world @ Vector(c) for c in o.bound_box]
    out.append({'name':o.name,'parent':o.parent.name if o.parent else None,'vertices':len(o.data.vertices),'materials':[m.name if m else None for m in o.data.materials], 'min':[min(p[i] for p in pts) for i in range(3)],'max':[max(p[i] for p in pts) for i in range(3)]})
materials={}
for m in bpy.data.materials:
    materials[m.name]=[{'path':n.image.filepath,'image':n.image.name} for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image] if m.node_tree else []
data={'objects':out,'materials':materials,'units':bpy.context.scene.unit_settings.system,'scale':bpy.context.scene.unit_settings.scale_length}
Path(r'D:/DigPals/Assets/Models/Merchant/source_inventory.json').write_text(json.dumps(data,indent=2))
print(json.dumps({'meshCount':len(out),'materialCount':len(materials),'parents':sorted(set(o['parent']or''for o in out)),'units':data['units'],'scale':data['scale']}))
