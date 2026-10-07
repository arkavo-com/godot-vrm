extends FacetsTestCase
## Session-level acceptance: T04, T08-T12, T14-T22, T24 plus the Mara
## controller fixture through the transactional API.

const W := preload("res://tests/framework/test_world.gd")


func _preview(session: FacetsSession, request: FacetsActionRequest, principal: FacetsPrincipal = null) -> FacetsCheckPreview:
	return assert_ok(session.preview(request, principal), "preview %s" % request.action_id)


func _commit(session: FacetsSession, request: FacetsActionRequest, push: bool, request_id: String) -> FacetsResolutionEvent:
	var preview := _preview(session, request)
	if preview == null:
		return null
	return assert_ok(session.commit(preview.token, {"push": push}, request_id), "commit %s" % request_id)


# --- Mara fixture and decisions ------------------------------------------------------

func test_t09_mara_controller_offer_order() -> void:
	var session := W.session([[3, 3]])
	var event := _commit(session, W.bypass_request(), false, "c1")
	assert_true(event.is_pending())
	assert_eq(event.dice, [3, 3])
	assert_eq(int(event.base["total"]), 11)
	assert_eq(int(event.base["margin"]), -2)
	assert_eq(event.base["band"], "costly_offer")
	assert_eq(event.pending_decision.kind, "resolve", "Resolve is offered before the costly choice")
	var spend: Dictionary = event.pending_decision.options[0]
	assert_eq(spend["id"], "spend")
	assert_eq(spend["band_after"], "success", "shows the band change before confirmation")


func test_t09_branch_c_spend_resolve_clean_success() -> void:
	var session := W.session([[3, 3]])
	var event := _commit(session, W.bypass_request(), false, "c1")
	var final: FacetsResolutionEvent = assert_ok(session.choose(event.event_id, event.pending_decision.decision_id, "spend", "c2"))
	assert_true(final.is_final())
	assert_eq(final.final_band, "success")
	assert_eq(int(final.evaluation["total"]), 13)
	var mara := session.actor_state("mara")
	assert_eq(mara.resolve, 0, "Resolve spent")
	assert_eq(session.snapshot().object_flag("door", "open"), true)
	assert_eq(session.snapshot().fact_value("fact.grid_trace"), null, "no trace on a clean success")


func test_t09_branch_a_accept_cost() -> void:
	var session := W.session([[3, 3]])
	var event := _commit(session, W.bypass_request(), false, "c1")
	var next: FacetsResolutionEvent = assert_ok(session.choose(event.event_id, event.pending_decision.decision_id, "decline", "c2"))
	assert_eq(next.pending_decision.kind, "cost")
	var final: FacetsResolutionEvent = assert_ok(session.choose(event.event_id, next.pending_decision.decision_id, "accept:trace", "c3"))
	assert_eq(final.final_band, "success_with_cost")
	assert_eq(session.snapshot().object_flag("door", "open"), true)
	assert_eq(session.snapshot().fact_value("fact.grid_trace"), true)
	assert_eq(session.actor_state("mara").resolve, 1, "declined Resolve kept")


func test_t09_branch_b_decline_cost_fails() -> void:
	var session := W.session([[3, 3]])
	var event := _commit(session, W.bypass_request(), false, "c1")
	var next: FacetsResolutionEvent = assert_ok(session.choose(event.event_id, event.pending_decision.decision_id, "decline", "c2"))
	var final: FacetsResolutionEvent = assert_ok(session.choose(event.event_id, next.pending_decision.decision_id, "decline", "c3"))
	assert_eq(final.final_band, "failure")
	var world := session.snapshot()
	assert_eq(world.object_flag("door", "open"), false)
	assert_eq(int(world.counters["patrol"]), 1, "patrol advanced")
	assert_eq(world.object_flag("controller", "locked"), true, "controller locked")


func test_t09_resolve_unavailable_at_zero_and_not_twice() -> void:
	var session := W.session([[3, 3], [3, 3]])
	var event := _commit(session, W.bypass_request(), false, "c1")
	assert_ok(session.choose(event.event_id, event.pending_decision.decision_id, "spend", "c2"))
	assert_eq(session.actor_state("mara").resolve, 0)
	# A new check with Resolve 0 offers no Resolve decision.
	session.apply_host_effects("mara", [W.eff("object.set_flag", {"object_id": "door", "key": "open", "value": false})], "reset door")
	var second := _commit(session, W.bypass_request(), false, "c3")
	assert_eq(second.pending_decision.kind, "cost", "no Resolve offer at 0")
	var record := second.to_dict()
	assert_false(record["decision"]["options"].any(func(o: Dictionary) -> bool: return o["id"] == "spend"))


