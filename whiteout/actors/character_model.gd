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
	"rimebound_tee_f", "rimebound_nurse", "rimebound_miner", "rimebound_cop", "rimebound_patient",
	"rimebound_hivis_m", "rimebound_old_m", "rimebound_teen_f", "rimebound_fat_m"]

static var _mat_cache := {}

var cfg := {}
var move_speed := 0.0
var aim := false
var pose := "normal"
var aim_pitch := 0.0          # radians, positive looks up
var death_variant := -1       # 0 back, 1 forward, 2 kneel, 3 side; -1 random
var held: Node3D              # weapon slot in the right hand
var weapon_ik                 # actors/weapon_ik.gd: two-hand IK + recoil for weapons with Grip_R markers (see hold())
var aim_point := Vector3.ZERO # world point the weapon should converge on (Player sets it while aiming)

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
		push_warning("CharacterModel: missing " + path + " (falling back)")
		for fb in ["rimebound_parka_m", "elias"]:
			if ResourceLoader.exists(MODEL_DIR + fb + ".glb"):
				model_name = fb
				path = MODEL_DIR + fb + ".glb"
				break
		if not ResourceLoader.exists(path):
			_make_pivots()
			_setup_held()
			return
	var ps: PackedScene = load(path)
	model_root = ps.instantiate()
	add_child(model_root)
	skeleton = _find(model_root, "Skeleton3D") as Skeleton3D
	player = _find(model_root, "AnimationPlayer") as AnimationPlayer
	_load_meta()
	_load_anim_sets()
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
		"rimebound_hivis_m": return 1.77
		"rimebound_old_m": return 1.68
		"rimebound_teen_f": return 1.57
		"rimebound_fat_m": return 1.75
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

# ------------------------------------------------------------------ mocap animation sets (assets/anims/<set>.glb)
## Animation-only glbs (tools/charpipe/anim_export.py) on the same rig. Their clips override the clips embedded in the character
## glb by name and add new ones. Elias/NPCs use "elias", every Rimebound + special uses "zombie".
const ANIM_DIR := "res://assets/anims/"
const ZOMBIE_LIKE := ["husk", "siren", "burster", "hanger", "foreman"]
static var _set_protos := {}     # set -> {clip: Animation} straight from the glb
static var _set_remap := {}      # "set|prefix" -> {clip: Animation} with track paths pointing at this skeleton
static var _set_meta = null

func _anim_sets_for_model() -> Array:
	if model_name.begins_with("rimebound_") or model_name in ZOMBIE_LIKE:
		return ["zombie"]
	return ["elias"]

static func _proto_set(set_name: String) -> Dictionary:
	if _set_protos.has(set_name):
		return _set_protos[set_name]
	var out := {}
	var path := ANIM_DIR + set_name + ".glb"
	if ResourceLoader.exists(path):
		var ps = load(path)
		if ps is PackedScene:
			var n: Node = ps.instantiate()
			var ap := n.find_children("*", "AnimationPlayer", true, false)
			if ap.size() > 0:
				for an in (ap[0] as AnimationPlayer).get_animation_list():
					out[an] = (ap[0] as AnimationPlayer).get_animation(an)
			n.free()
	_set_protos[set_name] = out
	return out

func _load_anim_sets() -> void:
	if skeleton == null:
		return
	if player == null:
		# mesh-only character glb: the anim set(s) carry every clip
		player = AnimationPlayer.new()
		player.name = "AnimationPlayer"
		model_root.add_child(player)
		player.add_animation_library("", AnimationLibrary.new())
	var lib := player.get_animation_library("")
	if lib == null:
		return
	var prefix := String(player.get_node(player.root_node).get_path_to(skeleton))
	for set_name in _anim_sets_for_model():
		var key: String = set_name + "|" + prefix
		if not _set_remap.has(key):
			var proto := _proto_set(set_name)
			var res := {}
			for an in proto:
				var a: Animation = (proto[an] as Animation).duplicate()
				for i in a.get_track_count():
					var bn := String(a.track_get_path(i).get_concatenated_subnames())
					a.track_set_path(i, NodePath(prefix + ":" + bn))
				res[an] = a
			_set_remap[key] = res
		var set_anims: Dictionary = _set_remap[key]
		for an in set_anims:
			if lib.has_animation(an):
				lib.remove_animation(an)
			lib.add_animation(an, set_anims[an])

