"""Distant mountain ridges and wooded hills as rendered parallax layers (Renders/panorama).
Layer widths follow the game: world width * parallax factor + 1280 units. 1.25 px per unit.

Usage: blender -b -P art/panorama.py [-- --preview] [--only=<mission>]
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
from mathutils import noise
from terrain import LOOKS, tree

U = 1 / 16.0
S = 1.25
E = math.radians(12)

PAL = {   # far ridges (back, front), mist, hills (dark, light), snow
    "valley": dict(far=(0x91a4b5, 0x7e93a5), mist=0xd3d7d3, hill=(0x4f6a58, 0x6a8a6f), trees=True, snow=False, jag=0.12, scale=0.62, mistk=0.8),
    "coast": dict(far=(0x56626e, 0x445059), mist=0x6c7882, hill=(0x38464c, 0x4c5d63), trees=False, snow=False, jag=0.3),
    "town": dict(far=(0xb8a392, 0x9f8b7c), mist=0xe0cdb2, hill=(0x84736a, 0x9d8b7b), trees=False, snow=False, jag=0.3),
    "volcano": dict(far=(0x56433d, 0x3d302d), mist=0x82604a, hill=(0x2c2522, 0x40342f), trees=False, snow=False, jag=0.7),
    "canyon": dict(far=(0xb98466, 0x9a674e), mist=0xd8b69a, hill=(0x87543c, 0xa76c4c), trees=False, snow=False, jag=0.85),
    "blizzard": dict(far=(0x9fb0c2, 0x8296ab), mist=0xd5dee7, hill=(0x5f7084, 0x7e8ea0), trees=False, snow=True, jag=0.9),
    "desert": dict(far=(0xd8ab72, 0xc28f58), mist=0xeccf9e, hill=(0xb4824c, 0xd2a266), trees=False, snow=False, jag=0.06, scale=0.55),
    "offshore": dict(far=(0x5a6874, 0x47545f), mist=0x6f7d89, hill=(0x3a4a54, 0x4b5c68), trees=False, snow=False, jag=0.05, scale=0.28),
    "alpine": dict(far=(0xb4c4d4, 0x97aabd), mist=0xe9eff3, hill=(0x6c7c8e, 0x8b9bad), trees=False, snow=True, jag=1.0),
}
NIGHT = dict(far=(0x2e3d52, 0x25344a), mist=0x3a4d66, hill=(0x1f2d3b, 0x2c3c4d), snow=False)


def ridge_h(x, depth, seed, base, amp, jag):
    """height in metres at layer-x (units) and depth (m)"""
    X = x * U
    n = noise.fractal((X * 0.035 + seed, depth * 0.05, 0.3), 0.55, 2.0, 5)
    r = 1 - abs(noise.noise((X * 0.05 + seed * 2, depth * 0.04, 1.7))) * 2
    return base + amp * ((1 - jag) * n * 1.4 + jag * r * 0.9 + 0.2 * math.sin(X * 0.04 + seed))


def heightfield(W_u, depth_m, seed, base, amp, jag, material):
    step = 10
    xs = [k * step for k in range(int(W_u / step) + 3)]
    rows = [0.0, 3.0, 8.0, 14.0, depth_m]
    bm = bmesh.new()
    grid = []
    for x in xs:
        col = [bm.verts.new((x * U, 0.0, -1.0))]      # skirt below the front edge
        for d in rows:
            col.append(bm.verts.new((x * U, d, ridge_h(x, d, seed, base, amp, jag))))
        grid.append(col)
    for a, b in zip(grid, grid[1:]):
        for k in range(len(rows)):
            bm.faces.new((a[k], b[k], b[k + 1], a[k + 1]))
    me = bpy.data.meshes.new("ridge")
    bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new("ridge", me)
    link(o)
    me.materials.append(material)
    for p in me.polygons: p.use_smooth = True
    return o


def ridge_material(color, mist, hmax, snow=False, mistk=0.45):
    """colour fading into mist towards the bottom, optional snow on the heights"""
    m = bpy.data.materials.new("ridge")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bs.inputs["Roughness"].default_value = 0.95
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    fac = nt.nodes.new("ShaderNodeMapRange")
    fac.inputs["From Min"].default_value = 0.0
    fac.inputs["From Max"].default_value = hmax * mistk
    nt.links.new(sep.outputs[2], fac.inputs["Value"])
    mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"
    mix.inputs[6].default_value = srgb(mist)
    mix.inputs[7].default_value = srgb(color)
    nt.links.new(fac.outputs["Result"], mix.inputs[0])
    col = mix.outputs[2]
    if snow:
        sn = nt.nodes.new("ShaderNodeMapRange")
        sn.inputs["From Min"].default_value = hmax * 0.62
        sn.inputs["From Max"].default_value = hmax * 0.70
        nt.links.new(sep.outputs[2], sn.inputs["Value"])
        m2 = nt.nodes.new("ShaderNodeMix"); m2.data_type = "RGBA"
        m2.inputs[7].default_value = srgb(0xf4f8fb)
        nt.links.new(sn.outputs["Result"], m2.inputs[0]); nt.links.new(col, m2.inputs[6])
        col = m2.outputs[2]
    nt.links.new(col, bs.inputs["Base Color"])
    nt.links.new(bs.outputs["BSDF"], out.inputs["Surface"])
    return m


def render_layer(name, W_u, H_u, preview):
    W_px, H_px = int(W_u * S), int(H_u * S)
    setup_render(W_px, H_px, samples=12 if preview else 32)
    world(strength=1.0)
    cam = ortho_camera(width=W_u * U)
    pivot = bpy.data.objects.new("pivot", None); link(pivot)
    sun("key", 2.3, (52, 0, -35), parent=pivot)
    sun("fill", 0.7, (70, 0, 140), color=(0.8, 0.88, 1.0), parent=pivot)
    sun("rim", 0.8, (115, 0, 200), parent=pivot)
    pivot.rotation_euler = (0, 0, math.radians(-90))
    target = Vector((W_u * U / 2, 10, H_u * U / 2 * math.cos(E) - 0.0))
    cam.location = target + Vector((0, -80 * math.cos(E), 80 * math.sin(E)))
    aim(cam, target)
    bpy.context.view_layer.update()
    # push the picture so that the front skirt (z = 0, depth 0) sits on the bottom edge
    low = project(cam, (W_u * U / 2, 0, 0))[1]
    cam.data.shift_y = (0.0 - low) * H_px / W_px * -1
    render(os.path.join(OUT, "panorama", name + ".png"))
    return {"w": W_u, "h": H_u}


def main():
    preview = "--preview" in argv()
    only = [a.split("=")[1] for a in argv() if a.startswith("--only=")]
    mf = os.path.join(OUT, "panorama", "panorama.json")
    meta = json.load(open(mf)) if os.path.exists(mf) else {}
    for fn in sorted(os.listdir(MISSIONS)):
        if not fn.endswith(".json"): continue
        mission = json.load(open(os.path.join(MISSIONS, fn)))
        if only and mission["id"] not in only: continue
        look = mission.get("look") or "valley"
        pal = dict(PAL.get(look, PAL["valley"]))
        if (mission.get("atmosphere") or {}).get("sky") == "night":
            pal.update(NIGHT)
        W = mission["world"]["width"]
        # far mountains: two ridges
        reset()
        Wf, Hf = int(W * 0.12 + 1280), 460
        hm = Hf * U
        for i, (depth, base, amp, col) in enumerate(((22, 0.42, 0.20, pal["far"][1]), (12, 0.30, 0.17, pal["far"][0]))):
            pass
        sc = pal.get("scale", 1.0); mk = pal.get("mistk", 0.45)
        back = heightfield(Wf, 20, 3.1, hm * 0.40 * sc, hm * 0.30 * sc, pal.get("jag", 0.12), ridge_material(pal["far"][0], pal["mist"], hm * 0.8, pal.get("snow", False), mk))
        back.location.y = 14
        front = heightfield(Wf, 14, 7.7, hm * 0.22 * sc, hm * 0.18 * sc, pal.get("jag", 0.12), ridge_material(pal["far"][1], pal["mist"], hm * 0.8, pal.get("snow", False), mk))
        meta[mission["id"] + "-far"] = render_layer("far-" + mission["id"], Wf, Hf, preview)
        # wooded hills
        reset()
        Wh, Hh = int(W * 0.35 + 1280), 400
        hm = Hh * U
        hill = heightfield(Wh, 16, 5.2, hm * 0.32, hm * 0.12, 0.1, ridge_material(pal["hill"][1], pal["mist"], hm * 0.7))
        if pal.get("trees"):
            rng = hexrand(77)
            x = 0.0
            parts = []
            while x < Wh:
                gx = x + rng.uniform(-6, 6)
                d = rng.uniform(1.0, 12.0)
                z = ridge_h(gx, d, 5.2, hm * 0.32, hm * 0.12, 0.1)
                if rng.random() > 0.15:
                    tree("conifer", gx * U, d, z - 0.2, rng.uniform(34, 70) * U, rng, parts)
                x += 26
            # hill trees keep the soft blue-green of distance
            for o in parts:
                for ms in o.data.materials:
                    if ms and ms.use_nodes:
                        b = ms.node_tree.nodes.get("Principled BSDF")
                        if b:
                            c = b.inputs["Base Color"].default_value
                            b.inputs["Base Color"].default_value = (c[0] * 0.55 + 0.04, c[1] * 0.6 + 0.07, c[2] * 0.6 + 0.08, 1)
        meta[mission["id"] + "-hill"] = render_layer("hill-" + mission["id"], Wh, Hh, preview)
        json.dump(meta, open(mf, "w"), indent=1)
        print("pano", mission["id"])


if __name__ == "__main__":
    main()
