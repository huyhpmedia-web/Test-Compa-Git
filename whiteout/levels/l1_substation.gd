extends "res://levels/level.gd"
## L1 — HIGHWAY 53 / KETTLE FALLS SUBSTATION. Dec 21 2026, 22:14, -40 degrees.
## Critical path:
##   start (ditch, bucket truck) -> tutorial + June's first radio call -> walk Highway 53 north
##   -> cut fence at the co-op substation -> control_key from the operator's body by the transformers
##   -> Control House (safe room: SCADA + load-shed order) -> hot_stick (operator's pickup bed)
##   + fuse_60a (cabinet in the storage container, pried with the hatchet) -> switching sequence
##   DS-2A, DS-2B, BKR-KF2 -> feeder_closed -> the school lights up -> road gate opens -> l2_school:from_road
## Flags: l1_intro, l1_saw_order, l1_cabinet_open, l1_fuse_in, l1_ctrl_unlocked, feeder_closed, trig:l1_*

# switchgear state
var _sw := {}                     # id -> {pivot, label, closed, kind}
var _step := 0
var _fails := 0
var _busy := false
var _hint_given := false
# ambient FX
var _beacons: Array = []          # [OmniLight3D, StandardMaterial3D]
var _fires: Array = []            # world positions of burning barrels (repel the Rimebound)
var _fire_t := 0.0
var _arc_lights: Array = []
var _arc_tick := -1
var _arc_cd := 0.0
var _yard_lamps: Array = []       # [Light3D, StandardMaterial3D]
var _school_mats: Array = []
var _school_lights: Array = []
var _gate_lamp: StandardMaterial3D
var _gate_lamp_light: OmniLight3D
var _road_sleepers: Array = []
var _ambush = null
var _worker = null
var _ctrl_door_pos := Vector3(27.0, 0.0, -81.0)
var _breaker_pos := Vector3(38.0, 0.0, -66.0)
var _lamp_off := Color(0.12, 0.12, 0.13)

const YARD_X0 := 14.0
const YARD_X1 := 52.0
const YARD_Z0 := -100.0   # north fence
const YARD_Z1 := -58.0    # south fence

func build() -> void:
	env_exterior_night(true, 0.02, 0.42)
	add_spawn("start", Vector3(2.5, 0.1, 31.0), PI)
	_ground()
	_road()
	_bucket_truck()
	_roadside()
	_powerline()
	_roadside_shed()
	_substation_fences()
	_transformers_and_towers()
	_switchyard()
	_control_house()
	_storage_container()
	_operator_area()
	_downed_line()
	_exit_gate_and_school()
	_pines()
	_enemies()
	_items_and_notes()
	_triggers()

func on_enter() -> void:
	Sfx.music("music_tension", -12.0)
	if Game.has_flag("feeder_closed"):
		Game.objective = "Reach the school. Gran's shelter. Follow Highway 53 north."
		return
	if not Game.has_flag("l1_intro"):
		Game.set_flag("l1_intro")
		Game.set_objective("Get into Kettle Falls. Follow Highway 53 north on foot.")
		UI.title_card("HIGHWAY 53", "Kettle Falls, Minnesota  -  Dec 21, 2026  22:14  -  -40 degrees")
		await get_tree().create_timer(3.5).timeout
		UI.toast("WASD - move     SHIFT - sprint", 5.0)

func _process(delta: float) -> void:
	super._process(delta)
	# amber beacons on the truck: alternating double flash
	var ph := fmod(_t, 1.1)
	for i in _beacons.size():
		var b: Array = _beacons[i]
		var on: bool = (ph < 0.12) if i == 0 else (ph > 0.5 and ph < 0.62)
		(b[0] as OmniLight3D).light_energy = 4.0 if on else 0.0
		(b[1] as StandardMaterial3D).emission_energy_multiplier = 6.0 if on else 0.2
	# arc flash light at the downed conductor
	_arc_cd = max(0.0, _arc_cd - delta)
	var tick := int(_t * 16.0)
	if tick != _arc_tick:
		_arc_tick = tick
		for a in _arc_lights:
			var l: OmniLight3D = a
			l.light_energy = 0.0 if randf() < 0.35 else randf_range(2.5, 9.0)
	# burning barrels repel the Rimebound
	_fire_t += delta
	if _fire_t > 0.5:
		_fire_t = 0.0
		for e in get_tree().get_nodes_in_group("enemy"):
			if is_instance_valid(e) and e.has_method("fear"):
				for fp in _fires:
					if (e as Node3D).global_position.distance_to(fp) < 5.5:
						e.fear(fp, 2.5)

# =================================================================== small helpers
func _mat(c: Color, r := 0.7, m := 0.0) -> StandardMaterial3D:
	return Mats.color(c, r, m)

func _drift(p: Vector3, sx := 1.6, sy := 0.35, sz := 1.0, yaw := 0.0) -> void:
	var mi := Props.sphere(geo, 1.0, p, Mats.get_mat("snow"), Vector3(sx, sy, sz))
	mi.rotation.y = yaw

func _icicles(a: Vector3, b: Vector3, n: int, length := 0.35) -> void:
	var ice := Mats.get_mat("ice")
	for i in n:
		var t := (i + 0.5) / n
		var l := length * randf_range(0.5, 1.3)
		Props.cyl(geo, 0.025, l, a.lerp(b, t) + Vector3(0, -l * 0.5, 0), ice, false, 0.0, Vector3(PI, 0, 0), 5)

func _wire(a: Vector3, b: Vector3, sag := 0.6, segs := 6, radius := 0.012) -> void:
	var prev := a
	for i in range(1, segs + 1):
		var t := float(i) / segs
		var p := a.lerp(b, t)
		p.y -= sag * 4.0 * t * (1.0 - t)
		p.y = max(p.y, 0.08)
		Props.pipe(geo, prev, p, radius, "rubber")
		prev = p

func _insulator(top: Vector3, n := 4, horizontal := false) -> Vector3:
	var porc := _mat(Color(0.55, 0.45, 0.35), 0.3, 0.1)
	var p := top
	for i in n:
		Props.cyl(geo, 0.13, 0.05, p, porc, false, -1.0, Vector3.ZERO, 8)
		p += Vector3(0, -0.1, 0)
	return p

func _razor(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var len := d.length()
	var steel := _mat(Color(0.55, 0.57, 0.6), 0.35, 0.9)
	var mid := (a + b) * 0.5
	var yaw := atan2(d.x, d.z)
	var mi := Props.cyl(geo, 0.1, len, mid, steel, false, -1.0, Vector3.ZERO, 6)
	mi.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5)
	var n := int(len / 0.9)
	for i in n:
		var p := a + d * ((i + 0.5) / n)
		var r := Props.box(geo, Vector3(0.28, 0.02, 0.02), p, steel, false)
		r.rotation = Vector3(0, yaw, randf() * PI)

func _fence_run(a: Vector3, b: Vector3, razor := true) -> void:
	Props.fence(geo, a, b, 2.4, "metal")
	if razor:
		_razor(a + Vector3(0, 2.55, 0), b + Vector3(0, 2.55, 0))

func _barrel_fire(p: Vector3, shadows := false) -> void:
	Props.barrel(geo, p, 0.0, true)
	var fl := CPUParticles3D.new()
	fl.amount = 28
	fl.lifetime = 0.9
	fl.direction = Vector3.UP
	fl.spread = 12.0
	fl.initial_velocity_min = 0.8
	fl.initial_velocity_max = 1.8
	fl.gravity = Vector3(0, 1.2, 0)
	fl.scale_amount_min = 0.05
	fl.scale_amount_max = 0.16
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	fl.mesh = sm
	fl.material_override = Mats.emissive(Color(1.0, 0.45, 0.12), 5.0)
	fl.position = p + Vector3(0, 0.95, 0)
	add_child(fl)
	Props.cyl(geo, 0.26, 0.04, p + Vector3(0, 0.88, 0), Mats.emissive(Color(1.0, 0.4, 0.1), 3.0), false)
	light(p + Vector3(0, 1.5, 0), Color(1.0, 0.55, 0.2), 4.5, 12.0, shadows, true)
	_fires.append(p)

func _sparks(p: Vector3, amount := 30, one_shot := true) -> void:
	var s := CPUParticles3D.new()
	s.amount = amount
	s.lifetime = 0.7
	s.one_shot = one_shot
	s.explosiveness = 0.9 if one_shot else 0.2
	s.direction = Vector3.UP
	s.spread = 70.0
	s.initial_velocity_min = 2.0
	s.initial_velocity_max = 5.0
	s.gravity = Vector3(0, -9.0, 0)
	s.scale_amount_min = 0.02
	s.scale_amount_max = 0.05
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	s.mesh = sm
	s.material_override = Mats.emissive(Color(0.8, 0.9, 1.0), 8.0)
	s.position = p
	add_child(s)
	if one_shot:
		get_tree().create_timer(1.5).timeout.connect(s.queue_free)

# =================================================================== ground + road
func _ground() -> void:
	var sn := "snow"
	floor_rect(-90, -200, -10, 46, 0.0, sn)
	floor_rect(-10, -200, -4, 2, 0.0, sn)
	floor_rect(-10, 26, -4, 46, 0.0, sn)
	floor_rect(-4, -200, 90, 46, 0.0, sn)
	# the ditch: two sloped slabs forming a V between x=-4 and x=-10, z 2..26
	var ang := atan2(1.2, 3.0)
	var ln := sqrt(9.0 + 1.44)
	var th := 0.3
	var na := Vector3(-sin(ang), cos(ang), 0)
	Props.box(geo, Vector3(ln, th, 24.0), Vector3(-5.5, -0.6, 14.0) - na * th * 0.5, Mats.get_mat("snow"), true, Vector3(0, 0, ang))
	var nb := Vector3(sin(ang), cos(ang), 0)
	Props.box(geo, Vector3(ln, th, 24.0), Vector3(-8.5, -0.6, 14.0) - nb * th * 0.5, Mats.get_mat("snow"), true, Vector3(0, 0, -ang))
	box(Vector3(-7.0, -0.7, 1.8), Vector3(6.4, 1.4, 0.4), "snow")
	box(Vector3(-7.0, -0.7, 26.2), Vector3(6.4, 1.4, 0.4), "snow")
	# snow banks, drifts
	var rng := RandomNumberGenerator.new()
	rng.seed = 5301
	for i in 26:
		var x := rng.randf_range(-30.0, 30.0)
		if abs(x) < 5.5:
			x = 7.0 if x >= 0.0 else -7.0
		_drift(Vector3(x, 0.0, rng.randf_range(-130.0, 40.0)), rng.randf_range(1.5, 3.5), rng.randf_range(0.25, 0.55), rng.randf_range(1.2, 2.4), rng.randf() * PI)

func _road() -> void:
	var asph := Mats.get_mat("asphalt_snow")
	box(Vector3(0, 0.02, -78.0), Vector3(8.0, 0.04, 244.0), asph, false)
	var yel := _mat(Color(0.75, 0.6, 0.1), 0.6)
	var wht := _mat(Color(0.75, 0.75, 0.72), 0.6)
	var z := 44.0
	while z > -138.0:
		Props.box(geo, Vector3(0.14, 0.012, 2.6), Vector3(0, 0.045, z), yel, false)
		z -= 7.0
	box(Vector3(-3.6, 0.045, -78.0), Vector3(0.12, 0.012, 244.0), wht, false)
	box(Vector3(3.6, 0.045, -78.0), Vector3(0.12, 0.012, 244.0), wht, false)
	# snow drifts creeping over the asphalt
	for dz in [18.0, -2.0, -22.0, -41.0, -66.0, -90.0, -105.0, -118.0]:
		_drift(Vector3(randf_range(-3.0, 3.0), 0.0, dz), randf_range(2.0, 3.5), 0.18, 1.0, randf() * 0.6)

