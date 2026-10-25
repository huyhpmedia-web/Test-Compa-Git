# Character assets - sources and licenses

All third-party data used to build `elias.glb`, `june.glb`, `ruth.glb` and `rimebound_*.glb` is CC0 / public-domain /
free-for-any-use.  Nothing here requires attribution, but the sources are recorded for provenance.
The glb files are produced by `tools/charpipe/build_characters.py` (Blender 5.0 as a Python module, `pip install bpy`).

| Data | Source (fetched via raw.githubusercontent.com / pypi) | License |
|---|---|---|
| Base human mesh (`3dobjs/base.obj`, hm08), macro/detail morph targets (`targets/**`), eye texture `eyes/materials/brown_eye.png` | https://github.com/makehumancommunity/makehuman (`makehuman/data/...`) | CC0 1.0 (repo `LICENSE.ASSETS.md`) |
| Rig definition + vertex weights `game_engine` (`rig.game_engine.json`, `weights.game_engine.json`), vertex-group metadata | https://github.com/makehumancommunity/mpfb2 (`src/mpfb/data/rigs/standard`, `mesh_metadata`) | CC0 1.0 (repo `LICENSE.ASSETS.md`) |
| MakeHuman system assets: clothes `male_casualsuit03/04/05/06`, `male_worksuit01`, `female_casualsuit01`, `female_elegantsuit01`, `shoes02/04/05/06`; hair `short02/03/04`, `bob01/02`, `ponytail01`; `eyebrow001/002`; `eyelashes01`; low-poly eyes; skins `middleage/young/old_caucasian_male/female` | CC0 mirror of the MakeHuman system assets: https://github.com/vidya-hub/makehuman-core (`data/clothes|hair|eyebrows|eyelashes|eyes|skins`) - files carry the header "explicitly released as CC0 in september 2020" (Data Collection AB / J. Palmius / J. Hauquier) | CC0 1.0 |
| Motion capture: walk `35_01`, run `09_01` | CMU Graphics Lab Motion Capture Database (mocap.cs.cmu.edu), BVH conversion by Bruce Hahne (cgspeed.com), mirrored at https://github.com/una-dinosauria/cmu-mocap (`data/035/35_01.bvh`, `data/009/09_01.bvh`) | "free for all uses" (CMU: "This data is free for use in research projects... free for any use", READMEFIRST.txt of the BVH release) |
| Blender (bpy) | https://pypi.org/project/bpy/ (5.0.1) | GPL-3.0-or-later (tool only; no Blender code is shipped in the game) |

Original work for this project (CC0, dedicated by the project): all Rimebound frostbite skins and baked gore (blood, wounds, torn flesh, wet roughness + normal maps; `tools/charpipe/gore.py`, `zombies.py`), husk/siren/burster/hanger/foreman bodies (MakeHuman morph targets + procedural pieces), the hi-vis jacket / parka / cardigan / trouser / boot / glove
textures (derived procedurally from the CC0 clothing UV layouts - see `tools/charpipe/specs.py`, `chars2.py`), tool belt and pouches,
stethoscope, beanie, hard hat, headphones, stubble/weathering baked into the skin texture, and all authored animations
(idle, aim_idle, shoot, reload, hurt, stagger, death (4 variants), getup, hang, hatchet_swing, knife, heavy, zombie_idle, zombie_walk (CMU legs + authored upper body),
zombie_attack/attack, grab, roar, crawl, sit).  `walk` and `run` are retargeted CMU mocap (see above).

Not used (license incompatible): MakeHuman's bundled `zombieWalk1.bvh` (AGPL-3.0).
