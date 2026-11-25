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

	# Open World Radar & live pickup tracking
	var ow_places := a11y.radar.collect_targets(ow, ow.player.global_position, A11yRadar.Category.PLACES)
	var ow_loot_before := a11y.radar.collect_targets(ow, ow.player.global_position, A11yRadar.Category.LOOT)
	check(ow_places.size() >= 7, "Open World radar enumerates Harbor District landmarks and vehicles")
	check(ow_loot_before.size() > 0, "Open World radar enumerates live world_pickups")
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

	ow.queue_free()
	await process_frame
	print("ACCESSIBILITY_SUITE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
