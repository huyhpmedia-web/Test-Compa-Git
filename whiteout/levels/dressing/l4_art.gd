extends RefCounted
## L4 - MERIDIAN environment art (agent F): real PBR finishes (ambientCG CC0 + generated panels),
## a ceiling light grid with flickering/dead panels, lobby furniture, evacuation clutter, hall detail.
## Everything is decoration: no gameplay nodes, nothing is placed inside a doorway or a 2.4 m corridor.
## Usage (from levels/l4_meridian.gd): Art.mat_*() for the shell, Art.dress(level) at the end of build().

const Props = preload("res://world/props.gd")
const Mats = preload("res://core/mats.gd")
const Env = preload("res://world/env_assets.gd")

const TX := "res://textures/env/f/"
static var _c := {}
static var geo: Node3D
static var host: Node3D
static var rng := RandomNumberGenerator.new()

# ------------------------------------------------------------------ materials
static func _tex(n: String) -> Texture2D:
	var p := TX + n + ".jpg"
	if ResourceLoader.exists(p):
		return load(p) as Texture2D
	return null

## Triplanar world-space PBR material from textures/env/f/<key>_{a,n,r}.jpg.
static func pbr(key: String, tile: float, tint := Color.WHITE, rough := 1.0, nscale := 1.0, metal := 0.0) -> StandardMaterial3D:
	var k := "%s@%.2f@%s@%.2f@%.2f@%.2f" % [key, tile, str(tint), rough, nscale, metal]
	if _c.has(k):
		return _c[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	var a := _tex(key + "_a")
	if a:
		m.albedo_texture = a
	var n := _tex(key + "_n")
	if n:
		m.normal_enabled = true
		m.normal_texture = n
		m.normal_scale = nscale
	var r := _tex(key + "_r")
	if r:
		m.roughness_texture = r
		m.roughness = rough
	else:
		m.roughness = rough
	m.metallic = metal
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / tile
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_c[k] = m
	return m

static func wall() -> StandardMaterial3D:
	return pbr("wpanel", 2.4, Color(0.78, 0.82, 0.88), 1.0, 0.8)

static func wall_dirty() -> StandardMaterial3D:
	return pbr("plaster", 2.5, Color(0.62, 0.66, 0.72), 1.0, 0.7)

static func ext() -> StandardMaterial3D:
	return pbr("clad", 2.0, Color.WHITE, 1.0, 1.0, 0.3)

static func floor_lobby() -> StandardMaterial3D:
	return pbr("terrazzo", 3.2, Color(0.5, 0.54, 0.6), 0.34, 0.5)

static func floor_raised() -> StandardMaterial3D:
	return pbr("raised", 1.2, Color(0.8, 0.86, 0.95), 1.0, 1.0)

static func floor_carpet() -> StandardMaterial3D:
	return pbr("carpet", 1.6, Color(0.72, 0.78, 0.95), 1.0, 1.0)

static func floor_conc() -> StandardMaterial3D:
	return pbr("concrete", 3.0, Color(0.52, 0.56, 0.62), 0.9, 0.8)

static func floor_plate() -> StandardMaterial3D:
	return pbr("diamond", 1.2, Color(0.55, 0.6, 0.66), 0.8, 1.0, 0.6)

static func ceil_tile() -> StandardMaterial3D:
	return pbr("ceil", 2.4, Color(0.62, 0.68, 0.76), 1.0, 0.8)

static func ceil_dark() -> StandardMaterial3D:
	return pbr("concrete", 3.0, Color(0.16, 0.18, 0.22), 1.0, 0.8)

static func metal() -> StandardMaterial3D:
	return pbr("metal", 1.5, Color(0.8, 0.84, 0.9), 0.6, 0.6, 0.85)

static func hazard() -> StandardMaterial3D:
	return pbr("hazard", 0.8, Color(0.8, 0.8, 0.8), 1.0, 0.5)

# ------------------------------------------------------------------ small helpers
static func rf(a: float, b: float) -> float:
	return rng.randf_range(a, b)

static func spawn(rel: String, pos: Vector3, yaw := 0.0, opts := {}) -> Node3D:
	if not opts.has("snow"):
		opts["snow"] = 0.0
	return Env.spawn(geo, "office/" + rel if not rel.contains("/") else rel, pos, yaw, opts)

static func label(text: String, pos: Vector3, yaw: float, size := 48, color := Color(0.75, 0.95, 1.2), ps := 0.004, shaded := false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = ps
	l.modulate = color
	l.shaded = shaded
	l.double_sided = false
	l.outline_size = 0
	l.position = pos
	l.rotation.y = yaw
	host.add_child(l)
	return l

static func box(pos: Vector3, size: Vector3, mat: Material, solid := false, rot := Vector3.ZERO) -> MeshInstance3D:
	return Props.box(geo, size, pos, mat, solid, rot)

static func emi(c: Color, e := 2.0) -> StandardMaterial3D:
	return Mats.emissive(c, e)

# ------------------------------------------------------------------ ceiling light panels (MultiMesh, 3 states)
static var _panel_sh: Shader
static func _panel_mat(mode: int) -> ShaderMaterial:
	if _panel_sh == null:
		_panel_sh = Shader.new()
		_panel_sh.code = "shader_type spatial;\nuniform int mode = 0;\nuniform vec3 tint = vec3(0.82, 0.92, 1.0);\nvarying float ph;\nvoid vertex() { ph = COLOR.a; }\nfloat hash(float x) { return fract(sin(x * 91.345) * 47453.5453); }\nvoid fragment() {\n\tfloat k = 1.0;\n\tif (mode == 1) {\n\t\tfloat t = floor(TIME * 9.0 + ph * 40.0);\n\t\tfloat r = hash(t + ph * 7.0);\n\t\tk = (r > 0.55) ? 1.0 : (r > 0.3 ? 0.25 : 0.04);\n\t\tk *= 0.9 + 0.1 * sin(TIME * 120.0);\n\t} else if (mode == 2) {\n\t\tk = 0.0;\n\t}\n\tvec3 c = mix(vec3(0.07, 0.075, 0.085), tint, k);\n\tALBEDO = mix(vec3(0.5), c, 0.5);\n\tROUGHNESS = 0.3;\n\tEMISSION = tint * k * 3.2;\n}\n"
	var m := ShaderMaterial.new()
	m.shader = _panel_sh
	m.set_shader_parameter("mode", mode)
	return m

static func light_panels(pts: Array, y: float, size := Vector2(0.6, 1.2), along_z := true, seed_v := 1, dead := 0.12, flick := 0.12, tint := Color(0.82, 0.92, 1.0)) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var groups := [[], [], []]
	for p in pts:
		var roll := r.randf()
		var mode := 2 if roll < dead else (1 if roll < dead + flick else 0)
		groups[mode].append(p)
	for mode in 3:
		var arr: Array = groups[mode]
		if arr.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var bm := BoxMesh.new()
		bm.size = Vector3(size.x, 0.05, size.y) if along_z else Vector3(size.y, 0.05, size.x)
		mm.mesh = bm
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3(arr[i].x, y - 0.025, arr[i].y)))
			mm.set_instance_color(i, Color(1, 1, 1, r.randf()))
		var mat := _panel_mat(mode)
		mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.add_child(mmi)
	# dark frames (one multimesh for all)
	var fm := MultiMesh.new()
	fm.transform_format = MultiMesh.TRANSFORM_3D
	var fb := BoxMesh.new()
	fb.size = (Vector3(size.x + 0.1, 0.03, size.y + 0.1) if along_z else Vector3(size.y + 0.1, 0.03, size.x + 0.1))
	fm.mesh = fb
	fm.instance_count = pts.size()
	for i in pts.size():
		fm.set_instance_transform(i, Transform3D(Basis(), Vector3(pts[i].x, y - 0.012, pts[i].y)))
	var fmi := MultiMeshInstance3D.new()
	fmi.multimesh = fm
	fmi.material_override = Mats.color(Color(0.06, 0.065, 0.075), 0.5, 0.6)
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(fmi)

