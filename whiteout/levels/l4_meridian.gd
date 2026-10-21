extends "res://levels/level.gd"
## L4 — MERIDIAN. A hyperscale AI data centre on the frozen lake shore: the only warm, lit
## place in town. Gate -> lobby -> Hall A -> (electrical-room load puzzle) -> Hall C ->
## cooling plant (armory, coolant key) -> corridor -> NOC (Dr. Hart) -> pipeline head -> L5.

const T = preload("res://levels/l4_meridian_text.gd")

const HT := 4.5                 # ceiling height of most rooms
const BH := 9.5                 # exterior building height
const PH_H := 8.5               # pipeline hall ceiling
## Load-shed switches: flag -> kW. A set flag means the feeder is SHED (isolated).
const SW := {"l4_sw_pdu7": 14, "l4_sw_pdu9": 26, "l4_sw_ch3": 40}
const REQ := {"hallc": 40, "noc": 54}
const BREACH_LIMIT := 75.0

var _leds: Array = []
var _m_rack: StandardMaterial3D
var _m_front: StandardMaterial3D
var _m_cold: StandardMaterial3D
var _m_tray: StandardMaterial3D
var _m_insul: StandardMaterial3D
var _sw_lamp := {}
var _sw_lever := {}
var _sw_text := {}
var _total_label: Label3D
var _panel_lbl := {}
var _ch3_lamp: StandardMaterial3D
var _ch3_light: OmniLight3D
var _corr_zombies: Array = []
var _corr_alive := 0
var _breach_t := -1.0
var _wake_group: Array = []
var _foreman: Node3D
var _imogen: Node3D
var _toggled_once := false

# =================================================================== build
func build() -> void:
	_m_rack = Mats.color(Color(0.06, 0.07, 0.09), 0.45, 0.6)
	_m_front = Mats.color(Color(0.11, 0.12, 0.15), 0.35, 0.7)
	_m_cold = Mats.emissive(Color(0.7, 0.88, 1.0), 3.2)
	_m_tray = Mats.color(Color(0.45, 0.48, 0.52), 0.5, 0.8)
	_m_insul = Mats.color(Color(0.74, 0.77, 0.8), 0.35, 0.7)
	_env()
	_add_spawns()
	_shell()
	_yard()
	_lobby()
	_hall_a()
	_electrical()
	_hall_c()
	_plant()
	_armory()
	_corridor()
	_noc()
	_break_room()
	_pipeline_head()
	_flush_leds()
	_enemies()
	_refresh_switches()
	_restore_state()

func _env() -> void:
	env_exterior_night(false, 0.009, 0.3)
	var e: Environment = env.environment
	e.ambient_light_energy = 0.42
	e.glow_intensity = 0.9
	e.glow_hdr_threshold = 0.95
	e.volumetric_fog_albedo = Color(0.78, 0.86, 1.0)
	snowfall(1800)
	footstep = "snow"

func _add_spawns() -> void:
	add_spawn("start", Vector3(0, 0, 82), 0.0)

func _process(delta: float) -> void:
	super._process(delta)
	if player != null:
		var z: float = player.global_position.z
		if _snow != null:
			_snow.visible = z > 9.0
		footstep = "snow" if z > 12.0 else "tile"
	if _breach_t >= 0.0:
		_breach_t += delta
		if _corr_alive <= 0:
			_breach_t = -1.0
			if not Game.has_flag("imogen_taken"):
				Game.set_flag("imogen_alive")
		elif _breach_t > BREACH_LIMIT:
			_breach_t = -1.0
			if not Game.has_flag("met_imogen") and not Game.has_flag("imogen_alive"):
				Game.set_flag("imogen_taken")
				UI.toast("The pounding at the NOC glass stops.")

# =================================================================== helpers
func W(ax: float, az: float, bx: float, bz: float, gaps: Array = [], mat: Variant = "lab_wall", h: float = HT, y0: float = 0.0) -> void:
	wall(Vector2(ax, az), Vector2(bx, bz), h, mat, y0, 0.25, gaps)

func zone(x0: float, z0: float, x1: float, z1: float, h: float = HT, fmat: Variant = null, cmat: Variant = null) -> void:
	var fm: Variant = fmat if fmat != null else Mats.get_mat("lab_floor", 0.8)
	var cm: Variant = cmat if cmat != null else Mats.color(Color(0.55, 0.6, 0.66), 0.85)
	floor_rect(x0 - 0.13, z0 - 0.13, x1 + 0.13, z1 + 0.13, 0.0, fm)
	ceiling_rect(x0 - 0.13, z0 - 0.13, x1 + 0.13, z1 + 0.13, h, cm)

