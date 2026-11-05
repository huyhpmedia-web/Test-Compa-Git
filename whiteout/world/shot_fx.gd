extends RefCounted
## Shooting feel FX (VISUAL_REVIEW section 5): muzzle flash quads, lingering smoke, pooled brass casings with landing sound, per-surface impacts with
## bullet-hole decals, hit-stop, melee trail/spark. Everything is procedural (no external textures) and cheap enough for rapid fire.

const Mats = preload("res://core/mats.gd")

static var _tex := {}
static var _decals: Array = []
static var _stopping := false

# ------------------------------------------------------------------ procedural textures
static func _radial(size: int, power: float, spikes := 0, spike_amt := 0.0, seed_v := 1) -> ImageTexture:
	var key := "r%d_%.1f_%d_%.2f_%d" % [size, power, spikes, spike_amt, seed_v]
	if _tex.has(key):
		return _tex[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var phase := rng.randf() * TAU
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var v := Vector2(x + 0.5 - size * 0.5, y + 0.5 - size * 0.5) / (size * 0.5)
			var d := v.length()
			var a := 1.0 - clampf(d, 0.0, 1.0)
			if spikes > 0:
				var ang := atan2(v.y, v.x)
				var sp: float = pow(absf(cos(ang * spikes * 0.5 + phase)), 6.0)
				a = clampf(a + sp * spike_amt * (1.0 - d) * 1.5, 0.0, 1.0)
			a = pow(a, power)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var t := ImageTexture.create_from_image(img)
	_tex[key] = t
	return t

static func _puff(seed_v := 3) -> ImageTexture:
	var key := "puff%d" % seed_v
	if _tex.has(key):
		return _tex[key]
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = 0.05
	n.fractal_octaves = 3
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - 32.0, y + 0.5 - 32.0).length() / 32.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, 1.4) * (0.65 + 0.35 * (n.get_noise_2d(x, y) + 1.0) * 0.5)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	var t := ImageTexture.create_from_image(img)
	_tex[key] = t
	return t

static func _hole_tex(kind: String) -> Array:
	var key := "hole_" + kind
	if _tex.has(key):
		return _tex[key]
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var nrm := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var n := FastNoiseLite.new()
	n.seed = rng.randi()
	n.frequency = 0.12
	for y in size:
		for x in size:
			var v := Vector2(x + 0.5 - 32.0, y + 0.5 - 32.0) / 32.0
			var d := v.length() * (1.0 + 0.25 * n.get_noise_2d(x, y))
			var col := Color(0, 0, 0, 0)
			var core := 0.22
			var halo := 0.75 if kind != "metal" else 0.5
			if d < core:
				col = Color(0.02, 0.02, 0.02, 0.95)
			elif d < halo:
				var t := (d - core) / (halo - core)
				var base := {"snow": Color(0.45, 0.5, 0.58), "concrete": Color(0.12, 0.12, 0.12), "wood": Color(0.1, 0.06, 0.03), "metal": Color(0.08, 0.08, 0.09), "ice": Color(0.55, 0.7, 0.8)}.get(kind, Color(0.1, 0.1, 0.1))
				col = Color(base.r, base.g, base.b, (1.0 - t) * (0.9 if kind == "snow" else 0.7))
			img.set_pixel(x, y, col)
			# normal: raised rim around the hole, dark pit inside
			var rim := smoothstep(core * 0.8, core * 1.3, d) * (1.0 - smoothstep(core * 1.3, core * 2.4, d))
			var dir := v.normalized() if v.length() > 0.001 else Vector2.ZERO
			var nx := -dir.x * rim * (1.0 if d > core else -1.0) * 0.9
			var ny := -dir.y * rim * (1.0 if d > core else -1.0) * 0.9
			nrm.set_pixel(x, y, Color(0.5 + nx * 0.5, 0.5 + ny * 0.5, 1.0, 1.0))
	var out := [ImageTexture.create_from_image(img), ImageTexture.create_from_image(nrm)]
	_tex[key] = out
	return out

