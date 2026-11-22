"""Exterior storytelling props from Sketchfab (CC-BY, credits in assets/CREDITS_SKETCHFAB.json) -> assets/env/town_props/.
Raw glbs (not committed): scratchpad/sf_raw/<name>.glb.  Run: venv/bin/python -I tools/town/props_sf.py [name ...] [--probe]
Convention: real metres, base at y=0, footprint centred, front = Godot +Z (Blender -Y)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "charpipe", "bosses"))
import hd_common as H
from hd_common import *

RAW = os.path.join(H.SCRATCH, "sf_raw")
# name: (size m, 'len'|'h', texture px, target faces, extra z rotation deg)
SPEC = {
    "sandbags":   (2.6, "len", 1024, 12000, 0),
    "laundry":    (4.2, "len", 1024, 9000, 0),
    "shovel":     (1.35, "h", 512, 3000, 0),
    "trash_pile": (2.6, "len", 1024, 12000, 0),
    "neon_open":  (0.62, "len", 512, 6000, 0),
    "snowman":    (1.45, "h", 1024, 12000, 0),
    "sled":       (1.3, "len", 512, 6000, 0),
}

def load(name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(RAW, name + ".glb"))
    obs = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in obs:
        mw = o.matrix_world.copy()
        o.parent = None
        o.data.transform(mw)
        o.matrix_world = Matrix.Identity(4)
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    if len(obs) > 1:
        bpy.ops.object.join()
    o = [o for o in bpy.data.objects if o.type == "MESH"][0]
    for e in [e for e in bpy.data.objects if e.type != "MESH"]:
        bpy.data.objects.remove(e)
    o.name = name
    return o

def build(name, probe=False):
    size, mode, tex, ft, rz = SPEC[name]
    o = load(name)
    v = verts(o)
    ext = v.max(0) - v.min(0)
    s = size / (max(ext[0], ext[1]) if mode == "len" else ext[2])
    # long axis along X (left-right as seen from the front)
    r = rz + (90.0 if (mode == "len" and ext[1] > ext[0]) else 0.0)
    orient(o, s, rotz_deg=r, center="bbox")
    v = verts(o)
    print(name, "ext", np.round(v.max(0) - v.min(0), 3), "polys", len(o.data.polygons))
    for view in ("front", "side"):
        preview(o, "tp_%s_%s" % (name, view), view=view, grid=size / 8)
    if probe:
        return
    downscale_images(tex)
    if len(o.data.polygons) > ft:
        m = o.modifiers.new("dec", "DECIMATE")
        m.ratio = ft / len(o.data.polygons)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier="dec")
    for m in o.data.materials:
        if m:
            m.name = name + "_" + m.name
    out = os.path.join(REPO, "assets/env/town_props", name + ".glb")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    export(out, [o])

if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    for n in (args or list(SPEC)):
        build(n, probe="--probe" in sys.argv)
