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

jacket=garment('elvs_hooded_sweat_jacket1','Courier_Jacket')
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

# The jacket's source is fitted women's clothing. The male morph provides the
# anatomy; straighten the waist into a relaxed shell instead of a pinched waist.
for v in jacket.data.vertices:
    p=v.co
    if .95<p.z<1.43 and abs(p.x)<.24:
        u=(p.z-.95)/.48
        p.x*=1.07+.08*math.sin(u*math.pi)
        p.y*=1.08
    if 1.20<p.z<1.51 and p.y>.10 and abs(p.x)<.20:
        strength=math.sin(math.pi*(p.z-1.20)/.31)**.5
        p.y-=max(0,p.y-.135)*strength*.92
    if p.z>1.52 and abs(p.x)>.13:
        p.x*=.90
        p.z-=.018
# Add enough topology for knee/elbow deformation without a remesher.
subdiv(pants,2)
subdiv(shoes,1)
m=shoes.modifiers.new("Trainer mobile topology","DECIMATE");m.ratio=.55;apply(shoes,m)
# Shoes are modelled for a taller ankle; align their sole to the gameplay foot plane.
for v in shoes.data.vertices:
    n='foot_l' if v.co.x<0 else 'foot_r';ank=J[n]
    v.co.z+=.035
# Tuck the trouser opening into the trainer collar, retaining authored bunching.
for v in pants.data.vertices:
    if v.co.z<.23:
        n='foot_l' if v.co.x<0 else 'foot_r';ank=J[n]
        t=max(0,min(1,(.23-v.co.z)/.20));v.co.x=ank.x+(v.co.x-ank.x)*(1-.28*t)
        v.co.y*=1-.18*t
        v.co.z+=.075*t

jp=SRC/'elvs_hooded_sweat_jacket1'
jtex=recolor_texture(jp/'hoodietex1.png','jacket_albedo',(.19,.205,.225))
jmat=material('hero_jacket',(.04,.045,.05),.78,jtex,jp/'normalshoodie.png')
ptex=recolor_texture(SRC/'cortu_cargo_pants'/'cargo_pants_diff.png','cargo_albedo',(.21,.225,.24)) if (SRC/'cortu_cargo_pants'/'cargo_pants_diff.png').exists() else None
pmat=material('hero_cargo',(.046,.051,.054),.86,ptex,SRC/'cortu_cargo_pants'/'cargo_pants_norm.png')
stex=recolor_texture(SRC/'punkduck_running_shoes_01'/'runningshoes.png','trainer_albedo',(.94,.95,.96),True)
smat=material('hero_trainer',(.8,.8,.8),.55,stex)
gmat=material('hero_glove',(.023,.026,.029),.58)
for ob,mat in [(jacket,jmat),(pants,pmat),(shoes,smat),(gloves,gmat)]:ob.data.materials.clear();ob.data.materials.append(mat)

# Full-cover mask: retain the authored anatomical skull and jaw, bridge the
# facial surface with cloth. Face is opaque; there are no eyes, lips or skin.
bv,bu,bf,bfu,bg=obj_read(SRC/'base.obj')
keep=[]
for i,f in enumerate(bf):
    if bg[i]=='body' and min(base[j,1] for j in f)>6.35:keep.append(i)
ids=sorted({j for i in keep for j in bf[i]});remap={j:i for i,j in enumerate(ids)}
vs=[]
for i in ids:
    p=torso(base[i]);
    # Mouth/eye/nose relief is flattened into a single textile face panel.
    if p.y>.13:
        p.y=.13
    p.z-=.018
    if p.z<1.65:
        p.x*=.55+.45*max(0,(p.z-1.54)/.11)
        p.z-=max(0,(1.62-p.z))*.32
    vs.append(p)
mask=mesh('Courier_Mask',vs,bu,[[remap[j] for j in bf[i]] for i in keep],[bfu[i] for i in keep])
# A convex textile envelope removes facial openings and internal mouth/eye
# topology while retaining the authored cranium, jaw and neck proportions.
bm=bmesh.new()
for v in vs:bm.verts.new(v)
bmesh.ops.convex_hull(bm,input=bm.verts[:],use_existing_faces=False)
bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
bm.to_mesh(mask.data);bm.free()
subdiv(mask,1)
for f in mask.data.polygons:f.use_smooth=True
# New cloth envelope gets its own packed UVs.
active(mask);bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(island_margin=.02);bpy.ops.object.mode_set(mode='OBJECT')
vh=mask.vertex_groups.new(name='b_head');vn=mask.vertex_groups.new(name='b_neck')
for v in mask.data.vertices:
    w=max(0,min(1,(v.co.z-1.57)/.09))
    vh.add([v.index],w,'REPLACE');vn.add([v.index],1-w,'REPLACE')
mask.data.materials.append(material('hero_mask',(.018,.022,.027),.8))
# Neck gaiter uses the lower mask and extends below the jacket opening.

all_meshes=[jacket,pants,shoes,gloves,mask]
# Authored anatomical torso underlayer fills the open zip/collar naturally.
lin_faces=[i for i,f in enumerate(bf) if bg[i]=='body' and
           all(3.6<base[j,1]<6.65 and abs(base[j,0])<1.9 for j in f)]
