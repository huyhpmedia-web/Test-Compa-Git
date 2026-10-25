extends "res://levels/level.gd"
## L5 - LOWER KETTLE MINE. Pipeline tunnel -> hoist house (lamp room safe room) -> side drifts
## (pump station: lamp_battery, collapsed 2011 drift: hoist_lever) -> THE FOREMAN at the hoist ->
## cage down -> powder magazine (dynamite) -> haulage cavern: THE HAULER -> refuge chamber: JUNE
## -> brine shaft -> l6_heart:start.
##
## Layout (x east, z south). Upper works at y=0; the lower level is at y=LY.
##   pipeline tunnel  x 0..26, z 0          pump station  x 0..20, z -32..-18 (via adit x=9)
##   hoist hall       x 26..48, z -10..10   collapsed drift/memorial x 7..29, z 16..30 (via adit x=17)
##   lamp room (safe) x 31..43, z -19..-10
##   LOWER: landing x 56..68 / haulage tunnel x 68..84 / magazine / cavern x 84..120 / refuge z -34..-26 / shaft x 132..142

const LY := -30.0
const Humanoid = preload("res://actors/humanoid.gd")
const CAGE_POS := Vector3(36.5, 0.0, 0.0)

var _rng := RandomNumberGenerator.new()
var _rime_mat: StandardMaterial3D
var _timber_mat: StandardMaterial3D
var _rock_names := ["rock", "rock", "rock", "dirt", "rock_wet", "sewer"]
var _ghosts: Array = []
var foreman: Node3D
var hauler: Node3D
var june: Node3D
var cage: Node3D
var cage_lo: Node3D
var _cage_busy := false
var _furnace_lit := false
var _furnace_pos := Vector3(29.0, 0.0, -8.0)
var _pillar: Node3D
var _hall_lamps: Array = []
var _plant_busy := false

func build() -> void:
	_rng.seed = 5150
	footstep = "concrete"
	env_interior(0.05, 0.022, Color(0.38, 0.48, 0.68))
	Sfx.ambience("amb_mine")
	add_spawn("start", Vector3(2.2, 0.05, 0.0), PI * 0.5)
	add_spawn("lower", Vector3(60.0, LY + 0.05, 0.0), PI * 0.5)
	add_spawn("cavern", Vector3(88.0, LY + 0.05, 0.0), PI * 0.5)
	add_spawn("refuge", Vector3(110.0, LY + 0.05, -20.0), 0.0)
	_build_pipeline_tunnel()
	_build_hoist_hall()
	_build_lamp_room()
	_build_pump_station()
	_build_drift()
	_build_lower_landing()
	_build_haulage()
	_build_cavern()
	_build_refuge()
	_build_shaft()
	_build_enemies()
	_build_hallucinations()
	if Game.has_flag("mine_power"):
		_hall_power_on(true)

func on_enter() -> void:
	for spent in ["badge_meridian", "coolant_key", "hot_stick", "school_key"]:
		Game.remove_item(spent, Game.count_item(spent))
	Sfx.music("music_tension")
	Sfx.ambience("amb_mine")
	if not Game.has_flag("mn_intro"):
		Game.set_flag("mn_intro")
		UI.title_card("LOWER KETTLE MINE", "Northline Mineral - Level 1, heat recovery tunnel")
		Game.set_objective("Follow the heat pipeline to the hoist house.")
	if Game.has_flag("found_june"):
		_spawn_june(player.global_position + Vector3(1.2, 0, 1.0), true)
		Game.set_objective("Take June down the brine shaft.")
	elif Game.has_flag("hauler_dead"):
		Game.set_objective("Find June. The refuge chamber is north of the cavern.")
	elif Game.has_flag("foreman_dead"):
		Game.set_objective("Ride the cage down to the haulage level.")

func _process(delta: float) -> void:
	super._process(delta)
	_update_ghosts()

# =================================================================== generic helpers
func _rmat(name: String) -> Material:
	return Mats.get_mat(name, 2.5)

func _timber() -> StandardMaterial3D:
	if _timber_mat == null:
		_timber_mat = Mats.color(Color(0.2, 0.135, 0.08), 0.92)
	return _timber_mat

func _rime() -> StandardMaterial3D:
	if _rime_mat == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.45, 0.85, 1.0, 0.55)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.emission_enabled = true
		m.emission = Color(0.15, 0.7, 1.0)
		m.emission_energy_multiplier = 1.4
		m.roughness = 0.08
		m.metallic_specular = 0.9
		_rime_mat = m
	return _rime_mat

func rk(a: float, b: float) -> float:
	return _rng.randf_range(a, b)

## One irregular rock lump.
func rock_chunk(pos: Vector3, size: Vector3, yaw: float, solid := true) -> void:
	var m: Material = _rmat(_rock_names[_rng.randi() % _rock_names.size()])
	Props.box(geo, size, pos, m, solid, Vector3(rk(-0.07, 0.07), yaw, rk(-0.07, 0.07)))

## Irregular rock wall from many rotated boxes. `inward` is the unit normal pointing into the open space.
## gaps: [[dist_from_a, width, height], ...]. The inner face of the backing wall lies on line a-b.
func rock_wall(a: Vector2, b: Vector2, h: float, y0: float, inward: Vector2, gaps: Array = []) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.1:
		return
	var dir := d / L
	var out := -inward
	wall(a + out * 0.35, b + out * 0.35, h, "rock", y0, 0.7, gaps)
	var yaw_base := atan2(dir.x, dir.y)
	var rowh := 3.0
	var rows := int(ceil(h / rowh))
	for r in rows:
		var base := y0 + r * rowh
		var rh: float = min(rowh, h - r * rowh)
		var skip_row := false
		for g in gaps:
			if r > 0 and base < y0 + g[2] - 0.2:
				skip_row = true
		var t := 0.0
		while t < L - 0.3:
			var t1: float = min(L, t + rk(1.1, 2.3))
			var skip := skip_row
			for g in gaps:
				var g0: float = g[0] - g[1] * 0.5 - 0.05
				var g1: float = g[0] + g[1] * 0.5 + 0.05
				if t1 > g0 and t < g1 and (r == 0 or base < y0 + g[2]):
					skip = true
			if not skip and t1 - t > 0.5:
				var th := rk(0.35, 0.8)
				var prot := rk(0.0, 0.3) if r == 0 else rk(0.1, 0.5)
				var mid := a + dir * (t + t1) * 0.5 + out * (th * 0.5 - prot)
				var ch: float = rh * rk(0.7, 1.0)
				rock_chunk(Vector3(mid.x, base + ch * 0.5, mid.y), Vector3(th, ch, t1 - t + 0.25), yaw_base + rk(-0.1, 0.1), r == 0)
			t = max(t1 - 0.15, t + 0.4)

## Rectangular cave: floor, rock ceiling, four rock walls. doors like room(): n,s,w,e -> [[dist, width, height]...]
func cave(x0: float, z0: float, x1: float, z1: float, h := 4.0, y := 0.0, doors := {}, floor_mat: Variant = "dirt", ceil_mat: Variant = "rock") -> void:
	floor_rect(x0, z0, x1, z1, y, floor_mat)
	ceiling_rect(x0, z0, x1, z1, y + h, ceil_mat)
	rock_wall(Vector2(x0, z0), Vector2(x1, z0), h, y, Vector2(0, 1), doors.get("n", []))
	rock_wall(Vector2(x0, z1), Vector2(x1, z1), h, y, Vector2(0, -1), doors.get("s", []))
	rock_wall(Vector2(x0, z0), Vector2(x0, z1), h, y, Vector2(1, 0), doors.get("w", []))
	rock_wall(Vector2(x1, z0), Vector2(x1, z1), h, y, Vector2(-1, 0), doors.get("e", []))
	# hanging rock lumps on the ceiling
	var n := int((x1 - x0) * (z1 - z0) / 18.0)
	for i in n:
		var p := Vector3(rk(x0 + 0.6, x1 - 0.6), y + h - rk(0.1, 0.3), rk(z0 + 0.6, z1 - 0.6))
		Props.box(geo, Vector3(rk(0.5, 1.4), rk(0.3, 0.7), rk(0.5, 1.4)), p, _rmat("rock_wet"), false, Vector3(rk(-0.2, 0.2), rk(0, 3), rk(-0.2, 0.2)))

## Straight tunnel from a to b (axis aligned). gl = gaps on the low side, gr = high side.
func tunnel(a: Vector2, b: Vector2, width := 3.6, h := 3.4, y := 0.0, gl: Array = [], gr: Array = [], floor_mat: Variant = "dirt") -> void:
	var alongx: bool = abs(b.x - a.x) > abs(b.y - a.y)
	if alongx:
		var x0: float = min(a.x, b.x)
		var x1: float = max(a.x, b.x)
		var z0 := a.y - width * 0.5
		var z1 := a.y + width * 0.5
		floor_rect(x0, z0, x1, z1, y, floor_mat)
		ceiling_rect(x0, z0, x1, z1, y + h, "rock")
		rock_wall(Vector2(x0, z0), Vector2(x1, z0), h, y, Vector2(0, 1), gl)
		rock_wall(Vector2(x0, z1), Vector2(x1, z1), h, y, Vector2(0, -1), gr)
	else:
		var z0: float = min(a.y, b.y)
		var z1: float = max(a.y, b.y)
		var x0 := a.x - width * 0.5
		var x1 := a.x + width * 0.5
		floor_rect(x0, z0, x1, z1, y, floor_mat)
		ceiling_rect(x0, z0, x1, z1, y + h, "rock")
		rock_wall(Vector2(x0, z0), Vector2(x0, z1), h, y, Vector2(1, 0), gl)
		rock_wall(Vector2(x1, z0), Vector2(x1, z1), h, y, Vector2(-1, 0), gr)

## Timber set (two posts + cap beam) spanning a tunnel. c = floor point on the tunnel axis.
func timber_set(c: Vector3, along_x: bool, width: float, height: float) -> void:
	var m := _timber()
	var half := width * 0.5 - 0.1
	for s in [-1.0, 1.0]:
		if along_x:
			Props.box(geo, Vector3(0.28, height, 0.28), Vector3(c.x, c.y + height * 0.5, c.z + s * half), m, false, Vector3(0, 0, s * 0.03))
		else:
			Props.box(geo, Vector3(0.28, height, 0.28), Vector3(c.x + s * half, c.y + height * 0.5, c.z), m, false, Vector3(s * 0.03, 0, 0))
	if along_x:
		Props.box(geo, Vector3(0.32, 0.3, width + 0.5), Vector3(c.x, c.y + height + 0.1, c.z), m, false, Vector3(rk(-0.02, 0.02), 0, rk(-0.02, 0.02)))
	else:
		Props.box(geo, Vector3(width + 0.5, 0.3, 0.32), Vector3(c.x, c.y + height + 0.1, c.z), m, false, Vector3(rk(-0.02, 0.02), 0, rk(-0.02, 0.02)))

## Rail track (along x or z). Sleepers + two rails.
func rails(a: Vector3, b: Vector3, gauge := 0.9) -> void:
	var d := b - a
	var L := d.length()
	var dir := d / L
	var yaw := atan2(dir.x, dir.z)
	var steel := Mats.get_mat("metal_rust", 1.0)
	var mid := (a + b) * 0.5
	for s in [-1.0, 1.0]:
		var off: Vector3 = Vector3(dir.z, 0, -dir.x) * s * gauge * 0.5
		Props.box(geo, Vector3(0.07, 0.09, L), mid + off + Vector3(0, 0.1, 0), steel, false, Vector3(0, yaw, 0))
	var n := int(L / 0.9)
	for i in n:
		var p := a + dir * (i + 0.5) * (L / n)
		Props.box(geo, Vector3(gauge + 0.5, 0.08, 0.16), p + Vector3(0, 0.04, 0), _timber(), false, Vector3(0, yaw, 0))

func ore_cart(pos: Vector3, yaw := 0.0, full := true) -> void:
	var r := Node3D.new()
	r.position = pos
	r.rotation.y = yaw
	geo.add_child(r)
	var m := Mats.get_mat("metal_rust", 1.0)
	Props.box(r, Vector3(1.5, 0.75, 0.95), Vector3(0, 0.62, 0), m, true)
	Props.box(r, Vector3(1.6, 0.08, 1.05), Vector3(0, 1.0, 0), Mats.get_mat("metal", 1.0), false)
	for sx in [-0.5, 0.5]:
		for sz in [-0.42, 0.42]:
			Props.cyl(r, 0.17, 0.08, Vector3(sx, 0.17, sz), Mats.color(Color(0.1, 0.1, 0.1), 0.5, 0.6), false, -1.0, Vector3(PI * 0.5, 0, 0), 10)
	if full:
		for i in 5:
			Props.sphere(r, rk(0.12, 0.22), Vector3(rk(-0.55, 0.55), 1.05 + rk(0, 0.1), rk(-0.3, 0.3)), _rmat("rock_wet"), Vector3(1, 0.7, 1))
	# a little rime on the ore
	if full and _rng.randf() < 0.6:
		rime(pos + Vector3(rk(-0.4, 0.4), 1.1, rk(-0.2, 0.2)), Vector3.UP, 3, 0.3)

## Cluster of glowing Rime crystals on a surface.
func rime(pos: Vector3, normal := Vector3.UP, n := 5, size := 0.5, lit := false) -> void:
	var nrm := normal.normalized()
	var q := Quaternion(Vector3.UP, nrm) if nrm.dot(Vector3.UP) > -0.99 else Quaternion(Vector3.RIGHT, PI)
	var bq := Basis(q)
	Props.sphere(geo, size * 0.3, pos, _rime(), Vector3(1, 0.2, 1)).basis = bq * Basis.from_scale(Vector3(1, 0.2, 1))
	for i in n:
		var hgt := size * rk(0.5, 1.5)
		var r := hgt * rk(0.07, 0.14)
		var off := bq * Vector3(rk(-1, 1), 0, rk(-1, 1)) * size * 0.5
		var jq := Quaternion(Vector3(rk(-1, 1), 0.001, rk(-1, 1)).normalized(), rk(0.0, 0.5))
		var mi := Props.cyl(geo, r, hgt, Vector3.ZERO, _rime(), false, 0.0, Vector3.ZERO, 6)
		mi.basis = Basis(q * jq)
		mi.position = pos + off + (q * jq) * Vector3(0, hgt * 0.5, 0)
	if lit:
		light(pos + nrm * 0.5, Color(0.25, 0.8, 1.0), 0.7 + size, 3.6, false)

