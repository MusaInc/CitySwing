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
  * rigid parts – head, hood (separate so headwear can swap it), open hands, gripping fists, sneakers, spool and the
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


def hood(o, material, rim_mat):
    """Fitted courier helmet: swept crown, recessed visor, tapered jaw guards.
    Keeps the existing headwear attachment name for wardrobe compatibility.
    """
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=36, v_segments=24, radius=1.0)
    c=o(0,-.012,.128)
    drop=[]
    for v in bm.verts:
        d=v.co.copy()
        v.co=c+Vector((d.x*.108,d.y*.119,d.z*.117))
        v.co.y-=max(0,-d.y)*max(0,d.z)*.025
        if d.y>.48 and -.58<d.z<.43: drop.append(v)
        elif d.z<-.8: drop.append(v)
    bmesh.ops.delete(bm,geom=drop,context='VERTS')
    bmesh.ops.solidify(bm,geom=bm.faces[:],thickness=.008)
    bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
    ob=K.new_obj('helmet_shell',bm,material)
    for face in ob.data.polygons: face.use_smooth=True
    return ob


def paint_panels(body, mats):
    """Garment construction on the merged skin, as exact palette keys (so shop
    recolours still apply): the hoodie's ribbed hem band, side seams, the
    kangaroo pocket's stitched outline, dropped-shoulder seams; a quiet side
    seam down each jogger leg. Decided from the rest-pose surface position of
    each corner."""
    col = body.data.color_attributes["Col"]
    key = {n: tuple(m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value[:3]) for n, m in mats.items()}

    def near(c, k):
        return max(abs(c[i] - k[i]) for i in range(3)) < 0.03

    me = body.data
    for poly in me.polygons:
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            p = me.vertices[vi].co
            c = tuple(col.data[li].color[:3])
            x, y, z = p.x, p.y, p.z
            ax = abs(x)
            want = None
            if not any(near(c, key[k_]) for k_ in key):
                # A blend from the colour transfer (seat, cuffs): snap to the
                # nearest garment key so shop recolours apply everywhere.
                k_ = min(key, key=lambda n: sum((c[i] - key[n][i]) ** 2 for i in range(3)))
                if z < 0.785 and ax < 0.19 and k_ in ("jacket", "jacket_dk"):
                    k_ = "pants"
                c = key[k_]
                col.data[li].color = (c[0], c[1], c[2], col.data[li].color[3])
            if z > 1.565 and ax < 0.085 and "mask" in key:
                want = "mask"  # the gaiter (the colour transfer bleeds the neckline onto it)
            elif (near(c, key["jacket"]) or near(c, key["jacket_dk"])) and z < 0.785 and ax < 0.19:
                want = "pants"  # under the hem: the joggers
            elif near(c, key["jacket"]):
                torso = ax < 0.26 and 0.78 < z < 1.56
                if torso:
                    ang = math.degrees(math.atan2(y, ax))  # 0 = side, 90 = front, -90 = back
                    hem = z < 0.835
                    side = abs(ang) < 2.2 and 0.85 < z < 1.42 and ax > 0.14
                    # Kangaroo pocket: stitched outline (sides, bottom, top).
                    pk = y > 0.12 and ax < 0.152 and 0.865 < z < 1.045
                    pocket = pk and (ax > 0.138 or z < 0.876 or z > 1.034)
                    # Pocket openings: slanted slits at each side.
                    slit = y > 0.12 and 0.08 < ax < 0.15 and abs((z - 0.885) - (0.15 - ax) * 2.3) < 0.006 and z < 1.03
                    if hem or side or pocket or slit:
                        want = "jacket_dk"
                elif z > 1.0:
                    # Dropped-shoulder seam ring round the top of each sleeve.
                    sh = Vector((math.copysign(0.2, x), 0.0, 1.5))
                    d = p - sh
                    adir = Vector((math.copysign(math.sin(ARM_A), x), 0.0, -math.cos(ARM_A)))
                    along_ = d.dot(adir)
                    if 0.055 < along_ < 0.063:
                        want = "jacket_dk"
            elif near(c, key["pants"]) and z < 0.9:
                hip = Vector((math.copysign(0.1, x), 0.0, 0.94))
                ldir = Vector((math.copysign(math.sin(LEG_A), x), 0.0, -math.cos(LEG_A)))
                d = p - hip
                rad = d - ldir * d.dot(ldir)
                out = Vector((math.copysign(1.0, x), 0.0, 0.0))
                if rad.length > 1e-4 and rad.normalized().dot(out) > 0.996 and 0.12 < z < 0.86:
                    want = "pants_dk"
            if want:
                k = key[want]
                col.data[li].color = (k[0], k[1], k[2], col.data[li].color[3])


