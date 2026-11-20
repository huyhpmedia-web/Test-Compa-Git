extends RefCounted
## L5 - Lower Kettle Mine, round 7 (R7-C): real models for the structural kit (timber portal sets, narrow-gauge track,
## ducting), hoist-house machinery (motor, steam hammer, engine crane, cabinets), brine pumps, lamp room and the
## mine-cart / lantern / tool set dressing.  Models: assets/env/mine_sf + industrial_sf (Sketchfab CC-BY, see credits).

const Props = preload("res://world/props.gd")
const Mats = preload("res://core/mats.gd")
const R4 = preload("res://levels/dressing/l4_real.gd")
const Art = preload("res://levels/dressing/l4_art.gd")
const Gore = preload("res://world/gore.gd")

static var rng := RandomNumberGenerator.new()
static var _rust: StandardMaterial3D
static var _steel: StandardMaterial3D

static func rust() -> StandardMaterial3D:
	if _rust == null:
		_rust = Art.pbr("metal", 1.3, Color(0.52, 0.34, 0.24), 0.85, 0.8, 0.45)
	return _rust

static func steel() -> StandardMaterial3D:
	if _steel == null:
		_steel = Art.pbr("metal", 1.2, Color(0.42, 0.45, 0.5), 0.6, 0.6, 0.8)
	return _steel

static func setup(level: Node3D) -> void:
	R4.setup(level)
	rng.seed = 5505

static func _sp(rel: String, pos: Vector3, yaw := 0.0, opts := {}) -> Node3D:
	if not opts.has("range"):
		opts["range"] = 90.0
	return R4.sp(rel, pos, yaw, opts)

# ------------------------------------------------------------------ structural kit (called from l5_mine.gd helpers)
## Hewn-timber portal set spanning a tunnel (real A-frame model), c = floor point on the axis.
static func timber(c: Vector3, along_x: bool, width: float, height: float) -> bool:
	if width > 4.2:
		return false          # wide pump-cavern spans keep the log-post kit (a stretched A-frame would turn to slabs)
	var n := _sp("mine_sf/timber_beam", c, PI * 0.5 if along_x else 0.0, {"fit_box": Vector3(width - 0.3, height + 0.3, 0.34), "range": 80.0, "shadow": false, "tint": Color(1.7, 1.3, 1.0)})
	return n != null

## Narrow-gauge track as 4 m rail sections laid along a->b (long axis X of the model, yaw aligns it).
static func rails(a: Vector3, b: Vector3, gauge: float) -> bool:
	var d := b - a
	var L := d.length()
	if L < 0.5 or not R4.Env.has("mine_sf/rail_4m"):
		return false
	var dir := d / L
	var yaw := atan2(-dir.z, dir.x)
	var n := int(ceil(L / 4.0))
	var seg := L / float(n)
	for i in n:
		var p := a + dir * (seg * (i + 0.5))
		_sp("mine_sf/rail_4m", p, yaw, {"fit_box": Vector3(seg + 0.02, 0.32, gauge + 0.55), "range": 70.0, "shadow": false})
	return true

## Rectangular sheet-metal ducting with flange collars (PBR, no more flat boxes).
static func duct(a: Vector3, b: Vector3, size: float) -> void:
	var d := b - a
	var L := d.length()
	var dir := d / L
	var m := Art.pbr("metal", 1.1, Color(0.55, 0.58, 0.62), 0.6, 0.6, 0.75)
	var fl := rust()
	var basis := Basis.looking_at(dir, Vector3.UP) if absf(dir.y) < 0.99 else Basis()
	var mid := (a + b) * 0.5
	var mi := Props.box(R4.geo, Vector3(size, size, L), mid, m, false)
	mi.basis = basis
	var n := int(L / 2.0)
	for i in range(0, n + 1):
		var p := a.lerp(b, float(i) / float(maxi(n, 1)))
		var f := Props.box(R4.geo, Vector3(size + 0.1, size + 0.1, 0.08), p, fl, false)
		f.basis = basis

