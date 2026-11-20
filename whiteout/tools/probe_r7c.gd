extends Node
func _ready() -> void:
	name = "World"
	Game.level_id = "l5_mine"
	Game.spawn_id = "start"
	Game.add_item("knife")
	await get_tree().process_frame
	Game._load_level()
	for i in 20:
		await get_tree().process_frame
	var c := Vector3(3.5, 1.5, 1.0)
	for n in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.mesh == null: continue
		var a := m.global_transform * m.mesh.get_aabb()
		if a.grow(0.5).has_point(c) and a.size.length() > 1.5:
			print("PROBE ", m.get_path(), " ", a.size, " ", a.position, " mat=", m.get_active_material(0))
	for d in get_tree().root.find_children("*", "Decal", true, false):
		var dd := d as Decal
		if dd.global_position.distance_to(c) < 6.0:
			print("PROBE decal ", dd.global_position, " size=", dd.size, " basis_y=", dd.global_transform.basis.y)
	for n in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.mesh == null: continue
		var a := m.global_transform * m.mesh.get_aabb()
		if a.grow(2.5).has_point(c) and a.size.x > 2.0 and a.size.y>1.5:
			print("PROBE2 ", m.get_path(), " ", a.size, " ", a.position)
	get_tree().quit()
