extends "res://actors/models/creature.gd"
## THE CHOIR: a 5 m pillar of a dozen fused congregants. Five glowing singing heads are weak points.
const Kit = preload("res://actors/kit.gd")
const EnemyGlb = preload("res://actors/models/enemy_glb.gd")

const WEAK := [0, 1, 2, 3, 4]   # glb: Head0..Head4 (the procedural fallback uses its own indices, see _build_procedural)
const WEAK_PROC := [2, 4, 6, 8, 10]
var heads: Array = []        # {node, mats, light, alive, k, mouth}
var arm_l: Node3D
var arm_r: Node3D
var arm_raise := 0.0         # 0..1 set by the owner (sweep telegraph)
var arm_yaw := 0.0           # radians, sweep angle set by the owner
var sag := 0.0               # 0..1 (heads destroyed)
var cracks: Array = []
var pulse := 0.0             # hum pulse flash 0..1
var column: Node3D

func _ready() -> void:
	_build()

var _hd := false
var _halos: Array = []        # hd: {mesh, mat} per head
var _skins: Array = []        # hd: duplicated flesh material per head (tinted dark when the head dies)

func _build() -> void:
	var hd := EnemyGlb.load_scene("choir_hd.glb")
	if hd != null and EnemyGlb.find(hd, "Head4") != null and EnemyGlb.find(hd, "Pillar") != null:
		_build_hd(hd)
		return
	var g := EnemyGlb.load_scene("choir.glb")
	if g != null and EnemyGlb.find(g, "Head0") != null and EnemyGlb.find(g, "ArmL") != null:
		_build_glb(g)
	else:
		_build_procedural()

## HD build (tools/charpipe/bosses/hd_choir.py, Tripo H3.1): Pillar (static, textured PBR), Head0..Head4 (weak points, pivot at the head
## centre, each with a Head<i>_glow halo child that is additive-blended and pulses), ArmL/ArmR (sweep pieces).
func _build_hd(g: Node3D) -> void:
	_hd = true
	column = g
	add_child(g)
	for i in 5:
		var hn := EnemyGlb.find(g, "Head%d" % i) as MeshInstance3D
		var halo := EnemyGlb.find(hn, "Head%d_glow" % i) as MeshInstance3D
		var hm := (halo.mesh.surface_get_material(0).duplicate() as StandardMaterial3D)
		hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hm.cull_mode = BaseMaterial3D.CULL_DISABLED
		hm.albedo_color = Color(0.35, 0.85, 1.0, 0.55)
		hm.emission_enabled = false
		halo.material_override = hm
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# per-head copy of the flesh material: tinted + faintly emissive while the head sings
		var sk := hn.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
		sk.emission_enabled = true
		sk.emission = Color(0.35, 0.8, 1.0)
		sk.emission_energy_multiplier = 0.1
		hn.set_surface_override_material(0, sk)
		var l := OmniLight3D.new()
		l.light_color = Color(0.45, 0.9, 1.0)
		l.light_energy = 1.0
		l.omni_range = 4.0
		l.shadow_enabled = false
		l.position = Vector3(0, 0.0, 0.55)
		hn.add_child(l)
		_halos.append(halo)
		_skins.append(sk)
		heads.append({"node": hn, "mats": [hm], "light": l, "alive": true, "k": 0.0, "weak": true, "mouth": null, "skin": sk, "halo": halo})
	arm_l = EnemyGlb.find(g, "ArmL") as Node3D
	arm_r = EnemyGlb.find(g, "ArmR") as Node3D

