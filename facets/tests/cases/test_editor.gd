extends FacetsTestCase
## T29 (headless part): authoring undo/redo, creation budgets, exact
## probability fixture, validation scanning and export blocking. Plugin
## enable/disable cycles and the editor's own undo manager are covered by
## tools/run_editor_selftest.sh, which needs a real editor.

var registry: FacetsRegistry


func before_each() -> void:
	registry = FacetsRegistry.core()


func _character() -> FacetsCharacterResource:
	var character := FacetsCharacterResource.new()
	character.id = "test.author"
	character.facet_set = FacetsFacetSet.new()
	character.identity = FacetsIdentityResource.new()
	character.identity.name = "Author"
	return character


func test_t29_undo_redo_for_every_mutation() -> void:
	var undo := UndoRedo.new()
	var authoring := FacetsAuthoring.make(undo)
	var character := _character()
	authoring.set_facet(character, "agility", 4)
	authoring.set_skill(character, "stealth", 2)
	authoring.set_talent(character, 0, "core.second_look")
	authoring.set_identity_field(character, "drive", "Find them")
	assert_eq(character.facet_set.agility, 4)
	assert_eq(int(character.skills["stealth"]), 2)
	assert_eq(character.talents, ["core.second_look"])
	assert_eq(character.identity.drive, "Find them")
	undo.undo()
	assert_eq(character.identity.drive, "")
	undo.undo()
	assert_eq(character.talents.size(), 0)
	undo.undo()
	assert_false(character.skills.has("stealth"))
	undo.undo()
	assert_eq(character.facet_set.agility, 2)
	undo.redo()
	undo.redo()
	assert_eq(character.facet_set.agility, 4)
	assert_eq(int(character.skills["stealth"]), 2)
	undo.free()


func test_t29_preset_copies_values_and_is_undoable() -> void:
	var undo := UndoRedo.new()
	var authoring := FacetsAuthoring.make(undo)
	var character := _character()
	var archetype := registry.get_archetype("core.archetype.courier")
	var changes := [0]
	character.changed.connect(func() -> void: changes[0] += 1)
	authoring.apply_preset(character, archetype)
	assert_true(changes[0] > 0, "Resource marked changed for saving")
	assert_eq(character.build().to_dict(), FacetsBuild.from_dict(archetype["build"]).to_dict())
	assert_eq(FacetsValidator.validate_character(character, registry).size(), 0, "preset is a legal starting build")
	character.skills["stealth"] = 0
	assert_eq(int(registry.get_archetype("core.archetype.courier")["build"]["skills"]["stealth"]), 2, "preset itself untouched")
	undo.undo()
	assert_eq(character.facet_set.agility, 2)
	undo.free()


func test_t29_shared_facet_set_is_copied_on_write() -> void:
	var path := "user://facets_tests/shared_facets.tres"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://facets_tests"))
	assert_eq(ResourceSaver.save(FacetsFacetSet.new(), path), OK)
	var shared := load(path) as FacetsFacetSet
	var one := _character()
	var two := _character()
	one.facet_set = shared
	two.facet_set = shared
	var undo := UndoRedo.new()
	FacetsAuthoring.make(undo).set_facet(one, "sense", 4)
	assert_eq(one.facet_set.sense, 4)
	assert_eq(two.facet_set.sense, 2, "other character's shared definition untouched")
	assert_eq(shared.sense, 2)
	undo.undo()
	assert_true(one.facet_set == shared, "undo restores the original reference")
	undo.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_t29_budgets_and_capacity() -> void:
	var character := _character()
	var summary := FacetsCharacterSheet.summarize(character, registry)
	assert_eq(summary["facet_points_used"], 0)
	assert_eq(summary["strain_capacity"], 6)
	assert_false(summary["errors"].is_empty(), "empty character is not legal")
	var undo := UndoRedo.new()
	FacetsAuthoring.make(undo).apply_preset(character, registry.get_archetype("core.archetype.mediator"))
	summary = FacetsCharacterSheet.summarize(character, registry)
	assert_eq(summary["facet_points_used"], 6)
	assert_eq(summary["skill_points_used"], 12)
	assert_eq(summary["strain_capacity"], 7, "4 + tenacity 3")
	assert_eq(summary["errors"].size(), 0)
	assert_true(FacetsCharacterSheet.budget_text(summary).contains("Facets 6/6"))
	character.facet_set.force = 5
	summary = FacetsCharacterSheet.summarize(character, registry)
	assert_true(summary["advanced"])
	assert_true(summary["errors"].any(func(e: Dictionary) -> bool: return e["field_path"] == "facet_set.force"), "error points at the facet field")
	var choices := FacetsCharacterSheet.talent_choices(character, registry)
	assert_eq(choices.size(), 6)
	undo.free()


