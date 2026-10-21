"""MakeHuman data helpers (pure numpy, no bpy): base mesh, targets, macro blending,
mhclo proxy fitting, skeleton joint solving.  All MakeHuman data used here is CC0
(see assets/characters/LICENSES.md)."""
import os, re, json, gzip
import numpy as np

CACHE = os.environ.get("CHARPIPE_CACHE",
    "/tmp/claude-0/-home-user-Test-Compa-Git/b7d788c3-cd16-57ba-98fb-70cb388fdafd/scratchpad/charpipe")
MH_DATA = os.path.join(CACHE, "mh/makehuman/makehuman/data")
MPFB_DATA = os.path.join(CACHE, "mh/mpfb2/src/mpfb/data")
ASSETS = os.path.join(CACHE, "assets")
N_BODY = 13380          # base mesh body vertices (rest are helper geometry)


def load_obj(path):
    """-> verts (N,3), uvs (M,2), faces [(vi list, ti list)], groups {name: [face idx]}"""
    V, T, F, G = [], [], [], {}
    cur = None
    with open(path, "r", errors="replace") as f:
        for ln in f:
            if ln.startswith("v "):
                V.append([float(x) for x in ln.split()[1:4]])
            elif ln.startswith("vt "):
                T.append([float(x) for x in ln.split()[1:3]])
            elif ln.startswith("g "):
                cur = ln.split()[1]
                G.setdefault(cur, [])
            elif ln.startswith("f "):
                vi, ti = [], []
                for tok in ln.split()[1:]:
                    p = tok.split("/")
                    vi.append(int(p[0]) - 1)
                    ti.append(int(p[1]) - 1 if len(p) > 1 and p[1] else -1)
                F.append((vi, ti))
                G.setdefault(cur, []).append(len(F) - 1)
    return np.array(V, dtype=np.float64), np.array(T, dtype=np.float64).reshape(-1, 2), F, G


def load_target(path):
    idx, dl = [], []
    op = gzip.open if path.endswith(".gz") else open
    with op(path, "rt", errors="replace") as f:
        for ln in f:
            if not ln.strip() or ln.startswith("#"):
                continue
            p = ln.split()
            if len(p) >= 4:
                idx.append(int(p[0])); dl.append([float(p[1]), float(p[2]), float(p[3])])
    return np.array(idx, dtype=np.int64), np.array(dl, dtype=np.float64).reshape(-1, 3)


class Human:
    """Base mesh + target blending, MakeHuman macro-modifier logic."""

    def __init__(self):
        self.base_v, self.uv, self.faces_all, self.groups = load_obj(os.path.join(MH_DATA, "3dobjs/base.obj"))
        self.body_faces = [self.faces_all[i] for i in self.groups["body"]]
        self.v = self.base_v.copy()
        self._tcache = {}
        vg = json.load(open(os.path.join(MPFB_DATA, "mesh_metadata/basemesh_vertex_groups.json")))
        self.vgroups = {k: (np.array(v)[:, 0] if np.array(v).ndim == 2 else np.array(v)).astype(np.int64) for k, v in vg.items()}

    def _target(self, rel):
        p = os.path.join(MH_DATA, "targets", rel)
        if not os.path.exists(p):
            return None
        if p not in self._tcache:
            self._tcache[p] = load_target(p)
        return self._tcache[p]

    def add_target(self, rel, w):
        if abs(w) < 1e-4:
            return
        t = self._target(rel)
        if t is None:
            print("  [warn] missing target", rel)
            return
        self.v[t[0]] += t[1] * w

    # ---- macro ----
    @staticmethod
    def age_years_to_val(y):
        if y <= 1: return 0.0
        if y < 11: return 0.1875 * (y - 1) / 10.0
        if y < 25: return 0.1875 + (0.5 - 0.1875) * (y - 11) / 14.0
        return 0.5 + 0.5 * (y - 25) / 65.0

    def macro(self, gender=1.0, age_years=25, muscle=0.5, weight=0.5, height=0.5,
              race=(1/3, 1/3, 1/3)):
        age = self.age_years_to_val(age_years)
        if age < 0.5:
            baby = max(0.0, 1 - age / 0.1875)
            young = max(0.0, (age - 0.1875) / (0.5 - 0.1875)) if age >= 0.1875 else 0.0
            child = max(0.0, 1.0 - baby - young); old = 0.0
        else:
            baby = child = 0.0; old = (age - 0.5) / 0.5; young = 1 - old
        ages = {"baby": baby, "child": child, "young": young, "old": old}
        genders = {"female": 1 - gender, "male": gender}
        mus = {"minmuscle": max(0, (0.5 - muscle) * 2), "maxmuscle": max(0, (muscle - 0.5) * 2)}
        mus["averagemuscle"] = 1 - mus["minmuscle"] - mus["maxmuscle"]
        wei = {"minweight": max(0, (0.5 - weight) * 2), "maxweight": max(0, (weight - 0.5) * 2)}
        wei["averageweight"] = 1 - wei["minweight"] - wei["maxweight"]
        hei = {"minheight": max(0, (0.5 - height) * 2), "maxheight": max(0, (height - 0.5) * 2)}
        races = dict(zip(("african", "asian", "caucasian"), race))
        for g, gw in genders.items():
            for a, aw in ages.items():
                if gw * aw < 1e-5: continue
                for m, mw in mus.items():
                    for w_, ww in wei.items():
                        f = gw * aw * mw * ww
                        if f < 1e-5: continue
                        self.add_target(f"macrodetails/universal-{g}-{a}-{m}-{w_}.target", f)
                        for h, hw in hei.items():
                            if hw > 1e-5:
                                self.add_target(f"macrodetails/height/{g}-{a}-{m}-{w_}-{h}.target", f * hw)
                for r, rw in races.items():
                    if rw > 1e-5:
                        self.add_target(f"macrodetails/{r}-{g}-{a}.target", gw * aw * rw)

    def detail(self, group, target, value, mn=None, mx=None):
        """MakeHuman detail modifier: value in [-1,1] for paired, [0,1] for single."""
        if mn is None:
            self.add_target(f"{group}/{target}.target", value)
        elif value >= 0:
            self.add_target(f"{group}/{target}-{mx}.target", value)
        else:
            self.add_target(f"{group}/{target}-{mn}.target", -value)

    # ---- skeleton ----
    def joint(self, name):
        return self.v[self.vgroups[name]].mean(axis=0)


