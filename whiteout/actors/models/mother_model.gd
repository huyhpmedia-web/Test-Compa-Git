extends "res://actors/models/creature.gd"
## THE HOLLOW MOTHER. Phase 1: a vast crystal lattice at the back of the cavern with Ruth's upper
## body fused at the centre (her chest glow is the weak point). Phase 2: the lattice shatters and
## Ruth tears free atop eight long crystal spider legs (3 m figure).
## Owner vars: phase, move_speed, lunge_k (0..1 crouch/lunge), crack_k (0..1 pre-shatter shaking), flash.
const Kit = preload("res://actors/kit.gd")
const Humanoid = preload("res://actors/humanoid.gd")
const RimeLook = preload("res://actors/rime_look.gd")

var phase := 1
var lattice: Node3D
var legs_group: Node3D
var ruth: Node3D
var legs: Array = []
var heart_mat: StandardMaterial3D
var heart_light: OmniLight3D
var eye_mat: StandardMaterial3D
var flash := 0.0
var lunge_k := 0.0
var crack_k := 0.0
var leg_k := 0.0           # 0..1 legs extended (phase 2 reveal)
var _phase_t := 0.0
var _dead_t := 0.0
var _abdomen: Node3D
const RUTH_Y := 1.5
const L1 := 1.9
const L2 := 2.4

func _ready() -> void:
	_build()

