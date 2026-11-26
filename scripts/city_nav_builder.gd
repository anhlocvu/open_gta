class_name CityNavBuilder
extends RefCounted
## Builds Harbor District landmark portal zones and multi-layer RoadGraph walkways/entrances.


static func build_nav_zones(city: City) -> Array[Dictionary]:
	var zones: Array[Dictionary] = []
	var last_st := city.st_zs.size() - 1
	# Specific nested zones first (army_hangar before army_base)
	zones.append({
		"id": "army_hangar",
		"parent_zone": "army_base",
		"bounds": Rect2(city.base_pos.x - 28.5, city.base_pos.z + 9.5, 17.0, 17.0),
		"interior_pos": city.base_pos + Vector3(-20.0, 0.0, 18.0),
		"door_pos": city.base_pos + Vector3(-9.5, 0.0, 18.0),
		"apron_pos": city.base_pos + Vector3(0.0, 0.0, 0.0),
		"drive_pos": city.base_pos + Vector3(-7.0, 0.0, 18.0),
		"enclosed": true,
		"walk_only_entry": true,
	})
	zones.append({
		"id": "army_base",
		"bounds": Rect2(city.base_pos.x - 39.0, city.base_pos.z - 31.5, 78.0, 63.0),
		"interior_pos": city.base_pos,
		"door_pos": city.base_pos + Vector3(0.0, 0.0, -29.0),
		"apron_pos": Vector3(city.base_pos.x, 0.15, city.st_zs[last_st] + 5.2),
		"street_pos": Vector3(city.base_pos.x, 0.15, city.st_zs[last_st]),
		"drive_pos": city.base_pos,
		"block_i": 2,
		"south_st_j": last_st,
		"enclosed": true,
		"walk_only_entry": false,
	})
	zones.append({
		"id": "dealership",
		"bounds": Rect2(city.dealership_pos.x - 7.8, city.dealership_pos.z - 9.8, 15.6, 10.6),
		"interior_pos": city.dealership_pos,
		"door_pos": Vector3(city.dealership_pos.x, 0.15, city.dealership_pos.z + 1.5),
		"apron_pos": Vector3(city.dealership_pos.x, 0.15, city.st_zs[5] - 7.6),
		"street_pos": Vector3(city.dealership_pos.x, 0.15, city.st_zs[5]),
		"drive_pos": city.dealership_spawn_pos,
		"block_i": 6,
		"south_st_j": 5,
		"enclosed": true,
		"walk_only_entry": true,
	})
	zones.append({
		"id": "gun_shop",
		"bounds": Rect2(city.gun_shop_pos.x - 6.2, city.gun_shop_pos.z - 4.8, 12.4, 10.0),
		"interior_pos": city.gun_shop_pos,
		"door_pos": city.gun_shop_pos + Vector3(0.0, 0.0, 5.8),
		"apron_pos": Vector3(city.gun_shop_pos.x, 0.15, city.st_zs[4] - 7.6),
		"street_pos": Vector3(city.gun_shop_pos.x, 0.15, city.st_zs[4]),
		"drive_pos": Vector3(city.gun_shop_pos.x, 0.35, city.st_zs[4]),
		"block_i": 7,
		"south_st_j": 4,
		"enclosed": true,
		"walk_only_entry": true,
	})
	zones.append({
		"id": "bar",
		"bounds": Rect2(city.bar_pos.x - 5.7, city.bar_pos.z - 4.6, 11.4, 9.6),
		"interior_pos": city.bar_pos,
		"door_pos": city.bar_pos + Vector3(0.0, 0.0, 5.5),
		"apron_pos": Vector3(city.bar_pos.x, 0.15, city.st_zs[11] - 7.6),
		"street_pos": Vector3(city.bar_pos.x, 0.15, city.st_zs[11]),
		"drive_pos": Vector3(city.bar_pos.x, 0.35, city.st_zs[11]),
		"block_i": 3,
		"south_st_j": 11,
		"enclosed": true,
		"walk_only_entry": true,
	})
	zones.append({
		"id": "spray",
		"bounds": Rect2(city.spray_pos.x - 5.0, city.spray_pos.z - 5.0, 10.0, 10.0),
		"interior_pos": city.spray_pos,
		"door_pos": city.spray_pos + Vector3(0.0, 0.0, 4.5),
		"apron_pos": Vector3(city.spray_pos.x, 0.15, city.st_zs[8] - 7.6),
		"street_pos": Vector3(city.spray_pos.x, 0.15, city.st_zs[8]),
		"drive_pos": city.spray_pos,
		"block_i": 1,
		"south_st_j": 8,
		"enclosed": false,
		"walk_only_entry": false,
	})
	zones.append({
		"id": "garage",
		"bounds": Rect2(city.garage_pos.x - 5.0, city.garage_pos.z - 5.0, 10.0, 10.0),
		"interior_pos": city.garage_pos,
		"door_pos": city.garage_pos + Vector3(0.0, 0.0, 4.5),
		"apron_pos": Vector3(city.garage_pos.x, 0.15, city.st_zs[2] - 7.6),
		"street_pos": Vector3(city.garage_pos.x, 0.15, city.st_zs[2]),
		"drive_pos": city.garage_pos,
		"block_i": 4,
		"south_st_j": 2,
		"enclosed": false,
		"walk_only_entry": false,
	})
	zones.append({
		"id": "hospital",
		"bounds": Rect2(city.hospital_pos.x - 6.0, city.hospital_pos.z - 4.0, 12.0, 8.0),
		"interior_pos": city.hospital_pos,
		"door_pos": city.hospital_pos + Vector3(0.0, 0.0, 3.2),
		"apron_pos": Vector3(city.hospital_pos.x, 0.15, city.st_zs[13] - 7.6),
		"street_pos": Vector3(city.hospital_pos.x, 0.15, city.st_zs[13]),
		"drive_pos": city.hospital_pos,
		"block_i": 8,
		"south_st_j": 13,
		"enclosed": false,
		"walk_only_entry": false,
	})
	zones.append({
		"id": "station",
		"bounds": Rect2(city.station_pos.x - 6.0, city.station_pos.z - 4.0, 12.0, 8.0),
		"interior_pos": city.station_pos,
		"door_pos": city.station_pos + Vector3(0.0, 0.0, 3.2),
		"apron_pos": Vector3(city.station_pos.x, 0.15, city.st_zs[9] - 7.6),
		"street_pos": Vector3(city.station_pos.x, 0.15, city.st_zs[9]),
		"drive_pos": city.station_pos,
		"block_i": 9,
		"south_st_j": 9,
		"enclosed": false,
		"walk_only_entry": false,
	})
	return zones


