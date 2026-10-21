extends CharacterBody3D
## Friendly NPC (not in the "enemy" group; group "npc"). Built on the humanoid model API
## (actors/humanoid.gd now; actors/character_model.gd later: set cfg "model" to its path).
##
## Usage:   var n := NPC.spawn(self, "june", Vector3(...), yaw)        # or:
##          var n = NPC.new(); n.setup_npc(NPC.preset("ruth")); add_child(n)
## Props:   follow_player := false, follow_dist := 2.0, talk_lines: Array, display_name
##          (talk_lines entries: ["SPEAKER", "text"] or plain strings -> speaker = display name)
## Methods: await walk_to(pos) (navigation), look_at_player(), set_pose(p), sit(), die()
## Poses:   "stand" | "sit" | "cower" | "lean" | "dead"
## Presets: june | ruth | imogen | caretaker | miner_corpse
## Talk prompt: an Interactable ("Talk to <name>") like levels/level.gd; emits `talked`.

signal talked
signal died_npc

const Humanoid = preload("res://actors/humanoid.gd")
const Interactable = preload("res://world/interactable.gd")
const Kit = preload("res://actors/kit.gd")
const RimeLook = preload("res://actors/rime_look.gd")

var display_name := "Stranger"
var follow_player := false
var follow_dist := 2.0
var talk_lines: Array = []
var prompt_verb := "Talk to"
var cfg: Dictionary = {}
var model: Node3D
var nav: NavigationAgent3D
var interact_node: Node3D
var corpse := false
var is_dead := false
var pose_name := "stand"

var _walking := false
var _goal := Vector3.ZERO
var _walk_speed := 2.0
var _repath := 0.0
var _turn_to := 0.0
var _built := false

# ------------------------------------------------------------------ presets
static func preset(name: String) -> Dictionary:
	match name:
		"june":
			return {"id": "june", "display_name": "June",
				"look": {"height": 1.6, "female": true, "bulk": 0.88, "skin": Color(0.9, 0.75, 0.68), "hair": Color(0.33, 0.2, 0.11), "hair_style": "ponytail",
					"shirt": Color(0.7, 0.72, 0.75), "pants": Color(0.14, 0.16, 0.24), "coat": true, "coat_color": Color(0.14, 0.3, 0.38), "shoes": Color(0.12, 0.1, 0.1)},
				"extras": ["knit_hat", "headphones"], "pose": "stand",
				"talk_lines": [["JUNE", "Dad. You actually came."], ["JUNE", "Don't look at me like that. I'm fine. I'm just cold."]]}
		"ruth":
			return {"id": "ruth", "display_name": "Ruth",
				"look": {"height": 1.62, "female": true, "bulk": 0.95, "skin": Color(0.84, 0.74, 0.7), "hair": Color(0.65, 0.63, 0.65), "hair_style": "short",
					"shirt": Color(0.42, 0.27, 0.35), "pants": Color(0.2, 0.2, 0.25), "coat": false},
				"extras": ["glasses_chain"], "pose": "stand",
				"talk_lines": [["RUTH", "Elias. You're letting the cold in."], ["RUTH", "Tom's calling from downstairs. Can't you hear him?"]]}
		"imogen":
			return {"id": "imogen", "display_name": "Dr. Hart",
				"look": {"height": 1.7, "female": true, "bulk": 0.95, "skin": Color(0.8, 0.64, 0.54), "hair": Color(0.1, 0.07, 0.06), "hair_style": "short",
					"shirt": Color(0.3, 0.32, 0.36), "pants": Color(0.15, 0.17, 0.2), "coat": true, "coat_color": Color(0.1, 0.19, 0.3)},
				"extras": ["glasses", "northline_patch"], "pose": "stand",
				"talk_lines": [["IMOGEN", "Eight months. I reported it eight months ago."], ["IMOGEN", "I need a sample. Bring me one and I'll tell you everything."]]}
		"caretaker":
			return {"id": "caretaker", "display_name": "Caretaker",
				"look": {"height": 1.75, "female": false, "bulk": 1.12, "skin": Color(0.72, 0.58, 0.5), "hair": Color(0.6, 0.6, 0.6), "hair_style": "buzz",
					"shirt": Color(0.34, 0.37, 0.4), "pants": Color(0.18, 0.22, 0.18), "coat": true, "coat_color": Color(0.22, 0.24, 0.2)},
				"extras": ["keys"], "pose": "stand",
				"talk_lines": [["CARETAKER", "Boiler's been dead since Tuesday. I told them."], ["CARETAKER", "Something dragged Pete down the hall. Heavy. Slow."]]}
		"miner_corpse":
			return {"id": "miner_corpse", "display_name": "Frozen miner", "corpse": true, "prompt_verb": "Examine",
				"look": {"height": 1.78, "female": false, "bulk": 1.2, "zombie": true, "skin": Color(0.6, 0.5, 0.45), "hair_style": "short", "bloody": 0.3,
					"shirt": Color(0.34, 0.13, 0.1), "pants": Color(0.13, 0.17, 0.27), "gloves": true},
				"extras": ["hardhat_dead", "rime"], "pose": "dead",
				"talk_lines": [["", "A miner. Frozen where he lay down to rest. A crystal grows from his open mouth."]]}
	return {"id": name, "display_name": name.capitalize(), "look": {}, "extras": [], "pose": "stand", "talk_lines": []}