static func grid(x0: float, x1: float, z0: float, z1: float, dx: float, dz: float) -> Array:
	var out := []
	var x := x0
	while x <= x1 + 0.01:
		var z := z0
		while z <= z1 + 0.01:
			out.append(Vector2(x, z))
			z += dz
		x += dx
	return out

# ------------------------------------------------------------------ the entry point
static func dress(level: Node3D) -> void:
	host = level
	geo = level.get("geo") if level.get("geo") is Node3D else level
	rng.seed = 4004
	_ceilings()
	_lobby()
	_halls()
	_corridor()
	_noc_break()
	_plant_pipeline()
	_exterior()
	_signage_and_safety()

# ------------------------------------------------------------------ ceilings
static func _ceilings() -> void:
	var y := 4.5 - 0.0
	# lobby: full recessed grid
	light_panels(grid(-6.0, 6.0, -3.6, 10.0, 2.4, 3.4), y, Vector2(0.6, 1.2), true, 11, 0.16, 0.12)
	# armory / electrical / break room / NOC / corridor
	light_panels(grid(-28.0, -18.0, -30.0, -14.0, 3.6, 4.0), y, Vector2(0.6, 1.2), true, 12, 0.2, 0.14)
	light_panels(grid(-28.0, -16.0, -78.0, -68.0, 4.2, 3.4), y, Vector2(0.6, 1.2), true, 13, 0.1, 0.0, Color(1.0, 0.82, 0.58))
	light_panels(grid(-12.0, 0.0, -82.0, -68.0, 3.0, 3.6), y, Vector2(0.6, 1.2), true, 14, 0.1, 0.18)
	var cor := []
	var x := -27.0
	while x < 50.0:
		cor.append(Vector2(x, -63.0))
		x += 4.5
	light_panels(cor, y, Vector2(0.6, 1.2), false, 15, 0.14, 0.18)
	light_panels(grid(36.0, 48.0, -34.0, -24.0, 4.0, 4.0), y, Vector2(0.6, 1.2), true, 16, 0.2, 0.2)

