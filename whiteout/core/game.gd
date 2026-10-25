extends Node
## Global game state: flags, inventory, health, level flow and save/load.
## Autoloaded as `Game`.

signal inventory_changed
signal health_changed(hp: int, max_hp: int)
signal flag_changed(key: String, value)
signal objective_changed(text: String)

const Items = preload("res://core/items.gd")
const SAVE_PATH := "user://save_%d.json"
const MAX_HP := 100

var hp: int = MAX_HP
var inventory: Array = []          # Array of {id:String, count:int}
var inv_slots: int = 8
var item_box: Array = []           # shared storage across all save rooms
var equipped: String = ""          # weapon item id currently equipped
var flags: Dictionary = {}         # persistent world state
var level_id: String = ""
var spawn_id: String = ""
var objective: String = ""
var play_time: float = 0.0
var saves_used: int = 0
var deaths: int = 0
var difficulty: int = 1            # 0 assisted, 1 standard, 2 hardcore

var current_level: Node = null
var player: Node = null
var paused_by_ui: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()

func _process(delta: float) -> void:
	if current_level != null and not get_tree().paused:
		play_time += delta

# ---------------------------------------------------------------- input map
func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT], "interact": [KEY_E, KEY_ENTER], "reload": [KEY_R],
		"inventory": [KEY_TAB, KEY_I], "pause": [KEY_ESCAPE, KEY_P], "knife": [KEY_F],
		"quick_turn": [KEY_Q], "flashlight": [KEY_L], "heal": [KEY_H],
		"weapon_1": [KEY_1], "weapon_2": [KEY_2], "weapon_3": [KEY_3], "weapon_4": [KEY_4],
		"ui_back": [KEY_BACKSPACE],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	for pair in [["aim", MOUSE_BUTTON_RIGHT], ["fire", MOUSE_BUTTON_LEFT]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
		var mb := InputEventMouseButton.new()
		mb.button_index = pair[1]
		InputMap.action_add_event(pair[0], mb)
	# Gamepad basics
	var pad := {"interact": JOY_BUTTON_A, "knife": JOY_BUTTON_X, "reload": JOY_BUTTON_Y,
		"inventory": JOY_BUTTON_BACK, "pause": JOY_BUTTON_START, "sprint": JOY_BUTTON_LEFT_STICK}
	for action in pad:
		var jb := InputEventJoypadButton.new()
		jb.button_index = pad[action]
		InputMap.action_add_event(action, jb)

# ---------------------------------------------------------------- new game / flow
func new_game() -> void:
	hp = MAX_HP
	inventory = []
	inv_slots = 8
	item_box = [{"id": "spray", "count": 1}]
	equipped = ""
	flags = {}
	play_time = 0.0
	saves_used = 0
	deaths = 0
	objective = ""
	add_item("knife", 1)
	add_item("handgun", 1)
	add_item("radio", 1)
	set_ammo_loaded("handgun", 12)
	add_item("ammo_9mm", 15)
	equipped = "handgun"
	goto_level("l1_substation", "start")

func goto_level(id: String, spawn: String = "start") -> void:
	level_id = id
	spawn_id = spawn
	UI.fade_out(0.6)
	await get_tree().create_timer(0.65, true).timeout
	_load_level()
	UI.fade_in(0.8)

func _load_level() -> void:
	get_tree().paused = false
	if current_level != null and is_instance_valid(current_level):
		current_level.queue_free()
		current_level = null
	player = null
	var main := get_tree().current_scene
	if main == null or main.name != "World":
		var w := Node.new()
		w.name = "World"
		get_tree().root.add_child(w)
		if main != null:
			main.queue_free()
		get_tree().current_scene = w
		main = w
	var script: Script = load("res://levels/%s.gd" % level_id)
	var lvl: Node3D = script.new()
	lvl.name = level_id
	current_level = lvl
	main.add_child(lvl)
	UI.show_hud(true)

func game_over() -> void:
	deaths += 1
	UI.show_game_over()

func finish_game(ending: String) -> void:
	flags["ending"] = ending
	UI.show_ending(ending)

# ---------------------------------------------------------------- flags / objective
func set_flag(key: String, value = true) -> void:
	flags[key] = value
	flag_changed.emit(key, value)

func has_flag(key: String) -> bool:
	if not flags.has(key):
		return false
	var v = flags[key]
	return not (v is bool and v == false)

func get_flag(key: String, default = null):
	return flags.get(key, default)

func set_objective(text: String) -> void:
	objective = text
	objective_changed.emit(text)
	UI.toast("OBJECTIVE: " + text, 4.0)

# ---------------------------------------------------------------- health
func damage(amount: int) -> void:
	if hp <= 0:
		return
	var mult: float = [0.6, 1.0, 1.5][difficulty]
	hp = max(0, hp - int(round(amount * mult)))
	health_changed.emit(hp, MAX_HP)
	if hp <= 0:
		game_over()

func heal(amount: int) -> void:
	hp = min(MAX_HP, hp + amount)
	health_changed.emit(hp, MAX_HP)

func health_state() -> String:
	if hp > 66:
		return "FINE"
	elif hp > 33:
		return "CAUTION"
	return "DANGER"

# ---------------------------------------------------------------- inventory
func item_def(id: String) -> Dictionary:
	return Items.get_def(id)

func count_item(id: String) -> int:
	var n := 0
	for s in inventory:
		if s.id == id:
			n += s.count
	return n

func has_item(id: String) -> bool:
	return count_item(id) > 0

func slots_used() -> int:
	return inventory.size()

func can_add(id: String, count: int = 1) -> bool:
	var d := item_def(id)
	var maxs: int = d.get("stack", 1)
	var room := 0
	for s in inventory:
		if s.id == id:
			room += maxs - s.count
	room += (inv_slots - inventory.size()) * maxs
	return room >= count

## Adds as much as fits. Returns the leftover count that did not fit.
func add_item(id: String, count: int = 1) -> int:
	var d := item_def(id)
	var maxs: int = d.get("stack", 1)
	for s in inventory:
		if count <= 0:
			break
		if s.id == id and s.count < maxs:
			var put: int = min(maxs - s.count, count)
			s.count += put
			count -= put
	while count > 0 and inventory.size() < inv_slots:
		var put: int = min(maxs, count)
		inventory.append({"id": id, "count": put})
		count -= put
	inventory_changed.emit()
	return count

func remove_item(id: String, count: int = 1) -> bool:
	if count_item(id) < count:
		return false
	for i in range(inventory.size() - 1, -1, -1):
		if count <= 0:
			break
		var s = inventory[i]
		if s.id == id:
			var take: int = min(s.count, count)
			s.count -= take
			count -= take
			if s.count <= 0:
				inventory.remove_at(i)
	if equipped != "" and not has_item(equipped):
		equipped = ""
	inventory_changed.emit()
	return true

func set_ammo_loaded(weapon: String, n: int) -> void:
	flags["mag:" + weapon] = n

func ammo_loaded(weapon: String) -> int:
	return int(flags.get("mag:" + weapon, 0))

## Use an item from inventory (healing / key items handled by the level).
func use_item(id: String) -> bool:
	var d := item_def(id)
	match d.get("kind", ""):
		"heal":
			if hp >= MAX_HP:
				UI.toast("You are already in good condition.")
				return false
			heal(d.get("heal", 30))
			remove_item(id, 1)
			Sfx.play("heal")
			return true
		"weapon":
			equipped = id
			inventory_changed.emit()
			Sfx.play("equip")
			return true
		"upgrade":
			if id == "pouch":
				inv_slots += 2
				remove_item(id, 1)
				UI.toast("Inventory expanded to %d slots." % inv_slots)
				return true
		"resource":
			if id == "flare" and player != null and is_instance_valid(player):
				remove_item(id, 1)
				var FX = load("res://world/fx.gd")
				FX.flare(current_level, player.global_position + player.model.global_transform.basis.z * 0.8)
				UI.toast("You strike a flare.")
				return true
			UI.toast("Combine it with something.")
		"key":
			# Let the level/interactable under focus consume it.
			if current_level != null and current_level.has_method("try_use_item"):
				return current_level.try_use_item(id)
			UI.toast("There is nothing to use it on here.")
	return false

func combine(a: String, b: String) -> bool:
	var res := Items.combine_result(a, b)
	if res == "":
		UI.toast("These can't be combined.")
		return false
	remove_item(a, 1)
	remove_item(b, 1)
	add_item(res, Items.get_def(res).get("yield", 1))
	Sfx.play("combine")
	UI.toast("Created: " + Items.get_def(res).name)
	return true

func ammo_for(weapon: String) -> String:
	return item_def(weapon).get("ammo", "")

# ---------------------------------------------------------------- save / load
func save_game(slot: int) -> void:
	saves_used += 1
	var data := {
		"hp": hp, "inventory": inventory, "inv_slots": inv_slots, "item_box": item_box,
		"equipped": equipped, "flags": flags, "level_id": level_id, "spawn_id": spawn_id,
		"objective": objective, "play_time": play_time, "saves_used": saves_used,
		"deaths": deaths, "difficulty": difficulty,
		"stamp": Time.get_datetime_string_from_system(false, true),
	}
	var f := FileAccess.open(SAVE_PATH % slot, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		UI.toast("Progress recorded.")

func save_info(slot: int) -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH % slot):
		return {}
	var f := FileAccess.open(SAVE_PATH % slot, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

func load_game(slot: int) -> bool:
	var d := save_info(slot)
	if d.is_empty():
		return false
	hp = int(d.hp)
	inventory = []
	for s in d.inventory:
		inventory.append({"id": s.id, "count": int(s.count)})
	item_box = []
	for s in d.item_box:
		item_box.append({"id": s.id, "count": int(s.count)})
	inv_slots = int(d.inv_slots)
	equipped = d.equipped
	flags = d.flags
	objective = d.get("objective", "")
	play_time = float(d.play_time)
	saves_used = int(d.saves_used)
	deaths = int(d.get("deaths", 0))
	difficulty = int(d.get("difficulty", 1))
	goto_level(d.level_id, d.spawn_id)
	return true

func format_time(t: float) -> String:
	var s := int(t)
	return "%02d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
