extends Node
## Headless AUTOMATED PLAYTHROUGH harness (QA).
##
##   godot --headless --fixed-fps 60 --path . res://tools/playtest.tscn -- level=l1_substation
##   godot --headless --fixed-fps 60 --path . res://tools/playtest.tscn -- level=chain
##   godot --headless --fixed-fps 60 --path . res://tools/playtest.tscn -- level=l3_church soak=1
##   (use tools/playtest.sh [level|all|chain|soak])
##
## Args (after `--`):  level=<l1_substation|...|l6_heart|chain>   soak=1 (runtime-error soak only)
##                     flags=a,b   verbose=1   frames=600 (soak length)
##
## The harness plays each level's critical path like a player would: it teleports the player
## to a *walkable* spot (nav-mesh point) next to each Interactable, checks the player's own
## reach/facing rules, checks that the interactable actually receives focus, and calls
## `interact(player)`. Dialogue is auto-advanced, modals closed, every cutscene must release
## the player again (otherwise the step FAILs as a softlock). Bosses are killed through the
## enemy API (take_hit / burn on their real weak points). Output is a PASS/FAIL report;
## exit code is 1 if any step failed.

# ------------------------------------------------------------------ log capture (Godot 4.5 Logger)
class PlayLogger extends Logger:
	var mutex := Mutex.new()
	var entries: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _bt: Array) -> void:
		mutex.lock()
		entries.append({"fn": function, "file": file, "line": line, "code": code, "msg": rationale, "type": error_type})
		mutex.unlock()
	func _log_message(_message: String, _error: bool) -> void:
		pass
	func take() -> Array:
		mutex.lock()
		var out := entries.duplicate()
		entries.clear()
		mutex.unlock()
		return out

var args := {}
var plog: PlayLogger
var results: Array = []        # {scope, name, ok, detail}
var scope := ""
var verbose := false
var god := true
var min_hp := 100
var lowest_y := 999.0
var log_count := 0
var last_spot := Vector3.INF      # where the player last stood (for walkability checks)
var route_checks := true
var routes_failed := 0
var walking := true               # really walk legs with the player controller (walk=0 -> teleport only)
var walked_m := 0.0
var pre_interact := Callable()    # called right before the next interact() (e.g. to place an enemy)

const FPS := 60.0

# =================================================================== bootstrap
func _ready() -> void:
	name = "World"  # Game._load_level reuses a current scene named World
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() == 2 else "1"
	verbose = args.has("verbose")
	walking = args.get("walk", "1") != "0"
	plog = PlayLogger.new()
	OS.add_logger(plog)
	get_tree().process_frame.connect(_on_frame)
	await get_tree().process_frame
	var target: String = args.get("level", "l1_substation")
	if target == "chain":
		await run_chain()
	elif args.has("soak"):
		await run_soak(target)
	else:
		await run_level(target)
	_report_and_quit()

func _on_frame() -> void:
	# autopilot: advance dialogue, close informational modals, god mode
	if UI._dlg_active:
		UI._dlg_advance = true
	if UI.modal != null and is_instance_valid(UI.modal) and not (UI.modal.name in ["Ending", "GameOver"]):
		UI.close_modal()
	if god and Game.hp > 0:
		if Game.hp < min_hp:
			min_hp = Game.hp
		Game.hp = Game.MAX_HP
	var p = Game.player
	if p != null and is_instance_valid(p) and p.is_inside_tree():
		lowest_y = min(lowest_y, p.global_position.y)
	_drain_log()

func _drain_log() -> void:
	for e in plog.take():
		log_count += 1
		var kind: String = ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"][clampi(int(e.type), 0, 3)]
		var line := "[LOG] %s in %s:%d  %s %s" % [kind, str(e.file).get_file(), e.line, e.code, e.msg]
		print(line)
		results.append({"scope": scope, "name": "log: " + kind, "ok": int(e.type) == 1, "detail": line, "log": true})

func _report_and_quit() -> void:
	_drain_log()
	var fails := 0
	var per := {}
	for r in results:
		if r.has("log") and r.ok:
			continue
		var s: String = r.scope
		if not per.has(s):
			per[s] = [0, 0]
		if r.ok:
			per[s][0] += 1
		else:
			per[s][1] += 1
			fails += 1
	print("")
	print("==================== PLAYTEST REPORT ====================")
	for s in per:
		print("%-24s PASS %3d   FAIL %3d" % [s, per[s][0], per[s][1]])
	if fails > 0:
		print("---- failures ----")
		for r in results:
			if not r.ok:
				print("FAIL %s :: %s :: %s" % [r.scope, r.name, r.detail])
	print("lowest player y seen: %.2f   lowest hp seen: %d" % [lowest_y, min_hp])
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)

# =================================================================== reporting helpers
func rec(step: String, ok: bool, detail := "") -> void:
	results.append({"scope": scope, "name": step, "ok": ok, "detail": detail})
	print("[%s] %s: %s%s" % ["PASS" if ok else "FAIL", scope, step, ("  -- " + detail) if (detail != "" and (not ok or verbose)) else ""])

func info(msg: String) -> void:
	print("[INFO] %s: %s" % [scope, msg])

func warn(msg: String) -> void:
	print("[WARN] %s: %s" % [scope, msg])

# =================================================================== time
func fr(n := 1) -> void:
	for i in n:
		await get_tree().process_frame

func wait(sec: float) -> void:
	await fr(int(ceil(sec * FPS)))

func lvl() -> Node:
	return Game.current_level

func pl() -> Node:
	return Game.player

## Waits until nothing blocks the player (dialogue, modal, cutscene lock) for ~20 frames.
func settle(max_sec := 90.0, what := "") -> bool:
	var stable := 0
	var t := 0.0
	while t < max_sec:
		await get_tree().process_frame
		t += 1.0 / FPS
		var p = Game.player
		var blocked: bool = UI.is_blocking() or (p != null and is_instance_valid(p) and p.input_locked)
		if blocked:
			stable = 0
		else:
			stable += 1
			if stable >= 20:
				return true
	rec("softlock: player released after %s" % what, false, "still blocked after %.0fs (dlg=%s modal=%s)" % [max_sec, UI._dlg_active, UI.modal])
	# force-release so later steps can still run
	if pl():
		pl().input_locked = false
	UI._dlg_active = false
	UI.dlg_panel.visible = false
	return false

func wait_until(cond: Callable, max_sec := 30.0) -> bool:
	var t := 0.0
	while t < max_sec:
		if cond.call():
			return true
		await get_tree().process_frame
		t += 1.0 / FPS
	return cond.call()