static func build_graph(city: City) -> RoadGraph:
	var g := RoadGraph.grid(city.ave_xs, city.st_zs)
	if city.nav_zones.is_empty():
		city.nav_zones = build_nav_zones(city)
	var nx := city.ave_xs.size()
	var nz := city.st_zs.size()
	for pi in [4, 5]:
		for pj in [6, 7]:
			var cx := (city.ave_xs[pi] + city.ave_xs[pi + 1]) * 0.5
			var cz := (city.st_zs[pj] + city.st_zs[pj + 1]) * 0.5
			var p_idx := g.add_node(Vector3(cx, 0.15, cz), "park")
			for xi in [pi, pi + 1]:
				for zi in [pj, pj + 1]:
					g.connect_nodes(p_idx, zi * nx + xi, "walk")

	var zones_copy: Array[Dictionary] = []
	for z in city.nav_zones:
		var zc := z.duplicate(true)
		var walk_only := bool(zc.get("walk_only_entry", false))
		var portal_mode := "walk" if walk_only else "both"
		var int_idx := g.add_node(zc["interior_pos"], "interior")
		var door_idx := g.add_node(zc["door_pos"], "door")
		var apron_idx := g.add_node(zc["apron_pos"], "apron")
		g.connect_nodes(int_idx, door_idx, portal_mode)
		g.connect_nodes(door_idx, apron_idx, portal_mode)
		zc["interior_node"] = int_idx
		zc["door_node"] = door_idx
		zc["apron_node"] = apron_idx
		if zc.has("street_pos"):
			var spos: Vector3 = zc["street_pos"]
			var st_idx := g.add_node(spos, "road")
			zc["street_node"] = st_idx
			g.connect_nodes(apron_idx, st_idx, portal_mode)
			var bi := int(zc.get("block_i", -1))
			var sz_i := int(zc.get("south_st_j", -1))
			if bi >= 0 and bi + 1 < nx and sz_i >= 0 and sz_i < nz:
				var left_road := sz_i * nx + bi
				var right_road := sz_i * nx + (bi + 1)
				g.connect_nodes(st_idx, left_road, "both")
				g.connect_nodes(st_idx, right_road, "both")
				var sw_z := spos.z + 7.6 if float((zc["apron_pos"] as Vector3).z) > spos.z else spos.z - 7.6
				var sw_l := g.add_node(Vector3(city.ave_xs[bi] + 7.6, 0.15, sw_z), "sidewalk")
				var sw_r := g.add_node(Vector3(city.ave_xs[bi + 1] - 7.6, 0.15, sw_z), "sidewalk")
				g.connect_nodes(apron_idx, sw_l, "walk")
				g.connect_nodes(apron_idx, sw_r, "walk")
				g.connect_nodes(sw_l, left_road, "walk")
				g.connect_nodes(sw_r, right_road, "walk")
		zones_copy.append(zc)

	var base_int_idx := -1
	var hangar_apron_idx := -1
	for zc in zones_copy:
		if str(zc.get("id", "")) == "army_base":
			base_int_idx = int(zc.get("interior_node", -1))
		elif str(zc.get("id", "")) == "army_hangar":
			hangar_apron_idx = int(zc.get("apron_node", -1))
	if base_int_idx >= 0 and hangar_apron_idx >= 0:
		g.connect_nodes(hangar_apron_idx, base_int_idx, "walk")
	city.nav_zones = zones_copy
	g.zones = city.nav_zones
	return g


