"""Rimebound (zombie) variants: frostbitten MakeHuman bodies with baked gore (albedo + normal + wet roughness)."""
import os, math
import numpy as np
import bpy
import mh_lib as mh
import bl_common as bc
import paint as pt
import gore
from specs import (A, jtex, make_pbr, solid_mat, TEX, normals_jpg, eye_image, hair_png, messy, body_surface_patch,
                   merge_meshes, ensure, scalp_cap)
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


def cloth_painter(color, contrast, gcfg, seed, label, rough=0.9, tint2=None, bands=False):
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
        gr = col.mean(1, keepdims=True)
        col = (gr * 0.32 + col * 0.68) * 0.86                                  # drab, grimy fabric (not saturated)
        # dirt / wear
        d = gore.fbm(p, 110, seed + 3)
        col = col * (0.86 + 0.2 * d[:, None])
        col = col * (1 - 0.3 * pt.smoothstep(0.25, 0.0, p[:, 2])[:, None])        # dirty low
        if bands:   # hi-vis reflective bands (dirty silver)
            zc0 = cb.conv(cb.H.joint("joint-spine-1"))[2]
            bd = np.maximum(pt.smoothstep(0.03, 0.01, np.abs(p[:, 2] - (zc0 + 0.03))), pt.smoothstep(0.03, 0.01, np.abs(p[:, 2] - (zc0 + 0.26))))
            bd = bd * (0.6 + 0.4 * d)
            col = col * (1 - bd[:, None]) + np.array([0.42, 0.43, 0.44])[None] * bd[:, None]
        mask = np.isin(comp, list(ids))
        zc = cb.conv(cb.H.joint("joint-spine-1"))[2]
        cand = (pos[:, 2] > zc - 0.18) & (pos[:, 2] < zc + 0.16) & mask
        eye_z = cb.conv(cb.H.joint("joint-l-eye"))[2]
        wr = [tuple(bone_pts(cb, b_, 0.0)[0]) for b_ in ("hand_l", "hand_r")]
        anchors = dict(mouth=(0.0, 0.0, eye_z - 0.066), pts=pick_points(pos, cand, 60, seed), hem_z=float(pos[mask][:, 2].min()), wrists=wr)
        f = gore.fields(p, nn, seed, anchors, gcfg)
        rg = np.full(len(p), rough)
        col, rg = gore.shade(col, rg, f, p, seed)
        base_n = None
        base_dir = os.path.dirname(A(P.name if False else "clothes"))
        return maps_to_files(cb, label, size, r, col, rg, f["h"] + 0.0, getattr(P, "_nrm_img", None), flat_scale=np.clip(f["blood"] + f["flesh"], 0, 1), nstrength=3.0)
    return paint


def vein_net(p, seed, f=38.0, w=0.028):
    """thin winding lines = iso-contour of smooth noise (reads as a vein / capillary network)."""
    a = np.abs(gore.fbm(p, f, seed) - 0.5)
    b = np.abs(gore.fbm(p, f * 1.9, seed + 7) - 0.5)
    return np.maximum(pt.smoothstep(w, 0.0, a), 0.55 * pt.smoothstep(w * 0.8, 0.0, b))


