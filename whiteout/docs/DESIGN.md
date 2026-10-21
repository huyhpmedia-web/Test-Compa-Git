# WHITEOUT: KETTLE FALLS — Design Bible

A ~60-minute third-person survival-horror game in Godot 4.5 (Forward+). Genre conventions of
late-90s survival horror (scarce ammo, limited inventory, item box, save rooms, key-item
puzzles, backtracking, a stalker) — but an **original story, setting, monsters and mechanics**.
It must NOT read like a Resident Evil clone: no police station, no virus/bio-weapon
corporation lab, no Tyrant/licker/G analogues, no Umbrella-style labs, no trains.

Visual target: **semi-realistic** — PBR, snowy night at −40°, frost, breath vapour, red brick,
volumetric fog, flashlight, strong shadows. Reference art: a snowy courtyard in front of a
red-brick school with a corrugated tool shed and bare trees at night.

## Premise

**December 21, 2026 — the longest night of the year. Kettle Falls, Minnesota**, a dying
iron-range town near the Canadian border. A polar vortex has pushed the temperature to −40°.

Two years ago, two things came to town at once:
- **Northline Mineral** reopened the flooded **Lower Kettle Mine** to pump lithium brine.
- **Corvane Systems** built **MERIDIAN**, a hyperscale AI data centre on the frozen lake, for
  "free cooling". Its contract with the power co-op guarantees Meridian *priority load*: in a
  grid emergency, the town is shed first. Its waste heat is piped down into the mine to thaw
  the brine — sold to the town as "green heat recovery".

The heat woke something sealed in a 10,000-year-old brine pocket: **the Rime** — a cryophilic
colony (part lichen, part fungus, part something else) that lives on *heat*. It takes people
who fall asleep in the cold. Their body heat is drained and replaced with crystalline growth;
they become the **Rimebound**, drawn to warmth and light, carrying heat back down to the colony.
The colony emits a **19 Hz hum** that makes people hear the voices of their dead.

Three nights ago the storm hit. The grid algorithm shed Kettle Falls to keep Meridian online.
The town went dark and cold. People slept in the cold. The Rime came up.

**Themes:** a town turned into a "sacrifice zone" for compute and extraction; infrastructure
that decides whose warmth matters; a father who left coming home too late; grief that speaks
in the voices of the dead. Tone: grounded, cold, quiet, sad — horror through isolation,
silence, and the body.

## Characters

| Name | Role | Notes |
|---|---|---|
| **ELIAS KADE** (38, male) | Player. Power-line technician for Lakeshore Electric Co-op, ex-Army combat engineer. | Grew up in Kettle Falls; left after his father **Tom** died in the 2011 mine collapse. Divorced; hasn't visited in three years. Drove up through the storm when his daughter's calls stopped. Quiet, practical, guilty, dry humour. Look: short dark hair, stubble, weathered face; hi-vis orange/black insulated work jacket with reflective stripes, dark work trousers, tool belt, insulated boots, beanie optional. |
| **JUNE KADE** (15) | Elias's daughter. | Lives with her grandmother. A ham-radio kid: she talks to Elias over a handheld radio through most of the game (guiding, scared, funny, angry that he left). Hiding somewhere — she keeps moving. Found in the mine (L5), half-frozen but alive. Parka, knit hat, headphones. |
| **RUTH KADE** (68) | Elias's mother; retired union nurse. | Ran the school's warming shelter. Hears Tom's voice in the hum and walks into the mine. Becomes the voice of the colony — final boss **THE HOLLOW MOTHER**. |
| **DR. IMOGEN HART** (45) | Northline geologist. | Found the colony 8 months ago and reported it; buried by NDAs. Barricaded inside Meridian's control room. Ally with an agenda (wants a sample to prove she was right). Survives or not depending on player actions. |
| **MERIDIAN** | The data centre's site-operations AI. | Polite, literal, never lies, never cares. Its only goal is uptime. Controls Meridian's doors and power; will help Elias *only* in ways that don't reduce uptime. Voice on intercoms (speaker `MERIDIAN`). |
| **TOM KADE** (deceased) | Elias's father. | Heard only through the hum: hallucinated voice lines, a figure in a mining helmet at the edge of the flashlight. |
| **THE FOREMAN** | The stalker. | Once the mine's night foreman, Gil Arsenault. Now 2.6 m, limbs stretched and jointed wrong by crystalline growth, hard hat with its **headlamp still burning** — he hunts by light. Bullets only stagger him; **fire and flares drive him off**. Heavy, slow, dragging steps + the creak of ice. Appears from L2 end, stalks L3–L4, destroyed in L5. |

## Enemy roster (the Rimebound)

All enemies sense **heat and light**: Elias's flashlight (L key) makes him visible from far
away in dark areas; gunfire and running are loud; sneaking with the light off is a real option.
**Fire** (flares, burning barrels, the flare launcher) deals bonus damage and causes fear.

