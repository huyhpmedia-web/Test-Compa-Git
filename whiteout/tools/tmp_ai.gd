extends Node
var lv
var P

func w(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func log_(s: String) -> void:
	print("T: ", s)

func put(n: Node3D) -> void:
	pass

func spawn(type: String, pos: Vector3, params := {}) -> Node3D:
	var e = lv.enemy("", type, pos, 0.0, params)
	return e

func _ready() -> void:
	name = "World"
	Game.level_id = "tmp_ai_level"
	Game.spawn_id = "start"
	Game.add_item("handgun"); Game.set_ammo_loaded("handgun", 12); Game.equipped = "handgun"
	await get_tree().process_frame
	Game._load_level()
	for i in 5:
		await get_tree().process_frame
	for c in get_children():
		if c.has_method("enemy"):
			lv = c
	P = Game.player
	P.global_position = Vector3(0, 0.1, 10)
	await w(0.5)
	var which: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "all"
	for t in which.split(","):
		log_("=== " + t)
		await call("t_" + t)
		for e in get_tree().get_nodes_in_group("enemy"):
			e.queue_free()
		await w(0.3)
	log_("HARNESS_DONE")
	get_tree().quit()

func watch(e: Node, secs: float, every := 0.5) -> void:
	var t := 0.0
	var last := ""
	while t < secs and is_instance_valid(e):
		var s: String = str(e.state)
		var d: float = e.global_position.distance_to(P.global_position)
		if s != last:
			log_("%.1f state=%s dist=%.1f hp=%.0f" % [t, s, d, e.hp])
			last = s
		await w(0.1)
		t += 0.1

func t_foreman() -> void:
	P.global_position = Vector3(0, 0.1, 10)
	var f = spawn("foreman", Vector3(0, 0, -14), {"stalk": true})
	await w(0.3)
	log_("foreman lamp=%s hp=%s inv=%s" % [f.lamp != null, f.hp, f.invulnerable])
	P.flashlight.visible = true
	await watch(f, 8.0)
	log_("music=%s" % Sfx.music_name)
	log_("-- light off + far: should lose track")
	P.flashlight.visible = false
	P.global_position = Vector3(25, 0.1, 25)
	await watch(f, 8.0)
	log_("music after=%s" % Sfx.music_name)
	log_("-- bullets (stagger @150)")
	P.flashlight.visible = true
	P.global_position = f.global_position + Vector3(0, 0, 8)
	await w(0.5)
	for i in 8:
		f.take_hit(25.0, f.global_position + Vector3(0, 1, 0), Vector3(0, 0, -1), false)
	log_("after bullets hp=%s state=%s" % [f.hp, f.state])
	await w(1.5)
	log_("-- burn")
	f.burn(10.0, P.global_position)
	await w(0.5)
	log_("after burn state=%s retreat=%s" % [f.state, f._retreat_t])
	await w(3.0)
	P.global_position = f.global_position + Vector3(5, 0, 0)
	await w(0.2)
	log_("-- safe zone")
	var a := Area3D.new()
	a.add_to_group("safe_zone")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = Vector3(10, 4, 10)
	cs.shape = bs; a.add_child(cs)
	a.position = Vector3(-20, 2, 20)
	lv.add_child(a)
	f._retreat_t = 0.0
	f._set_state("chase")
	P.global_position = Vector3(-20, 0.1, 20)
	f.global_position = Vector3(-8, 0, 12)
	await watch(f, 8.0)
	log_("foreman inside safe zone? %s" % f._in_safe_zone(f.global_position))
	f.vanish()
	await w(5.0)
	log_("after vanish valid=%s" % is_instance_valid(f))
	a.queue_free()
	log_("-- mortal")
	var m = spawn("foreman", Vector3(0, 0, -14), {"mortal": true})
	await w(0.3)
	log_("mortal hp=%s inv=%s" % [m.hp, m.invulnerable])
	m.take_hit(100.0, m.global_position + Vector3(0, 1, 0), Vector3.FORWARD, false)
	for i in 30:
		m.burn(40.0, P.global_position)
	log_("mortal after fire hp=%s state=%s" % [m.hp, m.state])
	m.hp = 5
	m.take_hit(50.0, m.global_position + Vector3(0, 1, 0), Vector3.FORWARD, false)
	log_("mortal dead state=%s" % m.state)

func t_husk() -> void:
	P.global_position = Vector3(0, 0.1, 10)
	var h = spawn("husk", Vector3(0, 0, -5), {})
	await w(0.3)
	log_("husk armor=%s hp=%s plates=%d" % [h.armor_hp, h.hp, h._plates.size()])
	for i in 4:
		h.take_hit(20.0, h.global_position + Vector3(0, 1, 0), Vector3(0, 0, 1), false)
	log_("after 4 pistol: armor=%s hp=%s shed=%d" % [h.armor_hp, h.hp, h._shed])
	Game.equipped = "shotgun"
	for i in 6:
		h.take_hit(30.0, h.global_position + Vector3(0, 1, 0), Vector3(0, 0, 1), false)
	log_("after 6 shotgun: armor=%s hp=%s shed=%d state=%s" % [h.armor_hp, h.hp, h._shed, h.state])
	Game.equipped = "handgun"
	h.take_hit(30.0, h.global_position + Vector3(0, 1, 0), Vector3(0, 0, 1), false)
	log_("flesh hit hp=%s" % h.hp)
	await watch(h, 4.0)
	h.burn(10.0, P.global_position)
	for i in 6:
		h.take_hit(30.0, h.global_position + Vector3(0, 1, 0), Vector3(0, 0, 1), false)
	log_("dead? state=%s" % h.state)
	var h2 = spawn("husk", Vector3(5, 0, -5), {})
	await w(0.2)
	for i in 12:
		h2.burn(10.0, Vector3(5, 0, 0))
	log_("fire: armor=%s hp=%s" % [h2.armor_hp, h2.hp])

func t_siren() -> void:
	P.global_position = Vector3(0, 0.1, 10)
	P.flashlight.visible = true
	P.flashlight.look_at(Vector3(0, 1, 10))
	var z = spawn("zombie", Vector3(8, 0, -8), {"dormant": true})
	var hd = spawn("hound", Vector3(-8, 0, -8), {})
	var s = spawn("siren", Vector3(0, 0, -6), {"hum_interval": 3.0})
	await w(0.3)
	log_("siren hp=%s zombie state=%s" % [s.hp, z.state])
	await watch(s, 7.0)
	log_("zombie state after hum=%s hound=%s" % [z.state, hd.state])
	log_("-- flashlight flee")
	P.flashlight.visible = true
	P.global_position = Vector3(0, 0.1, 6)
	P.flashlight.global_position = P.global_position + Vector3(0, 1.4, 0)
	P.flashlight.look_at(s.global_position + Vector3(0, 1.2, 0))
	var d0: float = s.global_position.distance_to(P.global_position)
	await w(0.3)
	P.flashlight.look_at(s.global_position + Vector3(0, 1.2, 0))
	log_("in beam=%s" % s._in_player_beam(s.global_position + Vector3(0, 1.3, 0), 24.0, 6.0))
	await w(1.0)
	log_("flee state=%s flee_t=%s" % [s.state, s._flee_t])
	s.take_hit(45.0, s.global_position + Vector3(0, 1.4, 0), Vector3.FORWARD, true)
	log_("siren dead? %s" % s.state)

func t_hound() -> void:
	P.global_position = Vector3(0, 0.1, 10)
	var a = spawn("hound", Vector3(-6, 0, -10), {})
	var b = spawn("hound", Vector3(6, 0, -12), {})
	var c = spawn("hound", Vector3(12, 0, -14), {})
	await w(0.3)
	a.hear(P.global_position)
	await w(0.5)
	log_("pack states a=%s b=%s c=%s" % [a.state, b.state, c.state])
	var t := 0.0
	var hp0: int = Game.hp
	var lastl := ""
	while t < 12.0:
		var s := "%s/%s/%s" % [a.state, b.state, c.state]
		if s != lastl:
			log_("%.1f %s hp=%d speed=%.1f" % [t, s, Game.hp, a.velocity.length()])
			lastl = s
		await w(0.1)
		t += 0.1
	log_("player lost %d hp" % (hp0 - Game.hp))
	a.take_hit(40.0, a.global_position + Vector3(0, 0.5, 0), Vector3.FORWARD, false)
	log_("hound dead? %s" % a.state)

func t_burster() -> void:
	P.global_position = Vector3(0, 0.1, 10)
	var b = spawn("burster", Vector3(0, 0, 7.5), {})
	await w(0.3)
	var hp0: int = Game.hp
	await watch(b, 2.0)
	for i in 6:
		log_("t=%d slow=%s slow_t=%s hp=%d" % [i, P.get_meta("slow", "none"), P.get_meta("slow_t", "none"), Game.hp])
		await w(0.8)
	log_("slow meta=%s hp %d -> %d" % [P.get_meta("slow", "none"), hp0, Game.hp])
	await w(4.5)
	log_("after cloud slow meta=%s" % [P.get_meta("slow", "none")])
	var b2 = spawn("burster", Vector3(0, 0, -10), {})
	var z = spawn("zombie", Vector3(1.5, 0, -10), {})
	await w(0.2)
	var zh: float = z.hp
	b2.take_hit(999.0, b2.global_position + Vector3(0, 1, 0), Vector3.FORWARD, false)
	await w(2.0)
	log_("burster2 state=%s zombie hp %.0f -> %.0f" % [b2.state, zh, z.hp])

func t_hanger() -> void:
	P.global_position = Vector3(0, 0.1, 10)
	box_ceiling()
	var h = spawn("hanger", Vector3(0, 0, -5), {"ceiling_height": 3.6, "climb_after": 3.0})
	await w(0.3)
	log_("hanger y=%.2f state=%s" % [h.global_position.y, h.state])
	await w(1.0)
	log_("still hanging? %s" % h.state)
	P.global_position = Vector3(0, 0.1, -3.5)
	await watch(h, 3.0)
	log_("landed y=%.2f hp=%d" % [h.global_position.y, Game.hp])
	P.global_position = Vector3(0, 0.1, 10)
	await watch(h, 8.0)
	log_("end y=%.2f state=%s" % [h.global_position.y, h.state])

func box_ceiling() -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = Vector3(60, 0.4, 60)
	cs.shape = bs; b.add_child(cs)
	b.position = Vector3(0, 3.8, 0)
	lv.add_child(b)

func t_choir() -> void:
	P.global_position = Vector3(0, 0.1, 6)
	var c = spawn("boss_choir", Vector3(0, 0, -6), {})
	var died := [false]
	c.died.connect(func(_e): died[0] = true)
	await w(0.3)
	log_("choir hp=%s heads=%d" % [c.hp, c.model.heads.size()])
	c.take_hit(50.0, c.global_position + Vector3(0, 0.5, 1), Vector3.FORWARD, false)
	log_("body hit -> hp=%s" % c.hp)
	await watch(c, 10.0)
	log_("hp player=%d minions=%d" % [Game.hp, c._minions.size()])
	for k in 5:
		var idx: int = c.model.WEAK[k]
		var pos: Vector3 = c.model.head_world(idx)
		c.take_hit(70.0, pos, Vector3.FORWARD, true)
		c.take_hit(80.0, pos, Vector3.FORWARD, true)
		log_("head %d hp=%s" % [idx, c._hp_left[idx]])
	await w(0.5)
	log_("died=%s state=%s sag=%.2f" % [died[0], c.state, c.model.sag])

func t_hauler() -> void:
	P.global_position = Vector3(0, 0.1, 18)
	var h = spawn("boss_hauler", Vector3(0, 0, -2), {})
	var died := [false]
	h.died.connect(func(_e): died[0] = true)
	await w(0.3)
	log_("hauler hp=%.0f weak=%s" % [h.hp, h._weak_pos()])
	h.take_hit(100.0, h.global_position + Vector3(0, 1, 1), Vector3.FORWARD, false)
	log_("body 100 -> hp=%.0f" % h.hp)
	h.take_hit(100.0, h._weak_pos(), Vector3.FORWARD, true)
	log_("weak 100 -> hp=%.0f" % h.hp)
	P.global_position = Vector3(0, 0.1, 27)
	await watch(h, 14.0)
	log_("hp player=%d" % Game.hp)
	h.hp = 50
	h.take_hit(100.0, h._weak_pos(), Vector3.FORWARD, true)
	await w(0.3)
	log_("died=%s" % died[0])

func t_mother() -> void:
	Game.hp = 100
	P.global_position = Vector3(0, 0.1, 6)
	var m = spawn("boss_mother", Vector3(0, 0, -10), {})
	var died := [false]
	m.died.connect(func(_e): died[0] = true)
	await w(0.3)
	log_("mother phase=%d hp=%.0f heart=%s" % [m.phase, m.hp, m._heart()])
	m.take_hit(100.0, m.global_position + Vector3(2, 3, 0), Vector3.FORWARD, false)
	log_("lattice hit hp=%.0f" % m.hp)
	await watch(m, 6.0)
	log_("player hp=%d" % Game.hp)
	Game.hp = 100
	var hv: Vector3 = m._heart()
	m.take_hit(300.0, hv, Vector3.FORWARD, false)
	log_("weak 300 hp=%.0f" % m.hp)
	m.take_hit(700.0, hv, Vector3.FORWARD, false)
	log_("phase1 down state=%s hp=%.0f died=%s" % [m.state, m.hp, died[0]])
	await w(4.0)
	log_("phase=%d hp=%.0f state=%s died=%s" % [m.phase, m.hp, m.state, died[0]])
	P.global_position = Vector3(0, 0.1, 8)
	Game.hp = 100
	await watch(m, 10.0)
	log_("player hp=%d" % Game.hp)
	m.burn(100.0, m.global_position)
	log_("fire hp=%.0f" % m.hp)
	m.take_hit(5000.0, m.global_position + Vector3(0, 2, 0), Vector3.FORWARD, false)
	await w(0.3)
	log_("final state=%s died=%s" % [m.state, died[0]])

func t_npc() -> void:
	var NPC = load("res://actors/npc.gd")
	var out := []
	for nm in ["june", "ruth", "imogen", "caretaker", "miner_corpse"]:
		var n = NPC.spawn(lv, nm, Vector3(randf_range(-5, 5), 0, -5))
		out.append(n)
	await w(0.3)
	var j = out[0]
	j.follow_player = true
	P.global_position = Vector3(10, 0.1, 10)
	await w(5.0)
	log_("june follows: dist=%.1f" % j.global_position.distance_to(P.global_position))
	j.follow_player = false
	await j.walk_to(Vector3(-10, 0, 0))
	log_("june walked: pos=%s" % j.global_position)
	j.sit()
	await w(0.3)
	out[1].die()
	log_("ruth dead=%s" % out[1].is_dead)

func t_wall() -> void:
	Game.hp = 100
	P.global_position = Vector3(-25, 0.1, -25)
	var h = spawn("boss_hauler", Vector3(0, 0, 18), {})
	await w(0.3)
	h._dir = Vector3(0, 0, 1)
	h._hit_done = true
	h._set_state("charge")
	await watch(h, 6.0)
	log_("stun_k=%.2f z=%.1f" % [h.model.stun_k, h.global_position.z])
