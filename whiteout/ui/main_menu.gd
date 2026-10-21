extends Control
## Title screen.

func _ready() -> void:
	theme = UI.theme_res
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UI.show_hud(false)
	UI.fade_in(1.5)
	Sfx.music("music_title", -6.0)
	Sfx.ambience("amb_wind", -14.0)
	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if ResourceLoader.exists("res://ui/title_bg.png"):
		bg.texture = load("res://ui/title_bg.png")
	bg.modulate = Color(0.75, 0.75, 0.8)
	add_child(bg)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.35)
	add_child(shade)
	var v := VBoxContainer.new()
	v.position = Vector2(90, 180)
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var t := UI._label("KETTLE FALLS", 64, Color(0.92, 0.92, 0.9))
	v.add_child(t)
	var t2 := UI._label("W H I T E O U T", 26, Color(0.7, 0.12, 0.1))
	v.add_child(t2)
	v.add_child(UI._label("December 21, 2026  ·  −40°", 16, UI.C_DIM))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	v.add_child(spacer)
	var nb := UI._button("New Game", _new_game_menu, v)
	nb.custom_minimum_size = Vector2(300, 0)
	var has_save := false
	for i in 3:
		if not Game.save_info(i).is_empty():
			has_save = true
	var lb := UI._button("Load Game", func(): UI.open_load(), v)
	lb.disabled = not has_save
	UI._button("Controls", func(): UI.show_note("Controls", UI.CONTROLS_TEXT), v)
	UI._button("Credits", func(): UI.show_note("Credits", UI.CREDITS_TEXT), v)
	UI._button("Quit", func(): get_tree().quit(), v)
	nb.grab_focus()
	var foot := UI._label("A fan-made survival horror homage. Built with Godot.", 13, UI.C_DIM)
	foot.position = Vector2(90, 660)
	add_child(foot)
	_box = v

var _box: VBoxContainer

func _new_game_menu() -> void:
	for c in _box.get_children():
		if c is Button:
			c.queue_free()
	_box.add_child(UI._label("Select difficulty", 18, UI.C_ACCENT))
	var b := UI._button("Assisted — more ammo forgiveness, weaker dead", func(): _start(0), _box)
	UI._button("Standard — the intended experience", func(): _start(1), _box)
	UI._button("Hardcore — every bullet counts", func(): _start(2), _box)
	b.grab_focus()

func _start(diff: int) -> void:
	Game.difficulty = diff
	Game.new_game()
