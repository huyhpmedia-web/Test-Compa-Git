"""Shared Blender (bpy) helpers for the Whiteout boss/creature builds.

Run with the charpipe venv python (needs bpy, numpy, pillow):
    venv/bin/python tools/charpipe/bosses/build_choir.py
Source glbs (MakeHuman bodies built by tools/charpipe/build_characters.py) are read from
SRC_GLB (default: <repo>/assets/characters, override with BOSS_SRC_GLB); generated textures are cached
in BOSS_CACHE (default: $TMPDIR/boss_cache).
"""
import os, sys, math, random, tempfile, json, zlib
import numpy as np
import bpy, bmesh
from mathutils import Vector, Matrix, Euler, Quaternion, noise

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import texgen

REPO = os.path.abspath(os.path.join(HERE, "../../.."))
SRC_GLB = os.environ.get("BOSS_SRC_GLB", os.path.join(REPO, "assets/characters"))
OUT_DIR = os.environ.get("BOSS_OUT", os.path.join(REPO, "assets/enemies"))
CACHE = os.environ.get("BOSS_CACHE", os.path.join(tempfile.gettempdir(), "boss_cache"))
os.makedirs(CACHE, exist_ok=True)

MATS = {}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()


# ----------------------------------------------------------------------------- materials
def _principled(m):
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bs.outputs["BSDF"], out.inputs["Surface"])
    return nt, bs


def make_mat(name, color=(0.5, 0.5, 0.5, 1), tex=None, rough=0.7, metal=0.0, emission=None, emit=0.0,
             alpha=None, vcol=True, spec=0.5, coat=0.0, coat_rough=0.05, sss=0.0, ior=1.45,
             normal=None, normal_strength=1.0, alpha_tex=False, clip=False):
    """Principled material. tex = path of a base colour image (multiplied by vertex colour 'Col' when vcol)."""
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt, bs = _principled(m)
    bs.inputs["Roughness"].default_value = rough
    bs.inputs["Metallic"].default_value = metal
    try:
        bs.inputs["Specular IOR Level"].default_value = spec
        bs.inputs["IOR"].default_value = ior
    except KeyError:
        pass
    if coat > 0:
        bs.inputs["Coat Weight"].default_value = coat
        bs.inputs["Coat Roughness"].default_value = coat_rough
    if sss > 0:
        bs.inputs["Subsurface Weight"].default_value = sss
        bs.inputs["Subsurface Radius"].default_value = (0.8, 0.25, 0.15)
        bs.inputs["Subsurface Scale"].default_value = 0.03
    src = None
    if tex:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(tex, check_existing=True)
        t.image.colorspace_settings.name = "sRGB"
        src = t.outputs["Color"]
        if alpha_tex:
            nt.links.new(t.outputs["Alpha"], bs.inputs["Alpha"])
    if vcol:
        vc = nt.nodes.new("ShaderNodeVertexColor")
        vc.layer_name = "Col"
        if src is not None:
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = 'RGBA'
            mix.blend_type = 'MULTIPLY'
            mix.inputs[0].default_value = 1.0
            nt.links.new(src, mix.inputs[6])
            nt.links.new(vc.outputs["Color"], mix.inputs[7])
            src = mix.outputs[2]
        else:
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = 'RGBA'
            mix.blend_type = 'MULTIPLY'
            mix.inputs[0].default_value = 1.0
            mix.inputs[6].default_value = color
            nt.links.new(vc.outputs["Color"], mix.inputs[7])
            src = mix.outputs[2]
    if src is not None:
        nt.links.new(src, bs.inputs["Base Color"])
    else:
        bs.inputs["Base Color"].default_value = color
    if normal:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(normal, check_existing=True)
        t.image.colorspace_settings.name = "Non-Color"
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = normal_strength
        nt.links.new(t.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bs.inputs["Normal"])
    if emission is not None and emit > 0:
        bs.inputs["Emission Color"].default_value = emission
        bs.inputs["Emission Strength"].default_value = emit
    if alpha is not None and not alpha_tex:
        bs.inputs["Alpha"].default_value = alpha
    if (alpha is not None and alpha < 1.0) or alpha_tex:
        for attr, val in (("blend_method", 'CLIP' if clip else 'BLEND'), ("surface_render_method", 'DITHERED' if clip else 'BLENDED')):
            try:
                setattr(m, attr, val)
            except Exception:
                pass
        if clip:
            try:
                m.alpha_threshold = 0.5
            except Exception:
                pass
    MATS[name] = m
    return m


