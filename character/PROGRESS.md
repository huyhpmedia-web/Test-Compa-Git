# Character build -- progress / hand-off notes

Goal: rebuild the woman in `reference/` as a Blender character, as close to the photos as possible.
The user asked to focus on the PERSON; the background stays a rough sketch (do not spend time on it).

## State (all stages run end to end)
`scripts/01_analyze_refs.py` -> `02_fit_head.py` -> `03_bake_skin.py` -> `04_build_character.py` -> `05_render.py`
(see README.md).  Outputs: `data/fit_head.npz`, `textures/skin_albedo.png`, `textures/eye_{L,R}.png`,
`character.blend`, `renders/{front,profile,closeup}.png` + `compare_*.jpg`.

Environment: `./setup_env.sh <venv>` (bpy 5.2.4 + MediaPipe); Cycles CPU, a full 1254 px shot takes 6-9 min.
Quick check: `05_render.py closeup 48 50 _t` (50 % scale, ~40 s).

## What is in the character
- Head: MakeHuman mesh warped to 478 landmarks (2 frontal photos) + profile silhouette.
- Skin: photos projected into the UV atlas (viewing-angle cut-off, hair-masked, mirrored fill, photo-space de-lighting).
- Eyes: spheres from the warped MakeHuman eye helper, textured by projecting the photos (lids/lashes/iris as photographed).
- Hair: `hairgen.py` -- strands go root -> great arc over the skull -> release point (azimuth limited to sides/back) -> hang with waves.
- Outfit: tee cut from the subdivided body (`outfit.py`), choker/bow/strings/earrings (`outfit_posed.py`).
- Pose keyed per shot (frame 1 front, 2 profile, 3 close-up); cameras are rigidly attached to the head.

## Ideas for further likeness (not done)
- Hair is too tidy: more volume on her right side at jaw level, piecey locks, flyaways; fringe sweep across the forehead.
- Skin: add detail/normal map, stronger lips colour, specular variation; the neck fade under the choker.
- Geometry: ear position/shape and jaw line from the profile photo; bust/shoulder shape vs. the front photo.
- Real lashes as curves; bow shape closer to the photo.

## Seen in the final renders (fix first next time)
- PROFILE shot is the weakest: the front lock on her right hangs across the cheek/eye and the ear is hidden
  (photo: ear visible, hair tucked behind it, only a thin lock in front) -> narrow/thin the front lock, keep it
  behind the eye line, widen the ear gap in `hairgen.comb` (phi_r ranges, thickness, flare).
- PROFILE: choker tail/strings stick out diagonally in front of the bust (they should lie on the chest);
  face looks over-exposed from the side; tee has a flap at the bust side.
- FRONT/CLOSE-UP: thin vertical line on her right cheek (mirrored content from the left ear junction), patch edge
  on the forehead near the part, faint neck line under the choker; bust bumps still show through the tee.
