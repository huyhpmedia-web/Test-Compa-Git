extends Node
## R9 guard / grab test. godot --path . res://tools/grab_test.tscn -- out=/prefix [level=l2_school]
## Checks: guard cuts frontal damage to ~30%; a grab starts a struggle, mashing breaks free and staggers the grabber;
## not mashing lets the bite land. Saves screenshots of the guard pose and the grab.

func _ready() -> void:
	name = "World"
	var out := "/tmp/grab"
	var lv := "l3_church"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
		if a.begins_with("level="): lv = a.substr(6)
	Game.level_id = lv
	Game.spawn_id = "start"
	Game.add_item("knife"); Game.add_item("handgun"); Game.set_ammo_loaded("handgun", 12); Game.equipped = "handgun"
	await get_tree().process_frame
	Game._load_level()
	for i in 30: await get_tree().process_frame
	var p = Game.player
	var en: Node3D = null
	var bd := 1e9
	for e in get_tree().get_nodes_in_group("enemy"):
		var sp: String = e.get_script().resource_path
		if float(e.get("hp")) > 0.0 and String(e.get("state")) != "dormant" and e.global_position.distance_to(p.global_position) < bd:
			bd = e.global_position.distance_to(p.global_position); en = e
	if en == null:
		print("GRABTEST FAIL no enemy"); get_tree().quit(); return
	en.set_physics_process(false)
	var fwd: Vector3 = p.model.global_transform.basis.z; fwd.y = 0; fwd = fwd.normalized()
	en.global_position = p.global_position + fwd * 0.9
	en.look_at(p.global_position, Vector3.UP, true)
	p.cam_yaw = p.model.rotation.y + PI + 0.6
	p.cam_pitch = -0.1
	# --- guard
	Input.action_press("guard")
	for i in 25: await get_tree().process_frame
	_snap(out + "_guard.png")
	var m = p.model
	var sk: Skeleton3D = m.skeleton
	for bn in ["head", "upperarm_l", "lowerarm_l", "hand_l", "hand_r"]:
		var gp: Vector3 = m.global_transform.affine_inverse() * (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bn)).origin)
		print("GRABTEST bone ", bn, " ", gp)
	print("GRABTEST guard_w ", m._guard_w, " guarding ", p.guarding, " guard ", m.guard)
	var hp0: int = Game.hp
	p.invuln = 0.0
	p.hurt(20, en.global_position, true)
	var gd: int = hp0 - Game.hp
	print("GRABTEST guard dmg ", gd, " (unguarded 20) grabbed=", p._grab_t > 0.0)
	Input.action_release("guard")
	for i in 40: await get_tree().process_frame
	# --- grab + mash
	Game.hp = Game.MAX_HP
	p.invuln = 0.0
	p.hurt(20, en.global_position, true)
	print("GRABTEST grab started=", p._grab_t > 0.0, " need=", p._grab_need)
	for i in 12: await get_tree().process_frame
	_snap(out + "_grab.png")
	var k := 0
	while p._grab_t > 0.0 and k < 200:
		if k % 6 == 0: Input.action_press("interact")
		elif k % 6 == 3: Input.action_release("interact")
		await get_tree().process_frame
		k += 1
	Input.action_release("interact")
	print("GRABTEST freed after ", k, " frames, hp ", Game.hp, " enemy state ", en.get("state"))
	for i in 8: await get_tree().process_frame
	_snap(out + "_shove.png")
	if DisplayServer.get_name() != "headless":
		get_tree().quit()
		return
	# --- grab, no mash
	for i in 70: await get_tree().process_frame
	en.global_position = p.global_position + fwd * 0.9
	Game.hp = Game.MAX_HP
	p.invuln = 0.0
	p.hurt(20, en.global_position, true)
	for i in 200: await get_tree().process_frame
	print("GRABTEST bitten: hp ", Game.hp, " of ", Game.MAX_HP, " grab over=", p._grab_t <= 0.0)
	get_tree().quit()

func _snap(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	get_viewport().get_texture().get_image().save_png(path)
