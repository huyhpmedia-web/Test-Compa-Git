"""Hair: side-parted wavy chin-length bob as a Curves object (dark roots -> pale blonde).

Strands are combed away from the part line over an ellipsoid fitted to the skull, then
hang freely with waves and flipped ends.  Guides are multiplied into clumped children.
"""
import math

import bpy
import numpy as np

import blcore
import mhlib

N_GUIDES = 2600
CHILDREN = 22
K = 22                       # points per strand
PART_ANGLE = math.radians(33.0)   # part sits on her left (towards +X) of the top of the head


def _smooth(x, lo, hi):
    t = np.clip((x - lo) / (hi - lo), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def skull(fit, base):
    v = fit["verts"][:mhlib.N_BODY]
    z_eye = float(fit["eyes"][:, 2].mean())
    cr = v[v[:, 2] > z_eye + 0.01]
    c = np.array([0.0, 0.5 * (cr[:, 1].min() + cr[:, 1].max()), z_eye + 0.012])
    r = np.array([np.abs(cr[:, 0]).max(), 0.5 * (cr[:, 1].max() - cr[:, 1].min()), cr[:, 2].max() - c[2]])
    return c, r, z_eye


def scalp_roots(fit, base, c, r, n, rng):
    v = fit["verts"][:mhlib.N_BODY]
    faces = np.array([base.faces[i] for i in base.body_faces()])
    cen = v[faces].mean(axis=1)
    u = (cen - c) / r
    un = u / np.linalg.norm(u, axis=1, keepdims=True)
    thr = np.interp(un[:, 1], [-1, -0.55, 0.0, 0.5, 1.0], [0.52, 0.34, 0.10, -0.42, -0.72])
    ok = (un[:, 2] > thr) & (cen[:, 2] > c[2] - 0.075) & (np.linalg.norm(u, axis=1) > 0.8)
    f = faces[ok]
    a, b, d, e = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]], v[f[:, 3]]
    area = 0.5 * (np.linalg.norm(np.cross(b - a, d - a), axis=1) + np.linalg.norm(np.cross(d - a, e - a), axis=1))
    pick = rng.choice(len(f), size=n, p=area / area.sum())
    s, t = rng.random(n), rng.random(n)
    pts = (a[pick] * ((1 - s) * (1 - t))[:, None] + b[pick] * (s * (1 - t))[:, None] +
           d[pick] * (s * t)[:, None] + e[pick] * ((1 - s) * t)[:, None])
    return pts, ok, faces