# ----------------------------------------------------------------------------- generic mesh builders
class MeshBuilder:
    """Accumulates verts/faces/vertex-colours in one bmesh -> one object."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.color.new("Col")

    def _finish_faces(self, faces, color):
        for f in faces:
            for l in f.loops:
                l[self.col] = color
            f.smooth = True

    def add_faces(self, vlists, color=(1, 1, 1, 1), mat_index=0):
        out = []
        for vl in vlists:
            try:
                f = self.bm.faces.new(vl)
            except ValueError:
                continue
            f.material_index = mat_index
            out.append(f)
        self._finish_faces(out, color)
        return out

    def vert(self, p):
        return self.bm.verts.new(Vector(p))

    def build(self, mats=(), link=True, smooth=True):
        me = bpy.data.meshes.new(self.name)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        for m in mats:
            me.materials.append(m)
        ob = bpy.data.objects.new(self.name, me)
        if link:
            bpy.context.scene.collection.objects.link(ob)
        return ob


def orth_basis(d):
    d = Vector(d).normalized()
    a = Vector((0, 0, 1)) if abs(d.z) < 0.95 else Vector((1, 0, 0))
    u = d.cross(a).normalized()
    v = d.cross(u).normalized()
    return u, v, d


def add_crystal(mb, base, direction, length, radius, sides=6, tip=0.22, jitter=0.18, rng=None, color=(1, 1, 1, 1),
                bevel=0.0, mat_index=0, taper=0.85):
    """Hexagonal prism with a pyramid point (irregular, like frost crystals). Returns tip position."""
    rng = rng or random
    u, v, d = orth_basis(direction)
    base = Vector(base)
    n = sides
    ring0, ring1 = [], []
    rot = rng.uniform(0, math.tau)
    for i in range(n):
        a = rot + math.tau * i / n
        r = radius * (1 + rng.uniform(-jitter, jitter))
        off = (u * math.cos(a) + v * math.sin(a))
        ring0.append(mb.vert(base + off * r))
        ring1.append(mb.vert(base + d * length * (1 - tip) + off * r * taper * (1 + rng.uniform(-jitter, jitter) * 0.5)))
    tp = base + d * length + (u * rng.uniform(-1, 1) + v * rng.uniform(-1, 1)) * radius * 0.25
    tv = mb.vert(tp)
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces.append([ring0[i], ring0[j], ring1[j], ring1[i]])
        faces.append([ring1[i], ring1[j], tv])
    faces.append(list(reversed(ring0)))
    mb.add_faces(faces, color, mat_index)
    return tp


def add_tube(mb, pts, radii, sides=8, color=(1, 1, 1, 1), mat_index=0, cap=True, twist=0.0, noise_amp=0.0, seed=0):
    """Swept tube along a polyline (Vector list); radii per point (float or list)."""
    pts = [Vector(p) for p in pts]
    if not isinstance(radii, (list, tuple)):
        radii = [radii] * len(pts)
    rings = []
    prev_u = None
    for k, p in enumerate(pts):
        if k == 0:
            d = pts[1] - pts[0]
        elif k == len(pts) - 1:
            d = pts[-1] - pts[-2]
        else:
            d = pts[k + 1] - pts[k - 1]
        d.normalize()
        if prev_u is None:
            u, v, _ = orth_basis(d)
        else:
            u = (prev_u - d * prev_u.dot(d)).normalized()
            v = d.cross(u).normalized()
        prev_u = u
        ring = []
        for i in range(sides):
            a = math.tau * i / sides + twist * k
            off = u * math.cos(a) + v * math.sin(a)
            r = radii[k]
            if noise_amp:
                r *= 1 + noise_amp * noise.noise(p * 7.0 + Vector((seed, a, 0)))
            ring.append(mb.vert(p + off * r))
        rings.append(ring)
    faces = []
    for k in range(len(rings) - 1):
        for i in range(sides):
            j = (i + 1) % sides
            faces.append([rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]])
    if cap:
        faces.append(list(reversed(rings[0])))
        faces.append(rings[-1])
    mb.add_faces(faces, color, mat_index)
    return rings


def add_blob(mb, center, radii, rot=None, seg=12, rings=8, noise_amp=0.0, seed=0, color=(1, 1, 1, 1), mat_index=0):
    """Noise-displaced ellipsoid."""
    c = Vector(center)
    R = (rot or Matrix.Identity(3))
    vs = []
    for r in range(rings + 1):
        th = math.pi * r / rings
        row = []
        for s in range(seg if 0 < r < rings else 1):
            ph = math.tau * s / seg
            p = Vector((math.sin(th) * math.cos(ph), math.sin(th) * math.sin(ph), math.cos(th)))
            q = Vector((p.x * radii[0], p.y * radii[1], p.z * radii[2]))
            if noise_amp:
                q *= 1 + noise_amp * noise.fractal(p * 1.7 + Vector((seed, seed * 0.7, 0)), 1.0, 2.0, 3)
            row.append(mb.vert(c + R @ q))
        vs.append(row)
    faces = []
    for r in range(rings):
        a, b = vs[r], vs[r + 1]
        for s in range(seg):
            s2 = (s + 1) % seg
            if r == 0:
                faces.append([a[0], b[s2], b[s]])
            elif r == rings - 1:
                faces.append([a[s], a[s2], b[0]])
            else:
                faces.append([a[s], a[s2], b[s2], b[s]])
    mb.add_faces(faces, color, mat_index)


def smooth_noise(co, scale=1.0, seed=0.0, octaves=3):
    return noise.fractal(Vector(co) * scale + Vector((seed, seed * 1.3, seed * 0.7)), 1.0, 2.0, octaves)


# ----------------------------------------------------------------------------- characters
def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def select_only(ob):
    for o in list(bpy.context.view_layer.objects):
        if o is not None:
            o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def delete(ob):
    bpy.data.objects.remove(ob, do_unlink=True)


def src_image(char, mat):
    """Save a material's base colour image to the cache, return the path (or None)."""
    if mat is None or not mat.use_nodes:
        return None
    for n in mat.node_tree.nodes:
        if n.type == 'TEX_IMAGE' and n.image is not None and any(
                l.to_socket.name in ("Base Color", "Color") or l.to_socket.name.startswith("Color") for l in n.outputs["Color"].links):
            ext = "png"
            p = os.path.join(CACHE, "src", f"{char}__{mat.name}.{ext}")
            if not os.path.exists(p):
                os.makedirs(os.path.dirname(p), exist_ok=True)
                img = n.image
                if max(img.size) > 1024:
                    img = img.copy()
                    img.scale(1024, 1024)
                if "hair" in mat.name.lower() and max(img.size) > 512:
                    img = img.copy() if img is n.image else img
                    img.scale(512, 512)
                img.filepath_raw = p
                img.file_format = 'PNG'
                img.save()
            return p
    return None


