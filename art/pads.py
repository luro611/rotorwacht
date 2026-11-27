"""Landing pads and the buildings under them, one sprite per rescue point, read straight from the mission files.

Scale: 1 world unit = 1/16 m (the helicopter is drawn at 16 pt per metre), sprites are rendered at 2 px per unit.
The sprite's anchor (u, v) is the middle of the landing surface, so placing the sprite at (x, top) with that
anchor puts the surface exactly at `top`. Writes Renders/pads/pads.json with size and anchor of every sprite.

Usage: blender -b -P art/pads.py [-- --preview] [--only=<mission>]
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *

U = 1 / 16.0     # metres per world unit
S = 2            # pixels per world unit
ELEV = 14.0
DEPTH = 9.0      # metres, depth of buildings and decks


def M(name, col, rough=0.6, **kw):
    return mat(name, col, rough=rough, **kw)


PALETTES = [(0xe6dcc6, 0xc9b896), (0xd9c2a4, 0xb59878), (0xdcd7cc, 0xb4aea2), (0xd8b8a0, 0xb08a70), (0xc9d0c2, 0x9aa592), (0xe3d1b2, 0xc4a577)]


def slab(name, c, size, mt, bevel=0.03):
    return prim("cube", name, c, size, mats=[mt], bevel=bevel)


def helipad_marks(w_m, d_m, z=0.0, ring=0xe9c85a):
    """Yellow ring and white H painted on the deck, plus a red edge line at the front."""
    r = min(w_m, d_m * 0.9) * 0.36
    prim("torus", "ring", (0, 0, z + 0.012), (r * 2, r * 2, r * 0.5), mats=[M("ring", ring, 0.5)], minor=0.07 / (r * 2))
    h = M("hmark", 0xf6f2ea, 0.5)
    k = r * 0.55
    slab("h1", (-k * 0.55, 0, z + 0.02), (0.22, k * 1.5, 0.03), h, 0.005)
    slab("h2", (k * 0.55, 0, z + 0.02), (0.22, k * 1.5, 0.03), h, 0.005)
    slab("h3", (0, 0, z + 0.02), (k * 1.1, 0.22, 0.03), h, 0.005)


def deck(w_m, d_m, thick, mt_top, mt_edge, z=0.0):
    slab("deck", (0, 0, z - thick / 2), (w_m, d_m, thick), mt_top, 0.02)
    slab("edgeF", (0, -d_m / 2 + 0.07, z + 0.01), (w_m - 0.1, 0.14, 0.03), mt_edge, 0.005)
    slab("edgeL", (-w_m / 2 + 0.07, 0, z + 0.01), (0.14, d_m - 0.1, 0.03), mt_edge, 0.005)
    slab("edgeR", (w_m / 2 - 0.07, 0, z + 0.01), (0.14, d_m - 0.1, 0.03), mt_edge, 0.005)


def corner_lights(w_m, d_m, z=0.0):
    for sx in (-1, 1):
        for sy in (-1, 1):
            prim("sphere", "lamp", (sx * (w_m / 2 - 0.2), sy * (d_m / 2 - 0.2), z + 0.1), (0.22, 0.22, 0.22),
                 mats=[M("lampm", 0xffb35a, 0.3, emit=0xffb35a, strength=6)])


def railing_back(w_m, d_m, z=0.0, col=0xcfcac2):
    mt = M("rail", col, 0.4, metal=0.5)
    y = d_m / 2 - 0.1
    tube("railtop", [(-w_m / 2 + 0.1, y, z + 0.95), (w_m / 2 - 0.1, y, z + 0.95)], 0.03, mt, 4)
    n = int(w_m / 1.2)
    for i in range(n + 1):
        x = -w_m / 2 + 0.1 + (w_m - 0.2) * i / n
        tube("post", [(x, y, z), (x, y, z + 0.95)], 0.025, mt, 4)


def building(p, seed, below_m, palette=None):
    rng = hexrand(seed)
    wall, trim = palette or PALETTES[rng.randrange(len(PALETTES))]
    w = p["width"] * U
    bw = w + 0.4
    mwall, mtrim = M("wall%d" % seed, wall, 0.85), M("trim%d" % seed, trim, 0.8)
    slab("body", (0, 0, -below_m / 2 - 0.1), (bw, DEPTH - 0.4, below_m), mwall, 0.02)
    slab("cornice", (0, 0, -0.24), (bw + 0.3, DEPTH, 0.36), mtrim, 0.03)
    # windows and door
    glass = M("glassb", 0x4d6a7c, 0.1, metal=0.2)
    frame = M("frame", 0xf2eee6, 0.5)
    floor_h = 2.7
    rows = max(0, int((below_m - 1.4) / floor_h))
    cols = max(2, int(bw / 2.4))
    for r in range(rows):
        for c in range(cols):
            x = -bw / 2 + (c + 0.5) * bw / cols
            z = -0.7 - floor_h * (r + 0.5) + 0.3
            slab("frame", (x, -DEPTH / 2 + 0.2 - 0.02, z), (1.05, 0.06, 1.35), frame, 0.01)
            slab("win", (x, -DEPTH / 2 + 0.2 - 0.06, z), (0.85, 0.05, 1.15), glass, 0.005)
    if below_m > 3.2:
        slab("door", (0.0, -DEPTH / 2 + 0.2 - 0.04, -below_m + 0.95), (1.1, 0.08, 1.9), M("door", 0x6a4c3a, 0.6), 0.02)
        slab("step", (0.0, -DEPTH / 2 + 0.1, -below_m + 0.08), (1.7, 0.5, 0.16), mtrim, 0.01)
    deck(w, DEPTH - 0.8, 0.18, M("asphalt", 0x3d3b39, 0.9), M("edgered", 0xc75d3b, 0.6))
    helipad_marks(w, DEPTH - 0.8)
    railing_back(w, DEPTH - 0.8)
    corner_lights(w, DEPTH - 0.8)
    # roof extras behind the pad
    if rng.random() < 0.7:
        slab("stair", (-w / 2 + 0.9, DEPTH / 2 - 1.8, 0.7), (1.3, 1.5, 1.4), mtrim, 0.03)
    prim("cyl", "antenna", (w / 2 - 0.7, DEPTH / 2 - 1.2, 1.3), (0.06, 0.06, 2.6), mats=[M("ant", 0x6b6862, 0.4, metal=0.7)])
    return dict(above=3.0)


def rig(p, below_m):
    """Helideck of an offshore platform: steel deck on short struts, safety net, lamps."""
    w = p["width"] * U
    steel, dark = M("rigsteel", 0x8a949c, 0.5, metal=0.6), M("rigdark", 0x3a4248, 0.7)
    deck(w, DEPTH - 0.8, 0.3, M("rigdeck", 0x34503f, 0.85), M("rigedge", 0xe9c85a, 0.5))
    helipad_marks(w, DEPTH - 0.8)
    railing_back(w, DEPTH - 0.8, col=0xe9c85a)
    corner_lights(w, DEPTH - 0.8)
    for sx in (-1, -0.35, 0.35, 1):
        tube("strut", [(sx * w * 0.42, -2.6, -below_m), (sx * w * 0.48, -3.2, -0.3)], 0.14, steel, 6)
    slab("under", (0, 0, -0.5), (w * 0.96, DEPTH - 1.6, 0.3), dark, 0.02)
    prim("cyl", "mast", (w / 2 - 0.6, DEPTH / 2 - 1.2, 1.5), (0.1, 0.1, 3.0), mats=[M("rigr", 0xc75d3b, 0.6)])
    return dict(above=3.2)


def wood_tower(p, below_m, hunting=False):
    w = p["width"] * U
    wood = M("wood", 0x8a6240, 0.85)
    dk = M("wood2", 0x6a4a30, 0.9)
    deckw = w
    slab("floor", (0, 0, -0.11), (deckw, DEPTH * 0.6, 0.22), M("plank", 0xa27a50, 0.85), 0.02)
    deckd = DEPTH * 0.6
    helipad_marks(deckw, deckd)
    railing_back(deckw, deckd, col=0xc9b48f)
    # legs with cross bracing
    lw = deckw * 0.42
    for sx in (-1, 1):
        for sy in (-1, 1):
            tube("leg", [(sx * lw / 2 * 1.15, sy * 1.2, -below_m), (sx * lw / 2, sy * 1.0, -0.2)], 0.14, dk, 6)
    for i in range(3):
        z0, z1 = -below_m + below_m * i / 3, -below_m + below_m * (i + 1) / 3
        tube("brace", [(-lw / 2, -1.1, z0), (lw / 2, -1.0, z1)], 0.05, wood, 4)
        tube("brace", [(lw / 2, -1.1, z0), (-lw / 2, -1.0, z1)], 0.05, wood, 4)
    if not hunting:
        slab("hut", (-deckw / 2 + 1.0, deckd / 2 - 1.0, 0.9), (1.6, 1.5, 1.8), wood, 0.03)
        slab("hutroof", (-deckw / 2 + 1.0, deckd / 2 - 1.0, 1.9), (2.0, 1.9, 0.18), M("roofr", 0x7a3a28, 0.7), 0.03)
    corner_lights(deckw, deckd)
    return dict(above=2.6)


def water_tower(p, below_m):
    w = p["width"] * U
    conc = M("conc", 0xcfcbc2, 0.8)
    dk = M("conc2", 0xa9a59b, 0.85)
    r = w / 2
    prim("cyl", "plat", (0, 0, -0.15), (w, w, 0.3), mats=[M("platm", 0x4a4846, 0.8)], bevel=0.02)
    helipad_marks(w, w)
    prim("cyl", "tank", (0, 0, -1.7), (w * 0.86, w * 0.86, 2.6), mats=[conc], bevel=0.1)
    prim("cone", "cap", (0, 0, -0.35), (w * 0.9, w * 0.9, 0.5), mats=[dk], r2=0.35)
    prim("cyl", "shaft", (0, 0, -below_m / 2 - 2), (w * 0.34, w * 0.34, below_m), mats=[dk])
    for k in range(int(below_m / 2.2)):
        prim("cyl", "ring", (0, 0, -3.8 - k * 2.2), (w * 0.37, w * 0.37, 0.12), mats=[M("conc3", 0x8d897f, 0.85)])
    prim("cyl", "stripe", (0, 0, -1.7), (w * 0.875, w * 0.875, 0.45), mats=[M("redstripe", 0xc75d3b, 0.6)])
    corner_lights(w * 0.9, w * 0.9)
    return dict(above=2.0)


def lighthouse(p, below_m):
    w = p["width"] * U
    white, red = M("lw", 0xf0ece4, 0.7), M("lr", 0xc9452b, 0.6)
    deck(w, DEPTH * 0.7, 0.3, M("lgrey", 0x55534f, 0.8), M("edgered", 0xc75d3b, 0.6))
    helipad_marks(w, DEPTH * 0.7)
    railing_back(w, DEPTH * 0.7, col=0x2c2b29)
    # tower behind the pad: stripes, lantern room, light
    ty = DEPTH * 0.35 + 0.8
    top_r, bot_r = 1.4, 2.4
    seg = 5
    for i in range(seg):
        z0, z1 = -below_m + below_m * i / seg, -below_m + below_m * (i + 1) / seg
        r0, r1 = bot_r + (top_r - bot_r) * i / seg, bot_r + (top_r - bot_r) * (i + 1) / seg
        o = prim("cone", "seg", (0, ty, (z0 + z1) / 2), ((r0 + 0) * 2, (r0) * 2, z1 - z0), mats=[white if i % 2 == 0 else red], r2=0.5 * r1 / r0)
    # the tower rises above the deck: continue up
    prim("cyl", "up", (0, ty, 2.3), (top_r * 2, top_r * 2, 4.6), mats=[white])
    prim("cyl", "lantern", (0, ty, 5.4), (2.3, 2.3, 1.5), mats=[M("lantg", 0xdcebf0, 0.05, emit=0xffe9a0, strength=2.5)])
    prim("cone", "dome", (0, ty, 6.6), (2.7, 2.7, 1.0), mats=[red], r2=0.0)
    corner_lights(w, DEPTH * 0.7)
    return dict(above=7.4)


def boat(p, below_m):
    w = p["width"] * U            # length of the deck pad
    L = w + 4.0
    hull = M("hull", 0x2f4a60, 0.5)
    hullw = M("hullw", 0xf0ece4, 0.5)
    prof = [(-L / 2, -0.14), (L / 2 - 0.2, -0.14), (L / 2 + 1.6, 1.0), (L / 2 - 0.4, -below_m * 0.45), (L / 2 - 2.5, -below_m), (-L / 2 + 0.6, -below_m), (-L / 2, -below_m * 0.5)]
    bm = bmesh.new()
    wd = 2.4
    vs = [bm.verts.new((x, -wd, z)) for x, z in prof] + [bm.verts.new((x, wd, z)) for x, z in prof]
    n = len(prof)
    bm.faces.new(vs[:n][::-1]); bm.faces.new(vs[n:])
    for i in range(n):
        bm.faces.new((vs[i], vs[(i + 1) % n], vs[n + (i + 1) % n], vs[n + i]))
    o = mesh_obj("hull", bm, [hull])
    smooth(o, bevel=0.15)
    slab("deck", (0, 0, -0.06), (L - 0.8, wd * 2 - 0.3, 0.12), M("deckp", 0x6f7a78, 0.8), 0.02)
    slab("wl", (0, -wd + 0.05, -below_m * 0.18), (L - 0.4, 0.12, 0.35), hullw, 0.02)
    helipad_marks(w * 0.8, wd * 1.8, ring=0xffffff)
    # wheelhouse at the stern (left), mast and railing
    slab("house", (-L / 2 + 1.6, 0, 1.1), (2.6, 3.4, 2.1), hullw, 0.1)
    slab("hglass", (-L / 2 + 2.95, 0, 1.5), (0.1, 3.0, 0.7), M("hg", 0x1d2a33, 0.1), 0.02)
    slab("hroof", (-L / 2 + 1.7, 0, 2.2), (3.0, 3.8, 0.14), M("hr", 0xc9452b, 0.5), 0.03)
    mm = M("mastm", 0x55534f, 0.5, metal=0.5)
    tube("mast", [(-L / 2 + 1.4, 0, 2.2), (-L / 2 + 1.4, 0, 4.4)], 0.07, mm, 4)
    tube("boom", [(-L / 2 + 1.4, 0, 4.0), (-L / 2 + 5.4, 0, 1.6)], 0.04, mm, 4)
    railing_back(w, wd * 2 - 0.4)
    prim("sphere", "lamp", (-L / 2 + 1.4, 0, 4.5), (0.3, 0.3, 0.3), mats=[M("mlamp", 0xffffff, 0.2, emit=0xffffff, strength=5)])
    return dict(above=4.8, width_extra=2.5 * 16)


def island_deck(p, mission, kind_id):
    """Flat ground pads: a low slab with painted H, plus props to the sides."""
    w = p["width"] * U
    d = 7.0
    grass = {"wiese": 0x6e8a4e, "kies": 0x9a948a, "pflaster": 0x8d8780, "fels": 0x77736c, "sand": 0xb7a888, "asche": 0x4a4745, "wald": 0x6a7a48, "schnee": 0xe9eef4}
    style = STYLE.get((mission, p["id"]), "wiese")
    top = M("padtop_" + style, grass[style], 0.95)
    slab("pad", (0, 0, -0.1), (w, d, 0.2), top, 0.05)
    slab("padedge", (0, -d / 2 + 0.04, 0.005), (w - 0.1, 0.1, 0.03), M("padedge", 0xf0ece4, 0.5), 0.005)
    helipad_marks(w, d, ring=0xf6f2ea)
    corner_lights(w, d)
    rng = hexrand(sum(map(ord, p["id"])))
    above = 1.0
    # props outside the pad
    for sx in (-1, 1):
        x = sx * (w / 2 + 0.9)
        if style in ("wiese", "wald"):
            for k in range(3):
                prim("cone", "tree", (x + sx * k * 0.9, rng.uniform(0.5, 2.0), 1.6 + k * 0.3), (1.3, 1.3, 3.2 + k * 0.6), mats=[M("conif", 0x2f5a35, 0.9)], r2=0.0)
            above = 5.0
        elif style in ("fels", "asche"):
            for k in range(2):
                prim("sphere", "rock", (x + sx * k * 1.0, rng.uniform(-0.5, 1.0), 0.6), (1.6 + k * 0.6, 1.3, 1.2 + k * 0.5), mats=[M("rock", 0x6a665f, 0.95)], seg=8, rings=6, smooth=False)
            above = 2.2
        elif style == "pflaster":
            prim("cyl", "bollard", (x, -2.5, 0.3), (0.25, 0.25, 0.6), mats=[M("bol", 0x3c3a38, 0.5)])
        elif style == "sand" and kind_id == "brunnen":
            prim("cone", "palmtrunk", (x, 1.0, 1.6), (0.3, 0.3, 3.2), mats=[M("trunk", 0x8a6a40, 0.9)], r2=0.7)
            for k in range(5):
                a = k * 2 * math.pi / 5
                o = slab("leaf", (x + math.cos(a) * 0.7, 1.0 + math.sin(a) * 0.4, 3.2), (1.5, 0.35, 0.08), M("palm", 0x4f7a3a, 0.8), 0.02)
                o.rotation_euler = (0, math.radians(18 * math.cos(a)), a)
            above = 4.0
        elif style in ("schnee", "sand"):
            # stranded vehicles half buried beside the cleared spot
            body = M("car%d" % (sx + 1), 0xc75d3b if sx < 0 else (0x41607a if style == "schnee" else 0x6a7350), 0.5)
            cx = x + sx * 0.5
            slab("carbody", (cx, 0.2, 0.55), (2.2, 1.4, 0.8), body, 0.15)
            slab("carroof", (cx - sx * 0.2, 0.2, 1.15), (1.2, 1.3, 0.55), body, 0.2)
            slab("carwin", (cx - sx * 0.2, -0.47, 1.17), (1.0, 0.05, 0.36), M("carglass", 0x2d3f4c, 0.1), 0.02)
            drift = M("drift" + style, 0xf4f7fa if style == "schnee" else 0xdcb878, 0.95)
            prim("sphere", "drift", (cx + sx * 0.3, -0.5, 0.05), (2.8, 1.6, 0.8), mats=[drift], seg=12, rings=8)
            prim("sphere", "drifttop", (cx - sx * 0.2, 0.2, 1.45), (1.1, 1.1, 0.3), mats=[drift], seg=10, rings=6)
            above = 2.2
    if kind_id in ("zelt", "zeltplatz"):
        for sx in (-1, 1):
            prim("cone", "tent", (sx * (w / 2 + 2.4), 1.5, 1.0), (2.8, 2.8, 2.0), mats=[M("tent", 0xe8e0cf if sx < 0 else 0xc75d3b, 0.8)], r2=0.0, seg=4)
        above = 3.0
    return dict(above=above, width_extra=40)


def ledge_marker(p):
    """Winch ledge: no landing. Orange panel on the rock, pole with flag and a small beacon."""
    w = p["width"] * U
    slab("rockpad", (0, 0, -0.18), (w, 6.0, 0.36), M("ledgerock", 0x6d6a64, 0.95), 0.1)
    slab("panel", (0, -0.3, 0.02), (w * 0.5, 2.2, 0.04), M("panel", 0xee6a2c, 0.5), 0.01)
    X = M("xw", 0xf6f2ea, 0.5)
    for s in (-1, 1):
        o = slab("x", (0, -0.3, 0.05), (w * 0.5, 0.28, 0.03), X, 0.005)
        o.rotation_euler = (0, 0, math.radians(21 * s))
    tube("pole", [(w / 2 - 0.5, 0.8, 0), (w / 2 - 0.5, 0.8, 3.0)], 0.05, M("polem", 0xf6f2ea, 0.5), 4)
    slab("flag", (w / 2 - 0.05, 0.8, 2.7), (0.9, 0.04, 0.55), M("flagm", 0xc75d3b, 0.6), 0.005)
    prim("sphere", "beacon", (w / 2 - 0.5, 0.8, 3.1), (0.28, 0.28, 0.28), mats=[M("bm", 0xff7a3a, 0.2, emit=0xff7a3a, strength=8)])
    return dict(above=3.5, width_extra=20)


STYLE = {
    ("hochwasser", "insel"): "wiese", ("hochwasser", "huegel"): "kies",
    ("waldbrand", "lichtung"): "wald", ("waldbrand", "zelt"): "wiese",
    ("kueste", "klippe1"): "fels", ("kueste", "klippe2"): "fels",
    ("vulkan", "hafen"): "pflaster", ("staudamm", "zeltplatz"): "wiese", ("staudamm", "weiler"): "kies",
    ("pass", "autos1"): "schnee", ("pass", "autos2"): "schnee",
    ("wueste", "karawane"): "sand", ("wueste", "jeep"): "sand", ("wueste", "brunnen"): "sand", ("altstadt", "platz1"): "pflaster", ("altstadt", "gasse1"): "pflaster",
    ("altstadt", "platz2"): "pflaster", ("altstadt", "gasse2"): "pflaster",
}


def build_point(mission, p, below_m):
    kind, pid = p["kind"], p["id"]
    seed = sum(ord(c) for c in mission["id"] + pid)
    if p.get("access") == "winch":
        return ledge_marker(p)
    if kind == "rig":
        return rig(p, below_m)
    if kind == "boat":
        return boat(p, below_m)
    if kind == "lighthouse":
        return lighthouse(p, below_m)
    if kind == "island":
        return island_deck(p, mission["id"], pid)
    if kind == "tower":
        if mission["id"] == "hochwasser":
            return water_tower(p, below_m)
        return wood_tower(p, below_m, hunting=(pid == "hochsitz"))
    return building(p, seed, below_m)


def camp(w_u):
    """Rescue camp: big flush pad with edge lights, tent, fuel tank, lamp mast and wind sock pole."""
    w = w_u * U
    d = 8.0
    slab("pad", (0, 0, -0.1), (w, d, 0.2), M("campgrey", 0x74716b, 0.9), 0.03)
    slab("padstripe", (0, -d / 2 + 0.25, 0.01), (w - 1.0, 0.18, 0.02), M("campy", 0xe9c85a, 0.5), 0.003)
    helipad_marks(5.0, d * 0.9)
    for i in range(9):
        x = -w / 2 + 0.7 + i * (w - 1.4) / 8
        prim("sphere", "lamp", (x, -d / 2 + 0.3, 0.1), (0.24, 0.24, 0.24), mats=[M("campl", 0xffb35a, 0.3, emit=0xffb35a, strength=7)])
    tw, tl, th = 7.0, 4.5, 3.0
    tx, ty = -w / 2 + 5.0, d / 2 - 2.6
    for sg in (-1, 1):
        o = slab("tentroof", (tx, ty + sg * tl * 0.27, th * 0.5), (tw, tl * 0.62, 0.08), M("tent1", 0xece6d8, 0.85), 0.01)
        o.rotation_euler = (math.radians(-sg * 38), 0, 0)
    slab("tentfront", (tx, ty - tl / 2 + 0.25, th * 0.35), (tw - 0.2, 0.06, th * 0.7), M("tent1", 0xece6d8, 0.85), 0.01)
    slab("tentdoor", (tx, ty - tl / 2 + 0.2, 0.9), (1.4, 0.08, 1.8), M("tentd", 0x3a3532, 0.8), 0.01)
    slab("tentband", (tx, ty - tl / 2 + 0.1, 2.2), (tw * 0.8, 0.08, 0.4), M("tentr", 0xc75d3b, 0.6), 0.01)
    # fuel tank
    fx, fy = w / 2 - 7.0, d / 2 - 2.2
    prim("cyl", "tank", (fx, fy, 1.0), (2.2, 2.2, 2.0), mats=[M("fuel", 0xe3dfd5, 0.5)], bevel=0.1)
    prim("cyl", "tankband", (fx, fy, 1.0), (2.22, 2.22, 0.45), mats=[M("fuelr", 0xc75d3b, 0.6)])
    # lamp mast with light, and sock pole
    mm = M("camppole", 0x55534f, 0.5, metal=0.5)
    tube("mast", [(w / 2 - 1.2, d / 2 - 1.2, 0), (w / 2 - 1.2, d / 2 - 1.2, 6.5)], 0.07, mm, 4)
    prim("sphere", "mastlamp", (w / 2 - 1.2, d / 2 - 1.2, 6.7), (0.5, 0.5, 0.5), mats=[M("mastl", 0xfff0c8, 0.2, emit=0xfff0c8, strength=7)])
    tube("sockpole", [(w / 2 - 3.0, 0.5, 0), (w / 2 - 3.0, 0.5, 6.25)], 0.05, mm, 4)
    return dict(above=7.2, width_extra=30)

def ground_min(mission, p):
    t = mission["terrain"]
    def gh(x):
        if x <= t[0][0]: return t[0][1]
        if x >= t[-1][0]: return t[-1][1]
        for a, b in zip(t, t[1:]):
            if a[0] <= x <= b[0]:
                u = (x - a[0]) / (b[0] - a[0]); s = u * u * (3 - 2 * u)
                return a[1] + (b[1] - a[1]) * s
    xs = [p["x"] - p["width"] / 2 + p["width"] * i / 10 for i in range(11)]
    return min(gh(x) for x in xs)


def main():
    preview = "--preview" in argv()
    only = [a.split("=")[1] for a in argv() if a.startswith("--only=")]
    meta = {}
    mf = os.path.join(OUT, "pads", "pads.json")
    if os.path.exists(mf) and only:
        meta = json.load(open(mf))
    for fn in sorted(os.listdir(MISSIONS)):
        if not fn.endswith(".json"):
            continue
        mission = json.load(open(os.path.join(MISSIONS, fn)))
        if only and mission["id"] not in only:
            continue
        town = mission.get("look") == "town"
        for p in mission["rescuePoints"]:
            reset()
            below_u = max(40, p["top"] - ground_min(mission, p) + 24)
            if p["kind"] == "boat":
                below_u = 80
            if town and p["kind"] == "roof":
                below_u = 14       # the house itself belongs to the terrain
            info = build_point(mission, p, below_u * U)
            extra_w = info.get("width_extra", 24)
            width_u = p["width"] + extra_w * 2 + (24 if p["kind"] == "roof" else 0)
            width_u = math.ceil(width_u / 2) * 2
            above_u = info["above"] / U
            E = math.radians(ELEV)
            # vertical extent of the sprite in metres of image height
            span_z = (below_u + above_u) * U
            h_img_m = span_z * math.cos(E) + DEPTH * math.sin(E)
            W_px, H_px = int(width_u * S), int(math.ceil(h_img_m / U * S))
            setup_render(W_px, H_px, samples=16 if preview else 48)
            world(strength=1.0)
            cam = ortho_camera(width=width_u * U)
            pivot = bpy.data.objects.new("pivot", None); link(pivot)
            sun("key", 4.2, (52, 0, -35), parent=pivot)
            sun("fill", 1.1, (70, 0, 140), color=(0.8, 0.88, 1.0), parent=pivot)
            sun("rim", 1.6, (115, 0, 200), parent=pivot)
            pivot.rotation_euler = (0, 0, math.radians(-90))
            target = Vector((0, 0, (above_u - below_u) / 2 * U))
            cam.location = target + Vector((0, -60 * math.cos(E), 60 * math.sin(E)))
            aim(cam, target)
            bpy.context.view_layer.update()
            a = project(cam, (0, 0, 0))
            name = "pad-%s-%s" % (mission["id"], p["id"])
            render(os.path.join(OUT, "pads", name + ".png"))
            meta[name] = {"w": W_px / S, "h": H_px / S, "u": a[0], "v": a[1]}
            print("pad", name, W_px, H_px)
    if not only or "camp" in only:
        reset()
        info = camp(420)
        width_u = 420 + info["width_extra"] * 2
        above_u, below_u = info["above"] / U, 14
        E = math.radians(ELEV)
        h_img_m = (below_u + above_u) * U * math.cos(E) + 8.0 * math.sin(E)
        W_px, H_px = int(width_u * S), int(math.ceil(h_img_m / U * S))
        setup_render(W_px, H_px, samples=16 if preview else 48)
        world(strength=1.0)
        cam = ortho_camera(width=width_u * U)
        pivot = bpy.data.objects.new("pivot", None); link(pivot)
        sun("key", 4.2, (52, 0, -35), parent=pivot)
        sun("fill", 1.1, (70, 0, 140), color=(0.8, 0.88, 1.0), parent=pivot)
        sun("rim", 1.6, (115, 0, 200), parent=pivot)
        pivot.rotation_euler = (0, 0, math.radians(-90))
        target = Vector((0, 0, (above_u - below_u) / 2 * U))
        cam.location = target + Vector((0, -60 * math.cos(E), 60 * math.sin(E)))
        aim(cam, target)
        bpy.context.view_layer.update()
        a = project(cam, (0, 0, 0))
        render(os.path.join(OUT, "pads", "pad-camp.png"))
        meta["pad-camp"] = {"w": W_px / S, "h": H_px / S, "u": a[0], "v": a[1]}
    json.dump(meta, open(mf, "w"), indent=1)


if __name__ == "__main__":
    main()
