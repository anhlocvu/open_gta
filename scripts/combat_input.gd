class_name CombatInput
extends RefCounted
## Add defaults only when missing so saved/custom InputMap bindings win.
static func _make_key_event(phys_key: int, shift := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.device = -1
	event.physical_keycode = phys_key
	event.shift_pressed = shift
	return event


static func install() -> void:
	var keys := {"move_left": KEY_A, "move_right": KEY_D, "move_forward": KEY_W,
		"move_back": KEY_S, "jump": KEY_SPACE, "sprint": KEY_SHIFT,
		"crouch": KEY_CTRL, "reload": KEY_R, "swap_shoulder": KEY_Q,
		"tactical_sprint": KEY_T, "interact": KEY_E,
		"return_menu": KEY_TAB}
	keys["cover"] = KEY_C
	keys["weapon_holster"] = KEY_0
	keys["weapon_1"] = KEY_1
	keys["weapon_2"] = KEY_2
	keys["weapon_3"] = KEY_3
	keys["graphics_profile"] = KEY_F6
	keys["dev_panel"] = KEY_F1
	keys["melee"] = KEY_F
	keys["armor_plate"] = KEY_4
	keys["camera_view"] = KEY_V
	keys["weapon_4"] = KEY_5
	# Accessibility actions (never bind Insert, CapsLock, or Numpad)
	keys["a11y_turn_left"] = KEY_J
	keys["a11y_turn_right"] = KEY_L
	keys["a11y_look_up"] = KEY_I
	keys["a11y_look_down"] = KEY_K
	keys["a11y_center_pitch"] = KEY_U
	keys["a11y_aim_assist"] = KEY_O
	keys["a11y_status"] = KEY_Z
	keys["a11y_objective"] = KEY_X
	keys["a11y_compass"] = KEY_H
	keys["a11y_radar_cycle"] = KEY_B
	keys["a11y_radar_prev"] = KEY_COMMA
	keys["a11y_radar_next"] = KEY_PERIOD
	keys["a11y_beacon_toggle"] = KEY_M
	keys["a11y_autowalk"] = KEY_P
	keys["a11y_sonar_sweep"] = KEY_G
	keys["a11y_history_prev"] = KEY_BRACKETLEFT
	keys["a11y_history_next"] = KEY_BRACKETRIGHT
	keys["a11y_repeat_last"] = KEY_BACKSLASH
	keys["a11y_help"] = KEY_SLASH
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		InputMap.action_add_event(action, _make_key_event(int(keys[action])))
	if not InputMap.has_action("a11y_radar_cycle_prev"):
		InputMap.add_action("a11y_radar_cycle_prev")
		InputMap.action_add_event("a11y_radar_cycle_prev", _make_key_event(KEY_B, true))
	if not InputMap.has_action("a11y_snap_enemy"):
		InputMap.add_action("a11y_snap_enemy")
		InputMap.action_add_event("a11y_snap_enemy", _make_key_event(KEY_O, true))
	var dual_actions := {
		"fire": [MOUSE_BUTTON_LEFT, KEY_SEMICOLON],
		"aim": [MOUSE_BUTTON_RIGHT, KEY_APOSTROPHE],
		"cycle_weapon_up": [MOUSE_BUTTON_WHEEL_UP, KEY_EQUAL],
		"cycle_weapon_down": [MOUSE_BUTTON_WHEEL_DOWN, KEY_MINUS],
	}
	for action in dual_actions:
		if InputMap.has_action(action):
			continue
		var spec: Array = dual_actions[action]
		InputMap.add_action(action)
		var mouse_ev := InputEventMouseButton.new()
		mouse_ev.device = -1
		mouse_ev.button_index = int(spec[0])
		InputMap.action_add_event(action, mouse_ev)
		InputMap.action_add_event(action, _make_key_event(int(spec[1])))
