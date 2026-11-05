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



def spec(**kw):
    """overlay spec helper: spec(rot={bone:(rx,ry,rz)}, curl={'l':deg,'r':deg}, loc=(x,y,z))"""
    d = {}
    for k, v in kw.items():
        if k == "rot":
            for b, a in v.items(): d[("rot", b)] = np.array(a, dtype=float)
        elif k == "curl":
            for sd, a in v.items(): d[("curl", sd)] = np.array(a if hasattr(a, "__len__") else [a], dtype=float)
        elif k == "loc":
            d[("loc", "_")] = np.array(v, dtype=float)
    return d


def loco(ctx, cid, lo, hi, region=None, mirror=False, flip_if_x=None):
    """cyclic locomotion from a CMU file: -> (frames[no dup end], speed m/s, travel_vec)"""
    path = os.path.join(BVH_DIR, cid + ".bvh")
    s0, s1, err = S.find_loop(path, lo, hi, region)
    t = S.bvh_take(ctx.rig, path, s0, s1, xy="drift")
    tk = S.bvh_take(ctx.rig, path, s0, s1, xy="keep")
    tv = tk.loc[-1][:2] - tk.loc[0][:2]
    if mirror: t = t.mirrored(); tv = np.array([-tv[0], tv[1]])
    dur = t.n / t.fps
    t = t.sliced(0, dur)
    fr = S.finalize(ctx.rig, t)[:-1]
    print("   loop %s %d-%d err=%.2f dur=%.2f travel=(%.2f,%.2f)" % (cid, s0, s1, err, dur, tv[0], tv[1]))
    return fr, float(np.linalg.norm(tv) / dur), tv


def slice_loop(ctx, cid, t0, t1, blend=10, xy="zero", mirror=False, speed=1.0, yaw=None):
    fr, t = bvh_frames(ctx, cid, t0, t1, xy=xy, mirror=mirror, speed=speed, yaw=yaw)
    return S.make_loop(fr, blend)


def hit_clip(name, peaks, dur=0.55, rate=1.0):
    """authored additive-style hit clip (T-pose + spine/head rotation keys, played as delta from frame 0)."""
    c = Clip(name, dur, False)
    z = {b: (0, 0, 0) for b in peaks}
    c.key(0, rot=z)
    c.key(0.07 * dur / 0.55, rot=peaks)
    c.key(0.22 * dur / 0.55, rot={b: tuple(0.35 * np.array(v)) for b, v in peaks.items()})
    c.key(dur, rot=z)
    return c


def put_authored(ctx, c, loop=False):
    n = max(2, int(round(c.dur * FPS)))
    frames = []
    for i in range(n + 1):
        sp = c.eval(min(i / FPS, c.dur))
        frames.append(({}, None, sp))
    qs, locs = [], []
    for Rw, lc, sp in frames:
        q, l = pose_frame(ctx.rig, {}, None, sp)
        qs.append(q); locs.append(l)
    A.write_action(ctx.rig, c.name, qs, locs, loop=loop)
    ctx.meta[c.name] = {"duration": c.dur}
    print("[clip] %-18s authored %.2fs" % (c.name, c.dur))


def add_hits(ctx):
    W = ctx.want
    if W("hit_front"):
        ctx.put("hit_front", ual_frames(ctx, "Hit_Chest"), False)
    if W("hit_head"):
        ctx.put("hit_head", ual_frames(ctx, "Hit_Head"), False)
    if W("hit_back"):
        put_authored(ctx, hit_clip("hit_back", {"spine_01": (9, 0, 0), "spine_02": (14, 0, 0), "spine_03": (10, 0, 0), "head": (16, 0, 0),
                                                "upperarm_l": (0, 0, 22), "upperarm_r": (0, 0, -22)}))
    if W("hit_left"):
        put_authored(ctx, hit_clip("hit_left", {"spine_01": (0, -8, 6), "spine_02": (0, -13, 10), "spine_03": (0, -9, 8), "head": (0, -16, 14),
                                                "upperarm_r": (0, 0, -18)}))
    if W("hit_right"):
        put_authored(ctx, hit_clip("hit_right", {"spine_01": (0, 8, -6), "spine_02": (0, 13, -10), "spine_03": (0, 9, -8), "head": (0, 16, -14),
                                                 "upperarm_l": (0, 0, 18)}))



