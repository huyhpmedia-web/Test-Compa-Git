extends Node
## Switches a level's town windows / porch lights on when a Game flag is set (world/town.gd power_flag),
## one house at a time, like a feeder being re-energised.
var flag := ""
var _groups: Array = []      # [[cards], [lights]]
var _cd := 0.0

func register(cards: Array, lights: Array) -> void:
	_groups.append([cards, lights])

func _process(delta: float) -> void:
	_cd -= delta
	if _cd > 0.0:
		return
	_cd = 0.5
	if flag == "" or not Game.has_flag(flag):
		return
	set_process(false)
	_groups.shuffle()
	var t := 0.6
	for g in _groups:
		_switch_on.call_deferred(g, t)
		t += randf_range(0.08, 0.35)

func _switch_on(g: Array, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	for c in g[0]:
		if is_instance_valid(c):
			(c as GeometryInstance3D).set_instance_shader_parameter("win_power", 1.0)
	for l in g[1]:
		if is_instance_valid(l):
			(l as Node3D).visible = true
