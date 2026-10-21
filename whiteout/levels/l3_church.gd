extends "res://levels/level.gd"
## L3 — MAIN STREET / ST. BRENDAN'S.
## West -> east along Main Street (x from -70 to +72). Pharmacy (key) and diner on the north side,
## the boarded Northline office + billboard, the abandoned plow, Lindqvist Hardware (shotgun,
## flares, safe room) on the south side, the Christmas-tree square, St. Brendan's on the north-east
## corner and the chained lakeside gate at the far east end. MERIDIAN glows over the lake.
##
## Flags set:  l3_foreman_on, l3_key_hint, l3_fight_started, l3_bell_fitted, l3_june_call,
##             choir_dead, has_rosary (global contract flags)
## Flags read: choir_dead, has_rosary

var env_ext: Environment
var env_int: Environment
var _inside := false
var foreman: Node3D = null
var boss: Node3D = null
var _dormant: Array = []          # dormant street zombies, woken by gunfire/bell/siren
var _fires: Array = []            # [Vector3, OmniLight3D, base, phase]
var _beacon: Node3D = null
var _bell_cd := 0.0
var _boss_active := false
var _nave_spots: Array = []       # [Light3D, base_energy]
var _nave_dim := 1.0
var _last_weapon := ""
var _last_ammo := -1
var _tick := 0.0
var _bell_node: Node3D = null
var _tree_bulb: OmniLight3D = null
var _sign_light: OmniLight3D = null
var _rooms: Array = []            # [Rect2(x, z, w, h), kind, Vector3 eject_to]
var _glass_cache := {}

# =================================================================== small helpers
func _c(c: Color, r := 0.8, m := 0.0) -> StandardMaterial3D:
	return Mats.color(c, r, m)

func _em(c: Color, e := 3.0) -> StandardMaterial3D:
	return Mats.emissive(c, e)

