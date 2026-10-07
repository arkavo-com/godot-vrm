@tool
extends EditorDock
## Lists FACETS validation errors by Resource and field. Activating an issue
## opens the Resource and focuses the offending property. Content export is
## refused while errors remain.

var registry: FacetsRegistry
var _tree: Tree
var _status: Label
var _connected := false


func setup(p_registry: FacetsRegistry) -> void:
	registry = p_registry
	name = "FACETS Validation"
	title = "FACETS"
	default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	set_meta("facets_ui", "validation")
	var box := VBoxContainer.new()
	add_child(box)
	var buttons := HBoxContainer.new()
	var rescan := Button.new()
	rescan.text = "Rescan"
	rescan.pressed.connect(refresh)
	var export_button := Button.new()
	export_button.text = "Export content pack"
	export_button.tooltip_text = "Writes res://build/facets_content.json. Blocked while any definition is invalid."
	export_button.pressed.connect(_export)
	buttons.add_child(rescan)
	buttons.add_child(export_button)
	box.add_child(buttons)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_tree = Tree.new()
	_tree.columns = 3
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size.y = 200
	_tree.set_column_title(0, "Resource")
	_tree.set_column_title(1, "Field")
	_tree.set_column_title(2, "Problem")
	_tree.column_titles_visible = true
	_tree.item_activated.connect(_on_activated)
	box.add_child(_tree)


func _enter_tree() -> void:
	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem != null and not _connected:
		filesystem.filesystem_changed.connect(refresh)
		_connected = true
	refresh.call_deferred()


func _exit_tree() -> void:
	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem != null and _connected and filesystem.filesystem_changed.is_connected(refresh):
		filesystem.filesystem_changed.disconnect(refresh)
	_connected = false


func refresh() -> void:
	if _tree == null or registry == null:
		return
	_tree.clear()
	var root := _tree.create_item()
	var issues := FacetsValidationScanner.scan(FacetsValidationScanner.registry_for(), ["res://"])
	for issue in issues:
		var item := _tree.create_item(root)
		item.set_text(0, str(issue["path"]).get_file())
		item.set_tooltip_text(0, str(issue["path"]))
		item.set_text(1, str(issue["field_path"]))
		item.set_text(2, "%s: %s" % [issue["code"], issue["message"]])
		item.set_metadata(0, issue)
	_status.text = "No FACETS validation errors." if issues.is_empty() else "%d FACETS validation error(s). Double-click to open." % issues.size()


func _on_activated() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	var issue: Dictionary = item.get_metadata(0)
	var resource := load(str(issue["path"]))
	if resource == null:
		return
	EditorInterface.edit_resource(resource)
	var target := FacetsValidationScanner.resolve_field(resource, str(issue["field_path"]))
	EditorInterface.inspect_object(target[0], target[1])


func _export() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var reply := FacetsValidationScanner.export_content(FacetsValidationScanner.registry_for(), ["res://examples"], "examples.content", "res://build/facets_content.json")
	_status.text = ("Exported %s." % reply.value) if reply.ok else reply.error.message
