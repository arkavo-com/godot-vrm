extends FacetsTestCase
## T30: all three demo routes, Mara's scripted branches with save/reload
## during the offered choice, the passenger identity trigger, the retained
## consequence in the second scene and the offline fake-AI flow.

const FIXTURE := "res://examples/night_market/fixtures/walkthrough_mara.json"
const MARA := NightMarketDemo.MARA
const IRIS := NightMarketDemo.IRIS


func _demo(dice: Array) -> NightMarketDemo:
	return assert_ok(NightMarketDemo.create({"store": FacetsMemoryStore.new(), "dice": dice}))


func _walkthrough() -> Dictionary:
	return FacetsJson.parse(FileAccess.get_file_as_string(FIXTURE)).value


func _world_value(world: FacetsWorldSnapshot, path: String) -> Variant:
	if path.begins_with("facts."):
		return world.fact_value(path.trim_prefix("facts."))
	var parts := path.split(".")
	match parts[0]:
		"objects":
			return world.object_flag(parts[1], parts[2])
		"counters":
			return world.counters.get(parts[1])
	return null


func _resolve_all(demo: NightMarketDemo, picks: Dictionary) -> FacetsResolutionEvent:
	var event := demo.pending()
	var guard := 0
	while event != null and guard < 5:
		guard += 1
		var decision := event.pending_decision
		var option: String = picks.get(decision.kind, decision.option_ids()[0])
		var reply := demo.choose(option)
		assert_ok(reply, "choose %s" % option)
		event = demo.pending()
		if event == null:
			return reply.value
	return null


func test_t30_mara_branches_with_save_and_reload() -> void:
	var fixture := _walkthrough()
	for branch_name in fixture["branches"]:
		var branch: Dictionary = fixture["branches"][branch_name]
		var demo := _demo([fixture["dice"]])
		var preview: FacetsCheckPreview = assert_ok(demo.preview(MARA, fixture["action_id"], fixture["approach_id"]))
		for key in fixture["expected_preview"]:
			assert_eq(preview.get(key), fixture["expected_preview"][key], "%s preview %s" % [branch_name, key])
		var event: FacetsResolutionEvent = assert_ok(demo.commit(preview, false))
		for key in fixture["expected_roll"]:
			assert_eq(event.base[key], fixture["expected_roll"][key], "%s roll %s" % [branch_name, key])
		assert_eq(event.pending_decision.kind, fixture["first_decision"])
		# Save during the offered choice, then reload into a fresh demo.
		var saved := FacetsMemoryStore.new()
		assert_ok(demo.save_game(saved))
		var reloaded := _demo([])
		assert_ok(reloaded.load_game(saved, FacetsDiceSource.fixed([])))
		var pending := reloaded.pending()
		assert_true(pending != null, "%s pending after reload" % branch_name)
		assert_eq(pending.dice, fixture["dice"], "%s dice retained" % branch_name)
		var final: FacetsResolutionEvent
		for choice in branch["choices"]:
			final = assert_ok(reloaded.choose(choice), "%s %s" % [branch_name, choice])
		assert_true(final.is_final(), "%s finalized" % branch_name)
		assert_eq(final.final_band, branch["final_band"], "%s band" % branch_name)
		assert_eq(int(final.evaluation["total"]), int(branch["final_total"]), "%s total" % branch_name)
		var world := reloaded.session.snapshot()
		assert_eq(world.actor(MARA).resolve, int(branch["resolve_after"]), "%s Resolve" % branch_name)
		for path in branch["world"]:
			assert_eq(_world_value(world, path), branch["world"][path], "%s %s" % [branch_name, path])
		assert_eq(reloaded.session.dice_source().draws, 0, "%s no reroll after reload" % branch_name)


func test_t30_three_routes_reach_the_hall_and_deliver() -> void:
	var routes := [
		{"actor": MARA, "action": "nm.ask_guard", "approach": "plead", "dice": [6, 6], "picks": {"benefit": "route"}},
		{"actor": MARA, "action": "nm.bypass_controller", "approach": "tech", "dice": [5, 5], "picks": {"resolve": "decline"}},
		{"actor": MARA, "action": "nm.rooftop_entry", "approach": "climb", "dice": [6, 5], "picks": {"resolve": "decline"}},
	]
	for route in routes:
		var demo := _demo([route["dice"]])
		var preview: FacetsCheckPreview = assert_ok(demo.preview(route["actor"], route["action"], route["approach"]), route["action"])
		assert_false(str(preview.stakes.get("success", "")).is_empty(), "stakes visible before commitment")
		assert_false(str(preview.stakes.get("failure", "")).is_empty())
		var event: FacetsResolutionEvent = assert_ok(demo.commit(preview, false))
		if event.is_pending():
			event = _resolve_all(demo, route["picks"])
		assert_true(FacetsRules.is_success_band(event.final_band), "%s succeeds" % route["action"])
		assert_eq(demo.actor(route["actor"]).zone_id, "hall", "%s reaches the hall" % route["action"])
		assert_ok(demo.deliver(route["actor"]), "deliver after %s" % route["action"])
		var world := demo.session.snapshot()
		assert_eq(world.object_flag("package", "delivered"), true)
		assert_eq(world.object_flag("package", "late"), false, "on time via %s" % route["action"])
		assert_eq(demo.actor(route["actor"]).growth, 1, "one small milestone")
		assert_error(demo.session.award_milestone(route["actor"], "nm.delivery", "small", "nm.chapter1.package_delivered", demo.host), FacetsError.ALREADY_USED)


