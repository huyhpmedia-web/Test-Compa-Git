extends RefCounted
## L1 - Highway 53 / Kettle Falls substation. First night: restrained but unmistakable. The road
## tells what happened to the people who tried to walk to town; the van carries the first warning
## ("DON'T SLEEP"); the yard shows a man who died at his post; the gate shows who never got in.

const D = preload("res://levels/dressing/dress_util.gd")
const Gore = preload("res://world/gore.gd")
const Props = preload("res://world/props.gd")

static func dress(level: Node3D) -> void:
	D.begin(level)
	_family_car()
	_road_trail()
	_van()
	_red_car()
	_yard()
	_control_house_door()
	_gate()
	_ditch_truck()
	_env()
	_banks_and_tracks()

# the frozen family car at (-1.9, -9): someone was dragged out of it into the ditch
static func _family_car() -> void:
	var c := Vector3(-1.9, 0.02, -9.0)
	D.pool(c + Vector3(-1.6, 0, 0.6), 1.6)
	D.splat(c + Vector3(-0.2, 0, 2.2), 0.9)
	D.drag(c + Vector3(-1.8, 0, 0.9), Vector3(-7.4, 0.02, -14.6), 0.15, 0.0)
	D.droplets(c + Vector3(-1.0, 0, -1.0), c + Vector3(-1.9, 0, 0.6), 4)
	# smeared handprints on the driver's door (west side of the car, tilted 0.28 rad)
	var n := Vector3(-cos(0.28), 0, sin(0.28))
	D.hands(c + Vector3(-0.95, 0.9, -0.5), c + Vector3(-0.95, 0.75, -0.3), n, 2, 0.22)
	D.drips(c + Vector3(-0.95, 0.88, -0.1), n, 0.55)

# a lone survivor staggering up the centre line, losing blood: boots, drops, a rest stop
static func _road_trail() -> void:
	D.steps(Vector3(-0.6, 0.05, -14.0), Vector3(-0.5, 0.05, -29.5), 0.95, false)
	D.droplets(Vector3(-0.8, 0.05, -14.0), Vector3(-0.3, 0.05, -33.0), 10, 0.3)
	# he sat against the snowbank by the sign for a while
	D.pool(Vector3(5.8, 0.03, -26.0), 1.7)
	D.smear(Vector3(6.2, 0.03, -26.0), Vector3.UP, Vector3(0.3, 0, -1.0), 1.8)
	D.hands(Vector3(5.2, 0.04, -26.0), Vector3(5.4, 0.04, -27.0), Vector3.UP, 2, 0.2)
	D.steps(Vector3(5.4, 0.05, -28.0), Vector3(1.8, 0.05, -45.0), 0.95, false)
	D.droplets(Vector3(5.0, 0.05, -28.0), Vector3(1.5, 0.05, -46.0), 8, 0.28)

# the abandoned van across the lane: a warning written in blood and a bad night inside it
static func _van() -> void:
	var yaw := 0.12
	var n := Vector3(cos(yaw), 0, -sin(yaw))              # east face (toward the road)
	var p := Vector3(-2.4, 0.0, -52.0) + n * 1.02
	D.write("sleep", p + Vector3(0, 1.25, 0.0), n, 2.3)
	D.drips(p + Vector3(0, 0.95, 0.9), n, 0.6)
	D.hands(p + Vector3(0, 0.9, -1.6), p + Vector3(0.0, 0.8, -2.0), n, 2, 0.22)
	D.pool(Vector3(-0.3, 0.04, -52.8), 2.0)
	D.drag(Vector3(-0.3, 0.04, -52.8), Vector3(5.2, 0.04, -56.5), 0.0, 0.0)
	D.splat(Vector3(-0.6, 0.04, -50.0), 0.8)

static func _red_car() -> void:
	var c := Vector3(2.6, 0.03, -33.0)
	D.pool(c + Vector3(-1.4, 0, 0.3), 1.4)
	D.splat(c + Vector3(0.8, 0, 1.8), 0.9)
	D.spray(c + Vector3(-1.1, 0.04, 2.6), Vector3.UP, Vector3(-0.6, 0, 1.0), 1.4)

# the yard: the operator's death in the cold, a bad scene at the pickup, a victim at the transformers
static func _yard() -> void:
	var op := Vector3(37.4, 0.03, -90.8)
	Gore.frozen_blood(level_ref(), op + Vector3(0.4, 0, 0.0), 2.6, {"local": true})
	D.n += 2
	D.droplets(Vector3(36.0, 0.04, -86.5), op, 5, 0.3)
	D.hands(Vector3(35.0, 0.05, -88.5), Vector3(36.0, 0.05, -90.0), Vector3.UP, 2, 0.22)
	# pickup truck at (21,-64): tailgate and bed
	var tg := Vector3(21.0, 0.0, -64.0) + Vector3(-2.75, 0, 0)       # rear at -x (yaw PI/2 -> bed toward -x)
	D.pool(tg + Vector3(-1.0, 0.03, -0.3), 1.5)
	D.drips(tg + Vector3(0.05, 1.05, 0.2), Vector3(-1, 0, 0), 0.55)
	D.splat(tg + Vector3(-0.2, 0.03, 1.8), 0.8)
	# a smear leading up to the downed line: someone reached for the wire
	D.drag(Vector3(13.5, 0.03, -63.0), Vector3(10.0, 0.03, -61.8), 0.0, 1.1)
	# the T2 transformer: handprints on the cold steel
	D.hands(Vector3(41.0, 1.0, -73.0), Vector3(41.0, 1.3, -74.0), Vector3(-1, 0, 0), 3, 0.22)

