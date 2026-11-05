"""Poly Haven (CC0) service_pistol + hatchet -> assets/weapons/<id>/<id>.glb with markers.
usage: python build_handgun_hatchet.py <pistol_gltf> <hatchet_gltf> <outdir>"""
import sys, os, math, bpy
sys.path.insert(0, os.path.dirname(__file__))
from wlib import *
from mathutils import Vector

pg, hg, outdir = sys.argv[-3:]

# ---------------------------------------------------------------- handgun
reset()
bpy.ops.import_scene.gltf(filepath=pg)
root = bpy.data.objects.new("Handgun", None); bpy.context.collection.objects.link(root)
root.rotation_euler = (0, 0, math.radians(90))      # source barrel is +X -> weapon forward +Y
keep = {"service_pistol_pistol_a": "Frame", "service_pistol_slide_a": "Slide", "service_pistol_magazine_loaded": "Magazine",
        "service_pistol_hammer_a": "Hammer", "service_pistol_trigger_a": "Trigger"}
for o in list(bpy.data.objects):
    if o.type == 'MESH' and o.name in keep:
        o.name = keep[o.name]; o.parent = root
    elif o is not root:
        bpy.data.objects.remove(o, do_unlink=True)
bpy.data.objects["Magazine"].location.x = 0.0
# source frame: x fwd, y left, z up (pre-rotation). marker axes given in SOURCE frame (root rotates them into weapon space)
F = (1, 0, 0); U = (0, 0, 1); L = (0, 1, 0); R = (0, -1, 0)
empty("Grip_R", (-0.016, -0.0125, -0.012), root, axes=(U, F, L))        # right palm on the back/right of the grip
empty("Support_L", (0.004, 0.0135, -0.034), root, axes=((0, 0, -1), F, R))   # left palm on the left side, low
empty("Muzzle", (0.176, 0.0, 0.061), root)
empty("Eject", (0.012, -0.015, 0.067), root, axes=(U, F, R))
export(os.path.join(outdir, "handgun", "handgun.glb"), root)

# ---------------------------------------------------------------- hatchet
reset()
bpy.ops.import_scene.gltf(filepath=hg)
root = bpy.data.objects.new("Knife", None); bpy.context.collection.objects.link(root)
# source: handle along z (up), blade toward -y (blender). Rotate so blade edge faces +Y (forward).
root.rotation_euler = (0, 0, math.radians(180))
for o in list(bpy.data.objects):
    if o.type == 'MESH':
        o.name = "Hatchet"; o.parent = root
    elif o is not root:
        bpy.data.objects.remove(o, do_unlink=True)
for o in bpy.data.objects:
    if o.type == 'MESH':
        pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
        print("HATCHET bbox", [round(min(p[i] for p in pts), 3) for i in range(3)], [round(max(p[i] for p in pts), 3) for i in range(3)])
# markers in source frame (blade toward -y): "forward" there is -y
F = (0, -1, 0); U = (0, 0, 1); Lf = (1, 0, 0)    # source: forward=-y; left = up x forward... (0,0,1)x(0,-1,0) = (1,0,0)
empty("Grip_R", (0.0, 0.0, 0.0), root, axes=(U, F, Lf))
empty("Muzzle", (0.0, -0.05, 0.2), root)    # blade centre (hit point) - used for trail/spark
export(os.path.join(outdir, "knife", "knife.glb"), root)
