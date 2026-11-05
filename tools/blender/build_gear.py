"""City Swing shop gear: headwear and face pieces for the hero.

Run:  blender -b --factory-startup --python tools/blender/build_gear.py -- assets/models

Output: gear.glb, one object per shop piece. Headwear/face items have their
origin at the head joint like the character's head and hood parts, so Godot
parents them straight onto the head pivot; gadget pieces are built in their
own bone's frame (CharacterRig.GEAR_BONES says which). Shapes are fitted to the head in
build_character.py (same J / head offset). Colours use the character palette
so character.gdshader recolours them: "jacket" follows the suit colour,
"gear_glow" follows the web colour; everything else is fixed.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import build_kit as K  # noqa: E402

OUT = K.OUT
# The head joint of the character's bind pose (build_character.py J["head"]).
# That builder exports the whole character at import time, so the two
# helpers gear needs live here instead of being imported from it.
HC = Vector((0, 0, 1.64))


def tube(name, rings, segs=20, cap=True, front=Vector((0, 1, 0))):
    """Loft along a polyline. rings: [(centre, rx, ry)] (rx across, ry front-back)."""
    bm = bmesh.new()
    loops = []
    pts = [Vector(r[0]) for r in rings]
    for i, (c, rx, ry, *_rest) in enumerate(rings):
        c = Vector(c)
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        f = (front - t * front.dot(t)).normalized()
        sd = f.cross(t).normalized()
        loops.append([bm.verts.new(c + sd * math.cos(k / segs * math.tau) * rx + f * math.sin(k / segs * math.tau) * ry)
                      for k in range(segs)])
    for r0, r1 in zip(loops, loops[1:]):
        for k in range(segs):
            j = (k + 1) % segs
            bm.faces.new((r0[k], r0[j], r1[j], r1[k]))
    if cap:
        for ring_ in (loops[0], loops[-1]):
            bm.faces.new(ring_)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return K.new_obj(name, bm)


def smooth_path(pts, n):
    """Catmull-Rom through pts, n points out."""
    pts = [Vector(p) for p in pts]
    out = []
    for k in range(n):
        u = k / (n - 1) * (len(pts) - 1)
        i = min(int(u), len(pts) - 2)
        t = u - i
        p0, p1, p2, p3 = pts[max(i - 1, 0)], pts[i], pts[i + 1], pts[min(i + 2, len(pts) - 1)]
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                          + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t))
    return out


class C:  # what the gear used from the old character builder
    J = {"head": HC}
    tube = staticmethod(tube)


def o(x, y, z):
    """Head-local point, matching build_character's head offset."""
    return HC + Vector((x, y, z - 0.028))