def mat_base_color(mat):
    try:
        bs = [n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'][0]
        return tuple(bs.inputs["Base Color"].default_value)
    except Exception:
        return (0.5, 0.5, 0.5, 1)


SKIP_ROLES = ("brows", "eyes", "lashes", "boot_shaft", "stethoscope")


class Person:
    """An imported MakeHuman body, posed + deformed + baked to static meshes."""

    def __init__(self, char, tag, seed=1, skin_style=None, cloth_style=None, keep=None, skip=()):
        self.char = char
        self.tag = tag
        self.seed = seed
        self.skin_style = skin_style or {}
        self.cloth_style = cloth_style or {}
        objs = import_glb(os.path.join(SRC_GLB, char + ".glb"))
        self.arm = [o for o in objs if o.type == 'ARMATURE'][0]
        self.parts = []
        for o in objs:
            if o.type == 'MESH' and o.parent == self.arm:
                role = o.name[len(char) + 1:] if o.name.startswith(char) else o.name
                role = role.split(".")[0]
                if role == "eyes":
                    ev = np.array([v.co[:] for v in o.data.vertices])
                    self.eye_c = Vector(ev.mean(0))
                    self.eye_dx = float(np.abs(ev[:, 0]).mean())
                    self.eye_r = float((ev[:, 2].max() - ev[:, 2].min()) * 0.5)
                if role in SKIP_ROLES or role in skip or (keep is not None and role not in keep):
                    delete(o)
                    continue
                o.name = f"{tag}_{role}"
                self.parts.append((role, o))
            elif o.type != 'ARMATURE':
                delete(o)
        self.arm.name = f"{tag}_rig"

    # ---- rest-pose deformations (before skinning) ----
    def vgroup_weights(self, ob, bones):
        idx = [ob.vertex_groups[b].index for b in bones if b in ob.vertex_groups]
        w = np.zeros(len(ob.data.vertices), np.float32)
        for v in ob.data.vertices:
            s = 0.0
            for g in v.groups:
                if g.group in idx:
                    s += g.weight
            w[v.index] = s
        return w

    def bone_head(self, name):
        return Vector(self.arm.data.bones[name].head_local)

    def head_morph(self, stretch=0.0, jaw=0.0, mouth_cut=0.0):
        """Stretch the skull upward, cut the lip seam open and drop the jaw (hinge near the ears)."""
        nk = self.bone_head("neck_01")
        self.stretch = stretch
        self.z0 = nk.z + 0.02
        ez = self.eye_c.z
        self.mouth = Vector((0, self.eye_c.y + 0.01, ez - 0.075))
        self.mouth_z0 = self.mouth.z
        for role, ob in self.parts:
            me = ob.data
            co = np.array([v.co[:] for v in me.vertices], np.float32)
            wh = self.vgroup_weights(ob, ["head"])
            self.last_w = wh
            if role in ("body", "hair"):
                if jaw:
                    self._jaw(co, wh, jaw, role)
            co[:, 2] = self.z0 + (co[:, 2] - self.z0) * (1 + stretch * wh)
            me.vertices.foreach_set("co", co.reshape(-1))
            me.update()
        # the stretch also lifts the mouth/eyes
        k = 1 + stretch
        self.mouth.z = self.z0 + (self.mouth.z - self.z0) * k
        self.eye_c = Vector((0, self.eye_c.y, self.z0 + (self.eye_c.z - self.z0) * k))
        if mouth_cut > 0:
            self._cut_mouth(mouth_cut)

    def _cut_mouth(self, h):
        """delete faces of the closed lip seam (done after morph: coordinates are post-stretch)."""
        ob = dict(self.parts)["body"]
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bm.faces.ensure_lookup_table()
        mz = self.mouth.z - 0.002
        kill = []
        for f in bm.faces:
            c = f.calc_center_median()
            if abs(c.x) < 0.03 and abs(c.z - mz) < h and c.y < self.eye_c.y + 0.045:
                kill.append(f)
        bmesh.ops.delete(bm, geom=kill, context='FACES')
        bm.to_mesh(ob.data)
        bm.free()
        ob.data.update()

    def _jaw(self, co, wh, jaw, role):
        mz = self.mouth_z0
        hy, hz = self.eye_c.y + 0.085, self.eye_c.z - 0.035        # hinge near the ear
        for i in range(len(co)):
            if wh[i] < 0.25:
                continue
            x, y, z = co[i]
            if y > hy + 0.02:
                continue
            s = 1.0 - min(1.0, max(0.0, (z - (mz - 0.003)) / 0.01))
            s *= 1.0 - min(1.0, max(0.0, (abs(x) - 0.04) / 0.045))
            if s <= 0:
                continue
            ang = jaw * s
            c, sn = math.cos(ang), math.sin(ang)
            dy, dz = y - hy, z - hz
            co[i] = (x, hy + dy * c - dz * sn, hz + dy * sn + dz * c)

    def add_eyes(self, mat, scale=1.0):
        """two simple eyeballs skinned to the head bone (the MakeHuman eye meshes are dropped)."""
        mb = MeshBuilder("eyes")
        for sx in (-1, 1):
            add_blob(mb, Vector((sx * self.eye_dx, self.eye_c.y + 0.004, self.eye_c.z)), (self.eye_r * scale,) * 3, seg=8, rings=6)
        ob = mb.build([mat])
        self.add_part(ob, "throat_eyes", "head")
        return ob

    # ---- posing ----
    def rot(self, bone, axis, deg):
        """Rotate a pose bone about armature-space axis ('X','Y','Z' or Vector) at its head."""
        pb = self.arm.pose.bones[bone]
        ax = {"X": Vector((1, 0, 0)), "Y": Vector((0, 1, 0)), "Z": Vector((0, 0, 1))}.get(axis, None) if isinstance(axis, str) else Vector(axis)
        head = self.arm.matrix_world @ pb.head
        R = Matrix.Rotation(math.radians(deg), 4, ax)
        T = Matrix.Translation(pb.head)
        pb.matrix = T @ R @ T.inverted() @ pb.matrix
        bpy.context.view_layer.update()

    def pose(self, spec):
        """spec: list of (bone, axis, deg) applied in order (parents first)."""
        for b, a, d in spec:
            self.rot(b, a, d)

    def add_part(self, ob, role, bone="head"):
        """skin an extra object (e.g. a throat) rigidly to one bone so it follows the pose."""
        ob.vertex_groups.clear()
        vg = ob.vertex_groups.new(name=bone)
        vg.add(list(range(len(ob.data.vertices))), 1.0, 'REPLACE')
        ob.parent = self.arm
        md = ob.modifiers.new("Armature", 'ARMATURE')
        md.object = self.arm
        ob.name = f"{self.tag}_{role}"
        self.parts.append((role, ob))

    # ---- bake ----
    def mark(self, name, bones):
        """store per-vertex summed bone weight as a point attribute `name` (survives evaluation)."""
        for role, ob in self.parts:
            w = self.vgroup_weights(ob, bones)
            me = ob.data
            if name in me.attributes:
                me.attributes.remove(me.attributes[name])
            at = me.attributes.new(name, 'FLOAT', 'POINT')
            at.data.foreach_set("value", w)

    def bake(self, xform=None, select=None, thr=0.5, invert=False, roles=None):
        """Evaluate the armature modifier -> static objects. select = attribute name: keep only faces
        whose verts all have attr >= thr (or < thr when invert)."""
        dg = bpy.context.evaluated_depsgraph_get()
        out = []
        for role, ob in self.parts:
            if roles is not None and role not in roles:
                continue
            ev = ob.evaluated_get(dg)
            me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
            new = bpy.data.objects.new(ob.name + "_b", me)
            bpy.context.scene.collection.objects.link(new)
            if select:
                bm = bmesh.new()
                bm.from_mesh(me)
                lay = bm.verts.layers.float.get(select)
                if lay is not None:
                    bad = [v for v in bm.verts if ((v[lay] < thr) if not invert else (v[lay] >= thr))]
                    bmesh.ops.delete(bm, geom=bad, context='VERTS')
                bm.to_mesh(me)
                bm.free()
            if xform is not None:
                me.transform(xform)
            out.append((role, new, ob))
        return out


def apply_xform(me, M):
    me.transform(M)


def decimate(ob, ratio, collapse_triangulate=True):
    if ratio >= 0.99:
        return
    select_only(ob)
    m = ob.modifiers.new("dec", 'DECIMATE')
    m.ratio = ratio
    m.use_collapse_triangulate = collapse_triangulate
    bpy.ops.object.modifier_apply(modifier="dec")


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def total_tris(objs=None):
    objs = objs or [o for o in bpy.data.objects if o.type == 'MESH']
    return sum(tri_count(o) for o in objs)


def join(objs, name):
    objs = [o for o in objs if o is not None]
    select_only(objs[0])
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def set_vertex_color(ob, fn):
    """fn(co: Vector(world), normal: Vector, index) -> (r,g,b,a); writes layer 'Col' (point domain -> loop)."""
    me = ob.data
    if "Col" not in me.color_attributes:
        me.color_attributes.new("Col", 'BYTE_COLOR', 'CORNER')
    attr = me.color_attributes["Col"]
    M = ob.matrix_world
    vcol = [None] * len(me.vertices)
    for v in me.vertices:
        vcol[v.index] = fn(M @ v.co, (M.to_3x3() @ v.normal).normalized(), v.index)
    data = attr.data
    for li, loop in enumerate(me.loops):
        data[li].color = vcol[loop.vertex_index]
    me.color_attributes.active_color = attr


def ensure_col(ob, color=(1, 1, 1, 1)):
    me = ob.data
    if "Col" not in me.color_attributes:
        a = me.color_attributes.new("Col", 'BYTE_COLOR', 'CORNER')
        for d in a.data:
            d.color = color
    me.color_attributes.active_color = me.color_attributes["Col"]


def shade_smooth(ob):
    for p in ob.data.polygons:
        p.use_smooth = True


def uv_smart(ob, angle=66):
    select_only(ob)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(angle), island_margin=0.01)
    bpy.ops.object.mode_set(mode='OBJECT')


