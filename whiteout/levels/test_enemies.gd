extends "res://levels/level.gd"
## Dev arena: every Rimebound type, bosses and NPCs in a row along z = -20, facing the
## player's start (z = -8). Flags (shot.sh flags=...):
##   te_calm   -> all enemies spawn dormant (inert) so they can be photographed
##   te_nonpc  -> skip NPCs
## Exhibit x positions are listed in EXHIBITS so screenshots can aim at them.

const EXHIBITS := {
	"zombies": -44.0, "crawler": -34.0, "husk": -30.0, "siren": -26.0, "hound": -22.0, "burster": -17.0,
	"hanger": -12.0, "foreman": -6.0, "choir": 8.0, "hauler": 30.0, "mother": 56.0, "npcs": -50.0,
}

func build() -> void:
	env_exterior_night(false, 0.01, 0.35)
	add_spawn("start", Vector3(0, 0, -8), PI)
	floor_rect(-70, -45, 80, 12, 0.0, "concrete")
	box(Vector3(5, 5, -45.5), Vector3(150, 10, 1), "brick_dark")
	box(Vector3(5, 5, 12.5), Vector3(150, 10, 1), "brick_dark")
	box(Vector3(-70.5, 5, -16), Vector3(1, 10, 58), "brick_dark")
	box(Vector3(80.5, 5, -16), Vector3(1, 10, 58), "brick_dark")
	var calm := Game.has_flag("te_calm")
	var dorm := {"dormant": true} if calm else {}
	# general lighting: soft cold fills + warm sources
	for x in range(-60, 80, 14):
		light(Vector3(x, 5.5, -16), Color(0.65, 0.78, 1.0), 2.2, 18.0, false)
	for x in range(-52, 80, 14):
		light(Vector3(x, 3.0, -12), Color(1.0, 0.75, 0.5), 1.6, 11.0, false)
	# Shamblers
	var zx: float = EXHIBITS.zombies
	var i := 0
	for v in ["civilian", "worker", "nurse", "miner"]:
		enemy("", "zombie", Vector3(zx + i * 2.4, 0, -20), 0.0, _p({"variant": v}, dorm))
		i += 1
	enemy("", "zombie", Vector3(zx + 9.6, 0, -20), 0.0, _p({"variant": "civilian", "rime": 1.5}, dorm))
	enemy("", "zombie", Vector3(EXHIBITS.crawler, 0, -20), 0.0, _p({"crawler": true}, dorm))
	enemy("", "zombie", Vector3(EXHIBITS.crawler + 2.0, 0, -20), 0.0, _p({"sleeping": true, "variant": "miner"}, {}))
	enemy("", "husk", Vector3(EXHIBITS.husk, 0, -20), 0.0, _p({}, dorm))
	enemy("", "siren", Vector3(EXHIBITS.siren, 0, -20), 0.0, _p({}, dorm))
	enemy("", "hound", Vector3(EXHIBITS.hound, 0, -20), 0.0, _p({}, dorm))
	enemy("", "hound", Vector3(EXHIBITS.hound + 2.2, 0, -19), 0.3, _p({}, dorm))
	enemy("", "burster", Vector3(EXHIBITS.burster, 0, -20), 0.0, _p({}, dorm))
	# hanger alcove with a low ceiling
	var hx: float = EXHIBITS.hanger
	box(Vector3(hx, 4.0, -20), Vector3(8, 0.4, 8), "concrete")
	enemy("", "hanger", Vector3(hx, 0, -20), 0.0, _p({"ceiling_height": 3.8}, dorm))
	enemy("", "foreman", Vector3(EXHIBITS.foreman, 0, -22), 0.0, _p({"stalk": false}, dorm))
	# bosses
	enemy("", "boss_choir", Vector3(EXHIBITS.choir, 0, -26), 0.0, _p({}, dorm))
	enemy("", "boss_hauler", Vector3(EXHIBITS.hauler, 0, -24), 0.0, _p({}, dorm))
	enemy("", "boss_mother", Vector3(EXHIBITS.mother, 0, -30), 0.0, _p({}, dorm))
	# safe room (test the foreman giving up)
	var sz := Area3D.new()
	sz.add_to_group("safe_zone")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(8, 4, 8)
	cs.shape = bs
	sz.add_child(cs)
	sz.position = Vector3(66, 2, -6)
	add_child(sz)
	light(Vector3(66, 3.2, -6), Color(1.0, 0.85, 0.6), 2.0, 9.0, false)
	# NPCs
	if not Game.has_flag("te_nonpc") and ResourceLoader.exists("res://actors/npc.gd"):
		var NPC = load("res://actors/npc.gd")
		var nx: float = EXHIBITS.npcs
		var k := 0
		for nm in ["june", "ruth", "imogen", "caretaker", "miner_corpse"]:
			var n: Node3D = NPC.new()
			n.setup_npc(NPC.preset(nm))
			n.position = Vector3(nx + k * 2.2, 0, -14)
			n.rotation.y = 0.0
			add_child(n)
			k += 1

func _p(a: Dictionary, b: Dictionary) -> Dictionary:
	var r := a.duplicate()
	r.merge(b, true)
	return r

func on_enter() -> void:
	pass
