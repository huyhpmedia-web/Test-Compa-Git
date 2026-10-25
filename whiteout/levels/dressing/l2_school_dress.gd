extends RefCounted
## L2 - Kettle Falls Consolidated School. The warming shelter was overrun in the night: the gym
## is a slaughterhouse of cots, drag trails run toward the dark behind the stage, the front doors
## show where the last stand was; the basement locker room has blood frozen under the ice.
## Layout notes: FY = 0.45 ground floor, YB = -3.05 basement, stage top = FY + 1.0.

const D = preload("res://levels/dressing/dress_util.gd")
const Gore = preload("res://world/gore.gd")
const Props = preload("res://world/props.gd")

const FY := 0.45
const YB := -3.05

static func dress(level: Node3D) -> void:
	D.begin(level)
	_gym()
	_stage()
	_hall()
	_basement()
	_corridor_rooms()
	_west_wing()
	_courtyard()

# ---- gym: cots at x {12.2, 13.2, 17.4, 18.4}, z rows -14.2 ... -27.2; aisle x 14..16.8
static func _cot_blood(x: float, z: float, big := true) -> void:
	# decal volume (y FY+0.5 +-0.25) catches the canvas / blanket top of the cot
	if not D._ok(2):
		return
	Gore.decal(D.lv, "pool_b" if big else "splat_a", Vector3(x, FY + 0.5, z + D.rf(-0.15, 0.15)), Vector3.UP, 1.25 if big else 0.9, Vector3.RIGHT, {"local": true, "depth": 0.5, "roll": D.rf(0, TAU)})
	Gore.decal(D.lv, "splat_c", Vector3(x + D.rf(-0.2, 0.2), FY + 0.5, z + D.rf(-0.6, 0.6)), Vector3.UP, 0.6, Vector3.RIGHT, {"local": true, "depth": 0.5, "roll": D.rf(0, TAU)})
	# it ran off the side onto the floor
	var side := -1.0 if x < 15.0 else 1.0
	D.pool(Vector3(x + side * 0.7, FY + 0.01, z + D.rf(-0.3, 0.3)), D.rf(0.9, 1.4))

static func _gym() -> void:
	# blood-soaked cots (the covered / empty ones - the occupied cots hold the Sleepers)
	for c in [Vector2(12.2, -14.2), Vector2(13.2, -16.8), Vector2(12.2, -22.0), Vector2(13.2, -19.4), Vector2(12.2, -27.2),
			Vector2(17.4, -14.2), Vector2(18.4, -16.8), Vector2(18.4, -19.4), Vector2(17.4, -24.6), Vector2(18.4, -27.2), Vector2(13.2, -22.0)]:
		_cot_blood(c.x, c.y, true)
	# the dragging: from the cots, along the aisle, toward the stage and the dark behind the curtains
	D.drag(Vector3(13.4, FY + 0.01, -15.6), Vector3(14.6, FY + 0.01, -29.2), 0.2, 0.0)
	D.drag(Vector3(16.6, FY + 0.01, -19.8), Vector3(15.6, FY + 0.01, -29.3), 0.2, 0.0)
	D.drag(Vector3(18.6, FY + 0.01, -25.0), Vector3(16.8, FY + 0.01, -29.3), 0.2, 0.0)
	D.drag(Vector3(19.6, FY + 0.01, -14.0), Vector3(19.6, FY + 0.01, -23.5), 0.0, 1.1)
	D.splat(Vector3(14.8, FY + 0.01, -20.5), 1.5)
	D.splat(Vector3(15.8, FY + 0.01, -24.0), 1.3)
	D.pool(Vector3(15.2, FY + 0.01, -17.5), 2.1)
	D.spray(Vector3(15.4, FY + 0.01, -22.0), Vector3.UP, Vector3(0.1, 0, -1), 1.8)
	# dead shelter folk who did not make it to a cot: east side + aisle foot
	Props.corpse(D.lv, Vector3(20.2, FY, -24.8), 2.3, {"shirt": Color(0.25, 0.3, 0.2), "bloody": 1.0})
	D.n += 1
	Props.torso(D.lv, Vector3(19.4, FY, -27.6), 0.7)
	D.n += 3
	Props.severed_limb(D.lv, Vector3(16.1, FY, -26.6), 1.3, "arm")
	D.n += 2
	Props.severed_limb(D.lv, Vector3(14.4, FY, -13.6), -0.5, "leg")
	D.n += 2
	Props.gut_pile(D.lv, Vector3(15.3, FY, -28.4), 0.4, 1.0)
	D.n += 2
	Props.body_bag(D.lv, Vector3(20.8, FY, -12.3), 0.0, false, true)
	D.n += 3
	Props.body_bag(D.lv, Vector3(19.7, FY, -12.2), 0.05, true, true)
	D.n += 3
	# the west wall by the sign-in table (path to the stairs): a dragged person's smear
	D.spray(Vector3(7.14, 1.2, -27.3), Vector3(1, 0, 0), Vector3(0, 0, 1), 1.5)
	D.hands(Vector3(7.14, 0.9, -24.8), Vector3(7.14, 1.2, -26.5), Vector3(1, 0, 0), 3, 0.22)
	D.drips(Vector3(7.14, 1.6, -28.2), Vector3(1, 0, 0), 0.8)
	# east wall bleachers side & hoop wall
	D.wall_splat(Vector3(21.9, 1.6, -22.5), Vector3(-1, 0, 0), 1.2, Vector3(0, 0, -1))
	D.spray(Vector3(21.94, 1.3, -23.5), Vector3(-1, 0, 0), Vector3(0, 0, -1), 1.6)

