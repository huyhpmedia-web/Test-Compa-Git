extends RefCounted
## Prop library. Every function: (parent: Node3D, pos: Vector3, yaw: float = 0.0, ...) -> Node3D
## Props with `solid` get StaticBody3D box colliders on layer 1 (world).
## Level authors may add their own local props; keep generic ones here.

const Mats = preload("res://core/mats.gd")
const Gore = preload("res://world/gore.gd")
const Env = preload("res://world/env_assets.gd")
const FireFX = preload("res://world/fire_fx.gd")

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
	var gk := Env.spawn(parent, "camp/crate_wood_0%d" % (1 + int(abs(pos.x * 7 + pos.z * 3)) % 2), pos, yaw, {"name": "Crate", "fit_len": s * 1.0, "collide": Vector3(s, s, s) * 0.95})
	if gk:
		return gk
	var r := _root(parent, pos, yaw, "Crate")
	box(r, Vector3(s, s, s), Vector3(0, s * 0.5, 0), Mats.get_mat("wood", 0.8))
	return r

static func barrel(parent: Node3D, pos: Vector3, yaw := 0.0, rusty := true) -> Node3D:
	var gb := Env.spawn(parent, "camp/barrel", pos, yaw, {"name": "Barrel", "tint": Color(0.75, 0.55, 0.4) if rusty else Color(0.5, 0.58, 0.6), "collide": "cyl", "cyl_r": 0.3})
	if gb:
		return gb
	var r := _root(parent, pos, yaw, "Barrel")
	cyl(r, 0.3, 0.9, Vector3(0, 0.45, 0), Mats.get_mat("metal_rust" if rusty else "metal_painted", 0.6))
	return r

static func desk(parent: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	var gd := Env.spawn(parent, "interior/desk", pos, yaw, {"name": "Desk", "snow": 0.0, "scale": 0.85, "collide": Vector3(1.7, 0.8, 0.8)})
	if gd:
		# monitor + papers on top (the model itself is a bare steel desk)
		box(gd, Vector3(0.5, 0.32, 0.04), Vector3(0.3, 1.0, -0.2), Mats.color(Color(0.05, 0.05, 0.06), 0.3), false)
		box(gd, Vector3(0.46, 0.27, 0.01), Vector3(0.3, 1.0, -0.177), Mats.emissive(Color(0.05, 0.12, 0.18), 0.6), false)
		box(gd, Vector3(0.25, 0.01, 0.32), Vector3(-0.45, 0.68, 0.1), Mats.get_mat("paper"), false, Vector3(0, 0.3, 0))
		return gd
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
	var gc := Env.spawn(parent, "interior/chair_0%d" % (1 + int(abs(pos.x * 5 + pos.z)) % 2), pos, yaw, {"name": "Chair", "snow": 0.0, "collide": Vector3(0.5, 0.9, 0.5), "rot": Vector3(1.45 if toppled else 0.0, 0, 0)})
	if gc:
		if toppled:
			gc.position.y += 0.25
		return gc
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
	if Env.has("interior/bookshelf") and h > 1.6:
		var gs := _root(parent, pos, yaw, "Shelf")
		var n := maxi(1, int(round(w / 1.37)))
		for i in n:
			Env.spawn(gs, "interior/bookshelf", Vector3((i - (n - 1) * 0.5) * 1.37, 0, 0), 0.0, {"snow": 0.0, "fit_h": h})
		return gs
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
	var gcb := Env.spawn(parent, "interior/drawer_cabinet", pos, yaw, {"name": "Cabinet", "snow": 0.0, "fit_h": 1.35})
	if gcb:
		return gcb
	var r := _root(parent, pos, yaw, "Cabinet")
	box(r, Vector3(0.5, 1.3, 0.6), Vector3(0, 0.65, 0), Mats.get_mat("metal_painted", 1.0))
	for i in 4:
		box(r, Vector3(0.12, 0.02, 0.02), Vector3(0, 0.2 + i * 0.3, 0.31), Mats.get_mat("metal"), false)
	return r

static func couch(parent: Node3D, pos: Vector3, yaw := 0.0, color := Color(0.3, 0.2, 0.15)) -> Node3D:
	var gco := Env.spawn(parent, "interior/sofa_0%d" % (2 + int(abs(pos.x + pos.z)) % 2), pos, yaw, {"name": "Couch", "snow": 0.0, "tint": Color(0.7, 0.7, 0.7).lerp(color * 2.5, 0.35)})
	if gco:
		return gco
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
	if Env.spawn(r, "interior/bed_frame", Vector3.ZERO, 0.0, {"snow": 0.0, "tint": Color(0.75, 0.8, 0.82) if hospital else Color.WHITE, "collide": Vector3(0.95, 0.5, 2.0)}) == null:
		box(r, Vector3(1.0, 0.3, 2.0), Vector3(0, 0.35, 0), frame)
	box(r, Vector3(0.95, 0.18, 1.95), Vector3(0, 0.58, 0), Mats.color(Color(0.8, 0.8, 0.78), 0.95), false)
	box(r, Vector3(0.6, 0.12, 0.35), Vector3(0, 0.72, -0.75), Mats.color(Color(0.9, 0.9, 0.88), 0.95), false)
	if not Env.has("interior/bed_frame"):
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
	var names := ["pool_a", "pool_b", "pool_c"]
	var d := Gore.decal(r, names[randi() % 3], Vector3(0, 0.0, 0), Vector3.UP, size * 1.5, Vector3.RIGHT, {"local": true, "depth": 0.3})
	if d == null:
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
	var CM = load("res://actors/character_model.gd")
	var r := _root(parent, pos, yaw, "Corpse")
	var h: Node3D = CM.new()
	# frozen, mauled victims: the MakeHuman Rimebound bodies lying in a (random) dead pose
	var c := {"zombie": true, "seed": hash(Vector3(pos.x, pos.y, pos.z)), "death_variant": int(abs(hash(pos.x * 7.0 + pos.z)) % 4)}
	for k in cfg:
		if k in ["model", "body", "seed", "death_variant", "scale", "height"]:
			c[k] = cfg[k]
	h.setup(c)
	h.pose = "dead"
	r.add_child(h)
	blood_pool(r, Vector3(0, 0, -0.4), 1.6)
	return r

# ------------------------------------------------------------------ exterior
static func car(parent: Node3D, pos: Vector3, yaw := 0.0, color := Color(0.25, 0.28, 0.3), wrecked := false, kind := "sedan") -> Node3D:
	var gcar := _glb_car(parent, pos, yaw, color, wrecked, kind)
	if gcar:
		return gcar
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
	## Bare winter tree: generated skin (assets/env/trees/bare_N.glb) with a high-detail model and a cheap LOD.
	var gt := _glb_bare_tree(parent, pos, h, seed)
	if gt:
		return gt
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
	if Env.has("street/lamp_01"):
		return _glb_lamp(parent, pos, yaw, on, color)
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
	if Env.has("street/fence_post"):
		return _glb_fence(parent, a, b, h)
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
	var gbn := Env.spawn(parent, "interior/sofa_02", pos, yaw + PI, {"name": "Bench", "snow": 0.3, "scale": 0.95, "tint": Color(0.75, 0.78, 0.8)})
	if gbn:
		return gbn
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

static var _win_mats := {}
static func _wm(key: String) -> StandardMaterial3D:
	if not _win_mats.has(key):
		var m: StandardMaterial3D
		match key:
			"trim":
				m = Mats.color(Color(0.62, 0.6, 0.55), 0.75)
			"trim_dark":
				m = Mats.color(Color(0.16, 0.15, 0.15), 0.6, 0.2)
			"stone":
				m = Mats.get_mat("concrete", 1.0)
			"glass":
				m = Mats.color(Color(0.02, 0.03, 0.045), 0.04, 0.6)
			"curtain":
				m = Mats.color(Color(0.1, 0.08, 0.07), 0.95)
			"frost":
				m = Mats.color(Color(0.82, 0.88, 0.94, 0.55), 0.4)
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_:
				m = Mats.get_mat("snow")
		_win_mats[key] = m
	return _win_mats[key]

static func window(parent: Node3D, pos: Vector3, yaw := 0.0, w := 1.4, h := 1.8, lit := false) -> Node3D:
	## Window unit for building facades: proud casing, stone sill + lintel, glazing bars, frosted lower pane, curtain, snow on the sill.
	## Local +Z points out of the wall. Not solid.
	var r := _root(parent, pos, yaw, "Window")
	var glass: Material = Mats.emissive(Color(0.95, 0.68, 0.32), 0.9) if lit else _wm("glass")
	var trim := _wm("trim")
	box(r, Vector3(w, h, 0.03), Vector3(0, 0, 0.0), glass, false)
	if not lit:
		box(r, Vector3(w * 0.94, h * 0.92, 0.01), Vector3(0, 0, -0.01), _wm("curtain"), false)
	# casing: four boards standing 14 cm proud
	box(r, Vector3(0.09, h + 0.1, 0.14), Vector3(-w * 0.5 - 0.02, 0, 0.06), trim, false)
	box(r, Vector3(0.09, h + 0.1, 0.14), Vector3(w * 0.5 + 0.02, 0, 0.06), trim, false)
	box(r, Vector3(w + 0.2, 0.09, 0.14), Vector3(0, h * 0.5 + 0.03, 0.06), trim, false)
	box(r, Vector3(w + 0.2, 0.08, 0.1), Vector3(0, -h * 0.5 - 0.02, 0.05), trim, false)
	# transom bar + muntins
	box(r, Vector3(w, 0.06, 0.1), Vector3(0, h * 0.18, 0.04), trim, false)
	box(r, Vector3(0.05, h, 0.09), Vector3(0, 0, 0.04), trim, false)
	if w > 1.2:
		for sx in [-1, 1]:
			box(r, Vector3(0.025, h, 0.07), Vector3(sx * w * 0.25, 0, 0.03), trim, false)
	# frost creeping up the lower pane
	box(r, Vector3(w * 0.96, h * 0.28, 0.02), Vector3(0, -h * 0.34, 0.03), _wm("frost"), false)
	# stone sill (projects 22 cm) + lintel
	box(r, Vector3(w + 0.34, 0.08, 0.26), Vector3(0, -h * 0.5 - 0.1, 0.12), _wm("stone"), false)
	box(r, Vector3(w + 0.26, 0.07, 0.2), Vector3(0, -h * 0.5 - 0.17, 0.08), _wm("stone"), false)
	box(r, Vector3(w + 0.36, 0.16, 0.2), Vector3(0, h * 0.5 + 0.17, 0.1), _wm("stone"), false)
	# snow loaded on the sill
	var sn := box(r, Vector3(w + 0.2, 0.07, 0.2), Vector3(0, -h * 0.5 - 0.03, 0.13), _wm("snow"), false)
	sn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in r.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).visibility_range_end = 90.0
	return r

