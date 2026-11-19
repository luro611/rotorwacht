"""Rescue helicopter "RW-1": twin-engine, ducted tail rotor (fenestron), red and white, hoist, searchlight, skids.

Own design, no real-world markings. Units: metres. x = forward (nose), y = left, z = up. Skids touch z = 0.

Renders layers for several yaw angles (camera turns around the helicopter, lights turn with it):
  body, rotor (blades at rest), rotorblur (spinning disc), tailblur (fan disc)
and writes anchors.json with projected positions of hub, lights, hoist and skid contact.

Usage: blender -b -P art/helicopter.py [-- --preview]
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *

PPM = 64            # pixels per metre in the render (game draws it at 16 pt per metre)
FRAME_W, FRAME_H = 13.2, 5.0   # metres, same canvas for every yaw
YAWS = [-90, -70, -45, -22, 0, 22, 45, 70, 90]   # camera angle: 0 = looking at the nose, 90 = looking at the right side (nose points right)
ELEV = 7.0

RED, RED_DK, WHITE, GREY, DARK = 0xc9452b, 0x9e3320, 0xf2eee6, 0x8d8a84, 0x2a2826


def interp(sections, n):
    """Catmull-Rom through (x, hw, zc, hh) control sections -> n smooth sections."""
    out = []
    m = len(sections)
    for k in range(n):
        t = k / (n - 1) * (m - 1)
        i = min(int(t), m - 2)
        f = t - i
        p0, p1, p2, p3 = sections[max(i - 1, 0)], sections[i], sections[i + 1], sections[min(i + 2, m - 1)]
        row = []
        for c in range(4):
            a, b, cc, d = p0[c], p1[c], p2[c], p3[c]
            row.append(0.5 * ((2 * b) + (-a + cc) * f + (2 * a - 5 * b + 4 * cc - d) * f * f + (-a + 3 * b - 3 * cc + d) * f ** 3))
        out.append(row)
    return out



def paint_material():
    """Red/white paint and glass, all procedural in object space so the edges stay sharp at any size."""
    m = bpy.data.materials.new("fuselage_paint")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    def bsdf(color, rough, coat=0.0, metal=0.0):
        n = nt.nodes.new("ShaderNodeBsdfPrincipled")
        n.inputs["Base Color"].default_value = srgb(color)
        n.inputs["Roughness"].default_value = rough
        n.inputs["Metallic"].default_value = metal
        n.inputs["Coat Weight"].default_value = coat
        return n
    red, white, glass = bsdf(RED, 0.28, 0.6), bsdf(WHITE, 0.3, 0.5), bsdf(0x4c6d82, 0.08, 1.0, 0.2)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    X, Y, Z = sep.outputs[0], sep.outputs[1], sep.outputs[2]
    def math(op, a, b=None, clamp=False):
        n = nt.nodes.new("ShaderNodeMath")
        n.operation = op
        n.use_clamp = clamp
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = v
            else:
                nt.links.new(v, n.inputs[i])
        return n.outputs[0]
    def step(v, edge, soft=0.012, invert=False):
        """smooth 0/1 switch at edge (1 above the edge unless inverted)"""
        t = math("DIVIDE", math("SUBTRACT", v, edge), soft)
        t = math("ADD", t, 0.5, clamp=True)
        return math("SUBTRACT", 1.0, t) if invert else t
    def ellipse(cx, cz, a, b):
        dx = math("DIVIDE", math("SUBTRACT", X, cx), a)
        dz = math("DIVIDE", math("SUBTRACT", Z, cz), b)
        d = math("ADD", math("MULTIPLY", dx, dx), math("MULTIPLY", dz, dz))
        return step(d, 1.0, 0.06, invert=True)
    # white roof (above a line that sinks slightly towards the tail) and belly, white tail tip
    roofline = math("SUBTRACT", 2.50, math("MULTIPLY", math("SUBTRACT", X, 0.0), 0.05))
    roof = step(math("SUBTRACT", Z, roofline), 0.0)
    belly = step(math("SUBTRACT", Z, math("ADD", 0.86, math("MULTIPLY", X, 0.06))), 0.0, invert=True)
    tip = step(X, -5.55, invert=True)
    wmask = math("MAXIMUM", math("MAXIMUM", roof, belly), tip)
    # cockpit and cabin windows
    cockpit = ellipse(1.95, 1.72, 1.35, 0.52)
    cabin = math("MULTIPLY", ellipse(-0.45, 1.78, 0.62, 0.34), step(math("ABSOLUTE", Y), 0.55))
    gmask = math("MAXIMUM", cockpit, cabin)
    stripe = math("MULTIPLY", math("MULTIPLY", step(Z, 0.98), step(Z, 1.16, invert=True)), step(X, 2.0, invert=True))
    wmask = math("MAXIMUM", wmask, stripe)
    mix1 = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(wmask, mix1.inputs[0])
    nt.links.new(red.outputs[0], mix1.inputs[1]); nt.links.new(white.outputs[0], mix1.inputs[2])
    mix2 = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(gmask, mix2.inputs[0])
    nt.links.new(mix1.outputs[0], mix2.inputs[1]); nt.links.new(glass.outputs[0], mix2.inputs[2])
    nt.links.new(mix2.outputs[0], out.inputs["Surface"])
    return m

def fuselage(m_paint):
    ctrl = [
        (3.55, 0.04, 1.15, 0.04), (3.42, 0.45, 1.18, 0.45), (2.7, 0.86, 1.28, 0.78), (1.7, 1.06, 1.45, 1.0),
        (0.3, 1.16, 1.55, 1.12), (-1.1, 1.10, 1.62, 1.06), (-1.9, 0.80, 1.78, 0.78),
        (-3.1, 0.46, 1.96, 0.46), (-5.3, 0.30, 2.10, 0.30), (-6.2, 0.22, 2.16, 0.22), (-6.4, 0.06, 2.16, 0.06)]
    secs = interp(ctrl, 46)
    NA = 28
    bm = bmesh.new()
    rings = []
    for (x, hw, zc, hh) in secs:
        ring = []
        for j in range(NA):
            a = 2 * math.pi * j / NA
            ca, sa = math.cos(a), math.sin(a)
            # superellipse, a bit boxy at the cabin
            e = 2.0 / 2.6
            y = hw * math.copysign(abs(ca) ** e, ca)
            z = zc + hh * math.copysign(abs(sa) ** e, sa)
            ring.append(bm.verts.new((x, y, z)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for j in range(NA):
            f = bm.faces.new((rings[i][j], rings[i][(j + 1) % NA], rings[i + 1][(j + 1) % NA], rings[i + 1][j]))
    mats = [m_paint]
    o = mesh_obj("fuselage", bm, mats)
    for f in o.data.polygons: f.material_index = 0
    smooth(o, subsurf=1)
    return o


def build():
    reset()
    m_red = mat("paint_red", RED, rough=0.28, coat=0.6)
    m_red_dk = mat("paint_red_dk", RED_DK, rough=0.4)
    m_white = mat("paint_white", WHITE, rough=0.3, coat=0.5)
    m_glass = mat("glass", 0x1c2a33, rough=0.06, metal=0.0, coat=1.0)
    m_dark = mat("dark", DARK, rough=0.6)
    m_grey = mat("grey", GREY, rough=0.35, metal=0.8)
    m_rubber = mat("rubber", 0x1d1c1b, rough=0.85)
    m_blade = mat("blade", 0x252321, rough=0.5)
    m_tip = mat("tip", 0xe9c85a, rough=0.5)
    L = {"body": [], "rotor": [], "rotorblur": [], "tailblur": []}

    fus = fuselage(paint_material())
    L["body"].append(fus)

    # Engine cowlings and roof fairing
    roof = prim("sphere", "roof", (-0.5, 0, 2.6), (3.0, 1.15, 0.4), mats=[m_white])
    L["body"].append(roof)
    for sgn in (-1, 1):
        L["body"].append(prim("sphere", "cowl", (-0.7, 0.42 * sgn, 2.85), (2.1, 0.62, 0.42), mats=[m_white]))
        L["body"].append(prim("cyl", "exhaust", (-1.85, 0.42 * sgn, 2.9), (0.26, 0.26, 0.5), rot=(0, 90, 0), mats=[m_dark]))
    # Mast and rotor head
    L["body"].append(prim("cyl", "mast", (0.0, 0, 3.15), (0.3, 0.3, 0.9), mats=[m_dark]))
    L["body"].append(prim("cyl", "hub", (0.0, 0, 3.6), (0.62, 0.62, 0.2), mats=[m_grey]))
    L["body"].append(prim("cyl", "hubtop", (0.0, 0, 3.74), (0.34, 0.34, 0.1), mats=[m_dark]))

    # Tail: ducted fan in the fin (built around an empty, axis = local z, turned to point sideways)
    fan_c = Vector((-6.05, 0, 3.0))
    grp = bpy.data.objects.new("fangrp", None)
    link(grp)
    grp.location = fan_c
    grp.rotation_euler = (math.radians(90), 0, 0)
    def child(o):
        o.parent = grp
        o.location = (0, 0, 0)
        L["body"].append(o)
        return o
    sh = prim("torus", "shroud", (0, 0, 0), (1.5, 1.5, 1.0), mats=[m_red], minor=0.085)
    child(sh)
    child(prim("cyl", "fanback", (0, 0, 0), (1.36, 1.36, 0.05), mats=[m_dark]))
    child(prim("cyl", "fanhub", (0, 0, 0), (0.42, 0.42, 0.3), mats=[m_grey]))
    for k in range(11):
        a = 2 * math.pi * k / 11
        bl = prim("cube", "fanblade", (0, 0, 0), (0.58, 0.13, 0.03), mats=[m_blade])
        bl.parent = grp
        bl.location = (math.cos(a) * 0.46, math.sin(a) * 0.46, 0.0)
        bl.rotation_euler = (math.radians(25), 0, a)
        L["body"].append(bl)
    def slab(name, pts, thick, mt):
        bmf = bmesh.new()
        vs = [bmf.verts.new((x, -thick / 2, z)) for x, z in pts] + [bmf.verts.new((x, thick / 2, z)) for x, z in pts]
        n = len(pts)
        bmf.faces.new(vs[:n][::-1]); bmf.faces.new(vs[n:])
        for i in range(n):
            bmf.faces.new((vs[i], vs[(i + 1) % n], vs[n + (i + 1) % n], vs[n + i]))
        o = mesh_obj(name, bmf, [mt])
        smooth(o, bevel=0.04)
        L["body"].append(o)
        return o
    slab("finlow", [(-4.7, 2.0), (-5.45, 2.0), (-5.4, 3.35), (-5.0, 3.0)], 0.26, m_red)
    slab("fintop", [(-5.45, 3.55), (-6.15, 4.35), (-6.95, 4.3), (-6.95, 3.5), (-6.7, 3.4)], 0.26, m_red)
    L["body"].append(prim("cube", "fintip", (-6.7, 0, 4.2), (0.5, 0.3, 0.18), mats=[m_white], bevel=0.03))
    # horizontal stabiliser
    L["body"].append(prim("cube", "stab", (-4.5, 0, 2.2), (0.7, 2.0, 0.07), mats=[m_red], bevel=0.02))
    for sgn in (-1, 1):
        L["body"].append(prim("cube", "stabend", (-4.5, 1.0 * sgn, 2.4), (0.7, 0.05, 0.5), mats=[m_red], bevel=0.02))

    # Skids
    sk_y = 1.3
    for sgn in (-1, 1):
        pts = [(-2.0, sgn * sk_y, 0.1), (-1.8, sgn * sk_y, 0.07), (1.5, sgn * sk_y, 0.07), (2.2, sgn * sk_y, 0.1), (2.7, sgn * sk_y, 0.42)]
        L["body"].append(tube("skid", pts, 0.075, m_dark))
        # cross tubes
        for xc in (1.15, -0.85):
            L["body"].append(tube("strut", [(xc, sgn * sk_y, 0.1), (xc, sgn * 0.85, 0.6), (xc, sgn * 0.7, 0.75)], 0.06, m_grey))
    # step / footplate
    # Rescue hoist on the starboard side (y negative)
    L["body"].append(prim("cube", "hoistarm", (0.35, -1.38, 2.55), (0.9, 0.34, 0.16), mats=[m_grey], bevel=0.03))
    L["body"].append(prim("cyl", "hoistdrum", (0.6, -1.5, 2.55), (0.3, 0.3, 0.3), rot=(90, 0, 0), mats=[m_dark]))
    L["body"].append(prim("cyl", "cable", (0.85, -1.5, 2.35), (0.025, 0.025, 0.35), mats=[m_dark]))
    L["body"].append(prim("sphere", "hook", (0.85, -1.5, 2.12), (0.16, 0.16, 0.16), mats=[m_tip]))
    # Searchlight under the nose and nose sensor ball
    L["body"].append(prim("sphere", "searchlight", (2.55, 0.0, 0.72), (0.5, 0.5, 0.45), mats=[m_dark]))
    L["body"].append(prim("cyl", "lens", (2.78, 0, 0.74), (0.34, 0.34, 0.05), rot=(0, 90, 0),
                          mats=[mat("lamp", 0xfff2c8, rough=0.1, emit=0xfff2c8, strength=14)]))
    # Nav lights: port (left, y+) red, starboard green, tail white, belly strobe
    lights = {}
    def lamp(name, p, col, r=0.09):
        L["body"].append(prim("sphere", name, p, (r * 2, r * 2, r * 2), mats=[mat("l_" + name, col, emit=col, strength=18)]))
        lights[name] = p
    lamp("navPort", (1.0, 1.18, 1.0), 0xff2a1a)
    lamp("navStar", (1.0, -1.18, 1.0), 0x28ff55)
    lamp("tailLight", (-6.95, 0, 3.7), 0xffffff, 0.08)
    lamp("strobe", (-0.6, 0, 0.5), 0xff3a2a, 0.1)
    lamp("strobeTop", (-2.4, 0, 3.2), 0xffffff, 0.08)

    # Main rotor: 4 blades at rest, plus translucent blur disc
    R = 5.2
    for k in range(4):
        az = 18 + 90 * k
        b = prim("cube", "blade", (0, 0, 3.58), (R, 0.34, 0.05), mats=[m_blade], bevel=0.01)
        b.location = (math.cos(math.radians(az)) * (R / 2 + 0.3), math.sin(math.radians(az)) * (R / 2 + 0.3), 3.58)
        b.rotation_euler = (0, 0, math.radians(az))
        L["rotor"].append(b)
        tipb = prim("cube", "bladetip", (0, 0, 3.58), (0.55, 0.35, 0.052), mats=[m_tip])
        tipb.location = (math.cos(math.radians(az)) * (R + 0.02), math.sin(math.radians(az)) * (R + 0.02), 3.58)
        tipb.rotation_euler = (0, 0, math.radians(az))
        L["rotor"].append(tipb)
    L["rotorblur"].append(disc("rotorblur", (0, 0, 3.58), R + 0.3, 0xdfe4e6))
    L["tailblur"].append(disc("tailblur", fan_c, 0.68, 0xdfe4e6, axis_y=True, strength=0.3))

    anchors = {
        "hub": (0, 0, 3.6), "tailHub": tuple(fan_c), "searchlight": (2.8, 0, 0.74), "hook": (0.85, -1.5, 2.1),
        "contact": (0.2, 0, 0.0), **lights,
    }
    return L, anchors


def disc(name, c, r, color, axis_y=False, strength=0.8):
    bm = bmesh.new()
    segs = 64
    cv = bm.verts.new((0, 0, 0))
    vs = [bm.verts.new((math.cos(2 * math.pi * i / segs) * r, math.sin(2 * math.pi * i / segs) * r, 0)) for i in range(segs)]
    for i in range(segs):
        bm.faces.new((cv, vs[i], vs[(i + 1) % segs]))
    o = mesh_obj(name, bm)
    o.location = c
    if axis_y:
        o.rotation_euler = (math.radians(90), 0, 0)
    m = bpy.data.materials.new(name + "_m")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    mix = nt.nodes.new("ShaderNodeMixShader")
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = srgb(color)
    em.inputs["Strength"].default_value = 1.0
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1 / (2 * r),) * 3
    mp.inputs["Location"].default_value = (0.5, 0.5, 0)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    gr = nt.nodes.new("ShaderNodeTexGradient")
    gr.gradient_type = "SPHERICAL"
    nt.links.new(mp.outputs["Vector"], gr.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    # spherical gradient: 1 at centre, 0 at radius 0.5 -> invert so the rim is a little denser
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (0, 0, 0, 1)
    ramp.color_ramp.elements[1].position = 1.0
    ramp.color_ramp.elements[1].color = (0.0, 0.0, 0.0, 1)
    e = ramp.color_ramp.elements.new(0.08); e.color = (strength * 0.75, ) * 3 + (1,)
    e = ramp.color_ramp.elements.new(0.55); e.color = (strength * 0.55, ) * 3 + (1,)
    e = ramp.color_ramp.elements.new(0.9); e.color = (strength * 0.35, ) * 3 + (1,)
    nt.links.new(gr.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], mix.inputs["Fac"])
    nt.links.new(tr.outputs["BSDF"], mix.inputs[1])
    nt.links.new(em.outputs["Emission"], mix.inputs[2])
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    o.data.materials.append(m)
    return o


def show(L, which):
    for k, objs in L.items():
        for o in objs:
            o.hide_render = k not in which
            o.hide_viewport = o.hide_render


def main():
    preview = "--preview" in argv()
    L, anchors = build()
    setup_render(int(FRAME_W * PPM), int(FRAME_H * PPM), samples=24 if preview else 96)
    world(strength=1.0)
    cam = ortho_camera(width=FRAME_W)
    pivot = bpy.data.objects.new("pivot", None)
    link(pivot)
    # Lights turn with the camera so every yaw is lit the same way (key from upper left, soft fill, rim).
    sun("key", 4.2, (52, 0, -35), parent=pivot)
    sun("fill", 1.1, (70, 0, 140), color=(0.8, 0.88, 1.0), parent=pivot)
    sun("rim", 1.6, (115, 0, 200), parent=pivot)
    target = Vector((-0.85, 0, 1.85))
    meta = {"ppm": PPM, "frameW": FRAME_W, "frameH": FRAME_H, "yaws": YAWS, "frames": {}}
    dist, E = 60.0, math.radians(ELEV)
    foot = [(x, y, 0.0) for x in (-2.0, 2.7) for y in (-1.3, 1.3)]
    for yaw in YAWS:
        f = math.radians(yaw)
        pivot.rotation_euler = (0, 0, -f)
        cam.location = target + Vector((dist * math.cos(E) * math.cos(f), -dist * math.cos(E) * math.sin(f), dist * math.sin(E)))
        aim(cam, target)
        cam.data.shift_x = 0
        cam.data.shift_y = 0
        bpy.context.view_layer.update()
        lowest = min(project(cam, p)[1] for p in foot)
        cam.data.shift_y = (0.04 - lowest) * FRAME_H / FRAME_W * -1
        bpy.context.view_layer.update()
        name = "%+03d" % yaw
        for layer in ("body", "rotor", "rotorblur", "tailblur"):
            show(L, [layer])
            render(os.path.join(OUT, "heli", "heli-%s-%s.png" % (layer, name)))
        meta["frames"][name] = {k: project(cam, p) for k, p in anchors.items()}
    json.dump(meta, open(os.path.join(OUT, "heli", "anchors.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