# =================================================================== state
func fresh_state(extra_flags: Array = []) -> void:
	Game.hp = Game.MAX_HP
	Game.inventory = []
	Game.inv_slots = 8
	Game.item_box = [{"id": "spray", "count": 1}]
	Game.equipped = ""
	Game.flags = {}
	Game.play_time = 0.0
	Game.saves_used = 0
	Game.deaths = 0
	Game.objective = ""
	Game.add_item("knife", 1)
	Game.add_item("handgun", 1)
	Game.add_item("radio", 1)
	Game.set_ammo_loaded("handgun", 12)
	Game.add_item("ammo_9mm", 15)
	Game.equipped = "handgun"
	for f in extra_flags:
		if f != "":
			Game.flags[f] = true

func load_level(id: String, spawn := "start") -> void:
	Game.level_id = id
	Game.spawn_id = spawn
	Game._load_level()
	await fr(3)

## After a real level transition: wait until the new level exists and the player is placed.
func await_level(id: String, spawn: String) -> bool:
	var ok := await wait_until(func(): return Game.level_id == id and Game.current_level != null and is_instance_valid(Game.current_level) and Game.current_level.name == id and Game.player != null and is_instance_valid(Game.player) and Game.player.is_inside_tree(), 15.0)
	await fr(5)
	if ok:
		ok = Game.spawn_id == spawn
	return ok

# =================================================================== finding things
func interactables() -> Array:
	var out := []
	for n in get_tree().get_nodes_in_group("interactable"):
		if is_instance_valid(n) and n.is_inside_tree():
			out.append(n)
	return out

func find_it(sub: String, near := Vector3.INF) -> Node:
	var best: Node = null
	var bd := 1e18
	for n in interactables():
		if not n.get("enabled"):
			continue
		if str(n.get("prompt")).findn(sub) < 0:
			continue
		var d: float = 0.0 if near == Vector3.INF else n.global_position.distance_to(near)
		if d < bd:
			bd = d
			best = n
	return best

func find_meta(key: String, val) -> Node:
	for n in interactables():
		if n.has_meta(key) and n.get_meta(key) == val:
			return n
	return null

func _walk(root: Node, pred: Callable) -> Array:
	var out := []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if pred.call(n):
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out

func find_trigger(uid: String) -> Node:
	var r := _walk(lvl(), func(n): return n is Area3D and n.has_method("_on_enter") and n.get("uid") == uid)
	return r[0] if not r.is_empty() else null

func all_triggers() -> Array:
	return _walk(lvl(), func(n): return n is Area3D and n.has_method("_on_enter"))

func enemies() -> Array:
	var out := []
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			out.append(e)
	return out

func enemy_by_uid(uid: String) -> Node:
	var r := _walk(lvl(), func(n): return n is CharacterBody3D and n.get("uid") != null and n.get("uid") == uid)
	return r[0] if not r.is_empty() else null

# =================================================================== positioning
func nav_map() -> RID:
	return lvl().geo.get_navigation_map()

func snap(p: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(nav_map(), p)

## Opens every door collider and re-bakes the nav mesh, so route checks answer "is there a
## physical way between these two spots once the doors are opened".
func prep_nav() -> void:
	for d in get_tree().get_nodes_in_group("door"):
		for sb in d.find_children("*", "StaticBody3D", true, false):
			sb.collision_layer = 0
	lvl().geo.bake_navigation_mesh(false)
	await fr(4)

func route_ok(a: Vector3, b: Vector3) -> bool:
	var path := NavigationServer3D.map_get_path(nav_map(), a, b, true)
	return path.size() >= 1 and path[path.size() - 1].distance_to(b) < 0.7

func check_route(to: Vector3, label: String) -> void:
	if route_checks and last_spot != Vector3.INF:
		if not route_ok(last_spot, to):
			routes_failed += 1
			rec("walkable route to " + label, false, "no navmesh path from %s to %s (doors counted as open) - unreachable on foot?" % [last_spot.snapped(Vector3(0.1, 0.1, 0.1)), to.snapped(Vector3(0.1, 0.1, 0.1))])
	last_spot = to

## Would the real player rules (Player._find_interactable) accept `it` from standing spot `pos`?
func reach_ok(it: Node, pos: Vector3) -> bool:
	var to: Vector3 = it.global_position - pos
	var dy: float = abs(to.y - 0.8)
	to.y = 0
	var r: float = it.get("radius") if it.get("radius") != null else 1.6
	return to.length() <= r and dy <= 2.0

## Best walkable standing spot for interacting with `it`. Returns Vector3.INF if none.
## Spots connected (by navmesh) to where the player last stood are preferred; if the only spots
## that satisfy the reach rules are on an island (e.g. on top of a truck bed), the route check fails.
func standing_spot(it: Node, want := Callable()) -> Vector3:
	var t: Vector3 = it.global_position
	var r: float = it.get("radius") if it.get("radius") != null else 1.6
	var cands: Array = [snap(t)]
	for rad in [0.6, 1.0, 0.35, 0.8, 0.9, 0.5]:
		for k in 16:
			var a := TAU * k / 16.0
			cands.append(snap(t + Vector3(cos(a), 0, sin(a)) * r * rad))
	# nav points keep 0.4 m from walls, the player capsule only needs 0.32: also try creeping
	# up to 0.4 m closer to the target (validated against real collision geometry)
	var extra: Array = []
	for c in cands:
		var dir := Vector3(t.x - c.x, 0, t.z - c.z)
		if dir.length() > 0.5:
			dir = dir.normalized()
			for step in [0.15, 0.3, 0.42]:
				var c2: Vector3 = c + dir * step
				if capsule_free(c2):
					extra.append(c2)
	cands.append_array(extra)
	var best := Vector3.INF
	var bscore := 1e18
	var best_any := Vector3.INF
	var bscore_any := 1e18
	for c in cands:
		if not reach_ok(it, c):
			continue
		if want.is_valid() and not want.call(c):
			continue
		var flat: float = Vector2(c.x - t.x, c.z - t.z).length()
		var score: float = abs(flat - 0.55 * r) + abs(t.y - c.y - 0.8) * 0.3
		if score < bscore_any:
			bscore_any = score
			best_any = c
		if (not route_checks or last_spot == Vector3.INF or route_ok(last_spot, c)) and score < bscore:
			bscore = score
			best = c
	if verbose:
		info("spot for %s (it at %s): best=%s any=%s ncand=%d" % [it.get("prompt"), t, best, best_any, cands.size()])
	return best if best != Vector3.INF else best_any

## Really walk to `target` with the player controller (sprint + forward, camera steered along the
## nav path) so collision, door gaps, ramps and steps are exercised by real physics.
## Triggers and cutscenes met on the way fire naturally; we simply wait them out.
func walk_to(target: Vector3, label: String) -> bool:
	var p = pl()
	if p == null or not is_instance_valid(p):
		return false
	await settle(90.0, "before walking to " + label)
	var path := NavigationServer3D.map_get_path(nav_map(), p.global_position, target, true)
	if path.size() < 2:
		return true
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i].distance_to(path[i - 1])
	if total < 1.0:
		return true
	var miny := 1e9
	for pp in path:
		miny = min(miny, pp.y)
	var old_mask: int = p.collision_mask
	p.collision_mask = 1          # enemies must not body-block the scripted walk
	Input.action_press("sprint")
	var idx := 1
	var t := 0.0
	var limit := total / 2.5 + 12.0
	var ok := true
	var mark: Vector3 = p.global_position
	var mark_t := 0.0
	var reason := ""
	while idx < path.size():
		await get_tree().process_frame
		t += 1.0 / FPS
		p = pl()
		if p == null or not is_instance_valid(p):
			ok = false
			reason = "player vanished"
			break
		if p.input_locked or UI.is_blocking():
			Input.action_release("move_forward")
			mark = p.global_position
			mark_t = t
			limit += 1.0 / FPS
			continue
		var wp: Vector3 = path[idx]
		var d: Vector3 = wp - p.global_position
		d.y = 0
		var thr := 0.45 if idx < path.size() - 1 else 0.3
		if d.length() < thr:
			idx += 1
			continue
		p.cam_yaw = atan2(-d.x, -d.z)
		Input.action_press("move_forward")
		if p.global_position.y < miny - 2.5:
			ok = false
			reason = "fell through the floor at %s" % p.global_position.snapped(Vector3(0.1, 0.1, 0.1))
			break
		if t - mark_t > 2.0:
			if p.global_position.distance_to(mark) < 0.3:
				var why := "blocked at %s heading to %s" % [p.global_position.snapped(Vector3(0.1, 0.1, 0.1)), wp.snapped(Vector3(0.1, 0.1, 0.1))]
				warn("walk to %s: %s (ledge/obstacle the navmesh does not know; teleporting on)" % [label, why])
				break
			mark = p.global_position
			mark_t = t
		if t > limit:
			ok = false
			reason = "walk timed out (%.0fs for %.0fm)" % [t, total]
			break
	Input.action_release("move_forward")
	Input.action_release("sprint")
	p = pl()
	if p != null and is_instance_valid(p):
		p.collision_mask = old_mask
		p.velocity = Vector3.ZERO
	walked_m += total
	if not ok:
		rec("walk to " + label, false, reason)
	return ok

