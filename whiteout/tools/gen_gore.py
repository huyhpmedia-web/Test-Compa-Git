#!/usr/bin/env python3
"""Procedural gore decal textures for WHITEOUT: KETTLE FALLS.   Run:  python3 -I tools/gen_gore.py

No suitable CC0 blood-decal set exists on the reachable mirrors (the MorePET/mat-vis release holds
tiling surface materials, not decals), so every texture here is generated (numpy + PIL, seeded and
deterministic; our own work, CC0).  Per decal <name> three maps are written to textures/gore/:

    <name>_a.png   albedo RGBA (alpha = coverage; dark, translucent thin film, congealed rim, clots)
    <name>_n.png   normal map (OpenGL, meniscus rim + clot relief)
    <name>_o.png   ORM (R=occlusion, G=roughness: glossy wet centre, duller rim / clots, B=metal 0)
    <name>_i.png   optional ichor (Rimebound fluid: cyan-tinged black) albedo variant

Blood is physically dark: thick pooled blood has linear albedo ~0.05, thin film ~0.3.  Gloss comes
from the roughness map (~0.07 wet) so flashlight / lamp highlights slide across it.
"""
import os
import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "textures", "gore"))
os.makedirs(OUT, exist_ok=True)
SS = 3  # supersampling for drawn shapes

# ------------------------------------------------------------------ numeric helpers


def noise(w, h, seed, beta=2.0, lo=0.0, hi=1e9):
    rng = np.random.default_rng(seed)
    f = np.fft.rfft2(rng.standard_normal((h, w)))
    fy = np.fft.fftfreq(h)[:, None] * h
    fx = np.fft.rfftfreq(w)[None, :] * w
    r = np.sqrt(fx * fx + fy * fy)
    r[0, 0] = 1.0
    f = f / r ** beta
    f[(r < lo) | (r > hi)] = 0
    f[0, 0] = 0
    n = np.fft.irfft2(f, s=(h, w))
    return (n - n.mean()) / (n.std() + 1e-9)


def gblur(a, sigma):
    if sigma <= 0.01:
        return a
    h, w = a.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.rfftfreq(w)[None, :]
    k = np.exp(-2.0 * (np.pi * sigma) ** 2 * (fx * fx + fy * fy))
    return np.fft.irfft2(np.fft.rfft2(a) * k, s=(h, w))


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0 + 1e-9), 0, 1)
    return t * t * (3 - 2 * t)


class Cv:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.im = Image.new("L", (w * SS, h * SS), 0)
        self.d = ImageDraw.Draw(self.im)

    def poly(self, pts, v=255):
        self.d.polygon([(x * SS, y * SS) for x, y in pts], fill=v)

    def circ(self, x, y, r, v=255):
        self.d.ellipse([(x - r) * SS, (y - r) * SS, (x + r) * SS, (y + r) * SS], fill=v)

    def ell(self, cx, cy, rx, ry, ang=0.0, v=255, n=18):
        t = np.linspace(0, 2 * np.pi, n, endpoint=False)
        ca, sa = np.cos(ang), np.sin(ang)
        px = rx * np.cos(t)
        py = ry * np.sin(t)
        self.poly(list(zip(cx + px * ca - py * sa, cy + px * sa + py * ca)), v)

    def taper(self, x0, y0, x1, y1, w0, w1, v=255, caps=True):
        dx, dy = x1 - x0, y1 - y0
        L = max(np.hypot(dx, dy), 1e-6)
        nx, ny = -dy / L, dx / L
        self.poly([(x0 + nx * w0, y0 + ny * w0), (x1 + nx * w1, y1 + ny * w1),
                   (x1 - nx * w1, y1 - ny * w1), (x0 - nx * w0, y0 - ny * w0)], v)
        if caps:
            self.circ(x0, y0, w0, v)
            self.circ(x1, y1, w1, v)

    def arr(self):
        im = self.im.resize((self.w, self.h), Image.BOX)
        return np.asarray(im).astype(np.float32) / 255.0


# ------------------------------------------------------------------ blood shader (maps)

BLOOD = dict(thin=(0.34, 0.012, 0.016), thick=(0.075, 0.004, 0.007), edge=(0.05, 0.008, 0.008), clot=(0.022, 0.003, 0.005))
ICHOR = dict(thin=(0.018, 0.09, 0.10), thick=(0.006, 0.026, 0.032), edge=(0.01, 0.022, 0.022), clot=(0.004, 0.012, 0.015))


def _col(c, shape):
    return np.stack([np.full(shape, c[0], np.float32), np.full(shape, c[1], np.float32), np.full(shape, c[2], np.float32)], -1)


def srgb(lin):
    return np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.power(np.maximum(lin, 1e-6), 1 / 2.4) - 0.055)


