extends CanvasLayer
## All 2D UI, built in code. Autoloaded as `UI`.

signal dialogue_done
signal modal_closed

const Items = preload("res://core/items.gd")

const C_TEXT := Color(0.86, 0.87, 0.84)
const C_DIM := Color(0.55, 0.57, 0.56)
const C_ACCENT := Color(0.75, 0.82, 0.9)
const C_PANEL := Color(0.03, 0.035, 0.04, 0.92)

var root: Control
var fade: ColorRect
var hud: Control
var hp_label: Label
var hp_bar: ColorRect
var hp_ecg: Control
var ammo_label: Label
var weapon_label: Label
var objective_label: Label
var prompt_label: Label
var toast_box: VBoxContainer
var reticle: Control
var dmg_flash: ColorRect
var vignette: ColorRect
var dlg_panel: PanelContainer
var dlg_name: Label
var dlg_text: RichTextLabel
var modal: Control = null
var _modal_stack := []
var _dlg_active := false
var _dlg_advance := false
var _reticle_on := false
var _reticle_focus := 0.0
var _ecg_t := 0.0
var theme_res: Theme

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme_res = _make_theme()
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme_res
	add_child(root)
	_build_hud()
	_build_dialogue()
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)
	Game.health_changed.connect(func(_a, _b): _refresh_hud())
	Game.inventory_changed.connect(_refresh_hud)
	Game.objective_changed.connect(func(t): objective_label.text = t)
	show_hud(false)

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["DejaVu Sans", "Noto Sans", "Arial", "Helvetica"])
	if ResourceLoader.exists("res://ui/font.ttf"):
		t.default_font = load("res://ui/font.ttf")
	else:
		t.default_font = font
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL
	sb.border_color = Color(0.35, 0.38, 0.4, 0.8)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(14)
	t.set_stylebox("panel", "PanelContainer", sb)
	t.set_stylebox("panel", "Panel", sb)
	var bn := StyleBoxFlat.new()
	bn.bg_color = Color(0.08, 0.09, 0.1, 0.9)
	bn.border_color = Color(0.3, 0.32, 0.34)
	bn.set_border_width_all(1)
	bn.set_content_margin_all(8)
	var bh := bn.duplicate()
	bh.bg_color = Color(0.18, 0.22, 0.26, 0.95)
	bh.border_color = C_ACCENT
	var bp := bh.duplicate()
	bp.bg_color = Color(0.25, 0.3, 0.35)
	for st in [["normal", bn], ["hover", bh], ["focus", bh], ["pressed", bp], ["disabled", bn]]:
		t.set_stylebox(st[0], "Button", st[1])
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.35, 0.35, 0.35))
	t.set_color("font_color", "Label", C_TEXT)
	t.set_color("default_color", "RichTextLabel", C_TEXT)
	return t

func _label(text: String, size := 18, color := C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l

# ================================================================= HUD
func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)

	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float strength = 0.0;
uniform vec4 tint : source_color = vec4(0.4, 0.0, 0.0, 1.0);
void fragment(){
	vec2 d = UV - vec2(0.5);
	float v = smoothstep(0.25, 0.75, length(d * vec2(1.3, 1.0)));
	float base = v * 0.55;
	COLOR = mix(vec4(0.0, 0.0, 0.0, base), vec4(tint.rgb, v), strength);
}"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	vignette.material = sm
	hud.add_child(vignette)

	dmg_flash = ColorRect.new()
	dmg_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	dmg_flash.color = Color(0.6, 0.0, 0.0, 0.0)
	dmg_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(dmg_flash)

	# bottom-right status block
	var status := VBoxContainer.new()
	status.anchor_left = 1.0; status.anchor_right = 1.0; status.anchor_top = 1.0; status.anchor_bottom = 1.0
	status.offset_left = -300; status.offset_right = -24; status.offset_top = -120; status.offset_bottom = -20
	status.alignment = BoxContainer.ALIGNMENT_END
	hud.add_child(status)
	weapon_label = _label("", 16, C_DIM)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.add_child(weapon_label)
	ammo_label = _label("", 34)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.add_child(ammo_label)
	hp_ecg = Control.new()
	hp_ecg.custom_minimum_size = Vector2(276, 34)
	hp_ecg.draw.connect(_draw_ecg)
	status.add_child(hp_ecg)
	hp_label = _label("FINE", 15)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.add_child(hp_label)
	hp_bar = ColorRect.new()  # kept for compatibility (unused visual)

	objective_label = _label("", 15, C_DIM)
	objective_label.position = Vector2(24, 20)
	objective_label.size = Vector2(700, 30)
	hud.add_child(objective_label)

	prompt_label = _label("", 18, Color(0.95, 0.95, 0.9))
	prompt_label.anchor_left = 0.5; prompt_label.anchor_right = 0.5; prompt_label.anchor_top = 1.0; prompt_label.anchor_bottom = 1.0
	prompt_label.offset_left = -300; prompt_label.offset_right = 300; prompt_label.offset_top = -190; prompt_label.offset_bottom = -160
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(prompt_label)

	toast_box = VBoxContainer.new()
	toast_box.position = Vector2(24, 60)
	toast_box.size = Vector2(620, 300)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_box)

	reticle = Control.new()
	reticle.anchor_left = 0.5; reticle.anchor_right = 0.5; reticle.anchor_top = 0.5; reticle.anchor_bottom = 0.5
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle.draw.connect(_draw_reticle)
	hud.add_child(reticle)

