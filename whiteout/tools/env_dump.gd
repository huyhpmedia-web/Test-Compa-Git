extends SceneTree
## Prints native AABB of every assets/env glb: godot --headless --path . --script res://tools/env_dump.gd
const Env = preload("res://world/env_assets.gd")
func _initialize() -> void:
	var dirs := ["trees","vehicles","street","camp","interior","facade","industrial","mine","church","props"]
	for d in dirs:
		var da := DirAccess.open("res://assets/env/" + d)
		if da == null: continue
		var files := Array(da.get_files()).filter(func(f): return f.ends_with(".glb"))
		files.sort()
		for f in files:
			var rel: String = d + "/" + f.get_basename()
			var ps := Env.scene(rel)
			if ps == null:
				print("MISSING ", rel); continue
			var inst := ps.instantiate() as Node3D
			var a := Env.local_aabb(inst)
			print("AABB %-28s size=(%.2f, %.2f, %.2f) min=(%.2f, %.2f, %.2f)" % [rel, a.size.x, a.size.y, a.size.z, a.position.x, a.position.y, a.position.z])
			inst.free()
	quit()
