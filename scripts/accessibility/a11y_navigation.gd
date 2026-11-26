class_name A11yNavigation
extends RefCounted
## Keyboard camera turning, 3D audio beacons, obstacle/cover proximity, and resilient Auto-Walk / Auto-Drive.

const AUTODRIVE_WALL_SLOW_DIST := 20.0
const AUTODRIVE_EMERGENCY_DIST := 3.8
const AUTODRIVE_BUMPER_OFFSET := 2.15
const AUTODRIVE_HALF_WIDTH := 0.96
const AUTODRIVE_WIDE_SIDE_DIST := 3.2
const AUTODRIVE_CORNER_LOOKAHEAD := 22.0

var beacon_active := false
var autowalk_active := false
var autopilot_mode := "walk"
var track_objective := false
var target_label := "Objective"
var target_position := Vector3.ZERO
var current_waypoint := Vector3.ZERO

var _beacon_timer := 0.0
var _obstacle_timer := 0.0
var _cover_hint_cooldown := 0.0
var _last_turn_hint := ""
var _route_timer := 0.0
var _cached_waypoint := Vector3.ZERO
var _cached_dest := Vector3.ZERO
var _path_points := PackedVector3Array()
var _path_node_ids := PackedInt32Array()
var _path_idx := 0
var _blocked_edges: Dictionary = {}

var _progress_anchor := Vector3.ZERO
var _stall_timer := 0.0
var _recovery_timer := 0.0
var _recovery_steer := 0.0
var _recovery_throttle := 0.0
var _recovery_move := Vector2.ZERO
var _avoid_side := 0.0
var _avoid_hold_timer := 0.0
var _reroute_speech_cd := 0.0
var _reroute_penalty_cd := 0.0
var _touch_ref: TouchControls


func reset(player: Player = null, vehicle: Vehicle = null) -> void:
	autowalk_active = false
	autopilot_mode = "walk"
	track_objective = false
	beacon_active = false
	target_position = Vector3.ZERO
	current_waypoint = Vector3.ZERO
	_last_turn_hint = ""
	_route_timer = 0.0
	_cached_waypoint = Vector3.ZERO
	_cached_dest = Vector3.ZERO
	_path_points = PackedVector3Array()
	_path_node_ids = PackedInt32Array()
	_path_idx = 0
	_blocked_edges.clear()
	_clear_recovery()
	if player and is_instance_valid(player):
		player.a11y_move_override = Vector2.ZERO
	_clear_vehicle_override(player, vehicle)


func _clear_recovery() -> void:
	_progress_anchor = Vector3.ZERO
	_stall_timer = 0.0
	_recovery_timer = 0.0
	_recovery_steer = 0.0
	_recovery_throttle = 0.0
	_recovery_move = Vector2.ZERO
	_avoid_side = 0.0
	_avoid_hold_timer = 0.0
	_reroute_penalty_cd = 0.0


func _clear_vehicle_override(player: Player = null, vehicle: Vehicle = null, preserve_handbrake := false) -> void:
	var veh := vehicle
	if veh == null and player and is_instance_valid(player) and player.is_inside_tree():
		var g := player.get_tree().current_scene
		if g and g.get("active_vehicle") is Vehicle:
			veh = g.active_vehicle as Vehicle
	if veh and is_instance_valid(veh):
		veh.a11y_drive_override = Vector2.ZERO
		if not preserve_handbrake:
			veh.a11y_handbrake = false


func stop_autowalk(player: Player, reason := "", vehicle: Vehicle = null, preserve_handbrake := false) -> void:
	var was_active := autowalk_active
	autowalk_active = false
	autopilot_mode = "walk"
	track_objective = false
	_clear_recovery()
	if player and is_instance_valid(player):
		player.a11y_move_override = Vector2.ZERO
	_clear_vehicle_override(player, vehicle, preserve_handbrake)
	if was_active and reason != "":
		A11yUIHelper.say(reason, true, 2, &"a11y_nav", true)