# =================================================================== bucket truck in the ditch
func _bucket_truck() -> void:
	var root := Node3D.new()
	root.position = Vector3(-5.9, -0.35, 14.0)
	root.rotation.y = -PI * 0.5
	geo.add_child(root)
	var t := Node3D.new()
	t.rotation.x = 0.36          # nose down
	root.add_child(t)
	var white := _mat(Color(0.86, 0.88, 0.88), 0.4, 0.1)
	var orange := _mat(Color(0.95, 0.42, 0.06), 0.5)
	var dark := _mat(Color(0.06, 0.06, 0.07), 0.6, 0.2)
	var glass := _mat(Color(0.03, 0.05, 0.07, 0.92), 0.05, 0.3)
	var frost := _mat(Color(0.85, 0.9, 0.95, 0.55), 0.4)
	var tire := Mats.get_mat("rubber")
	# chassis, hood, cab, utility body
	Props.box(t, Vector3(1.1, 0.4, 7.4), Vector3(0, 0.95, 0), dark)
	Props.box(t, Vector3(2.3, 0.95, 1.4), Vector3(0, 1.75, 3.7), white)       # hood
	Props.box(t, Vector3(2.4, 1.85, 1.9), Vector3(0, 2.2, 2.05), white)       # cab
	Props.box(t, Vector3(2.42, 0.78, 1.5), Vector3(0, 2.55, 2.05), glass, false)  # side windows
	Props.box(t, Vector3(2.0, 0.8, 0.06), Vector3(0, 2.55, 3.02), glass, false)   # windshield
	Props.box(t, Vector3(2.0, 0.78, 0.04), Vector3(0, 2.56, 3.06), frost, false)
	Props.box(t, Vector3(2.55, 1.35, 4.6), Vector3(0, 1.75, -1.65), white)    # utility body
	Props.box(t, Vector3(2.6, 0.24, 4.64), Vector3(0, 1.5, -1.65), orange, false)   # co-op stripe
	Props.box(t, Vector3(2.46, 0.2, 1.92), Vector3(0, 1.62, 2.05), orange, false)
	Props.box(t, Vector3(2.32, 0.2, 1.42), Vector3(0, 1.45, 3.7), orange, false)
	for i in 4:
		Props.box(t, Vector3(2.62, 0.9, 0.03), Vector3(0, 1.85, -3.4 + i * 1.15), dark, false)
	Props.box(t, Vector3(2.7, 0.12, 4.7), Vector3(0, 1.1, -1.65), _mat(Color(0.2, 0.2, 0.22), 0.5, 0.6), false)
	# snow on cab roof and body
	Props.box(t, Vector3(2.3, 0.12, 1.8), Vector3(0, 3.18, 2.05), Mats.get_mat("snow"), false)
	Props.box(t, Vector3(2.4, 0.14, 4.4), Vector3(0, 2.5, -1.65), Mats.get_mat("snow"), false)
	Props.sign(t, Vector3(1.28, 2.0, -1.6), PI * 0.5, "LAKESHORE ELECTRIC CO-OP", 22, Color(0.1, 0.1, 0.12), false)
	Props.sign(t, Vector3(-1.28, 2.0, -1.6), -PI * 0.5, "LAKESHORE ELECTRIC CO-OP", 22, Color(0.1, 0.1, 0.12), false)
	Props.sign(t, Vector3(1.22, 2.3, 2.0), PI * 0.5, "UNIT 14", 26, Color(0.1, 0.1, 0.12), false)
	# wheels
	for sx in [-1, 1]:
		for zz in [3.5, -2.1, -3.3]:
			Props.cyl(t, 0.56, 0.42, Vector3(sx * 1.2, 0.56, zz), tire, false, -1.0, Vector3(0, 0, PI * 0.5))
			Props.cyl(t, 0.3, 0.44, Vector3(sx * 1.2, 0.56, zz), _mat(Color(0.5, 0.5, 0.52), 0.4, 0.8), false, -1.0, Vector3(0, 0, PI * 0.5), 10)
	# aerial boom: pedestal, lower boom stowed forward over the cab, upper boom, bucket
	Props.cyl(t, 0.38, 0.8, Vector3(0, 2.9, -2.7), dark, false)
	Props.box(t, Vector3(0.5, 0.5, 4.3), Vector3(0, 3.55, -0.5), orange, false, Vector3(-0.26, 0, 0))
	Props.box(t, Vector3(0.36, 0.4, 3.4), Vector3(0, 4.15, 3.1), white, false, Vector3(-0.05, 0, 0))
	Props.pipe(t, Vector3(0.0, 2.95, -0.3), Vector3(0.0, 3.6, 0.8), 0.07, "metal")
	var bk := Vector3(0, 3.35, 4.9)
	Props.box(t, Vector3(1.0, 0.1, 1.0), bk + Vector3(0, -0.5, 0), white, false)
	for sx in [-1, 1]:
		Props.box(t, Vector3(0.06, 0.95, 1.0), bk + Vector3(sx * 0.5, 0.0, 0), white, false)
		Props.box(t, Vector3(1.0, 0.95, 0.06), bk + Vector3(0, 0.0, sx * 0.5), white, false)
	Props.box(t, Vector3(1.02, 0.14, 1.02), bk + Vector3(0, 0.45, 0), orange, false)
	Props.pipe(t, Vector3(0, 4.05, 4.3), bk + Vector3(0, 0.2, -0.45), 0.08, "metal")
	# amber roof beacons (flashing)
	for i in 2:
		var sx := -0.7 if i == 0 else 0.7
		Props.box(t, Vector3(0.5, 0.06, 0.3), Vector3(sx, 3.28, 1.7), dark, false)
		var am := Mats.emissive(Color(1.0, 0.6, 0.05), 0.2)
		Props.cyl(t, 0.14, 0.16, Vector3(sx, 3.4, 1.7), am, false, 0.1, Vector3.ZERO, 10)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.58, 0.1)
		l.omni_range = 12.0
		l.omni_attenuation = 1.2
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.light_volumetric_fog_energy = 3.0
		l.position = Vector3(sx, 3.7, 1.7)
		t.add_child(l)
		_beacons.append([l, am])
	# one surviving headlight, flickering, throws a cold wedge on the slope
	var hl := SpotLight3D.new()
	hl.light_color = Color(0.95, 0.92, 0.8)
	hl.light_energy = 3.0
	hl.spot_range = 9.0
	hl.spot_angle = 38.0
	hl.shadow_enabled = false
	hl.light_volumetric_fog_energy = 2.0
	hl.position = Vector3(0.8, 1.7, 4.4)
	hl.rotation = Vector3(-0.25, PI, 0)
	t.add_child(hl)
	_flicker.append([hl, 3.0, 1.7])
	Props.box(t, Vector3(0.3, 0.14, 0.04), Vector3(0.8, 1.7, 4.41), Mats.emissive(Color(1, 0.95, 0.8), 1.2), false)
	# a fine mess: open door, scattered gear, snow banked against the nose
	_drift(Vector3(-8.6, -0.7, 14.0), 2.2, 0.8, 2.6, 0.0)
	_drift(Vector3(-4.0, -0.1, 11.0), 1.8, 0.4, 1.0, 0.4)
	Props.crate(geo, Vector3(-3.3, -0.12, 17.4), 0.4, 0.5)
	Props.cyl(geo, 0.22, 0.4, Vector3(-3.0, 0.05, 16.4), _mat(Color(0.9, 0.4, 0.05), 0.5), false)   # traffic cone
	Props.cyl(geo, 0.2, 0.35, Vector3(-2.4, 0.05, 11.4), _mat(Color(0.9, 0.4, 0.05), 0.5), false, 0.04)
	Props.debris(geo, Vector3(-3.4, 0.0, 12.0), 0.0, 4, "metal")
	# long skid marks gouged down the road shoulder
	for i in 5:
		Props.box(geo, Vector3(0.25, 0.01, 9.0), Vector3(-3.0 - i * 0.3, 0.05, 22.0), _mat(Color(0.05, 0.05, 0.06), 0.9), false, Vector3(0, 0.05, 0))

# =================================================================== road dressing
func _frost_car(p: Vector3, yaw: float, col: Color, kind := "sedan") -> void:
	Props.car(geo, p, yaw, col, true, kind)
	var frost := _mat(Color(0.88, 0.92, 0.96, 0.62), 0.5)
	var r := Node3D.new()
	r.position = p
	r.rotation.y = yaw
	geo.add_child(r)
	if kind == "van":
		Props.box(r, Vector3(1.74, 0.85, 4.12), Vector3(0, 0.35 + 0.75 + 0.55, -0.25), frost, false)
	else:
		Props.box(r, Vector3(1.74, 0.43, 2.1), Vector3(0, 1.37, -0.2), frost, false)
	_drift(p + Basis(Vector3.UP, yaw) * Vector3(1.0, 0.0, 1.6), 1.3, 0.45, 0.8, yaw)
	_drift(p + Basis(Vector3.UP, yaw) * Vector3(-1.0, 0.0, -1.7), 1.2, 0.4, 0.8, yaw + 0.5)
	for sx in [-1, 1]:
		_icicles(p + Basis(Vector3.UP, yaw) * Vector3(sx * 0.93, 0.9, 2.2), p + Basis(Vector3.UP, yaw) * Vector3(sx * 0.93, 0.9, 1.0), 4, 0.25)

func _roadside() -> void:
	# family car, abandoned and frozen: belongings strewn, a Sleeper beside the driver's door
	var fp := Vector3(-1.9, 0.0, -9.0)
	_frost_car(fp, 0.28, Color(0.22, 0.3, 0.38))
	var fb := Basis(Vector3.UP, 0.28)
	Props.box(geo, Vector3(0.7, 0.28, 0.45), fp + fb * Vector3(0.9, 0.14, -3.3), _mat(Color(0.45, 0.1, 0.1), 0.7), false, Vector3(0, 0.5, 0))   # suitcase
	Props.box(geo, Vector3(0.6, 0.24, 0.4), fp + fb * Vector3(1.6, 0.12, -3.0), _mat(Color(0.2, 0.25, 0.4), 0.7), false, Vector3(0, -0.3, 0))
	Props.sphere(geo, 0.3, fp + fb * Vector3(-1.6, 0.2, -2.6), _mat(Color(0.18, 0.3, 0.2), 0.9), Vector3(1.6, 0.8, 0.9))   # duffel
	Props.box(geo, Vector3(0.5, 0.05, 1.1), fp + fb * Vector3(2.2, 0.05, -1.0), _mat(Color(0.75, 0.1, 0.1), 0.5), false, Vector3(0, 0.2, 0))   # child's sled
	Props.sphere(geo, 0.18, fp + fb * Vector3(-2.0, 0.17, -0.6), _mat(Color(0.55, 0.38, 0.22), 0.95))   # teddy bear
	Props.sphere(geo, 0.11, fp + fb * Vector3(-2.0, 0.4, -0.6), _mat(Color(0.55, 0.38, 0.22), 0.95))
	Props.cyl(geo, 0.07, 0.3, fp + fb * Vector3(-2.4, 0.15, -2.0), _mat(Color(0.7, 0.7, 0.75), 0.3, 0.8), false)   # thermos
	Props.papers(geo, fp + fb * Vector3(-2.4, 0.01, -3.0), 5)
	Props.blood_pool(geo, fp + fb * Vector3(-1.9, 0, 0.2), 0.9)
	# a second car, a van across the lane, a pickup half in the snow
	_frost_car(Vector3(2.6, 0.0, -33.0), -0.55, Color(0.55, 0.12, 0.1))
	_frost_car(Vector3(-2.4, 0.0, -52.0), 0.12, Color(0.75, 0.75, 0.72), "van")
	_frost_car(Vector3(6.5, 0.0, -102.0), 2.7, Color(0.15, 0.2, 0.15))
	_frost_car(Vector3(-2.6, 0.0, -122.0), -0.2, Color(0.3, 0.3, 0.33))
	# the sign
	var sp := Vector3(7.4, 0.0, -24.0)
	Props.cyl(geo, 0.07, 3.0, sp + Vector3(-1.6, 1.5, 0), Mats.get_mat("metal_painted"), true)
	Props.cyl(geo, 0.07, 3.0, sp + Vector3(1.6, 1.5, 0), Mats.get_mat("metal_painted"), true)
	Props.box(geo, Vector3(3.6, 1.6, 0.1), sp + Vector3(0, 2.3, 0), _mat(Color(0.05, 0.25, 0.14), 0.45, 0.2), true, Vector3(0, -0.15, 0))
	var sg := Node3D.new()
	sg.position = sp + Vector3(0, 2.3, 0.07)
	sg.rotation.y = -0.15
	geo.add_child(sg)
	Props.sign(sg, Vector3(0, 0.38, 0), 0.0, "KETTLE FALLS", 70, Color(0.95, 0.95, 0.9), false)
	Props.sign(sg, Vector3(0, -0.15, 0), 0.0, "pop. 1,204", 46, Color(0.9, 0.9, 0.85), false)
	Props.sign(sg, Vector3(0, -0.52, 0), 0.0, "Home of the Iron Range Miners", 20, Color(0.8, 0.8, 0.75), false)
	Props.box(geo, Vector3(3.8, 0.35, 0.5), sp + Vector3(0, 3.2, 0), Mats.get_mat("snow"), false, Vector3(0, -0.15, 0))
	_icicles(sp + Vector3(-1.7, 3.05, 0.1), sp + Vector3(1.7, 3.05, 0.1), 12, 0.4)
	_drift(sp + Vector3(0, 0, 0.6), 3.0, 0.55, 1.1)
	spot(sp + Vector3(2.2, 0.4, 4.0), sp + Vector3(0, 2.2, 0), Color(1.0, 0.85, 0.6), 3.0, 9.0, 32.0, false)   # a work lamp someone left on, fading
	# digital hazard board over the road (still has a trickle from its battery)
	var bp := Vector3(-5.2, 0.0, -2.0)
	Props.cyl(geo, 0.1, 3.2, bp + Vector3(0, 1.6, 0), Mats.get_mat("metal_painted"), true)
	Props.box(geo, Vector3(2.4, 1.1, 0.2), bp + Vector3(0, 3.4, 0), dark_panel(), true, Vector3(0, 0.25, 0))
	var bm := Node3D.new()
	bm.position = bp + Vector3(0, 3.4, 0.11)
	bm.rotation.y = 0.25
	geo.add_child(bm)
	Props.sign(bm, Vector3(0, 0.2, 0), 0.0, "EXTREME COLD", 44, Color(1.0, 0.65, 0.05), false)
	Props.sign(bm, Vector3(0, -0.22, 0), 0.0, "TRAVEL NOT ADVISED", 36, Color(1.0, 0.65, 0.05), false)
	light(bp + Vector3(0.3, 3.0, 1.2), Color(1.0, 0.6, 0.1), 1.2, 7.0, false, true)
	# spur sign
	var up := Vector3(5.0, 0.0, -56.0)
	Props.cyl(geo, 0.06, 2.4, up + Vector3(0, 1.2, 0), Mats.get_mat("metal_painted"), true)
	Props.box(geo, Vector3(2.0, 0.9, 0.06), up + Vector3(0, 2.2, 0), _mat(Color(0.9, 0.78, 0.1), 0.5), true, Vector3(0, 0.5, 0))
	var ub := Node3D.new()
	ub.position = up + Vector3(0, 2.2, 0)
	ub.rotation.y = 0.5
	geo.add_child(ub)
	Props.sign(ub, Vector3(0, 0.18, 0.05), 0.0, "LAKESHORE ELECTRIC CO-OP", 22, Color(0.08, 0.08, 0.08), false)
	Props.sign(ub, Vector3(0, -0.05, 0.05), 0.0, "KETTLE FALLS SUBSTATION", 22, Color(0.08, 0.08, 0.08), false)
	Props.sign(ub, Vector3(0, -0.27, 0.05), 0.0, "AUTHORIZED PERSONNEL ONLY", 15, Color(0.08, 0.08, 0.08), false)
	# a few roadside flares guttering out near the second car (atmosphere, light pool)
	light(Vector3(3.6, 0.5, -31.0), Color(1.0, 0.25, 0.1), 1.6, 6.0, false, true)
	Props.cyl(geo, 0.025, 0.28, Vector3(3.6, 0.08, -31.0), Mats.emissive(Color(1.0, 0.2, 0.1), 3.0), false, -1.0, Vector3(PI * 0.5, 0, 0.3), 6)