func _b(size: Vector3, pos: Vector3, mat: Variant, solid := false, rot := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var m: Material = Mats.get_mat(mat) if mat is String else mat
	return Props.box(parent if parent != null else geo, size, pos, m, solid, rot)

func _cy(r: float, h: float, pos: Vector3, mat: Variant, solid := false, top := -1.0, rot := Vector3.ZERO, segs := 16, parent: Node3D = null) -> MeshInstance3D:
	var m: Material = Mats.get_mat(mat) if mat is String else mat
	return Props.cyl(parent if parent != null else geo, r, h, pos, m, solid, top, rot, segs)

func _glass(a: float, tint := Color(0.78, 0.86, 0.92)) -> StandardMaterial3D:
	var key := "%.2f_%s" % [a, str(tint)]
	if _glass_cache.has(key):
		return _glass_cache[key]
	var m := Mats.color(Color(tint.r, tint.g, tint.b, a), 0.15)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_cache[key] = m
	return m

func _icicles(a: Vector3, b: Vector3, n: int, maxlen := 0.7) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(a.x * 7 + a.z * 3)
	for i in n:
		var t := (i + rng.randf_range(0.1, 0.9)) / float(n)
		var p := a.lerp(b, t)
		var l := rng.randf_range(0.2, maxlen)
		_cy(0.0, l, p - Vector3(0, l * 0.5, 0), "ice", false, rng.randf_range(0.03, 0.05), Vector3.ZERO, 6)

func _drift(pos: Vector3, size: Vector3, yaw := 0.0) -> void:
	_b(size, pos + Vector3(0, size.y * 0.5 - 0.05, 0), "snow", true, Vector3(0, yaw, 0.0))

func _fire_barrel(pos: Vector3, shadows := false) -> void:
	Props.barrel(geo, pos, 0.0, true)
	_cy(0.27, 0.04, pos + Vector3(0, 0.9, 0), _em(Color(1.0, 0.45, 0.1), 3.0), false)
	var p := CPUParticles3D.new()
	p.amount = 26
	p.lifetime = 0.9
	p.direction = Vector3.UP
	p.spread = 14.0
	p.initial_velocity_min = 0.7
	p.initial_velocity_max = 1.7
	p.gravity = Vector3(0, 0.9, 0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.16
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	p.mesh = sm
	p.material_override = _em(Color(1.0, 0.5, 0.15), 4.5)
	p.position = pos + Vector3(0, 0.95, 0)
	add_child(p)
	var l := light(pos + Vector3(0, 1.5, 0), Color(1.0, 0.55, 0.22), 3.4, 13.0, shadows)
	_fires.append([pos, l, 3.4, randf() * 10.0])

func _candle(pos: Vector3, h := 0.14, lit := true) -> void:
	_cy(0.025, h, pos + Vector3(0, h * 0.5, 0), _c(Color(0.85, 0.82, 0.7), 0.7), false, -1.0, Vector3.ZERO, 8)
	if lit:
		Props.sphere(geo, 0.016, pos + Vector3(0, h + 0.02, 0), _em(Color(1.0, 0.75, 0.35), 5.0), Vector3(1, 1.8, 1))

func _candles(pos: Vector3, n: int, spread: float, light_e := 0.9, lit := true) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 11 + pos.z * 5)
	for i in n:
		_candle(pos + Vector3(rng.randf_range(-spread, spread), 0, rng.randf_range(-spread, spread)), rng.randf_range(0.08, 0.3), lit)
	if lit and light_e > 0.0:
		var l := light(pos + Vector3(0, 0.7, 0), Color(1.0, 0.7, 0.38), light_e, 5.5, false)
		_nave_spots.append([l, light_e])

func _sign(pos: Vector3, yaw: float, text: String, size := 64, col := Color(0.9, 0.9, 0.85), bg := true) -> void:
	Props.sign(geo, pos, yaw, text, size, col, bg)

func _note2(uid: String, pos: Vector3, title: String, body: String, yaw := 0.0, cb: Callable = Callable()) -> void:
	var root := note(uid, pos, title, body, yaw)
	var it: Node = null
	for ch in root.get_children():
		if ch is Interactable:
			it = ch
	if it != null and cb.is_valid():
		var inner: Callable = it.action
		it.action = func(p):
			inner.call(p)
			cb.call()

func _wshelf(x: float, z: float, yaw: float, w := 1.6, h := 2.1) -> Node3D:
	var r := Node3D.new()
	r.position = Vector3(x, 0, z)
	r.rotation.y = yaw
	geo.add_child(r)
	var m := Mats.get_mat("wood_panel", 1.0)
	Props.box(r, Vector3(w, h, 0.04), Vector3(0, h * 0.5, -0.2), m, false)
	for sx in [-1, 1]:
		Props.box(r, Vector3(0.05, h, 0.42), Vector3(sx * w * 0.5, h * 0.5, 0), m, true)
	for i in 4:
		Props.box(r, Vector3(w, 0.04, 0.42), Vector3(0, 0.45 + i * 0.5, 0), m, false)
	return r

func _clutter(r: Node3D, w: float, plank_y: float, rng: RandomNumberGenerator, cols: Array) -> void:
	var x := -w * 0.5 + 0.12
	while x < w * 0.5 - 0.15:
		var bw := rng.randf_range(0.1, 0.22)
		var bh := rng.randf_range(0.1, 0.28)
		if rng.randf() > 0.35:
			Props.box(r, Vector3(bw, bh, 0.22), Vector3(x + bw * 0.5, plank_y + 0.02 + bh * 0.5, 0.0), _c(cols[rng.randi() % cols.size()], 0.7), false, Vector3(0, rng.randf_range(-0.2, 0.2), 0))
		x += bw + 0.04

# =================================================================== environment switching
func _set_inside(on: bool, kind := "shop") -> void:
	if on == _inside:
		return
	_inside = on
	if env != null:
		env.environment = env_int if on else env_ext
	if _snow != null:
		_snow.visible = not on
	if sun != null:
		sun.visible = not on
	if on:
		footstep = "wood" if kind == "church" else "tile"
		Sfx.ambience("amb_interior")
	else:
		footstep = "snow"
		Sfx.ambience("amb_wind")

## Inside/outside is decided by where the player stands (robust across save/load).
func _update_inside() -> void:
	if player == null:
		return
	var pp := Vector2(player.global_position.x, player.global_position.z)
	for r in _rooms:
		var rc: Rect2 = r[0]
		if rc.has_point(pp):
			_set_inside(true, r[1])
			return
	_set_inside(false)

# =================================================================== BUILD
func build() -> void:
	_rooms = [
		[Rect2(-41.85, -19.85, 11.7, 13.7), "shop", Vector3(-36.0, 0.0, -3.0)],
		[Rect2(-25.85, -17.85, 13.7, 11.7), "shop", Vector3(-19.0, 0.0, -3.0)],
		[Rect2(0.15, 6.15, 15.7, 13.7), "shop", Vector3(8.0, 0.0, 3.0)],
		[Rect2(38.2, -41.8, 15.6, 33.6), "church", Vector3(36.0, 0.0, -4.5)],
	]
	env_exterior_night(true, 0.02, 0.42)
	env_ext = env.environment
	env_interior(0.3, 0.012, Color(0.58, 0.62, 0.78))
	env_int = env.environment
	env.environment = env_ext
	footstep = "snow"
	Sfx.ambience("amb_wind")
	add_spawn("from_school", Vector3(-70, 0.1, 0.0), PI * 0.5)
	add_spawn("start", Vector3(-70, 0.1, 0.0), PI * 0.5)
	add_spawn("from_meridian", Vector3(68, 0.1, 0.0), -PI * 0.5)
	_build_world()
	_build_north_row()
	_build_south_row()
	_build_hardware()
	_build_square()
	_build_church()
	_build_street_props()
	_build_meridian()
	_build_enemies()
	_build_triggers()
	_build_exit()

# ------------------------------------------------------------------ ground & boundary
func _build_world() -> void:
	floor_rect(-80, -50, 75, 50, 0.0, "snow")
	floor_rect(-80, -5.5, 72, 5.5, 0.02, "asphalt_snow", 0.1)
	# plowed snowbank boundary
	box(Vector3(-2.5, 2.5, 23.5), Vector3(160, 5.0, 3.0), "snow")      # south, behind the shops
	box(Vector3(-40.0, 2.5, -22.5), Vector3(80, 5.0, 3.0), "snow")     # north, behind west shops
	box(Vector3(-79, 2.5, 0), Vector3(3, 5.0, 100), "snow")             # west
	box(Vector3(3.0, 2.5, -31.0), Vector3(2, 5.0, 30.0), "snow")        # west edge of the square (z -46..-16)
	box(Vector3(20, 2.5, -47.5), Vector3(116, 5.0, 3.0), "snow")        # north, behind square/church
	# the lake: frozen, glossy, empty
	var lake := _c(Color(0.16, 0.2, 0.28), 0.12, 0.2)
	box(Vector3(190, -0.05, 0), Vector3(240, 0.1, 300), lake, false)
	box(Vector3(85, -0.02, 0), Vector3(22, 0.05, 120), "snow", false)
	# a few bare trees silhouetted behind the banks
	for p in [Vector3(-52, 0, -27), Vector3(-20, 0, -26), Vector3(-66, 0, 27), Vector3(10, 0, 27), Vector3(48, 0, 27), Vector3(-30, 0, 27)]:
		Props.tree(geo, p, randf_range(10.0, 13.0), int(p.x))
	# faint Meridian glow raking down the street from the east
	var glow := DirectionalLight3D.new()
	glow.light_color = Color(0.55, 0.75, 1.0)
	glow.light_energy = 0.16
	glow.shadow_enabled = false
	glow.rotation_degrees = Vector3(-10, 90, 0)
	add_child(glow)
	light(Vector3(80, 7, -8), Color(0.5, 0.72, 1.0), 1.6, 55.0, false)

# ------------------------------------------------------------------ shared storefront bits
## Builds a two-storey brick shop block. `north_side` true = faces +z (front wall at z1).
func _block(x0: float, z0: float, x1: float, z1: float, north_side: bool, label := "", sign_x := 0.0, upper_n := 3, enterable := false) -> void:
	var zf := z1 if north_side else z0
	var yaw := 0.0 if north_side else PI
	var out := 1.0 if north_side else -1.0
	if not enterable:
		box(Vector3((x0 + x1) * 0.5, 3.6, (z0 + z1) * 0.5), Vector3(x1 - x0, 7.2, z1 - z0), "brick" if (int(x0) % 2 == 0) else "brick_dark")
	# snow cap + cornice
	_b(Vector3(x1 - x0 + 0.5, 0.45, z1 - z0 + 0.5), Vector3((x0 + x1) * 0.5, 7.35, (z0 + z1) * 0.5), "snow", true)
	_b(Vector3(x1 - x0 + 0.3, 0.3, 0.35), Vector3((x0 + x1) * 0.5, 6.9, zf + out * 0.15), "concrete")
	# upper-storey windows (dark)
	var span := x1 - x0
	for i in upper_n:
		var wx := x0 + span * (i + 0.5) / float(upper_n)
		Props.window(geo, Vector3(wx, 5.2, zf + out * 0.03), yaw, 1.3, 1.7, false)
		_icicles(Vector3(wx - 0.6, 4.35, zf + out * 0.12), Vector3(wx + 0.6, 4.35, zf + out * 0.12), 5, 0.6)
	if label != "":
		_sign(Vector3(sign_x if sign_x != 0.0 else (x0 + x1) * 0.5, 4.0, zf + out * 0.2), yaw, label, 78, Color(0.88, 0.86, 0.78), true)

func _awning(cx: float, zf: float, out: float, w: float, col: Color) -> void:
	_b(Vector3(w, 0.06, 1.6), Vector3(cx, 3.25, zf + out * 0.8), _c(col, 0.8), false, Vector3(0.28 * out, 0, 0))
	_b(Vector3(w, 0.12, 1.5), Vector3(cx, 3.38, zf + out * 0.8), "snow", false, Vector3(0.28 * out, 0, 0))

func _storefront_glass(x0: float, zf: float, gaps: Array, thick := 0.05) -> void:
	for g in gaps:
		if g.size() >= 4 and g[3] > 0.3:
			var w: float = g[1]
			var top: float = g[2]
			var sill: float = g[3]
			_b(Vector3(w, top - sill, thick), Vector3(x0 + g[0], (top + sill) * 0.5 - 0.05, zf), _glass(0.5), false)
			# frost creeping in from the lower corners
			_b(Vector3(w * 0.9, 0.5, 0.07), Vector3(x0 + g[0], sill + 0.2 - 0.05, zf), "frost", false)
			_b(Vector3(0.7, 1.1, 0.07), Vector3(x0 + g[0] - w * 0.5 + 0.35, sill + 0.55 - 0.05, zf), "frost", false)

func _interior_floor(x0: float, z0: float, x1: float, z1: float, mat: Variant) -> void:
	floor_rect(x0 + 0.12, z0 + 0.12, x1 - 0.12, z1 - 0.12, 0.02, mat, 0.1)

func _stool(pos: Vector3) -> void:
	_cy(0.03, 0.62, pos + Vector3(0, 0.31, 0), "metal", false)
	_cy(0.2, 0.07, pos + Vector3(0, 0.65, 0), _c(Color(0.5, 0.1, 0.1), 0.5), false)

func _booth(pos: Vector3, yaw: float) -> void:
	var r := Node3D.new()
	r.position = pos
	r.rotation.y = yaw
	geo.add_child(r)
	var vinyl := _c(Color(0.42, 0.08, 0.08), 0.45)
	Props.box(r, Vector3(1.1, 0.05, 0.8), Vector3(0, 0.74, 0), Mats.get_mat("wood", 0.8), true)
	Props.box(r, Vector3(0.1, 0.72, 0.1), Vector3(0, 0.36, 0), Mats.get_mat("metal"), false)
	for s in [-1, 1]:
		Props.box(r, Vector3(1.2, 0.45, 0.45), Vector3(0, 0.22, s * 0.78), vinyl, true)
		Props.box(r, Vector3(1.2, 0.55, 0.1), Vector3(0, 0.72, s * 1.0), vinyl, false)

# ------------------------------------------------------------------ NORTH ROW (pharmacy, diner, Northline)
func _build_north_row() -> void:
	# ---------------- KETTLE FALLS PHARMACY  x -42..-30, z -20..-6
	var px0 := -42.0
	var pz0 := -20.0
	var px1 := -30.0
	var pz1 := -6.0
	var pgaps := [[2.4, 2.6, 2.6, 0.9], [6.0, 1.8, 2.5], [9.9, 3.6, 2.6, 0.9]]
	room(px0, pz0, px1, pz1, 3.4, "tile_floor", "brick_dark", "plaster_dirty", {"s": pgaps}, -0.05)
	_interior_floor(px0, pz0, px1, pz1, "tile_floor")
	_block(px0, pz0, px1, pz1, true, "KETTLE FALLS PHARMACY", -36.0, 3, true)
	_b(Vector3(px1 - px0, 3.4, pz1 - pz0), Vector3(-36, 5.3, -13), "brick_dark", true)
	_storefront_glass(px0, pz1, pgaps)
	_awning(-36.0, pz1, 1.0, 4.4, Color(0.1, 0.35, 0.22))
	# green cross, dead but frosted
	_b(Vector3(0.9, 0.28, 0.12), Vector3(-30.9, 3.9, pz1 + 0.3), _c(Color(0.05, 0.3, 0.14), 0.4), false)
	_b(Vector3(0.28, 0.9, 0.12), Vector3(-30.9, 3.9, pz1 + 0.3), _c(Color(0.05, 0.3, 0.14), 0.4), false)
	light(Vector3(-30.9, 3.9, pz1 + 1.4), Color(0.3, 1.0, 0.5), 0.35, 4.0, false, true)
	# interior
	_wshelf(-41.5, -9.0, PI * 0.5, 1.8)
	_wshelf(-41.5, -11.2, PI * 0.5, 1.8)
	_wshelf(-31.2, -9.5, -PI * 0.5, 1.8)
	_wshelf(-31.2, -11.7, -PI * 0.5, 1.8)
	_b(Vector3(8.0, 1.05, 0.7), Vector3(-37.4, 0.55, -13.2), "wood_panel", true)       # dispensary counter
	_b(Vector3(8.2, 0.05, 0.9), Vector3(-37.4, 1.1, -13.2), "marble", false)
	for i in 4:
		_wshelf(-40.6 + i * 2.0, -19.6, 0.0, 1.8)
	_b(Vector3(0.5, 0.4, 0.4), Vector3(-39.6, 1.3, -13.2), _c(Color(0.7, 0.72, 0.7), 0.4), false)   # till
	Props.cabinet(geo, Vector3(-31.0, 0, -17.8), PI * 0.5)
	# cots for the cold-exposure patients, and a sleeper on a mattress
	Props.bed(geo, Vector3(-40.4, 0, -8.6), PI * 0.5, true)
	Props.bed(geo, Vector3(-40.4, 0, -10.8), PI * 0.5, true)
	Props.corpse(geo, Vector3(-40.4, 0.62, -8.2), PI * 0.5, {"shirt": Color(0.5, 0.55, 0.5), "bloody": 0.0, "skin": Color(0.72, 0.78, 0.82)})
	Props.corpse(geo, Vector3(-40.4, 0.62, -10.4), PI * 0.5, {"shirt": Color(0.4, 0.4, 0.5), "bloody": 0.0, "skin": Color(0.7, 0.76, 0.82)})
	_b(Vector3(0.9, 0.12, 1.9), Vector3(-34.4, 0.08, -9.4), _c(Color(0.3, 0.35, 0.3), 0.95), false)
	_b(Vector3(0.9, 0.12, 1.9), Vector3(-33.0, 0.08, -9.4), _c(Color(0.35, 0.28, 0.25), 0.95), false)
	Props.papers(geo, Vector3(-36.0, 0.03, -10.5), 7)
	Props.chair(geo, Vector3(-36.3, 0, -15.6), 0.4, true)
	Props.blood_pool(geo, Vector3(-38.1, 0.03, -16.7), 1.6)
	_frost_corner(Vector3(-41.6, 0, -6.7), 1.8)
	_frost_corner(Vector3(-30.4, 0, -6.7), 1.5)
	light(Vector3(-36, 3.0, -12), Color(0.7, 0.9, 0.85), 0.9, 9.0, true, true)
	light(Vector3(-37.5, 1.5, -17.2), Color(1.0, 0.8, 0.55), 0.8, 5.0, false)
	# ---------------- IRON RANGE DINER  x -26..-12, z -18..-6
	var dx0 := -26.0
	var dz0 := -18.0
	var dx1 := -12.0
	var dz1 := -6.0
	var dgaps := [[2.2, 3.0, 2.6, 0.9], [7.0, 1.8, 2.5], [12.0, 3.4, 2.6, 0.9]]
	room(dx0, dz0, dx1, dz1, 3.4, "tile_floor", "brick", "plaster_dirty", {"s": dgaps}, -0.05)
	_interior_floor(dx0, dz0, dx1, dz1, "tile_floor")
	_block(dx0, dz0, dx1, dz1, true, "", 0.0, 4, true)
	_b(Vector3(dx1 - dx0, 3.4, dz1 - dz0), Vector3(-19, 5.3, -12), "brick", true)
	_storefront_glass(dx0, dz1, dgaps)
	_awning(-23.8, dz1, 1.0, 3.6, Color(0.55, 0.1, 0.1))
	_awning(-14.0, dz1, 1.0, 3.6, Color(0.55, 0.1, 0.1))
	# THE frozen neon sign: dead tubes, a faint red sputter
	_b(Vector3(5.6, 1.1, 0.2), Vector3(-19, 4.6, dz1 + 0.25), _c(Color(0.1, 0.1, 0.12), 0.5, 0.3), false)
	var neon := Label3D.new()
	neon.text = "IRON RANGE DINER"
	neon.font_size = 90
	neon.pixel_size = 0.0055
	neon.modulate = Color(0.75, 0.12, 0.1)
	neon.shaded = false
	neon.double_sided = false
	neon.position = Vector3(-19, 4.7, dz1 + 0.37)
	add_child(neon)
	var neon2 := Label3D.new()
	neon2.text = "OPEN 24 HRS"
	neon2.font_size = 50
	neon2.pixel_size = 0.005
	neon2.modulate = Color(0.1, 0.25, 0.45)
	neon2.shaded = false
	neon2.double_sided = false
	neon2.position = Vector3(-19, 4.2, dz1 + 0.37)
	add_child(neon2)
	_b(Vector3(5.7, 0.3, 0.12), Vector3(-19, 4.62, dz1 + 0.36), "frost", false)
	_icicles(Vector3(-21.8, 4.0, dz1 + 0.4), Vector3(-16.2, 4.0, dz1 + 0.4), 12, 0.8)
	_sign_light = light(Vector3(-19, 4.7, dz1 + 1.2), Color(1.0, 0.1, 0.06), 0.9, 6.5, false, true)
	# interior
	_b(Vector3(8.6, 1.05, 0.8), Vector3(-20.3, 0.55, -12.0), "wood_panel", true)         # counter
	_b(Vector3(8.8, 0.06, 1.0), Vector3(-20.3, 1.1, -12.0), "marble", false)
	for i in 6:
		_stool(Vector3(-23.6 + i * 1.5, 0, -11.0))
	_booth(Vector3(-24.0, 0, -8.2), 0.0)
	_booth(Vector3(-14.3, 0, -8.2), 0.0)
	_booth(Vector3(-24.6, 0, -15.0), PI * 0.5)
	Props.table(geo, Vector3(-17.8, 0, -9.0), 0.2, Vector2(1.0, 1.0))
	Props.chair(geo, Vector3(-17.1, 0, -8.3), 1.3, true)
	Props.chair(geo, Vector3(-18.6, 0, -9.6), 2.2, false)
	_b(Vector3(1.2, 0.9, 0.7), Vector3(-17.0, 0.45, -17.4), "metal", true)                 # griddle line
	_b(Vector3(0.9, 1.9, 0.8), Vector3(-12.8, 0.95, -15.0), _c(Color(0.7, 0.72, 0.74), 0.35, 0.5), true)  # fridge
	_b(Vector3(1.8, 0.9, 0.7), Vector3(-14.6, 0.45, -17.4), "metal", true)
	Props.trash_bags(geo, Vector3(-21.4, 0, -17.2), 0.0, 3)
	Props.debris(geo, Vector3(-19.5, 0.0, -9.5), 0.0, 5, "plaster")
	Props.blood_pool(geo, Vector3(-15.8, 0.03, -14.2), 1.4)
	Props.corpse(geo, Vector3(-16.4, 0.0, -14.7), 0.7, {"shirt": Color(0.9, 0.9, 0.85), "bloody": 0.7})
	_frost_corner(Vector3(-25.5, 0, -6.7), 2.0)
	light(Vector3(-19, 2.9, -12.5), Color(1.0, 0.75, 0.5), 1.1, 9.0, true, true)
	light(Vector3(-14.8, 1.8, -15.5), Color(0.5, 0.75, 0.9), 0.5, 5.0, false)
	# ---------------- NORTHLINE MINERAL (boarded)  x -10..2, z -16..-6, plus the billboard
	var nx0 := -10.0
	var nx1 := 2.0
	_block(nx0, -16.0, nx1, -6.0, true, "", 0.0, 4, false)
	for wx in [-8.0, -3.0, 0.5]:
		Props.window(geo, Vector3(wx, 1.9, -5.97), 0.0, 2.2, 2.0, false)
		for i in 4:
			_b(Vector3(2.5, 0.22, 0.05), Vector3(wx, 1.0 + i * 0.5, -5.9), "wood", false, Vector3(0, 0, [0.08, -0.05, 0.1, -0.09][i]))
	# boarded double door with an X
	_b(Vector3(2.2, 2.5, 0.12), Vector3(-3.0, 1.25, -5.93), _c(Color(0.12, 0.12, 0.14), 0.6), false)
	for sgn in [-1, 1]:
		_b(Vector3(0.22, 3.0, 0.06), Vector3(-3.0, 1.35, -5.84), "wood", false, Vector3(0, 0, 0.9 * sgn))
	_sign(Vector3(-4.0, 4.1, -5.78), 0.0, "NORTHLINE MINERAL", 70, Color(0.8, 0.82, 0.85), true)
	_sign(Vector3(-4.0, 3.55, -5.78), 0.0, "COMMUNITY RECRUITMENT OFFICE — CLOSED", 34, Color(0.7, 0.72, 0.75), false)
	_sign(Vector3(-8.0, 2.0, -5.86), 0.0, "NOW HIRING", 40, Color(0.78, 0.3, 0.25), false)
	_sign(Vector3(0.5, 2.55, -5.86), 0.0, "NORTHLINE CARES", 28, Color(0.7, 0.75, 0.8), false)
	# billboard on the roof: 12 x 4.6, lit by a cold Meridian-blue wash
	_b(Vector3(0.35, 6.5, 0.35), Vector3(-9.0, 10.4, -7.8), "metal_painted", true)
	_b(Vector3(0.35, 6.5, 0.35), Vector3(1.0, 10.4, -7.8), "metal_painted", true)
	_b(Vector3(12.0, 4.6, 0.25), Vector3(-4.0, 11.5, -7.8), _c(Color(0.07, 0.2, 0.32), 0.5), false)
	_b(Vector3(12.3, 0.2, 0.4), Vector3(-4.0, 13.85, -7.8), "metal_painted", false)
	_b(Vector3(12.3, 0.2, 0.4), Vector3(-4.0, 9.15, -7.8), "metal_painted", false)
	_sign(Vector3(-4.0, 12.6, -7.6), 0.0, "NORTHLINE", 190, Color(0.92, 0.94, 0.96), false)
	_sign(Vector3(-4.0, 11.2, -7.6), 0.0, "LITHIUM FOR A CLEANER TOMORROW", 82, Color(0.82, 0.9, 0.98), false)
	_sign(Vector3(-4.0, 10.1, -7.6), 0.0, "powering the future of Kettle Falls", 40, Color(0.7, 0.8, 0.9), false)
	_sign(Vector3(0.2, 9.55, -7.58), 0.0, "TOMORROW FOR WHO?", 30, Color(0.65, 0.12, 0.1), false)
	for sx in [-8.0, 0.0]:
		spot(Vector3(sx, 8.4, -4.8), Vector3(sx * 0.6 - 1.6, 11.0, -7.8), Color(0.55, 0.75, 1.0), 5.5, 14.0, 42.0, false)
	_icicles(Vector3(-9.8, 6.9, -5.8), Vector3(1.8, 6.9, -5.8), 22, 0.9)

func _frost_corner(pos: Vector3, s: float) -> void:
	_b(Vector3(s, 0.03, s), pos + Vector3(0, 0.04, 0), "frost", false)
	_b(Vector3(s * 0.5, 0.25, s * 0.35), pos + Vector3(0.1, 0.12, 0.1), "snow", false, Vector3(0, 0.5, 0))

# ------------------------------------------------------------------ SOUTH ROW (dead shops, gas station)
func _build_south_row() -> void:
	# credit union
	_block(-40.0, 6.0, -22.0, 20.0, false, "LAKESHORE SAVINGS & LOAN", -31.0, 5)
	for wx in [-37.0, -33.0, -29.0, -25.0]:
		Props.window(geo, Vector3(wx, 1.9, 5.97), PI, 2.0, 2.0, false)
	_b(Vector3(1.9, 2.5, 0.12), Vector3(-31.0, 1.25, 5.93), _c(Color(0.1, 0.1, 0.12), 0.5), false)
	_awning(-31.0, 6.0, -1.0, 3.0, Color(0.15, 0.2, 0.3))
	# tap room + bakery
	_block(18.0, 6.0, 33.0, 20.0, false, "THE TAP ROOM", 25.5, 4)
	for wx in [20.5, 23.5, 27.5, 30.5]:
		Props.window(geo, Vector3(wx, 1.9, 5.97), PI, 2.2, 2.0, true)
	_b(Vector3(1.9, 2.5, 0.12), Vector3(25.5, 1.25, 5.93), _c(Color(0.1, 0.1, 0.12), 0.5), false)
	_awning(25.5, 6.0, -1.0, 3.0, Color(0.2, 0.3, 0.15))
	light(Vector3(25.5, 2.0, 4.8), Color(1.0, 0.75, 0.45), 0.5, 4.0, false, true)
	# vacant lot between savings and hardware: bus shelter + dumpster
	_b(Vector3(3.2, 0.12, 1.4), Vector3(-9.5, 2.5, 8.5), "metal_painted", true)
	for sx in [-1, 1]:
		_b(Vector3(0.1, 2.5, 1.4), Vector3(-9.5 + sx * 1.55, 1.25, 8.5), "metal_painted", true)
	_b(Vector3(3.0, 1.9, 0.06), Vector3(-9.5, 1.3, 9.15), _glass(0.4), false)
	_b(Vector3(3.2, 0.2, 1.5), Vector3(-9.5, 2.65, 8.5), "snow", false)
	Props.bench(geo, Vector3(-9.5, 0, 8.6), PI)
	_b(Vector3(2.0, 1.2, 1.0), Vector3(-15.5, 0.6, 13.0), _c(Color(0.1, 0.25, 0.15), 0.6), true)
	_drift(Vector3(-15.5, 0, 12.2), Vector3(2.6, 0.9, 1.0))
	Props.trash_bags(geo, Vector3(-13.5, 0, 12.0), 0.0, 3)
	# lot fence to the bank
	Props.fence(geo, Vector3(-22, 0, 20), Vector3(-1, 0, 20), 2.4)
	Props.fence(geo, Vector3(-22, 0, 6), Vector3(-22, 0, 20), 2.4)
	Props.fence(geo, Vector3(-1, 0, 6), Vector3(-1, 0, 20), 2.4)
	# alley gap between hardware and tap room: sealed with a wall of snow and a rusted dumpster
	box(Vector3(17.0, 2.0, 13.0), Vector3(2.0, 4.0, 14.0), "snow")
	# gas station canopy, x 40..58
	for px in [41.0, 56.0]:
		for pz in [9.0, 17.0]:
			_cy(0.22, 4.6, Vector3(px, 2.3, pz), "concrete", true)
	_b(Vector3(17.5, 0.5, 10.5), Vector3(48.5, 4.75, 13.0), _c(Color(0.5, 0.08, 0.08), 0.6), false)
	_b(Vector3(17.7, 0.25, 10.7), Vector3(48.5, 5.12, 13.0), "snow", false)
	_sign(Vector3(48.5, 4.75, 7.62), PI, "LAKESHORE CO-OP FUEL", 60, Color(0.9, 0.9, 0.85), false)
	for px in [45.0, 52.0]:
		_b(Vector3(0.7, 1.5, 0.5), Vector3(px, 0.75, 13.0), _c(Color(0.7, 0.7, 0.72), 0.4, 0.4), true)
		_b(Vector3(0.5, 0.3, 0.02), Vector3(px, 1.2, 12.74), _em(Color(0.05, 0.08, 0.1), 0.2), false)
	_b(Vector3(6.0, 3.2, 4.0), Vector3(48.5, 1.6, 19.0), "concrete", true)  # kiosk
	_sign(Vector3(48.5, 2.2, 16.95), PI, "PREPAY ONLY", 40, Color(0.85, 0.85, 0.8), true)
	Props.car(geo, Vector3(48.5, 0, 9.6), 1.5, Color(0.2, 0.24, 0.3), true, "sedan")
	light(Vector3(48.5, 4.3, 13.0), Color(1.0, 0.4, 0.3), 0.8, 10.0, false)
	_fire_barrel(Vector3(50.5, 0, 11.0))
	Props.fence(geo, Vector3(40, 0, 20), Vector3(72, 0, 20), 2.4)

# ------------------------------------------------------------------ LINDQVIST HARDWARE
func _build_hardware() -> void:
	var hx0 := 0.0
	var hz0 := 6.0
	var hx1 := 16.0
	var hz1 := 20.0
	var hgaps := [[3.0, 3.0, 2.6, 0.9], [8.0, 1.8, 2.5], [13.0, 3.0, 2.6, 0.9]]
	room(hx0, hz0, hx1, hz1, 3.4, "wood_floor", "brick", "plaster_dirty", {"n": hgaps}, -0.05)
	_interior_floor(hx0, hz0, hx1, hz1, "wood_floor")
	_block(hx0, hz0, hx1, hz1, false, "LINDQVIST HARDWARE", 8.0, 4, true)
	_b(Vector3(hx1 - hx0, 3.4, hz1 - hz0), Vector3(8, 5.3, 13), "brick", true)
	_storefront_glass(hx0, hz0, hgaps)
	_sign(Vector3(8.0, 3.45, 5.7), PI, "SINCE 1954 — NAILS TO NEW ROOFS", 30, Color(0.75, 0.7, 0.55), false)
	_awning(8.0, 6.0, -1.0, 6.0, Color(0.15, 0.3, 0.18))
	# interior partition: z=14 with office door (x=3) and storeroom opening (x=13); x=10 splits office/storeroom
	wall(Vector2(hx0, 14.0), Vector2(hx1, 14.0), 3.4, "plaster_dirty", -0.05, 0.2, [[3.0, 1.5, 2.4], [13.0, 1.7, 2.5]])
	wall(Vector2(10.0, 14.0), Vector2(10.0, hz1), 3.4, "plaster_dirty", -0.05, 0.2, [])
	door("l3_office_door", Vector3(3.0, 0.0, 14.0), 0.0, {"width": 1.3, "height": 2.3, "mat": "wood", "prompt": "Open office door"})
	_sign(Vector3(3.0, 2.65, 13.84), PI, "OFFICE", 28, Color(0.85, 0.85, 0.8), true)
	# sales floor
	_b(Vector3(9.0, 1.05, 0.8), Vector3(6.5, 0.55, 10.4), "wood_panel", true)    # counter x 2..11
	_b(Vector3(9.2, 0.06, 1.0), Vector3(6.5, 1.1, 10.4), "wood", false)
	_b(Vector3(0.5, 0.35, 0.4), Vector3(3.2, 1.3, 10.4), _c(Color(0.35, 0.34, 0.3), 0.4, 0.6), false)  # till
	Props.table(geo, Vector3(14.0, 0, 10.4), 0.1, Vector2(2.2, 0.9))
	_wshelf(15.4, 8.0, -PI * 0.5, 1.8)
	_wshelf(0.6, 8.0, PI * 0.5, 1.8)
	_wshelf(0.6, 11.6, PI * 0.5, 1.6)
	_wshelf(15.4, 12.2, -PI * 0.5, 1.6)
	# shelf dressing
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	for sh in [[15.4, 8.0, -PI * 0.5], [0.6, 8.0, PI * 0.5], [0.6, 11.6, PI * 0.5]]:
		var holder := Node3D.new()
		holder.position = Vector3(sh[0], 0, sh[1])
		holder.rotation.y = sh[2]
		geo.add_child(holder)
		for py in [0.47, 0.97, 1.47]:
			_clutter(holder, 1.6, py, rng, [Color(0.5, 0.3, 0.1), Color(0.25, 0.3, 0.4), Color(0.55, 0.5, 0.35), Color(0.3, 0.35, 0.25)])
	# propane cylinders, paint, rope
	for i in 4:
		_cy(0.16, 0.5, Vector3(11.4 + i * 0.4, 0.25, 7.2), _c(Color(0.75, 0.75, 0.78), 0.4, 0.6), true, -1.0, Vector3.ZERO, 12)
	_sign(Vector3(12.5, 1.05, 7.0), PI, "PROPANE — ASK DON", 24, Color(0.9, 0.85, 0.5), false)
	_sign(Vector3(3.2, 2.4, 6.2), 0.0, "SPACE HEATERS: SOLD OUT", 34, Color(0.85, 0.3, 0.25), false)
	_sign(Vector3(3.2, 2.0, 6.2), 0.0, "ROCK SALT: SOLD OUT   SHOVELS: SOLD OUT", 24, Color(0.8, 0.8, 0.75), false)
	Props.debris(geo, Vector3(6.0, 0.0, 8.0), 0.0, 4, "plaster")
	Props.papers(geo, Vector3(9.0, 0.03, 8.6), 6)
	# the owner's last stand behind the counter
	Props.blood_pool(geo, Vector3(7.0, 0.03, 12.4), 2.0)
	Props.corpse(geo, Vector3(6.8, 0.0, 12.5), 0.3, {"shirt": Color(0.5, 0.15, 0.1), "bloody": 0.9, "coat": true, "coat_color": Color(0.5, 0.2, 0.15)})
	for i in 7:
		_cy(0.012, 0.06, Vector3(5.2 + i * 0.28, 0.05, 11.9 + (i % 3) * 0.2), _c(Color(0.7, 0.15, 0.1), 0.5), false, -1.0, Vector3(0, 0, PI * 0.5), 6)
	_b(Vector3(2.2, 0.9, 0.5), Vector3(5.0, 0.45, 13.6), "wood_panel", true)
	_b(Vector3(0.9, 1.2, 0.4), Vector3(8.8, 0.6, 13.6), "metal_painted", true)
	# lighting: lantern on the counter, cold spill from the windows
	_cy(0.07, 0.18, Vector3(5.5, 1.22, 10.5), _c(Color(0.2, 0.3, 0.2), 0.5), false)
	Props.sphere(geo, 0.06, Vector3(5.5, 1.36, 10.5), _em(Color(1.0, 0.78, 0.45), 3.5))
	light(Vector3(5.5, 1.7, 10.8), Color(1.0, 0.76, 0.46), 1.7, 8.5, true, true)
	light(Vector3(8.0, 2.8, 8.0), Color(0.5, 0.7, 0.95), 0.5, 8.0, false)
	_frost_corner(Vector3(0.9, 0, 6.8), 1.6)
	_frost_corner(Vector3(15.2, 0, 6.8), 1.3)
	# ---- storeroom (x 10..16, z 14..20): ammo + crates + dim lantern
	_wshelf(15.4, 16.0, -PI * 0.5, 1.8)
	_wshelf(10.6, 18.5, PI * 0.5, 1.8)
	Props.crate(geo, Vector3(13.0, 0, 19.2), 0.3, 0.9)
	Props.crate(geo, Vector3(14.1, 0, 19.3), 0.0, 0.7)
	Props.crate(geo, Vector3(13.6, 0.7, 19.25), 0.6, 0.6)
	_cy(0.07, 0.18, Vector3(15.15, 0.99, 16.5), _c(Color(0.2, 0.3, 0.2), 0.5), false)
	light(Vector3(14.6, 1.5, 16.6), Color(1.0, 0.8, 0.55), 0.7, 5.5, false)
	# ---- the back office: the safe room
	Props.desk(geo, Vector3(7.9, 0, 19.45), PI)
	Props.chair(geo, Vector3(7.6, 0, 18.4), 0.3, false)
	Props.bed(geo, Vector3(1.0, 0, 16.6), PI * 0.5, false)
	_wshelf(5.2, 19.65, PI, 1.6)
	Props.crate(geo, Vector3(9.3, 0, 15.1), 0.2, 0.7)
	# propane heater: grille, glow, warm light
	_b(Vector3(0.7, 0.9, 0.5), Vector3(2.4, 0.45, 19.3), _c(Color(0.55, 0.12, 0.1), 0.45, 0.4), true)
	_b(Vector3(0.5, 0.35, 0.04), Vector3(2.4, 0.55, 19.02), _em(Color(1.0, 0.4, 0.08), 3.2), false)
	_cy(0.15, 0.7, Vector3(3.1, 0.35, 19.4), _c(Color(0.75, 0.75, 0.78), 0.4, 0.6), false, -1.0, Vector3.ZERO, 12)
	light(Vector3(2.4, 1.0, 18.2), Color(1.0, 0.55, 0.25), 2.6, 9.0, true)
	light(Vector3(7.6, 1.4, 18.7), Color(1.0, 0.82, 0.55), 1.3, 7.0, false)
	_sign(Vector3(5.0, 2.4, 14.14), 0.0, "WARM — COME IN — SHUT THE DOOR", 22, Color(0.95, 0.85, 0.55), false)
	Props.papers(geo, Vector3(8.4, 0.82, 19.4), 3)
	_b(Vector3(0.5, 0.3, 0.4), Vector3(1.1, 1.0, 16.6), _c(Color(0.35, 0.3, 0.25), 0.9), false)   # blankets
	save_point(Vector3(7.5, 0.80, 19.5), PI)
	item_box(Vector3(5.3, 0.0, 14.8), 0.0)
	# the safe zone volume
	var sz := Area3D.new()
	sz.add_to_group("safe_zone")
	sz.collision_layer = 0
	sz.collision_mask = 2
	var cs := CollisionShape3D.new()
	var shp := BoxShape3D.new()
	shp.size = Vector3(10.0, 3.2, 6.0)
	cs.shape = shp
	sz.add_child(cs)
	sz.position = Vector3(5.0, 1.6, 17.0)
	add_child(sz)
	trigger("", Vector3(5.0, 1.5, 17.0), Vector3(9.2, 3.0, 5.2), _music_safe, false)
	trigger("", Vector3(8.0, 1.5, 10.0), Vector3(7.0, 3.0, 2.0), _music_tension, false)

# ------------------------------------------------------------------ SQUARE: the dead Christmas tree
func _build_square() -> void:
	# town hall at the back of the square
	box(Vector3(19, 4.0, -41.0), Vector3(30, 8.0, 10.0), "brick_dark")
	_b(Vector3(31, 0.45, 11.0), Vector3(19, 8.2, -41.0), "snow", true)
	for i in 6:
		Props.window(geo, Vector3(7.0 + i * 4.8, 3.2, -35.97), 0.0, 1.6, 2.3, false)
	_b(Vector3(3.0, 2.8, 0.2), Vector3(19, 1.4, -35.9), _c(Color(0.08, 0.08, 0.1), 0.5), false)
	_sign(Vector3(19, 5.4, -35.8), 0.0, "KETTLE FALLS TOWN HALL", 90, Color(0.85, 0.83, 0.75), true)
	for sx in [-1, 1]:
		_cy(0.3, 5.0, Vector3(19 + sx * 2.2, 2.5, -34.9), "concrete", true)
	_cy(0.04, 9.0, Vector3(7.5, 4.5, -34.0), "metal", false)
	_b(Vector3(1.2, 0.8, 0.02), Vector3(8.1, 8.2, -34.0), _c(Color(0.4, 0.4, 0.45), 0.9), false, Vector3(0, 0, 0.7))
	# banner across the square
	_sign(Vector3(19, 4.2, -33.5), 0.0, "WINTER SOLSTICE CARNIVAL — DEC 21 — FREE COCOA", 54, Color(0.75, 0.35, 0.3), true)
	# the giant tree
	var tp := Vector3(19, 0, -19)
	var tiers := [[3.7, 2.6, 0.0], [3.1, 2.5, 1.8], [2.5, 2.4, 3.5], [1.9, 2.3, 5.2], [1.3, 2.2, 6.8], [0.8, 2.0, 8.2]]
	var needle := _c(Color(0.1, 0.19, 0.13), 0.95)
	var frosted := _c(Color(0.62, 0.7, 0.72), 0.6)
	_cy(0.45, 9.5, tp + Vector3(0, 4.75, 0), "bark", false)
	for i in tiers.size():
		var t: Array = tiers[i]
		_cy(t[0], t[1], tp + Vector3(0, 1.3 + t[2] + t[1] * 0.5, 0), needle, i == 0, 0.08, Vector3.ZERO, 14)
		_cy(t[0] * 0.92, t[1] * 0.4, tp + Vector3(0, 1.3 + t[2] + t[1] * 0.2, 0), frosted, false, 0.05, Vector3.ZERO, 14)
	var brng := RandomNumberGenerator.new()
	brng.seed = 21
	var bulb_cols := [Color(0.35, 0.05, 0.05), Color(0.05, 0.2, 0.08), Color(0.08, 0.1, 0.3), Color(0.35, 0.28, 0.08)]
	for i in 46:
		var ti: int = brng.randi() % tiers.size()
		var t2: Array = tiers[ti]
		var ang := brng.randf() * TAU
		var f := brng.randf_range(0.25, 0.95)
		var rr: float = t2[0] * (1.0 - f) * 0.95 + 0.1
		var y: float = 1.3 + t2[2] + t2[1] * f
		Props.sphere(geo, 0.09, tp + Vector3(cos(ang) * rr, y, sin(ang) * rr), _c(bulb_cols[brng.randi() % 4], 0.12, 0.3))
	Props.sphere(geo, 0.28, tp + Vector3(0, 10.5, 0), _c(Color(0.55, 0.5, 0.3), 0.3, 0.6), Vector3(1, 1.2, 1))
	# one string still alive: a single red bulb that sputters
	var live := tp + Vector3(1.4, 4.0, 1.2)
	Props.sphere(geo, 0.1, live, _em(Color(1.0, 0.08, 0.05), 5.0))
	_tree_bulb = light(live, Color(1.0, 0.1, 0.06), 1.2, 6.0, false, true)
	# presents, a ring fence, a cocoa stand
	for i in 7:
		var a := i * 0.9
		_b(Vector3(0.5, 0.4, 0.5), tp + Vector3(cos(a) * 4.6, 0.2, sin(a) * 4.6), _c(Color.from_hsv(brng.randf(), 0.4, 0.25), 0.7), false, Vector3(0, a, 0))
	_b(Vector3(2.2, 2.2, 2.2), Vector3(26.0, 1.1, -12.0), "wood_panel", true)
	_sign(Vector3(26.0, 2.0, -10.88), 0.0, "FREE COCOA", 44, Color(0.85, 0.8, 0.7), false)
	_cy(0.28, 0.6, Vector3(26.0, 2.5, -12.0), "metal", false)
	_drift(Vector3(26.0, 0, -10.5), Vector3(3.0, 0.5, 1.2))
	# snow-covered benches, lamp posts, bodies
	Props.bench(geo, Vector3(11.5, 0, -12.0), 0.3)
	Props.bench(geo, Vector3(28.5, 0, -24.0), -0.5)
	for p in [Vector3(8, 0, -9), Vector3(30, 0, -9), Vector3(8, 0, -30), Vector3(30, 0, -30)]:
		Props.lamp_post(geo, p, 0.0, false)
	Props.corpse(geo, Vector3(14.5, 0.02, -23.0), 0.4, {"shirt": Color(0.2, 0.35, 0.5), "bloody": 0.1, "coat": true, "skin": Color(0.72, 0.8, 0.85)})
	Props.corpse(geo, Vector3(23.0, 0.02, -15.0), 2.0, {"shirt": Color(0.5, 0.2, 0.2), "bloody": 0.0, "skin": Color(0.7, 0.78, 0.84)})
	_b(Vector3(0.7, 0.05, 1.3), Vector3(21.5, 0.2, -23.5), "wood", false, Vector3(0.1, 0.4, 0.1))    # a child's sled
	_candles(Vector3(23.0, 0.03, -14.0), 6, 0.5, 0.0, false)
	# a burning barrel at the foot of the tree: the one warm pool in the square
	_fire_barrel(Vector3(14.0, 0, -15.0), true)
	_fire_barrel(Vector3(32.5, 0, -6.8))
	# fenced graveyard behind the church, east side
	_build_graveyard()

func _build_graveyard() -> void:
	Props.fence(geo, Vector3(56, 0, -44), Vector3(56, 0, -8), 1.6, "metal_rust")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for r in 5:
		for c in 4:
			var p := Vector3(59.0 + c * 3.4, 0, -14.0 - r * 5.4)
			var h := rng.randf_range(0.6, 1.2)
			_b(Vector3(0.6, h, 0.14), p + Vector3(0, h * 0.5, 0), "concrete", true, Vector3(0, rng.randf_range(-0.2, 0.2), rng.randf_range(-0.07, 0.07)))
			_drift(p + Vector3(0, 0, 1.0), Vector3(0.9, 0.3, 1.6), 0.0)
	Props.tree(geo, Vector3(63, 0, -24), 10.0, 5)
	Props.tree(geo, Vector3(66, 0, -38), 11.0, 8)
	Props.statue(geo, Vector3(61, 0, -40), 0.0)

# ------------------------------------------------------------------ the street itself
func _build_street_props() -> void:
	# west arrival: the road behind us is blocked by a snowed-in jack-knifed truck
	_b(Vector3(2.6, 3.0, 8.0), Vector3(-76.5, 1.7, -1.5), _c(Color(0.55, 0.45, 0.1), 0.6, 0.3), true, Vector3(0, 0.25, 0))
	_b(Vector3(2.4, 0.5, 7.8), Vector3(-76.5, 3.4, -1.5), "snow", false, Vector3(0, 0.25, 0))
	_drift(Vector3(-77, 0, 4.5), Vector3(3.0, 1.6, 4.0))
	_drift(Vector3(-77, 0, -6.0), Vector3(3.0, 1.4, 4.0))
	_sign(Vector3(-69.0, 2.8, 7.0), -PI * 0.5 + 0.2, "WELCOME TO KETTLE FALLS — POP. 1,812", 52, Color(0.9, 0.9, 0.85), true)
	_cy(0.07, 3.0, Vector3(-69.0, 1.5, 7.0), "metal_painted", true)
	_sign(Vector3(-69.0, 2.25, 7.0), -PI * 0.5 + 0.2, "HOME OF THE IRON RANGE HAWKS", 28, Color(0.9, 0.85, 0.5), false)
	_fire_barrel(Vector3(-66.5, 0, 3.4), true)
	_fire_barrel(Vector3(-66.5, 0, -3.4))
	Props.debris(geo, Vector3(-72, 0, 1.0), 0.0, 5, "concrete")
	# cars along the curbs and across the lanes
	var cars := [
		[Vector3(-62, 0, 4.2), 0.08, Color(0.2, 0.25, 0.3), "sedan"],
		[Vector3(-56, 0, -4.2), PI - 0.05, Color(0.32, 0.12, 0.1), "van"],
		[Vector3(-47, 0, 0.5), 1.45, Color(0.22, 0.28, 0.2), "sedan"],
		[Vector3(-38, 0, 4.3), 0.0, Color(0.3, 0.3, 0.34), "sedan"],
		[Vector3(-30, 0, -4.3), PI, Color(0.1, 0.1, 0.12), "police"],
		[Vector3(-21, 0, 4.2), 0.06, Color(0.35, 0.3, 0.12), "van"],
		[Vector3(-19.5, 0, -4.4), PI + 0.04, Color(0.18, 0.2, 0.32), "sedan"],
		[Vector3(11, 0, 4.2), 0.0, Color(0.28, 0.1, 0.12), "sedan"],
		[Vector3(18, 0, -4.2), PI, Color(0.2, 0.3, 0.3), "ambulance"],
		[Vector3(30, 0, -0.5), 1.2, Color(0.26, 0.26, 0.3), "sedan"],
		[Vector3(38, 0, 4.2), 0.0, Color(0.15, 0.2, 0.15), "van"],
		[Vector3(62, 0, 1.8), 1.7, Color(0.3, 0.3, 0.32), "sedan"],
	]
	for c in cars:
		Props.car(geo, c[0], c[1], c[2], true, c[3])
	# THE SNOWPLOW, abandoned mid-street, amber beacon still turning
	_build_plow(Vector3(-8.0, 0, 0.2))
	# a dead traffic light at the crossroads
	_cy(0.1, 5.4, Vector3(27.0, 2.7, 5.0), "metal_painted", true)
	_b(Vector3(0.18, 0.18, 6.0), Vector3(27.0, 5.3, 2.0), "metal_painted", false)
	_b(Vector3(0.55, 1.5, 0.5), Vector3(27.0, 4.8, 0.0), _c(Color(0.08, 0.08, 0.09), 0.5), false)
	for i in 3:
		Props.sphere(geo, 0.16, Vector3(27.0, 5.3 - i * 0.45, 0.27), _c([Color(0.25, 0.04, 0.04), Color(0.25, 0.2, 0.04), Color(0.04, 0.2, 0.06)][i], 0.1, 0.3))
	_b(Vector3(0.6, 0.12, 0.55), Vector3(27.0, 5.62, 0.0), "snow", false)
	_icicles(Vector3(26.8, 5.2, 3.0), Vector3(27.2, 5.2, 3.0), 4, 0.5)
	# dead street lamps down both sides
	for x in [-60.0, -46.0, -32.0, -18.0, 4.0, 40.0, 56.0]:
		Props.lamp_post(geo, Vector3(x, 0, 5.8), PI, false)
	for x in [-53.0, -39.0, -5.0, 36.0, 64.0]:
		Props.lamp_post(geo, Vector3(x, 0, -5.8), 0.0, false)
	# phone line sagging across, scattered newspapers, sandwich board
	Props.papers(geo, Vector3(-44, 0.03, -3.0), 9)
	Props.papers(geo, Vector3(20, 0.03, 2.0), 8)
	_sign(Vector3(-22.0, 0.55, -5.2), 0.2, "SOUP OF THE DAY: NO", 24, Color(0.9, 0.9, 0.8), true)
	# burning barrels: the pools of light that keep the Foreman at bay
	_fire_barrel(Vector3(-27.5, 0, -2.0))
	_fire_barrel(Vector3(-12.5, 0, 3.8), true)
	_fire_barrel(Vector3(6.5, 0, -1.8))
	_fire_barrel(Vector3(35.5, 0, -3.5), true)
	_fire_barrel(Vector3(66.0, 0, -3.5))
	# scattered items in the street
	pickup("l3_amm_street1", "ammo_9mm", 6, Vector3(-47.0, 0.05, -2.4))
	pickup("l3_gel_car", "gel", 1, Vector3(-30.3, 0.55, -4.6))
	pickup("l3_amm_plow", "ammo_9mm", 4, Vector3(-9.0, 0.05, -3.2))
	pickup("l3_amm_sq", "ammo_9mm", 5, Vector3(15.5, 0.05, -10.5))
	pickup("l3_amm_east", "ammo_9mm", 4, Vector3(52.0, 0.05, -2.6))
	_candles(Vector3(37.4, 0.03, -6.8), 8, 0.7, 0.0, false)

func _build_plow(p: Vector3) -> void:
	var r := Node3D.new()
	r.position = p
	r.rotation.y = 0.12
	geo.add_child(r)
	var orange := _c(Color(0.95, 0.5, 0.08), 0.5, 0.2)
	var dark := _c(Color(0.08, 0.08, 0.09), 0.6)
	Props.box(r, Vector3(7.0, 0.9, 2.6), Vector3(0, 1.0, 0), orange, true)
	Props.box(r, Vector3(2.3, 1.8, 2.5), Vector3(-1.6, 2.35, 0), orange, true)
	Props.box(r, Vector3(2.32, 0.9, 2.52), Vector3(-1.6, 2.7, 0), _glass(0.65, Color(0.15, 0.2, 0.25)), false)
	Props.box(r, Vector3(3.0, 0.5, 2.6), Vector3(2.0, 1.7, 0), _c(Color(0.55, 0.58, 0.6), 0.5, 0.5), false)
	Props.box(r, Vector3(3.0, 0.2, 2.6), Vector3(2.0, 2.0, 0), Mats.get_mat("snow"), false)
	# V-plow blade, angled, frosted
	Props.box(r, Vector3(0.3, 1.5, 4.0), Vector3(-4.0, 1.0, 0.6), _c(Color(0.7, 0.34, 0.05), 0.45, 0.4), true, Vector3(0, 0.55, 0))
	Props.box(r, Vector3(0.3, 1.5, 3.2), Vector3(-3.7, 1.0, -1.6), _c(Color(0.7, 0.34, 0.05), 0.45, 0.4), true, Vector3(0, -0.6, 0))
	for sx in [-1, 1]:
		for sx2 in [-2.2, 2.4]:
			Props.cyl(r, 0.55, 0.45, Vector3(sx2, 0.55, sx * 1.2), dark, false, -1.0, Vector3(PI * 0.5, 0, 0))
	# the beacon: an amber dome and a rotating spot that sweeps the street
	Props.cyl(r, 0.18, 0.2, Vector3(-1.6, 3.35, 0), dark, false)
	Props.sphere(r, 0.2, Vector3(-1.6, 3.55, 0), _em(Color(1.0, 0.55, 0.05), 6.0), Vector3(1, 0.8, 1))
	_beacon = Node3D.new()
	_beacon.position = p + Vector3(-1.6, 3.55, 0)
	add_child(_beacon)
	var sp := SpotLight3D.new()
	sp.light_color = Color(1.0, 0.55, 0.1)
	sp.light_energy = 9.0
	sp.spot_range = 24.0
	sp.spot_angle = 24.0
	sp.shadow_enabled = false
	sp.light_volumetric_fog_energy = 2.0
	sp.rotation_degrees = Vector3(-8, 0, 0)
	_beacon.add_child(sp)
	var sp2 := sp.duplicate() as SpotLight3D
	sp2.rotation_degrees = Vector3(-8, 180, 0)
	sp2.rotation = Vector3(deg_to_rad(-8), PI, 0)
	_beacon.add_child(sp2)
	light(p + Vector3(-1.6, 3.7, 0), Color(1.0, 0.55, 0.1), 1.0, 7.0, false)
	light(p + Vector3(1.0, 3.0, -3.5), Color(0.8, 0.85, 1.0), 1.4, 11.0, false)
	_drift(p + Vector3(-5.3, 0, 2.6), Vector3(3.0, 1.0, 2.2))
	Props.corpse(geo, p + Vector3(-2.7, 0.02, 2.2), 0.5, {"shirt": Color(0.9, 0.5, 0.1), "bloody": 0.2, "coat": true, "coat_color": Color(0.9, 0.45, 0.08), "skin": Color(0.72, 0.8, 0.85)})

# ------------------------------------------------------------------ ST. BRENDAN'S
func _cwall(a: Vector2, b: Vector2, gaps: Array = []) -> void:
	# gaps: [dist, width, top_y, sill_y]; stone plinth below 1.4 m, timber above
	var low: Array = []
	var up: Array = []
	for g in gaps:
		var top: float = g[2]
		var sill: float = g[3]
		if sill < 1.4:
			low.append([g[0], g[1], min(top, 1.4), sill])
		if top > 1.4:
			up.append([g[0], g[1], top - 1.4, max(sill - 1.4, 0.0)])
	wall(a, b, 1.4, "rock", 0.0, 0.5, low)
	wall(a, b, 5.6, "wood_panel", 1.4, 0.4, up)

func _pew(x: float, z: float, yaw: float, length := 4.8, tilt := 0.0, lift := 0.0) -> void:
	var r := Node3D.new()
	r.position = Vector3(x, lift, z)
	r.rotation = Vector3(0, yaw, tilt)
	geo.add_child(r)
	var w := Mats.get_mat("wood", 0.8)
	Props.box(r, Vector3(length, 0.1, 0.5), Vector3(0, 0.45, 0), w, true)
	Props.box(r, Vector3(length, 0.8, 0.07), Vector3(0, 0.9, -0.24), w, false)
	for sx in [-1, 1]:
		Props.box(r, Vector3(0.08, 1.0, 0.6), Vector3(sx * length * 0.5, 0.5, 0), w, false)

func _stained(pos: Vector3, along_z: bool, palette: Array, w := 1.3, h := 3.2) -> void:
	# a glowing frost-rimed window pane set into the wall plane
	var cols := palette.size()
	var cw := w / float(cols)
	for i in cols:
		var off := -w * 0.5 + cw * (i + 0.5)
		var size := Vector3(0.05, h, cw - 0.04) if along_z else Vector3(cw - 0.04, h, 0.05)
		var p := pos + (Vector3(0, 0, off) if along_z else Vector3(off, 0, 0))
		_b(size, p, _em(palette[i], 1.3), false)
	# lead cames
	for k in 4:
		var yy := pos.y - h * 0.5 + h * (k + 1) / 5.0
		var s2 := Vector3(0.07, 0.04, w) if along_z else Vector3(w, 0.04, 0.07)
		_b(s2, Vector3(pos.x, yy, pos.z), _c(Color(0.05, 0.05, 0.05), 0.5), false)
	# frost across the lower half
	var sf := Vector3(0.08, h * 0.35, w * 0.96) if along_z else Vector3(w * 0.96, h * 0.35, 0.08)
	_b(sf, pos + Vector3(0, -h * 0.33, 0), _glass(0.55, Color(0.85, 0.92, 1.0)), false)

func _build_church() -> void:
	var X0 := 38.0
	var X1 := 54.0
	var ZF := -8.0
	var ZB := -42.0
	var ZA := -18.0
	# --- floor (raised 4 cm to avoid z-fighting with the snow)
	floor_rect(X0, ZB, X1, ZF, 0.04, "wood_floor", 0.1)
	# --- outer walls
	var win_d := [14.0, 20.0, 26.0]   # distance from the front along the long walls
	var west_gaps := [[3.0, 1.6, 2.5, 0.0]]
	var east_gaps := []
	for d in win_d:
		west_gaps.append([d, 1.3, 5.2, 2.0])
		east_gaps.append([d, 1.3, 5.2, 2.0])
	west_gaps.append([31.0, 1.3, 5.2, 2.0])
	east_gaps.append([31.0, 1.3, 5.2, 2.0])
	east_gaps.append([5.0, 0.6, 5.2, 4.0])
	_cwall(Vector2(X0, ZF), Vector2(X0, ZB), west_gaps)
	_cwall(Vector2(X1, ZF), Vector2(X1, ZB), east_gaps)
	_cwall(Vector2(X0, ZF), Vector2(X1, ZF), [[5.5, 3.0, 3.5, 0.0], [1.8, 0.9, 5.2, 2.4], [9.8, 0.9, 5.2, 2.4]])
	_cwall(Vector2(X0, ZB), Vector2(X1, ZB), [])
	# nave arch wall (z=-18) with a wide opening; narthex/tower west wall (x=49)
	_cwall(Vector2(X0, ZA), Vector2(X1, ZA), [[5.0, 8.0, 4.8, 0.0]])
	wall(Vector2(49.0, ZF), Vector2(49.0, ZA), 10.8, "wood_panel", 0.0, 0.3, [[1.3, 1.6, 2.4]])
	# narthex ceiling + attic, tower shaft and cap
	ceiling_rect(X0, ZA, 49.0, ZF, 3.4, "wood_panel")
	box(Vector3(43.5, 5.55, -13.0), Vector3(11.0, 3.8, 10.0), "wood_panel", false)
	box(Vector3(43.5, 7.65, -13.0), Vector3(10.4, 0.4, 10.4), "snow", false)
	# tower upper walls (above the common wall height) and steeple
	for s in [[Vector3(51.5, 9.0, ZF), Vector3(5.0, 4.0, 0.4)], [Vector3(51.5, 9.0, ZA), Vector3(5.0, 4.0, 0.4)], [Vector3(X1, 9.0, -13.0), Vector3(0.4, 4.0, 10.0)]]:
		box(s[0], s[1], "wood_panel", false)
	ceiling_rect(49.0, ZA, X1, ZF, 10.8, "wood_panel")
	_cy(4.0, 3.6, Vector3(51.5, 13.6, -13.0), "metal_rust", false, 0.1, Vector3(0, PI * 0.25, 0), 4)
	_cy(0.05, 2.2, Vector3(51.5, 16.4, -13.0), "metal", false)
	_b(Vector3(0.9, 0.08, 0.08), Vector3(51.5, 16.9, -13.0), "metal", false)
	_b(Vector3(0.08, 1.4, 0.08), Vector3(51.5, 16.7, -13.0), "metal", false)
	_b(Vector3(5.2, 0.4, 10.4), Vector3(51.5, 11.0, -13.0), "snow", false)
	# belfry louvres: dark slats in the shaft walls
	for i in 5:
		_b(Vector3(0.06, 0.12, 1.4), Vector3(53.74, 8.2 + i * 0.35, -13.0), "wood", false, Vector3(0.4, 0, 0))
	# nave: pitched timber roof (z -42..-18), gables, tie beams
	var ang := atan2(3.5, 8.0)
	var rlen := sqrt(8.0 * 8.0 + 3.5 * 3.5) + 0.6
	for sx in [-1, 1]:
		_b(Vector3(rlen, 0.3, 24.8), Vector3(46.0 + sx * 4.1, 8.8, -30.0), "metal_rust", false, Vector3(0, 0, -sx * ang))
	# gable fill (stepped) at both ends of the nave
	for zg in [ZA, ZB]:
		for st in [[14.6, 1.1, 7.55], [10.8, 1.1, 8.65], [6.6, 1.1, 9.75], [2.6, 1.0, 10.8]]:
			_b(Vector3(st[0], st[1], 0.4), Vector3(46.0, st[2], zg), "wood_panel", false)
	for z in [-21.0, -26.0, -31.0, -36.0, -40.5]:
		_b(Vector3(15.6, 0.35, 0.3), Vector3(46.0, 6.85, z), "wood", false)
		for sx in [-1, 1]:
			_b(Vector3(0.25, 3.2, 0.25), Vector3(46.0 + sx * 3.6, 8.2, z), "wood", false, Vector3(0, 0, sx * -0.65))
	# --- the sealed front doors (ice) and the real side door
	door("l3_front", Vector3(43.5, 0.04, ZF), 0.0, {"double": true, "width": 2.8, "height": 3.4, "mat": "wood_panel", "lock_flag": "l3_never", "locked_msg": "The doors are sealed shut by a half-metre of ice. There must be another way in."})
	_b(Vector3(3.1, 3.6, 0.35), Vector3(43.5, 1.8, ZF - 0.3), "ice", false)
	_b(Vector3(3.3, 0.5, 0.5), Vector3(43.5, 0.2, ZF - 0.4), "snow", false)
	_icicles(Vector3(41.9, 3.7, ZF - 0.4), Vector3(45.1, 3.7, ZF - 0.4), 10, 1.4)
	_stained(Vector3(39.8, 3.85, ZF), false, [Color(0.9, 0.2, 0.15), Color(0.95, 0.75, 0.2)], 0.9, 2.8)
	_stained(Vector3(47.8, 3.85, ZF), false, [Color(0.2, 0.35, 0.9), Color(0.2, 0.7, 0.4)], 0.9, 2.8)
	_sign(Vector3(43.5, 5.75, ZF - 0.35), 0.0, "ST. BRENDAN'S", 76, Color(0.86, 0.84, 0.76), false)
	_sign(Vector3(43.5, 5.15, ZF - 0.35), 0.0, "ADVENT SERVICES  —  ALL ARE WELCOME", 28, Color(0.78, 0.76, 0.7), false)
	door("l3_side", Vector3(X0, 0.04, -11.0), PI * 0.5, {"width": 1.4, "height": 2.3, "mat": "wood_panel", "lock_item": "church_key", "locked_msg": "Locked. A tag on the frame reads: 'Sacristy key — see D. Halloran'."})
	_b(Vector3(0.12, 0.1, 1.9), Vector3(37.4, 0.1, -11.0), "snow", false)
	_icicles(Vector3(37.55, 2.7, -11.8), Vector3(37.55, 2.7, -10.2), 6, 0.6)
	# --- stained glass along both naves, with coloured moonlight pooling on the floor
	var pal := [
		[Color(0.15, 0.25, 0.85), Color(0.8, 0.15, 0.2), Color(0.15, 0.25, 0.85)],
		[Color(0.9, 0.65, 0.15), Color(0.15, 0.55, 0.3), Color(0.9, 0.65, 0.15)],
		[Color(0.7, 0.15, 0.3), Color(0.2, 0.3, 0.85), Color(0.7, 0.15, 0.3)],
		[Color(0.2, 0.6, 0.45), Color(0.85, 0.7, 0.2), Color(0.2, 0.6, 0.45)],
	]
	var wi := 0
	for d in [14.0, 20.0, 26.0, 31.0]:
		var wz: float = ZF - d
		_stained(Vector3(X0 + 0.0, 3.6, wz), true, pal[wi % 4])
		_stained(Vector3(X1 - 0.0, 3.6, wz), true, pal[(wi + 2) % 4])
		var col_w: Color = pal[wi % 4][1]
		var col_e: Color = pal[(wi + 2) % 4][1]
		var sh := wi == 1
		var sp1 := spot(Vector3(X0 + 0.5, 5.3, wz), Vector3(X0 + 6.5, 0.0, wz + 1.2), col_w, 3.2, 14.0, 26.0, sh)
		var sp2 := spot(Vector3(X1 - 0.5, 5.3, wz), Vector3(X1 - 6.5, 0.0, wz - 1.2), col_e, 3.2, 14.0, 26.0, sh)
		_nave_spots.append([sp1, 3.2])
		_nave_spots.append([sp2, 3.2])
		wi += 1
	# tower slit window
	_b(Vector3(0.05, 1.2, 0.5), Vector3(X1, 4.6, -13.0), _em(Color(0.5, 0.7, 1.0), 1.4), false)
	# the rose window above the altar
	_cy(1.5, 0.08, Vector3(46.0, 5.9, ZB + 0.1), _em(Color(0.7, 0.2, 0.3), 1.3), false, -1.0, Vector3(PI * 0.5, 0, 0), 24)
	for k in 8:
		_b(Vector3(3.0, 0.06, 0.05), Vector3(46.0, 5.9, ZB + 0.16), _c(Color(0.05, 0.05, 0.05), 0.5), false, Vector3(0, 0, k * PI / 8.0))
	_cy(0.5, 0.1, Vector3(46.0, 5.9, ZB + 0.14), _em(Color(0.9, 0.7, 0.2), 1.6), false, -1.0, Vector3(PI * 0.5, 0, 0), 16)
	var rose := spot(Vector3(46.0, 6.0, ZB + 0.9), Vector3(46.0, 0.0, -30.0), Color(0.75, 0.25, 0.4), 4.0, 16.0, 34.0, false)
	_nave_spots.append([rose, 4.0])
	# --- chancel: platform, altar, cross, organ, pulpit
	stairs(Vector3(46.0, 0.04, -34.0), 9.0, 1.1, 0.34, "-z", "wood_floor")
	floor_rect(X0 + 0.25, ZB + 0.2, X1 - 0.25, -35.1, 0.38, "wood_floor", 0.34)
	var alt := Vector3(46.0, 0.38, -40.2)
	_b(Vector3(3.2, 1.0, 1.1), alt + Vector3(0, 0.5, 0), "marble", true)
	_b(Vector3(3.5, 0.06, 1.3), alt + Vector3(0, 1.03, 0), _c(Color(0.9, 0.9, 0.88), 0.9), false)
	_b(Vector3(3.6, 0.9, 1.35), alt + Vector3(0, 0.5, 0.02), _c(Color(0.75, 0.75, 0.74, 1.0), 0.95), false)
	_b(Vector3(0.28, 3.0, 0.2), Vector3(46.0, 3.5, ZB + 0.3), "wood", false)
	_b(Vector3(1.4, 0.26, 0.2), Vector3(46.0, 4.2, ZB + 0.3), "wood", false)
	_candles(alt + Vector3(-1.1, 1.06, 0), 5, 0.25, 0.8)
	_candles(alt + Vector3(1.1, 1.06, 0), 5, 0.25, 0.8)
	_candles(Vector3(43.0, 0.4, -37.0), 9, 0.6, 0.6)
	_candles(Vector3(49.0, 0.4, -37.0), 9, 0.6, 0.6)
	Props.statue(geo, Vector3(41.2, 0.38, -40.0), 0.5)
	# organ: console + pipes
	_b(Vector3(1.9, 1.3, 1.1), Vector3(40.4, 0.65 + 0.38, -38.0), "wood_panel", true)
	_b(Vector3(1.7, 0.08, 0.5), Vector3(40.9, 1.75, -38.0), _c(Color(0.9, 0.9, 0.85), 0.5), false)
	Props.bench(geo, Vector3(41.8, 0.38, -38.0), PI * 0.5)
	for i in 11:
		var ph := 2.0 + (i % 6) * 0.6 + (1.5 if i > 4 and i < 8 else 0.0)
		_cy(0.09, ph, Vector3(38.7, 0.38 + ph * 0.5 + 1.0, -41.0 + i * 0.5), _c(Color(0.62, 0.58, 0.45), 0.35, 0.8), false, -1.0, Vector3.ZERO, 10)
	_b(Vector3(0.3, 0.9, 5.6), Vector3(38.5, 1.0, -38.2), "wood_panel", false)
	# pulpit
	_b(Vector3(1.0, 1.3, 1.0), Vector3(51.8, 0.38 + 0.65, -36.4), "wood_panel", true)
	_b(Vector3(1.2, 0.08, 1.2), Vector3(51.8, 0.38 + 1.34, -36.4), "wood", false)
	# --- pews: intact rows near the entrance, a barricade line toward the chancel
	for zz in [-19.7, -21.5]:
		_pew(41.4, zz, 0.0, 5.0)
		_pew(50.6, zz, 0.0, 5.0)
	_pew(41.3, -23.3, 0.0, 5.0, 0.0)
	_pew(50.8, -23.4, 0.12, 4.6)
	_pew(41.0, -25.1, 0.2, 4.8, 0.0)
	_pew(50.8, -25.0, 0.0, 4.8)
	# barricades facing the chancel: tipped and stacked pews = cover for the fight
	_pew(41.6, -28.0, -0.15, 4.6, 0.0)
	_pew(41.4, -28.5, -0.1, 4.2, 1.15, 0.0)
	_pew(40.2, -29.6, 1.35, 3.8, 0.25, 0.35)
	_pew(50.4, -28.2, 0.12, 4.6, 0.0)
	_pew(50.6, -28.7, 0.1, 4.2, -1.1, 0.0)
	_pew(52.0, -29.8, 1.8, 3.8, -0.3, 0.35)
	_pew(44.0, -31.4, 0.5, 2.2, 0.0)             # stray pew left in the aisle (cover, not a wall)
	_pew(48.2, -26.4, -0.4, 2.0, 0.0)
	Props.chair(geo, Vector3(46.4, 0.04, -24.0), 0.0, true)
	Props.debris(geo, Vector3(46.0, 0.04, -27.0), 0.0, 6, "wood")
	Props.papers(geo, Vector3(46.5, 0.05, -22.5), 9)
	Props.blood_pool(geo, Vector3(44.8, 0.05, -29.5), 2.0)
	_b(Vector3(1.8, 0.04, 14.0), Vector3(46.0, 0.07, -25.0), _c(Color(0.35, 0.07, 0.07), 1.0), false)   # aisle runner
	# candles on pew ends and the aisle: a vigil
	_candles(Vector3(44.0, 0.05, -22.3), 6, 0.5, 0.7)
	_candles(Vector3(48.0, 0.05, -24.2), 6, 0.5, 0.7)
	_candles(Vector3(46.0, 0.05, -20.0), 5, 0.4, 0.6)
	# cold fill so the nave reads as a space, not a void
	var fill := light(Vector3(46.0, 6.0, -28.0), Color(0.45, 0.55, 0.85), 0.8, 18.0, false)
	_nave_spots.append([fill, 0.8])
	# frost on the nave floor along the walls, drifts under the broken glass
	_b(Vector3(1.4, 0.05, 20.0), Vector3(38.9, 0.07, -29.0), "frost", false)
	_b(Vector3(1.4, 0.05, 20.0), Vector3(53.1, 0.07, -29.0), "frost", false)
	_b(Vector3(1.8, 0.5, 2.4), Vector3(38.9, 0.28, -26.0), "snow", false, Vector3(0, 0, 0.2))
	# --- narthex dressing
	Props.table(geo, Vector3(40.2, 0.04, -15.8), 0.0, Vector2(1.6, 0.7))
	Props.bench(geo, Vector3(43.0, 0.04, -9.2), PI)
	_cy(0.25, 0.9, Vector3(47.8, 0.49, -16.2), "marble", true)    # holy-water font
	_cy(0.3, 0.1, Vector3(47.8, 0.97, -16.2), _c(Color(0.55, 0.7, 0.8, 1.0), 0.1), false)
	_b(Vector3(0.9, 1.7, 0.2), Vector3(40.4, 1.2, -8.3), "wood_panel", false)
	_sign(Vector3(40.4, 1.5, -8.42), PI, "HYMNS: 214  118  304", 22, Color(0.85, 0.85, 0.8), false)
	Props.corpse(geo, Vector3(39.4, 0.04, -9.7), 1.5, {"shirt": Color(0.1, 0.1, 0.12), "pants": Color(0.1, 0.1, 0.12), "bloody": 0.1, "skin": Color(0.72, 0.8, 0.85)})
	_candles(Vector3(40.3, 0.8, -15.8), 4, 0.25, 0.0)
	light(Vector3(41.0, 1.6, -14.0), Color(1.0, 0.75, 0.45), 1.5, 8.0, true, true)
	light(Vector3(46.0, 2.5, -10.0), Color(0.55, 0.65, 0.9), 0.7, 7.0, false)
	# --- bell tower: stairs, loft, bell, chain
	_candles(Vector3(52.8, 0.05, -9.5), 3, 0.2, 0.0, true)
	stairs(Vector3(52.2, 0.04, -9.6), 2.2, 5.8, 2.96, "-z", "wood")
	floor_rect(49.15, ZA + 0.15, X1 - 0.2, -15.5, 3.0, "wood_floor", 0.3)
	_b(Vector3(0.08, 1.0, 1.9), Vector3(49.3, 3.5, -16.5), "wood", false)
	_b(Vector3(0.08, 1.0, 2.3), Vector3(53.6, 3.5, -16.8), "wood", false)
	_bell_node = Node3D.new()
	_bell_node.position = Vector3(51.5, 7.0, -16.4)
	add_child(_bell_node)
	var bronze := _c(Color(0.55, 0.38, 0.14), 0.35, 0.9)
	Props.cyl(_bell_node, 0.75, 1.1, Vector3(0, -0.1, 0), bronze, false, 0.3, Vector3.ZERO, 20)
	Props.sphere(_bell_node, 0.14, Vector3(0, -0.72, 0), bronze)
	Props.box(_bell_node, Vector3(1.8, 0.2, 0.3), Vector3(0, 0.7, 0), Mats.get_mat("wood"), false)
	_b(Vector3(0.3, 0.3, 4.2), Vector3(51.5, 7.75, -15.5), "wood", false)
	_cy(0.012, 2.9, Vector3(51.5, 4.9, -16.4), _c(Color(0.25, 0.25, 0.27), 0.5, 0.8), false, -1.0, Vector3.ZERO, 6)   # the pull-chain, handle missing
	light(Vector3(51.5, 3.9, -15.0), Color(0.9, 0.78, 0.55), 0.9, 6.0, false)
	light(Vector3(52.0, 1.8, -10.6), Color(0.7, 0.8, 1.0), 0.6, 5.0, false)
	_sign(Vector3(51.5, 3.9, -17.88), 0.0, "RING FOR VESPERS", 22, Color(0.8, 0.75, 0.6), false)
	_build_bell_interact()
	# --- items: key item + pickups in the tower foot, narthex and nave
	if not Game.has_item("bell_rope") and not Game.has_flag("l3_bell_fitted"):
		pickup("l3_bell_rope", "bell_rope", 1, Vector3(53.0, 0.12, -8.9))
	_b(Vector3(1.8, 0.05, 0.08), Vector3(52.9, 0.1, -9.1), "wood", false, Vector3(0, 0.3, 0))
	pickup("l3_amm_church", "ammo_9mm", 4, Vector3(39.4, 0.1, -16.8))
	pickup("l3_adren", "adrenaline", 1, Vector3(40.1, 0.84, -15.4))
	# --- notes
	_note2("l3_note_sermon", Vector3(40.7, 0.83, -15.9), "Sermon Draft: Advent IV",
		"[b]SERMON — ADVENT IV (draft, unfinished)[/b]\n\nThey ask us to give thanks for the jobs. For the mine, for the data centre, for the lithium that will make tomorrow cleaner. I have stood in this pulpit nineteen years and given thanks for worse.\n\nBut I buried eleven men from the Lower Kettle in 2011, and nobody thanked them on the way down. [crossed out: The new people are polite. They sent the parish a fruit basket and a letter about community heat credits.]\n\nTonight this is the only building in Kettle Falls with a wood stove, and sixty people came. I don't know what to say to them.\n\n[in pencil, below] Say nothing. Light the candles. Keep them awake. KEEP THEM AWAKE.\n\n[in a different hand] The singing started at three. It sounds like us. Ruth Kade stayed past midnight with the blankets. I told her to go home to the school. She said the lake was calling.", 0.2)
	_note2("l3_note_altar", Vector3(45.4, 1.45, -40.1), "Mom's Note",
		"[b]Elias —[/b]\n\nI know you'll come. You always said you were coming. I've stopped being angry about it.\n\nI'm going down to the mine tonight. Your father is calling me from the lake. I'm a nurse, Elias — I know what a fever dream sounds like, and I know this isn't one. It doesn't matter. It's his voice, and it says my name the way he said it in the kitchen.\n\nI came here to say goodbye to a few people. They were already singing. They let me through. I think they know me.\n\nJune followed me out of the school. I sent her back. I don't think she went.\n\nIf you find my rosary, keep it. If you find me, don't let me be the thing that's singing.\n\n— Mom", 0.3)

# ------------------------------------------------------------------ MERIDIAN on the horizon
func _build_meridian() -> void:
	var white := _em(Color(0.7, 0.85, 1.0), 6.5)
	var dim := _em(Color(0.45, 0.65, 1.0), 4.0)
	var shell := _c(Color(0.1, 0.12, 0.15), 0.5, 0.4)
	# main data hall
	box(Vector3(150, 9.0, -30), Vector3(56, 18.0, 44), shell, false)
	for i in 5:
		_b(Vector3(0.6, 0.9, 40.0), Vector3(122.0, 4.0 + i * 2.8, -30.0), white, false)
	for i in 5:
		_b(Vector3(0.6, 0.9, 36.0), Vector3(122.0, 5.0 + i * 2.8, -30.0), white, false)
	for i in 3:
		_b(Vector3(0.7, 1.4, 6.0), Vector3(121.9, 18.9, -48.0 + i * 12.0), white, false)
	# annex halls
	box(Vector3(160, 6.0, 24), Vector3(40, 12.0, 24), shell, false)
	for i in 4:
		_b(Vector3(0.6, 0.8, 22.0), Vector3(139.8, 3.0 + i * 2.5, 24.0), dim, false)
	box(Vector3(185, 7.0, -62), Vector3(30, 14.0, 20), shell, false)
	for i in 3:
		_b(Vector3(0.6, 0.8, 18.0), Vector3(169.8, 4.0 + i * 3.0, -62.0), dim, false)
	# cooling towers and the exhaust stack
	for p in [Vector3(130, 0, -62), Vector3(140, 0, -74), Vector3(150, 0, -62)]:
		_cy(5.5, 22.0, p + Vector3(0, 11.0, 0), shell, false, 4.2, Vector3.ZERO, 20)
		_cy(4.4, 0.8, p + Vector3(0, 22.2, 0), white, false, -1.0, Vector3.ZERO, 20)
	_cy(1.8, 40.0, Vector3(170, 20.0, -10), shell, false)
	Props.sphere(geo, 0.6, Vector3(170, 40.4, -10), _em(Color(1.0, 0.05, 0.03), 8.0))
	# steam plume
	var steam := CPUParticles3D.new()
	steam.amount = 60
	steam.lifetime = 7.0
	steam.direction = Vector3.UP
	steam.spread = 8.0
	steam.initial_velocity_min = 2.0
	steam.initial_velocity_max = 3.0
	steam.gravity = Vector3(1.0, 0.2, 0)
	steam.scale_amount_min = 3.0
	steam.scale_amount_max = 7.0
	var qs := SphereMesh.new()
	qs.radius = 0.5
	qs.height = 1.0
	steam.mesh = qs
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.55, 0.7, 0.9, 0.18)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	steam.material_override = smat
	steam.position = Vector3(140, 24, -74)
	add_child(steam)
	light(Vector3(118, 14, -30), Color(0.55, 0.75, 1.0), 4.0, 70.0, false)
	light(Vector3(130, 6, 10), Color(0.55, 0.75, 1.0), 2.5, 50.0, false)
	# perimeter lights along the shoreline
	for i in 10:
		_b(Vector3(0.3, 0.3, 0.3), Vector3(118.0, 3.0, -52.0 + i * 8.0), white, false)

