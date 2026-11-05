"""Blender helpers for the Whiteout weapon pipeline (run with the charpipe venv's python: bpy 5.0).
Weapon frame (Blender): forward = +Y (muzzle), up = +Z, right = +X.  glTF export maps this to Godot: forward = -Z, up = +Y.
Marker empties carry the *hand bone frame*: marker X = thumb/pinky axis of the hand bone (right hand: toward thumb, left hand:
toward pinky), marker Y = along the fingers, marker Z = palm normal. Origin = palm contact point."""
import bpy, bmesh, math, os
from mathutils import Vector, Matrix

TEX = os.environ.get("WTEX", "")

_mats = {}

def reset():
    _mats.clear()
    bpy.ops.wm.read_factory_settings(use_empty=True)

def tex_mat(name, tex=None, color=None, rough=0.5, metal=0.0, uv=0.25):
    key = name
    if key in _mats: return _mats[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type != 'OUTPUT_MATERIAL': nt.nodes.remove(n)
    out = nt.nodes['Material Output']
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    if tex:
        def img(suffix, nonc):
            im = bpy.data.images.load(os.path.join(TEX, f"{tex}_{suffix}.jpg"))
            im.colorspace_settings.name = 'Non-Color' if nonc else 'sRGB'
            n = nt.nodes.new('ShaderNodeTexImage'); n.image = im
            return n
        c = img('c', False); nt.links.new(c.outputs['Color'], bsdf.inputs['Base Color'])
        o = img('orm', True)
        sep = nt.nodes.new('ShaderNodeSeparateColor'); nt.links.new(o.outputs['Color'], sep.inputs['Color'])
        nt.links.new(sep.outputs['Green'], bsdf.inputs['Roughness']); nt.links.new(sep.outputs['Blue'], bsdf.inputs['Metallic'])
        n = img('n', True)
        nm = nt.nodes.new('ShaderNodeNormalMap'); nt.links.new(n.outputs['Color'], nm.inputs['Color'])
        nt.links.new(nm.outputs['Normal'], bsdf.inputs['Normal'])
    else:
        bsdf.inputs['Base Color'].default_value = color
        bsdf.inputs['Roughness'].default_value = rough
        bsdf.inputs['Metallic'].default_value = metal
    _mats[key] = m
    return m

def _finish(obj, mat, bevel=0.0015, uv=0.3, smooth=True, segs=2):
    if mat: obj.data.materials.append(mat)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    if uv:
        bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.cube_project(cube_size=uv)
        bpy.ops.object.mode_set(mode='OBJECT')
    if bevel > 0:
        b = obj.modifiers.new('bev', 'BEVEL'); b.width = bevel; b.segments = segs; b.limit_method = 'ANGLE'; b.angle_limit = math.radians(35)
    if smooth:
        try: bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
        except Exception: bpy.ops.object.shade_smooth()
    obj.select_set(False)
    return obj

def new_obj(name, bm_or_mesh, parent=None):
    me = bpy.data.meshes.new(name)
    if isinstance(bm_or_mesh, bmesh.types.BMesh):
        bm_or_mesh.to_mesh(me); bm_or_mesh.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    if parent: o.parent = parent
    return o

def box(name, center, size, mat=None, parent=None, bevel=0.0015, taper=None, uv=0.3):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0]; v.co.y *= size[1]; v.co.z *= size[2]
    bm.normal_update()
    o = new_obj(name, bm, parent); o.location = center
    return _finish(o, mat, bevel, uv)

def cyl(name, p0, p1, r0, r1=None, mat=None, parent=None, seg=28, bevel=0.0008, cap=True, uv=0.3):
    """Cylinder/cone between two points (Blender coords)."""
    r1 = r0 if r1 is None else r1
    p0 = Vector(p0); p1 = Vector(p1)
    d = p1 - p0; L = d.length
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=cap, segments=seg, radius1=r0, radius2=r1, depth=L)
    o = new_obj(name, bm, parent)
    o.location = (p0 + p1) * 0.5
    o.rotation_mode = 'QUATERNION'
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d)
    return _finish(o, mat, bevel, uv, segs=2)

def profile(name, pts, thick, xc=0.0, mat=None, parent=None, bevel=0.002, uv=0.3):
    """Extrude a side profile (list of (y,z)) along X by `thick` centred at xc."""
    bm = bmesh.new()
    vs = [bm.verts.new((xc - thick / 2, y, z)) for y, z in pts]
    f = bm.faces.new(vs)
    r = bmesh.ops.extrude_face_region(bm, geom=[f])
    vv = [e for e in r['geom'] if isinstance(e, bmesh.types.BMVert)]
    for v in vv: v.co.x += thick
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    o = new_obj(name, bm, parent)
    return _finish(o, mat, bevel, uv)

def torus_arc(name, center, r_major, r_minor, a0, a1, mat=None, parent=None, axis='X'):
    """Trigger-guard style arc in the Y-Z plane (a0/a1 degrees, 0 = +Y, 90 = +Z)."""
    bm = bmesh.new()
    n = 18; ns = 10
    ring = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        cy, cz = math.cos(a) * r_major, math.sin(a) * r_major
        row = []
        for j in range(ns):
            t = j / ns * math.tau
            # circle in plane perpendicular to the arc tangent: radial (cy,cz) and X
            rad = r_minor * math.cos(t); x = r_minor * math.sin(t)
            row.append(bm.verts.new((x, (cy + math.cos(a) * rad), (cz + math.sin(a) * rad))))
        ring.append(row)
    for i in range(n):
        for j in range(ns):
            bm.faces.new((ring[i][j], ring[i][(j + 1) % ns], ring[i + 1][(j + 1) % ns], ring[i + 1][j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    o = new_obj(name, bm, parent); o.location = center
    return _finish(o, mat, 0, 0.3)

def empty(name, loc, parent=None, axes=None):
    """Marker empty. axes=(X,Y,Z) hand-frame vectors in weapon space (optional)."""
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = 'ARROWS'; e.empty_display_size = 0.02
    bpy.context.collection.objects.link(e)
    if parent: e.parent = parent
    if axes:
        X, Y, Z = [Vector(a).normalized() for a in axes]
        m = Matrix((X, Y, Z)).transposed()
        e.rotation_mode = 'QUATERNION'; e.rotation_quaternion = m.to_quaternion()
    e.location = loc
    return e

def export(path, root):
    bpy.ops.object.select_all(action='DESELECT')
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', export_apply=True, export_yup=True,
                              export_image_format='JPEG', export_jpeg_quality=85, export_cameras=False, export_lights=False,
                              use_selection=False, export_extras=False)
