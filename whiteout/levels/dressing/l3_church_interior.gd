extends RefCounted
## L3 interiors (R7-B): pharmacy, diner, hardware store and St. Brendan's nave.  Sketchfab props from
## assets/env/interior_sf plus grime decals.  Called from levels/l3_church.gd:
##   L3I.dress(self)   at the end of build()  (decals / skirting only; props are placed where the old
##                     primitives were via L3I.pew / L3I.organ / L3I.booth / L3I.shelf ...)

const SF = preload("res://levels/dressing/l2_sf.gd")
const L2I = preload("res://levels/dressing/l2_school_interior.gd")
const Props = preload("res://world/props.gd")
const Mats = preload("res://core/mats.gd")

static var g: Node3D
static var lv: Node3D

static func _setup(level: Node3D) -> void:
	lv = level
	var gg = level.get("geo")
	g = gg if gg is Node3D else level
	L2I.lv = level
	L2I.g = g

static func dress(level: Node3D) -> void:
	_setup(level)
	SF.begin(hash("l3_interior"))
	# pharmacy (inner faces x -41.85..-30.15, z -19.85..-6.15)
	L2I.room(Rect2(-41.85, -19.85, 11.7, 13.7), 0.02, 3.4, {"gaps": {}, "skip": ["s"], "water": 3, "peel": 3, "mold": 2, "floor": 4, "ceil": 3, "cracks": 1, "rail": true})
	# diner
	L2I.room(Rect2(-25.85, -17.85, 13.7, 11.7), 0.02, 3.4, {"gaps": {}, "skip": ["s"], "water": 3, "peel": 3, "mold": 2, "floor": 4, "ceil": 3, "cracks": 1, "rail": true})
	# hardware
	L2I.room(Rect2(0.15, 6.15, 15.7, 13.7), 0.02, 3.4, {"gaps": {}, "skip": ["n"], "water": 3, "peel": 3, "mold": 2, "rust": 3, "floor": 4, "ceil": 3, "cracks": 1})
	# St. Brendan's: nave and narthex (walls rise to ~7 m)
	L2I.room(Rect2(38.2, -41.8, 15.6, 23.4), 0.04, 7.0, {"gaps": {}, "skip": ["s"], "water": 6, "peel": 5, "mold": 4, "floor": 6, "ceil": 0, "cracks": 3, "band_op": 0.8, "rail": false})
	L2I.room(Rect2(38.2, -17.8, 10.65, 9.6), 0.04, 3.4, {"gaps": {"w": [[-11.0, 1.4]]}, "skip": ["s", "e"], "water": 3, "peel": 3, "mold": 2, "floor": 3, "ceil": 2})
	# floor wear down the centre aisle, wet muck at the doors
	SF.floor_dec(lv, "grime", Vector3(46.0, 0.07, -22.0), 3.4, 7.0, 0.55, 0.0)
	SF.floor_dec(lv, "grime", Vector3(46.0, 0.07, -30.0), 3.4, 6.0, 0.5, 0.0)

# ------------------------------------------------------------------ church
## Replaces the primitive _pew(): two GLB pews per 4.8 m run.  Parent r carries yaw/tilt like the original.
static func pew(level: Node3D, x: float, z: float, yaw: float, length: float, tilt: float, lift: float) -> void:
	_setup(level)
	var r := Node3D.new()
	r.position = Vector3(x, lift, z)
	r.rotation = Vector3(0, yaw, tilt)
	g.add_child(r)
	var n := maxi(1, int(round(length / 2.8)))
	var s := length / (n * 2.8)
	for i in n:
		SF.prop(r, "pew_a", Vector3((i - (n - 1) * 0.5) * 2.8 * s, 0, 0.0), 0.0, {"scale": s, "collide": "none", "range": 45.0, "shadow": false})
	# the original seat-height solid (cover for the choir fight, steppable by nothing)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(length, 0.1, 0.5)
	cs.shape = bs
	cs.position = Vector3(0, 0.45, 0)
	sb.add_child(cs)
	r.add_child(sb)

## Real pipe organ against the west wall of the chancel (replaces the console / pipe cylinders).
static func organ(level: Node3D) -> void:
	_setup(level)
	SF.prop_solid(g, "organ", Vector3(39.35, 0.38, -38.4), PI * 0.5, Vector3(1.9, 3.0, 1.7), {"range": 60.0, "shadow": true})

## Altar furniture: candelabras with real flame lights, tall candle stands, Mary, confessional.
static func altar_fixtures(level: Node3D) -> void:
	_setup(level)
	var alt := Vector3(46.0, 0.38, -40.2)
	for sx in [-1.35, 1.35]:
		var p := alt + Vector3(sx, 1.44, 0.0)
		SF.prop(g, "candelabra", p, 0.0, {"collide": "none", "range": 40.0})
		_flame(level, p + Vector3(0, 0.74, 0.0), 1.1)
	for sp in [Vector3(42.6, 0.38, -39.4), Vector3(49.4, 0.38, -39.4)]:
		SF.prop(g, "candle_stand", sp, 0.0, {"collide": "cyl", "cyl_r": 0.25, "range": 40.0})
		_flame(level, sp + Vector3(0, 1.7, 0.0), 1.0)
	SF.prop_solid(g, "mary", Vector3(51.6, 0.38, -40.6), PI * -0.15, Vector3(0.4, 0.95, 0.4), {"range": 40.0})
	_flame(level, Vector3(51.4, 0.38 + 1.2, -40.0), 0.5)
	SF.prop_solid(g, "confessional", Vector3(39.15, 0.04, -32.6), PI * 0.5, Vector3(1.5, 2.7, 1.75), {"range": 60.0})
	# a pair of altar-step grime decals and a candle-wax drip on the cloth
	SF.floor_dec(lv, "grime", Vector3(46.0, 0.4, -37.0), 4.0, 2.5, 0.5, 0.0)

static func _flame(level: Node3D, pos: Vector3, e: float) -> void:
	var l: OmniLight3D = level.call("light", pos, Color(1.0, 0.66, 0.34), e, 5.5, false, true)
	var arr = level.get("_nave_spots")
	if arr is Array:
		arr.append([l, e])

# ------------------------------------------------------------------ shops
## Replaces the diner's _booth().
static func booth(level: Node3D, pos: Vector3, yaw: float) -> void:
	_setup(level)
	SF.prop_solid(g, "booth", pos, yaw, Vector3(1.2, 0.5, 2.5), {"range": 36.0})

## Supermarket gondola with stock; used for the pharmacy shelves.  Front faces local +Z.
static func shelf(level: Node3D, pos: Vector3, yaw: float, scale_v := 1.0) -> void:
	_setup(level)
	SF.prop_solid(g, "shelf_market", pos, yaw, Vector3(3.5 * scale_v, 1.7 * scale_v, 0.7 * scale_v), {"scale": scale_v, "range": 40.0})

static func register(level: Node3D, pos: Vector3, yaw: float) -> void:
	_setup(level)
	SF.prop(g, "register", pos, yaw, {"collide": "none", "scale": 1.3, "range": 25.0})

static func coffee(level: Node3D, pos: Vector3, yaw: float) -> void:
	_setup(level)
	SF.prop(g, "coffee", pos, yaw, {"collide": "none", "scale": 1.0, "range": 25.0})

static func workbench(level: Node3D, pos: Vector3, yaw: float) -> void:
	_setup(level)
	SF.prop_solid(g, "workbench", pos, yaw, Vector3(2.3, 1.0, 0.5), {"range": 36.0})
