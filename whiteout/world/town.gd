extends RefCounted
## Real town buildings (assets/env/town/*.glb, built by tools/town/build_town.py from 3D Jutsu meshes).
## The glbs carry category material names; this swaps them for shared PBR materials (textures/town).
##
##   Town.building(parent, "house_two_story", Vector3(10, 0, -20), PI * 0.5, {lit = 0.3, collide = true})
##
## opts: lit (0..1 chance a window material is warm-lit; default 0), collide (default true),
##       tint (Color multiplier for siding), dirt (0..1 extra darkening, default 0.15), range (visibility end, 0 = always)
## Returns the Node3D (or null when the glb is missing, so callers can fall back).

const Mats = preload("res://core/mats.gd")
const ROOT := "res://assets/env/town/"
const TEX := "res://textures/town/"
const NAMES := ["house_two_story", "house_bungalow", "house_ranch", "house_split", "house_duplex", "house_farm",
	"house_timber", "house_narrow", "shop_corner", "office_small", "hall_station", "shop_diner", "shop_wood_store"]

static var _scenes := {}
static var _mats := {}
static var _tex := {}

static func has(name: String) -> bool:
	return ResourceLoader.exists(ROOT + name + ".glb")

static func _t(n: String) -> Texture2D:
	if not _tex.has(n):
		_tex[n] = load(TEX + n + ".jpg") if ResourceLoader.exists(TEX + n + ".jpg") else null
	return _tex[n]

static func _pbr(key: String, tex: String, albedo: Color, rough := 1.0, metal := 0.0, nscale := 1.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	if tex != "":
		m.albedo_texture = _t(tex + "_a")
		m.roughness_texture = _t(tex + "_r")
		m.normal_enabled = _t(tex + "_n") != null
		m.normal_texture = _t(tex + "_n")
		m.normal_scale = nscale
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.roughness = rough
	m.metallic = metal
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m

static func material(cat: String, lit := false, dirt := 0.15) -> Material:
	var d := 1.0 - dirt
	var base := cat.split("_")[0]
	match base:
		"SIDING":
			var hex := cat.substr(7, 6)
			var c := Color.html("#" + hex) if hex.length() == 6 else Color(0.6, 0.6, 0.6)
			return _pbr("siding_%s_%.2f" % [hex, dirt], "siding", Color(c.r * d, c.g * d, c.b * d), 1.0, 0.0, 1.2)
		"ROOF":
			return _pbr("roof", "roof", Color(0.55, 0.55, 0.58), 1.0, 0.0, 1.0)
		"SNOW":
			return Mats.get_mat("snow", 3.0)
		"TRIM":
			return _pbr("trim_%.2f" % dirt, "trim", Color(0.78 * d, 0.78 * d, 0.76 * d), 1.0)
		"BRICK":
			return _pbr("brick_%.2f" % dirt, "brick", Color(0.85 * d, 0.8 * d, 0.78 * d), 1.0)
		"STONE":
			return _pbr("stone", "stone", Color(0.75, 0.75, 0.75), 1.0)
		"WOOD":
			return _pbr("wood_%.2f" % dirt, "planks", Color(0.8 * d, 0.76 * d, 0.7 * d), 1.0)
		"GLASS":
			if lit:
				if not _mats.has("glass_lit"):
					var g := StandardMaterial3D.new()
					g.albedo_color = Color(0.25, 0.2, 0.12)
					g.emission_enabled = true
					g.emission = Color(1.0, 0.72, 0.42)
					g.emission_energy_multiplier = 1.6
					g.roughness = 0.15
					_mats["glass_lit"] = g
				return _mats["glass_lit"]
			if not _mats.has("glass"):
				var g2 := StandardMaterial3D.new()
				g2.albedo_color = Color(0.04, 0.05, 0.065)
				g2.metallic = 0.7
				g2.roughness = 0.06
				_mats["glass"] = g2
			return _mats["glass"]
		"DARK":
			return _pbr("dark", "", Color(0.05, 0.05, 0.055), 0.7)
		"METAL":
			return _pbr("metal", "", Color(0.35, 0.36, 0.38), 0.45, 0.8)
	return _pbr("siding_default", "siding", Color(0.5, 0.5, 0.5))

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
	if opts.has("scale"):
		root.scale = Vector3.ONE * float(opts.scale)
	parent.add_child(root)
	root.add_child(inst)
	var lit: bool = randf() < float(opts.get("lit", 0.0))
	var dirt: float = float(opts.get("dirt", 0.15))
	var aabb := AABB()
	var first := true
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		var mesh := m.mesh
		for s in mesh.get_surface_count():
			var src := mesh.surface_get_material(s)
			var cat := src.resource_name if src != null else "SIDING_888888"
			var mat := material(cat, lit, dirt)
			if opts.has("tint") and cat.begins_with("SIDING"):
				var t := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				t.albedo_color *= opts.tint
				mat = t
			m.set_surface_override_material(s, mat)
		var r := float(opts.get("range", 0.0))
		if r > 0.0:
			m.visibility_range_end = r
			m.visibility_range_end_margin = 10.0
		var ab := m.global_transform * mesh.get_aabb() if m.is_inside_tree() else mesh.get_aabb()
		aabb = ab if first else aabb.merge(ab)
		first = false
	if bool(opts.get("collide", true)) and not first:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var local := root.global_transform.affine_inverse() * aabb
		bs.size = Vector3(local.size.x * 0.92, local.size.y, local.size.z * 0.92)
		cs.shape = bs
		cs.position = local.get_center()
		body.add_child(cs)
		root.add_child(body)
	return root

const SHOPS := [["shop_corner", 8.7, 9.1], ["hall_station", 9.5, 6.0], ["shop_wood_store", 5.9, 7.5],
	["house_narrow", 5.4, 6.6], ["office_small", 9.3, 11.5], ["shop_diner", 8.0, 6.6], ["house_timber", 5.6, 5.2]]
const HOUSES := [["house_two_story", 7.9, 6.7], ["house_bungalow", 7.3, 6.7], ["house_ranch", 8.8, 6.3],
	["house_split", 9.7, 6.9], ["house_duplex", 9.6, 6.9], ["house_farm", 8.5, 9.0]]

## A row of buildings along x (x0..x1) whose fronts sit on z = zf, facing +z when out > 0 (else -z).
## Background rows: pass collide=false. Returns the number placed.
static func row(parent: Node, x0: float, x1: float, zf: float, out: float, pool: Array, seed_v: int, opts := {}) -> int:
	if not has("house_two_story"):
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var x := x0 + 0.2
	var yaw := 0.0 if out > 0.0 else PI
	var n := 0
	var gap_min: float = float(opts.get("gap_min", 0.4))
	var gap_max: float = float(opts.get("gap_max", 1.6))
	while x < x1 - 4.0 and n < 30:
		var room := x1 - x
		var fits: Array = pool.filter(func(b): return b[1] <= room + 0.3)
		if fits.is_empty():
			break
		var b: Array = fits[rng.randi() % fits.size()]
		var o := opts.duplicate()
		o["lit"] = opts.get("lit", 0.3)
		building(parent, b[0], Vector3(x + float(b[1]) * 0.5, 0, zf - out * float(b[2]) * 0.5), yaw + rng.randf_range(-0.04, 0.04), o)
		x += float(b[1]) + rng.randf_range(gap_min, gap_max)
		n += 1
	return n