# ------------------------------------------------------------------ lobby
static func _lobby() -> void:
	# ---- reception: stone top on a slatted-walnut body, metal kick, glowing under-edge, CORVANE back wall
	var rd := "res://assets/env/props/reception_desk.glb"
	var have_glb := ResourceLoader.exists(rd)
	var wood := Mats.get_mat("wood_panel", 0.6)
	var top := pbr("terrazzo", 1.6, Color(0.9, 0.9, 0.92), 0.28, 0.4)
	var dark := Mats.color(Color(0.035, 0.04, 0.05), 0.35, 0.55)
	if have_glb:
		Env.spawn(geo, "props/reception_desk", Vector3(-4.5, 0, 1.0), 0.0, {"snow": 0.0})
	else:
		box(Vector3(-4.5, 0.55, 1.0), Vector3(4.4, 1.1, 0.9), pbr("wpanel", 1.2, Color(0.5, 0.46, 0.42), 0.55), true)
		for i in 15:
			box(Vector3(-6.45 + i * 0.28, 0.55, 1.46), Vector3(0.12, 1.0, 0.04), wood, false)
		box(Vector3(-4.5, 1.095, 1.04), Vector3(4.6, 0.07, 1.1), top, false)
		box(Vector3(-4.5, 0.04, 1.0), Vector3(4.46, 0.08, 0.96), dark, false)
		box(Vector3(-4.5, 0.075, 1.5), Vector3(4.2, 0.02, 0.02), emi(Color(0.45, 0.75, 1.0), 4.0), false)
		# raised transaction ledge + inner shelf
		box(Vector3(-4.5, 1.26, 1.36), Vector3(4.4, 0.04, 0.2), top, false)
	# back-of-house wall behind the desk with the brand
	box(Vector3(-4.5, 1.7, -0.2), Vector3(4.6, 3.4, 0.08), pbr("wpanel", 1.2, Color(0.2, 0.22, 0.26), 0.5, 0.8), false)
	label("CORVANE", Vector3(-4.5, 2.5, -0.15), 0.0, 120, Color(0.88, 0.94, 1.1), 0.007, false)
	label("S  Y  S  T  E  M  S", Vector3(-4.5, 2.05, -0.15), 0.0, 40, Color(0.55, 0.75, 1.0), 0.005, false)
	box(Vector3(-4.5, 2.2, -0.17), Vector3(3.0, 0.015, 0.01), emi(Color(0.5, 0.8, 1.0), 3.5), false)
	if not have_glb:
		# monitors / laptop / lamp on the desk (kept away from the note and the gel pickup spots)
		for mx in [-5.9, -4.6]:
			box(Vector3(mx, 1.4, 1.14), Vector3(0.52, 0.32, 0.03), Mats.color(Color(0.03, 0.03, 0.035), 0.3), false, Vector3(0, 0.25, 0))
			box(Vector3(mx, 1.4, 1.13), Vector3(0.47, 0.27, 0.01), emi(Color(0.12, 0.35, 0.6), 1.4), false, Vector3(0, 0.25, 0))
			box(Vector3(mx, 1.2, 1.15), Vector3(0.06, 0.2, 0.06), dark, false)
		spawn("laptop", Vector3(-3.7, 1.13, 1.08), 0.5, {"scale": 0.5, "collide": "none"})
		spawn("notepads", Vector3(-2.8, 1.13, 1.2), 0.3, {"scale": 0.3, "collide": "none"})
		spawn("stationery", Vector3(-5.2, 1.13, 1.28), 0.0, {"scale": 1.0, "collide": "none"})
	# the receptionist's chair is on its side (spawned by Props.chair in the level); add a second, fallen
	Props.chair(geo, Vector3(-3.6, 0, 2.4), 2.1, true)
	Props.papers(geo, Vector3(-5.4, 0.03, 3.2), 9)
	Props.papers(geo, Vector3(-2.2, 0.03, 3.8), 8)
	# ---- lounge cluster (east): armchairs around a low table, one knocked over
	var lx := 5.4
	spawn("coffee_table", Vector3(lx, 0, 5.6), PI * 0.5, {"collide": Vector3(1.2, 0.4, 0.6), "name": "CoffeeTable"})
	spawn("lounge_chair", Vector3(lx - 1.6, 0, 5.6), PI * 0.5, {"scale": 0.85, "collide": Vector3(0.9, 0.8, 0.9)})
	spawn("lounge_chair", Vector3(lx + 1.5, 0, 6.6), -PI * 0.5 - 0.5, {"scale": 0.85, "rot": Vector3(1.38, 0, 0.0), "collide": "none"})
	spawn("arm_chair", Vector3(lx, 0, 3.9), PI, {"scale": 0.9, "collide": Vector3(0.9, 0.85, 0.9)})
	spawn("plant_01", Vector3(7.0, 0, 9.3), 0.0, {"scale": 1.05, "collide": "cyl", "cyl_r": 0.3, "tint": Color(0.55, 0.52, 0.42)})
	spawn("plant_02", Vector3(-7.0, 0, 9.3), 1.0, {"scale": 1.1, "collide": "cyl", "cyl_r": 0.3, "tint": Color(0.5, 0.48, 0.4)})
	spawn("plant_02", Vector3(7.1, 0, -4.6), 2.0, {"scale": 1.1, "collide": "cyl", "cyl_r": 0.3, "tint": Color(0.5, 0.5, 0.45)})
	# frozen coffee, bag, spilled cups
	for p in [Vector3(lx + 0.15, 0.4, 5.55), Vector3(lx - 0.2, 0.4, 5.7)]:
		Props.cyl(geo, 0.04, 0.1, p, Mats.color(Color(0.9, 0.9, 0.92), 0.5), false)
	# ---- optical turnstiles: pedestals + glass flaps (the central lane stays 2.6 m clear)
	for sx in [-1.5, 1.5]:
		box(Vector3(sx, 0.5, -3.5), Vector3(0.22, 1.0, 1.5), metal(), true)
		box(Vector3(sx, 1.02, -3.5), Vector3(0.24, 0.04, 1.52), Mats.color(Color(0.04, 0.045, 0.05), 0.3, 0.5), false)
		box(Vector3(sx + (0.13 if sx < 0 else -0.13), 0.96, -3.5), Vector3(0.015, 0.03, 0.9), emi(Color(0.2, 1.0, 0.5), 4.0), false)
		var gm := Mats.get_mat("glass")
		box(Vector3(sx * 0.82, 0.98, -3.5), Vector3(0.02, 0.9, 1.0), gm, false)
	# glass partition wings along both sides of the lobby with steel mullions
	for sx in [-7.6, 7.6]:
		pass
	# ---- floor inlay: a thin cold-blue ring and the company mark in the centre of the lobby
	box(Vector3(0, 0.006, 4.0), Vector3(6.0, 0.004, 0.05), emi(Color(0.4, 0.7, 1.0), 1.6), false)
	box(Vector3(0, 0.006, 6.6), Vector3(6.0, 0.004, 0.05), emi(Color(0.4, 0.7, 1.0), 1.6), false)
	# ---- side walls: acoustic-timber slat feature + brand plaques
	for sx in [-7.84, 7.84]:
		var yaw := PI * 0.5 if sx < 0 else -PI * 0.5
		for i in 20:
			box(Vector3(sx, 1.5, -5.0 + i * 0.6), Vector3(0.06, 2.6, 0.18), wood, false)
	label("CORVANE SYSTEMS", Vector3(-7.78, 2.9, 4.0), PI * 0.5, 44, Color(0.7, 0.85, 1.05), 0.005)
	label("Reliability is a promise.", Vector3(7.78, 2.9, 4.0), -PI * 0.5, 44, Color(0.7, 0.85, 1.05), 0.005)
	# floor wayfinding (matches turnstile lane) + wet-floor sign left standing
	spawn("wet_sign", Vector3(2.4, 0, 8.2), 0.4, {"scale": 1.0, "collide": "none"})
	# ---- evacuation: dropped lanyards, bags, shoes, spilled papers all over the floor
	for p in [Vector3(-2.0, 0, 7.2), Vector3(2.8, 0, 1.0), Vector3(0.5, 0, -1.2), Vector3(-5.8, 0, 7.4), Vector3(3.6, 0, 9.4), Vector3(-0.6, 0, 4.8)]:
		Props.papers(geo, p + Vector3(0, 0.03, 0), 6)
	var bag := Mats.color(Color(0.1, 0.12, 0.2), 0.8)
	box(Vector3(1.2, 0.18, 6.6), Vector3(0.5, 0.18, 0.28), bag, false, Vector3(0, 0.6, 0.1))
	box(Vector3(-1.4, 0.14, 8.8), Vector3(0.4, 0.28, 0.24), Mats.color(Color(0.3, 0.12, 0.1), 0.7), false, Vector3(0.1, 1.2, 0))
	spawn("laptop", Vector3(0.0, 0.03, 4.6), 2.3, {"scale": 0.5, "rot": Vector3(0, 0, 0), "collide": "none"})
	spawn("clipboard", Vector3(-3.0, 0.04, 6.0), 0.9, {"scale": 1.0, "collide": "none", "rot": Vector3(1.57, 0, 0)})
	# frost creeping in from the doors: ice-rime shelf on the floor + drifts of blown snow in the vestibule
	_vestibule()

