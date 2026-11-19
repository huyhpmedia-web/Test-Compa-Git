extends SubViewportContainer
## Item inspection stage (RE-style): the item's real 3D model on a lit turntable, drag to rotate,
## wheel to zoom, slow idle spin. Items without a 3D model show their studio photo instead.
##
##   var st := ItemView.new(); st.custom_minimum_size = Vector2(420, 420); st.setup("handgun"); parent.add_child(st)
##   ItemView.icon("ammo_9mm") -> Texture2D (inventory slot icon)
##   ItemView.model("flare")   -> Node3D (the raw real-scale model, metres) or null; used by world pickups
##   ItemView.fitted("flare")  -> Node3D (model laid out + scaled to the stage frame); used by tools/ui_shot.gd

const ICONS := "res://assets/items/icons/"
const MODELS := "res://assets/items/models/"
const FX = preload("res://world/fx.gd")

const GRAIN_SHADER := """
shader_type canvas_item;
render_mode blend_premul_alpha;
uniform float strength = 1.0;
void fragment() {
	vec2 uv = UV - 0.5;
	float v = smoothstep(0.30, 0.78, length(uv * vec2(1.0, 1.15)));
	float g = fract(sin(dot(UV * vec2(1013.3, 671.7) + floor(TIME * 24.0) * vec2(13.1, 7.7), vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	float a = v * 0.72 * strength;
	COLOR = vec4(vec3(max(g, 0.0) * 0.07 * strength), a);
}
"""

var _vp: SubViewport
var _pivot: Node3D
var _cam: Camera3D
var _photo: TextureRect
var _hint: Label
var _size_lbl: Label
var _drag := false
var _yaw := 0.6
var _pitch := -0.25
var _zoom := 1.0
var _idle := 0.0
var _touched := false
var _cam_dist := 3.3

static func icon(id: String) -> Texture2D:
	var p := ICONS + id + ".jpg"
	return load(p) if ResourceLoader.exists(p) else null

static func has_model(id: String) -> bool:
	if ResourceLoader.exists(MODELS + id + ".glb"):
		return true
	return ResourceLoader.exists("res://assets/weapons/%s/%s.glb" % [id, id])

## Raw model of a (non-weapon) item in real-world metres; null when there is none.
static func model(id: String) -> Node3D:
	var p := MODELS + id + ".glb"
	if ResourceLoader.exists(p):
		return (load(p) as PackedScene).instantiate()
	return null

func setup(id: String) -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_vp = SubViewport.new()
	_vp.transparent_bg = false
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_vp)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.055, 0.065)
	# a dim studio sky gives metal / glass something to reflect (keys, bottles, brass)
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.38, 0.5)
	sky_mat.sky_horizon_color = Color(0.85, 0.78, 0.68)
	sky_mat.ground_horizon_color = Color(0.5, 0.45, 0.4)
	sky_mat.ground_bottom_color = Color(0.04, 0.04, 0.05)
	sky_mat.sky_energy_multiplier = 0.7
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.2
	env.glow_bloom = 0.04
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -42, 0)
	key.light_energy = 1.7
	key.light_color = Color(1.0, 0.94, 0.85)
	key.shadow_enabled = true
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-12, 150, 0)
	rim.light_energy = 1.1
	rim.light_color = Color(0.6, 0.75, 1.0)
	_vp.add_child(rim)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-8, 70, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(1.0, 0.85, 0.7)
	_vp.add_child(fill)
	_vp.add_child(_pool())
	_cam = Camera3D.new()
	_cam.fov = 30.0
	_vp.add_child(_cam)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	var aspect := 1.0
	if custom_minimum_size.y > 0.0:
		aspect = custom_minimum_size.x / custom_minimum_size.y
	var m := _model_for(id)
	if m != null:
		_pivot.add_child(m)
		var fit := _fit(m, aspect)
		var cm: float = fit.get("longest_cm", 0.0)
		if cm > 0.0:
			_make_size_label(cm)
		_make_hint()
	else:
		# no 3D model yet: show the studio photo, filling the stage
		_photo = TextureRect.new()
		_photo.texture = icon(id)
		_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_photo.set_anchors_preset(Control.PRESET_FULL_RECT)
		_photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_photo)
	_add_film_overlay()
	_update_cam()