lin_ids=sorted({j for i in lin_faces for j in bf[i]});lin_map={v:i for i,v in enumerate(lin_ids)}
lin_vs=[retarget(base[j],weights[j]) for j in lin_ids]
liner=mesh('Technical_underlayer',lin_vs,bu,[[lin_map[j] for j in reversed(bf[i])] for i in lin_faces],[list(reversed(bfu[i])) for i in lin_faces])
liner.data.materials.append(mask.data.materials[0])
for n,index in ni.items():
    vg=liner.vertex_groups.new(name='b_'+n)
    for k,j in enumerate(lin_ids):
        if weights[j,index]>.001:vg.add([k],float(weights[j,index]),'REPLACE')
all_meshes.append(liner)
# A continuous smoked lens covers the eye region; no exposed eyes or face.
# It is fitted to the textile skull, without a protruding helmet shell.
tree=BVHTree.FromPolygons([v.co for v in mask.data.vertices],[list(p.vertices) for p in mask.data.polygons])
vs=[]
for row in range(3):
    for col in range(9):
        x=-.076+col*.019
        z=1.735+(row-1)*.014-abs(x)*.075
        hit=tree.ray_cast(Vector((x,1,z)),Vector((0,-1,0)))
        y=(hit[0].y if hit[0] is not None else .11)+.002
        vs.append((x,y,z))
fs=[]
for r in range(2):
    for c in range(8):
        a=r*9+c;fs.append([a,a+9,a+10,a+1])
visor=mesh('Opaque_smoked_lens',vs,[],fs,[])
visor.data.materials.append(material('hero_lens',(.008,.013,.017),.24))
vg=visor.vertex_groups.new(name='b_head');vg.add(list(range(len(vs))),1,'REPLACE');all_meshes.append(visor)

# Garment thickness is restrained; authored UV islands remain intact.
for ob in [jacket,pants]:
    solid=ob.modifiers.new('Bound cloth edges','SOLIDIFY');solid.thickness=.0025;solid.offset=-1;solid.use_rim_only=True;apply(ob,solid)

# Pocket panels are cut and sewn surfaces following the thigh, with a gusset
# and an overlapping flap. They are not boxes attached to the body.
pocketmat=material('hero_cargo_pocket',(.034,.04,.046),.85)
def pocket(side):
    sx=-1 if side=='l' else 1;hip=J['thigh_'+side];knee=J['shin_'+side]
    vs=[]
    tree=BVHTree.FromPolygons([v.co for v in pants.data.vertices],[list(p.vertices) for p in pants.data.polygons])
    # 5 x 5 curved grid, lower corners inset and softly rounded by subdivision.
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

# A narrow yellow woven pull and a small rear chevron establish the signature.
yellow=material('hero_signature',(.70,.43,.025),.65)
def ribbon(name,pts,width,bone):
    tree=BVHTree.FromPolygons([v.co for v in jacket.data.vertices],[list(p.vertices) for p in jacket.data.polygons])
    front=pts[0][1]>0
    fitted=[]
    for x,y,z in pts:
        hit=tree.ray_cast(Vector((x,1 if front else -1,z)),Vector((0,-1 if front else 1,0)))
        if hit[0] is not None:y=hit[0].y+(.003 if front else -.003)
        fitted.append((x,y,z))
    pts=fitted
    vs=[]
    for p in pts:vs.extend([Vector(p)+Vector((-width/2,0,0)),Vector(p)+Vector((width/2,0,0))])
    fs=[[2*i,2*i+1,2*i+3,2*i+2] for i in range(len(pts)-1)]
    if not front:fs=[list(reversed(f)) for f in fs]
    ob=mesh(name,vs,[],fs,[]);ob.data.materials.append(yellow);vg=ob.vertex_groups.new(name='b_'+bone);vg.add(list(range(len(vs))),1,'REPLACE');all_meshes.append(ob)
ribbon('Woven_zip_pull',[(.018,.145,1.40),(.018,.153,1.37),(.022,.155,1.335)],.009,'chest')
# Sewn rear mark follows the back panel instead of floating armour plates.
for sx in [-1,1]:
    ribbon('Rear_signature',[(sx*.065,-.119,1.34),(sx*.032,-.129,1.30),(0,-.133,1.26)],.012,'chest')

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
            if ob==jacket and abs(p.x)<.24:freedom=max(0,min(.28,(1.18-p.z)*1.4))
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
for ob in [jacket,pants,shoes,gloves,mask]:
    active(ob);mat=ob.data.materials[0];nodes=mat.node_tree.nodes
    im=bpy.data.images.new(ob.name+'_ao',1024,1024,alpha=False);im.colorspace_settings.name='Non-Color'
    target=nodes.new('ShaderNodeTexImage');target.image=im;nodes.active=target
    # All other objects are hidden from baking: avoid frozen limb shadows.
    for other in all_meshes:other.hide_render=other!=ob
    bpy.ops.object.bake(type='AO')
    data=np.empty(1024*1024*4,dtype=np.float32);im.pixels.foreach_get(data);pixels=data.reshape(-1,4)
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