static func _vestibule() -> void:
	var fm := pbr("ice", 1.5, Color(0.8, 0.9, 1.0, 1.0), 0.35, 0.8)
	for i in 7:
		var x := rf(-2.4, 2.4)
		var z := rf(10.0, 11.8)
		box(Vector3(x, 0.01, z), Vector3(rf(1.4, 2.6), 0.014, rf(0.8, 1.6)), Mats.get_mat("frost", 1.0), false, Vector3(0, rng.randf() * TAU, 0))
	for p in [Vector3(-1.9, 0, 11.4), Vector3(1.8, 0, 11.5), Vector3(0.0, 0, 11.7)]:
		Props.drift(geo, p, rf(1.4, 2.2), rf(0.25, 0.4), rf(0.7, 1.0), rf(-0.4, 0.4))
	# glass shards on the floor in front of the door and on the sill
	var sh := Mats.color(Color(0.75, 0.85, 0.9, 0.45), 0.05)
	for i in 38:
		var s := rf(0.03, 0.12)
		box(Vector3(rf(-2.6, 2.6), 0.012, rf(8.6, 11.8)), Vector3(s, 0.006, s * rf(0.4, 1.0)), sh, false, Vector3(0, rng.randf() * TAU, 0))
	# icicles along the lintel
	var ice := Mats.get_mat("ice")
	for i in 14:
		var h := rf(0.1, 0.45)
		Props.cyl(geo, 0.0, h, Vector3(-2.4 + i * 0.37, 3.15 - h * 0.5, 11.95), ice, false, 0.025)

