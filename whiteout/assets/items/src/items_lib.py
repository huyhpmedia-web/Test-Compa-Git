import bpy, bmesh, math, os, sys
from mathutils import Vector, Matrix, Euler

S = "/tmp/claude-0/-home-user-Test-Compa-Git/b7d788c3-cd16-57ba-98fb-70cb388fdafd/scratchpad"
RAW = S + "/sf_raw/"
OUT = "/home/user/Test-Compa-Git/whiteout/assets/items/models/"
TEX = "/home/user/Test-Compa-Git/whiteout/textures/"


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def meshes(objs=None):
    return [o for o in (objs or bpy.context.scene.objects) if o.type == "MESH"]


def sel(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    if objs:
        bpy.context.view_layer.objects.active = objs[0]


def flatten(objs):
    """flatten hierarchy: bake world transforms into meshes, drop non-mesh objects"""
    ms = [o for o in objs if o.type == "MESH"]
    for o in ms:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    sel(ms)
    # remove shape keys/modifiers (armature) to be safe
    for o in ms:
        o.modifiers.clear() if False else None
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in list(objs):
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    return ms


def import_glb(name, keep=None):
    path = RAW + name + ".glb"
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.context.scene.objects if o not in before]
    ms = flatten(new)
    if keep:
        kept = []
        for o in list(ms):
            if keep(o):
                kept.append(o)
            else:
                bpy.data.objects.remove(o, do_unlink=True)
        ms = kept
    return ms


def join(objs, name):
    objs = [o for o in objs if o.name in bpy.data.objects]
    sel(objs)
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    return o


def bbox(objs):
    mn = Vector((1e9,) * 3)
    mx = Vector((-1e9,) * 3)
    for o in objs:
        for v in o.bound_box:
            w = o.matrix_world @ Vector(v)
            for i in range(3):
                mn[i] = min(mn[i], w[i])
                mx[i] = max(mx[i], w[i])
    return mn, mx


def rot(objs, deg_xyz):
    e = Euler([math.radians(a) for a in deg_xyz], "XYZ")
    m = e.to_matrix().to_4x4()
    for o in objs:
        o.matrix_world = m @ o.matrix_world
    sel(objs)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def move(objs, v):
    for o in objs:
        o.location += Vector(v)
    sel(objs)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def scale_all(objs, f):
    for o in objs:
        o.matrix_world = Matrix.Diagonal((f, f, f, 1.0)) @ o.matrix_world
    sel(objs)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def fit_max(objs, meters):
    mn, mx = bbox(objs)
    d = max(mx - mn)
    f = meters / d
    scale_all(objs, f)
    return f


def fit_axis(objs, axis, meters):
    mn, mx = bbox(objs)
    d = (mx - mn)[axis]
    f = meters / d
    scale_all(objs, f)


def center(objs):
    mn, mx = bbox(objs)
    c = (mn + mx) * 0.5
    move(objs, -c)


def tris(o):
    me = o.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def decimate(o, target):
    sel([o])
    bpy.context.view_layer.objects.active = o
    t = tris(o)
    if t <= target:
        return
    # triangulate first
    m = o.modifiers.new("tri", "TRIANGULATE")
    bpy.ops.object.modifier_apply(modifier=m.name)
    t = tris(o)
    m = o.modifiers.new("dec", "DECIMATE")
    m.ratio = max(0.02, target / t)
    m.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=m.name)


def shrink_images(maxs=1024):
    for im in bpy.data.images:
        if im.size[0] == 0:
            continue
        w, h = im.size
        if max(w, h) > maxs:
            f = maxs / max(w, h)
            im.scale(max(1, int(w * f)), max(1, int(h * f)))


def img(path):
    return bpy.data.images.load(path, check_existing=True)


