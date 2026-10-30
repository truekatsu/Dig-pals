import bpy, math, os
from mathutils import Vector
from math import radians

OUT=os.path.dirname(os.path.abspath(__file__))
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene; scene.render.engine='BLENDER_EEVEE'; scene.render.fps=24
scene.render.resolution_x=1400; scene.render.resolution_y=1100; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'; scene.world.color=(.12,.16,.22)
collections={}
for name in ('Architecture','Roof','Furnishings','Exterior_Decor','Mayor_NPC','Preview'):
    c=bpy.data.collections.new(name); scene.collection.children.link(c); collections[name]=c
def move(obj,group):
    for c in list(obj.users_collection): c.objects.unlink(obj)
    collections[group].objects.link(obj)
def mat(n,c,metal=0,rough=.7):
    m=bpy.data.materials.new(n); m.diffuse_color=(*c,1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*c,1); p.inputs['Metallic'].default_value=metal; p.inputs['Roughness'].default_value=rough
    return m
M={
 'timber':mat('Wood_Dark',(.17,.065,.025)), 'wood':mat('Wood_Honey',(.58,.30,.105)), 'lightwood':mat('Wood_Golden',(.78,.50,.19)),
 'red':mat('Brick_Red',(.46,.075,.045)), 'roof':mat('Roof_Terracotta',(.30,.065,.045)), 'slate':mat('Roof_Charcoal',(.065,.075,.09)),
 'stone':mat('Stone_Gray',(.32,.34,.35)), 'stone2':mat('Stone_Light',(.47,.47,.44)), 'gold':mat('Gold_Trim',(.92,.55,.09),.65,.3),
 'glass':mat('Glass_Sky',(.27,.65,.73),.05,.22), 'cream':mat('Cream_Paper',(.91,.80,.55)), 'leaf':mat('Leaf_Green',(.18,.38,.12)),
 'soil':mat('Soil',(.15,.075,.035)), 'blue':mat('Mayor_Coat',(.06,.13,.25)), 'skin':mat('Mayor_Skin',(.74,.44,.25)),
 'hair':mat('Mayor_Hair',(.18,.12,.08)), 'white':mat('Ivory',(.94,.90,.77)), 'black':mat('Black',(.02,.023,.03)),
 'green':mat('Grass',(.24,.38,.15)), 'orange':mat('Lamp_Glow',(1,.66,.22)),
}
def box(n,loc,size,ma,group='Architecture',rot=(0,0,0),bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc,rotation=rot); o=bpy.context.object; o.name=n; o.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.materials.append(M[ma]); move(o,group)
    if bevel:
        b=o.modifiers.new('Edge highlights','BEVEL'); b.width=bevel; b.segments=1
        bpy.context.view_layer.objects.active=o; bpy.ops.object.modifier_apply(modifier=b.name)
    return o
def sphere(n,loc,scale,ma,group='Exterior_Decor',segments=12,rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments,ring_count=rings,location=loc); o=bpy.context.object; o.name=n; o.scale=scale
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True); o.data.materials.append(M[ma]); move(o,group); return o
def text_obj(n,text,loc,size,ma,group='Exterior_Decor'):
    curve=bpy.data.curves.new(n,'FONT'); curve.body=text; curve.align_x='CENTER'; curve.align_y='CENTER'; curve.size=size; curve.extrude=.012; curve.bevel_depth=.002
    o=bpy.data.objects.new(n,curve); collections[group].objects.link(o); o.location=loc; o.rotation_euler=(radians(90),0,0); o.data.materials.append(M[ma])
    bpy.context.view_layer.objects.active=o; o.select_set(True); bpy.ops.object.convert(target='MESH'); o.select_set(False); return o
def cylinder(n,loc,radius,depth,ma,group='Exterior_Decor',rot=(0,0,0),vertices=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,location=loc,rotation=rot); o=bpy.context.object; o.name=n; o.data.materials.append(M[ma]); move(o,group); return o

# Local front faces -Y.  The footprint is 18 by 15 Blender units, each mapped to one target stud on import.
box('Stone_Foundation',(0,0,.36),(18,15,.72),'stone')
box('Ground_Floor',(0,0,.77),(17.6,14.6,.15),'wood')
for x in range(-8,9,2):
    for y in (-7.55,7.55): box('Foundation_Block',(x,y,.38),(1.92,.10,.56),'stone2')
