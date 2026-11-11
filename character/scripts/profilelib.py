"""Face-profile contours: extraction from the side photo and from the mesh, feature
detection (nasion, nose tip, lips, chin ...) and contour-to-contour correspondence.

Every contour is expressed in a common 2D frame:  a = anterior (towards the nose),
u = up.  Photo: a = +x px, u = -y px.  Model: a = -Y m, u = +Z m.
"""
import os
import numpy as np
import cv2
from scipy.ndimage import gaussian_filter1d
from scipy.signal import find_peaks

FEATURES = ["glabella", "nasion", "pronasale", "subnasale", "labrale_sup", "stomion",
            "labrale_inf", "sublabiale", "pogonion", "menton"]


# --------------------------------------------------------------------------- photo
def photo_contour(img_bgr, seg, y0=150, y1=760):
    """Ordered polyline (a, u) in pixels, from the forehead down to the neck."""
    lab = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    L = cv2.GaussianBlur(lab[:, :, 0], (0, 0), 1.2)
    skin = seg[:, :, 2] + seg[:, :, 3]
    h, w = L.shape

    def edge_row(y):
        xs = np.where(skin[y] > 0.5)[0]
        if len(xs) == 0:
            return None
        x0 = xs.max()
        lo, hi = max(x0 - 14, 1), min(x0 + 14, w - 2)
        g = L[y, lo - 1:hi] - L[y, lo + 1:hi + 2]
        k = int(np.argmax(g))
        off = 0.0
        if 0 < k < len(g) - 1:
            den = g[k - 1] - 2 * g[k] + g[k + 1]
            if abs(den) > 1e-6:
                off = 0.5 * (g[k - 1] - g[k + 1]) / den
        return lo + k + off, float(g[k])

    rows = []
    for y in range(y0, y1):
        r = edge_row(y)
        if r is not None and r[1] > 6:
            rows.append((r[0], float(y)))
    rows = np.array(rows)
    # the chin ends where the row-wise edge jumps back towards the neck
    jump = np.where(np.diff(rows[:, 0]) < -25)[0]
    k = int(jump[0]) if len(jump) else len(rows) - 1
    upper, lower = rows[:k + 1], rows[k + 1:]
    # under the chin: column-wise scan (lowest skin pixel of each column)
    under = []
    if len(lower):
        xa, xb = int(lower[0, 0]) + 2, int(upper[-1, 0]) - 1
        yc = int(upper[-1, 1])
        for x in range(xb, xa, -1):
            col = L[yc - 45:yc + 40, x]
            g = col[:-2] - col[2:]
            j = int(np.argmax(g))
            if g[j] > 6:
                under.append((float(x), float(yc - 45 + j + 1)))
    parts = [upper] + ([np.array(under)] if under else []) + ([lower] if len(lower) else [])
    pts = np.concatenate(parts)
    return np.stack([pts[:, 0], -pts[:, 1]], axis=1)


# --------------------------------------------------------------------------- model
def model_contour(verts, tris, z_top, z_bot=1.33, half_width=0.06, res=0.0001):
    """Profile silhouette of a triangle mesh seen from the side (orthographic).
    The triangles are rasterised into a mask; returns ordered (a, u) in metres."""
    cen = verts[tris].mean(axis=1)
    keep = (np.abs(cen[:, 0]) < half_width) & (cen[:, 2] > z_bot - 0.02) & (cen[:, 2] < z_top + 0.02)
    t = tris[keep]
    a_all, u_all = -verts[:, 1], verts[:, 2]
    a_min = float(a_all[t].min()) - 0.002
    u_max = z_top
    w = int((float(a_all[t].max()) + 0.002 - a_min) / res) + 2
    h = int((u_max - z_bot) / res) + 2
    px = np.stack([(a_all - a_min) / res, (u_max - u_all) / res], axis=1)
    mask = np.zeros((h, w), dtype=np.uint8)
    polys = np.round(px[t] * 16).astype(np.int32)           # 4 fractional bits
    for i in range(0, len(polys), 20000):
        cv2.fillPoly(mask, list(polys[i:i + 20000]), 255, lineType=cv2.LINE_8, shift=4)
    cols = np.arange(w)
    rows = []
    for y in range(h):
        xs = cols[mask[y] > 0]
        if len(xs):
            rows.append((xs.max(), y))
    rows = np.array(rows, dtype=np.float64)
    jump = np.where(np.diff(rows[:, 0]) < -0.008 / res)[0]
    if len(jump):
        k = int(jump[0])
        upper, lower = rows[:k + 1], rows[k + 1:]
        xa, xb = int(lower[0, 0]) + 1, int(upper[-1, 0])
        yc = int(upper[-1, 1])
        under = []
        for x in range(xb, xa, -1):
            ys = np.where(mask[max(yc - 400, 0):min(yc + 300, h), x] > 0)[0]
            if len(ys):
                under.append((x, max(yc - 400, 0) + ys.max()))
        rows = np.concatenate([upper, np.array(under, dtype=np.float64).reshape(-1, 2), lower])
    return np.stack([a_min + rows[:, 0] * res, u_max - rows[:, 1] * res], axis=1)


