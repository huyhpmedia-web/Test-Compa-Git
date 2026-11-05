extends Node3D
## Animation contact sheet (frames of clips on a CharacterModel, bypassing the AnimationTree).
## godot --path . res://tools/anim_sheet.tscn -- model=elias anims=aim_idle,shoot cols=8 out=/tmp/s.png [yaw=0.6] [w=1920] [t0=0 t1=len] [hold=handgun]
##   anims entries may be name or name@t0-t1 (seconds).  yaw: 0 front, 1.57 character's left side to camera.
func _ready() -> void:
	var out := "/tmp/sheet.png"
	var model := "elias"
	var anims := PackedStringArray(["idle"])
	var cols := 8
	var yaw := 0.5
	var w := 1920
	var zoom := 1.0
	var hold := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
		elif a.begins_with("model="): model = a.substr(6)
		elif a.begins_with("anims="): anims = a.substr(6).split(",")
		elif a.begins_with("cols="): cols = int(a.substr(5))
		elif a.begins_with("yaw="): yaw = float(a.substr(4))
		elif a.begins_with("w="): w = int(a.substr(2))
		elif a.begins_with("zoom="): zoom = float(a.substr(5))
		elif a.begins_with("hold="): hold = a.substr(5)
	var sp := 1.35
	var rows := anims.size()
	var cell := float(w) / cols
	var h := int(float(w) * (rows * 2.1) / (cols * sp))
	var svp := SubViewport.new()
	svp.size = Vector2i(w, h)
	svp.own_world_3d = true
	svp.msaa_3d = Viewport.MSAA_2X
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(svp)
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.65, 0.75)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new(); we.environment = e; svp.add_child(we)
	var key := DirectionalLight3D.new(); key.rotation_degrees = Vector3(-35, 30, 0); key.light_energy = 1.6; svp.add_child(key)
	var fill := DirectionalLight3D.new(); fill.rotation_degrees = Vector3(-15, -60, 0); fill.light_energy = 0.6; svp.add_child(fill)
	var CM = load("res://actors/character_model.gd")
	var FX = load("res://world/fx.gd")
	for r in rows:
		var spec := anims[r].split("@")
		var an := spec[0]
		var t0 := 0.0
		var t1 := -1.0
		if spec.size() > 1:
			var tt := spec[1].split("-")
			t0 = float(tt[0]); t1 = float(tt[1])
		for c in cols:
			var m: Node3D = CM.new()
			m.setup({"model": model})
			svp.add_child(m)
			if hold != "":
				m.hold(FX.weapon_mesh(hold))
			var len := 1.0
			if m.player and m.player.has_animation(an):
				len = m.player.get_animation(an).length
			else:
				print("MISSING ", an)
			var t1e := len if t1 < 0.0 else t1
			var t := t0 + (t1e - t0) * float(c) / float(max(cols - 1, 1))
			m.debug_pose(an, minf(t, len - 0.001))
			m.position = Vector3((c - (cols - 1) * 0.5) * sp, 0, -r * 0.0)
			m.position.y = -r * 2.1
			m.rotation.y = yaw
	var f := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(60, 60); f.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.2, 0.21, 0.24); f.material_override = fm
	svp.add_child(f)
	var cam := Camera3D.new(); svp.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = cols * sp / zoom
	var cy := 0.9 - (rows - 1) * 1.05
	cam.look_at_from_position(Vector3(0, cy + 0.0, 12), Vector3(0, cy, 0), Vector3.UP)
	cam.current = true
	for i in 12:
		await get_tree().process_frame
	svp.get_texture().get_image().save_png(out)
	print("SHEET_DONE ", out)
	get_tree().quit()