for x in (-9.05,9.05):
    for y in range(-6,8,2): box('Foundation_Side_Block',(x,y,.38),(.10,1.9,.56),'stone2')
# Walls leave openings for a real doorway and windows; roof is separate for inspection.
for x in (-8.8,8.8): box('Side_Wall',(x,0,3.9),(.4,14.7,6.2),'lightwood')
box('Back_Wall',(0,7.3,3.9),(17.6,.4,6.2),'lightwood')
for x,w in [(-7.0,3.6),(-3.6,1.0),(3.6,1.0),(7.0,3.6)]: box('Front_Wall',(x,-7.3,3.9),(w,.4,6.2),'lightwood')
for x in (-5.1,5.1):
    box('Window_Sill_Wall',(x,-7.3,1.67),(2.1,.4,1.7),'lightwood')
    box('Window_Header_Wall',(x,-7.3,6.25),(2.1,.4,1.5),'lightwood')
    box('Window_Glass',(x,-7.34,4.1),(2.05,.15,2.8),'glass')
    for dx in (-1.15,1.15): box('Window_Frame',(x+dx,-7.57,4.1),(.22,.25,3.1),'timber')
    for z in (2.55,4.05,5.65): box('Window_Crossbar',(x,-7.58,z),(2.5,.25,.20),'red')
    box('Window_Mullion',(x,-7.61,4.1),(.15,.24,2.95),'timber')
box('Door_Header',(0,-7.3,6.3),(2.65,.4,1.35),'lightwood')
box('Door_Leaf',(0,-7.25,2.88),(2.18,.17,4.20),'timber')
for x in (-.8,-.4,0,.4,.8): box('Door_Plank',(x,-7.37,2.88),(.035,.05,4.0),'wood')
for x in (-1.25,1.25): box('Door_Jamb',(x,-7.53,2.9),(.22,.33,4.35),'timber')
box('Door_Lintel',(0,-7.53,5.1),(2.72,.33,.26),'timber')
sphere('Door_Handle',(.78,-7.50,2.55),(.11,.08,.11),'gold')
for x in (-8.6,-4.0,4.0,8.6):
    for y in (-7.55,7.55): box('Structural_Post',(x,y,3.95),(.48,.52,6.45),'timber')
for z in (.95,3.25,6.9):
    for y in (-7.56,7.56): box('Front_Back_Beam',(0,y,z),(18.0,.5,.35),'timber')
    for x in (-9.0,9.0): box('Side_Beam',(x,0,z),(.48,15.4,.35),'timber')

# Tall gable with broad, block-laid pitched roof.
angle=math.atan2(3.7,9.6); slope=math.sqrt(9.6**2+3.7**2)
for s in (-1,1):
    box('Roof_Plane',(s*4.8,0,8.80),(slope,16.1,.30),'roof','Roof',rot=(0,s*angle,0))
    for i in range(7):
        x=s*(.75+i*1.35); z=10.65-abs(x)*3.7/9.6
        box('Roof_Tile_Row',(x,0,z+.12),(.10,16.25,.11),'red','Roof',rot=(0,s*angle,0))
    for y in (-8.0,8.0): box('Gable_Bargeboard',(s*4.8,y,8.82),(slope,.34,.40),'timber','Roof',rot=(0,s*angle,0))
box('Roof_Ridge',(0,0,10.72),(.46,16.55,.35),'slate','Roof')
# Gable front filled using progressively smaller decorative boards.
for i in range(7):
    z=7.15+i*.50; width=max(1,17.2-i*2.12)
    box('Gable_Board',(0,-7.34,z),(width,.30,.49),'red','Roof')
for s in (-1,1): box('Gable_Trim',(s*4.4,-7.56,8.72),(9.3,.35,.34),'timber','Roof',rot=(0,s*angle,0))
box('Chimney',(5.8,3.8,10.25),(1.25,1.25,3.1),'stone','Roof')
box('Chimney_Cap',(5.8,3.8,11.82),(1.55,1.55,.26),'slate','Roof')

