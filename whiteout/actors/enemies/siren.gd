extends "res://actors/enemy.gd"
## Siren: emaciated, jaw unhinged, throat swollen with resonating crystals. Keeps its distance,
## flees the player's flashlight beam, and every ~6 s emits the hum which calls/wakes every
## Rimebound within 18 m (dormant ones included). Fragile (40 HP): priority target.
## params: hum_interval (6.0), hum_radius (18.0)

const Kit = preload("res://actors/kit.gd")
const RimeLook = preload("res://actors/rime_look.gd")

var hum_interval := 6.0
var hum_radius := 18.0
var rime := 0.8
var _hum_cd := 3.0
var _hum_k := 0.0            # 0..1 throat-resonance animation
var _hum_fired := false
var _jaw: Node3D
var _throat_mats: Array = []
var _throat_light: OmniLight3D
var _flee_t := 0.0
var _strafe := 1.0

func _ready() -> void:
	max_hp = 40.0 * [0.8, 1.0, 1.25][Game.difficulty]
	speed = 1.6
	run_speed = 3.4
	attack_range = 1.5
	attack_damage = 12
	attack_cooldown = 2.0
	stagger_threshold = 14.0
	head_height = 1.5
	sight = 20.0
	dark_sight = 0.5
	sep_radius = 1.2
	fire_weakness = 1.8
	_hum_cd = randf_range(1.5, hum_interval)
	_strafe = 1.0 if randf() < 0.5 else -1.0
	super._ready()

func _sound(kind: String) -> String:
	return "siren_" + kind

func _make_model() -> Node3D:
	var h := Humanoid.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(uid) if uid != "" else randi()
	h.setup({"zombie": true, "bloody": 0.2, "female": true, "skin": Color(0.78, 0.7, 0.68), "hair": Color(0.08, 0.07, 0.08), "hair_style": "long",
		"height": 1.92, "bulk": 0.62, "shirt": Color(0.3, 0.3, 0.34), "pants": Color(0.22, 0.22, 0.26), "coat": true, "coat_color": Color(0.38, 0.38, 0.42)})
	h.pose = "normal"
	var s: float = h.cfg.height / 1.72
	RimeLook.decorate(h, rime, rng.randi(), {"mouth": false})
	# ribs & spine knobs: emaciated look
	var bone := Kit.mat("bone")
	for i in 5:
		Kit.box(h.chest, Vector3(0.17 - i * 0.012, 0.012, 0.012) * s, bone, Vector3(0, 0.2 - i * 0.045, 0.108) * s)
	for i in 4:
		Kit.sphere(h.spine, 0.014 * s, bone, Vector3(0, 0.04 + i * 0.07, -0.08) * s)
	# unhinged jaw
	_jaw = Node3D.new()
	_jaw.position = Vector3(0, 0.065, 0.02) * s
	h.head.add_child(_jaw)
	var flesh := Kit.mat("skin_frost")
	var jaw_m := Kit.blob(0.05 * s, 11, 0.1, Vector3(1.0, 1.9, 1.0), 8, 12)
	Kit.mi(_jaw, jaw_m, flesh, Vector3(0, -0.07, 0.045) * s)
	var teeth := Kit.mat("tooth")
	for i in 7:
		var a: float = lerp(-0.5, 0.5, float(i) / 6.0)
		Kit.crystal(_jaw, Vector3(sin(a) * 0.045, -0.015, 0.05 + cos(a) * 0.035) * s, Vector3(0, 1, 0.1), 0.028 * s * rng.randf_range(0.7, 1.4), 0.006 * s, teeth, i)
	# dark mouth cavity on the face + upper teeth
	Kit.sphere(h.head, 0.045 * s, Kit.mat("mouth"), Vector3(0, 0.05, 0.065) * s, Vector3(0.95, 0.9, 0.55))
	for i in 6:
		var a: float = lerp(-0.5, 0.5, float(i) / 5.0)
		Kit.crystal(h.head, Vector3(sin(a) * 0.04, 0.08, 0.08 + cos(a) * 0.02) * s, Vector3(0, -1, 0.1), 0.024 * s * rng.randf_range(0.7, 1.3), 0.006 * s, teeth, i + 3)
	# throat: swollen goiter of resonating crystals
	var gm: StandardMaterial3D = Kit.mat("ice_glow").duplicate()
	_throat_mats.append(gm)
	Kit.sphere(h.neck, 0.062 * s, gm, Vector3(0, 0.045, 0.03) * s, Vector3(1.0, 1.5, 0.9))
	for i in 9:
		var ang := TAU * float(i) / 9.0
		var d := Vector3(sin(ang), rng.randf_range(-0.3, 0.9), cos(ang) * 0.9 + 0.2)
		Kit.crystal(h.neck, Vector3(0, 0.045, 0.03) * s + d.normalized() * 0.045 * s, d, rng.randf_range(0.08, 0.17) * s, 0.016 * s, gm, i)
	_throat_light = OmniLight3D.new()
	_throat_light.light_color = Color(0.45, 0.9, 1.0)
	_throat_light.light_energy = 0.6
	_throat_light.omni_range = 3.5
	_throat_light.shadow_enabled = false
	_throat_light.position = Vector3(0, 0.05, 0.12) * s
	h.neck.add_child(_throat_light)
	Kit.post(h, _pose_post)
	return h

