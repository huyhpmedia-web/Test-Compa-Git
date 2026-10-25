extends Node3D
## glTF character (MakeHuman body + Blender rig/animations) with the SAME driving API as actors/humanoid.gd,
## so the player, enemies and NPCs can swap `Humanoid.new()` for `CharacterModel.new()`.
##
## Owner drives it each frame by setting:
##   move_speed (m/s), aim (bool), aim_pitch (rad, + looks up), pose ("normal"|"zombie"|"crawl"|"dead"|"sit")
## and calling play("shoot"|"hurt"|"attack"|"knife"|"stagger"|"grab"|"reload"|"roar"|"heavy"|"hatchet").
## `held` is a Node3D on the right hand bone (BoneAttachment3D); hold(node) puts a weapon there.
## Leaving the "dead" pose plays a full-body "getup" automatically.
##
## Models (cfg "model"): elias, june, ruth, imogen, caretaker, rimebound_{parka_m,jacket_m,parka_f,flannel_m,tee_m,tee_f,nurse,miner,cop,patient},
##   husk, siren, burster, hanger, foreman.   (built by tools/charpipe/build_characters.py; see assets/characters/LICENSES.md)
##
## Extras: skeleton (Skeleton3D), set_bone_hidden("head") (scales the bone + its children to ~0, for gore),
##   bone_attachment("hand_l"), stretch({"upperarm": Vector3(1,1.5,1)}) (persistent bone scaling), get_materials("sac").

const MODEL_DIR := "res://assets/characters/"
const DEFAULT_MODEL := "elias"
const ZOMBIE_MODELS := ["rimebound_parka_m", "rimebound_jacket_m", "rimebound_parka_f", "rimebound_flannel_m", "rimebound_tee_m",
	"rimebound_tee_f", "rimebound_nurse", "rimebound_miner", "rimebound_cop", "rimebound_patient"]

static var _mat_cache := {}

var cfg := {}
var move_speed := 0.0
var aim := false
var pose := "normal"
var aim_pitch := 0.0          # radians, positive looks up
var death_variant := -1       # 0 back, 1 forward, 2 kneel, 3 side; -1 random
var held: Node3D              # weapon slot in the right hand

# humanoid.gd-compatible pivots (BoneAttachment3D nodes; bone-local axes: +Y runs along the bone)
var hips: Node3D
var spine: Node3D
var chest: Node3D
var neck: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var fore_l: Node3D
var fore_r: Node3D
var hand_l: Node3D
var hand_r: Node3D
var thigh_l: Node3D
var thigh_r: Node3D
var shin_l: Node3D
var shin_r: Node3D
var foot_l: Node3D
var foot_r: Node3D

var skeleton: Skeleton3D
var player: AnimationPlayer
var tree: AnimationTree
var model_root: Node3D
var model_name := ""
var _s := 1.0                 # scale relative to the 1.72 m humanoid (rime_look/kit compatibility)

# playback speeds of the mocap clips (m/s), per model from anim_meta.json
var walk_speed := 1.31
var run_speed := 3.75
var zombie_speed := 0.65

const LOOPS := ["idle", "aim_idle", "walk", "run", "zombie_idle", "zombie_walk", "crawl", "sit", "hang"]
const ONESHOTS := ["shoot", "hurt", "reload", "knife", "stagger", "attack", "grab", "roar", "heavy", "hatchet_swing"]
const ALIASES := {"hatchet": "hatchet_swing", "zombie_attack": "attack", "swing": "hatchet_swing"}
const POSES := ["normal", "zombie", "crawl", "sit", "dead", "dead_f", "dead_k", "dead_s", "hang"]
const DEATH_ANIMS := ["death", "death_fwd", "death_knees", "death_side"]
const UPPER := ["spine_01", "spine_02", "spine_03", "neck_01", "head", "clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r",
	"lowerarm_l", "lowerarm_r", "hand_l", "hand_r"]

