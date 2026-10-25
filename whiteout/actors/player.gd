extends CharacterBody3D
## Elias Kade — over-the-shoulder third-person survival-horror controller.

const CharacterModel = preload("res://actors/character_model.gd")
const Mats = preload("res://core/mats.gd")
const FX = preload("res://world/fx.gd")

const WALK := 2.3
const RUN := 4.6
const AIM_WALK := 1.1
const GRAVITY := 18.0
const MOUSE_SENS := 0.0025

var model: Node3D
var yaw_pivot: Node3D
var pitch_pivot: Node3D
var arm: SpringArm3D
var cam: Camera3D
var flashlight: SpotLight3D
var muzzle_light: OmniLight3D

var cam_yaw := 0.0
var cam_pitch := -0.15
var aiming := false
var aim_t := 0.0            # 0..1 aim blend
var focus := 0.0            # reticle focus 0 (wide) .. 1 (tight)
var fire_cd := 0.0
var reload_t := 0.0
var knife_cd := 0.0
var invuln := 0.0
var stun := 0.0
var step_t := 0.0
var shake := 0.0
var input_locked := false   # cutscenes
var focused_interact: Node = null
var _recoil := 0.0
var _kick := Vector2.ZERO

func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.7
	col.shape = cap
	col.position.y = 0.85
	add_child(col)

	model = CharacterModel.new()
	model.setup({"model": "elias"})
	add_child(model)

	yaw_pivot = Node3D.new()
	yaw_pivot.top_level = true
	add_child(yaw_pivot)
	pitch_pivot = Node3D.new()
	pitch_pivot.position = Vector3(0, 1.55, 0)
	yaw_pivot.add_child(pitch_pivot)
	arm = SpringArm3D.new()
	arm.spring_length = 2.4
	arm.collision_mask = 1
	arm.margin = 0.15
	var sph := SphereShape3D.new()
	sph.radius = 0.18
	arm.shape = sph
	arm.position = Vector3(0.45, 0.05, 0)
	pitch_pivot.add_child(arm)
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.05
	cam.far = 300.0
	cam.current = true
	arm.add_child(cam)
	arm.add_excluded_object(get_rid())

	flashlight = SpotLight3D.new()
	flashlight.light_color = Color(1.0, 0.95, 0.85)
	flashlight.light_energy = 4.0
	flashlight.spot_range = 22.0
	flashlight.spot_angle = 24.0
	flashlight.spot_angle_attenuation = 0.8
	flashlight.shadow_enabled = true
	flashlight.light_volumetric_fog_energy = 0.6
	flashlight.position = Vector3(0.35, 1.45, 0.1)
	add_child(flashlight)
	flashlight.visible = Game.get_flag("flashlight_on", true)

	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = Color(1.0, 0.75, 0.4)
	muzzle_light.omni_range = 6.0
	muzzle_light.light_energy = 0.0
	add_child(muzzle_light)

	cam_yaw = rotation.y + PI
	model.rotation.y = 0.0
	_update_weapon_model()
	Game.inventory_changed.connect(_update_weapon_model)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Spawn helper: face direction yaw (radians, 0 = +Z).
