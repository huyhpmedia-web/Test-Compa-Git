extends "res://levels/level.gd"
## Gore test arena: a brick back wall at z=-20, shamblers standing in a row at z=-14 get killed
## programmatically with each weapon type a few frames after load (head pops, limb loss, sprays on the
## wall, fire, ice shards) so the aftermath can be photographed:
##   tools/shot.sh test_gore out.png frames=160 pos=0,0,-7 yaw=0 pitch=-0.1
## Flags:  tg_<scenario> runs only the named scenarios (magnum, shotgun, pistol, fire, knife,
##         explosion, husk, siren, limb, props); tg_nokill spawns them alive.

const Gore = preload("res://world/gore.gd")

const SCEN := ["magnum", "shotgun", "pistol", "limb", "fire", "knife", "explosion", "husk", "siren"]
var _frame := 0
var _list: Array = []
var _cam: Camera3D = null
var _use_cam := false

func build() -> void:
	env_exterior_night(false, 0.01, 0.35)
	add_spawn("start", Vector3(0, 0, -6), PI)
	floor_rect(-45, -24, 45, 6, 0.0, "concrete")
	box(Vector3(0, 3, -17.5), Vector3(92, 6, 1), "brick_dark")
	box(Vector3(-45.5, 3, -9), Vector3(1, 6, 30), "plaster_dirty")
	box(Vector3(45.5, 3, -9), Vector3(1, 6, 30), "plaster_dirty")
	var lk := 2.4 if Game.has_flag("tg_props") else 1.0
	for x in range(-40, 44, 8):
		light(Vector3(x, 4.5, -10), Color(0.75, 0.85, 1.0), 2.0 * lk, 14.0, false)
		light(Vector3(x + 3, 2.0, -9), Color(1.0, 0.8, 0.55), 1.4 * lk, 9.0, false)
	# optional fixed cameras for photographing the aftermath: tg_cam_close / tg_cam_wide / tg_cam_side
	var cam := Camera3D.new()
	_cam = cam
	cam.fov = 62.0
	add_child(cam)
	var cams := {"tg_cam_close": [Vector3(1.9, 1.5, -10.8), Vector3(0, 1.1, -14.2)], "tg_cam_wide": [Vector3(0, 2.4, -7.5), Vector3(0, 1.0, -14.5)],
		"tg_cam_side": [Vector3(-4.2, 1.3, -11.5), Vector3(0, 1.0, -14.2)], "tg_cam_row": [Vector3(0, 2.6, -4.0), Vector3(0, 1.0, -14.5)]}
	for k in cams:
		if Game.has_flag(k):
			cam.look_at_from_position(cams[k][0], cams[k][1], Vector3.UP)
			_use_cam = true
	if Game.has_flag("tg_props"):
		_props_row()
		var pc := {"tg_cam_p1": -23.0, "tg_cam_p2": -14.0, "tg_cam_p3": -5.0, "tg_cam_p4": 6.0, "tg_cam_p5": 15.0, "tg_cam_p6": 22.0}
		for k in pc:
			if Game.has_flag(k):
				var cx: float = pc[k]
				cam.fov = 66.0
				cam.look_at_from_position(Vector3(cx, 1.7, -7.6), Vector3(cx, 0.55, -12.2), Vector3.UP)
				_use_cam = true
		return
	var picked: Array = []
	for s in SCEN:
		if Game.has_flag("tg_" + s):
			picked.append(s)
	if picked.is_empty():
		picked = SCEN.duplicate()
	var i := 0
	for s in picked:
		var x := -16.0 + i * 4.0
		if picked.size() == 1:
			x = 0.0
		var kind := "zombie"
		var params := {"variant": ["civilian", "worker", "nurse", "miner"][i % 4], "speed": 0.0, "run_speed": 0.0, "sight": 0.0}
		if s == "husk":
			kind = "husk"
		elif s == "siren":
			kind = "siren"
		var e: Node3D = enemy("", kind, Vector3(x, 0, -14), 0.0, params)
		if e != null:
			_list.append([s, e])
		i += 1

func _process(delta: float) -> void:
	super._process(delta)
	_frame += 1
	if _frame == 4 and _use_cam:
		_cam.make_current()
		if Game.player != null:
			Game.player.visible = false
	if _frame == 12 and not Game.has_flag("tg_nokill"):
		_run()
	if _frame == 8 and Game.has_flag("tg_hurt"):
		Game.hp = 24
		Game.health_changed.emit(Game.hp, Game.MAX_HP)
		UI.flash_damage()
	if _frame == 40:
		for pair in _list:
			var e = pair[1]
			if is_instance_valid(e):
				print("TG ", pair[0], " state=", e.state, " hp=", e.hp, " head_gone=", e.has_meta("gore_head_gone"), " pos=", e.global_position)