func dark_panel() -> StandardMaterial3D:
	return _mat(Color(0.04, 0.045, 0.05), 0.4, 0.3)

func _powerline() -> void:
	# dead wooden line along the west side of the highway; some spans have fallen
	var zs := [34.0, 10.0, -14.0, -38.0, -62.0, -86.0, -110.0, -132.0]
	var px := -13.0
	var pole_m := Mats.get_mat("bark", 1.0)
	var tops: Array = []
	for z in zs:
		Props.cyl(geo, 0.2, 10.0, Vector3(px, 5.0, z), pole_m, true, 0.16, Vector3.ZERO, 10)
		Props.box(geo, Vector3(0.14, 0.14, 3.0), Vector3(px, 9.2, z), pole_m, false)
		Props.box(geo, Vector3(0.1, 0.1, 2.2), Vector3(px, 8.3, z), pole_m, false)
		Props.cyl(geo, 0.32, 0.5, Vector3(px + 0.5, 7.4, z), _mat(Color(0.35, 0.37, 0.4), 0.5, 0.6), false)   # pole transformer pot
		var phases: Array = []
		for dz in [-1.3, 0.0, 1.3]:
			Props.cyl(geo, 0.05, 0.22, Vector3(px, 9.4, z + dz), _mat(Color(0.5, 0.42, 0.34), 0.3), false)
			phases.append(Vector3(px, 9.55, z + dz))
		tops.append(phases)
		_drift(Vector3(px, 0.0, z), 1.4, 0.4, 1.4)
	for i in tops.size() - 1:
		for k in 3:
			var a: Vector3 = tops[i][k]
			var b: Vector3 = tops[i + 1][k]
			var sag := 1.2
			if i == 4 and k == 1:
				sag = 9.0   # sagging all the way to the snow
			if i == 5 and k == 2:
				sag = 6.0
			_wire(a, b, sag, 7)
	# a snow-covered tree line behind the poles
	for i in 8:
		Props.tree(geo, Vector3(randf_range(-26.0, -17.0), 0.0, -10.0 - i * 16.0), randf_range(8.0, 11.0), 700 + i)

func _roadside_shed() -> void:
	# Highway dept. sand shed: optional side room (door faces the road)
	var sp := Vector3(14.5, 0.0, -42.0)
	Props.shed(geo, sp, -PI * 0.5, Vector3(3.6, 2.7, 4.0))
	Props.sign(geo, sp + Vector3(-2.3, 2.9, 0.0), -PI * 0.5, "MnDOT  SAND / SALT", 28, Color(0.9, 0.8, 0.2), true)
	# interior
	Props.shelf(geo, sp + Vector3(1.6, 0.0, 0.2), -PI * 0.5, 1.6, 2.0, false)
	Props.crate(geo, sp + Vector3(0.9, 0.0, 1.5), 0.3, 0.7)
	Props.crate(geo, sp + Vector3(0.8, 0.0, -1.5), 0.0, 0.8)
	Props.trash_bags(geo, sp + Vector3(0.5, 0.0, 1.0), 0.0, 2)
	Props.cyl(geo, 0.28, 0.9, sp + Vector3(0.2, 0.45, -1.7), Mats.get_mat("metal_rust"), true)
	_drift(sp + Vector3(-2.2, 0.0, 0.0), 1.4, 0.4, 1.8)
	# sand pile
	Props.sphere(geo, 1.2, sp + Vector3(-0.2, 0.0, 1.0), Mats.get_mat("dirt"), Vector3(1.4, 0.7, 1.2))
	light(sp + Vector3(0.8, 2.0, 0.0), Color(1.0, 0.75, 0.45), 1.6, 5.0, false, true)
	# its roof is snowed deep
	Props.box(geo, Vector3(4.2, 0.18, 4.6), sp + Vector3(0, 3.0, 0), Mats.get_mat("snow"), false)
	_icicles(sp + Vector3(-2.0, 2.6, -1.8), sp + Vector3(-2.0, 2.6, 1.8), 10, 0.5)

# =================================================================== substation yard
func _substation_fences() -> void:
	var x0 := YARD_X0
	var x1 := YARD_X1
	var z0 := YARD_Z0
	var z1 := YARD_Z1
	# yard surface: frozen gravel
	floor_rect(x0, z0, x1, z1, 0.03, "rock", 0.3)
	# perimeter: south, east, north, west (with locked gate and a torn gap)
	_fence_run(Vector3(x0, 0, z1), Vector3(x1, 0, z1))
	_fence_run(Vector3(x1, 0, z1), Vector3(x1, 0, z0))
	_fence_run(Vector3(x1, 0, z0), Vector3(x0, 0, z0))
	_fence_run(Vector3(x0, 0, z0), Vector3(x0, 0, -71.6))
	_fence_run(Vector3(x0, 0, -68.6), Vector3(x0, 0, -63.4))
	_fence_run(Vector3(x0, 0, -60.6), Vector3(x0, 0, z1))
	# torn flap where the fence was cut, bent outward
	Props.box(geo, Vector3(0.03, 2.1, 1.7), Vector3(x0 - 0.5, 0.95, -69.1), _mat(Color(0.4, 0.42, 0.44, 0.55), 0.5, 0.8), false, Vector3(0.6, 0.0, 0.7))
	Props.cyl(geo, 0.04, 2.4, Vector3(x0, 1.2, -68.6), Mats.get_mat("metal"), false)
	Props.cyl(geo, 0.04, 2.4, Vector3(x0, 1.2, -71.6), Mats.get_mat("metal"), false)
	Props.cyl(geo, 0.04, 2.4, Vector3(x0 - 0.3, 1.1, -71.6), Mats.get_mat("metal"), false, -1.0, Vector3(0.0, 0.0, 0.25))
	# the main gate: chained
	var gm := Mats.get_mat("metal_painted")
	for sz in [-60.6, -63.4]:
		Props.box(geo, Vector3(0.25, 3.0, 0.25), Vector3(x0, 1.5, sz), gm, true)
	Props.box(geo, Vector3(0.05, 2.2, 1.35), Vector3(x0, 1.15, -61.3), _mat(Color(0.4, 0.42, 0.44, 0.55), 0.5, 0.8), true)
	Props.box(geo, Vector3(0.05, 2.2, 1.35), Vector3(x0, 1.15, -62.7), _mat(Color(0.4, 0.42, 0.44, 0.55), 0.5, 0.8), true)
	Props.box(geo, Vector3(0.1, 0.1, 1.5), Vector3(x0 - 0.1, 1.1, -62.0), _mat(Color(0.5, 0.5, 0.5), 0.3, 0.9), false)
	Props.box(geo, Vector3(0.1, 0.16, 0.12), Vector3(x0 - 0.13, 0.95, -62.0), _mat(Color(0.6, 0.5, 0.15), 0.3, 0.9), false)
	_razor(Vector3(x0, 2.55, -63.4), Vector3(x0, 2.55, -60.6))
	Props.sign(geo, Vector3(x0 - 0.2, 2.0, -64.2), -PI * 0.5, "DANGER  HIGH VOLTAGE", 26, Color(0.95, 0.2, 0.1), true)
	Props.sign(geo, Vector3(x0 - 0.2, 1.55, -64.2), -PI * 0.5, "KEEP OUT", 30, Color(0.95, 0.95, 0.9), true)
	interact(Vector3(x0 - 0.6, 1.0, -62.0), "Check gate", _gate_check, 1.8)
	# snow banked on the fence, razor wire ice
	for z in [-96.0, -88.0, -80.0, -74.0, -66.0]:
		_drift(Vector3(x0 - 0.6, 0.0, z), 0.9, 0.7, 2.2)
	for x in [20.0, 30.0, 40.0, 48.0]:
		_drift(Vector3(x, 0.0, z1 + 0.7), 2.0, 0.55, 0.8)
	# yard floodlights: dead until the feeder is closed
	for fp in [Vector3(23.0, 0.0, -66.5), Vector3(46.0, 0.0, -84.0), Vector3(30.0, 0.0, -89.0)]:
		_floodlight(fp)
	# entry light on the control house wall
	# fire barrel at the gap (it repels them and shows the way)
	_barrel_fire(Vector3(18.5, 0.03, -69.5), true)

func _gate_check(_p) -> void:
	UI.toast("Chained and padlocked. The fence is cut open further north.")
	Sfx.play("door_locked")

func _floodlight(p: Vector3) -> void:
	Props.cyl(geo, 0.1, 6.5, p + Vector3(0, 3.25, 0), Mats.get_mat("metal_painted"), true, 0.07)
	Props.box(geo, Vector3(0.9, 0.12, 0.4), p + Vector3(0, 6.5, 0), Mats.get_mat("metal_painted"), false)
	var lm := _mat(_lamp_off, 0.3)
	lm.emission_enabled = true
	lm.emission = Color(1.0, 0.88, 0.62)
	lm.emission_energy_multiplier = 0.0
	Props.box(geo, Vector3(0.8, 0.08, 0.3), p + Vector3(0, 6.38, 0.0), lm, false)
	var l := SpotLight3D.new()
	l.light_color = Color(1.0, 0.85, 0.6)
	l.light_energy = 7.0
	l.spot_range = 20.0
	l.spot_angle = 60.0
	l.shadow_enabled = false
	l.light_volumetric_fog_energy = 1.5
	l.position = p + Vector3(0, 6.3, 0)
	l.rotation = Vector3(-PI * 0.5, 0, 0)
	l.visible = Game.has_flag("feeder_closed")
	add_child(l)
	if Game.has_flag("feeder_closed"):
		lm.emission_energy_multiplier = 4.0
	_yard_lamps.append([l, lm])