func place(pos: Vector3, yaw: float) -> void:
	global_position = pos
	model.rotation.y = yaw
	cam_yaw = yaw + PI
	velocity = Vector3.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if UI.is_blocking() or input_locked:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := MOUSE_SENS * (0.55 if aiming else 1.0)
		cam_yaw -= event.relative.x * sens
		cam_pitch = clamp(cam_pitch - event.relative.y * sens, -1.2, 0.9)
		focus = max(0.0, focus - event.relative.length() * 0.004)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if Game.hp <= 0:
		model.pose = "dead"
		velocity.x = 0; velocity.z = 0
		velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	fire_cd = max(0.0, fire_cd - delta)
	knife_cd = max(0.0, knife_cd - delta)
	invuln = max(0.0, invuln - delta)
	stun = max(0.0, stun - delta)
	shake = max(0.0, shake - delta * 3.0)
	muzzle_light.light_energy = max(0.0, muzzle_light.light_energy - delta * 60.0)
	_recoil = max(0.0, _recoil - delta * 4.0)

	var blocked := UI.is_blocking() or input_locked or stun > 0.0
	var in_dir := Vector2.ZERO
	if not blocked:
		in_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		# gamepad right stick look
		var rs := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
		if rs.length() > 0.15:
			cam_yaw -= rs.x * delta * 2.6
			cam_pitch = clamp(cam_pitch - rs.y * delta * 2.0, -1.2, 0.9)
	aiming = not blocked and (Input.is_action_pressed("aim") or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT) > 0.5) and _equipped_is_gun() and reload_t <= 0.0
	aim_t = move_toward(aim_t, 1.0 if aiming else 0.0, delta * 6.0)
	if aiming:
		var moving := in_dir.length() > 0.1
		focus = min(1.0, focus + delta * (0.35 if moving else 0.9))
	else:
		focus = 0.0

	# movement relative to camera
	var basis_y := Basis(Vector3.UP, cam_yaw)
	var dir := basis_y * Vector3(in_dir.x, 0, in_dir.y)
	var running := Input.is_action_pressed("sprint") and not aiming
	var spd := AIM_WALK if aiming else (RUN if running else WALK)
	if Game.health_state() == "DANGER":
		spd *= 0.7
	# frost clouds (burster) slow the player via node meta, refreshed while inside
	if has_meta("slow"):
		var st: float = get_meta("slow_t", 0.0) - delta
		if st <= 0.0 and has_meta("slow_t"):
			remove_meta("slow")
			remove_meta("slow_t")
		else:
			set_meta("slow_t", st)
			spd *= float(get_meta("slow", 1.0))
	var target := dir * spd
	velocity.x = move_toward(velocity.x, target.x, delta * 20.0)
	velocity.z = move_toward(velocity.z, target.z, delta * 20.0)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.5
	move_and_slide()

	var hspeed := Vector2(velocity.x, velocity.z).length()
	# facing
	var face_yaw := model.rotation.y
	if aiming or aim_t > 0.5:
		face_yaw = cam_yaw + PI
	elif dir.length() > 0.1:
		face_yaw = atan2(dir.x, dir.z)
	model.rotation.y = lerp_angle(model.rotation.y, face_yaw, clamp(delta * (16.0 if aiming else 10.0), 0.0, 1.0))
	model.move_speed = hspeed
	model.aim = aim_t > 0.5
	model.aim_pitch = cam_pitch + 0.15
	model.pose = "normal"

	# footsteps
	if hspeed > 0.5 and is_on_floor():
		step_t -= delta * hspeed * 0.75
		if step_t <= 0.0:
			step_t = 1.0
			var surf: String = Game.current_level.get("footstep") if Game.current_level and Game.current_level.get("footstep") != null else "concrete"
			Sfx.play_at("step_" + surf, global_position, -14.0 + (4.0 if running else 0.0), randf_range(0.9, 1.1))

	# actions
	if not blocked:
		if Input.is_action_just_pressed("quick_turn") and not aiming:
			cam_yaw += PI
			model.rotation.y += PI
		if aiming and Input.is_action_pressed("fire"):
			_try_fire()
		elif not aiming and Input.is_action_just_pressed("fire") and Game.equipped == "knife":
			_knife()
		if Input.is_action_just_pressed("knife"):
			_knife()
		if Input.is_action_just_pressed("reload"):
			_start_reload()
		if Input.is_action_just_pressed("interact") and focused_interact != null and is_instance_valid(focused_interact):
			focused_interact.interact(self)
		if Input.is_action_just_pressed("flashlight"):
			flashlight.visible = not flashlight.visible
			Game.flags["flashlight_on"] = flashlight.visible
			Sfx.play("click")
		if Input.is_action_just_pressed("heal"):
			_quick_heal()
		for i in 4:
			if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
				_quick_weapon(i)
		if Input.is_action_just_pressed("inventory"):
			UI.open_inventory()
		if Input.is_action_just_pressed("pause"):
			UI.open_pause()
	if reload_t > 0.0:
		reload_t -= delta
		if reload_t <= 0.0:
			_finish_reload()

	_find_interactable()

