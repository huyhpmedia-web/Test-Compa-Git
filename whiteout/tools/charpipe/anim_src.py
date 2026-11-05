"""Mocap sources -> retargeted `Take`s on the MakeHuman game_engine rig (bpy side).

Sources (all redistributable):
  * CMU Graphics Lab Motion Capture Database (BVH conversion, free for any use)
  * Quaternius Universal Animation Library "Standard" (CC0) as FBX
  * 100STYLE (CC BY 4.0) -- hook kept (bvh_take works on its BVH too) but the dataset is not reachable from the build box.

A Take stores, per frame, the *world delta rotation* of each bone relative to the source rest pose (already expressed in the
target rig's axes: +X left, -Y forward, +Z up) plus the pelvis location delta, and the source rest bone directions.
`finalize(rig, take)` aligns the target bones to those rest directions (same trick as anim.mocap_frames) and yields
`[(Rw, loc)]` frames ready for anim.pose_frame().  Takes can be mirrored, resampled, sliced, spliced.
"""
import math, os
import numpy as np
from mathutils import Matrix, Quaternion
from anim import MAP, FINGERS, C, FPS, swing, rot_axis, to_quat, pose_frame, write_action
from bvh import BVH

MIRROR = np.diag([-1.0, 1.0, 1.0])
_bvh_cache = {}


def _swap(b):
    if b.endswith("_l"): return b[:-2] + "_r"
    if b.endswith("_r"): return b[:-2] + "_l"
    return b


class Take:
    def __init__(self, D, loc, restdir, fps=FPS, name="", meta=None):
        self.D, self.loc, self.restdir, self.fps, self.name = D, loc, restdir, fps, name
        self.meta = meta or {}

    @property
    def n(self):
        return len(self.D)

    # ---- editing
    def mirrored(self):
        D = [{_swap(b): MIRROR @ R @ MIRROR for b, R in f.items()} for f in self.D]
        loc = [np.array([-l[0], l[1], l[2]]) for l in self.loc]
        rd = {_swap(b): MIRROR @ d for b, d in self.restdir.items()}
        return Take(D, loc, rd, self.fps, self.name + "_m", dict(self.meta))

    def _interp(self, x):
        n = self.n
        x = min(max(x, 0.0), n - 1.0)
        i0 = int(math.floor(x)); i1 = min(i0 + 1, n - 1); a = x - i0
        D = {}
        for b in self.D[i0]:
            if a < 1e-6 or i1 == i0:
                D[b] = self.D[i0][b]
            else:
                D[b] = np.array(to_quat(self.D[i0][b]).slerp(to_quat(self.D[i1][b]), a).to_matrix())
        return D, self.loc[i0] * (1 - a) + self.loc[i1] * a

    def sliced(self, t0, t1, fps=FPS, speed=1.0, name=None):
        """new take covering source seconds [t0, t1] sampled at `fps` (speed>1 plays faster)."""
        dur = (t1 - t0) / speed
        m = max(2, int(round(dur * fps)) + 1)
        D, loc = [], []
        for i in range(m):
            x = (t0 + i / fps * speed) * self.fps
            d, l = self._interp(x)
            D.append(d); loc.append(l)
        return Take(D, loc, self.restdir, fps, name or self.name, dict(self.meta))

    def looped(self):
        """drop the duplicate last frame (if any) so the take wraps cleanly."""
        return self

    def travel(self):
        """(distance, duration) of pelvis horizontal travel in the *source* (stored in meta by loaders)."""
        return self.meta.get("travel", 0.0), self.n / self.fps


def finalize(rig, take):
    Q = {}
    for tb, d in take.restdir.items():
        if tb in rig.rdir:
            Q[tb] = swing(rig.rdir[tb], d) @ rig.Rr[tb]
    out = []
    for D, loc in zip(take.D, take.loc):
        Rw = {tb: D[tb] @ Q[tb] for tb in D if tb in Q}
        out.append((Rw, loc))
    return out


