extends RefCounted
## R8-A: exterior storytelling and grime for the town levels: L1 (edge of town beyond the substation gate),
## L2 (the street outside the school wall) and L3 (Main Street + the diner / pharmacy / hardware storefronts).
## Everything here is dressing: no collision on gameplay paths (props outside the playable area or collide "none"),
## no triggers, no navigation changes. Textures: textures/town_decals (tools/town/gen_decals.py),
## props: assets/env/town_props (Sketchfab CC-BY, tools/town/props_sf.py), assets/env/town, street, vehicles.

const Env = preload("res://world/env_assets.gd")
const Props = preload("res://world/props.gd")
const Mats = preload("res://core/mats.gd")
const DEC := "res://textures/town_decals/"

static var _tex := {}
static var _mat := {}
static var rng := RandomNumberGenerator.new()

static func _t(n: String) -> Texture2D:
	if not _tex.has(n):
		var p := DEC + n + ".png"
		_tex[n] = load(p) if ResourceLoader.exists(p) else null
	return _tex[n]

static func rf(a: float, b: float) -> float:
	return rng.randf_range(a, b)

# ====================================================================== primitives
## Ground decal (projects straight down). size = (width x, length z).
static func decal(parent: Node, name: String, pos: Vector3, size: Vector2, yaw := 0.0, opacity := 0.85, tint := Color.WHITE, depth := 0.8) -> Decal:
	var a := _t(name + "_a")
	if a == null:
		return null
	var d := Decal.new()
	d.name = "Dec_" + name
	d.size = Vector3(size.x, depth, size.y)
	d.texture_albedo = a
	var nt := _t(name + "_n")
	if nt:
		d.texture_normal = nt
	d.modulate = Color(tint.r, tint.g, tint.b, opacity)
	d.upper_fade = 0.2
	d.lower_fade = 0.4
	d.normal_fade = 0.5
	d.distance_fade_enabled = true
	d.distance_fade_begin = 55.0
	d.distance_fade_length = 15.0
	d.position = pos
	d.rotation.y = yaw
	parent.add_child(d)
	return d

static func prop(parent: Node3D, rel: String, pos: Vector3, yaw := 0.0, opts := {}) -> Node3D:
	var o := {"collide": "none"}
	o.merge(opts, true)
	return Env.spawn(parent, rel, pos, yaw, o)