## Projecting cornice band with a snow cap, running along x from x0..x1 at height y on a wall whose outward normal is `out` (+1/-1 on z).
static func cornice(parent: Node3D, x0: float, x1: float, y: float, zf: float, out := 1.0, depth := 0.45, mat := "concrete") -> Node3D:
	var r := _root(parent, Vector3((x0 + x1) * 0.5, y, zf), 0.0, "Cornice")
	var w := x1 - x0
	var m := Mats.get_mat(mat, 1.5)
	box(r, Vector3(w + 0.3, 0.22, 0.2), Vector3(0, 0, out * 0.1), m, false)
	box(r, Vector3(w + 0.4, 0.12, depth * 0.8), Vector3(0, 0.17, out * depth * 0.4), m, false)
	box(r, Vector3(w + 0.5, 0.1, depth), Vector3(0, 0.28, out * depth * 0.5), m, false)
	# dentils
	var n := int(w / 0.5)
	for i in n:
		box(r, Vector3(0.18, 0.14, 0.14), Vector3(-w * 0.5 + (i + 0.5) * w / n, -0.16, out * 0.22), m, false)
	var sn := box(r, Vector3(w + 0.55, 0.09, depth * 1.02), Vector3(0, 0.37, out * depth * 0.5), _wm("snow"), false)
	sn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return r

## Gutter + downpipe along a wall edge (Poly Haven gutter pieces scaled) - simple tube version.
static func gutter(parent: Node3D, a: Vector3, b: Vector3, drop := 0.0) -> Node3D:
	var r := _root(parent, (a + b) * 0.5, atan2(b.x - a.x, b.z - a.z), "Gutter")
	var len := Vector2(b.x - a.x, b.z - a.z).length()
	var m := Mats.get_mat("metal_painted", 1.0)
	var g := box(r, Vector3(0.1, 0.1, len), Vector3(0, 0, 0), m, false)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if drop > 0.0:
		cyl(r, 0.04, drop, Vector3(0, -drop * 0.5, len * 0.5 - 0.1), m, false, -1.0, Vector3.ZERO, 8)
	return r

# ================================================================== GORE / HORROR PROPS
# (world/gore.gd supplies decals, fluids and gib meshes)

