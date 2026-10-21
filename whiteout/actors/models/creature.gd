extends Node3D
## Base for procedurally animated non-humanoid models (same driving API as humanoid.gd):
##   move_speed (m/s), pose (string), play(anim) for one-shots. Subclasses build meshes in
##   _ready()/build() and animate in _animate(delta).

var move_speed := 0.0
var pose := "normal"
var aim := false
var t := 0.0
var _one := ""
var _one_t := 0.0
var _one_len := 0.5

func play(anim: String, length := -1.0) -> void:
	_one = anim
	_one_t = 0.0
	_one_len = length if length > 0.0 else float({"hurt": 0.3, "stagger": 0.9, "attack": 0.8, "roar": 1.6, "heavy": 1.1}.get(anim, 0.6))

func is_playing(anim := "") -> bool:
	return _one != "" and (anim == "" or _one == anim)

## 0..1..0 bump over the one-shot's length (0 if the named one-shot is not playing).
func one_k(anim: String) -> float:
	if _one != anim:
		return 0.0
	return sin(clamp(_one_t / _one_len, 0.0, 1.0) * PI)

## 0..1 progress of the named one-shot (0 when not playing).
func one_p(anim: String) -> float:
	if _one != anim:
		return 0.0
	return clamp(_one_t / _one_len, 0.0, 1.0)

func _process(delta: float) -> void:
	t += delta
	if _one != "":
		_one_t += delta
		if _one_t >= _one_len:
			_one = ""
	_animate(delta)

func _animate(_delta: float) -> void:
	pass
