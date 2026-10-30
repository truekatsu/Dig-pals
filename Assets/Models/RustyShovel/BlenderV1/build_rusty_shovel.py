"""Original 'Oxide No. 07' shovel. Run with Blender 5.2 --background --python this_file."""
import bpy, math, json, tempfile, sys
from pathlib import Path
from mathutils import Vector

OUT = Path(__file__).resolve().parent
(OUT/'temp').mkdir(exist_ok=True)
tempfile.tempdir = str(OUT/'temp')
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 32
scene.cycles.device = 'CPU'
scene.render.threads_mode = 'FIXED'
scene.render.threads = 8
scene.unit_settings.system = 'NONE'

def node(mat, kind, **values):
    n = mat.node_tree.nodes.new(kind)
    for k, v in values.items(): n.inputs[k].default_value = v
    return n

def link(mat, a, output, b, inp):
    mat.node_tree.links.new(a.outputs[output], b.inputs[inp])

def ramp(mat, source, stops):
    n = node(mat, 'ShaderNodeValToRGB')
    r = n.color_ramp
    while len(r.elements)>2: r.elements.remove(r.elements[-1])
    for i,(p,c) in enumerate(stops):
        e = r.elements[i] if i<2 else r.elements.new(p)
        e.position=p
        e.color=(*c,1)
    link(mat,source,'Fac',n,'Fac')
    return n

def material(name, kind):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.use_fake_user = True
    bs = m.node_tree.nodes.get('Principled BSDF')
    tex = node(m,'ShaderNodeTexCoord')
    vec = tex.outputs['Object']
    if kind=='wood':
        mapping=node(m,'ShaderNodeVectorMath'); mapping.operation='MULTIPLY'
        mapping.inputs[1].default_value=(18,18,.65)
        m.node_tree.links.new(vec,mapping.inputs[0]); vec=mapping.outputs[0]
    n=node(m,'ShaderNodeTexNoise',Scale=7 if kind!='wood' else 3,Detail=4,Roughness=.72)
    m.node_tree.links.new(vec,n.inputs['Vector'])
    palettes={
      'rust':[(.18,(.025,.018,.013)),(.36,(.095,.035,.014)),(.48,(.29,.084,.023)),(.60,(.46,.18,.050)),(.69,(.11,.12,.112)),(.82,(.29,.32,.30))],
      'paint':[(.22,(.035,.022,.013)),(.40,(.25,.082,.025)),(.51,(.38,.15,.045)),(.56,(.028,.10,.088)),(.75,(.055,.22,.18))],
      'wood':[(.18,(.022,.011,.006)),(.35,(.085,.039,.016)),(.52,(.22,.115,.049)),(.73,(.40,.255,.127)),(.88,(.19,.092,.038))],
      'edge':[(.22,(.07,.055,.035)),(.48,(.18,.19,.17)),(.77,(.40,.43,.39))],
      'leather':[(.2,(.014,.009,.006)),(.5,(.060,.028,.012)),(.8,(.16,.078,.032))],
    }
    color=ramp(m,n,palettes[kind]); link(m,color,'Color',bs,'Base Color')
    fine=node(m,'ShaderNodeTexNoise',Scale=125,Detail=2,Roughness=.8)
    m.node_tree.links.new(tex.outputs['Object'],fine.inputs['Vector'])
    bump=node(m,'ShaderNodeBump',Strength=.32,Distance=.014 if kind in ('rust','paint') else .007)
    link(m,fine,'Fac',bump,'Height'); link(m,bump,'Normal',bs,'Normal')
    if kind in ('rust','paint'):
        rough=ramp(m,n,[(.25,(.95,)*3),(.60,(.89,)*3),(.68,(.48,)*3),(.85,(.38,)*3)])
        metal=ramp(m,n,[(.25,(0,)*3),(.60,(.02,)*3),(.68,(.8,)*3),(.85,(.93,)*3)])
        if kind=='paint':
            rough=ramp(m,n,[(.2,(.95,)*3),(.5,(.93,)*3),(.57,(.67,)*3),(.8,(.73,)*3)])
            bs.inputs['Metallic'].default_value=.03
        else: link(m,metal,'Color',bs,'Metallic')
        link(m,rough,'Color',bs,'Roughness')
    else:
        bs.inputs['Roughness'].default_value={'wood':.82,'edge':.48,'leather':.91}[kind]
        bs.inputs['Metallic'].default_value=.82 if kind=='edge' else 0
    return m

