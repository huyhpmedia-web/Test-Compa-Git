extends RefCounted
## L6 - THE HEART, round 7 (R7-C): real models for the mine mouth, nook, steam-relief valves, manifold and the
## pipeline control station (control cabinets, monitors, breaker gear, valve wheels).  Gameplay stays in l6_heart.gd.

const Props = preload("res://world/props.gd")
const Mats = preload("res://core/mats.gd")
const R4 = preload("res://levels/dressing/l4_real.gd")
const Art = preload("res://levels/dressing/l4_art.gd")

static func _sp(rel: String, pos: Vector3, yaw := 0.0, opts := {}) -> Node3D:
	return R4.sp(rel, pos, yaw, opts)

## Timber door frame + rails + cart + floodlight at the top of the descent (replaces the box frame / strip rails).
static func mine_mouth() -> void:
	# hewn timber portal (real beam model, stretched to the drift opening)
	_sp("mine_sf/timber_beam", Vector3(0.25, 0.0, 66.4), 0.0, {"fit_box": Vector3(5.0, 3.7, 0.55), "snow": 0.0, "range": 90.0})
	R4.solid(Vector3(-1.9, 1.7, 66.6), Vector3(0.4, 3.4, 0.4))
	R4.solid(Vector3(2.4, 1.7, 66.6), Vector3(0.4, 3.4, 0.4))
	# narrow-gauge track running a few metres into the cavern
	for i in 2:
		_sp("mine_sf/rail_4m", Vector3(0.15, 0.0, 63.0 - i * 4.0), PI * 0.5, {"fit_box": Vector3(4.0, 0.3, 1.8), "snow": 0.0, "range": 100.0, "shadow": false})
	_sp("mine_sf/mine_cart", Vector3(0.15, 0.0, 59.4), 0.35, {"scale": 1.0, "snow": 0.0, "collide": Vector3(1.2, 0.9, 1.9), "range": 100.0})
	# the dropped Northline floodlight: tripod + searchlight head (replaces the white slab)
	var tp := Vector3(1.6, 0.0, 63.4)
	for k in 3:
		var a := k * TAU / 3.0
		var leg := Props.cyl(R4.geo, 0.014, 1.35, tp + Vector3(cos(a) * 0.26, 0.66, sin(a) * 0.26), Mats.color(Color(0.18, 0.19, 0.2), 0.45, 0.8), false, -1.0, Vector3(sin(a) * 0.3, 0, -cos(a) * 0.3), 5)
	_sp("camp/searchlight", tp + Vector3(0, 1.28, 0), 0.5, {"scale": 3.0, "rot": Vector3(0.0, 0, 0), "emissive": {"portable_searchlight_glass": [Color(1.0, 0.9, 0.7), 4.0]}, "range": 80.0})
	R4.omni(tp + Vector3(0.1, 1.3, -0.3), Color(1.0, 0.82, 0.55), 1.1, 6.0)

static func path_dressing() -> void:
	# Ruth's dead lantern (real) and a rusty pick left on the sleeping bag
	_sp("mine_sf/lantern", Vector3(-0.3, 0.0, 51.0), 0.6, {"scale": 1.0, "range": 70.0})
	_sp("mine_sf/pickaxe", Vector3(-0.2, 0.05, 52.6), 1.2, {"rot": Vector3(PI * 0.5, 0, 0), "range": 60.0})
	_sp("mine_sf/shovel", Vector3(3.2, 0.05, 41.4), 0.3, {"rot": Vector3(PI * 0.5, 0, 0), "range": 60.0})
	_sp("mine_sf/mine_cart", Vector3(3.4, 0.0, 44.0), 2.4, {"scale": 1.0, "collide": Vector3(1.2, 0.9, 1.9), "range": 100.0})
	# service pipes down the east wall with flanges + insulated heat line (PBR metal instead of flat cylinders)
	R4.pipe(Vector3(2.3, 3.4, 66.0), Vector3(2.3, 3.4, 47.0), 0.22, Color(0.5, 0.55, 0.6), true)
	R4.pipe(Vector3(2.3, 2.6, 66.0), Vector3(2.3, 2.6, 47.0), 0.1, Color(0.55, 0.4, 0.3))
	R4.pipe(Vector3(4.85, 3.6, 46.0), Vector3(4.85, 3.6, 31.0), 0.22, Color(0.5, 0.55, 0.6), true)
	_sp("industrial_sf/pipe_manifold", Vector3(2.3, 0.4, 56.0), -PI * 0.5, {"scale": 1.0, "range": 80.0, "rot": Vector3.ZERO})
	for z in [62.0, 53.0, 45.0]:
		_sp("industrial_sf/valve_wheel", Vector3(2.15, 2.2, z), -PI * 0.5, {"scale": 1.2, "range": 60.0})

