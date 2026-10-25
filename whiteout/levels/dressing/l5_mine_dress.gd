extends RefCounted
## L5 - Lower Kettle Mine. The Rime does not kill neatly. The pipeline tunnel is warm and wet
## (melt drips, steam); miners are frozen into the walls with their blood frozen under them; the
## Foreman's hall has crystal spikes with bodies on them; the pump station is a butchery on meat
## hooks; the old 2011 collapse carries long-dried stains; the haulage tunnel shows the Hauler's
## drag marks; the cavern floor is plated with blood frozen under ice and bodies hang above it.
## Upper level y = 0; lower level y = LY = -30.

const D = preload("res://levels/dressing/dress_util.gd")
const Gore = preload("res://world/gore.gd")
const Props = preload("res://world/props.gd")

const LY := -30.0

static func dress(level: Node3D) -> void:
	D.begin(level)
	_cavern()
	_tunnel()
	_hoist_hall()
	_pump_station()
	_haulage()
	_lower()
	_drift()
	_refuge()

static func _frozen(p: Vector3, size: float) -> void:
	if D._ok():
		Gore.frozen_blood(D.lv, p + Vector3(0, 0.0, 0), size, {"local": true})

static func _tunnel() -> void:
	# the heat loop sweats: melt drips off the warm casing and steam at the flanges
	Gore.drip_emitter(D.lv, Vector3(6.0, 2.9, -0.8), "melt", 1.3)
	Gore.drip_emitter(D.lv, Vector3(19.0, 2.9, -0.8), "melt", 1.7)
	Gore.steam_vent(D.lv, Vector3(14.0, 2.3, -1.15), Vector3(0, 0.3, 1), 0.8, 0.12)
	D.puddle(Vector3(6.0, 0.03, -0.4), 1.4)
	D.puddle(Vector3(19.0, 0.03, -0.3), 1.2)
	# miners frozen into the wall: blood frozen under them, hands that clawed at the rock
	_frozen(Vector3(7.8, 0.02, 1.0), 2.2)
	_frozen(Vector3(15.5, 0.02, -1.0), 2.2)
	D.hands(Vector3(6.0, 1.0, 1.78), Vector3(10.0, 1.4, 1.78), Vector3(0, 0, -1), 4, 0.2)
	D.hands(Vector3(14.0, 1.0, -1.78), Vector3(18.0, 1.5, -1.78), Vector3(0, 0, 1), 4, 0.2)
	D.drag(Vector3(24.0, 0.03, 0.2), Vector3(9.5, 0.03, -0.6), 0.5, 0.0)
	D.spray(Vector3(3.0, 1.2, -1.78), Vector3(0, 0, 1), Vector3(1, 0, 0), 1.6, true)
	D.splat(Vector3(21.0, 0.03, 0.5), 1.1, true)

static func _hoist_hall() -> void:
	# the Foreman's larder: spikes of crystal growing out of the concrete with bodies on them
	Props.crystal_impale(D.lv, Vector3(44.5, 0.0, -7.2), 0.5, 2.6)
	D.n += 3
	Props.crystal_impale(D.lv, Vector3(46.2, 0.0, 6.4), 3.2, 2.2)
	D.n += 3
	Props.crystal_impale(D.lv, Vector3(29.5, 0.0, 7.4), 1.0, 2.0)
	D.n += 3
	D.pool(Vector3(41.0, 0.02, 4.0), 2.8)
	D.drag(Vector3(30.0, 0.02, 1.0), Vector3(36.0, 0.02, 5.0), 0.5, 0.0)
	D.drag(Vector3(45.0, 0.02, -2.0), Vector3(42.0, 0.02, 4.0), 0.5, 0.0)
	D.pool(Vector3(31.5, 0.02, -6.0), 2.0, true)
	D.splat(Vector3(35.0, 0.02, -4.5), 1.4)
	D.spray(Vector3(47.84, 1.5, 2.0), Vector3(-1, 0, 0), Vector3(0, 0, -1), 1.8)
	D.hands(Vector3(47.85, 0.9, -3.0), Vector3(47.85, 1.4, -4.5), Vector3(-1, 0, 0), 3, 0.2)
	D.write("run", Vector3(37.0, 2.2, 9.84), Vector3(0, 0, -1), 1.6)
	D.drips(Vector3(36.0, 3.0, -9.84), Vector3(0, 0, 1), 1.0)

