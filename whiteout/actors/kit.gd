extends RefCounted
## Procedural mesh/material toolkit for the Rimebound: noise-displaced blobs, faceted
## crystals, limbs between two points, ice/frost/flesh materials, shard debris, FX rings.

const Mats = preload("res://core/mats.gd")
const PostNode = preload("res://actors/post_node.gd")

static var _mats := {}
static var _meshes := {}

# ------------------------------------------------------------------ materials
static func mat(kind: String) -> StandardMaterial3D:
	if _mats.has(kind):
		return _mats[kind]
	var m := StandardMaterial3D.new()
	match kind:
		"ice", "ice_deep", "ice_glow":
			m.albedo_color = Color(0.72, 0.9, 1.0, 0.5)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.08
			m.metallic = 0.15
			m.metallic_specular = 0.9
			m.rim_enabled = true
			m.rim = 0.9
			m.rim_tint = 0.6
			m.emission_enabled = true
			m.emission = Color(0.3, 0.75, 0.95)
			m.emission_energy_multiplier = 0.45
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			if kind == "ice_deep":
				m.albedo_color = Color(0.35, 0.62, 0.9, 0.68)
				m.emission_energy_multiplier = 0.3
			elif kind == "ice_glow":
				m.albedo_color = Color(0.6, 0.95, 1.0, 0.7)
				m.emission = Color(0.35, 0.9, 1.0)
				m.emission_energy_multiplier = 2.6
		"frost":
			m.albedo_color = Color(0.82, 0.9, 0.96)
			m.roughness = 0.5
			m.rim_enabled = true
			m.rim = 0.5
			m.rim_tint = 0.7
			m.emission_enabled = true
			m.emission = Color(0.2, 0.4, 0.55)
			m.emission_energy_multiplier = 0.2
		"skin_frost":
			m.albedo_color = Color(0.8, 0.88, 0.92)
			m.roughness = 0.55
			m.subsurf_scatter_enabled = true
			m.subsurf_scatter_strength = 0.3
			m.rim_enabled = true
			m.rim = 0.35
			m.rim_tint = 0.8
			m.emission_enabled = true
			m.emission = Color(0.15, 0.35, 0.5)
			m.emission_energy_multiplier = 0.25
		"flesh_black":
			m.albedo_color = Color(0.07, 0.05, 0.06)
			m.roughness = 0.5
		"flesh_dead":
			m.albedo_color = Color(0.5, 0.47, 0.5)
			m.roughness = 0.6
			m.rim_enabled = true
			m.rim = 0.25
			m.rim_tint = 0.8
		"flesh_raw":
			m.albedo_color = Color(0.38, 0.07, 0.07)
			m.roughness = 0.35
		"bone":
			m.albedo_color = Color(0.75, 0.72, 0.62)
			m.roughness = 0.6
		"cloth_dark":
			m.albedo_color = Color(0.12, 0.11, 0.13)
			m.roughness = 0.95
		"cloth_grey":
			m.albedo_color = Color(0.3, 0.3, 0.33)
			m.roughness = 0.95
		"hat_yellow":
			m.albedo_color = Color(0.72, 0.56, 0.08)
			m.roughness = 0.45
		"denim":
			m.albedo_color = Color(0.13, 0.17, 0.27)
			m.roughness = 0.95
		"hivis":
			m.albedo_color = Color(0.85, 0.32, 0.04)
			m.roughness = 0.8
		"rust":
			m.albedo_color = Color(0.36, 0.2, 0.12)
			m.roughness = 0.75
			m.metallic = 0.6
		"iron":
			m.albedo_color = Color(0.2, 0.2, 0.22)
			m.roughness = 0.45
			m.metallic = 0.85
		"root":
			m.albedo_color = Color(0.06, 0.06, 0.09)
			m.roughness = 0.35
			m.metallic = 0.3
			m.emission_enabled = true
			m.emission = Color(0.1, 0.35, 0.5)
			m.emission_energy_multiplier = 0.4
		"tooth":
			m.albedo_color = Color(0.82, 0.8, 0.7)
			m.roughness = 0.4
		"mouth":
			m.albedo_color = Color(0.02, 0.0, 0.01)
			m.roughness = 1.0
		_:
			m.albedo_color = Color(0.5, 0.5, 0.5)
	_mats[kind] = m
	return m

