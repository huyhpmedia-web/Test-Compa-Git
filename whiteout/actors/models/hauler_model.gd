extends "res://actors/models/creature.gd"
## THE HAULER: a mountain of frozen miners fused around a haul-truck driver, dragging itself on
## dozens of arms. The driver's exposed torso sits in the crown (the weak point).
## Owner-driven vars: move_speed, stun_k (0..1 crown lowers when stunned), slam_k, charge_k, lean.
const Kit = preload("res://actors/kit.gd")
const Humanoid = preload("res://actors/humanoid.gd")
const EnemyGlb = preload("res://actors/models/enemy_glb.gd")

var crown: Node3D
var driver: Node3D
var mass: Node3D
var arms: Array = []       # {sh, el, ph, base}
var stun_k := 0.0
var slam_k := 0.0
var charge_k := 0.0
var flash := 0.0
var heart_mat: StandardMaterial3D
var heart_light: OmniLight3D
var _phase := 0.0
var _dead_t := 0.0
var _glb: Node3D
var _crawlers: Array = []   # glb: {root, base: Basis, ph}

func _ready() -> void:
	_build()

func _build() -> void:
	var g := EnemyGlb.load_scene("hauler.glb")
	if g != null and EnemyGlb.find(g, "Mass") != null and EnemyGlb.find(g, "Crown") != null and EnemyGlb.find(g, "Driver") != null:
		_build_glb(g)
	else:
		_build_procedural()

## glTF build (tools/charpipe/bosses/build_hauler.py): Mass (static mound + Crawler0..N miners dragging it),
## Crown (cab) holding Driver (its origin is the glowing, torn-open chest = the weak point).
func _build_glb(g: Node3D) -> void:
	_glb = g
	add_child(g)
	mass = EnemyGlb.find(g, "Mass") as Node3D
	crown = EnemyGlb.find(g, "Crown") as Node3D
	driver = EnemyGlb.find(g, "Driver") as Node3D
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	for c in mass.get_children():
		if String(c.name).begins_with("Crawler"):
			arms.append({"sh": c, "el": null, "ph": rng.randf() * TAU, "base_y": 0.0, "l1": 1.0, "base_pos": (c as Node3D).position, "base_basis": (c as Node3D).transform.basis})
	var hm := EnemyGlb.unique_mats(driver, "glow_heart")
	heart_mat = hm[0] if hm.size() > 0 else null
	heart_light = OmniLight3D.new()
	heart_light.light_color = Color(1.0, 0.55, 0.3)
	heart_light.light_energy = 2.0
	heart_light.omni_range = 6.0
	heart_light.shadow_enabled = false
	heart_light.position = Vector3(0, 0.1, 0.4)
	driver.add_child(heart_light)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.7, 0.4)
	lamp.light_energy = 1.4
	lamp.omni_range = 7.0
	lamp.shadow_enabled = false
	lamp.position = Vector3(0.75, 1.0, 0.6)
	crown.add_child(lamp)

