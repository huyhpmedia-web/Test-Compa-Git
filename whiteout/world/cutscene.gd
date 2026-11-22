extends Node3D
## R8-C: in-engine cinematic director.
##
##   var cs := cine()                 # (levels/level.gd helper) letterbox slides in, HUD hides,
##                                    # player locked, a cinematic Camera3D with depth of field takes over
##   cs.shot({"from": a, "to": b, "look": target, "dur": 4.0, "fov": 40})   # keyframed dolly / pan
##   cs.close(node, toward)           # helpers: face close-up, over-the-shoulder, orbit, crane
##   await say([...])                 # lines show as subtitles (still UI.dialogue -> tr(), so vi works)
##   cs.finish()                      # bars out, gameplay camera restored
##
## Hold E (or press Esc) to skip: dialogue auto-advances and scripted timers run at 4x behind a fade.
## Under automation (tools/playtest.gd, shot/dev tools in res://tools/, headless) the director is
## inert: no camera, no bars, no lock, no time-scale changes, so flags and timing are untouched.
##
## Shot spec keys (all optional except "look"):
##   from, to       camera position at start / end (Vector3, or Node3D -> its position + "off")
##   look, look_to  look target at start / end (Vector3 or Node3D -> head height, "look_h" = 1.55)
##   dur            seconds (default 3)        ease   "inout" | "out" | "in" | "linear"
##   fov, fov_to    degrees (default 45)       blend  seconds to blend from the previous shot (0 = cut)
##   dof            blur amount (default 0.1)  focus  fixed focus distance (default: distance to look)
##   shake          handheld sway amplitude (default 0.012 rad)

static var active: Node = null
static var force := false            # dev tools (tools/cine_shot.gd) set this to film cutscenes

var level: Node3D
var inert := true
var cam: Camera3D
var attrs: CameraAttributesPractical
var _layer: CanvasLayer
var _top: ColorRect
var _bot: ColorRect
var _black: ColorRect
var _hint: Label
var _queue: Array = []
var _cur: Dictionary = {}
var _blend_from := Transform3D()
var _prev_locked := false
var _hud_was := true
var _dlg_saved := {}
var _hold := 0.0
var _last_ms := 0
var skipping := false
var finished := false
var _noise_t := 0.0

static func automated() -> bool:
	if force:
		return false
	if DisplayServer.get_name() == "headless":
		return true
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var cs: Node = (ml as SceneTree).current_scene
		if cs != null and cs.get_script() != null and String(cs.get_script().resource_path).begins_with("res://tools/"):
			return true
	return false

static func start(lvl: Node3D, opts := {}) -> Node:
	if active != null and is_instance_valid(active):
		active.call("finish")
	var c = load("res://world/cutscene.gd").new()
	c.name = "Cutscene"
	c.level = lvl
	c.inert = automated()
	lvl.add_child(c)
	if not c.inert:
		active = c
		c._begin(opts)
	return c

# ------------------------------------------------------------------ lifecycle
func _begin(opts: Dictionary) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var p = Game.player
	_prev_locked = p != null and is_instance_valid(p) and bool(p.get("input_locked"))
	if p != null and is_instance_valid(p):
		p.set("input_locked", true)
	# camera starts exactly where the gameplay camera is, the first shot blends from there
	cam = Camera3D.new()
	cam.name = "CineCam"
	cam.near = 0.05
	cam.far = 400.0
	cam.fov = 45.0
	attrs = CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_near_enabled = true
	attrs.dof_blur_amount = 0.1
	cam.attributes = attrs
	add_child(cam)
	var vp_cam := get_viewport().get_camera_3d()
	if vp_cam != null:
		cam.global_transform = vp_cam.global_transform
		cam.fov = vp_cam.fov
	_blend_from = cam.global_transform
	cam.make_current()
	# letterbox + skip hint + skip fade
	_layer = CanvasLayer.new()
	_layer.layer = 9            # under the UI layer (10): subtitles sit on the bottom bar
	add_child(_layer)
	_top = ColorRect.new()
	_bot = ColorRect.new()
	for r in [_top, _bot]:
		r.color = Color(0, 0, 0, 1)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_layer.add_child(r)
	_top.anchor_right = 1.0
	_bot.anchor_right = 1.0
	_bot.anchor_top = 1.0
	_bot.anchor_bottom = 1.0
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 0)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_black)
	_hint = Label.new()
	_hint.text = tr("HOLD E TO SKIP")
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.modulate = Color(0.75, 0.75, 0.72, 0.0)
	_hint.anchor_left = 1.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = -170
	_hint.offset_right = -22
	_hint.offset_top = -30
	_hint.offset_bottom = -12
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_layer.add_child(_hint)
	_set_bars(0.0)
	var bar: float = opts.get("bars", 0.125)
	var tw := create_tween()
	tw.tween_method(_set_bars, 0.0, bar, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_hint, "modulate:a", 0.55, 1.2).set_delay(0.8)
	# HUD off, dialogue box becomes a subtitle on the bottom bar
	_hud_was = UI.hud.visible
	UI.hud.visible = false
	UI.set_prompt("")
	_subtitle_mode(true)
	_last_ms = Time.get_ticks_msec()

