class_name A11yGameplayController
extends Node
## Coordinates Open World NVDA callouts, 3D world audio, radar, waypoint navigation, sonar, and LOS aim assist.

var game: Node3D
var audio: A11ySpatialAudio
var radar := A11yRadar.new()
var nav := A11yNavigation.new()
var aim_assist := A11yAimAssist.new()

var _prev_reload := false
var _prev_weapon := -1
var _prev_grounded := true
var _prev_sliding := false
var _prev_plating := false
var _empty_click_cd := 0.0
var _last_wanted := 0
var _last_district := ""
var _nav_refresh_cd := 0.0
var _fallback_settings := A11ySettings.new()


func _ready() -> void:
	audio = A11ySpatialAudio.new()
	add_child(audio)


func reset_state() -> void:
	nav.reset(game.get("player") as Player if game else null)
	_prev_reload = false
	_prev_weapon = -1
	_prev_grounded = true
	_prev_sliding = false
	_prev_plating = false
	_last_wanted = 0
	_last_district = ""


func sync_wanted(stars: int) -> void:
	_last_wanted = stars


func on_weapon_fired(shooter_id: int, pos: Vector3, is_ally: bool) -> void:
	if audio:
		audio.play_gunshot(pos, shooter_id == 0, is_ally)


func on_empty_trigger() -> void:
	if _empty_click_cd > 0.0:
		return
	_empty_click_cd = 0.45
	if audio:
		audio.play_weapon_cue(&"empty")
	A11yUIHelper.say("Empty magazine, press R to reload.", true, 2, &"a11y_ammo")


func on_hit_confirmed(armored: bool, broken: bool, headshot := false) -> void:
	if audio:
		audio.play_hit_confirm(armored, broken, headshot)
	if broken:
		A11yUIHelper.say("Armor broken!", true, 2, &"a11y_combat")


func handle_input(event: InputEvent) -> bool:
	var speech := _speech()
	var settings: A11ySettings = speech.settings if speech else _fallback_settings
	if A11yUIHelper.action_pressed(event, &"a11y_history_prev"):
		if speech: speech.review_previous()
		return true
	if A11yUIHelper.action_pressed(event, &"a11y_history_next"):
		if speech: speech.review_next()
		return true
	if A11yUIHelper.action_pressed(event, &"a11y_repeat_last"):
		if speech: speech.repeat_last()
		return true
	if A11yUIHelper.action_pressed(event, &"a11y_help"):
		_speak_context_help()
		return true

	if game == null:
		return false
	var player := game.get("player") as Player
	var camera := game.get("camera") as CameraRig
	if player == null or camera == null or player.locked:
		return false
	if not _is_gameplay_active():
		return false

	if nav.handle_turn_press(event, camera, settings):
		return true
	if A11yUIHelper.action_pressed(event, &"a11y_compass"):
		_speak_compass(player, camera)
		return true
	if A11yUIHelper.action_pressed(event, &"a11y_status"):
		_speak_status(player)
		return true
	if A11yUIHelper.action_pressed(event, &"a11y_objective"):
		_speak_objective(player, camera)
		return true
	if A11yUIHelper.action_pressed(event, &"a11y_radar_cycle_prev", true):
		radar.cycle_category(-1)
		A11yUIHelper.say("Radar filter: %s" % radar.category_label(), true, 2, &"a11y_radar", true)
		return true
	if A11yUIHelper.action_pressed(event, &"a11y_radar_cycle", true):
		radar.cycle_category(1)
		A11yUIHelper.say("Radar filter: %s" % radar.category_label(), true, 2, &"a11y_radar", true)
		return true
	if A11yUIHelper.action_pressed(event, &"a11y_radar_prev"):
		_step_radar(player, camera, -1)
		return true
	if A11yUIHelper.action_pressed(event, &"a11y_radar_next"):
		_step_radar(player, camera, 1)
		return true
	if A11yUIHelper.action_pressed(event, &"a11y_sonar_sweep"):
		_trigger_sonar_sweep(player, camera)
		return true
	if A11yUIHelper.action_pressed(event, &"a11y_beacon_toggle"):
		_toggle_beacon(player, camera)
		return true
	if A11yUIHelper.action_pressed(event, &"a11y_autowalk"):
		_toggle_autowalk(player)
		return true
	if A11yUIHelper.action_pressed(event, &"a11y_snap_enemy", true):
		var snap_res := aim_assist.snap_to_visible_enemy(game, player, camera, settings)
		if snap_res.get("locked", false):
			A11yUIHelper.say("Aimed at %s, %d meters" % [snap_res.label, snap_res.distance], true, 3, &"a11y_aim", true)
		elif str(snap_res.get("reason", "")) != "":
			A11yUIHelper.say(str(snap_res.reason), true, 2, &"a11y_aim", true)
		return true
	if A11yUIHelper.action_pressed(event, &"a11y_aim_assist", true):
		var face_res := aim_assist.face_radar_target(game, player, camera, radar)
		if face_res.get("locked", false):
			var los_txt := "clear" if bool(face_res.get("clear", true)) else "behind cover"
			var msg := "Facing %s, %d meters, %s" % [face_res.label, face_res.distance, los_txt]
			var hp_pct := float(face_res.get("hp", -1.0))
			if hp_pct >= 0.0:
				msg += ", %d percent durability" % int(round(hp_pct))
			A11yUIHelper.say(msg, true, 3, &"a11y_aim", true)
		elif str(face_res.get("reason", "")) != "":
			A11yUIHelper.say(str(face_res.reason), true, 2, &"a11y_aim", true)
		return true
	return false


