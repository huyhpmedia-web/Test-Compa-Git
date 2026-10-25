"""Rimebound (zombie) variants: frostbitten MakeHuman bodies with baked gore (albedo + normal + wet roughness)."""
import os, math
import numpy as np
import bpy
import mh_lib as mh
import bl_common as bc
import paint as pt
import gore
from specs import (A, jtex, make_pbr, solid_mat, TEX, normals_jpg, eye_image, hair_png, messy, body_surface_patch,
                   merge_meshes, ensure)
import chars2 as c2


def maps_to_files(cb, label, size, r, col, rough, hgt, base_nrm=None, flat_scale=0.0, nstrength=3.0, covered_fill=None):
    px, py = r["x"], r["y"]
    cov = np.zeros((size, size), dtype=bool); cov[py, px] = True
    img = np.zeros((size, size, 3), dtype=np.float32)
    img[py, px] = np.clip(col, 0, 1)
    img = pt.dilate(img, cov, 8)
    mr = np.zeros((size, size, 3), dtype=np.float32); mr[..., 0] = 1.0; mr[..., 1] = 0.85
    mr[py, px, 1] = np.clip(rough, 0.05, 1.0); mr[py, px, 2] = 0.0
    mr = pt.dilate(mr, cov, 8)
    Hh = np.zeros((size, size), dtype=np.float32); Hh[py, px] = hgt
    Hh = pt.dilate(Hh[..., None], cov, 6)[..., 0]
    flat = None
    if base_nrm is not None:
        fl = np.zeros((size, size), dtype=np.float32); fl[py, px] = np.clip(flat_scale, 0, 1)
        flat = fl
    nrm = gore.normal_from_height(Hh, base_nrm, nstrength, flat)
    return (jtex(f"{cb.name}_{label}_diffuse.jpg", img, 90), jtex(f"{cb.name}_{label}_mr.jpg", mr, 92),
            jtex(f"{cb.name}_{label}_normal.jpg", nrm, 92))


def pick_points(pos, mask, n=60, seed=0):
    idx = np.where(mask)[0]
    if len(idx) == 0:
        return []
    rng = np.random.RandomState(seed + 5)
    sel = rng.choice(idx, size=min(n, len(idx)), replace=False)
    return [tuple(pos[i]) for i in sel]


def cloth_painter(color, contrast, gcfg, seed, label, rough=0.9, tint2=None):
    def paint(cb, P, pos, comp, ids, orig, size):
        tris = [t for t in pt.tri_list(P.faces) if comp[t[0]] in ids]
        nrm = pt.vertex_normals(pos, [f[0] for f in P.faces])
        r = pt.rasterize(tris, P.uv, {"pos": pos, "nrm": nrm}, size)
        p = r["pos"]; nn = r["nrm"]
        nn = nn / np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-6)
        o = orig[r["y"], r["x"]]
        lum = (o * np.array([0.3, 0.59, 0.11])).sum(1)
        lum = (1 - contrast) + contrast * np.clip(lum / max(np.median(lum), 1e-3), 0.3, 2.0)
        col = np.array(color)[None] * lum[:, None]
        # dirt / wear
        d = gore.fbm(p, 110, seed + 3)
        col = col * (0.86 + 0.2 * d[:, None])
        col = col * (1 - 0.3 * pt.smoothstep(0.25, 0.0, p[:, 2])[:, None])        # dirty low
        mask = np.isin(comp, list(ids))
        zc = cb.conv(cb.H.joint("joint-spine-1"))[2]
        cand = (pos[:, 2] > zc - 0.45) & (pos[:, 2] < zc + 0.12) & mask
        eye_z = cb.conv(cb.H.joint("joint-l-eye"))[2]
        anchors = dict(mouth=(0.0, 0.0, eye_z - 0.066), pts=pick_points(pos, cand, 60, seed))
        f = gore.fields(p, nn, seed, anchors, gcfg)
        rg = np.full(len(p), rough)
        col, rg = gore.shade(col, rg, f, p, seed)
        base_n = None
        base_dir = os.path.dirname(A(P.name if False else "clothes"))
        return maps_to_files(cb, label, size, r, col, rg, f["h"] + 0.0, getattr(P, "_nrm_img", None), flat_scale=np.clip(f["blood"] + f["flesh"], 0, 1), nstrength=3.0)
    return paint