static func _control_house_door() -> void:
	# someone crawled to the door and never got in (east face of the control house, x = 27)
	D.drag(Vector3(33.5, 0.03, -93.0), Vector3(27.9, 0.03, -81.4), 0.0, 1.6)
	var n := Vector3(1, 0, 0)
	D.hands(Vector3(27.14, 0.7, -80.6), Vector3(27.14, 1.2, -81.6), n, 4, 0.2)
	D.smear(Vector3(27.14, 0.55, -81.0), n, Vector3(0, -1, 0), 1.0)
	D.drips(Vector3(27.14, 1.5, -81.2), n, 0.8)
	D.pool(Vector3(28.4, 0.03, -81.2), 1.9)

# the road gate: everyone who ran for the school and found it chained
static func _gate() -> void:
	Props.frozen_pile(level_ref(), Vector3(-3.2, 0.0, -133.6), 0.3, 4)
	D.n += 4
	D.pool(Vector3(1.8, 0.03, -135.0), 2.2)
	D.hands(Vector3(-3.1, 0.9, -137.52), Vector3(-3.1, 1.15, -137.52), Vector3(0, 0, 1), 3, 0.22)
	D.hands(Vector3(0.9, 1.0, -137.98), Vector3(1.4, 1.5, -137.98), Vector3(0, 0, 1), 2, 0.2)
	D.steps(Vector3(0.5, 0.05, -120.0), Vector3(0.9, 0.05, -134.0), 1.0, false)
	D.drag(Vector3(5.0, 0.03, -128.0), Vector3(3.2, 0.03, -135.0), 0.0, 0.0)

# the bucket truck in the ditch: the driver's seat
static func _ditch_truck() -> void:
	D.splat(Vector3(-3.0, 0.02, 12.0), 0.9)
	D.droplets(Vector3(-3.5, 0.0, 14.0), Vector3(-1.5, 0.05, 6.0), 4, 0.25)
	D.steps(Vector3(-1.2, 0.05, 6.0), Vector3(0.0, 0.05, -4.0), 1.0, false)

static func level_ref() -> Node3D:
	return D.lv


# real set dressing: street furniture on the shoulders (never on the 8 m road) and yard clutter
static func _env() -> void:
	var lv: Node3D = D.lv
	Props.utility_box(lv, Vector3(7.2, 0.0, -3.0), PI * 0.5, true)
	Props.power_box(lv, Vector3(-6.4, 0.0, -21.0), -PI * 0.5)
	Props.hydrant(lv, Vector3(5.8, 0.0, -59.0), PI)
	Props.hydrant(lv, Vector3(-5.8, 0.0, -108.0), 0.0)
	Props.barrier(lv, Vector3(5.3, 0.0, -117.0), 0.1, 1)
	Props.barrier(lv, Vector3(5.4, 0.0, -118.5), -0.1, 2)
	Props.barrier(lv, Vector3(-5.3, 0.0, -125.0), 0.2, 1)
	Props.trash_can(lv, Vector3(14.0, 0.0, -45.8), 0.4)
	# yard: a portable generator + fuel cans by the control house, a searchlight by the fence
	Props.generator(lv, Vector3(30.0, 0.0, -62.6), 0.2)
	Props.prop(lv, "camp/jerrycan", Vector3(31.0, 0.0, -62.4), 0.8, {"snow": 0.4, "scale": 1.2})
	Props.prop(lv, "camp/jerrycan", Vector3(31.4, 0.0, -62.9), 1.9, {"snow": 0.4, "scale": 1.2})
	Props.prop(lv, "camp/propane", Vector3(28.8, 0.0, -62.4), 0.0, {"snow": 0.4})
	Props.prop(lv, "camp/searchlight", Vector3(46.0, 0.0, -61.0), 2.8, {"snow": 0.3, "scale": 2.2})
	Props.prop(lv, "camp/crate_plastic", Vector3(24.0, 0.0, -62.0), 0.3, {"snow": 0.5, "scale": 1.5})
	Props.stump(lv, Vector3(-9.0, 0.0, -35.0), 0.3)
	Props.dead_log(lv, Vector3(-11.0, 0.0, 6.0), 1.2, false)


# sculpted plough banks along both shoulders (long wind-shaped mounds with gaps), and tyre tracks printed in the road snow
static func _banks_and_tracks() -> void:
	var lv: Node3D = D.lv
	var rng := RandomNumberGenerator.new()
	rng.seed = 7311
	for side in [-1.0, 1.0]:
		var z := 36.0
		while z > -138.0:
			var len := rng.randf_range(5.0, 9.0)
			if rng.randf() < 0.82 and not (z < 4.0 and z > -3.0 and side < 0.0):
				var w := rng.randf_range(1.2, 2.0)
				Props.drift(lv, Vector3(side * (4.9 + w * 0.55 + rng.randf_range(0, 0.6)), -0.02, z - len * 0.5), w, rng.randf_range(0.5, 1.0), len * 0.5, rng.randf_range(-0.08, 0.08))
			z -= len + rng.randf_range(0.5, 5.0)
	var track_m := StandardMaterial3D.new()
	track_m.albedo_color = Color(0.02, 0.02, 0.03, 0.42)
	track_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	track_m.roughness = 0.9
	for lane: float in [-1.3, 1.3, 2.2]:
		var z2 := 40.0
		while z2 > -136.0:
			var nx: float = lane + 0.35 * sin(z2 * 0.045 + lane)
			var mi := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(0.22, 6.2)
			mi.mesh = qm
			mi.material_override = track_m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			lv.add_child(mi)
			mi.position = Vector3(nx, 0.052, z2 - 3.0)
			mi.rotation = Vector3(-PI * 0.5, 0, 0.35 * 0.045 * cos(z2 * 0.045 + lane) * -1.0)
			z2 -= 6.0
