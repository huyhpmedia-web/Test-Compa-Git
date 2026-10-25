"""THE HAULER (HD): Tripo H3.1 mesh -> assets/enemies/hauler_hd.glb
One textured mesh 'Mass' (mound + crawling miners + the exposed driver) with two crawl shape keys (StepA/StepB: the miners' hands/arms
pull forward in alternating columns, travelling wave), a 'Driver' marker on the torn-open chest (weak point) with a warm glow halo.
Run: venv/bin/python tools/charpipe/bosses/hd_hauler.py
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hd_common import *

HEIGHT = 3.1
CHEST = (0.04, 2.08)       # x, z of the exposed ribcage (front view)
HEAD = (0.05, 2.88)


def main():
    o = load_raw("hauler")
    v = verts(o)
    orient(o, HEIGHT / (v[:, 2].max() - v[:, 2].min()), center="bbox")
    downscale_images(2048)
    tune_pbr(o, blood=0.12, ice=0.5)
    o.name = "Mass"
    v = verts(o)
    root = bpy.data.objects.new("Hauler", None)
    bpy.context.scene.collection.objects.link(root)
    parent_keep(o, root)
    # crawl shape keys
    o.shape_key_add(name="Basis", from_mix=False)
    for nm, sgn in (("StepA", 1.0), ("StepB", -1.0)):
        sk = o.shape_key_add(name=nm, from_mix=False)
        ph = 2 * math.pi * (v[:, 0] / 0.9 + v[:, 1] / 3.2)
        s = np.maximum(0.0, sgn * np.sin(ph))
        w = np.clip(1.0 - v[:, 2] / 1.15, 0.0, 1.0) ** 0.8
        # only the miners (not the driver column): fade out inside the driver's footprint
        co = v.copy()
        co[:, 1] -= 0.20 * w * s        # pull forward (front = -Y)
        co[:, 2] += 0.07 * w * s        # lift
        sk.data.foreach_set("co", co.reshape(-1))
        sk.value = 0.0
    # driver marker
    fy = front_y(v, CHEST[0], CHEST[1], 0.12)
    drv = empty("Driver", (CHEST[0], fy + 0.12, CHEST[1]), parent=o)
    hy = front_y(v, HEAD[0], HEAD[1], 0.12)
    empty("DriverHead", (HEAD[0], hy + 0.1, HEAD[1]), parent=o)
    gm = glow_material("glow_heart", (1.0, 0.5, 0.2), 4.0, 0.6)
    blob("Driver_glow", (CHEST[0], fy + 0.06, CHEST[1] + 0.04), (0.20, 0.07, 0.30), gm, parent=drv)
    print("fy", fy, "hy", hy)
    export(os.path.join(OUT_DIR, "hauler_hd.glb"), [root])


main()
