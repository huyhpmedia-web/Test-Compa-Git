extends "res://actors/enemy.gd"
## THE CHOIR (boss, St. Brendan's nave): a 5 m stationary pillar of a dozen fused congregants.
## Five glowing singing heads are the weak points (140 HP each; destroy all 5 to kill it; the
## heads flash when hit, go dark when destroyed and the pillar cracks and sags).
## Attacks: ice-shard fan (7 shards), fused-arm sweep (close range, 28 dmg + knockback),
## summons 2 crawlers every ~20 s (max 6 alive), hum pulse (screen shake; 8 dmg within 6 m).
## Body hits that miss a head do nothing. Emits `died` when all five heads are destroyed.
## params: head_hp (140), summon_every (20.0)

const Kit = preload("res://actors/kit.gd")
const ChoirModel = preload("res://actors/models/choir_model.gd")
const Projectile = preload("res://actors/projectile.gd")

var head_hp := 140.0
var summon_every := 20.0
var _hp_left: Array = []
var _shard_cd := 4.0
var _sweep_cd := 2.0
var _summon_cd := 8.0
var _pulse_cd := 9.0
var _minions: Array = []
var _swing_done := false
var _lost := 0

func _ready() -> void:
	max_hp = head_hp * 5.0
	stagger_threshold = 1e9
	sight = 30.0
	sep_strength = 0.0
	fire_weakness = 1.5
	can_revive = false
	head_height = 99.0
	super._ready()
	for i in ChoirModel.WEAK.size():
		_hp_left.append(head_hp)
	_hp_left = []
	for i in model.heads.size():
		_hp_left.append(head_hp if model.heads[i].weak else 0.0)
		if model.heads[i].weak:
			var cs := CollisionShape3D.new()
			var sh := SphereShape3D.new()
			sh.radius = 0.5
			cs.shape = sh
			cs.position = model.heads[i].node.position
			add_child(cs)

func _sound(kind: String) -> String:
	return "choir_" + kind

func _setup_collision() -> void:
	var col := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 1.15
	cy.height = 5.0
	col.shape = cy
	col.position.y = 2.5
	add_child(col)

func _make_model() -> Node3D:
	return ChoirModel.new()

func _head_at(pos: Vector3) -> int:
	var best := -1
	var bd := 0.65
	for i in model.heads.size():
		if model.heads[i].weak and model.heads[i].alive:
			var d: float = model.head_world(i).distance_to(pos)
			if d < bd:
				bd = d
				best = i
	return best

func is_headshot(pos: Vector3) -> bool:
	return _head_at(pos) >= 0

func take_hit(dmg: float, pos: Vector3, _dir: Vector3, _headshot: bool) -> void:
	if state == "dead" or (state == "dormant" and dormant):
		return
	awake = true
	if state == "idle":
		_set_state("fight")
	var i := _head_at(pos)
	if i < 0:
		Sfx.play_at(_sound("hit"), pos, -6.0)
		return
	_damage_head(i, dmg)

func _damage_head(i: int, dmg: float) -> void:
	_hp_left[i] -= dmg
	model.flash_head(i)
	Sfx.play_at(_sound("hit"), model.head_world(i), -2.0, randf_range(0.9, 1.1))
	if _hp_left[i] <= 0.0:
		_hp_left[i] = 0.0
		model.kill_head(i)
		_lost += 1
		Kit.shard_burst(get_tree().current_scene, model.head_world(i), 14, 4.0, 0.14, "ice_glow")
		Sfx.play_at(_sound("head_die"), model.head_world(i), 4.0)
		if model.heads[i].node:
			pass
		_shard_cd = min(_shard_cd, 1.0)
	hp = 0.0
	for v in _hp_left:
		hp += v
	if hp <= 0.0:
		_die(true)

func burn(dmg: float, pos: Vector3) -> void:
	if state == "dead":
		return
	var best := -1
	var bd := 5.0
	for i in model.heads.size():
		if model.heads[i].weak and model.heads[i].alive:
			var d: float = model.head_world(i).distance_to(pos)
			if d < bd:
				bd = d
				best = i
	if best >= 0:
		awake = true
		_damage_head(best, dmg * fire_weakness)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	velocity.x = 0
	velocity.z = 0

