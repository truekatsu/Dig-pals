"""Build the mole using the shared pet rig/export workflow."""
import os
source = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'CometMinerDog', 'build_dog.py')
with open(source, encoding='utf-8') as f:
    code = f.read()
start = code.index('# A broad chest')
end = code.index("bpy.ops.object.select_all(action='DESELECT')", start)
geometry = '''
# Rounded earth-toned mole with oversized digging claws and a miner lamp.
uv('Body',(0,.08,.49),(.43,.53,.34),'coat','Body')
uv('Chest',(0,-.35,.45),(.31,.16,.23),'cream','Body')
uv('Head',(0,-.43,.68),(.38,.33,.30),'blue','Head')
uv('Snout',(0,-.74,.58),(.22,.21,.13),'cream','Head')
uv('Nose',(0,-.925,.64),(.10,.065,.07),'ear','Head')
uv('Lower_Jaw',(0,-.71,.50),(.15,.12,.055),'cream','Head')
for sign,side in [(-1,'L'),(1,'R')]:
    uv('Eye_'+side,(sign*.20,-.716,.76),(.048,.035,.055),'nose','Head',16,12)
    uv('Eye_Glint_'+side,(sign*.19,-.746,.78),(.014,.010,.015),'white','Head',12,8)
    uv('Cheek_'+side,(sign*.24,-.70,.59),(.12,.10,.09),'cream','Head')
    for j in range(3):
        cyl('Whisker_'+side+str(j),(sign*.17,-.84,.61-j*.025),(sign*.40,-.89,.64-j*.045),.007,'paw','Head',8)
    uv('Small_Ear_'+side,(sign*.34,-.35,.79),(.09,.07,.11),'blue','Head')
    uv('Ear_Inner_'+side,(sign*.36,-.415,.79),(.045,.02,.06),'ear','Head')
for label,x,y in [('FL',-.28,-.31),('FR',.28,-.31),('BL',-.28,.36),('BR',.28,.36)]:
    g='Leg_'+label
    uv('Leg_'+label,(x,y,.27),(.16,.17,.22),'blue',g)
    front=label.startswith('F')
    uv('Paw_'+label,(x,y-.12 if front else y+.08,.10),(.23 if front else .16,.22,.11),'ear',g)
    for j in (-.12,-.04,.04,.12) if front else (-.07,0,.07):
        x2=x+j
        a=(x2,y-.25 if front else y+.18,.09)
        b=(x2*1.08,y-.38 if front else y+.28,.045)
        cyl('Dig_Claw_'+label+str(j),a,b,.035 if front else .025,'paw',g,8)
uv('Short_Tail',(0,.64,.48),(.09,.17,.09),'ear','Tail_01',16,12)
# Canvas cap, copper headlamp, harness and ore pouch.
uv('Miner_Cap',(0,-.36,.91),(.34,.29,.12),'metal','Head')
uv('Cap_Brim',(0,-.63,.88),(.34,.13,.035),'copper','Head')
torus('Headlamp_Rim',(0,-.641,.96),.09,.025,'copper','Head',(radians(90),0,0))
uv('Headlamp_Lens',(0,-.658,.96),(.067,.025,.067),'white','Head')
cyl('Harness_Left',(-.34,-.15,.62),(-.33,.42,.42),.035,'copper','Body')
cyl('Harness_Right',(.34,-.15,.62),(.33,.42,.42),.035,'copper','Body')
uv('Ore_Pouch',(0,.39,.72),(.24,.20,.16),'metal','Body')
ico('Ore_Gold',(-.10,.40,.86),(.09,.09,.10),'copper','Body',1)
ico('Ore_Stone',(.10,.40,.86),(.09,.10,.11),'paw','Body',1)

'''
code = code[:start] + geometry + code[end:]
for old, new in [
    ('CometMinerDog','MinerMole'), ('Comet Miner Dog','Miner Mole'),
    ('DPM_Dog','DPM_Mole'), ('DOG_', 'MOLE_'), ('Dog_', 'Mole_'),
    ('Comet_DeepNavy','Mole_EarthBrown'), ('Comet_RoyalBlue','Mole_SoftBrown'),
    ('Comet_Crystal_Cyan','Lamp_Glass'), ('Comet_Crystal_Violet','Mole_EarPink'),
    ("(.025,.055,.13)","(.20,.09,.045)"),
    ("(.055,.15,.32)","(.34,.18,.095)"),
    ("(.12,.045,.16)","(.64,.30,.25)"),
    ("(.04,.74,1)","(1,.76,.30)"),
    ("(.36,.09,.8)","(.62,.29,.24)"),
    ("(.2,.8,1)","(1,.76,.50)"),
    ("(.4,.1,1)","(.60,.30,.16)"),
]: code=code.replace(old,new)
exec(compile(code, __file__, 'exec'), {'__file__':__file__, '__name__':'__main__'})