def author(ctx, base, clip, loop=False, name=None):
    """frames = mocap base frames (cycled) + a keyed Clip overlay (hand IK, rot, curl, twist, loc) evaluated per frame."""
    n = max(2, int(round(clip.dur * FPS)))
    rig = ctx.rig
    frames_q, frames_l = [], []
    for i in range(n + 1):
        t = min(i / FPS, clip.dur) if not loop else (i % n) / FPS
        Rw, lc = base[i % len(base)]
        q, l = pose_frame(rig, Rw, lc, clip.eval(t))
        frames_q.append(q); frames_l.append(l)
    A.write_action(rig, name or clip.name, frames_q, frames_l, loop=loop)
    ctx.meta[name or clip.name] = {"duration": clip.dur}
    print("[clip] %-18s keyed-over-mocap %.2fs" % (name or clip.name, clip.dur))


def L_(sc, x, y, z):
    return V(x, y, z) * sc


def zombie_base(ctx):
    return slice_loop(ctx, "137_15", 2.0, 8.0, blend=24, xy="zero")


def zombie_attacks(ctx):
    sc = ctx.sc
    base = zombie_base(ctx)
    hunch = lambda a=1.0: {"spine_01": (6 * a, 0, 0), "spine_02": (10 * a, 0, 0), "spine_03": (8 * a, 0, 0), "head": (10 * a, 0, 0)}
    claw = {"l": 55, "r": 55}
    idleh = {"l": L_(sc, 0.24, -0.34, 1.05), "r": L_(sc, -0.24, -0.34, 1.05)}
    reach = {"l": L_(sc, 0.2, -0.62, 1.40), "r": L_(sc, -0.2, -0.62, 1.40)}
    # grab + bite: reach both arms to shoulder height, lunge, claw, pull in, head dips to the neck, release
    c = Clip("grab", 1.9, False)
    c.key(0.0, rot=hunch(), hand=idleh, curl=claw)
    c.key(0.35, rot=hunch(0.8), hand=reach, curl={"l": 25, "r": 25})
    c.key(0.62, rot={"spine_01": (10, 0, 0), "spine_02": (18, 0, 0), "spine_03": (14, 0, 0), "head": (6, 0, 0)},
          hand={"l": L_(sc, 0.14, -0.86, 1.34), "r": L_(sc, -0.14, -0.86, 1.34)}, curl={"l": 80, "r": 80}, loc=V(0, -0.16, -0.05))
    c.key(1.0, rot={"spine_01": (12, 0, 0), "spine_02": (24, 0, 0), "spine_03": (20, 0, 0), "head": (34, 0, 0)},
          hand={"l": L_(sc, 0.12, -0.42, 1.32), "r": L_(sc, -0.12, -0.42, 1.32)}, curl={"l": 85, "r": 85}, loc=V(0, -0.10, -0.08))
    c.key(1.35, rot={"spine_01": (12, 0, 0), "spine_02": (22, 0, 0), "spine_03": (18, 0, 0), "head": (38, 0, 0)},
          hand={"l": L_(sc, 0.14, -0.38, 1.30), "r": L_(sc, -0.14, -0.38, 1.30)}, curl={"l": 85, "r": 85}, loc=V(0, -0.08, -0.08))
    c.key(1.9, rot=hunch(), hand=idleh, curl=claw)
    author(ctx, base, c)
    # attack (swipe both claws forward and rake down)
    c = Clip("attack", 1.1, False)
    c.key(0.0, rot=hunch(), hand=idleh, curl=claw)
    c.key(0.22, rot=hunch(0.6), hand={"l": L_(sc, 0.26, -0.45, 1.5), "r": L_(sc, -0.26, -0.45, 1.5)}, curl={"l": 25, "r": 25})
    c.key(0.45, rot={"spine_01": (10, 0, 0), "spine_02": (20, 0, 0), "spine_03": (14, 0, 0), "head": (12, 0, 0)},
          hand={"l": L_(sc, 0.16, -0.82, 1.12), "r": L_(sc, -0.16, -0.82, 1.12)}, curl={"l": 85, "r": 85}, loc=V(0, -0.14, -0.04))
    c.key(0.75, rot=hunch(1.1), hand={"l": L_(sc, 0.2, -0.55, 1.1), "r": L_(sc, -0.2, -0.55, 1.1)}, curl={"l": 60, "r": 60})
    c.key(1.1, rot=hunch(), hand=idleh, curl=claw)
    author(ctx, base, c)
    c.name = "zombie_attack"
    author(ctx, base, c, name="zombie_attack")
    # attack_b: one-arm hooking swipe
    c = Clip("attack_b", 1.2, False)
    c.key(0.0, rot=hunch(), hand=idleh, curl=claw)
    c.key(0.25, rot={"spine_01": (4, 0, -8), "spine_02": (8, 0, -14), "spine_03": (6, 0, -10), "head": (10, 0, 6)},
          hand={"l": L_(sc, 0.2, -0.4, 1.0), "r": L_(sc, -0.46, -0.14, 1.5)}, curl={"l": 55, "r": 25})
    c.key(0.5, rot={"spine_01": (8, 0, 10), "spine_02": (16, 0, 18), "spine_03": (12, 0, 12), "head": (12, 0, -6)},
          hand={"l": L_(sc, 0.2, -0.4, 1.0), "r": L_(sc, 0.05, -0.82, 1.18)}, curl={"l": 55, "r": 85}, loc=V(0, -0.12, -0.04))
    c.key(0.85, rot=hunch(1.1), hand={"l": L_(sc, 0.22, -0.36, 1.0), "r": L_(sc, -0.14, -0.55, 1.1)}, curl=claw)
    c.key(1.2, rot=hunch(), hand=idleh, curl=claw)
    author(ctx, base, c)
    # lunge: bigger forward body travel then reach
    c = Clip("lunge", 1.5, False)
    c.key(0.0, rot=hunch(), hand=idleh, curl=claw)
    c.key(0.3, rot=hunch(0.7), hand=reach, curl={"l": 25, "r": 25}, loc=V(0, 0.06, -0.06))
    c.key(0.6, rot={"spine_01": (14, 0, 0), "spine_02": (26, 0, 0), "spine_03": (18, 0, 0), "head": (8, 0, 0)},
          hand={"l": L_(sc, 0.14, -0.95, 1.25), "r": L_(sc, -0.14, -0.95, 1.25)}, curl={"l": 80, "r": 80}, loc=V(0, -0.35, -0.14))
    c.key(1.0, rot=hunch(1.3), hand={"l": L_(sc, 0.16, -0.7, 1.2), "r": L_(sc, -0.16, -0.7, 1.2)}, curl={"l": 70, "r": 70}, loc=V(0, -0.18, -0.08))
    c.key(1.5, rot=hunch(), hand=idleh, curl=claw)
    author(ctx, base, c)