static func _mi(r: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	r.add_child(mi)
	return mi

static func _cylm(rt: float, rb: float, h: float, segs := 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c

## Local-space decal helper for props: texture name, local pos, width.
static func _d(r: Node3D, name: String, pos: Vector3, width: float, normal := Vector3.UP, tangent := Vector3.RIGHT, ichor := false, roll := -1.0) -> Decal:
	return Gore.decal(r, name, pos, normal, width, tangent, {"local": true, "ichor": ichor, "roll": randf() * TAU if roll < 0.0 else roll, "depth": 0.3})

static func _pool_at(r: Node3D, pos: Vector3, size: float, ichor := false) -> Decal:
	var n := ["pool_a", "pool_b", "pool_c"]
	return _d(r, n[randi() % 3], pos, size, Vector3.UP, Vector3.RIGHT, ichor)

static func _no_pool(c: Node3D) -> void:
	for ch in c.get_children():
		if ch.name == "Blood":
			ch.queue_free()

## Frozen rime coating over every mesh below `n`.
static func frost_overlay(n: Node, amount := 0.45) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.82, 0.9, 0.97, amount)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.55
	m.metallic_specular = 0.8
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = m

## A dead person in a given pose ("dead" | "sit" | "normal") - wraps Props.corpse so it follows
## whatever human model corpse() currently builds.
static func corpse_pose(parent: Node3D, pos: Vector3, yaw := 0.0, cfg := {}, pose := "dead", pool := true) -> Node3D:
	var c := corpse(parent, pos, yaw, cfg)
	if not pool:
		_no_pool(c)
	if pose != "dead" and c.get_child_count() > 0:
		var h = c.get_child(0)
		if h != null and h.get("pose") != null:
			h.pose = pose
	return c

static func body_bag(parent: Node3D, pos: Vector3, yaw := 0.0, open := false, bloody := true) -> Node3D:
	var r := _root(parent, pos, yaw, "BodyBag")
	var plastic := Mats.color(Color(0.055, 0.062, 0.07), 0.26)
	plastic.clearcoat_enabled = true
	plastic.clearcoat = 0.5
	plastic.clearcoat_roughness = 0.25
	var cm := CapsuleMesh.new()
	cm.radius = 0.23
	cm.height = 1.85
	cm.radial_segments = 18
	_mi(r, cm, plastic, Vector3(0, 0.13, 0), Vector3(PI * 0.5, 0, 0), Vector3(1, 1, 0.55))
	# the lumps of the body inside
	for b in [[0.0, 0.36, 0.2, 0.12, 0.26], [0.0, -0.3, 0.2, 0.12, 0.3], [0.0, -0.75, 0.16, 0.1, 0.28], [0.0, 0.7, 0.13, 0.11, 0.13]]:
		_mi(r, SphereMesh.new(), plastic, Vector3(b[0], 0.12, b[1]), Vector3.ZERO, Vector3(b[2] * 2.0, b[3] * 2.0 + 0.1, b[4] * 2.0))
	box(r, Vector3(0.025, 0.012, 1.55), Vector3(0, 0.262, -0.05), Mats.get_mat("metal"), false)
	if open:
		box(r, Vector3(0.1, 0.01, 0.8), Vector3(0, 0.258, 0.4), Mats.color(Color(0.01, 0.01, 0.012), 0.5), false)
		_mi(r, SphereMesh.new(), Mats.color(Color(0.6, 0.58, 0.52), 0.55), Vector3(0, 0.22, 0.72), Vector3.ZERO, Vector3(0.2, 0.22, 0.25))
		_mi(r, SphereMesh.new(), Mats.color(Color(0.08, 0.05, 0.04), 0.7), Vector3(0, 0.25, 0.82), Vector3.ZERO, Vector3(0.18, 0.1, 0.12))
	box(r, Vector3(0.5, 0.3, 1.9), Vector3(0, 0.15, 0), plastic, true).visible = false
	if bloody:
		_pool_at(r, Vector3(0.1, 0.0, 0.0), 2.0)
		_d(r, "splat_b", Vector3(0.03, 0.26, 0.15), 0.8, Vector3.UP, Vector3.RIGHT)
		_d(r, "smear_a", Vector3(0.22, 0.12, -0.3), 0.9, Vector3.RIGHT, Vector3.BACK)
	return r

## Chunks of viscera: intestine coils, organs and a pool. Use sparingly near corpses.
static func gut_pile(parent: Node3D, pos: Vector3, yaw := 0.0, size := 1.0) -> Node3D:
	var r := _root(parent, pos, yaw, "Viscera")
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 41 + pos.z * 23 + 7)
	_pool_at(r, Vector3.ZERO, 1.7 * size)
	for k in 3:
		var pts := PackedVector3Array()
		var cx := rng.randf_range(-0.12, 0.12) * size
		var cz := rng.randf_range(-0.12, 0.12) * size
		var a0 := rng.randf() * TAU
		for i in 30:
			var a := a0 + i * 0.5
			var rad := (0.07 + 0.11 * (0.5 + 0.5 * sin(i * 0.37 + k * 1.3))) * size
			pts.append(Vector3(cx + cos(a) * rad, 0.028 + 0.022 * sin(i * 0.8 + k), cz + sin(a) * rad))
		# trailing end dragging away
		var ang := rng.randf() * TAU
		var last := pts[pts.size() - 1]
		for j in 10:
			pts.append(last + Vector3(cos(ang) * j * 0.1 * size, 0.02 + 0.01 * sin(j), sin(ang) * j * 0.1 * size + 0.04 * sin(j * 0.8)))
		var m: Material = Gore.mat_gut() if k < 2 else Mats.color(Color(0.34, 0.09, 0.11), 0.14)
		_mi(r, Gore.tube_mesh(pts, 0.036 * size, 10, 0.2), m)
	_mi(r, Gore.chunk_mesh(0), Mats.color(Color(0.2, 0.035, 0.045), 0.18), Vector3(0.18 * size, 0.04, -0.1 * size), Vector3(0, 0.6, 0), Vector3(0.3, 0.1, 0.18) * size)
	_mi(r, Gore.chunk_mesh(3), Mats.color(Color(0.55, 0.3, 0.3), 0.2), Vector3(-0.16 * size, 0.035, 0.12 * size), Vector3(0, 2.0, 0), Vector3(0.2, 0.08, 0.14) * size)
	_mi(r, Gore.chunk_mesh(5), Gore.mat_flesh(), Vector3(0.0, 0.03, 0.22 * size), Vector3(0, 1.0, 0), Vector3(0.14, 0.06, 0.1) * size)
	return r

## Upper body torn from its legs: ribs, spine stub, intestines and a drag smear.
static func torso(parent: Node3D, pos: Vector3, yaw := 0.0, shirt := Color(0.28, 0.1, 0.1)) -> Node3D:
	var r := _root(parent, pos, yaw, "Torso")
	var cloth := Mats.color(shirt, 0.95)
	var skin := Mats.color(Color(0.56, 0.5, 0.45), 0.55)
	_pool_at(r, Vector3(0, 0.0, 0.1), 2.3)
	_d(r, "drag_a", Vector3(0, 0.0, 1.3), 1.9, Vector3.UP, Vector3.BACK)
	_mi(r, _cylm(0.17, 0.14, 0.58, 14), cloth, Vector3(0, 0.16, -0.05), Vector3(PI * 0.5, 0, 0), Vector3(1.25, 1, 0.8))
	# shoulders / arm stubs
	for sx in [-1, 1]:
		_mi(r, _cylm(0.05, 0.045, 0.22, 8), skin, Vector3(sx * 0.27, 0.12, -0.28), Vector3(0, 0, PI * 0.5 + sx * 0.3))
		_mi(r, Gore.chunk_mesh(1), Gore.mat_flesh(), Vector3(sx * 0.37, 0.1, -0.28), Vector3.ZERO, Vector3(0.09, 0.08, 0.09))
	# neck end: ragged flesh, spine, windpipe
	_mi(r, Gore.chunk_mesh(2), Gore.mat_flesh(), Vector3(0, 0.16, -0.36), Vector3.ZERO, Vector3(0.3, 0.22, 0.12))
	_mi(r, _cylm(0.018, 0.02, 0.1, 8), Gore.mat_bone(), Vector3(0, 0.2, -0.4), Vector3(PI * 0.5, 0, 0))
	_mi(r, _cylm(0.012, 0.012, 0.08, 8), Gore.mat_flesh_pale(), Vector3(0.04, 0.19, -0.42), Vector3(PI * 0.5, 0, 0))
	# belly end: torn open
	_mi(r, Gore.chunk_mesh(4), Gore.mat_flesh(), Vector3(0, 0.15, 0.27), Vector3.ZERO, Vector3(0.34, 0.2, 0.16))
	for i in 5:
		for sx in [-1, 1]:
			_mi(r, CapsuleMesh.new(), Gore.mat_bone(), Vector3(sx * 0.14, 0.2 + i * 0.012, 0.2 - i * 0.07), Vector3(0.1, 0, sx * (0.9 + 0.05 * i)), Vector3(0.016, 0.07, 0.016))
	_mi(r, _cylm(0.02, 0.022, 0.16, 8), Gore.mat_bone(), Vector3(0, 0.12, 0.34), Vector3(PI * 0.5, 0, 0))
	gut_pile(r, Vector3(0.1, 0.0, 0.62), 0.8, 0.9)
	box(r, Vector3(0.5, 0.25, 0.9), Vector3(0, 0.12, 0), cloth, false).visible = false
	return r

