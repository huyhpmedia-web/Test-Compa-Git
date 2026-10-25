extends RefCounted
## L4 - MERIDIAN. The only warm, lit place in town, and the people who reached it died at its gate.
## The security checkpoint (z = 46) is a charnel heap; the lobby's welcome wall carries smeared
## handprints; bloody hands on the cold-aisle glass and the NOC window; ichor around the floor
## holes where the Rimebound come up; the cooling plant steams.
## Yard z 12..100 (+z away from the building), building floor y = 0.

const D = preload("res://levels/dressing/dress_util.gd")
const Gore = preload("res://world/gore.gd")
const Props = preload("res://world/props.gd")

static func dress(level: Node3D) -> void:
	D.begin(level)
	_gate()
	_hall_a()
	_corridor_noc()
	_lobby()
	_hall_c()
	_plant()
	_pipeline()
	_armory()

static func _gate() -> void:
	# the lake road: wrecks and the long crawl to the fence
	for c in [Vector3(-4.2, 0.03, 62.0), Vector3(3.8, 0.03, 55.0), Vector3(-9.0, 0.03, 30.0)]:
		D.pool(c + Vector3(1.8, 0, 0.5), 1.9)
		D.splat(c + Vector3(-1.5, 0, -1.0), 1.0)
	Props.glass_blood(D.lv, Vector3(-4.4, 1.45, 60.1), PI, "splat", 0.9)
	D.drag(Vector3(-3.0, 0.03, 61.0), Vector3(-1.4, 0.03, 50.4), 0.0, 0.0)
	D.drag(Vector3(3.2, 0.03, 54.0), Vector3(0.6, 0.03, 49.6), 0.0, 0.0)
	D.drag(Vector3(-8.2, 0.03, 31.0), Vector3(-3.5, 0.03, 49.0), 0.0, 0.0)
	D.steps(Vector3(-3.0, 0.03, 70.0), Vector3(-2.0, 0.03, 63.0), 1.0, false)
	# pile at the fence: the people who did not get in
	for p in [Vector3(-1.4, 0, 49.4), Vector3(0.5, 0, 50.6), Vector3(1.9, 0, 48.6), Vector3(-0.2, 0, 52.4), Vector3(-3.4, 0, 51.4)]:
		D.pool(p + Vector3(0, 0.03, 0), D.rf(1.8, 2.6))
	D.splat(Vector3(0.6, 0.03, 53.5), 1.4)
	D.splat(Vector3(-2.2, 0.03, 47.8), 1.1)
	D.spray(Vector3(1.0, 0.03, 52.0), Vector3.UP, Vector3(0.1, 0, 1), 1.9)
	Props.torso(D.lv, Vector3(2.6, 0.03, 52.4), 2.4, Color(0.15, 0.2, 0.3))
	D.n += 3
	Props.severed_limb(D.lv, Vector3(-4.6, 0.03, 49.0), -0.3, "leg")
	D.n += 2
	Props.gut_pile(D.lv, Vector3(0.9, 0.03, 54.0), 0.2, 0.9)
	D.n += 2
	# bloody hands on the gate posts, the checkpoint sign and the booth window
	D.hands(Vector3(-2.2, 1.0, 46.16), Vector3(-2.2, 1.5, 46.16), Vector3(0, 0, 1), 2, 0.2)
	D.hands(Vector3(2.2, 0.9, 46.16), Vector3(2.2, 1.4, 46.16), Vector3(0, 0, 1), 2, 0.2)
	D.drips(Vector3(-0.4, 2.8, 46.2), Vector3(0, 0, 1), 0.9)
	Props.glass_blood(D.lv, Vector3(5.2, 1.6, 45.8), 0.0, "hand", 0.25)
	Props.glass_blood(D.lv, Vector3(5.5, 1.35, 45.8), 0.0, "hand2", 0.25)
	Props.glass_blood(D.lv, Vector3(6.6, 1.55, 45.8), 0.0, "smear", 0.3)
	Props.glass_blood(D.lv, Vector3(6.9, 1.8, 45.8), 0.0, "drips", 0.4)
	D.pool(Vector3(5.4, 0.04, 42.8), 1.8)
	D.hands(Vector3(7.5, 1.1, 45.88), Vector3(7.5, 1.5, 45.88), Vector3(0, 0, 1), 2, 0.2)
	D.hands(Vector3(-0.4, 1.0, 12.14), Vector3(0.9, 1.6, 12.14), Vector3(0, 0, 1), 4, 0.22)   # the entrance doors
	D.pool(Vector3(0.0, 0.03, 13.2), 2.0)