var _os_name := ""
var _os_t := 0.0
var _os_len := 0.0
var _aim_w := 0.0
var _move_w := 0.0
var _last_pose := ""
var _ready_ok := false
var _lens := {}
var _pitch_bones := {}
var _pose_t: AnimationNodeTransition
var _dead_t := 0.0
var _age := 0.0
var _stretch := {}
var _extra_rot := {}
var _hidden := {}
var _was_dead := false
var _getup_t := 0.0

func setup(c: Dictionary) -> void:
	for k in c:
		cfg[k] = c[k]
	_build()

func _ready() -> void:
	if not _ready_ok:
		_build()

func _pick_model() -> String:
	var m: String = cfg.get("model", "")
	if m != "":
		return m
	if cfg.get("zombie", false):
		var b := String(cfg.get("body", ""))
		if b != "":
			return b
		var h: int = hash(str(cfg.get("seed", randi())))
		return ZOMBIE_MODELS[abs(h) % ZOMBIE_MODELS.size()]
	if cfg.get("female", false):
		return "june"
	return DEFAULT_MODEL

func _build() -> void:
	_ready_ok = true
	for c in get_children():
		c.queue_free()
	model_name = _pick_model()
	if cfg.has("death_variant"):
		death_variant = int(cfg.death_variant)
	var path := MODEL_DIR + model_name + ".glb"
	if not ResourceLoader.exists(path):
		push_warning("CharacterModel: missing " + path)
		return
	var ps: PackedScene = load(path)
	model_root = ps.instantiate()
	add_child(model_root)
	skeleton = _find(model_root, "Skeleton3D") as Skeleton3D
	player = _find(model_root, "AnimationPlayer") as AnimationPlayer
	_load_meta()
	var base_h := _model_height(model_name)
	if cfg.has("height"):
		var s := float(cfg.height) / base_h
		model_root.scale = Vector3.ONE * s
		_s = float(cfg.height) / 1.72
	elif cfg.has("scale"):
		model_root.scale = Vector3.ONE * float(cfg.scale)
		_s = base_h * float(cfg.scale) / 1.72
	else:
		_s = base_h / 1.72
	_fix_materials()
	_setup_held()
	_make_pivots()
	_setup_animation()
	_collect_pitch_bones()

func _model_height(n: String) -> float:
	match n:
		"elias": return 1.82
		"june": return 1.60
		"ruth": return 1.62
		"imogen": return 1.70
		"caretaker": return 1.74
		"husk": return 2.0
		"siren": return 1.9
		"burster": return 1.75
		"hanger": return 2.1
		"foreman": return 1.95
		"rimebound_parka_m": return 1.80
		"rimebound_jacket_m": return 1.74
		"rimebound_parka_f": return 1.68
		"rimebound_flannel_m": return 1.78
		"rimebound_tee_m": return 1.72
		"rimebound_tee_f": return 1.64
		"rimebound_nurse": return 1.66
		"rimebound_miner": return 1.78
		"rimebound_cop": return 1.82
		"rimebound_patient": return 1.72
	return 1.75

func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls:
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null

func _load_meta() -> void:
	var p := MODEL_DIR + "anim_meta.json"
	if FileAccess.file_exists(p):
		var d = JSON.parse_string(FileAccess.get_file_as_string(p))
		if d is Dictionary:
			var m: Dictionary = d.get(model_name, d.get("elias", {}))
			walk_speed = float(m.get("walk", {}).get("speed", walk_speed))
			run_speed = float(m.get("run", {}).get("speed", run_speed))
			zombie_speed = float(m.get("zombie_walk", {}).get("speed", zombie_speed))

# ------------------------------------------------------------------ materials (cached + shared between instances)
func _fix_materials() -> void:
	for mi in model_root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s)
			if not (mat is StandardMaterial3D):
				continue
			if not _mat_cache.has(mat):
				_mat_cache[mat] = _fixed(mat as StandardMaterial3D)
			m.set_surface_override_material(s, _mat_cache[mat])