func _process(delta: float) -> void:
	_empty_click_cd = maxf(_empty_click_cd - delta, 0.0)
	_nav_refresh_cd = maxf(_nav_refresh_cd - delta, 0.0)
	if game == null:
		return
	var player := game.get("player") as Player
	var camera := game.get("camera") as CameraRig
	var speech := _speech()
	var settings: A11ySettings = speech.settings if speech else _fallback_settings
	if not _is_gameplay_active() or player == null or camera == null:
		if nav.autowalk_active:
			nav.stop_autowalk(player)
		if audio:
			audio.stop_world_loops()
		return
	nav.process_camera_turn(camera, settings, delta, player.locked)
	if (nav.beacon_active or nav.autowalk_active) and _nav_refresh_cd <= 0.0:
		_nav_refresh_cd = 0.35
		_refresh_nav_target(player)
	nav.tick(game, player, camera, audio, settings, delta)
	aim_assist.tick_crosshair(game, player, camera, audio, settings, delta)
	if audio:
		audio.tick_world_audio(game, _tracked_pos(player), delta)
	_tick_player_cues(player)
	_tick_open_world_cues(player, settings)


func announce_weapon_switch(player: Player, requested_id := -1) -> void:
	if player == null:
		return
	_prev_weapon = player.weapon
	if player.owned_weapons.is_empty():
		A11yUIHelper.say("No weapons.", true, 2, &"a11y_weapon", true)
		return
	if requested_id > Arsenal.Id.NONE and not player.owned_weapons.has(requested_id):
		A11yUIHelper.say("No %s." % Player.weapon_spoken_name(requested_id), true, 2, &"a11y_weapon", true)
		return
	if player.weapon == Arsenal.Id.NONE:
		A11yUIHelper.say("Unarmed, fists.", true, 2, &"a11y_weapon", true)
		return
	var wname := Player.weapon_spoken_name(player.weapon)
	if player.infinite_ammo:
		A11yUIHelper.say("%s, infinite ammo." % wname, true, 2, &"a11y_weapon", true)
	else:
		A11yUIHelper.say("%s, %d in mag, %d reserve." % [wname, int(player.magazines.get(player.weapon, 0)), int(player.ammo.get(player.weapon, 0))], true, 2, &"a11y_weapon", true)