func handle_turn_press(event: InputEvent, camera: CameraRig, settings: A11ySettings) -> bool:
	if camera == null or settings == null:
		return false
	if A11yUIHelper.action_pressed(event, &"a11y_center_pitch"):
		camera.pitch = -0.04
		A11yUIHelper.say("Horizon level, facing %s" % A11yRadar.compass_heading(camera.yaw), true, 2, &"a11y_compass", true)
		return true
	if not settings.snap_turn_enabled:
		return false
	if A11yUIHelper.action_pressed(event, &"a11y_turn_left"):
		camera.yaw += deg_to_rad(settings.snap_turn_degrees)
		A11yUIHelper.say(A11yRadar.compass_heading(camera.yaw), true, 2, &"a11y_compass", true)
		return true
	if A11yUIHelper.action_pressed(event, &"a11y_turn_right"):
		camera.yaw -= deg_to_rad(settings.snap_turn_degrees)
		A11yUIHelper.say(A11yRadar.compass_heading(camera.yaw), true, 2, &"a11y_compass", true)
		return true
	return false


func start_autowalk(mode := "walk") -> void:
	autowalk_active = true
	autopilot_mode = mode
	_last_turn_hint = ""
	_route_timer = 0.0
	_cached_waypoint = Vector3.ZERO
	_cached_dest = Vector3.ZERO
	_path_points = PackedVector3Array()
	_path_node_ids = PackedInt32Array()
	_path_idx = 0
	_blocked_edges.clear()
	_clear_recovery()


func start_autodrive() -> void:
	start_autowalk("drive")


func process_camera_turn(camera: CameraRig, settings: A11ySettings, delta: float, player_locked := false) -> void:
	if camera == null or settings == null or player_locked:
		return
	if not settings.snap_turn_enabled:
		var turn := Input.get_action_strength("a11y_turn_left") - Input.get_action_strength("a11y_turn_right")
		if absf(turn) > 0.01:
			camera.yaw += turn * settings.keyboard_turn_speed * delta
	var pitch_in := Input.get_action_strength("a11y_look_up") - Input.get_action_strength("a11y_look_down")
	if absf(pitch_in) > 0.01:
		var lo := -0.92 if camera.aircraft_mode else (-1.4 if camera.first_person else -1.1)
		var hi := 0.42 if camera.aircraft_mode else (1.4 if camera.first_person else 0.85)
		camera.pitch = clampf(camera.pitch + pitch_in * (settings.keyboard_turn_speed * 0.65) * delta, lo, hi)


func _corridor_clear(space: PhysicsDirectSpaceState3D, origin: Vector3, destination: Vector3, half_width: float, exclude_rids: Array[RID], mask: int = 1) -> bool:
	if space == null:
		return true
	var flat := Vector3(destination.x - origin.x, 0.0, destination.z - origin.z)
	if flat.length_squared() < 0.05:
		return true
	var fwd := flat.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var up := Vector3.UP * 0.9
	for off in [0.0, -half_width, half_width]:
		var shift: Vector3 = right * float(off)
		var q := PhysicsRayQueryParameters3D.create(origin + up + shift, destination + up + shift, mask, exclude_rids)
		if not space.intersect_ray(q).is_empty():
			return false
	return true


func compute_route_waypoint(game: Node, origin: Vector3, destination: Vector3, corridor_half_w := 0.45, mask := 1, extra_exclude: Array[RID] = []) -> Dictionary:
	var roads: RoadGraph = game.get("roads") as RoadGraph if game else null
	var player := game.get("player") as Player if game else null
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state if (player and player.is_inside_tree()) else null
	var exclude: Array[RID] = []
	if player and player.is_inside_tree():
		exclude.append(player.get_rid())
	for rid in extra_exclude:
		exclude.append(rid)

	var flat_dist := Vector2(destination.x - origin.x, destination.z - origin.z).length()
	if roads == null or roads.nodes.is_empty():
		return {"waypoint": destination, "path": PackedVector3Array([destination]), "node_ids": PackedInt32Array(), "uses_astar": false}
	if flat_dist <= 45.0 and _corridor_clear(space, origin, destination, corridor_half_w, exclude, mask):
		return {"waypoint": destination, "path": PackedVector3Array([destination]), "node_ids": PackedInt32Array(), "uses_astar": false}

	var res := roads.astar_path(origin, destination, _blocked_edges, space, exclude)
	var pts: PackedVector3Array = res.points
	var nids: PackedInt32Array = res.node_ids
	if pts.is_empty():
		return {"waypoint": destination, "path": PackedVector3Array([destination]), "node_ids": PackedInt32Array(), "uses_astar": false}
	var start_idx := 0
	if pts.size() >= 2 and Vector2(pts[0].x - origin.x, pts[0].z - origin.z).length() < 8.0:
		start_idx = 1
	elif pts.size() >= 2 and _corridor_clear(space, origin, pts[1], corridor_half_w, exclude, mask):
		var to_first := Vector2(pts[0].x - origin.x, pts[0].z - origin.z)
		var to_second := Vector2(pts[1].x - origin.x, pts[1].z - origin.z)
		if to_first.length() < 26.0 and to_first.dot(to_second) < 0.0:
			start_idx = 1
	return {"waypoint": pts[start_idx], "path": pts, "node_ids": nids, "start_idx": start_idx, "uses_astar": true}


