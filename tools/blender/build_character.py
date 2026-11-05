"""Build the CitySwing courier from licensed, authored garment topology.

Blender -b --factory-startup --python tools/blender/build_character.py -- assets/models
Sources and their original UVs live in art/hero/sources; provenance in CREDITS.md.
No voxel fusion or primitive body construction. The source anatomy weights are
transferred through the garments' barycentric fitting records, then retargeted
to the existing gameplay rig. Reproducible .blend + textured GLB output.
"""
import bpy, bmesh, math, json, sys
from pathlib import Path
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
SRC=ROOT/'art/hero/sources'
OUT=Path(sys.argv[sys.argv.index('--')+1]) if '--' in sys.argv else ROOT/'assets/models'
TEX=ROOT/'art/hero/textures'
TEX.mkdir(parents=True,exist_ok=True);OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)

def obj_read(path):
    vs=[];uv=[];fs=[];fu=[];groups=[];group=''
    for line in path.read_text().splitlines():
        a=line.split()
        if not a:continue
        if a[0]=='v':vs.append([float(x) for x in a[1:4]])
        elif a[0]=='vt':uv.append([float(x) for x in a[1:3]])
        elif a[0]=='g':group=' '.join(a[1:])
        elif a[0]=='f':
            f=[x.split('/') for x in a[1:]]
            fs.append([int(x[0])-1 for x in f]);fu.append([int(x[1])-1 if len(x)>1 and x[1] else 0 for x in f]);groups.append(group)
    return np.array(vs),np.array(uv),fs,fu,groups

base,_,_,_,_=obj_read(SRC/'base.obj')
for n,w in [('african-male-young.target',1/3),('asian-male-young.target',1/3),('caucasian-male-young.target',1/3),('universal-male-young-averagemuscle-averageweight.target',.65),('universal-male-young-maxmuscle-averageweight.target',.35)]:
    for l in (SRC/n).read_text().splitlines():
        a=l.split()
        if not a or a[0].startswith('#'):continue
        base[int(a[0])]+=np.array(list(map(float,a[1:4])))*w
sk=json.loads((SRC/'default.mhskel').read_text())
raw_weights=json.loads((SRC/'default_weights.mhw').read_text())['weights']
J={'hips':Vector((0,0,.98)),'spine':Vector((0,0,1.04)),'chest':Vector((0,0,1.30)),'neck':Vector((0,0,1.56)),'head':Vector((0,0,1.64))}
P={'hips':None,'spine':'hips','chest':'spine','neck':'chest','head':'neck'}
for side,sx in [('l',-1),('r',1)]:
    a=Vector((sx*math.sin(math.radians(42)),0,-math.cos(math.radians(42))))
    l=Vector((sx*math.sin(math.radians(5)),0,-math.cos(math.radians(5))))
    J['upper_arm_'+side]=Vector((sx*.2,0,1.50))
    J['forearm_'+side]=J['upper_arm_'+side]+a*.29
    J['hand_'+side]=J['forearm_'+side]+a*.26
    J['thigh_'+side]=Vector((sx*.1,0,.94))
    J['shin_'+side]=J['thigh_'+side]+l*.45
    J['foot_'+side]=J['shin_'+side]+l*.44
    for b,parent in [('upper_arm','chest'),('forearm','upper_arm_'+side),('hand','forearm_'+side),('thigh','hips'),('shin','thigh_'+side),('foot','shin_'+side)]:P[b+'_'+side]=parent
names=list(P);ni={n:i for i,n in enumerate(names)}
def mapped(n):
    side='r' if n.endswith('.L') else 'l'
    if n.startswith('upperarm'):return 'upper_arm_'+side
    if n.startswith('lowerarm'):return 'forearm_'+side
    if n.startswith(('finger','metacarpal','wrist')):return 'hand_'+side
    if n.startswith('upperleg'):return 'thigh_'+side
    if n.startswith('lowerleg'):return 'shin_'+side
    if n.startswith(('foot','toe')):return 'foot_'+side
    if n.startswith('neck'):return 'neck'
    if n.startswith(('pelvis','root','spine05')):return 'hips'
    if n.startswith(('spine03','spine04')):return 'spine'
    if n.startswith(('spine','clavicle','shoulder','breast')):return 'chest'
    return 'head'
weights=np.zeros((len(base),len(names)))
for n,entries in raw_weights.items():
    for i,w in entries:weights[i,ni[mapped(n)]]+=w
weights/=np.maximum(weights.sum(1)[:,None],1e-8)
def source_joint(b,k='head'):
    return Vector(np.mean(base[sk['joints'][sk['bones'][b][k]]],axis=0))
def coord(v):return Vector((v[0],v[2],v[1]))
trans={}
for side,suf in [('r','.L'),('l','.R')]:
    specs=[('upper_arm','upperarm01','lowerarm01','forearm'),('forearm','lowerarm01','wrist','hand'),('hand','wrist','finger3-1',None),('thigh','upperleg01','lowerleg01','shin'),('shin','lowerleg01','foot','foot')]
    for dst,src,end,tail in specs:
        origin=coord(source_joint(src+suf));axis=coord(source_joint(end+suf))-origin
        target=(J[tail+'_'+side]-J[dst+'_'+side]) if tail else (J['hand_'+side]-J['forearm_'+side]).normalized()*.085
        scale=target.length/axis.length if tail else .1
        trans[dst+'_'+side]=(origin,axis.normalized().rotation_difference(target.normalized()),scale)
    trans['foot_'+side]=(coord(source_joint('foot'+suf)),None,.1)

def torso(v):
    x,y,z=v
    h=np.interp(y,[-8.45,1.003,3.225,5.608,6.654,7.62,9.22],[0,.94,1.25,1.50,1.59,1.68,1.84])
    return Vector((x*.105,z*.1,h))
def retarget(v,w):
    result=Vector((0,0,0));p=coord(v)
    for n,i in ni.items():
        if w[i]<1e-6:continue
        if n in trans:
            o,q,s=trans[n];r=p-o
            t=J[n]+(q@r if q else r)*s
        else:t=torso(v)
        result+=t*float(w[i])
    return result

def mesh(name,verts,uv,faces,faceuv):
    me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update()
    ob=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(ob)
    if len(uv):
        layer=me.uv_layers.new(name='GarmentUV')
        for poly,us in zip(me.polygons,faceuv):
            for li,ui in zip(poly.loop_indices,us):layer.data[li].uv=uv[ui]
    for p in me.polygons:p.use_smooth=True
    return ob