def mat_pbr(name, albedo=None, color=(0.5, 0.5, 0.5, 1), rough=None, normal=None, rough_val=0.5, metal=0.0, use_tex_dir=None):
    """Image-based PBR (no mapping/mix nodes so glTF export keeps it). albedo/rough/normal are absolute paths."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bs.outputs[0], out.inputs[0])
    bs.inputs["Metallic"].default_value = metal
    bs.inputs["Roughness"].default_value = rough_val
    bs.inputs["Base Color"].default_value = color

    def tex(path, nonc=False):
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = img(path)
        if nonc:
            n.image.colorspace_settings.name = "Non-Color"
        return n

    if albedo:
        nt.links.new(tex(albedo).outputs[0], bs.inputs["Base Color"])
    if rough:
        nt.links.new(tex(rough, True).outputs[0], bs.inputs["Roughness"])
    if normal:
        t = tex(normal, True)
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs[0].default_value = 0.8
        nt.links.new(t.outputs[0], nm.inputs["Color"])
        nt.links.new(nm.outputs[0], bs.inputs["Normal"])
    return m


def box_uv(o, size=0.1):
    """cube-project UVs so tiled textures have sensible texel density (size = metres per tile)"""
    sel([o])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.cube_project(cube_size=size)
    bpy.ops.object.mode_set(mode="OBJECT")


def new_obj(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for l in me.uv_layers:
        l.name = "UVMap"
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o


def cyl(name, r, h, seg=32, loc=(0, 0, 0), axis="Z", r2=None, mat=None):
    bm = bmesh.new()
    bm.loops.layers.uv.verify()
    bmesh.ops.create_cone(bm, cap_ends=True, calc_uvs=True, segments=seg, radius1=r, radius2=(r if r2 is None else r2), depth=h)
    o = new_obj(name, bm)
    if axis == "X":
        o.rotation_euler = (0, math.radians(90), 0)
    elif axis == "Y":
        o.rotation_euler = (math.radians(90), 0, 0)
    o.location = loc
    if mat:
        o.data.materials.append(mat)
    bpy.context.view_layer.update()
    return o


def box(name, sx, sy, sz, loc=(0, 0, 0), mat=None, bevel=0.0):
    bm = bmesh.new()
    bm.loops.layers.uv.verify()
    bmesh.ops.create_cube(bm, size=1.0, calc_uvs=True)
    for v in bm.verts:
        v.co.x *= sx
        v.co.y *= sy
        v.co.z *= sz
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=2, affect="EDGES")
    o = new_obj(name, bm)
    o.location = loc
    if mat:
        o.data.materials.append(mat)
    return o


def sphere(name, r, loc=(0, 0, 0), mat=None, seg=24, rings=16, sx=1, sy=1, sz=1):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=r)
    for v in bm.verts:
        v.co.x *= sx
        v.co.y *= sy
        v.co.z *= sz
    o = new_obj(name, bm)
    o.location = loc
    if mat:
        o.data.materials.append(mat)
    return o


def torus(name, R, r, loc=(0, 0, 0), mat=None, rotx=0, maj=48, mnr=12):
    bm = bmesh.new()
    verts = []
    for i in range(maj):
        a = 2 * math.pi * i / maj
        ring = []
        for j in range(mnr):
            b = 2 * math.pi * j / mnr
            x = (R + r * math.cos(b)) * math.cos(a)
            y = (R + r * math.cos(b)) * math.sin(a)
            z = r * math.sin(b)
            ring.append(bm.verts.new((x, y, z)))
        verts.append(ring)
    for i in range(maj):
        for j in range(mnr):
            bm.faces.new((verts[i][j], verts[(i + 1) % maj][j], verts[(i + 1) % maj][(j + 1) % mnr], verts[i][(j + 1) % mnr]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = new_obj(name, bm)
    o.location = loc
    o.rotation_euler = (math.radians(rotx), 0, 0)
    if mat:
        o.data.materials.append(mat)
    return o


def curve_tube(name, pts, radius, mat=None, res=6, bevel_res=4):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = bevel_res
    cu.resolution_u = res
    cu.use_fill_caps = True
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(pts) - 1)
    for i, p in enumerate(pts):
        bp = sp.bezier_points[i]
        bp.co = p
        bp.handle_left_type = "AUTO"
        bp.handle_right_type = "AUTO"
    o = bpy.data.objects.new(name, cu)
    bpy.context.scene.collection.objects.link(o)
    if mat:
        cu.materials.append(mat)
    sel([o])
    bpy.ops.object.convert(target="MESH")
    return bpy.context.view_layer.objects.active


def shade_smooth(o):
    for p in o.data.polygons:
        p.use_smooth = True


def export(id_, objs, tri_target=8000):
    objs = [o for o in objs if o.name in bpy.data.objects]
    o = join(objs, id_)
    decimate(o, tri_target)
    shrink_images(1024)
    sel([o])
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=OUT + id_ + ".glb",
        export_format="GLB",
        use_selection=True,
        export_image_format="JPEG",
        export_jpeg_quality=85,
        export_apply=True,
        export_yup=True,
    )
    mn, mx = bbox([o])
    print("EXPORT", id_, "tris=%d" % tris(o), "dims(m)=%.3f x %.3f x %.3f" % tuple(mx - mn), "size=%dKB" % (os.path.getsize(OUT + id_ + ".glb") // 1024))


def inspect(name):
    ms = import_glb(name)
    mn, mx = bbox(ms)
    print("INSPECT", name, "meshes=%d" % len(ms), "tris=%d" % sum(tris(o) for o in ms), "dim=%.3f %.3f %.3f" % tuple(mx - mn), "mats=%s" % [m.name for o in ms for m in o.data.materials][:8])
    for o in ms:
        print("   ", o.name, "tris=%d" % tris(o), "dim=%.3f %.3f %.3f" % tuple(o.dimensions))


def planar_uv(o, w, h, flip_v=False):
    me = o.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers.active
    for p in me.polygons:
        for li in p.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            u = co.x / w + 0.5
            v = co.y / h + 0.5
            uv.data[li].uv = (u, (1 - v) if flip_v else v)