func finish() -> void:
	if finished:
		return
	finished = true
	if inert:
		queue_free()
		return
	if active == self:
		active = null
	Engine.time_scale = 1.0
	_subtitle_mode(false)
	UI.hud.visible = _hud_was
	var p = Game.player
	if p != null and is_instance_valid(p):
		if not _prev_locked:
			p.set("input_locked", false)
		var pc = p.get("cam")
		if pc is Camera3D and is_instance_valid(pc):
			(pc as Camera3D).make_current()
	if cam != null:
		cam.current = false
	_queue.clear()
	_cur = {}
	# bars slide out (and the skip fade lifts) on a free-standing layer, then everything goes
	var tw := create_tween()
	tw.tween_method(_set_bars, _bar_h, 0.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_black, "color:a", 0.0, 0.45)
	tw.parallel().tween_property(_hint, "modulate:a", 0.0, 0.2)
	tw.tween_callback(queue_free)

func _exit_tree() -> void:
	if inert:
		return
	if not finished:
		Engine.time_scale = 1.0
		_subtitle_mode(false)
		if UI.hud != null:
			UI.hud.visible = _hud_was
		if active == self:
			active = null

# ------------------------------------------------------------------ letterbox + subtitles
var _bar_h := 0.0
func _set_bars(h: float) -> void:
	_bar_h = h
	var vh := get_viewport().get_visible_rect().size.y if is_inside_tree() else 720.0
	_top.offset_bottom = vh * h
	_bot.offset_top = -vh * h

func _subtitle_mode(on: bool) -> void:
	var pnl: PanelContainer = UI.dlg_panel
	if pnl == null:
		return
	if on:
		_dlg_saved = {"t": pnl.offset_top, "b": pnl.offset_bottom, "l": pnl.offset_left, "r": pnl.offset_right, "m": pnl.self_modulate}
		pnl.self_modulate = Color(1, 1, 1, 0)        # no box: white subtitle text on the black bar
		pnl.offset_left = -430
		pnl.offset_right = 430
		pnl.offset_top = -118
		pnl.offset_bottom = -14
		UI.dlg_text.add_theme_constant_override("outline_size", 6)
		UI.dlg_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		UI.dlg_text.add_theme_color_override("default_color", Color(0.93, 0.92, 0.88))
		UI.dlg_text.custom_minimum_size.x = 820
		UI.dlg_name.add_theme_constant_override("outline_size", 5)
		UI.dlg_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	elif not _dlg_saved.is_empty():
		pnl.self_modulate = _dlg_saved.m
		pnl.offset_top = _dlg_saved.t
		pnl.offset_bottom = _dlg_saved.b
		pnl.offset_left = _dlg_saved.l
		pnl.offset_right = _dlg_saved.r
		UI.dlg_text.remove_theme_constant_override("outline_size")
		UI.dlg_text.remove_theme_color_override("font_outline_color")
		UI.dlg_text.remove_theme_color_override("default_color")
		UI.dlg_text.custom_minimum_size.x = 620
		UI.dlg_name.remove_theme_constant_override("outline_size")
		UI.dlg_name.remove_theme_color_override("font_outline_color")
		_dlg_saved = {}

