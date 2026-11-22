extends RefCounted
## R8-C: per-level acoustic layout. Called once by levels/level.gd after build()/dressing.
##   * base space of the level (Sfx.set_base_space)
##   * reverb zones (world/audio_zone.gd): Area3D boxes that switch the SFX/ambience reverb per space
##   * positional ambience one-shots (drips, creaks, radiator knocks, distant moans, wind through
##     broken windows) and looping server-fan emitters.
## The table is documented in docs/AUDIO_ZONES.md. Coordinates come from each level's layout comments.

const Zone = preload("res://world/audio_zone.gd")

## Random one-shot emitter: every `every` seconds (random in [x, y]) plays one of `sounds` at a
## random point in the box (position +- spread), only while the player is within `radius`.
class Emitter extends Node3D:
	var sounds: Array = []        # [[name, db, pitch_min, pitch_max], ...]
	var every := Vector2(8, 16)
	var radius := 24.0
	var spread := Vector3.ZERO
	var cond: Callable
	var _t := 0.0

	func _ready() -> void:
		_t = randf_range(1.0, every.y)

	func _process(delta: float) -> void:
		_t -= delta
		if _t > 0.0:
			return
		_t = randf_range(every.x, every.y)
		var p = Game.player
		if p == null or not is_instance_valid(p) or not p.is_inside_tree():
			return
		if p.global_position.distance_to(global_position) > radius:
			return
		if cond.is_valid() and not cond.call():
			return
		var s: Array = sounds[randi() % sounds.size()]
		var off := Vector3(randf_range(-spread.x, spread.x), randf_range(-spread.y, spread.y), randf_range(-spread.z, spread.z))
		Sfx.ambient_at(s[0], global_position + off, s[1], randf_range(s[2], s[3]), radius + 10.0)

const DRIP := [["water_drip", -13.0, 0.8, 1.2]]
const CREAK := [["amb_creak", -15.0, 0.8, 1.15], ["door_open", -24.0, 0.42, 0.55]]
const RADIATOR := [["amb_radiator", -14.0, 0.9, 1.1]]
const PIPE := [["amb_pipe_groan", -17.0, 0.8, 1.15], ["amb_radiator", -22.0, 0.6, 0.75]]
const MOAN := [["zombie_groan", -24.0, 0.58, 0.72], ["hanger_groan", -26.0, 0.6, 0.75], ["husk_groan", -26.0, 0.6, 0.7]]
const WIND := [["wind_gust", -12.0, 0.85, 1.1]]
const ICE := [["ice_crack", -17.0, 0.6, 0.95]]
const HOWL := [["hound_howl", -24.0, 0.75, 0.9]]
const METAL := [["metal_impact", -24.0, 0.45, 0.6], ["amb_creak", -20.0, 0.5, 0.65]]

const BASE := {"l1_substation": "outdoor", "l2_school": "outdoor", "l3_church": "outdoor",
	"l4_meridian": "outdoor", "l5_mine": "mine", "l6_heart": "cavern"}

static func install(level: Node3D) -> void:
	var id := String(level.name)
	Sfx.set_base_space(BASE.get(id, "room" if id.begins_with("test") else "outdoor"))
	match id:
		"l1_substation": _l1(level)
		"l2_school": _l2(level)
		"l3_church": _l3(level)
		"l4_meridian": _l4(level)
		"l5_mine": _l5(level)
		"l6_heart": _l6(level)

static func zone(level: Node3D, preset: String, center: Vector3, size: Vector3) -> void:
	Zone.make(level, preset, center, size)

static func emit(level: Node3D, sounds: Array, pos: Vector3, every: Vector2, radius := 24.0, spread := Vector3.ZERO, cond := Callable()) -> Node3D:
	var e := Emitter.new()
	e.name = "AmbEmitter"
	e.sounds = sounds
	e.every = every
	e.radius = radius
	e.spread = spread
	e.cond = cond
	level.add_child(e)
	e.global_position = pos
	return e

static func fan(level: Node3D, pos: Vector3, db := -21.0) -> void:
	var n := Node3D.new()
	n.name = "ServerFan"
	level.add_child(n)
	n.global_position = pos
	var p := Sfx.attach_loop("amb_server_fan", n, db)
	if p != null:
		p.unit_size = 2.5
		p.max_distance = 18.0

