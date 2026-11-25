class_name GameHUD
extends CanvasLayer

const ACTION_LABELS := {
	"move_left": "Move Left", "move_right": "Move Right", "move_forward": "Move Forward", "move_back": "Move Back",
	"jump": "Jump", "sprint": "Sprint", "crouch": "Crouch / Slide", "cover": "Take Cover",
	"aim": "Aim ADS", "fire": "Fire / Punch Unarmed", "reload": "Reload", "interact": "Enter / Exit / Interact",
	"swap_shoulder": "Swap Shoulder", "tactical_sprint": "Tactical Sprint", "melee": "Punch / Melee",
	"return_menu": "Pause Menu", "camera_view": "Toggle Camera View", "graphics_profile": "Graphics Quality",
	"weapon_holster": "Holster / Unarmed", "weapon_1": "Pistol / Buy Pistol", "weapon_2": "SMG / Buy SMG", "weapon_3": "Rifle / Buy Rifle", "weapon_4": "Shotgun / Buy Shotgun",
	"cycle_weapon_up": "Next Weapon", "cycle_weapon_down": "Previous Weapon",
	"a11y_turn_left": "Turn Left (Keyboard)", "a11y_turn_right": "Turn Right (Keyboard)",
	"a11y_look_up": "Look Up (Keyboard)", "a11y_look_down": "Look Down (Keyboard)",
	"a11y_center_pitch": "Center Pitch / Level Horizon", "a11y_aim_assist": "Snap Aim to Visible Enemy",
	"a11y_status": "Read Player Status", "a11y_objective": "Read Objective & Distance",
	"a11y_compass": "Read Compass Heading", "a11y_radar_cycle": "Next Radar Filter",
	"a11y_radar_cycle_prev": "Previous Radar Filter",
	"a11y_radar_prev": "Previous Radar Target", "a11y_radar_next": "Next Radar Target",
	"a11y_sonar_sweep": "360 Audio Sonar Sweep",
	"a11y_beacon_toggle": "Toggle 3D Navigation Beacon", "a11y_autowalk": "Toggle Auto-Walk",
	"a11y_history_prev": "Speech History Previous", "a11y_history_next": "Speech History Next",
	"a11y_repeat_last": "Repeat Last Speech", "a11y_help": "Accessibility Controls Help"
}

var _title: Label
var _brief: Label
var _continue_btn: Button
var _start: Button
var _resume_btn: Button
var _save_btn: Button
var _load_btn: Button
var _settings_btn: Button
var _main_menu_btn: Button
var _quit_btn: Button
var _objective: Label
var _stars: Label
var _prompt: Label
var _banner: Label
var _dist: Label
var _district: Label
var _start_panel: ColorRect
var _menu_col: VBoxContainer
var _settings_scroll: ScrollContainer
var _settings_content: VBoxContainer
var _tag: Label
var _health: Label
var _money: Label
var _crime: Label
var _weapon: Label
var _speed: Label
var radar: Radar
var _heat_punch: Tween
var reticle: CombatReticle
var _waiting_action := ""
var _waiting_prev_text := ""
var _binding_button: Button
var _in_pause := false


func _game() -> Node:
	return get_tree().current_scene


func set_combat(on: bool, ads: bool, speed: float) -> void:
	reticle.visible = on
	reticle.gap = 3.0 if ads else 8.0 + minf(speed, 10.0)


func confirm_hit() -> void:
	reticle.hit_remaining = 0.15


func _ready() -> void:
	layer = 10
	_build()
	show_start(true)
	set_banner("")
	set_prompt("")


func show_start(on: bool) -> void:
	_in_pause = false
	_start_panel.visible = on
	if _menu_col: _menu_col.visible = true
	if _settings_scroll: _settings_scroll.visible = false
	if _settings_content: _settings_content.visible = false
	var sum := SaveManager.peek_summary()
	var has_save := not sum.is_empty()
	if _continue_btn:
		_continue_btn.visible = on and has_save
		if has_save:
			_continue_btn.text = "CONTINUE GAME  ·  $%d  (%d PACKAGES LEFT)" % [int(sum.get("money", 420)), int(sum.get("packages_left", 3))]
	if _resume_btn: _resume_btn.visible = false
	if _save_btn: _save_btn.visible = false
	if _load_btn: _load_btn.visible = false
	if _main_menu_btn: _main_menu_btn.visible = false
	if _start: _start.visible = true
	if on and reticle:
		reticle.visible = false
	if radar: radar.visible = not on
	if _health:
		_health.visible = not on
		_money.visible = not on
	if _weapon: _weapon.visible = not on
	if _speed: _speed.visible = not on
	if _district: _district.visible = not on
	if on and _start:
		A11yUIHelper.say("Operation Chaos Main Menu. Slash for help.", true, 2, &"ui_screen")
		A11yUIHelper.grab_focus_safe(_continue_btn if (_continue_btn and _continue_btn.visible) else _start)
	elif not on:
		A11yUIHelper.release_focus_safe(get_viewport())


