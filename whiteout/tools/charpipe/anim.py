"""Animation retargeting + procedural keyframe authoring for the MakeHuman game_engine rig (bpy side).

Motion sources: CMU Graphics Lab Motion Capture Database (free for any use, via the cgspeed BVH conversion
mirrored at github.com/una-dinosauria/cmu-mocap):  35_01 (walk), 09_01 (run).
Everything else (aim, shoot, reload, hurt, death, melee, zombie, crawl, sit, idle) is authored here as
direction/rotation keyframes on top of the same machinery (and zombie_walk layers a hunched zombie
upper body over the mocap walk legs)."""
import math
import numpy as np
import bpy
from mathutils import Matrix, Vector, Quaternion
from bvh import BVH

FPS = 30

# target bone -> BVH joint (rotation source)
MAP = {"pelvis": "Hips", "spine_01": "LowerBack", "spine_02": "Spine", "spine_03": "Spine1",
       "neck_01": "Neck", "head": "Head",
       "clavicle_l": "LeftShoulder", "upperarm_l": "LeftArm", "lowerarm_l": "LeftForeArm", "hand_l": "LeftHand",
       "clavicle_r": "RightShoulder", "upperarm_r": "RightArm", "lowerarm_r": "RightForeArm", "hand_r": "RightHand",
       "thigh_l": "LeftUpLeg", "calf_l": "LeftLeg", "foot_l": "LeftFoot", "ball_l": "LeftToeBase",
       "thigh_r": "RightUpLeg", "calf_r": "RightLeg", "foot_r": "RightFoot", "ball_r": "RightToeBase"}

FINGERS = [f"{f}_{i:02d}_{s}" for f in ("thumb", "index", "middle", "ring", "pinky") for i in (1, 2, 3) for s in ("l", "r")]

# BVH (Y up, +Z fwd) -> Blender (Z up, -Y fwd)
C = np.array([[1, 0, 0], [0, 0, -1], [0, 1, 0]], dtype=float)


def swing(a, b):
    """minimal rotation matrix taking unit vector a to b"""
    a = a / np.linalg.norm(a); b = b / np.linalg.norm(b)
    v = np.cross(a, b); c = float(np.dot(a, b))
    if c < -0.999999:
        ax = np.cross(a, [1, 0, 0]) if abs(a[0]) < 0.9 else np.cross(a, [0, 1, 0])
        ax /= np.linalg.norm(ax)
        return 2 * np.outer(ax, ax) - np.eye(3)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx * (1.0 / (1.0 + c))


def rot_axis(axis, deg):
    a = math.radians(deg); c, s = math.cos(a), math.sin(a)
    if axis == 0: return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
    if axis == 1: return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def rot_xyz(rx, ry, rz):
    return rot_axis(2, rz) @ rot_axis(1, ry) @ rot_axis(0, rx)


def to_quat(R):
    return Matrix(R.tolist()).to_quaternion()


class Rig:
    def __init__(self, arm_ob):
        self.ob = arm_ob
        self.bones = [b.name for b in arm_ob.data.bones]
        self.parent = {b.name: (b.parent.name if b.parent else None) for b in arm_ob.data.bones}
        self.Rr = {b.name: np.array(b.matrix_local.to_3x3()) for b in arm_ob.data.bones}
        self.head = {b.name: np.array(b.head_local) for b in arm_ob.data.bones}
        self.tail = {b.name: np.array(b.tail_local) for b in arm_ob.data.bones}
        self.rdir = {b: (self.tail[b] - self.head[b]) / np.linalg.norm(self.tail[b] - self.head[b]) for b in self.bones}
        self.children = {b: [c for c in self.bones if self.parent[c] == b] for b in self.bones}
        # hierarchy order
        self.order = []
        def add(b):
            if b in self.order: return
            if self.parent[b]: add(self.parent[b])
            self.order.append(b)
        for b in self.bones: add(b)
        self.leg_len = np.linalg.norm(self.head["calf_l"] - self.head["thigh_l"]) + np.linalg.norm(self.head["foot_l"] - self.head["calf_l"])
        self.hip_h = self.head["pelvis"][2]

    def rest_rel(self, b):
        p = self.parent[b]
        return self.Rr[b] if p is None else self.Rr[p].T @ self.Rr[b]

    def descendants(self, b):
        out = []
        for c in self.children[b]:
            out.append(c); out += self.descendants(c)
        return out

    # ---- frame solving ----
    def solve(self, Rw, loc=None, local_override=None):
        """Rw: dict bone-> world rotation (3x3, armature space) for specified bones; others follow parent.
        returns {bone: quaternion basis}, pelvis/root location delta"""
        full = {}
        basis = {}
        for b in self.order:
            p = self.parent[b]
            rr = self.rest_rel(b)
            if b in Rw:
                R = Rw[b]
            else:
                R = (full[p] @ rr) if p else self.Rr[b]
            full[b] = R
            if local_override and b in local_override:
                B = local_override[b]
                full[b] = (full[p] @ rr @ B) if p else (self.Rr[b] @ B)
                basis[b] = B
            else:
                B = (rr.T @ full[p].T @ R) if p else (self.Rr[b].T @ R)
                basis[b] = B
        return basis, full


