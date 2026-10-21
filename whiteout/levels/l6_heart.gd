extends "res://levels/level.gd"
## L6 — THE HEART. The brine cavern beneath the Lower Kettle mine: the colony's heart.
## Critical path: mine mouth (z=+64) -> rock path down the lake shore -> save nook (east alcove)
## -> arena (z=+22 .. -30) -> THE HOLLOW MOTHER on the far wall -> pipeline control station
## (east wall) -> the ending choice (dark / thaw).
##
## Coordinates: path runs along -Z. Lake is west (-X). Pipeline breach + control station east (+X).
## Flags set: l6_intro, l6_tom1, l6_nook, l6_revealed, l6_phase2, mother_dead, l6_ending_talk
## Flags read: mother_dead, found_june (optional)

const CYAN := Color(0.3, 0.85, 1.0)
const HEAT := Color(1.0, 0.5, 0.18)

var _rng := RandomNumberGenerator.new()
var _june: Node3D = null
var _june_fallback := false
var _boss: Node3D = null
var _boss_type := "boss_mother"
var _phase := 1
var _fight_on := false
var _fallback_boss := false
var _ending_busy := false
var _crystal_lights: Array = []   # [OmniLight3D, base_energy, phase]
var _tom_fig: Node3D = null
var _vent_ready := [0.0, 0.0]
var _valves: Array = []
var _vent_pos := [Vector3(-15.2, 0, -20), Vector3(18.0, 0, -20)]
var _station_light: OmniLight3D
var _breach_light: OmniLight3D
var _key_cyan: OmniLight3D
var _crystal_mat: StandardMaterial3D
var _filament_mat: StandardMaterial3D
var _hum := 0.0

# ================================================================== build
func build() -> void:
	_rng.seed = 6606
	env_interior(0.16, 0.035, Color(0.35, 0.55, 0.75))
	var e := env.environment
	e.volumetric_fog_albedo = Color(0.45, 0.65, 0.78)
	e.volumetric_fog_emission = Color(0.01, 0.03, 0.045)
	e.volumetric_fog_length = 70.0
	e.tonemap_exposure = 1.25
	e.glow_intensity = 0.9
	e.ssr_enabled = true
	Sfx.ambience("amb_cavern")
	footstep = "concrete"
	_crystal_mat = _mk_crystal_mat()
	_filament_mat = Mats.color(Color(0.55, 0.85, 0.95, 0.5), 0.2)
	_filament_mat.emission_enabled = true
	_filament_mat.emission = Color(0.1, 0.5, 0.7)
	_filament_mat.emission_energy_multiplier = 0.8
	add_spawn("start", Vector3(0, 0.05, 62.0), PI)

	_build_shell()
	_build_lake()
	_build_mine_mouth()
	_build_path_dressing()
	_build_nook()
	_build_arena()
	_build_pipeline()
	_build_station()
	_build_lattice_wall()
	_build_crystals()
	_build_hanging_bodies()
	_build_items()
	_build_enemies()
	_build_npcs()
	_build_triggers()

func _mk_crystal_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.35, 0.85, 1.0, 0.38)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.08
	m.metallic_specular = 0.9
	m.emission_enabled = true
	m.emission = Color(0.12, 0.7, 1.0)
	m.emission_energy_multiplier = 1.7
	return m

# ------------------------------------------------------------------ helpers
func _mass(x0: float, z0: float, x1: float, z1: float, y0 := -3.0, y1 := 21.0, mat := "rock") -> void:
	box(Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5), Vector3(abs(x1 - x0), y1 - y0, abs(z1 - z0)), mat)

func _barrier(center: Vector3, size: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	sb.position = center
	geo.add_child(sb)

func _boulder(pos: Vector3, size: Vector3, solid := true) -> void:
	var rot := Vector3(_rng.randf_range(-0.25, 0.25), _rng.randf_range(0, TAU), _rng.randf_range(-0.25, 0.25))
	Props.box(geo, size, pos + Vector3(0, size.y * 0.4, 0), Mats.get_mat("rock" if _rng.randf() > 0.4 else "rock_wet"), solid, rot)

func _crystal(pos: Vector3, h: float, r: float, tilt := Vector3.ZERO, solid := false, lit := false) -> void:
	var up := Basis.from_euler(tilt) * Vector3.UP
	Props.cyl(geo, r, h, pos + up * h * 0.5, _crystal_mat, solid, 0.0, tilt, 6)
	if r > 0.5:
		# twin shard
		var t2 := tilt + Vector3(_rng.randf_range(-0.35, 0.35), 0, _rng.randf_range(-0.35, 0.35))
		var up2 := Basis.from_euler(t2) * Vector3.UP
		Props.cyl(geo, r * 0.55, h * 0.7, pos + up2 * h * 0.35 + Vector3(r * 0.7, 0, 0), _crystal_mat, false, 0.0, t2, 6)
	if lit:
		var l := light(pos + up * h * 0.5, CYAN, 3.0, min(h * 1.6, 22.0), false)
		_crystal_lights.append([l, 3.0, _rng.randf() * TAU])

func _steam(pos: Vector3, dir: Vector3, amount := 40, size := 0.8, speed := 3.0, alpha := 0.14, life := 2.2, emitting := true) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.direction = dir
	p.spread = 14.0
	p.initial_velocity_min = speed * 0.6
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, 0.5, 0)
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 8
	sm.rings = 4
	p.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.85, 0.9, 0.95, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p.material_override = m
	p.emitting = emitting
	add_child(p)
	p.position = pos
	return p

func _hang_body(x: float, z: float, y_top: float, yaw := 0.0) -> void:
	# a frozen person wrapped in crystal filaments, hanging from the ceiling (y=20)
	var r := Node3D.new()
	r.position = Vector3(x, y_top, z)
	r.rotation.y = yaw
	r.rotation.z = _rng.randf_range(-0.12, 0.12)
	geo.add_child(r)
	var skin := Mats.get_mat("skin_dead")
	var cloth := Mats.color(Color(0.25, 0.28, 0.33), 0.9)
	Props.cyl(r, 0.2, 0.7, Vector3(0, 0.0, 0), cloth, false)                  # torso
	Props.sphere(r, 0.13, Vector3(0, 0.5, 0.0), skin)                          # head (bowed)
	Props.cyl(r, 0.08, 0.75, Vector3(-0.11, -0.7, 0), cloth, false)
	Props.cyl(r, 0.08, 0.75, Vector3(0.11, -0.7, 0.05), cloth, false)
	Props.cyl(r, 0.06, 0.65, Vector3(-0.3, 0.12, 0), cloth, false, -1.0, Vector3(0, 0, 0.5))
	Props.cyl(r, 0.06, 0.65, Vector3(0.3, 0.12, 0), cloth, false, -1.0, Vector3(0, 0, -0.5))
	Props.cyl(r, 0.42, 2.0, Vector3(0, -0.15, 0), _filament_mat, false, 0.25, Vector3.ZERO, 8)  # cocoon
	var top := 20.0 - y_top
	for i in 3:
		var fx := _rng.randf_range(-0.15, 0.15)
		Props.cyl(r, 0.012, top, Vector3(fx, 0.9 + top * 0.5, _rng.randf_range(-0.1, 0.1)), _filament_mat, false, -1.0, Vector3.ZERO, 4)

