extends RefCounted
## The Rimebound look, layered on top of any humanoid body:
##   RimeLook.decorate(model, intensity)           (0.3 faint .. 1 normal .. 1.6 heavy)
## Works on actors/humanoid.gd-style models (pivots head, chest, spine, arm_l/r, fore_l/r,
## hand_l/r, scale var `_s`) and, as a fallback, on any model containing a Skeleton3D
## (crystals are parented via BoneAttachment3D; bones are found by substring:
## "head", "spine_03"/"chest", "spine_01", "upperarm_l", "lowerarm_l", "hand_l"...).
## Adds: frost-white skin tint, black frostbitten fingers, frost crust, ice crystals bursting
## from mouth / eyes / crown / back / shoulders / forearms. Returns the nodes it added.

const Kit = preload("res://actors/kit.gd")

static func decorate(model: Node, intensity := 1.0, seed := 0, opts := {}) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else (randi() | 1)
	var added: Array = []
	var iv: float = clamp(intensity, 0.1, 2.0)
	if model.get("skeleton") is Skeleton3D and model.has_method("bone_attachment"):
		_character(model, iv, rng, opts, added)
	elif model.get("head") is Node3D and model.get("chest") is Node3D:
		_pivots(model, iv, rng, opts, added)
	else:
		var sks := model.find_children("*", "Skeleton3D", true, false)
		if sks.size() > 0:
			_skeleton(sks[0], iv, rng, opts, added)
	return added

# ------------------------------------------------------------------ CharacterModel (glTF MakeHuman rig)
## Bone frames of the rig: head/spine bones are y-up / z-forward / x-left; limb bones run along +Y.
## Skin pallor, frostbite and gore are baked into the textures; this adds the ice growth on bones.
static func _bc(model: Node, bone: String, pos: Vector3, dir: Vector3, len: float, r: float, rng: RandomNumberGenerator, kind := "ice", added: Array = []) -> void:
	var ba: Node = model.bone_attachment(bone)
	if ba == null:
		return
	var n := Kit.crystal(ba, pos, dir, len, r, Kit.mat(kind), rng.randi() % 8)
	added.append(n)

static func _ring(rng: RandomNumberGenerator, up := 0.35) -> Vector3:
	var a := rng.randf() * TAU
	return Vector3(cos(a), up * rng.randf_range(-0.5, 1.5), sin(a)).normalized()