# ------------------------------------------------------------------ enemies
func _dz(uid: String, pos: Vector3, yaw: float, params := {}) -> Node3D:
	var p := {"dormant": true, "variant": "civilian"}
	p.merge(params, true)
	var e := enemy(uid, "zombie", pos, yaw, p)
	if e != null:
		_dormant.append(e)
	return e

func _build_enemies() -> void:
	# frozen mid-motion in the street: dormant until gunfire, the siren, or the bell
	_dz("l3_z1", Vector3(-58.0, 0, -1.8), 1.3)
	_dz("l3_z2", Vector3(-44.0, 0, 3.0), -0.6)
	_dz("l3_z3", Vector3(-27.0, 0, 1.2), 2.6)
	_dz("l3_z4", Vector3(-3.0, 0, -3.6), 0.4)
	_dz("l3_z5", Vector3(12.0, 0, -9.5), 1.0)
	_dz("l3_z6", Vector3(24.5, 0, -27.0), 0.0, {"sleeping": true, "dormant": false})
	_dz("l3_z7", Vector3(34.0, 0, -3.5), -1.4)
	_dz("l3_z8", Vector3(20.0, 0, 2.6), 3.0)
	_dz("l3_cr1", Vector3(54.0, 0, 2.5), 2.0, {"crawler": true})
	_dz("l3_cr2", Vector3(60.5, 0, -2.0), 1.0, {"crawler": true})
	# pharmacy: a sleeper on a mattress, and Dolores Halloran who still wears the key
	enemy("l3_z_cot", "zombie", Vector3(-34.4, 0.1, -9.4), 0.0, {"sleeping": true, "variant": "civilian"})
	_dz("l3_z_pharm", Vector3(-38.6, 0, -17.2), 0.6, {"variant": "medic"})
	# siren in the diner kitchen, husk by the plow
	enemy("l3_siren", "siren", Vector3(-14.2, 0, -16.6), 3.0)
	enemy("l3_husk", "husk", Vector3(-1.6, 0, 3.4), 2.5)
	# the Foreman, if already triggered
	if Game.has_flag("l3_foreman_on") and not Game.has_flag("choir_dead"):
		_spawn_foreman(Vector3(-72.0, 0, 0.0))
	# the Choir waits in the chancel (dormant) until the reveal
	if not Game.has_flag("choir_dead"):
		_spawn_choir(not Game.has_flag("l3_fight_started"))
	else:
		_place_altar_loot()

