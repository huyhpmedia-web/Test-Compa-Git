# HOLLOW CREEK: WHITEOUT — Design Bible

A ~60-minute third-person survival-horror game in Godot 4.5 (Forward+), a modern (2026)
derivative of the late-90s police-station-outbreak formula. Visual target: **semi-realistic**
— PBR materials, snowy night, wet brick, volumetric fog, flashlight, strong shadows (see the
reference art: a snowy courtyard in front of a red-brick building with a corrugated shed and
bare trees at night).

## Premise

**December 24, 2026. Hollow Creek, Michigan** — a small "smart city" pilot town. Every
service runs through **HALCYON**, a municipal AI contracted from **Aster Genomics**, which also
runs a subsidised subscription gene therapy, **EVERGREEN** ("Never get sick again — $29/month").
EVERGREEN's latest over-the-air booster (yes, its delivery nanocapsules can be re-dosed via the
water supply) mutated. Within 48 hours the town is overrun.

HALCYON's emergency protocol scores every citizen for evacuation priority. Those under the
threshold were never sent help. Aster's cleanup team is quietly destroying evidence before a
federal "sterilisation" strike scheduled for **06:00**.

Themes: algorithmic triage (who decides who is worth saving), health as a subscription
product, corporate cover-up, what you owe the people nobody counted. Tone: grounded, sad,
tense; not campy.

## Characters

| Name | Role | Notes |
|---|---|---|
| **Maya Reyes** (27) | Player. Hollow Creek EMS, first night shift. | Her mother died in 2023 waiting for an ambulance that HALCYON's dispatch routing "deprioritised". She doesn't trust the system but believes in the job. Practical, warm, dry humour under pressure. Ponytail, grey-mauve shirt, dark jeans. |
| **Lily Voss** (12) | Child survivor hiding in the precinct. | Daughter of Helen & Adrian Voss. Wears a smartwatch that is secretly the hardware key to the NEST lab's DAYBREAK synthesiser. Clever, scared, talks to HALCYON like a friend. |
| **Daniel Okafor** (34) | Ex-Aster data engineer, whistleblower. | Arrested on a fake warrant two days ago; locked in the precinct holding cells (L2). Knows about EVERGREEN-Ω and HALCYON's triage logs. Killed by the Collector in L3 after telling Maya where the evidence server is. |
| **Dr. Helen Voss** | Aster lead scientist, EVERGREEN's creator. | Wants to stop it, but also to protect her work and Lily. Synthesised the only counter-agent, **DAYBREAK**. Dies in L5 after helping Maya. |
| **Dr. Adrian Voss** | Helen's husband, Aster VP of Research. | Injected himself with EVERGREEN-Ω when Aster's cleanup team came for the samples. Becomes **PATIENT ZERO**, the escalating final boss (seen briefly in L4, fought in L6). |
| **IRIS** | A calm female voice on Maya's phone/PA speakers. | Presents as a "FEMA coordinator". She is actually a HALCYON persona, executing Aster's contract: retrieve the DAYBREAK sample and destroy the evidence drive. Revealed in L5. |
| **THE COLLECTOR** | Aster cleanup bio-weapon. | 2.3m tall, long grey coat, black mask with blue visor slit. Invulnerable: can be staggered, never killed until L5. Slow heavy footsteps that can be heard through walls. |
| **Chief Warren Hale** | Police chief, on Aster's payroll. | Appears via notes and as a corpse in L3; he covered for Aster and signed Daniel's fake warrant. |

## Level flow (~60 min)

