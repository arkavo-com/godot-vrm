extends SceneTree
## Loads every GDScript under the given roots and fails on parse errors.
## Usage: godot --headless --path . --script tools/parse_check.gd

const ROOTS := ["res://addons", "res://examples", "res://tests", "res://tools"]


func _initialize() -> void:
	var failures := 0
	var count := 0
	for root in ROOTS:
		for path in _collect(root):
			count += 1
			var script := load(path) as Script
			if script == null or not script.can_instantiate() and not _is_abstract_ok(script):
				printerr("PARSE FAIL: ", path)
				failures += 1
	print("parse_check: %d scripts, %d failures" % [count, failures])
	quit(1 if failures > 0 else 0)


func _is_abstract_ok(script: Script) -> bool:
	# Editor-only scripts cannot instantiate outside the editor but still parse.
	return script.has_source_code() and script.get_instance_base_type() != &""


func _collect(root: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return result
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var path := root.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				result.append_array(_collect(path))
		elif name.ends_with(".gd"):
			result.append(path)
		name = dir.get_next()
	result.sort()
	return result
