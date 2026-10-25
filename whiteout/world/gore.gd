extends RefCounted
## GORE / FLUIDS library (static). Everything blood-, bile-, water- or flesh-shaped lives here.
##
## Decals use the procedural textures in res://textures/gore (tools/gen_gore.py): albedo + normal +
## ORM per decal, so blood is dark, wet (roughness ~0.07 in the middle, duller congealed rim and
## clots) and catches the flashlight.  Decal albedo_mix stays 1 and emission is off.
##
## World-space API (parent must be inside the tree):
##   splatter(parent, pos, normal, dir, size)      pool(parent, pos, size, grow_time)
##   trail(parent, from, to)                       handprint(parent, pos, normal)
##   wall_drips(parent, pos, normal)               footprint / smear / spray_decal / writing
## Fluids: puddle, drip_emitter, steam_vent, frozen_blood, ichor_splatter
## Enemy hooks (called from actors/enemy.gd): on_enemy_hit, on_enemy_death
## Gibs: gib(), head_pop(), lose_limb()
## Pass {"local": true} in opts to give pos/normal/tangent in the parent's LOCAL space instead
## (works before the parent is in the tree - used by world/props.gd).

const Mats = preload("res://core/mats.gd")
const TEX := "res://textures/gore/"

const MAX_DYN_DECALS := 130     # dynamic (combat) decals alive at once; oldest fade out
const MAX_GIBS := 30
const MAX_CORPSES := 28
const MAX_WOUNDS := 7           # wound decals stuck to one body

const SPLAT := ["splat_a", "splat_b", "splat_c", "splat_d"]
const POOL := ["pool_a", "pool_b", "pool_c"]
const SPRAY := ["spray_a", "spray_b"]
const SMEAR := ["smear_a", "smear_b"]
const DRAG := ["drag_a", "drag_b"]
## decal height / width of the source texture
const ASPECT := {"spray_a": 0.5, "spray_b": 0.5, "smear_a": 0.25, "smear_b": 0.25, "drag_a": 0.25, "drag_b": 0.25,
	"foot_r": 2.0, "foot_l": 2.0, "foot_bare": 2.0, "drips_a": 2.0, "drips_b": 2.0, "outline": 2.0,
	"write_help": 0.3, "write_run": 0.3, "write_sleep": 0.3, "write_out": 0.3}
## fraction of Rimebound fluid that is cyan-tinged ichor instead of blood
const ICHOR_MIX := {"zombie": 0.18, "hound": 0.35, "husk": 0.4, "siren": 0.6, "burster": 0.75, "hanger": 0.5,
	"foreman": 0.5, "boss_choir": 0.5, "boss_hauler": 0.45, "boss_mother": 0.7}

static var _tex := {}
static var _mat := {}
static var _mesh := {}
static var _dyn: Array = []
static var _gibs: Array = []
static var _corpses: Array = []
static var _burst_frame := {}
static var last_hit_pos := Vector3(1e9, 1e9, 1e9)
static var last_hit_msec := -1000
static var src_override := ""       # FX.explosion sets "explosion" while it applies damage
static var _bleed_t := 0.0
static var _bleed_side := false
static var _bleed_pool: Decal = null
static var _bleed_still := 0.0

# =================================================================== resources
static func _t(n: String) -> Texture2D:
	if _tex.has(n):
		return _tex[n]
	var p := TEX + n + ".png"
	var t: Texture2D = load(p) if ResourceLoader.exists(p) else null
	_tex[n] = t
	return t

static func soft_tex() -> Texture2D:
	if _tex.has("_soft"):
		return _tex["_soft"]
	var g := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	g.gradient = gr
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(0.5, 0.0)
	g.width = 64
	g.height = 64
	_tex["_soft"] = g
	return g

