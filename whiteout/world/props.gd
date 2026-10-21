extends RefCounted
## Prop library. Every function: (parent: Node3D, pos: Vector3, yaw: float = 0.0, ...) -> Node3D
## Props with `solid` get StaticBody3D box colliders on layer 1 (world).
## Level authors may add their own local props; keep generic ones here.

const Mats = preload("res://core/mats.gd")

static func _root(parent: Node3D, pos: Vector3, yaw: float, n: String) -> Node3D:
	var r := Node3D.new()
	r.name = n
	parent.add_child(r)
	r.position = pos
	r.rotation.y = yaw
	return r

## Box mesh (+ optional collider) in local space of `r`.
static func box(r: Node3D, size: Vector3, pos: Vector3, mat: Material, solid := true, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	r.add_child(mi)
	if solid:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		sb.add_child(cs)
		mi.add_child(sb)
	return mi

static func cyl(r: Node3D, radius: float, h: float, pos: Vector3, mat: Material, solid := true, top_radius := -1.0, rot := Vector3.ZERO, segs := 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = radius
	cm.top_radius = radius if top_radius < 0.0 else top_radius
	cm.height = h
	cm.radial_segments = segs
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	r.add_child(mi)
	if solid:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = max(radius, cm.top_radius)
		sh.height = h
		cs.shape = sh
		sb.add_child(cs)
		mi.add_child(sb)
	return mi

static func sphere(r: Node3D, radius: float, pos: Vector3, mat: Material, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	r.add_child(mi)
	return mi

# ------------------------------------------------------------------ furniture
static func crate(parent: Node3D, pos: Vector3, yaw := 0.0, s := 0.8) -> Node3D:
	var r := _root(parent, pos, yaw, "Crate")
	box(r, Vector3(s, s, s), Vector3(0, s * 0.5, 0), Mats.get_mat("wood", 0.8))
	return r

static func barrel(parent: Node3D, pos: Vector3, yaw := 0.0, rusty := true) -> Node3D:
	var r := _root(parent, pos, yaw, "Barrel")
	cyl(r, 0.3, 0.9, Vector3(0, 0.45, 0), Mats.get_mat("metal_rust" if rusty else "metal_painted", 0.6))
	return r

static func desk(parent: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	var r := _root(parent, pos, yaw, "Desk")
	var w := Mats.get_mat("wood", 0.8)
	box(r, Vector3(1.6, 0.06, 0.8), Vector3(0, 0.76, 0), w)
	box(r, Vector3(0.45, 0.72, 0.75), Vector3(-0.55, 0.36, 0), w)
	box(r, Vector3(0.05, 0.72, 0.75), Vector3(0.75, 0.36, 0), w)
	# monitor + keyboard + papers
	box(r, Vector3(0.5, 0.32, 0.04), Vector3(0.2, 1.0, -0.2), Mats.color(Color(0.05, 0.05, 0.06), 0.3), false)
	box(r, Vector3(0.46, 0.27, 0.01), Vector3(0.2, 1.0, -0.177), Mats.emissive(Color(0.05, 0.12, 0.18), 0.6), false)
	box(r, Vector3(0.42, 0.02, 0.14), Vector3(0.2, 0.8, 0.12), Mats.color(Color(0.1, 0.1, 0.1), 0.6), false)
	box(r, Vector3(0.25, 0.01, 0.32), Vector3(-0.45, 0.795, 0.1), Mats.get_mat("paper"), false, Vector3(0, 0.3, 0))
	return r

static func chair(parent: Node3D, pos: Vector3, yaw := 0.0, toppled := false) -> Node3D:
	var r := _root(parent, pos, yaw, "Chair")
	var m := Mats.color(Color(0.08, 0.08, 0.09), 0.6)
	var holder := Node3D.new()
	r.add_child(holder)
	if toppled:
		holder.rotation.x = PI * 0.5
		holder.position.y = 0.25
	box(holder, Vector3(0.48, 0.07, 0.48), Vector3(0, 0.47, 0), m, false)
	box(holder, Vector3(0.48, 0.5, 0.06), Vector3(0, 0.75, -0.22), m, false)
	cyl(holder, 0.03, 0.44, Vector3(0, 0.22, 0), Mats.get_mat("metal"), false)
	box(r, Vector3(0.5, 0.9, 0.5), Vector3(0, 0.45, 0), m, true).visible = false
	return r

static func table(parent: Node3D, pos: Vector3, yaw := 0.0, size := Vector2(1.4, 0.8)) -> Node3D:
	var r := _root(parent, pos, yaw, "Table")
	var w := Mats.get_mat("wood", 0.8)
	box(r, Vector3(size.x, 0.05, size.y), Vector3(0, 0.75, 0), w)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			box(r, Vector3(0.06, 0.73, 0.06), Vector3(sx * (size.x * 0.5 - 0.06), 0.365, sz * (size.y * 0.5 - 0.06)), w, false)
	return r

static func shelf(parent: Node3D, pos: Vector3, yaw := 0.0, w := 1.8, h := 2.2, books := true) -> Node3D:
	var r := _root(parent, pos, yaw, "Shelf")
	var m := Mats.get_mat("wood_panel", 1.0)
	box(r, Vector3(w, h, 0.05), Vector3(0, h * 0.5, -0.2), m)
	for sx in [-1, 1]:
		box(r, Vector3(0.05, h, 0.42), Vector3(sx * w * 0.5, h * 0.5, 0), m)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 100 + pos.z * 7)
	for i in 5:
		var y := 0.05 + i * (h - 0.1) / 4.6
		box(r, Vector3(w, 0.04, 0.42), Vector3(0, y, 0), m, false)
		if books and i < 4:
			var x := -w * 0.5 + 0.06
			while x < w * 0.5 - 0.1:
				var bw := rng.randf_range(0.03, 0.07)
				var bh := rng.randf_range(0.22, 0.34)
				if rng.randf() > 0.12:
					var c := Color.from_hsv(rng.randf(), rng.randf_range(0.3, 0.7), rng.randf_range(0.15, 0.45))
					box(r, Vector3(bw, bh, 0.25), Vector3(x + bw * 0.5, y + 0.02 + bh * 0.5, 0.0), Mats.color(c, 0.8), false, Vector3(0, 0, rng.randf_range(-0.05, 0.05)))
				x += bw + 0.005
	return r

static func locker(parent: Node3D, pos: Vector3, yaw := 0.0, count := 3) -> Node3D:
	var r := _root(parent, pos, yaw, "Lockers")
	var m := Mats.get_mat("metal_painted", 1.0)
	for i in count:
		box(r, Vector3(0.4, 1.9, 0.5), Vector3((i - (count - 1) * 0.5) * 0.42, 0.95, 0), m)
		for k in 3:
			box(r, Vector3(0.25, 0.015, 0.01), Vector3((i - (count - 1) * 0.5) * 0.42, 1.6 + k * 0.04, 0.255), Mats.color(Color(0.05, 0.05, 0.05)), false)
	return r

static func cabinet(parent: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	var r := _root(parent, pos, yaw, "Cabinet")
	box(r, Vector3(0.5, 1.3, 0.6), Vector3(0, 0.65, 0), Mats.get_mat("metal_painted", 1.0))
	for i in 4:
		box(r, Vector3(0.12, 0.02, 0.02), Vector3(0, 0.2 + i * 0.3, 0.31), Mats.get_mat("metal"), false)
	return r

static func couch(parent: Node3D, pos: Vector3, yaw := 0.0, color := Color(0.3, 0.2, 0.15)) -> Node3D:
	var r := _root(parent, pos, yaw, "Couch")
	var m := Mats.color(color, 0.9)
	box(r, Vector3(2.0, 0.45, 0.9), Vector3(0, 0.22, 0), m)
	box(r, Vector3(2.0, 0.5, 0.2), Vector3(0, 0.65, -0.35), m, false)
	for sx in [-1, 1]:
		box(r, Vector3(0.2, 0.3, 0.9), Vector3(sx * 0.9, 0.55, 0), m, false)
	return r

static func bed(parent: Node3D, pos: Vector3, yaw := 0.0, hospital := false) -> Node3D:
	var r := _root(parent, pos, yaw, "Bed")
	var frame := Mats.get_mat("metal") if hospital else Mats.get_mat("wood")
	box(r, Vector3(1.0, 0.3, 2.0), Vector3(0, 0.35, 0), frame)
	box(r, Vector3(0.95, 0.18, 1.95), Vector3(0, 0.58, 0), Mats.color(Color(0.8, 0.8, 0.78), 0.95), false)
	box(r, Vector3(0.6, 0.12, 0.35), Vector3(0, 0.72, -0.75), Mats.color(Color(0.9, 0.9, 0.88), 0.95), false)
	box(r, Vector3(1.0, 0.9 if not hospital else 0.6, 0.06), Vector3(0, 0.5, -1.0), frame, false)
	return r

static func vending(parent: Node3D, pos: Vector3, yaw := 0.0, lit := true) -> Node3D:
	var r := _root(parent, pos, yaw, "Vending")
	box(r, Vector3(0.9, 1.9, 0.8), Vector3(0, 0.95, 0), Mats.color(Color(0.55, 0.08, 0.08), 0.4, 0.3))
	box(r, Vector3(0.6, 1.2, 0.02), Vector3(-0.08, 1.15, 0.405), Mats.emissive(Color(0.8, 0.85, 0.9), 1.2) if lit else Mats.get_mat("glass"), false)
	return r

static func trash_bags(parent: Node3D, pos: Vector3, yaw := 0.0, n := 3) -> Node3D:
	var r := _root(parent, pos, yaw, "Trash")
	var m := Mats.color(Color(0.04, 0.04, 0.05), 0.3)
	for i in n:
		sphere(r, 0.32, Vector3(i * 0.45 - n * 0.2, 0.25, (i % 2) * 0.3), m, Vector3(1, 0.75, 0.9))
	return r

static func debris(parent: Node3D, pos: Vector3, yaw := 0.0, n := 6, mat := "concrete") -> Node3D:
	var r := _root(parent, pos, yaw, "Debris")
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 31 + pos.z * 17)
	for i in n:
		var s := Vector3(rng.randf_range(0.2, 0.8), rng.randf_range(0.1, 0.35), rng.randf_range(0.2, 0.7))
		box(r, s, Vector3(rng.randf_range(-1.0, 1.0), s.y * 0.4, rng.randf_range(-1.0, 1.0)), Mats.get_mat(mat, 1.0), false, Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4)))
	return r

static func papers(parent: Node3D, pos: Vector3, n := 6) -> Node3D:
	var r := _root(parent, pos, 0.0, "Papers")
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 13 + pos.z * 29)
	for i in n:
		box(r, Vector3(0.21, 0.004, 0.29), Vector3(rng.randf_range(-0.8, 0.8), 0.01 + i * 0.002, rng.randf_range(-0.8, 0.8)), Mats.get_mat("paper"), false, Vector3(0, rng.randf() * TAU, 0))
	return r