def shade(m, seed, pal=BLOOD, thick_sigma=None, clot_amt=1.0, wet=1.0, relief=1.0, opacity=0.97, film=0.0):
    """m: coverage mask 0..1 -> (albedo RGBA u8, normal RGB u8, orm RGB u8)"""
    h, w = m.shape
    sc = w / 512.0
    ts = thick_sigma if thick_sigma else 7.0 * sc
    n1 = noise(w, h, seed, 1.5)
    n2 = noise(w, h, seed + 1, 2.4)
    n3 = noise(w, h, seed + 2, 1.0, lo=w / 40)
    soft = np.clip(gblur(m, 0.9 * sc), 0, 1)
    body = gblur(m, ts)
    # thickness: interior of big areas is deep, droplets / streak tips are thin film
    t = np.clip(body * 2.2 + 0.22 * n1 * body + film, 0, 1)
    edge = np.clip(soft - body * 1.25, 0, 1)
    edge = np.clip(edge * 2.5, 0, 1)
    clot_field = n1 * 0.7 + n3 * 0.45 + (t - 0.55) * 2.2
    clot = smooth(0.85, 1.45, clot_field) * clot_amt * (t > 0.35)
    clot = np.clip(gblur(clot.astype(np.float32), 1.0 * sc), 0, 1)
    alpha = np.clip((soft - 0.03) / 0.42, 0, 1) ** 0.85
    alpha *= opacity * (0.82 + 0.18 * t)
    # colour
    shape = m.shape
    c_thin, c_thick, c_edge, c_clot = (_col(pal[k], shape) for k in ("thin", "thick", "edge", "clot"))
    tt = t[..., None]
    col = c_thin * (1 - tt) + c_thick * tt
    col = col * (1 - edge[..., None] * 0.7) + c_edge * edge[..., None] * 0.7
    col = col * (1 - clot[..., None]) + c_clot * clot[..., None]
    col = col * (0.9 + 0.12 * n2[..., None])
    # pull the rgb of fully transparent texels toward the rim colour (clean mip borders)
    rgb = np.clip(srgb(np.clip(col, 0, 1)), 0, 1)
    alb = np.dstack([rgb, alpha])
    # height -> normal
    hgt = t * 0.55 * relief + edge * 0.45 * relief + clot * 0.35 + 0.035 * n2 * body
    hgt = gblur(hgt, 0.7 * sc)
    gy, gx = np.gradient(hgt)
    k = 7.0 * sc * relief
    nx, ny, nz = -gx * k, gy * k, np.ones_like(hgt)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.dstack([nx / ln, ny / ln, nz / ln]) * 0.5 + 0.5
    # orm
    rough = (0.07 + 0.30 * edge + 0.42 * clot + 0.05 * n2) / max(wet, 0.2)
    rough = np.clip(rough + (1 - t) * 0.06, 0.03, 1.0)
    orm = np.dstack([1.0 - 0.35 * clot, rough, np.zeros_like(rough)])
    u8 = lambda a: (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)
    return u8(alb), u8(nrm), u8(orm), (t, edge, clot, n1, n2)


def save(name, m, seed, ichor=False, **kw):
    a, n, o, aux = shade(m, seed, **kw)
    Image.fromarray(a, "RGBA").save(f"{OUT}/{name}_a.png", optimize=True)
    Image.fromarray(n, "RGB").save(f"{OUT}/{name}_n.png", optimize=True)
    Image.fromarray(o, "RGB").save(f"{OUT}/{name}_o.png", optimize=True)
    if ichor:
        kw2 = dict(kw)
        kw2["pal"] = ICHOR
        a2, _, _, _ = shade(m, seed, **kw2)
        Image.fromarray(a2, "RGBA").save(f"{OUT}/{name}_i.png", optimize=True)
    print("wrote", name, m.shape)


# ------------------------------------------------------------------ shapes


def splat_into(cv, cx, cy, R, rng, n_spikes, n_sat, reach, elong, wmax, spike_len=(1.3, 3.0)):
    t = np.linspace(0, 2 * np.pi, 90, endpoint=False)
    ph = rng.uniform(0, 6.28, 4)
    r = R * (1 + 0.22 * np.sin(3 * t + ph[0]) + 0.14 * np.sin(5 * t + ph[1]) + 0.1 * np.sin(8 * t + ph[2]) + 0.05 * np.sin(13 * t + ph[3]))
    cv.poly(list(zip(cx + r * np.cos(t), cy + r * np.sin(t))))
    angs = []
    for i in range(n_spikes):
        a = rng.uniform(0, 6.283)
        angs.append(a)
        L = R * rng.uniform(*spike_len) * (0.6 + 0.8 * rng.random())
        wb = R * rng.uniform(0.06, 0.16)
        x0, y0 = cx + np.cos(a) * R * 0.7, cy + np.sin(a) * R * 0.7
        x1, y1 = cx + np.cos(a) * L, cy + np.sin(a) * L
        # slightly wobbly two-segment spike
        mx, my = (x0 + x1) / 2 + rng.normal(0, wb * 0.6), (y0 + y1) / 2 + rng.normal(0, wb * 0.6)
        cv.taper(x0, y0, mx, my, wb, wb * 0.6)
        cv.taper(mx, my, x1, y1, wb * 0.6, wb * 0.18)
        if rng.random() < 0.8:
            cv.circ(x1 + np.cos(a) * wb * 0.6, y1 + np.sin(a) * wb * 0.6, wb * rng.uniform(0.55, 1.0))
    half = min(cv.w, cv.h) * 0.47
    for i in range(n_sat):
        u = rng.random()
        dist = R * 1.15 + reach * max(half - R * 1.15, 1) * u ** 1.5
        a = rng.choice(angs) + rng.normal(0, 0.28) if (angs and rng.random() < 0.6) else rng.uniform(0, 6.283)
        rr = 0.8 + wmax * (rng.random() ** 3.2) * (1.0 - 0.55 * u)
        e = 1.0 + elong * (dist / half) * 2.2
        px, py = cx + np.cos(a) * dist, cy + np.sin(a) * dist
        if 2 < px < cv.w - 2 and 2 < py < cv.h - 2:
            cv.ell(px, py, rr * e, rr, a, n=12)


