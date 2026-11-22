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

# ---- R8-C: bus layout, acoustic spaces (reverb zones) and occlusion
## Acoustic presets for AudioEffectReverb on the SFX bus (ambience bus gets a scaled-down send).
## room = room_size, damp = damping, wet = reverb level, pre = predelay ms, hp = hipass.
const SPACES := {
	"outdoor":    {"room": 0.22, "damp": 0.9,  "wet": 0.05, "pre": 18.0, "hp": 0.25},  # snow eats reflections: dry
	"room":       {"room": 0.30, "damp": 0.6,  "wet": 0.17, "pre": 6.0,  "hp": 0.05},  # small room / office / booth
	"corridor":   {"room": 0.45, "damp": 0.5,  "wet": 0.22, "pre": 12.0, "hp": 0.05},
	"basement":   {"room": 0.55, "damp": 0.4,  "wet": 0.26, "pre": 10.0, "hp": 0.0},   # bare concrete
	"hall":       {"room": 0.86, "damp": 0.28, "wet": 0.34, "pre": 45.0, "hp": 0.0},   # gym / main hall / big halls
	"church":     {"room": 0.97, "damp": 0.15, "wet": 0.44, "pre": 75.0, "hp": 0.0},   # stone nave, long tail
	"mine":       {"room": 0.72, "damp": 0.45, "wet": 0.32, "pre": 22.0, "hp": 0.1},   # rock tunnels, flutter
	"cavern":     {"room": 1.0,  "damp": 0.2,  "wet": 0.5,  "pre": 95.0, "hp": 0.0},   # brine cavern
	"datacenter": {"room": 0.62, "damp": 0.78, "wet": 0.2,  "pre": 20.0, "hp": 0.15},  # fan noise masks the tail
}
const BUS_SFX := "SFX"
const BUS_MUFFLED := "Muffled"
const BUS_AMB := "Ambience"
const BUS_MUSIC := "Music"
var space := "outdoor"            # current acoustic space (top of the zone stack, else the level base)
var base_space := "outdoor"
var _space_stack: Array = []      # [[key, space], ...] most recent last
var _rev: AudioEffectReverb
var _rev_amb: AudioEffectReverb
var _lp: AudioEffectLowPassFilter
var _occ_t := 0.0
var _tracked: Array = []          # looping 3D emitters re-checked for occlusion
var occlusion := true

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
	_setup_buses()
	for p in _pool:
		p.bus = BUS_SFX
	_music.bus = BUS_MUSIC
	_music_b.bus = BUS_MUSIC
	_amb.bus = BUS_AMB

## Bus layout (built in code so it is identical in editor, export and headless runs):
##   Master <- Music
##   Master <- Ambience   [Reverb, low send]
##   Master <- SFX        [Reverb: the per-space tail]
##   SFX    <- Muffled    [LowPass 700 Hz]  positional sounds behind a wall
func _setup_buses() -> void:
	if AudioServer.get_bus_index(BUS_SFX) != -1:
		_rev = AudioServer.get_bus_effect(AudioServer.get_bus_index(BUS_SFX), 0)
		_rev_amb = AudioServer.get_bus_effect(AudioServer.get_bus_index(BUS_AMB), 0)
		_lp = AudioServer.get_bus_effect(AudioServer.get_bus_index(BUS_MUFFLED), 0)
		return
	var add := func(nm: String, send: String) -> int:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, nm)
		AudioServer.set_bus_send(i, send)
		return i
	add.call(BUS_MUSIC, "Master")
	var ia: int = add.call(BUS_AMB, "Master")
	var isf: int = add.call(BUS_SFX, "Master")
	var im: int = add.call(BUS_MUFFLED, BUS_SFX)
	_rev = AudioEffectReverb.new()
	_rev.dry = 1.0
	_rev.spread = 0.8
	_rev.predelay_feedback = 0.25
	AudioServer.add_bus_effect(isf, _rev, 0)
	_rev_amb = AudioEffectReverb.new()
	_rev_amb.dry = 1.0
	_rev_amb.spread = 1.0
	AudioServer.add_bus_effect(ia, _rev_amb, 0)
	_lp = AudioEffectLowPassFilter.new()
	_lp.cutoff_hz = 700.0
	_lp.resonance = 0.5
	AudioServer.add_bus_effect(im, _lp, 0)
	AudioServer.set_bus_volume_db(im, -3.0)
	_apply_space(1.0)