func capsule_free(pos: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.31
	cap.height = 1.6
	q.shape = cap
	q.transform = Transform3D(Basis(), pos + Vector3(0, 0.95, 0))
	q.collision_mask = 1
	return pl().get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()

func place_player(pos: Vector3, face_to := Vector3.INF) -> void:
	var p = pl()
	p.global_position = pos + Vector3(0, 0.06, 0)
	p.velocity = Vector3.ZERO
	if face_to != Vector3.INF:
		var d := face_to - pos
		var yaw := atan2(d.x, d.z)
		p.model.rotation.y = yaw
		p.cam_yaw = yaw + PI

# =================================================================== inventory management
## Real players can store gear in the supply crate. Make room for `item` the way a player would:
## move expendables (and, if really needed, spare weapons) to the item box. Logged so that
## inventory pressure shows up in the report.
func make_room(item: String) -> void:
	if Game.can_add(item, 1):
		return
	var order := ["gel", "adrenaline", "powder", "flare", "ammo_shell", "ammo_44", "ammo_grenade", "spray", "gel_mix", "shotgun", "magnum", "launcher", "pouch"]
	for id in order:
		if id == item:
			continue
		if Game.has_item(id):
			var s = null
			for x in Game.inventory:
				if x.id == id:
					s = x
			Game.inventory.erase(s)
			Game.item_box.append({"id": id, "count": s.count})
			Game.inventory_changed.emit()
			warn("inventory full: stored %s x%d in the crate to fit %s" % [id, s.count, item])
			if Game.can_add(item, 1):
				return
	if not Game.can_add(item, 1):
		rec("inventory has room for %s" % item, false, "inventory: %s" % str(inv_ids()))

func inv_ids() -> Array:
	return Game.inventory.map(func(s): return s.id)

# =================================================================== actions
## Walk up to an interactable (teleport to a walkable spot in reach), verify focus, press interact.
func use(it: Node, label: String, expect_focus := true, want := Callable(), do_settle := true) -> bool:
	if it == null or not is_instance_valid(it):
		rec("interact: " + label, false, "interactable not found / freed")
		return false
	var spot := standing_spot(it, want)
	if spot == Vector3.INF:
		rec("reachable: " + label, false, "no walkable standing spot within reach (radius=%s, at %s)" % [it.get("radius"), it.global_position])
		return false
	check_route(spot, label)
	if walking:
		await walk_to(spot, label)
	place_player(spot, it.global_position)
	await fr(4)
	if expect_focus and pl().focused_interact != it:
		var f = pl().focused_interact
		var fp := str(f.get("prompt")) if f != null else "<none>"
		warn("focus for '%s' went to '%s' (shadowed by a closer interactable)" % [label, fp])
		var spot2 := snap(it.global_position)
		if reach_ok(it, spot2):
			place_player(spot2, it.global_position)
			await fr(4)
	if expect_focus and pl().focused_interact != it:
		var f2 = pl().focused_interact
		rec("focusable: " + label, false, "focus stayed on '%s'" % (str(f2.get("prompt")) if f2 else "<none>"))
	if pre_interact.is_valid():
		pre_interact.call()
		pre_interact = Callable()
	it.interact(pl())
	await fr(2)
	if do_settle:
		await settle(90.0, label)
	return true

func use_prompt(sub: String, label := "", near := Vector3.INF, want := Callable()) -> bool:
	var it := find_it(sub, near)
	if it == null:
		rec("interactable '%s' exists" % sub, false, "not found (or disabled)")
		return false
	return await use(it, label if label != "" else sub, true, want)

func pick(uid: String, label := "") -> bool:
	var lb := label if label != "" else uid
	var it := find_meta("uid", uid)
	if it == null:
		if Game.has_flag("got:" + uid):
			rec("pickup " + lb, true, "already collected")
			return true
		rec("pickup " + lb, false, "no pickup node for uid %s in the level" % uid)
		return false
	var item: String = it.get_meta("item", "")
	make_room(item)
	var ok := await use(it, "pickup " + lb)
	if not ok:
		return false
	await settle(60.0, "pickup " + lb)
	if item == "pouch" and Game.has_item("pouch"):
		Game.use_item("pouch")   # a player would use the pouch straight away
	var got := Game.has_flag("got:" + uid)
	rec("pickup " + lb, got, "flag got:%s not set (inventory full?)" % uid)
	return got

func read_note(uid: String) -> bool:
	var it := find_meta("uid", uid)
	if it == null:
		rec("note " + uid, false, "note node missing")
		return false
	var ok := await use(it, "note " + uid)
	await settle(10.0, "note " + uid)
	return ok

func open_door(uid: String, expect_open := true, label := "", want := Callable()) -> bool:
	var lb := label if label != "" else "door " + uid
	var it := find_meta("door_uid", uid)
	if it == null:
		if Game.has_flag("open:" + uid):
			rec(lb, true, "already open")
			return true
		rec(lb, false, "door node not found")
		return false
	if not await use(it, lb, true, want):
		return false
	await fr(50)  # key-unlock timer inside door()
	await settle(30.0, lb)
	var opened: bool = Game.has_flag("open:" + uid) or not is_instance_valid(it) or not it.enabled
	if expect_open:
		rec(lb + " opens", opened, "door did not open (locked?)")
	return opened

func fire_trigger(uid: String) -> void:
	var t := find_trigger(uid)
	if t == null:
		if not Game.has_flag("trig:" + uid):
			rec("trigger " + uid, false, "trigger node not found")
		return
	await _step_into(t, "trigger " + uid, true)
	await fr(5)
	if t.get("once") and not Game.has_flag("trig:" + uid):
		rec("trigger " + uid + " fires", false, "player standing in the trigger volume did not fire it")
	await settle(90.0, "trigger " + uid)

func _step_into(t: Node, label := "", walk := false) -> void:
	var cs: CollisionShape3D = null
	for c in t.get_children():
		if c is CollisionShape3D:
			cs = c
	var bottom: Vector3 = t.global_position
	if cs != null and cs.shape is BoxShape3D:
		bottom.y -= (cs.shape as BoxShape3D).size.y * 0.5
	var spot := snap(bottom + Vector3(0, 0.1, 0))
	if label != "":
		check_route(spot, label)
	if walk and walking:
		await walk_to(spot, label)
	place_player(spot)

# =================================================================== sanity checks
## Player spawn: above the floor, not inside geometry, nav mesh exists. Enemies not inside walls.
func check_world(id: String) -> void:
	var l := lvl()
	rec("level loads (%s)" % id, l != null and pl() != null, "no level / player")
	if l == null or pl() == null:
		return
	var nm: NavigationMesh = l.geo.navigation_mesh
	var polys := nm.get_polygon_count() if nm != null else 0
	rec("navmesh baked (%d polys)" % polys, polys > 20, "nav mesh empty - enemies cannot path")
	var y0: float = pl().global_position.y
	await wait(3.0)
	var y1: float = pl().global_position.y
	rec("player stands at spawn (y %.2f -> %.2f)" % [y0, y1], y1 > -1.0 and abs(y1 - y0) < 1.5, "player fell / sank")
	var space: PhysicsDirectSpaceState3D = pl().get_world_3d().direct_space_state
	var pq := PhysicsShapeQueryParameters3D.new()
	var pcap := CapsuleShape3D.new()
	pcap.radius = 0.3
	pcap.height = 1.6
	pq.shape = pcap
	pq.transform = Transform3D(Basis(), pl().global_position + Vector3(0, 0.9, 0))
	pq.collision_mask = 1
	rec("player spawn is free of geometry", space.intersect_shape(pq, 4).is_empty(), "spawn capsule overlaps world geometry at %s" % pl().global_position)
	var bad_inside := []
	var bad_nav := []
	for e in enemies():
		var type := str(e.get_script().resource_path.get_file().get_basename())
		if type in ["hanger"] or e.state == "dead":
			continue
		var q := PhysicsShapeQueryParameters3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.25
		cap.height = 1.2
		q.shape = cap
		q.transform = Transform3D(Basis(), e.global_position + Vector3(0, 0.95, 0))
		q.collision_mask = 1
		var hits := space.intersect_shape(q, 4)
		if not hits.is_empty():
			bad_inside.append("%s(%s) @%s" % [e.get("uid"), type, e.global_position.snapped(Vector3(0.1, 0.1, 0.1))])
		var sp := snap(e.global_position)
		if sp.distance_to(e.global_position) > 2.5 and type != "boss_choir":
			bad_nav.append("%s(%s) %.1fm" % [e.get("uid"), type, sp.distance_to(e.global_position)])
	rec("no enemy spawned inside geometry", bad_inside.is_empty(), ", ".join(bad_inside))
	if not bad_nav.is_empty():
		warn("enemies far from navmesh (will not path): " + ", ".join(bad_nav))

## Every stair/ramp must be climbable with the real controller (both directions).
func check_stairs() -> void:
	var p = pl()
	var n := 0
	var home: Vector3 = p.global_position
	var home_yaw: float = p.cam_yaw
	for r in get_tree().get_nodes_in_group("stairs"):
		var m: Dictionary = r.get_meta("stairs")
		var fwd := Basis(Vector3.UP, m.yaw) * Vector3(0, 0, 1)
		var lo: Vector3 = m.pos
		var hi: Vector3 = lo + fwd * m.length + Vector3(0, m.rise, 0)
		n += 1
		for up in [true, false]:
			var a: Vector3 = (lo - fwd * 0.8) if up else (hi + fwd * 0.8)
			var b: Vector3 = hi if up else lo
			# start on the floor level that belongs to that end (find it with a ray)
			var from := a + Vector3(0, 1.2 if up else 1.2, 0)
			var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -4, 0), 1)
			var h: Dictionary = p.get_world_3d().direct_space_state.intersect_ray(q)
			if h.is_empty():
				continue
			p.global_position = h.position + Vector3(0, 0.08, 0)
			p.velocity = Vector3.ZERO
			p.collision_mask = 1
			await fr(3)
			var d := b - a
			d.y = 0
			p.cam_yaw = atan2(-d.x, -d.z)
			Input.action_press("move_forward")
			var t := 0.0
			var reached := false
			while t < (d.length() / 2.0 + 3.0):
				await get_tree().process_frame
				t += 1.0 / FPS
				if abs(p.global_position.y - b.y) < 0.5 and Vector2(p.global_position.x - b.x, p.global_position.z - b.z).length() < 1.2:
					reached = true
					break
			Input.action_release("move_forward")
			p.collision_mask = 5
			rec("stairs at %s walkable %s" % [lo.snapped(Vector3(0.1, 0.1, 0.1)), "up" if up else "down"], reached, "player stuck at %s (target %s)" % [p.global_position.snapped(Vector3(0.1, 0.1, 0.1)), b.snapped(Vector3(0.1, 0.1, 0.1))])
	p.global_position = home
	p.velocity = Vector3.ZERO
	p.cam_yaw = home_yaw
	if n > 0:
		info("%d stair(s) tested" % n)

