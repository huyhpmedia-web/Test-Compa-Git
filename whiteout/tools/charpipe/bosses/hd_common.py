"""Shared helpers for the HD (Tripo H3.1) boss builds: orient / scale / split / preview / export.

Run with the charpipe venv python (needs bpy, numpy, pillow):
    venv/bin/python tools/charpipe/bosses/hd_<name>.py
Raw Tripo glbs (never committed, ~20 MB each) are read from HD_RAW (default: $HD_SCRATCH/tripo_raw).
Coordinates: Blender is Z-up; the glTF exporter maps Blender -Y -> glTF +Z (Godot's forward), so the
creature's FRONT is built facing Blender -Y. The raw Tripo meshes face +X, so we rotate -90 deg about Z.
"""
import os, sys, math
import numpy as np
import bpy, bmesh
from mathutils import Vector, Matrix
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "../../.."))
SCRATCH = os.environ.get("HD_SCRATCH", "/tmp/claude-0/-home-user-Test-Compa-Git/b7d788c3-cd16-57ba-98fb-70cb388fdafd/scratchpad")
RAW = os.environ.get("HD_RAW", os.path.join(SCRATCH, "tripo_raw"))
OUT_DIR = os.environ.get("HD_OUT", os.path.join(REPO, "assets/enemies"))
PREV = os.path.join(SCRATCH, "hd", "prev")
os.makedirs(PREV, exist_ok=True)


def load_raw(name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(RAW, name + "_tripo.glb"))
    obj = [o for o in bpy.data.objects if o.type == "MESH"][0]
    obj.parent = None
    obj.matrix_world = Matrix.Identity(4)
    obj.name = name
    return obj


def orient(obj, scale, rotz_deg=-90.0, center="bbox", base=0.0):
    """rotate about Z, scale uniformly, put the base on z=0 and the xy centre (bbox centre or given (x,y)) at 0."""
    M = Matrix.Scale(scale, 4) @ Matrix.Rotation(math.radians(rotz_deg), 4, "Z")
    obj.data.transform(M)
    v = verts(obj)
    mn, mx = v.min(0), v.max(0)
    if center == "base":   # centre of the lowest 6% of the model (the footprint)
        lo = v[v[:, 2] < mn[2] + 0.06 * (mx[2] - mn[2])]
        cx, cy = (lo[:, 0].min() + lo[:, 0].max()) / 2, (lo[:, 1].min() + lo[:, 1].max()) / 2
    elif center == "bbox":
        cx, cy = (mn[0] + mx[0]) / 2, (mn[1] + mx[1]) / 2
    else:
        cx, cy = center
    obj.data.transform(Matrix.Translation((-cx, -cy, -mn[2] + base)))
    obj.data.update()
    return obj


def verts(obj):
    me = obj.data
    a = np.empty(len(me.vertices) * 3, dtype=np.float32)
    me.vertices.foreach_get("co", a)
    return a.reshape(-1, 3)


def faces(obj):
    """(n,3) triangle vertex indices (the raw meshes are triangulated)."""
    me = obj.data
    me.calc_loop_triangles()
    a = np.empty(len(me.loop_triangles) * 3, dtype=np.int32)
    me.loop_triangles.foreach_get("vertices", a)
    return a.reshape(-1, 3)


def vert_uv(obj):
    me = obj.data
    uv = np.empty(len(me.loops) * 2, dtype=np.float32)
    me.uv_layers[0].data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    vi = np.empty(len(me.loops), dtype=np.int32)
    me.loops.foreach_get("vertex_index", vi)
    out = np.zeros((len(me.vertices), 2), dtype=np.float32)
    out[vi] = uv
    return out


def base_image(obj):
    for m in obj.data.materials:
        for n in m.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image and n.image.colorspace_settings.name == "sRGB":
                return n.image
    return None


_prev_tex = {}


