extends Node
## Dev tool: load a level headless and print how many decals / lights / gibs it holds.
##   godot --headless --path . res://tools/gore_stats.tscn -- level=l2_school

func _ready() -> void:
	name = "World"
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	Game.level_id = args.get("level", "test_yard")
	Game.spawn_id = args.get("spawn", "start")
	await get_tree().process_frame
	Game._load_level()
	for i in 6:
		await get_tree().process_frame
	var root := get_tree().current_scene
	var decals := root.find_children("*", "Decal", true, false).size()
	var omni := root.find_children("*", "OmniLight3D", true, false).size()
	var spot := root.find_children("*", "SpotLight3D", true, false).size()
	var parts := root.find_children("*", "CPUParticles3D", true, false).size()
	print("GORE_STATS ", Game.level_id, " decals=", decals, " omni=", omni, " spot=", spot, " cpu_particles=", parts, " clustered_total=", decals + omni + spot)
	get_tree().quit()
