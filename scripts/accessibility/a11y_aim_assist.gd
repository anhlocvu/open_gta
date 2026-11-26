class_name A11yAimAssist
extends RefCounted
## Universal Radar target facing (O), plus LOS-validated quick enemy snap (Shift+O) and acoustic crosshair ping.

var _crosshair_cd := 0.0


func find_best_visible_enemy(game: Node, player: Player, camera: CameraRig, max_range := 80.0, cone_cos := -1.0) -> Dictionary:
	if game == null or player == null or camera == null or not player.is_inside_tree():
		return {}
	var cam := camera.camera()
	var eye := cam.global_position if cam else (player.global_position + Vector3.UP * 1.5)
	var look_dir := -cam.global_basis.z if cam else A11yRadar.forward_from_yaw(camera.yaw)
	var space := player.get_world_3d().direct_space_state
	var candidates: Array[Dictionary] = []
	var tree := player.get_tree()
	if tree:
		for node in tree.get_nodes_in_group("foot_cops"):
			var fc := node as Node3D
			if fc and is_instance_valid(fc) and not bool(fc.get("downed")):
				candidates.append({"node": fc, "label": "Base Officer", "aim_point": fc.global_position + Vector3.UP * 1.1, "priority": 0.5})
		for node in tree.get_nodes_in_group("peds"):
			var ped := node as Node3D
			if ped and is_instance_valid(ped) and not bool(ped.get("downed")) and not bool(ped.get("is_officer")):
				candidates.append({"node": ped, "label": "Civilian Pedestrian", "aim_point": ped.global_position + Vector3.UP * 1.1, "priority": 0.0})
	var best: Dictionary = {}
	var best_score := -INF
	for c in candidates:
		var target_node: Node3D = c.node
		var aim_pt: Vector3 = c.aim_point
		var offset := aim_pt - eye
		var dist := offset.length()
		if dist < 0.2 or dist > max_range:
			continue
		var dir := offset / dist
		var dot := look_dir.dot(dir)
		if dot < cone_cos:
			continue
		var query := PhysicsRayQueryParameters3D.create(eye, aim_pt + dir * 0.25, 1 | 2 | 4 | 8 | 16, [player.get_rid()])
		var hit := space.intersect_ray(query)
		if hit.is_empty() or hit.collider != target_node:
			continue
		var score := dot * 2.0 + float(c.priority) - dist / max_range
		if score > best_score:
			best_score = score
			best = {
				"node": target_node,
				"label": c.label,
				"aim_point": aim_pt,
				"distance": dist,
				"alignment": clampf((dot - 0.85) / 0.15, 0.0, 1.0),
				"dot": dot
			}
	return best


func tick_crosshair(game: Node, player: Player, camera: CameraRig, audio: A11ySpatialAudio, settings: A11ySettings, delta: float) -> void:
	_crosshair_cd = maxf(_crosshair_cd - delta, 0.0)
	if settings == null or not settings.acoustic_crosshair_enabled or audio == null:
		return
	if player == null or player.locked or player.in_vehicle or player.weapon == Arsenal.Id.NONE:
		return
	if _crosshair_cd > 0.0:
		return
	var found := find_best_visible_enemy(game, player, camera, 85.0, cos(deg_to_rad(24.0)))
	if found.is_empty():
		return
	var align := float(found.alignment)
	audio.play_crosshair_ping(align)
	_crosshair_cd = lerpf(0.24, 0.09, align)


func snap_to_visible_enemy(game: Node, player: Player, camera: CameraRig, settings: A11ySettings) -> Dictionary:
	if settings == null or not settings.aim_assist_enabled:
		return {"locked": false, "reason": "Aim assist is disabled in settings."}
	if player == null or camera == null or player.locked or player.in_vehicle:
		return {"locked": false, "reason": ""}
	var found := find_best_visible_enemy(game, player, camera, 95.0, -1.0)
	if found.is_empty():
		return {"locked": false, "reason": "No target in sight."}
	var eye_height := 0.94 if player.crouched else 1.5
	var pivot := player.global_position + Vector3.UP * eye_height
	var delta_vec: Vector3 = found.aim_point - pivot
	var horiz := Vector2(delta_vec.x, delta_vec.z).length()
	camera.yaw = atan2(-delta_vec.x, -delta_vec.z)
	camera.pitch = clampf(atan2(delta_vec.y, maxf(horiz, 0.01)), -1.35, 1.35)
	if not player.in_cover:
		player.rotation.y = camera.yaw
	return {
		"locked": true,
		"label": str(found.label),
		"distance": int(round(float(found.distance))),
		"bearing": A11yRadar.relative_bearing_text(player.global_position, camera.yaw, found.aim_point)
	}