# ------------------------------------------------------------------ shell
func _build_shell() -> void:
	# floors (rock slabs 3m thick so there is no void underneath)
	floor_rect(-2.0, 44.0, 2.5, 67.0, 0.0, "rock", 3.0)       # descent, upper leg
	floor_rect(0.0, 22.0, 5.0, 46.0, 0.0, "rock", 3.0)        # descent, lower leg
	floor_rect(5.0, 30.0, 12.0, 36.0, 0.0, "rock", 3.0)       # nook
	floor_rect(-17.0, -32.0, 19.0, 24.0, 0.0, "rock", 3.0)    # arena
	# a few dressing patches of wet rock on the floor
	for i in 5:
		box(Vector3(_rng.randf_range(-12, 14), 0.01, _rng.randf_range(-24, 14)), Vector3(_rng.randf_range(2, 5), 0.02, _rng.randf_range(2, 5)), "rock_wet", false, _rng.randf() * TAU)
	# ceiling
	ceiling_rect(-46.0, -41.0, 31.0, 68.0, 20.0, "rock", 3.0)
	# outer walls
	_mass(-47.0, -41.0, -45.0, 68.0)
	_mass(-47.0, -43.0, 31.0, -40.0)
	_mass(-47.0, 67.0, 31.0, 70.0)
	_mass(30.0, -43.0, 33.0, 70.0)
	# east mass beside the path (with the nook cut out)
	_mass(2.5, 46.0, 30.0, 67.0)
	_mass(5.0, 36.0, 30.0, 46.0)
	_mass(5.0, 24.0, 30.0, 30.0)
	_mass(12.0, 30.0, 30.0, 36.0)
	# arena east wall (pipeline wall)
	_mass(19.0, -42.0, 30.0, 24.0)
	# back wall (the lattice wall)
	_mass(-47.0, -42.0, 31.0, -33.0)
	# low overhang above the lower leg: the Hanger's ceiling
	box(Vector3(2.0, 5.0, 41.0), Vector3(8.5, 1.2, 7.0), "rock")
	# nook ceiling (cosy low roof)
	ceiling_rect(5.0, 30.0, 12.0, 36.0, 3.4, "rock", 0.8)
	# lake barriers (invisible, tall) + low visible rim stones
	_barrier(Vector3(-2.3, 2, 55), Vector3(0.4, 6, 22))
	_barrier(Vector3(-1.15, 2, 44.0), Vector3(2.4, 6, 0.4))
	_barrier(Vector3(-0.3, 2, 33.5), Vector3(0.4, 6, 23))
	_barrier(Vector3(-8.5, 2, 24.1), Vector3(17.0, 6, 0.4))
	_barrier(Vector3(-17.2, 2, -4), Vector3(0.4, 6, 56))
	for i in 14:
		_boulder(Vector3(-2.4 + _rng.randf_range(-0.3, 0.2), -0.2, 66 - i * 1.6), Vector3(0.7, _rng.randf_range(0.5, 0.9), _rng.randf_range(0.9, 1.5)), false)
	for i in 12:
		_boulder(Vector3(-0.4, -0.2, 45 - i * 1.9), Vector3(0.7, _rng.randf_range(0.5, 0.9), _rng.randf_range(0.9, 1.5)), false)
	for i in 10:
		_boulder(Vector3(-17.2, -0.2, 22 - i * 5.4), Vector3(0.9, _rng.randf_range(0.5, 1.1), _rng.randf_range(1.2, 2.4)), false)
	for i in 8:
		_boulder(Vector3(-15.5 + i * 2.1, -0.2, 24.0), Vector3(_rng.randf_range(1.2, 2.2), _rng.randf_range(0.5, 0.9), 0.9), false)
	# stalactites
	for i in 46:
		var sx := _rng.randf_range(-44, 28)
		var sz := _rng.randf_range(-38, 65)
		var len := _rng.randf_range(2.5, 9.0)
		var rr := _rng.randf_range(0.2, 0.7)
		Props.cyl(geo, 0.04, len, Vector3(sx, 20.0 - len * 0.5, sz), Mats.get_mat("rock_wet"), false, rr, Vector3.ZERO, 7)
	# a few stalagmites on the lake shore side of the arena + path
	for i in 10:
		var gx := _rng.randf_range(-16, 18)
		var gz := _rng.randf_range(-28, 20)
		if abs(gx) < 3 and gz > -6:
			continue
		var gh := _rng.randf_range(0.8, 2.2)
		Props.cyl(geo, _rng.randf_range(0.25, 0.5), gh, Vector3(gx, gh * 0.5, gz), Mats.get_mat("rock"), false, 0.05, Vector3.ZERO, 7)

func _build_lake() -> void:
	# lake bed, dark reflective surface, crystal islands
	box(Vector3(-23.0, -3.2, 12.0), Vector3(44.0, 0.4, 110.0), "rock_wet", true)
	var wm: StandardMaterial3D = Mats.get_mat("water").duplicate()
	wm.albedo_color = Color(0.015, 0.03, 0.04, 0.94)
	wm.roughness = 0.03
	wm.metallic = 0.35
	wm.metallic_specular = 1.0
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	Props.box(geo, Vector3(44.0, 0.05, 108.0), Vector3(-23.0, -0.45, 13.0), wm, false)
	# drowned rubble near the shore, and a pale drifting film of frost on the water
	var fm := Mats.color(Color(0.8, 0.9, 1.0, 0.18), 0.4)
	for i in 8:
		Props.cyl(geo, _rng.randf_range(1.5, 3.5), 0.03, Vector3(_rng.randf_range(-40, -6), -0.42, _rng.randf_range(-30, 62)), fm, false, -1.0, Vector3.ZERO, 12)
	# island with the helmeted watcher (Tom?)
	_boulder(Vector3(-11.0, -0.5, 34.0), Vector3(3.6, 1.4, 3.0), false)
	_boulder(Vector3(-12.2, -0.5, 35.4), Vector3(2.0, 1.0, 2.0), false)
	# drip sounds
	for i in 3:
		var n := Node3D.new()
		add_child(n)
		n.position = Vector3(-8.0 - i * 8.0, 1, 50.0 - i * 24.0)
		Sfx.attach_loop("water_drip", n, -14.0)

func _build_mine_mouth() -> void:
	# the service drift they came down through (south wall)
	var wood := Mats.get_mat("wood", 1.0)
	Props.box(geo, Vector3(0.4, 3.4, 0.4), Vector3(-1.9, 1.7, 66.6), wood, true)
	Props.box(geo, Vector3(0.4, 3.4, 0.4), Vector3(2.4, 1.7, 66.6), wood, true)
	Props.box(geo, Vector3(5.1, 0.45, 0.5), Vector3(0.25, 3.5, 66.6), wood, true)
	# gap in wall reads as the tunnel: dark box behind with a small lamp
	Props.box(geo, Vector3(4.2, 3.2, 0.2), Vector3(0.25, 1.6, 67.2), Mats.color(Color(0.01, 0.01, 0.015), 1.0), false)
	Props.sign(geo, Vector3(0.25, 3.0, 66.3), PI, "LOWER KETTLE — LEVEL 6 — BRINE", 26, Color(0.85, 0.8, 0.5))
	# ore-cart rails run a few metres into the cavern, then stop at the broken edge
	for i in 6:
		Props.box(geo, Vector3(0.08, 0.05, 1.0), Vector3(-0.6, 0.03, 65.0 - i * 1.1), Mats.get_mat("metal_rust"), false)
		Props.box(geo, Vector3(0.08, 0.05, 1.0), Vector3(0.9, 0.03, 65.0 - i * 1.1), Mats.get_mat("metal_rust"), false)
		Props.box(geo, Vector3(1.8, 0.05, 0.14), Vector3(0.15, 0.0, 65.0 - i * 1.1), wood, false)
	Props.box(geo, Vector3(1.4, 0.7, 2.2), Vector3(0.15, 0.4, 59.4), Mats.get_mat("metal_rust"), true, Vector3(0, 0.15, 0.25))
	# dropped Northline work light on a tripod: warm pool at the top of the descent
	for k in 3:
		var a := k * TAU / 3.0
		Props.cyl(geo, 0.015, 1.5, Vector3(1.6 + cos(a) * 0.25, 0.7, 63.4 + sin(a) * 0.25), Mats.get_mat("metal"), false, -1.0, Vector3(sin(a) * 0.25, 0, -cos(a) * 0.25), 5)
	Props.box(geo, Vector3(0.5, 0.35, 0.2), Vector3(1.6, 1.55, 63.4), Mats.emissive(Color(1.0, 0.85, 0.6), 2.5), false, Vector3(0.4, 0.5, 0))
	spot(Vector3(1.6, 1.6, 63.4), Vector3(-0.5, 0.0, 56.0), Color(1.0, 0.82, 0.55), 9.0, 16.0, 40.0, true)
	light(Vector3(0.2, 2.6, 64.0), Color(1.0, 0.8, 0.5), 0.8, 7.0, false)