## Scatter rime along a line (wall run / pipe). normal = surface normal.
func rime_run(a: Vector3, b: Vector3, normal: Vector3, count: int, size := 0.4, spread_y := 0.0, lit_every := 0) -> void:
	for i in count:
		var t := (i + rk(0.0, 1.0)) / float(count)
		var p := a.lerp(b, t) + Vector3(0, rk(0.0, spread_y), 0)
		var nn := (normal + Vector3(rk(-0.4, 0.4), rk(0.0, 0.5), rk(-0.4, 0.4))).normalized()
		rime(p, nn, _rng.randi_range(3, 6), size * rk(0.6, 1.3), lit_every > 0 and i % lit_every == 0)

func icicle(pos: Vector3, length := 0.5) -> void:
	Props.cyl(geo, 0.0005, length, pos - Vector3(0, length * 0.5, 0), Mats.get_mat("ice"), false, rk(0.03, 0.06), Vector3.ZERO, 6)

## Caged work light hanging from a cable. up = cable length above the lamp.
func work_light(p: Vector3, on := true, col := Color(1.0, 0.82, 0.55), energy := 1.8, flick := false, up := 0.9) -> void:
	Props.cyl(geo, 0.012, up, p + Vector3(0, up * 0.5 + 0.15, 0), Mats.get_mat("rubber"), false, -1.0, Vector3.ZERO, 5)
	var bulb: Material = Mats.emissive(col, 3.0) if on else Mats.color(Color(0.25, 0.25, 0.22), 0.4, 0.2)
	Props.sphere(geo, 0.07, p, bulb)
	var cm := Mats.get_mat("metal", 1.0)
	for s in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
		Props.cyl(geo, 0.008, 0.28, p + Vector3(s[0] * 0.1, 0.0, s[1] * 0.1), cm, false, -1.0, Vector3.ZERO, 4)
	Props.cyl(geo, 0.12, 0.012, p + Vector3(0, 0.14, 0), cm, false, -1.0, Vector3.ZERO, 8)
	Props.cyl(geo, 0.12, 0.012, p + Vector3(0, -0.14, 0), cm, false, -1.0, Vector3.ZERO, 8)
	if on:
		light(p + Vector3(0, -0.1, 0), col, energy, 7.5, false, flick)

## Sagging cable between two points.
func cable_run(a: Vector3, b: Vector3, sag := 0.25, segs := 4) -> void:
	var prev := a
	for i in range(1, segs + 1):
		var t := float(i) / segs
		var p := a.lerp(b, t) - Vector3(0, sag * sin(t * PI), 0)
		Props.pipe(geo, prev, p, 0.018, "rubber")
		prev = p

func vent_duct(a: Vector3, b: Vector3, size := 0.7) -> void:
	var d := b - a
	var L := d.length()
	var n := int(L / 2.0)
	var m := Mats.get_mat("metal", 1.5)
	var dir := d / L
	var yaw := atan2(dir.x, dir.z)
	for i in n:
		var p := a + d * ((i + 0.5) / n)
		Props.box(geo, Vector3(size, size, L / n - 0.06), p, m, false, Vector3(0, yaw, 0))
		Props.box(geo, Vector3(size + 0.1, size + 0.1, 0.1), a + d * (float(i) / n), Mats.get_mat("metal_rust", 1.0), false, Vector3(0, yaw, 0))

func body_in_rock(pos: Vector3, yaw: float, cover_dir: Vector3) -> void:
	## a frozen miner half-swallowed by the wall: the body lies at the foot of it, rock + rime over the half.
	Props.corpse(geo, pos, yaw, {"skin": Color(0.55, 0.68, 0.72), "shirt": Color(0.34, 0.27, 0.16), "pants": Color(0.16, 0.15, 0.14), "bloody": 0.0})
	var c := pos + cover_dir * 0.5 + Vector3(0, 0.35, 0)
	Props.box(geo, Vector3(1.0, 0.6, 0.9), c, _rmat("rock_wet"), false, Vector3(rk(-0.2, 0.2), rk(0, 3), rk(-0.2, 0.2)))
	rime(pos + Vector3(0, 0.25, 0), Vector3.UP, 7, 0.55, true)
	rime(c + Vector3(0, 0.3, 0), Vector3.UP + cover_dir * -0.3, 5, 0.4)

func hard_hat(pos: Vector3, col := Color(0.9, 0.7, 0.1), yaw := 0.0) -> void:
	var hm := Mats.color(col, 0.5)
	var s := Props.sphere(geo, 0.14, pos + Vector3(0, 0.07, 0), hm, Vector3(1, 0.65, 1.1))
	s.rotation.y = yaw
	Props.box(geo, Vector3(0.3, 0.02, 0.12), pos + Vector3(0, 0.02, 0.13), hm, false)

func set_area(name: String, pos: Vector3, size: Vector3, group := "safe_zone") -> Area3D:
	var a := Area3D.new()
	a.name = name
	a.collision_layer = 0
	a.collision_mask = 2
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	a.add_child(cs)
	a.position = pos
	a.add_to_group(group)
	add_child(a)
	return a

func _blink() -> void:
	UI.fade_out(0.1)
	await get_tree().create_timer(0.22).timeout
	UI.fade_in(0.45)

func _hum_beat() -> void:
	Sfx.play("hum", -2.0)
	if player:
		player.shake = max(player.shake, 0.35)

# =================================================================== A. PIPELINE TUNNEL
func _build_pipeline_tunnel() -> void:
	tunnel(Vector2(0, 0), Vector2(26, 0), 3.6, 3.4, 0.0,
		[[9.0, 2.8, 2.8]], [[17.0, 2.8, 2.8]])
	# west end: heavy concrete bulkhead with the sealed pipeline hatch
	box(Vector3(-0.35, 1.7, 0), Vector3(0.7, 3.4, 3.6), "concrete")
	Props.sign(geo, Vector3(0.1, 2.45, 0), PI * 0.5, "PIPELINE SERVICE TUNNEL\nMERIDIAN SITE - NO ACCESS", 36, Color(0.9, 0.75, 0.2))
	box(Vector3(0.08, 1.1, 0), Vector3(0.1, 2.2, 1.5), "metal_painted", false)
	# the heat pipeline: warm, with orange glow at the flanges, rime creeping along it
	Props.pipe(geo, Vector3(0.1, 2.55, -1.15), Vector3(26.0, 2.55, -1.15), 0.42, "metal_painted")
	for x in range(2, 26, 4):
		Props.cyl(geo, 0.5, 0.18, Vector3(x, 2.55, -1.15), Mats.emissive(Color(1.0, 0.45, 0.1), 0.9), false, -1.0, Vector3(0, 0, PI * 0.5), 14).rotation = Vector3(0, 0, PI * 0.5)
		Props.box(geo, Vector3(0.12, 0.7, 0.12), Vector3(x + 1.0, 3.0, -1.15), Mats.get_mat("metal", 1.0), false)
	light(Vector3(8, 2.4, -0.8), Color(1.0, 0.5, 0.2), 0.8, 5.0, false)
	light(Vector3(21, 2.4, -0.8), Color(1.0, 0.5, 0.2), 0.8, 5.0, false)
	for x in range(5, 25, 4):
		rime(Vector3(x, 2.97, -1.15), Vector3.UP, 5, 0.35, x % 8 == 5)
	rime_run(Vector3(2, 2.2, -1.5), Vector3(25, 2.2, -1.5), Vector3(0, -0.5, 1), 12, 0.35)
	# wall rime + floor
	rime_run(Vector3(1, 0.1, 1.5), Vector3(25, 0.1, 1.5), Vector3(0, 0.6, -1), 10, 0.45, 1.8, 3)
	rime_run(Vector3(1, 0.05, 0.4), Vector3(24, 0.05, 0.4), Vector3.UP, 5, 0.25)
	# vent duct + cables + work lights
	vent_duct(Vector3(0.5, 3.05, 1.2), Vector3(25.5, 3.05, 1.2), 0.6)
	cable_run(Vector3(0.5, 3.2, 1.45), Vector3(25.5, 3.2, 1.45), 0.35, 12)
	work_light(Vector3(5.5, 2.5, 0.9), true, Color(0.85, 0.9, 1.0), 1.6, true)
	work_light(Vector3(13.0, 2.5, 0.9), false)
	work_light(Vector3(21.5, 2.5, 0.9), true, Color(1.0, 0.8, 0.5), 1.5, true)
	# timber sets
	for x in [3.0, 6.5, 12.0, 14.5, 20.0, 23.0]:
		timber_set(Vector3(x, 0, 0), true, 3.6, 2.9)
	rails(Vector3(1, 0, 0.55), Vector3(25.9, 0, 0.55), 0.85)
	ore_cart(Vector3(11.2, 0, 0.55), PI * 0.5)
	ore_cart(Vector3(19.0, 0, 0.55), PI * 0.5, false)
	# frozen bodies in the walls
	body_in_rock(Vector3(7.8, 0, 1.0), 1.4, Vector3(0, 0, 1))
	body_in_rock(Vector3(15.5, 0, -1.0), -0.4, Vector3(0, 0, -1))
	# icicles on the pipe supports
	for x in [6.0, 10.0, 15.0, 19.0, 23.0]:
		icicle(Vector3(x, 3.3, rk(-0.8, 0.8)), rk(0.3, 0.8))
	# timber frames at adit mouths
	timber_set(Vector3(9.0, 0, -1.8), false, 2.8, 2.6)
	timber_set(Vector3(17.0, 0, 1.8), false, 2.8, 2.6)
	Props.sign(geo, Vector3(9.0, 2.35, -1.55), 0.0, "BRINE PUMPS", 32, Color(0.5, 0.8, 0.95))
	Props.sign(geo, Vector3(17.0, 2.35, 1.55), PI, "4 NORTH DRIFT\nCLOSED 2011", 28, Color(0.9, 0.3, 0.2))
	# entrance to hoist house: timber gate
	timber_set(Vector3(25.5, 0, 0), false, 3.4, 3.0)
	# pickups
	pickup("mn_flare1", "flare", 1, Vector3(3.4, 0.02, 1.3))
	pickup("mn_9mm1", "ammo_9mm", 6, Vector3(7.4, 0.02, -1.2))
	pickup("mn_gel1", "gel", 1, Vector3(15.0, 0.02, 1.2))
	note("mn_note_notice", Vector3(4.2, 0.02, -1.25), "Notice: Heat Recovery Loop",
		"[b]NORTHLINE MINERAL - LOWER KETTLE[/b]\n[b]HEAT RECOVERY LOOP (CORVANE / MERIDIAN)[/b]\n\nTunnel temperature is held at 6 C by the loop. Do NOT touch the pipeline casing. Do NOT remove growth or 'scale' from casing - report to shift supervisor.\n\nPipeline casing surface temperature: 41 C.\n\nGood heat is a shared resource. Be a good neighbour.\n\n[i]- Site Services[/i]", PI * 0.5)

