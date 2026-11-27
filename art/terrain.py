"""Terrain strips per mission: the ground profile from the mission file as a lit 3D cross-section with grass, soil,
rock, snow or ash, plus rendered trees, rocks and house facades. Written in 1024-unit chunks (Renders/terrain).

Scale: 1 world unit = 1/16 m, rendered at 1.5 px per unit. Camera looks straight at the front face, so the profile
line is exactly where the physics puts the ground.

Usage: blender -b -P art/terrain.py [-- --preview] [--only=<mission>] [--chunk=<n>]
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
from mathutils import noise

U = 1 / 16.0
S = 1.5
CHUNK = 1024

LOOKS = {
    "valley": dict(grass=(0x86a24f, 0x5f7f3c), soil=(0x7a6847, 0x5d4a38), rock=0x3f352e, band=0.9, trees="forest", rocks=False),
    "coast": dict(grass=(0x78905f, 0x5d7550), soil=(0x7c746b, 0x5a544e), rock=0x35312e, band=0.5, trees=None, rocks=True),
    "town": dict(grass=(0x8d8072, 0x6d6258), soil=(0xc4ab88, 0x9c866a), rock=0x6e5f4e, band=0.2, trees=None, rocks=False),
    "volcano": dict(grass=(0x4b4541, 0x35302d), soil=(0x3a322e, 0x28221f), rock=0x171311, band=1.4, trees=None, rocks=True),
    "offshore": dict(grass=(0xd9b24a, 0xb8913a), soil=(0x6a737a, 0x4d555c), rock=0x2a2f34, band=0.7, trees=None, rocks=False),
    "alpine": dict(grass=(0xf3f6f9, 0xd4dde5), soil=(0x959ba3, 0x6b7179), rock=0x3d4249, band=1.8, trees=None, rocks=True),
}
PLASTER = [0xe3d3b6, 0xd8bf9c, 0xcfae90, 0xdcd4c4, 0xc9b79a, 0xe0c9a6, 0xd2c1a8]


def gh_fn(t):
    def gh(x):
        if x <= t[0][0]: return t[0][1]
        if x >= t[-1][0]: return t[-1][1]
        lo, hi = 0, len(t) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if t[mid][0] <= x: lo = mid
            else: hi = mid
        a, b = t[lo], t[hi]
        u = (x - a[0]) / (b[0] - a[0]); s = u * u * (3 - 2 * u)
        return a[1] + (b[1] - a[1]) * s
    return gh


def attr_node(nt, name):
    n = nt.nodes.new("ShaderNodeAttribute")
    n.attribute_name = name
    return n.outputs["Fac"]


def terrain_material(look, town):
    L = LOOKS[look]
    m = bpy.data.materials.new("terrain")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bs.inputs["Roughness"].default_value = 0.92
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    depth = attr_node(nt, "depth")           # metres below the surface line
    tint = attr_node(nt, "tint")             # per building (town) 0..1

    def math(op, a, b=None, clamp=False):
        n = nt.nodes.new("ShaderNodeMath"); n.operation = op; n.use_clamp = clamp
        for i, v in enumerate((a, b)):
            if v is None: continue
            if isinstance(v, (int, float)): n.inputs[i].default_value = v
            else: nt.links.new(v, n.inputs[i])
        return n.outputs[0]

    def noise_tex(scale, detail=4.0, rough=0.55):
        n = nt.nodes.new("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        nt.links.new(tc.outputs["Object"], n.inputs["Vector"])
        return n.outputs["Fac"]

    def ramp(fac, stops):
        r = nt.nodes.new("ShaderNodeValToRGB")
        for i, (pos, col) in enumerate(stops):
            if i < len(r.color_ramp.elements):
                e = r.color_ramp.elements[i]
            else:
                e = r.color_ramp.elements.new(pos)
            e.position = pos
            e.color = srgb(col)
        nt.links.new(fac, r.inputs["Fac"])
        return r.outputs["Color"]

    big, fine = noise_tex(1.3, 5), noise_tex(9.0, 3)
    # grass / snow / ash band at the top, soil below, rock deeper
    band = L["band"]
    wob = math("MULTIPLY", math("SUBTRACT", big, 0.5), band * 0.9)
    d = math("ADD", depth, wob)
    top_t = math("DIVIDE", d, band, clamp=True)
    soil_t = math("DIVIDE", math("SUBTRACT", d, band), 9.0, clamp=True)
    rock_t = math("DIVIDE", math("SUBTRACT", d, 6.0), 30.0, clamp=True)
    c_top = ramp(fine, [(0.3, L["grass"][1]), (0.7, L["grass"][0])])
    c_soil = ramp(fine, [(0.25, L["soil"][1]), (0.75, L["soil"][0])])
    c_deep = ramp(math("ADD", big, 0.0), [(0.3, L["rock"]), (0.8, L["soil"][1])])
    mixA = nt.nodes.new("ShaderNodeMix"); mixA.data_type = "RGBA"
    nt.links.new(math("ADD", math("MULTIPLY", top_t, 0.0), math("SUBTRACT", 1.0, math("MINIMUM", 1.0, math("MAXIMUM", 0.0, math("SUBTRACT", d, band * 0.55))))), mixA.inputs[0]) if False else None
    # explicit blends: top -> soil by `soil_start`, soil -> deep by rock_t
    s1 = math("MINIMUM", 1.0, math("MAXIMUM", 0.0, math("SUBTRACT", math("MULTIPLY", math("SUBTRACT", d, band * 0.8), 4.0), 0.0)))
    s1 = math("MINIMUM", 1.0, math("MAXIMUM", 0.0, math("DIVIDE", math("SUBTRACT", d, band * 0.7), 0.35)))
    mixA.inputs[0].default_value = 0.0
    nt.links.new(s1, mixA.inputs[0])
    nt.links.new(c_top, mixA.inputs[6]); nt.links.new(c_soil, mixA.inputs[7])
    mixB = nt.nodes.new("ShaderNodeMix"); mixB.data_type = "RGBA"
    nt.links.new(rock_t, mixB.inputs[0])
    nt.links.new(mixA.outputs[2], mixB.inputs[6]); nt.links.new(c_deep, mixB.inputs[7])
    color = mixB.outputs[2]
    if town:
        # plaster by building, windows in a regular grid, darker rows
        pl = nt.nodes.new("ShaderNodeValToRGB")
        n = len(PLASTER)
        pl.color_ramp.interpolation = "CONSTANT"
        for i in range(n):
            e = pl.color_ramp.elements[0] if i == 0 else pl.color_ramp.elements.new(i / n)
            e.position = i / n
            e.color = srgb(PLASTER[i])
        nt.links.new(tint, pl.inputs["Fac"])
        X, Z = sep.outputs[0], sep.outputs[2]
        def cell(v, size):
            return math("SUBTRACT", math("DIVIDE", v, size), math("FLOOR", math("DIVIDE", v, size)))
        fx, fz = cell(X, 2.55), cell(Z, 3.0)
        def win_mask():
            a = math("MULTIPLY", math("GREATER_THAN", fx, 0.28), math("LESS_THAN", fx, 0.72))
            b = math("MULTIPLY", math("GREATER_THAN", fz, 0.30), math("LESS_THAN", fz, 0.78))
            return math("MULTIPLY", a, b)
        wm = math("MULTIPLY", win_mask(), math("GREATER_THAN", depth, 1.1))
        frame_a = math("MULTIPLY", math("GREATER_THAN", fx, 0.22), math("LESS_THAN", fx, 0.78))
        frame_b = math("MULTIPLY", math("GREATER_THAN", fz, 0.24), math("LESS_THAN", fz, 0.84))
        fm = math("MULTIPLY", math("MULTIPLY", frame_a, frame_b), math("GREATER_THAN", depth, 1.1))
        wall = nt.nodes.new("ShaderNodeMix"); wall.data_type = "RGBA"
        nt.links.new(math("MULTIPLY", math("GREATER_THAN", depth, 0.5), 1.0), wall.inputs[0])
        nt.links.new(c_top, wall.inputs[6]); nt.links.new(pl.outputs["Color"], wall.inputs[7])
        withframe = nt.nodes.new("ShaderNodeMix"); withframe.data_type = "RGBA"
        withframe.inputs[7].default_value = srgb(0xf4efe6)
        nt.links.new(fm, withframe.inputs[0]); nt.links.new(wall.outputs[2], withframe.inputs[6])
        withwin = nt.nodes.new("ShaderNodeMix"); withwin.data_type = "RGBA"
        withwin.inputs[7].default_value = srgb(0x4e6b7e)
        nt.links.new(wm, withwin.inputs[0]); nt.links.new(withframe.outputs[2], withwin.inputs[6])
        color = withwin.outputs[2]
        # ground floor below street level is plain soil
        low = nt.nodes.new("ShaderNodeMix"); low.data_type = "RGBA"
        nt.links.new(attr_node(nt, "below"), low.inputs[0])
        nt.links.new(color, low.inputs[6]); nt.links.new(mixB.outputs[2], low.inputs[7])
        color = low.outputs[2]
    nt.links.new(color, bs.inputs["Base Color"])
    # relief
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.0 if town else 0.55
    bump.inputs["Distance"].default_value = 0.25
    nt.links.new(math("ADD", fine, math("MULTIPLY", big, 1.4)), bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bs.inputs["Normal"])
    nt.links.new(bs.outputs["BSDF"], out.inputs["Surface"])
    return m


def build_ground(mission, gh, ymin, look):
    W = mission["world"]["width"]
    town = look == "town"
    t = mission["terrain"]
    # building ids for the town look: plateaus of equal height
    plateaus = []
    i = 0
    while i < len(t) - 1:
        if t[i][1] == t[i + 1][1] and t[i][1] > 150 and town:
            plateaus.append((t[i][0], t[i + 1][0]))
            i += 2
        else:
            i += 1
    def building_id(x):
        best, bd = 0, 1e9
        for k, (a, b) in enumerate(plateaus):
            d = 0 if a <= x <= b else min(abs(x - a), abs(x - b))
            if d < bd: best, bd = k, d
        return best
    step = 6
    xs = [-30 + k * step for k in range(int((W + 60) / step) + 1)]
    bottom = ymin - 40
    N = 22
    fr = [(k / N) ** 1.7 for k in range(N + 1)]
    bm = bmesh.new()
    depth_l, tint_l, below_l = [], [], []
    rows = []
    for x in xs:
        g = gh(x)
        total = g - bottom
        col = []
        for f in fr:
            z = g - f * total
            dm = (g - z) * U
            X, Z = x * U, z * U
            n = noise.fractal((X * 0.5, 3.1, Z * 0.5), 0.6, 2.0, 5)
            Y = 0.5 * n + 0.5 * noise.noise((X * 2.2, 7.7, Z * 2.2))
            if dm < 1.0:
                Y += (1.0 - dm) * 0.7        # soft rounded top edge
            if town:
                Y = 0.08 * n
            col.append(bm.verts.new((X, Y, Z)))
            depth_l.append(dm)
            tint_l.append((building_id(x) % 7 + 0.5) / 7 if town else 0.0)
            below_l.append(1.0 if (town and g < 140) else 0.0)
        rows.append(col)
    for a, b in zip(rows, rows[1:]):
        for k in range(N):
            bm.faces.new((a[k], b[k], b[k + 1], a[k + 1]))
    # flip normals to face -y (the camera)
    me = bpy.data.meshes.new("ground")
    bm.to_mesh(me)
    bm.free()
    for nm, vals in (("depth", depth_l), ("tint", tint_l), ("below", below_l)):
        at = me.attributes.new(name=nm, type="FLOAT", domain="POINT")
        at.data.foreach_set("value", vals)
    o = bpy.data.objects.new("ground", me)
    link(o)
    me.materials.append(terrain_material(look, town))
    for p in me.polygons:
        p.use_smooth = True
    # make sure normals face the camera at -y
    if me.polygons[0].normal.y > 0:
        for p in me.polygons:
            pass
        me.flip_normals()
    return o


def tree(kind, x_m, y_m, z_m, size_m, rng, parts):
    trunk = mat("trunk", 0x5a4331, 0.9)
    if kind == "conifer":
        cols = [mat("c1", 0x36553f, 0.85), mat("c2", 0x426a4b, 0.85)]
        parts.append(prim("cyl", "trunk", (x_m, y_m, z_m + size_m * 0.1), (size_m * 0.07, size_m * 0.07, size_m * 0.25), mats=[trunk], seg=6))
        for k in range(4):
            r = size_m * (0.32 - k * 0.055)
            parts.append(prim("cone", "cone", (x_m, y_m, z_m + size_m * (0.2 + k * 0.2) + size_m * 0.15), (r * 2, r * 2, size_m * 0.36), mats=[cols[k % 2]], seg=9, r2=0.0, smooth=False))
    else:
        cols = [mat("b1", 0x4a7040, 0.85), mat("b2", 0x5f8a50, 0.85)]
        parts.append(prim("cyl", "trunk", (x_m, y_m, z_m + size_m * 0.18), (size_m * 0.07, size_m * 0.07, size_m * 0.36), mats=[trunk], seg=6))
        for dx, dz, r in ((-0.16, 0.52, 0.26), (0.16, 0.55, 0.25), (0.0, 0.74, 0.28)):
            parts.append(prim("sphere", "leaf", (x_m + dx * size_m, y_m, z_m + dz * size_m), (r * 2 * size_m, r * 2 * size_m, r * 1.8 * size_m), mats=[cols[rng.randrange(2)]], seg=10, rings=6))


def platforms(mission, gh):
    """Offshore: steel columns and braces on the front of every platform block, a drill tower behind the big ones."""
    t = mission["terrain"]
    steel = mat("steel", 0x8a949c, 0.5, metal=0.6)
    dark = mat("steeld", 0x4a535a, 0.6, metal=0.5)
    red = mat("steelr", 0xc75d3b, 0.6)
    blocks = [(a[0], b[0], a[1]) for a, b in zip(t, t[1:]) if a[1] == b[1] and a[1] > 100 and b[0] < mission["base"]["x"] - mission["base"]["width"]]
    for x0, x1, top in blocks:
        w = x1 - x0
        n = max(1, int(w / 110))
        for i in range(n + 1):
            x = (x0 + 4 + (w - 8) * i / n) * U
            tube("col", [(x, -0.8, -90 * U), (x, -0.8, (top - 8) * U)], 0.45 if w > 150 else 0.2, steel, 6)
        for i in range(n):
            xa, xb = (x0 + 4 + (w - 8) * i / n) * U, (x0 + 4 + (w - 8) * (i + 1) / n) * U
            for k in range(int((top + 40) / 100)):
                za, zb = (k * 100 - 20) * U, min(top - 12, k * 100 + 80) * U
                tube("br", [(xa, -0.9, za), (xb, -0.9, zb)], 0.12, dark, 4)
                tube("br", [(xb, -0.9, za), (xa, -0.9, zb)], 0.12, dark, 4)
        slab_m = prim("cube", "lip", ((x0 + x1) / 2 * U, -0.7, (top - 7) * U), (w * U, 0.5, 0.45), mats=[red], bevel=0.05)
        if w > 300:      # drill tower behind the deck, out of the flight path
            cx, base_z = (x0 + 90) * U, (top - 4) * U
            for s in (-1, 1):
                tube("leg", [(cx + s * 2.2, 3.5, base_z), (cx + s * 0.4, 3.5, base_z + 11)], 0.16, red, 5)
            for k in range(1, 6):
                half = 2.2 - 1.8 * k / 6
                z = base_z + 11 * k / 6
                tube("rung", [(cx - half, 3.5, z), (cx + half, 3.5, z)], 0.07, steel, 4)


def scatter(mission, gh, look):
    L = LOOKS[look]
    rng = hexrand(901)
    W = mission["world"]["width"]
    parts = []
    lakes = mission.get("lakes") or []
    pts = mission["rescuePoints"]
    base = mission["base"]
    if L["trees"]:
        gx = -38.0
        while gx < W + 38:
            wx = gx + rng.uniform(-10, 10)
            near = any(abs(p["x"] - wx) < p["width"] / 2 + 60 for p in pts)
            in_camp = abs(wx - base["x"]) < base["width"] / 2 + 40
            wet = any(l["x0"] - 10 <= wx <= l["x1"] + 10 and gh(wx) <= l["level"] + 6 for l in lakes)
            r = rng.random()
            if not near and not in_camp and not wet and r > 0.45 and 40 < wx < W - 40:
                g = gh(wx)
                size = rng.uniform(34, 66) * U
                tree("conifer" if rng.random() > 0.35 else "round", wx * U, rng.uniform(0.3, 2.8), (g - 3) * U, size, rng, parts)
            gx += 38
    if L["rocks"]:
        rs = hexrand(55)
        col = {"coast": 0x6b6862, "volcano": 0x2b2522, "alpine": 0x8a9098}[look]
        gx = 0.0
        while gx < W:
            wx = gx + rs.uniform(0, 70)
            near = any(abs(p["x"] - wx) < p["width"] / 2 + 70 for p in pts) or abs(wx - base["x"]) < base["width"] / 2 + 60
            if not near and rs.random() > 0.5:
                g = gh(wx)
                s = rs.uniform(10, 34) * U
                o = prim("sphere", "rock", (wx * U, rs.uniform(0.2, 1.5), (g + 2) * U), (s * 2, s * 1.4, s * 1.2), mats=[mat("rk%x" % col, col, 0.95)], seg=7, rings=5, smooth=False)
                parts.append(o)
            gx += 60
    return parts


def main():
    preview = "--preview" in argv()
    only = [a.split("=")[1] for a in argv() if a.startswith("--only=")]
    onlychunk = [int(a.split("=")[1]) for a in argv() if a.startswith("--chunk=")]
    mf = os.path.join(OUT, "terrain", "terrain.json")
    meta = json.load(open(mf)) if os.path.exists(mf) else {}
    for fn in sorted(os.listdir(MISSIONS)):
        if not fn.endswith(".json"): continue
        mission = json.load(open(os.path.join(MISSIONS, fn)))
        if only and mission["id"] not in only: continue
        look = mission.get("look") or "valley"
        if look not in LOOKS: look = "valley"
        reset()
        ts = mission["terrain"]
        gh = gh_fn(ts)
        lowest, highest = min(p[1] for p in ts), max(p[1] for p in ts)
        ymin = max(-120, min(0, lowest - 10))
        ymax = max(480, highest + 40)
        build_ground(mission, gh, ymin, look)
        scatter(mission, gh, look)
        if look == "offshore":
            platforms(mission, gh)
        H_px = int(math.ceil((ymax - ymin) * S))
        W = mission["world"]["width"]
        n = int(math.ceil(W / CHUNK))
        setup_render(int(CHUNK * S), H_px, samples=12 if preview else 40)
        world(strength=1.0)
        cam = ortho_camera(width=CHUNK * U)
        pivot = bpy.data.objects.new("pivot", None); link(pivot)
        sun("key", 4.2, (52, 0, -35), parent=pivot)
        sun("fill", 1.1, (70, 0, 140), color=(0.8, 0.88, 1.0), parent=pivot)
        sun("rim", 1.6, (115, 0, 200), parent=pivot)
        pivot.rotation_euler = (0, 0, math.radians(-90))
        # sun rig shifted so shadows read the same in every chunk: lights are directional, so no change needed
        cz = (ymin + ymax) / 2 * U
        for c in range(n):
            if onlychunk and c not in onlychunk: continue
            cx = (c * CHUNK + CHUNK / 2) * U
            cam.location = (cx, -80, cz)
            cam.rotation_euler = (math.radians(90), 0, 0)
            render(os.path.join(OUT, "terrain", "%s-%d.png" % (mission["id"], c)))
            print("chunk", mission["id"], c)
        meta[mission["id"]] = {"chunks": n, "yMin": ymin, "yMax": ymax, "chunk": CHUNK, "ppu": S}
        json.dump(meta, open(mf, "w"), indent=1)


if __name__ == "__main__":
    main()
