extends "res://actors/enemy.gd"
## Burster: bloated with glowing frost-spore sacs. Slow. When killed, or when it stays adjacent
## to the player for 1.2 s, it bursts into a freezing cloud (actors/frost_cloud.gd, 4 s,
## 6 dmg/s to the player + slow 0.5, also hurts other enemies). Shoot it from range.
## params: fuse (1.2 s adjacency), cloud_radius (3.2)

const Kit = preload("res://actors/kit.gd")
const RimeLook = preload("res://actors/rime_look.gd")
const FrostCloud = preload("res://actors/frost_cloud.gd")

var fuse := 1.2
var cloud_radius := 3.2
var _adj_t := 0.0
var _burst_done := false
var _sacs: Array = []     # {node, base, ph}
var _sac_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _sac_lights: Array = []
var _swell := 0.0

func _ready() -> void:
	max_hp = 60.0 * [0.8, 1.0, 1.3][Game.difficulty]
	speed = 0.7
	run_speed = 1.05
	turn_speed = 2.5
	attack_range = 1.9
	attack_damage = 0
	head_height = 1.5
	stagger_threshold = 40.0
	sep_radius = 1.5
	sight = 13.0
	fire_weakness = 2.2
	can_revive = false
	super._ready()

func _sound(kind: String) -> String:
	return "burster_" + kind

func _setup_collision() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.55
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)

const CharacterModel = preload("res://actors/character_model.gd")

func _make_model() -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(uid) if uid != "" else randi()
	var h := CharacterModel.new()
	h.setup({"model": "burster"})
	h.pose = "zombie"
	RimeLook.decorate(h, 0.7, rng.randi())
	var s: float = clampf(h._s, 0.9, 1.3)
	_sac_mat = StandardMaterial3D.new()
	_sac_mat.albedo_color = Color(0.45, 0.9, 0.95, 0.5)
	_sac_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_sac_mat.roughness = 0.1
	_sac_mat.rim_enabled = true
	_sac_mat.rim = 1.0
	_sac_mat.rim_tint = 0.4
	_sac_mat.emission_enabled = true
	_sac_mat.emission = Color(0.2, 0.85, 0.9)
	_sac_mat.emission_energy_multiplier = 1.1
	_sac_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_core_mat = Kit.glow_unique(Color(0.45, 0.95, 1.0), 2.5)
	# [bone, bone-local pos, radius]  (torso bones: y up / z forward / x left; limb bones run along +Y)
	var defs := [
		["spine_01", Vector3(0, 0.12, 0.2), 0.26], ["spine_01", Vector3(0.16, 0.1, 0.14), 0.18], ["spine_01", Vector3(-0.16, 0.14, 0.13), 0.17],
		["spine_03", Vector3(-0.12, 0.08, 0.13), 0.13], ["spine_03", Vector3(0.1, 0.18, 0.12), 0.12], ["spine_03", Vector3(0.0, 0.1, -0.15), 0.2],
		["spine_03", Vector3(0.13, 0.05, -0.12), 0.13], ["upperarm_l", Vector3(0.06, 0.15, 0.0), 0.1], ["upperarm_r", Vector3(-0.06, 0.12, 0.02), 0.09],
		["neck_01", Vector3(0.04, 0.03, 0.04), 0.07], ["thigh_l", Vector3(0.0, 0.2, 0.08), 0.1], ["thigh_r", Vector3(0.0, 0.26, 0.07), 0.08],
	]
	var i := 0
	for d in defs:
		var r: float = d[2] * s * 0.9
		var holder := Node3D.new()
		holder.position = d[1] * s
		var ba: Node3D = h.bone_attachment(d[0])
		if ba == null:
			continue
		ba.add_child(holder)
		Kit.mi(holder, Kit.blob(r, 70 + i, 0.09, Vector3(1, 1, 0.9), 10, 14), _sac_mat, Vector3.ZERO)
		Kit.sphere(holder, r * 0.55, _core_mat, Vector3.ZERO, Vector3(1, 1, 1))
		# dark veins over the sac
		for k in 3:
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(0.2, 1)).normalized()
			Kit.crystal(holder, dir * r * 0.9, dir, r * 0.4, r * 0.05, RimeLook.glacial("ice"), i + k)
		_sacs.append({"node": holder, "base": holder.scale, "ph": rng.randf() * 6.28})
		i += 1
	for q in [["spine_01", Vector3(0, 0.1, 0.35)], ["spine_03", Vector3(0, 0.1, -0.25)]]:
		var l := OmniLight3D.new()
		l.light_color = Color(0.4, 0.9, 1.0)
		l.light_energy = 0.9
		l.omni_range = 3.5
		l.shadow_enabled = false
		l.position = q[1] * s
		var ba2: Node3D = h.bone_attachment(q[0])
		if ba2:
			ba2.add_child(l)
			_sac_lights.append(l)
	Kit.post(h, _pulse)
	return h

