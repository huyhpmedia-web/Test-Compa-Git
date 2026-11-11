"""Extract the face profile silhouette (forehead -> nose -> lips -> chin -> neck) from the
side-view reference.  Output: build/profile_contour.npy  (N x 2 pixel coords, top to bottom)."""
import os, sys
import numpy as np, cv2
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE); B = os.path.join(ROOT, "build")

def main():
    img = cv2.imread(os.path.join(ROOT, "reference", "ref_profile.jpg"))
    seg = np.load(os.path.join(B, "seg_2.npy")).astype(np.float32)
    lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB).astype(np.float32)
    L = cv2.GaussianBlur(lab[:, :, 0], (0, 0), 1.2)
    person = 1.0 - seg[:, :, 0]
    skin = seg[:, :, 2] + seg[:, :, 3]
    h, w = L.shape
    pts = []
    for y in range(150, 700):
        row_skin = skin[y]
        xs = np.where(row_skin > 0.5)[0]
        if len(xs) == 0:
            continue
        x0 = xs.max()                       # coarse edge from the segmentation
        lo, hi = max(x0 - 14, 1), min(x0 + 14, w - 2)
        g = L[y, lo - 1:hi] - L[y, lo + 1:hi + 2]     # brightness drop going right (skin -> background)
        k = int(np.argmax(g))
        # sub-pixel: parabola through the gradient peak
        if 0 < k < len(g) - 1:
            den = g[k - 1] - 2 * g[k] + g[k + 1]
            off = 0.5 * (g[k - 1] - g[k + 1]) / den if abs(den) > 1e-6 else 0.0
        else:
            off = 0.0
        pts.append((lo + k + off, y, g[k]))
    pts = np.array(pts)
    np.save(os.path.join(B, "profile_contour_raw.npy"), pts)
    vis = img.copy()
    for x, y, g in pts:
        cv2.circle(vis, (int(round(x)), int(y)), 1, (0, 255, 0) if g > 12 else (0, 0, 255), -1)
    cv2.imwrite(os.path.join(B, "profile_contour_dbg.png"), vis[120:720, 560:1000])
    print(len(pts))

if __name__ == "__main__":
    main()
