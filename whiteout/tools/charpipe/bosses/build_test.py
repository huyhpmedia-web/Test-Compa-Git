import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bosslib import *
reset()
p = Person("rimebound_civ_m", "t0", seed=3)
p.head_morph(stretch=0.2, jaw=0.5, mouth_cut=0.006)
p.pose([("head", "X", -15)])
M = Matrix.Identity(4)
res = finalize_person(p, M, dec={"body": 0.6})
export(os.path.join(OUT_DIR, "_test.glb"))
