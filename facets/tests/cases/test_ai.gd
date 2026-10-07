extends FacetsTestCase
## T23 perception-filtered views plus the optional AI adapter: proposal
## validation, timeouts, cancellation, narration fallback and NPC policy.

const W := preload("res://tests/framework/test_world.gd")


func _session(dice: Array = []) -> FacetsSession:
	return W.session(dice)


func test_t23_private_facts_absent_from_provider_views() -> void:
	var session := _session([[6, 5]])
	var provider := FacetsFakeProvider.new()
	var adapter := FacetsAiAdapter.make(session, provider)
	var mara := FacetsPrincipal.ai("ai.mara", ["mara"])
	adapter.propose("mara", mara, 0)
	var sent := FacetsJson.canonical(provider.observations[0])
	assert_false(sent.contains("fact.guard_secret"), "NPC private fact ID absent")
	assert_false(sent.contains("paid by the fixer"), "NPC private fact text absent")
	assert_false(sent.contains("fact.trail"), "unknown private fact absent")
	assert_true(sent.contains("fact.market_open"), "public fact present")
	assert_false(sent.contains("\"facets\""), "other actors' builds absent")
	# Mara learns a private fact; Iris still cannot see it.
	assert_ok(session.apply_host_effects("mara", [W.eff("fact.reveal", {"fact_id": "fact.trail"})], "learn"))
	var mara_view := FacetsAiViews.observation(session, "mara", mara)
	var iris_view := FacetsAiViews.observation(session, "iris", FacetsPrincipal.ai("ai.iris", ["iris"]))
	assert_true(FacetsJson.canonical(mara_view).contains("fact.trail"), "observer's own knowledge included")
	assert_false(FacetsJson.canonical(iris_view).contains("fact.trail"), "not leaked to another actor")
	assert_false(FacetsJson.canonical(iris_view).contains("Footprints"), "label not leaked either")


func test_t23_preview_errors_do_not_disclose_hidden_requirements() -> void:
	var registry := W.registry()
	assert_ok(registry.add_action({
		"id": "test.blackmail", "version": 1, "display_name": "Lean on the guard", "objective_id": "obj.blackmail",
		"approaches": [{"id": "press", "facet": "cunning", "skill": "influence"}],
		"requirements": [{"op": "require.knows_fact", "params": {"fact_id": "fact.guard_secret"}, "label": "Know that the guard is paid by the fixer", "secret": true}],
		"difficulty": {"kind": "fixed", "target": 11}, "retry_policy": "repeatable",
	}))
	var session: FacetsSession = FacetsSession.create(registry, W.world(), {}).value
	var reply := session.preview(FacetsActionRequest.make("mara", "test.blackmail", "press"))
	assert_error(reply, FacetsError.INELIGIBLE)
	assert_false(reply.error.message.contains("fixer"), "secret requirement not revealed")
	assert_false(reply.error.message.contains("guard_secret"))
	var entry: Array = session.catalog("mara").filter(func(e: Dictionary) -> bool: return e["action_id"] == "test.blackmail")
	assert_false(str(entry[0]["reason"]).contains("fixer"), "catalog reason hides it too")
	var npc_preview: FacetsCheckPreview = assert_ok(session.preview(FacetsActionRequest.make("mara", "test.persuade", "plead")))
	assert_false(FacetsJson.canonical(npc_preview.to_dict()).contains("tenacity 4"), "NPC defense stats not shown")


func test_t23_narration_view_hides_other_actors_private_notes() -> void:
	var session := _session([[6, 5]])
	assert_ok(session.add_actor(W.actor("scout", "Scout", FacetsBuild.from_dict(session.registry.get_archetype("core.archetype.investigator")["build"]).to_dict())))
	var preview: FacetsCheckPreview = session.preview(FacetsActionRequest.make("scout", "test.search", "look")).value
	var event: FacetsResolutionEvent = session.commit(preview.token, {}, "n1").value
	event = session.choose(event.event_id, event.pending_decision.decision_id, "decline", "n2").value
	assert_true(event.is_final())
	var own := FacetsAiViews.narration_view(session, event, "scout")
	var other := FacetsAiViews.narration_view(session, event, "mara")
	assert_true(FacetsJson.canonical(own).contains("fact.trail"), "actor's own talent note visible to them")
	assert_false(FacetsJson.canonical(other).contains("fact.trail"), "another observer does not see the revealed fact")