func _tick_player_cues(player: Player) -> void:
	if player.weapon != _prev_weapon:
		if _prev_weapon != -1:
			if player.weapon == Arsenal.Id.NONE:
				A11yUIHelper.say("Unarmed, fists.", true, 2, &"a11y_weapon", true)
			elif player.infinite_ammo:
				A11yUIHelper.say("%s, infinite ammo." % Player.weapon_spoken_name(player.weapon), true, 2, &"a11y_weapon", true)
			else:
				A11yUIHelper.say("%s, %d in mag, %d reserve." % [Player.weapon_spoken_name(player.weapon), int(player.magazines.get(player.weapon, 0)), int(player.ammo.get(player.weapon, 0))], true, 2, &"a11y_weapon", true)
		_prev_weapon = player.weapon
	var reloading := player.reload_remaining > 0.0
	if reloading and not _prev_reload:
		if audio: audio.play_weapon_cue(&"reload_start")
		A11yUIHelper.say("Reloading", false, 1, &"a11y_reload")
	elif not reloading and _prev_reload:
		if audio: audio.play_weapon_cue(&"reload_done")
		A11yUIHelper.say("Reloaded", false, 1, &"a11y_reload")
	_prev_reload = reloading
	var grounded := player.is_on_floor()
	var sliding := player.slide_remaining > 0.0
	var plating := player.plate_remaining > 0.0
	if not player.in_vehicle and not player.locked and audio:
		if _prev_grounded and not grounded and player.velocity.y > 1.0:
			audio.play_movement_cue(&"jump")
		elif not _prev_grounded and grounded:
			audio.play_movement_cue(&"land")
		if sliding and not _prev_sliding:
			audio.play_movement_cue(&"slide")
		if not plating and _prev_plating and player.vitality.armor > 0.0:
			audio.play_weapon_cue(&"plate_done")
	_prev_grounded = grounded
	_prev_sliding = sliding
	_prev_plating = plating


func _tick_open_world_cues(player: Player, settings: A11ySettings) -> void:
	var heat = game.get("heat")
	if heat != null:
		var stars := int(heat.get("stars"))
		if stars != _last_wanted:
			if stars > _last_wanted:
				A11yUIHelper.say("Wanted level %d stars. %s." % [stars, heat.label()], true, 3, &"a11y_wanted")
			elif stars == 0:
				A11yUIHelper.say("Heat cleared. Units lost.", true, 2, &"a11y_wanted")
			_last_wanted = stars
	if game.has_method("district_name"):
		var dname: String = game.district_name(_tracked_pos(player))
		if dname != _last_district:
			var had_prev := _last_district != ""
			_last_district = dname
			if had_prev and settings.combat_verbosity >= A11ySettings.Verbosity.STANDARD:
				A11yUIHelper.say("Entering %s" % dname, false, 0, &"a11y_zone")


func _trigger_sonar_sweep(player: Player, camera: CameraRig) -> void:
	var origin := _tracked_pos(player)
	var items := radar.collect_targets(game, origin, A11yRadar.Category.ALL)
	var fwd := A11yRadar.forward_from_yaw(camera.yaw)
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var near_items: Array[Dictionary] = []
	var counts := {"enemy": 0, "civ": 0, "pickup": 0, "veh": 0}
	for it in items:
		var pos: Vector3 = it.get("position", origin)
		var d := origin.distance_to(pos)
		if d > 85.0:
			continue
		var cat := int(it.get("category", A11yRadar.Category.ALL))
		match cat:
			A11yRadar.Category.ENEMIES: counts["enemy"] += 1
			A11yRadar.Category.CIVILIANS: counts["civ"] += 1
			A11yRadar.Category.LOOT: counts["pickup"] += 1
			_: counts["veh"] += 1
		var flat := Vector3(pos.x - origin.x, 0.0, pos.z - origin.z)
		var angle := 0.0
		if flat.length_squared() > 0.01:
			var dir := flat.normalized()
			angle = atan2(right.dot(dir), fwd.dot(dir))
		var pitch := 1.35 if cat == A11yRadar.Category.ENEMIES else (1.15 if cat == A11yRadar.Category.LOOT else 0.9)
		near_items.append({"pos": pos + Vector3.UP * 1.1, "pitch": pitch, "db": lerpf(-3.0, -13.0, clampf(d / 85.0, 0.0, 1.0)), "angle": angle})
	near_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.angle) < float(b.angle))
	if near_items.size() > 8:
		near_items.resize(8)
	if audio and not near_items.is_empty():
		audio.queue_sonar_sweep(near_items)
	var dname := str(game.district_name(origin)) if game.has_method("district_name") else "Harbor District"
	A11yUIHelper.say("Sonar sweep in %s: %d police, %d civilians, %d pickups nearby." % [dname, counts["enemy"], counts["civ"], counts["pickup"]], true, 2, &"a11y_sonar", true)


