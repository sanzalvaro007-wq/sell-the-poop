# Genera el modelo 3D "CacaGigante" (caca con cara) en Blender y lo exporta a FBX y OBJ.
# Uso: blender --background --python caca_gigante.py -- <carpeta_salida>
# El perfil es el mismo que usa src/server/Map.luau para la caca de bloques.
import math
import os
import sys

import bpy
from mathutils import Vector

out_dir = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.path.dirname(os.path.abspath(__file__))
R = 10.0  # radio del piso de abajo (en Roblox se reescala solo)

TIERS = [
    {"r": 1.0, "h": 0.5, "y": 0.0},
    {"r": 0.72, "h": 0.42, "y": 0.4},
    {"r": 0.45, "h": 0.34, "y": 0.72},
]


def tier_radius(t, dy):
    h = t["h"] * R
    if dy < 0 or dy > h:
        return 0.0
    c = 0.35 * h
    k = (c - dy) / (c * 1.6) if dy < c else (dy - c) / (h - c)
    return t["r"] * R * math.sqrt(max(0.0, 1 - k * k))


def radius_at(z):
    return max(tier_radius(t, z - t["y"] * R) for t in TIERS)


def material(name, rgb, rough=0.45):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Roughness"].default_value = rough
    return m


bpy.ops.wm.read_factory_settings(use_empty=True)
brown = material("Caca", (0.17, 0.065, 0.018))
white = material("Blanco", (0.9, 0.9, 0.9), 0.3)
black = material("Negro", (0.004, 0.004, 0.004), 0.2)
mouth = material("Boca", (0.045, 0.005, 0.005), 0.4)

# Cuerpo: perfil girado 360º (torno)
top = (TIERS[-1]["y"] + TIERS[-1]["h"]) * R
steps = 120
verts = [(0.0, 0.0, 0.0)]
for i in range(steps + 1):
    z = top * i / steps
    verts.append((radius_at(z), 0.0, z))
verts.append((0.0, 0.0, top))
edges = [(i, i + 1) for i in range(len(verts) - 1)]
mesh = bpy.data.meshes.new("CuerpoPerfil")
mesh.from_pydata(verts, edges, [])
body = bpy.data.objects.new("Cuerpo", mesh)
bpy.context.scene.collection.objects.link(body)
bpy.context.view_layer.objects.active = body
screw = body.modifiers.new("Torno", "SCREW")
screw.axis = "Z"
screw.steps = 64
screw.render_steps = 64
screw.use_merge_vertices = True
bpy.ops.object.modifier_apply(modifier="Torno")
bpy.ops.object.shade_smooth()
body.data.materials.append(brown)

# Normales hacia fuera
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.object.mode_set(mode="OBJECT")


def sphere(name, pos, d, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=d / 2, location=pos, segments=32, ring_count=16)
    o = bpy.context.object
    o.name = name
    bpy.ops.object.shade_smooth()
    o.data.materials.append(mat)
    return o


# Punta con rizo
sphere("Punta", (0, 0, top + 0.03 * R), 0.26 * R, brown)
sphere("Rizo", (0.08 * R, 0, top + 0.15 * R), 0.14 * R, brown)

# Cara mirando hacia -Y de Blender
t = TIERS[0]
h = t["h"] * R


def surface(x, dy, out):
    r = tier_radius(t, dy)
    y = math.sqrt(max(0.0, r * r - x * x))
    return Vector((x, -(y + out), dy))


eye_y = 0.5 * h
for side, tag in ((-1, "Izq"), (1, "Der")):
    x = side * 0.26 * R
    sphere("Ojo" + tag, surface(x, eye_y, -0.03 * R), 0.24 * R, white)
    sphere("Pupila" + tag, surface(x * 0.95, eye_y + 0.01 * R, 0.07 * R), 0.11 * R, black)

# Sonrisa: un tubo curvo
pts = []
for i in range(-8, 9):
    x = i * 0.0225 * R
    dy = 0.14 * h + 0.0015 * R * (i * i)
    pts.append(surface(x, dy, 0.0))
curve = bpy.data.curves.new("Sonrisa", "CURVE")
curve.dimensions = "3D"
spline = curve.splines.new("POLY")
spline.points.add(len(pts) - 1)
for p, v in zip(spline.points, pts):
    p.co = (v.x, v.y, v.z, 1)
curve.bevel_depth = 0.035 * R
curve.bevel_resolution = 4
curve.use_fill_caps = True
smile = bpy.data.objects.new("Boca", curve)
bpy.context.scene.collection.objects.link(smile)
bpy.context.view_layer.objects.active = smile
smile.select_set(True)
bpy.ops.object.convert(target="MESH")
smile.data.materials.append(mouth)

os.makedirs(out_dir, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.fbx(
    filepath=os.path.join(out_dir, "CacaGigante.fbx"),
    use_selection=True,
    apply_scale_options="FBX_SCALE_ALL",
    axis_forward="-Z",
    axis_up="Y",
)
bpy.ops.wm.obj_export(filepath=os.path.join(out_dir, "CacaGigante.obj"), export_selected_objects=True, forward_axis="NEGATIVE_Z", up_axis="Y")
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out_dir, "CacaGigante.blend"))
print("exportado en", out_dir)
