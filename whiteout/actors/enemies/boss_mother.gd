extends "res://actors/enemy.gd"
## THE HOLLOW MOTHER (final boss, L6 brine cavern). Speaks with Ruth's face.
##  PHASE 1: a vast crystalline lattice at the back of the cavern (stationary) with Ruth's upper
##   body fused at the centre. Weak point: Ruth's glowing chest (~900 HP; hits elsewhere do
##   nothing). Attacks: root tendrils erupting under the player (cracking-ice decal telegraph
##   ~1.1 s), summons shamblers/sirens every ~18 s, hum pulse.
##  PHASE 2: Ruth tears free - a 3 m spidery figure of crystal limbs. Fast lunges, stabs and
##   grabs. ~1200 HP, fire is very effective (x3). `died` is emitted ONLY after phase 2.
## params: phase (1|2, start phase), auto_phase2 (true: transforms when phase 1 HP is gone;
##   false: stays at 1 HP, invulnerable, until start_phase2() is called by the level script)
## signals: phase_changed(phase)

signal phase_changed(phase)

const Kit = preload("res://actors/kit.gd")
const MotherModel = preload("res://actors/models/mother_model.gd")

var phase := 1
var auto_phase2 := true
var _p1_hp := 900.0
var _p2_hp := 1200.0
var _tendril_cd := 3.0
var _summon_cd := 7.0
var _pulse_cd := 12.0
var _minions: Array = []
var _p1_shapes: Array = []
var _transforming := false
var _lunge_cd := 3.0
var _hit_done := false
var _lunge_dir := Vector3.ZERO
static var _crack_tex: ImageTexture

func _ready() -> void:
	var dm: float = [0.8, 1.0, 1.25][Game.difficulty]
	_p1_hp *= dm
	_p2_hp *= dm
	max_hp = _p1_hp
	speed = 2.6
	run_speed = 4.8
	turn_speed = 5.0
	attack_range = 3.5
	attack_damage = 20
	attack_cooldown = 1.5
	stagger_threshold = 1e9
	sight = 40.0
	sep_strength = 0.0
	fire_weakness = 3.0
	can_revive = false
	head_height = 3.0
	super._ready()
	if phase == 2:
		_enter_phase2(true)

func _sound(kind: String) -> String:
	return "mother_" + kind

func _setup_collision() -> void:
	var box := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(8, 6, 2.5)
	box.shape = bs
	box.position = Vector3(0, 3, -1.4)
	add_child(box)
	var sp := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = 0.95
	sp.shape = ss
	sp.position = Vector3(0, 2.75, 0.45)
	add_child(sp)
	_p1_shapes = [box, sp]

func _make_model() -> Node3D:
	return MotherModel.new()

func _heart() -> Vector3:
	return model.heart_world()

func is_headshot(pos: Vector3) -> bool:
	if phase == 2:
		return pos.distance_to(model.head_world()) < 0.45
	return pos.distance_to(_heart()) < 1.0

func fear(_pos: Vector3, _dur: float = 4.0) -> void:
	pass

func take_hit(dmg: float, pos: Vector3, _dir: Vector3, headshot: bool) -> void:
	if state == "dead" or (state == "dormant" and dormant) or _transforming:
		return
	awake = true
	if state == "idle":
		_set_state("fight" if phase == 1 else "chase")
	if phase == 1:
		if pos.distance_to(_heart()) < 1.05 and not invulnerable:
			model.flash = 1.0
			Sfx.play_at(_sound("hit"), pos, 0.0)
			hp -= dmg
			if hp <= 0.0:
				_p1_down()
		else:
			Sfx.play_at(_sound("hit"), pos, -8.0)
	else:
		model.flash = 0.6
		Sfx.play_at(_sound("hit"), pos, -3.0)
		hp -= dmg
		if hp <= 0.0:
			_die(headshot)

func burn(dmg: float, pos: Vector3) -> void:
	if state == "dead" or _transforming:
		return
	awake = true
	if phase == 1:
		if pos.distance_to(_heart()) < 6.0 and not invulnerable:
			hp -= dmg * 1.2
			model.flash = 1.0
			if hp <= 0.0:
				_p1_down()
	else:
		hp -= dmg * fire_weakness
		model.flash = 1.0
		if hp <= 0.0:
			_die(false)

func _p1_down() -> void:
	hp = 1.0
	invulnerable = true
	if auto_phase2:
		start_phase2()

## Begin the transformation (public: level scripts call this when auto_phase2 is false).
func start_phase2() -> void:
	if phase != 1 or _transforming:
		return
	_transforming = true
	invulnerable = true
	hp = 1.0
	_set_state("transform")
	Sfx.play_at(_sound("roar"), global_position, 8.0)
	if model:
		model.ruth.play("roar", 2.5)