func _spawn_foreman(pos: Vector3) -> void:
	foreman = enemy("l3_foreman", "foreman", pos, 0.0, {"stalk": true})

func _spawn_choir(dormant: bool) -> void:
	boss = enemy("l3_boss", "boss_choir", Vector3(46.0, 0.4, -37.0), 0.0, {"dormant": dormant})
	if boss != null:
		boss.died.connect(_on_choir_died)
		if not dormant:
			_boss_active = true

# ------------------------------------------------------------------ items & shop notes (placed here to keep build() tidy)
func _build_triggers() -> void:
	_build_items()
	# the Foreman appears behind you on Main Street
	trigger("l3_t_foreman", Vector3(-52.0, 1.5, 0.0), Vector3(1.2, 4.0, 12.0), _foreman_intro)
	# a first hint about fire & shops, once, at the first burning barrel
	trigger("l3_t_hint", Vector3(-62.0, 1.5, 0.0), Vector3(1.2, 4.0, 12.0), func(_p):
		UI.toast("Burning barrels and flares keep the Rimebound back. Shops break their line of sight.", 5.0))
	# diner: the siren's call
	trigger("l3_t_diner", Vector3(-19.0, 1.4, -8.2), Vector3(3.0, 3.0, 1.5), _diner_hum)
	# church: the reveal
	trigger("l3_t_choir", Vector3(43.0, 1.5, -19.2), Vector3(8.0, 3.0, 1.0), _choir_reveal)
	# leaving the nave after the fight etc: ambience stays as is

