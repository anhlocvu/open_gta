class_name A11yRadar
extends RefCounted
## Relative bearing, compass heading, and categorized Open World target scanner.

enum Category { ALL = 0, ENEMIES = 1, CIVILIANS = 2, OBJECTIVES = 3, LOOT = 4, PLACES = 5 }

const COMPASS_NAMES := ["North", "Northeast", "East", "Southeast", "South", "Southwest", "West", "Northwest"]
const CATEGORY_NAMES := ["All", "Enemies and Police", "Civilians", "Objectives", "Pickups", "Places and Vehicles"]

var selected_category: int = Category.ALL
var cursor := 0
var locked_target_id := ""


static func forward_from_yaw(yaw: float) -> Vector3:
	return (Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, -1.0)).normalized()


static func compass_heading(yaw: float) -> String:
	var fwd := forward_from_yaw(yaw)
	var deg := fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)
	var index := int(roundi(deg / 45.0)) % 8
	return COMPASS_NAMES[index]


static func yaw_toward(from: Vector3, to: Vector3) -> float:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if flat.length_squared() < 0.0001:
		return 0.0
	return atan2(-flat.x, -flat.z)


static func relative_bearing_text(origin: Vector3, yaw: float, target: Vector3) -> String:
	var offset := Vector3(target.x - origin.x, 0.0, target.z - origin.z)
	var dist := offset.length()
	var vert := ""
	var dy := target.y - origin.y
	if dy > 2.2:
		vert = ", above"
	elif dy < -2.2:
		vert = ", below"
	if dist < 0.8:
		return "right here" + vert
	var fwd := forward_from_yaw(yaw)
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var dir := offset / dist
	var angle := rad_to_deg(atan2(right.dot(dir), fwd.dot(dir)))
	var sector := "ahead"
	if angle > 157.5 or angle < -157.5:
		sector = "behind you"
	elif angle > 112.5:
		sector = "behind right"
	elif angle > 67.5:
		sector = "to your right"
	elif angle > 22.5:
		sector = "ahead right"
	elif angle < -112.5:
		sector = "behind left"
	elif angle < -67.5:
		sector = "to your left"
	elif angle < -22.5:
		sector = "ahead left"
	return sector + vert


static func format_target_callout(origin: Vector3, yaw: float, target: Dictionary) -> String:
	var pos: Vector3 = target.get("position", origin)
	var dist := int(round(origin.distance_to(pos)))
	var bearing := relative_bearing_text(origin, yaw, pos)
	return "%s, %d meters, %s" % [str(target.get("label", "Target")), dist, bearing]


func cycle_category(step := 1) -> int:
	selected_category = posmod(selected_category + step, CATEGORY_NAMES.size())
	cursor = 0
	return selected_category


func category_label() -> String:
	return CATEGORY_NAMES[clampi(selected_category, 0, CATEGORY_NAMES.size() - 1)]


func collect_targets(game: Node, origin: Vector3, category := -1) -> Array[Dictionary]:
	var cat := selected_category if category < 0 else category
	var items: Array[Dictionary] = []
	if game == null or game.get("city") == null:
		return items
	_collect_open_world(game, origin, cat, items)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	return items


func step_target(game: Node, origin: Vector3, delta_step: int) -> Dictionary:
	var items := collect_targets(game, origin, selected_category)
	if items.is_empty():
		cursor = 0
		locked_target_id = ""
		return {}
	if locked_target_id != "":
		var existing := _find_by_id(items, locked_target_id)
		if existing >= 0:
			cursor = existing
	cursor = posmod(cursor + delta_step, items.size())
	var chosen := items[cursor]
	locked_target_id = str(chosen.id)
	return chosen