static func _lobby() -> void:
	D.pool(Vector3(-6.2, 0.03, 6.5), 2.2)
	D.drag(Vector3(-4.0, 0.03, 10.5), Vector3(-6.2, 0.03, 6.5), 0.0, 0.0)
	D.drag(Vector3(0.0, 0.03, 11.0), Vector3(1.5, 0.03, -2.0), 0.0, 0.0)
	D.steps(Vector3(0.2, 0.03, 10.5), Vector3(0.6, 0.03, -2.5), 0.95, false)
	D.pool(Vector3(1.0, 0.03, -3.2), 1.8)
	# the welcome wall: handprints, smear, a long wipe through "UPTIME"
	D.hands(Vector3(-2.6, 1.1, -5.74), Vector3(2.4, 1.5, -5.74), Vector3(0, 0, 1), 7, 0.2)
	D.smear(Vector3(0.6, 1.0, -5.74), Vector3(0, 0, 1), Vector3(-1, -0.3, 0), 2.0)
	D.drips(Vector3(-1.4, 1.6, -5.74), Vector3(0, 0, 1), 0.9)
	# reception desk front and the floor
	D.spray(Vector3(-4.6, 0.7, 1.46), Vector3(0, 0, 1), Vector3(1, 0, 0), 1.6)
	D.drips(Vector3(-4.0, 1.0, 1.46), Vector3(0, 0, 1), 0.7)
	D.splat(Vector3(-4.5, 0.03, 3.0), 1.3)
	D.pool(Vector3(5.0, 0.03, 5.5), 1.6)

static func _hall_a() -> void:
	# glass doors of the cold aisles: pounding hands, sliding smears, a long run of blood
	for x in [-11.5, 11.5]:
		for z in [-6.97, -35.53]:
			var yaw := 0.0 if z > -20.0 else PI
			Props.glass_blood(D.lv, Vector3(x - 0.8, 1.45, z), yaw, "hand", 0.26)
			Props.glass_blood(D.lv, Vector3(x - 0.55, 1.15, z), yaw, "hand2", 0.26)
			Props.glass_blood(D.lv, Vector3(x + 0.7, 1.7, z), yaw, "smear", 0.34)
			Props.glass_blood(D.lv, Vector3(x + 0.2, 2.0, z), yaw, "drips", 0.45)
	# floor holes: ichor stains, a trail, handprints on the racks
	for p in [Vector3(-4, 0, -21), Vector3(3, 0, -22), Vector3(7, 0, -9)]:
		D.pool(p + Vector3(0, 0.03, 0), 2.0, true)
		D.splat(p + Vector3(D.rf(-1, 1), 0.03, D.rf(-1, 1)), 1.1, true)
	D.drag(Vector3(-4.0, 0.03, -20.5), Vector3(-2.5, 0.03, -14.2), 0.9, 0.0)
	D.pool(Vector3(-2.5, 0.03, -14.0), 2.4)
	D.pool(Vector3(11.8, 0.03, -29.0), 2.0)
	D.drag(Vector3(11.0, 0.03, -24.5), Vector3(11.7, 0.03, -29.0), 0.0, 0.0)
	D.hands(Vector3(9.0, 1.2, -29.0), Vector3(9.0, 1.7, -27.0), Vector3(1, 0, 0), 3, 0.2)
	D.spray(Vector3(-7.0, 1.0, -35.7), Vector3(0, 0, 1), Vector3(1, 0, 0), 1.7)
	D.splat(Vector3(-0.5, 0.03, -9.0), 1.0)
	D.droplets(Vector3(0.0, 0.03, -7.0), Vector3(-1.5, 0.03, -14.0), 6, 0.26)
	D.write("help", Vector3(3.0, 1.6, -35.78), Vector3(0, 0, 1), 1.6)

static func _hall_c() -> void:
	for p in [Vector3(-3, 0, -47), Vector3(4, 0, -41), Vector3(2, 0, -56)]:
		D.pool(p + Vector3(0, 0.03, 0), 1.9, true)
	D.pool(Vector3(-1.5, 0.03, -52.5), 2.2)
	D.pool(Vector3(8.0, 0.03, -47.2), 2.0)
	D.drag(Vector3(2.0, 0.03, -55.0), Vector3(-1.5, 0.03, -52.5), 0.8, 0.0)
	D.drag(Vector3(4.0, 0.03, -42.0), Vector3(8.0, 0.03, -47.0), 0.8, 0.0)
	for x in [-11.5, 11.5]:
		Props.glass_blood(D.lv, Vector3(x - 0.7, 1.4, -59.17), PI, "hand", 0.26)
		Props.glass_blood(D.lv, Vector3(x + 0.6, 1.1, -59.17), PI, "smear", 0.34)
	D.hands(Vector3(15.86, 1.0, -46.0), Vector3(15.86, 1.5, -47.0), Vector3(-1, 0, 0), 3, 0.2)
	D.splat(Vector3(-8.0, 0.03, -43.0), 1.2)

