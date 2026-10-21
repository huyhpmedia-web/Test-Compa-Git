"""UV-space painting driven by 3D position: the texture colour at each texel is a function of the
3D point on the mesh that texel maps to.  Gives mesh-density independent stripes / stubble."""
import numpy as np
from PIL import Image


def tri_list(faces):
    """faces: [(vi list, ti list)] -> list of (v0,v1,v2,t0,t1,t2)"""
    out = []
    for vi, ti in faces:
        for k in range(1, len(vi) - 1):
            out.append((vi[0], vi[k], vi[k + 1], ti[0], ti[k], ti[k + 1]))
    return out


def rasterize(tris, uv, attrs, size):
    """attrs: dict name -> (nverts,k) per-vertex arrays (first should be 'pos').
    -> dict x,y + each attr interpolated per covered texel (pixel y is top-down)."""
    xs, ys = [], []
    acc = {k: [] for k in attrs}
    uvp = np.stack([uv[:, 0] * size, (1.0 - uv[:, 1]) * size], axis=1)
    for v0, v1, v2, t0, t1, t2 in tris:
        a, b, c = uvp[t0], uvp[t1], uvp[t2]
        x0 = int(max(0, np.floor(min(a[0], b[0], c[0]) - 1))); x1 = int(min(size - 1, np.ceil(max(a[0], b[0], c[0]) + 1)))
        y0 = int(max(0, np.floor(min(a[1], b[1], c[1]) - 1))); y1 = int(min(size - 1, np.ceil(max(a[1], b[1], c[1]) + 1)))
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(d) < 1e-9:
            continue
        l1 = ((b[1] - c[1]) * (gx - c[0]) + (c[0] - b[0]) * (gy - c[1])) / d
        l2 = ((c[1] - a[1]) * (gx - c[0]) + (a[0] - c[0]) * (gy - c[1])) / d
        l3 = 1 - l1 - l2
        e = -0.02
        m = (l1 >= e) & (l2 >= e) & (l3 >= e)
        if not m.any():
            continue
        l1, l2, l3 = l1[m], l2[m], l3[m]
        xs.append(gx[m].astype(np.int32)); ys.append(gy[m].astype(np.int32))
        for k, arr in attrs.items():
            acc[k].append(l1[:, None] * arr[v0] + l2[:, None] * arr[v1] + l3[:, None] * arr[v2])
    r = dict(x=np.minimum(np.concatenate(xs), size - 1), y=np.minimum(np.concatenate(ys), size - 1))
    for k in attrs:
        r[k] = np.concatenate(acc[k])
    return r


def dilate(img, covered, iters=6):
    """bleed covered texel colours outward into uncovered texels (mip/seam padding)."""
    img = img.copy(); cov = covered.copy()
    for _ in range(iters):
        acc = np.zeros_like(img); cnt = np.zeros(cov.shape, dtype=np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
            sc = np.roll(np.roll(cov, dy, 0), dx, 1)
            si = np.roll(np.roll(img, dy, 0), dx, 1)
            acc += si * sc[..., None]; cnt += sc
        new = (~cov) & (cnt > 0)
        img[new] = acc[new] / cnt[new][:, None]
        cov = cov | new
    return img


def load_rgb(path, size):
    im = Image.open(path).convert("RGB")
    if im.size != (size, size):
        im = im.resize((size, size), Image.LANCZOS)
    return np.asarray(im, dtype=np.float32) / 255.0


def save_img(arr, path, quality=90):
    a = (np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8)
    im = Image.fromarray(a)
    if path.lower().endswith((".jpg", ".jpeg")):
        im.save(path, quality=quality, subsampling=0)
    else:
        im.save(path)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0 + 1e-12), 0, 1)
    return t * t * (3 - 2 * t)


def hash_noise(x, y, seed=0):
    h = (x.astype(np.uint32) * np.uint32(374761393) + y.astype(np.uint32) * np.uint32(668265263) + np.uint32(seed * 1442695041))
    h = (h ^ (h >> np.uint32(13))) * np.uint32(1274126177)
    h = h ^ (h >> np.uint32(16))
    return (h & np.uint32(0xFFFF)).astype(np.float32) / 65535.0


def blur(a, r=2):
    k = np.ones(2 * r + 1, dtype=np.float32) / (2 * r + 1)
    for ax in (0, 1):
        a = np.apply_along_axis(lambda m: np.convolve(np.pad(m, r, mode='edge'), k, mode='valid'), ax, a)
    return a


def vertex_normals(pos, faces):
    n = np.zeros_like(pos)
    for vi in faces:
        for k in range(1, len(vi) - 1):
            a, b, c = pos[vi[0]], pos[vi[k]], pos[vi[k + 1]]
            fn = np.cross(b - a, c - a)
            n[vi[0]] += fn; n[vi[k]] += fn; n[vi[k + 1]] += fn
    l = np.linalg.norm(n, axis=1, keepdims=True)
    return n / np.maximum(l, 1e-9)