static func _quad_mat(tex: Texture2D, color: Color, additive: bool, billboard := true, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tex
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.vertex_color_use_as_albedo = true
	m.disable_receive_shadows = true
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
	return m

# ------------------------------------------------------------------ muzzle flash
const FLASH := {"handgun": [0.9, 0.9], "magnum": [1.5, 1.4], "shotgun": [1.7, 1.6], "launcher": [1.8, 1.7]}

## Randomised 2-frame flash: a billboard star, a forward cone (two crossed quads) and side puffs. `wmodel` = weapon glb root (forward -Z).
static func muzzle_flash(wmodel: Node3D, muzzle: Node3D, id: String) -> void:
	if wmodel == null or muzzle == null or not wmodel.is_inside_tree():
		return
	var k: Array = FLASH.get(id, [1.0, 1.0])
	var root := Node3D.new()
	wmodel.add_child(root)
	root.global_position = muzzle.global_position
	root.global_transform.basis = wmodel.global_transform.basis
	var seed_v := randi() % 3
	var core := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE * 0.26 * k[0] * randf_range(0.8, 1.25)
	core.mesh = qm
	core.material_override = _quad_mat(_radial(64, 1.3, 5 + seed_v * 2, 0.9, seed_v + 1), Color(1.0, 0.82, 0.5, 1.0), true)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.rotation.z = randf() * TAU
	root.add_child(core)
	for i in 2:
		var cone := MeshInstance3D.new()
		var cq := QuadMesh.new()
		var length: float = 0.42 * k[1] * randf_range(0.7, 1.3)
		cq.size = Vector2(length, 0.12 * k[0] * randf_range(0.8, 1.2))
		cone.mesh = cq
		cone.material_override = _quad_mat(_radial(64, 0.9, 0, 0.0, 7), Color(1.0, 0.7, 0.35, 0.95), true, false)
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cone.rotation = Vector3(0, PI * 0.5, 0)           # quad X (length) -> along -Z
		cone.position = Vector3(0, 0, -length * 0.45)
		var holder := Node3D.new()
		holder.rotation.z = i * PI * 0.5 + randf_range(-0.3, 0.3)
		holder.add_child(cone)
		root.add_child(holder)
	# short side blast for the shotgun / magnum
	if id in ["shotgun", "magnum", "launcher"]:
		for sgn in [-1.0, 1.0]:
			var sp := MeshInstance3D.new()
			var sq := QuadMesh.new()
			sq.size = Vector2(0.16, 0.05) * k[0]
			sp.mesh = sq
			sp.material_override = _quad_mat(_radial(32, 1.0), Color(1.0, 0.6, 0.3, 0.8), true, false)
			sp.rotation = Vector3(0, 0, 0)
			sp.position = Vector3(sgn * 0.07 * k[0], 0, 0.02)
			root.add_child(sp)
	var tw := root.create_tween()
	tw.tween_interval(0.035)
	tw.tween_callback(root.queue_free)

## Barrel smoke: soft billboard puffs that linger 1-2 s and drift (world space so they stay behind when the gun moves).
static func muzzle_smoke(parent: Node, pos: Vector3, dir: Vector3, heavy := 1.0) -> void:
	if parent == null:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = int(7 * heavy) + 3
	p.lifetime = 1.7
	p.explosiveness = 0.85
	p.local_coords = false
	p.direction = dir
	p.spread = 22.0
	p.initial_velocity_min = 0.25
	p.initial_velocity_max = 1.3 * heavy
	p.gravity = Vector3(0.12, 0.28, 0.05)
	p.damping_min = 0.8
	p.damping_max = 1.6
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.24
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4)); curve.add_point(Vector2(1, 2.6))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.12, 1.0])
	g.colors = PackedColorArray([Color(0.75, 0.72, 0.7, 0.0), Color(0.72, 0.72, 0.74, 0.32), Color(0.5, 0.52, 0.56, 0.0)])
	p.color_ramp = g
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE
	p.mesh = qm
	p.material_override = _quad_mat(_puff(randi() % 3 + 1), Color.WHITE, false)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(p.lifetime + 0.3)
	tw.tween_callback(p.queue_free)

# ------------------------------------------------------------------ casings
const CASING := {
	"handgun": {"r": 0.0045, "h": 0.019, "col": Color(0.78, 0.58, 0.25), "metal": 1.0, "snd": "casing"},
	"magnum": {"r": 0.0065, "h": 0.033, "col": Color(0.78, 0.58, 0.25), "metal": 1.0, "snd": "casing"},
	"shotgun": {"r": 0.010, "h": 0.07, "col": Color(0.62, 0.07, 0.05), "metal": 0.0, "snd": "shell"},
}
const POOL_MAX := 30

