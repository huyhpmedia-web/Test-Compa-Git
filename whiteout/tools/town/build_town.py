"""Town buildings: 3D Jutsu catalog meshes (vertex-coloured low-poly) -> game-ready glbs with
material categories + metric box-projected UVs. Godot (world/town.gd) swaps the category materials
for shared PBR materials (textures/town/*), so the glbs stay tiny.

Run: venv/bin/python tools/town/build_town.py <town.glb from 3D Jutsu> [--preview DIR]
Material names written: ROOF, SNOW, SIDING_rrggbb, TRIM, BRICK, STONE, WOOD, GLASS, DARK, METAL.
"""
import bpy, bmesh, sys, os, colorsys, math
import numpy as np
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "env", "town")

# name in glb -> (output name, target height m, yaw fix deg)
KEEP = {
    "two_story_house": ("house_two_story", 8.6, 0),
    "bungalow_house": ("house_bungalow", 6.2, 0),
    "ranch_house": ("house_ranch", 5.2, 0),
    "split_level_house": ("house_split", 7.4, 0),
    "townhouse_duplex": ("house_duplex", 8.4, 0),
    "farmhouse": ("house_farm", 7.6, 0),
    "home_timber_2storey_01": ("house_timber", 7.4, 0),
    "home_townhouse_01": ("house_narrow", 8.2, 0),
    "corner_store_01": ("shop_corner", 9.6, 0),
    "small_office_01": ("office_small", 12.5, 0),
    "station_building": ("hall_station", 6.6, 0),
    "diner_01": ("shop_diner", 5.6, 0),
    "general_store": ("shop_wood_store", 6.0, 0),
    "privacy_fence": ("fence_privacy", 1.9, 0),
    "picket_fence": ("fence_picket", 1.1, 0),
}
TILE = {"SIDING": 2.0, "ROOF": 2.2, "BRICK": 1.8, "STONE": 2.0, "TRIM": 1.5, "WOOD": 2.0, "SNOW": 3.0,
        "GLASS": 1.0, "DARK": 1.5, "METAL": 1.5}


def face_colors(me):
    ca = me.color_attributes.get("Color") or (me.color_attributes[0] if len(me.color_attributes) else None)
    n = len(me.polygons)
    if ca is None:
        return np.full((n, 3), 0.7)
    a = np.empty(len(ca.data) * 4, dtype=np.float32)
    ca.data.foreach_get("color", a)
    a = a.reshape(-1, 4)[:, :3]
    if ca.domain == "POINT":
        vi = np.empty(len(me.loops), dtype=np.int32)
        me.loops.foreach_get("vertex_index", vi)
        a = a[vi]
    ls = np.empty(n, dtype=np.int32); me.polygons.foreach_get("loop_start", ls)
    lt = np.empty(n, dtype=np.int32); me.polygons.foreach_get("loop_total", lt)
    out = np.zeros((n, 3))
    for i in range(n):
        out[i] = a[ls[i]:ls[i] + lt[i]].mean(0)
    # BYTE_COLOR attributes come back linear; convert to sRGB for classification
    return np.where(out <= 0.0031308, out * 12.92, 1.055 * np.power(np.clip(out, 0, 1), 1 / 2.4) - 0.055)


def classify(c, nz, zc, H, zmin_face):
    h, s, v = colorsys.rgb_to_hsv(*c)
    hd = h * 360
    roofish = nz > 0.30 and zc > 0.40 * H
    if roofish and nz > 0.45:
        return "SNOW"
    if 160 <= hd <= 200 and 0.06 < s < 0.32 and v >= 0.55 and abs(nz) < 0.3:
        return "GLASS"
    if roofish:
        return "ROOF"
    if v < 0.18:
        return "DARK"
    if s < 0.12 and v > 0.78:
        return "TRIM"
    if (hd < 22 or hd > 345) and s > 0.35 and 0.3 < v < 0.85:
        return "BRICK"
    if 18 <= hd <= 48 and s > 0.30 and v < 0.75:
        return "WOOD"
    if s < 0.15 and zmin_face < 0.9:
        return "STONE"
    if s < 0.10 and v < 0.6:
        return "METAL"
    return "SIDING"


