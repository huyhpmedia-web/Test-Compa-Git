extends Area3D
## Freezing spore cloud (Burster). Lives `life` seconds. While the player is inside:
##   Game.damage(dps * 0.5) every 0.5 s (6 dmg/s) and the player's movement is slowed via
##   player meta:  set_meta("slow", 0.5)  +  set_meta("slow_t", 0.35)   (refreshed every physics tick)
## player.gd should multiply its target velocity by get_meta("slow", 1.0) and count slow_t down
## (see the report). Other enemies inside take light damage every tick.

const Kit = preload("res://actors/kit.gd")

var radius := 3.2
var life := 4.0
var dps := 6.0
var slow := 0.5
var source: Node = null
var _t := 0.0
var _tick := 0.0
var _flash := 0.0
var _light: OmniLight3D

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 | 4
	monitoring = true
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = radius
	cs.shape = sh
	cs.position.y = radius * 0.45
	add_child(cs)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.55, 0.9, 1.0)
	_light.light_energy = 2.5
	_light.omni_range = radius * 2.2
	_light.shadow_enabled = false
	_light.position.y = 1.0
	add_child(_light)
	# billowing frost: soft overlapping puffs
	var p := CPUParticles3D.new()
	p.amount = 70
	p.lifetime = 2.6
	p.preprocess = 0.3
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.55
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.7
	p.gravity = Vector3(0, 0.15, 0)
	p.scale_amount_min = 0.9
	p.scale_amount_max = 1.7
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 8
	sm.rings = 4
	p.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.7, 0.92, 1.0, 0.22)
	m.vertex_color_use_as_albedo = true
	p.material_override = m
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.add_point(0.2, Color(1, 1, 1, 1.0))
	g.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = g
	p.position.y = radius * 0.4
	add_child(p)
	Sfx.play_at("burster_burst", global_position, 4.0)
	Kit.ring_wave(get_parent(), global_position + Vector3(0, 0.1, 0), radius, Color(0.6, 0.95, 1.0), 0.7)
	Kit.shard_burst(get_parent(), global_position + Vector3(0, 0.8, 0), 8, 3.5, 0.1, "ice_glow")

func _physics_process(delta: float) -> void:
	_t += delta
	_tick -= delta
	var fade: float = clamp((life - _t) / 1.0, 0.0, 1.0)
	_light.light_energy = 2.5 * fade
	var player_in := false
	for b in get_overlapping_bodies():
		if not is_instance_valid(b):
			continue
		if b.is_in_group("player"):
			player_in = true
			b.set_meta("slow", slow)
			b.set_meta("slow_t", 0.35)
			if _tick <= 0.0 and Game.hp > 0:
				Game.damage(int(round(dps * 0.5)))
				_flash += 1.0
				if _flash >= 2.0:
					_flash = 0.0
					UI.flash_damage()
	if _tick <= 0.0:
		_tick = 0.5
		for b in get_overlapping_bodies():
			if is_instance_valid(b) and b != source and b.is_in_group("enemy") and b.has_method("take_hit"):
				if b.get("state") in ["dead", "dormant"]:
					continue
				b.take_hit(dps * 0.4, b.global_position + Vector3(0, 1, 0), Vector3.ZERO, false)
	if _t >= life:
		_release_player()
		queue_free()

func _release_player() -> void:
	for p in get_tree().get_nodes_in_group("player"):
		if p.has_meta("slow") and p.get_meta("slow") == slow:
			p.remove_meta("slow")
			if p.has_meta("slow_t"):
				p.remove_meta("slow_t")

func _exit_tree() -> void:
	if is_inside_tree():
		_release_player()