func _build_procedural() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var flesh := Kit.mat("flesh_dead")
	var ice := Kit.mat("ice")
	var frost := Kit.mat("frost")
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.16, 0.16, 0.19)
	rock.roughness = 0.85
	mass = Node3D.new()
	add_child(mass)
	# the mountain: overlapping lumps of fused flesh, ore and ice
	Kit.mi(mass, Kit.blob(2.3, 4, 0.16, Vector3(1.0, 0.8, 1.15), 16, 24), flesh, Vector3(0, 1.5, 0))
	for i in 9:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.8, 1.8)
		Kit.mi(mass, Kit.blob(rng.randf_range(0.8, 1.3), 100 + i, 0.2, Vector3(1, 0.9, 1), 10, 14), flesh if i % 2 else frost, Vector3(cos(a) * r, rng.randf_range(1.2, 2.8), sin(a) * r))
	for i in 7:
		var a2 := rng.randf() * TAU
		Kit.mi(mass, Kit.blob(rng.randf_range(0.4, 0.8), 200 + i, 0.3, Vector3.ONE, 8, 10), rock, Vector3(cos(a2) * 2.0, rng.randf_range(0.8, 3.0), sin(a2) * 2.0))
	# fused miners: torsos, helmeted heads, reaching arms emerging from the mass
	var hat := Kit.mat("hat_yellow")
	var cloth := Kit.mat("hivis")
	for i in 16:
		var a3 := rng.randf() * TAU
		var elev := rng.randf_range(0.2, 1.2)
		var dir := Vector3(cos(a3) * cos(elev), sin(elev), sin(a3) * cos(elev))
		var base := Vector3(0, 1.7, 0) + dir * Vector3(2.0, 1.7, 2.2)
		var tor := Kit.mi(mass, Kit.blob(0.32, 300 + i, 0.08, Vector3(1.0, 1.3, 0.8), 8, 12), cloth if i % 3 == 0 else Kit.mat("cloth_grey"), base)
		tor.look_at_from_position(base, base + dir, Vector3.UP)
		var hp := base + dir * 0.35 + Vector3(0, 0.2, 0)
		Kit.mi(mass, Kit.blob(0.19, 400 + i, 0.06, Vector3(0.9, 1.1, 1.0), 8, 10), Kit.mat("skin_frost"), hp)
		if i % 2 == 0:
			Kit.sphere(mass, 0.21, hat, hp + Vector3(0, 0.1, 0), Vector3(1, 0.75, 1.1))
		Kit.sphere(mass, 0.05, Kit.mat("mouth"), hp + dir * 0.17 + Vector3(0, -0.06, 0), Vector3(1, 1.4, 0.6))
		Kit.cluster(mass, hp, dir + Vector3(0, 0.8, 0), 3, 0.35, 0.04, ice, rng, 0.8)
		# reaching arm
		var perp := dir.cross(Vector3.UP).normalized()
		Kit.limb(mass, base + perp * 0.3, base + perp * 0.45 + dir * 0.9 + Vector3(0, 0.1, 0), 0.08, 0.06, Kit.mat("skin_frost"), true, 6)
	# massive crystal growth
	for i in 36:
		var a4 := rng.randf() * TAU
		var o := Vector3(cos(a4), rng.randf_range(0.3, 1.2), sin(a4))
		Kit.crystal(mass, Vector3(cos(a4) * 1.8, rng.randf_range(1.6, 3.4), sin(a4) * 1.9), o, rng.randf_range(0.6, 1.8), rng.randf_range(0.08, 0.2), ice, i)
	# dozens of arms dragging the mass
	for i in 28:
		var a5 := TAU * float(i) / 28.0 + rng.randf_range(-0.1, 0.1)
		var side := Vector3(cos(a5), 0, sin(a5))
		var sh := Node3D.new()
		sh.position = side * rng.randf_range(1.5, 2.0) + Vector3(0, rng.randf_range(0.6, 1.4), 0)
		sh.rotation.y = -a5 + PI * 0.5
		mass.add_child(sh)
		# arm in local space: +Z outward
		var l1 := rng.randf_range(0.9, 1.3)
		var l2 := rng.randf_range(1.1, 1.6)
		Kit.limb(sh, Vector3.ZERO, Vector3(0, -l1 * 0.3, l1), 0.2, 0.14, flesh, true, 6)
		var el := Node3D.new()
		el.position = Vector3(0, -l1 * 0.3, l1)
		sh.add_child(el)
		Kit.limb(el, Vector3.ZERO, Vector3(0, -l2 * 0.8, l2 * 0.5), 0.14, 0.09, Kit.mat("skin_frost"), true, 6)
		var hand := Node3D.new()
		hand.position = Vector3(0, -l2 * 0.8, l2 * 0.5)
		el.add_child(hand)
		Kit.box(hand, Vector3(0.12, 0.05, 0.16), Kit.mat("flesh_black"), Vector3(0, 0, 0.05))
		Kit.cluster(hand, Vector3(0, 0, 0.1), Vector3(0, 0.3, 1), 2, 0.2, 0.025, ice, rng, 0.5)
		arms.append({"sh": sh, "el": el, "ph": rng.randf() * TAU, "base_y": sh.rotation.y, "l1": l1, "base_pos": sh.position})
	# crown: the haul-truck driver in his rusted cab, torso exposed
	crown = Node3D.new()
	crown.position = Vector3(0, 3.35, 0.3)
	add_child(crown)
	Kit.box(crown, Vector3(1.6, 0.12, 1.2), Kit.mat("rust"), Vector3(0, -0.5, 0))
	for x in [-0.8, 0.8]:
		Kit.limb(crown, Vector3(x, -0.5, -0.4), Vector3(x * 0.9, 1.5, -0.55), 0.045, 0.04, Kit.mat("rust"))
	Kit.limb(crown, Vector3(-0.8, 1.5, -0.55), Vector3(0.8, 1.5, -0.55), 0.04, 0.04, Kit.mat("rust"))
	var lamp := Kit.glow(Color(1.0, 0.6, 0.2), 3.0)
	Kit.sphere(crown, 0.12, lamp, Vector3(0.75, 1.5, -0.5))
	driver = Humanoid.new()
	driver.setup({"zombie": true, "bloody": 0.7, "female": false, "height": 1.9, "bulk": 1.2, "skin": Color(0.75, 0.62, 0.55), "hair_style": "bald",
		"shirt": Color(0.75, 0.28, 0.04), "pants": Color(0.2, 0.2, 0.2), "coat": false, "vest": true, "vest_color": Color(0.7, 0.3, 0.05), "gloves": true})
	driver.position = Vector3(0, -1.55, 0)
	driver.pose = "zombie"
	crown.add_child(driver)
	var s: float = driver.cfg.height / 1.72
	heart_mat = Kit.glow_unique(Color(1.0, 0.45, 0.2), 3.0)
	# torn chest cavity glowing with the colony's heat
	Kit.sphere(driver.chest, 0.09 * s, heart_mat, Vector3(0, 0.08, 0.12) * s, Vector3(1.0, 1.3, 0.6))
	Kit.cluster(driver.chest, Vector3(0, 0.08, 0.14) * s, Vector3(0, 0.2, 1), 6, 0.2 * s, 0.025 * s, Kit.mat("ice_glow"), rng, 0.8)
	Kit.cluster(driver.head, Vector3(0, 0.2, 0) * s, Vector3(0, 1, -0.2), 6, 0.3 * s, 0.03 * s, ice, rng, 0.8)
	Kit.hardhat(driver.head, s, true)
	heart_light = OmniLight3D.new()
	heart_light.light_color = Color(1.0, 0.55, 0.3)
	heart_light.light_energy = 2.0
	heart_light.omni_range = 6.0
	heart_light.shadow_enabled = false
	heart_light.position = Vector3(0, 0.1, 0.4) * s
	driver.chest.add_child(heart_light)
	Kit.post(driver, _driver_pose)

