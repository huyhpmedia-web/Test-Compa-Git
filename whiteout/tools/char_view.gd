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
	var cm_args := ""
	var lineup_arg := ""
	var lineup_rows := 2
	var lineup_pose := "zombie"
	var lineup_w := 2400
	var lineup_h := 1200
	var cam_pos_arg := ""
	var look_arg := ""
	var fov_arg := 0.0
	var spacing := 1.5
	var lit := "dark"   # dark = in-game moody rig + flashlight spot; studio = old bright rig
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
		elif a.begins_with("model="): model = a.substr(6)
		elif a.begins_with("view="): view = a.substr(5)
		elif a.begins_with("anim="): anim = a.substr(5)
		elif a.begins_with("t="): t = float(a.substr(2))
		elif a.begins_with("poses="): poses = a.substr(6).split(",")
		elif a.begins_with("yaw="): yaw_arg = float(a.substr(4))
		elif a.begins_with("cm="): cm_args = a.substr(3)
		elif a.begins_with("lineup="): lineup_arg = a.substr(7)
		elif a.begins_with("rows="): lineup_rows = int(a.substr(5))
		elif a.begins_with("lpose="): lineup_pose = a.substr(6)
		elif a.begins_with("w="): lineup_w = int(a.substr(2))
		elif a.begins_with("h="): lineup_h = int(a.substr(2))
		elif a.begins_with("campos="): cam_pos_arg = a.substr(7)
		elif a.begins_with("look="): look_arg = a.substr(5)
		elif a.begins_with("fov="): fov_arg = float(a.substr(4))
		elif a.begins_with("spacing="): spacing = float(a.substr(8))
		elif a.begins_with("lit="): lit = a.substr(4)
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
	if lineup_arg != "":
		await _lineup(lineup_arg.split("|"), out, lineup_rows, lineup_pose, lineup_w, lineup_h, t, {"campos": cam_pos_arg, "look": look_arg, "fov": fov_arg, "spacing": spacing, "lit": lit, "yaw": yaw_arg})
		return
	if cm_args != "":
		await _cm_mode(cm_args, model, out, yaw_arg)
		return
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
		cam.position = Vector3(0, 0.95, 4.6); cam.look_at(Vector3(0, 0.85, 0)); cam.fov = 40
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


## CharacterModel test: cm="speed=2.3,aim=1,pitch=0.2,pose=normal,play=shoot@20,hold=handgun,frames=60,zoom=1"
func _cm_mode(args: String, model: String, out: String, yaw: float) -> void:
	var kv := {}
	for p in args.split(","):
		var q := p.split("=")
		kv[q[0]] = q[1] if q.size() > 1 else "1"
	var CM = load("res://actors/character_model.gd")
	var h: Node3D = CM.new()
	h.setup({"model": model, "zombie": kv.get("zombie", "0") == "1"})
	add_child(h)
	h.rotation.y = yaw
	h.move_speed = float(kv.get("speed", 0))
	h.aim = kv.get("aim", "0") == "1"
	h.aim_pitch = float(kv.get("pitch", 0))
	h.pose = kv.get("pose", "normal")
	if kv.has("hold"):
		var FX = load("res://world/fx.gd")
		h.hold(FX.weapon_mesh(kv.hold))
	var frames := int(kv.get("frames", 60))
	var play_at := -1
	var play_name := ""
	if kv.has("play"):
		var pp: PackedStringArray = kv.play.split("@")
		play_name = pp[0]; play_at = int(pp[1]) if pp.size() > 1 else 5
	var cam := Camera3D.new(); add_child(cam)
	var z := float(kv.get("zoom", 1))
	if z > 1.5:
		cam.position = Vector3(0, 1.3, 2.2); cam.look_at(Vector3(0, 1.25, 0)); cam.fov = 40
	else:
		cam.position = Vector3(0, 1.1, 3.6); cam.look_at(Vector3(0, 0.9, 0)); cam.fov = 42
	cam.current = true
	var f := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(12, 12); f.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.13, 0.14, 0.16); f.material_override = fm
	add_child(f)
	for i in frames:
		if i == play_at: h.play(play_name)
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	print("CHAR_VIEW_DONE ", out, " playing=", h.is_playing())
	get_tree().quit()


