extends FacetsTestCase
## T26 admission, T27 JSON round trip / migration / limits, T28 shared
## Resource definitions and core independence from the editor plugin.

const W := preload("res://tests/framework/test_world.gd")

var registry: FacetsRegistry


func before_each() -> void:
	registry = FacetsRegistry.core()


func _text(relative: String) -> String:
	return FileAccess.get_file_as_string("res://tests/fixtures/".path_join(relative))


# --- T26 admission ------------------------------------------------------------------------

func test_t26_advanced_character_standard_admission() -> void:
	var character: FacetsPortableCharacter = assert_ok(FacetsCharacterCodec.decode(_text("schemas/character/valid/advanced_import.json"), registry))
	var proposal: FacetsAdmissionProposal = assert_ok(FacetsAdmission.propose(character, registry.policy(), registry))
	assert_eq(FacetsValidator.validate_creation(proposal.build, registry).size(), 0, "legal 18/12/2 build")
	assert_eq(proposal.build.facets, {"force": 4, "agility": 4, "cunning": 4, "empathy": 2, "tenacity": 2, "sense": 2}, "greedy facet allocation")
	assert_eq(proposal.build.skill_total(), 12)
	assert_eq(proposal.build.skill("fighting"), 2)
	assert_eq(proposal.build.skill("athletics"), 2)
	assert_eq(proposal.build.skill("marksmanship"), 2)
	assert_eq(proposal.build.talents.size(), 2)
	assert_eq(proposal.identity, character.identity, "identity retained verbatim")
	var kinds := {}
	for exclusion in proposal.exclusions:
		kinds[exclusion["kind"] + ":" + exclusion["id"]] = true
	assert_true(kinds.has("capability:elsewhere.storm_call"), "local powers excluded")
	assert_true(kinds.has("growth:growth"), "Growth dropped")
	assert_true(kinds.has("equipment:elsewhere.storm_blade"), "unadmitted equipment dropped")
	assert_eq(proposal.memories.size(), 1)
	assert_eq(proposal.memories[0]["status"], "reference", "memories stay source-labeled references")
	assert_eq(proposal.memories[0]["source"], "elsewhere.campaign_7")
	assert_false(proposal.warnings.is_empty(), "explains capped preferences")
	var state := FacetsAdmission.accept(proposal)
	assert_eq(state.growth, 0)
	assert_eq(state.resolve, 1)
	assert_eq(state.known_facts.size(), 0, "no imported memory becomes a local fact")
	assert_eq(state.profile["accomplishments"], ["Hero of Kesh Reef"])


func test_t26_admission_is_deterministic_and_respects_talent_eligibility() -> void:
	var character: FacetsPortableCharacter = assert_ok(FacetsCharacterCodec.decode(_text("schemas/character/valid/advanced_import.json"), registry))
	var first: FacetsAdmissionProposal = assert_ok(FacetsAdmission.propose(character, registry.policy(), registry))
	var second: FacetsAdmissionProposal = assert_ok(FacetsAdmission.propose(character, registry.policy(), registry))
	assert_eq(first.to_dict(), second.to_dict(), "stable proposal")
	# Empathy is admitted at 2, so Steady Voice (Empathy 3) is skipped in favor of the next preference.
	assert_eq(first.build.talents, ["core.trail_reader", "core.bargain_maker"])
	assert_true(first.warnings.any(func(w: String) -> bool: return w.contains("core.steady_voice")))


func test_t26_admitted_actor_joins_session_without_replacing_live_build() -> void:
	var character: FacetsPortableCharacter = assert_ok(FacetsCharacterCodec.decode(_text("schemas/character/valid/advanced_import.json"), registry))
	var proposal: FacetsAdmissionProposal = assert_ok(FacetsAdmission.propose(character, registry.policy(), registry))
	var session := W.session()
	assert_ok(session.add_actor(FacetsAdmission.accept(proposal)))
	assert_eq(session.actor_state("elsewhere.captain_oro").build.facet("force"), 4)
	var clash := FacetsAdmission.accept(proposal)
	clash.actor_id = "mara"
	assert_error(session.add_actor(clash), FacetsError.DUPLICATE, "never silently replaces a live build")
	assert_error(session.add_actor(FacetsAdmission.accept(proposal), FacetsPrincipal.player("p", ["mara"])), FacetsError.NOT_AUTHORIZED, "host acceptance required")