def finger_local(rig, curl, thumb=None, spread=0.0):
    """local basis rotations for finger bones; curl in degrees (all joints scaled)."""
    out = {}
    for f in FINGERS:
        part = f.split("_")[0]; i = int(f.split("_")[1])
        k = curl if part != "thumb" else (thumb if thumb is not None else curl * 0.6)
        scale = (0.6, 1.0, 0.8)[i - 1]
        side = -1.0 if f.endswith("_r") else 1.0
        out[f] = rot_axis(0, k * scale)   # curl about local X (checked visually)
    return out


# ------------------------------------------------------------------ mocap
def mocap_frames(rig, bvh_path, f0, f1, speed_scale=1.0):
    """-> list of per-frame (Rw dict, hips loc delta), plus root speed in m/s (in-place)."""
    b = BVH(bvh_path)
    W = b.world_rots()
    P = b.rest_world_pos()
    # BVH rest directions (blender axes)
    def desc_dir(j):
        # first descendant (BFS) at non-zero distance, or end site
        q = [j]
        while q:
            n = q.pop(0)
            for k, p in enumerate(b.parent):
                if p == n:
                    d = P[k] - P[j]
                    if np.linalg.norm(d) > 1e-4: return d
                    q.append(k)
        if j in b.endsite: return np.array(b.endsite[j])
        return None
    leg_b = np.linalg.norm(b.offset[b.idx("LeftLeg")]) + np.linalg.norm(b.offset[b.idx("LeftFoot")])
    scale = rig.leg_len / leg_b
    DIRJ = {"pelvis": "Spine", "spine_01": "Spine", "spine_02": "Spine1", "spine_03": "Neck1", "neck_01": "Neck1"}
    Q = {}
    for tb, bj in MAP.items():
        j = b.idx(bj)
        if tb in DIRJ:
            d = P[b.idx(DIRJ[tb])] - P[j]
        else:
            d = desc_dir(j)
        if d is None:
            d = b.offset[j]
        Q[tb] = swing(rig.rdir[tb], C @ (d / np.linalg.norm(d))) @ rig.Rr[tb]
    frames = []
    pos = b.pos[f0:f1] * scale
    hips = pos.copy()
    # horizontal: remove drift (in place), keep vertical + sway
    hb = (C @ hips.T).T            # blender axes
    n = len(hb)
    t = np.linspace(0, 1, n)[:, None]
    drift = hb[0] + (hb[-1] - hb[0]) * t
    hb_xy = hb[:, :2] - drift[:, :2]
    dist = np.linalg.norm(((C @ (b.pos[f1 - 1] - b.pos[f0]) * scale)))
    dur = (f1 - f0) * b.dt
    spd = dist / dur
    hz = hb[:, 2] - hb[:, 2].mean() + rig.hip_h * 0 
    for k in range(f0, f1):
        Rw = {}
        for tb, bj in MAP.items():
            j = b.idx(bj)
            Rw[tb] = C @ W[j][k] @ C.T @ Q[tb]
        loc = np.array([hb_xy[k - f0, 0], hb_xy[k - f0, 1], hz[k - f0]])
        frames.append((Rw, loc))
    return frames, spd, b.dt


