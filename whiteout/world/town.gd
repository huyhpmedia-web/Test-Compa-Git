extends RefCounted
## Photoreal town buildings (Sketchfab CC-BY, assets/env/town_sf/*.glb, built by tools/town/build_town_sf.py).
## Real-world metres, base at y=0, footprint centred on x/z, front = +Z. Credits: assets/CREDITS_SKETCHFAB.json.
##
##   Town.building(parent, "house_colonial", Vector3(10, 0, -20), PI * 0.5, {collide = true})
##
## opts: collide (default true), tint (Color), snow (0..1 roof/ground cover, default 0.7), range (visibility end, 0 = always),
##       scale (float), shadow (bool, default true when range <= 90 or 0),
##       lit (0..1: share of front windows glowing; most steady lamps, some TV-blue / failing bulbs; lit houses may get a porch
##            light and Christmas lights), power_flag (String: windows stay dark until Game flag is set, then switch on one by one),
##       porch (0..1 chance of a porch light on a lit house, default 0.55), xmas (0..1 chance of Christmas lights, default 0.3)
## Returns the Node3D (or null when the glb is missing, so callers can fall back).

const Env = preload("res://world/env_assets.gd")
const TW = preload("res://world/town_windows.gd")
const WIN_SHADER := "res://world/shaders/town_window.gdshader"
const MAX_PORCH_OMNI := 10
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
static var _win_mat: ShaderMaterial
static var _quad: QuadMesh
static var _bulb_mat: StandardMaterial3D
static var _xmas_mat: ShaderMaterial
static var _spill: Texture2D

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
	var lit: float = float(opts.get("lit", 0.0))
	if lit > 0.0:
		_light_up(root, name, lit, opts)
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

# ------------------------------------------------------------------ lit windows / porch lights / Christmas lights
static func _level_root(n: Node) -> Node:
	var r := n
	while r.get_parent() != null and not r.has_method("build") and not (r.get_parent() is Window):
		r = r.get_parent()
	return r

## The TownPower watcher of the level that owns `parent` (created on first use).
static func _power(parent: Node, flag: String) -> Node:
	var lr := _level_root(parent)
	var key := "town_power_" + flag
	if lr.has_meta(key) and is_instance_valid(lr.get_meta(key)):
		return lr.get_meta(key)
	var tp: Node = load("res://world/town_power.gd").new()
	tp.name = "TownPower_" + flag
	tp.flag = flag
	lr.add_child(tp)
	lr.set_meta(key, tp)
	return tp