def zombie_skin(cb, spec, size=1024):
    """frostbitten corpse skin: grey-blue, mottled, veined; black nose / ear tips / fingertips; cracked purple lips;
    gore concentrated at mouth / neck / bites / hands."""
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
    Wn = cb.W[:, [names.index(b) for b in ("neck_01",)]].sum(1)[:, None]
    tris = pt.tri_list(H.body_faces)
    r = pt.rasterize(tris, H.uv, {"pos": pos, "nrm": nrm, "wf": Wf, "wh": Wh, "wa": Wa, "wn": Wn}, size)
    p = r["pos"]; nn = r["nrm"] / np.maximum(np.linalg.norm(r["nrm"], axis=1, keepdims=True), 1e-6)
    seed = spec.get("seed", 1)
    px, py = r["x"], r["y"]
    orig = base[py, px].copy()
    eye_z = cb.conv(H.joint("joint-l-eye"))[2]
    mouth_z = eye_z - 0.066
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    ax = np.abs(x)
    fwd = pt.smoothstep(-0.03, -0.1, y)
    zbody = z / max(spec.get("height_m", 1.8), 1e-3)
    ext = np.clip(r["wf"][:, 0] + r["wh"][:, 0] + r["wa"][:, 0] * 0.8, 0, 1)       # extremities
    # --- grey-blue corpse base keeping the pore detail of the source skin
    pal = np.array(spec.get("pallor", (0.70, 0.80, 0.90)))
    lum = (orig * np.array([0.3, 0.59, 0.11])).sum(1, keepdims=True)
    lum = np.clip(lum / max(float(np.median(lum)), 1e-3), 0.35, 1.5)
    tone = spec.get('tone', (seed % 3))
    base_t = [np.array([0.44, 0.50, 0.42]), np.array([0.43, 0.48, 0.52]), np.array([0.50, 0.47, 0.40])][tone]   # grey-olive / grey-blue / sallow
    cool = base_t * (pal / np.array([0.70, 0.80, 0.90]))[None]
    col = (0.88 * cool * (0.5 + 0.5 * lum) + 0.12 * orig * pal[None]) * 0.68
    # livor mottling (purple, low contrast) + greenish decay patches + frost-pale patches
    m1 = gore.fbm(p, 20, seed)
    liv = pt.smoothstep(0.52, 0.74, m1) * (0.45 + 0.4 * ext + 0.25 * (1 - zbody))
    col = col * (1 - 0.55 * liv[:, None]) + np.array([0.30, 0.24, 0.40])[None] * 0.55 * liv[:, None]
    dep = pt.smoothstep(0.15, -0.55, nn[:, 2]) * 0.8 + pt.smoothstep(0.3, -0.7, z / max(spec.get('height_m', 1.8), 1e-3) - 0.3) * 0.35 + ext * 0.35
    lv = np.clip(dep * (0.5 + 0.9 * gore.fbm(p, 26, seed + 61)), 0, 1) * pt.smoothstep(0.35, 0.65, gore.fbm(p, 12, seed + 62) + 0.25 * dep)
    col = col * (1 - 0.55 * lv[:, None]) + np.array([0.36, 0.14, 0.2])[None] * 0.55 * lv[:, None]
    bruise = pt.smoothstep(0.64, 0.8, gore.fbm(p, 32, seed + 63)) * 0.55
    col = col * (1 - bruise[:, None]) + np.array([0.24, 0.17, 0.32])[None] * bruise[:, None]
    rot = pt.smoothstep(0.62, 0.74, gore.fbm(p, 17, seed + 64)) * 0.7
    col = col * (1 - rot[:, None]) + np.array([0.12, 0.14, 0.09])[None] * rot[:, None]
    slough = pt.smoothstep(0.7, 0.78, gore.fbm(p, 24, seed + 65)) * (0.4 + ext * 0.5)
    col = col * (1 - 0.6 * slough[:, None]) + np.array([0.64, 0.58, 0.52])[None] * 0.6 * slough[:, None]
    m3 = gore.fbm(p, 14, seed + 31)
    dec = pt.smoothstep(0.58, 0.76, m3) * 0.28
    col = col * (1 - dec[:, None]) + np.array([0.46, 0.50, 0.38])[None] * dec[:, None]
    m2 = gore.fbm(p, 55, seed + 4)
    ice = pt.smoothstep(0.64, 0.82, m2)
    # --- veins: strongest on forearms, hands, neck, temples
    vm = np.clip(0.28 + 0.9 * ext + 0.8 * r["wn"][:, 0], 0, 1)
    temple = np.exp(-(((ax - 0.07) / 0.03) ** 2 + ((z - (eye_z + 0.01)) / 0.035) ** 2)) * fwd
    vein = vein_net(p, seed + 20, 38.0, 0.03) * np.clip(vm + temple * 0.8, 0, 1)
    fine = vein_net(p, seed + 40, 95.0, 0.04) * 0.5 * (0.3 + 0.7 * vm)
    vv = np.clip(np.maximum(vein, fine * (1 - ext * 0.3)), 0, 1) * spec.get("veins", 1.0)
    col = col * (1 - 0.62 * vv[:, None]) + np.array([0.20, 0.24, 0.42])[None] * 0.62 * vv[:, None]
    # --- frostbite: nose / ears / cheeks go bluish-black
    nose = np.exp(-(((x) / 0.016) ** 2 + ((z - (eye_z - 0.043)) / 0.02) ** 2)) * fwd
    cheek = np.exp(-(((ax - 0.062) / 0.028) ** 2 + ((z - (eye_z - 0.05)) / 0.028) ** 2)) * fwd
    ear = np.exp(-(((ax - 0.088) / 0.014) ** 2 + ((z - (eye_z - 0.03)) / 0.03) ** 2))
    fbk = spec.get("frostbite", 1.0)
    col = col * (1 - np.clip(cheek * 0.5 * fbk, 0, 0.6)[:, None]) + np.array([0.33, 0.26, 0.40])[None] * np.clip(cheek * 0.5 * fbk, 0, 0.6)[:, None]
    nb = np.clip(nose * 1.2 * (0.7 + 0.5 * gore.fbm(p, 120, seed + 9)), 0, 0.95) * fbk
    eb = np.clip(ear * 1.0 * (0.6 + 0.6 * gore.fbm(p, 120, seed + 10)), 0, 0.92) * fbk
    fb = np.maximum(nb, eb)
    col = col * (1 - fb[:, None]) + np.array([0.075, 0.06, 0.095])[None] * fb[:, None]
    # dark sunken eye sockets, purple-blue
    eyes = np.exp(-(((ax - 0.035) / 0.03) ** 2 + ((z - (eye_z - 0.004)) / 0.017) ** 2)) * fwd
    col = col * (1 - 0.7 * eyes[:, None]) + np.array([0.12, 0.09, 0.17])[None] * 0.7 * eyes[:, None]
    sock = np.exp(-(((ax - 0.036) / 0.026) ** 2 + ((z - (eye_z + 0.002)) / 0.02) ** 2)) * fwd
    hh0 = -sock * 1.2 * spec.get('sunken', 1.0)
    col = col * (1 - 0.35 * sock[:, None]) + np.array([0.16, 0.09, 0.14])[None] * 0.35 * sock[:, None]
    em = spec.get("eye_missing")
    eye_blood = np.zeros(len(p))
    if em:
        sx = 1.0 if em == "l" else -1.0
        cav = np.exp(-(((x - sx * 0.035) / 0.021) ** 2 + ((z - eye_z) / 0.015) ** 2)) * fwd
        col = col * (1 - np.clip(cav * 1.6, 0, 0.97)[:, None]) + np.array([0.09, 0.012, 0.014])[None] * np.clip(cav * 1.6, 0, 0.97)[:, None]
        hh0 = hh0 - cav * 3.0
        eye_blood = pt.smoothstep(0.012, 0.003, np.abs(x - sx * 0.036 - 0.004 * np.sin(z * 300))) * pt.smoothstep(0.0, 0.012, eye_z - z) * pt.smoothstep(0.14, 0.05, eye_z - z) * fwd * 0.9 + cav
    # --- cracked purple lips
    lips = np.exp(-(((ax) / 0.034) ** 2 + ((z - (mouth_z - 0.002)) / 0.011) ** 2)) * fwd
    col = col * (1 - 0.85 * lips[:, None]) + np.array([0.27, 0.13, 0.21])[None] * 0.85 * lips[:, None]
    crack = pt.smoothstep(0.6, 0.7, gore.n3(p * np.array([220.0, 20.0, 12.0]) / 20.0, 1.0, seed + 12)) * lips
    col = col * (1 - 0.85 * crack[:, None]) + np.array([0.10, 0.015, 0.02])[None] * 0.85 * crack[:, None]
    # --- bared teeth + receded gums painted on the lip band (grimace): ivory teeth rows, dark slit, dirty gums, relief
    tb = spec.get("teeth", 1.0 if seed % 2 == 0 else 0.0) + (0.0 if not spec.get("open_mouth") else 1.0)
    if tb > 0:
        mc = mouth_z - 0.002
        band = pt.smoothstep(0.036, 0.031, ax) * fwd * min(tb, 1.0)
        up_r = band * pt.smoothstep(0.0090, 0.0068, np.abs(z - (mc + 0.0062)))
        lo_r = band * pt.smoothstep(0.0090, 0.0068, np.abs(z - (mc - 0.0068)))
        gum = band * pt.smoothstep(0.0045, 0.0030, np.abs(z - (mc + 0.0145))) + band * pt.smoothstep(0.004, 0.0025, np.abs(z - (mc - 0.0155))) * 0.7
        slit = band * pt.smoothstep(0.0016, 0.0004, np.abs(z - mc))
        per = 0.0046
        phx = x / per + 0.3 * np.sin(z * 90)
        frx = phx - np.floor(phx)
        gx = pt.smoothstep(0.14, 0.02, np.minimum(frx, 1 - frx))
        tn = gore.fbm(p, 600, seed + 80)
        tooth = np.clip(np.maximum(up_r, lo_r) * (1 - gx * 0.9), 0, 1)
        tcol = np.array([0.60, 0.55, 0.42])[None] * (0.7 + 0.5 * tn)[:, None]
        tcol = tcol * (1 - 0.35 * pt.smoothstep(0.0, 0.01, np.abs(z - mc))[:, None])         # darker at the gum line
        col = col * (1 - gum[:, None] * 0.85) + np.array([0.34, 0.11, 0.12])[None] * gum[:, None] * 0.85
        col = col * (1 - np.maximum(up_r, lo_r)[:, None]) + np.array([0.05, 0.012, 0.014])[None] * np.maximum(up_r, lo_r)[:, None]
        col = col * (1 - tooth[:, None]) + tcol * tooth[:, None]
        col = col * (1 - slit[:, None]) + np.array([0.03, 0.006, 0.008])[None] * slit[:, None]
        hh0 = hh0 + tooth * 1.1 - np.maximum(up_r, lo_r) * (1 - tooth) * 1.0 - slit * 1.5
    # --- blackened fingers (tips worst) and darkened hands
    fing = np.clip(r["wf"][:, 0] * 1.5, 0, 1)
    hand = np.clip(r["wh"][:, 0] * 0.8, 0, 1)
    black = np.clip(fing * (0.6 + 0.7 * gore.fbm(p, 90, seed + 8)) + hand * 0.12, 0, 0.96) * spec.get("frostbite", 1.0)
    col = col * (1 - black[:, None]) + np.array([0.055, 0.05, 0.07])[None] * black[:, None]
    arm = np.clip(r["wa"][:, 0], 0, 1) * 0.18
    col = col * (1 - arm[:, None]) + np.array([0.26, 0.27, 0.40])[None] * arm[:, None]
    feet = pt.smoothstep(0.14, 0.05, z) * (0.6 + 0.5 * gore.fbm(p, 80, seed + 14))
    col = col * (1 - np.clip(feet, 0, 0.9)[:, None]) + np.array([0.12, 0.10, 0.17])[None] * np.clip(feet, 0, 0.9)[:, None]
    # --- frost sheen / hoarfrost speckle on cheeks, brow, shoulders
    up = pt.smoothstep(0.3, 0.9, nn[:, 2])
    spark = pt.smoothstep(0.55, 0.9, gore.n3(p, 480, seed + 50))
    fr_a = np.clip(ice * 0.4 + up * 0.25 * pt.smoothstep(0.1, 0.0, zbody - 0.82) * 0 + (cheek + temple) * 0.2, 0, 1) * (0.5 + 0.8 * spark)
    fr_a = fr_a * 0.0
    col = scalp_cap(cb, p, col)
    # --- emaciation / ribcage (Siren)
    hh = np.zeros(len(p))
    if spec.get("ribs"):
        zs1 = cb.conv(H.joint("joint-spine-1"))[2]; zs4 = cb.conv(H.joint("joint-spine-4"))[2]
        sp_ = (zs4 - zs1 - 0.02) / 8.0
        zr = z + 0.035 * (np.clip(ax / 0.16, 0, 1.4) ** 2)           # ribs sweep downward to the sides
        ph = (zr - (zs1 + 0.02)) / sp_
        ridge = np.exp(-(((ph - np.floor(ph)) - 0.5) / 0.2) ** 2)
        inr = (ph > 0) & (ph < 8)
        rm = inr * pt.smoothstep(0.24, 0.17, ax) * pt.smoothstep(-0.01, -0.07, y) * 1.0 + inr * pt.smoothstep(0.24, 0.18, ax) * 0.5 * (y > -0.01) * 0.0
        rm = rm * (1 - pt.smoothstep(0.012, 0.02, ax) * 0) * pt.smoothstep(0.012, 0.03, ax)      # gap = sternum
        stern = np.exp(-((ax / 0.011) ** 2)) * pt.smoothstep(zs4 + 0.01, zs4 - 0.03, z) * pt.smoothstep(zs1 + 0.0, zs1 + 0.06, z) * fwd
        clav = np.exp(-(((z - (zs4 + 0.075)) / 0.008) ** 2)) * pt.smoothstep(0.02, 0.05, ax) * pt.smoothstep(0.17, 0.12, ax) * fwd
        hh = ridge * rm * 1.6 + stern * 1.1 + clav * 1.2
        shade_ = (1 - 0.5 * (1 - ridge) * rm) * (1 + 0.1 * ridge * rm)
        col = col * shade_[:, None]
        # hollow belly under the ribs + thin limbs shading
        belly = np.exp(-(((ax) / 0.12) ** 2 + ((z - (zs1 - 0.06)) / 0.08) ** 2)) * fwd
        col = col * (1 - 0.18 * belly[:, None])
    # --- desaturate toward dead grey, grime, scabs, micro skin relief
    gr_ = col.mean(1, keepdims=True)
    col = gr_ * 0.5 + col * 0.5
    grime = np.clip(pt.smoothstep(0.55, 0.8, gore.fbm(p, 9, seed + 70)) * 0.45 + 0.25 * gore.fbm(p, 60, seed + 71), 0, 0.7)
    col = col * (1 - grime[:, None] * 0.45) + np.array([0.10, 0.08, 0.06])[None] * grime[:, None] * 0.25
    scab = pt.smoothstep(0.7, 0.78, gore.fbm(p, 46, seed + 72)) * (0.5 + 0.5 * (nn[:, 2] > 0.2)) * spec.get("scabs", 0.8)
    col = col * (1 - scab[:, None] * 0.8) + np.array([0.19, 0.07, 0.05])[None] * scab[:, None] * 0.8
    micro = 0.3 * (gore.fbm(p, 420, seed + 73) - 0.5) + 0.35 * (gore.fbm(p, 150, seed + 74) - 0.5) + scab * 0.9
    # --- gore
    vmk = (cb.W[:, [names.index(b) for b in ("neck_01", "lowerarm_l", "lowerarm_r", "upperarm_l", "upperarm_r")]].sum(1) > 0.6) & (pos[:, 2] < eye_z - 0.06)
    pts = pick_points(pos, vmk, 60, seed)                                      # neck / arms
    tears = [(c_, r_ * 0.8, b_) for c_, r_, b_ in tear_spots(cb, spec)]
    anchors = dict(mouth=(0.0, 0.0, mouth_z), pts=pts, tears=tears)
    gcfg = dict(spec.get("gore_skin", dict(mouth=0.8, wounds=2, splat=0.3, frost=0.4)))
    gcfg['frost'] = 0.0
    gcfg.setdefault('gashes', spec.get('gashes', 1 + seed % 2))
    f = gore.fields(p, nn, seed, anchors, gcfg)
    hb = np.clip(r["wh"][:, 0] * 1.0 + r["wa"][:, 0] * 0.8, 0, 1) * pt.smoothstep(0.3, 0.62, gore.fbm(p, 45, seed + 30)) * gcfg.get("hands", 0.0)
    nk = np.clip(r["wn"][:, 0], 0, 1) * pt.smoothstep(0.35, 0.65, gore.fbm(p, 40, seed + 33)) * gcfg.get("neck", 0.0) * fwd
    tear = (pt.smoothstep(0.006, 0.0, np.abs(ax - 0.04 - 0.02 * pt.smoothstep(0.0, 0.06, eye_z - z))) * pt.smoothstep(0.0, 0.006, eye_z - z) * pt.smoothstep(0.075, 0.03, eye_z - z) * fwd
            * pt.smoothstep(0.3, 0.6, gore.fbm(p, 90, seed + 35))) * gcfg.get("tears", 0.0)
    f["blood"] = np.clip(np.maximum(f["blood"], np.maximum(np.maximum(hb, nk * 0.9), np.maximum(tear * 0.9, eye_blood))), 0, 1)
    f["h"] = f["h"] + hh + hh0 + micro
    rg = np.full(len(p), 0.62) - 0.2 * ice - 0.1 * vv
    col, rg = gore.shade(col, rg, f, p, seed)
    # unhinged jaw: dark open-mouth cavity
    if spec.get("open_mouth"):
        cav = np.exp(-(((ax) / 0.04) ** 2 + ((z - (mouth_z - 0.03)) / 0.05) ** 2)) * fwd
        col = col * (1 - cav[:, None]) + np.array([0.05, 0.008, 0.012])[None] * cav[:, None]
        rg = rg * (1 - cav) + 0.2 * cav
    return maps_to_files(cb, "skin", size, r, col, rg, f["h"], None, 0.0, nstrength=3.0)


