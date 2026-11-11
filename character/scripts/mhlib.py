"""MakeHuman (hm08) base mesh, target and rig loader -- pure numpy, no bpy.

The base mesh and all targets are CC0 (see mh_data/LICENSE.CC0.md).
Coordinates are converted to Blender convention on load: Z up, -Y front, metres.
"""
import gzip
import json
import os
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MH_DATA = os.path.join(ROOT, "mh_data")
# Full target library (only needed when (re)building the shape from scratch).
MPFB_TARGETS = os.environ.get(
    "MPFB_TARGETS", "/home/user/makehumancommunity/mpfb2/src/mpfb/data/targets")
SCALE = 0.1  # MakeHuman decimetres -> metres

N_BODY = 13380  # vertices 0..13379 are the skin; the rest are helpers / joint cubes


def mh_to_bl(v):
    """(x, y, z) MakeHuman Y-up -> Blender Z-up, metres."""
    v = np.asarray(v, dtype=np.float64)
    out = np.empty_like(v)
    out[..., 0] = v[..., 0]
    out[..., 1] = -v[..., 2]
    out[..., 2] = v[..., 1]
    return out * SCALE


class BaseMesh:
    def __init__(self, path=None):
        path = path or os.path.join(MH_DATA, "base.obj")
        verts, uvs, faces, fuvs, fgroups = [], [], [], [], []
        group = "body"
        with open(path) as fh:
            for line in fh:
                if line.startswith("v "):
                    verts.append([float(x) for x in line.split()[1:4]])
                elif line.startswith("vt "):
                    uvs.append([float(x) for x in line.split()[1:3]])
                elif line.startswith("g "):
                    group = line.split()[1]
                elif line.startswith("f "):
                    vi, ti = [], []
                    for tok in line.split()[1:]:
                        a = tok.split("/")
                        vi.append(int(a[0]) - 1)
                        ti.append(int(a[1]) - 1 if len(a) > 1 and a[1] else -1)
                    faces.append(vi)
                    fuvs.append(ti)
                    fgroups.append(group)
        self.raw = np.array(verts, dtype=np.float64)          # MakeHuman space
        self.uvs = np.array(uvs, dtype=np.float64)
        self.faces = faces
        self.face_uvs = fuvs
        self.face_groups = fgroups
        with open(os.path.join(MH_DATA, "basemesh_vertex_groups.json")) as fh:
            self.vgroups = json.load(fh)
        self.mirror = np.arange(len(self.raw))
        with open(os.path.join(MH_DATA, "hm08.mirror")) as fh:
            for line in fh:
                a = line.split()
                if len(a) >= 2:
                    self.mirror[int(a[0])] = int(a[1])

    def group_indices(self, name):
        idx = []
        for a, b in self.vgroups[name]:
            idx.extend(range(a, b + 1))
        return np.array(idx, dtype=np.int64)

    def body_faces(self):
        """Indices of faces that belong to the skin ('body' group)."""
        return [i for i, g in enumerate(self.face_groups) if g == "body"]


def load_target(name):
    """Return (indices, deltas[MakeHuman space]) for a target, e.g. 'nose/nose-point-up'."""
    for base in (os.path.join(MH_DATA, "targets"), MPFB_TARGETS):
        p = os.path.join(base, name + ".target.gz")
        if os.path.exists(p):
            raw = gzip.open(p, "rt").read()
            break
    else:
        raise FileNotFoundError(name)
    if not raw.strip():
        return np.zeros(0, dtype=np.int64), np.zeros((0, 3))
    arr = np.array([[float(x) for x in ln.split()[:4]]
                    for ln in raw.splitlines() if ln.strip() and not ln.startswith("#")])
    return arr[:, 0].astype(np.int64), arr[:, 1:4]


