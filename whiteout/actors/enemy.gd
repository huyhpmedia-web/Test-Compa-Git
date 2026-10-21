extends CharacterBody3D
## Base enemy: health, hit reactions, navigation chase, melee attack, persistence.
## Subclasses override _make_model(), and optionally _think(delta) / _attack() / _on_death().
##
## Layer 3 (bit value 4) so the player's bullets hit it. Group "enemy".
## API used by the player/FX:  take_hit(dmg, pos, dir, headshot)  is_headshot(pos)  hear(pos)

const Humanoid = preload("res://actors/humanoid.gd")
const FX = preload("res://world/fx.gd")

signal died(enemy)

var uid := ""
var max_hp := 70.0
var hp := 70.0
var speed := 1.1
var run_speed := 1.1
var turn_speed := 4.0
var sight := 14.0
var attack_range := 1.3
var attack_damage := 18
var attack_cooldown := 1.6
var head_height := 1.5        # world-local Y above which hits count as headshots
var stagger_threshold := 30.0
var can_revive := false       # zombies may get up again once if not headshot-killed
var persistent_death := true
var model: Node3D
var nav: NavigationAgent3D
var state := "idle"           # idle | wander | chase | attack | stagger | dead | dormant
var target: Node3D
var awake := false
var dormant := false          # set true to keep it inert until wake() (scripted)
var invulnerable := false

var _atk_cd := 0.0
var _state_t := 0.0
var _stagger_acc := 0.0
var _repath := 0.0
var _home := Vector3.ZERO
var _wander_to := Vector3.ZERO
var _groan := 0.0
var _last_heard := Vector3.ZERO
var _revived := false

func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	hp = max_hp
	_home = global_position
	_setup_collision()
	model = _make_model()
	if model:
		add_child(model)
	nav = NavigationAgent3D.new()
	nav.path_desired_distance = 0.6
	nav.target_desired_distance = 0.8
	nav.radius = 0.35
	nav.avoidance_enabled = false
	add_child(nav)
	_groan = randf_range(2.0, 7.0)
	if dormant:
		state = "dormant"

func _setup_collision() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.33
	cap.height = 1.75
	col.shape = cap
	col.position.y = 0.875
	add_child(col)

func _make_model() -> Node3D:
	var h := Humanoid.new()
	h.setup({"zombie": true})
	return h

func wake() -> void:
	dormant = false
	if state == "dormant":
		state = "chase"
		awake = true

func is_headshot(pos: Vector3) -> bool:
	return pos.y - global_position.y > head_height

## Fire/flares: flee from pos for dur seconds (bosses/stalkers may override to ignore).
var _fear_t := 0.0
var _fear_from := Vector3.ZERO
var fire_weakness := 1.5      # damage multiplier from fire (FX.explosion / flares)

func fear(pos: Vector3, dur: float = 4.0) -> void:
	if state in ["dead", "dormant", "down"]:
		return
	_fear_t = dur
	_fear_from = pos

func burn(dmg: float, pos: Vector3) -> void:
	take_hit(dmg * fire_weakness, global_position + Vector3(0, 1, 0), (global_position - pos).normalized(), false)
	fear(pos, 3.0)

## Effective sight range: the Rimebound sense light and heat. A player with the
## flashlight off in the dark is much harder to notice.
func _sight_range() -> float:
	var p = Game.player
	if p != null and is_instance_valid(p) and p.get("flashlight") != null and not p.flashlight.visible:
		return sight * 0.35
	return sight

func hear(pos: Vector3) -> void:
	if state in ["dead", "dormant"]:
		return
	_last_heard = pos
	if state in ["idle", "wander"]:
		state = "chase"
		awake = true

func take_hit(dmg: float, _pos: Vector3, dir: Vector3, headshot: bool) -> void:
	if state == "dead" or state == "dormant" and dormant:
		return
	awake = true
	if not invulnerable:
		hp -= dmg
	_stagger_acc += dmg
	velocity += Vector3(dir.x, 0, dir.z).normalized() * min(dmg * 0.04, 2.5)
	Sfx.play_at(_sound("hit"), global_position, -4.0, randf_range(0.9, 1.1))
	if hp <= 0.0 and not invulnerable:
		_die(headshot)
		return
	if _stagger_acc >= stagger_threshold or headshot and randf() < 0.5:
		_stagger_acc = 0.0
		_set_state("stagger")
		if model and model.has_method("play"):
			model.play("stagger")
	elif model and model.has_method("play"):
		model.play("hurt")
	if state in ["idle", "wander"]:
		_set_state("chase")

func _sound(kind: String) -> String:
	return "zombie_" + kind

