import bpy, os, math
from mathutils import Vector, Quaternion

bpy.ops.wm.open_mainfile(filepath=r'D:\Models\golden_shovel\Golden_Shovel.blend')
for img in bpy.data.images:
    p = os.path.join(r'D:\Models\golden_shovel', os.path.basename(img.filepath.replace('\\', '/')))
    if os.path.isfile(p):
        img.filepath = p
        img.reload()

s = bpy.context.scene
s.render.film_transparent = True
s.render.resolution_x = 512
s.render.resolution_y = 512
s.render.resolution_percentage = 100
s.render.image_settings.color_mode = 'RGBA'

cam_obj = bpy.data.objects.get("IconCamera")
if not cam_obj:
    cam_data = bpy.data.cameras.new("IconCamera")
    cam_obj = bpy.data.objects.new("IconCamera", cam_data)
    bpy.context.scene.collection.objects.link(cam_obj)

s.camera = cam_obj
cam_obj.location = (0.55, -2.4, 0.75)
cam_obj.rotation_euler = ((Vector((0, 0, 0.59)) - cam_obj.location).to_track_quat('-Z', 'Y') @ Quaternion((0, 0, 1), math.radians(-32))).to_euler()
cam_obj.data.type = 'ORTHO'
cam_obj.data.ortho_scale = 1.32
s.render.filepath = r'D:\DigPals\Assets\Icons\icon_golden_shovel.png'
bpy.ops.render.render(write_still=True)
print("[RENDER COMPLETE] icon_golden_shovel.png generated successfully")
