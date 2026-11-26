class_name A11yNavigation
extends RefCounted
## Keyboard camera turning, 3D audio beacons, obstacle/cover proximity, and entrance-aware Auto-Walk / Auto-Drive.

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
var _route_mode := ""
var _force_reroute := false
var _cached_waypoint := Vector3.ZERO
var _cached_dest := Vector3.ZERO
var _effective_dest := Vector3.ZERO
var _rerouted_outside := false
var _path_points := PackedVector3Array()
var _path_node_ids := PackedInt32Array()
var _path_idx := 0
var _blocked_edges: Dictionary = {}

var _progress_anchor := Vector3.ZERO
var _stall_timer := 0.0
var _best_wp_dist := INF
var _no_progress_timer := 0.0
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
	_route_mode = ""
	_force_reroute = false
	_cached_waypoint = Vector3.ZERO
	_cached_dest = Vector3.ZERO
	_effective_dest = Vector3.ZERO
	_rerouted_outside = false
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
	_best_wp_dist = INF
	_no_progress_timer = 0.0
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
	_route_mode = ""
	_force_reroute = true
	_cached_waypoint = Vector3.ZERO
	_cached_dest = Vector3.ZERO
	_effective_dest = Vector3.ZERO
	_rerouted_outside = false
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
	return RoadGraph.corridor_clear(space, origin, destination, half_width, exclude_rids, mask, 0.9)


func _resolve_destination(game: Node, destination: Vector3, mode: String) -> Dictionary:
	if mode != "drive" or game == null:
		return {"position": destination, "rerouted_outside": false}
	var city = game.get("city")
	if city != null and city.has_method("resolve_drive_target"):
		return city.resolve_drive_target(destination, target_label)
	return {"position": destination, "rerouted_outside": false}


func compute_route_waypoint(game: Node, origin: Vector3, destination: Vector3, corridor_half_w := 0.42, _mask := 1, extra_exclude: Array[RID] = [], mode := "walk") -> Dictionary:
	var roads: RoadGraph = game.get("roads") as RoadGraph if game else null
	var player := game.get("player") as Player if game else null
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state if (player and player.is_inside_tree()) else null
	var exclude: Array[RID] = []
	if player and player.is_inside_tree():
		exclude.append(player.get_rid())
	for rid in extra_exclude:
		exclude.append(rid)

	var resolved := _resolve_destination(game, destination, mode)
	var eff_dest: Vector3 = resolved.get("position", destination)
	var rerouted_out := bool(resolved.get("rerouted_outside", false))

	var flat_dist := Vector2(eff_dest.x - origin.x, eff_dest.z - origin.z).length()
	if roads == null or roads.nodes.is_empty():
		return {"waypoint": eff_dest, "path": PackedVector3Array([eff_dest]), "node_ids": PackedInt32Array(), "start_idx": 0, "uses_astar": false, "effective_dest": eff_dest, "rerouted_outside": rerouted_out}

	var start_zone := roads.find_containing_zone(origin, true)
	var goal_zone := roads.find_containing_zone(eff_dest, true)
	var same_zone := start_zone.is_empty() and goal_zone.is_empty()
	if not start_zone.is_empty() and str(start_zone.get("id", "")) == str(goal_zone.get("id", "")):
		same_zone = true
	if same_zone and flat_dist <= 45.0 and _corridor_clear(space, origin, eff_dest, corridor_half_w, exclude, 1):
		return {"waypoint": eff_dest, "path": PackedVector3Array([eff_dest]), "node_ids": PackedInt32Array(), "start_idx": 0, "uses_astar": false, "effective_dest": eff_dest, "rerouted_outside": rerouted_out}

	var res := roads.astar_path(origin, eff_dest, _blocked_edges, space, exclude, mode, corridor_half_w)
	var pts: PackedVector3Array = res.points
	var nids: PackedInt32Array = res.node_ids
	if pts.is_empty():
		return {"waypoint": eff_dest, "path": PackedVector3Array([eff_dest]), "node_ids": PackedInt32Array(), "start_idx": 0, "uses_astar": false, "effective_dest": eff_dest, "rerouted_outside": rerouted_out}

	var start_idx := 0
	var close_skip := 7.5 if mode == "drive" else 2.8
	if pts.size() >= 2 and Vector2(pts[0].x - origin.x, pts[0].z - origin.z).length() < close_skip and _corridor_clear(space, origin, pts[1], corridor_half_w, exclude, 1):
		start_idx = 1
	elif pts.size() >= 2 and _corridor_clear(space, origin, pts[1], corridor_half_w, exclude, 1):
		var to_first := Vector2(pts[0].x - origin.x, pts[0].z - origin.z)
		var to_second := Vector2(pts[1].x - origin.x, pts[1].z - origin.z)
		if to_first.length() < 26.0 and to_first.dot(to_second) < 0.0:
			start_idx = 1
	return {"waypoint": pts[start_idx], "path": pts, "node_ids": nids, "start_idx": start_idx, "uses_astar": true, "effective_dest": eff_dest, "rerouted_outside": rerouted_out}


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
				var b_mode := "walk"
				if active_veh and is_instance_valid(active_veh) and player.in_vehicle:
					beacon_excl.append(active_veh.get_rid())
					b_mode = "drive"
				var route_info := compute_route_waypoint(game, origin, target_position, 0.45, 1, beacon_excl, b_mode)
				current_waypoint = route_info.waypoint
			if audio:
				audio.play_beacon_ping(current_waypoint + Vector3.UP * 1.2, dist < 10.0)
	if settings.obstacle_cues_enabled and not player.in_vehicle:
		_tick_obstacles(player, camera, audio, delta)