static func _pump_station() -> void:
	# the pump crew: butchered on hooks over the brine, intestines on the grating
	Props.meat_hook(D.lv, Vector3(3.2, 0.0, -21.8), 0.0, true, 4.6)
	D.n += 5
	Props.meat_hook(D.lv, Vector3(16.8, 0.0, -21.8), 0.0, true, 4.6)
	D.n += 5
	Props.gut_pile(D.lv, Vector3(9.6, 0.0, -24.5), 0.8, 1.2)
	D.n += 2
	Props.torso(D.lv, Vector3(12.5, 0.0, -30.0), 2.4, Color(0.34, 0.13, 0.1))
	D.n += 3
	D.pool(Vector3(10.0, 0.02, -28.0), 3.0)
	D.pool(Vector3(5.0, 0.02, -28.5), 2.0, true)
	D.drag(Vector3(9.0, 0.02, -3.0), Vector3(9.0, 0.02, -17.0), 0.4, 1.0)
	D.hands(Vector3(7.86, 1.0, -8.0), Vector3(7.86, 1.4, -10.0), Vector3(1, 0, 0), 3, 0.2)
	D.puddle(Vector3(11.0, 0.03, -20.0), 1.6)
	D.puddle(Vector3(4.0, 0.03, -26.0), 1.4)
	Gore.drip_emitter(D.lv, Vector3(14.0, 4.6, -26.0), "water", 1.2)
	Gore.steam_vent(D.lv, Vector3(18.5, 0.4, -26.0), Vector3.UP, 0.8, 0.12)
	D.write("help", Vector3(10.0, 1.8, -31.86), Vector3(0, 0, 1), 1.8)
	D.spray(Vector3(0.14, 1.3, -26.0), Vector3(1, 0, 0), Vector3(0, 0, -1), 1.7)

static func _drift() -> void:
	# 2011: old, dry, brown stains by the rock fall and the memorial; one fresh one
	D.old_pool(Vector3(19.0, 0.02, 21.5), 2.4)
	D.old_pool(Vector3(15.7, 0.02, 8.0), 1.8)
	D.old_pool(Vector3(20.0, 0.02, 25.0), 2.0)
	D.hands(Vector3(14.14, 1.0, 21.0), Vector3(14.14, 1.4, 23.0), Vector3(1, 0, 0), 2, 0.2)
	D.pool(Vector3(12.0, 0.02, 27.0), 1.4)
	D.droplets(Vector3(17.0, 0.02, 5.0), Vector3(12.0, 0.02, 26.0), 6, 0.22)

static func _lower() -> void:
	# lower cage landing: the cage came down full
	_frozen(Vector3(60.0, LY + 0.02, 0.0), 3.2)
	D.pool(Vector3(64.0, LY + 0.02, 2.5), 2.0)
	D.drag(Vector3(60.0, LY + 0.03, 0.0), Vector3(67.5, LY + 0.03, 0.4), 0.2, 0.0)
	D.hands(Vector3(56.14, LY + 1.0, 2.0), Vector3(56.14, LY + 1.5, 3.5), Vector3(1, 0, 0), 3, 0.2)
	D.spray(Vector3(61.0, LY + 1.4, -5.84), Vector3(0, 0, 1), Vector3(1, 0, 0), 1.6)

