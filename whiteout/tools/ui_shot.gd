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
	else:
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
			UI.toast("Picked up Road Flare x3.")
			UI.set_prompt("Open control house")
		"inventory":
			Game.set_objective("Re-close feeder KF-2. Find the hot stick and a 60A fuse, then follow the switching order.")
			UI.open_inventory()
		"files":
			Game.set_flag("files", ["f1"])
			Game.set_flag("file:f1", {"title": "Operator's switching order and log", "body": "[b]SWITCHING ORDER - RESTORE KF-2[/b]\n(copy from the manual, for my own sake)\n\n1. Verify BKR-KF2 OPEN.\n2. CLOSE DS-2A (bus side)."})
			UI._build_inventory("files")
		"dialogue":
			UI.dialogue([["JUNE (radio)", "Dad! Dad, the school just lit up. The gym, the hall, everything. Gran's shelter is there."], ["ELIAS", "Hold on, June. I'm coming. Stay inside, stay warm."]])
		"note":
			UI.show_note("Letter: T. Kade to Ruth, March 2011", "[b]Ruth,[/b]\n\nI started this three times at the kitchen table and you kept coming in to top up my coffee, so I'm finishing it here in the lamp room where nobody watches me think.\n\nThe top level has been making noises I don't like. I told Gil. Gil told the office. The office told Gil to stop telling them. You know how it goes. I'll be fine. Twenty-two years down here and the mountain and I have an understanding.\n\nHere's what I never manage at supper. I'm proud of you. I'm proud of how you sit with people when it's bad. And I'm proud of Eli, even when he looks at me like I'm the thing he's trying to get away from. He's got my hands and your head. He'll leave this town. Let him. Just don't let him leave angry.")
		"ending":
			UI.show_ending(str(args.get("ending", "thaw")))
		"options":
			UI.open_options()
		"itemget":
			UI.show_item_get("rosary")
		"pause":
			UI.open_pause()
		"save":
			UI.open_save()
		"itembox":
			UI.open_item_box()
		"title":
			UI.title_card("THE LONGEST NIGHT", "Kettle Falls, Minnesota  -  Dec 21, 2026  22:14  -  -40 degrees")
	for i in int(args.get("wait", "40")):
		await get_tree().process_frame
	if args.has("out"):
		get_viewport().get_texture().get_image().save_png(args.out)
		print("SHOT_SAVED ", args.out)
	get_tree().quit()
