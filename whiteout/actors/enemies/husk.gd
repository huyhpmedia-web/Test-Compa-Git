extends "res://actors/enemy.gd"
## Husk: a Rimebound wrapped in thick crystalline armour plates. Slow, heavy grab.
## Bullets chip the armour (armor_hp) at a weapon-dependent rate and do NOTHING to the flesh
## until it is gone: pistol 20%, magnum 35%, shotgun pellets 60%; fire 100% and melts it.
## Plates visibly break off and fall as the armour drops. Then flesh HP (~90).
## params: armor_hp (default 120), rime (crystal intensity)

const Kit = preload("res://actors/kit.gd")
const RimeLook = preload("res://actors/rime_look.gd")

var armor_hp := 120.0
var armor_max := 120.0
var rime := 1.2
var _plates: Array = []       # MeshInstance3D, in shedding order
var _shed := 0
var _armor_flash := 0.0

func _ready() -> void:
	armor_max = armor_hp
	max_hp = 90.0 * [0.8, 1.0, 1.25][Game.difficulty]
	speed = 0.75
	run_speed = 1.2
	turn_speed = 2.6
	attack_range = 1.7
	attack_damage = 26
	attack_cooldown = 2.6
	stagger_threshold = 90.0
	head_height = 1.62
	fire_weakness = 1.0
	sep_radius = 1.4
	sight = 12.0
	super._ready()

func _sound(kind: String) -> String:
	return "husk_" + kind

func _setup_collision() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.5
	cap.height = 1.95
	col.shape = cap
	col.position.y = 0.98
	add_child(col)

const CharacterModel = preload("res://actors/character_model.gd")

