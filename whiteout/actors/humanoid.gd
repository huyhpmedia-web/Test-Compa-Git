extends Node3D
## Procedurally built, procedurally animated semi-realistic human figure.
## Used by the player, NPCs, zombies and humanoid bosses.
##
## Owner drives it each frame by setting:
##   move_speed (m/s), aim (bool), pose ("normal" | "zombie" | "crawl" | "dead" | "sit")
## and calling play("shoot" | "hurt" | "attack" | "knife" | "stagger" | "grab" | "reload").
## Configure with `setup(cfg)` before adding to tree (or right after).

const Mats = preload("res://core/mats.gd")

var cfg := {
	"height": 1.72, "female": false, "skin": Color(0.78, 0.6, 0.5),
	"shirt": Color(0.35, 0.33, 0.36), "pants": Color(0.12, 0.13, 0.18), "shoes": Color(0.08, 0.07, 0.07),
	"hair": Color(0.1, 0.07, 0.05), "hair_style": "short", "coat": false, "coat_color": Color(0.2, 0.2, 0.22),
	"zombie": false, "bulk": 1.0, "vest": false, "vest_color": Color(0.12, 0.14, 0.18), "gloves": false,
	"bloody": 0.0, "headgear": "",
}

var move_speed := 0.0
var aim := false
var pose := "normal"
var aim_pitch := 0.0          # radians, positive looks up

var _phase := 0.0
var _oneshot := ""
var _oneshot_t := 0.0
var _oneshot_len := 0.0
var _dead_t := 0.0
var _breath := 0.0
var _rng := RandomNumberGenerator.new()

# pivots
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
var held: Node3D  # weapon/attachment slot in right hand

var _s := 1.0  # scale factor relative to 1.72m

func setup(c: Dictionary) -> void:
	for k in c:
		cfg[k] = c[k]
	_rng.seed = hash(str(c))
	_build()

func _ready() -> void:
	if hips == null:
		_build()

