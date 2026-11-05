# Whiteout: Kettle Falls — Art & Animation Review (Nov 2026)

The benchmark is a 2026 AA third-person horror game (RE2/RE4 Remake, TLOU2, Alan Wake 2: semi-realistic PBR, believable rigs, mocap).
Evidence is in `docs/review/*.jpg`. Raw renders are in the scratchpad `review/` folder. Renders came from `tools/shot.sh`, `tools/char_view` and a scratch helper that steps the real `CharacterModel` AnimationTree frame by frame.

**Verdict:** the lighting, snow and fog are strong, and so are the bosses. Everything you touch or look at closely is still prototype quality: the gun, the hands, the zombies, cars, trees, houses and fire. The owner's feedback is correct on every point, and the problems go further than he said. The biggest gap is the weapon: the pistol is **two boxes**, and nothing holds it. The second biggest is the world: **every prop is a Godot primitive** (`world/props.gd`). There is not a single real 3D environment model in the game.

## 1. Scores (1–10 against the 2026 AA horror benchmark)

| Area | Score | One-line justification |
|---|---|---|
| Snow ground, night sky, fog, flashlight (approved) | 7 | Good PBR snow and asphalt, moody fog and nice flashlight pools. Drifts are perfect flat discs, which looks fake (`09`). |
| Bosses: Choir, Hauler, Mother, Hound HD (approved) | 7 | Real sculpted meshes with PBR maps. Scary, and they read well in the arenas. The only real-asset tier in the game. |
| Lighting / grading | 6 | Solid mood. Interiors are flat and evenly lit (`12`). No reflection probes or GI, so metal and glass look dead. |
| Elias model | 4 | MakeHuman base is passable. The hair has holes and a "clay helmet" hairline. The tool belt is boxes. The jacket is a painted texture with no cloth detail (`03`). |
| Elias animation | 2 | CMU walk and run are OK. Aim, shoot, reload and hatchet are hand-keyed in code and read as robotic. The hands never grip anything (`01`, `08`). |
| Weapons | 1 | Pistol = 2 boxes. Shotgun = 3 boxes. Revolver = 3 boxes. Launcher = cylinder + box. Hatchet ("knife") = 2 thin boxes (`fx.gd:21`). |
| Shooting feel | 2 | One omni-light blink, a 40 ms cylinder tracer, random camera jitter and a ~1.7° pitch kick. No flash sprite, smoke, casing, slide motion, hit-stop or hit marker. |
| Zombies (Rimebound) look | 3 | Clean store-fresh clothes and tidy faces with a red chin smear. Ice prisms float off the face. Every zombie shares one body and one pose (`04`, `05`). |
| Zombie animation | 3 | One idle, one shamble, a tiny hurt twitch and a weak attack. Deaths end in a stiff star-fish pose. No get-up or grab-bite variety (`07`). |
| Specials (husk, siren, burster, hanger, foreman) | 3 | The silhouette ideas are good. The execution is primitive: the husk has glass-plate boxes, the burster a glowing ball and the foreman a stick pick (`06`). |
| Environment props and architecture | 2 | Cars are 2-box shapes with cylinder wheels. Trees are cones, or recursive cylinders for bare trees. Buildings are boxes, and the mine is octagon pipes and cone crystals (`09`–`12`). |
| Fire / VFX | 1 | Barrel fire is a column of opaque yellow spheres (`10`). Impact sparks are sphere meshes. |
| Gore | 5 | Good decal system (pools, sprays, drips, writing). Chunks are low-poly blobs, and a wound never shows on the body itself. |
| Combat UI / feedback | 3 | There is a reticle. No hit marker, no damage direction, no kill confirm. Enemy flinch is barely visible. |

## 2. Prioritised problems

### P0: must fix before anyone sees the game again