def uv_box(ob, scale=1.0):
    """simple world-scale box projection UVs (tiling textures)."""
    me = ob.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uvl = me.uv_layers.active.data
    M = ob.matrix_world
    for p in me.polygons:
        n = M.to_3x3() @ p.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in p.loop_indices:
            co = M @ me.vertices[me.loops[li].vertex_index].co
            if ax == 0:
                uvl[li].uv = (co.y * scale, co.z * scale)
            elif ax == 1:
                uvl[li].uv = (co.x * scale, co.z * scale)
            else:
                uvl[li].uv = (co.x * scale, co.y * scale)


def metaball_mesh(name, elems, resolution=0.08, threshold=0.6, mat=None):
    """elems: list of (center, radius, stiffness[, (sx,sy,sz)]). Converts a metaball field to a mesh."""
    mb = bpy.data.metaballs.new(name)
    mb.resolution = resolution
    mb.render_resolution = resolution
    mb.threshold = threshold
    ob = bpy.data.objects.new(name, mb)
    bpy.context.scene.collection.objects.link(ob)
    for e in elems:
        el = mb.elements.new(type='ELLIPSOID')
        el.co = Vector(e[0])
        el.radius = e[1]
        el.stiffness = e[2] if len(e) > 2 else 2.0
        if len(e) > 3:
            el.size_x, el.size_y, el.size_z = e[3]
    select_only(ob)
    bpy.ops.object.convert(target='MESH')
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    if mat is not None:
        ob.data.materials.clear()
        ob.data.materials.append(mat)
    return ob


