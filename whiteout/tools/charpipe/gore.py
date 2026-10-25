"""Position-driven gore / frostbite fields for baked textures (numpy only).

fields(p, nrm, seed, anchors, cfg) -> dict of per-texel arrays:
   blood (0..1 blood coverage), flesh (0..1 exposed wet flesh), frost (0..1), h (height for bump)
Everything is a function of the 3D surface point, so seams between UV islands and between garment / skin match."""
import numpy as np
import paint as pt


def n3(p, f=1.0, seed=0):
    """cheap smooth 3D noise in [0,1] (sum of sines)."""
    q = p * f + seed * 7.13
    v = (np.sin(q[:, 0] * 1.31 + np.sin(q[:, 1] * 0.77 + seed)) + np.sin(q[:, 1] * 1.73 + np.sin(q[:, 2] * 1.1)) +
         np.sin(q[:, 2] * 1.57 + np.sin(q[:, 0] * 0.9 + 2.0)) + np.sin((q[:, 0] + q[:, 1] + q[:, 2]) * 0.71)) * 0.25
    return v * 0.5 + 0.5


def fbm(p, f, seed=0):
    return 0.55 * n3(p, f, seed) + 0.3 * n3(p, f * 2.3, seed + 1) + 0.15 * n3(p, f * 5.1, seed + 2)


def wound(p, c, r, seed, nz=0.4):
    """irregular disc mask (0..1, core ~1) + rim ring"""
    d = np.linalg.norm(p - c, axis=1) / r
    d = d * (1.0 + nz * (fbm(p, 60.0 / max(r * 10, 0.3), seed) - 0.5) * 2)
    core = pt.smoothstep(1.0, 0.55, d)
    rim = pt.smoothstep(1.7, 1.0, d) * (1 - core)
    return core, rim


def drip(p, c, length, width, seed):
    """vertical blood streaks below c (world z down)"""
    dz = c[2] - p[:, 2]
    lat = np.hypot(p[:, 0] - c[0], p[:, 1] - c[1])
    m = np.zeros(len(p))
    for k in range(3):
        off = (n3(p * 0 + k, 1, seed + k)[0] - 0.5) * 2 * width * 3
        lx = np.hypot(p[:, 0] - (c[0] + off * 0.8), p[:, 1] - c[1])
        ln = length * (0.5 + 0.5 * ((seed * 7 + k * 13) % 10) / 10.0)
        wv = width * (0.4 + 0.6 * pt.smoothstep(0, 0.3 * ln, dz)) * (1 - 0.7 * pt.smoothstep(0.4 * ln, ln, dz))
        wv = wv * (0.7 + 0.6 * fbm(p, 120, seed + k))
        m = np.maximum(m, pt.smoothstep(wv, wv * 0.4, lx) * pt.smoothstep(-0.005, 0.01, dz) * pt.smoothstep(ln, ln * 0.85, dz))
    return m