func heart_world() -> Vector3:
	if _glb != null:
		return driver.global_position
	return driver.chest.global_position + driver.chest.global_transform.basis.z * 0.15 * 1.1 + Vector3(0, 0.05, 0)

func _driver_pose(_d: float) -> void:
	if driver.pose == "dead":
		return
	driver.spine.rotation.x = 0.1 - stun_k * 0.15 + sin(t * 1.5) * 0.03
	driver.head.rotation = Vector3(-0.35 + sin(t * 1.2) * 0.1 - slam_k * 0.3, sin(t * 0.8) * 0.4, 0.15)
	var up := 1.0 + slam_k * 0.8
	driver.arm_l.rotation = Vector3(-2.2 * up + sin(t * 2.0) * 0.15, 0.3, -0.5)
	driver.arm_r.rotation = Vector3(-2.2 * up + sin(t * 2.3) * 0.15, -0.3, 0.5)
	driver.fore_l.rotation = Vector3(-0.3, 0, 0)
	driver.fore_r.rotation = Vector3(-0.3, 0, 0)

func _animate(delta: float) -> void:
	var v := move_speed
	var a: float = clamp(v / 4.0, 0.0, 1.0)
	_phase += delta * (1.5 + v * 1.4)
	flash = max(0.0, flash - delta * 4.0)
	if heart_mat:
		heart_mat.emission_energy_multiplier = 3.0 + sin(t * 4.0) * 1.0 + flash * 10.0 + stun_k * 3.0
	heart_light.light_energy = 2.0 + flash * 5.0 + stun_k * 2.0
	if pose == "dead":
		_dead_t = min(_dead_t + delta * 0.5, 1.0)
		mass.position.y = -0.7 * _dead_t
		mass.scale.y = 1.0 - 0.25 * _dead_t
		crown.position.y = 3.35 - 1.3 * _dead_t
		if heart_mat:
			heart_mat.emission_energy_multiplier = 0.0
		heart_light.light_energy = 0.0
		for ar in arms:
			if _glb != null:
				ar.sh.transform.basis = ar.sh.transform.basis.slerp(ar.base_basis * Basis(Vector3.RIGHT, 0.5), delta * 2.0)
			else:
				ar.sh.rotation.x = lerp(ar.sh.rotation.x, 0.5, delta * 2.0)
		return
	# body: lumbering lurch, leans forward when charging, rears on slam
	mass.position.y = abs(sin(_phase * 0.5)) * 0.12 * a - slam_k * 0.0
	mass.rotation.x = charge_k * 0.18 - slam_k * 0.12 + sin(_phase * 0.5) * 0.02 * a
	mass.rotation.z = sin(_phase * 0.5) * 0.03 * a
	crown.rotation.x = mass.rotation.x
	crown.position.y = 3.35 - stun_k * 0.95 + abs(sin(_phase * 0.5)) * 0.12 * a + slam_k * 0.5
	crown.position.z = 0.3 + stun_k * 0.5 + charge_k * 0.3
	for ar in arms:
		var s := sin(_phase + ar.ph)
		var c := cos(_phase + ar.ph)
		var sh: Node3D = ar.sh
		if _glb != null:
			# crawlers: pull forward (pitch about their own shoulder), slam raises them, stun slumps them
			var pitch: float = -0.05 + s * 0.32 * a - slam_k * 0.6 + stun_k * 0.25
			sh.transform.basis = (ar.base_basis as Basis) * Basis(Vector3.RIGHT, pitch)
			sh.position = (ar.base_pos as Vector3) + (ar.base_basis as Basis) * Vector3(0, max(0.0, c) * 0.12 * a, c * 0.16 * a)
			continue
		sh.rotation.x = -0.05 + s * 0.35 * a + slam_k * -0.9 + stun_k * 0.2
		(ar.el as Node3D).rotation.x = max(0.0, c) * 0.5 * a - 0.2
		sh.position.y = ar.base_pos.y + max(0.0, c) * 0.1 * a
