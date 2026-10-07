@tool
extends EditorDock
## Probability inspector: enumerates all 36 dice pairs and shows failure,
## costly-success offer, success and strong success with exact fractions.
## Push and Resolve scenarios are shown separately; unavailable toggles are
## disabled rather than assumed.

var _inputs := {}
var _costly: CheckBox
var _push: CheckBox
var _resolve: CheckBox
var _output: RichTextLabel


func setup() -> void:
	name = "FACETS Odds"
	title = "FACETS Odds"
	default_slot = EditorDock.DOCK_SLOT_BOTTOM
	set_meta("facets_ui", "probability")
	var row := HBoxContainer.new()
	var box := VBoxContainer.new()
	box.add_child(row)
	add_child(box)
	for spec in [["facet", 1, 6, 3], ["skill", 0, 4, 2], ["target", 2, 30, 13], ["modifiers", -9, 9, 0]]:
		var label := Label.new()
		label.text = str(spec[0]).capitalize()
		var spin := SpinBox.new()
		spin.min_value = spec[1]
		spin.max_value = spec[2]
		spin.value = spec[3]
		spin.value_changed.connect(func(_value: float) -> void: _refresh())
		_inputs[spec[0]] = spin
		row.add_child(label)
		row.add_child(spin)
	_costly = _toggle(row, "Costly success", true)
	_push = _toggle(row, "Push available", true)
	_resolve = _toggle(row, "Resolve available", true)
	var from_selection := Button.new()
	from_selection.text = "Use inspected action"
	from_selection.pressed.connect(_from_selection)
	row.add_child(from_selection)
	_output = RichTextLabel.new()
	_output.fit_content = true
	_output.custom_minimum_size.y = 160
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_output)
	_refresh()


func _toggle(parent: Control, text: String, pressed: bool) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.button_pressed = pressed
	box.toggled.connect(func(_on: bool) -> void: _refresh())
	parent.add_child(box)
	return box


func _from_selection() -> void:
	var edited := EditorInterface.get_inspector().get_edited_object()
	if edited is FacetsActionResource:
		_inputs["target"].value = edited.target
		_costly.button_pressed = edited.allows_costly_success and not edited.costly_options.is_empty()
		_push.button_pressed = edited.allow_push
		_push.disabled = not edited.allow_push
		_resolve.button_pressed = edited.allow_resolve
		_resolve.disabled = not edited.allow_resolve
	_refresh()


func _refresh() -> void:
	if _output == null:
		return
	var table := FacetsProbabilityTable.build(int(_inputs["facet"].value), int(_inputs["skill"].value), int(_inputs["target"].value), int(_inputs["modifiers"].value), _costly.button_pressed, _push.button_pressed and not _push.disabled, _resolve.button_pressed and not _resolve.disabled)
	_output.text = FacetsProbabilityTable.as_text(table)