func _speak_compass(player: Player, camera: CameraRig) -> void:
	var msg := "Facing %s" % A11yRadar.compass_heading(camera.yaw)
	if player.in_vehicle:
		msg += ", in vehicle"
	elif player.in_cover:
		msg += ", in cover"
	elif player.crouched:
		msg += ", crouched"
	A11yUIHelper.say(msg, true, 2, &"a11y_compass", true)


func _speak_status(player: Player) -> void:
	var w_text := "Unarmed"
	if player.weapon != Arsenal.Id.NONE:
		w_text = "%s, %d of %d rounds" % [Arsenal.data(player.weapon).label, int(player.magazines.get(player.weapon, 0)), int(player.ammo.get(player.weapon, 0))]
	var money_val := int(game.get("money")) if game.get("money") != null else 0
	var stars := int(game.get("heat").get("stars")) if game.get("heat") != null else 0
	var dname := str(game.district_name(_tracked_pos(player))) if game.has_method("district_name") else "Harbor District"
	var msg := "%s. Health %d, Stamina %d, %s. Cash %d dollars, Wanted %d stars" % [dname, int(player.health), int(player.stamina), w_text, money_val, stars]
	if game.get("active_aircraft") != null:
		var jet: Node3D = game.active_aircraft
		msg += ". Flying %s at %d miles per hour" % [str(jet.get("display_name")), int(absf(float(jet.get("speed"))) * 2.4)]
	elif game.get("active_vehicle") != null:
		var veh: Node3D = game.active_vehicle
		msg += ". Driving %s at %d miles per hour" % [str(veh.get("display_name")), int(absf(float(veh.get("speed"))) * 2.4)]
	A11yUIHelper.say(msg, true, 3, &"a11y_status", true)


func _speak_objective(player: Player, camera: CameraRig) -> void:
	var origin := _tracked_pos(player)
	var info := _default_objective()
	var dest: Vector3 = info.position
	if dest == Vector3.ZERO:
		A11yUIHelper.say(str(info.label), true, 2, &"a11y_obj", true)
		return
	var dist := int(round(origin.distance_to(dest)))
	var dir := A11yRadar.relative_bearing_text(origin, camera.yaw, dest)
	A11yUIHelper.say("%s, %d meters, %s" % [str(info.label), dist, dir], true, 3, &"a11y_obj", true)


func _step_radar(player: Player, camera: CameraRig, step_dir: int) -> void:
	var origin := _tracked_pos(player)
	var chosen := radar.step_target(game, origin, step_dir)
	if chosen.is_empty():
		A11yUIHelper.say("No %s targets nearby." % radar.category_label(), true, 2, &"a11y_radar", true)
		return
	nav.target_label = str(chosen.label)
	nav.target_position = chosen.position
	A11yUIHelper.say(A11yRadar.format_target_callout(origin, camera.yaw, chosen), true, 2, &"a11y_radar", true)


func _toggle_beacon(player: Player, camera: CameraRig) -> void:
	nav.beacon_active = not nav.beacon_active
	if nav.beacon_active:
		nav.track_objective = radar.locked_target_id == ""
		_refresh_nav_target(player)
		var origin := _tracked_pos(player)
		if nav.target_position == Vector3.ZERO:
			nav.beacon_active = false
			nav.track_objective = false
			A11yUIHelper.say("No target available for beacon.", true, 2, &"a11y_nav", true)
			return
		var dist := int(round(origin.distance_to(nav.target_position)))
		var dir := A11yRadar.relative_bearing_text(origin, camera.yaw, nav.target_position)
		A11yUIHelper.say("Beacon on for %s, %d meters, %s." % [nav.target_label, dist, dir], true, 2, &"a11y_nav", true)
	else:
		if not nav.autowalk_active:
			nav.track_objective = false
		A11yUIHelper.say("Navigation beacon off.", true, 2, &"a11y_nav", true)


