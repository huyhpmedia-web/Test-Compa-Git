extends RefCounted
## Shared helpers for the per-level gore dressing scripts (levels/dressing/<id>_dress.gd).
## Everything is placed in the level's local space with explicit floor heights (no raycasts, so it
## works during Level._ready).  A per-level decal budget (MAX) keeps the cluster cost sane.

const Gore = preload("res://world/gore.gd")
const Props = preload("res://world/props.gd")
const Mats = preload("res://core/mats.gd")

const MAX := 118
static var n := 0
static var lv: Node3D
static var rng := RandomNumberGenerator.new()

static func begin(level: Node3D) -> void:
	# parent everything under the level's navigation geometry so solid props carve the navmesh
	var g = level.get("geo")
	lv = g if g is Node3D else level
	n = 0
	rng.seed = hash(String(level.name))

static func rf(a: float, b: float) -> float:
	return rng.randf_range(a, b)

static func _ok(c := 1) -> bool:
	if n + c > MAX:
		return false
	n += c
	return true

static func _o(extra := {}) -> Dictionary:
	var o := {"local": true, "depth": 0.3}
	o.merge(extra, true)
	return o

## Floor pool (blood or ichor).
static func pool(p: Vector3, size: float, ichor := false) -> void:
	if not _ok():
		return
	Gore.decal(lv, Gore.POOL[rng.randi() % 3], p, Vector3.UP, size, Vector3(rf(-1, 1), 0, rf(-1, 1)), _o({"ichor": ichor, "roll": rf(0, TAU)}))

static func splat(p: Vector3, size: float, ichor := false) -> void:
	if not _ok():
		return
	Gore.decal(lv, Gore.SPLAT[rng.randi() % 4], p, Vector3.UP, size, Vector3.RIGHT, _o({"ichor": ichor, "roll": rf(0, TAU)}))

## Scatter of small droplets between a and b (a bleeding person walking).
static func droplets(a: Vector3, b: Vector3, count: int, size := 0.28) -> void:
	for i in count:
		if not _ok():
			return
		var t := (i + rng.randf()) / float(count)
		var p := a.lerp(b, t) + Vector3(rf(-0.25, 0.25), 0, rf(-0.25, 0.25))
		Gore.decal(lv, "splat_c", p, Vector3.UP, size * rf(0.7, 1.3), Vector3.RIGHT, _o({"roll": rf(0, TAU), "depth": 0.2}))

## Alternating bloody bootprints from a to b.
static func steps(a: Vector3, b: Vector3, spacing := 0.8, bare := false, fade := true) -> void:
	var d := b - a
	d.y = 0
	var L := d.length()
	if L < 0.3:
		return
	var dir := d / L
	var side := dir.cross(Vector3.UP)
	var k := 0
	var t := 0.0
	while t < L:
		if not _ok():
			return
		var left := (k % 2 == 0)
		var p := a + dir * t + side * (0.13 if left else -0.13)
		var op := 0.95 * (1.0 - 0.8 * t / L) if fade else 0.9
		Gore.footprint(lv, p, Vector3.UP, dir, left, bare, 0.34, _o({"opacity": op, "depth": 0.2}))
		t += spacing
		k += 1

## Drag trail from a to b on the floor (y of a), with a pool at the start.
static func drag(a: Vector3, b: Vector3, ichor_mix := 0.0, pool_size := 1.5) -> void:
	var d := b - a
	d.y = 0
	var L := d.length()
	if L < 0.5:
		return
	var dir := d / L
	var step := 1.9
	var segs := int(ceil(L / step))
	for i in segs:
		if not _ok():
			return
		var c: Vector3 = a + dir * min(step * (i + 0.5), L)
		c.y = lerp(a.y, b.y, (i + 0.5) / segs)
		Gore.decal(lv, Gore.DRAG[rng.randi() % 2], c, Vector3.UP, step * 1.12, dir, _o({"roll": rf(-0.1, 0.1), "ichor": rng.randf() < ichor_mix}))
	if pool_size > 0.0:
		pool(a, pool_size)

