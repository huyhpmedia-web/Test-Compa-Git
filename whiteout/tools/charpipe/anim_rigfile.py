"""Save just the armature of a character spec to a .blend (input for anim_export.py): python anim_rigfile.py <model> <out.blend>"""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import build_characters as bcm, specs
name = sys.argv[-2]; out = sys.argv[-1]
t=time.time()
cb = bcm.CharBuilder(specs.SPECS[name]); cb.build_armature()
for o in list(bpy.data.objects):
    if o is not cb.arm: bpy.data.objects.remove(o)
bpy.ops.wm.save_as_mainfile(filepath=out)
print("saved", out, time.time()-t, [b.name for b in cb.arm.data.bones][:5])
