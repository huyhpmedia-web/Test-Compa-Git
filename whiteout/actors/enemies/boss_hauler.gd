extends "res://actors/enemy.gd"
## THE HAULER (boss, L5 haulage cavern): mountain of frozen miners around a haul-truck driver.
## ~1600 HP total. Only hits near the driver's exposed torso in the crown take full damage
## (everywhere else 25%). Charges in straight lines (hits a wall -> stunned 3 s and the crown drops
## so the weak point is much lower/easier to hit), ground slams (AOE) and flings ore chunks.
## params: (none needed)

const Kit = preload("res://actors/kit.gd")
const HaulerModel = preload("res://actors/models/hauler_model.gd")
const Projectile = preload("res://actors/projectile.gd")

var _charge_cd := 5.0
var _slam_cd := 3.0
var _ore_cd := 3.0
var _dir := Vector3.FORWARD
var _hit_done := false
var _stunned := 0.0
var weak_radius := 1.4

func _ready() -> void:
	max_hp = 1600.0 * [0.8, 1.0, 1.2][Game.difficulty]
	speed = 1.5
	run_speed = 1.7
	turn_speed = 1.3
	stagger_threshold = 1e9
	sight = 40.0
	sep_strength = 0.0
	fire_weakness = 1.6
	can_revive = false
	head_height = 99.0
	super._ready()

func _sound(kind: String) -> String:
	return "hauler_" + kind

func _setup_collision() -> void:
	var col := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 2.2
	cy.height = 3.4
	col.shape = cy
	col.position.y = 1.7
	add_child(col)
	var c2 := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.9
	c2.shape = sp
	c2.position = Vector3(0, 3.6, 0.3)
	add_child(c2)

func _make_model() -> Node3D:
	return HaulerModel.new()

func stun(sec: float) -> void:
	if state in ["dead", "dormant"]:
		return
	_set_state("stunned")
	_stun_len = sec

func stagger() -> void:
	pass

func _weak_pos() -> Vector3:
	return model.heart_world()

func is_headshot(pos: Vector3) -> bool:
	return pos.distance_to(_weak_pos()) < weak_radius

func take_hit(dmg: float, pos: Vector3, dir: Vector3, headshot: bool) -> void:
	if state == "dead" or (state == "dormant" and dormant):
		return
	awake = true
	if state == "idle":
		_set_state("chase")
	var weak := pos.distance_to(_weak_pos()) < weak_radius
	var d := dmg if weak else dmg * 0.25
	if weak:
		model.flash = 1.0
		Sfx.play_at(_sound("weak"), pos, 0.0)
	else:
		Sfx.play_at(_sound("hit"), pos, -4.0)
	hp -= d
	if hp <= 0.0:
		_die(headshot)

func burn(dmg: float, pos: Vector3) -> void:
	# fire licks the whole mass of frozen flesh
	if state == "dead":
		return
	awake = true
	hp -= dmg * fire_weakness * 0.5
	if hp <= 0.0:
		_die(false)