func tick(game: Node, player: Player, camera: CameraRig, audio: A11ySpatialAudio, settings: A11ySettings, delta: float) -> void:
	if player == null or not is_instance_valid(player) or camera == null or settings == null:
		return
	_reroute_speech_cd = maxf(_reroute_speech_cd - delta, 0.0)
	_reroute_penalty_cd = maxf(_reroute_penalty_cd - delta, 0.0)
	_avoid_hold_timer = maxf(_avoid_hold_timer - delta, 0.0)
	if player.locked or player.health <= 0.0:
		if autowalk_active:
			stop_autowalk(player)
		return

	var active_veh := game.get("active_vehicle") as Vehicle if game else null
	var active_air := game.get("active_aircraft") as Aircraft if game else null
	if autowalk_active:
		if autopilot_mode == "drive":
			if active_veh == null or not is_instance_valid(active_veh) or active_veh.exploded or active_veh.burning or not player.in_vehicle:
				var danger_stop := active_veh != null and is_instance_valid(active_veh) and (active_veh.exploded or active_veh.burning)
				stop_autowalk(player, "" if danger_stop else "Auto-drive stopped.", active_veh)
			elif _manual_drive_pressed(player):
				stop_autowalk(player, "Auto-drive cancelled.", active_veh)
			elif target_position == Vector3.ZERO:
				stop_autowalk(player, "Auto-drive stopped.", active_veh)
			else:
				_tick_autodrive(game, player, active_veh, delta)
		else:
			if player.in_vehicle or active_air != null or target_position == Vector3.ZERO:
				stop_autowalk(player, "Auto-walk stopped.", active_veh)
			elif _manual_move_pressed(player):
				stop_autowalk(player, "Auto-walk cancelled.")
			else:
				_tick_autowalk(game, player, camera, delta)

	var origin := active_veh.global_position if (active_veh and is_instance_valid(active_veh) and player.in_vehicle) else player.global_position
	if (beacon_active or autowalk_active) and settings.beacon_enabled and target_position != Vector3.ZERO:
		_beacon_timer -= delta
		if _beacon_timer <= 0.0:
			var dist := origin.distance_to(target_position)
			_beacon_timer = clampf(dist / 26.0, 0.35, 1.25)
			if not autowalk_active:
				var beacon_excl: Array[RID] = []
				if active_veh and is_instance_valid(active_veh) and player.in_vehicle:
					beacon_excl.append(active_veh.get_rid())
				var route_info := compute_route_waypoint(game, origin, target_position, 0.45, 1, beacon_excl)
				current_waypoint = route_info.waypoint
			if audio:
				audio.play_beacon_ping(current_waypoint + Vector3.UP * 1.2, dist < 10.0)
	if settings.obstacle_cues_enabled and not player.in_vehicle:
		_tick_obstacles(player, camera, audio, delta)


func _refresh_route(game: Node, origin: Vector3, corridor_w: float, mask: int, exclude: Array[RID], delta: float) -> void:
	_route_timer = maxf(_route_timer - delta, 0.0)
	var dist_wp := INF
	if _cached_waypoint != Vector3.ZERO:
		dist_wp = Vector2(_cached_waypoint.x - origin.x, _cached_waypoint.z - origin.z).length()
	var advance_dist := 6.5 if autopilot_mode == "drive" else 2.4
	if _path_points.size() > 0 and _path_idx < _path_points.size() - 1 and dist_wp < advance_dist:
		_path_idx += 1
		_cached_waypoint = _path_points[_path_idx]
		current_waypoint = _cached_waypoint
		return
	var dest_moved := _cached_dest.distance_to(target_position) > 3.0
	if _route_timer <= 0.0 or _cached_waypoint == Vector3.ZERO or dest_moved:
		var info := compute_route_waypoint(game, origin, target_position, corridor_w, mask, exclude)
		_path_points = info.path
		_path_node_ids = info.get("node_ids", PackedInt32Array())
		_path_idx = int(info.get("start_idx", 0))
		_cached_waypoint = info.waypoint
		_cached_dest = target_position
		_route_timer = 0.65 if autopilot_mode == "drive" else 0.5
	current_waypoint = _cached_waypoint