func test_t09_resolve_capped_at_three() -> void:
	var session := W.session()
	for scene in ["s1", "s2", "s3", "s4"]:
		session.start_scene(scene)
		var offer: FacetsResolutionEvent = assert_ok(session.offer_identity_trigger("mara", "mara.lead"))
		var final: FacetsResolutionEvent = assert_ok(session.choose(offer.event_id, offer.pending_decision.decision_id, "accept", "id-%s" % scene))
		# Make the disadvantage material again for the next scene.
		assert_ok(session.apply_host_effects("mara", [W.eff("fact.set", {"fact_id": "fact.window_missed", "value": false})], "reset window"))
		if scene == "s3" or scene == "s4":
			assert_eq(int(final.record["amount"]), 0, "award is 0 at the cap (%s)" % scene)
	assert_eq(session.actor_state("mara").resolve, 3, "Resolve never exceeds 3")


func test_t09_strong_benefit_choice_and_auto_select() -> void:
	var session := W.session([[6, 6], [6, 6]])
	# Two benefits -> explicit choice after the Resolve offer is skipped at strong.
	var event := _commit(session, W.bypass_request(), false, "c1")
	assert_eq(event.pending_decision.kind, "benefit", "no Resolve offer when already strong")
	var final: FacetsResolutionEvent = assert_ok(session.choose(event.event_id, event.pending_decision.decision_id, "log", "c2"))
	assert_eq(final.final_band, "strong_success")
	assert_true(session.actor_state("mara").knows("fact.access_log"))
	# Single harmless benefit auto-selects.
	var sneak := _commit(session, FacetsActionRequest.make("mara", "test.sneak", "quiet"), false, "c3")
	assert_true(sneak.is_final(), "single harmless benefit auto-selected")
	assert_eq(session.actor_state("mara").flags.get("unseen"), true)


# --- T04 impossible/ineligible actions ------------------------------------------------

func test_t04_ineligible_consumes_nothing() -> void:
	var session := W.session([[3, 3]])
	assert_ok(session.apply_host_effects("mara", [W.eff("object.set_flag", {"object_id": "controller", "key": "locked", "value": true})], "lock"))
	var before := session.snapshot().to_dict()
	assert_error(session.preview(W.bypass_request()), FacetsError.INELIGIBLE)
	assert_eq(session.dice_source().draws, 0, "no dice drawn")
	assert_eq(session.snapshot().to_dict(), before, "nothing spent")


func test_t04_routine_succeeds_without_rng() -> void:
	var session := W.session([])
	var event := _commit(session, FacetsActionRequest.make("mara", "test.routine", "give"), false, "r1")
	assert_true(event.is_final())
	assert_true(event.routine)
	assert_eq(event.final_band, "success")
	assert_eq(event.dice, [])
	assert_eq(session.dice_source().draws, 0, "routine draws no dice")
	assert_eq(session.snapshot().object_flag("package", "delivered"), true)


# --- T07 opposed in session -------------------------------------------------------

func test_t07_opposed_defender_does_not_roll() -> void:
	var session := W.session([[4, 4]])
	var preview := _preview(session, FacetsActionRequest.make("mara", "test.persuade", "plead"))
	assert_eq(preview.target, 13, "7 + tenacity 4 + influence 2")
	assert_false(preview.target_explanation[0].contains("tenacity"), "NPC defense breakdown is private")
	assert_ok(session.commit(preview.token, {}, "p1"))
	assert_eq(session.dice_source().draws, 1, "only the actor rolls")


# --- T08 push -----------------------------------------------------------------------

func test_t08_push_capacity_boundary() -> void:
	var session := W.session([[3, 3]])
	# Mara: tenacity 2, capacity 6. capacity-3 = 3 strain: push allowed.
	assert_ok(session.apply_host_effects("mara", [W.eff("actor.strain", {"amount": 3})], "strain"))
	var preview := _preview(session, W.bypass_request())
	assert_true(preview.push_available, "push at capacity-3")
	var event: FacetsResolutionEvent = assert_ok(session.commit(preview.token, {"push": true}, "p1"))
	assert_eq(int(event.base["push_bonus"]), 1)
	assert_eq(session.actor_state("mara").strain, 5, "paid 2 strain")
	assert_false(session.actor_state("mara").is_overwhelmed(), "push never reaches capacity")