# =================================================================== B. HOIST HALL
func _build_hoist_hall() -> void:
	var hh := 9.0
	# floor around the shaft
	floor_rect(26, -10, 48, -1.9, 0.0, "concrete")
	floor_rect(26, 1.9, 48, 10, 0.0, "concrete")
	floor_rect(26, -1.9, 34.6, 1.9, 0.0, "concrete")
	floor_rect(38.4, -1.9, 48, 1.9, 0.0, "concrete")
	ceiling_rect(26, -10, 48, 10, hh, "metal_painted")
	# walls: west with the tunnel mouth, north with the lamp-room door, south and east plain
	wall(Vector2(26, -10), Vector2(26, 10), hh, "corrugated", 0.0, 0.3, [[10.0, 3.4, 3.2]])
	wall(Vector2(26, -10), Vector2(48, -10), hh, "corrugated", 0.0, 0.3, [[11.0, 1.8, 2.4]])
	wall(Vector2(26, 10), Vector2(48, 10), hh, "corrugated", 0.0, 0.3)
	wall(Vector2(48, -10), Vector2(48, 10), hh, "corrugated", 0.0, 0.3)
	# concrete plinth skirting
	box(Vector3(37, 0.5, 9.75), Vector3(22, 1.0, 0.4), "concrete", false)
	box(Vector3(47.75, 0.5, 0), Vector3(0.4, 1.0, 20), "concrete", false)
	# steel trusses and the sheave frame in the headframe above
	for x in range(28, 48, 4):
		Props.box(geo, Vector3(0.35, 0.5, 20.0), Vector3(x, hh - 0.3, 0), Mats.get_mat("metal_painted", 1.5), false)
		Props.box(geo, Vector3(0.25, 0.25, 21), Vector3(x + 1, hh - 1.5, 0), Mats.get_mat("metal_rust", 1.5), false, Vector3(0.0, 0.0, 0.0))
	for z in [-8, -4, 0, 4, 8]:
		Props.box(geo, Vector3(22, 0.4, 0.4), Vector3(37, hh - 0.6, z), Mats.get_mat("metal_painted", 1.5), false)
	# moonlight through the broken roof above the shaft
	var sp := spot(Vector3(36.5, hh - 0.2, 0.0), Vector3(36.5, 0, 0.0), Color(0.55, 0.7, 1.0), 9.0, 14.0, 26.0, true)
	sp.light_volumetric_fog_energy = 2.5
	Props.box(geo, Vector3(3.6, 0.2, 3.6), Vector3(36.5, hh + 0.1, 0), Mats.emissive(Color(0.4, 0.55, 0.85), 0.6), false)
	# snow drift indoors under the roof hole
	Props.sphere(geo, 1.6, Vector3(34.0, 0.0, -2.8), Mats.get_mat("snow"), Vector3(1.4, 0.35, 1.0))
	Props.sphere(geo, 1.2, Vector3(39.2, 0.0, 2.9), Mats.get_mat("snow"), Vector3(1.4, 0.3, 1.0))
	# shaft pit
	var pit_m := Mats.get_mat("concrete", 1.5)
	for s in [-1.0, 1.0]:
		box(Vector3(36.5 + s * 1.95, -3.0, 0), Vector3(0.2, 6.0, 4.0), pit_m)
		box(Vector3(36.5, -3.0, s * 1.95), Vector3(3.8, 6.0, 0.2), pit_m)
	floor_rect(34.6, -1.9, 38.4, 1.9, -6.0, "rock_wet")
	rime(Vector3(36.5, -6.0, 0), Vector3.UP, 12, 0.9, true)
	# the cage (platform + frame) - moves when the brake is released
	cage = Node3D.new()
	cage.position = CAGE_POS
	add_child(cage)
	Props.box(cage, Vector3(3.8, 0.3, 3.8), Vector3(0, -0.15, 0), Mats.get_mat("metal_rust", 1.5), true)
	for sx in [-1.8, 1.8]:
		for sz in [-1.8, 1.8]:
			Props.box(cage, Vector3(0.12, 2.6, 0.12), Vector3(sx, 1.3, sz), Mats.get_mat("metal_painted", 1.0), false)
	Props.box(cage, Vector3(3.9, 0.12, 3.9), Vector3(0, 2.6, 0), Mats.get_mat("metal_painted", 1.0), false)
	Props.box(cage, Vector3(0.06, 1.2, 3.6), Vector3(-1.8, 1.0, 0), Mats.get_mat("metal", 3.0), false).material_override = Mats.color(Color(0.4, 0.42, 0.45, 0.25), 0.4, 0.8)
	Props.sign(cage, Vector3(0, 2.3, 1.95), 0.0, "CAGE NO. 1   MAX 6 MEN", 28, Color(0.9, 0.85, 0.7))
	for sx in [-0.6, 0.6]:
		Props.pipe(geo, Vector3(36.5 + sx, 2.6, 0), Vector3(36.5 + sx, hh - 0.8, 0), 0.035, "metal_rust")
	# sheave wheel
	Props.cyl(geo, 1.3, 0.25, Vector3(36.5, hh - 1.3, 0), Mats.get_mat("metal_rust", 1.5), false, -1.0, Vector3(0, 0, PI * 0.5), 20)
	# hoist drum, flanges, motor housing
	Props.cyl(geo, 1.5, 3.2, Vector3(44.0, 2.0, -4.0), Mats.get_mat("metal_rust", 1.5), true, -1.0, Vector3(PI * 0.5, 0, 0), 24)
	for s in [-1.0, 1.0]:
		Props.cyl(geo, 2.0, 0.15, Vector3(44.0, 2.0, -4.0 + s * 1.7), Mats.get_mat("metal_painted", 1.5), false, -1.0, Vector3(PI * 0.5, 0, 0), 24)
	box(Vector3(44.0, 0.6, -4.0), Vector3(2.6, 1.2, 4.4), "concrete")
	box(Vector3(45.6, 1.2, -8.2), Vector3(3.6, 2.4, 3.0), "metal_painted")
	Props.sign(geo, Vector3(45.6, 2.0, -6.66), 0.0, "ASEA HOIST  1953", 30, Color(0.8, 0.8, 0.75))
	Props.pipe(geo, Vector3(44.0, 3.6, -4.0), Vector3(36.5 + 0.6, hh - 1.0, 0.0), 0.035, "metal_rust")
	# brake lever station (needs hoist_lever + mine_power)
	var st := Node3D.new()
	st.position = Vector3(41.2, 0, -2.6)
	geo.add_child(st)
	Props.box(st, Vector3(0.9, 1.1, 0.6), Vector3(0, 0.55, 0), Mats.get_mat("metal_painted", 1.0), true)
	Props.box(st, Vector3(0.8, 0.12, 0.7), Vector3(0, 1.15, 0.05), Mats.get_mat("metal", 1.0), false, Vector3(-0.3, 0, 0))
	Props.box(st, Vector3(0.12, 0.3, 0.12), Vector3(0, 1.3, 0.12), Mats.color(Color(0.1, 0.1, 0.1), 0.6), false)
	Props.sphere(st, 0.05, Vector3(-0.28, 1.28, 0.0), Mats.emissive(Color(1.0, 0.1, 0.05), 2.0))
	Props.sign(st, Vector3(0, 1.62, -0.05), PI, "BRAKE", 26, Color(0.9, 0.3, 0.2))
	Props.cyl(geo, 0.04, 0.9, Vector3(41.2, 1.55, -2.55), Mats.get_mat("metal", 1.0), false)  # socket stub
	interact(Vector3(41.2, 1.1, -2.1), "Hoist brake station", _brake_station, 1.8)
	# furnace (lure + burn)
	_build_furnace()
	# lit/unlit state: hall is dark until power. Only an emergency red lamp over the door + moonlight.
	work_light(Vector3(27.2, 3.2, 2.2), true, Color(1.0, 0.15, 0.1), 1.3, true, 0.5)
	light(Vector3(30.0, 1.5, 0.0), Color(0.4, 0.55, 0.8), 0.5, 8.0, false)
	# dressing
	Props.crate(geo, Vector3(46.5, 0, 7.5), 0.3, 1.0)
	Props.crate(geo, Vector3(46.4, 0, 8.7), -0.2, 0.9)
	Props.crate(geo, Vector3(46.5, 1.0, 7.6), 0.5, 0.7)
	Props.barrel(geo, Vector3(28.0, 0, 7.5))
	Props.barrel(geo, Vector3(28.7, 0, 8.4))
	Props.barrel(geo, Vector3(42.0, 0, 8.5), 0.0, false)
	Props.debris(geo, Vector3(32.0, 0, -6.0), 0.3, 6, "concrete")
	Props.papers(geo, Vector3(40.5, 0.02, -1.4), 7)
	Props.chair(geo, Vector3(40.0, 0, -3.8), 0.4, true)
	Props.table(geo, Vector3(41.8, 0, 6.8), 0.0, Vector2(2.2, 0.9))
	rime(Vector3(41.8, 0.8, 6.8), Vector3.UP, 3, 0.25)
	rime_run(Vector3(27.0, 0.1, 9.5), Vector3(47.0, 0.1, 9.5), Vector3(0, 0.5, -1), 10, 0.5, 1.5, 4)
	rime_run(Vector3(26.5, 0.1, -9.5), Vector3(30.0, 0.1, -9.5), Vector3(0, 0.5, 1), 3, 0.5, 1.5)
	rime(Vector3(36.5, -0.02, -2.2), Vector3.UP, 8, 0.45)
	for i in 6:
		icicle(Vector3(rk(29, 46), hh - 0.7, rk(-9, 9)), rk(0.6, 1.4))
	# safety signs
	Props.sign(geo, Vector3(26.3, 2.6, 5.0), PI * 0.5, "ALL MEN CHECK IN\nAT THE LAMP ROOM", 30, Color(0.95, 0.85, 0.3))
	Props.sign(geo, Vector3(37, 2.6, -9.85), 0.0, "LAMP ROOM", 36, Color(0.95, 0.85, 0.3))
	# the lamp-room door in the north wall
	door("mn_lampdoor", Vector3(37, 0, -10), 0.0, {"width": 1.7, "height": 2.35, "mat": "wood", "prompt": "Open lamp room door"})
	# ride the cage
	interact(Vector3(36.5, 1.0, 0.0), "Ride the cage down", _ride_down, 2.4)
	# pickups
	pickup("mn_hall_flare", "flare", 1, Vector3(46.1, 0.02, 6.4))
	pickup("mn_hall_9mm", "ammo_9mm", 5, Vector3(42.4, 0.02, 7.6))
	pickup("mn_hall_inc", "ammo_grenade", 1, Vector3(46.4, 1.72, 7.5))
	pickup("mn_hall_gel", "gel", 1, Vector3(41.8, 0.82, 6.9))
	# lamp: foreman trigger arming when he's called
	if Game.has_flag("hoist_ready") and not Game.has_flag("foreman_dead"):
		_spawn_foreman(Vector3(24.0, 0.05, 0.0))
	trigger("mn_enter_hall", Vector3(28.5, 1.2, 0), Vector3(2.0, 2.4, 3.4), func(_p):
		Sfx.music("music_tension")
		if not Game.has_flag("got:mn_tag"):
			Game.set_objective("Find a way down. Check the lamp room.")
		await get_tree().create_timer(0.6).timeout
		await say([["ELIAS", "A headframe from the fifties. They kept this place alive for the brine. The heat, the pipes. All of it."]]))

func _build_furnace() -> void:
	var f := Node3D.new()
	f.position = Vector3(29.0, 0, -8.6)
	add_child(f)
	Props.box(f, Vector3(2.2, 1.9, 1.4), Vector3(0, 0.95, 0), Mats.get_mat("brick_dark", 1.5), true)
	Props.box(f, Vector3(0.9, 0.8, 0.12), Vector3(0, 0.7, 0.72), Mats.color(Color(0.04, 0.04, 0.04), 0.6, 0.4), false)
	Props.box(f, Vector3(0.7, 0.55, 0.05), Vector3(0, 0.7, 0.79), Mats.color(Color(0.2, 0.05, 0.02), 0.5), false)
	Props.cyl(f, 0.25, 3.0, Vector3(0, 3.4, -0.2), Mats.get_mat("metal_rust", 1.0), false)
	Props.sign(f, Vector3(0, 1.75, 0.72), 0.0, "COAL FURNACE", 24, Color(0.85, 0.7, 0.5))
	Props.crate(geo, Vector3(31.2, 0, -9.0), 0.2, 0.9)
	Props.barrel(geo, Vector3(30.8, 0, -7.2), 0.0, true)
	interact(Vector3(29.0, 1.0, -7.6), "Light the furnace", _light_furnace, 1.8)

func _light_furnace(_p) -> void:
	if _furnace_lit:
		UI.toast("The furnace is already roaring.")
		return
	_furnace_lit = true
	Sfx.play("flare_ignite")
	UI.toast("Coal and lamp oil catch. The furnace roars.")
	var fl := light(Vector3(29.0, 0.9, -7.2), Color(1.0, 0.5, 0.15), 4.0, 11.0, true, true)
	fl.light_volumetric_fog_energy = 2.0
	var fx := FX.flare(self, Vector3(29.0, 0.4, -7.5), 200.0, 5.0)
	var t := Timer.new()
	t.wait_time = 0.5
	t.autostart = true
	add_child(t)
	t.timeout.connect(func():
		for e in get_tree().get_nodes_in_group("enemy"):
			if is_instance_valid(e) and e.global_position.distance_to(_furnace_pos) < 4.8 and e.has_method("burn"):
				e.burn(5.0, _furnace_pos))

func _brake_station(_p) -> void:
	if Game.has_flag("hoist_ready"):
		_release_brake()
		return
	if not Game.has_item("hoist_lever"):
		UI.toast("The socket for the brake lever is empty.")
		Sfx.play("deny")
		return
	if not Game.has_flag("mine_power"):
		UI.toast("The hoist controls are dead. The signal system has no power.")
		Sfx.play("deny")
		return
	Game.remove_item("hoist_lever", 1)
	Game.set_flag("hoist_ready")
	Sfx.play("unlock")
	Props.cyl(geo, 0.03, 0.9, Vector3(41.2, 1.55, -2.55), Mats.get_mat("metal", 1.0), false)
	lock_player(true)
	await say([["ELIAS", "Lever's seated. Signal bells are live. Somewhere above me the whole hoist just woke up."],
		["ELIAS", "And everything in this mine just heard it."]])
	lock_player(false)
	_foreman_encounter()

func _foreman_encounter() -> void:
	Sfx.music("music_chase")
	Game.set_objective("Survive the Foreman. Lure him onto the cage and release the brake - or burn him.")
	_blink()
	_spawn_foreman(Vector3(24.0, 0.05, 0.0))
	await get_tree().create_timer(1.2).timeout
	lock_player(true)
	await say([["ELIAS", "That hard hat. The headlamp is still burning. Gil. Gil Arsenault."],
		["ELIAS", "You wrote the request to seal 4 North. Dad used to say you were the only one who read the reports."],
		["ELIAS", "If I can get him on the cage and pull the brake, the old safety dogs won't hold. The furnace works too."]])
	lock_player(false)
	if not is_instance_valid(foreman):
		# fallback: the stalker type is missing; finish the beat cleanly
		await get_tree().create_timer(1.0).timeout
		_on_foreman_died(null)

func _spawn_foreman(pos: Vector3) -> void:
	if Game.has_flag("foreman_dead"):
		return
	foreman = enemy("mn_foreman", "foreman", pos, PI * 0.5, {"stalk": true, "mortal": true})
	if foreman != null and foreman.has_signal("died"):
		foreman.connect("died", _on_foreman_died)

func _on_foreman_died(_e) -> void:
	if Game.has_flag("foreman_dead"):
		return
	Game.set_flag("foreman_dead")
	Sfx.music("music_tension")
	Game.set_objective("Ride the cage down to the haulage level.")
	await get_tree().create_timer(1.0).timeout
	await say([["ELIAS", "...Rest, Gil."], ["ELIAS", "The cage is clear. Down we go."]])