## Everything dormant/idle wakes up; used by the soak test.
func wake_all() -> void:
	for e in enemies():
		e.set("dormant", false)
		if e.has_method("wake"):
			e.wake()
		e.awake = true
		if e.state in ["idle", "wander", "dormant", "down"]:
			e.state = "chase"

## Step on every trigger of the level once (those left): none may leave the player locked.
func sweep_triggers() -> void:
	var n := 0
	for t in all_triggers():
		if not is_instance_valid(t):
			continue
		var uid: String = str(t.get("uid"))
		if uid != "" and Game.has_flag("trig:" + uid):
			continue
		if not t.monitoring and t.get("once"):
			continue
		await _step_into(t)
		await fr(5)
		n += 1
		await settle(60.0, "trigger sweep %s" % (uid if uid != "" else "<anon>"))
	rec("trigger sweep: %d triggers fired, player always released" % n, true)

# =================================================================== soak
func run_soak(id: String) -> void:
	scope = id + "/soak"
	var spawn: String = {"l2_school": "from_road", "l3_church": "from_school"}.get(id, "start")
	fresh_state(args.get("flags", "").split(",", false))
	await load_level(id, spawn)
	await check_world(id)
	var frames := int(args.get("frames", "600"))
	await fr(60)
	var ne := enemies().size()
	wake_all()
	info("%d enemies awake, soaking %d frames at spawn" % [ne, frames])
	await fr(frames)
	rec("soak %d frames with %d enemies awake (see LOG lines)" % [frames, ne], true)
	await sweep_triggers()

