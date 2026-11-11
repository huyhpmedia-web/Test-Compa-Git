"""Stage 3 -- skin albedo: project the three reference photos into the MakeHuman UV atlas.

For every texel the surface position/normal is baked (Cycles), projected into each photo
with the fitted cameras, tested for visibility and for 'is this pixel skin?', and the
photos are blended by viewing angle.  Hidden texels are filled from the mirrored side,
then from the average skin tone.

Output: textures/skin_albedo.png (+ build/skin_cover.png coverage map)
"""
import os
import sys

import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402
import blcore  # noqa: E402
import charlib  # noqa: E402
import fitlib  # noqa: E402
import mhlib  # noqa: E402

ROOT = charlib.ROOT
B = charlib.B
SIZE = int(os.environ.get("ATLAS", "4096"))
EYE_RADIUS = 0.0122
EYE_TEX = 512
VIS_DIV = 2                      # visibility is ray-cast on a SIZE/VIS_DIV grid
DELIGHT = float(os.environ.get("DELIGHT", "0.5"))
Z_CUT = [0.0, 1.0]               # set in main(): projection fades out below the jaw
PHOTOS = {"closeup": ("ref_closeup.jpg", "seg_3.npy", 1.0),
          "profile": ("ref_profile.jpg", "seg_2.npy", 0.8),
          "front": ("ref_front.jpg", "seg_1.npy", 0.5)}


