extends RefCounted
## L2 school interiors (R7-B): grimy wall/floor decals, skirting, Sketchfab props.  Called from
## levels/l2_school.gd build() after the shell exists:  L2I.dress(self).
## Does not touch walls / doors / triggers / items; every solid prop sits on already-clear floor.

const SF = preload("res://levels/dressing/l2_sf.gd")
const Props = preload("res://world/props.gd")
const Mats = preload("res://core/mats.gd")

const FY := 0.45
const YB := -3.05
const HC := 4.2
const K := 0.7      # decal density multiplier (clustered decal budget)

static var lv: Node3D     # the level (decals / lights parent)
static var g: Node3D      # geo (props parent: carves the navmesh)

## Call first thing in build() (props need the geo parent before dress() runs).
static func begin(level: Node3D) -> void:
	lv = level
	var gg = level.get("geo")
	g = gg if gg is Node3D else level
	SF.rng.seed = hash("l2_interior_props")

static func dress(level: Node3D) -> void:
	begin(level)
	if OS.get_environment("R7B_OFF") == "1":
		return
	SF.begin(hash("l2_interior"))
	_hall()
	_corridor()
	_gym()
	_west_wing()
	_rear_rooms()
	_basement()
	_boiler_room()
	_locker_room()
	_fixtures()

# ------------------------------------------------------------------ generic room dressing
## rect = inner wall faces (x0, z0, x1, z1); gaps = per wall list of [centre, width] along that wall.
## walls: "w" (x0, normal +x), "e" (x1, normal -x), "n" (z0, normal +z), "s" (z1, normal -z).
static func room(r: Rect2, fy: float, h: float, o := {}) -> void:
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.end.x
	var z1 := r.end.y
	var gaps: Dictionary = o.get("gaps", {})
	var skirt: bool = o.get("skirt", true)
	var skip: Array = o.get("skip", [])     # walls without skirting / decals ("w","e","n","s")
	var walls := {
		"w": [Vector3(x0, fy, z0), Vector3(x0, fy, z1), Vector3(1, 0, 0)],
		"e": [Vector3(x1, fy, z0), Vector3(x1, fy, z1), Vector3(-1, 0, 0)],
		"n": [Vector3(x0, fy, z0), Vector3(x1, fy, z0), Vector3(0, 0, 1)],
		"s": [Vector3(x0, fy, z1), Vector3(x1, fy, z1), Vector3(0, 0, -1)],
	}
	for k in walls:
		if k in skip:
			continue
		var a: Vector3 = walls[k][0]
		var b: Vector3 = walls[k][1]
		var nrm: Vector3 = walls[k][2]
		var along := (b - a).normalized()
		var L := a.distance_to(b)
		# free spans between gaps
		var spans: Array = [[0.0, L]]
		for gp in gaps.get(k, []):
			var c: float = (gp[0] - a.x) if absf(along.x) > 0.5 else (gp[0] - a.z)
			var w: float = gp[1] * 0.5 + 0.02
			var nsp: Array = []
			for sp in spans:
				if c + w <= sp[0] or c - w >= sp[1]:
					nsp.append(sp)
				else:
					if c - w > sp[0] + 0.15:
						nsp.append([sp[0], c - w])
					if c + w < sp[1] - 0.15:
						nsp.append([c + w, sp[1]])
			spans = nsp
		if skirt:
			for sp in spans:
				SF.skirting(g, a + along * sp[0], a + along * sp[1], nrm)
				if o.get("rail", false):
					SF.rail(g, a + along * sp[0], a + along * sp[1], nrm, 1.05)
		# soot band at the foot
		if o.get("band", true):
			for sp in spans:
				var seg_len: float = sp[1] - sp[0]
				var cnt := maxi(1, int(round(seg_len / 6.5)))
				for i in cnt:
					var t0: float = sp[0] + seg_len * i / cnt
					var t1: float = sp[0] + seg_len * (i + 1) / cnt
					var c := a + along * ((t0 + t1) * 0.5) + Vector3(0, 0.55, 0) + nrm * 0.0
					SF.decal(lv, "band", c, nrm, t1 - t0 + 0.2, 1.1, o.get("band_op", 0.75), 0.0, 0.3)
		# stains hanging from the ceiling, peeling paint, mould, rust
		for kind in [["water", "water", 2.6], ["peel", "peel", 2.2], ["mold", "mold", 1.6], ["rust", "rust", 2.0]]:
			var cnt: int = int(round(o.get(kind[0], 0) * K))
			for i in cnt:
				if spans.is_empty():
					break
				var sp: Array = spans[SF.rng.randi() % spans.size()]
				var t: float = SF.rf(sp[0], sp[1])
				var sz: float = kind[2] * SF.rf(0.8, 1.25)
				var yy: float
				match kind[0]:
					"water":
						yy = fy + h - sz * 0.5 + 0.1
					"mold":
						yy = fy + SF.rf(0.5, 1.2)
					_:
						yy = fy + SF.rf(1.0, h - 1.0)
				var c := a + along * t + Vector3(0, yy - fy, 0)
				SF.decal(lv, kind[1], c, nrm, sz, sz * (1.15 if kind[0] == "water" else 1.0), SF.rf(0.55, 0.85), 0.0, 0.3)
	# floor grime: tracked-in muck and wear
	for i in int(round(o.get("floor", 0) * K)):
		var p := Vector3(SF.rf(x0 + 0.5, x1 - 0.5), fy + 0.01, SF.rf(z0 + 0.5, z1 - 0.5))
		SF.floor_dec(lv, "grime" if SF.rng.randf() < 0.75 else "pool", p, SF.rf(2.0, 3.6), SF.rf(2.0, 3.4), SF.rf(0.5, 0.85))
	# ceiling stains
	for i in int(round(o.get("ceil", 0) * K)):
		var p := Vector3(SF.rf(x0 + 1.0, x1 - 1.0), fy + h - 0.02, SF.rf(z0 + 1.0, z1 - 1.0))
		SF.decal(lv, "water", p, Vector3.DOWN, SF.rf(2.2, 3.4), SF.rf(2.0, 3.2), SF.rf(0.5, 0.8), SF.rf(0, TAU), 0.3)
	for i in o.get("cracks", 0):
		if spans_ok(walls):
			var kk: String = ["w", "e", "n", "s"][SF.rng.randi() % 4]
			if kk in skip:
				continue
			var a2: Vector3 = walls[kk][0]
			var b2: Vector3 = walls[kk][1]
			var al: Vector3 = (b2 - a2).normalized()
			var t2 := SF.rf(1.0, a2.distance_to(b2) - 1.0)
			SF.decal(lv, "cracks", a2 + al * t2 + Vector3(0, SF.rf(1.0, h - 1.5), 0), walls[kk][2], 2.4, 2.4, 0.8, 0.0, 0.3)

