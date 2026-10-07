extends FacetsTestCase
## T27 (transport fixtures): the same positive/negative fixtures checked by
## tools/check_schemas.py must be accepted or rejected by the GDScript
## decoders, because schemas alone do not validate gameplay eligibility.

const ROOT := "res://tests/fixtures/schemas"


func _files(kind: String, expectation: String) -> Array[String]:
	var result: Array[String] = []
	for file in DirAccess.get_files_at(ROOT.path_join(kind).path_join(expectation)):
		if file.ends_with(".json"):
			result.append(ROOT.path_join(kind).path_join(expectation).path_join(file))
	result.sort()
	return result


func _load(path: String) -> Variant:
	return FacetsJson.parse(FileAccess.get_file_as_string(path), 8 * 1048576, 64).value


func test_t27_request_fixtures() -> void:
	for path in _files("request", "valid"):
		assert_ok(FacetsActionRequest.validate_dict(_load(path)), path)
	assert_error(FacetsActionRequest.validate_dict(_load(ROOT + "/request/invalid/injected_stat.json")), FacetsError.UNKNOWN_FIELD)
	assert_error(FacetsActionRequest.validate_dict(_load(ROOT + "/request/invalid/missing_approach.json")), FacetsError.MISSING_FIELD)
	var demo: NightMarketDemo = NightMarketDemo.create({"store": FacetsMemoryStore.new(), "dice": []}).value
	var two_helpers: FacetsActionRequest = FacetsActionRequest.validate_dict(_load(ROOT + "/request/invalid/two_helpers.json")).value
	assert_error(demo.session.preview(two_helpers, demo.player), FacetsError.INELIGIBLE, "one helper at most")


func test_t27_proposal_fixtures() -> void:
	var demo: NightMarketDemo = NightMarketDemo.create({"store": FacetsMemoryStore.new(), "dice": []}).value
	for path in _files("proposal", "valid"):
		var proposal: Dictionary = _load(path)
		var observation := FacetsAiViews.observation(demo.session, proposal["actor_id"], FacetsPrincipal.ai("ai", [proposal["actor_id"]]))
		assert_ok(FacetsProposalValidator.validate(JSON.stringify(proposal), observation), path)
	var mara := FacetsAiViews.observation(demo.session, NightMarketDemo.MARA, FacetsPrincipal.ai("ai", [NightMarketDemo.MARA]))
	for path in _files("proposal", "invalid"):
		var reply := FacetsProposalValidator.validate(FileAccess.get_file_as_string(path), mara)
		assert_false(reply.ok, path)


func test_t27_action_fixtures() -> void:
	for path in _files("action", "valid"):
		var registry := FacetsRegistry.core()
		assert_ok(registry.add_action(_load(path)), path)
	for path in _files("action", "invalid"):
		var registry := FacetsRegistry.core()
		var data: Variant = _load(path)
		var reply := registry.add_action(data) if data is Dictionary else FacetsReply.fail(FacetsError.MALFORMED, "")
		assert_false(reply.ok, path)


func test_t27_pack_fixtures() -> void:
	var core := FacetsRegistry.create()
	assert_ok(core.register_pack_dict(_load(ROOT + "/pack/valid/core.json")), "core pack from JSON")
	assert_ok(core.register_pack_dict(_load(ROOT + "/pack/valid/night_market.json")), "demo pack depends on core")
	FacetsCombat.register_hooks(core)
	assert_ok(core.register_pack_dict(_load(ROOT + "/pack/valid/combat.json")), "combat pack")
	assert_error(FacetsRegistry.create().register_pack_dict(_load(ROOT + "/pack/valid/night_market.json")), FacetsError.UNSUPPORTED_VERSION, "missing dependency")
	assert_error(FacetsRegistry.core().register_pack_dict(_load(ROOT + "/pack/invalid/wrong_ruleset_version.json")), FacetsError.UNSUPPORTED_VERSION)
	assert_false(FacetsRegistry.core().register_pack_dict(_load(ROOT + "/pack/invalid/talent_with_script.json")).ok, "talent with script")
	assert_error(FacetsRegistry.core().register_pack_dict(_load(ROOT + "/pack/invalid/condition_bonus.json")), FacetsError.OUT_OF_RANGE)


func test_t27_save_fixtures() -> void:
	var registry := NightMarketDemo.build_registry()
	for path in _files("save", "valid"):
		var session: FacetsSession = assert_ok(FacetsSession.from_save_dict(_load(path), registry), path)
		assert_true(session != null)
	var expectations := {
		"future_schema.json": FacetsError.FUTURE_SCHEMA,
		"wrong_kind.json": FacetsError.MALFORMED,
		"journal_entry_without_ops.json": FacetsError.REPLAY_CORRUPT,
		"impossible_dice.json": FacetsError.OUT_OF_RANGE,
		"resolve_above_cap.json": FacetsError.OUT_OF_RANGE,
		"float_rng_state.json": FacetsError.INVALID_FIELD,
	}
	for file in expectations:
		var text := FileAccess.get_file_as_string(ROOT + "/save/invalid/" + file)
		var parsed := FacetsJson.parse(text, 8 * 1048576, 64)
		var reply := FacetsSession.from_save_dict(parsed.value, registry) if parsed.ok else parsed
		assert_error(reply, expectations[file], file)


func test_t27_event_fixtures() -> void:
	for path in _files("event", "valid"):
		var data: Dictionary = _load(path)
		if data.has("format"):
			continue
		assert_eq(FacetsSaveValidator.validate_record(data, "event").size(), 0, path)
		assert_eq(FacetsResolutionEvent.from_record(data).event_id, data["event_id"])
	for path in _files("event", "invalid"):
		var data: Dictionary = _load(path)
		var errors := FacetsSaveValidator.validate_record(data, "event")
		if path.ends_with("pending_without_decision.json"):
			var save: Dictionary = _load(ROOT + "/save/valid/mara_pending_choice.json")
			save["pending"] = data
			assert_error(FacetsSession.from_save_dict(save, NightMarketDemo.build_registry()), FacetsError.MALFORMED, path)
		else:
			assert_false(errors.is_empty(), path)