static func nook() -> void:
	# table, cot and lamp: real models
	_sp("interior/desk", Vector3(10.6, 0.0, 32.0), PI * 0.5, {"collide": Vector3(0.95, 0.8, 2.0), "scale": 0.8})
	_sp("interior/bed_frame", Vector3(7.2, 0.0, 35.0), PI * 0.5, {"collide": Vector3(2.0, 0.5, 0.95), "tint": Color(0.55, 0.62, 0.55)})
	_sp("mine_sf/lantern", Vector3(10.5, 0.8, 31.3), 0.2, {"scale": 1.0, "range": 40.0})
	_sp("mine_sf/pickaxe", Vector3(5.6, 0.05, 31.2), 0.4, {"rot": Vector3(PI * 0.5, 0, 0), "range": 40.0})

## Steam-relief valve assembly at ground level (the interactable keeps its place in l6_heart.gd).
static func valve(vp: Vector3, i: int) -> void:
	# riser pipe + real valve wheel on a flanged tee; a tall hand wheel over the old red cross
	_sp("industrial_sf/pipe_manifold", vp + Vector3(0, 0.2, 0), 0.0 if i == 1 else PI, {"scale": 0.55, "range": 80.0, "collide": "none"})
	_sp("industrial_sf/valve_wheel", vp + Vector3(0, 0.95, 0), 0.0, {"scale": 1.8, "range": 80.0, "collide": "none", "tint": Color(1.0, 0.55, 0.5)})
	R4.solid(vp + Vector3(0, 0.6, 0), Vector3(0.9, 1.2, 0.9))
	R4.pipe(vp + Vector3(0, 0.0, 0), vp + Vector3(0, 1.4, 0), 0.3, Color(0.55, 0.6, 0.66), true)

