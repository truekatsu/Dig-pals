import bpy, math, json, os

blend_path = bpy.data.filepath
print("Processing blend file:", blend_path)

arm = bpy.data.objects.get('DPM_Chick_Rig')
if not arm:
    for obj in bpy.data.objects:
        if obj.type == 'ARMATURE':
            arm = obj
            break
print("Using armature:", arm.name)

scene = bpy.context.scene

actions = [
    ('Chick_Idle', 'CHICK_Idle_Loop', True),
    ('Chick_Walk', 'CHICK_Walk_Loop', True),
    ('Chick_Digging', 'CHICK_Digging', False)
]

output = {}

for export_name, act_name, is_loop in actions:
    act = bpy.data.actions.get(act_name)
    if not act:
        print('Missing action:', act_name)
        continue
    arm.animation_data.action = act
    start_f = int(act.frame_range[0])
    end_f = int(act.frame_range[1])
    total_frames = end_f - start_f + 1
    
    keyframes_list = []
    
    for f in range(start_f, end_f + 1):
        scene.frame_set(f)
        time_sec = (f - start_f) / 24.0
        
        poses = {}
        for pb in arm.pose.bones:
            # Local location and rotation
            rx, ry, rz = pb.rotation_euler
            lx, ly, lz = pb.location
            poses[pb.name] = {
                'loc': [round(lx, 5), round(ly, 5), round(lz, 5)],
                'rot': [round(rx, 5), round(ry, 5), round(rz, 5)] # radians
            }
        
        keyframes_list.append({
            'time': round(time_sec, 4),
            'poses': poses
        })
        
    output[export_name] = {
        'loop': is_loop,
        'fps': 24,
        'length': round((total_frames - 1) / 24.0, 4),
        'keyframes': keyframes_list
    }

out_json_path = os.path.join(os.path.dirname(blend_path), 'chick_anims_processed.json')
with open(out_json_path, 'w', encoding='utf-8') as out_f:
    json.dump(output, out_f, indent=2)

print('Generated chick_anims_processed.json successfully!')
for k, v in output.items():
    print(f'  {k}: {len(v["keyframes"])} keyframes, loop={v["loop"]}, length={v["length"]}s')