def elias_authored(ctx, W):
    sc = ctx.sc
    idle_b = ual_frames(ctx, "Idle_Loop", drop_last=True)
    aim_b = ual_frames(ctx, "Pistol_Idle_Loop", drop_last=True)
    aim_rot = {"spine_01": (0, 0, 4), "spine_02": (-1.5, 0, 8), "spine_03": (0, 0, 5), "head": (0, 0, -10)}
    tw = {"lowerarm_r": -70, "lowerarm_l": 80}
    # --- hatchet combo: tight one-handed chops (elbow bent, strike forward-down)
    def chop(name, dur, wind, strike, rot_w, rot_s, hold=0.18):
        c = Clip(name, dur, False)
        idle_r = L_(sc, -0.24, -0.1, 0.95)
        c.key(0.0, rot={"spine_02": (0, 0, 0)}, hand={"r": idle_r, "l": L_(sc, 0.24, -0.1, 0.95)}, curl={"r": 80, "l": 20})
        c.key(dur * 0.30, rot=rot_w, hand={"r": wind, "l": L_(sc, 0.3, -0.15, 1.0)}, curl={"r": 85, "l": 20})
        c.key(dur * 0.46, rot=rot_s, hand={"r": strike, "l": L_(sc, 0.3, -0.25, 1.05)}, curl={"r": 85, "l": 20})
        c.key(dur * 0.46 + hold, rot=rot_s, hand={"r": strike, "l": L_(sc, 0.3, -0.25, 1.05)}, curl={"r": 85, "l": 20})
        c.key(dur, rot={"spine_02": (0, 0, 0)}, hand={"r": idle_r, "l": L_(sc, 0.24, -0.1, 0.95)}, curl={"r": 40, "l": 20})
        return c
    if W("hatchet_swing"):
        author(ctx, idle_b, chop("hatchet_swing", 1.0, L_(sc, -0.24, 0.02, 1.78), L_(sc, -0.1, -0.6, 1.0),
                                 {"spine_01": (-4, 0, -8), "spine_02": (-8, 0, -14), "spine_03": (-4, 0, -8), "head": (4, 0, 8)},
                                 {"spine_01": (8, 0, 8), "spine_02": (16, 0, 14), "spine_03": (10, 0, 8), "head": (8, 0, -6)}))
    if W("hatchet_2"):
        author(ctx, idle_b, chop("hatchet_2", 0.95, L_(sc, 0.3, -0.12, 1.5), L_(sc, -0.5, -0.5, 1.12),
                                 {"spine_01": (0, 0, 8), "spine_02": (0, 0, 16), "spine_03": (0, 0, 10), "head": (0, 0, -8)},
                                 {"spine_01": (6, 0, -10), "spine_02": (12, 0, -20), "spine_03": (8, 0, -12), "head": (6, 0, 8)}))
    if W("hatchet_3"):
        author(ctx, idle_b, chop("hatchet_3", 1.15, L_(sc, -0.12, 0.05, 2.0), L_(sc, -0.08, -0.7, 0.9),
                                 {"spine_01": (-8, 0, 0), "spine_02": (-14, 0, 0), "spine_03": (-8, 0, 0), "head": (-6, 0, 0)},
                                 {"spine_01": (14, 0, 0), "spine_02": (26, 0, 0), "spine_03": (14, 0, 0), "head": (12, 0, 0)}, hold=0.25))
    # --- pistol reload at sternum height: mag out to the belt (left), new mag in, slide rack, back to aim
    if W("reload"):
        c = Clip("reload", 2.2, False)
        gr = L_(sc, -0.09, -0.38, 1.22)           # gun hand at the sternum
        aimh = {"l": L_(sc, 0.035, -0.60, 1.375), "r": L_(sc, -0.035, -0.64, 1.40)}
        def kk(t, hl, hr, cl=55, lean=0):
            r = dict(aim_rot); r["spine_02"] = (lean, 0, 8); r["head"] = (lean * 2, 0, -8)
            c.key(t, rot=r, hand={"l": hl, "r": hr}, curl={"l": cl, "r": 62}, twist=tw)
        kk(0.0, aimh["l"], aimh["r"])
        kk(0.30, L_(sc, 0.05, -0.34, 1.22), gr, lean=4)
        kk(0.62, L_(sc, 0.25, -0.06, 0.96), gr, cl=25, lean=6)      # left hand to mag pouch on the belt
        kk(0.95, L_(sc, 0.14, -0.2, 1.05), gr, cl=75, lean=6)       # mag in hand
        kk(1.25, L_(sc, 0.03, -0.36, 1.14), gr, cl=75, lean=5)      # seat the mag
        kk(1.5, L_(sc, 0.04, -0.46, 1.27), gr, cl=45, lean=4)       # grip slide
        kk(1.68, L_(sc, 0.04, -0.30, 1.27), gr, cl=45, lean=4)      # rack back
        kk(1.85, L_(sc, 0.04, -0.46, 1.27), gr, cl=55, lean=3)      # release
        kk(2.2, aimh["l"], aimh["r"])
        author(ctx, aim_b, c)
    # --- long gun (shotgun / launcher): stock to the shoulder, support hand on the fore-end
    rh = L_(sc, -0.15, -0.34, 1.30)
    lh = L_(sc, 0.09, -0.64, 1.30)
    lrot = {"spine_01": (0, 0, 6), "spine_02": (-1, 0, 12), "spine_03": (0, 0, 8), "head": (2, 0, -12), "pelvis": (0, 0, 6)}
    ltw = {"lowerarm_r": -55, "lowerarm_l": 70}
    if W("aim_long"):
        c = Clip("aim_long", 2.4, True)
        for t, a in ((0, 0), (1.2, 1), (2.4, 0)):
            c.key(t, rot=lrot, hand={"l": lh + V(0.002, 0.002 * a, 0.003 * a) * sc, "r": rh + V(0, 0.002, 0.002 * a) * sc}, curl={"l": 50, "r": 62}, twist=ltw)
        author(ctx, aim_b, c, loop=True)
    if W("shoot_long"):
        c = Clip("shoot_long", 1.1, False)
        c.key(0.0, rot=lrot, hand={"l": lh, "r": rh}, curl={"l": 50, "r": 62}, twist=ltw)
        kick = dict(lrot); kick["spine_03"] = (-5, 0, 8); kick["head"] = (-3, 0, -12)
        c.key(0.06, rot=kick, hand={"l": lh + V(0, 0.07, 0.04) * sc, "r": rh + V(0, 0.06, 0.04) * sc}, curl={"l": 50, "r": 64}, twist=ltw, loc=V(0, 0.03, 0))
        c.key(0.22, rot=lrot, hand={"l": lh, "r": rh}, curl={"l": 50, "r": 62}, twist=ltw)
        c.key(0.38, rot=lrot, hand={"l": lh + V(0, 0.16, -0.01) * sc, "r": rh}, curl={"l": 70, "r": 62}, twist=ltw)   # pump back
        c.key(0.55, rot=lrot, hand={"l": lh + V(0, 0.16, -0.01) * sc, "r": rh}, curl={"l": 70, "r": 62}, twist=ltw)
        c.key(0.72, rot=lrot, hand={"l": lh, "r": rh}, curl={"l": 50, "r": 62}, twist=ltw)                               # pump fwd
        c.key(1.1, rot=lrot, hand={"l": lh, "r": rh}, curl={"l": 50, "r": 62}, twist=ltw)
        author(ctx, aim_b, c)
    if W("reload_long"):
        c = Clip("reload_long", 2.8, False)
        def kl(t, hl, hr, cl=50, lean=0):
            r = dict(lrot); r["spine_02"] = (lean, 0, 10)
            c.key(t, rot=r, hand={"l": hl, "r": hr}, curl={"l": cl, "r": 62}, twist=ltw)
        low = L_(sc, -0.12, -0.42, 1.12)           # gun lowered to the belly, port facing up
        kl(0.0, lh, rh)
        kl(0.3, L_(sc, 0.08, -0.52, 1.18), low, lean=3)
        for k, t0 in enumerate((0.55, 1.0, 1.45)):
            kl(t0, L_(sc, 0.24, -0.06, 0.96), low, cl=25, lean=5)                # shell from the belt loop
            kl(t0 + 0.22, L_(sc, 0.06, -0.38, 1.1), low, cl=75, lean=5)         # shell into the loading port
        kl(1.95, L_(sc, 0.08, -0.52, 1.22), L_(sc, -0.14, -0.38, 1.24), lean=3)
        kl(2.15, lh + V(0, 0.16, -0.01) * sc, rh, cl=70)
        kl(2.35, lh, rh)
        kl(2.8, lh, rh)
        author(ctx, aim_b, c)