def zombie_skin(cb, spec, size=1024):
    H = cb.H
    sk_dir = A("skins", spec["skin"])
    base = pt.load_rgb(os.path.join(sk_dir, [f for f in os.listdir(sk_dir) if f.endswith(".png")][0]), size)
    pos = cb.conv(H.v[:mh.N_BODY])
    nrm = pt.vertex_normals(pos, [f[0] for f in H.body_faces])
    names = cb.bones
    hand_names = [b for b in names if any(k in b for k in ("thumb", "index", "middle", "ring", "pinky"))]
    Wf = cb.W[:, [names.index(b) for b in hand_names]].sum(1)[:, None]
    Wh = cb.W[:, [names.index(b) for b in ("hand_l", "hand_r")]].sum(1)[:, None]
    Wa = cb.W[:, [names.index(b) for b in ("lowerarm_l", "lowerarm_r")]].sum(1)[:, None]
    tris = pt.tri_list(H.body_faces)
    r = pt.rasterize(tris, H.uv, {"pos": pos, "nrm": nrm, "wf": Wf, "wh": Wh, "wa": Wa}, size)
    p = r["pos"]; nn = r["nrm"] / np.maximum(np.linalg.norm(r["nrm"], axis=1, keepdims=True), 1e-6)
    seed = spec.get("seed", 1)
    px, py = r["x"], r["y"]
    col = base[py, px].copy()
    eye_z = cb.conv(H.joint("joint-l-eye"))[2]
    mouth_z = eye_z - 0.066
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    ax = np.abs(x)
    fwd = pt.smoothstep(-0.03, -0.1, y)
    # --- frostbite pallor + mottling
    pal = np.array(spec.get("pallor", (0.70, 0.80, 0.90)))
    col = col * pal[None]
    m1 = gore.fbm(p, 28, seed)
    bruise = pt.smoothstep(0.52, 0.72, m1)[:, None] * np.array([0.62, 0.52, 0.72])[None]
    col = col * (1 - 0.55 * pt.smoothstep(0.52, 0.72, m1)[:, None]) + col * bruise * 0.55
    m2 = gore.fbm(p, 55, seed + 4)
    ice = pt.smoothstep(0.62, 0.8, m2)
    col = col * (1 - 0.45 * ice[:, None]) + np.array([0.86, 0.92, 0.97])[None] * 0.45 * ice[:, None]
    # nose/ears/cheeks go bluish-black (frostbite)
    nose = np.exp(-(((x) / 0.02) ** 2 + ((z - (eye_z - 0.04)) / 0.024) ** 2)) * fwd
    cheek = np.exp(-(((ax - 0.06) / 0.03) ** 2 + ((z - (eye_z - 0.05)) / 0.03) ** 2)) * fwd
    fb = np.clip(nose * 0.8 + cheek * 0.5, 0, 0.85) * spec.get("frostbite", 1.0)
    col = col * (1 - fb[:, None]) + np.array([0.20, 0.17, 0.26])[None] * fb[:, None]
    # dark eye sockets
    eyes = np.exp(-(((ax - 0.035) / 0.03) ** 2 + ((z - (eye_z - 0.004)) / 0.016) ** 2)) * fwd
    col = col * (1 - 0.65 * eyes[:, None]) + np.array([0.10, 0.08, 0.14])[None] * 0.65 * eyes[:, None]
    # black lips
    lips = np.exp(-(((ax) / 0.034) ** 2 + ((z - (mouth_z - 0.002)) / 0.012) ** 2)) * fwd
    col = col * (1 - 0.9 * lips[:, None]) + np.array([0.07, 0.04, 0.06])[None] * 0.9 * lips[:, None]
    # blackened hands / fingers
    fing = np.clip(r["wf"][:, 0] * 1.4, 0, 1)
    hand = np.clip(r["wh"][:, 0] * 0.8, 0, 1)
    black = np.clip(fing * (0.55 + 0.6 * gore.fbm(p, 90, seed + 8)) + hand * 0.25, 0, 0.95) * spec.get("frostbite", 1.0)
    col = col * (1 - black[:, None]) + np.array([0.06, 0.05, 0.07])[None] * black[:, None]
    arm = np.clip(r["wa"][:, 0], 0, 1) * 0.25
    col = col * (1 - arm[:, None]) + np.array([0.3, 0.3, 0.42])[None] * arm[:, None]
    # --- gore
    vm = (cb.W[:, [names.index(b) for b in ("neck_01", "lowerarm_l", "lowerarm_r", "upperarm_l", "upperarm_r")]].sum(1) > 0.6) & (pos[:, 2] < eye_z - 0.06)
    pts = pick_points(pos, vm, 60, seed)                                      # neck / arms
    anchors = dict(mouth=(0.0, 0.0, mouth_z), pts=pts)
    f = gore.fields(p, nn, seed, anchors, spec.get("gore_skin", dict(mouth=0.8, wounds=2, splat=0.3, frost=0.4)))
    rg = np.full(len(p), 0.58) - 0.12 * ice
    col, rg = gore.shade(col, rg, f, p, seed)
    # unhinged jaw: dark open-mouth cavity
    if spec.get("open_mouth"):
        cav = np.exp(-(((ax) / 0.04) ** 2 + ((z - (mouth_z - 0.03)) / 0.05) ** 2)) * fwd
        col = col * (1 - cav[:, None]) + np.array([0.06, 0.01, 0.015])[None] * cav[:, None]
        rg = rg * (1 - cav) + 0.2 * cav
    return maps_to_files(cb, "skin", size, r, col, rg, f["h"], None, 0.0, nstrength=3.0)


