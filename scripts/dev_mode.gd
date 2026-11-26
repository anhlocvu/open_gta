class_name DevMode
extends RefCounted
## Validates anhloc.env beside the executable (or editor project root) to gate Dev Mode tools.

const ENV_FILENAME := "anhloc.env"
const _CODE_SALT := "operation-chaos-dev-v1:"
const _CODE_SHA256 := "77f8e50a55a1ad484d8f19c3366c3db0647f1f84e0a0897e1fb1afee640083f6"


static func env_candidate_paths() -> Array[String]:
	var paths: Array[String] = []
	var exe_path := OS.get_executable_path()
	if exe_path != "":
		paths.append(exe_path.get_base_dir().path_join(ENV_FILENAME))
	if OS.has_feature("editor"):
		paths.append(ProjectSettings.globalize_path("res://" + ENV_FILENAME))
	return paths


static func is_unlocked() -> bool:
	for path in env_candidate_paths():
		if verify_env_file(path):
			return true
	return false


static func verify_env_file(path: String) -> bool:
	if path == "" or not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if (_CODE_SALT + line).sha256_text() == _CODE_SHA256:
			return true
		var eq := line.find("=")
		if eq > 0:
			var val := line.substr(eq + 1).strip_edges().trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")
			if (_CODE_SALT + val).sha256_text() == _CODE_SHA256:
				return true
	return false