# ---- stage and the dark behind it
static func _stage() -> void:
	var n := Vector3(0, 0, 1)
	for x in [10.0, 12.5, 15.0, 17.2, 19.4]:
		D.drips(Vector3(x + D.rf(-0.3, 0.3), FY + 1.0, -29.49), n, D.rf(0.6, 1.0))
	D.hands(Vector3(11.0, FY + 0.8, -29.49), Vector3(18.5, FY + 0.5, -29.49), n, 5, 0.22)
	D.smear(Vector3(15.0, FY + 0.5, -29.49), n, Vector3(0, -1, 0), 2.2)
	D.pool(Vector3(14.8, FY + 1.01, -30.6), 2.6)
	D.pool(Vector3(11.0, FY + 1.01, -31.8), 1.8)
	D.drag(Vector3(16.0, FY + 1.01, -30.0), Vector3(13.0, FY + 1.01, -33.2), 0.3, 0.0)
	# the covered bodies on the stage (17..20, z=-33): blood soaked through the blankets
	for i in 3:
		Gore.decal(D.lv, "splat_a", Vector3(17.0 + i * 1.5, FY + 1.0 + 0.35, -33.0), Vector3.UP, 0.9, Vector3.RIGHT, {"local": true, "depth": 0.5, "roll": D.rf(0, TAU)})
		D.n += 1
	# the black curtain: wipes at head height, one long writing
	D.write("help", Vector3(14.5, FY + 3.0, -33.78), Vector3(0, 0, 1), 3.2)

# ---- main hall: the last stand at the double doors (x=0, z=-10), a blood path to the gym
static func _hall() -> void:
	D.pool(Vector3(-1.4, FY + 0.01, -11.6), 2.4)
	D.pool(Vector3(1.6, FY + 0.01, -11.9), 1.9)
	D.drag(Vector3(0.0, FY + 0.01, -12.5), Vector3(6.0, FY + 0.01, -17.3), 0.0, 0.0)
	D.drag(Vector3(-2.5, FY + 0.01, -13.0), Vector3(-1.0, FY + 0.01, -21.2), 0.2, 0.0)
	D.hands(Vector3(-1.2, 0.8, -10.14), Vector3(1.4, 1.7, -10.14), Vector3(0, 0, -1), 4, 0.22)
	D.drips(Vector3(0.9, 1.9, -10.14), Vector3(0, 0, -1), 0.9)
	Props.corpse(D.lv, Vector3(-2.2, FY, -12.6), 0.4, {"shirt": Color(0.4, 0.2, 0.2), "bloody": 1.0})
	D.n += 1
	Props.corpse(D.lv, Vector3(2.3, FY, -13.3), -2.4, {"shirt": Color(0.2, 0.3, 0.35), "bloody": 1.0})
	D.n += 1
	D.spray(Vector3(-5.3, 1.3, -14.0), Vector3(-1, 0, 0), Vector3(0, 0, 1), 1.5)   # overhead spray on the hall's west pier? (decal on wall plane)
	D.steps(Vector3(0.4, FY + 0.01, -10.8), Vector3(-0.2, FY + 0.01, -20.8), 1.0, false)
	D.steps(Vector3(1.2, FY + 0.01, -11.4), Vector3(4.6, FY + 0.01, -17.6), 1.0, true)
	D.write("run", Vector3(5.0, 1.0, -21.78), Vector3(0, 0, 1), 1.0)

# ---- west wing: lobby lockers and Ruth's office (subtle)
static func _west_wing() -> void:
	D.hands(Vector3(-14.1, 1.0, -12.0), Vector3(-14.1, 1.5, -13.3), Vector3(1, 0, 0), 3, 0.2)
	D.pool(Vector3(-19.0, FY + 0.01, -17.8), 1.8)
	D.drag(Vector3(-17.5, FY + 0.01, -17.0), Vector3(-21.0, FY + 0.01, -14.5), 0.0, 0.0)
	D.splat(Vector3(-16.4, FY + 0.01, -13.0), 1.0)
	Props.corpse(D.lv, Vector3(-20.5, FY, -19.5), 1.0, {"shirt": Color(0.3, 0.22, 0.12), "bloody": 1.0})
	D.n += 1
	# Ruth's office: a few drops on the floor leading out, a smear on the whiteboard
	D.droplets(Vector3(-10.0, FY + 0.01, -15.0), Vector3(-8.0, FY + 0.01, -12.0), 4, 0.22)
	D.smear(Vector3(-13.83, 1.5, -15.7), Vector3(1, 0, 0), Vector3(0, 0, 1), 1.0)