static func _light_up(root: Node3D, name: String, lit: float, opts: Dictionary) -> void:
	var wins: Array = TW.WIN.get(name, [])
	if wins.is_empty():
		return
	if _win_mat == null:
		_win_mat = ShaderMaterial.new()
		_win_mat.shader = load(WIN_SHADER)
		_quad = QuadMesh.new()
		_bulb_mat = StandardMaterial3D.new()
		_bulb_mat.albedo_color = Color(1.0, 0.85, 0.6)
		_bulb_mat.emission_enabled = true
		_bulb_mat.emission = Color(1.0, 0.78, 0.5)
		_bulb_mat.emission_energy_multiplier = 6.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(root.position.round())) ^ hash(name)
	var flag: String = String(opts.get("power_flag", ""))
	var powered := flag == "" or Game.has_flag(flag)
	var shop := name.begins_with("shop")
	var rng_end: float = float(opts.get("range", 0.0))
	var cards: Array = []
	var lights: Array = []
	# a lit house has one or two "occupied" rooms: neighbouring windows share the same lamp colour
	var warm := [Color(1.0, 0.6, 0.28), Color(1.0, 0.68, 0.4), Color(1.0, 0.52, 0.22), Color(0.98, 0.74, 0.5)]
	var house_col: Color = warm[rng.randi() % warm.size()]
	for w in wins:
		if rng.randf() > lit:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "LitWindow"
		mi.mesh = _quad
		mi.material_override = _win_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(w[0], w[1], float(w[2]) + 0.012)
		mi.scale = Vector3(float(w[3]) * 0.97, float(w[4]) * 0.97, 1.0)
		if rng_end > 0.0:
			mi.visibility_range_end = rng_end
		root.add_child(mi)
		var mode := 0.0
		var col := house_col
		var e := rng.randf_range(1.5, 2.6)
		var r := rng.randf()
		if shop and float(w[1]) < 3.2:
			mode = 3.0
			col = Color(0.85, 0.92, 1.0) if r < 0.6 else Color(1.0, 0.85, 0.6)
			e = rng.randf_range(1.2, 1.9)
		elif r < 0.13:
			mode = 1.0
			e = 1.6
		elif r < 0.2:
			mode = 2.0
		elif r < 0.3:
			e *= 0.4      # a lamp left on in a back room
		elif r < 0.36:
			col = Color(0.8, 0.9, 1.0)   # kitchen strip light
			e *= 0.8
		mi.set_instance_shader_parameter("win_col", col)
		mi.set_instance_shader_parameter("win_energy", e)
		mi.set_instance_shader_parameter("win_mode", mode)
		mi.set_instance_shader_parameter("win_seed", rng.randf() * 100.0)
		mi.set_instance_shader_parameter("win_size", Vector2(w[3], w[4]))
		mi.set_instance_shader_parameter("win_power", 1.0 if powered else 0.0)
		cards.append(mi)
		# warm light thrown onto the snow under a lit ground-floor window (emissive decal, no light cost)
		if float(w[1]) < 3.2 and mode != 1.0:
			if _spill == null and ResourceLoader.exists("res://textures/town_decals/spill_a.png"):
				_spill = load("res://textures/town_decals/spill_a.png")
			if _spill != null:
				var dc := Decal.new()
				dc.name = "WindowSpill"
				var L: float = 2.2 + float(w[1]) * 0.6
				dc.size = Vector3(float(w[3]) * 2.2, 3.0, L)
				dc.position = Vector3(w[0], 0.0, float(w[2]) + L * 0.5)
				dc.texture_albedo = _spill
				dc.texture_emission = _spill
				dc.albedo_mix = 0.0
				dc.emission_energy = e * 0.35
				dc.modulate = col
				dc.normal_fade = 0.6
				dc.upper_fade = 0.1
				dc.lower_fade = 0.1
				dc.cull_mask = 1
				dc.distance_fade_enabled = true
				dc.distance_fade_begin = 70.0
				dc.distance_fade_length = 20.0
				root.add_child(dc)
				lights.append(dc)
	if cards.is_empty():
		return
	var door: Array = TW.DOOR.get(name, [])
	var lr := _level_root(root)
	if not door.is_empty() and rng.randf() < float(opts.get("porch", 0.55)):
		var px: float = float(door[0]) + (float(door[3]) * 0.5 + 0.25) * (1.0 if rng.randf() < 0.5 else -1.0)
		var bulb := MeshInstance3D.new()
		bulb.name = "PorchBulb"
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		bulb.mesh = sm
		bulb.material_override = _bulb_mat
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bulb.position = Vector3(px, float(door[1]) + 0.25, float(door[2]) + 0.12)
		root.add_child(bulb)
		var cap := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.09
		cm.height = 0.1
		cap.mesh = cm
		cap.position = bulb.position + Vector3(0, 0.09, 0)
		root.add_child(cap)
		lights.append(bulb)
		var n_omni: int = int(lr.get_meta("town_omni", 0))
		if n_omni < MAX_PORCH_OMNI:
			lr.set_meta("town_omni", n_omni + 1)
			var om := OmniLight3D.new()
			om.name = "PorchLight"
			om.light_color = Color(1.0, 0.72, 0.42)
			om.light_energy = 1.6
			om.omni_range = 7.0
			om.omni_attenuation = 1.4
			om.shadow_enabled = false
			om.light_volumetric_fog_energy = 0.6
			om.distance_fade_enabled = true
			om.distance_fade_begin = 60.0
			om.distance_fade_length = 20.0
			om.position = bulb.position + Vector3(0, -0.1, 0.35)
			root.add_child(om)
			lights.append(om)
	if not door.is_empty() and rng.randf() < float(opts.get("xmas", 0.3)):
		lights.append(_xmas(root, door, rng))
	if not powered:
		for l in lights:
			(l as Node3D).visible = false
		_power(root, flag).register(cards, lights)

## A sagging string of coloured bulbs over the door (December 21st).
static func _xmas(root: Node3D, door: Array, rng: RandomNumberGenerator) -> Node3D:
	if _xmas_mat == null:
		_xmas_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = "shader_type spatial;\nrender_mode unshaded, shadows_disabled;\nvoid fragment() {\n\tfloat f = 0.75 + 0.25 * sin(TIME * 1.3 + COLOR.a * 40.0);\n\tALBEDO = COLOR.rgb * 3.5 * f;\n}\n"
		_xmas_mat.shader = sh
	var span := float(door[3]) + rng.randf_range(2.5, 5.0)
	var x0: float = float(door[0]) - span * 0.5
	var y: float = float(door[1]) + 0.45
	var z: float = float(door[2]) + 0.1
	var n := int(span / 0.22)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var sm := SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.07
	sm.radial_segments = 6
	sm.rings = 3
	mm.mesh = sm
	mm.instance_count = n + 1
	var cols := [Color(1, 0.1, 0.08), Color(0.1, 0.9, 0.2), Color(0.15, 0.3, 1.0), Color(1.0, 0.7, 0.1), Color(1, 0.4, 0.8)]
	var sag := rng.randf_range(0.15, 0.3)
	var segs := 3
	for i in n + 1:
		var t := float(i) / float(n)
		var ts := fmod(t * segs, 1.0)
		var p := Vector3(x0 + span * t, y - sag * 4.0 * ts * (1.0 - ts), z)
		mm.set_instance_transform(i, Transform3D(Basis(), p))
		var c: Color = cols[i % cols.size()]
		if rng.randf() < 0.12:
			c = Color(0.05, 0.05, 0.05)   # dead bulbs
		c.a = rng.randf()
		mm.set_instance_color(i, c)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "XmasLights"
	mmi.multimesh = mm
	mmi.material_override = _xmas_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
	return mmi
