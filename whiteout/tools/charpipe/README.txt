Whiteout character pipeline (MakeHuman CC0 data + Blender-as-a-module -> glTF)
==========================================================================
Setup (once):
  pip install uv && uv python install 3.11 && uv venv --python 3.11 venv && venv/bin/pip install bpy==5.0.1 numpy pillow
Data cache (not in the repo, ~300 MB; set CHARPIPE_CACHE to its location):
  mh/makehuman   - raw.githubusercontent.com/makehumancommunity/makehuman/master/makehuman/data/{3dobjs,targets,eyes}
  mh/mpfb2       - raw.githubusercontent.com/makehumancommunity/mpfb2/master/src/mpfb/data/{rigs/standard,mesh_metadata}
  assets/        - tools/charpipe/fetch_assets.py (CC0 MakeHuman system assets: clothes/hair/eyes/skins)
  bvh/           - CMU mocap: tools/charpipe/fetch_assets.py bvh 35_01 09_01
Build:
  CHARPIPE_CACHE=... venv/bin/python tools/charpipe/build_characters.py [--only elias,june,...] [--no-anim] [--out DIR]
Files:
  mh_lib.py      MakeHuman base mesh / targets / macro blending / mhclo proxy fitting
  bl_common.py   Blender helpers          paint.py   position-driven UV texture painting
  specs.py       character specs + Elias assembly (hi-vis jacket, belt, boots, gloves)
  chars2.py      June, Ruth, Rimebound bodies
  anim.py        BVH retarget + keyframe authoring engine   bvh.py  BVH parser   clips.py  all clips
Godot: actors/character_model.gd wraps the glb with the same API as actors/humanoid.gd.
