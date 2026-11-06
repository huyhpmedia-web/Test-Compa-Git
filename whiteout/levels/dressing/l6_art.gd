extends RefCounted
## L6 - THE HEART: cavern environment art (agent F). Real rock (ambientCG Rock035/Rock058, CC0) on all
## masses, procedural noise-displaced stalactites/stalagmites (no cones), the generated ice_cluster.glb
## (translucent ice material) in place of prism crystals, rock_lo relief blocks along the cave walls.

const Props = preload("res://world/props.gd")
const Mats = preload("res://core/mats.gd")
const Env = preload("res://world/env_assets.gd")
const A4 = preload("res://levels/dressing/l4_art.gd")

static var _c := {}
static var _ice_mat: StandardMaterial3D
static var host: Node3D
static var geo: Node3D
static var rng := RandomNumberGenerator.new()

static func rock_mat() -> StandardMaterial3D:
	return A4.pbr("rock", 4.0, Color(0.55, 0.65, 0.85), 1.0, 1.3)

static func rock_wet() -> StandardMaterial3D:
	return A4.pbr("rock2", 3.0, Color(0.5, 0.62, 0.8), 0.7, 1.2)

static func rock_floor() -> StandardMaterial3D:
	return A4.pbr("rock2", 2.6, Color(0.55, 0.66, 0.85), 0.55, 1.1)

## Translucent ice using the generated cluster's own colour/normal maps.
static func ice_mat() -> StandardMaterial3D:
	if _ice_mat != null:
		return _ice_mat
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.85, 1.0, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.07
	m.metallic_specular = 1.0
	m.rim_enabled = true
	m.rim = 0.8
	m.rim_tint = 0.5
	m.emission_enabled = true
	m.emission = Color(0.1, 0.5, 0.75)
	m.emission_energy_multiplier = 1.2
	var ps := Env.scene("props/ice_cluster")
	if ps:
		var inst := ps.instantiate()
		var arr: Array = []
		Env._meshes(inst, arr)
		for mi in arr:
			var mesh: Mesh = (mi as MeshInstance3D).mesh
			if mesh and mesh.get_surface_count() > 0:
				var src := mesh.surface_get_material(0)
				if src is BaseMaterial3D:
					m.albedo_texture = (src as BaseMaterial3D).albedo_texture
					if (src as BaseMaterial3D).normal_texture:
						m.normal_enabled = true
						m.normal_texture = (src as BaseMaterial3D).normal_texture
						m.normal_scale = 1.4
					m.emission_texture = m.albedo_texture
				break
		inst.free()
	_ice_mat = m
	return m

## Natural ice formation(s): ice_cluster.glb scaled/stacked to roughly height h and radius r, tilted.
static func ice(parent: Node3D, pos: Vector3, h: float, r: float, tilt := Vector3.ZERO) -> bool:
	var ps := Env.scene("props/ice_cluster")
	if ps == null:
		return false
	var root := Node3D.new()
	root.position = pos
	root.rotation = tilt
	parent.add_child(root)
	var count := 1
	var seg := h / float(count)
	for k in count:
		var inst := ps.instantiate() as Node3D
		var s := clampf(seg / 2.2 * 1.15, 0.14, 7.0)
		var sxz := clampf(r * 1.5, 0.16, s * 1.7)
		inst.scale = Vector3(sxz, s, sxz)
		inst.rotation.y = rng.randf() * TAU
		inst.position = Vector3(rng.randf_range(-0.3, 0.3) * r * (1 if k > 0 else 0), k * seg * 0.78 - 0.15 * s, rng.randf_range(-0.3, 0.3) * r * (1 if k > 0 else 0))
		root.add_child(inst)
		var arr: Array = []
		Env._meshes(inst, arr)
		for mi in arr:
			var m: MeshInstance3D = mi
			m.material_override = ice_mat()
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			m.visibility_range_end = 80.0
	return true

