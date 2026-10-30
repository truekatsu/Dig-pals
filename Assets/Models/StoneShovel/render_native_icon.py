"""Render the exported Roblox part specs; no imported meshes or image textures."""
import bpy, json, math
from pathlib import Path
from mathutils import Vector, Matrix, Quaternion

ROOT = Path(__file__).resolve().parents[3]
specs = json.loads((Path(__file__).parent / 'native_geometry.json').read_text())
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
# Roblox XYZ -> Blender X,-Z,Y.
axis = Matrix(((1,0,0),(0,0,-1),(0,1,0)))
for spec in specs:
    sx, sy, sz = spec['size']
    if spec['class'] == 'WedgePart':
        # Roblox wedges have their vertical face at +Z and flat underside at -Y.
        verts = [(x,y,z) for x in (-sx/2,sx/2) for y,z in ((-sy/2,-sz/2),(-sy/2,sz/2),(sy/2,sz/2))]
        mesh = bpy.data.meshes.new(spec['name'])
        mesh.from_pydata(verts, [], [(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)])
        obj = bpy.data.objects.new(spec['name'],mesh)
        bpy.context.collection.objects.link(obj)
    elif spec.get('shape') == 'Ball':
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=6,radius=.5)
        obj = bpy.context.object
        obj.name = spec['name']
        obj.scale = (sx,sy,sz)
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    else:
        bpy.ops.mesh.primitive_cube_add(size=1)
        obj = bpy.context.object
        obj.name = spec['name']
        obj.scale = (sx,sy,sz)
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    c = spec['cf']
    rot = Matrix((c[3:6],c[6:9],c[9:12]))
    obj.matrix_world = (axis @ rot).to_4x4()
    obj.location = axis @ Vector(c[:3])
    mat = bpy.data.materials.new(spec['name'])
    mat.diffuse_color = (*spec['color'],1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*[v**2.2 for v in spec['color']],1)
    bsdf.inputs['Roughness'].default_value = .87
    if spec.get('material') == 'CorrodedMetal':
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        coord = nodes.new('ShaderNodeNewGeometry')
        noise = nodes.new('ShaderNodeTexNoise')
        noise.inputs['Scale'].default_value = 8
        noise.inputs['Detail'].default_value = 3
        links.new(coord.outputs['Position'],noise.inputs['Vector'])
        ramp = nodes.new('ShaderNodeValToRGB')
        ramp.color_ramp.elements[0].position = .23
        ramp.color_ramp.elements[0].color = (.067,.036,.018,1)
        ramp.color_ramp.elements[1].position = .77
        ramp.color_ramp.elements[1].color = (.25,.12,.055,1)
        links.new(noise.outputs['Fac'],ramp.inputs[0])
        links.new(ramp.outputs['Color'],bsdf.inputs['Base Color'])
        bump = nodes.new('ShaderNodeBump')
        bump.inputs['Strength'].default_value = .24
        bump.inputs['Distance'].default_value = .012
        links.new(noise.outputs['Fac'],bump.inputs['Height'])
        links.new(bump.outputs[0],bsdf.inputs['Normal'])
        bsdf.inputs['Metallic'].default_value = .28
    if spec.get('material') in {'Granite','Slate'}:
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        coord = nodes.new('ShaderNodeNewGeometry')
        noise = nodes.new('ShaderNodeTexNoise')
        noise.inputs['Scale'].default_value = 24
        noise.inputs['Detail'].default_value = 4
        links.new(coord.outputs['Position'],noise.inputs['Vector'])
        ramp = nodes.new('ShaderNodeValToRGB')
        ramp.color_ramp.elements[0].position = .28
        ramp.color_ramp.elements[0].color = (.095,.11,.13,1)
        ramp.color_ramp.elements[1].position = .72
        ramp.color_ramp.elements[1].color = (.34,.37,.40,1)
        links.new(noise.outputs['Fac'],ramp.inputs[0])
        links.new(ramp.outputs['Color'],bsdf.inputs['Base Color'])
        bump = nodes.new('ShaderNodeBump')
        bump.inputs['Strength'].default_value = .42
        bump.inputs['Distance'].default_value = .022
        links.new(noise.outputs['Fac'],bump.inputs['Height'])
        links.new(bump.outputs[0],bsdf.inputs['Normal'])
        bsdf.inputs['Roughness'].default_value = .95
    obj.data.materials.append(mat)

scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 48
scene.render.film_transparent = True
scene.render.resolution_x = scene.render.resolution_y = 512
scene.render.resolution_percentage = 100
scene.render.image_settings.color_mode = 'RGBA'
scene.world.color = (.35,.35,.35)
scene.view_settings.view_transform = 'Standard'
for pos,power,size in [((3,-4,6),750,5),((-4,-2,2),450,4),((1,3,5),700,3)]:
    bpy.ops.object.light_add(type='AREA',location=pos)
    light=bpy.context.object
    light.data.energy=power
    light.data.shape='DISK'
    light.data.size=size
    light.rotation_euler=(Vector((0,0,0))-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(2,-9,2.4))
cam=bpy.context.object
target=Vector((0,0,-.17))
cam.rotation_euler=((target-cam.location).to_track_quat('-Z','Y') @ Quaternion((0,0,1),math.radians(-28))).to_euler()
cam.data.type='ORTHO'
cam.data.ortho_scale=4.8
scene.camera=cam
scene.render.filepath=str(ROOT/'Assets/Icons/icon_stone_shovel.png')
bpy.ops.render.render(write_still=True)