def build_elias(ctx, only=None):
    ctx.only = set(only) if only else None
    W = ctx.want
    if W("idle"): ctx.put("idle", ual_frames(ctx, "Idle_Loop", drop_last=True), True)
    if W("aim_idle"): ctx.put("aim_idle", ual_frames(ctx, "Pistol_Idle_Loop", drop_last=True), True)
    if W("shoot"): ctx.put("shoot", ual_frames(ctx, "Pistol_Shoot"), False)
    if W("aim_up"): ctx.put("aim_up", ual_frames(ctx, "Pistol_Aim_Up", drop_last=True)[:1] * 2, True)
    if W("aim_down"): ctx.put("aim_down", ual_frames(ctx, "Pistol_Aim_Down", drop_last=True)[:1] * 2, True)
    elias_authored(ctx, W)
    if W("knife"): ctx.put("knife", ual_frames(ctx, "Punch_Jab", speed=1.1), False)
    if W("heavy"):
        fr, t = bvh_frames(ctx, "79_01", 0.4, 3.2, xy="zero")
        ctx.put("heavy", fr, False)
    if W("death"): ctx.put("death", ual_frames(ctx, "Death01"), False)
    if W("interact"): ctx.put("interact", ual_frames(ctx, "Interact"), False)
    if W("pickup"): ctx.put("pickup", ual_frames(ctx, "PickUp_Table"), False)
    if W("flashlight"): ctx.put("flashlight", ual_frames(ctx, "Idle_Torch_Loop"), False)
    if W("roll"): ctx.put("roll", ual_frames(ctx, "Roll"), False)
    if W("sprint"):
        t = ctx.ual.take("Sprint_Loop", xy="keep", drop_last=True)
        tv = np.linalg.norm(t.loc[-1][:2] - t.loc[0][:2]) * (t.n + 1) / t.n / (t.n / t.fps)
        ctx.put("sprint", ual_frames(ctx, "Sprint_Loop", xy="drift", drop_last=True), True, speed=5.4)
    if W("run_stop"):
        fr, t = bvh_frames(ctx, "143_02", 0.0, 1.2, xy="zero")
        ctx.put("run_stop", fr, False)
    for nm, cid, mir in (("walk_back", "143_39", False), ("walk_side", "143_40", False)):
        if W(nm) or W("walk_left") or W("walk_right"):
            if nm == "walk_back":
                fr, sp, tv = loco(ctx, cid, 0.8, 1.5)
                ctx.put("walk_back", fr, True, speed=sp)
            else:
                fr, sp, tv = loco(ctx, cid, 0.8, 1.7)
                left = tv[0] > 0
                ctx.put("walk_left" if left else "walk_right", fr, True, speed=sp)
                t = S.bvh_take  # mirrored copy for the other side
                path = os.path.join(BVH_DIR, cid + ".bvh")
                s0, s1, _ = S.find_loop(path, 0.8, 1.7)
                tk = S.bvh_take(ctx.rig, path, s0, s1, xy="drift").mirrored()
                tk = tk.sliced(0, tk.n / tk.fps)
                ctx.put("walk_right" if left else "walk_left", S.finalize(ctx.rig, tk)[:-1], True, speed=sp)
    for nm, cid, t0, t1 in (("turn_a", "69_16", 0.5, 2.0), ("turn_b", "69_18", 0.5, 2.0)):
        if W("turn_l") or W("turn_r"):
            fr, t = bvh_frames(ctx, cid, t0, t1, xy="zero")
            # unyaw: remove the body spin so only the stepping stays
            path = os.path.join(BVH_DIR, cid + ".bvh")
            tk = S.bvh_take(ctx.rig, path, int(t0 / 0.00833), int(t1 / 0.00833), xy="zero", unyaw=True)
            tk = tk.sliced(0, tk.n / tk.fps)
            ctx.put("turn_l" if nm == "turn_a" else "turn_r", S.make_loop(S.finalize(ctx.rig, tk), 12), True)
    if W("stagger"):
        fr, t = bvh_frames(ctx, "22_12", 0.0, 2.4, xy="zero")
        ctx.put("stagger", fr, False)
    if W("struggle"):
        fr, t = bvh_frames(ctx, "19_05", 0.2, 3.4, xy="zero")
        ctx.put("struggle", fr, False)
    add_hits(ctx)
    legacy(ctx)
    return ctx.meta