| type id | Name | Behaviour |
|---|---|---|
| `zombie` | **Shambler** | Frost-crusted townsperson; ice crystals growing from mouth and eyes; slow, grabs. Variants by clothing (civilian, worker, nurse, miner, kid-sized avoided). May fake death. |
| `zombie` + `sleeping` | **Sleeper** | Lies frozen in the snow / on cots; wakes when a light or a warm body comes near. |
| `zombie` + `crawler` | **Crawler** | Legs shattered from frostbite; drags itself; low profile. |
| `husk` | **Husk** | Thick ice plating; bullets chip the armour (armour HP) before damaging; shotgun/fire crack it fast. |
| `siren` | **Siren** | Emaciated, jaw unhinged, throat swollen with resonating crystals; emits the hum to wake/call nearby Rimebound; fragile; flees light. Priority target. |
| `hound` | **Rime Hound** | Frozen sled dog / wolf, fast pack hunter. |
| `burster` | **Burster** | Bloated with frost-spore sacs; when killed or close it bursts into a freezing cloud (damage over time + slows). Shoot from range. |
| `hanger` | **Hanger** | Hangs from ceilings by crystalline filaments, drops on the player, retracts. |
| `foreman` | **THE FOREMAN** | Stalker (see above). Params: `stalk`, `leave_after`, `mortal`. |

### Bosses

| type id | Name | Where | Concept |
|---|---|---|---|
| `boss_choir` | **THE CHOIR** | L3, St. Brendan's church | A dozen congregants fused into a pillar of frozen flesh and ice in the nave, faces still singing the hum. Several heads glow (weak points); destroying them silences the hum. Spawns crawlers, sweeps with fused arms, sends ice-shard waves. |
| `foreman` (mortal) | **THE FOREMAN** | L5, the hoist room | Final fight with the stalker: lure him onto the hoist and burn him with the mine's furnace / flares. |
| `boss_hauler` | **THE HAULER** | L5, the haulage cavern | A mountain of frozen miners fused around a haul-truck driver, dragging itself on dozens of arms; charges, slams, flings ore. Weak point: the driver's exposed torso in the crown. |
| `boss_mother` | **THE HOLLOW MOTHER** | L6, the brine cavern | The colony's heart, wearing Ruth's upper body on a vast crystalline lattice that fills the cavern; speaks in Ruth's and Tom's voices. Phase 1: root tendrils + summons; Phase 2: the lattice cracks, Ruth's body tears free and hunts. |

## Mechanics specific to this game

- **Power restoration** (Elias is a lineman): breakers, disconnects, substations, generators.
  Restoring power opens doors, lights safe rooms and runs lifts — but light and heat also draw
  the Rimebound. Puzzles are electrical in flavour (switching sequences, fuses, phase
  matching, isolating a feeder) — always clued in notes, schematics, or June's radio advice.
- **Flashlight stealth**: light on = see and be seen.
- **Fire**: flares (consumable, thrown/planted light that repels and burns), burning barrels,
  the flare launcher.
- **The hum**: near the colony, hallucinations — Tom's voice, figures at the edge of vision,
  brief audio/visual distortion. Never damaging; purely atmospheric/story.
- **Radio**: June speaks over the radio at key moments (speaker `JUNE (radio)`).

## Level flow (~60 min)

| # | id | Area | Target | Content |
|---|---|---|---|---|
| 1 | `l1_substation` | Highway 53 ditch → Lakeshore Co-op **Kettle Falls substation** → edge of town | 8 min | Elias's bucket truck in a ditch. Tutorial. First Rimebound (sleepers in snow). June's first radio call. The substation: the town feeder was *deliberately shed*; the load-shed order (MERIDIAN PRIORITY) is on the control-house printer. Elias re-closes a feeder by hand (switching puzzle) → the school lights flicker on in the distance → June: "Dad, the school just lit up. Gran's shelter was there." Exit → `l2_school:from_road`. |
| 2 | `l2_school` | **Kettle Falls Consolidated School** — snowy courtyard (reference art), main hall, gym shelter, classrooms, boiler room | 14 min | The town's warming shelter, overrun. Courtyard: shed, bare trees, hounds. Gym: rows of cots with Sleepers. Restore the boiler (valve + fuse puzzle) → warmth + safe room. June's message chalked on a blackboard. Ruth's shelter log. Sirens introduced. Ends with THE FOREMAN's first appearance (cutscene, he drags the shelter caretaker into the dark). Exit → `l3_church:from_school`. |
| 3 | `l3_church` | **Main Street** (diner, pharmacy, hardware store, frozen cars, Northline billboard) → **St. Brendan's church** | 10 min | Foreman stalks Main Street. Hardware store: flares + shotgun. Church: boss **THE CHOIR**. Afterwards Ruth's rosary and the note: "Ruth went down to the mine. She said Tom was calling her." June reveals she followed Ruth. Exit → `l4_meridian:start`. |
| 4 | `l4_meridian` | **MERIDIAN data centre** on the lake: security gate, server halls, cooling plant, control room, heat-pipeline head | 12 min | The only warm, lit place in town — humming servers, cold blue LEDs, and the AI. Dr. Imogen Hart in the control room. The truth: the heat pipeline into the mine. MERIDIAN opens doors only if uptime isn't affected — Elias must trade (re-route power/cooling) to get through. Husks and Bursters in the cooling plant. **Flare launcher** found. Foreman hunts through the server aisles. Exit via the pipeline service tunnel → `l5_mine:start`. |
| 5 | `l5_mine` | **Lower Kettle Mine**: pipeline tunnel, hoist house, drifts, the haulage cavern | 10 min | Tom's hallucinations. The 2011 collapse site. Final fight with **THE FOREMAN** (mortal, fire). Boss **THE HAULER**. Find **June** alive in a refuge chamber, hypothermic. Ruth's voice from below. Exit → `l6_heart:start`. |
| 6 | `l6_heart` | **The brine cavern** — the colony's heart | 6 min | Final boss **THE HOLLOW MOTHER**. Ending choice (see endings). |