func test_t30_routes_have_their_own_prerequisites() -> void:
	var demo := _demo([[1, 1]])
	assert_ok(demo.session.apply_host_effects(MARA, [{"op": "actor.item_add", "params": {"item_id": "tool.signal_kit", "amount": -1}}, {"op": "actor.item_add", "params": {"item_id": "item.scrap_wire", "amount": -1}}], "lose tools", demo.host))
	assert_error(demo.preview(MARA, "nm.bypass_controller", "tech"), FacetsError.INELIGIBLE, "controller route needs a tool")
	assert_ok(demo.session.apply_host_effects(MARA, [{"op": "actor.condition_add", "params": {"condition_id": "core.injured"}}], "hurt", demo.host))
	assert_error(demo.preview(MARA, "nm.rooftop_entry", "climb"), FacetsError.INELIGIBLE, "rooftop needs an uninjured climber")
	var event: FacetsResolutionEvent = assert_ok(demo.commit(demo.preview(MARA, "nm.ask_guard", "plead").value, false))
	_resolve_all(demo, {"resolve": "decline", "cost": "decline"})
	assert_error(demo.preview(MARA, "nm.ask_guard", "plead"), FacetsError.INELIGIBLE, "Rook raised the alarm")
	assert_true(event != null)


func test_t30_passenger_lead_misses_window_and_awards_once() -> void:
	var fixture: Dictionary = _walkthrough()["passenger"]
	var demo := _demo([[5, 5]])
	assert_eq(demo.actor(MARA).resolve, int(fixture["resolve_before"]))
	var offer: FacetsResolutionEvent = assert_ok(demo.offer_passenger_lead())
	assert_eq(offer.pending_decision.kind, "identity")
	var accepted: FacetsResolutionEvent = assert_ok(demo.choose("accept"))
	assert_eq(int(accepted.record["amount"]), 1)
	assert_eq(demo.actor(MARA).resolve, int(fixture["resolve_after"]))
	assert_eq(demo.session.snapshot().fact_value("fact.window_missed"), fixture["window_missed"])
	assert_true(demo.actor(MARA).knows("fact.passenger_lead"), "Tamsin's lead learned")
	assert_ok(demo.offer_passenger_lead())
	var duplicate: FacetsResolutionEvent = assert_ok(demo.choose("accept"))
	assert_eq(int(duplicate.record["amount"]), int(fixture["duplicate_award"]), "eligible Resolve awarded once")
	# Delivery after missing the window is late.
	var event: FacetsResolutionEvent = assert_ok(demo.commit(demo.preview(MARA, "nm.bypass_controller", "tech").value, false))
	if event.is_pending():
		_resolve_all(demo, {"resolve": "decline"})
	assert_ok(demo.deliver(MARA))
	assert_eq(demo.session.snapshot().object_flag("package", "late"), true, "missed the delivery window")


func test_t30_retained_consequences_in_second_scene() -> void:
	var demo := _demo([[3, 3]])
	assert_ok(demo.commit(demo.preview(MARA, "nm.bypass_controller", "tech").value, false))
	assert_ok(demo.choose("decline"))
	assert_ok(demo.choose("accept:trace"))
	assert_ok(demo.offer_passenger_lead())
	assert_ok(demo.choose("accept"))
	assert_ok(demo.deliver(MARA))
	assert_ok(demo.go_to_clinic())
	var lines := demo.consequences()
	assert_true(lines.any(func(l: String) -> bool: return l.contains("trace")), "trace consequence shown")
	assert_true(lines.any(func(l: String) -> bool: return l.contains("late")), "late delivery shown")
	var slip: FacetsCheckPreview = assert_ok(demo.preview(MARA, "nm.slip_away", "sneak"))
	assert_eq(slip.modifier_applied, -1, "grid trace makes slipping away harder")
	var calm: FacetsCheckPreview = assert_ok(demo.preview(IRIS, "nm.calm_doctor", "talk"))
	assert_eq(calm.modifier_applied, -1, "late package makes the doctor harder to settle")
	assert_ok(demo.preview(MARA, "nm.follow_lead", "search"), "lead unlocks a new action")
	assert_error(demo.preview(IRIS, "nm.follow_lead", "search"), FacetsError.INELIGIBLE, "only Mara knows the lead")
	assert_error(demo.preview(MARA, "nm.ask_guard", "plead"), FacetsError.INELIGIBLE, "gate actions belong to the first scene")
	# The consequence survives save/load.
	var saved := FacetsMemoryStore.new()
	assert_ok(demo.save_game(saved))
	var reloaded := _demo([])
	assert_ok(reloaded.load_game(saved))
	assert_eq((reloaded.preview(MARA, "nm.slip_away", "sneak").value as FacetsCheckPreview).modifier_applied, -1)