func _build_items() -> void:
	# --- diner
	pickup("l3_amm_diner", "ammo_9mm", 6, Vector3(-20.0, 1.13, -12.0))
	pickup("l3_adren_diner", "adrenaline", 1, Vector3(-18.0, 1.13, -12.2))
	_note2("l3_note_corvane", Vector3(-24.2, 0.78, -8.2), "Corvane Community Heat Credit",
		"[b]CORVANE SYSTEMS — Community Partnerships[/b]\n\nDear Kettle Falls Neighbor,\n\nWe are delighted to enrol your household in the [b]Community Heat Credit[/b]: $40 each month, applied automatically to your winter heating bill, for as long as MERIDIAN remains a proud member of the Kettle Falls community.\n\nBecause MERIDIAN draws less cooling load in winter, we are able to share the benefits of our efficiency with you. Isn't that what neighbours do?\n\n[font_size=11]Credits are suspended during Grid Priority Events. A Grid Priority Event is declared at the sole discretion of the Operator.[/font_size]\n\nWarmly,\nBrooke A. Lindahl\nDirector, Community Partnerships", 0.4)
	# --- pharmacy
	pickup("l3_key", "church_key", 1, Vector3(-37.4, 0.07, -16.6))
	pickup("l3_trauma", "spray", 1, Vector3(-35.0, 1.16, -13.2))
	pickup("l3_gel_pharm", "gel", 1, Vector3(-31.6, 0.1, -14.0))
	_note2("l3_note_pharm", Vector3(-38.6, 1.13, -13.2), "Pharmacy Cold-Exposure Log",
		"[b]KETTLE FALLS PHARMACY — COLD EXPOSURE LOG[/b]\n\nDec 18, 22:10 — M. Brandvold, 71. Core temp 91.4. Warmed up, refused to leave. Fell asleep in the chair.\n\nDec 19, 03:40 — Three on cots. All asleep. They don't wake. They are not cold the way they should be. They are colder than that.\n\nDec 19, 05:15 — Checked an airway. Frost inside the mouth. Not on the lips: inside. On the tongue, down the throat. Fine white needles, like a freezer shelf. I closed the mouth. It opened again.\n\nDec 19, 06:00 — Whatever else you do, do not let them sleep.\n\n[i]— D.H.[/i]  (the sacristy key is on my lanyard, if Father Okafor sends anyone)", 0.1)
	# --- hardware
	pickup("l3_shotgun", "shotgun", 1, Vector3(5.2, 0.12, 12.8))
	pickup("l3_shells", "ammo_shell", 12, Vector3(7.8, 0.1, 12.9))
	pickup("l3_flares", "flare", 3, Vector3(15.35, 0.99, 8.0))
	pickup("l3_amm_hw", "ammo_9mm", 6, Vector3(15.35, 0.99, 16.4))
	pickup("l3_amm_hw2", "ammo_9mm", 4, Vector3(5.2, 0.99, 19.6))
	_note2("l3_note_tally", Vector3(3.2, 1.12, 10.4), "Cardboard Sign: Lindqvist Hardware",
		"[b](marker, on a flattened box)[/b]\n\nSPACE HEATERS — SOLD OUT (Tues)\nROCK SALT — SOLD OUT\nPROPANE — 4 LEFT. KIDS AND OLD FIRST.\nCASH — I DON'T WANT YOUR CASH.\n\nSHELLS: 12 LEFT. I'M KEEPING 2.\n\nCounted them from the roof. Eleven on Main at midnight. Nineteen by three. They don't run. They just come, like it's closing time and they're all headed for the same door.\n\nGave the Halvorsen girl my last heater. Went back for the shotgun. If you're reading this it's behind the counter. It's yours. It's loud, and they listen to loud.\n\n— Don Lindqvist. Open since 1954. Still open.", 0.0)
	# --- the church door notice (also sets the objective)
	_b(Vector3(0.9, 1.0, 0.55), Vector3(41.0, 0.5, -6.8), "wood", true)
	_sign(Vector3(41.0, 1.6, -6.8), 0.0, "NOTICE — READ ME", 24, Color(0.85, 0.85, 0.8), true)
	_note2("l3_note_door", Vector3(41.0, 1.03, -6.8), "Notice on the Church Door",
		"[b]ST. BRENDAN'S — NOTICE[/b]\n\nServices and warming hours are moved to the sacristy until the heat comes back. Please use the SIDE DOOR on the west wall. The front doors have frozen shut; do not force them. Those hinges are the oldest thing in Kettle Falls and I would like them to outlast me.\n\nThe sacristy key is with Dolores Halloran at the pharmacy. She keeps it on her lanyard with the safe key; she has been helping with the elderly.\n\nBring a blanket if you can spare one. Do not sleep in the pews.\n\n[i]— Fr. Emeka Okafor[/i]\n\nP.S. If you hear singing at night, it isn't us.", PI,
		func():
			if not Game.has_flag("l3_key_hint") and not Game.has_item("church_key"):
				Game.set_flag("l3_key_hint")
				Game.set_objective("Find the sacristy key — Kettle Falls Pharmacy, west end of Main Street."))

