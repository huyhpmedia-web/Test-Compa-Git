extends RefCounted
## L4 - MERIDIAN, round 7 (R7-C): real Sketchfab models (assets/env/industrial_sf, CC-BY, see assets/CREDITS_SKETCHFAB.json)
## replacing the remaining primitives: modern industrial facade (cladding fins, ribbon windows, plinth, roof plant,
## loading docks, mechanical yard, fire escape), security booth, rack rows, NOC video wall + consoles, break room,
## cooling plant, electrical room and pipeline head.  Decoration only: gameplay nodes live in l4_meridian.gd.

const Props = preload("res://world/props.gd")
const Mats = preload("res://core/mats.gd")
const Env = preload("res://world/env_assets.gd")
const Art = preload("res://levels/dressing/l4_art.gd")
const Gore = preload("res://world/gore.gd")

static var geo: Node3D
static var host: Node3D
static var rng := RandomNumberGenerator.new()
static var _screen_sh: Shader

# ================================================================== helpers
static func sp(rel: String, pos: Vector3, yaw := 0.0, opts := {}) -> Node3D:
	if not opts.has("snow"):
		opts["snow"] = 0.0
	if not opts.has("collide"):
		opts["collide"] = "none"
	return Env.spawn(geo, rel, pos, yaw, opts)

static func isf(name: String, pos: Vector3, yaw := 0.0, opts := {}) -> Node3D:
	return sp("industrial_sf/" + name, pos, yaw, opts)

## Mesh-less collider (carves the navmesh like any StaticBody3D under geo).
static func solid(pos: Vector3, size: Vector3, yaw := 0.0) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	sb.position = pos
	sb.rotation.y = yaw
	geo.add_child(sb)
	return sb

static func box(pos: Vector3, size: Vector3, mat: Material, solid_ := false, rot := Vector3.ZERO) -> MeshInstance3D:
	return Props.box(geo, size, pos, mat, solid_, rot)

static func rf(a: float, b: float) -> float:
	return rng.randf_range(a, b)

