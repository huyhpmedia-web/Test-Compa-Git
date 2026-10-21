extends "res://levels/level.gd"
## L2 — KETTLE FALLS CONSOLIDATED SCHOOL  (target ~14 min)
##
## Layout (x east, z south; the school faces +Z toward the courtyard and the road):
##   courtyard  x -26..26, z -10..24      (gate from the road at z=24, exit gate in the east wall)
##   ground floor (y = FY) footprint x -22..22, z -34..-10:
##      west lobby (x-22..-14) | shelter office (x-14..-7) | MAIN HALL (x-7..7) | GYM (x7..22)
##      corridor z-26..-22 along the back of the hall; rear rooms: stair, classroom 2B, shop, nurse, coach
##   basement (y = YB): stair foot + corridor, pipe chase, BOILER ROOM, custodian office (SAFE ROOM),
##      service passage, flooded-and-frozen LOCKER ROOM (reached from the gym or through the boiler room).
##
## Critical path: shed (school_key + flares) -> side door -> shop (fuse_60a, pouch) / coach office (gym_key)
##   -> gym (stealth past Sleepers, kill the siren) -> stairs down to the locker room (hatchet the ice -> valve_handle)
##   -> boiler room: fuse, valve wheel, PURGE -> IGNITE -> OPEN FEED => boiler_on -> classroom 2B (June's chalk message)
##   -> unchain the main doors from inside -> courtyard: THE FOREMAN drags the caretaker away (met_foreman) -> east gate.

const FY := 0.45        # ground floor level
const YB := -3.05       # basement floor level
const HC := 4.2         # ceiling height, ground floor
const HG := 6.5         # gym ceiling height
const TOP := 8.85       # roof level
const PNL := Vector3(-6.5, YB + 1.1, -18.6)     # boiler control panel
const VLV := Vector3(-4.0, YB + 1.7, -25.2)     # feed valve

var _lamps: Array = []          # [Light3D, base_energy, phase, kind, Material|null]   kind: weak | late | steady
var _sleepers: Array = []
var _fires: Array = []          # [pos, Light3D, phase]
var _frost_cold: Array = []     # nodes hidden once the boiler runs
var _powered := false
var _brown := 0.0
var _brown_t := 7.0
var _inside_prev := false
var _basement_prev := false
var _env_amb := 0.55
var _env_fog := 0.028
var _breath: CPUParticles3D
var _breath_t := 2.0
var _fire_t := 0.0
var _purging := false
var _lamp_fuse: MeshInstance3D
var _lamp_purge: MeshInstance3D
var _lamp_flame: MeshInstance3D
var _lamp_feed: MeshInstance3D
var _firebox: OmniLight3D
var _firebox_glow: MeshInstance3D
var _valve_wheel: Node3D
var _ice_sheath: Node3D
var _front_leaves: Array = []
var _front_chain: Array = []
var _front_it: Node3D
var _steam: CPUParticles3D
var _scene_running := false
var _cot_toggle := 0

# ====================================================================== build
func build() -> void:
	_powered = Game.has_flag("boiler_on")
	env_exterior_night(true, 0.028, 0.42)
	add_spawn("from_road", Vector3(0, 0.05, 20.0), PI)
	add_spawn("start", Vector3(0, 0.05, 20.0), PI)
	_build_courtyard()
	_build_facade()
	_build_shell()
	_build_hall()
	_build_west_wing()
	_build_corridor()
	_build_rear_rooms()
	_build_gym()
	_build_basement()
	_build_boiler()
	_build_safe_room()
	_build_locker_room()
	_place_enemies()
	_place_items()
	_place_notes()
	_build_breath()
	_build_indoor_fx()
	if Game.has_flag("l2_front_open") and not Game.has_flag("met_foreman"):
		_make_finale_trigger()
	_apply_power_visuals(true)

func on_enter() -> void:
	Sfx.music("music_tension", -13.0)
	if not Game.has_flag("l2_intro"):
		Game.set_flag("l2_intro")
		UI.title_card("KETTLE FALLS CONSOLIDATED SCHOOL", "The longest night")
		_refresh_objective()
		await get_tree().create_timer(3.5).timeout
		lock_player(true)
		Sfx.play("radio_squelch")
		await say([
			["JUNE (radio)", "Dad? The school lights just came on. Gran ran the warming shelter there. Check the gym."],
			["ELIAS", "Stay where you are, June."],
			["JUNE (radio)", "I don't stay anywhere. You'd know that if you ever called."],
			["ELIAS", "...Fair."],
		])
		lock_player(false)
	else:
		_refresh_objective()

# ====================================================================== process
func _process(delta: float) -> void:
	super._process(delta)
	_update_lamps(delta)
	_update_env(delta)
	_update_sleepers()
	_update_fires(delta)
	_update_breath(delta)

func _update_lamps(delta: float) -> void:
	_brown_t -= delta
	if _brown_t <= 0.0 and not _powered:
		_brown = 0.45
		_brown_t = randf_range(6.0, 14.0)
	_brown = max(0.0, _brown - delta)
	var browned := _brown > 0.0
	for e in _lamps:
		var l: Light3D = e[0]
		if not is_instance_valid(l):
			continue
		var base: float = e[1]
		var ph: float = e[2]
		var kind: String = e[3]
		var f := 1.0
		if kind == "steady":
			f = 1.0
		elif _powered:
			f = 1.0 + 0.05 * sin(_t * 31.0 + ph) * (1.0 if kind == "weak" else 0.0)
		elif kind == "late":
			f = 0.0
		else:
			var n := sin(_t * 23.0 + ph) * sin(_t * 7.3 + ph * 2.0)
			f = 0.55 + 0.1 * sin(_t * 3.0 + ph)
			if n > 0.8:
				f = 0.06
			if browned:
				f *= 0.35
		l.light_energy = base * f
		l.visible = f > 0.01
		var m = e[4]
		if m != null:
			(m as StandardMaterial3D).emission_energy_multiplier = 0.15 + 3.0 * f

func _update_env(delta: float) -> void:
	if player == null or env == null:
		return
	var p := player.global_position
	var inside := p.z < -9.9 and absf(p.x) < 22.1 and p.z > -34.2
	var basement := p.y < -1.2
	if inside != _inside_prev or basement != _basement_prev:
		_inside_prev = inside
		_basement_prev = basement
		Sfx.ambience("amb_interior" if inside else "amb_wind")
	var tgt_amb := 0.55
	var tgt_fog := 0.028
	if inside:
		tgt_amb = 0.16
		tgt_fog = 0.012
	if basement:
		tgt_amb = 0.07
		tgt_fog = 0.010
	var k: float = clamp(delta * 2.5, 0.0, 1.0)
	_env_amb = lerp(_env_amb, tgt_amb, k)
	_env_fog = lerp(_env_fog, tgt_fog, k)
	var e := env.environment
	e.ambient_light_energy = _env_amb
	e.volumetric_fog_density = _env_fog
	if _breath != null:
		_breath.visible = true

func _update_fires(delta: float) -> void:
	_fire_t -= delta
	for f in _fires:
		var l: OmniLight3D = f[1]
		if is_instance_valid(l):
			l.light_energy = 2.4 + 0.9 * sin(_t * 9.0 + f[2]) + 0.6 * sin(_t * 23.0 + f[2] * 3.0)
	if _fire_t <= 0.0:
		_fire_t = 0.6
		for f in _fires:
			for en in get_tree().get_nodes_in_group("enemy"):
				if is_instance_valid(en) and en.has_method("fear") and en.global_position.distance_to(f[0]) < 3.5:
					en.fear(f[0], 2.0)

func _update_breath(delta: float) -> void:
	if _breath == null or player == null:
		return
	_breath_t -= delta
	_breath.global_position = player.global_position + Vector3(0, 1.45, 0) + player.model.global_transform.basis.z * 0.25
	if _breath_t <= 0.0:
		_breath_t = 3.4
		var cold := (not _powered) or player.global_position.z > -9.9
		_breath.emitting = false
		if cold:
			_breath.restart()
			_breath.emitting = true

# ====================================================================== small helpers
var _mc := {}

func _m(key: String, c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	if not _mc.has(key):
		_mc[key] = Mats.color(c, rough, metal)
	return _mc[key]

func _mat(m: Variant) -> Material:
	return Mats.get_mat(m) if m is String else m

func _deco(pos: Vector3, size: Vector3, mat: Variant, rot := Vector3.ZERO) -> MeshInstance3D:
	return Props.box(geo, size, pos, _mat(mat), false, rot)

func _blocker(pos: Vector3, size: Vector3) -> void:
	var mi := Props.box(geo, size, pos, Mats.get_mat("metal"), true)
	mi.visible = false

func _w(x0: float, z0: float, x1: float, z1: float, h: float, mat: Variant, gaps: Array, y0 := FY) -> void:
	wall(Vector2(x0, z0), Vector2(x1, z1), h, mat, y0, 0.25, gaps)

## Doorway helpers. Door root sits on the wall centre line at floor height.
func _dopts(opts: Dictionary) -> Dictionary:
	var o := {"width": 1.4, "height": 2.3}
	o.merge(opts, true)
	return o

func _dx(uid: String, x: float, z: float, opts := {}, y := FY) -> Node3D:
	return door(uid, Vector3(x, y, z), 0.0, _dopts(opts))

func _dz(uid: String, x: float, z: float, opts := {}, y := FY) -> Node3D:
	return door(uid, Vector3(x, y, z), PI * 0.5, _dopts(opts))

func _L(pos: Vector3, col: Color, energy: float, rng: float, shadows := false, kind := "weak", em: Material = null) -> OmniLight3D:
	var l := light(pos, col, energy, rng, shadows, false)
	_lamps.append([l, energy, randf() * 20.0, kind, em])
	return l

## Fluorescent fixture + light. y = ceiling underside.
func _fluor(pos: Vector3, yaw := 0.0, energy := 1.6, rng := 8.0, shadows := false, kind := "weak", col := Color(0.82, 0.9, 1.0)) -> void:
	var r := Node3D.new()
	r.position = pos
	r.rotation.y = yaw
	add_child(r)
	Props.box(r, Vector3(0.25, 0.06, 1.3), Vector3(0, -0.05, 0), Mats.get_mat("metal"), false)
	var em := Mats.emissive(col, 3.0)
	Props.box(r, Vector3(0.18, 0.03, 1.2), Vector3(0, -0.09, 0), em, false)
	_L(pos + Vector3(0, -0.7, 0), col, energy, rng, shadows, kind, em)

## Caged bulb on a cord.
func _bulb(pos: Vector3, energy := 1.5, rng := 7.0, shadows := false, kind := "weak", col := Color(1.0, 0.76, 0.5), drop := 0.5) -> void:
	Props.cyl(geo, 0.012, drop, pos + Vector3(0, -drop * 0.5, 0), Mats.get_mat("metal"), false)
	var em := Mats.emissive(col, 3.0)
	Props.sphere(geo, 0.08, pos + Vector3(0, -drop - 0.06, 0), em)
	_L(pos + Vector3(0, -drop - 0.15, 0), col, energy, rng, shadows, kind, em)

func _red_lamp(pos: Vector3, energy := 1.2, rng := 6.0) -> void:
	var em := Mats.emissive(Color(1.0, 0.1, 0.05), 2.5)
	Props.box(geo, Vector3(0.22, 0.12, 0.12), pos, em, false)
	_L(pos + Vector3(0, -0.1, 0.1), Color(1.0, 0.12, 0.06), energy, rng, false, "steady", null)

func _snow_box(pos: Vector3, size: Vector3) -> void:
	_deco(pos, size, "snow")

func _mound(pos: Vector3, r: float, hs := 0.4, stretch := 1.0) -> void:
	var mi := Props.sphere(geo, r, pos, Mats.get_mat("snow"), Vector3(1.0 * stretch, hs, 1.0))
	mi.rotation.y = randf() * TAU

func _icicles(a: Vector3, b: Vector3, n: int, maxlen := 0.5) -> void:
	var m: Material = Mats.get_mat("ice")
	for i in n:
		var t := (float(i) + randf() * 0.7) / float(n)
		var p := a.lerp(b, t)
		var ln := randf_range(0.12, maxlen)
		Props.cyl(geo, randf_range(0.015, 0.035), ln, p + Vector3(0, -ln * 0.5, 0), m, false, 0.0, Vector3.ZERO, 6)

func _frost_patch(pos: Vector3, sx: float, sz: float, cold := true) -> void:
	var mi := _deco(pos + Vector3(0, 0.012, 0), Vector3(sx, 0.012, sz), _m("frost_floor", Color(0.88, 0.92, 1.0, 0.45), 0.4), Vector3(0, randf() * 3.0, 0))
	if cold:
		_frost_cold.append(mi)

func _leaves(c: Vector3, radius: float, n: int) -> void:
	var cols := [Color(0.22, 0.12, 0.05), Color(0.3, 0.17, 0.07), Color(0.16, 0.1, 0.05), Color(0.35, 0.22, 0.09)]
	for i in n:
		var a := randf() * TAU
		var d := sqrt(randf()) * radius
		var s := randf_range(0.05, 0.11)
		_deco(c + Vector3(cos(a) * d, 0.012, sin(a) * d), Vector3(s, 0.006, s * 0.7), _m("leaf%d" % (i % 4), cols[i % 4], 0.95), Vector3(0, randf() * TAU, 0))

func _chunks(c: Vector3, n: int, spread: float, big := 0.7) -> void:
	for i in n:
		var s := Vector3(randf_range(0.2, big), randf_range(0.12, big * 0.55), randf_range(0.2, big * 0.9))
		var p := c + Vector3(randf_range(-spread, spread), s.y * 0.3, randf_range(-spread, spread))
		var mi := _deco(p, s, "concrete", Vector3(randf_range(-0.5, 0.5), randf() * TAU, randf_range(-0.5, 0.5)))
		if randf() < 0.4:
			_deco(p + Vector3(0, s.y * 0.5 + 0.02, 0), Vector3(s.x * 0.8, 0.05, s.z * 0.8), "snow", mi.rotation)

func _paper_chain(a: Vector3, b: Vector3, sag := 0.4, n := 22) -> void:
	var cols := [Color(0.75, 0.1, 0.1), Color(0.1, 0.5, 0.2), Color(0.85, 0.85, 0.8), Color(0.8, 0.65, 0.1)]
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var p := a.lerp(b, t)
		p.y -= sag * sin(t * PI)
		var dir := (b - a)
		var yaw := atan2(dir.x, dir.z)
		var m := _m("pc%d" % (i % 4), cols[i % 4], 0.9)
		var link := _deco(p, Vector3(0.05, 0.1, 0.16) if i % 2 == 0 else Vector3(0.16, 0.1, 0.05), m, Vector3(0, yaw, 0))

func _coat_pile(pos: Vector3, scale := 1.0) -> void:
	var cols := [Color(0.18, 0.2, 0.28), Color(0.3, 0.12, 0.1), Color(0.14, 0.22, 0.16), Color(0.35, 0.3, 0.22), Color(0.1, 0.1, 0.12)]
	for i in 7:
		var c: Color = cols[i % cols.size()]
		var p := pos + Vector3(randf_range(-0.5, 0.5), 0.12 + (i / 3) * 0.14, randf_range(-0.4, 0.4)) * scale
		var mi := Props.sphere(geo, 0.3 * scale, p, _m("coat%d" % (i % 5), c, 0.95), Vector3(1.4, 0.45, 1.0))
		mi.rotation.y = randf() * TAU
	# frost on top
	Props.sphere(geo, 0.34 * scale, pos + Vector3(0, 0.38 * scale, 0), _m("frost_top", Color(0.85, 0.9, 1.0, 0.4), 0.4), Vector3(1.5, 0.12, 1.1))

func _vine(base: Vector3, height: float, seed_v: int, spread := 1.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var p := base
	var dir := Vector3(rng.randf_range(-0.2, 0.2), 1.0, 0.0).normalized()
	var r := 0.035
	var segs := int(height / 0.45)
	for i in segs:
		dir = (dir + Vector3(rng.randf_range(-0.55, 0.55) * spread, rng.randf_range(0.0, 0.25), 0.0)).normalized()
		dir.y = max(dir.y, 0.35)
		dir = dir.normalized()
		var q := p + dir * rng.randf_range(0.35, 0.6)
		Props.pipe(geo, p, q, r, "bark")
		if rng.randf() < 0.45:
			var side := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.1, 0.6), 0).normalized()
			var e := q + side * rng.randf_range(0.25, 0.7)
			Props.pipe(geo, q, e, r * 0.6, "bark")
			if rng.randf() < 0.5:
				Props.pipe(geo, e, e + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.1, 0.35), 0), r * 0.4, "bark")
		p = q
		r = max(0.014, r * 0.97)

func _hoop(pos: Vector3, yaw: float) -> void:
	var r := Node3D.new()
	r.position = pos
	r.rotation.y = yaw
	add_child(r)
	Props.box(r, Vector3(1.8, 1.05, 0.05), Vector3(0, 0, 0), Mats.color(Color(0.8, 0.82, 0.85, 0.7), 0.2), false)
	Props.box(r, Vector3(0.6, 0.45, 0.012), Vector3(0, -0.12, 0.03), Mats.color(Color(0.9, 0.3, 0.1), 0.5), false)
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.21
	tm.outer_radius = 0.235
	mi.mesh = tm
	mi.material_override = Mats.color(Color(0.85, 0.3, 0.08), 0.4, 0.5)
	mi.position = Vector3(0, -0.4, 0.3)
	r.add_child(mi)
	Props.cyl(r, 0.04, 0.9, Vector3(0, 0.5, -0.1), Mats.get_mat("metal"), false)
	# net icicles
	for i in 6:
		var a := TAU * float(i) / 6.0
		Props.cyl(r, 0.012, 0.3, Vector3(cos(a) * 0.17, -0.58, 0.3 + sin(a) * 0.17), Mats.get_mat("ice"), false, 0.0, Vector3.ZERO, 5)