static func spawn_casing(scene: Node, id: String, pos: Vector3, wbasis: Basis, base_vel: Vector3, surface: String) -> void:
	if scene == null or not CASING.has(id):
		return
	var c: Dictionary = CASING[id]
	var pool := scene.get_node_or_null("CasingPool")
	if pool == null:
		pool = Node3D.new()
		pool.name = "CasingPool"
		scene.add_child(pool)
	var body: RigidBody3D
	if pool.get_child_count() >= POOL_MAX:
		body = pool.get_child(0)
		pool.move_child(body, pool.get_child_count() - 1)
		body.sleeping = false
		body.freeze = false
	else:
		body = RigidBody3D.new()
		body.mass = 0.012
		body.collision_layer = 1 << 7
		body.collision_mask = 1
		body.contact_monitor = true
		body.max_contacts_reported = 2
		body.continuous_cd = true
		var pm := PhysicsMaterial.new()
		pm.bounce = 0.42
		pm.friction = 0.5
		body.physics_material_override = pm
		var sh := CylinderShape3D.new()
		sh.radius = c.r
		sh.height = c.h
		var cs := CollisionShape3D.new()
		cs.shape = sh
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = c.r * 0.92
		cm.bottom_radius = c.r
		cm.height = c.h
		cm.radial_segments = 10
		cm.rings = 1
		mi.mesh = cm
		mi.name = "Mesh"
		body.add_child(mi)
		if c.metal < 0.5:
			var base := MeshInstance3D.new()
			var bm := CylinderMesh.new()
			bm.top_radius = c.r * 1.02; bm.bottom_radius = c.r * 1.02; bm.height = c.h * 0.22; bm.radial_segments = 10
			base.mesh = bm
			base.position.y = -c.h * 0.39
			base.material_override = Mats.color(Color(0.75, 0.55, 0.22), 0.35, 1.0)
			body.add_child(base)
		pool.add_child(body)
		body.body_entered.connect(func(_b): _casing_hit(body, scene))
	(body.get_node("Mesh") as MeshInstance3D).material_override = Mats.color(c.col, 0.35 if c.metal > 0.5 else 0.6, c.metal)
	body.set_meta("snd", String(c.snd))
	body.set_meta("surface", surface)
	body.set_meta("last_snd", 0)
	body.set_meta("hits", 0)
	body.global_position = pos
	body.global_transform.basis = Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU))
	var right := wbasis.x
	var up := wbasis.y
	var fwd := -wbasis.z
	body.linear_velocity = right * randf_range(1.8, 3.0) + up * randf_range(1.2, 2.2) - fwd * randf_range(0.0, 0.7) + base_vel * 0.5
	body.angular_velocity = Vector3(randf_range(-30, 30), randf_range(-30, 30), randf_range(-30, 30))

static func _casing_hit(body: RigidBody3D, scene: Node) -> void:
	if not is_instance_valid(body) or not body.is_inside_tree():
		return
	var now := Time.get_ticks_msec()
	if now - int(body.get_meta("last_snd", 0)) < 90 or body.linear_velocity.length() < 0.5 and int(body.get_meta("hits", 0)) > 0:
		return
	body.set_meta("last_snd", now)
	body.set_meta("hits", int(body.get_meta("hits", 0)) + 1)
	if int(body.get_meta("hits")) > 5:
		return
	var surf: String = body.get_meta("surface", "concrete")
	var snd: String = body.get_meta("snd", "casing")
	var name := snd + "_snow" if surf == "snow" else snd
	Sfx.play_at(name, body.global_position, -9.0 - 3.0 * int(body.get_meta("hits")), randf_range(0.9, 1.15))

# ------------------------------------------------------------------ surfaces
static func level_surface() -> String:
	if Game.current_level and Game.current_level.get("footstep") != null:
		var f: String = Game.current_level.get("footstep")
		return f
	return "concrete"