def tear_spots(cb, spec):
    """deterministic rip/bite spots on the torso / arms / thighs: [(centre_xyz, radius, exposes_bone)]. used both to cut the
    clothes open and to paint the wound on the body underneath."""
    if spec.get("clean"):
        return []
    key = "_tears"
    if key in spec:
        return spec[key]
    H = cb.H
    bp = cb.conv(H.v[:mh.N_BODY])
    names = cb.bones
    rng = np.random.RandomState(spec.get("seed", 1) * 7 + 3)
    n = spec.get("tears", 1 + spec.get("seed", 1) % 3)
    zs = {"torso": (0.95, 1.4), "arm": (1.0, 1.45), "thigh": (0.65, 1.0)}
    groups = [("spine_01", "spine_02", "spine_03"), ("upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r"), ("thigh_l", "thigh_r")]
    out = []
    for i in range(n):
        g = groups[[0, 0, 1, 2][rng.randint(0, 4)]]
        w = cb.W[:, [names.index(b) for b in g]].sum(1)
        zk = spec.get("height_m", 1.8) / 1.8
        m = (w > 0.7) & (np.abs(bp[:, 0]) < 0.3) & (bp[:, 1] < 0.05) & (bp[:, 2] > 0.6 * zk)
        idx = np.where(m)[0]
        if len(idx) == 0:
            continue
        j = idx[rng.randint(len(idx))]
        out.append((tuple(bp[j]), float(rng.uniform(0.05, 0.09)), bool(rng.rand() < 0.4)))
    spec[key] = out
    return out


