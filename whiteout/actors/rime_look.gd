extends RefCounted
## The Rimebound (infected) look. v3: NO ice crystals / frost prisms on the infected.
##   RimeLook.decorate(model, intensity)  -> no-op kept for API compatibility (callers: zombie, npc, specials).
##   RimeLook.flesh(kind)                 -> organic materials for the specials ("scab", "sinew", "pus", "pus_core", "gland", "bone", "tooth").
##   RimeLook.glacial(kind)               -> glassy ice material, still used by the (approved) boss scripts only.
## The zombie look (grey-green necrotic skin, livor mortis, lacerations / bites with normal + wet roughness, bared teeth,
## clouded eyes, torn bloody clothes) is baked into assets/characters/*.glb by tools/charpipe (zombies.py, gore.py).

const Kit = preload("res://actors/kit.gd")

static func decorate(model: Node, intensity := 1.0, seed := 0, opts := {}) -> Array:
	## v3: NO ice crystals / frost prisms on the infected. Their look (necrotic skin, livor mortis, wounds, torn clothes, clouded eyes, teeth)
	## is baked into assets/characters/*.glb by tools/charpipe. This only adds a light dusting of hoarfrost-free grime hooks: nothing.
	return []

# ------------------------------------------------------------------ CharacterModel (glTF MakeHuman rig)
## Bone frames of the rig: head/spine bones are y-up / z-forward / x-left; limb bones run along +Y.
## Skin pallor, frostbite and gore are baked into the textures; this adds the ice growth on bones.
## Shared materials (v2): translucent glacial ice, slightly dirty (triplanar noise), faint inner glow; hoarfrost crust.
static var _mats := {}
static var _dirt: NoiseTexture2D

static func _dirt_tex() -> NoiseTexture2D:
	if _dirt == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.05
		n.fractal_octaves = 3
		_dirt = NoiseTexture2D.new()
		_dirt.noise = n
		_dirt.width = 128
		_dirt.height = 128
		_dirt.seamless = true
	return _dirt

## kind: "ice" (clear-ish glacial ice), "deep" (thicker blue plates), "glow" (eye-socket / throat ice), "frost" (opaque hoarfrost)
static func glacial(kind := "ice") -> StandardMaterial3D:
	if _mats.has(kind):
		return _mats[kind]
	var m := StandardMaterial3D.new()
	m.resource_name = "rime_" + kind
	if kind == "frost":
		m.albedo_color = Color(0.78, 0.86, 0.92)
		m.roughness = 0.62
		m.emission_enabled = true
		m.emission = Color(0.12, 0.25, 0.35)
		m.emission_energy_multiplier = 0.1
	else:
		var a := 0.4
		var c := Color(0.66, 0.82, 0.88)
		var em := 0.08
		match kind:
			"deep":
				a = 0.5; c = Color(0.5, 0.7, 0.82); em = 0.06
			"glow":
				a = 0.5; c = Color(0.6, 0.86, 0.95); em = 0.55
		m.albedo_color = Color(c.r, c.g, c.b, a)
		m.albedo_texture = _dirt_tex()
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(7, 7, 7)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.05
		m.metallic_specular = 0.85
		m.rim_enabled = true
		m.rim = 0.35
		m.rim_tint = 0.6
		m.emission_enabled = true
		m.emission = Color(0.3, 0.6, 0.78)
		m.emission_energy_multiplier = em
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[kind] = m
	return m

static func _thin_ice(kind: String) -> StandardMaterial3D:
	return glacial("glow" if kind == "ice_glow" else "ice")

static func _bc(model: Node, bone: String, pos: Vector3, dir: Vector3, len: float, r: float, rng: RandomNumberGenerator, kind := "ice", added: Array = []) -> void:
	var ba: Node = model.bone_attachment(bone)
	if ba == null:
		return
	var n := Kit.crystal(ba, pos, dir, len, r, _thin_ice(kind), rng.randi() % 8)
	added.append(n)

static func _ring(rng: RandomNumberGenerator, up := 0.35) -> Vector3:
	var a := rng.randf() * TAU
	return Vector3(cos(a), up * rng.randf_range(-0.5, 1.5), sin(a)).normalized()

## organic materials for the specials (scab hide, sinew, pus sacs, bone): opaque / wet, never glassy
static var _flesh := {}
static func flesh(kind := "scab") -> StandardMaterial3D:
	if _flesh.has(kind):
		return _flesh[kind]
	var m := StandardMaterial3D.new()
	m.resource_name = "flesh_" + kind
	m.subsurf_scatter_enabled = kind != "bone"
	m.subsurf_scatter_strength = 0.3
	match kind:
		"scab":   # dried blood crust / necrotic hide plates
			m.albedo_color = Color(0.22, 0.07, 0.06); m.roughness = 0.75
			m.albedo_texture = _dirt_tex(); m.uv1_triplanar = true; m.uv1_scale = Vector3(5, 5, 5)
		"sinew":  # wet red-grey tendon ropes
			m.albedo_color = Color(0.42, 0.14, 0.14); m.roughness = 0.28; m.rim_enabled = true; m.rim = 0.3
		"pus":    # distended sac: yellow-green, translucent, wet
			m.albedo_color = Color(0.5, 0.52, 0.3, 0.85); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.12; m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.emission_enabled = true; m.emission = Color(0.35, 0.4, 0.1); m.emission_energy_multiplier = 0.12
		"pus_core":
			m.albedo_color = Color(0.7, 0.62, 0.15); m.roughness = 0.3
			m.emission_enabled = true; m.emission = Color(0.8, 0.7, 0.15); m.emission_energy_multiplier = 1.2
		"gland":  # swollen throat bladder: pink-grey, veined, wet
			m.albedo_color = Color(0.55, 0.38, 0.4); m.roughness = 0.22
			m.emission_enabled = true; m.emission = Color(0.5, 0.1, 0.12); m.emission_energy_multiplier = 0.3
		"bone":
			m.albedo_color = Color(0.66, 0.6, 0.48); m.roughness = 0.5
		"tooth":
			m.albedo_color = Color(0.6, 0.55, 0.4); m.roughness = 0.3
		_:
			m.albedo_color = Color(0.3, 0.1, 0.1)
	_flesh[kind] = m
	return m

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