# ---------------------------------------------------------------- L1 Highway 53 / substation
static func _l1(l: Node3D) -> void:
	zone(l, "room", Vector3(22.0, 1.5, -81.0), Vector3(10.0, 3.0, 10.0))        # control house
	zone(l, "room", Vector3(20.0, 1.35, -95.4), Vector3(6.2, 2.7, 2.4))         # storage container
	emit(l, RADIATOR, Vector3(18.0, 0.6, -84.5), Vector2(10, 22), 16.0)         # the operator's heater
	emit(l, METAL, Vector3(-5.9, 1.0, 14.0), Vector2(14, 28), 22.0)             # the truck settling in the ditch
	emit(l, WIND, Vector3(0.0, 3.0, 10.0), Vector2(10, 22), 45.0, Vector3(20, 2, 20))
	emit(l, WIND, Vector3(10.0, 3.0, -50.0), Vector2(12, 24), 45.0, Vector3(20, 2, 20))
	emit(l, WIND, Vector3(30.0, 3.0, -85.0), Vector2(12, 24), 45.0, Vector3(15, 2, 15))
	emit(l, HOWL, Vector3(70.0, 2.0, -40.0), Vector2(45, 90), 140.0)
	emit(l, CREAK, Vector3(20.0, 2.4, -95.4), Vector2(12, 26), 14.0)            # container walls in the cold

# ---------------------------------------------------------------- L2 school
static func _l2(l: Node3D) -> void:
	var FY := 0.45
	var YB := -3.05
	zone(l, "room", Vector3(0.0, FY + 2.1, -22.0), Vector3(44.0, 4.2, 24.0))     # ground floor (rear rooms, offices)
	zone(l, "hall", Vector3(0.0, FY + 2.1, -16.0), Vector3(14.0, 4.2, 12.0))     # main hall
	zone(l, "hall", Vector3(14.5, FY + 3.25, -22.0), Vector3(15.0, 6.5, 24.0))   # GYM (the shelter)
	zone(l, "corridor", Vector3(-7.5, FY + 2.1, -24.0), Vector3(29.0, 4.2, 4.0)) # back corridor
	zone(l, "basement", Vector3(0.0, YB + 1.6, -23.0), Vector3(44.0, 3.2, 22.0)) # basement, boiler, locker room
	var heat := func(): return Game.has_flag("boiler_on")
	var cold := func(): return not Game.has_flag("boiler_on")
	for p in [Vector3(-6.0, FY + 0.5, -11.0), Vector3(-2.0, FY + 0.5, -24.0), Vector3(-17.0, FY + 0.5, -30.0)]:
		emit(l, RADIATOR, p, Vector2(7, 16), 18.0, Vector3.ZERO, heat)      # steam knocking through the cold pipes
		emit(l, PIPE, p, Vector2(16, 32), 18.0, Vector3.ZERO, cold)         # pipes contracting before the boiler
	emit(l, RADIATOR, Vector3(-9.9, YB + 2.5, -24.5), Vector2(6, 12), 14.0, Vector3.ZERO, heat)
	emit(l, DRIP, Vector3(-8.0, YB + 2.9, -24.0), Vector2(2.5, 6), 16.0, Vector3(6, 0, 4))
	emit(l, DRIP, Vector3(13.0, YB + 2.9, -23.0), Vector2(3, 7), 16.0, Vector3(7, 0, 8))
	emit(l, ICE, Vector3(13.0, YB + 0.2, -23.0), Vector2(14, 30), 18.0, Vector3(6, 0, 8))
	emit(l, MOAN, Vector3(18.0, YB + 1.0, -31.0), Vector2(25, 50), 30.0)
	emit(l, WIND, Vector3(21.5, FY + 4.5, -22.0), Vector2(9, 18), 22.0, Vector3(0, 0, 9))   # broken gym windows
	emit(l, CREAK, Vector3(14.5, FY + 6.0, -22.0), Vector2(10, 22), 20.0, Vector3(6, 0, 9)) # gym roof under the snow load
	emit(l, CREAK, Vector3(-18.0, FY + 3.5, -14.0), Vector2(14, 28), 14.0)
	emit(l, HOWL, Vector3(-40.0, 2.0, 30.0), Vector2(45, 90), 120.0)
	emit(l, WIND, Vector3(0.0, 3.0, 8.0), Vector2(10, 20), 40.0, Vector3(20, 2, 12))

