# Character build — progress / hand-off notes

Goal: rebuild the woman in `reference/ref_front.jpg`, `ref_profile.jpg`, `ref_closeup.jpg`
as a Blender character (as close to the photos as possible), render the 3 matching views,
commit `.blend` + scripts + renders to branch `claude/lucid-hypatia-0ft2mr`.

## Environment (ephemeral container — recreate with `./setup_env.sh <venv>`)
- Blender = `bpy==5.2.4` pip module (Python 3.13), Cycles CPU only (4 cores, ~5 s per 1254² clay render).
- MediaPipe 1.2.2 runs in the same venv (installed `--no-deps`, needs `libegl1`).
- MakeHuman base mesh/targets/rig are CC0, bundled in `mh_data/` (full target library:
  `git clone --depth 1 https://github.com/makehumancommunity/mpfb2`, env `MPFB_TARGETS`).
- Run stages as `<venv>/bin/python scripts/NN_*.py` from `character/`. `build/` is scratch (gitignored).

## Done
1. `scripts/01_analyze_refs.py` → `build/lm_{1,2,3}.json` (478 landmarks) + `build/seg_{1,2,3}.npy`
   (hair / face-skin / body-skin / clothes masks; very clean). 1=front, 2=profile, 3=closeup.
2. `scripts/mhlib.py` (base mesh, macro targets, rig json), `blcore.py` (bpy helpers),
   `fitlib.py` (camera/PnP/RBF warp/detector), `fitscene.py` (clay scene for detection),
   `profilelib.py` (profile silhouette + features).
3. `scripts/02_fit_head.py` — joint head fit: frontal landmark steps (closeup + front photo)
   interleaved with profile-silhouette depth steps. Converges to ~3.5 px / 2.2 px landmark
   RMS and ~0.9 mm profile RMS. Result: `data/fit_head.npz`
   (`verts` 19158x3 Blender coords metres, `eyes` centres, `H` landmark 3D points,
   `cam_closeup`/`cam_front` 4x4 camera world matrices for 85 mm lens, 36 mm sensor, 1254 px,
   `profile_s/R/t` = photo(a=+x, u=-y px) -> model(a=-Y, u=+Z) similarity).
   `scripts/view_fit.py <npz> <png>` renders clay check views.

## Findings / decisions
- Photo head pose: front photo yaw ≈ -7°, pitch ≈ -4.5°, roll ≈ 9°; closeup yaw ≈ -9°, roll ≈ 9°;
  profile photo pitch ≈ -8° (chin up). Hair hides her right cheek in both frontal photos
  → occluded landmarks are mirrored from the left side.
- MediaPipe depth (z) is too noisy → only in-plane residuals are used; depth comes from the profile.
- Macros: female, young, cup 1.0, firmness 0.7, proportions 0.9 (see MACROS in 02_fit_head.py).
- Light in the photos: sun from her front-left (image right in frontal shots), soft.

## Next steps (in order)
1. Check `data/fit_head.npz` visually (view_fit.py); ear position / jaw from profile if needed.
2. `03_build_character.py`: body mesh from fitted verts + rig (rig.default.json, weights),
   pose (arms down, head roll/yaw like the photo), subdivision.
3. Skin: project the 3 photos into the MakeHuman UV atlas (4096²) using the fitted cameras,
   skin masks from `seg_*`, visibility test, mirror fill, light de-shading; Principled + SSS.
4. Eyes: real eyeballs (cornea + iris colour grey-blue from photo), lashes; winged eyeliner is in the texture.
5. Hair: Curves object, chin-length wavy bob, side part on her left, volume swept to her right,
   dark ash roots → platinum/golden blonde, flyaways; Principled Hair BSDF. Match silhouettes from `seg_*`.
6. Outfit: white fitted short-sleeve crop tee with wide scoop neck (from body faces, offset + smooth),
   white ribbon choker tied in a bow on her right-front, two halter strings to the neckline corners,
   one long tail hanging to bust level; small crystal stud earrings.
7. Scene: black slatted gate, brick pillar (left), foliage (left), concrete canopy with wood slats; sun + sky.
8. Three cameras matching the photos, renders, side-by-side comparison sheets in `renders/`,
   save `character.blend` (packed textures), README, commit + push.