func _penalize_current_edge() -> void:
	if _path_node_ids.size() >= 2:
		var node_idx := clampi(_path_idx, 0, _path_node_ids.size() - 1)
		if node_idx > 0:
			var key := RoadGraph.edge_key(_path_node_ids[node_idx - 1], _path_node_ids[node_idx])
			_blocked_edges[key] = int(_blocked_edges.get(key, 0)) + 1
		elif _path_node_ids.size() >= 2:
			var key0 := RoadGraph.edge_key(_path_node_ids[0], _path_node_ids[1])
			_blocked_edges[key0] = int(_blocked_edges.get(key0, 0)) + 1
	_route_timer = 0.0
	_cached_waypoint = Vector3.ZERO


func _scan_whiskers(space: PhysicsDirectSpaceState3D, origin: Vector3, fwd: Vector3, reach: float, exclude: Array[RID], mask: int) -> Dictionary:
	var out := {"center_hit": {}, "center_dist": reach, "left_score": reach, "right_score": reach}
	if space == null:
		return out
	var chest := origin + Vector3.UP * 0.85
	var q_center := PhysicsRayQueryParameters3D.create(chest, chest + fwd * reach, mask, exclude)
	var hit_c := space.intersect_ray(q_center)
	if not hit_c.is_empty():
		out["center_hit"] = hit_c
		out["center_dist"] = origin.distance_to(hit_c.position)
	var left_sum := 0.0
	var right_sum := 0.0
	for deg in [28.0, 58.0, 86.0]:
		var rad := deg_to_rad(deg)
		var dir_l := (Basis(Vector3.UP, rad) * fwd).normalized()
		var dir_r := (Basis(Vector3.UP, -rad) * fwd).normalized()
		var hl := space.intersect_ray(PhysicsRayQueryParameters3D.create(chest, chest + dir_l * reach, mask, exclude))
		var hr := space.intersect_ray(PhysicsRayQueryParameters3D.create(chest, chest + dir_r * reach, mask, exclude))
		left_sum += reach if hl.is_empty() else origin.distance_to(hl.position)
		right_sum += reach if hr.is_empty() else origin.distance_to(hr.position)
	out["left_score"] = left_sum / 3.0
	out["right_score"] = right_sum / 3.0
	return out