def splice(rig, base, over, bones, w=1.0, hand_from_over=True):
    """blend finalized frames: bones (list) take `over`'s world rotation with weight w (slerp). Frame counts must match."""
    out = []
    for (Rb, lb), (Ro, lo) in zip(base, over):
        R = dict(Rb)
        for b in bones:
            if b in Ro and b in Rb:
                R[b] = np.array(to_quat(Rb[b]).slerp(to_quat(Ro[b]), w).to_matrix()) if w < 0.999 else Ro[b]
            elif b in Ro:
                R[b] = Ro[b]
        out.append((R, lb))
    return out


def blend_frames(A, B, w):
    """per-frame slerp between two finalized frame lists (same length)."""
    out = []
    for (Ra, la), (Rb, lb) in zip(A, B):
        R = {}
        for b in Ra:
            R[b] = np.array(to_quat(Ra[b]).slerp(to_quat(Rb[b]), w).to_matrix()) if b in Rb else Ra[b]
        out.append((R, la * (1 - w) + lb * w))
    return out


# ================================================================== BVH (CMU / 100STYLE)
def _bvh(path):
    if path not in _bvh_cache:
        b = BVH(path)
        _bvh_cache.clear()
        _bvh_cache[path] = (b, b.world_rots(), b.world_pos())
    return _bvh_cache[path]


def bvh_take(rig, path, f0=0, f1=None, xy="drift", yaw=None, name=None, heading_from=None, unyaw=False):
    """Retarget BVH frames [f0, f1) onto `rig`. xy: 'drift' (remove linear travel: loops), 'keep' (travel relative to frame 0),
    'zero' (in place). yaw: manual heading offset in degrees (default: align hips-left to +X at f0)."""
    b, W, P = _bvh(path)
    f1 = b.nframes if f1 is None else min(f1, b.nframes)
    leg_b = np.linalg.norm(b.offset[b.idx("LeftLeg")]) + np.linalg.norm(b.offset[b.idx("LeftFoot")])
    scale = rig.leg_len / leg_b
    Prest = b.rest_world_pos()

    def desc_dir(j):
        q = [j]
        while q:
            n = q.pop(0)
            for k, p in enumerate(b.parent):
                if p == n:
                    d = Prest[k] - Prest[j]
                    if np.linalg.norm(d) > 1e-4: return d
                    q.append(k)
        if j in b.endsite: return np.array(b.endsite[j])
        return None
    DIRJ = {"pelvis": "Spine", "spine_01": "Spine", "spine_02": "Spine1", "spine_03": "Neck1", "neck_01": "Neck1"}
    restdir = {}
    for tb, bj in MAP.items():
        j = b.idx(bj)
        d = (Prest[b.idx(DIRJ[tb])] - Prest[j]) if tb in DIRJ else desc_dir(j)
        if d is None: d = b.offset[j]
        restdir[tb] = C @ (d / np.linalg.norm(d))
    # heading alignment
    hips = b.idx("Hips")
    if yaw is None:
        lv = W[hips][heading_from if heading_from is not None else f0] @ np.array([1.0, 0, 0])
        lv = np.array([lv[0], 0, lv[2]]); lv /= max(np.linalg.norm(lv), 1e-6)
        c, s = lv[0], lv[2]
    else:
        c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    Ry = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
    # floor / standing hip height from the whole file
    lf, rf = b.idx("LeftFoot"), b.idx("RightFoot")
    floor_ankle = min(P[lf][:, 1].min(), P[rf][:, 1].min())
    y_stand = floor_ankle - Prest[lf][1]
    D, loc = [], []
    hp = (C @ (Ry @ P[hips][f0:f1].T)).T * scale          # blender axes, metres
    z = (P[hips][f0:f1, 1] - y_stand) * scale
    xyv = hp[:, :2] - hp[0, :2]
    if xy == "drift":
        t = np.linspace(0, 1, len(xyv))[:, None]
        xyv = xyv - (xyv[-1] - xyv[0]) * t
    elif xy == "zero":
        xyv = xyv * 0
    for k in range(f0, f1):
        f = {}
        if unyaw:
            lv = W[hips][k] @ np.array([1.0, 0, 0]); lv = np.array([lv[0], 0, lv[2]]); lv /= max(np.linalg.norm(lv), 1e-6)
            Ry = np.array([[lv[0], 0, lv[2]], [0, 1, 0], [-lv[2], 0, lv[0]]])
        for tb, bj in MAP.items():
            f[tb] = C @ Ry @ W[b.idx(bj)][k] @ C.T
        D.append(f)
        loc.append(np.array([xyv[k - f0, 0], xyv[k - f0, 1], z[k - f0]]))
    dist = float(np.linalg.norm(hp[-1, :2] - hp[0, :2]))
    return Take(D, loc, restdir, 1.0 / b.dt, name or os.path.basename(path), {"travel": dist, "src": os.path.basename(path)})


