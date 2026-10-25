"""June, Ruth and the Rimebound civilian bodies (MakeHuman CC0 clothes + procedural pieces)."""
import os, math
import numpy as np
import bpy
import mh_lib as mh
import bl_common as bc
import paint as pt
from specs import (A, jtex, make_pbr, solid_mat, paint_skin, recolor_texture, normals_jpg, hair_png, ensure,
                   inflate, body_surface_patch, merge_meshes, box_mesh, TEX)


# ----------------------------------------------------------------- shared pieces
def face_parts(cb, spec, hair=None, hair_tint=None, brow="eyebrows/eyebrow002/eyebrow002", brow_tint=(0.4, 0.35, 0.33),
               lashes=True, eye_tint=(0.8, 0.85, 0.95), decim_hair=1.0, subdiv=True):
    n = cb.name; H = cb.H
    from specs import eye_image
    emat_png = eye_image(n + "_eye.jpg", spec.get("iris", (0.5, 0.33, 0.2)))
    emat = make_pbr(n + "_eyes", emat_png, rough=0.12, spec=0.8)
    P_e = mh.Proxy(A("eyes/low-poly/low-poly.mhclo"))
    ob = cb.add_mesh("eyes", cb.conv(P_e.fit(H.v, H.base_v)), [f[0] for f in P_e.faces], [f[1] for f in P_e.faces], P_e.uv, bone="head", mat=emat)
    if subdiv:
        sub = ob.modifiers.new("sub", 'SUBSURF'); sub.levels = 1; sub.render_levels = 1
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_move_to_index(modifier="sub", index=0)
        bpy.ops.object.modifier_apply(modifier="sub")
    items = [("brows", brow, brow_tint)]
    if lashes:
        items.append(("lashes", "eyelashes/eyelashes01/eyelashes01", (0.5, 0.45, 0.45)))
    for nm, d, tint in items:
        Pp = mh.Proxy(A(d + ".mhclo"))
        png = [f for f in os.listdir(os.path.dirname(A(d))) if f.endswith(".png")][0]
        m = make_pbr(n + "_" + nm, hair_png(cb, nm, os.path.join(os.path.dirname(A(d)), png), 512, tint=tint), rough=0.8, alpha=True)
        cb.add_mesh(nm, cb.conv(Pp.fit(H.v, H.base_v)), [f[0] for f in Pp.faces], [f[1] for f in Pp.faces], Pp.uv, bone="head", mat=m)
    if hair:
        Ph = mh.Proxy(A(hair, os.path.basename(hair) + ".mhclo"))
        png = [f for f in os.listdir(A(hair)) if f.endswith(".png")][0]
        hm = make_pbr(n + "_hair", hair_png(cb, "hair", os.path.join(A(hair), png), 1024, tint=hair_tint), rough=0.7, alpha=True)
        ho = cb.add_mesh("hair", cb.conv(Ph.fit(H.v, H.base_v)), [f[0] for f in Ph.faces], [f[1] for f in Ph.faces], Ph.uv,
                         W=Ph.skin_weights(cb.Wfull), mat=hm)
        if decim_hair < 1.0:
            cb.decimate(ho, decim_hair)


def head_dims(cb):
    """head extents in blender coords (y forward = negative)."""
    H = cb.H
    bp = cb.conv(H.v[:mh.N_BODY])
    eye_z = cb.conv(H.joint("joint-l-eye"))[2]
    m = (bp[:, 2] > eye_z - 0.03) & (bp[:, 2] < eye_z + 0.03)
    xs = np.abs(bp[m][:, 0]); ys = bp[m][:, 1]
    top = bp[:, 2].max()
    return dict(eye_z=eye_z, hw=float(np.percentile(xs, 99)), ymin=float(ys.min()), ymax=float(ys.max()), top=float(top))