# Front porch, formal steps, sign and emblem.
box('Porch_Stone_Base',(0,-9.15,.5),(13,3.6,1.0),'stone')
box('Porch_Platform',(0,-9.15,1.05),(13,3.55,.2),'wood')
for j in range(3): box('Stone_Step',(0,-11.05-j*.62,.15+j*.20),(7.2,1.9-j*.2,.30+j*.4),'stone2')
for x in (-5.75,5.75):
    box('Porch_Column',(x,-10.65,3.55),(.55,.55,5.1),'timber')
    box('Column_Gold_Cap',(x,-10.65,5.85),(.72,.72,.18),'gold')
    box('Column_Base',(x,-10.65,1.35),(.8,.8,.55),'stone2')
box('Porch_Header',(0,-10.65,6.1),(12.5,.58,.55),'timber')
box('Porch_Roof',(0,-9.2,6.45),(13.5,4.15,.40),'roof','Roof')
box('Porch_Fascia',(0,-11.31,6.4),(13.6,.22,.5),'timber','Roof')
box('Sign_Gold_Frame',(0,-11.48,6.45),(6.7,.30,1.32),'gold')
box('Sign_Red_Field',(0,-11.67,6.45),(6.30,.12,1.0),'red')
text_obj('Mayor_Office_Lettering',"MAYOR'S OFFICE",(0,-11.76,6.43),.57,'white')
box('Civic_Shield_Gold',(0,-11.48,7.48),(1.15,.25,1.12),'gold')
box('Civic_Shield_Red',(0,-11.64,7.48),(.86,.10,.84),'red')
box('Crown_Base',(0,-11.72,7.37),(.62,.07,.13),'gold')
for x in (-.23,0,.23): box('Crown_Point',(x,-11.72,7.55),(.12,.07,.30),'gold')
for x in (-3.1,3.1):
    cylinder('Flagpole',(x,-8.1,4.6),.07,2.8,'gold')
    box('Town_Flag',(x+(.50 if x<0 else -.50),-8.12,5.15),(1.0,.12,.75),'red')
    box('Flag_Badge',(x+(.50 if x<0 else -.50),-8.20,5.15),(.26,.06,.26),'gold')
for x in (-7.4,7.4):
    box('Planter',(x,-9.7,.65),(1.5,1.4,1.3),'wood','Exterior_Decor')
    box('Planter_Rim',(x,-9.7,1.30),(1.65,1.55,.16),'timber','Exterior_Decor')
    for dx,dy,dz in [(-.35,0,0),(.3,.2,.2),(0,-.2,.4)]: box('Block_Shrub',(x+dx,-9.7+dy,1.65+dz),(.65,.7,.65),'leaf','Exterior_Decor')
for x in (-8.1,8.1):
    box('Lamp_Post',(x,-12,2.15),(.22,.22,4.0),'timber','Exterior_Decor')
    box('Lamp_Case',(x,-12,4.22),(.72,.72,.8),'gold','Exterior_Decor')
    box('Lamp_Light',(x,-12.39,4.22),(.52,.04,.58),'orange','Exterior_Decor')
    box('Lamp_Cap',(x,-12,4.68),(.88,.88,.16),'slate','Exterior_Decor')
box('Notice_Post',(-8.0,-10.9,1.7),(.22,.22,2.7),'timber','Exterior_Decor')
box('Notice_Frame',(-8,-11.05,3.05),(2.25,.22,1.65),'timber','Exterior_Decor')
box('Notice_Paper',(-8,-11.19,3.05),(1.95,.07,1.38),'cream','Exterior_Decor')
text_obj('Notice_Label','TOWN NEWS',(-8,-11.24,3.35),.22,'red')
for z in (3.05,2.88,2.71): box('Notice_Line',(-8,-11.24,z),(1.4,.03,.035),'timber','Exterior_Decor')
for j in range(4): box('Path_Stone',(0,-13.2-j*1.4,.08),(4.0,1.15,.16),'stone2','Exterior_Decor')
cylinder('Barrel',(7.6,5.5,1.45),.60,1.4,'wood','Exterior_Decor')
for z in (.95,1.95): cylinder('Barrel_Band',(7.6,5.5,z),.63,.12,'timber','Exterior_Decor')

