"""Stage 2b -- fit the eye openings.

The landmark fit leaves the lids a little too open.  Here the visible eye opening of the
mesh (where a ray from the close-up camera reaches the eyeball before the skin) is
measured column by column and the lid edges are moved until the opening matches the eye
contour of the close-up photo.  Also samples a few colours from the photo.

Updates data/fit_head.npz (verts, eye_c, eye_r, lid_upper_*, lid_lower_*) and writes
data/face_params.json.
"""
import json
import os
import sys

import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
import blcore  # noqa: E402
import charlib  # noqa: E402
import fitlib  # noqa: E402
import fitscene  # noqa: E402
import mhlib  # noqa: E402

ROOT, B, RES, LENS = charlib.ROOT, charlib.B, charlib.RES, charlib.LENS
EYES = {
    "R": dict(helper="helper-r-eye", upper=[33, 246, 161, 160, 159, 158, 157, 173, 133],
              lower=[33, 7, 163, 144, 145, 153, 154, 155, 133], outer=33, inner=133, iris=[468, 469, 470, 471, 472]),
    "L": dict(helper="helper-l-eye", upper=[263, 466, 388, 387, 386, 385, 384, 398, 362],
              lower=[263, 249, 390, 373, 374, 380, 381, 382, 362], outer=263, inner=362, iris=[473, 474, 475, 476, 477]),
}
N_ITER = 5


