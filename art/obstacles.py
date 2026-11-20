"""Obstacles: lattice pylon, crane tower, jib and load, cable car pylon and gondola, wind turbine tower, blade and hub.

Scale: 1 world unit = 1/16 m, rendered at 2 px per unit (like the pads). Straight-on view, low sun.
Outputs in Renders/obstacles/ (all with a transparent background):
  pylon-head.png      80 x 96 units: head of a power pylon, arms at 80 and 36 units above the bottom (wires hang there)
  tower-tile.png      40 x 32 units: one lattice cell of a pylon shaft, stacked by the game
  crane-tile.png      36 x 32 units: one lattice cell of the crane tower, stacked by the game
  crane-jib.png       240 x 72 units: jib (right, 160 long) and counter jib (left, 56), tower axis at x = 60
  crane-hook.png      40 x 40 units: hook block with a crate
  cable-head.png      56 x 48 units: head of a cable car support, the cable runs 44 units above the bottom
  gondola.png         60 x 72 units: hanger and cabin, cable attachment at the top middle
  windmill-tower.png  28 x 256 units: tapering tower with the nacelle at the top (hub at x middle, 22 units below the top)
  windmill-blade.png  22 x 128 units: blade pointing up, root at the bottom middle (scaled by the game to the blade length)
  windmill-hub.png    26 x 26 units

Usage: blender -b -P art/obstacles.py [-- --preview]
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
from passages import M, textured, slab

U = 1 / 16.0
S = 2
DIR = os.path.join(OUT, "obstacles")
STEEL = 0x8c959c
STEEL_D = 0x59626a
RED = 0xc9503a
WHITE = 0xe9e7e1
YEL = 0xe9c85a


def shoot(name, w_u, h_u, build, samples=32):
    reset()
    build()
    W, H = int(w_u * S), int(h_u * S)
    setup_render(W, H, samples=samples)
    world(strength=1.1)
    cam = ortho_camera(width=w_u * U)
    sun("key", 4.0, (74, 0, -50), color=(1.0, 0.95, 0.86))
    sun("fill", 1.2, (80, 0, 150), color=(0.8, 0.88, 1.0))
    target = Vector((0, 0, h_u * U / 2))
    cam.location = target + Vector((0, -60, 0))
    aim(cam, target)
    render(os.path.join(DIR, name))
    print("obstacle", name, W, H)


def beam(name, a, b, t, mt):
    """Square bar from a=(x, z) to b=(x, z), thickness t metres."""
    ax, az = a
    bx, bz = b
    cx, cz = (ax + bx) / 2, (az + bz) / 2
    ln = math.hypot(bx - ax, bz - az)
    ang = math.degrees(math.atan2(bx - ax, bz - az))
    return prim("cube", name, (cx, 0, cz), (t, t, ln), rot=(0, ang, 0), mats=[mt])


def lattice(w, h, t, mt, cells, taper=0.0):
    """A lattice tower: two legs with diagonals; w, h in metres, bottom width w, top width w*(1-taper)."""
    wt = w * (1 - taper)
    for sx in (-1, 1):
        beam("leg", (sx * w / 2, 0), (sx * wt / 2, h), t * 1.5, mt)
    for i in range(cells):
        z0, z1 = h * i / cells, h * (i + 1) / cells
        w0 = w + (wt - w) * i / cells
        w1 = w + (wt - w) * (i + 1) / cells
        beam("cross", (-w0 / 2, z0), (w1 / 2, z1) if i % 2 == 0 else (-w1 / 2, z1), t, mt)
        beam("hor", (-w1 / 2, z1), (w1 / 2, z1), t, mt)
        if i % 2 == 1:
            beam("cross2", (w0 / 2, z0), (-w1 / 2, z1), t, mt)


def pylon_head():
    mt = M("pylon", STEEL, 0.45, metal=0.6)
    ins = M("ins", 0x9fb4a0, 0.3)
    # picture 80 x 96 units = 5 x 6 m; arms at 5.0 m and 2.25 m
    lattice(1.5, 5.0, 0.09, mt, 4, taper=0.0)
    slab("arm", (0, 0, 5.0), (4.6, 0.3, 0.22), mt, 0.02)
    slab("arm2", (0, 0, 2.25), (3.6, 0.3, 0.22), mt, 0.02)
    for z, x in ((5.0, 2.1), (5.0, -2.1), (2.25, 1.6), (2.25, -1.6)):
        prim("cyl", "ins", (x, 0, z - 0.25), (0.16, 0.16, 0.5), mats=[ins])
    slab("top", (0, 0, 5.55), (0.3, 0.3, 0.8), mt, 0.02)


def tower_tile():
    lattice(2.0, 2.0, 0.09, M("tile", STEEL, 0.45, metal=0.6), 1)
    beam("x2", (1.0, 0.0), (-1.0, 2.0), 0.09, M("tile2", STEEL, 0.45, metal=0.6))


def crane_tile():
    mt = M("ctower", YEL, 0.5, metal=0.2)
    lattice(1.7, 2.0, 0.1, mt, 1)
    beam("x2", (0.85, 0.0), (-0.85, 2.0), 0.1, mt)


def crane_jib():
    yel = M("jib", YEL, 0.5, metal=0.2)
    dark = M("jibd", STEEL_D, 0.5, metal=0.4)
    # Coordinates: x in metres from the tower axis (jib to the right), z up from the bottom of the picture.
    zc = 1.0
    jibl, cnt = 10.0, 3.5
    beam("top", (0.0, zc + 1.1), (jibl, zc + 0.15), 0.12, yel)
    beam("bot", (0.0, zc), (jibl, zc), 0.14, yel)
    for i in range(10):
        x0, x1 = jibl * i / 10, jibl * (i + 1) / 10
        z0 = zc + 1.1 - 0.95 * i / 10
        z1 = zc + 1.1 - 0.95 * (i + 1) / 10
        beam("d", (x0, zc) if i % 2 == 0 else (x0, z0), (x1, z1) if i % 2 == 0 else (x1, zc), 0.07, yel)
    beam("ctop", (0.0, zc + 1.1), (-cnt, zc + 0.3), 0.1, yel)
    beam("cbot", (0.0, zc), (-cnt, zc), 0.12, yel)
    slab("weight", (-cnt + 0.5, 0, zc - 0.55), (1.2, 0.8, 0.9), dark, 0.03)
    slab("cab", (0.9, 0.2, zc - 0.75), (1.3, 0.8, 1.0), M("cab", WHITE, 0.4), 0.05)
    slab("cabw", (1.2, -0.2, zc - 0.75), (0.5, 0.05, 0.5), M("glass", 0x6fa3c4, 0.1, metal=0.3), 0.0)
    prim("cube", "apex", (0, 0, zc + 1.9), (0.2, 0.2, 1.8), mats=[yel])
    beam("stayA", (0, zc + 2.8), (jibl * 0.55, zc + 0.65), 0.04, dark)
    beam("stayB", (0, zc + 2.8), (-cnt, zc + 0.3), 0.04, dark)
    # The tower axis sits 60 units (3.75 m) from the left edge of the picture.
    for o in bpy.data.objects:
        o.location.x -= 3.75


def crane_hook():
    slab("block", (0, 0, 2.05), (0.7, 0.4, 0.4), M("hb", STEEL_D, 0.5, metal=0.5), 0.03)
    prim("torus", "hook", (0, 0, 1.55), (0.5, 0.5, 0.5), rot=(90, 0, 0), mats=[M("hk", STEEL, 0.4, metal=0.7)], minor=0.12)
    crate = textured("crate", 0xa87a45, 0xd2a86a, scale=14.0, bump=0.5, rough=0.8)
    slab("crate", (0, 0, 0.55), (1.9, 1.2, 1.1), crate, 0.05)
    for sx in (-0.7, 0.7):
        slab("band", (sx, -0.62, 0.55), (0.12, 0.05, 1.1), M("band", 0x3d3a35, 0.6), 0.0)


def cable_head():
    mt = M("cpylon", STEEL, 0.45, metal=0.6)
    # picture 56 x 48 units = 3.5 x 3 m; the cable runs on the wheels at 2.75 m
    lattice(1.5, 1.9, 0.09, mt, 2)
    slab("head", (0, 0, 2.05), (2.4, 0.5, 0.4), M("chead", RED, 0.45), 0.03)
    for sx in (-0.9, 0.9):
        prim("cyl", "wheel", (sx, -0.3, 2.45), (0.5, 0.2, 0.5), rot=(90, 0, 0), mats=[M("wheel", STEEL_D, 0.4, metal=0.5)])


def gondola():
    red = M("gred", RED, 0.35, metal=0.1)
    white = M("gwhite", WHITE, 0.35)
    glass = M("gglass", 0x6fa3c4, 0.08, metal=0.2)
    # picture 60 x 72 units = 3.75 x 4.5 m; cable attachment at the top
    slab("hanger", (0, 0, 4.0), (0.15, 0.2, 0.9), M("hg", STEEL_D, 0.5, metal=0.5), 0.0)
    slab("bar", (0, 0, 3.55), (2.4, 0.3, 0.2), M("hbar", STEEL_D, 0.5, metal=0.5), 0.02)
    slab("roof", (0, 0, 3.3), (3.0, 1.6, 0.25), red, 0.06)
    slab("body", (0, 0, 2.0), (3.2, 1.7, 2.3), white, 0.12)
    slab("band", (0, -0.86, 1.0), (3.2, 0.05, 0.45), red, 0.0)
    for sx in (-0.95, 0, 0.95):
        slab("win", (sx, -0.87, 2.4), (0.8, 0.05, 1.0), glass, 0.0)
    slab("floor", (0, 0, 0.75), (3.0, 1.6, 0.2), red, 0.04)


def windmill_tower():
    wh = M("wtower", WHITE, 0.4)
    # tapering tube 16 m, nacelle on top; picture 28 x 256 units = 1.75 x 16 m, hub axis 22 units below the top
    bpy.ops.mesh.primitive_cone_add(radius1=0.62, radius2=0.34, depth=14.2, vertices=36, location=(0, 0, 7.1))
    t = bpy.context.active_object
    t.data.materials.append(wh)
    for p in t.data.polygons:
        p.use_smooth = True
    slab("band", (0, 0, 1.1), (1.25, 0.05, 0.25), M("wred", RED, 0.45), 0.0)
    slab("nacelle", (0, 0.1, 14.7), (0.75, 1.3, 0.62), M("nac", 0xdedbd3, 0.35), 0.1)
    slab("door", (0, -0.6, 0.9), (0.28, 0.04, 0.7), M("door", 0x44505a, 0.5), 0.0)


def windmill_blade():
    wh = M("blade", 0xf2f0ea, 0.3)
    # root at the bottom, 8 m long, tapering; picture 22 x 128 units
    bm = bmesh.new()
    prof = [(-0.30, 0.0), (0.30, 0.0), (0.36, 0.5), (0.30, 1.8), (0.12, 5.5), (0.03, 8.0), (-0.12, 8.0), (-0.28, 1.8), (-0.30, 0.5)]
    top = [bm.verts.new((x, 0.05, z)) for x, z in prof]
    bot = [bm.verts.new((x * 0.86, -0.05, z)) for x, z in prof]
    bm.faces.new(top[::-1]); bm.faces.new(bot)
    n = len(prof)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([bot[i], bot[j], top[j], top[i]])
    mesh_obj("blade", bm, [wh])
    slab("stripe", (0.0, -0.08, 7.4), (0.25, 0.03, 1.0), M("rt", RED, 0.45), 0.0)


def windmill_hub():
    prim("sphere", "hub", (0, 0, 0.8), (1.5, 1.5, 1.5), mats=[M("hub", 0xdedbd3, 0.3)])
    prim("cone", "nose", (0, -0.55, 0.8), (1.1, 1.1, 0.8), rot=(90, 0, 0), mats=[M("nose", RED, 0.4)], r2=0.1)


def main():
    smp = 16 if "--preview" in argv() else 48
    os.makedirs(DIR, exist_ok=True)
    shoot("pylon-head.png", 80, 96, pylon_head, smp)
    shoot("tower-tile.png", 40, 32, tower_tile, smp)
    shoot("crane-tile.png", 36, 32, crane_tile, smp)
    shoot("crane-jib.png", 240, 72, crane_jib, smp)
    shoot("crane-hook.png", 40, 40, crane_hook, smp)
    shoot("cable-head.png", 56, 48, cable_head, smp)
    shoot("gondola.png", 60, 72, gondola, smp)
    shoot("windmill-tower.png", 28, 256, windmill_tower, smp)
    shoot("windmill-blade.png", 22, 128, windmill_blade, smp)
    shoot("windmill-hub.png", 26, 26, windmill_hub, smp)


if __name__ == "__main__":
    main()