func show_hud(on: bool) -> void:
	hud.visible = on
	_refresh_hud()

func _refresh_hud() -> void:
	if hp_label == null:
		return
	var st := Game.health_state()
	hp_label.text = st
	hp_label.add_theme_color_override("font_color", {"FINE": Color(0.45, 0.9, 0.5), "CAUTION": Color(0.95, 0.75, 0.25), "DANGER": Color(0.95, 0.25, 0.2)}[st])
	var eq := Game.equipped
	if eq != "" and eq != "knife":
		var d := Game.item_def(eq)
		weapon_label.text = d.name
		ammo_label.text = "%d  /  %d" % [Game.ammo_loaded(eq), Game.count_item(d.get("ammo", ""))]
	else:
		weapon_label.text = Game.item_def(eq).name if eq != "" else ""
		ammo_label.text = ""
	objective_label.text = Game.objective
	if vignette.material:
		var s := 0.0
		if st == "CAUTION":
			s = 0.25
		elif st == "DANGER":
			s = 0.6
		(vignette.material as ShaderMaterial).set_shader_parameter("strength", s)

func _process(delta: float) -> void:
	_ecg_t += delta
	if hud.visible:
		hp_ecg.queue_redraw()
	dmg_flash.color.a = max(0.0, dmg_flash.color.a - delta * 1.5)
	if _dlg_active and (Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("fire")):
		_dlg_advance = true

func _draw_ecg() -> void:
	var st := Game.health_state()
	var col: Color = {"FINE": Color(0.45, 0.9, 0.5), "CAUTION": Color(0.95, 0.75, 0.25), "DANGER": Color(0.95, 0.25, 0.2)}[st]
	var w := hp_ecg.size.x
	var h := hp_ecg.size.y
	var rate: float = {"FINE": 1.0, "CAUTION": 1.5, "DANGER": 2.3}[st]
	var pts := PackedVector2Array()
	for i in 120:
		var x := w * i / 119.0
		var ph := fmod(_ecg_t * rate - i / 60.0, 1.0)
		if ph < 0:
			ph += 1.0
		var y := 0.0
		if ph < 0.04:
			y = -ph * 10.0
		elif ph < 0.08:
			y = (ph - 0.06) * 30.0
		elif ph < 0.12:
			y = -(0.12 - ph) * 8.0
		pts.append(Vector2(x, h * 0.5 + y * h * 0.9))
	for i in range(1, pts.size()):
		var a := 1.0 - float(i) / pts.size()
		hp_ecg.draw_line(pts[i - 1], pts[i], Color(col.r, col.g, col.b, 0.25 + a * 0.75), 2.0, true)

func set_reticle(on: bool, focus: float) -> void:
	_reticle_on = on
	_reticle_focus = focus
	reticle.queue_redraw()

func _draw_reticle() -> void:
	if not _reticle_on:
		return
	var r: float = lerp(26.0, 5.0, _reticle_focus)
	var c := Color(1, 1, 1, 0.85) if _reticle_focus < 0.95 else Color(1.0, 0.85, 0.5, 1.0)
	reticle.draw_arc(Vector2.ZERO, r, 0, TAU, 40, c, 1.5, true)
	reticle.draw_circle(Vector2.ZERO, 1.6, c)