func _tick_autowalk(game: Node, player: Player, camera: CameraRig, delta: float) -> void:
	if player.in_cover:
		player.exit_cover()
	var origin := player.global_position
	var dist_total := Vector2(target_position.x - origin.x, target_position.z - origin.z).length()
	if dist_total <= 2.2:
		stop_autowalk(player, "Arrived at %s." % target_label)
		return

	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state if player.is_inside_tree() else null
	var exclude: Array[RID] = [player.get_rid()]
	_refresh_route(game, origin, 0.42, 1 | 4 | 8, exclude, delta)

	# Progress tracking based on actual movement, never cancelling on temporary detours.
	if _progress_anchor == Vector3.ZERO or Vector2(origin.x - _progress_anchor.x, origin.z - _progress_anchor.z).length() > 0.65:
		_progress_anchor = origin
		_stall_timer = 0.0
	else:
		_stall_timer += delta

	if _recovery_timer > 0.0:
		_recovery_timer = maxf(_recovery_timer - delta, 0.0)
		player.a11y_move_override = _recovery_move
		return

	var to_wp := Vector3(current_waypoint.x - origin.x, 0.0, current_waypoint.z - origin.z)
	var desired_dir := to_wp.normalized() if to_wp.length_squared() > 0.01 else A11yRadar.forward_from_yaw(camera.yaw)
	var whiskers := _scan_whiskers(space, origin, desired_dir, 3.6, exclude, 1 | 4 | 8)
	var center_hit: Dictionary = whiskers["center_hit"]
	var center_dist := float(whiskers["center_dist"])
	var steer_dir := desired_dir
	var move_vec := Vector2(0.0, -1.0)

	if not center_hit.is_empty() and center_dist < 2.6:
		if _avoid_hold_timer <= 0.0 or _avoid_side == 0.0:
			_avoid_side = -1.0 if float(whiskers["left_score"]) >= float(whiskers["right_score"]) else 1.0
			_avoid_hold_timer = 1.25
		var norm: Vector3 = center_hit.normal
		norm.y = 0.0
		if norm.length_squared() > 0.01:
			norm = norm.normalized()
			var tangent := Vector3(-norm.z, 0.0, norm.x) * _avoid_side
			if tangent.dot(Basis(Vector3.UP, _avoid_side * 1.2) * desired_dir) < 0.0:
				tangent = -tangent
			steer_dir = (tangent * 0.92 + norm * 0.25).normalized()
		else:
			steer_dir = (Basis(Vector3.UP, -_avoid_side * 1.15) * desired_dir).normalized()
	elif _avoid_hold_timer > 0.0 and _avoid_side != 0.0:
		# Keep brief clearance margin past a wall corner before snapping back.
		var side_check := _scan_whiskers(space, origin, desired_dir, 2.0, exclude, 1 | 4 | 8)
		if float(side_check["center_dist"]) < 1.9:
			steer_dir = (Basis(Vector3.UP, -_avoid_side * 0.85) * desired_dir).normalized()

	if _stall_timer > 1.1:
		_stall_timer = 0.0
		if player.tactical and player.try_mantle():
			return
		var side := -1.0 if float(whiskers["left_score"]) >= float(whiskers["right_score"]) else 1.0
		_avoid_side = side
		_avoid_hold_timer = 1.6
		_recovery_timer = 0.75
		_recovery_move = Vector2(side * 0.92, 0.35 if center_dist < 1.2 else -0.45).normalized()
		_penalize_current_edge()
		if _reroute_speech_cd <= 0.0:
			_reroute_speech_cd = 5.0
			A11yUIHelper.say("Rerouting around obstacle.", false, 1, &"a11y_turn_hint")
		player.a11y_move_override = _recovery_move
		return

	var desired_yaw := atan2(-steer_dir.x, -steer_dir.z)
	var turn_rate := 12.0 if (not center_hit.is_empty() and center_dist < 2.6) else 7.5
	camera.yaw = lerp_angle(camera.yaw, desired_yaw, 1.0 - exp(-turn_rate * delta))
	player.a11y_move_override = move_vec

	var turn_hint := A11yRadar.relative_bearing_text(origin, camera.yaw, current_waypoint)
	if turn_hint != _last_turn_hint and turn_hint in ["to your left", "to your right", "behind left", "behind right"]:
		_last_turn_hint = turn_hint
		A11yUIHelper.say("Turning " + turn_hint, false, 1, &"a11y_turn_hint")


func _scan_drive_corridor(space: PhysicsDirectSpaceState3D, origin: Vector3, fwd: Vector3, reach: float, exclude: Array[RID], mask: int) -> Dictionary:
	var out := {
		"bumper_dist": reach,
		"left_bumper_dist": reach,
		"right_bumper_dist": reach,
		"left_open": 22.0,
		"right_open": 22.0,
		"side_min": 7.0,
	}
	if space == null:
		return out
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var chest := origin + Vector3.UP * 0.72
	var min_bumper := reach
	for off in [-AUTODRIVE_HALF_WIDTH, 0.0, AUTODRIVE_HALF_WIDTH]:
		var start := chest + right * float(off)
		var q := PhysicsRayQueryParameters3D.create(start, chest + fwd * (reach + AUTODRIVE_BUMPER_OFFSET) + right * float(off), mask, exclude)
		var hit := space.intersect_ray(q)
		var dist := reach
		if not hit.is_empty():
			dist = maxf(0.0, (hit.position - origin).dot(fwd) - AUTODRIVE_BUMPER_OFFSET)
		min_bumper = minf(min_bumper, dist)
		if off < 0.0:
			out["left_bumper_dist"] = dist
		elif off > 0.0:
			out["right_bumper_dist"] = dist
	out["bumper_dist"] = min_bumper

	var escape_reach := 22.0
	var left_sum := 0.0
	var right_sum := 0.0
	for deg in [24.0, 52.0, 82.0]:
		var rad := deg_to_rad(deg)
		var dir_l := (Basis(Vector3.UP, rad) * fwd).normalized()
		var dir_r := (Basis(Vector3.UP, -rad) * fwd).normalized()
		var hl := space.intersect_ray(PhysicsRayQueryParameters3D.create(chest, chest + dir_l * escape_reach, mask, exclude))
		var hr := space.intersect_ray(PhysicsRayQueryParameters3D.create(chest, chest + dir_r * escape_reach, mask, exclude))
		left_sum += escape_reach if hl.is_empty() else origin.distance_to(hl.position)
		right_sum += escape_reach if hr.is_empty() else origin.distance_to(hr.position)
	out["left_open"] = left_sum / 3.0 + float(out["left_bumper_dist"]) * 0.15
	out["right_open"] = right_sum / 3.0 + float(out["right_bumper_dist"]) * 0.15

	var side_reach := 7.0
	var hl_side := space.intersect_ray(PhysicsRayQueryParameters3D.create(chest, chest - right * side_reach, mask, exclude))
	var hr_side := space.intersect_ray(PhysicsRayQueryParameters3D.create(chest, chest + right * side_reach, mask, exclude))
	var left_clear := side_reach if hl_side.is_empty() else maxf(0.0, origin.distance_to(hl_side.position) - AUTODRIVE_HALF_WIDTH)
	var right_clear := side_reach if hr_side.is_empty() else maxf(0.0, origin.distance_to(hr_side.position) - AUTODRIVE_HALF_WIDTH)
	out["side_min"] = minf(left_clear, right_clear)
	return out