def garment(folder,name):
    path=SRC/folder;mh=next(path.glob('*.mhclo'));lines=mh.read_text().splitlines()
    objname=next(l.split()[1] for l in lines if l.startswith('obj_file '))
    _,uv,faces,fu,_=obj_read(path/objname)
    start=next(i for i,l in enumerate(lines) if l.startswith('verts '))+1
    vs=[];ws=[]
    scales={}
    for l in lines[:start]:
        a=l.split()
        if a and a[0] in ['x_scale','y_scale','z_scale']:
            axis={'x_scale':0,'y_scale':1,'z_scale':2}[a[0]]
            scales[axis]=abs(base[int(a[1]),axis]-base[int(a[2]),axis])/float(a[3])
    for l in lines[start:]:
        a=l.split()
        if not a or a[0].startswith('#'):continue
        if not a[0].lstrip('-').isdigit():break
        if len(a)==1:v=base[int(a[0])];w=weights[int(a[0])].copy()
        elif len(a)==9:
            ids=list(map(int,a[:3]));b=np.array(list(map(float,a[3:6])))
            v=(base[ids]*b[:,None]).sum(0)+np.array(list(map(float,a[6:9])))*np.array([scales.get(i,1) for i in range(3)])
            w=np.maximum((weights[ids]*b[:,None]).sum(0),0)
        else:break
        w/=max(w.sum(),1e-8);ws.append(w);vs.append(retarget(v,w))
    assert len(vs)>max(max(f) for f in faces),(name,len(vs))
    ob=mesh(name,vs,uv,[list(reversed(f)) for f in faces],[list(reversed(f)) for f in fu])
    for n,i in ni.items():
        vg=ob.vertex_groups.new(name='b_'+n)
        for vi,w in enumerate(ws):
            if w[i]>.001:vg.add([vi],float(w[i]),'REPLACE')
    return ob

def active(ob):
    bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob

def apply(ob,mod):
    active(ob);bpy.ops.object.modifier_apply(modifier=mod.name)

def subdiv(ob,level):
    m=ob.modifiers.new('Tailored surface','SUBSURF');m.levels=level;apply(ob,m)

def image_load(path):
    im=bpy.data.images.load(str(path),check_existing=True);return im

def material(name,color,rough=.75,tex=None,normal=None):
    m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;l=m.node_tree.links;p=n.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=rough
    if tex:
        t=n.new('ShaderNodeTexImage');t.image=image_load(tex);l.new(t.outputs['Color'],p.inputs['Base Color'])
    if normal:
        t=n.new('ShaderNodeTexImage');t.image=image_load(normal);t.image.colorspace_settings.name='Non-Color'
        nm=n.new('ShaderNodeNormalMap');nm.inputs['Strength'].default_value=.42;l.new(t.outputs['Color'],nm.inputs['Color']);l.new(nm.outputs['Normal'],p.inputs['Normal'])
    return m

def recolor_texture(src,name,color,white=False):
    im=image_load(src);w,h=im.size;data=np.empty(w*h*4,dtype=np.float32);im.pixels.foreach_get(data);a=data.reshape(h,w,4)
    lum=a[:,:,:3].mean(2)
    if white:
        # Retain the authored seams, lace shadows and sole boundary; neutralise old branding colours.
        value=np.clip(lum*.55+.42,.20,.91);rgb=value[:,:,None]*np.array(color)
    else:
        value=np.clip(lum/(np.percentile(lum,70)+.001),.32,1.45);rgb=value[:,:,None]*np.array(color)
    a[:,:,:3]=rgb;a[:,:,3]=1
    out=bpy.data.images.new(name,w,h,alpha=False);out.pixels.foreach_set(a.ravel());out.filepath_raw=str(TEX/(name+'.png'));out.file_format='PNG';out.save();return TEX/(name+'.png')

pants=garment('cortu_cargo_pants','Courier_Cargo')
shoes=garment('punkduck_running_shoes_01','Courier_Trainers')
gloves=garment('toigo_gloves_short','Courier_Gloves')
# Pose-corrective glove shapes retain the authored fingers and UVs.
gloves.shape_key_add(name='Basis')
for side,sx in [('l',-1),('r',1)]:
    key=gloves.shape_key_add(name='Grip_'+side)
    direction=(J['hand_'+side]-J['forearm_'+side]).normalized()
    pivot=J['hand_'+side]+direction*.055
    for v,k in zip(gloves.data.vertices,key.data):
        if v.co.x*sx<0:continue
        d=v.co-pivot;length=d.dot(direction)
        if length<=0:continue
        angle=min(2.3,length/.075*2.3)
        radius=.075/2.3
        sideways=d-direction*length
        k.co=pivot+sideways+direction*(math.sin(angle)*radius)+Vector((0,1,0))*(1-math.cos(angle))*radius
# Add enough topology for knee/elbow deformation without a remesher.
subdiv(pants,2)
subdiv(shoes,1)
m=shoes.modifiers.new("Trainer mobile topology","DECIMATE");m.ratio=.55;apply(shoes,m)
for v in shoes.data.vertices:
    v.co.z+=.035
# A clean, level waistband (the hoodie used to hide the authored one); the
# top tucks in under it.
bm=bmesh.new();bm.from_mesh(pants.data)
bmesh.ops.bisect_plane(bm,geom=bm.verts[:]+bm.edges[:]+bm.faces[:],plane_co=(0,0,.985),plane_no=(0,0,1))
bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.co.z>.985+1e-5],context='VERTS')
bm.to_mesh(pants.data);bm.free();pants.data.update()
for v in pants.data.vertices:
    if v.co.z<.23:
        n='foot_l' if v.co.x<0 else 'foot_r';ank=J[n]
        t=max(0,min(1,(.23-v.co.z)/.20));v.co.x=ank.x+(v.co.x-ank.x)*(1-.28*t)
        v.co.y*=1-.18*t
        v.co.z+=.045*t  # the hem ends inside the trainer's collar, never above it
ptex=recolor_texture(SRC/'cortu_cargo_pants'/'cargo_pants_diff.png','cargo_albedo',(.21,.225,.24)) if (SRC/'cortu_cargo_pants'/'cargo_pants_diff.png').exists() else None
pmat=material('hero_cargo',(.046,.051,.054),.86,ptex,SRC/'cortu_cargo_pants'/'cargo_pants_norm.png')
stex=recolor_texture(SRC/'punkduck_running_shoes_01'/'runningshoes.png','trainer_albedo',(.94,.95,.96),True)
smat=material('hero_trainer',(.8,.8,.8),.55,stex)
gmat=material('hero_glove',(.023,.026,.029),.58)
for ob,mat in [(pants,pmat),(shoes,smat),(gloves,gmat)]:ob.data.materials.clear();ob.data.materials.append(mat)

# ------------------------------------------------------------------ body parts
# The anatomy itself (MakeHuman hm08 body, morphed above) is the source for
# the skin-tight tops, the bare forearms and the heads: cut by skin weight and
# height, retargeted to the gameplay rig with the same weights, so a garment
# made from the skin fits it exactly and deforms with it.
bv,bu,bf,bfu,bg=obj_read(SRC/'base.obj')
GROUP_FACES={}
for i,g in enumerate(bg):GROUP_FACES.setdefault(g,[]).append(i)
RB=[retarget(base[j],weights[j]) for j in range(len(base))]
def wsum(j,*bones):return float(sum(weights[j,ni[b]] for b in bones))
def part(name,faces,positions,wts,flip=True):
    ids=sorted({j for i in faces for j in bf[i]});rm={j:k for k,j in enumerate(ids)}
    fs=[[rm[j] for j in (reversed(bf[i]) if flip else bf[i])] for i in faces]
    fu=[list(reversed(bfu[i])) if flip else list(bfu[i]) for i in faces]
    ob=mesh(name,[positions[j] for j in ids],bu,fs,fu)
    for n,i in ni.items():
        vg=ob.vertex_groups.new(name='b_'+n)
        for k,j in enumerate(ids):
            if wts[j,i]>.001:vg.add([k],float(wts[j,i]),'REPLACE')
    return ob,ids