## Pipeline control station: replaces the slab-and-box console with cabinets, monitors, breaker gear and valve wheels.
## `r` is the station root (east wall, local +z points into the cavern).
static func station(r: Node3D) -> void:
	var pos := r.position
	var yaw := r.rotation.y
	var b := Basis(Vector3.UP, yaw)
	# flanking control cabinets and breaker panels (wall side)
	for sx in [-1.9, 1.9]:
		var p := pos + b * Vector3(sx, 0.0, 0.25)
		_sp("industrial_sf/control_cabinet", p, yaw, {"collide": "none", "tint": Color(0.82, 0.86, 0.9), "range": 90.0})
	for sx in [-3.1, 3.1]:
		_sp("industrial_sf/breaker_box", pos + b * Vector3(sx, 1.0, -0.3), yaw, {"scale": 1.3, "range": 90.0})
	R4.solid(pos + b * Vector3(0, 1.0, 0.1), Vector3(4.6, 2.0, 1.2), yaw)
	# console desk: steel shell + sloped panel, monitors with live screens, status lamps
	var dark := Art.pbr("metal", 1.2, Color(0.18, 0.2, 0.22), 0.45, 0.6, 0.85)
	var top := Art.pbr("hazard", 1.0, Color(0.7, 0.7, 0.7), 0.6, 0.5, 0.3)
	var c0 := pos + b * Vector3(0, 0, 0.1)
	var shell := Props.box(R4.geo, Vector3(2.6, 0.95, 0.75), c0 + Vector3(0, 0.475, 0), dark, false)
	shell.rotation.y = yaw
	var slope := Props.box(R4.geo, Vector3(2.6, 0.06, 0.55), c0 + b * Vector3(0, 1.0, 0.18) + Vector3(0, 0, 0), dark, false)
	slope.rotation = Vector3(-0.42, yaw, 0.0)
	for mx in [-0.8, 0.0, 0.8]:
		R4.monitor(c0 + b * Vector3(mx, 1.18, 0.0), yaw + (-0.25 if mx < 0 else (0.25 if mx > 0 else 0.0)), [Color(0.1, 0.6, 0.9), Color(0.1, 0.8, 0.5), Color(0.9, 0.5, 0.1)][int(mx + 1.0) % 3], mx * 3.3, 1 if mx == 0.0 else 0)
	# valve wheels (flow) mounted on the cabinet sides
	_sp("industrial_sf/valve_wheel", pos + b * Vector3(-1.45, 1.15, 0.7), yaw, {"scale": 1.4, "range": 70.0})
	_sp("industrial_sf/valve_wheel", pos + b * Vector3(1.45, 1.15, 0.7), yaw + 0.4, {"scale": 1.4, "range": 70.0})
	# status lamps along the top of the slope
	for k in 5:
		var lc := Color(0.2, 1.0, 0.4) if k % 2 == 0 else Color(1.0, 0.3, 0.1)
		Props.sphere(R4.geo, 0.025, c0 + b * Vector3(-1.1 + k * 0.55, 1.22, -0.1), Mats.emissive(lc, 3.0))
	# cable trunk from the station to the ceiling
	R4.pipe(pos + b * Vector3(-2.0, 2.0, -0.3), pos + b * Vector3(-2.0, 9.0, -0.3), 0.07, Color(0.1, 0.1, 0.12))
	R4.pipe(pos + b * Vector3(2.0, 2.0, -0.3), pos + b * Vector3(2.0, 9.0, -0.3), 0.07, Color(0.1, 0.1, 0.12))

## Heavy-industry set pieces along the pipeline wall and under the breach.
static func pipeline_wall() -> void:
	# header manifold spans on the east wall, valve banks, fallen cable reels
	for z in [-9.0, -31.0, 4.0]:
		_sp("industrial_sf/pipe_manifold", Vector3(18.3, 1.0, z), -PI * 0.5, {"scale": 1.5, "range": 100.0, "collide": "none"})
	_sp("industrial_sf/storage_tank", Vector3(18.0, 0.0, 14.0), 0.0, {"scale": 0.9, "collide": "cyl", "range": 90.0})
	_sp("industrial_sf/diesel_gen", Vector3(17.6, 0.0, -12.0), -PI * 0.5, {"scale": 1.6, "collide": Vector3(1.8, 1.7, 3.0), "range": 90.0})
	_sp("mine_sf/steam_hammer", Vector3(-15.8, 0.0, 18.0), PI * 0.5, {"scale": 1.0, "collide": Vector3(2.2, 3.0, 1.0), "range": 90.0})

## Grime decals: wet-rock streaks, pipe rust stains, oil at the station.
static func grime() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 6161
	for i in 12:
		var z := -26.0 + i * 4.0
		R4.decal("streak", Vector3(18.9, 3.5, z), Vector3(-1, 0, 0), Vector2(r.randf_range(2.0, 4.0), 7.0), Color(0.02, 0.03, 0.04), r.randf_range(0.5, 0.85))
	for i in 7:
		var z2 := 46.0 + i * 3.0
		R4.decal("streak", Vector3(2.45, 2.0, z2), Vector3(-1, 0, 0), Vector2(r.randf_range(2.0, 3.0), 4.5), Color(0.03, 0.03, 0.035), r.randf_range(0.5, 0.8))
	for pz in [-20.0, -4.0]:
		R4.decal("oil", Vector3(16.5, 0.04, pz), Vector3.UP, Vector2(2.6, 2.2), Color(0.02, 0.025, 0.03), 0.8, 0.6)
	for k in 5:
		R4.decal("stain", Vector3(r.randf_range(-12.0, 14.0), 0.04, r.randf_range(-24.0, 14.0)), Vector3.UP, Vector2(r.randf_range(2.0, 3.6), r.randf_range(2.0, 3.0)), Color(0.02, 0.04, 0.05), 0.55, 0.6)
