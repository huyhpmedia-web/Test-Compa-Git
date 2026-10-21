extends Node3D
## Base class for all levels. A level is a script in res://levels/<id>.gd that
## `extends "res://levels/level.gd"` and overrides:
##   build()            -> create environment, geometry, props, items, enemies, spawns
##   on_enter()         -> called after the player is placed (music, intro dialogue...)
##   try_use_item(id)   -> optional: return true if a key item was used from the inventory
##
## All static geometry made with the helpers lands under `geo` (a NavigationRegion3D)
## and the navigation mesh is baked automatically after build().

const Mats = preload("res://core/mats.gd")
const Props = preload("res://world/props.gd")
const FX = preload("res://world/fx.gd")
const Interactable = preload("res://world/interactable.gd")
const Trigger = preload("res://world/trigger.gd")
const PlayerScript = preload("res://actors/player.gd")

var footstep := "concrete"         # step_<footstep> sound
var spawns := {}                   # name -> [pos, yaw]
var geo: NavigationRegion3D
var env: WorldEnvironment
var sun: DirectionalLight3D
var player: CharacterBody3D
var _snow: GPUParticles3D
var _flicker: Array = []
var _t := 0.0

func _ready() -> void:
	geo = NavigationRegion3D.new()
	geo.name = "Geo"
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.4
	nm.agent_height = 1.7
	nm.agent_max_climb = 0.3
	nm.agent_max_slope = 40.0
	nm.cell_size = 0.2
	nm.cell_height = 0.1
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	geo.navigation_mesh = nm
	add_child(geo)
	build()
	_bake_nav()
	_spawn_player()
	on_enter()

func build() -> void:
	pass

func on_enter() -> void:
	pass

func try_use_item(_id: String) -> bool:
	UI.toast("There is nothing to use it on here.")
	return false

func _process(delta: float) -> void:
	_t += delta
	if _snow != null and player != null:
		_snow.global_position = player.global_position + Vector3(0, 9, 0)
	for f in _flicker:
		var l: Light3D = f[0]
		if is_instance_valid(l):
			var n := sin(_t * 23.0 + f[2]) * sin(_t * 7.3 + f[2] * 2.0)
			l.light_energy = f[1] * (0.15 if n > 0.75 else (0.85 + 0.15 * sin(_t * 50.0)))

func _bake_nav() -> void:
	geo.bake_navigation_mesh(false)

func _spawn_player() -> void:
	player = PlayerScript.new()
	player.name = "Player"
	add_child(player)
	Game.player = player
	var s: Array = spawns.get(Game.spawn_id, spawns.get("start", [Vector3.ZERO, 0.0]))
	player.place(s[0], s[1])
	UI.checkpoint_now()

# =================================================================== environment
## Snowy night exterior (matches the art direction reference).
func env_exterior_night(snow := true, fog_density := 0.025, moon_energy := 0.35) -> void:
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.05, 0.06, 0.1)
	sm.sky_horizon_color = Color(0.2, 0.22, 0.28)
	sm.ground_bottom_color = Color(0.03, 0.03, 0.04)
	sm.ground_horizon_color = Color(0.18, 0.2, 0.25)
	sm.sky_cover = load("res://textures/clouds_sky.png") if ResourceLoader.exists("res://textures/clouds_sky.png") else null
	sm.sky_cover_modulate = Color(0.5, 0.55, 0.65)
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.55
	e.ambient_light_sky_contribution = 0.85
	_common_post(e)
	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = fog_density
	e.volumetric_fog_albedo = Color(0.7, 0.75, 0.85)
	e.volumetric_fog_emission = Color(0.02, 0.025, 0.04)
	e.volumetric_fog_length = 64.0
	e.fog_enabled = true
	e.fog_light_color = Color(0.12, 0.13, 0.17)
	e.fog_density = 0.012
	e.fog_sky_affect = 0.25
	_set_env(e)
	sun = DirectionalLight3D.new()
	sun.name = "Moon"
	sun.light_color = Color(0.62, 0.7, 0.95)
	sun.light_energy = moon_energy
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	sun.rotation_degrees = Vector3(-38, 35, 0)
	sun.light_volumetric_fog_energy = 0.6
	add_child(sun)
	footstep = "snow"
	if snow:
		snowfall()
	Sfx.ambience("amb_wind")