func set_prompt(text: String) -> void:
	if prompt_label.text != ("[E]  " + text if text != "" else ""):
		prompt_label.text = "[E]  " + text if text != "" else ""

func toast(text: String, dur := 3.0) -> void:
	var l := _label(text, 17)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(600, 0)
	toast_box.add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(dur)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)
	while toast_box.get_child_count() > 5:
		toast_box.get_child(0).free()

func flash_damage() -> void:
	dmg_flash.color.a = 0.45

func fade_out(t := 0.6) -> void:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, t)

func fade_in(t := 0.8) -> void:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, t)

## Big title card used when entering an area: UI.title_card("THE PRECINCT", "Dec 24 2026 — 23:58")
func title_card(title: String, sub := "") -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.anchor_top = 0.38; box.anchor_bottom = 0.38
	box.offset_left = -500; box.offset_right = 500
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := _label(title, 44, Color(0.92, 0.92, 0.9))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	if sub != "":
		var s := _label(sub, 18, C_DIM)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(s)
	box.modulate.a = 0.0
	root.add_child(box)
	var tw := box.create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 1.2)
	tw.tween_interval(2.5)
	tw.tween_property(box, "modulate:a", 0.0, 1.5)
	tw.tween_callback(box.queue_free)

# ================================================================= dialogue
func _build_dialogue() -> void:
	dlg_panel = PanelContainer.new()
	dlg_panel.anchor_left = 0.5; dlg_panel.anchor_right = 0.5; dlg_panel.anchor_top = 1.0; dlg_panel.anchor_bottom = 1.0
	dlg_panel.offset_left = -480; dlg_panel.offset_right = 480; dlg_panel.offset_top = -150; dlg_panel.offset_bottom = -24
	var v := VBoxContainer.new()
	dlg_panel.add_child(v)
	dlg_name = _label("", 16, C_ACCENT)
	v.add_child(dlg_name)
	dlg_text = RichTextLabel.new()
	dlg_text.bbcode_enabled = true
	dlg_text.fit_content = true
	dlg_text.custom_minimum_size = Vector2(900, 60)
	dlg_text.add_theme_font_size_override("normal_font_size", 19)
	v.add_child(dlg_text)
	dlg_panel.visible = false
	root.add_child(dlg_panel)

## lines: [["SPEAKER", "text"], ...] or plain strings. Awaitable.
func dialogue(lines: Array) -> void:
	_dlg_active = true
	dlg_panel.visible = true
	for ln in lines:
		var who := ""
		var txt := ""
		if ln is Array:
			who = ln[0]
			txt = ln[1]
		else:
			txt = str(ln)
		dlg_name.text = who
		dlg_name.visible = who != ""
		dlg_text.text = txt
		dlg_text.visible_ratio = 0.0
		_dlg_advance = false
		var n: int = max(1, txt.length())
		var t := 0.0
		while dlg_text.visible_ratio < 1.0:
			await get_tree().process_frame
			t += get_process_delta_time()
			dlg_text.visible_ratio = min(1.0, t * 55.0 / n)
			if _dlg_advance:
				_dlg_advance = false
				dlg_text.visible_ratio = 1.0
		var wait := 0.0
		while not _dlg_advance:
			await get_tree().process_frame
			wait += get_process_delta_time()
			if wait > 2.5 + n * 0.06:
				break
		_dlg_advance = false
	dlg_panel.visible = false
	_dlg_active = false
	dialogue_done.emit()

# ================================================================= modal plumbing
func is_blocking() -> bool:
	return modal != null or _dlg_active

func _open_modal(c: Control, pause := true) -> void:
	if modal != null:
		modal.queue_free()
	modal = c
	root.add_child(c)
	if pause:
		get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close_modal() -> void:
	if modal != null:
		modal.queue_free()
		modal = null
	get_tree().paused = false
	if Game.current_level != null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	modal_closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if modal == null:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_back") or (event.is_action_pressed("inventory") and modal.name in ["Inventory", "ItemBox"]):
		if modal.name not in ["GameOver", "Ending"]:
			get_viewport().set_input_as_handled()
			close_modal()

