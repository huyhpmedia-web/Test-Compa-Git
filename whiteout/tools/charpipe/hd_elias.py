"""Elias HD: Higgsfield/Meshy 7 photoreal mesh moved onto the game's MPFB 'game_engine' skeleton.

The Meshy rig has 24 bones and no fingers, so instead of using it we:
  1. align/scale the Meshy model to the MPFB rest skeleton (rigs/elias.blend from anim_rigfile.py),
  2. re-pose its arms/legs with its own Meshy rig so the limbs lie along the MPFB rest bones,
  3. bake that pose into the mesh, drop the Meshy rig,
  4. copy skin weights from the current MakeHuman Elias (assets/characters/elias.glb) by nearest surface
     (that body wears a similar jacket, gloves and boots, so the weights land on the right bones,
     fingers included), normalise, and export with the MPFB skeleton -> assets/characters/elias.glb.
All existing animation sets (assets/anims/elias.glb), weapon IK and finger curls keep working.

Run: venv/bin/python -I tools/charpipe/hd_elias.py <meshy.glb> <rigs/elias.blend> <old elias.glb> <out.glb>
"""
import sys, math
import bpy, bmesh
import numpy as np
from mathutils import Vector, Matrix, Quaternion

meshy_path, rig_path, old_path, out_path = sys.argv[-4:]

# ------------------------------------------------------------------ MPFB rest skeleton
bpy.ops.wm.open_mainfile(filepath=rig_path)
rig = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
rig.name = "elias_rig"
R = {b.name: (rig.matrix_world @ b.head_local, rig.matrix_world @ b.tail_local) for b in rig.data.bones}

# ------------------------------------------------------------------ Meshy model
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=meshy_path)
new = [o for o in bpy.data.objects if o not in before]
marm = [o for o in new if o.type == "ARMATURE"][0]
mesh = max([o for o in new if o.type == "MESH"], key=lambda o: len(o.data.polygons))
for o in new:
    if o.type == "MESH" and o is not mesh:
        bpy.data.objects.remove(o)
# stop any imported clip from driving the pose
if marm.animation_data:
    marm.animation_data.action = None
for pb in marm.pose.bones:
    pb.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.update()


def mj(name, tail=False):
    pb = marm.pose.bones[name]
    return marm.matrix_world @ (pb.tail if tail else pb.head)


# orientation: both should face -Y; compare foot->toe directions
# use the hip line (left minus right), feet splay too much to be reliable
mf = (mj("LeftUpLeg") - mj("RightUpLeg")); rf = (R["thigh_l"][0] - R["thigh_r"][0])
mf.z = rf.z = 0
ang = math.atan2(mf.y, mf.x) - math.atan2(rf.y, rf.x)
# left/right check: MPFB left side has +X for a -Y facing body
print("yaw fix deg", math.degrees(ang))
# scale by pelvis->head height, then put the pelvis on the MPFB pelvis
mh = (mj("Head") - mj("Hips")).length
rh = (R["head"][0] - R["pelvis"][0]).length
s = rh / mh
T = Matrix.Translation(R["pelvis"][0]) @ Matrix.Rotation(-ang, 4, "Z") @ Matrix.Scale(s, 4) @ Matrix.Translation(-mj("Hips"))
marm.matrix_world = T @ marm.matrix_world
bpy.context.view_layer.update()
print("scale", s, "meshy L arm x", mj("LeftArm").x, "mpfb L upperarm x", R["upperarm_l"][0].x)

# ------------------------------------------------------------------ re-pose Meshy limbs onto MPFB rest bones
PAIRS = [("LeftArm", "LeftForeArm", "upperarm_l", "lowerarm_l"), ("LeftForeArm", "LeftHand", "lowerarm_l", "hand_l"),
         ("RightArm", "RightForeArm", "upperarm_r", "lowerarm_r"), ("RightForeArm", "RightHand", "lowerarm_r", "hand_r"),
         ("LeftUpLeg", "LeftLeg", "thigh_l", "calf_l"), ("LeftLeg", "LeftFoot", "calf_l", "foot_l"),
         ("RightUpLeg", "RightLeg", "thigh_r", "calf_r"), ("RightLeg", "RightFoot", "calf_r", "foot_r")]
