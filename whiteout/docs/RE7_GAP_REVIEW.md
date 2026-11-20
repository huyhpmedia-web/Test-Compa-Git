# WHITEOUT: KETTLE FALLS: RE7 Gap Review (Nov 20, 2026)

**Reviewer:** game director / art and experience critic. **Benchmark:** *Resident Evil 7 biohazard* (2017). That means photogrammetry environments, baked GI with heavy grime, filmic post (grain, CA, vignette, lens dirt), bespoke Molded enemies, first-person body awareness, binaural audio, and fully voiced, staged cutscenes.
**Scope:** this is a snapshot of the build while five agents are still swapping assets (town exteriors, L2/L3 interiors, L4-L6 environments, characters, items). Scores describe **what is in the repo now**, not what is promised.

## Evidence (`docs/review_re7/`)

| # | File | What it shows |
|---|---|---|
| 01 | `01_l1_spawn_highway.jpg` | L1 start (my `tools/shot.sh` capture). Blobby putty drifts, a clean road, flat blue moon light, black rectangles on the snow left and right. |
| 02 | `02_l1_school_gate_spike_bug.jpg` | L1/L2 gate. **A black blade-shaped mesh sticks out of the back of Elias's head/hood.** It is visible in every OTS frame (also in 03, 04, 05, 06, 13). |
| 03 | `03_l2_courtyard_dialogue.jpg` | L2 exterior. This is the best-looking shot in the game. The Sketchfab school, bare trees and the barrel fire work. The dialogue is a plain text box. |
| 04-06 | `04/05/06_l6_*.jpg` | L6 mine mouth and cavern. Crystals are untextured white extrusions. Orange glow sticks float in the air. A blood decal sits on a raised square card. The floodlight is a white quad. June is still the old MakeHuman model with a clay face. |
| 07-08 | `07_elias_trio.jpg`, `08_elias_face.jpg` | Elias HD (Meshy). The body is good at distance. Close up, the face is waxy, the lighting is baked into the albedo, the hair is a painted cap and the eyes are dead. There is no facial rig. |
| 09 | `09_zombie_tee_m.jpg` | Rimebound base zombie. Low detail, painted-on blood, **spotless white sneakers**, a tiny grey face. |
| 10-12 | `10/11_roster_style_clash_*.jpg`, `12_zombie_lineup.jpg` | Character agent's current roster. **Three art styles at once:** a cartoon Sketchfab nurse with giant teeth, a lime-green-faced cop, a glossy latex ninja, a PS2-grade fat man with torn UVs, an untextured grey trench-coat figure, and MakeHuman bodies. |
| 13 | `13_elias_anim_run_walk_aimidle.jpg` | Run and walk mocap are fine. With no weapon, `aim_idle` is a crossed-arms pose. The head spike shows on every frame. |
| 14-18 | `14..18_ui_*.jpg` | Inventory, item get, menu, Vietnamese dialogue, note. |
| 19-20 | `19_item_models.jpg`, `20_npc_june_hd.jpg` | New item models (decent) and the HD June (decent, but not yet in the level, see 04). |
| 21-23 | `21..23_*_prev_round.jpg` | L4 lobby, L3 Main Street and L5 tunnel. These are **previous-round** captures from `docs/progress/` because fresh interior renders were OOM-killed (see Performance). |

Capture note: every fresh L2-L6 level render I attempted, about 14 of them (`shot.sh` and `shot_multi`), was **OOM-killed** while 3-4 peer agents were rendering at the same time. A level load peaks at 3-4+ GB RSS under llvmpipe. Evidence 04-06 and 10-12 are peer agents' captures of the current build from today.

## Scores (1-10, RE7 = 10)