## Convenience: create, configure and add an NPC.
static func spawn(parent: Node, name: String, pos: Vector3, yaw := 0.0, overrides := {}) -> Node3D:
	var n: Node3D = load("res://actors/npc.gd").new()
	var c := preset(name)
	c.merge(overrides, true)
	n.setup_npc(c)
	n.position = pos
	n.rotation.y = yaw
	parent.add_child(n)
	return n

# ------------------------------------------------------------------ setup
func setup_npc(c: Dictionary) -> void:
	cfg = c
	display_name = c.get("display_name", display_name)
	follow_dist = c.get("follow_dist", follow_dist)
	follow_player = c.get("follow_player", follow_player)
	corpse = c.get("corpse", false)
	prompt_verb = c.get("prompt_verb", prompt_verb)
	talk_lines = c.get("talk_lines", []).duplicate(true)
	if _built:
		if model:
			model.queue_free()
	_build(c)
	set_pose(c.get("pose", "stand"))

func _ready() -> void:
	add_to_group("npc")
	collision_layer = 8
	collision_mask = 1
	if not _built:
		setup_npc(cfg if not cfg.is_empty() else preset("june"))

func _build(c: Dictionary) -> void:
	_built = true
	if get_child_count() == 0 or nav == null:
		var col := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.3
		cap.height = 1.7
		col.shape = cap
		col.position.y = 0.85
		add_child(col)
		nav = NavigationAgent3D.new()
		nav.path_desired_distance = 0.5
		nav.target_desired_distance = 0.6
		nav.radius = 0.35
		add_child(nav)
		interact_node = Interactable.new()
		interact_node.radius = 2.0
		interact_node.position = Vector3(0, 1.0, 0)
		interact_node.action = func(_p): _talk()
		add_child(interact_node)
	interact_node.prompt = "%s %s" % [prompt_verb, display_name]
	var mp: String = c.get("model", "res://actors/humanoid.gd")
	model = load(mp).new()
	var look: Dictionary = c.get("look", {})
	model.setup(look)
	add_child(model)
	var s := 1.0
	var sv = model.get("_s")
	if sv != null:
		s = float(sv)
	for ex in c.get("extras", []):
		_extra(ex, s)
	Kit.post(model, _post)