# ------------------------------------------------------------------ pump station
static func pump(px: float, pz: float) -> void:
	# rusty pump tank + motor on a plinth; the old collider cylinder stays in the level
	_sp("industrial_sf/storage_tank", Vector3(px, 0.0, pz), rng.randf() * 6.0, {"scale": 0.72, "collide": "none"})
	_sp("mine_sf/motor", Vector3(px + 1.35, 0.0, pz + 0.2), PI * 0.5, {"scale": 1.15, "collide": Vector3(1.4, 1.3, 1.0)})
	_sp("industrial_sf/valve_wheel", Vector3(px - 0.9, 1.5, pz + 0.9), rng.randf() * 3.0, {"scale": 1.3})

# ------------------------------------------------------------------ hoist house
static func hoist_hall() -> void:
	# winding motor + control gear behind the drum
	_sp("mine_sf/motor", Vector3(45.7, 0.0, -8.6), -PI * 0.5, {"scale": 2.1, "collide": Vector3(3.0, 2.2, 2.0)})
	_sp("mine_sf/motor", Vector3(45.7, 0.0, -5.6), -PI * 0.5 + 0.2, {"scale": 1.4, "collide": "none"})
	for k in 2:
		_sp("industrial_sf/control_cabinet", Vector3(47.2, 0.0, -9.0 + k * 1.1), -PI * 0.5, {"collide": Vector3(0.9, 1.9, 0.9), "tint": Color(0.72, 0.7, 0.62)})
	R4.solid(Vector3(45.6, 1.2, -8.2), Vector3(3.6, 2.4, 3.0))
	# heavy machinery set dressing in the hall
	_sp("mine_sf/steam_hammer", Vector3(46.4, 0.0, 1.2), -PI * 0.5, {"collide": Vector3(1.0, 3.0, 2.4), "tint": Color(0.85, 0.82, 0.8)})
	_sp("mine_sf/engine_crane", Vector3(31.8, 0.0, 6.4), 0.5, {"collide": Vector3(1.4, 2.0, 1.4), "tint": Color(0.85, 0.8, 0.7)})
	_sp("mine_sf/old_machinery", Vector3(27.8, 0.0, 6.2), PI * 0.5, {"scale": 0.9, "collide": Vector3(1.8, 2.0, 2.2), "tint": Color(0.8, 0.78, 0.76)})
	_sp("mine_sf/mine_cart", Vector3(34.0, 0.0, 8.2), PI * 0.5 + 0.3, {"collide": Vector3(1.2, 0.9, 1.9)})
	_sp("mine_sf/pickaxe", Vector3(41.6, 0.9, 6.6), 0.4, {"rot": Vector3(PI * 0.5, 0, 0), "range": 40.0})
	_sp("mine_sf/shovel", Vector3(40.8, 0.05, 8.4), 0.9, {"rot": Vector3(PI * 0.5, 0, 0), "range": 40.0})
	_sp("mine_sf/sledge", Vector3(32.4, 0.05, -6.2), 2.0, {"rot": Vector3(PI * 0.5, 0, 0), "range": 40.0})
	_sp("industrial_sf/exhaust_fan", Vector3(47.8, 6.0, 4.0), -PI * 0.5, {"scale": 2.4, "range": 80.0})
	_sp("industrial_sf/welder", Vector3(43.4, 0.0, 9.0), PI, {"collide": Vector3(1.0, 0.9, 1.7)})
	# motivated lighting: caged work lamps on cables over the machinery, a sodium flood from the headframe
	for lp in [Vector3(44.0, 5.0, -4.0), Vector3(45.0, 4.2, 2.0), Vector3(31.0, 4.5, 5.5), Vector3(40.5, 3.6, -2.0), Vector3(36.5, 6.5, -4.0)]:
		_sp("mine/hanging_lamp", lp + Vector3(0, 0.0, 0), rng.randf() * 6.0, {"scale": 0.9, "emissive": {"hanging_industrial_lamp_glass": [Color(1.0, 0.8, 0.5), 3.5]}, "range": 80.0})
		R4.omni(lp + Vector3(0, -0.9, 0), Color(1.0, 0.72, 0.4), 3.2, 11.0, lp.x > 40.0 and lp.z < 0.0)
	var fl := SpotLight3D.new()
	fl.light_color = Color(1.0, 0.7, 0.35)
	fl.light_energy = 9.0
	fl.spot_range = 24.0
	fl.spot_angle = 48.0
	fl.shadow_enabled = false
	fl.position = Vector3(30.0, 7.8, 8.0)
	R4.host.add_child(fl)
	fl.look_at_from_position(Vector3(30.0, 7.8, 8.0), Vector3(42.0, 0.5, -2.0))
	# lantern on the brake desk
	_sp("mine_sf/lantern", Vector3(41.2, 1.18, -2.3), 0.5, {"range": 40.0})
	# steel pipework off the drum to the sheave
	R4.pipe(Vector3(43.2, 3.4, 8.8), Vector3(43.2, 7.8, 8.8), 0.12, Color(0.5, 0.5, 0.55))