# ------------------------------------------------------------------ shots
## Queue a camera move. Returns self (chainable).
func shot(spec: Dictionary) -> Node:
	if inert or finished:
		return self
	_queue.append(spec.duplicate())
	if _cur.is_empty():
		_next()
	return self

## Cut straight to the given shot (drops queued ones).
func cut(spec: Dictionary) -> Node:
	if inert or finished:
		return self
	_queue.clear()
	_cur = {}
	return shot(spec)

## Waits until every queued shot has played (returns at once when inert or skipping).
func wait_shots() -> void:
	while not inert and not finished and not skipping and (not _queue.is_empty() or (not _cur.is_empty() and _cur.t < _cur.dur)):
		await get_tree().process_frame

## Face close-up: camera between `subject` and `toward`, slightly off-axis, slow push-in.
func close(subject: Node3D, toward: Vector3, dur := 4.0, dist := 1.25, side := 0.35, opts := {}) -> Node:
	if inert or subject == null or not is_instance_valid(subject):
		return self
	var head := subject.global_position + Vector3(0, float(opts.get("look_h", 1.6)), 0)
	var d := toward - head
	d.y = 0.0
	d = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
	var right := d.cross(Vector3.UP).normalized()
	var a := head + d * dist + right * side + Vector3(0, 0.05, 0)
	var b := head + d * (dist * 0.78) + right * side * 0.8 + Vector3(0, 0.03, 0)
	var s := {"from": a, "to": b, "look": subject, "look_h": float(opts.get("look_h", 1.6)), "dur": dur, "fov": 32.0, "dof": 0.14}
	s.merge(opts, true)
	return shot(s)

## Over-the-shoulder of `subject`, looking at `target` (Vector3 or Node3D).
func ots(subject: Node3D, target: Variant, dur := 4.0, side := 1.0, opts := {}) -> Node:
	if inert or subject == null or not is_instance_valid(subject):
		return self
	var tp: Vector3 = _resolve(target, 1.5)
	var sp := subject.global_position + Vector3(0, 1.6, 0)
	var d := tp - sp
	d.y = 0.0
	d = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
	var right := d.cross(Vector3.UP).normalized() * side
	var a := sp - d * 1.35 + right * 0.55 + Vector3(0, 0.08, 0)
	var b := sp - d * 1.1 + right * 0.5 + Vector3(0, 0.06, 0)
	var s := {"from": a, "to": b, "look": target, "dur": dur, "fov": 40.0, "dof": 0.1}
	s.merge(opts, true)
	return shot(s)

## Slow orbit around a point (degrees, 0 = +Z side).
func orbit(center: Vector3, radius: float, height: float, a0: float, a1: float, dur := 6.0, opts := {}) -> Node:
	var p0 := center + Vector3(sin(deg_to_rad(a0)) * radius, height, cos(deg_to_rad(a0)) * radius)
	var p1 := center + Vector3(sin(deg_to_rad(a1)) * radius, height, cos(deg_to_rad(a1)) * radius)
	var s := {"from": p0, "to": p1, "look": center + Vector3(0, float(opts.get("look_y", 1.2)), 0), "dur": dur, "fov": 42.0, "ease": "linear"}
	s.merge(opts, true)
	return shot(s)

func _next() -> void:
	if _queue.is_empty():
		return
	var s: Dictionary = _queue.pop_front()
	s.t = 0.0
	s.dur = maxf(0.05, float(s.get("dur", 3.0)))
	if _cur.is_empty() and not s.has("blend"):
		s.blend = 1.1 if cam != null and _first_shot else 0.0
	_first_shot = false
	_blend_from = cam.global_transform
	s.fov0 = float(s.get("fov", 45.0))
	s.fov1 = float(s.get("fov_to", s.fov0))
	s.look_h = float(s.get("look_h", 1.55))
	_cur = s

var _first_shot := true

func _resolve(v: Variant, h := 1.55) -> Vector3:
	if v is Node3D:
		if is_instance_valid(v):
			return (v as Node3D).global_position + Vector3(0, h, 0)
		return Vector3.ZERO
	if v is Vector3:
		return v
	return Vector3.ZERO