func _cot(pos: Vector3, yaw: float, shade: Color, state := 0) -> void:
	## state: 0 tidy blanket, 1 rumpled, 2 covered body, 3 occupied (blanket kicked to the foot)
	var r := Node3D.new()
	r.position = pos
	r.rotation.y = yaw
	add_child(r)
	var frame := _m("cot_frame", Color(0.25, 0.27, 0.26), 0.5, 0.6)
	Props.box(r, Vector3(0.8, 0.045, 1.9), Vector3(0, 0.33, 0), _m("cot_canvas", Color(0.3, 0.33, 0.22), 0.95), false)
	for sx in [-1, 1]:
		Props.box(r, Vector3(0.045, 0.045, 1.95), Vector3(sx * 0.4, 0.31, 0), frame, false)
		for sz in [-1, 1]:
			Props.box(r, Vector3(0.04, 0.3, 0.04), Vector3(sx * 0.38, 0.15, sz * 0.85), frame, false)
	Props.box(r, Vector3(0.45, 0.1, 0.3), Vector3(0, 0.42, -0.75), _m("pillow", Color(0.78, 0.78, 0.74), 0.95), false)
	var bm := _m("blk%d" % int(shade.r * 100 + shade.g * 10), shade, 0.97)
	match state:
		0:
			Props.box(r, Vector3(0.74, 0.07, 1.2), Vector3(0, 0.42, 0.2), bm, false)
		1:
			Props.box(r, Vector3(0.7, 0.12, 0.9), Vector3(0.04, 0.44, 0.15), bm, false, Vector3(0.1, 0.25, 0.05))
			Props.box(r, Vector3(0.4, 0.1, 0.5), Vector3(-0.2, 0.4, 0.75), bm, false, Vector3(0, 0.6, 0))
		2:
			Props.box(r, Vector3(0.62, 0.22, 1.7), Vector3(0, 0.46, 0.05), bm, false)
			Props.sphere(r, 0.14, Vector3(0, 0.55, -0.82), bm, Vector3(1, 0.8, 1.1))
			_deco_local(r, Vector3(0.64, 0.02, 1.72), Vector3(0, 0.575, 0.05), _m("frost_blk", Color(0.85, 0.9, 1.0, 0.35), 0.4))
		3:
			Props.box(r, Vector3(0.5, 0.1, 0.4), Vector3(0.1, 0.42, 0.8), bm, false, Vector3(0, 0.5, 0))
	# solid footprint (invisible), low enough to look like a cot but too tall to step over
	var b := Props.box(r, Vector3(0.84, 0.4, 1.95), Vector3(0, 0.2, 0), Mats.get_mat("metal"), true)
	b.visible = false