func _die(headshot: bool) -> void:
	if can_revive and not _revived and not headshot and randf() < 0.45:
		# fakes death, gets back up later
		_revived = true
		_set_state("down")
		if model:
			model.pose = "dead"
		Sfx.play_at(_sound("death"), global_position)
		return
	_set_state("dead")
	hp = 0
	if model:
		model.pose = "dead"
	Sfx.play_at(_sound("death"), global_position)
	collision_layer = 0
	collision_mask = 1
	if persistent_death and uid != "":
		Game.set_flag("dead:" + uid)
	remove_from_group("enemy")
	_on_death()
	died.emit(self)

func _on_death() -> void:
	pass

func _set_state(s: String) -> void:
	state = s
	_state_t = 0.0

func _physics_process(delta: float) -> void:
	_state_t += delta
	_atk_cd = max(0.0, _atk_cd - delta)
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = -0.5
	if target == null or not is_instance_valid(target):
		target = Game.player
	match state:
		"dormant":
			velocity.x = 0
			velocity.z = 0
		"dead":
			velocity.x = move_toward(velocity.x, 0, delta * 10)
			velocity.z = move_toward(velocity.z, 0, delta * 10)
		"down":
			velocity.x = 0
			velocity.z = 0
			if _state_t > randf_range(5.0, 9.0) and target and global_position.distance_to(target.global_position) < 8.0:
				hp = max_hp * 0.5
				if model:
					model.pose = "zombie"
				Sfx.play_at(_sound("groan"), global_position)
				_set_state("chase")
		"stagger":
			velocity.x = move_toward(velocity.x, 0, delta * 6)
			velocity.z = move_toward(velocity.z, 0, delta * 6)
			if _state_t > 1.0:
				_set_state("chase")
		"attack":
			velocity.x = move_toward(velocity.x, 0, delta * 10)
			velocity.z = move_toward(velocity.z, 0, delta * 10)
			if _state_t > 0.45 and _state_t - delta <= 0.45:
				_attack_hit()
			if _state_t > 1.1:
				_set_state("chase")
		_:
			_think(delta)
	move_and_slide()
	if model:
		model.move_speed = Vector2(velocity.x, velocity.z).length()
	_groan -= delta
	if _groan <= 0.0 and state != "dead" and state != "dormant":
		_groan = randf_range(4.0, 10.0)
		Sfx.play_at(_sound("groan"), global_position, -6.0, randf_range(0.85, 1.1))

## Default AI: idle until the player is seen/heard, then chase and attack.
func _think(delta: float) -> void:
	if target == null:
		return
	var to := target.global_position - global_position
	to.y = 0
	var dist := to.length()
	if state in ["idle", "wander"]:
		if dist < _sight_range() and _can_see(target) or dist < 2.2:
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
	if _fear_t > 0.0:
		_fear_t -= delta
		var away := global_position - _fear_from
		away.y = 0
		_move_to(global_position + away.normalized() * 4.0, run_speed * 1.2, delta)
		return
	if state == "chase":
		if Game.hp <= 0:
			velocity.x = 0
			velocity.z = 0
			return
		if dist < attack_range and _atk_cd <= 0.0:
			_face(to, delta * 3.0)
			_attack()
			return
		_move_to(target.global_position, run_speed, delta)

func _attack() -> void:
	_atk_cd = attack_cooldown
	_set_state("attack")
	if model and model.has_method("play"):
		model.play("attack")
	Sfx.play_at(_sound("attack"), global_position)

func _attack_hit() -> void:
	if target == null:
		return
	var to := target.global_position - global_position
	to.y = 0
	var fwd := global_transform.basis.z
	if to.length() < attack_range + 0.4 and fwd.dot(to.normalized()) > 0.3 and target.has_method("hurt"):
		target.hurt(attack_damage, global_position, true)

func _can_see(t: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.5, 0), t.global_position + Vector3(0, 1.4, 0), 1)
	return space.intersect_ray(q).is_empty()

func _move_to(p: Vector3, spd: float, delta: float) -> void:
	_repath -= delta
	if _repath <= 0.0:
		_repath = 0.4
		nav.target_position = p
	var next := nav.get_next_path_position()
	var dir := next - global_position
	dir.y = 0
	if dir.length() < 0.05 or nav.is_navigation_finished():
		dir = p - global_position
		dir.y = 0
	if dir.length() > 0.01:
		dir = dir.normalized()
		velocity.x = move_toward(velocity.x, dir.x * spd, delta * 8.0)
		velocity.z = move_toward(velocity.z, dir.z * spd, delta * 8.0)
		_face(dir, delta * turn_speed)

func _face(dir: Vector3, w: float) -> void:
	if dir.length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), clamp(w, 0.0, 1.0))
