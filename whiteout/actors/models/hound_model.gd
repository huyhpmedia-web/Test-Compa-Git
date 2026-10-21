extends "res://actors/models/creature.gd"
## Frozen sled dog / wolf, built from noise-displaced blobs and jointed limbs.
## Poses: normal | crouch | dead.  One-shots: attack (lunge), hurt, stagger, roar.
const Kit = preload("res://actors/kit.gd")

var body: Node3D
var neck: Node3D
var head: Node3D
var jaw: Node3D
var tail: Array = []
var legs: Array = []          # each: {sh, kn, pw, front, side, rest_sh, rest_kn}
var eye_mats: Array = []
var _phase := 0.0
var _dead_t := 0.0
var _seed := 7

func _ready() -> void:
	_build()

func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed * 31
	var fur := StandardMaterial3D.new()
	fur.albedo_color = Color(0.2, 0.19, 0.21)
	fur.roughness = 0.95
	fur.rim_enabled = true
	fur.rim = 0.4
	fur.rim_tint = 0.9
	var fur2 := fur.duplicate() as StandardMaterial3D
	fur2.albedo_color = Color(0.32, 0.31, 0.34)
	var frost := Kit.mat("frost")
	var ice := Kit.mat("ice")
	var bone := Kit.mat("bone")
	var raw := Kit.mat("flesh_raw")
	body = Node3D.new()
	body.position = Vector3(0, 0.62, 0)
	add_child(body)
	# torso masses
	Kit.mi(body, Kit.blob(0.25, 3, 0.07, Vector3(0.95, 1.05, 1.3), 12, 18), fur, Vector3(0, 0.02, 0.27))
	Kit.mi(body, Kit.blob(0.22, 5, 0.07, Vector3(0.9, 0.95, 1.3), 12, 18), fur, Vector3(0, 0.0, -0.1))
	Kit.mi(body, Kit.blob(0.22, 9, 0.07, Vector3(0.95, 1.0, 1.15), 12, 18), fur, Vector3(0, 0.0, -0.42))
	# frost crust on shoulders and back
	for i in 7:
		var z: float = lerp(0.5, -0.5, float(i) / 6.0)
		Kit.sphere(body, rng.randf_range(0.07, 0.12), frost, Vector3(rng.randf_range(-0.1, 0.1), 0.22 + rng.randf_range(-0.03, 0.01), z), Vector3(1.3, 0.45, 1.2))
	# exposed ribs and torn flank
	for side in [-1.0, 1.0]:
		for i in 5:
			var rb := Kit.box(body, Vector3(0.012, 0.15, 0.022), bone, Vector3(side * 0.225, 0.0, 0.4 - i * 0.075))
			rb.rotation.z = side * 0.35
		Kit.sphere(body, 0.07, raw, Vector3(side * 0.2, -0.02, 0.3), Vector3(0.4, 1.0, 1.6))
	# crystal spines along the back
	for i in 10:
		var z2: float = lerp(0.55, -0.55, float(i) / 9.0)
		var h := rng.randf_range(0.14, 0.34) * (1.0 if i % 3 else 1.4)
		Kit.crystal(body, Vector3(rng.randf_range(-0.04, 0.04), 0.2, z2), Vector3(rng.randf_range(-0.25, 0.25), 1.0, rng.randf_range(-0.7, -0.2)), h, rng.randf_range(0.024, 0.045), ice, i)
	# neck + head
	neck = Node3D.new()
	neck.position = Vector3(0, 0.1, 0.5)
	body.add_child(neck)
	Kit.mi(neck, Kit.blob(0.16, 21, 0.06, Vector3(0.85, 0.95, 1.5), 10, 14), fur2, Vector3(0, 0.07, 0.1)).rotation.x = -0.45
	head = Node3D.new()
	head.position = Vector3(0, 0.17, 0.26)
	neck.add_child(head)
	Kit.mi(head, Kit.blob(0.12, 33, 0.05, Vector3(0.9, 0.85, 1.15), 10, 14), fur2, Vector3(0, 0.0, 0.0))
	Kit.mi(head, Kit.blob(0.085, 34, 0.04, Vector3(0.62, 0.55, 1.35), 9, 12), fur2, Vector3(0, -0.03, 0.16))
	Kit.sphere(head, 0.022, Kit.mat("flesh_black"), Vector3(0, -0.01, 0.285), Vector3(1.2, 0.9, 1.0))
	for x in [-1.0, 1.0]:
		var ear := Kit.crystal(head, Vector3(x * 0.07, 0.09, -0.03), Vector3(x * 0.4, 1.0, -0.3), 0.15, 0.05, fur, 3)
		ear.scale.z *= 0.35
		var em := Kit.glow_unique(Color(0.5, 0.95, 1.0), 4.0)
		eye_mats.append(em)
		Kit.sphere(head, 0.017, em, Vector3(x * 0.055, 0.035, 0.1), Vector3(1.0, 0.7, 0.8))
		Kit.sphere(head, 0.05, frost, Vector3(x * 0.07, 0.07, 0.02), Vector3(1.0, 0.5, 1.0))
	Kit.cluster(head, Vector3(0, 0.11, -0.04), Vector3(0, 1, -0.4), 4, 0.15, 0.025, ice, rng, 0.5)
	jaw = Node3D.new()
	jaw.position = Vector3(0, -0.055, 0.08)
	head.add_child(jaw)
	Kit.mi(jaw, Kit.blob(0.06, 41, 0.04, Vector3(0.65, 0.45, 1.5), 8, 12), fur2, Vector3(0, -0.012, 0.085))
	var tooth := Kit.mat("tooth")
	for i in 6:
		var zz := 0.06 + i * 0.03
		Kit.crystal(jaw, Vector3(0.035, 0.005, zz), Vector3(0, 1, 0.1), 0.035 if i % 2 == 0 else 0.022, 0.007, tooth, i)
		Kit.crystal(jaw, Vector3(-0.035, 0.005, zz), Vector3(0, 1, 0.1), 0.03 if i % 2 == 1 else 0.022, 0.007, tooth, i + 2)
	for i in 6:
		var zz2 := 0.13 + i * 0.028
		Kit.crystal(head, Vector3(0.034, -0.075, zz2), Vector3(0, -1, 0.1), 0.03, 0.007, tooth, i)
		Kit.crystal(head, Vector3(-0.034, -0.075, zz2), Vector3(0, -1, 0.1), 0.03, 0.007, tooth, i + 1)
	# icicle fangs bursting from the muzzle
	Kit.crystal(head, Vector3(0.03, -0.05, 0.25), Vector3(0.3, -0.5, 1.0), 0.09, 0.012, ice, 1)
	Kit.crystal(head, Vector3(-0.03, -0.05, 0.25), Vector3(-0.3, -0.5, 1.0), 0.07, 0.01, ice, 2)
	# legs
	var defs := [
		{"p": Vector3(-0.15, -0.05, 0.4), "front": true, "side": -1.0},
		{"p": Vector3(0.15, -0.05, 0.4), "front": true, "side": 1.0},
		{"p": Vector3(-0.15, -0.02, -0.42), "front": false, "side": -1.0},
		{"p": Vector3(0.15, -0.02, -0.42), "front": false, "side": 1.0},
	]
	for d in defs:
		var sh := Node3D.new()
		sh.position = d.p
		body.add_child(sh)
		var l1 := 0.3 if d.front else 0.27
		var l2 := 0.3 if d.front else 0.3
		Kit.limb(sh, Vector3.ZERO, Vector3(0, -l1, 0), 0.075, 0.05, fur, true)
		var kn := Node3D.new()
		kn.position = Vector3(0, -l1, 0)
		sh.add_child(kn)
		Kit.limb(kn, Vector3.ZERO, Vector3(0, -l2, 0), 0.05, 0.035, fur, true)
		var pw := Node3D.new()
		pw.position = Vector3(0, -l2, 0)
		kn.add_child(pw)
		Kit.mi(pw, Kit.blob(0.05, 51, 0.05, Vector3(0.8, 0.5, 1.4), 8, 10), frost, Vector3(0, -0.015, 0.03))
		Kit.crystal(kn, Vector3(0, -0.04, -0.03), Vector3(0, 0.5, -1.0), 0.1, 0.018, ice, 4)
		legs.append({"sh": sh, "kn": kn, "pw": pw, "front": d.front, "side": d.side})
	# tail: frosted brush with crystal tip
	var parent: Node3D = body
	var pos := Vector3(0, 0.12, -0.6)
	for i in 3:
		var seg := Node3D.new()
		seg.position = pos
		parent.add_child(seg)
		Kit.limb(seg, Vector3.ZERO, Vector3(0, 0, -0.18), 0.05 - i * 0.01, 0.04 - i * 0.01, fur2, true, 6)
		Kit.sphere(seg, 0.045 - i * 0.008, frost, Vector3(0, 0.02, -0.09), Vector3(1.0, 0.8, 1.6))
		tail.append(seg)
		parent = seg
		pos = Vector3(0, 0, -0.18)
	Kit.cluster(parent, Vector3(0, 0, -0.2), Vector3(0, 0.3, -1), 3, 0.18, 0.025, ice, rng, 0.4)