| Category | Score | Blunt justification |
|---|---|---|
| Environments: exterior | **4.5** | The best category. Snow, fog and the Sketchfab houses read as "real". But the drifts are smooth noise blobs with no wind sculpting or sparkle. The asphalt is clean, with a hard edge against the snow (no tyre ruts, slush or plow berms). Spaces are wide, empty and evenly lit. RE7 is claustrophobic and dense with clutter. |
| Environments: interiors | **3.5** | The L4 lobby is a sterile CG box: grid ceiling, repeating black wall slats, floating paper cards. The L6 cavern has untextured crystal shards and floating light sticks. L2 and L4 interiors are lit by the **exterior sky ambient** (`env_exterior_night` for the whole level, `l2_school.gd:61` and `l4_meridian.gd:66`), so rooms are washed flat. There is no clutter density of the Baker-house kind. |
| Lighting & post | **3.5** | No GI of any kind (no SDFGI, VoxelGI, LightmapGI or ReflectionProbe anywhere; `ssil_enabled=false`). Exposure is fixed. There is no film grain, chromatic aberration, lens dirt or DOF. The only vignette is a HUD ColorRect. One `_common_post()` grades all six levels identically. Shadow-casting lights are scattered without a key/fill plan. The flashlight is the only good light. |
| Materials / decals / grime | **3** | Decals exist only for gore (`world/gore.gd`). The L1, L4, L5 and L6 dressing files use **zero decals**. There are no leak stains, mould, soot, grime gradients at wall bases, wet floors or frost-on-glass decals. Blood pools render as raised cards (05). RE7's look is about 50% grime. |
| Characters & faces | **4** | The Elias HD body is about a 6. His face is about a 3.5 (waxy, baked light, no blendshapes, no jaw bone). The head-spike bug is visible in every gameplay frame. In-level NPCs are still old MakeHuman (June in L6). The HD NPCs exist but have not landed. |
| Zombies | **2.5** | This is a style catastrophe in progress. Cartoon Sketchfab zombies sit next to MakeHuman bodies and a PS2 fat man. Clothes are clean and there are white sneakers. RE7 uses one bespoke enemy family (Molded) with a consistent material language. Nothing here is frightening at OTS distance. |
| Animation & feel | **4** | Mocap locomotion is acceptable. There is no foot IK, no jaw or lip animation, and a broken empty-hand `aim_idle`. The OTS camera with FOV 62 has no head-bob, breathing sway or flashlight sway. RE7's dread comes from first-person, slow speed and close framing. |
| Weapons & combat feedback | **5** | Real meshes, recoil springs, casings, impacts and hit-stop all exist. But there is **no guard/block**, which is RE7's core defensive verb. Enemy hit reactions are small. The item-get view shows the shotgun tiny and end-on (15). |
| UI / UX / onboarding | **3.5** | Inventory, notes and menu are generic dev-panel boxes. The pistol icon (white Walther-like) **does not match** the 3D model (rusty 1911). Icons are grey studio photos on a black UI. Objective text is duplicated with the toast (21), and the title card covers gameplay. Onboarding is a single toast, "WASD - move, SHIFT - sprint". Aim, shoot, interact, inventory, quick-turn and flare are never taught in context. L1's opening task is an **8-step electrical switching puzzle** written in jargon (hot stick, DS-2A, BKR-KF2, 60A fuse). That is why the owner got stuck. There is no map. |
| Audio | **4** | Library coverage is broad: per-enemy groans, hits and deaths in a/b/c variants, surface steps, gun tails. But there is **no voice acting at all**, no `default_bus_layout.tres` (no reverb or EQ buses, no room zones), no occlusion, one 2D ambience loop per level, 6 music cues, and several procedural synth layers. RE7's audio is a 9-10. |
| Narrative presentation | **2** | Text box plus speaker name, and that is all. No cutscenes, no camera staging, no VO, no lip sync, no letterbox. `player.input_locked` exists but is barely used. RE7's dinner scene alone outclasses the whole presentation. |
| Performance risk | **4** | Levels are built at runtime in GDScript (1.2-2k-line builders). That means no baked lighting, occlusion or LOD (only about 10 `visibility_range`/occluder uses in the codebase). 188 glbs totalling 445 MB, with 5.5 MB per street pole. Load peaks at 3-4+ GB RAM. Every level has volumetric fog, SSR and SSAO, plus dozens of shadowed omnis (L3 builder: about 83 `shadows=true` call sites). |
| **Overall** | **~3.8** | The mood at distance is good. Up close, in motion and in narrative, this is a mid-2000s indie horror game, not RE7. |

## What asset swaps can fix vs. what needs engine or rendering work

