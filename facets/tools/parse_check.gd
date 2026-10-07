extends SceneTree
## Loads every GDScript under the given roots and fails on parse or compile
## errors (including errors reported only through the engine log).
## Usage: godot --headless --path . --script tools/parse_check.gd

const ROOTS := ["res://addons", "res://examples", "res://tests", "res://tools"]


class ErrorCapture:
	extends Logger
	var errors: Array[String] = []

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			errors.append("%s:%d %s %s" % [file, line, code, rationale])

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _initialize() -> void:
	var capture := ErrorCapture.new()
	OS.add_logger(capture)
	var failures := 0
	var count := 0
	for root in ROOTS:
		for path in _collect(root):
			count += 1
			capture.errors.clear()
			var script := load(path) as Script
			if script == null or not capture.errors.is_empty():
				printerr("PARSE FAIL: %s %s" % [path, "; ".join(capture.errors)])
				failures += 1
	OS.remove_logger(capture)
	print("parse_check: %d scripts, %d failures" % [count, failures])
	quit(1 if failures > 0 else 0)


func _collect(root: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return result
	for sub in dir.get_directories():
		if not sub.begins_with("."):
			result.append_array(_collect(root.path_join(sub)))
	for file in dir.get_files():
		if file.ends_with(".gd"):
			result.append(root.path_join(file))
	result.sort()
	return result