**P0-1 Pistol grip is broken; the left hand floats.** Evidence: `01`, `02`, `08`.
- At aim, the two fists sit about 15–20 cm apart. The left hand touches nothing.
- The "gun" is a black bar resting on top of the right fist, and its grip box sticks out under the fist.
- In game the camera sees the pistol raised vertically beside Elias's ear, not on the reticle line (`02`).
- When running, the gun hangs backwards out of an open hand.
- Why: the weapon is parented to `hand_r` with a fixed offset. The `aim_idle` clip is hand-keyed, and nothing constrains the hands to the weapon.
- Fix:
  - (a) Replace the box gun with a real model (Poly Haven `service_pistol`, CC0). Add marker nodes `grip_r`, `support_l` and `muzzle`.
  - (b) Use a weapon-driven rig. Place the gun in camera/aim space: a spine_03-relative "aim pivot" that is pitched by the camera.
  - (c) Drive the right hand to `grip_r` and the left hand to `support_l` with two-bone IK. Use `SkeletonIK3D`, or a custom analytic two-bone `SkeletonModifier3D` (≈60 lines), run after the AnimationTree.
  - (d) Add per-weapon static finger-curl hand poses as a filtered Blend2 layer: trigger finger extended, thumbs forward, support hand wrapped.
  - (e) Author a proper isosceles stance (elbows slightly bent, shoulders forward), then retarget it.
  - Every weapon gets the same grip/support/muzzle sockets.

**P0-2 Single shots feel fake.** Evidence: `01`: the four frames at t = 0 / .05 / .1 / .2 s are nearly identical.
- The `shoot` one-shot moves the arms by only a few millimetres.
- The muzzle light is an OmniLight at energy 6 that decays in ~0.1 s.
- The tracer is an emissive cylinder that lives 40 ms.
- Fix: work through the checklist in §5. The minimum is:
  - a procedural recoil spring on the aim pivot (pitch +6–8°, back 4 cm, roll ±2°, settling in ~180 ms);
  - slide blowback (0.03 s back, 0.06 s return);
  - a muzzle-flash quad plus a light that lasts 2 frames;
  - smoke wisps and an ejected RigidBody casing;
  - a camera kick that recovers (not random jitter);
  - layered audio;
  - 30–40 ms hit-stop on a headshot.

**P0-3 Hair holes / "dented bald spots".** Evidence: `03` (back of head and top view), `04`, nurse close-up in the scratchpad.
- MakeHuman hair proxies are alpha-scissor cards (`character_model.gd:212`, threshold 0.45). Between cards the scalp shows through as skin-coloured holes. The crown shows them most.
- On the zombies, a stray white ellipsoid (frost blob from `rime_look`) floats on the hair.
- The hairline is a hard texture edge on bare forehead skin.
- Fix:
  - (1) Paint a hair-coloured scalp/hair-cap into the skin albedo under every hair proxy (charpipe `paint.py`). This alone removes the "dent".
  - (2) Switch hair to `TRANSPARENCY_ALPHA_HASH`, with TAA/MSAA alpha-to-coverage, and a 0.3 threshold.
  - (3) Use a denser CC0 MPFB2 hair, or add a second shell layer.
  - (4) Remove the crown frost blob.

**P0-4 Zombies do not read as zombies, and the ice crystals look fake.** Evidence: `04`, `05`, `06`.
- Faces are clean and pale-blue with tidy lips. The clothes are new. There is no decay, no wounds and no wet or dry contrast.
- The crystals are clear hexagonal prisms floating 5–10 cm off the skin. They are unattached and clip the eyes.
- Fix:
  - Remove the crystal growths from shamblers (`rime_look.gd`).
  - Keep the frost only as a hoarfrost material layer on hair, brows, lashes and shoulders. Use upward normals plus a mask, opaque, rough 0.7. Ice is plausible at −40°, prisms are not.
  - Build a decay material stack on the MakeHuman skin:
    - Mottled necrotic albedo: livor mortis on the lower side, green-grey discolouration, dark veins.
    - Sunken eyes: MakeHuman targets `emaciated`, sunken cheeks, plus a shape key. Use milky cataract eye textures.
    - Cracked, peeling lips, receded gums and exposed teeth.
    - Black frostbitten fingers, which you already have.
    - Wet roughness on wounds against dry roughness on skin.
    - SSS on the skin.
  - Add wound inserts as mesh decals or skinned "gore caps":
    - bite on the neck or forearm;
    - torn cheek with jaw showing;
    - exposed ribs through a ripped shirt;
    - de-gloved hand;
    - a missing-lower-jaw variant (hide the `jaw` bone and add a cap mesh).
  - Clothing:
    - alpha-cut tears;
    - blood that soaks from the wounds down, using vertex-colour/UV masks;
    - grime that grades up from the feet;
    - frozen blood crusts.
  - Body variety: at least 4 body morphs (heavy, thin, old, young adult), randomised MakeHuman macros, hair loss patches, and 3 face textures.
  - Sources for the texture masks: hand-paint them, or generate tileable rot/wound sheets with Higgsfield image generation and project them in `paint.py`.