func test_t08_push_rejected_at_capacity_minus_two_draws_nothing() -> void:
	var session := W.session([[3, 3]])
	assert_ok(session.apply_host_effects("mara", [W.eff("actor.strain", {"amount": 4})], "strain"))
	var preview := _preview(session, W.bypass_request())
	assert_false(preview.push_available, "push at capacity-2 rejected")
	assert_error(session.commit(preview.token, {"push": true}, "p1"), FacetsError.PUSH_NOT_ALLOWED)
	assert_eq(session.dice_source().draws, 0, "rejected push draws nothing")
	assert_eq(session.actor_state("mara").strain, 4, "no strain paid")
	assert_false(session.has_pending())


func test_t08_push_stays_spent_on_failure_and_abandon() -> void:
	var session := W.session([[1, 1]])
	var preview := _preview(session, W.bypass_request())
	var event: FacetsResolutionEvent = assert_ok(session.commit(preview.token, {"push": true}, "p1"))
	assert_true(event.is_pending())
	var final: FacetsResolutionEvent = assert_ok(session.abandon(event.event_id, "p2"))
	assert_eq(final.final_band, "failure")
	assert_eq(session.actor_state("mara").strain, 2, "push not refunded")


# --- T10 Overwhelmed in session -------------------------------------------------------

func test_t10_overwhelmed_blocks_push_and_penalizes() -> void:
	var session := W.session([[3, 3]])
	assert_ok(session.apply_host_effects("mara", [W.eff("actor.strain", {"amount": 9})], "overload"))
	var mara := session.actor_state("mara")
	assert_eq(mara.strain, 6, "clamped at capacity")
	assert_true(mara.is_overwhelmed())
	assert_ok(session.apply_host_effects("mara", [W.eff("actor.condition_add", {"condition_id": "core.shaken"})], "shaken"))
	var preview := _preview(session, FacetsActionRequest.make("mara", "test.persuade", "plead"))
	assert_false(preview.push_available, "Overwhelmed cannot push")
	assert_eq(preview.modifier_raw, -1, "Overwhelmed -1 and Shaken -1 do not stack")


# --- T11 recovery -------------------------------------------------------------------

func test_t11_breather_once_per_authorized_opportunity() -> void:
	var session := W.session()
	assert_ok(session.apply_host_effects("mara", [W.eff("actor.strain", {"amount": 6})], "overload"))
	assert_error(session.take_breather("mara", "opp.1"), FacetsError.NOT_AUTHORIZED, "no opportunity yet")
	assert_ok(session.grant_opportunity("opp.1", "breather"))
	var event: FacetsResolutionEvent = assert_ok(session.take_breather("mara", "opp.1"))
	assert_eq(int(event.resource_deltas["strain"]), -2)
	assert_eq(session.actor_state("mara").strain, 4)
	assert_false(session.actor_state("mara").is_overwhelmed(), "Overwhelmed removed below capacity")
	assert_error(session.take_breather("mara", "opp.1"), FacetsError.ALREADY_USED, "once per opportunity")
	assert_ok(session.take_breather("iris", "opp.1"), "another actor may use the same opportunity")


func test_t11_spoken_scene_reset_grants_nothing() -> void:
	var session := W.session()
	assert_ok(session.apply_host_effects("mara", [W.eff("actor.strain", {"amount": 4})], "strain"))
	var player := FacetsPrincipal.player("p1", ["mara"])
	assert_error(session.start_scene("scene.new", "", player), FacetsError.NOT_AUTHORIZED, "client cannot start a scene")
	assert_error(session.grant_opportunity("opp.fake", "breather", player), FacetsError.NOT_AUTHORIZED, "client cannot authorize recovery")
	assert_error(session.take_breather("mara", "opp.fake", player), FacetsError.NOT_AUTHORIZED)
	assert_error(session.preview(FacetsActionRequest.make("mara", "breather", "rest"), player), FacetsError.UNKNOWN_ID, "no breather action")
	assert_eq(session.actor_state("mara").strain, 4)