# =================================================================== per-level runner
func run_level(id: String) -> void:
	scope = id
	var spawn: String = {"l2_school": "from_road", "l3_church": "from_school"}.get(id, "start")
	fresh_state(args.get("flags", "").split(",", false))
	await load_level(id, spawn)
	if args.has("probe"):
		var pr: PackedStringArray = args.probe.split(",")
		var o := Vector3(float(pr[0]), float(pr[1]), float(pr[2]))
		var dirs := [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]
		for dv in dirs:
			var q := PhysicsRayQueryParameters3D.create(o, o + dv * 1.5, 1)
			var h: Dictionary = pl().get_world_3d().direct_space_state.intersect_ray(q)
			var desc := "free"
			if not h.is_empty():
				var c: Node = h.collider
				var chain := ""
				var n: Node = c
				while n != null and n != lvl():
					chain = str(n.name) + "/" + chain
					n = n.get_parent()
				var size := ""
				for ch in c.get_children():
					if ch is CollisionShape3D and ch.shape is BoxShape3D:
						size = str((ch.shape as BoxShape3D).size) + " at " + str(c.global_position)
				desc = chain + " " + size + " hit " + str(h.position)
			print("PROBE ", dv, " -> ", desc)
	await check_world(id)
	await check_stairs()
	await prep_nav()
	last_spot = snap(pl().global_position)
	await play_level(id)
	await sweep_triggers()
	await reload_check(id, spawn)
	await exit_level(id)
	if id == "l6_heart" and not args.has("ending"):
		# the other ending, from a fresh load with the Mother already dead
		UI.close_modal()
		args["ending"] = "thaw"
		Game.flags.erase("ending")
		fresh_state(["mother_dead", "found_june"])
		await load_level("l6_heart", "start")
		await check_world("l6_heart (thaw)")
		await prep_nav()
		last_spot = snap(pl().global_position)
		await finish_l6()

## "Load game" at the end of the level: flags/inventory persist, the level is rebuilt from them.
## Everything that was solved must still be solved (exit open, no errors, nobody stuck).
func reload_check(id: String, spawn: String) -> void:
	await settle(30.0, "before reload")
	var inv_before := inv_ids()
	await load_level(id, spawn)
	await settle(30.0, "after reload")
	await fr(30)
	rec("level reloads from saved state", lvl() != null and pl() != null and str(lvl().name).contains(id), "lvl=%s player=%s" % [lvl(), pl()])
	rec("inventory survives reload", inv_ids() == inv_before, "%s != %s" % [inv_ids(), inv_before])
	await prep_nav()
	last_spot = Vector3.INF
	walking = false     # (the exit may be on another floor/area than the reload spawn)

func play_level(id: String) -> void:
	match id:
		"l1_substation": await play_l1()
		"l2_school": await play_l2()
		"l3_church": await play_l3()
		"l4_meridian": await play_l4()
		"l5_mine": await play_l5()
		"l6_heart": await play_l6()
		_: rec("known level", false, id)

func exit_level(id: String) -> void:
	match id:
		"l1_substation": await transit("l1_exit_gate", "l2_school", "from_road")
		"l2_school": await transit("l2_exit_gate", "l3_church", "from_school")
		"l3_church": await transit("l3_gate", "l4_meridian", "start")
		"l4_meridian": await transit("l4_exit", "l5_mine", "start")
		"l5_mine": await transit("mn_exit", "l6_heart", "start")
		"l6_heart": await finish_l6()

func run_chain() -> void:
	scope = "chain"
	Game.new_game()
	var ok := await await_level("l1_substation", "start")
	rec("new game starts in l1_substation", ok)
	if not ok:
		return
	for id in ["l1_substation", "l2_school", "l3_church", "l4_meridian", "l5_mine", "l6_heart"]:
		scope = "chain/" + id
		if Game.level_id != id:
			rec("arrived in %s" % id, false, "level_id is %s" % Game.level_id)
			return
		await settle(60.0, "arrival in " + id)
		await check_world(id)
		await prep_nav()
		last_spot = snap(pl().global_position)
		info("inventory on arrival: %s  flags: %s" % [str(Game.inventory.map(func(s): return "%s x%d" % [s.id, s.count])), _story_flags()])
		await play_level(id)
		await exit_level(id)
		if id != "l6_heart":
			await settle(30.0, "exit " + id)
	scope = "chain"
	rec("game finished: ending=%s" % str(Game.get_flag("ending", "")), str(Game.get_flag("ending", "")) != "", "Game.finish_game never reached")

func _story_flags() -> String:
	var out := []
	for k in ["feeder_closed", "boiler_on", "met_foreman", "choir_dead", "has_rosary", "met_imogen", "imogen_alive", "pipeline_open", "foreman_dead", "hauler_dead", "found_june", "mother_dead"]:
		if Game.has_flag(k):
			out.append(k)
	return ",".join(out)

# =================================================================== scenario helpers shared
func expect_flag(f: String, label := "") -> void:
	rec("flag %s%s" % [f, (" (" + label + ")") if label != "" else ""], Game.has_flag(f), "flag not set")

