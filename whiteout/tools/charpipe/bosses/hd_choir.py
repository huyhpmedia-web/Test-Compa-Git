"""THE CHOIR (HD): Tripo H3.1 mesh -> assets/enemies/choir_hd.glb
Pillar (static) + Head0..Head4 (weak points, own pivot at the head centre, each with a glowing halo child) + ArmL/ArmR sweep pieces.
Run: venv/bin/python tools/charpipe/bosses/hd_choir.py
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hd_common import *

HEIGHT = 5.0
# five weak-point faces picked from the front view (x, z in the base-centred frame before the final recentre)
HEADS = [(0.17, 4.79), (-0.55, 4.13), (0.80, 3.70), (-0.45, 2.69), (0.43, 1.70)]
ARM_R = dict(xmin=1.0, zlo=2.75, zhi=3.55)      # long lower arm reaching out
ARM_L = dict(xmin=0.78, zlo=4.40, zhi=5.1)      # the priest's raised arm


def main():
    o = load_raw("choir")
    v = verts(o)
    orient(o, HEIGHT / (v[:, 2].max() - v[:, 2].min()), center="base")
    downscale_images(2048)
    tune_pbr(o, blood=0.14, ice=0.45)
    v = verts(o)
    core = v[(v[:, 2] > 0.3) & (v[:, 2] < 1.3)]
    shift = Vector((-float(np.mean(core[:, 0])), -float(np.mean(core[:, 1])), 0))
    print("core shift", shift)
    pc = polygon_centers(o)
    n = len(pc)
    taken = np.zeros(n, dtype=bool)
    parts = {}
    root = bpy.data.objects.new("Choir", None)
    bpy.context.scene.collection.objects.link(root)

    # arms first (they are long thin pieces that would otherwise be eaten by head spheres)
    for nm, d in (("ArmR", ARM_R), ("ArmL", ARM_L)):
        m = (pc[:, 0] > d["xmin"]) & (pc[:, 2] > d["zlo"]) & (pc[:, 2] < d["zhi"]) & ~taken
        band = v[(abs(v[:, 0] - d["xmin"]) < 0.08) & (v[:, 2] > d["zlo"]) & (v[:, 2] < d["zhi"])]
        piv = band.mean(0) if len(band) else np.array([d["xmin"], 0, (d["zlo"] + d["zhi"]) / 2])
        parts[nm] = (m, piv)
        taken |= m
    heads = []
    for i, (hx, hz) in enumerate(HEADS):
        fy = front_y(v, hx, hz, 0.12)
        c = np.array([hx, fy + 0.11, hz])
        for _ in range(3):   # pull the centre onto the head's mass
            mm = sphere_mask(v, c, (0.2, 0.3, 0.24))
            if mm.sum() > 50:
                c[0], c[2] = v[mm][:, 0].mean(), v[mm][:, 2].mean()
        m = sphere_mask(pc, c, (0.21, 0.26, 0.25)) & ~taken
        parts["Head%d" % i] = (m, c)
        heads.append((c, fy))
        taken |= m
        print("Head%d" % i, np.round(c, 2), "polys", int(m.sum()))
    parts["Pillar"] = (~taken, np.zeros(3))
    objs = {}
    for nm, (m, piv) in parts.items():
        ob = extract(o, m, nm)
        if nm != "Pillar":
            set_origin(ob, piv)
        parent_keep(ob, root)
        objs[nm] = ob
    # glow halos: flattened ellipsoids hugging each face (additive in game; see choir_model.gd)
    gm = glow_material("glow_halo", (0.45, 0.9, 1.0), 3.0, 0.5)
    for i, (c, fy) in enumerate(heads):
        h = objs["Head%d" % i]
        blob("Head%d_glow" % i, (c[0], fy - 0.03, c[2] - 0.02), (0.17, 0.07, 0.21), gm, parent=h)
    bpy.data.objects.remove(o)
    for ob in root.children:
        ob.location += shift
    print("polys:", {k: len(ob.data.polygons) for k, ob in objs.items()})
    export(os.path.join(OUT_DIR, "choir_hd.glb"), [root])


main()