static func _std(key: String, albedo: Color, rough: float, spec := 0.7) -> StandardMaterial3D:
	if _mat.has(key):
		return _mat[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic_specular = spec
	if albedo.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat[key] = m
	return m

static func mat_blood(ichor := false) -> StandardMaterial3D:
	return _std("blood_i" if ichor else "blood", Color(0.025, 0.07, 0.08) if ichor else Color(0.19, 0.006, 0.008), 0.1, 0.9)

## thick wet pool / liquid surface material (very glossy, dark)
static func mat_fluid(c := Color(0.16, 0.008, 0.011)) -> StandardMaterial3D:
	var k := "fluid%s" % str(c)
	if _mat.has(k):
		return _mat[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.04
	m.metallic_specular = 1.0
	m.clearcoat_enabled = true
	m.clearcoat = 0.6
	m.clearcoat_roughness = 0.05
	_mat[k] = m
	return m

static func mat_flesh() -> StandardMaterial3D:
	return _std("flesh", Color(0.33, 0.045, 0.05), 0.24, 0.8)

static func mat_flesh_pale() -> StandardMaterial3D:
	return _std("flesh_pale", Color(0.6, 0.3, 0.3), 0.22, 0.8)

static func mat_gut() -> StandardMaterial3D:
	return _std("gut", Color(0.42, 0.16, 0.18), 0.14, 0.95)

static func mat_bone() -> StandardMaterial3D:
	return _std("bone", Color(0.72, 0.66, 0.54), 0.5, 0.4)

static func mat_brain() -> StandardMaterial3D:
	return _std("brain", Color(0.55, 0.33, 0.34), 0.2, 0.8)

static func mat_ice_shard() -> StandardMaterial3D:
	var k := "iceshard"
	if _mat.has(k):
		return _mat[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.88, 1.0, 0.8)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.08
	m.metallic_specular = 0.9
	m.emission_enabled = true
	m.emission = Color(0.4, 0.6, 0.8)
	m.emission_energy_multiplier = 0.35
	_mat[k] = m
	return m

static func _drop_mesh() -> Mesh:
	if _mesh.has("drop"):
		return _mesh["drop"]
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 6
	s.rings = 3
	_mesh["drop"] = s
	return s

static func _chunk_box() -> Mesh:
	if _mesh.has("cbox"):
		return _mesh["cbox"]
	var b := BoxMesh.new()
	b.size = Vector3(1.0, 0.7, 0.85)
	_mesh["cbox"] = b
	return b

static func _quad() -> Mesh:
	if _mesh.has("quad"):
		return _mesh["quad"]
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	_mesh["quad"] = q
	return q

## A lumpy blob (displaced sphere) for flesh chunks / organs. `i` selects one of 6 shapes.
static func chunk_mesh(i: int) -> Mesh:
	var key := "blob%d" % (i % 6)
	if _mesh.has(key):
		return _mesh[key]
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 10
	sm.rings = 6
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms := PackedVector3Array()
	var s := float(i % 6) * 1.7 + 0.3
	for k in verts.size():
		var v := verts[k]
		var f := 1.0 + 0.28 * sin(v.x * 11.0 + s) * cos(v.y * 9.0 + s * 2.0) + 0.2 * sin(v.z * 13.0 + s * 3.0) + 0.1 * sin((v.x + v.y + v.z) * 23.0)
		v = Vector3(v.x * f * (1.0 + 0.2 * sin(s)), v.y * f * 0.8, v.z * f)
		verts[k] = v
		norms.append(v.normalized())
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mesh[key] = am
	return am

## Smooth tube along `pts` (intestines, hoses, tendons...). radii: per point or a single float.
static func tube_mesh(pts: PackedVector3Array, radius: float, sides := 8, taper := 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := pts.size()
	var rings: Array = []
	for i in n:
		var t: Vector3 = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
		var up := Vector3.UP if abs(t.y) < 0.95 else Vector3.RIGHT
		var a := t.cross(up).normalized()
		var b := t.cross(a).normalized()
		var r: float = radius * (1.0 - taper * float(i) / max(n - 1, 1))
		r *= 1.0 + 0.12 * sin(float(i) * 1.7)
		var ring: Array = []
		for j in sides:
			var ang := TAU * float(j) / sides
			ring.append(pts[i] + (a * cos(ang) + b * sin(ang)) * r)
		rings.append(ring)
	for i in n - 1:
		for j in sides:
			var j2 := (j + 1) % sides
			var p00: Vector3 = rings[i][j]
			var p01: Vector3 = rings[i][j2]
			var p10: Vector3 = rings[i + 1][j]
			var p11: Vector3 = rings[i + 1][j2]
			st.add_vertex(p00)
			st.add_vertex(p10)
			st.add_vertex(p01)
			st.add_vertex(p01)
			st.add_vertex(p10)
			st.add_vertex(p11)
	st.generate_normals()
	return st.commit()

# =================================================================== decals
static func _basis(normal: Vector3, tangent: Vector3, roll := 0.0) -> Basis:
	var y := normal.normalized()
	var x := tangent - y * tangent.dot(y)
	if x.length() < 0.01:
		x = y.cross(Vector3.FORWARD if abs(y.z) < 0.95 else Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	var b := Basis(x, y, z)
	if roll != 0.0:
		b = b.rotated(y, roll)
	return b

static func _probe(node: Node, from: Vector3, to: Vector3, mask := 1) -> Dictionary:
	if node == null or not node.is_inside_tree():
		return {}
	var vp := node.get_viewport()
	if vp == null:
		return {}
	var space := vp.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	return space.intersect_ray(q)

## Generic projected decal. `name` is a texture base name in textures/gore (e.g. "pool_a").
## width = metres along the texture's X; opts: ichor, opacity, depth, roll, fade, local, dyn.
static func decal(parent: Node, name: String, pos: Vector3, normal: Vector3, width: float, tangent := Vector3.ZERO, opts := {}) -> Decal:
	if parent == null:
		return null
	var local: bool = opts.get("local", false)
	if not local and not parent.is_inside_tree():
		return null
	var tex := _t(name + "_a")
	if tex == null:
		return null
	var d := Decal.new()
	var asp: float = ASPECT.get(name, 1.0)
	var depth: float = opts.get("depth", clamp(width * 0.4, 0.14, 0.5))
	d.size = Vector3(width, depth, width * asp)
	if opts.get("ichor", false) and _t(name + "_i") != null:
		d.texture_albedo = _t(name + "_i")
	else:
		d.texture_albedo = tex
	d.texture_normal = _t(name + "_n")
	d.texture_orm = _t(name + "_o")
	d.albedo_mix = 1.0
	d.emission_energy = 0.0
	d.normal_fade = opts.get("normal_fade", 0.3)
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	var col: Color = opts.get("color", Color(1, 1, 1))
	col.a = opts.get("opacity", 1.0)
	d.modulate = col
	d.distance_fade_enabled = true
	d.distance_fade_begin = opts.get("fade", 24.0)
	d.distance_fade_length = 8.0
	parent.add_child(d)
	var b := _basis(normal, tangent, opts.get("roll", 0.0))
	if local:
		d.transform = Transform3D(b, pos)
	else:
		d.global_transform = Transform3D(b, pos)
	if opts.get("dyn", false):
		_reg(d)
	return d

static func _reg(d: Decal) -> void:
	_dyn.append(d)
	var alive: Array = []
	for x in _dyn:
		if is_instance_valid(x):
			alive.append(x)
	_dyn = alive
	while _dyn.size() > MAX_DYN_DECALS:
		var old: Decal = _dyn.pop_front()
		if is_instance_valid(old):
			var tw := old.create_tween()
			tw.tween_property(old, "modulate:a", 0.0, 2.0)
			tw.tween_callback(old.queue_free)

static func _icho(opts: Dictionary, p := 0.0) -> Dictionary:
	if p > 0.0 and randf() < p:
		var o := opts.duplicate()
		o["ichor"] = true
		return o
	return opts

## Blood splatter on a surface. dir (optional) = direction the blood travelled (for walls / impacts).
static func splatter(parent: Node, pos: Vector3, normal: Vector3, dir := Vector3.ZERO, size := 0.8, ichor := false, opts := {}) -> Decal:
	var o := opts.duplicate()
	o["ichor"] = ichor
	var name: String = SPLAT[randi() % SPLAT.size()]
	var tangent := Vector3.ZERO
	var roll := randf() * TAU
	if dir.length() > 0.01 and randf() < 0.75:
		name = "splat_wall"
		tangent = dir
		roll = randf_range(-0.2, 0.2)
	o["roll"] = roll
	return decal(parent, name, pos, normal, size, tangent, o)

static func ichor_splatter(parent: Node, pos: Vector3, normal: Vector3, dir := Vector3.ZERO, size := 0.8, opts := {}) -> Decal:
	return splatter(parent, pos, normal, dir, size, true, opts)

## Directional spray streaks (arterial / exit spray) travelling along `dir`.
static func spray_decal(parent: Node, pos: Vector3, normal: Vector3, dir: Vector3, size := 1.3, ichor := false, opts := {}) -> Decal:
	var o := opts.duplicate()
	o["ichor"] = ichor
	o["roll"] = randf_range(-0.15, 0.15)
	# the decal's origin blob sits at x ~ 0.05 of the width: shift the centre along dir
	var n := normal.normalized()
	var t := (dir - n * dir.dot(n)).normalized()
	if t.length() < 0.5:
		t = Vector3.RIGHT
	return decal(parent, SPRAY[randi() % SPRAY.size()], pos + t * size * 0.42, normal, size, t, o)

## Pool on the floor below `pos`; spreads from a tiny puddle over grow_time seconds.
static func pool(parent: Node, pos: Vector3, size := 1.4, grow_time := 4.0, opts := {}) -> Decal:
	var p := pos
	var n := Vector3.UP
	if not opts.get("local", false):
		var h := _probe(parent, pos + Vector3(0, 0.5, 0), pos + Vector3(0, -2.0, 0))
		if h.is_empty():
			return null
		p = h.position
		n = h.normal
	var name: String = POOL[randi() % POOL.size()]
	var o := opts.duplicate()
	o["roll"] = randf() * TAU
	o["depth"] = 0.3
	var start := size * (0.18 if grow_time > 0.0 else 1.0)
	var d := decal(parent, name, p, n, start, Vector3(randf() - 0.5, 0, randf() - 0.5), o)
	if d != null and grow_time > 0.0:
		var tw := d.create_tween()
		tw.tween_property(d, "size", Vector3(size, 0.3, size), grow_time).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	return d

## Drag trail of blood from `from` to `to` (floor), chained decals with a pool at the start.
static func trail(parent: Node, from: Vector3, to: Vector3, opts := {}) -> void:
	var d := to - from
	d.y = 0
	var L := d.length()
	if L < 0.3:
		return
	var dir := d / L
	var step: float = opts.get("step", 1.9)
	var n := int(ceil(L / step))
	var o := opts.duplicate()
	for i in n:
		var c: Vector3 = from + dir * min(step * (i + 0.5), L)
		var h := _probe(parent, c + Vector3(0, 0.6, 0), c + Vector3(0, -1.6, 0))
		if h.is_empty():
			continue
		o["roll"] = randf_range(-0.12, 0.12)
		var oo := o.duplicate()
		if randf() < float(opts.get("ichor_mix", 0.0)):
			oo["ichor"] = true
		decal(parent, DRAG[randi() % DRAG.size()], h.position, h.normal, step * 1.12, dir, oo)
	var hp := _probe(parent, from + Vector3(0, 0.6, 0), from + Vector3(0, -1.6, 0))
	if not hp.is_empty():
		decal(parent, SMEAR[randi() % 2], hp.position, hp.normal, 1.5, dir, o)

## Bloody hand on a wall (fingers up, sliding down 40%) or floor.
static func handprint(parent: Node, pos: Vector3, normal: Vector3, size := 0.2, opts := {}) -> Decal:
	var o := opts.duplicate()
	var name := "hand_r" if randf() < 0.5 else "hand_l"
	if randf() < 0.35:
		name = "hand_smear"
	var n := normal.normalized()
	var t: Vector3
	if abs(n.y) > 0.8:
		var a := randf() * TAU
		t = Vector3(cos(a), 0, sin(a))
	else:
		t = n.cross(Vector3.DOWN)   # X = right, Z = down (fingers up)
		o["roll"] = randf_range(-0.5, 0.5)
	return decal(parent, name, pos, normal, size, t, o)

## Blood running down a wall from `pos` (top anchor).
static func wall_drips(parent: Node, pos: Vector3, normal: Vector3, size := 0.7, opts := {}) -> Decal:
	var o := opts.duplicate()
	var n := normal.normalized()
	var t := n.cross(Vector3.DOWN)
	if t.length() < 0.2:
		return null
	var name := "drips_a" if randf() < 0.6 else "drips_b"
	var p := pos + Vector3.DOWN * size * 0.95
	o["roll"] = randf_range(-0.04, 0.04)
	return decal(parent, name, p, normal, size, t, o)

## Blood-written text on a wall. id: help | run | sleep | out. `pos` = centre of the writing.
static func writing(parent: Node, id: String, pos: Vector3, normal: Vector3, width := 1.6, opts := {}) -> Decal:
	var n := normal.normalized()
	var t := n.cross(Vector3.DOWN)
	var o := opts.duplicate()
	o["depth"] = opts.get("depth", 0.3)
	return decal(parent, "write_" + id, pos, normal, width, t, o)

static func footprint(parent: Node, pos: Vector3, normal: Vector3, dir: Vector3, left := false, bare := false, size := 0.3, opts := {}) -> Decal:
	var n := normal.normalized()
	var f := Vector3(dir.x, 0, dir.z).normalized()
	if f.length() < 0.5:
		return null
	var t := f.cross(n)
	var name := "foot_bare" if bare else ("foot_l" if left else "foot_r")
	var o := opts.duplicate()
	o["depth"] = 0.2
	o["opacity"] = opts.get("opacity", 0.9)
	return decal(parent, name, pos, normal, size * 0.5, t, o)

static func smear(parent: Node, pos: Vector3, normal: Vector3, dir: Vector3, length := 1.6, opts := {}) -> Decal:
	var o := opts.duplicate()
	return decal(parent, SMEAR[randi() % 2], pos, normal, length, dir, o)

static func body_outline(parent: Node, pos: Vector3, yaw := 0.0, size := 1.0, opts := {}) -> Decal:
	var o := opts.duplicate()
	o["depth"] = 0.25
	var t := Vector3(cos(yaw), 0, -sin(yaw))
	return decal(parent, "outline", pos, Vector3.UP, size, t, o)

# =================================================================== fluids
## Glossy water / melt puddle (roughness ~0.03 so SSR / probes reflect in it).
static func puddle(parent: Node, pos: Vector3, size := 1.4, opts := {}) -> Decal:
	var p := pos
	var n := Vector3.UP
	if not opts.get("local", false):
		var h := _probe(parent, pos + Vector3(0, 0.5, 0), pos + Vector3(0, -2.0, 0))
		if h.is_empty():
			return null
		p = h.position
		n = h.normal
	var o := opts.duplicate()
	o["roll"] = randf() * TAU
	o["depth"] = 0.3
	return decal(parent, "puddle_a" if randf() < 0.5 else "puddle_b", p, n, size, Vector3(randf() - 0.5, 0, randf() - 0.5), o)

## Ceiling drip. kind: water | melt | blood | ichor. A drop falls every `interval` s, splashes
## and spreads a ripple (blood drips feed one slowly growing pool).
static func drip_emitter(parent: Node, pos: Vector3, kind := "water", interval := 1.6) -> Node3D:
	var em := Node3D.new()
	em.name = "Drip_" + kind
	parent.add_child(em)
	if parent.is_inside_tree():
		em.global_position = pos
	else:
		em.position = pos
	var st := {"kind": kind, "floor": null, "pool": null, "ripple": null, "n": 0, "ready": false}
	var tm := Timer.new()
	tm.wait_time = interval * randf_range(0.7, 1.3)
	tm.autostart = true
	em.add_child(tm)
	tm.timeout.connect(_drip_tick.bind(em, tm, st, interval))
	return em

static func _drip_tick(em: Node3D, tm: Timer, st: Dictionary, interval: float) -> void:
	if not is_instance_valid(em) or not em.is_inside_tree():
		return
	tm.wait_time = interval * randf_range(0.6, 1.5)
	var pl = Game.player
	if pl == null or not is_instance_valid(pl) or pl.global_position.distance_to(em.global_position) > 26.0:
		return
	var from := em.global_position
	if not st.ready:
		st.ready = true
		var h := _probe(em, from, from + Vector3(0, -9, 0))
		if not h.is_empty():
			st.floor = h
	if st.floor == null:
		return
	var fp: Vector3 = st.floor.position
	var kind: String = st.kind
	var drop := MeshInstance3D.new()
	drop.mesh = _drop_mesh()
	var blood := kind == "blood" or kind == "ichor"
	drop.material_override = mat_blood(kind == "ichor") if blood else _std("water_drop", Color(0.7, 0.85, 0.95, 0.6), 0.04, 1.0)
	drop.scale = Vector3(0.022, 0.034, 0.022)
	drop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	em.get_tree().current_scene.add_child(drop)
	drop.global_position = from
	var tfall := sqrt(2.0 * max(from.y - fp.y, 0.1) / 9.8)
	var tw := drop.create_tween()
	tw.tween_property(drop, "global_position:y", fp.y + 0.01, tfall).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_drip_land.bind(drop, st, fp))

static func _drip_land(drop: MeshInstance3D, st: Dictionary, fp: Vector3) -> void:
	if not is_instance_valid(drop):
		return
	var scene := drop.get_tree().current_scene
	drop.queue_free()
	var n: Vector3 = st.floor.normal
	var kind: String = st.kind
	var blood := kind == "blood" or kind == "ichor"
	# splash
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 5
	p.lifetime = 0.35
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.1
	p.scale_amount_min = 0.008
	p.scale_amount_max = 0.016
	p.mesh = _drop_mesh()
	p.material_override = mat_blood(kind == "ichor") if blood else _std("water_drop", Color(0.7, 0.85, 0.95, 0.6), 0.04, 1.0)
	p.emitting = true
	scene.add_child(p)
	p.global_position = fp + Vector3(0, 0.02, 0)
	var tw := p.create_tween()
	tw.tween_interval(0.6)
	tw.tween_callback(p.queue_free)
	if randf() < 0.6:
		Sfx.play_at("water_drip", fp, -14.0, randf_range(0.85, 1.2))
	st.n += 1
	if blood:
		if st.pool == null or not is_instance_valid(st.pool):
			st.pool = pool(scene, fp, 0.35, 0.0, {"ichor": kind == "ichor"})
		elif st.pool.size.x < 0.9:
			var s: float = st.pool.size.x + 0.025
			st.pool.size = Vector3(s, st.pool.size.y, s)
	else:
		if st.pool == null:
			st.pool = puddle(scene, fp, randf_range(0.7, 1.1))
			st.pool = st.pool if st.pool != null else false
		var r = st.ripple
		if r == null or (r is Decal and not is_instance_valid(r)):
			r = decal(scene, "ripple", fp, n, 0.1, Vector3.RIGHT, {"depth": 0.2, "opacity": 0.0, "normal_fade": 0.0})
			st.ripple = r
		if r is Decal:
			r.global_position = fp + n * 0.005
			r.size = Vector3(0.06, 0.2, 0.06)
			r.modulate.a = 0.8
			var t2: Tween = r.create_tween()
			t2.set_parallel(true)
			t2.tween_property(r, "size", Vector3(0.42, 0.2, 0.42), 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			t2.tween_property(r, "modulate:a", 0.0, 0.9)

## Rising steam / vapour (vents, hot pipes, cooling corpses). Cheap: one CPUParticles3D.
static func steam_vent(parent: Node, pos: Vector3, dir := Vector3.UP, scale := 1.0, alpha := 0.16, life := 0.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = int(14 * scale + 6)
	p.lifetime = 2.6
	p.preprocess = 1.5
	p.direction = dir
	p.spread = 14.0
	p.initial_velocity_min = 0.35 * scale
	p.initial_velocity_max = 0.9 * scale
	p.gravity = Vector3(0, 0.15, 0)
	p.damping_min = 0.1
	p.damping_max = 0.3
	p.scale_amount_min = 0.35 * scale
	p.scale_amount_max = 0.7 * scale
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.35))
	sc.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = sc
	var gr := Gradient.new()
	gr.set_color(0, Color(0.85, 0.9, 0.95, 0.0))
	gr.add_point(0.25, Color(0.85, 0.9, 0.95, alpha))
	gr.set_color(gr.get_point_count() - 1, Color(0.85, 0.9, 0.95, 0.0))
	p.color_ramp = gr
	p.mesh = _quad()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = soft_tex()
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.disable_receive_shadows = true
	p.material_override = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	if parent.is_inside_tree():
		p.global_position = pos
	else:
		p.position = pos
	if life > 0.0:
		var tw := p.create_tween()
		tw.tween_interval(life)
		tw.tween_callback(func(): p.emitting = false)
		tw.tween_interval(3.0)
		tw.tween_callback(p.queue_free)
	return p

## Blood frozen under clear ice: a very dark pool decal under a translucent ice slab with frost.
static func frozen_blood(parent: Node, pos: Vector3, size := 1.6, opts := {}) -> Node3D:
	var r := Node3D.new()
	r.name = "FrozenBlood"
	parent.add_child(r)
	var local: bool = opts.get("local", false)
	if local:
		r.position = pos
	else:
		r.global_position = pos
	var o := opts.duplicate()
	o["local"] = true
	o["color"] = Color(0.8, 0.55, 0.6)
	o["roll"] = randf() * TAU
	var h := 0.0
	var d := decal(r, POOL[randi() % POOL.size()], Vector3(0, 0.0, 0), Vector3.UP, size, Vector3.RIGHT, o)
	if d != null:
		d.size = Vector3(size, 0.5, size)
	var ice := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size * 0.85, 0.03, size * 0.7)
	ice.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.7, 0.85, 0.95, 0.42)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.04
	m.metallic_specular = 1.0
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.03
	m.rim_enabled = true
	m.rim = 0.4
	ice.material_override = m
	ice.position = Vector3(0, 0.02, 0)
	ice.rotation.y = randf() * TAU
	ice.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.add_child(ice)
	# frost crystals poking out of the sheet
	for i in 6:
		var c := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = randf_range(0.015, 0.03)
		cm.height = randf_range(0.06, 0.16)
		cm.radial_segments = 5
		c.mesh = cm
		c.material_override = mat_ice_shard()
		var a := randf() * TAU
		var rr := randf_range(0.1, size * 0.34)
		c.position = Vector3(cos(a) * rr, 0.03 + cm.height * 0.4, sin(a) * rr)
		c.rotation = Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		r.add_child(c)
	return r

# =================================================================== particle helpers
static func _free_later(n: Node, t: float) -> void:
	var tw := n.create_tween()
	tw.tween_interval(t)
	tw.tween_callback(n.queue_free)

static func _emitter(scene: Node, pos: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.92
	p.randomness = 0.3
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(p)
	p.global_position = pos
	return p

## Fast blood droplets flying along `dir`.
static func blood_spray(scene: Node, pos: Vector3, dir: Vector3, amount := 1.0, ichor := false, spread := 22.0) -> void:
	var p := _emitter(scene, pos)
	p.amount = int(clamp(16.0 * amount, 6.0, 64.0))
	p.lifetime = 0.9
	p.direction = dir.normalized()
	p.spread = spread
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0 + 3.5 * amount
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.014
	p.scale_amount_max = 0.04 + 0.01 * amount
	p.mesh = _drop_mesh()
	p.material_override = mat_blood(ichor)
	p.emitting = true
	_free_later(p, 1.3)

## Dark red aerosol mist puff.
static func mist_puff(scene: Node, pos: Vector3, dir: Vector3, amount := 1.0, ichor := false) -> void:
	var p := _emitter(scene, pos)
	p.amount = int(clamp(4.0 * amount, 3.0, 14.0))
	p.lifetime = 0.75
	p.explosiveness = 0.85
	p.direction = dir.normalized()
	p.spread = 35.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0, -0.8, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 0.14 * amount
	p.scale_amount_max = 0.3 * amount
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 1.7))
	p.scale_amount_curve = sc
	var col := Color(0.2, 0.012, 0.012) if not ichor else Color(0.03, 0.12, 0.13)
	var gr := Gradient.new()
	gr.set_color(0, Color(col.r, col.g, col.b, 0.5))
	gr.set_color(1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = gr
	p.mesh = _quad()
	var k := "mist_i" if ichor else "mist"
	if not _mat.has(k):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = soft_tex()
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		_mat[k] = m
	p.material_override = _mat[k]
	p.emitting = true
	_free_later(p, 1.3)

## Chunks of flesh (and optional bone) thrown along dir.
static func chunk_burst(scene: Node, pos: Vector3, dir: Vector3, amount := 1.0, bone := false, ichor := false) -> void:
	var p := _emitter(scene, pos)
	p.amount = int(clamp(6.0 * amount, 3.0, 22.0))
	p.lifetime = 1.1
	p.explosiveness = 1.0
	p.direction = dir.normalized()
	p.spread = 38.0
	p.initial_velocity_min = 1.8
	p.initial_velocity_max = 5.5
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.025
	p.scale_amount_max = 0.07
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.mesh = chunk_mesh(randi() % 6)
	p.material_override = mat_bone() if bone else (_std("flesh_i", Color(0.06, 0.16, 0.17), 0.25) if ichor else mat_flesh())
	p.emitting = true
	_free_later(p, 1.6)

static func ice_shards(scene: Node, pos: Vector3, dir: Vector3, amount := 1.0) -> void:
	var p := _emitter(scene, pos)
	p.amount = int(clamp(10.0 * amount, 5.0, 28.0))
	p.lifetime = 0.9
	p.direction = dir.normalized()
	p.spread = 48.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.02
	p.scale_amount_max = 0.06
	if not _mesh.has("shard"):
		var pm := PrismMesh.new()
		pm.size = Vector3(0.6, 1.6, 0.4)
		_mesh["shard"] = pm
	p.mesh = _mesh["shard"]
	p.material_override = mat_ice_shard()
	p.emitting = true
	_free_later(p, 1.3)
	mist_puff_color(scene, pos, dir, Color(0.82, 0.9, 0.98), 0.5)

static func mist_puff_color(scene: Node, pos: Vector3, dir: Vector3, col: Color, amount: float) -> void:
	var p := _emitter(scene, pos)
	p.amount = 5
	p.lifetime = 0.8
	p.direction = dir.normalized()
	p.spread = 40.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.9
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.1 * amount
	p.scale_amount_max = 0.24 * amount
	var gr := Gradient.new()
	gr.set_color(0, Color(col.r, col.g, col.b, 0.38))
	gr.set_color(1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = gr
	p.mesh = _quad()
	if not _mat.has("mist_w"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = soft_tex()
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		_mat["mist_w"] = m
	p.material_override = _mat["mist_w"]
	p.emitting = true
	_free_later(p, 1.3)

# =================================================================== spray decals (raycast)
## Cast `count` rays from pos spreading around dir; each hit leaves a blood decal after a short
## flight delay. Also drops a couple of droplets on the floor below.
static func spray_decals(scene: Node, pos: Vector3, dir: Vector3, count := 4, reach := 3.0, scale := 1.0, ichor_p := 0.0) -> void:
	if scene == null or not scene.is_inside_tree():
		return
	for i in count:
		var d := (dir + Vector3(randf_range(-0.45, 0.45), randf_range(-0.3, 0.4), randf_range(-0.45, 0.45))).normalized()
		var from := pos + d * 0.08
		var h := _probe(scene, from, from + d * reach)
		if h.is_empty():
			continue
		var dist := pos.distance_to(h.position)
		var delay := dist / 7.5
		scene.get_tree().create_timer(delay).timeout.connect(_spawn_hit_decal.bind(scene, h.position, h.normal, d, scale * lerp(1.0, 0.45, dist / reach), randf() < ichor_p))
	# a couple of floor drops under the wound
	var f := _probe(scene, pos, pos + Vector3(0, -3.0, 0))
	if not f.is_empty():
		scene.get_tree().create_timer(sqrt(2.0 * max(pos.y - f.position.y, 0.1) / 9.8)).timeout.connect(
			_spawn_hit_decal.bind(scene, f.position, f.normal, Vector3(dir.x, 0, dir.z), 0.35 * scale, randf() < ichor_p))

static func _spawn_hit_decal(scene: Node, pos: Vector3, normal: Vector3, dir: Vector3, scale: float, ichor: bool) -> void:
	if not is_instance_valid(scene) or not scene.is_inside_tree():
		return
	var o := {"dyn": true, "ichor": ichor, "fade": 22.0}
	var floor_like := normal.y > 0.7
	var r := randf()
	if floor_like:
		if r < 0.45:
			o["roll"] = randf() * TAU
			decal(scene, SPLAT[randi() % 4], pos + normal * 0.01, normal, randf_range(0.4, 0.8) * scale, Vector3.ZERO, o)
		elif r < 0.8:
			spray_decal(scene, pos, normal, dir, randf_range(0.9, 1.5) * scale, ichor, {"dyn": true})
		else:
			splatter(scene, pos, normal, dir, randf_range(0.4, 0.7) * scale, ichor, {"dyn": true})
	else:
		if r < 0.55:
			spray_decal(scene, pos, normal, dir, randf_range(0.9, 1.6) * scale, ichor, {"dyn": true})
		else:
			splatter(scene, pos, normal, dir, randf_range(0.4, 0.9) * scale, ichor, {"dyn": true})
		if randf() < 0.3 * scale and normal.y > -0.3:
			wall_drips(scene, pos + Vector3(0, 0.1, 0), normal, randf_range(0.35, 0.6) * scale, {"dyn": true, "ichor": ichor})

# =================================================================== enemy hooks
static func weapon_of(src := "") -> String:
	if src_override != "":
		return src_override
	if src == "fire":
		return "fire"
	var eq = Game.equipped
	return eq if eq != null else ""

static func _kind(e: Node) -> String:
	var sc = e.get_script()
	if sc == null:
		return "zombie"
	return String(sc.resource_path).get_file().get_basename()

static func _is_boss(e: Node) -> bool:
	return _kind(e).begins_with("boss_")

static func _model_has_head(e: Node) -> bool:
	var m = e.get("model")
	if m == null:
		return false
	if m.has_method("set_bone_hidden"):
		return true
	return m.get("skeleton") == null and m.get("head") != null

## Called from Enemy.take_hit for every damaging hit.
static func on_enemy_hit(e: Node3D, dmg: float, pos: Vector3, dir: Vector3, headshot: bool, src := "") -> void:
	if e == null or not e.is_inside_tree():
		return
	var scene := e.get_tree().current_scene
	var w := weapon_of(src)
	var kind := _kind(e)
	var d := Vector3(dir.x, dir.y, dir.z)
	if d.length() < 0.01:
		d = Vector3.FORWARD
	d = d.normalized()
	last_hit_pos = pos
	last_hit_msec = Time.get_ticks_msec()
	e.set_meta("gore_dir", d)
	e.set_meta("gore_pos", pos)
	if w == "fire":
		_fire_hit(e, pos)
		return
	# frozen target? armoured husk plate, rime crust on a shambler / siren, crystalline Foreman limbs
	var frozen := false
	var rime: float = float(e.get("rime")) if e.get("rime") != null else 0.0
	if kind == "husk" and float(e.get("armor_hp")) > 0.0:
		frozen = true
	elif kind == "foreman":
		frozen = randf() < 0.5
	elif kind in ["zombie", "siren", "hanger"] and not headshot:
		frozen = randf() < 0.28 * clamp(rime, 0.0, 1.6)
	var frame := Engine.get_physics_frames()
	var key := e.get_instance_id()
	var rep: bool = _burst_frame.get(key, -1) == frame
	_burst_frame[key] = frame
	if _burst_frame.size() > 300:
		_burst_frame.clear()
	if frozen:
		if not rep:
			ice_shards(scene, pos, -d + Vector3(0, 0.25, 0), 1.0 if w != "shotgun" else 1.6)
			Sfx.play_at("ice_crack", pos, -4.0, randf_range(0.9, 1.15))
		return
	var ichor_p: float = ICHOR_MIX.get(kind, 0.2)
	var ich := randf() < ichor_p
	var amt := 1.0
	var spread := 20.0
	match w:
		"shotgun":
			amt = 0.85
			spread = 30.0
		"magnum":
			amt = 2.2
			spread = 16.0
		"knife":
			amt = 0.9
			spread = 35.0
		"explosion":
			amt = 1.6
			spread = 70.0
	if headshot:
		amt *= 1.4
	if rep:
		amt *= 0.35
	var big := _is_boss(e)
	if big:
		amt *= 1.8
	blood_spray(scene, pos, d + Vector3(0, 0.1, 0), amt, ich, spread)
	if not rep:
		Sfx.play_at("gore_hit", pos, -7.0 + (3.0 if w == "magnum" else 0.0), randf_range(0.85, 1.15))
	if not rep or randf() < 0.3:
		mist_puff(scene, pos, d, amt * 0.8, ich)
		blood_spray(scene, pos, -d + Vector3(0, 0.2, 0), amt * 0.4, ich, 55.0)   # entry back-spatter
	if (w == "magnum" or w == "shotgun" or w == "explosion" or big) and not rep:
		chunk_burst(scene, pos, d, amt, headshot and randf() < 0.5, ich)
	spray_decals(scene, pos, d, int(clamp(3.0 * amt, 2.0, 7.0)) if not rep else 1, 3.0, 1.0 if not big else 1.6, ichor_p)
	_wound(e, pos, d, amt, ich)

## Fallback used by FX.blood_burst when the enemy did not run the hook (bosses override take_hit).
static func fallback_hit(scene: Node, pos: Vector3, normal: Vector3) -> void:
	if scene == null or not scene.is_inside_tree():
		return
	if Time.get_ticks_msec() - last_hit_msec < 60 and pos.distance_to(last_hit_pos) < 0.05:
		return
	var best: Node3D = null
	var bd := 1.8
	for e in scene.get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e is Node3D:
			var dd: float = (e as Node3D).global_position.distance_to(pos - Vector3(0, 0.8, 0))
			if dd < bd:
				bd = dd
				best = e
	var d := -normal.normalized()
	var big := best != null and _is_boss(best)
	var kind := _kind(best) if best != null else "zombie"
	if kind == "husk" and float(best.get("armor_hp")) > 0.0:
		ice_shards(scene, pos, normal + Vector3(0, 0.25, 0), 1.0)
		return
	var ichor_p: float = ICHOR_MIX.get(kind, 0.3)
	var ich := randf() < ichor_p
	var w := weapon_of()
	var amt: float = float({"magnum": 2.2, "shotgun": 0.85, "knife": 0.9}.get(w, 1.0)) * (1.8 if big else 1.0)
	blood_spray(scene, pos, d + Vector3(0, 0.1, 0), amt, ich, 22.0)
	mist_puff(scene, pos, d, amt * 0.8, ich)
	if w == "magnum" or big:
		chunk_burst(scene, pos, d, amt, false, ich)
	spray_decals(scene, pos, d, int(clamp(2.5 * amt, 2.0, 6.0)), 3.0, 1.0 if not big else 1.8, ichor_p)

static func _fire_hit(e: Node3D, pos: Vector3) -> void:
	var now := Time.get_ticks_msec()
	if now - int(e.get_meta("gore_fire_ms", -5000)) < 1100:
		return
	e.set_meta("gore_fire_ms", now)
	var scene := e.get_tree().current_scene
	if randf() < 0.35:
		steam_vent(scene, pos, Vector3.UP, 0.6, 0.12, 0.6)
	var p := _emitter(scene, pos)
	p.amount = 5
	p.lifetime = 0.9
	p.direction = Vector3.UP
	p.spread = 40.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, 0.4, 0)
	p.scale_amount_min = 0.008
	p.scale_amount_max = 0.018
	p.mesh = _drop_mesh()
	var em := _std("ember", Color(1.0, 0.45, 0.12), 0.5)
	em.emission_enabled = true
	em.emission = Color(1.0, 0.4, 0.1)
	em.emission_energy_multiplier = 4.0
	p.material_override = em
	p.emitting = true
	_free_later(p, 1.2)

## Wound decal stuck on the body itself (moves with the enemy, stays on the corpse).
static func _wound(e: Node3D, pos: Vector3, dir: Vector3, amt: float, ichor: bool) -> void:
	var list: Array = e.get_meta("gore_wounds", [])
	var alive: Array = []
	for w in list:
		if is_instance_valid(w):
			alive.append(w)
	list = alive
	while list.size() >= MAX_WOUNDS:
		var old = list.pop_front()
		old.queue_free()
	var n := -dir
	var nm: String = SPLAT[randi() % 4] if randf() < 0.6 else "splat_wall"
	var o := {"ichor": ichor and randf() < 0.5, "fade": 16.0, "depth": 0.5, "normal_fade": 0.15, "roll": randf() * TAU}
	var d := decal(e, nm, pos + n * 0.05, n, clamp(0.28 + 0.12 * amt, 0.25, 0.7), Vector3.ZERO, o)
	if d != null:
		list.append(d)
	e.set_meta("gore_wounds", list)

## Called from Enemy._die once the enemy is really dead.
static func on_enemy_death(e: Node3D, headshot: bool, src := "") -> void:
	if e == null or not e.is_inside_tree():
		return
	var scene := e.get_tree().current_scene
	var w := weapon_of(src)
	var kind := _kind(e)
	var boss := _is_boss(e)
	var d: Vector3 = e.get_meta("gore_dir", Vector3.FORWARD)
	var hpos: Vector3 = e.get_meta("gore_pos", e.global_position + Vector3(0, 1.2, 0))
	var ichor_p: float = ICHOR_MIX.get(kind, 0.2)
	var ich := randf() < ichor_p
	# corpse bookkeeping: the oldest bodies sink away past the cap
	_corpses.append(e)
	_trim_corpses()
	# blood pool spreading under the body
	var psize := 1.9
	match kind:
		"hound":
			psize = 1.1
		"burster":
			psize = 2.4
		"hanger":
			psize = 1.6
	if e.get("crawler") == true:
		psize = 1.3
	if boss:
		psize = 4.5
	var fire_kill := w == "fire"
	if w == "magnum" or w == "shotgun" or w == "explosion":
		psize *= 1.25
	if not fire_kill or randf() < 0.4:
		e.get_tree().create_timer(0.9).timeout.connect(_death_pool.bind(e, psize, ich))
	# torso exit-wound spray on a close wall
	spray_decals(scene, hpos, d, 3 if not boss else 8, 3.0, 1.0 if not boss else 1.8, ichor_p)
	if boss:
		for i in 3:
			var p := e.global_position + Vector3(randf_range(-1.5, 1.5), randf_range(0.8, 3.0), randf_range(-1.5, 1.5))
			blood_spray(scene, p, Vector3.UP + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)), 3.0, ich, 60.0)
			chunk_burst(scene, p, Vector3.UP, 3.0, i == 0, ich)
			mist_puff(scene, p, Vector3.UP, 3.0, ich)
		return
	if fire_kill:
		_char_model(e)
		steam_vent(scene, e.global_position + Vector3(0, 0.5, 0), Vector3.UP, 0.8, 0.14, 7.0)
		return
	# dismemberment / head pop
	var pl = Game.player
	var dist := 99.0
	if pl != null and is_instance_valid(pl):
		dist = pl.global_position.distance_to(e.global_position)
	if headshot and kind in ["zombie", "siren", "husk"] and _model_has_head(e):
		if not (kind == "husk" and float(e.get("armor_hp")) > 0.0):
			var pop := false
			match w:
				"magnum":
					pop = true
				"shotgun":
					pop = dist < 9.0
				"handgun":
					pop = dist < 5.0 and randf() < 0.5
				"explosion":
					pop = true
			if pop:
				head_pop(e, d, w)
				return
	if kind in ["zombie", "husk", "siren"] and (w == "explosion" or (w == "shotgun" and dist < 4.5 and randf() < 0.55) or (w == "magnum" and randf() < 0.3)):
		lose_limb(e, "", d, w)

