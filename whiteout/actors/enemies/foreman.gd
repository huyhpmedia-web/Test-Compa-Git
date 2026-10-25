extends "res://actors/enemy.gd"
## THE FOREMAN (Gil Arsenault): 2.6 m stalker. Limbs stretched, crystal-jointed, hard hat with a
## WORKING headlamp (SpotLight3D that sweeps). He hunts by LIGHT: if the player's flashlight is off,
## the player is > 6 m away and not inside his lamp cone, he loses track (and searches).
## Invulnerable unless `mortal` (then ~1100 HP, final fight). Bullets stagger at ~150 accumulated
## damage. FIRE (burn(): flares, explosions) makes him recoil and retreat for 8 s. He never enters
## a "safe_zone" Area3D with the player inside (gives up and walks away).
## params: stalk (true: roams toward the player's area), leave_after (0 = never; seconds of life
##         after which he vanishes), mortal (false)
## API: vanish() fades/walks into the dark and despawns (emits `vanished`).
## Music: plays Sfx.music("music_chase") while hunting; restores the previous track afterwards.

signal vanished

const Kit = preload("res://actors/kit.gd")
const RimeLook = preload("res://actors/rime_look.gd")

var stalk := true
var leave_after := 0.0
var mortal := false

var lamp: SpotLight3D
var _life := 0.0
var _hunting := false
var _prev_music := ""
var _lost_t := 0.0
var _heard_t := 0.0
var _last_seen := Vector3.ZERO
var _retreat_t := 0.0
var _retreat_from := Vector3.ZERO
var _roar_cd := 0.0
var _stride := 0.0
var _search_to := Vector3.ZERO
var _leave_dir := Vector3.ZERO
var _cool := 0.0
var _vanishing := false
var _atk_kind := "swipe"
var _head_yaw := 0.0
var _head_pitch := 0.0
var _aim_k := 0.0
var _patrol_t := 0.0
var _sweep_t := 0.0
var _flicker := 0.0
var _lamp_energy := 7.0
var _leg_boost := 0.0

func _ready() -> void:
	invulnerable = not mortal
	max_hp = 1100.0 if mortal else 1000.0
	speed = 1.5
	run_speed = 3.1
	turn_speed = 2.4
	attack_range = 2.3
	attack_damage = 35
	attack_cooldown = 2.2
	stagger_threshold = 150.0
	head_height = 2.1
	sight = 30.0
	fire_weakness = 2.5 if mortal else 1.0
	sep_strength = 0.0
	can_revive = false
	persistent_death = mortal
	super._ready()

func _sound(kind: String) -> String:
	return "foreman_" + kind

func _setup_collision() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 2.5
	col.shape = cap
	col.position.y = 1.3
	add_child(col)

# ------------------------------------------------------------------ model
const CharacterModel = preload("res://actors/character_model.gd")
const STRETCH := {"upperarm": Vector3(1, 1.55, 1), "thigh": Vector3(1, 1.4, 1), "calf": Vector3(1, 1.0, 1)}

