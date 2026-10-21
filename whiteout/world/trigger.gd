extends Area3D
## Fires `action.call(player)` when the player enters. Optionally once only (persisted by uid).

var uid := ""
var once := true
var action: Callable

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	body_entered.connect(_on_enter)

func _on_enter(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if once:
		if uid != "":
			if Game.has_flag("trig:" + uid):
				return
			Game.set_flag("trig:" + uid)
		set_deferred("monitoring", false)
	if action.is_valid():
		action.call(body)
