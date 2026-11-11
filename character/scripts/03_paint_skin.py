"""Stage 3 -- painted skin albedo (no photo pixels on the face).

The texture is generated from the geometry itself: an even skin tone sampled from the
photos, lips from the mesh's lip mask, blush, eye shadow, eyeliner along the fitted lid
edge, freckles and a scalp tint.  Because every feature is placed from the mesh, it can
never drift against the 3D shape the way a projected photograph does.

Output: textures/skin_albedo.png
"""
import importlib
import json
import os
import sys

import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy  # noqa: E402
from scipy.spatial import cKDTree  # noqa: E402
import blcore  # noqa: E402
import charlib  # noqa: E402
import hairgen  # noqa: E402
import mhlib  # noqa: E402

bk = importlib.import_module("03_bake_skin")
ROOT, B = charlib.ROOT, charlib.B
SIZE = int(os.environ.get("ATLAS", "4096"))


def sm(x, lo, hi):
    t = np.clip((x - lo) / (hi - lo), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def blob(alb, pos, valid, c, sigma, tint, strength):
    """Multiply the albedo towards `tint` inside a soft 3D ball."""
    c = np.asarray(c, dtype=np.float32)
    box = valid & (np.abs(pos[:, :, 0] - c[0]) < 3 * sigma) & (np.abs(pos[:, :, 1] - c[1]) < 3 * sigma) & \
        (np.abs(pos[:, :, 2] - c[2]) < 3 * sigma)
    d2 = ((pos[box] - c) ** 2).sum(1)
    w = np.exp(-d2 / (2 * sigma * sigma))[:, None] * strength
    alb[box] = alb[box] * (1 - w * (1 - np.asarray(tint, dtype=np.float32)))


def line(alb, pos, valid, poly, width, color, strength):
    """Paint a soft line of given half-width (metres) along a 3D polyline. strength: per-vertex array."""
    poly = np.asarray(poly, dtype=np.float32)
    lo, hi = poly.min(0) - 3 * width, poly.max(0) + 3 * width
    box = valid & np.all((pos > lo) & (pos < hi), axis=2)
    p = pos[box]
    if not len(p):
        return
    d = np.linalg.norm(p[:, None, :] - poly[None, :, :], axis=2)
    k = d.argmin(1)
    a = (1 - sm(d.min(1), width * 0.45, width * 1.25)) * np.asarray(strength, dtype=np.float32)[k]
    alb[box] = alb[box] * (1 - a[:, None]) + np.asarray(color, dtype=np.float32) * a[:, None]


def resample(poly, n):
    seg = np.linalg.norm(np.diff(poly, axis=0), axis=1)
    t = np.concatenate([[0], np.cumsum(seg)]) / seg.sum()
    s = np.linspace(0, 1, n)
    return np.stack([np.interp(s, t, poly[:, k]) for k in range(3)], axis=1)


def main():
    fit = charlib.load_fit()
    params = json.load(open(os.path.join(ROOT, "data", "face_params.json")))
    base = mhlib.BaseMesh()
    blcore.reset_scene()
    body = blcore.make_body_object(base, fit["verts"])
    sub = body.modifiers.new("Subdiv", 'SUBSURF'); sub.levels = 2; sub.render_levels = 2
    geo = bk.bake_geometry(body, SIZE)
    pos, valid = geo["pos"], geo["valid"]
    H = fit["H"]
    rng = np.random.default_rng(5)

    # ---- tones sampled from the photos
    ph = cv2.imread(os.path.join(ROOT, "reference", "ref_front.jpg")).astype(np.float32) / 255.0
    sg = np.load(os.path.join(B, "seg_1.npy")).astype(np.float32)
    bm = cv2.erode((sg[:, :, 2] > 0.8).astype(np.uint8), np.ones((15, 15), np.uint8)) > 0
    bm[:700] = False
    body_rgb = np.median(ph[bm], axis=0)[::-1].astype(np.float32)
    face_rgb = np.array(params["face_rgb"], np.float32)
    alb = np.empty((SIZE, SIZE, 3), np.float32)
    alb[:] = body_rgb
    # face is a touch warmer than the chest
    nose = H[4].astype(np.float32)
    wf = np.exp(-((pos - nose) ** 2).sum(2) / (2 * 0.085 ** 2))[:, :, None] * 0.7
    alb = alb * (1 - wf) + (0.5 * face_rgb + 0.5 * body_rgb) * wf
    # soft blotchiness so the skin is not a flat colour
    n1 = cv2.resize(rng.normal(0, 1, (96, 96)).astype(np.float32), (SIZE, SIZE), interpolation=cv2.INTER_CUBIC)
    n2 = cv2.resize(rng.normal(0, 1, (700, 700)).astype(np.float32), (SIZE, SIZE), interpolation=cv2.INTER_CUBIC)
    alb *= (1 + 0.018 * n1 + 0.012 * n2)[:, :, None] * np.array([1.0, 1.0 - 0.0, 1.0], np.float32)
    alb[:, :, 0] *= 1 + 0.010 * n1                                  # redness varies a little more

    # ---- make-up and colour zones, all placed from the mesh
    for i in (205, 425):
        blob(alb, pos, valid, H[i], 0.021, (1.0, 0.86, 0.86), 0.55)            # blush
    blob(alb, pos, valid, H[4], 0.010, (1.0, 0.88, 0.87), 0.5)                 # nose tip
    for i in (234, 454):
        blob(alb, pos, valid, H[i], 0.016, (1.0, 0.90, 0.88), 0.4)             # ears / temples
    lips = cv2.imread(os.path.join(mhlib.MH_DATA, "mpfb_lips.jpg"), cv2.IMREAD_GRAYSCALE).astype(np.float32) / 255.0
    lips = cv2.GaussianBlur(cv2.resize(lips, (SIZE, SIZE), interpolation=cv2.INTER_LINEAR), (0, 0), SIZE / 4096 * 3)[:, :, None]
    lip_rgb = np.array(params["lips_rgb"], np.float32)
    lip_rgb = 0.52 * lip_rgb + 0.48 * face_rgb * np.array([1.0, 0.86, 0.90], np.float32)   # soft nude pink
    alb = alb * (1 - 0.85 * lips) + lip_rgb * (0.85 * lips)
    for side in ("R", "L"):
        up = resample(fit[f"lid_upper_{side}"], 60)                 # outer -> inner
        lo = resample(fit[f"lid_lower_{side}"], 40)
        blob(alb, pos, valid, up.mean(0) + np.array([0, 0, 0.0045]), 0.0085, (0.88, 0.76, 0.71), 0.50)   # eye shadow
        blob(alb, pos, valid, lo.mean(0) - np.array([0, 0, 0.004]), 0.007, (0.93, 0.86, 0.86), 0.5)      # under-eye
        # winged eyeliner: along the upper lid edge, continuing past the outer corner
        t_out = up[0] - up[3]
        t_out /= np.linalg.norm(t_out)
        wing = up[0][None] + (t_out * 0.9 + np.array([0, 0, 0.45]))[None] * np.linspace(0.0005, 0.0052, 12)[:, None]
        liner = np.concatenate([wing[::-1], up])
        s = np.concatenate([np.linspace(0.25, 1.0, 12), np.linspace(1.0, 0.45, 60)])
        line(alb, pos, valid, liner, 0.00085, (0.07, 0.05, 0.045), s)
        line(alb, pos, valid, lo[:22], 0.0007, (0.22, 0.16, 0.14), np.linspace(0.6, 0.15, 22))

    # ---- freckles over nose bridge and cheeks
    eye_z = float(0.5 * (fit["eye_c_L"][2] + fit["eye_c_R"][2]))
    reg = valid & (np.abs(pos[:, :, 0]) < 0.058) & (pos[:, :, 2] < eye_z + 0.004) & (pos[:, :, 2] > H[2][2] - 0.004) & \
        (pos[:, :, 1] < H[4][1] + 0.05)
    ys, xs = np.nonzero(reg)
    if len(ys):
        pick = rng.choice(len(ys), 340, replace=False)
        for y, x in zip(ys[pick], xs[pick]):
            mmpp = float(np.linalg.norm(pos[y, min(x + 1, SIZE - 1)] - pos[y, x])) + 1e-6
            r = rng.uniform(0.00035, 0.0009) / mmpp
            k = int(np.ceil(3 * r))
            y0, y1, x0, x1 = max(y - k, 0), min(y + k + 1, SIZE), max(x - k, 0), min(x + k + 1, SIZE)
            yy, xx = np.mgrid[y0:y1, x0:x1]
            g = np.exp(-((yy - y) ** 2 + (xx - x) ** 2) / (2 * r * r))[:, :, None] * rng.uniform(0.05, 0.15)
            alb[y0:y1, x0:x1] *= 1 - g * (1 - np.array([0.80, 0.62, 0.50], np.float32))

    # ---- scalp under the hair
    hc, hr, _ = hairgen.skull(fit, base)
    hu = (pos - hc.astype(np.float32)) / hr.astype(np.float32)
    hun = hu / np.maximum(np.linalg.norm(hu, axis=2, keepdims=True), 1e-6)
    thr = np.interp(hun[:, :, 1], [-1, -0.55, 0.0, 0.5, 1.0], [0.52, 0.34, 0.10, -0.42, -0.72])
    sc = np.clip((hun[:, :, 2] - thr) / 0.10, 0, 1) * (pos[:, :, 2] > hc[2] - 0.075) * valid
    sc = cv2.GaussianBlur(sc.astype(np.float32), (0, 0), SIZE / 4096 * 10)[:, :, None]
    alb = alb * (1 - 0.9 * sc) + np.array([0.42, 0.30, 0.20], np.float32) * (0.9 * sc)

    grey = alb.mean(axis=2, keepdims=True)
    alb = grey + (alb - grey) * 0.93                         # skin slightly less saturated
    alb[~valid] = body_rgb
    os.makedirs(os.path.join(ROOT, "textures"), exist_ok=True)
    out = np.clip(alb[:, :, ::-1] * 255 + 0.5, 0, 255).astype(np.uint8)
    cv2.imwrite(os.path.join(ROOT, "textures", "skin_albedo.png"), out)
    print("painted skin_albedo.png", out.shape, "body", np.round(body_rgb, 3), "face", np.round(face_rgb, 3))


if __name__ == "__main__":
    main()
