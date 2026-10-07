@tool
extends VBoxContainer
## Talent authoring: pick a registered typed hook and edit its typed
## parameters, usage scope and prerequisites. Arbitrary effect scripts cannot
## be entered.

var talent: FacetsTalentResource
var registry: FacetsRegistry
var authoring: FacetsAuthoring
var _hook: OptionButton
var _info: Label


func setup(p_talent: FacetsTalentResource, p_registry: FacetsRegistry, p_authoring: FacetsAuthoring) -> void:
	talent = p_talent
	registry = p_registry
	authoring = p_authoring
	var title := Label.new()
	title.text = "FACETS Talent"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)
	_hook = OptionButton.new()
	for hook_id in registry.hooks.hook_ids():
		_hook.add_item(hook_id)
	_hook.item_selected.connect(func(index: int) -> void:
		var hook_id := _hook.get_item_text(index)
		if hook_id != talent.hook_id:
			authoring.set_talent_hook(talent, hook_id, registry.hooks))
	add_child(_hook)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_info)
	_refresh()
	if not talent.changed.is_connected(_refresh):
		talent.changed.connect(_refresh)


func _exit_tree() -> void:
	if talent != null and talent.changed.is_connected(_refresh):
		talent.changed.disconnect(_refresh)


func _refresh() -> void:
	for index in _hook.item_count:
		if _hook.get_item_text(index) == talent.hook_id:
			_hook.select(index)
	var description := registry.hooks.describe(talent.hook_id)
	var lines: Array[String] = []
	lines.append(str(description.get("description", "Unknown hook.")))
	lines.append("Parameters: %s" % JSON.stringify(description.get("params", {})))
	for error in FacetsValidationScanner.validate_resource(talent, registry):
		lines.append("- %s: %s" % [error.field_path, error.message])
	_info.text = "\n".join(lines)
