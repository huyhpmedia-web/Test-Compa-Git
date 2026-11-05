"""Export animation-only glbs (assets/anims/<set>.glb) retargeted onto the Whiteout MakeHuman/MPFB2 rig.

  CHARPIPE_CACHE=... venv/bin/python tools/charpipe/anim_export.py <rig.blend> <set> [--out DIR] [--only a,b] [--ual UAL1_Standard.fbx]

<rig.blend> is a file holding just the character armature (made by `anim_rigfile.py <model> <out.blend>`: the same CharBuilder
armature that ships in assets/characters/<model>.glb).  Sets are defined in anim_sets.py.
The glb carries a one-triangle dummy skinned mesh so Godot builds a Skeleton3D; actors/character_model.gd loads the clips into an
AnimationLibrary at runtime, overriding the clips embedded in the character glb by name and adding new ones.
"""
import os, sys, json, argparse, time, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import bpy
import anim as A
import anim_src as S

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../.."))


def load_rig(blend):
    bpy.ops.wm.open_mainfile(filepath=blend)
    arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    return A.Rig(arm)


def add_dummy_mesh(rig):
    me = bpy.data.meshes.new("dummy")
    me.from_pydata([(0, 0, 0), (0.01, 0, 0), (0, 0.01, 0)], [], [(0, 1, 2)])
    ob = bpy.data.objects.new("dummy_mesh", me)
    bpy.context.scene.collection.objects.link(ob)
    vg = ob.vertex_groups.new(name="pelvis")
    vg.add([0, 1, 2], 1.0, "REPLACE")
    m = ob.modifiers.new("Armature", "ARMATURE"); m.object = rig.ob
    ob.parent = rig.ob
    return ob


def export(rig, path):
    add_dummy_mesh(rig)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in bpy.data.objects:
        ob.select_set(True)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=False, export_yup=True, export_skins=True,
        export_animations=True, export_animation_mode="NLA_TRACKS", export_image_format="AUTO", export_materials="NONE",
        export_cameras=False, export_lights=False, export_force_sampling=True, export_optimize_animation_size=True,
        export_def_bones=False, export_leaf_bone=False)
    print("exported", path, os.path.getsize(path) // 1024, "KB")


def speed_of(take_frames, loop_dur, rig_scale_travel=None):
    return None


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("rig")
    ap.add_argument("set")
    ap.add_argument("--out", default=os.path.join(REPO, "assets/anims"))
    ap.add_argument("--only", default="")
    ap.add_argument("--ual", default=os.environ.get("UAL_FBX", ""))
    a = ap.parse_args(argv)
    t0 = time.time()
    rig = load_rig(a.rig)
    import anim_sets
    ctx = anim_sets.Ctx(rig, a.ual)
    meta = getattr(anim_sets, "build_" + a.set)(ctx, only=a.only.split(",") if a.only else None)
    export(rig, os.path.join(a.out, a.set + ".glb"))
    mp = os.path.join(a.out, "anim_meta.json")
    allm = {}
    if os.path.exists(mp):
        try: allm = json.load(open(mp))
        except Exception: allm = {}
    allm.setdefault(a.set, {}).update(meta)
    json.dump(allm, open(mp, "w"), indent=1, sort_keys=True)
    print("done in %.0fs" % (time.time() - t0))