func _release_brake() -> void:
	if _cage_busy:
		return
	if Game.has_flag("foreman_dead") or not is_instance_valid(foreman):
		UI.toast("The brake holds the cage. There is nothing to drop it on.")
		return
	var d := Vector2(foreman.global_position.x - CAGE_POS.x, foreman.global_position.z - CAGE_POS.z)
	if abs(d.x) > 2.4 or abs(d.y) > 2.4:
		UI.toast("Wait until he is standing on the cage.")
		Sfx.play("deny")
		return
	_cage_busy = true
	Sfx.play("door_locked")
	var tw := create_tween()
	tw.tween_property(cage, "position:y", -6.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(0.45).timeout
	if is_instance_valid(foreman):
		foreman.call("take_hit", 99999.0, foreman.global_position + Vector3(0, 1, 0), Vector3.DOWN, false)
		if foreman.get("state") != "dead" and foreman.has_method("_die"):
			foreman.call("_die", false)
	FX.explosion(self, Vector3(36.5, -5.0, 0.0), 2.0, 0.0)
	await get_tree().create_timer(3.0).timeout
	var tw2 := create_tween()
	tw2.tween_property(cage, "position:y", 0.0, 5.0).set_trans(Tween.TRANS_SINE)
	await tw2.finished
	_cage_busy = false

func _ride_down(_p) -> void:
	if _cage_busy:
		return
	if not Game.has_flag("foreman_dead"):
		UI.toast("The cage is locked out. Nobody rides until the hoist is secure.")
		Sfx.play("deny")
		return
	_ride(true)

func _ride_up(_p) -> void:
	_ride(false)

func _ride(down: bool) -> void:
	lock_player(true)
	UI.fade_out(0.8)
	Sfx.play("door_open")
	await get_tree().create_timer(1.0).timeout
	Sfx.play("door_locked")
	await get_tree().create_timer(1.6).timeout
	if down:
		player.place(Vector3(62.0, LY + 0.05, 0.0), PI * 0.5)
	else:
		player.place(Vector3(36.5, 0.05, 1.0), PI * 0.5)
	UI.fade_in(1.0)
	lock_player(false)
	if down and not Game.has_flag("mn_lower"):
		Game.set_flag("mn_lower")
		Sfx.music("music_tension")
		Game.set_objective("Find the powder magazine. You will need blasting charges.")
		await get_tree().create_timer(1.2).timeout
		await say([["JUNE (radio)", "...Dad? ...so cold. I can hear a... bell. Is that... you?"],
			["ELIAS", "June? June, stay on. I'm coming down."],
			["JUNE (radio)", "...steel. It's all steel. ...so quiet..."]])

# =================================================================== C. LAMP ROOM (SAFE ROOM)
func _build_lamp_room() -> void:
	var y := 0.0
	floor_rect(31, -19, 43, -10, y, "wood_floor")
	ceiling_rect(31, -19, 43, -10, 3.4, "plaster_dirty")
	wall(Vector2(31, -19), Vector2(43, -19), 3.4, "plaster_dirty", 0.0, 0.25)
	wall(Vector2(31, -19), Vector2(31, -10), 3.4, "plaster_dirty", 0.0, 0.25)
	wall(Vector2(43, -19), Vector2(43, -10), 3.4, "plaster_dirty", 0.0, 0.25)
	# lamp racks along the north wall: benches with rows of cap lamps
	for bx in [34.0, 38.0, 41.2]:
		Props.box(geo, Vector3(3.2, 0.9, 0.6), Vector3(bx, 0.45, -18.55), Mats.get_mat("wood_panel", 1.0), true)
		for row in 2:
			Props.box(geo, Vector3(3.2, 0.05, 0.4), Vector3(bx, 1.5 + row * 0.55, -18.7), Mats.get_mat("wood_panel", 1.0), false)
			for i in 14:
				var lx: float = bx - 1.5 + i * 0.23
				var live := _rng.randf() < 0.07
				var mat: Material = Mats.emissive(Color(1.0, 0.7, 0.3), 1.2) if live else Mats.color(Color(0.18, 0.17, 0.12), 0.6, 0.3)
				Props.cyl(geo, 0.045, 0.1, Vector3(lx, 1.58 + row * 0.55, -18.7), mat, false, -1.0, Vector3.ZERO, 8)
	# tag board on the west wall
	var board := Mats.get_mat("wood_panel", 1.0)
	Props.box(geo, Vector3(0.08, 1.6, 3.4), Vector3(31.17, 1.7, -14.5), board, false)
	for row in 5:
		for col in 14:
			var hz := -14.5 - 1.55 + col * 0.24
			var hy := 2.25 - row * 0.28
			Props.sphere(geo, 0.012, Vector3(31.24, hy, hz), Mats.color(Color(0.6, 0.5, 0.2), 0.4, 0.8))
	Props.sign(geo, Vector3(31.3, 2.7, -14.5), PI * 0.5, "CHECK-IN BOARD  -  EVERY MAN IN, EVERY MAN OUT", 30, Color(0.9, 0.85, 0.65))
	# two tags still hanging
	_tag(Vector3(31.27, 1.68, -14.5 + 0.0), "114", false)
	_tag(Vector3(31.27, 1.96, -14.5 - 0.72), "109", true)
	Props.sign(geo, Vector3(31.3, 1.55, -14.5), PI * 0.5, "114  T. KADE", 20, Color(0.95, 0.8, 0.4), false)
	interact(Vector3(32.0, 1.4, -14.5), "Brass tag 114", _take_tag, 1.7)
	# Tom's letter on a little table below
	Props.table(geo, Vector3(32.0, 0, -12.2), PI * 0.5, Vector2(1.2, 0.7))
	note("mn_tom_letter", Vector3(32.0, 0.8, -12.2), "Letter: T. Kade to Ruth, March 2011",
		"[b]Ruth,[/b]\n\nI started this three times at the kitchen table and you kept coming in to top up my coffee, so I'm finishing it here in the lamp room where nobody watches me think.\n\nThe top level has been making noises I don't like. I told Gil. Gil told the office. The office told Gil to stop telling them. You know how it goes. I'll be fine. Twenty-two years down here and the mountain and I have an understanding.\n\nHere's what I never manage at supper. I'm proud of you. I'm proud of how you sit with people when it's bad. And I'm proud of Eli, even when he looks at me like I'm the thing he's trying to get away from. He's got my hands and your head. He'll leave this town. Let him. Just don't let him leave angry.\n\nI hang my brass tag on the board like always. People think the tag is so they know who's down. It isn't. It's the only thing in this mine that comes back every single night.\n\nI'm going to quit in June. I mean it this time. We'll drive up to that lake in Michigan you keep talking about.\n\nLeave the porch light on.\n\n[i]- Tom[/i]", PI * 0.5)
	# warm light, heater, cot
	ceiling_lamp(Vector3(37, 3.4, -14.5), "bulb", true, false)
	light(Vector3(33.3, 0.7, -11.2), Color(1.0, 0.5, 0.2), 1.6, 5.5, false)
	Props.box(geo, Vector3(0.7, 0.9, 0.3), Vector3(33.3, 0.45, -10.5), Mats.get_mat("metal_painted", 1.0), true)
	Props.box(geo, Vector3(0.5, 0.4, 0.02), Vector3(33.3, 0.55, -10.34), Mats.emissive(Color(1.0, 0.4, 0.1), 2.5), false)
	Props.bed(geo, Vector3(35.0, 0, -11.6), PI * 0.5)
	Props.desk(geo, Vector3(41.4, 0, -17.2), PI)
	save_point(Vector3(41.0, 0.82, -17.2), PI)
	item_box(Vector3(42.55, 0, -12.8), -PI * 0.5)
	Props.locker(geo, Vector3(42.6, 0, -15.6), -PI * 0.5, 3)
	Props.chair(geo, Vector3(41.2, 0, -16.0), 2.8)
	Props.papers(geo, Vector3(38.0, 0.02, -13.0), 5)
	Props.crate(geo, Vector3(32.0, 0, -17.8), 0.3, 0.7)
	# cap-lamp charging cabinet + signal panel (lamp_battery goes here)
	var cc := Node3D.new()
	cc.position = Vector3(36.0, 0, -18.5)
	add_child(cc)
	Props.box(cc, Vector3(1.0, 2.0, 0.4), Vector3(0, 1.0, 0), Mats.get_mat("metal_painted", 1.0), false)
	Props.box(cc, Vector3(0.7, 0.35, 0.02), Vector3(0, 1.4, 0.21), Mats.color(Color(0.05, 0.05, 0.05), 0.3), false)
	Props.sphere(cc, 0.03, Vector3(-0.25, 1.75, 0.21), Mats.emissive(Color(1.0, 0.1, 0.1), 2.0))
	Props.sign(cc, Vector3(0, 1.9, 0.22), 0.0, "CHARGER / SIGNAL", 22, Color(0.9, 0.9, 0.8), false)
	interact(Vector3(36.0, 1.1, -17.7), "Cap-lamp charger and signal panel", _charger, 1.8)
	# safe zone + music
	set_area("mn_safe", Vector3(37, 1.6, -14.5), Vector3(12, 3.2, 9))
	trigger("mn_safe_music", Vector3(37, 1.2, -13.5), Vector3(11, 2.4, 8), func(_p): Sfx.music("music_safe"), false)
	trigger("mn_safe_out", Vector3(37, 1.2, -9.4), Vector3(2.2, 2.4, 1.0), _leave_safe, false)
	# supplies are in the crate; a few visible
	pickup("mn_lamp_shells", "ammo_shell", 5, Vector3(39.0, 0.02, -17.3))
	# frost around the door only (the room is warm)
	rime(Vector3(37.0, 0.02, -10.6), Vector3.UP, 4, 0.3)

func _leave_safe(_p) -> void:
	if not Game.has_flag("hoist_ready") or Game.has_flag("foreman_dead"):
		Sfx.music("music_tension")

func _tag(pos: Vector3, num: String, dim: bool) -> void:
	Props.box(geo, Vector3(0.02, 0.1, 0.07), pos, Mats.color(Color(0.8, 0.62, 0.25) if not dim else Color(0.5, 0.42, 0.22), 0.35, 0.8), false)

func _take_tag(_p) -> void:
	if Game.has_flag("got:mn_tag"):
		UI.toast("Tag 109 - R. VOSS. Someone else who never came up.")
		return
	make_room_for_key("tom_tag")
	if not Game.can_add("tom_tag", 1):
		UI.toast("Your inventory is full.")
		return
	Game.set_flag("got:mn_tag")
	Game.add_item("tom_tag", 1)
	Sfx.play("pickup")
	UI.show_item_get("tom_tag")
	_tag_moment()

func _tag_moment() -> void:
	lock_player(true)
	await get_tree().create_timer(0.6).timeout
	await say([["ELIAS", "114. T. KADE. They took every other tag down, after. Somebody left yours."],
		["ELIAS", "Fifteen years, Dad. I never came back to see the one place you're still on the wall."],
		["ELIAS", "...I'm here now. Late. I know. I'm always late."]])
	await get_tree().create_timer(1.0).timeout
	_hum_beat()
	_blink()
	await get_tree().create_timer(0.35).timeout
	await say([["TOM?", "Eli. You came back."]])
	await get_tree().create_timer(0.5).timeout
	await say([["ELIAS", "...No. That's the hum. Hart said it plays your dead back to you."],
		["ELIAS", "Don't answer it. Get the lever. Get the battery. Get June."]])
	lock_player(false)
	Game.set_objective("Find the hoist brake lever (south drift, 4 North) and a lamp battery (north, brine pumps).")

func _charger(_p) -> void:
	if Game.has_flag("mine_power"):
		UI.toast("The charger hums. Signal bells and hall lights are live.")
		return
	if not Game.has_item("lamp_battery"):
		UI.toast("The charger and bell signal are dead. They need a charged cap-lamp battery.")
		Sfx.play("deny")
		return
	Game.remove_item("lamp_battery", 1)
	Game.set_flag("mine_power")
	Sfx.play("unlock")
	_hall_power_on(false)
	lock_player(true)
	await say([["ELIAS", "Contacts are clean. Battery seated... signal bells are live. The hall lights just came up."]])
	lock_player(false)
	if Game.has_item("hoist_lever"):
		Game.set_objective("Fit the brake lever at the hoist station.")
	else:
		Game.set_objective("Find the hoist brake lever in the south drift (4 North).")

func _hall_power_on(silent: bool) -> void:
	for x in [30.5, 36.5, 43.0]:
		for z in [-6.0, 6.5]:
			var l := light(Vector3(x, 7.5, z), Color(0.85, 0.9, 1.0), 2.4, 12.0, false, x == 36.5 and z == 6.5)
			_hall_lamps.append(l)
			Props.box(geo, Vector3(1.2, 0.08, 0.3), Vector3(x, 7.7, z), Mats.emissive(Color(0.85, 0.92, 1.0), 2.5), false)
	if not silent:
		Sfx.play("lights_on")

# =================================================================== D. PUMP STATION (north)
func _build_pump_station() -> void:
	# adit x=9, z -1.8 .. -18
	tunnel(Vector2(9, -18), Vector2(9, -1.8), 2.8, 3.2, 0.0)
	for z in [-5.0, -9.0, -13.0]:
		timber_set(Vector3(9, 0, z), false, 2.8, 2.7)
	rails(Vector3(9.0, 0, -2.0), Vector3(9.0, 0, -17.8), 0.8)
	work_light(Vector3(9, 2.4, -6.5), false)
	work_light(Vector3(9, 2.4, -12.5), true, Color(0.7, 0.85, 1.0), 1.3, true)
	rime_run(Vector3(7.8, 0.1, -3), Vector3(7.8, 0.1, -17), Vector3(1, 0.5, 0), 6, 0.45, 1.8, 3)
	rime_run(Vector3(10.2, 0.1, -3), Vector3(10.2, 0.1, -17), Vector3(-1, 0.5, 0), 6, 0.45, 1.8)
	cable_run(Vector3(8.0, 3.0, -2.5), Vector3(8.0, 3.0, -17.5), 0.3, 10)
	body_in_rock(Vector3(8.4, 0, -10.8), 0.2, Vector3(-1, 0, 0))
	pickup("mn_adit_9mm", "ammo_9mm", 6, Vector3(10.0, 0.02, -15.0))
	# pump cavern
	cave(0, -32, 20, -18, 5.0, 0.0, {"s": [[9.0, 2.8, 2.8]]}, "concrete")
	for x in [4.0, 10.0, 16.0]:
		timber_set(Vector3(x, 0, -24), true, 14.0, 4.2)
	# Northline brine pumps: three big pump bodies with manifold
	for i in 3:
		var px := 4.0 + i * 5.5
		Props.cyl(geo, 0.9, 2.2, Vector3(px, 1.1, -27.0), Mats.get_mat("metal_painted", 1.5), true)
		Props.cyl(geo, 1.0, 0.2, Vector3(px, 2.3, -27.0), Mats.get_mat("metal", 1.5), false)
		Props.box(geo, Vector3(1.6, 0.6, 1.2), Vector3(px, 0.3, -27.0), Mats.get_mat("concrete", 1.5), false)
		Props.pipe(geo, Vector3(px, 2.4, -27.0), Vector3(px, 2.4, -30.6), 0.18, "metal_rust")
		Props.pipe(geo, Vector3(px - 1.0, 0.6, -27.0), Vector3(px - 1.0, 0.6, -30.6), 0.14, "metal_painted")
		Props.sphere(geo, 0.12, Vector3(px + 0.3, 1.8, -26.1), Mats.emissive(Color(1.0, 0.3, 0.1), 1.8) if i != 1 else Mats.emissive(Color(0.2, 1.0, 0.4), 1.8))
		rime(Vector3(px, 2.45, -27.0), Vector3.UP, 6, 0.5, i == 1)
	Props.pipe(geo, Vector3(1.0, 2.4, -30.6), Vector3(19.0, 2.4, -30.6), 0.3, "metal_rust")
	Props.pipe(geo, Vector3(1.0, 0.6, -30.6), Vector3(19.0, 0.6, -30.6), 0.18, "metal_painted")
	rime_run(Vector3(2.0, 2.7, -30.6), Vector3(19.0, 2.7, -30.6), Vector3.UP, 12, 0.5, 0.0, 4)
	Props.sign(geo, Vector3(10.0, 3.6, -31.6), 0.0, "NORTHLINE MINERAL\nBRINE LIFT STATION 2", 40, Color(0.5, 0.85, 1.0))
	# the pipe growth is thickest at pump 3 (the one that drew from the pocket)
	rime(Vector3(15.0, 0.02, -28.8), Vector3.UP, 12, 0.9, true)
	rime_run(Vector3(14.0, 0.1, -31.4), Vector3(19.0, 0.1, -31.4), Vector3(0, 0.6, 1), 6, 0.7, 2.5, 2)
	# control desk, workbench with the lamp battery
	Props.desk(geo, Vector3(3.0, 0, -19.5), 0.0)
	Props.table(geo, Vector3(17.0, 0, -29.5), 0.0, Vector2(2.2, 0.9))
	Props.box(geo, Vector3(0.28, 0.2, 0.18), Vector3(17.4, 0.88, -29.5), Mats.color(Color(0.3, 0.3, 0.2), 0.5, 0.4), false)
	pickup("mn_battery", "lamp_battery", 1, Vector3(17.0, 0.9, -29.5))
	Props.locker(geo, Vector3(1.0, 0, -21.5), PI * 0.5, 3)
	Props.barrel(geo, Vector3(18.8, 0, -20.0))
	Props.barrel(geo, Vector3(18.8, 0, -21.0), 0.0, false)
	Props.debris(geo, Vector3(7.0, 0, -21.0), 0.0, 6, "rock")
	Props.papers(geo, Vector3(4.2, 0.02, -21.0), 6)
	ore_cart(Vector3(13.5, 0, -20.5), 0.4, true)
	# lights
	work_light(Vector3(5.0, 3.6, -22.0), true, Color(1.0, 0.8, 0.5), 2.0, true, 1.2)
	work_light(Vector3(14.0, 3.6, -23.0), false, Color(1, 1, 1), 1.0, false, 1.2)
	work_light(Vector3(17.0, 3.0, -29.0), true, Color(0.8, 0.9, 1.0), 1.8, true, 1.5)
	light(Vector3(10.0, 3.0, -24.0), Color(0.5, 0.75, 1.0), 1.2, 9.0, true)
	vent_duct(Vector3(0.7, 4.3, -19.0), Vector3(19.5, 4.3, -19.0), 0.8)
	vent_duct(Vector3(0.7, 4.2, -31.0), Vector3(0.7, 4.2, -19.5), 0.8)
	cable_run(Vector3(1.0, 4.6, -24.0), Vector3(19.0, 4.6, -24.0), 0.5, 10)
	for i in 8:
		icicle(Vector3(rk(1, 19), 4.8, rk(-31, -19)), rk(0.5, 1.2))
	note("mn_note_northline", Vector3(3.0, 0.82, -19.5), "Northline Incident Report NM-26-0417",
		"[b]NORTHLINE MINERAL - INTERNAL - PRIVILEGED[/b]\n[b]INCIDENT REPORT NM-26-0417 - BRINE POCKET B-7[/b]\n\nDuring ramp of the heat-recovery loop to 41 C feed (CORVANE SYSTEMS / MERIDIAN contract), Lift Pump 3 drew from a previously sealed pocket at 412 m.\n\nOperators report [b]biological growth[/b] on pump casing: crystalline, conductive, self-heating. Growth rate on heated surfaces: ~4 cm/day. Three operators report cold intolerance, sleep loss, and auditory phenomena (voices; low hum). One operator failed to report for shift.\n\n[b]RECOMMENDATION (I. Hart, Site Geologist):[/b] Halt heat injection. Quarantine B-7. Notify state.\n\n[b]MANAGEMENT RESPONSE:[/b] [color=#ff6a50]DENIED.[/color] Heat offtake is contractual. Reclassify as 'mineral scaling'. Remind all personnel of NDA obligations. Do not escalate to regulators.\n\n[i]- Regional Operations[/i]", 0.0)
	# lamp battery foot note: June's chalk or a miner's
	# ambushes: pump 3 corner. trigger raises the hum and wakes the siren's escorts
	trigger("mn_pump_enter", Vector3(9, 1.2, -19.8), Vector3(3.0, 2.4, 1.4), func(_p):
		Sfx.music("music_tension")
		for e in get_tree().get_nodes_in_group("enemy"):
			if is_instance_valid(e) and e.has_method("wake") and e.get("dormant") == true and e.global_position.z < -18.0:
				e.wake())

# =================================================================== E. COLLAPSED DRIFT + MEMORIAL (south)
func _build_drift() -> void:
	tunnel(Vector2(17, 1.8), Vector2(17, 16), 2.8, 3.2, 0.0)
	for z in [4.0, 7.0, 10.0, 13.0]:
		timber_set(Vector3(17, 0, z), false, 2.8, 2.7)
	rails(Vector3(17.0, 0, 2.0), Vector3(17.0, 0, 15.8), 0.8)
	work_light(Vector3(17, 2.4, 5.0), true, Color(0.75, 0.88, 1.0), 1.3, true)
	work_light(Vector3(17, 2.4, 11.0), false)
	rime_run(Vector3(15.8, 0.1, 3), Vector3(15.8, 0.1, 15), Vector3(1, 0.5, 0), 6, 0.4, 1.8, 3)
	rime_run(Vector3(18.2, 0.1, 3), Vector3(18.2, 0.1, 15), Vector3(-1, 0.5, 0), 6, 0.4, 1.8)
	cable_run(Vector3(16.0, 3.0, 2.5), Vector3(16.0, 3.0, 15.5), 0.3, 10)
	body_in_rock(Vector3(15.7, 0, 8.0), 1.6, Vector3(-1, 0, 0))
	pickup("mn_drift_gel", "gel", 1, Vector3(18.0, 0.02, 12.5))
	# memorial cavern
	cave(7, 16, 29, 30, 4.2, 0.0, {"n": [[10.0, 2.8, 2.8]]})
	# rock fall: the east half is buried
	for i in 22:
		var rx := rk(21.0, 28.0)
		var rz := rk(17.0, 29.0)
		var hgt := rk(0.8, 3.0) * (1.0 + (rx - 21.0) * 0.12)
		Props.box(geo, Vector3(rk(1.0, 2.2), hgt, rk(1.0, 2.2)), Vector3(rx, hgt * 0.5 - 0.1, rz), _rmat("rock"), true, Vector3(rk(-0.3, 0.3), rk(0, 3), rk(-0.3, 0.3)))
	Props.box(geo, Vector3(8.0, 4.4, 14.0), Vector3(26.0, 2.2, 23.0), _rmat("rock_wet"), false)
	for i in 10:
		var bx := rk(21.0, 25.0)
		Props.box(geo, Vector3(rk(0.8, 1.6), rk(2.2, 4.4), rk(0.8, 1.6)), Vector3(bx, 1.1, rk(17.5, 29.0)), _rmat("sewer"), false, Vector3(rk(-0.3, 0.3), rk(0, 3), rk(-0.3, 0.3)))
	# splintered, crushed timber sets
	for z in [18.5, 22.0, 26.0]:
		Props.box(geo, Vector3(0.3, 3.4, 0.3), Vector3(20.0, 1.7, z), _timber(), false, Vector3(0, 0, rk(-0.35, 0.35)))
		Props.box(geo, Vector3(0.3, 0.3, 3.0), Vector3(20.2, 3.0, z + 0.6), _timber(), false, Vector3(rk(-0.4, 0.2), 0, rk(-0.3, 0.3)))
	# the memorial: hard hats, plastic flowers, photographs, candles, a wooden cross
	var mx := 12.0
	Props.box(geo, Vector3(5.0, 0.35, 1.2), Vector3(mx, 0.17, 28.8), _timber(), true)
	Props.box(geo, Vector3(4.6, 1.6, 0.1), Vector3(mx, 1.1, 29.6), Mats.get_mat("wood_panel", 1.0), false)
	Props.box(geo, Vector3(0.12, 1.9, 0.12), Vector3(mx, 1.4, 29.45), _timber(), false)
	Props.box(geo, Vector3(1.0, 0.12, 0.12), Vector3(mx, 1.8, 29.45), _timber(), false)
	Props.sign(geo, Vector3(mx, 2.55, 29.5), PI, "IN MEMORY OF THOMAS J. KADE  AND  ROBERT VOSS\nFEB 11, 2011  -  THEY WENT DOWN FOR US", 24, Color(0.92, 0.88, 0.75))
	var hats := [Color(0.95, 0.75, 0.1), Color(0.9, 0.9, 0.9), Color(0.85, 0.3, 0.15), Color(0.2, 0.4, 0.8), Color(0.95, 0.75, 0.1), Color(0.9, 0.9, 0.9)]
	for i in 6:
		hard_hat(Vector3(mx - 2.0 + i * 0.8, 0.35, 28.7 + rk(-0.2, 0.2)), hats[i], rk(-1, 1))
	for i in 9:
		var fx := mx - 2.2 + i * 0.55
		Props.cyl(geo, 0.008, 0.45, Vector3(fx, 0.55, 28.35 + rk(-0.1, 0.1)), Mats.color(Color(0.1, 0.4, 0.15), 0.8), false, -1.0, Vector3(rk(-0.3, 0.3), 0, rk(-0.3, 0.3)), 4)
		var fc: Color = [Color(0.9, 0.2, 0.25), Color(0.95, 0.85, 0.3), Color(0.9, 0.9, 0.95), Color(0.9, 0.4, 0.7)][i % 4]
		Props.sphere(geo, 0.06, Vector3(fx, 0.8, 28.35), Mats.color(fc, 0.6))
	rime(Vector3(mx - 2.1, 0.37, 28.6), Vector3.UP, 4, 0.3)
	rime(Vector3(mx + 2.0, 0.37, 28.5), Vector3.UP, 5, 0.4)
	Props.box(geo, Vector3(0.28, 0.2, 0.01), Vector3(mx + 0.9, 1.0, 29.52), Mats.color(Color(0.55, 0.5, 0.42), 0.6), false)
	for cx in [mx - 1.4, mx + 1.6]:
		Props.cyl(geo, 0.04, 0.2, Vector3(cx, 0.46, 28.55), Mats.color(Color(0.9, 0.88, 0.8), 0.7), false)
		Props.sphere(geo, 0.025, Vector3(cx, 0.58, 28.55), Mats.emissive(Color(1.0, 0.7, 0.3), 3.0))
	light(Vector3(mx, 0.9, 28.2), Color(1.0, 0.7, 0.35), 1.6, 5.5, true, true)
	# Tom's toolbox: the hoist lever
	var tb := Node3D.new()
	tb.position = Vector3(mx + 2.9, 0, 28.5)
	add_child(tb)
	Props.box(tb, Vector3(0.7, 0.35, 0.3), Vector3(0, 0.18, 0), Mats.color(Color(0.5, 0.12, 0.1), 0.5, 0.4), true)
	Props.box(tb, Vector3(0.7, 0.04, 0.32), Vector3(0, 0.37, 0), Mats.color(Color(0.55, 0.14, 0.12), 0.5, 0.4), false, Vector3(0.4, 0, 0))
	Props.sign(tb, Vector3(0, 0.2, 0.16), 0.0, "T. KADE", 14, Color(0.9, 0.85, 0.7), false)
	pickup("mn_lever", "hoist_lever", 1, Vector3(mx + 2.9, 0.45, 28.5))
	# floor dressing
	Props.debris(geo, Vector3(14.0, 0, 20.0), 0.0, 8, "rock")
	Props.debris(geo, Vector3(10.0, 0, 24.0), 1.0, 5, "rock")
	Props.papers(geo, Vector3(9.5, 0.02, 21.0), 5)
	ore_cart(Vector3(10.0, 0, 18.5), 0.0, false)
	rails(Vector3(17.0, 0, 16.0), Vector3(17.0, 0, 22.0), 0.8)
	cable_run(Vector3(8.0, 3.7, 17.0), Vector3(20.0, 3.7, 29.0), 0.5, 10)
	work_light(Vector3(14.0, 3.3, 22.0), false, Color(1, 1, 1), 1.0, false, 0.8)
	work_light(Vector3(18.0, 3.3, 26.0), true, Color(0.7, 0.85, 1.0), 1.4, true, 0.8)
	light(Vector3(14.0, 2.2, 25.0), Color(0.5, 0.75, 1.0), 1.1, 8.0, true)
	rime_run(Vector3(8.0, 0.1, 18), Vector3(8.0, 0.1, 29), Vector3(1, 0.6, 0), 8, 0.5, 2.0, 3)
	rime_run(Vector3(20.0, 0.1, 17.5), Vector3(20.0, 0.1, 29.0), Vector3(-1, 0.6, 0), 10, 0.55, 3.0, 3)
	for i in 6:
		icicle(Vector3(rk(8, 20), 4.1, rk(17, 29)), rk(0.5, 1.2))
	body_in_rock(Vector3(19.0, 0, 21.5), 0.8, Vector3(1, 0, 0))
	pickup("mn_drift_44a", "ammo_44", 3, Vector3(mx + 2.1, 0.02, 26.8))
	pickup("mn_drift_adr", "adrenaline", 1, Vector3(8.8, 0.02, 21.5))
	note("mn_note_msha", Vector3(mx - 3.0, 0.4, 28.0), "MSHA Report of Investigation (excerpt)",
		"[b]U.S. DEPARTMENT OF LABOR - MINE SAFETY AND HEALTH ADMINISTRATION[/b]\n[b]REPORT OF INVESTIGATION - FATAL GROUND FALL[/b]\nLower Kettle Mine, Kettle Falls, Minnesota - February 11, 2011\n\n[b]FINDINGS (excerpt)[/b]\nA roof fall of approx. 340 tons occurred in 4 North Drift at 02:14. Two miners were buried: Thomas J. Kade (49, roof bolter) and Robert Voss (31, helper). Recovery was suspended after secondary falls.\n\n[b]CONTRIBUTING FACTORS[/b]\n1. Scheduled rehabilitation of 4 North was deferred for 14 months.\n2. Ground-control inspections were reduced from weekly to monthly 'to reduce downtime.'\n3. Night foreman G. Arsenault submitted a written request on Oct. 3, 2010 to close the drift. It was returned with the notation: [b]'Not in budget.'[/b]\n\n[b]ENFORCEMENT[/b]\nThree citations. Total proposed penalty: $11,400. The operator contests all three.\n\n[i]4 North Drift was sealed. The bodies were not recovered.[/i]", 0.4)
	# beats
	trigger("mn_memorial", Vector3(17, 1.2, 18.0), Vector3(3.0, 2.4, 2.0), func(_p):
		await get_tree().create_timer(0.5).timeout
		await say([["ELIAS", "4 North. The roof just... stopped. Dad's hard hat is on that shelf. Somebody kept these up. Fifteen years."]])
		_hum_beat()
		await get_tree().create_timer(0.8).timeout
		await say([["TOM?", "I told them the roof was wrong, Eli. I told them."],
			["ELIAS", "I know, Dad. I know you did."]]))

# =================================================================== F. LOWER LEVEL
func _build_lower_landing() -> void:
	var y := LY
	cave(56, -6, 68, 6, 4.6, y, {"e": [[6.0, 3.2, 3.0]]}, "concrete")
	# lower cage landing
	cage_lo = Node3D.new()
	cage_lo.position = Vector3(60.0, y, 0)
	add_child(cage_lo)
	Props.box(cage_lo, Vector3(3.8, 0.3, 3.8), Vector3(0, 0.0, 0), Mats.get_mat("metal_rust", 1.5), true)
	for sx in [-1.8, 1.8]:
		for sz in [-1.8, 1.8]:
			Props.box(cage_lo, Vector3(0.12, 2.6, 0.12), Vector3(sx, 1.4, sz), Mats.get_mat("metal_painted", 1.0), false)
	Props.box(cage_lo, Vector3(3.9, 0.12, 3.9), Vector3(0, 2.7, 0), Mats.get_mat("metal_painted", 1.0), false)
	Props.sign(cage_lo, Vector3(0, 2.4, 1.95), 0.0, "CAGE NO. 1  -  LEVEL 2", 26, Color(0.9, 0.85, 0.7))
	for sx in [-0.6, 0.6]:
		Props.pipe(geo, Vector3(60.0 + sx, y + 2.7, 0), Vector3(60.0 + sx, y + 4.6, 0), 0.035, "metal_rust")
	interact(Vector3(60.0, y + 1.0, 0.0), "Ride the cage up", _ride_up, 2.4)
	# surrounding frame
	rails(Vector3(62.5, y, 0.55), Vector3(68.0, y, 0.55), 0.85)
	work_light(Vector3(58.0, y + 3.4, -3.5), true, Color(0.85, 0.92, 1.0), 1.8, true, 1.0)
	work_light(Vector3(64.0, y + 3.4, 3.5), true, Color(1.0, 0.8, 0.5), 1.5, false, 1.0)
	light(Vector3(62.0, y + 3.0, 0.0), Color(0.6, 0.75, 1.0), 1.3, 10.0, true)
	rime_run(Vector3(56.8, y + 0.1, -5.0), Vector3(56.8, y + 0.1, 5.0), Vector3(1, 0.6, 0), 8, 0.5, 2.0, 3)
	rime_run(Vector3(67.2, y + 0.1, -5.0), Vector3(67.2, y + 0.1, 5.0), Vector3(-1, 0.6, 0), 6, 0.5, 2.0)
	Props.crate(geo, Vector3(57.4, y, 4.6), 0.2, 0.9)
	Props.barrel(geo, Vector3(57.4, y, -4.8))
	Props.debris(geo, Vector3(65.0, y, -3.5), 0.3, 6, "rock")
	vent_duct(Vector3(56.7, y + 4.0, -4.0), Vector3(67.3, y + 4.0, -4.0), 0.7)
	for i in 5:
		icicle(Vector3(rk(57, 67), y + 4.5, rk(-5, 5)), rk(0.4, 1.0))
	pickup("mn_low_9mm", "ammo_9mm", 8, Vector3(57.5, y + 0.92, 4.6))
	pickup("mn_low_inc", "ammo_grenade", 1, Vector3(57.4, y + 0.02, -3.8))
	# arrival beat: Tom warns him
	trigger("mn_low_tom", Vector3(65.0, y + 1.2, 0), Vector3(1.6, 2.4, 3.0), func(_p):
		_hum_beat()
		await get_tree().create_timer(0.5).timeout
		await say([["TOM?", "Don't go down any further, Eli. It's warm down there. That's the trouble."],
			["ELIAS", "Dad, if that's you... I'm going anyway. June's down there."]]))

func _build_haulage() -> void:
	var y := LY
	tunnel(Vector2(68, 0), Vector2(84, 0), 3.6, 3.8, y, [], [[8.0, 2.4, 2.8]])
	for x in [70.0, 74.0, 78.0, 82.0]:
		timber_set(Vector3(x, y, 0), true, 3.6, 3.1)
	rails(Vector3(68.0, y, 0.55), Vector3(84.0, y, 0.55), 0.85)
	rails(Vector3(68.0, y, -0.55), Vector3(84.0, y, -0.55), 0.85)
	work_light(Vector3(72.0, y + 2.6, 0.5), false)
	work_light(Vector3(78.0, y + 2.6, -0.5), true, Color(1.0, 0.45, 0.2), 1.5, true)
	rime_run(Vector3(68.5, y + 0.1, -1.6), Vector3(83.5, y + 0.1, -1.6), Vector3(0, 0.6, 1), 10, 0.45, 2.0, 3)
	rime_run(Vector3(68.5, y + 0.1, 1.6), Vector3(83.5, y + 0.1, 1.6), Vector3(0, 0.6, -1), 10, 0.45, 2.0)
	cable_run(Vector3(68.5, y + 3.2, 1.2), Vector3(83.5, y + 3.2, 1.2), 0.35, 12)
	vent_duct(Vector3(68.5, y + 3.0, -1.2), Vector3(83.5, y + 3.0, -1.2), 0.5)
	ore_cart(Vector3(70.7, y, 0.55), PI * 0.5)        # QA: moved west, off the magazine entrance (was x=74.5/75.8)
	ore_cart(Vector3(71.9, y, 0.55), PI * 0.5, false)
	body_in_rock(Vector3(70.5, y, -1.2), -0.2, Vector3(0, 0, -1))
	body_in_rock(Vector3(81.0, y, 1.2), 3.0, Vector3(0, 0, 1))
	pickup("mn_hal_44", "ammo_44", 3, Vector3(79.2, y + 0.02, -1.1))
	pickup("mn_hal_9mm", "ammo_9mm", 6, Vector3(72.0, y + 0.02, 1.2))
	# powder magazine: concrete room south of the tunnel
	room(70, 4, 82, 12, 3.2, "concrete", "concrete", "concrete", {"n": [[6.0, 2.4, 2.4]]}, y)
	# QA fix: the tunnel wall gap (z=1.8) and the magazine door (z=4) were separated by a 2.2 m void
	tunnel(Vector2(76.0, 1.6), Vector2(76.0, 4.1), 2.4, 2.8, y, [], [])
	door("mn_magdoor", Vector3(76.0, y, 4.0), 0.0, {"width": 2.2, "height": 2.4, "mat": "metal_rust", "prompt": "Open magazine door"})
	Props.sign(geo, Vector3(76.0, y + 2.75, 3.8), 0.0, "POWDER MAGAZINE\nNO FLAME - NO ENTRY", 30, Color(0.95, 0.35, 0.2))
	ceiling_lamp(Vector3(76.0, y + 3.2, 8.0), "bulb", true, true)
	for sx in [71.0, 81.0]:
		Props.shelf(geo, Vector3(sx, y, 11.4), PI, 2.0, 2.0, false)
	Props.crate(geo, Vector3(71.2, y, 6.0), 0.3, 0.9)
	Props.crate(geo, Vector3(71.3, y, 7.0), 0.0, 0.8)
	Props.crate(geo, Vector3(71.2, y + 0.9, 6.1), 0.7, 0.6)
	Props.crate(geo, Vector3(80.8, y, 6.4), 0.1, 0.9)
	Props.table(geo, Vector3(76.0, y, 9.5), 0.0, Vector2(2.4, 1.0))
	rime(Vector3(76.0, y + 0.8, 9.5), Vector3.UP, 3, 0.2)
	pickup("mn_dyn", "dynamite", 1, Vector3(76.0, y + 0.82, 9.7))
	pickup("mn_mag_inc", "ammo_grenade", 1, Vector3(81.0, y + 0.02, 8.0))
	pickup("mn_mag_shell", "ammo_shell", 5, Vector3(72.0, y + 0.02, 10.4))
	pickup("mn_mag_flare", "flare", 1, Vector3(80.9, y + 0.92, 6.4))
	note("mn_note_imogen", Vector3(75.2, y + 0.82, 9.3), "Field Notebook, p. 41 (I. Hart)",
		"[b]DR. IMOGEN HART - FIELD NOTEBOOK - p. 41[/b]\n[i]Colony response to heat.[/i]\n\nIt does not resist heat. It [b]follows[/b] it.\n\nGrowth scales with the temperature difference between pipe and rock. At the 41 C feed: 4 cm a day. At a full 60 C feed: I stopped writing the numbers down. It does not eat heat the way a fire does. It [i]moves[/i] it. Everything it takes goes down - to the pocket, to the middle. Whatever lives down there is warm, and getting warmer.\n\nTwo ways this ends:\n1. Cut the heat off entirely. It starves back into the dormancy it had for ten thousand years.\n2. Give it more than it can carry. I do not know what happens then. I only know that everything it has ever held is down there with it.\n\nAnd the voices. 19 Hz is just under what you can hear. You do not hear it. You [i]remember[/i] it. Do not trust any voice that knows what you would give to hear it again.\n\nI've been hearing my brother since March.", 0.2)
	# lighting inside the magazine is the only warm light, so the player understands the way
	light(Vector3(76.0, y + 2.4, 8.0), Color(1.0, 0.7, 0.4), 1.2, 7.0, true)
	# storage rime
	rime_run(Vector3(70.5, y + 0.1, 5.0), Vector3(70.5, y + 0.1, 11.0), Vector3(1, 0.6, 0), 4, 0.35, 1.5)

func _build_cavern() -> void:
	var y := LY
	cave(84, -18, 120, 18, 12.0, y, {"w": [[18.0, 3.6, 3.4]], "n": [[26.0, 3.0, 3.0]], "e": [[18.0, 3.6, 3.4]]}, "dirt")
	# fix: tunnel in from the west joins at z=0 (w gap at dist 18)
	# pillars
	for p in [Vector3(94, 0, -9), Vector3(94, 0, 9), Vector3(100, 0, 0), Vector3(112, 0, 10), Vector3(110, 0, -11)]:
		Props.cyl(geo, rk(1.2, 1.6), 12.0, Vector3(p.x, y + 6.0, p.z), _rmat("rock"), true, rk(1.5, 2.0), Vector3.ZERO, 12)
		rime(Vector3(p.x, y + 0.1, p.z + 1.5), Vector3.UP, 5, 0.5, true)
	# THE weak pillar: marked, cribbed, cracked
	var wp := Vector3(106.0, 0, -4.0)
	_pillar = Node3D.new()
	_pillar.position = Vector3(wp.x, y, wp.z)
	add_child(_pillar)
	Props.cyl(_pillar, 1.1, 12.0, Vector3(0, 6.0, 0), _rmat("rock_wet"), true, 1.7, Vector3.ZERO, 12)
	for k in 5:
		Props.box(_pillar, Vector3(0.1, rk(1.5, 3.5), 0.05), Vector3(rk(-0.8, 0.8), rk(1.0, 6.0), 1.0), Mats.color(Color(0.05, 0.05, 0.05), 1.0), false, Vector3(0, rk(0, 3), rk(-0.5, 0.5)))
	for k in 4:
		Props.box(_pillar, Vector3(0.3, 1.2, 0.3), Vector3(cos(k * PI * 0.5) * 1.3, 0.6, sin(k * PI * 0.5) * 1.3), _timber(), false, Vector3(0, 0, rk(-0.15, 0.15)))
	Props.cyl(_pillar, 1.15, 0.25, Vector3(0, 2.4, 0), Mats.emissive(Color(1.0, 0.1, 0.05), 1.2), false, 1.15, Vector3.ZERO, 12)
	Props.sign(_pillar, Vector3(0, 3.0, 1.2), 0.0, "X\nUNSOUND", 60, Color(1.0, 0.2, 0.15))
	light(Vector3(wp.x, y + 3.0, wp.z + 2.0), Color(1.0, 0.15, 0.1), 1.5, 6.5, false, true)
	interact(Vector3(wp.x, y + 1.0, wp.z + 1.9), "Marked pillar", _plant_charges, 2.3)
	# rubble field, ore carts, the wrecked haul truck
	for i in 18:
		var rx := rk(86, 118)
		var rz := rk(-16, 16)
		Props.box(geo, Vector3(rk(0.5, 1.4), rk(0.3, 0.9), rk(0.5, 1.4)), Vector3(rx, y + 0.2, rz), _rmat("rock"), false, Vector3(rk(-0.3, 0.3), rk(0, 3), rk(-0.3, 0.3)))
	ore_cart(Vector3(90.0, y, -13.0), 0.6, true)
	ore_cart(Vector3(91.6, y, -12.2), 0.2, true)
	ore_cart(Vector3(117.0, y, -3.0), 1.4, false)
	ore_cart(Vector3(98.0, y, 14.0), -0.5, true)
	rails(Vector3(84.0, y, 0.55), Vector3(97.0, y, 0.55), 0.85)
	_haul_truck(Vector3(113.0, y, 6.5), 2.6)
	# ledge: old drilling jumbo on a pile
	Props.box(geo, Vector3(3.0, 1.2, 1.6), Vector3(88.0, y + 0.6, 14.0), Mats.get_mat("metal_rust", 1.0), true)
	Props.pipe(geo, Vector3(88.0, y + 1.2, 14.0), Vector3(91.0, y + 2.4, 14.4), 0.12, "metal_rust")
	# cavern lighting: red work lamp on the pillar, big cold fill from a rime mass, flickering truck headlamps
	light(Vector3(100.0, y + 5.0, 0.0), Color(0.5, 0.75, 1.0), 3.0, 22.0, true)
	light(Vector3(92.0, y + 4.0, 0.0), Color(0.45, 0.7, 1.0), 1.6, 14.0, false)
	light(Vector3(108.0, y + 4.0, 12.0), Color(0.45, 0.7, 1.0), 1.6, 14.0, false)
	light(Vector3(112.0, y + 4.0, -10.0), Color(0.45, 0.7, 1.0), 1.6, 14.0, false)
	light(Vector3(88.0, y + 2.6, -10.0), Color(1.0, 0.8, 0.5), 1.3, 7.0, false, true)
	work_light(Vector3(96.0, y + 5.0, -14.0), true, Color(1.0, 0.8, 0.5), 2.0, true, 1.5)
	work_light(Vector3(104.0, y + 6.0, 12.0), false, Color(1, 1, 1), 1.0, false, 1.5)
	work_light(Vector3(86.5, y + 3.0, 7.0), true, Color(0.9, 0.95, 1.0), 1.8, true, 1.0)
	# rime mass on the north wall (it's what pulls from the shaft)
	for i in 3:
		rime(Vector3(rk(100, 118), y + 0.1, -17.2), Vector3(0, 0.5, 1), 12, 1.1, i == 1)
	rime_run(Vector3(85.0, y + 0.1, 17.0), Vector3(119.0, y + 0.1, 17.0), Vector3(0, 0.5, -1), 18, 0.8, 4.0, 4)
	rime_run(Vector3(85.0, y + 0.1, -17.0), Vector3(99.0, y + 0.1, -17.0), Vector3(0, 0.5, 1), 8, 0.8, 4.0, 4)
	for i in 10:
		icicle(Vector3(rk(86, 118), y + 11.7, rk(-16, 16)), rk(0.8, 2.0))
	vent_duct(Vector3(85.0, y + 9.0, 17.0), Vector3(119.0, y + 9.0, 17.0), 1.0)
	cable_run(Vector3(85.0, y + 9.5, -16.0), Vector3(119.0, y + 9.5, -16.0), 1.2, 10)
	# entrance alcove: trauma kit + painkillers right before the boss
	Props.crate(geo, Vector3(86.4, y, -15.6), 0.4, 0.9)
	Props.crate(geo, Vector3(86.2, y, -14.5), -0.2, 0.8)
	pickup("mn_cav_spray", "spray", 1, Vector3(86.4, y + 0.92, -15.6))
	pickup("mn_cav_9mm", "ammo_9mm", 5, Vector3(86.3, y + 0.02, -13.4))
	pickup("mn_cav_adr", "adrenaline", 1, Vector3(87.2, y + 0.02, -15.0))
	pickup("mn_cav_gel", "gel", 1, Vector3(86.3, y + 0.82, -14.5))
	pickup("mn_cav_shell", "ammo_shell", 5, Vector3(116.5, y + 0.02, 14.5))
	note("mn_note_refuge", Vector3(102.0, y + 0.02, 15.5), "Scratched into the steel",
		"[b]Scratched with a knife into a hauler's door panel:[/b]\n\nDAY 3 IN THE REFUGE. SIX OF US WENT IN. FOUR NOW.\n\nTHE HUM STARTS AT DUSK. DEL WALKED OUT TO ANSWER HIS WIFE. WE KNOW SHE'S DEAD. HE HEARD HER ANYWAY. WE HEARD HIM SAY SORRY TO THE DOOR AND THEN THE DOOR WAS OPEN AND THE DOOR WAS CLOSED.\n\nDO NOT OPEN FOR ANYONE WHO KNOWS YOUR NAME.\n\nKEEP WARM. KEEP QUIET. KEEP COUNTING.\n\nIF YOU FIND THIS: THE FOREMAN WENT UP, NOT DOWN. THE BIG ONE IS IN THE CAVERN. IT WAS THE ORE TRUCKS. IT'S ALL OF US.\n\n[i]- M. OKONKWO, SHIFT B[/i]", 0.0)
	# the fight: entering the cavern
	trigger("mn_cavern_enter", Vector3(87.0, y + 1.2, 0), Vector3(2.0, 2.6, 4.0), func(_p): _hauler_start())
	if not Game.has_flag("hauler_dead"):
		hauler = enemy("mn_hauler", "boss_hauler", Vector3(114.0, y + 0.05, -4.0), -PI * 0.5, {"dormant": true})
		if hauler != null and hauler.has_signal("died"):
			hauler.connect("died", _on_hauler_died)

func _haul_truck(pos: Vector3, yaw: float) -> void:
	var r := Node3D.new()
	r.position = pos
	r.rotation.y = yaw
	geo.add_child(r)
	var body := Mats.get_mat("metal_rust", 2.0)
	var yel := Mats.color(Color(0.55, 0.42, 0.08), 0.6, 0.4)
	Props.box(r, Vector3(9.0, 1.2, 3.8), Vector3(0, 1.8, 0), yel, true)
	Props.box(r, Vector3(2.6, 2.2, 3.4), Vector3(-3.6, 3.5, 0), yel, true)
	Props.box(r, Vector3(0.05, 1.0, 2.6), Vector3(-4.95, 3.8, 0), Mats.color(Color(0.05, 0.07, 0.08, 0.6), 0.1, 0.6), false)
	# tilted dump bed
	Props.box(r, Vector3(6.4, 0.3, 3.6), Vector3(1.4, 3.6, 0), body, true, Vector3(0, 0, 0.28))
	Props.box(r, Vector3(6.4, 1.6, 0.3), Vector3(1.4, 4.4, -1.8), body, false, Vector3(0, 0, 0.28))
	Props.box(r, Vector3(6.4, 1.6, 0.3), Vector3(1.4, 4.4, 1.8), body, false, Vector3(0, 0, 0.28))
	for sx in [-3.2, 3.2]:
		for sz in [-2.0, 2.0]:
			Props.cyl(r, 1.3, 0.9, Vector3(sx, 1.3, sz), Mats.color(Color(0.05, 0.05, 0.05), 0.9), true, -1.0, Vector3(PI * 0.5, 0, 0), 18)
	# frozen miners fused into the bed and the cab: Rime clumps and bodies
	rime(pos + Vector3(0, 5.0, 0), Vector3.UP, 14, 1.4, true)
	rime(pos + Vector3(-0.3, 4.6, 1.0), Vector3(0, 0.5, 1), 8, 0.9)
	Props.corpse(geo, pos + Vector3(-2.0, 0, 3.3), 0.4, {"skin": Color(0.55, 0.68, 0.72), "shirt": Color(0.34, 0.27, 0.16)})
	work_light(pos + Vector3(-5.1, 3.0, 1.0), true, Color(1.0, 0.9, 0.7), 1.5, true, 0.3)

func _build_refuge() -> void:
	var y := LY
	# approach tunnel north of the cavern
	tunnel(Vector2(110, -26), Vector2(110, -18), 3.0, 3.4, y)
	timber_set(Vector3(110, y, -20), false, 3.0, 2.8)
	timber_set(Vector3(110, y, -24), false, 3.0, 2.8)
	work_light(Vector3(110, y + 2.5, -21), true, Color(0.7, 0.85, 1.0), 1.4, true)
	rime_run(Vector3(108.7, y + 0.1, -19), Vector3(108.7, y + 0.1, -25), Vector3(1, 0.5, 0), 5, 0.5, 1.8, 2)
	# the steel refuge chamber (a 12x8 shipping-container room)
	floor_rect(104, -34, 116, -26, y, "metal")
	ceiling_rect(104, -34, 116, -26, y + 3.0, "metal_painted")
	wall(Vector2(104, -26), Vector2(116, -26), 3.0, "metal_painted", y, 0.25, [[6.0, 1.7, 2.4]])
	wall(Vector2(104, -34), Vector2(116, -34), 3.0, "metal_painted", y, 0.25)
	wall(Vector2(104, -34), Vector2(104, -26), 3.0, "metal_painted", y, 0.25)
	wall(Vector2(116, -34), Vector2(116, -26), 3.0, "metal_painted", y, 0.25)
	door("mn_refugedoor", Vector3(110, y, -26), 0.0, {"width": 1.5, "height": 2.4, "mat": "metal", "lock_flag": "hauler_dead",
		"locked_msg": "A steel refuge door, dogged shut from inside. Something huge is shaking the cavern - you can't get close.", "prompt": "Open the refuge door"})
	Props.sign(geo, Vector3(110, y + 2.65, -25.8), 0.0, "REFUGE CHAMBER NO. 3\n18 MEN - 36 HOURS AIR", 32, Color(0.2, 0.9, 0.5))
	# bunks, supplies, water, oxygen
	Props.bed(geo, Vector3(105.2, y, -31.0), 0.0)
	Props.bed(geo, Vector3(105.2, y, -28.2), 0.0)
	Props.bed(geo, Vector3(114.8, y, -31.0), 0.0)
	Props.shelf(geo, Vector3(109.0, y, -33.5), 0.0, 2.4, 2.0, false)
	for i in 5:
		Props.cyl(geo, 0.16, 0.5, Vector3(111.3 + i * 0.45, y + 0.25, -33.4), Mats.color(Color(0.2, 0.4, 0.8, 1.0), 0.3), false)
	Props.cyl(geo, 0.14, 1.3, Vector3(114.8, y + 0.65, -33.4), Mats.color(Color(0.2, 0.55, 0.3), 0.4, 0.6), false)
	Props.box(geo, Vector3(1.0, 0.3, 0.7), Vector3(113.0, y + 0.15, -30.0), Mats.color(Color(0.8, 0.8, 0.85), 0.5), false)
	Props.papers(geo, Vector3(108.0, y + 0.02, -30.0), 5)
	# the lantern: a single battery lantern, cold glow; June's flashing radio
	Props.cyl(geo, 0.1, 0.28, Vector3(111.5, y + 0.14, -31.2), Mats.emissive(Color(0.9, 0.95, 1.0), 2.0), false)
	light(Vector3(111.5, y + 0.6, -31.2), Color(0.8, 0.9, 1.0), 1.6, 8.0, true)
	light(Vector3(109.0, y + 2.5, -28.0), Color(1.0, 0.25, 0.15), 0.6, 5.0, false, true)
	# rime in the corners: the cold got in
	rime(Vector3(105.0, y + 0.05, -33.0), Vector3.UP, 7, 0.5)
	rime(Vector3(115.0, y + 0.05, -26.8), Vector3.UP, 6, 0.45)
	pickup("mn_ref_gel", "gel", 1, Vector3(113.0, y + 0.35, -30.0))
	pickup("mn_ref_flare", "flare", 1, Vector3(112.0, y + 0.02, -33.0))
	# JUNE
	if not Game.has_flag("found_june"):
		_spawn_june(Vector3(112.3, y, -31.8), false)
		interact(Vector3(112.3, y + 1.0, -31.2), "Talk to June", _reunion, 1.9)
	# approach beat
	trigger("mn_ref_voice", Vector3(110, y + 1.2, -22.5), Vector3(2.6, 2.4, 1.0), func(_p):
		await get_tree().create_timer(0.3).timeout
		await say([["JUNE", "...Dad? Dad, is that you? Or are you the other one?"],
			["ELIAS", "It's me, June. It's me. Open the door."]]))

func _spawn_june(pos: Vector3, follow: bool) -> void:
	if is_instance_valid(june):
		return
	if ResourceLoader.exists("res://actors/npc.gd"):
		var N = load("res://actors/npc.gd")
		june = N.new()
		june.setup_npc(N.preset("june"))
		june.set("display_name", "JUNE")
		june.set("follow_player", follow)
		add_child(june)
		june.position = pos
		if not follow and june.has_method("sit"):
			june.call("sit")
	else:
		var h := Humanoid.new()
		h.setup({"female": true, "height": 1.58, "coat": true, "coat_color": Color(0.3, 0.2, 0.25), "hair_style": "long", "hair": Color(0.2, 0.12, 0.08)})
		june = Node3D.new()
		june.add_child(h)
		add_child(june)
		june.position = pos
		if not follow:
			h.pose = "sit"

func _reunion(_p) -> void:
	if Game.has_flag("found_june"):
		return
	Game.set_flag("found_june")
	lock_player(true)
	if is_instance_valid(june) and june.has_method("look_at_player"):
		june.call("look_at_player")
	Sfx.music("music_safe")
	await say([["JUNE", "...Dad?"],
		["ELIAS", "June. Hey. Hey, I've got you. I've got you."],
		["JUNE", "You're late."],
		["ELIAS", "I know."],
		["JUNE", "Three years, Dad. Three Christmases. And you pick tonight to drive up?"],
		["ELIAS", "I'm sorry. I'm so sorry. I should have come for every one of them."],
		["JUNE", "I almost didn't pick up. When you called on the radio. I almost didn't."],
		["JUNE", "...I'm glad I did."],
		["ELIAS", "Can you walk?"],
		["JUNE", "My feet are gone. I'll walk anyway. Don't carry me, I'm not five."],
		["ELIAS", "Where's your grandmother, June?"],
		["JUNE", "Gran went deeper. She heard Grandpa in the hum, and she went down the brine shaft."],
		["JUNE", "She's not Gran anymore, Dad. She's singing."]])
	if is_instance_valid(june):
		june.set("follow_player", true)
		if june.has_method("stand"):
			june.call("stand")
	lock_player(false)
	Game.set_objective("Take June down the brine shaft.")
	Sfx.music("music_tension")

func _build_shaft() -> void:
	var y := LY
	tunnel(Vector2(120, 0), Vector2(132, 0), 3.6, 3.8, y, [], [])
	for x in [123.0, 127.0, 130.5]:
		timber_set(Vector3(x, y, 0), true, 3.6, 3.1)
	rails(Vector3(120.0, y, 0.0), Vector3(132.0, y, 0.0), 0.85)
	rime_run(Vector3(120.5, y + 0.1, -1.6), Vector3(131.5, y + 0.1, -1.6), Vector3(0, 0.6, 1), 12, 0.6, 2.4, 3)
	rime_run(Vector3(120.5, y + 0.1, 1.6), Vector3(131.5, y + 0.1, 1.6), Vector3(0, 0.6, -1), 12, 0.6, 2.4, 3)
	work_light(Vector3(125.0, y + 2.6, 0.0), true, Color(0.5, 0.85, 1.0), 1.6, true)
	body_in_rock(Vector3(123.5, y, -1.3), 0.0, Vector3(0, 0, -1))
	body_in_rock(Vector3(128.5, y, 1.3), 3.3, Vector3(0, 0, 1))
	# the brine shaft room
	cave(132, -7, 144, 7, 5.5, y, {"w": [[7.0, 3.6, 3.4]]}, "rock_wet")
	# the shaft: a ring collar with a steel ladder going down, huge rime-wrapped pipe
	Props.cyl(geo, 2.4, 0.5, Vector3(138.0, y + 0.25, -1.5), Mats.get_mat("concrete", 2.0), false)
	Props.cyl(geo, 1.9, 0.3, Vector3(138.0, y + 0.45, -1.5), Mats.color(Color(0.01, 0.01, 0.015), 1.0), false)
	Props.cyl(geo, 0.7, 6.0, Vector3(138.0, y + 3.0, -1.5), Mats.get_mat("metal_painted", 2.0), false)
	rime(Vector3(138.0, y + 0.5, -1.5), Vector3.UP, 20, 1.2, true)
	rime(Vector3(139.5, y + 0.5, -0.2), Vector3.UP, 12, 0.9, true)
	rime_run(Vector3(137.4, y + 1.0, -1.5), Vector3(138.6, y + 5.0, -1.5), Vector3(0, 0, 1), 8, 0.6, 0.0)
	light(Vector3(138.0, y + 0.2, -1.5), Color(0.3, 0.8, 1.0), 4.0, 11.0, true)
	light(Vector3(138.0, y + 4.5, -1.5), Color(1.0, 0.45, 0.15), 1.2, 7.0, false)
	for i in 6:
		icicle(Vector3(rk(133, 143), y + 5.3, rk(-6, 6)), rk(0.6, 1.5))
	# the exit door: down the brine shaft access to the heart
	door("mn_exit", Vector3(143.8, y, 3.5), -PI * 0.5, {"width": 1.8, "height": 2.4, "mat": "metal", "double": true,
		"to_level": "l6_heart", "to_spawn": "start", "lock_flag": "found_june",
		"locked_msg": "You are not leaving without June.", "prompt": "Go down the brine shaft"})
	Props.sign(geo, Vector3(143.6, y + 2.8, 3.5), -PI * 0.5, "BRINE SHAFT ACCESS\nLEVEL 6 - AUTHORISED ONLY", 28, Color(0.5, 0.85, 1.0))
	Props.pipe(geo, Vector3(133.0, y + 0.5, 6.4), Vector3(143.5, y + 0.5, 6.4), 0.25, "metal_painted")
	Props.pipe(geo, Vector3(133.0, y + 1.2, 6.4), Vector3(143.5, y + 1.2, 6.4), 0.18, "metal_rust")
	Props.barrel(geo, Vector3(133.8, y, -6.0))
	Props.crate(geo, Vector3(133.6, y, 5.5), 0.3, 0.9)
	# RUTH calls up the shaft
	trigger("mn_shaft_voice", Vector3(136.0, y + 1.2, 0), Vector3(1.2, 2.6, 6.0), func(_p):
		lock_player(true)
		_hum_beat()
		_blink()
		await get_tree().create_timer(0.6).timeout
		await say([["RUTH", "Eli... come down. It's warm down here. Your father's here."],
			["JUNE", "Don't. Dad, don't answer her. That's what she does."],
			["ELIAS", "...Mom. I'm coming. But not to stay."]])
		lock_player(false)
		Game.set_objective("Go through the brine shaft access door with June."))
	pickup("mn_sh_gel", "gel", 1, Vector3(134.0, y + 0.92, 5.5))

# =================================================================== enemies / beats
func _build_enemies() -> void:
	var y := LY
	# pipeline tunnel
	enemy("mn_z1", "zombie", Vector3(5.0, 0.05, -1.0), 0.8, {"variant": "miner", "sleeping": true})
	enemy("mn_z2", "zombie", Vector3(13.0, 0.05, 0.9), 1.5, {"variant": "miner", "crawler": true})
	enemy("mn_h1", "hanger", Vector3(21.0, 3.3, 0.0), 0.0, {"on_ceiling": true})
	# pump station
	enemy("mn_z3", "zombie", Vector3(6.0, 0.05, -24.5), 0.0, {"variant": "miner", "dormant": true})
	enemy("mn_z4", "zombie", Vector3(15.0, 0.05, -22.5), 1.0, {"variant": "miner", "dormant": true})
	enemy("mn_hk1", "husk", Vector3(11.0, 0.05, -29.0), 0.0, {"dormant": true})
	enemy("mn_s1", "siren", Vector3(2.5, 0.05, -30.0), 0.0, {})
	enemy("mn_h2", "hanger", Vector3(12.0, 4.9, -24.0), 0.0, {"on_ceiling": true})
	# south drift
	enemy("mn_b1", "burster", Vector3(17.0, 0.05, 8.5), PI, {})
	enemy("mn_z5", "zombie", Vector3(14.0, 0.05, 26.0), 0.0, {"variant": "miner", "dormant": true})
	enemy("mn_z6", "zombie", Vector3(22.0, 0.05, 19.5), 2.0, {"variant": "miner", "crawler": true})
	# lower level
	enemy("mn_z7", "zombie", Vector3(73.0, y + 0.05, -0.5), 1.5, {"variant": "miner"})
	enemy("mn_hk2", "husk", Vector3(80.0, y + 0.05, 0.5), 1.5, {"dormant": true})
	enemy("mn_z8", "zombie", Vector3(74.0, y + 0.05, 10.6), 0.0, {"variant": "miner", "sleeping": true})

func on_pickup(item: String, _uid: String) -> void:
	if item == "lamp_battery":
		Game.set_objective("Take the battery to the charger in the lamp room.")
		_hum_beat()
	elif item == "hoist_lever":
		_hum_beat()
		_blink()
		for e in get_tree().get_nodes_in_group("enemy"):
			if is_instance_valid(e) and e.has_method("wake") and e.get("dormant") == true and e.global_position.z > 14.0 and e.global_position.x < 30.0:
				e.wake()
		if Game.has_flag("mine_power"):
			Game.set_objective("Fit the brake lever at the hoist station.")
		else:
			Game.set_objective("Find a lamp battery in the north pump station.")
	elif item == "dynamite":
		Game.set_objective("Lure the Hauler near the marked pillar in the cavern.")

func _build_hallucinations() -> void:
	# the hum rises in the tunnel
	trigger("mn_hum1", Vector3(5.5, 1.2, 0), Vector3(1.4, 2.4, 3.4), func(_p):
		_hum_beat()
		await get_tree().create_timer(0.4).timeout
		await say([["ELIAS", "There's a hum in the rock. Felt more than heard. Like standing under a transmission line in the rain."]]))
	# a figure at the end of the pump adit
	trigger("mn_tom_fig1", Vector3(9.0, 1.2, -4.0), Vector3(2.6, 2.4, 1.4), func(_p):
		_spawn_ghost(Vector3(9.0, 0.0, -17.2), 0.0, "Hold the lamp for me, Eli."))
	# a figure in the south drift
	trigger("mn_tom_fig2", Vector3(17.0, 1.2, 4.0), Vector3(2.6, 2.4, 1.4), func(_p):
		_spawn_ghost(Vector3(17.0, 0.0, 15.2), PI, "Eli. Hand me the bolter."))
	# the hall after power: Tom at the far end of the hall under the sheave
	trigger("mn_tom_fig3", Vector3(30.0, 1.2, 0), Vector3(1.4, 2.4, 3.0), func(_p):
		if Game.has_flag("mine_power") and not Game.has_flag("foreman_dead"):
			_spawn_ghost(Vector3(46.0, 0.0, 7.0), PI, "It's not the light he follows, Eli. It's you."))
	# a figure in the lower haulage tunnel
	trigger("mn_tom_fig4", Vector3(69.5, LY + 1.2, 0), Vector3(1.4, 2.4, 3.0), func(_p):
		_spawn_ghost(Vector3(83.0, LY, 0.0), PI * 0.5, "Mind the roof."))

func _make_tom() -> Node3D:
	var root := Node3D.new()
	var h := Humanoid.new()
	h.setup({"height": 1.78, "shirt": Color(0.3, 0.26, 0.17), "pants": Color(0.2, 0.2, 0.22), "skin": Color(0.55, 0.7, 0.74), "coat": true, "coat_color": Color(0.25, 0.22, 0.14), "gloves": true})
	root.add_child(h)
	var hat := Props.sphere(root, 0.14, Vector3(0, 1.82, 0), Mats.color(Color(0.9, 0.75, 0.12), 0.5), Vector3(1, 0.7, 1.1))
	var lamp := Props.sphere(root, 0.04, Vector3(0, 1.84, 0.15), Mats.emissive(Color(1.0, 0.95, 0.8), 4.0))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.9, 0.7)
	l.light_energy = 0.8
	l.omni_range = 3.0
	l.shadow_enabled = false
	l.position = Vector3(0, 1.85, 0.4)
	root.add_child(l)
	return root