# ------------------------------------------------------------------ halls A / C
static func _halls() -> void:
	# overhead: fire-suppression main (red) and hot-aisle exhaust trunking, per hall
	var red := Mats.color(Color(0.55, 0.06, 0.05), 0.45, 0.35)
	for hall in [[-6.0, -36.0], [-36.5, -59.5]]:
		var z0: float = hall[1]
		var z1: float = hall[0]
		var zc: float = (z0 + z1) * 0.5
		var len: float = absf(z1 - z0)
		for x in [-3.2, 3.2]:
			Props.cyl(geo, 0.07, len, Vector3(x, 4.05, zc), red, false, -1.0, Vector3(PI * 0.5, 0, 0), 12)
			var z := z0 + 1.0
			while z < z1:
				Props.cyl(geo, 0.012, 0.45, Vector3(x, 4.28, z), Mats.color(Color(0.3, 0.3, 0.32), 0.5, 0.8), false)
				z += 3.0
	# hot aisle exhaust ducts above the (orange) hot aisles
	for hall in [[-34.0, -8.0], [-58.0, -38.0]]:
		for x in [-7.5, 7.5]:
			duct(Vector3(x, 3.55, hall[0]), Vector3(x, 3.55, hall[1]), 0.7, 0.45)
	# lifted floor tiles, cable bundles
	for p in [Vector3(-4.0, 0, -17.0), Vector3(2.3, 0, -26.0), Vector3(9.0, 0, -12.0), Vector3(-6.5, 0, -46.0), Vector3(6.0, 0, -52.0)]:
		_lifted_tile(p)
	# sealed pallets / spares cage in a hall A corner
	spawn("plant_01", Vector3(-14.8, 0, -6.6), 0.0, {"scale": 0.9, "collide": "none", "tint": Color(0.5, 0.5, 0.42)})
	# scattered tech paper, a dropped tablet, hi-vis helmet near the doors
	for p in [Vector3(-1.5, 0, -8.5), Vector3(2.0, 0, -33.5), Vector3(-2.5, 0, -38.0), Vector3(3.5, 0, -57.5)]:
		Props.papers(geo, p + Vector3(0, 0.03, 0), 7)
	spawn("clipboard", Vector3(1.2, 0.03, -10.2), 1.0, {"scale": 1.0, "collide": "none", "rot": Vector3(1.57, 0, 0)})
	# cold-air glow under the perforated tiles of the cold aisles
	for x in [-11.5, 11.5]:
		for hz in [[-34.0, -8.0], [-58.0, -38.0]]:
			var zc: float = (hz[0] + hz[1]) * 0.5
			var l: float = absf(hz[1] - hz[0])
			box(Vector3(x, 0.012, zc), Vector3(1.4, 0.006, l), emi(Color(0.25, 0.55, 1.0), 0.55), false)
	# aisle labels on the floor: yellow guide lines
	for hz in [[-34.0, -8.0], [-58.0, -38.0]]:
		var zc: float = (hz[0] + hz[1]) * 0.5
		var l: float = absf(hz[1] - hz[0])
		box(Vector3(0.0, 0.01, zc), Vector3(0.1, 0.004, l), Mats.color(Color(0.95, 0.8, 0.1), 0.5), false)

