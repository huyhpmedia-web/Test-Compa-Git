extends Node
## Audio manager. Autoloaded as `Sfx`.
## Sounds are loaded from res://audio/<name>.ogg or .wav; missing sounds are silently skipped.
## Music/ambience loop on dedicated players with crossfades.

var _cache := {}
var _pool: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _amb: AudioStreamPlayer
var music_name := ""
var amb_name := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	_amb = AudioStreamPlayer.new()
	for p in [_music, _music_b, _amb]:
		add_child(p)

func get_stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var s: AudioStream = null
	# variants: name_1, name_2 ... chosen randomly by caller via `name`
	for ext in ["ogg", "wav"]:
		var path := "res://audio/%s.%s" % [name, ext]
		if ResourceLoader.exists(path):
			s = load(path)
			break
	_cache[name] = s
	return s

func _pick(name: String) -> AudioStream:
	# support random variants name_a / name_b / name_c
	var vars := []
	for suf in ["", "_a", "_b", "_c", "_d"]:
		var st := get_stream(name + suf)
		if st != null:
			vars.append(st)
	if vars.is_empty():
		return null
	return vars[randi() % vars.size()]

func play(name: String, db: float = 0.0, pitch: float = 1.0) -> void:
	var st := _pick(name)
	if st == null:
		return
	for p in _pool:
		if not p.playing:
			p.stream = st
			p.volume_db = db
			p.pitch_scale = pitch
			p.play()
			return
	_pool[0].stream = st
	_pool[0].play()

## Positional one-shot at a world position (uses the current scene).
func play_at(name: String, pos: Vector3, db: float = 0.0, pitch: float = 1.0) -> void:
	var st := _pick(name)
	if st == null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.volume_db = db
	p.pitch_scale = pitch
	p.unit_size = 6.0
	p.max_distance = 60.0
	p.attenuation_filter_cutoff_hz = 6000.0
	scene.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)

## Looping positional emitter attached to a node (e.g. a generator hum).
func attach_loop(name: String, node: Node3D, db: float = -6.0) -> AudioStreamPlayer3D:
	var st := _pick(name)
	if st == null:
		return null
	_set_loop(st)
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.volume_db = db
	p.unit_size = 4.0
	p.max_distance = 30.0
	p.autoplay = true
	node.add_child(p)
	return p

func _set_loop(st: AudioStream) -> void:
	if st is AudioStreamWAV:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		if st.loop_end <= 0:
			st.loop_end = int(st.get_length() * st.mix_rate)
	elif st is AudioStreamOggVorbis:
		st.loop = true

func music(name: String, db: float = -8.0, fade: float = 2.0) -> void:
	if name == music_name:
		return
	music_name = name
	var old := _music
	_music = _music_b
	_music_b = old
	if old.playing:
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -60.0, fade)
		tw.tween_callback(old.stop)
	if name == "":
		return
	var st := get_stream(name)
	if st == null:
		return
	_set_loop(st)
	_music.stream = st
	_music.volume_db = -60.0
	_music.play()
	var tw2 := create_tween()
	tw2.tween_property(_music, "volume_db", db, fade)

func ambience(name: String, db: float = -10.0) -> void:
	if name == amb_name:
		return
	amb_name = name
	_amb.stop()
	if name == "":
		return
	var st := get_stream(name)
	if st == null:
		return
	_set_loop(st)
	_amb.stream = st
	_amb.volume_db = db
	_amb.play()

## Gunshots etc. alert enemies within radius.
func alert_noise(pos: Vector3, radius: float) -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.has_method("hear") and e.global_position.distance_to(pos) < radius:
			e.hear(pos)
