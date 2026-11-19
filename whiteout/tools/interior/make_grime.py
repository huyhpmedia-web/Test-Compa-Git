#!/usr/bin/env python3
"""Builds RGBA grime decal textures for interiors (R7-B). Sources: ambientCG CC0 sets (Rust002, Rust004,
Concrete034, PaintedPlaster015, Moss002) used as albedo/normal detail under procedural alpha masks.
usage: make_grime.py <acg_dir> <out_dir>"""
import sys, os
import numpy as np
from PIL import Image, ImageFilter
acg, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
N = 1024
rng = np.random.default_rng(11)

def load(set_, kind="Color"):
    return np.asarray(Image.open(f"{acg}/{set_}/{set_}_1K-JPG_{kind}.jpg").convert("RGB").resize((N, N)), dtype=np.float32) / 255.0

def noise(scale_x, scale_y, seed=None):
    r = np.random.default_rng(seed) if seed is not None else rng
    g = r.random((max(2, int(scale_y)), max(2, int(scale_x)))).astype(np.float32)
    im = Image.fromarray((g * 255).astype(np.uint8)).resize((N, N), Image.BICUBIC)
    return np.asarray(im, dtype=np.float32) / 255.0

def fbm(sx=4, sy=4, oct=5, seed=None):
    t = np.zeros((N, N), np.float32); amp = 1.0; tot = 0
    for o in range(oct):
        t += amp * noise(sx * 2 ** o, sy * 2 ** o, None if seed is None else seed + o); tot += amp; amp *= 0.5
    t /= tot
    t = (t - t.min()) / (t.max() - t.min() + 1e-6)
    return t

def smooth(x, a, b):
    t = np.clip((x - a) / (b - a + 1e-6), 0, 1); return t * t * (3 - 2 * t)

def edge_fade(m, f=0.12):
    y, x = np.mgrid[0:N, 0:N].astype(np.float32) / N
    e = np.minimum(np.minimum(x, 1 - x), np.minimum(y, 1 - y))
    return m * smooth(e, 0.0, f)

def save(name, rgb, a, normal=None):
    arr = np.dstack([np.clip(rgb, 0, 1), np.clip(a, 0, 1)])
    Image.fromarray((arr * 255).astype(np.uint8), "RGBA").save(f"{out}/{name}_a.png", optimize=True)
    print(name, "alpha mean %.2f" % a.mean())

def gradient_dark(c, k):  # darken colour
    return c * k

# 1) water damage: tide-line stain running down from the top edge, tea-brown with a darker rim
def water():
    streak = fbm(14, 3, 5, 100)
    flow = fbm(30, 2, 4, 200)
    y = np.mgrid[0:N, 0:N][0].astype(np.float32) / N
    reach = 0.35 + 0.65 * flow            # how far each streak runs
    m = smooth(reach - y * 1.0, 0.0, 0.25) * smooth(streak, 0.28, 0.65)
    rim = smooth(m, 0.25, 0.5) - smooth(m, 0.6, 0.95)
    d = load("Concrete034")
    base = np.array([0.36, 0.27, 0.15], np.float32)
    rgb = base * (0.55 + 0.7 * d.mean(2, keepdims=True)) * (1 - 0.35 * rim[..., None])
    a = edge_fade(np.clip(m * 0.85, 0, 1))
    save("water", rgb, a)

# 2) peeling paint: patchy exposed substrate with curled light edges
def peel():
    f = fbm(5, 5, 6, 300)
    m = smooth(f, 0.52, 0.56)
    m_edge = smooth(f, 0.50, 0.53) - smooth(f, 0.56, 0.60)   # curled paint lip
    sub = load("Concrete034") * np.array([0.8, 0.76, 0.7], np.float32)
    pl = load("PaintedPlaster015")
    rgb = sub * m[..., None] + (pl * 0.72) * np.clip(m_edge, 0, 1)[..., None]
    a = edge_fade(np.clip(m * 0.9 + m_edge * 0.7, 0, 1))
    save("peel", rgb, a)