func _transformer(p: Vector3, yaw := 0.0, label := "T1") -> void:
	var r := Node3D.new()
	r.position = p
	r.rotation.y = yaw
	geo.add_child(r)
	var grey := _mat(Color(0.38, 0.4, 0.42), 0.55, 0.45)
	var grey2 := _mat(Color(0.3, 0.32, 0.34), 0.6, 0.4)
	var porc := _mat(Color(0.5, 0.42, 0.34), 0.28, 0.1)
	Props.box(r, Vector3(4.0, 0.45, 2.8), Vector3(0, 0.22, 0), Mats.get_mat("concrete"), true)
	Props.box(r, Vector3(3.2, 2.5, 2.0), Vector3(0, 1.7, 0), grey, true)                  # tank
	Props.box(r, Vector3(3.3, 0.12, 2.1), Vector3(0, 3.0, 0), grey2, false)               # lid
	Props.box(r, Vector3(3.1, 0.14, 1.9), Vector3(0, 3.1, 0), Mats.get_mat("snow"), false)
	for sz in [-1, 1]:
		for i in 10:
			Props.box(r, Vector3(0.07, 2.2, 0.55), Vector3(-1.4 + i * 0.31, 1.6, sz * 1.35), grey2, false)
		Props.pipe(r, Vector3(-1.6, 2.7, sz * 1.0), Vector3(-1.6, 2.7, sz * 1.5), 0.08, "metal")
		Props.pipe(r, Vector3(1.6, 0.8, sz * 1.0), Vector3(1.6, 0.8, sz * 1.5), 0.08, "metal")
	# conservator (oil expansion tank) on posts
	Props.cyl(r, 0.42, 3.0, Vector3(0, 3.75, -0.7), grey, false, -1.0, Vector3(0, 0, PI * 0.5), 14)
	Props.box(r, Vector3(0.12, 0.5, 0.12), Vector3(-1.2, 3.35, -0.7), grey2, false)
	Props.box(r, Vector3(0.12, 0.5, 0.12), Vector3(1.2, 3.35, -0.7), grey2, false)
	# HV bushings: stacked porcelain with rain sheds, brass cap
	for i in 3:
		var bx := -1.0 + i * 1.0
		Props.cyl(r, 0.17, 0.3, Vector3(bx, 3.3, 0.35), grey2, false)
		for k in 6:
			Props.cyl(r, 0.11, 0.2, Vector3(bx, 3.55 + k * 0.2, 0.35), porc, false, -1.0, Vector3.ZERO, 10)
			Props.cyl(r, 0.22 - k * 0.012, 0.035, Vector3(bx, 3.6 + k * 0.2, 0.35), porc, false, -1.0, Vector3.ZERO, 12)
		Props.cyl(r, 0.07, 0.18, Vector3(bx, 4.85, 0.35), Mats.get_mat("metal"), false)
	# LV bushings on the side
	for i in 4:
		Props.cyl(r, 0.06, 0.55, Vector3(1.9, 2.3 + i * 0.0, -0.9 + i * 0.6), porc, false, -1.0, Vector3(0, 0, PI * 0.5), 8)
	# warning plates, nameplate
	Props.sign(r, Vector3(0, 1.8, 1.02), 0.0, "DANGER  HIGH VOLTAGE", 24, Color(0.95, 0.15, 0.08), true)
	Props.sign(r, Vector3(0, 1.3, 1.02), 0.0, "KETTLE FALLS  " + label + "   69/12.47 kV", 18, Color(0.85, 0.85, 0.8), false)
	_icicles(r.position + Vector3(-1.5, 3.0, 1.05), r.position + Vector3(1.5, 3.0, 1.05), 9, 0.5)
	# oil stain + frost around the base
	Props.box(r, Vector3(3.6, 0.01, 2.4), Vector3(0, 0.46, 0), _mat(Color(0.8, 0.86, 0.92, 0.6), 0.5), false)

func _lattice(p: Vector3, h := 12.0, w := 2.4) -> float:
	## Steel lattice gantry tower. Returns the wire attachment height.
	var m := _mat(Color(0.5, 0.53, 0.56), 0.55, 0.65)
	var hw := w * 0.5
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			Props.box(geo, Vector3(0.14, h, 0.14), p + Vector3(sx * hw, h * 0.5, sz * hw), m, true)
	var panels := 4
	var ph := h / panels
	for i in panels:
		var y0 := p.y + i * ph
		var y1 := y0 + ph
		for f in 4:
			var a0: Vector3
			var a1: Vector3
			var b0: Vector3
			var b1: Vector3
			match f:
				0:
					a0 = Vector3(-hw, y0, hw); a1 = Vector3(hw, y1, hw); b0 = Vector3(hw, y0, hw); b1 = Vector3(-hw, y1, hw)
				1:
					a0 = Vector3(-hw, y0, -hw); a1 = Vector3(hw, y1, -hw); b0 = Vector3(hw, y0, -hw); b1 = Vector3(-hw, y1, -hw)
				2:
					a0 = Vector3(hw, y0, -hw); a1 = Vector3(hw, y1, hw); b0 = Vector3(hw, y0, hw); b1 = Vector3(hw, y1, -hw)
				_:
					a0 = Vector3(-hw, y0, -hw); a1 = Vector3(-hw, y1, hw); b0 = Vector3(-hw, y0, hw); b1 = Vector3(-hw, y1, -hw)
			Props.pipe(geo, Vector3(p.x, 0, p.z) + a0, Vector3(p.x, 0, p.z) + a1, 0.035, "metal")
			Props.pipe(geo, Vector3(p.x, 0, p.z) + b0, Vector3(p.x, 0, p.z) + b1, 0.035, "metal")
		# horizontal rings
		Props.box(geo, Vector3(w, 0.08, 0.08), p + Vector3(0, y1 - p.y, hw), m, false)
		Props.box(geo, Vector3(w, 0.08, 0.08), p + Vector3(0, y1 - p.y, -hw), m, false)
		Props.box(geo, Vector3(0.08, 0.08, w), p + Vector3(hw, y1 - p.y, 0), m, false)
		Props.box(geo, Vector3(0.08, 0.08, w), p + Vector3(-hw, y1 - p.y, 0), m, false)
	# crossarm along z and hanging insulator strings
	Props.box(geo, Vector3(0.22, 0.26, 7.2), p + Vector3(0, h + 0.1, 0), m, false)
	Props.box(geo, Vector3(0.3, 0.1, 6.8), p + Vector3(0, h + 0.28, 0), Mats.get_mat("snow"), false)
	for dz in [-3.0, 0.0, 3.0]:
		_insulator(p + Vector3(0, h - 0.1, dz), 5)
	_icicles(p + Vector3(0, h - 0.05, -3.4), p + Vector3(0, h - 0.05, 3.4), 10, 0.45)
	return h - 0.7

func _transformers_and_towers() -> void:
	var tz := -95.0
	var xs := [32.0, 41.0, 50.0]
	var names := ["T1", "T2", "T3"]
	for i in 3:
		_transformer(Vector3(xs[i], 0.03, tz), 0.0, names[i])
	# towers and conductors
	var tops: Array = []
	for i in 3:
		var hh := _lattice(Vector3(xs[i], 0.03, -78.0), 12.0)
		tops.append(hh)
	for dz in [-3.0, 0.0, 3.0]:
		for i in 2:
			_wire(Vector3(xs[i], tops[i], -78.0 + dz), Vector3(xs[i + 1], tops[i + 1], -78.0 + dz), 1.2, 7)
	for i in 3:
		_wire(Vector3(xs[i], tops[i], -78.0), Vector3(xs[i], 4.9, tz + 0.35), 2.0, 7)
	# the dead conductors drooping off the west end of the gantry
	_wire(Vector3(xs[0], tops[0], -75.0), Vector3(YARD_X0 + 1.0, 0.1, -76.0), 3.5, 8)
	# cold light pooled at the transformer bank (a dropped work lantern)
	Props.cyl(geo, 0.1, 0.28, Vector3(36.4, 0.17, -90.2), Mats.emissive(Color(0.85, 0.95, 1.0), 2.5), false, 0.08)
	light(Vector3(36.4, 0.7, -90.2), Color(0.7, 0.85, 1.0), 2.2, 7.0, true, false)
	_drift(Vector3(36.0, 0.0, -98.5), 3.0, 0.6, 1.0)

# =================================================================== switchyard
func _disconnect(id: String, title: String, p: Vector3, warn := false) -> void:
	var porc := _mat(Color(0.52, 0.44, 0.35), 0.3, 0.1)
	var steel := _mat(Color(0.62, 0.64, 0.67), 0.35, 0.9)
	Props.box(geo, Vector3(3.4, 0.3, 1.4), p + Vector3(0, 0.15, 0), Mats.get_mat("concrete"), true)
	Props.box(geo, Vector3(3.2, 0.12, 0.14), p + Vector3(0, 0.36, 0), steel, false)
	var xa := -1.1
	var xb := 1.1
	for xx in [xa, xb]:
		for k in 5:
			Props.cyl(geo, 0.13, 0.34, p + Vector3(xx, 0.5 + k * 0.34, 0), porc, false, -1.0, Vector3.ZERO, 10)
			Props.cyl(geo, 0.21, 0.04, p + Vector3(xx, 0.62 + k * 0.34, 0), porc, false, -1.0, Vector3.ZERO, 12)
		Props.box(geo, Vector3(0.3, 0.1, 0.3), p + Vector3(xx, 2.25, 0), steel, false)
	var pivot := Node3D.new()
	pivot.position = p + Vector3(xa, 2.32, 0)
	geo.add_child(pivot)
	Props.box(pivot, Vector3(2.2, 0.09, 0.12), Vector3(1.1, 0, 0), steel, false)
	Props.box(pivot, Vector3(0.14, 0.2, 0.2), Vector3(0.0, 0, 0), steel, false)
	# operating shaft + handle
	Props.pipe(geo, p + Vector3(0, 0.4, 0.5), p + Vector3(0, 1.7, 0.5), 0.045, "metal")
	Props.box(geo, Vector3(0.5, 0.06, 0.06), p + Vector3(0.0, 1.7, 0.5), _mat(Color(0.9, 0.7, 0.1), 0.5), false)
	var plate := Node3D.new()
	plate.position = p + Vector3(0, 2.95, 0.2)
	geo.add_child(plate)
	Props.box(plate, Vector3(2.0, 0.7, 0.05), Vector3.ZERO, _mat(Color(0.9, 0.78, 0.1) if warn else Color(0.1, 0.12, 0.14), 0.5), false)
	var tl := Label3D.new()
	tl.text = title
	tl.font_size = 40
	tl.pixel_size = 0.0045
	tl.modulate = Color(0.08, 0.08, 0.08) if warn else Color(0.9, 0.92, 0.85)
	tl.position = Vector3(0, 0.12, 0.03)
	plate.add_child(tl)
	var st := Label3D.new()
	st.text = "OPEN"
	st.font_size = 34
	st.pixel_size = 0.004
	st.modulate = Color(0.3, 1.0, 0.45)
	st.position = Vector3(0, -0.17, 0.03)
	plate.add_child(st)
	_sw[id] = {"pivot": pivot, "label": st, "closed": false, "kind": "ds", "open_rot": 1.2}
	if Game.has_flag("feeder_closed") and id != "DS2C":
		_sw[id].closed = true
		pivot.rotation.z = 0.0
		st.text = "CLOSED"
		st.modulate = Color(1.0, 0.35, 0.25)
	else:
		pivot.rotation.z = 1.2
	interact(p + Vector3(0, 1.0, 1.5), "Operate %s (hot stick)" % title, func(_pl): _operate(id), 2.0)
	_icicles(p + Vector3(xa, 2.2, 0), p + Vector3(xb, 2.2, 0), 6, 0.3)

func _breaker(p: Vector3) -> void:
	var grey := _mat(Color(0.4, 0.43, 0.45), 0.5, 0.5)
	var porc := _mat(Color(0.52, 0.44, 0.35), 0.3, 0.1)
	var steel := _mat(Color(0.62, 0.64, 0.67), 0.35, 0.9)
	Props.box(geo, Vector3(5.4, 0.3, 2.0), p + Vector3(0, 0.15, 0), Mats.get_mat("concrete"), true)
	Props.box(geo, Vector3(2.6, 1.2, 1.2), p + Vector3(0, 1.05, 0), grey, true)
	Props.box(geo, Vector3(2.7, 0.1, 1.3), p + Vector3(0, 1.7, 0), Mats.get_mat("snow"), false)
	for i in 3:
		var bx := -0.9 + i * 0.9
		Props.cyl(geo, 0.14, 0.3, p + Vector3(bx, 1.9, 0), grey, false)
		for k in 4:
			Props.cyl(geo, 0.1, 0.2, p + Vector3(bx, 2.15 + k * 0.2, 0), porc, false, -1.0, Vector3.ZERO, 10)
			Props.cyl(geo, 0.19, 0.035, p + Vector3(bx, 2.2 + k * 0.2, 0), porc, false, -1.0, Vector3.ZERO, 12)
	# control cabinet on the right
	var cab := p + Vector3(2.0, 0.0, 0.0)
	Props.box(geo, Vector3(0.9, 1.8, 0.6), cab + Vector3(0, 1.1, 0), _mat(Color(0.5, 0.52, 0.5), 0.5, 0.4), true)
	Props.box(geo, Vector3(0.75, 1.6, 0.04), cab + Vector3(0, 1.1, 0.32), _mat(Color(0.42, 0.44, 0.42), 0.5, 0.4), false)
	Props.sign(geo, cab + Vector3(0, 1.75, 0.36), 0.0, "BKR-KF2 CONTROL", 20, Color(0.1, 0.1, 0.1), false)
	var plate := Node3D.new()
	plate.position = p + Vector3(0, 3.2, 0.2)
	geo.add_child(plate)
	Props.box(plate, Vector3(2.3, 0.7, 0.05), Vector3.ZERO, _mat(Color(0.1, 0.12, 0.14), 0.5), false)
	var tl := Label3D.new()
	tl.text = "BKR-KF2  FEEDER BREAKER"
	tl.font_size = 34
	tl.pixel_size = 0.0045
	tl.modulate = Color(0.9, 0.92, 0.85)
	tl.position = Vector3(0, 0.12, 0.03)
	plate.add_child(tl)
	var st := Label3D.new()
	st.text = "OPEN"
	st.font_size = 34
	st.pixel_size = 0.004
	st.modulate = Color(0.3, 1.0, 0.45)
	st.position = Vector3(0, -0.17, 0.03)
	plate.add_child(st)
	var flag := Node3D.new()
	flag.position = p + Vector3(0, 1.1, 0.62)
	geo.add_child(flag)
	Props.box(flag, Vector3(0.6, 0.18, 0.06), Vector3(0, 0, 0), _mat(Color(0.2, 0.9, 0.35), 0.5), false)
	_sw["BKR"] = {"pivot": flag, "label": st, "closed": false, "kind": "bkr", "open_rot": 0.0}
	if Game.has_flag("feeder_closed"):
		_sw["BKR"].closed = true
		st.text = "CLOSED"
		st.modulate = Color(1.0, 0.35, 0.25)
	# cabinet: fuse block
	interact(cab + Vector3(0, 1.0, 1.1), "Control cabinet: fuse block", func(_pl): _fuse_block(), 1.6)
	interact(p + Vector3(-0.3, 1.0, 1.5), "Operate BKR-KF2", func(_pl): _operate("BKR"), 1.8)
	Props.sign(geo, p + Vector3(0, 0.55, 0.62), 0.0, "OPEN  TRIP  CLOSE", 16, Color(0.9, 0.9, 0.85), false)

