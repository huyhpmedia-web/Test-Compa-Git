extends Node3D
## Head close-up montage under a flashlight + moon rig: front / 3-4 / back / top panels.
## godot --path . res://tools/b_head.tscn -- model=elias out=x.png [zombie=1] [w=640] [h=360] [views=front,side,back,top]
func _ready() -> void:
	var out := "/tmp/head.png"; var model := "elias"; var zombie := false; var pw := 640; var ph := 400
	var views := ["front", "side", "back", "top"]
	var distm := 0.85
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
		elif a.begins_with("model="): model = a.substr(6)
		elif a.begins_with("zombie="): zombie = a.substr(7) == "1"
		elif a.begins_with("w="): pw = int(a.substr(2))
		elif a.begins_with("h="): ph = int(a.substr(2))
		elif a.begins_with("dist="): distm = float(a.substr(5))
		elif a.begins_with("views="): views = a.substr(6).split(",")
	var CM = load("res://actors/character_model.gd")
	var RL = load("res://actors/rime_look.gd")
	var svp := SubViewport.new(); svp.size = Vector2i(pw, ph); svp.own_world_3d = true; svp.msaa_3d = Viewport.MSAA_4X
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(svp)
	var e := Environment.new(); e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.02, 0.025, 0.035)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(0.25, 0.32, 0.45); e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new(); we.environment = e; svp.add_child(we)
	var key := DirectionalLight3D.new(); key.rotation_degrees = Vector3(-35, 25, 0); key.light_energy = 0.35; key.light_color = Color(0.6, 0.72, 1.0); key.shadow_enabled = true; svp.add_child(key)
	var m: Node3D = CM.new(); m.setup({"model": model, "zombie": zombie}); svp.add_child(m)
	m.pose = "zombie" if zombie else "normal"
	if zombie and RL.has_method("decorate"): RL.decorate(m, 1.0, 100, {})
	var cam := Camera3D.new(); svp.add_child(cam); cam.fov = 28; cam.current = true
	var sl := SpotLight3D.new(); svp.add_child(sl)
	sl.light_energy = 1.4; sl.spot_range = 8.0; sl.spot_angle = 35.0; sl.light_color = Color(1.0, 0.95, 0.85); sl.shadow_enabled = true
	for i in 20: await get_tree().process_frame
	var hp: Vector3 = m.head.global_position + Vector3(0, 0.06, 0)
	var img := Image.create(pw * views.size(), ph, false, Image.FORMAT_RGBA8)
	var k := 0
	for v in views:
		var dir := Vector3(0, 0, 1)
		match v:
			"front": dir = Vector3(0, 0.05, 1)
			"side": dir = Vector3(0.8, 0.15, 0.7)
			"back": dir = Vector3(0, 0.1, -1)
			"top": dir = Vector3(0.05, 1.0, 0.45)
			"backtop": dir = Vector3(0.0, 0.8, -0.7)
		dir = dir.normalized()
		var hbas: Basis = m.head.global_transform.basis.orthonormalized()
		var tgt := hp
		if zombie:
			tgt = m.head.global_position + hbas * Vector3(0, 0.0, 0.07)   # centre of the (bowed) face
			if v == "top":
				dir = Vector3(0.0, 0.7, 0.7).normalized()
		cam.look_at_from_position(tgt + dir * distm, tgt, Vector3.UP if v != "top" else Vector3(0, 0, -1))
		sl.look_at_from_position(cam.position + Vector3(0.15, 0.1, 0), tgt, Vector3.UP)
		for i in 6: await get_tree().process_frame
		var im := svp.get_texture().get_image(); im.convert(Image.FORMAT_RGBA8)
		img.blit_rect(im, Rect2i(0, 0, pw, ph), Vector2i(k * pw, 0)); k += 1
	img.save_png(out)
	print("CHAR_VIEW_DONE ", out)
	get_tree().quit()