func _build_path_dressing() -> void:
	# Ruth's resting place (sleeping bag, dead lantern) beside the path — her last note is here
	Props.box(geo, Vector3(0.7, 0.12, 1.8), Vector3(-1.1, 0.07, 52.0), Mats.color(Color(0.3, 0.12, 0.12), 1.0), false, Vector3(0, 0.1, 0))
	Props.cyl(geo, 0.1, 0.22, Vector3(-0.3, 0.12, 51.0), Mats.get_mat("metal_rust"), false)
	Props.box(geo, Vector3(0.18, 0.04, 0.18), Vector3(-1.5, 0.08, 53.0), Mats.get_mat("paper"), false)
	_crystal(Vector3(-1.5, 0, 50.0), 1.1, 0.14, Vector3(0.2, 0, -0.3))
	_crystal(Vector3(-0.9, 0, 54.0), 0.8, 0.12, Vector3(-0.25, 0, 0.2))
	# frozen miners along the path
	Props.corpse(geo, Vector3(1.4, 0.0, 48.5), 0.8, {})
	Props.corpse(geo, Vector3(3.6, 0.0, 33.0), 2.4, {})
	Props.debris(geo, Vector3(1.2, 0, 56.0), 0.3, 4, "rock")
	Props.debris(geo, Vector3(3.8, 0, 40.5), 1.1, 4, "rock")
	# pipeline service pipes, running down the east wall of the path to the arena
	Props.pipe(geo, Vector3(2.35, 3.4, 66.0), Vector3(2.35, 3.4, 47.0), 0.22, "metal_painted")
	Props.pipe(geo, Vector3(2.35, 2.6, 66.0), Vector3(2.35, 2.6, 47.0), 0.12, "metal_rust")
	Props.pipe(geo, Vector3(4.9, 3.6, 46.0), Vector3(4.9, 3.6, 31.0), 0.22, "metal_painted")
	for i in 5:
		Props.box(geo, Vector3(0.25, 0.4, 0.4), Vector3(2.3, 3.0, 64.0 - i * 4.0), Mats.get_mat("metal"), false)
	Props.sign(geo, Vector3(2.2, 2.2, 60.0), -PI * 0.5, "MERIDIAN HEAT RECOVERY — FEED 2 — DO NOT ENTER", 22, Color(1.0, 0.7, 0.3))
	# crystals lining the path (cyan fills)
	_crystal(Vector3(3.2, 0.0, 61.0), 2.4, 0.3, Vector3(0.0, 0, 0.2), false, true)
	_crystal(Vector3(-3.5, -0.5, 47.0), 3.8, 0.5, Vector3(0.1, 0, -0.35), false, true)
	_crystal(Vector3(6.0, 0.0, 43.5), 1.6, 0.25, Vector3(-0.1, 0, -0.2))
	_crystal(Vector3(-1.9, -0.4, 38.0), 2.6, 0.35, Vector3(0.1, 0, -0.5))
	_crystal(Vector3(4.5, 0.0, 26.0), 3.0, 0.45, Vector3(0.0, 0, 0.15), false, true)

func _build_nook() -> void:
	# last safe place: a sheltered alcove with a lamp, the field radio and a supply crate
	wall(Vector2(5.0, 30.0), Vector2(12.0, 30.0), 3.4, "rock", 0.0, 0.3)
	light(Vector3(8.5, 2.7, 33.0), Color(1.0, 0.72, 0.4), 3.2, 9.5, true)
	light(Vector3(6.0, 1.2, 33.0), Color(1.0, 0.65, 0.35), 0.8, 4.0, false)
	Props.cyl(geo, 0.05, 0.4, Vector3(8.5, 3.15, 33.0), Mats.get_mat("metal"), false)
	Props.sphere(geo, 0.12, Vector3(8.5, 2.85, 33.0), Mats.emissive(Color(1.0, 0.8, 0.5), 3.0))
	Props.table(geo, Vector3(10.6, 0, 32.0), 0.0, Vector2(1.6, 0.8))
	save_point(Vector3(10.4, 0.78, 32.0), PI * 0.5)
	item_box(Vector3(10.8, 0, 34.8), PI)
	Props.box(geo, Vector3(2.0, 0.15, 0.9), Vector3(7.2, 0.2, 35.0), Mats.color(Color(0.22, 0.28, 0.2), 1.0), false)   # cot
	Props.box(geo, Vector3(0.5, 0.1, 0.4), Vector3(6.4, 0.32, 35.0), Mats.color(Color(0.7, 0.7, 0.65), 1.0), false)
	Props.crate(geo, Vector3(6.0, 0, 31.0), 0.4, 0.7)
	Props.barrel(geo, Vector3(11.4, 0, 30.8), 0.0, true)
	Props.sign(geo, Vector3(8.5, 2.2, 35.85), PI, "NORTHLINE — PUMP STN 3 — REFUGE", 24, Color(0.9, 0.85, 0.6))
	# supplies
	note("l6_log", Vector3(10.2, 0.8, 31.8), "Pump Station 3 — Last Log",
		"[b]NORTHLINE MINERAL — LOWER KETTLE\nPUMP STATION 3 — OPERATOR LOG[/b]\n\n[i]D. Ostrowski, night shift[/i]\n\n02:10  Brine temp +4 over setpoint. Meridian heat feed at 118% of contract. Called Meridian ops. Voice said, \"Uptime is within tolerance.\" Asked who I was talking to. Got a ticket number.\n\n02:40  Lattice has grown across the east drift. It is not on any survey. It hums. My dead brother is on the intercom. Turned the intercom off. He is still on it.\n\n03:05  Crew stopped answering. Found Bobby asleep at the sump. He was warm. Everyone else is so cold, and he was warm, and I thought: good. Then I saw what was in him.\n\n03:30  I am going to stay at the pumps. If the pumps stop, the lake stops, and maybe so does it. If someone reads this: the feed valves are on the cavern's east wall. Close them. Not the Meridian side. THIS side.\n\n03:34  It's so quiet now.", 0.4)
	_crystal(Vector3(11.2, 0, 31.0), 0.5, 0.1, Vector3(0.1, 0, 0.3))

