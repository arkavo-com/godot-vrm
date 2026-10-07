extends FacetsTestCase
## T13: each noncombat talent triggers only under its prerequisites and
## usage limit.

const W := preload("res://tests/framework/test_world.gd")


func _add_archetype(session: FacetsSession, actor_id: String, archetype_id: String) -> void:
	var build := FacetsBuild.from_dict(session.registry.get_archetype(archetype_id)["build"])
	var state := W.actor(actor_id, actor_id.capitalize(), build.to_dict())
	assert_ok(session.add_actor(state), "add %s" % actor_id)


func _resolve_all(session: FacetsSession, event: FacetsResolutionEvent, picks: Dictionary, prefix: String) -> FacetsResolutionEvent:
	var step := 0
	while event != null and event.is_pending():
		step += 1
		var decision := event.pending_decision
		var option: String = picks.get(decision.kind, decision.option_ids()[decision.option_ids().size() - 1])
		event = assert_ok(session.choose(event.event_id, decision.decision_id, option, "%s-%d" % [prefix, step]))
	return event


func _attempt(session: FacetsSession, request: FacetsActionRequest, request_id: String, picks: Dictionary = {}) -> FacetsResolutionEvent:
	var preview: FacetsCheckPreview = assert_ok(session.preview(request), "preview %s" % request_id)
	if preview == null:
		return null
	var event: FacetsResolutionEvent = assert_ok(session.commit(preview.token, {}, request_id))
	return _resolve_all(session, event, picks, request_id)


# --- Second Look -----------------------------------------------------------------------

func test_t13_second_look_needs_lock_evidence_and_interval() -> void:
	var session := W.session([[1, 1], [6, 6], [6, 6]])
	var search := FacetsActionRequest.make("mara", "test.search", "look")
	assert_error(session.preview(FacetsActionRequest.make("mara", "test.search", "look").with_talents(["core.second_look"], "evidence.bag_seal")), FacetsError.NOT_APPLICABLE, "no prior failure")
	var failed := _attempt(session, search, "s1", {"resolve": "decline"})
	assert_eq(failed.final_band, "failure")
	assert_error(session.preview(FacetsActionRequest.make("mara", "test.search", "look")), FacetsError.RETRY_LOCKED, "unchanged retry locked")
	assert_error(session.preview(FacetsActionRequest.make("mara", "test.search", "look").with_talents(["core.second_look"], "evidence.rumor")), FacetsError.NOT_APPLICABLE, "needs an authored alternate source")
	assert_error(session.preview(FacetsActionRequest.make("iris", "test.search", "look").with_talents(["core.second_look"], "evidence.bag_seal")), FacetsError.NOT_APPLICABLE, "Iris lacks Second Look")
	var clock_before := session.snapshot().clock
	var draws_before := session.dice_source().draws
	var second := _attempt(session, FacetsActionRequest.make("mara", "test.search", "look").with_talents(["core.second_look"], "evidence.bag_seal"), "s2")
	assert_eq(session.dice_source().draws, draws_before + 1, "a real new attempt draws dice")
	assert_eq(session.snapshot().clock, clock_before + 1, "extra interval spent")
	assert_true(FacetsRules.is_success_band(second.final_band))
	assert_true(session.actor_state("mara").knows("fact.lead"))
	# Fail again with fresh dice later in the scene: usage is exhausted.
	assert_eq(session.actor_state("mara").usage.get(FacetsTalents.usage_key("core.second_look", "scene.market")), 1)


func test_t13_second_look_once_per_scene_and_evidence_once() -> void:
	var session := W.session([[1, 1], [1, 1], [1, 1], [1, 1]])
	_attempt(session, FacetsActionRequest.make("mara", "test.search", "look"), "a1", {"resolve": "decline"})
	var retry := _attempt(session, FacetsActionRequest.make("mara", "test.search", "look").with_talents(["core.second_look"], "evidence.bag_seal"), "a2", {"resolve": "decline"})
	assert_eq(retry.final_band, "failure")
	assert_error(session.preview(FacetsActionRequest.make("mara", "test.search", "look").with_talents(["core.second_look"], "evidence.cctv")), FacetsError.USAGE_LIMIT, "once per scene")
	assert_ok(session.start_scene("scene.next"))
	assert_error(session.preview(FacetsActionRequest.make("mara", "test.search", "look").with_talents(["core.second_look"], "evidence.bag_seal")), FacetsError.ALREADY_USED, "same evidence is not a new look")
	assert_ok(session.preview(FacetsActionRequest.make("mara", "test.search", "look").with_talents(["core.second_look"], "evidence.cctv")), "new scene, new evidence")


# --- Quiet Hands -----------------------------------------------------------------------

