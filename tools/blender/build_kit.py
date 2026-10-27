"""Procedural asset kit for City Swing.

Run:  blender -b --factory-startup --python tools/blender/build_kit.py -- <out_dir>

Every model is built from code (bmesh + modifiers, no hand modelling) and
exported as its own GLB. Conventions:
  * Blender Z-up / +Y forward  ->  glTF/Godot Y-up / -Z forward.
  * Material names are stable; Godot keys off a few of them ("lamp", "glass",
    "paint") to swap in shared runtime materials.
  * Origins sit where Godot places the piece (base centre, or joint pivot for
    character parts).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "assets/models"
os.makedirs(OUT, exist_ok=True)

# ---------------------------------------------------------------- helpers
_mats = {}


def mat(name, rgb, rough=0.7, metal=0.0, emit=None):
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 3.0
    _mats[name] = m
    return m


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()


def new_obj(name, bm, material=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if material:
        me.materials.append(material)
    return ob


def box(name, size, loc=(0, 0, 0), material=None, bevel=0.0, segs=2):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(loc), verts=bm.verts)
    ob = new_obj(name, bm, material)
    if bevel > 0:
        mod = ob.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segs
        mod.limit_method = "ANGLE"
    return ob


def cyl(name, r, h, loc=(0, 0, 0), material=None, verts=16, r2=None, cap=True):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=verts,
                          radius1=r, radius2=r if r2 is None else r2, depth=h)
    bmesh.ops.translate(bm, vec=Vector(loc) + Vector((0, 0, h / 2)), verts=bm.verts)
    return new_obj(name, bm, material)


def sphere(name, r, loc=(0, 0, 0), material=None, segs=16, rings=10, scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
    bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(loc), verts=bm.verts)
    return new_obj(name, bm, material)


def dome(name, r, loc=(0, 0, 0), material=None, segs=16, rings=6, height=1.0):
    """Upper hemisphere, flattened/raised by `height`."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings * 2, radius=r)
    for v in [v for v in bm.verts if v.co.z < -1e-4]:
        bm.verts.remove(v)
    bmesh.ops.scale(bm, vec=Vector((1, 1, height)), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(loc), verts=bm.verts)
    return new_obj(name, bm, material)


def smooth(ob, level=1, shade=True):
    mod = ob.modifiers.new("sub", "SUBSURF")
    mod.levels = level
    mod.render_levels = level
    if shade:
        for p in ob.data.polygons:
            p.use_smooth = True
    return ob


def join(name, objs, origin=(0, 0, 0)):
    objs = [o for o in objs if o is not None]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.convert(target="MESH")  # apply modifiers
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    bpy.context.scene.cursor.location = origin
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    return ob


def export(filename, objs=None):
    bpy.ops.object.select_all(action="DESELECT")
    targets = objs or [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in targets:
        o.select_set(True)
    path = os.path.join(OUT, filename)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True, export_materials="EXPORT")
    tris = sum(len(o.data.polygons) for o in targets)
    print(f"KIT {filename}: {len(targets)} objects, ~{tris} faces")


# ---------------------------------------------------------------- props
def water_tower():
    reset()
    wood = mat("timber", (0.42, 0.27, 0.17), 0.85)
    steel = mat("steel_dark", (0.16, 0.16, 0.17), 0.5, 0.6)
    roofm = mat("roof_metal", (0.25, 0.3, 0.32), 0.45, 0.5)
    parts = [cyl("tank", 2.3, 4.2, (0, 0, 3.2), wood, 20)]
    for i in range(5):
        parts.append(cyl(f"hoop{i}", 2.36, 0.12, (0, 0, 3.5 + i * 0.85), steel, 20))
    parts.append(cyl("cap", 2.5, 1.6, (0, 0, 7.4), roofm, 20, r2=0.15))
    for sx, sy in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
        leg = cyl("leg", 0.12, 3.3, (sx * 1.5, sy * 1.5, 0), steel, 6)
        parts.append(leg)
    parts.append(box("deck", (3.8, 3.8, 0.15), (0, 0, 3.15), steel))
    parts.append(box("xb1", (3.2, 0.06, 0.06), (0, 1.5, 1.6), steel))
    parts.append(box("xb2", (3.2, 0.06, 0.06), (0, -1.5, 1.6), steel))
    export("water_tower.glb", [join("water_tower", parts)])