**Asset swaps (agents can do now):** zombie roster, NPC faces, interior clutter density, decal packs, item icons, crystals and rocks in L5/L6, drift meshes, VO lines.
**Engine/system work (code owner):** GI, reflection probes, the post stack, per-room environments, camera mode, guard mechanic, cutscene system, audio buses and zones, onboarding flow, level freezing for baking and occlusion.

## Prioritised action list (to reach 8+ per category)

### P0: blockers (this week)
1. **Kill the head-spike bug.** Find the black blade-shaped mesh on the Elias HD rig. It is present in `char_view`, `anim_sheet` and in-game, so it lives in `assets/characters/elias.glb` or a `character_model.gd` attachment. Delete it or re-parent it. *(asset / 1 h)*
2. **Pick ONE zombie art direction and purge the rest.** Rule: photoreal, frost-and-necrosis, the same skin shader for all. Remove the cartoon Sketchfab zombies (giant-teeth nurse, green cop), the latex ninja, the PS2 fat man and the untextured trench coat. Rebuild 6-8 bodies as photogrammetry or scan-based humans: Meshy/Higgsfield photoreal, the same pipeline as Elias HD (`tools/charpipe/hd_elias.py`). Add a shared `rime_look.gd` overlay: frost in cavities, grey-blue lividity, black frostbite on fingers and nose, **dirtied shoes**. *(asset, characters agent)*
3. **Rewrite the L1 onboarding** (`levels/l1_substation.gd`):
   - Teach interact, aim, shoot, flashlight, inventory and quick-turn with context prompts at the first use point. Use `UI.set_prompt` with key glyphs, not one toast at t=3.5 s.
   - Collapse the switching puzzle to **3 player-visible steps**: get the key, get the fuse, throw the breaker. Keep the DS-2A/2B order only as optional flavour.
   - Rename items in plain words ("Insulated pole", not "hot stick").
   - Add a world-space beacon light on each target, not only the small ◆ glyph.
   - Add an **objective re-show key** and a **map screen** (top-down auto-map per level from the builder rects).

   *(engine/UX)*
4. **Per-room interior environments for L2 and L4.** Use `_set_inside()` zone switching the way L3 does. Run `env_interior()` with ambient 0.05-0.1 inside, so rooms stop getting exterior sky ambient. This is the single cheapest lighting win. *(engine, 1 day)*

### P1: rendering (lighting & post from 3.5 to 8)
5. **Global illumination.** Exteriors: enable SDFGI (`sdfgi_enabled`, `use_occlusion=true`, cascades 4, `min_cell_size` 0.2). Interiors: **freeze each level into a `.tscn`** with a tool that runs `build()` in the editor and packs the scene, then **bake LightmapGI** (static-only, directional off). Fallback: one VoxelGI per major room, baked at load. RE7's look is baked bounce light; without it nothing reaches 8.
6. **Reflection probes** (UPDATE_ONCE) per room and in the L4 halls, plus wet-floor roughness maps. Metal, glass and the L4 terrazzo are dead right now.
7. **A real post stack.** Add a full-screen `CanvasLayer` or compositor effect with:
   - film grain at about 0.04, animated per frame
   - chromatic aberration of 1-1.5 px at the edges
   - vignette in the scene pass, not the HUD
   - lens dirt on glow
   - **auto exposure** (`CameraAttributesPractical` `auto_exposure_enabled`, scale 0.4, so a flashlight in darkness blooms properly)
   - DOF far blur in cutscenes
   - a per-level LUT (`adjustment_color_correction`), e.g. cold teal L1-L3, sodium amber in the L5 mine, sick cyan in L6

   Do this in `levels/level.gd::_common_post()`, with per-level overrides.
8. **Lighting design pass.** One motivated key light per space (practical fixtures with IES-like cookies via `light_projector`), cut ambient to near zero, and leave 60% of every frame in shadow. Set flashlight `shadow_blur` and add a projector texture with a hot ring and dust. Cap shadowed omnis at about 8 visible and use `distance_fade` on the rest.

### P1: materials & grime (from 3 to 8)
9. **Decal pass on every level.** Build a library of 30-40 CC0 decals (leak streaks, mould blooms, soot above heaters, grime at wall bases, boot prints, frost on glass, water rings, posters, graffiti, blood drag marks) in `levels/dressing/dress_util.gd`. Target at least 150 decals per level, plus vertex or texture **height-blend grime** on the lower 40 cm of every wall material (`core/mats.gd` triplanar overlay). Replace the "blood on a raised card" pools with projected decals. *(asset + small code)*