# ---------------------------------------------------------------- L3 Main Street / St. Brendan's
static func _l3(l: Node3D) -> void:
	var rooms = l.get("_rooms")
	if rooms is Array:
		for r in rooms:
			var rc: Rect2 = r[0]
			var church: bool = r[1] == "church"
			var h := 12.0 if church else 6.0
			zone(l, "church" if church else "room", Vector3(rc.get_center().x, h * 0.5, rc.get_center().y), Vector3(rc.size.x, h, rc.size.y))
			if church:
				emit(l, CREAK, Vector3(rc.get_center().x, 8.0, rc.get_center().y), Vector2(9, 20), 26.0, Vector3(5, 1, 12))
				emit(l, WIND, Vector3(rc.position.x + 0.5, 3.5, rc.get_center().y), Vector2(10, 20), 24.0, Vector3(0, 0, 10))
				emit(l, WIND, Vector3(rc.end.x - 0.5, 3.5, rc.get_center().y), Vector2(12, 24), 24.0, Vector3(0, 0, 10))
			else:
				emit(l, CREAK, Vector3(rc.get_center().x, 2.8, rc.get_center().y), Vector2(14, 28), 12.0, Vector3(3, 0, 3))
	emit(l, MOAN, Vector3(-20.0, 1.0, -22.0), Vector2(30, 60), 50.0, Vector3(30, 0, 4))
	emit(l, HOWL, Vector3(20.0, 2.0, 40.0), Vector2(45, 90), 140.0)
	emit(l, WIND, Vector3(-40.0, 3.0, 0.0), Vector2(10, 20), 40.0, Vector3(25, 2, 6))
	emit(l, WIND, Vector3(30.0, 3.0, 0.0), Vector2(10, 20), 40.0, Vector3(25, 2, 6))

# ---------------------------------------------------------------- L4 MERIDIAN data centre
static func _l4(l: Node3D) -> void:
	zone(l, "datacenter", Vector3(8.0, 4.75, -43.0), Vector3(84.0, 9.5, 110.0))  # whole building
	zone(l, "hall", Vector3(0.0, 2.25, 3.0), Vector3(16.0, 4.5, 18.0))           # glass lobby
	zone(l, "datacenter", Vector3(0.0, 2.25, -21.0), Vector3(32.0, 4.5, 30.0))   # Hall A
	zone(l, "room", Vector3(-23.0, 2.25, -22.0), Vector3(14.0, 4.5, 20.0))       # electrical room
	zone(l, "datacenter", Vector3(0.0, 2.25, -48.0), Vector3(32.0, 4.5, 24.0))   # Hall C
	zone(l, "hall", Vector3(33.0, 2.25, -48.0), Vector3(34.0, 4.5, 24.0))        # cooling plant
	zone(l, "room", Vector3(42.0, 2.25, -29.0), Vector3(16.0, 4.5, 14.0))        # armory
	zone(l, "corridor", Vector3(10.0, 2.25, -63.0), Vector3(80.0, 4.5, 6.0))     # corridor
	zone(l, "room", Vector3(-6.0, 2.25, -75.0), Vector3(16.0, 4.5, 18.0))        # NOC
	zone(l, "room", Vector3(-22.0, 2.25, -73.0), Vector3(16.0, 4.5, 14.0))       # break room
	zone(l, "hall", Vector3(18.0, 4.25, -82.0), Vector3(24.0, 8.5, 32.0))        # pipeline hall
	for x in [-10.0, 0.0, 10.0]:
		fan(l, Vector3(x, 1.4, -16.0))
		fan(l, Vector3(x, 1.4, -28.0))
		fan(l, Vector3(x, 1.4, -48.0))
	fan(l, Vector3(-23.0, 1.2, -22.0), -24.0)
	emit(l, PIPE, Vector3(33.0, 3.0, -48.0), Vector2(9, 20), 22.0, Vector3(12, 1, 8))
	emit(l, RADIATOR, Vector3(33.0, 2.0, -48.0), Vector2(12, 26), 22.0, Vector3(12, 1, 8))
	emit(l, DRIP, Vector3(18.0, 7.5, -82.0), Vector2(3, 7), 18.0, Vector3(9, 0, 12))
	emit(l, PIPE, Vector3(18.0, 4.0, -90.0), Vector2(10, 22), 22.0, Vector3(6, 2, 6))
	emit(l, MOAN, Vector3(18.0, 0.5, -96.0), Vector2(30, 60), 30.0)
	emit(l, WIND, Vector3(0.0, 3.0, 50.0), Vector2(9, 18), 45.0, Vector3(25, 2, 12))
	emit(l, CREAK, Vector3(6.0, 2.2, 44.0), Vector2(14, 28), 12.0)               # guard booth