def push(ob,d,zmask=None):
    bm=bmesh.new();bm.from_mesh(ob.data);bm.normal_update()
    for v in bm.verts:
        k=1.0 if zmask is None else zmask(v.co)
        v.co+=v.normal*d*k
    bm.to_mesh(ob.data);bm.free();ob.data.update()
def arm_t(j):
    # 0 at the shoulder joint, 1 at the elbow, >1 down the forearm.
    p=RB[j];side='l' if p.x<0 else 'r'
    a=J['upper_arm_'+side];e=J['forearm_'+side];ax=e-a
    return (p-a).dot(ax)/ax.length_squared
ARM=('upper_arm_l','upper_arm_r','forearm_l','forearm_r')
def armish(j):return wsum(j,*ARM)>.5
body=GROUP_FACES['body']

# Skin-tight tops: mock neck to the waistband, long sleeves to the glove
# cuff or short sleeves to mid-bicep. 4 mm off the skin (compression knit),
# a turned hem, contrast side panels and a raglan shoulder stripe.
# Sleeve cuts as arm_t limits (0 shoulder, 1 elbow): long to the glove,
# three-quarter just below the elbow, short mid-bicep, sleeveless none.
CUTS={'Long':9.0,'Tq':1.38,'Short':.56,'Vest':-1.0}
def top_faces(cut):
    lim=CUTS[cut];out=[]
    for i in body:
        ok=True
        for j in bf[i]:
            p=RB[j]
            if p.z<.9 or p.z>1.605 or wsum(j,'hand_l','hand_r')>.45 or wsum(j,'thigh_l','thigh_r')>.35:ok=False;break
            if armish(j) and arm_t(j)>lim+.22:ok=False;break
        if ok:out.append(i)
    return out
panelmat=material('hero_top_panel',(.07,.075,.085),.55)
# Knit rib normal map (tangent space, tileable): fine vertical ribs.
if True:
    n=512;y,x=np.mgrid[0:n,0:n]/n
    g=np.random.default_rng(3).random((n,n)).astype(np.float32)
    g=(g+np.roll(g,1,0)+np.roll(g,1,1))/3
    nx=(np.roll(g,1,1)-g)*.9;ny=(np.roll(g,1,0)-g)*.9
    img=np.zeros((n,n,4),dtype=np.float32);img[:,:,0]=.5+nx*.5;img[:,:,1]=.5+ny*.5;img[:,:,2]=1;img[:,:,3]=1
    im=bpy.data.images.new('top_knit_normal',n,n,alpha=False);im.pixels.foreach_set(img.ravel());im.filepath_raw=str(TEX/'top_knit_normal.png');im.file_format='PNG';im.save()
    # Heathered knit albedo (near white: it modulates the shop colour).
    rng=np.random.default_rng(7)
    def noise_img(name,n,lo,hi,blur,extra=None):
        a=rng.random((n,n)).astype(np.float32)
        for _ in range(blur):a=(a+np.roll(a,1,0)+np.roll(a,-1,0)+np.roll(a,1,1)+np.roll(a,-1,1))/5
        a=(a-a.min())/(a.max()-a.min()+1e-6)
        v=lo+(hi-lo)*a
        rgb=np.stack([v,v,v],-1) if extra is None else extra(v)
        img=np.concatenate([rgb,np.ones((n,n,1),dtype=np.float32)],-1)
        im=bpy.data.images.new(name,n,n,alpha=False);im.pixels.foreach_set(img.ravel());im.filepath_raw=str(TEX/(name+'.png'));im.file_format='PNG';im.save()
        return TEX/(name+'.png')
    knit=noise_img('top_knit_albedo',512,.86,1.0,1)
    topmat=material('hero_top',(.16,.17,.19),.62,knit,TEX/'top_knit_normal.png')
    # Skin: fine mottling with a faint warm/cool drift (no painted features).
    skin_tex=noise_img('skin_albedo',512,.9,1.0,2,lambda v:np.stack([v*1.0,v*.985+.01,v*.975+.015],-1))
tops=[]
for cut in ['Long','Tq','Short','Vest']:
    nm='Top_'+cut
    ob,_=part(nm,top_faces(cut),RB,weights)
    push(ob,.004)
    # Clean cuts instead of whole-triangle edges: a level waist hem, sleeve
    # hems square to the arm, straight side seams for the contrast panels.
    lim=CUTS[cut]
    bm=bmesh.new();bm.from_mesh(ob.data)
    def cut_plane(co,no,kill):
        bmesh.ops.bisect_plane(bm,geom=bm.verts[:]+bm.edges[:]+bm.faces[:],plane_co=co,plane_no=no)
        bmesh.ops.delete(bm,geom=[v for v in bm.verts if kill(v.co)],context='VERTS')
    cut_plane((0,0,.95),(0,0,1),lambda co:co.z<.95-1e-5)
    if lim<9:
        for side,sx in [('l',-1),('r',1)]:
            a=J['upper_arm_'+side];e=J['forearm_'+side];h=J['hand_'+side]
            if lim<=1.0:
                pt=a+(e-a)*max(lim,0.0);ax=(e-a).normalized()
            else:
                pt=e+(h-e)*(lim-1.0);ax=(h-e).normalized()
            if lim<0:pt=a+Vector((-sx*.012,0,0))
            def beyond(co,pt=pt,ax=ax,a=a):
                along=(co-pt).dot(ax)
                off=(co-a)-ax*(co-a).dot(ax)   # distance from the arm's own axis
                return along>1e-5 and off.length<.075
            cut_plane(tuple(pt),tuple(ax),beyond)
    # Panel seams cut exactly (inner and outer side seams, and the level top
    # under the arm), so the contrast panel has straight edges, not a
    # staircase of whole triangles.
    for sx in [-1,1]:
        for px in (.135,.205):
            bmesh.ops.bisect_plane(bm,geom=bm.verts[:]+bm.edges[:]+bm.faces[:],plane_co=(sx*px,0,0),plane_no=(1,0,0))
    bmesh.ops.bisect_plane(bm,geom=bm.verts[:]+bm.edges[:]+bm.faces[:],plane_co=(0,0,1.40),plane_no=(0,0,1))
    bm.to_mesh(ob.data);bm.free();ob.data.update()
    ob.data.materials.append(topmat);ob.data.materials.append(panelmat)
    for poly in ob.data.polygons:
        c=poly.center
        poly.material_index=1 if (abs(c.x)>.135 and abs(c.x)<.205 and c.z<1.40) else 0
    so=ob.modifiers.new('Hem','SOLIDIFY');so.thickness=.003;so.offset=-1;so.use_rim_only=True;apply(ob,so)
    tops.append(ob)
top_long,top_tq,top_short,top_vest=tops
# Mock-neck band: a knitted collar fitted round the neck (rows sampled on the
# skin, 5 mm off it), so both tops end in a clean edge over the face's seam.
neck_faces=[i for i in body if all(1.45<RB[j].z<1.68 for j in bf[i])]
ntree=BVHTree.FromPolygons([RB[j] for j in range(len(RB))],[list(reversed(bf[i])) for i in neck_faces])
nc=J['neck'];rows=[1.548,1.575,1.6,1.614];ring=36;cvs=[]
for z in rows:
    for k in range(ring):
        a=math.tau*k/ring;d=Vector((math.sin(a),math.cos(a),0))
        o=Vector((nc.x,nc.y-.005,z))+d*.3
        hit=ntree.ray_cast(o,-d)
        q=hit[0] if hit[0] is not None else Vector((nc.x,nc.y,z))+d*.06
        cvs.append(q+d*(.006 if z<1.61 else .0045))