func test_t13_quiet_hands_replaces_strong_benefit_once_per_scene() -> void:
	var session := W.session([[6, 6], [6, 6], [2, 2]])
	_add_archetype(session, "tink", "core.archetype.tinkerer")
	var first: FacetsResolutionEvent = assert_ok(session.commit((session.preview(FacetsActionRequest.make("tink", "test.sneak", "quiet")).value as FacetsCheckPreview).token, {}, "q1"))
	assert_eq(first.pending_decision.kind, "benefit", "quiet option makes the choice explicit")
	assert_true(first.pending_decision.option_ids().has("quiet_hands.no_trace"))
	var final: FacetsResolutionEvent = assert_ok(session.choose(first.event_id, first.pending_decision.decision_id, "quiet_hands.no_trace", "q2"))
	var tink := session.actor_state("tink")
	assert_eq(tink.flags.get("left_no_trace"), true)
	assert_false(tink.flags.has("unseen"), "replaces, does not add to, the strong benefit")
	assert_true(final.is_final())
	var second := _attempt(session, FacetsActionRequest.make("tink", "test.sneak", "quiet"), "q3")
	assert_true(second.is_final(), "only the normal benefit remains: auto-selected")
	assert_eq(session.actor_state("tink").flags.get("unseen"), true)
	var plain := _attempt(session, FacetsActionRequest.make("tink", "test.sneak", "quiet"), "q4", {"resolve": "decline"})
	assert_ne(plain.final_band, "strong_success")
	var mara_preview: FacetsCheckPreview = assert_ok(session.preview(FacetsActionRequest.make("mara", "test.sneak", "quiet")))
	assert_false(mara_preview.benefit_options.any(func(o: Dictionary) -> bool: return str(o["id"]).begins_with("quiet")), "Mara lacks Quiet Hands")


# --- Field Engineer ---------------------------------------------------------------------

func test_t13_field_engineer_substitutes_consumable_and_expires() -> void:
	var session := W.session([[5, 5], [5, 5]])
	assert_ok(session.apply_host_effects("mara", [W.eff("actor.item_add", {"item_id": "tool.signal_kit", "amount": -1})], "lose kit"))
	assert_error(session.preview(FacetsActionRequest.make("mara", "test.bypass", "tech")), FacetsError.INELIGIBLE, "no tool and no substitute declared")
	var request := FacetsActionRequest.make("mara", "test.bypass", "tech").with_tools(["item.scrap_wire"])
	var event := _attempt(session, request, "f1", {"resolve": "decline"})
	assert_eq(event.final_band, "success")
	assert_eq(session.actor_state("mara").item_count("item.scrap_wire"), 1, "consumable used")
	assert_eq(session.snapshot().object_flag("door", "open"), true)
	assert_eq(session.snapshot().expiring.size(), 1, "repair marked to expire")
	assert_ok(session.apply_host_effects("mara", [W.eff("object.set_flag", {"object_id": "door", "key": "open", "value": false})], "close"))
	assert_error(session.preview(request), FacetsError.INELIGIBLE, "once per scene")
	assert_ok(session.start_scene("scene.next"))
	assert_eq(session.snapshot().object_flag("door", "open"), false, "repair expired at scene end")
	assert_eq(session.snapshot().expiring.size(), 0)
	var iris_request := FacetsActionRequest.make("iris", "test.bypass", "tech")
	assert_ok(session.apply_host_effects("iris", [W.eff("actor.item_add", {"item_id": "item.scrap_wire", "amount": 1})], "give wire"))
	iris_request.with_tools(["item.scrap_wire"])
	assert_error(session.preview(iris_request), FacetsError.INELIGIBLE, "Iris lacks Field Engineer")


func test_t13_field_engineer_expiry_restores_previous_value() -> void:
	var session := W.session([[5, 5]])
	assert_ok(session.apply_host_effects("mara", [W.eff("actor.item_add", {"item_id": "tool.signal_kit", "amount": -1})], "lose kit"))
	_attempt(session, FacetsActionRequest.make("mara", "test.bypass", "tech").with_tools(["item.scrap_wire"]), "f1", {"resolve": "decline"})
	assert_ok(session.end_scene())
	assert_eq(session.snapshot().object_flag("door", "open"), false)


# --- Steady Voice --------------------------------------------------------------------------

