extends Node
## Dev harness: aim + fire in a level and capture a frame sequence.
## godot --path . res://tools/shoot_shot.tscn -- level=test_yard weapon=handgun yaw=0 pitch=-0.05 pos=x,y,z aim=1 fire=40 caps=41,43,46,60 out=/tmp/s.png  (-> /tmp/s_41.png ...)
func _ready() -> void:
	name = "World"
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	Game.level_id = args.get("level", "test_yard")
	Game.spawn_id = args.get("spawn", "start")
	var w: String = args.get("weapon", "handgun")
	Game.add_item("knife")
	for it in [["handgun", "ammo_9mm"], ["shotgun", "ammo_shell"], ["magnum", "ammo_44"], ["launcher", "ammo_grenade"]]:
		Game.add_item(it[0]); Game.add_item(it[1], 30)
	Game.set_ammo_loaded("handgun", 12); Game.set_ammo_loaded("shotgun", 6); Game.set_ammo_loaded("magnum", 6)
	Game.equipped = w
	await get_tree().process_frame
	Game._load_level()
	var caps: PackedStringArray = String(args.get("caps", "")).split(",", false)
	var fire_at := int(args.get("fire", "-1"))
	var frames := int(args.get("frames", "90"))
	for i in frames:
		await get_tree().process_frame
		var p = Game.player
		if i == 5 and p:
			if args.has("pos"):
				var q = args.pos.split(",")
				p.global_position = Vector3(float(q[0]), float(q[1]), float(q[2]))
			if args.has("yaw"):
				p.cam_yaw = float(args.yaw)
				p.model.rotation.y = float(args.yaw) + PI
			if args.has("pitch"):
				p.cam_pitch = float(args.pitch)
			if args.get("aim", "0") == "1":
				Input.action_press("aim")
		if p and args.has("target") and (i == 5 or i == fire_at - 1):
			var best: Node3D = null
			for e in get_tree().get_nodes_in_group("enemy"):
				if best == null or e.global_position.distance_to(p.global_position) < best.global_position.distance_to(p.global_position):
					best = e
			if best:
				var d: Vector3 = best.global_position - p.global_position
				p.cam_yaw = atan2(d.x, d.z) + PI
				p.model.rotation.y = atan2(d.x, d.z)
				p.cam_pitch = atan2(1.15 - 1.65, Vector2(d.x, d.z).length())
		if p and i == fire_at:
			p.fire_cd = 0.0
			p._try_fire()
		if str(i) in caps:
			get_viewport().get_texture().get_image().save_png(String(args.out).replace(".png", "_%d.png" % i))
	if args.has("out"):
		get_viewport().get_texture().get_image().save_png(args.out)
	print("SHOOT_DONE")
	get_tree().quit()