static func lamp_room() -> void:
	_sp("industrial_sf/lockers", Vector3(42.6, 0, -15.6), -PI * 0.5, {"collide": Vector3(0.55, 2.0, 2.2)})
	_sp("interior/desk", Vector3(32.0, 0, -12.2), PI * 0.5, {"collide": Vector3(0.9, 0.8, 1.7), "scale": 0.7})
	_sp("mine_sf/lantern", Vector3(40.6, 0.82, -17.4), 0.0, {"range": 40.0})
	_sp("mine_sf/lantern", Vector3(31.6, 0.0, -17.3), 1.0, {"range": 40.0})

## The coal furnace body: stove model + brick surround (collider and interactable stay in l5_mine.gd).
static func furnace(f: Vector3) -> void:
	_sp("camp/barrel_stove", f + Vector3(0, 0, 0.1), 0.0, {"scale": 2.0, "collide": "none", "emissive": {}})
	_sp("industrial_sf/pipe_pack", f + Vector3(0.0, 2.6, -0.3), 0.0, {"scale": 0.55, "range": 60.0})

# ------------------------------------------------------------------ tunnels
static func tunnel_set() -> void:
	# the warm heat loop: insulated PBR pipe, flange glow stays in the level; valve wheels + manifold taps
	R4.pipe(Vector3(0.1, 2.85, -1.42), Vector3(26.0, 2.85, -1.42), 0.3, Color(0.6, 0.62, 0.66), true)
	for x in [6.0, 12.5, 19.0]:
		_sp("industrial_sf/valve_wheel", Vector3(x, 2.25, -1.6), 0.0, {"scale": 1.1, "range": 60.0})
	_sp("industrial_sf/pipe_manifold", Vector3(15.5, 0.0, -1.2), 0.0, {"scale": 0.55, "range": 60.0})
	# derailed cart with its own track stub, lanterns hung from the portal sets, tools in the dirt
	_sp("mine_sf/mine_cart", Vector3(23.0, 0.0, -0.9), 3.4, {"collide": "none", "range": 70.0})
	for x in [3.0, 12.0, 20.0]:
		_sp("mine_sf/lantern", Vector3(x, 2.25, 1.55), rng.randf() * 6.0, {"scale": 1.0, "range": 40.0, "snow": 0.0})
	_sp("mine_sf/pickaxe", Vector3(8.6, 0.05, -1.3), 0.7, {"rot": Vector3(PI * 0.5, 0, 0), "range": 40.0})

static func haulage_set(y: float) -> void:
	_sp("mine_sf/mine_cart", Vector3(74.5, y, -0.7), PI * 0.5 + 0.1, {"collide": "none", "range": 70.0})
	_sp("mine_sf/lantern", Vector3(72.0, y + 2.3, 1.6), 0.3, {"range": 40.0})
	_sp("mine_sf/lantern", Vector3(80.0, y + 2.3, -1.6), 1.6, {"range": 40.0})
	_sp("industrial_sf/pallets", Vector3(78.5, y, 5.8), 0.6, {"scale": 0.9, "range": 60.0})
	_sp("industrial_sf/warehouse_shelf", Vector3(76.0, y, 11.2), PI, {"collide": Vector3(3.2, 2.5, 0.7), "range": 60.0})