def mouth_parts(cb, spec):
    """stained teeth + dark tongue (MakeHuman CC0 proxies) visible through the dropped jaw / receded lips."""
    H = cb.H
    for nm, rel, col in (("teeth", "teeth/teeth_base/teeth_base", spec.get("tooth", (0.52, 0.45, 0.32))), ("tongue", "tongue/tongue01/tongue01", (0.30, 0.09, 0.1))):
        try:
            Pp = mh.Proxy(A(rel + ".mhclo"))
        except Exception as e:
            print("[warn] mouth part", nm, e); continue
        pos = cb.conv(Pp.fit(H.v, H.base_v))
        cb.add_mesh(nm, pos, [f[0] for f in Pp.faces], [f[1] for f in Pp.faces], Pp.uv, bone="head", mat=solid_mat(f"{cb.name}_{nm}", col, 0.25 if nm == "teeth" else 0.35))


def zombie_face(cb, spec, hair, hair_tint, brow="eyebrows/eyebrow001/eyebrow001"):
    from specs import milky_eye_image
    spec.setdefault("iris", (0.92, 0.95, 1.0))
    c2.face_parts(cb, spec, hair=hair, hair_tint=hair_tint, brow=brow, brow_tint=(0.3, 0.3, 0.3), lashes=True, eye_tint=(0.7, 0.85, 1.0),
                  decim_hair=1.0, subdiv=False, eye_fn=milky_eye_image, lash_tint=(0.2, 0.2, 0.2), frost_hair=spec.get("hair_frost", 0.0), frost_brow=0.0)