func resolve_locked_target(game: Node, origin: Vector3) -> Dictionary:
	if locked_target_id == "" or game == null:
		return {}
	if locked_target_id == "ow:objective":
		var dest: Vector3 = game.radar_objective() if game.has_method("radar_objective") else Vector3.ZERO
		if dest == Vector3.ZERO:
			return {}
		return {"id": locked_target_id, "label": "Current Mission Objective", "category": Category.OBJECTIVES, "position": dest, "distance": origin.distance_to(dest), "node": null}
	if locked_target_id.begins_with("place:"):
		var city = game.get("city")
		if city == null:
			return {}
		var map := {
			"place:gun_shop": ["Gun Shop", city.gun_shop_pos],
			"place:bar": ["Bar", city.bar_pos],
			"place:spray": ["Pay and Spray", city.spray_pos],
			"place:garage": ["Drop Warehouse", city.garage_pos],
			"place:hospital": ["Hospital", city.hospital_pos],
			"place:station": ["Police Station", city.station_pos],
			"place:base": ["Army Base", city.base_pos],
		}
		if map.has(locked_target_id):
			var info: Array = map[locked_target_id]
			var pos: Vector3 = info[1]
			return {"id": locked_target_id, "label": info[0], "category": Category.PLACES, "position": pos, "distance": origin.distance_to(pos), "node": null}
		return {}
	var sep := locked_target_id.find(":")
	if sep > 0:
		var prefix := locked_target_id.substr(0, sep)
		var raw_id := locked_target_id.substr(sep + 1)
		if raw_id.is_valid_int():
			var obj := instance_from_id(int(raw_id))
			if obj is Node3D and is_instance_valid(obj) and obj.is_inside_tree():
				var n := obj as Node3D
				if prefix == "ow_pk" and bool(n.get("taken")):
					return {}
				if prefix in ["cop", "civ"] and bool(n.get("downed")):
					return {}
				if prefix in ["copcar", "veh", "jet"] and (bool(n.get("occupied")) or bool(n.get("wrecked"))):
					return {}
				var label := "Target"
				match prefix:
					"cop": label = "Base Officer"
					"copcar": label = "Police Unit"
					"civ": label = "Civilian Pedestrian"
					"veh", "jet": label = str(n.get("display_name")) if n.get("display_name") != null else "Vehicle"
					"ow_pk":
						var pkind := int(n.get("kind"))
						label = ["Health Pickup", "Cash Pickup", "Package Pickup"][clampi(pkind, 0, 2)]
				return {"id": locked_target_id, "label": label, "category": Category.ALL, "position": n.global_position, "distance": origin.distance_to(n.global_position), "node": n}
	return {}


func _find_by_id(items: Array[Dictionary], id: String) -> int:
	for i in items.size():
		if str(items[i].id) == id:
			return i
	return -1


