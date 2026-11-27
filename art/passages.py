"""Passages: rock face above a tunnel, viaduct above an underpass, shutter parts and signal lamps.

Scale: 1 world unit = 1/16 m, rendered at 2 px per unit (like the pads). Straight-on view with a low sun so the relief reads.
Outputs in Renders/passages/:
  mass-<mission>-<passage>.png   the solid above the roof (x0..x1, roof..ceiling), bottom edge = underside of the roof
  shutter-door.png, shutter-bar.png, shutter-housing.png, lamp-green/amber/red.png

Usage: blender -b -P art/passages.py [-- --preview] [--masses] [--only=<mission>]
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *

U = 1 / 16.0
S = 2
DIR = os.path.join(OUT, "passages")


def M(name, col, rough=0.7, **kw):
    return mat(name, col, rough=rough, **kw)


def textured(name, c1, c2, scale=6.0, stretch=(1, 1, 1), bump=0.6, rough=0.9, detail=8.0, strata=0.0):
    """Principled material with noise-driven colour and bump (rock, concrete)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Roughness"].default_value = rough
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = stretch
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = scale
    nz.inputs["Detail"].default_value = detail
    nz.inputs["Roughness"].default_value = 0.62
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = srgb(c1)
    ramp.color_ramp.elements[1].color = srgb(c2)
    bp = nt.nodes.new("ShaderNodeBump")
    bp.inputs["Strength"].default_value = bump
    bp.inputs["Distance"].default_value = 0.25
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], nz.inputs["Vector"])
    fac = nz.outputs["Fac"]
    if strata:
        wv = nt.nodes.new("ShaderNodeTexWave")
        wv.wave_type = "BANDS"
        wv.bands_direction = "Z"
        wv.inputs["Scale"].default_value = 1.4
        wv.inputs["Distortion"].default_value = 6.0
        wv.inputs["Detail"].default_value = 3.0
        nt.links.new(mp.outputs["Vector"], wv.inputs["Vector"])
        mx = nt.nodes.new("ShaderNodeMix")
        mx.data_type = "FLOAT"
        mx.inputs[0].default_value = strata
        nt.links.new(nz.outputs["Fac"], mx.inputs[2])
        nt.links.new(wv.outputs["Fac"], mx.inputs[3])
        fac = mx.outputs[0]
    nt.links.new(fac, ramp.inputs["Fac"])
    nt.links.new(fac, bp.inputs["Height"])
    nt.links.new(ramp.outputs["Color"], p.inputs["Base Color"])
    nt.links.new(bp.outputs["Normal"], p.inputs["Normal"])
    return m


def slab(name, c, size, mt, bevel=0.02):
    return prim("cube", name, c, size, mats=[mt], bevel=bevel)


def shoot(path, w_u, h_u, build, samples=32, sun_energy=4.0):
    """Straight-on render of `build()`; the content spans x -w/2..w/2 and z 0..h (metres), camera looks along +y."""
    reset()
    build()
    W, H = int(w_u * S), int(h_u * S)
    setup_render(W, H, samples=samples)
    world(strength=1.1)
    cam = ortho_camera(width=w_u * U)
    sun("key", sun_energy, (74, 0, -50), color=(1.0, 0.95, 0.86))
    sun("fill", 1.2, (80, 0, 150), color=(0.8, 0.88, 1.0))
    target = Vector((0, 0, h_u * U / 2))
    cam.location = target + Vector((0, -60, 0))
    aim(cam, target)
    render(path)
    print("passage", os.path.basename(path), W, H)


# ---------------------------------------------------------------- masses

PALETTES = {
    "vulkan": ((0x45392f, 0x8a7664), 0xb9b2a6),
    "gebirge": ((0x6b6f74, 0xc9ccd0), 0xd6d4cf),
    "hochwasser": ((0x8c877d, 0xc3beb2), 0xcfcabd),
    "altstadt": ((0x9a8f80, 0xcdbfa8), 0xd6cdbd),
    "staudamm": ((0x8a5a40, 0xc08a64), 0xc7b29a),
    "pass": ((0x70767f, 0xe2e8ee), 0xd9dde2),
}