func test_t11_full_rest_resets_strain() -> void:
	var session := W.session()
	assert_ok(session.apply_host_effects("mara", [W.eff("actor.strain", {"amount": 5})], "strain"))
	assert_error(session.full_rest("mara", "opp.b"), FacetsError.NOT_AUTHORIZED)
	assert_ok(session.grant_opportunity("opp.b", "breather"))
	assert_error(session.full_rest("mara", "opp.b"), FacetsError.NOT_AUTHORIZED, "a breather is not secure rest")
	assert_ok(session.grant_opportunity("opp.rest", "secure_rest"))
	assert_ok(session.full_rest("mara", "opp.rest"))
	assert_eq(session.actor_state("mara").strain, 0)


# --- T12 identity trigger ------------------------------------------------------------

func test_t12_identity_award_once_per_scene() -> void:
	var session := W.session()
	var offer: FacetsResolutionEvent = assert_ok(session.offer_identity_trigger("mara", "mara.lead"))
	assert_eq(offer.pending_decision.kind, "identity")
	var final: FacetsResolutionEvent = assert_ok(session.choose(offer.event_id, offer.pending_decision.decision_id, "accept", "i1"))
	assert_eq(int(final.record["amount"]), 1)
	assert_eq(final.record["award_key"], "identity:mara:scene.market")
	assert_eq(final.record["disadvantage"], "Miss the delivery window")
	assert_eq(session.snapshot().fact_value("fact.window_missed"), true, "disadvantage applied")
	assert_eq(session.actor_state("mara").resolve, 2)
	# Same scene again: disadvantage is already applied (trivial) and the key is used.
	var again: FacetsResolutionEvent = assert_ok(session.offer_identity_trigger("mara", "mara.lead"))
	var duplicate: FacetsResolutionEvent = assert_ok(session.choose(again.event_id, again.pending_decision.decision_id, "accept", "i2"))
	assert_eq(int(duplicate.record["amount"]), 0, "trivial duplicate awards zero")
	assert_eq(session.actor_state("mara").resolve, 2)
	# Even with a material disadvantage, the same scene awards nothing more.
	assert_ok(session.apply_host_effects("mara", [W.eff("fact.set", {"fact_id": "fact.window_missed", "value": false})], "reset"))
	var third: FacetsResolutionEvent = assert_ok(session.offer_identity_trigger("mara", "mara.lead"))
	var third_final: FacetsResolutionEvent = assert_ok(session.choose(third.event_id, third.pending_decision.decision_id, "accept", "i3"))
	assert_eq(int(third_final.record["amount"]), 0, "once per actor per scene")


func test_t12_rejection_gives_nothing_and_client_cannot_offer() -> void:
	var session := W.session()
	assert_error(session.offer_identity_trigger("mara", "mara.lead", FacetsPrincipal.player("p", ["mara"])), FacetsError.NOT_AUTHORIZED)
	var offer: FacetsResolutionEvent = assert_ok(session.offer_identity_trigger("mara", "mara.lead"))
	var final: FacetsResolutionEvent = assert_ok(session.choose(offer.event_id, offer.pending_decision.decision_id, "reject", "i1"))
	assert_eq(int(final.record["amount"]), 0)
	assert_eq(session.actor_state("mara").resolve, 1)
	assert_eq(session.snapshot().fact_value("fact.window_missed"), null)


# --- T14/T15 retry locks -------------------------------------------------------------

func _fail_bypass(session: FacetsSession) -> void:
	var event := _commit(session, W.bypass_request(), false, "fail-1")
	assert_ok(session.abandon(event.event_id, "fail-2"))


func test_t14_rephrased_retry_gets_no_new_dice() -> void:
	var session := W.session([[1, 1], [6, 6]])
	var preview := _preview(session, FacetsActionRequest.make("mara", "test.search", "look"))
	var event: FacetsResolutionEvent = assert_ok(session.commit(preview.token, {}, "s1"))
	if event.is_pending():
		event = assert_ok(session.abandon(event.event_id, "s2"))
	assert_eq(event.final_band, "failure")
	var draws := session.dice_source().draws
	for attempt in 20:
		var request := FacetsActionRequest.make("mara", "test.search", "look")
		assert_error(session.preview(request), FacetsError.RETRY_LOCKED, "attempt %d" % attempt)
	assert_eq(session.dice_source().draws, draws, "twenty rephrasings draw no dice")