# ================================================================== armature actions (Quaternius UAL FBX)
class ArmSrc:
    """Imports an FBX with an armature + actions into the current Blender scene and samples its actions."""
    A = np.diag([-1.0, -1.0, 1.0])      # source (faces +Y, left = -X) -> target (faces -Y, left = +X)

    def __init__(self, rig, fbx_path):
        import bpy
        self.bpy = bpy
        before = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=fbx_path)
        new = [o for o in bpy.data.objects if o not in before]
        self.arm = [o for o in new if o.type == "ARMATURE"][0]
        for o in new:
            if o.type == "MESH": bpy.data.objects.remove(o, do_unlink=True)
        self.rig = rig
        mw = np.array(self.arm.matrix_world.to_3x3())
        self.mw = mw
        bones = self.arm.data.bones
        self.names = [x.name for x in bones]
        self.Rs0, self.head0, self.tail0 = {}, {}, {}
        for x in bones:
            M = np.array(x.matrix_local.to_3x3())
            self.Rs0[x.name] = self._ortho(mw @ M)
            self.head0[x.name] = mw @ np.array(x.head_local)
            self.tail0[x.name] = mw @ np.array(x.tail_local)
        self.leg_len = np.linalg.norm(self.head0["thigh_l"] - self.head0["calf_l"]) + np.linalg.norm(self.head0["calf_l"] - self.head0["foot_l"])
        self.scale = rig.leg_len / self.leg_len
        self.p_rest = self.A @ self.head0["pelvis"]
        self.bmap = {}
        for tb in list(MAP.keys()) + FINGERS:
            sb = "Head" if tb == "head" else tb
            if sb in bones: self.bmap[tb] = sb
        self.restdir = {}
        for tb, sb in self.bmap.items():
            self.restdir[tb] = self.A @ self._rest_dir(sb)
        self.actions = {a.name.split("|")[-1]: a for a in bpy.data.actions}

    @staticmethod
    def _ortho(M):
        q = Matrix(M.tolist()).to_quaternion()
        return np.array(q.to_matrix())

    def _rest_dir(self, sb):
        bones = self.arm.data.bones
        if sb == "pelvis":
            d = self.head0["spine_01"] - self.head0["pelvis"]
        elif sb == "hand_l" or sb == "hand_r":
            d = self.head0["middle_01" + sb[-2:]] - self.head0[sb]
        else:
            ch = [c.name for c in bones[sb].children if np.linalg.norm(self.head0[c.name] - self.head0[sb]) > 1e-4]
            ch = [c for c in ch if not c.endswith("_leaf_l") or True]
            d = (self.head0[ch[0]] - self.head0[sb]) if ch else (self.tail0[sb] - self.head0[sb])
        return d / np.linalg.norm(d)

    def take(self, action, f0=None, f1=None, xy="zero", name=None, fps_src=24.0, drop_last=False):
        bpy = self.bpy
        act = self.actions[action]
        ad = self.arm.animation_data or self.arm.animation_data_create()
        ad.action = act
        try:
            ad.action_slot = act.slots[0]
        except Exception:
            pass
        s, e = act.frame_range
        f0 = s if f0 is None else f0
        f1 = e if f1 is None else f1
        frames = list(range(int(round(f0)), int(round(f1)) + 1))
        if drop_last and len(frames) > 1:
            frames = frames[:-1]
        pel = self.arm.pose.bones["pelvis"]
        D, loc = [], []
        for fr in frames:
            bpy.context.scene.frame_set(fr)
            bpy.context.view_layer.update()
            d = {}
            for tb, sb in self.bmap.items():
                M = self._ortho(self.mw @ np.array(self.arm.pose.bones[sb].matrix.to_3x3()))
                d[tb] = self.A @ (M @ self.Rs0[sb].T) @ self.A.T
            pw = self.A @ (self.mw @ np.array(pel.head))
            D.append(d)
            loc.append((pw - self.p_rest) * self.scale)
        loc = [np.array(l) for l in loc]
        if xy == "zero":
            loc = [np.array([0.0, 0.0, l[2]]) for l in loc]
        elif xy == "drift":
            n = len(loc)
            l0, l1 = loc[0].copy(), loc[-1].copy()
            loc = [l - np.array([(l1[0] - l0[0]) * i / max(n - 1, 1) + l0[0], (l1[1] - l0[1]) * i / max(n - 1, 1) + l0[1], 0]) for i, l in enumerate(loc)]
        elif xy == "keep":
            l0 = loc[0].copy()
            loc = [l - np.array([l0[0], l0[1], 0]) for l in loc]
        t = Take(D, loc, self.restdir, fps_src, name or action, {"src": action})
        return t