func _enter_phase2(initial := false) -> void:
	phase = 2
	_transforming = false
	invulnerable = false
	max_hp = _p2_hp
	hp = _p2_hp
	model.crack_k = 0.0
	model.set_phase(2)
	for s in _p1_shapes:
		if is_instance_valid(s):
			s.queue_free()
	_p1_shapes = []
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.9
	cap.height = 3.3
	col.shape = cap
	col.position.y = 1.9
	add_child(col)
	if not initial:
		var w := get_tree().current_scene
		for i in 6:
			Kit.shard_burst(w, global_position + Vector3(randf_range(-6, 6), randf_range(1, 6), randf_range(-5, 0)), 10, 5.0, 0.3)
		Kit.ring_wave(w, global_position + Vector3(0, 0.1, 0), 14.0, Color(0.6, 0.95, 1.0), 1.0)
		var p = Game.player
		if p != null and is_instance_valid(p):
			p.set("shake", 1.0)
		_set_state("chase")
		_lunge_cd = 2.0
	phase_changed.emit(2)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if phase == 1:
		velocity.x = 0
		velocity.z = 0

func _think(delta: float) -> void:
	if target == null:
		return
	var to := target.global_position - global_position
	to.y = 0
	var dist := to.length()
	if state == "transform":
		model.crack_k = min(1.0, _state_t / 2.4)
		if _state_t > 2.8:
			_enter_phase2()
		return
	if phase == 1:
		_think_p1(delta, to, dist)
	else:
		_think_p2(delta, to, dist)

# ------------------------------------------------------------------ phase 1
func _think_p1(delta: float, _to: Vector3, dist: float) -> void:
	if state in ["idle", "wander"]:
		if dist < 30.0:
			_set_state("fight")
		return
	if Game.hp <= 0:
		return
	var rage := 1.0 + (1.0 - hp / max_hp) * 0.9
	_tendril_cd -= delta * rage
	_summon_cd -= delta
	_pulse_cd -= delta
	if _tendril_cd <= 0.0:
		_tendril_cd = randf_range(2.6, 3.8)
		var n := 1 + int(hp < max_hp * 0.5) + int(hp < max_hp * 0.25)
		for i in n:
			var lead: Vector3 = target.velocity * 0.5 if target.get("velocity") != null else Vector3.ZERO
			var off := Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)) * (0.0 if i == 0 else 1.0)
			_tendril(target.global_position + lead + off)
	if _summon_cd <= 0.0:
		_summon_cd = 18.0
		_summon()
	if _pulse_cd <= 0.0:
		_pulse_cd = randf_range(12.0, 16.0)
		Sfx.play_at(_sound("hum"), global_position, 8.0)
		Kit.ring_wave(get_tree().current_scene, global_position + Vector3(0, 0.1, 0), 14.0, Color(0.5, 0.9, 1.0), 1.5)
		target.set("shake", max(float(target.get("shake")), 0.7))

static func _crack_texture() -> ImageTexture:
	if _crack_tex != null:
		return _crack_tex
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var c := Color(0.55, 0.92, 1.0, 1.0)
	for k in 11:
		var ang := rng.randf() * TAU + k * 0.1
		var jit := 0.0
		var r := 3.0
		var px := 31.5
		var py := 31.5
		while r < 30.0:
			jit += rng.randf_range(-0.35, 0.35)
			px = 31.5 + cos(ang + jit) * r
			py = 31.5 + sin(ang + jit) * r
			for dx in 2:
				for dy in 2:
					img.set_pixel(clampi(int(px) + dx, 0, 63), clampi(int(py) + dy, 0, 63), Color(c.r, c.g, c.b, 1.0 - r / 40.0))
			r += 0.8
	for a in 120:
		var ang2 := TAU * float(a) / 120.0
		img.set_pixel(clampi(int(31.5 + cos(ang2) * 28.0), 0, 63), clampi(int(31.5 + sin(ang2) * 28.0), 0, 63), Color(c.r, c.g, c.b, 0.9))
	_crack_tex = ImageTexture.create_from_image(img)
	return _crack_tex

func _tendril(pos: Vector3) -> void:
	var w := get_tree().current_scene
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 2, 0), pos + Vector3(0, -4, 0), 1)
	var hit := space.intersect_ray(q)
	if hit:
		pos = hit.position
	var node := Node3D.new()
	w.add_child(node)
	node.global_position = pos
	var d := Decal.new()
	d.size = Vector3(3.0, 2.0, 3.0)
	d.texture_albedo = _crack_texture()
	d.texture_emission = _crack_texture()
	d.emission_energy = 2.5
	node.add_child(d)
	d.rotate_y(randf() * TAU)
	Sfx.play_at(_sound("crack"), pos, 0.0)
	var tw := node.create_tween()
	tw.tween_interval(1.1)
	tw.tween_callback(func(): _erupt(node, pos))
	tw.tween_interval(1.4)
	tw.tween_callback(node.queue_free)