## Emissive material (cached per colour+energy).
static func glow(c: Color, energy := 3.0) -> StandardMaterial3D:
	var key := "glow%s_%.1f" % [c.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := Mats.emissive(c, energy)
	_mats[key] = m
	return m

## Unique (non-shared) emissive material, safe to animate.
static func glow_unique(c: Color, energy := 3.0) -> StandardMaterial3D:
	return Mats.emissive(c, energy)

# ------------------------------------------------------------------ meshes
static func basis_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.RIGHT if abs(y.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x := ref.cross(y).normalized()
	return Basis(x, y, x.cross(y))

## Noise-displaced ellipsoid with smooth normals.
static func blob(radius: float, seed: int, amp := 0.12, scl := Vector3.ONE, rings := 12, segs := 18, freq := 1.5) -> ArrayMesh:
	var key := "blob_%.3f_%d_%.3f_%s_%d_%d_%.2f" % [radius, seed, amp, str(scl), rings, segs, freq]
	if _meshes.has(key):
		return _meshes[key]
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = 1.0
	var grid := []
	for i in rings + 1:
		var row := []
		var th := PI * float(i) / rings
		for j in segs:
			var ph := TAU * float(j) / segs
			var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			var r := radius * (1.0 + amp * n.get_noise_3d(d.x * freq * 2.0, d.y * freq * 2.0, d.z * freq * 2.0) * 2.0)
			row.append(d * r * scl)
		grid.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rings:
		for j in segs:
			var j2 := (j + 1) % segs
			var a: Vector3 = grid[i][j]
			var b: Vector3 = grid[i + 1][j]
			var c: Vector3 = grid[i + 1][j2]
			var d2: Vector3 = grid[i][j2]
			if i > 0:
				st.add_vertex(a); st.add_vertex(b); st.add_vertex(d2)
			if i < rings - 1:
				st.add_vertex(d2); st.add_vertex(b); st.add_vertex(c)
	st.generate_normals()
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh

## Faceted crystal, base radius 1 at y=0, height 1 (tip at y=1). Scale it (r, len, r).
static func crystal_mesh(variant := 0, sides := 6) -> ArrayMesh:
	var key := "crys_%d_%d" % [variant, sides]
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + variant * 77
	var tip_h := rng.randf_range(0.18, 0.34)
	var shoulder := 1.0 - tip_h
	var tip := Vector3(rng.randf_range(-0.12, 0.12), 1.0, rng.randf_range(-0.12, 0.12))
	var bot := []
	var top := []
	for k in sides:
		var a := TAU * float(k) / sides + rng.randf_range(-0.12, 0.12)
		var rr := rng.randf_range(0.85, 1.1)
		bot.append(Vector3(cos(a) * rr, 0.0, sin(a) * rr))
		top.append(Vector3(cos(a) * rr * 0.92, shoulder + rng.randf_range(-0.04, 0.04), sin(a) * rr * 0.92))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for k in sides:
		var k2 := (k + 1) % sides
		st.add_vertex(bot[k]); st.add_vertex(top[k2]); st.add_vertex(top[k])
		st.add_vertex(bot[k]); st.add_vertex(bot[k2]); st.add_vertex(top[k2])
		st.add_vertex(top[k]); st.add_vertex(top[k2]); st.add_vertex(tip)
		st.add_vertex(bot[k]); st.add_vertex(Vector3.ZERO); st.add_vertex(bot[k2])
	st.generate_normals()
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh

static func mi(parent: Node, mesh: Mesh, m: Material, pos := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = m
	n.position = pos
	if not shadow:
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if parent != null:
		parent.add_child(n)
	return n

static func crystal(parent: Node, pos: Vector3, dir: Vector3, length: float, radius: float, m: Material = null, variant := 0) -> MeshInstance3D:
	if m == null:
		m = mat("ice")
	var n := MeshInstance3D.new()
	n.mesh = crystal_mesh(variant % 8)
	n.material_override = m
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var b := basis_y(dir)
	n.transform = Transform3D(Basis(b.x * radius, b.y * length, b.z * radius), pos)
	parent.add_child(n)
	return n

static func cluster(parent: Node, pos: Vector3, dir: Vector3, n: int, length: float, radius: float, m: Material, rng: RandomNumberGenerator, spread := 0.5) -> Array:
	var out := []
	for i in n:
		var d := (dir.normalized() + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * spread).normalized()
		out.append(crystal(parent, pos + d * radius * 0.2, d, length * rng.randf_range(0.5, 1.2), radius * rng.randf_range(0.6, 1.25), m, rng.randi() % 8))
	return out

## Cylinder limb from a to b (parent-local), radius r0 at a, r1 at b. Optional joint ball at a.
static func limb(parent: Node, a: Vector3, b: Vector3, r0: float, r1: float, m: Material, joint := false, segs := 8) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r1
	cm.bottom_radius = r0
	cm.height = a.distance_to(b)
	cm.radial_segments = segs
	cm.rings = 1
	var n := MeshInstance3D.new()
	n.mesh = cm
	n.material_override = m
	var dir := b - a
	if dir.length() < 0.001:
		dir = Vector3.UP
	n.transform = Transform3D(basis_y(dir), (a + b) * 0.5)
	parent.add_child(n)
	if joint:
		var s := SphereMesh.new()
		s.radius = r0
		s.height = r0 * 2.0
		s.radial_segments = 10
		s.rings = 6
		mi(parent, s, m, a)
	return n

static func sphere(parent: Node, r: float, m: Material, pos := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 14
	s.rings = 8
	var n := mi(parent, s, m, pos)
	n.scale = scl
	return n

static func box(parent: Node, size: Vector3, m: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return mi(parent, b, m, pos)

static func post(model: Node, fn: Callable) -> Node:
	var p := PostNode.new()
	p.fn = fn
	model.add_child(p)
	return p

# ------------------------------------------------------------------ debris / FX
## Falling crystal shards (RigidBody3D, auto-freed).
static func shard_burst(world: Node, pos: Vector3, n := 10, power := 3.5, size := 0.12, kind := "ice") -> void:
	if world == null or not world.is_inside_tree():
		return
	var m := mat(kind)
	for i in n:
		var rb := RigidBody3D.new()
		rb.collision_layer = 0
		rb.collision_mask = 1
		rb.mass = 0.3
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = size * 0.5
		cs.shape = sh
		rb.add_child(cs)
		var sz := size * randf_range(0.6, 1.6)
		crystal(rb, Vector3.ZERO, Vector3.UP, sz * 2.2, sz * 0.5, m, randi() % 8)
		world.add_child(rb)
		rb.global_position = pos
		rb.linear_velocity = Vector3(randf_range(-1, 1), randf_range(0.3, 1.4), randf_range(-1, 1)) * power
		rb.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
		var tw := rb.create_tween()
		tw.tween_interval(2.5 + randf() * 1.5)
		tw.tween_callback(rb.queue_free)

## Detach a mesh node from its model and let it fall as a rigid body.
static func drop_piece(node: MeshInstance3D, world: Node, push := Vector3.ZERO) -> void:
	if node == null or not is_instance_valid(node) or world == null or not node.is_inside_tree():
		return
	var xf := node.global_transform
	var rb := RigidBody3D.new()
	rb.collision_layer = 0
	rb.collision_mask = 1
	rb.mass = 2.0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	var ab := node.mesh.get_aabb() if node.mesh else AABB(Vector3.ZERO, Vector3.ONE * 0.2)
	sh.size = (ab.size * xf.basis.get_scale()).abs().clamp(Vector3.ONE * 0.08, Vector3.ONE * 3.0)
	cs.shape = sh
	cs.position = ab.get_center() * xf.basis.get_scale()
	rb.add_child(cs)
	var vis := MeshInstance3D.new()
	vis.mesh = node.mesh
	vis.material_override = node.material_override
	vis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vis.scale = xf.basis.get_scale()
	rb.add_child(vis)
	world.add_child(rb)
	rb.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	rb.linear_velocity = push + Vector3(randf_range(-1, 1), randf_range(0.5, 2.0), randf_range(-1, 1))
	rb.angular_velocity = Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5))
	node.queue_free()
	var tw := rb.create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(vis, "scale", Vector3.ZERO, 0.6)
	tw.tween_callback(rb.queue_free)

## Expanding translucent ring on the floor (hum pulses, slams).
static func ring_wave(world: Node, pos: Vector3, radius: float, color := Color(0.5, 0.9, 1.0), dur := 0.9, thick := 0.08) -> void:
	if world == null or not world.is_inside_tree():
		return
	var t := TorusMesh.new()
	t.inner_radius = 0.92
	t.outer_radius = 1.0
	t.rings = 24
	t.ring_segments = 6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color.r, color.g, color.b, 0.6)
	var n := mi(null, t, m, Vector3.ZERO, false)
	world.add_child(n)
	n.global_position = pos
	n.scale = Vector3(0.2, thick * 6.0, 0.2)
	var tw := n.create_tween()
	tw.set_parallel(true)
	tw.tween_property(n, "scale", Vector3(radius, thick * 6.0, radius), dur).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, dur)
	tw.chain().tween_callback(n.queue_free)

## All MeshInstance3D under a node.
static func meshes(root: Node) -> Array:
	return root.find_children("*", "MeshInstance3D", true, false)

## Hard hat on a humanoid head pivot (head-local metres * s). Returns the lamp mount node
## (front of the hat, +Z forward) so callers can add a SpotLight3D or a dead lamp lens.
static func hardhat(head: Node3D, s: float, lit := false) -> Node3D:
	var hat := Node3D.new()
	hat.name = "HardHat"
	head.add_child(hat)
	var ym := mat("hat_yellow")
	sphere(hat, 0.122 * s, ym, Vector3(0, 0.165, -0.005) * s, Vector3(1.0, 0.72, 1.12))
	box(hat, Vector3(0.27, 0.012, 0.31) * s, ym, Vector3(0, 0.145, 0.02) * s)
	box(hat, Vector3(0.03, 0.03, 0.26) * s, ym, Vector3(0, 0.255, -0.005) * s)
	var mount := Node3D.new()
	mount.position = Vector3(0, 0.205, 0.125) * s
	hat.add_child(mount)
	box(mount, Vector3(0.07, 0.05, 0.04) * s, mat("iron"), Vector3.ZERO)
	var lens := sphere(mount, 0.026 * s, glow(Color(1.0, 0.92, 0.7), 6.0) if lit else mat("iron"), Vector3(0, 0, 0.022) * s, Vector3(1, 1, 0.6))
	lens.name = "Lens"
	return mount