func _make_model() -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var h := CharacterModel.new()
	h.setup({"model": "foreman"})
	h.pose = "zombie"
	var s: float = h._s
	# stretch the limbs: arms 1.55x, thighs 1.4x (the model is lifted so the feet stay on the floor)
	h.stretch(STRETCH)
	h.position.y = 0.36
	RimeLook.decorate(h, 1.1, 99)
	var ice := RimeLook.glacial("ice")
	var glow := RimeLook.glacial("glow")
	# crystal joints at the (stretched) elbows / knees / shoulders and bursting from his back and chest
	for sd in [["l", 1.0], ["r", -1.0]]:
		var ef: Node3D = h.bone_attachment("lowerarm_" + sd[0])
		var sh: Node3D = h.bone_attachment("upperarm_" + sd[0])
		var kn: Node3D = h.bone_attachment("calf_" + sd[0])
		if ef:
			Kit.cluster(ef, Vector3.ZERO, Vector3(sd[1], 0.3, -0.5), 4, 0.22 * s, 0.026 * s, ice, rng, 0.8)
			Kit.sphere(ef, 0.055 * s, glow, Vector3.ZERO)
		if sh:
			Kit.cluster(sh, Vector3(0, 0.05, 0), Vector3(sd[1], 1, -0.2), 4, 0.3 * s, 0.032 * s, ice, rng, 0.7)
		if kn:
			Kit.cluster(kn, Vector3.ZERO, Vector3(0, 0.2, 1.0), 3, 0.22 * s, 0.026 * s, ice, rng, 0.8)
			Kit.sphere(kn, 0.05 * s, glow, Vector3.ZERO)
	var ca: Node3D = h.bone_attachment("spine_03")
	Kit.cluster(ca, Vector3(0, 0.1, -0.1) * s, Vector3(0, 0.8, -1), 6, 0.45 * s, 0.035 * s, ice, rng, 0.7)
	Kit.cluster(ca, Vector3(0, 0.1, 0.1) * s, Vector3(0, 0.3, 1), 2, 0.2 * s, 0.03 * s, glow, rng, 0.6)
	# the headlamp that never went out (the hard hat is part of the body mesh)
	var mount := Node3D.new()
	mount.position = Vector3(0, 0.145, 0.125) * s
	h.bone_attachment("head").add_child(mount)
	lamp = SpotLight3D.new()
	lamp.rotation.y = PI
	lamp.light_color = Color(1.0, 0.93, 0.78)
	lamp.light_energy = _lamp_energy
	lamp.spot_range = 26.0
	lamp.spot_angle = 26.0
	lamp.spot_angle_attenuation = 0.7
	lamp.shadow_enabled = true
	lamp.light_volumetric_fog_energy = 2.5
	mount.add_child(lamp)
	# the pick he drags
	var pick := Node3D.new()
	Kit.limb(pick, Vector3(0, 0.25, 0), Vector3(0, -1.25, 0), 0.025, 0.02, Kit.mat("rust"))
	Kit.box(pick, Vector3(0.5, 0.05, 0.05), Kit.mat("iron"), Vector3(0, -1.25, 0))
	Kit.crystal(pick, Vector3(0.25, -1.25, 0), Vector3(1, 0, 0), 0.12, 0.03, ice, 2)
	Kit.crystal(pick, Vector3(-0.25, -1.25, 0), Vector3(-1, 0, 0), 0.12, 0.03, ice, 3)
	pick.rotation.x = 0.35
	h.hold(pick)
	Kit.post(h, _pose_post)
	return h

func _pose_post(delta: float) -> void:
	var m = model
	if m == null or m.pose == "dead" or lamp == null:
		return
	var tt := Time.get_ticks_msec() * 0.001
	var ph := tt * 1.6
	m.add_bone_rotation("spine_01", Vector3(0.16 + sin(tt * 0.9) * 0.02, 0, 0))
	m.add_bone_rotation("spine_03", Vector3(0.08, 0, sin(ph) * 0.06))
	# head: sweeps the lamp, or locks onto the player while tracking
	m.add_bone_rotation("neck_01", Vector3(-0.2, 0, 0))
	m.add_bone_rotation("head", Vector3(-0.1 + _head_pitch, _head_yaw, 0.05))

# ------------------------------------------------------------------ senses
func _eye() -> Vector3:
	return global_position + Vector3(0, 2.35, 0)