func show_pause(on: bool, silent := false) -> void:
	_in_pause = on
	_start_panel.visible = on
	if _menu_col: _menu_col.visible = true
	if _settings_scroll: _settings_scroll.visible = false
	if _settings_content: _settings_content.visible = false
	if _continue_btn: _continue_btn.visible = false
	if _resume_btn: _resume_btn.visible = on
	if _save_btn: _save_btn.visible = on
	if _load_btn:
		_load_btn.visible = on
		_load_btn.disabled = not SaveManager.has_save()
	if _main_menu_btn: _main_menu_btn.visible = on
	if _start: _start.visible = not on
	if on and reticle:
		reticle.visible = false
	if radar: radar.visible = not on
	if _health:
		_health.visible = not on
		_money.visible = not on
	if _weapon: _weapon.visible = not on
	if _speed: _speed.visible = not on
	if _district: _district.visible = not on
	if on and _resume_btn:
		if not silent:
			A11yUIHelper.say("Game paused.", true, 3, &"ui_screen", true)
		A11yUIHelper.grab_focus_safe(_resume_btn)
	elif not on:
		A11yUIHelper.release_focus_safe(get_viewport())
		if not silent:
			A11yUIHelper.say("Resumed.", true, 2, &"ui_screen", true)


func set_objective(text: String) -> void:
	_objective.text = text


func set_wanted(stars: int, rank_delta := 0) -> void:
	if stars <= 0:
		_stars.text = ""
		_reset_heat_punch()
		return
	_stars.text = "HEAT  " + "◆".repeat(stars) + "◇".repeat(maxi(0, 5 - stars))
	if rank_delta > 0:
		_punch_heat()


