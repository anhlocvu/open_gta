extends Node
## Autoload: NVDA-only speech coordinator with priority queue, deduplication, and speech history.
## Strict screen-reader output via NVDA only (zero SAPI fallback).

const NvdaBridge = preload("res://addons/nvda_integration/NvdaWrapper.gd")

signal spoken(text: String, interrupt: bool, priority: int)

enum Priority { LOW = 0, NORMAL = 1, HIGH = 2, CRITICAL = 3 }

const HISTORY_LIMIT := 30
const DEFAULT_DEDUP_SEC := 1.15
const MAX_QUEUE := 12

var settings := A11ySettings.new()

var _history: Array[String] = []
var _history_cursor := -1
var _queue: Array[Dictionary] = []
var _queue_seq := 0
var _recent: Dictionary = {}
var _busy_until := 0.0
var _last_spoken := ""
var _filter_layer: CanvasLayer
var _filter_rect: ColorRect

var _backend_is_running: Callable
var _backend_speak: Callable
var _backend_cancel: Callable


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reset_backend_to_nvda()
	load_settings()


func reset_backend_to_nvda() -> void:
	_backend_is_running = _default_nvda_is_running
	_backend_speak = _default_nvda_speak
	_backend_cancel = _default_nvda_cancel


func set_mock_backend(is_running_cb: Callable, speak_cb: Callable, cancel_cb: Callable) -> void:
	_backend_is_running = is_running_cb
	_backend_speak = speak_cb
	_backend_cancel = cancel_cb


func is_nvda_available() -> bool:
	return _backend_is_running.is_valid() and bool(_backend_is_running.call())


func load_settings(path := "user://open_world_settings.cfg") -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		settings.load_from_config(cfg)
	apply_screen_filter(settings.screen_filter_mode)


func save_settings(path := "user://open_world_settings.cfg") -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	settings.save_to_config(cfg)
	cfg.save(path)


func speak(text: String, interrupt := true, priority := Priority.NORMAL, category := &"general", force := false) -> bool:
	var clean := _sanitize(text)
	if clean.is_empty():
		return false
	var now := _now_sec()
	if not force:
		var dedup_key := "%s:%s" % [String(category), clean]
		if _recent.has(dedup_key) and now < float(_recent[dedup_key]):
			return false
		_recent[dedup_key] = now + DEFAULT_DEDUP_SEC
		_prune_recent(now)
	_push_history(clean)
	if not settings.speech_enabled:
		return false
	if interrupt or priority >= Priority.HIGH:
		if interrupt:
			_clear_lower_or_all(priority)
		_emit_now(clean, interrupt, priority)
		return true
	if now >= _busy_until and _queue.is_empty():
		_emit_now(clean, false, priority)
		return true
	if _queue.size() >= MAX_QUEUE:
		_queue.pop_front()
	_queue_seq += 1
	_queue.append({"text": clean, "priority": priority, "expires": now + 6.0, "seq": _queue_seq})
	return true


func stop() -> void:
	_queue.clear()
	_busy_until = 0.0
	if is_nvda_available() and _backend_cancel.is_valid():
		_backend_cancel.call()


func clear_history() -> void:
	_history.clear()
	_history_cursor = -1


func get_history() -> Array[String]:
	return _history.duplicate()


func review_previous() -> String:
	if _history.is_empty():
		_speak_review("Speech history is empty.")
		return ""
	if _history_cursor <= 0:
		_history_cursor = 0
	else:
		_history_cursor -= 1
	var entry := _history[_history_cursor]
	_speak_review(entry)
	return entry


func review_next() -> String:
	if _history.is_empty():
		_speak_review("Speech history is empty.")
		return ""
	if _history_cursor < 0:
		_history_cursor = _history.size() - 1
	elif _history_cursor < _history.size() - 1:
		_history_cursor += 1
	var entry := _history[_history_cursor]
	_speak_review(entry)
	return entry