func _build_arena() -> void:
	# pillars: floor-to-ceiling rock columns, cyan-veined (cover)
	var pillars := [Vector3(-9, 0, 8), Vector3(8, 0, 6), Vector3(-10, 0, -6), Vector3(10, 0, -8), Vector3(-5, 0, -15), Vector3(5, 0, -16), Vector3(-11, 0, -22), Vector3(12, 0, -23)]
	for p in pillars:
		var r := _rng.randf_range(1.0, 1.5)
		Props.cyl(geo, r, 20.0, p + Vector3(0, 10, 0), Mats.get_mat("rock_wet"), true, r * 0.7, Vector3.ZERO, 10)
		# crystal growths on the pillar base
		_crystal(p + Vector3(r * 0.9, 0, 0.3), 2.2, 0.32, Vector3(0, 0, -0.45), false, false)
		_crystal(p + Vector3(-r * 0.8, 0, -0.5), 1.6, 0.26, Vector3(0.3, 0, 0.5), false, false)
		var gl := light(p + Vector3(0, 2.2, 0), CYAN, 1.3, 7.0, false)
		_crystal_lights.append([gl, 1.3, _rng.randf() * TAU])
	# boulders as low cover
	for i in 14:
		_boulder(Vector3(_rng.randf_range(-15, 17), 0, _rng.randf_range(-26, 20)), Vector3(_rng.randf_range(0.8, 1.8), _rng.randf_range(0.6, 1.1), _rng.randf_range(0.8, 1.8)))
	# June's hiding place: a rock cluster in the south-east corner
	_boulder(Vector3(14.5, 0, 15.5), Vector3(3.0, 1.8, 2.0))
	_boulder(Vector3(17.3, 0, 13.6), Vector3(2.0, 1.5, 3.2))
	_boulder(Vector3(15.5, 0, 12.2), Vector3(2.4, 1.2, 1.4))
	# Northline sampling station beside the lake (Imogen's label)
	Props.table(geo, Vector3(-13.5, 0, 14.0), 0.3, Vector2(1.6, 0.8))
	Props.crate(geo, Vector3(-14.8, 0, 12.4), 0.2, 0.6)
	Props.box(geo, Vector3(0.14, 0.3, 0.14), Vector3(-13.9, 0.93, 13.8), Mats.color(Color(0.5, 0.8, 0.9, 0.5), 0.1), false)
	Props.box(geo, Vector3(0.12, 0.25, 0.12), Vector3(-13.3, 0.9, 14.2), Mats.color(Color(0.5, 0.8, 0.9, 0.5), 0.1), false)
	note("l6_label", Vector3(-13.6, 0.8, 14.5), "Sample Label — Final",
		"[b]NORTHLINE GEOSCIENCE — SAMPLE LABEL[/b]\nSite: Lower Kettle, Brine Cavern, Lattice Face A\nCollected: Dec 20, 23:50 (self)\nCollector: I. HART, PhD\n\n[i]Specimen is the colony itself. Viable. Metabolic rate rises with ambient heat, 4x per 10 C. It does not eat the heat. It SENDS it somewhere.[/i]\n\nTo whoever opens this cooler:\nI wanted proof so badly I let it keep burning for eight months. I wrote 'recommend immediate shutdown' eleven times. Legal rewrote it 'recommend continued monitoring' eleven times.\n\nDo not carry this out. Do not give it to Corvane. Burn it with the rest of it.\n\nI was right. That was never the same as being good.", 0.2)
	# a sealed Northline cooler (dressing)
	Props.box(geo, Vector3(0.7, 0.4, 0.45), Vector3(-12.6, 0.2, 13.6), Mats.get_mat("metal_painted"), true)

func _build_pipeline() -> void:
	# Northline/Meridian heat pipeline bursts through the east wall high up, venting steam
	var pm := Mats.get_mat("metal_painted", 1.0)
	Props.pipe(geo, Vector3(31.0, 9.0, -20.0), Vector3(19.0, 9.0, -20.0), 1.1, "metal_painted")
	# ragged flange + breach glow
	var ring := Mats.emissive(Color(1.0, 0.45, 0.12), 3.5)
	Props.cyl(geo, 1.3, 0.35, Vector3(18.7, 9.0, -20.0), ring, false, -1.0, Vector3(0, 0, PI * 0.5), 14)
	Props.cyl(geo, 1.7, 0.5, Vector3(19.9, 9.0, -20.0), Mats.get_mat("metal_rust"), false, -1.0, Vector3(0, 0, PI * 0.5), 14)
	for i in 8:
		var a := i * TAU / 8.0
		Props.box(geo, Vector3(0.25, 0.9, 0.35), Vector3(18.6, 9.0 + sin(a) * 1.4, -20.0 + cos(a) * 1.4), Mats.get_mat("metal_rust"), false, Vector3(a, 0, 0.5))
	# wall damage: glowing seams + fallen rubble
	for i in 9:
		var sy := _rng.randf_range(4, 13)
		var sz := -20.0 + _rng.randf_range(-5, 5)
		Props.box(geo, Vector3(0.1, _rng.randf_range(1.0, 3.0), 0.12), Vector3(18.92, sy, sz), Mats.emissive(Color(1.0, 0.4, 0.1), 2.2), false, Vector3(0, 0, _rng.randf_range(-0.4, 0.4)))
	for i in 7:
		_boulder(Vector3(17.5 + _rng.randf_range(-1.2, 1.0), 0, -20.0 + _rng.randf_range(-3, 3)), Vector3(_rng.randf_range(0.5, 1.2), _rng.randf_range(0.4, 0.9), _rng.randf_range(0.5, 1.2)), false)
	# manifold across the cavern ceiling to the west wall + risers to the two valves
	Props.pipe(geo, Vector3(19.0, 9.0, -20.0), Vector3(-16.0, 9.0, -20.0), 0.45, "metal_painted")
	Props.pipe(geo, Vector3(18.0, 9.0, -20.0), Vector3(18.0, 1.4, -20.0), 0.3, "metal_painted")
	Props.pipe(geo, Vector3(-15.2, 9.0, -20.0), Vector3(-15.2, 1.4, -20.0), 0.3, "metal_painted")
	# nozzle branches that point at the lattice wall (they spray when vented)
	Props.pipe(geo, Vector3(8.0, 9.0, -20.0), Vector3(5.5, 7.0, -28.5), 0.2, "metal_painted")
	Props.pipe(geo, Vector3(-7.0, 9.0, -20.0), Vector3(-5.5, 7.0, -28.5), 0.2, "metal_painted")
	# flanges along the manifold
	for i in 7:
		Props.cyl(geo, 0.6, 0.18, Vector3(15.0 - i * 5.0, 9.0, -20.0), pm, false, -1.0, Vector3(0, 0, PI * 0.5), 12)
	# heat: orange key light + steam
	_breach_light = light(Vector3(16.5, 8.5, -19.0), HEAT, 9.0, 24.0, true, true)
	_breach_light.light_volumetric_fog_energy = 2.0
	light(Vector3(16.0, 2.0, -20.0), Color(1.0, 0.45, 0.15), 1.6, 9.0, false)
	_steam(Vector3(18.0, 9.0, -20.0), Vector3(-1, -0.2, 0), 70, 1.6, 4.0, 0.16, 3.0)
	_steam(Vector3(18.3, 9.0, -20.0), Vector3(-1, 0.8, 0), 40, 1.2, 3.0, 0.12, 3.0)
	# steam valves (interactables)
	for i in 2:
		var vp: Vector3 = _vent_pos[i]
		Props.box(geo, Vector3(0.7, 1.0, 0.7), vp + Vector3(0, 0.5, 0), Mats.get_mat("metal_painted"), true)
		Props.cyl(geo, 0.4, 0.06, vp + Vector3(0, 1.4, 0), Mats.color(Color(0.7, 0.1, 0.08), 0.5, 0.5), false, -1.0, Vector3.ZERO, 16)
		Props.box(geo, Vector3(0.9, 0.06, 0.06), vp + Vector3(0, 1.4, 0), Mats.color(Color(0.7, 0.1, 0.08), 0.5, 0.5), false)
		Props.box(geo, Vector3(0.06, 0.06, 0.9), vp + Vector3(0, 1.4, 0), Mats.color(Color(0.7, 0.1, 0.08), 0.5, 0.5), false)
		Props.sign(geo, vp + Vector3(0.0, 0.7, -0.38 if i == 0 else 0.38), 0.0 if i == 1 else PI, "STEAM RELIEF %d" % (i + 1), 20, Color(1.0, 0.75, 0.3))
		light(vp + Vector3(0, 2.0, 0.6), Color(1.0, 0.55, 0.25), 1.0, 5.0, false)
		var it := interact(vp + Vector3(0, 1.0, 0), "Vent steam valve", func(_p): _vent(i), 2.2)
		_valves.append(it)