func _dist_to_active_segment(origin: Vector3) -> float:
	if _path_points.is_empty() or _path_idx < 0 or _path_idx >= _path_points.size():
		return INF
	var p_cur := Vector2(_path_points[_path_idx].x, _path_points[_path_idx].z)
	var o2 := Vector2(origin.x, origin.z)
	if _path_idx == 0:
		return o2.distance_to(p_cur)
	var p_prev := Vector2(_path_points[_path_idx - 1].x, _path_points[_path_idx - 1].z)
	var seg := p_cur - p_prev
	var seg_len_sq := seg.length_squared()
	if seg_len_sq < 0.01:
		return o2.distance_to(p_cur)
	var t := clampf((o2 - p_prev).dot(seg) / seg_len_sq, 0.0, 1.0)
	var closest := p_prev + seg * t
	return o2.distance_to(closest)


func _refresh_route(game: Node, origin: Vector3, space: PhysicsDirectSpaceState3D, corridor_w: float, exclude: Array[RID], delta: float) -> void:
	_route_timer = maxf(_route_timer - delta, 0.0)
	var dest_moved := _cached_dest.distance_to(target_position) > 3.0
	var mode_changed := _route_mode != autopilot_mode

	# Monotonic forward waypoint progression along the current path
	if not _force_reroute and not dest_moved and not mode_changed and _path_points.size() > 0:
		var advance_dist := 6.5 if autopilot_mode == "drive" else 2.2
		while _path_idx < _path_points.size() - 1:
			var wp := _path_points[_path_idx]
			var nxt := _path_points[_path_idx + 1]
			var dist_wp := Vector2(wp.x - origin.x, wp.z - origin.z).length()
			var advance := dist_wp < advance_dist
			if not advance:
				var seg := Vector2(nxt.x - wp.x, nxt.z - wp.z)
				if seg.length_squared() > 1.0:
					var proj := Vector2(origin.x - wp.x, origin.z - wp.z).dot(seg.normalized())
					var d_origin_nxt := Vector2(origin.x - nxt.x, origin.z - nxt.z).length()
					var d_wp_nxt := seg.length()
					if proj > 0.5 and d_origin_nxt < d_wp_nxt and _corridor_clear(space, origin, nxt, corridor_w, exclude, 1):
						advance = true
			if advance:
				_path_idx += 1
				_cached_waypoint = _path_points[_path_idx]
				current_waypoint = _cached_waypoint
				_best_wp_dist = INF
				_no_progress_timer = 0.0
			else:
				break

	var off_route_limit := 24.0 if autopilot_mode == "drive" else 14.0
	var off_route := _path_points.is_empty() or _dist_to_active_segment(origin) > off_route_limit
	var need_recompute := _force_reroute or _cached_waypoint == Vector3.ZERO or dest_moved or mode_changed or (_route_timer <= 0.0 and off_route)
	if need_recompute:
		var info := compute_route_waypoint(game, origin, target_position, corridor_w, 1, exclude, autopilot_mode)
		_path_points = info.path
		_path_node_ids = info.get("node_ids", PackedInt32Array())
		_path_idx = int(info.get("start_idx", 0))
		_cached_waypoint = info.waypoint
		_cached_dest = target_position
		_effective_dest = info.get("effective_dest", target_position)
		_rerouted_outside = bool(info.get("rerouted_outside", false))
		_route_mode = autopilot_mode
		_force_reroute = false
		_route_timer = 1.0
		_best_wp_dist = INF
		_no_progress_timer = 0.0
	current_waypoint = _cached_waypoint