cfs=[]
for r in range(len(rows)-1):
    for k in range(ring):
        a=r*ring+k;b_=r*ring+(k+1)%ring;cfs.append([a,b_,b_+ring,a+ring])
collar=mesh('Top_Collar',cvs,[],cfs,[]);collar.data.materials.append(material('hero_top_collar',(.16,.17,.19),.62))
vgn=collar.vertex_groups.new(name='b_neck');vgc=collar.vertex_groups.new(name='b_chest')
for v in collar.data.vertices:
    w=max(0.0,min(1.0,(v.co.z-1.54)/.07));vgn.add([v.index],.35+.6*w,'REPLACE');vgc.add([v.index],.65-.6*w,'REPLACE')
so=collar.modifiers.new('Knit','SOLIDIFY');so.thickness=.003;so.offset=-1;apply(collar,so)
subdiv(collar,1)
# Bare forearms for the short sleeve: skin from under the sleeve to under
# the glove cuff (overlapping both, so no seam opens when the arm bends).
skinmat=material('hero_skin',(.5,.34,.25),.48,skin_tex)
armskin=material('hero_skin_body',(.5,.34,.25),.5,skin_tex)
skin_arms=[]
for cut in ['Tq','Short','Vest']:
    lim=CUTS[cut]-.1
    af=[i for i in body if all(armish(j) and arm_t(j)>lim and wsum(j,'hand_l','hand_r')<.75 for j in bf[i])]
    if cut=='Vest':
        # Bare shoulders too: the arm's skin plus the shoulder cap round to the top.
        af=[i for i in body if all((armish(j) or (abs(RB[j].x)>.15 and RB[j].z>1.36)) and wsum(j,'hand_l','hand_r')<.75 for j in bf[i])]
    ob,_=part('Skin_Arms_'+cut,af,RB,weights);ob.data.materials.append(armskin);skin_arms.append(ob)
# Ankle liners: the skin round each ankle, from inside the trainer to well
# under the trouser hem, in a dark knit. Invisible when everything fits; when
# the ankle flexes it fills the gap instead of showing the sky through it.
liner_faces=[i for i in body if all(.045<RB[j].z<.24 and wsum(j,'hand_l','hand_r')<.1 for j in bf[i])]
liner,_=part('Ankle_Liner',liner_faces,RB,weights);push(liner,.003)
liner.data.materials.append(material('hero_liner',(.03,.032,.036),.9));skin_arms.append(liner)

# ------------------------------------------------------------------ faces
# Five faces from MakeHuman's facial targets (art/hero/sources/face_targets,
# CC0), applied to the head only (faded out down the neck, under the mock
# collar, so every face meets the same tops). Skin tone, hair and eye colour
# are tints set in the game (Shop "hero" items); the shapes are here.
FT={}
for f in (SRC/'face_targets').glob('*.target'):
    d={}
    for l in f.read_text().splitlines():
        a=l.split()
        if not a or a[0].startswith('#'):continue
        d[int(a[0])]=np.array(list(map(float,a[1:4])))
    FT[f.stem]=d
ETH={}
for n in ['african','asian','caucasian']:
    d={}
    for l in (SRC/(n+'-male-young.target')).read_text().splitlines():
        a=l.split()
        if not a or a[0].startswith('#'):continue
        d[int(a[0])]=np.array(list(map(float,a[1:4])))
    ETH[n]=d
FACES=[
    ('kai',{'african':0,'asian':0,'caucasian':0},{'cheek_l-cheek-bones-incr':.5,'cheek_r-cheek-bones-incr':.5,'chin_chin-prominent-incr':.35,'nose_nose-point-width-decr':.3,'eyebrows_eyebrows-angle-up':.3,'head_head-square':.25},'buzz'),
    ('ade',{'african':.6,'asian':-.3,'caucasian':-.3},{'head_head-square':.45,'chin_chin-width-incr':.45,'mouth_mouth-lowerlip-volume-incr':.35,'nose_nose-nostrils-width-incr':.3,'forehead_forehead-scale-vert-decr':.3},'crop'),
    ('ren',{'african':-.3,'asian':.6,'caucasian':-.3},{'head_head-round':.35,'cheek_l-cheek-inner-incr':.4,'cheek_r-cheek-inner-incr':.4,'nose_nose-scale-vert-decr':.3,'eyebrows_eyebrows-trans-down':.3,'chin_chin-height-decr':.25},'crop'),
    ('theo',{'african':-.3,'asian':-.3,'caucasian':.6},{'head_head-oval':.45,'nose_nose-hump-incr':.45,'nose_nose-scale-vert-incr':.3,'chin_chin-height-incr':.35,'chin_chin-prominent-incr':.3,'mouth_mouth-scale-horiz-decr':.2},'buzz'),
    ('malik',{'african':.25,'asian':-.15,'caucasian':-.1},{'head_head-diamond':.45,'cheek_l-cheek-bones-incr':.6,'cheek_r-cheek-bones-incr':.6,'nose_nose-curve-convex':.35,'forehead_forehead-temple-incr':.4,'mouth_mouth-upperlip-volume-incr':.3},'crop'),
]
def face_base(eth,tg):
    b=base.copy()
    fade=np.clip((b[:,1]-6.15)/.5,0,1)  # head only; zero below the collar
    for n,w in eth.items():
        for i,dl in ETH[n].items():b[i]+=dl*w*fade[i]
    for n,w in tg.items():
        if n not in FT:print('MISSING TARGET',n);continue
        for i,dl in FT[n].items():b[i]+=dl*w*fade[i]
    # Keep each face's shape, not a moved or rescaled head: remove the mean
    # shift and match the canonical head's height, about its centre.
    sel=fade>=.999
    shift=(b[sel]-base[sel]).mean(0)
    b-=shift[None,:]*fade[:,None]
    c=base[sel].mean(0)
    k=(base[sel,1].max()-base[sel,1].min())/max(b[sel,1].max()-b[sel,1].min(),1e-6)
    b=b+((c+(b-c)*k)-b)*fade[:,None]
    return b