func _build_station() -> void:
	# PIPELINE CONTROL: a panel with two big handles on the east wall
	var r := Node3D.new()
	r.position = Vector3(18.8, 0, -4.0)
	r.rotation.y = -PI * 0.5
	geo.add_child(r)
	Props.box(r, Vector3(3.0, 0.9, 0.8), Vector3(0, 0.45, -0.1), Mats.get_mat("metal_painted"), true)
	Props.box(r, Vector3(2.6, 1.7, 0.28), Vector3(0, 1.75, -0.3), Mats.get_mat("metal_painted"), false)
	Props.box(r, Vector3(2.4, 1.3, 0.04), Vector3(0, 1.8, -0.15), Mats.color(Color(0.05, 0.07, 0.07), 0.4, 0.2), false)
	Props.sign(r, Vector3(-0.62, 2.2, -0.1), PI, "MERIDIAN TIE\nPOWER + HEAT", 22, Color(0.5, 0.9, 1.0), false)
	Props.sign(r, Vector3(0.62, 2.2, -0.1), PI, "PIPELINE FEED\nMAIN / FULL", 22, Color(1.0, 0.6, 0.25), false)
	# two big handles in slots
	for i in 2:
		var hx := -0.62 if i == 0 else 0.62
		var hc := Color(0.2, 0.55, 0.85) if i == 0 else Color(0.85, 0.2, 0.1)
		Props.box(r, Vector3(0.16, 1.0, 0.08), Vector3(hx, 1.45, -0.12), Mats.color(Color(0.02, 0.02, 0.02), 0.5), false)
		Props.cyl(r, 0.05, 0.9, Vector3(hx, 1.7, 0.2), Mats.get_mat("metal"), false, -1.0, Vector3(-0.5, 0, 0), 8)
		Props.sphere(r, 0.12, Vector3(hx, 2.05, 0.4), Mats.color(hc, 0.4, 0.2))
		Props.sphere(r, 0.04, Vector3(hx, 1.0, -0.12), Mats.emissive(hc, 3.0))
	_station_light = light(Vector3(16.8, 3.2, -4.0), Color(1.0, 0.55, 0.28), 1.8, 9.0, false)
	Props.box(geo, Vector3(1.6, 0.05, 1.6), Vector3(17.2, 0.02, -4.0), Mats.get_mat("metal"), false)
	interact(Vector3(17.2, 1.0, -4.0), "Use pipeline control", func(_p): _station_use(), 2.4)

func _build_lattice_wall() -> void:
	# the colony's heart: a vast crystalline lattice filling the far wall, Ruth fused into it
	for i in 26:
		var x := -22.0 + i * 1.75 + _rng.randf_range(-0.6, 0.6)
		var h := _rng.randf_range(5.0, 17.0)
		var rr := _rng.randf_range(0.5, 1.5)
		_crystal(Vector3(x, 0, -31.0 + _rng.randf_range(-1.5, 1.0)), h, rr, Vector3(_rng.randf_range(-0.5, 0.2), 0, _rng.randf_range(-0.5, 0.5)), false, false)
	for i in 6:
		var x2 := -15.0 + i * 6.0
		var l := light(Vector3(x2, 5.0 + (i % 2) * 3.0, -29.0), CYAN, 3.2, 17.0, false)
		_crystal_lights.append([l, 3.2, _rng.randf() * TAU])
	_key_cyan = light(Vector3(0, 8.0, -23.0), Color(0.35, 0.85, 1.0), 7.0, 28.0, true)
	_key_cyan.light_volumetric_fog_energy = 1.5
	_crystal_lights.append([_key_cyan, 7.0, 0.0])
	# filament curtain
	for i in 18:
		var fx := -13.0 + i * 1.5
		var top := _rng.randf_range(6.0, 12.0)
		Props.cyl(geo, 0.02, top, Vector3(fx, 20.0 - top * 0.5, -27.0 + _rng.randf_range(-2, 2)), _filament_mat, false, -1.0, Vector3.ZERO, 4)
	# the dais of lattice-grown ice under the Mother
	Props.cyl(geo, 5.5, 0.6, Vector3(0, 0.3, -28.0), Mats.get_mat("ice"), false, 4.0, Vector3.ZERO, 16)
	# fallback figure (used only if boss_mother is missing): Ruth's bust fused in the lattice
	if not ResourceLoader.exists("res://actors/enemies/%s.gd" % _boss_type):
		var rr2 := Node3D.new()
		rr2.position = Vector3(0, 4.0, -28.5)
		geo.add_child(rr2)
		Props.cyl(rr2, 0.55, 1.6, Vector3(0, 0, 0), Mats.color(Color(0.55, 0.62, 0.7), 0.6), false, 0.35)
		Props.sphere(rr2, 0.3, Vector3(0, 1.1, 0.0), Mats.get_mat("skin_dead"))
		Props.sphere(rr2, 0.34, Vector3(0, 1.15, -0.05), Mats.color(Color(0.7, 0.72, 0.75), 0.9), Vector3(1, 0.8, 1))
		for s in [-1, 1]:
			Props.cyl(rr2, 0.12, 1.4, Vector3(s * 0.9, 0.2, 0), _crystal_mat, false, 0.03, Vector3(0, 0, s * 1.2))

func _build_crystals() -> void:
	# enormous translucent formations in and around the lake: cyan from within
	var big := [
		[Vector3(-14, -0.5, 6), 15.0, 2.2, Vector3(0.12, 0, -0.1)],
		[Vector3(-26, -0.5, 18), 17.0, 2.8, Vector3(-0.1, 0, 0.15)],
		[Vector3(-30, -0.5, -8), 18.0, 3.0, Vector3(0.1, 0, 0.1)],
		[Vector3(-20, -0.5, -20), 14.0, 2.4, Vector3(0.0, 0, 0.2)],
		[Vector3(-34, -0.5, 40), 16.0, 2.6, Vector3(0.08, 0, -0.12)],
		[Vector3(-18, -0.5, 52), 13.0, 2.0, Vector3(-0.15, 0, 0.1)],
		[Vector3(-8, -0.5, -29), 16.0, 2.4, Vector3(0.1, 0, 0.05)],
		[Vector3(9, 0.0, -30.5), 15.0, 2.2, Vector3(0.1, 0, -0.08)],
	]
	for b in big:
		_crystal(b[0], b[1], b[2], b[3], false, true)
	for i in 14:
		_crystal(Vector3(_rng.randf_range(-42, -4), -0.5, _rng.randf_range(-36, 62)), _rng.randf_range(2.5, 7.0), _rng.randf_range(0.3, 0.8), Vector3(_rng.randf_range(-0.3, 0.3), 0, _rng.randf_range(-0.3, 0.3)), false, i % 3 == 0)