def dome(cb, label, color, rim_front, rim_back, extra=0.012, nu=28, nv=14, rough=0.9, knit=False, pom=None, cuff=0.0):
    """closed dome (beanie / hard hat) fitted to the head; returns object."""
    d = head_dims(cb)
    cx = 0.0; cy = (d["ymin"] + d["ymax"]) / 2
    rx = d["hw"] + extra; ry = (d["ymax"] - d["ymin"]) / 2 + extra
    zc = d["eye_z"]; rz = d["top"] - zc + extra
    verts = []; uvs = []; faces = []; fuv = []
    for j in range(nv + 1):
        v = j / nv                       # 0 = rim .. 1 = top
        for i in range(nu + 1):
            a = i / nu * 2 * math.pi
            ca, sa = math.cos(a), math.sin(a)
            # rim height varies front (low on forehead) to back
            fb = (-(sa) + 1) / 2         # 1 at front (-y)  0 at back
            rim_z = rim_back + (rim_front - rim_back) * fb
            ph = v * math.pi / 2
            zz = rim_z + (zc + rz - rim_z) * math.sin(ph) if True else 0
            rr = math.cos(ph) if v < 1 else 0.0
            # radius at rim from ellipse at that height
            t = np.clip((zz - zc) / rz, -0.9, 0.995)
            k = math.sqrt(max(1 - t * t, 0.02))
            verts.append([cx + rx * k * ca * (1.0 if v > 0 else 1.0), cy + ry * k * sa, zz])
            uvs.append([i / nu * (6 if knit else 1), v * (3 if knit else 1)])
    idx = lambda i, j: j * (nu + 1) + i
    for j in range(nv):
        for i in range(nu):
            faces.append([idx(i, j), idx(i + 1, j), idx(i + 1, j + 1), idx(i, j + 1)])
            fuv.append(faces[-1])
    verts = np.array(verts)
    # cuff ring
    mat = cuff_mat = None
    ob_parts = [(verts, faces)]
    if cuff > 0:
        # thicker band around the rim
        ring = []
        for i in range(nu):
            a = i / nu * 2 * math.pi
            ca, sa = math.cos(a), math.sin(a)
            fb = (-(sa) + 1) / 2
            rim_z = rim_back + (rim_front - rim_back) * fb
            for dz, grow in ((-0.002, 0.012), (cuff, 0.016)):
                zz = rim_z + dz
                t = np.clip((zz - zc) / rz, -0.9, 0.995); k = math.sqrt(max(1 - t * t, 0.02))
                ring.append([cx + (rx * k + grow) * ca, cy + (ry * k + grow) * sa, zz])
        ring = np.array(ring)
        rf = [[2 * i, 2 * ((i + 1) % nu), 2 * ((i + 1) % nu) + 1, 2 * i + 1] for i in range(nu)]
        ob_parts.append((ring, rf))
    V, F = merge_meshes(ob_parts)
    m = solid_mat(cb.name + "_" + label, color, rough)
    ob = cb.add_mesh(label, V, F, bone="head", mat=m)
    return ob, d


def knit_dome(cb, label, color, rim_front, rim_back, cuff=0.045, pom=False):
    ob, d = dome(cb, label, color, rim_front, rim_back, extra=0.014, cuff=cuff)
    # knit texture via UVs would need a texture; use colour + subtle noise vertex-less (kept simple)
    if pom:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.035, location=(0, 0, 0), segments=12, ring_count=8)
        s = bpy.context.active_object
        s.location = (0.0, (d["ymin"] + d["ymax"]) / 2, d["top"] + 0.03)
        # transfer to head bone mesh by merging later: bind rigid
        bm_verts = np.array([v.co[:] for v in s.data.vertices]) + np.array(s.location)
        faces = [list(p.vertices) for p in s.data.polygons]
        bpy.data.objects.remove(s)
        cb.add_mesh(label + "_pom", bm_verts, faces, bone="head", mat=solid_mat(cb.name + "_pom", color, 0.95))
    return ob


