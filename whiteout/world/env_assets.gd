extends RefCounted
## Real 3D environment assets (assets/env/**.glb): loader, snow-on-top materials, colliders, visibility ranges.
##
##   Env.spawn(parent, "street/hydrant", Vector3(1, 0, 2), yaw, {scale = 1.0, snow = 0.6, collide = "box"})
##
## opts: scale (float|Vector3), snow (0..1, default 0.55), collide ("box" default | "cyl" | "none" | Vector3 size),
##       shadow (bool, default: off for props < 0.6 m), range (visibility end in metres, 0 = always),
##       tint (Color multiplier on albedo), mats ({material_name: Material}), name, rot (Vector3 radians x/z),
##       center (bool: re-centre the node on the model AABB footprint), emissive ({mat_name: [Color, energy]})
## Missing files return null so callers can fall back to primitives.

const SHADER_PATH := "res://world/shaders/env_snow.gdshader"
const FOLIAGE_PATH := "res://world/shaders/env_foliage.gdshader"
const ROOT := "res://assets/env/"

static var _scenes := {}
static var _mats := {}
static var _sh_1: Shader
static var _sh_2: Shader
static var _sh_leaf: Shader
static var _tex := {}
static var snow_default := 0.55

static func has(rel: String) -> bool:
	return ResourceLoader.exists(ROOT + rel + ".glb")

static func scene(rel: String) -> PackedScene:
	if _scenes.has(rel):
		return _scenes[rel]
	var ps: PackedScene = null
	if ResourceLoader.exists(ROOT + rel + ".glb"):
		ps = load(ROOT + rel + ".glb") as PackedScene
	_scenes[rel] = ps
	return ps

static func _shader(two_sided: bool) -> Shader:
	if _sh_1 == null:
		_sh_1 = load(SHADER_PATH)
		_sh_2 = Shader.new()
		_sh_2.code = (_sh_1 as Shader).code.replace("cull_back", "cull_disabled")
	return _sh_2 if two_sided else _sh_1

static func _texture(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]

# -------------------------------------------------------------------------- materials
static func bark_material(snow := 0.5, tint := Color(0.5, 0.45, 0.4)) -> ShaderMaterial:
	var key := "bark@%.2f@%s" % [snow, str(tint)]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = _shader(false)
	m.set_shader_parameter("albedo_tex", _texture("res://textures/env/bark014_Color.jpg"))
	m.set_shader_parameter("normal_tex", _texture("res://textures/env/bark014_NormalGL.jpg"))
	m.set_shader_parameter("orm_tex", _texture("res://textures/env/bark014_Roughness.jpg"))
	m.set_shader_parameter("use_orm", false)
	m.set_shader_parameter("albedo_tint", tint)
	m.set_shader_parameter("snow_amount", snow)
	m.set_shader_parameter("snow_sharp", 3.0)
	_mats[key] = m
	return m

static func foliage_material(snow := 0.8, tint := Color(1, 1, 1)) -> ShaderMaterial:
	var key := "leaf@%.2f@%s" % [snow, str(tint)]
	if _mats.has(key):
		return _mats[key]
	if _sh_leaf == null:
		_sh_leaf = load(FOLIAGE_PATH)
	var m := ShaderMaterial.new()
	m.shader = _sh_leaf
	m.set_shader_parameter("frond_tex", _texture("res://textures/env/frond_atlas.png"))
	m.set_shader_parameter("clump_tex", _texture("res://textures/env/frond_clump.png"))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("snow_amount", snow)
	_mats[key] = m
	return m

## Converts a glTF-imported StandardMaterial3D into the snow shader (opaque materials only).
static func snowify(src: Material, snow: float, tint: Color, emissive: Array = []) -> Material:
	if src == null:
		return null
	if src.resource_name == "bark":
		return bark_material(snow, Color(0.5, 0.45, 0.4) * tint)
	if src.resource_name == "frond":
		return foliage_material(snow, tint)
	if not (src is BaseMaterial3D):
		return src
	var b := src as BaseMaterial3D
	if b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return src      # glass / alpha cards keep their own material
	var key := "%d@%.2f@%s@%s" % [b.get_instance_id(), snow, str(tint), str(emissive)]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = _shader(b.cull_mode == BaseMaterial3D.CULL_DISABLED)
	m.set_shader_parameter("two_sided", b.cull_mode == BaseMaterial3D.CULL_DISABLED)
	m.set_shader_parameter("albedo_tint", b.albedo_color * tint)
	if b.albedo_texture:
		m.set_shader_parameter("albedo_tex", b.albedo_texture)
	if b.normal_texture:
		m.set_shader_parameter("normal_tex", b.normal_texture)
		m.set_shader_parameter("normal_depth", b.normal_scale)
	else:
		m.set_shader_parameter("normal_depth", 0.0)
	var orm: Texture2D = b.roughness_texture if b.roughness_texture else b.metallic_texture
	if b.ao_texture and not orm:
		orm = b.ao_texture
	if orm:
		m.set_shader_parameter("orm_tex", orm)
		m.set_shader_parameter("use_orm", true)
		m.set_shader_parameter("roughness_mul", 1.0)
		m.set_shader_parameter("metallic_mul", 1.0 if b.metallic_texture else 0.0)
	else:
		m.set_shader_parameter("use_orm", false)
	m.set_shader_parameter("snow_amount", snow)
	if b.emission_enabled:
		m.set_shader_parameter("emission_energy", b.emission_energy_multiplier)
		m.set_shader_parameter("emission_color", b.emission)
	if emissive.size() == 2:
		m.set_shader_parameter("emission_energy", float(emissive[1]))
		m.set_shader_parameter("emission_color", emissive[0])
	m.set_shader_parameter("uv_scale", Vector2(b.uv1_scale.x, b.uv1_scale.y))
	_mats[key] = m
	return m

