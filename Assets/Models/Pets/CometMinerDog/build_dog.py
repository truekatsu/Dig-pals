import bpy, math, os, json
from mathutils import Vector
from math import sin, cos, pi, radians

OUT = os.path.dirname(os.path.abspath(__file__))
ANIMS = os.path.join(OUT, 'Animations')
os.makedirs(ANIMS, exist_ok=True)
S = .62
P = lambda p: tuple(S*v for v in p)

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.render.engine = 'BLENDER_EEVEE'
scene.render.resolution_x = scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.fps = 24
scene.world.color = (.012,.015,.04)

def mat(name, rgba, metal=0, rough=.4, emission=0):
    m=bpy.data.materials.new(name); m.use_nodes=True
    bs=m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value=(*rgba,1)
    bs.inputs['Metallic'].default_value=metal
    bs.inputs['Roughness'].default_value=rough
    if emission:
        bs.inputs['Emission Color'].default_value=(*rgba,1)
        bs.inputs['Emission Strength'].default_value=emission
    return m

M={
 'coat':mat('Comet_DeepNavy',(.025,.055,.13),.06,.32),
 'blue':mat('Comet_RoyalBlue',(.055,.15,.32),.05,.32),
 'cream':mat('Muzzle_Cream',(.88,.68,.42),0,.44),
 'ear':mat('Ear_Velvet',(.12,.045,.16),0,.48),
 'nose':mat('Nose_Charcoal',(.012,.02,.035),0,.2),
 'copper':mat('Miner_Copper',(.78,.33,.07),.8,.22),
 'metal':mat('Harness_Gunmetal',(.035,.06,.10),.75,.24),
 'cyan':mat('Comet_Crystal_Cyan',(.04,.74,1),.15,.17,3),
 'violet':mat('Comet_Crystal_Violet',(.36,.09,.8),.2,.2,2.4),
 'white':mat('Eyes_Opal',(.8,.97,1),0,.18,1),
 'paw':mat('Paw_Socks',(.93,.8,.58),0,.48),
}

armd=bpy.data.armatures.new('DPM_Dog_Armature')
arm=bpy.data.objects.new('DPM_Dog_Rig',armd)
bpy.context.collection.objects.link(arm)
bpy.context.view_layer.objects.active=arm; arm.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
def bone(n,h,t,parent=None):
    b=armd.edit_bones.new(n); b.head=P(h); b.tail=P(t)
    if parent: b.parent=armd.edit_bones[parent]
bone('Root',(0,0,0),(0,0,.35))
bone('Body',(0,0,.28),(0,0,.72),'Root')
bone('Head',(0,-.39,.68),(0,-.39,1.03),'Body')
for side in ('L','R'):
    x=-.29 if side=='L' else .29
    bone('Ear_'+side,(x,-.43,1.04),(x*1.3,-.48,.73),'Head')
for pos,x,y in [('FL',-.28,-.31),('FR',.28,-.31),('BL',-.28,.36),('BR',.28,.36)]:
    bone('Leg_'+pos,(x,y,.49),(x,y,.09),'Body')
bone('Tail_01',(0,.51,.58),(0,.81,.76),'Body')
bone('Tail_02',(0,.81,.76),(.11,1.03,.94),'Tail_01')
bpy.ops.object.mode_set(mode='OBJECT')
for pb in arm.pose.bones: pb.rotation_mode='XYZ'

parts=[]
def finish(o,n,material,group):
    o.name=n; o.data.name=n+'_Mesh'; o.data.materials.append(material)
    for p in o.data.polygons: p.use_smooth=True
    vg=o.vertex_groups.new(name=group); vg.add(list(range(len(o.data.vertices))),1,'REPLACE')
    parts.append(o); return o