func _fuse_block() -> void:
	if Game.has_flag("feeder_closed"):
		UI.toast("The breaker control circuit is live.")
		return
	if Game.has_flag("l1_fuse_in"):
		UI.toast("Fuse block: 60A installed. Control power is up.")
		return
	if Game.has_item("fuse_60a"):
		Game.remove_item("fuse_60a", 1)
		Game.set_flag("l1_fuse_in")
		Sfx.play("unlock")
		UI.toast("Installed the 60A fuse. The breaker's control circuit is alive.")
	else:
		UI.toast("The control fuse block is empty. Needs a 60A cartridge fuse.")
		Sfx.play("deny")

func _switchyard() -> void:
	var z := -66.0
	_disconnect("DS2A", "DS-2A  BUS ISOLATOR", Vector3(31.0, 0.03, z))
	_breaker(Vector3(38.5, 0.03, z))
	_disconnect("DS2B", "DS-2B  LINE ISOLATOR", Vector3(46.5, 0.03, z))
	_disconnect("DS2C", "DS-2C  BYPASS - MAINT ONLY", Vector3(50.0, 0.03, -72.0), true)
	# bus work between them
	_wire(Vector3(31.0, 2.45, z), Vector3(37.6, 2.5, z), 0.4, 5, 0.03)
	_wire(Vector3(39.4, 2.5, z), Vector3(45.4, 2.45, z), 0.4, 5, 0.03)
	_wire(Vector3(32.2, 2.45, z), Vector3(32.2, 11.3, -78.0), 1.0, 6)
	_wire(Vector3(47.7, 2.45, z), Vector3(50.0, 11.3, -78.0), 1.0, 6)
	# yellow lock-out sign
	Props.sign(geo, Vector3(24.5, 1.5, -61.0), 0.0, "KF-2 BAY  -  FOLLOW THE SWITCHING ORDER", 22, Color(0.1, 0.1, 0.1), true)
	Props.box(geo, Vector3(5.0, 0.7, 0.05), Vector3(24.5, 1.5, -61.05), _mat(Color(0.9, 0.78, 0.1), 0.5), false)
	# blue lantern and a second barrel for light on the bay
	_barrel_fire(Vector3(34.5, 0.03, -62.0), false)
	_drift(Vector3(40.0, 0.03, -63.0), 2.5, 0.45, 1.0)

# =================================================================== control house (safe room)
func _control_house() -> void:
	var x0 := 17.0
	var z0 := -86.0
	var x1 := 27.0
	var z1 := -76.0
	var h := 3.0
	# door in east wall (x=27) at z=-81: dist from z0 = 5.0
	room(x0, z0, x1, z1, h, "concrete", "brick", "metal_painted", {"e": [[5.0, 1.5, 2.4]]})
	# snow cap and eaves
	box(Vector3(22.0, h + 0.5, -81.0), Vector3(10.8, 0.5, 10.8), "snow", false)
	box(Vector3(22.0, h + 0.28, -81.0), Vector3(10.6, 0.1, 10.6), "metal", false)
	_icicles(Vector3(x0, h, z1 + 0.1), Vector3(x1, h, z1 + 0.1), 14, 0.6)
	_icicles(Vector3(x1 + 0.1, h, z0), Vector3(x1 + 0.1, h, z1), 14, 0.6)
	_drift(Vector3(x1 + 1.2, 0.0, -78.0), 1.2, 0.5, 1.8)
	_drift(Vector3(x0 + 3.0, 0.0, z1 + 0.8), 2.0, 0.45, 0.7)
	# door
	door("l1_ctrl_door", _ctrl_door_pos, PI * 0.5, {"width": 1.3, "height": 2.3, "mat": "metal", "lock_item": "control_key",
		"locked_msg": "Locked. Brass key tag: KF SUBSTATION - CONTROL HOUSE.", "prompt": "Open control house"})
	Props.sign(geo, Vector3(x1 + 0.15, 2.7, -81.0), PI * 0.5, "CONTROL HOUSE", 26, Color(0.9, 0.9, 0.85), true)
	Props.sign(geo, Vector3(x1 + 0.15, 2.3, -83.0), PI * 0.5, "NO ENTRY - HV", 16, Color(0.95, 0.2, 0.1), true)
	# lit window facing the spur: the warm heater glow
	Props.window(geo, Vector3(22.0, 1.8, z1 + 0.14), 0.0, 1.6, 1.0, true)
	Props.window(geo, Vector3(x0 - 0.14, 1.8, -81.0), -PI * 0.5, 1.6, 1.0, false)
	# interior ----------------------------------------------------------------
	# SCADA wall + desk
	Props.desk(geo, Vector3(21.0, 0.0, -85.0), 0.0)
	Props.chair(geo, Vector3(21.2, 0.0, -83.9), 2.8, true)
	box(Vector3(24.2, 1.7, -85.82), Vector3(3.2, 1.3, 0.1), "metal_painted", false)
	var scr := Props.box(geo, Vector3(3.0, 1.1, 0.03), Vector3(24.2, 1.7, -85.74), Mats.emissive(Color(0.1, 0.35, 0.28), 1.5), false)
	var sl := Label3D.new()
	sl.text = "KETTLE FALLS SUB  -  SCADA  (UPS)\nBUS 1   69 kV   DEAD\nFDR KF-1  OPEN   LOAD SHED\nFDR KF-2  OPEN   LOAD SHED\nFDR KF-3  CLOSED  PRIORITY (MERIDIAN)\nORDER 0417 ACTIVE - DO NOT RESTORE"
	sl.font_size = 22
	sl.pixel_size = 0.0045
	sl.modulate = Color(0.45, 1.0, 0.75)
	sl.shaded = false
	sl.position = Vector3(24.2, 1.7, -85.71)
	add_child(sl)
	light(Vector3(24.2, 1.7, -84.8), Color(0.35, 1.0, 0.8), 1.2, 4.5, false, true)
	# printer + load-shed order, switching order on a clipboard
	Props.box(geo, Vector3(0.5, 0.25, 0.4), Vector3(26.2, 1.05, -85.4), _mat(Color(0.8, 0.8, 0.75), 0.6), true)
	Props.table(geo, Vector3(26.2, 0.0, -85.4), 0.0, Vector2(0.8, 0.6))
	# heater and warm light
	Props.box(geo, Vector3(0.5, 0.9, 0.35), Vector3(18.3, 0.45, -84.7), _mat(Color(0.5, 0.15, 0.1), 0.5, 0.4), true)
	Props.box(geo, Vector3(0.38, 0.5, 0.04), Vector3(18.3, 0.5, -84.5), Mats.emissive(Color(1.0, 0.4, 0.1), 3.0), false)
	light(Vector3(18.5, 0.9, -83.6), Color(1.0, 0.5, 0.2), 3.0, 9.0, true, true)
	# desk lamp: warm pool for reading
	light(Vector3(21.0, 1.35, -84.3), Color(1.0, 0.82, 0.55), 1.4, 5.0, false, false)
	# field radio (save), supply crate, lockers, cot
	Props.table(geo, Vector3(18.4, 0.0, -80.5), PI * 0.5, Vector2(1.4, 0.7))
	save_point(Vector3(18.4, 0.78, -80.5), PI * 0.5)
	item_box(Vector3(23.0, 0.0, -76.7), PI)
	Props.locker(geo, Vector3(17.5, 0.0, -78.4), PI * 0.5, 2)
	Props.bed(geo, Vector3(25.6, 0.0, -77.6), PI * 0.5)
	Props.shelf(geo, Vector3(26.5, 0.0, -83.2), -PI * 0.5, 1.6, 2.0, false)
	Props.crate(geo, Vector3(19.0, 0.0, -77.0), 0.2, 0.6)
	# bulletin board + wall map
	Props.box(geo, Vector3(0.05, 1.0, 1.8), Vector3(17.2, 1.6, -82.8), Mats.get_mat("wood_panel"), false)
	Props.sign(geo, Vector3(17.3, 2.0, -82.8), PI * 0.5, "SAFETY IS A CHOICE", 22, Color(0.9, 0.8, 0.2), false)
	Props.papers(geo, Vector3(17.5, 0.02, -82.0), 4)
	Props.box(geo, Vector3(0.05, 1.5, 2.6), Vector3(17.2, 1.65, -80.0), _mat(Color(0.12, 0.2, 0.3), 0.5), false)
	Props.sign(geo, Vector3(17.3, 1.65, -80.0), PI * 0.5, "ONE-LINE  KF-2:  BUS-DS2A-BKR-DS2B-LINE", 14, Color(0.7, 0.9, 1.0), false)
	# frost on the inside of the glass and a drift under the north window
	_drift(Vector3(19.5, 0.0, -85.4), 1.0, 0.25, 0.7)
	# the SCADA terminal: Elias reads the situation (once)
	interact(Vector3(24.2, 1.0, -84.7), "Read SCADA screen", func(_p): _scada(), 2.0)
	# safe zone + music
	var sz := Area3D.new()
	sz.collision_layer = 0
	sz.collision_mask = 2
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(9.6, 3.0, 9.6)
	cs.shape = bs
	sz.add_child(cs)
	sz.position = Vector3(22.0, 1.5, -81.0)
	sz.add_to_group("safe_zone")
	add_child(sz)
	trigger("", Vector3(22.0, 1.5, -81.0), Vector3(8.0, 3.0, 8.0), func(_p): Sfx.music("music_safe", -10.0), false)
	trigger("", Vector3(30.0, 1.5, -81.0), Vector3(5.0, 3.0, 5.0), func(_p): Sfx.music("music_tension", -12.0), false)

func _scada() -> void:
	if Game.has_flag("l1_saw_order"):
		UI.toast("Bus 1 dead. KF-1 and KF-2 open. KF-3 closed: priority load.")
		return
	Game.set_flag("l1_saw_order")
	lock_player(true)
	Sfx.play("paper")
	await say([
		["ELIAS", "UPS is still holding the screen. Bus dead. KF-1 open. KF-2 open. KF-3 closed."],
		["ELIAS", "KF-3. Lake Road. That's the only feeder in the whole county still carrying load."],
		["ELIAS", "Shed order from Dispatch. 'MERIDIAN load protected.' Three nights. Three nights in the cold, for a data centre."],
		["ELIAS", "This isn't a fault. Someone opened these on purpose. And someone sat here and held them open."],
		["ELIAS", "KF-2 feeds the school. If I can close it by the book, Gran's shelter gets heat."],
	])
	lock_player(false)
	Game.set_objective("Re-close feeder KF-2. Find the hot stick and a 60A fuse, then follow the switching order.")

