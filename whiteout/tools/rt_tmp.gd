extends Node
func _ready():
	var CM = load("res://actors/character_model.gd")
	var root := Node3D.new(); add_child(root)
	var floor_ := StaticBody3D.new(); var cs := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = Vector3(50, 1, 50); cs.shape = bx; cs.position.y = -0.5; floor_.add_child(cs); root.add_child(floor_)
	var tgt := Node3D.new(); root.add_child(tgt); tgt.position = Vector3(3, 0, 2)
	for mname in ["elias", "rimebound_tee_m", "husk"]:
		var m: Node3D = CM.new()
		m.setup({"model": mname})
		root.add_child(m)
		print(mname, " player=", m.player != null, " clips=", m.player.get_animation_list().size() if m.player else -1, " zv=", m.walk_variant, " tree=", m.tree != null)
		if m.tree == null: continue
		m.pose = "zombie" if mname != "elias" else "normal"
		for i in 20: await get_tree().process_frame
		m.move_speed = 1.0
		for i in 10: await get_tree().process_frame
		m.aim = true
		for i in 10: await get_tree().process_frame
		for a in ["shoot", "reload", "attack", "knife", "knife", "stagger", "grab", "hurt", "getup", "interact", "flashlight"]:
			m.play(a)
			for i in 3: await get_tree().process_frame
		m.hit_react(Vector3(0, 0, -1), 20.0)
		m.hit_react(Vector3(1, 0, 0), 20.0)
		m.hit_react(Vector3(0, 0, 1), 20.0, false)
		m.set_look_target(tgt)
		for i in 10: await get_tree().process_frame
		m.hit_dir = Vector3(0, 0, -1); m.hit_power = 30
		m.pose = "dead"
		for i in 60: await get_tree().process_frame
		var ps: Vector3 = m.skeleton.get_bone_global_pose(m.skeleton.find_bone("pelvis")).origin
		print("  dead; ragdoll sim=", m._rag_sim != null, " pelvis y=", ps.y)
		m.pose = "zombie" if mname != "elias" else "normal"
		for i in 10: await get_tree().process_frame
		print("  revived ok")
	get_tree().quit()
