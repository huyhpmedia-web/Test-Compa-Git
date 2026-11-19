extends Node
## UI screenshot harness (Vietnamese/English evidence + clipping checks).
## godot --path . res://tools/ui_shot.tscn -- scene=menu|hud|inventory|files|dialogue|note|ending|options|itemget|pause|save|itembox
##     [lang=vi] [level=l1_substation spawn=start frames=60] out=/tmp/x.png
## Without level= the UI is drawn over a dark backdrop (no 3D, fast).

func _ready() -> void:
	name = "World"
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	await get_tree().process_frame
	if args.has("lang"):
		UI.set_language(args.lang, false)
	Game.inventory = []
	Game.inv_slots = 8
	Game.item_box = [{"id": "spray", "count": 1}, {"id": "ammo_shell", "count": 12}]
	for id in ["knife", "handgun", "shotgun", "flare", "gel", "adrenaline", "ammo_9mm", "hot_stick", "fuse_60a"]:
		Game.add_item(id, 1)
	Game.add_item("ammo_9mm", 20)
	Game.set_ammo_loaded("handgun", 9)
	Game.equipped = "handgun"
	Game.hp = 55
	var scene := str(args.get("scene", "hud"))
	if args.has("level"):
		Game.level_id = args.level
		Game.spawn_id = args.get("spawn", "start")
		Game._load_level()
	elif scene != "sign" and scene != "itemsheet":
		var bg := ColorRect.new()
		bg.color = Color(0.09, 0.11, 0.14)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(bg)
		UI.show_hud(scene in ["hud", "dialogue"])
	for i in int(args.get("frames", "20")):
		await get_tree().process_frame
	match scene:
		"menu":
			var m: Control = load("res://ui/main_menu.tscn").instantiate()
			add_child(m)
		"hud":
			Game.set_objective("Reach the school. Gran's shelter. Follow Highway 53 north.")
			UI.toast(tr("Picked up %s%s.") % [Game.item_def("flare").name, " x3"])
			UI.set_prompt("Open control house")
		"inventory":
			Game.set_objective("Re-close feeder KF-2. Find the hot stick and a 60A fuse, then follow the switching order.")
			UI.open_inventory()
			if args.has("sel"):
				UI._select_slot(int(args.sel))
		"files":
			Game.set_flag("files", ["f1"])
			Game.set_flag("file:f1", {"title": _msg("Operator's switching order"), "body": _msg("[b]SWITCHING ORDER - RESTORE KF-2[/b]")})
			UI._build_inventory("files")
		"dialogue":
			UI.dialogue([["JUNE (radio)", "Dad! Dad, the school just lit up. The gym, the hall, everything. Gran's shelter is there."], ["ELIAS", "Hold on, June. I'm coming. Stay inside, stay warm."]])
		"note":
			UI.show_note(_msg("Letter: T. Kade"), _msg("[b]Ruth,[/b]\n\nI started this three times"))
		"ending":
			UI.show_ending(str(args.get("ending", "thaw")))
		"options":
			UI.open_options()
		"itemget":
			UI.show_item_get(str(args.get("item", "rosary")))
		"itemsheet":
			_item_sheet(args)
		"pause":
			UI.open_pause()
		"save":
			UI.open_save()
		"itembox":
			UI.open_item_box()
		"sign":
			var cam := Camera3D.new()
			cam.position = Vector3(0, 0, 3.2)
			add_child(cam)
			cam.make_current()
			var env := WorldEnvironment.new()
			env.environment = Environment.new()
			env.environment.background_mode = Environment.BG_COLOR
			env.environment.background_color = Color(0.05, 0.06, 0.08)
			env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.environment.ambient_light_color = Color.WHITE
			add_child(env)
			var y := 1.0
			for t in ["DANGER  HIGH VOLTAGE", "ST. BRENDAN'S", "BASEMENT\nBOILER · CUSTODIAL", "NO TRESPASSING — CORVANE SYSTEMS", "SHELTER ENTRANCE:\nWEST DOOR (CUSTODIAL)\nKNOCK. ASK FOR RUTH."]:
				var l := Label3D.new()
				l.text = t
				l.font_size = 48
				l.pixel_size = 0.004
				l.position = Vector3(0, y, 0)
				add_child(l)
				y -= 0.6
		"title":
			UI.title_card("THE LONGEST NIGHT", "Kettle Falls, Minnesota  -  Dec 21, 2026  22:14  -  -40 degrees")
	for i in int(args.get("wait", "40")):
		await get_tree().process_frame
	if args.has("out"):
		get_viewport().get_texture().get_image().save_png(args.out)
		print("SHOT_SAVED ", args.out)
	get_tree().quit()