func _process(delta: float) -> void:
	# camera rig follows smoothly
	yaw_pivot.global_position = yaw_pivot.global_position.lerp(global_position, clamp(delta * 14.0, 0.0, 1.0))
	yaw_pivot.rotation.y = cam_yaw
	pitch_pivot.rotation.x = cam_pitch + _recoil * 0.06
	arm.spring_length = lerp(2.4, 1.15, aim_t)
	arm.position = Vector3(lerp(0.45, 0.55, aim_t), lerp(0.05, 0.08, aim_t), 0)
	cam.fov = lerp(62.0, 48.0, aim_t)
	if shake > 0.0:
		cam.h_offset = randf_range(-1, 1) * shake * 0.06
		cam.v_offset = randf_range(-1, 1) * shake * 0.06
	else:
		cam.h_offset = 0.0
		cam.v_offset = 0.0
	# flashlight follows camera aim
	var fwd := -cam.global_transform.basis.z
	flashlight.global_position = global_position + Vector3(0, 1.45, 0) + model.global_transform.basis.x * -0.15 + model.global_transform.basis.z * 0.2
	flashlight.look_at(flashlight.global_position + fwd * 10.0 + Vector3(0, -0.4, 0), Vector3.UP)
	UI.set_reticle(aim_t > 0.6, focus)

# ---------------------------------------------------------------- weapons
func _equipped_is_gun() -> bool:
	var d := Game.item_def(Game.equipped)
	return Game.equipped != "" and Game.equipped != "knife" and d.get("kind", "") == "weapon"

func _quick_weapon(i: int) -> void:
	var order := ["handgun", "shotgun", "magnum", "launcher"]
	var id: String = order[i]
	if Game.has_item(id):
		Game.equipped = id
		Sfx.play("equip")
		_update_weapon_model()

func _update_weapon_model() -> void:
	if model == null:
		return
	model.hold(FX.weapon_mesh(Game.equipped) if Game.equipped != "" else null)

func _try_fire() -> void:
	if fire_cd > 0.0 or reload_t > 0.0:
		return
	var id := Game.equipped
	var d := Game.item_def(id)
	var loaded := Game.ammo_loaded(id)
	if loaded <= 0:
		fire_cd = 0.4
		Sfx.play("dry_fire")
		if Game.count_item(d.get("ammo", "")) > 0:
			_start_reload()
		return
	Game.set_ammo_loaded(id, loaded - 1)
	Game.inventory_changed.emit()
	fire_cd = d.get("rate", 0.3)
	model.play("shoot")
	muzzle_light.global_position = model.held.global_position + (-cam.global_transform.basis.z) * 0.4
	muzzle_light.light_energy = 6.0
	Sfx.play_at("shot_" + id, global_position, 0.0, randf_range(0.95, 1.05))
	Sfx.alert_noise(global_position, 25.0)
	shake = max(shake, {"handgun": 0.25, "shotgun": 0.8, "magnum": 1.0, "launcher": 0.6}.get(id, 0.3))
	_recoil = {"handgun": 0.5, "shotgun": 1.4, "magnum": 1.8, "launcher": 1.0}.get(id, 0.5)
	var pellets: int = d.get("pellets", 1)
	var spread: float = deg_to_rad(d.get("spread", 1.0)) * lerp(2.5, 0.35, focus)
	var dmg: float = d.get("damage", 20)
	var rng: float = d.get("range", 50.0)
	var origin := cam.global_position
	var fwd := -cam.global_transform.basis.z
	# start the ray at the player's shoulder depth so it doesn't hit things behind her
	origin += fwd * (arm.get_hit_length() + 0.2)
	var space := get_world_3d().direct_space_state
	for p in pellets:
		var dir := fwd.rotated(cam.global_transform.basis.x, randf_range(-spread, spread)).rotated(cam.global_transform.basis.y, randf_range(-spread, spread))
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * rng, 1 | 4)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		var end := origin + dir * rng
		if hit:
			end = hit.position
			if d.get("explosive", false):
				FX.explosion(get_tree().current_scene, hit.position, 4.5, dmg)
			else:
				var col: Object = hit.collider
				if col != null and col.has_method("take_hit"):
					var head := false
					if col.has_method("is_headshot"):
						head = col.is_headshot(hit.position)
					col.take_hit(dmg * (2.0 if head else 1.0), hit.position, dir, head)
					FX.blood_burst(get_tree().current_scene, hit.position, hit.normal)
				else:
					FX.impact(get_tree().current_scene, hit.position, hit.normal)
		FX.tracer(get_tree().current_scene, model.held.global_position + fwd * 0.3, end)
	focus = max(0.0, focus - 0.45)
	if Game.ammo_loaded(id) <= 0 and Game.count_item(d.get("ammo", "")) > 0:
		await get_tree().create_timer(0.3).timeout
		_start_reload()