def bake_geometry(body, size, bounds=None):
    """Per-texel world position, normal and validity via a Cycles EMIT bake."""
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 1
    scene.cycles.use_denoising = False
    co = blcore.evaluated_coords(body)
    lo, hi = co.min(0) - 0.01, co.max(0) + 0.01
    out = {}
    for what in ("position", "normal"):
        mat = bpy.data.materials.new("Bake_" + what)
        mat.use_nodes = True
        nt = mat.node_tree
        nt.nodes.clear()
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        if what == "position":
            sub = nt.nodes.new("ShaderNodeVectorMath"); sub.operation = 'SUBTRACT'
            sub.inputs[1].default_value = tuple(lo)
            div = nt.nodes.new("ShaderNodeVectorMath"); div.operation = 'DIVIDE'
            div.inputs[1].default_value = tuple(hi - lo)
            nt.links.new(geo.outputs["Position"], sub.inputs[0])
            nt.links.new(sub.outputs[0], div.inputs[0])
            vec = div.outputs[0]
        else:
            mul = nt.nodes.new("ShaderNodeVectorMath"); mul.operation = 'MULTIPLY_ADD'
            mul.inputs[1].default_value = (0.5, 0.5, 0.5); mul.inputs[2].default_value = (0.5, 0.5, 0.5)
            nt.links.new(geo.outputs["Normal"], mul.inputs[0])
            vec = mul.outputs[0]
        em = nt.nodes.new("ShaderNodeEmission")
        nt.links.new(vec, em.inputs["Color"])
        mo = nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(em.outputs[0], mo.inputs["Surface"])
        img = bpy.data.images.new("bake_" + what, size, size, alpha=True, float_buffer=True, is_data=True)
        tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = img
        nt.nodes.active = tex; tex.select = True
        body.data.materials.clear(); body.data.materials.append(mat)
        blcore.set_active(body)
        bpy.ops.object.bake(type='EMIT', margin=0, use_clear=True)
        px = np.empty(size * size * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        px = px.reshape(size, size, 4)[::-1]            # row 0 = top (v = 1)
        if what == "position":
            out["pos"] = px[:, :, :3] * (hi - lo).astype(np.float32) + lo.astype(np.float32)
            out["valid"] = px[:, :, :3].max(axis=2) > 1e-5      # unbaked texels stay black
        else:
            n = px[:, :, :3] * 2.0 - 1.0
            out["nrm"] = n / np.maximum(np.linalg.norm(n, axis=2, keepdims=True), 1e-6)
        bpy.data.images.remove(img)
    body.data.materials.clear()
    return out


def visibility(bvh, pos, nrm, valid, cam_c, div):
    """1 where the texel sees the camera centre (ray-cast on a coarse grid, then upsampled)."""
    p = pos[::div, ::div]; n = nrm[::div, ::div]; ok = valid[::div, ::div]
    to_cam = cam_c[None, None, :] - p
    dist = np.linalg.norm(to_cam, axis=2)
    d = to_cam / np.maximum(dist[:, :, None], 1e-9)
    facing = ok & ((n * d).sum(2) > 0.05)
    vis = np.zeros(p.shape[:2], dtype=np.float32)
    ys, xs = np.nonzero(facing)
    for y, x in zip(ys, xs):
        o = p[y, x] + n[y, x] * 0.0008
        hit = bvh.ray_cast(Vector(o.tolist()), Vector(d[y, x].tolist()), float(dist[y, x]))
        if hit[0] is None:
            vis[y, x] = 1.0
    vis = cv2.resize(vis, (pos.shape[1], pos.shape[0]), interpolation=cv2.INTER_LINEAR)
    return vis


def sample_photo(name, cams, pos, nrm, valid, bvh):
    fn, segfn, prio = PHOTOS[name]
    img = cv2.imread(os.path.join(ROOT, "reference", fn)).astype(np.float32) / 255.0
    seg = np.load(os.path.join(B, segfn)).astype(np.float32)
    skin = seg[:, :, 2] + seg[:, :, 3]
    hair = cv2.dilate(seg[:, :, 1], np.ones((19, 19), np.uint8))
    mask = cv2.erode((skin > 0.6).astype(np.float32), np.ones((7, 7), np.uint8)) * (hair < 0.2)
    mask = cv2.GaussianBlur(mask, (0, 0), 1.5)
    cam = cams[name]
    fpx = fitlib.focal_px(charlib.LENS, charlib.RES)
    P = pos.reshape(-1, 3).astype(np.float64)
    uv, depth = fitlib.project(P, cam, fpx, charlib.RES, charlib.RES)
    mx = uv[:, 0].reshape(pos.shape[:2]).astype(np.float32)
    my = uv[:, 1].reshape(pos.shape[:2]).astype(np.float32)
    col = cv2.remap(img, mx, my, cv2.INTER_CUBIC, borderMode=cv2.BORDER_CONSTANT, borderValue=0)
    m = cv2.remap(mask, mx, my, cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=0)
    inside = (mx > 2) & (mx < charlib.RES - 3) & (my > 2) & (my < charlib.RES - 3) & (depth.reshape(mx.shape) > 0)
    cam_c = cam[:3, 3]
    view = cam_c[None, None, :] - pos
    view /= np.maximum(np.linalg.norm(view, axis=2, keepdims=True), 1e-9)
    cosv = np.clip(((nrm * view).sum(2) - 0.12) / 0.88, 0.0, 1.0)
    vis = visibility(bvh, pos, nrm, valid, cam_c, VIS_DIV)
    zc = np.clip((pos[:, :, 2] - Z_CUT[0]) / (Z_CUT[1] - Z_CUT[0]), 0.0, 1.0)
    if name == "profile":
        prio = prio * np.clip((-nrm[:, :, 0] - 0.45) / 0.3, 0.0, 1.0)
    w = (cosv ** 2) * m * vis * inside * valid * prio * zc
    return np.clip(col, 0, 1), w.astype(np.float32)


def bake_eyes(fit, base, cams, bvh):
    """Eyeball textures: what each photo shows through the eye opening of the fitted lids."""
    import bmesh
    v = fit["verts"]
    for side, grp in (("L", "helper-l-eye"), ("R", "helper-r-eye")):
        hp = v[base.group_indices(grp)]
        c = hp.mean(0)
        EYE_RADIUS = float(np.linalg.norm(hp - c, axis=1).mean())
        me = bpy.data.meshes.new("EyeBake")
        bm = bmesh.new()
        bm.loops.layers.uv.new("UVMap")
        bmesh.ops.create_uvsphere(bm, u_segments=48, v_segments=24, radius=EYE_RADIUS, calc_uvs=True)
        bm.to_mesh(me); bm.free()
        ob = bpy.data.objects.new("EyeBake", me)
        bpy.context.scene.collection.objects.link(ob)
        ob.location = c
        bpy.context.view_layer.update()
        geo = bake_geometry(ob, EYE_TEX)
        samples = []
        for k in PHOTOS:
            col, w = sample_photo(k, cams, geo["pos"], geo["nrm"], geo["valid"], bvh)
            samples.append((col, w))
        col, w = blend(samples)
        a = np.clip(w / 0.05, 0, 1)[:, :, None]
        sclera = np.array([0.70, 0.74, 0.80], np.float32)          # bgr
        out = col * a + sclera * (1 - a)
        cv2.imwrite(os.path.join(ROOT, "textures", f"eye_{side}.png"), np.clip(out * 255 + 0.5, 0, 255).astype(np.uint8))
        bpy.data.objects.remove(ob)
    print("wrote eye textures")


def blend(samples, power=1.6):
    num = np.zeros_like(samples[0][0]); den = np.zeros(samples[0][1].shape, dtype=np.float32)
    for col, w in samples:
        ww = w ** power
        num += col * ww[:, :, None]; den += ww
    return num / np.maximum(den, 1e-12)[:, :, None], np.max([w for _, w in samples], axis=0)


def main():
    fit = charlib.load_fit()
    base = mhlib.BaseMesh()
    blcore.reset_scene()
    body = blcore.make_body_object(base, fit["verts"])
    sub = body.modifiers.new("Subdiv", 'SUBSURF'); sub.levels = 2; sub.render_levels = 2
    geo = bake_geometry(body, SIZE)
    pos, nrm, valid = geo["pos"], geo["nrm"], geo["valid"]
    print("baked texels", int(valid.sum()))
    bvh = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get())
    cams = charlib.photo_cameras(fit)
    chin_z = float(fit["H"][152][2])
    Z_CUT[0], Z_CUT[1] = chin_z - 0.050, chin_z - 0.018

    os.makedirs(os.path.join(ROOT, "textures"), exist_ok=True)
    bake_eyes(fit, base, cams, bvh)
    direct = {k: sample_photo(k, cams, pos, nrm, valid, bvh) for k in PHOTOS}
    # per-photo colour gain relative to the close-up, measured where both see the surface
    ref_c, ref_w = direct["closeup"]
    for k in ("front", "profile"):
        c, w = direct[k]
        both = (ref_w > 0.15) & (w > 0.08)
        if both.sum() > 500:
            gain = np.median(ref_c[both], axis=0) / np.maximum(np.median(c[both], axis=0), 1e-3)
            gain = np.clip(gain, 0.5, 1.6)
            direct[k] = (np.clip(c * gain, 0, 1), w)
            print(k, "gain (bgr)", np.round(gain, 3), "overlap", int(both.sum()))
    col_d, w_d = blend(list(direct.values()))

    # mirrored pass: what the other half of the face looks like at the mirrored position
    mpos = pos * np.array([-1, 1, 1], dtype=np.float32)
    mnrm = nrm * np.array([-1, 1, 1], dtype=np.float32)
    mirrored = []
    for k in PHOTOS:
        c, w = sample_photo(k, cams, mpos, mnrm, valid, bvh)
        if k != "closeup" and k in direct:
            pass
        mirrored.append((c, w))
    col_m, w_m = blend(mirrored)

    # body tone: well-lit body skin of the front photo (chest / shoulders)
    ph = cv2.imread(os.path.join(ROOT, "reference", "ref_front.jpg")).astype(np.float32) / 255.0
    sg = np.load(os.path.join(B, "seg_1.npy")).astype(np.float32)
    bm = cv2.erode((sg[:, :, 2] > 0.8).astype(np.uint8), np.ones((15, 15), np.uint8)) > 0
    bm[:700] = False
    base_col = np.median(ph[bm], axis=0).astype(np.float32)
    print("base skin (bgr)", np.round(base_col, 3))
    def delight(col, alpha):
        """Bring the low-frequency colour of projected skin to the body tone (removes the baked
        hair shadow / sun gradient; real shading comes from the scene lights)."""
        q = 4
        small = cv2.resize(col * alpha[:, :, None], (SIZE // q, SIZE // q), interpolation=cv2.INTER_AREA)
        smallw = cv2.resize(alpha, (SIZE // q, SIZE // q), interpolation=cv2.INTER_AREA)
        sig = SIZE / 4096 * 80 / q
        low = cv2.GaussianBlur(small, (0, 0), sig) / np.maximum(cv2.GaussianBlur(smallw, (0, 0), sig), 1e-4)[:, :, None]
        low = cv2.resize(low, (SIZE, SIZE), interpolation=cv2.INTER_LINEAR)
        gain = np.clip(base_col[None, None, :] / np.maximum(low, 1e-3), 0.7, 2.4)
        return np.clip(col * (1.0 + DELIGHT * (gain - 1.0)), 0, 1)

    a_d = np.clip(w_d / 0.12, 0, 1)
    a_mm = np.clip(w_m / 0.12, 0, 1)
    col_d, col_m = delight(col_d, a_d), delight(col_m, a_mm)
    a_d = np.minimum(a_d, cv2.GaussianBlur(cv2.erode(a_d, np.ones((7, 7), np.uint8)), (0, 0), SIZE / 4096 * 45))
    a_m = a_mm * (1 - a_d)
    tot = np.clip(a_d + a_m, 0, 1)
    proj = (col_d * a_d[:, :, None] + col_m * a_m[:, :, None]) / np.maximum(a_d + a_m, 1e-6)[:, :, None]
    # feathered edge towards the plain body tone
    feather = cv2.GaussianBlur(cv2.erode(tot, np.ones((9, 9), np.uint8)), (0, 0), SIZE / 4096 * 22)
    tot = np.minimum(tot, feather)
    out = proj * tot[:, :, None] + base_col[None, None, :] * (1 - tot[:, :, None])
    # scalp under the hair: dark-blonde tint so that gaps between strands do not show pink skin
    import hairgen
    hc, hr, hz_eye = hairgen.skull(fit, base)
    hu = (pos - hc.astype(np.float32)) / hr.astype(np.float32)
    hun = hu / np.maximum(np.linalg.norm(hu, axis=2, keepdims=True), 1e-6)
    thr = np.interp(hun[:, :, 1], [-1, -0.55, 0.0, 0.5, 1.0], [0.52, 0.34, 0.10, -0.42, -0.72])
    sc = np.clip((hun[:, :, 2] - thr) / 0.10, 0, 1) * (pos[:, :, 2] > hc[2] - 0.075) * valid
    sc = cv2.GaussianBlur(sc.astype(np.float32), (0, 0), SIZE / 4096 * 10)[:, :, None]
    out = out * (1 - 0.9 * sc) + np.array([0.20, 0.30, 0.42], np.float32) * (0.9 * sc)
    out[~valid] = base_col
    # bleed valid colours across UV seams
    inval = (~valid).astype(np.uint8)
    out8 = np.clip(out * 255 + 0.5, 0, 255).astype(np.uint8)
    out8 = cv2.inpaint(cv2.resize(out8, (SIZE // 2, SIZE // 2), interpolation=cv2.INTER_AREA),
                       cv2.resize(inval, (SIZE // 2, SIZE // 2), interpolation=cv2.INTER_NEAREST), 3, cv2.INPAINT_TELEA) \
        if os.environ.get("SEAMFILL", "0") == "1" else out8
    if out8.shape[0] != SIZE:
        big = cv2.resize(out8, (SIZE, SIZE), interpolation=cv2.INTER_LINEAR)
        keep = np.clip(out * 255 + 0.5, 0, 255).astype(np.uint8)
        big[valid] = keep[valid]
        out8 = big
    os.makedirs(os.path.join(ROOT, "textures"), exist_ok=True)
    cv2.imwrite(os.path.join(ROOT, "textures", "skin_albedo.png"), out8)
    cv2.imwrite(os.path.join(B, "skin_cover.png"), (np.stack([a_m, a_d, valid.astype(np.float32)], axis=2) * 255).astype(np.uint8))
    np.save(os.path.join(B, "skin_base_bgr.npy"), base_col)
    print("wrote skin_albedo.png", out8.shape)


if __name__ == "__main__":
    main()