def headphones(cb, color=(0.05, 0.05, 0.06), accent=(0.75, 0.15, 0.1)):
    d = head_dims(cb)
    cy = (d["ymin"] + d["ymax"]) / 2
    pts = []
    for k in range(25):
        a = math.pi * k / 24
        pts.append([(d["hw"] + 0.03) * math.cos(a), cy + 0.0, d["eye_z"] + 0.02 + (d["top"] - d["eye_z"] + 0.035) * math.sin(a)])
    V, F = tube(pts, 0.007, 6)
    parts = [(V, F)]
    for sx in (-1, 1):
        cx = sx * (d["hw"] + 0.032)
        cyl_v, cyl_f = cylinder([cx, cy + 0.005, d["eye_z"] + 0.015], 0.045, 0.03, axis=0, n=16)
        parts.append((cyl_v, cyl_f))
    V, F = merge_meshes(parts)
    cb.add_mesh("headphones", V, F, bone="head", mat=solid_mat(cb.name + "_hp", color, 0.5, 0.2))


def tube(points, r, n=6):
    pts = np.array(points); V = []; F = []
    for i, p in enumerate(pts):
        t = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]; t /= np.linalg.norm(t)
        helper = [0, 1, 0] if abs(t[1]) < 0.9 else [1, 0, 0]
        a = np.cross(t, helper); a /= np.linalg.norm(a); b = np.cross(t, a)
        for k in range(n):
            ang = 2 * math.pi * k / n
            V.append(p + r * (math.cos(ang) * a + math.sin(ang) * b))
    for i in range(len(pts) - 1):
        for k in range(n):
            k2 = (k + 1) % n
            F.append([i * n + k, i * n + k2, (i + 1) * n + k2, (i + 1) * n + k])
    return np.array(V), F


def cylinder(center, radius, length, axis=0, n=16):
    V = []; F = []
    c = np.array(center)
    for end in (-0.5, 0.5):
        for k in range(n):
            a = 2 * math.pi * k / n
            off = np.zeros(3); off[axis] = end * length
            o2 = [math.cos(a) * radius, math.sin(a) * radius]
            ax2 = [i for i in range(3) if i != axis]
            off[ax2[0]] = o2[0]; off[ax2[1]] = o2[1]
            V.append(c + off)
    for k in range(n):
        k2 = (k + 1) % n
        F.append([k, k2, n + k2, n + k])
    F.append(list(range(n))[::-1]); F.append([n + i for i in range(n)])
    return np.array(V), F


def make_boots(cb, shoe, color, top=0.22, shaft_col=None, sole=1.0, widen=(1.12, 1.1, 1.25), dec=0.6):
    n = cb.name; H = cb.H
    Ps = mh.Proxy(A(f"clothes/{shoe}/{shoe}.mhclo"))
    spos = cb.conv(Ps.fit(H.v, H.base_v))
    for side in (1, -1):
        m = (spos[:, 0] * side) > 0
        c = np.array([spos[m][:, 0].mean(), spos[m][:, 1].mean(), 0.0])
        spos[m] = c + (spos[m] - c) * np.array(widen)
    spos = spos + pt.vertex_normals(spos, [f[0] for f in Ps.faces]) * 0.005
    so = pt.load_rgb(A(f"clothes/{shoe}/{shoe}_diffuse.png"), 1024)
    sd = recolor_texture(cb, "boots", Ps, spos, np.zeros(len(spos), dtype=np.int64), {0}, color, 1024, so, contrast=0.55)
    bo = cb.add_mesh("boots", spos, [f[0] for f in Ps.faces], [f[1] for f in Ps.faces], Ps.uv, W=Ps.skin_weights(cb.Wfull),
                     mat=make_pbr(n + "_boots", sd, rough=0.7))
    cb.decimate(bo, dec)
    bpos = cb.conv(H.v[:mh.N_BODY])
    mask = (bpos[:, 2] > 0.045) & (bpos[:, 2] < top + 0.04) & (np.abs(bpos[:, 0]) > 0.04)
    sp, sfv, sft, used = body_surface_patch(cb, mask, 0.014)
    cb.add_mesh("boot_shaft", sp, sfv, None, None, W=cb.W[used], mat=solid_mat(n + "_shaft", shaft_col or tuple(c ** 0.9 for c in color), 0.7))
    return set(np.where(bpos[:, 2] < top + 0.05)[0].tolist()) | set(Ps.delete_verts)


