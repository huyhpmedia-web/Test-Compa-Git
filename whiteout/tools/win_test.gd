extends Node3D
## R9 window interior test: one lit house + one lit shop at night, two camera angles to show the parallax.
## xvfb-run godot --path . res://tools/win_test.tscn -- out=/path/prefix
const Town = preload("res://world/town.gd")
var out := "/tmp/win"
var cam: Camera3D
var f := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.03, 0.06)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.25, 0.3, 0.45)
	e.ambient_light_energy = 0.4
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	env.environment = e
	add_child(env)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-35, 30, 0)
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.light_energy = 0.25
	add_child(moon)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	g.mesh = pm
	add_child(g)
	Town.building(self, "house_twostory", Vector3(-6, 0, 0), 0.0, {"lit": 1.0, "porch": 0.0})
	Town.building(self, "shop_brick", Vector3(8, 0, 0), 0.0, {"lit": 1.0})
	cam = Camera3D.new()
	cam.fov = 55
	add_child(cam)
	cam.position = Vector3(-6, 1.7, 9)
	cam.look_at(Vector3(-5, 2.5, 0))

func _process(_d: float) -> void:
	f += 1
	if f == 40:
		get_viewport().get_texture().get_image().save_png(out + "_a.png")
		cam.position = Vector3(-11, 1.7, 7)
		cam.look_at(Vector3(-4, 2.2, 0))
	elif f == 80:
		get_viewport().get_texture().get_image().save_png(out + "_b.png")
		cam.position = Vector3(4, 1.7, 9)
		cam.look_at(Vector3(8, 2.2, 0))
	elif f == 120:
		get_viewport().get_texture().get_image().save_png(out + "_c.png")
		get_tree().quit()