def uv(n,loc,scale,m,g,segments=24,rings=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments,ring_count=rings,location=P(loc))
    o=bpy.context.object; o.scale=P(scale)
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return finish(o,n,M[m],g)
def ico(n,loc,scale,m,g,sub=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub,location=P(loc))
    o=bpy.context.object; o.scale=P(scale)
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return finish(o,n,M[m],g)
def cyl(n,a,b,r,m,g,verts=12):
    a,b=Vector(P(a)),Vector(P(b)); d=b-a
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r*S,depth=d.length,location=(a+b)/2)
    o=bpy.context.object; o.rotation_mode='QUATERNION'
    o.rotation_quaternion=Vector((0,0,1)).rotation_difference(d.normalized())
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.rotation_mode='XYZ'; return finish(o,n,M[m],g)
def torus(n,loc,major,minor,m,g,rotation=(0,0,0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major*S,minor_radius=minor*S,major_segments=28,minor_segments=8,location=P(loc),rotation=rotation)
    return finish(bpy.context.object,n,M[m],g)

# A broad chest, short legs, floppy ears and upright comet tail make a dog silhouette.
uv('Body',(0,.06,.56),(.43,.57,.35),'coat','Body')
uv('Chest_Bib',(0,-.41,.55),(.29,.17,.26),'cream','Body')
uv('Head',(0,-.49,.9),(.39,.36,.33),'blue','Head')
uv('Muzzle_L',(-.13,-.81,.79),(.18,.19,.13),'cream','Head')
uv('Muzzle_R',(.13,-.81,.79),(.18,.19,.13),'cream','Head')
uv('Nose',(0,-.96,.84),(.095,.075,.065),'nose','Head')
uv('Lower_Jaw',(0,-.77,.68),(.19,.16,.075),'cream','Head')
uv('Forehead_Blaze',(0,-.795,1.07),(.085,.025,.20),'cream','Head')
for sign,side in [(-1,'L'),(1,'R')]:
    x=sign*.31; g='Ear_'+side
    uv('Floppy_Ear_'+side,(sign*.405,-.44,.90),(.17,.16,.27),'ear',g)
    uv('Ear_Inner_'+side,(sign*.43,-.584,.84),(.095,.028,.17),'violet',g)
    uv('Eye_'+side,(sign*.17,-.80,.98),(.075,.038,.095),'white','Head')
    uv('Pupil_'+side,(sign*.17,-.837,.98),(.030,.017,.061),'nose','Head',16,12)
    uv('Brow_'+side,(sign*.18,-.79,1.09),(.085,.027,.027),'coat','Head',16,12)
    uv('Freckle_'+side,(sign*.28,-.844,.82),(.025,.012,.025),'copper','Head',12,8)
    for j in range(2):
        cyl('Whisker_'+side+str(j),(sign*.22,-.87,.79-j*.045),(sign*.39,-.92,.83-j*.07),.008,'cyan','Head',8)

for label,x,y in [('FL',-.28,-.31),('FR',.28,-.31),('BL',-.28,.36),('BR',.28,.36)]:
    g='Leg_'+label
    uv('Leg_'+label,(x,y,.30),(.15,.18,.27),'blue',g)
    uv('Paw_'+label,(x,y-.095 if y<0 else y+.08,.10),(.19,.22,.115),'paw',g)
    for j in (-.065,0,.065):
        uv('Toe_'+label+str(j),(x+j,y-.27 if y<0 else y+.22,.07),(.045,.065,.055),'cream',g,12,8)

cyl('Tail_Base',(0,.51,.59),(0,.81,.77),.14,'blue','Tail_01',16)
cyl('Tail_Tip', (0,.81,.77),(.12,1.04,.96),.12,'violet','Tail_02',16)
ico('Comet_Tail_Gem',(.13,1.05,.98),(.14,.13,.17),'cyan','Tail_02')

# Miner equipment remains bound to body and head bones.
torus('Collar',(0,-.38,.70),.32,.035,'copper','Head')
ico('Collar_Gem',(0,-.50,.62),(.085,.055,.13),'cyan','Body')
torus('Goggle_Left',(-.17,-.812,1.00),.11,.025,'copper','Head',(radians(90),0,0))
torus('Goggle_Right',(.17,-.812,1.00),.11,.025,'copper','Head',(radians(90),0,0))
cyl('Goggle_Bridge',(-.07,-.83,1.00),(.07,-.83,1.00),.025,'metal','Head')
cyl('Harness_Left',(-.36,-.24,.71),(-.35,.36,.50),.036,'copper','Body')
cyl('Harness_Right',(.36,-.24,.71),(.35,.36,.50),.036,'copper','Body')
ico('Backpack',(0,.37,.78),(.28,.22,.20),'metal','Body')
ico('Backpack_Crystal',(0,.42,.98),(.13,.13,.22),'cyan','Body',2)
for sx in (-1,1):
    ico('Side_Crystal_'+str(sx),(sx*.22,.42,.92),(.075,.085,.13),'violet','Body',1)

bpy.ops.object.select_all(action='DESELECT')
for o in parts: o.select_set(True)
bpy.context.view_layer.objects.active=parts[0]; bpy.ops.object.join()
mesh=bpy.context.object; mesh.name='DPM_CometMinerDog_Mesh'; mesh.data.name='DPM_Dog_Geometry'
mesh.data.validate(clean_customdata=False)
mod=mesh.modifiers.new('Armature','ARMATURE'); mod.object=arm; mesh.parent=arm
mesh['AssetType']='DigPalsPet'; mesh['PetName']='Comet Miner Dog'
arm['RobloxReady']=True; arm['AnimationFPS']=24

def clear_pose():
    for pb in arm.pose.bones:
        pb.location=(0,0,0); pb.rotation_euler=(0,0,0); pb.scale=(1,1,1)
def action(name,length,samples,loop):
    a=bpy.data.actions.new(name); a.use_fake_user=True; a['Looped']=loop; a['FPS']=24
    arm.animation_data_create(); arm.animation_data.action=a
    for frame,pose in samples:
        clear_pose()
        for bn,(rot,loc) in pose.items():
            p=arm.pose.bones[bn]; p.rotation_euler=rot; p.location=P(loc)
        for p in arm.pose.bones:
            p.keyframe_insert('rotation_euler',frame=frame,group=p.name)
            p.keyframe_insert('location',frame=frame,group=p.name)
    return a
def spec(**kwargs): return kwargs
def r(x=0,y=0,z=0): return (radians(x),radians(y),radians(z))
def v(x=0,y=0,z=0): return (x,y,z)

idle=[]
for f,t in [(1,0),(13,pi/2),(25,pi),(37,3*pi/2),(49,2*pi)]:
    idle.append((f,spec(Root=(r(),v(z=.02*(1-cos(t)))),Body=(r(2*sin(t),0,1.5*sin(t)),v()),Head=(r(-3*sin(t),0,3*sin(t)),v()),Ear_L=(r(3*sin(t)),v()),Ear_R=(r(-3*sin(t)),v()),Tail_01=(r(0,0,16*sin(t)),v()),Tail_02=(r(0,0,24*sin(t+.7)),v()))))
a_idle=action('DOG_Idle_Loop',49,idle,True)
walk=[]
for f,t in [(1,0),(7,pi/2),(13,pi),(19,3*pi/2),(25,2*pi)]:
    s=sin(t)
    walk.append((f,spec(Root=(r(0,0,2*s),v(z=.037*(1-cos(t)))),Body=(r(3*cos(t),0,3*s),v()),Head=(r(-3*cos(t),0,-2*s),v()),Leg_FL=(r(34*s),v()),Leg_BR=(r(34*s),v()),Leg_FR=(r(-34*s),v()),Leg_BL=(r(-34*s),v()),Ear_L=(r(12*cos(t)),v()),Ear_R=(r(12*cos(t)),v()),Tail_01=(r(0,0,20*s),v()),Tail_02=(r(0,0,26*sin(t+.7)),v()))))
a_walk=action('DOG_Walk_Loop',25,walk,True)
dig=[]
for f in (1,5,9,13,17,21,25,31,37):
    active=5<=f<=25; left=f in (9,17,25); right=f in (13,21)
    dig.append((f,spec(Root=(r(),v(0,-.07 if active else 0,-.07 if active else 0)),Body=(r(-18 if active else 0),v()),Head=(r(12 if active else 0),v()),Leg_FL=(r(-75 if left else 30 if right else -20 if active else 0),v()),Leg_FR=(r(-75 if right else 30 if left else -20 if active else 0),v()),Tail_01=(r(0,0,14 if left else -14 if right else 0),v()),Ear_L=(r(8 if active else 0),v()),Ear_R=(r(8 if active else 0),v()))))
a_dig=action('DOG_Digging',37,dig,False)

def export(path,a=None):
    if a:
        arm.animation_data.action=a; scene.frame_start=1; scene.frame_end=int(a.frame_range[1]); scene.frame_set(1)
    bpy.ops.object.select_all(action='DESELECT'); mesh.select_set(True); arm.select_set(True)
    bpy.context.view_layer.objects.active=arm
    bpy.ops.export_scene.fbx(filepath=path,use_selection=True,object_types={'ARMATURE','MESH'},global_scale=1,apply_unit_scale=True,apply_scale_options='FBX_SCALE_UNITS',use_mesh_modifiers=True,mesh_smooth_type='FACE',add_leaf_bones=False,use_armature_deform_only=True,axis_forward='-Z',axis_up='Y',bake_space_transform=False,bake_anim=bool(a),bake_anim_use_all_bones=True,bake_anim_use_nla_strips=False,bake_anim_use_all_actions=False,bake_anim_force_startend_keying=True,bake_anim_step=1,bake_anim_simplify_factor=0,path_mode='AUTO',embed_textures=False)

export(os.path.join(OUT,'DigPals_CometMinerDog_Rig.fbx'))
for a,n in [(a_idle,'Dog_Idle.fbx'),(a_walk,'Dog_Walk.fbx'),(a_dig,'Dog_Digging.fbx')]: export(os.path.join(ANIMS,n),a)

def aim(o,at): o.rotation_euler=(Vector(at)-o.location).to_track_quat('-Z','Y').to_euler()
floor_mat=mat('Preview_Pedestal',(.026,.028,.085),.3,.3)
bpy.ops.object.select_all(action='DESELECT')
bpy.ops.mesh.primitive_cylinder_add(vertices=64,radius=1.25*S,depth=.07*S,location=P((0,0,-.06)))
floor=bpy.context.object; floor.name='PREVIEW_Pedestal'; floor.data.materials.append(floor_mat)
bpy.ops.mesh.primitive_torus_add(major_radius=1.06*S,minor_radius=.026*S,major_segments=64,minor_segments=8,location=P((0,0,-.015)))
bpy.context.object.name='PREVIEW_Ring'; bpy.context.object.data.materials.append(M['cyan'])
bpy.ops.object.camera_add(location=(2.1,-3.2,1.75)); cam=bpy.context.object; cam.name='PREVIEW_Camera'; cam.data.lens=55; aim(cam,P((0,0,.65))); scene.camera=cam
for name,loc,power,color,size in [('Key_Cyan',(-2.5,-2.8,3),950,(.2,.8,1),3),('Fill_Copper',(2.7,-1.3,2),680,(1,.34,.08),2.4),('Rim_Violet',(0,2.4,2.5),1150,(.4,.1,1),2.1)]:
    ld=bpy.data.lights.new(name,'AREA'); ld.energy=power; ld.color=color; ld.shape='DISK'; ld.size=size
    obj=bpy.data.objects.new(name,ld); bpy.context.collection.objects.link(obj); obj.location=loc; aim(obj,P((0,0,.6)))

arm.animation_data.action=a_idle; scene.frame_set(13)
scene.render.filepath=os.path.join(OUT,'Preview_Hero.png'); bpy.ops.render.render(write_still=True)
arm.animation_data.action=a_dig; scene.frame_set(17)
scene.render.filepath=os.path.join(OUT,'Preview_Digging.png'); bpy.ops.render.render(write_still=True)
arm.animation_data.action=a_idle; scene.frame_start=1; scene.frame_end=49; scene.frame_set(13)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'DigPals_CometMinerDog.blend'))
print('DOG_BUILT',len(mesh.data.vertices),len(mesh.data.polygons),len(arm.data.bones),tuple(mesh.dimensions))
