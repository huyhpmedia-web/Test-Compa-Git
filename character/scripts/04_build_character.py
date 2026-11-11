"""Stage 4 -- assemble the character and save character.blend.

Body (fitted MakeHuman mesh) + rig + pose, photo-projected skin, eyeballs, hair, outfit,
environment, sun/sky lighting and three cameras that reproduce the reference photos
(timeline frames 1 = front, 2 = profile, 3 = close-up; cameras are bound to markers).
"""
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402
import blcore  # noqa: E402
import charlib  # noqa: E402
import eyes as eyelib  # noqa: E402
import mhlib  # noqa: E402

ROOT = charlib.ROOT
SHOTS = [("front", 1), ("profile", 2), ("closeup", 3)]
CAM_PITCH = 3.0          # the front photo's camera looks up by about this much (degrees)
NECK_LEAN = 6.0          # forward lean of the lower neck (degrees)
NECK_LEAN_PROFILE = 14.0


def skin_material(albedo_path):
    mat = bpy.data.materials.new("Skin")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(albedo_path)
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Subsurface Weight"].default_value = 0.32
    bsdf.inputs["Subsurface Radius"].default_value = (1.0, 0.36, 0.20)
    bsdf.inputs["Subsurface Scale"].default_value = 0.0045
    bsdf.inputs["Roughness"].default_value = 0.44
    bsdf.inputs["Specular IOR Level"].default_value = 0.42
    # fine pores
    tc = nt.nodes.new("ShaderNodeTexCoord")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 1400.0
    noise.inputs["Detail"].default_value = 3.0
    nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.06
    bump.inputs["Distance"].default_value = 0.0004
    nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def parent_to_bone(obj, rig, bone):
    """Bone-parent an object that was authored in the rest pose (keeps its rest placement)."""
    bpy.context.view_layer.update()
    world = obj.matrix_world.copy()
    obj.parent = rig
    obj.parent_type = 'BONE'
    obj.parent_bone = bone
    pb = rig.pose.bones[bone]
    rest = rig.matrix_world @ pb.bone.matrix_local
    # bone parenting is relative to the bone tail
    tail = Matrix.Translation((0, pb.bone.length, 0))
    obj.matrix_parent_inverse = (rest @ tail).inverted()
    obj.matrix_basis = world
    return obj


def setup_world(scene):
    world = bpy.data.worlds.new("Sky")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.74, 0.83, 1.0, 1.0)
    bg.inputs[1].default_value = 1.15
    sun = bpy.data.lights.new("Sun", 'SUN')
    sun.energy = 3.4
    sun.angle = math.radians(9.0)
    sun.color = (1.0, 0.96, 0.9)
    so = bpy.data.objects.new("Sun", sun)
    blcore.link(so, blcore.collection("Lights"))
    to_sun = Vector((0.55, -0.50, 0.67)).normalized()      # from her front-left, high
    so.matrix_world = to_sun.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    return so


def main():
    fit = charlib.load_fit()
    base = mhlib.BaseMesh()
    scene = blcore.reset_scene()
    c_char = blcore.collection("Character")
    c_cam = blcore.collection("Cameras")
    v = fit["verts"]

    # ---- everything is authored in the rest pose first
    body, rig = charlib.build_body(base, v, col=c_char)
    body.data.materials.append(skin_material(os.path.join(ROOT, "textures", "skin_albedo.png")))
    centers, radii = {}, {}
    for side, grp in (("L", "helper-l-eye"), ("R", "helper-r-eye")):
        p = v[base.group_indices(grp)]
        centers[side] = p.mean(0)
        radii[side] = 0.0122
    eyeballs = eyelib.build_eyes(centers, radii, col=c_char)
    extra = {}
    for modname in ("hairgen", "outfit"):
        try:
            mod = __import__(modname)
        except ImportError:
            continue
        extra[modname] = mod.build(base=base, fit=fit, body=body, rig=rig, col=c_char)
    for ob in eyeballs.values():
        parent_to_bone(ob, rig, "head")
    for ob in extra.get("hairgen", {}).get("head_objects", []):
        parent_to_bone(ob, rig, "head")

    # ---- poses: arms down; the head pose is keyed per shot (frame) so that each photo camera,
    #      which is rigidly attached to the head, ends up level with the world
    cams_rest = charlib.photo_cameras(fit)
    charlib.pose_arms_down(rig)
    target = bpy.data.objects.new("EyeTarget", None)
    target.empty_display_size = 0.03
    blcore.link(target, c_cam)
    scene.frame_start, scene.frame_end = 1, 3
    neck = ("neck01", "neck02", "neck03", "head")
    R_side = np.array([[0.0, 0.0, -1.0], [-1.0, 0.0, 0.0], [0.0, 1.0, 0.0]])   # level camera looking along +X
    M_head = None
    for name, frame in SHOTS:
        for b in neck:
            rig.pose.bones[b].matrix_basis = Matrix.Identity(4)
        if name == "profile":
            lean, rot = NECK_LEAN_PROFILE, R_side @ cams_rest["profile"][:3, :3].T
        else:
            lean, rot = NECK_LEAN, charlib.level_rotation(cams_rest["front"], CAM_PITCH)
        if lean:
            blcore.rotate_bone_world(rig, "neck01", (1, 0, 0), -lean)     # lean forward
            blcore.rotate_bone_world(rig, "head", (1, 0, 0), lean)        # keep the head level
        charlib.rotate_head(rig, rot)
        for b in neck:
            rig.pose.bones[b].keyframe_insert("rotation_quaternion", frame=frame)
            rig.pose.bones[b].keyframe_insert("location", frame=frame)
        M = charlib.rest_to_pose(rig, "head")
        if name == "front":
            M_head = M
        world = M @ cams_rest[name]
        cam = charlib.add_camera("Cam_" + name, world, col=c_cam)
        eye_mid = M[:3, :3] @ ((centers["L"] + centers["R"]) * 0.5) + M[:3, 3]
        cam.data.dof.use_dof = True
        cam.data.dof.focus_distance = float(np.linalg.norm(world[:3, 3] - eye_mid))
        cam.data.dof.aperture_fstop = 8.0 if name != "closeup" else 5.6
        m = scene.timeline_markers.new(name, frame=frame)
        m.camera = cam
        look = world[:3, 3] if name != "profile" else eye_mid + (M[:3, :3] @ np.array([0.0, -1.0, 0.0])) * 3.0
        target.location = Vector(look.tolist())
        target.keyframe_insert("location", frame=frame)
    scene.frame_set(1)
    for ob in eyeballs.values():
        con = ob.constraints.new('DAMPED_TRACK')
        con.target = target
        con.track_axis = 'TRACK_NEGATIVE_Y'
    scene.camera = bpy.data.objects["Cam_front"]

    for modname in ("outfit_posed", "env"):
        try:
            mod = __import__(modname)
        except ImportError:
            continue
        mod.build(base=base, fit=fit, body=body, rig=rig, M_head=M_head)
    setup_world(scene)

    blcore.setup_cycles(scene, samples=160, res=(charlib.RES, charlib.RES))
    scene.view_settings.view_transform = 'AgX'
    scene.frame_set(1)
    bpy.ops.file.pack_all()
    out = os.path.join(ROOT, "character.blend")
    bpy.ops.wm.save_as_mainfile(filepath=out, compress=True)
    print("saved", out)


if __name__ == "__main__":
    main()