func _toggle_autowalk(player: Player) -> void:
	if nav.autowalk_active:
		var stop_msg := "Auto-drive stopped." if nav.autopilot_mode == "drive" else "Auto-walk stopped."
		nav.stop_autowalk(player, stop_msg)
		return
	var active_air := game.get("active_aircraft") as Aircraft if game else null
	if active_air != null:
		A11yUIHelper.say("Auto-pilot is not available in aircraft.", true, 2, &"a11y_nav", true)
		return
	var active_veh := game.get("active_vehicle") as Vehicle if game else null
	var drive_mode := player.in_vehicle and active_veh != null and is_instance_valid(active_veh)
	if player.in_vehicle and not drive_mode:
		A11yUIHelper.say("Auto-drive unavailable.", true, 2, &"a11y_nav", true)
		return
	if drive_mode and (active_veh.burning or active_veh.exploded):
		A11yUIHelper.say("Vehicle is burning, get out!", true, 3, &"a11y_nav", true)
		return
	nav.track_objective = radar.locked_target_id == ""
	_refresh_nav_target(player)
	if nav.target_position == Vector3.ZERO:
		nav.track_objective = false
		A11yUIHelper.say("Select a radar target or objective first.", true, 2, &"a11y_nav", true)
		return
	if drive_mode:
		nav.start_autodrive()
		A11yUIHelper.say("Auto-drive started toward %s. Press any driving key or P to stop." % nav.target_label, true, 3, &"a11y_nav", true)
	else:
		nav.start_autowalk("walk")
		A11yUIHelper.say("Auto-walk started toward %s. Press any movement key or P to stop." % nav.target_label, true, 3, &"a11y_nav", true)


func _refresh_nav_target(player: Player) -> void:
	if radar.locked_target_id != "":
		nav.track_objective = false
		var locked := radar.resolve_locked_target(game, _tracked_pos(player))
		if not locked.is_empty():
			nav.target_label = str(locked.label)
			nav.target_position = locked.position
			return
		radar.locked_target_id = ""
		if nav.autowalk_active:
			nav.stop_autowalk(player, "Tracked target lost. Auto-pilot stopped.")
		elif nav.beacon_active:
			A11yUIHelper.say("Tracked target lost. Switching beacon to objective.", false, 1, &"a11y_nav")
		nav.track_objective = true
	if not nav.track_objective and nav.target_position != Vector3.ZERO:
		return
	var info := _default_objective()
	nav.target_label = str(info.label)
	nav.target_position = info.position
	if info.position == Vector3.ZERO and nav.autowalk_active:
		nav.stop_autowalk(player, "Objective unavailable. Auto-pilot stopped.")


func _default_objective() -> Dictionary:
	if game and game.has_method("objective_info"):
		return game.objective_info()
	var dest: Vector3 = game.radar_objective() if (game and game.has_method("radar_objective")) else Vector3.ZERO
	return {"position": dest, "label": "Current Objective"}


func _tracked_pos(player: Player) -> Vector3:
	if game and game.has_method("tracked_node"):
		var t: Node3D = game.tracked_node()
		if t:
			return t.global_position
	return player.global_position


func _is_gameplay_active() -> bool:
	if game == null:
		return false
	if game.has_method("is_gameplay_active"):
		return game.is_gameplay_active()
	return false


func _speak_context_help() -> void:
	var msg := "Open world accessibility keys: W A S D move or drive. J and L turn, I and K look up and down, U levels horizon, O faces locked radar target, Shift O snaps aim to enemy. F, Semicolon, or Left click fires gun or punches when unarmed. Apostrophe or Right click aims. Minus and Equal cycle weapons, 0 holsters to fists, 1 to 3 and 5 select or buy guns, R reloads, E interacts, Enter opens Vehicle Dealership when inside showroom. Z status, X objective, H compass, G sonar sweep. B next radar filter, Shift B previous filter, Comma and Period cycle targets, M beacon, P auto-walk or auto-drive. Tab or Escape pauses."
	A11yUIHelper.say(msg, true, 3, &"a11y_help", true)


func _speech() -> Node:
	return A11yUIHelper.speech()