static func _death_pool(e: Node3D, size: float, ichor: bool) -> void:
	if not is_instance_valid(e) or not e.is_inside_tree():
		return
	var p := e.global_position + Vector3(0, 0.1, 0)
	var fwd := -e.global_transform.basis.z
	pool(e.get_tree().current_scene, p + fwd * 0.1, size, 7.0, {"dyn": true, "ichor": ichor})

static func _trim_corpses() -> void:
	var alive: Array = []
	for c in _corpses:
		if is_instance_valid(c):
			alive.append(c)
	_corpses = alive
	while _corpses.size() > MAX_CORPSES:
		var old: Node3D = _corpses.pop_front()
		var m = old.get("model")
		var tw := old.create_tween()
		tw.tween_property(m if m != null else old, "position:y", -0.8, 4.0).as_relative()
		tw.tween_callback(old.queue_free)

## Dark charring + soot on a burnt model.
static func _char_model(e: Node3D) -> void:
	var m = e.get("model")
	if m == null:
		return
	for mi in (m as Node).find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		var done := false
		if inst.material_override is StandardMaterial3D:
			var mat := (inst.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
			_char_mat(mat)
			inst.material_override = mat
			done = true
		if not done and inst.mesh != null:
			for s in inst.mesh.get_surface_count():
				var am := inst.get_active_material(s)
				if am is StandardMaterial3D:
					var mat2 := (am as StandardMaterial3D).duplicate() as StandardMaterial3D
					_char_mat(mat2)
					inst.set_surface_override_material(s, mat2)

static func _char_mat(m: StandardMaterial3D) -> void:
	var c := m.albedo_color
	m.albedo_color = Color(c.r * 0.16 + 0.015, c.g * 0.14 + 0.012, c.b * 0.13 + 0.01, c.a)
	m.roughness = 0.88
	m.metallic = 0.0
	m.rim_enabled = false
	m.subsurf_scatter_enabled = false

# =================================================================== gibs & dismemberment
static func _gib_body(scene: Node, pos: Vector3, vel: Vector3, shape_r: float, mass := 0.4) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.collision_layer = 0
	rb.collision_mask = 1
	rb.mass = mass
	rb.continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.12
	pm.friction = 0.9
	rb.physics_material_override = pm
	rb.linear_damp = 0.15
	rb.angular_damp = 0.5
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = shape_r
	cs.shape = sh
	rb.add_child(cs)
	rb.contact_monitor = true
	rb.max_contacts_reported = 3
	scene.add_child(rb)
	rb.global_position = pos
	rb.linear_velocity = vel
	rb.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
	rb.set_meta("hits", 0)
	rb.body_entered.connect(_gib_hit.bind(rb))
	# register + cap
	_gibs.append(rb)
	var alive: Array = []
	for g in _gibs:
		if is_instance_valid(g):
			alive.append(g)
	_gibs = alive
	while _gibs.size() > MAX_GIBS:
		var old: Node3D = _gibs.pop_front()
		var tw := old.create_tween()
		tw.tween_property(old, "scale", Vector3.ONE * 0.01, 1.5)
		tw.tween_callback(old.queue_free)
	return rb

static func _gib_hit(_other: Node, rb: RigidBody3D) -> void:
	if not is_instance_valid(rb) or not rb.is_inside_tree():
		return
	var hits: int = rb.get_meta("hits", 0)
	if hits >= 2 or rb.linear_velocity.length() < 0.8:
		return
	rb.set_meta("hits", hits + 1)
	var scene := rb.get_tree().current_scene
	var v := rb.linear_velocity
	var d := v.normalized() if v.length() > 0.1 else Vector3.DOWN
	var h := _probe(scene, rb.global_position, rb.global_position + d * 0.7)
	if h.is_empty():
		h = _probe(scene, rb.global_position, rb.global_position + Vector3.DOWN * 0.7)
	if h.is_empty():
		return
	Sfx.play_at("gore_splat", rb.global_position, -5.0, randf_range(0.85, 1.15))
	if rb.get_meta("ichor", false):
		_spawn_hit_decal(scene, h.position, h.normal, d, 0.55, true)
	else:
		_spawn_hit_decal(scene, h.position, h.normal, d, 0.65, false)
	blood_spray(scene, rb.global_position, h.normal + Vector3(0, 0.3, 0), 0.6, rb.get_meta("ichor", false), 50.0)

static func _gib_drip(rb: Node3D, secs := 1.6, ichor := false) -> void:
	var p := CPUParticles3D.new()
	p.local_coords = false
	p.amount = 18
	p.lifetime = 0.5
	p.direction = Vector3.DOWN
	p.spread = 70.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.6
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.01
	p.scale_amount_max = 0.025
	p.mesh = _drop_mesh()
	p.material_override = mat_blood(ichor)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rb.add_child(p)
	var tw := p.create_tween()
	tw.tween_interval(secs)
	tw.tween_callback(func(): p.emitting = false)
	tw.tween_interval(0.8)
	tw.tween_callback(p.queue_free)

## kind: skull | jaw | flesh | bone | brain | eye | arm | leg
static func gib(scene: Node, pos: Vector3, kind: String, vel: Vector3, scale := 1.0, ichor := false) -> RigidBody3D:
	var r := 0.06 * scale
	var rb := _gib_body(scene, pos, vel, r * (1.4 if kind in ["skull", "arm", "leg"] else 1.0), 0.6 if kind in ["arm", "leg"] else 0.3)
	rb.set_meta("ichor", ichor)
	var fl: Material = _std("flesh_i", Color(0.06, 0.16, 0.17), 0.25) if ichor else mat_flesh()
	match kind:
		"skull":
			var cap := MeshInstance3D.new()
			var hs := SphereMesh.new()
			hs.radius = 0.095 * scale
			hs.height = 0.19 * scale
			hs.is_hemisphere = true
			hs.radial_segments = 12
			hs.rings = 6
			cap.mesh = hs
			cap.material_override = mat_bone()
			cap.rotation.x = PI * 0.5 if randf() < 0.0 else 0.0
			rb.add_child(cap)
			var inner := MeshInstance3D.new()
			var hs2 := SphereMesh.new()
			hs2.radius = 0.085 * scale
			hs2.height = 0.17 * scale
			hs2.is_hemisphere = true
			hs2.radial_segments = 12
			hs2.rings = 6
			inner.mesh = hs2
			inner.material_override = mat_brain()
			inner.position.y = 0.012 * scale
			rb.add_child(inner)
			rb.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		"jaw":
			var j := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.1, 0.035, 0.09) * scale
			j.mesh = bm
			j.material_override = mat_bone()
			rb.add_child(j)
			var fl2 := MeshInstance3D.new()
			fl2.mesh = chunk_mesh(2)
			fl2.scale = Vector3(0.08, 0.05, 0.07) * scale
			fl2.material_override = fl
			fl2.position = Vector3(0, 0.025 * scale, 0)
			rb.add_child(fl2)
		"eye":
			var e := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.014 * scale
			sm.height = 0.028 * scale
			e.mesh = sm
			e.material_override = _std("eyeball", Color(0.82, 0.78, 0.74), 0.12, 1.0)
			rb.add_child(e)
		"arm", "leg":
			var len := 0.55 * scale if kind == "arm" else 0.85 * scale
			var rad := 0.045 * scale if kind == "arm" else 0.07 * scale
			var cm := CylinderMesh.new()
			cm.height = len
			cm.top_radius = rad
			cm.bottom_radius = rad * 0.7
			cm.radial_segments = 10
			var seg := MeshInstance3D.new()
			seg.mesh = cm
			seg.material_override = _std("limb", Color(0.45, 0.4, 0.36), 0.7, 0.3)
			seg.rotation.z = PI * 0.5
			rb.add_child(seg)
			var cut := MeshInstance3D.new()
			cut.mesh = chunk_mesh(1)
			cut.scale = Vector3(rad * 1.5, len * 0.1, rad * 1.5)
			cut.material_override = fl
			cut.rotation.z = PI * 0.5
			cut.position = Vector3(len * 0.5, 0, 0)
			rb.add_child(cut)
			var bn := MeshInstance3D.new()
			var bc := CylinderMesh.new()
			bc.top_radius = rad * 0.28
			bc.bottom_radius = rad * 0.28
			bc.height = len * 0.12
			bn.mesh = bc
			bn.material_override = mat_bone()
			bn.rotation.z = PI * 0.5
			bn.position = Vector3(len * 0.5 + len * 0.05, 0, 0)
			rb.add_child(bn)
			var hand := MeshInstance3D.new()
			hand.mesh = chunk_mesh(4)
			hand.scale = Vector3(0.11, 0.05, 0.09) * scale if kind == "arm" else Vector3(0.28, 0.1, 0.12) * scale
			hand.material_override = _std("limb", Color(0.45, 0.4, 0.36), 0.7, 0.3)
			hand.position = Vector3(-len * 0.52, 0, 0)
			rb.add_child(hand)
			# limb cylinder collision is a sphere: widen it
			(rb.get_child(0) as CollisionShape3D).shape = SphereShape3D.new()
			((rb.get_child(0) as CollisionShape3D).shape as SphereShape3D).radius = rad * 1.2
		_:
			var m := MeshInstance3D.new()
			m.mesh = chunk_mesh(randi() % 6)
			m.scale = Vector3(1.0, 0.8, 0.9) * 0.14 * scale * randf_range(0.6, 1.3)
			m.material_override = mat_bone() if kind == "bone" else (mat_brain() if kind == "brain" else fl)
			rb.add_child(m)
	if kind != "eye" and kind != "bone":
		_gib_drip(rb, 1.8, ichor)
	return rb