static func _plant() -> void:
	D.pool(Vector3(27.0, 0.03, -49.8), 2.4)
	D.drag(Vector3(24.0, 0.03, -45.0), Vector3(27.0, 0.03, -49.6), 0.2, 0.0)
	D.splat(Vector3(35.0, 0.03, -44.0), 1.3, true)
	D.pool(Vector3(33.0, 0.03, -52.0), 2.6, true)
	D.pool(Vector3(41.0, 0.03, -41.0), 2.0, true)
	D.spray(Vector3(49.88, 1.4, -45.0), Vector3(-1, 0, 0), Vector3(0, 0, -1), 1.8, true)
	D.wall_splat(Vector3(20.0, 1.2, -59.88), Vector3(0, 0, 1), 1.3, Vector3(1, 0, 0), true)
	D.drips(Vector3(35.0, 2.6, -35.88), Vector3(0, 0, 1), 1.0, true)
	D.write("sleep", Vector3(38.0, 1.5, -59.86), Vector3(0, 0, 1), 2.2)
	# coolant mist
	Gore.steam_vent(D.lv, Vector3(22.0, 0.3, -56.0), Vector3.UP, 1.0, 0.14)
	Gore.steam_vent(D.lv, Vector3(44.0, 0.3, -40.0), Vector3.UP, 1.0, 0.14)
	Gore.drip_emitter(D.lv, Vector3(30.0, 3.8, -44.0), "water", 1.5)
	Gore.drip_emitter(D.lv, Vector3(40.0, 3.8, -52.0), "melt", 1.2)

static func _corridor_noc() -> void:
	# the NOC window: everyone came here for Imogen. Hands, smears, a face-sized print
	for x in [-12.4, -11.2, -9.9, -8.6, -2.8, -1.6, -0.3, 1.0]:
		Props.glass_blood(D.lv, Vector3(x, D.rf(0.9, 1.9), -65.86), 0.0, "hand" if D.rng.randf() < 0.5 else "hand2", 0.26, D.rf(-0.3, 0.3))
	Props.glass_blood(D.lv, Vector3(-10.4, 1.9, -65.86), 0.0, "smear", 0.34)
	Props.glass_blood(D.lv, Vector3(-1.9, 2.0, -65.86), 0.0, "drips", 0.5)
	Props.glass_blood(D.lv, Vector3(-12.0, 2.3, -65.86), 0.0, "splat", 0.7)
	D.pool(Vector3(-10.0, 0.03, -64.0), 2.0)
	D.pool(Vector3(-2.0, 0.03, -63.5), 1.8)
	D.drag(Vector3(-9.5, 0.03, -63.5), Vector3(-3.0, 0.03, -63.0), 0.0, 0.0)
	D.pool(Vector3(30.0, 0.03, -64.0), 2.2)
	D.drag(Vector3(36.0, 0.03, -62.0), Vector3(30.0, 0.03, -64.0), 0.3, 0.0)
	D.hands(Vector3(5.0, 1.0, -65.88), Vector3(6.0, 1.6, -65.88), Vector3(0, 0, 1), 2, 0.2)
	D.spray(Vector3(18.0, 1.4, -65.88), Vector3(0, 0, 1), Vector3(1, 0, 0), 1.8)
	D.steps(Vector3(36.0, 0.03, -61.5), Vector3(24.0, 0.03, -62.5), 1.0, false)

static func _armory() -> void:
	D.pool(Vector3(38.0, 0.03, -31.0), 2.2)
	D.splat(Vector3(44.0, 0.03, -30.0), 1.0)
	D.spray(Vector3(34.12, 1.3, -28.0), Vector3(1, 0, 0), Vector3(0, 0, 1), 1.6)
	D.drag(Vector3(42.0, 0.03, -34.0), Vector3(38.0, 0.03, -31.0), 0.0, 0.0)

static func _pipeline() -> void:
	# the return line is frosted and, someone says, bleeds ichor on the inside
	D.pool(Vector3(26.0, 0.03, -92.0), 2.6, true)
	D.splat(Vector3(23.0, 0.03, -90.0), 1.2, true)
	D.drips(Vector3(25.4, 3.6, -91.3), Vector3(-1, 0, 0), 1.1, true)
	Gore.drip_emitter(D.lv, Vector3(26.0, 6.0, -91.5), "ichor", 1.8)
	Gore.drip_emitter(D.lv, Vector3(21.5, 6.5, -92.0), "ichor", 2.4)
	D.pool(Vector3(14.0, 0.03, -90.0), 2.4)
	D.drag(Vector3(10.0, 0.03, -74.0), Vector3(14.0, 0.03, -89.0), 0.0, 0.0)
	D.hands(Vector3(7.14, 1.0, -85.0), Vector3(7.14, 1.4, -87.0), Vector3(1, 0, 0), 3, 0.2)
	Gore.steam_vent(D.lv, Vector3(18.0, 7.6, -88.0), Vector3.UP, 1.2, 0.12)