func on_pickup(item: String, uid: String) -> void:
	match item:
		"church_key":
			Game.set_objective("Unlock the side door of St. Brendan's (west wall).")
			for e in _dormant:
				if is_instance_valid(e) and e.get("uid") == "l3_z_pharm":
					UI.toast("The pharmacist's hand closes on your wrist.", 3.0)
					Sfx.play("stinger_a")
					e.wake()
		"shotgun":
			UI.toast("The Pump Shotgun spreads wide up close. It's loud, and they listen to loud.", 5.0)
		"rosary":
			Game.set_flag("has_rosary")
			_june_call()

# ------------------------------------------------------------------ the exit gate
func _build_exit() -> void:
	Props.fence(geo, Vector3(72, 0, -50), Vector3(72, 0, -3.0), 2.8)
	Props.fence(geo, Vector3(72, 0, 3.0), Vector3(72, 0, 50), 2.8)
	for z in [-3.0, 3.0]:
		_cy(0.16, 3.2, Vector3(72, 1.6, z), "metal_painted", true)
	_b(Vector3(0.2, 0.25, 6.4), Vector3(72, 3.2, 0), "metal_painted", false)
	_icicles(Vector3(71.9, 3.1, -2.8), Vector3(71.9, 3.1, 2.8), 12, 0.6)
	door("l3_gate", Vector3(72.0, 0.02, 0.0), PI * 0.5, {"double": true, "width": 5.0, "height": 2.6, "mat": "metal", "to_level": "l4_meridian", "to_spawn": "start",
		"lock_flag": "has_rosary", "locked_msg": "The lakeside gate is chained and frozen shut. You can't leave Mom behind.", "prompt": "Go through the gate"})
	_sign(Vector3(71.5, 3.6, 0.0), -PI * 0.5, "LAKESHORE ROAD — MERIDIAN SITE ACCESS — AUTHORIZED PERSONNEL ONLY", 36, Color(0.85, 0.85, 0.8), true)
	_sign(Vector3(71.4, 2.1, -3.9), -PI * 0.5, "NO TRESPASSING — CORVANE SYSTEMS", 26, Color(0.8, 0.3, 0.25), true)
	light(Vector3(69.0, 3.4, 0.0), Color(0.6, 0.78, 1.0), 1.2, 12.0, false)

