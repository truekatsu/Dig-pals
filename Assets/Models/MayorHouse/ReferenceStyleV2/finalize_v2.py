import bpy, os
root=os.path.dirname(os.path.abspath(__file__))
bpy.ops.wm.open_mainfile(filepath=os.path.join(root,'DigPals_MayorHouse.blend'))
scene=bpy.context.scene
roof=bpy.data.collections['Roof']
for obj in list(roof.objects):
    if obj.name.startswith('Roof_Tile_Row'): bpy.data.objects.remove(obj,do_unlink=True)
    if obj.name.startswith(('Gable_Board','Gable_Siding_Seam')):
        allowed=max(.2,2*(10.65-obj.location.z-.30)*9.6/3.7)
        if obj.dimensions.x>allowed: obj.scale.x *= allowed/obj.dimensions.x
# Export joined copies grouped by collection and material, leaving editable source objects intact.
temp=bpy.data.collections.new('TEMP_EXPORT'); scene.collection.children.link(temp)
export_objects=[]
for group in ('Architecture','Roof','Furnishings','Exterior_Decor'):
    buckets={}
    for src in bpy.data.collections[group].objects:
        if src.type!='MESH': continue
        key=tuple(m.name for m in src.data.materials)
        dup=src.copy(); dup.data=src.data.copy(); temp.objects.link(dup)
        chunks=buckets.setdefault(key,[[]])
        triangles=sum(max(0,len(p.vertices)-2) for p in dup.data.polygons)
        current=sum(sum(max(0,len(p.vertices)-2) for p in ob.data.polygons) for ob in chunks[-1])
        if chunks[-1] and current+triangles>15000: chunks.append([])
        chunks[-1].append(dup)
    for index,objects in enumerate(chunk for chunks in buckets.values() for chunk in chunks):
        bpy.ops.object.select_all(action='DESELECT')
        for o in objects: o.select_set(True)
        bpy.context.view_layer.objects.active=objects[0]
        if len(objects)>1: bpy.ops.object.join()
        o=bpy.context.view_layer.objects.active; o.name=group+'_Material_'+str(index); export_objects.append(o)
bpy.ops.object.select_all(action='DESELECT')
for o in export_objects: o.select_set(True)
bpy.context.view_layer.objects.active=export_objects[0]
bpy.ops.export_scene.fbx(filepath=os.path.join(root,'MayorHouse_Architecture.fbx'),use_selection=True,object_types={'MESH'},axis_forward='-Z',axis_up='Y',apply_unit_scale=True,add_leaf_bones=False,bake_anim=False,mesh_smooth_type='FACE')
for o in list(temp.objects): bpy.data.objects.remove(o,do_unlink=True)
bpy.data.collections.remove(temp)
scene.camera=bpy.data.objects['Camera_Exterior']
scene.render.filepath=os.path.join(root,'Preview_Exterior.png'); bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(root,'DigPals_MayorHouse.blend'))
print('FINAL_V2',len(export_objects))