func _ease(k: float, mode: String) -> float:
	match mode:
		"linear": return k
		"in": return k * k * k
		"out": return 1.0 - pow(1.0 - k, 3.0)
	return k * k * (3.0 - 2.0 * k) if k < 1.0 else 1.0

func _process(delta: float) -> void:
	if inert or finished:
		return
	var now := Time.get_ticks_msec()
	var real_dt := (now - _last_ms) / 1000.0
	_last_ms = now
	_update_skip(real_dt)
	if _cur.is_empty():
		return
	_cur.t += delta
	if _cur.t >= _cur.dur and not _queue.is_empty():
		_next()
	var k := clampf(_cur.t / _cur.dur, 0.0, 1.0)
	var e := _ease(k, String(_cur.get("ease", "inout")))
	var look0 := _resolve(_cur.get("look"), _cur.look_h)
	var look1 := _resolve(_cur.get("look_to", _cur.get("look")), _cur.look_h)
	var look := look0.lerp(look1, e)
	var off: Vector3 = _cur.get("off", Vector3.ZERO)
	var p0 := _resolve(_cur.get("from", cam.global_position), 0.0) + off
	var p1 := _resolve(_cur.get("to", _cur.get("from", cam.global_position)), 0.0) + off
	var pos := _safe(look, p0.lerp(p1, e))
	var xf := Transform3D(Basis(), pos)
	if pos.distance_to(look) > 0.01:
		var up := Vector3.UP if absf((look - pos).normalized().y) < 0.98 else Vector3.FORWARD
		xf = xf.looking_at(look, up)
	# handheld sway (two incommensurate sines per axis)
	_noise_t += delta
	var sh := float(_cur.get("shake", 0.012))
	if sh > 0.0:
		var rx := sh * (sin(_noise_t * 0.71) * 0.6 + sin(_noise_t * 1.93 + 1.3) * 0.4)
		var ry := sh * (sin(_noise_t * 0.53 + 2.1) * 0.6 + sin(_noise_t * 1.37) * 0.4)
		xf.basis = xf.basis * Basis.from_euler(Vector3(rx, ry, 0.0))
	var bl := float(_cur.get("blend", 0.0))
	if bl > 0.0 and _cur.t < bl:
		var kb := smoothstep(0.0, 1.0, _cur.t / bl)
		xf = _blend_from.interpolate_with(xf, kb)
	cam.global_transform = xf
	cam.fov = lerpf(_cur.fov0, _cur.fov1, e)
	# depth of field: focus on the look target, shallow for close shots, gentle for wide ones
	var focus := float(_cur.get("focus", cam.global_position.distance_to(look)))
	attrs.dof_blur_amount = float(_cur.get("dof", 0.1))
	attrs.dof_blur_far_distance = focus + maxf(1.2, focus * 0.3)
	attrs.dof_blur_far_transition = maxf(2.0, focus * 0.9)
	attrs.dof_blur_near_enabled = focus < 30.0
	attrs.dof_blur_near_distance = maxf(0.2, focus * 0.5)
	attrs.dof_blur_near_transition = maxf(0.2, focus * 0.35)

## Keep the camera out of walls: pull it toward the look target if level geometry is in between.
func _safe(look: Vector3, pos: Vector3) -> Vector3:
	if not is_inside_tree():
		return pos
	var q := PhysicsRayQueryParameters3D.create(look, pos, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return pos
	var d := (pos - look).normalized()
	return (hit.position as Vector3) - d * 0.25

# ------------------------------------------------------------------ skipping
func _update_skip(real_dt: float) -> void:
	if skipping:
		UI._dlg_advance = true
		return
	if Input.is_action_just_pressed("pause"):
		_skip()
		return
	if Input.is_action_pressed("interact"):
		_hold += real_dt
		_hint.modulate.a = 0.55 + 0.45 * clampf(_hold / 0.8, 0.0, 1.0)
		if _hold >= 0.8:
			_skip()
	else:
		_hold = 0.0

func _skip() -> void:
	if skipping:
		return
	skipping = true
	_queue.clear()
	UI._dlg_advance = true
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(_black, "color:a", 1.0, 0.2)
	Engine.time_scale = 4.0      # scripted timers / tweens of the beat run out behind the fade