mats={k:material('Source_'+k,k) for k in ('rust','paint','wood','edge','leather')}
parts=[]

def finish(o,name,mat,bevel=0,smooth=True):
    o.name=name
    bpy.context.view_layer.objects.active=o
    o.select_set(True)
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.materials.append(mats[mat])
    if bevel:
        mod=o.modifiers.new('Soft worn edges','BEVEL'); mod.width=bevel; mod.segments=2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for p in o.data.polygons: p.use_smooth=smooth
    parts.append(o)
    o.select_set(False)
    return o

def tube(name,a,b,r,mat,r2=None,verts=16):
    a,b=Vector(a),Vector(b)
    bpy.ops.mesh.primitive_cone_add(vertices=verts,radius1=r,radius2=r if r2 is None else r2,depth=(b-a).length,location=(a+b)/2)
    o=bpy.context.object
    o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    return finish(o,name,mat,.008)

def box(name,loc,size,mat,bevel=.02):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
    o=bpy.context.object; o.scale=size
    return finish(o,name,mat,bevel,False)

def mesh(name,vs,fs,mat):
    me=bpy.data.meshes.new(name); me.from_pydata(vs,[],fs); me.update()
    o=bpy.data.objects.new(name,me); bpy.context.collection.objects.link(o)
    return finish(o,name,mat)

# Closed, cupped blade: each horizontal section has real curvature, front and back.
zs=[-2.70,-2.59,-2.43,-2.20,-1.93,-1.65,-1.38,-1.15,-1.05]
widths=[.035,.19,.37,.57,.70,.76,.74,.68,.55]
N=13
vs=[]
for back in (False,True):
    for j,(z,w) in enumerate(zip(zs,widths)):
        for i in range(N):
            u=i/(N-1)*2-1
            x=w*u
            # Small, deliberate scallop on right cutting edge.
            if j==3 and i==N-1: x-=.045
            y=.095*(1-u*u)-.12*u*u+.035*(z+1.5)
            if back: y+=.055
            vs.append((x,y,z))
fs=[]; count=len(zs)*N
for b in range(2):
    for j in range(len(zs)-1):
        for i in range(N-1):
            a=b*count+j*N+i
            f=(a,a+1,a+N+1,a+N)
            fs.append(tuple(reversed(f)) if b==0 else f)
border=list(range(N))+[j*N+N-1 for j in range(1,len(zs))]+list(range(count-2,count-N-1,-1))+[j*N for j in range(len(zs)-2,0,-1)]
for a,b in zip(border,border[1:]+border[:1]):fs.append((a,b,b+count,a+count))
blade=mesh('Forged cupped blade',vs,fs,'rust')
# Polished cutting strip follows the pointed outline, visibly thin and worn.
for side in (-1,1):
    ev=[]
    for j in range(7):
        z,w=zs[j],widths[j]
        x=w*side
        if side==1 and j==3:x-=.045
        ev.extend([(x,-.123+.035*(z+1.5),z+.004),(x-side*.026,-.108+.035*(z+1.5),z+.020)])
    ef=[(2*j,2*j+1,2*j+3,2*j+2) for j in range(6)]
    edge=mesh('Worn cutting bevel',ev,ef,'edge')
    bpy.context.view_layer.objects.active=edge; edge.select_set(True)
    sol=edge.modifiers.new('Edge thickness','SOLIDIFY');sol.thickness=.009
    bpy.ops.object.modifier_apply(modifier=sol.name);edge.select_set(False)

# Rolled shoulders, rusted socket, exposed wooden shaft, and repair wrap.
for side in (-1,1):
    tube('Rolled foot step',(side*.14,-.01,-1.05),(side*.59,-.055,-1.05),.058,'rust',verts=12)