func _spawn_ghost(pos: Vector3, yaw: float, line: String) -> void:
	var g := _make_tom()
	g.position = pos
	g.rotation.y = yaw
	add_child(g)
	_ghosts.append({"node": g, "line": line, "t": 0.0})
	_hum_beat()

func _update_ghosts() -> void:
	if _ghosts.is_empty() or player == null or not is_instance_valid(player):
		return
	var fwd: Vector3 = -player.cam.global_transform.basis.z
	for i in range(_ghosts.size() - 1, -1, -1):
		var gd: Dictionary = _ghosts[i]
		var g: Node3D = gd.node
		if not is_instance_valid(g):
			_ghosts.remove_at(i)
			continue
		gd.t += get_process_delta_time()
		var to: Vector3 = g.global_position + Vector3(0, 1.4, 0) - player.cam.global_position
		var dist: float = to.length()
		var ang := rad_to_deg(fwd.angle_to(to.normalized()))
		var lit: bool = player.flashlight != null and player.flashlight.visible and ang < 18.0 and dist < 22.0
		if (lit and gd.t > 0.4) or dist < 3.2 or gd.t > 40.0:
			_vanish_ghost(g, gd.line, dist < 12.0)
			_ghosts.remove_at(i)

func _vanish_ghost(g: Node3D, line: String, speak: bool) -> void:
	Sfx.play("hum", -4.0, 0.8)
	var tw := create_tween()
	tw.tween_property(g, "scale", Vector3(0.01, 1.6, 0.01), 0.18)
	tw.tween_callback(g.queue_free)
	if speak and line != "":
		await get_tree().create_timer(0.5).timeout
		await say([["TOM?", line]])
		await get_tree().create_timer(0.2).timeout

