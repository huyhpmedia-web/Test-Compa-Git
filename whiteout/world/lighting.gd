extends RefCounted
## R8-B lighting helpers: global illumination (SDFGI) setting, per-space colour grades,
## interior environments, reflection probes, wet-floor decals, light-shaft spots, and the
## shadow budget (cap on shadow-casting lights near the camera).
##
## Used by levels/level.gd (_common_post, make_interior_env, env zones) and the lighting
## sections of the level scripts.

const SETTINGS_PATH := "user://settings.cfg"

# =================================================================== GI setting
static var _gi_cached := -1

## Global illumination (SDFGI) on/off, persisted in user://settings.cfg [graphics] gi.
static func gi_enabled() -> bool:
	if _gi_cached < 0:
		var cfg := ConfigFile.new()
		var on := true
		if cfg.load(SETTINGS_PATH) == OK:
			on = bool(cfg.get_value("graphics", "gi", true))
		if OS.get_environment("WHITEOUT_GI") == "0":
			on = false
		_gi_cached = 1 if on else 0
	return _gi_cached == 1

static func set_gi_enabled(on: bool) -> void:
	_gi_cached = 1 if on else 0
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("graphics", "gi", on)
	cfg.save(SETTINGS_PATH)

## SDFGI with moderate settings. Cascade count / min cell / occlusion / y-scale are kept
## identical for every Environment so swapping exterior <-> interior environments does not
## rebuild the SDF cascades (only energy and sky reading differ).
static func apply_gi(e: Environment, exterior: bool) -> void:
	e.sdfgi_enabled = gi_enabled()
	e.sdfgi_cascades = 4
	e.sdfgi_min_cell_size = 0.2
	e.sdfgi_use_occlusion = true
	e.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	e.sdfgi_bounce_feedback = 0.45
	e.sdfgi_read_sky_light = exterior
	e.sdfgi_energy = 0.75 if exterior else 1.15
	e.sdfgi_normal_bias = 1.1
	e.sdfgi_probe_bias = 1.1
	# screen-space bounce stays on: it is the fallback when SDFGI is off and adds contact bounce when on
	e.ssil_enabled = true

# =================================================================== colour grades
## Per-space grades as per-channel curves (GradientTexture1D in adjustment_color_correction):
## [offset, Color] stops; each channel of the image is looked up in the same channel of the curve.
const GRADES := {
	# cold blue night exterior: blue-lifted blacks, neutral-cool mids, untouched highlights
	"cold": [[0.0, Color(0.0, 0.006, 0.02)], [0.22, Color(0.19, 0.215, 0.255)], [0.55, Color(0.535, 0.555, 0.585)], [1.0, Color(1.0, 1.0, 1.0)]],
	# sickly school: green-olive shadows, yellowed mids, slightly crushed
	"school": [[0.0, Color(0.004, 0.012, 0.004)], [0.22, Color(0.19, 0.215, 0.15)], [0.55, Color(0.57, 0.575, 0.47)], [1.0, Color(1.0, 0.98, 0.86)]],
	# sterile Meridian: cyan shadows, clean cool whites
	"meridian": [[0.0, Color(0.0, 0.012, 0.018)], [0.22, Color(0.17, 0.215, 0.235)], [0.55, Color(0.5, 0.56, 0.58)], [1.0, Color(0.94, 1.0, 1.0)]],
	# sodium mine: brown blacks, amber mids, warm highlights
	"mine": [[0.0, Color(0.014, 0.006, 0.0)], [0.22, Color(0.24, 0.19, 0.12)], [0.55, Color(0.62, 0.53, 0.4)], [1.0, Color(1.0, 0.93, 0.8)]],
	# the Heart: red-black, crushed shadows, bloodied mids
	"heart": [[0.0, Color(0.012, 0.0, 0.002)], [0.25, Color(0.23, 0.13, 0.13)], [0.6, Color(0.66, 0.53, 0.52)], [1.0, Color(1.0, 0.94, 0.92)]],
	# church nave: candle-warm mids, cold blue blacks (moonlight in the windows)
	"church": [[0.0, Color(0.0, 0.004, 0.016)], [0.22, Color(0.22, 0.2, 0.19)], [0.55, Color(0.6, 0.54, 0.47)], [1.0, Color(1.0, 0.96, 0.9)]],
}

## Which grade a level uses by default (exterior envs always use "cold").
const LEVEL_GRADE := {
	"l1_substation": "cold", "l2_school": "school", "l3_church": "church", "l4_meridian": "meridian",
	"l5_mine": "mine", "l6_heart": "heart",
}

static var _grade_cache := {}

static func grade_texture(grade: String) -> Texture2D:
	if not GRADES.has(grade):
		return null
	if _grade_cache.has(grade):
		return _grade_cache[grade]
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in GRADES[grade]:
		offs.append(s[0])
		cols.append(s[1])
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	t.use_hdr = false
	_grade_cache[grade] = t
	return t

static func apply_grade(e: Environment, grade: String) -> void:
	var t := grade_texture(grade)
	if t != null:
		e.adjustment_enabled = true
		e.adjustment_color_correction = t
	e.set_meta("grade", grade)