func test_t26_custom_policy_ranges() -> void:
	var character: FacetsPortableCharacter = assert_ok(FacetsCharacterCodec.decode(_text("schemas/character/valid/advanced_import.json"), registry))
	var policy := FacetsAdmissionPolicy.new()
	policy.id = "test.veteran"
	policy.kind = "custom"
	policy.facet_cap = 5
	policy.facet_total = 21
	policy.skill_points = 16
	policy.skill_cap = 3
	policy.allowed_capabilities = ["elsewhere.storm_call"]
	var proposal: FacetsAdmissionProposal = assert_ok(FacetsAdmission.propose(character, policy, registry))
	assert_eq(proposal.build.facet("force"), 5)
	assert_eq(proposal.build.facet_total(), 21)
	assert_eq(proposal.build.skill_total(), 16)
	assert_true(proposal.build.capabilities.has("elsewhere.storm_call"), "policy explicitly admits the power")


# --- T27 JSON -----------------------------------------------------------------------------

func test_t27_round_trip_canonical() -> void:
	var text := _text("schemas/character/valid/mara_vale.json")
	var character: FacetsPortableCharacter = assert_ok(FacetsCharacterCodec.decode(text, registry))
	var encoded := FacetsCharacterCodec.encode(character)
	var again: FacetsPortableCharacter = assert_ok(FacetsCharacterCodec.decode(encoded, registry))
	assert_eq(FacetsCharacterCodec.encode(again), encoded, "stable canonical output")
	assert_eq(JSON.parse_string(encoded), JSON.parse_string(text), "round trip preserves content")
	assert_true(encoded.find("\"character_id\"") < encoded.find("\"identity\""), "sorted keys")
	assert_true(RegEx.create_from_string("\\d\\.0[,}\\]]").search(encoded) == null, "integers stay integers")
	assert_eq(FacetsValidator.validate_creation(character.preferred_build, registry).size(), 0, "Mara's source build is legal")


func test_t27_extensions_round_trip_inert() -> void:
	var character: FacetsPortableCharacter = assert_ok(FacetsCharacterCodec.decode(_text("schemas/character/valid/advanced_import.json"), registry))
	assert_eq(character.extensions["elsewhere.ship"]["hull"], 4)
	var again: FacetsPortableCharacter = assert_ok(FacetsCharacterCodec.decode(FacetsCharacterCodec.encode(character), registry))
	assert_eq(again.extensions, character.extensions)


func test_t27_legacy_alias_migration() -> void:
	var character: FacetsPortableCharacter = assert_ok(FacetsCharacterCodec.decode(_text("schemas/character/valid/legacy_alias.json"), registry))
	assert_eq(character.ruleset_id, "facets.core")
	assert_eq(character.ruleset_version, "0.1.0")
	assert_eq(character.migration_notes.size(), 1)
	assert_false(FacetsCharacterCodec.encode(character).contains("gom.facets.core"), "re-encoded with the current ruleset ID")


func test_t27_invalid_documents() -> void:
	var expectations := {
		"future_schema.json": FacetsError.FUTURE_SCHEMA,
		"live_journey_state.json": FacetsError.UNKNOWN_FIELD,
		"unknown_version.json": FacetsError.UNSUPPORTED_VERSION,
		"fractional_rating.json": FacetsError.INVALID_FIELD,
		"missing_identity_name.json": FacetsError.MISSING_FIELD,
		"unnamespaced_extension.json": FacetsError.INVALID_FIELD,
	}
	for file in expectations:
		assert_error(FacetsCharacterCodec.decode(_text("schemas/character/invalid/" + file), registry), expectations[file], file)
	var cases: Dictionary = fixture("characters/codec_cases.json")
	for case in cases["cases"]:
		assert_error(FacetsCharacterCodec.decode(JSON.stringify(case["document"]), registry), case["expected_error"], case["name"])


func test_t27_malformed_and_oversize_fail_before_objects() -> void:
	assert_error(FacetsCharacterCodec.decode("{\"schema_version\": 1,", registry), FacetsError.MALFORMED)
	assert_error(FacetsCharacterCodec.decode("[1, 2]", registry), FacetsError.MALFORMED)
	var big := "{\"pad\": \"%s\"}" % "x".repeat(1048577)
	assert_error(FacetsCharacterCodec.decode(big, registry), FacetsError.TOO_LARGE, "1 MiB limit")
	var deep := "[".repeat(17) + "]".repeat(17)
	assert_error(FacetsCharacterCodec.decode(deep, registry), FacetsError.TOO_LARGE, "nesting limit")
	var base: Dictionary = JSON.parse_string(_text("schemas/character/valid/mara_vale.json"))
	var wide := base.duplicate(true)
	var skills := {}
	for index in 129:
		skills["genre.skill_%d" % index] = 0
	wide["preferred_build"]["skills"] = skills
	assert_error(FacetsCharacterCodec.decode(JSON.stringify(wide), registry), FacetsError.TOO_LARGE, "128 skills limit")
	var talkative := base.duplicate(true)
	talkative["identity"]["drive"] = "y".repeat(4097)
	assert_error(FacetsCharacterCodec.decode(JSON.stringify(talkative), registry), FacetsError.TOO_LARGE, "4096 character text limit")
	var limits := FacetsImportLimits.standard()
	limits.max_text = 8192
	assert_ok(FacetsCharacterCodec.decode(JSON.stringify(talkative), registry, limits), "trusted host may raise limits")