def load_nrm_img(P, size=1024):
    d = os.path.dirname(os.path.join(mh.ASSETS, "clothes", P.name.replace(".mhclo", ""), "x"))
    return None


# ----------------------------------------------------------------------------- outfits
def spec_seed(cb):
    return cb.spec.get('seed', 1) + 3


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
        for (hc, hr) in pc.get("holes", []):
            dd = np.linalg.norm(pos - np.array(hc)[None], axis=1)
            ragged = hr * (0.75 + 0.5 * gore.fbm(pos, 30, spec_seed(cb)))
            mask = mask & (dd > ragged)
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


def _sac_plan():
    return SAC_PLAN


BURSTER_LOCAL = [("spine_01", (0, 0.12, 0.2), 0.26), ("spine_01", (0.16, 0.1, 0.14), 0.18), ("spine_01", (-0.16, 0.14, 0.13), 0.17),
                 ("spine_03", (-0.12, 0.08, 0.13), 0.13), ("spine_03", (0.1, 0.18, 0.12), 0.12), ("spine_03", (0.0, 0.1, -0.15), 0.2)]   # same as actors/enemies/burster.gd


def burster_holes(cb):
    """torn-open tee: holes where the spore sacs push through (belly, flanks, chest, back). bone-local (x left, y up, z fwd) -> blender (x, -z, y)."""
    out = []
    k = cb.spec.get("height_m", 1.75) / 1.75
    for bone, (lx, ly, lz), r in BURSTER_LOCAL:
        o, _ = bone_pts(cb, bone, 0.0)
        out.append((tuple(o + np.array([lx, -lz, ly]) * k), r * k * 0.95))
    return {"tee": out, "jeans": []}


