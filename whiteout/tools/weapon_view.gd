extends Node3D
## Studio render of a weapon glb with its marker frames: godot --path . res://tools/weapon_view.tscn -- id=handgun out=/tmp/w.png [yaw=35] [pitch=15] [dist=0.5] [markers=1]
func _ready() -> void:
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.split("=", true, 1)
		if kv.size() == 2: a[kv[0]] = kv[1]
	var FX = load("res://world/fx.gd")
	var w: Node3D = FX.weapon_mesh(a.get("id", "handgun"))
	w.rotation = Vector3(PI * 0.5, 0, 0)
	add_child(w)
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.1, 0.11, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(0.5, 0.55, 0.65); e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new(); we.environment = e; add_child(we)
	var k := DirectionalLight3D.new(); k.rotation_degrees = Vector3(-40, 35, 0); k.light_energy = 1.8; add_child(k)
	var r := DirectionalLight3D.new(); r.rotation_degrees = Vector3(-20, 210, 0); r.light_energy = 1.0; add_child(r)
	if a.get("markers", "1") == "1":
		for n in ["Grip_R", "Support_L", "Muzzle", "Eject"]:
			var m := w.find_child(n, true, false) as Node3D
			if m == null: print("MISSING MARKER ", n); continue
			for i in 3:
				var b := MeshInstance3D.new(); var bm := BoxMesh.new()
				var sz := Vector3.ONE * 0.003; sz[i] = 0.03
				bm.size = sz; b.mesh = bm
				var mt := StandardMaterial3D.new(); mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mt.albedo_color = [Color.RED, Color.GREEN, Color.BLUE][i]; b.material_override = mt
				b.position[i] = 0.015
				m.add_child(b)
	var cam := Camera3D.new(); add_child(cam)
	var yaw := deg_to_rad(float(a.get("yaw", 35))); var pit := deg_to_rad(float(a.get("pitch", 15))); var d := float(a.get("dist", 0.5))
	var c := Vector3(float(a.get("cx", 0)), float(a.get("cy", 0)), float(a.get("cz", 0)))
	cam.position = c + Vector3(sin(yaw) * cos(pit), sin(pit), cos(yaw) * cos(pit)) * d
	cam.look_at(c); cam.fov = 35; cam.current = true
	for i in 12: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(a.get("out", "/tmp/w.png"))
	print("WEAPON_VIEW_DONE")
	get_tree().quit()
