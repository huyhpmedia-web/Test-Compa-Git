extends SceneTree
func _init() -> void:
	var ps: PackedScene = load("res://assets/characters/elias.glb")
	var r = ps.instantiate()
	root.add_child(r)
	var sk: Skeleton3D = r.find_children("*", "Skeleton3D", true, false)[0]
	print("scale ", r.scale, " skel xf ", sk.global_transform)
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		var g := sk.get_bone_global_rest(i)
		print(i, " ", n, " parent=", sk.get_bone_parent(i), " pos=", g.origin, " Y=", g.basis.y.snapped(Vector3(0.01,0.01,0.01)), " Z=", g.basis.z.snapped(Vector3(0.01,0.01,0.01)), " X=", g.basis.x.snapped(Vector3(0.01,0.01,0.01)))
	var ap: AnimationPlayer = r.find_children("*", "AnimationPlayer", true, false)[0]
	print(ap.get_animation_list())
	quit()