func expect_item(id: String, label := "") -> void:
	rec("have %s%s" % [id, (" (" + label + ")") if label != "" else ""], Game.has_item(id), "item missing; inventory=%s" % str(inv_ids()))

## Use a transition door and verify the next level + spawn.
func transit(door_uid: String, to_level: String, to_spawn: String) -> void:
	var it := find_meta("door_uid", door_uid)
	if it == null:
		rec("exit door %s exists" % door_uid, false, "not found")
		return
	await use(it, "exit door " + door_uid)
	var ok := await await_level(to_level, to_spawn)
	rec("transition -> %s:%s" % [to_level, to_spawn], ok, "Game.level_id=%s spawn=%s" % [Game.level_id, Game.spawn_id])
	if ok:
		var y0: float = pl().global_position.y
		await wait(3.0)
		rec("arrival spot stable (y=%.2f)" % pl().global_position.y, pl().global_position.y > -1.0 and abs(pl().global_position.y - y0) < 1.5)

# =================================================================== L1 - HIGHWAY 53 / SUBSTATION
func play_l1() -> void:
	# the opening beats on the road (each locks the player while talking)
	for t in ["l1_t_light", "l1_t_truck", "l1_t_radio", "l1_t_e", "l1_t_aim", "l1_t_flare", "l1_t_sign"]:
		await fire_trigger(t)
	await pick("l1_ammo_car")
	await pick("l1_flare_a")
	await fire_trigger("l1_t_ambush")
	await fire_trigger("l1_t_spur")
	# into the yard through the cut fence
	await fire_trigger("l1_t_yard")
	await fire_trigger("l1_t_body")
	# key from the operator, control house, SCADA
	await pick("l1_key", "control key")
	expect_item("control_key")
	await open_door("l1_ctrl_door", true, "control house door")
	rec("control key consumed by the door", not Game.has_item("control_key"))
	await read_note("l1_note_order")
	await read_note("l1_note_switch")
	await use_prompt("Read SCADA screen", "SCADA screen")
	expect_flag("l1_saw_order")
	# hot stick (truck bed), fuse (pried cabinet)
	await pick("l1_hotstick", "hot stick")
	expect_item("hot_stick")
	await use_prompt("Open locked cabinet", "pry the cabinet")
	expect_flag("l1_cabinet_open")
	await pick("l1_fuse", "60A fuse")
	expect_item("fuse_60a")
	# operating without the fuse must refuse the breaker, wrong order must arc flash and reset
	await use_prompt("Operate BKR-KF2", "breaker before fuse (must refuse)")
	rec("breaker refuses without control fuse", not lvl()._sw["BKR"].closed)
	await use_prompt("Control cabinet: fuse block", "install fuse")
	expect_flag("l1_fuse_in")
	await use_prompt("Operate DS-2B", "DS-2B out of order (arc flash expected)")
	await wait(1.5)
	await settle(30.0, "arc flash")
	rec("arc flash resets switchgear", not lvl()._sw["DS2B"].closed and lvl()._step == 0, "switches still closed after a failed sequence")
	await use_prompt("Operate DS-2B", "DS-2B again (second failure -> June's hint)")
	await wait(2.0)
	await settle(40.0, "June hint")
	# the real sequence
	await use_prompt("Operate DS-2A", "DS-2A")
	rec("DS-2A closed", lvl()._sw["DS2A"].closed)
	await use_prompt("Operate DS-2B", "DS-2B")
	rec("DS-2B closed", lvl()._sw["DS2B"].closed)
	await use_prompt("Operate BKR-KF2", "BKR-KF2")
	await settle(120.0, "feeder-closed cutscene")
	expect_flag("feeder_closed")

# =================================================================== L2 - SCHOOL
func play_l2() -> void:
	await settle(60.0, "L2 intro radio call")
	# courtyard shed: janitor's keyring + flares
	await open_door("l2_shed_door", true, "shed door")
	await pick("l2_school_key", "janitor keyring")
	await pick("l2_flares", "shed flares")
	expect_item("school_key")
	# custodial side door (key kept) -> lobby
	await open_door("l2_side", true, "custodial side door")
	expect_item("school_key", "keyring kept after the side door")
	# hall corridor -> shop (60A fuse + pouch), coach office (gym key)
	await open_door("l2_d_lobby_corr", true, "lobby->corridor door")
	await fire_trigger("l2_corr_ambush")
	await open_door("l2_d_shop", true, "shop door")
	await pick("l2_fuse", "60A fuse (shop)")
	await pick("l2_pouch", "tool pouch")
	await open_door("l2_d_coach", true, "coach office door")
	await pick("l2_gym_key", "gym key")
	await wait(2.0)
	# gym (padlocked)
	await open_door("l2_d_gym", true, "gym doors")
	rec("gym key consumed by gym doors", not Game.has_item("gym_key"))
	# locker room: break the ice -> valve wheel
	await use_prompt("Break the ice", "break the locker-room ice")
	expect_flag("l2_ice_broken")
	await pick("l2_valve_wheel", "valve wheel")
	expect_item("valve_handle")
	# boiler room: purge before fuse (nothing), ignite before purge (lockout), then the right order
	await open_door("l2_d_boiler", true, "boiler room door")
	await use_prompt("PURGE", "PURGE without fuse (must refuse)")
	rec("purge refuses without fuse", not Game.has_flag("l2_purged"))
	await use_prompt("Fuse holder", "fuse holder")
	expect_flag("l2_fuse_in")
	await use_prompt("IGNITE", "IGNITE before purge (lockout expected)")
	rec("early ignite does not light the boiler", not Game.has_flag("l2_flame"))
	await wait(2.5)
	await use_prompt("Feed valve", "mount valve wheel")
	expect_flag("l2_valve_on")
	await use_prompt("PURGE", "PURGE")
	await wait(6.5)
	expect_flag("l2_purged")
	await use_prompt("IGNITE", "IGNITE")
	expect_flag("l2_flame")
	await use_prompt("Feed valve", "open feed valve")
	await settle(60.0, "boiler roar cutscene")
	expect_flag("boiler_on")
	# June's chalk message, classroom 2B (needs boiler)
	await open_door("l2_d_2b", true, "classroom 2B door")
	await use_prompt("Read the blackboard", "blackboard")
	await wait(1.0)
	await settle(60.0, "blackboard")
	expect_flag("l2_read_june")
	# unchain the front doors from the INSIDE
	await use_prompt("Front doors", "unchain front doors (inside)", Vector3.INF, func(c): return c.z < -10.2)
	await settle(60.0, "unchain cutscene")
	expect_flag("l2_front_open")
	# walk out into the courtyard: the Foreman scene
	await fire_trigger("l2_finale")
	await settle(120.0, "Foreman cutscene")
	expect_flag("met_foreman")

