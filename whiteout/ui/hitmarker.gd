extends CanvasLayer
## Hit / kill confirmation at the screen centre: white tick marks on a hit (4 diagonal ticks that pinch in), a bigger red X on a kill, a thicker one on a headshot.
## Self-installing: Hitmarker.install(node) once (Player does it); Hitmarker.ping("hit"|"head"|"kill") from anywhere. ui.gd only needs to keep layer < 100.

const SELF := preload("res://ui/hitmarker.gd")
static var _inst: CanvasLayer = null

var _kind := ""
var _t := 0.0
var _len := 0.2
var _canvas: Control

static func install(from: Node) -> void:
	if _inst != null and is_instance_valid(_inst):
		return
	var h := CanvasLayer.new()
	h.set_script(SELF)
	h.name = "Hitmarker"
	h.layer = 40
	from.get_tree().root.add_child.call_deferred(h)
	_inst = h

static func ping(kind: String) -> void:
	if _inst != null and is_instance_valid(_inst):
		_inst._show(kind)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_marks)
	add_child(_canvas)
	set_process(false)

func _show(kind: String) -> void:
	_kind = kind
	_t = 0.0
	_len = 0.45 if kind == "kill" else 0.2
	set_process(true)
	match kind:
		"kill": Sfx.play("killmark", -4.0)
		"head": Sfx.play("hitmark", -3.0, 1.25)
		_: Sfx.play("hitmark", -8.0, randf_range(0.95, 1.05))

func _process(delta: float) -> void:
	_t += delta / maxf(Engine.time_scale, 0.05)   # keep real-time while hit-stop slows the game
	if _t >= _len:
		_kind = ""
		set_process(false)
	_canvas.queue_redraw()

func _draw_marks() -> void:
	if _kind == "":
		return
	var c := _canvas.size * 0.5
	var k := _t / _len
	var a := 1.0 - smoothstep(0.35, 1.0, k)
	var col := Color(1, 1, 1, a)
	if _kind == "kill":
		col = Color(0.95, 0.12, 0.1, a)
	elif _kind == "head":
		col = Color(1.0, 0.82, 0.3, a)
	var inner := lerpf(15.0, 8.0, minf(k * 4.0, 1.0)) if _kind != "kill" else lerpf(24.0, 11.0, minf(k * 5.0, 1.0))
	var length := 9.0 if _kind != "kill" else 14.0
	var wd := 2.0 if _kind != "head" else 3.0
	if _kind == "kill":
		wd = 3.0
	for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var dn: Vector2 = d.normalized()
		_canvas.draw_line(c + dn * inner, c + dn * (inner + length), Color(0, 0, 0, a * 0.5), wd + 2.0)
		_canvas.draw_line(c + dn * inner, c + dn * (inner + length), col, wd)