tube('Tapered socket',(0,.025,-1.70),(0,.025,-.78),.088,'rust',r2=.15)
tube('Original timber shaft',(0,.025,-.93),(0,.025,1.92),.104,'wood',r2=.115,verts=20)
tube('Faded green socket cuff',(0,.025,-.92),(0,.025,-.76),.151,'paint',r2=.143)
for z in (-1.48,-1.17,-.83):
    tube('Hammered socket rivet',(0,-.085,z),(0,-.126,z),.037,'edge',verts=12)
# Raised central reinforcement ends above the cutting tip.
tube('Forged centre spine',(0,.058,-2.22),(0,.07,-1.49),.022,'rust',r2=.045,verts=8)
for i in range(6):
    z=-.52+i*.074
    bpy.ops.mesh.primitive_torus_add(major_radius=.109,minor_radius=.018,major_segments=20,minor_segments=6,location=(0,.025,z))
    o=bpy.context.object;o.rotation_euler.x=.13
    finish(o,'Old leather repair binding','leather')
# D-shaped iron yoke; full width .84, top reaches exactly +2.70.
tube('D grip left yoke',(-.10,.025,1.81),(-.37,.025,2.17),.061,'paint',verts=12)
tube('D grip left upright',(-.37,.025,2.17),(-.37,.025,2.57),.061,'paint',verts=12)
tube('D grip right yoke',(.10,.025,1.81),(.37,.025,2.17),.061,'paint',verts=12)
tube('D grip right upright',(.37,.025,2.17),(.37,.025,2.57),.061,'paint',verts=12)
tube('Hand polished wooden cross grip',(-.38,.025,2.58),(.38,.025,2.58),.12,'wood',verts=20)
for x in (-.38,.38):
    tube('Cross grip iron end cap',(x-.023,.025,2.58),(x+.023,.025,2.58),.12,'rust',verts=16)
tube('Yoke ferrule',(0,.025,1.76),(0,.025,1.96),.137,'paint',r2=.125)
tube('Yoke pin',(0,-.103,1.87),(0,-.135,1.87),.036,'edge',verts=12)

# One mesh, one UV atlas, one final material: economical Roblox import.
bpy.ops.object.select_all(action='DESELECT')
for o in parts:o.select_set(True)
bpy.context.view_layer.objects.active=blade
bpy.ops.object.join()
obj=bpy.context.object;obj.name='RustyShovel_Oxide07'
bpy.context.scene.cursor.location=(0,0,0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
# Recalculate closed shells; cutting strips are thin solidified shells.
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.018,area_weight=.5)
bpy.ops.object.mode_set(mode='OBJECT')
tri=obj.modifiers.new('Stable triangulation','TRIANGULATE')
bpy.ops.object.modifier_apply(modifier=tri.name)

SIZE=2048
maps={}
sources=list(obj.data.materials)
scene.render.bake.margin=12
scene.cycles.samples=8
for label,socket in [('Color','Base Color'),('Roughness','Roughness'),('Metalness','Metallic'),('Normal','Normal')]:
    cached=OUT/('RustyShovel_'+label+'.png')
    if '--reuse-textures' in sys.argv and cached.exists():
        img=bpy.data.images.load(str(cached),check_existing=True)
        if label!='Color':img.colorspace_settings.name='Non-Color'
        maps[label]=img
        continue
    print('BAKING',label,flush=True)
    img=bpy.data.images.new('RustyShovel_'+label,width=SIZE,height=SIZE,alpha=False)
    if label!='Color':img.colorspace_settings.name='Non-Color'
    restore=[]
    for mat in sources:
        ns=mat.node_tree.nodes;ls=mat.node_tree.links
        target=ns.new('ShaderNodeTexImage');target.image=img;ns.active=target
        bs=ns.get('Principled BSDF');out=next(n for n in ns if n.type=='OUTPUT_MATERIAL')
        restore.append((mat,out,bs))
        if label!='Normal':
            em=ns.new('ShaderNodeEmission')
            inp=bs.inputs[socket]
            if inp.is_linked:ls.new(inp.links[0].from_socket,em.inputs['Color'])
            else:
                val=inp.default_value
                em.inputs['Color'].default_value=val if socket=='Base Color' else (val,val,val,1)
            ls.new(em.outputs[0],out.inputs['Surface'])
    bpy.ops.object.bake(type='NORMAL' if label=='Normal' else 'EMIT',normal_space='TANGENT')
    img.filepath_raw=str(OUT/('RustyShovel_'+label+'.png'));img.file_format='PNG';img.save()
    maps[label]=img
    for mat,out,bs in restore:mat.node_tree.links.new(bs.outputs[0],out.inputs['Surface'])