def ac_unit():
    reset()
    body = mat("hvac", (0.72, 0.73, 0.72), 0.5, 0.2)
    dark = mat("steel_dark", (0.12, 0.12, 0.13), 0.5, 0.5)
    parts = [box("b", (3.0, 2.0, 1.4), (0, 0, 0.7), body, bevel=0.05)]
    for x in (-0.75, 0.75):
        parts.append(cyl("fan", 0.6, 0.06, (x, 0, 1.4), dark, 16))
    export("ac_unit.glb", [join("ac_unit", parts)])


def antenna():
    reset()
    steel = mat("steel_light", (0.7, 0.7, 0.72), 0.4, 0.7)
    red = mat("lamp_red", (0.9, 0.1, 0.05), 0.4, 0.0, emit=(1.0, 0.1, 0.05))
    parts = [cyl("mast", 0.18, 14, (0, 0, 0), steel, 8, r2=0.06)]
    for i in range(4):
        parts.append(box("arm", (2.2 - i * 0.4, 0.06, 0.06), (0, 0, 3 + i * 2.8), steel))
    parts.append(sphere("beacon", 0.22, (0, 0, 14.1), red, 8, 6))
    export("antenna.glb", [join("antenna", parts)])


def streetlight():
    reset()
    pole = mat("lamp_post", (0.13, 0.15, 0.16), 0.45, 0.6)
    lamp = mat("lamp", (1.0, 0.92, 0.75), 0.3, 0.0, emit=(1.0, 0.85, 0.6))
    parts = [cyl("pole", 0.11, 7.0, (0, 0, 0), pole, 8, r2=0.07),
             cyl("foot", 0.2, 0.6, (0, 0, 0), pole, 8)]
    arm = box("arm", (0.08, 1.6, 0.08), (0, 0.75, 6.9), pole)
    head = box("head", (0.34, 0.7, 0.16), (0, 1.45, 6.82), pole, bevel=0.03)
    glow = box("glow", (0.28, 0.6, 0.04), (0, 1.45, 6.72), lamp)
    export("streetlight.glb", [join("streetlight", parts + [arm, head, glow])])


def car():
    reset()
    paint = mat("paint", (1.0, 1.0, 1.0), 0.35, 0.3)
    glass = mat("car_glass", (0.08, 0.1, 0.12), 0.1, 0.2)
    tyre = mat("tyre", (0.05, 0.05, 0.05), 0.9)
    lights = mat("lamp", (1.0, 0.92, 0.75), 0.3, 0.0, emit=(1.0, 0.85, 0.6))
    tail = mat("lamp_red", (0.9, 0.1, 0.05), 0.4, 0.0, emit=(1.0, 0.1, 0.05))
    body = box("body", (1.8, 4.3, 0.7), (0, 0, 0.62), paint, bevel=0.18, segs=3)
    cabin = box("cabin", (1.6, 2.3, 0.62), (0, -0.25, 1.22), glass, bevel=0.2, segs=3)
    parts = [body, cabin]
    for sx in (-0.86, 0.86):
        for sy in (-1.35, 1.35):
            w = cyl("w", 0.34, 0.24, (sx - 0.12 * (1 if sx < 0 else -1), sy, 0.34), tyre, 12)
            w.rotation_euler = (0, math.pi / 2, 0)
            w.location = (sx - 0.12, sy, 0.34) if sx > 0 else (sx - 0.12, sy, 0.34)
            parts.append(w)
    parts.append(box("hl", (1.5, 0.05, 0.14), (0, 2.16, 0.72), lights))
    parts.append(box("tl", (1.5, 0.05, 0.14), (0, -2.16, 0.78), tail))
    export("car.glb", [join("car", parts)])