## Surface class from the hit collider (material texture names where available), normal and level default.
static func surface_of(collider: Object, normal: Vector3) -> String:
	if collider is Node:
		var cn := collider as Node
		if cn.has_meta("surface"):
			return String(cn.get_meta("surface"))
		var nm := String(cn.name).to_lower()
		var scan: Array = [cn]
		if cn.get_parent():
			scan.append(cn.get_parent())
		for n in scan:
			for mi in (n as Node).get_children():
				if mi is MeshInstance3D:
					var mat: Material = (mi as MeshInstance3D).material_override
					if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null:
						var path := (mat as BaseMaterial3D).albedo_texture.resource_path.get_file().to_lower()
						var s := _surface_from_name(path)
						if s != "":
							return s
					break
		var s2 := _surface_from_name(nm)
		if s2 != "":
			return s2
	var lv := level_surface()
	if normal.y > 0.6:
		return "snow" if lv == "snow" else ("wood" if lv == "wood" else "concrete")
	return "concrete" if lv != "metal" else "metal"

static func _surface_from_name(s: String) -> String:
	if s.contains("snow") or s.contains("frost"):
		return "snow"
	if s.contains("wood") or s.contains("plank") or s.contains("door") or s.contains("crate") or s.contains("pew"):
		return "wood"
	if s.contains("metal") or s.contains("corrug") or s.contains("car") or s.contains("truck") or s.contains("steel") or s.contains("iron") or s.contains("rack"):
		return "metal"
	if s.contains("ice"):
		return "ice"
	if s.contains("brick") or s.contains("concrete") or s.contains("plaster") or s.contains("asphalt") or s.contains("rock") or s.contains("tile") or s.contains("marble"):
		return "concrete"
	return ""

# ------------------------------------------------------------------ impacts
static func _burst(parent: Node, pos: Vector3, normal: Vector3, amount: int, speed: float, size: float, life: float, color: Color, mesh_kind: String, gravity := 9.8, spread := 55.0, additive := false) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = normal
	p.spread = spread
	p.initial_velocity_min = speed * 0.3
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -gravity, 0)
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if mesh_kind == "puff":
		var qm := QuadMesh.new(); qm.size = Vector2.ONE
		p.mesh = qm
		p.material_override = _quad_mat(_puff(randi() % 3 + 1), Color.WHITE, false)
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
		g.colors = PackedColorArray([Color(color.r, color.g, color.b, 0.0), Color(color.r, color.g, color.b, color.a), Color(color.r, color.g, color.b, 0.0)])
		p.color_ramp = g
		var cv := Curve.new(); cv.add_point(Vector2(0, 0.5)); cv.add_point(Vector2(1, 2.2))
		p.scale_amount_curve = cv
		p.damping_min = 2.0; p.damping_max = 4.0
	elif mesh_kind == "spark":
		var bm := BoxMesh.new(); bm.size = Vector3(0.12, 0.12, 1.0)
		p.mesh = bm
		var sm := Mats.emissive(color, 6.0)
		p.material_override = sm
	else:
		var bm2 := BoxMesh.new(); bm2.size = Vector3(1.0, 0.6, 0.8) if mesh_kind == "chip" else Vector3(0.25, 0.25, 1.4)
		p.mesh = bm2
		p.material_override = Mats.color(color, 0.9)
		p.angle_min = 0.0; p.angle_max = 360.0
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(life + 0.3)
	tw.tween_callback(p.queue_free)

static func hole(parent: Node, pos: Vector3, normal: Vector3, kind: String, size: float) -> void:
	var d := Decal.new()
	var t: Array = _hole_tex(kind)
	d.size = Vector3(size, 0.25, size)
	d.texture_albedo = t[0]
	d.texture_normal = t[1]
	d.normal_fade = 0.2
	d.cull_mask = 1
	parent.add_child(d)
	d.global_position = pos
	var up := normal.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.99 else Vector3.RIGHT).normalized()
	d.global_transform.basis = Basis(side, up, side.cross(up))
	d.rotate_object_local(Vector3.UP, randf() * TAU)
	_decals.append(d)
	while _decals.size() > 70:
		var old = _decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()