**P0-5 Primitive world: cars, houses, trees, lamps, trucks and transformers are boxes and cylinders.** Evidence: `09`, `10`, `11`, `12`.
- Conifers are literal cones. Bare trees are 7-sided recursive cylinders.
- Cars are 2 boxes plus 4 cylinders. The bucket truck and van are boxes.
- Main Street buildings are untextured dark boxes with stripe windows.
- The mine pipe has octagonal "flanges". The Meridian lobby desk and the debris are slabs.
- Fix: replace them with real models from the §3 shopping list.
  - Keep `props.gd` as the API (`Props.car(...)`) but make it instance `.glb` scenes. Keep the box collision.
  - Priority by screen time:
    1. trees, cars, street lamps and poles (L1–L3 exteriors);
    2. building facades (L3 Main Street, L2 school detail);
    3. interior furniture (L2, L4);
    4. mine kit (L5).

**P0-6 Fire is opaque yellow spheres.** Evidence: `02_school spawn` (scratchpad), `10`.
- Replace them with GPUParticles3D billboards: a flipbook flame texture (CC0 fire flipbook, or bake one in Blender/EmberGen), additive and soft, with heat-haze distortion, embers and a flickering OmniLight. Use Poly Haven `barrel_stove` as the barrel.

### P1: needed for a 2026 standard

**P1-1 Zombie animation set is thin and keyframed.**
- There is one zombie idle and one shamble. Every zombie is in the same pose (`05`).
- The hurt reaction is a ~5° twitch (`07`).
- The attack is two raised fists.
- Deaths snap to a symmetrical spread-eagle (`07`, bottom).
- Missing: get-up, grab/bite, lunge, stumble, turn-in-place, crawl attack and a feeding idle.
- Fix:
  - Use mocap: CMU and 100STYLE (§4).
  - Add 3–4 shamble variants with randomised play rate and phase.
  - Directional hit reacts (front, back, left, right, head, leg buckle) as additive layers.
  - Ragdoll deaths: `PhysicalBoneSimulator3D` blended from the last animated pose, with partial ragdoll on a hit.

**P1-2 Elias hatchet and reload are unreadable.** Evidence: `08`.
- The hatchet is a 9 cm stick, invisible at gameplay distance, and the swing is a one-arm overhead chop with no anticipation.
- The reload never brings the left hand to the magazine well.
- Fix:
  - Use the real `hatchet` (Poly Haven).
  - Author or retarget a 3-hit combo: diagonal down, backhand, shove.
  - Reload: a mag-drop prop, the left hand to the belt and then to the grip (IK targets keyed over time), and a slide release.

**P1-3 Special enemies look primitive.**
- Husk: replace the transparent box plates with sculpted opaque frozen-crust armour. Treat it as frozen meat and ice slabs, not glass.
- Burster: replace the glowing ball with a fleshy distended sac mesh (SSS, veins) that glows only faintly.
- Foreman: replace the stick pick with a real pickaxe model, and keep the head-lamp idea.
- Option: build these as Higgsfield image→3D sculpts like the bosses, which already proved good.

**P1-4 Snow drifts are perfect discs** (`09`, school spawn). Use heightmapped drift meshes, or terrain with noise. Taper into walls and cars, and add wind-sculpted lee drifts.