## Debug / contact-sheet helper: pose the rig on clip `anim` at time `t` (bypasses the AnimationTree).
func debug_pose(anim: String, t: float) -> void:
	set_process(false)
	if tree:
		tree.active = false
	if player and player.has_animation(anim):
		player.play(anim)
		player.seek(t, true)
		player.pause()
		player.advance(0.0)

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
		# scissor + alpha-to-coverage: no sorting artefacts, soft strand edges under MSAA; the scalp under the hair is painted hair-coloured
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		sm.alpha_scissor_threshold = 0.38
		sm.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		sm.roughness = 0.82
		sm.metallic_specular = 0.22
		sm.anisotropy_enabled = false
		sm.backlight_enabled = false
	elif n.ends_with("_skin"):
		# subsurface-ish skin: SSS blur + warm backlight (ears, fingers, nose against the flashlight)
		sm.subsurf_scatter_enabled = true
		sm.subsurf_scatter_strength = 0.22
		sm.subsurf_scatter_skin_mode = true
		sm.backlight_enabled = true
		sm.backlight = Color(0.32, 0.12, 0.09) if not n.contains("rimebound") else Color(0.16, 0.12, 0.14)
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
		# glacial ice plates baked into the glb: translucent, glassy, very faintly lit from within
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.albedo_color = Color(0.62, 0.8, 0.88, 0.42)
		sm.emission_enabled = true
		sm.emission = Color(0.3, 0.6, 0.78)
		sm.emission_energy_multiplier = 0.08
		sm.roughness = 0.05
		sm.metallic_specular = 0.85
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	elif n.contains("_lamp"):
		sm.emission_enabled = true
		sm.emission = Color(1.0, 0.92, 0.7)
		sm.emission_energy_multiplier = 3.0
	elif n.contains("eyes"):
		sm.roughness = 0.06
		sm.metallic_specular = 1.0
		sm.clearcoat_enabled = true
		sm.clearcoat = 1.0
		sm.clearcoat_roughness = 0.03
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
func bone_attachment(bone_name: String) -> Node3D:
	var nm := "BA_" + bone_name
	if skeleton == null or skeleton.find_bone(bone_name) < 0:
		# never null: a plain node at the model origin keeps callers (lamps, crystals, hats) safe
		var dn := get_node_or_null(nm)
		if dn == null:
			dn = Node3D.new()
			dn.name = nm
			add_child(dn)
		return dn as Node3D
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
	if weapon_ik == null and skeleton != null:
		weapon_ik = load("res://actors/weapon_ik.gd").new(self)
	if weapon_ik != null and weapon_ik.valid() and (node == null or node.has_meta("weapon_id")):
		for c in held.get_children():
			c.queue_free()
		weapon_ik.set_weapon(node)
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
## Additive hit reactions ("hit_*" clips are authored as poses; they are converted once into deltas from their first frame and
## played through ADD one-shots whose amplitude is scaled by damage via a Blend2 against an identity "_zero" twin).
const HITS := ["hit_front", "hit_back", "hit_left", "hit_right", "hit_head"]
const UPPER_SHOTS := ["shoot", "hurt", "reload", "knife", "attack", "attack_b", "grab", "roar", "heavy", "hatchet_swing", "hatchet_2",
	"hatchet_3", "flashlight", "interact", "pickup", "struggle", "bite", "shoot_long", "reload_long"]
const FULL_SHOTS := ["stagger", "lunge", "run_stop", "roll"]
const GETUPS := ["getup", "getup_back", "getup_front", "getup_side"]
const LOWER := ["pelvis", "thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r", "ball_l", "ball_r"]
const SPECIAL_WALK := {"husk": "zombie_walk_e", "siren": "zombie_walk_b", "burster": "zombie_walk_f", "hanger": "zombie_walk_g", "foreman": "zombie_walk_g"}
const STRAFE_SPEED := 1.6

var walk_variant := "zombie_walk"
var idle_variant := "zombie_idle"
var hit_dir := Vector3.ZERO        # world direction the last impact travelled (set by enemies for hit reacts + ragdoll)
var hit_power := 0.0
var allow_ragdoll := true
var _combo := 0
var _combo_t := 0.0
var _prev_spd := 0.0
var _prev_yaw := 0.0
var _yaw_rate := 0.0
var _last_pos := Vector3.ZERO
var _local_vel := Vector3.ZERO
var _strafe_w := 0.0
var _turn_l_w := 0.0
var _turn_r_w := 0.0
var _hit_amt := {}
var _meta_speeds := {}

func _clip_speed(name: String, fallback: float) -> float:
	return float(_meta_speeds.get(name, {}).get("speed", fallback))

func _load_set_meta() -> void:
	_meta_speeds.clear()
	var p := ANIM_DIR + "anim_meta.json"
	if FileAccess.file_exists(p):
		var d = JSON.parse_string(FileAccess.get_file_as_string(p))
		if d is Dictionary:
			for s in _anim_sets_for_model():
				for k in d.get(s, {}):
					_meta_speeds[k] = d[s][k]
	if _meta_speeds.has("walk") and _meta_speeds["walk"].has("speed"):
		walk_speed = float(_meta_speeds["walk"]["speed"])
	if _meta_speeds.has("run") and _meta_speeds["run"].has("speed"):
		run_speed = float(_meta_speeds["run"]["speed"])