def legacy(ctx):
    """clips of the old pipeline (clips.py: CMU walk/run + hand-keyed idle/sit/hang/death/...) that the new sets do not replace, so the
    anim glb alone fully drives a mesh-only character glb (the character glbs no longer need embedded clips)."""
    import clips as old
    out, meta = old.build_clips(ctx.rig, True)
    loops = ("idle", "aim_idle", "walk", "run", "zombie_idle", "zombie_walk", "crawl", "sit", "hang")
    for name, (qs, locs) in out.items():
        if name in ctx.meta: continue
        A.write_action(ctx.rig, name, qs, locs, loop=name in loops)
        ctx.meta[name] = dict(meta.get(name, {}), duration=len(qs) / FPS, legacy=True)
        print("[legacy] %s" % name)


def zombify(arms=50.0, hunch=14.0, head=14.0, claw=30.0):
    def fn(i, n):
        return spec(rot={"spine_01": (hunch * 0.4, 0, 0), "spine_02": (hunch * 0.6, 0, 0), "spine_03": (hunch * 0.5, 0, 0), "head": (head, 0, 0),
                         "upperarm_l": (-arms, 0, 0), "upperarm_r": (-arms, 0, 0), "lowerarm_l": (-arms * 0.4, 0, 0), "lowerarm_r": (-arms * 0.4, 0, 0)},
                    curl={"l": claw, "r": claw})
    return fn