## glTF build (tools/charpipe/bosses/build_choir.py): Head0..Head4 are the weak points (throat + eyes use emissive
## materials animated here), ArmL/ArmR are the sweep pivots (geometry hangs along -Y), everything else is static.
func _build_glb(g: Node3D) -> void:
	column = g
	add_child(g)
	for i in 5:
		var hn := EnemyGlb.find(g, "Head%d" % i) as Node3D
		var mats: Array = EnemyGlb.unique_mats(hn, "throat") + EnemyGlb.unique_mats(hn, "glow")
		var l := OmniLight3D.new()
		l.light_color = Color(0.45, 0.9, 1.0)
		l.light_energy = 1.0
		l.omni_range = 4.0
		l.shadow_enabled = false
		l.position = Vector3(0, 0.0, 0.55)
		hn.add_child(l)
		heads.append({"node": hn, "mats": mats, "light": l, "alive": true, "k": 0.0, "weak": true, "mouth": null})
	arm_l = EnemyGlb.find(g, "ArmL") as Node3D
	arm_r = EnemyGlb.find(g, "ArmR") as Node3D
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.01, 0.01, 0.02)
	var rng := RandomNumberGenerator.new()
	rng.seed = 778
	for i in 10:
		var y3 := 0.8 + i * 0.4
		var a4 := PI * 0.5 + rng.randf_range(-1.2, 1.2)
		var c := Kit.box(column, Vector3(0.05, rng.randf_range(0.5, 1.1), 0.03), dark, Vector3(cos(a4) * 0.8, y3, sin(a4) * 0.8))
		c.look_at_from_position(c.position, Vector3(0, y3, 0), Vector3.UP)
		c.rotate_object_local(Vector3.FORWARD, rng.randf_range(-0.5, 0.5))
		c.visible = false
		cracks.append(c)