# =================================================================== side storage container
func _storage_container() -> void:
	var p := Vector3(20.0, 0.03, -95.4)
	var c := Mats.get_mat("corrugated", 1.2)
	var snow := Mats.get_mat("snow")
	Props.box(geo, Vector3(6.2, 2.7, 0.1), p + Vector3(0, 1.35, -1.15), c, true)            # back
	Props.box(geo, Vector3(0.1, 2.7, 2.4), p + Vector3(-3.1, 1.35, 0), c, true)             # west
	Props.box(geo, Vector3(0.1, 2.7, 2.4), p + Vector3(3.1, 1.35, 0), c, true)              # east
	Props.box(geo, Vector3(6.3, 0.12, 2.5), p + Vector3(0, 2.75, 0), c, true)               # roof
	Props.box(geo, Vector3(6.1, 0.18, 2.3), p + Vector3(0, 2.9, 0), snow, false)
	Props.box(geo, Vector3(6.2, 0.1, 2.3), p + Vector3(0, 0.05, 0), _mat(Color(0.25, 0.22, 0.2), 0.8), false)
	for i in 6:
		Props.box(geo, Vector3(0.05, 2.6, 0.05), p + Vector3(-2.6 + i * 1.04, 1.35, 1.2), _mat(Color(0.5, 0.2, 0.15), 0.8, 0.5), false)
	_icicles(p + Vector3(-3.0, 2.7, 1.2), p + Vector3(3.0, 2.7, 1.2), 14, 0.55)
	Props.sign(geo, p + Vector3(0, 2.4, -1.08), 0.0, "KF SUBSTATION  -  STORES", 24, Color(0.9, 0.9, 0.85), true)
	# contents: shelves, drums, the locked cabinet
	Props.shelf(geo, p + Vector3(0.6, 0.0, -0.85), 0.0, 1.8, 2.0, false)
	Props.crate(geo, p + Vector3(2.2, 0.0, 0.0), 0.2, 0.7)
	Props.barrel(geo, p + Vector3(-2.5, 0.0, 0.6), 0.0, true)
	Props.cabinet(geo, p + Vector3(-1.8, 0.0, -0.8), 0.0)
	Props.box(geo, Vector3(0.52, 0.04, 0.04), p + Vector3(-1.8, 0.85, -0.47), _mat(Color(0.6, 0.5, 0.15), 0.3, 0.9), false)   # frozen padlock
	Props.cyl(geo, 0.04, 0.1, p + Vector3(-1.8, 0.8, -0.46), _mat(Color(0.6, 0.5, 0.15), 0.3, 0.9), false)
	# battery lantern
	light(p + Vector3(0.4, 2.0, -0.2), Color(0.8, 0.9, 1.0), 1.8, 6.0, false, false)
	Props.cyl(geo, 0.08, 0.2, p + Vector3(0.4, 2.1, -0.85), Mats.emissive(Color(0.9, 0.95, 1.0), 3.0), false)
	interact(p + Vector3(-1.8, 1.0, 0.1), "Open locked cabinet", func(_pl): _pry_cabinet(p + Vector3(-1.8, 0.9, 0.05)), 1.8)
	if Game.has_flag("l1_cabinet_open"):
		pickup("l1_fuse", "fuse_60a", 1, p + Vector3(-1.5, 0.9, 0.0))
	_drift(p + Vector3(0, 0.0, 2.2), 2.4, 0.4, 0.8)

func _pry_cabinet(at: Vector3) -> void:
	if Game.has_flag("l1_cabinet_open"):
		UI.toast("The cabinet is open. Empty shelves and rust.")
		return
	if not Game.has_item("knife"):
		UI.toast("Padlock frozen solid. You need something to pry it with.")
		Sfx.play("deny")
		return
	Game.set_flag("l1_cabinet_open")
	Sfx.play("unlock")
	Sfx.play_at("knife_hit", at, 0.0, 0.7)
	UI.toast("You wedge the hatchet under the hasp and lean. The frozen padlock shears.")
	pickup("l1_fuse", "fuse_60a", 1, at + Vector3(0.3, 0.0, -0.05))

# =================================================================== the operator's area
func _pickup_truck(p: Vector3, yaw: float) -> void:
	var r := Node3D.new()
	r.position = p
	r.rotation.y = yaw
	geo.add_child(r)
	var body := _mat(Color(0.12, 0.28, 0.2), 0.35, 0.4)
	var dark := _mat(Color(0.05, 0.05, 0.06), 0.6, 0.2)
	var glass := _mat(Color(0.04, 0.06, 0.08, 0.9), 0.05, 0.3)
	var frost := _mat(Color(0.88, 0.92, 0.96, 0.6), 0.5)
	Props.box(r, Vector3(2.0, 0.5, 5.4), Vector3(0, 0.6, 0), dark)
	Props.box(r, Vector3(2.0, 0.7, 1.4), Vector3(0, 1.1, 1.8), body)                 # hood
	Props.box(r, Vector3(2.0, 0.95, 1.5), Vector3(0, 1.8, 0.45), body)               # cab
	Props.box(r, Vector3(2.02, 0.6, 1.2), Vector3(0, 1.95, 0.45), glass, false)
	Props.box(r, Vector3(2.04, 0.58, 1.18), Vector3(0, 1.95, 0.45), frost, false)
	Props.box(r, Vector3(1.9, 0.1, 1.4), Vector3(0, 2.32, 0.45), Mats.get_mat("snow"), false)
	# bed with walls
	Props.box(r, Vector3(1.9, 0.08, 2.2), Vector3(0, 0.9, -1.55), dark)
	for sx in [-1, 1]:
		Props.box(r, Vector3(0.1, 0.55, 2.3), Vector3(sx * 0.96, 1.15, -1.55), body)
	Props.box(r, Vector3(1.9, 0.55, 0.1), Vector3(0, 1.15, -2.65), body)
	Props.box(r, Vector3(1.9, 0.55, 0.1), Vector3(0, 1.15, -0.45), body)
	Props.box(r, Vector3(1.7, 0.12, 0.6), Vector3(0.0, 1.02, -2.2), _mat(Color(0.6, 0.15, 0.1), 0.6), false)   # toolbox
	Props.box(r, Vector3(1.8, 0.08, 1.6), Vector3(0, 1.0, -1.4), Mats.get_mat("snow"), false)
	for sx in [-1, 1]:
		for zz in [1.7, -1.7]:
			Props.cyl(r, 0.4, 0.3, Vector3(sx * 0.95, 0.4, zz), Mats.get_mat("rubber"), false, -1.0, Vector3(0, 0, PI * 0.5))
	Props.sign(r, Vector3(1.03, 1.8, 0.45), PI * 0.5, "LAKESHORE ELEC. 22", 16, Color(0.9, 0.9, 0.85), false)
	_drift(p + Basis(Vector3.UP, yaw) * Vector3(1.4, 0, 1.0), 1.1, 0.45, 0.8)

func _operator_area() -> void:
	# his pickup: parked inside the gate; hot stick lies in the bed
	_pickup_truck(Vector3(21.0, 0.03, -64.0), PI * 0.5)
	# the operator, frozen, by the transformers; control key, phone and ammo with him
	var op := Vector3(37.4, 0.03, -90.8)
	Props.corpse(geo, op, 2.2, {"shirt": Color(0.9, 0.45, 0.08), "pants": Color(0.12, 0.13, 0.18), "skin": Color(0.55, 0.62, 0.7)})
	Props.box(geo, Vector3(0.75, 0.16, 1.85), op + Vector3(0, 0.1, 0), _mat(Color(0.85, 0.92, 0.98, 0.65), 0.4), false, Vector3(0, 2.2, 0))
	for i in 7:
		var a := randf() * TAU
		Props.cyl(geo, 0.025, randf_range(0.15, 0.4), op + Vector3(cos(a) * 0.5, 0.15, sin(a) * 0.6), Mats.get_mat("ice"), false, 0.0, Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4)), 5)
	Props.sphere(geo, 0.2, op + Vector3(-0.5, 0.17, 0.9), _mat(Color(0.95, 0.75, 0.1), 0.5), Vector3(1.1, 0.7, 1.1))   # hard hat

func _downed_line() -> void:
	# a snapped pole leans over the access spur; one live end writhes in the snow and arcs
	var base := Vector3(12.0, 0.0, -66.5)
	var pole_m := Mats.get_mat("bark", 1.0)
	Props.cyl(geo, 0.2, 9.0, base + Vector3(0.0, 4.2, 0.0), pole_m, false, 0.16, Vector3(0.35, 0, 0.35), 10)
	Props.box(geo, Vector3(0.12, 0.12, 2.6), base + Vector3(-1.4, 7.8, -1.5), pole_m, false, Vector3(0.35, 0, 0.35))
	var arc := Vector3(9.0, 0.15, -62.0)
	for k in 3:
		var start := base + Vector3(-1.0 + k * 0.1, 8.3, -2.2 + k * 0.9)
		var end := arc + Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8))
		_wire(start, end, 1.0, 8, 0.02)
	Props.box(geo, Vector3(0.2, 0.08, 0.2), arc, _mat(Color(0.3, 0.3, 0.3), 0.3, 0.9), false)
	# cold blue-white arc light + sparks
	for i in 1:
		var l := OmniLight3D.new()
		l.light_color = Color(0.7, 0.82, 1.0)
		l.omni_range = 13.0
		l.omni_attenuation = 1.3
		l.light_energy = 5.0
		l.shadow_enabled = true
		l.light_volumetric_fog_energy = 3.0
		l.position = arc + Vector3(0, 0.8, 0)
		add_child(l)
		_arc_lights.append(l)
	_sparks(arc + Vector3(0, 0.2, 0), 14, false)
	# hazard cones and tape
	for pz in [-59.2, -64.8]:
		Props.cyl(geo, 0.2, 0.4, Vector3(10.5, 0.2, pz), _mat(Color(0.9, 0.4, 0.05), 0.5), false, 0.05)
	Props.box(geo, Vector3(0.4, 0.6, 0.04), Vector3(10.5, 0.4, -61.2), _mat(Color(0.9, 0.78, 0.1), 0.5), false)
	# warning once, damage zone always
	trigger("l1_warn_arc", Vector3(8.5, 1.0, -62.0), Vector3(10.0, 3.0, 8.0), func(_p):
		UI.toast("Downed conductor. Still live. Stay clear of the arcing end.", 4.0))
	_arc_pos = arc
	trigger("", arc + Vector3(0, 1.0, 0), Vector3(2.8, 2.4, 2.8), _arc_zone, false)

var _arc_pos := Vector3.ZERO

func _arc_zone(p) -> void:
	if _arc_cd > 0.0:
		return
	_arc_cd = 1.5
	Sfx.play_at("explosion", _arc_pos, -10.0, 1.8)
	_sparks(_arc_pos + Vector3(0, 0.4, 0), 40)
	UI.toast("The live conductor arcs across your boots!", 2.5)
	if p.has_method("hurt"):
		p.hurt(15, _arc_pos)

