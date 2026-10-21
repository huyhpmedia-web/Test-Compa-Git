extends Node
## Tiny helper: calls `fn(delta)` every frame. Added as the LAST child of a model so it
## runs after the model's own _process (tree order) and can override its pose.
var fn: Callable

func _process(delta: float) -> void:
	if fn.is_valid():
		fn.call(delta)