static func spans_ok(_w) -> bool:
	return true

# ------------------------------------------------------------------ props
static func _root(pos: Vector3, yaw: float) -> Node3D:
	var r := Node3D.new()
	r.position = pos
	r.rotation.y = yaw
	g.add_child(r)
	return r

## A row of lockers (replaces Props.locker): `count` lockers 0.42 m apart, centred on pos, front toward local +Z.
static func lockers(pos: Vector3, yaw: float, count := 3, kind := "locker_b") -> Node3D:
	var r := _root(pos, yaw)
	var width := count * 0.42
	var unit := 1.367 if kind == "locker_b" else 2.41
	var per := 3.0 if kind == "locker_b" else 5.0
	var units := maxi(1, int(round(width / unit)))
	var sx := width / (units * unit)
	var uh := 1.85 if kind == "locker_b" else 1.75
	var sy := 1.0
	var dep := 0.33 if kind == "locker_b" else 1.04
	for i in units:
		var x := (i - (units - 1) * 0.5) * unit * sx
		SF.prop(r, kind, Vector3(x, 0, (-0.085 if kind == "locker_b" else 0.27)), 0.0, {"scale": Vector3(sx, sy, 1.0), "collide": "none", "range": 38.0})
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, 1.9, 0.5)
	cs.shape = bs
	cs.position = Vector3(0, 0.95, 0)
	sb.add_child(cs)
	r.add_child(sb)
	var _u := uh
	return r