static func severed_limb(parent: Node3D, pos: Vector3, yaw := 0.0, kind := "arm") -> Node3D:
	var r := _root(parent, pos, yaw, "Limb")
	var skin := Mats.color(Color(0.55, 0.5, 0.44), 0.5)
	var arm := kind == "arm"
	var L := 0.62 if arm else 0.9
	var rad := 0.042 if arm else 0.07
	_pool_at(r, Vector3(0, 0.0, L * 0.4), 1.1 if arm else 1.5)
	var cloth := Mats.color(Color(0.2, 0.22, 0.3) if arm else Color(0.12, 0.13, 0.2), 0.95)
	_mi(r, _cylm(rad, rad * 0.75, L, 10), skin, Vector3(0, rad, 0), Vector3(PI * 0.5, 0, randf_range(-0.2, 0.2)))
	_mi(r, _cylm(rad * 1.2, rad * 1.1, L * 0.6, 10), cloth, Vector3(0, rad * 1.05, L * 0.2), Vector3(PI * 0.5, 0, 0))
	# cut end
	_mi(r, Gore.chunk_mesh(3), Gore.mat_flesh(), Vector3(0, rad, L * 0.5), Vector3.ZERO, Vector3(rad * 2.4, rad * 2.0, rad * 1.5))
	_mi(r, _cylm(rad * 0.3, rad * 0.34, rad * 1.6, 8), Gore.mat_bone(), Vector3(0, rad, L * 0.5 + rad * 0.5), Vector3(PI * 0.5, 0, 0))
	if arm:
		_mi(r, Gore.chunk_mesh(4), skin, Vector3(0, 0.03, -L * 0.54), Vector3.ZERO, Vector3(0.1, 0.045, 0.11))
		for i in 4:
			_mi(r, _cylm(0.008, 0.007, 0.07, 6), skin, Vector3((i - 1.5) * 0.02, 0.03, -L * 0.54 - 0.08), Vector3(PI * 0.5 + randf_range(-0.3, 0.3), randf_range(-0.2, 0.2), 0))
	else:
		_mi(r, BoxMesh.new(), Mats.color(Color(0.08, 0.07, 0.07), 0.8), Vector3(0, 0.05, -L * 0.52), Vector3.ZERO, Vector3(0.1, 0.1, 0.27))
	return r

static func blood_cot(parent: Node3D, pos: Vector3, yaw := 0.0, canvas := Color(0.24, 0.3, 0.24)) -> Node3D:
	var r := _root(parent, pos, yaw, "BloodCot")
	var metal := Mats.get_mat("metal", 1.0)
	for sx in [-1, 1]:
		box(r, Vector3(0.035, 0.035, 1.9), Vector3(sx * 0.38, 0.38, 0), metal, false)
		for sz in [-1, 1]:
			box(r, Vector3(0.035, 0.38, 0.035), Vector3(sx * 0.38, 0.19, sz * 0.85), metal, false, Vector3(0, 0, sx * 0.15))
	box(r, Vector3(0.78, 0.035, 1.86), Vector3(0, 0.4, 0), Mats.color(canvas, 0.95), false)
	box(r, Vector3(0.7, 0.07, 1.7), Vector3(0, 0.45, 0), Mats.color(Color(0.45, 0.45, 0.4), 0.95), false)
	var blank := Mats.color(Color(0.38, 0.36, 0.3), 0.95)
	box(r, Vector3(0.68, 0.09, 1.0), Vector3(0.0, 0.54, -0.35), blank, false, Vector3(0.0, 0.05, 0.08))
	box(r, Vector3(0.45, 0.09, 0.3), Vector3(0, 0.55, 0.8), Mats.color(Color(0.62, 0.6, 0.55), 0.95), false)
	box(r, Vector3(0.9, 0.5, 1.95), Vector3(0, 0.25, 0), blank, true).visible = false
	_d(r, "pool_b", Vector3(0.0, 0.59, -0.25), 1.3)
	_d(r, "splat_a", Vector3(0.05, 0.6, 0.5), 0.85)
	_d(r, "spray_a", Vector3(-0.1, 0.6, 0.1), 1.0, Vector3.UP, Vector3.BACK)
	_d(r, "drips_a", Vector3(0.405, 0.3, -0.3), 0.5, Vector3.RIGHT, Vector3.RIGHT.cross(Vector3.DOWN) * 1.0, false, 0.0)
	_pool_at(r, Vector3(0.62, 0.0, -0.3), 1.3)
	return r

static func bathtub(parent: Node3D, pos: Vector3, yaw := 0.0, filled := true) -> Node3D:
	var r := _root(parent, pos, yaw, "Bathtub")
	var por := Mats.color(Color(0.8, 0.82, 0.8), 0.14)
	por.clearcoat_enabled = true
	por.clearcoat = 0.6
	var hh := 0.55
	box(r, Vector3(0.08, hh, 1.7), Vector3(-0.36, hh * 0.5 + 0.06, 0), por, false)
	box(r, Vector3(0.08, hh, 1.7), Vector3(0.36, hh * 0.5 + 0.06, 0), por, false)
	box(r, Vector3(0.8, hh, 0.08), Vector3(0, hh * 0.5 + 0.06, -0.81), por, false)
	box(r, Vector3(0.8, hh, 0.08), Vector3(0, hh * 0.5 + 0.06, 0.81), por, false)
	box(r, Vector3(0.8, 0.1, 1.7), Vector3(0, 0.12, 0), por, false)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			cyl(r, 0.035, 0.07, Vector3(sx * 0.32, 0.035, sz * 0.75), Mats.get_mat("metal"), false)
	box(r, Vector3(0.8, hh + 0.06, 1.7), Vector3(0, (hh + 0.06) * 0.5, 0), por, true).visible = false
	if filled:
		box(r, Vector3(0.64, 0.02, 1.54), Vector3(0, 0.46, 0), Gore.mat_fluid(Color(0.22, 0.012, 0.016)), false)
		# the body just below the surface: knees, shoulder, hair
		var skin := Mats.color(Color(0.62, 0.58, 0.54), 0.5)
		_mi(r, SphereMesh.new(), skin, Vector3(-0.1, 0.46, -0.4), Vector3.ZERO, Vector3(0.18, 0.1, 0.2))
		_mi(r, SphereMesh.new(), skin, Vector3(0.12, 0.465, -0.45), Vector3.ZERO, Vector3(0.17, 0.09, 0.2))
		_mi(r, SphereMesh.new(), Mats.color(Color(0.1, 0.07, 0.05), 0.7), Vector3(0.0, 0.47, 0.64), Vector3.ZERO, Vector3(0.22, 0.12, 0.24))
		_mi(r, SphereMesh.new(), skin, Vector3(0.16, 0.47, 0.35), Vector3.ZERO, Vector3(0.12, 0.08, 0.14))
	# arm trailing over the edge
	var skin2 := Mats.color(Color(0.6, 0.56, 0.52), 0.5)
	_mi(r, _cylm(0.04, 0.032, 0.5, 8), skin2, Vector3(-0.45, 0.47, 0.25), Vector3(0, 0, 0.9))
	_mi(r, _cylm(0.032, 0.026, 0.4, 8), skin2, Vector3(-0.55, 0.22, 0.28), Vector3(0, 0, 0.15))
	_mi(r, Gore.chunk_mesh(4), skin2, Vector3(-0.57, 0.04, 0.28), Vector3.ZERO, Vector3(0.09, 0.04, 0.11))
	_d(r, "drips_b", Vector3(-0.405, 0.6, 0.0), 0.7, Vector3.LEFT, Vector3.LEFT.cross(Vector3.DOWN), false, 0.0)
	_pool_at(r, Vector3(-0.7, 0.0, 0.2), 1.6)
	_d(r, "splat_c", Vector3(-0.2, 0.0, -0.9), 1.0)
	Gore.drip_emitter(r, Vector3(-0.57, 0.14, 0.28), "blood", 1.3)
	return r

