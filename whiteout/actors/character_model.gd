extends Node3D
## glTF character (MakeHuman body + Blender rig/animations) with the SAME driving API as actors/humanoid.gd,
## so the player, enemies and NPCs can swap `Humanoid.new()` for `CharacterModel.new()`.
##
## Owner drives it each frame by setting:
##   move_speed (m/s), aim (bool), aim_pitch (rad, + looks up), pose ("normal"|"zombie"|"crawl"|"dead"|"sit")
## and calling play("shoot"|"hurt"|"attack"|"knife"|"stagger"|"grab"|"reload"|"roar"|"heavy"|"hatchet").
## `held` is a Node3D on the right hand bone (BoneAttachment3D); hold(node) puts a weapon there.
##
## Models (cfg "model"): elias, june, ruth, rimebound_civ_m, rimebound_civ_f, rimebound_miner, rimebound_nurse
## Built by tools/charpipe/build_characters.py (see assets/characters/LICENSES.md).

const MODEL_DIR := "res://assets/characters/"
const DEFAULT_MODEL := "elias"
const ZOMBIE_DEFAULT_MODELS := ["rimebound_civ_m", "rimebound_civ_f", "rimebound_miner", "rimebound_nurse"]

var cfg := {}
var move_speed := 0.0
var aim := false
var pose := "normal"
var aim_pitch := 0.0          # radians, positive looks up
var held: Node3D              # weapon slot in the right hand

var skeleton: Skeleton3D
var player: AnimationPlayer
var tree: AnimationTree
var model_root: Node3D

# playback speeds of the mocap clips (m/s) - assets/characters/anim_meta.json overrides
var walk_speed := 1.31
var run_speed := 3.75
var zombie_speed := 0.65

const LOOPS := ["idle", "aim_idle", "walk", "run", "zombie_idle", "zombie_walk", "crawl", "sit"]
const ONESHOTS := ["shoot", "hurt", "reload", "knife", "stagger", "attack", "grab", "roar", "heavy", "hatchet_swing"]
const ALIASES := {"hatchet": "hatchet_swing", "zombie_attack": "attack", "swing": "hatchet_swing"}
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
var _height := 1.8

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
		var h: int = hash(str(cfg.get("seed", cfg.get("variant", randi()))))
		var pick := String(cfg.get("body", ""))
		if pick != "":
			return pick
		if cfg.get("female", false):
			return "rimebound_civ_f"
		match String(cfg.get("headgear", "")):
			"hat", "hardhat":
				return "rimebound_miner"
		return ZOMBIE_DEFAULT_MODELS[abs(h) % ZOMBIE_DEFAULT_MODELS.size()]
	if cfg.get("female", false):
		return "june"
	return DEFAULT_MODEL

func _build() -> void:
	_ready_ok = true
	for c in get_children():
		c.queue_free()
	var model_name := _pick_model()
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
	if cfg.has("height"):
		_height = float(cfg.height)
		var base := _model_height(model_name)
		var s := _height / base
		model_root.scale = Vector3.ONE * s
	_fix_materials()
	_setup_held()
	_setup_animation()
	_collect_pitch_bones()

func _model_height(name: String) -> float:
	match name:
		"elias": return 1.82
		"june": return 1.60
		"ruth": return 1.62
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
			walk_speed = float(d.get("walk", {}).get("speed", walk_speed))
			run_speed = float(d.get("run", {}).get("speed", run_speed))
			zombie_speed = float(d.get("zombie_walk", {}).get("speed", zombie_speed))

# ------------------------------------------------------------------ materials
func _fix_materials() -> void:
	var zombie: bool = cfg.get("zombie", false)
	for mi in model_root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s)
			if not (mat is StandardMaterial3D):
				continue
			var sm := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			var n := String(sm.resource_name).to_lower()
			if n.contains("hair") or n.contains("brow") or n.contains("lash"):
				sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				sm.alpha_scissor_threshold = 0.45
				sm.cull_mode = BaseMaterial3D.CULL_DISABLED
			if n.contains("eyes"):
				sm.roughness = 0.1
			if zombie and (n.contains("skin") or n.contains("hair")):
				var t: Color = Color(0.62, 0.72, 0.8) if n.contains("skin") else Color(0.5, 0.55, 0.6)
				sm.albedo_color = sm.albedo_color * t
			if zombie and n.contains("eyes"):
				sm.emission_enabled = true
				sm.emission = Color(0.55, 0.8, 1.0)
				sm.emission_energy_multiplier = 0.6
			m.set_surface_override_material(s, sm)

