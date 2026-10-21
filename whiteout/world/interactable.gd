extends Node3D
## Generic interactable point. The player shows `prompt` when close and facing it,
## and pressing Interact calls `action.call(player)`.

var prompt := "Examine"
var radius := 1.6
var enabled := true
var action: Callable

func _ready() -> void:
	add_to_group("interactable")

func interact(player: Node) -> void:
	if enabled and action.is_valid():
		action.call(player)
