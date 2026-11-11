"""Outfit, rest-pose part: fitted white cropped tee with a wide square neckline.

The garment is cut out of the body surface (so it inherits the body's skin weights and
follows the rig), pushed out along the normals and smoothed across the bust so the
fabric spans instead of hugging every valley.
"""
import bpy
import numpy as np

import blcore
import mhlib

ARM_BONES = ("upperarm", "lowerarm", "wrist", "finger", "metacarpal")
D_MIN = 0.0030


def fabric_material():
    mat = bpy.data.materials.new("Fabric_White_Jersey")
    mat.use_nodes = True
    nt = mat.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.86, 0.84, 0.83, 1)
    b.inputs["Roughness"].default_value = 0.78
    if "Sheen Weight" in b.inputs:
        b.inputs["Sheen Weight"].default_value = 0.35
    b.inputs["Subsurface Weight"].default_value = 0.08
    b.inputs["Subsurface Radius"].default_value = (0.4, 0.3, 0.3)
    b.inputs["Subsurface Scale"].default_value = 0.002
    tc = nt.nodes.new("ShaderNodeTexCoord")
    wave = nt.nodes.new("ShaderNodeTexNoise")
    wave.inputs["Scale"].default_value = 2600.0
    nt.links.new(tc.outputs["Object"], wave.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.12
    bump.inputs["Distance"].default_value = 0.0003
    nt.links.new(wave.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return mat


def _field(co, is_arm, joints):
    """Signed 'inside the garment' value per vertex (> 0 inside), plus bust apex / hem heights."""
    x, y, z = co[:, 0], co[:, 1], co[:, 2]
    chest = (np.abs(x) < 0.13) & (z > 1.10) & (z < 1.32) & (y < 0) & (~is_arm)
    z_apex = float(z[chest][np.argmin(y[chest])])
    z_hem = z_apex - 0.085
    # wide square neckline: low in front (just above the bust), a little higher at the back
    front = np.clip((0.02 - y) / 0.05, 0.0, 1.0)
    z_neck = (z_apex + 0.030 + 0.024 * np.clip(np.abs(x) / 0.125, 0, 1) ** 2) * front + (z_apex + 0.115) * (1 - front)
    g_neck = np.maximum(z_neck - z, np.abs(x) - 0.125)
    f = np.minimum(np.minimum(z - z_hem, g_neck), 1.40 - z)
    for side in ("l", "r"):
        sh, el = joints[f"joint-{side}-shoulder"], joints[f"joint-{side}-elbow"]
        axis = (el - sh) / np.linalg.norm(el - sh)
        along = (co - sh) @ axis
        sgn = 1.0 if side == "l" else -1.0
        arm = is_arm & (x * sgn > 0)
        f[arm] = 0.098 - along[arm]
    return f, z_apex, z_hem


def build(base, fit, body, rig, col):
    """Cut the garment out of the *subdivided* rest-pose body so its rim is smooth."""
    from scipy import sparse
    joints = mhlib.joint_positions(base, fit["verts"])
    sub = body.modifiers["Subdiv"]
    old = sub.levels
    sub.levels = 2
    bpy.context.view_layer.update()
    ev = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    me = ev.to_mesh()
    n = len(me.vertices)
    co = np.empty(n * 3); me.vertices.foreach_get("co", co); co = co.reshape(-1, 3)
    nrm = np.empty(n * 3); me.vertices.foreach_get("normal", nrm); nrm = nrm.reshape(-1, 3)
    faces = np.empty(len(me.polygons) * 4, dtype=np.int32); me.polygons.foreach_get("vertices", faces)
    faces = faces.reshape(-1, 4)
    cand = np.where((co[:, 2] > 0.98) & (co[:, 2] < 1.43))[0]
    names = [g.name for g in body.vertex_groups]
    arm_idx = {i for i, nm in enumerate(names) if nm.startswith(ARM_BONES)}
    arm_w = np.zeros(n)
    vw = {}
    for i in cand:
        gs = [(g.group, g.weight) for g in me.vertices[i].groups]
        vw[int(i)] = gs
        arm_w[i] = sum(w for g, w in gs if g in arm_idx)
    field, z_apex, z_hem = _field(co, arm_w > 0.5, joints)
    mask = np.zeros(n, dtype=bool)
    mask[cand] = field[cand] > 0
    fsel = faces[mask[faces].all(axis=1)]
    used = np.unique(fsel)
    remap = -np.ones(n, dtype=np.int64); remap[used] = np.arange(len(used))
    p0 = co[used].copy()
    # rim vertices slide along their outgoing edges onto the exact cut line
    acc = np.zeros((n, 3)); cnt = np.zeros(n)
    for a in range(4):
        u, w_ = faces[:, a], faces[:, (a + 1) % 4]
        for s_, t_ in ((u, w_), (w_, u)):
            sel = mask[s_] & (~mask[t_]) & (remap[s_] >= 0)
            ss, tt = s_[sel], t_[sel]
            t = np.clip(field[ss] / np.maximum(field[ss] - field[tt], 1e-9), 0.0, 0.95)
            np.add.at(acc, ss, co[ss] + (co[tt] - co[ss]) * t[:, None]); np.add.at(cnt, ss, 1.0)
    rim = cnt[used] > 0
    p0[rim] = acc[used][rim] / cnt[used][rim][:, None]
    nv = nrm[used]
    P = p0 + nv * D_MIN
    f2 = remap[fsel]
    # umbrella smoothing over the bust so the cloth spans the cleavage instead of hugging it
    ii = np.concatenate([f2[:, a] for a in range(4)]); jj = np.concatenate([f2[:, (a + 1) % 4] for a in range(4)])
    A = sparse.coo_matrix((np.ones(len(ii) * 2), (np.concatenate([ii, jj]), np.concatenate([jj, ii]))),
                          shape=(len(used), len(used))).tocsr()
    A.data[:] = 1.0
    deg = np.maximum(np.asarray(A.sum(axis=1)).ravel(), 1.0)
    bust = (p0[:, 2] > z_apex - 0.075) & (p0[:, 2] < z_apex + 0.09) & (p0[:, 1] < -0.02) & (np.abs(p0[:, 0]) < 0.125)
    wm = bust.astype(np.float64)
    for _ in range(40):
        wm = 0.5 * wm + 0.5 * (A @ wm) / deg
    # 1) iron small body detail out of the surface the cloth is built on
    base_s = p0.copy()
    for _ in range(70):
        avg = (A @ base_s) / deg[:, None]
        base_s[bust] = 0.5 * base_s[bust] + 0.5 * avg[bust]
    d0 = D_MIN + 0.009 * wm                                                      # padded like a lined cup
    # offset along *smoothed* normals: the raw body normals fan out around small detail and
    # would print it straight back into the cloth
    ns = nv.copy()
    for _ in range(80):
        avg = (A @ ns) / deg[:, None]
        ns[bust] = 0.5 * ns[bust] + 0.5 * avg[bust]
    ns /= np.maximum(np.linalg.norm(ns, axis=1, keepdims=True), 1e-9)
    nv = ns
    # 2) let the cloth span the cleavage
    Ps = base_s + nv * d0[:, None]
    for _ in range(1500):
        avg = (A @ Ps) / deg[:, None]
        Ps[bust] = 0.5 * Ps[bust] + 0.5 * avg[bust]
    d = np.maximum(d0, ((Ps - base_s) * nv).sum(1))
    P = base_s + nv * d[:, None]
    P = p0 + nv * np.maximum(0.0018, ((P - p0) * nv).sum(1))[:, None]             # always clear of the real skin
    # even out the cut edge: average every rim vertex with its two rim neighbours
    e = np.sort(np.concatenate([np.stack([f2[:, a], f2[:, (a + 1) % 4]], axis=1) for a in range(4)]), axis=1)
    ue, cnt_e = np.unique(e, axis=0, return_counts=True)
    be = ue[cnt_e == 1]
    for _ in range(12):
        acc_r = np.zeros_like(P); n_r = np.zeros(len(P))
        np.add.at(acc_r, be[:, 0], P[be[:, 1]]); np.add.at(acc_r, be[:, 1], P[be[:, 0]])
        np.add.at(n_r, be[:, 0], 1.0); np.add.at(n_r, be[:, 1], 1.0)
        r_ = n_r > 0
        P[r_] = 0.5 * P[r_] + 0.5 * acc_r[r_] / n_r[r_][:, None]
    gm = blcore.mesh_from_arrays("Top_Mesh", P, f2.tolist())
    top = bpy.data.objects.new("Top", gm)
    blcore.link(top, col)
    groups = {}
    for k, vi in enumerate(used):
        for g, w in vw.get(int(vi), ()):
            if w > 0:
                groups.setdefault(g, []).append((k, w))
    for g, pairs in groups.items():
        vg = top.vertex_groups.new(name=names[g])
        for k, w in pairs:
            vg.add([k], w, 'REPLACE')
    ev.to_mesh_clear()
    sub.levels = old
    blcore.bind(top, rig)
    sol = top.modifiers.new("Thickness", 'SOLIDIFY'); sol.thickness = 0.0016; sol.offset = 1.0
    gm.materials.append(fabric_material())
    top["z_apex"] = z_apex
    print("top faces", len(f2), "apex z", round(z_apex, 3), "hem z", round(z_hem, 3))
    return {"top": top, "z_apex": z_apex}