func test_t15_unrelated_revision_does_not_unlock_but_authorized_change_does() -> void:
	var session := W.session([[1, 1], [6, 6]])
	var preview := _preview(session, FacetsActionRequest.make("mara", "test.search", "look"))
	var event: FacetsResolutionEvent = assert_ok(session.commit(preview.token, {}, "s1"))
	if event.is_pending():
		assert_ok(session.abandon(event.event_id, "s2"))
	for index in 3:
		assert_ok(session.apply_host_effects("mara", [W.eff("world.counter_add", {"counter_id": "noise", "amount": 1})], "unrelated"))
	assert_error(session.preview(FacetsActionRequest.make("mara", "test.search", "look")), FacetsError.RETRY_LOCKED, "revision bumps alone do not unlock")
	assert_ok(session.preview(FacetsActionRequest.make("mara", "test.search", "track")), "a different approach is a different route")
	assert_ok(session.authorize_meaningful_change("obj.lead", "new witness arrived"))
	assert_ok(session.preview(FacetsActionRequest.make("mara", "test.search", "look")), "authorized change unlocks")


# --- T16 stale previews ---------------------------------------------------------------

func test_t16_stale_preview_rejected_before_costs_and_rng() -> void:
	var session := W.session([[3, 3]])
	var preview := _preview(session, W.bypass_request())
	assert_ok(session.apply_host_effects("mara", [W.eff("world.counter_add", {"counter_id": "noise", "amount": 1})], "world moved"))
	assert_error(session.commit(preview.token, {"push": true}, "x1"), FacetsError.STALE_PREVIEW)
	assert_eq(session.dice_source().draws, 0)
	assert_eq(session.actor_state("mara").strain, 0, "no push paid")
	assert_eq(session.actor_state("mara").item_count("item.scrap_wire"), 2)
	var expected := FacetsActionRequest.make("mara", "test.bypass", "tech").with_tools(["tool.signal_kit"])
	expected.expected_revision = 0
	assert_error(session.preview(expected), FacetsError.STALE_PREVIEW, "expected_revision mismatch")


# --- T17 idempotency --------------------------------------------------------------------

func test_t17_duplicate_commit_and_choice_return_same_record() -> void:
	var session := W.session([[3, 3], [6, 6]])
	var preview := _preview(session, W.bypass_request())
	var first: FacetsResolutionEvent = assert_ok(session.commit(preview.token, {}, "dup-1"))
	var again: FacetsResolutionEvent = assert_ok(session.commit(preview.token, {}, "dup-1"))
	assert_eq(again.to_dict(), first.to_dict(), "same record")
	assert_eq(session.dice_source().draws, 1, "no second roll")
	assert_error(session.commit(preview.token, {"push": true}, "dup-1"), FacetsError.IDEMPOTENCY_CONFLICT)
	var chosen: FacetsResolutionEvent = assert_ok(session.choose(first.event_id, first.pending_decision.decision_id, "spend", "dup-2"))
	var chosen_again: FacetsResolutionEvent = assert_ok(session.choose(first.event_id, first.pending_decision.decision_id, "spend", "dup-2"))
	assert_eq(chosen_again.to_dict(), chosen.to_dict())
	assert_error(session.choose(first.event_id, first.pending_decision.decision_id, "decline", "dup-2"), FacetsError.IDEMPOTENCY_CONFLICT)
	assert_error(session.choose(first.event_id, first.pending_decision.decision_id, "decline", "dup-3"), FacetsError.NOT_PENDING)
	assert_eq(session.actor_state("mara").resolve, 0, "Resolve spent once")


func test_t17_commit_requires_request_id() -> void:
	var session := W.session([[3, 3]])
	var preview := _preview(session, W.bypass_request())
	assert_error(session.commit(preview.token, {}, ""), FacetsError.MISSING_REQUEST_ID)
	assert_error(session.commit("pv-unknown", {}, "z"), FacetsError.UNKNOWN_PREVIEW)


# --- T18 save/reload pending ---------------------------------------------------------------

