class_name A11yUIHelper
extends RefCounted
## Reusable focus, contrast styling, and NVDA announcement wiring for Godot Control nodes.

static var _queue_focus_target_id := 0
static var _cached_focus_box: StyleBoxFlat


static func speech() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("A11ySpeech")
	return null


static func say(text: String, interrupt := true, priority := 2, category := &"ui", force := false) -> void:
	var s := speech()
	if s and s.has_method("speak"):
		s.speak(text, interrupt, priority, category, force)


static func style_focusable(ctrl: Control) -> void:
	if ctrl == null:
		return
	ctrl.focus_mode = Control.FOCUS_ALL
	if _cached_focus_box == null:
		_cached_focus_box = StyleBoxFlat.new()
		_cached_focus_box.bg_color = Color(0.14, 0.22, 0.30, 0.92)
		_cached_focus_box.border_color = Color("ffd166")
		_cached_focus_box.set_border_width_all(3)
		_cached_focus_box.set_corner_radius_all(6)
	ctrl.add_theme_stylebox_override("focus", _cached_focus_box)


static func _focus_interrupt(ctrl: Control) -> bool:
	if _queue_focus_target_id != 0:
		var matches := ctrl != null and ctrl.get_instance_id() == _queue_focus_target_id
		_queue_focus_target_id = 0
		if matches:
			return false
	return true


static func wire_button(btn: Button, hint := "", label_override := "") -> void:
	style_focusable(btn)
	btn.focus_entered.connect(func() -> void:
		if not is_instance_valid(btn):
			return
		var label_text := label_override if label_override != "" else btn.text
		var msg := "%s, button" % label_text
		if hint != "":
			msg += ", " + hint
		say(msg, _focus_interrupt(btn), 2, &"ui_focus", true)
	)


static func wire_toggle(chk: CheckButton, label_text: String, hint := "") -> void:
	style_focusable(chk)
	chk.focus_entered.connect(func() -> void:
		if not is_instance_valid(chk):
			return
		var state := "checked" if chk.button_pressed else "unchecked"
		var msg := "%s, checkbox, %s" % [label_text, state]
		if hint != "":
			msg += ", " + hint
		say(msg, _focus_interrupt(chk), 2, &"ui_focus", true)
	)
	chk.toggled.connect(func(on: bool) -> void:
		if is_instance_valid(chk):
			say("%s, %s" % [label_text, "checked" if on else "unchecked"], true, 2, &"ui_value", true)
	)


static func wire_option(opt: OptionButton, label_text: String) -> void:
	style_focusable(opt)
	opt.focus_entered.connect(func() -> void:
		if not is_instance_valid(opt):
			return
		var current := opt.get_item_text(opt.selected) if opt.selected >= 0 else "none"
		say("%s, dropdown, %s" % [label_text, current], _focus_interrupt(opt), 2, &"ui_focus", true)
	)
	opt.item_selected.connect(func(index: int) -> void:
		if not is_instance_valid(opt):
			return
		say("%s, selected %s" % [label_text, opt.get_item_text(index)], true, 2, &"ui_value", true)
	)
	var popup := opt.get_popup()
	if popup:
		popup.id_focused.connect(func(id: int) -> void:
			if not is_instance_valid(opt):
				return
			var idx := opt.get_item_index(id)
			if idx >= 0:
				say(opt.get_item_text(idx), true, 2, &"ui_popup", true)
		)


static func wire_slider(slider: HSlider, label_text: String, formatter: Callable = Callable()) -> void:
	style_focusable(slider)
	var format_val := func(val: float) -> String:
		if formatter.is_valid():
			return str(formatter.call(val))
		var pct := int(round((val - slider.min_value) / maxf(slider.max_value - slider.min_value, 0.0001) * 100.0))
		return "%d percent" % pct
	slider.focus_entered.connect(func() -> void:
		if not is_instance_valid(slider):
			return
		say("%s, slider, %s" % [label_text, format_val.call(slider.value)], _focus_interrupt(slider), 2, &"ui_focus", true)
	)
	slider.value_changed.connect(func(val: float) -> void:
		if is_instance_valid(slider) and slider.has_focus():
			say("%s, %s" % [label_text, format_val.call(val)], true, 2, &"ui_value", true)
	)


static func grab_focus_safe(ctrl: Control, queue_callout := true) -> void:
	if ctrl == null or not is_instance_valid(ctrl) or not ctrl.is_inside_tree():
		return
	var do_focus := func() -> void:
		if is_instance_valid(ctrl) and ctrl.is_inside_tree() and ctrl.is_visible_in_tree():
			_queue_focus_target_id = ctrl.get_instance_id() if queue_callout else 0
			ctrl.grab_focus()
	do_focus.call_deferred()


static func release_focus_safe(vp: Viewport) -> void:
	if vp == null:
		return
	_queue_focus_target_id = 0
	var owner := vp.gui_get_focus_owner()
	if owner and is_instance_valid(owner):
		owner.release_focus()


static func action_pressed(event: InputEvent, action: StringName, exact_modifiers := false) -> bool:
	if event == null or not InputMap.has_action(action):
		return false
	if event.is_action_pressed(action, false, exact_modifiers) and not event.is_echo():
		return true
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_NONE and event.keycode != KEY_NONE:
		for bound in InputMap.action_get_events(action):
			if bound is InputEventKey and (bound.physical_keycode == event.keycode or bound.keycode == event.keycode):
				if exact_modifiers:
					if bound.shift_pressed == event.shift_pressed and bound.ctrl_pressed == event.ctrl_pressed and bound.alt_pressed == event.alt_pressed and bound.meta_pressed == event.meta_pressed:
						return true
				elif (not bound.shift_pressed or event.shift_pressed) and (not bound.ctrl_pressed or event.ctrl_pressed) and (not bound.alt_pressed or event.alt_pressed) and (not bound.meta_pressed or event.meta_pressed):
					return true
	return false