# =================================================================== reflection probes
## Box-projected, update-once interior reflection probe covering an axis-aligned room.
## centre = floor centre of the room, size = full room extents. ambient: the probe's own interior
## ambient (dark, tinted) so geometry inside the probe stops picking up exterior sky light.
static func probe(parent: Node3D, centre: Vector3, size: Vector3, ambient := Color(0.02, 0.022, 0.026), amb_energy := 0.35, intensity := 1.0) -> ReflectionProbe:
	var p := ReflectionProbe.new()
	p.name = "ReflProbe"
	p.size = size
	p.position = centre + Vector3(0, size.y * 0.5, 0)
	p.origin_offset = Vector3(0, -size.y * 0.5 + minf(1.6, size.y * 0.45), 0)   # capture from eye height
	p.box_projection = true
	p.interior = true
	p.update_mode = ReflectionProbe.UPDATE_ONCE
	p.intensity = intensity
	p.blend_distance = 0.6
	p.max_distance = maxf(size.x, size.z) * 1.2
	p.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	p.ambient_color = ambient
	p.ambient_color_energy = amb_energy
	p.enable_shadows = false
	p.mesh_lod_threshold = 4.0
	parent.add_child(p)
	return p

# =================================================================== wet / glossy floor patches
static var _wet_mat_tex := {}

## Decal that darkens and drops roughness on a patch of floor (melt water, mopped tile, brine).
static func wet_patch(parent: Node3D, pos: Vector3, sx: float, sz: float, yaw := 0.0, strength := 1.0) -> Decal:
	if not _wet_mat_tex.has("a"):
		_wet_mat_tex["a"] = load("res://textures/lighting/wet_albedo.png") if ResourceLoader.exists("res://textures/lighting/wet_albedo.png") else null
		_wet_mat_tex["o"] = load("res://textures/lighting/wet_orm.png") if ResourceLoader.exists("res://textures/lighting/wet_orm.png") else null
	if _wet_mat_tex["a"] == null:
		return null
	var d := Decal.new()
	d.name = "WetPatch"
	d.size = Vector3(sx, 0.5, sz)
	d.texture_albedo = _wet_mat_tex["a"]
	d.texture_orm = _wet_mat_tex["o"]
	d.albedo_mix = 0.6 * strength
	d.modulate = Color(1, 1, 1, clampf(strength, 0.0, 1.0))
	d.upper_fade = 0.4
	d.lower_fade = 0.4
	d.cull_mask = 1
	d.distance_fade_enabled = true
	d.distance_fade_begin = 30.0
	d.distance_fade_length = 8.0
	d.position = pos + Vector3(0, 0.05, 0)
	d.rotation.y = yaw
	parent.add_child(d)
	return d

## Lower the roughness of every material on a mesh (polished terrazzo, lacquered gym floor).
static func gloss(mi: MeshInstance3D, roughness := 0.22) -> void:
	if mi == null:
		return
	var m := mi.material_override
	if m == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
		m = mi.mesh.surface_get_material(0)
	if m is BaseMaterial3D:
		var c: BaseMaterial3D = m.duplicate()
		c.roughness = roughness
		if c.roughness_texture != null:
			c.roughness = roughness * 1.6
		mi.material_override = c

# =================================================================== hero light shafts
## A motivated light shaft: a narrow shadowed spot (moonlight through a window, a sodium lamp
## through grating) with a strong volumetric fog contribution. One or two per space, no more.
static func shaft(parent: Node3D, from: Vector3, to: Vector3, color := Color(0.6, 0.7, 0.95), energy := 3.0, angle := 18.0, fog := 6.0, shadows := true) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.name = "Shaft"
	l.light_color = color
	l.light_energy = energy
	l.spot_range = from.distance_to(to) * 1.4
	l.spot_angle = angle
	l.spot_angle_attenuation = 1.6
	l.spot_attenuation = 0.6
	l.shadow_enabled = shadows
	l.shadow_blur = 1.5
	l.light_volumetric_fog_energy = fog
	l.light_specular = 0.4
	parent.add_child(l)
	l.global_position = from
	var up := Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.FORWARD
	l.look_at(to, up)
	l.set_meta("hero", true)
	return l

# =================================================================== shadow budget
## Distance fade on every positional light + a cap of `cap` shadow-casting lights nearest to the
## camera (the rest keep their light but drop their shadow). `lights` = [[Light3D, wants_shadow]].
static func collect_lights(root: Node) -> Array:
	var out: Array = []
	for n in root.find_children("*", "Light3D", true, false):
		if n is DirectionalLight3D:
			continue
		var l: Light3D = n
		var rng: float = float(l.get("omni_range")) if l is OmniLight3D else (float(l.get("spot_range")) if l is SpotLight3D else 99.0)
		if rng < 16.0 and not l.distance_fade_enabled:
			# small practicals: fade out beyond 40 m, their shadows beyond 24 m (big street/flood lights are left alone)
			l.distance_fade_enabled = true
			l.distance_fade_begin = 40.0
			l.distance_fade_shadow = 24.0
			l.distance_fade_length = 10.0
		out.append([l, l.shadow_enabled])
	return out

static func enforce_shadow_cap(lights: Array, eye: Vector3, cap := 8) -> void:
	var cands: Array = []
	for e in lights:
		if not is_instance_valid(e[0]) or not e[1]:
			continue
		var l: Light3D = e[0]
		if not l.is_visible_in_tree():
			continue
		var d := l.global_position.distance_to(eye)
		if l.has_meta("hero"):
			d *= 0.5
		cands.append([d, l])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for i in cands.size():
		var l: Light3D = cands[i][1]
		var want: bool = i < cap
		if l.shadow_enabled != want:
			l.shadow_enabled = want