def fields(p, nrm, seed, anchors, cfg):
    """anchors: dict(mouth=(x,y,z) or None, pts=[(x,y,z)...] candidate wound centres, front=bool)"""
    rng = np.random.RandomState(seed)
    N = len(p)
    blood = np.zeros(N); flesh = np.zeros(N); frost = np.zeros(N); h = np.zeros(N); dark = np.zeros(N)
    fwd = pt.smoothstep(0.0, -0.45, nrm[:, 1])          # facing forward (-y)
    # --- blood from the mouth down chin / neck / chest
    mo = anchors.get("mouth")
    amt = cfg.get("mouth", 0.0)
    if mo is not None and amt > 0:
        mo = np.array(mo)
        dz = mo[2] - p[:, 2]
        L = 0.25 + 0.5 * amt
        wid = (0.03 + 0.03 * amt) * (1 - 0.5 * pt.smoothstep(0.0, L, dz)) * (0.8 + 0.5 * fbm(p, 80, seed))
        cx = mo[0] + (fbm(p * np.array([0, 1, 1]) + 3, 25, seed + 5) - 0.5) * 0.04
        ribbon = pt.smoothstep(wid, wid * 0.35, np.abs(p[:, 0] - cx)) * pt.smoothstep(-0.015, 0.0, dz) * pt.smoothstep(L, L * 0.55, dz) * fwd
        # clotted edges + runs
        ribbon = ribbon * (0.75 + 0.5 * fbm(p, 140, seed + 9))
        around = pt.smoothstep(0.05, 0.012, np.hypot(p[:, 0] - mo[0], (p[:, 2] - (mo[2] - 0.012)) * 1.2)) * fwd * amt * 0.85   # around the lips/chin
        blood = np.maximum(blood, np.clip(ribbon * (0.6 + 0.6 * amt) + around, 0, 1))
    # --- bite wounds / torn flesh
    pts = list(anchors.get("pts", []))
    nw = cfg.get("wounds", 0)
    rng.shuffle(pts)
    for i in range(min(nw, len(pts))):
        c = np.array(pts[i])
        r = rng.uniform(0.028, 0.06) * cfg.get("wound_scale", 1.0)
        core, rim = wound(p, c, r, seed + i * 3)
        flesh = np.maximum(flesh, core)
        blood = np.maximum(blood, np.clip(rim * 0.95 + drip(p, c, rng.uniform(0.12, 0.35), r * 0.55, seed + i), 0, 1))
        h = h - core * 1.0 + rim * 0.55
    # larger torn patches of exposed flesh (cloth only uses these)
    nt = cfg.get("torn", 0)
    for i in range(min(nt, max(0, len(pts) - nw))):
        c = np.array(pts[nw + i])
        r = rng.uniform(0.06, 0.12) * cfg.get("wound_scale", 1.0)
        core, rim = wound(p, c, r, seed + 40 + i, nz=0.7)
        flesh = np.maximum(flesh, core * 0.95)
        blood = np.maximum(blood, rim * 0.9)
        h = h - core * 0.8 + rim * 0.7
        dark = np.maximum(dark, rim)
    # --- splatter
    sp = cfg.get("splat", 0.0)
    if sp > 0:
        m = fbm(p, 55.0, seed + 70)
        s1 = pt.smoothstep(0.74 - 0.08 * sp, 0.8 - 0.08 * sp, m) * (0.5 + 0.5 * fbm(p, 200, seed + 71)) * fwd
        blood = np.maximum(blood, s1 * sp)
    # --- blood soaking down from the wounds into cloth (broad)
    soak = cfg.get("soak", 0.0)
    if soak > 0 and mo is not None:
        dz = mo[2] - p[:, 2]
        broad = pt.smoothstep(0.55, 0.05, np.abs(p[:, 0] - mo[0])) * pt.smoothstep(0.0, 0.1, dz) * pt.smoothstep(0.7, 0.3, dz) * fwd
        broad = broad * pt.smoothstep(0.5, 0.75, fbm(p, 24, seed + 80)) * soak * 0.6
        blood = np.maximum(blood, np.clip(broad, 0, 0.6))
    hem = cfg.get('hem', 0.0)
    if hem > 0:
        lowz = anchors.get('hem_z')
        if lowz is not None:
            m = pt.smoothstep(lowz + 0.14, lowz, p[:, 2]) * pt.smoothstep(0.4, 0.7, fbm(p, 40, seed + 85)) * hem
            blood = np.maximum(blood, np.clip(m, 0, 0.75))
    # --- frost rime on up-facing surfaces / edges
    fr = cfg.get("frost", 0.0)
    if fr > 0:
        up = pt.smoothstep(0.25, 0.8, nrm[:, 2])
        fm = pt.smoothstep(0.55, 0.8, fbm(p, 45.0, seed + 90))
        frost = np.clip((up * 0.8 + fm * 0.15 * up + fm * 0.12) * fr * (0.6 + 0.6 * fbm(p, 160, seed + 91)), 0, 1)
    return dict(blood=blood, flesh=flesh, frost=frost, h=h, dark=dark)


BLOOD_FRESH = np.array([0.29, 0.024, 0.024])
BLOOD_DRY = np.array([0.17, 0.045, 0.035])
FLESH = np.array([0.52, 0.09, 0.075])
FLESH_DARK = np.array([0.20, 0.02, 0.02])
FAT = np.array([0.78, 0.55, 0.42])
FROST = np.array([0.80, 0.90, 0.96])


def shade(col, rough, f, p, seed):
    """apply fields to base colour/roughness arrays. returns col, rough"""
    b = f["blood"]; fl = f["flesh"]
    thick = np.clip(b * (0.6 + 0.8 * fbm(p, 70, seed + 100)), 0, 1)
    fresh = pt.smoothstep(0.45, 0.85, thick) * (0.6 + 0.4 * fbm(p, 30, seed + 101))
    bc = BLOOD_DRY[None] + (BLOOD_FRESH - BLOOD_DRY)[None] * fresh[:, None]
    col = col * (1 - 0.92 * thick[:, None]) + bc * 0.92 * thick[:, None]
    fc = FLESH_DARK[None] + (FLESH - FLESH_DARK)[None] * pt.smoothstep(0.1, 0.9, fl * (0.7 + 0.5 * fbm(p, 90, seed + 102)))[:, None]
    fat = (fbm(p, 220, seed + 103) > 0.7)[:, None] * FAT[None] * 0.5
    fc = fc * (1 - fat * 0.5) + fat * 0.5
    col = col * (1 - fl[:, None]) + fc * fl[:, None]
    fr = f["frost"]
    col = col * (1 - fr[:, None] * 0.7) + FROST[None] * fr[:, None] * 0.7
    rough = rough * (1 - thick) + (0.6 - 0.46 * fresh) * thick
    rough = rough * (1 - fl) + 0.2 * fl
    rough = rough * (1 - fr * 0.6) + 0.5 * fr * 0.6
    return col, rough


def normal_from_height(Himg, base_nrm=None, strength=2.5, flat=None):
    """Himg (S,S) height -> tangent-space normal image (S,S,3) in 0..1 (OpenGL +Y)."""
    Hb = pt.blur(Himg, 1)
    gy, gx = np.gradient(Hb)
    nx = -gx * strength; ny = gy * strength
    S = Himg.shape[0]
    if base_nrm is not None:
        bx = base_nrm[..., 0] * 2 - 1; by = base_nrm[..., 1] * 2 - 1
        if flat is not None:
            bx = bx * (1 - flat); by = by * (1 - flat)
        nx = nx + bx; ny = ny + by
    nz = np.sqrt(np.clip(1 - nx * nx - ny * ny, 0.05, 1))
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    out = np.stack([nx / l, ny / l, nz / l], axis=2) * 0.5 + 0.5
    return out
