extends RefCounted
## L6 - The Heart (brine cavern). The colony has been collecting people for years: bodies hang
## from the 20 m roof wrapped in crystal filaments, their blood pooled and frozen under clear ice
## on the floor below; a few still drip. The path down is a line of blood frozen in place; the
## arena floor is plated with it. Floor y = 0.

const D = preload("res://levels/dressing/dress_util.gd")
const Gore = preload("res://world/gore.gd")
const Props = preload("res://world/props.gd")

static func dress(level: Node3D) -> void:
	D.begin(level)
	_path()
	_under_hanging_bodies()
	_arena()
	_station_and_nook()

static func _frozen(p: Vector3, size: float) -> void:
	if D._ok():
		Gore.frozen_blood(D.lv, p, size, {"local": true})

static func _path() -> void:
	# they came down this way and did not climb back up
	D.drag(Vector3(0.3, 0.02, 65.0), Vector3(1.4, 0.02, 49.0), 0.4, 0.0)
	D.hands(Vector3(-1.9, 0.9, 66.38), Vector3(-1.9, 1.6, 66.38), Vector3(0, 0, -1), 2, 0.2)
	D.hands(Vector3(2.4, 1.0, 66.38), Vector3(2.4, 1.5, 66.38), Vector3(0, 0, -1), 2, 0.2)
	_frozen(Vector3(1.4, 0.02, 48.5), 2.6)
	_frozen(Vector3(3.6, 0.02, 33.0), 2.6)
	D.drag(Vector3(3.6, 0.02, 40.0), Vector3(3.6, 0.02, 33.5), 0.5, 0.0)
	D.droplets(Vector3(1.0, 0.02, 62.0), Vector3(1.5, 0.02, 37.0), 10, 0.26)
	D.steps(Vector3(0.6, 0.02, 60.0), Vector3(1.2, 0.02, 50.0), 1.0, false)
	# the sleeper and the first worker: old, dark, partly frozen
	D.old_pool(Vector3(-0.2, 0.02, 55.5), 2.0)
	D.pool(Vector3(1.0, 0.02, 47.0), 1.8, true)
	D.pool(Vector3(3.2, 0.02, 37.5), 1.4, true)
	# crystal-mounted victim at the path (a warning)
	Props.crystal_impale(D.lv, Vector3(5.4, 0.0, 44.5), 2.8, 2.4)
	D.n += 3
	D.spray(Vector3(4.86, 1.4, 56.0), Vector3(-1, 0, 0), Vector3(0, 0, -1), 1.6, true)
	D.splat(Vector3(2.0, 0.02, 22.0), 1.2, true)

static func _under_hanging_bodies() -> void:
	# floor under every hanging body: blood frozen into the ice; the low ones still bleed
	var spots := [Vector2(-6, 14), Vector2(3, 2), Vector2(-8, -10), Vector2(7, -12), Vector2(0, -19), Vector2(-13, -2),
		Vector2(14, -2), Vector2(-3, 22), Vector2(-5, 36), Vector2(-12, 28)]
	for s in spots:
		_frozen(Vector3(s.x, 0.02, s.y), D.rf(2.6, 3.8))
	Gore.drip_emitter(D.lv, Vector3(-4.5, 4.2, 50.0), "blood", 1.4)
	Gore.drip_emitter(D.lv, Vector3(-3.5, 4.8, 30.0), "blood", 1.9)
	D.pool(Vector3(-4.5, 0.02, 50.0), 2.4)
	D.pool(Vector3(-3.5, 0.02, 30.0), 2.4)

static func _arena() -> void:
	# the colony's feeding floor: frozen blood slicks, ichor and fresh kills around the pillars
	for p in [Vector3(-9, 0, 8), Vector3(8, 0, 6), Vector3(-10, 0, -6), Vector3(10, 0, -8), Vector3(-5, 0, -15), Vector3(5, 0, -16)]:
		D.pool(p + Vector3(D.rf(-1.5, 1.5), 0.02, D.rf(-1.5, 1.5)), D.rf(2.2, 3.4), D.rng.randf() < 0.5)
	_frozen(Vector3(0.0, 0.02, 6.0), 4.2)
	_frozen(Vector3(-6.0, 0.02, -2.0), 3.6)
	_frozen(Vector3(6.0, 0.02, -2.0), 3.6)
	_frozen(Vector3(0.0, 0.02, -12.0), 4.4)
	_frozen(Vector3(-12.0, 0.02, 14.0), 3.0)
	D.drag(Vector3(-10.0, 0.02, 10.0), Vector3(-1.0, 0.02, -8.0), 0.6, 0.0)
	D.drag(Vector3(9.0, 0.02, 8.0), Vector3(1.5, 0.02, -9.0), 0.6, 0.0)
	D.drag(Vector3(0.0, 0.02, 14.0), Vector3(0.0, 0.02, -2.0), 0.6, 0.0)
	D.splat(Vector3(-3.0, 0.02, 10.0), 1.6, true)
	D.splat(Vector3(4.0, 0.02, 0.0), 1.8)
	D.splat(Vector3(-2.0, 0.02, -8.0), 1.6, true)
	# impaled on the colony's crystals around the arena
	Props.crystal_impale(D.lv, Vector3(-13.0, 0.0, -10.0), 0.8, 2.6)
	D.n += 3
	Props.crystal_impale(D.lv, Vector3(14.0, 0.0, 0.0), 3.9, 2.2)
	D.n += 3
	Props.crystal_impale(D.lv, Vector3(-7.0, 0.0, -24.0), 0.2, 2.4)
	D.n += 3
	# human remains the Mother has finished with
	Props.torso(D.lv, Vector3(-2.5, 0.0, -4.0), 1.1, Color(0.25, 0.28, 0.33))
	D.n += 3
	Props.gut_pile(D.lv, Vector3(3.0, 0.0, -6.5), 0.6, 1.1)
	D.n += 2
	Props.severed_limb(D.lv, Vector3(-4.2, 0.0, 3.0), 2.0, "arm")
	D.n += 2
	Props.frozen_pile(D.lv, Vector3(-14.5, 0.0, 4.0), 0.4, 5)
	D.n += 5
	Gore.steam_vent(D.lv, Vector3(16.0, 0.3, -20.0), Vector3.UP, 1.4, 0.14)
	Gore.steam_vent(D.lv, Vector3(-14.5, 0.3, -20.0), Vector3.UP, 1.4, 0.14)

static func _station_and_nook() -> void:
	# the pipeline station: someone tried to reach the handles
	D.drag(Vector3(8.0, 0.02, -4.0), Vector3(17.0, 0.02, -4.0), 0.0, 1.4)
	D.hands(Vector3(18.7, 0.8, -2.6), Vector3(18.7, 1.2, -3.2), Vector3(-1, 0, 0), 2, 0.2)
	D.pool(Vector3(15.5, 0.02, -5.5), 2.0)
	# nook (safe room): nothing but a dried drop or two near the cot
	D.droplets(Vector3(5.0, 0.02, 36.5), Vector3(6.5, 0.02, 38.5), 2, 0.18)