func _mat(c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	return Mats.color(c, rough, metal)

func _skin_mat() -> StandardMaterial3D:
	var c: Color = cfg.skin
	if cfg.zombie:
		c = c.lerp(Color(0.52, 0.55, 0.47), 0.65)
	var m := _mat(c, 0.55)
	# subtle subsurface for semi-realistic skin
	m.subsurf_scatter_enabled = true
	m.subsurf_scatter_strength = 0.25
	m.rim_enabled = true
	m.rim = 0.15
	if cfg.zombie and ResourceLoader.exists("res://textures/skin_dead_albedo.png"):
		m.albedo_texture = load("res://textures/skin_dead_albedo.png")
		# the texture averages ~0.22 linear: compensate so the tint colour keeps its brightness
		m.albedo_color = Color(m.albedo_color.r * 3.4, m.albedo_color.g * 3.4, m.albedo_color.b * 3.4)
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * 2.0
	return m

func _cloth(c: Color, rough := 0.95) -> StandardMaterial3D:
	var m := _mat(c, rough)
	if ResourceLoader.exists("res://textures/fabric_albedo.png"):
		m.albedo_texture = load("res://textures/fabric_albedo.png")
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * 6.0
	if ResourceLoader.exists("res://textures/fabric_normal.png"):
		m.normal_enabled = true
		m.normal_texture = load("res://textures/fabric_normal.png")
	if cfg.bloody > 0.0:
		m.albedo_color = c.lerp(Color(0.25, 0.03, 0.02), clamp(cfg.bloody * _rng.randf_range(0.2, 0.6), 0.0, 0.7))
	if m.albedo_texture != null:
		# fabric texture averages ~0.09 linear: compensate (else every garment renders near-black)
		var k := 3.6
		m.albedo_color = Color(m.albedo_color.r * k, m.albedo_color.g * k, m.albedo_color.b * k)
	return m

func _pivot(parent: Node3D, pos: Vector3, n: String) -> Node3D:
	var p := Node3D.new()
	p.name = n
	p.position = pos
	parent.add_child(p)
	return p

## Tapered limb segment hanging downward (-Y) from the pivot.
func _limb(parent: Node3D, length: float, r_top: float, r_bot: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.height = length
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.radial_segments = 14
	cm.rings = 2
	mi.mesh = cm
	mi.material_override = m
	mi.position = Vector3(0, -length * 0.5, 0)
	parent.add_child(mi)
	# rounded joint caps
	var cap := _sphere(parent, r_top, m)
	cap.position = Vector3.ZERO
	return mi

func _sphere(parent: Node3D, r: float, m: Material, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 16
	sm.rings = 10
	mi.mesh = sm
	mi.material_override = m
	mi.scale = scl
	parent.add_child(mi)
	return mi

func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi

func _capsule(parent: Node3D, r: float, h: float, pos: Vector3, m: Material, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = h
	cm.radial_segments = 16
	cm.rings = 6
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	return mi

func _build() -> void:
	for c in get_children():
		c.queue_free()
	_s = cfg.height / 1.72
	var s := _s
	var b: float = cfg.bulk
	var fem: bool = cfg.female
	var skin := _skin_mat()
	var shirt := _cloth(cfg.shirt)
	var pants := _cloth(cfg.pants)
	var shoes := _mat(cfg.shoes, 0.5)
	var hair := _mat(cfg.hair, 0.75)
	var sleeve_m: Material = _cloth(cfg.coat_color) if cfg.coat else shirt

	var shoulder_w := (0.19 if fem else 0.21) * s * b
	var hip_w := (0.1 if fem else 0.095) * s * b

	hips = _pivot(self, Vector3(0, 0.95 * s, 0), "Hips")
	_capsule(hips, 0.15 * s * b, 0.32 * s, Vector3(0, 0.02 * s, 0), pants, Vector3(1.15 if fem else 1.05, 1, 0.75))
	spine = _pivot(hips, Vector3(0, 0.1 * s, 0), "Spine")
	# abdomen
	_capsule(spine, 0.135 * s * b, 0.34 * s, Vector3(0, 0.1 * s, 0), shirt, Vector3(1.05, 1, 0.72))
	chest = _pivot(spine, Vector3(0, 0.22 * s, 0), "Chest")
	# ribcage / torso
	var torso := _capsule(chest, 0.17 * s * b, 0.42 * s, Vector3(0, 0.08 * s, 0), shirt, Vector3(1.12 if not fem else 1.0, 1, 0.66))
	torso.name = "Torso"
	if fem:
		_sphere(chest, 0.065 * s, shirt, Vector3(1, 0.85, 0.9)).position = Vector3(-0.07 * s, 0.1 * s, 0.08 * s)
		_sphere(chest, 0.065 * s, shirt, Vector3(1, 0.85, 0.9)).position = Vector3(0.07 * s, 0.1 * s, 0.08 * s)
	if cfg.vest:
		var vm := _mat(cfg.vest_color, 0.7)
		_box(chest, Vector3(0.36 * s * b, 0.36 * s, 0.25 * s), Vector3(0, 0.08 * s, 0.0), vm)
		for i in 3:
			_box(chest, Vector3(0.07 * s, 0.09 * s, 0.05 * s), Vector3((-0.1 + i * 0.1) * s, 0.02 * s, 0.14 * s), vm)
	if cfg.coat:
		var cmt := _cloth(cfg.coat_color)
		_capsule(chest, 0.18 * s * b, 0.46 * s, Vector3(0, 0.06 * s, 0), cmt, Vector3(1.14, 1, 0.72))
		# coat skirt
		var skirt := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.17 * s * b
		cm.bottom_radius = 0.24 * s * b
		cm.height = 0.62 * s
		skirt.mesh = cm
		skirt.material_override = cmt
		skirt.scale = Vector3(1.05, 1, 0.8)
		skirt.position = Vector3(0, -0.22 * s, 0)
		hips.add_child(skirt)
		# collar
		_box(chest, Vector3(0.3 * s, 0.08 * s, 0.2 * s), Vector3(0, 0.28 * s, -0.02 * s), cmt)

	neck = _pivot(chest, Vector3(0, 0.3 * s, 0), "Neck")
	_limb(neck, 0.1 * s, 0.05 * s, 0.055 * s, skin).position.y = 0.04 * s
	head = _pivot(neck, Vector3(0, 0.09 * s, 0), "Head")
	_build_head(head, skin, hair)

	# arms
	arm_l = _pivot(chest, Vector3(-shoulder_w, 0.24 * s, 0), "ArmL")
	arm_r = _pivot(chest, Vector3(shoulder_w, 0.24 * s, 0), "ArmR")
	for side in [[arm_l, -1.0], [arm_r, 1.0]]:
		var a: Node3D = side[0]
		_sphere(a, 0.06 * s * b, sleeve_m)
		_limb(a, 0.29 * s, 0.052 * s * b, 0.042 * s * b, sleeve_m)
		var fore := _pivot(a, Vector3(0, -0.29 * s, 0), "Fore")
		var fore_m: Material = sleeve_m if (cfg.coat or cfg.get("long_sleeves", true)) else skin
		_limb(fore, 0.26 * s, 0.042 * s * b, 0.032 * s, fore_m)
		var hand := _pivot(fore, Vector3(0, -0.27 * s, 0), "Hand")
		var hm: Material = _mat(Color(0.08, 0.08, 0.08), 0.6) if cfg.gloves else skin
		_box(hand, Vector3(0.05 * s, 0.09 * s, 0.025 * s), Vector3(0, -0.04 * s, 0), hm)
		_box(hand, Vector3(0.02 * s, 0.05 * s, 0.02 * s), Vector3(-side[1] * 0.025 * s, -0.03 * s, 0.015 * s), hm)
		if a == arm_l:
			fore_l = fore; hand_l = hand
		else:
			fore_r = fore; hand_r = hand
	held = _pivot(hand_r, Vector3(0, -0.06 * s, 0.0), "Held")

	# legs
	thigh_l = _pivot(hips, Vector3(-hip_w, -0.05 * s, 0), "ThighL")
	thigh_r = _pivot(hips, Vector3(hip_w, -0.05 * s, 0), "ThighR")
	for t in [thigh_l, thigh_r]:
		_limb(t, 0.43 * s, 0.085 * s * b, 0.06 * s * b, pants)
		var shin := _pivot(t, Vector3(0, -0.43 * s, 0), "Shin")
		_limb(shin, 0.42 * s, 0.06 * s * b, 0.045 * s, pants)
		var foot := _pivot(shin, Vector3(0, -0.42 * s, 0), "Foot")
		_box(foot, Vector3(0.1 * s, 0.08 * s, 0.26 * s), Vector3(0, -0.04 * s, 0.05 * s), shoes)
		if t == thigh_l:
			shin_l = shin; foot_l = foot
		else:
			shin_r = shin; foot_r = foot

	if cfg.zombie:
		_add_wounds()
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func _build_head(h: Node3D, skin: Material, hair: Material) -> void:
	var s := _s
	var fem: bool = cfg.female
	# skull & jaw
	_sphere(h, 0.105 * s, skin, Vector3(0.9 if fem else 0.95, 1.12, 1.0)).position = Vector3(0, 0.1 * s, 0)
	_sphere(h, 0.08 * s, skin, Vector3(0.95 if fem else 1.05, 0.8, 1.0)).position = Vector3(0, 0.04 * s, 0.025 * s)
	# nose
	_box(h, Vector3(0.022 * s, 0.045 * s, 0.03 * s), Vector3(0, 0.09 * s, 0.1 * s), skin).rotation.x = -0.25
	# brow ridge
	_box(h, Vector3(0.13 * s, 0.018 * s, 0.03 * s), Vector3(0, 0.13 * s, 0.085 * s), skin)
	# ears
	for x in [-1.0, 1.0]:
		_sphere(h, 0.022 * s, skin, Vector3(0.5, 1.3, 1)).position = Vector3(x * 0.098 * s, 0.1 * s, 0)
	# eyes: white + iris
	var eye_white := _mat(Color(0.85, 0.82, 0.76) if not cfg.zombie else Color(0.75, 0.72, 0.5), 0.2)
	var iris := _mat(Color(0.18, 0.12, 0.08) if not cfg.zombie else Color(0.7, 0.68, 0.6), 0.15)
	for x in [-1.0, 1.0]:
		_sphere(h, 0.014 * s, eye_white).position = Vector3(x * 0.036 * s, 0.112 * s, 0.083 * s)
		_sphere(h, 0.007 * s, iris).position = Vector3(x * 0.036 * s, 0.112 * s, 0.096 * s)
	# mouth line
	_box(h, Vector3(0.04 * s, 0.006 * s, 0.01 * s), Vector3(0, 0.045 * s, 0.098 * s), _mat(Color(0.35, 0.15, 0.13) if not cfg.zombie else Color(0.2, 0.05, 0.04), 0.5))
	# hair
	match cfg.hair_style:
		"ponytail":
			_sphere(h, 0.112 * s, hair, Vector3(0.95, 1.05, 1.05)).position = Vector3(0, 0.125 * s, -0.012 * s)
			_box(h, Vector3(0.2 * s, 0.05 * s, 0.05 * s), Vector3(0, 0.19 * s, 0.07 * s), hair).rotation.x = 0.3
			var tail := _capsule(h, 0.035 * s, 0.22 * s, Vector3(0, 0.08 * s, -0.12 * s), hair)
			tail.rotation.x = 0.35
			_sphere(h, 0.04 * s, hair).position = Vector3(0, 0.15 * s, -0.1 * s)
		"long":
			_sphere(h, 0.115 * s, hair, Vector3(0.98, 1.05, 1.05)).position = Vector3(0, 0.12 * s, -0.012 * s)
			_box(h, Vector3(0.22 * s, 0.26 * s, 0.1 * s), Vector3(0, 0.0, -0.06 * s), hair)
		"short":
			_sphere(h, 0.11 * s, hair, Vector3(0.96, 0.9, 1.02)).position = Vector3(0, 0.15 * s, -0.01 * s)
		"buzz":
			_sphere(h, 0.108 * s, hair, Vector3(0.92, 0.95, 1.0)).position = Vector3(0, 0.13 * s, -0.01 * s)
		"bald", _:
			pass
	match cfg.headgear:
		"cap":
			var cm := _mat(Color(0.1, 0.12, 0.2), 0.8)
			_sphere(h, 0.115 * s, cm, Vector3(0.98, 0.7, 1.02)).position = Vector3(0, 0.17 * s, 0)
			_box(h, Vector3(0.16 * s, 0.012 * s, 0.09 * s), Vector3(0, 0.17 * s, 0.12 * s), cm)
		"hat":
			var hm := _mat(Color(0.08, 0.08, 0.09), 0.7)
			var brim := MeshInstance3D.new()
			var cy := CylinderMesh.new()
			cy.top_radius = 0.2 * s; cy.bottom_radius = 0.2 * s; cy.height = 0.012 * s
			brim.mesh = cy; brim.material_override = hm
			brim.position = Vector3(0, 0.2 * s, 0)
			h.add_child(brim)
			var crown := MeshInstance3D.new()
			var cy2 := CylinderMesh.new()
			cy2.top_radius = 0.1 * s; cy2.bottom_radius = 0.115 * s; cy2.height = 0.13 * s
			crown.mesh = cy2; crown.material_override = hm
			crown.position = Vector3(0, 0.26 * s, 0)
			h.add_child(crown)
		"mask":
			_box(h, Vector3(0.17 * s, 0.1 * s, 0.05 * s), Vector3(0, 0.06 * s, 0.09 * s), _mat(Color(0.05, 0.05, 0.05), 0.4))
			_box(h, Vector3(0.16 * s, 0.03 * s, 0.03 * s), Vector3(0, 0.115 * s, 0.1 * s), _mat(Color(0.2, 0.9, 1.0), 0.1))

func _add_wounds() -> void:
	var blood := _mat(Color(0.22, 0.02, 0.02), 0.35)
	var flesh := _mat(Color(0.45, 0.1, 0.08), 0.5)
	for i in 6:
		var parent: Node3D = [chest, spine, arm_l, fore_r, thigh_l, head, neck][_rng.randi_range(0, 6)]
		var w := _sphere(parent, _rng.randf_range(0.02, 0.05) * _s, blood if i % 2 == 0 else flesh, Vector3(1, 1, 0.4))
		w.position = Vector3(_rng.randf_range(-0.08, 0.08), _rng.randf_range(-0.15, 0.1), _rng.randf_range(0.06, 0.12)) * _s
	# blood streak down the chest
	_box(chest, Vector3(0.12 * _s, 0.3 * _s, 0.01 * _s), Vector3(0.02 * _s, 0.02 * _s, 0.118 * _s), blood)

## Attach a mesh/scene to the right hand (e.g. a weapon). Replaces previous.
func hold(node: Node3D) -> void:
	for c in held.get_children():
		c.queue_free()
	if node != null:
		held.add_child(node)

func play(anim: String) -> void:
	_oneshot = anim
	_oneshot_t = 0.0
	_oneshot_len = {"shoot": 0.18, "hurt": 0.35, "attack": 0.8, "knife": 0.35, "stagger": 0.9, "grab": 1.2, "reload": 1.2, "roar": 1.6, "heavy": 1.1}.get(anim, 0.5)

func is_playing(anim: String = "") -> bool:
	if _oneshot == "":
		return false
	return anim == "" or _oneshot == anim

func _process(delta: float) -> void:
	if hips == null:
		return
	_breath += delta
	if _oneshot != "":
		_oneshot_t += delta
		if _oneshot_t >= _oneshot_len:
			_oneshot = ""
	var spd: float = move_speed
	var zombie_pose := pose == "zombie"
	var stride := 2.2 if not zombie_pose else 1.4
	_phase += delta * spd * stride / max(_s, 0.5)
	var sw := sin(_phase * 2.0)
	var amp: float = clamp(spd / 3.5, 0.0, 1.0)
	var run: float = clamp((spd - 2.5) / 2.5, 0.0, 1.0)

	if pose == "dead":
		_pose_dead(delta)
		return
	_dead_t = 0.0
	if pose == "crawl":
		_pose_crawl(sw, amp)
		return

	var breath := sin(_breath * 1.6) * 0.015
	# legs
	var leg := 0.55 * amp + 0.25 * run
	thigh_l.rotation = Vector3(sw * leg, 0, 0)
	thigh_r.rotation = Vector3(-sw * leg, 0, 0)
	shin_l.rotation = Vector3(max(0.0, -cos(_phase * 2.0)) * (0.9 * amp + 0.5 * run) + 0.02, 0, 0)
	shin_r.rotation = Vector3(max(0.0, cos(_phase * 2.0)) * (0.9 * amp + 0.5 * run) + 0.02, 0, 0)
	foot_l.rotation.x = 0.0
	foot_r.rotation.x = 0.0
	hips.position.y = 0.95 * _s - abs(sw) * 0.03 * amp - 0.02 * run
	hips.rotation = Vector3(0, sw * 0.08 * amp, 0)
	spine.rotation = Vector3(0.05 + 0.18 * run + breath, -sw * 0.06 * amp, 0)
	chest.rotation = Vector3(breath, -sw * 0.06 * amp, 0)
	neck.rotation = Vector3(-0.05 - 0.1 * run, 0, 0)
	head.rotation = Vector3(0, 0, 0)

	if zombie_pose:
		# hunched, arms reaching, head lolling
		spine.rotation.x = 0.28
		chest.rotation.z = sin(_breath * 0.7) * 0.08
		head.rotation = Vector3(-0.15, sin(_breath * 0.9) * 0.25, 0.25 + sin(_breath * 1.3) * 0.1)
		arm_l.rotation = Vector3(-1.2 + sin(_breath * 1.7) * 0.15, 0, -0.1)
		arm_r.rotation = Vector3(-1.05 + sin(_breath * 1.4 + 1.0) * 0.15, 0, 0.1)
		fore_l.rotation = Vector3(-0.3, 0, 0)
		fore_r.rotation = Vector3(-0.2, 0, 0)
	elif aim:
		var p: float = aim_pitch
		spine.rotation.x = 0.02
		chest.rotation = Vector3(-p * 0.35, -0.15, 0)
		head.rotation = Vector3(-p * 0.4, 0.15, 0)
		arm_r.rotation = Vector3(-PI * 0.5 - p * 0.6, -0.05, 0.0)
		fore_r.rotation = Vector3(0, 0, 0)
		arm_l.rotation = Vector3(-PI * 0.5 - p * 0.6, 0.55, 0.0)
		fore_l.rotation = Vector3(-0.25, 0, 0)
		hand_r.rotation = Vector3.ZERO
	else:
		var arm := 0.45 * amp + 0.35 * run
		arm_l.rotation = Vector3(-sw * arm, 0, -0.08)
		arm_r.rotation = Vector3(sw * arm, 0, 0.08)
		fore_l.rotation = Vector3(-0.15 - 0.6 * run - max(0.0, sw) * 0.3 * amp, 0, 0)
		fore_r.rotation = Vector3(-0.15 - 0.6 * run - max(0.0, -sw) * 0.3 * amp, 0, 0)
		hand_r.rotation = Vector3.ZERO

	# one-shot overlays
	if _oneshot != "":
		var t := _oneshot_t / _oneshot_len
		var k := sin(t * PI)
		match _oneshot:
			"shoot":
				arm_r.rotation.x -= 0.25 * k
				arm_l.rotation.x -= 0.25 * k
				chest.rotation.x += 0.08 * k
			"hurt":
				chest.rotation.x -= 0.35 * k
				head.rotation.x -= 0.4 * k
				spine.rotation.z += 0.15 * k
			"stagger":
				spine.rotation.x -= 0.45 * k
				head.rotation.x -= 0.5 * k
				arm_l.rotation.z -= 0.6 * k
				arm_r.rotation.z += 0.6 * k
			"attack", "grab":
				spine.rotation.x += 0.4 * k
				arm_l.rotation = Vector3(-1.5 - 0.3 * k, 0.3 * k, 0)
				arm_r.rotation = Vector3(-1.5 - 0.3 * k, -0.3 * k, 0)
				head.rotation.x += 0.4 * k
			"heavy":
				arm_r.rotation = Vector3(-2.6 * k + (1.2 * (1.0 - k) if t > 0.5 else 0.0), 0, 0.2)
				spine.rotation.x += 0.5 * k
			"knife":
				arm_r.rotation = Vector3(-1.4, lerp(-0.8, 0.9, t), 0)
				fore_r.rotation.x = -0.3
				chest.rotation.y += lerp(0.4, -0.4, t)
			"reload":
				arm_l.rotation = Vector3(-1.0, 0.4, 0)
				arm_r.rotation = Vector3(-1.1, -0.2, 0)
				fore_l.rotation.x = -0.6 - 0.4 * sin(t * PI * 3.0)
			"roar":
				spine.rotation.x -= 0.3 * k
				head.rotation.x -= 0.6 * k
				arm_l.rotation = Vector3(-0.3, 0, -0.9 * k)
				arm_r.rotation = Vector3(-0.3, 0, 0.9 * k)

func _pose_crawl(sw: float, amp: float) -> void:
	hips.position.y = 0.22 * _s
	hips.rotation = Vector3(PI * 0.45, 0, 0)
	spine.rotation = Vector3(0, 0, 0)
	chest.rotation = Vector3(0, 0, 0)
	head.rotation = Vector3(-1.0, 0, 0)
	arm_l.rotation = Vector3(-PI * 0.45 - 0.6 + sw * 0.7 * max(amp, 0.3), 0, -0.2)
	arm_r.rotation = Vector3(-PI * 0.45 - 0.6 - sw * 0.7 * max(amp, 0.3), 0, 0.2)
	fore_l.rotation = Vector3(-0.5, 0, 0)
	fore_r.rotation = Vector3(-0.5, 0, 0)
	thigh_l.rotation = Vector3(0.1, 0, 0.1)
	thigh_r.rotation = Vector3(0.1, 0, -0.15)
	shin_l.rotation = Vector3(-0.2, 0, 0)
	shin_r.rotation = Vector3(-0.4, 0, 0)

func _pose_dead(delta: float) -> void:
	_dead_t = min(_dead_t + delta * 2.5, 1.0)
	var t := ease(_dead_t, 0.4)
	hips.position.y = lerp(0.95 * _s, 0.12 * _s, t)
	hips.rotation = Vector3(lerp(0.0, -PI * 0.5, t), 0, lerp(0.0, 0.2, t))
	spine.rotation = Vector3(0, 0, 0.1 * t)
	chest.rotation = Vector3(0, 0, 0)
	head.rotation = Vector3(0, 0.6 * t, 0.3 * t)
	arm_l.rotation = Vector3(-0.2, 0, -1.2 * t)
	arm_r.rotation = Vector3(-0.6 * t, 0, 0.9 * t)
	fore_l.rotation = Vector3(-0.3 * t, 0, 0)
	fore_r.rotation = Vector3(-0.9 * t, 0, 0)
	thigh_l.rotation = Vector3(0.1 * t, 0, -0.15 * t)
	thigh_r.rotation = Vector3(-0.3 * t, 0, 0.1 * t)
	shin_l.rotation = Vector3(-0.1, 0, 0)
	shin_r.rotation = Vector3(-0.6 * t, 0, 0)
