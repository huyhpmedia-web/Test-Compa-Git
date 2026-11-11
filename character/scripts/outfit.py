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


def garment_mask(base, v, weights, joints):
    n = mhlib.N_BODY
    arm_w = np.zeros(n)
    for bname, pairs in weights.items():
        if bname.startswith(ARM_BONES):
            for vi, w in pairs:
                if vi < n:
                    arm_w[vi] += w
    is_arm = arm_w > 0.5
    x, y, z = v[:n, 0], v[:n, 1], v[:n, 2]
    chest = (np.abs(x) < 0.13) & (z > 1.12) & (z < 1.30) & (y < 0)
    z_apex = float(z[chest][np.argmin(y[chest])])
    z_hem = z_apex - 0.082
    # wide square neckline: lower in front, a little higher at the back
    front = np.clip((0.02 - y) / 0.05, 0.0, 1.0)
    z_neck = (z_apex + 0.072 + 0.018 * (np.abs(x) / 0.125) ** 2) * front + (z_apex + 0.135) * (1 - front)
    open_neck = (np.abs(x) < 0.122) & (z > z_neck)
    torso = (~is_arm) & (z > z_hem) & (z < 1.40) & (~open_neck)
    sleeve = np.zeros(n, dtype=bool)
    for side in ("l", "r"):
        sh, el = joints[f"joint-{side}-shoulder"], joints[f"joint-{side}-elbow"]
        axis = (el - sh) / np.linalg.norm(el - sh)
        along = (v[:n] - sh) @ axis
        sgn = 1.0 if side == "l" else -1.0
        sleeve |= is_arm & (along < 0.095) & (x * sgn > 0)
    return torso | sleeve, z_apex, z_hem


def build(base, fit, body, rig, col):
    v = fit["verts"]
    bones, weights = mhlib.load_rig(base, v)
    joints = mhlib.joint_positions(base, v)
    mask, z_apex, z_hem = garment_mask(base, v, weights, joints)
    fidx = [i for i in base.body_faces() if all(mask[j] for j in base.faces[i])]
    used = sorted({j for i in fidx for j in base.faces[i]})
    remap = {j: k for k, j in enumerate(used)}
    used = np.array(used)
    nrm = np.empty(len(body.data.vertices) * 3)
    body.data.vertices.foreach_get("normal", nrm)
    nrm = nrm.reshape(-1, 3)[used]
    p0 = v[used]
    P = p0 + nrm * D_MIN
    faces = [[remap[j] for j in base.faces[i]] for i in fidx]
    # umbrella smoothing over the bust so the cloth bridges the cleavage
    nb = [set() for _ in used]
    for f in faces:
        for a in range(4):
            nb[f[a]].add(f[(a + 1) % 4]); nb[f[(a + 1) % 4]].add(f[a])
    bust = (p0[:, 2] > z_apex - 0.07) & (p0[:, 2] < z_apex + 0.085) & (p0[:, 1] < -0.02) & (np.abs(p0[:, 0]) < 0.125)
    idx = np.where(bust)[0]
    Ps = P.copy()
    for _ in range(40):
        new = Ps.copy()
        for i in idx:
            new[i] = 0.5 * Ps[i] + 0.5 * np.mean(Ps[list(nb[i])], axis=0)
        Ps = new
    d = np.maximum(D_MIN, ((Ps - p0) * nrm).sum(1))
    P = p0 + nrm * d[:, None]
    me = blcore.mesh_from_arrays("Top_Mesh", P, faces)
    top = bpy.data.objects.new("Top", me)
    blcore.link(top, col)
    for bname, pairs in weights.items():
        sel = [(remap[vi], w) for vi, w in pairs if vi in remap and w > 0]
        if sel:
            vg = top.vertex_groups.new(name=bname)
            for k, w in sel:
                vg.add([k], w, 'REPLACE')
    blcore.bind(top, rig)
    sub = top.modifiers.new("Subdiv", 'SUBSURF'); sub.levels, sub.render_levels = 1, 2
    sol = top.modifiers.new("Thickness", 'SOLIDIFY'); sol.thickness = 0.0016; sol.offset = 1.0
    me.materials.append(fabric_material())
    print("top faces", len(faces), "apex z", round(z_apex, 3), "hem z", round(z_hem, 3))
    return {"top": top, "z_apex": z_apex}