func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var ice := Kit.mat("ice")
	var deep := Kit.mat("ice_deep")
	var glow := Kit.mat("ice_glow")
	var root := Kit.mat("root")
	lattice = Node3D.new()
	add_child(lattice)
	var hub := Vector3(0, 3.0, -1.0)
	# main radiating columns (back hemisphere, fanning up and out)
	for i in 70:
		var d := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.55, 1.0), rng.randf_range(-1.0, 0.25)).normalized()
		var start := hub + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.8), rng.randf_range(-0.5, 0.5))
		var len := rng.randf_range(2.5, 8.5)
		var m: Material = deep if i % 4 else (glow if i % 9 == 0 else ice)
		Kit.crystal(lattice, start, d, len, rng.randf_range(0.14, 0.5), m, i)
	# rooted spikes from the floor behind
	for i in 30:
		var x := rng.randf_range(-10, 10)
		var z := rng.randf_range(-7, -1.5)
		Kit.crystal(lattice, Vector3(x, -0.2, z), Vector3(rng.randf_range(-0.3, 0.3) - x * 0.03, 1, rng.randf_range(-0.4, 0.2)), rng.randf_range(2.0, 6.0), rng.randf_range(0.2, 0.55), deep, i + 7)
	# cross braces between tips, dark root tendrils draped over everything
	for i in 26:
		var a := hub + Vector3(rng.randf_range(-6, 6), rng.randf_range(-1, 5), rng.randf_range(-5, -0.5))
		var b := a + Vector3(rng.randf_range(-3, 3), rng.randf_range(-2, 2), rng.randf_range(-2, 1))
		Kit.limb(lattice, a, b, 0.07, 0.05, ice, false, 5)
	for i in 22:
		var top := hub + Vector3(rng.randf_range(-3, 3), rng.randf_range(0.5, 4), rng.randf_range(-3, 0.5))
		var prev := top
		for k in 3:
			var nxt := prev + Vector3(rng.randf_range(-0.6, 0.6), -rng.randf_range(0.8, 1.6), rng.randf_range(-0.4, 0.5))
			nxt.y = max(nxt.y, 0.0)
			Kit.limb(lattice, prev, nxt, 0.11 - k * 0.025, 0.09 - k * 0.025, root, true, 6)
			prev = nxt
	# the thorax mass Ruth is fused into
	Kit.mi(lattice, Kit.blob(1.1, 9, 0.15, Vector3(1.2, 0.9, 1.0), 12, 16), deep, Vector3(0, 2.15, -0.1))
	# Ruth
	ruth = Humanoid.new()
	ruth.setup({"zombie": false, "female": true, "height": 1.62, "bulk": 0.95, "skin": Color(0.82, 0.76, 0.73), "hair": Color(0.62, 0.6, 0.62),
		"hair_style": "short", "shirt": Color(0.4, 0.26, 0.34), "pants": Color(0.2, 0.2, 0.24), "coat": false, "bloody": 0.1})
	ruth.position = Vector3(0, RUTH_Y, 0.2)
	add_child(ruth)
	var s: float = ruth.cfg.height / 1.72
	ruth.thigh_l.visible = false
	ruth.thigh_r.visible = false
	RimeLook.decorate(ruth, 0.5, 5, {"mouth": false, "eyes": false})
	eye_mat = Kit.glow_unique(Color(0.5, 0.95, 1.0), 4.0)
	for x in [-1.0, 1.0]:
		Kit.sphere(ruth.head, 0.017 * s, eye_mat, Vector3(x * 0.036, 0.112, 0.092) * s, Vector3(1.4, 0.8, 0.6))
	# glowing heart through the cardigan
	heart_mat = Kit.glow_unique(Color(0.5, 0.95, 1.0), 4.0)
	Kit.sphere(ruth.chest, 0.07 * s, heart_mat, Vector3(0, 0.12, 0.1) * s, Vector3(1, 1.2, 0.7))
	Kit.cluster(ruth.chest, Vector3(0, 0.12, 0.12) * s, Vector3(0, 0.1, 1), 9, 0.28 * s, 0.03 * s, glow, rng, 0.9)
	for k in 5:
		Kit.crystal(ruth.chest, Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(0.0, 0.2), -0.1) * s, Vector3(rng.randf_range(-1, 1), rng.randf_range(0, 1), -1), rng.randf_range(0.4, 1.0), 0.05 * s, deep, k)
	heart_light = OmniLight3D.new()
	heart_light.light_color = Color(0.5, 0.95, 1.0)
	heart_light.light_energy = 3.0
	heart_light.omni_range = 9.0
	heart_light.shadow_enabled = false
	heart_light.position = Vector3(0, 0.12, 0.3) * s
	ruth.chest.add_child(heart_light)
	Kit.post(ruth, _ruth_pose)
	# phase-2 legs (hidden until the lattice shatters)
	legs_group = Node3D.new()
	legs_group.visible = false
	add_child(legs_group)
	for i in 8:
		var a := TAU * float(i) / 8.0 + 0.2
		var hip := Vector3(cos(a) * 0.45, 2.15, sin(a) * 0.45 - 0.1)
		var up := Kit.crystal(legs_group, hip, Vector3.UP, 1.0, 0.1, deep, i)
		var lo := Kit.crystal(legs_group, hip, Vector3.UP, 1.0, 0.07, deep, i + 3)
		var tip := Kit.crystal(legs_group, hip, Vector3.DOWN, 0.5, 0.07, glow, i + 5)
		var knee := Kit.sphere(legs_group, 0.13, glow, hip)
		legs.append({"hip": hip, "rest": Vector3(cos(a) * 2.3, 0, sin(a) * 2.3 - 0.1), "up": up, "lo": lo, "tip": tip, "knee": knee, "ph": PI * (i % 2), "a": a, "foot": Vector3(cos(a) * 2.3, 0, sin(a) * 2.3 - 0.1)})
	# spider abdomen behind her, glowing from within
	_abdomen = Node3D.new()
	_abdomen.position = Vector3(0, 2.0, -1.0)
	legs_group.add_child(_abdomen)
	Kit.mi(_abdomen, Kit.blob(0.9, 44, 0.12, Vector3(0.9, 0.8, 1.5), 12, 16), deep, Vector3.ZERO)
	Kit.sphere(_abdomen, 0.5, glow, Vector3.ZERO, Vector3(0.8, 0.7, 1.2))
	Kit.cluster(_abdomen, Vector3(0, 0.5, -0.5), Vector3(0, 1, -0.5), 8, 1.0, 0.1, ice, rng, 0.7)

func set_phase(p: int) -> void:
	phase = p
	if p == 2:
		lattice.visible = false
		legs_group.visible = true
		leg_k = 0.0

func heart_world() -> Vector3:
	return ruth.chest.global_position + ruth.chest.global_transform.basis.z * 0.12 + Vector3(0, 0.05, 0)

func head_world() -> Vector3:
	return ruth.head.global_position + Vector3(0, 0.1, 0)