func _panel(w: float, h: float) -> PanelContainer:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.offset_left = -w * 0.5; p.offset_right = w * 0.5; p.offset_top = -h * 0.5; p.offset_bottom = h * 0.5
	bg.add_child(p)
	p.set_meta("bg", bg)
	return p

func _button(text: String, cb: Callable, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func():
		Sfx.play("ui_select")
		cb.call())
	b.mouse_entered.connect(func(): b.grab_focus())
	b.focus_entered.connect(func(): Sfx.play("ui_move", -8.0))
	parent.add_child(b)
	return b

# ================================================================= note reader / item get
func show_note(title: String, body: String) -> void:
	var p := _panel(760, 560)
	var bg: Control = p.get_meta("bg")
	bg.name = "Note"
	var v := VBoxContainer.new()
	p.add_child(v)
	var t := _label(title, 24, Color(0.95, 0.92, 0.85))
	v.add_child(t)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(720, 430)
	v.add_child(sc)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.text = body
	rt.fit_content = true
	rt.custom_minimum_size = Vector2(700, 0)
	rt.add_theme_font_size_override("normal_font_size", 17)
	sc.add_child(rt)
	var b := _button("Close", close_modal, v)
	_open_modal(bg)
	b.grab_focus()

func show_item_get(id: String) -> void:
	var d := Items.get_def(id)
	var p := _panel(560, 220)
	var bg: Control = p.get_meta("bg")
	bg.name = "ItemGet"
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(_label("OBTAINED", 14, C_DIM))
	v.add_child(_label(d.name, 26, Color(0.95, 0.9, 0.7)))
	var desc := _label(d.desc, 16)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(520, 0)
	v.add_child(desc)
	var b := _button("OK", close_modal, v)
	_open_modal(bg)
	b.grab_focus()

# ================================================================= inventory
var _inv_sel := -1
var _combine_from := ""

func open_inventory() -> void:
	_inv_sel = -1
	_combine_from = ""
	_build_inventory()

func _build_inventory(tab := "items") -> void:
	var p := _panel(980, 600)
	var bg: Control = p.get_meta("bg")
	bg.name = "Inventory"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var st := Game.health_state()
	top.add_child(_label("ELIAS KADE   ·   ", 18, C_DIM))
	top.add_child(_label(st, 18, {"FINE": Color(0.45, 0.9, 0.5), "CAUTION": Color(0.95, 0.75, 0.25), "DANGER": Color(0.95, 0.25, 0.2)}[st]))
	top.add_child(_label("   ·   " + Game.format_time(Game.play_time), 18, C_DIM))
	var tabs := HBoxContainer.new()
	v.add_child(tabs)
	_button("ITEMS", func(): _rebuild_inv("items"), tabs)
	_button("FILES", func(): _rebuild_inv("files"), tabs)
	if Game.objective != "":
		tabs.add_child(_label("     Objective: " + Game.objective, 15, C_DIM))
	if tab == "files":
		_files_view(v)
	else:
		_items_view(v)
	_open_modal(bg)

func _rebuild_inv(tab: String) -> void:
	if modal:
		modal.queue_free()
		modal = null
	_build_inventory(tab)