func _upcoming_turn_angle(origin: Vector3, fwd: Vector3) -> float:
	if _path_points.size() < 2 or _path_idx >= _path_points.size() - 1:
		return 0.0
	var wp := _path_points[_path_idx]
	var to_wp := Vector3(wp.x - origin.x, 0.0, wp.z - origin.z)
	if to_wp.length() > AUTODRIVE_CORNER_LOOKAHEAD:
		return 0.0
	var nxt := _path_points[_path_idx + 1]
	var seg := Vector3(nxt.x - wp.x, 0.0, nxt.z - wp.z)
	if seg.length_squared() < 0.05:
		return 0.0
	var cur_dir := to_wp.normalized() if to_wp.length_squared() > 0.05 else fwd
	return absf(cur_dir.signed_angle_to(seg.normalized(), Vector3.UP))


func _autodrive_target_speed(vehicle: Vehicle, bumper_dist: float, side_min: float, steer_angle: float, upcoming_turn: float, dist_total: float) -> float:
	var target_speed := vehicle.max_speed
	var fwd_speed := maxf(vehicle.speed, 0.0)
	var brake_horizon := maxf(AUTODRIVE_WALL_SLOW_DIST, (fwd_speed * fwd_speed) / maxf(vehicle.brake_rate * 4.4, 1.0) + 6.0)
	if bumper_dist <= AUTODRIVE_WALL_SLOW_DIST:
		var t := clampf((bumper_dist - AUTODRIVE_EMERGENCY_DIST) / (AUTODRIVE_WALL_SLOW_DIST - AUTODRIVE_EMERGENCY_DIST), 0.0, 1.0)
		target_speed = minf(target_speed, lerpf(0.0, 26.0, t * t))
	elif bumper_dist <= brake_horizon:
		var bt := clampf((bumper_dist - AUTODRIVE_WALL_SLOW_DIST) / maxf(brake_horizon - AUTODRIVE_WALL_SLOW_DIST, 0.1), 0.0, 1.0)
		target_speed = minf(target_speed, lerpf(26.0, vehicle.max_speed, bt))
	if side_min < AUTODRIVE_WIDE_SIDE_DIST:
		target_speed = minf(target_speed, lerpf(12.0, 32.0, clampf(side_min / AUTODRIVE_WIDE_SIDE_DIST, 0.0, 1.0)))
	if absf(steer_angle) > 0.35:
		target_speed = minf(target_speed, lerpf(36.0, 12.0, clampf((absf(steer_angle) - 0.35) / 1.1, 0.0, 1.0)))
	if upcoming_turn > 0.45:
		target_speed = minf(target_speed, lerpf(32.0, 13.0, clampf((upcoming_turn - 0.45) / 1.1, 0.0, 1.0)))
	if dist_total < 22.0:
		target_speed = minf(target_speed, lerpf(8.0, 28.0, clampf(dist_total / 22.0, 0.0, 1.0)))
	return maxf(target_speed, 0.0)


