extends "res://levels/level.gd"
## Reference/test level reproducing the art-direction image: a snowy courtyard in front
## of a red-brick building with a corrugated shed and bare trees. Also a living example
## of the level API for level authors.

func build() -> void:
	env_exterior_night(true)
	add_spawn("start", Vector3(0, 0, 10), PI)
	# ground
	floor_rect(-20, -20, 20, 20, 0.0, "snow")
	# building facade (north)
	var bz := -8.0
	box(Vector3(-4, 5, bz - 3), Vector3(22, 10, 6), "brick")
	# portico with columns and steps
	box(Vector3(-8, 3.6, bz + 1.2), Vector3(6, 0.4, 2.6), "concrete")
	for x in [-10.5, -5.5]:
		cyl(Vector3(x, 1.8, bz + 2.2), 0.3, 3.6, "concrete")
	stairs(Vector3(-8, 0, bz + 0.0), 4.0, 1.6, 0.6, "+z", "concrete")
	door("ty_front", Vector3(-8, 0.6, bz - 0.01), 0.0, {"double": true, "width": 1.8, "mat": "plaster", "lock_flag": "never", "locked_msg": "The main doors are barricaded from inside."})
	for i in 4:
		Props.window(geo, Vector3(-1 + i * 3.0 - 2.0, 6.5, bz + 0.01), 0.0, 1.5, 2.0)
		if i > 1:
			Props.window(geo, Vector3(-1 + i * 3.0 - 2.0, 2.4, bz + 0.01), 0.0, 1.5, 2.0, i == 3)
	Props.pipe(geo, Vector3(-2.5, 0, bz + 0.15), Vector3(-2.5, 9.5, bz + 0.15), 0.07, "metal_painted")
	# perimeter walls
	box(Vector3(12, 2, -6), Vector3(16, 4, 0.6), "brick_dark")
	box(Vector3(20, 2, 7), Vector3(0.6, 4, 26), "brick_dark")
	# shed + trees
	Props.shed(geo, Vector3(9, 0, -1), -0.3)
	Props.tree(geo, Vector3(4, 0, -2), 11.0)
	Props.tree(geo, Vector3(15, 0, 4), 9.0)
	Props.debris(geo, Vector3(1, 0, 4), 0.0, 5)
	Props.lamp_post(geo, Vector3(-3, 0, 6), PI)
	light(Vector3(-8, 3.2, bz + 1.2), Color(1, 0.8, 0.55), 1.5, 7.0)
	pickup("ty_ammo", "ammo_9mm", 15, Vector3(2, 0.02, 6))
	pickup("ty_gel", "gel", 1, Vector3(-3, 0.02, 3))
	note("ty_note", Vector3(1, 0.02, 8), "Shelter Notice", "[b]HOLLOW CREEK EMERGENCY MANAGEMENT[/b]\n\nThis building is a designated warming shelter.\nHALCYON has assigned your household a priority score.\nPlease wait for your score to be called.")
	enemy("ty_z1", "zombie", Vector3(3, 0, -3), 0.5)
	enemy("ty_z2", "zombie", Vector3(-6, 0, 0), 0.0, {"variant": "cop"})

func on_enter() -> void:
	UI.title_card("TEST COURTYARD", "Dev level")