func _fixed(src: StandardMaterial3D) -> StandardMaterial3D:
	var sm := src.duplicate() as StandardMaterial3D
	var n := String(sm.resource_name).to_lower()
	if n.contains("hair") or n.contains("brow") or n.contains("lash"):
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		sm.alpha_scissor_threshold = 0.45
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	elif n.contains("_sac_core") or n.contains("_saccore"):
		sm.emission_enabled = true
		sm.emission = Color(0.6, 1.0, 1.0)
		sm.emission_energy_multiplier = 2.5
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	elif n.contains("_sac"):
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.albedo_color = Color(0.45, 0.85, 0.9, 0.5)
		sm.emission_enabled = true
		sm.emission = Color(0.2, 0.85, 0.9)
		sm.emission_energy_multiplier = 0.9
		sm.rim_enabled = true
		sm.rim = 1.0
		sm.rim_tint = 0.4
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		sm.roughness = 0.1
	elif n.contains("_ice"):
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.albedo_color = Color(0.55, 0.8, 0.95, 0.72)
		sm.emission_enabled = true
		sm.emission = Color(0.3, 0.6, 0.85)
		sm.emission_energy_multiplier = 0.35
		sm.roughness = 0.08
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	elif n.contains("_lamp"):
		sm.emission_enabled = true
		sm.emission = Color(1.0, 0.92, 0.7)
		sm.emission_energy_multiplier = 3.0
	elif n.contains("eyes"):
		sm.roughness = 0.1
	return sm

## All (shared) materials whose name contains `substr` (e.g. "sac" for the Burster).
func get_materials(substr: String) -> Array:
	var out: Array = []
	for mi in model_root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var mat := m.get_surface_override_material(s)
			if mat and String(mat.resource_name).to_lower().contains(substr) and not out.has(mat):
				out.append(mat)
	return out

# ------------------------------------------------------------------ held item / pivots / bones
func _setup_held() -> void:
	held = Node3D.new()
	held.name = "Held"
	if skeleton == null:
		add_child(held)
		return
	var ba := bone_attachment("hand_r")
	ba.add_child(held)
	# rig hand space -> humanoid hand space (-Y down the fingers): the bone's +Y runs down the fingers.
	held.transform = Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, 0.07, 0))

## Attachment point following a bone (use for frost growths, hard-hat lamps, etc.).
func bone_attachment(bone_name: String) -> BoneAttachment3D:
	if skeleton == null or skeleton.find_bone(bone_name) < 0:
		return null
	var nm := "BA_" + bone_name
	var ex := skeleton.get_node_or_null(nm)
	if ex:
		return ex as BoneAttachment3D
	var ba := BoneAttachment3D.new()
	ba.name = nm
	ba.bone_name = bone_name
	skeleton.add_child(ba)
	return ba

func _make_pivots() -> void:
	hips = bone_attachment("pelvis")
	spine = bone_attachment("spine_01")
	chest = bone_attachment("spine_03")
	neck = bone_attachment("neck_01")
	head = bone_attachment("head")
	arm_l = bone_attachment("upperarm_l")
	arm_r = bone_attachment("upperarm_r")
	fore_l = bone_attachment("lowerarm_l")
	fore_r = bone_attachment("lowerarm_r")
	hand_l = bone_attachment("hand_l")
	hand_r = bone_attachment("hand_r")
	thigh_l = bone_attachment("thigh_l")
	thigh_r = bone_attachment("thigh_r")
	shin_l = bone_attachment("calf_l")
	shin_r = bone_attachment("calf_r")
	foot_l = bone_attachment("foot_l")
	foot_r = bone_attachment("foot_r")

func hold(node: Node3D) -> void:
	if held == null:
		return
	for c in held.get_children():
		c.queue_free()
	if node != null:
		held.add_child(node)

## Scale every bone whose name contains `substr` (and so everything skinned to / parented under it) to ~0.
## For gore: set_bone_hidden("head") blows off the head, set_bone_hidden("upperarm_l") an arm, ("calf") the lower legs...
func set_bone_hidden(substr: String, hidden := true) -> void:
	if skeleton == null:
		return
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_name(i).contains(substr):
			if hidden:
				_hidden[i] = true
			else:
				_hidden.erase(i)
				skeleton.set_bone_pose_scale(i, _stretch_for(i))