# =================================================================== exit gate and the school
func _exit_gate_and_school() -> void:
	var gz := -138.0
	# fence line across the whole field, concrete barriers either side of the gate
	_fence_run(Vector3(-80, 0, gz), Vector3(-4.4, 0, gz), false)
	_fence_run(Vector3(4.4, 0, gz), Vector3(80, 0, gz), false)
	for sx in [-1, 1]:
		box(Vector3(sx * 3.15, 0.65, gz), Vector3(1.9, 1.3, 1.0), "concrete")
		box(Vector3(sx * 2.05, 1.5, gz), Vector3(0.3, 3.0, 0.3), "metal_painted")
		Props.box(geo, Vector3(1.9, 0.12, 1.0), Vector3(sx * 3.15, 1.35, gz), Mats.get_mat("snow"), false)
	Props.box(geo, Vector3(4.4, 0.35, 0.3), Vector3(0, 3.0, gz), Mats.get_mat("metal_painted"), false)
	Props.sign(geo, Vector3(0, 3.0, gz + 0.2), 0.0, "KETTLE FALLS CONSOLIDATED SCHOOLS", 26, Color(0.9, 0.9, 0.85), true)
	Props.sign(geo, Vector3(0, 2.6, gz + 0.2), 0.0, "WINTER ROAD CLOSURE  -  SHELTER OPEN", 16, Color(0.95, 0.75, 0.2), false)
	door("l1_exit_gate", Vector3(0, 0.0, gz), 0.0, {"width": 3.6, "height": 2.5, "double": true, "mat": "metal", "to_level": "l2_school", "to_spawn": "from_road",
		"lock_flag": "feeder_closed", "locked_msg": "The road barrier is chained, and the gate motor is dead. No power in the whole town.", "prompt": "Go through the gate"})
	# status lamp on the gate post: red until the feeder is closed
	_gate_lamp = Mats.emissive(Color(1.0, 0.1, 0.05), 3.0)
	if Game.has_flag("feeder_closed"):
		_gate_lamp = Mats.emissive(Color(0.2, 1.0, 0.35), 3.0)
	Props.box(geo, Vector3(0.18, 0.18, 0.12), Vector3(2.05, 2.4, gz + 0.2), _gate_lamp, false)
	_gate_lamp_light = light(Vector3(2.0, 2.4, gz + 0.6), Color(0.2, 1.0, 0.35) if Game.has_flag("feeder_closed") else Color(1.0, 0.1, 0.05), 1.4, 6.0, false, false)
	# snow drifts + a burning barrel at the gate
	_drift(Vector3(-5.0, 0.0, gz + 1.2), 3.0, 0.7, 1.2)
	_drift(Vector3(6.0, 0.0, gz + 1.0), 3.0, 0.6, 1.0)
	# the school, 25 m beyond the gate: dark red-brick silhouette, windows still black
	var sz := -176.0
	var sw := 54.0
	box(Vector3(0, 4.5, sz), Vector3(sw, 9.0, 14.0), "brick_dark")
	box(Vector3(0, 9.3, sz), Vector3(sw + 1.0, 0.6, 15.0), "concrete", false)
	box(Vector3(0, 9.75, sz), Vector3(sw, 0.4, 14.4), "snow", false)
	box(Vector3(36.0, 5.5, sz + 2.0), Vector3(18.0, 11.0, 12.0), "brick_dark")   # gym wing
	box(Vector3(36.0, 11.4, sz + 2.0), Vector3(18.4, 0.5, 12.4), "snow", false)
	Props.cyl(geo, 1.1, 17.0, Vector3(-30.0, 8.5, sz - 4.0), Mats.get_mat("brick_dark"), false, 0.9)   # boiler stack
	var fz := sz + 7.02
	for row in 2:
		for i in 11:
			var wx := -23.0 + i * 4.6
			var wm := _mat(Color(0.04, 0.05, 0.06), 0.1, 0.4)
			wm.emission_enabled = true
			wm.emission = Color(1.0, 0.8, 0.5)
			wm.emission_energy_multiplier = 0.0
			Props.box(geo, Vector3(2.0, 2.0, 0.1), Vector3(wx, 2.7 + row * 3.8, fz), wm, false)
			Props.box(geo, Vector3(2.3, 0.14, 0.2), Vector3(wx, 3.76 + row * 3.8, fz + 0.05), Mats.get_mat("concrete"), false)
			_school_mats.append(wm)
			if Game.has_flag("feeder_closed"):
				wm.emission_energy_multiplier = 2.6
	for i in 4:
		var gx := 29.0 + i * 4.2
		var wm2 := _mat(Color(0.04, 0.05, 0.06), 0.1, 0.4)
		wm2.emission_enabled = true
		wm2.emission = Color(1.0, 0.85, 0.55)
		wm2.emission_energy_multiplier = 2.6 if Game.has_flag("feeder_closed") else 0.0
		Props.box(geo, Vector3(2.2, 5.0, 0.1), Vector3(gx, 5.5, sz + 8.02), wm2, false)
		_school_mats.append(wm2)
	# portico
	box(Vector3(0, 3.4, fz + 1.5), Vector3(9.0, 0.4, 3.4), "concrete", false)
	for cx in [-4.0, 4.0]:
		Props.cyl(geo, 0.3, 3.4, Vector3(cx, 1.7, fz + 2.8), Mats.get_mat("concrete"), false)
	Props.box(geo, Vector3(3.0, 2.6, 0.1), Vector3(0, 1.3, fz + 0.05), _mat(Color(0.03, 0.03, 0.04), 0.5), false)
	Props.sign(geo, Vector3(0, 4.2, fz + 0.2), 0.0, "KETTLE FALLS CONSOLIDATED SCHOOL", 40, Color(0.85, 0.85, 0.8), false)
	# lawn: flagpole, bare trees, bus
	Props.cyl(geo, 0.07, 9.0, Vector3(-12.0, 4.5, -160.0), Mats.get_mat("metal"), false)
	Props.tree(geo, Vector3(-16.0, 0.0, -156.0), 10.0, 911)
	Props.tree(geo, Vector3(14.0, 0.0, -158.0), 9.0, 912)
	Props.tree(geo, Vector3(22.0, 0.0, -152.0), 11.0, 913)
	for lx in [-18.0, 0.0, 18.0]:
		var ll := OmniLight3D.new()
		ll.light_color = Color(1.0, 0.8, 0.5)
		ll.omni_range = 22.0
		ll.light_energy = 2.5 if Game.has_flag("feeder_closed") else 0.0
		ll.shadow_enabled = false
		ll.light_volumetric_fog_energy = 1.0
		ll.position = Vector3(lx, 3.0, sz + 11.0)
		add_child(ll)
		_school_lights.append(ll)
	# the road continues up to the school
	box(Vector3(0, 0.02, -157.0), Vector3(10.0, 0.04, 40.0), "asphalt_snow", false)

func _pines() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var dark := _mat(Color(0.05, 0.1, 0.08), 0.95)
	var tip := _mat(Color(0.7, 0.75, 0.8), 0.9)
	var made := 0
	var tries := 0
	while made < 70 and tries < 400:
		tries += 1
		var x := rng.randf_range(-70.0, 75.0)
		var z := rng.randf_range(-150.0, 38.0)
		if abs(x) < 15.0:
			continue
		if x > 10.0 and x < 56.0 and z < -52.0 and z > -104.0:
			continue
		if x > 8.0 and x < 22.0 and z < -36.0 and z > -48.0:
			continue
		if x > 0.0 and x < 20.0 and z < -52.0 and z > -70.0:
			continue
		var h := rng.randf_range(5.0, 9.5)
		Props.cyl(geo, rng.randf_range(1.2, 1.9), h, Vector3(x, h * 0.5, z), dark, false, 0.05, Vector3.ZERO, 7)
		Props.cyl(geo, 0.9, h * 0.4, Vector3(x, h * 0.8, z), tip, false, 0.05, Vector3.ZERO, 7)
		made += 1

# =================================================================== switching puzzle
func _is_feeder_closed() -> bool:
	return Game.has_flag("feeder_closed")

func _operate(id: String) -> void:
	if _busy:
		return
	if _is_feeder_closed():
		UI.toast("KF-2 is already energised. Leave it alone.")
		return
	var sw: Dictionary = _sw[id]
	if sw.closed:
		UI.toast("Already closed.")
		return
	if sw.kind == "ds" and not Game.has_item("hot_stick"):
		UI.toast("You are not touching a disconnect bare-handed. You need an insulated hot stick.")
		Sfx.play("deny")
		return
	if sw.kind == "bkr" and not Game.has_flag("l1_fuse_in"):
		UI.toast("No control power. The breaker's control fuse is missing.")
		Sfx.play("deny")
		return
	var order := ["DS2A", "DS2B", "BKR"]
	if id == order[_step]:
		_set_switch(id, true)
		_step += 1
		Sfx.play("door_locked", -4.0, 0.7)
		if _step >= 3:
			_close_feeder_sequence()
		else:
			UI.toast("%s closed." % _sw_title(id), 2.0)
	else:
		_arc_flash(id)

func _sw_title(id: String) -> String:
	return {"DS2A": "DS-2A", "DS2B": "DS-2B", "DS2C": "DS-2C", "BKR": "BKR-KF2"}.get(id, id)

func _set_switch(id: String, closed: bool) -> void:
	var sw: Dictionary = _sw[id]
	sw.closed = closed
	var lbl: Label3D = sw.label
	lbl.text = "CLOSED" if closed else "OPEN"
	lbl.modulate = Color(1.0, 0.35, 0.25) if closed else Color(0.3, 1.0, 0.45)
	var piv: Node3D = sw.pivot
	if sw.kind == "ds":
		var tw := piv.create_tween()
		tw.tween_property(piv, "rotation:z", 0.0 if closed else float(sw.open_rot), 0.5).set_trans(Tween.TRANS_BACK)
	else:
		var tw2 := piv.create_tween()
		tw2.tween_property(piv, "position:y", piv.position.y + (0.3 if closed else -0.3), 0.3)

func _reset_switches() -> void:
	for id in _sw:
		if _sw[id].closed:
			_set_switch(id, false)
	_step = 0

func _arc_flash(id: String) -> void:
	_busy = true
	var sw: Dictionary = _sw[id]
	var at: Vector3 = (sw.pivot as Node3D).global_position
	var l := OmniLight3D.new()
	l.light_color = Color(0.8, 0.9, 1.0)
	l.light_energy = 60.0
	l.omni_range = 24.0
	l.shadow_enabled = false
	l.position = at + Vector3(0, 0.5, 0.5)
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.6)
	tw.tween_callback(l.queue_free)
	_sparks(at, 60)
	Sfx.play_at("explosion", at, 6.0, 1.3)
	Sfx.play("alarm", -10.0, 0.5)
	Sfx.alert_noise(at, 60.0)
	if player != null:
		player.call("hurt", 25, at)
	UI.toast("ARC FLASH! The disconnect flashes over and trips the bay. Everything drops open.", 4.0)
	_fails += 1
	await get_tree().create_timer(0.7).timeout
	_reset_switches()
	_busy = false
	if _fails >= 2 and not _hint_given:
		_hint_given = true
		await get_tree().create_timer(1.2).timeout
		Sfx.play("radio_squelch")
		await say([
			["JUNE (radio)", "Dad? ...I heard a bang. Are you okay? Do the thing from the manual. Dad, I know it by heart."],
			["JUNE (radio)", "Bus side first. Then the line side. The breaker last. Never touch the bypass. Never switch a disconnect under load."],
			["ELIAS", "Bus side, line side, breaker. Right. Thanks, kiddo."],
		])
	elif _fails == 1:
		UI.toast("Check the switching order in the control house.", 3.0)

func _close_feeder_sequence() -> void:
	_busy = true
	Game.set_flag("feeder_closed")
	lock_player(true)
	Sfx.play("unlock")
	Sfx.play("door_locked", 0.0, 0.5)
	Sfx.play("alarm", -18.0, 0.4)
	_sparks((_sw["BKR"].pivot as Node3D).global_position + Vector3(0, 0.5, 0), 30)
	await get_tree().create_timer(1.2).timeout
	# yard floodlights thump on
	for yl in _yard_lamps:
		(yl[0] as Light3D).visible = true
		(yl[1] as StandardMaterial3D).emission_energy_multiplier = 4.0
	Sfx.music("music_tension", -9.0)
	# turn the camera toward the school
	if player != null and player.get("cam_yaw") != null:
		var from: float = player.get("cam_yaw")
		var d := Vector3(0, 0, -176.0) - player.global_position
		var target := atan2(-d.x, -d.z)
		var yawtw := create_tween()
		yawtw.tween_method(func(v: float): player.set("cam_yaw", v), from, from + wrapf(target - from, -PI, PI), 1.6).set_trans(Tween.TRANS_SINE)
		yawtw.parallel().tween_method(func(v: float): player.set("cam_pitch", v), float(player.get("cam_pitch")), 0.05, 1.6)
	await get_tree().create_timer(1.8).timeout
	# the school's windows come on one by one
	for i in _school_mats.size():
		var m: StandardMaterial3D = _school_mats[i]
		var wt := create_tween()
		wt.tween_interval(randf_range(0.0, 2.6))
		wt.tween_property(m, "emission_energy_multiplier", 2.6, 0.35)
	for ll in _school_lights:
		var lt := create_tween()
		lt.tween_interval(1.5)
		lt.tween_property(ll, "light_energy", 2.5, 1.5)
	# gate status lamp to green
	_gate_lamp.albedo_color = Color(0.2, 1.0, 0.35)
	_gate_lamp.emission = Color(0.2, 1.0, 0.35)
	if _gate_lamp_light:
		_gate_lamp_light.light_color = Color(0.2, 1.0, 0.35)
	await get_tree().create_timer(3.4).timeout
	Sfx.play("radio_squelch")
	await say([
		["ELIAS", "KF-2 is hot. Look at that."],
		["JUNE (radio)", "Dad! Dad, the school just lit up. The gym, the hall, everything. Gran's shelter is there."],
		["JUNE (radio)", "People are crying. Gran's saying your name. Please hurry. Please, before they come toward the light."],
		["ELIAS", "Hold on, June. I'm coming. Stay inside, stay warm."],
	])
	lock_player(false)
	Game.set_objective("Reach the school. Gran's shelter. Follow Highway 53 north.")
	# the town's lights draw them
	for rs in _road_sleepers:
		_rouse(rs)
	if is_instance_valid(_worker):
		_rouse(_worker)
	Sfx.music("music_chase", -10.0)
	await get_tree().create_timer(14.0).timeout
	Sfx.music("music_tension", -12.0)
	_busy = false

func _rouse(e) -> void:
	if e == null or not is_instance_valid(e):
		return
	if e.get("state") == "down":
		e.hp = e.max_hp * 0.6
		if e.model:
			e.model.pose = "zombie"
		e._set_state("chase")
		e.awake = true
	elif e.get("state") == "dormant" or e.get("dormant"):
		e.wake()