HOLES = {"burster": burster_holes}


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
                       painter=P_(col, 0.45, "coat", rough=0.85, bands=spec.get("hivis", False)), dec=0.55, inflate=0.012 if o != "jacket" else 0.006,
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
                  dict(match=lambda zmin, zmax, n_: zmax < 1.25 and n_ < 1000, label="skirt", painter=P_(col2, 0.25, "skirt"), dec=0.6)]
    elif o == "dress":
        s_rel, s_png = SUIT["felegant"]
        pieces = [dict(match=lambda zmin, zmax, n_: zmax > 1.0 and n_ > 1000, label="gown", painter=P_(col, 0.25, "gown"), dec=0.6),
                  dict(match=lambda zmin, zmax, n_: zmax < 1.25 and n_ < 1000, label="skirt", painter=P_(col2, 0.25, "skirt"), dec=0.6, stretch=(None, 1.7, 0.1))]
    elif o == "miner":
        s_rel, s_png = SUIT["work"]
        pieces = [dict(match=lambda zmin, zmax, n_: zmin < 0.4 and zmax > 1.2 and n_ > 1500, label="overalls", painter=P_(col, 0.7, "overalls"), dec=0.5),
                  dict(match=lambda zmin, zmax, n_: zmax > 1.2 and zmin > 0.5 and n_ > 500, label="shirt", painter=P_(col2, 0.6, "shirt"), dec=0.55)]
    else:
        raise ValueError(o)
    if spec.get("skip_pieces"):
        pieces = [pc for pc in pieces if pc["label"] not in spec["skip_pieces"]]
    if spec.get("holes_fn"):
        hs = HOLES[spec["holes_fn"]](cb)
        for pc in pieces:
            if pc["label"] in hs:
                pc["holes"] = hs[pc["label"]]
    tears = tear_spots(cb, spec)
    for pc in pieces:
        if pc["label"] not in ("trousers", "jeans", "pants", "skirt"):
            pc["holes"] = list(pc.get("holes", [])) + [(c_, r_) for c_, r_, _ in tears]
    keep_dv = suit_pieces_g(cb, s_rel, A(s_png), pieces)
    if tears:
        bpt = cb.conv(H.v[:mh.N_BODY])
        near = np.zeros(mh.N_BODY, dtype=bool)
        for c_, r_, _ in tears:
            near |= np.linalg.norm(bpt - np.array(c_)[None], axis=1) < r_ * 1.5
        keep_dv = {i for i in keep_dv if i >= mh.N_BODY or not near[i]}
    if spec.get("bare_above") is not None:
        bp_ = cb.conv(H.v[:mh.N_BODY])
        keep_dv = {i for i in keep_dv if i >= mh.N_BODY or bp_[i, 2] < spec["bare_above"]}       # skin stays above this height
    dv |= keep_dv
    if boots:
        dv |= c2.make_boots(cb, boots[0], boots[1], top=boots[2], widen=(1.1, 1.08, 1.12 if boots[2] > 0.15 else 1.0), dec=0.4)
    if glove:
        dv |= c2.glove_hands(cb, glove, dec=0.3)
    bpos = cb.conv(H.v[:mh.N_BODY])
    if boots:
        dv |= set(np.where(bpos[:, 2] < (0.26 if boots[2] > 0.15 else 0.14))[0].tolist())
    else:
        dv |= set(np.where(bpos[:, 2] < 0.012)[0].tolist())      # bare feet stay (frostbitten, see zombie_skin)
    skin_mat = make_pbr(n + "_skin", sk_d, sk_n, sk_mr, rough=0.6, spec=0.35)
    body = cb.build_body(sorted(dv))
    body.data.materials.append(skin_mat)
    cb.decimate(body, spec.get("body_dec", 0.4))
    d = c2.head_dims(cb)
    if spec.get("clean"):
        c2.face_parts(cb, spec, hair=spec.get("hair"), hair_tint=spec.get("hair_tint"), brow="eyebrows/eyebrow002/eyebrow002", brow_tint=(0.35, 0.3, 0.28),
                      lashes=spec.get("gender", 1) < 0.5, eye_tint=(0.8, 0.85, 1.0), decim_hair=1.0, subdiv=True)
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