def gen_splat(name, seed, S=512, R=0.1, spikes=14, sat=110, reach=1.0, elong=0.4, wmax=0.022, **kw):
    rng = np.random.default_rng(seed)
    cv = Cv(S, S)
    splat_into(cv, S / 2, S / 2, R * S, rng, spikes, sat, reach, elong, wmax * S)
    save(name, cv.arr(), seed, ichor=True, **kw)


def gen_splat_impact(name, seed, S=512):
    """wall impact: oriented along +x, dense droplets with long tails flying forward."""
    rng = np.random.default_rng(seed)
    cv = Cv(S, S)
    cx, cy = S * 0.24, S / 2
    splat_into(cv, cx, cy, S * 0.07, rng, 9, 0, 0, 0, 1)
    for i in range(170):
        u = rng.random() ** 1.3
        x = cx + S * 0.06 + u * S * 0.66
        y = cy + rng.normal(0, 0.035 * S + u * 0.1 * S)
        r = 1.0 + S * 0.0125 * (rng.random() ** 3) * (1.1 - u * 0.6)
        ln = r * (1.6 + 5.0 * u + 3 * rng.random())
        ang = np.arctan2(y - cy, x - cx)
        cv.taper(x - np.cos(ang) * ln, y - np.sin(ang) * ln, x, y, r * 0.25, r)
    save(name, cv.arr(), seed, ichor=True)


def gen_spray(name, seed, W=1024, H=512, arcs=False, ichor=False):
    rng = np.random.default_rng(seed)
    cv = Cv(W, H)
    ox, oy = W * 0.05, H / 2
    splat_into(cv, ox + W * 0.03, oy, H * 0.05, rng, 7, 0, 0, 0, 1, (1.2, 2.2))
    sc = H / 512
    for i in range(80 if not arcs else 55):
        a = rng.normal(0, 0.2)
        u = rng.beta(1.3, 2.0)
        L = W * (0.06 + 0.88 * u)
        x, y = ox + np.cos(a) * L, oy + np.sin(a) * L * 0.9
        if x > W - 6 or abs(y - H / 2) > H / 2 - 6:
            continue
        r = (1.2 + 7.5 * (rng.random() ** 2.6) * (1.2 - u * 0.5)) * sc
        ln = r * rng.uniform(2.2, 7.0)
        cv.taper(x - np.cos(a) * ln, y - np.sin(a) * ln * 0.9, x, y, r * 0.2, r)
    for i in range(120):
        u = rng.random() ** 1.2
        x = ox + u * W * 0.9
        y = oy + rng.normal(0, 0.05 * H + u * 0.13 * H)
        r = (0.8 + 2.3 * rng.random() ** 2) * sc
        cv.ell(x, y, r * 1.7, r, rng.normal(0, 0.2), n=8)
    if arcs:
        for k in range(5):
            ph = rng.uniform(-0.5, 0.5)
            curv = rng.uniform(-0.55, 0.55) * H
            n = rng.integers(9, 17)
            for j in range(n):
                t = (j + 1) / n * rng.uniform(0.85, 1.0)
                x = ox + t * W * 0.88
                y = oy + ph * t * H * 0.5 + curv * (t ** 2) * (1.0 if curv > 0 else 1.0)
                if abs(y - H / 2) > H / 2 - 8:
                    break
                r = (6.5 - 5.0 * t) * rng.uniform(0.7, 1.2) * sc
                cv.ell(x, y, r * 1.6, r, np.arctan2(curv * 2 * t + ph * H * .5, W * 0.88), n=10)
    save(name, cv.arr(), seed, ichor=ichor, thick_sigma=4.5 * sc)