def displace_noise(ob, amp, scale, seed=0.0, octaves=4, along_normal=True, ridged=False):
    me = ob.data
    for v in me.vertices:
        p = v.co
        n = noise.fractal(p * scale + Vector((seed, seed * 1.7, seed * 0.3)), 1.0, 2.1, octaves)
        if ridged:
            n = 1 - abs(n) * 2
        d = n * amp
        v.co = p + (v.normal * d if along_normal else Vector((0, 0, d)))
    me.update()


def remesh_voxel(ob, voxel):
    select_only(ob)
    m = ob.modifiers.new("rm", 'REMESH')
    m.mode = 'VOXEL'
    m.voxel_size = voxel
    bpy.ops.object.modifier_apply(modifier="rm")


def smooth_mesh(ob, iters=2, factor=0.5):
    select_only(ob)
    m = ob.modifiers.new("sm", 'SMOOTH')
    m.iterations = iters
    m.factor = factor
    bpy.ops.object.modifier_apply(modifier="sm")


def origin_to(ob, point):
    """move object origin to world `point` keeping geometry in place."""
    p = Vector(point)
    off = ob.matrix_world.inverted() @ p
    ob.data.transform(Matrix.Translation(-off))
    ob.matrix_world.translation = p


def export(path, objs=None, anims=False):
    for o in list(bpy.context.view_layer.objects):
        if o is not None:
            o.select_set(False)
    for o in (objs or list(bpy.data.objects)):
        o.select_set(True)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', use_selection=True, export_apply=False, export_yup=True,
        export_skins=True, export_animations=anims, export_image_format='WEBP', export_image_quality=82, export_texcoords=True,
        export_normals=True, export_tangents=False, export_materials='EXPORT', export_cameras=False,
        export_lights=False, export_vertex_color='ACTIVE', export_all_vertex_colors=False,
        export_active_vertex_color_when_no_material=True, export_def_bones=False, export_leaf_bone=False)
    tris = total_tris([o for o in (objs or bpy.data.objects) if o.type == 'MESH'])
    print(f"EXPORTED {path} {os.path.getsize(path)//1024} KB, {tris} tris")
    return tris