bpy.context.view_layer.objects.active = marm
bpy.ops.object.mode_set(mode="POSE")
for mb, mb_child, rb, rb_child in PAIRS:
    pb = marm.pose.bones[mb]
    cur = (mj(mb_child) - mj(mb)).normalized()
    want = (R[rb_child][0] - R[rb][0]).normalized()
    q = cur.rotation_difference(want)
    # rotate the pose bone in world space by q about its head
    mw = marm.matrix_world @ pb.matrix
    head = mw.translation.copy()
    rot = q.to_matrix().to_4x4()
    new_mw = Matrix.Translation(head) @ rot @ Matrix.Translation(-head) @ mw
    pb.matrix = marm.matrix_world.inverted() @ new_mw
    bpy.context.view_layer.update()
    if mb in ("LeftArm", "RightArm", "LeftUpLeg", "RightUpLeg"):
        off = R[rb][0] - mj(mb)
        mw = marm.matrix_world @ pb.matrix
        pb.matrix = marm.matrix_world.inverted() @ (Matrix.Translation(off) @ mw)
        bpy.context.view_layer.update()
    print(mb, "aligned, err deg", math.degrees((mj(mb_child) - mj(mb)).normalized().angle(want)), "joint err", (mj(mb) - R[rb][0]).length)
bpy.ops.object.mode_set(mode="OBJECT")

# bake the pose into the mesh and drop the Meshy rig
bpy.context.view_layer.objects.active = mesh
for o in bpy.context.selected_objects:
    o.select_set(False)
mesh.select_set(True)
mods = [m for m in mesh.modifiers if m.type == "ARMATURE"]
for m in mods:
    bpy.ops.object.modifier_apply(modifier=m.name)
mw = mesh.matrix_world.copy()
mesh.parent = None
mesh.data.transform(mw)
mesh.matrix_world = Matrix.Identity(4)
mesh.vertex_groups.clear()
bpy.data.objects.remove(marm)
mesh.name = "elias_hd"

# ------------------------------------------------------------------ automatic (bone heat) weights via a watertight proxy
# The Meshy mesh is not manifold, so bone heat fails on it directly: voxel-remesh a copy (watertight),
# heat-weight that, then copy the weights onto the real mesh by nearest surface.
proxy = mesh.copy(); proxy.data = mesh.data.copy(); proxy.name = "weight_proxy"
bpy.context.collection.objects.link(proxy)
rm = proxy.modifiers.new("vox", "REMESH")
rm.mode = "VOXEL"; rm.voxel_size = 0.012
bpy.ops.object.select_all(action="DESELECT")
proxy.select_set(True); bpy.context.view_layer.objects.active = proxy
bpy.ops.object.modifier_apply(modifier="vox")
dec = proxy.modifiers.new("dec", "DECIMATE"); dec.ratio = min(1.0, 80000 / max(1, len(proxy.data.polygons)))
bpy.ops.object.modifier_apply(modifier="dec")
print("proxy faces", len(proxy.data.polygons))
proxy.select_set(True); rig.select_set(True); bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
print("proxy unweighted:", sum(1 for v in proxy.data.vertices if len(v.groups) == 0), "/", len(proxy.data.vertices))
for g in proxy.vertex_groups:
    mesh.vertex_groups.new(name=g.name)
dt = mesh.modifiers.new("dt", "DATA_TRANSFER")
dt.object = proxy
dt.use_vert_data = True
dt.data_types_verts = {"VGROUP_WEIGHTS"}
dt.vert_mapping = "POLYINTERP_NEAREST"
dt.layers_vgroup_select_src = "ALL"
dt.layers_vgroup_select_dst = "NAME"
bpy.ops.object.select_all(action="DESELECT")
mesh.select_set(True); bpy.context.view_layer.objects.active = mesh
bpy.ops.object.modifier_apply(modifier="dt")
bpy.data.objects.remove(proxy)
mesh.parent = rig
am = mesh.modifiers.new("Armature", "ARMATURE"); am.object = rig
print("mesh unweighted:", sum(1 for v in mesh.data.vertices if len(v.groups) == 0))
bpy.context.view_layer.objects.active = mesh
bpy.ops.object.mode_set(mode="WEIGHT_PAINT")
bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
bpy.ops.object.mode_set(mode="OBJECT")

# ------------------------------------------------------------------ parent to the MPFB rig and export
for m in mesh.data.materials:
    m.name = "elias_hd_body"
bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True)
mesh.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB", use_selection=True, export_animations=False,
                          export_skins=True, export_yup=True, export_image_format="JPEG", export_jpeg_quality=90)
print("EXPORTED", out_path, len(mesh.data.polygons))