func _make_model() -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(uid) if uid != "" else randi()
	var h := CharacterModel.new()
	h.setup({"model": "husk"})
	h.pose = "zombie"
	RimeLook.decorate(h, rime * 0.6, rng.randi())
	var s: float = h._s
	var m := Kit.mat("ice_deep")
	var list: Array = []
	# --- armour plates: [bone, bone-local pos, dir, length, width, thickness]; limb bones run along +Y, torso bones are y-up / z-forward
	for sd in ["l", "r"]:
		var x := 1.0 if sd == "l" else -1.0
		list.append(["upperarm_" + sd, Vector3(0.05, 0.08, 0.02), Vector3(0.9, 0.6, 0.0), 0.36, 0.13, 0.05])
		list.append(["upperarm_" + sd, Vector3(0.0, 0.2, 0.06), Vector3(0.0, 0.5, 1.0), 0.3, 0.1, 0.045])
		list.append(["lowerarm_" + sd, Vector3(0.0, 0.08, -0.05), Vector3(0.0, 0.4, -1.0), 0.3, 0.09, 0.04])
		list.append(["lowerarm_" + sd, Vector3(0.04, 0.18, 0.03), Vector3(0.8, 0.5, 0.3), 0.24, 0.07, 0.035])
		list.append(["thigh_" + sd, Vector3(0.0, 0.14, 0.08), Vector3(0.0, -0.4, 1.0), 0.32, 0.1, 0.05])
		list.append(["thigh_" + sd, Vector3(0.08 * x, 0.22, 0.0), Vector3(x, -0.5, 0.0), 0.28, 0.09, 0.045])
		list.append(["calf_" + sd, Vector3(0.0, 0.14, 0.07), Vector3(0.0, -0.4, 1.0), 0.28, 0.08, 0.04])
		list.append(["clavicle_" + sd, Vector3(0.06 * x, 0.04, 0.0), Vector3(x * 0.6, 1.0, -0.2), 0.34, 0.12, 0.05])
	for i in 4:
		list.append(["spine_03", Vector3((i - 1.5) * 0.09, 0.08 + (i % 2) * 0.1, 0.11), Vector3((i - 1.5) * 0.35, 0.3 + (i % 2) * 0.2, 1.0), 0.3, 0.1, 0.05])
		list.append(["spine_03", Vector3((i - 1.5) * 0.1, 0.05 + (i % 2) * 0.12, -0.12), Vector3((i - 1.5) * 0.35, 0.9, -1.0), 0.42 + (i % 2) * 0.2, 0.11, 0.055])
	list.append(["spine_02", Vector3(0.0, 0.05, -0.12), Vector3(0, 0.7, -1.0), 0.45, 0.12, 0.055])
	list.append(["spine_01", Vector3(0.08, 0.05, 0.12), Vector3(0.3, 0.3, 1.0), 0.28, 0.09, 0.045])
	list.append(["head", Vector3(0, 0.15, -0.03), Vector3(0, 1.0, -0.5), 0.26, 0.06, 0.055])
	list.append(["head", Vector3(-0.05, 0.14, 0.0), Vector3(-0.8, 1.0, -0.3), 0.2, 0.045, 0.045])
	list.append(["head", Vector3(0.05, 0.14, 0.0), Vector3(0.8, 1.0, -0.3), 0.2, 0.045, 0.045])
	for e in list:
		var ba: Node3D = h.bone_attachment(e[0])
		if ba == null:
			continue
		var n := Kit.crystal(ba, e[1], e[2], e[3], 1.0, m, rng.randi() % 8)
		# flatten into a plate: width x length x thickness
		var bs: Basis = n.transform.basis.orthonormalized()
		n.transform.basis = Basis(bs.x * e[4] * 1.5, bs.y * e[3] * 1.4, bs.z * e[5] * 2.4)
		_plates.append(n)
	# shedding order: shuffled, but chest/head plates tend to go last
	for i in range(_plates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = _plates[i]
		_plates[i] = _plates[j]
		_plates[j] = tmp
	return h

func fear(pos: Vector3, dur: float = 4.0) -> void:
	super.fear(pos, dur * 0.4)

func _bullet_efficiency() -> float:
	match str(Game.equipped):
		"shotgun": return 0.6
		"magnum": return 0.35
		_: return 0.2

func take_hit(dmg: float, pos: Vector3, dir: Vector3, headshot: bool) -> void:
	if state == "dead" or (state == "dormant" and dormant):
		return
	if armor_hp > 0.0:
		awake = true
		var chip := dmg * (0.5 if headshot else 1.0) * _bullet_efficiency()
		_chip_armor(chip, pos)
		Sfx.play_at(_sound("armor"), global_position, -2.0, randf_range(0.9, 1.15))
		velocity += Vector3(dir.x, 0, dir.z).normalized() * 0.3
		if state in ["idle", "wander"]:
			_set_state("chase")
		return
	super.take_hit(dmg, pos, dir, headshot)

func burn(dmg: float, pos: Vector3) -> void:
	if armor_hp > 0.0:
		# fire melts the armour at full strength, plus extra melt
		awake = true
		_chip_armor(dmg * 1.0 + 3.0, global_position + Vector3(0, 1.2, 0))
		fear(pos, 3.0)
		return
	super.burn(dmg, pos)

func _chip_armor(amount: float, pos: Vector3) -> void:
	var before := armor_hp
	armor_hp = max(0.0, armor_hp - amount)
	_armor_flash = 0.15
	Kit.shard_burst(get_tree().current_scene, pos, 2, 2.0, 0.07)
	# shed plates progressively
	var want := int(floor(float(_plates.size()) * (1.0 - armor_hp / armor_max)))
	if armor_hp <= 0.0:
		want = _plates.size()
	while _shed < want and _shed < _plates.size():
		var pl: MeshInstance3D = _plates[_shed]
		_shed += 1
		if is_instance_valid(pl):
			Kit.shard_burst(get_tree().current_scene, pl.global_position, 4, 2.5, 0.1)
			Kit.drop_piece(pl, get_tree().current_scene, (pl.global_position - global_position).normalized() * 2.0)
			Sfx.play_at(_sound("crack"), global_position, 2.0)
	if before > 0.0 and armor_hp <= 0.0:
		_stagger_acc = 0.0
		_set_state("stagger")
		Sfx.play_at(_sound("shatter"), global_position, 4.0)

func _attack() -> void:
	_atk_cd = attack_cooldown
	_set_state("attack")
	if model and model.has_method("play"):
		model.play("grab")
	Sfx.play_at(_sound("attack"), global_position)

func _on_death() -> void:
	var w := get_tree().current_scene
	for pl in _plates:
		if is_instance_valid(pl):
			Kit.drop_piece(pl, w, (pl.global_position - global_position).normalized() * 1.5)
	Kit.shard_burst(w, global_position + Vector3(0, 1.0, 0), 8, 3.0, 0.1)