func _punch_heat() -> void:
	if _heat_punch and _heat_punch.is_valid():
		_heat_punch.kill()
	_stars.pivot_offset = _stars.size * 0.5
	_stars.scale = Vector2.ONE
	_stars.modulate = Color.WHITE
	_heat_punch = create_tween()
	_heat_punch.set_parallel(true)
	_heat_punch.tween_property(_stars, "scale", Vector2(1.32, 1.32), 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_heat_punch.tween_property(_stars, "modulate", Color("fff1a8"), 0.07)
	_heat_punch.chain().set_parallel(true)
	_heat_punch.tween_property(_stars, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_heat_punch.tween_property(_stars, "modulate", Color.WHITE, 0.22)


func _reset_heat_punch() -> void:
	if _heat_punch and _heat_punch.is_valid():
		_heat_punch.kill()
	_heat_punch = null
	if _stars:
		_stars.scale = Vector2.ONE
		_stars.modulate = Color.WHITE


func set_prompt(text: String) -> void:
	_prompt.text = text


func set_banner(text: String) -> void:
	_banner.text = text
	_banner.visible = text != ""
	if text != "":
		A11yUIHelper.say(text, false, 2, &"hud_banner")


func set_stats(health: float, money: int, weapon := "", speed := -1.0) -> void:
	if _health:
		_health.text = "HP  %d" % int(health)
		_health.add_theme_color_override("font_color", Color("ff6a6a") if health < 30.0 else Color("8eecc0"))
	if _money:
		_money.text = "$%d" % money
	if _weapon:
		_weapon.text = weapon
	if _speed:
		_speed.text = "" if speed < 0.0 else "%d MPH" % int(speed * 2.4)


func set_crime(text: String) -> void:
	if _crime:
		_crime.text = text


func page(text: String) -> void:
	set_crime(text)


func set_distance(meters: float, label: String) -> void:
	if meters < 0.0:
		_dist.text = ""
		return
	_dist.text = "%s  ·  %dm" % [label, int(round(meters))]


func set_district(text: String) -> void:
	if _district:
		_district.text = text.to_upper() if text != "" else ""


func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	reticle = CombatReticle.new()
	reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle.visible = false
	root.add_child(reticle)

	_objective = _label(18, Color("f0e6c8"))
	_objective.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_objective.offset_left = 188
	_objective.offset_top = 20
	_objective.offset_right = 820
	_objective.offset_bottom = 52
	root.add_child(_objective)

	_health = _label(16, Color("8eecc0"))
	_health.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_health.offset_left = 188
	_health.offset_top = 48
	_health.offset_right = 360
	_health.offset_bottom = 72
	root.add_child(_health)

	_money = _label(20, Color("f0d060"))
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_money.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_money.offset_left = -280
	_money.offset_top = 18
	_money.offset_right = -24
	_money.offset_bottom = 46
	root.add_child(_money)

	_weapon = _label(15, Color("d8e6f0"))
	_weapon.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_weapon.offset_left = 188
	_weapon.offset_top = 72
	_weapon.offset_right = 420
	_weapon.offset_bottom = 96
	root.add_child(_weapon)

	_speed = _label(16, Color("f0e6c8"))
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_speed.offset_left = -200
	_speed.offset_top = 128
	_speed.offset_right = -24
	_speed.offset_bottom = 154
	root.add_child(_speed)

	_dist = _label(15, Color(0.94, 0.63, 0.19, 0.9))
	_dist.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_dist.offset_left = 188
	_dist.offset_top = 96
	_dist.offset_right = 520
	_dist.offset_bottom = 120
	root.add_child(_dist)

	_district = _label(13, Color(0.75, 0.86, 0.95, 0.88))
	_district.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_district.offset_left = 188
	_district.offset_top = 120
	_district.offset_right = 520
	_district.offset_bottom = 142
	root.add_child(_district)

	_crime = _label(14, Color("ff8a6a"))
	_crime.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_crime.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crime.offset_top = 18
	_crime.offset_bottom = 42
	root.add_child(_crime)

	radar = Radar.new()
	radar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	radar.offset_left = 18
	radar.offset_top = 18
	radar.offset_right = 172
	radar.offset_bottom = 172
	root.add_child(radar)

	_stars = _label(22, Color("ff5a5a"))
	_stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stars.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stars.offset_left = -360
	_stars.offset_top = 48
	_stars.offset_right = -24
	_stars.offset_bottom = 82
	root.add_child(_stars)

	_prompt = _label(16, Color(0.94, 0.63, 0.19))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left = -280
	_prompt.offset_top = -150
	_prompt.offset_right = 280
	_prompt.offset_bottom = -120
	root.add_child(_prompt)

	_banner = _label(42, Palette.amber())
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.offset_left = -420
	_banner.offset_top = -40
	_banner.offset_right = 420
	_banner.offset_bottom = 40
	root.add_child(_banner)

	_start_panel = ColorRect.new()
	_start_panel.color = Color(0.08, 0.11, 0.16, 0.84)
	_start_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_start_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_start_panel)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_start_panel.add_child(center)

	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 580
	col.add_theme_constant_override("separation", 12)
	center.add_child(col)

	_tag = _label(14, Color(0.94, 0.63, 0.19, 0.9))
	_tag.text = "HARBOR DISTRICT  ·  DAY RUN"
	_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_tag)

	_title = _label(48, Color("f0e6c8"))
	_title.text = "OPERATION CHAOS"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)

	_menu_col = VBoxContainer.new()
	_menu_col.add_theme_constant_override("separation", 12)
	col.add_child(_menu_col)

	_brief = _label(18, Color(0.88, 0.86, 0.78, 0.95))
	_brief.text = "Open-world crime sandbox. Steal the amber coupe, lose the heat, make the drop.\nUse Tab or Arrows to navigate, Enter to activate, Slash for help."
	_brief.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_col.add_child(_brief)

	_resume_btn = _primary_button("RESUME GAME", func() -> void:
		var g := _game()
		if g and g.has_method("set_paused"): g.set_paused(false))
	_resume_btn.visible = false
	_menu_col.add_child(_resume_btn)
	A11yUIHelper.wire_button(_resume_btn, "Return to Harbor District gameplay")

	_continue_btn = _primary_button("CONTINUE GAME", _on_continue)
	_continue_btn.visible = false
	_menu_col.add_child(_continue_btn)
	A11yUIHelper.wire_button(_continue_btn, "Resume your saved open world progress")

	_start = _primary_button("NEW GAME · OPEN WORLD", _on_start)
	_menu_col.add_child(_start)
	A11yUIHelper.wire_button(_start, "Start a new open world mission")

	_save_btn = _mode_button("SAVE GAME")
	_save_btn.visible = false
	_save_btn.pressed.connect(func() -> void:
		var g := _game()
		if g and g.has_method("save_current_game"): g.save_current_game())
	_menu_col.add_child(_save_btn)
	A11yUIHelper.wire_button(_save_btn, "Save current progress")

	_load_btn = _mode_button("LOAD SAVED GAME")
	_load_btn.visible = false
	_load_btn.pressed.connect(func() -> void:
		var g := _game()
		if g and g.has_method("load_saved_game"): g.load_saved_game())
	_menu_col.add_child(_load_btn)
	A11yUIHelper.wire_button(_load_btn, "Load last saved game")

	_settings_btn = _mode_button("SETTINGS")
	_settings_btn.pressed.connect(_show_settings)
	_menu_col.add_child(_settings_btn)
	A11yUIHelper.wire_button(_settings_btn, "Graphics, audio, NVDA accessibility, and key bindings")

	_main_menu_btn = _mode_button("MAIN MENU")
	_main_menu_btn.visible = false
	_main_menu_btn.pressed.connect(func() -> void:
		var g := _game()
		if g and g.has_method("return_to_main_menu"): g.return_to_main_menu())
	_menu_col.add_child(_main_menu_btn)
	A11yUIHelper.wire_button(_main_menu_btn, "Return to main menu without saving")

	_quit_btn = _mode_button("QUIT")
	_quit_btn.pressed.connect(func() -> void: get_tree().quit())
	_menu_col.add_child(_quit_btn)
	A11yUIHelper.wire_button(_quit_btn, "Exit game")

	var keys := _label(13, Color(0.78, 0.76, 0.68, 0.85))
	keys.text = "WASD move · ; fire/punch · ' aim · -/= weapons · 0 fists · J/L turn · O snap aim · B/Shift+B radar · G sonar · Slash help"
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_col.add_child(keys)

	_settings_scroll = ScrollContainer.new()
	_settings_scroll.custom_minimum_size = Vector2(580, 460)
	_settings_scroll.visible = false
	_settings_scroll.follow_focus = true
	col.add_child(_settings_scroll)

	_settings_content = VBoxContainer.new()
	_settings_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_content.add_theme_constant_override("separation", 8)
	_settings_content.visible = false
	_settings_scroll.add_child(_settings_content)


