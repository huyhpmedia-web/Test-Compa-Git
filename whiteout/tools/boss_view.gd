extends Node3D
## Studio render of an enemy glb or game model -> PNG (boss/creature modelling tool).
## godot --path . res://tools/boss_view.tscn -- glb=choir out=/tmp/x.png [cam=x,y,z look=x,y,z fov=40 yaw=0 frames=30]
##   model=choir|hauler|mother1|mother2|hound  uses the game's model class instead of the raw glb
##   set=prop:value,prop:value  (numbers) sets properties on the model; call=method:arg  calls a method
##   file=/abs/path.glb  loads any glb; scl=2 pos=x,y,z scale / place the instance
##   yaws=0,90,180,270  turntable: one png per yaw (out_0.png ...)
##   anim=name[@t]  plays an animation of the raw glb, bg=r,g,b  floor=0|1  fx=hum|none (extra ambient)
func _ready() -> void:
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var out: String = a.get("out", "/tmp/boss.png")
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	var bg: PackedStringArray = String(a.get("bg", "0.04,0.05,0.08")).split(",")
	e.background_color = Color(float(bg[0]), float(bg[1]), float(bg[2]))
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.55, 0.75)
	e.ambient_light_energy = float(a.get("amb", 0.18))
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = int(a.get("ssao", 0)) == 1
	e.glow_enabled = int(a.get("glow", 0)) == 1
	e.glow_intensity = 0.6
	e.glow_bloom = 0.1
	var we := WorldEnvironment.new()
	we.environment = e
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, float(a.get("keyyaw", 35)), 0)
	key.light_energy = float(a.get("key", 0.4))
	key.light_color = Color(0.75, 0.85, 1.0)
	key.shadow_enabled = true
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 200, 0)
	rim.light_energy = 0.5
	rim.light_color = Color(0.7, 0.8, 1.0)
	add_child(rim)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 1.5, 4)
	fill.light_energy = float(a.get("fill", 0.15))
	fill.omni_range = 14
	fill.light_color = Color(0.7, 0.85, 1.0)
	add_child(fill)
	var inst: Node3D = null
	if a.has("model"):
		var path: String = {"choir": "res://actors/models/choir_model.gd", "hauler": "res://actors/models/hauler_model.gd",
			"mother1": "res://actors/models/mother_model.gd", "mother2": "res://actors/models/mother_model.gd",
			"hound": "res://actors/models/hound_model.gd"}[a.model]
		inst = load(path).new()
		add_child(inst)
		if a.model == "mother2":
			inst.set_phase(2)
	else:
		var gl := GLTFDocument.new()
		var st := GLTFState.new()
		var gpath := ProjectSettings.globalize_path("res://assets/enemies/%s.glb" % a.get("glb", "_test"))
		if a.has("file"):
			gpath = String(a.file)
		var err := gl.append_from_file(gpath, st)
		if err != OK:
			push_error("cannot load " + gpath)
			get_tree().quit(1)
			return
		inst = gl.generate_scene(st) as Node3D
		load("res://actors/models/enemy_glb.gd").fix_materials(inst)
		add_child(inst)
		if a.has("anim"):
			var pp := String(a.anim).split("@")
			var ap := _find_ap(inst)
			if ap and ap.has_animation(pp[0]):
				ap.play(pp[0])
				ap.seek(float(pp[1]) if pp.size() > 1 else 0.0, true)
				ap.pause()
	inst.rotation.y = float(a.get("yaw", 0.0))
	for kv in String(a.get("set", "")).split(",", false):
		var q := kv.split(":")
		var v: Variant = float(q[1])
		if q[1] == "true": v = true
		elif q[1] == "false": v = false
		elif q[1] == "str": v = q[2]
		inst.set(q[0], v)
	if a.has("scl"):
		inst.scale = Vector3.ONE * float(a.scl)
	if a.has("pos"):
		var pq := String(a.pos).split(",")
		inst.position = Vector3(float(pq[0]), float(pq[1]), float(pq[2]))
	if int(a.get("floor", 1)) == 1:
		var f := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(60, 60)
		f.mesh = pm
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(0.2, 0.22, 0.26)
		fm.roughness = 0.9
		f.material_override = fm
		add_child(f)
	var cam := Camera3D.new()
	add_child(cam)
	var cp := String(a.get("cam", "0,2,10")).split(",")
	var lp := String(a.get("look", "0,2,0")).split(",")
	cam.position = Vector3(float(cp[0]), float(cp[1]), float(cp[2]))
	cam.fov = float(a.get("fov", 40))
	cam.current = true
	cam.look_at(Vector3(float(lp[0]), float(lp[1]), float(lp[2])))
	if int(a.get("spot", 1)) == 1:   # flashlight held by the viewer
		var sp := SpotLight3D.new()
		sp.light_energy = float(a.get("spotE", 3.0))
		sp.spot_range = 40.0
		sp.spot_angle = 22.0
		sp.spot_attenuation = 0.6
		sp.light_color = Color(1.0, 0.95, 0.85)
		sp.shadow_enabled = true
		cam.add_child(sp)
	var frames := int(a.get("frames", 8))
	for i in frames:
		await get_tree().process_frame
		if a.has("call") and i == 3:
			var cq := String(a.call).split(":")
			if cq.size() > 1:
				inst.call(cq[0], cq[1])
			else:
				inst.call(cq[0])
	if a.has("yaws"):   # turntable: renders one image per yaw (degrees) -> out with _<i> suffix
		var ys := String(a.yaws).split(",")
		var base_y := inst.rotation.y
		for yi in ys.size():
			inst.rotation.y = base_y + deg_to_rad(float(ys[yi]))
			for k in 4:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out.replace(".png", "_%d.png" % yi))
		print("BOSS_VIEW_DONE ", out)
		get_tree().quit()
		return
	get_viewport().get_texture().get_image().save_png(out)
	print("BOSS_VIEW_DONE ", out)
	get_tree().quit()

func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_ap(c)
		if r:
			return r
	return null
