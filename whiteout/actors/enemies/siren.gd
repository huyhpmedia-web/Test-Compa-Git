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

const CharacterModel = preload("res://actors/character_model.gd")

func _make_model() -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(uid) if uid != "" else randi()
	var h := CharacterModel.new()
	h.setup({"model": "siren"})
	h.pose = "zombie"
	var s: float = clampf(h._s, 0.9, 1.3)
	RimeLook.decorate(h, rime, rng.randi(), {"mouth": false})
	# throat: swollen goiter of resonating crystals (neck bone: y up, z forward)
	var nk: Node3D = h.bone_attachment("neck_01")
	var gm: StandardMaterial3D = RimeLook.glacial("glow").duplicate()
	_throat_mats.append(gm)
	Kit.sphere(nk, 0.058 * s, gm, Vector3(0, 0.05, 0.045) * s, Vector3(1.0, 1.5, 0.9))
	for i in 9:
		var ang := TAU * float(i) / 9.0
		var d := Vector3(sin(ang), rng.randf_range(-0.3, 0.9), cos(ang) * 0.9 + 0.2)
		Kit.crystal(nk, Vector3(0, 0.05, 0.045) * s + d.normalized() * 0.045 * s, d, rng.randf_range(0.05, 0.11) * s, 0.011 * s, gm, i)
	# crystal "teeth" in the dropped jaw
	var teeth := Kit.mat("tooth")
	var hb: Node3D = h.bone_attachment("head")
	for i in 7:
		var a: float = lerp(-0.5, 0.5, float(i) / 6.0)
		Kit.crystal(hb, Vector3(sin(a) * 0.035, -0.07, 0.085 + cos(a) * 0.02) * s, Vector3(0, 1, 0.1), 0.03 * s * rng.randf_range(0.7, 1.4), 0.006 * s, teeth, i)
	_throat_light = OmniLight3D.new()
	_throat_light.light_color = Color(0.45, 0.9, 1.0)
	_throat_light.light_energy = 0.6
	_throat_light.omni_range = 3.5
	_throat_light.shadow_enabled = false
	_throat_light.position = Vector3(0, 0.05, 0.12) * s
	nk.add_child(_throat_light)
	Kit.post(h, _pose_post)
	return h

## Runs after the model's own animation: head thrown back (and the throat lit) when humming.
func _pose_post(delta: float) -> void:
	var m = model
	if m == null or m.pose == "dead":
		return
	var k := _hum_k
	var tt := Time.get_ticks_msec() * 0.001
	m.add_bone_rotation("spine_03", Vector3(lerpf(0.0, -0.3, k), 0, 0))
	m.add_bone_rotation("neck_01", Vector3(lerpf(0.0, -0.45, k), 0, 0))
	m.add_bone_rotation("head", Vector3(lerpf(0.0, -0.45, k) + sin(tt * 1.7) * 0.03, sin(tt * 0.9) * 0.15 * (1.0 - k), 0))
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