def vert_colors(obj, size=512):
    key = obj.name
    img = base_image(obj)
    if img is None:
        return np.full((len(obj.data.vertices), 3), 0.6, dtype=np.float32)
    if key not in _prev_tex:
        w, h = img.size
        px = np.empty(w * h * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        im = Image.fromarray((np.clip(px.reshape(h, w, 4)[::-1, :, :3], 0, 1) ** (1 / 2.2) * 255).astype(np.uint8)).resize((size, size), Image.BILINEAR)
        _prev_tex[key] = np.asarray(im, dtype=np.float32) / 255.0
    tex = _prev_tex[key]
    uv = vert_uv(obj)
    x = np.clip((uv[:, 0] * (size - 1)).astype(int), 0, size - 1)
    y = np.clip(((1 - uv[:, 1]) * (size - 1)).astype(int), 0, size - 1)
    return tex[y, x]


def downscale_images(size):
    for img in list(bpy.data.images):
        if img.size[0] > size or img.size[1] > size:
            img.scale(size, size)


# ----------------------------------------------------------------------------- preview (point-splat renders)
PALETTE = [(230, 60, 60), (60, 200, 80), (70, 120, 240), (240, 200, 40), (200, 70, 220), (40, 210, 210), (250, 140, 30),
           (150, 150, 150), (120, 220, 120), (240, 130, 160), (110, 80, 200), (200, 200, 120)]


def preview(obj_or_pts, name, view="front", labels=None, cols=None, marks=None, px=900, grid=0.5, box=None, splat=4):
    """Render a point-splat preview of the vertex cloud: textured (or label-coloured if `labels`).
    view: front (from -Y), back, side (from +X), top. marks: [(label, (x,y,z)), ...] drawn as crosses."""
    if isinstance(obj_or_pts, np.ndarray):
        P = obj_or_pts
        C = cols if cols is not None else np.full((len(P), 3), 0.7, dtype=np.float32)
    else:
        P = verts(obj_or_pts)
        C = vert_colors(obj_or_pts) if cols is None else cols
    if labels is not None:
        C = np.array([PALETTE[int(l) % len(PALETTE)] for l in labels], dtype=np.float32) / 255.0 * 0.85 + C * 0.15
    if view == "front":
        sx, sy, dp = P[:, 0], P[:, 2], -P[:, 1]
        dp = P[:, 1]   # farther = larger y -> draw far first
    elif view == "back":
        sx, sy, dp = -P[:, 0], P[:, 2], -P[:, 1]
    elif view == "side":
        sx, sy, dp = P[:, 1], P[:, 2], -P[:, 0]
    else:  # top: screen x = x, screen y = -y (front = bottom of the image)
        sx, sy, dp = P[:, 0], -P[:, 1], P[:, 2]
    if box is None:
        x0, x1, y0, y1 = sx.min() - 0.1, sx.max() + 0.1, sy.min() - 0.1, sy.max() + 0.1
    else:
        x0, x1, y0, y1 = box
    sc = px / max(x1 - x0, y1 - y0)
    W, H = int((x1 - x0) * sc), int((y1 - y0) * sc)
    img = np.zeros((H, W, 3), dtype=np.float32) + 0.07
    order = np.argsort(-dp) if view != "top" else np.argsort(dp)
    ix = ((sx[order] - x0) * sc).astype(int)
    iy = (H - 1 - ((sy[order] - y0) * sc)).astype(int)
    co = C[order]
    for dx in range(splat):
        for dy in range(splat):
            m = (ix + dx >= 0) & (ix + dx < W) & (iy + dy >= 0) & (iy + dy < H)
            img[iy[m] + dy, ix[m] + dx] = co[m]
    im = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    if grid:
        g = math.floor(x0 / grid) * grid
        while g < x1:
            X = (g - x0) * sc
            d.line([(X, 0), (X, H)], fill=(60, 60, 90), width=1)
            d.text((X + 2, 2), "%.1f" % g, fill=(150, 150, 200))
            g += grid
        g = math.floor(y0 / grid) * grid
        while g < y1:
            Y = H - 1 - (g - y0) * sc
            d.line([(0, Y), (W, Y)], fill=(60, 60, 90), width=1)
            d.text((2, Y - 10), "%.1f" % g, fill=(150, 150, 200))
            g += grid
    for lab, p in (marks or []):
        p = np.array(p, dtype=np.float32)
        if view == "front":
            a, b = p[0], p[2]
        elif view == "back":
            a, b = -p[0], p[2]
        elif view == "side":
            a, b = p[1], p[2]
        else:
            a, b = p[0], -p[1]
        X, Y = (a - x0) * sc, H - 1 - (b - y0) * sc
        d.line([(X - 8, Y), (X + 8, Y)], fill=(255, 255, 0), width=2)
        d.line([(X, Y - 8), (X, Y + 8)], fill=(255, 255, 0), width=2)
        d.text((X + 6, Y + 4), str(lab), fill=(255, 255, 0))
    path = os.path.join(PREV, name + ".png")
    im.save(path)
    return path


# ----------------------------------------------------------------------------- splitting
def tri_face_labels(obj, vlabel):
    """label of each polygon = the label most voted by its vertices (ties: first vertex)."""
    me = obj.data
    out = np.empty(len(me.polygons), dtype=np.int32)
    for i, p in enumerate(me.polygons):
        ls = [int(vlabel[v]) for v in p.vertices]
        out[i] = max(set(ls), key=ls.count) if len(set(ls)) < len(ls) else ls[0]
    return out


def polygon_centers(obj):
    me = obj.data
    v = verts(obj)
    out = np.empty((len(me.polygons), 3), dtype=np.float32)
    for i, p in enumerate(me.polygons):
        out[i] = v[list(p.vertices)].mean(0)
    return out


def extract(obj, face_mask, name):
    """new mesh object with the polygons where face_mask is True (keeps uv / material)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    kill = [f for f in bm.faces if not face_mask[f.index]]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in obj.data.materials:
        me.materials.append(m)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    return o


def set_origin(obj, point):
    """move the object's origin to `point` (world) without moving the geometry."""
    p = Vector(point)
    obj.data.transform(Matrix.Translation(-p))
    obj.location = obj.location + p
    obj.data.update()


def parent_keep(child, parent):
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()


def empty(name, loc, parent=None, size=0.1):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = size
    e.location = Vector(loc)
    bpy.context.scene.collection.objects.link(e)
    if parent is not None:
        parent_keep(e, parent)
    return e


def tri_count(objs):
    return sum(len(o.data.polygons) for o in objs if o.type == "MESH")


def export(path, objs, fmt="JPEG", quality=88):
    bpy.ops.object.select_all(action="DESELECT")
    sel = []

    def add(o):
        sel.append(o)
        for c in o.children:
            add(c)
    for o in objs:
        add(o)
    for o in sel:
        o.select_set(True)
    bpy.context.view_layer.objects.active = sel[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_image_format=fmt,
                              export_jpeg_quality=quality, export_yup=True, export_apply=False, export_materials="EXPORT",
                              export_cameras=False, export_lights=False)
    print("EXPORTED", path, round(os.path.getsize(path) / 1e6, 2), "MB", tri_count(sel), "polys")


# ----------------------------------------------------------------------------- welded graph / geodesics
def weld(v, tol=2e-5):
    """vertex -> welded id (UV-seam duplicates share an id). Returns (ids, n_unique)."""
    q = np.round(v / tol).astype(np.int64)
    _, inv = np.unique(q, axis=0, return_inverse=True)
    return inv.reshape(-1), int(inv.max()) + 1


def geodesic(v, F, sources, wid=None):
    """multi-source Dijkstra over the welded triangle graph. sources: list of lists of vertex indices (one list per source
    group). Returns (dist per vertex, group id per vertex)."""
    import heapq
    if wid is None:
        wid, _ = weld(v)
    n = int(wid.max()) + 1
    pos = np.zeros((n, 3), dtype=np.float64)
    pos[wid] = v
    adj = [[] for _ in range(n)]
    seen = set()
    for t in F:
        a, b, c = int(wid[t[0]]), int(wid[t[1]]), int(wid[t[2]])
        for p, q in ((a, b), (b, c), (c, a)):
            if p == q:
                continue
            k = (p, q) if p < q else (q, p)
            if k in seen:
                continue
            seen.add(k)
            d = float(np.linalg.norm(pos[p] - pos[q]))
            adj[p].append((q, d))
            adj[q].append((p, d))
    dist = np.full(n, np.inf)
    grp = np.full(n, -1, dtype=np.int32)
    h = []
    for gi, vs in enumerate(sources):
        for vi in vs:
            w = int(wid[vi])
            if dist[w] > 0:
                dist[w] = 0.0
                grp[w] = gi
                heapq.heappush(h, (0.0, w))
    while h:
        d, u = heapq.heappop(h)
        if d > dist[u]:
            continue
        for q, w in adj[u]:
            nd = d + w
            if nd < dist[q]:
                dist[q] = nd
                grp[q] = grp[u]
                heapq.heappush(h, (nd, q))
    return dist[wid], grp[wid]


# ----------------------------------------------------------------------------- PBR tuning (wet blood / glossy ice)
def _img(obj, prefix):
    for m in obj.data.materials:
        for n in m.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image and n.image.name.startswith(prefix):
                return n.image
    return None


def _blur(mask, r):
    im = Image.fromarray((np.clip(mask, 0, 1) * 255).astype(np.uint8)).filter(__import__("PIL.ImageFilter", fromlist=["x"]).GaussianBlur(r))
    return np.asarray(im, dtype=np.float32) / 255.0


def tune_pbr(obj, blood=0.16, ice=0.5, rename="flesh_hd", metal_cap=0.15):
    """Edit the roughness (ORM green) from the albedo: dark-red regions (blood) become wet/glossy, bright bluish regions
    (ice / frost) get glossier too; metallic is capped. Also renames the material so enemy_glb.gd treats it as flesh."""
    col, orm = _img(obj, "Color"), _img(obj, "ORM")
    if col is None or orm is None:
        return
    w, h = col.size
    c = np.empty(w * h * 4, dtype=np.float32)
    col.pixels.foreach_get(c)
    c = c.reshape(h, w, 4)[:, :, :3]
    o = np.empty(orm.size[0] * orm.size[1] * 4, dtype=np.float32)
    orm.pixels.foreach_get(o)
    o = o.reshape(orm.size[1], orm.size[0], 4)
    if (orm.size[0], orm.size[1]) != (w, h):
        return
    r, g, b = c[:, :, 0], c[:, :, 1], c[:, :, 2]
    lum = 0.3 * r + 0.55 * g + 0.15 * b
    bl = ((r > g * 1.7) & (r > b * 1.4) & (lum < 0.22)).astype(np.float32)
    bl = _blur(bl, 3)
    ic = ((b > r * 1.04) & (lum > 0.28)).astype(np.float32)
    ic = _blur(ic, 4)
    rough = o[:, :, 1]
    rough = rough * (1 - bl) + np.minimum(rough, blood) * bl
    rough = rough * (1 - ic * 0.6) + rough * ic * 0.6 * ice
    o[:, :, 1] = np.clip(rough, 0.04, 1.0)
    o[:, :, 2] = np.minimum(o[:, :, 2], metal_cap)
    orm.pixels.foreach_set(o.reshape(-1))
    orm.update()
    print("tune_pbr: blood %.1f%% ice %.1f%%" % (bl.mean() * 100, ic.mean() * 100))
    if rename:
        for m in obj.data.materials:
            m.name = rename


def glow_material(name, color=(0.45, 0.9, 1.0), strength=4.0, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bs = nt.nodes["Principled BSDF"]
    bs.inputs["Base Color"].default_value = (color[0] * 0.3, color[1] * 0.3, color[2] * 0.3, 1)
    bs.inputs["Emission Color"].default_value = (color[0], color[1], color[2], 1)
    bs.inputs["Emission Strength"].default_value = strength
    bs.inputs["Alpha"].default_value = alpha
    bs.inputs["Roughness"].default_value = 0.4
    return m


def blob(name, loc, scale, mat, parent=None, seg=16, rings=10):
    """small UV-sphere ellipsoid (overlay glows, markers)."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=1.0)
    bm.to_mesh(me)
    bm.free()
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.scale = Vector(scale)
    o.location = Vector(loc)
    if parent is not None:
        parent_keep(o, parent)
        o.matrix_parent_inverse = parent.matrix_world.inverted()
    return o


def sphere_mask(v, c, r):
    """ellipsoid test: c centre, r (rx, ry, rz)."""
    d = (v - np.array(c)) / np.array(r)
    return (d * d).sum(1) <= 1.0


def front_y(v, x, z, rad=0.1):
    """y of the front-most (smallest y) vertex within `rad` of (x, z) in the front projection."""
    m = ((v[:, 0] - x) ** 2 + (v[:, 2] - z) ** 2) < rad * rad
    return float(np.percentile(v[m, 1], 12)) if m.any() else float(v[:, 1].mean())