func _animate(delta: float) -> void:
	if body == null:
		return
	var v := move_speed
	var a: float = clamp(v / 5.0, 0.0, 1.0)
	_phase += delta * (3.0 + v * 1.9)
	var gallop: float = clamp((v - 3.0) / 1.5, 0.0, 1.0)
	var atk := one_k("attack")
	var hurt := one_k("hurt") + one_k("stagger")
	var roar := one_k("roar")
	if pose == "dead":
		_dead_t = min(_dead_t + delta * 2.2, 1.0)
		var k := ease(_dead_t, 0.4)
		body.position.y = lerp(0.62, 0.2, k)
		body.rotation = Vector3(0, 0, lerp(0.0, PI * 0.5, k))
		neck.rotation = Vector3(0.3 * k, 0.5 * k, 0)
		jaw.rotation.x = 0.5 * k
		for i in legs.size():
			var l: Dictionary = legs[i]
			l.sh.rotation = Vector3(lerp(0.0, -0.9 + 0.5 * (i % 2), k), 0, 0)
			l.kn.rotation = Vector3(0.7 * k, 0, 0)
		for em in eye_mats:
			em.emission_energy_multiplier = 0.0
		return
	_dead_t = 0.0
	body.rotation.z = 0.0
	for em in eye_mats:
		em.emission_energy_multiplier = 3.0 + sin(t * 9.0) * 0.8
	var crouch := 1.0 if pose == "crouch" else 0.0
	# gait offsets: trot (diagonal pairs) -> gallop (bound)
	var offs := [0.0, lerp(PI, 0.35, gallop), lerp(PI, PI * 0.95, gallop), lerp(0.0, PI * 1.25, gallop)]
	var bob: float = absf(sin(_phase)) * 0.06 * a
	body.position.y = 0.62 + bob - crouch * 0.22 - atk * 0.02
	body.rotation.x = sin(_phase * 1.0 + 0.6) * 0.1 * a * (0.5 + gallop) + crouch * 0.12 - atk * 0.25 + hurt * -0.2
	body.rotation.y = sin(_phase * 0.5) * 0.04 * a
	for i in legs.size():
		var l: Dictionary = legs[i]
		var s := sin(_phase + offs[i])
		var c := cos(_phase + offs[i])
		var sw: float = s * (0.55 + 0.45 * gallop) * a
		var lift: float = max(0.0, c) * (0.9 + 0.4 * gallop) * a
		if l.front:
			l.sh.rotation.x = sw - 0.05 + crouch * 0.55 - atk * 1.1
			l.kn.rotation.x = -lift * 0.9 - 0.12 - crouch * 0.9 - atk * 0.3
			l.pw.rotation.x = lift * 0.5 + crouch * 0.4
		else:
			l.sh.rotation.x = sw - 0.4 - crouch * 0.5 + atk * 1.0
			l.kn.rotation.x = lift * 1.0 + 0.55 + crouch * 0.7 - atk * 0.7
			l.pw.rotation.x = -lift * 0.6 - 0.2
		l.sh.rotation.z = l.side * (0.04 + crouch * 0.18)
	# head & neck: low and forward when running, up and sniffing at rest
	var idle := 1.0 - a
	neck.rotation.x = lerp(0.1, -0.45, a) + sin(t * 1.3) * 0.05 * idle - roar * 0.9 + atk * -0.35 + crouch * 0.4 + hurt * -0.3
	head.rotation.x = lerp(0.05, 0.35, a) + sin(t * 2.1) * 0.04 * idle + roar * 0.5
	head.rotation.y = sin(t * 0.8) * 0.3 * idle
	jaw.rotation.x = 0.1 + atk * 0.9 + roar * 0.8 + a * 0.25 + (sin(_phase * 2.0) * 0.07 * a) + crouch * 0.35
	# tail
	for i in tail.size():
		var sg: Node3D = tail[i]
		sg.rotation.y = sin(t * 3.0 - i * 0.7 + _phase * 0.2) * (0.25 + 0.2 * idle)
		sg.rotation.x = -0.35 + a * 0.45 + crouch * 0.5 if i == 0 else 0.15