func test_t18_reload_pending_resolve_cost_and_benefit() -> void:
	for branch in ["resolve", "cost", "benefit"]:
		var store := FacetsMemoryStore.new()
		var dice := [[6, 6]] if branch == "benefit" else [[3, 3]]
		var session := W.session(dice, store)
		var preview := _preview(session, W.bypass_request())
		var event: FacetsResolutionEvent = assert_ok(session.commit(preview.token, {"push": branch == "cost"}, "b1"))
		if branch == "cost":
			event = assert_ok(session.choose(event.event_id, event.pending_decision.decision_id, "decline", "b2"))
		assert_eq(event.pending_decision.kind, branch)
		var restored: FacetsSession = assert_ok(FacetsSession.restore(store, W.registry(), {"dice": FacetsDiceSource.fixed([])}), branch)
		var pending := restored.pending_event()
		assert_true(pending != null and pending.is_pending(), "%s pending survives" % branch)
		assert_eq(pending.dice, event.dice, "%s dice retained" % branch)
		assert_eq(pending.pending_decision.option_ids(), event.pending_decision.option_ids(), "%s options frozen" % branch)
		assert_eq(pending.push, event.push, "%s push payment retained" % branch)
		assert_eq(restored.actor_state("mara").strain, session.actor_state("mara").strain)
		var option := "accept:trace" if branch == "cost" else ("spend" if branch == "resolve" else "silent")
		var final: FacetsResolutionEvent = assert_ok(restored.choose(pending.event_id, pending.pending_decision.decision_id, option, "b3"))
		assert_true(final.is_final(), "%s finishes after reload" % branch)
		assert_eq(restored.dice_source().draws, 0, "%s no reroll after reload" % branch)


func test_t18_file_store_roundtrip_with_backup() -> void:
	var path := "user://facets_tests/session_t18.json"
	var store := FacetsFileStore.at(path)
	store.delete_all()
	var session := W.session([[3, 3]], store)
	var event := _commit(session, W.bypass_request(), false, "f1")
	assert_true(FileAccess.file_exists(ProjectSettings.globalize_path(path + ".bak")), "previous save retained")
	var restored: FacetsSession = assert_ok(FacetsSession.restore(FacetsFileStore.at(path), W.registry()))
	assert_eq(restored.pending_event().event_id, event.event_id)
	# Corrupt the primary save: the backup is still recoverable.
	var file := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	var recovered: FacetsSession = assert_ok(FacetsSession.restore(FacetsFileStore.at(path), W.registry()), "recover from .bak")
	assert_true(recovered != null)
	store.delete_all()


# --- T19 injected failures -----------------------------------------------------------------

func test_t19_persistence_failure_commits_nothing_and_restores_rng() -> void:
	var store := FacetsMemoryStore.new()
	var reply := FacetsSession.create(W.registry(), W.world(), {"seed": 1234, "store": store})
	var session: FacetsSession = reply.value
	var preview := _preview(session, W.bypass_request())
	var before := session.snapshot().to_dict()
	var rng_before := session.dice_source().get_state()
	store.fail_next_writes = 1
	var failed := session.commit(preview.token, {"push": true}, "pf-1")
	assert_error(failed, FacetsError.PERSISTENCE_FAILED)
	assert_true(failed.error.retryable)
	assert_eq(session.snapshot().to_dict(), before, "old committed state intact")
	assert_false(session.has_pending())
	assert_eq(session.dice_source().get_state()["state"], rng_before["state"], "RNG restored")
	var retry: FacetsResolutionEvent = assert_ok(session.commit(preview.token, {"push": true}, "pf-1"), "retry same request")
	assert_eq(session.actor_state("mara").strain, 2, "push paid exactly once")
	assert_true(retry != null)


func test_t19_effect_failure_keeps_pending_recoverable() -> void:
	var store := FacetsMemoryStore.new()
	var session := W.session([[3, 3]], store)
	var event := _commit(session, W.bypass_request(), false, "e1")
	var before := session.snapshot().to_dict()
	store.fail_next_writes = 1
	assert_error(session.choose(event.event_id, event.pending_decision.decision_id, "spend", "e2"), FacetsError.PERSISTENCE_FAILED)
	assert_true(session.has_pending(), "pending record retained")
	assert_eq(session.snapshot().to_dict(), before, "no partial final state")
	assert_eq(session.actor_state("mara").resolve, 1)
	var final: FacetsResolutionEvent = assert_ok(session.choose(event.event_id, event.pending_decision.decision_id, "spend", "e2"))
	assert_eq(final.final_band, "success")
	# An effect that cannot apply rejects the whole finalization.
	var broken := FacetsSession.create(W.registry(), W.world(), {"dice": FacetsDiceSource.fixed([[1, 1]])}).value as FacetsSession
	var preview := _preview(broken, FacetsActionRequest.make("mara", "test.broken", "try"))
	var snapshot_before := broken.snapshot().to_dict()
	assert_error(broken.commit(preview.token, {}, "bk1"), FacetsError.EFFECT_REJECTED)
	assert_eq(broken.snapshot().to_dict(), snapshot_before, "nothing applied")