func is_bone_hidden(substr: String) -> bool:
	if skeleton == null:
		return false
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_name(i).contains(substr) and _hidden.has(i):
			return true
	return false

## Persistent bone scaling, e.g. stretch({"upperarm": Vector3(1, 1.5, 1), "thigh": Vector3(1, 1.25, 1)}) (Y runs along a bone).
func stretch(map: Dictionary) -> void:
	_stretch = map

func _stretch_for(i: int) -> Vector3:
	var bn := skeleton.get_bone_name(i)
	for k in _stretch:
		if bn.contains(k):
			return _stretch[k]
	return Vector3.ONE

## Additive local rotation (euler, radians) on a bone, re-applied after the animation every frame.
## Head/neck/spine bones are y-up / z-forward: x = nod forward(+) / back(-), y = turn, z = tilt.
func add_bone_rotation(bone: String, euler: Vector3) -> void:
	if skeleton == null:
		return
	var i := skeleton.find_bone(bone)
	if i >= 0:
		_extra_rot[i] = Basis.from_euler(euler).get_rotation_quaternion()

func clear_bone_rotations() -> void:
	_extra_rot.clear()

func _apply_extra_rot() -> void:
	for i in _extra_rot:
		skeleton.set_bone_pose_rotation(i, skeleton.get_bone_pose_rotation(i) * _extra_rot[i])

func _apply_bone_scales() -> void:
	if skeleton == null:
		return
	if _stretch.is_empty() and _hidden.is_empty():
		return
	for i in skeleton.get_bone_count():
		if _hidden.has(i):
			skeleton.set_bone_pose_scale(i, Vector3.ONE * 0.001)
		elif not _stretch.is_empty():
			skeleton.set_bone_pose_scale(i, _stretch_for(i))