def empty(name, loc=(0, 0, 0), parent=None):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = 'PLAIN_AXES'
    e.location = Vector(loc)
    bpy.context.scene.collection.objects.link(e)
    if parent:
        e.parent = parent
    return e


# ----------------------------------------------------------------------------- person finishing
_TEXCACHE = {}


def person_material(p, role, orig_mat):
    """dead-skin / frozen-cloth material for one part of a Person (cached by source + style)."""
    st = p.skin_style if role == "body" else p.cloth_style
    key = (p.char, orig_mat.name, p.seed if role == "body" else st.get("variant", 0), json.dumps(st, sort_keys=True))
    if key in _TEXCACHE:
        return _TEXCACHE[key]
    src = src_image(p.char, orig_mat)
    tag = f"{p.char}_{orig_mat.name}_{zlib.crc32(repr(key).encode()) % 99999}"
    if role == "body":
        out = os.path.join(CACHE, "tex", f"skin_{tag}.jpg")
        if src and not os.path.exists(out):
            texgen.dead_skin(src, out, seed=p.seed, size=st.get("size", 1024), frost=st.get("frost", 0.45), blood=st.get("blood", 0.25),
                             livid=st.get("livid", 0.6), bruise=st.get("bruise", 0.5))
        m = make_mat("skin_" + tag, tex=out if src else None, color=(0.7, 0.72, 0.8, 1), rough=st.get("rough", 0.5), spec=0.55, sss=0.1)
    elif role == "hair":
        m = make_mat("hair_" + tag, tex=src, color=(0.3, 0.3, 0.33, 1), rough=0.6, alpha_tex=True, clip=True) if src else make_mat("hair_flat", color=(0.15, 0.15, 0.17, 1))
    else:
        flat = st.get("flat")
        if isinstance(flat, dict):
            flat = flat.get(role, flat.get("default"))
        elif flat is not None and role in ("jeans", "trousers", "pants"):
            flat = tuple(c * 0.55 for c in flat)
        elif flat is not None and role in ("boots", "shoes"):
            flat = (0.07, 0.06, 0.06)
        if src:
            out = os.path.join(CACHE, "tex", f"cloth_{tag}_{role}.jpg")
            if not os.path.exists(out):
                texgen.frozen_cloth(src, out, seed=p.seed + 5, size=st.get("size", 512), frost=st.get("frost", 0.5), dirt=st.get("dirt", 0.45),
                                    blood=st.get("blood", 0.2), desat=st.get("desat", 0.35), mul=st.get("mul", (1, 1, 1)), flat=flat)
            m = make_mat("cloth_" + tag, tex=out, rough=0.85, spec=0.3)
        elif "lamp" in orig_mat.name.lower():
            m = make_mat("glow_lamp", color=(1, 0.85, 0.5, 1), rough=0.3, emission=(1.0, 0.8, 0.45, 1), emit=8.0)
        else:
            c = list(mat_base_color(orig_mat))
            m = make_mat("plain_" + tag, color=(c[0] * 0.8, c[1] * 0.8, c[2] * 0.85, 1), rough=0.6, spec=0.4)
    _TEXCACHE[key] = m
    return m


