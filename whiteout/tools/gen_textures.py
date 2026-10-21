#!/usr/bin/env python3
"""Texture build script for HOLLOW CREEK: WHITEOUT.   Run with:  python3 -I tools/gen_textures.py [--src DIR]

Two kinds of output land in whiteout/textures/:

 1. REAL (CC0) PBR sets from ambientCG / Poly Haven.  They are fetched (one HTTP range request per
    PNG) from the public "mat-vis" mirror (github.com/MorePET/mat-vis, release v2026.04.0, CC0 data)
    into a scratch dir laid out as  DIR/<preset>_{color,normal,roughness}.png  and then converted
    here with `--src DIR`:  * normal maps flipped DirectX -> OpenGL (green inverted)
                            * non-square sets tiled to a square (keeps real-world aspect)
                            * albedo re-graded to the preset's intended brightness/hue (REAL_SPEC)
                            * roughness remapped (mul, add) to the preset's intended gloss.
    The source <-> preset mapping is REAL_MAP below (and in textures/LICENSES.md).

 2. PROCEDURAL textures (no suitable CC0 source): blood, skin_dead, water, paper, glass and the
    night-storm sky `clouds_sky.png`.  numpy + PIL only.  Always generated (seeded, deterministic).
"""
import os, sys, argparse
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "textures"))

# ----------------------------------------------------------------------------------------------
# real-texture import
# ----------------------------------------------------------------------------------------------
# preset -> (source site, asset id)
REAL_MAP = {
    "brick": ("ambientcg", "Bricks101"), "brick_dark": ("ambientcg", "Bricks097"),
    "concrete": ("ambientcg", "Concrete031"), "plaster": ("ambientcg", "Plaster001"),
    "plaster_dirty": ("polyhaven", "grey_plaster_03"), "tile_floor": ("polyhaven", "anti_skid_tiles"),
    "tile_wall": ("ambientcg", "Tiles107"), "wood_floor": ("ambientcg", "WoodFloor008"),
    "wood": ("polyhaven", "old_planks_02"), "wood_panel": ("ambientcg", "Wood060"),
    "carpet": ("ambientcg", "Carpet012"), "marble": ("ambientcg", "Marble004"),
    "snow": ("ambientcg", "Snow013"), "asphalt": ("ambientcg", "Asphalt015"),
    "asphalt_snow": ("polyhaven", "asphalt_snow"), "metal": ("ambientcg", "Metal010"),
    "metal_rust": ("ambientcg", "Rust003"), "metal_painted": ("polyhaven", "green_metal_rust"),
    "corrugated": ("polyhaven", "rusty_corrugated_iron"), "sewer": ("ambientcg", "Concrete022"),
    "lab_floor": ("ambientcg", "Concrete034"), "lab_wall": ("ambientcg", "Plaster002"),
    "bark": ("ambientcg", "Bark001"), "dirt": ("polyhaven", "brown_mud"),
    "rock": ("ambientcg", "Rock030"), "rock_wet": ("ambientcg", "Rock058"),
    "ice": ("ambientcg", "Ice003"), "frost": ("ambientcg", "Ice001"),
    "fabric": ("ambientcg", "Fabric077"), "leather": ("ambientcg", "Leather001"),
    "rubber": ("ambientcg", "Rubber004"),
}
BIG = {"brick", "concrete", "snow", "asphalt", "asphalt_snow", "plaster", "plaster_dirty",
       "tile_floor", "wood_floor"}

