"""Hair: side-parted wavy chin-length bob as a Curves object (dark roots -> pale blonde).

Strands are combed away from the part line over an ellipsoid fitted to the skull, then
hang freely with waves and flipped ends.  Guides are multiplied into clumped children.
"""
import math

import bpy
import numpy as np

import blcore
import mhlib

N_GUIDES = 1700
CHILDREN = 34
K = 22                       # points per strand
PART_ANGLE = math.radians(24.0)   # part sits on her left (towards +X) of the top of the head


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
    """Integrate guide strands.  Returns (n, K, 3)."""
    n = len(roots)
    # part line on the unit sphere: from the front hairline back to the crown
    pa = np.array([math.sin(PART_ANGLE) * 0.85, -0.78, 0.50]); pa /= np.linalg.norm(pa)
    pb = np.array([math.sin(PART_ANGLE) * 0.55, 0.38, 0.92]); pb /= np.linalg.norm(pb)
    seg = np.linspace(0, 1, 24)[:, None]
    part = pa[None] * (1 - seg) + pb[None] * seg
    part /= np.linalg.norm(part, axis=1, keepdims=True)

    layer = rng.random(n)                                   # 0 = inner, 1 = outer layer
    u0 = (roots - c) / r
    u0n = u0 / np.linalg.norm(u0, axis=1, keepdims=True)
    side = np.where(u0n[:, 0] < np.interp(u0n[:, 1], [-0.78, 0.38], [pa[0], pb[0]]), -1.0, 1.0)   # -1: her right
    thick = np.where(side < 0, 0.036, 0.020)                # hair body is fuller on her right
    z_end = z_eye - np.where(side < 0, 0.112, 0.100) + rng.normal(0, 0.006, n) + 0.012 * (1 - layer)
    step = 0.0105
    p = roots.copy()
    out = np.zeros((n, K, 3))
    out[:, 0] = p
    free = np.zeros(n, dtype=bool)
    phase = 5.0 * np.arctan2(u0n[:, 0], -u0n[:, 1]) + rng.normal(0, 0.5, n)
    done_len = np.zeros(n)
    for k in range(1, K):
        u = (p - c) / r
        rad = np.linalg.norm(u, axis=1, keepdims=True)
        un = u / rad
        nrm = un / r
        nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
        # away from the nearest point of the part line
        d2 = ((un[:, None, :] - part[None]) ** 2).sum(2)
        q = part[d2.argmin(1)]
        away = (un - q) * r
        away -= nrm * (away * nrm).sum(1, keepdims=True)
        away /= np.maximum(np.linalg.norm(away, axis=1, keepdims=True), 1e-6)
        grav = np.array([0.0, 0.0, -1.0])[None] - nrm * (-nrm[:, 2:3])
        gl = np.linalg.norm(grav, axis=1, keepdims=True)
        grav /= np.maximum(gl, 1e-6)
        g = np.clip(gl[:, 0] * 1.25 + 0.03 * k, 0.0, 1.0)[:, None]
        d = away * (1 - g) + grav * g
        # sweep slightly backwards on the top so the fringe opens away from the face
        d[:, 1] += 0.18 * (un[:, 2] > 0.5)
        frontal = un[:, 1] < -0.05
        d[frontal, 1] = np.maximum(d[frontal, 1], 0.30)
        d /= np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-6)
        newly = (~free) & ((un[:, 2] < -0.02) | (p[:, 2] < z_eye - 0.005))
        free |= newly
        # on the head: step along the surface, then snap to the offset ellipsoid
        lift = 0.004 + thick * layer * _smooth(done_len, 0.0, 0.07)
        pn = p + d * step
        un2 = (pn - c) / r
        un2 /= np.linalg.norm(un2, axis=1, keepdims=True)
        on = c + un2 * (r + lift[:, None])
        # free hang: straight down with a gentle outward flare
        horiz = np.stack([p[:, 0] - c[0], p[:, 1] - c[1], np.zeros(n)], axis=1)
        horiz /= np.maximum(np.linalg.norm(horiz, axis=1, keepdims=True), 1e-6)
        fall = np.array([0.0, 0.0, -1.0])[None] + horiz * 0.10
        fall /= np.linalg.norm(fall, axis=1, keepdims=True)
        fr = p + fall * step
        p = np.where(free[:, None], fr, on)
        # curtain: below the hairline the hair may not come in front of this line
        ylim = np.where(side < 0, c[1] - 0.052, c[1] - 0.012) - 0.02 * layer
        low = _smooth(z_eye + 0.05 - p[:, 2], 0.0, 0.03)
        p[:, 1] = np.where(p[:, 1] < ylim, p[:, 1] + (ylim - p[:, 1]) * low, p[:, 1])
        # stop growing below the bob line
        stop = p[:, 2] < z_end
        p[stop] = out[stop, k - 1] + (p[stop] - out[stop, k - 1]) * 0.02
        done_len += step * (~stop)
        out[:, k] = p
    # tuck behind the ears: strands hanging right over the ear column move behind (or in front on her right)
    for kk in range(K):
        q = out[:, kk]
        near = _smooth(z_eye + 0.01 - q[:, 2], 0.0, 0.03) * (np.abs(q[:, 0]) > r[0] * 0.80)
        dy = q[:, 1] - ear_y
        left_side = q[:, 0] > 0
        push_back = np.where(left_side, dy < 0.022, (dy < 0.020) & (dy > -0.006))
        push_fwd = (~left_side) & (dy <= -0.006) & (dy > -0.030)
        q[:, 1] += near * (push_back * (0.024 - dy) * 0.9 - push_fwd * (dy + 0.032) * 0.5)
    # waves + flipped ends on the lower part of every strand
    s = np.concatenate([np.zeros((n, 1)), np.cumsum(np.linalg.norm(np.diff(out, axis=1), axis=2), axis=1)], axis=1)
    L = s[:, -1:]
    horiz = out[:, :, :2] - c[None, None, :2]
    horiz /= np.maximum(np.linalg.norm(horiz, axis=2, keepdims=True), 1e-6)
    tang = np.stack([-horiz[:, :, 1], horiz[:, :, 0]], axis=2)
    amp = 0.0060 * _smooth(s, 0.03, 0.10)
    wave = np.sin(2 * math.pi * s / 0.062 + phase[:, None])
    out[:, :, :2] += horiz * (amp * wave)[:, :, None] + tang * (amp * 0.6 * np.cos(2 * math.pi * s / 0.062 + phase[:, None]))[:, :, None]
    flip = _smooth(s / np.maximum(L, 1e-6), 0.80, 1.0) ** 2
    out[:, :, :2] += horiz * (0.010 * flip)[:, :, None]
    out[:, :, 2] += 0.006 * flip
    return out, side


def children(guides, rng):
    n = len(guides)
    g = np.repeat(guides, CHILDREN, axis=0)
    m = len(g)
    t = np.linspace(0, 1, K)[None, :, None]
    off = rng.normal(0, 1, (m, 1, 3)) * (0.0032 * (1 - 0.6 * t))          # clump: tighter at the tips
    frizz = np.cumsum(rng.normal(0, 0.00013, (m, K, 3)), axis=1)
    stray = (rng.random(m) < 0.015)[:, None, None]
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
    e[1].position = 0.30; e[1].color = (0.115, 0.115, 0.115, 1)
    mid = e.new(0.13); mid.color = (0.42, 0.42, 0.42, 1)
    nt.links.new(info.outputs["Intercept"], ramp.inputs[0])
    # a few darker / more golden strands
    rnd = nt.nodes.new("ShaderNodeMapRange")
    rnd.inputs["To Min"].default_value = 0.75; rnd.inputs["To Max"].default_value = 1.55
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


def make_curves(name, strands, mat, col, root_r=0.000055, tip_r=0.000022):
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