head_faces=[i for i in body if all(base[j,1]>6.3 for j in bf[i])]
face_meshes={}
lipmat=material('hero_lips',(.46,.29,.23),.42)
hairmat=material('hero_hair',(.05,.04,.035),.75)
browmat=material('hero_brow',(.05,.04,.035),.8)
lashmat=material('hero_lash',(.06,.045,.035),.8)
sclmat=material('hero_sclera',(.86,.84,.8),.2)
irismat=material('hero_iris',(.25,.15,.08),.2)
pupmat=material('hero_pupil',(.01,.01,.01),.1)
HAIR_STYLES=['buzz','crop','fade','curls','pixie','bob','ponytail','bun']
def make_hair(fid,style,pos,ecz,ecy):
    """One hairstyle on one face's scalp (see the FACES loop)."""
    long_=style=='bob'
    def margin(q):
        hl=.035 if style=='pixie' else .052   # forehead hairline above the eyes
        top=q.z-(ecz+hl)
        back=min(ecy-.085-q.y,q.z-(ecz-(.115 if long_ else .07)))
        if long_:
            temple=min(abs(q.x)-.055,ecy-.035-q.y,q.z-(ecz-.09))
        else:
            temple=min(abs(q.x)-.055,ecy-.03-q.y,q.z-(ecz+(-.012 if style=='pixie' else .012)))
        return max(top,back,temple)
    hf=[i for i in head_faces if any(margin(pos[j])>-.012 for j in bf[i])]
    hair,_=part('Hair_%s_%s'%(style,fid),hf,pos,weights)
    subdiv(hair,1)
    bm=bmesh.new();bm.from_mesh(hair.data)
    cuts=[((0,0,ecz+(.035 if style=='pixie' else .052)),(0,0,1)),((0,ecy-.085,0),(0,-1,0)),
          ((.055,0,0),(1,0,0)),((-.055,0,0),(-1,0,0))]
    if long_:cuts+=[((0,0,ecz-.115),(0,0,1)),((0,ecy-.035,0),(0,-1,0)),((0,0,ecz-.09),(0,0,1))]
    else:cuts+=[((0,0,ecz-.07),(0,0,1)),((0,ecy-.03,0),(0,-1,0)),((0,0,ecz+(-.012 if style=='pixie' else .012)),(0,0,1))]
    for co,no in cuts:
        bmesh.ops.bisect_plane(bm,geom=bm.verts[:]+bm.edges[:]+bm.faces[:],plane_co=co,plane_no=no)
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if margin(v.co)<-1e-5],context='VERTS')
    bm.normal_update()
    top=max(v.co.z for v in bm.verts)
    # The head's outline at eye height: the widest ring the bob falls from.
    hc=Vector((0,sum(v.co.y for v in bm.verts)/len(bm.verts),0))
    ring_r=[0.0]*48
    for j in {j for i in head_faces for j in bf[i]}:
        q=pos[j]
        if abs(q.z-(ecz+.01))<.03:
            d=Vector((q.x,q.y-hc.y,0));k=int((math.atan2(d.x,d.y)/math.tau+.5)*48)%48
            ring_r[k]=max(ring_r[k],d.length)
    for v in bm.verts:
        fadein=max(0.0,min(1.0,margin(v.co)/.01))
        fadein=fadein*fadein*(3-2*fadein)
        up=max(0.0,min(1.0,(v.co.z-(top-.08))/.06))   # 0 round the sides, 1 on top
        up_f=max(0.0,min(1.0,(v.co.z-(top-.055))/.03))   # the fade's top block starts higher, sharper
        lift={'buzz':.0024,'crop':.004+.015*up,'fade':.0017+.03*up_f**1.3,'curls':.009+.022*up,
              'pixie':.006+.012*up,'bob':.008+.008*up,'ponytail':.0035,'bun':.0035}[style]
        if style=='curls':
            p_=v.co*170.0
            lift+=.0045*(math.sin(p_.x)*math.sin(p_.y+1.3)*math.sin(p_.z+.7)+.4)
        if style=='pixie' and v.co.y>ecy-.04 and v.co.z<ecz+.07:
            lift+=.006   # the fringe stands off the forehead
        v.co+=v.normal*(.0006+lift*fadein)
        if long_ and v.co.z<ecz+.03:
            # Below the temples the bob hangs straight down from the head's
            # widest ring instead of following the jaw and neck in.
            d=Vector((v.co.x,v.co.y-hc.y,0))
            if d.length>1e-4:
                k=int((math.atan2(d.x,d.y)/math.tau+.5)*48)%48
                rr=max(ring_r[k],ring_r[(k+1)%48],ring_r[k-1])+.014
                t=max(0.0,min(1.0,(ecz+.03-v.co.z)/.05))
                want=max(d.length,d.length+(rr-d.length)*t)
                d2=d.normalized()*want
                v.co.x=d2.x;v.co.y=hc.y+d2.y
    bm.to_mesh(hair.data);bm.free();hair.data.update()
    so=hair.modifiers.new('Edge','SOLIDIFY');so.thickness=.002 if style!='bob' else .006;so.offset=-1;so.use_rim_only=style!='bob';apply(hair,so)
    hair.data.materials.append(hairmat)
    extras=[]
    if style in ('ponytail','bun'):
        vs=[v.co for v in hair.data.vertices]
        back=lambda z:min((q.y for q in vs if abs(q.z-z)<.008 and abs(q.x)<.02),default=hc.y-.09)
        if style=='bun':
            z=ecz+.07;c=Vector((0,back(z)-.022,z))
            bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=12,radius=.036,location=c)
            o_=bpy.context.object;o_.scale=(1.15,.9,.95)
            for p_ in o_.data.polygons:p_.use_smooth=True
            # wrapped look: faint rings across the bun
            for v in o_.data.vertices:v.co*=1+.06*math.sin(v.co.z*90)
            active(o_);bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
            extras.append(o_)
            tie_c=c+Vector((0,.026,-.004));tie_r=.03
        else:
            z=ecz+.05;yb=back(z)
            path=[Vector((0,yb+.006,z)),Vector((0,yb-.028,z-.012)),Vector((0,yb-.05,z-.06)),Vector((0,yb-.056,z-.13)),
                  Vector((0,yb-.05,z-.2)),Vector((0,yb-.036,z-.26))]
            rad=[.024,.03,.029,.024,.016,.005]
            bm2=bmesh.new();loops=[];segs=14
            for k,c in enumerate(path):
                t=(path[min(k+1,len(path)-1)]-path[max(k-1,0)]).normalized()
                f=Vector((1,0,0));sd=t.cross(f).normalized()
                loops.append([bm2.verts.new(c+f*math.cos(a)*rad[k]*1.05+sd*math.sin(a)*rad[k]*.85) for a in [i*math.tau/segs for i in range(segs)]])
            for r0,r1 in zip(loops,loops[1:]):
                for k in range(segs):bm2.faces.new((r0[k],r0[(k+1)%segs],r1[(k+1)%segs],r1[k]))
            bm2.faces.new(loops[0]);bm2.faces.new(list(reversed(loops[-1])))
            bmesh.ops.recalc_face_normals(bm2,faces=bm2.faces)
            me=bpy.data.meshes.new('tail');bm2.to_mesh(me);bm2.free()
            o_=bpy.data.objects.new('tail',me);bpy.context.collection.objects.link(o_)
            for p_ in o_.data.polygons:p_.use_smooth=True
            extras.append(o_);tie_c=path[0]+Vector((0,-.012,-.004));tie_r=.021
        bpy.ops.mesh.primitive_torus_add(major_radius=tie_r,minor_radius=.0045,major_segments=20,minor_segments=6,location=tie_c,rotation=(math.pi/2-.5,0,0))
        tie=bpy.context.object;active(tie);bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
        tie.data.materials.append(material('hero_hair_tie',(.03,.03,.035),.5))
        for o_ in extras:o_.data.materials.append(hairmat)
        extras.append(tie)
        uvl=hair.data.uv_layers.active
        if uvl is not None:
            for o_ in extras:
                while len(o_.data.uv_layers)<len(hair.data.uv_layers):o_.data.uv_layers.new()
                for k_,L in enumerate(hair.data.uv_layers):
                    o_.data.uv_layers[k_].name=L.name
                    src=L.data[hair.data.polygons[0].loop_indices[0]].uv.copy()
                    # A tiny patch round that UV, laid out from position:
                    # one flat UV would leave no tangents for the normal map
                    # (NaN normals = black speckles).
                    for poly in o_.data.polygons:
                        for li in poly.loop_indices:
                            co=o_.data.vertices[o_.data.loops[li].vertex_index].co
                            o_.data.uv_layers[k_].data[li].uv=(src.x+(co.x+.6*co.y)*.04,src.y+co.z*.04)
        for o_ in extras:
            vg=o_.vertex_groups.new(name='b_head');vg.add(list(range(len(o_.data.vertices))),1,'REPLACE')
        bpy.ops.object.select_all(action='DESELECT')
        for o_ in extras:o_.select_set(True)
        hair.select_set(True);bpy.context.view_layer.objects.active=hair;bpy.ops.object.join()
    return hair