func _extra(name: String, s: float) -> void:
	var head: Node3D = model.get("head")
	var chest: Node3D = model.get("chest")
	var hips: Node3D = model.get("hips")
	match name:
		"knit_hat":
			var col := Kit.mat("cloth_dark").duplicate() as StandardMaterial3D
			col.albedo_color = Color(0.55, 0.12, 0.14)
			Kit.sphere(head, 0.118 * s, col, Vector3(0, 0.15, -0.005) * s, Vector3(1.0, 0.85, 1.08))
			Kit.sphere(head, 0.122 * s, col, Vector3(0, 0.125, -0.005) * s, Vector3(1.0, 0.35, 1.08))
			Kit.sphere(head, 0.035 * s, col, Vector3(0, 0.255, -0.005) * s)
		"headphones":
			var blk := Kit.mat("iron")
			for i in 10:
				var a := PI * float(i) / 9.0
				var b := Kit.box(head, Vector3(0.02, 0.026, 0.02) * s, blk, Vector3(cos(a) * 0.118, 0.095 + sin(a) * 0.125, 0.0) * s)
				b.rotation.z = a + PI * 0.5
			for x in [-1.0, 1.0]:
				Kit.limb(head, Vector3(x * 0.1, 0.095, 0) * s, Vector3(x * 0.128, 0.095, 0) * s, 0.048 * s, 0.048 * s, blk)
		"glasses", "glasses_chain":
			var fr := Kit.mat("iron")
			for x in [-1.0, 1.0]:
				var tm := TorusMesh.new()
				tm.inner_radius = 0.02 * s
				tm.outer_radius = 0.024 * s
				var r := Kit.mi(head, tm, fr, Vector3(x * 0.038, 0.113, 0.1) * s)
				r.rotation.x = PI * 0.5
				Kit.box(head, Vector3(0.01, 0.01, 0.1) * s, fr, Vector3(x * 0.1, 0.115, 0.05) * s)
			Kit.box(head, Vector3(0.02, 0.008, 0.008) * s, fr, Vector3(0, 0.118, 0.103) * s)
		"northline_patch":
			Kit.box(chest, Vector3(0.07, 0.04, 0.012) * s, Kit.mat("hivis"), Vector3(0.09, 0.2, 0.125) * s)
		"keys":
			for i in 4:
				Kit.box(hips, Vector3(0.015, 0.06, 0.004) * s, Kit.mat("iron"), Vector3(0.14 + i * 0.01, -0.02 - i * 0.01, 0.05) * s)
			Kit.box(hips, Vector3(0.03, 0.03, 0.01) * s, Kit.mat("iron"), Vector3(0.14, 0.03, 0.05) * s)
		"hardhat_dead":
			Kit.hardhat(head, s, false)
		"rime":
			RimeLook.decorate(model, 1.3, 11)
			for k in 6:
				Kit.sphere(chest, 0.06 * s, Kit.mat("frost"), Vector3(randf_range(-0.14, 0.14), randf_range(-0.1, 0.2), 0.09) * s, Vector3(1.4, 0.7, 0.4))

# ------------------------------------------------------------------ behaviour
func _post(delta: float) -> void:
	if model == null or is_dead:
		return
	var m = model
	if m.get("hips") == null:
		return
	var tt := Time.get_ticks_msec() * 0.001
	match pose_name:
		"sit":
			m.hips.position.y = 0.52 * float(m._s)
			m.thigh_l.rotation = Vector3(-1.5, 0, -0.05)
			m.thigh_r.rotation = Vector3(-1.5, 0, 0.05)
			m.shin_l.rotation.x = 1.5
			m.shin_r.rotation.x = 1.5
			m.foot_l.rotation.x = -0.1
			m.foot_r.rotation.x = -0.1
			m.arm_l.rotation = Vector3(-0.7, 0, -0.1)
			m.arm_r.rotation = Vector3(-0.7, 0, 0.1)
			m.fore_l.rotation = Vector3(-0.9, 0, 0)
			m.fore_r.rotation = Vector3(-0.9, 0, 0)
			m.spine.rotation.x = 0.12
		"cower":
			m.hips.position.y = 0.55 * float(m._s)
			m.thigh_l.rotation = Vector3(-1.9, 0, 0.15)
			m.thigh_r.rotation = Vector3(-1.9, 0, -0.15)
			m.shin_l.rotation.x = 2.1
			m.shin_r.rotation.x = 2.1
			m.spine.rotation.x = 0.7
			m.chest.rotation.x = 0.2
			m.head.rotation = Vector3(0.4, sin(tt * 0.5) * 0.3, 0)
			m.arm_l.rotation = Vector3(-1.2, 0.5, 0.3)
			m.arm_r.rotation = Vector3(-1.2, -0.5, -0.3)
			m.fore_l.rotation = Vector3(-1.8, 0, 0)
			m.fore_r.rotation = Vector3(-1.8, 0, 0)
		"lean":
			m.spine.rotation.x = -0.05
			m.arm_l.rotation = Vector3(-0.3, 0, -0.1)
			m.arm_r.rotation = Vector3(-0.9, 0, 0.1)
			m.fore_r.rotation = Vector3(-1.4, 0, 0)
	# glance at the player when close
	var p = Game.player
	if p != null and is_instance_valid(p) and pose_name != "cower" and m.get("head") != null:
		var to: Vector3 = p.global_position - global_position
		if to.length() < 6.0:
			var yaw := wrapf(atan2(to.x, to.z) - rotation.y, -PI, PI)
			m.head.rotation.y = lerp_angle(m.head.rotation.y, clamp(yaw, -0.9, 0.9), clamp(delta * 4.0, 0.0, 1.0))

