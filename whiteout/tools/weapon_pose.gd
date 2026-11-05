extends Node3D
## Elias holding a weapon: godot --path . res://tools/weapon_pose.tscn -- hold=handgun aim=1 pitch=0 cam=0.9,1.5,-1.2 look=0,1.4,0.5 fov=40 frames=40 out=/tmp/p.png [speed=0] [kick=1]
func _ready() -> void:
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.split("=", true, 1)
		if kv.size() == 2: a[kv[0]] = kv[1]
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.08, 0.09, 0.11)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(0.55, 0.6, 0.7); e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new(); we.environment = e; add_child(we)
	var k := DirectionalLight3D.new(); k.rotation_degrees = Vector3(-35, 150, 0); k.light_energy = 1.6; add_child(k)
	var r := DirectionalLight3D.new(); r.rotation_degrees = Vector3(-20, 30, 0); r.light_energy = 0.8; add_child(r)
	var f := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(20, 20); f.mesh = pm; add_child(f)
	var CM = load("res://actors/character_model.gd")
	var h: Node3D = CM.new()
	h.setup({"model": "elias"})
	add_child(h)
	var FX = load("res://world/fx.gd")
	if a.get("hold", "") != "":
		h.hold(FX.weapon_mesh(a.hold))
	h.aim = a.get("aim", "0") == "1"
	h.aim_pitch = float(a.get("pitch", 0))
	h.move_speed = float(a.get("speed", 0))
	var c := Camera3D.new(); add_child(c)
	var cp: PackedStringArray = String(a.get("cam", "0.9,1.5,-1.2")).split(",")
	var lp: PackedStringArray = String(a.get("look", "0,1.4,0.5")).split(",")
	c.position = Vector3(float(cp[0]), float(cp[1]), float(cp[2]))
	c.look_at(Vector3(float(lp[0]), float(lp[1]), float(lp[2])))
	c.fov = float(a.get("fov", 40)); c.current = true
	var frames := int(a.get("frames", 40))
	var kick_at := int(a.get("kick", -1))
	var shots: PackedStringArray = String(a.get("shots", "")).split(",", false)   # frame numbers to save extra images: out_<n>.png
	for i in frames:
		if i == kick_at and h.weapon_ik: h.weapon_ik.kick(1.0)
		await get_tree().process_frame
		if str(i) in shots:
			get_viewport().get_texture().get_image().save_png(a.out.replace(".png", "_%d.png" % i))
	get_viewport().get_texture().get_image().save_png(a.get("out", "/tmp/p.png"))
	print("POSE_DONE")
	get_tree().quit()