func _has_rear_clearance(space: PhysicsDirectSpaceState3D, origin: Vector3, fwd: Vector3, speed: float, exclude: Array[RID], mask: int) -> bool:
	if space == null:
		return true
	var rear_reach := maxf(4.8, absf(speed) * 0.3 + 4.0)
	var rear_q := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.72, origin + Vector3.UP * 0.72 - fwd * rear_reach, mask, exclude)
	return space.intersect_ray(rear_q).is_empty()


func _handle_autodrive_recovery(space: PhysicsDirectSpaceState3D, origin: Vector3, fwd: Vector3, vehicle: Vehicle, bumper_dist: float, left_open: float, right_open: float, exclude: Array[RID], delta: float) -> bool:
	if _recovery_timer > 0.0:
		_recovery_timer = maxf(_recovery_timer - delta, 0.0)
		if not _has_rear_clearance(space, origin, fwd, vehicle.speed, exclude, 1 | 4 | 8):
			_recovery_timer = 0.0
			vehicle.a11y_handbrake = true
			vehicle.a11y_drive_override = Vector2.ZERO
			return true
		if _recovery_timer > 0.0:
			vehicle.a11y_handbrake = false
			vehicle.a11y_drive_override = Vector2(_recovery_steer, _recovery_throttle)
			return true

	if (bumper_dist <= AUTODRIVE_EMERGENCY_DIST and vehicle.speed <= 4.0) or _stall_timer > 1.1:
		_stall_timer = 0.0
		_avoid_hold_timer = 0.0
		var clear_left := left_open >= right_open
		if _reroute_penalty_cd <= 0.0:
			_reroute_penalty_cd = 1.2
			_penalize_current_edge()
		if not _has_rear_clearance(space, origin, fwd, vehicle.speed, exclude, 1 | 4 | 8):
			# Boxed in front and back: hold brake/steer toward open side without rear-slamming.
			vehicle.a11y_handbrake = bumper_dist <= 2.4 or vehicle.speed > 1.5
			vehicle.a11y_drive_override = Vector2(-0.95 if clear_left else 0.95, 0.0 if vehicle.a11y_handbrake else 0.25)
			return true
		_recovery_timer = 0.95
		_recovery_throttle = -0.35
		# In reverse (speed < 0), positive steer turns nose left while backing tail right.
		_recovery_steer = 0.95 if clear_left else -0.95
		if _reroute_speech_cd <= 0.0:
			_reroute_speech_cd = 5.0
			A11yUIHelper.say("Reversing and rerouting.", false, 1, &"a11y_turn_hint")
		vehicle.a11y_handbrake = false
		vehicle.a11y_drive_override = Vector2(_recovery_steer, _recovery_throttle)
		return true
	return false


