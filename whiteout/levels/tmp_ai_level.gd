extends "res://levels/level.gd"
func build() -> void:
	env_interior(0.5)
	add_spawn("start", Vector3(0, 0, 10), PI)
	floor_rect(-30, -30, 30, 30, 0.0, "concrete")
	box(Vector3(0, 3, -30.5), Vector3(62, 6, 1), "brick")
	box(Vector3(0, 3, 30.5), Vector3(62, 6, 1), "brick")
	box(Vector3(-30.5, 3, 0), Vector3(1, 6, 62), "brick")
	box(Vector3(30.5, 3, 0), Vector3(1, 6, 62), "brick")
	light(Vector3(0, 5, 0), Color(1, 1, 1), 3.0, 40.0, false)