static func _character(model: Node, iv: float, rng: RandomNumberGenerator, opts: Dictionary, added: Array) -> void:
	var s: float = float(model.get("_s")) if model.get("_s") != null else 1.0
	s = clampf(s, 0.8, 1.4)
	# head: crystals from the mouth, eyes, crown
	if opts.get("mouth", true):
		for i in 2 + int(3 * iv):
			var x := rng.randf_range(-1.0, 1.0)
			_bc(model, "head", Vector3(x * 0.022, -0.026, 0.115) * s, Vector3(x * 0.6, rng.randf_range(-0.5, 0.3), 1.0), rng.randf_range(0.06, 0.15) * iv * s, rng.randf_range(0.01, 0.018) * s, rng, "ice", added)
	if opts.get("eyes", true):
		for x in [-1.0, 1.0]:
			if rng.randf() < 0.45 + 0.3 * iv:
				_bc(model, "head", Vector3(x * 0.032, 0.046, 0.108) * s, Vector3(x * rng.randf_range(0.1, 0.7), rng.randf_range(-0.2, 0.4), 1.0), rng.randf_range(0.04, 0.1) * iv * s, rng.randf_range(0.006, 0.012) * s, rng, "ice_glow", added)
	for i in 2 + int(3 * iv):
		var x := rng.randf_range(-1.0, 1.0)
		_bc(model, "head", Vector3(x * 0.05, 0.14, rng.randf_range(-0.06, 0.03)) * s, Vector3(x * 0.7, 1.0, rng.randf_range(-0.7, 0.1)), rng.randf_range(0.05, 0.12) * iv * s, rng.randf_range(0.01, 0.018) * s, rng, "ice", added)
	# frost crust on the cheek / brow
	var hb: Node = model.bone_attachment("head")
	if hb:
		for x in [-1.0, 1.0]:
			if rng.randf() < 0.3:
				added.append(Kit.sphere(hb, 0.016 * s, Kit.mat("frost"), Vector3(x * 0.075, 0.035, 0.085) * s, Vector3(1.0, 0.8, 0.5)))
	# back / spine growths
	for i in int(3 + 4 * iv):
		var x := rng.randf_range(-1.0, 1.0)
		_bc(model, "spine_03", Vector3(x * 0.09, rng.randf_range(-0.04, 0.2), -0.11) * s, Vector3(x * 0.45, rng.randf_range(0.4, 1.0), -1.0), rng.randf_range(0.14, 0.32) * iv * s, rng.randf_range(0.02, 0.034) * s, rng, "ice", added)
	for i in int(1 + 2 * iv):
		var x := rng.randf_range(-1.0, 1.0)
		_bc(model, "spine_03", Vector3(x * 0.1, rng.randf_range(0.0, 0.16), 0.1) * s, Vector3(x * 0.4, 0.2, 1.0), rng.randf_range(0.06, 0.15) * iv * s, rng.randf_range(0.013, 0.022) * s, rng, "ice", added)
	for i in int(1 + iv):
		_bc(model, "spine_01", Vector3(rng.randf_range(-0.04, 0.04), rng.randf_range(0.0, 0.1), -0.1) * s, Vector3(0, 0.6, -1.0), rng.randf_range(0.1, 0.2) * iv * s, 0.024 * s, rng, "ice", added)
	# shoulders & limbs: radiate away from the bone axis (+Y)
	for side in ["l", "r"]:
		for i in 1 + int(2 * iv):
			_bc(model, "upperarm_" + side, Vector3(0, rng.randf_range(0.04, 0.24), 0) * s + _ring(rng) * 0.04 * s, _ring(rng, 0.5), rng.randf_range(0.1, 0.24) * iv * s, rng.randf_range(0.015, 0.028) * s, rng, "ice", added)
		for i in 1 + int(1.5 * iv):
			_bc(model, "lowerarm_" + side, Vector3(0, rng.randf_range(0.05, 0.22), 0) * s + _ring(rng) * 0.03 * s, _ring(rng, 0.6), rng.randf_range(0.07, 0.16) * iv * s, rng.randf_range(0.01, 0.019) * s, rng, "ice", added)
		if rng.randf() < 0.5 * iv:
			_bc(model, "hand_" + side, Vector3(0, 0.1, 0) * s, Vector3(0, 1, 0.2), rng.randf_range(0.03, 0.06) * s, 0.006 * s, rng, "ice", added)
		if rng.randf() < 0.45 * iv:
			_bc(model, "thigh_" + side, Vector3(0, rng.randf_range(0.1, 0.35), 0) * s + _ring(rng) * 0.06 * s, _ring(rng, 0.5), rng.randf_range(0.08, 0.16) * iv * s, rng.randf_range(0.012, 0.022) * s, rng, "ice", added)

# ------------------------------------------------------------------ pivot-based humanoid
static func _cr(parent: Node, pos: Vector3, dir: Vector3, len: float, r: float, s: float, rng: RandomNumberGenerator, kind := "ice") -> void:
	Kit.crystal(parent, pos * s, dir, len * s, r * s, Kit.mat(kind), rng.randi() % 8)

