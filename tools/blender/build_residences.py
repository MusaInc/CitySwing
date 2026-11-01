"""Original residence furniture, metric dimensions; bevelled, reusable mobile GLBs."""
import math, os, sys
sys.path.insert(0, os.path.dirname(__file__))
import build_kit as K

def start():
    K.reset()
    global oak, fabric, stone, metal, green, linen
    oak=K.mat('smoked_oak',(0.24,0.13,0.075),.65)
    fabric=K.mat('woven_ochre',(0.58,0.30,0.12),.92)
    stone=K.mat('limestone',(.83,.8,.72),.62)
    metal=K.mat('brushed_bronze',(.28,.22,.14),.35,.65)
    green=K.mat('leaves',(.09,.23,.12),.85)
    linen=K.mat('linen',(.88,.85,.77),.95)
def b(n,s,p,m,r=.025): return K.box(n,s,p,m,bevel=r,segs=3)
def finish(n,parts): K.export('home_'+n+'.glb',[K.join(n,parts)])
start()
p=[b('frame',(2.8,.94,.22),(0,0,.27),oak),b('back',(2.8,.22,.66),(0,.37,.65),fabric,.09)]
for x in [-1.32,1.32]: p.append(b('arm',(.22,.96,.52),(x,0,.51),fabric,.08))
for x in [-.83,0,.83]:
    p.append(b('seat',(.8,.71,.19),(x,-.06,.47),linen,.075))
    p.append(b('cushion',(.76,.17,.46),(x,.22,.77),linen,.08))
for x in [-1.1,1.1]:
    for y in [-.3,.3]: p.append(K.cyl('foot',.025,.18,(x,y,.09),metal,8))
finish('sofa',p)
start()
p=[b('frame',(1.85,2.25,.3),(0,0,.25),oak),b('mattress',(1.8,2.15,.22),(0,0,.51),linen,.1),b('headboard',(1.96,.13,1.16),(0,1.1,.66),fabric,.07),b('duvet',(1.83,1.4,.12),(0,-.34,.65),linen,.055)]
for x in [-.45,.45]: p.append(b('pillow',(.7,.45,.15),(x,.72,.7),linen,.12))
for x in [-.82,.82]:
    for y in [-.95,.95]: p.append(K.cyl('foot',.04,.18,(x,y,.09),metal,8))
finish('bed',p)
start()
p=[b('seat',(.48,.48,.1),(0,0,.48),fabric,.055),b('back',(.48,.09,.44),(0,.22,.76),fabric,.045)]
for x in [-.19,.19]:
    for y in [-.19,.19]: p.append(K.cyl('leg',.022,.45,(x,y,.225),oak,8))
finish('chair',p)
start()
p=[b('top',(2.2,1,.09),(0,0,.77),oak,.08)]
for x in [-.75,.75]: p.append(b('pedestal',(.12,.65,.72),(x,0,.36),metal))
p.append(K.cyl('vase',.12,.28,(0,0,.95),stone,16,r2=.07))
finish('dining',p)
start()
p=[K.cyl('table',.72,.07,(0,0,.4),stone,40)]
for x,y in [(-.4,.2),(.4,.2),(0,-.4)]: p.append(K.cyl('leg',.025,.36,(x,y,.18),metal,10))
p += [b('book',(.3,.23,.045),(.2,.1,.46),fabric,.006),K.cyl('bowl',.14,.07,(-.2,0,.47),oak,20,r2=.18)]
finish('coffee',p)
start()
p=[K.cyl('pot',.25,.43,(0,0,.215),stone,24,r2=.31),K.cyl('trunk',.025,1.5,(0,0,1),oak,8)]
for i in range(18):
    a=i*2.399; z=.7+i*.06
    p.append(K.sphere('leaf',1,(math.cos(a)*.26,math.sin(a)*.26,z),green,10,6,(.26,.105,.075)))
finish('plant',p)
start()
p=[b('vanity',(1.1,.58,.75),(0,0,.4),oak),b('top',(1.15,.62,.065),(0,0,.81),stone),K.cyl('basin',.22,.12,(0,0,.89),linen,24),K.cyl('tap',.022,.3,(0,.23,1),metal,10),b('mirror',(1,.04,.85),(0,.3,1.58),metal)]
finish('vanity',p)
start()
p=[b('plinth',(.4,.55,.35),(0,0,.2),linen,.1),K.sphere('bowl',1,(0,-.1,.45),linen,20,12,(.24,.34,.15)),b('cistern',(.42,.18,.55),(0,.24,.65),linen,.045)]
finish('toilet',p)
