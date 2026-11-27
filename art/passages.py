"""Passages: mountain and rock above a tunnel, the tunnel's inside and portals, bridges above an underpass,
shutter parts and signal lamps.

Scale: 1 world unit = 1/16 m, rendered at 2 px per unit (like the pads). Straight-on view with a low sun so the relief reads.
Outputs in Renders/passages/:
  mass-<mission>-<passage>.png      the solid above the roof (tunnel x0-24..x1+24, bridge x0-16..x1+16, roof..ceiling+12)
  pier-<mission>-<passage>.png      the support at both ends of a bridge (44 units wide, roof+40 high)
  flank-<mission>-<passage>.png     the mountain behind a tunnel (x0-300..x1+300, floor-140..ceiling+40), behind the terrain
  interior-<mission>-<passage>.png  the lit back wall of a tunnel (x0..x1, floor..roof)
  jamb-<mission>-<passage>.png      portal frame at a tunnel end (26 units wide, floor..roof)
  shutter-door/bar/post/housing.png, signal-green/amber/red.png, beacon.png

Usage: blender -b -P art/passages.py [-- --preview] [--masses] [--parts] [--bridges] [--only=<mission>]
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
from mathutils import noise
from terrain import gh_fn

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


def shoot(path, w_u, h_u, build, samples=32, scale=S, key_rot=(74, 0, -50), key_energy=4.0, fill=1.2, sky=1.1):
    """Straight-on render of `build()`; the content spans x -w/2..w/2 and z 0..h (metres), camera looks along +y."""
    reset()
    build()
    W, H = int(w_u * scale), int(h_u * scale)
    setup_render(W, H, samples=samples)
    world(strength=sky)
    cam = ortho_camera(width=w_u * U)
    sun("key", key_energy, key_rot, color=(1.0, 0.95, 0.86))
    sun("fill", fill, (80, 0, 150), color=(0.8, 0.88, 1.0))
    target = Vector((0, 0, h_u * U / 2))
    cam.location = target + Vector((0, -60, 0))
    aim(cam, target)
    render(path)
    print("passage", os.path.basename(path), W, H)


# ---------------------------------------------------------------- tunnels

# rock (dark, light), cover on ledges, cover amount, concrete, haze colour of the mountain behind
ROCKS = {
    "vulkan": dict(rock=(0x2e2421, 0x7d6455), cover=0x9a918a, amount=0.35, conc=0x8f8276, haze=0x6a4c40, lava=True),
    "gebirge": dict(rock=(0x464b52, 0x9c9a94), cover=0xf2f6fa, amount=0.8, conc=0xa9a69e, haze=0xa9bccd, lava=False),
    "pass": dict(rock=(0x434a55, 0x8b929c), cover=0xeef3f8, amount=1.0, conc=0x9ca1a8, haze=0xb4c1cf, lava=False),
}

def smoothstep(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def relief(x, z, seed):
    """depth of the rock face towards the camera in metres: buttresses, blocks and broken ledges"""
    wx = noise.noise((x * 0.13 + seed, z * 0.13, 0.5)) * 2.8
    wz = noise.fractal((x * 0.2, z * 0.2, seed + 3.3), 0.6, 2.0, 3) * 2.4
    big = noise.fractal(((x + wx) * 0.14 + seed, (z + wz) * 0.09, 2.1), 0.7, 2.0, 4)
    rib = 1 - abs(noise.noise(((x + wx) * 0.34 + seed, (z + wz) * 0.11, 5.3)))
    block = noise.voronoi(((x + wx) * 0.34, (z + wz) * 0.46, seed))
    edge = block[0][1] - block[0][0]
    face = noise.cell((block[1][0][0] * 7.1, block[1][0][1] * 5.3, block[1][0][2] + seed))
    zz = (z + wz * 1.5 + x * 0.07) / 3.9
    f = zz - math.floor(zz)
    mask = smoothstep(-0.05, 0.35, noise.noise((x * 0.17 + seed * 2, math.floor(zz) * 4.3, 0.2)))
    ledge = smoothstep(0.0, 0.7, f) * (1 - smoothstep(0.84, 1.0, f)) * mask
    small = noise.fractal((x * 0.85, z * 1.1, seed), 0.55, 2.2, 5)
    return big * 1.5 + rib * rib * 1.2 + min(edge, 0.6) * 0.9 + face * 0.35 + ledge * 1.1 + small * 0.42


def rock_material(name, pal, bump=1.0, haze=0.0):
    """rock colour from noise, lighter cover (snow, ash) from the point attribute `cover`, optional haze"""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Roughness"].default_value = 0.93
    tc = nt.nodes.new("ShaderNodeTexCoord")

    def nz(scale, detail, stretch=(1, 1, 1)):
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = stretch
        n = nt.nodes.new("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = 0.65
        nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
        nt.links.new(mp.outputs["Vector"], n.inputs["Vector"])
        return n.outputs["Fac"]

    def mixc(fac, a, b):
        mx = nt.nodes.new("ShaderNodeMix"); mx.data_type = "RGBA"
        if isinstance(fac, float): mx.inputs[0].default_value = fac
        else: nt.links.new(fac, mx.inputs[0])
        for sock, v in ((mx.inputs[6], a), (mx.inputs[7], b)):
            if isinstance(v, tuple): sock.default_value = v
            else: nt.links.new(v, sock)
        return mx.outputs[2]

    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.36
    ramp.color_ramp.elements[0].color = srgb(pal["rock"][0])
    ramp.color_ramp.elements[1].position = 0.68
    ramp.color_ramp.elements[1].color = srgb(pal["rock"][1])
    strata = nz(0.5, 6.0, (0.35, 0.35, 2.6))
    nt.links.new(strata, ramp.inputs["Fac"])
    col = ramp.outputs["Color"]
    at = nt.nodes.new("ShaderNodeAttribute"); at.attribute_name = "cover"
    col = mixc(at.outputs["Fac"], col, srgb(pal["cover"]))
    if haze:
        col = mixc(float(haze), col, srgb(pal["haze"]))
    nt.links.new(col, p.inputs["Base Color"])
    bp = nt.nodes.new("ShaderNodeBump")
    bp.inputs["Strength"].default_value = bump
    bp.inputs["Distance"].default_value = 0.3
    nt.links.new(nz(2.4, 9.0, (1, 1, 1.8)), bp.inputs["Height"])
    nt.links.new(bp.outputs["Normal"], p.inputs["Normal"])
    return m


def grid_mesh(name, columns, material, cover_of):
    """columns: list of columns of (x, y, z); builds quads and the attribute `cover` from the slope of the surface"""
    bm = bmesh.new()
    verts = [[bm.verts.new(p) for p in col] for col in columns]
    for a, b in zip(verts, verts[1:]):
        for k in range(len(a) - 1):
            bm.faces.new((a[k], b[k], b[k + 1], a[k + 1]))
    bm.normal_update()
    bm.verts.index_update()
    cov = [0.0] * len(bm.verts)
    for col in verts:
        for v in col:
            cov[v.index] = cover_of(v.co, v.normal)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    at = me.attributes.new(name="cover", type="FLOAT", domain="POINT")
    at.data.foreach_set("value", cov)
    me.materials.append(material)
    o = bpy.data.objects.new(name, me)
    link(o)
    return o


def cover_fn(pal, seed):
    def f(co, n):
        up = n.z + noise.noise((co.x * 0.7, co.z * 0.9, seed)) * 0.22
        patch = noise.fractal((co.x * 0.12, co.z * 0.12, seed + 4), 0.6, 2.0, 3)
        return min(1.0, max(0.0, smoothstep(0.34, 0.62, up) * pal["amount"] + max(0.0, patch) * 0.12 * pal["amount"]))
    return f


def tunnel_mass(w_u, h_u, pal, seed):
    """cliff above the roof with a ragged outline and the concrete portal band at the bottom"""
    w, h = w_u * U, h_u * U
    half = w / 2 - 24 * U                   # the passage itself ends here
    nx, nz = int(w / 0.16), int(h / 0.14)

    def edge(z, side):
        n = noise.fractal((z * 0.22, side * 7.0 + seed, 0.4), 0.7, 2.0, 5)
        step = noise.noise((math.floor(z / 2.7) * 5.1, side * 3.0, seed))
        base = half + 7 * U + (n * 11 + step * 9) * U
        low = smoothstep(2.5, 6.0, z)       # flush with the portal at the bottom
        return (half + 6 * U) * (1 - low) + min(half + 24 * U, max(half - 8 * U, base)) * low

    cols = []
    for i in range(nx + 1):
        u = i / nx * 2 - 1
        col = []
        for k in range(nz + 1):
            z = h * k / nz
            x = u * edge(z, 1 if u > 0 else -1)
            rim = smoothstep(0.86, 1.0, abs(u))
            y = 1.6 - relief(x, z, seed) * (1 - 0.7 * rim) + rim * rim * 2.2
            col.append((x, y, z))
        cols.append(col)
    grid_mesh("cliff", cols, rock_material("rock", pal), cover_fn(pal, seed))

    conc = textured("conc", 0x5c564f, pal["conc"], scale=1.4, bump=0.35, rough=0.9, detail=10.0)
    dark = M("conc-dark", 0x35312d, 0.9)
    stain = M("stain", 0x4a453f, 0.95)
    band = 2 * half + 0.5
    slab("fascia", (0, -1.6, 0.62), (band, 1.1, 1.24), conc, 0.08)
    slab("drip", (0, -2.2, 1.22), (band + 0.2, 0.3, 0.2), conc, 0.04)
    slab("soffit", (0, -2.1, 0.07), (band, 0.2, 0.14), dark, 0.01)
    rng = hexrand(int(w_u) + int(seed * 10))
    x = -band / 2 + 3.2
    while x < band / 2 - 3.2:
        slab("joint", (x, -2.17, 0.62), (0.07, 0.05, 1.18), dark, 0.0)
        slab("run", (x + rng.uniform(0.3, 2.6), -2.17, 0.62 + rng.uniform(-0.2, 0.2)), (rng.uniform(0.08, 0.3), 0.02, rng.uniform(0.4, 0.8)), stain, 0.0)
        x += 3.4
    # portal headwalls: stepped buttresses with a coping and a few warning stripes
    yel, blk = M("yel", 0xd9b44a, 0.6), M("blk", 0x262422, 0.7)
    for sx in (-1, 1):
        cx = sx * (half - 1.1)
        slab("head", (cx, -2.0, 2.0), (2.7, 1.3, 4.0), conc, 0.1)
        slab("head2", (cx + sx * 0.2, -2.0, 4.6), (2.1, 1.1, 1.3), conc, 0.1)
        slab("cap", (cx, -2.2, 4.1), (3.0, 1.5, 0.28), conc, 0.05)
        slab("cap2", (cx + sx * 0.2, -2.15, 5.35), (2.4, 1.35, 0.22), conc, 0.05)
        for i in range(4):
            slab("warn", (sx * (half - 0.35 - i * 0.55), -2.68, 0.55), (0.27, 0.05, 0.85), yel if i % 2 == 0 else blk, 0.01)


def flank(w_u, h_u, pal, seed, passage_w, floor_above_bottom):
    """the mountain behind a tunnel: slopes that rise from far left and right to the full height behind the passage"""
    w, h = w_u * U, h_u * U
    half = passage_w * U / 2
    base = floor_above_bottom * U
    nx, nz = int(w / 0.22), int(h / 0.22)

    def top_of(x):
        d = max(0.0, abs(x) - half)
        t = 1 - min(1.0, d / (w / 2 - half - 0.3))
        n = noise.fractal((x * 0.16 + seed, 0.7, 0.2), 0.65, 2.0, 6)
        shoulder = noise.noise((x * 0.07 + seed * 3, 2.2, 0.0))
        shape = t ** 1.7 + shoulder * 0.14 * smoothstep(0.0, 0.3, t) * (1 - smoothstep(0.75, 1.0, t))
        return base + (h * 1.03 - base) * max(0.0, shape) + n * 2.2 * smoothstep(0.02, 0.2, t)

    cols = []
    for i in range(nx + 1):
        x = -w / 2 + w * i / nx
        top = max(0.4, min(h, top_of(x)))
        col = []
        for k in range(nz + 1):
            z = min(top, h * k / nz)          # regular rows, the silhouette is cut at the top
            crest = smoothstep(top - 2.5, top, z)
            y = 1.5 - relief(x * 0.8, z * 0.8, seed + 9) * 1.1 + crest * 1.8
            col.append((x, y, z))
        cols.append(col)
    grid_mesh("flank", cols, rock_material("flankrock", pal, bump=0.7, haze=0.34), cover_fn(pal, seed + 2))


def interior(w_u, h_u, pal, seed):
    """back wall of a tunnel: vaulted lining with ribs, lamps with pools of light, road at the bottom"""
    w, h = w_u * U, h_u * U
    lava = pal["lava"]
    nx, nz = int(w / 0.18), int(h / 0.14)
    cols = []
    for i in range(nx + 1):
        x = -w / 2 + w * i / nx
        col = []
        for k in range(nz + 1):
            z = h * k / nz
            t = z / h * 2 - 1
            y = 2.2 - 2.0 * t ** 4              # curves towards the camera at roof and floor
            if lava:
                y -= relief(x * 1.4, z * 1.4, seed + 21) * 0.34
            col.append((x, y, z))
        cols.append(col)
    if lava:
        wall = rock_material("lining", dict(pal, rock=(0x2a211e, 0x6e5a4e), cover=0x4a3c35), bump=1.0)
        grid_mesh("lining", cols, wall, lambda co, n: 0.0)
    else:
        wall = textured("lining", 0x4d4a45, 0x8b877e, scale=0.8, bump=0.35, rough=0.9, detail=11.0)
        grid_mesh("lining", cols, wall, lambda co, n: 0.0)
    rib = M("rib", 0x6a4a36 if lava else 0x8e8a82, 0.75, metal=0.3 if lava else 0.0)
    dark = M("idark", 0x161412, 0.9)
    spacing = 5.0
    n = max(2, int(w / spacing))
    for i in range(n + 1):
        x = -w / 2 + w * i / n
        pts = []
        for k in range(9):
            z = h * k / 8
            t = z / h * 2 - 1
            pts.append((x, 2.2 - 2.0 * t ** 4 - 0.35, z))
        tube("rib", pts, 0.22 if lava else 0.3, rib, 4)
        if i < n:
            mx = x + w / n / 2
            if i % 2 == 1:                     # escape niche with a green sign
                slab("niche", (mx, 1.75, h * 0.28), (1.5, 0.3, h * 0.34), dark, 0.05)
                slab("sign", (mx, 1.55, h * 0.49), (0.8, 0.05, 0.28), M("exit", 0x2fae62, 0.4, emit=0x2fae62, strength=1.6), 0.01)
            slab("lamp", (mx, 0.55, h - 0.55), (1.3, 0.25, 0.16), M("tl", 0xffd9a0, 0.4, emit=0xffc37a, strength=9), 0.03)
            ld = bpy.data.lights.new("pool", "AREA")
            ld.energy = 130
            ld.color = (1.0, 0.72, 0.42)
            ld.size = 1.4
            o = bpy.data.objects.new("pool", ld)
            o.location = (mx, -0.2, h - 1.0)
            o.rotation_euler = (math.radians(35), 0, 0)
            link(o)
    for k, z in enumerate((h * 0.66, h * 0.7)):
        tube("cable", [(-w / 2, 1.5, z), (w / 2, 1.5, z)], 0.05, dark, 3)
    slab("road", (0, 0.4, 0.2), (w, 2.0, 0.4), M("road", 0x2b2927, 0.85), 0.03)
    slab("kerb", (0, -0.62, 0.44), (w, 0.2, 0.14), M("kerb", 0x8d877c, 0.8), 0.02)
    slab("lane", (0, -0.63, 0.2), (w, 0.04, 0.07), M("lane", 0xb9a04a, 0.6), 0.0)


def jamb(h_u, pal):
    h = h_u * U
    conc = textured("jconc", 0x55504a, pal["conc"], scale=1.8, bump=0.4, rough=0.9, detail=10.0)
    slab("post", (0, 0, h / 2), (1.25, 0.7, h), conc, 0.12)
    z = 0.7
    while z < h:
        slab("joint", (0, -0.36, z), (1.25, 0.04, 0.07), M("jd", 0x38342f, 0.9), 0.0)
        z += 1.5
    yel, blk = M("yel", 0xd9b44a, 0.6), M("blk", 0x262422, 0.7)
    for i in range(9):
        slab("warn", (0, -0.37, 0.2 + i * 0.36), (0.46, 0.04, 0.34), yel if i % 2 == 0 else blk, 0.0)
    slab("foot", (0, -0.05, 0.18), (1.6, 0.85, 0.36), conc, 0.05)


# ---------------------------------------------------------------- bridges

# Over an underpass there is no way (the span is solid up to the flight ceiling), so each bridge is a structure that
# visibly closes the sky above its deck: tiers of blind arches (masonry) or a tall braced truss with netting behind.

MASONRY = {
    "stone": dict(block=((0x8f7f68, 0xc9b999), 0xd9cdb2), mortar=0x6e6252, infill=(0x6d6050, 0x93826a), brick=False),
    "brick": dict(block=((0x6e3526, 0xa8583a), 0xc7b29a), mortar=0x8a735f, infill=(0x4a281f, 0x71402e), brick=True),
}
BRIDGE_KIND = {("altstadt", "viadukt"): "stone", ("staudamm", "eisenbahnbruecke"): "brick",
               ("staudamm", "holzbruecke"): "timber", ("hochwasser", "bruecke"): "steel"}
ARCH_TIER = 8.4          # metres from cornice to cornice


def ashlar(name, c1, c2, bw, bh, mortar):
    """masonry: courses of blocks with mortar joints and weathering"""
    m = textured(name, c1, c2, scale=1.1, bump=0.5, rough=0.92, detail=10.0)
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    base = p.inputs["Base Color"].links[0].from_socket
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    comb = nt.nodes.new("ShaderNodeCombineXYZ")
    nt.links.new(sep.outputs["X"], comb.inputs["X"])
    nt.links.new(sep.outputs["Z"], comb.inputs["Y"])
    br = nt.nodes.new("ShaderNodeTexBrick")
    br.inputs["Scale"].default_value = 1.0
    br.inputs["Brick Width"].default_value = bw
    br.inputs["Row Height"].default_value = bh
    br.inputs["Mortar Size"].default_value = 0.03
    br.inputs["Color1"].default_value = (1.0, 1.0, 1.0, 1)
    br.inputs["Color2"].default_value = (0.68, 0.66, 0.64, 1)
    br.inputs["Mortar"].default_value = srgb(mortar)
    nt.links.new(comb.outputs[0], br.inputs["Vector"])
    mx = nt.nodes.new("ShaderNodeMix"); mx.data_type = "RGBA"; mx.blend_type = "MULTIPLY"
    mx.inputs[0].default_value = 0.9
    nt.links.new(base, mx.inputs[6])
    nt.links.new(br.outputs["Color"], mx.inputs[7])
    nt.links.new(mx.outputs[2], p.inputs["Base Color"])
    return m


def poly_slab(name, pts, y, depth, material):
    """flat shape in x/z, extruded towards the back"""
    bm = bmesh.new()
    face = bm.faces.new([bm.verts.new((x, y, z)) for x, z in pts])
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    bmesh.ops.translate(bm, verts=[v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)], vec=(0, depth, 0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_obj(name, bm, [material])


def arch_ring(cx, spring, r, ring, y, depth, material, stones=11):
    """the voussoirs of a round arch"""
    for i in range(stones):
        a0, a1 = math.pi * i / stones + 0.006, math.pi * (i + 1) / stones - 0.006
        pts = [(cx + math.cos(a) * rr, spring + math.sin(a) * rr)
               for a, rr in ((a0, r), (a0, r + ring), (a1, r + ring), (a1, r))]
        poly_slab("voussoir", pts, y - (0.06 if i == stones // 2 else 0.0), depth, material)


def masonry_bridge(w_u, h_u, kind):
    st = MASONRY[kind]
    w, h = w_u * U, h_u * U
    c1, c2 = st["block"][0]
    bw, bh = (0.42, 0.14) if st["brick"] else (1.1, 0.5)
    face = ashlar("face", c1, c2, bw, bh, st["mortar"])
    infill = ashlar("infill", st["infill"][0], st["infill"][1], bw, bh, st["mortar"])
    trim = textured("trim", c1, st["block"][1], scale=2.0, bump=0.4, rough=0.85)
    slab("wall", (0, 0.45, h / 2), (w - 0.1, 0.5, h), infill, 0.0)          # closed wall behind every arch
    deck_h = 2.0
    slab("deck", (0, -0.1, deck_h / 2), (w, 1.1, deck_h), face, 0.05)
    slab("deckcap", (0, -0.35, deck_h + 0.18), (w, 1.3, 0.36), trim, 0.06)
    slab("decklip", (0, -0.45, 0.14), (w, 0.9, 0.28), trim, 0.04)
    n = max(2, int(round(w / 6.5)))
    bay = w / n
    pier = 1.15
    r = (bay - pier) / 2 - 0.35
    z = deck_h + 0.36
    tier = 0
    while z < h:
        top = z + ARCH_TIER
        spring = top - 0.9 - r - 0.55
        for i in range(n + 1):
            x = -w / 2 + i * bay
            half = pier / 2
            px = max(-w / 2 + half, min(w / 2 - half, x))
            slab("pier", (px, -0.15, z + ARCH_TIER / 2), (pier, 0.8, ARCH_TIER), face, 0.05)
            slab("impost", (px, -0.3, spring), (pier + 0.35, 0.95, 0.28), trim, 0.04)
        for i in range(n):
            cx = -w / 2 + (i + 0.5) * bay
            arch_ring(cx, spring, r, 0.55, -0.63, 0.75, trim)
            # spandrel: everything above the arch up to the cornice
            outer = r + 0.55
            arc = [(cx + math.cos(math.pi * k / 24) * outer, spring + math.sin(math.pi * k / 24) * outer) for k in range(25)]
            pts = [(cx + bay / 2, spring), (cx + bay / 2, top), (cx - bay / 2, top), (cx - bay / 2, spring)] + arc[::-1]
            poly_slab("spandrel", pts, -0.3, 0.55, face)
            if tier % 2 == 1:        # a few small windows in the infill, for scale
                slab("slit", (cx, 0.18, spring - 0.5), (0.45, 0.1, 1.4), M("slit", 0x1e1a16, 0.9), 0.03)
        slab("cornice", (0, -0.45, top - 0.18), (w, 1.2, 0.36), trim, 0.06)
        z = top
        tier += 1


def beam(name, a, b, size, y, depth, material):
    """straight member from a to b (x, z) with width `size`"""
    dx, dz = b[0] - a[0], b[1] - a[1]
    L = math.hypot(dx, dz) or 1.0
    nx, nz = -dz / L * size / 2, dx / L * size / 2
    pts = [(a[0] + nx, a[1] + nz), (b[0] + nx, b[1] + nz), (b[0] - nx, b[1] - nz), (a[0] - nx, a[1] - nz)]
    return poly_slab(name, pts, y, depth, material)


def netting(w, z0, z1, colour):
    """a thin veil behind the truss, so it reads as one closed structure"""
    m = mat("veil%x" % colour, colour, rough=1.0, alpha=0.5)
    poly_slab("veil", [(-w / 2 + 0.15, z0), (w / 2 - 0.15, z0), (w / 2 - 0.15, z1), (-w / 2 + 0.15, z1)], 1.4, 0.02, m)


def rivets(x, z, material):
    prim("sphere", "rivet", (x, -0.75, z), (0.13, 0.08, 0.13), mats=[material], seg=8, rings=6)


def steel_bridge(w_u, h_u):
    w, h = w_u * U, h_u * U
    paint = textured("paint", 0x466058, 0x6f8c80, scale=0.9, bump=0.15, rough=0.5)
    back = M("paint-back", 0x2f423d, 0.6, metal=0.2)
    plate = textured("plate", 0x3c544c, 0x607c71, scale=1.4, bump=0.2, rough=0.55)
    knob = M("knob", 0x8da297, 0.35, metal=0.6)
    rust = M("rust", 0x7a4a30, 0.8)
    netting(w, 2.2, h, 0x34453f)
    # plate girder under the roadway
    slab("web", (0, -0.1, 1.15), (w, 0.8, 2.1), plate, 0.02)
    for z in (0.12, 2.22):
        slab("flange", (0, -0.35, z), (w, 1.1, 0.24), paint, 0.03)
    n = int(w / 1.3)
    for i in range(n + 1):
        x = -w / 2 + 0.1 + (w - 0.2) * i / n
        slab("stiffener", (x, -0.55, 1.15), (0.16, 0.14, 1.9), paint, 0.01)
        for z in (0.12, 2.22):
            rivets(x, z, knob)
    rng = hexrand(8)
    for i in range(9):
        slab("run", (rng.uniform(-w / 2 + 0.4, w / 2 - 0.4), -0.52, rng.uniform(0.6, 1.3)), (rng.uniform(0.05, 0.14), 0.02, rng.uniform(0.5, 1.1)), rust, 0.0)
    # truss above the roadway
    cols = max(2, int(round(w / 5.0)))
    xs = [-w / 2 + 0.35 + (w - 0.7) * i / cols for i in range(cols + 1)]
    tier = 5.2
    z = 2.34
    while z < h:
        top = z + tier
        for a, b in zip(xs, xs[1:]):
            beam("d1", (a, z), (b, top), 0.34, -0.45, 0.28, paint)
            beam("d2", (a, top), (b, z), 0.34, -0.15, 0.28, paint)
            mx = (a + b) / 2
            poly_slab("gusset", [(mx - 0.4, z + tier / 2), (mx, z + tier / 2 - 0.4), (mx + 0.4, z + tier / 2), (mx, z + tier / 2 + 0.4)], -0.62, 0.15, plate)
            rivets(mx, z + tier / 2, knob)
            # a second truss further back, half a bay over: depth
            beam("b1", (mx, z), (mx + (b - a) / 2, z + tier / 2), 0.22, 0.8, 0.2, back)
            beam("b2", (mx, z), (mx - (b - a) / 2, z + tier / 2), 0.22, 0.8, 0.2, back)
            beam("b3", (mx - (b - a) / 2, z + tier / 2), (mx, top), 0.22, 0.8, 0.2, back)
            beam("b4", (mx + (b - a) / 2, z + tier / 2), (mx, top), 0.22, 0.8, 0.2, back)
        slab("chord", (0, -0.35, top), (w, 0.6, 0.36), paint, 0.03)
        for x in xs:
            slab("post", (x, -0.4, z + tier / 2), (0.55, 0.55, tier), paint, 0.04)
            poly_slab("joint", [(x - 0.55, top - 0.4), (x + 0.55, top - 0.4), (x + 0.3, top + 0.45), (x - 0.3, top + 0.45)], -0.72, 0.1, plate)
            for dz in (-0.2, 0.2):
                rivets(x - 0.18, top + dz, knob)
                rivets(x + 0.18, top + dz, knob)
        z = top


def timber_bridge(w_u, h_u):
    w, h = w_u * U, h_u * U
    woods = [textured("wood%d" % i, c1, c2, scale=2.0, stretch=(2.4, 2.4, 0.5), bump=0.5, rough=0.9, detail=9.0)
             for i, (c1, c2) in enumerate(((0x4e3522, 0x86603c), (0x5a3f29, 0x9a734a)))]
    back = M("wood-back", 0x33241a, 0.95)
    iron = M("iron", 0x3a3633, 0.5, metal=0.7)
    netting(w, 2.0, h, 0x34261c)
    rng = hexrand(21)
    # deck: two stringers and the plank ends
    slab("stringer", (0, -0.25, 0.42), (w, 0.7, 0.84), woods[0], 0.08)
    x = -w / 2 + 0.2
    while x < w / 2 - 0.2:
        slab("plank", (x, -0.55, 1.08 + rng.uniform(-0.03, 0.03)), (0.34, 0.7, 0.46), woods[rng.randrange(2)], 0.04)
        x += 0.4
    slab("rail", (0, -0.35, 1.5), (w, 0.55, 0.38), woods[1], 0.06)
    cols = max(2, int(round(w / 3.8)))
    xs = [-w / 2 + 0.35 + (w - 0.7) * i / cols for i in range(cols + 1)]
    tier = 4.4
    z = 1.7
    k = 0
    while z < h:
        top = z + tier
        for i, (a, b) in enumerate(zip(xs, xs[1:])):
            beam("brace", (a, z + 0.15), (b, top - 0.15), 0.3, -0.3 - 0.02 * i, 0.2, woods[(i + k) % 2])
            beam("brace2", (a, top - 0.15), (b, z + 0.15), 0.3, -0.02 + 0.01 * i, 0.2, woods[(i + k + 1) % 2])
            beam("back", ((a + b) / 2, z), ((a + b) / 2 + rng.uniform(-0.2, 0.2), top), 0.3, 0.8, 0.3, back)
            beam("backh", (a, z + tier / 2), (b, z + tier / 2 + rng.uniform(-0.15, 0.15)), 0.22, 0.9, 0.2, back)
            prim("sphere", "bolt", ((a + b) / 2, -0.52, z + tier / 2), (0.2, 0.1, 0.2), mats=[iron], seg=8, rings=6)
        slab("cap", (0, -0.45, top), (w, 0.5, 0.42), woods[k % 2], 0.07)
        for x in xs:
            prim("cyl", "post", (x + rng.uniform(-0.04, 0.04), -0.35, z + tier / 2), (0.56, 0.56, tier), mats=[woods[rng.randrange(2)]], seg=10)
            slab("strap", (x, -0.72, top), (0.62, 0.06, 0.5), iron, 0.01)
        z = top
        k += 1


def bridge(w_u, h_u, kind):
    if kind in MASONRY:
        masonry_bridge(w_u, h_u, kind)
    elif kind == "timber":
        timber_bridge(w_u, h_u)
    else:
        steel_bridge(w_u, h_u)


def bridge_pier(w_u, h_u, kind):
    """the support below the deck, top edge = underside of the roof"""
    w, h = w_u * U, h_u * U
    if kind in MASONRY:
        st = MASONRY[kind]
        bw, bh = (0.42, 0.14) if st["brick"] else (1.1, 0.5)
        face = ashlar("pface", st["block"][0][0], st["block"][0][1], bw, bh, st["mortar"])
        trim = textured("ptrim", st["block"][0][0], st["block"][1], scale=2.0, bump=0.4, rough=0.85)
        poly_slab("shaft", [(-1.0, 0), (1.0, 0), (0.78, h), (-0.78, h)], -0.2, 0.7, face)
        slab("capital", (0, -0.3, h - 0.9), (2.0, 0.9, 0.36), trim, 0.05)
        poly_slab("haunch", [(-1.2, h), (1.2, h), (0.8, h - 0.75), (-0.8, h - 0.75)], -0.25, 0.7, trim)
        z = h - 5.5
        while z > 0:
            slab("band", (0, -0.3, z), (2.0, 0.85, 0.26), trim, 0.04)
            z -= 4.6
    elif kind == "timber":
        wood = textured("pwood", 0x4e3522, 0x8f6a43, scale=2.0, stretch=(2.4, 2.4, 0.5), bump=0.5, rough=0.9, detail=9.0)
        iron = M("iron", 0x3a3633, 0.5, metal=0.7)
        for sx in (-1, 1):
            tube("leg", [(sx * 1.05, 0, 0), (sx * 0.65, 0, h)], 0.24, wood, 5)
        z = h
        while z > 0.3:
            slab("tie", (0, -0.2, z - 0.15), (2.1, 0.2, 0.28), wood, 0.05)
            beam("x1", (-0.8, z), (0.9, z - 3.0), 0.2, -0.32, 0.14, wood)
            beam("x2", (0.8, z), (-0.9, z - 3.0), 0.2, -0.18, 0.14, wood)
            slab("strap", (0, -0.44, z - 1.5), (0.3, 0.05, 0.3), iron, 0.01)
            z -= 3.0
    else:
        conc = textured("pconc", 0x6d6a63, 0xaaa69c, scale=1.3, bump=0.4, rough=0.9, detail=10.0)
        dark = M("pdark", 0x45423d, 0.9)
        poly_slab("shaft", [(-1.05, 0), (1.05, 0), (0.8, h - 0.5), (-0.8, h - 0.5)], -0.2, 0.8, conc)
        slab("bearing", (0, -0.35, h - 0.2), (2.3, 1.0, 0.4), conc, 0.07)
        z = h - 2.6
        while z > 0:
            slab("joint", (0, -0.22, z), (2.0, 0.05, 0.06), dark, 0.0)
            z -= 2.4


def build_masses(preview):
    from_missions = []
    for fn in sorted(os.listdir(MISSIONS)):
        if fn.endswith(".json"):
            m = json.load(open(os.path.join(MISSIONS, fn)))
            for p in m.get("passages", []):
                from_missions.append((m, p))
    only = [a.split("=")[1] for a in argv() if a.startswith("--only=")]
    smp = 16 if preview else 40
    for m, p in from_missions:
        if "--bridges" in argv() and p["kind"] == "tunnel":
            continue
        if only and m["id"] not in only:
            continue
        key = "%s-%s" % (m["id"], p["id"])
        w = p["x1"] - p["x0"]
        h_u = m["world"]["ceiling"] - p["roof"] + 12
        if p["kind"] != "tunnel":
            kind = BRIDGE_KIND.get((m["id"], p["id"]), "stone")
            shoot(os.path.join(DIR, "mass-%s.png" % key), w + 32, h_u, lambda: bridge(w + 32, h_u, kind),
                  samples=smp, key_rot=(55, 0, -42), key_energy=3.8, fill=0.9, sky=0.9)
            shoot(os.path.join(DIR, "pier-%s.png" % key), 44, p["roof"] + 40, lambda: bridge_pier(44, p["roof"] + 40, kind),
                  samples=smp, key_rot=(60, 0, -42), key_energy=3.4, sky=0.9)
            continue
        pal = ROCKS.get(m["id"], ROCKS["gebirge"])
        seed = 1.3 + len(m["id"]) * 0.77
        gh = gh_fn(m["terrain"])
        floor = max(max(gh(x) for x in range(int(p["x0"]), int(p["x1"]) + 1, 4)), (m.get("flood") or {}).get("maxLevel", -999))
        gap = p["roof"] - floor
        shoot(os.path.join(DIR, "mass-%s.png" % key), w + 48, h_u, lambda: tunnel_mass(w + 48, h_u, pal, seed),
              samples=smp, key_rot=(48, 0, -42), key_energy=4.6, fill=0.7, sky=0.8)
        fh = m["world"]["ceiling"] + 40 - (floor - 140)
        shoot(os.path.join(DIR, "flank-%s.png" % key), w + 600, fh, lambda: flank(w + 600, fh, pal, seed, w, 140),
              samples=smp, scale=1, key_rot=(50, 0, -42), key_energy=3.6, fill=1.0, sky=1.0)
        shoot(os.path.join(DIR, "interior-%s.png" % key), w, gap, lambda: interior(w, gap, pal, seed),
              samples=smp * 2, key_rot=(75, 0, -30), key_energy=0.25, fill=0.15, sky=0.22)
        shoot(os.path.join(DIR, "jamb-%s.png" % key), 26, gap, lambda: jamb(gap, pal), samples=smp, key_energy=3.0, sky=0.8)


# ---------------------------------------------------------------- shutter parts

def hazard_stripes(w, z0, z1, y, period=0.55):
    """diagonal yellow and black stripes filling x -w/2..w/2, z z0..z1, as one mesh each"""
    yel, blk = M("hy", 0xf2c230, 0.5), M("hb", 0x1d1b19, 0.6)
    h = z1 - z0
    n = int((w + h) / (period / 2)) + 2
    for i in range(n):
        a = -w / 2 - h + i * period / 2
        pts = [(a, z0), (a + period / 2, z0), (a + period / 2 + h, z1), (a + h, z1)]
        # clip against the two vertical sides
        for lim, sg in ((-w / 2, 1), (w / 2, -1)):
            out = []
            for k, p in enumerate(pts):
                q = pts[(k + 1) % len(pts)]
                pin, qin = (p[0] - lim) * sg >= 0, (q[0] - lim) * sg >= 0
                if pin: out.append(p)
                if pin != qin:
                    t = (lim - p[0]) / (q[0] - p[0])
                    out.append((lim, p[1] + (q[1] - p[1]) * t))
            pts = out
        if len(pts) >= 3:
            bm = bmesh.new()
            bm.faces.new([bm.verts.new((x, y, z)) for x, z in pts])
            mesh_obj("stripe", bm, [yel if i % 2 == 0 else blk])


def shutter_door():
    steel = M("steel", 0xb9c2c9, 0.32, metal=0.75)
    steel2 = M("steel2", 0x8c969f, 0.4, metal=0.75)
    w, h = 24 * U, 200 * U
    n = int(h / 0.3)
    for i in range(n):
        z = (i + 0.5) * h / n
        prim("cyl", "slat", (0, 0, z), (h / n, 0.3, w), rot=(0, 90, 0), mats=[steel if i % 2 == 0 else steel2], seg=12)
    # a broad warning band every 2.5 m
    z = 0.15
    while z < h - 0.7:
        slab("bandback", (0, -0.2, z + 0.35), (w, 0.06, 0.74), M("hb", 0x1d1b19, 0.6), 0.0)
        hazard_stripes(w, z, z + 0.7, -0.25)
        z += 2.5
    red = M("edge", 0xd9402e, 0.4, emit=0xd9402e, strength=0.6)
    for sx in (-1, 1):
        slab("rail", (sx * (w / 2 - 0.07), -0.3, h / 2), (0.14, 0.1, h), red, 0.01)


def shutter_bar():
    w, h = 38 * U, 16 * U
    slab("base", (0, 0.1, h / 2), (w, 0.4, h), M("hb", 0x1d1b19, 0.6), 0.08)
    hazard_stripes(w - 0.16, 0.2, h - 0.1, -0.12, 0.62)
    slab("rubber", (0, -0.14, 0.1), (w, 0.2, 0.2), M("rubber", 0x151413, 0.8), 0.05)
    for sx in (-1, 1):
        prim("sphere", "red", (sx * (w / 2 - 0.2), -0.28, h / 2), (0.34, 0.24, 0.34), mats=[M("barlamp", 0xff3b2e, 0.25, emit=0xff3b2e, strength=3)])


def shutter_post():
    w, h = 10 * U, 200 * U
    slab("post", (0, 0.1, h / 2), (w, 0.4, h), M("postm", 0x3a4046, 0.45, metal=0.6), 0.05)
    z = 0.0
    while z < h:
        hazard_stripes(w - 0.12, z, min(h, z + 0.9), -0.13, 0.5)
        z += 1.8


def shutter_housing():
    w, h = 66 * U, 26 * U
    steel = M("hous", 0x59636c, 0.4, metal=0.6)
    slab("box", (0, 0.1, h / 2 + 0.05), (w, 0.9, h - 0.1), steel, 0.14)
    slab("lipb", (0, -0.36, 0.16), (w + 0.05, 0.16, 0.2), M("lipm", 0x262b30, 0.6), 0.03)
    slab("plate", (0, -0.38, h * 0.56), (w - 0.3, 0.05, h * 0.46), M("hb", 0x1d1b19, 0.6), 0.02)
    hazard_stripes(w - 0.44, h * 0.38, h * 0.74, -0.42, 0.7)
    for sx in (-1, 1):
        for sz in (0.22, 0.86):
            prim("sphere", "rivet", (sx * (w / 2 - 0.18), -0.37, h * sz), (0.12, 0.08, 0.12), mats=[M("rivet", 0xb9c2c9, 0.3, metal=0.8)])


def signal(lit):
    """traffic light: red on top, amber, green"""
    w, h = 18 * U, 46 * U
    slab("case", (0, 0.1, h / 2), (w, 0.5, h), M("case", 0x15171a, 0.45, metal=0.3), 0.16)
    slab("rim", (0, 0.2, h / 2), (w + 0.1, 0.3, h + 0.06), M("rimy", 0xf2c230, 0.5), 0.18)
    for name, col, z in (("red", 0xff2a1c, 0.8), ("amber", 0xffa81e, 0.5), ("green", 0x21e06a, 0.2)):
        on = name == lit
        mt = M("sig-%s-%d" % (name, on), col if on else 0x2b2a28, 0.3, emit=col if on else None, strength=2.2 if on else 0.0)
        prim("sphere", name, (0, -0.2, h * z), (0.82, 0.3, 0.82), mats=[mt], seg=32)
        slab("hood", (0, -0.38, h * z + 0.46), (0.94, 0.3, 0.1), M("hood", 0x101113, 0.6), 0.03)


def beacon():
    slab("foot", (0, 0, 0.12), (0.6, 0.4, 0.24), M("case", 0x15171a, 0.45), 0.04)
    prim("sphere", "dome", (0, 0, 0.4), (0.56, 0.4, 0.66), mats=[M("dome", 0xffa81e, 0.2, emit=0xffa81e, strength=1.4)])


def build_parts(preview):
    smp = 16 if preview else 48
    for name, w, h, fn in (("shutter-door", 24, 200, shutter_door), ("shutter-bar", 38, 16, shutter_bar),
                           ("shutter-post", 10, 200, shutter_post), ("shutter-housing", 66, 26, shutter_housing),
                           ("beacon", 12, 12, beacon)):
        shoot(os.path.join(DIR, name + ".png"), w, h, fn, samples=smp, key_energy=3.0)
    for col in ("green", "amber", "red"):
        shoot(os.path.join(DIR, "signal-%s.png" % col), 20, 48, lambda c=col: signal(c), samples=smp, key_energy=2.0, sky=0.7)


def main():
    preview = "--preview" in argv()
    os.makedirs(DIR, exist_ok=True)
    if "--masses" not in argv() and "--bridges" not in argv():
        build_parts(preview)
    if "--parts" not in argv():
        build_masses(preview)


if __name__ == "__main__":
    main()
