class_name A11ySettings
extends RefCounted
## Persistent accessibility preferences for NVDA speech, audio cues, navigation, and aim assist.

enum Verbosity { MINIMAL = 0, STANDARD = 1, DETAILED = 2 }
enum FilterMode { OFF = 0, GRAYSCALE = 1, PROTANOPIA = 2, DEUTERANOPIA = 3, TRITANOPIA = 4 }

const SECTION := "accessibility"
const SNAP_ANGLES := [15.0, 30.0, 45.0, 90.0]

var speech_enabled := true
var combat_verbosity := Verbosity.STANDARD
var cue_volume := 0.85
var snap_turn_enabled := true
var snap_turn_degrees := 45.0
var keyboard_turn_speed := 2.4
var aim_assist_enabled := true
var acoustic_crosshair_enabled := true
var beacon_enabled := true
var obstacle_cues_enabled := true
var announce_subtitles := true
var screen_filter_mode := FilterMode.OFF


func load_from_config(cfg: ConfigFile) -> void:
	if cfg == null or not cfg.has_section(SECTION):
		return
	speech_enabled = _read_bool(cfg, "speech_enabled", speech_enabled)
	combat_verbosity = clampi(_read_int(cfg, "combat_verbosity", combat_verbosity), 0, 2)
	cue_volume = clampf(_read_float(cfg, "cue_volume", cue_volume), 0.0, 1.0)
	snap_turn_enabled = _read_bool(cfg, "snap_turn_enabled", snap_turn_enabled)
	snap_turn_degrees = clampf(_read_float(cfg, "snap_turn_degrees", snap_turn_degrees), 15.0, 90.0)
	keyboard_turn_speed = clampf(_read_float(cfg, "keyboard_turn_speed", keyboard_turn_speed), 0.8, 5.0)
	aim_assist_enabled = _read_bool(cfg, "aim_assist_enabled", aim_assist_enabled)
	acoustic_crosshair_enabled = _read_bool(cfg, "acoustic_crosshair_enabled", acoustic_crosshair_enabled)
	beacon_enabled = _read_bool(cfg, "beacon_enabled", beacon_enabled)
	obstacle_cues_enabled = _read_bool(cfg, "obstacle_cues_enabled", obstacle_cues_enabled)
	announce_subtitles = _read_bool(cfg, "announce_subtitles", announce_subtitles)
	screen_filter_mode = clampi(_read_int(cfg, "screen_filter_mode", screen_filter_mode), 0, 4)


static func _read_bool(cfg: ConfigFile, key: String, fallback: bool) -> bool:
	var val: Variant = cfg.get_value(SECTION, key, fallback)
	return val if val is bool else fallback


static func _read_int(cfg: ConfigFile, key: String, fallback: int) -> int:
	var val: Variant = cfg.get_value(SECTION, key, fallback)
	if val is int:
		return val
	if val is float:
		return int(val)
	return fallback


static func _read_float(cfg: ConfigFile, key: String, fallback: float) -> float:
	var val: Variant = cfg.get_value(SECTION, key, fallback)
	if val is float or val is int:
		return float(val)
	return fallback


func save_to_config(cfg: ConfigFile) -> void:
	if cfg == null:
		return
	cfg.set_value(SECTION, "speech_enabled", speech_enabled)
	cfg.set_value(SECTION, "combat_verbosity", combat_verbosity)
	cfg.set_value(SECTION, "cue_volume", cue_volume)
	cfg.set_value(SECTION, "snap_turn_enabled", snap_turn_enabled)
	cfg.set_value(SECTION, "snap_turn_degrees", snap_turn_degrees)
	cfg.set_value(SECTION, "keyboard_turn_speed", keyboard_turn_speed)
	cfg.set_value(SECTION, "aim_assist_enabled", aim_assist_enabled)
	cfg.set_value(SECTION, "acoustic_crosshair_enabled", acoustic_crosshair_enabled)
	cfg.set_value(SECTION, "beacon_enabled", beacon_enabled)
	cfg.set_value(SECTION, "obstacle_cues_enabled", obstacle_cues_enabled)
	cfg.set_value(SECTION, "announce_subtitles", announce_subtitles)
	cfg.set_value(SECTION, "screen_filter_mode", screen_filter_mode)


func verbosity_label() -> String:
	match combat_verbosity:
		Verbosity.MINIMAL: return "Minimal"
		Verbosity.DETAILED: return "Detailed"
		_: return "Standard"


func filter_label() -> String:
	match screen_filter_mode:
		FilterMode.GRAYSCALE: return "Grayscale"
		FilterMode.PROTANOPIA: return "Protanopia"
		FilterMode.DEUTERANOPIA: return "Deuteranopia"
		FilterMode.TRITANOPIA: return "Tritanopia"
		_: return "Off"
