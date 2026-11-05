extends Node
func _ready():
	var CM = load("res://actors/character_model.gd")
	var root := Node3D.new(); add_child(root)
	var m: Node3D = CM.new()
	m.setup({"model": "rimebound_tee_m"})
	root.add_child(m)
	m.pose = "zombie"
	for i in 30: await get_tree().process_frame
	var sk: Skeleton3D = m.skeleton
	var names := ["pelvis", "head", "foot_l", "hand_l"]
	var base := {}
	for n in names: base[n] = sk.get_bone_global_pose(sk.find_bone(n)).origin
	var os0: AnimationNodeOneShot = m.tree.tree_root.get_node("os_hit_back")
	print("mix_mode=", os0.mix_mode, " filter=", os0.filter_enabled)
	for hn in ["hit_back", "hit_front", "hit_left"]:
		var a: Animation = m.player.get_animation(hn)
		print(hn, " len=", a.length, " tracks=", a.get_track_count())
		for i in 3:
			print("  trk ", a.track_get_path(i), " type ", a.track_get_type(i), " k0=", a.track_get_key_value(i, 0), " k3=", a.track_get_key_value(i, min(3, a.track_get_key_count(i) - 1)))
		m.tree.set("parameters/amt_%s/blend_amount" % hn, 0.0)
		m.tree.set("parameters/os_%s/request" % hn, 1)
		for i in 6: await get_tree().process_frame
		for n in names: print("   ", hn, n, (sk.get_bone_global_pose(sk.find_bone(n)).origin - base[n]).length())
		for i in 40: await get_tree().process_frame
	get_tree().quit()