func _erupt(node: Node3D, pos: Vector3) -> void:
	if not is_instance_valid(node):
		return
	Sfx.play_at(_sound("erupt"), pos, 4.0)
	var root_m := Kit.mat("root")
	var holder := Node3D.new()
	node.add_child(holder)
	var spikes: Array = []
	spikes.append(Kit.crystal(holder, Vector3.ZERO, Vector3(0, 1, 0), 3.8, 0.5, root_m, randi() % 8))
	for k in 5:
		var a := TAU * float(k) / 5.0
		spikes.append(Kit.crystal(holder, Vector3(cos(a), 0, sin(a)) * 0.5, Vector3(cos(a) * 0.5, 1, sin(a) * 0.5), randf_range(1.6, 2.6), 0.22, Kit.mat("ice_glow"), k))
	holder.scale = Vector3(1, 0.05, 1)
	var t2 := holder.create_tween()
	t2.tween_property(holder, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK)
	t2.tween_interval(0.9)
	t2.tween_property(holder, "scale", Vector3(1, 0.02, 1), 0.35)
	var p = Game.player
	if p != null and is_instance_valid(p):
		var dd := Vector2(p.global_position.x - pos.x, p.global_position.z - pos.z).length()
		if dd < 1.5 and p.global_position.y < pos.y + 2.0 and p.has_method("hurt"):
			p.hurt(24, pos, true)
			p.velocity += Vector3(0, 5.0, 0)
	Kit.shard_burst(get_tree().current_scene, pos + Vector3(0, 0.3, 0), 8, 4.0, 0.12)

func _summon() -> void:
	_minions = _minions.filter(func(m): return is_instance_valid(m) and m.get("state") != "dead")
	if _minions.size() >= 6:
		return
	Sfx.play_at(_sound("summon"), global_position, 4.0)
	var kinds := ["zombie", "zombie", "siren"]
	var sirens := 0
	for m in _minions:
		if m.get_script().resource_path.ends_with("siren.gd"):
			sirens += 1
	for i in 2:
		var type: String = kinds[randi() % 3]
		if type == "siren" and sirens >= 2:
			type = "zombie"
		var pos := global_position + Vector3(randf_range(-7, 7), 0, randf_range(4, 9))
		var params := {}
		if type == "zombie":
			params = {"variant": ["civilian", "worker", "nurse", "miner"][randi() % 4]}
		var m := _spawn_minion(type, pos, params)
		if m:
			m.set("awake", true)
			m.set("state", "chase")
			_minions.append(m)
			Kit.shard_burst(get_tree().current_scene, pos + Vector3(0, 0.3, 0), 6, 2.5, 0.08)

# ------------------------------------------------------------------ phase 2
func _think_p2(delta: float, to: Vector3, dist: float) -> void:
	if state in ["idle", "wander", "fight"]:
		_set_state("chase")
	_lunge_cd -= delta
	match state:
		"lunge_wind":
			velocity.x = move_toward(velocity.x, 0, delta * 30)
			velocity.z = move_toward(velocity.z, 0, delta * 30)
			_face(to, delta * 10.0)
			model.lunge_k = min(1.0, _state_t * 2.2)
			if _state_t > 0.55:
				_lunge_dir = to.normalized()
				velocity = _lunge_dir * 12.5
				velocity.y = 4.5
				_hit_done = false
				Sfx.play_at(_sound("lunge"), global_position, 4.0)
				_set_state("lunge")
		"lunge":
			if not _hit_done and global_position.distance_to(target.global_position) < 2.2 and absf(global_position.y - target.global_position.y) < 2.5:
				_hit_done = true
				if target.has_method("hurt"):
					target.hurt(30, global_position, true)
					target.velocity += _lunge_dir * 6.0
					Sfx.play_at(_sound("grab"), global_position, 3.0)
			if _state_t > 0.3 and is_on_floor():
				_lunge_cd = randf_range(2.5, 4.5)
				_set_state("recover")
		"recover":
			velocity.x = move_toward(velocity.x, 0, delta * 20)
			velocity.z = move_toward(velocity.z, 0, delta * 20)
			model.lunge_k = move_toward(model.lunge_k, 0.0, delta * 2.5)
			if _state_t > 0.8:
				_set_state("chase")
		_:
			if Game.hp <= 0:
				velocity.x = 0
				velocity.z = 0
				return
			model.lunge_k = move_toward(model.lunge_k, 0.0, delta * 3.0)
			if dist < attack_range and _atk_cd <= 0.0:
				_face(to, delta * 5.0)
				_attack()
			elif dist > 4.0 and dist < 11.0 and _lunge_cd <= 0.0 and _can_see(target):
				_set_state("lunge_wind")
			else:
				_move_to(target.global_position, run_speed, delta)

func _attack_hit() -> void:
	if target == null:
		return
	var to := target.global_position - global_position
	to.y = 0
	if to.length() < attack_range + 0.6 and target.has_method("hurt"):
		target.hurt(attack_damage, global_position, true)
		target.velocity += to.normalized() * 6.0
		Sfx.play_at(_sound("stab"), global_position, 2.0)

func _on_death() -> void:
	model.pose = "dead"
	Sfx.play_at(_sound("death"), global_position, 8.0)
	var w := get_tree().current_scene
	for i in 5:
		Kit.shard_burst(w, global_position + Vector3(randf_range(-1.5, 1.5), randf_range(1, 4), randf_range(-1.5, 1.5)), 10, 4.5, 0.2, "ice_glow")