func test_t29_probability_inspector_exact_fixture() -> void:
	var table := FacetsProbabilityTable.build(5, 3, 14, 0, true, false, false)
	var rows: Array = table["scenarios"][0]["rows"]
	assert_eq(rows.map(func(r: Dictionary) -> String: return r["label"]), ["Failure", "Costly-success offer", "Success", "Strong success"])
	assert_eq(rows.map(func(r: Dictionary) -> String: return r["fraction"]), ["3/36", "7/36", "20/36", "6/36"])
	assert_eq(rows.map(func(r: Dictionary) -> String: return r["percent"]), ["8.33%", "19.44%", "55.56%", "16.67%"])
	assert_true(table["notes"][0].begins_with("Advanced build"), "labelled advanced")
	var merged := FacetsProbabilityTable.build(5, 3, 14, 0, false, false, false)
	var merged_rows: Array = merged["scenarios"][0]["rows"]
	assert_eq(merged_rows.size(), 3, "offer band merged into failure")
	assert_eq(merged_rows[0]["fraction"], "10/36")
	assert_eq(merged_rows[0]["percent"], "27.78%")
	var scenarios: Array = FacetsProbabilityTable.build(3, 2, 13, 0, true, true, true)["scenarios"]
	assert_eq(scenarios.map(func(s: Dictionary) -> String: return s["scenario"]), ["base", "push", "resolve", "push+resolve"], "fixed scenarios shown separately")
	var disabled: Array = FacetsProbabilityTable.build(3, 2, 13, 0, true, false, false)["scenarios"]
	assert_eq(disabled.size(), 1, "impossible toggles omitted")


func test_t29_scanner_reports_fields_and_blocks_export() -> void:
	var root := "user://facets_tests/scan"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	var bad := _character()
	bad.id = "test.bad"
	bad.facet_set.force = 6
	assert_eq(ResourceSaver.save(bad, root.path_join("bad_character.tres")), OK)
	var action := FacetsActionResource.from_dict(preload("res://tests/framework/test_world.gd").actions()[0])
	action.success_effects.append(FacetsOperationRef.make("actor.set_facet", {"facet": "force"}))
	assert_eq(ResourceSaver.save(action, root.path_join("bad_action.tres")), OK)
	var issues := FacetsValidationScanner.scan(registry, [root])
	assert_true(issues.any(func(i: Dictionary) -> bool: return i["path"].ends_with("bad_character.tres") and i["field_path"] == "facet_set.force"), "character field reported")
	assert_true(issues.any(func(i: Dictionary) -> bool: return i["path"].ends_with("bad_action.tres") and i["code"] == FacetsError.UNKNOWN_OPERATION), "unknown operation reported")
	var target := FacetsValidationScanner.resolve_field(load(root.path_join("bad_character.tres")), "facet_set.force")
	assert_true(target[0] is FacetsFacetSet and target[1] == "force", "navigates to the sub-resource field")
	var export_path := ProjectSettings.globalize_path(root.path_join("out.json"))
	assert_error(FacetsValidationScanner.export_content(registry, [root], "test.pack", export_path), FacetsError.INELIGIBLE, "export blocked")
	assert_false(FileAccess.file_exists(export_path))
	for file in DirAccess.get_files_at(root):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(root.path_join(file)))
	var good := FacetsActionResource.from_dict(preload("res://tests/framework/test_world.gd").actions()[0])
	assert_eq(ResourceSaver.save(good, root.path_join("good_action.tres")), OK)
	assert_ok(FacetsValidationScanner.export_content(registry, [root], "test.pack", export_path), "valid content exports")
	assert_true(FileAccess.get_file_as_string(export_path).contains("test.bypass"))
	for file in DirAccess.get_files_at(root):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(root.path_join(file)))


func test_t29_operation_pickers_are_registry_backed() -> void:
	var undo := UndoRedo.new()
	var authoring := FacetsAuthoring.make(undo)
	var action := FacetsActionResource.new()
	assert_false(authoring.add_operation(action, "success_effects", "os.execute", registry.operations), "unknown operation refused")
	assert_true(authoring.add_operation(action, "success_effects", "object.set_flag", registry.operations))
	assert_eq(action.success_effects[0].op, "object.set_flag")
	assert_eq(action.success_effects[0].params.keys().size(), 3, "parameter template from schema")
	var talent := FacetsTalentResource.new()
	assert_false(authoring.set_talent_hook(talent, "run_script", registry.hooks), "no free-form hooks")
	assert_true(authoring.set_talent_hook(talent, "trail_reader", registry.hooks))
	assert_true(talent.parameters.has("skills"))
	undo.undo()
	assert_eq(talent.hook_id, "")
	undo.free()


func test_t29_project_content_validates() -> void:
	var project_registry := FacetsValidationScanner.registry_for(["res://addons", "res://examples"])
	var issues := FacetsValidationScanner.scan(project_registry, ["res://addons", "res://examples"])
	assert_eq(issues, [], "shipped content has no validation errors")