func _can_see(t: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(_eye(), t.global_position + Vector3(0, 1.3, 0), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _in_lamp_cone(p: Vector3) -> bool:
	if lamp == null or not lamp.visible:
		return false
	var to := p - lamp.global_position
	if to.length() > lamp.spot_range:
		return false
	return rad_to_deg((-lamp.global_transform.basis.z).angle_to(to)) < lamp.spot_angle + 3.0

func _tracking(dist: float) -> bool:
	if target == null or _cool > 0.0 or _in_safe_zone(target.global_position, 0.2):
		return false
	var pc := target.global_position + Vector3(0, 1.2, 0)
	if dist < 6.0 and _can_see(target):
		return true
	if dist < 2.5:
		return true
	if _light_on() and dist < sight and _can_see(target):
		return true
	if _in_lamp_cone(pc) and _can_see(target):
		return true
	if _heard_t > 0.0 and dist < 40.0:
		return true
	return false

func hear(pos: Vector3) -> void:
	if state in ["dead", "dormant", "vanish"]:
		return
	_last_heard = pos
	if target != null and pos.distance_to(target.global_position) < 4.0:
		_heard_t = 2.5
	if state == "idle":
		_search_to = pos
		_set_state("search")

## Burning barrels / flares call fear(): he recoils and retreats (dur x2, max 8 s).
func fear(pos: Vector3, dur: float = 4.0) -> void:
	if state in ["dead", "vanish", "dormant"]:
		return
	_retreat_t = max(_retreat_t, min(dur * 2.0, 8.0))
	_retreat_from = pos
	if state != "recoil":
		_set_state("recoil")
		_set_hunting(false)

func stun(sec: float) -> void:
	if state in ["dead", "vanish", "dormant"]:
		return
	_stagger_acc = 0.0
	_stun_len = clamp(sec * 0.4, 1.0, 2.5)   # he is a stalker: the bell only staggers him briefly
	_set_state("stagger")
	if model:
		model.play("stagger")

func take_hit(dmg: float, pos: Vector3, dir: Vector3, headshot: bool) -> void:
	if state in ["vanish"]:
		return
	super.take_hit(dmg, pos, dir, headshot)
	if state in ["idle", "search", "leave"] and state != "dead":
		_heard_t = 3.0
		_set_state("chase")

func burn(dmg: float, pos: Vector3) -> void:
	if state in ["dead", "vanish"]:
		return
	if mortal and not invulnerable:
		hp -= dmg * fire_weakness
		if hp <= 0.0:
			_die(false)
			return
	_retreat_t = 8.0
	_retreat_from = pos
	if state != "recoil" and state != "stagger":
		_set_state("recoil")
		_set_hunting(false)
		if _roar_cd <= 0.0:
			_roar_cd = 2.0
			Sfx.play_at(_sound("roar"), global_position, 5.0)
			if model and model.has_method("play"):
				model.play("roar")

# ------------------------------------------------------------------ music
func _set_hunting(on: bool) -> void:
	if on and not _hunting:
		_hunting = true
		_prev_music = Sfx.music_name
		if _prev_music != "music_chase":
			Sfx.music("music_chase", -6.0, 1.0)
	elif not on and _hunting:
		_hunting = false
		if Sfx.music_name == "music_chase":
			Sfx.music(_prev_music if _prev_music != "music_chase" else "", -8.0, 2.5)

func _exit_tree() -> void:
	if _hunting and Sfx != null and is_inside_tree():
		_set_hunting(false)

# ------------------------------------------------------------------ AI
func _think(delta: float) -> void:
	_life += delta
	_heard_t = max(0.0, _heard_t - delta)
	_cool = max(0.0, _cool - delta)
	_roar_cd = max(0.0, _roar_cd - delta)
	_sweep_t += delta
	if leave_after > 0.0 and _life > leave_after and not _vanishing:
		vanish()
	if target == null:
		return
	var to := target.global_position - global_position
	to.y = 0
	var dist := to.length()
	var tracking := _tracking(dist)
	var aim_target := false
	match state:
		"vanish":
			var away := -to.normalized() if dist > 0.1 else Vector3.FORWARD
			_move_to(global_position + away * 6.0, speed, delta)
		"recoil":
			_retreat_t -= delta
			var away2 := global_position - _retreat_from
			away2.y = 0
			if away2.length() < 0.1:
				away2 = -to
			_move_to(global_position + away2.normalized() * 6.0, run_speed * 0.95, delta)
			if _retreat_t <= 0.0:
				_set_state("search")
				_search_to = target.global_position
		"leave":
			_move_to(global_position + _leave_dir * 6.0, speed * 1.3, delta)
			if _state_t > 7.0:
				_cool = 6.0
				_set_state("idle")
		"chase":
			if Game.hp <= 0:
				velocity.x = 0
				velocity.z = 0
				_set_hunting(false)
				return
			if _in_safe_zone(target.global_position, 0.2):
				_give_up()
			elif tracking:
				_lost_t = 0.0
				_last_seen = target.global_position
				_set_hunting(true)
				aim_target = true
				if dist < attack_range and _atk_cd <= 0.0:
					_face(to, delta * 3.0)
					_attack()
				else:
					_move_to(target.global_position, run_speed, delta)
			else:
				_lost_t += delta
				_move_to(_last_seen, speed * 1.3, delta)
				if _lost_t > 2.0:
					_search_to = _last_seen
					_set_state("search")
					_set_hunting(false)
		"search":
			_set_hunting(false)
			if tracking:
				_set_state("chase")
				_lost_t = 0.0
			else:
				_move_to(_search_to, speed * 1.4, delta)
				if global_position.distance_to(_search_to) < 1.5 or _state_t > 10.0:
					_set_state("idle")
		_:
			# idle / stalking: roam toward the player's area, lamp sweeping
			_set_hunting(false)
			if tracking and not dormant:
				_set_state("chase")
				_lost_t = 0.0
			elif stalk:
				_patrol_t -= delta
				if _patrol_t <= 0.0 or global_position.distance_to(_wander_to) < 1.5:
					_patrol_t = randf_range(6.0, 10.0)
					var ang := randf() * TAU
					var rr := randf_range(10.0, 22.0)
					_wander_to = target.global_position + Vector3(sin(ang), 0, cos(ang)) * rr
				_move_to(_wander_to, speed, delta)
			else:
				velocity.x = move_toward(velocity.x, 0, delta * 8)
				velocity.z = move_toward(velocity.z, 0, delta * 8)
	# never walk into a safe room
	var hv := Vector3(velocity.x, 0, velocity.z)
	if hv.length() > 0.3 and state != "leave" and _in_safe_zone(global_position + hv.normalized() * 1.4, 0.3):
		velocity.x = 0
		velocity.z = 0
		if state in ["chase", "search"] and _in_safe_zone(target.global_position, 4.0):
			_give_up()
	_update_lamp(delta, aim_target, to, dist)
	_footsteps(delta)

func _give_up() -> void:
	_set_hunting(false)
	_leave_dir = (global_position - target.global_position)
	_leave_dir.y = 0
	_leave_dir = _leave_dir.normalized() if _leave_dir.length() > 0.1 else Vector3.BACK
	_set_state("leave")

func _update_lamp(delta: float, aim: bool, to: Vector3, dist: float) -> void:
	_aim_k = move_toward(_aim_k, 1.0 if aim else 0.0, delta * 2.0)
	var local_yaw := wrapf(atan2(to.x, to.z) - rotation.y, -PI, PI)
	var sweep_yaw := sin(_sweep_t * 0.7) * 0.85
	var want_yaw: float = lerp(sweep_yaw, clamp(local_yaw, -1.0, 1.0), _aim_k)
	var want_pitch: float = lerp(-0.1 + sin(_sweep_t * 0.45) * 0.12, clamp(0.35 - dist * 0.03, -0.1, 0.3) - 0.1, _aim_k)
	_head_yaw = lerp_angle(_head_yaw, want_yaw, clamp(delta * 3.0, 0.0, 1.0))
	_head_pitch = lerp(_head_pitch, want_pitch, clamp(delta * 3.0, 0.0, 1.0))
	if lamp:
		# the lamp flickers when he is hurt / retreating from fire
		_flicker = max(0.0, _flicker - delta)
		if state == "recoil" or state == "stagger":
			lamp.light_energy = _lamp_energy * (0.3 + 0.7 * float(randf() > 0.5))
		elif not _vanishing:
			lamp.light_energy = _lamp_energy * (1.0 if randf() > 0.015 else 0.4)

func _footsteps(delta: float) -> void:
	var v := Vector2(velocity.x, velocity.z).length()
	_stride += v * delta
	if _stride >= 2.3:
		_stride = 0.0
		Sfx.play_at(_sound("step"), global_position, 6.0, randf_range(0.85, 1.0))
		if randf() < 0.35:
			Sfx.play_at(_sound("creak"), global_position + Vector3(0, 1.5, 0), 0.0, randf_range(0.8, 1.2))
		var p = Game.player
		if p != null and is_instance_valid(p):
			var d: float = p.global_position.distance_to(global_position)
			if d < 14.0:
				p.set("shake", max(float(p.get("shake")), 0.15 * (1.0 - d / 14.0)))

func _attack() -> void:
	_atk_cd = attack_cooldown
	_atk_kind = "grab" if (target != null and (float(target.get("stun")) > 0.0 or randf() < 0.35)) else "swipe"
	_set_state("attack")
	if model and model.has_method("play"):
		model.play("grab" if _atk_kind == "grab" else "attack")
	Sfx.play_at(_sound("attack"), global_position, 3.0)

func _attack_hit() -> void:
	if target == null:
		return
	var to := target.global_position - global_position
	to.y = 0
	if to.length() > attack_range + 0.6 or global_transform.basis.z.dot(to.normalized()) < 0.2:
		return
	if not target.has_method("hurt"):
		return
	if _atk_kind == "grab":
		target.hurt(25, global_position, true)
		# slam / throw
		target.velocity += to.normalized() * 9.0 + Vector3(0, 3.0, 0)
		Sfx.play_at(_sound("grab"), target.global_position, 2.0)
	else:
		target.hurt(attack_damage, global_position, true)
		target.velocity += to.normalized() * 7.0
		Sfx.play_at(_sound("swipe"), global_position, 2.0)

# ------------------------------------------------------------------ vanish / death
func vanish() -> void:
	if _vanishing or state == "dead":
		return
	_vanishing = true
	_set_hunting(false)
	_set_state("vanish")
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.set_parallel(true)
	for mi in Kit.meshes(self):
		if mi is GeometryInstance3D:
			tw.tween_property(mi, "transparency", 1.0, 3.0)
	if lamp:
		tw.tween_property(lamp, "light_energy", 0.0, 3.5)
	tw.chain().tween_callback(func():
		vanished.emit()
		queue_free())

func _on_death() -> void:
	_set_hunting(false)
	if lamp:
		var tw := lamp.create_tween()
		tw.tween_property(lamp, "light_energy", 0.0, 2.5)
	if model:
		model.position.y = 0.05
	Kit.shard_burst(get_tree().current_scene, global_position + Vector3(0, 1.5, 0), 24, 4.0, 0.16)
	Sfx.play_at(_sound("death"), global_position, 6.0)