## Rectangular sheet-metal duct from a to b (axis aligned) with flange collars and hanger rods.
static func duct(a: Vector3, b: Vector3, w: float, h: float) -> void:
	var d := b - a
	var len := d.length()
	var mid := (a + b) * 0.5
	var along_x := absf(d.x) > absf(d.z)
	var size := Vector3(len, h, w) if along_x else Vector3(w, h, len)
	var m := pbr("metal", 1.2, Color(0.62, 0.66, 0.72), 0.55, 0.5, 0.7)
	box(mid, size, m, false)
	var fl := Mats.color(Color(0.3, 0.33, 0.37), 0.5, 0.7)
	var n := int(len / 2.4)
	for i in range(1, n + 1):
		var t := float(i) / float(n + 1)
		var p := a.lerp(b, t)
		box(p, Vector3(0.06, h + 0.08, w + 0.08) if along_x else Vector3(w + 0.08, h + 0.08, 0.06), fl, false)
		if i % 2 == 0:
			for s in [-1, 1]:
				var off := Vector3(0, 0, s * w * 0.55) if along_x else Vector3(s * w * 0.55, 0, 0)
				Props.cyl(geo, 0.01, 4.5 - p.y - h * 0.5, p + off + Vector3(0, (4.5 - p.y + h * 0.5) * 0.5, 0), fl, false, -1.0, Vector3.ZERO, 4)

static func _lifted_tile(p: Vector3) -> void:
	box(p + Vector3(0, 0.008, 0), Vector3(0.62, 0.01, 0.62), Mats.color(Color(0.008, 0.008, 0.01), 0.9), false)
	box(p + Vector3(0.75, 0.04, 0.35), Vector3(0.58, 0.035, 0.58), floor_raised(), false, Vector3(0.0, 0.5, 0.18))
	var cols := [Color(0.9, 0.45, 0.05), Color(0.1, 0.4, 0.9), Color(0.95, 0.85, 0.1), Color(0.08, 0.08, 0.09), Color(0.1, 0.7, 0.3)]
	for i in 9:
		var c: Color = cols[i % cols.size()]
		var ln := rf(1.2, 3.2)
		var a := rf(0, TAU)
		var mat := Mats.color(c, 0.5)
		Props.cyl(geo, 0.012, ln, p + Vector3(cos(a) * ln * 0.5, 0.02, sin(a) * ln * 0.5), mat, false, -1.0, Vector3(0, -a, PI * 0.5), 5)

# ------------------------------------------------------------------ corridor
static func _corridor() -> void:
	# dado rail and kick strip along the north (plant side) wall
	box(Vector3(10.0, 0.15, -60.15), Vector3(79.0, 0.3, 0.04), Mats.color(Color(0.05, 0.055, 0.065), 0.4, 0.5), false)
	# cable tray cover and cameras
	for x in [-20.0, -2.0, 24.0, 40.0]:
		spawn("sec_cam", Vector3(x, 3.75, -65.6), PI, {"scale": 0.8, "collide": "none", "rot": Vector3(0.3, 0, 0)})
	# plants and benches along the corridor wall (south wall is glass at the NOC)
	for x in [-26.0, 12.0, 46.0]:
		spawn("plant_02", Vector3(x, 0, -65.2), rf(0, 6.0), {"scale": 1.1, "collide": "none", "tint": Color(0.5, 0.48, 0.4)})
	# fire extinguisher stations
	for x in [-24.0, 4.0, 34.0]:
		Env.spawn(geo, "interior/extinguisher", Vector3(x, 0.0, -60.4), 0.0, {"scale": 1.0, "snow": 0.0, "collide": "none"})
	# floor papers and an office chair that someone ran from
	for p in [Vector3(-12.0, 0, -62.0), Vector3(14.0, 0, -64.0), Vector3(36.0, 0, -61.5), Vector3(-22.0, 0, -64.0)]:
		Props.papers(geo, p + Vector3(0, 0.03, 0), 8)
	Props.chair(geo, Vector3(18.0, 0, -61.6), 0.8, true)
	Props.chair(geo, Vector3(-9.0, 0, -64.3), 2.2, true)