def mh_to_blender(p, scale=0.1):
    """MakeHuman (Y up, +Z forward, decimetres) -> Blender (Z up, -Y forward, metres)."""
    p = np.asarray(p)
    return np.stack([p[..., 0], -p[..., 2], p[..., 1]], axis=-1) * scale


# ---- mhclo proxies ----
class Proxy:
    def __init__(self, path, base_v_for_scale=None):
        self.dir = os.path.dirname(path)
        self.entries = []   # per proxy vertex: (idx(3), w(3), off(3)) or single
        self.scales = {}
        self.obj_file = None; self.material = None; self.delete_verts = []
        self.name = os.path.basename(path)
        mode = None
        with open(path, "r", errors="replace") as f:
            for ln in f:
                s = ln.strip()
                if not s or s.startswith("#"):
                    continue
                p = s.split()
                if p[0] == "verts": mode = "verts"; continue
                if p[0] == "delete_verts": mode = "del"; continue
                if mode == "verts" and re.match(r"^-?\d", p[0]):
                    if len(p) == 1:
                        self.entries.append(((int(p[0]),) * 3, (1.0, 0.0, 0.0), (0.0, 0.0, 0.0)))
                    else:
                        self.entries.append(((int(p[0]), int(p[1]), int(p[2])),
                                             (float(p[3]), float(p[4]), float(p[5])),
                                             (float(p[6]), float(p[7]), float(p[8]))))
                    continue
                if mode == "del":
                    if p[0] == "verts" : continue
                    # lines: "a - b" ranges or single numbers
                    toks = s.replace("-", " - ").split()
                    i = 0
                    while i < len(toks):
                        if i + 2 < len(toks) and toks[i + 1] == "-":
                            self.delete_verts.extend(range(int(toks[i]), int(toks[i + 2]) + 1)); i += 3
                        else:
                            try: self.delete_verts.append(int(toks[i]))
                            except ValueError: pass
                            i += 1
                    continue
                if p[0] in ("x_scale", "y_scale", "z_scale"):
                    self.scales[p[0][0]] = (int(p[1]), int(p[2]), float(p[3])); mode = None
                elif p[0] == "obj_file": self.obj_file = p[1]
                elif p[0] == "material": self.material = p[1]
                elif p[0] in ("vertexboneweights_file", "z_depth", "max_pole", "name", "uuid", "basemesh", "tag",
                              "subdivide", "shrinkwrap", "wrap_distance"):
                    pass
                else:
                    mode = None
        self.idx = np.array([e[0] for e in self.entries], dtype=np.int64)
        self.w = np.array([e[1] for e in self.entries])
        self.off = np.array([e[2] for e in self.entries])
        self.v0, self.uv, self.faces, self.groups = load_obj(os.path.join(self.dir, self.obj_file))

    def fit(self, human_v, base_v):
        """Fitted vertex positions (MH units) on the current (morphed) human mesh."""
        sc = np.ones(3)
        for i, ax in enumerate("xyz"):
            if ax in self.scales:
                a, b, den = self.scales[ax]
                sc[i] = abs(human_v[a][i] - human_v[b][i]) / den
        P = human_v[self.idx]                       # (N,3,3)
        pos = (P * self.w[:, :, None]).sum(axis=1) + self.off * sc
        return pos

    def skin_weights(self, body_w):
        """body_w: (13380, nb) dense -> proxy vertex weights (barycentric blend)."""
        ids = self.idx
        return (body_w[ids] * self.w[:, :, None]).sum(axis=1)


def parse_mhmat(path):
    d = {}
    with open(path, "r", errors="replace") as f:
        for ln in f:
            p = ln.strip().split()
            if len(p) >= 2 and not ln.startswith("#"):
                d[p[0]] = p[1:]
    return d


def load_rig(name="game_engine"):
    rig = json.load(open(os.path.join(MPFB_DATA, f"rigs/standard/rig.{name}.json")))
    wts = json.load(open(os.path.join(MPFB_DATA, f"rigs/standard/weights.{name}.json")))["weights"]
    return rig, wts


def dense_weights(wts, bones, n=N_BODY):
    W = np.zeros((n, len(bones)))
    bi = {b: i for i, b in enumerate(bones)}
    for b, lst in wts.items():
        if b not in bi: continue
        for v, w in lst:
            if v < n: W[v, bi[b]] = w
    return W
