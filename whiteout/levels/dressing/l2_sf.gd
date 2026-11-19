extends RefCounted
## Interior dressing helpers (R7-B): Sketchfab props from assets/env/interior_sf, projected grime decals
## (assets/env/interior_sf/decals, built by tools/interior/make_grime.py from ambientCG CC0 sets),
## lumpy fabric blankets, skirting.  Shared by L2 (school) and L3 (shops, church).
##
## Everything is placed in the caller's local space with explicit floor heights.

const Env = preload("res://world/env_assets.gd")
const Mats = preload("res://core/mats.gd")
const Props = preload("res://world/props.gd")

const DEC := "res://assets/env/interior_sf/decals/"
const MAX_DECALS := 210

static var n_dec := 0
static var _tex := {}
static var rng := RandomNumberGenerator.new()

static func begin(seed_v := 1) -> void:
	n_dec = 0
	rng.seed = seed_v

static func rf(a: float, b: float) -> float:
	return rng.randf_range(a, b)

# ------------------------------------------------------------------ props
## Spawns assets/env/interior_sf/<name>.glb (base on y, centred on x/z, forward +Z).
static func prop(parent: Node3D, name: String, pos: Vector3, yaw := 0.0, opts := {}) -> Node3D:
	var o := {"snow": 0.0, "name": name.capitalize().replace(" ", "")}
	o.merge(opts, true)
	return Env.spawn(parent, "interior_sf/" + name, pos, yaw, o)

## Same, but also adds an invisible collider box (so the visual can be hollow / low).
static func prop_solid(parent: Node3D, name: String, pos: Vector3, yaw: float, size: Vector3, opts := {}) -> Node3D:
	var o := {"collide": "none"}
	o.merge(opts, true)
	var r := prop(parent, name, pos, yaw, o)
	if r != null:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = Vector3(0, size.y * 0.5, 0)
		sb.add_child(cs)
		r.add_child(sb)
	return r

# ------------------------------------------------------------------ decals
static func _t(name: String) -> Texture2D:
	if _tex.has(name):
		return _tex[name]
	var p := DEC + name + "_a.png"
	var t: Texture2D = load(p) if ResourceLoader.exists(p) else null
	_tex[name] = t
	return t

## Projected grime decal. `normal` = outward surface normal (into the room). w/h are metres along the
## texture's X / Y (the image top is up on walls). Floors: pass Vector3.UP, `yaw` rotates it.
static func decal(parent: Node, tex: String, pos: Vector3, normal: Vector3, w: float, h: float, opacity := 0.8, yaw := 0.0, depth := 0.3, tint := Color.WHITE) -> Decal:
	if n_dec >= MAX_DECALS:
		return null
	var t := _t(tex)
	if t == null:
		return null
	n_dec += 1
	var d := Decal.new()
	d.size = Vector3(w, depth, h)
	d.texture_albedo = t
	d.albedo_mix = 1.0
	d.normal_fade = 0.25
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	var c := tint
	c.a = opacity
	d.modulate = c
	d.distance_fade_enabled = true
	d.distance_fade_begin = 22.0
	d.distance_fade_length = 8.0
	parent.add_child(d)
	var y := normal.normalized()
	var z: Vector3
	var x: Vector3
	if absf(y.y) > 0.9:
		# floor / ceiling: image top toward -Z, rotated by yaw
		z = Vector3(0, 0, 1) if y.y > 0 else Vector3(0, 0, -1)
		x = y.cross(z)
	else:
		z = Vector3.DOWN
		x = y.cross(z)
	var b := Basis(x.normalized(), y, z.normalized())
	if yaw != 0.0:
		b = b.rotated(y, yaw)
	d.transform = Transform3D(b, pos)
	return d

## Wall decal anchored at its top edge (water stains) or centre; pos = point on the wall surface.
static func wall(parent: Node, tex: String, pos: Vector3, normal: Vector3, w: float, h: float, opacity := 0.8, flip := false) -> Decal:
	var d := decal(parent, tex, pos, normal, w, h, opacity)
	if d != null and flip:
		d.transform.basis = d.transform.basis.rotated(normal.normalized(), PI) if absf(normal.y) < 0.5 else d.transform.basis
	return d

static func floor_dec(parent: Node, tex: String, pos: Vector3, w: float, d: float, opacity := 0.8, yaw := -999.0) -> Decal:
	return decal(parent, tex, pos, Vector3.UP, w, d, opacity, rf(0, TAU) if yaw == -999.0 else yaw, 0.4)

