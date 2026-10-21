extends RefCounted
## Item database. kind: weapon | ammo | heal | key | upgrade | resource | file
## Key items list `level` purely as documentation for designers.

const DEFS := {
	# --- weapons
	"knife": {"name": "Lineman's Hatchet", "kind": "weapon", "desc": "A short-handled hatchet from the truck. Quiet. Reliable. Close.", "color": Color(0.7, 0.7, 0.75)},
	"handgun": {"name": "M45 Pistol", "kind": "weapon", "ammo": "ammo_9mm", "mag": 12, "damage": 22, "rate": 0.28, "spread": 1.2, "range": 60.0, "desc": "Elias's old service pistol, kept in the truck's lockbox. 12-round magazine.", "color": Color(0.25, 0.25, 0.28)},
	"shotgun": {"name": "Pump Shotgun", "kind": "weapon", "ammo": "ammo_shell", "mag": 6, "damage": 14, "pellets": 8, "rate": 0.9, "spread": 6.0, "range": 18.0, "desc": "A hardware-store duck gun. Devastating up close; cracks ice armour.", "color": Color(0.35, 0.25, 0.18)},
	"magnum": {"name": "Tom's Revolver", "kind": "weapon", "ammo": "ammo_44", "mag": 6, "damage": 120, "pellets": 1, "rate": 0.85, "spread": 0.6, "range": 80.0, "pierce": true, "desc": "Your father's .44. Mom kept it in the shelter office. Pierces through targets.", "color": Color(0.6, 0.6, 0.62)},
	"launcher": {"name": "Flare Launcher", "kind": "weapon", "ammo": "ammo_grenade", "mag": 1, "damage": 160, "rate": 1.2, "spread": 0.5, "range": 60.0, "explosive": true, "desc": "A marine signal launcher modified by Meridian security. Incendiary burst. The Rimebound fear it.", "color": Color(0.75, 0.3, 0.1)},
	# --- ammo
	"ammo_9mm": {"name": "9mm Rounds", "kind": "ammo", "stack": 60, "desc": "Pistol ammunition.", "color": Color(0.8, 0.65, 0.3)},
	"ammo_shell": {"name": "12ga Shells", "kind": "ammo", "stack": 24, "desc": "Shotgun shells.", "color": Color(0.8, 0.2, 0.15)},
	"ammo_44": {"name": ".44 Rounds", "kind": "ammo", "stack": 12, "desc": "Heavy revolver rounds.", "color": Color(0.85, 0.8, 0.6)},
	"ammo_grenade": {"name": "Incendiary Flares", "kind": "ammo", "stack": 6, "desc": "40mm incendiary flares for the launcher.", "color": Color(0.9, 0.35, 0.1)},
	"powder": {"name": "Gunpowder", "kind": "resource", "stack": 10, "desc": "Combine two to make pistol rounds.", "color": Color(0.3, 0.3, 0.3)},
	"flare": {"name": "Road Flare", "kind": "resource", "stack": 5, "desc": "A magnesium road flare. Light it (use) to burn nearby Rimebound and drive them back for a while.", "color": Color(1.0, 0.25, 0.15)},
	# --- healing
	"gel": {"name": "Bandage Roll", "kind": "heal", "heal": 30, "stack": 1, "desc": "Restores some health. Combine with Painkillers.", "color": Color(0.85, 0.85, 0.8)},
	"adrenaline": {"name": "Painkillers", "kind": "resource", "stack": 1, "desc": "Not enough alone. Combine with a Bandage Roll.", "color": Color(0.9, 0.2, 0.2)},
	"gel_mix": {"name": "Field Dressing", "kind": "heal", "heal": 100, "stack": 1, "desc": "Bandage + painkillers. Fully restores health.", "color": Color(0.9, 0.7, 0.2)},
	"spray": {"name": "Trauma Kit", "kind": "heal", "heal": 100, "stack": 1, "desc": "A co-op first-responder kit. Fully restores health.", "color": Color(0.9, 0.9, 0.95)},
	# --- upgrades
	"pouch": {"name": "Tool Pouch", "kind": "upgrade", "desc": "Use to expand inventory by 2 slots.", "color": Color(0.4, 0.3, 0.2)},
	# --- key items (story)
	"radio": {"name": "Handheld Radio", "kind": "key", "desc": "Tuned to 146.52 MHz. June's frequency.", "color": Color(0.2, 0.2, 0.2)},
	"hot_stick": {"name": "Hot Stick", "kind": "key", "level": "l1", "desc": "An insulated fibreglass switching pole for operating energised disconnects.", "color": Color(0.9, 0.8, 0.1)},
	"control_key": {"name": "Control House Key", "kind": "key", "level": "l1", "desc": "Brass key tagged 'KF SUBSTATION — CONTROL HOUSE'.", "color": Color(0.85, 0.7, 0.3)},
	"fuse_60a": {"name": "60A Fuse", "kind": "key", "level": "l1/l2", "desc": "A 60-amp cartridge fuse.", "color": Color(0.9, 0.6, 0.1)},
	"school_key": {"name": "Janitor's Keyring", "kind": "key", "level": "l2", "desc": "Heavy keyring. Tag: 'KFCS — CUSTODIAL'. Opens the main hall and the boiler room.", "color": Color(0.7, 0.7, 0.6)},
	"valve_handle": {"name": "Valve Wheel", "kind": "key", "level": "l2", "desc": "A detachable cast-iron valve wheel from the boiler room.", "color": Color(0.5, 0.5, 0.55)},
	"gym_key": {"name": "Gym Padlock Key", "kind": "key", "level": "l2", "desc": "Small key on a whistle lanyard.", "color": Color(0.8, 0.8, 0.2)},
	"church_key": {"name": "Sacristy Key", "kind": "key", "level": "l3", "desc": "An old iron key. Father Okafor's handwriting on the tag: 'side door'.", "color": Color(0.4, 0.35, 0.3)},
	"bell_rope": {"name": "Bell Pull Handle", "kind": "key", "level": "l3", "desc": "The handle for the church bell's pull chain.", "color": Color(0.6, 0.4, 0.2)},
	"rosary": {"name": "Ruth's Rosary", "kind": "key", "level": "l3", "desc": "Your mother's rosary. The beads are rimed with frost that never melts.", "color": Color(0.7, 0.75, 0.8)},
	"badge_meridian": {"name": "Meridian Access Badge", "kind": "key", "level": "l4", "desc": "Contractor badge, cold to the touch. CORVANE SYSTEMS — MERIDIAN SITE.", "color": Color(0.2, 0.6, 0.9)},
	"coolant_key": {"name": "Cooling Plant Key", "kind": "key", "level": "l4", "desc": "A red key for the chiller plant's manual overrides.", "color": Color(0.9, 0.2, 0.2)},
	"pipeline_card": {"name": "Pipeline Override Card", "kind": "key", "level": "l4", "desc": "Imogen's override card for the heat-recovery pipeline service tunnel.", "color": Color(0.9, 0.5, 0.1)},
	"lamp_battery": {"name": "Cap-Lamp Battery", "kind": "key", "level": "l5", "desc": "A charged miner's cap-lamp battery pack.", "color": Color(0.3, 0.3, 0.2)},
	"hoist_lever": {"name": "Hoist Brake Lever", "kind": "key", "level": "l5", "desc": "The removable brake lever for the old hoist.", "color": Color(0.5, 0.45, 0.4)},
	"dynamite": {"name": "Blasting Charges", "kind": "key", "level": "l5", "desc": "Two sticks of old Northline blasting gel and a detonator.", "color": Color(0.8, 0.3, 0.2)},
	"tom_tag": {"name": "Tom's Brass Tag", "kind": "key", "level": "l5", "desc": "Miner's check-in tag no. 114. T. KADE. It was never collected in 2011.", "color": Color(0.8, 0.65, 0.3)},
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
