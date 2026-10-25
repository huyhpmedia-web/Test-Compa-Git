extends RefCounted
## L3 - Main Street / St. Brendan's. The town tried to reach the church. Bloody tracks run east
## along the street, bodies froze at the sealed doors, the pharmacy was a triage ward, the diner was
## a feeding ground, and the nave is a shrine of blood around the altar where the Choir stands.
## Street y = 0.02; church floor y = 0.04.

const D = preload("res://levels/dressing/dress_util.gd")
const Gore = preload("res://world/gore.gd")
const Props = preload("res://world/props.gd")

static func dress(level: Node3D) -> void:
	D.begin(level)
	_nave()
	_chancel()
	_church_front()
	_narthex()
	_pharmacy()
	_diner()
	_square()
	_street()

static func _street() -> void:
	# arrival roadblock: the jack-knifed truck, its driver pulled out through the windshield
	D.pool(Vector3(-73.4, 0.03, 1.4), 2.4)
	D.drag(Vector3(-73.4, 0.03, 1.4), Vector3(-66.0, 0.03, 3.2), 0.1, 0.0)
	D.splat(Vector3(-72.0, 0.03, -3.0), 1.2)
	# bleeding people walking east to the church, resting at each fire barrel
	D.droplets(Vector3(-66.0, 0.03, 3.0), Vector3(-30.0, 0.03, 2.0), 12, 0.3)
	D.steps(Vector3(-60.0, 0.03, 0.5), Vector3(-48.0, 0.03, -0.5), 1.0, false)
	D.pool(Vector3(-27.5, 0.03, -0.2), 1.8)
	D.droplets(Vector3(-27.0, 0.03, -0.5), Vector3(-9.0, 0.03, 1.0), 9, 0.3)
	D.pool(Vector3(6.0, 0.03, 0.8), 1.7)
	D.droplets(Vector3(6.5, 0.03, 0.3), Vector3(34.0, 0.03, -2.0), 11, 0.3)
	D.steps(Vector3(20.0, 0.03, -1.0), Vector3(33.0, 0.03, -2.4), 1.0, false)
	# police cruiser: the officer died holding the door
	D.pool(Vector3(-30.0, 0.03, -2.2), 1.9)
	D.hands(Vector3(-30.9, 0.95, -5.3), Vector3(-30.2, 0.8, -5.3), Vector3(0, 0, 1), 2, 0.22)
	D.spray(Vector3(-28.0, 0.03, -2.4), Vector3.UP, Vector3(1, 0, 0.4), 1.8)
	# the snowplow: operator dragged from the cab toward the diner
	D.pool(Vector3(-10.5, 0.03, 2.4), 2.2)
	D.drag(Vector3(-10.5, 0.03, 2.4), Vector3(-20.5, 0.03, -4.2), 0.2, 0.0)
	# ambulance by the square: body bags and a bloody trail from its back doors
	var amb := Vector3(18.0, 0.0, -4.2)
	D.pool(amb + Vector3(0, 0.03, 3.2), 2.0)
	Props.body_bag(D.lv, Vector3(13.4, 0.03, -3.6), 0.2, false, true)
	D.n += 3
	Props.body_bag(D.lv, Vector3(12.4, 0.03, -3.9), -0.1, true, true)
	D.n += 3
	Props.body_bag(D.lv, Vector3(14.6, 0.03, -3.4), 0.15, false, true)
	D.n += 3
	D.drag(amb + Vector3(0, 0.03, 2.6), Vector3(14.0, 0.03, -2.5), 0.0, 0.0)
	Props.severed_limb(D.lv, Vector3(10.5, 0.03, -2.2), 0.8, "arm")
	D.n += 2
	# cars: windshield blood on a couple of wrecks
	Props.glass_blood(D.lv, Vector3(-61.9, 1.45, 3.15), PI, "splat", 0.9)
	Props.glass_blood(D.lv, Vector3(-37.8, 1.4, 5.2), 0.0, "smear", 0.8)
	D.pool(Vector3(-45.0, 0.03, 2.0), 1.6)
	D.pool(Vector3(11.5, 0.03, 2.4), 1.4)