# =================================================================== L3 - MAIN STREET / ST. BRENDAN'S
func play_l3() -> void:
	await fire_trigger("l3_t_hint")
	await fire_trigger("l3_t_foreman")
	rec("Foreman spawned by the street trigger", enemy_by_uid("l3_foreman") != null, "no foreman node")
	# the notice on the church door sets the "find the key" objective (read it like a player)
	await read_note("l3_note_door")
	# pharmacy: sacristy key on Dolores' lanyard (she wakes when you take it)
	await pick("l3_key", "sacristy key")
	expect_item("church_key")
	await pick("l3_trauma", "trauma kit")
	# hardware store: shotgun, shells, flares
	await pick("l3_shotgun", "shotgun")
	await pick("l3_shells", "shotgun shells")
	await pick("l3_flares", "flares")
	# bell-pull handle in the tower foot, then the church side door (consumes the key)
	await open_door("l3_side", true, "church side door")
	rec("sacristy key consumed by the side door", not Game.has_item("church_key"))
	await pick("l3_bell_rope", "bell pull handle")
	await use_prompt("Ring the church bell", "fit the bell-pull handle")
	expect_flag("l3_bell_fitted")
	# nave: the Choir
	await fire_trigger("l3_t_choir")
	expect_flag("l3_fight_started")
	var boss := enemy_by_uid("l3_boss")
	rec("Choir boss exists and is awake", boss != null and boss.state != "dormant", "boss=%s state=%s" % [boss, boss.state if boss else "-"])
	await use_prompt("Ring the church bell", "ring the bell (stuns the Choir)")
	if boss != null:
		await kill_choir(boss)
	await wait(3.0)
	await settle(30.0, "Choir death")
	expect_flag("choir_dead")
	# Ruth's rosary appears on the altar
	await wait(2.0)
	await pick("l3_rosary", "Ruth's rosary")
	expect_item("rosary")
	await settle(90.0, "June's radio call")
	expect_flag("has_rosary")

## Kill The Choir through its API on the real weak points (handgun headshot = 44).
func kill_choir(boss: Node) -> void:
	var shots := 0
	for i in boss.model.heads.size():
		if not boss.model.heads[i].weak:
			continue
		var n := 0
		while boss.model.heads[i].alive and n < 60 and boss.state != "dead":
			boss.take_hit(44.0, boss.model.head_world(i), Vector3(0, 0, 1), true)
			n += 1
			shots += 1
			await fr(1)
	rec("Choir dies after all five heads are destroyed (%d shots)" % shots, boss.state == "dead", "state=%s hp=%s" % [boss.state, boss.hp])

# =================================================================== L4 - MERIDIAN
func toggle_sw(sub: String) -> void:
	await use_prompt("Toggle " + sub, "toggle " + sub)

func play_l4() -> void:
	await fire_trigger("l4_gate_greet")
	await pick("l4_badge", "MERIDIAN badge")
	expect_item("badge_meridian")
	await open_door("l4_front", true, "main entrance (badge)")
	expect_item("badge_meridian", "badge kept by the reader")
	await fire_trigger("l4_lobby_greet")
	await fire_trigger("l4_hallc_hint")
	# electrical room: wrong sum first (26 kW), MERIDIAN must refuse; then exactly 40 kW
	await open_door("l4_elec", true, "electrical room door")
	await use_prompt("Read the load-shed console", "load-shed console")
	await toggle_sw("PDU-9")
	await use_prompt("Use intercom", "hall C intercom with 26 kW (must refuse)", Vector3(-3.4, 1.3, -35.0))
	rec("MERIDIAN refuses the wrong sum", not Game.has_flag("l4_grant_hallc"))
	await toggle_sw("PDU-7")
	await use_prompt("Use intercom", "hall C intercom with 40 kW", Vector3(-3.4, 1.3, -35.0))
	expect_flag("l4_grant_hallc")
	await open_door("l4_hallc", true, "Hall C door")
	# cooling plant: coolant key -> override cabinet -> breach
	await open_door("l4_plantdoor", true, "cooling plant door")
	await pick("l4_coolant_key", "cooling plant key")
	await use_prompt("Chiller override cabinet", "chiller override cabinet")
	expect_flag("l4_override")
	await settle(60.0, "breach cutscene")
	await open_door("l4_contain", true, "containment door")
	# armory: launcher (triggers the Foreman's arrival)
	await open_door("l4_armory", true, "armory (badge)")
	await pick("l4_launcher", "flare launcher")
	await wait(4.0)
	await settle(60.0, "Foreman arrival")
	# clear the corridor so Imogen survives
	for u in ["l4_zK1", "l4_zK2"]:
		var z := enemy_by_uid(u)
		if z != null and z.state != "dead":
			z.take_hit(9999.0, z.global_position + Vector3(0, 1.6, 0), Vector3(0, 0, 1), true)
	await wait(1.0)
	# NOC: exactly 54 kW (PDU-7 + CH-3)
	await fire_trigger("l4_noc_glass")
	await toggle_sw("PDU-9")
	await toggle_sw("CH-3")
	await use_prompt("Use intercom", "NOC intercom with 54 kW", Vector3(-3.2, 1.3, -65.0))
	expect_flag("l4_grant_noc")
	await open_door("l4_noc", true, "NOC door")
	for it in interactables():
		if str(it.get("prompt")).find("Hart") >= 0 and it.get("enabled"):
			await use(it, "talk to Dr. Hart (" + str(it.get("prompt")) + ")", false)
	expect_flag("met_imogen")
	expect_item("pipeline_card", "from Imogen")
	await wait(1.0)
	expect_flag("imogen_alive")
	# pipeline head: swipe the card
	await use_prompt("Swipe override card", "pipeline card reader")
	expect_flag("pipeline_open")