func _build_hanging_bodies() -> void:
	var spots := [Vector2(-6, 14), Vector2(3, 2), Vector2(-8, -10), Vector2(7, -12), Vector2(0, -19), Vector2(-13, -2), Vector2(14, -2), Vector2(-3, 22), Vector2(-5, 36), Vector2(-12, 28), Vector2(-10, 58)]
	for i in spots.size():
		var s: Vector2 = spots[i]
		_hang_body(s.x, s.y, _rng.randf_range(6.5, 12.5), _rng.randf() * TAU)
	# two low ones above the lake edge near the path, visible from the walkway
	_hang_body(-4.5, 50.0, 4.2, 0.4)
	_hang_body(-3.5, 30.0, 4.8, 2.0)

func _build_items() -> void:
	# descent: modest, fair
	pickup("l6_flare_a", "flare", 2, Vector3(1.6, 0.03, 60.0))
	pickup("l6_shell_a", "ammo_shell", 6, Vector3(3.6, 0.03, 50.5))
	pickup("l6_gel_a", "gel", 1, Vector3(1.6, 0.03, 34.0))
	# nook
	pickup("l6_spray", "spray", 1, Vector3(11.0, 0.8, 31.2))
	pickup("l6_44_a", "ammo_44", 6, Vector3(6.3, 0.03, 31.8))
	pickup("l6_gel_b", "gel", 1, Vector3(7.5, 0.4, 34.8))
	# arena (behind pillars and boulders, rewarding a look around)
	pickup("l6_gren", "ammo_grenade", 2, Vector3(-12.5, 0.03, 9.5))
	pickup("l6_shell_b", "ammo_shell", 6, Vector3(-13.5, 0.03, -10.5))
	pickup("l6_44_b", "ammo_44", 6, Vector3(7.5, 0.03, -2.0))
	pickup("l6_flare_b", "flare", 2, Vector3(16.5, 0.03, 10.8))
	pickup("l6_gel_c", "gel", 1, Vector3(-3.0, 0.03, -12.0))

func _build_enemies() -> void:
	# descent: a few Rimebound, placed with intent
	enemy("l6_sleeper", "zombie", Vector3(-0.2, 0, 55.5), 0.7, {"variant": "miner", "sleeping": true})
	enemy("l6_z1", "zombie", Vector3(1.0, 0, 47.0), 3.0, {"variant": "worker"})
	enemy("l6_hanger", "hanger", Vector3(2.0, 4.2, 41.0), 0.0, {"on_ceiling": true})
	enemy("l6_crawl", "zombie", Vector3(3.2, 0, 37.5), 3.0, {"crawler": true})
	enemy("l6_siren", "siren", Vector3(2.6, 0, 20.0), PI, {})
	enemy("l6_z2", "zombie", Vector3(-2.0, 0, 14.0), 0.0, {"variant": "civilian"})
	# THE HOLLOW MOTHER (dormant until revealed)
	if Game.has_flag("mother_dead"):
		return
	var revealed := Game.has_flag("l6_revealed")
	var phase2_pending := Game.has_flag("dead:l6_mother") and not Game.has_flag("dead:l6_mother_p2")
	if ResourceLoader.exists("res://actors/enemies/%s.gd" % _boss_type):
		if phase2_pending:
			_phase = 2
			_boss = enemy("l6_mother_p2", _boss_type, Vector3(0, 0, -22.0), 0.0, {"phase": 2, "dormant": not revealed})
		else:
			_boss = enemy("l6_mother", _boss_type, Vector3(0, 0, -27.0), 0.0, {"phase": 1, "dormant": not revealed})
	else:
		# fallback so the level still completes: a tough lattice-grown husk on the dais
		_fallback_boss = true
		_boss = enemy("l6_mother", "zombie", Vector3(0, 0.6, -27.0), 0.0, {"variant": "civilian", "dormant": not revealed, "max_hp": 900.0, "hp": 900.0, "stagger_threshold": 400.0})
	if _boss != null:
		_boss.died.connect(_on_boss_died)

func _build_npcs() -> void:
	var revealed := Game.has_flag("l6_revealed")
	var dead := Game.has_flag("mother_dead")
	var pos := Vector3(1.0, 0, 61.0)
	if dead:
		pos = Vector3(16.0, 0, -2.5)
	elif revealed:
		pos = Vector3(16.5, 0, 14.4)
	_june = _make_npc("june", pos)
	if _june == null:
		return
	if not revealed and not dead:
		_june.set("follow_player", true)
	_june.set("display_name", "June")

func _make_npc(preset: String, pos: Vector3) -> Node3D:
	var n: Node3D = null
	if ResourceLoader.exists("res://actors/npc.gd"):
		var N = load("res://actors/npc.gd")
		n = N.new()
		n.setup_npc(N.preset(preset))
		add_child(n)
	elif ResourceLoader.exists("res://actors/humanoid.gd"):
		n = load("res://actors/humanoid.gd").new()
		n.setup({"height": 1.55, "female": true, "coat": true, "coat_color": Color(0.35, 0.18, 0.2), "hair": Color(0.2, 0.12, 0.08), "headgear": "beanie"})
		add_child(n)
		_june_fallback = true
	if n != null:
		n.position = pos
	return n

func _build_triggers() -> void:
	trigger("l6_t_intro", Vector3(0.2, 1.5, 57.5), Vector3(5, 3, 1.0), _intro_beat)
	trigger("l6_t_tom1", Vector3(0.2, 1.5, 46.0), Vector3(6, 3, 1.0), _tom_beat)
	trigger("l6_t_nook", Vector3(4.0, 1.5, 33.0), Vector3(2, 3, 6), _nook_beat)
	trigger("l6_t_tom_gone", Vector3(2.5, 1.5, 27.0), Vector3(6, 3, 1.0), func(_p):
		if _tom_fig != null and is_instance_valid(_tom_fig):
			_tom_fig.queue_free()
			_tom_fig = null)
	trigger("l6_t_reveal", Vector3(0.0, 1.5, 15.0), Vector3(36, 4, 1.5), _reveal_beat)
	# music: leaving the nook goes back to tension
	trigger("l6_t_tension", Vector3(2.5, 1.5, 27.8), Vector3(6, 3, 0.8), _tension_beat, false)
	# safe zone for the nook
	var sz := Area3D.new()
	sz.add_to_group("safe_zone")
	sz.collision_layer = 0
	sz.collision_mask = 2
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(8.0, 3.2, 6.0)
	cs.shape = sh
	sz.add_child(cs)
	sz.position = Vector3(8.5, 1.6, 33.0)
	add_child(sz)
	# tom's helmeted figure, standing on the island in the lake
	if not Game.has_flag("l6_tom1"):
		_tom_fig = _make_tom_figure(Vector3(-11.0, 0.9, 34.0))