# ------------------------------------------------------------------ animation tree
func _setup_animation() -> void:
	if player == null:
		return
	for an in player.get_animation_list():
		var a := player.get_animation(an)
		a.loop_mode = Animation.LOOP_LINEAR if an in LOOPS else Animation.LOOP_NONE
		_lens[an] = a.length
	var bt := AnimationNodeBlendTree.new()
	var fn := func(anim: String) -> AnimationNodeAnimation:
		var n := AnimationNodeAnimation.new()
		n.animation = anim if player.has_animation(anim) else "idle"
		return n
	# --- normal locomotion: idle <-> (walk/run blend space, time scaled)
	var bs := AnimationNodeBlendSpace1D.new()
	bs.min_space = 0.0
	bs.max_space = run_speed + 0.5
	bs.sync = true
	bs.add_blend_point(fn.call("walk"), walk_speed)
	bs.add_blend_point(fn.call("run"), run_speed)
	bt.add_node("bs_move", bs, Vector2(-600, 0))
	bt.add_node("ts_move", AnimationNodeTimeScale.new(), Vector2(-400, 0))
	bt.connect_node("ts_move", 0, "bs_move")
	bt.add_node("a_idle", fn.call("idle"), Vector2(-600, -150))
	bt.add_node("mix_move", AnimationNodeBlend2.new(), Vector2(-200, -50))
	bt.connect_node("mix_move", 0, "a_idle")
	bt.connect_node("mix_move", 1, "ts_move")
	# --- zombie locomotion
	bt.add_node("a_zidle", fn.call("zombie_idle"), Vector2(-600, 250))
	bt.add_node("a_zwalk", fn.call("zombie_walk"), Vector2(-600, 350))
	bt.add_node("ts_z", AnimationNodeTimeScale.new(), Vector2(-400, 350))
	bt.connect_node("ts_z", 0, "a_zwalk")
	bt.add_node("mix_z", AnimationNodeBlend2.new(), Vector2(-200, 300))
	bt.connect_node("mix_z", 0, "a_zidle")
	bt.connect_node("mix_z", 1, "ts_z")
	# --- crawl / sit / dead variants
	bt.add_node("a_crawl", fn.call("crawl"), Vector2(-600, 450))
	bt.add_node("ts_crawl", AnimationNodeTimeScale.new(), Vector2(-400, 450))
	bt.connect_node("ts_crawl", 0, "a_crawl")
	bt.add_node("a_sit", fn.call("sit"), Vector2(-600, 550))
	for i in 4:
		bt.add_node("a_dead%d" % i, fn.call(DEATH_ANIMS[i]), Vector2(-700, 650 + i * 80))
		bt.add_node("ts_dead%d" % i, AnimationNodeTimeScale.new(), Vector2(-450, 650 + i * 80))
		bt.connect_node("ts_dead%d" % i, 0, "a_dead%d" % i)
	_pose_t = AnimationNodeTransition.new()
	_pose_t.input_count = POSES.size()
	for i in POSES.size():
		_pose_t.set_input_name(i, POSES[i])
	_pose_t.xfade_time = 0.18
	bt.add_node("pose", _pose_t, Vector2(100, 150))
	bt.connect_node("pose", 0, "mix_move")
	bt.connect_node("pose", 1, "mix_z")
	bt.connect_node("pose", 2, "ts_crawl")
	bt.connect_node("pose", 3, "a_sit")
	for i in 4:
		bt.connect_node("pose", 4 + i, "ts_dead%d" % i)
	bt.add_node("a_hang", fn.call("hang"), Vector2(-600, 1000))
	bt.connect_node("pose", 8, "a_hang")
	# --- aim layer (upper body only)
	bt.add_node("a_aim", fn.call("aim_idle"), Vector2(100, -100))
	var aim_b := AnimationNodeBlend2.new()
	aim_b.filter_enabled = true
	_filter_upper(aim_b)
	bt.add_node("aim", aim_b, Vector2(350, 100))
	bt.connect_node("aim", 0, "pose")
	bt.connect_node("aim", 1, "a_aim")
	# --- one shots: upper body, plus a full-body get-up
	var last := "aim"
	var x := 600
	for os in ONESHOTS:
		var o := AnimationNodeOneShot.new()
		o.filter_enabled = true
		_filter_upper(o)
		o.fadein_time = 0.06
		o.fadeout_time = 0.18
		bt.add_node("os_" + os, o, Vector2(x, 100))
		bt.add_node("an_" + os, fn.call(os), Vector2(x, -150))
		bt.connect_node("os_" + os, 0, last)
		bt.connect_node("os_" + os, 1, "an_" + os)
		last = "os_" + os
		x += 250
	var gu := AnimationNodeOneShot.new()
	gu.fadein_time = 0.05
	gu.fadeout_time = 0.3
	bt.add_node("os_getup", gu, Vector2(x, 100))
	bt.add_node("an_getup", fn.call("getup"), Vector2(x, -150))
	bt.connect_node("os_getup", 0, last)
	bt.connect_node("os_getup", 1, "an_getup")
	bt.connect_node("output", 0, "os_getup")
	tree = AnimationTree.new()
	tree.name = "AnimTree"
	tree.tree_root = bt
	add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true

func _filter_upper(node) -> void:
	if not player.has_animation("idle"):
		return
	var a: Animation = player.get_animation("idle")
	for i in a.get_track_count():
		var p := a.track_get_path(i)
		var bone := String(p.get_concatenated_subnames())
		if bone in UPPER or bone.begins_with("thumb_") or bone.begins_with("index_") or bone.begins_with("middle_") \
				or bone.begins_with("ring_") or bone.begins_with("pinky_"):
			node.set_filter_path(p, true)