func test_t27_save_versions() -> void:
	var store := FacetsMemoryStore.new()
	var session := W.session([], store)
	var data := session.to_save_dict()
	var future := data.duplicate(true)
	future["schema_version"] = 2
	assert_error(FacetsSession.from_save_dict(future, W.registry()), FacetsError.FUTURE_SCHEMA)
	var other_pack := data.duplicate(true)
	other_pack["packs"]["facets.core"] = "0.0.9"
	assert_error(FacetsSession.from_save_dict(other_pack, W.registry()), FacetsError.UNSUPPORTED_VERSION, "pinned pack version")
	var legacy := data.duplicate(true)
	legacy.erase("ruleset_id")
	legacy.erase("ruleset_version")
	legacy["ruleset"] = "gom.facets.core@0.1.0"
	assert_ok(FacetsSession.from_save_dict(legacy, W.registry()), "legacy alias save migrates explicitly")


# --- T28 shared definitions ----------------------------------------------------------------

func test_t28_shared_tres_creates_independent_actors() -> void:
	var path := "user://facets_tests/shared_mara.tres"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://facets_tests"))
	var definition := FacetsCharacterResource.from_dict({
		"id": "mara", "display_name": "Mara Vale",
		"identity": {"name": "Mara Vale"},
		"build": W.MARA,
		"bonds": [{"other_id": "npc.guard", "trust": 1, "affinity": 0}],
		"items": {"tool.signal_kit": 1},
	})
	assert_eq(ResourceSaver.save(definition, path), OK)
	var shared := load(path) as FacetsCharacterResource
	var same := load(path) as FacetsCharacterResource
	assert_true(shared == same, "one cached shared definition")
	var first := FacetsActorState.from_character(shared)
	var second := FacetsActorState.from_character(shared)
	first.items["tool.signal_kit"] = 0
	first.bonds["npc.guard"]["trust"] = -2
	first.build.skills["stealth"] = 4
	assert_eq(second.item_count("tool.signal_kit"), 1, "items independent")
	assert_eq(second.bond_value("npc.guard", "trust"), 1, "bonds independent")
	assert_eq(second.build.skill("stealth"), 2, "build independent")
	assert_eq(int(shared.items["tool.signal_kit"]), 1, "definition untouched")
	assert_eq(shared.bonds[0].trust, 1)
	# Two sessions from one definition stay isolated.
	var world_a := FacetsWorldSnapshot.new()
	world_a.add_actor(FacetsActorState.from_character(shared))
	var world_b := FacetsWorldSnapshot.new()
	world_b.add_actor(FacetsActorState.from_character(shared))
	var a: FacetsSession = FacetsSession.create(registry, world_a, {}).value
	var b: FacetsSession = FacetsSession.create(registry, world_b, {}).value
	assert_ok(a.apply_host_effects("mara", [W.eff("actor.strain", {"amount": 3})], "strain"))
	assert_eq(b.actor_state("mara").strain, 0)
	assert_eq(a.actor_state("mara").strain, 3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_t28_registry_copies_resources() -> void:
	var action := FacetsActionResource.from_dict(W.actions()[0])
	action.id = "test.copy"
	var local := W.registry()
	assert_ok(local.add_action_resource(action))
	action.difficulty_kind = "fixed"
	action.target = 3
	assert_eq(int(local.get_action("test.copy")["difficulty"]["target"]), 13, "pinned copy unaffected by later Resource edits")
	var copy := local.get_action("test.copy")
	copy["difficulty"]["target"] = 2
	assert_eq(int(local.get_action("test.copy")["difficulty"]["target"]), 13, "getters return copies")


func test_t28_core_works_without_editor_plugin() -> void:
	assert_false(Engine.is_editor_hint(), "running outside the editor")
	var forbidden := ["EditorInterface", "EditorPlugin", "EditorInspector", "EditorUndoRedoManager", "facets_ai", "facets_combat", "FacetsAi", "FacetsCombat", "FacetsEncounter", "OS.execute", "HTTPRequest"]
	for directory in ["res://addons/facets/core", "res://addons/facets/core/types", "res://addons/facets/io", "res://addons/facets/resources"]:
		for file in DirAccess.get_files_at(directory):
			if not file.ends_with(".gd"):
				continue
			var source := FileAccess.get_file_as_string(directory.path_join(file))
			for word in forbidden:
				assert_false(source.contains(word), "%s references %s" % [file, word])
	var session := W.session([[3, 3]])
	assert_ok(session.preview(W.bypass_request()), "core session runs headless without the plugin")