# ---------------------------------------------------------------- L5 Lower Kettle mine
static func _l5(l: Node3D) -> void:
	var LY := -30.0
	zone(l, "hall", Vector3(37.0, 5.0, 0.0), Vector3(22.0, 10.0, 20.0))          # hoist hall
	zone(l, "room", Vector3(37.0, 1.6, -14.5), Vector3(12.0, 3.2, 9.0))          # lamp room (safe room)
	zone(l, "basement", Vector3(10.0, 1.7, -25.0), Vector3(20.0, 3.4, 14.0))     # pump station
	zone(l, "cavern", Vector3(102.0, LY + 7.0, 0.0), Vector3(36.0, 14.0, 34.0))  # haulage cavern
	zone(l, "room", Vector3(110.0, LY + 1.7, -30.0), Vector3(8.0, 3.4, 8.0))     # refuge chamber
	emit(l, DRIP, Vector3(13.0, 2.6, 0.0), Vector2(2.5, 6), 18.0, Vector3(11, 0, 1))
	emit(l, DRIP, Vector3(9.0, 2.6, -25.0), Vector2(3, 7), 16.0, Vector3(8, 0, 5))
	emit(l, DRIP, Vector3(18.0, 2.6, 23.0), Vector2(3, 7), 16.0, Vector3(9, 0, 5))
	emit(l, DRIP, Vector3(76.0, LY + 2.6, 0.0), Vector2(2.5, 6), 16.0, Vector3(8, 0, 1))
	emit(l, DRIP, Vector3(102.0, LY + 6.0, 0.0), Vector2(1.5, 4), 26.0, Vector3(14, 0, 12))
	emit(l, CREAK, Vector3(13.0, 2.6, 0.0), Vector2(10, 22), 18.0, Vector3(10, 0, 1))   # timber sets taking the load
	emit(l, CREAK, Vector3(18.0, 2.6, 23.0), Vector2(8, 18), 16.0, Vector3(9, 0, 5))
	emit(l, CREAK, Vector3(76.0, LY + 2.6, 0.0), Vector2(10, 22), 16.0, Vector3(8, 0, 1))
	emit(l, METAL, Vector3(37.0, 8.0, 0.0), Vector2(12, 26), 20.0, Vector3(8, 1, 8))     # headframe / cage cables
	emit(l, PIPE, Vector3(13.0, 2.4, 0.4), Vector2(14, 30), 18.0, Vector3(11, 0, 0))     # the warm pipeline itself
	emit(l, MOAN, Vector3(100.0, LY + 1.0, 0.0), Vector2(22, 45), 45.0, Vector3(14, 0, 12))
	emit(l, MOAN, Vector3(10.0, 1.0, -28.0), Vector2(30, 60), 30.0)
	emit(l, ICE, Vector3(102.0, LY + 3.0, 0.0), Vector2(12, 26), 30.0, Vector3(14, 2, 12))

# ---------------------------------------------------------------- L6 the Heart (brine cavern)
static func _l6(l: Node3D) -> void:
	zone(l, "room", Vector3(10.0, 1.5, 32.0), Vector3(5.0, 3.0, 7.0))            # save nook
	zone(l, "mine", Vector3(0.0, 2.5, 60.0), Vector3(12.0, 5.0, 10.0))           # mine mouth
	emit(l, DRIP, Vector3(0.0, 6.0, 42.0), Vector2(1.5, 4), 22.0, Vector3(8, 1, 12))
	emit(l, DRIP, Vector3(0.0, 9.0, -4.0), Vector2(1.2, 3.5), 34.0, Vector3(18, 2, 18))
	emit(l, ICE, Vector3(-12.0, 1.0, 10.0), Vector2(10, 22), 40.0, Vector3(8, 1, 20))     # frozen lake edge
	emit(l, MOAN, Vector3(0.0, 4.0, -20.0), Vector2(20, 40), 60.0, Vector3(18, 2, 8))
	emit(l, PIPE, Vector3(14.0, 4.0, -10.0), Vector2(12, 26), 40.0, Vector3(3, 2, 10))    # pipeline breach, east wall