static func _pharmacy() -> void:
	# triage: blood-soaked mattresses on the tile, the sleeper's cot, trails to the back
	Props.blood_cot(D.lv, Vector3(-40.7, 0.02, -9.8), PI * 0.5)
	D.n += 6
	Props.blood_cot(D.lv, Vector3(-31.3, 0.02, -18.4), PI * 0.5)
	D.n += 6
	D.pool(Vector3(-34.4, 0.03, -9.4), 2.0)
	D.drag(Vector3(-34.0, 0.03, -10.0), Vector3(-38.0, 0.03, -16.6), 0.2, 0.0)
	D.pool(Vector3(-38.6, 0.03, -17.2), 2.2)
	D.splat(Vector3(-35.5, 0.03, -14.5), 1.1)
	# the shelves: smears
	D.hands(Vector3(-41.86, 1.1, -14.0), Vector3(-41.86, 1.6, -15.5), Vector3(1, 0, 0), 3, 0.2)
	D.spray(Vector3(-36.0, 1.5, -19.85), Vector3(0, 0, 1), Vector3(1, 0, 0), 1.8)
	D.drips(Vector3(-33.0, 1.9, -19.85), Vector3(0, 0, 1), 0.9)
	# the storefront: people pounding on the glass from outside, then inside
	Props.glass_blood(D.lv, Vector3(-39.7, 1.5, -5.94), 0.0, "hand", 0.25)
	Props.glass_blood(D.lv, Vector3(-39.3, 1.25, -5.94), 0.0, "hand2", 0.25)
	Props.glass_blood(D.lv, Vector3(-32.6, 1.7, -5.94), 0.0, "smear", 0.3)
	Props.glass_blood(D.lv, Vector3(-31.6, 1.4, -5.94), 0.0, "hand", 0.25)
	Props.glass_blood(D.lv, Vector3(-32.0, 2.1, -5.94), 0.0, "drips", 0.35)
	D.write("help", Vector3(-36.0, 1.8, -19.82), Vector3(0, 0, 1), 1.8)
	Props.corpse(D.lv, Vector3(-37.4, 0.03, -12.0), 0.7, {"shirt": Color(0.6, 0.6, 0.62), "bloody": 1.0, "coat": true, "coat_color": Color(0.85, 0.85, 0.86)})
	D.n += 1

static func _diner() -> void:
	# feeding ground: floor smears from the booths to the kitchen where the siren sings
	D.drag(Vector3(-22.0, 0.03, -8.4), Vector3(-15.2, 0.03, -15.6), 0.35, 1.8)
	D.drag(Vector3(-19.0, 0.03, -10.0), Vector3(-14.5, 0.03, -16.2), 0.35, 0.0)
	D.pool(Vector3(-17.0, 0.03, -12.5), 2.4, true)
	D.splat(Vector3(-23.0, 0.03, -11.0), 1.2)
	D.spray(Vector3(-25.88, 1.2, -13.5), Vector3(1, 0, 0), Vector3(0, 0, -1), 1.8)
	D.drips(Vector3(-25.88, 2.0, -9.5), Vector3(1, 0, 0), 0.9)
	D.wall_splat(Vector3(-14.0, 1.4, -17.78), Vector3(0, 0, 1), 1.4, Vector3(1, 0, 0), true)
	Props.gut_pile(D.lv, Vector3(-15.8, 0.03, -14.8), 0.3, 1.0)
	D.n += 2
	Props.corpse(D.lv, Vector3(-20.8, 0.03, -9.0), 1.9, {"shirt": Color(0.9, 0.85, 0.8), "bloody": 1.0})
	D.n += 1
	Props.glass_blood(D.lv, Vector3(-22.7, 1.5, -5.94), 0.0, "hand2", 0.25)
	Props.glass_blood(D.lv, Vector3(-14.4, 1.3, -5.94), 0.0, "splat", 0.6)

static func _square() -> void:
	# huddled round the tree for warmth, they never left
	Props.frozen_pile(D.lv, Vector3(26.0, 0.0, -22.0), 0.6, 5)
	D.n += 5
	D.pool(Vector3(14.5, 0.03, -23.0), 1.8)
	D.pool(Vector3(23.0, 0.03, -15.0), 1.6)
	D.drag(Vector3(22.0, 0.03, -15.0), Vector3(23.0, 0.03, -24.0), 0.1, 0.0)
	D.hands(Vector3(18.0, 0.9, -35.78), Vector3(20.0, 1.6, -35.78), Vector3(0, 0, 1), 4, 0.22)
	D.drips(Vector3(19.0, 2.2, -35.78), Vector3(0, 0, 1), 1.0)
	D.write("sleep", Vector3(13.0, 1.7, -35.8), Vector3(0, 0, 1), 2.6)
	D.droplets(Vector3(11.0, 0.03, -30.0), Vector3(19.0, 0.03, -34.0), 6, 0.26)
	D.splat(Vector3(9.5, 0.03, -14.0), 1.0)

static func _church_front() -> void:
	# frozen at the sealed doors: the ones who found no way in
	Props.frozen_pile(D.lv, Vector3(47.6, 0.0, -6.6), 0.2, 4)
	D.n += 5
	D.hands(Vector3(42.0, 0.9, -8.2), Vector3(45.0, 1.8, -8.2), Vector3(0, 0, 1), 5, 0.22)
	D.drips(Vector3(43.5, 2.0, -8.2), Vector3(0, 0, 1), 1.0)
	D.pool(Vector3(43.5, 0.03, -6.8), 2.2)
	D.steps(Vector3(36.0, 0.03, -3.0), Vector3(40.0, 0.03, -8.0), 1.0, false)

