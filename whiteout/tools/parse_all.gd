extends Node
## Loads every script in the project so parse/compile errors are printed (autoloads available).
func _ready() -> void:
	var bad := 0
	for f in _walk("res://"):
		var s = load(f)
		if s == null or (s is GDScript and not s.can_instantiate() and not f.ends_with("items.gd")):
			print("PARSE_FAIL ", f)
			bad += 1
	print("PARSE_DONE bad=", bad)
	get_tree().quit()

func _walk(dir: String) -> Array:
	var out := []
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with("."):
			continue
		out += _walk(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	return out