func label(text: String, pos: Vector3, yaw: float, size := 48, color := Color(0.75, 0.95, 1.2), ps := 0.004, shaded := false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = ps
	l.modulate = color
	l.shaded = shaded
	l.double_sided = false
	l.outline_size = 0
	l.position = pos
	l.rotation.y = yaw
	add_child(l)
	return l

func em(pos: Vector3, size: Vector3, color: Color, energy := 3.0) -> void:
	Props.box(geo, size, pos, Mats.emissive(color, energy), false)

func strip(x: float, z: float, len: float, along_z := true, y := HT - 0.04, color := Color(0.78, 0.9, 1.0)) -> void:
	var sz := Vector3(0.22, 0.04, len) if along_z else Vector3(len, 0.04, 0.22)
	Props.box(geo, sz + Vector3(0.1, 0.02, 0.1), Vector3(x, y + 0.02, z), Mats.get_mat("metal"), false)
	Props.box(geo, sz, Vector3(x, y, z), Mats.emissive(color, 3.0), false)

func glow(pos: Vector3, color := Color(0.75, 0.88, 1.0), energy := 1.5, rng := 10.0, shadows := false, flicker := false) -> OmniLight3D:
	return light(pos, color, energy, rng, shadows, flicker)

func dist_to(p: Vector3) -> float:
	return player.global_position.distance_to(p) if player != null else 999.0

func _led(p: Vector3, c: Color) -> void:
	_leds.append([p, c])

func _flush_leds() -> void:
	if _leds.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bm := BoxMesh.new()
	bm.size = Vector3(0.035, 0.03, 0.02)
	mm.mesh = bm
	mm.instance_count = _leds.size()
	for i in _leds.size():
		mm.set_instance_transform(i, Transform3D(Basis(), _leds[i][0]))
		mm.set_instance_color(i, _leds[i][1])
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded;\nvarying vec4 vc;\nvoid vertex() { vc = COLOR; }\nvoid fragment() {\n\tfloat ph = vc.a;\n\tfloat k = 0.3 + 0.7 * step(0.45, fract(TIME * (0.4 + ph * 2.2) + ph * 9.0));\n\tif (ph < 0.45) { k = 1.0; }\n\tALBEDO = vc.rgb * k * 1.9;\n}\n"
	var smat := ShaderMaterial.new()
	smat.shader = sh
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = smat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

func _rack(pos: Vector3, yaw: float, rng: RandomNumberGenerator, warm := 0.1) -> void:
	var r := Node3D.new()
	r.position = pos
	r.rotation.y = yaw
	add_child(r)
	Props.box(r, Vector3(0.8, 2.3, 1.0), Vector3(0, 1.15, 0), _m_rack, true)
	Props.box(r, Vector3(0.74, 2.1, 0.03), Vector3(0, 1.15, 0.505), _m_front, false)
	var b := Basis(Vector3.UP, yaw)
	for u in 11:
		if rng.randf() < 0.15:
			continue
		var y := 0.22 + u * 0.18
		var n := rng.randi_range(2, 4)
		for i in n:
			var roll := rng.randf()
			var c := Color(0.1, 1.0, 0.3)
			if roll > 0.97 - warm * 0.4:
				c = Color(1.0, 0.12, 0.08)
			elif roll > 0.78 - warm:
				c = Color(1.0, 0.6, 0.1)
			elif roll > 0.55:
				c = Color(0.25, 0.55, 1.0)
			c.a = rng.randf()
			_led(pos + b * Vector3(-0.3 + i * 0.07, y, 0.527), c)
		Props.box(r, Vector3(0.3, 0.04, 0.012), Vector3(0.18, y, 0.522), Mats.color(Color(0.03, 0.03, 0.04), 0.5), false)

func _rack_row(x: float, z0: float, z1: float, face: int, seed_v: int = 1, warm := 0.1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var n := int((z1 - z0) / 0.84)
	for i in n:
		_rack(Vector3(x, 0, z0 + 0.42 + i * 0.84), PI * 0.5 * face, rng, warm)

func _tray(x: float, z0: float, z1: float, y: float, w := 0.7) -> void:
	var len := absf(z1 - z0)
	var zc := (z0 + z1) * 0.5
	Props.box(geo, Vector3(w, 0.05, len), Vector3(x, y, zc), _m_tray, false)
	for s in [-1, 1]:
		Props.box(geo, Vector3(0.04, 0.12, len), Vector3(x + s * w * 0.5, y + 0.06, zc), _m_tray, false)
	Props.box(geo, Vector3(w * 0.7, 0.1, len), Vector3(x, y + 0.08, zc), Mats.color(Color(0.04, 0.04, 0.05), 0.6), false)
	var z := minf(z0, z1) + 1.0
	while z < maxf(z0, z1):
		Props.box(geo, Vector3(0.03, HT - y - 0.1, 0.03), Vector3(x - w * 0.5 + 0.02, y + (HT - y) * 0.5, z), _m_tray, false)
		Props.box(geo, Vector3(0.03, HT - y - 0.1, 0.03), Vector3(x + w * 0.5 - 0.02, y + (HT - y) * 0.5, z), _m_tray, false)
		z += 3.0

func _containment(x: float, z: float, width: float, yaw: float, text: String) -> void:
	var r := Node3D.new()
	r.position = Vector3(x, 0, z)
	r.rotation.y = yaw
	add_child(r)
	var fm := Mats.color(Color(0.8, 0.82, 0.85), 0.4, 0.6)
	for s in [-1, 1]:
		Props.box(r, Vector3(0.1, 2.8, 0.1), Vector3(s * width * 0.5, 1.4, 0), fm, false)
	Props.box(r, Vector3(width + 0.1, 0.1, 0.1), Vector3(0, 2.8, 0), fm, false)
	Props.box(r, Vector3(width - 0.1, 2.7, 0.02), Vector3(0, 1.4, 0), Mats.get_mat("glass"), false)
	Props.box(r, Vector3(0.04, 2.7, 0.05), Vector3(0, 1.4, 0), fm, false)
	var l := Label3D.new()
	l.text = text
	l.font_size = 30
	l.pixel_size = 0.004
	l.modulate = Color(0.6, 0.85, 1.1)
	l.shaded = false
	l.position = Vector3(0, 2.55, 0.06)
	r.add_child(l)

func _frost(pos: Vector3, size: Vector2) -> void:
	Props.box(geo, Vector3(size.x, 0.012, size.y), pos + Vector3(0, 0.008, 0), Mats.get_mat("frost", 1.0), false, Vector3(0, randf() * TAU, 0))

func _icicles(pos: Vector3, count: int, span: float) -> void:
	var ice := Mats.get_mat("ice")
	for i in count:
		var h := randf_range(0.15, 0.5)
		Props.cyl(geo, 0.0, h, pos + Vector3(randf_range(-span, span), -h * 0.5, randf_range(-0.1, 0.1)), ice, false, 0.035)

func _floor_hole(pos: Vector3) -> void:
	Props.box(geo, Vector3(0.6, 0.01, 0.6), pos + Vector3(0, 0.012, 0), Mats.color(Color(0.01, 0.01, 0.015), 0.9), false)
	Props.box(geo, Vector3(0.58, 0.035, 0.58), pos + Vector3(0.9, 0.02, 0.4), Mats.get_mat("lab_floor", 0.6), false, Vector3(0, 0.3, 0.12))
	Props.cyl(geo, 0.03, 0.8, pos + Vector3(0, 0.03, 0), Mats.color(Color(0.05, 0.05, 0.3), 0.5), false, -1.0, Vector3(0, 0, PI * 0.5))

func _intercom(pos: Vector3, yaw: float, text := "") -> void:
	var r := Node3D.new()
	r.position = pos
	r.rotation.y = yaw
	add_child(r)
	Props.box(r, Vector3(0.34, 0.55, 0.1), Vector3(0, 1.4, 0), Mats.color(Color(0.1, 0.11, 0.14), 0.4, 0.5), false)
	Props.cyl(r, 0.07, 0.02, Vector3(0, 1.55, 0.06), Mats.emissive(Color(0.2, 0.6, 1.0), 4.0), false, -1.0, Vector3(PI * 0.5, 0, 0))
	Props.box(r, Vector3(0.2, 0.12, 0.02), Vector3(0, 1.3, 0.055), Mats.get_mat("emissive_cold"), false)
	var l := OmniLight3D.new()
	l.light_color = Color(0.3, 0.6, 1.0)
	l.light_energy = 0.5
	l.omni_range = 3.0
	l.shadow_enabled = false
	l.position = Vector3(0, 1.4, 0.4)
	r.add_child(l)

func _corpse(pos: Vector3, yaw: float, cfg := {}) -> void:
	Props.corpse(geo, pos, yaw, cfg)

func _make_npc(preset: String, pos: Vector3, yaw: float, cfg := {}) -> Node3D:
	if ResourceLoader.exists("res://actors/npc.gd"):
		var N = load("res://actors/npc.gd")
		var n: Node3D = N.new()
		n.setup_npc(N.preset(preset))
		n.position = pos
		n.rotation.y = yaw
		add_child(n)
		return n
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	add_child(root)
	var hmn: Node3D = load("res://actors/humanoid.gd").new()
	hmn.setup(cfg)
	root.add_child(hmn)
	return root

func _near(pos: Vector3, r := 3.5) -> bool:
	return dist_to(pos) < r

# =================================================================== shell
func _shell() -> void:
	var ext := Mats.get_mat("lab_wall", 3.0)
	wall(Vector2(-34, 12), Vector2(50, 12), BH, ext, 0.0, 0.4, [[34.0, 2.8, 2.9]])
	wall(Vector2(-34, -98), Vector2(-34, 12), BH, ext, 0.0, 0.4)
	wall(Vector2(50, -98), Vector2(50, 12), BH, ext, 0.0, 0.4)
	wall(Vector2(-34, -98), Vector2(50, -98), BH, ext, 0.0, 0.4, [[52.0, 2.8, 2.9]])
	box(Vector3(8, BH + 0.2, -43), Vector3(84.8, 0.4, 110.8), "concrete")
	# interior walls (shared walls built once)
	var lw := Mats.get_mat("lab_wall", 3.0)
	# lobby
	W(-8, -6, -8, 12)
	W(8, -6, 8, 12)
	# hall A
	W(-16, -6, 16, -6, [[16.0, 3.4, 3.2]])
	W(-16, -36, -16, -6, [[14.5, 2.4, 2.7]])
	W(16, -36, 16, -6)
	W(-16, -36, 16, -36, [[16.0, 3.0, 2.8]])
	# electrical room
	W(-30, -32, -30, -12)
	W(-30, -32, -16, -32)
	W(-30, -12, -16, -12)
	# hall C / plant
	W(-16, -60, -16, -36)
	W(16, -60, 16, -36, [[12.0, 3.0, 2.8]])
	W(16, -36, 50, -36, [[30.0, 2.6, 2.8]])
	W(-30, -60, 50, -60, [[74.0, 2.6, 2.8]])
	# armory
	W(34, -36, 34, -22)
	W(34, -22, 50, -22)
	# corridor
	W(-30, -66, -30, -60)
	W(-30, -66, -14, -66)
	W(-14, -66, 2, -66, [[8.0, 2.2, 2.7]], Mats.get_mat("glass"))
	W(2, -66, 50, -66, [[16.0, 3.0, 2.8]])
	W(6, -66, 30, -66, [], "lab_wall", PH_H - HT, HT)
	# NOC + break room
	W(-14, -84, 2, -84)
	W(-14, -84, -14, -66, [[10.0, 1.8, 2.6]])
	W(2, -84, 2, -66)
	W(-30, -80, -30, -66)
	W(-30, -80, -14, -80)
	# pipeline hall
	W(6, -98, 6, -66, [], "lab_wall", PH_H)
	W(30, -98, 30, -66, [], "lab_wall", PH_H)
	# zones: floors + ceilings
	zone(-8, -6, 8, 12)
	zone(-16, -36, 16, -6)
	zone(-30, -32, -16, -12)
	zone(-16, -60, 16, -36)
	zone(16, -60, 50, -36)
	zone(34, -36, 50, -22)
	zone(-30, -66, 50, -60)
	zone(-14, -84, 2, -66)
	zone(-30, -80, -14, -66)
	zone(6, -98, 30, -66, PH_H)
	# facade: glowing windows, sign, entrance canopy
	for i in range(-6, 10):
		var x := i * 5.0 - 1.0
		if absf(x) < 4.0:
			continue
		for yy in [2.4, 6.4]:
			Props.box(geo, Vector3(2.6, 1.6, 0.1), Vector3(x, yy, 12.25), Mats.emissive(Color(0.62, 0.82, 1.0), 1.6), false)
			Props.box(geo, Vector3(0.06, 1.6, 0.14), Vector3(x, yy, 12.27), Mats.get_mat("metal"), false)
	Props.box(geo, Vector3(84, 0.3, 0.2), Vector3(8, 4.3, 12.3), Mats.emissive(Color(0.5, 0.75, 1.0), 2.0), false)
	label("MERIDIAN", Vector3(0, 7.6, 12.3), 0.0, 220, Color(0.8, 0.95, 1.4), 0.012)
	label("CORVANE SYSTEMS  ·  SITE OPERATIONS  ·  AUTHORISED PERSONNEL ONLY", Vector3(0, 5.8, 12.3), 0.0, 60, Color(0.6, 0.78, 1.0), 0.008)
	Props.box(geo, Vector3(8, 0.25, 3.2), Vector3(0, 3.4, 13.7), Mats.get_mat("metal"), true)
	for sx in [-3.6, 3.6]:
		Props.cyl(geo, 0.12, 3.4, Vector3(sx, 1.7, 15.2), Mats.get_mat("metal"), true)
	Props.box(geo, Vector3(7.6, 0.06, 3.0), Vector3(0, 3.24, 13.7), Mats.emissive(Color(0.8, 0.92, 1.0), 2.5), false)
	for sx in [-14.0, 14.0, 30.0, -26.0]:
		var sp := spot(Vector3(sx, 9.0, 13.5), Vector3(sx * 0.6, 0, 30), Color(0.72, 0.85, 1.0), 9.0, 42.0, 48.0, false)
		sp.light_volumetric_fog_energy = 1.0
	glow(Vector3(0, 2.8, 14.0), Color(0.75, 0.9, 1.0), 2.5, 12.0, true)

# =================================================================== exterior yard
func _yard() -> void:
	floor_rect(-70, 12, 80, 100, 0.0, "snow", 0.4)
	box(Vector3(0, 0.015, 74), Vector3(9, 0.03, 54), "asphalt_snow")
	box(Vector3(0, 0.015, 30), Vector3(7, 0.03, 36), "asphalt_snow")
	box(Vector3(0, 0.015, 47), Vector3(7, 0.03, 12), "asphalt_snow")
	# perimeter: snowbanks and flank walls
	for seg in [[-70, 12, -70, 100], [80, 12, 80, 100]]:
		wall(Vector2(seg[0], seg[1]), Vector2(seg[2], seg[3]), 3.0, "snow", 0.0, 1.2)
	wall(Vector2(-70, 100), Vector2(80, 100), 3.0, "snow", 0.0, 1.2)
	wall(Vector2(-70, 12), Vector2(-34, 12), 3.5, "concrete", 0.0, 0.5)
	wall(Vector2(50, 12), Vector2(80, 12), 3.5, "concrete", 0.0, 0.5)
	# security fence with a gate gap
	Props.fence(geo, Vector3(-70, 0, 46), Vector3(-2.2, 0, 46), 3.0)
	Props.fence(geo, Vector3(2.2, 0, 46), Vector3(80, 0, 46), 3.0)
	for sx in [-2.2, 2.2]:
		Props.cyl(geo, 0.14, 3.4, Vector3(sx, 1.7, 46), Mats.get_mat("metal_painted"), true)
	Props.box(geo, Vector3(4.2, 0.15, 0.15), Vector3(0, 3.5, 46), Mats.get_mat("metal_painted"), false)
	label("SECURITY CHECKPOINT\nALL VISITORS REPORT TO GATE 1", Vector3(0, 3.0, 46.2), 0.0, 40, Color(1.0, 0.85, 0.2), 0.005, true)
	# barrier arm lowered across the vehicle lane (decor, left of pedestrian gap)
	Props.box(geo, Vector3(0.5, 1.0, 0.5), Vector3(-2.9, 0.5, 49.5), Mats.get_mat("metal_painted"), true)
	Props.box(geo, Vector3(3.2, 0.1, 0.1), Vector3(-1.2, 0.95, 49.5), Mats.color(Color(0.85, 0.1, 0.1), 0.5), false)
	# guard booth
	_booth()
	# lights on the road and yard
	Props.lamp_post(geo, Vector3(-5.5, 0, 66), PI, true, Color(0.7, 0.85, 1.0))
	Props.lamp_post(geo, Vector3(5.5, 0, 36), 0.0, true, Color(0.7, 0.85, 1.0))
	Props.lamp_post(geo, Vector3(-6.0, 0, 22), PI, true, Color(0.7, 0.85, 1.0))
	for p in [Vector3(-12, 0, 70), Vector3(12, 0, 74), Vector3(-18, 0, 30), Vector3(20, 0, 32)]:
		Props.box(geo, Vector3(7, 1.0 + randf(), 5), p + Vector3(0, 0.4, 0), Mats.get_mat("snow"), false, Vector3(0, randf() * 3, 0))
	# wrecked cars on the lake road, people who did not get in
	Props.car(geo, Vector3(-4.2, 0, 62), 0.2, Color(0.2, 0.25, 0.3), true)
	Props.car(geo, Vector3(3.8, 0, 55), PI - 0.3, Color(0.35, 0.1, 0.1), true, "van")
	Props.car(geo, Vector3(-9, 0, 30), 1.2, Color(0.15, 0.2, 0.15), true)
	var jackets := [Color(0.5, 0.15, 0.1), Color(0.1, 0.25, 0.4), Color(0.3, 0.3, 0.2), Color(0.55, 0.45, 0.1)]
	var spots := [Vector3(-1.4, 0, 49.4), Vector3(0.5, 0, 50.6), Vector3(1.9, 0, 48.6), Vector3(-0.2, 0, 52.4), Vector3(-3.4, 0, 51.4)]
	for i in spots.size():
		_corpse(spots[i], randf_range(-0.6, 0.6) + PI, {"coat": true, "coat_color": jackets[i % 4], "bloody": 0.1, "skin": Color(0.62, 0.66, 0.7)})
		_frost(spots[i] + Vector3(0, 0, 0.3), Vector2(1.6, 0.9))
	Props.tree(geo, Vector3(-22, 0, 60), 8.0, 3)
	Props.tree(geo, Vector3(24, 0, 64), 9.0, 5)
	Props.tree(geo, Vector3(-30, 0, 24), 8.0, 8)
	# intercom post at the gate
	Props.cyl(geo, 0.1, 1.2, Vector3(-3.4, 0.6, 47.4), Mats.get_mat("metal_painted"), false)
	Props.box(geo, Vector3(0.3, 0.45, 0.12), Vector3(-3.4, 1.3, 47.4), Mats.color(Color(0.1, 0.11, 0.14), 0.4, 0.5), false)
	Props.cyl(geo, 0.06, 0.02, Vector3(-3.4, 1.4, 47.48), Mats.emissive(Color(0.2, 0.6, 1.0), 4.0), false, -1.0, Vector3(PI * 0.5, 0, 0))
	glow(Vector3(-3.4, 1.8, 48.2), Color(0.3, 0.6, 1.0), 1.0, 5.0)
	# entrance door (badge) + gate trigger
	door("l4_front", Vector3(0, 0, 12), 0.0, {"double": true, "width": 2.6, "height": 2.8, "mat": "metal", "lock_item": "badge_meridian", "keep_key": true,
		"locked_msg": "Card reader: ACCESS DENIED. It needs a MERIDIAN badge."})
	label("MAIN ENTRANCE", Vector3(0, 3.15, 12.25), 0.0, 40, Color(0.7, 0.9, 1.2), 0.005)
	trigger("l4_gate_greet", Vector3(0, 1.5, 62), Vector3(24, 3, 3), func(_p): _gate_greet())

func _booth() -> void:
	var bx := 6.0
	var bz := 44.0
	W(bx - 1.6, bz - 1.8, bx + 1.6, bz - 1.8, [], "plaster_dirty", 2.7)
	W(bx - 1.6, bz + 1.8, bx + 1.6, bz + 1.8, [], "plaster_dirty", 2.7)
	W(bx + 1.6, bz - 1.8, bx + 1.6, bz + 1.8, [], "plaster_dirty", 2.7)
	W(bx - 1.6, bz - 1.8, bx - 1.6, bz + 1.8, [[1.8, 1.4, 2.3]], "plaster_dirty", 2.7)
	floor_rect(bx - 1.75, bz - 1.95, bx + 1.75, bz + 1.95, 0.0, "tile_floor", 0.3)
	box(Vector3(bx, 2.8, bz), Vector3(3.8, 0.2, 4.2), "concrete")
	Props.box(geo, Vector3(2.6, 0.9, 0.06), Vector3(bx, 1.5, bz + 1.76), Mats.get_mat("glass"), false)
	Props.desk(geo, Vector3(bx + 0.6, 0, bz - 1.0), PI)
	Props.chair(geo, Vector3(bx + 0.6, 0, bz - 0.2), 0.4, true)
	Props.cabinet(geo, Vector3(bx + 1.3, 0, bz + 1.2), -PI * 0.5)
	light(Vector3(bx, 2.5, bz), Color(1.0, 0.76, 0.5), 1.8, 7.5, true, false)
	Props.sphere(geo, 0.08, Vector3(bx, 2.58, bz), Mats.emissive(Color(1.0, 0.8, 0.5), 3.0))
	_corpse(Vector3(bx - 0.4, 0, bz + 0.4), 1.2, {"vest": true, "vest_color": Color(0.8, 0.5, 0.05), "shirt": Color(0.1, 0.12, 0.22), "pants": Color(0.08, 0.1, 0.18), "headgear": "cap", "bloody": 0.0, "skin": Color(0.6, 0.66, 0.72)})
	pickup("l4_badge", "badge_meridian", 1, Vector3(bx - 1.0, 0.04, bz + 0.3))
	pickup("l4_booth_9mm", "ammo_9mm", 4, Vector3(bx + 1.0, 0.82, bz - 1.0))
	note("l4_log", Vector3(bx + 0.3, 0.8, bz - 1.1), T.LOG_TITLE, T.LOG, 0.5)

func _gate_greet() -> void:
	lock_player(true)
	await say([["MERIDIAN", "Welcome to the MERIDIAN site. Your presence is not authorised."],
		["MERIDIAN", "Please remain where you are. Security has been notified. Uptime: 99.9997%."],
		["ELIAS", "Security's face-down in the booth. I'm coming in."],
		["MERIDIAN", "Noted. I have not been asked to prevent that. I have only been asked to describe it."]])
	lock_player(false)
	Game.set_objective("Search the guard booth for a MERIDIAN badge.")

# =================================================================== lobby
func _lobby() -> void:
	for x in [-5.0, 0.0, 5.0]:
		strip(x, 3.0, 12.0)
	glow(Vector3(0, 3.8, 6), Color(0.78, 0.9, 1.0), 2.0, 14.0, true)
	glow(Vector3(-5, 3.8, -1), Color(0.78, 0.9, 1.0), 1.2, 9.0)
	glow(Vector3(5, 3.8, -1), Color(0.78, 0.9, 1.0), 1.2, 9.0)
	# reception desk
	Props.box(geo, Vector3(4.2, 1.05, 0.9), Vector3(-4.5, 0.525, 1.0), Mats.color(Color(0.9, 0.92, 0.95), 0.25, 0.1), true)
	Props.box(geo, Vector3(4.2, 0.06, 1.0), Vector3(-4.5, 1.08, 1.0), Mats.color(Color(0.05, 0.06, 0.08), 0.2, 0.5), false)
	Props.box(geo, Vector3(0.5, 0.32, 0.04), Vector3(-5.5, 1.35, 0.9), Mats.emissive(Color(0.3, 0.6, 1.0), 1.5), false)
	Props.chair(geo, Vector3(-4.5, 0, 2.0), 0.3, true)
	note("l4_agreement", Vector3(-3.2, 1.115, 1.0), T.AGREEMENT_TITLE, T.AGREEMENT, 0.3)
	# welcome wall
	Props.box(geo, Vector3(5.5, 2.2, 0.08), Vector3(0, 2.2, -5.8), Mats.emissive(Color(0.1, 0.35, 0.65), 1.3), false)
	label("WELCOME TO MERIDIAN\nUPTIME  99.9997%", Vector3(0, 2.6, -5.74), 0.0, 90, Color(0.85, 0.98, 1.3), 0.007)
	label("Visitors must be escorted at all times.", Vector3(0, 1.5, -5.74), 0.0, 36, Color(0.6, 0.78, 0.95), 0.005)
	# turnstiles and benches
	for sx in [-1.5, 1.5]:
		Props.box(geo, Vector3(0.2, 1.0, 1.4), Vector3(sx, 0.5, -3.5), Mats.color(Color(0.7, 0.72, 0.76), 0.3, 0.6), true)
		em(Vector3(sx, 1.02, -3.5), Vector3(0.12, 0.03, 0.9), Color(0.2, 1.0, 0.5), 3.0)
	Props.bench(geo, Vector3(5.2, 0, 4.0), PI * 0.5)
	Props.bench(geo, Vector3(5.2, 0, 7.5), PI * 0.5)
	Props.debris(geo, Vector3(-3, 0, 8), 0.0, 4, "frost")
	Props.papers(geo, Vector3(1.5, 0.01, 3.0), 7)
	_corpse(Vector3(-6.2, 0, 6.5), 0.8, {"shirt": Color(0.2, 0.3, 0.45), "bloody": 0.3})
	_frost(Vector3(0, 0, 10.5), Vector2(3.0, 1.2))
	pickup("l4_lobby_gel", "gel", 1, Vector3(-5.6, 1.12, 0.8))
	trigger("l4_lobby_greet", Vector3(0, 1.5, 8), Vector3(8, 3, 3), func(_p): _lobby_greet())

func _lobby_greet() -> void:
	lock_player(true)
	await say([["MERIDIAN", "Badge detected. Contractor, CORVANE SYSTEMS. Expired fourteen days ago."],
		["MERIDIAN", "Welcome back. You are still not authorised. I have, however, lost the ability to care about that."],
		["MERIDIAN", "Doors inside this facility are under my control. I will open them if uptime is not reduced."],
		["ELIAS", "And if it is?"],
		["MERIDIAN", "Then we should discuss what you can offer."]])
	lock_player(false)
	Game.set_objective("Get through Hall A. MERIDIAN controls the doors.")

# =================================================================== hall A
func _hall_a() -> void:
	var z0 := -35.2
	var z1 := -7.2
	_rack_row(-13.5, z0, -24.0, 1, 11)
	_rack_row(-13.5, -19.6, z1, 1, 12)
	_rack_row(-9.5, z0, -24.0, -1, 13)
	_rack_row(-9.5, -19.6, z1, -1, 14, 0.25)
	_rack_row(-5.5, z0, -24.0, 1, 15)
	_rack_row(-5.5, -19.6, z1, 1, 16)
	_rack_row(5.5, z0, -24.0, -1, 17)
	_rack_row(5.5, -19.6, z1, -1, 18)
	_rack_row(9.5, z0, -24.0, 1, 19, 0.25)
	_rack_row(9.5, -19.6, z1, 1, 20)
	_rack_row(13.5, z0, -24.0, -1, 21)
	_rack_row(13.5, -19.6, z1, -1, 22)
	for x in [-11.5, 0.0, 11.5]:
		_tray(x, -35.5, -6.5, 3.4 if x == 0.0 else 2.9)
	for z in [-31.0, -26.0, -21.5, -16.0, -11.0]:
		strip(0, z, 2.0, false)
		strip(-11.5, z + 1.0, 1.6, false, HT - 0.04, Color(0.7, 0.85, 1.0))
		strip(11.5, z + 1.0, 1.6, false, HT - 0.04, Color(0.7, 0.85, 1.0))
	for z in [-31.0, -21.5, -11.0]:
		glow(Vector3(0, 3.9, z), Color(0.75, 0.88, 1.0), 1.7, 11.0, z == -21.5)
		glow(Vector3(-11.5, 3.6, z), Color(0.7, 0.85, 1.0), 1.1, 8.0)
		glow(Vector3(11.5, 3.6, z), Color(0.7, 0.85, 1.0), 1.1, 8.0)
	for x in [-7.5, 7.5]:
		glow(Vector3(x, 3.4, -28), Color(1.0, 0.55, 0.25), 0.9, 6.0)
	_containment(-11.5, -7.0, 2.9, 0.0, "COLD AISLE A1")
	_containment(11.5, -7.0, 2.9, 0.0, "COLD AISLE A3")
	_containment(-11.5, -35.5, 2.9, 0.0, "COLD AISLE A1")
	_containment(11.5, -35.5, 2.9, 0.0, "COLD AISLE A3")
	label("HALL A  ·  INFERENCE CLUSTER", Vector3(0, 3.7, -35.8), 0.0, 60, Color(0.65, 0.88, 1.2), 0.006)
	label("HOT AISLE — 41 °C", Vector3(-7.5, 3.0, -35.8), 0.0, 28, Color(1.0, 0.6, 0.3), 0.004)
	label("HOT AISLE — 41 °C", Vector3(7.5, 3.0, -35.8), 0.0, 28, Color(1.0, 0.6, 0.3), 0.004)
	for p in [Vector3(-4, 0, -21), Vector3(3, 0, -22), Vector3(7, 0, -9)]:
		_floor_hole(p)
	_corpse(Vector3(-2.5, 0, -14), 2.0, {"coat": true, "coat_color": Color(0.85, 0.85, 0.82), "bloody": 0.4})
	_corpse(Vector3(11.8, 0, -29), 0.3, {"shirt": Color(0.15, 0.2, 0.3), "bloody": 0.5})
	Props.debris(geo, Vector3(3, 0, -12), 0.0, 4, "frost")
	for i in 3:
		_frost(Vector3(-3 + i * 3, 0, -9.5), Vector2(1.2, 0.8))
	pickup("l4_a_ammo1", "ammo_9mm", 3, Vector3(-2.2, 0.03, -14.4))
	pickup("l4_a_ammo2", "ammo_9mm", 2, Vector3(11.5, 0.03, -28.5))
	# MERIDIAN panel at the Hall C door
	_intercom(Vector3(-3.4, 0, -35.78), 0.0)
	_panel_lbl["hallc"] = label("HALL C  ·  LOCKED\nREQUEST: 40 kW REDUCTION", Vector3(-3.4, 1.82, -35.7), 0.0, 24, Color(1.0, 0.7, 0.3), 0.004)
	interact(Vector3(-3.4, 1.3, -35.0), "Use intercom (MERIDIAN)", func(_p): _request("hallc"), 1.8)
	door("l4_hallc", Vector3(0, 0, -36), 0.0, {"double": true, "width": 2.8, "height": 2.8, "mat": "metal", "lock_flag": "l4_grant_hallc",
		"locked_msg": "Locked. MERIDIAN controls this door. Use the intercom panel."})
	label("HALL C", Vector3(0, 3.2, -35.78), 0.0, 40, Color(0.7, 0.9, 1.2), 0.005)
	# electrical room door
	door("l4_elec", Vector3(-16, 0, -21.5), PI * 0.5, {"width": 2.0, "height": 2.6, "mat": "metal"})
	label("ELECTRICAL ROOM 2", Vector3(-15.8, 3.1, -21.5), PI * 0.5, 36, Color(1.0, 0.85, 0.3), 0.005)
	trigger("l4_hallc_hint", Vector3(0, 1.5, -31), Vector3(10, 3, 3), func(_p): _hallc_hint())

func _hallc_hint() -> void:
	lock_player(true)
	await say([["MERIDIAN", "Hall C is restricted. To grant access to Hall C, I require 40 kW of load reduction."],
		["ELIAS", "Reduce it from where?"],
		["MERIDIAN", "Electrical Room 2, west of Hall A, has manual feeder isolation. I do not recommend that you use it."],
		["MERIDIAN", "I am obliged to add that I will not stop you. Stopping you would not improve uptime."]])
	lock_player(false)
	Game.set_objective("Electrical Room 2 (west of Hall A): shed exactly 40 kW so MERIDIAN opens Hall C.")

# =================================================================== electrical room
func _electrical() -> void:
	glow(Vector3(-23, 3.9, -22), Color(0.85, 0.92, 1.0), 2.6, 14.0, true)
	glow(Vector3(-23, 3.4, -28), Color(0.85, 0.92, 1.0), 2.4, 9.0, false, true)
	glow(Vector3(-27, 3.6, -16), Color(0.85, 0.9, 1.0), 1.8, 9.0)
	glow(Vector3(-20, 3.6, -16), Color(0.85, 0.9, 1.0), 1.8, 9.0)
	strip(-23, -22, 8.0, true, HT - 0.04, Color(0.85, 0.92, 1.0))
	strip(-27, -22, 6.0, true, HT - 0.04, Color(0.85, 0.92, 1.0))
	# switchboard on the north wall
	Props.box(geo, Vector3(9.5, 3.0, 0.3), Vector3(-23, 1.7, -31.7), Mats.color(Color(0.22, 0.26, 0.28), 0.5, 0.5), true)
	label("MANUAL FEEDER ISOLATION", Vector3(-23, 3.7, -31.5), 0.0, 52, Color(1.0, 0.85, 0.3), 0.006, true)
	var defs := [["l4_sw_pdu7", -26.5, "PDU-7\nRACK ROW 7"], ["l4_sw_pdu9", -23.0, "PDU-9\nRACK ROW 9"], ["l4_sw_ch3", -19.5, "CH-3\nREDUNDANT CHILLER"]]
	for d in defs:
		_build_switch(d[0], d[1], d[2])
	_total_label = label("LOAD REDUCTION: 0 kW", Vector3(-23, 3.1, -31.5), 0.0, 56, Color(0.5, 1.0, 0.6), 0.008)
	label("OPEN REQUESTS\nHALL C ... 40 kW\nNOC ...... 54 kW", Vector3(-28.5, 1.9, -31.5), 0.0, 28, Color(0.9, 0.9, 0.95), 0.004, true)
	# transformers + cable reels + lockers
	for x in [-29.0]:
		for z in [-28.0, -24.0, -20.0]:
			Props.box(geo, Vector3(1.4, 1.9, 1.4), Vector3(x + 0.1, 0.95, z), Mats.color(Color(0.3, 0.34, 0.32), 0.6, 0.4), true)
			Props.cyl(geo, 0.1, 0.5, Vector3(x + 0.1, 2.15, z), Mats.color(Color(0.8, 0.8, 0.82), 0.3, 0.5), false)
			em(Vector3(x + 0.82, 1.6, z), Vector3(0.03, 0.08, 0.5), Color(0.2, 1.0, 0.4), 2.5)
	Props.cyl(geo, 0.6, 0.6, Vector3(-18.5, 0.3, -14.0), Mats.get_mat("wood"), true)
	Props.cyl(geo, 0.6, 0.6, Vector3(-18.5, 0.3, -15.2), Mats.get_mat("wood"), true)
	Props.locker(geo, Vector3(-26.0, 0, -12.6), PI, 4)
	Props.desk(geo, Vector3(-18.0, 0, -28.0), -PI * 0.5)
	Props.chair(geo, Vector3(-19.2, 0, -28.0), -PI * 0.5, false)
	Props.pipe(geo, Vector3(-29.8, 3.9, -31.8), Vector3(-29.8, 3.9, -12.2), 0.12, "metal")
	_corpse(Vector3(-20.5, 0, -16.5), 0.4, {"vest": true, "vest_color": Color(0.9, 0.5, 0.05), "shirt": Color(0.2, 0.3, 0.4), "bloody": 0.2, "skin": Color(0.62, 0.66, 0.7)})
	note("l4_slack", Vector3(-17.9, 0.8, -27.6), T.SLACK_TITLE, T.SLACK, 0.4)
	# the terminal (instructions)
	Props.box(geo, Vector3(0.8, 0.9, 0.5), Vector3(-17.2, 0.45, -24.0), Mats.get_mat("metal_painted"), true)
	Props.box(geo, Vector3(0.6, 0.35, 0.05), Vector3(-17.2, 1.05, -24.1), Mats.emissive(Color(0.25, 0.8, 0.5), 1.4), false, Vector3(0.3, 0, 0))
	interact(Vector3(-17.8, 0.9, -24.0), "Read the load-shed console", func(_p): UI.show_note(T.TERMINAL_TITLE, T.TERMINAL), 1.6)
	pickup("l4_e_gel", "gel", 1, Vector3(-26.0, 0.03, -13.4))
	pickup("l4_e_ammo", "ammo_9mm", 3, Vector3(-18.6, 0.03, -13.2))

func _build_switch(id: String, x: float, title: String) -> void:
	var kw: int = SW[id]
	Props.box(geo, Vector3(1.0, 1.2, 0.16), Vector3(x, 1.5, -31.45), Mats.color(Color(0.12, 0.13, 0.15), 0.5, 0.5), false)
	var lever := Props.box(geo, Vector3(0.1, 0.55, 0.1), Vector3(x, 1.5, -31.3), Mats.color(Color(0.85, 0.15, 0.1), 0.4, 0.3), false)
	lever.rotation.x = 0.6
	var lamp := Mats.emissive(Color(0.2, 1.0, 0.4), 3.0)
	Props.box(geo, Vector3(0.18, 0.1, 0.04), Vector3(x, 2.0, -31.35), lamp, false)
	var t := label("", Vector3(x, 2.45, -31.5), 0.0, 40, Color(0.9, 0.95, 1.0), 0.006)
	var k := label("%d kW" % kw, Vector3(x, 0.8, -31.35), 0.0, 90, Color(1.0, 0.85, 0.3), 0.008)
	_sw_lever[id] = lever
	_sw_lamp[id] = lamp
	_sw_text[id] = [t, title, kw, k]
	interact(Vector3(x, 1.3, -30.6), "Toggle %s (%d kW)" % [title.get_slice("\n", 0), kw], func(_p): _toggle_switch(id), 1.4)

func _toggle_switch(id: String) -> void:
	var off := Game.has_flag(id)
	if off:
		Game.flags.erase(id)
	else:
		Game.set_flag(id)
	Sfx.play("door_locked", -4.0, 1.4)
	Sfx.play("equip")
	_refresh_switches()
	var red := glow(Vector3(-23, 2.5, -30.5), Color(1.0, 0.3, 0.2), 4.0, 8.0)
	var tw := red.create_tween()
	tw.tween_property(red, "light_energy", 0.0, 0.5)
	tw.tween_callback(red.queue_free)
	UI.toast("%s: %s. Board total %d kW." % [_sw_text[id][1].get_slice("\n", 0), "ISOLATED" if not off else "RESTORED", _reduction()])
	if not _toggled_once:
		_toggled_once = true
		await get_tree().create_timer(1.2).timeout
		await say([["MERIDIAN", "Unscheduled manual load change detected. Logging. Please continue."]])

func _reduction() -> int:
	var t := 0
	for k in SW:
		if Game.has_flag(k):
			t += int(SW[k])
	return t

func _refresh_switches() -> void:
	for id in SW:
		var off := Game.has_flag(id)
		var lever: MeshInstance3D = _sw_lever.get(id)
		if lever:
			lever.rotation.x = -0.6 if off else 0.6
		var lamp: StandardMaterial3D = _sw_lamp.get(id)
		if lamp:
			var c := Color(1.0, 0.15, 0.1) if off else Color(0.2, 1.0, 0.4)
			lamp.albedo_color = c
			lamp.emission = c
		var tx: Array = _sw_text.get(id, [])
		if tx.size() > 0:
			(tx[0] as Label3D).text = "%s\n[%s]" % [tx[1], "SHED" if off else "ONLINE"]
			(tx[3] as Label3D).modulate = Color(1.0, 0.3, 0.2) if off else Color(1.0, 0.85, 0.3)
	if _total_label:
		var tot := _reduction()
		_total_label.text = "LOAD REDUCTION: %d kW" % tot
		var hit := tot == int(REQ.hallc) or tot == int(REQ.noc)
		_total_label.modulate = Color(1.0, 0.85, 0.2) if hit else Color(0.5, 1.0, 0.6)
	if _ch3_lamp:
		var off3 := Game.has_flag("l4_sw_ch3")
		var c3 := Color(1.0, 0.15, 0.1) if off3 else Color(0.2, 1.0, 0.4)
		_ch3_lamp.albedo_color = c3
		_ch3_lamp.emission = c3
		if _ch3_light:
			_ch3_light.light_color = c3

func _request(stage: String) -> void:
	var flag := "l4_grant_" + stage
	var need: int = int(REQ[stage])
	var where := "Hall C" if stage == "hallc" else "the Network Operations Centre"
	if Game.has_flag(flag):
		await say([["MERIDIAN", "Access to %s is already granted. Thank you for your cooperation." % where]])
		return
	var cur := _reduction()
	if cur == need:
		await say([["MERIDIAN", "Current reduction: %d kW. Request satisfied." % cur],
			["MERIDIAN", "Uptime impact: 0.0003%. Acceptable. Releasing the lock on %s." % where]])
		Game.set_flag(flag)
		Sfx.play("unlock")
		if _panel_lbl.has(stage):
			(_panel_lbl[stage] as Label3D).text = ("HALL C  ·  RELEASED" if stage == "hallc" else "NOC  ·  RELEASED")
			(_panel_lbl[stage] as Label3D).modulate = Color(0.4, 1.0, 0.5)
		if stage == "hallc":
			await say([["MERIDIAN", "You may restore the load afterwards. I will not notice. I notice everything else."]])
			Game.set_objective("Find the cooling plant (east of Hall C). Look for the plant key and the chiller overrides.")
		else:
			Game.set_objective("Enter the NOC. Talk to Dr. Hart.")
	elif cur < need:
		await say([["MERIDIAN", "To grant access to %s, I require %d kW of load reduction." % [where, need]],
			["MERIDIAN", "Current reduction: %d kW. Shortfall: %d kW. Please reduce load elsewhere." % [cur, need - cur]]])
	else:
		await say([["MERIDIAN", "Current reduction: %d kW. This exceeds the request by %d kW." % [cur, cur - need]],
			["MERIDIAN", "Excess reduction suggests a thermal event. I cannot open doors during a thermal event. Please restore %d kW." % (cur - need)]])

# =================================================================== hall C
func _hall_c() -> void:
	var z0 := -59.2
	var z1 := -37.0
	for r in [[-13.5, 1, 31], [-9.5, -1, 32], [-5.5, 1, 33], [5.5, -1, 34], [9.5, 1, 35], [13.5, -1, 36]]:
		_rack_row(r[0], z0, -49.6, r[1], r[2], 0.3)
		_rack_row(r[0], -45.0, z1, r[1], r[2] + 10, 0.3)
	for x in [-11.5, 0.0, 11.5]:
		_tray(x, -59.5, -36.5, 3.4 if x == 0.0 else 2.9)
	for z in [-57.0, -52.0, -47.5, -42.0, -38.5]:
		strip(0, z, 2.0, false, HT - 0.04, Color(0.7, 0.85, 1.0))
		strip(-11.5, z, 1.6, false, HT - 0.04, Color(0.65, 0.8, 1.0))
		strip(11.5, z, 1.6, false, HT - 0.04, Color(0.65, 0.8, 1.0))
	for z in [-55.0, -47.5, -40.0]:
		glow(Vector3(0, 3.9, z), Color(0.7, 0.85, 1.0), 1.5, 11.0, z == -47.5, z == -55.0)
		glow(Vector3(-11.5, 3.6, z), Color(0.65, 0.8, 1.0), 1.0, 8.0)
		glow(Vector3(11.5, 3.6, z), Color(0.65, 0.8, 1.0), 1.0, 8.0)
	for x in [-7.5, 7.5]:
		glow(Vector3(x, 3.4, -50), Color(1.0, 0.5, 0.2), 1.0, 6.0)
	_containment(-11.5, -59.2, 2.9, 0.0, "COLD AISLE C1")
	_containment(11.5, -59.2, 2.9, 0.0, "COLD AISLE C3")
	label("HALL C  ·  TRAINING CLUSTER 3", Vector3(0, 3.7, -59.7), PI, 60, Color(0.65, 0.88, 1.2), 0.006)
	for p in [Vector3(-3, 0, -47), Vector3(4, 0, -41), Vector3(2, 0, -56)]:
		_floor_hole(p)
	_corpse(Vector3(-1.5, 0, -52.5), 1.0, {"shirt": Color(0.2, 0.3, 0.4), "bloody": 0.6})
	_corpse(Vector3(8.0, 0, -47.2), 2.6, {"coat": true, "coat_color": Color(0.8, 0.8, 0.78), "bloody": 0.4})
	Props.debris(geo, Vector3(-4, 0, -39), 0.0, 5, "frost")
	pickup("l4_c_ammo", "ammo_9mm", 4, Vector3(-1.3, 0.03, -52.2))
	pickup("l4_c_shells", "ammo_shell", 4, Vector3(8.2, 0.03, -47.6))
	# plant door
	door("l4_plantdoor", Vector3(16, 0, -48), PI * 0.5, {"double": true, "width": 2.8, "height": 2.7, "mat": "metal"})
	label("COOLING PLANT", Vector3(15.8, 3.2, -48), -PI * 0.5, 40, Color(0.5, 0.8, 1.2), 0.005)
	label("COOLING PLANT  ->", Vector3(15.7, 2.2, -45), -PI * 0.5, 28, Color(0.7, 0.9, 1.1), 0.004)
	# the cable-tray hanger ambush trigger
	trigger("l4_hanger_music", Vector3(0, 1.5, -40), Vector3(12, 3, 2), func(_p): Sfx.music("music_tension"))

# =================================================================== cooling plant
func _plant() -> void:
	var cold := Color(0.55, 0.78, 1.0)
	for x in [20.0, 30.0, 40.0, 47.0]:
		glow(Vector3(x, 3.7, -48), cold, 1.6, 12.0, x == 30.0)
		strip(x, -48, 6.0, true, HT - 0.04, cold)
	for x in [24.0, 36.0, 44.0]:
		glow(Vector3(x, 3.5, -55), cold, 1.0, 9.0)
		glow(Vector3(x, 3.5, -39.5), cold, 0.9, 8.0)
	glow(Vector3(46, 3.0, -38), Color(1.0, 0.25, 0.15), 0.6, 5.0)
	# chillers
	var cx := [22.5, 31.5, 40.5]
	var names := ["CH-1", "CH-2", "CH-3"]
	var tank := Mats.color(Color(0.78, 0.84, 0.88), 0.3, 0.6)
	for i in 3:
		var x: float = cx[i]
		Props.box(geo, Vector3(6.4, 0.4, 3.2), Vector3(x, 0.2, -41.8), Mats.get_mat("concrete"), true)
		Props.cyl(geo, 1.45, 6.0, Vector3(x, 2.05, -41.8), tank, true, -1.0, Vector3(0, 0, PI * 0.5), 24)
		for s in [-1, 1]:
			Props.sphere(geo, 1.45, Vector3(x + s * 3.0, 2.05, -41.8), tank, Vector3(0.35, 1.0, 1.0))
		for k in 4:
			Props.cyl(geo, 1.5, 0.12, Vector3(x - 2.1 + k * 1.4, 2.05, -41.8), Mats.color(Color(0.3, 0.33, 0.37), 0.4, 0.7), false, -1.0, Vector3(0, 0, PI * 0.5), 24)
		Props.cyl(geo, 0.3, 1.4, Vector3(x, 4.1 - 0.2, -42.4), _m_insul, false)
		Props.box(geo, Vector3(1.0, 1.3, 0.5), Vector3(x + 1.5, 1.05, -39.8), Mats.get_mat("metal_painted"), true)
		label(names[i], Vector3(x, 3.75, -40.4), 0.0, 60, Color(0.7, 0.9, 1.2), 0.006)
		var lm := Mats.emissive(Color(0.2, 1.0, 0.4), 3.0)
		Props.box(geo, Vector3(0.22, 0.14, 0.04), Vector3(x + 1.5, 1.55, -39.53), lm, false)
		_frost(Vector3(x, 0, -39.0), Vector2(5.5, 1.3))
		_icicles(Vector3(x, 3.2, -40.5), 6, 2.5)
		if i == 2:
			_ch3_lamp = lm
			_ch3_light = glow(Vector3(x + 1.5, 1.6, -39.0), Color(0.2, 1.0, 0.4), 0.7, 3.0)
			label("REDUNDANT (N+1)\n40 kW", Vector3(x + 1.5, 2.2, -39.52), 0.0, 26, Color(1.0, 0.85, 0.3), 0.004)
	# main header and risers
	Props.pipe(geo, Vector3(16.5, 3.9, -38.2), Vector3(49.5, 3.9, -38.2), 0.38, "metal")
	Props.pipe(geo, Vector3(16.5, 3.3, -57.5), Vector3(49.5, 3.3, -57.5), 0.3, "metal_painted")
	for x in cx:
		Props.pipe(geo, Vector3(x, 3.5, -38.2), Vector3(x, 3.5, -42.4), 0.22, "metal")
	for x in [18.0, 27.0, 36.0, 45.0]:
		Props.pipe(geo, Vector3(x, 0.0, -57.5), Vector3(x, 3.3, -57.5), 0.15, "metal")
	_icicles(Vector3(30, 3.85, -38.2), 12, 12.0)
	_icicles(Vector3(30, 3.25, -57.5), 10, 12.0)
	# heat exchangers (north)
	for x in [21.0, 29.0]:
		Props.box(geo, Vector3(5.0, 2.8, 2.6), Vector3(x, 1.4, -56.0), Mats.color(Color(0.4, 0.45, 0.5), 0.5, 0.6), true)
		for k in 3:
			Props.cyl(geo, 0.7, 0.08, Vector3(x - 1.6 + k * 1.6, 2.85, -56.0), Mats.color(Color(0.1, 0.1, 0.12), 0.4, 0.6), false)
		_frost(Vector3(x, 0, -53.8), Vector2(4.4, 1.1))
	Props.box(geo, Vector3(2.0, 1.6, 1.4), Vector3(34.5, 0.8, -55.5), Mats.get_mat("metal_painted"), true)
	Props.cyl(geo, 0.5, 1.4, Vector3(34.5, 2.2, -55.5), _m_insul, true)
	for p in [Vector3(25, 0, -46), Vector3(36, 0, -47), Vector3(18.5, 0, -51)]:
		_frost(p, Vector2(3.0, 2.2))
	Props.barrel(geo, Vector3(18.4, 0, -37.2), 0.3)
	Props.crate(geo, Vector3(49.0, 0, -50.0), 0.3, 0.9)
	Props.crate(geo, Vector3(49.0, 0, -51.0), 0.2, 0.8)
	label("COOLING PLANT 1\nWATCH FOR ICE ON PIPEWORK", Vector3(16.2, 2.6, -53), PI * 0.5, 34, Color(1.0, 0.85, 0.3), 0.005, true)
	# override cabinet + containment door
	Props.box(geo, Vector3(1.6, 2.2, 0.4), Vector3(38.0, 1.1, -59.7), Mats.color(Color(0.5, 0.1, 0.08), 0.5, 0.4), true)
	label("CHILLER OVERRIDE\nKEY REQUIRED", Vector3(38.0, 1.5, -59.47), 0.0, 32, Color(1.0, 0.9, 0.8), 0.004, true)
	Props.box(geo, Vector3(0.2, 0.2, 0.05), Vector3(38.0, 1.1, -59.48), Mats.emissive(Color(1.0, 0.15, 0.1), 3.0), false)
	interact(Vector3(38.0, 1.2, -58.9), "Chiller override cabinet", func(_p): _override_cabinet(), 1.8)
	door("l4_contain", Vector3(44, 0, -60), 0.0, {"double": true, "width": 2.6, "height": 2.7, "mat": "metal", "lock_flag": "l4_override",
		"locked_msg": "Containment door sealed. The chiller override has to be engaged first."})
	label("COLD AISLE CONTAINMENT", Vector3(44, 3.15, -59.78), 0.0, 36, Color(0.6, 0.85, 1.2), 0.005)
	# coolant key on a dead technician
	_corpse(Vector3(27.0, 0, -49.8), 0.7, {"vest": true, "vest_color": Color(0.9, 0.5, 0.05), "shirt": Color(0.2, 0.3, 0.4), "bloody": 0.2, "skin": Color(0.62, 0.68, 0.74)})
	_frost(Vector3(27.0, 0, -49.8), Vector2(2.4, 1.6))
	pickup("l4_coolant_key", "coolant_key", 1, Vector3(27.6, 0.05, -49.4))
	pickup("l4_p_shells", "ammo_shell", 6, Vector3(18.6, 0.03, -37.9))
	pickup("l4_p_gel", "gel", 1, Vector3(48.8, 0.03, -57.0))
	trigger("l4_plant_enter", Vector3(18.5, 1.5, -48), Vector3(2, 3, 3), func(_p): _plant_enter())
	trigger("l4_plant_wake", Vector3(30, 1.5, -47), Vector3(10, 3, 6), func(_p): _wake_husks())

func _plant_enter() -> void:
	Sfx.music("music_tension")
	UI.toast("The air in here is far below freezing.")

func _wake_husks() -> void:
	for e in _wake_group:
		if is_instance_valid(e) and e.has_method("wake"):
			e.wake()

func _override_cabinet() -> void:
	if Game.has_flag("l4_override"):
		UI.toast("The overrides are already engaged.")
		return
	if not Game.has_item("coolant_key"):
		UI.toast("Locked. It takes the red cooling plant key.")
		Sfx.play("door_locked")
		return
	Game.remove_item("coolant_key", 1)
	_engage_override()

func _engage_override() -> void:
	Game.set_flag("l4_override")
	Sfx.play("unlock")
	UI.toast("Chiller overrides engaged. Containment door released.")
	lock_player(true)
	await say([["MERIDIAN", "Manual chiller override detected. This is an unusual choice."],
		["MERIDIAN", "I will log it as 'maintenance'. Containment door seals are released."]])
	lock_player(false)
	_start_breach()

func _start_breach() -> void:
	Game.set_flag("l4_breach")
	for z in _corr_zombies:
		if is_instance_valid(z):
			z.wake()
	_breach_t = 0.0
	await say([["IMOGEN (muffled)", "Whoever just opened the cold-aisle seal, they heard it! They're at the glass!"],
		["IMOGEN (muffled)", "Clear the corridor. Fast. I can't hold this barricade."]])
	Game.set_objective("Clear the corridor north of the plant before the barricade at the NOC gives.")

# =================================================================== armory
func _armory() -> void:
	glow(Vector3(42, 3.6, -29), Color(1.0, 0.82, 0.6), 1.3, 9.0, true)
	glow(Vector3(37, 3.2, -25), Color(1.0, 0.25, 0.15), 0.5, 5.0)
	strip(42, -29, 7.0, false, HT - 0.04, Color(1.0, 0.9, 0.8))
	door("l4_armory", Vector3(46, 0, -36), 0.0, {"width": 1.8, "height": 2.6, "mat": "metal_painted", "lock_item": "badge_meridian", "keep_key": true,
		"locked_msg": "SECURITY ARMORY. Badge reader: ACCESS DENIED."})
	label("SECURITY ARMORY", Vector3(46, 3.0, -35.78), 0.0, 36, Color(1.0, 0.4, 0.3), 0.005)
	Props.locker(geo, Vector3(41, 0, -22.4), PI, 3)
	Props.locker(geo, Vector3(46, 0, -22.4), PI, 3)
	Props.shelf(geo, Vector3(49.6, 0, -29), -PI * 0.5, 3.0, 2.0, false)
	Props.crate(geo, Vector3(35.0, 0, -35.0), 0.4, 0.8)
	Props.table(geo, Vector3(42, 0, -26.5), 0.0, Vector2(2.2, 0.9))
	Props.chair(geo, Vector3(40.4, 0, -28.0), 2.0, true)
	Props.box(geo, Vector3(0.9, 0.12, 0.35), Vector3(37.0, 1.5, -35.82), Mats.color(Color(0.2, 0.2, 0.22), 0.4, 0.6), false)
	_corpse(Vector3(38.0, 0, -31.0), 0.5, {"vest": true, "shirt": Color(0.1, 0.12, 0.22), "pants": Color(0.08, 0.1, 0.18), "bloody": 0.3, "skin": Color(0.62, 0.66, 0.72)})
	pickup("l4_launcher", "launcher", 1, Vector3(41.6, 0.82, -26.5))
	pickup("l4_flares", "ammo_grenade", 4, Vector3(42.6, 0.82, -26.6))
	pickup("l4_arm_kit", "spray", 1, Vector3(41.2, 0.03, -23.1))
	pickup("l4_arm_9mm", "ammo_9mm", 4, Vector3(46.2, 0.03, -23.1))

# =================================================================== corridor
func _corridor() -> void:
	for x in range(-24, 50, 8):
		strip(float(x), -63, 2.4, false, HT - 0.04, Color(0.78, 0.88, 1.0))
		glow(Vector3(x, 3.9, -63), Color(0.75, 0.88, 1.0), 1.1, 8.0, x == 8)
	Props.box(geo, Vector3(80, 0.05, 0.7), Vector3(10, 3.4, -60.7), _m_tray, false)
	Props.box(geo, Vector3(80, 0.1, 0.5), Vector3(10, 3.48, -60.7), Mats.color(Color(0.04, 0.04, 0.05), 0.6), false)
	Props.pipe(geo, Vector3(-29.8, 0.4, -61.0), Vector3(49.8, 0.4, -61.0), 0.1, "metal")
	Props.pipe(geo, Vector3(-29.8, 3.9, -65.5), Vector3(49.8, 3.9, -65.5), 0.14, "metal_painted")
	# yellow floor line + cameras with blue eyes
	Props.box(geo, Vector3(79, 0.012, 0.1), Vector3(10, 0.012, -63), Mats.color(Color(0.9, 0.75, 0.1), 0.6), false)
	for x in [-20.0, -2.0, 24.0, 40.0]:
		Props.box(geo, Vector3(0.3, 0.2, 0.3), Vector3(x, 3.6, -65.85), Mats.color(Color(0.1, 0.1, 0.12), 0.4, 0.6), false)
		Props.sphere(geo, 0.05, Vector3(x, 3.6, -65.68), Mats.emissive(Color(0.2, 0.6, 1.0), 5.0))
	label("NETWORK OPERATIONS CENTRE  ->", Vector3(-12.0, 3.3, -65.8), 0.0, 36, Color(0.7, 0.9, 1.2), 0.005)
	label("<-  HR-1 PIPELINE HEAD", Vector3(18.0, 3.5, -65.8), 0.0, 36, Color(1.0, 0.7, 0.3), 0.005)
	label("<-  PLANT / HALLS", Vector3(40.0, 3.3, -65.8), 0.0, 30, Color(0.7, 0.9, 1.2), 0.004)
	# the NOC door panel
	_intercom(Vector3(-3.2, 0, -65.78), 0.0)
	_panel_lbl["noc"] = label("NOC  ·  SEALED\nREQUEST: 54 kW REDUCTION", Vector3(-3.2, 1.82, -65.7), 0.0, 24, Color(1.0, 0.7, 0.3), 0.004)
	interact(Vector3(-3.2, 1.3, -65.0), "Use intercom (MERIDIAN)", func(_p): _request("noc"), 1.8)
	door("l4_noc", Vector3(-6, 0, -66), 0.0, {"width": 2.2, "height": 2.6, "mat": "metal", "lock_flag": "l4_grant_noc",
		"locked_msg": "Sealed. MERIDIAN holds this door. Use the intercom panel."})
	Props.debris(geo, Vector3(-18, 0, -63), 0.0, 5, "frost")
	_corpse(Vector3(30, 0, -64), 0.8, {"shirt": Color(0.4, 0.15, 0.1), "bloody": 0.6})
	_frost(Vector3(44, 0, -62), Vector2(3.5, 2.0))
	pickup("l4_k_ammo", "ammo_9mm", 3, Vector3(29.4, 0.03, -63.5))
	trigger("l4_noc_glass", Vector3(-6, 1.5, -62.5), Vector3(5, 3, 2.5), func(_p): _noc_glass())

func _noc_glass() -> void:
	if Game.has_flag("imogen_taken"):
		return
	lock_player(true)
	await say([["IMOGEN (muffled)", "You're not one of them. They don't use the intercom. Ask MERIDIAN."],
		["IMOGEN (muffled)", "It will want 54 kW off the board for my door. It cannot lie. Do the sum."]])
	lock_player(false)
	if not Game.has_flag("l4_grant_noc"):
		Game.set_objective("Shed exactly 54 kW in Electrical Room 2, then ask MERIDIAN to open the NOC.")

# =================================================================== NOC
func _noc() -> void:
	glow(Vector3(-6, 3.9, -75), Color(0.7, 0.85, 1.0), 1.5, 14.0, true)
	glow(Vector3(-6, 2.2, -82), Color(0.3, 0.6, 1.0), 2.5, 12.0)
	strip(-9, -74, 8.0, true, HT - 0.04, Color(0.75, 0.88, 1.0))
	strip(-3, -74, 8.0, true, HT - 0.04, Color(0.75, 0.88, 1.0))
	# video wall
	var cols := [Color(0.1, 0.35, 0.7), Color(0.05, 0.5, 0.45), Color(0.15, 0.25, 0.6), Color(0.6, 0.35, 0.05), Color(0.05, 0.4, 0.65)]
	for r in 2:
		for c in 5:
			var col: Color = cols[(r * 2 + c) % cols.size()]
			Props.box(geo, Vector3(2.7, 1.5, 0.08), Vector3(-6 + (c - 2) * 2.85, 1.2 + r * 1.65, -83.78), Mats.emissive(col, 1.4), false)
	label("UPTIME 99.9997%", Vector3(-6, 3.0, -83.7), 0.0, 100, Color(0.9, 1.0, 1.3), 0.008)
	label("GRID: KETTLE FALLS FEEDER  — SHED\nSITE LOAD 40.2 MW  ·  PRIORITY: 1", Vector3(-11.0, 1.4, -83.7), 0.0, 24, Color(0.8, 0.95, 1.0), 0.004)
	label("HR-1 SUPPLY 96 °C\nRETURN  −2 °C  (!)", Vector3(-1.6, 1.4, -83.7), 0.0, 24, Color(1.0, 0.7, 0.4), 0.004)
	# consoles
	for r in 2:
		for c in 3:
			var x := -10.0 + c * 3.8
			var z := -76.0 + r * 2.5
			Props.desk(geo, Vector3(x, 0, z), PI)
	glass_mullions()
	var taken := Game.has_flag("imogen_taken")
	if taken:
		# barricade smashed, blood, empty cot. The card is on her desk.
		Props.chair(geo, Vector3(-9.3, 0, -68.8), 1.0, true)
		Props.cabinet(geo, Vector3(-11.5, 0, -68.0), 0.9)
		Props.debris(geo, Vector3(-9, 0, -68.6), 0.0, 6, "metal")
		Props.blood_pool(geo, Vector3(-8.0, 0, -71.0), 2.0)
		Props.blood_pool(geo, Vector3(-5.0, 0, -74.0), 1.4)
		pickup("l4_card_desk", "pipeline_card", 1, Vector3(-11.7, 0.8, -79.2))
		note("l4_taken_note", Vector3(-12.0, 0.8, -78.6), "Hart's recorder (transcript)", "[b]Voice memo — I. Hart[/b]\n\nIf you are reading this, they got in. The seal on the cold aisle went and I couldn't move the cabinets fast enough.\n\nThe card is on the desk. It opens the pipeline service tunnel. Go down. The colony is on the pipe walls. If anyone gets a sample, label it HART / BP-7 and make them read the whole report.\n\nTell Ruth Kade's boy I'm sorry. He'll know what that means.")
	else:
		# barricade of desks and cabinets piled each side of the door (a 1.8 m gap stays clear)
		Props.cabinet(geo, Vector3(-11.0, 0, -67.2), 0.1)
		Props.desk(geo, Vector3(-10.0, 0, -68.0), 0.4)
		Props.cabinet(geo, Vector3(-12.2, 0, -68.3), 1.2)
		Props.desk(geo, Vector3(-2.2, 0, -67.6), -0.3)
		Props.cabinet(geo, Vector3(-0.8, 0, -67.2), 0.0)
		Props.chair(geo, Vector3(-3.3, 0, -68.6), 0.3, true)
		_imogen = _make_npc("imogen", Vector3(-9.0, 0, -80.0), PI, {"female": true, "coat": true, "coat_color": Color(0.9, 0.9, 0.92), "hair_style": "ponytail", "height": 1.68, "shirt": Color(0.5, 0.2, 0.2)})
		interact(Vector3(-9.0, 1.0, -79.0), "Talk to Dr. Hart", func(_p): _talk_imogen(), 2.2)
	Props.box(geo, Vector3(1.6, 0.9, 0.7), Vector3(-12.2, 0.45, -80.6), Mats.color(Color(0.35, 0.37, 0.4), 0.6), true)
	Props.cabinet(geo, Vector3(-13.5, 0, -83.4), 0.0)
	Props.box(geo, Vector3(0.9, 0.08, 1.9), Vector3(-1.2, 0.35, -81.0), Mats.color(Color(0.2, 0.3, 0.2), 0.9), false)
	Props.cyl(geo, 0.06, 0.3, Vector3(-0.2, 0.15, -80.0), Mats.get_mat("metal"), false)
	note("l4_report", Vector3(-12.0, 0.92, -80.4), T.REPORT_TITLE, T.REPORT, 0.2)
	trigger("l4_noc_in", Vector3(-6, 1.5, -68.5), Vector3(5, 3, 2), func(_p): Sfx.music("music_tension"), false)

func glass_mullions() -> void:
	var fm := Mats.color(Color(0.7, 0.72, 0.76), 0.4, 0.6)
	for x in [-14.0, -10.0, -2.0, 2.0]:
		Props.box(geo, Vector3(0.14, 4.5, 0.3), Vector3(x, 2.25, -66), fm, false)
	Props.box(geo, Vector3(16.0, 0.14, 0.3), Vector3(-6, 2.9, -66), fm, false)

func _talk_imogen() -> void:
	lock_player(true)
	if not Game.has_flag("met_imogen"):
		await say([["IMOGEN", "Stop there. Hands where I can see them. ...Breath fog. A pulse, I'd guess. Good enough."],
			["ELIAS", "Elias Kade, Lakeshore Electric. I'm looking for my daughter. Fifteen, parka, knit hat. June."],
			["IMOGEN", "Kade. ...A woman in her sixties and a girl in a hat came through the loading dock eleven hours ago."],
			["IMOGEN", "MERIDIAN let them in. It doesn't count people who aren't in the badge database."],
			["ELIAS", "Where did they go?"],
			["IMOGEN", "Down the pipeline service tunnel. Into Lower Kettle. It's the only warm road in this town. The Rime follows warm."],
			["ELIAS", "The Rime."],
			["IMOGEN", "Imogen Hart, Northline geology. Eight months ago I cored a brine pocket and found something alive in it. Ten thousand years dormant."],
			["IMOGEN", "I filed the report. Northline and Corvane buried it under three NDAs and a bonus. Then they piped this building's waste heat down that shaft."],
			["IMOGEN", "Forty megawatts of warmth, delivered to a thing that eats heat. It woke. It's growing up the pipe toward everything warm."],
			["ELIAS", "Three nights ago the grid dropped the whole town to keep this place running."],
			["IMOGEN", "Section 4.2. Priority load. The town was cheaper to turn off."]])
		Game.set_flag("met_imogen")
	if not Game.has_flag("l4_card_given"):
		if not Game.can_add("pipeline_card"):
			await say([["IMOGEN", "Your pockets are full. Drop something. I'm not carrying this for you."]])
			lock_player(false)
			return
		await say([["IMOGEN", "Take this. Pipeline override card. It opens the service tunnel at the pipeline head."]])
		Game.add_item("pipeline_card", 1)
		Game.set_flag("l4_card_given")
		Sfx.play("pickup")
		UI.show_item_get("pipeline_card")
		await say([["IMOGEN", "One thing. The colony coats the pipe walls. Scrape me a sample. A glove, a vial, anything. Proof."],
			["ELIAS", "I'm going down for my family, doctor. Not for evidence."],
			["IMOGEN", "Then bring it by accident. And be careful with MERIDIAN. It never lies. It just never cares."]])
		Game.set_flag("imogen_wants_sample")
		Game.set_objective("Take the pipeline service tunnel (pipeline head, east of the NOC) down to the mine.")
	else:
		await say([["IMOGEN", "Go. The warm air is a lie. Every degree it gives you, it takes back from them."]])
	lock_player(false)

# =================================================================== break room (safe room)
func _break_room() -> void:
	var amber := Color(1.0, 0.78, 0.5)
	glow(Vector3(-22, 3.4, -73), amber, 2.2, 13.0, true)
	glow(Vector3(-27, 3.0, -77), amber, 1.0, 7.0)
	Props.sphere(geo, 0.12, Vector3(-22, 4.1, -73), Mats.emissive(amber, 3.0))
	Props.cyl(geo, 0.02, 0.4, Vector3(-22, 4.3, -73), Mats.get_mat("metal"), false)
	Props.box(geo, Vector3(15.6, 0.02, 13.6), Vector3(-22, 0.01, -73), Mats.get_mat("carpet", 2.0), false)
	Props.couch(geo, Vector3(-27.0, 0, -71.0), PI * 0.5, Color(0.35, 0.2, 0.15))
	Props.table(geo, Vector3(-24.0, 0, -74.0), 0.0, Vector2(1.8, 0.9))
	Props.chair(geo, Vector3(-24.0, 0, -72.9), PI, false)
	Props.chair(geo, Vector3(-25.0, 0, -75.2), 0.3, false)
	Props.vending(geo, Vector3(-29.1, 0, -77.5), PI * 0.5, true)
	Props.vending(geo, Vector3(-29.1, 0, -76.0), PI * 0.5, true)
	Props.cabinet(geo, Vector3(-16.5, 0, -67.2), PI)
	Props.locker(geo, Vector3(-19.0, 0, -79.5), 0.0, 3)
	Props.bed(geo, Vector3(-28.4, 0, -68.0), 0.0)
	Props.box(geo, Vector3(0.35, 0.4, 0.3), Vector3(-23.0, 0.95, -74.0), Mats.color(Color(0.8, 0.8, 0.82), 0.3, 0.5), false)
	save_point(Vector3(-24.8, 0.76, -74.0), 0.0)
	item_box(Vector3(-22.0, 0, -79.3), 0.0)
	label("BREAK ROOM", Vector3(-14.0 - 0.14, 3.1, -74), PI * 0.5, 40, Color(1.0, 0.85, 0.6), 0.005, true)
	label("Whoever last used the microwave: 99.9997% of us hate you.", Vector3(-29.85, 1.9, -72), PI * 0.5, 24, Color(0.9, 0.85, 0.7), 0.004, true)
	pickup("l4_b_pk", "adrenaline", 1, Vector3(-24.2, 0.77, -74.4))
	pickup("l4_b_flare", "flare", 2, Vector3(-18.6, 0.03, -78.6))
	var sz := Area3D.new()
	sz.add_to_group("safe_zone")
	sz.collision_layer = 0
	sz.collision_mask = 2
	sz.position = Vector3(-22, 1.5, -73)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(15.5, 3.2, 13.5)
	cs.shape = bs
	sz.add_child(cs)
	add_child(sz)
	trigger("l4_safe_music", Vector3(-20, 1.5, -73), Vector3(10, 3, 12), func(_p): Sfx.music("music_safe"), false)
	trigger("l4_safe_leave", Vector3(-10, 1.5, -74), Vector3(2, 3, 3), func(_p): Sfx.music("music_tension"), false)

# =================================================================== pipeline head
func _pipeline_head() -> void:
	var warm := Color(1.0, 0.62, 0.3)
	glow(Vector3(18, 7.5, -80), Color(0.8, 0.9, 1.0), 2.0, 22.0, true)
	glow(Vector3(18, 1.2, -88), warm, 4.0, 14.0, true)
	glow(Vector3(10, 3.0, -72), Color(0.75, 0.88, 1.0), 1.2, 10.0)
	glow(Vector3(26, 3.0, -72), Color(0.75, 0.88, 1.0), 1.2, 10.0)
	for x in [10.0, 18.0, 26.0]:
		strip(x, -78, 8.0, true, PH_H - 0.04, Color(0.8, 0.92, 1.0))
	# the pipe: horizontal run from the west wall, elbow, vertical drop into a concrete collar
	var jacket := _m_insul
	var band := Mats.color(Color(0.9, 0.55, 0.12), 0.5, 0.2)
	Props.box(geo, Vector3(7.0, 0.6, 7.0), Vector3(18, 0.3, -88), Mats.get_mat("concrete"), true)
	Props.cyl(geo, 3.4, 0.5, Vector3(18, 0.65, -88), Mats.get_mat("concrete"), true, -1.0, Vector3.ZERO, 32)
	Props.cyl(geo, 1.5, 6.4, Vector3(18, 4.15, -88), jacket, true, -1.0, Vector3.ZERO, 28)
	Props.sphere(geo, 1.5, Vector3(18, 7.35, -88), jacket)
	Props.cyl(geo, 1.5, 12.2, Vector3(12, 7.35, -88), jacket, true, -1.0, Vector3(0, 0, PI * 0.5), 28)
	for y in [1.6, 3.2, 4.8, 6.4]:
		Props.cyl(geo, 1.56, 0.22, Vector3(18, y, -88), band, false, -1.0, Vector3.ZERO, 28)
	for x in [7.5, 10.5, 13.5, 16.0]:
		Props.cyl(geo, 1.56, 0.22, Vector3(x, 7.35, -88), band, false, -1.0, Vector3(0, 0, PI * 0.5), 28)
	label("HR-1\n96 °C", Vector3(18, 3.2, -86.46), 0.0, 90, Color(1.0, 0.7, 0.3), 0.007)
	# glow at the base: the heat going into the ground
	Props.cyl(geo, 2.0, 0.04, Vector3(18, 0.93, -88), Mats.emissive(Color(1.0, 0.45, 0.12), 3.0), false, -1.0, Vector3.ZERO, 32)
	# railing ring
	for i in 16:
		var a := i * TAU / 16.0
		if a > PI * 0.35 and a < PI * 0.65:
			continue
		var p := Vector3(18 + sin(a) * 4.4, 0, -88 + cos(a) * 4.4)
		Props.cyl(geo, 0.04, 1.1, p + Vector3(0, 0.55, 0), Mats.get_mat("metal_painted"), false)
		var a2 := (i + 1) * TAU / 16.0
		var p2 := Vector3(18 + sin(a2) * 4.4, 0, -88 + cos(a2) * 4.4)
		if not (a2 > PI * 0.35 and a2 < PI * 0.65):
			Props.pipe(geo, p + Vector3(0, 1.05, 0), p2 + Vector3(0, 1.05, 0), 0.03, "metal_painted")
	# return line, frosted on the outside (and, someone says, the inside)
	var ret := Mats.color(Color(0.55, 0.7, 0.85), 0.35, 0.6)
	Props.cyl(geo, 0.7, 7.4, Vector3(26, 3.7, -92), ret, true, -1.0, Vector3.ZERO, 20)
	Props.cyl(geo, 0.76, 6.6, Vector3(26, 3.4, -92), Mats.get_mat("frost", 1.0), false, -1.0, Vector3.ZERO, 20)
	_icicles(Vector3(26, 4.3, -91.4), 8, 0.5)
	_frost(Vector3(26, 0, -92), Vector2(3.5, 3.5))
	Props.cyl(geo, 0.7, 5.0, Vector3(21.5, 7.0, -92), ret, false, -1.0, Vector3(0, 0, PI * 0.5), 20)
	# signage
	label("NORTHLINE GEOTHERMAL RECOVERY", Vector3(18, 6.4, -97.78), 0.0, 120, Color(1.0, 0.78, 0.35), 0.01)
	label("PROJECT WARMTH", Vector3(18, 4.6, -97.78), 0.0, 200, Color(1.0, 0.6, 0.25), 0.012)
	label("HEAT RECOVERY HEADER HR-1  ·  AUTHORISED PERSONNEL ONLY", Vector3(18, 3.45, -97.78), 0.0, 36, Color(0.85, 0.9, 1.0), 0.005)
	label("A GREENER KETTLE FALLS", Vector3(18, 7.4, -97.78), 0.0, 60, Color(0.75, 0.95, 0.8), 0.007)
	label("HR-1 SUPPLY\nTO LOWER KETTLE MINE\n2.4 km", Vector3(7.2, 2.4, -78), PI * 0.5, 30, Color(1.0, 0.8, 0.4), 0.005)
	# steam from the collar
	var st := CPUParticles3D.new()
	st.amount = 40
	st.lifetime = 3.0
	st.direction = Vector3.UP
	st.spread = 25.0
	st.initial_velocity_min = 0.4
	st.initial_velocity_max = 0.9
	st.gravity = Vector3(0, 0.15, 0)
	st.scale_amount_min = 0.25
	st.scale_amount_max = 0.7
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	st.mesh = sm
	var stm := Mats.color(Color(1.0, 0.9, 0.8, 0.12), 1.0)
	stm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	st.material_override = stm
	st.position = Vector3(18, 1.0, -85.2)
	add_child(st)
	# dressing
	Props.crate(geo, Vector3(8.5, 0, -70), 0.3, 0.9)
	Props.crate(geo, Vector3(9.5, 0, -70.6), 0.9, 0.7)
	Props.barrel(geo, Vector3(28.6, 0, -70.0), 0.2)
	Props.barrel(geo, Vector3(28.0, 0, -71.2), 1.2)
	_corpse(Vector3(14.0, 0, -76.0), 0.2, {"vest": true, "vest_color": Color(0.9, 0.5, 0.05), "shirt": Color(0.2, 0.3, 0.4), "bloody": 0.3, "skin": Color(0.6, 0.66, 0.72)})
	note("l4_pr", Vector3(11.0, 0.9, -70.1), T.PR_TITLE, T.PR, 0.5)
	Props.table(geo, Vector3(11.0, 0, -70.1), 0.0, Vector2(1.2, 0.7))
	# card reader + exit door
	Props.box(geo, Vector3(0.35, 0.55, 0.12), Vector3(20.8, 1.35, -97.8), Mats.color(Color(0.1, 0.11, 0.14), 0.4, 0.5), false)
	Props.box(geo, Vector3(0.22, 0.08, 0.02), Vector3(20.8, 1.5, -97.72), Mats.emissive(Color(1.0, 0.3, 0.1), 3.0), false)
	label("PIPELINE SERVICE TUNNEL", Vector3(18, 3.0, -97.78), 0.0, 40, Color(1.0, 0.9, 0.3), 0.005)
	interact(Vector3(20.6, 1.3, -97.0), "Swipe override card", func(_p): _card_reader(), 1.8)
	door("l4_exit", Vector3(18, 0, -98), 0.0, {"width": 2.4, "height": 2.6, "mat": "metal_painted", "double": true, "lock_flag": "pipeline_open", "to_level": "l5_mine", "to_spawn": "start",
		"locked_msg": "Locked. The reader wants the pipeline override card."})
	trigger("l4_ph_enter", Vector3(18, 1.5, -69), Vector3(6, 3, 2), func(_p): _ph_enter())

func _ph_enter() -> void:
	Sfx.music("music_tension")
	if Game.has_flag("pipeline_open"):
		return
	Game.set_objective("Swipe the pipeline override card at the service tunnel door.")

func _card_reader() -> void:
	if Game.has_flag("pipeline_open"):
		UI.toast("The tunnel door is already unlocked.")
		return
	if not Game.has_item("pipeline_card"):
		UI.toast("Card reader: ACCESS DENIED. It needs the pipeline override card.")
		Sfx.play("door_locked")
		return
	await _open_pipeline()

func _open_pipeline() -> void:
	Game.remove_item("pipeline_card", 1)
	Game.set_flag("pipeline_open")
	Sfx.play("unlock")
	lock_player(true)
	await say([["MERIDIAN", "Pipeline override accepted. Welcome to Project Warmth, Mr. Kade. Please mind the grating."],
		["MERIDIAN", "I have computed the town's surviving population against the cost of cutting heat recovery. Forty-one people."],
		["MERIDIAN", "Cutting the heat to save them costs 0.03% uptime per survivor-hour. I have declined, politely."],
		["MERIDIAN", "Two unregistered persons entered the tunnel at 02:14. Their body heat was added to the return-water load."],
		["MERIDIAN", "The tunnel is thirty-one degrees Celsius. You will be comfortable for approximately four minutes. Please close the door. Heat escapes."]])
	lock_player(false)
	Game.set_objective("Go down the pipeline service tunnel.")

func try_use_item(id: String) -> bool:
	if id == "coolant_key" and _near(Vector3(38.0, 1.2, -59.0), 4.0) and not Game.has_flag("l4_override"):
		Game.remove_item("coolant_key", 1)
		_engage_override()
		return true
	if id == "pipeline_card" and _near(Vector3(20.6, 1.3, -97.0), 4.0) and not Game.has_flag("pipeline_open"):
		_open_pipeline()
		return true
	UI.toast("There is nothing to use it on here.")
	return false

# =================================================================== enemies & state
func _enemies() -> void:
	enemy("l4_zA1", "zombie", Vector3(-3, 0, -28), 0.5, {"variant": "worker"})
	enemy("l4_zA2", "zombie", Vector3(7, 0, -13), 3.0, {"variant": "civilian"})
	enemy("l4_zC1", "zombie", Vector3(-4, 0, -44), 1.0, {"variant": "worker"})
	enemy("l4_zC2", "zombie", Vector3(6, 0, -55), 2.0, {"variant": "civilian", "crawler": true})
	enemy("l4_hanger", "hanger", Vector3(0, HT - 0.6, -47.5), 0.0, {"on_ceiling": true})
	var breach := Game.has_flag("l4_breach")
	for d in [["l4_zK1", Vector3(12, 0, -63), "worker"], ["l4_zK2", Vector3(-9, 0, -64.4), "civilian"]]:
		var e = enemy(d[0], "zombie", d[1], 1.0, {"variant": d[2], "dormant": not breach})
		if e != null:
			_corr_zombies.append(e)
			_corr_alive += 1
			e.died.connect(func(_x): _corr_alive -= 1)
	for d in [["l4_h1", Vector3(26, 0, -46)], ["l4_h2", Vector3(35, 0, -51)], ["l4_h3", Vector3(44, 0, -45)]]:
		var h = enemy(d[0], "husk", d[1], randf() * TAU, {})
		if h != null:
			_wake_group.append(h)
	enemy("l4_b1", "burster", Vector3(29, 0, -52.5), 0.0, {})
	enemy("l4_b2", "burster", Vector3(36.5, 0, -38.0), 0.0, {})

func _restore_state() -> void:
	# re-entering after the breach started: settle Imogen's fate
	if Game.has_flag("l4_breach") and not Game.has_flag("imogen_alive") and not Game.has_flag("imogen_taken"):
		if _corr_alive <= 0:
			Game.set_flag("imogen_alive")
		else:
			_breach_t = 0.0
	# the Foreman is already out if the launcher has been taken
	if Game.has_flag("got:l4_launcher") and not Game.has_flag("dead:l4_foreman"):
		_spawn_foreman()

func _spawn_foreman() -> void:
	if _foreman != null and is_instance_valid(_foreman):
		return
	_foreman = enemy("l4_foreman", "foreman", Vector3(0, 0, -30), 0.0, {"stalk": true, "leave_after": 20.0})

func on_pickup(item: String, _uid: String) -> void:
	if item == "launcher":
		_foreman_arrives()

func _foreman_arrives() -> void:
	await get_tree().create_timer(2.5).timeout
	lock_player(true)
	await say([["MERIDIAN", "Notice: an unregistered entity, 2.6 metres, has entered Hall A. It is not in the occupancy database."],
		["MERIDIAN", "It is carrying a lamp. I have classified it as 'maintenance'. Please do not engage it near the racks."]])
	lock_player(false)
	Sfx.music("music_tension")
	_spawn_foreman()
	if not Game.has_flag("l4_override"):
		Game.set_objective("The Foreman is hunting the server aisles. Fire drives him off. Engage the chiller override.")

# =================================================================== on_enter
func on_enter() -> void:
	Sfx.ambience("amb_datacenter")
	Sfx.music("")
	if not Game.has_flag("l4_intro"):
		Game.set_flag("l4_intro")
		UI.title_card("MERIDIAN", "The only warm place in town")
		Game.set_objective("Get into the MERIDIAN data centre. Start at the security gate.")
	elif Game.spawn_id == "start" and not Game.has_flag("got:l4_badge"):
		Game.set_objective("Search the guard booth for a MERIDIAN badge.")
