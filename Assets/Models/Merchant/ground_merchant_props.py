"""Shared exterior prop placement correction for both Merchant FBX exports."""
import bpy
from mathutils import Vector

def ground_exterior_props():
    for name,delta in {'ExtSack_1':(1.0,.4,-1.0),'ExtSack_2':(1.6,.7,-1.0)}.items():
        for o in bpy.data.objects:
            if o.name.startswith(name+'_'):o.location+=Vector(delta)
    for name,pos in {'ExtCrystal_Amethyst':(-13.8,-17.2,2.0),'ExtCrystal_GoldOre':(-18.5,-18.8,1.0)}.items():
        bpy.data.objects[name].location=pos
    plinth=bpy.data.objects['ExtCrate_Plinth']
    plinth.location.z=1.5
    plinth.scale.z=3.0/2.5
    bpy.context.view_layer.update()