static func impact(parent: Node, pos: Vector3, normal: Vector3, surface: String) -> void:
	if parent == null:
		return
	var n := normal.normalized()
	var p := pos + n * 0.02
	match surface:
		"snow":
			_burst(parent, p, n, 14, 2.4, 0.2, 1.1, Color(0.92, 0.95, 1.0, 0.7), "puff", 1.5, 70.0)
			_burst(parent, p, n, 6, 3.0, 0.015, 0.6, Color(0.95, 0.97, 1.0), "chip", 6.0, 60.0)
			hole(parent, pos, n, "snow", 0.14)
			Sfx.play_at("impact_snow", pos, -4.0, randf_range(0.9, 1.15))
		"metal":
			_burst(parent, p, n, 12, 7.0, 0.012, 0.35, Color(1.0, 0.75, 0.35), "spark", 9.8, 50.0)
			_burst(parent, p, n, 3, 1.5, 0.12, 0.5, Color(0.5, 0.5, 0.52, 0.35), "puff", 0.0, 40.0)
			hole(parent, pos, n, "metal", 0.09)
			Sfx.play_at("metal_impact", pos, -3.0, randf_range(0.95, 1.25))
			Sfx.play_at("ricochet", pos, -8.0, randf_range(0.9, 1.2))
			_spark_light(parent, p)
		"wood":
			_burst(parent, p, n, 9, 3.8, 0.018, 0.7, Color(0.62, 0.44, 0.25), "splinter", 9.8, 50.0)
			_burst(parent, p, n, 5, 1.2, 0.12, 0.7, Color(0.6, 0.5, 0.38, 0.3), "puff", 0.0, 50.0)
			hole(parent, pos, n, "wood", 0.1)
			Sfx.play_at("impact_wood", pos, -3.0, randf_range(0.9, 1.1))
		"ice":
			_burst(parent, p, n, 9, 3.5, 0.018, 0.7, Color(0.75, 0.92, 1.0), "chip", 9.8, 60.0)
			_burst(parent, p, n, 6, 1.5, 0.12, 0.8, Color(0.85, 0.95, 1.0, 0.4), "puff", 0.5, 60.0)
			hole(parent, pos, n, "ice", 0.12)
			Sfx.play_at("impact_ice", pos, -4.0, randf_range(0.9, 1.15))
		_:
			_burst(parent, p, n, 9, 2.0, 0.22, 1.0, Color(0.62, 0.6, 0.57, 0.55), "puff", 0.0, 55.0)
			_burst(parent, p, n, 8, 4.5, 0.02, 0.7, Color(0.3, 0.29, 0.28), "chip", 9.8, 60.0)
			_burst(parent, p, n, 4, 5.0, 0.01, 0.3, Color(1.0, 0.85, 0.55), "spark", 9.8, 40.0)
			hole(parent, pos, n, "concrete", 0.12)
			Sfx.play_at("impact_concrete", pos, -3.0, randf_range(0.9, 1.15))

static func _spark_light(parent: Node, pos: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.45)
	l.light_energy = 2.5
	l.omni_range = 2.5
	l.shadow_enabled = false
	parent.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.08)
	tw.tween_callback(l.queue_free)

# ------------------------------------------------------------------ hit-stop
static func hit_stop(tree: SceneTree, ms: float) -> void:
	if tree == null or _stopping:
		return
	_stopping = true
	Engine.time_scale = 0.04
	var t := tree.create_timer(ms / 1000.0, true, false, true)
	t.timeout.connect(func():
		Engine.time_scale = 1.0
		_stopping = false)

# ------------------------------------------------------------------ melee
## Crescent swing trail (additive), faded over ~0.16 s. `xf` = model transform (forward +Z), side +1/-1 = swing direction.
static func swing_trail(parent: Node, xf: Transform3D, side := 1.0) -> void:
	if parent == null:
		return
	var im := ArrayMesh.new()
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var n := 14
	for i in n + 1:
		var t := float(i) / n
		var ang := lerpf(-1.05, 1.05, t) * side
		var r_out := 1.25
		var r_in := lerpf(0.55, 1.0, t)
		var a := 0.9 * pow(t, 1.6)
		var y := lerpf(1.45, 0.95, t)
		verts.append(Vector3(sin(ang) * r_out, y, cos(ang) * r_out))
		verts.append(Vector3(sin(ang) * r_in, y - 0.03, cos(ang) * r_in))
		cols.append(Color(0.85, 0.92, 1.0, a))
		cols.append(Color(0.85, 0.92, 1.0, 0.0))
	for i in n:
		var b := i * 2
		idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	im.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_transform = xf
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.16)
	tw.tween_callback(mi.queue_free)

static func melee_spark(parent: Node, pos: Vector3, dir: Vector3) -> void:
	_burst(parent, pos, -dir, 8, 5.0, 0.012, 0.3, Color(1.0, 0.8, 0.45), "spark", 9.8, 60.0)
