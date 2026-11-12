extends SubViewportContainer
## Item inspection stage (RE-style): the item's real 3D model on a lit turntable, drag to rotate,
## wheel to zoom, slow idle spin. Items without a 3D model show their studio photo instead.
##
##   var st := ItemView.new(); st.custom_minimum_size = Vector2(420, 420); st.setup("handgun"); parent.add_child(st)
##   ItemView.icon("ammo_9mm") -> Texture2D (inventory slot icon)

const ICONS := "res://assets/items/icons/"
const MODELS := "res://assets/items/models/"
const FX = preload("res://world/fx.gd")

var _vp: SubViewport
var _pivot: Node3D
var _cam: Camera3D
var _photo: TextureRect
var _drag := false
var _yaw := 0.6
var _pitch := -0.25
var _zoom := 1.0
var _idle := 0.0

static func icon(id: String) -> Texture2D:
	var p := ICONS + id + ".jpg"
	return load(p) if ResourceLoader.exists(p) else null

static func has_model(id: String) -> bool:
	if ResourceLoader.exists(MODELS + id + ".glb"):
		return true
	return ResourceLoader.exists("res://assets/weapons/%s/%s.glb" % [id, id])

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
	env.background_color = Color(0.035, 0.038, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.25
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -40, 0)
	key.light_energy = 1.6
	key.light_color = Color(1.0, 0.95, 0.88)
	key.shadow_enabled = true
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 150, 0)
	rim.light_energy = 1.2
	rim.light_color = Color(0.6, 0.75, 1.0)
	_vp.add_child(rim)
	_cam = Camera3D.new()
	_cam.fov = 30.0
	_vp.add_child(_cam)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	var model := _model_for(id)
	if model != null:
		_pivot.add_child(model)
		_fit(model)
	else:
		# no 3D model yet: show the studio photo, filling the stage
		_photo = TextureRect.new()
		_photo.texture = icon(id)
		_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_photo.set_anchors_preset(Control.PRESET_FULL_RECT)
		_photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_photo)
	_update_cam()

func _model_for(id: String) -> Node3D:
	var p := MODELS + id + ".glb"
	if ResourceLoader.exists(p):
		return (load(p) as PackedScene).instantiate()
	if ResourceLoader.exists("res://assets/weapons/%s/%s.glb" % [id, id]):
		return FX.weapon_mesh(id)
	return null

## Centre the model on the pivot and scale it to a ~1 unit bounding sphere.
func _fit(model: Node3D) -> void:
	var ab := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		var t: Transform3D = model.global_transform.affine_inverse() * m.global_transform if m.is_inside_tree() else _rel(model, m)
		var a: AABB = t * m.mesh.get_aabb()
		ab = a if first else ab.merge(a)
		first = false
	if first:
		return
	# lay long items (guns, poles) on their side: longest axis -> X, then centre + scale in that frame
	var sz := ab.size
	var orient := Node3D.new()
	if sz.y >= sz.x and sz.y >= sz.z:
		orient.rotation.z = PI * 0.5
	elif sz.z >= sz.x and sz.z >= sz.y:
		orient.rotation.y = PI * 0.5
	orient.scale = Vector3.ONE * (1.6 / maxf(sz.length(), 0.001))
	var par := model.get_parent()
	par.remove_child(model)
	orient.add_child(model)
	par.add_child(orient)
	model.transform = Transform3D(Basis(), -ab.get_center())

func _rel(root: Node3D, n: Node3D) -> Transform3D:
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
	var d := 3.3 * _zoom
	var dir := Vector3(sin(_yaw) * cos(_pitch), -sin(_pitch), cos(_yaw) * cos(_pitch))
	_cam.look_at_from_position(dir * d, Vector3.ZERO, Vector3.UP)

func _process(delta: float) -> void:
	if _pivot == null:
		return
	_idle += delta
	if not _drag and _idle > 1.5:
		_yaw += delta * 0.35
		_update_cam()

func _gui_input(event: InputEvent) -> void:
	if _photo != null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
			_idle = 0.0
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