func _deco_local(r: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	Props.box(r, size, pos, mat, false)

func _chair_s(pos: Vector3, yaw: float, toppled := false) -> void:
	Props.chair(geo, pos, yaw, toppled)

## School desk: table-ish with chair attached.
func _school_desk(pos: Vector3, yaw: float, topple := false) -> void:
	var r := Node3D.new()
	r.position = pos
	r.rotation.y = yaw
	if topple:
		r.rotation.x = randf_range(-1.2, 1.2)
		r.position.y += 0.25
	add_child(r)
	var w := Mats.get_mat("wood", 0.8)
	var mm := _m("desk_metal", Color(0.3, 0.3, 0.32), 0.5, 0.6)
	Props.box(r, Vector3(0.62, 0.035, 0.48), Vector3(0, 0.72, 0), w, not topple)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			Props.box(r, Vector3(0.025, 0.7, 0.025), Vector3(sx * 0.28, 0.35, sz * 0.2), mm, false)
	Props.box(r, Vector3(0.38, 0.03, 0.36), Vector3(0, 0.44, 0.52), mm, false)
	Props.box(r, Vector3(0.38, 0.3, 0.03), Vector3(0, 0.62, 0.7), mm, false)

func _lantern(pos: Vector3, energy := 0.9, rng := 5.0) -> void:
	var r := Node3D.new()
	r.position = pos
	add_child(r)
	Props.cyl(r, 0.07, 0.2, Vector3(0, 0.1, 0), _m("lantern_body", Color(0.12, 0.2, 0.1), 0.5, 0.4), false)
	var em := Mats.emissive(Color(1.0, 0.82, 0.55), 2.5)
	Props.cyl(r, 0.06, 0.14, Vector3(0, 0.12, 0), em, false)
	var l := light(pos + Vector3(0, 0.35, 0), Color(1.0, 0.8, 0.55), energy, rng, false, false)
	_lamps.append([l, energy, randf() * 20.0, "steady", null])
	_fires.append([pos, l, randf() * 10.0])  # lanterns keep Rimebound off a little, too (light flicker)

func _label(text: String, pos: Vector3, yaw: float, size := 32, col := Color(0.9, 0.9, 0.85), px := 0.004) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = col
	l.shaded = true
	l.double_sided = false
	l.position = pos
	l.rotation.y = yaw
	add_child(l)
	return l

func _sign(text: String, pos: Vector3, yaw: float, size := 32, col := Color(0.9, 0.9, 0.85), bg := true) -> void:
	Props.sign(geo, pos, yaw, text, size, col, bg)

# ====================================================================== COURTYARD
func _brick_wall(a: Vector3, b: Vector3, h := 2.3) -> void:
	var d := b - a
	var ln := Vector2(d.x, d.z).length()
	var yaw := atan2(d.x, d.z)
	var mid := (a + b) * 0.5
	box(mid + Vector3(0, h * 0.5, 0), Vector3(0.5, h, ln), "brick_dark", true, yaw)
	box(mid + Vector3(0, h + 0.07, 0), Vector3(0.72, 0.14, ln + 0.1), "concrete", true, yaw)
	_deco(mid + Vector3(0, h + 0.19, 0), Vector3(0.6, 0.1, ln), "snow", Vector3(0, yaw, 0))
	var n := int(ceil(ln / 6.0))
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		box(p + Vector3(0, (h + 0.45) * 0.5, 0), Vector3(0.85, h + 0.45, 0.85), "concrete", true)
		_deco(p + Vector3(0, h + 0.5, 0), Vector3(1.0, 0.12, 1.0), "concrete")
		_deco(p + Vector3(0, h + 0.6, 0), Vector3(0.8, 0.1, 0.8), "snow")

func _iron_gate_leaf(r: Node3D, w: float, h: float, rot := 0.0) -> void:
	var m := _m("iron", Color(0.07, 0.07, 0.08), 0.5, 0.7)
	var n := int(w / 0.16)
	for i in n + 1:
		Props.cyl(r, 0.012, h, Vector3(i * w / n, h * 0.5, 0), m, false)
		Props.sphere(r, 0.025, Vector3(i * w / n, h + 0.02, 0), m)
	for y in [0.25, h * 0.5, h - 0.2]:
		Props.box(r, Vector3(w, 0.035, 0.035), Vector3(w * 0.5, y, 0), m, false)

func _build_courtyard() -> void:
	floor_rect(-26, -10, 26, 24, 0.0, "snow")
	# landscape beyond the walls (non-solid so the void is never seen)
	for spec in [[Vector3(-88, -0.2, -45), Vector3(124, 0.36, 210)], [Vector3(88, -0.2, -45), Vector3(124, 0.36, 210)],
			[Vector3(0, -0.2, -92), Vector3(52, 0.36, 116)], [Vector3(0, -0.2, 42), Vector3(52, 0.36, 36)],
			[Vector3(-24, -0.2, -22), Vector3(4, 0.36, 24)], [Vector3(24, -0.2, -22), Vector3(4, 0.36, 24)]]:
		box(spec[0], spec[1], "snow", false)
	# perimeter wall: south (road gate in the middle), east (exit gate), west (collapsed section)
	_brick_wall(Vector3(-26, 0, 24), Vector3(-3.4, 0, 24))
	_brick_wall(Vector3(3.4, 0, 24), Vector3(26, 0, 24))
	_brick_wall(Vector3(26, 0, 24), Vector3(26, 0, 5.8))
	_brick_wall(Vector3(26, 0, 2.2), Vector3(26, 0, -10))
	_brick_wall(Vector3(-26, 0, 24), Vector3(-26, 0, 13.2))
	_brick_wall(Vector3(-26, 0, 8.8), Vector3(-26, 0, -10))
	_brick_wall(Vector3(26, 0, -10), Vector3(22.2, 0, -10))
	_brick_wall(Vector3(-26, 0, -10), Vector3(-22.2, 0, -10))
	# the road gate: swung shut behind Elias
	for sgn in [-1.0, 1.0]:
		var lf := Node3D.new()
		lf.position = Vector3(sgn * 3.35, 0, 24.0)
		add_child(lf)
		_iron_gate_leaf(lf, 3.35, 2.6)
		lf.scale.x = -sgn
	_blocker(Vector3(0, 1.3, 24.0), Vector3(6.8, 2.6, 0.15))
	interact(Vector3(0, 1.0, 23.0), "Iron gate", func(_p): UI.toast("Locked behind you. Frozen solid. No going back."), 2.4)
	# exit gate (east) — opens once the Foreman has been and gone
	door("l2_exit_gate", Vector3(26, 0, 4.0), PI * 0.5, {"double": true, "width": 3.2, "height": 2.4, "mat": "metal", "to_level": "l3_church", "to_spawn": "from_school", "lock_flag": "met_foreman", "locked_msg": "The gate is chained. Not yet — there is still the school to get through.", "prompt": "Go through the east gate"})
	for z in [1.9, 6.1]:
		_deco(Vector3(25.9, 3.0, z), Vector3(0.12, 0.1, 0.12), "snow")
	_sign("ST. BRENDAN'S  ->  MAIN ST", Vector3(25.55, 2.9, 4.0), -PI * 0.5, 22, Color(0.8, 0.85, 0.6))
	# collapsed west wall: rubble blocks the gap; something dragged through here
	for i in 9:
		_deco(Vector3(-26.0 + randf_range(-0.6, 0.6), randf_range(0.25, 0.9), randf_range(9.1, 12.9)), Vector3(randf_range(0.6, 1.2), randf_range(0.5, 1.1), randf_range(0.6, 1.3)), "brick_dark", Vector3(randf_range(-0.5, 0.5), randf() * TAU, randf_range(-0.5, 0.5)))
	_blocker(Vector3(-26.0, 1.5, 11.0), Vector3(1.6, 3.0, 4.6))
	for i in 5:
		_deco(Vector3(-25.2 + randf_range(-0.4, 0.4), 1.0 + randf_range(0, 0.6), randf_range(9.3, 12.7)), Vector3(0.9, 0.45, 1.0), "snow", Vector3(0, randf() * TAU, 0))
	# lighting: moon + warm portico + lamp + barrel fire at the gate
	Props.lamp_post(geo, Vector3(-11, 0, 9), PI, true, Color(1.0, 0.72, 0.42))
	Props.lamp_post(geo, Vector3(12.5, 0, 14), 0.4, false)
	_fire_barrel(Vector3(-3.6, 0, 17.4))
	# bare trees (reference art)
	for t in [[Vector3(-13.5, 0, -3.8), 12.0, 11], [Vector3(10.5, 0, -2.6), 11.0, 7], [Vector3(-19.5, 0, 5.5), 9.5, 3],
			[Vector3(19.5, 0, 9.5), 10.0, 5], [Vector3(-6.2, 0, 3.4), 8.5, 17], [Vector3(-21.0, 0, 18.5), 9.0, 23],
			[Vector3(22.0, 0, 20.0), 8.0, 29], [Vector3(6.5, 0, 12.5), 7.5, 31]]:
		Props.tree(geo, t[0], t[1], t[2])
		_mound(t[0] + Vector3(0.4, 0, 0.3), 1.0, 0.25, 1.4)
	# distant tree line outside the walls
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 16:
		var side := i % 4
		var p := Vector3.ZERO
		match side:
			0: p = Vector3(rng.randf_range(-24, 24), 0, rng.randf_range(32, 46))
			1: p = Vector3(rng.randf_range(32, 48), 0, rng.randf_range(-30, 30))
			2: p = Vector3(-rng.randf_range(32, 48), 0, rng.randf_range(-30, 30))
			3: p = Vector3(rng.randf_range(-26, 26), 0, -rng.randf_range(42, 60))
		Props.tree(geo, p, rng.randf_range(9, 14), rng.randi())
	# shed (reference art): corrugated, white panelled door
	var shed_pos := Vector3(16.5, 0, -5.0)
	Props.shed(geo, shed_pos, 0.2)
	_build_shed_interior(shed_pos, 0.2)
	# staff cars half buried, a school van
	Props.car(geo, Vector3(-18.5, 0, 15.5), 0.35, Color(0.7, 0.55, 0.1), true, "van")
	Props.car(geo, Vector3(18.0, 0, 18.0), -1.15, Color(0.22, 0.25, 0.3), true)
	_mound(Vector3(-18.5, 0, 14.0), 2.6, 0.3, 1.6)
	_mound(Vector3(18.5, 0, 17.0), 2.2, 0.3, 1.5)
	# benches against the facade, flagpole, signs
	for x in [-9.5, 9.5]:
		Props.bench(geo, Vector3(x, 0, -9.2), 0.0)
		_snow_box(Vector3(x, 0.52, -9.2), Vector3(1.7, 0.06, 0.42))
	Props.cyl(geo, 0.06, 7.0, Vector3(-9.0, 3.5, -2.0), Mats.get_mat("metal"), false)
	_deco(Vector3(-8.5, 6.3, -2.0), Vector3(1.0, 0.6, 0.02), _m("flag", Color(0.18, 0.2, 0.28), 0.95), Vector3(0.1, 0, -0.15))
	Props.cyl(geo, 0.05, 1.8, Vector3(4.2, 0.9, -4.6), _m("sign_post", Color(0.3, 0.2, 0.12), 0.8), false)
	_sign("FRONT DOORS CLOSED", Vector3(4.2, 1.9, -4.5), 0.1, 36, Color(0.95, 0.35, 0.25))
	_sign("SHELTER ENTRANCE:\nWEST DOOR (CUSTODIAL)\nKNOCK. ASK FOR RUTH.", Vector3(4.2, 1.45, -4.5), 0.1, 26, Color(0.85, 0.85, 0.75))
	# dressing: drifts, concrete chunks, leaves, bodies
	_mound(Vector3(-24.5, 0, 5.0), 3.0, 0.3, 1.8)
	_mound(Vector3(24.5, 0, 12.0), 2.8, 0.3, 1.8)
	_mound(Vector3(-24.0, 0, -6.0), 2.2, 0.35, 1.6)
	_mound(Vector3(24.0, 0, -7.0), 2.4, 0.35, 1.6)
	_mound(Vector3(0, 0, 23.0), 2.0, 0.12, 2.5)
	_mound(Vector3(12.0, 0, -7.5), 2.0, 0.45, 1.3)
	_mound(Vector3(8.0, 0, 6.0), 1.6, 0.25, 1.4)
	_mound(Vector3(-8.0, 0, 11.0), 1.3, 0.3, 1.3)
	_chunks(Vector3(-4.5, 0, -2.5), 8, 2.2, 0.8)
	_chunks(Vector3(6.0, 0, 2.0), 6, 1.8, 0.7)
	_chunks(Vector3(-16.0, 0, -1.0), 7, 2.4, 0.9)
	_chunks(Vector3(2.0, 0, 9.5), 5, 2.0, 0.6)
	_chunks(Vector3(20.0, 0, 3.0), 5, 1.8, 0.7)
	_chunks(Vector3(-23.5, 0, 11.0), 6, 2.2, 0.9)
	Props.debris(geo, Vector3(-3.0, 0, 6.0), 0.6, 6, "concrete")
	Props.debris(geo, Vector3(9.0, 0, 8.0), 1.4, 5, "concrete")
	_leaves(Vector3(-13.0, 0, -2.0), 4.0, 60)
	_leaves(Vector3(10.0, 0, -1.0), 4.0, 50)
	_leaves(Vector3(-19.0, 0, 6.0), 3.5, 40)
	_leaves(Vector3(0, 0, 8.0), 5.0, 40)
	_leaves(Vector3(19.0, 0, 9.0), 3.5, 35)
	_leaves(Vector3(-5.0, 0, 3.0), 3.0, 35)
	Props.corpse(geo, Vector3(-2.2, 0.02, 11.0), 0.5, {"shirt": Color(0.3, 0.18, 0.12), "zombie": false})
	_mound(Vector3(-2.2, 0, 11.2), 0.9, 0.18, 1.8)
	Props.corpse(geo, Vector3(13.0, 0.02, 3.0), -2.0, {"shirt": Color(0.2, 0.25, 0.4), "zombie": false})
	# portico lamp (sets the warm key on the facade)
	_bulb(Vector3(0, FY + 4.1, -8.1), 3.2, 11.0, true, "weak", Color(1.0, 0.72, 0.42), 0.35)
	# side-door light
	_bulb(Vector3(-18.5, FY + 3.0, -8.7), 2.0, 6.5, false, "weak", Color(1.0, 0.72, 0.42), 0.25)

func _fire_barrel(pos: Vector3) -> void:
	Props.cyl(geo, 0.32, 0.95, pos + Vector3(0, 0.475, 0), Mats.get_mat("metal_rust", 0.6), true, 0.34)
	# burning contents
	var p := CPUParticles3D.new()
	p.amount = 36
	p.lifetime = 1.0
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.8
	p.gravity = Vector3(0, 0.8, 0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.18
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	p.mesh = sm
	p.material_override = Mats.emissive(Color(1.0, 0.45, 0.12), 4.0)
	p.position = pos + Vector3(0, 1.0, 0)
	add_child(p)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.5, 0.2)
	l.light_energy = 2.4
	l.omni_range = 10.0
	l.shadow_enabled = false
	l.light_volumetric_fog_energy = 1.2
	l.position = pos + Vector3(0, 1.4, 0)
	add_child(l)
	_fires.append([pos, l, randf() * 10.0])
	_mound(pos + Vector3(0.5, 0, 0.4), 0.6, 0.3)

func _shed_pt(shed_pos: Vector3, yaw: float, local: Vector3) -> Vector3:
	return shed_pos + Basis(Vector3.UP, yaw) * local

func _build_shed_interior(sp: Vector3, yaw: float) -> void:
	# white panelled door in the opening
	door("l2_shed_door", _shed_pt(sp, yaw, Vector3(0, 0, 1.8)), yaw, {"width": 1.0, "height": 2.05, "mat": "lab_wall", "prompt": "Open shed door"})
	# floor + workbench + shelves
	_deco(_shed_pt(sp, yaw, Vector3(0, 0.02, 0)), Vector3(3.0, 0.04, 3.4), "concrete", Vector3(0, yaw, 0))
	var bench := Props.table(geo, _shed_pt(sp, yaw, Vector3(-0.8, 0, -1.2)), yaw, Vector2(1.5, 0.7))
	Props.shelf(geo, _shed_pt(sp, yaw, Vector3(1.0, 0, -1.55)), yaw, 1.2, 1.9, false)
	Props.barrel(geo, _shed_pt(sp, yaw, Vector3(1.1, 0, 0.5)), 0.0)
	Props.crate(geo, _shed_pt(sp, yaw, Vector3(-1.15, 0, 0.4)), yaw + 0.3, 0.6)
	# pegboard + hooks: the janitor's keyring hangs here
	_deco(_shed_pt(sp, yaw, Vector3(-0.2, 1.5, -1.72)), Vector3(1.3, 0.9, 0.03), "wood_panel", Vector3(0, yaw, 0))
	for i in 5:
		Props.cyl(geo, 0.01, 0.07, _shed_pt(sp, yaw, Vector3(-0.7 + i * 0.25, 1.5 + (i % 2) * 0.2, -1.69)), Mats.get_mat("metal"), false, -1.0, Vector3(PI * 0.5, 0, 0))
	# shovel and snow-blower leaning
	Props.cyl(geo, 0.015, 1.5, _shed_pt(sp, yaw, Vector3(1.35, 0.78, -0.3)), Mats.get_mat("wood"), false, -1.0, Vector3(0.0, 0, 0.12))
	var wl := light(_shed_pt(sp, yaw, Vector3(0, 2.0, 0.2)), Color(1.0, 0.75, 0.45), 0.9, 4.2, false, false)
	_lamps.append([wl, 0.9, 3.0, "steady", null])
	_chunks(_shed_pt(sp, yaw, Vector3(0, 0, 2.6)), 3, 0.8, 0.4)

# ====================================================================== FACADE
func _build_facade() -> void:
	# brick skin with the two doorways
	wall(Vector2(-22.3, -9.81), Vector2(22.3, -9.81), TOP, "brick", 0.0, 0.12, [[3.8, 1.75, 2.5, FY], [22.3, 2.7, 3.1, FY]])
	box(Vector3(-22.19, TOP * 0.5, -22.0), Vector3(0.12, TOP, 24.4), "brick", false)
	box(Vector3(22.19, TOP * 0.5, -22.0), Vector3(0.12, TOP, 24.4), "brick", false)
	box(Vector3(0, TOP * 0.5, -34.19), Vector3(44.6, TOP, 0.12), "brick", false)
	# plinth, string course, cornice, roof snow
	_deco(Vector3(0, 0.5, -9.69), Vector3(44.8, 0.75, 0.2), "concrete")
	_deco(Vector3(0, FY + 4.35, -9.68), Vector3(44.6, 0.28, 0.2), "concrete")
	_deco(Vector3(0, TOP - 0.15, -9.55), Vector3(44.8, 0.5, 0.5), "concrete")
	_deco(Vector3(0, TOP + 0.12, -22.0), Vector3(44.8, 0.28, 25.0), "snow")
	_deco(Vector3(0, TOP + 0.35, -9.7), Vector3(44.0, 0.2, 0.35), "snow")
	# windows: dark, multi-pane, frosted. A few glow faintly (weak power).
	var frost_m := _m("win_frost", Color(0.82, 0.9, 1.0, 0.35), 0.3)
	var ground_x := [-21.0, -15.8, -12.2, -9.0, -6.2, 6.2]
	for x in ground_x:
		Props.window(geo, Vector3(x, FY + 1.9, -9.75), 0.0, 1.3, 2.2, false)
		Props.box(geo, Vector3(1.3, 1.1, 0.02), Vector3(x, FY + 1.35, -9.68), frost_m, false)
		_deco(Vector3(x, FY + 3.1, -9.72), Vector3(1.7, 0.16, 0.22), "concrete")
	for x in [9.5, 13.0, 16.5, 20.0]:
		Props.window(geo, Vector3(x, FY + 3.2, -9.75), 0.0, 1.6, 3.6, x == 13.0 or x == 20.0)
		Props.box(geo, Vector3(1.6, 1.8, 0.02), Vector3(x, FY + 2.2, -9.68), frost_m, false)
		_deco(Vector3(x, FY + 5.15, -9.72), Vector3(2.0, 0.18, 0.22), "concrete")
	for x in [-20.0, -16.5, -13.0, -9.5, -6.2, 6.2, 9.5, 13.0, 16.5, 20.0]:
		var yy := FY + 6.1 if x < 8.0 else FY + 7.5
		if x > 8.0:
			continue
		Props.window(geo, Vector3(x, yy, -9.75), 0.0, 1.5, 2.2, x == -13.0)
		Props.box(geo, Vector3(1.5, 1.1, 0.02), Vector3(x, yy - 0.55, -9.68), frost_m, false)
		_deco(Vector3(x, yy + 1.2, -9.72), Vector3(1.9, 0.16, 0.22), "concrete")
		_snow_box(Vector3(x, yy - 1.12, -9.58), Vector3(1.8, 0.07, 0.3))
	# central arched-style window above the pediment
	Props.window(geo, Vector3(0, FY + 7.0, -9.75), 0.0, 1.8, 2.4, true)
	_deco(Vector3(0, FY + 8.3, -9.72), Vector3(2.3, 0.2, 0.22), "concrete")
	# snow on ground-floor sills
	for x in ground_x:
		_snow_box(Vector3(x, FY + 0.73, -9.58), Vector3(1.6, 0.07, 0.3))
	# green drainpipes
	for x in [-7.55, 7.55, -21.6, 21.5]:
		Props.pipe(geo, Vector3(x, 0.15, -9.64), Vector3(x, TOP - 0.3, -9.64), 0.065, "metal_painted")
		for y in [1.5, 3.5, 5.5, 7.5]:
			_deco(Vector3(x, y, -9.68), Vector3(0.14, 0.08, 0.1), "metal")
		Props.pipe(geo, Vector3(x, 0.15, -9.64), Vector3(x + 0.6, 0.1, -9.0), 0.065, "metal_painted")
		_icicles(Vector3(x - 0.1, 2.0, -9.6), Vector3(x + 0.1, 2.0, -9.6), 3, 0.4)
	# dead vines creeping up the brick
	_vine(Vector3(-20.3, 0.1, -9.62), 7.5, 5)
	_vine(Vector3(-5.6, 0.1, -9.62), 6.0, 9)
	_vine(Vector3(8.4, 0.1, -9.62), 7.0, 13)
	_vine(Vector3(-11.0, 0.1, -9.62), 4.5, 21)
	_vine(Vector3(21.0, 0.1, -9.62), 6.5, 27)
	# portico: steps, platform, square columns, entablature, pediment, name plate
	stairs(Vector3(0, 0, -4.7), 5.2, 1.9, FY, "-z", "concrete")
	floor_rect(-4.6, -9.75, 4.6, -6.6, FY, "concrete")
	for x in [-4.3, -2.0, 2.0, 4.3]:
		box(Vector3(x, FY + 2.2, -7.2), Vector3(0.62, 4.4, 0.62), "concrete")
		_deco(Vector3(x, FY + 0.12, -7.2), Vector3(0.8, 0.24, 0.8), "concrete")
		_deco(Vector3(x, FY + 4.45, -7.2), Vector3(0.84, 0.2, 0.84), "concrete")
	box(Vector3(0, FY + 4.85, -8.2), Vector3(9.6, 0.62, 3.1), "concrete", false)
	_deco(Vector3(0, FY + 5.3, -8.3), Vector3(8.6, 0.3, 2.8), "concrete")
	_deco(Vector3(0, FY + 5.58, -8.4), Vector3(6.6, 0.26, 2.5), "concrete")
	_deco(Vector3(0, FY + 5.84, -8.5), Vector3(4.2, 0.26, 2.2), "concrete")
	_deco(Vector3(0, FY + 6.08, -8.6), Vector3(1.8, 0.22, 2.0), "concrete")
	_snow_box(Vector3(0, FY + 5.15, -8.2), Vector3(9.2, 0.08, 2.9))
	_sign("KETTLE FALLS CONSOLIDATED SCHOOL", Vector3(0, FY + 4.82, -6.62), 0.0, 40, Color(0.88, 0.86, 0.78), false)
	_sign("1926", Vector3(0, FY + 5.58, -7.2), 0.0, 44, Color(0.8, 0.78, 0.7), false)
	# side door: stoop, canopy
	floor_rect(-19.7, -9.8, -17.3, -8.2, FY, "concrete")
	stairs(Vector3(-18.5, 0, -6.6), 1.9, 1.6, FY, "-z", "concrete")
	_deco(Vector3(-18.5, FY + 2.75, -8.8), Vector3(2.2, 0.1, 1.5), "metal_painted")
	for sx in [-1, 1]:
		_deco(Vector3(-18.5 + sx * 1.0, FY + 2.0, -9.4), Vector3(0.05, 1.5, 0.05), "metal")
	_snow_box(Vector3(-18.5, FY + 2.84, -8.8), Vector3(2.0, 0.08, 1.4))
	_sign("CUSTODIAL", Vector3(-18.5, FY + 2.55, -9.2), 0.0, 22, Color(0.85, 0.85, 0.75))
	door("l2_side", Vector3(-18.5, FY, -9.95), 0.0, {"width": 1.2, "height": 2.35, "mat": "metal_painted", "lock_item": "school_key", "keep_key": true, "locked_msg": "Locked. The sign says CUSTODIAL — the janitor's keyring would open it.", "prompt": "Open custodial door"})
	_mound(Vector3(-18.5, FY + 0.05, -8.2), 0.9, 0.2, 1.5)
	_front_doors()
	# light spill: moonlit cold wash is the moon; warm key at the portico is above

func _front_doors() -> void:
	var r := Node3D.new()
	r.position = Vector3(0, FY, -9.95)
	add_child(r)
	var frame := _m("frame_white", Color(0.78, 0.78, 0.74), 0.7)
	var white := _m("door_white", Color(0.82, 0.83, 0.8), 0.6)
	var glass := _m("door_glass", Color(0.03, 0.04, 0.05), 0.05, 0.4)
	Props.box(r, Vector3(0.22, 3.1, 0.3), Vector3(-1.38, 1.55, 0), frame, false)
	Props.box(r, Vector3(0.22, 3.1, 0.3), Vector3(1.38, 1.55, 0), frame, false)
	Props.box(r, Vector3(2.98, 0.22, 0.3), Vector3(0, 3.1, 0), frame, false)
	Props.box(r, Vector3(2.5, 0.12, 0.22), Vector3(0, 2.92, 0), frame, false)
	Props.box(r, Vector3(2.4, 0.2, 0.05), Vector3(0, 2.2, 0), _m("transom_dark", Color(0.03, 0.04, 0.05), 0.1), false).position.y = 3.0
	var open := Game.has_flag("l2_front_open")
	var panel_m := _m("door_panel", Color(0.72, 0.73, 0.7), 0.6)
	var bar_m := _m("push_bar", Color(0.6, 0.6, 0.62), 0.3, 0.9)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var hinge := Node3D.new()
		hinge.position = Vector3(side * 1.2, 0, 0)
		r.add_child(hinge)
		var leaf := Props.box(hinge, Vector3(1.2, 2.9, 0.07), Vector3(-side * 0.6, 1.45, 0), white, true)
		for sd in [-1, 1]:
			Props.box(leaf, Vector3(0.84, 0.75, 0.025), Vector3(0, -0.95, sd * 0.045), panel_m, false)
			Props.box(leaf, Vector3(0.84, 0.5, 0.025), Vector3(0, -0.22, sd * 0.045), panel_m, false)
			Props.box(leaf, Vector3(0.84, 1.1, 0.02), Vector3(0, 0.78, sd * 0.04), glass, false)
			Props.box(leaf, Vector3(0.05, 1.1, 0.03), Vector3(0, 0.78, sd * 0.05), frame, false)
			Props.box(leaf, Vector3(0.9, 0.05, 0.05), Vector3(0, -0.4, sd * 0.1), bar_m, false)
		_front_leaves.append(hinge)
	if open:
		for i in 2:
			_front_leaves[i].rotation.y = (-1.0 if i == 0 else 1.0) * -1.6
			for sb in _front_leaves[i].find_children("*", "StaticBody3D", true, false):
				sb.collision_layer = 0
	else:
		# chain wrapped through the push bars + padlock, on both faces
		var cm := _m("chain", Color(0.12, 0.12, 0.13), 0.4, 0.9)
		for face in [-1.0, 1.0]:
			for i in 16:
				var t := float(i) / 15.0
				var p := Vector3(lerp(-0.8, 0.8, t), 1.05 + sin(t * PI * 3.0) * 0.07, face * 0.14)
				var link := Props.box(r, Vector3(0.07, 0.04, 0.025) if i % 2 == 0 else Vector3(0.025, 0.04, 0.07), p, cm, false)
				_front_chain.append(link)
			var pl := Props.box(r, Vector3(0.1, 0.14, 0.05), Vector3(0, 0.93, face * 0.15), _m("padlock", Color(0.7, 0.55, 0.15), 0.3, 0.9), false)
			_front_chain.append(pl)
		_front_it = Interactable.new()
		_front_it.set("prompt", "Front doors")
		_front_it.set("radius", 2.4)
		_front_it.position = Vector3(0, FY + 1.2, -9.95)
		_front_it.set("action", _front_interact)
		add_child(_front_it)

func _front_interact(p: Node) -> void:
	if Game.has_flag("l2_front_open"):
		return
	var inside: bool = p.global_position.z < -9.95
	if not inside:
		Sfx.play("door_locked")
		UI.toast("Chained shut from the inside, and the glass is frosted over. Another way in.")
		return
	if not Game.has_flag("boiler_on"):
		Sfx.play("door_locked")
		UI.toast("The mag-lock strike won't release on a brownout. It needs steady building power.")
		return
	if not Game.has_flag("l2_read_june"):
		Sfx.play("deny")
		await say([["ELIAS", "Not yet. June's homeroom was 2B. If she left anything, it's there."]])
		return
	_unchain()

func _unchain() -> void:
	if _scene_running:
		return
	_scene_running = true
	lock_player(true)
	Sfx.play("unlock")
	Game.set_flag("l2_front_open")
	for c in _front_chain:
		if is_instance_valid(c):
			var tw: Tween = c.create_tween()
			tw.tween_property(c, "position:y", c.position.y - 1.6, 0.5).set_trans(Tween.TRANS_QUAD)
			tw.tween_callback(c.queue_free)
	await get_tree().create_timer(0.6).timeout
	Sfx.play("metal_impact")
	await get_tree().create_timer(0.4).timeout
	Sfx.play("door_open")
	for i in _front_leaves.size():
		var hg: Node3D = _front_leaves[i]
		var tw := hg.create_tween()
		tw.tween_property(hg, "rotation:y", (-1.0 if i == 0 else 1.0) * -1.6, 1.0).set_trans(Tween.TRANS_SINE)
		for sb in hg.find_children("*", "StaticBody3D", true, false):
			sb.collision_layer = 0
	if is_instance_valid(_front_it):
		_front_it.set("enabled", false)
	Sfx.ambience("amb_wind")
	await get_tree().create_timer(1.2).timeout
	_make_finale_trigger()
	Game.set_objective("Get out of the school. Make for St. Brendan's church — the east gate.")
	lock_player(false)
	_scene_running = false

# ====================================================================== SHELL (floors, walls, ceilings)
func _build_shell() -> void:
	# ---- ground floor slabs (hole for the basement stairs in the stair room)
	floor_rect(-22, -22, -14, -10, FY, "wood_floor")
	floor_rect(-14, -22, -7, -10, FY, "carpet")
	floor_rect(-7, -22, 7, -10, FY, "marble")
	floor_rect(-22, -26, 7, -22, FY, "tile_floor")
	floor_rect(-22, -27, -18, -26, FY, "tile_floor")
	floor_rect(-18, -34, -11, -26, FY, "wood_floor")
	floor_rect(-11, -34, -5, -26, FY, "concrete")
	floor_rect(-5, -34, 1, -26, FY, "tile_floor")
	floor_rect(1, -34, 7, -26, FY, "carpet")
	# gym floor with the locker-room stair opening (x 8..10.4, z -17.7..-12.6)
	floor_rect(7, -34, 22, -17.7, FY, "wood_floor")
	floor_rect(7, -17.7, 8.0, -10, FY, "wood_floor")
	floor_rect(10.4, -17.7, 22, -10, FY, "wood_floor")
	floor_rect(8.0, -12.6, 10.4, -10, FY, "wood_floor")
	# ---- ceilings
	ceiling_rect(-22, -34, 7, -10, FY + HC, "plaster_dirty")
	ceiling_rect(7, -34, 22, -10, FY + HG, "plaster_dirty")
	# upper storeys are solid brick masses (decor): keeps the exterior honest without modelling upstairs
	box(Vector3(-7.5, FY + 6.5, -22.0), Vector3(29.25, 3.9, 24.25), "brick", false)
	box(Vector3(14.5, FY + 7.6, -22.0), Vector3(15.25, 1.7, 24.25), "brick", false)
	# ---- walls
	# front (facade) wall, hall + west wing: front door gap and side door gap
	_w(-22, -10, 7, -10, HC, "plaster", [[3.5, 1.6, 2.45], [22.0, 2.7, 3.15]])
	_w(7, -10, 22, -10, HG, "plaster", [])
	# north exterior
	_w(-22, -34, 7, -34, HC, "plaster_dirty", [])
	_w(7, -34, 22, -34, HG, "plaster_dirty", [])
	# west / east exterior
	_w(-22, -34, -22, -10, HC, "plaster", [])
	_w(22, -34, 22, -10, HG, "plaster", [])
	# west wing front: lobby | office | hall dividers
	_w(-14, -22, -14, -10, HC, "plaster", [[4.0, 1.6, 2.4]])
	_w(-7, -22, -7, -10, HC, "plaster", [[7.5, 1.6, 2.4]])
	# gym / hall+corridor wall (door to the corridor at z=-24)
	_w(7, -34, 7, -10, HG, "plaster", [[10.0, 2.4, 2.55]])
	# corridor walls: hall wall with a wide arch; west wing back wall with doorways
	_w(-22, -22, 7, -22, HC, "plaster_dirty", [[4.0, 1.6, 2.4], [11.5, 1.6, 2.4], [22.0, 3.4, 3.4]])
	_w(-22, -26, 7, -26, HC, "plaster_dirty", [[2.0, 2.4, 2.5], [7.5, 1.6, 2.4], [14.0, 1.6, 2.4], [20.0, 1.6, 2.4], [26.0, 1.6, 2.4]])
	# rear room dividers
	for x in [-18.0, -11.0, -5.0, 1.0]:
		_w(x, -34, x, -26, HC, "plaster", [])
	# ---- lintel strips and baseboards add some life
	for z in [-10.0]:
		_deco(Vector3(0, FY + 0.15, z + 0.17), Vector3(29.0, 0.3, 0.06), "wood_panel")
	# doors
	_dx("l2_d_lobby_corr", -18, -22)
	_dx("l2_d_off_corr", -10.5, -22)
	_dz("l2_d_lobby_off", -14, -18)
	_dz("l2_d_off_hall", -7, -14.5)
	_dx("l2_d_2b", -14.5, -26, {"mat": "wood_panel", "lock_flag": "boiler_on", "locked_msg": "The keypad is dead — the electric strike has no power. Brownout. Needs the heat plant back on.", "label": "2B", "prompt": "Classroom 2B"})
	_dx("l2_d_shop", -8, -26, {"mat": "metal_painted", "lock_item": "school_key", "keep_key": true, "locked_msg": "SHOP — locked. The custodian's keyring opens this.", "label": "SHOP"})
	_dx("l2_d_nurse", -2, -26, {"label": "NURSE"})
	_dx("l2_d_coach", 4, -26, {"label": "COACH"})
	_dz("l2_d_gym", 7, -24, {"double": true, "width": 2.2, "height": 2.45, "mat": "wood_panel", "lock_item": "gym_key", "locked_msg": "Gym doors. Padlocked. Hung on a chain through the handles.", "label": "GYM"})
	# stair room sign + rails
	_sign("BASEMENT\nBOILER · CUSTODIAL", Vector3(-20.0, FY + 2.7, -26.2), PI, 26, Color(0.85, 0.85, 0.7))
	# fill the slits above the shaft where ground walls float over the opening
	box(Vector3(-22.0, 0.3, -30.5), Vector3(0.25, 0.3, 7.0), "plaster", false)
	box(Vector3(-18.0, 0.3, -32.25), Vector3(0.25, 0.3, 3.5), "plaster", false)
	box(Vector3(-20.0, 0.3, -34.0), Vector3(4.25, 0.3, 0.25), "plaster", false)
	# outdoor-facing wall heights fine; frost around room borders:
	_frost_patch(Vector3(0, FY, -11.0), 3.0, 1.5)

# ====================================================================== MAIN HALL
func _build_hall() -> void:
	# ceiling lamps (weak: brown out until the boiler is on)
	_fluor(Vector3(-3.0, FY + HC, -13.0), 0.0, 1.6, 9.0, false)
	_fluor(Vector3(3.0, FY + HC, -13.0), 0.0, 1.6, 9.0, false)
	_fluor(Vector3(0.0, FY + HC, -19.0), PI * 0.5, 1.5, 9.0, false)
	_red_lamp(Vector3(0, FY + 3.5, -21.8), 1.0, 5.0)
	_sign("EXIT", Vector3(0, FY + 3.7, -9.8), PI, 30, Color(0.3, 1.0, 0.45), true)
	# trophy cases along the gym wall (east)
	for z in [-13.5, -19.0]:
		_trophy_case(Vector3(6.55, FY, z), -PI * 0.5)
	# mural of the 1950s mine, north wall
	_mural(Vector3(-4.3, FY + 1.9, -21.8))
	# notice wall (east of the arch): shelter signs
	_deco(Vector3(4.6, FY + 1.7, -21.85), Vector3(3.2, 1.9, 0.04), _m("cork", Color(0.45, 0.32, 0.2), 0.95))
	_sign("WARMING SHELTER\nGYM -> DOWN THE HALL", Vector3(4.6, FY + 2.3, -21.78), 0.0, 26, Color(0.9, 0.9, 0.8), true)
	_sign("DO NOT SLEEP\nOUTSIDE THE GYM", Vector3(4.6, FY + 1.6, -21.78), 0.0, 34, Color(1.0, 0.4, 0.3), true)
	_sign("RULE 2: NOBODY SLEEPS ALONE", Vector3(4.6, FY + 1.1, -21.78), 0.0, 20, Color(0.95, 0.95, 0.85), true)
	# paper chains over the hall
	_paper_chain(Vector3(-6.8, FY + 3.8, -12.0), Vector3(6.8, FY + 3.8, -12.0), 0.5, 30)
	_paper_chain(Vector3(-6.8, FY + 3.8, -16.0), Vector3(6.8, FY + 3.7, -17.0), 0.6, 30)
	_paper_chain(Vector3(-6.8, FY + 3.9, -20.0), Vector3(6.8, FY + 3.9, -20.5), 0.4, 30)
	# coats piled on benches, boots, barricade of desks by the front doors
	_coat_pile(Vector3(-5.6, FY, -17.0))
	_coat_pile(Vector3(-5.6, FY, -12.2), 0.9)
	Props.bench(geo, Vector3(-6.4, FY, -17.0), PI * 0.5)
	_school_desk(Vector3(-3.2, FY, -10.9), 0.2, true)
	_school_desk(Vector3(3.3, FY, -11.0), -0.3, true)
	_school_desk(Vector3(2.7, FY, -11.7), 1.0, true)
	_chair_s(Vector3(-2.3, FY, -11.4), 0.6, true)
	_chair_s(Vector3(1.9, FY, -10.6), -1.0, true)
	Props.papers(geo, Vector3(0, FY, -15.0), 12)
	Props.papers(geo, Vector3(-3.5, FY, -19.0), 7)
	Props.trash_bags(geo, Vector3(5.8, FY, -11.2), 0.4, 3)
	# snow that blew in under the doors, frost on the marble
	_snow_box(Vector3(0, FY + 0.04, -10.4), Vector3(3.2, 0.1, 0.8))
	_mound(Vector3(0, FY, -10.5), 0.9, 0.12, 2.4)
	_frost_patch(Vector3(0, FY, -14.0), 5.0, 3.0)
	_frost_patch(Vector3(-3.0, FY, -19.0), 3.0, 2.0)
	_icicles(Vector3(-1.5, FY + 3.2, -9.9), Vector3(1.5, FY + 3.2, -9.9), 7, 0.5)
	# stuffed bear and a pile of kids' coats at the arch
	Props.sphere(geo, 0.22, Vector3(1.6, FY + 0.3, -17.6), _m("bear", Color(0.4, 0.28, 0.18), 0.95))
	# vending machine (glow dead), radiator under a window-less wall
	Props.vending(geo, Vector3(6.35, FY, -16.2), -PI * 0.5, false)

func _trophy_case(pos: Vector3, yaw: float) -> void:
	var r := Node3D.new()
	r.position = pos
	r.rotation.y = yaw
	add_child(r)
	var wood := Mats.get_mat("wood_panel")
	Props.box(r, Vector3(2.4, 2.1, 0.5), Vector3(0, 1.05, 0), wood, true)
	Props.box(r, Vector3(2.2, 1.7, 0.02), Vector3(0, 1.1, 0.26), Mats.color(Color(0.55, 0.7, 0.75, 0.22), 0.05), false)
	for k in 4:
		Props.box(r, Vector3(2.2, 0.03, 0.4), Vector3(0, 0.5 + k * 0.4, 0.04), wood, false)
		for i in 5:
			var gx := -0.9 + i * 0.45
			Props.cyl(r, 0.05, 0.18, Vector3(gx, 0.62 + k * 0.4, 0.06), _m("trophy", Color(0.75, 0.6, 0.2), 0.3, 0.9), false, 0.07)
	Props.box(r, Vector3(2.0, 0.5, 0.01), Vector3(0, 0.25, 0.26), _m("case_frost", Color(0.85, 0.9, 1.0, 0.45), 0.3), false)

func _mural(pos: Vector3) -> void:
	var r := Node3D.new()
	r.position = pos
	add_child(r)
	Props.box(r, Vector3(4.6, 2.2, 0.05), Vector3(0, 0, 0), _m("mural_bg", Color(0.16, 0.22, 0.24), 0.9), false)
	Props.box(r, Vector3(4.6, 0.7, 0.06), Vector3(0, -0.75, 0.01), _m("mural_ground", Color(0.28, 0.2, 0.14), 0.95), false)
	# headframe
	var iron := _m("mural_iron", Color(0.08, 0.07, 0.07), 0.9)
	Props.box(r, Vector3(0.1, 1.5, 0.07), Vector3(-1.2, 0.2, 0.04), iron, false, Vector3(0, 0, 0.18))
	Props.box(r, Vector3(0.1, 1.5, 0.07), Vector3(-0.6, 0.2, 0.04), iron, false, Vector3(0, 0, -0.18))
	Props.box(r, Vector3(0.9, 0.08, 0.07), Vector3(-0.9, 0.95, 0.04), iron, false)
	Props.box(r, Vector3(0.9, 0.06, 0.07), Vector3(-0.9, 0.3, 0.04), iron, false)
	Props.cyl(r, 0.2, 0.05, Vector3(-0.9, 1.0, 0.05), iron, false, -1.0, Vector3(PI * 0.5, 0, 0))
	# sun / lamplight, ore cars, miners with lamps
	Props.sphere(r, 0.28, Vector3(1.4, 0.6, 0.04), _m("mural_sun", Color(0.9, 0.7, 0.3), 0.7), Vector3(1, 1, 0.1))
	for i in 3:
		Props.box(r, Vector3(0.45, 0.28, 0.07), Vector3(0.1 + i * 0.55, -0.5, 0.05), _m("mural_car", Color(0.45, 0.2, 0.12), 0.8), false)
	for i in 5:
		var mx := 0.2 + i * 0.5
		Props.box(r, Vector3(0.14, 0.4, 0.06), Vector3(mx, -0.05, 0.05), _m("mural_man", Color(0.12, 0.1, 0.09), 0.9), false)
		Props.sphere(r, 0.07, Vector3(mx, 0.22, 0.05), _m("mural_man", Color(0.12, 0.1, 0.09), 0.9))
		Props.sphere(r, 0.03, Vector3(mx, 0.26, 0.09), Mats.emissive(Color(1.0, 0.85, 0.4), 2.0))
	_sign("KETTLE FALLS — IRON FEEDS A NATION · 1954", Vector3(0, -1.2, 0.05), 0.0, 20, Color(0.85, 0.8, 0.6), false)
	_icicles(Vector3(-2.2, 1.1, 0.1), Vector3(2.2, 1.1, 0.1), 7, 0.35)

# ====================================================================== WEST WING (lobby + shelter office)
func _build_west_wing() -> void:
	# ---- west lobby
	_fluor(Vector3(-18.0, FY + HC, -16.0), PI * 0.5, 1.3, 8.0, false)
	_fluor(Vector3(-18.0, FY + HC, -20.0), PI * 0.5, 1.3, 8.0, false, "late")
	_snow_box(Vector3(-18.5, FY + 0.03, -10.6), Vector3(1.6, 0.08, 0.9))
	_mound(Vector3(-18.5, FY, -10.6), 0.8, 0.14, 1.8)
	_coat_pile(Vector3(-20.8, FY, -13.0))
	_coat_pile(Vector3(-20.8, FY, -17.5), 1.1)
	Props.bench(geo, Vector3(-21.0, FY, -15.2), PI * 0.5)
	Props.bench(geo, Vector3(-16.0, FY, -21.2), PI)
	# cubbies (lockers) along the divider
	Props.locker(geo, Vector3(-14.4, FY, -12.6), PI * 0.5, 4)
	Props.locker(geo, Vector3(-14.4, FY, -20.0), PI * 0.5, 3)
	# bulletin board of children's art + notices
	_deco(Vector3(-21.85, FY + 1.7, -19.0), Vector3(0.04, 1.4, 2.6), _m("cork", Color(0.45, 0.32, 0.2), 0.95))
	for i in 6:
		var cc := Color.from_hsv(randf(), 0.5, 0.8)
		_deco(Vector3(-21.8, FY + 1.4 + randf() * 0.7, -19.9 + i * 0.4), Vector3(0.01, 0.28, 0.22), _m("art%d" % i, cc, 0.9), Vector3(randf_range(-0.2, 0.2), 0, 0))
	_sign("WELCOME TO KETTLE FALLS\nWEST DOOR: SHELTER INTAKE", Vector3(-21.7, FY + 2.6, -16.5), PI * 0.5, 22, Color(0.9, 0.9, 0.8))
	_paper_chain(Vector3(-21.8, FY + 3.7, -12.0), Vector3(-14.2, FY + 3.7, -12.0), 0.4, 20)
	_paper_chain(Vector3(-21.8, FY + 3.7, -21.0), Vector3(-14.2, FY + 3.7, -21.0), 0.4, 20)
	Props.trash_bags(geo, Vector3(-20.6, FY, -11.4), 0.0, 3)
	Props.papers(geo, Vector3(-17.5, FY, -17.0), 9)
	_frost_patch(Vector3(-18.0, FY, -14.0), 5.0, 4.0)
	_icicles(Vector3(-19.2, FY + 2.55, -10.1), Vector3(-17.8, FY + 2.55, -10.1), 5, 0.35)
	# ---- shelter office (Ruth's)
	_bulb(Vector3(-10.5, FY + HC, -16.0), 1.6, 8.0, false, "weak", Color(1.0, 0.74, 0.46), 0.7)
	Props.desk(geo, Vector3(-10.5, FY, -13.6), PI)
	Props.chair(geo, Vector3(-10.5, FY, -12.6), 0.0)
	Props.cabinet(geo, Vector3(-13.6, FY, -20.3), PI * 0.5)
	Props.cabinet(geo, Vector3(-13.6, FY, -19.5), PI * 0.5)
	Props.shelf(geo, Vector3(-10.0, FY, -21.6), 0.0, 2.0, 2.0, true)
	Props.bed(geo, Vector3(-12.6, FY, -17.6), PI * 0.5)
	_coat_pile(Vector3(-8.0, FY, -20.6), 0.8)
	_deco(Vector3(-13.85, FY + 1.7, -15.5), Vector3(0.03, 1.1, 1.6), _m("whiteboard", Color(0.8, 0.82, 0.8), 0.4))
	_label("SIGN-IN\n63 / 41 / 38 ...", Vector3(-13.82, FY + 1.9, -15.5), PI * 0.5, 22, Color(0.15, 0.15, 0.4), 0.004)
	_label("DO NOT SLEEP OUTSIDE\nTHE GYM", Vector3(-13.82, FY + 1.5, -15.5), PI * 0.5, 26, Color(0.7, 0.1, 0.1), 0.004)
	Props.papers(geo, Vector3(-10.0, FY, -17.0), 8)
	_frost_patch(Vector3(-10.5, FY, -17.0), 5.0, 4.0)
	# warm desk lamp
	var dl := _L(Vector3(-10.9, FY + 1.3, -13.8), Color(1.0, 0.78, 0.5), 0.9, 4.0, false, "steady")
	Props.cyl(geo, 0.05, 0.02, Vector3(-10.9, FY + 0.8, -13.8), _m("lamp_base", Color(0.1, 0.12, 0.1), 0.5, 0.5), false)
	Props.box(geo, Vector3(0.15, 0.1, 0.12), Vector3(-10.9, FY + 1.2, -13.8), Mats.emissive(Color(1.0, 0.8, 0.5), 2.0), false)

# ====================================================================== CORRIDOR
func _build_corridor() -> void:
	for x in [-19.0, -13.0, -7.0, -1.0]:
		_fluor(Vector3(x, FY + HC, -24.0), PI * 0.5, 1.4, 8.0, false, "weak" if x < -8.0 else "late")
	_red_lamp(Vector3(5.8, FY + 3.4, -24.0), 1.2, 6.0)
	# lockers: south wall (faces -z) and north wall (faces +z)
	Props.locker(geo, Vector3(-20.2, FY, -22.4), PI, 5)
	Props.locker(geo, Vector3(-14.2, FY, -22.4), PI, 9)
	Props.locker(geo, Vector3(-5.3, FY, -22.4), PI, 8)
	Props.locker(geo, Vector3(-16.6, FY, -25.6), 0.0, 4)
	Props.locker(geo, Vector3(-11.25, FY, -25.6), 0.0, 10)
	Props.locker(geo, Vector3(-4.8, FY, -25.6), 0.0, 4)
	Props.locker(geo, Vector3(1.0, FY, -25.6), 0.0, 8)
	# vending machine + signs at the gym end
	Props.vending(geo, Vector3(6.35, FY, -22.8), -PI * 0.5, false)
	_sign("WARMING SHELTER ->", Vector3(0.0, FY + 3.3, -22.15), 0.0, 36, Color(0.95, 0.9, 0.7), true)
	_sign("DO NOT SLEEP OUTSIDE THE GYM", Vector3(5.2, FY + 2.6, -22.15), 0.0, 24, Color(1.0, 0.4, 0.3), true)
	_paper_chain(Vector3(-21.7, FY + 3.8, -24.0), Vector3(6.7, FY + 3.8, -24.0), 0.55, 80)
	_paper_chain(Vector3(-21.7, FY + 3.6, -23.2), Vector3(6.7, FY + 3.6, -24.8), 0.35, 80)
	_coat_pile(Vector3(-2.4, FY, -22.9), 0.8)
	# debris: dropped bags, boots, wheelchair, overturned fire extinguisher
	for p in [Vector3(-12.0, FY, -23.4), Vector3(-6.0, FY, -24.7), Vector3(3.0, FY, -23.0)]:
		Props.papers(geo, p, 8)
	Props.trash_bags(geo, Vector3(-17.5, FY, -22.9), 0.0, 3)
	Props.chair(geo, Vector3(-8.7, FY, -24.5), 1.4, true)
	# frost streaks + icicles at the dead-end
	_frost_patch(Vector3(-15.0, FY, -24.0), 8.0, 3.0)
	_frost_patch(Vector3(-2.0, FY, -24.0), 8.0, 3.0)
	_icicles(Vector3(-21.0, FY + 4.0, -26.0), Vector3(-19.0, FY + 4.0, -26.0), 5, 0.4)
	# the arch to the hall: hand-lettered banner
	_sign("HAPPY HOLIDAYS KETTLE FALLS", Vector3(-12.5, FY + 3.2, -22.15), 0.0, 30, Color(0.9, 0.2, 0.2), false)

# ====================================================================== REAR ROOMS
func _build_rear_rooms() -> void:
	# ---- stair room (top landing + shaft)
	_bulb(Vector3(-20.0, FY + HC, -26.8), 1.6, 8.0, false, "weak", Color(0.8, 0.9, 1.0), 0.6)
	stairs(Vector3(-20.0, YB, -33.0), 3.8, 6.0, FY - YB, "+z", "concrete")
	_deco(Vector3(-20.0, FY + 0.5, -27.15), Vector3(3.8, 0.04, 0.04), "metal")
	_deco(Vector3(-20.0, FY + 1.0, -27.15), Vector3(3.8, 0.04, 0.04), "metal")
	_frost_patch(Vector3(-20.0, FY, -26.5), 3.0, 1.0)
	# ---- classroom 2B
	_fluor(Vector3(-14.5, FY + HC, -29.0), PI * 0.5, 1.5, 8.5, false, "late")
	_fluor(Vector3(-14.5, FY + HC, -32.0), PI * 0.5, 1.2, 8.0, false, "late")
	_deco(Vector3(-14.5, FY + 1.75, -33.82), Vector3(5.3, 1.3, 0.05), _m("blackboard", Color(0.05, 0.1, 0.07), 0.9))
	_deco(Vector3(-14.5, FY + 1.05, -33.75), Vector3(5.3, 0.06, 0.15), "wood")
	_deco(Vector3(-14.5, FY + 1.7, -33.84), Vector3(5.5, 1.5, 0.03), "wood")
	_label("DAD —\nGran walked out at 3am. Said Grandpa\nwas calling her from the mine.\nI'm going after her. Church first.\n— J.\nP.S. you're late.", Vector3(-14.5, FY + 1.8, -33.77), 0.0, 36, Color(0.92, 0.93, 0.88), 0.0042)
	_label("2B — MS. PELTO", Vector3(-17.2, FY + 2.55, -33.77), 0.0, 22, Color(0.9, 0.9, 0.8), 0.004)
	interact(Vector3(-14.5, FY + 1.2, -33.0), "Read the blackboard", func(_p): _read_blackboard(), 2.4)
	for row in 3:
		for col in 4:
			var p := Vector3(-17.0 + col * 1.5, FY, -29.6 + row * 1.3)
			_school_desk(p, PI, (row * 4 + col) in [2, 7, 10])
	Props.desk(geo, Vector3(-12.2, FY, -27.2), PI * 0.5)
	_paper_chain(Vector3(-17.8, FY + 3.7, -27.0), Vector3(-11.2, FY + 3.7, -27.0), 0.4, 18)
	_paper_chain(Vector3(-17.8, FY + 3.7, -30.5), Vector3(-11.2, FY + 3.7, -30.5), 0.4, 18)
	Props.papers(geo, Vector3(-14.0, FY, -31.0), 9)
	_frost_patch(Vector3(-14.5, FY, -30.0), 6.0, 7.0)
	Props.shelf(geo, Vector3(-11.5, FY, -33.6), 0.0, 1.4, 1.6, true)
	# ---- shop class
	_fluor(Vector3(-8.0, FY + HC, -30.0), PI * 0.5, 1.4, 8.0, false, "late")
	for x in [-9.6, -6.6]:
		Props.table(geo, Vector3(x, FY, -29.5), 0.0, Vector2(1.5, 0.9))
	Props.table(geo, Vector3(-10.4, FY, -32.8), PI * 0.5, Vector2(1.6, 0.7))
	Props.cabinet(geo, Vector3(-5.4, FY, -28.0), -PI * 0.5)
	Props.cabinet(geo, Vector3(-5.4, FY, -28.7), -PI * 0.5)
	_deco(Vector3(-8.0, FY + 1.7, -33.85), Vector3(3.6, 1.3, 0.03), "wood_panel")  # pegboard
	for i in 9:
		Props.box(geo, Vector3(0.05, 0.3 + (i % 3) * 0.1, 0.03), Vector3(-9.6 + i * 0.38, FY + 1.6, -33.8), _m("tool_h", Color(0.5, 0.5, 0.52), 0.4, 0.8), false)
	# lathe
	Props.box(geo, Vector3(1.4, 0.2, 0.5), Vector3(-6.2, FY + 0.95, -33.3), _m("lathe", Color(0.2, 0.3, 0.25), 0.5, 0.6), true)
	Props.cyl(geo, 0.2, 0.3, Vector3(-6.2, FY + 0.5, -33.3), _m("lathe", Color(0.2, 0.3, 0.25), 0.5, 0.6), true)
	_sign("SHOP — NO ENTRY WITHOUT SUPERVISION", Vector3(-8.0, FY + 3.0, -26.2), PI, 22, Color(1.0, 0.8, 0.2))
	_frost_patch(Vector3(-8.0, FY, -30.0), 4.0, 6.0)
	# ---- nurse
	_bulb(Vector3(-2.0, FY + HC, -30.0), 1.4, 7.5, false, "weak", Color(0.85, 0.95, 1.0), 0.7)
	Props.bed(geo, Vector3(-3.6, FY, -31.8), 0.0, true)
	Props.bed(geo, Vector3(-0.2, FY, -31.8), 0.0, true)
	Props.cabinet(geo, Vector3(-4.7, FY, -27.0), PI * 0.5)
	Props.cabinet(geo, Vector3(-4.7, FY, -28.0), PI * 0.5)
	Props.desk(geo, Vector3(-1.4, FY, -27.3), 0.0)
	_deco(Vector3(-2.0, FY + 1.7, -33.85), Vector3(1.0, 1.4, 0.02), _m("eyechart", Color(0.9, 0.9, 0.88), 0.7))
	_label("E\nF P\nT O Z", Vector3(-2.0, FY + 1.9, -33.82), 0.0, 24, Color(0.05, 0.05, 0.05), 0.004)
	_sign("HEALTH OFFICE", Vector3(-2.0, FY + 3.0, -26.2), PI, 22, Color(0.5, 0.9, 0.7))
	_frost_patch(Vector3(-2.0, FY, -30.0), 4.5, 6.0)
	# ---- coach's office
	_bulb(Vector3(4.0, FY + HC, -30.0), 1.4, 7.5, false, "weak", Color(1.0, 0.76, 0.48), 0.7)
	Props.desk(geo, Vector3(4.0, FY, -31.8), 0.0)
	Props.chair(geo, Vector3(4.0, FY, -30.6), PI, true)
	Props.shelf(geo, Vector3(1.8, FY, -29.0), PI * 0.5, 2.0, 2.0, false)
	Props.locker(geo, Vector3(6.55, FY, -28.5), -PI * 0.5, 3)
	Props.bed(geo, Vector3(5.2, FY, -29.0), 0.0)  # coach's camp cot
	for i in 6:
		Props.cyl(geo, 0.07, 0.35, Vector3(1.9, FY + 1.15 + (i % 2) * 0.01 + (i / 2) * 0.0, -28.2 - i * 0.28), _m("trophy2", Color(0.75, 0.6, 0.2), 0.3, 0.9), false, 0.09)
	_sign("COACH  H. BERGSTROM", Vector3(4.0, FY + 3.0, -26.2), PI, 22, Color(0.9, 0.9, 0.8))
	Props.papers(geo, Vector3(3.0, FY, -29.5), 7)
	_frost_patch(Vector3(4.0, FY, -30.0), 4.5, 6.0)

# ====================================================================== GYM (the shelter)
func _build_gym() -> void:
	# stage (north), steps, curtains
	box(Vector3(14.5, FY + 0.5, -31.75), Vector3(14.75, 1.0, 4.5), "wood_panel")
	stairs(Vector3(9.4, FY, -27.9), 1.8, 1.6, 1.0, "-z", "wood_panel")
	stairs(Vector3(20.3, FY, -27.9), 1.6, 1.6, 1.0, "-z", "wood_panel")
	for x in [8.0, 21.0]:
		_deco(Vector3(x, FY + 3.2, -33.5), Vector3(1.6, 4.0, 0.3), _m("curtain", Color(0.38, 0.06, 0.07), 0.95))
	_deco(Vector3(14.5, FY + 5.0, -33.6), Vector3(14.5, 1.3, 0.1), _m("curtain", Color(0.3, 0.05, 0.06), 0.95))
	_sign("KETTLE FALLS  ·  HOME OF THE MINERS", Vector3(14.5, FY + 4.4, -33.8), 0.0, 44, Color(0.9, 0.78, 0.3), false)
	# court lines (spare: wood floor carries the paint)
	for z in [-14.8, -23.0]:
		_deco(Vector3(14.5, FY + 0.012, z), Vector3(14.0, 0.01, 0.08), _m("court_line", Color(0.8, 0.8, 0.75), 0.7))
	_deco(Vector3(12.0, FY + 0.012, -18.9), Vector3(0.08, 0.01, 8.4), _m("court_line", Color(0.8, 0.8, 0.75), 0.7))
	# hoops
	_hoop(Vector3(15.0, FY + 3.3, -10.3), PI)
	# bleachers (folded) along the east wall
	box(Vector3(21.575, FY + 0.225, -17.0), Vector3(0.6, 0.45, 7.6), "wood_panel")
	box(Vector3(21.275, FY + 0.675, -17.0), Vector3(0.6, 0.45, 7.6), "wood_panel")
	box(Vector3(20.975, FY + 1.125, -17.0), Vector3(0.6, 0.45, 7.6), "wood_panel")
	_blocker(Vector3(20.95, FY + 0.8, -17.0), Vector3(1.8, 1.6, 7.6))
	# cots: two blocks, aisle between
	var blanket_cols := [Color(0.38, 0.12, 0.1), Color(0.14, 0.24, 0.3), Color(0.35, 0.3, 0.12), Color(0.2, 0.28, 0.18), Color(0.3, 0.3, 0.32)]
	var rows := [-14.2, -16.8, -19.4, -22.0, -24.6, -27.2]
	var k := 0
	for z in rows:
		for x in [12.2, 13.2, 17.4, 18.4]:
			var st := 0
			var sleeper: bool = (x == 12.2 and z == -19.4) or (x == 13.2 and z == -24.6) or (x == 17.4 and z == -16.8) or (x == 18.4 and z == -22.0) or (x == 17.4 and z == -27.2)
			var cov: bool = (k % 5 == 1) or (x == 13.2 and z == -14.2)
			if sleeper:
				st = 3
			elif cov:
				st = 2
			else:
				st = k % 2
			_cot(Vector3(x, FY, z), 0.0, blanket_cols[k % blanket_cols.size()], st)
			k += 1
	# belongings
	for p in [Vector3(11.2, FY, -15.0), Vector3(14.4, FY, -20.5), Vector3(16.8, FY, -25.4), Vector3(11.3, FY, -26.0), Vector3(19.2, FY, -13.6)]:
		Props.box(geo, Vector3(0.38, 0.5, 0.25), p + Vector3(0, 0.25, 0), _m("pack%d" % int(p.x), Color.from_hsv(randf(), 0.5, 0.35), 0.9), true, Vector3(0, randf() * 3, 0))
	for p in [Vector3(12.9, FY, -17.8), Vector3(18.0, FY, -19.8), Vector3(15.0, FY, -13.0), Vector3(14.6, FY, -27.0)]:
		Props.papers(geo, p, 5)
	Props.trash_bags(geo, Vector3(21.2, FY, -28.2), 0.0, 3)
	_coat_pile(Vector3(8.2, FY, -22.8), 0.9)
	_coat_pile(Vector3(15.0, FY, -15.3), 0.8)
	# sign-in table by the door + heaters, supply tables on the south wall
	Props.table(geo, Vector3(8.6, FY, -25.7), PI * 0.5, Vector2(1.6, 0.7))
	_label("SIGN IN", Vector3(8.1, FY + 0.95, -25.7), PI * 0.5, 18, Color(0.1, 0.1, 0.4), 0.004)
	Props.table(geo, Vector3(16.5, FY, -10.9), 0.0, Vector2(2.4, 0.8))
	Props.table(geo, Vector3(19.4, FY, -10.9), 0.0, Vector2(1.8, 0.8))
	for i in 6:
		Props.cyl(geo, 0.05, 0.12, Vector3(15.8 + i * 0.28, FY + 0.83, -10.9), _m("tin", Color(0.55, 0.55, 0.5), 0.4, 0.8), false)
	Props.box(geo, Vector3(0.5, 0.3, 0.4), Vector3(17.5, FY + 0.95, -11.0), _m("stove", Color(0.2, 0.25, 0.2), 0.6, 0.4), false)
	# signs
	_sign("FAMILIES: WEST SIDE\nBLANKETS: STAGE", Vector3(7.3, FY + 2.6, -20.0), PI * 0.5 + PI, 22, Color(0.9, 0.9, 0.8))
	_sign("DO NOT SLEEP OUTSIDE THE GYM", Vector3(14.5, FY + 3.7, -10.2), PI, 36, Color(1.0, 0.4, 0.3))
	_sign("LOCKER ROOMS  v", Vector3(9.2, FY + 1.7, -10.2), PI, 24, Color(0.9, 0.9, 0.8))
	# rails round the locker-room stair opening
	for spec in [[Vector3(8.0, FY + 0.5, -15.15), Vector3(0.06, 1.0, 5.1)], [Vector3(10.4, FY + 0.5, -15.15), Vector3(0.06, 1.0, 5.1)], [Vector3(9.2, FY + 0.5, -17.7), Vector3(2.4, 1.0, 0.06)]]:
		var rm := Props.box(geo, spec[1], spec[0], Mats.get_mat("metal"), true)
	stairs(Vector3(9.2, YB, -17.7), 2.2, 5.1, FY - YB, "+z", "concrete")
	# christmas: a dead tree with fairy lights by the stage steps
	_xmas_tree(Vector3(20.6, FY, -25.6))
	# paper chains and bunting across the court
	for z in [-14.0, -19.0, -24.0, -29.0]:
		_paper_chain(Vector3(7.2, FY + 5.6, z), Vector3(21.8, FY + 5.6, z - 0.4), 0.9, 40)
	# light: weak high-bays (more come on with the boiler), cold moon fill, warm stage pars, lanterns
	for p in [Vector3(11.5, FY + HG, -16.0), Vector3(17.5, FY + HG, -16.0), Vector3(11.5, FY + HG, -25.0), Vector3(17.5, FY + HG, -25.0)]:
		var late: bool = p.x > 14.0
		Props.cyl(geo, 0.3, 0.12, p + Vector3(0, -0.2, 0), _m("highbay", Color(0.2, 0.22, 0.22), 0.5, 0.6), false)
		var em := Mats.emissive(Color(0.85, 0.92, 1.0), 3.0)
		Props.cyl(geo, 0.22, 0.06, p + Vector3(0, -0.28, 0), em, false)
		_L(p + Vector3(0, -1.2, 0), Color(0.85, 0.92, 1.0), 2.4, 12.0, false, "late" if late else "weak", em)
	var cold := light(Vector3(14.5, FY + 5.6, -20.0), Color(0.55, 0.7, 1.0), 0.7, 16.0, false, false)
	_lamps.append([cold, 0.7, 1.0, "steady", null])
	_lantern(Vector3(15.0, FY + 0.82, -10.9), 0.9, 5.0)
	_lantern(Vector3(8.6, FY + 0.76, -26.0), 0.8, 4.5)
	_lantern(Vector3(14.6, FY + 0.38, -18.6), 0.8, 5.0)
	for x in [10.5, 18.5]:
		var s := spot(Vector3(x, FY + 5.9, -26.5), Vector3(14.5, FY + 1.0, -31.8), Color(1.0, 0.82, 0.55), 3.0, 14.0, 30.0, false)
		_lamps.append([s, 3.0, 2.0, "weak", null])
	# the stage table: Ruth's log lives here
	Props.table(geo, Vector3(11.5, FY + 1.0, -32.0), 0.0, Vector2(1.8, 0.8))
	Props.chair(geo, Vector3(11.5, FY + 1.0, -30.9), PI, false)
	Props.chair(geo, Vector3(12.9, FY + 1.0, -31.6), PI * 0.7, true)
	_lantern(Vector3(12.1, FY + 1.0 + 0.75, -32.1), 1.0, 5.5)
	# covered bodies laid along the stage back wall (per Ruth's log)
	for i in 3:
		_cot(Vector3(17.0 + i * 1.5, FY + 1.0, -33.0), PI * 0.5, Color(0.5, 0.5, 0.52), 2)
	# frost, icicles
	_frost_patch(Vector3(14.5, FY, -20.0), 12.0, 14.0)
	_icicles(Vector3(8.0, FY + HG - 0.3, -10.3), Vector3(21.5, FY + HG - 0.3, -10.3), 14, 0.7)
	_icicles(Vector3(8.0, FY + HG - 0.3, -33.8), Vector3(21.5, FY + HG - 0.3, -33.8), 14, 0.7)
	# gym entry trigger: one-time hint about the light
	trigger("l2_gym_enter", Vector3(9.0, FY + 1.0, -24.0), Vector3(3.0, 2.5, 3.5), func(_p):
		UI.toast("Dozens of cots. Some of them are moving, slightly. The light is what wakes them. (L)", 6.0)
		Game.set_objective("Cross the gym to the locker-room stairs. Don't wake them — keep the flashlight off."))

func _xmas_tree(pos: Vector3) -> void:
	var g := _m("tree_g", Color(0.06, 0.14, 0.07), 0.95)
	Props.cyl(geo, 0.06, 0.4, pos + Vector3(0, 0.2, 0), _m("trunk", Color(0.2, 0.12, 0.07), 0.9), false)
	for i in 4:
		Props.cyl(geo, 0.7 - i * 0.14, 0.5, pos + Vector3(0, 0.55 + i * 0.4, 0), g, false, 0.1 - i * 0.02, Vector3.ZERO, 8)
		_deco(pos + Vector3(0, 0.78 + i * 0.4, 0), Vector3(1.0 - i * 0.2, 0.03, 1.0 - i * 0.2), _m("frost_top", Color(0.85, 0.9, 1.0, 0.4), 0.4))
	for i in 12:
		var a := TAU * float(i) / 12.0 * 2.0
		var h := 0.5 + (float(i) / 12.0) * 1.4
		var rad := 0.55 * (1.0 - h / 2.1)
		var c: Color = [Color(1.0, 0.3, 0.2), Color(1.0, 0.85, 0.4), Color(0.4, 0.8, 1.0), Color(0.5, 1.0, 0.5)][i % 4]
		Props.sphere(geo, 0.03, pos + Vector3(cos(a) * rad, h, sin(a) * rad), Mats.emissive(c, 3.0))
	Props.sphere(geo, 0.08, pos + Vector3(0, 2.1, 0), Mats.emissive(Color(1.0, 0.9, 0.5), 3.0))
	var l := light(pos + Vector3(0, 1.3, 0.3), Color(1.0, 0.75, 0.5), 1.1, 5.5, false, false)
	_lamps.append([l, 1.1, 5.0, "weak", null])

# ====================================================================== BASEMENT
func _build_basement() -> void:
	var h := 3.2
	# floors
	floor_rect(-22, -34, -2, -30.5, YB, "concrete")
	floor_rect(-22, -30.5, -18, -26, YB, "concrete")
	floor_rect(-18, -30.5, -12, -20, YB, "concrete")
	floor_rect(-12, -30.5, -2, -18, YB, "concrete")
	floor_rect(-2, -34, 4, -27, YB, "wood_floor")
	floor_rect(-2, -23, 4, -19.6, YB, "concrete")
	floor_rect(4, -34, 22, -12, YB, "concrete")
	# walls (basement walls rise to the underside of the ground slab at FY-0.3 = YB + 3.2)
	_w(-22, -34, 22, -34, h, "concrete", [], YB)                       # north (exterior)
	_w(-22, -34, -22, -26, h, "concrete", [], YB)                      # stair foot, west
	_w(-22, -26, -18, -26, h, "concrete", [], YB)                      # stair foot, south
	_w(-18, -30.5, -18, -20, h, "concrete", [], YB)                    # shaft east / chase west
	_w(-18, -30.5, -2, -30.5, h, "concrete", [[3.0, 1.6, 2.45], [11.0, 1.6, 2.45]], YB)   # BC south: chase door, boiler door
	_w(-18, -20, -12, -20, h, "concrete", [], YB)                      # chase south
	_w(-12, -30.5, -12, -18, h, "concrete", [], YB)                    # chase east / boiler west
	_w(-12, -18, -2, -18, h, "concrete", [], YB)                       # boiler south
	_w(-2, -34, -2, -18, h, "concrete", [[1.8, 1.6, 2.45], [5.3, 1.6, 2.45], [12.7, 1.6, 2.45]], YB)  # boiler/office east wall
	_w(-2, -27, 4, -27, h, "concrete", [], YB)                         # office south
	_w(-2, -23, 4, -23, h, "concrete", [], YB)                         # passage north
	_w(-2, -19.6, 4, -19.6, h, "concrete", [], YB)                     # passage south
	_w(4, -34, 4, -12, h, "concrete", [[12.7, 1.6, 2.45]], YB)         # office east / locker west
	_w(22, -34, 22, -12, h, "concrete", [], YB)                        # locker east
	_w(4, -12, 22, -12, h, "concrete", [], YB)                         # locker south
	# doors
	_dx("l2_d_chase", -15, -30.5, {"mat": "metal_painted"}, YB)
	_dx("l2_d_boiler", -7, -30.5, {"mat": "metal_painted", "lock_item": "school_key", "keep_key": true, "locked_msg": "BOILER ROOM — AUTHORIZED PERSONNEL ONLY. The custodian's keyring opens it.", "label": "BOILER"}, YB)
	_dz("l2_d_bc_office", -2, -32.2, {"mat": "wood"}, YB)
	_dz("l2_d_boiler_office", -2, -28.7, {"mat": "wood"}, YB)
	_dz("l2_d_boiler_pass", -2, -21.3, {"mat": "metal_painted"}, YB)
	_dz("l2_d_pass_locker", 4, -21.3, {"mat": "metal_painted"}, YB)
	# ---- stair foot / corridor
	_red_lamp(Vector3(-20.0, YB + 3.0, -33.6), 1.8, 8.0)
	var sl := _L(Vector3(-20.0, YB + 2.2, -30.5), Color(0.5, 0.65, 1.0), 1.0, 6.0, false, "steady")
	_fluor(Vector3(-11.0, YB + h, -32.2), PI * 0.5, 1.2, 7.5, false, "weak", Color(0.7, 0.85, 1.0))
	_fluor(Vector3(-5.0, YB + h, -32.2), PI * 0.5, 1.2, 7.5, false, "late", Color(0.7, 0.85, 1.0))
	Props.pipe(geo, Vector3(-21.9, YB + 3.0, -33.3), Vector3(-2.2, YB + 3.0, -33.3), 0.09, "metal_rust")
	Props.pipe(geo, Vector3(-17.9, YB + 2.75, -31.0), Vector3(-2.2, YB + 2.75, -31.0), 0.06, "metal")
	_icicles(Vector3(-17.0, YB + 2.9, -33.2), Vector3(-3.0, YB + 2.9, -33.2), 12, 0.5)
	_frost_patch(Vector3(-10.0, YB, -32.2), 14.0, 3.0)
	_sign("BOILER ROOM ->", Vector3(-7.0, YB + 2.7, -30.4), PI * 0.0 + PI, 24, Color(1.0, 0.8, 0.3))
	_sign("CUSTODIAL ->", Vector3(-3.0, YB + 2.7, -33.8), 0.0, 24, Color(0.85, 0.9, 0.8))
	Props.barrel(geo, Vector3(-16.4, YB, -33.2), 0.0)
	Props.crate(geo, Vector3(-13.0, YB, -33.0), 0.3, 0.7)
	Props.debris(geo, Vector3(-9.0, YB, -33.0), 0.0, 4, "concrete")
	# ---- pipe chase / storage
	_bulb(Vector3(-15.0, YB + h, -25.0), 1.4, 7.0, false, "weak", Color(0.8, 0.9, 1.0), 0.5)
	Props.shelf(geo, Vector3(-17.4, YB, -22.0), PI * 0.5, 2.0, 2.0, false)
	Props.shelf(geo, Vector3(-17.4, YB, -27.5), PI * 0.5, 2.0, 2.0, false)
	Props.barrel(geo, Vector3(-13.0, YB, -22.0), 0.0)
	Props.barrel(geo, Vector3(-12.9, YB, -23.0), 0.0, false)
	Props.crate(geo, Vector3(-13.0, YB, -29.0), 0.2, 0.8)
	Props.crate(geo, Vector3(-13.2, YB, -28.1), 0.5, 0.6)
	Props.trash_bags(geo, Vector3(-16.0, YB, -20.9), 0.0, 3)
	Props.pipe(geo, Vector3(-17.8, YB + 2.9, -29.0), Vector3(-12.2, YB + 2.9, -29.0), 0.08, "metal_rust")
	Props.pipe(geo, Vector3(-17.8, YB + 2.6, -22.0), Vector3(-12.2, YB + 2.6, -22.0), 0.08, "metal_rust")
	_frost_patch(Vector3(-15.0, YB, -25.0), 5.0, 9.0)
	_icicles(Vector3(-17.5, YB + 2.9, -21.0), Vector3(-12.5, YB + 2.9, -21.0), 8, 0.5)
	# mops, buckets
	Props.cyl(geo, 0.2, 0.3, Vector3(-16.5, YB + 0.15, -24.8), _m("bucket", Color(0.7, 0.7, 0.2), 0.6), false, 0.25)
	Props.cyl(geo, 0.015, 1.4, Vector3(-16.4, YB + 0.7, -24.8), Mats.get_mat("wood"), false, -1.0, Vector3(0.0, 0, 0.15))

# ---- boiler room
func _build_boiler() -> void:
	var h := 3.2
	# lighting: a work lamp, dead boiler glow added when lit
	_bulb(Vector3(-5.0, YB + h, -25.5), 1.8, 9.0, true, "weak", Color(1.0, 0.78, 0.5), 0.6)
	_fluor(Vector3(-9.0, YB + h, -20.0), PI * 0.5, 1.1, 7.0, false, "late", Color(0.7, 0.85, 1.0))
	# boiler shell (vertical cylinder), burner box, flue
	var steel := _m("boiler_steel", Color(0.28, 0.3, 0.3), 0.45, 0.7)
	Props.cyl(geo, 1.15, 2.7, Vector3(-9.0, YB + 1.35, -24.5), steel, true, -1.0, Vector3.ZERO, 24)
	Props.cyl(geo, 1.2, 0.12, Vector3(-9.0, YB + 2.74, -24.5), steel, false, -1.0, Vector3.ZERO, 24)
	Props.cyl(geo, 1.2, 0.12, Vector3(-9.0, YB + 0.06, -24.5), steel, false, -1.0, Vector3.ZERO, 24)
	for yy in [0.5, 1.4, 2.3]:
		Props.cyl(geo, 1.19, 0.08, Vector3(-9.0, YB + yy, -24.5), _m("boiler_band", Color(0.2, 0.2, 0.2), 0.5, 0.7), false, -1.0, Vector3.ZERO, 24)
	Props.cyl(geo, 0.28, 1.0, Vector3(-9.0, YB + 3.2, -24.5), steel, false)       # flue stub
	# burner / firebox on the east face
	Props.box(geo, Vector3(1.2, 1.0, 1.1), Vector3(-7.5, YB + 0.85, -24.5), _m("burner", Color(0.18, 0.2, 0.22), 0.5, 0.6), true)
	Props.box(geo, Vector3(0.5, 0.5, 0.6), Vector3(-6.7, YB + 0.95, -24.5), _m("burner_motor", Color(0.12, 0.25, 0.4), 0.5, 0.5), true)
	_firebox_glow = Props.box(geo, Vector3(0.04, 0.3, 0.4), Vector3(-6.88, YB + 0.9, -24.5), Mats.emissive(Color(1.0, 0.45, 0.1), 0.0), false)
	_firebox = light(Vector3(-6.4, YB + 1.0, -24.5), Color(1.0, 0.5, 0.18), 0.0, 8.0, false, false)
	# feed pipe from the burner side to the east wall + valve body + stem
	var pipe_m := "metal_rust"
	Props.pipe(geo, Vector3(-9.0, YB + 1.7, -25.2), Vector3(-2.15, YB + 1.7, -25.2), 0.09, pipe_m)
	Props.pipe(geo, Vector3(-9.0, YB + 2.5, -23.4), Vector3(-2.15, YB + 2.5, -23.4), 0.07, "metal")
	Props.cyl(geo, 0.17, 0.4, VLV + Vector3(0, 0, 0), _m("valve_body", Color(0.3, 0.2, 0.15), 0.6, 0.7), false)
	Props.cyl(geo, 0.025, 0.35, VLV + Vector3(0, 0.38, 0), Mats.get_mat("metal"), false)
	_valve_wheel = Node3D.new()
	_valve_wheel.position = VLV + Vector3(0, 0.56, 0)
	add_child(_valve_wheel)
	var wm := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.17
	tm.outer_radius = 0.21
	wm.mesh = tm
	wm.material_override = _m("wheel", Color(0.5, 0.1, 0.08), 0.5, 0.6)
	_valve_wheel.add_child(wm)
	for a in [0.0, PI * 0.5]:
		Props.box(_valve_wheel, Vector3(0.38, 0.03, 0.03), Vector3.ZERO, _m("wheel", Color(0.5, 0.1, 0.08), 0.5, 0.6), false, Vector3(0, a, 0))
	_valve_wheel.visible = Game.has_flag("l2_valve_on")
	_icicles(VLV + Vector3(-0.4, 0.3, 0.3), VLV + Vector3(0.4, 0.3, 0.3), 4, 0.3)
	# steam from the relief valve
	_steam = CPUParticles3D.new()
	_steam.amount = 30
	_steam.lifetime = 2.0
	_steam.direction = Vector3.UP
	_steam.spread = 18.0
	_steam.initial_velocity_min = 0.5
	_steam.initial_velocity_max = 1.2
	_steam.gravity = Vector3(0, 0.3, 0)
	_steam.scale_amount_min = 0.1
	_steam.scale_amount_max = 0.3
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	_steam.mesh = sm
	var stm := Mats.color(Color(0.9, 0.92, 0.95, 0.12), 1.0)
	stm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_steam.material_override = stm
	_steam.position = Vector3(-9.0, YB + 3.0, -23.8)
	_steam.emitting = false
	add_child(_steam)
	# gauges
	for g in [[Vector3(-9.0, YB + 2.0, -23.35), PI], [Vector3(-8.3, YB + 1.5, -23.5), PI]]:
		Props.cyl(geo, 0.12, 0.05, g[0], Mats.get_mat("metal"), false, -1.0, Vector3(PI * 0.5, 0, 0))
		Props.cyl(geo, 0.1, 0.02, g[0] + Vector3(0, 0, 0.03), Mats.emissive(Color(0.5, 0.9, 0.6), 0.5), false, -1.0, Vector3(PI * 0.5, 0, 0))
	# control cabinet on the south wall
	Props.box(geo, Vector3(1.9, 2.2, 0.4), Vector3(PNL.x, YB + 1.1, -18.35), _m("panel_grey", Color(0.38, 0.4, 0.4), 0.5, 0.5), true)
	Props.box(geo, Vector3(1.7, 1.9, 0.02), Vector3(PNL.x, YB + 1.15, -18.57), _m("panel_face", Color(0.2, 0.22, 0.22), 0.6, 0.3), false)
	_label("HEATING PLANT — BURNER CONTROL", Vector3(PNL.x, YB + 2.0, -18.6), PI, 18, Color(0.9, 0.9, 0.85), 0.0035)
	# fuse holder, lamps, buttons (positions chosen so interact radii do not overlap)
	_label("F2  60A", Vector3(-7.15, YB + 1.55, -18.6), PI, 16, Color(0.9, 0.9, 0.85), 0.004)
	_lamp_fuse = Props.box(geo, Vector3(0.14, 0.14, 0.05), Vector3(-7.15, YB + 1.3, -18.6), Mats.emissive(Color(1.0, 0.1, 0.05), 2.0), false)
	_label("PURGE", Vector3(-6.55, YB + 1.55, -18.6), PI, 16, Color(0.6, 0.85, 1.0), 0.004)
	_lamp_purge = Props.box(geo, Vector3(0.14, 0.14, 0.05), Vector3(-6.55, YB + 1.3, -18.6), Mats.emissive(Color(0.2, 0.2, 0.2), 0.2), false)
	_label("IGNITE", Vector3(-5.95, YB + 1.55, -18.6), PI, 16, Color(1.0, 0.7, 0.4), 0.004)
	_lamp_flame = Props.box(geo, Vector3(0.14, 0.14, 0.05), Vector3(-5.95, YB + 1.3, -18.6), Mats.emissive(Color(0.2, 0.2, 0.2), 0.2), false)
	_label("FEED", Vector3(-5.35, YB + 1.55, -18.6), PI, 16, Color(0.8, 0.9, 0.8), 0.004)
	_lamp_feed = Props.box(geo, Vector3(0.14, 0.14, 0.05), Vector3(-5.35, YB + 1.3, -18.6), Mats.emissive(Color(0.2, 0.2, 0.2), 0.2), false)
	# the fuse holder / buttons as interactables
	interact(Vector3(-7.15, YB + 1.2, -19.2), "Fuse holder (F2 60A)", func(_p): _fuse_interact(), 0.55)
	interact(Vector3(-6.55, YB + 1.2, -19.2), "PURGE", func(_p): _purge_interact(), 0.55)
	interact(Vector3(-5.95, YB + 1.2, -19.2), "IGNITE", func(_p): _ignite_interact(), 0.55)
	interact(VLV + Vector3(0, -0.4, 0.5), "Feed valve", func(_p): _valve_interact(), 1.5)
	# instruction card on a steel table
	Props.table(geo, Vector3(-3.6, YB, -19.6), 0.0, Vector2(1.2, 0.6))
	# workbench, tool wall, drums
	Props.table(geo, Vector3(-11.0 + 0.0, YB, -29.0), PI * 0.5, Vector2(1.8, 0.7))
	Props.barrel(geo, Vector3(-3.0, YB, -29.8), 0.0)
	Props.barrel(geo, Vector3(-3.0, YB, -28.9), 0.0, false)
	Props.crate(geo, Vector3(-4.0, YB, -29.8), 0.3, 0.7)
	Props.pipe(geo, Vector3(-11.8, YB + 3.0, -29.0), Vector3(-2.2, YB + 3.0, -29.0), 0.1, "metal_rust")
	Props.pipe(geo, Vector3(-11.8, YB + 2.8, -26.0), Vector3(-2.2, YB + 2.8, -26.0), 0.06, "metal")
	_icicles(Vector3(-11.5, YB + 2.9, -29.0), Vector3(-4.0, YB + 2.9, -29.0), 12, 0.5)
	_icicles(Vector3(-10.0, YB + 2.7, -26.1), Vector3(-5.0, YB + 2.7, -26.1), 8, 0.4)
	# frozen puddles and rime on the shell — melt when the boiler runs
	_frost_patch(Vector3(-7.0, YB, -23.0), 9.0, 9.0)
	_frost_patch(Vector3(-8.0, YB, -28.5), 6.0, 3.0)
	# hum of dead machinery: red standby lamp on the panel wall
	_red_lamp(Vector3(-3.0, YB + 2.9, -18.3), 0.9, 5.0)
	_sign("PURGE · IGNITE · FEED", Vector3(-9.0, YB + 2.6, -18.2), PI, 28, Color(1.0, 0.8, 0.3))

# ---- safe room: the custodian's office
func _build_safe_room() -> void:
	var h := 3.2
	# warm light, shadows on; steady (its own little circuit)
	var wl := _L(Vector3(1.0, YB + 2.6, -30.5), Color(1.0, 0.75, 0.45), 2.4, 8.0, true, "steady")
	Props.cyl(geo, 0.012, 0.5, Vector3(1.0, YB + 2.95, -30.5), Mats.get_mat("metal"), false)
	Props.sphere(geo, 0.1, Vector3(1.0, YB + 2.65, -30.5), Mats.emissive(Color(1.0, 0.8, 0.55), 3.0))
	var safe_pos := Vector3(1.0, YB + 1.0, -30.5)
	Props.desk(geo, Vector3(2.8, YB, -32.9), 0.0)
	Props.chair(geo, Vector3(2.8, YB, -31.8), PI, false)
	Props.couch(geo, Vector3(-0.2, YB, -31.0), PI * 0.5)
	Props.shelf(geo, Vector3(3.6, YB, -28.0), PI * 0.5, 1.8, 2.0, true)
	Props.cabinet(geo, Vector3(-1.5, YB, -28.2), PI)
	_label("CUSTODIAL", Vector3(1.0, YB + 2.5, -33.82), 0.0, 24, Color(0.85, 0.85, 0.75), 0.004)
	_label("DECEMBER 2026\nW. Dubois — heat + hearts", Vector3(3.8, YB + 1.8, -33.82), 0.0, 14, Color(0.6, 0.15, 0.15), 0.004)
	_deco(Vector3(3.8, YB + 1.65, -33.86), Vector3(0.6, 0.8, 0.02), "paper")
	item_box(Vector3(0.6, YB, -27.7), PI)
	save_point(Vector3(2.4, YB + 0.79, -32.8), 0.0)
	_lantern(Vector3(2.4, YB + 0.78, -32.6), 0.0, 3.0)
	# mug, thermos, blanket
	Props.cyl(geo, 0.05, 0.1, Vector3(3.3, YB + 0.84, -32.7), _m("mug", Color(0.85, 0.85, 0.8), 0.6), false)
	Props.box(geo, Vector3(1.2, 0.18, 0.5), Vector3(-0.3, YB + 0.55, -31.0), _m("blanket_red", Color(0.45, 0.1, 0.08), 0.97), false)
	_sign("SAFE — WARM", Vector3(-1.9, YB + 2.2, -30.0), PI * 0.5, 20, Color(0.5, 1.0, 0.6), false)
	# the safe zone volume + music
	var a := Area3D.new()
	a.add_to_group("safe_zone")
	a.collision_layer = 0
	a.collision_mask = 2
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(5.8, 3.0, 6.8)
	cs.shape = sh
	a.add_child(cs)
	a.position = Vector3(1.0, YB + 1.5, -30.5)
	add_child(a)
	a.body_entered.connect(func(b):
		if b.is_in_group("player"):
			Sfx.music("music_safe", -11.0))
	a.body_exited.connect(func(b):
		if b.is_in_group("player"):
			Sfx.music("music_tension", -13.0))

# ---- locker room: flooded, then frozen
func _build_locker_room() -> void:
	var h := 3.2
	# ice sheet over the floor
	_deco(Vector3(13.0, YB + 0.04, -23.0), Vector3(16.0, 0.08, 20.0), "ice")
	for i in 14:
		_deco(Vector3(randf_range(5.5, 21.0), YB + 0.09, randf_range(-33, -13)), Vector3(randf_range(0.5, 1.6), 0.02, randf_range(0.4, 1.2)), _m("ice_crack", Color(0.85, 0.95, 1.0, 0.5), 0.1), Vector3(0, randf() * TAU, 0))
	# lights: cold emergency strips, red exit, flicker
	_fluor(Vector3(10.0, YB + h, -30.0), 0.0, 1.5, 9.0, false, "weak", Color(0.65, 0.85, 1.0))
	_fluor(Vector3(16.0, YB + h, -22.0), 0.0, 1.6, 9.0, false, "late", Color(0.65, 0.85, 1.0))
	_fluor(Vector3(10.0, YB + h, -16.0), 0.0, 1.3, 9.0, false, "weak", Color(0.65, 0.85, 1.0))
	_red_lamp(Vector3(5.0, YB + 2.9, -21.3), 1.3, 7.0)
	_red_lamp(Vector3(13.0, YB + 3.0, -12.2), 1.3, 7.0)
	var cold := light(Vector3(13.0, YB + 2.8, -23.0), Color(0.4, 0.65, 1.0), 0.8, 14.0, false, false)
	_lamps.append([cold, 0.8, 1.5, "steady", null])
	# locker banks (rows) and benches
	for z in [-33.3, -12.7]:
		for xx in [7.0, 12.0, 17.0]:
			Props.locker(geo, Vector3(xx, YB, z), PI if z < -20.0 else 0.0, 6)
	for xx in [8.2, 13.2, 18.2]:
		Props.bench(geo, Vector3(xx, YB, -27.6), PI * 0.5)
		Props.bench(geo, Vector3(xx, YB, -17.6), PI * 0.5)
	Props.locker(geo, Vector3(21.5, YB, -26.0), -PI * 0.5, 6)
	Props.locker(geo, Vector3(21.5, YB, -19.0), -PI * 0.5, 6)
	# shower area on the east: pipes, heads, ice cones
	for i in 5:
		var sz := -30.5 + i * 0.9
		Props.pipe(geo, Vector3(21.4, YB + 2.6, sz), Vector3(21.4, YB + 2.9, sz), 0.03, "metal")
		Props.cyl(geo, 0.1, 0.04, Vector3(21.3, YB + 2.55, sz), Mats.get_mat("metal"), false)
		var ln := randf_range(0.6, 1.8)
		Props.cyl(geo, 0.1, ln, Vector3(21.3, YB + 2.5 - ln * 0.5, sz), Mats.get_mat("ice"), false, 0.01, Vector3.ZERO, 8)
	# frozen waterfalls from burst pipes
	for p in [Vector3(7.5, YB, -20.0), Vector3(19.5, YB, -30.0)]:
		Props.cyl(geo, 0.25, 2.8, p + Vector3(0, 1.4, 0), Mats.get_mat("ice"), false, 0.08, Vector3.ZERO, 8)
		_mound(p + Vector3(0, 0, 0.1), 0.9, 0.2)
	Props.pipe(geo, Vector3(5.0, YB + 2.8, -20.0), Vector3(21.5, YB + 2.8, -20.0), 0.08, "metal_rust")
	_icicles(Vector3(6.0, YB + 2.75, -20.2), Vector3(21.0, YB + 2.75, -20.2), 18, 0.7)
	_icicles(Vector3(5.0, YB + 3.1, -33.0), Vector3(21.0, YB + 3.1, -33.0), 12, 0.6)
	# the frozen supply pipe with the valve wheel entombed in ice
	var pp := Vector3(15.5, YB + 1.1, -26.0)
	Props.pipe(geo, pp + Vector3(-3.0, 0, 0), pp + Vector3(3.0, 0, 0), 0.09, "metal_rust")
	Props.pipe(geo, pp + Vector3(0, -1.1, 0), pp + Vector3(0, 0, 0), 0.07, "metal_rust")
	_ice_sheath = Node3D.new()
	_ice_sheath.position = pp
	add_child(_ice_sheath)
	var ice_m := Mats.get_mat("ice")
	Props.cyl(_ice_sheath, 0.4, 1.4, Vector3.ZERO, ice_m, false, 0.32, Vector3(0, 0, PI * 0.5), 12)
	Props.sphere(_ice_sheath, 0.42, Vector3(0, 0.05, 0), ice_m, Vector3(1.2, 0.9, 1.0))
	var w := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.1
	tm.outer_radius = 0.13
	w.mesh = tm
	w.material_override = _m("wheel", Color(0.5, 0.1, 0.08), 0.5, 0.6)
	w.position = Vector3(0, 0.04, 0)
	_ice_sheath.add_child(w)
	if Game.has_flag("l2_ice_broken"):
		_ice_sheath.visible = false
	else:
		interact(pp + Vector3(0, -0.5, 0.9), "Break the ice (hatchet)", func(_p): _use_hatchet_on_ice(), 1.8)
	# floor clutter frozen in place: shoes, towels, a gym bag
	for i in 14:
		var p := Vector3(randf_range(6.0, 20.5), YB + 0.1, randf_range(-32.0, -14.0))
		if absf(p.x - 9.2) < 1.8 and p.z > -18.5:
			continue
		Props.box(geo, Vector3(0.2, 0.1, 0.3), p, _m("shoe%d" % (i % 3), Color.from_hsv(randf(), 0.3, 0.3), 0.8), false, Vector3(0, randf() * 3.0, 0))
	Props.corpse(geo, Vector3(10.5, YB + 0.1, -29.5), 0.6, {"shirt": Color(0.3, 0.3, 0.32), "zombie": false})
	_frost_patch(Vector3(13.0, YB + 0.1, -23.0), 14.0, 18.0, false)

# ====================================================================== PUZZLE: boiler
func _fuse_interact() -> void:
	if Game.has_flag("l2_fuse_in"):
		UI.toast("The 60-amp fuse is seated. The controller's standby lamp is lit.")
		return
	if Game.has_item("fuse_60a"):
		_insert_fuse()
	else:
		Sfx.play("deny")
		UI.toast("F2 — 60A. The holder is empty. Somebody pulled it, or it blew.")

func _insert_fuse() -> void:
	if not Game.remove_item("fuse_60a", 1):
		return
	Game.set_flag("l2_fuse_in")
	Sfx.play("unlock")
	UI.toast("Seated the 60A fuse. The controller wakes: standby lamp on.")
	_refresh_panel_lamps()
	_refresh_objective()

func _purge_interact() -> void:
	if Game.has_flag("boiler_on"):
		UI.toast("The burner is running.")
		return
	if not Game.has_flag("l2_fuse_in"):
		Sfx.play("deny")
		UI.toast("Nothing happens. The burner controller has no power — no fuse.")
		return
	if _purging:
		UI.toast("The blower is still running. Wait for the lamp.")
		return
	if Game.has_flag("l2_purged"):
		UI.toast("Already purged. Light the pilot before the hearth cools: IGNITE.")
		return
	_purging = true
	Sfx.play("valve")
	UI.toast("PURGE: blower running. Hold on for one full cycle...")
	_set_lamp(_lamp_purge, Color(0.3, 0.6, 1.0), 1.5)
	await get_tree().create_timer(6.0).timeout
	_purging = false
	Game.set_flag("l2_purged")
	Sfx.play("click")
	UI.toast("PURGE COMPLETE. The green lamp is lit.")
	_set_lamp(_lamp_purge, Color(0.2, 1.0, 0.4), 2.5)
	_refresh_objective()

func _ignite_interact() -> void:
	if Game.has_flag("boiler_on"):
		UI.toast("The burner is running.")
		return
	if not Game.has_flag("l2_fuse_in"):
		Sfx.play("deny")
		UI.toast("Dead. No control power.")
		return
	if Game.has_flag("l2_flame"):
		UI.toast("Flame proven. Steady blue. Now the feed valve.")
		return
	if _purging or not Game.has_flag("l2_purged"):
		Sfx.play("metal_impact")
		Sfx.play("alarm")
		Game.flags.erase("l2_purged")
		_set_lamp(_lamp_purge, Color(0.2, 0.2, 0.2), 0.2)
		_set_lamp(_lamp_flame, Color(1.0, 0.1, 0.05), 2.5)
		UI.toast("FLAME FAILURE — LOCKOUT. Fired it before a full purge. Purge first, then ignite.", 4.5)
		await get_tree().create_timer(2.0).timeout
		_set_lamp(_lamp_flame, Color(0.2, 0.2, 0.2), 0.2)
		_purging = false
		return
	Game.set_flag("l2_flame")
	Sfx.play("explosion")
	UI.toast("IGNITE: pilot lit, main flame proven. Steady blue.")
	_set_lamp(_lamp_flame, Color(0.3, 0.6, 1.0), 2.5)
	if _firebox:
		var tw := create_tween()
		tw.tween_property(_firebox, "light_energy", 1.3, 0.8)
		tw.parallel().tween_property(_firebox_glow.material_override, "emission_energy_multiplier", 3.0, 0.8)
	_refresh_objective()

func _valve_interact() -> void:
	if not Game.has_flag("l2_valve_on"):
		if Game.has_item("valve_handle"):
			_mount_valve()
		else:
			Sfx.play("deny")
			UI.toast("The valve stem is bare. Somebody took the wheel off.")
		return
	if Game.has_flag("boiler_on"):
		UI.toast("The feed valve is open. Pipes are ticking.")
		return
	if not Game.has_flag("l2_flame"):
		UI.toast("Don't open the feed on a dead boiler. Purge, ignite — then feed.")
		return
	_boiler_roars()

func _mount_valve() -> void:
	if not Game.remove_item("valve_handle", 1):
		return
	Game.set_flag("l2_valve_on")
	_valve_wheel.visible = true
	Sfx.play("metal_impact")
	UI.toast("Fitted the valve wheel. The feed is still closed.")
	_set_lamp(_lamp_feed, Color(1.0, 0.7, 0.2), 1.5)
	_refresh_objective()

func _boiler_roars() -> void:
	lock_player(true)
	Game.set_flag("boiler_on")
	Sfx.play("valve")
	var tw := _valve_wheel.create_tween()
	tw.tween_property(_valve_wheel, "rotation:y", PI * 4.0, 2.0)
	_set_lamp(_lamp_feed, Color(0.2, 1.0, 0.4), 2.5)
	await get_tree().create_timer(1.8).timeout
	Sfx.play("explosion")
	_powered = true
	_apply_power_visuals(false)
	await get_tree().create_timer(1.5).timeout
	Sfx.play("metal_impact")
	await say([
		["ELIAS", "Hear that? Pipes ticking all the way up. That's heat in the walls."],
		["ELIAS", "And the building bus is steady again. No more brownout."],
	])
	lock_player(false)
	Game.set_objective("The boiler is running. Find June's trail — her homeroom, Classroom 2B.")
	await get_tree().create_timer(2.0).timeout
	Sfx.play("radio_squelch")
	UI.toast("JUNE (radio): \"Dad? The school's lit up like a Christmas tree. Is that you?\"", 5.0)

func _set_lamp(m: MeshInstance3D, c: Color, e: float) -> void:
	if m == null:
		return
	var mat := m.material_override as StandardMaterial3D
	mat.albedo_color = c
	mat.emission = c
	mat.emission_energy_multiplier = e

func _refresh_panel_lamps() -> void:
	if Game.has_flag("l2_fuse_in"):
		_set_lamp(_lamp_fuse, Color(0.2, 1.0, 0.4), 2.0)
	if Game.has_flag("l2_purged"):
		_set_lamp(_lamp_purge, Color(0.2, 1.0, 0.4), 2.5)
	if Game.has_flag("l2_flame"):
		_set_lamp(_lamp_flame, Color(0.3, 0.6, 1.0), 2.5)
	if Game.has_flag("l2_valve_on"):
		_set_lamp(_lamp_feed, Color(1.0, 0.7, 0.2), 1.5)
	if Game.has_flag("boiler_on"):
		_set_lamp(_lamp_feed, Color(0.2, 1.0, 0.4), 2.5)

func _apply_power_visuals(instant: bool) -> void:
	_refresh_panel_lamps()
	if not _powered:
		return
	if _firebox:
		_firebox.light_energy = 3.2
		(_firebox_glow.material_override as StandardMaterial3D).emission_energy_multiplier = 3.5
	if _steam:
		_steam.emitting = true
	for n in _frost_cold:
		if is_instance_valid(n):
			n.visible = false
	if _valve_wheel:
		_valve_wheel.visible = true

# ====================================================================== ICE + KEY ITEMS
func _use_hatchet_on_ice() -> void:
	if Game.has_flag("l2_ice_broken"):
		return
	if not Game.has_item("knife"):
		UI.toast("Solid ice. You'd need something with an edge. Your hatchet.")
		Sfx.play("deny")
		return
	Game.set_flag("l2_ice_broken")
	lock_player(true)
	for i in 4:
		Sfx.play("knife_hit")
		await get_tree().create_timer(0.45).timeout
	Sfx.play("glass_break")
	if is_instance_valid(_ice_sheath):
		_ice_sheath.visible = false
	lock_player(false)
	pickup("l2_valve_wheel", "valve_handle", 1, Vector3(15.5, YB + 0.2, -25.3))
	UI.toast("The ice cracks away. A cast-iron valve wheel drops out.")

# ====================================================================== ENEMIES
func _sleeper(uid: String, pos: Vector3, variant := "civilian", yaw := 0.0) -> void:
	var e := enemy(uid, "zombie", pos, yaw, {"variant": variant, "dormant": true})
	if e == null:
		return
	e.dormant = false
	if e.model:
		e.model.pose = "dead"
	_sleepers.append(e)

func _wake_sleeper(e: Node3D) -> void:
	if not is_instance_valid(e) or e.state != "dormant":
		return
	if e.model:
		e.model.pose = "zombie"
	e.wake()
	# neighbours stir
	for o in _sleepers:
		if is_instance_valid(o) and o != e and o.state == "dormant" and o.global_position.distance_to(e.global_position) < 3.6:
			o.set_meta("wake_at", _t + randf_range(0.5, 1.6))

func _update_sleepers() -> void:
	if _sleepers.is_empty() or player == null:
		return
	var fl: bool = player.flashlight != null and player.flashlight.visible
	var fwd: Vector3 = player.model.global_transform.basis.z
	var pp := player.global_position
	var keep: Array = []
	for e in _sleepers:
		if not is_instance_valid(e):
			continue
		if e.state != "dormant":
			# woken by something else (the siren's hum, gunfire): stand up properly
			if e.state != "dead" and e.model and e.model.pose == "dead":
				e.model.pose = "zombie"
			continue
		var to: Vector3 = e.global_position - pp
		to.y = 0.0
		var d := to.length()
		var woke: bool = e.awake or (e.has_meta("wake_at") and _t >= float(e.get_meta("wake_at")))
		if not woke:
			if d < 1.8:
				woke = true
			elif fl and d < 3.5:
				woke = true
			elif fl and d < 9.5 and to.normalized().dot(fwd) > 0.82:
				woke = true
			elif player.velocity.length() > 3.4 and d < 4.5:
				woke = true
		if woke:
			_wake_sleeper(e)
		else:
			keep.append(e)
	_sleepers = keep

func _place_enemies() -> void:
	# courtyard: two hounds in the dark by the wall, a Shambler by the shed, a Sleeper in the snow
	enemy("l2_hound1", "hound", Vector3(-17.0, 0, -0.5), 0.8)
	enemy("l2_hound2", "hound", Vector3(-9.0, 0, -6.5), 0.3)
	enemy("l2_z_shed", "zombie", Vector3(12.5, 0, 4.5), 2.6, {"variant": "worker"})
	enemy("l2_z_snow", "zombie", Vector3(2.5, 0.03, 4.0), 1.0, {"variant": "civilian", "sleeping": true})
	# corridor ambush: nurse variant waits in the dark by the stairwell and rises when you pass
	var amb := enemy("l2_z_corridor", "zombie", Vector3(-19.5, FY, -24.0), 0.0, {"variant": "nurse", "dormant": true})
	if amb:
		trigger("l2_corr_ambush", Vector3(-9.0, FY + 1.0, -24.0), Vector3(1.5, 3.0, 3.6), func(_p):
			if is_instance_valid(amb):
				amb.wake()
			Sfx.play("stinger_a"))
	# shop: a crawler under the benches
	enemy("l2_z_shop", "zombie", Vector3(-8.2, FY, -31.5), 0.0, {"variant": "civilian", "crawler": true})
	# coach's office: the coach, slumped, rises when the lanyard is lifted (see on_pickup)
	_coach = enemy("l2_z_coach", "zombie", Vector3(4.6, FY, -29.2), 3.0, {"variant": "worker", "dormant": true})
	if _coach and _coach.model:
		_coach.model.pose = "dead"
	# the gym: Sleepers on the cots (wake on light / proximity / the siren's hum)
	_sleeper("l2_s1", Vector3(12.2, FY + 0.37, -19.4), "civilian")
	_sleeper("l2_s2", Vector3(13.2, FY + 0.37, -24.6), "nurse")
	_sleeper("l2_s3", Vector3(17.4, FY + 0.37, -16.8), "worker")
	_sleeper("l2_s4", Vector3(18.4, FY + 0.37, -22.0), "civilian")
	_sleeper("l2_s5", Vector3(17.4, FY + 0.37, -27.2), "civilian")
	# the siren on the stage
	enemy("l2_siren", "siren", Vector3(15.6, FY + 1.0, -32.6), 0.0, {"hum_interval": 20.0})
	# stairwell hanger, locker-room burster
	enemy("l2_hanger", "hanger", Vector3(-20.0, FY + HC - 0.3, -30.0), 0.0, {"on_ceiling": true})
	enemy("l2_burster", "burster", Vector3(16.0, YB, -18.0), 3.0)

var _coach: Node3D = null

func on_pickup(item: String, uid: String) -> void:
	if item == "gym_key" and _coach and is_instance_valid(_coach) and _coach.state == "dormant":
		await get_tree().create_timer(0.8).timeout
		if is_instance_valid(_coach) and _coach.state == "dormant":
			_coach.model.pose = "zombie"
			_coach.wake()
			Sfx.play("stinger_b")
	_refresh_objective()

# ====================================================================== ITEMS
func _place_items() -> void:
	# courtyard
	pickup("l2_c_ammo1", "ammo_9mm", 8, Vector3(-3.5, 0.05, 6.0))
	pickup("l2_c_gel1", "gel", 1, Vector3(-1.5, 0.05, 11.6))
	pickup("l2_c_ammo2", "ammo_9mm", 4, Vector3(14.0, 0.05, 2.6))
	# shed (key on the hook + the road flares)
	var sp := Vector3(16.5, 0, -5.0)
	var yaw := 0.2
	pickup("l2_school_key", "school_key", 1, _shed_pt(sp, yaw, Vector3(-0.2, 1.52, -1.64)))
	pickup("l2_flares", "flare", 3, _shed_pt(sp, yaw, Vector3(-0.8, 0.8, -1.2)))
	pickup("l2_shed_ammo", "ammo_9mm", 4, _shed_pt(sp, yaw, Vector3(1.0, 0.07, 0.8)))
	# lobby / hall
	pickup("l2_h_ammo", "ammo_9mm", 6, Vector3(-6.3, FY + 0.52, -17.0))
	pickup("l2_lobby_gel", "gel", 1, Vector3(-21.0, FY + 0.52, -15.2))
	# shelter office desk: Tom's revolver and six rounds
	pickup("l2_magnum", "magnum", 1, Vector3(-10.9, FY + 0.82, -13.95))
	pickup("l2_magnum_ammo", "ammo_44", 6, Vector3(-10.1, FY + 0.82, -13.9))
	pickup("l2_office_ammo", "ammo_9mm", 6, Vector3(-9.2, FY + 0.05, -21.2))
	# shop: the 60A fuse and the tool pouch
	pickup("l2_fuse", "fuse_60a", 1, Vector3(-9.5, FY + 1.5, -33.7))
	pickup("l2_pouch", "pouch", 1, Vector3(-10.4, FY + 0.78, -32.8))
	# nurse
	pickup("l2_spray", "spray", 1, Vector3(-4.7, FY + 1.35, -27.5))
	pickup("l2_pills", "adrenaline", 1, Vector3(-1.4, FY + 0.82, -27.2))
	pickup("l2_nurse_gel", "gel", 1, Vector3(-3.6, FY + 0.7, -32.0))
	# coach: whistle lanyard = gym key
	pickup("l2_gym_key", "gym_key", 1, Vector3(3.6, FY + 0.82, -31.8))
	# 2B
	pickup("l2_2b_ammo", "ammo_9mm", 4, Vector3(-12.2, FY + 0.82, -27.2))
	# gym: ammo near the supplies, bandages under the stage
	pickup("l2_gym_ammo", "ammo_9mm", 6, Vector3(18.2, FY + 0.83, -10.9))
	pickup("l2_gym_gel", "gel", 1, Vector3(12.9, FY + 1.82, -31.7))
	pickup("l2_gym_stage_ammo", "ammo_9mm", 5, Vector3(9.0, FY + 1.05, -32.5))
	# basement
	pickup("l2_chase_ammo", "ammo_9mm", 6, Vector3(-17.0, YB + 0.05, -24.0))
	pickup("l2_chase_gel", "gel", 1, Vector3(-16.4, YB + 0.55, -27.5))
	pickup("l2_boiler_ammo", "ammo_9mm", 4, Vector3(-3.5, YB + 0.05, -29.4))
	pickup("l2_locker_ammo", "ammo_9mm", 5, Vector3(18.0, YB + 0.55, -17.6))
	pickup("l2_locker_pills", "adrenaline", 1, Vector3(13.2, YB + 0.55, -27.6))
	if Game.has_flag("l2_ice_broken") and not Game.has_flag("got:l2_valve_wheel"):
		pickup("l2_valve_wheel", "valve_handle", 1, Vector3(15.5, YB + 0.2, -25.3))

# ====================================================================== NOTES
func _place_notes() -> void:
	note("l2_n_log", Vector3(11.7, FY + 1.79, -32.0),
		"Shelter Log — R. Kade",
		"[b]KETTLE FALLS WARMING SHELTER — LOG[/b]\nKFCS Gym · R. Kade, coordinator\n\n[b]DEC 18[/b]  Grid down 6:10 pm. Co-op says \"load management.\" Opened the gym at 7. 41 signed in. Cots from the Legion, blankets from St. Brendan's.\n\n[b]DEC 19[/b]  Boiler tripped overnight. Walt says it's the 60-amp control fuse; the spare is in the shop-class drawer. Shop is locked. Walt's janitor keys hang on a hook in the yard shed, because of course they do. Locker rooms flooded when a line burst, now one big ice rink. Walt dropped the feed-valve wheel in there shutting off the water. It's frozen in the pipe. He says you'd need a hatchet. 63 in.\n\n[b]DEC 20[/b]  Three didn't wake this morning. Cold doesn't look like that. Frost on the INSIDE of their eyes. Moved them to the stage and covered them. Dr. Aho says don't touch.\nRule one: DO NOT SLEEP OUTSIDE THE GYM. Rule two: nobody sleeps alone.\n\n[b]DEC 21, 2 am[/b]  Checked off: Aho ✓ Bergstrom ✓ Lindqvist ✓ Moe ✓ Paulsen ✗ ✗ ✗ ✗\nI stopped checking.\n\nTom's voice in the vents tonight. I know it can't be. He said my name the way he did coming up the stairs.\nI'm going to the front doors to listen.", PI)
	note("l2_n_drawing", Vector3(-21.0, FY + 0.56, -15.6),
		"Drawing: \"the man with the light on his head\"",
		"[b]Crayon on construction paper.[/b]\n\nA tall black stick figure with a yellow scribble on its head and lines coming out of it. Four little stick people in a row beneath it, Xs for eyes.\n\nIn pencil, shaky, a child's capitals:\n[i]THE MAN WITH THE LIGHT ON HIS HEAD. HE WALKS AROUND OUTSIDE AT NIGHT. HE KNOCKS ON THE WINDOW AND SAYS OUR NAMES. MOM SAYS ITS JUST THE WIND. MR PELTO SAID DONT LOOK AT THE LIGHT.[/i]\n\n— Hannah W., grade 2", PI * 0.5)
	note("l2_n_email", Vector3(-10.7, FY + 0.82, -13.2),
		"Email: \"Meridian Scholars\"",
		"[b]From:[/b] Office of the Superintendent, KFCSD\n[b]To:[/b] All staff\n[b]Subject:[/b] FW: Meridian Scholars — laptops!\n\nColleagues, great news. Corvane Systems has donated 240 laptops to our students through its \"Meridian Scholars\" community partnership, pre-loaded with the Corvane Learning Suite. A photo op with the Corvane regional director is scheduled for Jan. 9.\n\nPlease note the donation is conditional on district support for the Meridian grid-priority addendum with the co-op (attached, \"non-controversial\"). Kindly do not discuss the addendum with parents before the vote.\n\nWarmly,\nD. Halvorsen\n\n[i]Handwritten across the bottom, in Ruth's pen:[/i]\n240 laptops. 63 cots. Do the math.", 0.0)
	note("l2_n_texts", Vector3(-5.5, FY + 0.52, -14.6),
		"Printout: parents' group text",
		"[b]GROUP: KF Parents (Gr. 2–5) — printed at the library, 12/19[/b]\n\n[b]Tara M:[/b] power's been out 14 hrs. Anyone else?\n[b]Brett L:[/b] whole town. Co-op text says \"rotating outages.\" Nothing's rotating. We're the ones that are out.\n[b]Tara M:[/b] my sister in Duluth has power. She sent a pic of the lake from her window. The data center is lit up like Christmas.\n[b]Brett L:[/b] why does a building in a blizzard get 100% of the juice and we get a text that says \"be patient\"\n[b]Marcy P:[/b] gym's open at the school. Ruth Kade's running it. Bring blankets, a thermos, your neighbors.\n[b]Tara M:[/b] heat's gone at the Pelto place. Taking the kids to the gym.\n[b]Brett L:[/b] hum's back. you hear it? like a refrigerator the size of the town\n[b]Tara M:[/b] [photo attached]\n\n[i](no further messages)[/i]", PI * 0.5)
	note("l2_n_boiler", Vector3(-3.6, YB + 0.78, -19.6),
		"Boiler Light-Up Card",
		"[b]KFCS HEATING PLANT — LIGHT-UP PROCEDURE[/b]\n(laminated · W. Dubois, Custodial)\n\n[b]0.[/b] Check control FUSE (F2, 60A). No fuse, no controller.\n[b]1.[/b] Fit the FEED VALVE WHEEL. Leave the valve CLOSED.\n[b]2.[/b] [b]PURGE.[/b] Run the blower one full cycle. Wait for the green lamp.\n[b]3.[/b] [b]IGNITE.[/b] Only after purge. Light it early and the controller locks out and you start over.\n[b]4.[/b] Watch the flame lamp. Steady blue = proven.\n[b]5.[/b] [b]OPEN THE FEED VALVE[/b] slowly, and not before the flame. Cold water on a hot dry shell cracks it. Ask me how I know.\n\n[i]Purge, ignite, feed. Say it out loud. Treat it like a line: verify, then energize in order.[/i]\n— Walt", 0.0)
	note("l2_n_gun", Vector3(-10.5, FY + 0.82, -14.2),
		"Sticky note on the drawer",
		"[i]In Ruth's handwriting, stuck to the desk drawer:[/i]\n\n\"Tom's gun. I could never throw it away. Six rounds in the box.\"\n\nUnderneath, in a different pen:\n\"If you're reading this you're not Tom. Be careful with it.\"", 0.3)

# ====================================================================== BLACKBOARD / objective / breath / fx
func _read_blackboard() -> void:
	var first := not Game.has_flag("l2_read_june")
	UI.show_note("Classroom 2B — Blackboard", "[i]Chalk, in a hurry, in June's slanting capitals:[/i]\n\n[b]DAD —\nGran walked out at 3am. Said Grandpa was calling her from the mine.\nI'm going after her. Church first.\n— J.\nP.S. you're late.[/b]")
	if first:
		Game.set_flag("l2_read_june")
		var files: Array = Game.get_flag("files", [])
		if not files.has("l2_n_board"):
			files.append("l2_n_board")
			Game.set_flag("files", files)
			Game.set_flag("file:l2_n_board", {"title": "Blackboard — June", "body": "DAD —\nGran walked out at 3am. Said Grandpa was calling her from the mine.\nI'm going after her. Church first.\n— J.\nP.S. you're late."})
		await get_tree().create_timer(0.3).timeout
		while UI.is_blocking():
			await get_tree().process_frame
		lock_player(true)
		await say([
			["ELIAS", "\"Grandpa was calling her from the mine.\" Dad's been dead fifteen years."],
			["ELIAS", "Ruth heard him too. The same hum that brought me home is walking my mother into the dark."],
			["ELIAS", "\"P.S. you're late.\" ...Yeah. I know, kid."],
		])
		lock_player(false)
		_refresh_objective()

func _refresh_objective() -> void:
	var t := ""
	if Game.has_flag("l2_front_open"):
		t = "Get out of the school. Make for St. Brendan's church — the east gate."
	elif Game.has_flag("l2_read_june"):
		t = "Leave through the front doors: unchain them from the inside."
	elif Game.has_flag("boiler_on"):
		t = "The boiler is running. Find June's trail — her homeroom, Classroom 2B."
	elif not Game.has_item("school_key") and not Game.has_flag("l2_side_open"):
		if Game.has_flag("open:l2_side"):
			t = "Restore the boiler: 60A fuse (shop), valve wheel (locker rooms)."
		else:
			t = "Find a way into the school. The front doors are chained — try the tool shed."
	elif Game.has_flag("l2_valve_on") and Game.has_flag("l2_fuse_in"):
		t = "At the boiler panel: PURGE, then IGNITE, then open the FEED valve."
	else:
		t = "Restore the boiler: 60A fuse (shop class), valve wheel (frozen in the locker room), then purge-ignite-feed."
	Game.set_objective(t)

func try_use_item(id: String) -> bool:
	var pp: Vector3 = player.global_position if player else Vector3.ZERO
	match id:
		"fuse_60a":
			if pp.y < -1.0 and pp.distance_to(PNL) < 4.0:
				_insert_fuse()
				return true
			UI.toast("The fuse belongs in the boiler's control panel.")
			return false
		"valve_handle":
			if pp.y < -1.0 and pp.distance_to(VLV) < 4.0:
				_mount_valve()
				return true
			UI.toast("It fits a valve stem. The boiler feed, maybe.")
			return false
		"school_key", "gym_key":
			UI.toast("Face a locked door and press interact — the key is used automatically.")
			return false
	return super.try_use_item(id)

func _build_breath() -> void:
	_breath = CPUParticles3D.new()
	_breath.amount = 7
	_breath.lifetime = 1.6
	_breath.one_shot = true
	_breath.explosiveness = 0.7
	_breath.emitting = false
	_breath.local_coords = false
	_breath.direction = Vector3(0, 0.2, 1.0)
	_breath.spread = 25.0
	_breath.initial_velocity_min = 0.2
	_breath.initial_velocity_max = 0.5
	_breath.gravity = Vector3(0, 0.1, 0)
	_breath.scale_amount_min = 0.012
	_breath.scale_amount_max = 0.035
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	_breath.mesh = sm
	var bm := Mats.color(Color(0.9, 0.93, 1.0, 0.22), 1.0)
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_breath.material_override = bm
	add_child(_breath)

func _build_indoor_fx() -> void:
	# dust-of-snow motes in the gym light and under the portico are covered by fog; add the finale trigger zone
	pass

# ====================================================================== FINALE
func _make_finale_trigger() -> void:
	trigger("l2_finale", Vector3(0, 1.2, -4.0), Vector3(9.0, 3.0, 2.0), func(_p): _foreman_scene())

func _foreman_scene() -> void:
	if Game.has_flag("met_foreman"):
		return
	_scene_running = true
	lock_player(true)
	Sfx.play("stinger_a")
	var H = load("res://actors/humanoid.gd")
	# the Foreman: tall, wrong-jointed, hard hat with its headlamp still burning
	var fm := Node3D.new()
	add_child(fm)
	fm.position = Vector3(-17.5, 0, 9.0)
	var hum: Node3D = H.new()
	hum.setup({"zombie": true, "height": 2.6, "bulk": 0.85, "shirt": Color(0.45, 0.28, 0.12), "pants": Color(0.18, 0.16, 0.14), "coat": true, "coat_color": Color(0.5, 0.32, 0.1), "skin": Color(0.62, 0.7, 0.74), "bloody": 0.6, "hair_style": "bald"})
	hum.pose = "zombie"
	fm.add_child(hum)
	var hard_hat := Props.sphere(hum.head, 0.14, Vector3(0, 0.15, 0), _m("hardhat", Color(0.85, 0.7, 0.1), 0.5), Vector3(1.0, 0.7, 1.1))
	var lamp_m := Props.sphere(hum.head, 0.045, Vector3(0, 0.17, 0.15), Mats.emissive(Color(1.0, 0.95, 0.8), 6.0))
	var beam := SpotLight3D.new()
	beam.light_color = Color(1.0, 0.95, 0.82)
	beam.light_energy = 9.0
	beam.spot_range = 34.0
	beam.spot_angle = 16.0
	beam.shadow_enabled = true
	beam.light_volumetric_fog_energy = 2.0
	beam.position = Vector3(0, 0.17, 0.15)
	hum.head.add_child(beam)
	# the caretaker (Walt), dragged by the ankle
	var cp := Node3D.new()
	add_child(cp)
	cp.position = Vector3(-20.5, 0.03, 10.6)
	var walt: Node3D = null
	var NPCS := "res://actors/npc.gd"
	var wh: Node3D = H.new()
	wh.setup({"shirt": Color(0.2, 0.28, 0.4), "pants": Color(0.2, 0.28, 0.4), "hair_style": "bald", "hair": Color(0.6, 0.6, 0.6), "height": 1.75, "bulk": 1.1})
	wh.pose = "dead"
	cp.add_child(wh)
	walt = cp
	cp.rotation.y = 1.0
	# camera turns toward the west side
	var pl := player
	var look_yaw := atan2(-17.5 - pl.global_position.x, -(9.0 - pl.global_position.z)) * 1.0
	# camera yaw 0 looks -Z; direction to the target:
	var dir := Vector3(-17.5, 0, 9.0) - pl.global_position
	var yaw := atan2(-dir.x, -dir.z)
	var tw := create_tween()
	tw.tween_property(pl, "cam_yaw", _near_angle(pl.cam_yaw, yaw), 1.4).set_trans(Tween.TRANS_SINE)
	await get_tree().create_timer(1.2).timeout
	# headlamp sweeps across the snow, then finds Elias
	var sw := create_tween()
	sw.tween_property(hum.head, "rotation:y", 0.9, 1.2)
	sw.tween_property(hum.head, "rotation:y", -0.8, 1.6)
	sw.tween_property(hum.head, "rotation:y", 0.0, 0.8)
	hum.move_speed = 0.0
	fm.rotation.y = atan2(pl.global_position.x - fm.position.x, pl.global_position.z - fm.position.z)
	Sfx.play("stinger_b")
	await get_tree().create_timer(1.6).timeout
	await say([
		["WALT", "Kade? Elias Kade?! Get out of here, kid — don't look at the light!"],
		["ELIAS", "Walt? Hold on, I'm —"],
	])
	Sfx.play("hurt_m")
	# dragging: Foreman walks backward-ish toward the collapsed wall, hauling Walt behind him
	hum.move_speed = 1.2
	fm.rotation.y = atan2(-26.0 - fm.position.x, 11.0 - fm.position.z)
	var drag := create_tween().set_parallel(true)
	drag.tween_property(fm, "position", Vector3(-29.0, 0, 11.0), 6.5).set_trans(Tween.TRANS_LINEAR)
	drag.tween_property(cp, "position", Vector3(-27.4, 0.03, 11.0), 6.5).set_trans(Tween.TRANS_LINEAR)
	var swing := create_tween()
	swing.tween_property(hum.head, "rotation:y", 2.4, 2.0)
	swing.tween_property(hum.head, "rotation:y", 0.0, 1.5)
	await get_tree().create_timer(2.4).timeout
	await say([["WALT", "He's got my — he's SAYING MY NAME — tell Ruth I kept the —"]])
	await get_tree().create_timer(2.8).timeout
	Sfx.play("glass_break")
	fm.queue_free()
	cp.queue_free()
	await get_tree().create_timer(1.2).timeout
	Game.set_flag("met_foreman")
	Sfx.music("music_tension", -13.0)
	Sfx.play("radio_squelch")
	await say([
		["JUNE (radio)", "Dad, I heard someone shouting on the open channel. Was that you? Are you okay?"],
		["ELIAS", "I'm okay. June — where are you?"],
		["JUNE (radio)", "Keep moving. Church first, Dad. The hum's loud, I can't stay on. I'll check in."],
		["ELIAS", "Gil Arsenault. He's been dead since... no. That was him."],
	])
	Game.set_objective("Take the east gate to St. Brendan's church. Something walks the town with a light.")
	lock_player(false)
	_scene_running = false

func _near_angle(from: float, to: float) -> float:
	return from + wrapf(to - from, -PI, PI)