func _tick_autodrive(game: Node, _player: Player, vehicle: Vehicle, delta: float) -> void:
	var origin := vehicle.global_position
	var dist_total := Vector2(target_position.x - origin.x, target_position.z - origin.z).length()
	var arrive_radius := 4.4 if (target_label in ["Pay and Spray", "Drop Warehouse"]) else 7.5
	if dist_total <= arrive_radius:
		vehicle.a11y_handbrake = true
		stop_autowalk(_player, "Arrived at %s." % target_label, vehicle, true)
		return

	var space: PhysicsDirectSpaceState3D = vehicle.get_world_3d().direct_space_state if vehicle.is_inside_tree() else null
	var exclude: Array[RID] = [vehicle.get_rid()]
	_refresh_route(game, origin, 1.15, 1 | 4 | 8, exclude, delta)

	if _progress_anchor == Vector3.ZERO or Vector2(origin.x - _progress_anchor.x, origin.z - _progress_anchor.z).length() > 1.1:
		_progress_anchor = origin
		_stall_timer = 0.0
	else:
		_stall_timer += delta

	var fwd := -vehicle.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD

	var scan_reach := maxf(28.0, absf(vehicle.speed) * 0.5 + 14.0)
	var corridor := _scan_drive_corridor(space, origin, fwd, scan_reach, exclude, 1 | 4 | 8)
	var bumper_dist := float(corridor["bumper_dist"])
	var left_open := float(corridor["left_open"])
	var right_open := float(corridor["right_open"])
	var side_min := float(corridor["side_min"])

	if _handle_autodrive_recovery(space, origin, fwd, vehicle, bumper_dist, left_open, right_open, exclude, delta):
		return
	if vehicle.speed < -0.6:
		# Stop lingering reverse momentum before steering forward.
		vehicle.a11y_handbrake = true
		vehicle.a11y_drive_override = Vector2.ZERO
		return

	var to_wp := Vector3(current_waypoint.x - origin.x, 0.0, current_waypoint.z - origin.z)
	var desired_dir := to_wp.normalized() if to_wp.length_squared() > 0.01 else fwd
	# Vehicle rotate_y(-steer * turn * sign(speed) * dt): positive signed angle = left = negative steer
	var angle := fwd.signed_angle_to(desired_dir, Vector3.UP)
	var steer := -clampf(angle / 0.42, -1.0, 1.0)
	if bumper_dist <= AUTODRIVE_WALL_SLOW_DIST:
		if _avoid_hold_timer <= 0.0 or _avoid_side == 0.0:
			_avoid_side = -1.0 if left_open >= right_open else 1.0
			_avoid_hold_timer = 1.0
		var urgency := clampf(1.0 - (bumper_dist - AUTODRIVE_EMERGENCY_DIST) / (AUTODRIVE_WALL_SLOW_DIST - AUTODRIVE_EMERGENCY_DIST), 0.25, 1.0)
		steer = clampf(lerpf(steer, _avoid_side, urgency * 0.92), -1.0, 1.0)

	var desired_speed := _autodrive_target_speed(vehicle, bumper_dist, side_min, angle, _upcoming_turn_angle(origin, fwd), dist_total)
	var use_handbrake := bumper_dist <= AUTODRIVE_EMERGENCY_DIST or vehicle.speed > desired_speed + 3.0
	var throttle := 0.0
	if not use_handbrake and vehicle.speed <= desired_speed + 0.6:
		throttle = 1.0 if desired_speed >= vehicle.max_speed - 0.5 else clampf((desired_speed - vehicle.speed) / 14.0, 0.22, 1.0)

	vehicle.a11y_handbrake = use_handbrake
	vehicle.a11y_drive_override = Vector2(clampf(steer, -1.0, 1.0), clampf(throttle, -1.0, 1.0))


func _tick_obstacles(player: Player, camera: CameraRig, audio: A11ySpatialAudio, delta: float) -> void:
	_obstacle_timer = maxf(_obstacle_timer - delta, 0.0)
	_cover_hint_cooldown = maxf(_cover_hint_cooldown - delta, 0.0)
	if _obstacle_timer > 0.0:
		return
	_obstacle_timer = 0.32
	var moving := Vector2(player.velocity.x, player.velocity.z).length() > 0.5
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state if player.is_inside_tree() else null
	if space == null:
		return
	if moving and audio:
		var fwd := A11yRadar.forward_from_yaw(camera.yaw)
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		var chest := player.global_position + Vector3.UP * 1.0
		var rays := [
			[0, fwd, 1.7],
			[-1, (fwd - right * 0.55).normalized(), 1.3],
			[1, (fwd + right * 0.55).normalized(), 1.3],
		]
		for spec in rays:
			var q := PhysicsRayQueryParameters3D.create(chest, chest + spec[1] * float(spec[2]), 1, [player.get_rid()])
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				audio.play_obstacle_tick(int(spec[0]))
				break
	if not player.in_cover and _cover_hint_cooldown <= 0.0:
		var cover := CoverController.detect(player)
		if not cover.is_empty():
			_cover_hint_cooldown = 6.0
			var speech := A11yUIHelper.speech()
			if speech and speech.settings.combat_verbosity >= A11ySettings.Verbosity.DETAILED:
				A11yUIHelper.say("Cover nearby, press C", false, 0, &"a11y_cover")


func _manual_move_pressed(player: Player = null) -> bool:
	if Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right") or Input.is_action_pressed("move_forward") or Input.is_action_pressed("move_back") or Input.is_action_pressed("jump"):
		return true
	if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_DOWN):
		return true
	if player and player.is_inside_tree():
		if _touch_ref == null or not is_instance_valid(_touch_ref):
			_touch_ref = player.get_tree().get_first_node_in_group("touch") as TouchControls
		if _touch_ref and _touch_ref.move.length_squared() > 0.01:
			return true
	return false


func _manual_drive_pressed(player: Player = null) -> bool:
	if _manual_move_pressed(player):
		return true
	if _touch_ref and is_instance_valid(_touch_ref) and (_touch_ref.gas or _touch_ref.brake or _touch_ref.handbrake):
		return true
	return false