# ---- corridor + rear rooms: nurse's office is where the wounded were brought
static func _corridor_rooms() -> void:
	D.drag(Vector3(-4.0, FY + 0.01, -23.8), Vector3(-17.0, FY + 0.01, -24.2), 0.2, 1.3)
	D.hands(Vector3(-11.0, 1.1, -22.15), Vector3(-8.0, 1.0, -22.15), Vector3(0, 0, 1), 3, 0.2)
	# nurse: beds soaked, floor pools
	for bx in [-3.6, -0.2]:
		Gore.decal(D.lv, "pool_b", Vector3(bx, FY + 0.7, -31.8), Vector3.UP, 1.1, Vector3.RIGHT, {"local": true, "depth": 0.6, "roll": D.rf(0, TAU)})
		D.n += 1
		D.pool(Vector3(bx + 0.8, FY + 0.01, -31.4), 1.2)
	D.drips(Vector3(-2.0, 1.6, -33.84), Vector3(0, 0, 1), 0.8)
	Props.corpse(D.lv, Vector3(-1.9, FY, -29.0), 2.2, {"shirt": Color(0.22, 0.45, 0.47), "bloody": 1.0})
	D.n += 1
	# coach's office: cot
	Gore.decal(D.lv, "splat_b", Vector3(5.2, FY + 0.6, -29.0), Vector3.UP, 1.0, Vector3.RIGHT, {"local": true, "depth": 0.6})
	D.n += 1
	D.pool(Vector3(4.2, FY + 0.01, -29.9), 1.2)
	# classroom 2B: a lone smear under the chalkboard
	D.droplets(Vector3(-13.0, FY + 0.01, -28.0), Vector3(-15.5, FY + 0.01, -33.0), 4, 0.22)

# ---- courtyard: drag marks across the snow, a feeding site by the shed, the broken west wall
static func _courtyard() -> void:
	D.drag(Vector3(-2.2, 0.03, 11.0), Vector3(-25.0, 0.03, 11.0), 0.0, 2.4)      # dragged through the collapsed wall
	D.pool(Vector3(-2.2, 0.03, 11.0), 2.2)
	D.pool(Vector3(13.0, 0.03, 3.0), 2.0)
	D.drag(Vector3(13.0, 0.03, 3.0), Vector3(16.6, 0.03, -4.4), 0.1, 0.0)
	D.steps(Vector3(2.0, 0.03, 20.0), Vector3(3.5, 0.03, 5.0), 1.0, false)
	D.droplets(Vector3(1.5, 0.03, 21.0), Vector3(3.8, 0.03, 4.0), 8, 0.26)
	# shed door and walls
	D.hands(Vector3(15.4, 1.2, -3.0), Vector3(15.0, 1.5, -3.6), Vector3(0, 0, 1), 2, 0.22)
	D.wall_splat(Vector3(21.6, 1.2, 16.5), Vector3(0, 0, -1), 1.2, Vector3(1, 0, 0))
	D.pool(Vector3(-0.4, 0.03, 18.8), 1.7)
	D.splat(Vector3(-5.6, 0.03, 16.2), 1.1)
	# staff van: someone died in the front seat
	D.pool(Vector3(-17.2, 0.03, 15.0), 1.6)
	D.hands(Vector3(-19.3, 0.9, 14.8), Vector3(-19.3, 1.1, 14.2), Vector3(-1, 0, 0), 2, 0.2)

# ---- basement: blood frozen under the ice in the locker room, a cut-off scream by the boiler
static func _basement() -> void:
	var frozen := {"local": true, "depth": 0.5, "color": Color(0.85, 0.6, 0.65)}
	for p in [Vector3(10.5, YB, -29.5), Vector3(14.0, YB, -23.0), Vector3(18.0, YB, -17.5), Vector3(8.0, YB, -22.0)]:
		if D._ok():
			var o := frozen.duplicate()
			o["roll"] = D.rf(0, TAU)
			Gore.decal(D.lv, Gore.POOL[D.rng.randi() % 3], p, Vector3.UP, D.rf(2.4, 3.4), Vector3.RIGHT, o)
	D.drag(Vector3(8.0, YB, -33.0), Vector3(14.5, YB, -26.0), 0.0, 0.0)
	D.hands(Vector3(5.1, YB + 1.2, -26.0), Vector3(5.1, YB + 1.6, -27.0), Vector3(1, 0, 0), 2, 0.22)
	# the stair foot: a smear down the stairs and into the passage
	D.drag(Vector3(-20.0, YB, -31.5), Vector3(-9.0, YB, -32.2), 0.0, 1.3)
	D.hands(Vector3(-21.86, YB + 1.0, -32.0), Vector3(-21.86, YB + 1.4, -33.0), Vector3(1, 0, 0), 2, 0.2)
	D.pool(Vector3(-7.0, YB, -32.2), 1.4)
