extends "res://actors/enemy.gd"
## Hanger: hangs upside-down from the ceiling by crystalline filaments. Drops when the player
## passes beneath it, when it has been lit by the flashlight for ~1.2 s, or when hurt/woken.
## Lands with a grab (20 dmg), chases, and CAN CLIMB BACK UP (retract) if it hasn't caught the
## player for `climb_after` seconds and there is ceiling overhead.
## params: on_ceiling (true), ceiling_height (default: spawn Y + 0.3, i.e. spawn it at ceiling - 0.3 m; Y is then re-set to hang),
##         strand_len (0.5), drop_radius (2.2), climb_after (10.0), rime

const Kit = preload("res://actors/kit.gd")
const RimeLook = preload("res://actors/rime_look.gd")

var on_ceiling := true
var ceiling_height := -1.0   # < 0: derived from the spawn Y (spawned at ceiling - 0.3 m)
var strand_len := 0.5
var drop_radius := 2.2
var climb_after := 10.0
var rime := 1.2
const BODY_H := 1.8

var _hanging := false
var _lit_t := 0.0
var _rig: Node3D
var _twitch := 0.0
var _phase := 0.0
var _ceil_x := 0.0
var _ceil_z := 0.0

func _ready() -> void:
	max_hp = 55.0 * [0.8, 1.0, 1.3][Game.difficulty]
	speed = 1.6
	run_speed = 3.1
	attack_range = 1.4
	attack_damage = 18
	attack_cooldown = 1.3
	stagger_threshold = 25.0
	head_height = 1.5
	sight = 10.0
	fire_weakness = 2.0
	can_revive = false
	if on_ceiling:
		if ceiling_height < 0.0:
			ceiling_height = position.y + 0.3 if position.y > 1.5 else 3.6
		position.y = ceiling_height - strand_len - BODY_H
	super._ready()
	if on_ceiling:
		_ceil_x = global_position.x
		_ceil_z = global_position.z
		_set_hanging(true)
		if not dormant:
			state = "hang"

func _sound(kind: String) -> String:
	return "hanger_" + kind

const CharacterModel = preload("res://actors/character_model.gd")

func _make_model() -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(uid) if uid != "" else randi()
	var h := CharacterModel.new()
	h.setup({"model": "hanger"})
	h.pose = "zombie"
	h.stretch({"upperarm": Vector3(1, 1.7, 1), "thigh": Vector3(1, 1.4, 1)})   # much longer limbs
	h.position.y = 0.34
	RimeLook.decorate(h, rime, rng.randi())
	var s: float = clampf(h._s, 0.9, 1.4)
	# crystalline filaments bursting from the ankles (calf bone runs along +Y toward the foot)
	for bn in ["calf_l", "calf_r"]:
		var ba: Node3D = h.bone_attachment(bn)
		if ba:
			Kit.cluster(ba, Vector3(0, 0.4, 0) * s, Vector3(0, 1, 0), 6, 0.6 * s, 0.014 * s, RimeLook.glacial("ice"), rng, 0.18)
	Kit.post(h, _pose_post)
	return h

func _set_hanging(on: bool) -> void:
	_hanging = on
	if on:
		model.rotation.z = PI
		model.position.y = BODY_H
		_build_rig()
	else:
		pass

func _build_rig() -> void:
	if _rig and is_instance_valid(_rig):
		_rig.queue_free()
	_rig = Node3D.new()
	_rig.top_level = true
	add_child(_rig)
	_rig.global_position = Vector3(global_position.x, ceiling_height, global_position.z)
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
	var m := Kit.mat("ice_deep")
	var fm := Kit.mat("frost")
	Kit.mi(_rig, Kit.blob(0.55, rng.randi() % 99, 0.15, Vector3(1.0, 0.3, 1.0), 8, 14), fm, Vector3(0, -0.05, 0))
	for i in 6:
		var a := Vector3(rng.randf_range(-0.45, 0.45), -0.05, rng.randf_range(-0.45, 0.45))
		var b := Vector3(rng.randf_range(-0.12, 0.12), -strand_len, rng.randf_range(-0.12, 0.12))
		var mid := (a + b) * 0.5 + Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
		Kit.limb(_rig, a, mid, 0.035, 0.022, m, true, 6)
		Kit.limb(_rig, mid, b, 0.022, 0.03, m, true, 6)
	Kit.cluster(_rig, Vector3(0, -0.1, 0), Vector3(0, -1, 0), 8, 0.3, 0.05, Kit.mat("ice"), rng, 0.9)

func _pose_post(_delta: float) -> void:
	if model == null or model.pose == "dead":
		return
	var tt := Time.get_ticks_msec() * 0.001
	if _hanging:
		# limp arms dangling toward the floor (the model is upside-down; the "hang" pose has them raised), head lolling
		model.pose = "hang"
		model.add_bone_rotation("head", Vector3(sin(tt * 0.8) * 0.12, sin(tt * 0.6) * 0.3, _twitch * 0.4))
		model.add_bone_rotation("spine_02", Vector3(sin(tt * 0.9) * 0.05, 0, _twitch * 0.2))
	elif model.pose == "hang":
		model.pose = "zombie"

func is_headshot(pos: Vector3) -> bool:
	if _hanging:
		return pos.y - global_position.y < 0.55
	return super.is_headshot(pos)

func wake() -> void:
	if _hanging:
		dormant = false
		awake = true
		_begin_drop()
		return
	super.wake()

func hear(pos: Vector3) -> void:
	if _hanging:
		_twitch = 1.0
		_last_heard = pos
		return
	super.hear(pos)