# Interior: front office and rear living quarters, divided with an open central passage.
for x in (-5.5,5.5): box('Interior_Divider',(x,2.5,3.35),(6.6,.25,5.2),'wood','Furnishings')
for x in (-2.0,2.0): box('Divider_Post',(x,2.5,3.3),(.3,.38,5.1),'timber','Furnishings')
box('Office_Desk',(0,-.25,2.15),(4.6,2.0,.3),'timber','Furnishings')
for x in (-1.9,1.9):
    for y in (-.95,.45): box('Desk_Leg',(x,y,1.5),(.28,.28,1.3),'wood','Furnishings')
box('Desk_Paper',(-.7,-.28,2.34),(1.1,.75,.04),'cream','Furnishings')
box('Desk_Book',(.7,-.20,2.36),(.8,.6,.10),'red','Furnishings')
box('Mayor_Chair_Seat',(0,1.25,1.55),(1.5,1.3,.20),'red','Furnishings')
box('Mayor_Chair_Back',(0,1.85,2.25),(1.55,.22,1.6),'timber','Furnishings')
for x in (-.58,.58):
    for y in (.75,1.75): box('Chair_Leg',(x,y,1.18),(.18,.18,.8),'timber','Furnishings')
for side in (-1,1):
    box('Bookshelf_Frame',(side*8.4,-.3,3.3),(.55,3.7,4.7),'timber','Furnishings')
    for z in (1.2,2.35,3.5,4.65,5.6): box('Shelf',(side*8.1,-.3,z),(.9,3.7,.16),'wood','Furnishings')
    for z in (1.55,2.7,3.85,5.0):
        for i in range(7): box('Book',(side*8.05,-1.85+i*.47,z),(.62,.31,.58),('red','blue','cream','leaf')[i%4],'Furnishings')
box('Town_Map_Frame',(-5,2.27,4.3),(3.3,.20,2.4),'gold','Furnishings')
box('Town_Map',(-5,2.14,4.3),(3.0,.08,2.1),'cream','Furnishings')
for x,z in [(-5.6,4.1),(-4.9,4.5),(-4.2,4.0)]: box('Map_Landmark',(x,2.08,z),(.40,.04,.30),'red','Furnishings')
box('Task_Board_Frame',(5,2.27,4.25),(3.0,.20,2.35),'timber','Furnishings')
box('Task_Board',(5,2.14,4.25),(2.7,.08,2.05),'cream','Furnishings')
for x in (4.35,5,5.65): box('Task_Note',(x,2.08,4.3),(.45,.04,1.1),'white','Furnishings')
box('Bed_Frame',(-5,5.0,1.35),(3.7,4.0,.55),'timber','Furnishings')
box('Bed_Mattress',(-5,5.0,1.73),(3.45,3.7,.35),'cream','Furnishings')
box('Bed_Blanket',(-5,4.45,1.94),(3.48,2.45,.15),'red','Furnishings')
box('Bed_Pillow',(-5,6.05,1.99),(1.8,.8,.25),'white','Furnishings')
box('Wardrobe',(4.0,6.1,3.0),(3.4,1.8,4.4),'wood','Furnishings')
for x in (3.2,4.8): box('Wardrobe_Door',(x,5.14,3.0),(1.46,.12,4.0),'timber','Furnishings')
box('Fireplace',(7.35,4.15,2.3),(2.5,2.0,3.0),'stone','Furnishings')
box('Fireplace_Open',(7.35,3.10,1.9),(1.7,.10,1.65),'black','Furnishings')
for x in (6.95,7.35,7.75): box('Fire_Ember',(x,3.02,1.65),(.25,.12,.7),'orange','Furnishings',rot=(0,radians(15*(x-7.35)),0))

# Independent stylized mayor character, exported separately from building.
N='Mayor_NPC'
box('Mayor_Torso',(0,0,3.25),(1.55,.8,1.8),'blue',N,bevel=.08)
box('Mayor_Shirt',(0,-.42,3.35),(.57,.08,1.35),'white',N)
box('Mayor_Tie',(0,-.48,3.45),(.20,.06,.95),'red',N)
box('Mayor_Head',(0,0,4.70),(1.30,1.0,1.15),'skin',N,bevel=.10)
box('Mayor_Hair',(0,.02,5.25),(1.34,1.04,.24),'hair',N)
for x in (-.38,.38):
    box('Mayor_Eye',(x,-.52,4.78),(.14,.06,.17),'black',N)
    box('Mayor_Brow',(x,-.53,5.00),(.28,.06,.07),'hair',N)
