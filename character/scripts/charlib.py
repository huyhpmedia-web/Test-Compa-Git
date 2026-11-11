"""Shared character-building helpers: fitted body + rig, pose, photo cameras."""
import math
import os

import bpy
import numpy as np
from mathutils import Matrix, Vector

import blcore
import fitlib
import mhlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
B = os.path.join(ROOT, "build")
RES = 1254
LENS = 85.0


def load_fit():
    return dict(np.load(os.path.join(ROOT, "data", "fit_head.npz")))


def profile_camera(fit):
    """Camera (rest head frame) that reproduces the side photo: looks along +X from her right."""
    s, R, t = float(fit["profile_s"]), fit["profile_R"], fit["profile_t"]
    th = math.atan2(R[1, 0], R[0, 0])
    c, sn = math.cos(th), math.sin(th)
    a0, u0 = (R @ np.array([RES * 0.5, -RES * 0.5])) * s + t       # model (a, u) of the image centre
    d = fitlib.focal_px(LENS, RES) * s                              # metres
    M = np.eye(4)
    M[:3, 0] = (0.0, -c, sn)       # image right  -> anterior, rotated by the head pitch
    M[:3, 1] = (0.0, sn, c)        # image up
    M[:3, 2] = (-1.0, 0.0, 0.0)    # towards the camera
    M[:3, 3] = (-d, -a0, u0)
    return M


def photo_cameras(fit):
    return {"closeup": np.array(fit["cam_closeup"]), "front": np.array(fit["cam_front"]),
            "profile": profile_camera(fit)}


def build_body(base, verts, name="Body", col=None, subdiv=(1, 2)):
    body = blcore.make_body_object(base, verts, name=name, col=col)
    bones, weights = mhlib.load_rig(base, verts)
    rig = blcore.make_armature(bones, name="Rig", col=col)
    blcore.apply_weights(body, weights, mhlib.N_BODY)
    blcore.bind(body, rig)
    sub = body.modifiers.new("Subdiv", 'SUBSURF')
    sub.levels, sub.render_levels = subdiv
    return body, rig


def rest_to_pose(rig, bone_name):
    """4x4 world transform that carries rest-pose points rigidly attached to a bone to the pose."""
    bpy.context.view_layer.update()
    pb = rig.pose.bones[bone_name]
    mw = rig.matrix_world
    return np.array(mw @ pb.matrix @ pb.bone.matrix_local.inverted() @ mw.inverted())


def pose_arms_down(rig, abduct_deg=9.0, forward_deg=4.0, shoulder_frac=0.22):
    for side, sx in (("L", 1.0), ("R", -1.0)):
        a, f = math.radians(abduct_deg), math.radians(forward_deg)
        target = Vector((sx * math.sin(a), -math.sin(f), -math.cos(a) * math.cos(f)))
        blcore.aim_bone_world(rig, f"shoulder01.{side}", target, fraction=shoulder_frac)
        blcore.aim_bone_world(rig, f"upperarm01.{side}", target)
        low = Vector((sx * math.sin(a * 0.6), -math.sin(f + math.radians(8)), -1.0))
        blcore.aim_bone_world(rig, f"lowerarm01.{side}", low)


def rotate_head(rig, rot, fractions=(("neck01", 0.2), ("neck02", 0.2), ("neck03", 0.2), ("head", 0.4))):
    """Distribute a world-space rotation (3x3) of the head over the neck chain."""
    q = Matrix(np.asarray(rot).tolist()).to_quaternion()
    axis, angle = q.to_axis_angle()
    if abs(angle) < 1e-6:
        return
    for name, frac in fractions:
        blcore.rotate_bone_world(rig, name, axis, math.degrees(angle) * frac)


def level_rotation(cam_rest, pitch_deg=0.0):
    """Rotation that turns the fitted (rest head frame) photo camera into a level camera that
    looks at the character from the front (+Y direction), pitched up by pitch_deg."""
    p = math.radians(pitch_deg)
    fwd = np.array([0.0, math.cos(p), math.sin(p)])
    right = np.array([1.0, 0.0, 0.0])
    up = np.cross(right, fwd)
    R_des = np.stack([right, up, -fwd], axis=1)
    return R_des @ np.asarray(cam_rest)[:3, :3].T


def add_camera(name, world, lens=LENS, col=None):
    cam = bpy.data.cameras.new(name)
    cam.lens = lens
    cam.sensor_width = fitlib.SENSOR
    cam.clip_start = 0.05
    cam.clip_end = 200.0
    obj = bpy.data.objects.new(name, cam)
    blcore.link(obj, col)
    obj.matrix_world = Matrix(np.asarray(world).tolist())
    return obj