static func _pivots(model: Node, iv: float, rng: RandomNumberGenerator, opts: Dictionary, added: Array) -> void:
	var s := 1.0
	var sv = model.get("_s")
	if sv != null:
		s = float(sv)
	var head: Node3D = model.get("head")
	var chest: Node3D = model.get("chest")
	var spine: Node3D = model.get("spine")
	var root := Node3D.new()
	root.name = "RimeLook"
	head.add_child(root)  # head-local group
	added.append(root)
	if opts.get("skin_tint", true):
		_tint_skin(model)
	# --- head: mouth, eyes, crown
	if opts.get("mouth", true):
		for i in 2 + int(3 * iv):
			var x := rng.randf_range(-1.0, 1.0)
			_cr(root, Vector3(x * 0.025, 0.048, 0.092), Vector3(x * 0.6, rng.randf_range(-0.5, 0.3), 1.0), rng.randf_range(0.07, 0.17) * iv, rng.randf_range(0.011, 0.02), s, rng)
	if opts.get("eyes", true):
		for x in [-1.0, 1.0]:
			if rng.randf() < 0.55 + 0.3 * iv:
				for k in 1 + int(iv > 0.9):
					_cr(root, Vector3(x * 0.036, 0.112, 0.09), Vector3(x * rng.randf_range(0.1, 0.7), rng.randf_range(-0.2, 0.4), 1.0), rng.randf_range(0.05, 0.11) * iv, rng.randf_range(0.007, 0.013), s, rng, "ice_glow")
	for i in 2 + int(3 * iv):
		var x := rng.randf_range(-1.0, 1.0)
		_cr(root, Vector3(x * 0.05, 0.19, rng.randf_range(-0.05, 0.02)), Vector3(x * 0.7, 1.0, rng.randf_range(-0.7, 0.1)), rng.randf_range(0.08, 0.2) * iv, rng.randf_range(0.012, 0.024), s, rng)
	# frost crust on cheek / brow
	for x in [-1.0, 1.0]:
		if rng.randf() < 0.7:
			Kit.sphere(root, 0.03 * s, Kit.mat("frost"), Vector3(x * 0.07, 0.1, 0.07) * s, Vector3(1.0, 0.8, 0.5))
	# --- torso
	var back := int(3 + 4 * iv)
	for i in back:
		var x := rng.randf_range(-1.0, 1.0)
		_cr(chest, Vector3(x * 0.09, rng.randf_range(-0.04, 0.22), -0.1), Vector3(x * 0.45, rng.randf_range(0.4, 1.0), -1.0), rng.randf_range(0.14, 0.34) * iv, rng.randf_range(0.02, 0.036), s, rng)
	for i in int(1 + 2 * iv):
		var x := rng.randf_range(-1.0, 1.0)
		_cr(chest, Vector3(x * 0.1, rng.randf_range(0.0, 0.18), 0.1), Vector3(x * 0.4, 0.2, 1.0), rng.randf_range(0.07, 0.16) * iv, rng.randf_range(0.014, 0.024), s, rng)
	if spine != null:
		for i in int(1 + iv):
			_cr(spine, Vector3(rng.randf_range(-0.04, 0.04), rng.randf_range(0.02, 0.2), -0.09), Vector3(0, 0.6, -1.0), rng.randf_range(0.1, 0.22) * iv, 0.026, s, rng)
	for k in 3:
		var p := Kit.sphere(chest, rng.randf_range(0.04, 0.08) * s, Kit.mat("frost"), Vector3(rng.randf_range(-0.14, 0.14), rng.randf_range(-0.1, 0.22), rng.randf_range(0.06, 0.1)) * s, Vector3(1.2, 0.8, 0.4))
		added.append(p)
	# --- arms
	for side in [[model.get("arm_l"), -1.0, model.get("fore_l"), model.get("hand_l")], [model.get("arm_r"), 1.0, model.get("fore_r"), model.get("hand_r")]]:
		var arm: Node3D = side[0]
		var sg: float = side[1]
		var fore: Node3D = side[2]
		var hand: Node3D = side[3]
		if arm:
			for i in 1 + int(2 * iv):
				_cr(arm, Vector3(sg * 0.03, 0.03, rng.randf_range(-0.03, 0.03)), Vector3(sg * 1.0, rng.randf_range(0.5, 1.2), rng.randf_range(-0.5, 0.1)), rng.randf_range(0.12, 0.26) * iv, rng.randf_range(0.016, 0.03), s, rng)
		if fore:
			for i in 1 + int(1.5 * iv):
				_cr(fore, Vector3(0, -rng.randf_range(0.06, 0.2), -0.02), Vector3(sg * rng.randf_range(0.3, 0.9), rng.randf_range(-0.6, 0.2), -rng.randf_range(0.2, 0.9)), rng.randf_range(0.08, 0.17) * iv, rng.randf_range(0.01, 0.02), s, rng)
		if hand and opts.get("fingers", true):
			var blk := Kit.mat("flesh_black")
			Kit.box(hand, Vector3(0.056, 0.06, 0.03) * s, blk, Vector3(0, -0.062, 0) * s)
			for f in 4:
				var fx := (f - 1.5) * 0.013
				Kit.box(hand, Vector3(0.011, 0.045, 0.014) * s, blk, Vector3(fx, -0.1, 0.0) * s)
				if rng.randf() < 0.4 * iv:
					_cr(hand, Vector3(fx, -0.12, 0), Vector3(0, -1, 0.2), 0.04, 0.005, s, rng)