## Level default acoustic space (clears zone overrides). Called by levels/level.gd.
func set_base_space(id: String) -> void:
	base_space = id
	_space_stack.clear()
	_tracked.clear()
	space = id
	_apply_space(1.0)

## Reverb zones (world/audio_zone.gd) push/pop their space while the player stands inside.
## When zones overlap, the one with the highest priority (the smallest volume) wins.
func enter_space(key: String, id: String, prio := 0.0) -> void:
	exit_space(key)
	_space_stack.append([key, id, prio])
	_pick_space()

func exit_space(key: String) -> void:
	for i in range(_space_stack.size() - 1, -1, -1):
		if _space_stack[i][0] == key:
			_space_stack.remove_at(i)
	_pick_space()

func _pick_space() -> void:
	space = base_space
	var best := -INF
	for e in _space_stack:
		if float(e[2]) >= best:
			best = float(e[2])
			space = e[1]

func _apply_space(k: float) -> void:
	if _rev == null:
		return
	var d: Dictionary = SPACES.get(space, SPACES.outdoor)
	_rev.room_size = lerpf(_rev.room_size, d.room, k)
	_rev.damping = lerpf(_rev.damping, d.damp, k)
	_rev.wet = lerpf(_rev.wet, d.wet, k)
	_rev.predelay_msec = lerpf(_rev.predelay_msec, d.pre, k)
	_rev.hipass = lerpf(_rev.hipass, d.hp, k)
	_rev_amb.room_size = _rev.room_size
	_rev_amb.damping = _rev.damping
	_rev_amb.wet = _rev.wet * 0.35
	_rev_amb.predelay_msec = _rev.predelay_msec

func _process(delta: float) -> void:
	_apply_space(clampf(delta * 2.5, 0.0, 1.0))
	_occ_t -= delta
	if _occ_t <= 0.0 and occlusion:
		_occ_t = 0.2
		for i in range(_tracked.size() - 1, -1, -1):
			var p = _tracked[i]
			if not is_instance_valid(p) or not p.is_inside_tree():
				_tracked.remove_at(i)
				continue
			p.bus = BUS_MUFFLED if is_occluded(p.global_position, 0.0) else BUS_SFX

## True when level geometry (collision layer 1) sits between the listener and `pos`.
func is_occluded(pos: Vector3, lift := 0.9) -> bool:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp else null
	if cam == null or not cam.is_inside_tree():
		return false
	var from := cam.global_position
	var to := pos + Vector3(0, lift, 0)
	var dist := from.distance_to(to)
	if dist < 1.5 or dist > 70.0:
		return false
	var space_state := cam.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.hit_back_faces = false
	var hit := space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	return from.distance_to(hit.position) < dist - 0.5

## Register a looping 3D emitter so it is muffled while a wall is between it and the listener.
func track_occlusion(p: AudioStreamPlayer3D) -> void:
	if p != null and not _tracked.has(p):
		_tracked.append(p)

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
	p.bus = BUS_SFX
	if occlusion and is_occluded(pos):
		p.bus = BUS_MUFFLED
		p.volume_db = db - 3.0
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
	p.bus = BUS_SFX
	node.add_child(p)
	track_occlusion(p)
	return p

## Positional ambience one-shot (drip, creak, distant moan...). Muffled behind walls like any 3D sound.
func ambient_at(name: String, pos: Vector3, db := -10.0, pitch := 1.0, max_dist := 30.0) -> void:
	var st := _pick(name)
	var scene := get_tree().current_scene
	if st == null or scene == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.volume_db = db
	p.pitch_scale = pitch
	p.unit_size = 3.0
	p.max_distance = max_dist
	p.attenuation_filter_cutoff_hz = 9000.0
	p.bus = BUS_MUFFLED if occlusion and is_occluded(pos, 0.0) else BUS_SFX
	scene.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)

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