func _start_reload() -> void:
	if reload_t > 0.0 or not _equipped_is_gun():
		return
	var id := Game.equipped
	var d := Game.item_def(id)
	if Game.ammo_loaded(id) >= d.get("mag", 1) or Game.count_item(d.get("ammo", "")) <= 0:
		return
	reload_t = {"shotgun": 1.6, "magnum": 1.5, "launcher": 1.4}.get(id, 1.1)
	model.play("reload")
	Sfx.play("reload")

func _finish_reload() -> void:
	var id := Game.equipped
	var d := Game.item_def(id)
	var need: int = d.get("mag", 1) - Game.ammo_loaded(id)
	var have := Game.count_item(d.get("ammo", ""))
	var take: int = min(need, have)
	if take > 0:
		Game.remove_item(d.ammo, take)
		Game.set_ammo_loaded(id, Game.ammo_loaded(id) + take)
		Game.inventory_changed.emit()

func _knife() -> void:
	if knife_cd > 0.0 or not Game.has_item("knife"):
		return
	knife_cd = 0.55
	model.play("knife")
	Sfx.play("knife_swing")
	var fwd := model.global_transform.basis.z
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not e.has_method("take_hit"):
			continue
		var to: Vector3 = e.global_position - global_position
		to.y = 0
		if to.length() < 1.7 and fwd.dot(to.normalized()) > 0.4:
			e.take_hit(12.0, e.global_position + Vector3(0, 1.2, 0), to.normalized(), false)
			Sfx.play("knife_hit")
			FX.blood_burst(get_tree().current_scene, e.global_position + Vector3(0, 1.2, 0), -to.normalized())

func _quick_heal() -> void:
	for id in ["gel", "gel_mix", "spray"]:
		if Game.has_item(id) and Game.hp < Game.MAX_HP:
			Game.use_item(id)
			return

# ---------------------------------------------------------------- damage
func hurt(amount: int, from: Vector3 = Vector3.ZERO, grab: bool = false) -> void:
	if invuln > 0.0 or Game.hp <= 0:
		return
	invuln = 1.4 if grab else 0.9
	stun = 0.8 if grab else 0.35
	model.play("hurt")
	shake = 1.0
	Sfx.play("hurt_m")
	UI.flash_damage()
	if from != Vector3.ZERO:
		var push := (global_position - from)
		push.y = 0
		velocity += push.normalized() * (4.0 if grab else 2.5)
	Game.damage(amount)

# ---------------------------------------------------------------- interaction
func _find_interactable() -> void:
	var best: Node = null
	var best_d := 2.2
	var fwd := model.global_transform.basis.z
	for n in get_tree().get_nodes_in_group("interactable"):
		if not is_instance_valid(n) or not n.is_inside_tree() or not n.get("enabled"):
			continue
		var to: Vector3 = n.global_position - global_position
		var dy: float = abs(to.y - 0.8)
		to.y = 0
		var dist := to.length()
		var r: float = n.get("radius") if n.get("radius") != null else 1.6
		if dist > r or dy > 2.0:
			continue
		var facing := fwd.dot(to.normalized()) if dist > 0.3 else 1.0
		if facing < 0.15:
			continue
		var score := dist - facing * 0.5
		if score < best_d:
			best_d = score
			best = n
	focused_interact = best
	UI.set_prompt(best.prompt if best != null else "")
