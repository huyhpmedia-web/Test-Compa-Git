extends RefCounted
## Visual effects helpers: weapon meshes, tracers, impacts, blood, explosions.

const Mats = preload("res://core/mats.gd")
const Gore = preload("res://world/gore.gd")
const ShotFX = preload("res://world/shot_fx.gd")

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

## Weapon model. If res://assets/weapons/<id>/<id>.glb exists it is used (Poly Haven service_pistol / hatchet, Blender hard-surface
## guns, or a later AI-generated replacement). Authoring contract for those glbs: forward = -Z (muzzle), up = +Y, and Node3D markers named
## Grip_R, Support_L (optional), Muzzle, Eject (optional) whose frame is the HAND BONE frame (X thumb/pinky axis, Y along the fingers, Z palm normal),
## origin = palm contact point. Optional movable parts: Slide / Pump / Hammer / Cylinder / Trigger (see actors/weapon_ik.gd, SPECS).
## The returned wrapper keeps the old "barrel along -Y" convention so pickups lying on the ground still work; meta "weapon_id" + "model"
## (the glb root, forward -Z) are read by actors/weapon_ik.gd.
## Weapons whose glb has no marker nodes (generated single meshes: origin = bbox centre, muzzle toward +Z). They are turned to the -Z contract and
## given markers from these offsets (metres, in the flipped frame: forward -Z, up +Y, right +X). support: "pistol" (left palm on the grip's left side)
## or "fore" (left palm up under the forend).
const OFFSETS := {
	"shotgun": {"flip": true, "grip": Vector3(0.02, 0.02, 0.13), "support": Vector3(0.0, -0.01, -0.22), "support_kind": "fore",
		"muzzle": Vector3(0, 0.03, -0.5), "eject": Vector3(0.03, 0.03, 0.02)},
	"magnum": {"flip": true, "grip": Vector3(0.018, -0.045, 0.14), "support": Vector3(-0.018, -0.075, 0.14), "support_kind": "pistol",
		"muzzle": Vector3(0, 0.03, -0.15), "eject": Vector3(0.025, 0.02, -0.02)},
	"launcher": {"flip": true, "grip": Vector3(0.018, -0.03, 0.075), "support": Vector3(-0.018, -0.06, 0.075), "support_kind": "pistol",
		"muzzle": Vector3(0, 0.03, -0.12), "eject": Vector3(0.025, 0.02, -0.02)},
}

static func _marker(parent: Node3D, name: String, pos: Vector3, b := Basis.IDENTITY) -> void:
	var m := Node3D.new()
	m.name = name
	m.transform = Transform3D(b, pos)
	parent.add_child(m)

static func weapon_mesh(id: String) -> Node3D:
	var path := "res://assets/weapons/%s/%s.glb" % [id, id]
	if not ResourceLoader.exists(path):
		return _legacy_weapon_mesh(id)
	var wrap := Node3D.new()
	wrap.name = "Weapon_" + id
	var model: Node3D = (load(path) as PackedScene).instantiate()
	if OFFSETS.has(id) and model.find_child("Grip_R", true, false) == null:
		var o: Dictionary = OFFSETS[id]
		var frame := Node3D.new()
		frame.add_child(model)
		if o.get("flip", false):
			model.rotation.y = PI
		var F := Vector3(0, 0, -1); var U := Vector3.UP; var L := Vector3(-1, 0, 0); var R := Vector3.RIGHT
		_marker(frame, "Grip_R", o.grip, Basis(U, F, L))
		_marker(frame, "Muzzle", o.muzzle)
		_marker(frame, "Eject", o.eject, Basis(U, F, R))
		if o.get("support_kind", "pistol") == "fore":
			_marker(frame, "Support_L", o.support, Basis(R, F, U))
		else:
			_marker(frame, "Support_L", o.support, Basis(-U, F, R))
		model = frame
	model.name = "Model"
	model.rotation = Vector3(-PI * 0.5, 0, 0)
	wrap.add_child(model)
	wrap.set_meta("weapon_id", id)
	wrap.set_meta("model", model)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return wrap

static func _legacy_weapon_mesh(id: String) -> Node3D:
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
	cyl.top_radius = 0.004
	cyl.bottom_radius = 0.004
	cyl.height = len
	var mi := _mi(cyl, Mats.emissive(Color(1.0, 0.85, 0.55), 2.5))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = (from + to) * 0.5
	var up := (to - from).normalized()
	var side := up.cross(Vector3.UP if abs(up.y) < 0.99 else Vector3.RIGHT).normalized()
	mi.global_transform.basis = Basis(side, up, side.cross(up))
	var tw := mi.create_tween()
	tw.tween_interval(0.05)
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
	ShotFX.impact(parent, pos, normal, ShotFX.surface_of(null, normal))

## Flesh hit at a bullet impact. Enemies running Enemy.take_hit already did the full gore hook
## (Gore.on_enemy_hit); this covers anything else that was shot (bosses, props, NPCs).
static func blood_burst(parent: Node, pos: Vector3, normal: Vector3) -> void:
	Gore.fallback_hit(parent, pos, normal)

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
	Gore.src_override = "explosion"
	for e in parent.get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.has_method("take_hit"):
			var d: float = e.global_position.distance_to(pos)
			if d < radius:
				var dmg := damage * (1.0 - d / radius * 0.6)
				if e.has_method("burn"):
					e.burn(dmg, pos)
				else:
					e.take_hit(dmg, e.global_position + Vector3(0, 1, 0), (e.global_position - pos).normalized(), false)
	Gore.src_override = ""
	for p in parent.get_tree().get_nodes_in_group("player"):
		var d2: float = p.global_position.distance_to(pos)
		if d2 < radius * 0.6:
			p.hurt(int(30 * (1.0 - d2 / radius)), pos)
	decal(parent, pos, Vector3.UP, Color(0.03, 0.03, 0.03, 0.9), radius * 0.6)

## A burning road flare on the ground: bright red light, smoke, burns and repels the
## Rimebound within `radius` for `life` seconds.
static func flare(parent: Node, pos: Vector3, life := 25.0, radius := 4.0) -> Node3D:
	if parent == null:
		return null
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos + Vector3(0, 0.05, 0)
	var stick := _box(Vector3(0.04, 0.04, 0.3), Mats.color(Color(0.8, 0.1, 0.05), 0.6))
	root.add_child(stick)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.25, 0.12)
	l.light_energy = 5.0
	l.omni_range = 9.0
	l.shadow_enabled = true
	l.position = Vector3(0, 0.3, 0)
	root.add_child(l)
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 1.2
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0, 0.6, 0)
	p.scale_amount_min = 0.04
	p.scale_amount_max = 0.14
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	p.mesh = sm
	p.material_override = Mats.emissive(Color(1.0, 0.4, 0.2), 4.0)
	root.add_child(p)
	Sfx.play_at("flare_ignite", pos)
	var tick := Timer.new()
	tick.wait_time = 0.5
	tick.autostart = true
	root.add_child(tick)
	var t := [0.0]
	tick.timeout.connect(func():
		t[0] += 0.5
		l.light_energy = 4.5 + randf() * 1.5
		for e in root.get_tree().get_nodes_in_group("enemy"):
			if is_instance_valid(e) and e.global_position.distance_to(root.global_position) < radius:
				if e.has_method("burn"):
					e.burn(4.0, root.global_position)
		if t[0] >= life:
			root.queue_free())
	return root