def zombie_face(cb, spec, hair, hair_tint, brow="eyebrows/eyebrow001/eyebrow001"):
    spec.setdefault("iris", (0.72, 0.84, 0.95))
    c2.face_parts(cb, spec, hair=hair, hair_tint=hair_tint, brow=brow, brow_tint=(0.4, 0.4, 0.42), lashes=False, eye_tint=(0.7, 0.85, 1.0),
                  decim_hair=0.35, subdiv=False)


def load_nrm_img(P, size=1024):
    d = os.path.dirname(os.path.join(mh.ASSETS, "clothes", P.name.replace(".mhclo", ""), "x"))
    return None


# ----------------------------------------------------------------------------- outfits
def suit_pieces_g(cb, rel, orig_png, pieces, size=1024):
    """like chars2.suit_pieces but painters may return (diffuse, mr, normal) and receive the proxy normal map."""
    n = cb.name; H = cb.H
    P = mh.Proxy(A(rel))
    pos = cb.conv(P.fit(H.v, H.base_v))
    comp = cb.components(P)
    orig = pt.load_rgb(orig_png, size)
    base_dir = os.path.dirname(A(rel))
    nrm_path = [os.path.join(base_dir, f) for f in os.listdir(base_dir) if f.endswith("_normal.png")]
    P._nrm_img = pt.load_rgb(nrm_path[0], size) if nrm_path else None
    nrm_jpg = normals_jpg(cb, os.path.basename(base_dir), nrm_path[0], 1024) if nrm_path else None
    stats = []
    for c in range(comp.max() + 1):
        m = comp == c
        hk = cb.spec["height_m"] / 1.8
        stats.append((float(pos[m][:, 2].min()) / hk, float(pos[m][:, 2].max()) / hk, int(m.sum())))
    Wd = P.skin_weights(cb.Wfull)
    nrm = pt.vertex_normals(pos, [f[0] for f in P.faces])
    for pc in pieces:
        ids = {c for c, st in enumerate(stats) if pc["match"](*st)}
        if not ids:
            print("  [warn] piece", pc["label"], "matched nothing", stats)
            continue
        mask = np.isin(comp, list(ids))
        ppos = pos.copy()
        if pc.get("inflate"):
            ppos[mask] = pos[mask] + nrm[mask] * pc["inflate"]
        if pc.get("stretch"):
            z0, k, grow = pc["stretch"]
            if z0 is None:
                z0 = float(pos[mask][:, 2].max()) - 0.05
            low = mask & (ppos[:, 2] < z0)
            if low.any():
                dz = (z0 - ppos[low, 2]) * (k - 1.0)
                ppos[low, 2] -= dz
                fac = (1 + grow * (dz / max(dz.max(), 1e-6)))
                ppos[low, 0] *= fac
                ym = pos[:, 1][mask].mean()
                ppos[low, 1] = (ppos[low, 1] - ym) * fac + ym
        if pc.get("cut_below") is not None:
            mask = mask & (pos[:, 2] > pc["cut_below"])
        res = pc["painter"](cb, P, pos, comp, ids, orig, size)
        if isinstance(res, tuple):
            d, mr, nr = res
        else:
            d, mr, nr = res, None, nrm_jpg
        mat = make_pbr(f"{n}_{pc['label']}", d, nr, mr, rough=pc.get("rough", 0.9))
        sub, fv, ft, remap, used = cb.sub_mesh(ppos, P.faces, mask)
        ob = cb.add_mesh(pc["label"], sub, fv, ft, P.uv, W=Wd[used], mat=mat)
        if pc.get("dec"):
            cb.decimate(ob, pc["dec"])
    return set(P.delete_verts)