def find_loop(bvh_path, rig_dummy=None, min_len=0.8, max_len=1.6, start_hint=0):
    """pick [f0,f1) with the best pose match for a cyclic walk/run"""
    b = BVH(bvh_path); W = b.world_rots()
    names = ["LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot", "LeftArm", "RightArm", "Spine1", "Head"]
    feat = np.concatenate([W[b.idx(n)].reshape(b.nframes, 9) for n in names], axis=1)
    n = b.nframes
    lo = int(min_len / b.dt); hi = int(max_len / b.dt)
    best = (1e9, 0, lo)
    for s in range(start_hint, max(start_hint + 1, n - hi - 1), 1):
        for L in range(lo, hi + 1):
            if s + L >= n: break
            e = np.linalg.norm(feat[s] - feat[s + L])
            if e < best[0]: best = (e, s, s + L)
    return best[1], best[2], best[0]


def resample(frames, dt, n_out=None, fps=FPS):
    """linear resample of a looping frame list (Rw dict, loc) to FPS (slerp via matrix->quat)."""
    n = len(frames)
    dur = n * dt
    n_out = n_out or max(2, int(round(dur * fps)))
    out = []
    for i in range(n_out):
        x = i / n_out * n          # loop position
        i0 = int(math.floor(x)) % n; i1 = (i0 + 1) % n; a = x - math.floor(x)
        Rw = {}
        for bn in frames[0][0]:
            q0 = to_quat(frames[i0][0][bn]); q1 = to_quat(frames[i1][0][bn])
            Rw[bn] = np.array(q0.slerp(q1, a).to_matrix())
        loc = frames[i0][1] * (1 - a) + frames[i1][1] * a
        out.append((Rw, loc))
    return out


# ================================================================== authoring engine
def ik2(S, T, l1, l2, pole):
    """two-bone IK: returns elbow position given shoulder S, target T (clamped), pole hint direction."""
    d = T - S; dist = np.linalg.norm(d)
    dist = min(dist, (l1 + l2) * 0.999); dn = d / max(np.linalg.norm(d), 1e-9)
    a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(l1 * l1 - a * a, 1e-9))
    p = pole - dn * np.dot(pole, dn)
    if np.linalg.norm(p) < 1e-6: p = np.array([0, 0, -1.0])
    p = p / np.linalg.norm(p)
    return S + dn * a + p * h


class Clip:
    """keyframe tracks:  ('rot', bone) -> (rx,ry,rz) deg world-axis rotation (propagates to children, applied
    in hierarchy order);  ('dir', bone) -> world unit direction (propagates);  ('twist', bone) -> deg about bone axis;
    ('hand', 'l'|'r') -> world target position of the wrist (two-bone IK on the arm);  ('loc','pelvis') -> m;
    ('root', 'rot') -> deg rotation of the whole body about the feet;  ('curl','l'|'r') -> finger curl deg."""

    def __init__(self, name, dur, loop=True):
        self.name, self.dur, self.loop = name, dur, loop
        self.tr = {}

    def key(self, t, **spec):
        for k, v in spec.items():
            if k in ("rot", "dir", "twist"):
                for b, val in v.items():
                    self.tr.setdefault((k, b), []).append((t, np.atleast_1d(np.array(val, dtype=float))))
            elif k == "hand":
                for s, val in v.items():
                    self.tr.setdefault(("hand", s), []).append((t, np.array(val, dtype=float)))
            elif k == "curl":
                for s, val in v.items():
                    self.tr.setdefault(("curl", s), []).append((t, np.array(val if hasattr(val, '__len__') else [val], dtype=float)))
            else:
                self.tr.setdefault((k, "_"), []).append((t, np.array(v, dtype=float)))
        return self

    def sample(self, track, t):
        pts = sorted(track, key=lambda p: p[0])
        n = len(pts)
        if n == 1: return pts[0][1]
        T = [p[0] for p in pts]; V = [p[1] for p in pts]
        if self.loop:
            if t < T[0] or t >= T[-1]:
                pass
        if t <= T[0] and not self.loop: return V[0]
        if t >= T[-1] and not self.loop: return V[-1]
        # find segment
        if self.loop:
            span = self.dur
            tt = t % span
            T2 = [T[-1] - span] + T + [T[0] + span]
            V2 = [V[-1]] + V + [V[0]]
            if T[0] > 1e-6 and abs(T[-1] - span) > 1e-6:
                pass
            i = max(j for j in range(len(T2) - 1) if T2[j] <= tt) if tt >= T2[0] else 0
            T, V = T2, V2; t = tt
            idx = i
        else:
            idx = max(j for j in range(n - 1) if T[j] <= t)
            T2 = [T[0] - 1] + T + [T[-1] + 1]; V2 = [V[0]] + V + [V[-1]]
            idx += 1; T, V = T2, V2
        t0, t1 = T[idx], T[idx + 1]
        a = (t - t0) / max(t1 - t0, 1e-9)
        p0, p1 = V[idx], V[idx + 1]
        m0 = (p1 - V[idx - 1]) / max(T[idx + 1] - T[idx - 1], 1e-9) * (t1 - t0) if idx - 1 >= 0 else (p1 - p0)
        m1 = (V[idx + 2] - p0) / max(T[idx + 2] - T[idx], 1e-9) * (t1 - t0) if idx + 2 < len(V) else (p1 - p0)
        a2, a3 = a * a, a * a * a
        return (2 * a3 - 3 * a2 + 1) * p0 + (a3 - 2 * a2 + a) * m0 + (-2 * a3 + 3 * a2) * p1 + (a3 - a2) * m1

    def eval(self, t):
        out = {}
        for k, tr in self.tr.items():
            out[k] = self.sample(tr, t)
        return out