## Runs after the humanoid's own animation: hunched, long dangling arms, head thrown back when humming.
func _pose_post(delta: float) -> void:
	var m = model
	if m == null or m.pose == "dead":
		return
	var k := _hum_k
	var tt := Time.get_ticks_msec() * 0.001
	m.spine.rotation.x = lerp(0.35, -0.12, k)
	m.chest.rotation.x = lerp(0.1, -0.15, k)
	m.neck.rotation.x = lerp(0.1, -0.5, k)
	m.head.rotation = Vector3(lerp(0.15, -0.55, k) + sin(tt * 1.7) * 0.03, sin(tt * 0.9) * 0.15 * (1.0 - k), lerp(0.18, 0.0, k))
	m.arm_l.rotation = Vector3(lerp(0.05, -0.35, k), 0, lerp(-0.12, -0.9, k))
	m.arm_r.rotation = Vector3(lerp(-0.05, -0.35, k), 0, lerp(0.12, 0.9, k))
	m.fore_l.rotation = Vector3(lerp(-0.35, -0.6, k), 0, 0)
	m.fore_r.rotation = Vector3(lerp(-0.25, -0.6, k), 0, 0)
	if _jaw:
		_jaw.rotation = Vector3(lerp(1.0, 1.45, k) + sin(tt * 3.0) * 0.04 * k, 0, 0.22)
	var e := 1.2 + k * 5.0 + sin(tt * 4.0) * 0.4
	for gm in _throat_mats:
		gm.emission_energy_multiplier = e
	if _throat_light:
		_throat_light.light_energy = 0.5 + k * 3.5

func _think(delta: float) -> void:
	if target == null:
		return
	var to := target.global_position - global_position
	to.y = 0
	var dist := to.length()
	_hum_k = move_toward(_hum_k, 1.0 if state == "hum" else 0.0, delta * 3.0)
	var lit := _in_player_beam(global_position + Vector3(0, 1.3, 0), 24.0, 6.0) and dist < 24.0
	if state in ["idle", "wander"]:
		_hum_k = move_toward(_hum_k, 0.0, delta * 3.0)
		if dist < _sight_range() and _can_see(target) or dist < 3.0:
			_set_state("chase")
			awake = true
		else:
			velocity.x = 0
			velocity.z = 0
			return
	if Game.hp <= 0:
		velocity.x = 0
		velocity.z = 0
		return
	_hum_cd -= delta
	if state == "hum":
		velocity.x = move_toward(velocity.x, 0, delta * 12)
		velocity.z = move_toward(velocity.z, 0, delta * 12)
		_face(to, delta * 3.0)
		if _state_t > 0.5 and not _hum_fired:
			_hum_fired = true
			_emit_hum()
		if _state_t > 1.9:
			_hum_cd = hum_interval + randf_range(-1.0, 1.0)
			_set_state("chase")
		if lit and _state_t > 0.3 and not _hum_fired:
			_set_state("chase")   # light interrupts the hum before it fires
		return
	if _fear_t > 0.0:
		_fear_t -= delta
		lit = true
	if lit:
		_flee_t = 0.8
	if _flee_t > 0.0:
		_flee_t -= delta
		var away := -to.normalized()
		var side := Vector3(-away.z, 0, away.x) * _strafe
		_move_to(global_position + (away + side * 0.6).normalized() * 5.0, run_speed, delta)
		return
	if _hum_cd <= 0.0 and dist < 24.0:
		_hum_fired = false
		_set_state("hum")
		return
	if dist < 1.6 and _atk_cd <= 0.0:
		_face(to, delta * 4.0)
		_attack()
	elif dist < 6.0:
		var away := -to.normalized()
		_move_to(global_position + away * 4.0, speed * 1.5, delta)
		if dist > 2.5:
			_face(to, delta * 3.0)
	elif dist > 11.5:
		_move_to(target.global_position, speed, delta)
	else:
		# hold at range, drift sideways
		var side := Vector3(-to.z, 0, to.x).normalized() * _strafe
		_move_to(global_position + side * 2.0, speed * 0.6, delta)
		_face(to, delta * 3.0)

func _emit_hum() -> void:
	Sfx.play_at(_sound("hum"), global_position, 8.0)
	Kit.ring_wave(get_tree().current_scene, global_position + Vector3(0, 0.1, 0), hum_radius * 0.5, Color(0.5, 0.9, 1.0), 1.4)
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == self or not is_instance_valid(e) or not (e is Node3D):
			continue
		if e.global_position.distance_to(global_position) > hum_radius:
			continue
		if e.get("dormant") == true or e.get("state") in ["dormant", "down"]:
			e.wake()
		elif e.has_method("hear"):
			e.hear(global_position)
	# the hum is also something the player feels
	var p = Game.player
	if p != null and is_instance_valid(p) and p.global_position.distance_to(global_position) < hum_radius:
		p.set("shake", max(float(p.get("shake")), 0.25))

func _attack_hit() -> void:
	if target == null:
		return
	var to := target.global_position - global_position
	to.y = 0
	if to.length() < attack_range + 0.5 and target.has_method("hurt"):
		target.hurt(attack_damage, global_position, false)

func _on_death() -> void:
	_hum_k = 0.0
	if _throat_light:
		_throat_light.light_energy = 0.0
	Kit.shard_burst(get_tree().current_scene, global_position + Vector3(0, 1.5, 0), 12, 3.0, 0.1, "ice_glow")
	for gm in _throat_mats:
		gm.emission_energy_multiplier = 0.0