## Soft light pool under the item so it reads as sitting on a lit turntable, not floating in the void.
func _pool() -> MeshInstance3D:
	var g := Gradient.new()
	g.set_color(0, Color(0.75, 0.82, 0.95, 0.22))
	g.set_color(1, Color(0.75, 0.82, 0.95, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	var qm := QuadMesh.new()
	qm.size = Vector2(3.4, 3.4)
	qm.orientation = PlaneMesh.FACE_Y
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = gt
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = qm
	mi.material_override = mat
	mi.position = Vector3(0, -0.95, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _add_film_overlay() -> void:
	var sh := Shader.new()
	sh.code = GRAIN_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var r := ColorRect.new()
	r.material = mat
	r.color = Color.WHITE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)

func _make_hint() -> void:
	_hint = Label.new()
	_hint.text = "⟲  DRAG TO ROTATE   ·   WHEEL TO ZOOM"
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.add_theme_color_override("font_color", Color(0.78, 0.8, 0.85, 0.55))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -22
	_hint.offset_bottom = -6
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)

func _make_size_label(cm: float) -> void:
	_size_lbl = Label.new()
	_size_lbl.text = ("%.0f cm" % cm) if cm >= 10.0 else ("%.1f cm" % cm)
	if cm >= 100.0:
		_size_lbl.text = "%.2f m" % (cm / 100.0)
	_size_lbl.add_theme_font_size_override("font_size", 11)
	_size_lbl.add_theme_color_override("font_color", Color(0.78, 0.8, 0.85, 0.5))
	_size_lbl.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_size_lbl.offset_left = -90
	_size_lbl.offset_right = -10
	_size_lbl.offset_top = 8
	_size_lbl.offset_bottom = 24
	_size_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_size_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_size_lbl)

func _model_for(id: String) -> Node3D:
	var m := model(id)
	if m != null:
		return m
	if ResourceLoader.exists("res://assets/weapons/%s/%s.glb" % [id, id]):
		return FX.weapon_mesh(id)
	return null

## Standalone fitted model (for contact sheets): laid out and scaled like the inspector stage.
static func fitted(id: String, aspect := 1.0) -> Node3D:
	var holder := Node3D.new()
	var m: Node3D = model(id)
	if m == null:
		return holder
	holder.add_child(m)
	_fit(m, aspect)
	return holder

static func _aabb_of(model_root: Node3D) -> AABB:
	var ab := AABB()
	var first := true
	for mi in model_root.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		var a: AABB = _rel(model_root, m) * m.mesh.get_aabb()
		ab = a if first else ab.merge(a)
		first = false
	return ab

## Centre the model on the pivot and scale it into the frame. Compact items: bounding sphere ~1.55.
## Elongated items (poles, flares, guns) lie on their side along X and may use the full stage width.
## Returns {"longest_cm": real-world longest dimension}.
static func _fit(model_root: Node3D, aspect := 1.0) -> Dictionary:
	var ab := _aabb_of(model_root)
	if ab.size == Vector3.ZERO:
		return {}
	var sz := ab.size
	var longest := maxf(sz.x, maxf(sz.y, sz.z))
	var others := sz.x + sz.y + sz.z - longest - minf(sz.x, minf(sz.y, sz.z))
	var elongated := longest > maxf(others, 0.0001) * 2.2
	var orient := Node3D.new()
	var s := 1.55 / maxf(sz.length(), 0.001)
	if elongated:
		# lay it along X: longest axis -> X
		if sz.y >= sz.x and sz.y >= sz.z:
			orient.rotation.z = PI * 0.5
		elif sz.z >= sz.x and sz.z >= sz.y:
			orient.rotation.y = PI * 0.5
		var view_w := 1.77 * clampf(aspect, 0.6, 2.0)
		s = minf(view_w * 0.80, 2.3) / longest
	orient.scale = Vector3.ONE * s
	var par := model_root.get_parent()
	par.remove_child(model_root)
	orient.add_child(model_root)
	par.add_child(orient)
	model_root.transform = Transform3D(Basis(), -ab.get_center())
	return {"longest_cm": longest * 100.0}

static func _rel(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t

func _update_cam() -> void:
	if _cam == null:
		return
	var d := _cam_dist * _zoom
	var dir := Vector3(sin(_yaw) * cos(_pitch), -sin(_pitch), cos(_yaw) * cos(_pitch))
	_cam.look_at_from_position(dir * d, Vector3.ZERO, Vector3.UP)

func _process(delta: float) -> void:
	if _pivot == null:
		return
	_idle += delta
	if not _drag and _idle > 1.5:
		_yaw += delta * 0.35
		_update_cam()
	if _hint != null and _touched:
		_hint.modulate.a = move_toward(_hint.modulate.a, 0.0, delta * 1.5)

func _gui_input(event: InputEvent) -> void:
	if _photo != null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
			_idle = 0.0
			if mb.pressed:
				_touched = true
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom = clampf(_zoom - 0.08, 0.45, 1.6)
			_update_cam()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom = clampf(_zoom + 0.08, 0.45, 1.6)
			_update_cam()
		accept_event()
	elif event is InputEventMouseMotion and _drag:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.01
		_pitch = clampf(_pitch + mm.relative.y * 0.01, -1.3, 1.3)
		_idle = 0.0
		_update_cam()
		accept_event()
