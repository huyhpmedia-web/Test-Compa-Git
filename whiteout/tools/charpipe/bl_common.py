"""Blender-side helpers (run inside bpy): meshes, armature, materials."""
import os, math
import numpy as np
import bpy, bmesh
from mathutils import Vector, Matrix, Quaternion
import mh_lib as mh


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)


def make_mesh(name, verts, faces, uv=None, uv_faces=None, collection=None):
    """verts (N,3) blender coords. faces: list of vertex-index lists. uv (M,2) + per-face uv index lists."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [list(f) for f in faces])
    me.update()
    if uv is not None and len(uv):
        layer = me.uv_layers.new(name="UVMap")
        data = layer.data
        k = 0
        for f, tf in zip(me.polygons, uv_faces):
            for j, li in enumerate(f.loop_indices):
                t = tf[j]
                data[li].uv = (uv[t][0], uv[t][1]) if t >= 0 else (0, 0)
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    (collection or bpy.context.scene.collection).objects.link(ob)
    return ob


def set_weights(ob, W, bone_names, min_w=0.01):
    """W: (nverts, nbones) dense; keeps top-4 influences, renormalised."""
    for b in bone_names:
        ob.vertex_groups.new(name=b)
    W = np.array(W)
    top = np.argsort(-W, axis=1)[:, :4]
    for vi in range(W.shape[0]):
        row = W[vi]
        idx = top[vi]
        tot = row[idx].sum()
        if tot <= 1e-6:
            continue
        for bi in idx:
            w = row[bi] / tot
            if w >= min_w:
                ob.vertex_groups[bone_names[bi]].add([vi], float(w), 'REPLACE')


def build_armature(name, rig, joint_pos_fn):
    """rig: dict from rig.json. joint_pos_fn(spec)->np.array xyz in Blender coords."""
    arm = bpy.data.armatures.new(name)
    ob = bpy.data.objects.new(name, arm)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    order = []
    def add(b):
        if b in order: return
        p = rig[b]["parent"]
        if p: add(p)
        order.append(b)
    for b in rig: add(b)
    for b in order:
        r = rig[b]
        eb = arm.edit_bones.new(b)
        eb.head = Vector(joint_pos_fn(r["head"]))
        eb.tail = Vector(joint_pos_fn(r["tail"]))
        if (eb.tail - eb.head).length < 1e-4:
            eb.tail = eb.head + Vector((0, 0, 0.02))
        eb.roll = r["roll"]
        if r["parent"]:
            eb.parent = arm.edit_bones[r["parent"]]
    bpy.ops.object.mode_set(mode='OBJECT')
    return ob, order


def tex_image(path, colorspace="sRGB", max_size=None):
    img = bpy.data.images.load(path, check_existing=True)
    img.colorspace_settings.name = colorspace
    if max_size and (img.size[0] > max_size or img.size[1] > max_size):
        img.scale(max_size, max_size)
    return img


def make_material(name, color=(1, 1, 1, 1), base=None, normal=None, rough=0.85, metal=0.0,
                  alpha_tex=False, emission=None, emission_strength=1.0, normal_strength=1.0,
                  spec=0.3, max_size=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bs.outputs["BSDF"], out.inputs["Surface"])
    bs.inputs["Roughness"].default_value = rough
    bs.inputs["Metallic"].default_value = metal
    try:
        bs.inputs["Specular IOR Level"].default_value = spec
    except KeyError:
        pass
    bs.inputs["Base Color"].default_value = color
    if base is not None:
        t = nt.nodes.new("ShaderNodeTexImage"); t.image = base
        if color != (1, 1, 1, 1):
            mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = 'RGBA'; mix.blend_type = 'MULTIPLY'
            mix.inputs[0].default_value = 1.0
            nt.links.new(t.outputs["Color"], mix.inputs[6])
            mix.inputs[7].default_value = color
            nt.links.new(mix.outputs[2], bs.inputs["Base Color"])
        else:
            nt.links.new(t.outputs["Color"], bs.inputs["Base Color"])
        if alpha_tex:
            nt.links.new(t.outputs["Alpha"], bs.inputs["Alpha"])
    if normal is not None:
        t = nt.nodes.new("ShaderNodeTexImage"); t.image = normal
        nm = nt.nodes.new("ShaderNodeNormalMap"); nm.inputs["Strength"].default_value = normal_strength
        nt.links.new(t.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bs.inputs["Normal"])
    if emission is not None:
        bs.inputs["Emission Color"].default_value = emission
        bs.inputs["Emission Strength"].default_value = emission_strength
    if alpha_tex:
        try: m.blend_method = 'BLEND'
        except Exception: pass
    return m


def parent_to_armature(ob, arm_ob):
    ob.parent = arm_ob
    mod = ob.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm_ob


def fill_small_holes(ob, max_extent=0.06):
    """close small boundary loops (holes between hair cards / crown gaps) with ngons that reuse a neighbouring face's UV,
    so no scalp shows through. Loops bigger than max_extent (hairline, neck opening) are left alone."""
    import bmesh
    me = ob.data
    bm = bmesh.new(); bm.from_mesh(me)
    uvl = bm.loops.layers.uv.active
    bm.edges.ensure_lookup_table()
    bnd = [e for e in bm.edges if e.is_boundary]
    seen = set(); made = 0
    for e0 in bnd:
        if e0.index in seen:
            continue
        # walk the loop
        loop_edges = []; stack = [e0]
        while stack:
            e = stack.pop()
            if e.index in seen:
                continue
            seen.add(e.index); loop_edges.append(e)
            for v in e.verts:
                for e2 in v.link_edges:
                    if e2.is_boundary and e2.index not in seen:
                        stack.append(e2)
        verts = list({v for e in loop_edges for v in e.verts})
        if len(verts) < 3 or len(verts) > 40:
            continue
        co = np.array([v.co[:] for v in verts])
        if (co.max(0) - co.min(0)).max() > max_extent:
            continue
        try:
            res = bmesh.ops.holes_fill(bm, edges=loop_edges, sides=len(verts))
        except Exception:
            continue
        for f in res["faces"]:
            for l in f.loops:
                # borrow the uv of an adjacent real face at this vertex
                for lf in l.vert.link_loops:
                    if lf.face is not f:
                        l[uvl].uv = lf[uvl].uv
                        break
            f.smooth = True
        made += len(res["faces"])
    bm.to_mesh(me); bm.free(); me.update()
    print(f"[hair] filled {made} hole faces in {ob.name}")