def cloth_uv(ob, weight, rest=None):
    """Second UV map "cloth" = (w, 0): how freely each corner moves with the
    wind/inertia offset in character.gdshader (0 = held by the body, 1 = a
    free hem edge). `weight(p, colour)` gets the rest-pose position."""
    me = ob.data
    mw = rest if rest is not None else Matrix.Identity(4)
    colattr = me.color_attributes.get("Col")
    uv = me.uv_layers.new(name="cloth")
    for poly in me.polygons:
        for li in poly.loop_indices:
            p = mw @ me.vertices[me.loops[li].vertex_index].co
            c = tuple(colattr.data[li].color[:3]) if colattr else (0, 0, 0)
            uv.data[li].uv = (max(0.0, min(1.0, weight(p, c))), 0.0)


def _repack(ob, _body):
    me = ob.data
    mw = Matrix.Identity(4)
    if "rest" in ob:
        r = list(ob["rest"])
        mw = Matrix([r[0:4], r[4:8], r[8:12], r[12:16]])
    ao = me.uv_layers["ao"]
    cl = me.uv_layers["cloth"]
    vals = [(ao.data[i].uv[0], cl.data[i].uv[0]) for i in range(len(me.loops))]
    fab = []
    for poly in me.polygons:
        n = poly.normal
        for li in poly.loop_indices:
            p = mw @ me.vertices[me.loops[li].vertex_index].co
            # Wrap round the vertical: knit ribs run up the garment.
            u = math.atan2(p.x, p.y) * 0.16 if abs(n.z) < 0.8 else p.x
            fab.append((li, (u, p.z)))
    while len(me.uv_layers) > 0:
        me.uv_layers.remove(me.uv_layers[0])
    f = me.uv_layers.new(name="fabric")
    for li, uv in fab:
        f.data[li].uv = uv
    a = me.uv_layers.new(name="aocloth")
    for i, (aov, cw) in enumerate(vals):
        a.data[i].uv = (0.5 + 0.5 * aov, cw)


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def bake_ao(objs):
    """Cheap baked ambient occlusion per vertex (rest pose, every part against
    every other), stored in UV map "ao" as (ao, 1). The character shader
    darkens creases with it – underarms, collar, between the legs, inside the
    hood – so the forms read without textures or post-processing. (v = 1 flags
    meshes that carry it; anything without stays unshaded.)"""
    from mathutils.bvhtree import BVHTree
    import random
    def rest(ob):
        if "rest" in ob:
            r = list(ob["rest"])
            return Matrix([r[0:4], r[4:8], r[8:12], r[12:16]])
        return ob.matrix_world

    def tree_of(group):
        verts, polys = [], []
        for ob in group:
            mw = rest(ob)
            base = len(verts)
            verts += [mw @ v.co for v in ob.data.vertices]
            polys += [[base + i for i in p.vertices] for p in ob.data.polygons]
        return BVHTree.FromPolygons(verts, polys)

    # Open hands and fists overlap (only one shows): never shade each other.
    main = tree_of([o for o in objs if not o.name.endswith("_grip")])
    grip = tree_of([o for o in objs if not (o.name.startswith("hand_") and not o.name.endswith("_grip"))])
    rng = random.Random(7)
    dirs = []
    while len(dirs) < 28:
        d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))
        if 0.05 < d.length <= 1.0:
            dirs.append(d.normalized())
    for ob in objs:
        me = ob.data
        mw = rest(ob)
        tree = grip if ob.name.endswith("_grip") else main
        nm = mw.to_3x3().inverted().transposed()
        ao = []
        for v in me.vertices:
            p = mw @ v.co
            n = (nm @ v.normal).normalized()
            hit, tot = 0.0, 0.0
            for d in dirs:
                c = d.dot(n)
                if c <= 0.05:
                    continue
                tot += c
                loc, _, _, dist = tree.ray_cast(p + n * 0.004, d, 0.16)
                if loc is not None:
                    hit += c * (1.0 - dist / 0.16) ** 0.5
            ao.append(1.0 - hit / max(tot, 1e-6))
        uv = me.uv_layers.new(name="ao")
        for poly in me.polygons:
            for li in poly.loop_indices:
                uv.data[li].uv = (ao[me.loops[li].vertex_index], 1.0)


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
    emblem = M("emblem", (0.96, 0.74, 0.22), 0.5)
    ink = M("ink", (0.07, 0.07, 0.09), 0.6)
    cord = M("cord", (0.7, 0.68, 0.64), 0.85)
    mask_m = M("mask", (0.14, 0.14, 0.15), 0.8)
    lens_w = M("lens_white", (0.93, 0.93, 0.9), 0.25)
    outsole = M("outsole", (0.15, 0.14, 0.14), 0.9)

    # ================================================================ body
    # An athletic free-runner in a pullover hoodie and joggers: the anatomy is
    # under the clothes, so it reads through as broad shoulders, a lean waist
    # and long limbs, softened by fabric – relaxed hoodie body bloused over a
    # ribbed hem, dropped shoulders, roomy sleeves bunching above ribbed
    # cuffs, a kangaroo pocket; tapered joggers that bag a little at the knee
    # and gather into cuffs over the trainers. Folds are modelled as soft
    # ridges (the remesh merges them into the surface). Left and right are
    # deliberately not identical (cuffs, folds, cords).
    src = []  # painted source shapes; merged into one skin below

    # Pelvis and seat (joggers), up under the hoodie.
    src.append(K.paint(tube("pelvis", [
        ((0, 0, 0.84), 0.114, 0.088), ((0, 0, 0.88), 0.156, 0.108, -0.005), ((0, 0, 0.93), 0.166, 0.112, -0.01),
        ((0, 0, 0.99), 0.16, 0.106, -0.005), ((0, 0, 1.03), 0.15, 0.1)]), pants))
    for sx in (-1, 1):  # glutes
        src.append(K.paint(K.sphere("glute", 0.086, (sx * 0.066, -0.058, 0.905), None, 14, 10, (1.0, 0.82, 1.0)), pants))
    # Hoodie body: hem band at the hips, bloused just above it, falling
    # straight past the waist, filling out over chest and back and carried
    # past the shoulder joint (dropped shoulder).
    src.append(K.paint(tube("hoodie", [
        ((0, 0, 0.8), 0.17, 0.115, -0.006), ((0, 0, 0.81), 0.19, 0.14, -0.004), ((0, 0, 0.85), 0.198, 0.143, -0.002),
        ((0, 0, 0.9), 0.198, 0.146, 0.004), ((0, 0, 0.97), 0.206, 0.156, 0.006),
        ((0, 0, 1.05), 0.174, 0.135, 0.008), ((0, 0, 1.12), 0.18, 0.14, 0.01), ((0, 0, 1.19), 0.21, 0.156, 0.012),
        ((0, 0, 1.26), 0.226, 0.162, 0.014), ((0, 0, 1.33), 0.236, 0.166, 0.014), ((0, 0, 1.39), 0.232, 0.16, 0.01),
        ((0, 0, 1.44), 0.212, 0.144, 0.004), ((0, 0, 1.485), 0.17, 0.12), ((0, 0, 1.53), 0.12, 0.1)], segs=32), jacket))
    for sx in (-1, 1):
        side = "l" if sx < 0 else "r"
        # Chest and shoulder blades read softly through the jersey.
        src.append(K.paint(K.sphere("pec", 0.085, (sx * 0.078, 0.084, 1.35), None, 16, 10, (1.1, 0.55, 0.7)), jacket))
        src.append(K.paint(K.sphere("scapula", 0.075, (sx * 0.092, -0.1, 1.385), None, 12, 8, (1.0, 0.5, 1.15)), jacket))
        src.append(K.paint(tube("trap", [((sx * 0.035, -0.014, 1.53), 0.05, 0.058), ((sx * 0.13, -0.01, 1.51), 0.056, 0.06),
                                         ((sx * 0.205, 0.0, 1.49), 0.062, 0.062)], segs=14), jacket))
        # Dropped shoulder: the seam sits down the arm; the fabric rounds
        # over the deltoid rather than hugging it.
        # Dropped shoulder: the fabric slopes from the neckline over the joint
        # into the sleeve (a long, flattened ellipsoid along that slope).
        sh = K.sphere("shoulder", 1.0, (0, 0, 0), None, 16, 10, (0.13, 0.085, 0.075))
        sh.rotation_euler = (0, sx * 0.42, 0)
        sh.location = J["upper_arm_" + side] + Vector((-sx * 0.05, 0.0, -0.015))
        bpy.context.view_layer.update()
        src.append(K.paint(sh, jacket))
    # Fabric folds: blousing ridges over the hem band (front and back, offset
    # side to side), a diagonal drag fold from each armpit, and a soft roll
    # at the small of the back.
    for (x, y, z, sx_, sz_, rot) in ((0.05, 0.16, 0.86, 0.085, 0.011, 0.08), (-0.08, 0.158, 0.85, 0.07, 0.01, -0.12),
                                      
                                      (0.16, 0.09, 0.9, 0.05, 0.009, 0.5), (-0.165, 0.075, 0.89, 0.045, 0.009, -0.4),
                                      ):
        f = K.sphere("fold", 1.0, (0, 0, 0), None, 14, 8, (sx_, 0.016, sz_))
        f.rotation_euler = (0, rot, math.atan2(x, y) * 0.0)
        f.location = (x, y, z)
        bpy.context.view_layer.update()
        src.append(K.paint(f, jacket))
    for sx in (-1, 1):
        f = K.sphere("drag", 1.0, (0, 0, 0), None, 12, 8, (0.012, 0.012, 0.07))
        f.rotation_euler = (0.0, sx * 0.55, 0.0)
        f.location = (sx * 0.19, 0.085, 1.31)
        bpy.context.view_layer.update()
        src.append(K.paint(f, jacket))
    # Kangaroo pocket: a patch slightly proud of the front, narrower at the
    # top; its outline and side slits are stitched in paint_panels.
    pocket = K.box("utility_hem", (0.14, 0.022, 0.2), (-0.1, 0.15, 0.94), jacket_dk, bevel=0.012, segs=3)
    for v in pocket.data.vertices:
        v.co.x *= 1.0 - 0.12 * max(0.0, (v.co.z - 0.955) / 0.085)
    src.append(pocket)
    # Neckline: the hood joins the body in a soft rolled seam.
    src.append(K.paint(tube("neckline", [((0, -0.004, 1.5), 0.112, 0.1), ((0, 0.0, 1.535), 0.104, 0.094),
                                         ((0, 0.004, 1.56), 0.092, 0.084)], segs=24), jacket_dk))
    src.append(K.paint(tube("neck", [((0, 0.0, 1.52), 0.07, 0.066), ((0, 0.008, 1.59), 0.06, 0.06),
                                     ((0, 0.012, 1.65), 0.055, 0.057)], segs=16), jacket_dk))

    # Sleeves: roomy upper arm, the elbow felt through the fabric, forearm
    # sleeve bunching in uneven rolls above a ribbed cuff at the wrist. The
    # left cuff is pushed up a little further than the right.
    for side, sx in (("l", -1), ("r", 1)):
        a, e, w = J["upper_arm_" + side], J["forearm_" + side], J["hand_" + side]
        src.append(K.paint(tube("upper_arm", [
            (along(a, e, -0.42), 0.05, 0.05), (along(a, e, -0.22), 0.082, 0.084), (along(a, e, 0.0), 0.093, 0.094),
            (along(a, e, 0.15), 0.09, 0.094, 0.004), (along(a, e, 0.45), 0.084, 0.088, 0.006),
            (along(a, e, 0.72), 0.077, 0.08, 0.002), (along(a, e, 0.92), 0.071, 0.072), (along(a, e, 1.03), 0.07, 0.07)], segs=18), jacket))
        pushed = 0.06 if side == "l" else 0.0
        src.append(K.paint(tube("forearm", [
            (along(e, w, -0.05), 0.07, 0.07), (along(e, w, 0.14), 0.072, 0.07, 0.004), (along(e, w, 0.36), 0.067, 0.064),
            (along(e, w, 0.55 - pushed), 0.06, 0.057), (along(e, w, 0.63 - pushed), 0.066, 0.062),
            (along(e, w, 0.7 - pushed), 0.058, 0.055), (along(e, w, 0.77 - pushed), 0.064, 0.06),
            (along(e, w, 0.83 - pushed), 0.054, 0.05), (along(e, w, 0.86 - pushed), 0.048, 0.044)], segs=18), jacket))
        src.append(K.paint(tube("cuff", [(along(e, w, 0.84 - pushed), 0.046, 0.042), (along(e, w, 1.0 - pushed), 0.04, 0.036)],
                                segs=16), jacket_dk))
        if pushed > 0.0:  # the bare wrist between the pushed cuff and the glove
            src.append(K.paint(tube("wrist", [(along(e, w, 0.92), 0.033, 0.028), (along(e, w, 1.03), 0.033, 0.028)], segs=14), glove))

    # Joggers: fuller through the thigh, a little bag at the knee, creases
    # behind it, tapering into a gathered cuff that bunches over the ankle.
    for side, sx in (("l", -1), ("r", 1)):
        h, k, f = J["thigh_" + side], J["shin_" + side], J["foot_" + side]
        src.append(K.paint(tube("thigh", [
            (along(h, k, -0.02), 0.094, 0.11), (along(h, k, 0.12), 0.104, 0.122, 0.012), (along(h, k, 0.4), 0.104, 0.118, 0.018),
            (along(h, k, 0.7), 0.096, 0.104, 0.012), (along(h, k, 0.92), 0.084, 0.088, 0.004), (along(h, k, 1.0), 0.081, 0.085, 0.006)],
            segs=20), pants))
        src.append(K.paint(K.sphere("knee", 0.078, k + Vector((0, 0.022, 0)), None, 14, 10, (1.0, 1.08, 1.05)), pants))
        bunch = 0.012 if side == "r" else 0.0
        src.append(K.paint(tube("shin", [
            (along(k, f, 0.0), 0.08, 0.082), (along(k, f, 0.2), 0.08, 0.088, -0.014), (along(k, f, 0.42), 0.074, 0.08, -0.01),
            (along(k, f, 0.64), 0.064, 0.066, -0.004), (along(k, f, 0.74), 0.068 + bunch * 0.4, 0.07, -0.002),
            (along(k, f, 0.8), 0.06, 0.061), (along(k, f, 0.85), 0.065, 0.066 + bunch * 0.3),
            (along(k, f, 0.885), 0.057, 0.058)], segs=20), pants))
        src.append(K.paint(tube("ankle_cuff", [(along(k, f, 0.88), 0.056, 0.058), (along(k, f, 0.985), 0.053, 0.055)], segs=16), pants_dk))
        for kk, (dz, rot) in enumerate(((0.012, 0.25), (-0.014, -0.2))):
            c_ = K.sphere("knee_crease", 1.0, (0, 0, 0), None, 10, 6, (0.045, 0.008, 0.008))
            c_.rotation_euler = (0, rot * sx, 0)
            c_.location = k + Vector((sx * 0.006, -0.056, dz))
            bpy.context.view_layer.update()
            src.append(K.paint(c_, pants))
        # A soft fold across the front of the hip where the leg bends.
        c_ = K.sphere("hip_fold", 1.0, (0, 0, 0), None, 10, 6, (0.05, 0.009, 0.009))
        c_.rotation_euler = (0, -sx * 0.5, 0)
        c_.location = along(h, k, 0.16) + Vector((0, 0.112, 0))
        bpy.context.view_layer.update()
        src.append(K.paint(c_, pants))

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
    # Thin painted details can leave tiny disconnected shells after the
    # remesh; they'd float off the body once skinned, so drop them.
    bm = bmesh.new()
    bm.from_mesh(body.data)
    seen, drop = set(), []
    for v in bm.verts:
        if v in seen:
            continue
        comp, stack = [], [v]
        seen.add(v)
        while stack:
            x = stack.pop()
            comp.append(x)
            for e in x.link_edges:
                o = e.other_vert(x)
                if o not in seen:
                    seen.add(o)
                    stack.append(o)
        if len(comp) < 400:
            drop += comp
    bmesh.ops.delete(bm, geom=drop, context="VERTS")
    bm.to_mesh(body.data)
    bm.free()
    print("BODY dropped shell verts", len(drop))
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
    paint_panels(body, {"jacket": jacket, "jacket_dk": jacket_dk, "pants": pants, "pants_dk": pants_dk, "glove": glove, "mask": mask_m})
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

    def arm_rest(side, joint):
        # Part frame (arm along -Z) -> A-pose rest frame at `joint`.
        sx = -1 if side == "l" else 1
        return Matrix.Translation(J[joint]) @ Matrix.Rotation(-sx * ARM_A, 4, "Y")

    def part(name, objs, origin, rest=None):
        ob = K.join(name, objs, origin)
        # Where this part sits in the rest pose (for the AO bake).
        ob["rest"] = [v for row in (rest or Matrix.Translation(origin)) for v in row]
        K.bake_vertex_colors(ob)
        ob.location = (0, 0, 0)  # exported at the origin; Godot parents it to the pivot
        parts.append(ob)

    # ---- head: always masked. A smooth cowl over skull, jaw and cheekbones
    # (in the suit's dark shade, so it recolours with every suit), a soft
    # nose ridge under the fabric, and two angled eye lenses that glow in the
    # web colour, each set in an ink outline. No skin, hair or ears showing.
    hc = J["head"]
    o = lambda x, y, z: hc + Vector((x, y, z - 0.028))  # noqa: E731  (head sits a little lower on the neck)
    mask = mask_m
    head = []
    head.append(K.sphere("cranium", 0.098, o(0, -0.012, 0.135), mask, 24, 16, (0.9, 1.04, 1.0)))
    for pl in head[-1].data.polygons:
        pl.use_smooth = True
    head.append(K.smooth(K.paint(tube("face", [(o(0, 0.034, 0.03), 0.04, 0.042), (o(0, 0.03, 0.05), 0.068, 0.07),
                                                (o(0, 0.02, 0.095), 0.082, 0.086), (o(0, 0.01, 0.14), 0.086, 0.09)], segs=22), mask), 1))
    # A continuous tapered visor; no facial anatomy or protruding goggles.
    for scale,depth,mat_ in [(1.16,.108,ink),(1.0,.119,lens_w)]:
        bm=bmesh.new()
        outline=[(-.084,.012),(-.055,.025),(0,.019),(.055,.025),(.084,.012),(.071,-.012),(0,-.02),(-.071,-.012)]
        vs=[bm.verts.new(o(x*scale,depth-abs(x)*.24,.128+z*scale)) for x,z in outline]
        bm.faces.new(vs)
        bmesh.ops.solidify(bm,geom=bm.faces[:],thickness=.006)
        bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
        head.append(K.new_obj('visor',bm,mat_))
    for sx in [-1,1]:
        head.append(K.box('jaw_vent',(.022,.009,.007),o(sx*.047,.096,.069),metal,bevel=.002))
    part("head", head, hc)
    # The hood is its own part (same origin) so shop headwear can replace it.
    # Under the chin the hood's front edges wrap the throat and run into the
    # neckline: a soft cowl round the neck (part of the hood, so headwear
    # that replaces the hood takes it too).
    cowl = K.smooth(K.paint(tube("cowl", [((0, -0.01, 1.51), 0.135, 0.118), ((0, 0.0, 1.545), 0.118, 0.104, 0.006),
                                          ((0, 0.012, 1.575), 0.098, 0.09, 0.012), ((0, 0.018, 1.59), 0.086, 0.08, 0.014)],
                                     segs=22), jacket), 1)
    part("hood", [hood(o, jacket_dk, ink), cowl], hc)

    # ---- hood drawcords (ride the chest bone): two flat cords out of the
    # neckline eyelets, lying over the chest, metal aglets on the ends. The
    # left one hangs a little longer. Their ends carry cloth weight, so they
    # swing and lift with the wind like the hem (see character.gdshader).
    cc = J["chest"]
    cords = []
    # Layered courier vest, diagonal harness and twin skyline insignia.
    cords.append(K.box("vest_back", (.32,.045,.29), (0,-.167,1.34), gear, bevel=.04,segs=4))
    cords.append(K.box("vest_front", (.29,.035,.23), (0,.185,1.37), jacket_dk, bevel=.035,segs=4))
    for front in [-1,1]:
        pts=[Vector((-.14,front*.221,1.49)),Vector((.14,front*.221,1.22))]
        cords.append(K.paint(tube("diagonal_webbing",[(q,.022,.008) for q in pts],segs=8),strap))
        for sx in [-1,1]:
            pts=[Vector((sx*.10,front*.236,1.43)),Vector((0,front*.236,1.35)),Vector((sx*.10,front*.236,1.27))]
            cords.append(K.paint(tube("skyline_mark",[(q,.009,.004) for q in pts],segs=6),emblem))
    cords.append(K.box("buckle",(.048,.018,.035),(.015,.214,1.34),metal,bevel=.006))
    cords.append(K.box("utility_pouch",(.084,.055,.1),(-.1,.2,1.25),gear,bevel=.014))
    part("chest", cords, cc)

    # ---- web launcher gauntlet: rides the right forearm pivot (elbow origin,
    # arm along -Z, back of the forearm toward +Y like the hand's knuckles).
    # A sleeve shaped to the forearm with a low module on the back of the
    # wrist, the nozzle just behind the knuckles.
    gaunt = [K.smooth(K.paint(tube("gauntlet", [(Vector((0, 0.002, -0.12)), 0.05, 0.049), (Vector((0, 0.003, -0.17)), 0.046, 0.044),
                                                 (Vector((0, 0.003, -0.225)), 0.04, 0.036), (Vector((0, 0.002, -0.24)), 0.039, 0.035)],
                                     segs=18, front=Vector((0, 1, 0))), gear), 1),
             K.box("module", (0.05, 0.03, 0.085), (0, 0.045, -0.18), gear, bevel=0.012, segs=2),
             K.box("nozzle", (0.022, 0.026, 0.03), (0, 0.052, -0.236), strap, bevel=0.006),
             K.box("grip_tape", (0.054, 0.006, 0.014), (0, 0.062, -0.16), strap),
             K.paint(tube("strap_g", [(Vector((0, 0, -0.128)), 0.052, 0.051), (Vector((0, 0, -0.14)), 0.052, 0.051)], segs=16), strap)]
    part("forearm_r", gaunt, Vector((0, 0, 0)), arm_rest("r", "forearm_r"))

    # ---- hands: modelled pointing along the arm (-Z) in the rig's rest frame,
    # i.e. at the origin, then placed on the hand joint. Fingers in segments.
    def finger(x, length, curl, thick, mat_, base_y=0.0, splay=0.0):
        segs = []
        p = Vector((x, base_y, -0.075))
        d = Vector((math.sin(splay), 0, -1)).normalized()
        ang = 0.0
        for i, frac in enumerate((0.45, 0.32, 0.23)):
            ang += curl
            # Curl toward the palm (−Y; the knuckles / back of the hand are +Y).
            dd = Matrix.Rotation(-ang, 3, "X") @ d
            q = p + dd * length * frac
            ph = K.paint(tube("phal", [(p, thick, thick * 0.9), (q, thick * 0.88, thick * 0.82)], segs=8), mat_)
            for pl in ph.data.polygons:
                pl.use_smooth = True
            segs.append(ph)
            p = q
        return segs

    for side, sx in (("l", -1), ("r", 1)):
        hand0 = Vector((0, 0, 0))
        palm = K.smooth(K.paint(tube("palm", [(Vector((0, 0, 0.008)), 0.034, 0.026), (Vector((0, 0.002, -0.04)), 0.047, 0.025),
                                              (Vector((0, 0.004, -0.08)), 0.049, 0.021)], segs=14), glove), 1)
        open_ = [palm]
        for i in range(4):
            x = (i - 1.5) * 0.0225
            open_ += finger(x, 0.084 - abs(i - 1.2) * 0.011, 0.42, 0.0136, glove, 0.004, (i - 1.5) * 0.03)
        th = K.smooth(K.paint(tube("thumb_o", [(Vector((sx * -0.034, -0.012, -0.018)), 0.016, 0.015),
                                             (Vector((sx * -0.054, -0.03, -0.052)), 0.014, 0.013),
                                             (Vector((sx * -0.058, -0.04, -0.08)), 0.0122, 0.011)], segs=9), glove), 1)
        open_.append(th)
        part("hand_" + side, open_, hand0, arm_rest(side, "hand_" + side))
        fist = [K.smooth(K.paint(tube("fistpalm", [(Vector((0, 0, 0.008)), 0.035, 0.026), (Vector((0, -0.004, -0.045)), 0.048, 0.028),
                                                    (Vector((0, -0.01, -0.08)), 0.049, 0.03)], segs=14), glove), 1)]
        for i in range(4):
            x = (i - 1.5) * 0.0225
            fist += finger(x, 0.076, 1.25, 0.0135, glove, -0.01)
        # Knuckle guard across the back of the fist.
        fist.append(K.smooth(K.paint(tube("knuckles", [(Vector((-0.045, 0.03, -0.08)), 0.012, 0.009),
                                                        (Vector((0.045, 0.03, -0.08)), 0.012, 0.009)], segs=8), strap), 1))
        fist.append(K.smooth(K.paint(tube("thumb_g", [(Vector((sx * -0.034, -0.015, -0.025)), 0.014, 0.013),
                                                       (Vector((sx * -0.023, -0.042, -0.06)), 0.0125, 0.0115),
                                                       (Vector((sx * -0.006, -0.053, -0.075)), 0.011, 0.01)], segs=8), glove), 1))
        part("hand_%s_grip" % side, fist, hand0, arm_rest(side, "hand_" + side))

    # ---- trainers (rest frame of the foot pivot at the ankle; toes +Y): a
    # modern runner built in layers – knit upper with a padded collar and a
    # raised tongue, a white midsole that kicks up at heel and toe, a dark
    # rubber outsole, and overlays in the accent colour (heel counter,
    # eyestay, heel tab); flat laces across the instep. The left lace
    # has a loose loop hanging off it.
    for side, sx in (("l", -1), ("r", 1)):
        z0 = Vector((0, 0, 0))
        upper = K.smooth(K.paint(tube("shoe_upper", [
            (Vector((0, -0.084, -0.066)), 0.047, 0.036), (Vector((0, -0.054, -0.056)), 0.06, 0.058), (Vector((0, 0.0, -0.062)), 0.064, 0.061),
            (Vector((0, 0.07, -0.077)), 0.066, 0.049), (Vector((0, 0.142, -0.088)), 0.062, 0.035), (Vector((0, 0.194, -0.094)), 0.049, 0.025),
            (Vector((0, 0.22, -0.096)), 0.026, 0.015)], segs=18, front=Vector((0, 0, 1))), shoe), 1)
        collar_ = (K.paint(tube("shoe_collar", [(Vector((0, -0.016, -0.05)), 0.064, 0.068), (Vector((0, -0.022, -0.008)), 0.062, 0.066),
                                                       (Vector((0, -0.026, 0.004)), 0.058, 0.062)], segs=16), shoe))
        tongue = (K.paint(tube("tongue", [(Vector((0, 0.012, -0.004)), 0.026, 0.008), (Vector((0, 0.05, -0.045)), 0.028, 0.009),
                                                   (Vector((0, 0.1, -0.07)), 0.026, 0.008)], segs=10, front=Vector((0, 0, 1))), shoe))
        mid = K.smooth(K.paint(tube("midsole", [
            (Vector((0, -0.1, -0.096)), 0.04, 0.03), (Vector((0, -0.082, -0.104)), 0.062, 0.034), (Vector((0, 0.0, -0.108)), 0.07, 0.03),
            (Vector((0, 0.08, -0.11)), 0.072, 0.027), (Vector((0, 0.16, -0.108)), 0.066, 0.024), (Vector((0, 0.212, -0.1)), 0.046, 0.02),
            (Vector((0, 0.236, -0.09)), 0.018, 0.013)], segs=18, front=Vector((0, 0, 1))), shoe), 1)
        outs = (K.paint(tube("outsole", [
            (Vector((0, -0.096, -0.125)), 0.042, 0.007), (Vector((0, -0.076, -0.13)), 0.06, 0.008), (Vector((0, 0.0, -0.132)), 0.068, 0.008),
            (Vector((0, 0.08, -0.132)), 0.07, 0.008), (Vector((0, 0.16, -0.128)), 0.064, 0.008), (Vector((0, 0.212, -0.118)), 0.042, 0.007)],
            segs=16, front=Vector((0, 0, 1))), outsole))
        heel = (K.paint(tube("heel_counter", [(Vector((0, -0.096, -0.084)), 0.03, 0.026), (Vector((0, -0.07, -0.082)), 0.05, 0.03),
                                                       (Vector((0, -0.03, -0.086)), 0.057, 0.026)], segs=16, front=Vector((0, 0, 1))), sole))
        overlay = []
        eyestay = (K.paint(tube("eyestay", [(Vector((0, 0.005, -0.016)), 0.034, 0.012), (Vector((0, 0.06, -0.054)), 0.036, 0.012),
                                                     (Vector((0, 0.118, -0.077)), 0.03, 0.01)], segs=12, front=Vector((0, 0, 1)), cap=False), sole))
        laces = []
        for n_, (y_, z_) in enumerate(((0.025, -0.03), (0.05, -0.045), (0.075, -0.058), (0.1, -0.068))):
            lb = K.box("lace", (0.05, 0.007, 0.005), (0, y_, z_ + 0.012), strap)
            lb.rotation_euler = (math.radians(-35), 0, math.radians(8 if n_ % 2 else -8))
            bpy.context.view_layer.update()
            laces.append(lb)
        if side == "l":
            loop = (K.paint(tube("lace_loop", [(Vector((0.01, 0.022, -0.012)), 0.004, 0.003), (Vector((0.03, 0.03, -0.03)), 0.004, 0.003),
                                                        (Vector((0.036, 0.016, -0.05)), 0.004, 0.003)], segs=6), strap))
            laces.append(loop)
        tab = K.box("heel_tab", (0.026, 0.012, 0.045), (0, -0.088, -0.03), sole, bevel=0.005)
        part("foot_" + side, [upper, collar_, tongue, mid, outs, heel, eyestay, tab] + overlay + laces, z0,
             Matrix.Translation(J["foot_" + side]))

    bake_ao(parts + [body])
    # Cloth weights (UV map 2). Body: the hoodie hem and lower back move
    # most, the sleeves a little toward the cuffs, the jogger legs a touch
    # below the knee. Hood: the back and the drooping peak. Cords: their
    # free ends. Everything else 0.
    kj = tuple(jacket.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value[:3])
    kjd = tuple(jacket_dk.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value[:3])
    kp = tuple(pants.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value[:3])
    kpd = tuple(pants_dk.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value[:3])

    def is_(c, k):
        return max(abs(c[i] - k[i]) for i in range(3)) < 0.04

    def body_w(p, c):
        if is_(c, kj) or is_(c, kjd):
            if abs(p.x) < 0.27 and p.z < 1.2:
                return smoothstep(1.08, 0.8, p.z)
            if abs(p.x) >= 0.2 and p.z < 1.45:  # sleeves: freer toward the cuff
                return 0.35 * smoothstep(1.3, 0.95, p.z)
        if (is_(c, kp) or is_(c, kpd)) and p.z < 0.55:
            return 0.22 * smoothstep(0.55, 0.15, p.z)
        return 0.0

    cloth_uv(body, body_w)
    hc_ = J["head"] + Vector((0, -0.024, 0.11))
    for ob in parts:
        if ob.name == "hood":
            cloth_uv(ob, lambda p, c: 0.12 if p.z < 1.59 else 0.0,
                     Matrix.Translation(J["head"]))
        elif ob.name == "chest":
            cloth_uv(ob, lambda p, c: 0.0, Matrix.Translation(J["chest"]))
        else:
            cloth_uv(ob, lambda p, c: 0.0)
    # Repack for the shader (Godot reads two UV sets): UV = fabric coordinates
    # (metres on the rest-pose surface, for the knit), UV2 = (0.5 + 0.5 ao,
    # cloth weight). UV2.x < 0.25 means "no data" (shop gear).
    for ob in parts + [body]:
        _repack(ob, body if ob is body else None)

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