def comb(roots, c, r, z_eye, rng, ear_y):
    """Guide strands.  Every strand runs from its root over the skull (great arc on the
    offset ellipsoid) to a release point at temple height whose azimuth is restricted to the
    sides / back of the head, then hangs with waves and a flipped end.  Returns (n, K, 3)."""
    n = len(roots)
    u = (roots - c) / r
    un = u / np.linalg.norm(u, axis=1, keepdims=True)
    layer = rng.random(n)                                    # 0 = inner, 1 = outer layer
    part_x = np.interp(un[:, 1], [-0.9, 0.5], [math.sin(PART_ANGLE) * 0.80, math.sin(PART_ANGLE) * 0.55])
    side = np.where(un[:, 0] < part_x, -1.0, 1.0)            # -1: swept to her right
    uy = un[:, 1]
    # release azimuth (degrees): 0 = front, +90 = her left, -90 = her right, 180 = back.
    # right: a face-framing lock in front of the ear, the rest behind it; left: all tucked behind the ear
    phi_r = np.where(uy < -0.25, np.interp(uy, [-0.9, -0.25], [-50.0, -66.0]),
                     np.interp(uy, [-0.25, 0.9], [-120.0, -180.0]))
    phi_l = np.interp(uy, [-0.9, 0.9], [110.0, 180.0])
    phi = np.radians(np.where(side < 0, phi_r, phi_l) + rng.normal(0, 6.0, n))
    z_rel = z_eye + 0.014 + rng.normal(0, 0.004, n)
    own = roots[:, 2] < z_rel + 0.012                        # low roots simply hang from where they are
    thick = np.where(side < 0, 0.030, 0.018)
    off = 0.004 + thick * layer
    q = np.sqrt(np.clip(1.0 - ((z_rel - c[2]) / r[2]) ** 2, 0.05, 1.0))
    rho = q / np.sqrt((np.sin(phi) / r[0]) ** 2 + (np.cos(phi) / r[1]) ** 2)
    rel = np.stack([c[0] + rho * np.sin(phi), c[1] - rho * np.cos(phi), z_rel], axis=1)
    rel[own] = roots[own]
    b_un = (rel - c) / r
    b_un /= np.linalg.norm(b_un, axis=1, keepdims=True)
    # ---- over the skull: slerp between the root direction and the release direction
    K1, K2 = 12, 16
    t1 = np.linspace(0, 1, K1)[None, :, None]
    om = np.arccos(np.clip((un * b_un).sum(1), -1, 1))[:, None, None]
    so = np.maximum(np.sin(om), 1e-4)
    d = (np.sin((1 - t1) * om) * un[:, None, :] + np.sin(t1 * om) * b_un[:, None, :]) / so
    d = np.where(om < 1e-3, un[:, None, :], d)
    d /= np.linalg.norm(d, axis=2, keepdims=True)
    lift = 0.0025 + (off[:, None, None] - 0.0025) * (t1 * t1 * (3 - 2 * t1))
    head = c[None, None, :] + d * (r[None, None, :] + lift)
    # ---- hanging part
    z_end = z_eye - np.where(side < 0, 0.140, 0.122) + rng.normal(0, 0.006, n) + 0.014 * (1 - layer)
    start = head[:, -1]
    hz = start[:, :2] - c[None, :2]
    hz /= np.maximum(np.linalg.norm(hz, axis=1, keepdims=True), 1e-6)
    t2 = np.linspace(0, 1, K2 + 1)[None, 1:, None]
    flare = np.where(side < 0, 0.040, 0.022)[:, None, None] * (0.4 + 0.6 * layer[:, None, None])
    hang = np.empty((n, K2, 3))
    hang[:, :, :2] = start[:, None, :2] + hz[:, None, :] * (flare * t2 ** 1.6)
    hang[:, :, 2:] = start[:, None, 2:] + (z_end[:, None, None] - start[:, None, 2:]) * t2
    path = np.concatenate([head, hang], axis=1)
    # ---- waves + flipped ends on the hanging part (phase coherent between neighbours)
    seg = np.linalg.norm(np.diff(path, axis=1), axis=2)
    s_all = np.concatenate([np.zeros((n, 1)), np.cumsum(seg, axis=1)], axis=1)
    s_h = np.clip(s_all - s_all[:, K1 - 1:K1], 0.0, None)
    L_h = np.maximum(s_h[:, -1:], 1e-6)
    phase = 4.0 * phi + rng.normal(0, 0.45, n)
    tang = np.stack([-hz[:, 1], hz[:, 0]], axis=1)
    amp = 0.0080 * _smooth(s_h, 0.0, 0.05) * rng.uniform(0.6, 1.6, (n, 1))
    wv = np.sin(2 * math.pi * s_h / 0.058 + phase[:, None])
    wc = np.cos(2 * math.pi * s_h / 0.058 + phase[:, None])
    path[:, :, :2] += hz[:, None, :] * (amp * wv)[:, :, None] + tang[:, None, :] * (amp * 0.7 * wc)[:, :, None]
    flip = _smooth(s_h / L_h, 0.78, 1.0) ** 2
    path[:, :, :2] += hz[:, None, :] * (0.014 * flip)[:, :, None]
    path[:, :, 2] += 0.007 * flip
    # ---- resample every strand to K points, uniform in arc length
    seg = np.linalg.norm(np.diff(path, axis=1), axis=2)
    s_all = np.concatenate([np.zeros((n, 1)), np.cumsum(seg, axis=1)], axis=1)
    out = np.empty((n, K, 3))
    tt = np.linspace(0, 1, K)
    for i in range(n):
        si = s_all[i]
        for k in range(3):
            out[i, :, k] = np.interp(tt * si[-1], si, path[i, :, k])
    return out, side


