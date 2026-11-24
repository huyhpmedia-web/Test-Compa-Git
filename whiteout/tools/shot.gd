extends Node
## Dev harness: loads a level, waits, optionally moves the camera, saves a screenshot, quits.
## godot --path . res://tools/shot.tscn -- level=l1_overpass spawn=start frames=90 out=/tmp/x.png yaw=0 pitch=-0.1 pos=x,y,z wait_dialog=1

func _ready() -> void:
	name = "World"  # Game._load_level reuses a current scene named World
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
	var frames := int(args.get("frames", "90"))
	for i in frames:
		await get_tree().process_frame
		if i == 5 and Game.player:
			if args.has("pos"):
				var p = args.pos.split(",")
				Game.player.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
			if args.has("yaw"):
				Game.player.cam_yaw = float(args.yaw)
				Game.player.model.rotation.y = float(args.yaw) + PI
			if args.has("pitch"):
				Game.player.cam_pitch = float(args.pitch)
			if args.has("aim"):
				Input.action_press("aim")
		if i == 8 and args.has("vgi"):
			# R9 experiment: runtime-baked VoxelGI around a point (cx,cy,cz,sx,sy,sz)
			var v = args.vgi.split(",")
			var vg := VoxelGI.new()
			vg.size = Vector3(float(v[3]), float(v[4]), float(v[5]))
			vg.subdiv = VoxelGI.SUBDIV_128
			Game.current_level.add_child(vg)
			vg.global_position = Vector3(float(v[0]), float(v[1]), float(v[2]))
			var t0 := Time.get_ticks_msec()
			vg.bake(Game.current_level)
			print("VGI baked in ", Time.get_ticks_msec() - t0, " ms data=", vg.data != null)
			if args.get("nosdf", "1") == "1":
				var we := get_tree().root.find_children("*", "WorldEnvironment", true, false)
				for w in we:
					(w as WorldEnvironment).environment.sdfgi_enabled = false
	if args.has("out"):
		get_viewport().get_texture().get_image().save_png(args.out)
		print("SHOT_SAVED ", args.out)
	print("SMOKE_OK ", Game.level_id)
	get_tree().quit()