## Wet, ragged stump cap + bone, attached to `holder` at world position `at`.
static func stump(holder: Node3D, at: Vector3, radius := 0.05, ichor := false) -> MeshInstance3D:
	var s := MeshInstance3D.new()
	s.mesh = chunk_mesh(3)
	s.material_override = _std("flesh_i", Color(0.06, 0.16, 0.17), 0.25) if ichor else mat_flesh()
	s.scale = Vector3(radius * 2.3, radius * 1.4, radius * 2.3)
	holder.add_child(s)
	s.global_position = at
	var b := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = radius * 0.3
	bc.bottom_radius = radius * 0.34
	bc.height = radius * 1.4
	bc.radial_segments = 8
	b.mesh = bc
	b.material_override = mat_bone()
	b.position = Vector3(0, radius * 0.5, 0)
	s.add_child(b)
	b.scale = Vector3(1.0 / (radius * 2.3), 1.0 / (radius * 1.4), 1.0 / (radius * 2.3))
	return s

static func _hide_part(model: Node, parts: Array, pivots: Array) -> void:
	if model.has_method("set_bone_hidden"):
		for p in parts:
			model.call("set_bone_hidden", p)
	else:
		for pv in pivots:
			var n = model.get(pv)
			if n is Node3D:
				(n as Node3D).visible = false