### P1: characters & animation (to 7-8)
10. **Faces.** Add ARKit 52 blendshapes or at least jaw, blink and brow to Elias, June, Ruth and the Caretaker (Meshy HD to Blender: Faceit or a manual jaw/lip rig). Drive jaw-flap and blink from dialogue. Re-texture the Elias face with de-lit albedo, an SSS-capable material (`subsurf_scatter_strength` 0.3), strand-card hair and wet-eye shaders. Land the HD NPCs in the levels: L6 still shows the old June.
11. **Camera feel.** Decide this now: **switch to first-person with a body** (RE7) or commit to a tight RE2R-style OTS. If OTS:
    - spring length 1.6, FOV 55-58
    - walk speed down 20%
    - procedural head-bob, breathing sway and flashlight lag on the camera
    - foot IK (`SkeletonIK3D` or a two-bone solver) on stairs and snow
    - fix the empty-hand `aim_idle`

    First-person is a bigger change (arms rig, weapon views) but is the honest RE7 answer.

### P2: combat, UI, audio, narrative
12. **Guard mechanic.** Add guard on a held button: arms up, 60-80% damage reduction, and a guard-break if attacked from behind. Add bigger enemy stagger and limb reactions (cripple a leg into a crawl), plus a camera **grab/bite sequence** with a struggle prompt. RE7 combat is a defensive stamina dance; ours is plain shooting.
13. **UI art pass.**
    - Re-render every item icon from its own 3D model in `ui/item_view.gd`'s viewport (matching lighting, transparent background), so the pistol icon matches the 1911.
    - Make the inspect view fill 60% of the screen with a 3/4 hero angle and rim light.
    - Use a diegetic or tactile UI skin (worn paper, tape, a lineman's notebook) instead of grey boxes.
    - Remove the duplicated objective/toast lines, and stop showing the title card over live gameplay.
14. **Audio systems.**
    - Add `default_bus_layout.tres` with Master, SFX, Music, VO and Amb buses, `AudioEffectReverb` per zone (Area3D `reverb_bus_enable` for school halls, church, mine and cavern), and low-pass occlusion via raycast to 3D emitters.
    - Spawn 3-6 positional ambient one-shots per room (creaks, drips, distant thuds) instead of one 2D loop.
    - **Record or TTS voice-over** for every dialogue line (ElevenLabs or Higgsfield voice; about 200 lines EN and VI).
15. **Cutscene / staging system.** Build a `Cutscene` node: `AnimationPlayer` driving `Camera3D`, letterbox, `input_locked`, subtitle track and VO cue. Then stage the 6 key beats as 15-40 s in-engine scenes with camera cuts: the June radio call, meeting the Foreman, the choir reveal, Dr. Hart in the NOC, Tom in the cavern, the Mother reveal, and the ending. This is RE7's single biggest advantage over us.

### Performance (do alongside 5)
- Freezing levels to `.tscn` also unlocks `OccluderInstance3D` baking and `visibility_range` HLOD.
- Recompress glbs: VRAM-compressed textures, max 2K for props and 1K for small items. The street poles at 5.5 MB each are absurd.
- Target under 2 GB RSS per level.
- Budget: at most 8 shadowed dynamic lights in view, volumetric fog `volume_size` 64 and depth 48 on low settings.
- Profile L2 and L3 on a mid GPU before adding more geometry.

## Expected scores after actions

| Category | Now | After actions |
|---|---|---|
| Ext / Int | 4.5 / 3.5 | 8 / 7.5 (needs 5, 8, 9) |
| Lighting & post | 3.5 | 8 (4-8) |
| Materials | 3 | 7.5 (9) |
| Characters | 4 | 7 (1, 10) |
| Zombies | 2.5 | 7 (2) |
| Animation & feel | 4 | 7 (11) |
| Combat | 5 | 7.5 (12) |
| UI / UX | 3.5 | 7.5 (3, 13) |
| Audio | 4 | 7.5 (14) |
| Narrative | 2 | 7 (15) |

Honest ceiling: without first-person, baked GI and professional VO, this project tops out around 7, not 8, against RE7.