func face_radar_target(game: Node, player: Player, camera: CameraRig, radar: A11yRadar) -> Dictionary:
	if game == null or player == null or camera == null or player.locked or not player.is_inside_tree():
		return {"locked": false, "reason": ""}
	var origin_node: Node3D = game.tracked_node() if game.has_method("tracked_node") and game.tracked_node() != null else player
	var origin := origin_node.global_position
	var chosen: Dictionary = {}
	if radar != null and radar.locked_target_id != "":
		chosen = radar.resolve_locked_target(game, origin)
		if chosen.is_empty():
			radar.locked_target_id = ""
	if chosen.is_empty() and game.has_method("objective_info"):
		var obj: Dictionary = game.objective_info()
		var opos: Vector3 = obj.get("position", Vector3.ZERO)
		if opos != Vector3.ZERO:
			chosen = {"id": "ow:objective", "label": str(obj.get("label", "Current Objective")), "position": opos, "distance": origin.distance_to(opos), "node": null, "aim_height": 1.2}
	if chosen.is_empty() and radar != null:
		var items := radar.collect_targets(game, origin, radar.selected_category)
		if items.is_empty() and radar.selected_category != A11yRadar.Category.ALL:
			items = radar.collect_targets(game, origin, A11yRadar.Category.ALL)
		if not items.is_empty():
			chosen = items[0]
			radar.locked_target_id = str(chosen.get("id", ""))
			chosen = radar.resolve_locked_target(game, origin)
			if chosen.is_empty():
				chosen = items[0]
	if chosen.is_empty():
		return {"locked": false, "reason": "No radar target available."}

	var target_pos: Vector3 = chosen.get("position", origin)
	var aim_h := float(chosen.get("aim_height", 1.1))
	var target_node: Node3D = chosen.get("node", null) as Node3D
	if target_node != null and is_instance_valid(target_node) and aim_h == 1.1 and target_node is Vehicle:
		aim_h = 0.72
	var aim_pt := target_pos + Vector3.UP * aim_h
	var eye_height := 1.4 if player.in_vehicle else (0.94 if player.crouched else 1.5)
	var pivot := origin + Vector3.UP * eye_height
	var delta_vec := aim_pt - pivot
	if Vector2(delta_vec.x, delta_vec.z).length_squared() < 0.0004:
		return {"locked": true, "label": str(chosen.get("label", "Target")), "distance": 0, "clear": true, "hp": float(chosen.get("hp", -1.0))}

	var horiz := Vector2(delta_vec.x, delta_vec.z).length()
	camera.yaw = atan2(-delta_vec.x, -delta_vec.z)
	camera.pitch = clampf(atan2(delta_vec.y, maxf(horiz, 0.01)), -1.35, 1.35)
	if not player.in_vehicle and not player.in_cover:
		player.rotation.y = camera.yaw

	var exclude: Array[RID] = [player.get_rid()]
	var active_veh := game.get("active_vehicle") as Vehicle
	if active_veh and is_instance_valid(active_veh):
		exclude.append(active_veh.get_rid())
	var space := player.get_world_3d().direct_space_state
	var clear := true
	if target_node != null and is_instance_valid(target_node):
		var dir := delta_vec.normalized()
		var q := PhysicsRayQueryParameters3D.create(pivot, aim_pt + dir * 0.25, 1 | 4 | 8 | 16, exclude)
		var hit := space.intersect_ray(q)
		clear = hit.is_empty() or hit.collider == target_node
	else:
		var dist := delta_vec.length()
		if dist > 2.0:
			var q := PhysicsRayQueryParameters3D.create(pivot, pivot + delta_vec.normalized() * (dist - 1.5), 1, exclude)
			clear = space.intersect_ray(q).is_empty()

	var hp_val := float(chosen.get("hp", -1.0))
	if hp_val < 0.0 and target_node is Vehicle:
		hp_val = float((target_node as Vehicle).hp)
	return {
		"locked": true,
		"label": str(chosen.get("label", "Target")),
		"distance": int(round(origin.distance_to(target_pos))),
		"clear": clear,
		"hp": hp_val
	}