# ------------------------------------------------------------------ NOC and break room
static func _noc_break() -> void:
	# monitors with live-looking screens across the NOC desks, laptops, fallen chairs
	var cols := [Color(0.1, 0.35, 0.7), Color(0.05, 0.5, 0.45), Color(0.15, 0.25, 0.6), Color(0.6, 0.35, 0.05)]
	for r in 2:
		for c in 3:
			var x := -10.0 + c * 3.8
			var z := -76.0 + r * 2.5
			var sc: Color = cols[(r * 3 + c) % cols.size()]
			box(Vector3(x - 0.45, 1.5, z - 0.1), Vector3(0.5, 0.32, 0.03), Mats.color(Color(0.03, 0.03, 0.035), 0.3), false, Vector3(0, PI + 0.3, 0))
			box(Vector3(x - 0.44, 1.5, z - 0.12), Vector3(0.46, 0.27, 0.01), emi(sc, 1.2), false, Vector3(0, PI + 0.3, 0))
			if (r + c) % 2 == 0:
				Props.chair(geo, Vector3(x + rf(-0.4, 0.4), 0, z + rf(0.9, 1.4)), rf(0, TAU), (r * 3 + c) % 3 == 0)
			Props.papers(geo, Vector3(x + rf(-0.3, 0.3), 0.03, z + rf(1.2, 1.8)), 5)
	spawn("laptop", Vector3(-5.9, 0.83, -75.6), 0.6, {"scale": 0.5, "collide": "none"})
	spawn("laptop", Vector3(1.7, 0.83, -77.4), 2.4, {"scale": 0.5, "collide": "none"})
	spawn("plant_01", Vector3(-12.6, 0, -69.5), 0.0, {"scale": 1.0, "collide": "none", "tint": Color(0.5, 0.48, 0.4)})
	# carpet tiles under everything, mismatched squares where something was dragged
	# break room: kitchenette, clock, plant and the notice board
	Env.spawn(geo, "interior/wall_clock", Vector3(-22.0, 2.7, -79.85), 0.0, {"scale": 1.0, "snow": 0.0, "collide": "none"})
	spawn("plant_01", Vector3(-29.0, 0, -79.0), 0.0, {"scale": 0.9, "collide": "none", "tint": Color(0.55, 0.52, 0.44)})
	spawn("mono_chair", Vector3(-26.4, 0, -73.2), 2.7, {"scale": 1.0, "collide": "none", "rot": Vector3(1.4, 0, 0)})
	box(Vector3(-20.0, 1.65, -79.88), Vector3(2.2, 1.0, 0.04), pbr("plaster", 1.0, Color(0.5, 0.4, 0.28), 1.0), false)
	for i in 6:
		box(Vector3(-20.8 + i * 0.32, 1.7 + rf(-0.2, 0.2), -79.84), Vector3(0.22, 0.3, 0.005), Mats.get_mat("paper"), false, Vector3(0, 0, rf(-0.15, 0.15)))

# ------------------------------------------------------------------ plant, armory, pipeline hall
static func _plant_pipeline() -> void:
	# hazard-striped floor lanes in the cooling plant and the pipeline hall
	box(Vector3(33.0, 0.008, -46.2), Vector3(32.0, 0.004, 0.18), hazard(), false)
	box(Vector3(33.0, 0.008, -49.8), Vector3(32.0, 0.004, 0.18), hazard(), false)
	box(Vector3(18.0, 0.008, -78.0), Vector3(0.18, 0.004, 22.0), hazard(), false)
	box(Vector3(18.0, 0.008, -92.0), Vector3(0.18, 0.004, 10.0), hazard(), false)
	# ducting overhead in the plant
	duct(Vector3(17.0, 3.8, -52.0), Vector3(49.0, 3.8, -52.0), 0.8, 0.5)
	# wet-floor, frozen mop bucket, crates
	spawn("wet_sign", Vector3(24.0, 0, -45.0), 1.2, {"scale": 1.0, "collide": "none"})
	Props.papers(geo, Vector3(30.0, 0.03, -44.0), 6)

