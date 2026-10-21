extends RefCounted
## Item database. kind: weapon | ammo | heal | key | upgrade | resource | file
## Key items list `level` purely as documentation for designers.

const DEFS := {
	# --- weapons
	"knife": {"name": "Combat Knife", "kind": "weapon", "desc": "A standard-issue EMT trauma knife. Quiet. Reliable. Close.", "color": Color(0.7, 0.7, 0.75)},
	"handgun": {"name": "P-17 Handgun", "kind": "weapon", "ammo": "ammo_9mm", "mag": 12, "damage": 22, "rate": 0.28, "spread": 1.2, "range": 60.0, "desc": "A Hollow Creek PD sidearm. 12-round magazine.", "color": Color(0.25, 0.25, 0.28)},
	"shotgun": {"name": "M870 Shotgun", "kind": "weapon", "ammo": "ammo_shell", "mag": 6, "damage": 14, "pellets": 8, "rate": 0.9, "spread": 6.0, "range": 18.0, "desc": "Pump-action. Devastating up close. Fires 8 pellets.", "color": Color(0.35, 0.25, 0.18)},
	"magnum": {"name": "Raging .44", "kind": "weapon", "ammo": "ammo_44", "mag": 6, "damage": 120, "pellets": 1, "rate": 0.85, "spread": 0.6, "range": 80.0, "pierce": true, "desc": "A revolver confiscated as evidence. Pierces through targets.", "color": Color(0.6, 0.6, 0.62)},
	"launcher": {"name": "GL-40 Launcher", "kind": "weapon", "ammo": "ammo_grenade", "mag": 1, "damage": 160, "rate": 1.2, "spread": 0.5, "range": 60.0, "explosive": true, "desc": "Aster security grenade launcher. Single shot, area damage.", "color": Color(0.2, 0.28, 0.2)},
	# --- ammo
	"ammo_9mm": {"name": "9mm Rounds", "kind": "ammo", "stack": 60, "desc": "Handgun ammunition.", "color": Color(0.8, 0.65, 0.3)},
	"ammo_shell": {"name": "12ga Shells", "kind": "ammo", "stack": 24, "desc": "Shotgun shells.", "color": Color(0.8, 0.2, 0.15)},
	"ammo_44": {"name": ".44 Rounds", "kind": "ammo", "stack": 12, "desc": "Heavy revolver rounds.", "color": Color(0.85, 0.8, 0.6)},
	"ammo_grenade": {"name": "40mm Grenades", "kind": "ammo", "stack": 6, "desc": "High-explosive grenades.", "color": Color(0.4, 0.45, 0.2)},
	"powder": {"name": "Gunpowder", "kind": "resource", "stack": 10, "desc": "Combine with gunpowder to make ammo.", "color": Color(0.3, 0.3, 0.3)},
	# --- healing
	"gel": {"name": "Hemostatic Gel", "kind": "heal", "heal": 30, "stack": 1, "desc": "Clotting gel. Restores some health. Combine with Adrenaline.", "color": Color(0.2, 0.8, 0.3)},
	"adrenaline": {"name": "Adrenaline Shot", "kind": "resource", "stack": 1, "desc": "Not useful alone. Combine with Hemostatic Gel.", "color": Color(0.9, 0.2, 0.2)},
	"gel_mix": {"name": "Trauma Pack", "kind": "heal", "heal": 100, "stack": 1, "desc": "Gel + adrenaline. Fully restores health.", "color": Color(0.9, 0.7, 0.2)},
	"spray": {"name": "First Aid Spray", "kind": "heal", "heal": 100, "stack": 1, "desc": "Military-grade medical spray. Fully restores health.", "color": Color(0.9, 0.9, 0.95)},
	# --- upgrades
	"pouch": {"name": "Hip Pouch", "kind": "upgrade", "desc": "Use to expand inventory by 2 slots.", "color": Color(0.4, 0.3, 0.2)},
	# --- key items (story)
	"ems_badge": {"name": "EMT Badge", "kind": "key", "desc": "Maya Reyes, Hollow Creek EMS. First day on the job.", "color": Color(0.8, 0.7, 0.2)},
	"bolt_cutter": {"name": "Bolt Cutter", "kind": "key", "level": "l1", "desc": "Heavy-duty cutters. Can break chains.", "color": Color(0.8, 0.1, 0.1)},
	"gate_fuse": {"name": "Power Fuse", "kind": "key", "level": "l1", "desc": "A 60A cartridge fuse for a utility box.", "color": Color(0.9, 0.6, 0.1)},
	"precinct_key": {"name": "Precinct Side Key", "kind": "key", "level": "l2", "desc": "A brass key tagged 'COURTYARD - SIDE ENTRANCE'.", "color": Color(0.85, 0.7, 0.3)},
	"valve_handle": {"name": "Valve Handle", "kind": "key", "level": "l2", "desc": "A detachable steel valve wheel.", "color": Color(0.5, 0.5, 0.55)},
	"keycard_blue": {"name": "Blue Keycard", "kind": "key", "level": "l2", "desc": "Hollow Creek PD access card. Clearance: Records.", "color": Color(0.2, 0.4, 0.9)},
	"seal_lion": {"name": "Lion Seal", "kind": "key", "level": "l3", "desc": "A heavy brass seal with a lion relief. Part of an old mechanism.", "color": Color(0.85, 0.65, 0.2)},
	"seal_owl": {"name": "Owl Seal", "kind": "key", "level": "l3", "desc": "A heavy brass seal with an owl relief.", "color": Color(0.85, 0.65, 0.2)},
	"seal_stag": {"name": "Stag Seal", "kind": "key", "level": "l3", "desc": "A heavy brass seal with a stag relief.", "color": Color(0.85, 0.65, 0.2)},
	"lily_drawing": {"name": "Lily's Drawing", "kind": "key", "level": "l3", "desc": "A crayon drawing: a girl, a woman in a lab coat, and a tall man in a coat. 'MOMMY IS MAKING EVERYONE BETTER'.", "color": Color(0.9, 0.85, 0.7)},
	"crank": {"name": "Hex Crank", "kind": "key", "level": "l4", "desc": "A hexagonal crank for maintenance shutters.", "color": Color(0.45, 0.45, 0.5)},
	"plug_a": {"name": "Pressure Plug (Red)", "kind": "key", "level": "l4", "desc": "A color-coded pressure plug for the water-control panel.", "color": Color(0.9, 0.2, 0.15)},
	"plug_b": {"name": "Pressure Plug (Green)", "kind": "key", "level": "l4", "desc": "A color-coded pressure plug for the water-control panel.", "color": Color(0.2, 0.85, 0.3)},
	"plug_c": {"name": "Pressure Plug (Blue)", "kind": "key", "level": "l4", "desc": "A color-coded pressure plug for the water-control panel.", "color": Color(0.2, 0.4, 0.95)},
	"aster_id": {"name": "Aster Staff ID", "kind": "key", "level": "l5", "desc": "ID of Dr. Helen Voss, Aster Genomics. Level 4 clearance.", "color": Color(0.9, 0.9, 0.9)},
	"daybreak": {"name": "DAYBREAK Vial", "kind": "key", "level": "l5", "desc": "The only synthesized dose of the counter-agent to EVERGREEN.", "color": Color(0.4, 0.8, 1.0)},
	"drive": {"name": "Evidence Drive", "kind": "key", "level": "l5", "desc": "An encrypted drive holding the full EVERGREEN trial data and HALCYON's triage logs.", "color": Color(0.1, 0.1, 0.1)},
	"train_key": {"name": "Train Control Key", "kind": "key", "level": "l6", "desc": "Operator key for the Aster freight shuttle.", "color": Color(0.9, 0.9, 0.3)},
}

## Combination recipes. Order-independent.
const RECIPES := [
	["gel", "adrenaline", "gel_mix"],
	["powder", "powder", "ammo_9mm"],
]

static func get_def(id: String) -> Dictionary:
	var d: Dictionary = DEFS.get(id, {"name": id, "kind": "key", "desc": "", "color": Color.WHITE}).duplicate()
	d["id"] = id
	if not d.has("stack"):
		d["stack"] = 1
	if id == "ammo_9mm" and not d.has("yield"):
		d["yield"] = 15
	return d

static func combine_result(a: String, b: String) -> String:
	for r in RECIPES:
		if (r[0] == a and r[1] == b) or (r[0] == b and r[1] == a):
			return r[2]
	return ""