func _think(delta: float) -> void:
	if target == null:
		return
	var to := target.global_position - global_position
	to.y = 0
	var dist := to.length()
	if state in ["idle", "wander"]:
		if dist < 22.0:
			_set_state("fight")
		else:
			return
	if Game.hp <= 0:
		return
	var rage := 1.0 + 0.3 * _lost
	_shard_cd -= delta * rage
	_sweep_cd -= delta * rage
	_summon_cd -= delta
	_pulse_cd -= delta * rage
	if state != "sweep":
		_face(to, delta * 0.8)
		model.arm_raise = move_toward(model.arm_raise, 0.0, delta * 2.0)
		model.arm_yaw = move_toward(model.arm_yaw, 0.0, delta * 2.0)
	model.pulse = max(0.0, model.pulse - delta * 2.0)
	if state == "sweep":
		_do_sweep(delta, to)
		return
	if dist < 5.8 and _sweep_cd <= 0.0:
		_swing_done = false
		_set_state("sweep")
		Sfx.play_at(_sound("roar"), global_position, 4.0)
		return
	if _pulse_cd <= 0.0:
		_pulse_cd = randf_range(11.0, 15.0)
		_hum_pulse(dist)
	elif _shard_cd <= 0.0 and dist > 2.5:
		_shard_cd = randf_range(5.0, 7.5)
		_shard_wave()
	elif _summon_cd <= 0.0:
		_summon_cd = summon_every
		_summon()

func _do_sweep(delta: float, to: Vector3) -> void:
	var t := _state_t
	if t < 0.8:
		model.arm_raise = move_toward(model.arm_raise, 1.0, delta * 2.0)
		model.arm_yaw = lerp(model.arm_yaw, 0.8, delta * 4.0)
		_face(to, delta * 2.0)
	elif t < 1.3:
		model.arm_yaw = lerp(0.8, -1.5, (t - 0.8) / 0.5)
		if not _swing_done and t > 1.0:
			_swing_done = true
			_sweep_hit()
	elif t < 2.0:
		model.arm_raise = move_toward(model.arm_raise, 0.0, delta * 1.5)
	else:
		_sweep_cd = randf_range(2.5, 4.0)
		_set_state("fight")

func _sweep_hit() -> void:
	Kit.ring_wave(get_tree().current_scene, global_position + Vector3(0, 0.1, 0), 5.5, Color(0.8, 0.95, 1.0), 0.4)
	Sfx.play_at(_sound("sweep"), global_position, 4.0)
	var to := target.global_position - global_position
	to.y = 0
	if to.length() < 5.8 and global_transform.basis.z.dot(to.normalized()) > -0.2 and target.has_method("hurt"):
		target.hurt(28, global_position, true)
		target.velocity += to.normalized() * 8.0

func _shard_wave() -> void:
	Sfx.play_at(_sound("shards"), global_position, 3.0)
	var origin := global_position + Vector3(0, 2.8, 0) + global_transform.basis.z * 1.2
	var aim := (target.global_position + Vector3(0, 1.2, 0)) - origin
	var flat_yaw := atan2(aim.x, aim.z)
	var pitch := atan2(aim.y, Vector2(aim.x, aim.z).length())
	for k in 7:
		var yaw := flat_yaw + deg_to_rad((k - 3) * 11.0)
		var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
		var pr := Projectile.new()
		pr.kind = "shard"
		pr.damage = 10
		pr.vel = dir * 9.0
		pr.life = 4.0
		pr.size = 1.2
		get_tree().current_scene.add_child(pr)
		pr.global_position = origin
	model.pulse = 0.6

func _hum_pulse(dist: float) -> void:
	model.pulse = 1.0
	Sfx.play_at(_sound("hum"), global_position, 8.0)
	Kit.ring_wave(get_tree().current_scene, global_position + Vector3(0, 0.1, 0), 12.0, Color(0.5, 0.9, 1.0), 1.4)
	if dist < 22.0:
		target.set("shake", max(float(target.get("shake")), 1.0))
	if dist < 6.0 and target.has_method("hurt"):
		target.hurt(8, global_position, false)

func _summon() -> void:
	_minions = _minions.filter(func(m): return is_instance_valid(m) and m.get("state") != "dead")
	if _minions.size() >= 6:
		return
	Sfx.play_at(_sound("summon"), global_position, 3.0)
	for i in 2:
		var a := randf() * TAU
		var pos := global_position + Vector3(cos(a), 0, sin(a)) * 3.2
		var m := _spawn_minion("zombie", pos, {"crawler": true, "sep_radius": 0.7})
		if m:
			m.set("awake", true)
			m.set("state", "chase")
			_minions.append(m)
			Kit.shard_burst(get_tree().current_scene, pos + Vector3(0, 0.3, 0), 5, 2.0, 0.08)

func _on_death() -> void:
	model.sag = 1.0
	Sfx.play_at(_sound("death"), global_position, 8.0)
	for i in 6:
		Kit.shard_burst(get_tree().current_scene, global_position + Vector3(randf_range(-1, 1), randf_range(0.5, 4.5), randf_range(-1, 1)), 8, 3.5, 0.18)