# =================================================================== items, notes, enemies, triggers
func try_use_item(id: String) -> bool:
	var pp: Vector3 = player.global_position if player != null else Vector3.ZERO
	match id:
		"control_key":
			if pp.distance_to(_ctrl_door_pos) < 3.5:
				if Game.has_flag("unlocked:l1_ctrl_door"):
					UI.toast("The control house is already unlocked.")
					return false
				Game.set_flag("unlocked:l1_ctrl_door")
				Game.remove_item("control_key", 1)
				Sfx.play("unlock")
				UI.toast("Used Control House Key. The door will open now.")
				return true
			UI.toast("The key tag reads KF SUBSTATION - CONTROL HOUSE.")
		"fuse_60a":
			if pp.distance_to(_breaker_pos + Vector3(2.0, 0, 0.5)) < 4.0:
				if Game.has_flag("l1_fuse_in"):
					UI.toast("The fuse block already has its fuse.")
					return false
				_fuse_block()
				return true
			UI.toast("A 60A cartridge fuse. It belongs in the breaker's control cabinet.")
		"hot_stick":
			UI.toast("Walk up to a disconnect and operate it with the hot stick.")
		_:
			UI.toast("There is nothing to use it on here.")
	return false

func on_pickup(item: String, _uid: String) -> void:
	match item:
		"control_key":
			Game.set_objective("Get into the control house. Find the SCADA room by the spur.")
		"flare":
			if not Game.has_flag("l1_flare_tip"):
				Game.set_flag("l1_flare_tip")
				UI.toast("TAB: select the Road Flare and USE. It burns and drives the Rimebound back.", 5.0)
		"hot_stick":
			UI.toast("Insulated hot stick. Now you can work the disconnects.", 4.0)
		"fuse_60a":
			UI.toast("A 60A cartridge fuse. The breaker's control cabinet is in the switchyard.", 4.0)

func _items_and_notes() -> void:
	# --- the road
	pickup("l1_ammo_car", "ammo_9mm", 8, Vector3(-4.5, 0.03, -12.0))
	pickup("l1_flare_a", "flare", 1, Vector3(4.4, 0.03, -34.2))
	# --- sand shed (side room)
	var sp := Vector3(14.5, 0.0, -42.0)
	pickup("l1_gel_shed", "gel", 1, sp + Vector3(1.4, 1.0, 0.3))
	pickup("l1_pain", "adrenaline", 1, sp + Vector3(1.4, 1.5, 0.5))
	pickup("l1_powder", "powder", 1, sp + Vector3(0.9, 0.78, 1.5))
	# --- operator
	pickup("l1_key", "control_key", 1, Vector3(36.6, 0.06, -90.0))
	pickup("l1_ammo_op", "ammo_9mm", 6, Vector3(38.4, 0.03, -89.6))
	note("l1_note_phone", Vector3(37.8, 0.07, -91.8), "Phone: messages with Deb",
		"[b]RUSS (Dec 19, 04:41)[/b]\nDeb the line's dead at the house too?\n\n[b]DEB[/b]\nThe house is 41 degrees. Are you coming home\n\n[b]RUSS[/b]\nCan't leave the yard. Dispatch says hold. Order's from Corvane.\n\n[b]DEB[/b]\nGina next door isn't answering her door. Russ people are dying out here\n\n[b]RUSS (Dec 20, 23:12)[/b]\nthey told me not to touch KF-2.\n\n[b]RUSS[/b]\nPeople are freezing, Deb.\n\n[b]DEB[/b]\nThen touch it\n\n[b]RUSS (Dec 21, 21:52)[/b]\nGoing to do it by the book. Checking T2 first. Something humming wrong out there. Back in 5\n\n[b]DEB (22:03)[/b]\nRuss?\n\n[b]DEB (22:09)[/b]\nRuss please\n\n[b]DEB (22:31)[/b]\nplease",
		0.5)
	# --- truck + yard
	pickup("l1_hotstick", "hot_stick", 1, Vector3(19.4, 1.08, -64.0))
	pickup("l1_ammo_truck", "ammo_9mm", 5, Vector3(22.8, 0.04, -62.3))
	# --- control house
	pickup("l1_gel_house", "gel", 1, Vector3(26.5, 1.52, -83.2))
	pickup("l1_flare_b", "flare", 1, Vector3(26.5, 1.12, -83.5))
	pickup("l1_ammo_house", "ammo_9mm", 3, Vector3(25.4, 0.55, -77.6))
	note("l1_note_order", Vector3(26.0, 1.07, -85.4), "Printout: Load-Shed Order 0417",
		"[b]LAKESHORE ELECTRIC COOPERATIVE - SYSTEM OPERATIONS[/b]\n[b]EMERGENCY LOAD-SHED ORDER 0417[/b]\nDec 18, 2026 02:11\nIssued by Regional Dispatch\n\nGrid emergency, Level 3 (polar vortex). Effective immediately the following feeders are to be opened and held open:\n\n   KF-1  Main Street / Downtown\n   KF-2  School / Church / Residential\n\nFeeder KF-1 and KF-2 shed per Corvane Systems Priority Load Agreement, section 4.2.\n\n[b]MERIDIAN load protected.[/b]\nFeeder KF-3 (Lake Road) is to remain closed.\n\nDo not restore any shed feeder without written release from Dispatch. Estimated duration: indeterminate.\n\nAcknowledge receipt.\n- K. Hallstrom, Dispatch\n\nHandwritten underneath, in blue pen:\n\"There will not be a release. - R.\"")
	note("l1_note_switch", Vector3(20.6, 0.82, -84.9), "Operator's switching order and log",
		"[b]SWITCHING ORDER - RESTORE KF-2[/b]\n(copy from the manual, for my own sake)\n\n1. Verify BKR-KF2 OPEN.\n2. CLOSE DS-2A (bus side).\n3. CLOSE DS-2B (line side).\n4. CLOSE BKR-KF2. Last.\n\n[b]NEVER[/b] operate a disconnect with the breaker closed. A disconnect cannot interrupt load. It arcs, and it takes you with it.\n[b]DS-2C is the bypass.[/b] Maintenance only. Leave it alone.\n\nHot stick is on the hook in my truck bed. The breaker's control fuse (60A) blew in November. The spare is in the cabinet in the stores container. Padlock froze. Pry it.\n\n[b]LOG[/b]\n12/19  Temp -34. Heater only. Dispatch: hold.\n12/20  Temp -39. Heard from Deb. Not good.\n12/21  Temp -41. I am going to do it. If I am wrong, they can fire me.\n12/21 21:50  Going out to check T2. Back in five.")
	note("l1_note_flyer", Vector3(6.1, 0.0, -22.8), "Flyer: MERIDIAN community benefits",
		"[b]CORVANE SYSTEMS[/b]\n[b]MERIDIAN: Powering Tomorrow, Warming Kettle Falls[/b]\n\nHyperscale means hometown scale!\n\n- 41 permanent jobs for Kettle Falls families\n- Free-cooling on Lake Superior's cold, so your town runs greener\n- Heat Recovery Pipeline will warm homes and thaw the old mine workings (and bring Northline's lithium jobs back!)\n- A 25-year Community Priority Load Agreement, so Meridian is always a good neighbour\n\n[i]Come to the community open house at the school gym. Free cocoa.[/i]\n\nsmall print:\n[i]Priority Load Agreement terms apply. In a declared grid emergency, curtailment order is determined by contract. Subject to grid availability.[/i]",
		0.3)

func _enemies() -> void:
	var closed := Game.has_flag("feeder_closed")
	# the first Sleeper, beside the frozen family car
	enemy("l1_z1", "zombie", Vector3(-4.4, 0.0, -10.2), 1.2, {"variant": "civilian", "sleeping": true})
	# a lone Shambler walking the centre line past the second car
	enemy("l1_z2", "zombie", Vector3(0.0, 0.0, -44.0), 2.4, {"variant": "civilian"})
	# a Sleeper in a snowbank at the sign
	enemy("l1_z3", "zombie", Vector3(9.5, 0.0, -29.0), 0.6, {"variant": "worker", "sleeping": true})
	# the ambush: dormant behind the van, wakes when you reach the substation turn-off
	_ambush = enemy("l1_z4", "zombie", Vector3(-6.0, 0.0, -56.5), 0.4, {"variant": "miner", "dormant": true})
	# the night operator's replacement: a worker Shambler lurking in the yard
	_worker = enemy("l1_z5", "zombie", Vector3(45.0, 0.0, -87.0), 3.6, {"variant": "worker"})
	# two roadside Sleepers that wake when the town's lights come on
	var ss := {"variant": "civilian", "sleeping": not closed}
	var a = enemy("l1_z6", "zombie", Vector3(-3.0, 0.0, -111.0), 0.9, ss)
	var b = enemy("l1_z7", "zombie", Vector3(3.2, 0.0, -124.0), 2.0, {"variant": "miner", "sleeping": not closed})
	if a != null:
		_road_sleepers.append(a)
	if b != null:
		_road_sleepers.append(b)
	# a Rime hound at the substation (type may not exist yet)
	enemy("l1_hound", "hound", Vector3(48.0, 0.0, -64.0), 3.9, {})

func _triggers() -> void:
	# tutorial + story beats along the road
	trigger("l1_t_light", Vector3(2.0, 1.0, 25.0), Vector3(10.0, 3.0, 1.5), func(_p):
		UI.toast("L - flashlight on/off. The Rimebound see light from far away. Dark means safer.", 6.0))
	trigger("l1_t_truck", Vector3(0.0, 1.0, 19.0), Vector3(10.0, 3.0, 1.5), func(_p):
		lock_player(true)
		await say([
			["ELIAS", "Brake line froze solid. At minus forty, steel cracks like candy."],
			["ELIAS", "Town limits. Quarter mile to the first house. Walk it."],
		])
		lock_player(false))
	trigger("l1_t_radio", Vector3(0.0, 1.0, 7.0), Vector3(10.0, 3.0, 1.5), func(_p): _radio_call())
	trigger("l1_t_e", Vector3(-1.0, 1.0, -2.0), Vector3(10.0, 3.0, 1.5), func(_p):
		UI.toast("E - pick up / interact.   TAB - inventory, files and combining items.", 6.0))
	trigger("l1_t_aim", Vector3(0.0, 1.0, -7.5), Vector3(10.0, 3.0, 1.5), func(_p):
		UI.toast("RIGHT MOUSE - aim.  LEFT MOUSE - fire.  R - reload.  F - hatchet.  Something lies in the snow ahead.", 7.0))
	trigger("l1_t_flare", Vector3(0.0, 1.0, -28.0), Vector3(10.0, 3.0, 1.5), func(_p):
		UI.toast("Ammo is scarce. A Road Flare (TAB, USE) burns and repels the Rimebound. Light is a tool.", 6.0))
	trigger("l1_t_sign", Vector3(4.0, 1.0, -22.0), Vector3(10.0, 3.0, 2.0), func(_p):
		await say([["ELIAS", "Pop. 1,204. Not a single light on. Not one."]]))
	# ambush: the miner in the dark behind the van
	trigger("l1_t_ambush", Vector3(0.0, 1.0, -58.0), Vector3(10.0, 3.0, 1.5), func(_p):
		if is_instance_valid(_ambush):
			_ambush.wake()
			Sfx.play("heartbeat", -6.0)
		Sfx.music("music_tension", -10.0))
	trigger("l1_t_spur", Vector3(5.0, 1.0, -61.0), Vector3(6.0, 3.0, 2.0), func(_p):
		await say([["ELIAS", "Substation's up the spur. Gate's chained. Someone cut the fence further along."]]))
	trigger("l1_t_yard", Vector3(16.5, 1.0, -70.0), Vector3(3.0, 3.0, 4.0), func(_p):
		Sfx.music("music_tension", -9.0)
		UI.toast("A burning barrel. The Rimebound keep off the fire.", 4.0))
	trigger("l1_t_body", Vector3(35.0, 1.0, -88.0), Vector3(8.0, 3.0, 5.0), func(_p):
		await say([
			["ELIAS", "Russ Pelletier. Night operator. Never met him. Tag says he's the only one they left out here."],
			["ELIAS", "Frozen where he knelt. Key's in his hand. Sorry, friend."],
		]))

func _radio_call() -> void:
	lock_player(true)
	Sfx.play("radio_squelch")
	await say([
		["ELIAS", "June? Come in. It's Dad. Come in, kiddo."],
		["JUNE (radio)", "...Dad? You're LATE. You said Tuesday. It's been three days."],
		["ELIAS", "I know. Truck went in the ditch at the town limits. I'm on foot. Where are you?"],
		["JUNE (radio)", "School. Gran's shelter. It's so cold, the power's been out since the storm and there are people who sleep and don't..."],
		["JUNE (radio)", "Don't use your light. They see it. They come to the light, Dad. Dad, I can hear the hum again, it sounds like"],
	])
	Sfx.play("radio_squelch", -4.0, 0.6)
	await get_tree().create_timer(0.8).timeout
	await say([
		["ELIAS", "June? June!"],
		["ELIAS", "Dead grid, and the school's on the KF-2 feeder. The co-op substation is on the way up. If it's open I can close it."],
	])
	lock_player(false)
	Game.set_objective("Reach the Kettle Falls co-op substation, north on Highway 53.")