box('Mayor_Nose',(0,-.58,4.62),(.20,.15,.20),'skin',N)
box('Mayor_Moustache',(0,-.59,4.42),(.75,.12,.13),'hair',N)
for x in (-1.02,1.02):
    box('Mayor_Arm',(x,0,3.24),(.43,.72,1.6),'blue',N,bevel=.04)
    box('Mayor_Hand',(x,0,2.43),(.40,.65,.35),'skin',N)
for x in (-.42,.42):
    box('Mayor_Leg',(x,0,1.9),(.54,.68,1.25),'slate',N)
    box('Mayor_Shoe',(x,-.16,1.27),(.60,.95,.24),'black',N)
box('Mayor_Sash',(.37,-.46,3.34),(.18,.08,1.7),'gold',N,rot=(0,radians(-25),0))
box('Mayor_Hat_Brim',(0,0,5.42),(1.7,1.3,.14),'timber',N)
box('Mayor_Hat',(0,0,5.70),(1.25,1.0,.5),'blue',N)
box('Mayor_Hat_Band',(0,-.51,5.52),(1.25,.08,.12),'gold',N)
box('Mayor_Badge',(.43,-.46,3.65),(.25,.08,.25),'gold',N)
# Place NPC behind desk for the master scene; export offset back to ground origin.
for o in collections[N].objects: o.location += Vector((0,1.0,-.5))

def select_collections(names):
    bpy.ops.object.select_all(action='DESELECT')
    for name in names:
        for o in collections[name].objects: o.select_set(True)
    bpy.context.view_layer.objects.active=next(iter(collections[names[0]].objects))
def export(path,names):
    select_collections(names)
    bpy.ops.export_scene.fbx(filepath=path,use_selection=True,object_types={'MESH'},axis_forward='-Z',axis_up='Y',apply_unit_scale=True,add_leaf_bones=False,bake_anim=False,mesh_smooth_type='FACE')
export(os.path.join(OUT,'MayorHouse_Architecture.fbx'),['Architecture','Roof','Furnishings','Exterior_Decor'])
for o in collections[N].objects: o.location -= Vector((0,1.0,-.5)); o.location.z-=1.15
export(os.path.join(OUT,'Mayor_NPC.fbx'),[N])
for o in collections[N].objects: o.location += Vector((0,1.0,.65))

# Preview only: isolated studio lighting and exterior ground.
box('Preview_Ground',(0,0,-.17),(38,42,.3),'green','Preview')
def aim(o,p): o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
def camera(n,loc,target,lens):
    bpy.ops.object.camera_add(location=loc); o=bpy.context.object; o.name=n; move(o,'Preview'); o.data.type='ORTHO'; o.data.ortho_scale=lens; aim(o,target); return o
cam=camera('Camera_Exterior',(26,-35,23),(0,-1,4.2),34); scene.camera=cam
for name,loc,energy,size in [('Key',(-12,-20,30),3500,18),('Fill',(22,-10,18),2200,15),('Rim',(0,20,24),2500,12)]:
    ld=bpy.data.lights.new(name,'AREA'); ld.energy=energy; ld.shape='DISK'; ld.size=size
    o=bpy.data.objects.new(name,ld); collections['Preview'].objects.link(o); o.location=loc; aim(o,(0,0,3))
scene.render.filepath=os.path.join(OUT,'Preview_Exterior.png'); bpy.ops.render.render(write_still=True)
# Roof and facade hidden for a readable interior cutaway render.
for o in collections['Roof'].objects: o.hide_render=True
hidden=[]
for o in collections['Architecture'].objects:
    if o.location.y < -6.7 and o.name not in {'Stone_Foundation','Ground_Floor'}: o.hide_render=True; hidden.append(o)
for o in collections['Exterior_Decor'].objects:
    if o.location.y < -6.7: o.hide_render=True; hidden.append(o)
cam2=camera('Camera_Interior',(17,-23,25),(0,1,1.5),26); scene.camera=cam2
scene.render.filepath=os.path.join(OUT,'Preview_Interior.png'); bpy.ops.render.render(write_still=True)
for o in collections['Roof'].objects: o.hide_render=False
for o in hidden: o.hide_render=False
scene.camera=cam
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'DigPals_MayorHouse.blend'))
print('MAYOR_DONE',len(collections['Architecture'].objects),len(collections['Mayor_NPC'].objects))