## Soot/dirt band along the foot of a wall: from a to b (floor positions on the wall line), normal into room.
static func baseboard_grime(parent: Node, a: Vector3, b: Vector3, normal: Vector3, height := 1.1, opacity := 0.7) -> void:
	var L := a.distance_to(b)
	var segs := maxi(1, int(ceil(L / 4.0)))
	var seg_len := L / segs
	var dir := (b - a).normalized()
	for i in segs:
		var c := a + dir * (seg_len * (i + 0.5)) + Vector3(0, height * 0.5, 0) + normal.normalized() * 0.02
		var d := decal(parent, "band", c, normal, seg_len + 0.1, height, opacity)
		if d != null and rng.randf() < 0.5:
			# mirror along the wall for variety
			d.transform.basis = d.transform.basis * Basis(Vector3(0, 1, 0), 0.0)
	return

# ------------------------------------------------------------------ skirting and trim
static var _trim_mat: StandardMaterial3D
static func trim_mat() -> StandardMaterial3D:
	if _trim_mat == null:
		_trim_mat = Mats.color(Color(0.16, 0.13, 0.1), 0.7)
	return _trim_mat

## Baseboard strip along a wall: a, b are floor points on the wall face; normal points into the room.
static func skirting(parent: Node3D, a: Vector3, b: Vector3, normal: Vector3, h := 0.16, mat: Material = null) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.2:
		return
	var m := Props.box(parent, Vector3(L, h, 0.035), (a + b) * 0.5 + Vector3(0, h * 0.5, 0) + normal.normalized() * 0.0175, mat if mat != null else trim_mat(), false)
	m.rotation.y = atan2(-d.z, d.x)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Wood chair-rail / dado along a wall at height y.
static func rail(parent: Node3D, a: Vector3, b: Vector3, normal: Vector3, y: float, h := 0.07, mat: Material = null) -> void:
	var d := b - a
	var L := d.length()
	var m := Props.box(parent, Vector3(L, h, 0.05), (a + b) * 0.5 + Vector3(0, y, 0) + normal.normalized() * 0.025, mat if mat != null else trim_mat(), false)
	m.rotation.y = atan2(-d.z, d.x)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# ------------------------------------------------------------------ blankets
static var _fab_cache := {}
static func fabric(col: Color, rough := 0.97) -> StandardMaterial3D:
	var key := col.to_html()
	if _fab_cache.has(key):
		return _fab_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	if ResourceLoader.exists("res://textures/fabric_albedo.png"):
		m.albedo_texture = load("res://textures/fabric_albedo.png")
	if ResourceLoader.exists("res://textures/fabric_normal.png"):
		m.normal_enabled = true
		m.normal_texture = load("res://textures/fabric_normal.png")
		m.normal_scale = 1.4
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 2.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fab_cache[key] = m
	return m

## Draped lumpy blanket: footprint (sx, sz) with its top at y=0 locally; edges droop `drop` m. `lump` 0..1.
static func blanket(parent: Node3D, size: Vector2, pos: Vector3, col: Color, lump := 0.5, drop := 0.1, yaw := 0.0, seed_v := 0, body := 0.0) -> MeshInstance3D:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v + 17
	var nx := 10
	var nz := 18
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ph := r.randf() * 6.0
	var pts := []
	for iz in nz + 1:
		for ix in nx + 1:
			var u := float(ix) / nx
			var v := float(iz) / nz
			var ex := absf(u - 0.5) * 2.0
			var ez := absf(v - 0.5) * 2.0
			var edge := maxf(pow(ex, 3.0), pow(ez, 6.0))
			var h := -drop * edge
			h += lump * (0.05 * sin(u * 9.0 + ph) * sin(v * 7.0 + ph * 0.7) + 0.035 * sin(v * 19.0 + u * 5.0 + ph))
			if body > 0.0:
				# a body under the cover: a ridge down the middle with a head bump near v = 0.1
				h += body * exp(-pow((u - 0.5) / 0.28, 2.0)) * (0.7 + 0.3 * sin(v * 9.0)) * smoothstep(0.02, 0.18, v) * (1.0 - smoothstep(0.78, 1.0, v))
				h += body * 0.8 * exp(-pow((u - 0.5) / 0.2, 2.0) - pow((v - 0.11) / 0.07, 2.0))
			pts.append(Vector3((u - 0.5) * size.x, h, (v - 0.5) * size.y))
	for iz in nz:
		for ix in nx:
			var i0 := iz * (nx + 1) + ix
			var a: Vector3 = pts[i0]
			var b: Vector3 = pts[i0 + 1]
			var c: Vector3 = pts[i0 + nx + 1]
			var d: Vector3 = pts[i0 + nx + 2]
			st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
			st.add_vertex(b); st.add_vertex(d); st.add_vertex(c)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = fabric(col)
	mi.position = pos
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