def suit_pieces(cb, rel, orig_png, pieces, trousers_cut=None, size=1024, inflate_map=None, stretch=None):
    """pieces: list of dict(match=fn(comp_zmin,comp_zmax,comp_size)->bool, label, color|painter, contrast, normal(bool), inflate,
       cut_below(z))  -> deleted body verts"""
    n = cb.name; H = cb.H
    P = mh.Proxy(A(rel))
    pos = cb.conv(P.fit(H.v, H.base_v))
    comp = cb.components(P)
    orig = pt.load_rgb(orig_png, size)
    base_dir = os.path.dirname(A(rel))
    nrm_path = [os.path.join(base_dir, f) for f in os.listdir(base_dir) if f.endswith("_normal.png")]
    nrm_jpg = normals_jpg(cb, os.path.basename(base_dir), nrm_path[0], 1024) if nrm_path else None
    stats = []
    for c in range(comp.max() + 1):
        m = comp == c
        stats.append((float(pos[m][:, 2].min()), float(pos[m][:, 2].max()), int(m.sum())))
    Wd = P.skin_weights(cb.Wfull)
    nrm = pt.vertex_normals(pos, [f[0] for f in P.faces])
    for pc in pieces:
        ids = {c for c, st in enumerate(stats) if pc["match"](*st)}
        if not ids:
            print("  [warn] piece", pc["label"], "matched nothing", stats)
            continue
        mask = np.isin(comp, list(ids))
        ppos = pos.copy()
        if pc.get("inflate"):
            ppos[mask] = pos[mask] + nrm[mask] * pc["inflate"]
        if pc.get("stretch"):
            z0, k, grow = pc["stretch"]       # stretch verts below z0 downward by k, grow outward
            low = mask & (ppos[:, 2] < z0)
            dz = (z0 - ppos[low, 2]) * (k - 1.0)
            ppos[low, 2] -= dz
            rad = np.array([1.0, 1.0])
            ppos[low, 0] *= (1 + grow * (dz / max(dz.max(), 1e-6)))
            ppos[low, 1] = (ppos[low, 1] - pos[:, 1][mask].mean()) * (1 + grow * (dz / max(dz.max(), 1e-6))) + pos[:, 1][mask].mean()
        if pc.get("cut_below") is not None:
            mask = mask & (pos[:, 2] > pc["cut_below"])
        if "painter" in pc:
            diff = pc["painter"](cb, P, pos, comp, ids, orig, size)
        else:
            diff = recolor_texture(cb, pc["label"], P, pos, comp, ids, pc["color"], size, orig, contrast=pc.get("contrast", 0.5), gain=pc.get("gain", 1.0))
        mat = make_pbr(f"{n}_{pc['label']}", diff, nrm_jpg if pc.get("normal", True) else None, rough=pc.get("rough", 0.9))
        sub, fv, ft, remap, used = cb.sub_mesh(ppos, P.faces, mask)
        ob = cb.add_mesh(pc["label"], sub, fv, ft, P.uv, W=Wd[used], mat=mat)
        if pc.get("dec"):
            cb.decimate(ob, pc["dec"])
    return set(P.delete_verts)


def finish_body(cb, spec, skin_png, del_verts, dec=0.6):
    skin_mat = make_pbr(cb.name + "_skin", skin_png, rough=0.58, spec=0.4)
    body = cb.build_body(sorted(del_verts))
    body.data.materials.append(skin_mat)
    if dec < 1.0:
        cb.decimate(body, dec)
    return body


def glove_hands(cb, color, offset=0.005, dec=0.4):
    H = cb.H
    bpos = cb.conv(H.v[:mh.N_BODY])
    hand_names = [b for b in cb.bones if any(k in b for k in ("hand_", "thumb", "index", "middle", "ring", "pinky"))]
    hw = cb.W[:, [cb.bones.index(b) for b in hand_names]].sum(1)
    gmask = hw > 0.3
    gp, gfv, gft, gused = body_surface_patch(cb, gmask, offset)
    go = cb.add_mesh("gloves", gp, gfv, None, None, W=cb.W[gused], mat=solid_mat(cb.name + "_gloves", color, 0.75))
    cb.decimate(go, dec)
    return set(np.where(gmask)[0].tolist())


