"""Blender (bpy) helpers shared by the build scripts."""
import math
import os
import bpy
import numpy as np
from mathutils import Matrix, Vector

import mhlib


# --------------------------------------------------------------------------- scene
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = 1.0
    return scene


def collection(name, parent=None):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        (parent or bpy.context.scene.collection).children.link(col)
    return col


def link(obj, col=None):
    (col or bpy.context.scene.collection).objects.link(obj)
    return obj


def remove_object(name):
    o = bpy.data.objects.get(name)
    if o is not None:
        data = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if data is not None and data.users == 0:
            try:
                type_coll = {bpy.types.Mesh: bpy.data.meshes, bpy.types.Curve: bpy.data.curves,
                             bpy.types.Armature: bpy.data.armatures}.get(type(data))
                if type_coll is not None:
                    type_coll.remove(data)
            except Exception:
                pass


def set_active(obj):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


# --------------------------------------------------------------------------- mesh
def mesh_from_arrays(name, verts, faces, uvs=None, face_uvs=None, smooth=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    if uvs is not None and face_uvs is not None:
        layer = me.uv_layers.new(name="UVMap")
        flat = np.array([uvs[i] for fu in face_uvs for i in fu], dtype=np.float32).reshape(-1)
        layer.data.foreach_set("uv", flat)
    if smooth:
        me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    me.update()
    return me


def make_body_object(base, verts_bl, name="Body", col=None):
    """Skin mesh only (vertices 0..N_BODY-1 keep their MakeHuman indices)."""
    fidx = base.body_faces()
    faces = [base.faces[i] for i in fidx]
    fuvs = [base.face_uvs[i] for i in fidx]
    me = mesh_from_arrays(name + "_Mesh", verts_bl[:mhlib.N_BODY], faces, base.uvs, fuvs)
    obj = bpy.data.objects.new(name, me)
    link(obj, col)
    return obj


def get_coords(obj_or_mesh):
    me = obj_or_mesh.data if hasattr(obj_or_mesh, "data") else obj_or_mesh
    co = np.empty(len(me.vertices) * 3, dtype=np.float64)
    me.vertices.foreach_get("co", co)
    return co.reshape(-1, 3)


def set_coords(obj_or_mesh, co):
    me = obj_or_mesh.data if hasattr(obj_or_mesh, "data") else obj_or_mesh
    me.vertices.foreach_set("co", np.asarray(co, dtype=np.float64).reshape(-1))
    me.update()


def evaluated_coords(obj):
    """World-space vertex positions after modifiers (armature etc)."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    co = np.empty(len(me.vertices) * 3, dtype=np.float64)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    mw = np.array(obj.matrix_world)
    out = co @ mw[:3, :3].T + mw[:3, 3]
    ev.to_mesh_clear()
    return out


def evaluated_tris(obj):
    """(world-space vertices, triangle index array) of the evaluated (modified) mesh."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    me.calc_loop_triangles()
    co = np.empty(len(me.vertices) * 3, dtype=np.float64)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    tri = np.empty(len(me.loop_triangles) * 3, dtype=np.int32)
    me.loop_triangles.foreach_get("vertices", tri)
    tri = tri.reshape(-1, 3).copy()
    mw = np.array(obj.matrix_world)
    out = co @ mw[:3, :3].T + mw[:3, 3]
    ev.to_mesh_clear()
    return out, tri


# --------------------------------------------------------------------------- rig
def make_armature(bones, name="Rig", col=None):
    arm = bpy.data.armatures.new(name + "_Armature")
    obj = bpy.data.objects.new(name, arm)
    link(obj, col)
    set_active(obj)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = {}
    for bname, b in bones.items():
        e = arm.edit_bones.new(bname)
        e.head = Vector(b["head"])
        e.tail = Vector(b["tail"])
        if (e.tail - e.head).length < 1e-5:
            e.tail = e.head + Vector((0, 0, 0.01))
        e.roll = b["roll"]
        eb[bname] = e
    for bname, b in bones.items():
        if b["parent"] and b["parent"] in eb:
            eb[bname].parent = eb[b["parent"]]
    bpy.ops.object.mode_set(mode='OBJECT')
    arm.display_type = 'STICK'
    return obj


def apply_weights(obj, weights, n_valid=None):
    n_valid = n_valid or len(obj.data.vertices)
    for bname, pairs in weights.items():
        vg = obj.vertex_groups.get(bname) or obj.vertex_groups.new(name=bname)
        for vi, w in pairs:
            if vi < n_valid and w > 0:
                vg.add([vi], w, 'REPLACE')


def bind(obj, rig, name="Armature"):
    m = obj.modifiers.get(name) or obj.modifiers.new(name, 'ARMATURE')
    m.object = rig
    obj.parent = rig
    return m


def rotate_bone_world(rig, bone_name, axis, angle_deg):
    """Rotate a pose bone about a world-space axis through its head."""
    bpy.context.view_layer.update()
    pb = rig.pose.bones[bone_name]
    mw = rig.matrix_world
    head_w = mw @ pb.head
    rot = Matrix.Rotation(math.radians(angle_deg), 4, Vector(axis).normalized())
    world = Matrix.Translation(head_w) @ rot @ Matrix.Translation(-head_w) @ (mw @ pb.matrix)
    pb.matrix = mw.inverted() @ world
    bpy.context.view_layer.update()


def aim_bone_world(rig, bone_name, direction, fraction=1.0):
    """Swing a pose bone so its head->tail axis points along a world direction."""
    bpy.context.view_layer.update()
    pb = rig.pose.bones[bone_name]
    mw = rig.matrix_world
    cur = ((mw @ pb.tail) - (mw @ pb.head)).normalized()
    tgt = Vector(direction).normalized()
    axis = cur.cross(tgt)
    if axis.length < 1e-8:
        return
    ang = math.degrees(cur.angle(tgt)) * fraction
    rotate_bone_world(rig, bone_name, axis, ang)


# --------------------------------------------------------------------------- render
def setup_cycles(scene, samples=64, res=(1024, 1024), denoise=True, transparent=False):
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = samples
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.adaptive_threshold = 0.02
    scene.cycles.use_denoising = denoise
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = transparent
    scene.render.image_settings.file_format = 'PNG'
    scene.render.threads_mode = 'AUTO'
    scene.render.use_persistent_data = False


def render_to(scene, path):
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


def look_at_camera(name, location, target, lens=85.0, sensor=36.0, col=None):
    cam = bpy.data.cameras.get(name) or bpy.data.cameras.new(name)
    cam.lens = lens
    cam.sensor_width = sensor
    obj = bpy.data.objects.get(name)
    if obj is None:
        obj = bpy.data.objects.new(name, cam)
        link(obj, col)
    loc = Vector(location)
    direction = Vector(target) - loc
    obj.matrix_world = Matrix.Translation(loc) @ direction.to_track_quat('-Z', 'Y').to_matrix().to_4x4()
    return obj


def simple_material(name, color, rough=0.5, sss=0.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    if sss:
        bsdf.inputs["Subsurface Weight"].default_value = sss
    return mat
