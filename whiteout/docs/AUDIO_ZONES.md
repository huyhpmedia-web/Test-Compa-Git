# Audio zones (R8-C)

Code: `core/sfx.gd` (buses, spaces, occlusion), `world/audio_zone.gd` (Area3D reverb zone),
`world/audio_zones.gd` (per-level table + ambience emitters, installed by `levels/level.gd` after build/dressing).

## Bus layout (built in code by the `Sfx` autoload)

| bus | sends to | effects | used by |
|---|---|---|---|
| Music | Master | - | `Sfx.music` |
| Ambience | Master | Reverb (same space, wet x0.35) | `Sfx.ambience` loops |
| SFX | Master | **Reverb**: morphs to the current space (≈0.4 s glide) | every one-shot, `play_at`, `attach_loop`, ambience one-shots |
| Muffled | SFX | LowPass 700 Hz, -3 dB | positional sounds with a wall between them and the listener |

**Occlusion**: `play_at` / `ambient_at` cast a ray (collision layer 1 = world) from the current camera to the source
(+0.9 m for actors). If level geometry is in between, the sound goes to `Muffled` (-3 dB extra). Looping 3D
emitters from `attach_loop` are re-checked every 0.2 s. Enemies (layer 3) and the player (layer 2) never occlude.

## Spaces (`Sfx.SPACES`)

| space | room | damping | wet | predelay | character |
|---|---|---|---|---|---|
| outdoor | 0.22 | 0.90 | 0.05 | 18 ms | snow eats reflections: dry |
| room | 0.30 | 0.60 | 0.17 | 6 ms | small room, office, booth, container |
| corridor | 0.45 | 0.50 | 0.22 | 12 ms | school / MERIDIAN corridors |
| basement | 0.55 | 0.40 | 0.26 | 10 ms | bare concrete |
| hall | 0.86 | 0.28 | 0.34 | 45 ms | gym, main hall, glass lobby, plant, hoist hall |
| church | 0.97 | 0.15 | 0.44 | 75 ms | St. Brendan's nave, long tail |
| mine | 0.72 | 0.45 | 0.32 | 22 ms | rock tunnels |
| cavern | 1.00 | 0.20 | 0.50 | 95 ms | haulage cavern, the Heart |
| datacenter | 0.62 | 0.78 | 0.20 | 20 ms | server halls (fan noise masks the tail) |

Overlapping zones: the smallest box wins. Leaving every zone returns to the level's base space.

## Per level

### L1 Highway 53 / substation — base `outdoor`
| zone | space | box |
|---|---|---|
| Control house | room | 10 x 3 x 10 at (22, 1.5, -81) |
| Storage container | room | 6.2 x 2.7 x 2.4 at (20, 1.35, -95.4) |

Ambience one-shots: heater knocks in the control house; the bucket truck settling (metal creak) in the ditch;
wind gusts along the highway, the spur and the yard; distant hound howls far east; container walls creaking.

### L2 Kettle Falls school — base `outdoor` (courtyard)
| zone | space | box |
|---|---|---|
| Ground floor (offices, rear rooms) | room | 44 x 4.2 x 24 at (0, 2.55, -22) |
| Main hall | hall | 14 x 4.2 x 12 at (0, 2.55, -16) |
| Gym (shelter) | hall | 15 x 6.5 x 24 at (14.5, 3.7, -22) |
| Back corridor | corridor | 29 x 4.2 x 4 at (-7.5, 2.55, -24) |
| Basement, boiler room, locker room | basement | 44 x 3.2 x 22 at (0, -1.45, -23) |

Ambience: before `boiler_on` the cold pipes groan/contract (main hall, corridor, west wing); after it the radiators
knock and tick (and the boiler flue). Drips in the basement and the frozen locker room, ice cracking on the locker
floor, distant moans from the basement's far end, wind through the broken gym windows, the gym roof creaking under
snow, west-wing creaks, howls and gusts in the courtyard.

### L3 Main Street / St. Brendan's — base `outdoor`
Zones are generated from the level's own `_rooms` table (the same rectangles that switch interior lighting):
the pharmacy, diner and hardware store (`room`, 6 m tall) and **St. Brendan's** (`church`, 12 m tall).
Ambience: roof timbers creaking and wind through the broken windows on both nave walls; creaks in each shop;
distant moans along the north frontage; howls from the lake; gusts along the street.

### L4 MERIDIAN — base `outdoor` (yard)
| zone | space |
|---|---|
| Whole building shell | datacenter |
| Glass lobby | hall |
| Hall A, Hall C | datacenter |
| Electrical room 2 | room |
| Cooling plant | hall |
| Armory | room |
| Corridor | corridor |
| NOC, break room | room |
| Pipeline hall (8.5 m) | hall |

Ambience: 9 looping server-fan emitters in Halls A and C plus one in the electrical room (muffled behind walls);
pipe groans and knocks in the cooling plant; drips and pipe stress in the pipeline hall, a distant moan at its far
end; wind across the yard; the guard booth creaking.

### L5 Lower Kettle mine — base `mine`
| zone | space |
|---|---|
| Hoist hall (headframe) | hall |
| Lamp room (safe room) | room |
| Pump station | basement |
| Haulage cavern (lower level) | cavern |
| Refuge chamber | room |

Ambience: drips in the pipeline tunnel, pump station, collapsed drift, haulage tunnel and cavern; timber sets
creaking under load; cage cables/headframe metal in the hoist hall; the warm pipeline groaning; moans in the cavern
and pump station; ice cracking in the cavern.

### L6 The Heart — base `cavern`
| zone | space |
|---|---|
| Save nook | room |
| Mine mouth | mine |

Ambience: drips on the path down and over the arena, ice cracking along the frozen lake edge, moans from the
far wall, pipeline breach groaning on the east wall.

## New sounds
`amb_creak_*`, `amb_radiator_*`, `amb_pipe_groan_*`, `amb_server_fan` are PROCEDURAL (`tools/gen_amb_oneshots.py`,
numpy only, listed in `audio/LICENSES.md`). Everything else re-uses the existing CC0 set (water_drip, wind_gust,
ice_crack, door_open, metal_impact, zombie/hanger/husk groans pitched down, hound_howl).