func test_t30_iris_steadies_mara_after_a_fall() -> void:
	var demo := _demo([[1, 1]])
	assert_ok(demo.commit(demo.preview(MARA, "nm.rooftop_entry", "climb").value, false))
	_resolve_all(demo, {"resolve": "decline"})
	assert_eq(demo.actor(MARA).strain, 2, "fall")
	assert_ok(demo.use_steady_voice(IRIS, MARA))
	assert_eq(demo.actor(MARA).strain, 0)
	assert_error(demo.use_steady_voice(IRIS, MARA), FacetsError.USAGE_LIMIT)
	assert_error(demo.preview(MARA, "nm.rooftop_entry", "climb"), FacetsError.INELIGIBLE, "the crates collapsed")


func test_t30_reset_keeps_profile_records() -> void:
	var demo := _demo([[5, 5]])
	assert_ok(demo.commit(demo.preview(MARA, "nm.bypass_controller", "tech").value, false))
	_resolve_all(demo, {"resolve": "decline"})
	assert_ok(demo.deliver(MARA))
	assert_eq(demo.actor(MARA).profile["accomplishments"], ["Delivered the sealed package through the Night Market"])
	assert_ok(demo.new_journey({"store": FacetsMemoryStore.new(), "dice": []}))
	var mara := demo.actor(MARA)
	assert_eq(mara.growth, 0, "new journey state")
	assert_eq(demo.session.snapshot().object_flag("package", "delivered"), false)
	assert_eq(mara.profile["accomplishments"], ["Delivered the sealed package through the Night Market"], "profile not silently erased")


func test_t30_offline_fake_ai_flow() -> void:
	var demo := _demo([[5, 5]])
	var provider := FacetsFakeProvider.new()
	provider.scripted = [JSON.stringify({"actor_id": MARA, "action_id": "nm.bypass_controller", "approach_id": "tech", "tool_ids": ["tool.signal_kit"], "display_text": "Let me get that door."})]
	var adapter := FacetsAiAdapter.make(demo.session, provider)
	var principal := FacetsPrincipal.ai("fake_ai", [MARA])
	var ticket := adapter.propose(MARA, principal, 0)
	var proposal: Dictionary = assert_ok(ticket.result)
	var preview: FacetsCheckPreview = assert_ok(demo.session.preview(proposal["request"], principal))
	var event: FacetsResolutionEvent = assert_ok(demo.commit(preview, false))
	if event.is_pending():
		event = _resolve_all(demo, {"resolve": "decline"})
	assert_eq(event.final_band, "success")
	var narration := adapter.narrate(event, MARA, 0)
	assert_eq(narration.state, FacetsAiTicket.DONE)
	assert_false(bool(narration.result.value["fallback"]))
	var auto := FacetsFakeProvider.new()
	var auto_adapter := FacetsAiAdapter.make(demo.session, auto)
	var suggestion := auto_adapter.propose(IRIS, FacetsPrincipal.ai("fake_ai", [IRIS]), 0)
	assert_ok(suggestion.result, "fake provider picks an available action deterministically")
	assert_eq(provider.observations[0]["actor"]["id"], MARA)
	var sent := FacetsJson.canonical(provider.observations[0])
	assert_false(sent.contains("fact.rook_paid") or sent.contains("takes money from the fixer"), "Rook's private fact never sent")
	assert_false(sent.contains("pump house"), "unlearned private facts never sent")


func test_t30_fixed_dice_debug_only_and_ui_smoke() -> void:
	assert_false(NightMarketDemo.fixed_dice_allowed(false), "absent from release exports")
	assert_true(NightMarketDemo.fixed_dice_allowed(true))
	var tree := Engine.get_main_loop() as SceneTree
	var scene: Control = (load("res://examples/night_market/night_market.tscn") as PackedScene).instantiate()
	tree.root.add_child(scene)
	assert_true(scene.demo != null, "UI started a journey offline")
	scene._on_preview("nm.bypass_controller", "tech")
	assert_true(scene._preview != null, "preview rendered")
	assert_true(scene._preview_text.text.contains("Odds"), "odds shown before commitment")
	assert_eq(scene._dice_row.get_child_count() > 0, NightMarketDemo.fixed_dice_allowed(), "fixed dice controls only when allowed")
	scene.demo.queue_fixed_dice(Vector2i(3, 3))
	scene._on_commit()
	assert_true(scene.demo.pending() != null, "choice buttons offered")
	assert_true(scene._choices.get_child_count() >= 3, "Resolve options plus walk away")
	scene.demo.choose("spend")
	assert_eq(scene.demo.session.snapshot().object_flag("service_door", "open"), true)
	scene.get_parent().remove_child(scene)
	scene.free()