Spawn contract:
- `l1_substation`: `start`. Exit → `l2_school:from_road`.
- `l2_school`: `from_road` (courtyard gate). Exit → `l3_church:from_school`.
- `l3_church`: `from_school`. Exit → `l4_meridian:start`.
- `l4_meridian`: `start`. Exit → `l5_mine:start`.
- `l5_mine`: `start`. Exit → `l6_heart:start`.
- `l6_heart`: `start`.

Global flags others may read: `feeder_closed` (L1), `boiler_on`, `met_foreman` (L2),
`choir_dead`, `has_rosary` (L3), `met_imogen`, `imogen_alive`, `pipeline_open` (L4),
`foreman_dead`, `hauler_dead`, `found_june` (L5), `mother_dead` (L6).

## Endings

At the end Elias stands at the pipeline's control in the cavern with June on his back:
- **"DARK"** (`Game.finish_game("dark")`): cut Meridian's heat feed and its power for good.
  The colony starves back into dormancy; the town gets its power back at dawn. Corvane sues the
  co-op; Elias loses his job; the survivors of Kettle Falls live.
- **"THAW"** (`Game.finish_game("thaw")`): open the pipeline to full and boil the cavern —
  destroys the colony and everyone it took, Ruth included, forever. Meridian never goes
  offline; Corvane calls it "a mining accident". Fast, certain, and nobody is ever held to account.

## Gameplay rules

- Resources are scarce: ~1.3 shots per Shambler on average. Shamblers take ~4 pistol body shots
  or ~2 headshots. Place ammo deliberately; reward exploration.
- Every level has at least one **safe room**: warm light, a **field radio** save point, a
  supply crate (item box), music `music_safe`, an Area3D in group `safe_zone`. No enemies inside.
- Key items are consumed by what uses them. 3–6 readable notes per level carry the themes
  (load-shed orders, Corvane PR, Northline incident reports, shelter logs, kids' drawings,
  group texts, Tom's 2011 letters). Dialogue lines ≤ 140 chars; speakers in caps: `ELIAS`,
  `JUNE (radio)`, `JUNE`, `RUTH`, `IMOGEN`, `MERIDIAN`, `TOM?` (hallucination).

## Engine API (read the source)

- `res://levels/level.gd` — base class: override `build()`, `on_enter()`, `try_use_item(id)`,
  `on_pickup(item, uid)`. Helpers: `env_exterior_night()`, `env_interior()`, `box()`,
  `floor_rect()`, `ceiling_rect()`, `wall()` (door gaps), `room()`, `cyl()`, `stairs()`,
  `light()`, `spot()`, `ceiling_lamp()`, `add_spawn()`, `interact()`, `trigger()`, `pickup()`,
  `door()`, `note()`, `save_point()`, `item_box()`, `enemy()`, `say()`, `lock_player()`.
- `res://world/props.gd` — props (crate, barrel, desk, chair, table, shelf, locker, cabinet,
  couch, bed, vending, trash_bags, debris, papers, blood_pool, corpse, car, tree, lamp_post,
  fence, bench, shed, statue, sign, pipe, window + raw box/cyl/sphere).
- `res://core/mats.gd` — `Mats.get_mat(name)` PBR materials; `Mats.color()`, `Mats.emissive()`.
- `Game` autoload (core/game.gd): flags, inventory, hp, objectives, `goto_level`, `finish_game`.
- `UI` autoload (ui/ui.gd): `toast`, `title_card`, `await dialogue(lines)`, `show_note`, fades.
- `Sfx` autoload (core/sfx.gd): `play`, `play_at`, `music`, `ambience`, `attach_loop`.
- `res://actors/enemy.gd` — enemy base; types in `res://actors/enemies/<type>.gd`.
- Item ids: `res://core/items.gd` (only use those ids).

Conventions: metres, +Y up, ground y=0 unless multi-storey. Characters face +Z;
`yaw = atan2(dir.x, dir.z)`. Doorways 1.4–1.8 wide × 2.3 high; corridors ≥ 2.4 m wide; ceilings
3.2–4.5 m. UIDs globally unique, prefixed with the level id.

## Dev tools

- `tools/check.sh <level ids>` — loads every script (prints parse errors) and smoke-runs levels.
- `tools/shot.sh <level> <out.png> [spawn= pos=x,y,z yaw= pitch= frames= flags=a,b]` — 1280×720
  Forward+ screenshot (software Vulkan; ~1–2 min).