## Lineup render: godot ... -- lineup=a|b|c|d,... out=x.png [rows=2] [lpose=zombie] [w=2400] [h=1200]
##   [campos=x,y,z look=x,y,z fov=40 spacing=1.5 lit=dark|studio yaw=0.35]
## lit=dark: dim blue ambient + cold moon key + a flashlight-like SpotLight3D from the camera (as in-game).
const SPECIAL_SCRIPT := {"husk": "res://actors/enemies/husk.gd", "siren": "res://actors/enemies/siren.gd", "burster": "res://actors/enemies/burster.gd",
	"hanger": "res://actors/enemies/hanger.gd", "foreman": "res://actors/enemies/foreman.gd"}
var _keep := []
func _v3(s: String, d: Vector3) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2])) if p.size() == 3 else d

func _lineup(models: PackedStringArray, out: String, rows: int, pose: String, w: int, h: int, anim_t: float, o := {}) -> void:
	var svp := SubViewport.new()
	svp.size = Vector2i(w, h)
	svp.own_world_3d = true
	svp.msaa_3d = Viewport.MSAA_2X
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(svp)
	var dark: bool = o.get("lit", "dark") == "dark"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.015, 0.02, 0.03) if dark else Color(0.07, 0.08, 0.1)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.25, 0.32, 0.45) if dark else Color(0.45, 0.52, 0.65)
	e.ambient_light_energy = 0.2 if dark else 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = false
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_hdr_threshold = 1.0
	var we := WorldEnvironment.new(); we.environment = e; svp.add_child(we)
	var key := DirectionalLight3D.new(); key.rotation_degrees = Vector3(-35, 25, 0); key.light_energy = 0.25 if dark else 1.6; key.light_color = Color(0.6, 0.72, 1.0) if dark else Color.WHITE; key.shadow_enabled = true; svp.add_child(key)
	var rim := DirectionalLight3D.new(); rim.rotation_degrees = Vector3(-20, 200, 0); rim.light_energy = 0.5 if dark else 0.8; rim.light_color = Color(0.5, 0.7, 1.0); svp.add_child(rim)
	var CM = load("res://actors/character_model.gd")
	var RL = load("res://actors/rime_look.gd")
	var per_row := int(ceil(float(models.size()) / rows))
	var sp: float = o.get("spacing", 1.5)
	var yaw0: float = o.get("yaw", 0.35)
	for i in models.size():
		var m: Node3D
		if SPECIAL_SCRIPT.has(models[i]) and pose == "zombie" and o.get("real", true):
			# the real enemy script builds the model (stretch, crystals, sacs, lamp ...) exactly as in game
			var en = load(SPECIAL_SCRIPT[models[i]]).new()
			_keep.append(en)
			m = en._make_model()
			svp.add_child(m)
			m.move_speed = 0.0
		else:
			m = CM.new()
			m.setup({"model": models[i]})
			svp.add_child(m)
			m.pose = pose
			if pose == "zombie":
				m.move_speed = 0.0
				RL.decorate(m, 1.0, 100 + i, {})
		var r := i / per_row
		var c := i % per_row
		m.position = Vector3((c - (per_row - 1) * 0.5) * sp + r * 0.4, 0, -r * 2.4)
		m.rotation.y = yaw0 if (i % 2 == 0) else -yaw0 * 0.85
	var f := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(40, 40); f.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.12, 0.13, 0.15); fm.roughness = 0.85; f.material_override = fm
	svp.add_child(f)
	var cam := Camera3D.new(); svp.add_child(cam)
	var span := per_row * sp
	cam.position = _v3(o.get("campos", ""), Vector3(0, 1.35, span * 0.62 + 1.6))
	var lk := _v3(o.get("look", ""), Vector3(0, 1.0 - rows * 0.1, -(rows - 1) * 0.8))
	cam.look_at_from_position(cam.position, lk, Vector3.UP)
	cam.fov = o.get("fov", 0.0) if o.get("fov", 0.0) > 0 else 42.0
	cam.current = true
	if dark:
		var sl := SpotLight3D.new()
		svp.add_child(sl)
		sl.position = cam.position + Vector3(0.35, -0.15, 0)
		sl.look_at_from_position(sl.position, lk + Vector3(0, 0.1, 0), Vector3.UP)
		sl.light_energy = 4.5
		sl.spot_range = 14.0
		sl.spot_angle = 30.0
		sl.spot_attenuation = 0.6
		sl.light_color = Color(1.0, 0.95, 0.85)
		sl.shadow_enabled = true
	for i in 60:
		await get_tree().process_frame
	svp.get_texture().get_image().save_png(out)
	print("CHAR_VIEW_DONE ", out)
	get_tree().quit()
