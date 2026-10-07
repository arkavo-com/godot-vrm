@tool
extends VBoxContainer
## Action authoring surface: approaches with exact odds against a preset,
## requirements, outcomes and validation on one panel. Operation pickers list
## only allowlisted registry operations; there is no free-form script field.

var action: FacetsActionResource
var registry: FacetsRegistry
var authoring: FacetsAuthoring
var _summary: Label
var _errors: Label
var _preset: OptionButton


func setup(p_action: FacetsActionResource, p_registry: FacetsRegistry, p_authoring: FacetsAuthoring) -> void:
	action = p_action
	registry = p_registry
	authoring = p_authoring
	_build()
	_refresh()
	if not action.changed.is_connected(_refresh):
		action.changed.connect(_refresh)


func _exit_tree() -> void:
	if action != null and action.changed.is_connected(_refresh):
		action.changed.disconnect(_refresh)


func _build() -> void:
	var title := Label.new()
	title.text = "FACETS Action"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)
	var preset_row := HBoxContainer.new()
	var preset_label := Label.new()
	preset_label.text = "Odds for preset:"
	_preset = OptionButton.new()
	for archetype_id in registry.archetype_ids():
		_preset.add_item(str(registry.get_archetype(archetype_id).get("display_name", archetype_id)))
		_preset.set_item_metadata(_preset.item_count - 1, archetype_id)
	_preset.item_selected.connect(func(_index: int) -> void: _refresh())
	preset_row.add_child(preset_label)
	preset_row.add_child(_preset)
	add_child(preset_row)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)
	for property in ["requirements", "success_effects", "failure_effects"]:
		add_child(_op_picker(property))
	_errors = Label.new()
	_errors.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_errors)


func _op_picker(property: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var kind := FacetsOperations.KIND_REQUIREMENT if property == "requirements" else FacetsOperations.KIND_EFFECT
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for op_id in registry.operations.op_ids(kind):
		picker.add_item(op_id)
		picker.set_item_tooltip(picker.item_count - 1, str(registry.operations.describe(op_id).get("description", "")))
	var add := Button.new()
	add.text = "Add to %s" % property.capitalize()
	add.pressed.connect(func() -> void:
		if picker.selected >= 0:
			authoring.add_operation(action, property, picker.get_item_text(picker.selected), registry.operations))
	row.add_child(picker)
	row.add_child(add)
	return row


func _refresh() -> void:
	if action == null:
		return
	var definition := action.to_dict()
	var lines: Array[String] = []
	var difficulty: Dictionary = definition["difficulty"]
	lines.append("Difficulty: %s%s" % [difficulty["kind"], (" %d" % int(difficulty["target"])) if difficulty["kind"] == "fixed" else ""])
	lines.append("Push %s | Resolve %s | Costly success %s | Retry %s" % ["yes" if action.allow_push else "no", "yes" if action.allow_resolve else "no", "offered" if action.allows_costly_success else "none (near miss fails)", action.retry_policy])
	if _preset.selected >= 0 and difficulty["kind"] == "fixed":
		var build := FacetsBuild.from_dict(registry.get_archetype(str(_preset.get_item_metadata(_preset.selected))).get("build", {}))
		for approach in definition["approaches"]:
			var odds := FacetsProbability.enumerate(FacetsCheckInput.make(build.facet(approach["facet"]), build.skill(approach["skill"]), int(difficulty["target"]), action.allows_costly_success and not action.costly_options.is_empty()), FacetsAdjustments.new())
			lines.append("  %s (%s + %s): fail %s, offer %s, success %s, strong %s" % [approach["id"], approach["facet"], approach["skill"], odds.fraction("failure"), odds.fraction("costly_offer"), odds.fraction("success"), odds.fraction("strong_success")])
	lines.append("Requirements: %d | Success effects: %d | Failure effects: %d | Strong benefits: %d" % [action.requirements.size(), action.success_effects.size(), action.failure_effects.size(), action.strong_benefits.size()])
	_summary.text = "\n".join(lines)
	var errors := FacetsValidationScanner.validate_resource(action, registry)
	var messages: Array[String] = []
	for error in errors:
		messages.append("- %s: %s" % [error.field_path, error.message])
	_errors.text = "No errors." if messages.is_empty() else "\n".join(messages)
	_errors.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5) if messages.is_empty() else Color(1.0, 0.5, 0.45))