def tree():
    reset()
    bark = mat("bark", (0.3, 0.22, 0.16), 0.9)
    leaf = mat("leaves", (0.32, 0.48, 0.24), 0.85)
    parts = [cyl("trunk", 0.22, 3.0, (0, 0, 0), bark, 7, r2=0.14)]
    for (x, y, z, r) in ((0, 0, 4.0, 1.9), (0.9, 0.4, 3.4, 1.3), (-0.8, -0.5, 3.6, 1.4), (0.2, -0.9, 4.6, 1.1)):
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=2, radius=r)
        for v in bm.verts:  # lumpy, stylised canopy
            n = v.co.normalized()
            v.co += n * 0.18 * math.sin(v.co.x * 3.1 + v.co.y * 2.3 + v.co.z * 1.7)
        bmesh.ops.translate(bm, vec=Vector((x, y, z)), verts=bm.verts)
        parts.append(new_obj("c", bm, leaf))
    export("tree.glb", [join("tree", parts)])


# ------------------------------------------------------------- landmarks
def clock_crown():
    """Crown for a waterfront clock tower (loosely early-1900s Liverpool):
    clock stage with four faces, colonnaded drum, ribbed dome, finial bird."""
    reset()
    stone = mat("stone_light", (0.78, 0.76, 0.72), 0.8)
    dark = mat("stone_dark", (0.45, 0.44, 0.42), 0.8)
    face = mat("clock_face", (0.95, 0.92, 0.82), 0.4, 0.0, emit=(0.4, 0.38, 0.3))
    bronze = mat("bronze", (0.35, 0.5, 0.42), 0.4, 0.8)  # verdigris
    gold = mat("gilt", (0.85, 0.66, 0.28), 0.3, 1.0)
    p = [box("stage", (16, 16, 12), (0, 0, 6), stone, bevel=0.2)]
    p.append(box("cornice", (17.2, 17.2, 0.9), (0, 0, 12.2), dark, bevel=0.1))
    for ang in range(4):  # clock faces
        a = ang * math.pi / 2
        c = cyl("clock", 3.6, 0.3, (0, 0, 0), face, 32)
        c.rotation_euler = (math.pi / 2, 0, a)
        c.location = (math.sin(a) * 8.05, -math.cos(a) * 8.05, 6.5)
        p.append(c)
    p.append(cyl("drum", 6.2, 7.0, (0, 0, 12.6), stone, 24))
    for i in range(12):  # colonnade
        a = i / 12 * math.tau
        p.append(cyl("col", 0.42, 6.6, (math.cos(a) * 6.9, math.sin(a) * 6.9, 12.8), stone, 8))
    p.append(cyl("ring", 7.4, 0.8, (0, 0, 19.4), dark, 24))
    p.append(dome("dome", 6.0, (0, 0, 20.2), bronze, 24, 6, 1.25))
    for i in range(8):  # dome ribs
        a = i / 8 * math.tau
        rib = box("rib", (0.35, 0.35, 7.2), (0, 0, 0), dark)
        rib.location = (math.cos(a) * 4.3, math.sin(a) * 4.3, 23.4)
        rib.rotation_euler = (0, -0.75, a)
        rib.rotation_euler = (math.sin(a) * 0.75, -math.cos(a) * 0.75, 0)
        p.append(rib)
    p.append(cyl("lantern", 1.3, 3.0, (0, 0, 27.4), stone, 12))
    p.append(cyl("plinth", 0.9, 1.0, (0, 0, 30.4), dark, 12))
    # Stylised mythical bird: body, neck, wings half-raised.
    p.append(sphere("bird_body", 1.0, (0, 0, 32.4), gold, 12, 8, (0.7, 1.3, 0.9)))
    p.append(sphere("bird_head", 0.45, (0, 1.2, 33.6), gold, 10, 6))
    p.append(cyl("bird_neck", 0.3, 1.2, (0, 0.8, 32.6), gold, 8))
    for s in (-1, 1):
        w = box("wing", (2.6, 1.2, 0.15), (s * 1.6, -0.1, 33.0), gold, bevel=0.05)
        w.rotation_euler = (0, s * 0.5, 0)
        p.append(w)
    export("clock_crown.glb", [join("clock_crown", p)])


