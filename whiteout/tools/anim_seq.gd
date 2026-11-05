extends Node3D
## Live CharacterModel sequence sheet (AnimationTree + ragdoll + hit reacts), tiles captured over time.
## godot --path . res://tools/anim_seq.tscn -- model=rimebound_tee_m mode=death|hit|getup|attack|walk|aimstrafe|hatchet out=/tmp/x.png [cols=8] [dt=0.3]
var model := "rimebound_tee_m"
var mode := "death"
var cols := 8
var dt := 0.3
var out := "/tmp/seq.png"
var tiles: Array = []
func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("model="): model = a.substr(6)
		elif a.begins_with("mode="): mode = a.substr(5)
		elif a.begins_with("out="): out = a.substr(4)
		elif a.begins_with("cols="): cols = int(a.substr(5))
		elif a.begins_with("dt="): dt = float(a.substr(3))
	get_window().size = Vector2i(480, 560)
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.1, 0.11, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(0.6, 0.65, 0.75); e.ambient_light_energy = 0.6
	var we := WorldEnvironment.new(); we.environment = e; add_child(we)
	var key := DirectionalLight3D.new(); key.rotation_degrees = Vector3(-35, 30, 0); key.light_energy = 1.6; add_child(key)
	var fl := StaticBody3D.new(); var cs := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = Vector3(60, 1, 60); cs.shape = bx; cs.position.y = -0.5; fl.add_child(cs); add_child(fl)
	var fm := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(60, 60); fm.mesh = pm
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color(0.25, 0.26, 0.3); fm.material_override = mat; add_child(fm)
	var CM = load("res://actors/character_model.gd")
	var m: Node3D = CM.new()
	m.setup({"model": model})
	add_child(m)
	var tgt := Node3D.new(); add_child(tgt); tgt.position = Vector3(2.5, 0, 2.5)
	var cam := Camera3D.new(); add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.5, 5.0), Vector3(0, 0.8, 0), Vector3.UP); cam.fov = 40; cam.current = true
	m.rotation.y = 0.0
	m.pose = "zombie" if model != "elias" else "normal"
	var t0 := Time.get_ticks_msec()
	var n := cols * (1 if mode != "death" else 2)
	var fired := {}
	for i in n:
		var target_t := float(i) * dt
		while (Time.get_ticks_msec() - t0) / 1000.0 < target_t:
			await get_tree().process_frame
		var t := (Time.get_ticks_msec() - t0) / 1000.0
		_script(m, tgt, i, t, fired)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		tiles.append(get_viewport().get_texture().get_image())
	var rows := int(ceil(float(n) / cols))
	var w: int = tiles[0].get_width(); var h: int = tiles[0].get_height()
	var img := Image.create(w * cols, h * rows, false, Image.FORMAT_RGB8)
	for i in tiles.size():
		img.blit_rect(tiles[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	img.save_png(out)
	print("SEQ_DONE ", out)
	get_tree().quit()

func _script(m: Node3D, tgt: Node3D, i: int, t: float, f: Dictionary) -> void:
	match mode:
		"death":
			if i == 1: m.set_look_target(tgt)
			if i == 3 and not f.has("d"):
				f["d"] = 1; m.hit_dir = Vector3(0, 0, -1); m.hit_power = 40; m.pose = "dead"
		"hit":
			var seq := [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]
			if i % 2 == 1 and i / 2 < seq.size():
				m.hit_react(seq[i / 2], 30.0, false)
		"getup":
			if i == 0: m.death_variant = 0; m.pose = "dead"
			if i == 3 and not f.has("g"): f["g"] = 1; m.pose = "zombie" if model != "elias" else "normal"
		"attack":
			if i == 1 or i == 5: m.play("attack")
		"walk":
			m.move_speed = 0.8 if model != "elias" else 1.3
		"aimstrafe":
			m.aim = true
			m.move_speed = 1.5
			m.position += Vector3(0.1 if i > 3 else 0.0, 0, 0) * 0.0
		"hatchet":
			if i % 3 == 1: m.play("knife")