# =================================================================== boss: THE HAULER
func _hauler_start() -> void:
	if Game.has_flag("hauler_dead") or Game.has_flag("mn_hauler_started"):
		return
	Game.set_flag("mn_hauler_started")
	Sfx.music("music_boss")
	lock_player(true)
	await say([["ELIAS", "Jesus. That's a haul truck. Those are... those were the night shift. They're all part of it."],
		["ELIAS", "Dad's old drift. The marked pillar. If I can get it under the roof... I have two sticks of gel, and the thing is the size of a house."]])
	lock_player(false)
	if is_instance_valid(hauler):
		if hauler.has_method("wake"):
			hauler.call("wake")
		hauler.set("dormant", false)
		Game.set_objective("Survive the Hauler. Plant the blasting charges on the red-marked pillar when it is near.")
		# adds: crawlers pulled out of the rock
		enemy("mn_z9", "zombie", Vector3(100.0, LY + 0.05, 12.0), 3.0, {"variant": "miner", "crawler": true})
		enemy("mn_z10", "zombie", Vector3(98.0, LY + 0.05, -12.0), 0.0, {"variant": "miner", "crawler": true})
	else:
		# fallback if the boss type is missing: don't block the level
		await get_tree().create_timer(1.0).timeout
		_on_hauler_died(null)