SUIT = {
    "suit05": ("clothes/male_casualsuit05/male_casualsuit05.mhclo", "clothes/male_casualsuit05/male_casualsuit05_diffuse.png"),
    "suit03": ("clothes/male_casualsuit03/male_casualsuit03.mhclo", "clothes/male_casualsuit03/male_casualsuit03_diffuse.png"),
    "suit06": ("clothes/male_casualsuit06/male_casualsuit06.mhclo", "clothes/male_casualsuit06/male_casualsuit06_diffuse.png"),
    "suit04": ("clothes/male_casualsuit04/male_casualsuit04.mhclo", "clothes/male_casualsuit04/male_casualsuit04_diffuse.png"),
    "fsuit01": ("clothes/female_casualsuit01/female_casualsuit01.mhclo", "clothes/female_casualsuit01/female_casualsuit01_diffuse.png"),
    "fsuit02": ("clothes/female_casualsuit02/female_casualsuit02.mhclo", "clothes/female_casualsuit02/female_casualsuit02_diffuse.png"),
    "felegant": ("clothes/female_elegantsuit01/female_elegantsuit01.mhclo", "clothes/female_elegantsuit01/female_elegantsuit01_diffuse.png"),
    "work": ("clothes/male_worksuit01/male_worksuit01.mhclo", "clothes/male_worksuit01/male_worksuit01_diffuse.png"),
}