static func wheelchair(parent: Node3D, pos: Vector3, yaw := 0.0, occupied := true) -> Node3D:
	var r := _root(parent, pos, yaw, "Wheelchair")
	var metal := Mats.get_mat("metal", 1.0)
	var vinyl := Mats.color(Color(0.05, 0.06, 0.08), 0.5)
	var strap := Mats.color(Color(0.16, 0.1, 0.06), 0.55)
	box(r, Vector3(0.46, 0.05, 0.46), Vector3(0, 0.5, 0), vinyl, false)
	box(r, Vector3(0.46, 0.46, 0.05), Vector3(0, 0.78, -0.22), vinyl, false, Vector3(0.1, 0, 0))
	for sx in [-1, 1]:
		box(r, Vector3(0.04, 0.04, 0.4), Vector3(sx * 0.25, 0.7, -0.02), vinyl, false)
		box(r, Vector3(0.025, 0.2, 0.025), Vector3(sx * 0.25, 0.6, 0.15), metal, false)
		cyl(r, 0.31, 0.03, Vector3(sx * 0.3, 0.31, -0.1), Mats.get_mat("rubber"), false, -1.0, Vector3(0, 0, PI * 0.5), 20)
		cyl(r, 0.27, 0.035, Vector3(sx * 0.3, 0.31, -0.1), metal, false, -1.0, Vector3(0, 0, PI * 0.5), 20)
		cyl(r, 0.07, 0.03, Vector3(sx * 0.24, 0.08, 0.32), Mats.get_mat("rubber"), false, -1.0, Vector3(0, 0, PI * 0.5), 10)
		box(r, Vector3(0.025, 0.025, 0.55), Vector3(sx * 0.23, 0.32, 0.12), metal, false)
		box(r, Vector3(0.12, 0.015, 0.16), Vector3(sx * 0.12, 0.14, 0.45), metal, false)
		# restraint straps: wrist + ankle
		box(r, Vector3(0.07, 0.025, 0.09), Vector3(sx * 0.25, 0.73, 0.12), strap, false)
		box(r, Vector3(0.1, 0.03, 0.05), Vector3(sx * 0.12, 0.18, 0.4), strap, false)
	box(r, Vector3(0.5, 0.06, 0.04), Vector3(0, 0.88, -0.17), strap, false)
	box(r, Vector3(0.5, 0.05, 0.05), Vector3(0, 0.56, 0.1), strap, false)
	box(r, Vector3(0.6, 0.95, 0.9), Vector3(0, 0.48, 0.1), vinyl, true).visible = false
	if occupied:
		corpse_pose(r, Vector3(0, 0.0, -0.02), 0.0, {"model": "rimebound_patient"}, "sit", false)
		_d(r, "splat_b", Vector3(0, 0.0, 0.1), 1.2)
		_d(r, "pool_c", Vector3(0, 0.0, 0.5), 1.1)
		_d(r, "drips_a", Vector3(0, 0.55, 0.28), 0.4, Vector3.BACK, Vector3.BACK.cross(Vector3.DOWN), false, 0.0)
	return r

## Hanging carcass on a ceiling rail with a chain and hook. h = rail height above the floor.
static func meat_hook(parent: Node3D, pos: Vector3, yaw := 0.0, with_body := true, h := 3.4) -> Node3D:
	var r := _root(parent, pos, yaw, "MeatHook")
	var rust := Mats.get_mat("metal_rust", 1.0)
	var steel := Mats.get_mat("metal", 1.0)
	box(r, Vector3(0.1, 0.14, 3.0), Vector3(0, h, 0), rust, false)
	box(r, Vector3(0.14, 0.1, 0.22), Vector3(0, h - 0.12, 0), steel, false)
	var hy := 2.15 if h > 2.9 else h - 0.6                      # hook height: the carcass hangs just above the floor
	var chain_len: float = max(h - 0.17 - hy, 0.1)
	cyl(r, 0.009, chain_len, Vector3(0, h - 0.17 - chain_len * 0.5, 0), steel, false, -1.0, Vector3.ZERO, 6)
	var tor := TorusMesh.new()
	tor.inner_radius = 0.032
	tor.outer_radius = 0.046
	_mi(r, tor, steel, Vector3(0, hy - 0.04, 0), Vector3(PI * 0.5, 0, 0))
	cyl(r, 0.012, 0.2, Vector3(0, hy - 0.2, 0.04), steel, false, 0.008, Vector3.ZERO, 6)
	_mi(r, _cylm(0.0, 0.012, 0.09, 6), steel, Vector3(0, hy - 0.34, 0.04))
	if with_body:
		# the hook goes through the upper back: the body hangs standing, head lolling
		var c := corpse_pose(r, Vector3(0, hy - 1.42, 0.16), PI * 0.0, {"model": "rimebound_flannel_m"}, "normal", false)
		c.rotation.x = 0.1
		_pool_at(r, Vector3(0, 0.0, 0.1), 2.6)
		_d(r, "splat_b", Vector3(0.2, 0.0, 0.4), 1.5)
		Gore.drip_emitter(r, Vector3(0, hy - 1.3, 0.2), "blood", 0.9)
	return r

## A body hanging from a cable or crystal filament. drop = cable length above the body's head,
## floor_y = y of the floor below (pool + drips), filament = ice-blue crystal strands instead of steel.
static func hanging_body(parent: Node3D, pos: Vector3, yaw := 0.0, drop := 3.0, floor_y := 0.0, filament := false) -> Node3D:
	var r := _root(parent, pos, yaw, "Hanging")
	var cab: Material
	if filament:
		var f := StandardMaterial3D.new()
		f.albedo_color = Color(0.55, 0.85, 0.95, 0.55)
		f.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		f.roughness = 0.15
		f.emission_enabled = true
		f.emission = Color(0.1, 0.5, 0.7)
		f.emission_energy_multiplier = 0.8
		cab = f
	else:
		cab = Mats.get_mat("metal", 1.0)
	var c := corpse_pose(r, Vector3(0, -1.78, 0.0), randf() * TAU, {"model": "rimebound_miner"}, "normal", false)
	c.rotation.x = randf_range(0.05, 0.2)
	if filament:
		frost_overlay(c, 0.25)
	for i in (3 if filament else 1):
		cyl(r, 0.012 if filament else 0.015, drop, Vector3(randf_range(-0.12, 0.12) if filament else 0.0, drop * 0.5, randf_range(-0.08, 0.08) if filament else 0.0), cab, false, -1.0, Vector3.ZERO, 5)
	var fy := floor_y - pos.y
	_pool_at(r, Vector3(0, fy + 0.02, 0.1), 2.6)
	Gore.drip_emitter(r, Vector3(0, -1.9, 0.1), "blood", 1.1)
	return r