func _plant_charges(_p) -> void:
	if _plant_busy or Game.has_flag("hauler_dead"):
		UI.toast("The pillar is cracked and cribbed with timber. A good charge would bring the roof down.")
		return
	if not Game.has_item("dynamite"):
		UI.toast("This pillar is cracked through and marked with red tape. A charge here could bring the roof down.")
		return
	if not is_instance_valid(hauler) or hauler.get("state") == "dead":
		UI.toast("Not yet. Lure the Hauler close to the pillar first.")
		return
	var wp := Vector3(106.0, LY, -4.0)
	if hauler.global_position.distance_to(wp) > 14.0:
		UI.toast("The Hauler is too far from the pillar. Draw it closer.")
		Sfx.play("deny")
		return
	_plant_busy = true
	Game.remove_item("dynamite", 1)
	Sfx.play("pickup")
	UI.toast("Charges planted. Fuse burning - RUN.", 3.5)
	Props.box(geo, Vector3(0.12, 0.4, 0.12), wp + Vector3(0, 1.0, 1.15), Mats.color(Color(0.8, 0.2, 0.15), 0.6), false)
	var fl := light(wp + Vector3(0, 1.3, 1.3), Color(1.0, 0.5, 0.2), 2.0, 5.0, false, true)
	await get_tree().create_timer(4.5).timeout
	fl.queue_free()
	_collapse_pillar(wp)