## Blow the head off: gore burst, skull/flesh gibs, wet neck stump with pulsing arterial spray.
static func head_pop(e: Node3D, dir: Vector3, weapon := "magnum") -> void:
	var m = e.get("model")
	if m == null or e.has_meta("gore_head_gone"):
		return
	e.set_meta("gore_head_gone", true)
	var scene := e.get_tree().current_scene
	var head: Node3D = m.get("head") as Node3D
	var hp := e.global_position + Vector3(0, 1.6, 0)
	if head != null:
		hp = head.global_transform * Vector3(0, 0.1, 0)
	var kind := _kind(e)
	var ich := randf() < float(ICHOR_MIX.get(kind, 0.2)) * 0.7
	_hide_part(m, ["head"], ["head"])
	# stump on the neck (or chest)
	var holder: Node3D = (m.get("neck") as Node3D) if m.get("neck") != null else (m.get("chest") as Node3D)
	if holder == null:
		holder = m
	var sp := stump(holder, hp - Vector3(0, 0.07, 0), 0.05, ich)
	# neck spurts: a few heartbeat pulses
	var jet := CPUParticles3D.new()
	jet.one_shot = true
	jet.emitting = false
	jet.amount = 22
	jet.lifetime = 0.8
	jet.explosiveness = 0.9
	jet.direction = Vector3.UP
	jet.spread = 14.0
	jet.initial_velocity_min = 1.6
	jet.initial_velocity_max = 3.2
	jet.gravity = Vector3(0, -9.8, 0)
	jet.scale_amount_min = 0.014
	jet.scale_amount_max = 0.034
	jet.local_coords = false
	jet.mesh = _drop_mesh()
	jet.material_override = mat_blood(ich)
	jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sp.add_child(jet)
	jet.position = Vector3(0, 0.03, 0)
	var tw := jet.create_tween()
	var iv := 0.42
	for i in 8:
		tw.tween_callback(func():
			if is_instance_valid(jet):
				jet.amount = max(6, 22 - i * 2)
				jet.restart())
		tw.tween_interval(iv)
		iv += 0.1
	# explosion of gore at the head
	var up := Vector3(0, 0.25, 0)
	blood_spray(scene, hp, dir + up, 3.4, ich, 40.0)
	blood_spray(scene, hp, Vector3.UP, 2.0, ich, 70.0)
	mist_puff(scene, hp, dir, 3.0, ich)
	mist_puff(scene, hp, Vector3.UP, 2.0, ich)
	chunk_burst(scene, hp, dir + up, 4.0, false, ich)
	chunk_burst(scene, hp, dir + up, 3.0, true, ich)
	spray_decals(scene, hp, dir, 8, 4.0, 1.5, 0.3)
	spray_decals(scene, hp, -dir, 3, 3.0, 1.0, 0.3)
	# gibs
	var base := dir * randf_range(2.5, 4.5) + Vector3(0, randf_range(2.0, 3.8), 0)
	gib(scene, hp, "skull", base + _rv(1.2), 1.0, ich)
	gib(scene, hp, "jaw", base * 0.8 + _rv(1.5), 1.0, ich)
	gib(scene, hp, "eye", base * 0.6 + _rv(1.5), 1.0, ich)
	for i in 3:
		gib(scene, hp, "flesh", base * randf_range(0.5, 1.1) + _rv(2.0), randf_range(0.6, 1.1), ich)
	for i in 2:
		gib(scene, hp, "brain", base * randf_range(0.3, 0.8) + _rv(1.8), 0.8, ich)
	gib(scene, hp, "bone", base * randf_range(0.5, 1.0) + _rv(2.0), 0.6, ich)
	Sfx.play_at("gore_pop", hp, 2.0, randf_range(0.9, 1.05))
	# the pool under the stump grows larger and keeps pulsing
	e.get_tree().create_timer(0.5).timeout.connect(_death_pool.bind(e, 2.6, ich))