# -------------------------------------------------------------------------- instancing
static func _meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)

## Local-space AABB of every mesh below `root` (relative to root).
static func local_aabb(root: Node3D) -> AABB:
	var meshes: Array = []
	_meshes(root, meshes)
	var box := AABB()
	var first := true
	for mi in meshes:
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		var t: Transform3D = _rel_xf(m, root)
		var a: AABB = t * m.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
	return box

static func _rel_xf(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != root:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t

static func spawn(parent: Node3D, rel: String, pos := Vector3.ZERO, yaw := 0.0, opts := {}) -> Node3D:
	var ps := scene(rel)
	if ps == null:
		return null
	var root := Node3D.new()
	root.name = String(opts.get("name", rel.get_file().capitalize().replace(" ", "")))
	parent.add_child(root)
	root.position = pos
	root.rotation.y = yaw
	if opts.has("rot"):
		root.rotation.x = opts.rot.x
		root.rotation.z = opts.rot.z
	var inst := ps.instantiate() as Node3D
	root.add_child(inst)
	var sc = opts.get("scale", 1.0)
	if opts.has("fit_box"):
		var nb := local_aabb(inst)
		var fb: Vector3 = opts.fit_box
		sc = Vector3(fb.x / max(nb.size.x, 0.01), fb.y / max(nb.size.y, 0.01), fb.z / max(nb.size.z, 0.01))
	elif opts.has("fit_h") or opts.has("fit_len"):
		var nat := local_aabb(inst)
		if opts.has("fit_h") and nat.size.y > 0.001:
			sc = float(opts.fit_h) / nat.size.y
		elif nat.size.z > 0.001:
			sc = float(opts.fit_len) / max(nat.size.z, nat.size.x)
	inst.scale = sc if sc is Vector3 else Vector3.ONE * float(sc)
	var snow: float = float(opts.get("snow", snow_default))
	var tint: Color = opts.get("tint", Color.WHITE)
	var overrides: Dictionary = opts.get("mats", {})
	var emis: Dictionary = opts.get("emissive", {})
	var meshes: Array = []
	_meshes(inst, meshes)
	var longest := 0.0
	for mi in meshes:
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var src: Material = m.get_active_material(s)
			var nm := src.resource_name if src else ""
			if overrides.has(nm):
				m.set_surface_override_material(s, overrides[nm])
			else:
				var mat := snowify(src, snow, tint, emis.get(nm, []))
				if mat != src:
					m.set_surface_override_material(s, mat)
		var ab := m.get_aabb().size * inst.scale
		longest = max(longest, max(ab.x, max(ab.y, ab.z)))
	var shadow = opts.get("shadow", longest > 0.6)
	var rng_end: float = float(opts.get("range", 0.0))
	for mi in meshes:
		var m: MeshInstance3D = mi
		if not shadow:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if rng_end > 0.0:
			m.visibility_range_end = rng_end
			m.visibility_range_end_margin = rng_end * 0.08
		if opts.has("range_begin"):
			m.visibility_range_begin = float(opts.range_begin)
			m.visibility_range_begin_margin = float(opts.range_begin) * 0.08
	var aabb := local_aabb(inst)
	aabb = Transform3D(Basis(), inst.position) * aabb
	if opts.get("center", false):
		inst.position -= Vector3(aabb.get_center().x, 0.0, aabb.get_center().z)
		aabb.position -= Vector3(aabb.get_center().x, 0.0, aabb.get_center().z)
	var col = opts.get("collide", "box")
	if not (col is String and col == "none"):
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		var cs := CollisionShape3D.new()
		if col is Vector3:
			var bs := BoxShape3D.new()
			bs.size = col
			cs.shape = bs
			cs.position = Vector3(aabb.get_center().x, aabb.position.y + (col as Vector3).y * 0.5, aabb.get_center().z)
		elif col is String and col == "cyl":
			var cy := CylinderShape3D.new()
			cy.radius = float(opts.get("cyl_r", min(aabb.size.x, aabb.size.z) * 0.5))
			cy.height = float(opts.get("cyl_h", aabb.size.y))
			cs.shape = cy
			cs.position = Vector3(aabb.get_center().x, aabb.position.y + cy.height * 0.5, aabb.get_center().z)
		else:
			var bs2 := BoxShape3D.new()
			var k: float = float(opts.get("box_shrink", 0.92))
			bs2.size = Vector3(aabb.size.x * k, aabb.size.y, aabb.size.z * k)
			cs.shape = bs2
			cs.position = aabb.get_center()
		sb.add_child(cs)
		root.add_child(sb)
	root.set_meta("env_aabb", aabb)
	return root