# --------------------------------------------------------------------------- features
def resample(poly, step):
    seg = np.linalg.norm(np.diff(poly, axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    keep = np.concatenate([[True], seg > 1e-12])
    s, poly = s[keep], poly[keep]
    t = np.arange(0, s[-1], step)
    return np.stack([np.interp(t, s, poly[:, 0]), np.interp(t, s, poly[:, 1])], axis=1)


def find_features(poly, mm):
    """poly: ordered (a, u), top -> bottom.  mm: length of one millimetre in contour units.
    Returns {name: index into the resampled polyline}, resampled polyline."""
    step = 0.25 * mm
    p = resample(poly, step)
    a = gaussian_filter1d(p[:, 0], 1.0 / 0.25)   # 1 mm smoothing
    u = gaussian_filter1d(p[:, 1], 1.0 / 0.25)
    n = len(a)
    per_mm = int(round(1 / 0.25))
    # nose tip: most anterior point of the upper 2/3 of the contour
    lim = int(n * 0.7)
    tip = int(np.argmax(a[:lim]))
    f = {"pronasale": tip}
    up0 = max(tip - 70 * per_mm, 0)
    nas = up0 + int(np.argmin(a[up0:tip - 8 * per_mm]))
    f["nasion"] = nas
    g0 = max(nas - 28 * per_mm, 0)
    f["glabella"] = g0 + int(np.argmax(a[g0:nas])) if nas - g0 > 4 else g0
    prom = 0.25 * mm
    mins, _ = find_peaks(-a[tip:], prominence=prom)
    maxs, _ = find_peaks(a[tip:], prominence=prom)
    mins, maxs = mins + tip, maxs + tip
    seq = [("subnasale", mins), ("labrale_sup", maxs), ("stomion", mins), ("labrale_inf", maxs),
           ("sublabiale", mins), ("pogonion", maxs)]
    cur = tip
    for name, cand in seq:
        nxt = cand[cand > cur + per_mm]
        if not len(nxt):
            raise RuntimeError(f"profile feature not found: {name}")
        cur = int(nxt[0])
        f[name] = cur
    # gnathion: chin point farthest along the forward-and-down diagonal (stable even when
    # the under-chin line is flat, unlike "lowest point")
    end = min(cur + 45 * per_mm, n)
    f["menton"] = cur + int(np.argmax(a[cur:end] - u[cur:end]))
    return f, np.stack([a, u], axis=1)


def correspond(pa, fa, pb, fb, mm_a, mm_b, n_per=12, fore_mm=30.0, tail_mm=55.0):
    """Matching point lists on two contours: same fraction of arc between the same features,
    plus a forehead stretch above the glabella and a chin/neck stretch below the menton."""
    def seg(p, i0, i1, n):
        idx = np.linspace(i0, i1, n, endpoint=False)
        return np.stack([np.interp(idx, np.arange(len(p)), p[:, 0]),
                         np.interp(idx, np.arange(len(p)), p[:, 1])], axis=1)
    A, Bp, labels = [], [], []
    per_a, per_b = 1 / 0.25, 1 / 0.25          # samples per mm in each resampled contour
    na = int(min(fore_mm * per_a, fa["glabella"]))
    nb = int(min(fore_mm * per_b, fb["glabella"]))
    k = min(na, nb)
    A.append(seg(pa, fa["glabella"] - k, fa["glabella"], n_per)); Bp.append(seg(pb, fb["glabella"] - k, fb["glabella"], n_per))
    labels += ["forehead"] * n_per
    for n0, n1 in zip(FEATURES[:-1], FEATURES[1:]):
        A.append(seg(pa, fa[n0], fa[n1], n_per)); Bp.append(seg(pb, fb[n0], fb[n1], n_per))
        labels += [n0] * n_per
    ta = int(min(tail_mm * per_a, len(pa) - 1 - fa["menton"]))
    tb = int(min(tail_mm * per_b, len(pb) - 1 - fb["menton"]))
    k = min(ta, tb)
    nt = max(int(k / per_a / 2.5), 2)
    A.append(seg(pa, fa["menton"], fa["menton"] + k, nt)); Bp.append(seg(pb, fb["menton"], fb["menton"] + k, nt))
    labels += ["neck"] * nt
    return np.concatenate(A), np.concatenate(Bp), labels


def similarity_2d(src, dst, weights=None):
    """Least-squares similarity (scale, rotation, translation) mapping src -> dst."""
    w = np.ones(len(src)) if weights is None else np.asarray(weights, dtype=np.float64)
    w = w / w.sum()
    mu_s, mu_d = (src * w[:, None]).sum(0), (dst * w[:, None]).sum(0)
    xs, xd = src - mu_s, dst - mu_d
    cov = (xd * w[:, None]).T @ xs
    U, S, Vt = np.linalg.svd(cov)
    d = np.sign(np.linalg.det(U @ Vt))
    Dm = np.diag([1.0, d])
    R = U @ Dm @ Vt
    var = (w * (xs ** 2).sum(1)).sum()
    s = (S * np.diag(Dm)).sum() / var
    t = mu_d - s * R @ mu_s
    return s, R, t
