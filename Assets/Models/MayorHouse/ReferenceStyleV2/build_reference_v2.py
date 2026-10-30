"""Rebuild the mayor building using the established house layout and reference-inspired detailing."""
import os
root=os.path.dirname(os.path.abspath(__file__))
source=os.path.join(os.path.dirname(root),'build_mayor_house.py')
with open(source,encoding='utf-8') as f: code=f.read()
code=code.replace("OUT=os.path.dirname(os.path.abspath(__file__))", "OUT="+repr(root))
code=code.replace("scene.render.resolution_x=1400; scene.render.resolution_y=1100", "scene.render.resolution_x=1920; scene.render.resolution_y=1080")
code=code.replace("(.30,.065,.045)","(.065,.075,.09)")
code=code.replace("(.58,.30,.105)","(.31,.16,.09)")
code=code.replace("(.78,.50,.19)","(.43,.075,.085)")
code=code.replace("(.46,.075,.045)","(.34,.035,.055)")
code=code.replace("(.17,.065,.025)","(.10,.065,.052)")
code=code.replace("(.32,.34,.35)","(.23,.25,.27)")
code=code.replace("(.47,.47,.44)","(.35,.37,.37)")
code=code.replace("(0,-11.67,6.45),(6.30,.12,1.0),'red'", "(0,-11.67,6.45),(6.30,.12,1.0),'timber'")
code=code.replace(".57,'white'", ".57,'cream'")
code=code.replace("scene.world.color=(.12,.16,.22)","scene.world.color=(.31,.37,.46)")
code=code.replace("(26,-35,23),(0,-1,4.2),34", "(27,-37,20),(0,-1,4.4),32")
code=code.replace("(38,42,.3),'green'", "(38,42,.3),'stone'")

detail='''
# Reference-inspired painted horizontal siding and restrained wood/metal trim.
for z in [1.12+i*.32 for i in range(18)]:
    for x in (-9.02,9.02):
        box('Siding_Seam',(x,0,z),(.025,14.6,.025),'timber','Architecture')
    box('Rear_Siding_Seam',(0,7.52,z),(17.5,.025,.025),'timber','Architecture')
    for x,w in [(-7.0,3.6),(-3.6,1.0),(3.6,1.0),(7.0,3.6)]:
        box('Facade_Siding_Seam',(x,-7.52,z),(w,.026,.025),'timber','Architecture')
for z in [7.18+i*.32 for i in range(10)]:
    width=max(.3,17.2-(z-7.15)*4.24)
    box('Gable_Siding_Seam',(0,-7.51,z),(width,.035,.025),'timber','Roof')
# Staggered stone courses replace the former broad, flat foundation blocks.
for row in range(4):
    z=.11+row*.17
    for i in range(19):
        x=-8.8+i*.96+(row%2)*.48
        if x<8.9:
            for y in (-7.62,7.62): box('Masonry_Brick',(x,y,z),(.90,.07,.145),'stone2' if (i+row)%4==0 else 'stone','Architecture')
    for i in range(15):
        y=-6.8+i*.96+(row%2)*.48
        if y<7.0:
            for x in (-9.10,9.10): box('Masonry_Brick',(x,y,z),(.07,.90,.145),'stone2' if (i+row)%4==0 else 'stone','Architecture')
# Layered rafters and shingle courses keep the roof legible from a distance.
for s in (-1,1):
    for y in (-8.2,8.2):
        for zoff in (-.13,.03,.18):
            box('Rafter_Gold_Pinstripe',(s*4.8,y,8.82+zoff),(slope,.09,.035),'wood','Roof',rot=(0,s*angle,0))
    for row in range(12):
        x=s*(.42+row*.76); z=10.65-abs(x)*3.7/9.6+.19
        for j in range(19):
            y=-7.65+j*.82+(row%2)*.41
            if y<8.0:
                box('Slate_Shingles',(x,y,z),(.78,.76,.08),'slate' if (j+row)%4 else 'roof','Roof',rot=(0,s*angle,0))
# Porch posts with dark metal bands, gold rivets and bracket silhouettes.
for x in (-5.75,5.75):
    for z in (1.75,3.05,4.4,5.5):
        box('Post_Band',(x,-10.65,z),(.62,.62,.16),'slate','Architecture')
        for dx in (-.18,.18): sphere('Post_Rivet',(x+dx,-10.98,z),(.045,.025,.045),'gold','Exterior_Decor',8,6)
    for s in (-1,1): box('Porch_Brace',(x+s*.55,-10.65,5.55),(1.55,.40,.28),'timber','Architecture',rot=(0,s*radians(35),0))
# Nested gold borders and bold serif lettering echo the two reference signs.
for x in (-3.0,3.0): box('Sign_Inner_Vertical',(x,-11.765,6.45),(.035,.035,.82),'gold','Exterior_Decor')
for z in (6.04,6.86): box('Sign_Inner_Horizontal',(0,-11.765,z),(6.03,.035,.035),'gold','Exterior_Decor')
for x in (-2.91,0,2.91):
    for z in (6.10,6.80): sphere('Sign_Rivet',(x,-11.79,z),(.045,.022,.045),'cream','Exterior_Decor',8,6)
for o in list(collections['Exterior_Decor'].objects):
    if o.name.startswith('Mayor_Office_Lettering'): o.data.materials.clear(); o.data.materials.append(M['cream'])
text_obj('Office_Subtitle','TOWN HALL  -  EST. DIGPALS',(0,-11.79,6.13),.18,'cream')
# Small symmetrical gold shield ornaments on the nameplate.
for x in (-2.55,2.55):
    box('Sign_Shield',(x,-11.80,6.45),(.38,.035,.48),'gold','Exterior_Decor')
    box('Sign_Shield_Inset',(x,-11.825,6.45),(.23,.02,.29),'red','Exterior_Decor')
# Additional timber details communicate the same construction language as both shops.
for x in (-8.6,-4,4,8.6):
    for z in (1.6,3.3,5.0): box('Facade_Post_Band',(x,-7.85,z),(.53,.16,.13),'wood','Architecture')
for x in (-7.4,7.4):
    box('Planter_Topsoil',(x,-9.7,1.40),(1.38,1.28,.08),'soil','Exterior_Decor')
    for z in (.35,.62,.89): box('Planter_Wood_Seam',(x,-10.42,z),(1.42,.03,.035),'timber','Exterior_Decor')
'''
marker='# Independent stylized mayor character, exported separately from building.'
code=code.replace(marker,detail+'\n'+marker)
exec(compile(code,__file__,'exec'),{'__file__':__file__,'__name__':'__main__'})
