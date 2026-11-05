# assets/anims: animation-only glbs (retargeted mocap on the Whiteout MakeHuman/MPFB2 rig)

Built by `tools/charpipe/anim_export.py` (+ anim_sets.py, anim_src.py). `elias.glb` drives Elias and the NPCs, `zombie.glb` drives every
Rimebound and special. The clips override the clips embedded in assets/characters/*.glb by name; the character glbs may be mesh-only.
`anim_meta.json` holds per-clip duration and locomotion speed (m/s).

| Source | Used for | Licence |
|---|---|---|
| CMU Graphics Lab Motion Capture Database (mocap.cs.cmu.edu; BVH conversion by B. Hahne, mirrored at github.com/una-dinosauria/cmu-mocap) | walk, run, strafe/back-pedal, run-to-stop, turn-in-place, zombie/drunk/limp/old-man shambles, idles, lunge/grab, get-ups, crawl, stagger, struggle, chop | "free for all uses" (CMU) |
| Quaternius Universal Animation Library, Standard (quaternius.com; CC0 FBX via github.com/IAFahim/quaternius.universalAnimationLibrary.standard) | pistol idle/aim/shoot/reload, sword/hatchet swings, punches, hit-chest/head, death, interact, pick-up, torch idle, roll, sprint, idle | CC0 1.0 |
| 100STYLE (Mason, Starke, Komura) | NOT used: dataset host unreachable from the build environment; retarget hook exists (anim_src.bvh_take works on its BVH) | CC BY 4.0 |

Credits text: "Motion capture: CMU Graphics Lab Motion Capture Database (mocap.cs.cmu.edu), funded by NSF EIA-0196217. Quaternius Universal Animation Library (CC0)."