## Convert a pose-style hit clip into deltas from its first frame (once per Animation resource) and make its identity twin.
func _prepare_hit(lib: AnimationLibrary, an: String) -> void:
	if not lib.has_animation(an):
		return
	var a: Animation = lib.get_animation(an)
	if not a.has_meta("additive"):
		# Godot's additive blending adds (value - rest). So a delta clip is stored as rest * (first-frame^-1 * frame).
		for i in a.get_track_count():
			var tt := a.track_get_type(i)
			var n := a.track_get_key_count(i)
			if n == 0:
				continue
			var bi := skeleton.find_bone(String(a.track_get_path(i).get_concatenated_subnames()))
			if bi < 0:
				continue
			var rest := skeleton.get_bone_rest(bi)
			if tt == Animation.TYPE_ROTATION_3D:
				var q0: Quaternion = a.track_get_key_value(i, 0)
				var rq := rest.basis.get_rotation_quaternion()
				for k in n:
					var q: Quaternion = a.track_get_key_value(i, k)
					a.track_set_key_value(i, k, rq * (q0.inverse() * q))
			elif tt == Animation.TYPE_POSITION_3D:
				var p0: Vector3 = a.track_get_key_value(i, 0)
				for k in n:
					a.track_set_key_value(i, k, rest.origin + ((a.track_get_key_value(i, k) as Vector3) - p0))
		for i in range(a.get_track_count() - 1, -1, -1):
			if a.track_get_type(i) == Animation.TYPE_SCALE_3D:
				a.remove_track(i)
		var z := a.duplicate() as Animation
		for i in z.get_track_count():
			var tt := z.track_get_type(i)
			var bi := skeleton.find_bone(String(z.track_get_path(i).get_concatenated_subnames()))
			if bi < 0:
				continue
			var rest := skeleton.get_bone_rest(bi)
			for k in z.track_get_key_count(i):
				if tt == Animation.TYPE_ROTATION_3D:
					z.track_set_key_value(i, k, rest.basis.get_rotation_quaternion())
				elif tt == Animation.TYPE_POSITION_3D:
					z.track_set_key_value(i, k, rest.origin)
		a.set_meta("additive", true)
		a.set_meta("zero", z)
	if not lib.has_animation(an + "_zero"):
		lib.add_animation(an + "_zero", a.get_meta("zero"))

func _is_loop_name(an: String) -> bool:
	return an in LOOPS or an.begins_with("zombie_walk") or an.begins_with("zombie_idle") or an in ["sprint", "walk_back", "walk_left", "walk_right", "turn_l", "turn_r", "zombie_run", "crawl_drag"]

func _pick_variant(prefix: String, base: String) -> String:
	var names: Array = []
	for an in player.get_animation_list():
		if an == base or (an.begins_with(prefix + "_") and an.length() == prefix.length() + 2):
			names.append(an)
	if names.is_empty():
		return base
	names.sort()
	var h: int = hash(str(cfg.get("seed", randi())))
	return names[abs(h) % names.size()]

