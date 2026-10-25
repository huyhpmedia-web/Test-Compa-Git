"""numpy/PIL texture generators for the boss pipeline (dead skin, frozen cloth, blood, flesh).
All output is deterministic for a given seed."""
import os
import numpy as np
from PIL import Image


def fbm(size, seed, octaves=5, base=4, persistence=0.5, tile=False):
    """value-noise fractal in [0,1], (size,size)."""
    rng = np.random.RandomState(seed)
    out = np.zeros((size, size), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        n = base * (2 ** o)
        g = rng.rand(n + (0 if tile else 1), n + (0 if tile else 1)).astype(np.float32)
        im = Image.fromarray(g, mode="F").resize((size, size), Image.BICUBIC)
        out += amp * np.asarray(im)
        tot += amp
        amp *= persistence
    out /= tot
    lo, hi = out.min(), out.max()
    return (out - lo) / (hi - lo + 1e-9)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0 + 1e-9), 0, 1)
    return t * t * (3 - 2 * t)


def load(path, size):
    im = Image.open(path).convert("RGB")
    if im.size != (size, size):
        im = im.resize((size, size), Image.LANCZOS)
    return np.asarray(im, np.float32) / 255.0


def save(arr, path, q=88):
    a = (np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im = Image.fromarray(a)
    if path.endswith(".jpg"):
        im.save(path, quality=q, subsampling=0)
    else:
        im.save(path)


def lum(a):
    return (a[..., 0] * 0.3 + a[..., 1] * 0.59 + a[..., 2] * 0.11)[..., None]


def dead_skin(src, out, seed=1, size=1024, frost=0.5, blood=0.25, livid=0.6, bruise=0.5, tone=(1, 1, 1)):
    """MakeHuman skin -> frostbitten, mottled, blue-grey dead skin with blood and frost speckle."""
    a = load(src, size)
    L = lum(a)
    cold = np.array([0.80, 0.87, 0.97], np.float32)
    base = a * 0.35 + (L * cold) * 0.65
    base = base * 1.05 * np.array(tone, np.float32)
    # lividity: purple/blue blotches
    n1 = fbm(size, seed, 4, 3)[..., None]
    liv = smooth(0.35, 0.8, n1) * livid
    base = base * (1 - liv) + base * np.array([0.78, 0.72, 0.88], np.float32) * liv
    # yellow-grey waxy patches
    n2 = fbm(size, seed + 11, 4, 5)[..., None]
    wax = smooth(0.55, 0.85, n2) * 0.5
    base = base * (1 - wax) + (L * np.array([0.95, 0.92, 0.7], np.float32)) * wax
    # frostbite: dark violet/black necrotic blotches with a red rim
    n3 = fbm(size, seed + 23, 5, 6)[..., None]
    nec = smooth(0.66, 0.78, n3) * bruise
    rim = smooth(0.58, 0.68, n3) * (1 - smooth(0.68, 0.78, n3)) * bruise
    base = base * (1 - rim * 0.7) + np.array([0.42, 0.10, 0.14], np.float32) * rim * 0.7
    base = base * (1 - nec) + np.array([0.09, 0.05, 0.09], np.float32) * nec
    # fine vein marbling
    n4 = fbm(size, seed + 31, 6, 12)
    vein = (1 - np.abs(n4 - 0.5) * 2)
    vein = smooth(0.90, 0.99, vein)[..., None] * 0.35
    base = base * (1 - vein) + np.array([0.28, 0.32, 0.55], np.float32) * vein
    # blood smears
    n5 = fbm(size, seed + 47, 5, 4)[..., None]
    bl = smooth(0.62, 0.74, n5) * blood
    base = base * (1 - bl) + np.array([0.30, 0.02, 0.03], np.float32) * bl
    # frost crust and speckle
    n6 = fbm(size, seed + 53, 6, 8)[..., None]
    n7 = fbm(size, seed + 59, 3, 32)[..., None]
    fr = (smooth(0.62, 0.8, n6) * 0.75 + smooth(0.86, 0.95, n7) * 0.6) * frost
    base = base * (1 - fr) + np.array([0.86, 0.94, 1.0], np.float32) * fr
    save(base, out)
    return out


def frozen_cloth(src, out, seed=1, size=512, frost=0.55, dirt=0.4, blood=0.2, tint=(0.8, 0.88, 1.0), desat=0.4, mul=(1, 1, 1), flat=None):
    a = load(src, size) * np.array(mul, np.float32)
    if flat is not None:
        # woven fabric in a flat colour: low-contrast noise + faint weave, keeps the source's folds only as a faint luminance
        w = fbm(size, seed + 101, 4, 16)[..., None]
        weave = (np.sin(np.arange(size)[None, :, None] * 1.9) * np.sin(np.arange(size)[:, None, None] * 1.9)) * 0.04
        L0 = lum(load(src, size))
        a = np.array(flat, np.float32) * (0.75 + 0.5 * w + weave) * (0.85 + 0.3 * L0)
    L = lum(a)
    base = a * (1 - desat) + L * np.array(tint, np.float32) * desat
    n1 = fbm(size, seed, 5, 4)[..., None]
    base = base * (1 - dirt * smooth(0.3, 0.8, n1) * 0.7)
    n5 = fbm(size, seed + 5, 5, 5)[..., None]
    bl = smooth(0.66, 0.77, n5) * blood
    base = base * (1 - bl) + np.array([0.22, 0.015, 0.02], np.float32) * bl
    n6 = fbm(size, seed + 9, 6, 7)[..., None]
    n7 = fbm(size, seed + 13, 3, 24)[..., None]
    fr = (smooth(0.58, 0.78, n6) * 0.8 + smooth(0.8, 0.93, n7) * 0.6) * frost
    base = base * (1 - fr) + np.array([0.88, 0.95, 1.0], np.float32) * fr
    save(base, out)
    return out


def flesh_tex(out, seed=1, size=1024, wet=True):
    """tileable-ish raw fused-flesh albedo: livid purple-grey with red wet patches, frost."""
    n1 = fbm(size, seed, 5, 4, tile=True)[..., None]
    n2 = fbm(size, seed + 3, 5, 8, tile=True)[..., None]
    n3 = fbm(size, seed + 7, 6, 16, tile=True)[..., None]
    c0 = np.array([0.42, 0.40, 0.50], np.float32)   # blue-grey
    c1 = np.array([0.52, 0.30, 0.30], np.float32)   # bruised pink
    c2 = np.array([0.30, 0.04, 0.05], np.float32)   # blood
    c3 = np.array([0.10, 0.07, 0.12], np.float32)   # necrotic
    a = c0 * (1 - n1) + c1 * n1
    a = a * (1 - smooth(0.55, 0.75, n2) * 0.8) + c2 * smooth(0.55, 0.75, n2) * 0.8
    a = a * (1 - smooth(0.7, 0.82, n3) * 0.7) + c3 * smooth(0.7, 0.82, n3) * 0.7
    n4 = fbm(size, seed + 13, 3, 20, tile=True)[..., None]
    fr = smooth(0.78, 0.92, n4) * 0.7
    a = a * (1 - fr) + np.array([0.85, 0.93, 1.0], np.float32) * fr
    save(a, out)
    return out