def children(guides, rng):
    n = len(guides)
    g = np.repeat(guides, CHILDREN, axis=0)
    m = len(g)
    t = np.linspace(0, 1, K)[None, :, None]
    off = rng.normal(0, 1, (m, 1, 3)) * (0.0031 * (1 - 0.6 * t))          # clump: tighter at the tips
    frizz = np.cumsum(rng.normal(0, 0.00009, (m, K, 3)), axis=1)
    stray = (rng.random(m) < 0.03)[:, None, None]
    fly = np.cumsum(rng.normal(0, 0.0011, (m, K, 3)), axis=1) * stray
    out = g + off + frizz + fly
    out[:, 0] = g[:, 0] + off[:, 0] * 0.6
    return out


def hair_material():
    mat = bpy.data.materials.new("Hair_Blonde")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    h = nt.nodes.new("ShaderNodeBsdfHairPrincipled")
    h.parametrization = 'MELANIN'
    info = nt.nodes.new("ShaderNodeHairInfo")
    ramp = nt.nodes.new("ShaderNodeValToRGB")          # melanin along the strand
    e = ramp.color_ramp.elements
    e[0].position = 0.0; e[0].color = (0.74, 0.74, 0.74, 1)
    e[1].position = 0.20; e[1].color = (0.045, 0.045, 0.045, 1)
    mid = e.new(0.085); mid.color = (0.30, 0.30, 0.30, 1)
    nt.links.new(info.outputs["Intercept"], ramp.inputs[0])
    # a few darker / more golden strands
    rnd = nt.nodes.new("ShaderNodeMapRange")
    rnd.inputs["To Min"].default_value = 0.55; rnd.inputs["To Max"].default_value = 2.1
    nt.links.new(info.outputs["Random"], rnd.inputs["Value"])
    mul = nt.nodes.new("ShaderNodeMath"); mul.operation = 'MULTIPLY'
    nt.links.new(ramp.outputs["Color"], mul.inputs[0]); nt.links.new(rnd.outputs["Result"], mul.inputs[1])
    nt.links.new(mul.outputs[0], h.inputs["Melanin"])
    for k, val in (("Melanin Redness", 0.34), ("Roughness", 0.32), ("Radial Roughness", 0.42), ("Coat", 0.05),
                   ("Random Roughness", 0.2), ("Random Color", 0.12)):
        if k in h.inputs:
            h.inputs[k].default_value = val
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(h.outputs[0], out.inputs["Surface"])
    return mat


def make_curves(name, strands, mat, col, root_r=0.00008, tip_r=0.00003):
    n, k, _ = strands.shape
    cu = bpy.data.hair_curves.new(name)
    cu.add_curves([k] * n)
    cu.points.foreach_set("position", strands.reshape(-1).astype(np.float32))
    rad = np.tile(np.linspace(root_r, tip_r, k, dtype=np.float32), n)
    attr = cu.attributes.get("radius") or cu.attributes.new("radius", 'FLOAT', 'POINT')
    attr.data.foreach_set("value", rad)
    cu.materials.append(mat)
    ob = bpy.data.objects.new(name, cu)
    blcore.link(ob, col)
    return ob


def build(base, fit, body, rig, col):
    rng = np.random.default_rng(7)
    c, r, z_eye = skull(fit, base)
    v = fit["verts"][:mhlib.N_BODY]
    ear = v[(np.abs(v[:, 0]) > r[0] * 0.97) & (v[:, 2] < z_eye + 0.012) & (v[:, 2] > z_eye - 0.05)]
    ear_y = float(ear[:, 1].mean()) if len(ear) else float(c[1] + 0.02)
    roots, _, _ = scalp_roots(fit, base, c, r, N_GUIDES, rng)
    guides, side = comb(roots, c, r, z_eye, rng, ear_y)
    strands = children(guides, rng)
    ob = make_curves("Hair", strands, hair_material(), col)
    print("hair strands", len(strands), "skull", np.round(c, 3), np.round(r, 3), "ear_y", round(ear_y, 3))
    return {"head_objects": [ob]}