func _think(delta: float) -> void:
	if target == null:
		return
	var to := target.global_position - global_position
	to.y = 0
	var dist := to.length()
	model.stun_k = move_toward(model.stun_k, 1.0 if state == "stunned" else 0.0, delta * 3.0)
	model.charge_k = move_toward(model.charge_k, 1.0 if state == "charge" else 0.0, delta * 3.0)
	model.slam_k = move_toward(model.slam_k, 0.0, delta * 2.5)
	if state in ["idle", "wander"]:
		if dist < 28.0:
			_set_state("chase")
		else:
			return
	if Game.hp <= 0:
		return
	_charge_cd -= delta
	_slam_cd -= delta
	_ore_cd -= delta
	match state:
		"stunned":
			velocity.x = move_toward(velocity.x, 0, delta * 10)
			velocity.z = move_toward(velocity.z, 0, delta * 10)
			if _state_t > max(3.0, _stun_len):
				_stun_len = 1.0
				_charge_cd = 3.0
				_set_state("chase")
		"windup":
			velocity.x = 0
			velocity.z = 0
			_face(to, delta * 2.5)
			_dir = to.normalized()
			model.charge_k = move_toward(model.charge_k, 0.4, delta)
			if _state_t > 1.2:
				_hit_done = false
				_set_state("charge")
				Sfx.play_at(_sound("charge"), global_position, 5.0)
		"charge":
			velocity.x = _dir.x * 11.0
			velocity.z = _dir.z * 11.0
			rotation.y = atan2(_dir.x, _dir.z)
			if target and not _hit_done and global_position.distance_to(target.global_position) < 2.8 and target.has_method("hurt"):
				_hit_done = true
				target.hurt(40, global_position, true)
				target.velocity += _dir * 10.0
			# wall impact: we stopped moving although we should be at full tilt
			if _hit_wall() or (_state_t > 0.6 and Vector2(velocity.x, velocity.z).length() < 3.0 and global_position.distance_to(target.global_position) > 3.8):
				_wall_crash()
			elif _state_t > 2.6:
				_charge_cd = 4.0
				_set_state("chase")
		"slam":
			velocity.x = 0
			velocity.z = 0
			model.slam_k = min(1.0, _state_t * 1.6) if _state_t < 0.7 else model.slam_k
			if _state_t > 0.8 and not _hit_done:
				_hit_done = true
				_slam_hit()
			if _state_t > 1.5:
				_slam_cd = randf_range(3.5, 5.5)
				_set_state("chase")
		_:
			if dist < 6.5 and _slam_cd <= 0.0:
				_hit_done = false
				_set_state("slam")
				return
			if dist > 7.0 and _charge_cd <= 0.0:
				_set_state("windup")
				Sfx.play_at(_sound("roar"), global_position, 5.0)
				return
			if dist > 9.0 and _ore_cd <= 0.0:
				_ore_cd = randf_range(3.5, 5.5)
				_fling_ore()
			_move_to(target.global_position, run_speed, delta)
	_shake_near(dist)

func _hit_wall() -> bool:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if absf(c.get_normal().y) < 0.5 and c.get_collider() != null and not (c.get_collider() is CharacterBody3D):
			return true
	return false

func _wall_crash() -> void:
	velocity = Vector3.ZERO
	_set_state("stunned")
	Sfx.play_at(_sound("crash"), global_position, 8.0)
	Kit.ring_wave(get_tree().current_scene, global_position + Vector3(0, 0.1, 0), 7.0, Color(0.8, 0.85, 0.9), 0.6)
	Kit.shard_burst(get_tree().current_scene, global_position + _dir * 2.0 + Vector3(0, 2.0, 0), 22, 5.0, 0.2)
	var p = Game.player
	if p != null and is_instance_valid(p):
		p.set("shake", 1.0)

func _slam_hit() -> void:
	Sfx.play_at(_sound("slam"), global_position, 8.0)
	Kit.ring_wave(get_tree().current_scene, global_position + Vector3(0, 0.1, 0), 6.0, Color(0.9, 0.9, 1.0), 0.6)
	Kit.shard_burst(get_tree().current_scene, global_position + Vector3(0, 0.5, 0), 14, 5.0, 0.15)
	var p = Game.player
	if p != null and is_instance_valid(p):
		p.set("shake", 1.0)
		var d: float = Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
		if d < 6.0 and p.global_position.y < global_position.y + 1.2 and p.has_method("hurt"):
			p.hurt(int(30 * (1.0 - d / 6.0 * 0.5)), global_position, true)

func _fling_ore() -> void:
	Sfx.play_at(_sound("fling"), global_position, 3.0)
	var n := 1 + randi() % 2
	for i in n:
		var pr := Projectile.new()
		pr.kind = "ore"
		pr.damage = 20
		pr.aoe = 2.2
		pr.grav = 14.0
		pr.size = 1.3
		pr.life = 4.0
		var from := global_position + Vector3(0, 3.8, 0)
		var tgt := target.global_position + Vector3(randf_range(-1.5, 1.5), 0.5, randf_range(-1.5, 1.5))
		# ballistic solve for ~1.3 s flight
		var T := 1.3
		var d := tgt - from
		pr.vel = Vector3(d.x / T, d.y / T + 0.5 * pr.grav * T, d.z / T)
		get_tree().current_scene.add_child(pr)
		pr.global_position = from

func _shake_near(dist: float) -> void:
	if dist < 14.0 and Vector2(velocity.x, velocity.z).length() > 4.0:
		var p = Game.player
		if p != null and is_instance_valid(p):
			p.set("shake", max(float(p.get("shake")), 0.3))

func _on_death() -> void:
	model.pose = "dead"
	Sfx.play_at(_sound("death"), global_position, 8.0)
	Kit.shard_burst(get_tree().current_scene, global_position + Vector3(0, 2.5, 0), 30, 5.0, 0.22)