## Full English msgid starting with `prefix` (read from locale/strings.pot).
func _msg(prefix: String) -> String:
	var f := FileAccess.open("res://locale/strings.pot", FileAccess.READ)
	var cur := ""
	var in_id := false
	while not f.eof_reached():
		var ln := f.get_line()
		if ln.begins_with("msgid "):
			cur = _unq(ln.substr(6))
			in_id = true
		elif ln.begins_with("msgstr"):
			if in_id and cur.begins_with(prefix):
				return cur
			in_id = false
		elif in_id and ln.begins_with("\""):
			cur += _unq(ln)
	return prefix

func _unq(s: String) -> String:
	s = s.strip_edges()
	s = s.substr(1, s.length() - 2)
	return s.replace("\\n", "\n").replace("\\\"", "\"").replace("\\\\", "\\")

## Contact sheet of every item model, laid out exactly like the inspector stage (one 3D render).
##   scene=itemsheet [ids=a,b,c] [cols=7]
func _item_sheet(args: Dictionary) -> void:
	var IV = preload("res://ui/item_view.gd")
	var ids: Array = []
	if args.has("ids"):
		ids = str(args.ids).split(",")
	else:
		for k in Items.DEFS.keys():
			if Items.DEFS[k].kind != "weapon":
				ids.append(k)
	var cols := int(args.get("cols", "7"))
	var rows := int(ceil(float(ids.size()) / cols))
	var cell := 2.1
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.055, 0.065)
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.38, 0.5)
	sm.sky_horizon_color = Color(0.85, 0.78, 0.68)
	sm.ground_horizon_color = Color(0.5, 0.45, 0.4)
	sm.ground_bottom_color = Color(0.04, 0.04, 0.05)
	sm.sky_energy_multiplier = 0.7
	env.environment.sky = Sky.new()
	env.environment.sky.sky_material = sm
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.environment.ambient_light_energy = 0.55
	env.environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -42, 0)
	key.light_energy = 1.7
	key.light_color = Color(1.0, 0.94, 0.85)
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-12, 150, 0)
	rim.light_energy = 1.1
	rim.light_color = Color(0.6, 0.75, 1.0)
	add_child(rim)
	var yaw := float(args.get("yaw", "0.6"))
	for i in ids.size():
		var id: String = ids[i]
		var holder: Node3D = IV.fitted(id, 1.0)
		holder.position = Vector3((i % cols - (cols - 1) * 0.5) * cell, -(i / cols - (rows - 1) * 0.5) * cell * 1.0, 0)
		holder.rotation = Vector3(0.25, yaw, 0)
		add_child(holder)
		var l := Label3D.new()
		l.text = id
		l.font_size = 40
		l.pixel_size = 0.0035
		l.position = holder.position + Vector3(0, -0.95, 0.3)
		l.modulate = Color(0.85, 0.88, 0.95)
		add_child(l)
	var cam := Camera3D.new()
	cam.fov = 30
	var w := cols * cell
	var h := rows * cell
	var dist := maxf(w / (2.0 * tan(deg_to_rad(15.0)) * (16.0 / 9.0)), h / (2.0 * tan(deg_to_rad(15.0)))) * 1.04
	cam.position = Vector3(0, 0, dist)
	add_child(cam)
	cam.make_current()
