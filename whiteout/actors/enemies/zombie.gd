extends "res://actors/enemy.gd"
## Shambler: frost-crusted Rimebound townsperson. Slow, durable, may fake death.
## params: variant ("civilian" | "worker" | "nurse" | "miner"; also "cop"/"medic"/"patient"),
##         crawler (bool), sleeping (bool lying until near), rime (0.3..1.6 crystal growth)

const Kit = preload("res://actors/kit.gd")
const RimeLook = preload("res://actors/rime_look.gd")

var variant := "civilian"
var crawler := false
var sleeping := false
var rime := 1.0

func _ready() -> void:
	max_hp = randf_range(60.0, 85.0) * ([0.75, 1.0, 1.3][Game.difficulty])
	speed = randf_range(0.7, 1.0)
	run_speed = randf_range(0.95, 1.35)
	can_revive = true
	fire_weakness = 1.8
	if crawler:
		max_hp *= 0.6
		run_speed = 0.8
		head_height = 0.4
		attack_range = 1.1
		sep_radius = 0.7
	super._ready()
	if crawler and model:
		model.pose = "crawl"
	if sleeping:
		state = "down"
		_revived = true
		if model:
			model.pose = "dead"

func _make_model() -> Node3D:
	var h := Humanoid.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(uid) if uid != "" else randi()
	var skins := [Color(0.85, 0.68, 0.58), Color(0.65, 0.48, 0.38), Color(0.45, 0.32, 0.24), Color(0.9, 0.75, 0.65)]
	var hair := [Color(0.1, 0.07, 0.05), Color(0.35, 0.25, 0.15), Color(0.6, 0.55, 0.5), Color(0.05, 0.05, 0.05)]
	var cfg := {"zombie": true, "bloody": rng.randf_range(0.2, 0.7), "female": rng.randf() < 0.4,
		"skin": skins[rng.randi() % skins.size()], "hair": hair[rng.randi() % hair.size()],
		"hair_style": ["short", "buzz", "long", "bald", "ponytail"][rng.randi() % 5],
		"height": rng.randf_range(1.6, 1.88), "bulk": rng.randf_range(0.95, 1.2)}
	match variant:
		"cop":
			cfg.merge({"shirt": Color(0.12, 0.16, 0.3), "pants": Color(0.08, 0.1, 0.18), "vest": true, "headgear": "cap" if rng.randf() < 0.4 else ""}, true)
		"medic":
			cfg.merge({"shirt": Color(0.2, 0.3, 0.45), "pants": Color(0.18, 0.25, 0.38)}, true)
		"nurse":
			cfg.merge({"female": true, "shirt": Color(0.22, 0.45, 0.47), "pants": Color(0.2, 0.4, 0.43), "coat": rng.randf() < 0.6,
				"coat_color": Color(0.62, 0.6, 0.64), "hair_style": "ponytail"}, true)
		"worker":
			cfg.merge({"shirt": Color(0.28, 0.28, 0.3), "pants": Color(0.26, 0.26, 0.29), "vest": true, "vest_color": Color(0.8, 0.3, 0.04),
				"gloves": true, "female": false, "bulk": rng.randf_range(1.1, 1.3)}, true)
		"miner":
			cfg.merge({"shirt": Color(0.34, 0.13, 0.1), "pants": Color(0.13, 0.17, 0.27), "female": false, "hair_style": "short",
				"bulk": rng.randf_range(1.1, 1.3), "gloves": true, "shoes": Color(0.2, 0.15, 0.08)}, true)
		"patient":
			cfg.merge({"shirt": Color(0.6, 0.7, 0.72), "pants": Color(0.6, 0.7, 0.72), "long_sleeves": false}, true)
		_:
			var shirts := [Color(0.4, 0.1, 0.1), Color(0.2, 0.3, 0.2), Color(0.5, 0.45, 0.35), Color(0.15, 0.15, 0.2), Color(0.6, 0.55, 0.5)]
			cfg.merge({"shirt": shirts[rng.randi() % shirts.size()], "pants": Color(0.12, 0.13, 0.2).lerp(Color(0.3, 0.25, 0.2), rng.randf()),
				"coat": rng.randf() < 0.35, "coat_color": Color(0.25, 0.2, 0.15).lerp(Color(0.1, 0.1, 0.12), rng.randf())}, true)
	h.setup(cfg)
	h.pose = "zombie"
	var s: float = h.cfg.height / 1.72
	if variant == "miner":
		_miner_gear(h, s)
	elif variant == "nurse":
		# nurse's cap, half crusted over
		Kit.box(h.head, Vector3(0.16, 0.05, 0.1) * s, Kit.mat("frost"), Vector3(0, 0.2, -0.01) * s)
	RimeLook.decorate(h, rime * rng.randf_range(0.75, 1.25), rng.randi())
	return h

func _miner_gear(h: Node3D, s: float) -> void:
	Kit.hardhat(h.head, s, false)  # lamp is dead
	var dn := Kit.mat("denim")
	# overall bib + straps
	Kit.box(h.chest, Vector3(0.27, 0.3, 0.02) * s, dn, Vector3(0, 0.03, 0.12) * s * h.cfg.bulk)
	for x in [-1.0, 1.0]:
		Kit.box(h.chest, Vector3(0.04, 0.02, 0.26) * s, dn, Vector3(x * 0.1, 0.2, 0.02) * s)
		Kit.box(h.chest, Vector3(0.04, 0.34, 0.02) * s, dn, Vector3(x * 0.1, 0.13, 0.12) * s * h.cfg.bulk)
	# reflective strip, mostly crusted over
	Kit.box(h.chest, Vector3(0.28, 0.03, 0.022) * s, Kit.mat("frost"), Vector3(0, -0.08, 0.125) * s * h.cfg.bulk)