func _build_procedural() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	column = Node3D.new()
	add_child(column)
	var flesh := Kit.mat("flesh_dead")
	var robe := Kit.mat("cloth_dark")
	var ice := Kit.mat("ice")
	var frost := Kit.mat("frost")
	# base mound of frozen bodies and ice
	Kit.mi(column, Kit.blob(1.5, 5, 0.18, Vector3(1.15, 0.7, 1.15), 12, 18), frost, Vector3(0, 0.45, 0))
	Kit.mi(column, Kit.blob(1.1, 8, 0.2, Vector3(1.0, 1.0, 1.0), 12, 18), flesh, Vector3(0, 0.9, 0))
	# core pillar
	Kit.limb(column, Vector3(0, 0.6, 0), Vector3(0, 4.9, 0), 0.6, 0.25, flesh, false, 14)
	for i in 12:
		var f := float(i) / 11.0
		var y := 0.85 + i * 0.36
		var a := PI * 0.5 + (1.0 if i % 2 == 0 else -1.0) * (0.25 + 0.22 * float(i % 6))
		if i in [1, 5, 9, 11, 0, 7]:
			a += PI * 0.9 + rng.randf_range(-0.3, 0.3)
		var rad: float = lerp(1.0, 0.62, f)
		var out := Vector3(cos(a), 0, sin(a))
		var p := out * rad + Vector3(0, y, 0)
		# torso + robe
		var tor := Kit.mi(column, Kit.blob(0.4, 20 + i, 0.1, Vector3(1.1, 1.35, 0.8), 10, 14), robe if i % 3 else flesh, p)
		tor.look_at_from_position(p, p - out, Vector3.UP)
		tor.rotate_object_local(Vector3.RIGHT, -0.25)
		Kit.mi(column, Kit.blob(0.34, 40 + i, 0.15, Vector3(1.0, 1.6, 0.9), 8, 12), robe, p + Vector3(0, -0.45, 0) - out * 0.05)
		# head
		var hd := Node3D.new()
		hd.position = p + out * 0.36 + Vector3(0, 0.66, 0)
		hd.scale = Vector3.ONE * 1.35
		column.add_child(hd)
		hd.transform.basis = Basis.looking_at(-out, Vector3.UP).rotated(out.cross(Vector3.UP).normalized(), 0.0)
		var weak: bool = i in WEAK_PROC
		var skin := Kit.mat("skin_frost") if weak else Kit.mat("flesh_dead")
		Kit.mi(hd, Kit.blob(0.2, 60 + i, 0.06, Vector3(0.88, 1.15, 1.0), 10, 14), skin)
		var mouth_m: Material = Kit.mat("mouth")
		var hm := {"node": hd, "mats": [], "light": null, "alive": true, "k": 0.0, "weak": weak, "mouth": null}
		if weak:
			mouth_m = Kit.glow_unique(Color(0.5, 0.95, 1.0), 3.0)
			hm.mats.append(mouth_m)
		var mouth := Kit.sphere(hd, 0.075, mouth_m, Vector3(0, -0.075, 0.15), Vector3(0.9, 1.5 if weak else 1.2, 0.5))
		hm.mouth = mouth
		for x in [-1.0, 1.0]:
			var em: Material = Kit.mat("mouth")
			if weak:
				em = Kit.glow_unique(Color(0.6, 1.0, 1.0), 4.0)
				hm.mats.append(em)
			Kit.sphere(hd, 0.032, em, Vector3(x * 0.075, 0.05, 0.155), Vector3(1.0, 0.7, 0.5))
		Kit.box(hd, Vector3(0.025, 0.05, 0.03), skin, Vector3(0, -0.01, 0.19))
		if weak:
			Kit.cluster(hd, Vector3(0, 0.18, 0), Vector3(0, 1, -0.2), 6, 0.35, 0.035, Kit.mat("ice_glow"), rng, 0.7)
			var l := OmniLight3D.new()
			l.light_color = Color(0.45, 0.9, 1.0)
			l.light_energy = 1.6
			l.omni_range = 5.0
			l.shadow_enabled = false
			l.position = Vector3(0, 0.05, 0.4)
			hd.add_child(l)
			hm.light = l
		else:
			Kit.cluster(hd, Vector3(0, 0.15, 0), Vector3(0, 1, 0), 2, 0.2, 0.03, ice, rng, 0.8)
		heads.append(hm)
		# fused arms reaching into the core / neighbours
		for s: float in [-1.0, 1.0]:
			var perp := out.cross(Vector3.UP).normalized() * s
			var sh := p + perp * 0.4 + Vector3(0, 0.25, 0)
			var el := sh + perp * 0.15 + Vector3(0, -0.3, 0) + out * 0.1
			var hand := Vector3(0, y + rng.randf_range(-0.2, 0.5), 0) + perp * rng.randf_range(0.05, 0.5)
			Kit.limb(column, sh, el, 0.07, 0.06, flesh, true, 6)
			Kit.limb(column, el, hand, 0.06, 0.05, flesh, true, 6)
	# crystals bursting from the pillar
	for i in 46:
		var a2 := rng.randf() * TAU
		var y2 := rng.randf_range(0.5, 4.8)
		var o := Vector3(cos(a2), rng.randf_range(-0.2, 0.9), sin(a2))
		Kit.crystal(column, Vector3(cos(a2) * 0.7, y2, sin(a2) * 0.7), o, rng.randf_range(0.4, 1.3), rng.randf_range(0.05, 0.13), ice, i)
	for i in 12:
		var a3 := rng.randf() * TAU
		Kit.crystal(column, Vector3(cos(a3) * 1.2, 0.3, sin(a3) * 1.2), Vector3(cos(a3), 0.9, sin(a3)), rng.randf_range(0.8, 1.8), rng.randf_range(0.1, 0.18), ice, i)
	Kit.cluster(column, Vector3(0, 4.9, 0), Vector3(0, 1, 0), 9, 1.4, 0.12, Kit.mat("ice_glow"), rng, 0.6)
	# fused-arm sweepers: thick bundled limbs
	for s: float in [-1.0, 1.0]:
		var piv := Node3D.new()
		piv.position = Vector3(s * 0.75, 2.7, 0.15)
		column.add_child(piv)
		for k in 3:
			var o2 := Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(-0.1, 0.1), rng.randf_range(-0.1, 0.1))
			Kit.limb(piv, o2, Vector3(s * 0.2, -1.1, 0.25) + o2, 0.2, 0.15, flesh, true, 8)
			var el2 := Node3D.new()
			el2.position = Vector3(s * 0.2, -1.1, 0.25)
			piv.add_child(el2)
			Kit.limb(el2, o2, Vector3(0, -1.2, 0.3) + o2, 0.15, 0.1, flesh, true, 8)
			if k == 0:
				Kit.cluster(el2, Vector3(0, -1.3, 0.3), Vector3(0, -1, 0.5), 7, 0.7, 0.05, ice, rng, 0.9)
		if s < 0:
			arm_l = piv
		else:
			arm_r = piv
	# cracks (revealed as heads die)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.01, 0.01, 0.02)
	for i in 10:
		var y3 := 0.8 + i * 0.4
		var a4 := PI * 0.5 + rng.randf_range(-1.2, 1.2)
		var c := Kit.box(column, Vector3(0.05, rng.randf_range(0.5, 1.1), 0.03), dark, Vector3(cos(a4) * 0.88, y3, sin(a4) * 0.88))
		c.look_at_from_position(c.position, Vector3(0, y3, 0), Vector3.UP)
		c.rotate_object_local(Vector3.FORWARD, rng.randf_range(-0.5, 0.5))
		c.visible = false
		cracks.append(c)