func _run() -> void:
	for pair in _list:
		var s: String = pair[0]
		var e: Node3D = pair[1]
		if not is_instance_valid(e):
			continue
		var head := e.global_position + Vector3(0, 1.62, 0)
		var chest := e.global_position + Vector3(0, 1.2, 0)
		var dir := Vector3(0, 0, -1)
		match s:
			"magnum":
				Game.equipped = "magnum"
				e.take_hit(240.0, head, dir, true)
			"shotgun":
				Game.equipped = "shotgun"
				for k in 8:
					e.take_hit(14.0, chest + Vector3(randf_range(-0.1, 0.1), randf_range(-0.2, 0.2), 0), dir, false)
				Gore.lose_limb(e, "arm_r", dir, "shotgun")
			"pistol":
				Game.equipped = "handgun"
				for k in 3:
					e.take_hit(22.0, chest, dir, false)
				e.take_hit(200.0, head, dir, true)
			"limb":
				Game.equipped = "shotgun"
				e.take_hit(30.0, chest, dir, false)
				Gore.lose_limb(e, "leg_l", dir, "shotgun")
				Gore.lose_limb(e, "arm_l", dir, "shotgun")
			"fire":
				e.burn(500.0, e.global_position + Vector3(0, 0, 2))
			"knife":
				Game.equipped = "knife"
				for k in 4:
					e.take_hit(12.0, chest, Vector3(randf_range(-0.5, 0.5), 0, -1), false)
			"explosion":
				Game.equipped = "launcher"
				Gore.src_override = "explosion"
				e.take_hit(500.0, chest, dir + Vector3(0.3, 0.2, 0), false)
				Gore.src_override = ""
				Gore.lose_limb(e, "leg_r", dir, "explosion")
			"husk":
				Game.equipped = "handgun"
				for k in 4:
					e.take_hit(22.0, chest, dir, false)
			"siren":
				Game.equipped = "magnum"
				e.take_hit(300.0, head, dir, true)

func _props_row() -> void:
	var x := -26.0
	var z := -12.0
	Props.body_bag(self, Vector3(x, 0.0, z), 0.3, true, true)
	x += 3.2
	Props.torso(self, Vector3(x, 0.0, z), 0.4)
	x += 3.2
	Props.severed_limb(self, Vector3(x, 0.0, z), 0.5, "arm")
	Props.severed_limb(self, Vector3(x + 1.4, 0.0, z), -0.5, "leg")
	x += 3.6
	Props.gut_pile(self, Vector3(x, 0.0, z), 0.0, 1.2)
	x += 3.2
	Props.meat_hook(self, Vector3(x, 0.0, z), 0.0, true, 3.6)
	x += 3.2
	Props.blood_cot(self, Vector3(x, 0.0, z), 0.4)
	x += 3.2
	Props.bathtub(self, Vector3(x, 0.0, z), 0.0, true)
	x += 3.2
	Props.wheelchair(self, Vector3(x, 0.0, z), 0.0, true)
	x += 3.2
	Props.frozen_corpse(self, Vector3(x, 0.0, z), 0.3, false)
	x += 3.6
	Props.frozen_pile(self, Vector3(x, 0.0, z), 0.0, 5)
	x += 3.6
	Props.body_outline(self, Vector3(x, 0.0, z), 0.4, 1.9)
	x += 3.0
	Props.crystal_impale(self, Vector3(x, 0.0, z), 0.0, 2.4)
	x += 3.0
	Props.hanging_body(self, Vector3(x, 4.2, z), 0.0, 3.0, 0.0, true)
	x += 3.0
	Props.car_gore(self, Vector3(x + 1.0, 0.0, z - 1.0), 1.57, Color(0.25, 0.28, 0.3))
	x += 5.5
	Props.blood_writing(self, Vector3(x, 1.7, -17.0), 0.0, "help", 2.0)
	Props.glass_blood(self, Vector3(x + 3, 1.5, -12.0), 0.0, "hand", 0.3)
	Gore.drip_emitter(self, Vector3(x - 2, 3.5, -14), "water", 1.0)
	Gore.puddle(self, Vector3(x - 2, 0.0, -14), 1.4)
	Gore.steam_vent(self, Vector3(x + 6, 0.2, -14), Vector3.UP, 1.0, 0.14)
