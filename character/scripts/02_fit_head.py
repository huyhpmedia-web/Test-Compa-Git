"""Stage 2 -- fit the MakeHuman head to the three reference photos.

Two kinds of step are interleaved until they agree:

* frontal step  (close-up + front photo): render the current head from the estimated
  photo camera, run the same landmark detector on the render and on the photo, convert
  the pixel residuals into in-plane 3D displacements and apply them as a smooth warp.
* profile step  (side photo): match the silhouette of the face profile (forehead, nose,
  lips, chin) and apply the difference as a depth warp that fades towards the cheeks.

usage: 02_fit_head.py [<init.npz>] [<out.npz>]      (no init -> start from the base mesh)
"""
import json
import os
import sys

import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy  # noqa: E402
import blcore  # noqa: E402
import fitlib  # noqa: E402
import fitscene  # noqa: E402
import mhlib  # noqa: E402
import profilelib as pl  # noqa: E402

ROOT = os.path.dirname(HERE)
B = os.path.join(ROOT, "build")
RES = 1254

MACROS = dict(gender=0.0, age=0.5, muscle=0.45, weight=0.42, proportions=0.9, height=0.5,
              cupsize=1.0, firmness=0.7, race=dict(caucasian=1.0, asian=0.0, african=0.0))

PHOTOS = {
    "closeup": dict(img="ref_closeup.jpg", lm="lm_3.json", seg="seg_3.npy", lens=85.0, weight=1.0),
    "front": dict(img="ref_front.jpg", lm="lm_1.json", seg="seg_1.npy", lens=85.0, weight=0.6),
}
ROUNDS = int(os.environ.get("FIT_ROUNDS", "8"))
GAIN_XY = 0.8
GAIN_SCALE = 0.5
GAIN_PROFILE = 0.8
SYM_XY = 0.25      # how strongly visible landmarks are pulled toward the mirrored solution
SMOOTH = 0.0015    # RBF smoothing (metres)


def smoothstep(z, lo, hi):
    t = np.clip((z - lo) / (hi - lo), 0.0, 1.0)
    return t * t * (3 - 2 * t)


