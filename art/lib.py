"""Shared helpers for the Rotorwacht art pipeline (run inside Blender: blender -b -P art/<script>.py).

Everything is generated from code: no external models or textures. Colours follow the project
palette (terracotta accent, warm greys) so the 3D renders sit well next to the menu design.
"""
import bpy, bmesh, math, json, os, sys, random
from mathutils import Vector, Matrix, Euler
from bpy_extras.object_utils import world_to_camera_view

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT = os.path.join(ROOT, "Sources", "Rotorwacht", "Renders")
MISSIONS = os.path.join(ROOT, "Sources", "RotorwachtCore", "Missions")


def argv():
    """Arguments after `--` on the Blender command line."""
    a = sys.argv
    return a[a.index("--") + 1:] if "--" in a else []


def srgb(h):
    """0xRRGGBB -> linear RGBA."""
    def lin(c):
        c /= 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin((h >> 16) & 255), lin((h >> 8) & 255), lin(h & 255), 1.0)


_mats = {}


def mat(name, color, rough=0.5, metal=0.0, emit=None, strength=0.0, alpha=1.0, coat=0.0, spec=0.5):
    if name in _mats and name in bpy.data.materials:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = srgb(color)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if "Coat Weight" in p.inputs:
        p.inputs["Coat Weight"].default_value = coat
    if emit is not None:
        p.inputs["Emission Color"].default_value = srgb(emit)
        p.inputs["Emission Strength"].default_value = strength
    if alpha < 1.0:
        p.inputs["Alpha"].default_value = alpha
    _mats[name] = m
    return m


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()


def assign(obj, *materials):
    obj.data.materials.clear()
    for m in materials:
        obj.data.materials.append(m)


def link(obj, coll=None):
    (coll or bpy.context.scene.collection).objects.link(obj)
    return obj


def mesh_obj(name, bm, mats=()):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    link(o)
    for m in mats:
        o.data.materials.append(m)
    return o


def smooth(o, subsurf=0, bevel=0.0):
    for p in o.data.polygons:
        p.use_smooth = True
    if bevel:
        b = o.modifiers.new("bevel", "BEVEL")
        b.width = bevel
        b.segments = 2
        b.limit_method = "ANGLE"
    if subsurf:
        s = o.modifiers.new("sub", "SUBSURF")
        s.levels = subsurf
        s.render_levels = subsurf
    return o


def prim(kind, name, loc=(0, 0, 0), scale=(1, 1, 1), rot=(0, 0, 0), mats=(), **kw):
    """Quick primitive. kind: cube, sphere, cyl, cone, torus."""
    if kind == "cube":
        bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    elif kind == "sphere":
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.5, segments=kw.get("seg", 32), ring_count=kw.get("rings", 16), location=loc)
    elif kind == "cyl":
        bpy.ops.mesh.primitive_cylinder_add(radius=0.5, depth=1, vertices=kw.get("seg", 24), location=loc)
    elif kind == "cone":
        bpy.ops.mesh.primitive_cone_add(radius1=0.5, radius2=kw.get("r2", 0.0), depth=1, vertices=kw.get("seg", 24), location=loc)
    elif kind == "torus":
        bpy.ops.mesh.primitive_torus_add(major_radius=0.5, minor_radius=kw.get("minor", 0.08), major_segments=48, minor_segments=16, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    o.rotation_euler = tuple(math.radians(a) for a in rot)
    bpy.ops.object.transform_apply(scale=True)
    for p in o.data.polygons:
        p.use_smooth = kw.get("smooth", kind in ("sphere", "torus"))
    for m in mats:
        o.data.materials.append(m)
    if kw.get("bevel"):
        b = o.modifiers.new("bevel", "BEVEL")
        b.width = kw["bevel"]
        b.segments = 2
    return o


def tube(name, pts, radius, material, res=8):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = res
    cu.use_fill_caps = True
    sp = cu.splines.new("POLY" if len(pts) < 3 else "NURBS")
    sp.points.add(len(pts) - 1)
    for i, p in enumerate(pts):
        sp.points[i].co = (p[0], p[1], p[2], 1)
    if sp.type == "NURBS":
        sp.order_u = 3
        sp.use_endpoint_u = True
    o = bpy.data.objects.new(name, cu)
    link(o)
    o.data.materials.append(material)
    return o


def setup_render(w, h, samples=64, engine="CYCLES"):
    s = bpy.context.scene
    s.render.engine = engine
    s.render.resolution_x = w
    s.render.resolution_y = h
    s.render.resolution_percentage = 100
    s.render.film_transparent = True
    s.render.image_settings.file_format = "PNG"
    s.render.image_settings.color_mode = "RGBA"
    s.render.image_settings.compression = 90
    s.cycles.samples = samples
    s.cycles.use_denoising = True
    s.cycles.device = "CPU"
    s.view_settings.view_transform = "Standard"
    s.view_settings.look = "None"
    return s


def world(sky=(0.70, 0.80, 0.92), strength=0.9, ground=(0.35, 0.33, 0.30)):
    """Soft sky light: bluish from above, warm bounce from below."""
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (*[c for c in ground], 1)
    ramp.color_ramp.elements[1].position = 0.65
    ramp.color_ramp.elements[1].color = (*[c for c in sky], 1)
    mapr = nt.nodes.new("ShaderNodeMapRange")
    mapr.inputs["From Min"].default_value = -1
    mapr.inputs["From Max"].default_value = 1
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    # Generated coords of the world are 0..1; use the camera-independent "Window"-free direction instead
    nt.nodes.remove(tc)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    nt.links.new(geo.outputs["Normal"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], mapr.inputs["Value"])
    nt.links.new(mapr.outputs["Result"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = strength
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    bpy.context.scene.world = w
    return w


def sun(name, energy, rot_deg, color=(1.0, 0.95, 0.86), angle=3.0, parent=None):
    ld = bpy.data.lights.new(name, "SUN")
    ld.energy = energy
    ld.color = color
    ld.angle = math.radians(angle)
    o = bpy.data.objects.new(name, ld)
    o.rotation_euler = tuple(math.radians(a) for a in rot_deg)
    link(o)
    if parent:
        o.parent = parent
    return o


def ortho_camera(name="cam", width=10.0):
    cd = bpy.data.cameras.new(name)
    cd.type = "ORTHO"
    cd.ortho_scale = width
    cd.sensor_fit = "HORIZONTAL"
    cd.clip_start = 0.1
    cd.clip_end = 2000
    o = bpy.data.objects.new(name, cd)
    link(o)
    bpy.context.scene.camera = o
    return o


def aim(obj, target):
    d = Vector(target) - obj.location
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def render(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def project(cam, p):
    """World point -> (u, v) in the image, 0..1 from the bottom left."""
    c = world_to_camera_view(bpy.context.scene, cam, Vector(p))
    return [round(c.x, 5), round(c.y, 5)]


def hexrand(seed):
    return random.Random(seed)
