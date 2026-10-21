extends Area3D
## Simple projectile (ice shard / ore chunk / spit). Hurts the player on contact, bursts on world.
## kind: "shard" | "ore" | "spike"
const Kit = preload("res://actors/kit.gd")

var vel := Vector3.ZERO
var damage := 10
var kind := "shard"
var grav := 0.0
var life := 5.0
var aoe := 0.0           # >0: explodes in a radius (ore)
var size := 1.0
var _dead := false

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 2
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.22 * size
	cs.shape = sh
	add_child(cs)
	match kind:
		"ore":
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.2, 0.2, 0.24)
			m.roughness = 0.8
			Kit.mi(self, Kit.blob(0.4 * size, randi() % 50, 0.25, Vector3.ONE, 8, 10), m)
			Kit.cluster(self, Vector3.ZERO, Vector3.UP, 3, 0.35 * size, 0.07 * size, Kit.mat("ice"), RandomNumberGenerator.new(), 1.0)
		_:
			var c := Kit.crystal(self, Vector3.ZERO, Vector3.FORWARD, 0.9 * size, 0.07 * size, Kit.mat("ice_glow"), randi() % 8)
			c.rotation = Vector3.ZERO
			# crystal points along local +Z (travel direction)
			c.transform = Transform3D(Kit.basis_y(Vector3.BACK).scaled_local(Vector3(0.07 * size, 0.9 * size, 0.07 * size)), Vector3(0, 0, -0.3 * size))
			var l := OmniLight3D.new()
			l.light_color = Color(0.5, 0.9, 1.0)
			l.light_energy = 0.8
			l.omni_range = 2.5
			l.shadow_enabled = false
			add_child(l)
	body_entered.connect(_hit)

func _physics_process(delta: float) -> void:
	if _dead:
		return
	life -= delta
	vel.y -= grav * delta
	position += vel * delta
	if vel.length() > 0.1:
		if kind == "ore":
			rotate_x(delta * 4.0)
		else:
			look_at(global_position + vel, Vector3.UP if abs(vel.normalized().y) < 0.98 else Vector3.RIGHT)
	if life <= 0.0:
		_burst()

func _hit(b: Node) -> void:
	if _dead:
		return
	if b.is_in_group("player") and b.has_method("hurt") and aoe <= 0.0:
		b.hurt(damage, global_position, false)
	_burst()

func _burst() -> void:
	if _dead:
		return
	_dead = true
	var w := get_tree().current_scene
	if aoe > 0.0:
		Kit.ring_wave(w, global_position, aoe, Color(0.7, 0.8, 0.9), 0.5)
		Sfx.play_at("ore_impact", global_position, 3.0)
		for p in get_tree().get_nodes_in_group("player"):
			var d: float = p.global_position.distance_to(global_position)
			if d < aoe and p.has_method("hurt"):
				p.hurt(int(damage * (1.0 - d / aoe * 0.5)), global_position, false)
	Kit.shard_burst(w, global_position, 5, 3.0, 0.1)
	queue_free()