# =================================================================== L5 - LOWER KETTLE MINE
func play_l5() -> void:
	await fire_trigger("mn_hum1")
	# pump station: lamp battery (siren + husk ambush wakes)
	await fire_trigger("mn_pump_enter")
	await pick("mn_battery", "cap-lamp battery")
	# south drift: hoist brake lever
	await pick("mn_lever", "hoist brake lever")
	# hoist hall -> lamp room (safe room): tag 114, charger
	await fire_trigger("mn_enter_hall")
	await open_door("mn_lampdoor", true, "lamp room door")
	await use_prompt("Brass tag 114", "Tom's brass tag")
	await settle(90.0, "tag 114 hallucination")
	expect_item("tom_tag", "Tom's tag")
	await use_prompt("Cap-lamp charger", "charger + signal panel")
	expect_flag("mine_power")
	# hoist brake station: lever + power -> the Foreman fight
	await use_prompt("Hoist brake station", "seat the brake lever")
	expect_flag("hoist_ready")
	await settle(60.0, "foreman encounter")
	var fm := enemy_by_uid("mn_foreman")
	rec("Foreman spawned for the hoist fight", fm != null, "no mn_foreman")
	if fm != null:
		# furnace must actually burn him
		await use_prompt("Light the furnace", "light the furnace")
		fm.global_position = Vector3(29.0, 0.05, -6.2)
		var hp0: float = fm.hp
		await wait(3.0)
		rec("furnace damages the Foreman (%.0f -> %.0f hp)" % [hp0, fm.hp], fm.hp < hp0, "no fire damage near the furnace")
		# lure onto the cage and drop it
		pre_interact = func():
			fm.global_position = Vector3(36.5, 0.05, 0.0)
			fm.velocity = Vector3.ZERO
		await use_prompt("Hoist brake station", "release the brake with the Foreman on the cage")
		await wait(4.0)
		await settle(60.0, "Foreman death")
		if not Game.has_flag("foreman_dead"):
			warn("brake drop did not kill the Foreman (state=%s hp=%s); burning him" % [fm.state if is_instance_valid(fm) else "freed", fm.hp if is_instance_valid(fm) else 0])
			for k in 40:
				if is_instance_valid(fm) and fm.state != "dead":
					fm.burn(100.0, fm.global_position + Vector3(1, 0, 0))
				await fr(2)
			await settle(60.0, "Foreman death (burn)")
	expect_flag("foreman_dead")
	# cage down (the cage needs ~9 s to come back up after the brake drop)
	await wait_until(func(): return not lvl()._cage_busy, 30.0)
	await use_prompt("Ride the cage down", "ride the cage down")
	await wait(4.0)
	await settle(90.0, "cage ride + June radio")
	rec("arrived on the lower level", pl().global_position.y < -20.0, "y=%.1f" % pl().global_position.y)
	last_spot = snap(pl().global_position)
	# powder magazine: dynamite
	await open_door("mn_magdoor", true, "magazine door")
	await pick("mn_dyn", "blasting charges")
	expect_item("dynamite")
	# cavern: the Hauler
	await fire_trigger("mn_cavern_enter")
	var h := enemy_by_uid("mn_hauler")
	rec("Hauler boss exists and wakes", h != null and h.state != "dormant", "hauler=%s" % h)
	if h != null:
		pre_interact = func(): h.global_position = Vector3(104.0, -29.95, -2.0)
		await use_prompt("Marked pillar", "plant charges on the marked pillar")
		await wait(6.5)
		rec("charges consumed", not Game.has_item("dynamite"), "dynamite still in inventory")
		var shots := 0
		while h.state != "dead" and shots < 80:
			h.take_hit(120.0, h.model.heart_world(), Vector3(0, 0, 1), true)
			shots += 1
			await fr(2)
		rec("Hauler dies from weak-point hits (%d magnum shots after the pillar)" % shots, h.state == "dead", "state=%s hp=%s" % [h.state, h.hp])
	await settle(60.0, "Hauler death")
	await wait(3.0)
	await settle(60.0, "Hauler death dialogue")
	expect_flag("hauler_dead")
	# refuge: June
	await fire_trigger("mn_ref_voice")
	await open_door("mn_refugedoor", true, "refuge door")
	await use_prompt("Talk to June", "talk to June", Vector3(112.3, -29.0, -31.2))
	await settle(60.0, "reunion")
	expect_flag("found_june")
	await fire_trigger("mn_shaft_voice")

# =================================================================== L6 - THE HEART
func play_l6() -> void:
	for t in ["l6_t_intro", "l6_t_tom1", "l6_t_nook"]:
		await fire_trigger(t)
	await use_prompt("Use field radio", "field radio (save point)")
	await use_prompt("Open supply crate", "supply crate")
	# walk into the arena: the reveal
	await fire_trigger("l6_t_reveal")
	await settle(120.0, "reveal cutscene")
	expect_flag("l6_revealed")
	var boss := enemy_by_uid("l6_mother")
	rec("Hollow Mother awake", boss != null and boss.state != "dormant", "boss=%s state=%s" % [boss, boss.state if boss else "-"])
	if boss != null:
		# steam valve (east) scorches the lattice
		await use_prompt("Vent steam valve", "steam valve", Vector3(18.0, 1.0, -20.0))
		await wait(2.0)
		# phase 1: Ruth's glowing chest
		var n := 0
		while boss.phase == 1 and boss.state != "dead" and n < 200:
			boss.take_hit(120.0, boss.model.heart_world(), Vector3(0, 0, 1), true)
			n += 1
			if verbose and n < 12:
				info("mother p1 hit %d: hp=%.0f state=%s dormant=%s inv=%s" % [n, boss.hp, boss.state, boss.dormant, boss.invulnerable])
			await fr(2)
		rec("phase 1 ends after %d weak-point hits" % n, boss.phase == 2 or boss.state == "dead", "phase=%s hp=%s" % [boss.phase, boss.hp])
		await wait(4.0)
		n = 0
		while boss.state != "dead" and n < 200:
			boss.take_hit(120.0, boss.global_position + Vector3(0, 2.0, 0), Vector3(0, 0, 1), true)
			n += 1
			await fr(2)
		rec("phase 2 dies after %d hits" % n, boss.state == "dead", "state=%s hp=%s" % [boss.state, boss.hp])
	await wait(2.0)
	await settle(120.0, "Mother death scene")
	expect_flag("mother_dead")

## The ending choice UI must appear and both buttons must reach Game.finish_game.
func finish_l6() -> void:
	var ending: String = args.get("ending", "dark")
	var st := find_it("Use pipeline control")
	await use(st, "pipeline control station", true, Callable(), false)
	var panel := await wait_until(func(): return lvl().get_node_or_null("EndingChoice") != null, 90.0)
	rec("ending choice UI appears", panel, "EndingChoice layer never created")
	if not panel:
		return
	await fr(3)
	var layer: Node = lvl().get_node("EndingChoice")
	var btns := _walk(layer, func(n): return n is Button)
	rec("ending choice has two buttons (%d)" % btns.size(), btns.size() == 2)
	var want := "CUT MERIDIAN" if ending == "dark" else "OPEN THE PIPELINE"
	for b in btns:
		if b.text.begins_with(want):
			b.pressed.emit()
	await fr(5)
	rec("Game.finish_game reached (ending=%s)" % ending, str(Game.get_flag("ending", "")) == ending, "ending flag=%s" % str(Game.get_flag("ending", "")))
	rec("ending screen shown", UI.modal != null and is_instance_valid(UI.modal) and UI.modal.name == "Ending", "modal=%s" % UI.modal)