**P1-5 Crystal set dressing in the mine and heart** (`11`, `L6 spawn`).
- Flat-shaded cones and pyramids with uniform cyan emission. They read as placeholder.
- Use a few sculpted crystal-cluster meshes (Higgsfield image→3D, or Blender Geometry Nodes) with refraction-like roughness variation and dirty bases. Cut the instance count by about 60%.

**P1-6 Combat UI and feedback:**
- Add a hit marker (white tick; red X on a kill; headshot pip).
- Add damage-direction arcs.
- Show low-ammo and reload state on the reticle.
- Enemy hit flash or shader tint on hit.

**P1-7 Elias materials.**
- The jacket needs a quilted-cloth normal and roughness map and real retro-reflective tape (bright in the flashlight).
- Tool belt pouches are boxes. Replace them with leather pouch meshes.
- Use a Poly Haven `rubber_boots`-class texture and add a beanie option.

### P2: polish
- **Interiors.** Add reflection probes and baked or SDFGI lighting to the L4 lobby and halls, which are flat-lit (`12`). Add ceiling grid, trims and baseboards.
- **Gore chunks.** Use 4–6 sculpted chunk meshes (flesh, bone, ice) instead of blobs, and add on-body wound decals at the hit point.
- **Footstep prints.** Add prints and snow deformation trails behind Elias and the zombies.
- **Asset folder hygiene.** `assets/enemies/` holds 834 files, about 600 of them duplicate `*_NNNNN.webp` copies. Prune them, because they bloat exports.
- **Foot sliding.** Not observed in the stills. `anim_meta.json` speed-matching exists. Verify it in motion when the player turns while aiming.

## 3. Asset shopping list (real 3D; CC0 unless noted)

The Poly Haven model API and `dl.polyhaven.org` were reachable from this environment on the review date. Each name below was verified in `api.polyhaven.com/assets?t=models`. Sketchfab and HuggingFace are blocked from this sandbox, so those need a manual download. Kenney and Quaternius are stylised, so avoid them for meshes.