static func _rv(s: float) -> Vector3:
	return Vector3(randf_range(-s, s), randf_range(-s * 0.4, s * 0.6), randf_range(-s, s))

## Tear off an arm or leg. which: "" (random) | arm_l | arm_r | leg_l | leg_r
static func lose_limb(e: Node3D, which: String, dir: Vector3, _weapon := "shotgun") -> void:
	var m = e.get("model")
	if m == null:
		return
	if not (m.has_method("set_bone_hidden") or m.get("skeleton") == null):
		return
	var opts := ["arm_l", "arm_r"] if e.get("crawler") == true else ["arm_l", "arm_r", "leg_l", "leg_r"]
	if which == "":
		which = opts[randi() % opts.size()]
	if e.has_meta("gore_lost_" + which):
		return
	e.set_meta("gore_lost_" + which, true)
	var side := which.substr(which.length() - 1)
	var is_arm := which.begins_with("arm")
	var scene := e.get_tree().current_scene
	var piv_name := ("arm_" if is_arm else "thigh_") + side
	var piv: Node3D = m.get(piv_name) as Node3D
	var at := e.global_position + Vector3(0, 1.35 if is_arm else 0.95, 0)
	if piv != null:
		at = piv.global_position
	var ich := randf() < float(ICHOR_MIX.get(_kind(e), 0.2))
	if is_arm:
		_hide_part(m, ["upperarm_" + side, "lowerarm_" + side, "hand_" + side], ["arm_" + side, "fore_" + side, "hand_" + side])
	else:
		_hide_part(m, ["thigh_" + side, "calf_" + side, "foot_" + side], ["thigh_" + side, "shin_" + side, "foot_" + side])
	var holder: Node3D = (m.get("chest") if is_arm else m.get("hips")) as Node3D
	if holder == null:
		holder = m
	stump(holder, at, 0.055 if is_arm else 0.08, ich)
	Sfx.play_at("gore_tear", at, 0.0, randf_range(0.9, 1.1))
	blood_spray(scene, at, dir + Vector3(0, 0.3, 0), 3.0, ich, 55.0)
	mist_puff(scene, at, dir, 2.0, ich)
	chunk_burst(scene, at, dir + Vector3(0, 0.3, 0), 2.5, true, ich)
	spray_decals(scene, at, dir, 6, 3.5, 1.4, 0.3)
	gib(scene, at, "arm" if is_arm else "leg", dir * randf_range(2.0, 4.0) + Vector3(0, randf_range(1.5, 3.0), 0) + _rv(1.2), 1.0, ich)
	for i in 2:
		gib(scene, at, "flesh", dir * 2.5 + Vector3(0, 2.0, 0) + _rv(2.0), 0.8, ich)
	var jet := CPUParticles3D.new()
	jet.local_coords = false
	jet.amount = 24
	jet.lifetime = 0.6
	jet.direction = Vector3.DOWN if not is_arm else dir
	jet.spread = 40.0
	jet.initial_velocity_min = 0.4
	jet.initial_velocity_max = 1.4
	jet.gravity = Vector3(0, -9.8, 0)
	jet.scale_amount_min = 0.012
	jet.scale_amount_max = 0.03
	jet.mesh = _drop_mesh()
	jet.material_override = mat_blood(ich)
	jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(jet)
	jet.global_position = at
	var tw := jet.create_tween()
	tw.tween_interval(3.0)
	tw.tween_callback(func(): jet.emitting = false)
	tw.tween_interval(1.0)
	tw.tween_callback(jet.queue_free)