## Corpse sealed in a block of ice. upright = standing in a wall niche.
static func frozen_corpse(parent: Node3D, pos: Vector3, yaw := 0.0, upright := false, cfg := {}) -> Node3D:
	var r := _root(parent, pos, yaw, "FrozenCorpse")
	var hold := Node3D.new()
	r.add_child(hold)
	var ice := StandardMaterial3D.new()
	ice.albedo_color = Color(0.7, 0.86, 0.96, 0.34)
	ice.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ice.roughness = 0.08
	ice.metallic_specular = 1.0
	ice.clearcoat_enabled = true
	ice.clearcoat = 1.0
	ice.clearcoat_roughness = 0.04
	ice.rim_enabled = true
	ice.rim = 0.35
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 0.62, 2.15)
	var blk := _mi(hold, bm, ice, Vector3(0, 0.31, 0))
	blk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cc := cfg.duplicate()
	cc["death_variant"] = 0
	var c: Node3D
	if upright:
		c = corpse_pose(hold, Vector3(0, 0.12, 0.0), 0.0, cc, "normal", false)
	else:
		c = corpse(hold, Vector3(0, 0.3, 0.88), 0.0, cc)      # lying on its back: origin at the feet, head toward -Z
		_no_pool(c)
	frost_overlay(c, 0.32)
	# dark frozen blood smudges inside the ice
	_mi(hold, Gore.chunk_mesh(2), Mats.color(Color(0.1, 0.01, 0.015, 0.8), 0.1), Vector3(0.1, 0.24, 0.1), Vector3.ZERO, Vector3(0.5, 0.05, 0.6))
	if upright:
		bm.size = Vector3(1.0, 2.15, 0.62)
		blk.mesh = bm
		blk.position = Vector3(0, 1.08, 0)
		box(r, Vector3(1.0, 2.15, 0.62), Vector3(0, 1.08, 0), ice, true).visible = false
	else:
		box(r, Vector3(1.0, 0.62, 2.15), Vector3(0, 0.31, 0), ice, true).visible = false
		Gore.frozen_blood(r, Vector3(0.0, 0.0, 0.0), 2.6, {"local": true})
	return r

static func frozen_pile(parent: Node3D, pos: Vector3, yaw := 0.0, n := 5) -> Node3D:
	var r := _root(parent, pos, yaw, "FrozenPile")
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 17 + pos.z * 31 + 3)
	var snow := Mats.get_mat("snow", 2.0)
	_mi(r, SphereMesh.new(), snow, Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(2.8, 0.45, 2.6))
	for i in n:
		var layer := i / 3
		var x := rng.randf_range(-0.45, 0.45)
		var z := rng.randf_range(-0.45, 0.45)
		var c := corpse(r, Vector3(x, 0.18 + layer * 0.3 + (i % 3) * 0.02, z), rng.randf() * TAU, {})
		_no_pool(c)
		c.rotation.x = rng.randf_range(-0.12, 0.12)
		c.rotation.z = rng.randf_range(-0.12, 0.12)
		frost_overlay(c, 0.28)
	box(r, Vector3(2.2, 0.6, 2.2), Vector3(0, 0.3, 0), snow, true).visible = false
	_d(r, "pool_b", Vector3(0.2, 0.0, 0.9), 2.4, Vector3.UP, Vector3.RIGHT, false)
	Gore.frozen_blood(r, Vector3(-0.8, 0.0, 0.8), 1.8, {"local": true})
	return r

## Chalk outline of a body on the ground with a dark pool, evidence tents and a smear.
static func body_outline(parent: Node3D, pos: Vector3, yaw := 0.0, size := 1.9) -> Node3D:
	var r := _root(parent, pos, yaw, "Outline")
	_d(r, "pool_a", Vector3(0, 0.0, -0.1), size * 0.95, Vector3.UP, Vector3.RIGHT)
	_d(r, "outline", Vector3(0, 0.0, 0.0), size * 0.5, Vector3.UP, Vector3.RIGHT, false, 0.0)
	var yel := Mats.color(Color(0.85, 0.65, 0.05), 0.5)
	for i in 3:
		var p := PrismMesh.new()
		p.size = Vector3(0.07, 0.1, 0.05)
		_mi(r, p, yel, Vector3(0.5 + 0.15 * i, 0.05, -0.5 + i * 0.4), Vector3(0, randf() * TAU, 0))
	return r

## Blood-written message. id: help | run | sleep | out. yaw = direction the wall faces.
static func blood_writing(parent: Node3D, pos: Vector3, yaw: float, id := "help", width := 1.6) -> Node3D:
	var r := _root(parent, pos, 0.0, "BloodWriting")
	var n := Vector3(sin(yaw), 0, cos(yaw))
	Gore.writing(r, id, Vector3.ZERO, n, width, {"local": true})
	return r

## Crashed car with a blood-smeared windshield, bloody hood and door handprints.
static func car_gore(parent: Node3D, pos: Vector3, yaw := 0.0, color := Color(0.25, 0.28, 0.3), kind := "sedan") -> Node3D:
	var c := car(parent, pos, yaw, color, true, kind)
	var splat := Gore._t("splat_b_a")
	var m := StandardMaterial3D.new()
	m.albedo_texture = splat
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.08
	m.metallic_specular = 0.9
	m.albedo_color = Color(1, 0.75, 0.75, 0.95)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cab_len := 2.25 if kind == "sedan" or kind == "police" else 4.6
	var cab_z := -0.2 if kind == "sedan" or kind == "police" else -0.25
	var wz := cab_z + cab_len * 0.46 + 0.012
	var qm := QuadMesh.new()
	qm.size = Vector2(1.5, 0.75)
	_mi(c, qm, m, Vector3(0.1, 1.37, wz), Vector3(-0.15, 0, 0))
	var sm := StandardMaterial3D.new()
	sm.albedo_texture = Gore._t("smear_a_a")
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.roughness = 0.08
	sm.albedo_color = Color(1, 0.8, 0.8, 0.9)
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var qs := QuadMesh.new()
	qs.size = Vector2(1.3, 0.33)
	_mi(c, qs, sm, Vector3(-0.2, 1.34, wz + 0.002), Vector3(-0.15, 0, 0.1))
	_d(c, "splat_a", Vector3(0.1, 1.1, 1.6), 1.1)
	_d(c, "spray_a", Vector3(0.4, 1.1, 1.2), 1.2, Vector3.UP, Vector3.BACK)
	_d(c, "hand_smear", Vector3(0.93, 0.95, -0.2), 0.3, Vector3.RIGHT, Vector3.RIGHT.cross(Vector3.DOWN), false, 0.0)
	_pool_at(c, Vector3(1.4, 0.0, -0.2), 1.8)
	return c

