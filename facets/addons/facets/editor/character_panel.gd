@tool
extends VBoxContainer
## Character authoring surface: presets, six facet controls, skill ranks,
## two starting talents, identity fields, bonds, budgets, derived strain
## capacity and validation errors.

var character: FacetsCharacterResource
var registry: FacetsRegistry
var authoring: FacetsAuthoring
var _budget: Label
var _errors: Label
var _facet_spins := {}
var _skill_spins := {}
var _talent_buttons: Array[OptionButton] = []
var _identity_edits := {}
var _refreshing := false


func setup(p_character: FacetsCharacterResource, p_registry: FacetsRegistry, p_authoring: FacetsAuthoring) -> void:
	character = p_character
	registry = p_registry
	authoring = p_authoring
	_build()
	_refresh()
	if not character.changed.is_connected(_refresh):
		character.changed.connect(_refresh)


func _exit_tree() -> void:
	if character != null and character.changed.is_connected(_refresh):
		character.changed.disconnect(_refresh)


func _build() -> void:
	var title := Label.new()
	title.text = "FACETS Character"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	var presets := HBoxContainer.new()
	var preset_button := OptionButton.new()
	preset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for archetype_id in registry.archetype_ids():
		preset_button.add_item(str(registry.get_archetype(archetype_id).get("display_name", archetype_id)))
		preset_button.set_item_metadata(preset_button.item_count - 1, archetype_id)
	var apply := Button.new()
	apply.text = "Apply preset"
	apply.tooltip_text = "Copies the preset's facets, skills and talents into this character (undoable)."
	apply.pressed.connect(func() -> void:
		if preset_button.selected >= 0:
			authoring.apply_preset(character, registry.get_archetype(str(preset_button.get_item_metadata(preset_button.selected)))))
	presets.add_child(preset_button)
	presets.add_child(apply)
	add_child(presets)

	_budget = Label.new()
	_budget.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_budget)

	add_child(_section("Facets"))
	var facets := GridContainer.new()
	facets.columns = 4
	for facet_id in FacetsRules.FACETS:
		var label := Label.new()
		label.text = facet_id.capitalize()
		var spin := SpinBox.new()
		spin.min_value = 1
		spin.max_value = 6
		spin.value_changed.connect(func(value: float) -> void:
			if not _refreshing:
				authoring.set_facet(character, facet_id, int(value)))
		_facet_spins[facet_id] = spin
		facets.add_child(label)
		facets.add_child(spin)
	add_child(facets)

	add_child(_section("Skills"))
	var skills := GridContainer.new()
	skills.columns = 4
	for skill_id in registry.skill_ids():
		var label := Label.new()
		label.text = str(registry.get_skill(skill_id).get("display_name", skill_id))
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = FacetsRules.SKILL_MAX
		spin.value_changed.connect(func(value: float) -> void:
			if not _refreshing:
				authoring.set_skill(character, skill_id, int(value)))
		_skill_spins[skill_id] = spin
		skills.add_child(label)
		skills.add_child(spin)
	add_child(skills)

	add_child(_section("Starting talents"))
	for slot in FacetsRules.STARTING_TALENTS:
		var option := OptionButton.new()
		option.item_selected.connect(func(index: int) -> void:
			if not _refreshing:
				authoring.set_talent(character, slot, str(option.get_item_metadata(index))))
		_talent_buttons.append(option)
		add_child(option)

	add_child(_section("Identity"))
	for field in ["name", "drive", "code", "hindrance", "tell"]:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = field.capitalize()
		label.custom_minimum_size.x = 80
		var edit := LineEdit.new()
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.text_submitted.connect(func(text: String) -> void: authoring.set_identity_field(character, field, text))
		edit.focus_exited.connect(func() -> void:
			var current: Variant = character.identity.get(field) if character.identity != null else ""
			if edit.text != str(current):
				authoring.set_identity_field(character, field, edit.text))
		_identity_edits[field] = edit
		row.add_child(label)
		row.add_child(edit)
		add_child(row)

	var bonds_note := Label.new()
	bonds_note.text = "Bonds: edit trust and affinity (each -2..+2) in the Bonds list below; they never add together."
	bonds_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(bonds_note)

	add_child(_section("Validation"))
	_errors = Label.new()
	_errors.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_errors)


func _section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	return label


func _refresh() -> void:
	if character == null or registry == null:
		return
	_refreshing = true
	var build := character.build()
	for facet_id in _facet_spins:
		_facet_spins[facet_id].set_value_no_signal(build.facet(facet_id))
	for skill_id in _skill_spins:
		_skill_spins[skill_id].set_value_no_signal(build.skill(skill_id))
	var choices := FacetsCharacterSheet.talent_choices(character, registry)
	for slot in _talent_buttons.size():
		var option := _talent_buttons[slot]
		option.clear()
		option.add_item("(none)")
		option.set_item_metadata(0, "")
		var current: String = build.talents[slot] if slot < build.talents.size() else ""
		for choice in choices:
			option.add_item("%s%s" % [choice["name"], "" if choice["eligible"] else "  (not eligible)"])
			var index := option.item_count - 1
			option.set_item_metadata(index, choice["id"])
			option.set_item_tooltip(index, choice["reason"])
			if choice["id"] == current:
				option.select(index)
		if current.is_empty():
			option.select(0)
	for field in _identity_edits:
		var value: Variant = character.identity.get(field) if character.identity != null else ""
		if not _identity_edits[field].has_focus():
			_identity_edits[field].text = str(value)
	var summary := FacetsCharacterSheet.summarize(character, registry)
	_budget.text = FacetsCharacterSheet.budget_text(summary) + ("\nAdvanced build (beyond standard creation)." if summary["advanced"] else "")
	var lines: Array[String] = []
	for error in summary["errors"]:
		lines.append("- %s: %s" % [error["field_path"], error["message"]])
	_errors.text = "No errors." if lines.is_empty() else "\n".join(lines)
	_errors.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5) if lines.is_empty() else Color(1.0, 0.5, 0.45))
	_refreshing = false