func _setup_animation() -> void:
	if player == null:
		return
	_load_set_meta()
	var lib0 := player.get_animation_library("")
	for h in HITS:
		_prepare_hit(lib0, h)
	for an in player.get_animation_list():
		var a := player.get_animation(an)
		a.loop_mode = Animation.LOOP_LINEAR if _is_loop_name(an) else Animation.LOOP_NONE
		_lens[an] = a.length
	# per-instance variants (zombie shamble / idle); specials get their own gait
	if cfg.has("walk_variant") and player.has_animation(String(cfg.walk_variant)):
		walk_variant = String(cfg.walk_variant)
	elif SPECIAL_WALK.has(model_name) and player.has_animation(SPECIAL_WALK[model_name]):
		walk_variant = SPECIAL_WALK[model_name]
	else:
		walk_variant = _pick_variant("zombie_walk", "zombie_walk")
	idle_variant = _pick_variant("zombie_idle", "zombie_idle")
	zombie_speed = _clip_speed(walk_variant, zombie_speed)
	var bt := AnimationNodeBlendTree.new()
	var fn := func(anim: String) -> AnimationNodeAnimation:
		var n := AnimationNodeAnimation.new()
		n.animation = anim if player.has_animation(anim) else "idle"
		return n
	var have := func(anim: String) -> bool:
		return player.has_animation(anim)
	# --- normal locomotion: idle <-> (walk/run/sprint blend space, time scaled); strafe space when aiming
	var bs := AnimationNodeBlendSpace1D.new()
	bs.min_space = 0.0
	bs.max_space = run_speed + 0.5
	bs.sync = true
	bs.add_blend_point(fn.call("walk"), walk_speed)
	bs.add_blend_point(fn.call("run"), run_speed)
	if have.call("sprint"):
		bs.max_space = _clip_speed("sprint", 5.4) + 0.2
		bs.add_blend_point(fn.call("sprint"), _clip_speed("sprint", 5.4))
	bt.add_node("bs_move", bs, Vector2(-600, 0))
	bt.add_node("ts_move", AnimationNodeTimeScale.new(), Vector2(-400, 0))
	bt.connect_node("ts_move", 0, "bs_move")
	var loco_out := "ts_move"
	if have.call("walk_back") and have.call("walk_left") and have.call("walk_right"):
		var s2 := AnimationNodeBlendSpace2D.new()
		s2.min_space = Vector2(-1, -1)
		s2.max_space = Vector2(1, 1)
		s2.sync = true
		s2.add_blend_point(fn.call("walk"), Vector2(0, 1))
		s2.add_blend_point(fn.call("walk_back"), Vector2(0, -1))
		s2.add_blend_point(fn.call("walk_left"), Vector2(1, 0))
		s2.add_blend_point(fn.call("walk_right"), Vector2(-1, 0))
		bt.add_node("bs_strafe", s2, Vector2(-600, 120))
		bt.add_node("ts_strafe", AnimationNodeTimeScale.new(), Vector2(-400, 120))
		bt.connect_node("ts_strafe", 0, "bs_strafe")
		bt.add_node("mix_dir", AnimationNodeBlend2.new(), Vector2(-250, 60))
		bt.connect_node("mix_dir", 0, "ts_move")
		bt.connect_node("mix_dir", 1, "ts_strafe")
		loco_out = "mix_dir"
	bt.add_node("a_idle", fn.call("idle"), Vector2(-600, -150))
	bt.add_node("mix_move", AnimationNodeBlend2.new(), Vector2(-100, -50))
	bt.connect_node("mix_move", 0, "a_idle")
	bt.connect_node("mix_move", 1, loco_out)
	var normal_out := "mix_move"
	# turn-in-place: lower-body stepping layers driven by yaw rate while standing
	if have.call("turn_l") and have.call("turn_r"):
		for sd in ["l", "r"]:
			var tb := AnimationNodeBlend2.new()
			tb.filter_enabled = true
			for p in _track_paths_for(LOWER):
				tb.set_filter_path(p, true)
			bt.add_node("mix_turn_" + sd, tb, Vector2(100 + (0 if sd == "l" else 200), -50))
			bt.add_node("a_turn_" + sd, fn.call("turn_" + sd), Vector2(100, -200))
			bt.connect_node("mix_turn_" + sd, 0, normal_out)
			bt.connect_node("mix_turn_" + sd, 1, "a_turn_" + sd)
			normal_out = "mix_turn_" + sd
	# --- zombie locomotion
	bt.add_node("a_zidle", fn.call(idle_variant), Vector2(-600, 250))
	bt.add_node("ts_zidle", AnimationNodeTimeScale.new(), Vector2(-450, 250))
	bt.connect_node("ts_zidle", 0, "a_zidle")
	var zbs := AnimationNodeBlendSpace1D.new()
	zbs.min_space = 0.0
	zbs.max_space = 3.8
	zbs.sync = true
	zbs.add_blend_point(fn.call(walk_variant), zombie_speed)
	if have.call("zombie_run"):
		zbs.add_blend_point(fn.call("zombie_run"), maxf(_clip_speed("zombie_run", 3.5), zombie_speed + 1.2))
	bt.add_node("a_zwalk", zbs, Vector2(-600, 350))
	bt.add_node("ts_z", AnimationNodeTimeScale.new(), Vector2(-400, 350))
	bt.connect_node("ts_z", 0, "a_zwalk")
	bt.add_node("mix_z", AnimationNodeBlend2.new(), Vector2(-200, 300))
	bt.connect_node("mix_z", 0, "ts_zidle")
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
	bt.connect_node("pose", 0, normal_out)
	bt.connect_node("pose", 1, "mix_z")
	bt.connect_node("pose", 2, "ts_crawl")
	bt.connect_node("pose", 3, "a_sit")
	for i in 4:
		bt.connect_node("pose", 4 + i, "ts_dead%d" % i)
	bt.add_node("a_hang", fn.call("hang"), Vector2(-600, 1000))
	bt.connect_node("pose", 8, "a_hang")
	# --- aim layer (upper body only)
	var aim_in := "a_aim"
	bt.add_node("a_aim", fn.call("aim_idle"), Vector2(100, -100))
	if have.call("aim_long"):
		# long guns (shotgun, launcher): stock-to-shoulder two-handed pose instead of the pistol stance
		bt.add_node("a_aim_long", fn.call("aim_long"), Vector2(100, -200))
		var asel := AnimationNodeTransition.new()
		asel.input_count = 2
		asel.set_input_name(0, "pistol")
		asel.set_input_name(1, "long")
		asel.xfade_time = 0.2
		bt.add_node("aim_sel", asel, Vector2(250, -150))
		bt.connect_node("aim_sel", 0, "a_aim")
		bt.connect_node("aim_sel", 1, "a_aim_long")
		aim_in = "aim_sel"
	var aim_b := AnimationNodeBlend2.new()
	aim_b.filter_enabled = true
	_filter_upper(aim_b)
	bt.add_node("aim", aim_b, Vector2(350, 100))
	bt.connect_node("aim", 0, "pose")
	bt.connect_node("aim", 1, aim_in)
	# --- one shots: upper body (+ full-body ones), then additive hit reacts
	var last := "aim"
	var x := 600
	for os in UPPER_SHOTS + FULL_SHOTS:
		if not have.call(os) and os != "hurt":
			continue
		var o := AnimationNodeOneShot.new()
		var upper: bool = os in UPPER_SHOTS
		o.filter_enabled = upper
		if upper:
			_filter_upper(o)
		o.fadein_time = 0.06 if upper else 0.12
		o.fadeout_time = 0.18 if upper else 0.25
		bt.add_node("os_" + os, o, Vector2(x, 100))
		bt.add_node("an_" + os, fn.call(os), Vector2(x, -150))
		bt.connect_node("os_" + os, 0, last)
		bt.connect_node("os_" + os, 1, "an_" + os)
		last = "os_" + os
		x += 250
	for gu in GETUPS:
		if not have.call(gu):
			continue
		var g := AnimationNodeOneShot.new()
		g.fadein_time = 0.04
		g.fadeout_time = 0.3
		bt.add_node("os_" + gu, g, Vector2(x, 100))
		bt.add_node("an_" + gu, fn.call(gu), Vector2(x, -150))
		bt.connect_node("os_" + gu, 0, last)
		bt.connect_node("os_" + gu, 1, "an_" + gu)
		last = "os_" + gu
		x += 250
	for h in HITS:
		if not have.call(h):
			continue
		var o := AnimationNodeOneShot.new()
		o.mix_mode = AnimationNodeOneShot.MIX_MODE_ADD
		o.fadein_time = 0.02
		o.fadeout_time = 0.2
		bt.add_node("os_" + h, o, Vector2(x, 100))
		var bl := AnimationNodeBlend2.new()
		bt.add_node("amt_" + h, bl, Vector2(x, -150))
		bt.add_node("z_" + h, fn.call(h + "_zero"), Vector2(x - 100, -300))
		bt.add_node("an_" + h, fn.call(h), Vector2(x + 100, -300))
		bt.connect_node("amt_" + h, 0, "z_" + h)
		bt.connect_node("amt_" + h, 1, "an_" + h)
		bt.connect_node("os_" + h, 0, last)
		bt.connect_node("os_" + h, 1, "amt_" + h)
		last = "os_" + h
		x += 250
	bt.connect_node("output", 0, last)
	tree = AnimationTree.new()
	tree.name = "AnimTree"
	tree.tree_root = bt
	add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	_last_pos = global_position if is_inside_tree() else Vector3.ZERO
	_prev_yaw = rotation.y
	if zombie_like():
		tree.advance(randf() * 3.0)
		tree.set("parameters/ts_zidle/scale", randf_range(0.8, 1.2))