func _items_view(v: VBoxContainer) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	v.add_child(hb)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	hb.add_child(grid)
	var first: Button = null
	for i in Game.inv_slots:
		var b := Button.new()
		b.custom_minimum_size = Vector2(120, 92)
		b.clip_text = true
		if i < Game.inventory.size():
			var s = Game.inventory[i]
			var d := Items.get_def(s.id)
			var txt: String = d.name
			if d.kind == "weapon" and s.id != "knife":
				txt += "\n[%d]" % Game.ammo_loaded(s.id)
			elif d.get("stack", 1) > 1:
				txt += "\nx%d" % s.count
			if s.id == Game.equipped:
				txt = "E  " + txt
			b.text = txt
			b.add_theme_color_override("font_color", d.color.lightened(0.3))
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var idx := i
			b.pressed.connect(func(): _select_slot(idx))
			b.mouse_entered.connect(func(): b.grab_focus())
			if first == null:
				first = b
		else:
			b.text = "—"
			b.disabled = true
		grid.add_child(b)
	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(440, 0)
	hb.add_child(info)
	if _combine_from != "":
		info.add_child(_label("Combine %s with...?" % Items.get_def(_combine_from).name, 18, C_ACCENT))
		_button("Cancel", func():
			_combine_from = ""
			_rebuild_inv("items"), info)
	elif _inv_sel >= 0 and _inv_sel < Game.inventory.size():
		var s = Game.inventory[_inv_sel]
		var d := Items.get_def(s.id)
		info.add_child(_label(d.name, 24, Color(0.95, 0.92, 0.85)))
		var desc := _label(d.desc, 16)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(420, 0)
		info.add_child(desc)
		var acts := VBoxContainer.new()
		info.add_child(acts)
		match d.kind:
			"weapon":
				_button("Equip" if s.id != Game.equipped else "Equipped", func():
					Game.use_item(s.id)
					_rebuild_inv("items"), acts)
			"heal", "upgrade":
				_button("Use", func():
					Game.use_item(s.id)
					_inv_sel = -1
					_rebuild_inv("items"), acts)
			"key":
				_button("Use", func():
					close_modal()
					Game.use_item(s.id), acts)
		if d.kind in ["heal", "resource", "ammo"]:
			_button("Combine", func():
				_combine_from = s.id
				_rebuild_inv("items"), acts)
		if d.kind in ["ammo", "resource", "heal"]:
			_button("Discard", func():
				Game.remove_item(s.id, s.count)
				_inv_sel = -1
				_rebuild_inv("items"), acts)
	else:
		info.add_child(_label("Select an item.", 16, C_DIM))
		info.add_child(_label("Inventory: %d / %d slots" % [Game.slots_used(), Game.inv_slots], 15, C_DIM))
	info.add_child(_label("\n[Tab/Esc] Close", 14, C_DIM))
	if first:
		first.call_deferred("grab_focus")

func _select_slot(i: int) -> void:
	Sfx.play("ui_select")
	if _combine_from != "":
		var other: String = Game.inventory[i].id
		var a := _combine_from
		_combine_from = ""
		if Game.inventory[i].id == a and Game.inventory[i].count < 2 and Game.count_item(a) < 2:
			toast("Need two of these.")
		else:
			Game.combine(a, other)
		_inv_sel = -1
	else:
		_inv_sel = i
	_rebuild_inv("items")

func _files_view(v: VBoxContainer) -> void:
	var files: Array = Game.get_flag("files", [])
	var hb := HBoxContainer.new()
	v.add_child(hb)
	var list := VBoxContainer.new()
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(320, 440)
	sc.add_child(list)
	hb.add_child(sc)
	var view := RichTextLabel.new()
	view.bbcode_enabled = true
	view.custom_minimum_size = Vector2(600, 440)
	view.add_theme_font_size_override("normal_font_size", 16)
	hb.add_child(view)
	if files.is_empty():
		list.add_child(_label("No files collected.", 16, C_DIM))
	for f in files:
		var fd = Game.get_flag("file:" + f, {})
		if fd is Dictionary and fd.has("title"):
			_button(fd.title, func(): view.text = "[b]%s[/b]\n\n%s" % [fd.title, fd.body], list)

# ================================================================= item box
func open_item_box() -> void:
	var p := _panel(900, 560)
	var bg: Control = p.get_meta("bg")
	bg.name = "ItemBox"
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(_label("SUPPLY CRATE — click to move items", 18, C_ACCENT))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 30)
	v.add_child(hb)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(400, 420)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(400, 420)
	hb.add_child(left)
	hb.add_child(right)
	left.add_child(_label("Inventory (%d/%d)" % [Game.slots_used(), Game.inv_slots], 16, C_DIM))
	right.add_child(_label("Box", 16, C_DIM))
	for i in Game.inventory.size():
		var s = Game.inventory[i]
		var idx := i
		_button("%s%s" % [Items.get_def(s.id).name, (" x%d" % s.count) if s.count > 1 else ""], func():
			var it = Game.inventory[idx]
			Game.inventory.remove_at(idx)
			if it.id == Game.equipped:
				Game.equipped = ""
			_box_add(it.id, it.count)
			Game.inventory_changed.emit()
			_reopen_box(), left)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(400, 380)
	var rl := VBoxContainer.new()
	sc.add_child(rl)
	right.add_child(sc)
	for i in Game.item_box.size():
		var s = Game.item_box[i]
		var idx := i
		_button("%s%s" % [Items.get_def(s.id).name, (" x%d" % s.count) if s.count > 1 else ""], func():
			var it = Game.item_box[idx]
			var left_over := Game.add_item(it.id, it.count)
			if left_over == it.count:
				toast("Inventory full.")
				return
			if left_over > 0:
				it.count = left_over
			else:
				Game.item_box.remove_at(idx)
			if Game.equipped == "" and Items.get_def(it.id).kind == "weapon":
				Game.equipped = it.id
			_reopen_box(), rl)
	_button("Close", close_modal, v)
	_open_modal(bg)