def gen_pool(name, seed, S=512, lobes=3, tendrils=7, drops=40, ichor=True, ragged=0.1):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    x, y = (xx - S / 2) / (S / 2), (yy - S / 2) / (S / 2)
    r = np.sqrt(x * x + y * y)
    th = np.arctan2(y, x)
    thr = 0.6 + 0.0 * r
    for k in range(2, 2 + lobes + 2):
        thr += rng.uniform(0.02, 0.07) * np.cos(k * th + rng.uniform(0, 6.28)) / (k * 0.35)
    thr += 0.04 * noise(S, S, seed, 2.5, hi=7)
    d = r + ragged * noise(S, S, seed + 7, 1.6, lo=3, hi=30) * 0.5
    mask = smooth(thr + 0.012, thr - 0.012, d)
    cv = Cv(S, S)
    for i in range(tendrils):
        a = rng.uniform(0, 6.283)
        x0, y0 = S / 2 + np.cos(a) * S * 0.29, S / 2 + np.sin(a) * S * 0.29
        L = S * rng.uniform(0.06, 0.12)
        w0 = S * rng.uniform(0.012, 0.03)
        x1, y1 = x0 + np.cos(a + rng.normal(0, .3)) * L, y0 + np.sin(a + rng.normal(0, .3)) * L
        cv.taper(x0, y0, x1, y1, w0, w0 * 0.3)
        if rng.random() < 0.6:
            cv.circ(x1, y1, w0 * 0.7)
    for i in range(drops):
        a = rng.uniform(0, 6.283)
        dist = S * rng.uniform(0.42, 0.485)
        rr = 1 + S * 0.01 * rng.random() ** 2.5
        cv.ell(S / 2 + np.cos(a) * dist, S / 2 + np.sin(a) * dist, rr * 1.2, rr, a, n=10)
    m = np.maximum(mask, cv.arr())
    save(name, m, seed, ichor=ichor, thick_sigma=14 * S / 512, relief=0.8, clot_amt=0.35)


