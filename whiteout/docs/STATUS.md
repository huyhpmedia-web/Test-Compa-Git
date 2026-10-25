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

## In progress (as of Oct 25, 16:50 UTC)
1. Integrating Higgsfield/Tripo boss models (concepts: docs/boss_concepts.png, picks 2/3/6/7/10).
   Raw GLBs live outside git in the scratchpad `tripo_raw/` (not in history; history was purged of them).
   Target: assets/enemies/{choir,hauler,mother_p1,mother_p2,hound}_hd.glb (<= 8 MB each) wired into actors/models/*.
   If interrupted: resume that agent, or re-download from Higgsfield job ids:
   choir 5f44f178-ade0-4013-bb4b-d6fc82207d49, hauler c5bddf16-d589-4940-8f82-e7b9252e4c9d,
   mother_p1 83ba5d35-bfc2-42c1-8eed-941e5d60be82, mother_p2 6136d145-af79-4e84-a443-786b8d540b7f,
   hound 5e6b380b-845c-419e-95ff-432bc7c468d0 (Higgsfield credits already spent: 92.4).

## Done since last update
- All humans/zombies are MakeHuman glbs (actors/character_model.gd), frostbite + baked gore, 21 animations.
- Gore & fluids system (world/gore.gd, levels/dressing/*_dress.gd), screen blood, head pops, limb loss.
- QA harness: tools/playtest.sh [level|all|chain|soak] — full chain l1 -> ending passes.

## Next
- Verify boss fights in real arenas with the HD models; screenshots per level.
- Full chain playtest + balance; export playable builds (Linux/Windows/Web) and a project zip.