static func blood_pool(parent: Node3D, pos: Vector3, size := 1.2) -> Node3D:
	var r := _root(parent, pos, randf() * TAU, "Blood")
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = size * 0.5
	cm.bottom_radius = size * 0.5
	cm.height = 0.005
	mi.mesh = cm
	mi.material_override = Mats.get_mat("blood")
	mi.position.y = 0.006
	mi.scale = Vector3(1, 1, 0.65)
	r.add_child(mi)
	return r

static func corpse(parent: Node3D, pos: Vector3, yaw := 0.0, cfg := {}) -> Node3D:
	var H = load("res://actors/humanoid.gd")
	var r := _root(parent, pos, yaw, "Corpse")
	var h: Node3D = H.new()
	var c := {"zombie": false, "bloody": 1.0, "skin": Color(0.62, 0.55, 0.5), "shirt": Color(0.2, 0.25, 0.4)}
	c.merge(cfg, true)
	h.setup(c)
	h.pose = "dead"
	r.add_child(h)
	blood_pool(r, Vector3(0, 0, -0.4), 1.6)
	return r

# ------------------------------------------------------------------ exterior
static func car(parent: Node3D, pos: Vector3, yaw := 0.0, color := Color(0.25, 0.28, 0.3), wrecked := false, kind := "sedan") -> Node3D:
	var r := _root(parent, pos, yaw, "Car")
	var body := Mats.color(color, 0.25, 0.6)
	body.clearcoat_enabled = true
	body.clearcoat = 0.6
	var glass := Mats.color(Color(0.05, 0.07, 0.09, 0.85), 0.05, 0.2)
	var tire := Mats.get_mat("rubber")
	var L := 4.5
	var H := 0.75
	var roof_h := 0.6
	if kind == "van" or kind == "ambulance":
		L = 5.4; roof_h = 1.25
	elif kind == "police":
		color = Color(0.05, 0.05, 0.07)
	box(r, Vector3(1.85, H, L), Vector3(0, 0.35 + H * 0.5, 0), body)
	var cab_len := L * 0.5 if kind == "sedan" or kind == "police" else L * 0.85
	var cab_z := -0.2 if kind == "sedan" or kind == "police" else -0.25
	box(r, Vector3(1.7, roof_h, cab_len), Vector3(0, 0.35 + H + roof_h * 0.5, cab_z), body, true)
	box(r, Vector3(1.72, roof_h * 0.7, cab_len * 0.92), Vector3(0, 0.35 + H + roof_h * 0.45, cab_z), glass, false)
	if kind == "ambulance":
		var white := Mats.color(Color(0.88, 0.88, 0.86), 0.35, 0.3)
		box(r, Vector3(1.95, 1.95, 3.4), Vector3(0, 0.35 + 0.98, -0.9), white)
		box(r, Vector3(1.97, 0.18, 3.42), Vector3(0, 0.35 + 0.9, -0.9), Mats.color(Color(0.8, 0.1, 0.08), 0.5), false)
		box(r, Vector3(1.2, 0.12, 0.3), Vector3(0, 2.38, 0.8), Mats.emissive(Color(1, 0.15, 0.1), 2.0), false)
	if kind == "police":
		box(r, Vector3(1.86, 0.3, 1.4), Vector3(0, 0.35 + H * 0.6, 0.8), Mats.color(Color(0.9, 0.9, 0.9), 0.3, 0.3), false)
		box(r, Vector3(1.1, 0.1, 0.25), Vector3(-0.3, 0.35 + H + roof_h + 0.05, cab_z), Mats.emissive(Color(1, 0.1, 0.1), 2.0), false)
		box(r, Vector3(1.1, 0.1, 0.25), Vector3(0.3, 0.35 + H + roof_h + 0.05, cab_z), Mats.emissive(Color(0.1, 0.3, 1), 2.0), false)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			cyl(r, 0.36, 0.25, Vector3(sx * 0.85, 0.36, sz * L * 0.32), tire, false, -1.0, Vector3(0, 0, PI * 0.5))
	# lights
	for sx in [-1, 1]:
		box(r, Vector3(0.35, 0.12, 0.04), Vector3(sx * 0.65, 0.85, L * 0.5), Mats.emissive(Color(0.9, 0.9, 0.8), 0.6 if not wrecked else 0.0), false)
		box(r, Vector3(0.3, 0.12, 0.04), Vector3(sx * 0.7, 0.85, -L * 0.5), Mats.emissive(Color(0.6, 0.02, 0.02), 1.0), false)
	if wrecked:
		r.rotation.z = randf_range(-0.06, 0.06)
		var snow := Mats.get_mat("snow")
		box(r, Vector3(1.6, 0.06, cab_len * 0.9), Vector3(0, 0.35 + H + roof_h + 0.03, cab_z), snow, false)
	return r

