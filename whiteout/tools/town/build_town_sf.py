"""Sketchfab town assets -> game-ready glb (assets/env/town_sf/<name>.glb) + town_sf/sizes.json.
Real-world metres, base at y=0, footprint centred on x/z origin, front = +Z, one mesh, tex <= 1024.
Run: venv/bin/python -I tools/town/build_town_sf.py <raw_dir> [name ...]
"""
import bpy, sys, os, json, math, glob
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "env", "town_sf")
# name: (raw file, target height m, yaw fix deg (applied about vertical), strip_ground, tri budget, kind)
CFG = {
 "house_american":  ("h_american", 7.6, 0, True, 36000),
 "house_colonial":  ("h_colonial", 8.4, 0, True, 36000),
 "house_glen":      ("h_glen", 4.4, 0, True, 22000),
 "house_porch":     ("h_porch", 7.4, 0, True, 12000),
 "house_ranch":     ("h_ranch", 4.3, 0, True, 26000),
 "house_suburban":  ("h_suburban", 8.2, 0, True, 38000),
 "house_twostory":  ("h_twostory", 7.8, 0, True, 6000),
 "house_weathered": ("h_weathered", 8.4, 0, False, 14000),
 "shop_brick":      ("b_brickshop", 8.2, 0, True, 6000),
 "shop_gray":       ("b_oldbldg", 8.6, 0, True, 6000),
 "shop_long":       ("b_oldamerican", 7.6, 0, True, 6000),
 "shop_pair":       ("b_oldpack", 9.5, 0, True, 22000),
 "block_tall":      ("b_twin", 13.5, 0, True, 12000),
 "block_row":       ("b_brooklyn", 15.0, 0, True, 12000),
 "block_nyc":       ("b_nyc", 11.0, 0, True, 12000),
 "gas_station":     ("gas_old2", 6.0, 0, True, 20000),
 "church_small":    ("church", 17.0, 0, True, 20000),
 "garage_brick":    ("s_brickgarage", 3.4, 0, True, 6000),
 "warehouse_red":   ("w_red", 8.0, 0, True, 4000),
 "pole_utility":    ("p_pole", 10.5, 0, False, 16000),
 "dumpster_a":      ("p_dumpster", 1.5, 0, False, 5000),
 "dumpster_b":      ("p_dumpster2", 1.5, 0, False, 6000),
 "mailbox_us":      ("p_mailbox2", 1.4, 0, False, 3000),
}

def bbox(objs):
    mn = Vector((1e9,) * 3); mx = Vector((-1e9,) * 3)
    for o in objs:
        for c in o.bound_box:
            p = o.matrix_world @ Vector(c)
            mn = Vector(map(min, mn, p)); mx = Vector(map(max, mx, p))
    return mn, mx

def process(name, raw_dir):
    raw, H, yaw, strip, budget = CFG[name]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(raw_dir, raw + ".glb"))
    objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    for o in bpy.context.scene.objects:
        if o.type != 'MESH':
            o.select_set(False)
    # bake world transforms
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    for o in objs:
        mw = o.matrix_world.copy(); o.parent = None; o.matrix_world = mw
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    mn, mx = bbox(objs)
    ext = mx - mn
    if strip:  # drop flat ground slabs (sidewalk / grass / street) lying at the base
        for o in list(objs):
            a, b = bbox([o])
            e = b - a
            if e.z < 0.04 * ext.z + 0.05 and (e.x * e.y) > 0.15 * ext.x * ext.y and a.z < mn.z + 0.2 * ext.z:
                bpy.data.objects.remove(o, do_unlink=True); objs.remove(o)
    # join
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if tris > budget:
        m = ob.modifiers.new("d", 'DECIMATE'); m.ratio = budget / tris
        bpy.ops.object.modifier_apply(modifier=m.name)
    mn, mx = bbox([ob])
    s = H / (mx.z - mn.z)
    # wide models: also cap footprint
    ob.scale = (s, s, s)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if yaw:
        ob.rotation_euler = (0, 0, math.radians(yaw))
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    mn, mx = bbox([ob])
    ob.location = Vector((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z))
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    mn, mx = bbox([ob])
    # textures <= 1024
    n_img = len(bpy.data.images)
    cap = 1024 if n_img <= 6 else (512 if n_img <= 20 else 256)
    for im in bpy.data.images:
        if im.size[0] > cap or im.size[1] > cap:
            k = cap / max(im.size)
            im.scale(max(4, int(im.size[0] * k)), max(4, int(im.size[1] * k)))
    ob.name = name
    out = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=False, export_apply=True,
                              export_image_format='JPEG', export_image_quality=82, export_yup=True, export_cameras=False, export_lights=False)
    # blender (x, y, z) -> gltf (x, z, -y): width=x, depth=y, front toward blender -Y
    return {"w": round(mx.x - mn.x, 2), "d": round(mx.y - mn.y, 2), "h": round(mx.z - mn.z, 2),
            "tris": sum(len(p.vertices) - 2 for p in ob.data.polygons), "kb": os.path.getsize(out) // 1024}

if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    raw_dir = args[0]
    names = args[1:] or list(CFG)
    sj = os.path.join(OUT, "sizes.json")
    sizes = json.load(open(sj)) if os.path.exists(sj) else {}
    for n in names:
        try:
            sizes[n] = process(n, raw_dir); print(n, sizes[n])
        except Exception as e:
            print("FAIL", n, e)
    json.dump(sizes, open(sj, "w"), indent=1, sort_keys=True)
