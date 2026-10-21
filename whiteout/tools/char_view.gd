extends Node3D
## Studio render of a character .glb (front, 3/4, back) -> PNG.
## godot --path . res://tools/char_view.tscn -- model=elias out=/tmp/elias.png [view=trio|face|front|three_q|back] [anim=idle] [t=0.5] [pose=...]
func _ready() -> void:
	var out := "/tmp/char.png"
	var model := "elias"
	var view := "trio"
	var anim := ""
	var t := 0.0
	var bg := Color(0.16, 0.17, 0.2)
	var poses: PackedStringArray = []
	var yaw_arg := 0.5
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
		elif a.begins_with("model="): model = a.substr(6)
		elif a.begins_with("view="): view = a.substr(5)
		elif a.begins_with("anim="): anim = a.substr(5)
		elif a.begins_with("t="): t = float(a.substr(2))
		elif a.begins_with("poses="): poses = a.substr(6).split(",")
		elif a.begins_with("yaw="): yaw_arg = float(a.substr(4))
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = bg
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.7)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	var we := WorldEnvironment.new(); we.environment = e; add_child(we)
	var key := DirectionalLight3D.new(); key.rotation_degrees = Vector3(-35, 30, 0); key.light_energy = 1.7; key.shadow_enabled = true; add_child(key)
	var fill := DirectionalLight3D.new(); fill.rotation_degrees = Vector3(-15, -60, 0); fill.light_energy = 0.55; fill.light_color = Color(0.8, 0.85, 1.0); add_child(fill)
	var rim := DirectionalLight3D.new(); rim.rotation_degrees = Vector3(-20, 200, 0); rim.light_energy = 1.0; rim.light_color = Color(0.7, 0.8, 1.0); add_child(rim)
	var path := "res://assets/characters/%s.glb" % model
	var ps: PackedScene = load(path)
	if ps == null:
		push_error("cannot load " + path)
		get_tree().quit(1)
		return
	var yaws: Array = {"trio": [0.0, 0.7, PI], "front": [0.0], "three_q": [0.7], "back": [PI], "face": [0.0], "wide": [0.0], "poses": [0.0]}[view]
	if poses.size() > 0:
		yaws = []
		for p in poses: yaws.append(yaw_arg)
		view = "poses"
	var n: int = yaws.size()
	var inst_list := []
	for i in n:
		var h: Node3D = ps.instantiate()
		add_child(h)
		h.position = Vector3((i - (n - 1) * 0.5) * (1.25 if poses.size() > 0 else 1.1), 0, 0)
		h.rotation.y = yaws[i]
		inst_list.append(h)
		var an := anim
		var tt := t
		if poses.size() > 0:
			var pp := poses[i].split("@")
			an = pp[0]; tt = float(pp[1]) if pp.size() > 1 else 0.0
		if an != "":
			var ap: AnimationPlayer = _find_ap(h)
			if ap and ap.has_animation(an):
				ap.play(an)
				ap.seek(tt, true)
				ap.pause()
			elif ap:
				print("NO ANIM ", an, " have: ", ap.get_animation_list())
	var f := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(12, 12); f.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.13, 0.14, 0.16); fm.roughness = 0.9; f.material_override = fm
	add_child(f)
	var cam := Camera3D.new(); add_child(cam)
	if view == "face":
		cam.position = Vector3(0, 1.66, 0.75); cam.look_at(Vector3(0, 1.66, 0)); cam.fov = 30
	elif view == "poses":
		var span := 1.25 * n
		cam.position = Vector3(0, 1.0 + span * 0.04, span * 0.95 + 1.5); cam.look_at(Vector3(0, 0.85, 0)); cam.fov = 40
	elif view == "wide":
		cam.position = Vector3(0, 0.45, 4.2); cam.look_at(Vector3(0, 0.3, 0)); cam.fov = 40
	elif view == "trio":
		cam.position = Vector3(0, 1.15, 4.2); cam.look_at(Vector3(0, 0.95, 0)); cam.fov = 42
	else:
		cam.position = Vector3(0, 1.05, 3.3); cam.look_at(Vector3(0, 0.9, 0)); cam.fov = 42
	cam.current = true
	for i in 25:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	print("CHAR_VIEW_DONE ", out)
	get_tree().quit()

func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer: return n
	for c in n.get_children():
		var r := _find_ap(c)
		if r: return r
	return null
