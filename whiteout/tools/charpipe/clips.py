"""Clip definitions (authored + mocap-based) -> Blender actions."""
import math, json, os
import numpy as np
import mh_lib as mh
from anim import *

BVH_DIR = os.path.join(mh.CACHE, "bvh")
V = lambda *a: np.array(a, dtype=float)


def sc_of(rig):
    return rig.head["neck_01"][2] / 1.564


def idle_hands(sc):
    return {"l": V(0.255, -0.09, 0.86) * sc, "r": V(-0.255, -0.09, 0.86) * sc}


def aim_hands(sc):
    return {"l": V(0.035, -0.60, 1.375) * sc, "r": V(-0.035, -0.64, 1.40) * sc}


def build_clips(rig, with_mocap=True):
    """-> dict name -> (frames_q, frames_loc, loop, meta)"""
    sc = sc_of(rig)
    out = {}
    meta = {}

    def render(clip, base=None, fps=FPS, loop=None, default_hands=True):
        loop = clip.loop if loop is None else loop
        n = max(2, int(round(clip.dur * fps)))
        qs, locs = [], []
        for i in range(n + 1):
            t = i / fps if i < n else (clip.dur if not loop else 0.0)
            if loop and i == n: t = 0.0
            spec = clip.eval(t if not (loop and i == n) else 0.0)
            if default_hands:
                for s in ("l", "r"):
                    if ("hand", s) not in spec:
                        spec[("hand", s)] = idle_hands(sc)[s]
            b_rw, b_loc = (base(i % n) if base else ({}, None))
            q, l = pose_frame(rig, b_rw, b_loc, spec)
            qs.append(q); locs.append(l)
        return qs, locs

    # ---------------- idle (breathing, weight shift)
    c = Clip("idle", 3.2, True)
    for t, a in ((0, 0), (1.6, 1), (3.2, 0)):
        c.key(t, rot={"spine_02": (1.2 * a, 0, 0.6 * a), "spine_03": (0.8 * a, 0, -0.5 * a), "head": (-0.6 * a, 0, 1.2 * a)},
              loc=V(0.004 * a, 0, -0.004 * a))
    c.key(0, rot={"pelvis": (0, 0, 0)}, curl={"l": 14, "r": 14})
    c.key(3.2, rot={"pelvis": (0, 0, 0)})
    c.key(1.6, rot={"pelvis": (0, 1.4, 0.8)})
    out["idle"] = render(c)

    # ---------------- aim idle (two-hand pistol)
    def aim_rot(a=1.0):
        return {"spine_01": (0, 0, 4 * a), "spine_02": (-1.5 * a, 0, 8 * a), "spine_03": (0, 0, 5 * a),
                "head": (0, 0, -14 * a), "pelvis": (0, 0, 6 * a)}
    c = Clip("aim_idle", 2.4, True)
    for t, a in ((0, 0), (1.2, 1), (2.4, 0)):
        h = aim_hands(sc)
        c.key(t, rot=aim_rot(), hand={"l": h["l"] + V(0.002, 0.003, 0.003 * a) * sc, "r": h["r"] + V(-0.002, 0.002, -0.003 * a) * sc},
              curl={"l": 55, "r": 62}, twist={"lowerarm_r": -70, "lowerarm_l": 80})
    out["aim_idle"] = render(c)

    c = Clip("shoot", 0.32, False)
    h = aim_hands(sc)
    c.key(0.0, rot=aim_rot(), hand=h, curl={"l": 55, "r": 62}, twist={"lowerarm_r": -70, "lowerarm_l": 80})
    r2 = aim_rot(); r2["spine_03"] = (-3, 0, 5); r2["head"] = (-2, 0, -14)
    kick = {"l": h["l"] + V(0.0, 0.045, 0.035) * sc, "r": h["r"] + V(0.0, 0.055, 0.045) * sc}
    c.key(0.05, rot=r2, hand=kick, curl={"l": 55, "r": 64}, twist={"lowerarm_r": -62, "lowerarm_l": 74})
    c.key(0.32, rot=aim_rot(), hand=h, curl={"l": 55, "r": 62}, twist={"lowerarm_r": -70, "lowerarm_l": 80})
    out["shoot"] = render(c)

    c = Clip("reload", 2.0, False)
    A0 = aim_hands(sc)
    tw = {"lowerarm_r": -70, "lowerarm_l": 80}
    def kk(t, hl, hr, head=0.0, lean=0.0, cl=55, cr=62, tl=80):
        r = aim_rot(); r["head"] = (head, 0, -14 + head * -0.2); r["spine_02"] = (lean, 0, 6)
        c.key(t, rot=r, hand={"l": hl * sc, "r": hr * sc}, curl={"l": cl, "r": cr}, twist={"lowerarm_r": -70, "lowerarm_l": tl})
    kk(0.0, V(0.035, -0.60, 1.375), V(-0.035, -0.64, 1.40))
    kk(0.30, V(0.07, -0.40, 1.18), V(-0.10, -0.40, 1.22), head=14, lean=3)
    kk(0.60, V(0.22, -0.10, 0.98), V(-0.11, -0.40, 1.20), head=18, lean=4, cl=30)
    kk(0.95, V(0.10, -0.33, 1.14), V(-0.10, -0.40, 1.20), head=18, lean=4, cl=70)
    kk(1.15, V(0.08, -0.36, 1.18), V(-0.10, -0.41, 1.21), head=16, lean=4, cl=70)
    kk(1.40, V(0.12, -0.38, 1.22), V(-0.10, -0.42, 1.24), head=8, lean=2)
    kk(1.70, V(0.05, -0.55, 1.34), V(-0.05, -0.60, 1.38), head=0)
    kk(2.0, V(0.035, -0.60, 1.375), V(-0.035, -0.64, 1.40))
    out["reload"] = render(c)

    # ---------------- hurt / stagger
    for nm, dur, amp in (("hurt", 0.6, 1.0), ("stagger", 1.0, 1.9)):
        c = Clip(nm, dur, False)
        c.key(0, rot={"spine_02": (0, 0, 0), "spine_03": (0, 0, 0), "head": (0, 0, 0), "pelvis": (0, 0, 0)}, loc=V(0, 0, 0))
        c.key(0.12 * dur / 0.6, rot={"spine_01": (-6 * amp, 0, 4 * amp), "spine_02": (-8 * amp, 0, 8 * amp), "spine_03": (-8 * amp, 0, 5 * amp),
                       "head": (-18 * amp, 0, -10 * amp), "pelvis": (-3 * amp, 0, -5 * amp)}, loc=V(0, 0.03 * amp, -0.02 * amp),
              hand={"l": V(0.38, -0.2, 1.1) * sc, "r": V(-0.38, -0.2, 1.1) * sc})
        c.key(dur * 0.55, rot={"spine_01": (-3 * amp, 0, 2 * amp), "spine_02": (-4 * amp, 0, 4 * amp), "spine_03": (-3 * amp, 0, 3 * amp),
                       "head": (-6 * amp, 0, -4 * amp), "pelvis": (-1, 0, -2)}, loc=V(0, 0.015 * amp, -0.01),
              hand={"l": V(0.3, -0.15, 0.95) * sc, "r": V(-0.3, -0.15, 0.95) * sc})
        c.key(dur, rot={"spine_02": (0, 0, 0), "spine_03": (0, 0, 0), "head": (0, 0, 0), "pelvis": (0, 0, 0), "spine_01": (0, 0, 0)}, loc=V(0, 0, 0))
        out[nm] = render(c)

    # ---------------- death
    c = Clip("death", 2.3, False)
    z = {"pelvis": (0, 0, 0)}
    c.key(0, root=V(0, 0, 0), loc=V(0, 0, 0), rot={"thigh_l": (0, 0, 0), "thigh_r": (0, 0, 0), "calf_l": (0, 0, 0), "calf_r": (0, 0, 0), "spine_02": (0, 0, 0), "head": (0, 0, 0)})
    c.key(0.35, root=V(-4, 0, 0), loc=V(0, 0.05, -0.12), rot={"thigh_l": (-30, 0, 0), "thigh_r": (-22, 0, 0), "calf_l": (45, 0, 0), "calf_r": (30, 0, 0), "spine_02": (-8, 0, 3), "head": (-12, 0, 6)},
          hand={"l": V(0.4, -0.15, 1.15) * sc, "r": V(-0.4, -0.2, 1.2) * sc})
    c.key(0.8, root=V(-30, 0, 0), loc=V(0, 0.03, -0.1), rot={"thigh_l": (-20, 0, 8), "thigh_r": (-35, 0, -5), "calf_l": (30, 0, 0), "calf_r": (50, 0, 0), "spine_02": (-10, 0, 5), "head": (-20, 0, 10)},
          hand={"l": V(0.7, 0.2, 1.4) * sc, "r": V(-0.65, 0.1, 1.3) * sc})
    c.key(1.35, root=V(-84, 0, 0), loc=V(0, 0.0, 0.1), rot={"thigh_l": (-8, 0, 10), "thigh_r": (-18, 0, -8), "calf_l": (12, 0, 0), "calf_r": (35, 0, 0), "spine_02": (-3, 0, 4), "head": (-8, 0, 20)},
          hand={"l": V(0.75, 0.9, 0.12) * sc, "r": V(-0.6, 1.0, 0.1) * sc})
    c.key(1.55, root=V(-90, 0, 0), loc=V(0, 0.0, 0.135), rot={"thigh_l": (-4, 0, 12), "thigh_r": (-10, 0, -10), "calf_l": (8, 0, 0), "calf_r": (22, 0, 0), "spine_02": (0, 0, 3), "head": (-4, 0, 22)},
          hand={"l": V(0.8, 0.85, 0.08) * sc, "r": V(-0.62, 0.95, 0.07) * sc})
    c.key(2.3, root=V(-90, 0, 0), loc=V(0, 0.0, 0.135), rot={"thigh_l": (-4, 0, 12), "thigh_r": (-10, 0, -10), "calf_l": (8, 0, 0), "calf_r": (22, 0, 0), "spine_02": (0, 0, 3), "head": (-4, 0, 22)},
          hand={"l": V(0.8, 0.85, 0.08) * sc, "r": V(-0.62, 0.95, 0.07) * sc})
    out["death"] = render(c)

    # ---------------- melee
    c = Clip("hatchet_swing", 1.1, False)
    idle_h = idle_hands(sc)
    c.key(0, rot={"spine_02": (0, 0, 0), "head": (0, 0, 0)}, hand={"l": idle_h["l"], "r": idle_h["r"]}, curl={"r": 75, "l": 20})
    c.key(0.32, rot={"spine_01": (-4, 0, -10), "spine_02": (-8, 0, -18), "spine_03": (-6, 0, -10), "head": (0, 0, 12)},
          hand={"l": V(0.2, -0.2, 1.7) * sc, "r": V(-0.25, 0.1, 2.0) * sc}, curl={"r": 85, "l": 40})
    c.key(0.52, rot={"spine_01": (12, 0, 12), "spine_02": (22, 0, 20), "spine_03": (14, 0, 10), "head": (6, 0, -12)},
          hand={"l": V(0.15, -0.35, 1.2) * sc, "r": V(-0.05, -0.75, 1.15) * sc}, curl={"r": 85, "l": 40})
    c.key(0.75, rot={"spine_01": (6, 0, 6), "spine_02": (10, 0, 10), "spine_03": (6, 0, 6), "head": (2, 0, -4)},
          hand={"l": V(0.22, -0.2, 1.0) * sc, "r": V(-0.15, -0.5, 1.0) * sc}, curl={"r": 80, "l": 30})
    c.key(1.1, rot={"spine_01": (0, 0, 0), "spine_02": (0, 0, 0), "spine_03": (0, 0, 0), "head": (0, 0, 0)},
          hand={"l": idle_h["l"], "r": idle_h["r"]}, curl={"r": 30, "l": 14})
    out["hatchet_swing"] = render(c)

    c = Clip("knife", 0.6, False)
    c.key(0, rot={"spine_02": (0, 0, 0)}, hand={"r": idle_h["r"]}, curl={"r": 70})
    c.key(0.14, rot={"spine_01": (0, 0, -6), "spine_02": (0, 0, -12), "spine_03": (0, 0, -6)}, hand={"r": V(-0.3, -0.25, 1.05) * sc}, curl={"r": 80})
    c.key(0.27, rot={"spine_01": (4, 0, 8), "spine_02": (8, 0, 14), "spine_03": (4, 0, 8)}, hand={"r": V(-0.12, -0.78, 1.25) * sc}, curl={"r": 80})
    c.key(0.6, rot={"spine_01": (0, 0, 0), "spine_02": (0, 0, 0), "spine_03": (0, 0, 0)}, hand={"r": idle_h["r"]}, curl={"r": 30})
    out["knife"] = render(c)

    c = Clip("heavy", 1.3, False)
    c.key(0, rot={"spine_02": (0, 0, 0), "head": (0, 0, 0)}, hand={"l": idle_h["l"], "r": idle_h["r"]})
    c.key(0.5, rot={"spine_01": (-6, 0, 0), "spine_02": (-14, 0, 0), "spine_03": (-8, 0, 0), "head": (-10, 0, 0)},
          hand={"l": V(0.16, -0.05, 2.1) * sc, "r": V(-0.16, -0.05, 2.1) * sc}, curl={"l": 85, "r": 85})
    c.key(0.72, rot={"spine_01": (14, 0, 0), "spine_02": (30, 0, 0), "spine_03": (18, 0, 0), "head": (12, 0, 0)},
          hand={"l": V(0.14, -0.7, 0.55) * sc, "r": V(-0.14, -0.7, 0.55) * sc}, curl={"l": 85, "r": 85})
    c.key(0.95, rot={"spine_01": (10, 0, 0), "spine_02": (20, 0, 0), "spine_03": (12, 0, 0), "head": (6, 0, 0)},
          hand={"l": V(0.2, -0.55, 0.6) * sc, "r": V(-0.2, -0.55, 0.6) * sc}, curl={"l": 60, "r": 60})
    c.key(1.3, rot={"spine_01": (0, 0, 0), "spine_02": (0, 0, 0), "spine_03": (0, 0, 0), "head": (0, 0, 0)},
          hand={"l": idle_h["l"], "r": idle_h["r"]}, curl={"l": 14, "r": 14})
    out["heavy"] = render(c)

    # ---------------- zombie
    zl = lambda a, side: V(0.2 * side, -0.55, 1.3 + 0.05 * a) * sc
    c = Clip("zombie_idle", 3.0, True)
    for t, a in ((0, 0), (1.5, 1), (3.0, 0)):
        c.key(t, rot={"spine_01": (8 + 1 * a, 0, 2 * a), "spine_02": (10 + 1.5 * a, 0, -3 * a), "spine_03": (6, 0, 3 * a),
                      "head": (8 + 3 * a, 0, 14 * (a - 0.5) * 2 * 0.6), "pelvis": (2, 0, 3 * (a - 0.5))},
              hand={"l": V(0.22, -0.36 - 0.02 * a, 1.12 + 0.03 * a) * sc, "r": V(-0.2, -0.40 + 0.02 * a, 1.08 - 0.03 * a) * sc}, curl={"l": 40, "r": 50})
    out["zombie_idle"] = render(c)

    c = Clip("zombie_attack", 1.1, False)
    c.key(0, rot={"spine_01": (8, 0, 0), "spine_02": (10, 0, 0), "head": (8, 0, 0)}, hand={"l": V(0.22, -0.36, 1.12) * sc, "r": V(-0.2, -0.4, 1.08) * sc})
    c.key(0.3, rot={"spine_01": (-4, 0, 0), "spine_02": (-6, 0, 0), "spine_03": (-4, 0, 0), "head": (-12, 0, 0)}, hand={"l": V(0.35, -0.3, 1.5) * sc, "r": V(-0.3, -0.3, 1.5) * sc})
    c.key(0.55, rot={"spine_01": (18, 0, 0), "spine_02": (30, 0, 0), "spine_03": (14, 0, 0), "head": (20, 0, 0)},
          hand={"l": V(0.12, -0.85, 1.35) * sc, "r": V(-0.12, -0.85, 1.35) * sc}, loc=V(0, -0.1, -0.04), curl={"l": 70, "r": 70})
    c.key(0.8, rot={"spine_01": (12, 0, 0), "spine_02": (20, 0, 0), "spine_03": (10, 0, 0), "head": (12, 0, 0)},
          hand={"l": V(0.15, -0.7, 1.2) * sc, "r": V(-0.15, -0.7, 1.2) * sc}, loc=V(0, -0.05, -0.02))
    c.key(1.1, rot={"spine_01": (8, 0, 0), "spine_02": (10, 0, 0), "spine_03": (0, 0, 0), "head": (8, 0, 0)}, hand={"l": V(0.22, -0.36, 1.12) * sc, "r": V(-0.2, -0.4, 1.08) * sc}, loc=V(0, 0, 0))
    out["attack"] = out["zombie_attack"] = render(c)

    c = Clip("grab", 1.4, False)
    c.key(0, rot={"spine_02": (8, 0, 0), "head": (6, 0, 0)}, hand={"l": V(0.22, -0.36, 1.12) * sc, "r": V(-0.2, -0.4, 1.08) * sc})
    c.key(0.35, rot={"spine_01": (10, 0, 0), "spine_02": (22, 0, 0), "spine_03": (10, 0, 0), "head": (6, 0, 0)}, hand={"l": V(0.2, -0.75, 1.4) * sc, "r": V(-0.2, -0.75, 1.4) * sc}, curl={"l": 20, "r": 20})
    c.key(0.6, rot={"spine_01": (12, 0, 0), "spine_02": (24, 0, 0), "spine_03": (12, 0, 0), "head": (14, 0, 0)}, hand={"l": V(0.12, -0.78, 1.35) * sc, "r": V(-0.12, -0.78, 1.35) * sc}, curl={"l": 85, "r": 85})
    c.key(1.0, rot={"spine_01": (6, 0, 0), "spine_02": (14, 0, 0), "spine_03": (6, 0, 0), "head": (18, 0, 0)}, hand={"l": V(0.14, -0.5, 1.2) * sc, "r": V(-0.14, -0.5, 1.2) * sc}, curl={"l": 85, "r": 85})
    c.key(1.4, rot={"spine_01": (0, 0, 0), "spine_02": (8, 0, 0), "spine_03": (0, 0, 0), "head": (6, 0, 0)}, hand={"l": V(0.22, -0.36, 1.12) * sc, "r": V(-0.2, -0.4, 1.08) * sc}, curl={"l": 14, "r": 14})
    out["grab"] = render(c)

    c = Clip("roar", 1.7, False)
    c.key(0, rot={"spine_02": (8, 0, 0), "head": (6, 0, 0)}, hand={"l": V(0.22, -0.36, 1.12) * sc, "r": V(-0.2, -0.4, 1.08) * sc})
    c.key(0.5, rot={"spine_01": (-6, 0, 0), "spine_02": (-14, 0, 0), "spine_03": (-12, 0, 0), "head": (-34, 0, 0)}, hand={"l": V(0.75, -0.1, 1.5) * sc, "r": V(-0.75, -0.1, 1.5) * sc}, curl={"l": 20, "r": 20})
    c.key(1.2, rot={"spine_01": (-5, 0, 0), "spine_02": (-12, 0, 0), "spine_03": (-10, 0, 0), "head": (-30, 0, 0)}, hand={"l": V(0.8, -0.05, 1.45) * sc, "r": V(-0.8, -0.05, 1.45) * sc}, curl={"l": 20, "r": 20})
    c.key(1.7, rot={"spine_01": (0, 0, 0), "spine_02": (8, 0, 0), "spine_03": (0, 0, 0), "head": (6, 0, 0)}, hand={"l": V(0.22, -0.36, 1.12) * sc, "r": V(-0.2, -0.4, 1.08) * sc})
    out["roar"] = render(c)

    # ---------------- crawl (loop) + sit
    c = Clip("crawl", 1.4, True)
    for t, a in ((0, 1), (0.7, -1), (1.4, 1)):
        c.key(t, root=V(84, 0, 0), loc=V(0, 0, 0.12), rot={"head": (-55, 0, 0), "spine_02": (-8, 0, 4 * a), "spine_03": (-12, 0, -4 * a),
              "thigh_l": (6, 0, 4 * a), "thigh_r": (6, 0, -4 * a), "calf_l": (5 + 10 * a, 0, 0), "calf_r": (5 - 10 * a, 0, 0), "pelvis": (0, 0, 5 * a)},
              hand={"l": V(0.28, -1.78 - 0.22 * a, 0.08 + 0.1 * (a > 0)) * sc, "r": V(-0.28, -1.78 + 0.22 * a, 0.08 + 0.1 * (a < 0)) * sc}, curl={"l": 50, "r": 50})
    out["crawl"] = render(c)

    c = Clip("sit", 1.0, True)
    for t in (0, 1.0):
        c.key(t, loc=V(0, 0, -0.455 * sc), rot={"thigh_l": (-86, 0, 0), "thigh_r": (-86, 0, 0), "calf_l": (88, 0, 0), "calf_r": (88, 0, 0),
              "spine_02": (3, 0, 0), "head": (2, 0, 0)}, hand={"l": V(0.2, -0.38, 0.62 * 1) * sc, "r": V(-0.2, -0.38, 0.62) * sc})
    out["sit"] = render(c)

    # ---------------- mocap based: walk, run, zombie_walk
    if with_mocap:
        for name, f, dtscale in (("walk", "35_01", 1.0), ("run", "09_01", 1.0)):
            path = os.path.join(BVH_DIR, f + ".bvh")
            lo, hi = (0.75, 1.5) if name == "walk" else (0.45, 0.9)
            s0, s1, err = find_loop(path, min_len=lo, max_len=hi, start_hint=10)
            frames, spd, dt = mocap_frames(rig, path, s0, s1)
            print(f"[mocap] {name}: {f} frames {s0}-{s1} err={err:.2f} speed={spd:.2f} m/s")
            fr = resample(frames, dt)
            meta[name] = {"speed": float(spd), "duration": len(fr) / FPS}
            qs, locs = [], []
            n = len(fr)
            for i in range(n + 1):
                Rw, loc = fr[i % n]
                spec = {("curl", "l"): np.array([20.0]), ("curl", "r"): np.array([20.0])}
                q, l = pose_frame(rig, Rw, loc, spec)
                qs.append(q); locs.append(l)
            out[name] = (qs, locs)
            if name == "walk":
                # zombie walk: slowed mocap legs, hunched torso, arms reaching, head lolling
                Z = fr
                nz = len(Z)
                dur = nz / FPS / 0.62
                meta["zombie_walk"] = {"speed": float(spd) * 0.62 * 0.8, "duration": dur}
                qs, locs = [], []
                nout = int(round(dur * FPS))
                zc = Clip("zw", dur, True)
                for t, a in ((0, 0), (dur * 0.25, 1), (dur * 0.5, 0), (dur * 0.75, -1), (dur, 0)):
                    zc.key(t, rot={"spine_01": (8, 0, 3 * a), "spine_02": (14, 0, -4 * a), "spine_03": (8, 0, 3 * a), "head": (10, 0, 16 * a), "pelvis": (4, 0, 0)},
                           hand={"l": V(0.2, -0.62, 1.30 + 0.05 * a) * sc, "r": V(-0.2, -0.60, 1.30 - 0.05 * a) * sc}, curl={"l": 40, "r": 40})
                for i in range(nout + 1):
                    k = (i / nout * nz) % nz
                    i0 = int(math.floor(k)) % nz; i1 = (i0 + 1) % nz; af = k - math.floor(k)
                    Rw = {}
                    for bn in Z[0][0]:
                        Rw[bn] = np.array(to_quat(Z[i0][0][bn]).slerp(to_quat(Z[i1][0][bn]), af).to_matrix())
                    loc = Z[i0][1] * (1 - af) + Z[i1][1] * af
                    # shuffle: reduce stride by blending legs toward rest slightly
                    spec = zc.eval((i % nout) / FPS)
                    q, l = pose_frame(rig, Rw, loc * 0.6, spec)
                    qs.append(q); locs.append(l)
                out["zombie_walk"] = (qs, locs)
    return out, meta


def add_all(rig, with_mocap=True, only=None):
    clips, meta = build_clips(rig, with_mocap)
    for name, (qs, locs) in clips.items():
        if only and name not in only: continue
        loop = name in ("idle", "aim_idle", "walk", "run", "zombie_idle", "zombie_walk", "crawl", "sit")
        write_action(rig, name, qs, locs, loop=loop)
    return meta
