extends Area3D
## R8-C: reverb zone. While the player stands inside, the SFX/ambience reverb morphs to `preset`
## (see Sfx.SPACES). Overlapping zones: the smallest one wins (priority = -volume).

var preset := "room"
var size := Vector3.ONE

static func make(parent: Node, preset_id: String, center: Vector3, sz: Vector3) -> Area3D:
	var z: Area3D = load("res://world/audio_zone.gd").new()
	z.preset = preset_id
	z.size = sz
	z.name = "AudioZone_" + preset_id
	parent.add_child(z)
	z.global_position = center
	return z

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	add_child(cs)
	body_entered.connect(func(b2: Node):
		if b2.is_in_group("player"):
			Sfx.enter_space(_key(), preset, -size.x * size.y * size.z))
	body_exited.connect(func(b2: Node):
		if b2.is_in_group("player"):
			Sfx.exit_space(_key()))

func _key() -> String:
	return str(get_instance_id())

func _exit_tree() -> void:
	Sfx.exit_space(_key())