# ------------------------------------------------------------------ held item
func _setup_held() -> void:
	held = Node3D.new()
	held.name = "Held"
	if skeleton == null:
		add_child(held)
		return
	var ba := BoneAttachment3D.new()
	ba.name = "HandR"
	ba.bone_name = "hand_r"
	skeleton.add_child(ba)
	ba.add_child(held)
	# rig hand space -> humanoid hand space (-Y down the fingers, +Z sights up):
	# the bone's +Y runs down the fingers, so flip about X; thumb-up palm-inward aim pose.
	held.transform = Transform3D(Basis(Vector3.RIGHT, PI) * Basis(Vector3.UP, 0.0), Vector3(0, 0.07, 0))

func hold(node: Node3D) -> void:
	if held == null:
		return
	for c in held.get_children():
		c.queue_free()
	if node != null:
		held.add_child(node)

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
	var ts := AnimationNodeTimeScale.new()
	bt.add_node("ts_move", ts, Vector2(-400, 0))
	bt.connect_node("ts_move", 0, "bs_move")
	bt.add_node("a_idle", fn.call("idle"), Vector2(-600, -150))
	var mix := AnimationNodeBlend2.new()
	bt.add_node("mix_move", mix, Vector2(-200, -50))
	bt.connect_node("mix_move", 0, "a_idle")
	bt.connect_node("mix_move", 1, "ts_move")
	# --- zombie locomotion
	bt.add_node("a_zidle", fn.call("zombie_idle"), Vector2(-600, 250))
	bt.add_node("a_zwalk", fn.call("zombie_walk"), Vector2(-600, 350))
	var zts := AnimationNodeTimeScale.new()
	bt.add_node("ts_z", zts, Vector2(-400, 350))
	bt.connect_node("ts_z", 0, "a_zwalk")
	var zmix := AnimationNodeBlend2.new()
	bt.add_node("mix_z", zmix, Vector2(-200, 300))
	bt.connect_node("mix_z", 0, "a_zidle")
	bt.connect_node("mix_z", 1, "ts_z")
	# --- crawl / sit / dead
	bt.add_node("a_crawl", fn.call("crawl"), Vector2(-600, 450))
	var cts := AnimationNodeTimeScale.new()
	bt.add_node("ts_crawl", cts, Vector2(-400, 450))
	bt.connect_node("ts_crawl", 0, "a_crawl")
	bt.add_node("a_sit", fn.call("sit"), Vector2(-600, 550))
	bt.add_node("a_dead", fn.call("death"), Vector2(-600, 650))
	var pose_t := AnimationNodeTransition.new()
	pose_t.input_count = 5
	for i in 5:
		pose_t.set_input_name(i, ["normal", "zombie", "crawl", "sit", "dead"][i])
	pose_t.xfade_time = 0.18
	bt.add_node("pose", pose_t, Vector2(100, 150))
	bt.connect_node("pose", 0, "mix_move")
	bt.connect_node("pose", 1, "mix_z")
	bt.connect_node("pose", 2, "ts_crawl")
	bt.connect_node("pose", 3, "a_sit")
	bt.connect_node("pose", 4, "a_dead")
	# --- aim layer (upper body only)
	bt.add_node("a_aim", fn.call("aim_idle"), Vector2(100, -100))
	var aim_b := AnimationNodeBlend2.new()
	aim_b.filter_enabled = true
	_filter_upper(aim_b)
	bt.add_node("aim", aim_b, Vector2(350, 100))
	bt.connect_node("aim", 0, "pose")
	bt.connect_node("aim", 1, "a_aim")
	# --- one shots (upper body)
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
	bt.connect_node("output", 0, last)
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
	if _os_name != "":
		_os_t += delta
		if _os_t >= _os_len:
			_os_name = ""
	var spd := move_speed
	# pose
	if pose != _last_pose:
		_last_pose = pose
		var req := pose if pose in ["normal", "zombie", "crawl", "sit", "dead"] else "normal"
		tree.set("parameters/pose/transition_request", req)
		if pose == "dead":
			for os in ONESHOTS:
				tree.set("parameters/os_%s/request" % os, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
			_os_name = ""
	# normal locomotion
	_move_w = move_toward(_move_w, clampf(inverse_lerp(0.05, 0.6, spd), 0.0, 1.0), delta * 6.0)
	tree.set("parameters/mix_move/blend_amount", _move_w)
	tree.set("parameters/bs_move/blend_position", clampf(spd, walk_speed, run_speed))
	var bsp: float = clampf(spd, walk_speed, run_speed)
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
	# lateral axis of the model in skeleton space
	var axis := (skeleton.global_transform.basis.inverse() * global_transform.basis * Vector3.RIGHT).normalized()
	for i in _pitch_bones:
		var ang: float = -aim_pitch * float(_pitch_bones[i]) * _aim_w
		var par := skeleton.get_bone_parent(i)
		var pg := skeleton.get_bone_global_pose(par).basis if par >= 0 else Basis.IDENTITY
		var r := Basis(axis, ang)
		var local_rot := (pg.inverse() * r * pg) * Basis(skeleton.get_bone_pose_rotation(i))
		skeleton.set_bone_pose_rotation(i, local_rot.get_rotation_quaternion())