func head_world(i: int) -> Vector3:
	return heads[i].node.global_position

func kill_head(i: int) -> void:
	var h: Dictionary = heads[i]
	h.alive = false
	for m in h.mats:
		m.emission_energy_multiplier = 0.0
		m.albedo_color = Color(0.05, 0.08, 0.1)
	if h.light:
		h.light.light_energy = 0.0
	if _hd:
		h.halo.visible = false
		h.skin.emission_energy_multiplier = 0.0
		h.skin.albedo_color = Color(0.32, 0.34, 0.4)
		h.node.rotation.x += 0.3
	else:
		h.node.rotation.x += 0.7
	if h.mouth:
		h.mouth.scale.y *= 1.6
	var dead := 0
	for q in heads:
		if q.weak and not q.alive:
			dead += 1
	for i2 in cracks.size():
		cracks[i2].visible = float(i2) / cracks.size() < float(dead) / WEAK.size()

func flash_head(i: int) -> void:
	heads[i].k = 1.0

func _animate(delta: float) -> void:
	var alive := 0
	for hm in heads:
		var h: Dictionary = hm
		h.k = max(0.0, h.k - delta * 4.0)
		if h.alive:
			alive += 1
			var sing := 0.5 + 0.5 * sin(t * 2.3 + float(heads.find(h)) * 1.1)
			var e: float = 2.2 + sing * 2.0 + h.k * 9.0 + pulse * 6.0
			for m in h.mats:
				if _hd:
					m.albedo_color.a = clampf(0.25 + sing * 0.25 + h.k * 0.5 + pulse * 0.3, 0.0, 1.0)
				else:
					m.emission_energy_multiplier = e
			if _hd:
				h.skin.emission_energy_multiplier = 0.05 + sing * 0.12 + h.k * 1.2 + pulse * 0.4
			if h.light:
				h.light.light_energy = 1.0 + sing * 1.0 + h.k * 4.0 + pulse * 3.0
			if h.mouth:
				h.mouth.scale.y = (1.5 if h.weak else 1.2) * (0.85 + sing * 0.45)
			h.node.rotation.z = sin(t * 0.8 + float(heads.find(h))) * 0.06
	# sag as heads die (pillar cracks and sinks)
	var target_sag := 1.0 - float(heads.filter(func(q): return q.weak and q.alive).size()) / WEAK.size()
	sag = move_toward(sag, target_sag, delta * 0.4)
	column.scale = Vector3(1.0 + 0.04 * sag, 1.0 - 0.14 * sag, 1.0 + 0.04 * sag)
	column.rotation = Vector3(0.03 * sag * sin(1.0), 0, 0.06 * sag)
	column.position.y = -0.1 * sag
	# arms
	var droop := 0.25
	var raise := arm_raise
	if _hd:
		# the pillar twists / leans into the sweep, the two reaching arms swing with it
		column.rotation.y = arm_yaw * 0.22
		column.rotation.x += raise * 0.06
		arm_l.rotation = Vector3(-raise * 0.55 + sin(t * 0.7) * 0.03, arm_yaw * 0.45, 0.0)
		arm_r.rotation = Vector3(-raise * 0.4 + sin(t * 0.7 + 1.0) * 0.03, arm_yaw * 0.5, 0.0)
		return
	arm_l.rotation = Vector3(-raise * 1.4 + sin(t * 0.7) * 0.02, arm_yaw, -droop * (1.0 - raise) - 0.0)
	arm_r.rotation = Vector3(-raise * 1.4 + sin(t * 0.7 + 1.0) * 0.02, arm_yaw, droop * (1.0 - raise))