def build_zombie(cb, spec):
    n = cb.name; H = cb.H
    seed = spec.get("seed", 1)
    o = spec["outfit"]; col = spec.get("color", (0.3, 0.3, 0.3)); col2 = spec.get("color2", (0.12, 0.15, 0.22))
    g = dict(spec.get("gore_cloth", dict(mouth=0.8, soak=0.6, wounds=2, torn=1, splat=0.35, frost=0.45)))
    dv = set()
    zw = cb.conv(H.joint("joint-spine-4"))[2]
    # skin first (needs W only)
    if spec.get("clean"):
        from specs import paint_skin
        sk_d = paint_skin(cb, spec["skin"], spec["details"], spec.get("stubble", 0.0), 0.5, (0.98, 0.92, 0.88)); sk_mr = None; sk_n = None
    else:
        sk_d, sk_mr, sk_n = zombie_skin(cb, spec)
    P_ = lambda c, ct, lab, **kw: cloth_painter(c, ct, g, seed, lab, **kw)
    boots = spec.get("boots", ("shoes02", (0.07, 0.06, 0.05), 0.2))
    glove = spec.get("gloves")
    low = lambda zmin, zmax, n_: zmax < 1.25 and zmin < 0.4 and n_ > 500
    up = lambda zmin, zmax, n_: zmax > 1.2 and zmin > 0.5 and n_ > 200
    if o in ("parka", "jacket", "cop", "worker"):
        s_rel, s_png = SUIT["suit05"]
        pieces = [dict(match=lambda zmin, zmax, n_: zmax > 1.2 and zmin > 0.5 and n_ > 1000, label="coat",
                       painter=P_(col, 0.45, "coat", rough=0.85), dec=0.55, inflate=0.012 if o != "jacket" else 0.006,
                       stretch=(zw + 0.03, 1.8, 0.1) if o == "parka" else None),
                  dict(match=lambda zmin, zmax, n_: zmax > 1.2 and zmin > 0.5 and 200 < n_ <= 1000, label="liner", painter=P_(col2, 0.2, "liner"), dec=0.6),
                  dict(match=low, label="trousers", painter=P_(spec.get("pants", (0.14, 0.16, 0.22)), 0.4, "trousers"), cut_below=0.2, dec=0.6)]
    elif o == "flannel":
        s_rel, s_png = SUIT["suit03"]
        pieces = [dict(match=up, label="shirt", painter=P_(col, 0.9, "shirt"), dec=0.55),
                  dict(match=low, label="jeans", painter=P_(col2, 0.5, "jeans"), cut_below=0.12, dec=0.6)]
    elif o == "tee_m":
        s_rel, s_png = SUIT["suit06"]
        pieces = [dict(match=up, label="tee", painter=P_(col, 0.35, "tee"), dec=0.5),
                  dict(match=low, label="jeans", painter=P_(col2, 0.5, "jeans"), cut_below=0.12, dec=0.6)]
    elif o == "patient":
        s_rel, s_png = SUIT["suit04"]
        pieces = [dict(match=up, label="gown", painter=P_(col, 0.2, "gown"), dec=0.55),
                  dict(match=low, label="pants", painter=P_(col2, 0.2, "pants"), cut_below=0.12, dec=0.6)]
    elif o == "tee_f":
        s_rel, s_png = SUIT["fsuit01"]
        pieces = [dict(match=up, label="top", painter=P_(col, 0.7, "top"), dec=0.6),
                  dict(match=low, label="jeans", painter=P_(col2, 0.5, "jeans"), cut_below=0.1, dec=0.6)]
    elif o == "nurse":
        s_rel, s_png = SUIT["felegant"]
        pieces = [dict(match=lambda zmin, zmax, n_: zmax > 1.0 and n_ > 1000, label="uniform", painter=P_(col, 0.25, "uniform"), dec=0.6),
                  dict(match=lambda zmin, zmax, n_: zmax < 1.1 and n_ < 1000, label="skirt", painter=P_(col2, 0.25, "skirt"), dec=0.6)]
    elif o == "dress":
        s_rel, s_png = SUIT["felegant"]
        pieces = [dict(match=lambda zmin, zmax, n_: zmax > 1.0 and n_ > 1000, label="gown", painter=P_(col, 0.25, "gown"), dec=0.6),
                  dict(match=lambda zmin, zmax, n_: zmax < 1.1 and n_ < 1000, label="skirt", painter=P_(col2, 0.25, "skirt"), dec=0.6, stretch=(None, 1.7, 0.1))]
    elif o == "miner":
        s_rel, s_png = SUIT["work"]
        pieces = [dict(match=lambda zmin, zmax, n_: zmin < 0.4 and zmax > 1.2 and n_ > 1500, label="overalls", painter=P_(col, 0.7, "overalls"), dec=0.5),
                  dict(match=lambda zmin, zmax, n_: zmax > 1.2 and zmin > 0.5 and n_ > 500, label="shirt", painter=P_(col2, 0.6, "shirt"), dec=0.55)]
    else:
        raise ValueError(o)
    dv |= suit_pieces_g(cb, s_rel, A(s_png), pieces)
    if boots:
        dv |= c2.make_boots(cb, boots[0], boots[1], top=boots[2], widen=(1.1, 1.08, 1.12 if boots[2] > 0.15 else 1.0), dec=0.4)
    if glove:
        dv |= c2.glove_hands(cb, glove, dec=0.3)
    bpos = cb.conv(H.v[:mh.N_BODY])
    dv |= set(np.where(bpos[:, 2] < (0.26 if boots and boots[2] > 0.15 else 0.14))[0].tolist())
    skin_mat = make_pbr(n + "_skin", sk_d, sk_n, sk_mr, rough=0.6, spec=0.35)
    body = cb.build_body(sorted(dv))
    body.data.materials.append(skin_mat)
    cb.decimate(body, spec.get("body_dec", 0.4))
    d = c2.head_dims(cb)
    if spec.get("clean"):
        c2.face_parts(cb, spec, hair=spec.get("hair"), hair_tint=spec.get("hair_tint"), brow="eyebrows/eyebrow002/eyebrow002", brow_tint=(0.35, 0.3, 0.28),
                      lashes=spec.get("gender", 1) < 0.5, eye_tint=(0.8, 0.85, 1.0), decim_hair=0.8, subdiv=True)
    else:
        zombie_face(cb, spec, spec.get("hair"), spec.get("hair_tint", (0.3, 0.3, 0.32)))
    for ex in spec.get("extras", []):
        globals()["extra_" + ex](cb, spec)
    if o == "miner":
        c2.dome(cb, "hardhat", (0.55, 0.4, 0.03), d["eye_z"] + 0.065, d["eye_z"], extra=0.02, rough=0.45)
        V, F = c2.cylinder([0.0, d["ymin"] - 0.015, d["eye_z"] + 0.1], 0.022, 0.035, axis=1, n=10)
        cb.add_mesh("lamp", V, F, bone="head", mat=solid_mat(n + "_lamp", (0.3, 0.3, 0.3), 0.4))
    if o == "cop":
        c2.dome(cb, "cap", (0.05, 0.06, 0.1), d["eye_z"] + 0.05, d["eye_z"] + 0.02, extra=0.012, rough=0.8)
    if o == "worker":
        c2.knit_dome(cb, "beanie", (0.12, 0.12, 0.14), d["eye_z"] + 0.05, d["eye_z"] - 0.03, cuff=0.04)
    if o == "nurse":
        c2.stethoscope(cb)