def fk_pos(rig, full, ploc):
    pos = {}
    for b in rig.order:
        p = rig.parent[b]
        if p is None:
            pos[b] = rig.head[b] + ploc * 0
        else:
            pos[b] = pos[p] + full[p] @ (rig.Rr[p].T @ (rig.head[b] - rig.head[p]))
        if b == "pelvis":
            pos[b] = pos[b] + ploc
    # children of pelvis inherit via full chain; recompute properly
    pos = {}
    for b in rig.order:
        p = rig.parent[b]
        if p is None:
            pos[b] = rig.head[b].copy()
        else:
            pos[b] = pos[p] + full[p] @ (rig.Rr[p].T @ (rig.head[b] - rig.head[p]))
            if b == "pelvis":
                pos[b] = pos[b] + ploc
    return pos


def pose_frame(rig, base_Rw, base_loc, spec, curl_default=(12.0, 12.0)):
    """build final per-bone basis quaternions for one frame."""
    ploc = np.array(base_loc if base_loc is not None else [0, 0, 0], dtype=float)
    # FK from absolute base
    full = {}
    for b in rig.order:
        p = rig.parent[b]
        if b in base_Rw: full[b] = base_Rw[b]
        else: full[b] = (full[p] @ rig.rest_rel(b)) if p else rig.Rr[b]
    def prop(b, D):
        full[b] = D @ full[b]
        for d in rig.descendants(b):
            full[d] = D @ full[d]
    # whole body rotation about the feet
    if ("root", "_") in spec:
        rx, ry, rz = spec[("root", "_")]
        D = rot_xyz(rx, ry, rz)
        for b in rig.order:
            full[b] = D @ full[b]
        rootD = D
    else:
        rootD = np.eye(3)
    for b in rig.order:
        if ("rot", b) in spec:
            rx, ry, rz = spec[("rot", b)]
            if abs(rx) + abs(ry) + abs(rz) > 1e-6:
                prop(b, rot_xyz(rx, ry, rz))
        if ("twist", b) in spec:
            ax = full[b][:, 1]
            ang = math.radians(float(spec[("twist", b)][0]))
            K = np.array([[0, -ax[2], ax[1]], [ax[2], 0, -ax[0]], [-ax[1], ax[0], 0]])
            prop(b, np.eye(3) + math.sin(ang) * K + (1 - math.cos(ang)) * K @ K)
        if ("dir", b) in spec:
            d = spec[("dir", b)]
            prop(b, swing(full[b][:, 1], d / np.linalg.norm(d)))
        # arm IK once the shoulder (upperarm) is reached
    for s in ("l", "r"):
        if ("hand", s) in spec:
            ua, la = f"upperarm_{s}", f"lowerarm_{s}"
            pos = fk_pos(rig, full, rootD @ ploc if False else ploc)
            S = pos[ua]
            l1 = np.linalg.norm(rig.head[la] - rig.head[ua]); l2 = np.linalg.norm(rig.head[f"hand_{s}"] - rig.head[la])
            T = spec[("hand", s)]
            pole = np.array([0.25 if s == "l" else -0.25, 0.55, -1.0])
            E = ik2(S, T, l1, l2, pole)
            prop(ua, swing(full[ua][:, 1], E - S))
            pos = fk_pos(rig, full, ploc)
            prop(la, swing(full[la][:, 1], T - pos[la]) if np.linalg.norm(T - pos[la]) > 1e-6 else np.eye(3))
        if ("hdir", s) in spec:
            pass
    # fingers (local)
    Bf = {}
    for s in ("l", "r"):
        c = np.atleast_1d(spec.get(("curl", s), np.array(curl_default[0])))
        k = float(c[0]) if len(c) else curl_default[0]
        kt = float(c[1]) if len(c) > 1 else k * 0.6
        for f in FINGERS:
            if not f.endswith("_" + s): continue
            part = f.split("_")[0]; i = int(f.split("_")[1])
            kk = kt if part == "thumb" else k
            Bf[f] = rot_axis(0, kk * (0.6, 1.0, 0.8)[i - 1])
    basis = {}
    for b in rig.order:
        p = rig.parent[b]
        rr = rig.rest_rel(b)
        if b in Bf:
            full[b] = full[p] @ rr @ Bf[b]
            basis[b] = Bf[b]
        else:
            basis[b] = (rr.T @ full[p].T @ full[b]) if p else (rig.Rr[b].T @ full[b])
    # pelvis location delta
    if ("loc", "_") in spec:
        ploc = ploc + spec[("loc", "_")]
    ploc_local = rig.Rr["pelvis"].T @ ploc
    pose_frame.last = (full, ploc)
    return {b: to_quat(basis[b]) for b in rig.order}, ploc_local