def siding_tint(c):
    # cold-night, weathered: desaturate hard, pull toward grey-blue, darken a touch
    h, s, v = colorsys.rgb_to_hsv(*c)
    s *= 0.38
    v = 0.35 + v * 0.5
    r, g, b = colorsys.hsv_to_rgb(h, s, v)
    q = lambda x: int(round(min(1, max(0, x)) * 15)) * 17   # quantise so buildings share few materials
    return "%02x%02x%02x" % (q(r), q(g), q(b))


def build(o, spec):
    out_name, H, yaw = spec
    me = o.data
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_parent_inverse = Matrix.Identity(4)
    o.data.transform(mw)
    o.matrix_basis = Matrix.Identity(4)
    v = np.array([vv.co[:] for vv in me.vertices])
    mn, mx = v.min(0), v.max(0)
    s = H / (mx[2] - mn[2])
    T = Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Scale(s, 4) @ Matrix.Translation(
        (-(mn[0] + mx[0]) / 2, -(mn[1] + mx[1]) / 2, -mn[2]))
    me.transform(T)
    me.update()
    cols = face_colors(me)
    bm = bmesh.new(); bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    uv = bm.loops.layers.uv.new("UV")
    cats = []
    for f in bm.faces:
        c = cols[f.index]
        n = f.normal
        zc = f.calc_center_median().z
        zmin = min(l.vert.co.z for l in f.loops)
        cat = classify(c, n.z, zc, H, zmin)
        if cat == "SIDING":
            cat = "SIDING_" + siding_tint(c)
        cats.append(cat)
        base = cat.split("_")[0]
        t = TILE.get(base, 2.0)
        ax = max(range(3), key=lambda i: abs(n[i]))
        for l in f.loops:
            p = l.vert.co
            if ax == 2:
                l[uv].uv = (p.x / t, p.y / t)
            elif ax == 0:
                l[uv].uv = (p.y / t, p.z / t)
            else:
                l[uv].uv = (p.x / t, p.z / t)
    # merge the many baked-shading siding shades into <=2 wall colours per building (area weighted k-means)
    sid = [(i, c) for i, c in enumerate(cats) if c.startswith("SIDING_")]
    if sid:
        cs = np.array([[int(c[7 + k * 2:9 + k * 2], 16) / 255.0 for k in range(3)] for _, c in sid])
        w = np.array([bm.faces[i].calc_area() for i, _ in sid]) + 1e-6
        k = 2 if len(set(c for _, c in sid)) > 3 else 1
        cent = cs[np.argsort(-w)[:1]]
        if k == 2:
            far = np.argmax(((cs - cent[0]) ** 2).sum(1) * w)
            cent = np.vstack([cent, cs[far]])
        for _ in range(8):
            lab = np.argmin(((cs[:, None, :] - cent[None]) ** 2).sum(2), 1)
            for j in range(len(cent)):
                if (lab == j).any():
                    cent[j] = (cs[lab == j] * w[lab == j, None]).sum(0) / w[lab == j].sum()
        for (i, _), j in zip(sid, lab):
            c = cent[j]
            cats[i] = "SIDING_%02x%02x%02x" % tuple(int(round(x * 255)) for x in c)
    names = sorted(set(cats))
    me.materials.clear()
    for nm in names:
        m = bpy.data.materials.get(nm) or bpy.data.materials.new(nm)
        me.materials.append(m)
    idx = {nm: i for i, nm in enumerate(names)}
    for f, cat in zip(bm.faces, cats):
        f.material_index = idx[cat]
    bm.to_mesh(me); bm.free()
    for ca in list(me.color_attributes):
        me.color_attributes.remove(ca)
    for a in [a for a in me.attributes if a.name == "custom_normal"]:
        me.attributes.remove(a)
    o.name = out_name
    o.parent = None
    hist = {nm: cats.count(nm) for nm in names}
    return hist


def main():
    args = [a for a in sys.argv[sys.argv.index("--") + 1:]] if "--" in sys.argv else sys.argv[1:]
    glb = args[0]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    os.makedirs(OUT, exist_ok=True)
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o.name in KEEP:
            spec = KEEP[o.name]
            hist = build(o, spec)
            # export alone
            bpy.ops.object.select_all(action="DESELECT")
            o.select_set(True)
            bpy.context.view_layer.objects.active = o
            path = os.path.join(OUT, spec[0] + ".glb")
            bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                                      export_materials="PLACEHOLDER" if False else "EXPORT", export_cameras=False,
                                      export_lights=False, export_attributes=False)
            print("EXPORTED", spec[0], len(o.data.polygons), "tris~", hist)


main()