func test_t13_steady_voice_after_fear_setback_once_per_scene() -> void:
	var session := W.session([[1, 1]])
	assert_error(session.use_steady_voice("iris", "mara"), FacetsError.NOT_APPLICABLE, "no fear setback yet")
	var scared := _attempt(session, FacetsActionRequest.make("mara", "test.scare", "brave"), "fear")
	assert_eq(scared.final_band, "failure")
	assert_eq(session.actor_state("mara").strain, 2)
	assert_error(session.use_steady_voice("mara", "iris"), FacetsError.NOT_APPLICABLE, "Mara lacks Steady Voice")
	assert_ok(session.apply_host_effects("mara", [W.eff("actor.flag", {"key": "unwilling", "value": true})], "sulk"))
	assert_error(session.use_steady_voice("iris", "mara"), FacetsError.INELIGIBLE, "ally must be willing")
	assert_ok(session.apply_host_effects("mara", [W.eff("actor.flag", {"key": "unwilling", "value": false})], "listen"))
	var event: FacetsResolutionEvent = assert_ok(session.use_steady_voice("iris", "mara"))
	assert_eq(int(event.record["resource_deltas"]["ally_strain"]), -2)
	assert_true(bool(event.record["consumes_action"]))
	assert_eq(session.actor_state("mara").strain, 0)
	assert_error(session.use_steady_voice("iris", "mara"), FacetsError.USAGE_LIMIT, "once per scene")
	assert_ok(session.start_scene("scene.next"))
	assert_error(session.use_steady_voice("iris", "mara"), FacetsError.NOT_APPLICABLE, "last scene's setback does not count")


func test_t13_steady_voice_requires_communication() -> void:
	var registry := W.registry()
	assert_ok(registry.add_condition({"id": "test.gagged", "display_name": "Gagged", "penalty": 0, "restrictions": ["cannot_communicate"], "applicability_tags": ["checks"]}))
	var session: FacetsSession = FacetsSession.create(registry, W.world(), {"dice": FacetsDiceSource.fixed([[1, 1]])}).value
	_attempt(session, FacetsActionRequest.make("mara", "test.scare", "brave"), "fear")
	assert_ok(session.apply_host_effects("mara", [W.eff("actor.condition_add", {"condition_id": "test.gagged"})], "gag"))
	assert_error(session.use_steady_voice("iris", "mara"), FacetsError.INELIGIBLE, "ally cannot communicate")


# --- Bargain Maker -------------------------------------------------------------------------

func test_t13_bargain_maker_offers_lesser_concession() -> void:
	var session := W.session([[6, 6], [6, 6]])
	var event: FacetsResolutionEvent = assert_ok(session.commit((session.preview(FacetsActionRequest.make("iris", "test.persuade", "plead")).value as FacetsCheckPreview).token, {}, "b1"))
	assert_eq(event.pending_decision.kind, "benefit")
	assert_true(event.pending_decision.option_ids().has("bargain:pass"))
	assert_ok(session.choose(event.event_id, event.pending_decision.decision_id, "bargain:pass", "b2"))
	assert_eq(session.actor_state("iris").item_count("item.side_pass"), 1)
	assert_false(session.actor_state("iris").knows("fact.patrol_route"), "concession replaced the benefit")
	assert_ok(session.authorize_meaningful_change("obj.gate", "new day"))
	var again: FacetsResolutionEvent = assert_ok(session.commit((session.preview(FacetsActionRequest.make("iris", "test.persuade", "plead")).value as FacetsCheckPreview).token, {}, "b3"))
	assert_false(again.pending_decision.option_ids().has("bargain:pass"), "once per scene")
	var mara: FacetsCheckPreview = W.session().preview(FacetsActionRequest.make("mara", "test.persuade", "plead")).value
	assert_false(mara.benefit_options.any(func(o: Dictionary) -> bool: return str(o["id"]).begins_with("bargain")), "Mara lacks Bargain Maker")


# --- Trail Reader ---------------------------------------------------------------------------

func test_t13_trail_reader_reveals_one_supported_fact() -> void:
	var session := W.session([[6, 5], [6, 5], [1, 1]])
	_add_archetype(session, "scout", "core.archetype.investigator")
	var first := _attempt(session, FacetsActionRequest.make("scout", "test.search", "look"), "t1", {"resolve": "decline"})
	assert_true(FacetsRules.is_success_band(first.final_band))
	var scout := session.actor_state("scout")
	assert_true(scout.knows("fact.trail"), "evidence-supported fact revealed")
	assert_false(scout.knows("fact.secret_trail"), "unsupported fact never revealed")
	assert_ok(session.start_scene("scene.next"))
	assert_ok(session.authorize_meaningful_change("obj.lead", "reset"))
	var other := _attempt(session, FacetsActionRequest.make("mara", "test.search", "look"), "t2", {"resolve": "decline"})
	assert_true(FacetsRules.is_success_band(other.final_band))
	assert_false(session.actor_state("mara").knows("fact.trail"), "Mara lacks Trail Reader")


func test_t13_trail_reader_not_on_failure() -> void:
	var session := W.session([[1, 1]])
	_add_archetype(session, "scout", "core.archetype.investigator")
	var failed := _attempt(session, FacetsActionRequest.make("scout", "test.search", "look"), "t1", {"resolve": "decline"})
	assert_eq(failed.final_band, "failure")
	assert_false(session.actor_state("scout").knows("fact.trail"))