func _music_safe(_p) -> void:
	if not _boss_active:
		Sfx.music("music_safe")

func _music_tension(_p) -> void:
	if not _boss_active and not Game.has_flag("choir_dead"):
		Sfx.music("music_tension")

# =================================================================== ON ENTER
func on_enter() -> void:
	Sfx.music("music_tension")
	if not Game.has_flag("l3_title"):
		Game.set_flag("l3_title")
		UI.title_card("MAIN STREET", "St. Brendan's — Kettle Falls")
	if Game.has_flag("choir_dead"):
		if Game.has_flag("has_rosary") or Game.has_item("rosary"):
			Game.set_objective("Take the lakeside road to MERIDIAN (east gate).")
		else:
			Game.set_objective("Take Ruth's rosary from the altar of St. Brendan's.")
	elif Game.has_flag("l3_fight_started"):
		Game.set_objective("Silence the Choir. The bell in the tower stuns it.")
	elif Game.has_item("church_key"):
		Game.set_objective("Unlock the side door of St. Brendan's (west wall).")
	elif Game.has_flag("l3_key_hint"):
		Game.set_objective("Find the sacristy key — Kettle Falls Pharmacy, west end of Main Street.")
	else:
		Game.set_objective("Cross Main Street to St. Brendan's church, at the far east end.")
	if Game.has_flag("l3_fight_started") and not Game.has_flag("choir_dead"):
		Sfx.music("music_boss")