def harbour_dome():
    """Big central dome with four corner cupolas (port-authority style)."""
    reset()
    stone = mat("stone_light", (0.78, 0.76, 0.72), 0.8)
    copper = mat("copper_patina", (0.36, 0.52, 0.46), 0.5, 0.6)
    p = [cyl("drum", 13, 8, (0, 0, 0), stone, 32), cyl("ring", 14, 1.0, (0, 0, 8), stone, 32),
         dome("dome", 12.5, (0, 0, 9), copper, 32, 8, 1.15), cyl("lantern", 2.0, 4.0, (0, 0, 22.8), stone, 12),
         dome("lanterncap", 2.2, (0, 0, 26.8), copper, 12, 4)]
    for sx, sy in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
        p.append(cyl("cup", 3.0, 5.0, (sx * 24, sy * 18, -8), stone, 12))
        p.append(dome("cupd", 3.1, (sx * 24, sy * 18, -3), copper, 12, 4, 1.3))
    export("harbour_dome.glb", [join("harbour_dome", p)])


def beacon():
    """Radio-beacon tower: tapering concrete shaft with a revolving-restaurant pod."""
    reset()
    conc = mat("concrete", (0.82, 0.8, 0.76), 0.85)
    glass = mat("glass", (0.25, 0.35, 0.42), 0.1, 0.6)
    steel = mat("steel_light", (0.7, 0.7, 0.72), 0.4, 0.7)
    red = mat("lamp_red", (0.9, 0.1, 0.05), 0.4, 0.0, emit=(1.0, 0.1, 0.05))
    p = [cyl("shaft", 6.5, 118, (0, 0, 0), conc, 24, r2=5.0)]
    p.append(cyl("pod_base", 7.0, 3.0, (0, 0, 115), conc, 24, r2=10.5))
    p.append(cyl("pod_glass", 10.5, 7.0, (0, 0, 118), glass, 32, r2=11.0))
    p.append(cyl("pod_top", 11.4, 1.6, (0, 0, 125), conc, 32, r2=9.0))
    p.append(cyl("crown", 5.0, 6.0, (0, 0, 126.6), conc, 16, r2=4.2))
    p.append(cyl("mast", 0.6, 12, (0, 0, 132.6), steel, 8, r2=0.2))
    p.append(sphere("tip", 0.5, (0, 0, 144.8), red, 8, 6))
    export("beacon.glb", [join("beacon", p)])


def cathedral_tower_top():
    """Pinnacles + louvred belfry stage for the sandstone cathedral tower."""
    reset()
    sand = mat("sandstone", (0.62, 0.38, 0.3), 0.9)
    dark = mat("sandstone_dark", (0.42, 0.25, 0.2), 0.9)
    p = [box("belfry", (34, 34, 20), (0, 0, 10), sand, bevel=0.3)]
    for i in range(3):  # tall louvred lancets on each face
        for a in range(4):
            ang = a * math.pi / 2
            off = (i - 1) * 8.5
            x = math.cos(ang) * 17.1 - math.sin(ang) * off
            y = math.sin(ang) * 17.1 + math.cos(ang) * off
            l = box("lancet", (2.8, 0.6, 14), (x, y, 10), dark)
            l.rotation_euler = (0, 0, ang + math.pi / 2)
            p.append(l)
    for sx, sy in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
        p.append(box("pier", (5, 5, 26), (sx * 15, sy * 15, 13), sand))
        p.append(cyl("pinnacle", 2.6, 9, (sx * 15, sy * 15, 26), sand, 8, r2=0.2))
    p.append(box("parapet", (35, 35, 2), (0, 0, 21), dark))
    export("cathedral_top.glb", [join("cathedral_top", p)])


