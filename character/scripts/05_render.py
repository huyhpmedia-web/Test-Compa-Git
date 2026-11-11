"""Stage 5 -- render the three reference-matching shots from character.blend and build
side-by-side comparison sheets.

usage: 05_render.py [shots=front,profile,closeup] [samples] [scale%]
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy  # noqa: E402
from PIL import Image  # noqa: E402

ROOT = os.path.dirname(HERE)
REF = {"front": "ref_front.jpg", "profile": "ref_profile.jpg", "closeup": "ref_closeup.jpg"}


def main(shots="front,profile,closeup", samples="160", scale="100", tag=""):
    bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT, "character.blend"))
    scene = bpy.context.scene
    scene.cycles.samples = int(samples)
    scene.cycles.device = 'CPU'
    scene.render.resolution_percentage = int(scale)
    os.makedirs(os.path.join(ROOT, "renders"), exist_ok=True)
    for name in shots.split(","):
        marker = scene.timeline_markers[name]
        scene.frame_set(marker.frame)
        scene.camera = marker.camera
        out = os.path.join(ROOT, "renders", f"{name}{tag}.png")
        scene.render.filepath = out
        bpy.ops.render.render(write_still=True)
        ren = Image.open(out).convert("RGB")
        ref = Image.open(os.path.join(ROOT, "reference", REF[name])).convert("RGB").resize(ren.size, Image.LANCZOS)
        sheet = Image.new("RGB", (ren.width * 2 + 12, ren.height), "white")
        sheet.paste(ref, (0, 0))
        sheet.paste(ren, (ren.width + 12, 0))
        sheet.save(os.path.join(ROOT, "renders", f"compare_{name}{tag}.jpg"), quality=92)
        print("rendered", name)


if __name__ == "__main__":
    main(*sys.argv[1:])
