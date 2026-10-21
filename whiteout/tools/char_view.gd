extends Node3D
## Renders the player character model in a simple studio setup (front + 3/4 views).
func _ready() -> void:
	var out: String = "/tmp/char.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.09, 0.11)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.65)
	e.ambient_light_energy = 0.4
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	var we := WorldEnvironment.new(); we.environment = e; add_child(we)
	var key := DirectionalLight3D.new(); key.rotation_degrees = Vector3(-30, 35, 0); key.light_energy = 1.6; key.shadow_enabled = true; add_child(key)
	var rim := DirectionalLight3D.new(); rim.rotation_degrees = Vector3(-20, 200, 0); rim.light_energy = 1.0; rim.light_color = Color(0.7, 0.8, 1.0); add_child(rim)
	var P = load("res://actors/player.gd")
	var H = load("res://actors/humanoid.gd")
	for i in 3:
		var h: Node3D = H.new()
		h.setup({"height": 1.66, "female": true, "skin": Color(0.72, 0.53, 0.42), "shirt": Color(0.36, 0.33, 0.38), "pants": Color(0.11, 0.13, 0.19), "hair": Color(0.13, 0.08, 0.05), "hair_style": "ponytail", "shoes": Color(0.09, 0.07, 0.06), "long_sleeves": true})
		add_child(h)
		h.position = Vector3((i - 1) * 1.1, 0, 0)
		h.rotation.y = [0.0, 0.7, PI][i]
	var f := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(10, 10); f.mesh = pm; add_child(f)
	var cam := Camera3D.new(); add_child(cam); cam.position = Vector3(0, 1.1, 3.6); cam.look_at(Vector3(0, 0.95, 0)); cam.fov = 45; cam.current = true
	for i in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