def viaduct():
    """25 m bay of an elevated railway: brick arch pier, iron deck, girders."""
    reset()
    brick = mat("brick_dark", (0.42, 0.2, 0.15), 0.9)
    iron = mat("iron", (0.2, 0.24, 0.26), 0.5, 0.7)
    p = [box("pier_a", (9, 3, 9.2), (0, 0, 4.6), brick)]
    p.append(box("cap", (10, 3.6, 0.8), (0, 0, 9.4), brick))
    p.append(box("deck", (9, 25, 0.8), (0, 12.5, 10.2), iron))
    for x in (-4.3, 4.3):
        p.append(box("girder", (0.4, 25, 1.6), (x, 12.5, 11.2), iron))
        for i in range(10):
            p.append(box("post", (0.2, 0.2, 1.4), (x, i * 2.5, 11.4), iron))
    export("viaduct.glb", [join("viaduct", p)])


def crane():
    reset()
    paint = mat("crane_paint", (0.86, 0.6, 0.16), 0.6, 0.3)
    dark = mat("steel_dark", (0.16, 0.16, 0.17), 0.5, 0.6)
    p = []
    for sx, sy in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
        p.append(box("leg", (0.8, 0.8, 22), (sx * 4, sy * 4, 11), paint))
    p.append(box("cab", (9, 9, 4), (0, 0, 24), paint))
    p.append(box("boom", (2.2, 46, 2.2), (0, 14, 27), paint))
    p.append(box("counter", (5, 6, 3), (0, -12, 26), dark))
    p.append(box("apex", (1.2, 1.2, 10), (0, 0, 31), paint))
    export("crane.glb", [join("crane", p)])