# --- T20 replay ------------------------------------------------------------------------------

func test_t20_replay_reproduces_state_without_dice() -> void:
	var store := FacetsMemoryStore.new()
	var session := W.session([[3, 3], [6, 6], [2, 2]], store)
	var event := _commit(session, W.bypass_request(), true, "r1")
	session.choose(event.event_id, event.pending_decision.decision_id, "decline", "r2")
	session.choose(event.event_id, "%s:cost" % event.event_id, "accept:trace", "r3")
	assert_ok(session.grant_opportunity("opp", "breather"))
	assert_ok(session.take_breather("mara", "opp"))
	var offer: FacetsResolutionEvent = assert_ok(session.offer_identity_trigger("mara", "mara.lead"))
	assert_ok(session.choose(offer.event_id, offer.pending_decision.decision_id, "accept", "r4"))
	assert_ok(session.award_milestone("mara", "m.delivery", "small", "evt.delivery"))
	var counting := FacetsDiceSource.fixed([])
	var restored: FacetsSession = assert_ok(FacetsSession.restore(store, W.registry(), {"dice": counting}))
	assert_eq(restored.snapshot().to_dict(), session.snapshot().to_dict(), "state and counters reproduced")
	assert_eq(counting.draws, 0, "replay never draws dice")
	var data := session.to_save_dict()
	var replayed: FacetsWorldSnapshot = assert_ok(FacetsSession.replay(data["checkpoint"]["state"], data["journal"], 0))
	assert_eq(replayed.digest(), session.snapshot().digest())


func test_t20_checkpoint_then_events_and_corruption() -> void:
	var store := FacetsMemoryStore.new()
	var session := W.session([[3, 3]], store)
	assert_ok(session.award_milestone("mara", "m.1", "small", "evt.1"))
	assert_ok(session.checkpoint())
	assert_ok(session.award_milestone("mara", "m.2", "small", "evt.2"))
	var data := session.to_save_dict()
	assert_eq(data["journal"].size(), 1, "only events after the checkpoint")
	var restored: FacetsSession = assert_ok(FacetsSession.restore(store, W.registry()))
	assert_eq(restored.actor_state("mara").growth, 2)
	# Corrupt sequences stop with actionable errors.
	var gap: Array = data["journal"].duplicate(true)
	gap[0]["sequence"] = 99
	assert_error(FacetsSession.replay(data["checkpoint"]["state"], gap, int(data["checkpoint"]["sequence"])), FacetsError.REPLAY_CORRUPT)
	var unknown: Array = data["journal"].duplicate(true)
	unknown[0]["ops"].append({"op": "teleport", "path": ["clock"]})
	assert_error(FacetsSession.replay(data["checkpoint"]["state"], unknown, int(data["checkpoint"]["sequence"])), FacetsError.UNKNOWN_OPERATION)
	var future: Array = data["journal"].duplicate(true)
	future[0]["format"] = 2
	assert_error(FacetsSession.replay(data["checkpoint"]["state"], future, int(data["checkpoint"]["sequence"])), FacetsError.UNSUPPORTED_VERSION)
	var tampered: Array = data["journal"].duplicate(true)
	tampered[0]["ops"][0]["before"] = 99
	assert_error(FacetsSession.replay(data["checkpoint"]["state"], tampered, int(data["checkpoint"]["sequence"])), FacetsError.REPLAY_CORRUPT)


# --- T21 duplicates ---------------------------------------------------------------------------

class CountingPort:
	extends RefCounted
	var seen: Array = []

	func present(event: FacetsResolutionEvent) -> void:
		seen.append(event.event_id)