class HeadFit:
    def __init__(self, init=None):
        self.base = mhlib.BaseMesh()
        self.extra = {}
        if init:
            self.extra = dict(np.load(init))
            self.v, self.eyes = self.extra["verts"], self.extra["eyes"]
        else:
            self.v, _ = mhlib.build_shape(self.base, MACROS)
            self.v[:, 2] -= mhlib.joint_positions(self.base, self.v)["joint-ground"][2]
            self.eyes = np.array([self.v[self.base.group_indices("helper-l-eye")].mean(0),
                                  self.v[self.base.group_indices("helper-r-eye")].mean(0)])
            np.save(os.path.join(B, "base_shape.npy"), self.v)
        self.fs = fitscene.FitScene(self.base, self.v, self.eyes, res=RES)
        self.det = fitlib.Detector(os.path.join(ROOT, "models", "face_landmarker.task"))
        self.photos = {}
        for name, spec in PHOTOS.items():
            d = json.load(open(os.path.join(B, spec["lm"])))
            lm = np.array(d["landmarks"])
            seg = np.load(os.path.join(B, spec["seg"])).astype(np.float32)
            xi = np.clip(np.round(lm[:, 0]).astype(int), 0, RES - 1)
            yi = np.clip(np.round(lm[:, 1]).astype(int), 0, RES - 1)
            vis = (seg[yi, xi, 1] < 0.4).astype(np.float64)
            self.photos[name] = dict(lm=lm, vis=vis, lens=spec["lens"], weight=spec["weight"], cam=None,
                                     img=os.path.join(ROOT, "reference", spec["img"]))
        # where do the landmarks sit on the current head?
        head_c = np.array([0.0, -0.10, self.eyes[0][2] - 0.03])
        cam0 = fitlib.look_at(head_c + np.array([0, -0.85, 0.0]), head_c)
        p = self.fs.render(cam0, 85.0, os.path.join(B, "fit_canon.png"))
        lm0 = self.det.detect(p)
        self.H, self.okH = self.fs.raycast(lm0[:, :2], cam0, 85.0)
        self.mirror = fitlib.mirror_pairs(np.where(self.okH[:, None], self.H, 1e3))
        body = self.v[:mhlib.N_BODY]
        self.anchors = np.where(((body[:, 1] > 0.03) & (body[:, 2] > 1.44)) |
                                ((body[:, 2] > 1.33) & (body[:, 2] < 1.36) & (np.abs(body[:, 0]) < 0.08)))[0][::5]
        # profile photo
        img = cv2.imread(os.path.join(ROOT, "reference", "ref_profile.jpg"))
        seg = np.load(os.path.join(B, "seg_2.npy")).astype(np.float32)
        self.profile_img = img
        self.pa_raw = pl.photo_contour(img, seg)
        self.mm_a = 2.7
        self.profile_xf = None

    # ------------------------------------------------------------------ frontal
    def frontal_step(self, tag, debug=False):
        v, H, okH, mirror = self.v, self.H, self.okH, self.mirror
        D_sum, W_sum = np.zeros((478, 3)), np.zeros(478)
        H_sum, Hn = np.zeros((478, 3)), np.zeros(478)
        stats = {}
        for name, ph in self.photos.items():
            fpx = fitlib.focal_px(ph["lens"], RES)
            use = okH & (ph["vis"] > 0) & (np.arange(478) < 468)
            ph["cam"] = fitlib.solve_pnp(H[use], ph["lm"][use, :2], fpx, RES, RES, init=ph["cam"])
            path = os.path.join(B, f"fit_{name}.png")
            self.fs.render(ph["cam"], ph["lens"], path)
            lr = self.det.detect(path)
            if lr is None:
                print("  no face in render", name)
                continue
            Hr, ok = self.fs.raycast(lr[:, :2], ph["cam"], ph["lens"])
            _, depth = fitlib.project(Hr, ph["cam"], fpx, RES, RES)
            res = ph["lm"][:, :2] - lr[:, :2]
            w = ok * ph["vis"] * ph["weight"]
            w[468:] = 0.0
            d_cam = np.stack([res[:, 0] * depth / fpx, -res[:, 1] * depth / fpx, np.zeros(478)], axis=1)
            D_sum += (d_cam @ ph["cam"][:3, :3].T) * w[:, None]
            W_sum += w
            H_sum += Hr * ok[:, None]
            Hn += ok
            stats[name] = round(float(np.sqrt((res[w > 0] ** 2).sum(1).mean())), 2)
            if debug:
                mix = cv2.addWeighted(cv2.imread(ph["img"]), 0.5, cv2.imread(path), 0.5, 0)
                for a, bb, ww in zip(ph["lm"], lr, w):
                    if ww > 0:
                        cv2.circle(mix, (int(a[0]), int(a[1])), 2, (0, 255, 0), -1)
                        cv2.circle(mix, (int(bb[0]), int(bb[1])), 2, (0, 0, 255), -1)
                cv2.imwrite(os.path.join(B, f"fit_dbg_{tag}_{name}.png"), mix)
        valid = Hn > 0
        Hc = np.where(valid[:, None], H_sum / np.maximum(Hn, 1)[:, None], H)
        D = np.where(W_sum[:, None] > 0, D_sum / np.maximum(W_sum, 1e-9)[:, None], 0.0)
        # symmetry: occluded landmarks copy their mirror partner; visible ones are nudged
        Dm = D[mirror] * np.array([-1.0, 1.0, 1.0])
        Wm = W_sum[mirror]
        Dn = D.copy()
        for c, beta in ((0, SYM_XY), (1, 1.0), (2, SYM_XY)):
            den = W_sum + beta * Wm
            Dn[:, c] = np.where(den > 0, (W_sum * D[:, c] + beta * Wm * Dm[:, c]) / np.maximum(den, 1e-9), 0.0)
        have = valid & ((W_sum + Wm) > 0) & (np.arange(478) < 468)
        # (a) global part: anisotropic scale of the whole head (depth scale = mean of the others)
        c0 = Hc[have].mean(axis=0)
        A, T = np.zeros(3), np.zeros(3)
        for c in (0, 2):
            X = np.stack([Hc[have][:, c] - c0[c], np.ones(have.sum())], axis=1)
            sol, *_ = np.linalg.lstsq(X, Dn[have][:, c], rcond=None)
            A[c], T[c] = sol
        A[1] = 0.5 * (A[0] + A[2])
        glob = lambda pts: ((pts - c0) * A + T) * GAIN_SCALE
        # (b) local part: smooth RBF warp of what the global scale cannot explain
        ctrl = np.concatenate([Hc[have], v[self.anchors]])
        disp = np.concatenate([(Dn[have] - ((Hc[have] - c0) * A + T)) * GAIN_XY, np.zeros((len(self.anchors), 3))])
        warp = fitlib.Warp(ctrl, disp, smoothing=SMOOTH)
        field = lambda pts: glob(pts) + warp(pts)
        dv = field(v) * smoothstep(v[:, 2], 1.355, 1.41)[:, None]
        self.v = v + dv
        self.eyes = self.eyes + field(self.eyes)
        self.H = Hc + field(Hc)
        self.okH = valid
        self.fs.set_shape(self.v, self.eyes)
        stats["scale_pct"] = [round(float(a) * 100, 2) for a in A]
        stats["max_mm"] = round(float(np.linalg.norm(dv[:mhlib.N_BODY], axis=1).max() * 1000), 2)
        return stats

    # ------------------------------------------------------------------ profile
    def profile_step(self):
        v = self.v
        dense, tris = blcore.evaluated_tris(self.fs.body)
        pb_raw = pl.model_contour(dense, tris, dense[:, 2].max() - 0.045)
        fb, pb = pl.find_features(pb_raw, 0.001)
        for _ in range(3):                         # features <-> alignment fixed point
            fa, pa = pl.find_features(self.pa_raw, self.mm_a)
            A, Bm, labels = pl.correspond(pa, fa, pb, fb, self.mm_a, 0.001, tail_mm=30.0)
            lab = np.array(labels)
            w = np.where((lab == "neck") | (lab == "forehead"), 0.0, 1.0)
            s, R, t = pl.similarity_2d(A, Bm, w)
            self.mm_a = 0.001 / s
        delta = (A @ R.T) * s + t - Bm
        wgt = np.where(lab == "neck", 0.5, 1.0)[:, None] * GAIN_PROFILE
        lateral = self.H[(np.abs(self.H[:, 0]) > 0.032) & self.okH]
        ctrl = np.concatenate([np.stack([np.zeros(len(Bm)), -Bm[:, 0], Bm[:, 1]], axis=1), lateral, v[self.anchors]])
        disp = np.concatenate([np.stack([np.zeros(len(Bm)), -delta[:, 0], delta[:, 1]], axis=1) * wgt,
                               np.zeros((len(lateral), 3)), np.zeros((len(self.anchors), 3))])
        warp = fitlib.Warp(ctrl, disp, smoothing=0.001)
        self.v = v + warp(v) * smoothstep(v[:, 2], 1.365, 1.41)[:, None]
        self.eyes = self.eyes + warp(self.eyes)
        self.H = self.H + warp(self.H)
        self.fs.set_shape(self.v, self.eyes)
        self.profile_xf = (s, R, t)
        return dict(rms_mm=round(float(np.sqrt((delta[w > 0] ** 2).sum(1).mean()) * 1000), 2),
                    max_mm=round(float(np.abs(delta[w > 0]).max() * 1000), 2),
                    px_per_mm=round(self.mm_a, 3),
                    pitch=round(float(np.degrees(np.arctan2(R[1, 0], R[0, 0]))), 2))

    def profile_debug(self, path):
        s, R, t = self.profile_xf
        dense, tris = blcore.evaluated_tris(self.fs.body)
        pb_raw = pl.model_contour(dense, tris, dense[:, 2].max() - 0.045)
        back = ((pb_raw - t) @ R) / s
        vis = self.profile_img.copy()
        for x, y in zip(self.pa_raw[:, 0], -self.pa_raw[:, 1]):
            cv2.circle(vis, (int(round(x)), int(round(y))), 1, (0, 255, 0), -1)
        for x, y in zip(back[:, 0], -back[:, 1]):
            cv2.circle(vis, (int(round(x)), int(round(y))), 1, (0, 0, 255), -1)
        cv2.imwrite(path, vis[120:760, 520:1000])

    def save(self, out):
        s, R, t = self.profile_xf
        self.extra.update(verts=self.v, eyes=self.eyes, H=self.H, okH=self.okH, mirror=self.mirror,
                          cam_closeup=self.photos["closeup"]["cam"], cam_front=self.photos["front"]["cam"],
                          profile_s=s, profile_R=R, profile_t=t, profile_mm=self.mm_a)
        np.savez(out, **self.extra)


def main(init=None, out=None):
    out = out or os.path.join(B, "fit_head.npz")
    fit = HeadFit(init)
    log = []
    for r in range(1, ROUNDS + 1):
        a = fit.frontal_step(f"r{r:02d}", debug=r in (1, ROUNDS))
        try:
            b = fit.profile_step()
        except RuntimeError as exc:          # a profile feature vanished this round: skip it
            b = dict(skipped=str(exc))
        log.append(dict(round=r, frontal=a, profile=b))
        if fit.profile_xf is not None:
            fit.save(out)                    # checkpoint every round
        print(f"round {r}: frontal {json.dumps(a)}  profile {json.dumps(b)}", flush=True)
    a = fit.frontal_step("final", debug=True)
    print("final frontal", json.dumps(a))
    fit.profile_debug(os.path.join(B, "profile_fit_dbg.png"))
    fit.save(out)
    json.dump(log, open(os.path.join(B, "fit_head_log.json"), "w"), indent=1)
    fit.det.close()


if __name__ == "__main__":
    main(*sys.argv[1:3])
