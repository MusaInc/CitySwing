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
    """Fitted hood up over the masked head (rides the head bone). A close
    shell (~2 cm off the skull, not a helmet) whose front edge frames the
    face with a soft rolled brim over the brow; slightly fuller at the back
    with a small point behind the crown, and a cowl that falls round the neck
    and tucks into the collar. Gentle folds at the back; the opening's lip is
    piped in the dark suit shade."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=40, v_segments=26, radius=1.0)
    # Pole forward: the face opening is cut along one clean ring of latitude.
    bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(-math.pi / 2, 3, "X"))
    c = o(0, -0.016, 0.137)
    rad = Vector((0.111, 0.124, 0.117))
    drop = []
    for v in bm.verts:
        d = v.co.normalized()
        p = Vector((d.x * rad.x, d.y * rad.y, d.z * rad.z))
        back = max(-d.y, 0.0)
        front = max(d.y, 0.0)
        # A little fuller over the back of the head.
        p += Vector((d.x * 0.006, -0.016 * back, 0.008 * max(d.z, 0.0))) * (0.5 + back)
        # Small point behind the crown.
        tip = max(0.0, -d.y - 0.5) * max(0.0, d.z + 0.1)
        p += Vector((0, -0.03, -0.012)) * tip
        # Lower half: the cowl falls round the neck and into the collar.
        if d.z < 0.0:
            lo = -d.z
            p.z -= lo * (0.055 + 0.03 * back + 0.05 * front * lo)
            p.x *= 1.0 + 0.22 * lo
            p.y += 0.018 * front * lo - 0.012 * back * lo
        # Brim rolls a touch forward over the brow; the opening sits a little
        # low and narrow so it frames the mask.
        if d.y > 0.2 and d.z > 0.35:
            p.y += 0.012 * d.z
        if front > 0.0:
            p.z -= 0.022 * front
            p.x *= 1.0 - 0.08 * front
        # Soft folds (back and sides only).
        ang = math.atan2(d.x, -d.y)
        p += d * 0.0035 * math.sin(ang * 6.0 + d.z * 3.0) * back * (1.0 - abs(d.z))
        v.co = c + p
        if d.y > 0.58 or d.z < -0.92:
            drop.append(v)
    bmesh.ops.delete(bm, geom=drop, context="VERTS")
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.01)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = K.new_obj("hood", bm)
    ob.data.materials.append(material)
    ob.data.materials.append(rim_mat)
    # Piping round the face opening (the faces nearest the cut).
    for pl in ob.data.polygons:
        pl.use_smooth = True
        dd = (pl.center - c).normalized()
        pl.material_index = 1 if dd.y > 0.4 else 0
    return ob


def paint_panels(body, mats):
    """Suit construction on the merged skin, as exact palette keys (so shop
    recolours still apply): dark raglan yokes over the shoulders, dark side
    panels down the flanks and inner arms, a centre zip line, a thin seam
    round the waist, accent stripes down the outside of the legs, and dark
    knee panels. Decided from the rest-pose surface position of each corner."""
    import bmesh as _bm
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
            if near(c, key["jacket"]):
                torso = ax < 0.215 and 0.95 < z < 1.56
                if torso:
                    ang = math.degrees(math.atan2(y, ax))  # 0 = side, 90 = front, -90 = back
                    # Raglan yoke: a band from the collar out over the
                    # shoulder, front and back.
                    yoke = z > 1.47 - 0.35 * max(ax - 0.06, 0.0) and z > 1.4
                    side = -28.0 < ang < 22.0 and z < 1.43 and ax > 0.1
                    zip_ = ax < 0.0045 and y > 0.05 and 1.0 < z < 1.5
                    waist = 0.995 < z < 1.006
                    if yoke or side or zip_ or waist:
                        want = "jacket_dk"
                elif z > 1.0:
                    # Sleeves: the dark yoke carries down the top of the
                    # shoulder; a dark panel runs along the underside.
                    sh = Vector((math.copysign(0.2, x), 0.0, 1.5))
                    d = p - sh
                    adir = Vector((math.copysign(math.sin(ARM_A), x), 0.0, -math.cos(ARM_A)))
                    along_ = d.dot(adir)
                    rad = d - adir * along_
                    up = Vector((math.copysign(math.cos(ARM_A), x), 0.0, math.sin(ARM_A)))
                    if along_ < 0.07 and rad.dot(up) > 0.0:
                        want = "jacket_dk"
                    elif 0.05 < along_ < 0.5 and rad.normalized().dot(up) < -0.82:
                        want = "jacket_dk"
            elif near(c, key["pants"]) and z < 0.9:
                # Accent stripe down the outside of each leg.
                hip = Vector((math.copysign(0.1, x), 0.0, 0.94))
                ldir = Vector((math.copysign(math.sin(LEG_A), x), 0.0, -math.cos(LEG_A)))
                d = p - hip
                rad = d - ldir * d.dot(ldir)
                out = Vector((math.copysign(1.0, x), 0.0, 0.0))
                if rad.length > 1e-4 and rad.normalized().dot(out) > 0.975 and 0.12 < z < 0.86:
                    want = "jacket"
            if want:
                k = key[want]
                col.data[li].color = (k[0], k[1], k[2], col.data[li].color[3])


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

    # ================================================================ body
    # Athletic, not bulky: a free-runner's build – square shoulders, a broad
    # back narrowing to a trim waist, long lean limbs with real muscle shape
    # (deltoid, biceps/triceps, forearm taper, quads, calves, slim ankles).
    # Painted panels and seams are added on the merged surface (see paint_
    # panels below); raised piping here only where it should catch light.
    src = []  # painted source shapes; merged into one skin below

    # Pelvis and seat (trousers), up under the jacket hem.
    src.append(K.paint(tube("pelvis", [
        ((0, 0, 0.84), 0.11, 0.085), ((0, 0, 0.88), 0.152, 0.104, -0.005), ((0, 0, 0.93), 0.166, 0.11, -0.01),
        ((0, 0, 0.99), 0.16, 0.106, -0.005), ((0, 0, 1.03), 0.15, 0.1)]), pants))
    for sx in (-1, 1):  # glutes
        src.append(K.paint(K.sphere("glute", 0.085, (sx * 0.066, -0.056, 0.915), None, 14, 10, (1.0, 0.82, 1.0)), pants))
    # Torso: trim waist, ribcage widening into a deep chest and broad upper
    # back; the shoulders are carried square out to the deltoids.
    src.append(K.paint(tube("torso", [
        ((0, 0, 0.97), 0.158, 0.113), ((0, 0, 1.02), 0.142, 0.104), ((0, 0, 1.08), 0.141, 0.106, 0.004),
        ((0, 0, 1.15), 0.156, 0.116, 0.008), ((0, 0, 1.23), 0.182, 0.13, 0.014), ((0, 0, 1.31), 0.206, 0.141, 0.018),
        ((0, 0, 1.38), 0.216, 0.139, 0.016), ((0, 0, 1.44), 0.21, 0.125, 0.006), ((0, 0, 1.49), 0.18, 0.104),
        ((0, 0, 1.53), 0.105, 0.08)], segs=28), jacket))
    for sx in (-1, 1):
        side = "l" if sx < 0 else "r"
        # Pecs (low, square), lats (the V of the back), a hint of obliques.
        src.append(K.paint(K.sphere("pec", 0.09, (sx * 0.076, 0.082, 1.355), None, 16, 10, (1.08, 0.58, 0.74)), jacket))
        src.append(K.paint(K.sphere("lat", 0.104, (sx * 0.126, -0.038, 1.29), None, 14, 10, (0.62, 0.8, 1.38)), jacket))
        # Shoulder blades under the back of the suit.
        src.append(K.paint(K.sphere("scapula", 0.07, (sx * 0.09, -0.098, 1.39), None, 12, 8, (1.0, 0.55, 1.2)), jacket))
        src.append(K.paint(K.sphere("oblique", 0.07, (sx * 0.118, 0.015, 1.08), None, 12, 8, (0.55, 0.85, 1.25)), jacket))
        # Trapezius slope from neck to shoulder.
        src.append(K.paint(tube("trap", [((sx * 0.03, -0.014, 1.532), 0.048, 0.056), ((sx * 0.12, -0.012, 1.514), 0.052, 0.058),
                                         ((sx * 0.19, -0.002, 1.5), 0.056, 0.058)], segs=14), jacket))
        # Deltoid cap: rounds the shoulder past the joint.
        src.append(K.paint(K.sphere("deltoid", 0.079, J["upper_arm_" + side] + Vector((sx * 0.022, 0.004, 0.006)),
                                    None, 16, 10, (0.95, 1.1, 1.05)), jacket))
    # High suit collar: hides most of the neck, the cowl of the hood tucks in.
    src.append(K.paint(tube("collar", [((0, 0.0, 1.5), 0.096, 0.092), ((0, 0.004, 1.55), 0.087, 0.083),
                                       ((0, 0.008, 1.6), 0.079, 0.076), ((0, 0.01, 1.615), 0.076, 0.073)], segs=20), jacket_dk))
    src.append(K.paint(tube("neck", [((0, 0.0, 1.52), 0.07, 0.066), ((0, 0.008, 1.59), 0.06, 0.06),
                                     ((0, 0.012, 1.65), 0.055, 0.057)], segs=16), jacket_dk))
    # Chest emblem: a small sun with an ink swing-arc, set high on the chest
    # (it becomes colour on the skin).
    emb = K.cyl("emblem", 0.033, 0.024, (0, 0, 0), emblem, 24)
    emb.rotation_euler = (math.pi / 2 + 0.12, 0, 0)
    emb.location = (0, 0.157, 1.385)
    src.append(emb)
    arc = K.box("emblem_arc", (0.05, 0.03, 0.009), (0, 0.163, 1.385), ink)
    arc.rotation_euler = (0.12, 0.6, 0)
    src.append(arc)
    # Belt with a low-profile metal buckle.
    src.append(K.paint(tube("belt", [((0, 0, 0.962), 0.168, 0.12), ((0, 0, 0.99), 0.168, 0.119)], segs=28, cap=False), strap))
    src.append(K.box("buckle", (0.046, 0.016, 0.026), (0, 0.12, 0.976), metal, bevel=0.005))

    # Arms (sleeves) in the A-pose: deltoid into a full upper arm (biceps in
    # front, triceps behind), a defined elbow, forearm tapering to a slim,
    # slightly flattened wrist.
    for side, sx in (("l", -1), ("r", 1)):
        a, e, w = J["upper_arm_" + side], J["forearm_" + side], J["hand_" + side]
        src.append(K.paint(tube("upper_arm", [
            (along(a, e, -0.06), 0.068, 0.07), (along(a, e, 0.18), 0.062, 0.068, 0.004), (along(a, e, 0.45), 0.058, 0.066, 0.006),
            (along(a, e, 0.72), 0.052, 0.058, 0.002), (along(a, e, 0.92), 0.046, 0.05), (along(a, e, 1.02), 0.045, 0.048)], segs=18), jacket))
        src.append(K.paint(tube("forearm", [
            (along(e, w, -0.04), 0.046, 0.048), (along(e, w, 0.14), 0.051, 0.05, 0.004), (along(e, w, 0.38), 0.047, 0.043),
            (along(e, w, 0.7), 0.038, 0.034), (along(e, w, 0.92), 0.033, 0.028), (along(e, w, 1.02), 0.033, 0.028)], segs=18), jacket))
        src.append(K.paint(tube("cuff", [(along(e, w, 0.82), 0.038, 0.034), (along(e, w, 1.03), 0.037, 0.032)], segs=16), glove))
        # Low elbow guard on the point of the elbow.
        src.append(K.paint(K.sphere("elbow_pad", 0.034, e + Vector((0, -0.03, 0)), None, 12, 8, (1.0, 0.55, 1.2)), jacket_dk))

    # Legs (athletic joggers): quads in front, a defined knee, calf bulge
    # behind, slim ankles.
    for side, sx in (("l", -1), ("r", 1)):
        h, k, f = J["thigh_" + side], J["shin_" + side], J["foot_" + side]
        src.append(K.paint(tube("thigh", [
            (along(h, k, -0.08), 0.1, 0.108), (along(h, k, 0.12), 0.102, 0.113, 0.012), (along(h, k, 0.4), 0.093, 0.104, 0.02),
            (along(h, k, 0.7), 0.077, 0.084, 0.012), (along(h, k, 0.92), 0.064, 0.067), (along(h, k, 1.0), 0.06, 0.063)], segs=20), pants))
        src.append(K.paint(K.sphere("knee", 0.058, k + Vector((0, 0.012, 0)), None, 14, 10), pants))
        src.append(K.paint(tube("shin", [
            (along(k, f, 0.0), 0.06, 0.062), (along(k, f, 0.2), 0.064, 0.076, -0.02), (along(k, f, 0.42), 0.058, 0.067, -0.015),
            (along(k, f, 0.7), 0.046, 0.047, -0.003), (along(k, f, 0.88), 0.04, 0.042), (along(k, f, 0.99), 0.043, 0.046)], segs=20), pants))
        src.append(K.paint(tube("ankle_cuff", [(along(k, f, 0.86), 0.046, 0.048), (along(k, f, 0.99), 0.047, 0.05)], segs=16), pants_dk))
        # Knee guard: a flat reinforced panel over the front of the knee (in
        # the dark trouser shade – construction, not a target).
        src.append(K.paint(K.sphere("knee_pad", 0.05, k + Vector((0, 0.05, 0.012)), None, 14, 10, (1.05, 0.42, 1.25)), pants_dk))

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
    paint_panels(body, {"jacket": jacket, "jacket_dk": jacket_dk, "pants": pants, "pants_dk": pants_dk})
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
    mask = jacket_dk
    head = []
    head.append(K.sphere("cranium", 0.096, o(0, -0.012, 0.135), mask, 24, 16, (0.9, 1.04, 1.0)))
    for pl in head[-1].data.polygons:
        pl.use_smooth = True
    # Jaw and chin: a defined, slightly squared chin and cheekbones.
    head.append(K.smooth(K.paint(tube("face", [(o(0, 0.034, 0.03), 0.038, 0.04), (o(0, 0.03, 0.05), 0.066, 0.068),
                                                (o(0, 0.02, 0.095), 0.08, 0.084), (o(0, 0.01, 0.14), 0.084, 0.088)], segs=22), mask), 1))
    nose = K.paint(tube("nose", [(o(0, 0.088, 0.138), 0.01, 0.007), (o(0, 0.102, 0.108), 0.014, 0.01),
                                 (o(0, 0.104, 0.098), 0.017, 0.009), (o(0, 0.094, 0.09), 0.014, 0.006)], segs=10), mask)
    head.append(K.smooth(nose, 1))
    for sx in (-1, 1):
        # Lens: a flattened teardrop tilted up at the outer corner, on the
        # mask's surface; the ink rim sits just behind it and shows round it.
        for nm, mat_, sc, dy in (("lens_rim", ink, (0.041, 0.012, 0.028), 0.091), ("eye_lens", glow, (0.034, 0.01, 0.021), 0.095)):
            e = K.sphere(nm, 1.0, (0, 0, 0), mat_, 16, 10, sc)
            for v in e.data.vertices:
                # Teardrop: the outer corner sweeps up and to a point, the
                # inner edge is flat along the nose, the lower edge straight.
                u = v.co.x * sx / sc[0]
                if u > 0:
                    v.co.z += u * u * sc[2] * 0.7
                    v.co.x *= 1.0 + 0.25 * u
                if v.co.z < 0:
                    v.co.z *= 0.6
            e.rotation_euler = (0.15, -sx * 0.2, sx * -0.18)  # outer corner up
            e.location = o(sx * 0.037, dy, 0.124)
            bpy.context.view_layer.update()
            head.append(e)
    part("head", head, hc)
    # The hood is its own part (same origin) so shop headwear can replace it.
    part("hood", [hood(o, jacket, jacket_dk)], hc)

    # ---- spool on the back (rides the chest bone): a compact, rounded
    # housing between the shoulder blades.
    cc = J["chest"]
    spool = [K.box("housing", (0.17, 0.065, 0.16), cc + Vector((0, -0.145, 0.11)), gear, bevel=0.024, segs=3)]
    for sx in (-1, 1):
        d = K.cyl("drum", 0.05, 0.045, (0, 0, 0), gear, 20)
        d.rotation_euler = (0, math.pi / 2, 0)
        d.location = cc + Vector((sx * 0.112, -0.148, 0.12))
        r = K.cyl("ring", 0.052, 0.009, (0, 0, 0), glow, 20)
        r.rotation_euler = (0, math.pi / 2, 0)
        r.location = cc + Vector((sx * 0.138, -0.148, 0.12))
        spool += [d, r]
    spool.append(K.box("spool_strap", (0.15, 0.012, 0.02), cc + Vector((0, -0.112, 0.02)), strap))
    part("chest", spool, cc)

    # ---- web launcher gauntlet: rides the right forearm pivot (elbow origin,
    # arm along -Z, back of the forearm toward +Y like the hand's knuckles).
    # A sleeve shaped to the forearm with a low module on the back of the
    # wrist, the nozzle just behind the knuckles.
    gaunt = [K.smooth(K.paint(tube("gauntlet", [(Vector((0, 0.002, -0.12)), 0.05, 0.049), (Vector((0, 0.003, -0.17)), 0.046, 0.044),
                                                 (Vector((0, 0.003, -0.225)), 0.04, 0.036), (Vector((0, 0.002, -0.24)), 0.039, 0.035)],
                                     segs=18, front=Vector((0, 1, 0))), gear), 1),
             K.box("module", (0.05, 0.03, 0.085), (0, 0.045, -0.18), gear, bevel=0.012, segs=2),
             K.box("nozzle", (0.022, 0.026, 0.03), (0, 0.052, -0.236), metal, bevel=0.006),
             K.box("led", (0.034, 0.005, 0.01), (0, 0.061, -0.165), glow),
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
            dd = Matrix.Rotation(ang, 3, "X") @ d
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
        th = K.smooth(K.paint(tube("thumb_o", [(Vector((sx * -0.034, 0.012, -0.018)), 0.016, 0.015),
                                             (Vector((sx * -0.054, 0.03, -0.052)), 0.014, 0.013),
                                             (Vector((sx * -0.058, 0.04, -0.08)), 0.0122, 0.011)], segs=9), glove), 1)
        open_.append(th)
        part("hand_" + side, open_, hand0, arm_rest(side, "hand_" + side))
        fist = [K.smooth(K.paint(tube("fistpalm", [(Vector((0, 0, 0.008)), 0.035, 0.026), (Vector((0, 0.004, -0.045)), 0.048, 0.028),
                                                    (Vector((0, 0.01, -0.08)), 0.049, 0.03)], segs=14), glove), 1)]
        for i in range(4):
            x = (i - 1.5) * 0.0225
            fist += finger(x, 0.076, 1.25, 0.0135, glove, 0.01)
        # Knuckle guard across the back of the fist.
        fist.append(K.smooth(K.paint(tube("knuckles", [(Vector((-0.045, 0.03, -0.08)), 0.012, 0.009),
                                                        (Vector((0.045, 0.03, -0.08)), 0.012, 0.009)], segs=8), strap), 1))
        fist.append(K.smooth(K.paint(tube("thumb_g", [(Vector((sx * -0.034, 0.015, -0.025)), 0.014, 0.013),
                                                       (Vector((sx * -0.023, 0.042, -0.06)), 0.0125, 0.0115),
                                                       (Vector((sx * -0.006, 0.053, -0.075)), 0.011, 0.01)], segs=8), glove), 1))
        part("hand_%s_grip" % side, fist, hand0, arm_rest(side, "hand_" + side))

    # ---- trainers (rest frame of the foot pivot at the ankle; toes +Y): a
    # low, sleek runner – narrow heel counter, tapered toe with a little toe
    # spring, a midsole that wraps up at heel and toe, a dark lace panel and
    # a heel tab in the sole colour.
    for side, sx in (("l", -1), ("r", 1)):
        z0 = Vector((0, 0, 0))
        upper = K.smooth(K.paint(tube("shoe_upper", [
            (Vector((0, -0.078, -0.07)), 0.042, 0.032), (Vector((0, -0.05, -0.062)), 0.053, 0.054), (Vector((0, 0.0, -0.068)), 0.057, 0.057),
            (Vector((0, 0.07, -0.083)), 0.058, 0.044), (Vector((0, 0.14, -0.094)), 0.053, 0.029), (Vector((0, 0.19, -0.1)), 0.039, 0.018),
            (Vector((0, 0.21, -0.1)), 0.02, 0.01)], segs=16, front=Vector((0, 0, 1))), shoe), 1)
        collar_ = K.smooth(K.paint(tube("shoe_collar", [(Vector((0, -0.012, -0.055)), 0.055, 0.058), (Vector((0, -0.014, -0.01)), 0.052, 0.055)],
                                        segs=16), shoe), 1)
        so = K.smooth(K.paint(tube("sole", [
            (Vector((0, -0.09, -0.106)), 0.034, 0.016), (Vector((0, -0.072, -0.113)), 0.051, 0.02), (Vector((0, 0.0, -0.116)), 0.06, 0.018),
            (Vector((0, 0.08, -0.117)), 0.062, 0.017), (Vector((0, 0.16, -0.114)), 0.056, 0.016), (Vector((0, 0.207, -0.104)), 0.036, 0.013),
            (Vector((0, 0.225, -0.097)), 0.013, 0.008)], segs=16, front=Vector((0, 0, 1))), sole), 1)
        lace = K.smooth(K.paint(tube("laces", [(Vector((0, 0.02, -0.03)), 0.024, 0.01), (Vector((0, 0.08, -0.058)), 0.026, 0.01),
                                               (Vector((0, 0.125, -0.075)), 0.022, 0.008)], segs=10, front=Vector((0, 0, 1))), strap), 1)
        tab = K.box("heel_tab", (0.03, 0.014, 0.05), (0, -0.082, -0.05), sole, bevel=0.006)
        part("foot_" + side, [upper, collar_, so, lace, tab], z0, Matrix.Translation(J["foot_" + side]))

    bake_ao(parts + [body])

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