| # | id | Area | Target time | Key content |
|---|---|---|---|---|
| 1 | `l1_overpass` | Route 9 overpass → Main Street → gas station → precinct gate | 8 min | Ambulance crash (wakes up), tutorial, first zombies, IRIS phone call, **bolt_cutter** + **gate_fuse** gating; reaches precinct courtyard gate. |
| 2 | `l2_precinct` | Courtyard (reference art) → precinct main hall → west wing (offices, save room, holding cells) | 15 min | Side entrance via **precinct_key** (in shed), main hall statue with 3 empty seal slots, save room + item box, Daniel in holding cell (talk), **valve_handle**, **keycard_blue** unlocks the east wing door. Shotgun here. |
| 3 | `l3_east` | East wing corridor → records library → chief's office → clock-tower roof | 12 min | Find Lily hiding in a library vent. **seal_lion/owl/stag** collected across the area. Collector introduced (stalks). Daniel killed (cutscene). Flayer enemy. Hip pouch. Return to L2 hall. |
| 2b | `l2_precinct` (return) | Main hall | — | Insert the 3 seals into the statue → floor opens → stairs to basement → L4. |
| 4 | `l4_sewers` | Precinct basement garage → sewers → water-control → service lift | 10 min | **crank**, 3 colour **plug** puzzle (clue note gives order), Swollen boss, Patient Zero glimpse takes Lily (she's injured/infected), magnum. |
| 5 | `l5_lab` | Aster NEST lab: atrium, power plant, Helen's office, synth lab, server room | 12 min | Restore power, **aster_id**, Helen's death, **daybreak** synthesis (needs Lily's watch flag), **drive**, IRIS reveal, Collector final fight (launcher). |
| 6 | `l6_train` | Freight shuttle platform + moving train car | 6 min | **train_key**, Patient Zero final boss (2 phases), DAYBREAK given to Lily, ending choice → `Game.finish_game("truth" or "silence")`. |

Spawn names between levels (contract):
- `l1_overpass`: `start` (crash site). Exit → `l2_precinct:from_street`.
- `l2_precinct`: `from_street` (courtyard gate), `from_east` (east wing door, inside hall), `from_basement` (if returning). Exit east → `l3_east:from_hall`. Exit basement (after seals) → `l4_sewers:start`.
- `l3_east`: `from_hall`. Exit → `l2_precinct:from_east`.
- `l4_sewers`: `start`. Exit → `l5_lab:start`.
- `l5_lab`: `start`. Exit → `l6_train:start`.
- `l6_train`: `start`.

Global flags other levels may read: `met_daniel`, `daniel_dead`, `found_lily`, `seals_placed`,
`lily_taken` (L4), `lily_watch` (Maya has Lily's watch key — set in L4), `power_on` (L5),
`helen_dead`, `iris_revealed`, `collector_dead`.

## Gameplay rules

- Resources are scarce: ~1.3 shots per zombie on average across the game. Zombies take ~4
  handgun body shots or ~2 headshots. Place ammo deliberately; reward exploration.
- Every level has at least one save point (field recorder) + item box in a "safe room" (warm
  light, calm music `music_safe`). Never put enemies inside safe rooms.
- Key items are consumed by the door/mechanism that uses them (default door behaviour).
- Each level should include 3–6 readable notes (files) that deepen the story and give puzzle
  hints. Notes are where the modern themes live: HALCYON score letters, EVERGREEN ads, cop
  group chats, Aster internal email, a kid's diary, a subreddit thread printout, etc.
- Dialogue lines are short (≤ 140 chars each). Speakers in caps: `MAYA`, `IRIS`, `LILY`, `DANIEL`,
  `HELEN`, `ADRIAN`, `HALCYON` (PA system).

## Engine API (read the source for details)

- `res://levels/level.gd` — base class for levels. Override `build()`, `on_enter()`,
  `try_use_item(id)`, `on_pickup(item, uid)`. Helpers: `env_exterior_night()`, `env_interior()`,
  `box()`, `floor_rect()`, `ceiling_rect()`, `wall()` (with door gaps), `room()`, `cyl()`,
  `stairs()`, `light()`, `spot()`, `ceiling_lamp()`, `add_spawn()`, `interact()`, `trigger()`,
  `pickup()`, `door()`, `note()`, `save_point()`, `item_box()`, `enemy()`, `say()`, `lock_player()`.
  Static geometry goes under `geo` (NavigationRegion3D) and nav is auto-baked.
- `res://world/props.gd` — prop library: crate, barrel, desk, chair, table, shelf, locker,
  cabinet, couch, bed, vending, trash_bags, debris, papers, blood_pool, corpse, car (sedan / van /
  ambulance / police), tree, lamp_post, fence, bench, shed, statue, sign, pipe, window, plus raw
  `box/cyl/sphere` builders.
- `res://core/mats.gd` — `Mats.get_mat(name)` shared PBR materials (triplanar world UVs) with
  textures from `res://textures/<name>_{albedo,normal,rough}.png`; `Mats.color()`,
  `Mats.emissive()`.
- `res://core/game.gd` (autoload `Game`) — flags, inventory, hp, objectives, level flow:
  `Game.set_flag/has_flag/get_flag`, `Game.add_item/remove_item/has_item`,
  `Game.set_objective(text)`, `Game.goto_level(id, spawn)`, `Game.finish_game(ending)`.
- `res://ui/ui.gd` (autoload `UI`) — `UI.toast()`, `UI.title_card()`, `await UI.dialogue(lines)`,
  `UI.show_note()`, `UI.show_item_get()`, `UI.fade_out/in()`.
- `res://core/sfx.gd` (autoload `Sfx`) — `Sfx.play(name)`, `Sfx.play_at(name, pos)`,
  `Sfx.music(name)`, `Sfx.ambience(name)`, `Sfx.attach_loop(name, node)`. Files in `res://audio/`.
- `res://actors/humanoid.gd` — procedural human (setup(cfg); drive `move_speed`, `pose`, `aim`,
  `play(anim)`).
- `res://actors/enemy.gd` — enemy base; types in `res://actors/enemies/<type>.gd`, spawned with
  `enemy(uid, type, pos, yaw, params)`.

Conventions: coordinates in metres, +Y up, ground at y=0 unless multi-storey. Character models
face +Z; `yaw = atan2(dir.x, dir.z)`. A standard doorway is 1.2–1.8 wide × 2.3 high; corridor
width ≥ 2.4 m (camera needs room); ceilings 3.2–4.5 m. UIDs are globally unique: prefix with the
level id (e.g. `l2_ammo_3`).

## Dev tools

- `tools/check.sh <level ids>` — loads every script (prints parse errors) and smoke-runs levels.
- `tools/shot.sh <level> <out.png> [spawn=.. pos=x,y,z yaw=.. pitch=.. frames=.. flags=a,b]`
  — renders a 1280×720 screenshot with Forward+ (software Vulkan, slow: ~1 min).