# ------------------------------------------------------------------ exterior
static func _exterior() -> void:
	# facade reading as a real building: curtain-wall glass bands and lit mullions
	var gl := Mats.color(Color(0.05, 0.09, 0.12, 0.5), 0.05, 0.1)
	for i in range(-6, 10):
		var x := i * 5.0 - 1.0
		if absf(x) < 4.0:
			continue
		for yy in [2.4, 6.4]:
			box(Vector3(x, yy, 12.4), Vector3(2.7, 1.7, 0.06), gl, false)
	# floodlights on poles near the gate: tall, cold, lit road
	for p in [Vector3(-9.0, 0, 52.0), Vector3(9.0, 0, 56.0)]:
		Props.lamp_post(geo, p, 0.0 if p.x < 0 else PI, true, Color(0.7, 0.85, 1.0))
	# jersey barriers at the checkpoint
	Props.barrier(geo, Vector3(-4.6, 0, 47.4), 0.1, 1)
	Props.barrier(geo, Vector3(4.6, 0, 47.4), -0.1, 2)
	# snowdrifts against the facade, plough berms along the road
	for i in 9:
		Props.drift(geo, Vector3(-30.0 + i * 9.0, 0, 13.6), rf(2.8, 4.6), rf(0.4, 0.9), rf(1.0, 1.8), rf(-0.2, 0.2))
	for z in [60.0, 70.0, 80.0, 90.0]:
		Props.drift(geo, Vector3(-6.4, 0, z), rf(1.6, 2.4), rf(0.5, 0.8), rf(2.0, 3.0), 0.0)
		Props.drift(geo, Vector3(6.6, 0, z + 3.0), rf(1.6, 2.4), rf(0.5, 0.8), rf(2.0, 3.0), 0.0)
	# rooftop beacons: red aviation lights pulse over the building (visible from the lake road)
	for p in [Vector3(-30, 9.9, -20), Vector3(46, 9.9, -20), Vector3(-30, 9.9, 8), Vector3(46, 9.9, 8)]:
		Props.sphere(geo, 0.18, p, emi(Color(1.0, 0.1, 0.05), 5.0))
	# MERIDIAN wordmark: big, floodlit, readable from the spawn
	var l := label("MERIDIAN", Vector3(0, 8.4, 12.34), 0.0, 260, Color(0.85, 0.95, 1.3), 0.016, false)
	l.render_priority = 2
	box(Vector3(0, 8.4, 12.3), Vector3(34.0, 3.2, 0.06), pbr("clad", 2.0, Color(0.5, 0.55, 0.6), 1.0), false)
	# the entrance's sidelights glow warm (the only warm light in town)
	box(Vector3(-2.2, 1.7, 12.42), Vector3(0.9, 3.0, 0.05), emi(Color(1.0, 0.85, 0.65), 1.1), false)
	box(Vector3(2.2, 1.7, 12.42), Vector3(0.9, 3.0, 0.05), emi(Color(1.0, 0.85, 0.65), 1.1), false)

# ------------------------------------------------------------------ signage / emergency lighting
static func _signage_and_safety() -> void:
	# exit signs with soft green spill, red emergency beacons that pulse in the corridor
	var exits := [Vector3(0, 3.5, -5.8), Vector3(-15.8, 3.0, -14.0), Vector3(15.8, 3.0, -48.0), Vector3(2.0, 3.0, -65.8)]
	var yaws := [0.0, PI * 0.5, -PI * 0.5, 0.0]
	for i in exits.size():
		var p: Vector3 = exits[i]
		box(p, Vector3(0.5, 0.2, 0.06), Mats.color(Color(0.04, 0.2, 0.08), 0.5), false, Vector3(0, yaws[i], 0))
		var lb := label("EXIT", p + Vector3(0, 0, 0.04).rotated(Vector3.UP, yaws[i]), yaws[i], 34, Color(0.3, 1.0, 0.5), 0.004)
		var gl := OmniLight3D.new()
		gl.light_color = Color(0.2, 1.0, 0.4)
		gl.light_energy = 0.4
		gl.omni_range = 4.0
		gl.shadow_enabled = false
		gl.position = p + Vector3(0, -0.4, 0.5).rotated(Vector3.UP, yaws[i])
		host.add_child(gl)
	# slow red emergency beacons (no shadows): corridor + plant
	for p in [Vector3(-8.0, 3.8, -63.0), Vector3(30.0, 3.8, -63.0), Vector3(28.0, 3.6, -50.0)]:
		var r := OmniLight3D.new()
		r.light_color = Color(1.0, 0.1, 0.08)
		r.light_energy = 0.9
		r.omni_range = 6.0
		r.shadow_enabled = false
		r.position = p
		host.add_child(r)
		var tw := r.create_tween().set_loops()
		tw.tween_property(r, "light_energy", 0.05, 1.1).set_trans(Tween.TRANS_SINE)
		tw.tween_property(r, "light_energy", 1.1, 1.1).set_trans(Tween.TRANS_SINE)
		box(p + Vector3(0, 0.15, 0), Vector3(0.18, 0.12, 0.18), emi(Color(1.0, 0.1, 0.05), 3.0), false)