def rock_face(w_u, h_u, pal):
    w, h = w_u * U, h_u * U
    c1, c2 = pal[0]
    rock = textured("rock", c1, c2, scale=3.2, stretch=(1, 1, 2.2), bump=3.0, detail=12.0, strata=0.55)
    nx, nz = int(w / 0.14), int(h / 0.14)
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=nx, y_subdivisions=nz, size=1, location=(0, 0.6, h / 2))
    g = bpy.context.active_object
    g.name = "face"
    g.scale = (w, h, 1)
    g.rotation_euler = (math.radians(90), 0, 0)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    for pl in g.data.polygons:
        pl.use_smooth = True
    g.data.materials.append(rock)
    tex = bpy.data.textures.new("disp", "CLOUDS")
    tex.noise_scale = 2.4
    tex.noise_depth = 4
    d = g.modifiers.new("d", "DISPLACE")
    d.texture = tex
    d.strength = 2.4
    d.mid_level = 0.4
    # darker crevices: a few vertical cracks as thin dark boxes
    rng = hexrand(int(w_u))
    crack = M("crack", 0x15120f, 0.9)
    for i in range(int(w / 2.2)):
        x = rng.uniform(-w / 2 + 0.5, w / 2 - 0.5)
        z0 = rng.uniform(1.5, h - 8)
        slab("crack", (x, 0.1, z0 + 3), (rng.uniform(0.06, 0.16), 0.06, rng.uniform(2.0, 7.0)), crack, 0.0)


def lip(w_u, pal):
    """Concrete roof slab with hazard chevrons at the bottom edge of the face."""
    w = w_u * U
    conc = M("conc", pal[1], 0.8)
    slab("lip", (0, -0.15, 0.9), (w, 0.7, 1.8), conc, 0.05)
    yel, blk = M("yel", 0xe9c85a, 0.5), M("blk", 0x2b2a28, 0.6)
    n = int(w / 1.2)
    for i in range(n):
        x = -w / 2 + 0.6 + i * 1.2
        slab("chev", (x, -0.52, 0.45), (0.6, 0.05, 0.7), yel if i % 2 == 0 else blk, 0.005)


def viaduct(w_u, h_u, pal):
    w, h = w_u * U, h_u * U
    dark = M("beton-dark", 0x56524b, 0.9)
    slab("core", (0, 0.5, h / 2), (w, 1.0, h), dark, 0.0)
    # girder band at the underside with ribs
    girder = textured("girder", 0x7d786f, 0xa9a398, scale=9.0, bump=0.5, rough=0.8)
    slab("girder", (0, -0.1, 1.3), (w, 0.9, 2.6), girder, 0.04)
    n = max(3, int(w / 2.4))
    for i in range(n + 1):
        x = -w / 2 + i * w / n
        slab("rib", (x, -0.5, 1.3), (0.28, 0.3, 2.3), M("rib", 0x5f5b54, 0.8), 0.02)
    # tall wall: concrete storeys of different height, with projecting slab edges, columns and dark recesses
    rng = hexrand(11)
    z = 2.8
    conc = textured("beton", 0x8c877d, 0xbab5a9, scale=5.0, bump=0.7, rough=0.85)
    while z < h - 0.6:
        sh = min(rng.choice([3.4, 4.2, 5.0]), h - z)
        slab("storey", (0, -0.05, z + sh / 2), (w, 0.6, sh - 0.35), conc, 0.03)
        slab("edge", (0, -0.4, z + sh - 0.1), (w, 0.7, 0.35), girder, 0.03)
        k = max(2, int(w / rng.choice([5.0, 6.5])))
        for c in range(k):
            x = -w / 2 + (c + 0.5) * w / k
            slab("recess", (x, -0.36, z + sh * 0.5), (w / k * 0.42, 0.04, sh * 0.45), M("rec", 0x2f2d2a, 0.8), 0.01)
        z += sh
    for sx in (-1, 1):
        slab("column", (sx * (w / 2 - 0.5), -0.55, h / 2), (0.7, 0.4, h), girder, 0.03)
    slab("strip", (0, -0.58, 2.7), (w, 0.08, 0.16), M("yel", 0xe9c85a, 0.5), 0.0)