func _show_settings() -> void:
	var g := _game()
	if g == null:
		return
	_waiting_action = ""
	_waiting_prev_text = ""
	_binding_button = null
	for child in _settings_content.get_children():
		_settings_content.remove_child(child)
		child.queue_free()
	_menu_col.visible = false
	_settings_scroll.visible = true
	_settings_content.visible = true
	_settings_content.add_child(_label(24, Color("f0e6c8"), "SETTINGS"))

	var view := CheckButton.new()
	view.text = "First-person camera"
	view.button_pressed = g.camera.first_person
	_settings_content.add_child(view)
	A11yUIHelper.wire_toggle(view, "First-person camera")
	view.toggled.connect(func(on: bool) -> void:
		g.camera.set_first_person(on)
		g.save_settings())

	_settings_content.add_child(_label(16, Color("f0e6c8"), "Field of View (FOV)"))
	var fov := HSlider.new()
	fov.min_value = 70
	fov.max_value = 110
	fov.step = 1
	fov.value = g.camera.first_person_fov
	_settings_content.add_child(fov)
	A11yUIHelper.wire_slider(fov, "Field of View", func(v: float) -> String: return "%d degrees" % int(round(v)))
	fov.value_changed.connect(func(value: float) -> void:
		if is_instance_valid(g):
			g.camera.first_person_fov = value)
	fov.drag_ended.connect(func(_changed: bool) -> void:
		if is_instance_valid(g):
			g.save_settings())

	var quality := OptionButton.new()
	for text in ["LOW", "MEDIUM", "HIGH"]:
		quality.add_item(text)
	quality.select(g.clock.quality)
	_settings_content.add_child(quality)
	A11yUIHelper.wire_option(quality, "Graphics Quality")
	quality.item_selected.connect(func(value: int) -> void:
		if is_instance_valid(g):
			g.clock.set_quality(value)
			g.save_settings())

	_settings_content.add_child(_label(16, Color("f0e6c8"), "Master Volume"))
	var master := HSlider.new()
	master.min_value = 0.0
	master.max_value = 1.0
	master.step = 0.05
	master.value = g.master_volume
	_settings_content.add_child(master)
	A11yUIHelper.wire_slider(master, "Master Volume")
	master.value_changed.connect(func(value: float) -> void:
		if is_instance_valid(g):
			g.set_master_volume(value))
	master.drag_ended.connect(func(_changed: bool) -> void:
		if is_instance_valid(g):
			g.save_settings())

	_settings_content.add_child(_label(16, Color("f0e6c8"), "Mouse / ADS Sensitivity"))
	var mouse := HSlider.new()
	mouse.min_value = 0.001
	mouse.max_value = 0.008
	mouse.step = 0.0001
	mouse.value = g.camera.mouse_sens
	_settings_content.add_child(mouse)
	A11yUIHelper.wire_slider(mouse, "Mouse Sensitivity")
	mouse.value_changed.connect(func(value: float) -> void:
		if is_instance_valid(g):
			g.camera.mouse_sens = value)
	mouse.drag_ended.connect(func(_changed: bool) -> void:
		if is_instance_valid(g):
			g.save_settings())

	var ads := HSlider.new()
	ads.min_value = 0.2
	ads.max_value = 1.0
	ads.step = 0.05
	ads.value = g.camera.ads_sensitivity
	_settings_content.add_child(ads)
	A11yUIHelper.wire_slider(ads, "ADS Sensitivity")
	ads.value_changed.connect(func(value: float) -> void:
		if is_instance_valid(g):
			g.camera.ads_sensitivity = value)
	ads.drag_ended.connect(func(_changed: bool) -> void:
		if is_instance_valid(g):
			g.save_settings())

	_build_accessibility_settings(g)

	_settings_content.add_child(_label(18, Color("f0e6c8"), "Key Bindings"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 140
	scroll.follow_focus = true
	_settings_content.add_child(scroll)
	var bindings := GridContainer.new()
	bindings.columns = 2
	bindings.add_theme_constant_override("h_separation", 8)
	bindings.add_theme_constant_override("v_separation", 8)
	scroll.add_child(bindings)
	for action in ACTION_LABELS:
		var events := InputMap.action_get_events(action)
		var key_name := events[0].as_text().replace(" - Physical", "") if not events.is_empty() else "Unbound"
		var caption := str(ACTION_LABELS.get(action, action)) + " · " + key_name
		var binding := _mode_button(caption)
		bindings.add_child(binding)
		A11yUIHelper.wire_button(binding, "Press Enter to rebind")
		binding.pressed.connect(func() -> void:
			_waiting_action = action
			_binding_button = binding
			_waiting_prev_text = binding.text
			binding.text = "Press key or button · Esc cancels"
			A11yUIHelper.say("Listening for new key for %s. Press Escape to cancel." % str(ACTION_LABELS.get(action, action)), true, 3, &"ui_rebind", true))

	var back := _mode_button("BACK")
	back.pressed.connect(_close_settings)
	_settings_content.add_child(back)
	A11yUIHelper.wire_button(back, "Return to menu")
	A11yUIHelper.say("Settings opened. Use Tab or arrows to navigate.", true, 2, &"ui_screen", true)
	A11yUIHelper.grab_focus_safe(view)


func _build_accessibility_settings(g: Node) -> void:
	var speech := A11yUIHelper.speech()
	if speech == null:
		return
	var s: A11ySettings = speech.settings
	_settings_content.add_child(_label(20, Color("f0e6c8"), "ACCESSIBILITY (NVDA & AUDIO)"))

	var nvda_chk := CheckButton.new()
	nvda_chk.text = "NVDA Screen Reader Speech"
	nvda_chk.button_pressed = s.speech_enabled
	_settings_content.add_child(nvda_chk)
	A11yUIHelper.wire_toggle(nvda_chk, "NVDA Screen Reader Speech")
	nvda_chk.toggled.connect(func(on: bool) -> void:
		s.speech_enabled = on
		g.save_settings())

	var verb := OptionButton.new()
	verb.add_item("Combat Detail · Minimal", A11ySettings.Verbosity.MINIMAL)
	verb.add_item("Combat Detail · Standard", A11ySettings.Verbosity.STANDARD)
	verb.add_item("Combat Detail · Detailed", A11ySettings.Verbosity.DETAILED)
	var v_idx := verb.get_item_index(s.combat_verbosity)
	verb.select(v_idx if v_idx >= 0 else 1)
	_settings_content.add_child(verb)
	A11yUIHelper.wire_option(verb, "Combat Speech Detail")
	verb.item_selected.connect(func(idx: int) -> void:
		s.combat_verbosity = verb.get_item_id(idx) as A11ySettings.Verbosity
		if is_instance_valid(g):
			g.save_settings())

	_settings_content.add_child(_label(16, Color("f0e6c8"), "Accessibility Cue Volume"))
	var cue_vol := HSlider.new()
	cue_vol.min_value = 0.0
	cue_vol.max_value = 1.0
	cue_vol.step = 0.05
	cue_vol.value = s.cue_volume
	_settings_content.add_child(cue_vol)
	A11yUIHelper.wire_slider(cue_vol, "Accessibility Cue Volume")
	cue_vol.value_changed.connect(func(v: float) -> void:
		s.cue_volume = v)
	cue_vol.drag_ended.connect(func(_changed: bool) -> void:
		if is_instance_valid(g):
			g.save_settings())

	var snap_chk := CheckButton.new()
	snap_chk.text = "Snap Turn Mode (On = Snap Step, Off = Smooth)"
	snap_chk.button_pressed = s.snap_turn_enabled
	_settings_content.add_child(snap_chk)
	A11yUIHelper.wire_toggle(snap_chk, "Snap Turn Mode")
	snap_chk.toggled.connect(func(on: bool) -> void:
		s.snap_turn_enabled = on
		g.save_settings())

	var snap_deg := OptionButton.new()
	for deg in A11ySettings.SNAP_ANGLES:
		snap_deg.add_item("Snap Angle · %d degrees" % int(deg), int(deg))
	var sel_idx := A11ySettings.SNAP_ANGLES.find(s.snap_turn_degrees)
	snap_deg.select(sel_idx if sel_idx >= 0 else 2)
	_settings_content.add_child(snap_deg)
	A11yUIHelper.wire_option(snap_deg, "Snap Turn Angle")
	snap_deg.item_selected.connect(func(idx: int) -> void:
		s.snap_turn_degrees = float(snap_deg.get_item_id(idx))
		g.save_settings())

	var aim_chk := CheckButton.new()
	aim_chk.text = "LOS Aim Assist (Visible Enemies Only)"
	aim_chk.button_pressed = s.aim_assist_enabled
	_settings_content.add_child(aim_chk)
	A11yUIHelper.wire_toggle(aim_chk, "LOS Aim Assist")
	aim_chk.toggled.connect(func(on: bool) -> void:
		s.aim_assist_enabled = on
		g.save_settings())

	var cross_chk := CheckButton.new()
	cross_chk.text = "Acoustic Crosshair Ping"
	cross_chk.button_pressed = s.acoustic_crosshair_enabled
	_settings_content.add_child(cross_chk)
	A11yUIHelper.wire_toggle(cross_chk, "Acoustic Crosshair Ping")
	cross_chk.toggled.connect(func(on: bool) -> void:
		s.acoustic_crosshair_enabled = on
		g.save_settings())

	var beacon_chk := CheckButton.new()
	beacon_chk.text = "3D Navigation Audio Beacon"
	beacon_chk.button_pressed = s.beacon_enabled
	_settings_content.add_child(beacon_chk)
	A11yUIHelper.wire_toggle(beacon_chk, "3D Navigation Audio Beacon")
	beacon_chk.toggled.connect(func(on: bool) -> void:
		s.beacon_enabled = on
		g.save_settings())

	var obs_chk := CheckButton.new()
	obs_chk.text = "Obstacle & Cover Proximity Cues"
	obs_chk.button_pressed = s.obstacle_cues_enabled
	_settings_content.add_child(obs_chk)
	A11yUIHelper.wire_toggle(obs_chk, "Obstacle and Cover Proximity Cues")
	obs_chk.toggled.connect(func(on: bool) -> void:
		s.obstacle_cues_enabled = on
		g.save_settings())

	var flt := OptionButton.new()
	for fname in ["Screen Filter · Off", "Screen Filter · Grayscale", "Screen Filter · Protanopia", "Screen Filter · Deuteranopia", "Screen Filter · Tritanopia"]:
		flt.add_item(fname)
	flt.select(s.screen_filter_mode)
	_settings_content.add_child(flt)
	A11yUIHelper.wire_option(flt, "Visual Screen Filter")
	flt.item_selected.connect(func(idx: int) -> void:
		speech.apply_screen_filter(idx)
		g.save_settings())


func _close_settings() -> void:
	_settings_content.visible = false
	_settings_scroll.visible = false
	_menu_col.visible = true
	_waiting_action = ""
	_waiting_prev_text = ""
	_binding_button = null
	var g := _game()
	if g and g.has_method("save_settings"):
		g.save_settings()
	A11yUIHelper.say("Pause Menu." if _in_pause else "Main Menu. Operation Chaos.", true, 2, &"ui_screen", true)
	var target: Control = _resume_btn if _in_pause else (_continue_btn if (_continue_btn and _continue_btn.visible) else _start)
	A11yUIHelper.grab_focus_safe(target)


func capture_binding(event: InputEvent) -> bool:
	if _waiting_action == "":
		return false
	if (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed() and not event.is_echo():
		if event is InputEventKey:
			var k := event as InputEventKey
			var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			if code in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
				return true
			if k.keycode in [KEY_INSERT, KEY_CAPSLOCK] or k.physical_keycode in [KEY_INSERT, KEY_CAPSLOCK]:
				A11yUIHelper.say("Insert and Caps Lock are reserved for NVDA. Choose another key.", true, 3, &"ui_rebind", true)
				return true
			if k.keycode == KEY_ESCAPE or k.physical_keycode == KEY_ESCAPE:
				_waiting_action = ""
				if is_instance_valid(_binding_button):
					_binding_button.text = _waiting_prev_text
					A11yUIHelper.grab_focus_safe(_binding_button, true)
				_waiting_prev_text = ""
				_binding_button = null
				A11yUIHelper.say("Rebinding cancelled.", true, 3, &"ui_rebind", true)
				return true
		var stored := event.duplicate() as InputEvent
		stored.device = -1
		InputMap.action_erase_events(_waiting_action)
		InputMap.action_add_event(_waiting_action, stored)
		var key_label := stored.as_text().replace(" - Physical", "")
		if is_instance_valid(_binding_button):
			_binding_button.text = str(ACTION_LABELS.get(_waiting_action, _waiting_action)) + " · " + key_label
		A11yUIHelper.say("Bound %s to %s" % [str(ACTION_LABELS.get(_waiting_action, _waiting_action)), key_label], true, 3, &"ui_rebind", true)
		_waiting_action = ""
		_waiting_prev_text = ""
		_binding_button = null
		var g := _game()
		if g and g.has_method("save_settings"):
			g.save_settings()
		return true
	return false


func _input(event: InputEvent) -> void:
	if _waiting_action != "" and capture_binding(event):
		get_viewport().set_input_as_handled()
		return
	if _settings_scroll and _settings_scroll.visible and event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		_close_settings()
		get_viewport().set_input_as_handled()


func _primary_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 52)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("f0a030")
	sb.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_color_override("font_color", Color("0b1020"))
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	return b


func _mode_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(140, 42)
	_style_chip(b)
	return b


func _style_chip(b: Button) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.12, 0.82)
	sb.border_color = Color("f0a030")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_color_override("font_color", Color("f0e6c8"))
	b.add_theme_font_size_override("font_size", 16)


func _on_continue() -> void:
	var g := _game()
	if g and g.has_method("begin_saved"):
		g.begin_saved()


func _on_start() -> void:
	var g := _game()
	if g and g.has_method("begin"):
		g.begin()


func _label(size: int, color: Color, text := "") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l
