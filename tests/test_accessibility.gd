extends SceneTree
## Open-World-only headless accessibility tests: keyboard parity, UI focus, Pause/Settings, Save/Load menu, radar, nav, autowalk, LOS aim assist.
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, msg: String) -> void:
	checks += 1
	if ok:
		print("PASS: " + msg)
	else:
		failures += 1
		push_error("FAIL: " + msg)

func frames(n: int) -> void:
	for _i in n:
		await physics_frame
		await process_frame

func _has_key_binding(action: StringName, phys_key: int, want_shift := false) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev.physical_keycode == phys_key or ev.keycode == phys_key) and ev.shift_pressed == want_shift:
			return true
	return false

func run() -> void:
	CombatInput.install()

	# 1. Verify no Insert / CapsLock conflicts on any game or accessibility action
	var conflict := false
	for action in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey and (ev.physical_keycode in [KEY_INSERT, KEY_CAPSLOCK] or ev.keycode in [KEY_INSERT, KEY_CAPSLOCK]):
				conflict = true
	check(not conflict, "Game and accessibility InputMap actions have zero Insert or CapsLock bindings")

	# 1b. Keyboard parity defaults for mouse actions, Shift+B, holster, sonar sweep
	check(_has_key_binding(&"fire", KEY_SEMICOLON), "fire has keyboard binding Semicolon alongside mouse")
	check(_has_key_binding(&"aim", KEY_APOSTROPHE), "aim has keyboard binding Apostrophe alongside mouse")
	check(_has_key_binding(&"cycle_weapon_up", KEY_EQUAL), "cycle_weapon_up has keyboard binding Equal alongside wheel")
	check(_has_key_binding(&"cycle_weapon_down", KEY_MINUS), "cycle_weapon_down has keyboard binding Minus alongside wheel")
	check(_has_key_binding(&"weapon_holster", KEY_0), "weapon_holster bound to 0")
	check(_has_key_binding(&"a11y_radar_cycle_prev", KEY_B, true), "a11y_radar_cycle_prev bound to Shift+B")
	check(_has_key_binding(&"a11y_sonar_sweep", KEY_G), "a11y_sonar_sweep bound to G")

	# 2. Compass & relative bearing math
	check(A11yRadar.compass_heading(0.0) == "North", "yaw 0 faces North")
	check(A11yRadar.compass_heading(-PI * 0.5) == "East", "yaw -PI/2 faces East")
	check(A11yRadar.compass_heading(PI) == "South", "yaw PI faces South")
	check(A11yRadar.compass_heading(PI * 0.5) == "West", "yaw PI/2 faces West")
	check(A11yRadar.relative_bearing_text(Vector3.ZERO, 0.0, Vector3(0, 0, -10)) == "ahead", "target at -Z when facing North is ahead")
	check(A11yRadar.relative_bearing_text(Vector3.ZERO, 0.0, Vector3(10, 0, 0)) == "to your right", "target at +X when facing North is to your right")
	check(A11yRadar.relative_bearing_text(Vector3.ZERO, 0.0, Vector3(-10, 0, 0)) == "to your left", "target at -X when facing North is to your left")
	check(A11yRadar.relative_bearing_text(Vector3.ZERO, 0.0, Vector3(0, 0, 10)) == "behind you", "target at +Z when facing North is behind you")
	check(A11yRadar.relative_bearing_text(Vector3.ZERO, 0.0, Vector3(0, 5, -10)) == "ahead, above", "elevation delta appends above")

	# 3. Open World main.tscn UI focus, Menu streamlining (no Day/Night), Pause/Save/Load, Radar, Nav, Autowalk, Aim Assist
	var ow = load("res://scenes/main.tscn").instantiate()
	root.add_child(ow)
	current_scene = ow
	await process_frame

	var ow_focusable := true
	for btn in ow.hud._menu_col.find_children("*", "Button", true, false):
		if (btn as Control).focus_mode == Control.FOCUS_NONE:
			ow_focusable = false
	check(ow_focusable, "Open World main menu buttons are all keyboard focusable")
	check(not ("_day_btn" in ow.hud) and not ("_night_btn" in ow.hud) and not ("_time_chip" in ow.hud), "Day/Night buttons removed from menu and HUD")
	check(ow.hud._save_btn != null and ow.hud._load_btn != null and ow.hud._continue_btn != null, "Menu provides Continue, Save, and Load buttons")

	ow.hud._show_settings()
	await process_frame
	var tab_ev := InputEventKey.new()
	tab_ev.physical_keycode = KEY_TAB
	tab_ev.keycode = KEY_TAB
	tab_ev.pressed = true
	ow.hud._input(tab_ev)
	check(ow.hud._settings_scroll.visible, "Tab inside Settings does not close Settings")
	var settings_focusable := true
	for ctrl in ow.hud._settings_content.find_children("*", "Control", true, false):
		if ctrl is Button or ctrl is HSlider or ctrl is OptionButton or ctrl is CheckButton:
			if (ctrl as Control).focus_mode == Control.FOCUS_NONE:
				settings_focusable = false
	check(settings_focusable, "all Open World Settings and Accessibility controls are keyboard focusable")
	check(ow.hud._settings_content.find_children("*", "CheckButton", true, false).size() >= 6, "Open World Settings includes Accessibility toggles")
	ow.hud._close_settings()
	await process_frame

	check(not ow.city.visible, "Heavy 3D city stays hidden on Title menu for 60 FPS navigation")
	ow.begin()
	await frames(3)
	var a11y: A11yGameplayController = ow.a11y
	check(a11y != null and a11y.audio != null, "A11yGameplayController and A11ySpatialAudio attached")
	check(a11y.audio._pool_3d.size() == 16 and a11y.audio._pool_3d[0].attenuation_model == AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE, "3D audio pool uses inverse distance attenuation")

	# Regression: City node count & world visibility/focus release on PLAY
	check(ow.city.get_child_count() < 2000, "City batches road dashes via MultiMeshInstance3D to stay under 2000 child nodes")
	check(ow.city.visible, "City becomes visible when gameplay begins")
	check(ow.get_viewport().gui_get_focus_owner() == null, "UI focus is cleared when gameplay begins")

	# Regression: real Input.parse_input_event across device IDs triggers NVDA speech in gameplay
	var speech_ref := root.get_node_or_null("A11ySpeech")
	var real_spoken: Array[String] = []
	var prev_cb := Callable()
	if speech_ref:
		prev_cb = func(txt: String, _intr: bool, _prio: int) -> void: real_spoken.append(txt)
		speech_ref.spoken.connect(prev_cb)
	for key_spec in [[KEY_H, 0, "Facing"], [KEY_Z, 1, "Health"], [KEY_X, 16, "Steal"], [KEY_B, 0, "Radar filter"], [KEY_PERIOD, 1, ""], [KEY_G, 16, "Sonar"], [KEY_SLASH, 16, "Open world accessibility keys"]]:
		real_spoken.clear()
		var kev := InputEventKey.new()
		kev.device = int(key_spec[1])
		kev.physical_keycode = int(key_spec[0])
		kev.keycode = int(key_spec[0])
		kev.pressed = true
		Input.parse_input_event(kev)
		await process_frame
		var kev_up := kev.duplicate()
		kev_up.pressed = false
		Input.parse_input_event(kev_up)
		await process_frame
		var got := "\n".join(real_spoken)
		var expected := str(key_spec[2])
		var ok := (got.length() > 0) if expected == "" else got.contains(expected)
		check(ok, "Input.parse_input_event key %s (device %d) triggers speech (%s)" % [OS.get_keycode_string(int(key_spec[0])), int(key_spec[1]), expected])
	if speech_ref and prev_cb.is_valid() and speech_ref.spoken.is_connected(prev_cb):
		speech_ref.spoken.disconnect(prev_cb)

	# B and Shift+B bidirectional radar cycling
	a11y.radar.selected_category = 0
	var b_next := InputEventKey.new()
	b_next.physical_keycode = KEY_B
	b_next.keycode = KEY_B
	b_next.pressed = true
	a11y.handle_input(b_next)
	check(a11y.radar.selected_category == 1, "B advances radar category from 0 to 1")
	var b_prev := InputEventKey.new()
	b_prev.physical_keycode = KEY_B
	b_prev.keycode = KEY_B
	b_prev.shift_pressed = true
	b_prev.pressed = true
	a11y.handle_input(b_prev)
	check(a11y.radar.selected_category == 0, "Shift+B steps radar category back from 1 to 0")
	a11y.handle_input(b_prev)
	check(a11y.radar.selected_category == A11yRadar.CATEGORY_NAMES.size() - 1, "Shift+B wraps backward from 0 to last category")

	# Radar finds Enemies/Police and Civilians from player spawn
	var ow_enemies := a11y.radar.collect_targets(ow, ow.player.global_position, A11yRadar.Category.ENEMIES)
	check(ow_enemies.size() > 0, "Enemies and Police filter returns nearest police units even from spawn")
	var ow_civs := a11y.radar.collect_targets(ow, ow.player.global_position, A11yRadar.Category.CIVILIANS)
	check(ow_civs.size() > 0, "Civilians filter enumerates nearby pedestrians matching O Snap Aim")

	# GTA-style combat: unarmed fire triggers punch; cycling weapons includes Unarmed (NONE) & speaks via NVDA
	ow.player.owned_weapons.clear()
	ow.player.select_weapon(Arsenal.Id.NONE)
	var w_spoken: Array[String] = []
	var w_cb := Callable()
	if speech_ref:
		w_cb = func(txt: String, _intr: bool, _prio: int) -> void: w_spoken.append(txt)
		speech_ref.spoken.connect(w_cb)
	w_spoken.clear()
	var cycle_up_ev := InputEventKey.new()
	cycle_up_ev.physical_keycode = KEY_EQUAL
	cycle_up_ev.keycode = KEY_EQUAL
	cycle_up_ev.pressed = true
	ow._unhandled_input(cycle_up_ev)
	check(w_spoken.size() > 0 and w_spoken[w_spoken.size() - 1].contains("No weapons"), "Pressing cycle weapon with no weapons speaks 'No weapons'")
	w_spoken.clear()
	var holster_ev := InputEventKey.new()
	holster_ev.physical_keycode = KEY_0
	holster_ev.keycode = KEY_0
	holster_ev.pressed = true
	ow._unhandled_input(holster_ev)
	check(w_spoken.size() > 0 and w_spoken[w_spoken.size() - 1].contains("No weapons"), "Pressing holster with no weapons speaks 'No weapons'")

	var fire_ev := InputEventKey.new()
	fire_ev.physical_keycode = KEY_SEMICOLON
	fire_ev.keycode = KEY_SEMICOLON
	fire_ev.pressed = true
	ow._unhandled_input(fire_ev)
	check(ow.player._punch_cd > 0.0, "Pressing fire while unarmed triggers punch")
	ow.player.give_weapon(Arsenal.Id.PISTOL)
	check(ow.player.weapon == Arsenal.Id.PISTOL, "Player holds Pistol after pickup")
	await frames(2)
	w_spoken.clear()
	ow._unhandled_input(cycle_up_ev)
	check(ow.player.weapon == Arsenal.Id.NONE, "Cycling past last weapon returns to Unarmed (Fists)")
	check(w_spoken.size() > 0 and w_spoken[w_spoken.size() - 1].contains("Unarmed"), "Cycling to Unarmed speaks 'Unarmed'")
	w_spoken.clear()
	ow._unhandled_input(cycle_up_ev)
	check(ow.player.weapon == Arsenal.Id.PISTOL, "Cycling forward from Unarmed selects first owned weapon")
	check(w_spoken.size() > 0 and w_spoken[w_spoken.size() - 1].contains("Pistol"), "Cycling to Pistol speaks 'Pistol'")
	if speech_ref and w_cb.is_valid() and speech_ref.spoken.is_connected(w_cb):
		speech_ref.spoken.disconnect(w_cb)

	# Snap Turn & Level Horizon (even when Snap Turn disabled)
	var yaw_before: float = ow.camera.yaw
	var turn_ev := InputEventAction.new()
	turn_ev.action = "a11y_turn_left"
	turn_ev.pressed = true
	a11y.handle_input(turn_ev)
	check(is_equal_approx(ow.camera.yaw, yaw_before + deg_to_rad(45.0)), "Snap Turn Left rotates camera by +45 degrees")
	var speech_node := root.get_node_or_null("A11ySpeech")
	var prev_snap := true
	if speech_node:
		prev_snap = speech_node.settings.snap_turn_enabled
		speech_node.settings.snap_turn_enabled = false
		speech_node.apply_screen_filter(A11ySettings.FilterMode.DEUTERANOPIA)
		check(speech_node._filter_rect.material.get_shader_parameter("type") == 3, "Deuteranopia filter maps to shader type 3")
		speech_node.apply_screen_filter(A11ySettings.FilterMode.OFF)
	ow.camera.pitch = -0.8
	var center_ev := InputEventAction.new()
	center_ev.action = "a11y_center_pitch"
	center_ev.pressed = true
	a11y.handle_input(center_ev)
	check(is_equal_approx(ow.camera.pitch, -0.04), "Center Pitch levels horizon even when Snap Turn is off")
	if speech_node:
		speech_node.settings.snap_turn_enabled = prev_snap

	# Pause toggle
	ow.toggle_pause()
	await process_frame
	check(ow.paused and ow.player.locked and ow.hud._resume_btn.visible, "Pause locks player and reveals Resume button")
	ow.toggle_pause()
	await process_frame
	check(not ow.paused and not ow.player.locked, "Unpause restores gameplay")

	# Open World Radar & live pickup tracking & split categories (Vehicles / Places / My Assets)
	var ow_places := a11y.radar.collect_targets(ow, ow.player.global_position, A11yRadar.Category.PLACES)
	var ow_vehicles := a11y.radar.collect_targets(ow, ow.player.global_position, A11yRadar.Category.VEHICLES)
	var ow_assets_empty := a11y.radar.collect_targets(ow, ow.player.global_position, A11yRadar.Category.ASSETS)
	var ow_loot_before := a11y.radar.collect_targets(ow, ow.player.global_position, A11yRadar.Category.LOOT)
	var places_only_landmarks := ow_places.size() == 8
	for item in ow_places:
		if not str(item.id).begins_with("place:"):
			places_only_landmarks = false
	var vehicles_only := ow_vehicles.size() > 0
	for item in ow_vehicles:
		if str(item.id).begins_with("place:"):
			vehicles_only = false
	check(places_only_landmarks, "Places filter enumerates all 8 map landmarks only (no vehicles)")
	check(vehicles_only, "Vehicles filter enumerates vehicles/aircraft only (no places)")
	check(ow_assets_empty.is_empty(), "My Assets filter is empty before owning or hijacking vehicles")
	check(ow_loot_before.size() > 0, "Open World radar enumerates live world_pickups")

	# Hospital, Police Station & Health pickup outside static colliders + Auto-Walk reaches Hospital
	var space_chk: PhysicsDirectSpaceState3D = ow.player.get_world_3d().direct_space_state
	var _point_clear := func(p: Vector3) -> bool:
		var pq := PhysicsPointQueryParameters3D.new()
		pq.position = p
		pq.collision_mask = 1
		return space_chk.intersect_point(pq).is_empty()
	check(_point_clear.call(ow.city.hospital_pos + Vector3(0.0, 1.0, 0.0)), "Hospital pos is outside building wall collider")
	check(_point_clear.call(ow.city.station_pos + Vector3(0.0, 1.0, 0.0)), "Police Station pos is outside building wall collider")
	check(ow.city.health_spawns.size() > 0 and _point_clear.call(ow.city.health_spawns[0] + Vector3(0.0, 0.5, 0.0)), "Hospital health pickup is outside building wall collider")
	ow.player.global_position = ow.city.hospital_pos + Vector3(0.0, 0.0, 7.5)
	ow.player.velocity = Vector3.ZERO
	a11y.radar.locked_target_id = "place:hospital"
	a11y.nav.target_label = "Hospital"
	a11y.nav.target_position = ow.city.hospital_pos
	a11y.nav.start_autowalk()
	await frames(120)
	check(not a11y.nav.autowalk_active and ow.player.global_position.distance_to(ow.city.hospital_pos) <= 2.4, "Auto-Walk arrives cleanly at Hospital entrance without wall looping")
	a11y.nav.stop_autowalk(ow.player)
	ow.player.global_position = ow.city.player_spawn
	ow.player.velocity = Vector3.ZERO
	a11y.radar.locked_target_id = ""
	await frames(2)
	if ow_loot_before.size() > 0:
		var first_pickup: Node = ow_loot_before[0].node
		first_pickup.queue_free()
		await process_frame
		var ow_loot_after := a11y.radar.collect_targets(ow, ow.player.global_position, A11yRadar.Category.LOOT)
		check(ow_loot_after.size() == ow_loot_before.size() - 1, "Collected pickup disappears from Open World radar")

	# Auto-walk real movement & cancellation on pause
	a11y.nav.target_position = ow.player.global_position + Vector3(0, 0, -25)
	a11y.nav.target_label = "Harbor Street"
	a11y.nav.autowalk_active = true
	var start_pos: Vector3 = ow.player.global_position
	await frames(25)
	check(ow.player.global_position.distance_to(start_pos) > 0.5, "Auto-walk physically moves Player in Open World")
	ow.set_paused(true)
	await frames(2)
	check(not a11y.nav.autowalk_active and ow.player.a11y_move_override == Vector2.ZERO, "Auto-walk stops safely on pause")
	ow.set_paused(false)

	# LOS Aim Assist against real officer in Open World
	var officers := get_nodes_in_group("foot_cops")
	check(officers.size() > 0, "Harbor Army Base spawns foot officers")
	if officers.size() > 0:
		var officer := officers[0] as Node3D
		check(officer != null, "Foot officer is a Node3D")
		if officer:
			ow.player.global_position = officer.global_position + Vector3(0, 0, 8)
			await frames(3)
			var s := A11ySettings.new()
			var lock_clear := a11y.aim_assist.snap_to_visible_enemy(ow, ow.player, ow.camera, s)
			check(lock_clear.get("locked", false), "LOS Aim Assist locks visible officer in Open World")

	# 4. Auto-Drive (P inside Vehicle) & manual cancellation
	if ow.coupe and is_instance_valid(ow.coupe):
		ow.player.global_position = ow.coupe.global_position + Vector3(2.0, 0.0, 0.0)
		ow._enter_vehicle(ow.coupe)
		await frames(24)
		a11y.radar.locked_target_id = "place:garage"
		a11y.nav.target_position = ow.city.garage_pos
		a11y.nav.target_label = "Drop Warehouse"
		var start_drive_pos: Vector3 = ow.coupe.global_position
		var p_ev := InputEventKey.new()
		p_ev.physical_keycode = KEY_P
		p_ev.keycode = KEY_P
		p_ev.pressed = true
		a11y.handle_input(p_ev)
		check(a11y.nav.autowalk_active and a11y.nav.autopilot_mode == "drive", "Pressing P inside Vehicle activates Auto-Drive")
		await frames(30)
		check(ow.coupe.global_position.distance_to(start_drive_pos) > 1.0, "Auto-Drive physically drives the Vehicle")
		Input.action_press("move_forward")
		await frames(2)
		Input.action_release("move_forward")
		await frames(1)
		check(not a11y.nav.autowalk_active and ow.coupe.a11y_drive_override == Vector2.ZERO, "Manual driving input cancels Auto-Drive")
		ow.coupe.speed = 0.0
		ow._exit_vehicle()
		await frames(2)

	# 5. Resilient Auto-Walk around a blocking wall (never aborts early with Path blocked)
	var test_origin := Vector3(ow.city.ave_xs[5], 0.15, ow.city.st_zs[7])
	var test_dest := test_origin + Vector3(0.0, 0.0, -22.0)
	ow.player.global_position = test_origin
	ow.player.velocity = Vector3.ZERO
	var blocker := StaticBody3D.new()
	blocker.collision_layer = 1
	var bcol := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = Vector3(12.0, 4.0, 1.2)
	bcol.shape = bshape
	blocker.add_child(bcol)
	blocker.position = test_origin + Vector3(0.0, 2.0, -8.0)
	ow.add_child(blocker)
	await frames(2)
	a11y.radar.locked_target_id = ""
	a11y.nav.target_label = "Across Block"
	a11y.nav.target_position = test_dest
	a11y.nav.start_autowalk()
	await frames(170)
	var routed_ok: bool = a11y.nav.autowalk_active or ow.player.global_position.distance_to(test_dest) < 3.5
	check(routed_ok and ow.player.global_position.distance_to(test_origin) > 4.0, "Auto-Walk routes around blocking wall without premature Path blocked stop")
	a11y.nav.stop_autowalk(ow.player)
	blocker.queue_free()
	await frames(2)

	# 6. Universal O key faces any locked Radar target (Places, Vehicles, Pickups)
	ow.player.global_position = Vector3(ow.city.ave_xs[5], 0.15, ow.city.st_zs[7])
	ow.camera.yaw = 0.0
	a11y.radar.locked_target_id = "place:gun_shop"
	var o_ev := InputEventKey.new()
	o_ev.physical_keycode = KEY_O
	o_ev.keycode = KEY_O
	o_ev.pressed = true
	a11y.handle_input(o_ev)
	var want_place_yaw := A11yRadar.yaw_toward(ow.player.global_position, ow.city.gun_shop_pos)
	check(absf(angle_difference(ow.camera.yaw, want_place_yaw)) < 0.18, "Pressing O faces locked Place target on Radar")

	if ow.coupe and is_instance_valid(ow.coupe) and not ow.coupe.wrecked:
		a11y.radar.locked_target_id = "veh:%d" % ow.coupe.get_instance_id()
		a11y.handle_input(o_ev)
		var want_veh_yaw := A11yRadar.yaw_toward(ow.player.global_position, ow.coupe.global_position)
		check(absf(angle_difference(ow.camera.yaw, want_veh_yaw)) < 0.18 and absf(angle_difference(ow.player.rotation.y, want_veh_yaw)) < 0.18, "Pressing O rotates camera and standing player toward locked Vehicle")

	var live_loot := a11y.radar.collect_targets(ow, ow.player.global_position, A11yRadar.Category.LOOT)
	if live_loot.size() > 0:
		a11y.radar.locked_target_id = str(live_loot[0].id)
		a11y.handle_input(o_ev)
		var want_loot_yaw := A11yRadar.yaw_toward(ow.player.global_position, live_loot[0].position)
		check(absf(angle_difference(ow.camera.yaw, want_loot_yaw)) < 0.18, "Pressing O faces locked Pickup target on Radar")

	# 7. Auto-Drive wide-road top speed, 20m wall slowdown/avoidance, and zero crash damage
	if ow.coupe and is_instance_valid(ow.coupe):
		ow.coupe.repair()
		ow.coupe.speed = 0.0
		ow.coupe.velocity = Vector3.ZERO
		ow.coupe.global_position = Vector3(ow.city.ave_xs[5], 0.35, ow.city.st_zs[10])
		ow.coupe.rotation.y = 0.0
		ow.coupe.force_update_transform()
		ow._enter_vehicle(ow.coupe)
		await frames(3)
		a11y.radar.locked_target_id = ""
		a11y.nav.target_label = "North Avenue"
		a11y.nav.target_position = Vector3(ow.city.ave_xs[5], 0.15, ow.city.st_zs[2])
		a11y.nav.start_autodrive()
		var max_open_speed := 0.0
		for _i in 95:
			await physics_frame
			await process_frame
			max_open_speed = maxf(max_open_speed, ow.coupe.speed)
		check(max_open_speed > 45.0, "Auto-Drive accelerates toward top speed on wide clear avenue")
		var wall_pos: Vector3 = ow.coupe.global_position + Vector3(0.0, 2.5, -28.0)
		var wall_blocker := StaticBody3D.new()
		wall_blocker.collision_layer = 1
		var wb_col := CollisionShape3D.new()
		var wb_shape := BoxShape3D.new()
		wb_shape.size = Vector3(14.0, 5.0, 2.0)
		wb_col.shape = wb_shape
		wall_blocker.add_child(wb_col)
		wall_blocker.position = wall_pos
		ow.add_child(wall_blocker)
		await frames(1)
		var min_avoid_speed: float = ow.coupe.speed
		for _i in 150:
			await physics_frame
			await process_frame
			min_avoid_speed = minf(min_avoid_speed, ow.coupe.speed)
		check(min_avoid_speed < max_open_speed * 0.65, "Auto-Drive decelerates when detecting wall ahead within 20m")
		check(ow.coupe.hp == 100.0 and not ow.coupe.burning and not ow.coupe.exploded, "Auto-Drive avoids wall without high-speed crash damage or explosion")
		a11y.nav.stop_autowalk(ow.player, "", ow.coupe)
		ow.coupe.speed = 0.0

		# Boxed-in Auto-Drive (front + rear walls) does not reverse-slam
		ow.coupe.repair()
		ow.coupe.speed = 0.0
		ow.coupe.global_position = Vector3(ow.city.ave_xs[5], 0.35, ow.city.st_zs[10])
		ow.coupe.rotation.y = 0.0
		ow.coupe.force_update_transform()
		wall_blocker.position = ow.coupe.global_position + Vector3(0.0, 2.5, -5.2)
		var rear_blocker := StaticBody3D.new()
		rear_blocker.collision_layer = 1
		var rb_col := CollisionShape3D.new()
		var rb_shape := BoxShape3D.new()
		rb_shape.size = Vector3(14.0, 5.0, 2.0)
		rb_col.shape = rb_shape
		rear_blocker.add_child(rb_col)
		rear_blocker.position = ow.coupe.global_position + Vector3(0.0, 2.5, 5.0)
		ow.add_child(rear_blocker)
		await frames(2)
		a11y.nav.target_position = ow.coupe.global_position + Vector3(0.0, 0.0, -40.0)
		a11y.nav.start_autodrive()
		await frames(60)
		check(ow.coupe.hp == 100.0 and not ow.coupe.exploded, "Boxed-in Auto-Drive does not reverse-slam rear obstacle")
		a11y.nav.stop_autowalk(ow.player, "", ow.coupe)
		rear_blocker.queue_free()

		# Arrival retains ABS handbrake until stopped
		wall_blocker.queue_free()
		ow.coupe.speed = 24.0
		ow.coupe.global_position = Vector3(ow.city.ave_xs[5], 0.35, ow.city.st_zs[10])
		a11y.nav.target_label = "Close Stop"
		a11y.nav.target_position = ow.coupe.global_position + Vector3(0.0, 0.0, -5.0)
		a11y.nav.start_autodrive()
		await frames(25)
		check(not a11y.nav.autowalk_active and absf(ow.coupe.speed) <= 3.0, "Auto-Drive arrival retains ABS handbrake until vehicle stops")

		ow._exit_vehicle()
		await frames(2)

		# Stolen coupe is tracked in My Assets even from across the map (> 120m)
		ow.player.global_position = Vector3(-220.0, 0.15, -220.0)
		var assets_far := a11y.radar.collect_targets(ow, ow.player.global_position, A11yRadar.Category.ASSETS)
		var found_coupe := false
		for aitem in assets_far:
			if aitem.get("node") == ow.coupe:
				found_coupe = true
		check(found_coupe, "My Assets tracks hijacked vehicle city-wide beyond 120m")

	ow.queue_free()
	await process_frame
	print("ACCESSIBILITY_SUITE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