# =================================================================== player bleeding
## Called every frame from ui/blood_screen.gd: in DANGER the player leaves drops, bloody
## footprints and (when still) a growing pool behind.
static func player_bleed(delta: float) -> void:
	var pl = Game.player
	if pl == null or not is_instance_valid(pl) or not pl.is_inside_tree() or Game.hp <= 0:
		return
	var st := Game.health_state()
	if st == "FINE":
		_bleed_still = 0.0
		return
	var spd := Vector2(pl.velocity.x, pl.velocity.z).length() if pl.get("velocity") != null else 0.0
	var every := 0.7 if st == "DANGER" else 3.0
	_bleed_t += delta
	if spd < 0.3:
		_bleed_still += delta
		if st == "DANGER" and _bleed_still > 2.5 and (_bleed_pool == null or not is_instance_valid(_bleed_pool)):
			_bleed_pool = pool(pl.get_tree().current_scene, pl.global_position + Vector3(0, 0.1, 0), 0.9, 6.0, {"dyn": true})
		return
	_bleed_still = 0.0
	_bleed_pool = null
	if _bleed_t < every * (1.4 - clamp(spd / 6.0, 0.0, 0.5)):
		return
	_bleed_t = 0.0
	var scene := pl.get_tree().current_scene
	var h := _probe(scene, pl.global_position + Vector3(0, 0.6, 0), pl.global_position + Vector3(0, -1.0, 0))
	if h.is_empty():
		return
	var vel := Vector3(pl.velocity.x, 0, pl.velocity.z)
	var back: Vector3 = -vel.normalized()
	var at: Vector3 = h.position + back * 0.35
	if st == "DANGER" and randf() < 0.5:
		_bleed_side = not _bleed_side
		footprint(scene, h.position + vel.normalized().cross(Vector3.UP) * (0.12 if _bleed_side else -0.12), h.normal, vel, _bleed_side, false, 0.34, {"dyn": true, "opacity": 0.75})
	else:
		decal(scene, "splat_c", at + Vector3(0, 0.01, 0), h.normal, randf_range(0.22, 0.4), Vector3.ZERO, {"dyn": true, "roll": randf() * TAU})
		if randf() < 0.3:
			smear(scene, at, h.normal, back, 0.9, {"dyn": true, "opacity": 0.8})

