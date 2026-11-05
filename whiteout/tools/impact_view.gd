extends Node3D
## Close-ups of the per-surface bullet impacts: godot --path . res://tools/impact_view.tscn -- out=/tmp/i.png
func _ready() -> void:
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.split("=", true, 1)
		if kv.size() == 2: a[kv[0]] = kv[1]
	var SF = load("res://world/shot_fx.gd")
	var FX = load("res://world/fx.gd")
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.03, 0.04, 0.06)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(0.4, 0.45, 0.6); e.ambient_light_energy = 0.9
	var we := WorldEnvironment.new(); we.environment = e; add_child(we)
	var k := DirectionalLight3D.new(); k.rotation_degrees = Vector3(-25, 20, 0); k.light_energy = 2.2; add_child(k)
	var spots := [["snow", Color(0.85, 0.88, 0.95)], ["concrete", Color(0.45, 0.43, 0.4)], ["metal", Color(0.35, 0.37, 0.4)], ["wood", Color(0.35, 0.22, 0.12)], ["flesh", Color(0.6, 0.45, 0.4)]]
	for i in spots.size():
		var m := MeshInstance3D.new(); var b := BoxMesh.new(); b.size = Vector3(0.9, 1.0, 0.1); m.mesh = b
		var mat := StandardMaterial3D.new(); mat.albedo_color = spots[i][1]; mat.roughness = 0.9 if i != 2 else 0.35; mat.metallic = 0.8 if i == 2 else 0.0
		m.material_override = mat
		m.position = Vector3((i - 2) * 1.0, 0.5, 0)
		add_child(m)
	var cam := Camera3D.new(); add_child(cam)
	cam.position = Vector3(0, 0.55, 3.0); cam.look_at(Vector3(0, 0.5, 0)); cam.fov = 58; cam.current = true
	for f in 3: await get_tree().process_frame
	for i in spots.size():
		var p := Vector3((i - 2) * 1.0 + randf_range(-0.12, 0.12), 0.55 + randf_range(-0.1, 0.1), 0.05)
		if spots[i][0] == "flesh":
			FX.blood_burst(self, p, Vector3.BACK)
		else:
			SF.impact(self, p, Vector3.BACK, spots[i][0])
	for f in 2: await get_tree().process_frame
	await get_tree().create_timer(0.02).timeout
	get_viewport().get_texture().get_image().save_png(String(a.get("out", "/tmp/i.png")).replace(".png", "_a.png"))
	await get_tree().create_timer(0.35).timeout
	get_viewport().get_texture().get_image().save_png(String(a.get("out", "/tmp/i.png")).replace(".png", "_b.png"))
	print("IMPACT_DONE")
	get_tree().quit()