func _box_add(id: String, count: int) -> void:
	for s in Game.item_box:
		if s.id == id and Items.get_def(id).get("stack", 1) > 1:
			s.count += count
			return
	Game.item_box.append({"id": id, "count": count})

func _reopen_box() -> void:
	if modal:
		modal.queue_free()
		modal = null
	open_item_box()

# ================================================================= save / load / pause
func open_save() -> void:
	_slots_menu(true)

func open_load() -> void:
	_slots_menu(false)

func _slots_menu(saving: bool) -> void:
	var p := _panel(640, 420)
	var bg: Control = p.get_meta("bg")
	bg.name = "Save"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(_label("RECORD PROGRESS" if saving else "LOAD", 22, C_ACCENT))
	var first: Button = null
	for slot in 3:
		var info := Game.save_info(slot)
		var txt := "Slot %d — empty" % (slot + 1)
		if not info.is_empty():
			txt = "Slot %d — %s · %s · %s" % [slot + 1, str(info.get("level_id", "")).replace("_", " ").to_upper(), Game.format_time(float(info.get("play_time", 0))), info.get("stamp", "")]
		var s := slot
		var b := _button(txt, func():
			if saving:
				Game.save_game(s)
				close_modal()
			else:
				if not Game.save_info(s).is_empty():
					close_modal()
					Game.load_game(s), v)
		if not saving and info.is_empty():
			b.disabled = true
		if first == null and not b.disabled:
			first = b
	_button("Cancel", close_modal, v)
	_open_modal(bg)
	if first:
		first.grab_focus()

func open_pause() -> void:
	var p := _panel(420, 380)
	var bg: Control = p.get_meta("bg")
	bg.name = "Pause"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(_label("PAUSED", 26, C_ACCENT))
	var b := _button("Resume", close_modal, v)
	_button("Load Game", func():
		close_modal()
		open_load(), v)
	_button("Controls", func():
		close_modal()
		show_note("Controls", CONTROLS_TEXT), v)
	_button("Quit to Title", func():
		close_modal()
		quit_to_title(), v)
	_open_modal(bg)
	b.grab_focus()

const CONTROLS_TEXT := """[b]WASD[/b] move   ·   [b]Shift[/b] run   ·   [b]Mouse[/b] look
[b]Right mouse[/b] aim   ·   [b]Left mouse[/b] fire (while aiming)
[b]R[/b] reload   ·   [b]F[/b] knife   ·   [b]Q[/b] quick turn
[b]E[/b] interact / advance dialogue   ·   [b]Tab[/b] inventory
[b]H[/b] quick heal   ·   [b]1-4[/b] weapons   ·   [b]L[/b] flashlight
[b]Esc[/b] pause / close menus

Hold aim without moving to tighten the reticle — a focused shot does far more damage. Headshots deal double damage and stop the dead from getting back up.
Zombies that fall may not stay down. Ammunition is scarce: avoid fights you don't need."""

func quit_to_title() -> void:
	get_tree().paused = false
	Game.current_level = null
	Game.player = null
	show_hud(false)
	Sfx.music("")
	Sfx.ambience("")
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	for n in get_tree().root.get_children():
		if n.name == "World":
			n.queue_free()