func _make_tom_figure(pos: Vector3) -> Node3D:
	var r := Node3D.new()
	r.position = pos
	r.rotation.y = 0.0
	add_child(r)
	var dark := Mats.color(Color(0.04, 0.045, 0.05), 0.9)
	Props.cyl(r, 0.24, 1.0, Vector3(0, 0.9, 0), dark, false, 0.2)
	Props.cyl(r, 0.1, 0.9, Vector3(-0.12, 0.2, 0), dark, false)
	Props.cyl(r, 0.1, 0.9, Vector3(0.12, 0.2, 0), dark, false)
	Props.sphere(r, 0.13, Vector3(0, 1.55, 0), dark)
	Props.sphere(r, 0.17, Vector3(0, 1.64, 0), Mats.color(Color(0.1, 0.1, 0.08), 0.5, 0.3), Vector3(1, 0.7, 1.1))
	Props.sphere(r, 0.045, Vector3(0, 1.67, 0.18), Mats.emissive(Color(1.0, 0.92, 0.7), 5.0))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.9, 0.7)
	l.light_energy = 0.7
	l.omni_range = 4.0
	l.shadow_enabled = false
	l.position = Vector3(0, 1.7, 0.3)
	r.add_child(l)
	return r

# ================================================================== entry
func on_enter() -> void:
	Sfx.music("music_tension")
	if Game.has_flag("mother_dead"):
		Sfx.music("music_safe")
		Game.set_objective("Reach the pipeline control station.")
		_dim_lattice(0.25)
		return
	if Game.has_flag("l6_revealed"):
		_fight_on = true
		Sfx.music("music_boss")
		Game.set_objective("Destroy the Hollow Mother. The steam valves will scorch the lattice.")
		return
	Game.set_objective("Follow the path down to the brine. Find Ruth.")
	if not Game.has_flag("l6_intro_card"):
		Game.set_flag("l6_intro_card")
		UI.title_card("THE HEART", "Brine cavern, beneath Lower Kettle")

func _process(delta: float) -> void:
	super._process(delta)
	if player == null:
		return
	# the hum: crystal light pulses at ~19Hz felt as a slow throb, stronger as you go deeper
	var depth: float = clamp((64.0 - player.global_position.z) / 90.0, 0.0, 1.0)
	_hum = lerp(_hum, depth, delta)
	var dead := Game.has_flag("mother_dead")
	var amp := 0.18 if dead else 0.25 + 0.35 * _hum
	for c in _crystal_lights:
		var l: OmniLight3D = c[0]
		if is_instance_valid(l):
			l.light_energy = c[1] * (1.0 + amp * sin(_t * 1.9 + c[2])) * (0.3 if dead else 1.0)
	if env != null and env.environment != null and not dead:
		env.environment.adjustment_saturation = 0.82 + 0.1 * sin(_t * 1.9) * _hum
	if _june_fallback and _june != null and _june.position.distance_to(player.global_position) > 2.6 and not Game.has_flag("l6_revealed"):
		var tgt: Vector3 = player.global_position + Vector3(1.0, 0, 1.4)
		tgt.y = 0
		_june.position = _june.position.move_toward(tgt, delta * 2.0)
	# valve prompts show their cooldown
	var now := Time.get_ticks_msec() / 1000.0
	for i in _valves.size():
		var rem: float = _vent_ready[i] - now
		_valves[i].prompt = "Vent steam valve" if rem <= 0.0 else "Valve cooling (%d s)" % int(ceil(rem))

func _dim_lattice(f: float) -> void:
	for c in _crystal_lights:
		c[1] = c[1] * f

# ================================================================== beats
func _npc_walk(n: Node3D, p: Vector3) -> void:
	if n == null:
		return
	if n.has_method("walk_to"):
		await n.walk_to(p)
	else:
		var tw := create_tween()
		tw.tween_property(n, "position", p, 2.5)
		await tw.finished

func _intro_beat(_p) -> void:
	Game.set_flag("l6_intro")
	lock_player(true)
	Sfx.play("heartbeat")
	await say([
		["ELIAS", "You hear that? Not with your ears. It's in the rock."],
		["JUNE", "Nineteen hertz. I measured it on Gran's old scope. It makes people hear things, Dad."],
		["JUNE", "I keep hearing Mom laughing in the kitchen. She's in Arizona."],
		["ELIAS", "Stay close. Don't answer it, whatever it says."],
	])
	lock_player(false)

func _tension_beat(_p) -> void:
	if not _fight_on and not Game.has_flag("mother_dead"):
		Sfx.music("music_tension")

func _tom_beat(_p) -> void:
	Game.set_flag("l6_tom1")
	lock_player(true)
	Sfx.play("stinger_a")
	await say([
		["TOM?", "Eli. Over here, son. Mind the edge. It's slick."],
		["ELIAS", "...Dad."],
		["JUNE", "Dad? Who are you talking to? There's nobody there. Dad."],
		["TOM?", "Fifteen years I've been waiting. You took the long way round."],
		["ELIAS", "You're not him. You don't get to be him."],
	])
	Game.set_objective("Keep going. There is a lamp lit ahead on the right.")
	lock_player(false)

func _nook_beat(_p) -> void:
	if Game.has_flag("l6_nook"):
		Sfx.music("music_safe")
		return
	Game.set_flag("l6_nook")
	Sfx.music("music_safe")
	await say([
		["JUNE", "Somebody lit this on purpose. Someone was still thinking down here."],
		["ELIAS", "Last stop before the floor of the cavern. Save, reload, patch up."],
		["JUNE", "Gran's down there. I can feel it. Is that stupid? It feels like being looked at."],
		["ELIAS", "Not stupid. Stay behind me. When it starts, you find a rock and you get low."],
	])
	Game.set_objective("Rest if you need to. Then head into the cavern.")

func _reveal_beat(_p) -> void:
	Game.set_flag("l6_revealed")
	lock_player(true)
	Sfx.music("music_tension")
	Sfx.play("stinger_b")
	Game.set_objective("")
	await say([
		["JUNE", "Dad. On the wall. That's Gran. That's Gran, isn't it."],
		["RUTH", "Eli. You came. You always did come, in the end."],
		["ELIAS", "Mom. Mom, can you hear me? It's Eli."],
		["RUTH", "I hear everyone, baby. Everyone who ever went cold. It's quiet here. It's so kind."],
		["TOM?", "Eli, it's warm here. Bring June. We can all be warm."],
		["ELIAS", "That's not Dad. Dad's dead. You stole his voice out of her head."],
		["RUTH", "Nobody stole anything. We only keep what you can't. Come closer."],
		["JUNE", "I'm not going, Dad. I'm not going to her. Please."],
		["ELIAS", "June. Behind the rocks, there. Get low and stay put. Whatever you hear."],
		["JUNE", "Dad—"],
		["ELIAS", "I've got this one. Go."],
	])
	if _june != null:
		_june.set("follow_player", false)
		await _npc_walk(_june, Vector3(16.5, 0, 14.4))
		if _june.has_method("look_at_player"):
			_june.look_at_player()
	_start_fight()

func _start_fight() -> void:
	_fight_on = true
	Sfx.music("music_boss")
	if _boss != null and is_instance_valid(_boss):
		if _boss.has_method("wake"):
			_boss.wake()
		_boss.set("dormant", false)
	else:
		# no boss script at all: complete the level after a beat so the game can finish
		lock_player(false)
		UI.toast("The lattice shudders and goes still.")
		await get_tree().create_timer(3.0).timeout
		_mother_down()
		return
	lock_player(false)
	Game.set_objective("Destroy the Hollow Mother. The steam valves on either wall will scorch the lattice.")
	UI.toast("The steam valves (east and west walls) can scorch the lattice.", 5.0)