def shell(name, centre, rad, keep, material, thick=0.01, segs=32, rings=20):
    """Part of an ellipsoid (keep(d) on the unit direction) solidified into a shell."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    drop = []
    for v in bm.verts:
        d = v.co.normalized()
        v.co = centre + Vector((d.x * rad.x, d.y * rad.y, d.z * rad.z))
        if not keep(d):
            drop.append(v)
    bmesh.ops.delete(bm, geom=drop, context="VERTS")
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=thick)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = K.new_obj(name, bm)
    for pl in ob.data.polygons:
        pl.use_smooth = True
    return K.paint(ob, material)


def placed(ob, loc, rot):
    """Pose a part built round the origin (rotating geometry baked at its
    final spot would swing it round the world origin)."""
    ob.rotation_euler = rot
    ob.location = loc
    bpy.context.view_layer.update()  # else join() bakes the stale world matrix
    return ob


def ring(name, centre, r, tube_r, material, axis="Z", segs=28, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_torus_add(major_radius=r, minor_radius=tube_r, major_segments=segs, minor_segments=8,
                                     location=centre)
    ob = bpy.context.active_object
    ob.name = name
    if axis == "X":
        ob.rotation_euler = (0, math.pi / 2, 0)
    elif axis == "Y":
        ob.rotation_euler = (math.pi / 2, 0, 0)
    ob.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    for pl in ob.data.polygons:
        pl.use_smooth = True
    return K.paint(ob, material)


def build():
    K.reset()
    M = K.mat
    # Same names + colours as the character, so the baked keys match.
    jacket = M("jacket", (0.8, 0.1, 0.09), 0.7)
    jacket_dk = M("jacket_dark", (0.42, 0.05, 0.05), 0.75)
    strap = M("strap", (0.06, 0.06, 0.07), 0.6)
    gear = M("gear", (0.18, 0.2, 0.22), 0.4, 0.7)
    glow = M("gear_glow", (0.2, 0.95, 0.95), 0.3, 0.0, emit=(0.1, 0.9, 0.95))
    emblem = M("emblem", (0.96, 0.74, 0.22), 0.5)
    white = M("eye_white", (0.86, 0.84, 0.8), 0.3)
    lens = M("shade_lens", (0.03, 0.035, 0.05), 0.15)
    knit = M("knit", (0.92, 0.9, 0.84), 0.9)
    ruby = M("ruby", (0.75, 0.04, 0.12), 0.2)

    items = []

    def item(name, objs):
        ob = K.join(name, objs, HC)
        K.bake_vertex_colors(ob)
        ob.location = (0, 0, 0)
        items.append(ob)

    # Hair cap (build_character): centre o(0,-0.022,0.15), radii ~(0.095, 0.107, 0.1).
    hair_c = o(0, -0.022, 0.15)

    # ---- Cap: a six-panel crown hugging the hair, a curved peak, a button.
    crown = shell("cap_crown", hair_c + Vector((0, 0.0, 0.004)), Vector((0.104, 0.116, 0.1)),
                  lambda d: d.z > 0.14 * max(d.y, 0.0) - 0.32 * max(-d.y, 0.0) - 0.02, jacket, 0.008)
    bm = bmesh.new()  # peak: a curved half-disc out front (polar grid)
    nu, nr = 16, 4
    grid = []
    for j in range(nr + 1):
        row = []
        for i in range(nu + 1):
            a = math.pi * i / nu
            k = 0.35 + 0.65 * j / nr
            x, y = -math.cos(a) * k, math.sin(a) * k
            row.append(bm.verts.new(o(x * 0.098, 0.07 + y * 0.09, 0.18 - 0.02 * x * x + 0.006 * y)))
        grid.append(row)
    for j in range(nr):
        for i in range(nu):
            bm.faces.new([grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]])
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.008)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    peak = K.paint(K.new_obj("cap_peak", bm), jacket_dk)
    button = K.sphere("cap_button", 0.011, hair_c + Vector((0, 0.0, 0.104)), jacket_dk, 10, 6, (1, 1, 0.6))
    logo = placed(K.box("cap_logo", (0.03, 0.006, 0.022), (0, 0, 0), emblem, bevel=0.003),
                  o(0, 0.1, 0.2), (math.radians(-35), 0, 0))
    item("cap", [crown, peak, button, logo])

    # ---- Beanie: snug knit over the ears' tops, a folded cuff, a bobble.
    dome = shell("beanie_dome", hair_c + Vector((0, 0, 0.008)), Vector((0.106, 0.116, 0.112)),
                 lambda d: d.z > -0.08 - 0.1 * max(-d.y, 0.0), knit, 0.01)
    cuff = ring("beanie_cuff", hair_c + Vector((0, -0.002, -0.006)), 0.104, 0.016, knit, scale=(1.0, 1.1, 1.0))
    stripe = ring("beanie_stripe", hair_c + Vector((0, 0, 0.05)), 0.098, 0.006, jacket, scale=(0.95, 1.06, 1.0))
    bobble = K.sphere("beanie_bobble", 0.03, hair_c + Vector((0, -0.01, 0.13)), jacket, 14, 10)
    for pl in bobble.data.polygons:
        pl.use_smooth = True
    item("beanie", [dome, cuff, stripe, bobble])

    # ---- Headphones: padded band over the crown, big cups on the ears,
    # glowing rings (web colour).
    # The band follows the measured hair profile (CharacterRig.GEAR_FIT
    # moves this frame 6.8 cm forward and 3.2 cm down onto the real head):
    # ~1 cm off the hair all the way over, from cup to cup.
    prof = [(0.122, 0.112), (0.112, 0.16), (0.104, 0.2), (0.088, 0.236), (0.058, 0.262), (0.0, 0.274)]
    half = [o(x, -0.012, z) for x, z in prof]
    path = smooth_path(half + [o(-x, -0.012, z) for x, z in reversed(prof[:-1])], 33)
    band = C.tube("hp_band", [(p, 0.011, 0.016) for p in path], segs=10, front=Vector((0, 1, 0)))
    for pl in band.data.polygons:
        pl.use_smooth = True
    K.paint(band, strap)
    parts = [band]
    for sx in (-1, 1):
        # Cups sit outside the ear (the faces' ears reach x 0.13).
        cup = placed(K.cyl("hp_cup", 0.045, 0.032, (0, 0, -0.016), gear, 28), o(sx * 0.13, -0.008, 0.112), (0, math.pi / 2, 0))
        pad = placed(K.cyl("hp_pad", 0.041, 0.018, (0, 0, -0.009), strap, 28), o(sx * 0.112, -0.008, 0.112), (0, math.pi / 2, 0))
        yoke = C.tube("hp_yoke", [(o(sx * 0.124, -0.012, 0.15), 0.006, 0.006), (o(sx * 0.13, -0.012, 0.125), 0.006, 0.006)], segs=8)
        K.paint(yoke, gear)
        parts += [cup, pad, yoke, ring("hp_glow", o(sx * 0.147, -0.008, 0.112), 0.03, 0.0045, glow, axis="X")]
        for ob_ in (cup, pad):
            for pl in ob_.data.polygons:
                pl.use_smooth = True
    item("headphones", parts)

    # ---- Crown: a gold band with points and jewels, sat on the hair.
    bm = bmesh.new()
    n = 40
    for i in range(n):
        a = math.tau * i / n
        pt = 0.5 + 0.5 * math.cos(a * 7.0)  # seven points
        top = 0.05 + 0.05 * pt ** 3
        for z, rr in ((0.0, 1.0), (top, 0.96)):
            bm.verts.new(hair_c + Vector((math.sin(a) * 0.088 * rr, math.cos(a) * 0.1 * rr, 0.045 + z)))
    bm.verts.ensure_lookup_table()
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([bm.verts[2 * i], bm.verts[2 * j], bm.verts[2 * j + 1], bm.verts[2 * i + 1]])
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.007)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    band = K.paint(K.new_obj("crown_band", bm), emblem)
    jewels = []
    for i in range(7):
        a = math.tau * i / 7.0
        jewels.append(K.sphere("crown_jewel", 0.009, hair_c + Vector((math.sin(a) * 0.092, math.cos(a) * 0.105, 0.068)),
                               ruby, 8, 6))
        jewels.append(K.sphere("crown_tip", 0.008, hair_c + Vector((math.sin(a) * 0.084, math.cos(a) * 0.096, 0.148)),
                               emblem, 8, 6))
    item("crown", [band] + jewels)

    # ---- Shades: two dark lenses on a thin frame, arms back to the ears.
    eyes_z = 0.13
    frame = []
    for sx in (-1, 1):
        l = K.sphere("shade_lens", 0.026, o(sx * 0.037, 0.103, eyes_z), lens, 16, 8, (1.0, 0.28, 0.78))
        frame.append(l)
        frame.append(ring("shade_rim", o(sx * 0.037, 0.104, eyes_z), 0.026, 0.0035, strap, axis="Y", scale=(1.0, 1.0, 0.78)))
        frame.append(C.tube("shade_arm", [(o(sx * 0.064, 0.1, eyes_z + 0.004), 0.003, 0.003),
                                          (o(sx * 0.092, 0.03, eyes_z + 0.002), 0.003, 0.003),
                                          (o(sx * 0.094, -0.01, eyes_z - 0.014), 0.003, 0.003)], segs=6))
        K.paint(frame[-1], strap)
    frame.append(K.box("shade_bridge", (0.024, 0.006, 0.005), o(0, 0.108, eyes_z + 0.006), strap))
    item("shades", frame)

    # ---- Visor: one wraparound glowing band (web colour) on a dark frame.
    vis = shell("visor_band", o(0, -0.004, eyes_z + 0.003), Vector((0.098, 0.115, 0.06)),
                lambda d: d.y > 0.1 and abs(d.z) < 0.3, lens, 0.005, 40, 32)
    line = shell("visor_glow", o(0, -0.004, eyes_z + 0.003), Vector((0.1, 0.118, 0.06)),
                 lambda d: d.y > 0.2 and abs(d.z) < 0.045, glow, 0.003, 40, 64)
    rim = shell("visor_rim", o(0, -0.004, eyes_z + 0.024), Vector((0.1, 0.116, 0.012)),
                lambda d: d.y > -0.3 and abs(d.z) < 0.5, gear, 0.006, 40, 12)
    item("visor", [vis, line, rim])

    # (The bandana is a fitted mask in build_character.py: Mask_bandana.)

    # ================================================================ gadgets
    # Built in their bone's local frame (origin at the joint, Blender +Y =
    # the bone's front, +Z = up the bone), like the character's rigid parts.
    metal = M("metal", (0.55, 0.57, 0.6), 0.35, 0.8)
    flame = M("flame", (1.0, 0.62, 0.2), 0.3, 0.0, emit=(1.0, 0.5, 0.1))

    def gadget(name, objs):
        ob = K.join(name, objs, (0, 0, 0))
        K.bake_vertex_colors(ob)
        ob.location = (0, 0, 0)
        items.append(ob)

    # ---- Jet boots: a thruster pod against the back of each heel (foot
    # pivot = ankle; toes +Y; the trainer's heel is at y -0.056, its sole at
    # z -0.056, its collar at z +0.047), held by a strap round the ankle just above it.
    for side in ("l", "r"):
        pod = K.cyl("jet_pod", 0.024, 0.075, (0, -0.074, -0.025), gear, 18)
        cap = K.sphere("jet_cap", 0.024, (0, -0.074, 0.05), gear, 16, 8, (1, 1, 0.6))
        nozzle = K.cyl("jet_nozzle", 0.027, 0.018, (0, -0.074, -0.043), metal, 18, r2=0.02)
        band = K.cyl("jet_band", 0.0255, 0.007, (0, -0.074, 0.02), glow, 18)
        strap_ = ring("jet_strap", (0, 0.0, 0.062), 0.05, 0.007, strap, segs=32, scale=(0.96, 1.5, 1.0))
        for ob_ in (pod, nozzle, band):
            for pl in ob_.data.polygons:
                pl.use_smooth = True
        gadget("jet_" + side, [pod, cap, nozzle, band, strap_])
        # Cones wide at the nozzle (z -0.043), tips pointing down.
        f1 = K.cyl("jet_flame", 0.005, 0.24, (0, -0.074, -0.283), flame, 14, r2=0.03)
        f2 = K.cyl("jet_core", 0.003, 0.15, (0, -0.074, -0.193), glow, 10, r2=0.015)
        gadget("jet_%s_fire" % side, [f1, f2])

    # ---- Glider pack on the back (chest pivot; the spool housing reaches
    # y -0.19): two folded wing slats, and the open wings shown in a glide.
    folded = [K.box("glider_case", (0.2, 0.035, 0.07), (0, -0.11, 0.22), gear, bevel=0.012)]
    for sx in (-1, 1):
        slat = placed(K.box("glider_slat", (0.05, 0.016, 0.32), (0, 0, 0), jacket, bevel=0.008),
                      (sx * 0.1, -0.11, 0.07), (0, sx * math.radians(28), 0))
        folded.append(slat)
    # Harness: a strap from the pack over each shoulder to the chest.
    for sx in (-1, 1):
        hp = [(sx * 0.085, -0.1, 0.2), (sx * 0.09, -0.075, 0.27), (sx * 0.09, -0.01, 0.305), (sx * 0.088, 0.065, 0.28),
              (sx * 0.085, 0.11, 0.2)]
        folded.append(K.paint(C.tube("glider_harness", [(Vector(p), 0.012, 0.004) for p in smooth_path(hp, 12)], segs=8,
                                     front=Vector((sx, 0, 0))), strap))
    gadget("glider", folded)
    wings = [K.box("glider_case", (0.2, 0.035, 0.07), (0, -0.11, 0.22), gear, bevel=0.012)]
    for sx in (-1, 1):
        bm = bmesh.new()
        outline = [(0.06, 0.24), (0.45, 0.2), (0.86, 0.08), (0.8, 0.0), (0.55, -0.06), (0.3, -0.12), (0.08, -0.08)]
        vs = [bm.verts.new(Vector((sx * x, -0.11 - 0.12 * x * x, z))) for x, z in outline]
        bm.faces.new(vs if sx > 0 else list(reversed(vs)))
        bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.012)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        wings.append(K.paint(K.new_obj("glider_wing", bm), jacket))
        spar = C.tube("glider_spar", [(Vector((sx * 0.06, -0.111, 0.24)), 0.008, 0.008),
                                      (Vector((sx * 0.45, -0.135, 0.205)), 0.007, 0.007),
                                      (Vector((sx * 0.86, -0.2, 0.085)), 0.005, 0.005)], segs=6)
        wings.append(K.paint(spar, gear))
        wings.append(K.sphere("glider_tip", 0.012, (sx * 0.86, -0.2, 0.085), glow, 8, 6))
    gadget("glider_open", wings)

    # ---- Chrono watch on the left wrist (forearm pivot: elbow origin, arm
    # along -Z, back of the forearm +Y).
    watch = [K.paint(C.tube("chrono_strap", [(Vector((0, 0.002, -0.2)), 0.034, 0.035),
                                             (Vector((0, 0.002, -0.224)), 0.034, 0.035)], segs=20), strap),
             K.box("chrono_case", (0.04, 0.012, 0.04), (0, 0.04, -0.212), metal, bevel=0.005),
             K.box("chrono_face", (0.032, 0.004, 0.032), (0, 0.0465, -0.212), glow),
             K.box("chrono_crown", (0.008, 0.008, 0.007), (0.023, 0.04, -0.212), metal)]
    gadget("chrono", watch)

    # ---- Coin magnet clipped to the belt at the back of the right hip
    # (hips pivot; belt at z ~0, the seat's surface at y ~-0.1), hanging
    # prongs-down and facing back, where the chase camera sees it.
    cx, cy = 0.1, -0.118
    arc = [(Vector((cx + 0.034 * math.cos(a), cy, -0.045 + 0.034 * math.sin(a))), 0.013, 0.013)
           for a in [i * math.pi / 10 for i in range(11)]]
    shoe = K.paint(C.tube("magnet_arc", arc, segs=12, front=Vector((0, -1, 0))), ruby)
    mag = [shoe]
    for sx in (-1, 1):
        mag.append(K.cyl("magnet_prong", 0.013, 0.04, (cx + sx * 0.034, cy, -0.085), ruby, 12))
        mag.append(K.cyl("magnet_tip", 0.0135, 0.016, (cx + sx * 0.034, cy, -0.101), glow, 12))
    mag.append(K.box("magnet_clip", (0.016, 0.012, 0.05), (cx, cy + 0.008, -0.006), metal, bevel=0.003))
    for ob_ in mag:
        for pl in ob_.data.polygons:
            pl.use_smooth = True
    gadget("magnet", mag)

    bpy.ops.object.select_all(action="DESELECT")
    for it in items:
        it.select_set(True)
    path = os.path.join(OUT, "gear.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False,
                              export_yup=True, export_materials="EXPORT", export_vertex_color="ACTIVE")
    print("GEAR DONE", path, [it.name for it in items])


if __name__ == "__main__":
    build()
