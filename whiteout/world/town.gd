extends RefCounted
## Photoreal town buildings (Sketchfab CC-BY, assets/env/town_sf/*.glb, built by tools/town/build_town_sf.py).
## Real-world metres, base at y=0, footprint centred on x/z, front = +Z. Credits: assets/CREDITS_SKETCHFAB.json.
##
##   Town.building(parent, "house_colonial", Vector3(10, 0, -20), PI * 0.5, {collide = true})
##
## opts: collide (default true), tint (Color), snow (0..1 roof/ground cover, default 0.7), range (visibility end, 0 = always),
##       scale (float), shadow (bool, default true when range <= 90 or 0)
## Returns the Node3D (or null when the glb is missing, so callers can fall back).

const Env = preload("res://world/env_assets.gd")
const ROOT := "res://assets/env/town_sf/"

## name -> [width (x), depth (z), height]
const SIZES := {
	"house_american": [17.15, 13.61, 7.6], "house_colonial": [15.65, 9.28, 8.4], "house_glen": [12.77, 12.87, 4.4],
	"house_porch": [9.2, 14.56, 7.4], "house_ranch": [11.8, 11.19, 4.3], "house_suburban": [18.08, 17.15, 8.2],
	"house_twostory": [9.42, 5.77, 7.8], "house_weathered": [5.48, 9.63, 8.4],
	"shop_brick": [9.86, 8.32, 8.2], "shop_gray": [8.63, 8.63, 8.6], "shop_long": [19.16, 5.73, 7.6],
	"shop_pair": [10.4, 30.66, 9.5], "block_tall": [11.77, 19.71, 13.5], "block_row": [19.86, 64.56, 15.0],
	"block_nyc": [24.38, 21.49, 11.0], "gas_station": [13.72, 15.83, 6.0], "church_small": [11.42, 12.17, 17.0],
	"warehouse_red": [24.91, 9.06, 8.0], "pole_utility": [3.02, 3.15, 10.5],
	"dumpster_a": [1.53, 1.01, 1.5], "dumpster_b": [4.24, 1.7, 1.5], "mailbox_us": [0.92, 0.63, 1.4],
}

# [name, width, depth] pools used by Town.row and the level town rows (so rows never repeat visibly)
const HOUSES := [["house_american", 17.15, 13.61], ["house_colonial", 15.65, 9.28], ["house_glen", 12.77, 12.87],
	["house_porch", 9.2, 14.56], ["house_ranch", 11.8, 11.19], ["house_suburban", 18.08, 17.15],
	["house_twostory", 9.42, 5.77], ["house_weathered", 5.48, 9.63]]
const SHOPS := [["shop_brick", 9.86, 8.32], ["shop_gray", 8.63, 8.63], ["shop_long", 19.16, 5.73],
	["shop_brick", 9.86, 8.32], ["house_twostory", 9.42, 5.77], ["house_weathered", 5.48, 9.63]]
## large / far-only masses (>= 40 m away)
const FAR := [["block_tall", 11.77, 19.71], ["warehouse_red", 24.91, 9.06], ["church_small", 11.42, 12.17],
	["gas_station", 13.72, 15.83], ["block_nyc", 24.38, 21.49]]

static var _scenes := {}

static func has(name: String) -> bool:
	return SIZES.has(name) and ResourceLoader.exists(ROOT + name + ".glb")

static func size_of(name: String) -> Vector3:
	var s: Array = SIZES.get(name, [8.0, 8.0, 6.0])
	return Vector3(s[0], s[2], s[1])

static func building(parent: Node, name: String, pos: Vector3, yaw := 0.0, opts := {}) -> Node3D:
	if not has(name):
		return null
	if not _scenes.has(name):
		_scenes[name] = load(ROOT + name + ".glb")
	var inst: Node3D = (_scenes[name] as PackedScene).instantiate()
	var root := Node3D.new()
	root.name = "Town_" + name
	root.position = pos
	root.rotation.y = yaw
	var sc: float = float(opts.get("scale", 1.0))
	root.scale = Vector3.ONE * sc
	parent.add_child(root)
	root.add_child(inst)
	var snow: float = float(opts.get("snow", 0.7))
	var tint: Color = opts.get("tint", Color.WHITE)
	var rng_end: float = float(opts.get("range", 0.0))
	var shadow: bool = bool(opts.get("shadow", rng_end <= 0.0 or rng_end <= 90.0))
	var meshes: Array = []
	Env._meshes(inst, meshes)
	for mi in meshes:
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var src: Material = m.get_active_material(s)
			var mat := Env.snowify(src, snow, tint)
			if mat != src:
				m.set_surface_override_material(s, mat)
		if not shadow:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if rng_end > 0.0:
			m.visibility_range_end = rng_end
			m.visibility_range_end_margin = rng_end * 0.08
	if bool(opts.get("collide", true)):
		var sz := size_of(name) * sc
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(sz.x * 0.92, sz.y, sz.z * 0.92)
		cs.shape = bs
		cs.position = Vector3(0, sz.y * 0.5, 0)
		body.add_child(cs)
		root.add_child(body)
	return root

## A row of buildings along x (x0..x1) whose fronts sit on z = zf, facing +z when out > 0 (else -z).
## Background rows: pass collide=false. Returns the number placed.
## opts: gap_min/gap_max, tint_var (0..1 colour variation, default 0.18), poles (bool: utility poles along the row),
##       clutter (bool: mailboxes / dumpsters between buildings, default true)
static func row(parent: Node, x0: float, x1: float, zf: float, out: float, pool: Array, seed_v: int, opts := {}) -> int:
	if not has("house_ranch"):
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var x := x0 + 0.2
	var yaw := 0.0 if out > 0.0 else PI
	var n := 0
	var gap_min: float = float(opts.get("gap_min", 0.4))
	var gap_max: float = float(opts.get("gap_max", 1.6))
	var tv: float = float(opts.get("tint_var", 0.18))
	var last := ""
	while x < x1 - 4.0 and n < 30:
		var room := x1 - x
		var fits: Array = pool.filter(func(b): return b[1] <= room + 0.3 and b[0] != last)
		if fits.is_empty():
			fits = pool.filter(func(b): return b[1] <= room + 0.3)
		if fits.is_empty():
			break
		var b: Array = fits[rng.randi() % fits.size()]
		last = b[0]
		var o := opts.duplicate()
		var g := 1.0 - rng.randf() * tv
		o["tint"] = Color(g, g * rng.randf_range(0.96, 1.0), g * rng.randf_range(0.92, 1.0))
		building(parent, b[0], Vector3(x + float(b[1]) * 0.5, 0, zf - out * float(b[2]) * 0.5), yaw + rng.randf_range(-0.04, 0.04), o)
		if bool(opts.get("clutter", true)) and rng.randf() < 0.45:
			var cx := x + float(b[1]) + rng.randf_range(0.3, 1.0)
			if cx < x1 - 1.0:
				var nm := "dumpster_a" if rng.randf() < 0.5 else "mailbox_us"
				building(parent, nm, Vector3(cx, 0, zf - out * 1.5), yaw + rng.randf_range(-0.5, 0.5), {"collide": false, "range": float(opts.get("range", 0.0)) * 0.5})
		x += float(b[1]) + rng.randf_range(gap_min, gap_max)
		n += 1
	if bool(opts.get("poles", false)):
		var px := x0 + 6.0
		while px < x1:
			building(parent, "pole_utility", Vector3(px, 0, zf - out * 1.0), 0.0, {"collide": false, "snow": 0.3, "range": 130.0})
			px += rng.randf_range(24.0, 32.0)
	return n
