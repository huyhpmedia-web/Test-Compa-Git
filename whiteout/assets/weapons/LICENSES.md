# Weapon assets

| Path | Source | Licence |
|---|---|---|
| handgun/handgun.glb | Poly Haven `service_pistol` (https://polyhaven.com/a/service_pistol), 2k diffuse, 1k normal/ARM; split and given grip/support/muzzle/eject markers by tools/weapons_build/build_handgun_hatchet.py | CC0 |
| knife/knife.glb (hatchet) | Poly Haven `hatchet` (https://polyhaven.com/a/hatchet), 1k; markers added by tools/weapons_build/build_handgun_hatchet.py | CC0 |
| shotgun/, magnum/, launcher/ | Higgsfield/Tripo generated for this project (owned output), tools/charpipe/props_hd.py. Markers are added at load time by the OFFSETS table in world/fx.gd | project-owned |

Loader: world/fx.gd `weapon_mesh(id)` picks up `assets/weapons/<id>/<id>.glb`. A replacement glb either carries nodes Grip_R / Support_L / Muzzle / Eject (hand-bone frame, forward -Z) or gets them from the OFFSETS table.
