extends "res://actors/enemy.gd"
## Rime Hound: frozen sled dog, fast pack hunter (5 m/s), 35 HP.
## Pack behaviour: when one notices the player, hounds within 22 m are alerted; they spread
## around the player on individual flank angles, circle at range, then crouch and LUNGE
## (leap + bite), and back off (hit and run) before the next one.

const Kit = preload("res://actors/kit.gd")
const HoundModel = preload("res://actors/models/hound_model.gd")

var pack_angle := 0.0
var _circle_dir := 1.0
var _pack_alerted := false
var _bit := false
var _lunge_dir := Vector3.ZERO

func _ready() -> void:
	max_hp = 35.0 * [0.8, 1.0, 1.3][Game.difficulty]
	speed = 2.4
	run_speed = 5.0
	turn_speed = 9.0
	attack_range = 1.3
	attack_damage = 12
	attack_cooldown = 1.4
	stagger_threshold = 14.0
	head_height = 0.62
	sight = 20.0
	dark_sight = 0.45
	sep_radius = 1.3
	sep_strength = 1.8
	fire_weakness = 2.0
	can_revive = false
	pack_angle = randf_range(-PI, PI)
	_circle_dir = 1.0 if randf() < 0.5 else -1.0
	super._ready()

func _sound(kind: String) -> String:
	return "hound_" + kind

func _setup_collision() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.35
	col.shape = cap
	col.rotation.x = PI * 0.5
	col.position = Vector3(0, 0.5, -0.05)   # HD model: torso centre sits ~5 cm behind the foot centre
	add_child(col)

func _make_model() -> Node3D:
	var m := HoundModel.new()
	m._seed = hash(uid) % 1000 if uid != "" else randi() % 1000
	return m

func hear(pos: Vector3) -> void:
	var was_calm := state in ["idle", "wander"]
	super.hear(pos)
	if was_calm and state == "chase":
		_alert_pack()

func _alert_pack() -> void:
	if _pack_alerted:
		return
	_pack_alerted = true
	Sfx.play_at(_sound("howl"), global_position, 2.0)
	if model and model.has_method("play"):
		model.play("roar", 1.0)
	for e in get_tree().get_nodes_in_group("enemy"):
		if e != self and is_instance_valid(e) and e.get_script() == get_script() and e.global_position.distance_to(global_position) < 22.0:
			if e.state in ["idle", "wander"]:
				e.hear(global_position)

func _think(delta: float) -> void:
	if target == null:
		return
	var to := target.global_position - global_position
	to.y = 0
	var dist := to.length()
	match state:
		"idle", "wander":
			if dist < _sight_range() and _can_see(target) or dist < 3.5:
				_set_state("chase")
				awake = true
				_alert_pack()
			else:
				if state == "idle" and _state_t > randf_range(2, 6):
					_wander_to = _home + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
					_set_state("wander")
				if state == "wander":
					_move_to(_wander_to, speed * 0.7, delta)
					if global_position.distance_to(_wander_to) < 0.8 or _state_t > 5:
						_set_state("idle")
				else:
					velocity.x = move_toward(velocity.x, 0, delta * 10)
					velocity.z = move_toward(velocity.z, 0, delta * 10)
			return
		"crouch":
			velocity.x = move_toward(velocity.x, 0, delta * 25)
			velocity.z = move_toward(velocity.z, 0, delta * 25)
			_face(to, delta * 12.0)
			if _state_t > 0.38:
				_lunge_dir = to.normalized() if dist > 0.1 else Vector3.FORWARD
				_bit = false
				model.pose = "normal"
				model.play("attack", 0.7)
				Sfx.play_at(_sound("attack"), global_position)
				velocity = _lunge_dir * min(9.5, max(6.0, dist * 2.4))
				velocity.y = 4.3
				_set_state("lunge")
			return
		"lunge":
			_face(_lunge_dir, delta * 6.0)
			if not _bit and target != null and global_position.distance_to(target.global_position) < 1.25 and absf(global_position.y - target.global_position.y) < 1.4:
				_bit = true
				if target.has_method("hurt"):
					target.hurt(attack_damage, global_position, false)
					Sfx.play_at(_sound("bite"), global_position)
			if _state_t > 0.25 and is_on_floor():
				_atk_cd = randf_range(1.3, 2.6)
				_set_state("retreat" if _bit else "recover")
			return
		"recover":
			velocity.x = move_toward(velocity.x, 0, delta * 14)
			velocity.z = move_toward(velocity.z, 0, delta * 14)
			if _state_t > 0.35:
				_set_state("chase")
			return
		"retreat":
			var away := -to.normalized()
			velocity.x = move_toward(velocity.x, away.x * 4.5, delta * 30)
			velocity.z = move_toward(velocity.z, away.z * 4.5, delta * 30)
			_face(to, delta * 5.0)
			if _state_t > 0.8:
				_set_state("chase")
			return
	# --- chase
	if Game.hp <= 0:
		velocity.x = 0
		velocity.z = 0
		return
	if _fear_t > 0.0:
		_fear_t -= delta
		var away2 := global_position - _fear_from
		away2.y = 0
		_move_to(global_position + away2.normalized() * 5.0, run_speed, delta)
		return
	pack_angle += _circle_dir * delta * 0.7
	if dist < 1.5 and _atk_cd <= 0.0:
		_atk_cd = attack_cooldown
		_bit = false
		_lunge_dir = to.normalized()
		_set_state("crouch")
		model.pose = "crouch"
		return
	if dist < 7.0 and _atk_cd <= 0.0 and _can_see(target):
		_set_state("crouch")
		model.pose = "crouch"
		return
	if dist > 8.0:
		# run to this hound's flank point so the pack surrounds the player
		var flank := target.global_position + Vector3(sin(pack_angle), 0, cos(pack_angle)) * 4.5
		var p := flank if dist > 12.0 else target.global_position
		_move_to(p, run_speed, delta)
	else:
		# circle at 3.5-5 m until the lunge cooldown is up
		var tp := target.global_position + Vector3(sin(pack_angle), 0, cos(pack_angle)) * 4.0
		_move_to(tp, run_speed * 0.8, delta)
		_face(to, delta * 4.0)

func _on_death() -> void:
	if model:
		model.pose = "dead"
	Kit.shard_burst(get_tree().current_scene, global_position + Vector3(0, 0.6, 0), 6, 2.5, 0.09)

func _physics_process(delta: float) -> void:
	if state != "crouch" and model and model.pose == "crouch":
		model.pose = "normal"
	super._physics_process(delta)