func take_hit(dmg: float, pos: Vector3, dir: Vector3, headshot: bool) -> void:
	var was_hanging := _hanging
	super.take_hit(dmg, pos, dir, headshot)
	if was_hanging and state != "dead":
		_begin_drop()

func _begin_drop() -> void:
	if not _hanging:
		return
	_hanging = false
	_set_state("drop")
	awake = true
	dormant = false
	velocity = Vector3.ZERO
	Sfx.play_at(_sound("drop"), global_position, 2.0)
	Kit.shard_burst(get_tree().current_scene, Vector3(global_position.x, ceiling_height - 0.2, global_position.z), 8, 2.5, 0.1)
	if _rig and is_instance_valid(_rig):
		var r := _rig
		_rig = null
		var tw := r.create_tween()
		tw.tween_interval(6.0)
		tw.tween_callback(r.queue_free)
	var tw2 := create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(model, "rotation:z", 0.0, 0.5).set_trans(Tween.TRANS_SINE)
	tw2.tween_property(model, "position:y", 0.0, 0.5)

func _physics_process(delta: float) -> void:
	_phase += delta
	_twitch = max(0.0, _twitch - delta * 1.5)
	if _hanging and state in ["hang", "dormant", "retract"]:
		_state_t += delta
		velocity = Vector3.ZERO
		if target == null or not is_instance_valid(target):
			target = Game.player
		if state == "hang":
			_hang_think(delta)
		# gentle sway
		model.position.x = sin(_phase * 0.7) * 0.04
		if randf() < delta * 0.25:
			_twitch = 1.0
		return
	if state == "retract":
		_retract(delta)
		return
	super._physics_process(delta)

func _hang_think(delta: float) -> void:
	if target == null:
		return
	var to := target.global_position - global_position
	var flat := Vector2(to.x, to.z).length()
	# passing beneath
	if flat < drop_radius and target.global_position.y < global_position.y + 1.6:
		_begin_drop()
		return
	# lit by the flashlight
	if _in_player_beam(global_position + Vector3(0, 1.0, 0), 9.0, 2.0):
		_lit_t += delta
		_twitch = max(_twitch, 0.6)
		if _lit_t > 1.2:
			_begin_drop()
	else:
		_lit_t = max(0.0, _lit_t - delta * 0.5)

func _think(delta: float) -> void:
	match state:
		"drop":
			velocity.x = 0
			velocity.z = 0
			if _state_t > 0.2 and is_on_floor():
				Sfx.play_at(_sound("land"), global_position, 3.0)
				Kit.ring_wave(get_tree().current_scene, global_position + Vector3(0, 0.05, 0), 2.0, Color(0.7, 0.9, 1.0), 0.5)
				_set_state("chase")
				_atk_cd = 0.4
				if target and Vector2(target.global_position.x - global_position.x, target.global_position.z - global_position.z).length() < 1.5 and target.has_method("hurt"):
					target.hurt(attack_damage, global_position, true)
					model.play("grab")
			return
	if target == null:
		return
	var to := target.global_position - global_position
	to.y = 0
	var dist := to.length()
	if Game.hp <= 0:
		velocity.x = 0
		velocity.z = 0
		return
	if _fear_t > 0.0:
		_fear_t -= delta
		var away := global_position - _fear_from
		away.y = 0
		_move_to(global_position + away.normalized() * 4.0, run_speed, delta)
		return
	# climb back to the ceiling if it lost the player for a while
	if state == "chase" and _state_t > climb_after and dist > 3.5 and on_ceiling and _ceiling_above():
		_begin_retract()
		return
	if dist < attack_range and _atk_cd <= 0.0:
		_face(to, delta * 4.0)
		_attack()
		return
	_move_to(target.global_position, run_speed, delta)

func _ceiling_above() -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.0, 0), global_position + Vector3(0, ceiling_height + 0.6, 0), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit.position.y > ceiling_height - 0.5

func _begin_retract() -> void:
	_set_state("retract")
	_hanging = false
	velocity = Vector3.ZERO
	_ceil_x = global_position.x
	_ceil_z = global_position.z
	Sfx.play_at(_sound("climb"), global_position)
	# a filament lashes up to the ceiling and hauls it in
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(model, "rotation:z", PI, 0.5)
	tw.tween_property(model, "position:y", BODY_H, 0.5)

func _retract(delta: float) -> void:
	_state_t += delta
	velocity = Vector3.ZERO
	var goal := ceiling_height - strand_len - BODY_H
	if _state_t > 0.5:
		global_position.y = move_toward(global_position.y, goal, delta * 6.0)
		if absf(global_position.y - goal) < 0.02:
			global_position.y = goal
			_hanging = true
			_build_rig()
			_set_state("hang")
			_lit_t = 0.0
	if model:
		model.move_speed = 0.0

func _attack() -> void:
	_atk_cd = attack_cooldown
	_set_state("attack")
	if model and model.has_method("play"):
		model.play("grab")
	Sfx.play_at(_sound("attack"), global_position)

func _on_death() -> void:
	if _hanging:
		_hanging = false
	if model:
		model.rotation.z = 0.0
		model.position.y = 0.34
	if _rig and is_instance_valid(_rig):
		var r := _rig
		_rig = null
		var tw := r.create_tween()
		tw.tween_interval(5.0)
		tw.tween_callback(r.queue_free)
	Kit.shard_burst(get_tree().current_scene, global_position + Vector3(0, 1.0, 0), 6, 2.5, 0.09)
