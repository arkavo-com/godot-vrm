@tool
extends EditorPlugin
## Development-only checks that need a real editor (T29):
##   - enable/disable cycles of the FACETS plugin never duplicate docks or
##     inspector panels and leave unrelated project settings untouched;
##   - authoring edits go through EditorUndoRedoManager and undo/redo.
## Runs only when the editor is started with "-- --facets-editor-selftest"
## and quits with a nonzero exit code on failure.

const FLAG := "--facets-editor-selftest"
const PLUGIN := "facets"

var _failures: Array[String] = []
var _checks := 0


func _enter_tree() -> void:
	if OS.get_cmdline_user_args().has(FLAG):
		_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		printerr("  FAIL ", message)
	else:
		print("  ok   ", message)


func _frames(count: int) -> void:
	for index in count:
		await get_tree().process_frame


func _count_meta(node: Node, key: String) -> int:
	var total := 1 if node.has_meta(key) and is_instance_valid(node) and not node.is_queued_for_deletion() else 0
	for child in node.get_children():
		total += _count_meta(child, key)
	return total


func _settings_snapshot() -> Dictionary:
	var snapshot := {}
	for property in ProjectSettings.get_property_list():
		var name: String = property["name"]
		if name.begins_with("editor_plugins/") or not ProjectSettings.has_setting(name):
			continue
		snapshot[name] = var_to_str(ProjectSettings.get_setting(name))
	return snapshot


func _run() -> void:
	print("FACETS editor self-test (Godot %s)" % Engine.get_version_info().string)
	var filesystem := EditorInterface.get_resource_filesystem()
	var waited := 0
	while filesystem.is_scanning() and waited < 600:
		await _frames(1)
		waited += 1
	await _frames(10)
	var base := EditorInterface.get_base_control()
	_check(EditorInterface.is_plugin_enabled(PLUGIN), "FACETS plugin enabled at startup")
	_check(_count_meta(base, "facets_ui") == 2, "two FACETS docks registered (found %d)" % _count_meta(base, "facets_ui"))
	var settings_before := _settings_snapshot()
	for cycle in 3:
		EditorInterface.set_plugin_enabled(PLUGIN, false)
		await _frames(5)
		_check(_count_meta(base, "facets_ui") == 0, "cycle %d: disable removes docks" % cycle)
		EditorInterface.set_plugin_enabled(PLUGIN, true)
		await _frames(5)
		_check(_count_meta(base, "facets_ui") == 2, "cycle %d: enable restores exactly two docks (found %d)" % [cycle, _count_meta(base, "facets_ui")])
	_check(_settings_snapshot() == settings_before, "enable/disable leaves unrelated project settings unchanged")

	# One inspector panel per inspected character after the cycles.
	var character := FacetsCharacterResource.new()
	character.id = "selftest.character"
	character.facet_set = FacetsFacetSet.new()
	character.identity = FacetsIdentityResource.new()
	EditorInterface.inspect_object(character)
	await _frames(5)
	var inspector := EditorInterface.get_inspector()
	_check(_count_meta(inspector, "facets_inspector_panel") == 1, "exactly one FACETS inspector panel (found %d)" % _count_meta(inspector, "facets_inspector_panel"))

	# Undo/redo through the editor's undo manager.
	var undo_redo := EditorInterface.get_editor_undo_redo()
	var authoring := FacetsAuthoring.make(undo_redo)
	authoring.set_facet(character, "agility", 4)
	_check(character.facet_set.agility == 4, "authoring edit applied")
	var history := undo_redo.get_history_undo_redo(undo_redo.get_object_history_id(character))
	history.undo()
	_check(character.facet_set.agility == 2, "undo restores the facet")
	history.redo()
	_check(character.facet_set.agility == 4, "redo reapplies the facet")
	authoring.set_skill(character, "stealth", 2)
	history.undo()
	_check(character.skills.get("stealth", 0) == 0, "skill edit undone")
	EditorInterface.inspect_object(null)
	await _frames(2)

	var code := 0 if _failures.is_empty() else 1
	print("FACETS editor self-test: %d checks, %d failures" % [_checks, _failures.size()])
	get_tree().quit(code)
