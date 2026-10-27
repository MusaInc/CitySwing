"""City Swing hero: an athletic, skinned character.

Run:  blender -b --factory-startup --python tools/blender/build_character.py -- assets/models

Output: character.glb with
  * "body"      – one continuous skinned mesh (torso, neck, arms, legs and the
                  clothes on them) on an armature whose bones match the Godot
                  rig (CharacterRig.BONES). Built from lofted anatomy, merged by
                  a voxel remesh (so shoulders, elbows, hips and knees bend as
                  one surface instead of rigid segments), decimated for mobile,
                  vertex-coloured from the painted source shapes, and weighted
                  automatically (bone heat).
  * rigid parts – head, open hands, gripping fists, sneakers, spool and the
                  web gauntlet, one object per bone with its origin at the joint (the
                  same convention as before: Godot parents them to the pivots).

The rest pose is an A-pose (arms 42° out, legs 5° out) so limbs don't fuse
with the torso in the remesh; the Godot rig maps its own pivots onto it.
Blender Z-up / +Y front  ->  Godot Y-up / -Z front. Feet on Z = 0.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import build_kit as K  # noqa: E402  (helpers: mat, box, cyl, sphere, smooth, join, paint, bake_vertex_colors)

OUT = K.OUT

# Rig joints (Godot rig space + 0.9 m: feet on the ground). Must match
# src/player/character_rig.gd BONES.
J = {
    "hips": Vector((0, 0, 0.98)), "spine": Vector((0, 0, 1.04)), "chest": Vector((0, 0, 1.30)),
    "neck": Vector((0, 0, 1.56)), "head": Vector((0, 0, 1.64)),
}
ARM_A = math.radians(42.0)   # A-pose arm abduction
LEG_A = math.radians(5.0)    # A-pose leg abduction
UPPER, FORE, HAND = 0.29, 0.26, 0.09
THIGH, SHIN = 0.45, 0.44
for side, sx in (("l", -1), ("r", 1)):
    sh = Vector((sx * 0.2, 0, 1.50))
    adir = Vector((sx * math.sin(ARM_A), 0, -math.cos(ARM_A)))
    J["upper_arm_" + side] = sh
    J["forearm_" + side] = sh + adir * UPPER
    J["hand_" + side] = sh + adir * (UPPER + FORE)
    J["hand_end_" + side] = sh + adir * (UPPER + FORE + HAND)
    hip = Vector((sx * 0.1, 0, 0.94))
    ldir = Vector((sx * math.sin(LEG_A), 0, -math.cos(LEG_A)))
    J["thigh_" + side] = hip
    J["shin_" + side] = hip + ldir * THIGH
    J["foot_" + side] = hip + ldir * (THIGH + SHIN)

PARENT = {
    "hips": None, "spine": "hips", "chest": "spine", "neck": "chest", "head": "neck",
    "upper_arm_l": "chest", "forearm_l": "upper_arm_l", "hand_l": "forearm_l",
    "upper_arm_r": "chest", "forearm_r": "upper_arm_r", "hand_r": "forearm_r",
    "thigh_l": "hips", "shin_l": "thigh_l", "foot_l": "shin_l",
    "thigh_r": "hips", "shin_r": "thigh_r", "foot_r": "shin_r",
}


def tube(name, rings, segs=20, cap=True, front=Vector((0, 1, 0))):
    """Loft along an arbitrary polyline. rings: [(centre, rx, ry, dy)] where rx
    is the half-width across the body (side), ry front–back, dy shifts the ring
    forward (+) or back (−)."""
    bm = bmesh.new()
    loops = []
    pts = [Vector(r[0]) for r in rings]
    for i, (c, rx, ry, *rest) in enumerate(rings):
        dy = rest[0] if rest else 0.0
        c = Vector(c)
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        f = (front - t * front.dot(t)).normalized()
        s = f.cross(t).normalized()
        ring = []
        for k in range(segs):
            a = k / segs * math.tau
            ring.append(bm.verts.new(c + f * dy + s * math.cos(a) * rx + f * math.sin(a) * ry))
        loops.append(ring)
    for r0, r1 in zip(loops, loops[1:]):
        for k in range(segs):
            j = (k + 1) % segs
            bm.faces.new((r0[k], r0[j], r1[j], r1[k]))
    if cap:
        for ring in (loops[0], loops[-1]):
            bm.faces.new(ring)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return K.new_obj(name, bm)


def along(a, b, t):
    return a.lerp(b, t)


def build():
    K.reset()
    M = K.mat
    skin = M("skin", (0.62, 0.42, 0.31), 0.55)
    lip = M("lip", (0.5, 0.29, 0.25), 0.6)
    hair = M("hair", (0.07, 0.05, 0.04), 0.85)
    brow = M("brow", (0.07, 0.045, 0.035), 0.85)
    eye_w = M("eye_white", (0.86, 0.84, 0.8), 0.3)
    iris = M("iris", (0.16, 0.1, 0.06), 0.3)
    jacket = M("jacket", (0.8, 0.1, 0.09), 0.7)
    jacket_dk = M("jacket_dark", (0.42, 0.05, 0.05), 0.75)
    tee = M("tee", (0.16, 0.16, 0.18), 0.6)
    pants = M("pants", (0.12, 0.14, 0.2), 0.85)
    pants_dk = M("pants_dark", (0.08, 0.09, 0.13), 0.85)
    strap = M("strap", (0.06, 0.06, 0.07), 0.6)
    metal = M("metal", (0.55, 0.57, 0.6), 0.35, 0.8)
    shoe = M("sneaker", (0.93, 0.93, 0.9), 0.6)
    sole = M("sole", (0.8, 0.12, 0.1), 0.6)
    glove = M("glove", (0.1, 0.1, 0.11), 0.7)
    gear = M("gear", (0.18, 0.2, 0.22), 0.4, 0.7)
    glow = M("gear_glow", (0.2, 0.95, 0.95), 0.3, 0.0, emit=(0.1, 0.9, 0.95))
    lens = M("lens", (0.2, 0.9, 0.95), 0.1, 0.0, emit=(0.05, 0.6, 0.7))
    scarf = M("scarf", (0.95, 0.75, 0.2), 0.8)

    # ================================================================ body
    src = []  # painted source shapes; merged into one skin below

    # Pelvis and seat (trousers), up under the jacket hem.
    src.append(K.paint(tube("pelvis", [
        ((0, 0, 0.84), 0.11, 0.085), ((0, 0, 0.88), 0.155, 0.105, -0.005), ((0, 0, 0.93), 0.172, 0.112, -0.01),
        ((0, 0, 0.99), 0.168, 0.108, -0.005), ((0, 0, 1.03), 0.158, 0.1)]), pants))
    for sx in (-1, 1):  # glutes
        src.append(K.paint(K.sphere("glute", 0.088, (sx * 0.068, -0.055, 0.91), None, 14, 10, (1.0, 0.85, 1.0)), pants))
    # Torso (jacket): V-taper from a narrow waist to broad lats and chest.
    src.append(K.paint(tube("torso", [
        ((0, 0, 0.97), 0.17, 0.118), ((0, 0, 1.02), 0.162, 0.115), ((0, 0, 1.09), 0.155, 0.112, 0.004),
        ((0, 0, 1.17), 0.165, 0.118, 0.01), ((0, 0, 1.25), 0.18, 0.126, 0.016), ((0, 0, 1.33), 0.192, 0.132, 0.02),
        ((0, 0, 1.40), 0.194, 0.128, 0.016), ((0, 0, 1.46), 0.178, 0.112, 0.004), ((0, 0, 1.51), 0.135, 0.09),
        ((0, 0, 1.54), 0.08, 0.07)], segs=24), jacket))
    for sx in (-1, 1):  # pecs and lats give the chest its shape under the jacket
        src.append(K.paint(K.sphere("pec", 0.085, (sx * 0.075, 0.08, 1.36), None, 14, 10, (1.0, 0.6, 0.8)), jacket))
        src.append(K.paint(K.sphere("lat", 0.09, (sx * 0.12, -0.03, 1.3), None, 14, 10, (0.6, 0.8, 1.3)), jacket))
        # Trapezius slope from neck to shoulder.
        src.append(K.paint(tube("trap", [((sx * 0.03, -0.01, 1.53), 0.04, 0.05), ((sx * 0.13, -0.01, 1.505), 0.045, 0.055),
                                         ((sx * 0.2, 0.0, 1.49), 0.05, 0.055)], segs=14), jacket))
        src.append(K.paint(K.sphere("deltoid", 0.06, J["upper_arm_" + ("l" if sx < 0 else "r")] + Vector((sx * 0.006, 0, -0.012)),
                                    None, 14, 10, (0.95, 1.05, 1.05)), jacket))
    # Hood bunched at the back of the neck.
    src.append(K.paint(tube("hood", [((0, -0.055, 1.49), 0.1, 0.05), ((0, -0.075, 1.55), 0.11, 0.055),
                                     ((0, -0.07, 1.6), 0.085, 0.045)], segs=18), jacket_dk))
    # Neck.
    src.append(K.paint(tube("neck", [((0, 0.0, 1.52), 0.066, 0.064), ((0, 0.008, 1.59), 0.058, 0.06),
                                     ((0, 0.012, 1.65), 0.055, 0.058)], segs=16), skin))
    # Zip line, hem band and harness straps (thin; they become colour on the skin).
    src.append(K.paint(tube("zip", [((0, 0.118, 1.0), 0.01, 0.006), ((0, 0.14, 1.25), 0.01, 0.006),
                                    ((0, 0.135, 1.44), 0.01, 0.006), ((0, 0.08, 1.53), 0.01, 0.006)], segs=6), tee))
    src.append(K.paint(tube("hem", [((0, 0, 0.965), 0.173, 0.121), ((0, 0, 0.99), 0.172, 0.12)], segs=24, cap=False), jacket_dk))

    # Arms (jacket sleeves) in the A-pose.
    for side, sx in (("l", -1), ("r", 1)):
        a, e, w = J["upper_arm_" + side], J["forearm_" + side], J["hand_" + side]
        src.append(K.paint(tube("upper_arm", [
            (along(a, e, -0.05), 0.058, 0.06), (along(a, e, 0.2), 0.058, 0.062), (along(a, e, 0.55), 0.052, 0.056),
            (along(a, e, 0.85), 0.046, 0.048), (along(a, e, 1.0), 0.045, 0.046)], segs=16), jacket))
        src.append(K.paint(tube("sleeve_stripe", [(along(a, e, 0.05) + Vector((sx * 0.052, 0, 0)), 0.006, 0.014),
                                                  (along(a, e, 0.9) + Vector((sx * 0.044, 0, 0)), 0.006, 0.012)], segs=6), jacket_dk))
        src.append(K.paint(tube("forearm", [
            (along(e, w, -0.04), 0.045, 0.046), (along(e, w, 0.2), 0.05, 0.048), (along(e, w, 0.6), 0.042, 0.04),
            (along(e, w, 0.88), 0.037, 0.035), (along(e, w, 1.02), 0.036, 0.034)], segs=16), jacket))
        src.append(K.paint(tube("cuff", [(along(e, w, 0.82), 0.041, 0.039), (along(e, w, 1.03), 0.04, 0.038)], segs=16), jacket_dk))

    # Legs (trousers) with real thigh/calf shape.
    for side, sx in (("l", -1), ("r", 1)):
        h, k, f = J["thigh_" + side], J["shin_" + side], J["foot_" + side]
        src.append(K.paint(tube("thigh", [
            (along(h, k, -0.08), 0.098, 0.104), (along(h, k, 0.15), 0.1, 0.104, 0.006), (along(h, k, 0.45), 0.09, 0.093, 0.01),
            (along(h, k, 0.8), 0.072, 0.074, 0.005), (along(h, k, 1.0), 0.064, 0.066)], segs=18), pants))
        src.append(K.paint(K.sphere("knee", 0.062, k + Vector((0, 0.012, 0)), None, 14, 10), pants))
        src.append(K.paint(tube("shin", [
            (along(k, f, 0.0), 0.062, 0.064), (along(k, f, 0.25), 0.068, 0.074, -0.012), (along(k, f, 0.55), 0.058, 0.06, -0.006),
            (along(k, f, 0.85), 0.054, 0.056), (along(k, f, 0.98), 0.058, 0.06)], segs=18), pants))
        src.append(K.paint(tube("ankle_cuff", [(along(k, f, 0.84), 0.06, 0.062), (along(k, f, 0.99), 0.061, 0.063)], segs=16), pants_dk))
        src.append(K.paint(K.box("cargo", (0.03, 0.09, 0.11), along(h, k, 0.42) + Vector((sx * 0.085, 0, 0)), None, bevel=0.015), pants_dk))

    body_src = K.join("body_src", src)
    K.bake_vertex_colors(body_src)

    # Merge into one surface, smooth the seams, and trim for mobile.
    bpy.ops.object.select_all(action="DESELECT")
    body = body_src.copy()
    body.data = body_src.data.copy()
    body.name = "body"
    bpy.context.scene.collection.objects.link(body)
    rm = body.modifiers.new("remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = 0.009
    rm.use_smooth_shade = True
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.modifier_apply(modifier="remesh")
    sm = body.modifiers.new("smooth", "CORRECTIVE_SMOOTH")
    sm.iterations = 4
    sm.use_only_smooth = True
    bpy.ops.object.modifier_apply(modifier="smooth")
    dec = body.modifiers.new("dec", "DECIMATE")
    dec.ratio = 1.0
    bpy.ops.object.modifier_apply(modifier="dec")
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    dec = body.modifiers.new("dec", "DECIMATE")
    dec.ratio = min(1.0, 9000.0 / max(tris, 1))
    bpy.ops.object.modifier_apply(modifier="dec")
    # Colour from the painted sources (nearest face, interpolated).
    body.data.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    dt = body.modifiers.new("col", "DATA_TRANSFER")
    dt.object = body_src
    dt.use_loop_data = True
    dt.data_types_loops = {"COLOR_CORNER"}
    dt.loop_mapping = "POLYINTERP_NEAREST"
    bpy.ops.object.modifier_apply(modifier="col")
    body.data.color_attributes.active_color = body.data.color_attributes["Col"]
    for p in body.data.polygons:
        p.use_smooth = True
    body.data.materials.clear()
    body.data.materials.append(K._mats.get("character") or M("character", (1, 1, 1), 0.7))
    bpy.data.objects.remove(body_src)
    print("BODY tris", sum(len(p.vertices) - 2 for p in body.data.polygons))

    # ------------------------------------------------------------ armature
    arm_data = bpy.data.armatures.new("rig")
    rig = bpy.data.objects.new("rig", arm_data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    tails = {
        "hips": J["spine"], "spine": J["chest"], "chest": J["neck"], "neck": J["head"], "head": J["head"] + Vector((0, 0, 0.22)),
    }
    for side in ("l", "r"):
        tails["upper_arm_" + side] = J["forearm_" + side]
        tails["forearm_" + side] = J["hand_" + side]
        tails["hand_" + side] = J["hand_end_" + side]
        tails["thigh_" + side] = J["shin_" + side]
        tails["shin_" + side] = J["foot_" + side]
        tails["foot_" + side] = J["foot_" + side] + Vector((0, 0.14, -0.04))
    for name in PARENT:
        b = arm_data.edit_bones.new("b_" + name)  # prefixed: part objects share the plain names
        b.head = J[name]
        b.tail = tails[name]
        b.roll = 0.0
    for name, par in PARENT.items():
        if par:
            arm_data.edit_bones["b_" + name].parent = arm_data.edit_bones["b_" + par]
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    unweighted = sum(1 for v in body.data.vertices if not v.groups)
    print("BODY unweighted verts", unweighted)

    # ======================================================== rigid parts
    parts = []

    def part(name, objs, origin):
        ob = K.join(name, objs, origin)
        K.bake_vertex_colors(ob)
        ob.location = (0, 0, 0)  # exported at the origin; Godot parents it to the pivot
        parts.append(ob)

    # ---- head: skull, jaw, cheekbones, brow ridge, eyes, nose, mouth, ears, hair
    hc = J["head"]
    o = lambda x, y, z: hc + Vector((x, y, z - 0.028))  # noqa: E731  (head sits a little lower on the neck)
    head = []
    head.append(K.sphere("cranium", 0.097, o(0, -0.012, 0.135), skin, 22, 14, (0.9, 1.04, 1.0)))
    for pl in head[-1].data.polygons:
        pl.use_smooth = True
    head.append(K.smooth(K.paint(tube("face", [(o(0, 0.03, 0.03), 0.045, 0.045), (o(0, 0.025, 0.055), 0.074, 0.072),
                                                (o(0, 0.018, 0.1), 0.082, 0.086), (o(0, 0.01, 0.14), 0.086, 0.09)], segs=20), skin), 1))
    head.append(K.smooth(K.paint(tube("chin", [(o(0, 0.06, 0.02), 0.026, 0.02), (o(0, 0.07, 0.04), 0.03, 0.02)], segs=12), skin), 1))
    for sx in (-1, 1):
        head.append(K.sphere("cheek", 0.03, o(sx * 0.045, 0.06, 0.1), skin, 10, 8, (1.0, 0.7, 0.8)))
        head.append(K.sphere("eye", 0.0135, o(sx * 0.034, 0.083, 0.127), eye_w, 10, 8))
        head.append(K.sphere("iris", 0.0072, o(sx * 0.034, 0.0955, 0.127), iris, 8, 6, (1.0, 0.5, 1.0)))
        head.append(K.box("lid", (0.03, 0.016, 0.006), o(sx * 0.034, 0.088, 0.139), skin, bevel=0.003))
        head.append(K.box("brow", (0.034, 0.012, 0.009), o(sx * 0.034, 0.09, 0.148), brow, bevel=0.003))
        head.append(K.sphere("ear", 0.024, o(sx * 0.091, -0.006, 0.118), skin, 10, 8, (0.42, 0.85, 1.3)))
    head.append(K.box("brow_ridge", (0.09, 0.02, 0.016), o(0, 0.084, 0.142), skin, bevel=0.007))
    nose = K.paint(tube("nose", [(o(0, 0.09, 0.14), 0.011, 0.009), (o(0, 0.108, 0.106), 0.016, 0.014),
                                 (o(0, 0.112, 0.095), 0.021, 0.013), (o(0, 0.098, 0.088), 0.017, 0.008)], segs=10), skin)
    head.append(K.smooth(nose, 1))
    head.append(K.box("lips", (0.042, 0.012, 0.012), o(0, 0.09, 0.07), lip, bevel=0.005))
    cap = K.sphere("hair_cap", 0.102, o(0, -0.022, 0.15), hair, 20, 12, (0.93, 1.05, 0.98))
    for pl in cap.data.polygons:
        pl.use_smooth = True
    for v in cap.data.vertices:  # hairline above the forehead and ears
        if v.co.y - hc.y > 0.03 and v.co.z - hc.z < 0.17:
            v.co.y = hc.y + 0.03 - (v.co.y - hc.y - 0.03) * 0.3
    head.append(cap)
    for (x, y, z, r) in ((0.0, 0.05, 0.225, 0.048), (0.04, 0.025, 0.232, 0.044), (-0.042, 0.018, 0.228, 0.044),
                         (0.02, -0.035, 0.232, 0.05), (-0.03, -0.065, 0.205, 0.05)):
        head.append(K.smooth(K.sphere("tuft", r, o(x, y, z), hair, 8, 5, (1.0, 1.2, 0.55)), 1))
    band = K.paint(tube("goggle_band", [(o(0, -0.01, 0.168), 0.102, 0.11), (o(0, -0.01, 0.186), 0.102, 0.11)], segs=22, cap=False), strap)
    head.append(band)
    for sx in (-1, 1):  # goggles pushed up onto the forehead
        g = K.cyl("goggle", 0.024, 0.02, (0, 0, 0), gear, 14)
        g.rotation_euler = (math.pi / 2 - 0.5, 0, 0)
        g.location = o(sx * 0.036, 0.083, 0.19)
        le = K.cyl("lens", 0.018, 0.006, (0, 0, 0), lens, 14)
        le.rotation_euler = (math.pi / 2 - 0.5, 0, 0)
        le.location = o(sx * 0.036, 0.096, 0.198)
        head += [g, le]
    part("head", head, hc)

    # ---- spool on the back (rides the chest bone)
    cc = J["chest"]
    spool = [K.box("housing", (0.22, 0.08, 0.2), cc + Vector((0, -0.15, 0.11)), gear, bevel=0.02)]
    for sx in (-1, 1):
        d = K.cyl("drum", 0.06, 0.055, (0, 0, 0), gear, 18)
        d.rotation_euler = (0, math.pi / 2, 0)
        d.location = cc + Vector((sx * 0.14, -0.155, 0.13))
        r = K.cyl("ring", 0.063, 0.011, (0, 0, 0), glow, 18)
        r.rotation_euler = (0, math.pi / 2, 0)
        r.location = cc + Vector((sx * 0.172, -0.155, 0.13))
        spool += [d, r]
    part("chest", spool, cc)

    # ---- web launcher gauntlet: rides the right forearm pivot (elbow origin,
    # arm along -Z, back of the forearm toward +Y like the hand's knuckles).
    gaunt = [K.box("gauntlet", (0.088, 0.1, 0.13), (0, 0.012, -0.165), gear, bevel=0.016, segs=2),
             K.box("nozzle", (0.028, 0.045, 0.035), (0, 0.06, -0.235), metal, bevel=0.006),
             K.box("led", (0.055, 0.006, 0.012), (0, 0.064, -0.13), glow),
             K.paint(tube("strap_g", [(Vector((0, 0, -0.105)), 0.047, 0.045), (Vector((0, 0, -0.115)), 0.047, 0.045)], segs=14), strap)]
    part("forearm_r", gaunt, Vector((0, 0, 0)))

    # ---- hands: modelled pointing along the arm (-Z) in the rig's rest frame,
    # i.e. at the origin, then placed on the hand joint. Fingers in segments.
    def finger(x, length, curl, thick, mat_, base_y=0.0, splay=0.0):
        segs = []
        p = Vector((x, base_y, -0.075))
        d = Vector((math.sin(splay), 0, -1)).normalized()
        ang = 0.0
        for i, frac in enumerate((0.45, 0.32, 0.23)):
            ang += curl
            dd = Matrix.Rotation(ang, 3, "X") @ d
            q = p + dd * length * frac
            ph = K.paint(tube("phal", [(p, thick, thick * 0.92), (q, thick * 0.9, thick * 0.85)], segs=7), mat_)
            for pl in ph.data.polygons:
                pl.use_smooth = True
            segs.append(ph)
            p = q
        return segs

    for side, sx in (("l", -1), ("r", 1)):
        hand0 = Vector((0, 0, 0))
        palm = K.smooth(K.paint(tube("palm", [(Vector((0, 0, 0.005)), 0.03, 0.02), (Vector((0, 0.002, -0.04)), 0.04, 0.018),
                                              (Vector((0, 0.004, -0.078)), 0.042, 0.015)], segs=12), glove), 1)
        open_ = [palm]
        for i in range(4):
            x = (i - 1.5) * 0.019
            open_ += finger(x, 0.078 - abs(i - 1.2) * 0.01, 0.22, 0.0088, glove, 0.004, (i - 1.5) * 0.025)
        th = K.smooth(K.paint(tube("thumb_o", [(Vector((sx * -0.03, 0.012, -0.02)), 0.011, 0.01),
                                             (Vector((sx * -0.048, 0.03, -0.055)), 0.01, 0.009),
                                             (Vector((sx * -0.052, 0.04, -0.082)), 0.009, 0.008)], segs=8), glove), 1)
        open_.append(th)
        part("hand_" + side, open_, hand0)
        fist = [K.smooth(K.paint(tube("fistpalm", [(Vector((0, 0, 0.005)), 0.03, 0.02), (Vector((0, 0.004, -0.045)), 0.041, 0.022),
                                                    (Vector((0, 0.01, -0.08)), 0.042, 0.024)], segs=12), glove), 1)]
        for i in range(4):
            x = (i - 1.5) * 0.019
            fist += finger(x, 0.072, 1.25, 0.0098, glove, 0.01)
        fist.append(K.smooth(K.paint(tube("thumb_g", [(Vector((sx * -0.03, 0.015, -0.025)), 0.011, 0.01),
                                                       (Vector((sx * -0.02, 0.04, -0.06)), 0.01, 0.009),
                                                       (Vector((sx * -0.005, 0.05, -0.075)), 0.009, 0.008)], segs=8), glove), 1))
        part("hand_%s_grip" % side, fist, hand0)

    # ---- sneakers (rest frame of the foot pivot at the ankle; toes +Y)
    for side, sx in (("l", -1), ("r", 1)):
        z0 = Vector((0, 0, 0))
        upper = K.smooth(K.paint(tube("shoe_upper", [
            (Vector((0, -0.065, -0.06)), 0.048, 0.035), (Vector((0, -0.01, -0.065)), 0.056, 0.055), (Vector((0, 0.08, -0.08)), 0.056, 0.042),
            (Vector((0, 0.17, -0.09)), 0.05, 0.026), (Vector((0, 0.205, -0.095)), 0.034, 0.013)], segs=14,
            front=Vector((0, 0, 1))), shoe), 1)
        collar_ = K.smooth(K.paint(tube("shoe_collar", [(Vector((0, -0.01, -0.06)), 0.057, 0.058), (Vector((0, -0.012, 0.0)), 0.06, 0.062)],
                                        segs=14), shoe), 1)
        so = K.box("sole", (0.118, 0.3, 0.034), (0, 0.065, -0.114), sole, bevel=0.014, segs=2)
        toe = K.smooth(K.sphere("toecap", 0.044, (0, 0.18, -0.094), sole, 12, 8, (1.15, 1.0, 0.6)), 1)
        lace = K.box("laces", (0.045, 0.11, 0.012), (0, 0.075, -0.035), strap)
        lace.rotation_euler = (-0.35, 0, 0)
        part("foot_" + side, [upper, collar_, so, toe, lace], z0)

    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    body.select_set(True)
    for p in parts:
        p.select_set(True)
    path = os.path.join(OUT, "character.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False,
                              export_yup=True, export_materials="EXPORT", export_vertex_color="ACTIVE",
                              export_skins=True, export_animations=False)
    print("CHARACTER DONE", path)


if __name__ == "__main__":
    build()