static func _haulage() -> void:
	# the Hauler drags its catch down the rails to the cavern: one long smear
	D.drag(Vector3(69.5, LY + 0.03, 0.2), Vector3(83.5, LY + 0.03, -0.1), 0.4, 1.5)
	D.drag(Vector3(70.0, LY + 0.03, -0.9), Vector3(83.0, LY + 0.03, -0.7), 0.4, 0.0)
	_frozen(Vector3(70.5, LY + 0.02, -1.2), 2.0)
	_frozen(Vector3(81.0, LY + 0.02, 1.2), 2.0)
	D.hands(Vector3(72.0, LY + 1.0, 1.78), Vector3(76.0, LY + 1.6, 1.78), Vector3(0, 0, -1), 4, 0.2)
	D.hands(Vector3(78.0, LY + 1.0, -1.78), Vector3(82.0, LY + 1.5, -1.78), Vector3(0, 0, 1), 4, 0.2)
	D.drips(Vector3(74.0, LY + 2.8, -1.78), Vector3(0, 0, 1), 1.0, true)
	D.pool(Vector3(76.0, LY + 0.03, 3.0), 1.6)
	D.write("sleep", Vector3(76.0, LY + 2.3, 11.86), Vector3(0, 0, -1), 2.0)

static func _cavern() -> void:
	# floor plated in frozen blood: big slabs under the ice near the rime mass
	for p in [Vector3(104.0, LY, -12.0), Vector3(110.0, LY, -14.0), Vector3(96.0, LY, -8.0), Vector3(116.0, LY, 4.0), Vector3(92.0, LY, 8.0), Vector3(100.0, LY, 12.0)]:
		_frozen(p + Vector3(0, 0.02, 0), D.rf(3.0, 4.4))
	D.pool(Vector3(110.0, LY + 0.02, 0.0), 4.0)
	D.pool(Vector3(100.0, LY + 0.02, -3.0), 3.0, true)
	D.pool(Vector3(113.0, LY + 0.02, 6.5), 3.2)
	D.splat(Vector3(94.0, LY + 0.02, 0.0), 1.6)
	D.drag(Vector3(86.0, LY + 0.02, 0.0), Vector3(112.0, LY + 0.02, 4.0), 0.4, 0.0)
	# hanging bodies: bound by cables from the 12 m roof, blood falling to the floor
	Props.hanging_body(D.lv, Vector3(92.0, LY + 7.5, -9.0), 0.4, 4.0, LY)
	D.n += 4
	Props.hanging_body(D.lv, Vector3(98.0, LY + 7.0, 6.0), 2.1, 4.5, LY)
	D.n += 4
	Props.hanging_body(D.lv, Vector3(106.0, LY + 7.8, 9.0), 1.3, 3.7, LY)
	D.n += 4
	Props.hanging_body(D.lv, Vector3(103.0, LY + 7.2, -10.0), 4.0, 4.2, LY)
	D.n += 4
	Props.hanging_body(D.lv, Vector3(116.0, LY + 7.6, -6.0), 0.9, 3.8, LY)
	D.n += 4
	D.hands(Vector3(84.14, LY + 1.0, 6.0), Vector3(84.14, LY + 1.5, 9.0), Vector3(1, 0, 0), 3, 0.2)
	D.spray(Vector3(119.84, LY + 1.6, 3.0), Vector3(-1, 0, 0), Vector3(0, 0, -1), 2.0)
	D.spray(Vector3(100.0, LY + 1.6, 17.84), Vector3(0, 0, -1), Vector3(1, 0, 0), 2.0, true)
	Gore.steam_vent(D.lv, Vector3(112.0, LY + 0.3, 10.0), Vector3.UP, 1.1, 0.12)

static func _refuge() -> void:
	# the refuge: dried stains, four of six survived, two bagged by the door
	Props.body_bag(D.lv, Vector3(114.9, LY, -28.9), 0.1, false, false)
	D.n += 1
	Props.body_bag(D.lv, Vector3(114.9, LY, -27.7), 0.0, false, false)
	D.n += 1
	D.old_pool(Vector3(106.5, LY + 0.02, -29.5), 1.8)
	D.old_pool(Vector3(112.0, LY + 0.02, -27.2), 1.4)
	D.hands(Vector3(103.86, LY + 1.0, -29.0), Vector3(103.86, LY + 1.4, -30.0), Vector3(1, 0, 0), 2, 0.2)
	D.hands(Vector3(109.2, LY + 1.0, -26.14), Vector3(110.8, LY + 1.5, -26.14), Vector3(0, 0, 1), 3, 0.2)
