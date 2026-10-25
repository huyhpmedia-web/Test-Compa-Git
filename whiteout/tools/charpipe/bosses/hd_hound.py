"""RIME HOUND (HD): Tripo H3.1 mesh -> assets/enemies/hound_hd.glb  (skinned; 19.9k tris)
Armature with the bone names hound_model.gd drives: body, neck, head, jaw, fl/fr/hl/hr_sh|kn|pw, tail1..3. Weights come from the distance to
bone capsules (soft blend near the joints) so the fur never tears. Two small glowing eye meshes are skinned to the head.
Run: venv/bin/python tools/charpipe/bosses/hd_hound.py
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hd_common import *

LENGTH_H = 0.89

# joints (x is mirrored for the right side; front of the dog is -Y). (y, z)
BONES = {}


def build_bones():
    B = []   # (name, parent, head(x,y,z), tail, radius)

    def add(n, p, h, t, r):
        B.append((n, p, Vector(h), Vector(t), r))
    add("body", None, (0, 0.40, 0.60), (0, -0.30, 0.64), 0.19)
    add("neck", "body", (0, -0.30, 0.64), (0, -0.46, 0.58), 0.10)
    add("head", "neck", (0, -0.46, 0.58), (0, -0.62, 0.50), 0.11)
    add("jaw", "head", (0, -0.50, 0.47), (0, -0.64, 0.41), 0.045)
    for sd, sx in (("l", -1), ("r", 1)):
        add("f%s_sh" % sd, "body", (sx * 0.095, -0.26, 0.58), (sx * 0.105, -0.31, 0.30), 0.075)
        add("f%s_kn" % sd, "f%s_sh" % sd, (sx * 0.105, -0.31, 0.30), (sx * 0.13, -0.35, 0.09), 0.055)
        add("f%s_pw" % sd, "f%s_kn" % sd, (sx * 0.13, -0.35, 0.09), (sx * 0.15, -0.41, 0.0), 0.05)
        add("h%s_sh" % sd, "body", (sx * 0.10, 0.20, 0.55), (sx * 0.12, 0.42, 0.27), 0.10)
        add("h%s_kn" % sd, "h%s_sh" % sd, (sx * 0.12, 0.42, 0.27), (sx * 0.14, 0.39, 0.10), 0.055)
        add("h%s_pw" % sd, "h%s_kn" % sd, (sx * 0.14, 0.39, 0.10), (sx * 0.15, 0.33, 0.0), 0.05)
    add("tail1", "body", (0, 0.40, 0.62), (0, 0.55, 0.50), 0.08)
    add("tail2", "tail1", (0, 0.55, 0.50), (0, 0.70, 0.38), 0.075)
    add("tail3", "tail2", (0, 0.70, 0.38), (0, 0.88, 0.27), 0.07)
    return B


def seg_dist(P, a, b):
    ab = b - a
    t = np.clip(((P - a) @ ab) / (ab @ ab), 0.0, 1.0)
    return np.linalg.norm(P - (a + t[:, None] * ab), axis=1)


def main():
    o = load_raw("hound")
    v = verts(o)
    orient(o, LENGTH_H / (v[:, 2].max() - v[:, 2].min()), center="base")
    downscale_images(2048)
    tune_pbr(o, blood=0.2, ice=0.9, rename="flesh_hd")
    o.name = "Hound"
    v = verts(o)
    print("bbox", v.min(0), v.max(0))
    B = build_bones()
    names = [b[0] for b in B]
    D = np.stack([seg_dist(v.astype(np.float64), np.array(b[2]), np.array(b[3])) / b[4] for b in B], axis=1)
    # the head capsule must not swallow the whole front: the neck/head only own vertices ahead of y=-0.36
    D[:, names.index("head")] += np.where(v[:, 1] > -0.40, 5.0, 0.0)
    D[:, names.index("jaw")] += np.where((v[:, 1] > -0.47) | (v[:, 2] > 0.50), 5.0, 0.0)
    D[:, names.index("neck")] += np.where((v[:, 1] > -0.18) | (v[:, 1] < -0.56), 3.0, 0.0)
    D[:, 0] += 3.0 * np.clip((-0.28 - v[:, 1]) / 0.12, 0, 1)      # the neck zone belongs to the neck, not the torso
    D[:, names.index("neck")] -= 0.6
    D[:, names.index("neck")] += 4.0 * np.clip((0.54 - v[:, 2]) / 0.08, 0, 1)   # chest below the throat stays with the torso
    W = np.exp(-(D - D.min(1, keepdims=True)) * 5.0)
    # keep the 4 strongest influences
    idx = np.argsort(-W, axis=1)[:, :4]
    Wk = np.zeros_like(W)
    r = np.arange(len(v))[:, None]
    Wk[r, idx] = W[r, idx]
    Wk /= Wk.sum(1, keepdims=True)
    if os.environ.get("HD_PREVIEW") == "1":
        lab = Wk.argmax(1)
        for view in ("side", "front", "top"):
            print(preview(v, "hound_w_" + view, view=view, labels=lab, px=1000, splat=3, grid=0.1))
        print(dict(zip(names, np.bincount(lab, minlength=len(names)))))
        return
    # armature
    arm_d = bpy.data.armatures.new("HoundArm")
    arm = bpy.data.objects.new("HoundRig", arm_d)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = {}
    for n, p, h, t, rad in B:
        b = arm_d.edit_bones.new(n)
        b.head, b.tail = h, t
        if p:
            b.parent = eb[p]
        eb[n] = b
    bpy.ops.object.mode_set(mode="OBJECT")
    # weights
    for j, n in enumerate(names):
        vg = o.vertex_groups.new(name=n)
        sel = np.where(Wk[:, j] > 0.01)[0]
        for i in sel:
            vg.add([int(i)], float(Wk[i, j]), "REPLACE")
    parent_keep(o, arm)
    md = o.modifiers.new("Armature", "ARMATURE")
    md.object = arm
    # glowing eyes (skinned to the head bone)
    em = glow_material("glow_eye", (0.55, 0.95, 1.0), 8.0, 1.0)
    objs = [arm, o]
    for sx in (-1, 1):
        ex, ez = sx * 0.05, 0.555
        ey = front_y(v, ex, ez, 0.03)
        e = blob("glow_eye_%s" % ("L" if sx < 0 else "R"), (ex, ey + 0.004, ez), (0.016, 0.01, 0.011), em, seg=10, rings=6)
        vg = e.vertex_groups.new(name="head")
        vg.add(list(range(len(e.data.vertices))), 1.0, "REPLACE")
        parent_keep(e, arm)
        m2 = e.modifiers.new("Armature", "ARMATURE")
        m2.object = arm
        objs.append(e)
        print("eye", sx, ey)
    export(os.path.join(OUT_DIR, "hound_hd.glb"), [arm])


main()
