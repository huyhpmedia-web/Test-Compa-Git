"""THE HOLLOW MOTHER phase 2 (HD): Tripo H3.1 spider-Ruth -> assets/enemies/mother_p2_hd.glb
Body (Ruth + dangling abdomen, markers Heart / HeadMark / Abdomen) + Leg0..Leg7 (upper piece, origin at the hip) + Leg<i>_lo (lower piece, origin at the
knee, with a Leg<i>_tip marker at the foot). The raw mesh has 7 legs; Leg7 is a mirrored copy of the back-right leg so the gait has 8.
Run: venv/bin/python tools/charpipe/bosses/hd_mother2.py     (HD_PREVIEW=1: only write label previews)
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hd_common import *

HEIGHT = 3.0
BODY_R = 0.62          # horizontal radius of the body cylinder (legs are cut where they leave it)
PREVIEW = os.environ.get("HD_PREVIEW") == "1"


def main():
    o = load_raw("mother_p2")
    v = verts(o)
    orient(o, HEIGHT / (v[:, 2].max() - v[:, 2].min()), center="bbox")
    downscale_images(2048)
    tune_pbr(o, blood=0.12, ice=0.35)
    v = verts(o)
    F = faces(o)
    top = v[v[:, 2] > 2.2]
    bx, by = float(top[:, 0].mean()), float(top[:, 1].mean())
    o.data.transform(Matrix.Translation((-bx, -by, 0)))
    o.data.update()
    v = verts(o)
    r = np.hypot(v[:, 0], v[:, 1])
    # --- 7 foot tips (lowest clusters)
    low = np.where(v[:, 2] < 0.4)[0]
    cl = []
    for i in low[np.argsort(v[low, 2])]:
        for c in cl:
            if np.linalg.norm(v[i, :2] - c["p"]) < 0.3:
                c["idx"].append(i)
                break
        else:
            cl.append({"p": v[i, :2].copy(), "idx": [i]})
    print("tips", len(cl))
    dist, grp = geodesic(v, F, [c["idx"] for c in cl])
    body = r < BODY_R
    body &= v[:, 2] > 0.9
    body |= (v[:, 2] > 1.9) & (r < 0.72)               # jacket / head / shoulders never belong to a leg
    BODY = 7
    lab = np.where(body, BODY, grp)
    if PREVIEW:
        for view in ("front", "side", "top"):
            print(preview(v, "m2_split_" + view, view=view, labels=lab, px=900, splat=3))
        return
    pc = polygon_centers(o)
    # polygon -> label by its vertices' majority
    me = o.data
    plab = np.empty(len(me.polygons), dtype=np.int32)
    for i, p in enumerate(me.polygons):
        ls = [int(lab[x]) for x in p.vertices]
        plab[i] = max(set(ls), key=ls.count)
    # --- knee / hip per leg
    legs = []
    for li in range(len(cl)):
        m = lab == li
        pts = v[m]
        ds = dist[m]
        zmax = pts[:, 2].max()
        knee = pts[pts[:, 2] > zmax - 0.1].mean(0)
        dk = float(ds[pts[:, 2] > zmax - 0.1].mean())
        hip_pts = pts[r[m] < BODY_R + 0.2]
        hip = hip_pts.mean(0) if len(hip_pts) else pts[np.argmin(r[m])]
        foot = pts[ds < 0.06].mean(0)
        legs.append(dict(li=li, knee=knee, dk=dk, hip=hip, foot=foot))
        print("leg", li, "hip", np.round(hip, 2), "knee", np.round(knee, 2), "foot", np.round(foot, 2), "dk", round(dk, 2))
    # --- pieces
    root = bpy.data.objects.new("MotherP2", None)
    bpy.context.scene.collection.objects.link(root)
    bodyo = extract(o, plab == BODY, "Body")
    parent_keep(bodyo, root)
    pieces = []
    for L in legs:
        li = L["li"]
        vm = (lab == li)
        lo_v = vm & (dist < L["dk"])
        lo_p = np.array([all(lo_v[x] for x in p.vertices) or (np.mean([lo_v[x] for x in p.vertices]) > 0.5) for p in me.polygons]) & (plab == li)
        up_p = (plab == li) & ~lo_p
        pieces.append((li, up_p, lo_p, L))
    legobjs = []
    for li, up_p, lo_p, L in pieces:
        up = extract(o, up_p, "Leg%d" % li)
        lo = extract(o, lo_p, "Leg%d_lo" % li)
        legobjs.append((li, up, lo, L))
    # 8th leg: a copy of the back-right leg turned round the body axis into the empty back slot (~103 deg)
    cand = max(legs, key=lambda L: L["foot"][1] if L["foot"][0] > 0 else -9)
    src = [x for x in legobjs if x[0] == cand["li"]][0]
    fa = math.atan2(cand["foot"][1], cand["foot"][0])
    delta = math.radians(103.0) - fa
    print("copy source leg", cand["li"], "turned by", round(math.degrees(delta), 1))
    rot = Matrix.Rotation(delta, 4, "Z")
    new = []
    for nm, sob in (("Leg7", src[1]), ("Leg7_lo", src[2])):
        me2 = sob.data.copy()
        me2.transform(rot)
        ob = bpy.data.objects.new(nm, me2)
        bpy.context.scene.collection.objects.link(ob)
        new.append(ob)
    Lm = dict(cand)
    for k in ("hip", "knee", "foot"):
        Lm[k] = np.array(rot @ Vector(cand[k]))
    Lm["li"] = 7
    legobjs.append((7, new[0], new[1], Lm))
    # rename in angle order so Leg0..Leg7 run round the body
    def ang(x):
        h = x[3]["hip"]
        return math.atan2(h[1], h[0])
    legobjs.sort(key=ang)
    for idx, (li, up, lo, L) in enumerate(legobjs):
        up.name = "Leg%d" % idx
        lo.name = "Leg%d_lo" % idx
        set_origin(up, L["hip"])
        set_origin(lo, L["knee"])
        parent_keep(up, root)
        parent_keep(lo, root)
        empty("Leg%d_tip" % idx, L["foot"], parent=lo)
        print("Leg%d <- src %d hip %s foot %s" % (idx, li, np.round(L["hip"], 2), np.round(L["foot"], 2)))
    # markers on the body
    cy = front_y(v[body], 0.0, 2.15, 0.2)
    empty("Heart", (0.0, cy + 0.12, 2.1), parent=bodyo)
    hy = front_y(v[body], 0.0, 2.68, 0.1)
    hm = empty("HeadMark", (0.0, hy + 0.08, 2.66), parent=bodyo)
    empty("Abdomen", (0.0, 0.0, 1.3), parent=bodyo)
    gm = glow_material("glow_heart", (0.5, 0.95, 1.0), 3.0, 0.5)
    blob("Heart_glow", (0.0, cy + 0.04, 2.1), (0.12, 0.05, 0.16), gm, parent=bodyo)
    em = glow_material("glow_eye", (0.55, 0.95, 1.0), 6.0, 0.9)
    for sx in (-1, 1):
        blob("glow_eye_%d" % sx, (sx * 0.09, hy + 0.0, 2.69), (0.035, 0.02, 0.025), em, parent=hm)
    bpy.data.objects.remove(o)
    export(os.path.join(OUT_DIR, "mother_p2_hd.glb"), [root])


main()
