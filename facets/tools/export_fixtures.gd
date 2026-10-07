extends SceneTree
## Regenerates the positive transport fixtures under
## tests/fixtures/schemas/*/valid/ from the real implementation, so the JSON
## Schemas are checked against what FACETS actually emits. Usage:
##   godot --headless --path . --script tools/export_fixtures.gd

const ROOT := "res://tests/fixtures/schemas"


func _write(kind: String, name: String, data: Variant) -> void:
	var file := FileAccess.open(ROOT.path_join(kind).path_join("valid").path_join(name + ".json"), FileAccess.WRITE)
	file.store_string(FacetsJson.pretty(data) + "\n")
	file.close()


func _initialize() -> void:
	var demo: NightMarketDemo = NightMarketDemo.create({"store": FacetsMemoryStore.new(), "dice": [[3, 3], [5, 5]], "request_salt": "fixture"}).value
	var preview: FacetsCheckPreview = demo.preview(NightMarketDemo.MARA, "nm.bypass_controller", "tech").value
	var request := demo.session.suggest_request(NightMarketDemo.MARA, "nm.bypass_controller", "tech")
	_write("request", "bypass_controller", request.to_dict())
	_write("request", "minimal", {"actor_id": "demo.mara_vale", "action_id": "nm.ask_guard", "approach_id": "plead"})
	var pending: FacetsResolutionEvent = demo.commit(preview, false).value
	_write("event", "check_pending_resolve", pending.to_dict())
	_write("save", "mara_pending_choice", demo.session.to_save_dict())
	demo.choose("decline")
	var final: FacetsResolutionEvent = demo.choose("accept:trace").value
	_write("event", "check_final_success_with_cost", final.to_dict())
	var offer: FacetsResolutionEvent = demo.offer_passenger_lead().value
	_write("event", "identity_pending", offer.to_dict())
	var identity: FacetsResolutionEvent = demo.choose("accept").value
	_write("event", "identity_final", identity.to_dict())
	var routine: FacetsResolutionEvent = demo.deliver(NightMarketDemo.MARA).value
	_write("event", "check_final_routine", routine.to_dict())
	var journal := demo.session.journal()
	_write("event", "journal_entry_commit", journal[0])
	_write("save", "night_market_after_delivery", demo.session.to_save_dict())
	_write("action", "nm_bypass_controller", demo.registry.get_action("nm.bypass_controller"))
	_write("action", "nm_slip_away", demo.registry.get_action("nm.slip_away"))
	_write("pack", "night_market", (load(NightMarketDemo.PACK_PATH) as FacetsRulesPack).to_dict())
	_write("pack", "core", (load(FacetsRegistry.CORE_PACK_PATH) as FacetsRulesPack).to_dict())
	_write("pack", "combat", (load(FacetsCombat.PACK_PATH) as FacetsRulesPack).to_dict())
	_write("proposal", "bypass_controller", {"actor_id": "demo.mara_vale", "action_id": "nm.bypass_controller", "approach_id": "tech", "tool_ids": ["tool.signal_kit"], "display_text": "Let me get that door."})
	_write("proposal", "minimal", {"actor_id": "demo.iris_kade", "action_id": "nm.help_passenger", "approach_id": "treat"})
	print("export_fixtures: ok")
	quit(0)