# ------------------------------------------------------------------ driving API
func play(anim: String) -> void:
	anim = ALIASES.get(anim, anim)
	if tree == null:
		return
	if anim == "getup":
		tree.set("parameters/os_getup/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		_os_name = "getup"; _os_t = 0.0; _os_len = float(_lens.get("getup", 2.0))
		return
	if not (anim in ONESHOTS):
		anim = "hurt"
	_os_name = anim
	_os_t = 0.0
	_os_len = float(_lens.get(anim, 0.6))
	tree.set("parameters/os_%s/request" % anim, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func is_playing(anim: String = "") -> bool:
	if _os_name == "":
		return false
	anim = ALIASES.get(anim, anim)
	return anim == "" or _os_name == anim

func _process(delta: float) -> void:
	if tree == null:
		return
	_age += delta
	if _os_name != "":
		_os_t += delta
		if _os_t >= _os_len:
			_os_name = ""
	var spd := move_speed
	var dead_now := pose == "dead"
	# pose transitions
	if pose != _last_pose:
		var prev := _last_pose
		_last_pose = pose
		var req := pose if pose in ["normal", "zombie", "crawl", "sit", "hang"] else "normal"
		if dead_now:
			var v := death_variant if death_variant >= 0 else randi() % 4
			req = ["dead", "dead_f", "dead_k", "dead_s"][v % 4]
			for os in ONESHOTS:
				tree.set("parameters/os_%s/request" % os, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
			_os_name = ""
			# spawned already dead (sleepers, corpses): jump straight to the final frame
			var instant := _age < 0.25
			_pose_t.xfade_time = 0.0 if instant else 0.18
			for i in 4:
				tree.set("parameters/ts_dead%d/scale" % i, 60.0 if instant else 1.0)
			_dead_t = 0.0 if not instant else -1.0
		else:
			_pose_t.xfade_time = 0.18
			if _was_dead and _age > 0.5:
				play("getup")
		tree.set("parameters/pose/transition_request", req)
		_was_dead = dead_now
	if dead_now and _dead_t < 0.0 and _age > 0.4:
		for i in 4:
			tree.set("parameters/ts_dead%d/scale" % i, 1.0)
		_dead_t = 0.0
	# normal locomotion
	_move_w = move_toward(_move_w, clampf(inverse_lerp(0.05, 0.6, spd), 0.0, 1.0), delta * 6.0)
	tree.set("parameters/mix_move/blend_amount", _move_w)
	var bsp: float = clampf(spd, walk_speed, run_speed)
	tree.set("parameters/bs_move/blend_position", bsp)
	tree.set("parameters/ts_move/scale", clampf(spd / maxf(bsp, 0.1), 0.5, 1.6))
	# zombie
	tree.set("parameters/mix_z/blend_amount", clampf(inverse_lerp(0.05, 0.4, spd), 0.0, 1.0))
	tree.set("parameters/ts_z/scale", clampf(spd / zombie_speed, 0.6, 2.4))
	tree.set("parameters/ts_crawl/scale", clampf(spd / 0.6, 0.35, 2.0) if spd > 0.05 else 0.0)
	# aim layer
	var want := 1.0 if (aim and pose == "normal") else 0.0
	_aim_w = move_toward(_aim_w, want, delta * 7.0)
	tree.set("parameters/aim/blend_amount", _aim_w)
	tree.advance(delta)
	_apply_aim_pitch()
	_apply_extra_rot()
	_apply_bone_scales()

# aim pitch: bend the spine/head about the character's lateral axis (after animation)
func _collect_pitch_bones() -> void:
	_pitch_bones.clear()
	if skeleton == null:
		return
	for b in [["spine_02", 0.3], ["spine_03", 0.35], ["head", 0.25]]:
		var i := skeleton.find_bone(b[0])
		if i >= 0:
			_pitch_bones[i] = b[1]

func _apply_aim_pitch() -> void:
	if skeleton == null or _aim_w < 0.01 or absf(aim_pitch) < 0.002:
		return
	var axis := (skeleton.global_transform.basis.inverse() * global_transform.basis * Vector3.RIGHT).normalized()
	for i in _pitch_bones:
		var ang: float = -aim_pitch * float(_pitch_bones[i]) * _aim_w
		var par := skeleton.get_bone_parent(i)
		var pg := skeleton.get_bone_global_pose(par).basis if par >= 0 else Basis.IDENTITY
		var r := Basis(axis, ang)
		var local_rot := (pg.inverse() * r * pg) * Basis(skeleton.get_bone_pose_rotation(i))
		skeleton.set_bone_pose_rotation(i, local_rot.get_rotation_quaternion())
