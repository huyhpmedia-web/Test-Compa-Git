extends Node
## Dev harness (R7-C): load a level once and save several views.
## godot --path . res://tools/shot_multi.tscn -- level=l4_meridian prefix=/tmp/x views=x,y,z,yaw,pitch;x,y,z,yaw,pitch frames=60 flags=a,b

func _ready() -> void:
	name = "World"
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	Game.level_id = args.get("level", "test_yard")
	Game.spawn_id = args.get("spawn", "start")
	if Game.inventory.is_empty():
		Game.add_item("knife")
		Game.add_item("handgun")
		Game.set_ammo_loaded("handgun", 12)
		Game.add_item("ammo_9mm", 30)
		Game.equipped = "handgun"
	for f in args.get("flags", "").split(",", false):
		Game.flags[f] = true
	await get_tree().process_frame
	Game._load_level()
	for i in 30:
		await get_tree().process_frame
	var views: PackedStringArray = args.get("views", "").split(";", false)
	var n := 0
	for v in views:
		var p := v.split(",")
		if Game.player:
			Game.player.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
			Game.player.cam_yaw = float(p[3])
			Game.player.model.rotation.y = float(p[3]) + PI
			Game.player.cam_pitch = float(p[4])
		for i in int(args.get("frames", "40")):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [args.get("prefix", "/tmp/shot"), n])
		print("SHOT_SAVED ", n)
		n += 1
	get_tree().quit()