static func school_desk(pos: Vector3, yaw: float, topple := false) -> void:
	var r := Node3D.new()
	r.position = pos
	r.rotation.y = yaw
	if topple:
		r.rotation.x = SF.rf(-1.2, 1.2)
		r.position.y += 0.25
	g.add_child(r)
	SF.prop(r, "desk", Vector3.ZERO, -PI * 0.5, {"collide": "none", "range": 30.0})
	if not topple:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.34, 0.035, 0.3)
		cs.shape = bs
		cs.position = Vector3(0, 0.72, -0.2)
		sb.add_child(cs)
		r.add_child(sb)

## Cot frame (replaces the primitive frame + canvas of _cot).
static func cot(r: Node3D) -> void:
	SF.prop(r, "cot", Vector3.ZERO, 0.0, {"collide": "none", "scale": 1.15, "range": 34.0, "shadow": false})

# ------------------------------------------------------------------ rooms
static func _hall() -> void:
	var gaps := {"n": [[0.0, 3.4]], "s": [[0.0, 2.7]], "w": [[-14.5, 1.6]]}
	room(Rect2(-6.875, -21.875, 13.75, 11.75), FY, HC, {"gaps": gaps, "water": 4, "peel": 3, "mold": 2, "rust": 0, "floor": 4, "ceil": 3, "cracks": 2, "rail": true, "band_op": 0.8})
	# cast-iron radiators under the notice wall and by the doors; extinguisher, clock
	SF.prop(g, "radiator", Vector3(-6.7, FY, -19.3), 0.0, {"collide": "none"})
	SF.prop(g, "radiator", Vector3(-6.7, FY, -12.0), 0.0, {"collide": "none"})
	SF.prop(g, "radiator", Vector3(4.5, FY, -21.7), PI * 0.5, {"collide": "none"})

static func _corridor() -> void:
	var gaps := {"n": [[-20.0, 2.4], [-14.5, 1.6], [-8.0, 1.6], [-2.0, 1.6], [4.0, 1.6]], "s": [[-18.0, 1.6], [-10.5, 1.6], [0.0, 3.4]], "e": [[-24.0, 2.2]]}
	room(Rect2(-21.875, -25.875, 28.75, 3.75), FY, HC, {"gaps": gaps, "water": 4, "peel": 4, "mold": 2, "rust": 2, "floor": 5, "ceil": 3, "cracks": 2})

static func _gym() -> void:
	var gaps := {"w": [[-24.0, 2.2]]}
	room(Rect2(7.125, -33.875, 14.75, 23.75), FY, 6.5, {"gaps": gaps, "water": 6, "peel": 5, "mold": 3, "rust": 2, "floor": 8, "ceil": 4, "cracks": 3, "skip": ["n"], "band_op": 0.7})
	# radiators along the west wall; wall clock
	for z in [-14.0, -19.0, -31.0]:
		SF.prop(g, "radiator", Vector3(7.3, FY, z), 0.0, {"collide": "none"})

static func _west_wing() -> void:
	# lobby
	room(Rect2(-21.875, -21.875, 7.75, 11.75), FY, HC, {"gaps": {"s": [[-18.5, 1.6]], "e": [[-18.0, 1.6]]}, "water": 3, "peel": 3, "mold": 2, "floor": 3, "ceil": 2})
	# Ruth's office
	room(Rect2(-13.875, -21.875, 6.75, 11.75), FY, HC, {"gaps": {"w": [[-18.0, 1.6]], "e": [[-14.5, 1.6]], "n": [[-10.5, 1.6]]}, "water": 2, "peel": 2, "mold": 1, "floor": 3, "ceil": 1})