# =================================================================== BEATS
func _foreman_intro(_p) -> void:
	Game.set_flag("l3_foreman_on")
	Sfx.play("stinger_b")
	Sfx.music("music_chase", -8.0, 3.0)
	_spawn_foreman(Vector3(-76.0, 0, 0.0))
	await get_tree().create_timer(1.2).timeout
	await say([["ELIAS", "A headlamp. Back at the roadblock. Walking like the road's too short for him."],
		["ELIAS", "Light and heat. It's following the light. Get under cover."]])
	await get_tree().create_timer(6.0).timeout
	if not _boss_active:
		Sfx.music("music_tension", -8.0, 4.0)

func _diner_hum(_p) -> void:
	Sfx.play("stinger_a")
	UI.toast("A thin, wet humming comes from behind the counter.", 3.5)
	var siren_alive := false
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.get("uid") == "l3_siren":
			siren_alive = true
	if not siren_alive:
		await get_tree().create_timer(2.0).timeout
		_wake_dormant(Vector3(-19, 0, -10), 55.0)

func _wake_dormant(center: Vector3, radius: float) -> void:
	var left: Array = []
	for e in _dormant:
		if not is_instance_valid(e):
			continue
		if e.global_position.distance_to(center) < radius and e.state == "dormant":
			e.wake()
		else:
			left.append(e)
	_dormant = left

func _on_gunshot() -> void:
	if player == null:
		return
	_wake_dormant(player.global_position, 26.0)

func _choir_reveal(_p) -> void:
	if Game.has_flag("choir_dead") or Game.has_flag("l3_fight_started"):
		return
	Game.set_flag("l3_fight_started")
	lock_player(true)
	Sfx.play("stinger_a")
	# the vigil candles gutter and drop as the hum builds
	var tw := create_tween()
	tw.tween_property(self, "_nave_dim", 0.12, 2.5)
	await get_tree().create_timer(2.5).timeout
	await say([["ELIAS", "...Is that singing?"]])
	Sfx.play("ice_crack")
	await get_tree().create_timer(1.2).timeout
	await say([["ELIAS", "'Lo, How a Rose E'er Blooming.' Mom sang it every Advent. In the kitchen. Out of tune."],
		["ELIAS", "Halloran's cardigan. The Lindqvist boys' hockey jackets. They're all still here."],
		["ELIAS", "All of them. Standing in one place. Singing the same note."]])
	Sfx.play("stinger_b")
	var tw2 := create_tween()
	tw2.tween_property(self, "_nave_dim", 1.5, 1.0)
	_boss_active = true
	Sfx.music("music_boss")
	Game.set_objective("Silence the Choir. The bell in the tower stuns it (find the bell-pull handle).")
	if boss != null and is_instance_valid(boss):
		boss.set("dormant", false)
		boss.wake()
		_spawn_choir_crawlers()
		lock_player(false)
	else:
		# fallback: the boss type is not available yet — keep the level completable
		lock_player(false)
		UI.toast("The singing cracks, and stops. Something in the chancel gives way.", 4.0)
		await get_tree().create_timer(4.0).timeout
		_on_choir_died(null)

func _spawn_choir_crawlers() -> void:
	var spots := [Vector3(40.4, 0, -24.5), Vector3(52.2, 0, -24.0), Vector3(42.2, 0, -31.5), Vector3(51.0, 0, -32.0)]
	for i in spots.size():
		var cr := enemy("l3_choir_cr%d" % i, "zombie", spots[i], 0.0, {"crawler": true, "variant": "civilian"})
		if cr != null:
			cr.state = "chase"
			cr.awake = true

func _on_choir_died(_e) -> void:
	if Game.has_flag("choir_dead"):
		return
	Game.set_flag("choir_dead")
	_boss_active = false
	Sfx.play("ice_shatter")
	Sfx.music("music_safe", -8.0, 4.0)
	var tw := create_tween()
	tw.tween_property(self, "_nave_dim", 0.7, 3.0)
	# the Foreman withdraws toward the lake, headlamp last
	if foreman != null and is_instance_valid(foreman):
		foreman.queue_free()
		foreman = null
	UI.toast("The hum stops. For the first time tonight, you can hear the wind.", 4.5)
	await get_tree().create_timer(1.5).timeout
	_place_altar_loot()
	Game.set_objective("Take Ruth's rosary from the altar.")

func _place_altar_loot() -> void:
	if not Game.has_flag("got:l3_rosary"):
		var r := pickup("l3_rosary", "rosary", 1, Vector3(46.6, 1.47, -40.0))
		if r != null:
			light(Vector3(46.6, 1.7, -39.4), Color(0.85, 0.9, 1.0), 1.0, 4.0, false)

func _june_call() -> void:
	if Game.has_flag("l3_june_call"):
		return
	Game.set_flag("l3_june_call")
	await get_tree().create_timer(0.8).timeout
	lock_player(true)
	Sfx.play("radio_squelch")
	await say([
		["JUNE (radio)", "Dad? ...Dad, I can hear bells. Are you at the church? Please say yes."],
		["ELIAS", "Yes. It's over. I have Gran's rosary. June, where are you?"],
		["JUNE (radio)", "I followed her. I know, I know. She just kept walking toward the lake like she wasn't cold."],
		["JUNE (radio)", "There's a pipe from the data center going down into the mine. Gran went in through Meridian."],
		["ELIAS", "Stay warm. Stay off the road. Don't follow anyone else. I'm coming."],
		["JUNE (radio)", "You said that about Christmas, too. ...Just hurry."]])
	lock_player(false)
	Game.set_objective("Take the lakeside road to MERIDIAN (east gate).")
	UI.toast("The lakeside gate is open to you now.", 3.5)

# =================================================================== THE BELL
func _build_bell_interact() -> void:
	interact(Vector3(51.5, 3.1, -16.4), "Ring the church bell", _ring_bell, 1.8)

func _ring_bell(_p) -> void:
	if not Game.has_flag("l3_bell_fitted"):
		if Game.has_item("bell_rope"):
			Game.remove_item("bell_rope", 1)
			Game.set_flag("l3_bell_fitted")
			Sfx.play("unlock")
			UI.toast("You fit the handle onto the pull-chain.", 3.0)
			return
		UI.toast("The pull-chain hangs bare. The handle is missing.", 3.5)
		Sfx.play("deny")
		return
	if _bell_cd > 0.0:
		UI.toast("The bell is still swaying. (%d s)" % int(ceil(_bell_cd)), 2.0)
		return
	_bell_cd = 20.0
	Sfx.play("metal_impact", 3.0, 0.35)
	Sfx.play_at("metal_impact", Vector3(51.5, 7.0, -16.4), 6.0, 0.3)
	UI.toast("The bell tolls. The hum falters.", 3.0)
	if _bell_node != null:
		var tw := create_tween()
		tw.tween_property(_bell_node, "rotation:x", 0.5, 0.35).set_trans(Tween.TRANS_SINE)
		tw.tween_property(_bell_node, "rotation:x", -0.35, 0.5).set_trans(Tween.TRANS_SINE)
		tw.tween_property(_bell_node, "rotation:x", 0.0, 0.6).set_trans(Tween.TRANS_SINE)
	var flare_tw := create_tween()
	flare_tw.tween_property(self, "_nave_dim", 0.2, 0.2)
	flare_tw.tween_property(self, "_nave_dim", 1.0, 3.0)
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var gp: Vector3 = e.global_position
		if gp.x > 36.0 and gp.x < 56.0 and gp.z < -8.0 and gp.z > -44.0:
			if e.has_method("stun"):
				e.stun(6.0)
			elif e.has_method("fear"):
				e.fear(Vector3(51.5, 0, -16.4), 6.0)
	# the cost: the bell carries down Main Street and wakes what is frozen out there
	_wake_dormant(Vector3(51.5, 0, -16.4), 70.0)
	Sfx.alert_noise(Vector3(51.5, 0, -16.4), 45.0)

# =================================================================== PER-FRAME
func _process(delta: float) -> void:
	super._process(delta)
	if _beacon != null:
		_beacon.rotation.y += delta * 2.4
	for f in _fires:
		var l: OmniLight3D = f[1]
		if is_instance_valid(l):
			l.light_energy = f[2] * (0.82 + 0.18 * sin(_t * 13.0 + f[3]) + 0.12 * sin(_t * 31.0 + f[3] * 2.0))
	for s in _nave_spots:
		var l2: Light3D = s[0]
		if is_instance_valid(l2):
			var hum := 1.0 + 0.08 * sin(_t * 6.0) if _boss_active else 1.0
			l2.light_energy = s[1] * _nave_dim * hum
	if _bell_cd > 0.0:
		_bell_cd = max(0.0, _bell_cd - delta)
	# gunfire detection: loaded-ammo count dropping while the same weapon is equipped
	var eq: String = Game.equipped
	if eq != "" and eq != "knife":
		var n: int = Game.ammo_loaded(eq)
		if eq == _last_weapon and _last_ammo >= 0 and n < _last_ammo:
			_on_gunshot()
		_last_weapon = eq
		_last_ammo = n
	_tick += delta
	if _tick >= 0.45:
		_tick = 0.0
		_fire_repel()
		_exclusion()
		_update_inside()

func _fire_repel() -> void:
	if _fires.is_empty():
		return
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not e.has_method("fear"):
			continue
		if e == boss:
			continue
		for f in _fires:
			var fp: Vector3 = f[0]
			if e.global_position.distance_to(fp) < 4.8:
				e.fear(fp, 2.5)
				break

func _exclusion() -> void:
	# the Foreman never enters shops or the church: if he crosses a threshold, he's put back on the street
	if foreman == null or not is_instance_valid(foreman):
		return
	var gp: Vector3 = foreman.global_position
	for z in _rooms:
		var rc: Rect2 = z[0]
		if rc.has_point(Vector2(gp.x, gp.z)):
			foreman.global_position = z[2]
			if foreman.has_method("fear"):
				foreman.fear(Vector3(gp.x, 0, gp.z), 3.0)
			return