static func smear(p: Vector3, normal: Vector3, dir: Vector3, length := 1.6) -> void:
	if not _ok():
		return
	Gore.decal(lv, Gore.SMEAR[rng.randi() % 2], p, normal, length, dir, _o())

static func wall_splat(p: Vector3, normal: Vector3, size: float, dir := Vector3.ZERO, ichor := false) -> void:
	if not _ok():
		return
	var o := _o({"ichor": ichor, "depth": 0.5})
	var name: String = Gore.SPLAT[rng.randi() % 4]
	var tg := Vector3.ZERO
	if dir.length() > 0.01:
		name = "splat_wall"
		tg = dir
	else:
		o["roll"] = rf(0, TAU)
	Gore.decal(lv, name, p, normal, size, tg, o)

static func spray(p: Vector3, normal: Vector3, dir: Vector3, size := 1.4, ichor := false) -> void:
	if not _ok():
		return
	var n_ := normal.normalized()
	var t := (dir - n_ * dir.dot(n_)).normalized()
	Gore.decal(lv, Gore.SPRAY[rng.randi() % 2], p + t * size * 0.4, normal, size, t, _o({"ichor": ichor, "roll": rf(-0.1, 0.1), "depth": 0.5}))

static func drips(top: Vector3, normal: Vector3, size := 0.7, ichor := false) -> void:
	if not _ok():
		return
	var t := normal.cross(Vector3.DOWN)
	Gore.decal(lv, "drips_a" if rng.randf() < 0.6 else "drips_b", top + Vector3.DOWN * size * 0.95, normal, size, t, _o({"ichor": ichor, "roll": rf(-0.04, 0.04), "depth": 0.5}))

## One bloody hand on a wall / door (fingers up).
static func hand(p: Vector3, normal: Vector3, size := 0.2) -> void:
	if not _ok():
		return
	var names := ["hand_r", "hand_l", "hand_smear"]
	Gore.decal(lv, names[rng.randi() % 3], p, normal, size, normal.cross(Vector3.DOWN), _o({"roll": rf(-0.5, 0.5), "depth": 0.5}))

## A staggered column of handprints climbing/sliding along a wall from a to b.
static func hands(a: Vector3, b: Vector3, normal: Vector3, count: int, size := 0.2) -> void:
	for i in count:
		var t := (i + 0.5) / float(count)
		hand(a.lerp(b, t) + Vector3(0, rf(-0.12, 0.12), 0) + normal.cross(Vector3.UP) * rf(-0.1, 0.1), normal, size * rf(0.9, 1.15))

static func write(id: String, p: Vector3, normal: Vector3, width := 1.6) -> void:
	if not _ok():
		return
	Gore.writing(lv, id, p, normal, width, _o({"depth": 0.4}))

static func outline(p: Vector3, yaw := 0.0, size := 1.9) -> void:
	if not _ok(2):
		return
	Props.body_outline(lv, p, yaw, size)

static func puddle(p: Vector3, size := 1.3) -> void:
	if not _ok():
		return
	Gore.decal(lv, "puddle_a" if rng.randf() < 0.5 else "puddle_b", p, Vector3.UP, size, Vector3.RIGHT, _o({"roll": rf(0, TAU)}))

## Blood decal on a vertical surface of a prop mesh (windows etc. use Props.car_gore instead).
static func prop_budget(c := 2) -> bool:
	return _ok(c)

## Old, dried blood (dark brown, matte): the 2011 collapse and other long-dead scenes.
static func old_pool(p: Vector3, size: float) -> void:
	if not _ok():
		return
	Gore.decal(lv, Gore.POOL[rng.randi() % 3], p, Vector3.UP, size, Vector3.RIGHT, _o({"roll": rf(0, TAU), "color": Color(0.7, 0.6, 0.5), "opacity": 0.8}))