# ----------------------------------------------------------------------------- extras
def pyramid(base, direction, length, width, thick, tip=0.15):
    d = np.array(direction, dtype=float); d /= np.linalg.norm(d)
    a = np.cross(d, [0.3, 0.5, 0.8]); a /= np.linalg.norm(a); b = np.cross(d, a)
    V = []
    for sa, sb in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        V.append(base + a * sa * width / 2 + b * sb * thick / 2)
    for sa, sb in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        V.append(base + d * length + a * sa * width * tip / 2 + b * sb * thick * tip / 2)
    F = [[0, 1, 2, 3][::-1], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
    return np.array(V), F


def ice_mat(cb, name="ice", color=(0.55, 0.8, 0.92), emit=0.25):
    m = make_pbr(f"{cb.name}_{name}", None, rough=0.08, color=(*[c ** 2.2 for c in color], 0.7))
    bs = m.node_tree.nodes["Principled BSDF"]
    bs.inputs["Alpha"].default_value = 0.72
    bs.inputs["Emission Color"].default_value = (*[c ** 2.2 for c in color], 1.0)
    bs.inputs["Emission Strength"].default_value = emit
    return m


def bone_pts(cb, bone, t):
    b = cb.arm.data.bones[bone]
    h = np.array(b.head_local); tl = np.array(b.tail_local)
    return h + (tl - h) * t, (tl - h) / max(np.linalg.norm(tl - h), 1e-6)


def extra_ice_plates(cb, spec):
    """big overlapping ice plates growing out of a Husk's shoulders, arms, back and legs (rigid on bones)."""
    rng = np.random.RandomState(spec.get("seed", 1) + 99)
    lst = []
    plan = [("upperarm_l", 3, 0.18), ("upperarm_r", 3, 0.18), ("lowerarm_l", 2, 0.14), ("lowerarm_r", 2, 0.14),
            ("thigh_l", 2, 0.2), ("thigh_r", 2, 0.2), ("calf_l", 1, 0.16), ("calf_r", 1, 0.16),
            ("spine_03", 5, 0.3), ("spine_02", 3, 0.25), ("clavicle_l", 1, 0.26), ("clavicle_r", 1, 0.26), ("head", 2, 0.16)]
    per_bone = {}
    for bone, n, ln in plan:
        parts = []
        for i in range(n):
            t = (i + 0.5) / n * 0.8 + 0.1
            p, axis = bone_pts(cb, bone, t)
            side = np.array([1.0 if bone.endswith("_l") else (-1.0 if bone.endswith("_r") else rng.uniform(-1, 1)), rng.uniform(-0.4, 0.8), rng.uniform(-0.3, 0.7)])
            if bone in ("spine_03", "spine_02"):
                side = np.array([rng.uniform(-0.8, 0.8), 1.0 if rng.rand() < 0.5 else -0.4, rng.uniform(0.3, 1.0)])   # back (+y) and sides
            side = side - axis * np.dot(side, axis); side /= np.linalg.norm(side)
            base = p + side * 0.035
            dirv = side + axis * rng.uniform(0.0, 0.7)
            V, F = pyramid(base, dirv, ln * rng.uniform(1.2, 2.0), rng.uniform(0.12, 0.2), rng.uniform(0.04, 0.07), tip=0.12)
            parts.append((V, F))
        V, F = merge_meshes(parts)
        cb.add_mesh("plates_" + bone, V, F, bone=bone, mat=ice_mat(cb, "ice"), smooth=False)


def sphere_mesh(c, r, seg=10, rings=6, squash=(1, 1, 1)):
    V = []; F = []
    for j in range(rings + 1):
        th = math.pi * j / rings
        for i in range(seg):
            ph = 2 * math.pi * i / seg
            V.append(np.array(c) + np.array([r * squash[0] * math.sin(th) * math.cos(ph), r * squash[1] * math.sin(th) * math.sin(ph), r * squash[2] * math.cos(th)]))
    for j in range(rings):
        for i in range(seg):
            i2 = (i + 1) % seg
            F.append([j * seg + i, j * seg + i2, (j + 1) * seg + i2, (j + 1) * seg + i])
    return np.array(V), F


def extra_sacs(cb, spec):
    """glowing frost-spore sacs bulging from the Burster's torso / limbs (named *sac* / *sac_core* for the AI to pulse)."""
    rng = np.random.RandomState(spec.get("seed", 1) + 7)
    sac_m = ice_mat(cb, "sac", (0.45, 0.9, 0.95), 1.4)
    core_m = ice_mat(cb, "sac_core", (0.7, 1.0, 1.0), 4.0)
    core_m.node_tree.nodes["Principled BSDF"].inputs["Alpha"].default_value = 1.0
    plan = [("spine_01", (0.0, -0.17, 0.0), 0.2), ("spine_01", (0.15, -0.12, 0.02), 0.15), ("spine_01", (-0.16, -0.1, 0.0), 0.15),
            ("spine_02", (0.0, 0.14, 0.02), 0.17), ("spine_03", (-0.1, -0.12, 0.03), 0.11), ("spine_03", (0.12, 0.12, 0.05), 0.1),
            ("upperarm_l", (0.04, 0.0, 0.0), 0.09), ("upperarm_r", (-0.04, 0.0, 0.02), 0.08), ("neck_01", (0.04, -0.03, 0.0), 0.06),
            ("thigh_l", (0.04, -0.05, 0.0), 0.09), ("thigh_r", (-0.02, 0.05, 0.0), 0.08)]
    for i, (bone, off, r) in enumerate(plan):
        p, axis = bone_pts(cb, bone, 0.5)
        c = p + np.array(off)
        V, F = sphere_mesh(c, r * (spec.get("height_m", 1.75) / 1.75))
        cb.add_mesh(f"sac_{i}", V, F, bone=bone, mat=sac_m)
        V2, F2 = sphere_mesh(c, r * 0.45)
        cb.add_mesh(f"saccore_{i}", V2, F2, bone=bone, mat=core_m)


def extra_foreman_hat(cb, spec):
    d = c2.head_dims(cb)
    n = cb.name
    c2.dome(cb, "hardhat", (0.7, 0.5, 0.04), d["eye_z"] + 0.065, d["eye_z"], extra=0.02, rough=0.45)
    V, F = c2.cylinder([0.0, d["ymin"] - 0.018, d["eye_z"] + 0.1], 0.026, 0.04, axis=1, n=10)
    lm = make_pbr(n + "_lamp", None, rough=0.3, color=(1.0, 0.95, 0.8, 1.0))
    lm.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = (1.0, 0.92, 0.7, 1.0)
    lm.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 6.0
    cb.add_mesh("lamp", V, F, bone="head", mat=lm)