# ================================================================== emit
def emit(rig, frames, name, loop, spec_fn=None, close=True):
    """frames: [(Rw, loc)] (finalized). spec_fn(i, n) -> pose_frame spec overlay. Returns the written action."""
    n = len(frames)
    qs, locs = [], []
    rng = list(range(n)) + ([0] if (loop and close) else [])
    for k, i in enumerate(rng):
        Rw, lc = frames[i]
        spec = spec_fn(k, n) if spec_fn else {}
        q, l = pose_frame(rig, Rw, lc, spec)
        qs.append(q); locs.append(l)
    return write_action(rig, name, qs, locs, loop=loop)


def find_loop(path, lo=0.7, hi=1.6, region=None):
    """best [f0, f1) frame pair of a BVH whose pose matches (cyclic locomotion). region=(t0,t1) seconds."""
    b, W, P = _bvh(path)
    names = ["LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot", "LeftArm", "RightArm", "Spine1", "Head"]
    feat = np.concatenate([W[b.idx(n)].reshape(b.nframes, 9) for n in names], axis=1)
    a0, a1 = 0, b.nframes
    if region:
        a0, a1 = int(region[0] / b.dt), min(b.nframes, int(region[1] / b.dt))
    feat = feat[a0:a1]
    best = (1e9, 0, 0)
    step = max(1, int(round(0.01 / b.dt)))
    for L in range(int(lo / b.dt), int(hi / b.dt) + 1, step):
        if L >= len(feat): break
        e = np.linalg.norm(feat[:-L:step] - feat[L::step], axis=1)
        i = int(np.argmin(e))
        if e[i] < best[0]:
            best = (float(e[i]), a0 + i * step, a0 + i * step + L)
    return best[1], best[2], best[0]


def make_loop(frames, blend):
    """seamless loop from a non-looping frame list: crossfade the last `blend` frames into the first ones."""
    n = len(frames)
    m = n - blend
    out = []
    for j in range(m):
        if j < blend:
            w = (j + 1) / (blend + 1)
            R = {}
            Ra, la = frames[m + j]; Rb, lb = frames[j]
            for bn in Rb:
                R[bn] = np.array(to_quat(Ra[bn]).slerp(to_quat(Rb[bn]), w).to_matrix()) if bn in Ra else Rb[bn]
            out.append((R, la * (1 - w) + lb * w))
        else:
            out.append(frames[j])
    return out