# --------------------------------------------------------------------------- macros
_MACRO_PARTS = {
    "gender": [(-0.01, 1.01, "female", "male")],
    "age": [(-0.01, 0.1874998, "baby", "child"), (0.1874999, 0.49998, "child", "young"),
            (0.49999, 1.01, "young", "old")],
    "muscle": [(-0.01, 0.49998, "minmuscle", "averagemuscle"),
               (0.49999, 1.01, "averagemuscle", "maxmuscle")],
    "weight": [(-0.01, 0.49998, "minweight", "averageweight"),
               (0.49999, 1.01, "averageweight", "maxweight")],
    "proportions": [(-0.01, 0.4999, "uncommonproportions", ""), (0.5, 1.01, "", "idealproportions")],
    "height": [(-0.01, 0.49, "minheight", ""), (0.51, 1.01, "", "maxheight")],
    "cupsize": [(-0.01, 0.49998, "mincup", "averagecup"), (0.49999, 1.01, "averagecup", "maxcup")],
    "firmness": [(-0.01, 0.4998, "minfirmness", "averagefirmness"),
                 (0.4999, 1.01, "averagefirmness", "maxfirmness")],
}


def _components(name, value):
    out = []
    for lowest, highest, low, high in _MACRO_PARTS[name]:
        if lowest < value < highest:
            pct = (value - lowest) / (highest - lowest)
            if low:
                out.append((low, round(1 - pct, 4)))
            if high:
                out.append((high, round(pct, 4)))
    return out


def macro_stack(m, cutoff=0.01):
    """Port of MPFB TargetService.calculate_target_stack_from_macro_info_dict."""
    c = {k: _components(k, m[k]) for k in _MACRO_PARTS}
    out = []
    for race, rw in m["race"].items():
        if rw > 1e-4:
            for an, aw in c["age"]:
                for gn, gw in c["gender"]:
                    w = rw * gw * aw
                    if w > cutoff:
                        out.append((f"macrodetails/{race}-{gn}-{an}", w))
    for gn, gw in c["gender"]:
        for an, aw in c["age"]:
            for mn, mw in c["muscle"]:
                for wn, ww in c["weight"]:
                    base = gw * aw * mw * ww
                    if base > cutoff:
                        out.append((f"macrodetails/universal-{gn}-{an}-{mn}-{wn}", base))
                    for hn, hw in c["height"]:
                        if base * hw > cutoff:
                            out.append((f"macrodetails/height/{gn}-{an}-{mn}-{wn}-{hn}", base * hw))
                    for pn, pw in c["proportions"]:
                        if base * pw > cutoff and an != "baby":
                            out.append((f"macrodetails/proportions/{gn}-{an}-{mn}-{wn}-{pn}", base * pw))
                    if gn == "female" and an != "baby":
                        for cn, cw in c["cupsize"]:
                            for fn, fw in c["firmness"]:
                                w = aw * mw * ww * cw * fw
                                if w > cutoff and not (cn == "averagecup" and fn == "averagefirmness"):
                                    out.append((f"breast/{gn}-{an}-{mn}-{wn}-{cn}-{fn}", w))
    return out


def build_shape(base, macros, details=None):
    """Apply macro + detail targets. Returns vertex positions in Blender space (metres)."""
    v = base.raw.copy()
    stack = macro_stack(macros) + list((details or {}).items())
    for name, w in stack:
        idx, d = load_target(name)
        if len(idx):
            v[idx] += d * w
    return mh_to_bl(v), stack


# --------------------------------------------------------------------------- rig
def joint_positions(base, verts_bl):
    """Centre of every joint cube -> {name: xyz}."""
    out = {}
    for name in base.vgroups:
        if name.startswith("joint-"):
            out[name] = verts_bl[base.group_indices(name)].mean(axis=0)
    return out


def load_rig(base, verts_bl):
    """Returns (bones, weights). bones: {name: dict(head, tail, roll, parent)}."""
    with open(os.path.join(MH_DATA, "rig.default.json")) as fh:
        rig = json.load(fh)
    with open(os.path.join(MH_DATA, "weights.default.json")) as fh:
        weights = json.load(fh)["weights"]
    joints = joint_positions(base, verts_bl)

    def pos(spec):
        s = spec["strategy"]
        if s == "CUBE":
            return joints[spec["cube_name"]]
        if s == "VERTEX":
            return verts_bl[spec["vertex_index"]]
        if s == "MEAN":
            return verts_bl[spec["vertex_indices"]].mean(axis=0)
        return np.array(spec["default_position"])

    bones = {}
    for name, b in rig.items():
        bones[name] = dict(head=pos(b["head"]), tail=pos(b["tail"]), roll=b.get("roll", 0.0),
                           parent=b.get("parent") or None, connect=b.get("use_connect", False))
    return bones, weights
