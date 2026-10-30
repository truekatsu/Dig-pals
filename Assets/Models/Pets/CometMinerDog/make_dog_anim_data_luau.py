import json, os

json_path = 'd:/DigPals/Assets/Models/Pets/CometMinerDog/dog_anims_processed.json'
with open(json_path, 'r', encoding='utf-8') as f:
    data = json.load(f)

lines = []
lines.append('--!strict')
lines.append('-- Auto-generated animation data for CometMinerDog from Blender master actions')
lines.append('local DogAnimationData = {')

for anim_name, anim_info in data.items():
    loop_str = 'true' if anim_info['loop'] else 'false'
    lines.append(f'    ["{anim_name}"] = {{')
    lines.append(f'        Loop = {loop_str},')
    lines.append(f'        Length = {anim_info["length"]},')
    lines.append('        Keyframes = {')
    
    for kf in anim_info['keyframes']:
        t = kf['time']
        poses_str_list = []
        for bname, pval in kf['poses'].items():
            loc = pval['loc']
            rot = pval['rot']
            # Only include if non-zero to save space
            if any(abs(v) > 0.0001 for v in loc) or any(abs(v) > 0.0001 for v in rot):
                poses_str_list.append(f'["{bname}"] = {{loc = {{{loc[0]}, {loc[1]}, {loc[2]}}}, rot = {{{rot[0]}, {rot[1]}, {rot[2]}}}}}')
        
        poses_content = ', '.join(poses_str_list)
        lines.append(f'            {{ Time = {t}, Poses = {{ {poses_content} }} }},')
    
    lines.append('        },')
    lines.append('    },')

lines.append('}')
lines.append('return DogAnimationData')

output_path = 'd:/DigPals/Assets/Models/Pets/CometMinerDog/DogAnimationData.luau'
with open(output_path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines))

print(f'Wrote {output_path}, size: {os.path.getsize(output_path)} bytes')