# 3) rust streaks running down from fixtures
def rust():
    s = fbm(22, 2, 5, 400)
    y = np.mgrid[0:N, 0:N][0].astype(np.float32) / N
    m = smooth(s, 0.42, 0.62) * smooth(1.0 - y * 0.8 + 0.2 * fbm(3, 3, 3, 410), 0.1, 0.9)
    c = load("Rust004")
    save("rust", c * 1.05, edge_fade(m * 0.9))

# 4) mould in a damp corner: black-green speckle clusters
def mold():
    f = fbm(6, 6, 6, 500)
    sp = fbm(60, 60, 3, 510)
    m = smooth(f * 0.7 + sp * 0.5, 0.55, 0.85)
    mo = load("Moss002")
    blk = np.array([0.04, 0.05, 0.03], np.float32)
    rgb = blk * 0.7 + mo * 0.25
    save("mold", rgb, edge_fade(m * 0.85, 0.2))

# 5) floor grime / wear: dark dirt blotches, tracked-in muck
def grime():
    f = fbm(4, 4, 6, 600)
    sp = fbm(28, 28, 4, 610)
    m = smooth(f, 0.4, 0.75) * (0.35 + 0.65 * sp)
    d = load("Concrete034") * np.array([0.35, 0.3, 0.26], np.float32)
    save("grime", d + 0.02, edge_fade(m * 0.8, 0.18))

# 6) baseboard scuff/dirt band (wall bottom): dark soot gradient upward with noise
def band():
    y = np.mgrid[0:N, 0:N][0].astype(np.float32) / N   # y=0 at top of image; decal bottom is image bottom
    f = fbm(16, 3, 5, 700)
    m = smooth(y + (f - 0.5) * 0.5, 0.45, 1.0)
    rgb = np.ones((N, N, 3), np.float32) * np.array([0.09, 0.075, 0.06], np.float32) + 0.05 * f[..., None]
    a = m * 0.8
    e = np.mgrid[0:N, 0:N][1].astype(np.float32) / N
    a = a * smooth(np.minimum(e, 1 - e), 0, 0.06)
    save("band", rgb, a)

# 7) cracks: fine dark crack network
def cracks():
    img = Image.new("L", (N, N), 0)
    from PIL import ImageDraw
    d = ImageDraw.Draw(img)
    r = np.random.default_rng(800)
    for k in range(5):
        x, y = r.uniform(0.2, 0.8) * N, r.uniform(0.0, 0.2) * N
        ang = np.pi / 2 + r.normal(0, 0.3)
        w = 5
        for i in range(90):
            ang += r.normal(0, 0.28)
            nx, ny = x + np.cos(ang) * 14, y + np.sin(ang) * 14
            d.line([(x, y), (nx, ny)], fill=255, width=max(1, int(w)))
            if r.random() < 0.12:   # branch
                bx, by, ba = nx, ny, ang + r.choice([-1, 1]) * 0.7
                for j in range(r.integers(6, 20)):
                    ba += r.normal(0, 0.3)
                    cx, cy = bx + np.cos(ba) * 12, by + np.sin(ba) * 12
                    d.line([(bx, by), (cx, cy)], fill=255, width=2); bx, by = cx, cy
            x, y = nx, ny
            w = max(2, w - 0.03)
    m = np.asarray(img.filter(ImageFilter.GaussianBlur(1.3)), dtype=np.float32) / 255.0
    rgb = np.ones((N, N, 3), np.float32) * 0.03
    save("cracks", rgb, edge_fade(m * 0.95, 0.04))

# 8) blood-free generic stain pool (dark liquid ring) for floors
def pool():
    f = fbm(3, 3, 5, 900)
    y, x = np.mgrid[0:N, 0:N].astype(np.float32) / N
    r = np.sqrt((x - 0.5) ** 2 + (y - 0.5) ** 2) * 2
    m = smooth(1.0 - r + (f - 0.5) * 0.7, 0.15, 0.35)
    ring = smooth(1.0 - r + (f - 0.5) * 0.7, 0.2, 0.3) - smooth(1.0 - r + (f - 0.5) * 0.7, 0.35, 0.5)
    rgb = np.ones((N, N, 3), np.float32) * np.array([0.08, 0.07, 0.05], np.float32) + 0.05 * ring[..., None]
    save("pool", rgb, edge_fade(m * 0.75, 0.05))

for fn in (water, peel, rust, mold, grime, band, cracks, pool):
    fn()
