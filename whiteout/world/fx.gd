extends RefCounted
## Visual effects helpers: weapon meshes, tracers, impacts, blood, explosions.

const Mats = preload("res://core/mats.gd")

static func _mi(mesh: Mesh, mat: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	return m

static func _box(size: Vector3, mat: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mi(b, mat, pos)

## Weapon model held in the right hand. Hand space: -Y is down the fingers, +Z forward
## once the aim pose rotates the hand; barrel points along -Y in hand space.
static func weapon_mesh(id: String) -> Node3D:
	var root := Node3D.new()
	var steel := Mats.color(Color(0.13, 0.13, 0.14), 0.35, 0.85)
	var grip := Mats.color(Color(0.06, 0.06, 0.06), 0.7)
	var wood := Mats.get_mat("wood", 0.4)
	match id:
		"handgun":
			root.add_child(_box(Vector3(0.03, 0.19, 0.035), steel, Vector3(0, -0.06, 0.04)))
			root.add_child(_box(Vector3(0.028, 0.06, 0.11), grip, Vector3(0, 0.0, -0.01)))
		"shotgun":
			root.add_child(_box(Vector3(0.04, 0.75, 0.05), steel, Vector3(0, -0.25, 0.05)))
			root.add_child(_box(Vector3(0.05, 0.25, 0.06), wood, Vector3(0, -0.3, 0.0)))
			root.add_child(_box(Vector3(0.045, 0.3, 0.09), wood, Vector3(0, 0.18, -0.02)))
		"magnum":
			root.add_child(_box(Vector3(0.035, 0.26, 0.035), Mats.color(Color(0.6, 0.6, 0.62), 0.25, 0.95), Vector3(0, -0.1, 0.045)))
			root.add_child(_box(Vector3(0.045, 0.05, 0.05), Mats.color(Color(0.6, 0.6, 0.62), 0.25, 0.95), Vector3(0, -0.01, 0.04)))
			root.add_child(_box(Vector3(0.03, 0.06, 0.11), wood, Vector3(0, 0.02, -0.01)))
		"launcher":
			var tube := CylinderMesh.new()
			tube.top_radius = 0.035; tube.bottom_radius = 0.035; tube.height = 0.5
			root.add_child(_mi(tube, Mats.color(Color(0.18, 0.22, 0.16), 0.6, 0.4), Vector3(0, -0.15, 0.05)))
			root.add_child(_box(Vector3(0.04, 0.25, 0.08), grip, Vector3(0, 0.15, 0.0)))
		"knife":
			root.add_child(_box(Vector3(0.008, 0.18, 0.025), Mats.color(Color(0.8, 0.8, 0.82), 0.2, 1.0), Vector3(0, -0.12, 0.01)))
			root.add_child(_box(Vector3(0.02, 0.09, 0.025), grip, Vector3(0, 0.0, 0)))
	for c in root.get_children():
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return root

static func tracer(parent: Node, from: Vector3, to: Vector3) -> void:
	if parent == null:
		return
	var len := from.distance_to(to)
	if len < 0.5:
		return
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.006
	cyl.bottom_radius = 0.006
	cyl.height = len
	var mi := _mi(cyl, Mats.emissive(Color(1.0, 0.85, 0.5), 4.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = (from + to) * 0.5
	var up := (to - from).normalized()
	var side := up.cross(Vector3.UP if abs(up.y) < 0.99 else Vector3.RIGHT).normalized()
	mi.global_transform.basis = Basis(side, up, side.cross(up))
	var tw := mi.create_tween()
	tw.tween_interval(0.04)
	tw.tween_callback(mi.queue_free)

static func _particles(parent: Node, pos: Vector3, color: Color, amount: int, speed: float, size: float, life: float, gravity := 9.8) -> void:
	if parent == null:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 1.0
	p.spread = 70.0
	p.direction = Vector3.UP
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -gravity, 0)
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	var mat := Mats.color(color, 0.4)
	if color.r > 0.9 and color.g > 0.5:
		mat = Mats.emissive(color, 5.0)
	p.material_override = mat
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(life + 0.2)
	tw.tween_callback(p.queue_free)

static func impact(parent: Node, pos: Vector3, normal: Vector3) -> void:
	_particles(parent, pos + normal * 0.02, Color(1.0, 0.8, 0.4), 8, 4.0, 0.02, 0.25)
	_particles(parent, pos + normal * 0.02, Color(0.45, 0.42, 0.38), 10, 1.5, 0.04, 0.6, 3.0)
	decal(parent, pos, normal, Color(0.05, 0.05, 0.05, 0.9), 0.06)

static func blood_burst(parent: Node, pos: Vector3, normal: Vector3) -> void:
	_particles(parent, pos, Color(0.35, 0.02, 0.02), 16, 2.5, 0.05, 0.6)
	# drip on the floor below
	if parent != null and parent.is_inside_tree():
		var space: PhysicsDirectSpaceState3D = parent.get_viewport().get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(pos, pos + Vector3(0, -3, 0), 1)
		var hit := space.intersect_ray(q)
		if hit:
			decal(parent, hit.position, hit.normal, Color(0.22, 0.01, 0.01, 0.95), randf_range(0.25, 0.5))

static func decal(parent: Node, pos: Vector3, normal: Vector3, color: Color, size: float) -> void:
	if parent == null:
		return
	var d := Decal.new()
	d.size = Vector3(size, 0.2, size)
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var dd := Vector2(x - 15.5, y - 15.5).length() / 15.5
			var a: float = clamp(1.0 - dd + randf_range(-0.15, 0.15), 0.0, 1.0)
			img.set_pixel(x, y, Color(color.r, color.g, color.b, color.a * smoothstep(0.0, 0.4, a)))
	d.texture_albedo = ImageTexture.create_from_image(img)
	parent.add_child(d)
	d.global_position = pos
	var up := normal.normalized()
	var side := up.cross(Vector3.FORWARD if abs(up.z) < 0.99 else Vector3.RIGHT).normalized()
	d.global_transform.basis = Basis(side, up, side.cross(up))
	d.rotate_object_local(Vector3.UP, randf() * TAU)
	var tw := d.create_tween()
	tw.tween_interval(40.0)
	tw.tween_callback(d.queue_free)

static func explosion(parent: Node, pos: Vector3, radius: float, damage: float) -> void:
	if parent == null:
		return
	_particles(parent, pos, Color(1.0, 0.6, 0.2), 40, 8.0, 0.25, 0.5, 2.0)
	_particles(parent, pos, Color(0.15, 0.14, 0.13), 30, 3.0, 0.6, 1.5, -1.0)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.3)
	l.light_energy = 12.0
	l.omni_range = radius * 3.0
	parent.add_child(l)
	l.global_position = pos + Vector3(0, 0.5, 0)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.5)
	tw.tween_callback(l.queue_free)
	Sfx.play_at("explosion", pos, 4.0)
	Sfx.alert_noise(pos, 40.0)
	for e in parent.get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.has_method("take_hit"):
			var d: float = e.global_position.distance_to(pos)
			if d < radius:
				e.take_hit(damage * (1.0 - d / radius * 0.6), e.global_position + Vector3(0, 1, 0), (e.global_position - pos).normalized(), false)
	for p in parent.get_tree().get_nodes_in_group("player"):
		var d2: float = p.global_position.distance_to(pos)
		if d2 < radius * 0.6:
			p.hurt(int(30 * (1.0 - d2 / radius)), pos)
	decal(parent, pos, Vector3.UP, Color(0.03, 0.03, 0.03, 0.9), radius * 0.6)