| Need | Source and asset id | Notes |
|---|---|---|
| Pistol (M45) | **Poly Haven `service_pistol`** | Add grip/support/muzzle markers and a separate slide node. |
| Hatchet | **Poly Haven `hatchet`** (alt `wooden_axe`) | |
| Pump shotgun, Tom's .44 revolver, flare launcher | No CC0 found on PH. Check **Smithsonian 3D Open Access (CC0)** for revolver scans; else **Higgsfield image→3D** | Then retopo to ≤15k tris, bake normals, split the moving parts. |
| Conifers | **PH `fir_tree_01`, `pine_tree_01`, `pine_sapling_small/medium`, `fir_sapling(_medium)`** | Add a snow-on-top shader (world-normal mask) and LODs. |
| Bare winter deciduous trees | Not on PH (leafy only). Generate with **Blender Sapling Tree Gen** in the existing bpy charpipe, using ambientCG `Bark014/016` | Output is ours. Add `dead_tree_trunk(_02)`, `tree_stump_01/02`, `pine_roots`. |
| Street lamps | **PH `street_lamp_01`, `street_lamp_02`** | |
| Power poles / lines / pole transformers | **PH `modular_electricity_poles`, `modular_electric_cables`** | Pole-top transformer pot, substation transformers and insulator stacks: **Higgsfield image→3D** or Blender hard-surface. |
| Utility cabinets | **PH `utility_box_01/02`, `power_box_01`, `fire_hydrant`, `concrete_road_barrier(_02)`** | |
| Fences | **PH `modular_chainlink_fence`** | Plus barbed-wire top, in Blender. |
| Cars: sedan, police cruiser, van, ambulance | Not on PH except **`covered_car`** (use it a lot; snow-covered cars hide detail). Others: **Higgsfield image→3D** from photo-real references, or manual Sketchfab CC0 | Keep it to ≤4 vehicle meshes and vary them with paint/decals and snow. |
| Utility bucket truck (hero, L1), mine haul truck (L5) | **Higgsfield image→3D** (hero quality, ≤40k tris) | Hero props, worth the credits. |
| Building facades: Main Street storefronts, diner, pharmacy, hardware, church, school detail | Modular facade kit authored in Blender with ambientCG `Bricks1xx`, `PaintedPlaster017`, `RoofingTiles013A`, `CorrugatedSteel009`, plus **PH `rollershutter_door`, `rollershutter_window_01-03`, `modular_fire_escape`, `modular_metal_gutter`, `modular_airduct_*`, `industrial_wall_lamp`** | Real window frames with depth, sills, cornices and signage. Church: steeple and stained-glass windows via Higgsfield. |
| School / shelter interior | **PH `old_bed_frame`** (cots), `metal_office_desk`, `painted_wooden_chair_01/02`, `drawer_cabinet`, `wooden_bookshelf_worn`, `painted_wooden_shelves`, `cardboard_box_01`, `plastic_crate_01-03`, `korean_fire_extinguisher_01`, `fire_alarm`, `wall_clock`, `medical_box`, `wheelchair_01`, `sofa_02/03`, `ceiling_fan` | Lockers: Blender plus ambientCG `Metal0xx`. |
| Fire barrels, camp | **PH `barrel_stove`, `barrel_03`, `metal_jerrycan`, `propane_tank`, `small_lpg_tank`, `portable_generator`, `portable_searchlight`** | |
| Church | **PH `Chandelier_01-03`, `wooden_candlestick`, `brass_candleholders`** | Pews, altar and font via Blender, using ambientCG Wood. |
| Meridian data centre | Server racks: Blender hard-surface (rack + blanking panels + LED emissive trim sheet) or Higgsfield, plus **PH `worn_metal_rack`, `modular_airduct_rectangular_01`, `modular_industrial_pipes_01`, `modular_pipes`** | Use cable-tray modules and a raised-floor tile texture (ambientCG `Tiles1xx`). |
| Mine | **PH `rock_face_01/02`, `rock_moss_set_*`, `coast_rocks_*`** (as rubble), `wooden_crate_01/02`, `old_military_crate`, `hand_truck`, `tool_cart`, `metal_tool_chest`, `ladder_sectioned_01`, `wooden_ladder`, `hanging_industrial_lamp`, `overhead_crane` | Timber sets, ore cart and hoist cage: Blender with ambientCG `Wood0xx`, or Higgsfield. |
| Debris / clutter | **PH `cardboard_box_01`, `metal_trash_can`, `binder_notebook`, `office_notepads`, `adjustable_wrench`, `pipe_wrench`, `rusted_wheel_rim_01/02`** | |
| HDRI / reflections | Poly Haven night and snow HDRIs; ambientCG `NightSkyHDRI003/008` | For reflection probes and sky. |
| Characters | Keep MakeHuman (CC0) and MPFB2 assets. Add higher-quality CC0 MPFB2 hair. Hand-paint or generate decay and wound masks | Not CC0: Mixamo characters, ActorCore, Rocketbox (MIT; OK licence but a different rig). |

## 4. Animation verdict

**Keep:**
- CMU-retargeted walk and run (CMU licence is free for any use; credit is courteous).
- The AnimationTree structure: pose transitions, upper-body filtered one-shots, aim layer.

**Replace with real mocap:**
- Aim idle and shoot: isosceles pistol stance, two-handed shotgun and revolver.
- Reload ×3, hatchet combo, hurt/stagger, the grab-escape struggle.
- All zombie locomotion, attacks and get-ups.

Sources:
- **CMU Graphics Lab Mocap**: thousands of clips (stagger, crawl, fall, get-up, punches, some reach/grab). Free.
- **100STYLE** (CC BY 4.0, attribution required): style locomotion including drunk, injured and zombie-like gaits. Use for the shambles.
- **Quaternius Universal Animation Library** is CC0. The animations are usable even though its characters are stylised. Check it for pistol and melee clips.
- **Mixamo is NOT CC0.** It is royalty-free inside a game, but you cannot redistribute the source FBX in an open repo. Avoid it if the project must stay CC0-clean.
- Bandai Namco Research Motion is CC BY-NC. Not allowed.
- Video→mocap (Higgsfield motion or other) can fill gaps but needs heavy cleanup.