canon=None
for fid,eth,tg,style in FACES:
    fb=face_base(eth,tg)
    pos=[retarget(fb[j],weights[j]) for j in range(len(fb))]
    face,ids=part('Face_'+fid,head_faces,pos,weights)
    face.data.materials.append(skinmat);face.data.materials.append(lipmat)
    # Lips: around the mouth, in front of the tongue.
    tongue=[pos[j] for i in GROUP_FACES['helper-tongue'] for j in bf[i]]
    mc=sum(tongue,Vector())/len(tongue)
    for poly in face.data.polygons:
        c=poly.center
        if ((c.x/.025)**2+((c.z-mc.z)/.0095)**2)<1 and c.y>mc.y+.014:poly.material_index=1
    if canon is None:canon=(fb,pos,mc)
    parts_=[face]
    # Eyes: the helper spheres, subdivided, iris and pupil by angle from forward.
    for side in ['l','r']:
        ef=GROUP_FACES['helper-%s-eye'%side]
        eye,eids=part('Eye_%s_%s'%(side,fid),ef,pos,weights)
        subdiv(eye,1)
        for m_ in [sclmat,irismat,pupmat]:eye.data.materials.append(m_)
        c=sum((v.co for v in eye.data.vertices),Vector())/len(eye.data.vertices)
        for poly in eye.data.polygons:
            d=(poly.center-c).normalized();k=d.y
            poly.material_index=2 if k>.93 else (1 if k>.78 else 0)
        parts_.append(eye)
        lf=GROUP_FACES['helper-%s-eyelashes-1'%side]+GROUP_FACES['helper-%s-eyelashes-2'%side]
        lash,_=part('Lash_%s_%s'%(side,fid),lf,pos,weights);lash.data.materials.append(lashmat);parts_.append(lash)
    # Brows: a tapered strip laid on the brow ridge above each eye.
    tree=BVHTree.FromPolygons([v.co for v in face.data.vertices],[list(p.vertices) for p in face.data.polygons])
    for side,sx in [('l',-1),('r',1)]:
        ev=[pos[j] for i in GROUP_FACES['helper-%s-eye'%side] for j in bf[i]]
        ec=sum(ev,Vector())/len(ev)
        pts=[];widths=[]
        for k in range(7):
            u=k/6.0
            x=ec.x+sx*(-.016+u*.044)
            z=ec.z+.019+math.sin(u*math.pi)*.006-u*.004
            hit=tree.ray_cast(Vector((x,1,z)),Vector((0,-1,0)))
            y=(hit[0].y if hit[0] is not None else ec.y+.012)+.0008
            pts.append(Vector((x,y,z)));widths.append(.0058*(1-.6*u)+.0012)
        vs=[];fs=[]
        for k,p_ in enumerate(pts):vs.extend([p_+Vector((0,0,-widths[k]/2)),p_+Vector((0,0,widths[k]/2))])
        for k in range(6):fs.append([2*k,2*k+2,2*k+3,2*k+1] if sx>0 else [2*k,2*k+1,2*k+3,2*k+2])
        brow=mesh('Brow_%s_%s'%(side,fid),vs,[],fs,[]);brow.data.materials.append(browmat)
        vg=brow.vertex_groups.new(name='b_head');vg.add(list(range(len(vs))),1,'REPLACE');parts_.append(brow)
    # Hair: cut from the scalp itself above a hairline and lifted off it,
    # one mesh per style per face (so each fits its own head). Styles:
    #   buzz/crop/fade/curls  short cuts, different volume on top
    #   pixie                 a soft crop with a fringe and sideburns
    #   bob                   a curtain that falls straight to the jaw
    #   ponytail/bun          tight on the scalp, gathered at the back
    # (MakeHuman's hair helper is long draped cards, not a cap.)
    ev2=[pos[j] for i in GROUP_FACES['helper-l-eye']+GROUP_FACES['helper-r-eye'] for j in bf[i]]
    ecz=sum((v.z for v in ev2))/len(ev2);ecy=sum((v.y for v in ev2))/len(ev2)
    hair_meshes=[make_hair(fid,style_,pos,ecz,ecy) for style_ in HAIR_STYLES]
    # One object per face (skin, lips, eyes, lashes, brows); hair apart.
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts_:o.select_set(True)
    bpy.context.view_layer.objects.active=face;bpy.ops.object.join()
    face_meshes[fid]=[face]+hair_meshes

# ------------------------------------------------------------------ masks
# Fitted to the canonical (first) face, 9-12 mm off it so every face fits.
fb,cpos,mouth=canon
head_ids=sorted({j for i in head_faces for j in bf[i]})
le=[cpos[j] for i in GROUP_FACES['helper-l-eye'] for j in bf[i]];re_=[cpos[j] for i in GROUP_FACES['helper-r-eye'] for j in bf[i]]
eye_l=sum(le,Vector())/len(le);eye_r=sum(re_,Vector())/len(re_);eye_z=(eye_l.z+eye_r.z)/2
masks=[]
def hull_mask(name,pts,offset,cut=None,mat=None,planes=()):
    hc=sum(pts,Vector())/len(pts)
    bm=bmesh.new()
    for p_ in pts:bm.verts.new(p_+(p_-Vector((0,hc.y-.02,p_.z if False else hc.z))).normalized()*0)
    bmesh.ops.convex_hull(bm,input=bm.verts[:],use_existing_faces=False)
    bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
    # Subdivide first so cut edges are fine, then cut exactly on the planes.
    bmesh.ops.subdivide_edges(bm,edges=bm.edges[:],cuts=1,use_grid_fill=True)
    for co,no in planes:
        bmesh.ops.bisect_plane(bm,geom=bm.verts[:]+bm.edges[:]+bm.faces[:],plane_co=co,plane_no=no)
    if cut:
        bmesh.ops.delete(bm,geom=[f for f in bm.faces if cut(f.calc_center_median(),f.normal)],context='FACES')
    me=bpy.data.meshes.new(name);bm.to_mesh(me);bm.free()
    ob=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(ob)
    push(ob,offset)
    for p_ in ob.data.polygons:p_.use_smooth=True
    active(ob);bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(island_margin=.02);bpy.ops.object.mode_set(mode='OBJECT')
    so=ob.modifiers.new('Edge','SOLIDIFY');so.thickness=.0025;so.offset=-1;so.use_rim_only=True;apply(ob,so)
    vh=ob.vertex_groups.new(name='b_head');vn=ob.vertex_groups.new(name='b_neck')
    for v in ob.data.vertices:
        w=max(0,min(1,(v.co.z-1.57)/.09));vh.add([v.index],w,'REPLACE');vn.add([v.index],1-w,'REPLACE')
    ob.data.materials.append(mat);masks.append(ob);return ob