func _penalize_current_edge() -> void:
	if _path_node_ids.size() >= 2:
		var node_idx := clampi(_path_idx, 0, _path_node_ids.size() - 1)
		if node_idx > 0:
			var key := RoadGraph.edge_key(_path_node_ids[node_idx - 1], _path_node_ids[node_idx])
			_blocked_edges[key] = int(_blocked_edges.get(key, 0)) + 1
		else:
			var key0 := RoadGraph.edge_key(_path_node_ids[0], _path_node_ids[1])
			_blocked_edges[key0] = int(_blocked_edges.get(key0, 0)) + 1
	_force_reroute = true
	_route_timer = 0.0
	_cached_waypoint = Vector3.ZERO


func _update_progress_tracker(origin: Vector3, wp: Vector3, delta: float, step_thresh: float, wp_improve: float) -> void:
	if _progress_anchor == Vector3.ZERO or Vector2(origin.x - _progress_anchor.x, origin.z - _progress_anchor.z).length() > step_thresh:
		_progress_anchor = origin
		_stall_timer = 0.0
	else:
		_stall_timer += delta
	var d_wp := Vector2(wp.x - origin.x, wp.z - origin.z).length()
	if _best_wp_dist == INF or d_wp < _best_wp_dist - wp_improve:
		_best_wp_dist = d_wp
		_no_progress_timer = 0.0
	else:
		_no_progress_timer += delta


func _scan_walk_fan(space: PhysicsDirectSpaceState3D, origin: Vector3, desired_dir: Vector3, reach: float, exclude: Array[RID], mask: int) -> Dictionary:
	var out := {"steer_dir": desired_dir, "blocked_center": false, "center_dist": reach, "left_score": reach, "right_score": reach}
	if space == null:
		return out
	var chest := origin + Vector3.UP * 0.9
	var right := Vector3(-desired_dir.z, 0.0, desired_dir.x)
	var center_min := reach
	for off in [-0.40, 0.0, 0.40]:
		var start := chest + right * float(off)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(start, start + desired_dir * reach, mask, exclude))
		if not hit.is_empty():
			center_min = minf(center_min, origin.distance_to(hit.position))
	out["center_dist"] = center_min
	out["blocked_center"] = center_min < 2.4

	var angles := [0.0, 22.0, -22.0, 48.0, -48.0, 78.0, -78.0]
	var left_sum := 0.0
	var right_sum := 0.0
	var best_dir := desired_dir
	var best_score := -INF
	for deg in angles:
		var rad := deg_to_rad(deg)
		var dir := (Basis(Vector3.UP, rad) * desired_dir).normalized()
		var d_clear := reach
		if absf(deg) < 1.0:
			d_clear = center_min
		else:
			var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(chest, chest + dir * reach, mask, exclude))
			if not h.is_empty():
				d_clear = origin.distance_to(h.position)
		if deg > 0.0:
			left_sum += d_clear
		elif deg < 0.0:
			right_sum += d_clear
		var side_sign := 0.0 if absf(deg) < 1.0 else (-1.0 if deg > 0.0 else 1.0)
		var consistency := 0.7 if (_avoid_hold_timer > 0.0 and _avoid_side != 0.0 and side_sign == _avoid_side) else 0.0
		var score := minf(d_clear, reach) - absf(deg) * 0.028 + consistency
		if d_clear < 1.45:
			score -= 3.5
		if score > best_score:
			best_score = score
			best_dir = dir
	out["left_score"] = left_sum / 3.0
	out["right_score"] = right_sum / 3.0
	out["steer_dir"] = best_dir
	return out


