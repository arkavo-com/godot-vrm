extends SceneTree
## Headless FACETS test runner. Uses Godot built-ins only.
##
##   godot --headless --path . --script tests/run_tests.gd
##   godot --headless --path . --script tests/run_tests.gd -- --filter=t08
##
## Exits nonzero when any test fails or a required acceptance group has no
## tests. Each acceptance group (T01..T30, C01..C04) must have at least one
## test method named test_<group>_*.

const CASES_DIR := "res://tests/cases"


## Captures engine and script errors so a runtime error inside a test (which
## GDScript does not propagate to the caller) fails that test.
class ErrorCapture:
	extends Logger
	var errors: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		errors.append("%s:%d in %s: %s %s" % [file, line, function, code, rationale])

	func _log_message(_message: String, _error: bool) -> void:
		pass
const REQUIRED_GROUPS_CORE := 30
const REQUIRED_GROUPS_COMBAT := 4


func _initialize() -> void:
	# Let the root viewport enter the tree so UI smoke tests get _ready().
	await process_frame
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.trim_prefix("--filter=").to_lower()
	var started := Time.get_ticks_msec()
	var passed := 0
	var failed := 0
	var total_assertions := 0
	var groups := {}
	var capture := ErrorCapture.new()
	OS.add_logger(capture)
	for path in _case_files():
		capture.errors.clear()
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate() or not capture.errors.is_empty():
			print("  FAIL %s :: could not load" % path)
			for message in capture.errors:
				print("         - %s" % message)
			failed += 1
			continue
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			var group := name.get_slice("_", 1)
			if not filter.is_empty() and not name.contains(filter) and not path.contains(filter):
				continue
			groups[group] = int(groups.get(group, 0)) + 1
			capture.errors.clear()
			var instance: FacetsTestCase = script.new()
			if instance.has_method("before_each"):
				instance.call("before_each")
			instance.call(name)
			if instance.has_method("after_each"):
				instance.call("after_each")
			for message in capture.errors:
				instance.failures.append("engine/script error: " + message)
			if instance.assertions == 0 and instance.failures.is_empty():
				instance.failures.append("test made no assertions")
			total_assertions += instance.assertions
			if instance.failures.is_empty():
				passed += 1
				print("  ok   %s :: %s (%d)" % [path.get_file().get_basename(), name, instance.assertions])
			else:
				failed += 1
				print("  FAIL %s :: %s" % [path.get_file().get_basename(), name])
				for message in instance.failures:
					print("         - %s" % message)
	var missing: Array[String] = []
	if filter.is_empty():
		for index in range(1, REQUIRED_GROUPS_CORE + 1):
			var group := "t%02d" % index
			if not groups.has(group):
				missing.append(group.to_upper())
		for index in range(1, REQUIRED_GROUPS_COMBAT + 1):
			var group := "c%02d" % index
			if not groups.has(group):
				missing.append(group.to_upper())
	OS.remove_logger(capture)
	var elapsed := Time.get_ticks_msec() - started
	print("")
	print("FACETS tests: %d passed, %d failed, %d assertions, %d groups, %d ms (Godot %s)" % [passed, failed, total_assertions, groups.size(), elapsed, Engine.get_version_info().string])
	if not missing.is_empty():
		print("Missing acceptance groups: %s" % ", ".join(missing))
	quit(1 if failed > 0 or not missing.is_empty() else 0)


func _case_files() -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(CASES_DIR)
	if dir == null:
		return result
	for file in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd"):
			result.append(CASES_DIR.path_join(file))
	result.sort()
	return result