static func cavern_set(y: float) -> void:
	_sp("industrial_sf/diesel_gen", Vector3(88.0, y, 12.0), -PI * 0.5, {"scale": 1.4, "collide": Vector3(1.6, 1.6, 2.6), "range": 80.0})
	_sp("mine_sf/mine_cart", Vector3(95.0, y, 14.0), 2.0, {"collide": "none", "range": 80.0})
	_sp("mine_sf/lantern", Vector3(106.0, y, 0.0), 0.0, {"scale": 1.0, "range": 40.0})

## Grime decals: water streaks down the rock, rust + ore dust stains, oil under the machinery.
static func grime() -> void:
	Gore.steam_vent(R4.host, Vector3(43.2, 7.6, 8.8), Vector3(0, 1, 0.2), 0.9, 0.16)
	Gore.steam_vent(R4.host, Vector3(46.0, 1.3, -6.4), Vector3.UP, 0.7, 0.12)
	Gore.drip_emitter(R4.host, Vector3(33.0, 8.4, 2.0), "melt", 1.8)
	Gore.drip_emitter(R4.host, Vector3(41.0, 8.4, -6.0), "melt", 2.2)
	Gore.steam_vent(R4.host, Vector3(9.0, 0.5, -27.8), Vector3.UP, 0.8, 0.12)
	var r := rng
	# pipeline tunnel (x 1..25, walls at z = -1.8 / +1.8)
	for i in 9:
		var x := 2.0 + i * 2.8 + r.randf_range(-0.8, 0.8)
		R4.decal("streak", Vector3(x, 1.7, 1.82), Vector3(0, 0, -1), Vector2(r.randf_range(1.2, 2.4), 3.0), Color(0.03, 0.035, 0.04), r.randf_range(0.5, 0.85))
		R4.decal("streak", Vector3(x + 1.2, 1.7, -1.82), Vector3(0, 0, 1), Vector2(r.randf_range(1.2, 2.4), 3.0), Color(0.04, 0.035, 0.03), r.randf_range(0.5, 0.85))
	for x in [4.0, 10.0, 17.0, 23.0]:
		R4.decal("oil", Vector3(x, 0.04, r.randf_range(-0.9, 0.9)), Vector3.UP, Vector2(r.randf_range(1.2, 2.4), r.randf_range(1.0, 1.8)), Color(0.02, 0.025, 0.03), 0.8, 0.6)
	# hoist hall: concrete walls (x=26 west, x=48 east, z=-10 north, z=+10 south)
	for i in 8:
		var z := -8.0 + i * 2.4
		R4.decal("streak", Vector3(47.9, 4.8, z), Vector3(-1, 0, 0), Vector2(r.randf_range(1.8, 3.0), 7.0), Color(0.05, 0.04, 0.035), r.randf_range(0.5, 0.85))
		R4.decal("streak", Vector3(26.2, 4.8, z), Vector3(1, 0, 0), Vector2(r.randf_range(1.8, 3.0), 7.0), Color(0.05, 0.04, 0.035), r.randf_range(0.4, 0.8))
	for i in 8:
		var x2 := 28.0 + i * 2.6
		R4.decal("streak", Vector3(x2, 4.8, 9.9), Vector3(0, 0, -1), Vector2(r.randf_range(1.8, 3.0), 7.0), Color(0.05, 0.04, 0.035), r.randf_range(0.4, 0.8))
	for p in [Vector3(44.0, 0.04, -4.0), Vector3(46.0, 0.04, 1.2), Vector3(32.0, 0.04, 6.0), Vector3(39.0, 0.04, -1.0)]:
		R4.decal("oil", p, Vector3.UP, Vector2(r.randf_range(1.6, 3.2), r.randf_range(1.4, 2.6)), Color(0.02, 0.02, 0.025), 0.85, 0.6)
	# pump cavern
	for x in range(2, 19, 3):
		R4.decal("streak", Vector3(x, 2.5, -31.9), Vector3(0, 0, 1), Vector2(r.randf_range(1.6, 3.0), 5.0), Color(0.03, 0.04, 0.045), r.randf_range(0.5, 0.9))
	for px in [4.0, 9.5, 15.0]:
		R4.decal("stain", Vector3(px, 0.04, -27.0), Vector3.UP, Vector2(3.4, 3.0), Color(0.18, 0.1, 0.06), 0.7, 0.6)