headpts=[cpos[j] for j in head_ids]
# Courier: the signature full mask (textile envelope) and smoked lens.
cour=[]
for q in headpts:
    q=q.copy()
    if q.y>.13:q.y=.13
    q.z-=.018
    if q.z<1.65:
        q.x*=.55+.45*max(0,(q.z-1.54)/.11)
        q.z-=max(0,(1.62-q.z))*.32
    cour.append(q)
hull_mask('Mask_courier',cour,.004,None,material('hero_mask_courier',(.018,.022,.027),.8))
mtree_ob=masks[-1]
mtree=BVHTree.FromPolygons([v.co for v in mtree_ob.data.vertices],[list(p.vertices) for p in mtree_ob.data.polygons])
vs=[]
for row in range(3):
    for col in range(9):
        x=-.076+col*.019
        z=eye_z+(row-1)*.014-abs(x)*.075
        hit=mtree.ray_cast(Vector((x,1,z)),Vector((0,-1,0)))
        y=(hit[0].y if hit[0] is not None else .12)+.002
        vs.append((x,y,z))
fs=[[r*9+c,r*9+c+9,r*9+c+10,r*9+c+1] for r in range(2) for c in range(8)]
lens=mesh('Mask_courier_lens',vs,[],fs,[]);lens.data.materials.append(material('hero_lens',(.008,.013,.017),.24))
vg=lens.vertex_groups.new(name='b_head');vg.add(list(range(len(vs))),1,'REPLACE');masks.append(lens)
# Runner: a gaiter pulled up over the nose (lower face and neck).
lower=[p_ for p_ in headpts if p_.z<eye_z-.014]
hull_mask('Mask_runner',lower,.007,lambda c,n:c.z>eye_z-.016,material('hero_mask_runner',(.06,.065,.075),.85),
    [((0,0,eye_z-.016),(0,0,1))])
# Bandana: a square scarf tied over the nose, its point hanging below the
# chin. Fitted round the face like the gaiter (so no lips or nose poke
# through on any face), plus the drape's point in front of the throat.
chin_z=mouth.z-.042   # the chin's underside, from the mouth (the head mesh runs on down the neck)
band=[p_ for p_ in headpts if chin_z<p_.z<eye_z-.02]
front=max(p_.y for p_ in band)
band+=[Vector((0,front-.012,chin_z-.05)),Vector((-.028,front-.03,chin_z-.026)),Vector((.028,front-.03,chin_z-.026))]
hull_mask('Mask_bandana',band,.008,lambda c,n:c.z>eye_z-.022 or (n.y<-.3 and c.z<chin_z+.01),material('hero_bandana',(.6,.1,.09),.85),
    [((0,0,eye_z-.022),(0,0,1))])
kn=[]
for k,(d,r) in enumerate([((0,-.012,0),.017),((-.016,-.03,-.03),.009),((.012,-.034,-.045),.009)]):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=10,ring_count=7,radius=r,location=Vector((0,min(p_.y for p_ in band)-.002,eye_z-.03))+Vector(d))
    o_=bpy.context.object;o_.scale=(1.1,.75,1.4 if k else 1.0);active(o_);bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    kn.append(o_)
bpy.ops.object.select_all(action='DESELECT')
for o_ in kn:o_.select_set(True)
bpy.context.view_layer.objects.active=kn[0];bpy.ops.object.join();knot=kn[0];knot.name='Mask_bandana_knot'
for p_ in knot.data.polygons:p_.use_smooth=True
knot.data.materials.append(material('hero_bandana_knot',(.6,.1,.09),.85))
vg=knot.vertex_groups.new(name='b_head');vg.add(list(range(len(knot.data.vertices))),1,'REPLACE');masks.append(knot)
# Balaclava: the whole head with an eye window.
hull_mask('Mask_balaclava',headpts,.008,lambda c,n:abs(c.x)<.07 and abs(c.z-eye_z)<.016 and n.y>.4,material('hero_mask_balaclava',(.03,.03,.035),.9),
    [((0,0,eye_z+.016),(0,0,1)),((0,0,eye_z-.016),(0,0,1)),((.07,0,0),(1,0,0)),((-.07,0,0),(1,0,0))])
# Domino: a thin band laid on the face round the eyes, with round eye holes.
dom_faces=[i for i in head_faces if all(abs(cpos[j].z-eye_z)<.024 and cpos[j].y>eye_l.y-.04 for j in bf[i])]
dom,_=part('Mask_domino',dom_faces,cpos,weights)
subdiv(dom,1)
bm=bmesh.new();bm.from_mesh(dom.data)
bmesh.ops.delete(bm,geom=[v for v in bm.verts if (Vector((v.co.x,0,v.co.z))-Vector((eye_l.x,0,eye_l.z))).length<.0145
    or (Vector((v.co.x,0,v.co.z))-Vector((eye_r.x,0,eye_r.z))).length<.0145],context='VERTS')
bm.normal_update()
for v in bm.verts:v.co+=v.normal*.0035
bm.to_mesh(dom.data);bm.free()
for v in dom.data.vertices:
    for g in list(v.groups):pass
so=dom.modifiers.new('Edge','SOLIDIFY');so.thickness=.002;so.offset=-1;apply(dom,so)
for p_ in dom.data.polygons:p_.use_smooth=True
active(dom);bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(island_margin=.02);bpy.ops.object.mode_set(mode='OBJECT')
dom.data.materials.append(material('hero_mask_domino',(.02,.02,.025),.4));masks.append(dom)
# Respirator: a moulded shell over mouth and nose, two filters.
resp=[p_ for p_ in headpts if p_.z<eye_z-.022 and p_.z>mouth.z-.05 and p_.y>mouth.y-.045]
rm_=hull_mask('Mask_respirator',resp,.012,lambda c,n:n.y<-.1,material('hero_mask_respirator',(.12,.125,.13),.4))
fmat=material('hero_mask_filter',(.85,.42,.08),.5)
for sx in [-1,1]:
    c=Vector((sx*.045,mouth.y+.02,mouth.z-.004))
    bpy.ops.mesh.primitive_cylinder_add(vertices=14,radius=.019,depth=.022,location=c,rotation=(math.pi/2,0,sx*.55))
    f_=bpy.context.object;f_.name='Mask_respirator_filter_'+('l' if sx<0 else 'r')
    f_.data.materials.append(fmat)
    vg=f_.vertex_groups.new(name='b_head');vg.add(list(range(len(f_.data.vertices))),1,'REPLACE')
    active(f_);bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    masks.append(f_)

all_meshes=[top_long,top_tq,top_short,top_vest,collar]+skin_arms+[pants,shoes,gloves]+[o for ps in face_meshes.values() for o in ps]+masks
for ob in [pants]:
    solid=ob.modifiers.new('Bound cloth edges','SOLIDIFY');solid.thickness=.0025;solid.offset=-1;solid.use_rim_only=True;apply(ob,solid)

