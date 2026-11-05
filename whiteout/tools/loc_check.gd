extends SceneTree
## godot --headless --path . --script res://tools/loc_check.gd
## Loads locale/vi.po through the engine, switches to vi and verifies that every msgid in
## locale/strings.pot resolves to a Vietnamese string (identical strings allowed for names).
## Also checks printf-style placeholders survive the round trip.

func _init() -> void:
	var tr_res: Translation = load("res://locale/vi.po")
	print("LOC engine messages in vi.po: ", tr_res.get_message_count())
	TranslationServer.set_locale("vi")
	var ids := _pot_ids()
	var missing := 0
	var same := 0
	var badfmt := 0
	for id in ids:
		var t := TranslationServer.translate(id)
		if t == id:
			same += 1
		if t == "":
			missing += 1
		var a := _ph(id)
		var b := _ph(t)
		if a != b:
			badfmt += 1
			print("LOC BAD PLACEHOLDERS: ", id.substr(0, 60))
	TranslationServer.set_locale("en")
	var en_ok := 0
	for id in ids:
		if TranslationServer.translate(id) == id:
			en_ok += 1
	print("LOC_MSGIDS=%d identical_in_vi=%d empty=%d bad_placeholders=%d english_roundtrip_ok=%d" % [ids.size(), same, missing, badfmt, en_ok])
	print("LOC_DONE ", "FAIL" if (missing > 0 or badfmt > 0 or en_ok != ids.size()) else "OK")
	quit(1 if (missing > 0 or badfmt > 0) else 0)

func _ph(s: String) -> Array:
	var rx := RegEx.new()
	rx.compile("%[-+0-9.]*[sdf]|%%")
	var out := []
	for m in rx.search_all(s):
		out.append(m.get_string())
	out.sort()
	return out

func _pot_ids() -> Array:
	var f := FileAccess.open("res://locale/strings.pot", FileAccess.READ)
	var ids := []
	var cur := ""
	var in_id := false
	while not f.eof_reached():
		var ln := f.get_line()
		if ln.begins_with("msgid "):
			if in_id and cur != "":
				ids.append(cur)
			cur = _unq(ln.substr(6))
			in_id = true
		elif ln.begins_with("msgstr"):
			if in_id and cur != "":
				ids.append(cur)
			in_id = false
			cur = ""
		elif in_id and ln.begins_with("\""):
			cur += _unq(ln)
	return ids

func _unq(s: String) -> String:
	s = s.strip_edges()
	s = s.substr(1, s.length() - 2)
	return s.replace("\\n", "\n").replace("\\t", "\t").replace("\\\"", "\"").replace("\\\\", "\\")