func set_pose(p: String) -> void:
	pose_name = p
	if model == null:
		return
	if p == "dead":
		model.pose = "dead"
	else:
		model.pose = "normal"

func sit() -> void:
	set_pose("sit")

func look_at_player() -> void:
	var p = Game.player
	if p == null or not is_instance_valid(p):
		return
	var to: Vector3 = p.global_position - global_position
	var yaw := atan2(to.x, to.z)
	var tw := create_tween()
	tw.tween_property(self, "rotation:y", rotation.y + wrapf(yaw - rotation.y, -PI, PI), 0.35)

func die() -> void:
	if is_dead:
		return
	is_dead = true
	set_pose("dead")
	if interact_node:
		interact_node.enabled = false
	follow_player = false
	_walking = false
	Sfx.play_at("npc_death", global_position)
	died_npc.emit()

func walk_to(pos: Vector3, spd := 2.0) -> void:
	_goal = pos
	_walk_speed = spd
	_walking = true
	_repath = 0.0
	var t := 0.0
	while _walking and is_inside_tree() and not is_dead:
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > 40.0:
			break
	_walking = false

func _talk() -> void:
	if is_dead and not corpse:
		return
	look_at_player()
	var lines: Array = []
	for ln in talk_lines:
		if ln is Array:
			lines.append(ln)
		else:
			lines.append([display_name.to_upper(), str(ln)])
	if lines.is_empty():
		return
	await UI.dialogue(lines)
	talked.emit()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = -0.5
	var want := Vector3.ZERO
	var spd := 0.0
	if is_dead or pose_name in ["sit", "cower", "dead", "lean"]:
		velocity.x = 0
		velocity.z = 0
	elif _walking:
		var d := _goal - global_position
		d.y = 0
		if d.length() < 0.6:
			_walking = false
		else:
			want = _path_dir(_goal, delta)
			spd = _walk_speed
	elif follow_player and Game.player != null and is_instance_valid(Game.player):
		var pp: Vector3 = Game.player.global_position
		var d2 := pp - global_position
		d2.y = 0
		if d2.length() > follow_dist + 0.6:
			want = _path_dir(pp, delta)
			spd = 2.3 if d2.length() < 6.0 else 4.0
		elif d2.length() < follow_dist * 0.6:
			want = -d2.normalized()
			spd = 1.0
	if want.length() > 0.01:
		velocity.x = move_toward(velocity.x, want.x * spd, delta * 10.0)
		velocity.z = move_toward(velocity.z, want.z * spd, delta * 10.0)
		rotation.y = lerp_angle(rotation.y, atan2(want.x, want.z), clamp(delta * 8.0, 0.0, 1.0))
	else:
		velocity.x = move_toward(velocity.x, 0, delta * 10.0)
		velocity.z = move_toward(velocity.z, 0, delta * 10.0)
		if follow_player and not is_dead and Game.player != null and is_instance_valid(Game.player):
			var tp: Vector3 = Game.player.global_position - global_position
			rotation.y = lerp_angle(rotation.y, atan2(tp.x, tp.z), clamp(delta * 3.0, 0.0, 1.0))
	move_and_slide()
	if model:
		model.move_speed = Vector2(velocity.x, velocity.z).length()

func _path_dir(p: Vector3, delta: float) -> Vector3:
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
	return dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
