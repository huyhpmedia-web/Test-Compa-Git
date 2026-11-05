extends RefCounted
## Real-looking fire: GPU-particle flame billboards (procedural noise-distorted teardrop sprite, additive),
## rising embers, soft smoke, and a flickering warm light.  Replaces the old stacks of emissive spheres.
##
##   var fire := FireFX.burn(parent, Vector3(x, y, z), 1.0, {light = true, shadows = false})
##
## `size` ~ 1.0 for a 55 gal barrel; 2-3 for a bonfire / burning car.  Returns the root Node3D (free it to put the fire out).

const SH_FLAME := "res://world/shaders/fire_flame.gdshader"
const SH_SMOKE := "res://world/shaders/fire_smoke.gdshader"
const SH_EMBER := "res://world/shaders/fire_ember.gdshader"

static var _quad: QuadMesh
static var _mats := {}

class Flicker extends OmniLight3D:
	var base := 4.5
	var ph := 0.0
	var amp := 0.35
	func _ready() -> void:
		ph = randf() * 100.0
	func _process(_d: float) -> void:
		var t := Time.get_ticks_msec() * 0.001 + ph
		var f := 1.0 + amp * (0.5 * sin(t * 13.0) + 0.3 * sin(t * 27.3 + 1.7) + 0.2 * sin(t * 5.1)) + (randf() - 0.5) * amp * 0.5
		light_energy = base * f
		position.x = sin(t * 7.0) * 0.04
		position.z = cos(t * 6.0) * 0.04

static func _q() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(1, 1)
	return _quad

static func _mat(path: String, params := {}) -> ShaderMaterial:
	var key := path + str(params)
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = load(path)
	for k in params:
		m.set_shader_parameter(k, params[k])
	_mats[key] = m
	return m

static func _curve(a: float, b: float, c: float) -> CurveTexture:
	var cv := Curve.new()
	cv.add_point(Vector2(0, a))
	cv.add_point(Vector2(0.35, b))
	cv.add_point(Vector2(1, c))
	var ct := CurveTexture.new()
	ct.curve = cv
	return ct

static func _particles(amount: int, life: float, mat: ShaderMaterial, pm: ParticleProcessMaterial, quad_scale: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.process_material = pm
	p.draw_pass_1 = _q()
	p.material_override = mat
	p.local_coords = false
	p.fixed_fps = 30
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-3, -1, -3) * quad_scale, Vector3(6, 8, 6) * quad_scale)
	p.visibility_range_end = 70.0
	return p

static func burn(parent: Node3D, pos: Vector3, size := 1.0, opts := {}) -> Node3D:
	var root := Node3D.new()
	root.name = String(opts.get("name", "Fire"))
	parent.add_child(root)
	root.position = pos
	# --- flames: two layers (big soft body + fast narrow tongues)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.14 * size
	pm.direction = Vector3.UP
	pm.spread = 9.0
	pm.initial_velocity_min = 0.7 * size
	pm.initial_velocity_max = 1.5 * size
	pm.gravity = Vector3(0, 0.5, 0)
	pm.damping_min = 0.2
	pm.damping_max = 0.6
	pm.scale_min = 0.8 * size
	pm.scale_max = 1.5 * size
	pm.scale_curve = _curve(0.75, 1.0, 0.35)
	pm.angle_min = -12.0
	pm.angle_max = 12.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.35
	pm.turbulence_noise_scale = 2.2
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.14
	var flame := _particles(14, 0.85, _mat(SH_FLAME, {"intensity": 2.3, "seed": 1.0}), pm, size)
	flame.name = "Flames"
	flame.position.y = 0.1 * size
	root.add_child(flame)
	var pm2 := pm.duplicate() as ParticleProcessMaterial
	pm2.scale_min = 0.45 * size
	pm2.scale_max = 0.8 * size
	pm2.initial_velocity_min = 1.2 * size
	pm2.initial_velocity_max = 2.2 * size
	pm2.emission_sphere_radius = 0.1 * size
	var tongues := _particles(10, 0.65, _mat(SH_FLAME, {"intensity": 2.6, "seed": 5.0, "flame_speed": 2.4}), pm2, size)
	tongues.name = "Tongues"
	tongues.position.y = 0.12 * size
	root.add_child(tongues)
	# --- embers
	var pe := ParticleProcessMaterial.new()
	pe.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pe.emission_sphere_radius = 0.16 * size
	pe.direction = Vector3.UP
	pe.spread = 28.0
	pe.initial_velocity_min = 0.8 * size
	pe.initial_velocity_max = 2.4 * size
	pe.gravity = Vector3(0.15, 0.35, 0.05)
	pe.scale_min = 0.012 * size + 0.006
	pe.scale_max = 0.03 * size + 0.01
	pe.turbulence_enabled = true
	pe.turbulence_noise_strength = 0.9
	pe.turbulence_noise_scale = 1.5
	pe.turbulence_influence_min = 0.1
	pe.turbulence_influence_max = 0.3
	var embers := _particles(14, 2.4, _mat(SH_EMBER, {"glow": 6.0}), pe, size * 2.0)
	embers.name = "Embers"
	embers.position.y = 0.2 * size
	root.add_child(embers)
	# --- smoke
	if opts.get("smoke", true):
		var ps := ParticleProcessMaterial.new()
		ps.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		ps.emission_sphere_radius = 0.12 * size
		ps.direction = Vector3.UP
		ps.spread = 14.0
		ps.initial_velocity_min = 0.5 * size
		ps.initial_velocity_max = 1.0 * size
		ps.gravity = Vector3(0.25, 0.25, 0.0)
		ps.scale_min = 0.9 * size
		ps.scale_max = 1.6 * size
		ps.scale_curve = _curve(0.5, 1.2, 2.4)
		ps.angle_min = 0.0
		ps.angle_max = 360.0
		ps.turbulence_enabled = true
		ps.turbulence_noise_strength = 0.5
		ps.turbulence_influence_min = 0.05
		ps.turbulence_influence_max = 0.12
		var smoke := _particles(9, 3.4, _mat(SH_SMOKE, {}), ps, size * 3.0)
		smoke.name = "Smoke"
		smoke.position.y = 0.9 * size
		root.add_child(smoke)
	# --- light
	if opts.get("light", true):
		var l := Flicker.new()
		l.name = "FireLight"
		l.light_color = opts.get("color", Color(1.0, 0.55, 0.2))
		l.base = float(opts.get("energy", 4.5)) * (0.6 + 0.4 * size)
		l.omni_range = float(opts.get("range", 12.0)) * (0.7 + 0.3 * size)
		l.omni_attenuation = 1.3
		l.shadow_enabled = bool(opts.get("shadows", false))
		l.light_volumetric_fog_energy = 1.2
		l.position = Vector3(0, 0.7 * size, 0)
		root.add_child(l)
	return root