func zombie_like() -> bool:
	return model_name.begins_with("rimebound_") or model_name in ZOMBIE_LIKE

func _track_paths_for(bones: Array) -> Array:
	var out: Array = []
	if not player.has_animation("idle"):
		return out
	var a: Animation = player.get_animation("idle")
	for i in a.get_track_count():
		var p := a.track_get_path(i)
		if String(p.get_concatenated_subnames()) in bones:
			out.append(p)
	return out

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
	if anim in ["shoot", "reload"] and _long_gun() and tree.tree_root.has_node("os_%s_long" % anim):
		anim += "_long"
	if anim in ["knife", "hatchet_swing"]:
		# 3-hit combo: diagonal chop, backhand, shove (resets after a pause)
		var seq := ["hatchet_swing", "hatchet_2", "hatchet_3"]
		_combo = (_combo + 1) % 3 if _combo_t > 0.0 else 0
		_combo_t = 1.4
		anim = seq[_combo]
	elif anim == "attack" and zombie_like() and player.has_animation("attack_b") and randf() < 0.4:
		anim = "attack_b"
	elif anim == "getup":
		anim = _getup_for_variant()
		if not tree.tree_root.has_node("os_" + anim):
			anim = "getup"
		if not tree.tree_root.has_node("os_" + anim):
			return
		tree.set("parameters/os_%s/request" % anim, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		_os_name = "getup"; _os_t = 0.0; _os_len = float(_lens.get(anim, 2.0))
		return
	if not tree.tree_root.has_node("os_" + anim):
		anim = "hurt"
		if not tree.tree_root.has_node("os_hurt"):
			return
	_os_name = anim
	_os_t = 0.0
	_os_len = float(_lens.get(anim, 0.6))
	tree.set("parameters/os_%s/request" % anim, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func _long_gun() -> bool:
	return weapon_ik != null and weapon_ik.weapon != null and String(weapon_ik.get("wid")) in ["shotgun", "launcher"]

func _getup_for_variant() -> String:
	match _death_idx:
		0: return "getup_back"
		1: return "getup_front"
		3: return "getup_side"
	return "getup"

func is_playing(anim: String = "") -> bool:
	if _os_name == "":
		return false
	anim = ALIASES.get(anim, anim)
	return anim == "" or _os_name == anim

## Directional additive hit reaction. `dir` = world direction the projectile / blow travelled (towards this body).
func hit_react(dir: Vector3, dmg: float, headshot := false) -> void:
	hit_dir = dir
	hit_power = dmg
	if tree == null or pose == "dead":
		return
	var l := global_transform.basis.inverse() * dir
	var nm := "hit_front"
	if headshot and player.has_animation("hit_head"):
		nm = "hit_head"
	elif absf(l.x) > absf(l.z) * 1.1:
		nm = "hit_right" if l.x > 0.0 else "hit_left"
	elif l.z > 0.0:
		nm = "hit_back"
	if not tree.tree_root.has_node("os_" + nm):
		play("hurt")
		return
	var amt := clampf(0.35 + dmg / 40.0, 0.4, 1.0)
	tree.set("parameters/amt_%s/blend_amount" % nm, amt)
	tree.set("parameters/os_%s/request" % nm, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

## Hit from a world position (e.g. the player being clawed).
func hit_react_from(src: Vector3, dmg: float) -> void:
	hit_react((global_position - src).normalized(), dmg)

func _process(delta: float) -> void:
	if tree == null:
		return
	_age += delta
	if _os_name != "":
		_os_t += delta
		if _os_t >= _os_len:
			_os_name = ""
	_combo_t = maxf(0.0, _combo_t - delta)
	# local velocity + yaw rate come from the node itself (works for player, enemies, NPCs)
	if delta > 0.0001:
		var v := (global_position - _last_pos) / delta
		_local_vel = _local_vel.lerp(global_transform.basis.inverse() * v, clampf(delta * 12.0, 0.0, 1.0))
		_yaw_rate = lerpf(_yaw_rate, wrapf(rotation.y - _prev_yaw, -PI, PI) / delta, clampf(delta * 10.0, 0.0, 1.0))
	_last_pos = global_position
	_prev_yaw = rotation.y
	var spd := move_speed
	var dead_now := pose == "dead"
	# pose transitions
	if pose != _last_pose:
		var prev := _last_pose
		_last_pose = pose
		var req := pose if pose in ["normal", "zombie", "crawl", "sit", "hang"] else "normal"
		if dead_now:
			var v := death_variant if death_variant >= 0 else randi() % 4
			_death_idx = v % 4
			req = ["dead", "dead_f", "dead_k", "dead_s"][v % 4]
			for os in UPPER_SHOTS + FULL_SHOTS + GETUPS:
				if tree.tree_root.has_node("os_" + os):
					tree.set("parameters/os_%s/request" % os, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
			_os_name = ""
			# spawned already dead (sleepers, corpses): jump straight to the final frame
			var instant := _age < 0.25
			_pose_t.xfade_time = 0.0 if instant else 0.18
			for i in 4:
				tree.set("parameters/ts_dead%d/scale" % i, 60.0 if instant else 1.0)
			_dead_t = 0.0 if not instant else -1.0
			if not instant and allow_ragdoll:
				_rag_delay = [0.45, 0.35, 0.5, 0.4][_death_idx]
		else:
			_pose_t.xfade_time = 0.18
			_rag_delay = -1.0
			if _rag_sim != null:
				stop_ragdoll()
			if _was_dead and _age > 0.5:
				play("getup")
		tree.set("parameters/pose/transition_request", req)
		_was_dead = dead_now
	if dead_now and _dead_t < 0.0 and _age > 0.4:
		for i in 4:
			tree.set("parameters/ts_dead%d/scale" % i, 1.0)
		_dead_t = 0.0
	if _rag_delay >= 0.0:
		_rag_delay -= delta
		if _rag_delay < 0.0:
			start_ragdoll(hit_dir.normalized() * clampf(2.0 + hit_power * 0.05, 2.0, 6.0) + Vector3(0, 1.2, 0))
	# normal locomotion
	_move_w = move_toward(_move_w, clampf(inverse_lerp(0.05, 0.6, spd), 0.0, 1.0), delta * 6.0)
	tree.set("parameters/mix_move/blend_amount", _move_w)
	var bsp: float = clampf(spd, walk_speed, run_speed)
	if spd > run_speed * 1.15:
		bsp = spd
	tree.set("parameters/bs_move/blend_position", bsp)
	tree.set("parameters/ts_move/scale", clampf(spd / maxf(bsp, 0.1), 0.5, 1.6))
	if tree.tree_root.has_node("mix_dir"):
		var want_strafe := 1.0 if (aim and pose == "normal" and spd > 0.1) else 0.0
		_strafe_w = move_toward(_strafe_w, want_strafe, delta * 8.0)
		tree.set("parameters/mix_dir/blend_amount", _strafe_w)
		var lv := Vector2(_local_vel.x, _local_vel.z)
		if lv.length() > 0.05:
			lv = lv.normalized()
		tree.set("parameters/bs_strafe/blend_position", lv)
		tree.set("parameters/ts_strafe/scale", clampf(spd / STRAFE_SPEED, 0.5, 1.7))
	if tree.tree_root.has_node("mix_turn_l"):
		var standing := 1.0 if (spd < 0.25 and pose == "normal") else 0.0
		var yr := clampf(absf(_yaw_rate) / 2.2, 0.0, 1.0) * standing
		_turn_l_w = move_toward(_turn_l_w, yr if _yaw_rate > 0.0 else 0.0, delta * 6.0)
		_turn_r_w = move_toward(_turn_r_w, yr if _yaw_rate < 0.0 else 0.0, delta * 6.0)
		tree.set("parameters/mix_turn_l/blend_amount", _turn_l_w)
		tree.set("parameters/mix_turn_r/blend_amount", _turn_r_w)
	# run-to-stop
	if tree.tree_root.has_node("os_run_stop"):
		if pose == "normal" and not aim and _prev_spd > 2.8 and spd < 1.2:
			tree.set("parameters/os_run_stop/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		elif spd > 1.0 and _prev_spd <= 1.0:
			tree.set("parameters/os_run_stop/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	_prev_spd = spd
	# zombie
	tree.set("parameters/mix_z/blend_amount", clampf(inverse_lerp(0.05, 0.4, spd), 0.0, 1.0))
	var zbp: float = clampf(spd, zombie_speed, 3.8) if spd > 1.8 else zombie_speed
	tree.set("parameters/a_zwalk/blend_position", zbp)
	tree.set("parameters/ts_z/scale", clampf(spd / maxf(zbp, 0.1), 0.6, 2.4))
	tree.set("parameters/ts_crawl/scale", clampf(spd / 0.6, 0.35, 2.0) if spd > 0.05 else 0.0)
	# aim layer
	var want := 1.0 if (aim and pose == "normal") else 0.0
	_aim_w = move_toward(_aim_w, want, delta * 7.0)
	tree.set("parameters/aim/blend_amount", _aim_w)
	if tree.tree_root.has_node("aim_sel"):
		tree.set("parameters/aim_sel/transition_request", "long" if _long_gun() else "pistol")
	tree.advance(delta)
	_apply_aim_pitch()
	_apply_extra_rot()
	if weapon_ik != null and weapon_ik.weapon != null:
		weapon_ik.move_speed = spd
		weapon_ik.has_aim_point = aim and aim_point != Vector3.ZERO
		weapon_ik.aim_point_world = aim_point
		weapon_ik.update(delta)
	_apply_bone_scales()
	_update_look(delta)

var _death_idx := 0
var _rag_delay := -1.0

# ------------------------------------------------------------------ look-at head tracking (zombies watch the player)
## Manual yaw/pitch blend over neck + head after the animation (LookAtModifier3D's axis handling was unreliable on this rig).
var look_target: Node3D
var _look_w := 0.0
var _look_yaw := 0.0
var _look_pitch := 0.0
const LOOK_BONES := [["spine_03", 0.15], ["neck_01", 0.3], ["head", 0.55]]

## Make the head (and a little neck/chest) follow `n` (e.g. the player) within anatomical limits; null releases.
func set_look_target(n: Node3D) -> void:
	look_target = n

func _update_look(delta: float) -> void:
	var want := 0.0
	var ty := 0.0
	var tp := 0.0
	if look_target != null and is_instance_valid(look_target) and pose in ["zombie", "normal"] and skeleton != null and is_inside_tree():
		var d := to_local(look_target.global_position + Vector3(0, 1.45, 0)) - Vector3(0, 1.5, 0)
		if Vector2(d.x, d.z).length() > 0.2:
			want = 1.0
			ty = clampf(atan2(d.x, d.z), deg_to_rad(-75.0), deg_to_rad(75.0))
			tp = clampf(-atan2(d.y, Vector2(d.x, d.z).length()), deg_to_rad(-20.0), deg_to_rad(20.0))
	_look_w = move_toward(_look_w, want, delta * 2.5)
	_look_yaw = lerp_angle(_look_yaw, ty, clampf(delta * 5.0, 0.0, 1.0))
	_look_pitch = lerpf(_look_pitch, tp, clampf(delta * 5.0, 0.0, 1.0))
	if _look_w < 0.01 or skeleton == null:
		return
	var up := (skeleton.global_transform.basis.inverse() * global_transform.basis * Vector3.UP).normalized()
	var right := (skeleton.global_transform.basis.inverse() * global_transform.basis * Vector3.RIGHT).normalized()
	for lb in LOOK_BONES:
		var i := skeleton.find_bone(lb[0])
		if i < 0:
			continue
		var w: float = lb[1] * _look_w
		var par := skeleton.get_bone_parent(i)
		var pg := skeleton.get_bone_global_pose(par).basis if par >= 0 else Basis.IDENTITY
		var r := Basis(up, _look_yaw * w) * Basis(right, -_look_pitch * w * 0.5)
		var local_rot := (pg.inverse() * r * pg) * Basis(skeleton.get_bone_pose_rotation(i))
		skeleton.set_bone_pose_rotation(i, local_rot.get_rotation_quaternion())

# ------------------------------------------------------------------ ragdoll (death clip first, then physics takes over)
const RAG_BONES := [
	# bone, child (length), radius, mass, swing, twist
	["pelvis", "spine_02", 0.13, 12.0, 0.0, 0.0],
	["spine_02", "spine_03", 0.14, 9.0, 35.0, 20.0],
	["spine_03", "neck_01", 0.15, 10.0, 35.0, 20.0],
	["head", "", 0.10, 4.5, 40.0, 40.0],
	["upperarm_l", "lowerarm_l", 0.05, 2.2, 75.0, 40.0], ["upperarm_r", "lowerarm_r", 0.05, 2.2, 75.0, 40.0],
	["lowerarm_l", "hand_l", 0.045, 1.4, 70.0, 30.0], ["lowerarm_r", "hand_r", 0.045, 1.4, 70.0, 30.0],
	["thigh_l", "calf_l", 0.085, 8.0, 60.0, 25.0], ["thigh_r", "calf_r", 0.085, 8.0, 60.0, 25.0],
	["calf_l", "foot_l", 0.06, 4.0, 45.0, 15.0], ["calf_r", "foot_r", 0.06, 4.0, 45.0, 15.0],
]
static var _rag_live: Array = []
var _rag_sim: PhysicalBoneSimulator3D

func can_ragdoll() -> bool:
	return skeleton != null and is_inside_tree() and _hidden.is_empty() and absf(model_root.scale.x - 1.0) < 0.12 \
		and skeleton.find_bone("pelvis") >= 0

func start_ragdoll(impulse: Vector3 = Vector3.ZERO) -> void:
	if not can_ragdoll():
		return
	if _rag_sim == null:
		_rag_sim = PhysicalBoneSimulator3D.new()
		_rag_sim.name = "Ragdoll"
		skeleton.add_child(_rag_sim)
		for r in RAG_BONES:
			var bi := skeleton.find_bone(r[0])
			if bi < 0:
				continue
			var ln := 0.2
			if r[1] != "" and skeleton.find_bone(r[1]) >= 0:
				ln = skeleton.get_bone_rest(skeleton.find_bone(r[1])).origin.length()
			var pb := PhysicalBone3D.new()
			pb.name = "PB_" + r[0]
			_rag_sim.add_child(pb)
			pb.bone_name = r[0]
			pb.mass = r[3]
			pb.collision_layer = 0
			pb.collision_mask = 1
			pb.linear_damp = 0.6
			pb.angular_damp = 2.0
			pb.friction = 1.0
			if r[0] != "pelvis":
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
				pb.set("joint_constraints/swing_span", r[4])
				pb.set("joint_constraints/twist_span", r[5])
			var cs := CollisionShape3D.new()
			var cap := CapsuleShape3D.new()
			cap.radius = r[2]
			cap.height = maxf(ln, r[2] * 2.0 + 0.02)
			cs.shape = cap
			cs.position = Vector3(0, ln * 0.5, 0)
			pb.add_child(cs)
	_rag_sim.physical_bones_start_simulation()
	_rag_live.erase(self)
	_rag_live.append(self)
	while _rag_live.size() > 10:
		var old = _rag_live.pop_front()
		if is_instance_valid(old):
			old._rag_settle()
	for pb in _rag_sim.get_children():
		if pb is PhysicalBone3D:
			var w := 1.0 if pb.bone_name in ["pelvis", "spine_03", "spine_02"] else 0.4
			pb.apply_central_impulse(impulse * pb.mass * w)

func _rag_settle() -> void:
	if _rag_sim == null:
		return
	for pb in _rag_sim.get_children():
		if pb is PhysicalBone3D:
			pb.linear_damp = 8.0
			pb.angular_damp = 8.0

func stop_ragdoll() -> void:
	if _rag_sim != null:
		_rag_sim.physical_bones_stop_simulation()
	_rag_live.erase(self)

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
