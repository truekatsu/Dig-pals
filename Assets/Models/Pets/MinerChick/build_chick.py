"""Build chick using the shared pet rig and export workflow."""
import os
source=os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),'CometMinerDog','build_dog.py')
with open(source,encoding='utf-8') as f: code=f.read()
start=code.index('# A broad chest')
end=code.index("bpy.ops.object.select_all(action='DESELECT')",start)
geometry='''
# A round chick with a short beak, small wings, orange feet and feather tufts.
uv('Body',(0,.07,.54),(.37,.39,.37),'coat','Body')
uv('Belly',(0,-.27,.48),(.25,.15,.25),'cream','Body')
uv('Head',(0,-.30,.85),(.31,.29,.28),'blue','Head')
ico('Beak_Upper',(0,-.615,.78),(.13,.12,.075),'copper','Head',1)
ico('Beak_Lower',(0,-.605,.72),(.105,.09,.045),'ear','Head',1)
for sign,side in [(-1,'L'),(1,'R')]:
    uv('Eye_'+side,(sign*.155,-.556,.91),(.057,.033,.068),'nose','Head',16,12)
    uv('Eye_Glint_'+side,(sign*.145,-.585,.93),(.018,.01,.02),'white','Head',12,8)
    uv('Cheek_'+side,(sign*.235,-.535,.77),(.055,.02,.032),'ear','Head',16,12)
    g='Leg_F'+side
    uv('Wing_'+side,(sign*.37,.02,.57),(.14,.22,.22),'blue',g)
    for j in range(3):
        uv('Wing_Feather_'+side+str(j),(sign*(.43+j*.025),.06+j*.055,.48),(.045,.09,.08),'cream',g,16,12)
for label,x in [('BL',-.19),('BR',.19)]:
    g='Leg_'+label
    cyl('Leg_'+label,(x,.25,.30),(x,.25,.10),.045,'copper',g,12)
    uv('Foot_'+label,(x,.13,.08),(.13,.19,.065),'copper',g,16,12)
    for j in (-.07,0,.07):
        uv('Toe_'+label+str(j),(x+j,-.01,.065),(.045,.10,.045),'copper',g,12,8)
for j in (-1,0,1):
    uv('Head_Tuft_'+str(j),(j*.08,-.23,1.12),(.05,.07,.14),'blue','Head',16,12)
    uv('Tail_Feather_'+str(j),(j*.09,.43,.59),(.07,.17,.09),'cream','Tail_01',16,12)
# A small work helmet, lamp and utility satchel.
uv('Miner_Helmet',(0,-.25,1.05),(.29,.25,.10),'metal','Head')
uv('Helmet_Brim',(0,-.46,1.02),(.29,.12,.03),'copper','Head')
torus('Lamp_Rim',(0,-.485,1.08),.065,.018,'copper','Head',(radians(90),0,0))
uv('Lamp_Lens',(0,-.505,1.08),(.048,.02,.048),'white','Head',16,12)
uv('Satchel',(0,.34,.69),(.18,.14,.13),'metal','Body')
ico('Satchel_Buckle',(0,.46,.70),(.05,.03,.05),'copper','Body',1)

'''
code=code[:start]+geometry+code[end:]
for old,new in [
 ('CometMinerDog','MinerChick'),('Comet Miner Dog','Miner Chick'),('DPM_Dog','DPM_Chick'),('DOG_','CHICK_'),('Dog_','Chick_'),
 ('Comet_DeepNavy','Chick_Gold'),('Comet_RoyalBlue','Chick_Yellow'),('Comet_Crystal_Cyan','Lamp_Glass'),('Comet_Crystal_Violet','Chick_Blush'),
 ("(.025,.055,.13)","(.96,.59,.08)"),("(.055,.15,.32)","(1,.78,.25)"),("(.88,.68,.42)","(1,.9,.53)"),
 ("(.12,.045,.16)","(.95,.34,.17)"),("(.78,.33,.07)","(.93,.34,.035)"),
 ("(.2,.8,1)","(1,.8,.58)"),("(.4,.1,1)","(.6,.35,.22)"),
]: code=code.replace(old,new)
code=code.replace("    bone('Leg_'+pos,(x,y,.49),(x,y,.09),'Body')", "    bone('Leg_'+pos,(x,0,.59) if pos.startswith('F') else (x,y,.49),(x*1.3,0,.43) if pos.startswith('F') else (x,y,.09),'Body')")
exec(compile(code,__file__,'exec'),{'__file__':__file__,'__name__':'__main__'})