static func _std(key: String, c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	if not _mat.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		_mat[key] = m
	return _mat[key]

static func _tex_mat(n: String, rough := 0.85, unshaded := false) -> StandardMaterial3D:
	var key := "tex_" + n
	if not _mat.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = _t(n)
		m.roughness = rough
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if unshaded:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat[key] = m
	return _mat[key]

static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	return Props.box(parent, size, pos, mat, false, rot)

## Paper poster / notice taped flat to a surface facing `yaw` (front +Z rotated by yaw).
static func poster(parent: Node3D, name: String, pos: Vector3, yaw: float, h := 0.5, tilt := 0.0) -> MeshInstance3D:
	var t := _t("poster_" + name)
	if t == null:
		return null
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(h * float(t.get_width()) / float(t.get_height()), h)
	mi.mesh = q
	mi.material_override = _tex_mat("poster_" + name)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation = Vector3(0, yaw, tilt)
	parent.add_child(mi)
	# two strips of tape at the top corners
	for sx in [-0.42, 0.42]:
		var tp := MeshInstance3D.new()
		var tq := QuadMesh.new()
		tq.size = Vector2(0.09, 0.03)
		tp.mesh = tq
		tp.material_override = _std("tape_clear", Color(0.85, 0.82, 0.7), 0.3)
		tp.position = Vector3(sx * q.size.x, h * 0.47, 0.002)
		tp.rotation.z = 0.6 * sign(sx)
		mi.add_child(tp)
	return mi

## POLICE LINE tape strung a -> b (printed texture, sagging, slightly twisted).
static func police_tape(parent: Node3D, a: Vector3, b: Vector3, sag := 0.2) -> void:
	var m := _tex_mat("tape", 0.6)
	m.uv1_scale = Vector3(1, 1, 1)
	var segs := maxi(4, int(a.distance_to(b) / 0.8))
	var prev := a
	var u0 := 0.0
	for i in range(1, segs + 1):
		var t := float(i) / segs
		var p := a.lerp(b, t)
		p.y -= sag * 4.0 * t * (1.0 - t)
		var d := p - prev
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(d.length() + 0.01, 0.075)
		mi.mesh = qm
		var mm := m.duplicate() as StandardMaterial3D
		mm.uv1_scale = Vector3(d.length() / 2.6, 1, 1)
		mm.uv1_offset = Vector3(u0, 0, 0)
		u0 += d.length() / 2.6
		mi.material_override = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		mi.position = (prev + p) * 0.5
		var xa := d.normalized()
		var za := xa.cross(Vector3.UP).normalized()
		mi.basis = Basis(xa, za.cross(xa).normalized(), za).rotated(xa, sin(t * 9.0) * 0.5)
		prev = p

# ====================================================================== fences
## kind: "picket" | "privacy" | "chain" | "wire" (wooden posts + sagging wire). Broken/missing panels at random.
static func fence(parent: Node3D, a: Vector3, b: Vector3, kind := "picket", opts := {}) -> void:
	var d := b - a
	d.y = 0
	var L := d.length()
	if L < 0.5:
		return
	var yaw := atan2(d.x, d.z) - PI * 0.5      # module length runs along local x
	var dir := d / L
	var broken: float = float(opts.get("broken", 0.12))
	var rng_end: float = float(opts.get("range", 120.0))
	match kind:
		"chain":
			var n := maxi(1, int(round(L / 10.84)))
			var w := L / n
			for i in n:
				var p := a + dir * (w * (i + 0.5))
				prop(parent, "industrial_sf/chainlink", p, yaw, {"scale": Vector3(w / 10.84, 1.0, 1.0), "snow": 0.5, "range": rng_end})
		"wire":
			var n := maxi(1, int(ceil(L / 2.8)))
			var wood := _std("post_wood", Color(0.24, 0.19, 0.14), 0.95)
			var tops: Array = []
			for i in n + 1:
				var p := a + dir * (L * float(i) / n)
				var lean := Vector3(rf(-0.08, 0.08), 0, rf(-0.08, 0.08))
				var hgt := rf(1.15, 1.35)
				Props.cyl(parent, 0.065, hgt, p + Vector3(0, hgt * 0.5 - 0.1, 0), wood, false, 0.06, lean, 7)
				Props.box(parent, Vector3(0.16, 0.06, 0.16), p + Vector3(0, hgt - 0.08, 0), Mats.get_mat("snow"), false)
				tops.append(p + Vector3(0, hgt - 0.12, 0))
			for k in 3:
				for i in n:
					if rng.randf() < 0.1:
						continue
					Props.power_wire(parent, tops[i] - Vector3(0, k * 0.35, 0), tops[i + 1] - Vector3(0, k * 0.35, 0), 0.08 + k * 0.03, 5, 0.005)
		_:
			var rel := "town/fence_picket" if kind == "picket" else "town/fence_privacy"
			var n := maxi(1, int(round(L / 1.92)))
			var w := L / n
			for i in n:
				var p := a + dir * (w * (i + 0.5))
				var r := rng.randf()
				if r < broken * 0.5:
					continue          # missing panel
				var o := {"scale": Vector3(w / 1.92, 1.0, 1.0), "snow": 0.75, "range": rng_end}
				var yy := yaw + rf(-0.03, 0.03)
				if r < broken:
					o["rot"] = Vector3(rf(-0.35, 0.35), 0, rf(-0.12, 0.12))   # leaning, half pushed over by the drifts
				prop(parent, rel, p, yy, o)
	# drift banked against the fence line
	if bool(opts.get("drift", true)):
		var k := 0.0
		while k < L:
			var p := a + dir * (k + rf(0.5, 2.0))
			Props.drift(parent, p + Vector3(0, 0, 0), rf(1.4, 2.6), rf(0.18, 0.4), rf(0.6, 1.0), yaw + rf(-0.2, 0.2))
			k += rf(3.0, 6.0)

# ====================================================================== props / vignettes
## Parked or abandoned car, roof and hood loaded with snow, a drift banked on the windward side.
static func snowed_car(parent: Node3D, pos: Vector3, yaw: float, col: Color, kind := "sedan", depth := 1.0) -> void:
	var car := Props.car(parent, pos, yaw, col, false, kind)
	var roof := {"sedan": [1.5, 1.45, 1.9], "police": [1.7, 1.75, 2.0], "van": [1.8, 2.1, 4.2], "covered_car": [1.5, 1.4, 1.9]}
	var r: Array = roof.get(kind, [1.5, 1.45, 1.9])
	var b := Basis(Vector3.UP, yaw)
	Props.drift(parent, pos + Vector3(0, float(r[1]) - 0.12, 0), float(r[0]) * 0.5, 0.22 * depth, float(r[2]) * 0.5, yaw)
	Props.drift(parent, pos + b * Vector3(0, 0.88, 1.65), 0.8, 0.14 * depth, 0.55, yaw)
	Props.drift(parent, pos + b * Vector3(0, 0.95, -1.75), 0.75, 0.12 * depth, 0.45, yaw)
	Props.drift(parent, pos + b * Vector3(-1.15, 0, 0), 1.2, 0.45 * depth, 2.6, yaw)
	if car and rng.randf() < 0.5:
		Props.drift(parent, pos + b * Vector3(1.1, 0, 0.6), 0.9, 0.3 * depth, 1.6, yaw)

static func snowman(parent: Node3D, pos: Vector3, yaw := 0.0, s := 1.0, solid := false) -> void:
	prop(parent, "town_props/snowman", pos + Vector3(0, -0.04, 0), yaw, {"scale": s, "snow": 0.0, "range": 90.0, "collide": "cyl" if solid else "none", "cyl_r": 0.45})

static func sled(parent: Node3D, pos: Vector3, yaw := 0.0) -> void:
	prop(parent, "town_props/sled", pos + Vector3(0, -0.06, 0), yaw, {"snow": 0.8, "range": 70.0, "rot": Vector3(rf(-0.08, 0.08), 0, rf(-0.1, 0.1))})

## Frozen laundry on a line between two T-posts (clothes left out when the power went).
static func laundry(parent: Node3D, pos: Vector3, yaw := 0.0) -> void:
	var b := Basis(Vector3.UP, yaw)
	var wood := _std("post_grey", Color(0.32, 0.3, 0.27), 0.9)
	for sx in [-2.25, 2.25]:
		var p: Vector3 = pos + b * Vector3(sx, 0, 0)
		Props.cyl(parent, 0.05, 2.25, p + Vector3(0, 1.12, 0), wood, false, -1.0, Vector3.ZERO, 6)
		var bar := Props.box(parent, Vector3(0.08, 0.08, 2.7), p + Vector3(0, 2.18, 0), wood, false)
		bar.rotation.y = yaw
	prop(parent, "town_props/laundry", pos + Vector3(0, 0.98, 0), yaw, {"snow": 0.35, "tint": Color(0.82, 0.86, 0.92), "range": 90.0})

static func sandbags(parent: Node3D, a: Vector3, b: Vector3, rows := 1) -> void:
	var d := b - a
	var L := Vector2(d.x, d.z).length()
	var yaw := atan2(d.x, d.z) - PI * 0.5
	var n := maxi(1, int(round(L / 2.5)))
	for i in n:
		for k in rows:
			var p := a.lerp(b, (i + 0.5) / n) + Vector3(0, k * 0.5, 0)
			prop(parent, "town_props/sandbags", p, yaw + rf(-0.05, 0.05) + (PI if (i + k) % 2 == 1 else 0.0), {"scale": Vector3(L / n / 2.6, 1, 1), "snow": 0.75, "range": 90.0})

static func trash(parent: Node3D, pos: Vector3, yaw := 0.0, s := 0.7) -> void:
	prop(parent, "town_props/trash_pile", pos + Vector3(0, -0.05, 0), yaw, {"scale": s, "snow": 0.55, "range": 80.0})

static func shovel(parent: Node3D, pos: Vector3, yaw := 0.0) -> void:
	prop(parent, "town_props/shovel", pos, yaw, {"snow": 0.4, "range": 50.0})

## A pole snapped by ice load: leaning hard, its conductors lying in the snow in loops.
static func downed_line(parent: Node3D, base: Vector3, yaw: float, lean := 0.45, sparks := false) -> void:
	var pole := Props.utility_pole(parent, base, yaw, 0, 9.0)
	if pole:
		pole.rotation.z = lean
	var b := Basis(Vector3.UP, yaw)
	var top := base + Vector3(-sin(lean) * 8.4, cos(lean) * 8.4, 0).rotated(Vector3.UP, yaw)
	for k in 3:
		var end := base + b * Vector3(-rf(9.0, 14.0), 0.03, rf(-2.5, 2.5))
		var mid := (top + end) * 0.5 + b * Vector3(rf(-1.5, 1.5), 0, rf(-2.0, 2.0))
		mid.y = 0.05
		Props.power_wire(parent, top - Vector3(0, k * 0.25, 0), mid, 0.3, 8, 0.014)
		Props.power_wire(parent, mid, end, 0.0, 6, 0.014)
		decal(parent, "slush", mid + Vector3(0, 0.2, 0), Vector2(1.2, 2.0), yaw + rf(-1, 1), 0.6)
	Props.drift(parent, base + b * Vector3(0.8, 0, 0), 1.3, 0.5, 1.0, yaw)

## Tyre tracks a -> b (two tread bands, gauge apart), tiled every ~7 m.
static func tyre_tracks(parent: Node3D, a: Vector3, b: Vector3, gauge := 1.6, opacity := 0.7) -> void:
	var d := b - a
	d.y = 0
	var L := d.length()
	var yaw := atan2(d.x, d.z)
	var side := Vector3(d.z, 0, -d.x).normalized()
	var n := maxi(1, int(ceil(L / 7.0)))
	for i in n:
		var c := a + d * ((i + 0.5) / n)
		for s in [-0.5, 0.5]:
			decal(parent, "tyre", c + side * (gauge * s) + Vector3(0, 0.25, 0), Vector2(0.26, L / n + 0.05), yaw, opacity)

static func footprints(parent: Node3D, a: Vector3, b: Vector3, opacity := 0.75) -> void:
	var d := b - a
	d.y = 0
	var L := d.length()
	var yaw := atan2(d.x, d.z)
	var n := maxi(1, int(round(L / 4.8)))
	for i in n:
		var c := a + d * ((i + 0.5) / n)
		decal(parent, "boots", c + Vector3(0, 0.25, 0), Vector2(0.8, L / n), yaw + rf(-0.04, 0.04), opacity)

## Road grime: oil, salt crust and slush scattered over an area (rect x0,z0 -> x1,z1).
static func road_grime(parent: Node3D, x0: float, z0: float, x1: float, z1: float, count: int, y := 0.04) -> void:
	for i in count:
		var p := Vector3(rf(x0, x1), y + 0.2, rf(z0, z1))
		var r := rng.randf()
		if r < 0.3:
			decal(parent, "oil", p, Vector2.ONE * rf(0.8, 1.8), rf(0, TAU), rf(0.55, 0.85))
		elif r < 0.6:
			decal(parent, "salt", p, Vector2.ONE * rf(1.2, 2.6), rf(0, TAU), rf(0.5, 0.8))
		else:
			decal(parent, "slush", p, Vector2(rf(1.2, 2.4), rf(2.0, 4.0)), rf(0, TAU), rf(0.5, 0.8))

## Neon sign with its own glowing tubes (texture as emission). on = 0 dead, 1 lit, 2 sputtering (animated by caller).
static func neon(parent: Node3D, pos: Vector3, yaw: float, energy := 3.0) -> Node3D:
	var n := prop(parent, "town_props/neon_open", pos, yaw, {"snow": 0.0, "range": 80.0})
	if n == null:
		return null
	var meshes: Array = []
	Env._meshes(n, meshes)
	for mi in meshes:
		var m: MeshInstance3D = mi
		for s in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(s)
			if src is BaseMaterial3D:
				var e := (src as BaseMaterial3D).duplicate() as StandardMaterial3D
				e.emission_enabled = true
				e.emission_texture = e.albedo_texture
				e.emission = Color.WHITE
				e.emission_energy_multiplier = energy
				m.set_surface_override_material(s, e)
	return n

# ====================================================================== storefronts (L3)
static func _awning_tex(c1: Color, c2: Color) -> ImageTexture:
	var img := Image.create(256, 16, false, Image.FORMAT_RGB8)
	for x in 256:
		var c := c1 if (x / 32) % 2 == 0 else c2
		for y in 16:
			var nn := 0.92 + 0.08 * sin(float(x * 7 + y * 13))
			img.set_pixel(x, y, c * nn)
	return ImageTexture.create_from_image(img)

## Fabric shop awning: sloped canvas with a scalloped valance, snow load on top, icicles off the hem.
## Front faces +Z of a node placed at the wall (pos = wall point at the awning's top edge).
static func awning(parent: Node3D, pos: Vector3, yaw: float, w: float, depth: float, c1: Color, c2: Color, drop := 0.55) -> Node3D:
	var r := Node3D.new()
	r.name = "Awning"
	r.position = pos
	r.rotation.y = yaw
	parent.add_child(r)
	var m := StandardMaterial3D.new()
	m.albedo_texture = _awning_tex(c1, c2)
	m.uv1_scale = Vector3(w / 2.0, 1, 1)
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 24
	var nz := 6
	# canvas: z 0..depth, y 0..-drop, sagging between the frame ribs (every ~1.2 m)
	var ribs := maxi(2, int(w / 1.2))
	var pts := []
	for iz in nz + 1:
		var row := []
		for ix in nx + 1:
			var u := float(ix) / nx
			var v := float(iz) / nz
			var x := (u - 0.5) * w
			var rib := absf(sin(u * PI * ribs))
			var y := -drop * v - 0.07 * rib * sin(v * PI)
			row.append(Vector3(x, y, depth * v))
		pts.append(row)
	for iz in nz:
		for ix in nx:
			var p00: Vector3 = pts[iz][ix]
			var p10: Vector3 = pts[iz][ix + 1]
			var p01: Vector3 = pts[iz + 1][ix]
			var p11: Vector3 = pts[iz + 1][ix + 1]
			for q in [[p00, Vector2(float(ix) / nx, 0.0)], [p10, Vector2(float(ix + 1) / nx, 0.0)], [p11, Vector2(float(ix + 1) / nx, 1.0)],
					[p00, Vector2(float(ix) / nx, 0.0)], [p11, Vector2(float(ix + 1) / nx, 1.0)], [p01, Vector2(float(ix) / nx, 1.0)]]:
				st.set_uv(q[1])
				st.add_vertex(q[0])
	# valance: 0.28 m skirt with scallops
	var vy := -drop
	var sc := maxi(4, int(w / 0.32))
	for i in sc:
		var x0 := (float(i) / sc - 0.5) * w
		var x1 := (float(i + 1) / sc - 0.5) * w
		var xm := (x0 + x1) * 0.5
		var a := Vector3(x0, vy, depth)
		var b := Vector3(x1, vy, depth)
		var c := Vector3(x1, vy - 0.22, depth)
		var d := Vector3(xm, vy - 0.3, depth)
		var e := Vector3(x0, vy - 0.22, depth)
		var u0 := float(i) / sc
		var u1 := float(i + 1) / sc
		for q in [[a, u0], [b, u1], [c, u1], [a, u0], [c, u1], [d, (u0 + u1) * 0.5], [a, u0], [d, (u0 + u1) * 0.5], [e, u0]]:
			st.set_uv(Vector2(q[1], 0.5))
			st.add_vertex(q[0])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	r.add_child(mi)
	# steel frame arms
	var steel := _std("awn_steel", Color(0.12, 0.12, 0.13), 0.5, 0.6)
	for sx in [-0.5, 0.5]:
		var arm := Props.box(r, Vector3(0.04, 0.04, sqrt(depth * depth + drop * drop)), Vector3(sx * (w - 0.1), -drop * 0.5 - 0.03, depth * 0.5), steel, false)
		arm.rotation.x = atan2(drop, depth)
	# snow load: a lumpy layer following the canvas
	var sn := Props.drift(r, Vector3(0, -drop * 0.45 + 0.04, depth * 0.45), w * 0.48, 0.16, depth * 0.5, 0.0)
	if sn:
		sn.rotation.x = atan2(drop, depth)
	# icicles off the hem
	var ice := Mats.get_mat("ice")
	var k := 0.0
	while k < w - 0.1:
		var L := rf(0.08, 0.45)
		Props.cyl(r, 0.0, L, Vector3(-w * 0.5 + k + 0.05, vy - 0.24 - L * 0.5, depth + 0.01), ice, false, 0.025, Vector3.ZERO, 5)
		k += rf(0.12, 0.35)
	return r

## Painted fascia board with raised lettering above a storefront.
static func fascia(parent: Node3D, pos: Vector3, yaw: float, w: float, text: String, board: Color, ink: Color, size := 120, h := 0.75) -> void:
	var r := Node3D.new()
	r.position = pos
	r.rotation.y = yaw
	parent.add_child(r)
	Props.box(r, Vector3(w, h, 0.08), Vector3(0, 0, 0.04), _std("fascia_%s" % board.to_html(), board, 0.7), false)
	var trim := _std("fascia_trim", Color(0.12, 0.1, 0.08), 0.6)
	Props.box(r, Vector3(w + 0.12, 0.08, 0.14), Vector3(0, h * 0.5 + 0.04, 0.07), trim, false)
	Props.box(r, Vector3(w + 0.12, 0.08, 0.14), Vector3(0, -h * 0.5 - 0.04, 0.07), trim, false)
	Props.box(r, Vector3(w + 0.1, 0.1, 0.3), Vector3(0, h * 0.5 + 0.13, 0.12), Mats.get_mat("snow"), false)
	var l := Label3D.new()
	l.text = text
	l.font = load("res://fonts/BeVietnamPro-Bold.ttf")
	l.font_size = size
	l.pixel_size = 0.0042
	l.modulate = ink
	l.outline_size = 6
	l.outline_modulate = Color(0, 0, 0, 0.6)
	l.shaded = true
	l.double_sided = false
	l.position = Vector3(0, 0, 0.085)
	r.add_child(l)

## Shopfront joinery around the existing wall openings (the room's gap list), without touching the walls/doors:
## painted frames, mullions, kick plates under the sills, a transom over the door.
## gaps: [[offset_from_x0, width, top, sill?]] as given to Level.room(). out = +1 facing +z, -1 facing -z.
static func shopfront(parent: Node3D, x0: float, zf: float, out: float, gaps: Array, paint: Color) -> void:
	var pm := _std("shop_paint_%s" % paint.to_html(), paint, 0.55)
	var dark := _std("shop_kick", paint.darkened(0.35), 0.6)
	var brass := _std("shop_brass", Color(0.55, 0.42, 0.2), 0.35, 0.8)
	var z := zf + out * 0.06
	for g in gaps:
		var cx: float = x0 + float(g[0])
		var w: float = g[1]
		var top: float = g[2]
		var sill: float = g[3] if g.size() >= 4 else 0.0
		var fw := 0.1
		# jambs + head
		for sx in [-1.0, 1.0]:
			_box(parent, Vector3(fw, top - sill + fw, 0.12), Vector3(cx + sx * (w * 0.5 - fw * 0.5), (top + sill) * 0.5, z), pm)
		_box(parent, Vector3(w + 0.1, 0.16, 0.16), Vector3(cx, top - 0.02, z), pm)
		if sill > 0.3:
			# window: sill, mullions, kick plate with two recessed panels
			_box(parent, Vector3(w + 0.16, 0.07, 0.24), Vector3(cx, sill, z + out * 0.04), pm)
			var nm := maxi(1, int(w / 1.3))
			for k in range(1, nm):
				_box(parent, Vector3(0.06, top - sill, 0.08), Vector3(cx - w * 0.5 + w * k / nm, (top + sill) * 0.5, z), pm)
			_box(parent, Vector3(w, sill - 0.05, 0.1), Vector3(cx, (sill - 0.05) * 0.5, z - out * 0.01), dark)
			for k in 2:
				_box(parent, Vector3(w * 0.42, sill * 0.55, 0.03), Vector3(cx - w * 0.25 + w * 0.5 * k, sill * 0.45, z + out * 0.045), pm)
			# transom bar
			_box(parent, Vector3(w, 0.06, 0.08), Vector3(cx, top - 0.5, z), pm)
		else:
			# door: brass kick strip line at the threshold + transom panel with the street number
			_box(parent, Vector3(w + 0.2, 0.05, 0.3), Vector3(cx, 0.025, z + out * 0.08), brass)
			var l := Label3D.new()
			l.text = str(100 + int(absf(cx)) * 2)
			l.font_size = 64
			l.pixel_size = 0.004
			l.modulate = Color(0.85, 0.7, 0.35)
			l.shaded = true
			l.position = Vector3(cx, top + 0.2, z + out * 0.08)
			l.rotation.y = 0.0 if out > 0 else PI
			parent.add_child(l)
			_box(parent, Vector3(w + 0.1, 0.32, 0.06), Vector3(cx, top + 0.2, z - out * 0.01), _std("transom_glass", Color(0.06, 0.07, 0.08), 0.15, 0.3))

## Shelves of stock seen through a shop window: a stepped display behind the glass (no collision).
static func window_display(parent: Node3D, cx: float, zf: float, out: float, w: float, sill: float, kind: String) -> void:
	var zin := zf - out * 0.45
	var yaw := 0.0 if out > 0 else PI
	var base := _std("disp_base", Color(0.3, 0.26, 0.22), 0.8)
	_box(parent, Vector3(w - 0.2, sill, 0.6), Vector3(cx, sill * 0.5, zin), base)
	match kind:
		"pharmacy":
			for tier in 3:
				var ty := sill + 0.02 + tier * 0.32
				var tz := zin - out * (0.12 * tier - 0.1)
				_box(parent, Vector3(w - 0.4, 0.03, 0.22), Vector3(cx, ty, tz), _std("disp_glass", Color(0.8, 0.85, 0.85), 0.2))
				var x := cx - w * 0.5 + 0.35
				while x < cx + w * 0.5 - 0.35:
					var c := Color.from_hsv(rng.randf(), rf(0.2, 0.7), rf(0.5, 0.95))
					var bw := rf(0.08, 0.18)
					var bh := rf(0.1, 0.25)
					_box(parent, Vector3(bw, bh, 0.08), Vector3(x, ty + bh * 0.5 + 0.015, tz), _std("box_%d" % (int(c.h * 12)), c, 0.6))
					x += bw + rf(0.02, 0.08)
			poster(parent, "flu", Vector3(cx + w * 0.28, sill + 1.05, zf - out * 0.04), yaw, 0.55)
		"hardware":
			for k in 4:
				shovel(parent, Vector3(cx - w * 0.35 + k * 0.32, sill, zin + out * 0.15), yaw + PI * 0.5 + rf(-0.1, 0.1))
			for k in 3:
				_box(parent, Vector3(0.55, 0.16, 0.38), Vector3(cx + w * 0.2, sill + 0.08 + k * 0.165, zin), _std("salt_bag", Color(0.85, 0.75, 0.15), 0.8))
			prop(parent, "camp/propane", Vector3(cx + w * 0.38, sill, zin - out * 0.05), 0.0, {"fit_h": 0.6, "snow": 0.0})
			prop(parent, "camp/jerrycan", Vector3(cx - w * 0.05, sill, zin), yaw, {"fit_h": 0.45, "snow": 0.0})
			poster(parent, "icemelt", Vector3(cx + w * 0.22, sill + 1.05, zf - out * 0.04), yaw, 0.55)
		"diner":
			_box(parent, Vector3(0.9, 0.35, 0.45), Vector3(cx + w * 0.2, sill + 0.18, zin), _std("pie_case", Color(0.7, 0.75, 0.78), 0.15, 0.3))
			for k in 3:
				Props.cyl(parent, 0.12, 0.05, Vector3(cx + w * 0.2 - 0.27 + k * 0.27, sill + 0.4, zin), _std("pie", Color(0.6, 0.38, 0.18), 0.7), false)
			poster(parent, "help", Vector3(cx - w * 0.3, sill + 0.95, zf - out * 0.04), yaw, 0.5)
	# garland swag across the top of every display window (December 21st)
	for k in 8:
		var t0 := float(k) / 8.0
		var t1 := float(k + 1) / 8.0
		var a := Vector3(cx - w * 0.5 + w * t0, 0.0, zin + out * 0.25)
		var b := Vector3(cx - w * 0.5 + w * t1, 0.0, zin + out * 0.25)
		var ft := fmod(t0 * 2.0, 1.0)
		a.y = 2.45 - 0.25 * 4.0 * ft * (1.0 - ft)
		ft = fmod(t1 * 2.0, 1.0) if k != 3 else 1.0
		b.y = 2.45 - 0.25 * 4.0 * ft * (1.0 - ft)
		Props.pipe(parent, a, b, 0.045, "metal")
	for k in 3:
		Props.sphere(parent, 0.04, Vector3(cx - w * 0.3 + k * w * 0.3, 2.3, zin + out * 0.26), _std("bauble%d" % k, [Color(0.6, 0.05, 0.05), Color(0.75, 0.6, 0.15), Color(0.1, 0.2, 0.5)][k], 0.2, 0.6))

# ====================================================================== per-level dressing
static func dress_l1(level: Node3D) -> void:
	var g: Node3D = level.get("geo")
	rng.seed = 5301
	# --- the road up to the gate (playable): grime decals only, nothing solid
	tyre_tracks(g, Vector3(-1.6, 0.04, -60.0), Vector3(-1.4, 0.04, -136.0), 1.6, 0.55)
	tyre_tracks(g, Vector3(1.8, 0.04, -136.0), Vector3(1.4, 0.04, -90.0), 1.6, 0.4)
	road_grime(g, -3.6, -136.0, 3.6, -96.0, 14)
	footprints(g, Vector3(4.6, 0.04, -100.0), Vector3(3.6, 0.04, -136.0), 0.6)
	police_tape(g, Vector3(-4.4, 1.0, -137.6), Vector3(-2.2, 0.95, -137.6), 0.08)
	police_tape(g, Vector3(4.4, 1.05, -137.6), Vector3(9.0, 0.9, -137.8), 0.25)
	poster(g, "curfew", Vector3(-2.05, 1.6, -137.82), 0.0, 0.5, 0.04)
	sandbags(g, Vector3(-9.5, 0.0, -136.6), Vector3(-5.2, 0.0, -136.8), 2)
	sandbags(g, Vector3(5.4, 0.0, -136.8), Vector3(9.8, 0.0, -136.5), 1)
	# --- beyond the gate: the edge of town (no collision, the gate is the level boundary)
	var road_z := -144.0
	tyre_tracks(g, Vector3(-1.5, 0.04, -139.0), Vector3(-1.0, 0.04, -175.0), 1.6, 0.5)
	# a side street in front of the houses, x across
	tyre_tracks(g, Vector3(-80.0, 0.04, road_z), Vector3(-5.0, 0.04, road_z + 0.4), 1.6, 0.5)
	tyre_tracks(g, Vector3(5.0, 0.04, road_z), Vector3(80.0, 0.04, road_z - 0.3), 1.6, 0.5)
	snowed_car(g, Vector3(-12.0, 0, -142.2), PI * 0.5 + 0.06, Color(0.42, 0.08, 0.08), "sedan", 1.3)
	snowed_car(g, Vector3(14.5, 0, -142.0), -PI * 0.5, Color(0.2, 0.22, 0.25), "van", 1.2)
	snowed_car(g, Vector3(-40.0, 0, -146.6), PI * 0.5 + 0.1, Color(0.6, 0.6, 0.55), "sedan", 1.4)
	snowed_car(g, Vector3(36.0, 0, -146.0), -PI * 0.5 + 0.08, Color(0.1, 0.13, 0.2), "police", 1.0)
	# front-yard fences along both rows (x -80..-18 and 18..82, fronts at z=-150)
	_yard_fences(g, -80.0, -18.0, -147.6, 53)
	_yard_fences(g, 18.0, 82.0, -147.6, 54)
	snowman(g, Vector3(-28.0, 0, -148.6), 0.4, 0.95)
	sled(g, Vector3(-26.6, 0, -148.0), 1.2)
	laundry(g, Vector3(58.0, 0, -153.5), 0.05)
	trash(g, Vector3(-17.0, 0, -148.6), 0.3, 0.7)
	downed_line(g, Vector3(22.0, 0, -147.2), PI * 0.5 + 0.2, 0.5)
	police_tape(g, Vector3(16.0, 0.95, -145.0), Vector3(28.0, 1.0, -145.5), 0.3)
	footprints(g, Vector3(-27.0, 0.04, -146.0), Vector3(-30.0, 0.04, -149.4), 0.7)

## Yard fences in front of a house row: picket / privacy / wire lots with gaps for driveways.
static func _yard_fences(g: Node3D, x0: float, x1: float, z: float, seed_v: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var x := x0
	while x < x1 - 3.0:
		var w := r.randf_range(7.0, 14.0)
		var e := minf(x + w, x1)
		var k := r.randf()
		var kind := "picket" if k < 0.45 else ("privacy" if k < 0.65 else ("wire" if k < 0.85 else ""))
		if kind != "":
			fence(g, Vector3(x, 0, z + r.randf_range(-0.3, 0.3)), Vector3(e - 3.2, 0, z + r.randf_range(-0.3, 0.3)), kind, {"range": 140.0})
		x = e + r.randf_range(0.5, 1.5)

static func dress_l2(level: Node3D) -> void:
	var g: Node3D = level.get("geo")
	rng.seed = 5302
	# street beyond the south wall (outside the playable courtyard): z 26..36
	tyre_tracks(g, Vector3(-60.0, 0.04, 29.5), Vector3(60.0, 0.04, 30.0), 1.6, 0.55)
	tyre_tracks(g, Vector3(60.0, 0.04, 32.5), Vector3(-60.0, 0.04, 33.0), 1.6, 0.4)
	road_grime(g, -40.0, 27.0, 40.0, 35.0, 12, 0.0)
	snowed_car(g, Vector3(-30.0, 0, 34.8), PI * 0.5 + 0.04, Color(0.18, 0.28, 0.22), "sedan", 1.3)
	snowed_car(g, Vector3(9.5, 0, 35.0), -PI * 0.5, Color(0.55, 0.5, 0.42), "van", 1.2)
	snowed_car(g, Vector3(34.0, 0, 34.6), PI * 0.5, Color(0.5, 0.1, 0.1), "sedan", 1.4)
	snowed_car(g, Vector3(-6.0, 0, 27.6), PI * 0.5 - 0.1, Color(0.1, 0.12, 0.18), "police", 0.8)
	police_tape(g, Vector3(-9.0, 1.0, 26.4), Vector3(-2.5, 0.95, 25.6), 0.25)
	trash(g, Vector3(-48.0, 0, 36.6), 0.0, 0.8)
	trash(g, Vector3(26.0, 0, 37.0), 1.2, 0.6)
	_yard_fences(g, -60.0, -8.0, 36.6, 201)
	_yard_fences(g, 8.0, 62.0, 36.6, 202)
	snowman(g, Vector3(-18.0, 0, 37.4), PI + 0.3, 0.9)
	sled(g, Vector3(-16.8, 0, 36.9), 2.0)
	laundry(g, Vector3(48.0, 0, 41.5), PI)
	downed_line(g, Vector3(-40.0, 0, 27.0), -0.3, 0.42)
	sandbags(g, Vector3(-3.6, 0.0, 25.2), Vector3(-8.6, 0.0, 25.4), 2)
	# back rows behind the side walls
	_yard_fences(g, -70.0, -34.0, -27.6, 203)
	_yard_fences(g, 34.0, 72.0, -27.6, 204)
	fence(g, Vector3(-34.0, 0, -26.0), Vector3(-34.0, 0, 20.0), "chain", {"range": 140.0})
	fence(g, Vector3(34.0, 0, -26.0), Vector3(34.0, 0, 20.0), "wire", {"range": 140.0})
	# courtyard (playable): decals only
	footprints(g, Vector3(0.4, 0.04, 21.5), Vector3(-2.0, 0.04, 6.0), 0.55)
	footprints(g, Vector3(-2.0, 0.04, 6.0), Vector3(-17.0, 0.04, 0.0), 0.5)
	road_grime(g, -6.0, 14.0, 6.0, 23.0, 4, 0.0)

static func dress_l3(level: Node3D) -> void:
	var g: Node3D = level.get("geo")
	rng.seed = 5303
	_storefronts(g)
	# Main Street: plough ruts, slush, oil under the parked cars, salt crust at the kerbs
	tyre_tracks(g, Vector3(-74.0, 0.05, -1.8), Vector3(70.0, 0.05, -2.0), 1.6, 0.6)
	tyre_tracks(g, Vector3(70.0, 0.05, 2.2), Vector3(-74.0, 0.05, 1.9), 1.6, 0.5)
	road_grime(g, -74.0, -5.0, 68.0, 5.0, 46, 0.02)
	for c in [Vector3(-62, 0, 4.2), Vector3(-38, 0, 4.3), Vector3(-30, 0, -4.3), Vector3(11, 0, 4.2), Vector3(38, 0, 4.2)]:
		decal(g, "oil", c + Vector3(rf(-0.6, 0.6), 0.25, rf(-0.3, 0.3)), Vector2.ONE * rf(1.4, 2.2), rf(0, TAU), 0.8)
	for x in [-60.0, -40.0, -20.0, 0.0, 20.0, 40.0, 60.0]:
		decal(g, "salt", Vector3(x + rf(-5, 5), 0.25, 5.2), Vector2(rf(2.0, 3.5), 1.6), rf(-0.3, 0.3), 0.7)
		decal(g, "salt", Vector3(x + rf(-5, 5), 0.25, -5.2), Vector2(rf(2.0, 3.5), 1.6), rf(-0.3, 0.3), 0.7)
	footprints(g, Vector3(-68.0, 0.05, 0.5), Vector3(-44.0, 0.05, -3.0), 0.6)
	footprints(g, Vector3(-44.0, 0.05, -3.0), Vector3(-36.0, 0.05, -6.6), 0.6)
	footprints(g, Vector3(-19.0, 0.05, -6.8), Vector3(-10.0, 0.05, 4.8), 0.5)
	# sidewalk life: sandbags at the pharmacy, a shovel left in the bank, tape across the Northline doors
	sandbags(g, Vector3(-41.6, 0.0, -5.0), Vector3(-39.0, 0.0, -5.0), 2)
	shovel(g, Vector3(-28.8, 0.0, -5.4), 0.4)
	police_tape(g, Vector3(-4.5, 1.1, -5.4), Vector3(-1.3, 1.0, -5.4), 0.12)
	police_tape(g, Vector3(-30.2, 1.0, -4.0), Vector3(-29.6, 0.95, -6.1), 0.08)
	poster(g, "missing", Vector3(-11.4, 1.5, -5.88), 0.0, 0.5, -0.03)
	poster(g, "curfew", Vector3(-6.2, 1.55, -5.88), 0.0, 0.48, 0.02)
	poster(g, "meridian", Vector3(1.4, 1.5, -5.88), 0.0, 0.5, -0.05)
	poster(g, "missing", Vector3(17.6, 1.5, 5.88), PI, 0.48, 0.04)
	trash(g, Vector3(-44.2, 0, -5.4), 0.2, 0.55)
	trash(g, Vector3(17.0, 0, 5.4), 2.8, 0.6)
	# beyond the banks (non-playable): yard fences in front of the house rows, a snowman, a downed line
	_yard_fences(g, -76.0, 70.0, 26.6, 311)
	fence(g, Vector3(-78.0, 0, -24.2), Vector3(-43.0, 0, -24.2), "picket", {"range": 120.0})
	snowman(g, Vector3(-3.2, 0, 17.6), PI + 0.4, 0.9, true)
	sled(g, Vector3(-4.6, 0, 18.4), 0.9)
	downed_line(g, Vector3(60.0, 0, 26.0), PI - 0.3, 0.38)

## Diner / pharmacy / hardware: real shopfront joinery, fabric awnings, fascia signs and window displays.
## Walls, door openings and colliders stay exactly where l3_church.gd builds them.
static func _storefronts(g: Node3D) -> void:
	# PHARMACY  x -42..-30, front z -6 (faces +z)
	var pg := [[2.4, 2.6, 2.6, 0.9], [6.0, 1.8, 2.5], [9.9, 3.6, 2.6, 0.9]]
	shopfront(g, -42.0, -6.0, 1.0, pg, Color(0.1, 0.24, 0.17))
	awning(g, Vector3(-38.4, 3.35, -5.95), 0.0, 4.0, 1.25, Color(0.1, 0.3, 0.2), Color(0.85, 0.85, 0.8))
	awning(g, Vector3(-32.1, 3.35, -5.95), 0.0, 4.0, 1.25, Color(0.1, 0.3, 0.2), Color(0.85, 0.85, 0.8))
	fascia(g, Vector3(-36.0, 4.05, -5.96), 0.0, 10.6, "KETTLE FALLS PHARMACY", Color(0.9, 0.9, 0.86), Color(0.08, 0.3, 0.18), 118)
	window_display(g, -39.6, -6.0, 1.0, 2.6, 0.9, "pharmacy")
	window_display(g, -32.1, -6.0, 1.0, 3.6, 0.9, "pharmacy")
	poster(g, "closed", Vector3(-36.45, 1.55, -5.9), 0.0, 0.42)
	poster(g, "xmas", Vector3(-31.0, 2.0, -5.9), 0.0, 0.4)
	# DINER  x -26..-12, front z -6
	var dg := [[2.2, 3.0, 2.6, 0.9], [7.0, 1.8, 2.5], [12.0, 3.4, 2.6, 0.9]]
	shopfront(g, -26.0, -6.0, 1.0, dg, Color(0.45, 0.06, 0.06))
	awning(g, Vector3(-23.8, 3.35, -5.95), 0.0, 3.6, 1.2, Color(0.55, 0.08, 0.08), Color(0.9, 0.88, 0.82))
	awning(g, Vector3(-14.0, 3.35, -5.95), 0.0, 3.8, 1.2, Color(0.55, 0.08, 0.08), Color(0.9, 0.88, 0.82))
	window_display(g, -23.8, -6.0, 1.0, 3.0, 0.9, "diner")
	window_display(g, -14.0, -6.0, 1.0, 3.4, 0.9, "diner")
	neon(g, Vector3(-14.0, 1.5, -6.3), 0.0, 2.2)
	poster(g, "xmas", Vector3(-25.0, 1.9, -5.9), 0.0, 0.4)
	# HARDWARE  x 0..16, front z 6 (faces -z)
	var hg := [[3.0, 3.0, 2.6, 0.9], [8.0, 1.8, 2.5], [13.0, 3.0, 2.6, 0.9]]
	shopfront(g, 0.0, 6.0, -1.0, hg, Color(0.12, 0.18, 0.12))
	awning(g, Vector3(3.0, 3.35, 5.95), PI, 3.4, 1.3, Color(0.14, 0.3, 0.16), Color(0.75, 0.62, 0.2))
	awning(g, Vector3(13.0, 3.35, 5.95), PI, 3.4, 1.3, Color(0.14, 0.3, 0.16), Color(0.75, 0.62, 0.2))
	fascia(g, Vector3(8.0, 4.05, 5.96), PI, 14.0, "LINDQVIST HARDWARE", Color(0.12, 0.2, 0.13), Color(0.86, 0.7, 0.32), 130)
	window_display(g, 3.0, 6.0, -1.0, 3.0, 0.9, "hardware")
	window_display(g, 13.0, 6.0, -1.0, 3.0, 0.9, "hardware")
	poster(g, "closed", Vector3(8.0, 1.6, 5.9), PI, 0.4, 0.03)
	sled(g, Vector3(10.6, 0.0, 5.3), 0.3)
	shovel(g, Vector3(5.5, 0.0, 5.45), PI + 0.3)
