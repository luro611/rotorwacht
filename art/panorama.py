"""Backgrounds as two rendered parallax layers per Einsatz (Renders/panorama): `far-<mission>` (parallax 0.12) and
`hill-<mission>` (0.35). Layer widths follow the game: world width * parallax factor + 1280 units. 1.25 px per unit.

Mountains are eroded heightfields with colours painted per point (rock, forest, snow, sand), lit by a low sun, and
faded into haze towards their foot and with distance. Everything else (woods, towns, farms, sea, dam, platforms,
smoke and glow) is generated from code too: no external textures or models.

Usage: blender -b -P art/panorama.py [-- --preview] [--only=<mission>] [--layer=far|hill]
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
from mathutils import noise

U = 1 / 16.0
S = 1.25
E = math.radians(12)
# Height of the far layer (also in GameScene). Things at depth d appear about 3.3 * d units higher than modelled.
FAR_H = 640


# ---------------------------------------------------------------- numbers and colours

def clamp(x, a=0.0, b=1.0):
    return a if x < a else (b if x > b else x)


def sstep(a, b, x):
    t = clamp((x - a) / (b - a))
    return t * t * (3 - 2 * t)


def col(h):
    return srgb(h)[:3]


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def fbm(x, y, z=0.0, octaves=5, h=0.7):
    return noise.fractal((x, y, z), h, 2.0, octaves)


def ridged(x, y, z=0.0, octaves=4):
    s, a, f = 0.0, 0.55, 1.0
    for _ in range(octaves):
        n = 1 - abs(noise.noise((x * f, y * f, z)))
        s += a * n * n
        a *= 0.5
        f *= 2.03
    return s


# ---------------------------------------------------------------- materials

def paint_material(name, lit=True, haze=0xd3d7d3):
    """colour from the point attribute `col`, mixed into flat haze colour by the attribute `haze`; alpha from `alpha`"""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")

    def attr(n, output="Fac"):
        a = nt.nodes.new("ShaderNodeAttribute")
        a.attribute_name = n
        return a.outputs[output]

    colour = attr("col", "Color")
    if lit:
        bs = nt.nodes.new("ShaderNodeBsdfDiffuse")
        nt.links.new(colour, bs.inputs["Color"])
        base = bs.outputs[0]
    else:
        em = nt.nodes.new("ShaderNodeEmission")
        nt.links.new(colour, em.inputs["Color"])
        base = em.outputs[0]
    fog = nt.nodes.new("ShaderNodeEmission")
    fog.inputs["Color"].default_value = srgb(haze)
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(attr("haze"), mix.inputs[0])
    nt.links.new(base, mix.inputs[1])
    nt.links.new(fog.outputs[0], mix.inputs[2])
    clear = nt.nodes.new("ShaderNodeBsdfTransparent")
    amix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(attr("alpha"), amix.inputs[0])
    nt.links.new(clear.outputs[0], amix.inputs[1])
    nt.links.new(mix.outputs[0], amix.inputs[2])
    nt.links.new(amix.outputs[0], out.inputs["Surface"])
    return m


def point_mesh(name, verts, faces, cols, hazes, alphas, material, smooth_=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    ca = me.attributes.new("col", "FLOAT_COLOR", "POINT")
    flat = []
    for c in cols:
        flat.extend((c[0], c[1], c[2], 1.0))
    ca.data.foreach_set("color", flat)
    me.attributes.new("haze", "FLOAT", "POINT").data.foreach_set("value", hazes)
    me.attributes.new("alpha", "FLOAT", "POINT").data.foreach_set("value", alphas)
    me.materials.append(material)
    if smooth_:
        for p in me.polygons:
            p.use_smooth = True
    o = bpy.data.objects.new(name, me)
    link(o)
    return o


def grid_faces(nx, nz):
    f = []
    for i in range(nx):
        for k in range(nz):
            a = i * (nz + 1) + k
            f.append((a, a + nz + 1, a + nz + 2, a + 1))
    return f


def painted(name, x0, x1, z0, z1, depth, fn, material, step=3.0):
    """upright picture plane in layer units; fn(x, z) -> (colour, haze, alpha)"""
    nx, nz = max(1, int((x1 - x0) / step)), max(1, int((z1 - z0) / step))
    verts, cols, hz, al = [], [], [], []
    for i in range(nx + 1):
        x = x0 + (x1 - x0) * i / nx
        for k in range(nz + 1):
            z = z0 + (z1 - z0) * k / nz
            c, h, a = fn(x, z)
            verts.append((x * U, depth, z * U))
            cols.append(c)
            hz.append(h)
            al.append(a)
    return point_mesh(name, verts, grid_faces(nx, nz), cols, hz, al, material, False)


# ---------------------------------------------------------------- mountains

def mountain(W, depth, foot_depth, crest, paint, material, seed, gully=14.0, rows=46, step=2.6):
    """A range seen from the side. crest(x) is the height of the skyline in units; the slopes fall towards the viewer
    over foot_depth metres, cut by erosion gullies. paint(x, z, hmax, slope, gully) -> (colour, haze)."""
    nx = int((W + 40) / step)
    verts, cols, hz, al = [], [], [], []
    tops = [crest(-20 + i * step) for i in range(nx + 1)]
    hmax = max(tops)
    for i in range(nx + 1):
        x = -20 + i * step
        top = tops[i]
        slope = abs(tops[min(nx, i + 3)] - tops[max(0, i - 3)]) / (6 * step)
        for k in range(rows + 2):
            t = max(0, k - 1) / rows                 # 0 at the foot, 1 on the crest
            wx = x + fbm(x * 0.011, t * 3.0, seed, 3) * 34 + (1 - t) * 40 * noise.noise((x * 0.006, seed, 0.0))
            g = ridged(wx * 0.017 + seed, t * 1.2, seed * 1.7, 4) - 0.55
            z = top * (t ** 1.25)
            z += g * gully * 2.0 * math.sin(math.pi * min(1.0, t * 0.97 + 0.015)) * clamp(top / hmax * 1.4)
            z += fbm(x * 0.05, t * 14.0, seed + 3, 3) * 3.0 * (1 - t * 0.6)
            if k == 0:
                z = -40.0
            y = depth - foot_depth * (1 - t) - g * 1.6
            c, h = paint(x, max(0.0, z), hmax, slope, g)
            verts.append((x * U, y, z * U))
            cols.append(c)
            hz.append(h)
            al.append(1.0)
    return point_mesh("range", verts, grid_faces(nx, rows + 1), cols, hz, al, material)


def skyline(seed, base, amp, jag, freq=1.0):
    def f(x):
        X = x * freq
        soft = fbm(X * 0.0022 + seed, seed, 0.3, 5, 0.9)
        peaks = ridged(X * 0.0031 + seed * 2.1, 0.7, seed, 5) - 0.6
        return max(12.0, base + amp * ((1 - jag) * soft * 1.3 + jag * peaks * 1.9) + fbm(X * 0.02, seed, 1.0, 4) * amp * 0.07)
    return f


def painter(rock, rock2, forest=None, tree_line=0.6, snow=None, snow_line=0.55, sand=None, haze=0.25, low=0.6, low_height=0.45, strata=0.0):
    """standard colouring of a range"""
    r1, r2 = col(rock), col(rock2)
    fo = (col(forest[0]), col(forest[1])) if forest else None
    sn = (col(snow[0]), col(snow[1])) if snow else None

    def f(x, z, hmax, slope, g):
        h = z / hmax
        n = fbm(x * 0.021, z * 0.035, 4.2, 4)
        big = fbm(x * 0.0045, z * 0.012, 8.8, 3)
        c = lerp(r1, r2, clamp(0.5 + n * 0.8 + g * 0.6))
        if strata:
            band = noise.noise((0.0, (z + fbm(x * 0.004, 0, 1.0, 3) * 26) * 0.11, 3.0))
            c = lerp(c, r1 if band > 0 else r2, clamp(abs(band) * 2.2) * strata)
        if fo:
            woods = sstep(tree_line + 0.08, tree_line - 0.08, h + big * 0.28 - g * 0.12)
            tree = noise.noise((x * 0.23, z * 0.31, 2.0))
            c = lerp(c, lerp(fo[0], fo[1], clamp(0.5 + tree * 1.4)), woods * sstep(-0.45, -0.05, n + 0.2))
        if sn:
            s = sstep(snow_line - 0.04, snow_line + 0.07, h + n * 0.16 - g * 0.38 + big * 0.12)
            c = lerp(c, lerp(sn[1], sn[0], clamp(0.55 + g * 1.2 + n * 0.4)), s)
        mist = clamp(haze + low * sstep(low_height, 0.0, h + big * 0.1))
        return c, mist
    return f


# ---------------------------------------------------------------- instanced things

class Kit:
    """prototype meshes (trees, houses) copied many times"""

    def __init__(self, haze_colour, night=False):
        self.haze = haze_colour
        self.night = night
        self.cache = {}

    def material(self, colour, mist, lit=True):
        key = (colour, round(mist, 2), lit)
        if key not in self.cache:
            m = bpy.data.materials.new("k")
            m.use_nodes = True
            nt = m.node_tree
            nt.nodes.clear()
            out = nt.nodes.new("ShaderNodeOutputMaterial")
            if lit:
                bs = nt.nodes.new("ShaderNodeBsdfDiffuse")
                bs.inputs["Color"].default_value = srgb(colour)
            else:
                bs = nt.nodes.new("ShaderNodeEmission")
                bs.inputs["Color"].default_value = srgb(colour)
                bs.inputs["Strength"].default_value = 1.0
            fog = nt.nodes.new("ShaderNodeEmission")
            fog.inputs["Color"].default_value = srgb(self.haze)
            mix = nt.nodes.new("ShaderNodeMixShader")
            mix.inputs[0].default_value = mist
            nt.links.new(bs.outputs[0], mix.inputs[1])
            nt.links.new(fog.outputs[0], mix.inputs[2])
            nt.links.new(mix.outputs[0], out.inputs["Surface"])
            self.cache[key] = m
        return self.cache[key]

    def mesh(self, key, verts, faces, mats, face_mat=None):
        me = bpy.data.meshes.new(key)
        me.from_pydata(verts, [], faces)
        for m in mats:
            me.materials.append(m)
        if face_mat:
            for p, i in zip(me.polygons, face_mat):
                p.material_index = i
        return me

    def place(self, me, x, z, depth, scale=1.0, sx=None, rot=0.0):
        o = bpy.data.objects.new("i", me)
        o.location = (x * U, depth, z * U)
        o.scale = (sx if sx is not None else scale, scale, scale)
        o.rotation_euler = (0, 0, rot)
        link(o)
        return o

    # conifer: stacked ragged cones, height 1 unit-metre
    def conifer(self, variant, colour, mist, snow=None):
        key = ("conifer", variant, colour, mist, snow)
        if key not in self.cache:
            rng = hexrand(100 + variant)
            verts, faces, fm = [], [], []
            tiers = 6
            for t in range(tiers):
                z0 = 0.08 + t * 0.135
                r = 0.27 * (1 - t / (tiers + 0.6)) + 0.02
                seg = 11
                base = len(verts)
                for i in range(seg):
                    a = 2 * math.pi * i / seg + t * 0.7
                    rr = r * rng.uniform(0.7, 1.2) * (1.0 if i % 2 == 0 else 0.68)
                    verts.append((math.cos(a) * rr, math.sin(a) * rr, z0 + rng.uniform(-0.02, 0.02)))
                verts.append((rng.uniform(-0.012, 0.012), 0.0, min(1.0, z0 + 0.25)))
                for i in range(seg):
                    faces.append((base + i, base + (i + 1) % seg, base + seg))
                    fm.append(1 if (snow and (i % 2 == 0) and t > 0) else 0)
            mats = [self.material(colour, mist)]
            if snow:
                mats.append(self.material(snow, mist))
            self.cache[key] = self.mesh("conifer", verts, faces, mats, fm)
        return self.cache[key]

    def broadleaf(self, variant, colour, mist):
        key = ("broad", variant, colour, mist)
        if key not in self.cache:
            rng = hexrand(300 + variant)
            bm = bmesh.new()
            for _ in range(9):
                m = Matrix.Translation((rng.uniform(-0.2, 0.2), rng.uniform(-0.1, 0.1), rng.uniform(0.35, 0.78)))
                bmesh.ops.create_icosphere(bm, subdivisions=2, radius=rng.uniform(0.13, 0.22), matrix=m)
            for v in bm.verts:
                n = noise.noise((v.co.x * 9, v.co.y * 9, v.co.z * 9 + variant))
                v.co += v.co.normalized() * n * 0.05
            me = bpy.data.meshes.new("broad")
            bm.to_mesh(me)
            bm.free()
            me.materials.append(self.material(colour, mist))
            self.cache[key] = me
        return self.cache[key]

    def house(self, wall, roof, mist, w, h, windows, lit_share=0.12, flat=False, seed=0):
        """a house of width w and wall height h (units) with a pitched or flat roof and rows of windows"""
        key = ("house", wall, roof, mist, w, h, windows, flat, seed)
        if key not in self.cache:
            rng = hexrand(seed + w * 7 + h)
            a, b, d = w * U / 2, h * U, 0.6
            rh = 0.12 * b if flat else min(a * 0.9, 20 * U)
            verts, faces, fm = [], [], []

            def quad(p, i):
                base = len(verts)
                verts.extend(p)
                faces.append(tuple(range(base, base + len(p))))
                fm.append(i)

            quad([(-a, -d, 0), (a, -d, 0), (a, -d, b), (-a, -d, b)], 0)
            quad([(a, -d, 0), (a, d, 0), (a, d, b), (a, -d, b)], 0)
            quad([(-a, d, 0), (-a, -d, 0), (-a, -d, b), (-a, d, b)], 0)
            if flat:
                quad([(-a * 1.06, -d * 1.2, b), (a * 1.06, -d * 1.2, b), (a * 1.06, -d * 1.2, b + rh), (-a * 1.06, -d * 1.2, b + rh)], 1)
                quad([(-a * 1.06, -d * 1.2, b + rh), (a * 1.06, -d * 1.2, b + rh), (a * 1.06, d, b + rh), (-a * 1.06, d, b + rh)], 1)
            else:
                o = a * 1.12
                quad([(-o, -d * 1.25, b), (o, -d * 1.25, b), (a * 0.75, 0, b + rh), (-a * 0.75, 0, b + rh)], 1)
                quad([(a * 0.75, 0, b + rh), (o, -d * 1.25, b), (o, d, b)], 1)
                quad([(-o, -d * 1.25, b), (-a * 0.75, 0, b + rh), (-o, d, b)], 1)
            if windows:
                cols_ = max(1, int(w / 9))
                rows_ = max(1, int(h / 11))
                ww, wh = min(4.2, w / cols_ * 0.45) * U, 5.2 * U
                for c in range(cols_):
                    for r in range(rows_):
                        x = -a + (c + 0.5) * 2 * a / cols_
                        z = (r + 0.5) * b / rows_
                        lit = rng.random() < (0.55 if self.night else lit_share * 0.2)
                        quad([(x - ww / 2, -d - 0.02, z - wh / 2), (x + ww / 2, -d - 0.02, z - wh / 2),
                              (x + ww / 2, -d - 0.02, z + wh / 2), (x - ww / 2, -d - 0.02, z + wh / 2)], 3 if (lit and self.night) else 2)
            mats = [self.material(wall, mist), self.material(roof, mist), self.material(0x3c4650, mist),
                    self.material(0xffd089, mist * 0.4, lit=False)]
            self.cache[key] = self.mesh("house", verts, faces, mats, fm)
        return self.cache[key]

    def box(self, colour, mist, x, z, w, h, depth, d=0.4, lit=True):
        """a beam or block, x centred, standing on z (units)"""
        a = w * U / 2
        v = [(-a, -d, 0), (a, -d, 0), (a, d, 0), (-a, d, 0), (-a, -d, h * U), (a, -d, h * U), (a, d, h * U), (-a, d, h * U)]
        f = [(0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7), (4, 5, 6, 7)]
        self.place(self.mesh("box", v, f, [self.material(colour, mist, lit)]), x, z, depth)

    def line(self, colour, mist, pts, radius, depth):
        tube("l", [(x * U, depth, z * U) for x, z in pts], radius * U, self.material(colour, mist), 2)


def woods(kit, W, ground, count, rng, colours, mist, size=(18, 36), depth=(2.0, 12.0), kind="conifer", snow=None,
          avoid=(), clump=True):
    """trees on the slope: ground(x, depth) -> height in units"""
    placed = 0
    tries = 0
    while placed < count and tries < count * 4:
        tries += 1
        x = rng.uniform(-20, W + 20)
        d = rng.uniform(*depth)
        if clump and noise.noise((x * 0.008, d * 0.2, 5.5)) < -0.12:
            continue
        if any(a <= x <= b for a, b in avoid):
            continue
        z = ground(x, d)
        s = rng.uniform(*size) * U
        c = colours[rng.randrange(len(colours))]
        if kind == "conifer" or (kind == "mixed" and rng.random() < 0.65):
            kit.place(kit.conifer(rng.randrange(4), c, mist, snow), x, z - 3, d, s, rot=rng.uniform(0, 6.3))
        else:
            kit.place(kit.broadleaf(rng.randrange(4), c, mist), x, z - 4, d, s * 0.9, rot=rng.uniform(0, 6.3))
        placed += 1


def meadow(kit_haze, W, base, amp, seed, c1, c2, c3, mist, depth=14.0, haze_low=0.35, lit=True, patch=0.006, fields=0.0):
    """a rolling hill; returns the ground function used to stand things on it"""
    def line(x):
        return base + amp * (fbm(x * 0.0028 + seed, seed, 0.2, 4, 0.9) * 1.1 + 0.35 * fbm(x * 0.012, seed, 4.0, 3))

    def ground(x, d):
        t = clamp(d / depth)
        return line(x) * (0.35 + 0.65 * t ** 0.7)

    mat_ = paint_material("hill%d" % seed, lit=lit, haze=kit_haze)
    a, b, f = col(c1), col(c2), col(c3)
    nx, rows = int((W + 60) / 4), 26
    verts, cols, hz, al = [], [], [], []
    for i in range(nx + 1):
        x = -30 + i * 4
        for k in range(rows + 2):
            t = max(0, k - 1) / rows
            d = depth * t
            z = ground(x, d) + fbm(x * 0.03, d * 0.7, seed, 3) * 4 if k else -60.0
            n = fbm(x * patch * 4, d * 0.4, seed + 2, 4)
            c = lerp(a, b, clamp(0.5 + n * 1.1))
            if fields:
                cell = noise.voronoi((x * 0.018 + fbm(x * 0.01, d, 0, 2) * 0.5, d * 0.55, seed))
                p = cell[1][0]
                r = noise.cell((p[0] * 5.0, p[1] * 3.0, p[2]))
                c = lerp(c, f if r > 0.15 else (b if r > -0.3 else a), fields)
            else:
                c = lerp(c, f, sstep(0.15, 0.4, fbm(x * patch, d * 0.2, seed + 7, 3)))
            verts.append((x * U, d, z * U))
            cols.append(c)
            hz.append(clamp(mist + haze_low * sstep(base * 0.9, 0.0, z)))
            al.append(1.0)
    point_mesh("hill", verts, grid_faces(nx, rows + 1), cols, hz, al, mat_)
    return ground


# ---------------------------------------------------------------- smoke, glow, water

def plume(name, x, z, height, width, lean, colour, dark, alpha, depth, seed, haze_colour, glow=None, step=3.0):
    """a rising column of smoke or ash that widens and drifts with the wind"""
    m = paint_material(name, lit=False, haze=haze_colour)
    c1, c2 = col(colour), col(dark)
    gl = col(glow) if glow else None

    def f(px, pz):
        t = clamp((pz - z) / height)
        cx = x + lean * t ** 1.5 + noise.noise((t * 3.0, seed, 0.0)) * width * 0.25
        r = width * (0.1 + 0.75 * t ** 0.7)
        wob = fbm(px * 0.017, pz * 0.017, seed, 4, 0.8)
        d = abs(px - cx) / r + wob * 0.8
        a = sstep(1.05, 0.35, d) * alpha * sstep(0.0, 0.05, t) * (1 - sstep(0.7, 1.0, t))
        shade = clamp(0.5 + fbm(px * 0.03, pz * 0.03, seed + 3, 3) * 1.3 + (cx - px) / r * 0.35)
        c = lerp(c2, c1, shade)
        if gl:
            c = lerp(c, gl, sstep(0.22, 0.0, t) * 0.9)
        return c, 0.0, a

    painted(name, x - width + min(0, lean), x + width + max(0, lean), z, z + height, depth, f, m, step)


def glow_spot(name, x, z, rx, rz, colour, alpha, depth):
    m = paint_material(name, lit=False)
    c = col(colour)

    def f(px, pz):
        d = math.hypot((px - x) / rx, (pz - z) / rz)
        return c, 0.0, alpha * sstep(1.0, 0.0, d) ** 1.6

    painted(name, x - rx, x + rx, z - rz, z + rz, depth, f, m, max(2.0, min(rx, rz) / 12))


def sea(name, W, horizon, depth, near, far, glint, haze_colour, seed, rough=1.0, haze_far=0.55):
    """open water up to a horizon: swell lines get finer with distance, glints and foam"""
    m = paint_material(name, lit=False, haze=haze_colour)
    a, b, g = col(near), col(far), col(glint)

    def f(x, z):
        t = clamp(z / horizon)                      # 0 near, 1 horizon
        k = 1.0 + t * t * 5.0
        warp = fbm(x * 0.006 * k, z * 0.03, seed, 3) * 2.0
        wave = noise.noise((x * 0.008 * k, (z + warp * 6) * 0.075 * k, seed))
        small = noise.noise((x * 0.04 * k, z * 0.22 * k, seed + 5))
        c = lerp(a, b, t ** 0.8)
        c = lerp(c, lerp(a, (0, 0, 0), 0.45), clamp(-wave * 1.6) * (1 - t * 0.6) * rough)
        crest = clamp((wave - 0.16) * 2.4) * clamp(0.4 + small * 2.0)
        c = lerp(c, g, crest * (1 - t * 0.4) * 0.75 * rough)
        foam = sstep(0.38, 0.55, wave + small * 0.35) * rough * (1 - t)
        c = lerp(c, col(0xdfe7ea), foam * 0.6)
        return c, haze_far * sstep(0.62, 1.0, t), sstep(horizon + 0.8, horizon - 0.8, z)

    painted(name, -30, W + 30, -60, horizon + 2, depth, f, m, 2.4)


# ---------------------------------------------------------------- the Einsätze
# Each function gets the layer width in units and the kit; heights are units above the bottom edge of the layer.

SKYHAZE = {"hochwasser": 0xc4cbcc, "waldbrand": 0xcfc0ac, "kueste": 0x34465e, "altstadt": 0xddc9ac, "vulkan": 0x85593f,
           "gebirge": 0xd3e0ea, "bohrinsel": 0x72808c, "staudamm": 0xd5b499, "pass": 0xd0d9e2, "wueste": 0xecd0a0}


def two_ranges(W, name, near_paint_args, far_paint_args, far_crest, near_crest, gully=(13.0, 11.0), seeds=(3, 7)):
    mist = SKYHAZE[name]
    mountain(W, 40, 12, far_crest, painter(**far_paint_args), paint_material("m1", haze=mist), seeds[0], gully=gully[0])
    mountain(W, 24, 10, near_crest, painter(**near_paint_args), paint_material("m2", haze=mist), seeds[1], gully=gully[1])


def far_hochwasser(W, kit):
    two_ranges(W, "hochwasser",
               dict(rock=0x5c6b70, rock2=0x76857f, forest=(0x3b544c, 0x56725c), tree_line=0.85, haze=0.28, low=0.6),
               dict(rock=0x6d7d90, rock2=0x93a2ae, snow=(0xf1f4f6, 0xb9c7d6), snow_line=0.72, haze=0.46, low=0.5),
               skyline(3.1, 150, 105, 0.55), skyline(7.7, 100, 50, 0.2))


def far_waldbrand(W, kit):
    two_ranges(W, "waldbrand",
               dict(rock=0x6a6258, rock2=0x8a8070, forest=(0x3a4a3e, 0x59694c), tree_line=0.9, haze=0.3, low=0.55),
               dict(rock=0x7b7884, rock2=0xa29a9c, haze=0.48, low=0.45),
               skyline(11.3, 165, 100, 0.45), skyline(5.2, 110, 55, 0.2))
    haze = SKYHAZE["waldbrand"]
    for i, fx in enumerate((0.2, 0.55, 0.83)):
        x = W * fx
        plume("smoke%d" % i, x, 90, 340, 130, 210, 0xb9ada2, 0x4e443f, 0.92 - i * 0.12, 15, 2.2 + i * 5, haze, glow=0xff8a2a)
        glow_spot("fire%d" % i, x, 100, 110, 38, 0xff7a1e, 0.75, 13)


def far_kueste(W, kit):
    haze = SKYHAZE["kueste"]
    sea("sea", W, 185, 46, 0x0b1626, 0x243752, 0x8fa8c8, haze, 3.3, rough=0.7)

    def headland(centre, width, height, seed):
        def f(x):
            d = abs(x - centre) / width
            return max(2.0, height * sstep(1.0, 0.15, d + fbm(x * 0.008, seed, 0, 4) * 0.35) + fbm(x * 0.03, seed, 2, 3) * 7 - 4)
        return f

    for i, (cx, wd, ht) in enumerate(((0.14, 420, 220), (0.52, 260, 120), (0.9, 480, 250))):
        mountain(W, 30 - i, 7, headland(W * cx, wd, ht, i * 4.1), painter(rock=0x131d2b, rock2=0x2b3b50, haze=0.12, low=0.35, strata=0.3),
                 paint_material("c%d" % i, haze=haze), 2 + i * 3, gully=9.0, rows=34)
        for k in range(7):
            x = W * cx + (k - 3) * 17 + 40
            kit.box(0xffcf8a, 0.15, x, 18 + (k * 37) % 23, 3, 4, 18, 0.05, lit=False)
    x = W * 0.14 + 40
    kit.box(0x9aa8ba, 0.15, x, 205, 13, 58, 17)
    kit.box(0xffe7b0, 0.0, x, 262, 16, 12, 17, lit=False)
    glow_spot("lh", x, 268, 70, 46, 0xffe2a8, 0.8, 15)
    m = paint_material("beam", lit=False)

    def beam(px, pz):
        d = px - x
        half = 4 + abs(d) * 0.055
        a = sstep(half, 0.0, abs(pz - 268 - d * 0.03)) * sstep(560, 0, abs(d)) * 0.42
        return col(0xffe9bd), 0.0, a

    painted("beam", x - 560, x + 560, 215, 330, 14.5, beam, m, 4.0)


def far_altstadt(W, kit):
    haze = SKYHAZE["altstadt"]
    two_ranges(W, "altstadt",
               dict(rock=0x8f7766, rock2=0xb49a80, forest=(0x7a7458, 0x94896a), tree_line=0.55, haze=0.4, low=0.5),
               dict(rock=0x9d8a8e, rock2=0xbda7a0, haze=0.55, low=0.4),
               skyline(2.4, 200, 62, 0.3), skyline(9.1, 135, 48, 0.2), gully=(11.0, 8.0))
    rng = hexrand(51)
    walls = (0xd8c0a0, 0xc9a88c, 0xe2d3b8, 0xb99a84, 0xcdb79c)
    for row, (mist, depth, zbase, hh) in enumerate(((0.58, 13, 92, (16, 36)), (0.38, 10, 58, (18, 42)))):
        x = -20.0
        while x < W + 20:
            w = rng.randrange(18, 40, 3)
            h = rng.randrange(hh[0], hh[1], 4)
            z = zbase + fbm(x * 0.004, row * 3.0, 0, 3) * 28
            kit.box(0x9c8470, mist, x, 0, w + 6, z, depth + 0.4)
            kit.place(kit.house(rng.choice(walls), rng.choice((0xa8553a, 0x8d4a38, 0xb56a48)), mist, w, h, True,
                                flat=rng.random() < 0.2, seed=rng.randrange(4)), x, z, depth)
            x += w * rng.uniform(0.7, 1.05)
    for i, fx in enumerate((0.17, 0.46, 0.71, 0.9)):
        x = W * fx
        mist = 0.45
        if i % 2 == 0:      # campanile
            kit.box(0xc7ad90, mist, x, 60, 18, 128, 11.5)
            for k in range(3):
                kit.box(0x5c4a40, mist, x - 5 + k * 5, 168, 3, 12, 11.0)
            kit.place(kit.house(0xc7ad90, 0x8d4a38, mist, 22, 4, False), x, 188, 11.5)
        else:               # dome
            kit.box(0xcbb598, mist, x, 60, 56, 72, 11.5)
            bm = bmesh.new()
            bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=12, radius=27 * U)
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -0.01], context="VERTS")
            me = bpy.data.meshes.new("dome")
            bm.to_mesh(me)
            bm.free()
            me.materials.append(kit.material(0x7f9a8c, mist))
            kit.place(me, x, 132, 11.5)
            kit.box(0x7f6a55, mist, x, 156, 4, 20, 11.4)
    for i, fx in enumerate((0.3, 0.62)):
        plume("dust%d" % i, W * fx, 60, 190, 110, 90, 0xd8c3a2, 0x9c8266, 0.6, 7, 3.0 + i, haze)


def far_vulkan(W, kit):
    haze = SKYHAZE["vulkan"]
    peak = W * 0.4

    def cone(x):
        d = abs(x - peak) / 760.0
        body = 300 * max(0.0, 1 - d) ** 1.55
        crater = 30 * sstep(0.085, 0.0, d)
        return max(70.0, body + 50 - crater) + fbm(x * 0.016, 3, 0, 4) * 8

    plume("ash", peak, 292, 200, 240, 420, 0x8a6e62, 0x201a1b, 0.97, 44, 4.4, haze, glow=0xff7a26)

    def cone_paint(x, z, hmax, slope, g):
        h = z / hmax
        c = lerp(col(0x231c1d), col(0x514140), clamp(0.5 + fbm(x * 0.02, z * 0.03, 1, 4) + g))
        flow = 1 - abs(noise.noise(((x - peak) / (60 + (hmax - z) * 0.55) * 4.2 + fbm(x * 0.02, z * 0.015, 2, 3) * 0.8, 0.0, 6.0)))
        lava = sstep(0.88, 0.98, flow) * sstep(0.3, 0.75, h) * sstep(300, 40, abs(x - peak))
        c = lerp(c, col(0xff6a14), lava)
        return c, clamp(0.16 + 0.62 * sstep(0.5, 0.05, h)) * (1 - lava * 0.8)

    mountain(W, 40, 12, cone, cone_paint, paint_material("v", haze=haze), 4, gully=15.0, rows=70, step=2.2)
    glow_spot("crater", peak, 364, 130, 62, 0xff7a20, 0.85, 26)
    mountain(W, 20, 8, skyline(6.6, 100, 58, 0.55), painter(rock=0x1d1718, rock2=0x3a2f2d, haze=0.18, low=0.55),
             paint_material("v2", haze=haze), 9, gully=10.0)


def far_gebirge(W, kit):
    two_ranges(W, "gebirge",
               dict(rock=0x3a4556, rock2=0x677286, snow=(0xeef3fa, 0x8ea3c2), snow_line=0.66, haze=0.12, low=0.45, low_height=0.4),
               dict(rock=0x6f7f98, rock2=0x95a5ba, snow=(0xeef3fa, 0xb4c5da), snow_line=0.54, haze=0.44, low=0.45),
               skyline(8.8, 270, 140, 0.85, 1.15), skyline(1.9, 165, 110, 0.8, 1.5), gully=(21.0, 18.0))


def far_bohrinsel(W, kit):
    haze = SKYHAZE["bohrinsel"]
    sea("sea", W, 190, 40, 0x1d2c36, 0x54666f, 0xaebfc6, haze, 8.1, rough=1.25, haze_far=0.8)
    for i, (fx, s, mist) in enumerate(((0.16, 1.0, 0.34), (0.47, 0.55, 0.62), (0.78, 0.8, 0.46))):
        x, base = W * fx, 108 + (1 - s) * 70
        steel, red = 0x232c33, 0x7a3a2e
        for dx in (-40, -14, 14, 40):
            kit.box(steel, mist, x + dx * s, base - 8 * s, 6 * s, 50 * s, 20 + i)
        for a in (-40, -14, 14):
            kit.line(steel, mist, [(x + a * s, base), (x + (a + 26) * s, base + 38 * s)], 1.2 * s, 19.8 + i)
        kit.box(steel, mist, x, base + 40 * s, 108 * s, 12 * s, 20 + i)
        for dx, w, h in ((-30, 34, 22), (14, 24, 32), (40, 20, 14)):
            kit.box(0x3a464e, mist, x + dx * s, base + 52 * s, w * s, h * s, 20 + i)
            for k in range(int(w / 8)):
                kit.box(0xffd08a, mist * 0.5, x + (dx - w / 2 + 5 + k * 8) * s, base + (60) * s, 2.6 * s, 2.6 * s, 19 + i, 0.05, lit=False)
        top = base + 160 * s
        for sg in (-1, 1):
            kit.line(red, mist, [(x - 22 * s + sg * 16 * s, base + 52 * s), (x - 22 * s + sg * 3 * s, top)], 1.5 * s, 19.6 + i)
        for k in range(6):
            za = base + 52 * s + (top - base - 52 * s) * k / 6
            zb = base + 52 * s + (top - base - 52 * s) * (k + 1) / 6
            wa, wb = (16 - 13 * k / 6) * s, (16 - 13 * (k + 1) / 6) * s
            kit.line(red, mist, [(x - 22 * s - wa, za), (x - 22 * s + wb, zb)], 0.8 * s, 19.5 + i)
        boom = (x + 54 * s, base + 52 * s), (x + 128 * s, base + 118 * s)
        kit.line(steel, mist, list(boom), 2.0 * s, 19.6 + i)
        fx_, fz = boom[1]
        glow_spot("flare%d" % i, fx_, fz + 8 * s, 46 * s, 34 * s, 0xff8a28, 0.85, 18)
        glow_spot("flame%d" % i, fx_ + 5 * s, fz + 9 * s, 14 * s, 17 * s, 0xffd27a, 1.0, 17.5)
        plume("flaresmoke%d" % i, fx_ + 6 * s, fz + 12 * s, 150 * s, 70 * s, 130 * s, 0x56616a, 0x252c32, 0.75, 18.5, 1.0 + i, haze)
    # a supply ship on the horizon
    x = W * 0.63
    kit.box(0x2a343c, 0.55, x, 160, 74, 10, 30)
    kit.box(0x44525c, 0.55, x - 22, 170, 18, 16, 30)


def far_staudamm(W, kit):
    haze = SKYHAZE["staudamm"]

    def mesas(seed, base, high, width):
        def f(x):
            n = noise.noise((x / width + seed, seed, 0.0)) + noise.noise((x / width * 2.7, seed + 3, 0.0)) * 0.35
            top = base + high * sstep(-0.06, 0.1, n) + high * 0.35 * sstep(0.34, 0.44, n)
            return top + fbm(x * 0.03, seed, 1, 4) * 7 + fbm(x * 0.008, seed, 5, 3) * 14
        return f

    mountain(W, 40, 10, mesas(2.0, 140, 120, 330), painter(rock=0x9a6458, rock2=0xc08a70, strata=0.7, haze=0.46, low=0.45),
             paint_material("s1", haze=haze), 3, gully=10.0)
    mountain(W, 24, 9, mesas(7.4, 70, 105, 260), painter(rock=0x6e3d2c, rock2=0xb06c47, strata=0.75, forest=(0x4a5236, 0x6a6c42),
             tree_line=0.34, haze=0.14, low=0.5), paint_material("s2", haze=haze), 6, gully=12.0)
    # the broken dam between two walls of the canyon
    x = W * 0.34
    for k in range(-9, 10):
        broken = -1 <= k <= 2
        h = 70 + abs(k) * 0.6 - (46 - abs(k - 0.5) * 12 if broken else 0)
        kit.box(0xb9ac9a if k % 2 == 0 else 0xaea08e, 0.2, x + k * 19, 40, 19.6, h, 12.0 + 0.012 * k * k)
        if not broken:
            kit.box(0x8a7c6c, 0.2, x + k * 19, 40 + h, 21, 5, 11.8 + 0.012 * k * k)
            kit.box(0x6d6054, 0.2, x + k * 19, 40, 4, h - 6, 11.4 + 0.012 * k * k)
    plume("spray", x + 14, 14, 105, 70, 40, 0xf1ece4, 0xb4a89c, 0.9, 10.0, 9.0, haze)
    m = paint_material("fall", lit=False, haze=haze)

    def fall(px, pz):
        w = 22 + (110 - pz) * 0.28
        d = abs(px - x - 12 + fbm(pz * 0.03, 1, 0, 3) * 6) / w
        streak = noise.noise((px * 0.18, pz * 0.025, 3.0))
        return lerp(col(0x8fa8a4), col(0xf4f2ea), clamp(0.5 + streak * 1.6)), 0.08, sstep(1.0, 0.6, d) * sstep(92, 80, pz)

    painted("fall", x - 50, x + 74, 6, 94, 11.0, fall, m, 2.0)


def far_pass(W, kit):
    two_ranges(W, "pass",
               dict(rock=0x4e5867, rock2=0x737e8c, snow=(0xeef3f9, 0xa5b6cc), snow_line=0.36, haze=0.3, low=0.62, low_height=0.55),
               dict(rock=0x77869a, rock2=0x95a3b6, snow=(0xe6edf5, 0xc0cddc), snow_line=0.35, haze=0.66, low=0.3),
               skyline(13.7, 255, 130, 0.78), skyline(4.5, 165, 105, 0.82, 1.4), gully=(20.0, 17.0))


def dunes(seed, base, high, width):
    def f(x):
        u = x / width + noise.noise((x / width * 0.7, seed, 0.0)) * 0.6 + seed
        t = u - math.floor(u)
        shape = (t / 0.7) ** 1.6 if t < 0.7 else (1 - (t - 0.7) / 0.3) ** 1.2
        amp = 0.55 + 0.45 * noise.noise((math.floor(u) * 3.1, seed, 1.0)) * 2
        return base + high * shape * amp + fbm(x * 0.006, seed, 2, 3) * 12
    return f


def far_wueste(W, kit):
    haze = SKYHAZE["wueste"]

    def mesa(x):
        n = noise.noise((x / 280.0, 4.0, 0.0))
        return 100 + 105 * sstep(0.08, 0.2, n) + 40 * sstep(0.36, 0.42, n) + fbm(x * 0.025, 1, 1, 4) * 8

    mountain(W, 44, 8, mesa, painter(rock=0xa8705a, rock2=0xc8906c, strata=0.6, haze=0.5, low=0.4),
             paint_material("d0", haze=haze), 2, gully=8.0)
    for i, (depth, base, high, width, mist, c1, c2) in enumerate(((30, 90, 62, 520, 0.3, 0xc78a54, 0xe2ab6e),
                                                                 (20, 44, 70, 640, 0.12, 0xc27c42, 0xe9b46c))):
        mountain(W, depth, 8, dunes(2.3 + i * 4, base, high, width), painter(rock=c1, rock2=c2, haze=mist, low=0.35),
                 paint_material("d%d" % (i + 1), haze=haze), 3 + i, gully=2.4, step=3.0)


def hill_hochwasser(W, kit):
    haze = SKYHAZE["hochwasser"]
    rng = hexrand(4)
    back = meadow(haze, W, 150, 52, 5, 0x4f6a48, 0x6d8454, 0x7d8a58, 0.28, fields=0.4)
    woods(kit, W, back, int(W * 0.22), rng, (0x2f4a3c, 0x3d5a44, 0x4a6648), 0.3, (16, 30), (4.0, 14.0), "mixed")
    # farms, a church and the flooded plain in front
    for i, fx in enumerate((0.12, 0.4, 0.66, 0.9)):
        x = W * fx
        for k in range(5):
            hx = x + k * 30 + rng.uniform(-8, 8) - 60
            kit.place(kit.house(rng.choice((0xe2d6c0, 0xc9a48a, 0xdcd8cc)), rng.choice((0x9a4e38, 0x5a544e)), 0.18,
                                rng.randrange(20, 34, 4), rng.randrange(14, 22, 4), True, seed=k), hx, back(hx, 3.4) - 6, 3.2)
        if i % 2 == 1:
            kit.box(0xded6c6, 0.18, x + 20, back(x + 20, 3.6) - 6, 14, 52, 3.4)
            kit.place(kit.house(0xded6c6, 0x4e5a60, 0.18, 15, 2, False), x + 20, back(x + 20, 3.6) + 46, 3.4, 1.0)
            kit.place(kit.conifer(0, 0x4e5a60, 0.18), x + 20, back(x + 20, 3.6) + 54, 3.4, 24 * U, sx=15 * U)
    sea("flood", W, 76, 2.0, 0x4a5c56, 0x93a6a6, 0xd7e2e2, haze, 2.0, rough=0.45, haze_far=0.15)
    woods(kit, W, lambda x, d: 24 + fbm(x * 0.01, 3, 0, 3) * 26, int(W * 0.03), rng, (0x35503e, 0x4a6040), 0.12, (20, 34), (0.5, 1.6), "mixed")


def hill_waldbrand(W, kit):
    haze = SKYHAZE["waldbrand"]
    rng = hexrand(14)
    back = meadow(haze, W, 190, 52, 15, 0x57603e, 0x6e6a44, 0x4a4234, 0.34)
    woods(kit, W, back, int(W * 0.34), rng, (0x2c4234, 0x3a5039, 0x4d5638), 0.34, (18, 34), (3.0, 14.0))
    burnt = [(W * 0.24, W * 0.31), (W * 0.62, W * 0.68)]
    front = meadow(haze, W, 104, 38, 23, 0x4d5a36, 0x66683c, 0x6e5c38, 0.14, depth=1.8)
    woods(kit, W, front, int(W * 0.2), rng, (0x24382a, 0x31462f, 0x45502f), 0.14, (24, 46), (0.2, 1.7), "mixed", avoid=burnt)
    for i, (a, b) in enumerate(burnt):
        for k in range(34):
            x = rng.uniform(a, b)
            z = front(x, 0.8) - 4
            h = rng.uniform(16, 38)
            kit.box(0x1d1714, 0.1, x, z, 2.4, h, 0.8)
            kit.line(0x1d1714, 0.1, [(x, z + h * 0.6), (x + rng.uniform(-9, 9), z + h * 0.85)], 0.7, 0.8)
        glow_spot("burn%d" % i, (a + b) / 2, front((a + b) / 2, 0.5), (b - a) * 0.62, 44, 0xff6a14, 0.7, -0.2)
        for k in range(16):
            x = rng.uniform(a, b)
            glow_spot("flame%d-%d" % (i, k), x, front(x, 0.4) + 3, 7, rng.uniform(10, 22), 0xffb040, 1.0, -0.4)
        plume("hsmoke%d" % i, (a + b) / 2, front((a + b) / 2, 1.0), 270, 90, 150, 0xa89c92, 0x3c3431, 0.85, 2.4, 6.0 + i, haze, glow=0xff8a2a)


def hill_kueste(W, kit):
    haze = SKYHAZE["kueste"]
    rng = hexrand(24)

    def shore(x):
        n = noise.noise((x / 330.0, 2.0, 0.0))
        return 18 + 112 * sstep(-0.12, 0.3, n) + fbm(x * 0.012, 4, 0, 4) * 18

    mountain(W, 8, 6, shore, painter(rock=0x0f1a26, rock2=0x26374a, forest=(0x122528, 0x1d3434), tree_line=1.2, haze=0.12, low=0.4, low_height=0.35),
             paint_material("k", haze=haze), 5, gully=7.0, rows=30)
    for i, fx in enumerate((0.08, 0.31, 0.55, 0.77, 0.94)):
        x0 = W * fx
        for k in range(6):
            x = x0 + k * 26 - 60 + rng.uniform(-6, 6)
            z = max(14.0, shore(x) * 0.55)
            kit.place(kit.house(0x34455a, 0x172230, 0.1, rng.randrange(18, 30, 4), rng.randrange(14, 22, 4), True, seed=k + i), x, z, 1.4)
            if k % 3 == 0:
                glow_spot("lamp%d-%d" % (i, k), x + 12, z + 6, 16, 14, 0xffc074, 0.6, 0.2)
    sea("surf", W, 34, 0.6, 0x0c1724, 0x1d2e44, 0x9fb6d0, haze, 12.0, rough=0.8, haze_far=0.1)


def hill_altstadt(W, kit):
    haze = SKYHAZE["altstadt"]
    rng = hexrand(34)
    walls = (0xd8bd98, 0xc89c80, 0xe0cfae, 0xb98f7a, 0xcab090, 0xd9c4b0)
    roofs = (0xa44e34, 0x8a402e, 0xb06442, 0x7a4a3c)
    ground = meadow(haze, W, 96, 34, 41, 0x8d7660, 0xa08a70, 0x7e7452, 0.3, depth=6.0)
    for row, (depth, mist, zoff, hh) in enumerate(((5.0, 0.36, 0, (20, 40)), (2.6, 0.22, -34, (24, 48)), (0.6, 0.12, -66, (24, 52)))):
        x = -30.0
        while x < W + 30:
            w = rng.randrange(24, 52, 4)
            h = rng.randrange(hh[0], hh[1], 4)
            z = max(2.0, ground(x, depth) + zoff)
            ruined = rng.random() < 0.09
            if ruined:
                for k in range(int(w / 6)):
                    kit.box(rng.choice(walls), mist, x - w / 2 + k * 6 + 3, 0, 6.4, z + rng.uniform(4, h * 0.8), depth)
            else:
                kit.box(0x8a735f, mist, x, 0, w, z, depth)
                kit.place(kit.house(rng.choice(walls), rng.choice(roofs), mist, w, h, True, flat=rng.random() < 0.15,
                                    seed=rng.randrange(5)), x, z, depth)
                if rng.random() < 0.3:
                    kit.box(0x8a5e4a, mist, x + w * 0.22, z + h, 4, 12, depth)
            if rng.random() < 0.12:
                kit.place(kit.broadleaf(rng.randrange(4), 0x5e6a44, mist), x + w * 0.6, z - 4, depth - 0.9, rng.uniform(18, 28) * U)
            x += w * rng.uniform(0.82, 1.1)
    for i, fx in enumerate((0.1, 0.43, 0.79)):
        x = W * fx
        z = ground(x, 3.0)
        kit.box(0xd2bc9c, 0.2, x, 0, 24, z + 108, 3.2)
        kit.box(0x6a564a, 0.2, x - 5, z + 78, 4, 14, 2.7)
        kit.box(0x6a564a, 0.2, x + 5, z + 78, 4, 14, 2.7)
        kit.place(kit.house(0xd2bc9c, 0x8a402e, 0.2, 30, 3, False), x, z + 108, 3.2)


def hill_vulkan(W, kit):
    haze = SKYHAZE["vulkan"]
    rng = hexrand(44)

    def ridge_(x):
        return 112 + fbm(x * 0.0035, 6, 0, 5) * 80 + ridged(x * 0.012, 2, 0, 3) * 18

    def paint(x, z, hmax, slope, g):
        c = lerp(col(0x151011), col(0x3c2e2b), clamp(0.4 + fbm(x * 0.025, z * 0.04, 3, 4) + g))
        flow = 1 - abs(noise.noise((x * 0.006 + fbm(x * 0.01, z * 0.02, 1, 3) * 0.7, z * 0.004, 2.0)))
        lava = sstep(0.955, 0.995, flow) * sstep(0.85, 0.5, z / hmax)
        return lerp(c, col(0xff5e12), lava), clamp(0.08 + 0.3 * sstep(0.5, 0.0, z / hmax)) * (1 - lava)

    mountain(W, 9, 6, ridge_, paint, paint_material("hv", haze=haze), 8, gully=11.0, rows=44, step=2.4)
    for k in range(int(W * 0.012)):
        x = rng.uniform(0, W)
        z = ridge_(x) * rng.uniform(0.3, 0.75)
        d = 2.6
        h = rng.uniform(14, 34)
        kit.box(0x120d0c, 0.05, x, z, 2.2, h, d)
        kit.line(0x120d0c, 0.05, [(x, z + h * 0.55), (x + rng.uniform(-10, 10), z + h * 0.8)], 0.7, d)
    for i, fx in enumerate((0.2, 0.55, 0.86)):
        x = W * fx
        glow_spot("vg%d" % i, x, 36, 150, 56, 0xff5a10, 0.55, 1.0)
        plume("vs%d" % i, x, 60, 190, 55, 100, 0x8a7064, 0x2a2121, 0.7, 1.5, 3.0 + i, haze, glow=0xff7a2a)


def hill_gebirge(W, kit, snow_trees=0xe8eff6, name="gebirge", chalets=True):
    haze = SKYHAZE[name]
    rng = hexrand(54)
    back = meadow(haze, W, 158, 74, 61, 0xcfdbe8, 0xf0f5fa, 0x93a6bc, 0.28)
    woods(kit, W, back, int(W * 0.16), rng, (0x35495a, 0x435868), 0.32, (16, 30), (4.0, 14.0), snow=snow_trees)
    front = meadow(haze, W, 78, 36, 73, 0xdbe5ef, 0xf7fafd, 0xaebed0, 0.12, depth=1.8)
    woods(kit, W, front, int(W * 0.09), rng, (0x243a45, 0x30495a), 0.12, (26, 52), (0.2, 1.7), snow=snow_trees)
    if chalets:
        for i, fx in enumerate((0.18, 0.5, 0.82)):
            for k in range(3):
                x = W * fx + k * 40 - 40
                z = front(x, 1.0) - 6
                kit.place(kit.house(0x6a4a36, 0xeef3f8, 0.1, 30, 18, True, lit_share=0.5, seed=k), x, z, 0.15)


def hill_pass(W, kit):
    haze = SKYHAZE["pass"]
    hill_gebirge(W, kit, name="pass", chalets=False)
    rng = hexrand(64)
    for x in range(40, int(W), 120):           # snow poles along the old road
        kit.box(0x2b2f36, 0.2, x, 40 + rng.uniform(-4, 4), 2.4, 34, -0.5)
        kit.box(0xe0552e, 0.15, x, 66, 3.2, 8, -0.6)


def hill_bohrinsel(W, kit):
    sea("sea", W, 105, 2.0, 0x16242c, 0x3a4d57, 0xc2d2d8, SKYHAZE["bohrinsel"], 31.0, rough=1.45, haze_far=0.5)
    for i, fx in enumerate((0.3, 0.72)):          # buoys
        x = W * fx
        kit.box(0xb4452d, 0.2, x, 62 + i * 9, 11, 16, 1.0)
        kit.line(0x2b2f33, 0.2, [(x, 76 + i * 9), (x, 96 + i * 9)], 1.0, 1.0)
        glow_spot("buoy%d" % i, x, 98 + i * 9, 11, 9, 0xffb050, 0.9, 0.6)


def hill_staudamm(W, kit):
    haze = SKYHAZE["staudamm"]
    rng = hexrand(74)

    def walls(x):
        n = noise.noise((x / 240.0, 9.0, 0.0))
        return 70 + 96 * sstep(-0.02, 0.16, n) + 36 * sstep(0.3, 0.38, n) + fbm(x * 0.025, 2, 1, 4) * 9

    mountain(W, 9, 5, walls, painter(rock=0x5c2f22, rock2=0xa86240, strata=0.8, haze=0.1, low=0.3),
             paint_material("hs", haze=haze), 12, gully=10.0, rows=44, step=2.4)
    woods(kit, W, lambda x, d: min(walls(x) * 0.42, 46 + fbm(x * 0.006, 1, 0, 3) * 30), int(W * 0.13), rng,
          (0x2e3c2a, 0x44502f, 0x56582f), 0.12, (18, 36), (0.4, 3.0), "mixed")
    sea("river", W, 34, 0.2, 0x3a352c, 0x8a7a60, 0xe8dcc4, haze, 41.0, rough=0.8, haze_far=0.0)


def hill_wueste(W, kit):
    haze = SKYHAZE["wueste"]
    rng = hexrand(84)
    mountain(W, 9, 7, dunes(9.1, 58, 62, 700), painter(rock=0xb06a34, rock2=0xdc9c54, haze=0.08, low=0.2),
             paint_material("hd", haze=haze), 14, gully=2.0, step=2.8)
    for i, fx in enumerate((0.15, 0.52, 0.84)):     # small oases with palms
        for k in range(7):
            x = W * fx + rng.uniform(-70, 70)
            z = 40 + rng.uniform(-10, 10)
            h = rng.uniform(40, 64)
            lean = rng.uniform(-10, 10)
            kit.line(0x6a4a2c, 0.1, [(x, z), (x + lean * 0.4, z + h * 0.55), (x + lean, z + h)], 1.8, 1.2)
            for a in (-165, -135, -105, -70, -40, -12):
                r = rng.uniform(18, 27)
                ex, ez = math.cos(math.radians(-a)) * r, math.sin(math.radians(-a)) * r
                kit.line(0x55662f, 0.1, [(x + lean, z + h), (x + lean + ex * 0.6, z + h + ez * 0.5), (x + lean + ex, z + h + ez * 0.15 - 6)], 1.5, 1.1)
        for k in range(14):
            x = W * fx + rng.uniform(-90, 90)
            kit.place(kit.broadleaf(rng.randrange(4), 0x6a6a38, 0.1), x, 28 + rng.uniform(-6, 8), 0.8, rng.uniform(12, 22) * U)


FAR = {"hochwasser": far_hochwasser, "waldbrand": far_waldbrand, "kueste": far_kueste, "altstadt": far_altstadt,
       "vulkan": far_vulkan, "gebirge": far_gebirge, "bohrinsel": far_bohrinsel, "staudamm": far_staudamm,
       "pass": far_pass, "wueste": far_wueste}
HILL = {"hochwasser": hill_hochwasser, "waldbrand": hill_waldbrand, "kueste": hill_kueste, "altstadt": hill_altstadt,
        "vulkan": hill_vulkan, "gebirge": hill_gebirge, "bohrinsel": hill_bohrinsel, "staudamm": hill_staudamm,
        "pass": hill_pass, "wueste": hill_wueste}
# sun: (energy, rotation), fill energy, sky light
LIGHT = {
    "hochwasser": (2.6, (58, 0, -62), 0.5, 0.85), "waldbrand": (3.0, (62, 0, -58), 0.4, 0.8),
    "kueste": (1.7, (52, 0, 55), 0.3, 0.7), "altstadt": (2.9, (60, 0, -58), 0.5, 0.85),
    "vulkan": (1.6, (60, 0, 50), 0.35, 0.7), "gebirge": (3.0, (60, 0, -62), 0.5, 0.85),
    "bohrinsel": (1.4, (45, 0, -40), 0.5, 0.9), "staudamm": (3.3, (68, 0, -64), 0.35, 0.75),
    "pass": (1.8, (52, 0, -50), 0.6, 0.95), "wueste": (3.2, (64, 0, -70), 0.4, 0.8),
}


# ---------------------------------------------------------------- render

def render_layer(name, mission, W_u, H_u, preview, build):
    reset()
    W_px, H_px = int(W_u * S), int(H_u * S)
    setup_render(W_px, H_px, samples=8 if preview else 32)
    bpy.context.scene.cycles.use_denoising = False
    bpy.context.scene.cycles.transparent_max_bounces = 24
    energy, rot, fill, sky = LIGHT.get(mission, LIGHT["hochwasser"])
    night = mission == "kueste"
    world(sky=(0.30, 0.40, 0.58) if night else (0.70, 0.80, 0.92), strength=sky * (0.7 if night else 1.0))
    cam = ortho_camera(width=W_u * U)
    sun("key", energy, rot, color=(0.72, 0.82, 1.0) if night else (1.0, 0.93, 0.82))
    sun("fill", fill, (75, 0, 110), color=(0.8, 0.88, 1.0))
    kit = Kit(SKYHAZE.get(mission, 0xc4cbcc), night)
    build(W_u, kit)
    target = Vector((W_u * U / 2, 10, H_u * U / 2 * math.cos(E)))
    cam.location = target + Vector((0, -80 * math.cos(E), 80 * math.sin(E)))
    aim(cam, target)
    bpy.context.view_layer.update()
    # push the picture so that z = 0 at depth 0 sits on the bottom edge
    low = project(cam, (W_u * U / 2, 0, 0))[1]
    cam.data.shift_y = (0.0 - low) * H_px / W_px * -1
    render(os.path.join(OUT, "panorama", name + ".png"))
    return {"w": W_u, "h": H_u}


def main():
    preview = "--preview" in argv()
    only = [a.split("=")[1] for a in argv() if a.startswith("--only=")]
    layers = [a.split("=")[1] for a in argv() if a.startswith("--layer=")]
    mf = os.path.join(OUT, "panorama", "panorama.json")
    meta = json.load(open(mf)) if os.path.exists(mf) else {}
    for fn in sorted(os.listdir(MISSIONS)):
        if not fn.endswith(".json"):
            continue
        mission = json.load(open(os.path.join(MISSIONS, fn)))
        mid = mission["id"]
        if only and mid not in only:
            continue
        W = mission["world"]["width"]
        if not layers or "far" in layers:
            meta[mid + "-far"] = render_layer("far-" + mid, mid, int(W * 0.12 + 1280), FAR_H, preview, FAR.get(mid, far_hochwasser))
        if not layers or "hill" in layers:
            meta[mid + "-hill"] = render_layer("hill-" + mid, mid, int(W * 0.35 + 1280), 400, preview, HILL.get(mid, hill_hochwasser))
        json.dump(meta, open(mf, "w"), indent=1)
        print("pano", mid)


if __name__ == "__main__":
    main()