def smooth(x, lo, hi):
    t = np.clip((x - lo) / (hi - lo), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def chain(lm, idx):
    p = lm[idx][:, :2]
    return p[np.argsort(p[:, 0])]


def scan(bvh, cam, fpx, c, R, xs, y0, y1):
    """Per image column: (y_top, y_bottom, skin point above, skin point below) of the visible eyeball."""
    ys = np.arange(y0, y1, 0.5)
    out = []
    for x in xs:
        pix = np.stack([np.full(len(ys), x), ys], axis=1)
        o, d = fitlib.pixel_rays(pix, cam, fpx, RES, RES)
        oc = o - c
        b = d @ oc
        disc = b * b - (oc @ oc - R * R)
        ts = np.where(disc > 0, -b - np.sqrt(np.maximum(disc, 0)), np.inf)
        tb = np.full(len(ys), np.inf)
        hits = [None] * len(ys)
        ov = Vector(o)
        for i in range(len(ys)):
            loc, _, _, dist = bvh.ray_cast(ov, Vector(d[i]))
            if loc is not None:
                tb[i] = dist
                hits[i] = np.array(loc)
        vis = ts < tb - 1e-5
        if not vis.any():
            out.append(None)
            continue
        # longest visible run
        idx = np.where(vis)[0]
        runs = np.split(idx, np.where(np.diff(idx) > 1)[0] + 1)
        run = max(runs, key=len)
        a, bb = run[0], run[-1]
        pa = hits[a - 1] if a > 0 and hits[a - 1] is not None else None
        pb = hits[bb + 1] if bb + 1 < len(ys) and hits[bb + 1] is not None else None
        out.append((ys[a], ys[bb], pa, pb))
    return out


def sample_colors(lm, img, seg):
    def median_in(poly, shrink=0, pct=50):
        m = np.zeros(img.shape[:2], np.uint8)
        cv2.fillPoly(m, [np.round(poly).astype(np.int32)], 255)
        if shrink:
            m = cv2.erode(m, np.ones((shrink, shrink), np.uint8))
        px = img[m > 0].astype(np.float32) / 255.0
        lum = px.mean(1)
        sel = px[lum <= np.percentile(lum, pct)] if pct < 50 else px
        return np.median(sel, axis=0)[::-1].tolist()             # rgb
    lips = median_in(lm[fitlib.LM_LIPS_OUTER][:, :2], shrink=5)
    brow = median_in(lm[[70, 63, 105, 66, 107, 55, 65, 52, 53, 46]][:, :2], pct=35)
    c, e = lm[473, :2], lm[474:478, :2]
    r = float(np.linalg.norm(e - c, axis=1).mean())
    yy, xx = np.mgrid[0:img.shape[0], 0:img.shape[1]]
    rr = np.hypot(xx - c[0], yy - c[1])
    ring = (rr > 0.50 * r) & (rr < 0.82 * r) & (np.abs(yy - c[1]) < 0.35 * r)   # left/right of the pupil only
    px = img[ring].astype(np.float32) / 255.0
    lum = px.mean(1)
    iris = np.median(px[(lum > np.percentile(lum, 25)) & (lum < np.percentile(lum, 85))], axis=0)[::-1].tolist()
    face = (seg[:, :, 3] > 0.8)
    face = cv2.erode(face.astype(np.uint8), np.ones((25, 25), np.uint8)) > 0
    px = img[face].astype(np.float32) / 255.0
    lum = px.mean(1)
    skin = np.median(px[lum > np.percentile(lum, 55)], axis=0)[::-1].tolist()
    return dict(lips_rgb=lips, brow_rgb=brow, iris_rgb=iris, face_rgb=skin)


def main():
    path = os.path.join(ROOT, "data", "fit_head.npz")
    fit = dict(np.load(path))
    v = fit["verts"].copy()
    base = mhlib.BaseMesh()
    cam = np.array(fit["cam_closeup"])
    fpx = fitlib.focal_px(LENS, RES)
    lm = np.array(json.load(open(os.path.join(B, "lm_3.json")))["landmarks"])
    fs = fitscene.FitScene(base, v, fit["eyes"], res=64, samples=1)
    fs.body.modifiers["Subdiv"].levels = 2
    up, right = cam[:3, 1], cam[:3, 0]
    params = {}
    for side, e in EYES.items():
        hp = v[base.group_indices(e["helper"])]
        c = hp.mean(0)
        R = float(np.linalg.norm(hp - c, axis=1).mean())
        cu, cl = chain(lm, e["upper"]), chain(lm, e["lower"])
        x0, x1 = cu[0, 0], cu[-1, 0]
        xs = np.linspace(x0 + 3, x1 - 3, 22)
        yu, yl = np.interp(xs, cu[:, 0], cu[:, 1]), np.interp(xs, cl[:, 0], cl[:, 1])
        (cpx,), depth_c = fitlib.project(c[None], cam, fpx, RES, RES)
        for it in range(N_ITER):
            fs.set_shape(v, fit["eyes"])
            bvh = fs.bvh()
            res = scan(bvh, cam, fpx, c, R, xs, yu.min() - 26, yl.max() + 26)
            ctrl, disp, err = [], [], []
            for x, tu, tl, r in zip(xs, yu, yl, res):
                if r is None:
                    continue
                mu, ml, pa, pb = r
                for p, d_px in ((pa, tu - mu), (pb, tl - ml)):
                    if p is None:
                        continue
                    depth = float(np.linalg.norm(p - cam[:3, 3]))
                    mm = np.clip(d_px * depth / fpx, -0.003, 0.003)
                    ctrl.append(p); disp.append(-up * mm * 0.8); err.append(abs(d_px))
            # ring of fixed points around the eye
            for rad in (0.020, 0.027):
                for a in np.linspace(0, 2 * np.pi, 20, endpoint=False):
                    px = cpx + np.array([np.cos(a), np.sin(a) * 0.8]) * rad * fpx / depth_c[0]
                    o, d = fitlib.pixel_rays(px[None], cam, fpx, RES, RES)
                    loc = bvh.ray_cast(Vector(o), Vector(d[0]))[0]
                    if loc is not None:
                        ctrl.append(np.array(loc)); disp.append(np.zeros(3))
            warp = fitlib.Warp(np.array(ctrl), np.array(disp), smoothing=2e-4)
            body = v[:mhlib.N_BODY]
            dist = np.linalg.norm(body - c, axis=1)
            near = dist < 0.030
            w = 1.0 - smooth(dist[near], 0.019, 0.029)
            body[near] += warp(body[near]) * w[:, None]
            # the lids must stay in front of the eyeball
            dist = np.linalg.norm(body - c, axis=1)
            inside = dist < R + 0.0003
            body[inside] = c + (body[inside] - c) / dist[inside][:, None] * (R + 0.0003)
            print(side, "iter", it, "mean |err| px", round(float(np.mean(err)), 2), "max", round(float(np.max(err)), 1), flush=True)
        fs.set_shape(v, fit["eyes"])
        res = scan(fs.bvh(), cam, fpx, c, R, xs, yu.min() - 26, yl.max() + 26)
        upp = np.array([r[2] for r in res if r is not None and r[2] is not None])
        low = np.array([r[3] for r in res if r is not None and r[3] is not None])
        # order outer -> inner
        if np.linalg.norm(upp[0] - fit["H"][e["outer"]]) > np.linalg.norm(upp[-1] - fit["H"][e["outer"]]):
            upp, low = upp[::-1], low[::-1]
        fit[f"lid_upper_{side}"], fit[f"lid_lower_{side}"] = upp, low
        fit[f"eye_c_{side}"], fit[f"eye_r_{side}"] = c, R
        iris_px = float(np.linalg.norm(lm[e["iris"][1:], :2] - lm[e["iris"][0], :2], axis=1).mean())
        params[f"iris_r_{side}"] = iris_px * float(depth_c[0]) / fpx
    fit["verts"] = v
    np.savez(path, **fit)
    img = cv2.imread(os.path.join(ROOT, "reference", "ref_closeup.jpg"))
    seg = np.load(os.path.join(B, "seg_3.npy")).astype(np.float32)
    params.update(sample_colors(lm, img, seg))
    json.dump(params, open(os.path.join(ROOT, "data", "face_params.json"), "w"), indent=1)
    print(json.dumps({k: (np.round(val, 4).tolist() if isinstance(val, list) else round(val, 5)) for k, val in params.items()}))


if __name__ == "__main__":
    main()
