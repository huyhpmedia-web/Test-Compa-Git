import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, bpy
import mh_lib as mh, bl_common as bc, specs, anim, clips
from build_characters import CharBuilder
spec = specs.SPECS["elias"]
cb = CharBuilder(spec); cb.build_armature()
rig = anim.Rig(cb.arm)
print("rest: pelvis", rig.head["pelvis"].round(3), "head", rig.head["head"].round(3), "foot", rig.head["foot_l"].round(3))
cl, meta = clips.build_clips(rig, True)
for name in sys.argv[sys.argv.index("--")+1:]:
    qs, locs = cl[name]
    # recompute FK for sampled frames by re-running pose on stored quats
    for fi in (0, len(qs)//2, len(qs)-1):
        # FK from basis
        full = {}
        for b in rig.order:
            p = rig.parent[b]; rr = rig.rest_rel(b)
            B = np.array(qs[fi][b].to_matrix())
            full[b] = (full[p] @ rr @ B) if p else (rig.Rr[b] @ B)
        ploc = rig.Rr["pelvis"] @ np.array(locs[fi])
        pos = anim.fk_pos(rig, full, ploc)
        print(name, fi, "pelvis", pos["pelvis"].round(2), "head", pos["head"].round(2), "foot_l", pos["foot_l"].round(2), "hand_r", pos["hand_r"].round(2))
