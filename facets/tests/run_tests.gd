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
const REQUIRED_GROUPS_CORE := 30
const REQUIRED_GROUPS_COMBAT := 4


func _initialize() -> void:
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.trim_prefix("--filter=").to_lower()
	var started := Time.get_ticks_msec()
	var passed := 0
	var failed := 0
	var total_assertions := 0
	var groups := {}
	for path in _case_files():
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			print("  FAIL %s :: could not load (parse error)" % path)
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
			var instance: FacetsTestCase = script.new()
			if instance.has_method("before_each"):
				instance.call("before_each")
			instance.call(name)
			if instance.has_method("after_each"):
				instance.call("after_each")
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