func _collapse_pillar(wp: Vector3) -> void:
	FX.explosion(self, wp + Vector3(0, 1.0, 0), 7.0, 80.0)
	if player:
		player.shake = 1.0
	Sfx.play("explosion", 3.0)
	if is_instance_valid(_pillar):
		_pillar.visible = false
		for sb in _pillar.find_children("*", "StaticBody3D", true, false):
			sb.collision_layer = 0
	# falling rocks
	for i in 14:
		var r := Props.box(self, Vector3(rk(0.8, 2.2), rk(0.6, 1.6), rk(0.8, 2.2)), wp + Vector3(rk(-3, 3), 11.0, rk(-3, 3)), _rmat("rock"), false, Vector3(rk(0, 3), rk(0, 3), rk(0, 3)))
		var tw := create_tween()
		tw.tween_interval(rk(0.0, 0.5))
		tw.tween_property(r, "position:y", LY + rk(0.3, 1.2), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(0.5).timeout
	if is_instance_valid(hauler) and hauler.get("state") != "dead":
		var d := hauler.global_position.distance_to(wp)
		var dmg := 650.0 if d < 12.0 else 220.0
		hauler.call("take_hit", dmg, hauler.global_position + Vector3(0, 3, 0), Vector3.DOWN, true)
		if hauler.has_method("stagger"):
			hauler.call("stagger")
	for i in 7:
		Props.box(geo, Vector3(rk(1.0, 2.4), rk(0.8, 2.0), rk(1.0, 2.4)), wp + Vector3(rk(-2.5, 2.5), 0.5, rk(-2.5, 2.5)), _rmat("rock_wet"), false, Vector3(rk(-0.3, 0.3), rk(0, 3), rk(-0.3, 0.3)))
	_plant_busy = false

func _on_hauler_died(_e) -> void:
	if Game.has_flag("hauler_dead"):
		return
	Game.set_flag("hauler_dead")
	Sfx.music("music_tension")
	Game.set_objective("Find June. The refuge chamber is north of the cavern.")
	await get_tree().create_timer(2.0).timeout
	await say([["ELIAS", "...They finally stopped. All of them."],
		["JUNE (radio)", "Dad? I heard it stop. I'm... in the refuge. Steel door, north. The big cold room. Please hurry."],
		["ELIAS", "Hold on, June. Ninety seconds. I'm coming."]])
