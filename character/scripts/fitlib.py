"""Camera maths, landmark detection and smooth warps used to fit the head to the photos."""
import os
import numpy as np
import cv2
from scipy.interpolate import RBFInterpolator

SENSOR = 36.0  # mm, horizontal


# --------------------------------------------------------------------------- camera
def focal_px(lens_mm, width):
    return lens_mm / SENSOR * width


def project(points, cam_world, fpx, w, h):
    """World points -> pixel coords (x right, y down) + camera depth (positive in front)."""
    inv = np.linalg.inv(np.asarray(cam_world, dtype=np.float64))
    pc = points @ inv[:3, :3].T + inv[:3, 3]
    depth = -pc[:, 2]
    u = w * 0.5 + fpx * pc[:, 0] / depth
    v = h * 0.5 - fpx * pc[:, 1] / depth
    return np.stack([u, v], axis=1), depth


def pixel_rays(pix, cam_world, fpx, w, h):
    """Pixel coords -> (origin, unit directions) in world space."""
    cam_world = np.asarray(cam_world, dtype=np.float64)
    d = np.stack([(pix[:, 0] - w * 0.5) / fpx, -(pix[:, 1] - h * 0.5) / fpx, -np.ones(len(pix))], axis=1)
    d = d @ cam_world[:3, :3].T
    d /= np.linalg.norm(d, axis=1, keepdims=True)
    return cam_world[:3, 3].copy(), d


def solve_pnp(model_pts, image_pts, fpx, w, h, init=None, weights=None):
    """Camera world matrix (Blender convention: looks down -Z, +Y up) from 3D-2D matches."""
    K = np.array([[fpx, 0, w * 0.5], [0, fpx, h * 0.5], [0, 0, 1]], dtype=np.float64)
    obj = np.ascontiguousarray(model_pts, dtype=np.float64).reshape(-1, 1, 3)
    img = np.ascontiguousarray(image_pts, dtype=np.float64).reshape(-1, 1, 2)
    if init is not None:
        rvec0, tvec0 = _world_to_cv(init)
        ok, rvec, tvec = cv2.solvePnP(obj, img, K, None, rvec0, tvec0, True, cv2.SOLVEPNP_ITERATIVE)
    else:
        ok, rvec, tvec = cv2.solvePnP(obj, img, K, None, flags=cv2.SOLVEPNP_EPNP)
        ok, rvec, tvec = cv2.solvePnP(obj, img, K, None, rvec, tvec, True, cv2.SOLVEPNP_ITERATIVE)
    R, _ = cv2.Rodrigues(rvec)
    # OpenCV camera (x right, y down, z forward) -> Blender camera (x right, y up, z back)
    flip = np.diag([1.0, -1.0, -1.0])
    Rw = R.T @ flip                    # camera axes in world
    C = (-R.T @ tvec).reshape(3)       # camera centre in world
    M = np.eye(4)
    M[:3, :3] = Rw
    M[:3, 3] = C
    return M


def _world_to_cv(cam_world):
    cam_world = np.asarray(cam_world, dtype=np.float64)
    flip = np.diag([1.0, -1.0, -1.0])
    R = (cam_world[:3, :3] @ flip).T
    t = -R @ cam_world[:3, 3]
    rvec, _ = cv2.Rodrigues(R)
    return rvec, t.reshape(3, 1)


def look_at(eye, target, up=(0, 0, 1)):
    eye = np.asarray(eye, dtype=np.float64)
    f = np.asarray(target, dtype=np.float64) - eye
    f /= np.linalg.norm(f)
    r = np.cross(f, np.asarray(up, dtype=np.float64))
    r /= np.linalg.norm(r)
    u = np.cross(r, f)
    M = np.eye(4)
    M[:3, 0], M[:3, 1], M[:3, 2], M[:3, 3] = r, u, -f, eye
    return M


# --------------------------------------------------------------------------- landmarks
class Detector:
    def __init__(self, model_path):
        import mediapipe as mp
        from mediapipe.tasks import python
        from mediapipe.tasks.python import vision
        self.mp = mp
        opts = vision.FaceLandmarkerOptions(
            base_options=python.BaseOptions(model_asset_path=model_path), num_faces=1,
            min_face_detection_confidence=0.3, min_face_presence_confidence=0.3)
        self.det = vision.FaceLandmarker.create_from_options(opts)

    def detect(self, path):
        img = self.mp.Image.create_from_file(path)
        res = self.det.detect(img)
        if not res.face_landmarks:
            return None
        w, h = img.width, img.height
        return np.array([[p.x * w, p.y * h, p.z * w] for p in res.face_landmarks[0]])

    def close(self):
        self.det.close()


# MediaPipe face-mesh index groups
LM_MIDLINE = [10, 151, 9, 8, 168, 6, 197, 195, 5, 4, 1, 19, 94, 2, 164, 0, 11, 12, 13, 14, 15, 16, 17, 18,
              200, 199, 175, 152]
LM_RIGHT_EYE = [33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246]
LM_LEFT_EYE = [263, 249, 390, 373, 374, 380, 381, 382, 362, 398, 384, 385, 386, 387, 388, 466]
LM_RIGHT_IRIS = [468, 469, 470, 471, 472]
LM_LEFT_IRIS = [473, 474, 475, 476, 477]
LM_LIPS_OUTER = [61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 409, 270, 269, 267, 0, 37, 39, 40, 185]
LM_LIPS_INNER = [78, 95, 88, 178, 87, 14, 317, 402, 318, 324, 308, 415, 310, 311, 312, 13, 82, 81, 80, 191]
LM_FACE_OVAL = [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377,
                152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109]


def mirror_pairs(points, tol=None):
    """For symmetric 3D landmark positions, index of each landmark's mirror partner (x -> -x)."""
    pts = np.asarray(points)
    mir = pts * np.array([-1.0, 1.0, 1.0])
    d = np.linalg.norm(pts[:, None, :] - mir[None, :, :], axis=2)
    return d.argmin(axis=1)


# --------------------------------------------------------------------------- warps
class Warp:
    """Smooth 3D displacement field interpolated from scattered control displacements."""

    def __init__(self, ctrl, disp, smoothing=1e-6, kernel="linear"):
        self.rbf = RBFInterpolator(np.asarray(ctrl), np.asarray(disp), kernel=kernel,
                                   smoothing=smoothing, degree=1)

    def __call__(self, pts):
        return self.rbf(np.asarray(pts))


def scalar_field(ctrl, values, smoothing=1e-6, kernel="linear"):
    rbf = RBFInterpolator(np.asarray(ctrl), np.asarray(values).reshape(-1, 1), kernel=kernel,
                          smoothing=smoothing, degree=1)
    return lambda pts: rbf(np.asarray(pts))[:, 0]
