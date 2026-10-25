# Project status (for resuming work)

Branch: `claude/tender-clarke-ld6xjw`. Work is autosaved (commit + push) every ~8 minutes while agents run.

## Done
- Core engine: game state, inventory, saves, UI, player controller, level builder API, FX, audio manager.
- Story bible: `docs/DESIGN.md` (Whiteout: Kettle Falls — male lead Elias Kade).
- Audio: `audio/` (CC0 / CC-BY, see `audio/LICENSES.md`).
- Textures: `textures/` (ambientCG / Poly Haven CC0 via mirror, see `textures/LICENSES.md`).
- Six levels: `levels/l1_substation.gd` … `levels/l6_heart.gd` (smoke-tested, not yet fully playtested).
- Enemy roster + bosses + NPCs (procedural models): `actors/enemies/`, `actors/models/`, `actors/npc.gd`.
- MakeHuman/Blender character pipeline: `tools/charpipe/` → `assets/characters/*.glb`, wrapper `actors/character_model.gd`.

## In progress
1. Swap all humans/zombies to MakeHuman models with frostbite + baked gore (character pipeline).
2. Gore & fluids system (`world/gore.gd`, `world/fx.gd`, `levels/dressing/<id>_dress.gd`).
3. Bosses + hound rebuilt in Blender (`tools/charpipe/bosses/`, `assets/enemies/`).
4. Automated playtests and bug fixes (`tools/playtest.*`).

## Next
- Integrate & verify all of the above in every level; screenshots per level.
- Full chain playtest l1 → l6 → endings; balance ammo/health.
- Export a playable build (Linux/Windows/Web) and a project zip for the Godot web editor.

## Tools
- `tools/check.sh <level ids>` — parse all scripts + smoke-run levels.
- `tools/shot.sh <level> <out.png> [pos= yaw= pitch= frames= flags=]` — screenshot (Forward+, software Vulkan).
- Godot 4.5.1 binary is downloaded to the session scratchpad (re-download from GitHub releases if missing).