static func _rear_rooms() -> void:
	# classroom 2B, shop, nurse, coach
	room(Rect2(-17.875, -33.875, 6.75, 7.75), FY, HC, {"gaps": {"s": [[-14.5, 1.6]]}, "water": 3, "peel": 3, "mold": 2, "floor": 4, "ceil": 2, "skip": ["n"], "rail": true})
	room(Rect2(-10.875, -33.875, 5.75, 7.75), FY, HC, {"gaps": {"s": [[-8.0, 1.6]]}, "water": 2, "peel": 2, "rust": 2, "floor": 4, "ceil": 1, "skip": ["n"]})
	room(Rect2(-4.875, -33.875, 5.75, 7.75), FY, HC, {"gaps": {"s": [[-2.0, 1.6]]}, "water": 2, "peel": 2, "mold": 1, "floor": 3, "ceil": 1, "skip": ["n"]})
	room(Rect2(1.125, -33.875, 5.75, 7.75), FY, HC, {"gaps": {"s": [[4.0, 1.6]]}, "water": 2, "peel": 2, "floor": 3, "ceil": 1, "skip": ["n"]})

static func _basement() -> void:
	var h := 3.2
	# stair foot + corridor
	room(Rect2(-21.875, -33.875, 19.75, 3.25), YB, h, {"gaps": {"s": [[-15.0, 1.6], [-7.0, 1.6]], "e": [[-32.2, 1.6]]}, "water": 3, "peel": 3, "mold": 4, "rust": 4, "floor": 4, "ceil": 3, "skip": []})
	# pipe chase
	room(Rect2(-17.875, -30.375, 5.75, 10.25), YB, h, {"gaps": {"s": [[-15.0, 1.6]]}, "water": 2, "mold": 4, "rust": 3, "floor": 3, "ceil": 2})

static func _boiler_room() -> void:
	var h := 3.2
	room(Rect2(-11.875, -30.375, 9.75, 12.25), YB, h, {"gaps": {"n": [[-7.0, 1.6]], "e": [[-28.7, 1.6], [-21.3, 1.6]]}, "water": 3, "peel": 3, "mold": 3, "rust": 6, "floor": 5, "ceil": 3, "cracks": 1, "skip": ["w"]})
	# real boiler: shell with burner pipework (replaces the primitive cylinder)
	SF.prop_solid(g, "boiler", Vector3(-9.9, YB, -24.5), 0.0, Vector3(2.7, 2.2, 1.45), {"range": 40.0})
	# horizontal expansion tank, header pipes and valves on the feed run
	SF.prop_solid(g, "tanks", Vector3(-10.2, YB, -20.9), 0.0, Vector3(2.9, 1.0, 0.9), {"scale": 0.9, "range": 40.0})
	SF.prop(g, "valve", Vector3(-5.8, YB + 1.56, -25.2), 0.0, {"collide": "none", "scale": 1.1})
	SF.prop(g, "valve", Vector3(-3.0, YB + 1.56, -25.2), PI * 0.5, {"collide": "none", "scale": 1.1})
	SF.prop(g, "pipes", Vector3(-9.8, YB, -29.7), 0.0, {"collide": "none", "scale": 1.3})
	SF.prop(g, "radiator", Vector3(-2.36, YB, -24.0), PI, {"collide": "none"})
	# oily floor and drip stains under the machinery
	SF.floor_dec(lv, "pool", Vector3(-9.0, YB + 0.02, -24.4), 3.6, 3.0, 0.9, 0.3)
	SF.floor_dec(lv, "pool", Vector3(-5.5, YB + 0.02, -27.5), 2.4, 2.2, 0.8, 1.9)

static func _locker_room() -> void:
	var h := 3.2
	room(Rect2(4.125, -33.875, 17.75, 21.75), YB, h, {"gaps": {"w": [[-21.3, 1.6], [-12.7, 1.6]]}, "water": 6, "peel": 4, "mold": 6, "rust": 6, "floor": 4, "ceil": 4, "cracks": 3, "skirt": false, "band": false})

static func blanket(parent: Node3D, size: Vector2, pos: Vector3, col: Color, lump := 0.5, drop := 0.1, yaw := 0.0, seed_v := 0, body := 0.0) -> void:
	SF.blanket(parent, size, pos, col, lump, drop, yaw, seed_v, body)

static func pillow(parent: Node3D, pos: Vector3, col: Color, seed_v := 0) -> void:
	Props.sphere(parent, 0.2, pos, SF.fabric(col), Vector3(1.15, 0.38, 0.78))