func _collect_open_world(game: Node, origin: Vector3, cat: int, out: Array[Dictionary]) -> void:
	var city = game.get("city")
	if city == null:
		return
	if cat in [Category.ALL, Category.OBJECTIVES]:
		var dest: Vector3 = game.radar_objective() if game.has_method("radar_objective") else Vector3.ZERO
		if dest != Vector3.ZERO:
			out.append({
				"id": "ow:objective",
				"label": "Current Mission Objective",
				"category": Category.OBJECTIVES,
				"position": dest,
				"distance": origin.distance_to(dest),
				"node": null
			})
	if cat in [Category.ALL, Category.PLACES]:
		var places := [
			["place:gun_shop", "Gun Shop", city.gun_shop_pos],
			["place:bar", "Bar", city.bar_pos],
			["place:spray", "Pay and Spray", city.spray_pos],
			["place:garage", "Drop Warehouse", city.garage_pos],
			["place:hospital", "Hospital", city.hospital_pos],
			["place:station", "Police Station", city.station_pos],
			["place:base", "Army Base", city.base_pos],
		]
		for p in places:
			out.append({
				"id": p[0],
				"label": p[1],
				"category": Category.PLACES,
				"position": p[2],
				"distance": origin.distance_to(p[2]),
				"node": null
			})
		var tree := game.get_tree()
		if tree:
			var veh_candidates: Array[Dictionary] = []
			for node in tree.get_nodes_in_group("vehicles"):
				var v := node as Node3D
				if v == null or not is_instance_valid(v) or bool(v.get("occupied")) or bool(v.get("wrecked")):
					continue
				var d := origin.distance_to(v.global_position)
				if d > 120.0:
					continue
				var dname := str(v.get("display_name")) if v.get("display_name") != null else "Vehicle"
				veh_candidates.append({
					"id": "veh:%d" % v.get_instance_id(),
					"label": dname,
					"category": Category.PLACES,
					"position": v.global_position,
					"distance": d,
					"node": v
				})
			veh_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
			for i in mini(veh_candidates.size(), 8):
				out.append(veh_candidates[i])
			for node in tree.get_nodes_in_group("aircraft"):
				var jet := node as Node3D
				if jet == null or not is_instance_valid(jet) or bool(jet.get("occupied")) or bool(jet.get("wrecked")):
					continue
				out.append({
					"id": "jet:%d" % jet.get_instance_id(),
					"label": str(jet.get("display_name")) if jet.get("display_name") != null else "Aircraft",
					"category": Category.PLACES,
					"position": jet.global_position,
					"distance": origin.distance_to(jet.global_position),
					"node": jet
				})
	if cat in [Category.ALL, Category.LOOT]:
		var tree := game.get_tree()
		if tree:
			for node in tree.get_nodes_in_group("world_pickups"):
				var pk := node as Node3D
				if pk == null or not is_instance_valid(pk) or bool(pk.get("taken")):
					continue
				var pkind := int(pk.get("kind"))
				var plabel: String = ["Health Pickup", "Cash Pickup", "Package Pickup"][clampi(pkind, 0, 2)]
				out.append({
					"id": "ow_pk:%d" % pk.get_instance_id(),
					"label": plabel,
					"category": Category.LOOT,
					"position": pk.global_position,
					"distance": origin.distance_to(pk.global_position),
					"node": pk
				})
	if cat in [Category.ALL, Category.ENEMIES]:
		var tree := game.get_tree()
		if tree:
			var enemy_candidates: Array[Dictionary] = []
			var wanted := int(game.get_wanted()) if game.has_method("get_wanted") else 0
			for node in tree.get_nodes_in_group("foot_cops"):
				var fc := node as Node3D
				if fc == null or not is_instance_valid(fc) or bool(fc.get("downed")):
					continue
				var d := origin.distance_to(fc.global_position)
				enemy_candidates.append({"id": "cop:%d" % fc.get_instance_id(), "label": "Base Officer", "category": Category.ENEMIES, "position": fc.global_position, "distance": d, "node": fc})
			var cops_arr = game.get("cops")
			if cops_arr is Array:
				for cop in cops_arr:
					if cop is Node3D and is_instance_valid(cop) and not bool(cop.get("occupied")) and not bool(cop.get("wrecked")):
						var d := origin.distance_to(cop.global_position)
						var chasing := wanted > 0 and cop.get("chase_target") != null
						var label := "Police Unit (Chasing)" if chasing else "Police Unit"
						enemy_candidates.append({"id": "copcar:%d" % cop.get_instance_id(), "label": label, "category": Category.ENEMIES, "position": cop.global_position, "distance": d, "node": cop})
			enemy_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
			for i in mini(enemy_candidates.size(), 10):
				out.append(enemy_candidates[i])
	if cat in [Category.ALL, Category.CIVILIANS]:
		var tree := game.get_tree()
		if tree:
			var civ_candidates: Array[Dictionary] = []
			for node in tree.get_nodes_in_group("peds"):
				var ped := node as Node3D
				if ped == null or not is_instance_valid(ped) or bool(ped.get("downed")) or bool(ped.get("is_officer")):
					continue
				var d := origin.distance_to(ped.global_position)
				if d <= 120.0:
					civ_candidates.append({"id": "civ:%d" % ped.get_instance_id(), "label": "Civilian Pedestrian", "category": Category.CIVILIANS, "position": ped.global_position, "distance": d, "node": ped})
			civ_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
			for i in mini(civ_candidates.size(), 10):
				out.append(civ_candidates[i])