def build_masses(preview):
    from_missions = []
    for fn in sorted(os.listdir(MISSIONS)):
        if fn.endswith(".json"):
            m = json.load(open(os.path.join(MISSIONS, fn)))
            for p in m.get("passages", []):
                from_missions.append((m, p))
    only = [a.split("=")[1] for a in argv() if a.startswith("--only=")]
    for m, p in from_missions:
        if only and m["id"] not in only:
            continue
        w_u = (p["x1"] - p["x0"]) + 2 * 16    # collars of 16 units on both sides
        h_u = m["world"]["ceiling"] - p["roof"] + 12
        pal = PALETTES.get(m["id"], PALETTES["hochwasser"])
        if p["kind"] == "tunnel":
            def b(w_u=w_u, h_u=h_u, pal=pal):
                rock_face(w_u, h_u, pal)
                lip(w_u, pal)
        else:
            def b(w_u=w_u, h_u=h_u, pal=pal):
                viaduct(w_u, h_u, pal)
        shoot(os.path.join(DIR, "mass-%s-%s.png" % (m["id"], p["id"])), w_u, h_u, b, samples=16 if preview else 32)


# ---------------------------------------------------------------- shutter parts

def shutter_door():
    steel = M("steel", 0x8f9aa3, 0.35, metal=0.7)
    steel2 = M("steel2", 0x7b868f, 0.4, metal=0.7)
    w, h = 1.0, 12.5
    n = int(h / 0.25)
    for i in range(n):
        slab("slat", (0, 0, 0.125 + i * 0.25), (w, 0.2, 0.22), steel if i % 2 == 0 else steel2, 0.02)
    slab("railL", (-w / 2 + 0.04, -0.12, h / 2), (0.08, 0.16, h), M("rail", 0x4f5860, 0.5, metal=0.5), 0.01)
    slab("railR", (w / 2 - 0.04, -0.12, h / 2), (0.08, 0.16, h), M("rail", 0x4f5860, 0.5, metal=0.5), 0.01)


def shutter_bar():
    yel, blk = M("yel", 0xe9c85a, 0.5), M("blk", 0x2b2a28, 0.6)
    w = 1.5
    slab("base", (0, 0.05, 0.25), (w, 0.3, 0.5), blk, 0.02)
    n = 6
    for i in range(n):
        slab("stripe", (-w / 2 + (i + 0.5) * w / n, -0.12, 0.25), (w / n * 0.55, 0.06, 0.42), yel, 0.005)


def shutter_housing():
    w, h = 2.4, 1.7
    slab("box", (0, 0, h / 2), (w, 0.9, h), M("hous", 0x6c757d, 0.45, metal=0.5), 0.06)
    slab("stripe", (0, -0.47, h * 0.78), (w - 0.2, 0.04, 0.12), M("yel", 0xe9c85a, 0.5), 0.0)
    slab("vent", (0, -0.47, h * 0.38), (w - 0.5, 0.04, 0.5), M("vent", 0x30363b, 0.6), 0.0)


def lamp(color, glow):
    slab("plate", (0, 0, 0.5), (1.0, 0.3, 1.0), M("plate", 0x2e3338, 0.5, metal=0.4), 0.05)
    prim("sphere", "bulb", (0, -0.22, 0.5), (0.7, 0.4, 0.7), mats=[M("bulb%x" % color, color, 0.25, emit=color, strength=glow)])


def build_parts(preview):
    smp = 16 if preview else 48
    shoot(os.path.join(DIR, "shutter-door.png"), 16, 200, shutter_door, samples=smp)
    shoot(os.path.join(DIR, "shutter-bar.png"), 24, 8, shutter_bar, samples=smp)
    shoot(os.path.join(DIR, "shutter-housing.png"), 38, 28, shutter_housing, samples=smp)
    for name, col in (("green", 0x39d068), ("amber", 0xffb02e), ("red", 0xff3b2e)):
        shoot(os.path.join(DIR, "lamp-%s.png" % name), 16, 16, lambda c=col: lamp(c, 14), samples=smp)


def main():
    preview = "--preview" in argv()
    os.makedirs(DIR, exist_ok=True)
    if "--masses" not in argv():
        build_parts(preview)
    build_masses(preview)


if __name__ == "__main__":
    main()
