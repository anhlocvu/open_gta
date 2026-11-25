class_name A11yNavigation
extends RefCounted
## Keyboard camera turning, 3D audio beacons, obstacle/cover proximity, and safe Auto-Walk.

var beacon_active := false
var autowalk_active := false
var target_label := "Objective"
var target_position := Vector3.ZERO
var current_waypoint := Vector3.ZERO
var _beacon_timer := 0.0
var _obstacle_timer := 0.0
var _cover_hint_cooldown := 0.0
var _autowalk_best_dist := INF
var _autowalk_stall_timer := 0.0
var _last_turn_hint := ""
var _route_timer := 0.0
var _cached_waypoint := Vector3.ZERO
var _cached_dest := Vector3.ZERO
var _touch_ref: TouchControls


func reset(player: Player = null) -> void:
	autowalk_active = false
	beacon_active = false
	target_position = Vector3.ZERO
	current_waypoint = Vector3.ZERO
	_autowalk_best_dist = INF
	_autowalk_stall_timer = 0.0
	_last_turn_hint = ""
	_route_timer = 0.0
	_cached_waypoint = Vector3.ZERO
	_cached_dest = Vector3.ZERO
	if player and is_instance_valid(player):
		player.a11y_move_override = Vector2.ZERO


func stop_autowalk(player: Player, reason := "") -> void:
	var was_active := autowalk_active
	autowalk_active = false
	_autowalk_best_dist = INF
	_autowalk_stall_timer = 0.0
	if player and is_instance_valid(player):
		player.a11y_move_override = Vector2.ZERO
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


func start_autowalk() -> void:
	autowalk_active = true
	_autowalk_best_dist = INF
	_autowalk_stall_timer = 0.0
	_last_turn_hint = ""


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


func compute_route_waypoint(game: Node, origin: Vector3, destination: Vector3) -> Dictionary:
	var roads: RoadGraph = game.get("roads") as RoadGraph if game else null
	if roads == null or roads.nodes.is_empty() or origin.distance_to(destination) <= 22.0:
		return {"waypoint": destination, "path": PackedVector3Array([destination]), "uses_astar": false}
	var player := game.get("player") as Player
	if player and player.is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 1.0, destination + Vector3.UP * 1.0, 1, [player.get_rid()])
		if player.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			return {"waypoint": destination, "path": PackedVector3Array([destination]), "uses_astar": false}
	var start_i := roads.nearest(origin)
	var goal_i := roads.nearest(destination)
	if start_i == goal_i:
		return {"waypoint": destination, "path": PackedVector3Array([destination]), "uses_astar": false}
	var queue: Array[int] = [start_i]
	var parent_map := {start_i: -1}
	var head := 0
	var found := false
	while head < queue.size():
		var cur := queue[head]
		head += 1
		if cur == goal_i:
			found = true
			break
		var nbs: Array = roads.links[cur]
		nbs = nbs.duplicate()
		nbs.sort_custom(func(a: int, b: int) -> bool: return roads.nodes[a].distance_squared_to(destination) < roads.nodes[b].distance_squared_to(destination))
		for nb in nbs:
			var nbi := int(nb)
			if not parent_map.has(nbi):
				parent_map[nbi] = cur
				queue.append(nbi)
	if not found:
		return {"waypoint": destination, "path": PackedVector3Array([destination]), "uses_astar": false}
	var rev: Array[int] = []
	var step := goal_i
	while step != -1:
		rev.append(step)
		step = int(parent_map.get(step, -1))
	rev.reverse()
	var pts := PackedVector3Array()
	for idx in rev:
		pts.append(roads.nodes[idx])
	pts.append(destination)
	var wp := pts[0]
	if pts.size() >= 2 and origin.distance_to(wp) < 8.0:
		wp = pts[1]
	return {"waypoint": wp, "path": pts, "uses_astar": true}


func tick(game: Node, player: Player, camera: CameraRig, audio: A11ySpatialAudio, settings: A11ySettings, delta: float) -> void:
	if player == null or not is_instance_valid(player) or camera == null or settings == null:
		return
	if player.locked or player.health <= 0.0:
		if autowalk_active:
			stop_autowalk(player)
		return
	if autowalk_active and _manual_move_pressed(player):
		stop_autowalk(player, "Auto-walk cancelled.")
	if autowalk_active:
		if player.in_vehicle or target_position == Vector3.ZERO:
			stop_autowalk(player, "Auto-walk stopped.")
		else:
			_tick_autowalk(game, player, camera, delta)
	if (beacon_active or autowalk_active) and settings.beacon_enabled and target_position != Vector3.ZERO:
		_beacon_timer -= delta
		if _beacon_timer <= 0.0:
			var dist := player.global_position.distance_to(target_position)
			_beacon_timer = clampf(dist / 26.0, 0.35, 1.25)
			var route_info := compute_route_waypoint(game, player.global_position, target_position)
			current_waypoint = route_info.waypoint
			if audio:
				audio.play_beacon_ping(current_waypoint + Vector3.UP * 1.2, dist < 10.0)
	if settings.obstacle_cues_enabled and not player.in_vehicle:
		_tick_obstacles(player, camera, audio, delta)


func _tick_autowalk(game: Node, player: Player, camera: CameraRig, delta: float) -> void:
	if player.in_cover:
		player.exit_cover()
	var dist_total := Vector2(target_position.x - player.global_position.x, target_position.z - player.global_position.z).length()
	if dist_total <= 2.2:
		stop_autowalk(player, "Arrived at %s." % target_label)
		return
	_route_timer = maxf(_route_timer - delta, 0.0)
	var dist_wp := Vector2(_cached_waypoint.x - player.global_position.x, _cached_waypoint.z - player.global_position.z).length()
	if _route_timer <= 0.0 or _cached_waypoint == Vector3.ZERO or dist_wp < 1.8 or _cached_dest.distance_to(target_position) > 2.5:
		var route_info := compute_route_waypoint(game, player.global_position, target_position)
		_cached_waypoint = route_info.waypoint
		_cached_dest = target_position
		_route_timer = 0.4
	current_waypoint = _cached_waypoint
	var desired_yaw := A11yRadar.yaw_toward(player.global_position, current_waypoint)
	camera.yaw = lerp_angle(camera.yaw, desired_yaw, 1.0 - exp(-7.5 * delta))
	player.a11y_move_override = Vector2(0.0, -1.0)
	if dist_total < _autowalk_best_dist - 0.35:
		_autowalk_best_dist = dist_total
		_autowalk_stall_timer = 0.0
	else:
		_autowalk_stall_timer += delta
		if _autowalk_stall_timer > 2.6:
			stop_autowalk(player, "Path blocked. Auto-walk stopped.")
	var turn_hint := A11yRadar.relative_bearing_text(player.global_position, camera.yaw, current_waypoint)
	if turn_hint != _last_turn_hint and turn_hint in ["to your left", "to your right", "behind left", "behind right"]:
		_last_turn_hint = turn_hint
		A11yUIHelper.say("Turning " + turn_hint, false, 1, &"a11y_turn_hint")


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