# albedo grade: gain (sRGB multiply), sat (multiplier), hue (degrees shift), tint (RGB multiplier)
# roughness remap: (mul, add)
REAL_SPEC = {
    "brick": dict(gain=0.88, sat=1.0, rough=(1.3, 0.0)),
    "brick_dark": dict(gain=0.62, sat=0.95, rough=(1.35, 0.0)),
    "concrete": dict(gain=1.3, sat=0.9, rough=(1.3, 0.0)),
    "plaster": dict(gain=0.88, sat=1.0, tint=(1.0, 0.97, 0.9), rough=(1.1, 0.0)),
    "plaster_dirty": dict(gain=0.95, sat=1.0, rough=(1.2, 0.0)),
    "tile_floor": dict(gain=1.15, sat=0.45, rough=(0.85, 0.0)),
    "tile_wall": dict(gain=0.82, sat=1.0, tint=(0.96, 1.0, 0.98), rough=(1.0, 0.32)),
    "wood_floor": dict(gain=1.45, sat=1.0, rough=(1.1, 0.0)),
    "wood": dict(gain=0.95, sat=1.4, rough=(0.8, 0.0)),
    "wood_panel": dict(gain=0.85, sat=1.0, rough=(0.95, 0.0)),
    "carpet": dict(gain=1.15, sat=1.0, hue=145, rough=(1.1, 0.0)),
    "marble": dict(gain=0.92, sat=1.0, rough=(1.0, 0.1)),
    "snow": dict(gain=1.33, sat=0.9, rough=(1.6, 0.1)),
    "asphalt": dict(gain=0.5, sat=0.9, rough=(1.35, 0.0)),
    "asphalt_snow": dict(gain=1.1, sat=0.8, tint=(0.95, 1.0, 1.08), rough=(0.9, 0.0)),
    "metal": dict(gain=1.0, sat=0.9, rough=(1.0, 0.0)),
    "metal_rust": dict(gain=1.0, sat=0.9, rough=(0.9, 0.0)),
    "metal_painted": dict(gain=1.05, sat=1.0, rough=(0.6, 0.0)),
    "corrugated": dict(gain=1.3, sat=0.85, rough=(0.75, 0.0)),
    "sewer": dict(gain=0.68, sat=0.6, tint=(0.97, 1.03, 0.95), rough=(0.7, 0.0)),
    "lab_floor": dict(gain=1.08, sat=0.9, tint=(0.98, 1.0, 1.03), rough=(0.6, 0.0)),
    "lab_wall": dict(gain=1.0, sat=1.0, rough=(0.75, 0.0)),
    "bark": dict(gain=0.45, sat=1.0, tint=(1.05, 0.95, 0.85), rough=(1.3, 0.0)),
    "dirt": dict(gain=0.85, sat=1.1, tint=(1.05, 0.93, 0.78), rough=(1.0, 0.0)),
    "fabric": dict(gain=0.75, sat=0.7, rough=(1.3, 0.0)),
    "leather": dict(gain=1.1, sat=0.85, rough=(1.0, 0.0)),
    "rubber": dict(gain=0.4, sat=1.0, rough=(1.3, 0.0)),
    "rock": dict(gain=0.75, sat=0.95, rough=(1.2, 0.0)),
    "rock_wet": dict(gain=0.6, sat=0.9, rough=(0.55, 0.0)),
    "ice": dict(gain=1.25, sat=1.1, hue=15, tint=(0.85, 0.98, 1.1), rough=(0.5, 0.0)),
    "frost": dict(gain=1.3, sat=0.35, lift=0.42, tint=(0.95, 1.0, 1.06), rough=(0.7, 0.35)),
}


def _load_gray(path):
    im = Image.open(path)
    if im.mode.startswith("I;16") or im.mode == "I":
        a = np.asarray(im).astype(np.float32) / 65535.0
    else:
        a = np.asarray(im.convert("L")).astype(np.float32) / 255.0
    return a