func show_game_over() -> void:
	await get_tree().create_timer(2.0).timeout
	var bg := ColorRect.new()
	bg.name = "GameOver"
	bg.color = Color(0.05, 0, 0, 0.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.offset_left = -220; v.offset_right = 220; v.offset_top = -120; v.offset_bottom = 120
	v.add_theme_constant_override("separation", 12)
	bg.add_child(v)
	var t := _label("YOU ARE DEAD", 46, Color(0.75, 0.08, 0.06))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var b := _button("Continue (retry area)", func():
		close_modal()
		_retry(), v)
	_button("Load Game", func():
		close_modal()
		open_load(), v)
	_button("Quit to Title", func():
		close_modal()
		quit_to_title(), v)
	_open_modal(bg)
	var tw := bg.create_tween()
	tw.tween_property(bg, "color:a", 0.85, 1.5)
	b.grab_focus()

var checkpoint := {}

## Levels call UI.checkpoint_now() on entry; retry restores that snapshot.
func checkpoint_now() -> void:
	checkpoint = {"hp": max(Game.hp, 60), "inventory": Game.inventory.duplicate(true), "flags": Game.flags.duplicate(true),
		"level": Game.level_id, "spawn": Game.spawn_id, "equipped": Game.equipped, "inv_slots": Game.inv_slots,
		"item_box": Game.item_box.duplicate(true)}

func _retry() -> void:
	if checkpoint.is_empty():
		quit_to_title()
		return
	Game.hp = checkpoint.hp
	Game.inventory = checkpoint.inventory.duplicate(true)
	Game.flags = checkpoint.flags.duplicate(true)
	Game.equipped = checkpoint.equipped
	Game.inv_slots = checkpoint.inv_slots
	Game.item_box = checkpoint.item_box.duplicate(true)
	Game.health_changed.emit(Game.hp, Game.MAX_HP)
	Game.goto_level(checkpoint.level, checkpoint.spawn)

func show_ending(ending: String) -> void:
	var bg := ColorRect.new()
	bg.name = "Ending"
	bg.color = Color(0, 0, 0, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.offset_left = -420; v.offset_right = 420; v.offset_top = -260; v.offset_bottom = 260
	v.add_theme_constant_override("separation", 12)
	bg.add_child(v)
	var text: String = ENDINGS.get(ending, ENDINGS["default"])
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.custom_minimum_size = Vector2(820, 300)
	rt.text = text
	rt.add_theme_font_size_override("normal_font_size", 18)
	v.add_child(rt)
	var rank := "S" if Game.play_time < 3600 and Game.saves_used <= 3 else ("A" if Game.play_time < 5400 else "B")
	v.add_child(_label("Clear time %s   ·   Saves %d   ·   Deaths %d   ·   Rank %s" % [Game.format_time(Game.play_time), Game.saves_used, Game.deaths, rank], 16, C_DIM))
	var b := _button("Return to Title", func():
		close_modal()
		quit_to_title(), v)
	_open_modal(bg)
	b.grab_focus()

const ENDINGS := {
	"dark": """[center][b]ENDING: DARK[/b][/center]

Elias pulled the last disconnect by hand. Somewhere on the lake, forty thousand servers went quiet, and the warm breath in the pipeline stopped.

Down in the cavern, the hum fell an octave, and then another, until it was only the sound of the ice settling. The lattice grew dull. Whatever had worn his mother's face went still and stayed still.

At 7:52 the sun came up over Kettle Falls for the first time in three days. The co-op's crews found the town's feeders closed, the school lit, and eighty-one people alive in its gym.

Corvane Systems filed suit against Lakeshore Electric on December 28th. Elias was named personally. He kept the letter on the fridge, next to June's drawing of the substation, and never once regretted it.

[i]"Load shed: Meridian. Priority: Kettle Falls."[/i]""",
	"thaw": """[center][b]ENDING: THAW[/b][/center]

Elias opened the pipeline to full. The brine boiled. The cavern screamed in a hundred voices and one of them was his mother's, and then all of them were steam.

By morning nothing in the Lower Kettle mine was alive, and nothing in it ever would be again. Meridian never dropped a single request.

Corvane's statement called it "a tragic mining accident during an extreme weather event." Northline's insurers paid out. The data centre doubled its capacity the following spring.

June doesn't talk about that night. Sometimes she leaves her radio on 146.52 and just listens to the static, as if someone down there might still answer.""",
	"default": """[center][b]THE END[/b][/center]

Kettle Falls is behind you. The cold is not.""",
}