## Frozen-crystal impalement: a body skewered on an ice spike (mine / cavern).
static func crystal_impale(parent: Node3D, pos: Vector3, yaw := 0.0, h := 2.3) -> Node3D:
	var r := _root(parent, pos, yaw, "Impaled")
	var ice := ShaderMaterial.new()
	ice.shader = load("res://world/shaders/env_ice.gdshader")
	# organic ice column: stacked, lumpy, slightly offset blobs (no cone), with a frost skirt at the base
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 31 + pos.z * 17)
	var segs := 7
	for i in segs:
		var t := float(i) / (segs - 1)
		var rad := 0.2 * (1.0 - 0.72 * t) + rng.randf_range(-0.02, 0.03)
		var y := (h + 0.5) * t
		var m := _mi(r, SphereMesh.new(), ice, Vector3(rng.randf_range(-0.05, 0.05) + 0.05 * t, y, rng.randf_range(-0.05, 0.05)), Vector3.ZERO, Vector3(rad * 2.0, (h + 0.5) / segs * 1.5, rad * 2.0))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in 4:
		var a2 := i * 1.57 + rng.randf()
		var rr := rng.randf_range(0.12, 0.22)
		var m2 := _mi(r, SphereMesh.new(), ice, Vector3(0.3 * cos(a2), rr * 0.6, 0.3 * sin(a2)), Vector3.ZERO, Vector3(rr * 2.2, rr * 1.4, rr * 1.8))
		m2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var c := corpse_pose(r, Vector3(0.04, h - 1.5, 0.0), randf() * TAU, {"model": "rimebound_miner"}, "normal", false)
	c.rotation.x = 0.18
	frost_overlay(c, 0.3)
	_pool_at(r, Vector3(0.1, 0.0, 0.1), 2.0)
	Gore.drip_emitter(r, Vector3(0.0, h - 0.5, 0.2), "blood", 1.0)
	return r

## Blood on a pane of glass (decals do not draw on transparent surfaces): a textured quad.
## kind: hand | hand2 | smear | splat | drips | spray.  yaw = direction the quad faces (+Z at yaw 0).
static func glass_blood(parent: Node3D, pos: Vector3, yaw := 0.0, kind := "hand", size := 0.25, roll := 0.0) -> Node3D:
	var names := {"hand": "hand_r", "hand2": "hand_l", "smear": "hand_smear", "splat": "splat_wall", "drips": "drips_a", "spray": "spray_a"}
	var nm: String = names.get(kind, "hand_r")
	var tex := Gore._t(nm + "_a")
	if tex == null:
		return null
	var asp: float = Gore.ASPECT.get(nm, 1.0)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.07
	m.metallic_specular = 0.9
	var ntex := Gore._t(nm + "_n")
	if ntex != null:
		m.normal_enabled = true
		m.normal_texture = ntex
	var q := QuadMesh.new()
	q.size = Vector2(size, size * asp)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = pos
	mi.rotation = Vector3(0, yaw, roll)
	return mi

# ================================================================== REAL 3D ASSETS (assets/env/**.glb via world/env_assets.gd)
const BARE_H := [11.79, 13.91, 9.08, 13.19, 10.91]
const CONIFER_H := [13.78, 11.78, 15.78]
const PINE_H := [16.25, 16.06]

## Generic: instance any assets/env glb (null if the file is missing).
static func prop(parent: Node3D, rel: String, pos := Vector3.ZERO, yaw := 0.0, opts := {}) -> Node3D:
	return Env.spawn(parent, rel, pos, yaw, opts)

static func _trunk_col(r: Node3D, radius: float, h: float) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = radius
	sh.height = h
	cs.shape = sh
	cs.position.y = h * 0.5
	sb.add_child(cs)
	r.add_child(sb)

static func _glb_bare_tree(parent: Node3D, pos: Vector3, h: float, seed: int) -> Node3D:
	var k := int(abs(seed if seed != 0 else int(pos.x * 97 + pos.z * 53)))
	var i := k % 5
	var rel := "trees/bare_%d" % (i + 1)
	if not Env.has(rel):
		return null
	var sc: float = h / BARE_H[i]
	var yaw := float(k % 628) / 100.0
	var r := _root(parent, pos, yaw, "Tree")
	Env.spawn(r, rel, Vector3.ZERO, 0.0, {"scale": sc, "collide": "none", "snow": 0.7, "range": 60.0, "name": "Hi"})
	if Env.has(rel + "_lod"):
		Env.spawn(r, rel + "_lod", Vector3.ZERO, 0.0, {"scale": sc, "collide": "none", "snow": 0.7, "range": 260.0, "range_begin": 60.0, "shadow": false, "name": "Lod"})
	_trunk_col(r, 0.3 * sc, 4.0)
	return r

## Needle conifers / pines (generated cards, snow settles on the upper faces). kind: "fir" | "pine" | "small"
static func conifer(parent: Node3D, pos: Vector3, h := 11.0, seed := 0, kind := "fir") -> Node3D:
	var k := int(abs(seed if seed != 0 else int(pos.x * 97 + pos.z * 53)))
	var rel := ""
	var nat := 10.0
	if kind == "small":
		rel = "trees/conifer_small"; nat = 5.36
	elif kind == "pine":
		var j := k % 2
		rel = "trees/pine_%d" % (j + 1); nat = PINE_H[j]
	else:
		var j2 := k % 3
		rel = "trees/conifer_%d" % (j2 + 1); nat = CONIFER_H[j2]
	var r := _root(parent, pos, float(k % 628) / 100.0, "Conifer")
	if Env.spawn(r, rel, Vector3.ZERO, 0.0, {"scale": h / nat * (0.9 + 0.2 * float(k % 7) / 7.0), "collide": "none", "range": 220.0, "snow": 0.85}) == null:
		r.queue_free()
		return null
	_trunk_col(r, 0.28 * h / 12.0 + 0.1, 3.0)
	return r