func repeat_last() -> String:
	if _history.is_empty():
		_speak_review("Nothing spoken yet.")
		return ""
	_history_cursor = _history.size() - 1
	var entry := _history[_history_cursor]
	_speak_review(entry)
	return entry


func apply_screen_filter(mode: int) -> void:
	settings.screen_filter_mode = clampi(mode, 0, 4)
	if settings.screen_filter_mode == A11ySettings.FilterMode.OFF:
		if _filter_layer:
			_filter_layer.visible = false
		return
	_ensure_filter_layer()
	if _filter_layer == null or _filter_rect == null:
		return
	var mat := ShaderMaterial.new()
	if settings.screen_filter_mode == A11ySettings.FilterMode.GRAYSCALE:
		var shader := load("res://addons/gato_screen_filters/view/shaders/black_and_white.gdshader") as Shader
		if shader:
			mat.shader = shader
	else:
		var shader := load("res://addons/gato_screen_filters/view/shaders/color_blindness.gdshader") as Shader
		if shader:
			const TYPE_MAP := {
				A11ySettings.FilterMode.PROTANOPIA: 1,
				A11ySettings.FilterMode.DEUTERANOPIA: 3,
				A11ySettings.FilterMode.TRITANOPIA: 5,
			}
			mat.shader = shader
			mat.set_shader_parameter("type", int(TYPE_MAP.get(settings.screen_filter_mode, 0)))
	_filter_rect.material = mat
	_filter_layer.visible = mat.shader != null


func _ensure_filter_layer() -> void:
	if _filter_layer != null:
		return
	_filter_layer = CanvasLayer.new()
	_filter_layer.layer = 128
	_filter_layer.name = "A11yScreenFilter"
	_filter_rect = ColorRect.new()
	_filter_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_filter_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_filter_layer.add_child(_filter_rect)
	add_child(_filter_layer)


func _process(_delta: float) -> void:
	if _queue.is_empty() or not settings.speech_enabled:
		return
	var now := _now_sec()
	if now < _busy_until:
		return
	_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := int(a.priority)
		var pb := int(b.priority)
		if pa != pb:
			return pa > pb
		return int(a.seq) < int(b.seq)
	)
	while not _queue.is_empty():
		var item: Dictionary = _queue.pop_front()
		if float(item.expires) >= now:
			_emit_now(str(item.text), false, int(item.priority))
			return


func _emit_now(clean: String, interrupt: bool, priority: int) -> void:
	_last_spoken = clean
	_busy_until = _now_sec() + clampf(clean.length() * 0.06, 0.55, 4.2)
	if is_nvda_available():
		if interrupt and _backend_cancel.is_valid():
			_backend_cancel.call()
		if _backend_speak.is_valid():
			_backend_speak.call(clean)
	spoken.emit(clean, interrupt, priority)


func _speak_review(clean: String) -> void:
	if clean.is_empty() or not settings.speech_enabled:
		return
	_emit_now(clean, true, Priority.CRITICAL)


func _push_history(clean: String) -> void:
	if not _history.is_empty() and _history[_history.size() - 1] == clean:
		_history_cursor = _history.size() - 1
		return
	_history.append(clean)
	while _history.size() > HISTORY_LIMIT:
		_history.pop_front()
	_history_cursor = _history.size() - 1


func _clear_lower_or_all(priority: int) -> void:
	var kept: Array[Dictionary] = []
	for item in _queue:
		if int(item.priority) > priority:
			kept.append(item)
	_queue = kept


func _prune_recent(now: float) -> void:
	if _recent.size() < 48:
		return
	var keys := _recent.keys()
	for k in keys:
		if float(_recent[k]) <= now:
			_recent.erase(k)


func _sanitize(text: String) -> String:
	return text.strip_edges().replace("\n", ". ").replace("  ", " ")


func _now_sec() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _default_nvda_is_running() -> bool:
	return NvdaBridge.check_nvda_running()


func _default_nvda_speak(clean: String) -> void:
	NvdaBridge.speak_nvda(clean, false)


func _default_nvda_cancel() -> void:
	NvdaBridge.stop_nvda()
