"""People to be rescued: five figure types with wave / walk / climb / hoist poses, rendered from the side or 3/4.

Units: metres, figure faces +x, feet touch z = 0. Camera: orthographic, 64 px per metre, feet at 2 % above the bottom edge
so a sprite anchored at (0.5, 0.02) stands exactly on the surface.

Usage: blender -b -P art/people.py [-- --preview]
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *

PPM = 64
FW, FH = 1.9, 2.5
FOOT_V = 0.02

TYPES = [
    # name, scale, skin, hair, top, trousers, extras
    dict(name="helfer", s=1.00, skin=0xe0b08c, hair=0x3a281c, top=0xf08a1e, legs=0x2f3a4a, extra="vest"),
    dict(name="frau", s=0.94, skin=0xf0c4a0, hair=0x7a4a28, top=0x3f78a8, legs=0x3a3633, extra="pony"),
    dict(name="kind", s=0.64, skin=0xd49a72, hair=0x1c1612, top=0xd24a38, legs=0x4a5f8a, extra="none"),
    dict(name="opa", s=1.02, skin=0xc68a62, hair=0xd8d4cc, top=0x5a8a4e, legs=0x57514a, extra="cap"),
    dict(name="wanderer", s=1.06, skin=0x8a5a3c, hair=0x141010, top=0xe6c43a, legs=0x37425a, extra="pack"),
]


def ell(name, c, r, mt, parent):
    """ellipsoid with radii r=(x,y,z) at local centre c"""
    o = prim("sphere", name, (0, 0, 0), (r[0] * 2, r[1] * 2, r[2] * 2), mats=[mt], seg=20, rings=12)
    o.parent = parent
    o.location = c
    return o


def box(name, c, size, mt, parent, bevel=0.02):
    o = prim("cube", name, (0, 0, 0), size, mats=[mt], bevel=bevel)
    o.parent = parent
    o.location = c
    return o


def joint(name, parent, loc):
    e = bpy.data.objects.new(name, None)
    link(e)
    e.parent = parent
    e.location = loc
    return e


def build(t):
    reset()
    skin = mat("skin", t["skin"], rough=0.55)
    hair = mat("hair", t["hair"], rough=0.8)
    top = mat("top", t["top"], rough=0.7)
    legs = mat("legs", t["legs"], rough=0.75)
    shoe = mat("shoe", 0x2a2522, rough=0.7)
    refl = mat("refl", 0xe8e8d8, rough=0.4)
    s = t["s"]
    kid = t["name"] == "kind"
    root = joint("root", None, (0, 0, 0))
    root.scale = (s, s, s)
    hips = joint("hips", root, (0, 0, 0.93))
    ell("pelvis", (0, 0, 0.0), (0.12, 0.17, 0.13), legs, hips)
    chest = joint("chest", hips, (0, 0, 0.08))
    ell("torso", (0, 0, 0.27), (0.14 if not kid else 0.15, 0.21, 0.30), top, chest)
    ell("neck", (0, 0, 0.60), (0.05, 0.05, 0.07), skin, chest)
    head = joint("head", chest, (0, 0, 0.72))
    hs = 1.25 if kid else 1.0
    ell("skull", (0, 0, 0.09 * hs), (0.105 * hs, 0.095 * hs, 0.125 * hs), skin, head)
    ell("hair", (-0.025, 0, 0.14 * hs), (0.11 * hs, 0.10 * hs, 0.10 * hs), hair, head)
    if t["extra"] == "cap":
        ell("cap", (0.0, 0, 0.17), (0.115, 0.105, 0.07), mat("capm", 0xb4452d, rough=0.6), head)
        box("brim", (0.1, 0, 0.14), (0.12, 0.17, 0.02), mat("capm", 0xb4452d), head, 0.005)
    if t["extra"] == "pony":
        ell("pony", (-0.14, 0, 0.05), (0.06, 0.05, 0.13), hair, head)
    if t["extra"] == "vest":
        box("vstripe", (0.0, 0.0, 0.22), (0.30, 0.43, 0.05), refl, chest, 0.005)
    if t["extra"] == "pack":
        box("pack", (-0.19, 0, 0.30), (0.17, 0.30, 0.38), mat("pack", 0x3d8a7a, rough=0.8), chest, 0.04)
        ell("hood", (-0.08, 0, 0.62), (0.10, 0.12, 0.09), top, chest)
    # legs
    J = {"chest": chest, "head": head, "hips": hips}
    for side, sy in (("L", 0.095), ("R", -0.095)):
        hip = joint("hip" + side, hips, (0, sy, -0.02))
        ell("thigh" + side, (0, 0, -0.22), (0.075, 0.075, 0.235), legs, hip)
        knee = joint("knee" + side, hip, (0, 0, -0.45))
        ell("shin" + side, (0, 0, -0.22), (0.062, 0.062, 0.235), legs, knee)
        ank = joint("ankle" + side, knee, (0, 0, -0.45))
        box("shoe" + side, (0.06, 0, -0.035), (0.27, 0.11, 0.09), shoe, ank, 0.03)
        J["hip" + side], J["knee" + side], J["ankle" + side] = hip, knee, ank
        sh = joint("shoulder" + side, chest, (0, sy * 2.35, 0.50))
        ell("upper" + side, (0, 0, -0.14), (0.055, 0.055, 0.16), top, sh)
        el = joint("elbow" + side, sh, (0, 0, -0.29))
        ell("fore" + side, (0, 0, -0.13), (0.047, 0.047, 0.15), top, el)
        ell("hand" + side, (0, 0, -0.30), (0.05, 0.045, 0.06), skin, el)
        J["shoulder" + side], J["elbow" + side] = sh, el
    return J


def rot(o, x=0, y=0, z=0):
    o.rotation_euler = (math.radians(x), math.radians(y), math.radians(z))


def pose(J, kind, phase, yaw):
    """phase 0..1"""
    for k, o in J.items():
        rot(o)
    hips, chest, head = J["hips"], J["chest"], J["head"]
    two = 2 * math.pi * phase
    if kind == "walk":
        a = 32 * math.sin(two)
        for side, sg in (("L", 1), ("R", -1)):
            ph = two + (0 if side == "L" else math.pi)
            sw = 30 * math.sin(ph)
            rot(J["hip" + side], y=-sw)
            rot(J["knee" + side], y=max(0, -34 * math.cos(ph) + 6) * (1 if math.cos(ph) < 0.4 else 0.2) + (22 if math.sin(ph) < 0 else 0) * max(0, -math.cos(ph)))
            rot(J["ankle" + side], y=-(rot_y(J["hip" + side]) + rot_y(J["knee" + side])) * 0.5)
            rot(J["shoulder" + side], x=0, y=sw * 0.9 + 0)
            rot(J["elbow" + side], y=-(18 + max(0, math.sin(ph + math.pi)) * 18))
        rot(chest, y=-5)
        hips.location.z = 0.93 - 0.03 * (1 - abs(math.sin(two)))
    elif kind == "climb":
        lean = 14 + 6 * phase
        rot(chest, y=-lean)
        rot(J["hipL"], y=-(25 + 40 * phase)); rot(J["kneeL"], y=60 * phase + 20)
        rot(J["hipR"], y=8); rot(J["kneeR"], y=5)
        rot(J["shoulderL"], y=-(70 + 30 * phase)); rot(J["elbowL"], y=-30)
        rot(J["shoulderR"], y=-(40 - 30 * phase)); rot(J["elbowR"], y=-20)
        hips.location.z = 0.92 + 0.07 * phase
    elif kind == "wave":
        rot(J["shoulderR"], x=-(155 + 6 * math.sin(two)))
        rot(J["elbowR"], x=-(22 + 38 * math.sin(two * 1.0 + 1.0)))
        rot(J["shoulderL"], x=8, y=4)
        rot(chest, x=1.5 * math.sin(two), z=2 * math.sin(two))
        rot(head, z=4 * math.sin(two + 1))
        hips.location.z = 0.93
    elif kind == "stand":
        rot(J["shoulderR"], x=-6); rot(J["shoulderL"], x=6)
        rot(J["elbowR"], y=-14); rot(J["elbowL"], y=-14)
        hips.location.z = 0.93
    elif kind == "hoist":
        rot(J["shoulderL"], x=165); rot(J["shoulderR"], x=-165)
        rot(J["elbowL"], x=10); rot(J["elbowR"], x=-10)
        rot(J["hipL"], y=-10); rot(J["hipR"], y=6); rot(J["kneeL"], y=14); rot(J["kneeR"], y=6)
        hips.location.z = 0.93


def rot_y(o):
    return math.degrees(o.rotation_euler[1])


def lowest_z():
    bpy.context.view_layer.update()
    m = 9
    for o in bpy.data.objects:
        if o.type == "MESH" and o.name.startswith(("shoe", "shin", "thigh")):
            for c in o.bound_box:
                m = min(m, (o.matrix_world @ Vector(c)).z)
    return m


def main():
    preview = "--preview" in argv()
    only = [a for a in argv() if a.startswith("--type=")]
    anims = [("wave", 8, -62), ("stand", 1, -62), ("walk", 8, 0), ("climb", 4, 0), ("hoist", 1, -62)]
    for ti, t in enumerate(TYPES):
        if only and ("--type=%s" % t["name"]) not in only:
            continue
        J = build(t)
        setup_render(int(FW * PPM), int(FH * PPM), samples=20 if preview else 56)
        world(strength=1.0)
        cam = ortho_camera(width=FW)
        pivot = bpy.data.objects.new("pivot", None); link(pivot)
        sun("key", 4.2, (52, 0, -35), parent=pivot)
        sun("fill", 1.1, (70, 0, 140), color=(0.8, 0.88, 1.0), parent=pivot)
        sun("rim", 1.6, (115, 0, 200), parent=pivot)
        E = math.radians(8)
        target = Vector((0, 0, FH / 2 - FH * FOOT_V))
        cam.location = target + Vector((0, -30 * math.cos(E), 30 * math.sin(E)))
        aim(cam, target)
        root = bpy.data.objects["root"]
        # camera is at -y, so rotate the key light rig to match the helicopter lighting (rig sits at +x side there)
        pivot.rotation_euler = (0, 0, math.radians(-90))
        bpy.context.view_layer.update()
        for kind, n, yaw in anims:
            for i in range(n):
                pose(J, kind, i / n, yaw)
                root.rotation_euler = (0, 0, math.radians(yaw))
                root.location = (0, 0, 0)
                dz = -lowest_z() * 1.0
                root.location.z = dz if kind != "hoist" else 0.15
                bpy.context.view_layer.update()
                cam.data.shift_y = 0
                if kind == "hoist":
                    cam.data.shift_y = 0
                render(os.path.join(OUT, "people", "%s-%s-%d.png" % (t["name"], kind, i)))
    meta = {"ppm": PPM, "frameW": FW, "frameH": FH, "footV": FOOT_V, "types": [t["name"] for t in TYPES],
            "anims": {k: n for k, n, _ in anims}}
    json.dump(meta, open(os.path.join(OUT, "people", "meta.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
