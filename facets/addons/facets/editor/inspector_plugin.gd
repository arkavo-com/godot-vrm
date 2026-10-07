@tool
extends EditorInspectorPlugin
## Adds FACETS authoring panels above the default inspector for characters,
## actions and talents. Panels edit through [FacetsAuthoring], so every
## change is undoable and marks the Resource as changed.

const CharacterPanel := preload("res://addons/facets/editor/character_panel.gd")
const ActionPanel := preload("res://addons/facets/editor/action_panel.gd")
const TalentPanel := preload("res://addons/facets/editor/talent_panel.gd")

var registry: FacetsRegistry
var authoring: FacetsAuthoring


func setup(p_registry: FacetsRegistry, undo: Object) -> void:
	registry = p_registry
	authoring = FacetsAuthoring.make(undo)


func _can_handle(object: Object) -> bool:
	return object is FacetsCharacterResource or object is FacetsActionResource or object is FacetsTalentResource


func _parse_begin(object: Object) -> void:
	var panel: Control
	if object is FacetsCharacterResource:
		panel = CharacterPanel.new()
	elif object is FacetsActionResource:
		panel = ActionPanel.new()
	else:
		panel = TalentPanel.new()
	panel.set_meta("facets_inspector_panel", true)
	panel.call("setup", object, registry, authoring)
	add_custom_control(panel)
