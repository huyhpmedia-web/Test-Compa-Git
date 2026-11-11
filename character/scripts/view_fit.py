"""Debug: clay renders of a fitted shape from canonical views.  usage: view_fit.py <npz> <out.png>"""
import os, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy, blcore, fitlib, fitscene, mhlib
from PIL import Image

def main(npz, out, views=None, res=700):
    d = np.load(npz)
    base = mhlib.BaseMesh()
    fs = fitscene.FitScene(base, d["verts"], d["eyes"], res=res, samples=16)
    fs.body.modifiers["Subdiv"].levels = 2
    fs.body.modifiers["Subdiv"].render_levels = 2
    c = np.array([0.0, -0.06, d["eyes"][0][2] - 0.035])
    views = views or [("front", 0, 0), ("q", -40, 0), ("side", -90, 0), ("q2", 40, 0), ("low", -15, -20)]
    tiles = []
    for name, yaw, pitch in views:
        yr, pr = np.radians(yaw), np.radians(pitch)
        eye = c + 0.72 * np.array([np.sin(yr) * np.cos(pr), -np.cos(yr) * np.cos(pr), np.sin(pr)])
        p = fs.render(fitlib.look_at(eye, c), 85.0, out.replace(".png", f"_{name}.png"))
        tiles.append(Image.open(p))
    W = Image.new("RGB", (res * len(tiles), res))
    for i, t in enumerate(tiles):
        W.paste(t, (i * res, 0))
    W.save(out)

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
