"""Eyebrows and eyelashes as real hair curves (rest pose; bone-parented to the head)."""
import json
import math
import os

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

import blcore
import charlib
import hairgen

BROWS = {"R": ([107, 66, 105, 63, 70], [55, 65, 52, 53, 46]),       # inner -> outer: upper edge, lower edge
         "L": ([336, 296, 334, 293, 300], [285, 295, 282, 283, 276])}


def _mat(name, melanin, redness=0.35, rough=0.4):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    h = nt.nodes.new("ShaderNodeBsdfHairPrincipled")
    h.parametrization = 'MELANIN'
    h.inputs["Melanin"].default_value = melanin
    h.inputs["Melanin Redness"].default_value = redness
    h.inputs["Roughness"].default_value = rough
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(h.outputs[0], out.inputs["Surface"])
    return mat


def _interp(poly, s):
    seg = np.linalg.norm(np.diff(poly, axis=0), axis=1)
    t = np.concatenate([[0], np.cumsum(seg)]) / seg.sum()
    return np.stack([np.interp(s, t, poly[:, k]) for k in range(3)], axis=1)


def brows(fit, bvh, rng, n=330, k=5):
    H = fit["H"]
    strands = []
    for side, (up_i, lo_i) in BROWS.items():
        up, lo = H[up_i], H[lo_i]
        s = np.clip(rng.beta(1.3, 1.5, n) * 1.04 - 0.02, 0, 1)        # 0 = inner end, 1 = tail
        t = rng.random(n)
        root = _interp(lo, s) * (1 - t)[:, None] + _interp(up, s) * t[:, None]
        mid0, mid1 = 0.5 * (_interp(lo, s) + _interp(up, s)), 0.5 * (_interp(lo, np.clip(s + 0.05, 0, 1)) + _interp(up, np.clip(s + 0.05, 0, 1)))
        T = mid1 - mid0
        T /= np.maximum(np.linalg.norm(T, axis=1, keepdims=True), 1e-9)
        U = _interp(up, s) - _interp(lo, s)
        U /= np.maximum(np.linalg.norm(U, axis=1, keepdims=True), 1e-9)
        # lower hairs sweep up-and-out, upper hairs lie along the brow; the inner end stands up
        ang = np.radians(40 - 48 * t + 22 * np.clip(1 - s / 0.22, 0, 1) + rng.normal(0, 7, n))
        d = T * np.cos(ang)[:, None] + U * np.sin(ang)[:, None]
        L = (0.0072 - 0.0026 * s) * rng.uniform(0.75, 1.15, n)
        for i in range(n):
            loc, nrm, _, _ = bvh.find_nearest(Vector(root[i]))
            p0, nn = np.array(loc), np.array(nrm)
            di = d[i] - nn * (d[i] @ nn)
            di /= max(np.linalg.norm(di), 1e-9)
            u = np.linspace(0, 1, k)
            lift = 0.0011 * np.sin(np.pi * np.minimum(u * 1.15, 1.0)) + 0.0002
            strands.append(p0[None] + di[None] * (L[i] * u)[:, None] + nn[None] * lift[:, None])
    return np.array(strands)


def lashes(fit, rng, k=6):
    strands = []
    up_w = np.array([0.0, 0.0, 1.0])
    for side in ("R", "L"):
        c = fit[f"eye_c_{side}"]
        for which, n, sgn in (("upper", 115, 1.0), ("lower", 55, -1.0)):
            curve = fit[f"lid_{which}_{side}"]                       # outer -> inner
            s = rng.uniform(0.02, 0.90 if which == "upper" else 0.80, n)
            root = _interp(curve, s)
            rad = root - c
            rad /= np.linalg.norm(rad, axis=1, keepdims=True)
            lat = np.array([-1.0 if side == "R" else 1.0, 0.0, 0.0])    # towards the temple
            base = np.array([0.0, -1.0, 0.0])[None] * 0.75 + rad * 0.35 + lat[None] * (0.30 * (1 - s))[:, None] \
                + up_w[None] * (0.18 * sgn) + rng.normal(0, 0.07, (n, 3))
            base /= np.linalg.norm(base, axis=1, keepdims=True)
            if which == "upper":
                L = (0.0098 - 0.0045 * s) * rng.uniform(0.8, 1.12, n)
                curl = 0.55
            else:
                L = (0.0052 - 0.0018 * s) * rng.uniform(0.75, 1.1, n)
                curl = 0.30
            u = np.linspace(0, 1, k)
            for i in range(n):
                pts = root[i][None] + base[i][None] * (L[i] * u)[:, None] + up_w[None] * (sgn * curl * L[i] * u ** 2)[:, None]
                strands.append(pts)
    return np.array(strands)


def build(base, fit, body, rig, col):
    rng = np.random.default_rng(11)
    if "lid_upper_R" not in fit:
        return {"head_objects": []}
    bvh = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get())
    params = json.load(open(os.path.join(charlib.ROOT, "data", "face_params.json")))
    br = brows(fit, bvh, rng)
    lum = float(np.mean(params.get("brow_rgb", [0.4, 0.3, 0.25])))
    ob_b = hairgen.make_curves("Eyebrows", br, _mat("Hair_Brows", float(np.clip(0.95 - lum * 1.6, 0.36, 0.7))), col,
                               root_r=0.000038, tip_r=0.000010)
    la = lashes(fit, rng)
    ob_l = hairgen.make_curves("Eyelashes", la, _mat("Hair_Lashes", 1.0, 0.2, 0.3), col, root_r=0.000050, tip_r=0.000008)
    print("brow hairs", len(br), "lashes", len(la))
    return {"head_objects": [ob_b, ob_l]}