func _ruth_pose(_d: float) -> void:
	if ruth == null:
		return
	var tt := t
	if phase == 1:
		var k := crack_k
		ruth.spine.rotation.x = -0.15 + sin(tt * 0.6) * 0.03
		ruth.chest.rotation.z = sin(tt * 0.4) * 0.03
		ruth.head.rotation = Vector3(-0.5 + sin(tt * 0.5) * 0.05, sin(tt * 0.3) * 0.2, 0.0)
		ruth.arm_l.rotation = Vector3(-0.2, 0, -1.35 + sin(tt * 0.7) * 0.03 - k * 0.2)
		ruth.arm_r.rotation = Vector3(-0.2, 0, 1.35 - sin(tt * 0.7) * 0.03 + k * 0.2)
		ruth.fore_l.rotation = Vector3(-0.2, 0, 0)
		ruth.fore_r.rotation = Vector3(-0.2, 0, 0)
	else:
		var lk := lunge_k
		ruth.spine.rotation.x = 0.25 + lk * 0.5 + sin(tt * 1.4) * 0.03
		ruth.head.rotation = Vector3(-0.1 - lk * 0.2, sin(tt * 0.9) * 0.15, 0.1)
		if not ruth.is_playing():
			ruth.arm_l.rotation = Vector3(-1.1 - lk * 0.9, 0.3, -0.35)
			ruth.arm_r.rotation = Vector3(-1.1 - lk * 0.9, -0.3, 0.35)
			ruth.fore_l.rotation = Vector3(-0.5, 0, 0)
			ruth.fore_r.rotation = Vector3(-0.5, 0, 0)

func _seg(mi: MeshInstance3D, a: Vector3, b: Vector3, r: float) -> void:
	var d := b - a
	var bs := Kit.basis_y(d)
	mi.transform = Transform3D(Basis(bs.x * r, bs.y * d.length(), bs.z * r), a)

func _animate(delta: float) -> void:
	flash = max(0.0, flash - delta * 4.0)
	var e := 3.5 + sin(t * 2.0) * 1.0 + flash * 10.0 + crack_k * 6.0
	heart_mat.emission_energy_multiplier = e
	heart_light.light_energy = 2.5 + flash * 6.0 + sin(t * 2.0)
	eye_mat.emission_energy_multiplier = 3.0 + sin(t * 3.0)
	if pose == "dead":
		_dead_t = min(_dead_t + delta * 0.6, 1.0)
		heart_mat.emission_energy_multiplier = 0.0
		heart_light.light_energy = 0.0
		eye_mat.emission_energy_multiplier = 0.0
		ruth.position.y = RUTH_Y - 1.2 * _dead_t
		for lg in legs:
			lg.foot = (lg.foot as Vector3).lerp(Vector3((lg.rest as Vector3).x * 0.5, 0, (lg.rest as Vector3).z * 0.5), delta * 2.0)
	if phase == 1:
		lattice.position = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.04 * crack_k
		return
	leg_k = move_toward(leg_k, 1.0, delta * 0.8)
	var a: float = clamp(move_speed / 4.5, 0.0, 1.0)
	_phase_t += delta * (2.0 + move_speed * 1.7)
	var crouch := lunge_k
	if pose != "dead":
		ruth.position.y = RUTH_Y - crouch * 0.7
	_abdomen.position.y = 2.0 - crouch * 0.7
	for lg in legs:
		var hip: Vector3 = lg.hip
		hip.y -= crouch * 0.7
		var rest: Vector3 = lg.rest
		var ph: float = _phase_t + lg.ph
		var foot := rest * (1.0 - 0.15 * crouch)
		if pose != "dead":
			foot.z += sin(ph) * 0.9 * a
			foot.y = max(0.0, cos(ph)) * 0.8 * a + sin(t * 1.3 + lg.a * 3.0) * 0.03
			foot.y += (1.0 - leg_k) * 3.0
			if lunge_k > 0.2 and (lg.a < 3.2):   # front legs rear up for the lunge
				foot.y += 1.0 * lunge_k
				foot.z += 0.8 * lunge_k
		else:
			foot = lg.foot
		var d := foot - hip
		var dist := d.length()
		var dn := d / maxf(dist, 0.01)
		var along := (L1 * L1 - L2 * L2 + dist * dist) / (2.0 * maxf(dist, 0.1))
		var hgt := sqrt(maxf(L1 * L1 - along * along, 0.04))
		var upv := (Vector3.UP - dn * dn.dot(Vector3.UP))
		if upv.length() < 0.05:
			upv = Vector3(cos(lg.a), 0.3, sin(lg.a))
		var knee := hip + dn * along + upv.normalized() * hgt
		_seg(lg.up, hip, knee, 0.11)
		_seg(lg.lo, knee, foot, 0.075)
		(lg.knee as Node3D).position = knee
		_seg(lg.tip, foot + Vector3(0, 0.25, 0), foot + Vector3(0, -0.15, 0), 0.07)