def parka_painter(color, trim, seam=0.0):
    def f(cb, P, pos, comp, ids, orig, size):
        tris = [t for t in pt.tri_list(P.faces) if comp[t[0]] in ids]
        r = pt.rasterize(tris, P.uv, {"pos": pos}, size)
        p = r["pos"]; z = p[:, 2]; ax = np.abs(p[:, 0])
        px_, py_ = r["x"], r["y"]
        o = orig[py_, px_]
        lum = (o * np.array([0.3, 0.59, 0.11])).sum(1)
        lum = np.clip(lum / max(np.median(lum), 1e-3), 0.6, 1.4); lum = 0.6 + 0.4 * lum
        per = 0.085
        fr = (z / per) - np.floor(z / per)
        puff = 0.8 + 0.2 * np.sin(np.pi * fr) ** 0.6
        sm = np.exp(-(fr ** 2) / 0.001) + np.exp(-((fr - 1) ** 2) / 0.001)
        col = np.array(color)[None] * (puff * lum)[:, None] * (1 - 0.45 * np.clip(sm, 0, 1)[:, None])
        n = pt.hash_noise(px_ // 3, py_ // 3, 5)
        col = col * (1 - 0.1 * n[:, None])
        cov = np.zeros((size, size), dtype=bool); cov[py_, px_] = True
        img = np.zeros((size, size, 3), dtype=np.float32); img[py_, px_] = np.clip(col, 0, 1)
        img = pt.dilate(img, cov, 8)
        return jtex(f"{cb.name}_parka_diffuse.jpg", img, 90)
    return f


UPPER = lambda zmin, zmax, n: zmax > 1.2 and zmin > 0.5 and n > 200
LOWER = lambda zmin, zmax, n: zmax < 1.25 and zmin < 0.4 and n > 500
OVERALL = lambda zmin, zmax, n: zmin < 0.4 and zmax > 1.2 and n > 1500
UPPER_BIG = lambda zmin, zmax, n: zmax > 1.2 and zmin > 0.5 and n > 1000
UPPER_SMALL = lambda zmin, zmax, n: zmax > 1.2 and zmin > 0.5 and 200 < n <= 1000



# ======================================================================= characters
def stethoscope(cb):
    H = cb.H
    neck = cb.conv(H.joint("joint-neck")); chest = cb.conv(H.joint("joint-spine-1"))
    r = 0.085
    ring = [[r * math.cos(a), neck[1] + 0.012 + r * 0.8 * math.sin(a) * 1.0, neck[2] - 0.035] for a in np.linspace(0, 2 * math.pi, 28)]
    V1, F1 = tube(ring + [ring[0]], 0.0045, 6)
    drop = [[0.0, neck[1] - 0.07, neck[2] - 0.045], [0.0, neck[1] - 0.095, neck[2] - 0.15], [0.01, neck[1] - 0.11, chest[2] - 0.12]]
    V2, F2 = tube(drop, 0.0045, 6)
    V3, F3 = cylinder([0.01, neck[1] - 0.115, chest[2] - 0.13], 0.022, 0.012, axis=1, n=12)
    V, F = merge_meshes([(V1, F1), (V2, F2), (V3, F3)])
    cb.add_mesh("stethoscope", V, F, bone="spine_03", mat=solid_mat(cb.name + "_steth", (0.12, 0.12, 0.13), 0.35, 0.6))


def build_june(cb, spec):
    n = cb.name; H = cb.H
    skin_png = paint_skin(cb, spec["skin"], spec["details"], 0.0, 0.5, (0.98, 0.92, 0.88))
    zw = cb.conv(H.joint("joint-spine-4"))[2]
    dv = set()
    dv |= suit_pieces(cb, "clothes/male_casualsuit05/male_casualsuit05.mhclo", A("clothes/male_casualsuit05/male_casualsuit05_diffuse.png"), [
        dict(match=UPPER_BIG, label="parka", painter=parka_painter((0.1, 0.24, 0.17), None), inflate=0.016, stretch=(zw + 0.03, 1.9, 0.10), dec=0.6),
        dict(match=UPPER_SMALL, label="hoodie", color=(0.12, 0.12, 0.14), contrast=0.2, rough=0.95),
        dict(match=LOWER, label="jeans", color=(0.1, 0.14, 0.22), contrast=0.35, cut_below=0.22),
    ])
    dv |= make_boots(cb, "shoes02", (0.2, 0.12, 0.08), top=0.2, widen=(1.1, 1.08, 1.15))
    dv |= glove_hands(cb, (0.62, 0.28, 0.1))
    bpos = cb.conv(H.v[:mh.N_BODY])
    dv |= set(np.where(bpos[:, 2] < 0.26)[0].tolist())
    finish_body(cb, spec, skin_png, dv, 0.65)
    d = head_dims(cb)
    face_parts(cb, spec, hair="hair/ponytail01", hair_tint=(0.36, 0.2, 0.1), brow="eyebrows/eyebrow002/eyebrow002", brow_tint=(0.5, 0.35, 0.28), eye_tint=(0.7, 0.85, 1.0))
    knit_dome(cb, "beanie", (0.78, 0.52, 0.1), d["eye_z"] + 0.055, d["eye_z"] - 0.03, cuff=0.05, pom=True)
    headphones(cb, (0.07, 0.07, 0.08))


def build_ruth(cb, spec):
    n = cb.name; H = cb.H
    skin_png = paint_skin(cb, spec["skin"], spec["details"], 0.0, 0.6, (0.98, 0.93, 0.9))
    dv = set()
    dv |= suit_pieces(cb, "clothes/female_elegantsuit01/female_elegantsuit01.mhclo", A("clothes/female_elegantsuit01/female_elegantsuit01_diffuse.png"), [
        dict(match=lambda zmin, zmax, n_: zmax > 1.0 and n_ > 1000, label="cardigan", color=(0.2, 0.34, 0.25), contrast=0.12, rough=0.95, inflate=0.006),
        dict(match=lambda zmin, zmax, n_: zmax < 1.1 and n_ < 1000, label="skirt", color=(0.1, 0.12, 0.2), contrast=0.4),
    ])
    dv |= make_boots(cb, "shoes05", (0.82, 0.82, 0.85), top=0.1, shaft_col=(0.8, 0.8, 0.82), widen=(1.05, 1.05, 1.0))
    bpos = cb.conv(H.v[:mh.N_BODY])
    dv |= set(np.where(bpos[:, 2] < 0.12)[0].tolist())
    finish_body(cb, spec, skin_png, dv, 0.65)
    face_parts(cb, spec, hair="hair/bob02", hair_tint=(0.82, 0.82, 0.85), brow="eyebrows/eyebrow002/eyebrow002", brow_tint=(0.7, 0.7, 0.7), eye_tint=(0.75, 0.85, 0.95))
    stethoscope(cb)


def build_rime(cb, spec):
    """Rimebound civilian body: spec['outfit'] selects clothes."""
    n = cb.name; H = cb.H; o = spec["outfit"]
    skin_png = paint_skin(cb, spec["skin"], spec["details"], spec.get("stubble", 0.0), 0.2, spec.get("skin_tint", (0.86, 0.92, 0.97)))
    dv = set()
    if o == "civ_m":
        dv |= suit_pieces(cb, "clothes/male_casualsuit03/male_casualsuit03.mhclo", A("clothes/male_casualsuit03/male_casualsuit03_diffuse.png"), [
            dict(match=UPPER, label="shirt", color=(0.42, 0.26, 0.22), contrast=0.9, dec=0.55),
            dict(match=LOWER, label="jeans", color=(0.15, 0.17, 0.22), contrast=0.5, cut_below=0.12, dec=0.6)])
        dv |= make_boots(cb, "shoes04", (0.12, 0.1, 0.08), top=0.1, widen=(1.05, 1.05, 1.0), dec=0.4)
        hair = ("hair/short03", (0.28, 0.24, 0.22))
    elif o == "civ_f":
        dv |= suit_pieces(cb, "clothes/female_casualsuit01/female_casualsuit01.mhclo", A("clothes/female_casualsuit01/female_casualsuit01_diffuse.png"), [
            dict(match=UPPER, label="top", color=(0.30, 0.34, 0.4), contrast=0.7, dec=0.6),
            dict(match=LOWER, label="jeans", color=(0.12, 0.15, 0.22), contrast=0.5, cut_below=0.1, dec=0.6)])
        dv |= make_boots(cb, "shoes06", (0.3, 0.3, 0.32), top=0.1, widen=(1.03, 1.03, 1.0), dec=0.4)
        hair = ("hair/bob01", (0.2, 0.15, 0.12))
    elif o == "miner":
        dv |= suit_pieces(cb, "clothes/male_worksuit01/male_worksuit01.mhclo", A("clothes/male_worksuit01/male_worksuit01_diffuse.png"), [
            dict(match=OVERALL, label="overalls", color=(0.13, 0.15, 0.2), contrast=0.7, dec=0.55),
            dict(match=lambda zmin, zmax, n_: zmax > 1.2 and zmin > 0.5 and n_ > 500, label="shirt", color=(0.4, 0.1, 0.08), contrast=0.6, dec=0.55)])
        dv |= make_boots(cb, "shoes02", (0.08, 0.07, 0.06), top=0.2, widen=(1.12, 1.1, 1.2), dec=0.4)
        dv |= glove_hands(cb, (0.3, 0.27, 0.22), dec=0.3)
        hair = ("hair/short04", (0.25, 0.22, 0.2))
    elif o == "nurse":
        dv |= suit_pieces(cb, "clothes/female_elegantsuit01/female_elegantsuit01.mhclo", A("clothes/female_elegantsuit01/female_elegantsuit01_diffuse.png"), [
            dict(match=lambda zmin, zmax, n_: zmax > 1.0 and n_ > 1000, label="uniform", color=(0.66, 0.7, 0.72), contrast=0.3, rough=0.9, dec=0.6),
            dict(match=lambda zmin, zmax, n_: zmax < 1.1 and n_ < 1000, label="skirt", color=(0.62, 0.66, 0.68), contrast=0.3, dec=0.6)])
        dv |= make_boots(cb, "shoes05", (0.7, 0.72, 0.74), top=0.1, widen=(1.04, 1.04, 1.0), dec=0.4)
        hair = ("hair/bob02", (0.38, 0.28, 0.2))
    bpos = cb.conv(H.v[:mh.N_BODY])
    dv |= set(np.where(bpos[:, 2] < 0.14)[0].tolist())
    if o == "miner":
        pass
    finish_body(cb, spec, skin_png, dv, spec.get("body_dec", 0.4))
    d = head_dims(cb)
    face_parts(cb, spec, hair=hair[0], hair_tint=hair[1], brow="eyebrows/eyebrow001/eyebrow001", brow_tint=(0.35, 0.33, 0.32),
               lashes=False, eye_tint=(0.75, 0.85, 1.0), decim_hair=0.35, subdiv=False)
    if o == "miner":
        dome(cb, "hardhat", (0.95, 0.68, 0.04), d["eye_z"] + 0.065, d["eye_z"] + 0.0, extra=0.02, rough=0.45, cuff=0.0)
        lamp, _ = cylinder([0.0, d["ymin"] - 0.012, d["eye_z"] + 0.1], 0.022, 0.03, axis=1, n=10)[0], None
        V, F = cylinder([0.0, d["ymin"] - 0.015, d["eye_z"] + 0.1], 0.022, 0.035, axis=1, n=10)
        lm = make_pbr(n + "_lamp", None, rough=0.3, color=(1.0, 0.95, 0.8, 1.0))
        lm.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = (1.0, 0.92, 0.7, 1.0)
        lm.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 3.0
        cb.add_mesh("lamp", V, F, bone="head", mat=lm)
    if o == "nurse":
        dome(cb, "cap", (0.9, 0.9, 0.92), d["top"] - 0.05, d["top"] - 0.04, extra=0.004, rough=0.9)
        stethoscope(cb)
