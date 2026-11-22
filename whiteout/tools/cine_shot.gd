extends Node
## R8-C dev harness: film a story cutscene and save frames.
## godot --path . res://tools/cine_shot.tscn -- level=l3_church beat=_choir_reveal arg=1 pos=46,0.1,-12 yaw=3.14
##        times=3,9,16 prefix=/tmp/cine flags=a,b items=a,b
## `arg=1` passes one null argument (trigger callbacks take the player). Cutscenes are forced ON.
const Cutscene = preload("res://world/cutscene.gd")

func _ready() -> void:
	name = "World"
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	Cutscene.force = true
	Game.level_id = args.get("level", "l1_substation")
	Game.spawn_id = args.get("spawn", "start")
	if Game.inventory.is_empty():
		Game.add_item("handgun")
		Game.set_ammo_loaded("handgun", 12)
		Game.equipped = "handgun"
	for f in args.get("flags", "").split(",", false):
		Game.flags[f] = true
	for it in args.get("items", "").split(",", false):
		Game.add_item(it)
	await get_tree().process_frame
	Game._load_level()
	for i in 40:
		await get_tree().process_frame
	var lvl = Game.current_level
	if args.has("pos") and Game.player:
		var p: PackedStringArray = args.pos.split(",")
		Game.player.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		var yaw := float(args.get("yaw", "0"))
		Game.player.model.rotation.y = yaw
		Game.player.cam_yaw = yaw + PI
		for i in 10:
			await get_tree().process_frame
	var beat: String = args.get("beat", "")
	if beat != "" and lvl != null:
		if args.get("arg", "0") == "1":
			lvl.call(beat, Game.player)
		else:
			lvl.call(beat)
	var el := 0.0
	var n := 0
	for ts in args.get("times", "3").split(","):
		var target := float(ts)
		if target > el:
			await get_tree().create_timer(target - el).timeout
			el = target
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [args.get("prefix", "/tmp/cine"), n])
		print("CINE_SAVED ", n, " t=", target)
		n += 1
	get_tree().quit()