pocketmat=material('hero_cargo_pocket',(.034,.04,.046),.85)
def pocket(side):
    sx=-1 if side=='l' else 1
    vs=[]
    tree=BVHTree.FromPolygons([v.co for v in pants.data.vertices],[list(p.vertices) for p in pants.data.polygons])
    for r in range(5):
        z=.78-r*.038
        for c in range(5):
            y=-.055+c*.034
            hit=tree.ray_cast(Vector((sx,y,z)),Vector((-sx,0,0)))
            edge=hit[0].x if hit[0] is not None else sx*.19
            x=edge+sx*(.004+.014*math.sin(math.pi*c/4)*math.sin(math.pi*r/4))
            vs.append((x,y,z))
    fs=[]
    for r in range(4):
        for c in range(4):
            a=r*5+c;fs.append([a,a+1,a+6,a+5] if sx<0 else [a+5,a+6,a+1,a])
    ob=mesh('Cargo_gusset_'+side,vs,[],fs,[]);vg=ob.vertex_groups.new(name='b_thigh_'+side);vg.add(list(range(25)),1,'REPLACE');subdiv(ob,1)
    so=ob.modifiers.new('Pocket welt','SOLIDIFY');so.thickness=.003;apply(ob,so);ob.data.materials.append(pocketmat);all_meshes.append(ob)
for s in ['l','r']:pocket(s)

# Rig: same rest joints and names as CharacterRig; gameplay animation remains
# the source of truth. Four normalized influences per vertex, no bone heat.
arm=bpy.data.armatures.new('CourierSkeleton');rig=bpy.data.objects.new('CourierRig',arm);bpy.context.collection.objects.link(rig);active(rig);bpy.ops.object.mode_set(mode='EDIT')
for n in names:
    b=arm.edit_bones.new('b_'+n);b.head=J[n]
    children=[c for c,p in P.items() if p==n]
    if n.startswith('hand'):b.tail=J[n]+(J[n]-J[P[n]]).normalized()*.12
    elif n.startswith('foot'):b.tail=J[n]+Vector((0,.16,0))
    elif children:b.tail=J[children[0]]
    else:b.tail=J[n]+Vector((0,0,.15))
    if (b.tail-b.head).length<.02:b.tail=b.head+Vector((0,0,.06))
    if P[n]:b.parent=arm.edit_bones['b_'+P[n]]
bpy.ops.object.mode_set(mode='OBJECT')
for ob in all_meshes:
    active(ob)
    bpy.ops.object.vertex_group_limit_total(limit=4)
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    mod=ob.modifiers.new('Gameplay skin','ARMATURE');mod.object=rig;ob.parent=rig
    # UV2.x is the cloth freedom mask, UV2.y reserved. Imported PBR keeps UV1.
    uv2=ob.data.uv_layers.new(name='ClothFreedom')
    for face in ob.data.polygons:
        for li in face.loop_indices:
            p=ob.data.vertices[ob.data.loops[li].vertex_index].co
            freedom=0
            if ob in tops and abs(p.x)<.24:freedom=max(0,min(.06,(1.0-p.z)*1.2))
            sole=1-max(0,min(1,(p.z-.027)/.012)) if ob==shoes else 0
            uv2.data[li].uv=(freedom,sole)
    # Some authored meshes have no UVs (signature/pockets); unwrap those.
    if len(ob.data.uv_layers)==1:
        ob.data.uv_layers.new(name='SurfaceUV');ob.data.uv_layers.active_index=1
        bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(island_margin=.03);bpy.ops.object.mode_set(mode='OBJECT')
        # Export ordering must remain SurfaceUV then ClothFreedom.
        cloth=[tuple(d.uv) for d in ob.data.uv_layers[0].data];surface=[tuple(d.uv) for d in ob.data.uv_layers[1].data]
        for i,d in enumerate(ob.data.uv_layers[0].data):d.uv=surface[i]
        for i,d in enumerate(ob.data.uv_layers[1].data):d.uv=cloth[i]
    ob.data.uv_layers[0].name='SurfaceUV';ob.data.uv_layers[1].name='ClothFreedom'
    ob.data.uv_layers.active_index=0

# Bake per-garment ambient occlusion into actual UV textures. The source normal
# map is retained; the procedural microfabric is baked, never evaluated per pixel.
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=12;scene.cycles.bake_type='AO'
scene.render.bake.margin=8
BAKE=[top_long,pants,shoes,gloves,face_meshes['kai'][0]]+[m_ for m_ in masks if m_.name in ('Mask_courier','Mask_runner','Mask_balaclava','Mask_domino','Mask_respirator')]
for ob in BAKE:
    size=1024 if ob in (top_long,pants,shoes,gloves) else 512
    active(ob);mat=ob.data.materials[0];nodes=mat.node_tree.nodes
    im=bpy.data.images.new(ob.name+'_ao',size,size,alpha=False);im.colorspace_settings.name='Non-Color'
    target=nodes.new('ShaderNodeTexImage');target.image=im;nodes.active=target
    # All other objects are hidden from baking: avoid frozen limb shadows.
    for other in all_meshes:other.hide_render=other!=ob
    bpy.ops.object.bake(type='AO')
    data=np.empty(size*size*4,dtype=np.float32);im.pixels.foreach_get(data);pixels=data.reshape(-1,4)
    # Packed ORM: occlusion red, roughness green, metallic blue.
    rough=float(nodes['Principled BSDF'].inputs['Roughness'].default_value)
    rng=np.random.default_rng(42)
    pixels[:,1]=np.clip(rough+rng.normal(0,.008,len(pixels)),0,1);pixels[:,2]=0;pixels[:,3]=1
    im.pixels.foreach_set(data)
    im.filepath_raw=str(TEX/(mat.name+'_orm.png'));im.file_format='PNG';im.save()
    separate=nodes.new('ShaderNodeSeparateColor');mat.node_tree.links.new(target.outputs['Color'],separate.inputs[0])
    mat.node_tree.links.new(separate.outputs['Green'],nodes['Principled BSDF'].inputs['Roughness'])
    # glTF's dedicated occlusion socket preserves AO without baking it into albedo.
    group=bpy.data.node_groups.get('glTF Material Output')
    if not group:
        group=bpy.data.node_groups.new('glTF Material Output','ShaderNodeTree');group.interface.new_socket(name='Occlusion',in_out='INPUT',socket_type='NodeSocketFloat')
    g=nodes.new('ShaderNodeGroup');g.node_tree=group;mat.node_tree.links.new(target.outputs['Color'],g.inputs['Occlusion'])
for ob in all_meshes:ob.hide_render=False
# Retain editable meshes, original garment UVs, weights and material nodes.
for im in bpy.data.images:
    if im.source=='FILE':im.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/hero/courier.blend'),compress=True)
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
for ob in all_meshes:ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT/'character.glb'),export_format='GLB',use_selection=True,export_apply=False,export_yup=True,export_materials='EXPORT',export_skins=True,export_animations=False)
triangles=sum(sum(len(p.vertices)-2 for p in ob.data.polygons) for ob in all_meshes)
(ROOT/'art/hero/build_report.json').write_text(json.dumps({'triangles':triangles,'meshes':{o.name:len(o.data.vertices) for o in all_meshes},'bones':len(names),'max_influences':4},indent=2))
print('COURIER EXPORTED',triangles,'triangles',flush=True)