def build_zombie(ctx, only=None):
    ctx.only = set(only) if only else None
    W = ctx.want
    walks = [("zombie_walk", "137_33", (0.9, 1.8), None, (3, 24), dict(arms=45, hunch=14, head=16, claw=40)),
             ("zombie_walk_b", "137_16", (0.9, 1.8), None, (1, 11), dict(arms=55, hunch=14, head=16)),
             ("zombie_walk_c", "139_19", (0.9, 1.8), None, (0.5, 8), dict(arms=40, hunch=18, head=18)),
             ("zombie_walk_d", "142_12", (0.9, 1.8), None, (2, 38), dict(arms=60, hunch=10, head=12)),
             ("zombie_walk_e", "20_08", (0.8, 1.7), None, None, dict(arms=15, hunch=8, head=10)),
             ("zombie_walk_f", "132_53", (0.9, 1.8), None, (3, 50), dict(arms=50, hunch=16, head=14)),
             ("zombie_walk_g", "136_01", (0.8, 1.7), None, (0.5, 7), dict(arms=35, hunch=6, head=10))]
    for nm, cid, (lo, hi), _, region, zk in walks:
        if W(nm):
            try:
                fr, sp, tv = loco(ctx, cid, lo, hi, region)
            except Exception as e:
                print("FAIL", nm, e); continue
            sp = {"zombie_walk_b": 0.6, "zombie_walk_f": 0.6}.get(nm, sp)
            ctx.put(nm, fr, True, zombify(**zk), speed=sp)
    if W("zombie_run"):
        fr, sp, tv = loco(ctx, "09_01", 0.45, 0.9)
        ctx.put("zombie_run", fr, True, zombify(arms=28, hunch=22, head=14, claw=45), speed=sp)
    for nm, cid, t0, t1 in (("zombie_idle", "137_15", 2.0, 8.0), ("zombie_idle_b", "137_32", 3.0, 9.0), ("zombie_idle_c", "140_06", 4.0, 10.0)):
        if W(nm):
            fr = slice_loop(ctx, cid, t0, t1, blend=24, xy="zero")
            ctx.put(nm, fr, True, zombify(arms=30, hunch=14, head=12, claw=35))
    if W("attack") or W("grab") or W("lunge"):
        zombie_attacks(ctx)
    if W("stagger"):
        fr, t = bvh_frames(ctx, "22_12", 0.0, 2.4, xy="zero")
        ctx.put("stagger", fr, False)
    for nm, cid, t0, t1 in (("getup_back", "140_08", 0.0, 6.0), ("getup_front", "140_01", 0.0, 5.5), ("getup_side", "140_03", 0.0, 6.5)):
        if W(nm):
            b = _bvh_file_frames(ctx, cid)
            full = S.bvh_take(ctx.rig, os.path.join(BVH_DIR, cid + ".bvh"), 0, min(b.nframes, int(t1 / b.dt)), xy="zero")
            z = np.array([l[2] for l in full.loc])
            k = int(np.argmax(z > z[0] + 0.06))             # first frame where the body actually starts to rise
            start = max(0.0, k / full.fps - 0.25)
            t = full.sliced(start, (full.n - 1) / full.fps, speed=1.5)
            ctx.put(nm, S.finalize(ctx.rig, t), False)
    if W("death"): ctx.put("death", ual_frames(ctx, "Death01"), False)
    if W("crawl"):
        fr, sp, tv = loco(ctx, "133_01", 1.0, 2.2)
        ctx.put("crawl", fr, True, speed=sp)
    add_hits(ctx)
    legacy(ctx)
    return ctx.meta
