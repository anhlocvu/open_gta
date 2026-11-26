class_name SaveManager
extends RefCounted
## Atomic, versioned JSON Save/Load manager with rolling .bak recovery in user://.

const DEFAULT_PATH := "user://open_world_save.json"
const SCHEMA_VERSION := 1


static func _is_safe_user_path(path: String) -> bool:
	if not path.begins_with("user://"):
		return false
	if path.contains("..") or path.contains("\\"):
		return false
	return path.get_file() != ""


static func has_save(path := DEFAULT_PATH) -> bool:
	return not peek_summary(path).is_empty()


static func save_data(data: Dictionary, path := DEFAULT_PATH) -> bool:
	if data.is_empty() or not _is_safe_user_path(path) or not (data.get("player") is Dictionary):
		return false
	var payload := data.duplicate(true)
	payload["version"] = SCHEMA_VERSION
	payload["saved_unix"] = int(Time.get_unix_time_from_system())
	payload["saved_text"] = Time.get_datetime_string_from_system(false, true)
	var json_text := JSON.stringify(payload, "\t")
	var tmp_path := path + ".tmp"
	var abs_path := ProjectSettings.globalize_path(path)
	var abs_bak := ProjectSettings.globalize_path(path + ".bak")
	var abs_tmp := ProjectSettings.globalize_path(tmp_path)
	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(abs_tmp)
	var tmp_file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if tmp_file == null:
		return false
	tmp_file.store_string(json_text)
	var write_err := tmp_file.get_error()
	tmp_file.close()
	if write_err != OK or _read_json_dict(tmp_path).is_empty():
		if FileAccess.file_exists(tmp_path):
			DirAccess.remove_absolute(abs_tmp)
		return false
	if FileAccess.file_exists(path) and not _read_json_dict(path).is_empty():
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.remove_absolute(abs_bak)
		var copy_err := DirAccess.copy_absolute(abs_path, abs_bak)
		if copy_err != OK:
			DirAccess.remove_absolute(abs_tmp)
			return false
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(abs_path)
	var rename_err := DirAccess.rename_absolute(abs_tmp, abs_path)
	if rename_err != OK:
		var fallback_err := DirAccess.copy_absolute(abs_tmp, abs_path)
		if FileAccess.file_exists(tmp_path):
			DirAccess.remove_absolute(abs_tmp)
		if fallback_err != OK or _read_json_dict(path).is_empty():
			return false
	return true


static func load_data(path := DEFAULT_PATH) -> Dictionary:
	if not _is_safe_user_path(path):
		return {}
	var primary := _read_json_dict(path)
	if not primary.is_empty():
		return primary
	return _read_json_dict(path + ".bak")


static func peek_summary(path := DEFAULT_PATH) -> Dictionary:
	var data := load_data(path)
	if data.is_empty():
		return {}
	var raw_money: Variant = data.get("money", 420)
	var raw_phase: Variant = data.get("phase", 1)
	var raw_pkg: Variant = data.get("packages_left", 3)
	return {
		"version": SCHEMA_VERSION,
		"money": maxi(int(raw_money) if (raw_money is int or raw_money is float) else 420, 0),
		"phase": clampi(int(raw_phase) if (raw_phase is int or raw_phase is float) else 1, 1, 4),
		"packages_left": maxi(int(raw_pkg) if (raw_pkg is int or raw_pkg is float) else 3, 0),
		"saved_text": str(data.get("saved_text", "")),
	}


static func _read_json_dict(path: String) -> Dictionary:
	if not _is_safe_user_path(path) or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var raw := file.get_as_text()
	file.close()
	if raw.strip_edges().is_empty():
		return {}
	var json := JSON.new()
	if json.parse(raw) != OK:
		return {}
	var parsed: Variant = json.data
	if not (parsed is Dictionary):
		return {}
	var dict := parsed as Dictionary
	var ver: Variant = dict.get("version")
	if not (ver is int or ver is float) or int(ver) != SCHEMA_VERSION:
		return {}
	if not (dict.get("player") is Dictionary):
		return {}
	return dict


static func safe_float(val: Variant, fallback: float, min_v: float, max_v: float) -> float:
	if val is int or val is float:
		var f := float(val)
		if is_finite(f):
			return clampf(f, min_v, max_v)
	return fallback


static func safe_int(val: Variant, fallback: int, min_v: int, max_v: int) -> int:
	if val is int or val is float:
		var f := float(val)
		if is_finite(f):
			return clampi(int(f), min_v, max_v)
	return fallback


static func safe_str(val: Variant, fallback := "") -> String:
	return val if val is String else fallback


static func safe_angle(val: Variant, fallback: float) -> float:
	if val is int or val is float:
		var f := float(val)
		if is_finite(f):
			return wrapf(f, -PI, PI)
	return fallback


static func vec3_to_array(v: Vector3) -> Array[float]:
	return [v.x, v.y, v.z]


static func array_to_vec3(val: Variant, fallback := Vector3.ZERO) -> Vector3:
	if val is Array and val.size() >= 3:
		var a: Array = val
		if (a[0] is int or a[0] is float) and (a[1] is int or a[1] is float) and (a[2] is int or a[2] is float):
			var fx := float(a[0])
			var fy := float(a[1])
			var fz := float(a[2])
			if is_finite(fx) and is_finite(fy) and is_finite(fz):
				return Vector3(fx, fy, fz)
	return fallback
