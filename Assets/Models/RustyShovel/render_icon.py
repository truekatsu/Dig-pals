import bpy, os, math
from mathutils import Vector, Quaternion
bpy.ops.wm.open_mainfile(filepath=r'D:\Models\rusty_shovel\Rusty_Shovel.blend')
for img in bpy.data.images:
 p=os.path.join(r'D:\Models\rusty_shovel',os.path.basename(img.filepath.replace('\\','/')))
 if os.path.isfile(p): img.filepath=p; img.reload()
s=bpy.context.scene
s.render.film_transparent=True
s.render.resolution_x=512
s.render.resolution_y=512
s.render.resolution_percentage=100
s.render.image_settings.color_mode='RGBA'
c=s.camera
c.location=(0.55,-2.4,0.75)
c.rotation_euler=((Vector((0,0,0.59))-c.location).to_track_quat('-Z','Y') @ Quaternion((0,0,1),math.radians(-32))).to_euler()
c.data.type='ORTHO'
c.data.ortho_scale=1.32
s.render.filepath=r'D:\DigPals\Assets\Icons\icon_rusty_shovel.png'
bpy.ops.render.render(write_still=True)
