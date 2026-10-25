"""THE HOLLOW MOTHER phase 1 (HD): Tripo H3.1 crystal lattice with Ruth fused into it -> assets/enemies/mother_p1_hd.glb
Single textured mesh 'Lattice' + markers Heart (glowing chest, weak point, with a cyan halo child) and HeadMark.
Run: venv/bin/python tools/charpipe/bosses/hd_mother1.py
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hd_common import *

HEIGHT = 5.0
HEART = (0.04, 3.48)
HEAD = (0.0, 4.58)


def main():
    o = load_raw("mother_p1")
    v = verts(o)
    orient(o, HEIGHT / (v[:, 2].max() - v[:, 2].min()), center="base")
    downscale_images(2048)
    tune_pbr(o, blood=0.14, ice=0.4)
    o.name = "Lattice"
    v = verts(o)
    core = v[(v[:, 2] > 0.2) & (v[:, 2] < 1.5)]
    shift = (-float(core[:, 0].mean()), -float(core[:, 1].mean()), 0)
    root = bpy.data.objects.new("MotherP1", None)
    bpy.context.scene.collection.objects.link(root)
    parent_keep(o, root)
    fy = front_y(v, HEART[0], HEART[1], 0.15)
    hy = front_y(v, HEAD[0], HEAD[1], 0.12)
    heart = empty("Heart", (HEART[0], fy + 0.1, HEART[1]), parent=o)
    empty("HeadMark", (HEAD[0], hy + 0.1, HEAD[1]), parent=o)
    gm = glow_material("glow_heart", (0.5, 0.95, 1.0), 4.0, 0.7)
    blob("Heart_glow", (HEART[0], fy + 0.02, HEART[1]), (0.22, 0.08, 0.30), gm, parent=heart)
    print("shift", shift, "heart y", fy, "head y", hy)
    o.location = Vector(shift)
    # markers are children of o: they follow
    export(os.path.join(OUT_DIR, "mother_p1_hd.glb"), [root])


main()
