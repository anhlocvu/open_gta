extends Node

## Strict NVDA-only speech wrapper via ClassDB NVDA static API (no SAPI / DisplayServer.tts fallback).

const _RUNNING_CACHE_MSEC := 350

static var _bridge: GDScript
static var _bridge_checked := false
static var _cached_running := false
static var _cache_expires_msec := -1


static func has_nvda_extension() -> bool:
	return ClassDB.class_exists(&"NVDA")


static func _get_bridge() -> GDScript:
	if _bridge_checked:
		return _bridge
	_bridge_checked = true
	if not ClassDB.class_exists(&"NVDA"):
		return null
	var script := GDScript.new()
	script.source_code = """extends RefCounted
static func is_running() -> bool:
	return bool(NVDA.is_running())
static func speak(text: String) -> void:
	NVDA.speak_text(text)
static func cancel() -> void:
	NVDA.cancel()
"""
	if script.reload() == OK:
		_bridge = script
	return _bridge


static func check_nvda_running(force_refresh := false) -> bool:
	var bridge := _get_bridge()
	if bridge == null:
		return false
	var now := Time.get_ticks_msec()
	if not force_refresh and _cache_expires_msec >= 0 and now < _cache_expires_msec:
		return _cached_running
	_cached_running = bool(bridge.is_running())
	_cache_expires_msec = now + _RUNNING_CACHE_MSEC
	return _cached_running


static func speak_nvda(text: String, interrupt := true) -> bool:
	if text.is_empty() or not check_nvda_running():
		return false
	var bridge := _get_bridge()
	if bridge == null:
		return false
	if interrupt:
		bridge.cancel()
	bridge.speak(text)
	return true


static func stop_nvda() -> void:
	if not check_nvda_running():
		return
	var bridge := _get_bridge()
	if bridge != null:
		bridge.cancel()


# Say something in NVDA, without falling back to TTS/SAPI.
func say_nvda(text: String) -> void:
	speak_nvda(text, true)


# Say something via NVDA only (never falls back to SAPI).
func say(text: String, interrupt := true) -> void:
	speak_nvda(text, interrupt)


# Stop speaking. Right. Now.
func stop() -> void:
	stop_nvda()


func is_using_nvda() -> bool:
	return check_nvda_running()