static func tree(parent: Node3D, pos: Vector3, h := 9.0, seed := 0) -> Node3D:
	## Bare winter tree: trunk + recursively branching limbs.
	var r := _root(parent, pos, 0.0, "Tree")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else int(pos.x * 97 + pos.z * 53)
	var bark := Mats.get_mat("bark", 1.2)
	var trunk_r := h * 0.045
	cyl(r, trunk_r * 1.3, h * 0.45, Vector3(0, h * 0.225, 0), bark, true, trunk_r, Vector3.ZERO, 10)
	_branch(r, Vector3(0, h * 0.42, 0), Vector3.UP, h * 0.4, trunk_r, 0, rng, bark)
	return r

static func _branch(r: Node3D, from: Vector3, dir: Vector3, length: float, radius: float, depth: int, rng: RandomNumberGenerator, mat: Material) -> void:
	if depth > 3 or length < 0.3:
		return
	var n := 3 if depth < 2 else 2
	for i in n:
		var d := (dir + Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(0.1, 0.6), rng.randf_range(-0.9, 0.9)) * (0.7 if depth > 0 else 0.55)).normalized()
		if i == 0 and depth == 0:
			d = (dir + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))).normalized()
		var to := from + d * length
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.bottom_radius = radius
		cm.top_radius = radius * 0.6
		cm.height = length
		cm.radial_segments = 7
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = mat
		r.add_child(mi)
		mi.position = (from + to) * 0.5
		var up := d
		var side := up.cross(Vector3.FORWARD if abs(up.z) < 0.95 else Vector3.RIGHT).normalized()
		mi.basis = Basis(side, up, side.cross(up)).orthonormalized()
		_branch(r, to, d, length * 0.62, radius * 0.6, depth + 1, rng, mat)