final=bpy.data.materials.new('Oxide07_BakedPBR');final.use_nodes=True
bs=final.node_tree.nodes.get('Principled BSDF')
for label,socket in [('Color','Base Color'),('Roughness','Roughness'),('Metalness','Metallic'),('Normal','Normal')]:
    t=node(final,'ShaderNodeTexImage');t.image=maps[label];t.label=label
    if label=='Normal':
        normal=node(final,'ShaderNodeNormalMap');link(final,t,'Color',normal,'Color');link(final,normal,'Normal',bs,socket)
    else:link(final,t,'Color',bs,socket)
obj.data.materials.clear();obj.data.materials.append(final)
for p in obj.data.polygons:p.material_index=0
obj['Design']='Oxide No. 07 / original DigPals shovel'
obj['CarryVersion']='DiagonalCarryV4'
obj['VisualVersion']='Oxide07BlenderV1'
obj['RobloxHeight']=5.4
obj['RobloxAxis']='Local +Y grip, -Y blade after Y-up export'
obj['HandleRobloxY']=1.6
scene.render.image_settings.file_format='PNG'
scene.render.image_settings.color_mode='RGBA'
scene.render.film_transparent=True
scene.view_settings.view_transform='AgX'
scene.world.color=(.23,.23,.23)

bpy.ops.export_scene.fbx(filepath=str(OUT/'RustyShovel_Oxide07.fbx'),use_selection=True,object_types={'MESH'},axis_forward='-Z',axis_up='Y',apply_unit_scale=True,bake_space_transform=True,mesh_smooth_type='FACE',path_mode='COPY',embed_textures=True,add_leaf_bones=False)
bpy.ops.export_scene.gltf(filepath=str(OUT/'RustyShovel_Oxide07.glb'),export_format='GLB',use_selection=True,export_yup=True)
stats={'design':'Oxide No. 07','visual_version':'Oxide07BlenderV1','vertices':len(obj.data.vertices),'triangles':len(obj.data.polygons),'materials':1,'texture_resolution':SIZE,'height':round(obj.dimensions.z,6),'width':round(obj.dimensions.x,6),'depth':round(obj.dimensions.y,6),'export_up_axis':'+Y','hand_hold_local_y':1.6,'shared_carry':'DiagonalCarryV4','studio_verified':False}
(OUT/'asset_manifest.json').write_text(json.dumps(stats,indent=2))
print('ASSET_STATS',json.dumps(stats),flush=True)
for pos,power,size,color in [((2,-4,6),650,4,(1,.85,.70)),((-3,-2,1),420,3,(.68,.83,1)),((1,3,4),900,3,(1,.72,.43))]:
    bpy.ops.object.light_add(type='AREA',location=pos)
    light=bpy.context.object;light.data.energy=power;light.data.shape='DISK';light.data.size=size;light.data.color=color
    light.rotation_euler=(Vector((0,0,0))-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(3,-9,2.2))
camera=bpy.context.object;scene.camera=camera;camera.data.type='ORTHO';camera.data.ortho_scale=6.35
scene.render.resolution_x=1000;scene.render.resolution_y=1250;scene.render.resolution_percentage=100
scene.cycles.samples=48
for name,pos in [('Preview_Hero',(3,-10,1.6)),('Preview_Front',(0,-10,.1)),('Preview_Back',(-3,10,1.7))]:
    camera.location=pos;camera.rotation_euler=(Vector((0,0,0))-camera.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
camera.location=(3,-10,1.6);camera.rotation_euler=(Vector((0,0,0))-camera.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
for img in maps.values():img.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'RustyShovel_Oxide07.blend'))
print('COMPLETE',flush=True)