func test_ai_valid_proposal_goes_through_normal_preview() -> void:
	var session := _session([[3, 3]])
	var provider := FacetsFakeProvider.new()
	provider.scripted = [JSON.stringify({"actor_id": "mara", "action_id": "test.bypass", "approach_id": "tech", "tool_ids": ["tool.signal_kit"], "display_text": "I'll crack the panel."})]
	var adapter := FacetsAiAdapter.make(session, provider)
	var principal := FacetsPrincipal.ai("ai.mara", ["mara"])
	var ticket := adapter.propose("mara", principal, 0)
	assert_eq(ticket.state, FacetsAiTicket.DONE)
	var proposal: Dictionary = assert_ok(ticket.result)
	var request: FacetsActionRequest = proposal["request"]
	assert_eq(proposal["display_text"], "I'll crack the panel.")
	assert_error(session.preview(FacetsActionRequest.make("iris", "test.sneak", "quiet"), principal), FacetsError.NOT_AUTHORIZED, "AI principal limited to its actor")
	var preview: FacetsCheckPreview = assert_ok(session.preview(request, principal), "same preview path as manual UI")
	assert_ok(session.commit(preview.token, {}, "ai-1"))


func test_ai_forbidden_fields_and_catalog_membership() -> void:
	var session := _session()
	var observation := FacetsAiViews.observation(session, "mara", FacetsPrincipal.ai("ai", ["mara"]))
	var cases := {
		"difficulty": {"actor_id": "mara", "action_id": "test.bypass", "approach_id": "tech", "difficulty": 9},
		"dice": {"actor_id": "mara", "action_id": "test.bypass", "approach_id": "tech", "dice": [6, 6]},
		"stat": {"actor_id": "mara", "action_id": "test.bypass", "approach_id": "tech", "facets": {"cunning": 6}},
		"grant": {"actor_id": "mara", "action_id": "test.bypass", "approach_id": "tech", "resolve": 3},
		"effects": {"actor_id": "mara", "action_id": "test.bypass", "approach_id": "tech", "effects": [{"op": "object.set_flag"}]},
	}
	for name in cases:
		assert_error(FacetsProposalValidator.validate(JSON.stringify(cases[name]), observation), FacetsError.UNKNOWN_FIELD, name)
	assert_error(FacetsProposalValidator.validate({"actor_id": "mara", "action_id": "test.teleport", "approach_id": "x"}, observation), FacetsError.UNKNOWN_ID, "not in catalog")
	assert_error(FacetsProposalValidator.validate({"actor_id": "iris", "action_id": "test.sneak", "approach_id": "quiet"}, observation), FacetsError.NOT_AUTHORIZED, "other actor")
	assert_error(FacetsProposalValidator.validate({"actor_id": "mara", "action_id": "test.bypass", "approach_id": "tech", "target_ids": ["vault.new_object"]}, observation), FacetsError.UNKNOWN_ID, "new object IDs")
	assert_error(FacetsProposalValidator.validate({"actor_id": "mara", "action_id": "test.bypass", "approach_id": "tech", "tool_ids": ["tool.plasma_cutter"]}, observation), FacetsError.UNKNOWN_ID, "tool not carried")
	assert_error(FacetsProposalValidator.validate({"actor_id": "mara", "action_id": "test.search", "approach_id": "look", "target_ids": ["fact.guard_secret"]}, observation), FacetsError.UNKNOWN_ID, "private fact reference")
	var malformed := FacetsProposalValidator.validate("sure! I'll pick the lock {", observation)
	assert_false(malformed.ok)
	assert_true(malformed.error.message.contains("Please name one action"), "actionable clarification")
	assert_error(FacetsProposalValidator.validate("{\"a\": %s}" % ("[".repeat(10) + "]".repeat(10)), observation), FacetsError.TOO_LARGE, "nesting bounded")


func test_ai_malformed_intent_leaves_state_unchanged() -> void:
	var session := _session([[3, 3]])
	var before := session.snapshot().to_dict()
	var provider := FacetsFakeProvider.new()
	provider.scripted = ["{\"actor_id\": \"mara\", \"action_id\": \"test.bypass\", \"approach_id\": \"tech\", \"strain\": -6}"]
	var adapter := FacetsAiAdapter.make(session, provider)
	var ticket := adapter.propose("mara", FacetsPrincipal.ai("ai", ["mara"]), 0)
	assert_eq(ticket.state, FacetsAiTicket.FAILED)
	assert_eq(session.snapshot().to_dict(), before)
	assert_eq(session.dice_source().draws, 0)