def gen_smear(name, seed, W=1024, H=256, ichor=True):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    u = xx / W
    cy = H / 2 + 0.10 * H * np.sin(u * 5.5 + rng.uniform(0, 6)) + 0.04 * H * np.sin(u * 13)
    hw = H * 0.34 * (1 - 0.55 * u ** 1.4) + 6 * noise(W, H, seed, 1.5, hi=6)
    inband = smooth(1.0, 0.0, np.abs(yy - cy) / np.maximum(hw, 2))
    # streaky wipe coverage (noise stretched along x)
    lo = noise(W // 24 + 2, H, seed + 3, 1.0)
    streak = np.asarray(Image.fromarray(lo.astype(np.float32), "F").resize((W, H), Image.BICUBIC))
    cover = 1.15 - u * 1.25 + 0.55 * streak + 0.2 * noise(W, H, seed + 4, 1.2, lo=8)
    mask = np.clip(inband * 1.2, 0, 1) * smooth(0.0, 0.35, cover)
    cv = Cv(W, H)
    splat_into(cv, W * 0.12, H / 2, H * 0.2, rng, 8, 40, 0.5, 0.5, H * 0.03, (1.2, 2.2))
    for i in range(40):
        x = rng.uniform(0.1, 0.8) * W
        y = H / 2 + rng.normal(0, H * 0.3)
        r = 1 + 4 * rng.random() ** 2
        cv.ell(x, y, r * 2, r, 0, n=8)
    m = np.clip(np.maximum(mask, cv.arr()), 0, 1)
    m[:, :6] *= 0.0 + np.linspace(0.0, 1, 6)[None, :]
    save(name, m.astype(np.float32), seed, ichor=ichor, thick_sigma=7 * W / 1024, film=0.0)


def gen_drag(name, seed, W=1024, H=256, ichor=False, twin=False):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    u = xx / W
    ph = rng.uniform(0, 6)
    cy = H / 2 + 0.16 * H * np.sin(u * 4.2 + ph) + 0.05 * H * np.sin(u * 11 + ph * 2)
    wid = H * (0.17 + 0.05 * noise(W, H, seed, 1.5, hi=5)) * (1 + 0.15 * np.sin(u * 40))
    mask = np.zeros((H, W), np.float32)
    offs = [0.0] if not twin else [-0.17 * H, 0.17 * H]
    for off in offs:
        wd = wid * (0.5 if twin else 1.0)
        band = smooth(1.0, 0.55, np.abs(yy - cy - off) / np.maximum(wd, 2))
        lo = noise(W // 28 + 2, H, seed + 5, 1.0)
        streak = np.asarray(Image.fromarray(lo.astype(np.float32), "F").resize((W, H), Image.BICUBIC))
        cov = 0.9 + 0.55 * streak + 0.3 * noise(W, H, seed + 6, 1.2, lo=6)
        mask = np.maximum(mask, band * smooth(0.1, 0.5, cov))
    cv = Cv(W, H)
    for i in range(55):
        x = rng.uniform(0.02, 0.98) * W
        yc = H / 2 + 0.16 * H * np.sin((x / W) * 4.2 + ph)
        y = yc + rng.normal(0, H * 0.28)
        r = 1 + 3.5 * rng.random() ** 2.5
        cv.ell(x, y, r * 1.6, r, rng.normal(0, 0.3), n=8)
    m = np.clip(np.maximum(mask, cv.arr()), 0, 1)
    fade = np.clip(np.minimum(u / 0.06, (1 - u) / 0.06), 0, 1)
    m *= fade
    save(name, m.astype(np.float32), seed, ichor=ichor, thick_sigma=6 * W / 1024)


def hand_mask(S, seed, mirror=False, smear=0.0, sp=1.0):
    rng = np.random.default_rng(seed)
    cv = Cv(S, S)
    pcx, pcy = 0.5 * S, 0.66 * S
    cv.ell(pcx, pcy, 0.19 * S, 0.165 * S, 0.0)
    cv.taper(pcx, pcy + 0.1 * S, pcx + 0.01 * S, S * 0.99, 0.11 * S, 0.12 * S, caps=False)
    fing = [(-0.145, -2, 0.33, 0.062), (-0.05, 0, 0.395, 0.066), (0.045, 2, 0.405, 0.066), (0.135, 4, 0.34, 0.058)]
    for bx, ang_deg, ln, wd in fing:
        a = np.deg2rad(ang_deg * 3.2 * sp + rng.normal(0, 2.0))
        x0, y0 = pcx + bx * S, pcy - 0.12 * S
        L = ln * S * rng.uniform(0.92, 1.06)
        x1, y1 = x0 + np.sin(a) * L, y0 - np.cos(a) * L
        cv.taper(x0, y0, x1, y1, wd * S, wd * S * 0.8)
    # thumb
    a = np.deg2rad(-62 * sp + rng.normal(0, 6))
    x0, y0 = pcx - 0.15 * S, pcy + 0.01 * S
    L = 0.24 * S
    cv.taper(x0, y0, x0 + np.sin(a) * L, y0 - np.cos(a) * L, 0.052 * S, 0.044 * S)
    m = cv.arr()
    # skin contact is incomplete: gaps and thin patches
    n = noise(S, S, seed, 1.4, lo=3)
    m = m * smooth(-0.9, -0.2, n + 0.3)
    if smear > 0:
        acc = m.copy()
        L = int(S * smear)
        base = m.copy()
        sm_noise = noise(S // 12 + 2, S, seed + 9, 1.0)
        sm_noise = np.asarray(Image.fromarray(sm_noise.astype(np.float32), "F").resize((S, S), Image.BICUBIC))
        for k in range(1, L, 3):
            sh = np.roll(base, k, axis=0)
            sh[:k] = 0
            fade = (1 - k / L) ** 1.4
            acc = np.maximum(acc, sh * fade * smooth(-0.8, 0.4, sm_noise + 0.6))
        m = acc
    if mirror:
        m = m[:, ::-1].copy()
    return m


def gen_hand(name, seed, mirror=False, smear=0.0, S=256):
    m = hand_mask(S, seed, mirror, smear)
    save(name, m, seed, thick_sigma=3.0, relief=0.6, film=0.12)


def gen_foot(name, seed, mirror=False, bare=False, W=128, H=256):
    rng = np.random.default_rng(seed)
    cv = Cv(W, H)
    cv.ell(W * 0.5, H * 0.3, W * 0.38, H * 0.22, 0.0)
    cv.poly([(W * 0.12, H * 0.3), (W * 0.86, H * 0.3), (W * 0.78, H * 0.78), (W * 0.3, H * 0.78)])
    cv.ell(W * 0.52, H * 0.84, W * 0.3, H * 0.12, 0.0)
    m = cv.arr()
    if bare:
        cv2 = Cv(W, H)
        for k, (tx, ty, tr) in enumerate([(0.26, 0.1, 0.07), (0.4, 0.07, 0.06), (0.52, 0.065, 0.055), (0.63, 0.08, 0.05), (0.73, 0.11, 0.045)]):
            cv2.ell(W * tx, H * ty, W * tr, W * tr * 1.15, 0.0)
        m = np.maximum(m, cv2.arr())
    else:
        # lug tread: cut horizontal slits
        yy = np.arange(H)[:, None] * np.ones((1, W))
        tread = (np.sin(yy / H * 60) > 0.35).astype(np.float32)
        tr = gblur(tread, 0.8)
        lug = noise(W, H, seed, 1.3, lo=3)
        m = m * (1 - 0.55 * tr * smooth(-0.8, 0.5, lug))
        cv3 = Cv(W, H)
        cv3.poly([(W * 0.3, H * 0.56), (W * 0.7, H * 0.56), (W * 0.7, H * 0.66), (W * 0.3, H * 0.66)], 255)
        m = m * (1 - 0.8 * cv3.arr() * 0.0)
    m = m * smooth(-1.3, -0.25, noise(W, H, seed + 3, 1.4, lo=2) + 0.4)
    # fades toward the toe (wet footprint: sharp heel, fading)
    m *= (0.55 + 0.45 * np.linspace(0, 1, H)[:, None] ** 0.6)
    if mirror:
        m = m[:, ::-1].copy()
    save(name, m.astype(np.float32), seed, thick_sigma=2.5, relief=0.5, film=0.15)


def gen_drips(name, seed, W=256, H=512, runs=7, ichor=False):
    rng = np.random.default_rng(seed)
    cv = Cv(W, H)
    cols = np.sort(rng.uniform(0.08, 0.92, runs)) * W
    # source smear along the top
    for x in np.linspace(0.02 * W, 0.98 * W, 14):
        cv.ell(x + rng.normal(0, 3), H * 0.03 + rng.normal(0, 3), W * 0.09, H * 0.03, rng.normal(0, 0.3))
    m_runs = np.zeros((H, W), np.float32)
    for x in cols:
        w0 = rng.uniform(3.0, 7.5)
        L = H * rng.uniform(0.2, 0.92) * (0.6 + 0.6 * rng.random())
        L = min(L, H * 0.93)
        ys = np.arange(0, int(L))
        wob = 1.6 * np.sin(ys / 27.0 + rng.uniform(0, 6)) + 1.0 * np.sin(ys / 11.0 + rng.uniform(0, 6))
        prev = None
        for y in ys[::3]:
            wd = w0 * (0.8 + 0.25 * np.sin(y / 31.0 + x))
            cx = x + wob[min(y, len(ys) - 1)]
            if prev is not None:
                cv.taper(prev[0], prev[1], cx, y, prev[2], wd, caps=False)
            prev = (cx, y, wd)
        # bulbous tip (drop about to fall)
        cv.circ(prev[0], prev[1], w0 * 1.25)
        cv.ell(prev[0], prev[1] - w0 * 1.5, w0 * 0.9, w0 * 1.8, 0.0)
        if rng.random() < 0.4:  # a detached falling drop below
            cv.ell(prev[0] + rng.normal(0, 1), prev[1] + w0 * 5, w0 * 0.55, w0 * 0.85, 0.0)
    m = np.clip(cv.arr(), 0, 1)
    save(name, m, seed, ichor=ichor, thick_sigma=3.2, relief=0.9, film=0.1)


def gen_puddle(name, seed, S=512):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    x, y = (xx - S / 2) / (S / 2), (yy - S / 2) / (S / 2)
    ang = rng.uniform(0, 3.14)
    xr = x * np.cos(ang) + y * np.sin(ang)
    yr = -x * np.sin(ang) + y * np.cos(ang)
    r = np.sqrt((xr / 0.95) ** 2 + (yr / 0.68) ** 2)
    d = r + 0.22 * noise(S, S, seed, 2.0, hi=9) + 0.05 * noise(S, S, seed + 2, 1.5, lo=8, hi=40)
    mask = smooth(0.83, 0.74, d).astype(np.float32)
    soft = gblur(mask, 1.2)
    rim = np.clip(soft - gblur(mask, 5.0) * 1.1, 0, 1) * 2.5
    alpha = np.clip(soft, 0, 1) * (0.78 - 0.1 * np.clip(gblur(mask, 18), 0, 1)) + 0.0
    col = np.dstack([0.012 + rim * 0.02, 0.016 + rim * 0.02, 0.02 + rim * 0.022]) + 0.0
    alb = np.dstack([np.clip(srgb(col), 0, 1), alpha])
    hgt = gblur(rim * 0.4 + 0.015 * noise(S, S, seed + 4, 2.0) * mask, 0.8)
    gy, gx = np.gradient(hgt)
    nx, ny, nz = -gx * 5, gy * 5, np.ones_like(hgt)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.dstack([nx / ln, ny / ln, nz / ln]) * 0.5 + 0.5
    rough = 0.025 + 0.2 * rim
    orm = np.dstack([np.ones_like(rough), np.clip(rough, 0.02, 1), np.zeros_like(rough)])
    u8 = lambda a: (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(u8(alb), "RGBA").save(f"{OUT}/{name}_a.png", optimize=True)
    Image.fromarray(u8(nrm), "RGB").save(f"{OUT}/{name}_n.png", optimize=True)
    Image.fromarray(u8(orm), "RGB").save(f"{OUT}/{name}_o.png", optimize=True)
    print("wrote", name)


def gen_ripple(name="ripple", S=256):
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    r = np.sqrt((xx - S / 2) ** 2 + (yy - S / 2) ** 2) / (S / 2)
    ring = np.zeros_like(r)
    for r0, a in [(0.34, 1.0), (0.62, 0.65), (0.86, 0.35)]:
        ring += a * np.exp(-((r - r0) / 0.035) ** 2)
    ring *= smooth(1.0, 0.8, r)
    alb = np.dstack([np.full_like(ring, 0.62), np.full_like(ring, 0.68), np.full_like(ring, 0.72), np.clip(ring * 0.5, 0, 1)])
    gy, gx = np.gradient(gblur(ring, 1.0))
    nx, ny, nz = -gx * 14, gy * 14, np.ones_like(ring)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.dstack([nx / ln, ny / ln, nz / ln]) * 0.5 + 0.5
    orm = np.dstack([np.ones_like(ring), np.full_like(ring, 0.05), np.zeros_like(ring)])
    u8 = lambda a: (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(u8(alb), "RGBA").save(f"{OUT}/{name}_a.png", optimize=True)
    Image.fromarray(u8(nrm), "RGB").save(f"{OUT}/{name}_n.png", optimize=True)
    Image.fromarray(u8(orm), "RGB").save(f"{OUT}/{name}_o.png", optimize=True)
    print("wrote", name)


def gen_screen(S=1024, seed=77):
    """Full-screen blood-on-lens overlay: splatters concentrated at the edges + running drips."""
    rng = np.random.default_rng(seed)
    cv = Cv(S, S)
    spots = [(0.12, 0.15), (0.9, 0.2), (0.2, 0.85), (0.82, 0.8), (0.5, 0.06), (0.05, 0.5), (0.95, 0.52), (0.35, 0.25), (0.68, 0.72), (0.55, 0.93), (0.28, 0.6), (0.75, 0.3)]
    for i, (px, py) in enumerate(spots):
        R = S * rng.uniform(0.035, 0.09) * (1.0 if i < 8 else 0.6)
        splat_into(cv, px * S, py * S, R, rng, rng.integers(7, 14), 28, 0.9, 0.3, S * 0.011, (1.3, 2.6))
    for i in range(130):
        a = rng.uniform(0, 6.283)
        rr = rng.uniform(0.2, 0.55) * S
        px, py = S / 2 + np.cos(a) * rr * 1.1, S / 2 + np.sin(a) * rr
        if 4 < px < S - 4 and 4 < py < S - 4:
            r = 1 + S * 0.007 * rng.random() ** 2.5
            cv.ell(px, py, r * 1.3, r, a, n=8)
    # drips running down from some blobs
    for px, py in [(0.12, 0.15), (0.9, 0.2), (0.5, 0.06), (0.35, 0.25)]:
        for k in range(rng.integers(2, 4)):
            x0 = px * S + rng.normal(0, S * 0.02)
            y0 = py * S
            L = rng.uniform(0.1, 0.32) * S
            w0 = rng.uniform(3, 6)
            prev = (x0, y0)
            for j in range(0, int(L), 4):
                xx = x0 + 3 * np.sin(j / 22.0 + k)
                cv.taper(prev[0], prev[1], xx, y0 + j, w0, w0 * 0.92, caps=False)
                prev = (xx, y0 + j)
            cv.circ(prev[0], prev[1], w0 * 1.3)
    m = cv.arr()
    # screen blood is brighter/more saturated than world decals (it is lit by the HUD)
    pal = dict(thin=(0.55, 0.02, 0.025), thick=(0.2, 0.006, 0.01), edge=(0.1, 0.01, 0.012), clot=(0.05, 0.004, 0.006))
    a, n, o, _ = shade(m, seed, pal=pal, thick_sigma=6.0, relief=1.2, opacity=0.95)
    Image.fromarray(a, "RGBA").save(f"{OUT}/screen_blood_a.png", optimize=True)
    Image.fromarray(n, "RGB").save(f"{OUT}/screen_blood_n.png", optimize=True)
    print("wrote screen_blood")


FONT = "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf"


def _warp(m, seed, amp):
    h, w = m.shape
    dx = noise(w, h, seed, 1.8, hi=40) * amp
    dy = noise(w, h, seed + 1, 1.8, hi=40) * amp
    yy, xx = np.mgrid[0:h, 0:w]
    sx = np.clip((xx + dx).astype(int), 0, w - 1)
    sy = np.clip((yy + dy).astype(int), 0, h - 1)
    return m[sy, sx]


def gen_writing(name, text, seed, W=1024, H=300, size=190):
    """Finger-painted message on a wall, with runs dripping off the letters."""
    from PIL import ImageFont
    rng = np.random.default_rng(seed)
    font = ImageFont.truetype(FONT, size)
    im = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(im)
    tw = d.textlength(text, font=font)
    x = (W - tw) / 2
    for ch in text:
        cw = d.textlength(ch, font=font)
        li = Image.new("L", (int(cw) + 60, int(size * 1.5)), 0)
        ImageDraw.Draw(li).text((30, 5), ch, font=font, fill=255, stroke_width=7, stroke_fill=255)
        li = li.rotate(rng.uniform(-9, 9), resample=Image.BICUBIC)
        im.paste(li, (int(x - 30 + rng.normal(0, 3)), int(H * 0.12 + rng.normal(0, 8))), li)
        x += cw
    m = np.asarray(im).astype(np.float32) / 255.0
    m = _warp(m, seed, 5.0)
    m = m * smooth(-1.4, -0.5, noise(W, H, seed + 2, 1.3, lo=3) + 0.7)   # patchy finger contact
    cv = Cv(W, H)
    solid = m > 0.5
    cols = np.where(solid.any(axis=0))[0]
    for x0 in (rng.choice(cols, size=min(len(cols), 22), replace=False) if len(cols) else []):
        y0 = float(np.where(solid[:, x0])[0].max()) - 2
        L = rng.uniform(0.04, 0.12) * H * (1 + 2.5 * rng.random() ** 2)
        w0 = rng.uniform(2.0, 4.5)
        prev = (x0, y0)
        for j in range(0, int(min(L, H - y0 - 4)), 3):
            xx = x0 + 1.5 * np.sin(j / 15.0 + x0)
            cv.taper(prev[0], prev[1], xx, y0 + j, w0, w0 * 0.9, caps=False)
            prev = (xx, y0 + j)
        cv.circ(prev[0], prev[1], w0 * 1.3)
    m = np.clip(np.maximum(m, cv.arr()), 0, 1)
    m *= 1.0
    save(name, m.astype(np.float32), seed, thick_sigma=2.2, relief=0.8, film=0.15)


def gen_outline(name="outline", seed=5, W=256, H=512):
    """Chalk body outline (a victim lying on the floor, seen from above, head at the top)."""
    cv = Cv(W, H)
    cv.circ(W * 0.5, H * 0.1, W * 0.095)
    cv.taper(W * 0.5, H * 0.17, W * 0.5, H * 0.5, W * 0.14, W * 0.1, caps=False)       # torso
    cv.taper(W * 0.42, H * 0.2, W * 0.1, H * 0.42, W * 0.045, W * 0.04)                  # arm l
    cv.taper(W * 0.58, H * 0.2, W * 0.92, H * 0.34, W * 0.045, W * 0.04)                 # arm r
    cv.taper(W * 0.45, H * 0.5, W * 0.36, H * 0.96, W * 0.065, W * 0.045)                # leg l
    cv.taper(W * 0.55, H * 0.5, W * 0.64, H * 0.94, W * 0.065, W * 0.045)                # leg r
    m = cv.arr()
    ring = np.clip(gblur(m, 2.5) - 0.0, 0, 1)
    edge = np.abs(gblur(m, 1.2) - 0.5) < 0.1
    edge = gblur(edge.astype(np.float32), 1.3)
    edge = np.clip(edge * 2.2, 0, 1)
    dust = smooth(-0.6, 0.6, noise(W, H, seed, 1.2, lo=3) + 0.2)
    a = edge * dust * 0.95
    rgb = np.dstack([np.full_like(a, 0.88), np.full_like(a, 0.88), np.full_like(a, 0.84)])
    alb = np.dstack([rgb, a])
    hgt = gblur(a, 0.8) * 0.3
    gy, gx = np.gradient(hgt)
    nx, ny, nz = -gx * 4, gy * 4, np.ones_like(hgt)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.dstack([nx / ln, ny / ln, nz / ln]) * 0.5 + 0.5
    orm = np.dstack([np.ones_like(a), np.full_like(a, 0.9), np.zeros_like(a)])
    u8 = lambda v: (np.clip(v, 0, 1) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(u8(alb), "RGBA").save(f"{OUT}/{name}_a.png", optimize=True)
    Image.fromarray(u8(nrm), "RGB").save(f"{OUT}/{name}_n.png", optimize=True)
    Image.fromarray(u8(orm), "RGB").save(f"{OUT}/{name}_o.png", optimize=True)
    print("wrote", name)


IMPORT_TMPL = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://textures/gore/{f}"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map={nm}
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""


def write_imports():
    for f in sorted(os.listdir(OUT)):
        if f.endswith(".png"):
            p = f"{OUT}/{f}.import"
            if os.path.exists(p):
                continue  # keep Godot-assigned uid/path
            nm = 1 if f.endswith("_n.png") else 0
            open(p, "w").write(IMPORT_TMPL.format(f=f, nm=nm))


if __name__ == "__main__":
    gen_splat("splat_a", 11, R=0.085, spikes=15, sat=130)
    gen_splat("splat_b", 22, R=0.11, spikes=20, sat=160, elong=0.7, wmax=0.026)
    gen_splat("splat_c", 33, R=0.045, spikes=6, sat=220, reach=1.0, elong=0.2, wmax=0.016)
    gen_splat("splat_d", 44, R=0.07, spikes=11, sat=90, reach=0.8, elong=0.0, wmax=0.03)
    gen_splat_impact("splat_wall", 55)
    gen_spray("spray_a", 66, ichor=True)
    gen_spray("spray_b", 77, arcs=True)
    gen_pool("pool_a", 101)
    gen_pool("pool_b", 202, lobes=5, tendrils=9, ragged=0.16)
    gen_pool("pool_c", 303, lobes=2, tendrils=4, drops=60, ragged=0.06)
    gen_smear("smear_a", 404)
    gen_smear("smear_b", 505)
    gen_drag("drag_a", 606)
    gen_drag("drag_b", 707, twin=True, ichor=True)
    gen_hand("hand_r", 808)
    gen_hand("hand_l", 809, mirror=True)
    gen_hand("hand_smear", 810, smear=0.55)
    gen_foot("foot_r", 911)
    gen_foot("foot_l", 912, mirror=True)
    gen_foot("foot_bare", 913, bare=True)
    gen_drips("drips_a", 1001, runs=7)
    gen_drips("drips_b", 1002, runs=11, ichor=True)
    gen_puddle("puddle_a", 1101)
    gen_puddle("puddle_b", 1102)
    gen_ripple()
    gen_screen()
    gen_writing('write_help', 'HELP', 31)
    gen_writing('write_run', 'RUN', 32, size=230)
    gen_writing('write_sleep', "DON'T SLEEP", 33, size=150)
    gen_writing('write_out', 'GET OUT', 34, size=170)
    gen_outline()
    write_imports()