## The player was hurt: a spurt of blood in the world (spray, floor drops, wall spatter if close).
static func player_hurt_fx() -> void:
	var pl = Game.player
	if pl == null or not is_instance_valid(pl) or not pl.is_inside_tree():
		return
	var scene := pl.get_tree().current_scene
	var chest: Vector3 = pl.global_position + Vector3(0, 1.3, 0)
	var back := Vector3(randf_range(-1, 1), 0.15, randf_range(-1, 1)).normalized()
	blood_spray(scene, chest, back, 1.0, false, 45.0)
	mist_puff(scene, chest, back, 0.7, false)
	spray_decals(scene, chest, back, 3, 2.5, 0.9, 0.0)

## Generic big gore burst (boss weak points, burst sacs, explosions). Callable from any actor:
##   Gore.burst(get_tree().current_scene, world_pos, direction, 2.5, true)
static func burst(scene: Node, pos: Vector3, dir := Vector3.UP, amount := 2.0, ichor := false, decals := 6) -> void:
	if scene == null or not scene.is_inside_tree():
		return
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.UP
	blood_spray(scene, pos, d + Vector3(0, 0.2, 0), amount * 1.6, ichor, 55.0)
	blood_spray(scene, pos, Vector3.UP, amount, ichor, 80.0)
	mist_puff(scene, pos, d, amount * 1.2, ichor)
	chunk_burst(scene, pos, d + Vector3(0, 0.3, 0), amount * 1.5, randf() < 0.5, ichor)
	spray_decals(scene, pos, d, decals, 4.0, 1.0 + amount * 0.3, 0.5 if ichor else 0.2)
	Sfx.play_at("gore_hit", pos, -2.0, randf_range(0.7, 0.9))