func test_ai_timeout_cancellation_and_late_delivery() -> void:
	var session := _session()
	var provider := FacetsFakeProvider.new()
	provider.hang = true
	var adapter := FacetsAiAdapter.make(session, provider)
	adapter.timeout_ms = 100
	var principal := FacetsPrincipal.ai("ai", ["mara"])
	var ticket := adapter.propose("mara", principal, 0)
	adapter.tick(50)
	assert_true(ticket.is_pending())
	adapter.tick(100)
	assert_eq(ticket.state, FacetsAiTicket.TIMED_OUT)
	assert_error(ticket.result, FacetsError.TIMEOUT)
	adapter.deliver(ticket, JSON.stringify({"actor_id": "mara", "action_id": "test.sneak", "approach_id": "quiet"}))
	assert_eq(ticket.state, FacetsAiTicket.TIMED_OUT, "late delivery ignored")
	var other := adapter.propose("mara", principal, 200)
	adapter.cancel(other)
	assert_eq(other.state, FacetsAiTicket.CANCELLED)
	assert_eq(adapter.pending_count(), 0)


func test_ai_delayed_provider_and_observation_cache() -> void:
	var session := _session()
	var provider := FacetsFakeProvider.new()
	provider.delay_ticks = 2
	var adapter := FacetsAiAdapter.make(session, provider)
	var principal := FacetsPrincipal.ai("ai", ["mara"])
	var ticket := adapter.propose("mara", principal, 0)
	adapter.tick(1)
	assert_true(ticket.is_pending())
	adapter.tick(2)
	assert_eq(ticket.state, FacetsAiTicket.DONE, "delivered after simulated latency")
	adapter.observe("mara", principal)
	adapter.observe("mara", principal)
	assert_eq(adapter.cache_hits, 2, "unchanged observations come from the cache")
	assert_ok(session.apply_host_effects("mara", [W.eff("actor.strain", {"amount": 1})], "change"))
	adapter.observe("mara", principal)
	assert_eq(adapter.cache_hits, 2, "relevant change refreshes the observation")


func test_ai_narration_fallback_never_rerolls() -> void:
	var session := _session([[3, 3]])
	var preview: FacetsCheckPreview = session.preview(W.bypass_request()).value
	var event: FacetsResolutionEvent = session.commit(preview.token, {}, "n1").value
	event = session.choose(event.event_id, event.pending_decision.decision_id, "spend", "n2").value
	var provider := FacetsFakeProvider.new()
	provider.fail_narration = true
	var adapter := FacetsAiAdapter.make(session, provider)
	var draws := session.dice_source().draws
	var before := session.snapshot().to_dict()
	var ticket := adapter.narrate(event, "mara", 0)
	var narration: Dictionary = assert_ok(ticket.result)
	assert_true(bool(narration["fallback"]))
	assert_true(str(narration["text"]).contains("3+3, total 13 against 13 - a success"), str(narration["text"]))
	var retry := adapter.narrate(event, "mara", 10)
	assert_eq(retry.result.value["text"], narration["text"], "retry is deterministic")
	provider.fail_narration = false
	var good := adapter.narrate(event, "mara", 20)
	assert_false(bool(good.result.value["fallback"]))
	assert_eq(session.dice_source().draws, draws, "narration never rerolls")
	assert_eq(session.snapshot().to_dict(), before, "narration never changes state")


func test_ai_npc_policy_uses_offered_options_only() -> void:
	var session := _session([[3, 3]])
	var policy := FacetsNpcPolicy.make(["accept:*", "decline"])
	var preview: FacetsCheckPreview = session.preview(W.bypass_request()).value
	var event: FacetsResolutionEvent = session.commit(preview.token, {}, "p1").value
	assert_eq(policy.choose_option(event.pending_decision), "decline", "no accept option at the Resolve decision")
	var final: FacetsResolutionEvent = assert_ok(policy.resolve(session, event, "npc"))
	assert_eq(final.final_band, "success_with_cost", "accepts the authored cost by priority")
	assert_eq(session.actor_state("mara").resolve, 1)
