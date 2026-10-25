extends "res://actors/enemy.gd"
## Shambler: frost-crusted Rimebound townsperson. Slow, durable, may fake death.
## params: variant ("civilian" | "worker" | "nurse" | "miner"; also "cop"/"medic"/"patient"),
##         crawler (bool), sleeping (bool lying until near), rime (0.3..1.6 crystal growth)

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

const CharacterModel = preload("res://actors/character_model.gd")

## Body (MakeHuman glb) per variant; "civilian" picks randomly from the winter-clothes civilians.
func _body_for(rng: RandomNumberGenerator) -> String:
	match variant:
		"nurse", "medic":
			return "rimebound_nurse"
		"miner":
			return "rimebound_miner"
		"cop":
			return "rimebound_cop"
		"patient":
			return "rimebound_patient"
		"worker":
			return ["rimebound_jacket_m", "rimebound_flannel_m"][rng.randi() % 2]
	var civ := ["rimebound_parka_m", "rimebound_parka_f", "rimebound_jacket_m", "rimebound_flannel_m", "rimebound_tee_m", "rimebound_tee_f"]
	return civ[rng.randi() % civ.size()]

func _make_model() -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(uid) if uid != "" else randi()
	var h := CharacterModel.new()
	h.setup({"model": _body_for(rng), "scale": rng.randf_range(0.96, 1.05)})
	h.pose = "zombie"
	RimeLook.decorate(h, rime * rng.randf_range(0.75, 1.25), rng.randi())
	return h