**Fix procedurally:**
- Two-hand weapon IK plus finger poses (P0-1).
- Aim-space weapon placement with camera pitch (already partly there in `_apply_aim_pitch`).
- Recoil spring.
- Additive directional hit reacts.
- Look-at head IK (`LookAtModifier3D`) for zombies tracking Elias.
- Foot IK on slopes and stairs.
- Ragdoll deaths (`PhysicalBoneSimulator3D`) blended with the death clips.
- Breathing additive and an idle weight shift.
- Run-to-stop and turn-in-place clips. Without them the player pivots on the spot.

## 5. Shooting-feel checklist (currently ✗ = missing, ~ = weak)

| Item | Now | Target |
|---|---|---|
| Camera kick | ~ random h/v jitter + 1.7° pitch | Directional kick (up, slight random yaw) on a critically damped spring. 80% of the pitch auto-recovers over 150–250 ms. FOV punch of −1° for 2 frames. |
| Weapon recoil animation | ✗ (shoot clip ≈ static) | Procedural spring on the aim pivot (rotation and translation); wrist flip; elbows absorb via IK; slide or hammer motion. |
| Muzzle flash | ~ light only | 3–4 randomised flash quads (side and front) plus a star, 1–2 frames; light 2 frames, warm, shadowless; brief smoke burst. |
| Smoke | ✗ | Lingering muzzle wisp (soft billboard particles, 1–2 s, drifts with the wind). Barrel smoke after rapid fire. |
| Shell casing | ✗ | RigidBody brass casing ejected right/up from the port; tinkle SFX on landing (snow = muffled). Pool 30 casings. |
| Tracer | ~ 40 ms cylinder | Thin stretched additive quad that fades in ~60 ms. Optional; pistols usually show none. |
| Impact | ~ sphere sparks + 6 cm dark decal | Per-surface impact sets: concrete dust puff and chips, metal sparks and a bright hole, wood splinters, snow powder, ice shards, flesh mist and exit spray. Bullet-hole decals with normal maps. |
| Hit-stop | ✗ | 30–50 ms time-scale dip on a headshot or kill; 2-frame enemy freeze on a heavy hit. |
| Enemy flinch | ~ tiny hurt one-shot | Directional additive hit react scaled by damage; head snap on a headshot; leg buckle; stagger on threshold (exists); partial ragdoll. |
| Hit marker / confirm | ✗ | Reticle tick plus a short hit sound; red X and a distinct thunk on a kill. |
| Audio layering | ~ single `shot_<id>` sample | Layer: transient crack + body + mechanical (slide) + tail with an environment reverb send (outdoor snow = dry slap; indoor = room tail); casing drop; ear-ring on repeated fire indoors. |
| Controller rumble | ✗ (check) | Short sharp pulse on each shot. |

## 6. Suggested work-order sequence
1. **Weapon rig:** real pistol and hatchet, sockets, two-hand IK, finger poses, recoil spring, flash/smoke/casing, hit marker. This fixes owner points 1–2.
2. **Hair-cap paint and alpha-hash hair** for all characters, and remove the frost blob. Owner point 3.
3. **Zombie decay pass:** remove the crystals, add the decay material stack, wound inserts, torn clothing and body variety. Owner point 4.
4. **Environment swap through `props.gd`:** trees → cars (`covered_car` + 3 generated) → lamps/poles → facades → interiors → mine kit. Owner point 5. Also fix fire VFX and snow drifts.
5. **Mocap pass:** zombie set and Elias combat clips, then ragdoll and hit reacts.

Evidence index (`docs/review/`):
- `01` pistol grip and shoot frames
- `02` in-game aim
- `03` hair holes, OTS shoot, head top
- `04` zombie face and crystals
- `05` zombie lineup
- `06` specials
- `07` zombie attack, hurt, crawl, death
- `08` reload and hatchet
- `09` L1 cone trees, truck, disc drifts
- `10` L3 box cars, sphere fire, box buildings
- `11` L5 primitive mine
- `12` L4 greybox lobby