static func lamp_post(parent: Node3D, pos: Vector3, yaw := 0.0, on := true, color := Color(1.0, 0.75, 0.45)) -> Node3D:
	var r := _root(parent, pos, yaw, "LampPost")
	var m := Mats.get_mat("metal_painted", 1.0)
	cyl(r, 0.09, 5.5, Vector3(0, 2.75, 0), m, true, 0.06)
	box(r, Vector3(0.12, 0.1, 1.2), Vector3(0, 5.45, 0.55), m, false)
	box(r, Vector3(0.35, 0.12, 0.5), Vector3(0, 5.35, 1.1), Mats.emissive(color, 4.0) if on else m, false)
	if on:
		var l := SpotLight3D.new()
		l.light_color = color
		l.light_energy = 6.0
		l.spot_range = 14.0
		l.spot_angle = 55.0
		l.shadow_enabled = true
		l.light_volumetric_fog_energy = 1.5
		l.position = Vector3(0, 5.2, 1.1)
		l.rotation.x = -PI * 0.5
		r.add_child(l)
	return r

static func fence(parent: Node3D, a: Vector3, b: Vector3, h := 2.2, mat := "metal") -> Node3D:
	## Chain-link style fence from a to b (world positions relative to parent).
	var r := _root(parent, a, 0.0, "Fence")
	var d := b - a
	var len := Vector2(d.x, d.z).length()
	r.rotation.y = atan2(d.x, d.z)
	var post := Mats.get_mat(mat, 1.0)
	var mesh_m := Mats.color(Color(0.4, 0.42, 0.44, 0.55), 0.5, 0.8)
	var n := int(ceil(len / 3.0))
	for i in n + 1:
		cyl(r, 0.04, h, Vector3(0, h * 0.5, i * len / n), post, false)
	box(r, Vector3(0.03, h - 0.1, len), Vector3(0, h * 0.5, len * 0.5), mesh_m, true)
	cyl(r, 0.03, len, Vector3(0, h, len * 0.5), post, false, -1.0, Vector3(PI * 0.5, 0, 0))
	return r

