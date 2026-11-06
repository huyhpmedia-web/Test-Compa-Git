# assets/env — real 3D environment assets

Props converted with Blender (bpy) from **Poly Haven** glTF models (CC0 1.0, https://polyhaven.com/a/<id>): meshes decimated, textures down-scaled to 512-1024 px, origin moved to the base centre. No attribution required; credit given to the Poly Haven artists.

| File(s) | Poly Haven id(s) |
|---|---|
| vehicles/covered_car | covered_car |
| trees/dead_trunk_01/02, stump_01/02, roots_1/2, fir_sapling_1-3, pine_sapling_s_1-3 | dead_tree_trunk, dead_tree_trunk_02, tree_stump_01/02, pine_roots, fir_sapling, pine_sapling_small |
| street/lamp_01/02, pole_a/b/c (assembled presets from the kit), hydrant, utility_box_01/02, power_box, barrier_01/02, fence_post/gate | street_lamp_01/02, modular_electricity_poles, fire_hydrant, utility_box_01/02, power_box_01, concrete_road_barrier(_02), modular_chainlink_fence |
| camp/* | barrel_stove, barrel_03, metal_jerrycan, propane_tank, small_lpg_tank, portable_generator, portable_searchlight, wooden_crate_01/02, plastic_crate_01, metal_trash_can, cardboard_box_01, rusted_wheel_rim_01, pipe_wrench |
| interior/* | old_bed_frame, metal_office_desk, painted_wooden_chair_01/02, drawer_cabinet, wooden_bookshelf_worn, painted_wooden_shelves, korean_fire_extinguisher_01, fire_alarm, wall_clock, medical_box, wheelchair_01, sofa_02/03, ceiling_fan, worn_metal_rack |
| facade/* | rollershutter_door, rollershutter_window_01, industrial_wall_lamp, modular_fire_escape, modular_metal_gutter |
| industrial/* | modular_airduct_rectangular_01, modular_industrial_pipes_01 |
| mine/* | rock_face_01/02, hand_truck, tool_cart, metal_tool_chest, ladder_sectioned_01, wooden_ladder, hanging_industrial_lamp, overhead_crane |
| church/* | Chandelier_01, wooden_candlestick, brass_candleholders |

## Generated for this project (our own work, CC0)
- trees/conifer_*.glb, pine_*.glb, bare_*.glb: procedural trees written for this project (Blender script tools/env_build/gen_trees.py). Bark: ambientCG Bark014 (CC0, textures/env/bark014_*). Needle atlas textures/env/frond_atlas.png and chainlink.png drawn procedurally (tools/env_build/frond.py).
- Poly Haven fir_tree_01 / pine_tree_01 were evaluated: they are 7 M / 15 M triangle needle clouds that collapse when decimated, so procedural conifers are used instead.

## Generated via Higgsfield (Tripo H3.1), built by tools/charpipe/props_hd.py
vehicles/sedan, police, ambulance, bucket_truck, haul_truck; props/transformer, server_rack, steeple. Generated for this project via Higgsfield (Tripo H3.1).

## Added by agent F (L4 MERIDIAN / L6 Heart)
- office/*: Poly Haven CC0 (decimated/1k via tools/env_build/conv2.py): mounted_fluorescent_lights, security_camera_01, potted_plant_01/02, modern_arm_chair_01, mid_century_lounge_chair, modern_coffee_table_01, classic_laptop, office_notepads, stationery_supplies, clipboard, WetFloorSign_01, modern_ceiling_lamp_01, plastic_monobloc_chair_01 (https://polyhaven.com/a/<id>).
- cave/boulder_nq2: Poly Haven namaqualand_boulder_02 (CC0).
- textures/env/f/{carpet,ceil,terrazzo,plaster,concrete,metal,rock,rock2,ice,diamond}_*.jpg: ambientCG CC0 (Carpet012, OfficeCeiling001, Terrazzo013, PaintedPlaster017, Concrete048, Metal061B, Rock035, Rock058, Ice003, DiamondPlate009). raised_*, wpanel_*, clad_*, hazard_*: generated procedurally for this project (CC0).