def idle_base(rig):
    """neutral relaxed standing pose: arms hang down at the sides."""
    return None


def write_action(rig, name, frames_q, frames_loc, fps=FPS, loop=True):
    """frames_q: list of {bone: quat}; frames_loc: list of pelvis local loc."""
    ob = rig.ob
    act = bpy.data.actions.new(name)
    n = len(frames_q)
    # keep quaternion hemisphere continuity
    for bn in rig.order:
        prev = None
        for i in range(n):
            q = frames_q[i][bn]
            if prev is not None and prev.dot(q) < 0:
                q = Quaternion((-q.w, -q.x, -q.y, -q.z)); frames_q[i][bn] = q
            prev = q
    ob.animation_data_create()
    ob.animation_data.action = act
    slot = act.slots.new('OBJECT', ob.name)
    ob.animation_data.action_slot = slot
    from bpy_extras import anim_utils
    cbag = anim_utils.action_ensure_channelbag_for_slot(act, slot)
    def fc_new(path, idx):
        return cbag.fcurves.new(data_path=path, index=idx)
    times = np.arange(n) * (FPS / fps) + 1
    for bn in rig.order:
        path = f'pose.bones["{bn}"].rotation_quaternion'
        arr = np.array([[frames_q[i][bn].w, frames_q[i][bn].x, frames_q[i][bn].y, frames_q[i][bn].z] for i in range(n)])
        for k in range(4):
            fc = fc_new(path, k)
            fc.keyframe_points.add(n)
            co = np.stack([times, arr[:, k]], axis=1).flatten()
            fc.keyframe_points.foreach_set("co", co)
    path = 'pose.bones["pelvis"].location'
    arr = np.array(frames_loc)
    for k in range(3):
        fc = fc_new(path, k)
        fc.keyframe_points.add(n)
        fc.keyframe_points.foreach_set("co", np.stack([times, arr[:, k]], axis=1).flatten())
    act.use_fake_user = True
    ob.animation_data.action = None
    # NLA track so the glTF exporter emits it by name
    tr = ob.animation_data.nla_tracks.new(); tr.name = name
    st = tr.strips.new(name, 1, act); st.name = name
    try: st.action_slot = slot
    except Exception: pass
    act.use_frame_range = True; act.frame_start = 1; act.frame_end = n if not loop else n
    return act