static func stump(parent: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	return Env.spawn(parent, "trees/stump_0%d" % (1 + int(abs(pos.x + pos.z)) % 2), pos, yaw, {"collide": "cyl", "snow": 0.7})

static func dead_log(parent: Node3D, pos: Vector3, yaw := 0.0, big := false) -> Node3D:
	return Env.spawn(parent, "trees/dead_trunk_02" if big else "trees/dead_trunk_01", pos, yaw, {"collide": "box", "snow": 0.8})

static func _glb_car(parent: Node3D, pos: Vector3, yaw: float, color: Color, wrecked: bool, kind: String) -> Node3D:
	var h := int(abs(hash(Vector2(pos.x, pos.z))))
	var rel: String = "vehicles/" + kind
	var tint := Color.WHITE
	if kind == "sedan":
		if wrecked and h % 3 == 0 and Env.has("vehicles/covered_car"):
			rel = "vehicles/covered_car"
		else:
			tint = Color.WHITE.lerp(Color(min(color.r * 2.2 + 0.25, 1.4), min(color.g * 2.2 + 0.25, 1.4), min(color.b * 2.2 + 0.25, 1.4)), 0.5)
	if not Env.has(rel):
		return null
	var r := Env.spawn(parent, rel, pos, yaw, {"name": "Car", "tint": tint, "snow": 0.75 if wrecked else 0.45, "box_shrink": 0.95})
	if r and wrecked:
		r.rotation.z = (float(h % 100) / 100.0 - 0.5) * 0.1
	return r

static func _glb_lamp(parent: Node3D, pos: Vector3, yaw: float, on: bool, color: Color) -> Node3D:
	var r := Env.spawn(parent, "street/lamp_01", pos, yaw, {"name": "LampPost", "fit_h": 5.4, "collide": "cyl", "cyl_r": 0.15, "cyl_h": 5.4, "snow": 0.5})
	if r == null:
		return null
	if on:
		var l := SpotLight3D.new()
		l.light_color = color
		l.light_energy = 6.0
		l.spot_range = 14.0
		l.spot_angle = 55.0
		l.shadow_enabled = true
		l.light_volumetric_fog_energy = 1.5
		l.position = Vector3(0, 5.15, 0.0)
		l.rotation.x = -PI * 0.5
		r.add_child(l)
		var glow := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.12
		glow.mesh = sm
		glow.material_override = Mats.emissive(color, 5.0)
		glow.position = Vector3(0, 5.08, 0.0)
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		r.add_child(glow)
	return r

static var _chain_mat: StandardMaterial3D

static func _glb_fence(parent: Node3D, a: Vector3, b: Vector3, h: float) -> Node3D:
	var r := _root(parent, a, 0.0, "Fence")
	var d := b - a
	var len := Vector2(d.x, d.z).length()
	r.rotation.y = atan2(d.x, d.z)
	var n := maxi(1, int(ceil(len / 3.0)))
	for i in n + 1:
		Env.spawn(r, "street/fence_post", Vector3(0, 0, i * len / n), 0.0, {"fit_h": h + 0.1, "collide": "none", "snow": 0.4, "name": "Post"})
	if _chain_mat == null:
		_chain_mat = StandardMaterial3D.new()
		_chain_mat.albedo_texture = load("res://textures/env/chainlink.png")
		_chain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		_chain_mat.alpha_scissor_threshold = 0.4
		_chain_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_chain_mat.metallic = 0.7
		_chain_mat.roughness = 0.45
		_chain_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(len, h - 0.15)
	qm.orientation = PlaneMesh.FACE_Z
	mi.mesh = qm
	var mm := _chain_mat.duplicate() as StandardMaterial3D
	mm.uv1_scale = Vector3(len / 1.0, (h - 0.15) / 1.0, 1)
	mm.uv1_triplanar = false
	mi.material_override = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation.y = PI * 0.5
	mi.position = Vector3(0, (h - 0.15) * 0.5 + 0.1, len * 0.5)
	r.add_child(mi)
	# top rail
	var rail := cyl(r, 0.025, len, Vector3(0, h, len * 0.5), Mats.get_mat("metal", 1.0), false, -1.0, Vector3(PI * 0.5, 0, 0), 6)
	rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# invisible solid wall so the player and the nav bake respect the fence
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.1, h, len)
	cs.shape = sh
	cs.position = Vector3(0, h * 0.5, len * 0.5)
	sb.add_child(cs)
	r.add_child(sb)
	return r

# ---- street furniture
static func hydrant(parent: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	var r := Env.spawn(parent, "street/hydrant", pos, yaw, {"fit_h": 0.85, "collide": "cyl", "cyl_r": 0.2, "snow": 0.6, "tint": Color(1.0, 0.75, 0.7)})
	if r == null:
		r = cyl(_root(parent, pos, yaw, "Hydrant"), 0.16, 0.8, Vector3(0, 0.4, 0), Mats.color(Color(0.6, 0.1, 0.08), 0.5), true).get_parent()
	return r

static func utility_box(parent: Node3D, pos: Vector3, yaw := 0.0, big := false) -> Node3D:
	return Env.spawn(parent, "street/utility_box_02" if big else "street/utility_box_01", pos, yaw, {"snow": 0.65})

static func power_box(parent: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	return Env.spawn(parent, "street/power_box", pos, yaw, {"snow": 0.6})

static func barrier(parent: Node3D, pos: Vector3, yaw := 0.0, kind := 1) -> Node3D:
	return Env.spawn(parent, "street/barrier_0%d" % kind, pos, yaw, {"snow": 0.8, "box_shrink": 1.0})

## Wooden utility pole with crossarms / insulators / transformer (generated kit). kind 0..2
static func utility_pole(parent: Node3D, pos: Vector3, yaw := 0.0, kind := 0, h := 9.0) -> Node3D:
	var rel: String = "street/pole_" + ["a", "b", "c"][kind % 3]
	return Env.spawn(parent, rel, pos, yaw, {"fit_h": h, "collide": "cyl", "cyl_r": 0.18, "snow": 0.4, "range": 300.0, "shadow": true})

static func barrel_stove(parent: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	return Env.spawn(parent, "camp/barrel_stove", pos, yaw, {"collide": "cyl", "cyl_r": 0.3, "snow": 0.2})

static func generator(parent: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	return Env.spawn(parent, "camp/generator", pos, yaw, {"snow": 0.4})

static func trash_can(parent: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	return Env.spawn(parent, "camp/trash_can", pos, yaw, {"snow": 0.5, "scale": 0.5, "collide": "cyl", "cyl_r": 0.3, "cyl_h": 0.9})

## Hero meshes generated for the project (Higgsfield/Tripo): substation transformer, 9 m steeple, data-centre rack.
static func transformer(parent: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	return Env.spawn(parent, "props/transformer", pos, yaw, {"snow": 0.55, "range": 400.0})

static func steeple(parent: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	return Env.spawn(parent, "props/steeple", pos, yaw, {"snow": 0.6, "range": 500.0, "collide": "none"})

static func server_rack(parent: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	return Env.spawn(parent, "props/server_rack", pos, yaw, {"snow": 0.0, "range": 60.0})

# ---- sculpted snow drift (replaces the flat discs): a heightfield mound with a wind lee tail, edges sink into the ground
static var _drift_mesh := {}
static func _drift_mesh_for(v: int) -> ArrayMesh:
	if _drift_mesh.has(v):
		return _drift_mesh[v]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + v
	var N := 22
	var ph := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	var lee := rng.randf_range(0.2, 0.55)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hs := []
	for j in N + 1:
		for i in N + 1:
			var u := (float(i) / N) * 2.0 - 1.0
			var w := (float(j) / N) * 2.0 - 1.0
			var r2 := u * u * 0.85 + w * w * 1.15
			var base: float = pow(max(0.0, 1.0 - r2), 1.35)
			base *= clampf(1.0 + lee * u * 1.2, 0.3, 1.8)
			var rip := 0.05 * sin(u * 9.0 + w * 3.0 + ph[0]) + 0.04 * sin(w * 11.0 - u * 4.0 + ph[1])
			var hh: float = base * (1.0 + rip * 2.0) + (rip * 0.4 * base)
			hs.append(Vector3(u, max(hh, 0.0) - 0.04 * (1.0 if base < 0.01 else 0.0), w))
	for j in N:
		for i in N:
			var a: Vector3 = hs[j * (N + 1) + i]
			var b: Vector3 = hs[j * (N + 1) + i + 1]
			var c: Vector3 = hs[(j + 1) * (N + 1) + i]
			var d: Vector3 = hs[(j + 1) * (N + 1) + i + 1]
			for p in [a, b, c, b, d, c]:
				st.set_uv(Vector2(p.x, p.z) * 0.5)
				st.add_vertex(p)
	st.generate_normals()
	var m := st.commit()
	_drift_mesh[v] = m
	return m

## Half-extents sx (x), sy (peak height), sz (z), like the old sphere discs.
static func drift(parent: Node3D, pos: Vector3, sx := 1.6, sy := 0.35, sz := 1.0, yaw := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _drift_mesh_for(int(abs(pos.x * 13.0 + pos.z * 7.0)) % 6)
	mi.material_override = Mats.get_mat("snow")
	mi.scale = Vector3(sx, sy * 1.35, sz)
	mi.position = pos
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if sx < 1.4 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi
