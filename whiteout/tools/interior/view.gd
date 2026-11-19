extends Node3D
## Dev harness: lines up interior_sf models with a floor + grid for scale checks.
## godot --path . res://tools/interior/view.tscn -- out=/tmp/x.png names=a,b,c
func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var names: PackedStringArray = args.get("names", "").split(",", false)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.25, 0.27, 0.3)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.75)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0)
	sun.light_energy = 1.2
	add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 6)
	fl.mesh = pm
	add_child(fl)
	var x := 0.0
	var Env = load("res://world/env_assets.gd")
	var xs := []
	for n in names:
		var r: Node3D = Env.spawn(self, "interior_sf/" + n, Vector3(x, 0, 0), float(args.get("yaw", "0")), {"snow": 0.0, "collide": "none"})
		if r == null:
			print("MISSING ", n)
			continue
		var bb: AABB = r.get_meta("env_aabb")
		x += bb.size.x * 0.5 + 0.4
		r.position.x = x
		x += bb.size.x * 0.5 + 0.4
		xs.append(x)
		print(n, " size ", bb.size)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(x * 0.5, 1.5, float(args.get("dist", "0")) if args.has("dist") else 6.0 + x * 0.35)
	cam.look_at(Vector3(x * 0.5, 0.9, 0))
	cam.fov = 55
	for i in 8:
		await get_tree().process_frame
	if args.has("out"):
		get_viewport().get_texture().get_image().save_png(args.out)
	get_tree().quit()