## Blackboard for classroom 2B: Sketchfab chalkboard stretched to the wall, base at pos.
static func chalkboard(pos: Vector3) -> void:
	SF.prop(g, "chalkboard", pos, 0.0, {"collide": "none", "scale": Vector3(1.66, 1.38, 1.0), "shadow": false})

# ------------------------------------------------------------------ ceilings, fixtures, wall furniture
static func _beam(a: Vector3, b: Vector3, size := Vector2(0.3, 0.4), mat := "metal_painted") -> void:
	var d := b - a
	var m := Props.box(g, Vector3(d.length(), size.y, size.x), (a + b) * 0.5, Mats.get_mat(mat, 1.0), false)
	m.rotation.y = atan2(-d.z, d.x)

static func _fixtures() -> void:
	# corridor ductwork + conduit
	var cy := FY + HC - 0.32
	_beam(Vector3(-21.5, cy, -22.75), Vector3(6.5, cy, -22.75), Vector2(0.55, 0.36), "metal")
	Props.pipe(g, Vector3(-21.5, FY + HC - 0.16, -25.55), Vector3(6.5, FY + HC - 0.16, -25.55), 0.045, "metal_rust")
	Props.pipe(g, Vector3(-21.5, FY + HC - 0.16, -25.35), Vector3(6.5, FY + HC - 0.16, -25.35), 0.03, "metal")
	# gym roof steel
	for z in [-12.0, -20.5, -29.0]:
		_beam(Vector3(7.3, FY + 6.3, z), Vector3(21.7, FY + 6.3, z), Vector2(0.28, 0.5), "metal_painted")
	Props.pipe(g, Vector3(7.3, FY + 6.1, -33.6), Vector3(21.7, FY + 6.1, -33.6), 0.07, "metal_rust")
	Props.pipe(g, Vector3(7.3, FY + 6.1, -10.4), Vector3(21.7, FY + 6.1, -10.4), 0.07, "metal_rust")
	# hall ceiling: cross beams
	for z in [-16.0, -21.2]:
		_beam(Vector3(-6.8, FY + HC - 0.18, z), Vector3(6.8, FY + HC - 0.18, z), Vector2(0.3, 0.3), "wood")
	# wall furniture from the PH office set: clocks, extinguishers, alarm pull-stations
	SF_env("interior/wall_clock", Vector3(-3.1, FY + 3.15, -21.86), 0.0, {"fit_h": 0.5})
	SF_env("interior/wall_clock", Vector3(14.5, FY + 5.2, -10.2), PI, {"fit_h": 0.9})
	SF_env("interior/extinguisher", Vector3(-6.8, FY + 1.1, -13.1), PI * 0.5, {"fit_h": 0.55})
	SF_env("interior/extinguisher", Vector3(-3.0, FY + 1.1, -22.2), PI, {"fit_h": 0.55})
	SF_env("interior/extinguisher", Vector3(7.25, FY + 1.1, -27.0), PI * 0.5, {"fit_h": 0.55})
	SF_env("interior/fire_alarm", Vector3(-9.5, FY + 1.35, -22.17), PI, {"fit_h": 0.2})
	SF_env("interior/fire_alarm", Vector3(-6.82, FY + 1.35, -20.2), PI * 0.5, {"fit_h": 0.2})
	SF_env("interior/wheelchair", Vector3(-9.6, FY, -23.5), 2.3, {"fit_h": 0.95, "collide": "none"})
	SF_env("interior/wheelchair", Vector3(-3.6, FY, -30.5), 0.6, {"fit_h": 0.95, "collide": "none"})
	SF_env("interior/medical_box", Vector3(-4.7, FY + 1.36, -27.5), PI * 0.5, {"fit_h": 0.4, "collide": "none"})
	SF_env("interior/wheelchair", Vector3(12.0, FY, -12.2), 0.4, {"fit_h": 0.95, "collide": "none"})

static func SF_env(rel: String, pos: Vector3, yaw: float, opts := {}) -> Node3D:
	var Env = load("res://world/env_assets.gd")
	var o := {"snow": 0.0, "range": 40.0, "collide": "none"}
	o.merge(opts, true)
	return Env.spawn(g, rel, pos, yaw, o)
