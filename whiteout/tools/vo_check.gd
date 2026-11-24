extends SceneTree
func _init():
	var idx = JSON.parse_string(FileAccess.get_file_as_string("res://audio/vo/index.json"))
	var ok := 0
	for k in idx:
		var t: String = idx[k].text
		if t.md5_text().substr(0, 12) == k and ResourceLoader.exists("res://audio/vo/%s.ogg" % k):
			ok += 1
		else:
			print("MISS ", k, " ", t)
	print("VO_OK ", ok, "/", idx.size())
	quit()