## Replace skin-like (subsurface) materials by frost-white versions.
static func _tint_skin(model: Node) -> void:
	var done := {}
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		var m = mi.material_override
		if m is StandardMaterial3D and m.subsurf_scatter_enabled:
			if not done.has(m):
				var c: StandardMaterial3D = m.duplicate()
				c.albedo_texture = null
				c.albedo_color = Color(0.8, 0.88, 0.93)
				c.emission_enabled = true
				c.emission = Color(0.12, 0.3, 0.45)
				c.emission_energy_multiplier = 0.25
				c.rim_enabled = true
				c.rim = 0.45
				c.rim_tint = 0.9
				done[m] = c
			mi.material_override = done[m]

# ------------------------------------------------------------------ skeleton fallback
const BONES := {
	"head": ["head"],
	"chest": ["spine_03", "spine_02", "chest", "spine3", "spine2", "spine"],
	"spine": ["spine_01", "spine1", "spine_02", "spine", "pelvis"],
	"arm_l": ["upperarm_l", "upperarm.l", "upper_arm_l", "arm_l", "shoulder_l"],
	"arm_r": ["upperarm_r", "upperarm.r", "upper_arm_r", "arm_r", "shoulder_r"],
	"fore_l": ["lowerarm_l", "lowerarm.l", "forearm_l", "forearm.l", "elbow_l"],
	"fore_r": ["lowerarm_r", "lowerarm.r", "forearm_r", "forearm.r", "elbow_r"],
	"hand_l": ["hand_l", "hand.l"],
	"hand_r": ["hand_r", "hand.r"],
}

static func find_bone(sk: Skeleton3D, keys: Array) -> String:
	for k in keys:
		for i in sk.get_bone_count():
			var bn := sk.get_bone_name(i).to_lower().replace(" ", "_").replace("mixamorig:", "").replace("mixamorig_", "")
			if bn == k or bn.contains(k):
				return sk.get_bone_name(i)
	return ""

static func _skeleton(sk: Skeleton3D, iv: float, rng: RandomNumberGenerator, _opts: Dictionary, added: Array) -> void:
	var counts := {"head": int(4 + 4 * iv), "chest": int(3 + 4 * iv), "spine": int(1 + 2 * iv), "arm_l": 2, "arm_r": 2, "fore_l": 2, "fore_r": 2, "hand_l": 0, "hand_r": 0}
	for key in BONES:
		var bone := find_bone(sk, BONES[key])
		if bone == "":
			continue
		var ba := BoneAttachment3D.new()
		ba.name = "Rime_" + key
		ba.bone_name = bone
		sk.add_child(ba)
		added.append(ba)
		var n: int = counts[key]
		for i in n:
			# bone-local axes are rig dependent: radiate in all directions, it reads as growth.
			var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			var len := rng.randf_range(0.08, 0.2) * iv
			Kit.crystal(ba, d * 0.03, d, len, rng.randf_range(0.012, 0.026), Kit.mat("ice"), rng.randi() % 8)
		if key.begins_with("hand"):
			Kit.box(ba, Vector3(0.07, 0.07, 0.04), Kit.mat("flesh_black"), Vector3.ZERO)