func _on_boss_died(e: Node) -> void:
	if _fallback_boss:
		_mother_down()
		return
	var auto = e.get("auto_phase2")
	var ph = e.get("phase")
	if _phase == 1 and not (auto == true) and (ph == null or int(ph) <= 1):
		# phase 1 down: spawn phase 2 (Ruth's body tears free)
		_phase = 2
		Game.set_flag("l6_phase2")
		UI.toast("The lattice cracks. Something tears free.", 4.0)
		Sfx.play("ice_shatter")
		FX.explosion(self, e.global_position + Vector3(0, 1.0, 0), 4.0, 0.0)
		var pos: Vector3 = e.global_position
		await get_tree().create_timer(1.2).timeout
		_boss = enemy("l6_mother_p2", _boss_type, pos, 0.0, {"phase": 2})
		if _boss != null:
			_boss.died.connect(_on_boss_died)
			Sfx.music("music_boss")
		else:
			_mother_down()
		return
	_mother_down()

func _mother_down() -> void:
	if Game.has_flag("mother_dead"):
		return
	Game.set_flag("mother_dead")
	_fight_on = false
	lock_player(true)
	Sfx.music("music_safe")
	_dim_lattice(0.3)
	await get_tree().create_timer(1.5).timeout
	await say([
		["RUTH", "Eli..."],
		["RUTH", "Oh. It's cold. It's so cold. I'd forgotten."],
		["ELIAS", "I know, Mom. I'm here."],
		["RUTH", "Tell June... the cold isn't the worst... Be warm. Please, be warm."],
		["TOM?", "..."],
	])
	if _june != null:
		await _npc_walk(_june, Vector3(15.5, 0, -2.0))
		if _june.has_method("look_at_player"):
			_june.look_at_player()
	await say([
		["JUNE", "She's gone, isn't she. The hum stopped."],
		["ELIAS", "Not all of it. Not the pipeline. That's still pushing heat into the dark."],
		["JUNE", "Then that's what's left. The control station, by the east wall."],
	])
	lock_player(false)
	Game.set_objective("Reach the pipeline control station on the east wall.")

# ================================================================== vents
func _vent(i: int) -> void:
	if not _fight_on:
		UI.toast("The manifold is cold. Nothing here to scorch yet.")
		Sfx.play("deny")
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _vent_ready[i]:
		UI.toast("Pressure is still building (%d s)." % int(ceil(_vent_ready[i] - now)))
		Sfx.play("deny")
		return
	_vent_ready[i] = now + 28.0
	Sfx.play("valve")
	var vp: Vector3 = _vent_pos[i]
	_steam(vp + Vector3(0, 1.5, 0), Vector3(0, 1, 0), 60, 1.4, 5.0, 0.2, 2.0).one_shot = true
	var tpos := Vector3(0, 1.2, -27.0)
	if _boss != null and is_instance_valid(_boss):
		tpos = _boss.global_position + Vector3(0, 1.2, 0)
	var nozzle := Vector3(5.5 if i == 1 else -5.5, 7.0, -28.5)
	var jet := _steam(nozzle, (tpos - nozzle).normalized(), 90, 2.2, 9.0, 0.3, 1.2)
	var tw := create_tween()
	tw.tween_interval(3.2)
	tw.tween_callback(func():
		if is_instance_valid(jet):
			jet.emitting = false
			jet.get_tree().create_timer(3.0).timeout.connect(jet.queue_free))
	await get_tree().create_timer(0.7).timeout
	if _boss != null and is_instance_valid(_boss):
		tpos = _boss.global_position + Vector3(0, 1.2, 0)
	UI.toast("Superheated steam rolls over the lattice!")
	FX.explosion(self, tpos, 7.0, 110.0)
	if _boss != null and is_instance_valid(_boss) and _boss.has_method("burn"):
		_boss.burn(30.0, nozzle)

# ================================================================== ending
func _station_use() -> void:
	if not Game.has_flag("mother_dead"):
		UI.toast("The panel is dead. The pipeline is still feeding the Mother.")
		Sfx.play("deny")
		return
	if _ending_busy:
		return
	_ending_busy = true
	lock_player(true)
	Game.set_flag("l6_ending_talk")
	await say([
		["JUNE", "Two handles. That's it? After all this, it's two handles."],
		["ELIAS", "Left one cuts the Meridian tie. Heat feed and power, both. Lake goes dark, town gets its grid back."],
		["ELIAS", "Right one opens the pipeline to full. Brine boils. Nothing survives in that cavern. Nothing."],
		["JUNE", "Gran's still in there, Dad. Whatever's left. And Grandpa's voice. Even if it was never him."],
		["JUNE", "If you burn it, it's over. Corvane calls it a mining accident. Nobody ever pays for any of it."],
		["JUNE", "If you cut it, it sleeps. It doesn't die. Someday somebody turns the heat back on and it wakes up."],
		["ELIAS", "Neither one's clean."],
		["JUNE", "No. I used to think grown-ups just knew which one was right."],
		["JUNE", "Pick the one you can live with, and I'll stand next to you. I'm not leaving this time."],
		["ELIAS", "Neither am I."],
	])
	_show_choice()

func _show_choice() -> void:
	var layer := CanvasLayer.new()
	layer.name = "EndingChoice"
	layer.layer = 120
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.015, 0.03, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	if UI != null and UI.get("theme_res") != null:
		bg.theme = UI.theme_res
	layer.add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.offset_left = -400
	v.offset_right = 400
	v.offset_top = -230
	v.offset_bottom = 230
	v.add_theme_constant_override("separation", 16)
	bg.add_child(v)
	var title := Label.new()
	title.text = "THE PIPELINE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	v.add_child(title)
	var txt := Label.new()
	txt.text = "Two handles. One heat feed, still pushing warmth into the dark.\nWhichever you pull, something Kettle Falls loved goes with it.\nNeither choice is clean."
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size = Vector2(780, 90)
	txt.add_theme_font_size_override("font_size", 20)
	txt.add_theme_color_override("font_color", Color(0.8, 0.82, 0.85))
	v.add_child(txt)
	var chosen := [false]
	var pick := func(ending: String):
		if chosen[0]:
			return
		chosen[0] = true
		Sfx.play("ui_select")
		get_tree().paused = false
		layer.queue_free()
		Game.finish_game(ending)
	var b1 := Button.new()
	b1.text = "CUT MERIDIAN — let it go dark"
	b1.custom_minimum_size = Vector2(780, 68)
	b1.add_theme_font_size_override("font_size", 24)
	b1.pressed.connect(func(): pick.call("dark"))
	v.add_child(b1)
	var d1 := Label.new()
	d1.text = "The heat feed and the data centre die. The colony starves back to sleep. The town gets its power at dawn. Corvane will sue."
	d1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d1.add_theme_font_size_override("font_size", 15)
	d1.add_theme_color_override("font_color", Color(0.55, 0.7, 0.85))
	v.add_child(d1)
	var b2 := Button.new()
	b2.text = "OPEN THE PIPELINE — burn it all"
	b2.custom_minimum_size = Vector2(780, 68)
	b2.add_theme_font_size_override("font_size", 24)
	b2.pressed.connect(func(): pick.call("thaw"))
	v.add_child(b2)
	var d2 := Label.new()
	d2.text = "The brine boils. The colony, and everyone it took, is gone for good. Meridian never goes offline. Nobody is held to account."
	d2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d2.add_theme_font_size_override("font_size", 15)
	d2.add_theme_color_override("font_color", Color(0.95, 0.6, 0.35))
	v.add_child(d2)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	b1.grab_focus()