func _tick_autowalk(game: Node, player: Player, camera: CameraRig, delta: float) -> void:
	if player.in_cover:
		player.exit_cover()
	var origin := player.global_position
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state if player.is_inside_tree() else null
	var exclude: Array[RID] = [player.get_rid()]
	var dist_total := Vector2(target_position.x - origin.x, target_position.z - origin.z).length()
	if dist_total <= 2.2 and _corridor_clear(space, origin, target_position, 0.0, exclude, 1):
		stop_autowalk(player, "Arrived at %s." % target_label)
		return
	_refresh_route(game, origin, space, 0.42, exclude, delta)
	_update_progress_tracker(origin, current_waypoint, delta, 0.65, 0.9)

	if _recovery_timer > 0.0:
		_recovery_timer = maxf(_recovery_timer - delta, 0.0)
		player.a11y_move_override = _recovery_move
		return

	var to_wp := Vector3(current_waypoint.x - origin.x, 0.0, current_waypoint.z - origin.z)
	var desired_dir := to_wp.normalized() if to_wp.length_squared() > 0.01 else A11yRadar.forward_from_yaw(camera.yaw)
	var fan := _scan_walk_fan(space, origin, desired_dir, 3.8, exclude, 1 | 4 | 8)
	var steer_dir: Vector3 = fan["steer_dir"]
	var blocked_center := bool(fan["blocked_center"])
	var center_dist := float(fan["center_dist"])

	if blocked_center:
		var rel := desired_dir.signed_angle_to(steer_dir, Vector3.UP)
		if absf(rel) > 0.15:
			_avoid_side = -1.0 if rel > 0.0 else 1.0
			_avoid_hold_timer = 0.85

	if _stall_timer > 1.1 or _no_progress_timer > 4.2:
		_stall_timer = 0.0
		_no_progress_timer = 0.0
		_best_wp_dist = INF
		if player.tactical and player.try_mantle():
			return
		var side := -1.0 if float(fan["left_score"]) >= float(fan["right_score"]) else 1.0
		_avoid_side = side
		_avoid_hold_timer = 1.2
		_recovery_timer = 0.65
		_recovery_move = Vector2(side * 0.9, 0.35 if center_dist < 1.2 else -0.45).normalized()
		if _reroute_penalty_cd <= 0.0:
			_reroute_penalty_cd = 1.2
			_penalize_current_edge()
		if _reroute_speech_cd <= 0.0:
			_reroute_speech_cd = 5.0
			A11yUIHelper.say("Rerouting around obstacle.", false, 1, &"a11y_turn_hint")
		player.a11y_move_override = _recovery_move
		return

	var desired_yaw := atan2(-steer_dir.x, -steer_dir.z)
	var turn_rate := 16.0 if blocked_center else 12.0
	camera.yaw = lerp_angle(camera.yaw, desired_yaw, 1.0 - exp(-turn_rate * delta))

	var heading_err := absf(angle_difference(camera.yaw, desired_yaw))
	var stride := -1.0
	if heading_err > deg_to_rad(95.0):
		stride = -0.25
	elif heading_err > deg_to_rad(45.0):
		stride = -0.55
	player.a11y_move_override = Vector2(0.0, stride)

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

	var looping := _no_progress_timer > 5.5
	if (bumper_dist <= AUTODRIVE_EMERGENCY_DIST and vehicle.speed <= 4.0) or _stall_timer > 1.1 or looping:
		_stall_timer = 0.0
		_no_progress_timer = 0.0
		_best_wp_dist = INF
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
	var resolved := _resolve_destination(game, target_position, "drive")
	var drive_dest: Vector3 = resolved.get("position", target_position)
	var rerouted_out := bool(resolved.get("rerouted_outside", false))
	var dist_total := Vector2(drive_dest.x - origin.x, drive_dest.z - origin.z).length()
	var arrive_radius := 4.4 if (target_label in ["Pay and Spray", "Drop Warehouse"]) else (6.5 if rerouted_out else 7.5)
	if dist_total <= arrive_radius:
		vehicle.a11y_handbrake = true
		var msg := ("Arrived outside %s." % target_label) if rerouted_out else ("Arrived at %s." % target_label)
		stop_autowalk(_player, msg, vehicle, true)
		return

	var space: PhysicsDirectSpaceState3D = vehicle.get_world_3d().direct_space_state if vehicle.is_inside_tree() else null
	var exclude: Array[RID] = [vehicle.get_rid()]
	_refresh_route(game, origin, space, 1.05, exclude, delta)
	_update_progress_tracker(origin, current_waypoint, delta, 1.1, 2.2)

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
	var obstacle_before_pad := bumper_dist + AUTODRIVE_BUMPER_OFFSET <= maxf(dist_total - arrive_radius * 0.5, 0.5)
	if bumper_dist <= AUTODRIVE_WALL_SLOW_DIST and obstacle_before_pad:
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