# ------------------------------------------------------------------ procedural rock spikes
static func spike_mesh(len: float, rad: float, seed_v: int) -> ArrayMesh:
	var key := "%d@%.1f@%.2f" % [seed_v, len, rad]
	if _c.has(key):
		return _c[key]
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var rings := 18
	var sides := 10
	var ph := r.randf() * 6.0
	var wob := Vector2(r.randf_range(-1, 1), r.randf_range(-1, 1)) * rad * 0.9
	var bump := r.randf_range(5.0, 12.0)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in rings + 1:
		var t := float(i) / float(rings)
		var prof := pow(maxf(1.0 - t, 0.0), 0.8) * (1.0 + 0.22 * sin(t * bump + ph) + 0.1 * sin(t * bump * 2.7 + ph * 2.0))
		var rr := maxf(rad * prof, rad * 0.025)
		var c := wob * t * t
		for j in sides:
			var a := float(j) / float(sides) * TAU + 0.15 * sin(t * 5.0 + j)
			var jag := 1.0 + 0.16 * sin(float(j) * 2.3 + t * 9.0 + ph) + r.randf_range(-0.05, 0.05)
			verts.append(Vector3(cos(a) * rr * jag + c.x, t * len, sin(a) * rr * jag + c.y))
			uvs.append(Vector2(float(j) / float(sides) * 2.0, t * len * 0.5))
	for i in rings:
		for j in sides:
			var a0 := i * sides + j
			var a1 := i * sides + (j + 1) % sides
			var b0 := (i + 1) * sides + j
			var b1 := (i + 1) * sides + (j + 1) % sides
			idx.append_array([a0, b0, a1, a1, b0, b1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# smooth normals through SurfaceTool
	var st := SurfaceTool.new()
	st.create_from(am, 0)
	st.generate_normals()
	var out := st.commit()
	_c[key] = out
	return out

## down = hangs from y_base (stalactite); otherwise rises from y_base.
static func spike(parent: Node3D, pos: Vector3, len: float, rad: float, down: bool, seed_v: int, mat: Material = null) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = spike_mesh(len, rad, seed_v % 24)
	mi.material_override = mat if mat else rock_wet()
	mi.position = pos
	if down:
		mi.rotation.x = PI
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 160.0
	parent.add_child(mi)

# ------------------------------------------------------------------ rock relief
static func rock_block(parent: Node3D, pos: Vector3, yaw: float, s: float, solid := false) -> Node3D:
	var n := "mine/rock_lo_%d" % (1 + rng.randi() % 3)
	return Env.spawn(parent, n, pos, yaw, {"scale": s, "snow": 0.0, "collide": "none", "tint": Color(0.6, 0.7, 0.9), "range": 110.0, "shadow": false})

## dir 1 = mass lies to +x of the face, 2 = mass lies to -z of the face
static func _wall_block(face: Vector3, dir: int, s: float) -> void:
	var off := 1.7 * s
	var p := face + (Vector3(off, 0, 0) if dir == 1 else Vector3(0, 0, -off))
	p.x += 0.0 if dir == 1 else rng.randf_range(-0.5, 0.5)
	p.z += rng.randf_range(-0.5, 0.5) if dir == 1 else 0.0
	rock_block(geo, p, rng.randf() * TAU, s)

static func boulder(parent: Node3D, pos: Vector3, size: Vector3, solid: bool, yaw: float) -> bool:
	var n := "mine/rock_lo_%d" % (1 + rng.randi() % 3)
	var o := {"snow": 0.0, "tint": Color(0.55, 0.66, 0.88), "range": 90.0, "fit_box": size * 1.25, "collide": Vector3(size.x * 0.9, size.y * 0.9, size.z * 0.9) if solid else "none", "shadow": false}
	var r := Env.spawn(parent, n, pos + Vector3(0, -size.y * 0.1, 0), yaw, o)
	return r != null

static func dress(level: Node3D) -> void:
	host = level
	geo = level.get("geo") if level.get("geo") is Node3D else level
	rng.seed = 6006
	# wall relief: blocks sunk into the masses so the flat box walls disappear
	var rows := [0.0, 3.0, 6.2]
	# path east wall (x = 2.5 for z 46..66, 5.0 for z 36..46) and arena east wall (x = 19)
	for row in rows.size():
		var z := 66.0
		while z > 47.0:
			_wall_block(Vector3(2.5, rows[row], z), 1, rng.randf_range(1.0, 1.35))
			z -= 3.6
		z = 45.0
		while z > 36.5:
			_wall_block(Vector3(5.0, rows[row], z), 1, rng.randf_range(1.0, 1.3))
			z -= 3.8
		z = 22.5
		while z > -34.0:
			if absf(z + 20.0) > 5.0 or row > 0:
				_wall_block(Vector3(19.0, rows[row], z), 1, rng.randf_range(1.1, 1.5))
			z -= 4.2
	# the back (lattice) wall, behind the crystals
	for row in 2:
		var x := -19.0
		while x < 20.0:
			_wall_block(Vector3(x, rows[row], -33.0), 2, rng.randf_range(1.1, 1.5))
			x += 4.4
	# pipeline wall damage: rubble pile of real rocks under the breach
	for i in 7:
		boulder(geo, Vector3(17.2 + rng.randf_range(-1.4, 0.8), 0, -20.0 + rng.randf_range(-3.5, 3.5)), Vector3(rng.randf_range(0.6, 1.4), rng.randf_range(0.4, 1.0), rng.randf_range(0.6, 1.4)), false, rng.randf() * TAU)
	# ice shelf and drip columns on the lake edge
	for i in 16:
		var x := rng.randf_range(-16.0, -4.0)
		var z := rng.randf_range(-28.0, 22.0)
		spike(geo, Vector3(x, 0.0, z), rng.randf_range(0.8, 2.4), rng.randf_range(0.18, 0.4), false, i + 7, ice_mat())

## A Rimebound impaled by a natural ice formation (replaces the stacked-sphere column of Props.crystal_impale).
static func impale(parent: Node3D, pos: Vector3, yaw := 0.0, h := 2.3) -> Node3D:
	var r := Node3D.new()
	r.position = pos
	r.rotation.y = yaw
	parent.add_child(r)
	ice(r, Vector3(0.0, 0.0, 0.0), h * 0.9, 0.45, Vector3(0.05, 0.0, -0.06))
	var c := Props.corpse_pose(r, Vector3(0.04, h - 1.6, 0.0), randf() * TAU, {"model": "rimebound_miner"}, "normal", false)
	c.rotation.x = 0.18
	Props.frost_overlay(c, 0.3)
	Props._pool_at(r, Vector3(0.1, 0.0, 0.1), 2.0)
	return r