def finalize_person(p, M, dec=None, vcol_fn=None, select=None, thr=0.5, invert=False, roles=None, name=None, free=True):
    """bake -> transform by M (Matrix 4x4) -> frozen materials -> decimate -> vertex colours.
    Returns {role: object}. `dec` = {role: ratio}.  free=False keeps the rig for further bakes."""
    baked = p.bake(xform=None, select=select, thr=thr, invert=invert, roles=roles)
    res = {}
    nm = name or p.tag
    for role, new, ob in baked:
        orig = ob.data.materials[0] if ob.data.materials else None
        new.data.materials.clear()
        if orig is not None and role.startswith("throat"):
            new.data.materials.append(orig)
        elif orig is not None:
            new.data.materials.append(person_material(p, role, orig))
        new.data.transform(M)
        new.matrix_world = Matrix.Identity(4)
        if len(new.data.polygons) == 0:
            delete(new)
            continue
        res[role] = new
    if free:
        for role, ob in p.parts:
            delete(ob)
        delete(p.arm)
    for role, ob in list(res.items()):
        r = (dec or {}).get(role, (dec or {}).get("default", 1.0))
        if r < 1:
            decimate(ob, r)
        ob.name = f"{nm}_{role}"
        shade_smooth(ob)
        ensure_col(ob)
        if vcol_fn:
            set_vertex_color(ob, vcol_fn)
    return res
