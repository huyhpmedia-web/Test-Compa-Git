"""HD props from Higgsfield/Tripo H3.1 image->3D (vehicles, weapons, set pieces).
Raw glbs (not committed) in $HD_RAW2 (default scratchpad/tripo_raw2/<name>.glb).
Run: venv/bin/python tools/charpipe/props_hd.py [name ...] [--probe]
Convention: front of vehicles / muzzle of weapons faces Blender -Y = Godot +Z. Origin: base centre (vehicles/props),
grip area for weapons is left to the weapon loader markers (origin = bbox centre for weapons).
"""
import os, sys, math
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "bosses"))
import hd_common as H
from hd_common import *

RAW2 = os.environ.get("HD_RAW2", os.path.join(H.SCRATCH, "tripo_raw2"))
# name: (out path, size metres, measure 'len'|'h', texture px, target faces)
SPEC = {
    "sedan":        ("assets/env/vehicles/sedan.glb", 4.85, "len", 2048, 40000),
    "police":       ("assets/env/vehicles/police.glb", 5.2, "len", 2048, 40000),
    "ambulance":    ("assets/env/vehicles/ambulance.glb", 6.4, "len", 2048, 40000),
    "bucket_truck": ("assets/env/vehicles/bucket_truck.glb", 7.8, "len", 2048, 45000),
    "haul_truck":   ("assets/env/vehicles/haul_truck.glb", 10.0, "len", 2048, 45000),
    "transformer":  ("assets/env/props/transformer.glb", 3.0, "h", 2048, 35000),
    "server_rack":  ("assets/env/props/server_rack.glb", 2.0, "h", 1024, 20000),
    "steeple":      ("assets/env/props/steeple.glb", 9.0, "h", 2048, 30000),
    "van":          ("assets/env/vehicles/van.glb", 5.9, "len", 2048, 40000),
    "snowplow":     ("assets/env/vehicles/snowplow.glb", 9.0, "len", 2048, 45000),
    "ice_cluster":  ("assets/env/props/ice_cluster.glb", 2.2, "h", 2048, 30000),
    "ore_cart":     ("assets/env/props/ore_cart.glb", 1.6, "len", 1024, 20000),
    "reception_desk": ("assets/env/props/reception_desk.glb", 3.0, "len", 1024, 20000),
    "shotgun":      ("assets/weapons/shotgun/shotgun.glb", 1.0, "len", 2048, 20000),
    "magnum":       ("assets/weapons/magnum/magnum.glb", 0.30, "len", 2048, 15000),
    "launcher":     ("assets/weapons/launcher/launcher.glb", 0.24, "len", 2048, 10000),
}
# extra rotation (deg about Z) after auto-alignment, filled in after looking at the probe previews
FIX = {"sedan": 180, "police": 180, "ambulance": 180, "bucket_truck": 180, "haul_truck": 180,
    "shotgun": 180, "magnum": 180, "van": 180, "snowplow": 180, "reception_desk": -90}
# real-world (width x, length y, height z) for vehicles: Tripo widens/heightens single-view cars a bit
DIMS = {"sedan": (1.86, 4.9, 1.48), "police": (2.0, 5.3, 1.72), "ambulance": (2.4, 6.6, 2.9),
        "bucket_truck": (2.45, 7.8, 3.7), "van": (2.03, 5.9, 2.1), "snowplow": (2.6, 9.0, 3.3), "reception_desk": (3.0, 1.45, 1.15), "haul_truck": (6.1, 10.0, 5.0)}


def load(name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(RAW2, name + ".glb"))
    obs = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in obs:
        mw = o.matrix_world.copy()
        o.parent = None
        o.data.transform(mw)
        o.matrix_world = Matrix.Identity(4)
    if len(obs) > 1:
        bpy.ops.object.select_all(action="DESELECT")
        for o in obs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = obs[0]
        bpy.ops.object.join()
    o = [o for o in bpy.data.objects if o.type == "MESH"][0]
    for e in [e for e in bpy.data.objects if e.type != "MESH"]:
        bpy.data.objects.remove(e)
    o.name = name
    return o


def decimate(o, target):
    n = len(o.data.polygons)
    if n > target:
        m = o.modifiers.new("dec", "DECIMATE")
        m.ratio = target / n
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier="dec")


def build(name, probe=False):
    out, size, mode, tex, faces_t = SPEC[name]
    o = load(name)
    v = verts(o)
    ext = v.max(0) - v.min(0)
    # long horizontal axis -> Y (rotate 90 if X is longer)
    rz = 90.0 if (mode == "len" and ext[0] > ext[1]) else 0.0
    rz += FIX.get(name, 0.0)
    v = verts(o)
    if mode == "len":
        s = size / max(ext[0], ext[1])
    else:
        s = size / ext[2]
    orient(o, s, rotz_deg=rz, center="bbox")
    if name in DIMS:
        v = verts(o)
        e = v.max(0) - v.min(0)
        t = DIMS[name]
        o.data.transform(Matrix.Diagonal((t[0] / e[0], t[1] / e[1], t[2] / e[2], 1.0)))
        o.data.update()
    if out.startswith("assets/weapons"):
        v = verts(o)
        c = (v.max(0) + v.min(0)) / 2
        o.data.transform(Matrix.Translation((-c[0], -c[1], -c[2])))
    for view in ("top", "side", "front"):
        preview(o, "%s_%s" % (name, view), view=view, grid=size / 8)
    if probe:
        print(name, "ext", np.round(verts(o).max(0) - verts(o).min(0), 3), "polys", len(o.data.polygons))
        return
    downscale_images(tex)
    decimate(o, faces_t)
    for m in o.data.materials:
        m.name = name + "_hd"
    os.makedirs(os.path.join(REPO, os.path.dirname(out)), exist_ok=True)
    export(os.path.join(REPO, out), [o])


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    for n in (args or list(SPEC)):
        build(n, probe="--probe" in sys.argv)