func _pulse(_delta: float) -> void:
	var tt := Time.get_ticks_msec() * 0.001
	var rate := 2.0 + _swell * 10.0
	for sc in _sacs:
		var n: Node3D = sc.node
		if is_instance_valid(n):
			var k := 1.0 + sin(tt * rate + sc.ph) * (0.05 + 0.08 * _swell) + _swell * 0.3
			n.scale = sc.base * k
	_core_mat.emission_energy_multiplier = 2.2 + sin(tt * rate) * 0.8 + _swell * 4.0
	for l in _sac_lights:
		l.light_energy = 0.8 + _swell * 2.5 + sin(tt * rate) * 0.2

func _think(delta: float) -> void:
	if target == null:
		return
	var to := target.global_position - global_position
	to.y = 0
	var dist := to.length()
	if state in ["idle", "wander"]:
		if dist < _sight_range() and _can_see(target) or dist < 2.5:
			_set_state("chase")
			awake = true
		else:
			if state == "idle" and _state_t > randf_range(3, 8):
				_wander_to = _home + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
				_set_state("wander")
			if state == "wander":
				_move_to(_wander_to, speed * 0.6, delta)
				if global_position.distance_to(_wander_to) < 0.8 or _state_t > 6:
					_set_state("idle")
			else:
				velocity.x = 0
				velocity.z = 0
			return
	if Game.hp <= 0:
		velocity.x = 0
		velocity.z = 0
		return
	# adjacency fuse
	if dist < attack_range and absf(target.global_position.y - global_position.y) < 1.5:
		_adj_t += delta
		_swell = clamp(_adj_t / fuse, 0.0, 1.0)
		if _adj_t == delta:
			Sfx.play_at(_sound("hiss"), global_position)
		if _adj_t >= fuse:
			hp = 0.0
			_die(false)
			return
		velocity.x = move_toward(velocity.x, 0, delta * 6)
		velocity.z = move_toward(velocity.z, 0, delta * 6)
		_face(to, delta * 3.0)
		return
	_adj_t = max(0.0, _adj_t - delta * 2.0)
	_swell = clamp(_adj_t / fuse, 0.0, 1.0)
	if _fear_t > 0.0:
		_fear_t -= delta
		var away := global_position - _fear_from
		away.y = 0
		_move_to(global_position + away.normalized() * 4.0, run_speed * 1.1, delta)
		return
	_move_to(target.global_position, run_speed, delta)

func _on_death() -> void:
	_burst()

func _burst() -> void:
	if _burst_done:
		return
	_burst_done = true
	_swell = 0.0
	for sc in _sacs:
		if is_instance_valid(sc.node):
			sc.node.visible = false
	for l in _sac_lights:
		l.light_energy = 0.0
	var w := get_tree().current_scene
	var c := FrostCloud.new()
	c.radius = cloud_radius
	c.source = self
	c.position = global_position
	w.add_child(c)
	FX.blood_burst(w, global_position + Vector3(0, 1.0, 0), Vector3.UP)
	FX.decal(w, global_position + Vector3(0, 0.02, 0), Vector3.UP, Color(0.5, 0.85, 0.95, 0.8), 2.2)
	set_deferred("collision_layer", 0)