static func _narthex() -> void:
	D.pool(Vector3(39.4, 0.05, -9.7), 2.0)
	D.hands(Vector3(37.86, 0.9, -12.6), Vector3(37.86, 1.5, -13.8), Vector3(1, 0, 0), 3, 0.2)
	D.spray(Vector3(41.0, 1.4, -8.14), Vector3(0, 0, 1), Vector3(1, 0, 0), 1.6)
	D.write("out", Vector3(48.82, 1.8, -13.0), Vector3(-1, 0, 0), 1.7)
	D.drag(Vector3(41.0, 0.05, -12.5), Vector3(45.5, 0.05, -17.6), 0.0, 1.4)
	Props.severed_limb(D.lv, Vector3(44.4, 0.05, -14.6), 0.4, "arm")
	D.n += 2

static func _nave() -> void:
	# the aisle: drag marks into the dark of the chancel, a long smear with pools at the pews
	D.drag(Vector3(45.6, 0.05, -18.6), Vector3(46.2, 0.05, -34.5), 0.3, 0.0)
	D.drag(Vector3(44.6, 0.05, -20.0), Vector3(45.9, 0.05, -34.0), 0.3, 1.8)
	D.drag(Vector3(47.4, 0.05, -21.0), Vector3(46.6, 0.05, -33.5), 0.0, 1.5)
	D.pool(Vector3(46.0, 0.05, -26.5), 2.8)
	D.pool(Vector3(44.0, 0.05, -23.0), 1.8, true)
	D.pool(Vector3(48.4, 0.05, -29.0), 2.0)
	D.splat(Vector3(43.0, 0.05, -31.0), 1.4)
	D.splat(Vector3(49.5, 0.05, -33.0), 1.3, true)
	# pews: blood over the seats and ends; people died where they sat praying
	for p in [Vector3(41.4, 0.5, -19.7), Vector3(50.6, 0.5, -21.5), Vector3(41.3, 0.5, -23.3), Vector3(50.8, 0.5, -25.0)]:
		if D._ok():
			Gore.decal(D.lv, "pool_b", p, Vector3.UP, 1.6, Vector3.RIGHT, {"local": true, "depth": 0.6, "roll": D.rf(0, TAU)})
	Props.corpse(D.lv, Vector3(44.0, 0.04, -21.0), 1.8, {"shirt": Color(0.2, 0.12, 0.12), "bloody": 1.0})
	D.n += 1
	Props.corpse(D.lv, Vector3(48.3, 0.04, -24.5), 4.5, {"shirt": Color(0.12, 0.14, 0.2), "bloody": 1.0})
	D.n += 1
	Props.torso(D.lv, Vector3(43.4, 0.04, -26.4), 1.2)
	D.n += 3
	# wall runs under the stained glass
	for z in [-22.0, -26.5, -31.0, -35.0]:
		D.drips(Vector3(38.16, 2.4, z), Vector3(1, 0, 0), D.rf(0.8, 1.3))
		D.drips(Vector3(53.84, 2.2, z + 1.0), Vector3(-1, 0, 0), D.rf(0.8, 1.3))
	D.hands(Vector3(38.16, 1.0, -28.0), Vector3(38.16, 1.5, -30.0), Vector3(1, 0, 0), 3, 0.2)
	D.write("help", Vector3(53.84, 1.5, -28.0), Vector3(-1, 0, 0), 1.8)
	D.spray(Vector3(53.84, 1.0, -33.0), Vector3(-1, 0, 0), Vector3(0, 0, -1), 1.6)

static func _chancel() -> void:
	# the altar: a pool on the marble, a run down its front, a congregation's worth at the steps
	Gore.decal(D.lv, "pool_a", Vector3(46.0, 1.45, -40.2), Vector3.UP, 2.4, Vector3.RIGHT, {"local": true, "depth": 0.5, "roll": D.rf(0, TAU)})
	D.n += 1
	D.drips(Vector3(46.0, 1.38, -39.6), Vector3(0, 0, 1), 1.2)
	D.drips(Vector3(44.7, 1.38, -39.6), Vector3(0, 0, 1), 0.8)
	D.drips(Vector3(47.3, 1.38, -39.6), Vector3(0, 0, 1), 0.9)
	D.pool(Vector3(46.0, 0.39, -38.2), 3.2)
	D.pool(Vector3(41.5, 0.39, -36.5), 2.0, true)
	D.pool(Vector3(50.0, 0.39, -38.5), 2.2, true)
	D.pool(Vector3(46.0, 0.05, -33.0), 3.0)
	D.write("run", Vector3(46.0, 3.3, -41.82), Vector3(0, 0, 1), 2.6)
	D.hands(Vector3(39.9, 1.0, -41.84), Vector3(41.5, 1.8, -41.84), Vector3(0, 0, 1), 4, 0.22)
	D.hands(Vector3(50.5, 1.0, -41.84), Vector3(52.0, 1.6, -41.84), Vector3(0, 0, 1), 3, 0.22)
	Props.corpse(D.lv, Vector3(43.5, 0.4, -36.0), 0.3, {"shirt": Color(0.1, 0.1, 0.12), "bloody": 1.0})
	D.n += 1
	Props.body_bag(D.lv, Vector3(51.5, 0.4, -38.8), 1.6, false, true)
	D.n += 3
