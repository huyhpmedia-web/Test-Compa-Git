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
	v.position = Vector2(90, 120)
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
	UI._button("Options", func(): UI.open_options(), v)
	UI._button("Credits", func(): UI.show_note("Credits", UI.CREDITS_TEXT), v)
	UI._button("Quit", func(): get_tree().quit(), v)
	nb.grab_focus()
	var foot := UI._label("A fan-made survival horror homage. Built with Godot.", 13, UI.C_DIM)
	foot.position = Vector2(90, 684)
	add_child(foot)
	_box = v
	_build_language_switch()

var _box: VBoxContainer
var _lang_buttons := {}

## Always-visible language switch (top right). Persisted by UI.set_language().
func _build_language_switch() -> void:
	var hb := HBoxContainer.new()
	hb.anchor_left = 1.0
	hb.anchor_right = 1.0
	hb.offset_left = -330
	hb.offset_right = -30
	hb.offset_top = 22
	hb.offset_bottom = 62
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 8)
	add_child(hb)
	for l in UI.LANGS:
		var code: String = l[0]
		var b := Button.new()
		b.text = l[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.custom_minimum_size = Vector2(120, 0)
		b.pressed.connect(func():
			Sfx.play("ui_select")
			UI.set_language(code))
		hb.add_child(b)
		_lang_buttons[code] = b
	UI.language_changed.connect(_sync_language_buttons)
	_sync_language_buttons()

func _sync_language_buttons() -> void:
	for code in _lang_buttons:
		(_lang_buttons[code] as Button).set_pressed_no_signal(code == UI.language)

func _exit_tree() -> void:
	if UI.language_changed.is_connected(_sync_language_buttons):
		UI.language_changed.disconnect(_sync_language_buttons)

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