static func find_containing_zone(zones: Array[Dictionary], pos: Vector3, only_enclosed := true) -> Dictionary:
	var p2 := Vector2(pos.x, pos.z)
	for z in zones:
		if only_enclosed and not bool(z.get("enclosed", false)):
			continue
		var bounds := z.get("bounds", Rect2()) as Rect2
		if bounds.size.x > 0.0 and bounds.size.y > 0.0 and bounds.has_point(p2):
			return z
	return {}


static func resolve_drive_target(city: City, pos: Vector3, label := "") -> Dictionary:
	var z := find_containing_zone(city.nav_zones, pos, true)
	if not z.is_empty() and bool(z.get("walk_only_entry", false)):
		return {"position": z.get("drive_pos", pos), "rerouted_outside": true}
	var p2 := Vector2(pos.x, pos.z)
	for item in city.nav_zones:
		if not bool(item.get("walk_only_entry", false)):
			continue
		var ipos: Vector3 = item.get("interior_pos", Vector3.ZERO)
		if Vector2(ipos.x, ipos.z).distance_to(p2) <= 4.5:
			return {"position": item.get("drive_pos", pos), "rerouted_outside": true}
	if label == "Vehicle Dealership":
		return {"position": city.dealership_spawn_pos, "rerouted_outside": true}
	if label == "Gun Shop":
		return {"position": Vector3(city.gun_shop_pos.x, 0.35, city.st_zs[4]), "rerouted_outside": true}
	if label == "Bar":
		return {"position": Vector3(city.bar_pos.x, 0.35, city.st_zs[11]), "rerouted_outside": true}
	return {"position": pos, "rerouted_outside": false}
