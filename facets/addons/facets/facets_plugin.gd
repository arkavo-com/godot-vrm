@tool
extends EditorPlugin
## FACETS editor plugin: registers the authoring inspector, the validation
## dock and the probability dock, and removes all of them on disable.
## Enabling twice never duplicates UI, and no project settings are touched.
## Core runtime code never depends on this plugin.

const InspectorPlugin := preload("res://addons/facets/editor/inspector_plugin.gd")
const ValidationDock := preload("res://addons/facets/editor/validation_dock.gd")
const ProbabilityDock := preload("res://addons/facets/editor/probability_dock.gd")

var _inspector: EditorInspectorPlugin
var _validation_dock: EditorDock
var _probability_dock: EditorDock


func _enter_tree() -> void:
	if _inspector != null:
		return
	var registry := FacetsValidationScanner.registry_for([])
	_inspector = InspectorPlugin.new()
	_inspector.setup(registry, get_undo_redo())
	add_inspector_plugin(_inspector)
	_validation_dock = ValidationDock.new()
	_validation_dock.setup(registry)
	add_dock(_validation_dock)
	_probability_dock = ProbabilityDock.new()
	_probability_dock.setup()
	add_dock(_probability_dock)


func _exit_tree() -> void:
	if _inspector != null:
		remove_inspector_plugin(_inspector)
		_inspector = null
	for dock in [_validation_dock, _probability_dock]:
		if dock != null:
			remove_dock(dock)
			dock.queue_free()
	_validation_dock = null
	_probability_dock = null


func _get_plugin_name() -> String:
	return "FACETS"
