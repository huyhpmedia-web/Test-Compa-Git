extends "res://levels/level.gd"
## Dev level: a snowy street lined with the 3D Jutsu town buildings (world/town.gd) for look-dev renders.
const Town = preload("res://world/town.gd")

func build() -> void:
	env_exterior_night(true, 0.02, 0.42)
	add_spawn("start", Vector3(0, 0.1, 14), PI)
	floor_rect(-40, -80, 40, 30, 0.0, "snow")
	floor_rect(-4, -80, 4, 30, 0.02, "asphalt_snow")
	var left := ["house_two_story", "house_bungalow", "house_duplex", "shop_corner", "house_farm", "office_small", "house_timber"]
	var right := ["house_ranch", "house_split", "shop_diner", "hall_station", "house_narrow", "shop_wood_store"]
	var z := 4.0
	for n in left:
		Town.building(geo, n, Vector3(-14, 0, z), PI * 0.5, {"lit": 0.5})
		z -= 13.0
	z = 2.0
	for n in right:
		Town.building(geo, n, Vector3(14, 0, z), -PI * 0.5, {"lit": 0.5})
		z -= 13.0
	# a facing row across the end of the street (front = +Z) for the hero view
	var xs := -22.0
	for n in ["house_bungalow", "shop_corner", "house_two_story", "house_split"]:
		Town.building(geo, n, Vector3(xs, 0, -6), 0.0, {"lit": 0.6})
		xs += 12.0
	for i in 6:
		Props.lamp_post(geo, Vector3(-5.5 if i % 2 == 0 else 5.5, 0, 6 - i * 13), PI * 0.5 if i % 2 == 0 else -PI * 0.5)