static func bench(parent: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	var r := _root(parent, pos, yaw, "Bench")
	var w := Mats.get_mat("wood", 0.6)
	var m := Mats.get_mat("metal_painted", 1.0)
	box(r, Vector3(1.8, 0.05, 0.45), Vector3(0, 0.45, 0), w)
	box(r, Vector3(1.8, 0.35, 0.05), Vector3(0, 0.75, -0.22), w, false)
	for sx in [-1, 1]:
		box(r, Vector3(0.06, 0.45, 0.45), Vector3(sx * 0.8, 0.22, 0), m, false)
	return r

static func shed(parent: Node3D, pos: Vector3, yaw := 0.0, size := Vector3(3.2, 2.6, 3.6)) -> Node3D:
	## Corrugated tool shed like in the reference art (door on +Z side).
	var r := _root(parent, pos, yaw, "Shed")
	var c := Mats.get_mat("corrugated", 1.2)
	var t := 0.08
	box(r, Vector3(size.x, size.y, t), Vector3(0, size.y * 0.5, -size.z * 0.5), c)
	box(r, Vector3(t, size.y, size.z), Vector3(-size.x * 0.5, size.y * 0.5, 0), c)
	box(r, Vector3(t, size.y, size.z), Vector3(size.x * 0.5, size.y * 0.5, 0), c)
	var dw := 1.1
	box(r, Vector3((size.x - dw) * 0.5, size.y, t), Vector3(-(size.x + dw) * 0.25, size.y * 0.5, size.z * 0.5), c)
	box(r, Vector3((size.x - dw) * 0.5, size.y, t), Vector3((size.x + dw) * 0.25, size.y * 0.5, size.z * 0.5), c)
	box(r, Vector3(dw, size.y - 2.1, t), Vector3(0, 2.1 + (size.y - 2.1) * 0.5, size.z * 0.5), c)
	# pitched roof
	var roof := Mats.get_mat("metal_rust", 1.5)
	var half := size.x * 0.5 + 0.2
	var slope := 0.45
	for sx in [-1, 1]:
		box(r, Vector3(half / cos(slope), 0.06, size.z + 0.4), Vector3(sx * half * 0.5, size.y + tan(slope) * half * 0.5, 0), roof, true, Vector3(0, 0, -sx * slope))
	return r

static func statue(parent: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	## Weathered goddess statue on a plinth (main hall centrepiece).
	var r := _root(parent, pos, yaw, "Statue")
	var stone := Mats.get_mat("marble", 1.5)
	box(r, Vector3(1.6, 1.0, 1.6), Vector3(0, 0.5, 0), stone)
	box(r, Vector3(1.3, 0.15, 1.3), Vector3(0, 1.07, 0), stone, false)
	cyl(r, 0.35, 1.6, Vector3(0, 1.95, 0), stone, false, 0.2)
	sphere(r, 0.2, Vector3(0, 2.95, 0), stone, Vector3(0.9, 1.1, 0.9))
	box(r, Vector3(1.0, 0.12, 0.15), Vector3(0, 2.4, 0.15), stone, false, Vector3(0, 0, 0.3))
	sphere(r, 0.12, Vector3(0.45, 2.6, 0.2), stone)
	return r

static func sign(parent: Node3D, pos: Vector3, yaw: float, text: String, size := 64, color := Color(0.9, 0.9, 0.85), bg := true) -> Node3D:
	var r := _root(parent, pos, yaw, "Sign")
	if bg:
		box(r, Vector3(text.length() * size * 0.0028 + 0.2, size * 0.006 + 0.1, 0.03), Vector3(0, 0, -0.02), Mats.color(Color(0.08, 0.1, 0.12), 0.6), false)
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	r.add_child(l)
	return r

static func pipe(parent: Node3D, a: Vector3, b: Vector3, radius := 0.08, mat := "metal_rust") -> Node3D:
	var r := _root(parent, (a + b) * 0.5, 0.0, "Pipe")
	var d := b - a
	var mi := cyl(r, radius, d.length(), Vector3.ZERO, Mats.get_mat(mat, 1.0), false, -1.0, Vector3.ZERO, 10)
	var up := d.normalized()
	var side := up.cross(Vector3.FORWARD if abs(up.z) < 0.95 else Vector3.RIGHT).normalized()
	mi.basis = Basis(side, up, side.cross(up)).orthonormalized()
	return r

static func window(parent: Node3D, pos: Vector3, yaw := 0.0, w := 1.4, h := 1.8, lit := false) -> Node3D:
	## Window decal for building facades: frame + mullions + dark glass. Not solid.
	var r := _root(parent, pos, yaw, "Window")
	var frame := Mats.color(Color(0.75, 0.75, 0.72), 0.6)
	var glass := Mats.emissive(Color(0.9, 0.7, 0.4), 0.8) if lit else Mats.color(Color(0.03, 0.04, 0.05), 0.05, 0.5)
	box(r, Vector3(w, h, 0.04), Vector3(0, 0, 0), glass, false)
	box(r, Vector3(w + 0.14, 0.1, 0.12), Vector3(0, h * 0.5, 0.02), frame, false)
	box(r, Vector3(w + 0.2, 0.1, 0.2), Vector3(0, -h * 0.5, 0.06), frame, false)
	for sx in [-1, 1]:
		box(r, Vector3(0.08, h, 0.1), Vector3(sx * w * 0.5, 0, 0.02), frame, false)
	for i in range(1, 3):
		box(r, Vector3(0.035, h, 0.05), Vector3(-w * 0.5 + w * i / 3.0, 0, 0.03), frame, false)
		box(r, Vector3(w, 0.035, 0.05), Vector3(0, -h * 0.5 + h * i / 3.0, 0.03), frame, false)
	return r