func test_t21_duplicates_never_reapply() -> void:
	var session := W.session([[3, 3]])
	var port := CountingPort.new()
	session.add_presentation_port(port)
	assert_ok(session.award_milestone("mara", "m.delivery", "small", "evt.delivery", null, "aw-1"))
	assert_ok(session.award_milestone("mara", "m.delivery", "small", "evt.delivery", null, "aw-1"), "duplicate delivery replays the response")
	assert_error(session.award_milestone("mara", "m.delivery", "small", "evt.delivery", null, "aw-2"), FacetsError.ALREADY_USED)
	assert_error(session.award_milestone("mara", "m.chapter", "chapter", "evt.delivery", null, "aw-3"), FacetsError.ALREADY_USED, "never both sizes for one event")
	assert_eq(session.actor_state("mara").growth, 1)
	# Re-presenting an event to narration changes nothing.
	var before := session.snapshot().to_dict()
	var event: FacetsResolutionEvent = assert_ok(session.get_event("evt-000001"))
	port.present(event)
	port.present(event)
	assert_eq(session.snapshot().to_dict(), before)
	assert_eq(port.seen.size(), 3, "one publication per commit plus two manual narrations")
	# Duplicate load does not double-apply.
	var store := session.store() as FacetsMemoryStore
	var one: FacetsSession = assert_ok(FacetsSession.restore(store.clone_store(), W.registry()))
	var two: FacetsSession = assert_ok(FacetsSession.restore(store.clone_store(), W.registry()))
	assert_eq(one.actor_state("mara").growth, 1)
	assert_eq(two.actor_state("mara").growth, 1)


# --- T22 rejection of invalid inputs ------------------------------------------------------------

func test_t22_unknown_effect_tool_stat_and_fact_rejected() -> void:
	var registry := W.registry()
	var bad: Dictionary = W.actions()[0].duplicate(true)
	bad["id"] = "test.bad"
	bad["success_effects"] = [{"op": "actor.set_facet", "params": {"facet": "cunning", "value": 6}}]
	var added := registry.add_action(bad)
	assert_error(added, FacetsError.UNKNOWN_OPERATION, "unknown effect op")
	var session := W.session([[3, 3]])
	var no_tool := FacetsActionRequest.make("mara", "test.bypass", "tech").with_tools(["tool.plasma_cutter"])
	assert_error(session.preview(no_tool), FacetsError.INELIGIBLE, "nonexistent tool")
	var injected := FacetsActionRequest.validate_dict({"actor_id": "mara", "action_id": "test.bypass", "approach_id": "tech", "facet": 5, "strain": -2})
	assert_error(injected, FacetsError.UNKNOWN_FIELD, "injected stat change")
	var hidden_target := FacetsActionRequest.make("mara", "test.search", "look").with_targets(["fact.guard_secret"])
	var reply := session.preview(hidden_target)
	assert_error(reply, FacetsError.UNKNOWN_ID, "inaccessible fact as target")
	assert_false(reply.error.message.contains("fixer"), "error does not disclose the hidden fact")
	assert_error(session.apply_host_effects("mara", [{"op": "fact.reveal", "params": {"fact_id": "x", "bonus": 3}}], "bad"), FacetsError.UNKNOWN_FIELD, "unknown parameter")


# --- T24 hard refusal -----------------------------------------------------------------------------

func test_t24_hard_refusal_survives_every_outcome() -> void:
	for die_1 in range(1, 7):
		for die_2 in range(1, 7):
			var session := W.session([[die_1, die_2]])
			var event := _commit(session, FacetsActionRequest.make("mara", "test.vault", "plead"), false, "v1")
			var guard := 0
			while event != null and event.is_pending() and guard < 4:
				guard += 1
				var decision := event.pending_decision
				var option: String = decision.option_ids()[0]
				event = assert_ok(session.choose(event.event_id, decision.decision_id, option, "v-%d" % guard))
			var world := session.snapshot()
			if not assert_false(world.grants.has("npc.guard:vault"), "dice %d,%d" % [die_1, die_2]):
				return
	var player_beliefs := W.session([[6, 6]])
	var before := player_beliefs.actor_state("mara").to_dict()
	assert_error(player_beliefs.apply_host_effects("npc.guard", [W.eff("npc.disposition", {"npc_id": "mara", "key": "believes_guard", "value": true})], "persuade player"), FacetsError.EFFECT_REJECTED, "player beliefs are never written")
	assert_eq(player_beliefs.actor_state("mara").to_dict(), before)


func test_t24_refusal_visible_as_note() -> void:
	var session := W.session([[6, 6]])
	var event := _commit(session, FacetsActionRequest.make("mara", "test.vault", "plead"), false, "v1")
	assert_true(event.is_final())
	var notes: Array = event.record["finalize_ops"].filter(func(op: Dictionary) -> bool: return op["op"] == "note" and op.get("kind") == "refused")
	assert_eq(notes.size(), 1, "refusal recorded")