SAC_PLAN = [("spine_01", (0.0, -0.20, 0.02), 0.21), ("spine_01", (0.16, -0.14, 0.04), 0.14), ("spine_01", (-0.17, -0.12, 0.0), 0.15),
            ("spine_02", (0.0, -0.17, 0.02), 0.12), ("spine_03", (-0.1, -0.13, 0.02), 0.095), ("spine_03", (0.0, 0.14, 0.05), 0.15),
            ("spine_02", (0.1, 0.12, -0.02), 0.11), ("upperarm_l", (0.04, 0.0, 0.0), 0.075), ("upperarm_r", (-0.04, 0.0, 0.02), 0.07),
            ("neck_01", (0.05, -0.04, 0.0), 0.05), ("thigh_l", (0.05, -0.06, 0.0), 0.08), ("thigh_r", (-0.03, 0.07, 0.0), 0.07)]


def lumpy_sphere(c, r, seed, seg=12, rings=8, squash=(1, 1, 1), lump=0.14):
    V, F = sphere_mesh(c, r, seg, rings, squash)
    c = np.array(c)
    d = V - c
    n = gore.fbm(V * 18.0, 1.0, seed)
    V = c + d * (1.0 + lump * (n[:, None] - 0.5) * 2)
    return V, F


def extra_sacs(cb, spec):
    """glowing frost-spore sacs bulging from the Burster's torso / limbs (named *sac* / *sac_core* for the AI to pulse)."""
    sac_m = ice_mat(cb, "sac", (0.45, 0.9, 0.95), 1.4)
    core_m = ice_mat(cb, "sac_core", (0.7, 1.0, 1.0), 4.0)
    core_m.node_tree.nodes["Principled BSDF"].inputs["Alpha"].default_value = 1.0
    k = spec.get("height_m", 1.75) / 1.75
    for i, (bone, off, r) in enumerate(SAC_PLAN):
        p, axis = bone_pts(cb, bone, 0.5)
        c = p + np.array(off)
        V, F = lumpy_sphere(c, r * k * 1.1, 70 + i, 12, 8, (1, 1, 0.85))
        cb.add_mesh(f"sac_{i}", V, F, bone=bone, mat=sac_m)
        if i < 8:
            V2, F2 = sphere_mesh(c, r * k * 0.5, 8, 5)
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


def extra_filaments(cb, spec):
    """ankle filaments are generated at runtime (actors/enemies/hanger.gd); nothing baked."""
    return None