def _square(a):
    h, w = a.shape[:2]
    if h == w:
        return a
    if w > h:
        return np.tile(a, (w // h, 1) + (1,) * (a.ndim - 2))[:w]
    return np.tile(a, (1, h // w) + (1,) * (a.ndim - 2))[:, :h]


def _resize(a, size):
    if a.shape[0] == size:
        return a
    im = Image.fromarray(a)
    return np.asarray(im.resize((size, size), Image.LANCZOS))


def import_real(src):
    for name, (site, asset) in REAL_MAP.items():
        sp = REAL_SPEC[name]
        size = 1024 if name in BIG else 512
        col = np.asarray(Image.open(f"{src}/{name}_color.png").convert("RGB"))
        nrm = np.asarray(Image.open(f"{src}/{name}_normal.png").convert("RGB")).copy()
        rgh = _load_gray(f"{src}/{name}_roughness.png")
        # ---- albedo grade
        im = Image.fromarray(_square(col))
        if sp.get("hue") or sp.get("sat", 1) != 1:
            hsv = np.asarray(im.convert("HSV")).astype(np.float32)
            hsv[..., 0] = (hsv[..., 0] + sp.get("hue", 0) / 360.0 * 255.0) % 255.0
            hsv[..., 1] = np.clip(hsv[..., 1] * sp.get("sat", 1.0), 0, 255)
            im = Image.fromarray(hsv.astype(np.uint8), "HSV").convert("RGB")
        f = np.asarray(im).astype(np.float32) / 255.0
        f = f * np.array(sp.get("tint", (1, 1, 1)), np.float32) * sp.get("gain", 1.0)
        f = f * (1 - sp.get("lift", 0.0)) + sp.get("lift", 0.0)
        alb = (np.clip(f, 0, 1) * 255 + 0.5).astype(np.uint8)
        # ---- normal: DirectX -> OpenGL (all mirrored sources ship DX-first), square-tile
        nrm[..., 1] = 255 - nrm[..., 1]
        nrm = _square(nrm)
        # ---- roughness
        m, a = sp["rough"]
        rgh = np.clip(_square(rgh) * m + a, 0.02, 1.0)
        rgh8 = (rgh * 255 + 0.5).astype(np.uint8)
        Image.fromarray(_resize(alb, size)).save(f"{OUT}/{name}_albedo.png", optimize=True)
        Image.fromarray(_resize(nrm, size)).save(f"{OUT}/{name}_normal.png", optimize=True)
        Image.fromarray(_resize(rgh8, size), "L").save(f"{OUT}/{name}_rough.png", optimize=True)
        print("real", name, site, asset, size)


# ----------------------------------------------------------------------------------------------
# procedural helpers (all periodic -> seamless)
# ----------------------------------------------------------------------------------------------
def fnoise(rng, size, beta=2.0, lo=0.0, hi=None, aniso=(1.0, 1.0)):
    """Tileable noise in [0,1]: random-phase spectrum ~ 1/f^beta (band-limited by lo/hi cycles)."""
    h, w = (size, size) if isinstance(size, int) else size
    fy = np.fft.fftfreq(h)[:, None] * h / aniso[0]
    fx = np.fft.fftfreq(w)[None, :] * w / aniso[1]
    r = np.sqrt(fx ** 2 + fy ** 2)
    r[0, 0] = 1
    amp = 1.0 / r ** (beta / 2.0)
    amp[0, 0] = 0
    amp[r < lo] = 0
    if hi is not None:
        amp[r > hi] = 0
    spec = amp * np.exp(2j * np.pi * rng.random((h, w)))
    n = np.fft.ifft2(spec).real
    n -= n.min()
    return n / max(n.max(), 1e-9)


def norm01(a):
    a = a - a.min()
    return a / max(a.max(), 1e-9)


def blur(a, s):
    h, w = a.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    return np.fft.ifft2(np.fft.fft2(a) * np.exp(-2 * (np.pi * s) ** 2 * (fx ** 2 + fy ** 2))).real


def height_to_normal(h, strength=2.0):
    """OpenGL-convention (Y+ up in image = row-decreasing) tangent normal map from periodic height."""
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy_row = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    nx = -dx * strength
    ny = dy_row * strength  # = -dh/dv with v up
    nz = np.ones_like(h)
    L = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx / L, ny / L, nz / L], -1)
    return ((n * 0.5 + 0.5) * 255 + 0.5).astype(np.uint8)


def save_set(name, albedo, normal, rough):
    def u8(a):
        return (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(u8(albedo)).save(f"{OUT}/{name}_albedo.png", optimize=True)
    Image.fromarray(normal).save(f"{OUT}/{name}_normal.png", optimize=True)
    Image.fromarray(u8(rough), "L").save(f"{OUT}/{name}_rough.png", optimize=True)
    print("procedural", name)


def mix(a, b, t):
    return a + (b - a) * t[..., None]


# ----------------------------------------------------------------------------------------------
# PROCEDURAL materials
# ----------------------------------------------------------------------------------------------
def gen_blood(S=512):
    rng = np.random.default_rng(101)
    big = fnoise(rng, S, 2.6, hi=6)
    mid = fnoise(rng, S, 2.0, lo=4, hi=24)
    fine = fnoise(rng, S, 1.2, lo=20, hi=120)
    # clotted dark regions where `big` is high, thin wet film elsewhere
    clot = np.clip((big - 0.55) * 4.0, 0, 1) * (0.6 + 0.4 * mid)
    ridge = 1 - np.abs(2 * mid - 1)
    film = np.clip(1 - clot, 0, 1)
    bright = np.array([0.36, 0.035, 0.03])
    dark = np.array([0.10, 0.005, 0.008])
    alb = mix(np.broadcast_to(bright, (S, S, 3)).copy(), np.broadcast_to(dark, (S, S, 3)).copy(), clot)
    alb *= (0.85 + 0.3 * fine)[..., None]
    alb *= (0.9 + 0.2 * ridge)[..., None]
    h = clot * 0.9 + mid * 0.15 + fine * 0.03 + film * ridge * 0.1
    nrm = height_to_normal(blur(h, 1.0) * 1.0, 6.0)
    rough = 0.16 + 0.34 * clot + 0.08 * fine
    save_set("blood", alb, nrm, rough)


def gen_skin_dead(S=512):
    rng = np.random.default_rng(202)
    base = np.array([0.56, 0.55, 0.47])      # sallow grey-green pallor
    bruise = np.array([0.34, 0.36, 0.40])    # livor mortis blue-grey
    flush = np.array([0.52, 0.34, 0.30])     # residual red
    blot = fnoise(rng, S, 2.4, hi=7)
    blot2 = fnoise(rng, S, 2.0, lo=3, hi=18)
    alb = np.broadcast_to(base, (S, S, 3)).copy()
    alb = mix(alb, np.broadcast_to(bruise, (S, S, 3)).copy(), np.clip((blot - 0.55) * 2.5, 0, 1) * 0.35)
    alb = mix(alb, np.broadcast_to(flush, (S, S, 3)).copy(), np.clip((blot2 - 0.62) * 3.0, 0, 1) * 0.3)
    # veins: ridged low-freq noise, thin dark blue-green lines
    v = fnoise(rng, S, 2.2, lo=2, hi=10)
    vein = np.clip(1 - np.abs(v - 0.5) * 22.0, 0, 1) ** 2 * np.clip(fnoise(rng, S, 2, hi=5) * 1.6 - 0.35, 0, 1)
    alb = mix(alb, np.broadcast_to(np.array([0.30, 0.38, 0.42]), (S, S, 3)).copy(), vein * 0.45)
    pores = fnoise(rng, S, 0.6, lo=90, hi=230)
    wr = fnoise(rng, S, 1.8, lo=10, hi=60)
    alb *= (0.93 + 0.14 * pores)[..., None]
    h = pores * 0.35 + wr * 0.4 + blur(fnoise(rng, S, 2, hi=20), 0.5) * 0.3
    nrm = height_to_normal(h, 3.0)
    rough = 0.62 + 0.18 * wr + 0.1 * pores - 0.15 * vein
    save_set("skin_dead", alb, nrm, rough)


def gen_water(S=512):
    rng = np.random.default_rng(303)
    n1 = fnoise(rng, S, 2.4, lo=2, hi=40)
    n2 = fnoise(rng, S, 1.6, lo=10, hi=110)
    # sewage / meltwater: dark murky green-brown with faint oily variation
    murk = blur(fnoise(rng, S, 2.8, hi=8), 1)
    base = np.array([0.11, 0.13, 0.095])
    alb = np.broadcast_to(base, (S, S, 3)).copy() * (0.85 + 0.35 * murk)[..., None]
    h = n1 * 1.0 + n2 * 0.35
    nrm = height_to_normal(h, 3.0)
    rough = 0.05 + 0.05 * n2 + 0.04 * murk
    save_set("water", alb, nrm, rough)


def gen_paper(S=512):
    rng = np.random.default_rng(404)
    fib = fnoise(rng, S, 0.9, lo=30, hi=200, aniso=(1.0, 1.0))
    fib2 = fnoise(rng, S, 1.4, lo=60, hi=250, aniso=(4.0, 1.0)) * fnoise(rng, S, 1.4, lo=60, hi=250, aniso=(1.0, 4.0))
    stain = fnoise(rng, S, 2.6, hi=8)
    age = np.clip((stain - 0.5) * 2.2, 0, 1)
    base = np.array([0.90, 0.88, 0.80])
    alb = np.broadcast_to(base, (S, S, 3)).copy()
    alb = mix(alb, np.broadcast_to(np.array([0.74, 0.66, 0.50]), (S, S, 3)).copy(), age * 0.25)
    alb *= (0.95 + 0.07 * fib + 0.05 * norm01(fib2))[..., None]
    h = fib * 0.5 + norm01(fib2) * 0.5 + blur(fnoise(rng, S, 2, lo=2, hi=12), 0.5) * 0.4
    nrm = height_to_normal(h, 1.5)
    rough = 0.9 + 0.08 * fib
    save_set("paper", alb, nrm, rough)


def gen_glass(S=512):
    rng = np.random.default_rng(505)
    # greasy smudges + dust: lighten albedo (more opaque-looking) and roughen where dirty
    sm = fnoise(rng, S, 2.2, lo=2, hi=14)
    sm2 = fnoise(rng, S, 1.6, lo=6, hi=60)
    streak = fnoise(rng, S, 1.8, lo=3, hi=40, aniso=(5.0, 1.0))
    dirt = np.clip((sm - 0.45) * 2.5, 0, 1) * (0.4 + 0.6 * sm2) + np.clip((streak - 0.6) * 3, 0, 1) * 0.5
    dirt = np.clip(dirt, 0, 1)
    base = np.array([0.62, 0.72, 0.75])
    alb = np.broadcast_to(base, (S, S, 3)).copy()
    alb = mix(alb, np.broadcast_to(np.array([0.82, 0.84, 0.82]), (S, S, 3)).copy(), dirt * 0.3)
    h = blur(sm, 4) * 0.3 + sm2 * 0.03
    nrm = height_to_normal(h, 2.0)
    rough = 0.04 + 0.5 * dirt
    save_set("glass", alb, nrm, rough)


# ----------------------------------------------------------------------------------------------
# night storm sky (RGBA equirect, alpha = cloud density, black RGB where clear)
# ----------------------------------------------------------------------------------------------
def gen_clouds_sky(W=2048, H=1024):
    """Equirect storm deck. 2D periodic spectral noise (seamless in longitude), stretched horizontally,
    domain-warped, thinned toward the horizon. RGBA: alpha = density, RGB = dark blue-grey lit from
    one side (fake volume via the density gradient). Clear sky = alpha 0 and RGB black."""
    rng = np.random.default_rng(606)
    base = fnoise(rng, (H, W), 3.4, lo=1.5, hi=260, aniso=(1.0, 2.6))
    wx = (fnoise(rng, (H, W), 3.0, hi=40) - 0.5) * 120
    wy = (fnoise(rng, (H, W), 3.0, hi=40) - 0.5) * 50
    yy, xx = np.mgrid[0:H, 0:W]
    xs = ((xx + wx).astype(int)) % W
    ys = np.clip((yy + wy).astype(int), 0, H - 1)
    n = base[ys, xs]
    n2 = fnoise(rng, (H, W), 2.8, lo=12, hi=260, aniso=(1.0, 2.0))
    n = norm01(n * 0.88 + n2 * 0.12)
    n = (n - np.percentile(n, 2)) / (np.percentile(n, 98) - np.percentile(n, 2))
    row = (np.arange(H) + 0.5) / H                      # 0 zenith .. 0.5 horizon .. 1 nadir
    elev = np.clip(1 - row / 0.5, 0, 1)[:, None]        # 1 zenith -> 0 horizon
    thresh = 0.30 - 0.18 * elev                         # thicker overhead
    d = np.clip((n - thresh) / 0.28, 0, 1)
    d = d * d * (3 - 2 * d)
    d *= np.clip(elev * 7.0, 0, 1) ** 0.8               # thin out into the horizon
    d *= (row < 0.5)[:, None]
    # fake lighting: lit where density falls toward a light direction (up-left), dark in thick cores
    g = np.roll(blur(n, 9.0), 14, 0) - np.roll(blur(n, 9.0), -14, 0)
    gx = np.roll(blur(n, 9.0), 14, 1) - np.roll(blur(n, 9.0), -14, 1)
    lit = np.clip(0.5 + 6.0 * (g * 0.7 + gx * 0.5), 0, 1)
    core = np.clip(d * 1.2, 0, 1)
    shade = np.clip(0.25 + 0.55 * lit - 0.35 * core + 0.25 * (n2 - 0.5), 0, 1)
    dark = np.array([0.035, 0.042, 0.06])
    light = np.array([0.30, 0.34, 0.42])
    rgb = dark + (light - dark) * shade[..., None]
    rgb *= (d > 0.002)[..., None]
    img = np.concatenate([rgb, d[..., None]], -1)
    Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(f"{OUT}/clouds_sky.png", optimize=True)
    print("procedural clouds_sky")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", help="dir with <preset>_{color,normal,roughness}.png downloaded from mat-vis")
    ap.add_argument("--only", help="comma list: procedural names to (re)generate")
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    if args.src:
        import_real(args.src)
    procs = {"blood": gen_blood, "skin_dead": gen_skin_dead, "water": gen_water, "paper": gen_paper,
             "glass": gen_glass, "clouds_sky": gen_clouds_sky}
    want = args.only.split(",") if args.only else list(procs)
    for k in want:
        procs[k]()