static func omni(pos: Vector3, col: Color, energy: float, rng_m: float, shadow := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng_m
	l.shadow_enabled = shadow
	l.position = pos
	host.add_child(l)
	return l

## Animated monitor / video-wall surface: dark glass with a scrolling graph, bars and scanline, tinted per screen.
static func screen_mat(col: Color, energy := 1.6, seed_v := 0.0, mode := 0) -> ShaderMaterial:
	if _screen_sh == null:
		_screen_sh = Shader.new()
		_screen_sh.code = """shader_type spatial;
render_mode cull_disabled;
uniform vec3 tint : source_color = vec3(0.1, 0.4, 0.8);
uniform float energy = 1.6;
uniform float seed = 0.0;
uniform int mode = 0;
float h(float x) { return fract(sin(x * 127.1 + seed * 13.7) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	float t = TIME;
	vec3 c = vec3(0.012, 0.016, 0.022);
	float g = step(0.96, fract(uv.x * 24.0)) + step(0.94, fract(uv.y * 12.0));
	c += tint * g * 0.08;
	if (mode == 0) {
		float x = uv.x * 40.0 + t * 1.5;
		float y = 0.5 + 0.28 * sin(x * 0.7 + seed) * h(floor(x)) + 0.1 * (h(floor(x * 2.0)) - 0.5);
		float line = smoothstep(0.03, 0.0, abs(uv.y - y));
		c += tint * line * 1.4;
		for (int i = 0; i < 6; i++) {
			float fi = float(i);
			float bx = 0.06 + fi * 0.15;
			float bh = 0.1 + 0.25 * h(fi + floor(t * 0.7 + seed) );
			if (uv.x > bx && uv.x < bx + 0.09 && uv.y > 0.08 && uv.y < 0.08 + bh) { c += tint * 0.55; }
		}
		float panel = step(0.62, uv.y) * step(0.05, uv.x) * step(uv.x, 0.45);
		c += tint * panel * 0.1 * (0.5 + 0.5 * sin(t * 2.0 + seed));
	} else if (mode == 1) {
		float rowv = floor(uv.y * 26.0);
		float ln = step(h(rowv), 0.65) * step(uv.x, 0.1 + 0.8 * h(rowv + 3.0));
		c += tint * ln * 0.5 * step(0.5, fract(uv.y * 26.0));
		float cur = step(fract(t * 0.8 + seed), 0.5) * step(uv.x, 0.52) * step(0.5, uv.x) * step(0.9, uv.y);
		c += tint * cur;
	} else {
		c += tint * (0.25 + 0.15 * sin(t * 3.0 + seed)) * step(0.05, uv.y);
		c += tint * smoothstep(0.02, 0.0, abs(uv.x - fract(t * 0.2 + seed)));
	}
	float scan = 0.88 + 0.12 * sin(uv.y * 380.0 - t * 5.0);
	float flick = 0.94 + 0.06 * sin(t * 61.0 + seed * 9.0);
	ALBEDO = c * 0.25;
	EMISSION = c * energy * scan * flick;
	ROUGHNESS = 0.18;
	METALLIC = 0.0;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _screen_sh
	m.set_shader_parameter("tint", Vector3(col.r, col.g, col.b))
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("seed", seed_v)
	m.set_shader_parameter("mode", mode)
	return m

## Desktop monitor on a desk (local frame given by pos/yaw).
static func monitor(pos: Vector3, yaw: float, col: Color, seed_v := 0.0, mode := 0) -> Node3D:
	var m := sp("industrial_sf/monitor", pos, yaw, {"mats": {"layar": screen_mat(col, 1.5, seed_v, mode)}, "shadow": false, "range": 40.0})
	return m

## Pipe with PBR metal, flanges every few metres and optional insulation wrap.
static func pipe(a: Vector3, b: Vector3, r: float, tint := Color(0.6, 0.64, 0.7), insulated := false) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.05:
		return
	var m := Art.pbr("metal", 1.0, tint if not insulated else Color(0.78, 0.8, 0.82), 0.5 if not insulated else 0.7, 0.5, 0.75 if not insulated else 0.35)
	var mi := Props.cyl(geo, r, L, (a + b) * 0.5, m, false, -1.0, Vector3.ZERO, 14)
	var up := d.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.95 else Vector3.RIGHT).normalized()
	mi.basis = Basis(side, up, side.cross(up)).orthonormalized()
	var fm := Mats.color(Color(0.22, 0.24, 0.27), 0.45, 0.7)
	var n := int(L / 2.6)
	for i in range(1, n + 1):
		var p := a.lerp(b, float(i) / float(n + 1))
		var fl := Props.cyl(geo, r * 1.22, 0.07, p, fm, false, -1.0, Vector3.ZERO, 14)
		fl.basis = mi.basis
		if insulated and i % 2 == 0:
			var bd := Props.cyl(geo, r * 1.06, 0.14, p, Mats.color(Color(0.55, 0.57, 0.6), 0.5, 0.6), false, -1.0, Vector3.ZERO, 14)
			bd.basis = mi.basis


# ================================================================== grime decals (procedural, generated once)
static var _decal_tex := {}

static func _make_decal(kind: String) -> Texture2D:
	if _decal_tex.has(kind):
		return _decal_tex[kind]
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = 77 + kind.hash() % 1000
	var W := 96
	var H := 192 if kind == "streak" else 128
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for y in H:
		for x in W:
			var fx := float(x) / W
			var fy := float(y) / H
			var a := 0.0
			if kind == "streak":
				var v := n.get_noise_2d(x * 5.5, y * 0.35) * 0.5 + 0.5
				var v2 := n.get_noise_2d(x * 1.8 + 40.0, y * 0.12) * 0.5 + 0.5
				a = clampf((v - 0.45) * 3.2, 0.0, 1.0) * clampf((v2 - 0.25) * 2.0, 0.0, 1.0)
				a *= pow(1.0 - fy, 0.8) * smoothstep(0.0, 0.06, fy)
			elif kind == "stain":
				var d := Vector2(fx - 0.5, fy - 0.5).length() * 2.0
				var v3 := n.get_noise_2d(x * 2.2, y * 2.2) * 0.5 + 0.5
				a = clampf((1.0 - d) * 1.6 + (v3 - 0.5) * 1.3, 0.0, 1.0)
				a = smoothstep(0.05, 0.8, a) * 0.9
			else:   # oil / grease: dark irregular puddle with a thin bright rim
				var d2 := Vector2(fx - 0.5, fy - 0.5).length() * 2.0
				var v4 := n.get_noise_2d(x * 3.0, y * 3.0) * 0.5 + 0.5
				a = clampf((0.95 - d2) * 2.2 + (v4 - 0.5) * 1.6, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var t := ImageTexture.create_from_image(img)
	_decal_tex[kind] = t
	return t

## Projected grime: kind = streak | stain | oil.  `normal` points out of the surface; size = (width, height) on it.
static func decal(kind: String, pos: Vector3, normal: Vector3, size: Vector2, tint := Color(0.05, 0.045, 0.04), strength := 0.8, depth := 0.7) -> Decal:
	if kind == "streak" and normal.y == 0.0 and pos.y < 3.0 and pos.z < 3.0 and pos.z > -3.0 and pos.x < 30.0 and pos.y > 1.0:
		return null
	var d := Decal.new()
	d.size = Vector3(size.x, depth, size.y)
	d.texture_albedo = _make_decal(kind)
	d.modulate = Color(tint.r, tint.g, tint.b, strength)
	d.albedo_mix = 1.0
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	d.cull_mask = 1
	var y_axis := normal.normalized()
	var x_axis := Vector3.RIGHT
	var z_axis := Vector3.BACK
	if absf(y_axis.y) < 0.9:
		z_axis = Vector3.DOWN                       # streaks run down the wall
		x_axis = y_axis.cross(z_axis).normalized()
		z_axis = x_axis.cross(y_axis).normalized()
	else:
		x_axis = Vector3.RIGHT
		z_axis = x_axis.cross(y_axis).normalized()
	d.basis = Basis(x_axis, y_axis, z_axis)
	d.position = pos
	geo.add_child(d)
	return d

# ================================================================== entry
static func setup(level: Node3D) -> void:
	host = level
	geo = level.get("geo") if level.get("geo") is Node3D else level

static func dress(level: Node3D) -> void:
	setup(level)
	rng.seed = 7007
	_facade()
	_roof()
	_docks()
	_mech_yard()
	_fire_escape()
	_yard_clutter()
	_lobby()
	_noc()
	_break_room()
	_plant_extras()
	_electrical_extras()
	_pipeline_extras()
	_halls_extras()
	_steam()

# ================================================================== facade
static func _facade() -> void:
	var fz := 12.2
	var dark := Art.pbr("metal", 1.6, Color(0.2, 0.22, 0.25), 0.4, 0.6, 0.85)
	var conc := Art.pbr("concrete", 2.5, Color(0.62, 0.64, 0.66), 1.0, 1.0)
	var alu := Mats.color(Color(0.55, 0.57, 0.6), 0.35, 0.85)
	var glass_dark := Mats.color(Color(0.012, 0.02, 0.03), 0.04, 0.7)
	# plinth: reinforced concrete skirt, 1.1 m, with a drip cap
	for seg in [[-34.0, -4.4], [4.4, 50.0]]:
		var w: float = seg[1] - seg[0]
		var c: float = (seg[0] + seg[1]) * 0.5
		box(Vector3(c, 0.55, fz + 0.12), Vector3(w, 1.1, 0.3), conc)
		box(Vector3(c, 1.12, fz + 0.2), Vector3(w, 0.05, 0.4), dark)
	# structural fins every 6 m, with a thin cold edge light
	var x := -31.0
	while x < 50.0:
		if absf(x) > 6.5:
			box(Vector3(x, 4.95, fz + 0.2), Vector3(0.5, 9.0, 0.42), dark)
			box(Vector3(x, 9.55, fz + 0.2), Vector3(0.62, 0.25, 0.5), alu)
		x += 6.0
	# horizontal reveal bands (shadow lines in the cladding)
	for yy in [3.5, 6.0, 8.4]:
		box(Vector3(8.0, yy, fz + 0.06), Vector3(84.0, 0.06, 0.1), Mats.color(Color(0.04, 0.045, 0.05), 0.6))
	# ribbon windows: dark glass in aluminium frames, some lit warm (office wing), most cold-dark
	var seed_i := 0
	for i in range(-6, 10):
		var wx := i * 5.0 - 1.0
		if absf(wx) < 4.5:
			continue
		for yy in [2.4, 6.4]:
			seed_i += 1
			var lit := rng.randf()
			var gm: Material = glass_dark
			if lit > 0.78:
				gm = Mats.emissive(Color(1.0, 0.82, 0.6), 0.9)
			elif lit > 0.45:
				gm = Mats.emissive(Color(0.45, 0.62, 0.85), 0.35)
			box(Vector3(wx, yy, fz + 0.02), Vector3(2.7, 1.7, 0.12), gm)
			# frame
			for s in [-1, 1]:
				box(Vector3(wx + s * 1.37, yy, fz + 0.12), Vector3(0.09, 1.8, 0.2), alu)
			box(Vector3(wx, yy + 0.88, fz + 0.12), Vector3(2.85, 0.09, 0.2), alu)
			box(Vector3(wx, yy - 0.88, fz + 0.14), Vector3(2.85, 0.07, 0.32), conc)
			box(Vector3(wx, yy, fz + 0.12), Vector3(0.05, 1.7, 0.18), alu)
			# blinds half-drawn in a few
			if rng.randf() < 0.35:
				box(Vector3(wx + rf(-0.5, 0.5), yy + 0.4, fz + 0.08), Vector3(rf(1.0, 2.4), rf(0.3, 0.8), 0.03), Mats.color(Color(0.5, 0.5, 0.48), 0.9))
	# grime: rain/dirt streaks under sills and the parapet, salt stains at the plinth
	for i in range(-6, 10):
		var gx := i * 5.0 - 1.0
		if absf(gx) < 4.5:
			continue
		for yy in [2.4, 6.4]:
			if rng.randf() < 0.75:
				decal("streak", Vector3(gx + rf(-0.5, 0.5), yy - 2.1, fz + 0.2), Vector3(0, 0, 1), Vector2(rf(1.6, 2.8), 3.4), Color(0.04, 0.04, 0.035), rf(0.45, 0.8))
	for gx2 in range(-30, 50, 7):
		if absf(gx2) > 6.0:
			decal("streak", Vector3(gx2 + rf(-1, 1), 8.0, fz + 0.2), Vector3(0, 0, 1), Vector2(rf(3.0, 5.0), 4.6), Color(0.05, 0.045, 0.035), rf(0.5, 0.9))
	for gx3 in range(-32, 50, 5):
		decal("stain", Vector3(gx3 + rf(-1, 1), 0.7, fz + 0.2), Vector3(0, 0, 1), Vector2(rf(2.0, 4.0), rf(1.2, 2.2)), Color(0.55, 0.55, 0.52), rf(0.25, 0.5))
	# louvre intake grilles on the plant side (dark slats, blue standby glow)
	for gx in [-22.5, 22.0, 41.5]:
		box(Vector3(gx, 4.9, fz + 0.1), Vector3(3.4, 1.6, 0.12), Mats.color(Color(0.015, 0.018, 0.022), 0.5))
		for k in 9:
			box(Vector3(gx, 4.2 + k * 0.17, fz + 0.2), Vector3(3.3, 0.04, 0.12), alu, false, Vector3(0.45, 0, 0))
		box(Vector3(gx, 5.82, fz + 0.18), Vector3(3.4, 0.03, 0.04), Mats.emissive(Color(0.25, 0.55, 1.0), 1.4))
	# entrance: dark mullions framing the glass doors, recessed downlights, brass plate, bollards, planters
	var em := Mats.emissive(Color(1.0, 0.9, 0.75), 3.0)
	for dx in [-2.6, -1.3, 1.3, 2.6]:
		Props.cyl(geo, 0.1, 0.02, Vector3(dx, 3.27, 13.7), em, false, -1.0, Vector3.ZERO, 10)
	for dx in [-3.6, 3.6]:
		Props.cyl(geo, 0.14, 0.9, Vector3(dx, 0.45, 14.9), Mats.color(Color(0.9, 0.75, 0.1), 0.5), false, -1.0, Vector3.ZERO, 10)
		Props.cyl(geo, 0.15, 0.04, Vector3(dx, 0.9, 14.9), Mats.color(Color(0.1, 0.1, 0.1), 0.5), false, -1.0, Vector3.ZERO, 10)
	box(Vector3(-5.2, 1.5, fz + 0.1), Vector3(0.55, 0.38, 0.03), Mats.color(Color(0.6, 0.5, 0.25), 0.3, 0.8))
	# wall lamps on the facade, down-lighting the cladding (practical lights without shadows)
	for lx in [-26.0, -16.0, 14.0, 26.0, 38.0, 46.0]:
		sp("facade/wall_lamp", Vector3(lx, 3.0, fz + 0.1), 0.0, {"scale": 1.2})
		omni(Vector3(lx, 2.7, fz + 1.0), Color(0.75, 0.86, 1.0), 0.9, 6.5)
	# flank walls (3.5 m concrete): coping + cap fence, so they read as a secured perimeter
	for seg in [[-70.0, -34.0], [50.0, 80.0]]:
		var c2: float = (seg[0] + seg[1]) * 0.5
		var w2: float = seg[1] - seg[0]
		box(Vector3(c2, 3.55, 12.0), Vector3(w2, 0.14, 0.9), conc)
		var fx: float = seg[0] + 1.6
		while fx < seg[1] - 1.0:
			sp("industrial_sf/chainlink", Vector3(fx + 5.4, 3.55, 12.0), 0.0, {"scale": 1.0, "snow": 0.3, "range": 140.0, "shadow": false})
			fx += 10.8

# ================================================================== roof plant
static func _roof() -> void:
	var y := 9.9
	var par := Art.pbr("clad", 2.0, Color(0.75, 0.78, 0.82), 0.9, 0.8, 0.3)
	# parapet and coping around the roof (front only matters; sides cheap)
	box(Vector3(8.0, y + 0.45, 12.1), Vector3(84.8, 0.9, 0.35), par)
	box(Vector3(8.0, y + 0.92, 12.1), Vector3(85.0, 0.1, 0.55), Art.pbr("metal", 1.5, Color(0.5, 0.53, 0.57), 0.4, 0.5, 0.9))
	# roof-top air handlers and exhaust fans in a row behind the parapet
	for i in 9:
		var hx := -30.0 + i * 8.6 + rf(-0.6, 0.6)
		isf("hvac_unit", Vector3(hx, y, 8.4 + rf(-0.5, 0.5)), PI + rf(-0.1, 0.1), {"scale": 1.35, "snow": 0.7, "range": 150.0, "shadow": false})
	for i in 6:
		var hx2 := -26.0 + i * 13.0
		isf("exhaust_fan", Vector3(hx2, y + 0.05, 5.0), 0.0, {"scale": 1.8, "snow": 0.6, "range": 120.0, "shadow": false, "rot": Vector3(-PI * 0.5, 0, 0)})
	# roof-edge anchor line (fall protection) and a satellite comms mast: tall thin silhouettes on the sky
	Props.cyl(geo, 0.08, 9.0, Vector3(44.0, y + 4.5, 2.0), Mats.color(Color(0.5, 0.52, 0.55), 0.5, 0.8), false, 0.05, Vector3.ZERO, 8)
	Props.cyl(geo, 0.04, 6.0, Vector3(44.0, y + 7.0, 2.0), Mats.color(Color(0.5, 0.52, 0.55), 0.5, 0.8), false, 0.04, Vector3(0, 0, 0.6), 6)

# ================================================================== loading docks
static func _docks() -> void:
	var fz := 12.2
	var conc := Art.pbr("concrete", 2.0, Color(0.55, 0.57, 0.6), 1.0, 1.1)
	var dark := Art.pbr("metal", 1.6, Color(0.2, 0.22, 0.25), 0.4, 0.6, 0.85)
	var x0 := 13.0
	var x1 := 35.0
	var cx := (x0 + x1) * 0.5
	# dock platform (1.25 m, truck bed height) + dock levelers
	var plat := box(Vector3(cx, 0.625, fz + 2.2), Vector3(x1 - x0, 1.25, 4.4), conc, true)
	box(Vector3(cx, 1.26, fz + 4.35), Vector3(x1 - x0, 0.03, 0.22), Art.hazard())
	# steps at the west end
	for s in 4:
		box(Vector3(x0 - 0.5 - s * 0.0, 0.16 + s * 0.31, fz + 3.7 + 0.5 - s * 0.5), Vector3(1.8, 0.31, 0.5), conc, true)
	# four bays: shutter doors (3 m), frames, bumpers, wheel stops, number plates
	var bays := 4
	var bw := (x1 - x0) / float(bays)
	for i in bays:
		var bx := x0 + bw * (i + 0.5)
		var door_open := (i == 1)
		sp("facade/shutter_door", Vector3(bx, 1.25, fz + 0.15), 0.0, {"scale": Vector3(2.85, 1.35, 1.0), "range": 120.0})
		if door_open:
			# one door jammed half open: black gap and a work light spilling out
			box(Vector3(bx, 2.15, fz + 0.1), Vector3(2.8, 1.5, 0.08), Mats.color(Color(0.01, 0.01, 0.012), 1.0))
			omni(Vector3(bx, 2.4, fz + 1.2), Color(1.0, 0.7, 0.4), 1.4, 5.0)
		for s in [-1, 1]:
			box(Vector3(bx + s * 1.5, 2.9, fz + 0.2), Vector3(0.16, 3.3, 0.26), dark)
			box(Vector3(bx + s * 1.0, 1.7, fz + 0.38), Vector3(0.4, 0.55, 0.22), Mats.color(Color(0.03, 0.03, 0.03), 0.9))
		box(Vector3(bx, 4.57, fz + 0.2), Vector3(3.2, 0.2, 0.26), dark)
		box(Vector3(bx, 1.27, fz + 1.2), Vector3(2.4, 0.04, 1.8), Art.pbr("diamond", 1.2, Color(0.55, 0.57, 0.6), 0.5, 0.6, 0.8))
		var nl := Art.label(str(i + 1), Vector3(bx, 4.9, fz + 0.12), 0.0, 110, Color(1.0, 0.85, 0.2), 0.008)
		# painted lane guides + stop line on the apron
		box(Vector3(bx - 1.35, 0.013, fz + 9.5), Vector3(0.12, 0.004, 9.0), Mats.color(Color(0.9, 0.75, 0.1), 0.6))
		box(Vector3(bx + 1.35, 0.013, fz + 9.5), Vector3(0.12, 0.004, 9.0), Mats.color(Color(0.9, 0.75, 0.1), 0.6))
		box(Vector3(bx, 0.016, fz + 5.5), Vector3(2.0, 0.004, 0.14), Mats.color(Color(0.9, 0.9, 0.9), 0.6))
	# bollards on the dock edge, hazard-yellow
	var bxx := x0 + 0.4
	while bxx < x1:
		Props.cyl(geo, 0.1, 1.0, Vector3(bxx, 1.75, fz + 4.2), Mats.color(Color(0.92, 0.72, 0.05), 0.5), false, -1.0, Vector3.ZERO, 10)
		bxx += 2.75
	# steel canopy over the platform with strip lights
	box(Vector3(cx, 4.95, fz + 2.6), Vector3(x1 - x0 + 1.0, 0.22, 5.2), Art.pbr("metal", 1.8, Color(0.3, 0.32, 0.35), 0.5, 0.6, 0.8))
	for s in [x0 - 0.3, x1 + 0.3]:
		Props.cyl(geo, 0.12, 4.9, Vector3(s, 2.45, fz + 5.0), dark.duplicate(), true, -1.0, Vector3.ZERO, 10)
	for i in bays:
		var bx2 := x0 + bw * (i + 0.5)
		box(Vector3(bx2, 4.82, fz + 3.6), Vector3(2.4, 0.05, 0.18), Mats.emissive(Color(0.85, 0.93, 1.0), 3.2))
		omni(Vector3(bx2, 4.4, fz + 3.6), Color(0.8, 0.9, 1.0), 1.3, 7.5, i == 0)
	# oil and tyre-rubber stains on the apron, black ice patches
	for i in 7:
		decal("oil", Vector3(x0 + rf(1, x1 - x0 - 1), 0.04, fz + rf(6.0, 13.0)), Vector3.UP, Vector2(rf(1.4, 3.0), rf(1.0, 2.4)), Color(0.02, 0.02, 0.025), rf(0.6, 0.95), 0.6)
	# the live scene: truck at bay 3, forklift with a pallet on the platform, stretch-wrapped pallets, cardboard
	Props.car(geo, Vector3(x0 + bw * 2.5, 0.0, fz + 12.0), PI, Color(0.82, 0.82, 0.8), true, "van")
	isf("forklift", Vector3(x0 + 3.0, 1.25, fz + 2.6), 0.5, {"scale": 1.0, "snow": 0.0, "range": 120.0})
	var py := 1.25
	for p in [[x0 + 14.0, 2.4], [x0 + 15.3, 2.0], [x0 + 17.0, 3.0], [x0 + 9.5, 1.7]]:
		isf("pallets", Vector3(p[0], py, fz + p[1]), rf(0, 3.0), {"scale": 0.9, "snow": 0.0})
	# wrapped pallet loads (boxes stacked, translucent film)
	for p in [[x0 + 15.3, 2.0], [x0 + 17.0, 3.0]]:
		var h := rf(1.2, 1.7)
		box(Vector3(p[0], py + 0.15 + h * 0.5, fz + p[1]), Vector3(1.0, h, 0.9), Mats.color(Color(0.62, 0.5, 0.36), 0.9))
		box(Vector3(p[0], py + 0.15 + h * 0.5, fz + p[1]), Vector3(1.03, h + 0.02, 0.93), Mats.color(Color(0.8, 0.85, 0.9, 0.22), 0.1))
	for i in 7:
		sp("camp/cardboard_box", Vector3(x0 + 5.0 + rf(0, 4.5), py, fz + rf(1.2, 3.5)), rf(0, 6.0), {"scale": rf(1.2, 1.8)})

# ================================================================== mechanical yard (west wing)
static func _mech_yard() -> void:
	var fz := 12.2
	var conc := Art.pbr("concrete", 2.0, Color(0.55, 0.57, 0.6), 1.0, 1.1)
	# pad
	box(Vector3(-22.0, 0.08, fz + 3.0), Vector3(21.0, 0.16, 5.4), conc)
	# condensers on pads
	for i in 3:
		var hx := -29.0 + i * 6.8
		isf("hvac_unit", Vector3(hx, 0.16, fz + 2.8), PI, {"scale": 1.05, "snow": 0.5, "range": 130.0})
		solid(Vector3(hx, 1.0, fz + 2.8), Vector3(2.9, 2.0, 1.6))
		# refrigerant lines up the wall
		pipe(Vector3(hx - 0.6, 0.9, fz + 1.8), Vector3(hx - 0.6, 3.6, fz + 0.5), 0.05, Color(0.7, 0.45, 0.25))
		pipe(Vector3(hx - 0.35, 0.9, fz + 1.8), Vector3(hx - 0.35, 3.6, fz + 0.5), 0.07, Color(0.2, 0.2, 0.22), true)
	# chain-link cage along the front of the pad
	for i in 2:
		sp("industrial_sf/chainlink", Vector3(-27.0 + i * 10.8, 0.0, fz + 5.8), 0.0, {"snow": 0.4, "range": 100.0})
	# electrical: diesel standby generator, breaker box and conduit on the wall, fuel tank
	isf("diesel_gen", Vector3(-14.0, 0.16, fz + 2.6), 0.2, {"scale": 1.5, "collide": Vector3(2.7, 1.9, 1.4), "snow": 0.4})
	isf("breaker_box", Vector3(-11.2, 0.0, fz + 0.45), 0.0, {"scale": 1.2, "snow": 0.0})
	pipe(Vector3(-11.4, 0.2, fz + 0.5), Vector3(-11.4, 8.5, fz + 0.5), 0.05, Color(0.4, 0.42, 0.45))
	isf("storage_tank", Vector3(-33.2, 0.0, fz + 4.2), 0.0, {"scale": 0.8, "collide": "cyl", "snow": 0.5})
	omni(Vector3(-22.0, 4.5, fz + 3.0), Color(1.0, 0.7, 0.4), 0.8, 8.0)

# ================================================================== fire escape (east end)
static func _fire_escape() -> void:
	var fz := 12.2
	var rail := Art.pbr("metal", 1.0, Color(0.3, 0.32, 0.35), 0.6, 0.6, 0.8)
	var ex := 44.0
	# two-flight scissor stair up the facade to the roof, landings at 4.0 and 8.0
	sp("facade/fire_escape_platform", Vector3(ex, 4.0, fz + 0.95), 0.0, {"snow": 0.3, "range": 120.0, "collide": "none"})
	sp("facade/fire_escape_railing", Vector3(ex, 4.0, fz + 0.95), 0.0, {"snow": 0.3, "range": 120.0})
	sp("facade/fire_escape_platform", Vector3(ex, 8.0, fz + 0.95), 0.0, {"snow": 0.3, "range": 120.0})
	sp("facade/fire_escape_railing", Vector3(ex, 8.0, fz + 0.95), 0.0, {"snow": 0.3, "range": 120.0})
	sp("facade/fire_escape_stairs", Vector3(ex + 0.2, 0.0, fz + 0.95), 0.0, {"snow": 0.3, "range": 120.0})
	sp("facade/fire_escape_stairs", Vector3(ex - 0.2, 4.0, fz + 0.95), PI, {"snow": 0.3, "range": 120.0})
	sp("facade/fire_escape_ladder", Vector3(ex + 1.6, 8.0, fz + 0.3), 0.0, {"snow": 0.3, "range": 120.0})

# ================================================================== yard clutter and checkpoint
static func _yard_clutter() -> void:
	# plough-pushed pallets and a dead forklift in the snow near the dock apron, work lights
	isf("forklift", Vector3(4.5, 0.0, 24.0), 2.4, {"snow": 0.55, "range": 130.0, "collide": Vector3(1.2, 2.0, 3.0)})
	for i in 3:
		isf("pallets", Vector3(10.0 + i * 1.6, 0.0, 22.0 + rf(-0.5, 0.5)), rf(0, 3), {"scale": 0.9, "snow": 0.6, "range": 100.0})
	# fuel bunker + transformer yard on the east wing: transformer, generator, cabinet, fenced
	sp("props/transformer", Vector3(60.0, 0.0, 20.0), PI * 0.5, {"snow": 0.4, "collide": Vector3(2.4, 3.0, 3.4), "range": 150.0})
	isf("diesel_gen", Vector3(58.0, 0.0, 32.0), PI * 0.5, {"scale": 1.7, "collide": Vector3(1.8, 2.0, 3.0), "snow": 0.5, "range": 140.0})
	isf("control_cabinet", Vector3(56.5, 0.0, 26.0), PI * 0.5, {"snow": 0.4, "collide": Vector3(0.8, 1.9, 1.2), "range": 120.0})
	for i in 2:
		sp("industrial_sf/chainlink", Vector3(53.0, 0.0, 24.0 + i * 10.8), PI * 0.5, {"snow": 0.5, "range": 120.0})

# ================================================================== booth
static func booth(bx: float, bz: float) -> void:
	# the security booth model (door on its back): rotated so the door faces the road (west)
	isf("guard_booth", Vector3(bx, 0.0, bz), PI * 0.5, {"scale": 1.12, "snow": 0.35, "range": 160.0})
	# perimeter collision around the glb (door gap 1.4 m centred on the road side)
	solid(Vector3(bx + 1.6, 1.35, bz), Vector3(0.2, 2.7, 3.6))
	solid(Vector3(bx, 1.35, bz - 1.8), Vector3(3.4, 2.7, 0.2))
	solid(Vector3(bx, 1.35, bz + 1.8), Vector3(3.4, 2.7, 0.2))
	solid(Vector3(bx - 1.6, 1.35, bz - 1.25), Vector3(0.2, 2.7, 1.0))
	solid(Vector3(bx - 1.6, 1.35, bz + 1.25), Vector3(0.2, 2.7, 1.0))
	omni(Vector3(bx, 2.5, bz), Color(1.0, 0.76, 0.5), 1.8, 7.5, true)

# ================================================================== rack row helper (called from l4_meridian)
static func rack(pos: Vector3, yaw: float) -> void:
	var r := sp("industrial_sf/rack_sf", pos, yaw, {"fit_box": Vector3(0.72, 2.25, 0.88), "shadow": false, "range": 60.0})
	if r != null:
		solid(pos + Vector3(0, 1.15, 0), Vector3(0.8, 2.3, 1.0), yaw)

# ================================================================== lobby
static func _lobby() -> void:
	# optical turnstile banks either side of the 2.6 m central lane
	for sx in [-3.45, 3.45]:
		isf("turnstile", Vector3(sx, 0.0, -3.5), PI * 0.5 if sx < 0 else -PI * 0.5, {"collide": Vector3(1.9, 1.1, 1.1), "range": 60.0})
	# visitor lounge: real sofa pair + water cooler by the reception
	isf("water_cooler", Vector3(-7.2, 0.0, 3.0), PI * 0.5, {"collide": Vector3(0.4, 1.4, 0.4)})

static func lobby_wall() -> void:
	for i in 3:
		var p := Vector3(-3.0 + i * 3.0, 1.55, -5.84)
		isf("wall_tv", p, 0.0, {"scale": Vector3(1.75, 1.75, 1.75), "mats": {"TVS0001_Screen": screen_mat(Color(0.12, 0.45, 0.9), 1.5, float(i) * 2.3, 2)}, "shadow": false})

# ================================================================== NOC
static func _noc() -> void:
	var cols := [Color(0.1, 0.4, 0.9), Color(0.05, 0.7, 0.55), Color(0.2, 0.35, 0.95), Color(0.95, 0.5, 0.1), Color(0.1, 0.55, 0.85)]
	# 2 x 5 video wall of real wall TVs (replaces the emissive slabs)
	var k := 0
	for r in 2:
		for c in 5:
			var col: Color = cols[(r * 2 + c) % cols.size()]
			var p := Vector3(-6.0 + (c - 2) * 2.85, 0.62 + r * 1.75, -83.83)
			isf("wall_tv", p, 0.0, {"scale": Vector3(1.62, 1.62, 1.62), "mats": {"TVS0001_Screen": screen_mat(col, 1.5, float(k) * 3.1, (k * 7) % 3)}, "shadow": false, "range": 60.0})
			k += 1
	# consoles: bank of desks (monitors x2, keyboard strip, chair, mug) replaces box monitors
	var mi := 0
	for r in 2:
		for c in 3:
			var x := -10.0 + c * 3.8
			var z := -76.0 + r * 2.5
			var col2: Color = cols[(r * 3 + c) % cols.size()]
			for s in [-1, 1]:
				monitor(Vector3(x + s * 0.5, 0.79, z - 0.12), PI + s * 0.18, col2.lerp(cols[(mi + 1) % cols.size()], 0.4 if s > 0 else 0.0), float(mi) * 1.7 + s, (mi + s + 5) % 3)
			box(Vector3(x, 0.8, z + 0.25), Vector3(0.5, 0.025, 0.17), Mats.color(Color(0.04, 0.04, 0.045), 0.5))
			isf("office_chair", Vector3(x + rf(-0.35, 0.35), 0.0, z + rf(0.85, 1.25)), PI + rf(-1.2, 1.2), {"rot": Vector3(1.25, 0, 0) if mi % 3 == 0 else Vector3.ZERO})
			mi += 1
	# wall-mounted status screens either side of the door and a row of lockers
	for sx in [-13.8, 1.8]:
		isf("wall_tv", Vector3(sx, 1.2, -68.0), PI * 0.5 if sx < 0 else -PI * 0.5, {"scale": Vector3(0.9, 0.9, 0.9), "mats": {"TVS0001_Screen": screen_mat(Color(0.9, 0.5, 0.1), 1.3, sx, 1)}, "shadow": false})
	# cable runs along the video wall: pipe-like conduits
	pipe(Vector3(-13.9, 0.15, -83.5), Vector3(1.9, 0.15, -83.5), 0.05, Color(0.1, 0.1, 0.12))
	omni(Vector3(-6.0, 2.0, -82.6), Color(0.3, 0.6, 1.0), 1.2, 9.0)

# ================================================================== break room
static func _break_room() -> void:
	# vending machines (real), water cooler, lockers, bin, microwave counter
	isf("vending", Vector3(-29.2, 0, -77.5), PI * 0.5, {"collide": Vector3(0.8, 1.9, 1.05), "snow": 0.0, "emissive": {}})
	isf("vending", Vector3(-29.2, 0, -76.0), PI * 0.5, {"collide": Vector3(0.8, 1.9, 1.05)})
	isf("water_cooler", Vector3(-29.3, 0, -73.8), PI * 0.5, {"collide": Vector3(0.4, 1.4, 0.4)})
	isf("lockers", Vector3(-19.0, 0, -79.5), 0.0, {"collide": Vector3(2.2, 2.0, 0.5)})
	omni(Vector3(-28.0, 1.9, -76.7), Color(0.9, 0.2, 0.2), 0.7, 3.5)
	omni(Vector3(-27.9, 1.0, -76.7), Color(0.4, 0.8, 1.0), 0.5, 3.0)

# ================================================================== cooling plant
static func _plant_extras() -> void:
	# chillers: air-handling packages over the old tank silhouettes (concrete pads stay in the level)
	for x in [22.5, 31.5, 40.5]:
		isf("hvac_unit", Vector3(x, 0.4, -41.8), PI * 0.5 + 0.0, {"scale": Vector3(2.4, 2.3, 2.0), "snow": 0.0, "range": 90.0})
		# frosted pipework bridging the chiller to the header
		pipe(Vector3(x - 1.0, 3.2, -43.0), Vector3(x - 1.0, 3.9, -38.2), 0.16, Color(0.75, 0.8, 0.85), true)
		isf("valve_wheel", Vector3(x - 1.0, 3.55, -42.0), 0.0, {"scale": 1.0, "snow": 0.0})
	# heat exchangers as real tanks
	for x in [21.0, 29.0]:
		for s in [-1, 1]:
			isf("storage_tank", Vector3(x + s * 1.3, 0.0, -56.0), rf(0, 6), {"scale": 0.82, "snow": 0.0, "collide": "none"})
	# manifold + valves on the north wall
	isf("pipe_manifold", Vector3(26.0, 0.9, -59.6), PI, {"scale": 1.4, "snow": 0.0, "range": 80.0})
	isf("pipe_manifold", Vector3(44.0, 0.9, -59.6), PI, {"scale": 1.0, "snow": 0.0, "range": 80.0})
	# override cabinet: real cabinet over the red slab
	isf("control_cabinet", Vector3(36.4, 0.0, -59.5), PI, {"snow": 0.0, "tint": Color(1.0, 0.55, 0.5)})
	isf("control_cabinet", Vector3(39.6, 0.0, -59.5), PI, {"snow": 0.0})
	omni(Vector3(38.0, 2.2, -58.4), Color(1.0, 0.2, 0.15), 0.8, 4.5)
	# diesel pumps / welder / barrels in the corners
	isf("welder", Vector3(48.4, 0.0, -41.0), PI * 0.5 + 0.4, {"collide": Vector3(1.0, 0.9, 1.7), "snow": 0.0})
	isf("pallets", Vector3(18.8, 0.0, -43.5), 0.2, {"scale": 0.8, "snow": 0.0})
	isf("exhaust_fan", Vector3(48.7, 3.0, -48.0), -PI * 0.5, {"scale": 1.6, "snow": 0.0, "rot": Vector3(0, 0, 0)})

# ================================================================== electrical room
static func _electrical_extras() -> void:
	# real cabinets down the east wall of the room and breaker boxes either side of the switchboard
	for i in 3:
		isf("control_cabinet", Vector3(-29.1, 0, -27.5 + i * 4.0), PI * 0.5, {"collide": Vector3(0.7, 1.9, 1.0), "snow": 0.0})
	for bx in [-29.0, -17.0]:
		isf("breaker_box", Vector3(bx, 1.0, -31.6), 0.0, {"scale": 1.1, "snow": 0.0})
	pipe(Vector3(-29.8, 3.4, -31.6), Vector3(-16.4, 3.4, -31.6), 0.07, Color(0.3, 0.32, 0.35))
	isf("lockers", Vector3(-26.0, 0, -12.6), PI, {"collide": Vector3(2.2, 2.0, 0.5)})
	isf("diesel_gen", Vector3(-24.0, 0.0, -15.0), PI, {"scale": 1.35, "collide": Vector3(2.5, 1.9, 1.3), "snow": 0.0})

# ================================================================== pipeline head
static func _pipeline_extras() -> void:
	# service pipework along the west wall of the pipeline hall + valve stations on the return line
	isf("pipe_manifold", Vector3(7.5, 0.5, -84.0), PI * 0.5, {"scale": 1.2, "snow": 0.0, "range": 90.0})
	isf("pipe_pack", Vector3(7.4, 3.2, -92.0), PI * 0.5, {"scale": 1.6, "snow": 0.0, "range": 90.0})
	isf("valve_wheel", Vector3(25.0, 1.1, -89.0), 0.0, {"scale": 1.6, "snow": 0.0})
	isf("valve_wheel", Vector3(27.0, 1.4, -94.0), 1.0, {"scale": 1.3, "snow": 0.0})
	isf("warehouse_shelf", Vector3(28.8, 0.0, -76.0), -PI * 0.5, {"collide": Vector3(0.7, 2.5, 3.0), "snow": 0.0})
	isf("forklift", Vector3(9.0, 0.0, -94.5), 0.3, {"collide": Vector3(1.2, 2.0, 3.0), "snow": 0.0})
	isf("storage_tank", Vector3(28.8, 0.0, -83.0), 0.0, {"scale": 0.7, "collide": "cyl", "snow": 0.0})

# ================================================================== halls
static func _halls_extras() -> void:
	# spares cage in a Hall A corner: warehouse shelf with boxes, a pallet jack's worth of clutter
	isf("warehouse_shelf", Vector3(-14.4, 0.0, -9.5), PI * 0.5, {"collide": Vector3(0.7, 2.5, 3.0)})
	isf("pallets", Vector3(-14.0, 0.0, -13.5), 0.4, {"scale": 0.7})
	isf("exhaust_fan", Vector3(0.0, 3.2, -35.7), 0.0, {"scale": 1.2, "range": 50.0})
	isf("water_cooler", Vector3(14.9, 0, -6.8), -PI * 0.5, {"collide": Vector3(0.4, 1.4, 0.4)})

## Practical atmosphere: steam off the rooftop plant (visible from the yard), leaking plant pipework, drips.
static func _steam() -> void:
	for p in [Vector3(-21.0, 11.6, 8.4), Vector3(4.6, 11.6, 8.4), Vector3(30.0, 11.6, 8.4)]:
		Gore.steam_vent(host, p, Vector3(0.3, 1, 0.5), 1.6, 0.2)
	for p in [Vector3(25.0, 3.9, -38.2), Vector3(44.0, 3.9, -38.2)]:
		Gore.steam_vent(host, p, Vector3(0, 0.6, 1), 0.8, 0.14)
		Gore.drip_emitter(host, p + Vector3(0.5, -0.1, 0.3), "water", 1.5)
	Gore.steam_vent(host, Vector3(18.0, 7.4, -88.0), Vector3.UP, 1.2, 0.16)
	Gore.drip_emitter(host, Vector3(22.0, 7.6, -92.0), "water", 1.1)
	Gore.steam_vent(host, Vector3(-17.0, 0.4, 14.5), Vector3.UP, 0.9, 0.14)      # condenser pad
