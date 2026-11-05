"""Animation set definitions (what goes into assets/anims/<set>.glb).  See anim_export.py.

Clip names follow actors/character_model.gd.  Sources: CMU mocap BVH ($CHARPIPE_CACHE/bvh), Quaternius UAL (CC0 FBX).
"""
import os, math
import numpy as np
import mh_lib as mh
import anim as A
import anim_src as S
from anim import FPS, Clip, pose_frame

BVH_DIR = os.path.join(mh.CACHE, "bvh")
V = lambda *a: np.array(a, dtype=float)


class Ctx:
    def __init__(self, rig, ual_path=""):
        self.rig = rig
        self.sc = rig.head["neck_01"][2] / 1.564
        self.ual_path = ual_path
        self._ual = None
        self.meta = {}
        self.only = None

    @property
    def ual(self):
        if self._ual is None:
            self._ual = S.ArmSrc(self.rig, self.ual_path)
        return self._ual

    def want(self, name):
        return self.only is None or name in self.only

    def bvh(self, cid, f0=0, f1=None, **kw):
        return S.bvh_take(self.rig, os.path.join(BVH_DIR, cid + ".bvh"), f0, f1, **kw)

    def sec(self, take, t0, t1):
        """frame indices for seconds t0..t1 of a source BVH-take file (uses the take's own fps)."""
        return int(t0 * take.fps), int(t1 * take.fps)

    def put(self, name, frames, loop, spec_fn=None, speed=None, extra=None):
        S.emit(self.rig, frames, name, loop, spec_fn)
        m = {"duration": len(frames) / FPS}
        if speed is not None: m["speed"] = float(speed)
        if extra: m.update(extra)
        self.meta[name] = m
        print("[clip] %-18s %3d frames %.2fs loop=%s %s" % (name, len(frames), len(frames) / FPS, loop, ("speed=%.2f" % speed) if speed else ""))


def _bvh_file_frames(ctx, cid):
    from bvh import BVH
    return BVH(os.path.join(BVH_DIR, cid + ".bvh"))


def ual_frames(ctx, action, f0=None, f1=None, xy="zero", mirror=False, speed=1.0, drop_last=False):
    t = ctx.ual.take(action, f0, f1, xy=xy, drop_last=drop_last)
    if mirror: t = t.mirrored()
    if speed != 1.0:
        t = t.sliced(0, (t.n - 1) / t.fps, speed=speed)
    else:
        t = t.sliced(0, (t.n - 1) / t.fps)
    return S.finalize(ctx.rig, t)


def bvh_frames(ctx, cid, t0=0.0, t1=None, xy="zero", mirror=False, speed=1.0, yaw=None):
    b = _bvh_file_frames(ctx, cid)
    f0 = int(t0 / b.dt); f1 = b.nframes if t1 is None else int(t1 / b.dt)
    t = S.bvh_take(ctx.rig, os.path.join(BVH_DIR, cid + ".bvh"), f0, f1, xy=xy, yaw=yaw)
    if mirror: t = t.mirrored()
    t = t.sliced(0, (t.n - 1) / t.fps, speed=speed)
    return S.finalize(ctx.rig, t), t


def build_elias(ctx, only=None):
    ctx.only = set(only) if only else None
    W = ctx.want
    if W("idle"): ctx.put("idle", ual_frames(ctx, "Idle_Loop", drop_last=True), True)
    if W("aim_idle"): ctx.put("aim_idle", ual_frames(ctx, "Pistol_Idle_Loop", drop_last=True), True)
    if W("shoot"): ctx.put("shoot", ual_frames(ctx, "Pistol_Shoot"), False)
    if W("reload"): ctx.put("reload", ual_frames(ctx, "Pistol_Reload"), False)
    if W("hatchet_swing"): ctx.put("hatchet_swing", ual_frames(ctx, "Sword_Attack"), False)
    if W("death"): ctx.put("death", ual_frames(ctx, "Death01"), False)
    if W("interact"): ctx.put("interact", ual_frames(ctx, "Interact"), False)
    return ctx.meta


def build_zombie(ctx, only=None):
    ctx.only = set(only) if only else None
    W = ctx.want
    if W("zombie_walk"):
        fr, t = bvh_frames(ctx, "120_22", xy="drift")
        ctx.put("zombie_walk", fr, False, speed=t.meta["travel"] / (t.n / FPS))
    return ctx.meta