# ------------------------------------------------------------- character
def character():
    """One stylised human (~1.8 m) in streetwear with grapple gear.
    One object per bone; origin at the joint; limbs extend toward -Z (Blender)
    which is -Y in Godot. The rig in Godot rotates these pivots."""
    reset()
    skin = mat("skin", (0.78, 0.56, 0.42), 0.6)
    hair = mat("hair", (0.1, 0.07, 0.05), 0.8)
    hood = mat("hoodie", (0.86, 0.12, 0.1), 0.75)      # signal red: reads against stone and sky
    hood_dk = mat("hoodie_dark", (0.5, 0.06, 0.06), 0.8)
    jog = mat("joggers", (0.13, 0.15, 0.19), 0.85)
    stripe = mat("stripe", (0.9, 0.9, 0.88), 0.7)
    shoe = mat("sneaker", (0.94, 0.94, 0.92), 0.6)
    sole = mat("sole", (0.2, 0.2, 0.22), 0.7)
    gear = mat("gear", (0.18, 0.2, 0.22), 0.4, 0.7)
    accent = mat("gear_accent", (0.15, 0.85, 0.85), 0.3, 0.2, emit=(0.1, 0.7, 0.75))
    objs = []

    def limb(name, length, r_top, r_bot, material, extra=(), seg=12):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r_bot, radius2=r_top, depth=length)
        bmesh.ops.translate(bm, vec=Vector((0, 0, -length / 2)), verts=bm.verts)
        ob = new_obj(name, bm, material)
        smooth(ob, 1)
        return join(name, [ob, *extra], (0, 0, 0))

    # Torso pieces (Godot rig: hips at 0.98 m, spine +0.06, chest +0.26, neck +0.26)
    pel = sphere("hips_m", 0.17, (0, 0, 0.0), jog, 16, 10, (1.0, 0.75, 0.6))
    belt = cyl("belt", 0.165, 0.07, (0, 0, 0.05), gear, 16)
    objs.append(join("hips", [smooth(pel, 1), belt]))

    abd = sphere("spine_m", 0.16, (0, 0, 0.13), hood, 16, 10, (1.0, 0.72, 1.0))
    pocket = box("pocket", (0.24, 0.05, 0.11), (0, 0.115, 0.07), hood_dk, bevel=0.02)
    objs.append(join("spine", [smooth(abd, 1), pocket]))

    ch = sphere("chest_m", 0.2, (0, 0, 0.1), hood, 18, 12, (1.05, 0.68, 0.95))
    hoodfold = sphere("hoodfold", 0.12, (0, -0.1, 0.27), hood_dk, 12, 8, (1.3, 0.8, 0.6))
    pack = box("pack", (0.26, 0.12, 0.34), (0, -0.19, 0.08), gear, bevel=0.03)
    spool = cyl("spool", 0.07, 0.24, (0, 0, 0), gear, 16)
    spool.rotation_euler = (0, math.pi / 2, 0)
    spool.location = (0.12, -0.26, 0.16)
    light = box("packlight", (0.18, 0.01, 0.03), (0, -0.255, 0.0), accent)
    objs.append(join("chest", [smooth(ch, 1), smooth(hoodfold, 1), pack, spool, light]))

    neck = cyl("neck_m", 0.055, 0.1, (0, 0, -0.02), skin, 10)
    objs.append(join("neck", [neck]))

    head = sphere("head_m", 0.105, (0, 0.0, 0.11), skin, 18, 12, (0.9, 1.0, 1.12))
    hair_c = sphere("hair_m", 0.112, (0, -0.015, 0.14), hair, 16, 10, (0.94, 1.02, 1.0))
    for v in hair_c.data.vertices:  # trim the hair cap to sit above the face
        if v.co.z < -0.02 or (v.co.y > 0.02 and v.co.z < 0.05):
            v.co.z = max(v.co.z, 0.05 if v.co.y > 0.02 else -0.02)
    nose = sphere("nose", 0.022, (0, 0.1, 0.1), skin, 8, 6, (0.8, 1.0, 1.2))
    ears = [sphere("ear", 0.025, (s * 0.094, 0.0, 0.11), skin, 8, 6, (0.5, 1.0, 1.3)) for s in (-1, 1)]
    objs.append(join("head", [smooth(head, 1), smooth(hair_c, 1), nose, *ears]))

    for side, s in (("l", -1), ("r", 1)):
        objs.append(limb(f"upper_arm_{side}", 0.29, 0.065, 0.055, hood))
        extra = []
        if side == "r":  # wrist launcher
            extra.append(box("launcher", (0.085, 0.13, 0.16), (0, 0.035, -0.17), gear, bevel=0.015))
            extra.append(box("launch_led", (0.02, 0.005, 0.1), (0, 0.1, -0.17), accent))
        cuff = cyl("cuff", 0.05, 0.05, (0, 0, -0.27), hood_dk, 12)
        objs.append(limb(f"forearm_{side}", 0.26, 0.055, 0.045, hood, [cuff, *extra]))
        hand = sphere(f"hand_m", 0.048, (0, 0.0, -0.05), skin, 10, 8, (0.8, 0.55, 1.1))
        objs.append(join(f"hand_{side}", [smooth(hand, 1)]))
        knee_pad = sphere("kp", 0.06, (0, 0.04, -0.44), jog, 10, 6, (1.0, 0.8, 1.0))
        stripe_t = box("stripe", (0.012, 0.02, 0.4), (s * 0.085, 0.0, -0.22), stripe)
        objs.append(limb(f"thigh_{side}", 0.45, 0.09, 0.065, jog, [knee_pad, stripe_t]))
        cuffl = cyl("cuffl", 0.055, 0.06, (0, 0, -0.42), jog, 12)
        stripe_s = box("stripe2", (0.012, 0.02, 0.38), (s * 0.06, 0.0, -0.2), stripe)
        objs.append(limb(f"shin_{side}", 0.44, 0.065, 0.05, jog, [cuffl, stripe_s]))
        sh = box("shoe", (0.11, 0.27, 0.1), (0, 0.06, -0.03), shoe, bevel=0.035, segs=3)
        so = box("sole", (0.115, 0.28, 0.03), (0, 0.06, -0.085), sole, bevel=0.01)
        objs.append(join(f"foot_{side}", [sh, so]))
    export("character.glb", objs)


if __name__ == "__main__":
    for fn in (water_tower, ac_unit, antenna, streetlight, car, tree, clock_crown, harbour_dome, beacon,
               cathedral_tower_top, viaduct, crane, character):
        fn()
    print("KIT DONE")