## Dark interior. ambient: base ambient light (0.05 very dark .. 0.4 lit).
func env_interior(ambient := 0.12, fog_density := 0.015, tint := Color(0.55, 0.6, 0.7)) -> void:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.0, 0.0, 0.0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = tint
	e.ambient_light_energy = ambient
	_common_post(e)
	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = fog_density
	e.volumetric_fog_albedo = Color(0.8, 0.8, 0.8)
	e.volumetric_fog_length = 40.0
	_set_env(e)
	footstep = "concrete"
	Sfx.ambience("amb_interior")

func _common_post(e: Environment) -> void:
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.1
	e.tonemap_white = 6.0
	e.ssao_enabled = true
	e.ssao_radius = 1.2
	e.ssao_intensity = 2.2
	e.ssil_enabled = false
	e.ssr_enabled = true
	e.ssr_max_steps = 48
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_bloom = 0.08
	e.glow_hdr_threshold = 1.1
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.08
	e.adjustment_saturation = 0.82
	e.adjustment_brightness = 1.0

func _set_env(e: Environment) -> void:
	if env != null:
		env.queue_free()
	env = WorldEnvironment.new()
	env.environment = e
	add_child(env)

func snowfall(amount := 2500) -> void:
	_snow = GPUParticles3D.new()
	_snow.amount = amount
	_snow.lifetime = 6.0
	_snow.preprocess = 6.0
	_snow.visibility_aabb = AABB(Vector3(-20, -15, -20), Vector3(40, 20, 40))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(18, 1, 18)
	pm.direction = Vector3(0.2, -1, 0.1)
	pm.spread = 15.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0.4, -0.6, 0.2)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 4.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	_snow.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.03, 0.03)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(0.9, 0.92, 1.0, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.material = m
	_snow.draw_pass_1 = qm
	add_child(_snow)

# =================================================================== geometry
## Solid box. pos = centre of the box.
func box(pos: Vector3, size: Vector3, mat: Variant = "concrete", solid := true, rot_y := 0.0) -> MeshInstance3D:
	var m: Material = Mats.get_mat(mat) if mat is String else mat
	var mi := Props.box(geo, size, pos, m, solid, Vector3(0, rot_y, 0))
	return mi

## Floor slab with top surface at height y.
func floor_rect(x0: float, z0: float, x1: float, z1: float, y := 0.0, mat: Variant = "concrete", thick := 0.3) -> MeshInstance3D:
	return box(Vector3((x0 + x1) * 0.5, y - thick * 0.5, (z0 + z1) * 0.5), Vector3(abs(x1 - x0), thick, abs(z1 - z0)), mat)

## Ceiling slab with bottom surface at height y.
func ceiling_rect(x0: float, z0: float, x1: float, z1: float, y := 3.2, mat: Variant = "plaster", thick := 0.25) -> MeshInstance3D:
	return box(Vector3((x0 + x1) * 0.5, y + thick * 0.5, (z0 + z1) * 0.5), Vector3(abs(x1 - x0), thick, abs(z1 - z0)), mat)

## Wall along a straight line from a to b (x,z). gaps = [[dist_from_a, width, height], ...]
## for doorways/windows (height = gap top; bottom is at floor unless gap has 4th elem sill).
func wall(a: Vector2, b: Vector2, h := 3.2, mat: Variant = "plaster", y0 := 0.0, thick := 0.25, gaps: Array = []) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return
	var dir := d / len
	var yaw := atan2(dir.x, dir.y)
	var sorted := gaps.duplicate()
	sorted.sort_custom(func(p, q): return p[0] < q[0])
	var cur := 0.0
	for g in sorted:
		var g0: float = g[0] - g[1] * 0.5
		var g1: float = g[0] + g[1] * 0.5
		var gh: float = g[2]
		var sill: float = g[3] if g.size() > 3 else 0.0
		if g0 > cur:
			_wall_seg(a, dir, cur, g0, y0, h, thick, mat, yaw)
		if gh < h:
			_wall_seg(a, dir, g0, g1, y0 + gh, h - gh, thick, mat, yaw)
		if sill > 0.0:
			_wall_seg(a, dir, g0, g1, y0, sill, thick, mat, yaw)
		cur = g1
	if cur < len:
		_wall_seg(a, dir, cur, len, y0, h, thick, mat, yaw)

func _wall_seg(a: Vector2, dir: Vector2, t0: float, t1: float, y: float, h: float, thick: float, mat: Variant, yaw: float) -> void:
	var mid := a + dir * (t0 + t1) * 0.5
	box(Vector3(mid.x, y + h * 0.5, mid.y), Vector3(thick, h, t1 - t0), mat, true, yaw)

## Rectangular room: floor, ceiling (unless ceil_mat == ""), 4 walls.
## doors: {"n": [[dist, width, height], ...], "s": [...], "e": [...], "w": [...]}
## n = wall at z0 (running +x), s = z1, w = x0 (running +z), e = x1. dist measured from the low x/z corner.
func room(x0: float, z0: float, x1: float, z1: float, h := 3.2, floor_mat: Variant = "tile_floor", wall_mat: Variant = "plaster", ceil_mat: Variant = "plaster", doors := {}, y := 0.0) -> void:
	floor_rect(x0, z0, x1, z1, y, floor_mat)
	if ceil_mat is Material or (ceil_mat is String and ceil_mat != ""):
		ceiling_rect(x0, z0, x1, z1, y + h, ceil_mat)
	var t := 0.25
	wall(Vector2(x0, z0), Vector2(x1, z0), h, wall_mat, y, t, doors.get("n", []))
	wall(Vector2(x0, z1), Vector2(x1, z1), h, wall_mat, y, t, doors.get("s", []))
	wall(Vector2(x0, z0), Vector2(x0, z1), h, wall_mat, y, t, doors.get("w", []))
	wall(Vector2(x1, z0), Vector2(x1, z1), h, wall_mat, y, t, doors.get("e", []))

func cyl(pos: Vector3, r: float, h: float, mat: Variant = "concrete", solid := true) -> MeshInstance3D:
	var m: Material = Mats.get_mat(mat) if mat is String else mat
	return Props.cyl(geo, r, h, pos, m, solid)

## Ramp / stairs as a sloped solid from (x,z) at y0 to y1 along `dir` ("+z","-z","+x","-x").
func stairs(pos: Vector3, width: float, length: float, rise: float, dir := "+z", mat: Variant = "concrete") -> void:
	var steps := int(max(2, round(rise / 0.18)))
	var sl := length / steps
	var sh := rise / steps
	for i in steps:
		var off := sl * (i + 0.5)
		var p := pos
		var size := Vector3(width, sh * (i + 1), sl)
		match dir:
			"+z": p += Vector3(0, 0, off)
			"-z": p += Vector3(0, 0, -off)
			"+x":
				p += Vector3(off, 0, 0)
				size = Vector3(sl, sh * (i + 1), width)
			"-x":
				p += Vector3(-off, 0, 0)
				size = Vector3(sl, sh * (i + 1), width)
		p.y = pos.y + size.y * 0.5
		box(p, size, mat, false)
	# smooth invisible ramp collider for walking
	var ramp := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh2 := BoxShape3D.new()
	var slope_len := sqrt(length * length + rise * rise)
	sh2.size = Vector3(width, 0.1, slope_len)
	cs.shape = sh2
	ramp.add_child(cs)
	geo.add_child(ramp)
	var ang := atan2(rise, length)
	var center := pos + Vector3(0, rise * 0.5, 0)
	var yaw: float = {"+z": 0.0, "-z": PI, "+x": PI * 0.5, "-x": -PI * 0.5}[dir]
	center += Basis(Vector3.UP, yaw) * Vector3(0, 0, length * 0.5)
	ramp.position = center
	ramp.rotation = Vector3(-ang, yaw, 0)

# =================================================================== lights
func light(pos: Vector3, color := Color(1.0, 0.85, 0.65), energy := 2.0, rng := 8.0, shadows := true, flicker := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.4
	l.shadow_enabled = shadows
	l.light_volumetric_fog_energy = 1.0
	l.position = pos
	add_child(l)
	if flicker:
		_flicker.append([l, energy, randf() * 10.0])
	return l

func spot(pos: Vector3, target: Vector3, color := Color(1, 0.9, 0.75), energy := 4.0, rng := 12.0, angle := 35.0, shadows := true) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.spot_range = rng
	l.spot_angle = angle
	l.shadow_enabled = shadows
	l.light_volumetric_fog_energy = 1.5
	add_child(l)
	l.position = pos
	l.look_at_from_position(pos, target, Vector3.UP if abs((target - pos).normalized().y) < 0.99 else Vector3.FORWARD)
	return l

## Ceiling fixture (fluorescent tube or bulb) + light. y = ceiling height.
func ceiling_lamp(pos: Vector3, kind := "fluor", on := true, flicker := false, color := Color(0.85, 0.92, 1.0), energy := 2.2) -> void:
	var m: Material = Mats.emissive(color, 3.0) if on else Mats.color(Color(0.6, 0.6, 0.6), 0.4)
	if kind == "fluor":
		Props.box(geo, Vector3(0.25, 0.06, 1.3), pos + Vector3(0, -0.05, 0), Mats.get_mat("metal"), false)
		Props.box(geo, Vector3(0.18, 0.03, 1.2), pos + Vector3(0, -0.09, 0), m, false)
	else:
		Props.cyl(geo, 0.02, 0.5, pos + Vector3(0, -0.25, 0), Mats.get_mat("metal"), false)
		Props.sphere(geo, 0.1, pos + Vector3(0, -0.55, 0), m)
		color = Color(1.0, 0.78, 0.5)
	if on:
		light(pos + Vector3(0, -0.4, 0), color, energy, 9.0, true, flicker)

# =================================================================== gameplay objects
func add_spawn(name: String, pos: Vector3, yaw := 0.0) -> void:
	spawns[name] = [pos, yaw]

func interact(pos: Vector3, prompt: String, action: Callable, radius := 1.6) -> Node3D:
	var it := Interactable.new()
	it.prompt = prompt
	it.action = action
	it.radius = radius
	it.position = pos
	add_child(it)
	return it

func trigger(uid: String, pos: Vector3, size: Vector3, action: Callable, once := true) -> Area3D:
	if once and uid != "" and Game.has_flag("trig:" + uid):
		return null
	var t := Trigger.new()
	t.uid = uid
	t.once = once
	t.action = action
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	t.add_child(cs)
	t.position = pos
	add_child(t)
	return t

## Item pickup. uid must be unique within the game (prefix with the level id).
func pickup(uid: String, item: String, count: int, pos: Vector3) -> Node3D:
	if Game.has_flag("got:" + uid):
		return null
	var d := Game.item_def(item)
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var vis := FX.weapon_mesh(item) if d.kind == "weapon" else _item_mesh(item, d)
	if d.kind == "weapon":
		vis.rotation = Vector3(PI * 0.5, randf() * TAU, 0)
		vis.position.y = 0.04
	root.add_child(vis)
	var glint := OmniLight3D.new()
	glint.light_color = Color(1.0, 0.95, 0.8)
	glint.light_energy = 0.35
	glint.omni_range = 1.2
	glint.shadow_enabled = false
	glint.position.y = 0.3
	root.add_child(glint)
	var it := Interactable.new()
	it.prompt = "Pick up " + d.name
	it.radius = 1.5
	root.add_child(it)
	it.action = func(_p):
		var left := Game.add_item(item, count)
		if left == count:
			UI.toast("Your inventory is full.")
			Sfx.play("deny")
			return
		Sfx.play("pickup")
		if left > 0:
			UI.toast("Picked up %s (%d). %d left behind." % [d.name, count - left, left])
			count = left
			return
		Game.set_flag("got:" + uid)
		if d.kind == "key" or d.kind == "weapon" or d.kind == "upgrade":
			UI.show_item_get(item)
		else:
			UI.toast("Picked up %s%s." % [d.name, (" x%d" % count) if count > 1 else ""])
		root.queue_free()
		on_pickup(item, uid)
	return root

## Override to react to pickups (e.g. scripted scares).
func on_pickup(_item: String, _uid: String) -> void:
	pass

func _item_mesh(item: String, d: Dictionary) -> Node3D:
	var r := Node3D.new()
	var c: Color = d.get("color", Color.WHITE)
	match d.kind:
		"ammo":
			Props.box(r, Vector3(0.14, 0.08, 0.1), Vector3(0, 0.04, 0), Mats.color(c.darkened(0.3), 0.6), false)
			Props.box(r, Vector3(0.145, 0.02, 0.105), Vector3(0, 0.075, 0), Mats.color(Color(0.1, 0.1, 0.1), 0.6), false)
		"heal":
			if item == "spray":
				Props.cyl(r, 0.035, 0.2, Vector3(0, 0.1, 0), Mats.color(Color(0.9, 0.9, 0.92), 0.3, 0.4), false)
				Props.cyl(r, 0.02, 0.03, Vector3(0, 0.215, 0), Mats.color(Color(0.1, 0.5, 0.2), 0.4), false)
			else:
				Props.box(r, Vector3(0.1, 0.12, 0.05), Vector3(0, 0.06, 0), Mats.color(c, 0.5), false)
				Props.box(r, Vector3(0.06, 0.02, 0.052), Vector3(0, 0.07, 0), Mats.color(Color(0.95, 0.95, 0.95), 0.5), false)
		"resource":
			Props.cyl(r, 0.04, 0.1, Vector3(0, 0.05, 0), Mats.color(c, 0.5), false)
		_:
			Props.box(r, Vector3(0.14, 0.04, 0.1), Vector3(0, 0.02, 0), Mats.color(c, 0.4, 0.5), false)
	return r

## Door. opts:
##  to_level / to_spawn : RE-style transition door (loads another level)
##  lock_item           : key item required (consumed unless keep_key)
##  lock_flag           : flag that must be set (e.g. power restored); locked_msg shown otherwise
##  one_way_msg         : door can't be opened from this side (message)
##  width, height, mat ("wood"/"metal"/...), double (bool), prompt
## Without to_level the door swings open locally and stays open (persisted).
func door(uid: String, pos: Vector3, yaw: float, opts := {}) -> Node3D:
	var w: float = opts.get("width", 1.1)
	var h: float = opts.get("height", 2.2)
	var dbl: bool = opts.get("double", false)
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	add_child(root)
	var mat: Material = Mats.get_mat(opts.get("mat", "wood"), 1.0)
	var frame_m := Mats.color(Color(0.2, 0.15, 0.1), 0.6)
	var leaves: Array = []
	var nleaf := 2 if dbl else 1
	var lw := w / nleaf
	for i in nleaf:
		var hinge := Node3D.new()
		var side := -1.0 if i == 0 else 1.0
		hinge.position = Vector3(side * w * 0.5, 0, 0)
		root.add_child(hinge)
		var leaf := Props.box(hinge, Vector3(lw, h, 0.06), Vector3(-side * lw * 0.5, h * 0.5, 0), mat, true)
		# panel detail + handle
		for k in 2:
			Props.box(leaf, Vector3(lw * 0.6, h * 0.3, 0.02), Vector3(0, -h * 0.2 + k * h * 0.42, 0.035), mat, false)
			Props.box(leaf, Vector3(lw * 0.6, h * 0.3, 0.02), Vector3(0, -h * 0.2 + k * h * 0.42, -0.035), mat, false)
		Props.sphere(leaf, 0.03, Vector3(-side * (lw * 0.5 - 0.1), 0.0, 0.06), Mats.get_mat("metal"))
		leaves.append(hinge)
	# frame
	Props.box(root, Vector3(0.08, h + 0.08, 0.16), Vector3(-w * 0.5 - 0.04, h * 0.5, 0), frame_m, false)
	Props.box(root, Vector3(0.08, h + 0.08, 0.16), Vector3(w * 0.5 + 0.04, h * 0.5, 0), frame_m, false)
	Props.box(root, Vector3(w + 0.16, 0.08, 0.16), Vector3(0, h + 0.04, 0), frame_m, false)
	if opts.has("label"):
		Props.sign(root, Vector3(0, h + 0.25, 0.1), 0.0, opts.label, 40)
		Props.sign(root, Vector3(0, h + 0.25, -0.1), PI, opts.label, 40)

	var open_local := func():
		for i in leaves.size():
			var hg: Node3D = leaves[i]
			var tw := hg.create_tween()
			tw.tween_property(hg, "rotation:y", (-1.0 if i == 0 else 1.0) * -1.6, 0.6).set_trans(Tween.TRANS_SINE)
			for sb in hg.find_children("*", "StaticBody3D", true, false):
				sb.collision_layer = 0
	if Game.has_flag("open:" + uid) and not opts.has("to_level"):
		for i in leaves.size():
			leaves[i].rotation.y = (-1.0 if i == 0 else 1.0) * -1.6
			for sb in leaves[i].find_children("*", "StaticBody3D", true, false):
				sb.collision_layer = 0
		return root

	var it := Interactable.new()
	it.prompt = opts.get("prompt", "Open door")
	it.radius = 1.8
	it.position = Vector3(0, 1.0, 0)
	root.add_child(it)
	it.action = func(_p):
		if opts.has("one_way_msg") and not Game.has_flag("unlocked:" + uid):
			# One-way doors can only be unlocked from the side that sets the flag.
			UI.toast(opts.one_way_msg)
			Sfx.play("door_locked")
			return
		if opts.has("lock_flag") and not Game.has_flag(opts.lock_flag):
			UI.toast(opts.get("locked_msg", "It won't open."))
			Sfx.play("door_locked")
			return
		if opts.has("lock_item") and not Game.has_flag("unlocked:" + uid):
			var key: String = opts.lock_item
			if Game.has_item(key):
				if not opts.get("keep_key", false):
					Game.remove_item(key, 1)
				Game.set_flag("unlocked:" + uid)
				Sfx.play("unlock")
				UI.toast("Used %s." % Game.item_def(key).name)
				await get_tree().create_timer(0.6).timeout
			else:
				UI.toast(opts.get("locked_msg", "It's locked. It needs %s." % Game.item_def(key).name))
				Sfx.play("door_locked")
				return
		if opts.has("to_level"):
			Sfx.play("door_open")
			Game.goto_level(opts.to_level, opts.get("to_spawn", "start"))
		else:
			Game.set_flag("open:" + uid)
			Sfx.play_at("door_open", root.global_position)
			open_local.call()
			it.enabled = false
	return root

## Readable document. Collected into the Files list in the inventory.
func note(uid: String, pos: Vector3, title: String, body: String, yaw := 0.0) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	add_child(root)
	Props.box(root, Vector3(0.22, 0.004, 0.3), Vector3(0, 0.003, 0), Mats.get_mat("paper"), false, Vector3(0, 0.2, 0))
	Props.box(root, Vector3(0.22, 0.004, 0.3), Vector3(0.03, 0.007, 0.02), Mats.get_mat("paper"), false, Vector3(0, -0.1, 0))
	var it := Interactable.new()
	it.prompt = "Read: " + title
	it.radius = 1.5
	root.add_child(it)
	it.action = func(_p):
		var files: Array = Game.get_flag("files", [])
		if not files.has(uid):
			files.append(uid)
			Game.set_flag("files", files)
			Game.set_flag("file:" + uid, {"title": title, "body": body})
		Sfx.play("paper")
		UI.show_note(title, body)
	return root

## Save point: a battery field recorder on a desk (unlimited saves) + green light.
func save_point(pos: Vector3, yaw := 0.0) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	add_child(root)
	Props.box(root, Vector3(0.36, 0.14, 0.24), Vector3(0, 0.07, 0), Mats.color(Color(0.12, 0.12, 0.12), 0.5, 0.4), false)
	Props.box(root, Vector3(0.12, 0.06, 0.01), Vector3(-0.08, 0.09, 0.121), Mats.emissive(Color(0.2, 1.0, 0.4), 2.0), false)
	Props.cyl(root, 0.006, 0.35, Vector3(0.14, 0.3, -0.08), Mats.get_mat("metal"), false)
	var l := OmniLight3D.new()
	l.light_color = Color(0.4, 1.0, 0.55)
	l.light_energy = 0.6
	l.omni_range = 2.5
	l.position = Vector3(0, 0.3, 0.2)
	root.add_child(l)
	var it := Interactable.new()
	it.prompt = "Use field recorder (Save)"
	root.add_child(it)
	it.action = func(_p): UI.open_save()
	return root

func item_box(pos: Vector3, yaw := 0.0) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	add_child(root)
	Props.box(root, Vector3(1.1, 0.6, 0.55), Vector3(0, 0.3, 0), Mats.get_mat("metal_painted", 0.8))
	Props.box(root, Vector3(1.12, 0.06, 0.57), Vector3(0, 0.6, 0), Mats.color(Color(0.15, 0.2, 0.18), 0.5, 0.5), false)
	Props.sign(root, Vector3(0, 0.35, 0.29), 0.0, "EMERGENCY SUPPLY", 28, Color(0.9, 0.8, 0.2), false)
	var it := Interactable.new()
	it.prompt = "Open supply box"
	root.add_child(it)
	it.action = func(_p): UI.open_item_box()
	return root

## Spawn an enemy from res://actors/enemies/<type>.gd. Skipped if already killed.
## params are assigned onto the enemy before it enters the tree.
func enemy(uid: String, type: String, pos: Vector3, yaw := 0.0, params := {}) -> Node3D:
	if uid != "" and Game.has_flag("dead:" + uid):
		return null
	var path := "res://actors/enemies/%s.gd" % type
	if not ResourceLoader.exists(path):
		push_warning("Missing enemy type " + type)
		return null
	var e: Node3D = load(path).new()
	e.set("uid", uid)
	for k in params:
		e.set(k, params[k])
	e.position = pos
	e.rotation.y = yaw
	add_child(e)
	return e

## Dialogue helper: await say([["MAYA", "text"], ["???", "text"]])
func say(lines: Array) -> void:
	await UI.dialogue(lines)

## Lock player input for a scripted moment.
func lock_player(on: bool) -> void:
	if player:
		player.input_locked = on
