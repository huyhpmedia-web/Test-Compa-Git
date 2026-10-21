"""Dev tool: build a static wardrobe sheet glb (all MakeHuman clothes on a body) for visual picking."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, bpy
import mh_lib as mh, bl_common as bc
from build_characters import CharBuilder, A, export_glb
items = sys.argv[sys.argv.index("--")+1:]
gender = 1.0 if items[0].startswith("male") or items[0].startswith("shoes") or items[0].startswith("fedora") else 0.0
spec = dict(name="wardrobe", gender=gender, age=30, height_m=1.75)
cb = CharBuilder(spec); cb.arm = None
for i, it in enumerate(items):
    kind, name = it.split("/")
    skin = bc.make_material("skin%d" % i, color=(0.9, 0.75, 0.65, 1), rough=0.6)
    mat = cb.mat_from_mhmat(name + str(i), A(kind, name, name + ".mhmat"), max_size=512)
    ob, P = cb.build_proxy(name, A(kind, name, name + ".mhclo"), mat)
    ob.location.x = (i - len(items)/2) * 0.9
    b = cb.build_body([]); b.location.x = ob.location.x; b.data.materials.append(skin); b.name = "b%d" % i
    # shift body slightly away? keep (clothes fit on top)
export_glb(cb, os.path.join(mh.CACHE, "work", "wardrobe.glb"), False)
