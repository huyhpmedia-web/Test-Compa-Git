extends Node
## Dev harness: loads a level, puts a free camera anywhere and saves a screenshot (boss arena beauty shots).
## godot --path . res://tools/boss_shot.tscn -- level=l3_church cam=46,2.5,-24 look=46,2.8,-37 out=/tmp/x.png [fov=60 frames=90 flags=a,b pos=x,y,z wake=1 set=uid:prop:value]
##   pos = where the (hidden) player stands (keeps level logic / streaming near the boss); wake=1 wakes every boss; light=1 adds a handheld flashlight to the camera
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
	var cam := Camera3D.new()
	var cp: PackedStringArray = String(args.get("cam", "0,2,10")).split(",")
	var lp: PackedStringArray = String(args.get("look", "0,2,0")).split(",")
	add_child(cam)
	cam.global_position = Vector3(float(cp[0]), float(cp[1]), float(cp[2]))
	cam.look_at(Vector3(float(lp[0]), float(lp[1]), float(lp[2])))
	cam.fov = float(args.get("fov", "60"))
	if int(args.get("light", "1")) == 1:
		var sp := SpotLight3D.new()
		sp.light_energy = float(args.get("spotE", "6.0"))
		sp.spot_range = 40.0
		sp.spot_angle = 28.0
		sp.light_color = Color(1.0, 0.95, 0.85)
		sp.shadow_enabled = true
		cam.add_child(sp)
	var frames := int(args.get("frames", "90"))
	for i in frames:
		await get_tree().process_frame
		if i == 4:
			if Game.player:
				if args.has("pos"):
					var p = args.pos.split(",")
					Game.player.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
				Game.player.model.visible = false
			cam.make_current()
		if i == 8 and int(args.get("wake", "0")) == 1:
			for e in get_tree().get_nodes_in_group("enemy"):
				if e.has_method("wake"):
					e.wake()
	if args.has("out"):
		get_viewport().get_texture().get_image().save_png(args.out)
		print("SHOT_SAVED ", args.out)
	print("SMOKE_OK ", Game.level_id)
	get_tree().quit()
