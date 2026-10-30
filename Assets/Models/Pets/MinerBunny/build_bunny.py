"""Build bunny with the shared pet FBX and animation workflow."""
import os
source=os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),'CometMinerDog','build_dog.py')
with open(source,encoding='utf-8') as f: code=f.read()
start=code.index('# A broad chest')
end=code.index("bpy.ops.object.select_all(action='DESELECT')",start)
geometry='''
# Soft cream rabbit with long ears, prominent hind paws and a cotton tail.
uv('Body',(0,.07,.49),(.38,.48,.32),'coat','Body')
uv('Chest',(0,-.31,.49),(.25,.17,.23),'cream','Body')
uv('Head',(0,-.37,.74),(.34,.30,.29),'blue','Head')
uv('Muzzle_Left',(-.09,-.638,.63),(.13,.11,.09),'cream','Head')
uv('Muzzle_Right',(.09,-.638,.63),(.13,.11,.09),'cream','Head')
uv('Nose',(0,-.745,.69),(.055,.04,.04),'ear','Head',16,12)
uv('Chin',(0,-.63,.56),(.10,.07,.06),'cream','Head')
for sign,side in [(-1,'L'),(1,'R')]:
    g='Ear_'+side
    uv('Long_Ear_'+side,(sign*.19,-.34,1.15),(.115,.085,.36),'blue',g)
    uv('Inner_Ear_'+side,(sign*.19,-.417,1.17),(.064,.021,.26),'ear',g)
    uv('Eye_'+side,(sign*.16,-.638,.78),(.055,.03,.068),'nose','Head',16,12)
    uv('Eye_Glint_'+side,(sign*.15,-.665,.80),(.017,.009,.02),'white','Head',12,8)
    for j in range(2):
        cyl('Whisker_'+side+str(j),(sign*.13,-.71,.65-j*.03),(sign*.35,-.76,.67-j*.05),.006,'paw','Head',8)
for label,x,y in [('FL',-.25,-.27),('FR',.25,-.27),('BL',-.28,.32),('BR',.28,.32)]:
    g='Leg_'+label; front=label.startswith('F')
    uv('Leg_'+label,(x,y,.25),(.13,.15,.20) if front else (.18,.20,.24),'blue',g)
    uv('Paw_'+label,(x,y-.09 if front else y+.02,.10),(.15,.21,.10) if front else (.18,.27,.11),'cream',g)
    for j in (-.055,0,.055):
        uv('Toe_'+label+str(j),(x+j,y-.25 if front else y-.20,.065),(.035,.055,.035),'ear',g,12,8)
uv('Cotton_Tail',(0,.55,.58),(.16,.15,.16),'cream','Tail_01',20,12)
# Small miner scarf, headlamp and satchel.
torus('Scarf',(0,-.29,.55),.29,.045,'copper','Head')
ico('Scarf_Knot',(0,-.48,.48),(.085,.06,.09),'copper','Body')
cyl('Lamp_Strap',(-.25,-.45,.95),(.25,-.45,.95),.025,'metal','Head')
torus('Lamp_Rim',(0,-.57,.96),.075,.020,'copper','Head',(radians(90),0,0))
uv('Lamp_Glass',(0,-.588,.96),(.055,.02,.055),'white','Head')
uv('Satchel',(0,.32,.69),(.20,.17,.13),'metal','Body')
ico('Satchel_Buckle',(0,.44,.72),(.055,.035,.055),'copper','Body',1)

'''
code=code[:start]+geometry+code[end:]
for old,new in [
 ('CometMinerDog','MinerBunny'),('Comet Miner Dog','Miner Bunny'),('DPM_Dog','DPM_Bunny'),('DOG_','BUNNY_'),('Dog_','Bunny_'),
 ('Comet_DeepNavy','Bunny_Cream'),('Comet_RoyalBlue','Bunny_White'),('Comet_Crystal_Cyan','Lamp_Glass'),('Comet_Crystal_Violet','Ear_Pink'),
 ("(.025,.055,.13)","(.71,.57,.43)"),("(.055,.15,.32)","(.84,.74,.61)"),("(.88,.68,.42)","(.96,.88,.74)"),
 ("(.12,.045,.16)","(.79,.38,.38)"),("(.2,.8,1)","(1,.8,.58)"),("(.4,.1,1)","(.6,.35,.22)"),
]: code=code.replace(old,new)
exec(compile(code,__file__,'exec'),{'__file__':__file__,'__name__':'__main__'})
