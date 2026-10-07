@tool
class_name FacetsSession
extends RefCounted
## Transactional FACETS session: one isolated world, random stream, journal
## and persistence port.
##
## State machine for checks: preview -> committed/rolled -> pending
## decisions -> finalized. Preview is free to discard. A committed check is
## never canceled into a free reroll. While a check or identity choice is
## pending the world revision is held: state-changing commands are rejected
## with a retryable PENDING_DECISION error until the choice resolves
## (implementation decision D-005).
##
## Every state change is journaled as low-level ops (see [FacetsReducer]) and
## durably written through the attached [FacetsSessionStore] before it
## becomes visible. Presentation signals fire only after that write.
## Calls are expected from a single thread.

## Emitted after a transaction is durably committed. Never changes state.
signal published(event: FacetsResolutionEvent)

const SAVE_KIND := "facets.session"
const JOURNAL_FORMAT := 1
const COMMIT_OPTIONS: Array[String] = ["push"]
## Previews kept in memory so stale tokens are reported as stale, not unknown.
const PREVIEW_CACHE := 64

var registry: FacetsRegistry
var session_id: String = "session"
## Principal used when a call does not pass one. Hosts that expose sessions
## to remote players or AI must always pass an explicit principal.
var default_principal: FacetsPrincipal = FacetsPrincipal.host("local")

var _world: FacetsWorldSnapshot
var _dice: FacetsDiceSource
var _store: FacetsSessionStore = null
var _checkpoint: Dictionary = {}
var _journal: Array = []
var _sequence: int = 0
var _event_counter: int = 0
var _pending: Dictionary = {}
var _events: Dictionary = {}
var _requests: Dictionary = {}
var _previews: Dictionary = {}
var _preview_order: Array[String] = []
var _ports: Array = []


## Creates a session owning [param world] (copied). Options:
##   "seed": int        session-owned RNG seed (default 0)
##   "dice": FacetsDiceSource   injected dice (tests, conformance)
##   "store": FacetsSessionStore   persistence port; initial state is written
##   "session_id": String
static func create(p_registry: FacetsRegistry, world: FacetsWorldSnapshot, options: Dictionary = {}) -> FacetsReply:
	var session := FacetsSession.new()
	session.registry = p_registry
	session.session_id = str(options.get("session_id", "session"))
	session._world = world.copy()
	session._dice = options.get("dice") if options.get("dice") is FacetsDiceSource else FacetsDiceSource.seeded(int(options.get("seed", 0)))
	session._checkpoint = {"sequence": 0, "state": session._world.to_dict()}
	var store: Variant = options.get("store")
	if store is FacetsSessionStore:
		session._store = store
		var written: FacetsReply = store.write_save(session.to_save_dict())
		if not written.ok:
			return written
	return FacetsReply.success(session)


# --- Read-only accessors -----------------------------------------------------

func snapshot() -> FacetsWorldSnapshot:
	return _world.copy()


func actor_state(actor_id: String) -> FacetsActorState:
	var state := _world.actor(actor_id)
	return state.copy() if state != null else null


func revision() -> int:
	return _world.revision


func last_sequence() -> int:
	return _sequence


func journal() -> Array:
	return _journal.duplicate(true)


func has_pending() -> bool:
	return not _pending.is_empty()


func pending_event() -> FacetsResolutionEvent:
	return FacetsResolutionEvent.from_record(_pending) if has_pending() else null


func dice_source() -> FacetsDiceSource:
	return _dice


func store() -> FacetsSessionStore:
	return _store


func is_durable() -> bool:
	return _store != null


func add_presentation_port(port: Object) -> void:
	if port != null and port.has_method("present") and not _ports.has(port):
		_ports.append(port)


func remove_presentation_port(port: Object) -> void:
	_ports.erase(port)


func get_event(event_id: String) -> FacetsReply:
	if has_pending() and str(_pending.get("event_id", "")) == event_id:
		return FacetsReply.success(FacetsResolutionEvent.from_record(_pending))
	if _events.has(event_id):
		return FacetsReply.success(FacetsResolutionEvent.from_record(_events[event_id]))
	return FacetsReply.fail(FacetsError.UNKNOWN_ID, "Unknown event.", "event_id")


## Every registered action/approach for an actor with availability and the
## suggested request (relevant carried tools filled in). Unavailable entries
## carry only visible reasons.
func catalog(actor_id: String, principal: FacetsPrincipal = null) -> Array:
	var result: Array = []
	var actor := _world.actor(actor_id)
	if actor == null:
		return result
	for action_id in registry.action_ids():
		var action := registry.get_action(action_id)
		for approach in action.get("approaches", []):
			var request := suggest_request(actor_id, action_id, str(approach["id"]))
			var plan := FacetsCheckPlanner.build(registry, _world, request, _principal(principal))
			result.append({
				"action_id": action_id,
				"approach_id": str(approach["id"]),
				"label": "%s (%s + %s)" % [action.get("display_name", action_id), approach["facet"], approach["skill"]],
				"available": plan.ok,
				"reason": "" if plan.ok else plan.error.message,
				"request": request.to_dict(),
			})
	return result


## Request with the actor's carried tools that the action cares about.
func suggest_request(actor_id: String, action_id: String, approach_id: String) -> FacetsActionRequest:
	var request := FacetsActionRequest.make(actor_id, action_id, approach_id)
	var actor := _world.actor(actor_id)
	var action := registry.get_action(action_id)
	if actor == null or action.is_empty():
		return request
	var tools: Array[String] = []
	for tool_id in action.get("required_tools", []) + action.get("useful_tools", []):
		if actor.item_count(tool_id) > 0 and not tools.has(tool_id):
			tools.append(tool_id)
	for tool_id in action.get("required_tools", []):
		if actor.item_count(tool_id) <= 0:
			for substitute in action.get("consumable_substitutes", []):
				if actor.item_count(substitute) > 0 and not tools.has(substitute):
					tools.append(substitute)
	request.with_tools(tools)
	return request


# --- Checks --------------------------------------------------------------------

## Validates authority and eligibility and returns an immutable preview with
## exact odds. Spends nothing, draws no dice.
func preview(request: FacetsActionRequest, principal: FacetsPrincipal = null) -> FacetsReply:
	if has_pending():
		return FacetsReply.fail(FacetsError.PENDING_DECISION, "Resolve the pending choice first.", "", true)
	var who := _principal(principal)
	var built := FacetsCheckPlanner.build(registry, _world, request, who)
	if not built.ok:
		return built
	var plan: Dictionary = built.value
	var token := "pv-" + FacetsJson.digest({"session": session_id, "principal": who.principal_id, "request": plan["request"], "action": plan["action_digest"], "revision": plan["revision"]}).substr(0, 40)
	if not _previews.has(token):
		_preview_order.append(token)
	_previews[token] = {"plan": plan, "principal": who}
	while _preview_order.size() > PREVIEW_CACHE:
		_previews.erase(_preview_order.pop_front())
	return FacetsReply.success(FacetsCheckPlanner.to_preview(plan, token))


## Revalidates the preview, pays Push, draws dice once and durably records
## the commitment. Returns the pending record (with a decision) or the final
## event. Options: {"push": bool}.
func commit(preview_token: String, options: Dictionary, request_id: String) -> FacetsReply:
	if request_id.is_empty():
		return FacetsReply.fail(FacetsError.MISSING_REQUEST_ID, "commit needs a request_id.", "request_id")
	var payload := {"command": "commit", "token": preview_token, "options": FacetsJson.normalize(options)}
	var duplicate := _idempotent(request_id, payload)
	if duplicate != null:
		return duplicate
	if has_pending():
		return FacetsReply.fail(FacetsError.PENDING_DECISION, "Resolve the pending choice first.", "", true)
	if not _previews.has(preview_token):
		return FacetsReply.fail(FacetsError.UNKNOWN_PREVIEW, "Unknown or expired preview; preview again.", "preview_token")
	var binding: Dictionary = _previews[preview_token]
	var plan: Dictionary = binding["plan"]
	if int(plan["revision"]) != _world.revision or registry.action_digest(plan["action_id"]) != plan["action_digest"]:
		_previews.erase(preview_token)
		return FacetsReply.fail(FacetsError.STALE_PREVIEW, "The situation changed since this preview; preview again.", "preview_token", true)
	for key in options:
		if not COMMIT_OPTIONS.has(str(key)):
			return FacetsReply.fail(FacetsError.UNKNOWN_FIELD, "Unknown commit option '%s'." % key, "options.%s" % key)
	var push := bool(options.get("push", false))
	if push and not bool(plan["push_available"]):
		return FacetsReply.fail(FacetsError.PUSH_NOT_ALLOWED, str(plan["push_note"]), "options.push")
	var fresh := FacetsCheckPlanner.build(registry, _world, FacetsActionRequest.from_dict(plan["request"]), binding["principal"])
	if not fresh.ok:
		return fresh

	var staged := _world.copy()
	var txn := FacetsTxn.begin(staged)
	var counter := _event_counter + 1
	var event_id := "evt-%06d" % counter
	var actor_id: String = plan["actor_id"]
	var action := registry.get_action(plan["action_id"])
	var deltas := {"strain": 0, "resolve": 0}
	if push:
		deltas["strain"] = txn.add_strain(actor_id, FacetsRules.PUSH_STRAIN)
	var substitution: Dictionary = plan["tool_substitution"]
	if not substitution.is_empty():
		txn.add_item(actor_id, substitution["consumable_id"], -1)
		txn.increment_usage(actor_id, FacetsTalents.usage_key(substitution["talent_id"], staged.scene_id))
	var second_look: Dictionary = plan["second_look"]
	if not second_look.is_empty():
		txn.increment_usage(actor_id, FacetsTalents.usage_key(second_look["talent_id"], staged.scene_id))
		txn.increment_usage(actor_id, second_look["evidence_key"])
		txn.advance_clock(int(second_look["interval"]))
	txn.advance_clock(int(action.get("clock_cost", 0)))
	if txn.failed():
		return FacetsReply.failure(txn.error)

	var rng_before := _dice.get_state()
	var check := FacetsCheckInput.make(int(plan["facet_rating"]), int(plan["skill_rank"]), int(plan["target"]), bool(plan["allows_costly_success"]))
	check.facet_id = plan["facet_id"]
	check.skill_id = plan["skill_id"]
	var dice: Array = []
	var base: Dictionary
	if bool(plan["routine"]):
		base = {"routine": true, "dice": [], "facet": check.facet, "skill": check.skill, "target": check.target, "total": 0, "margin": 0, "band": FacetsRules.BAND_SUCCESS}
	else:
		var pair := _dice.roll_pair()
		if pair == Vector2i.ZERO:
			_dice.set_state(rng_before)
			return FacetsReply.fail(FacetsError.DICE_UNAVAILABLE, "No dice are available.", "", true)
		dice = [pair.x, pair.y]
		base = FacetsResolver.evaluate_with_sum(check, pair, int(plan["modifier_raw"]), push, false).to_dict()
	var record := {
		"event_id": event_id,
		"kind": "check",
		"status": FacetsResolutionEvent.STATUS_PENDING,
		"actor_id": actor_id,
		"action_id": plan["action_id"],
		"action_version": plan["action_version"],
		"action_digest": plan["action_digest"],
		"action": action,
		"approach_id": str(plan["approach"]["id"]),
		"approach": plan["approach"],
		"request": plan["request"],
		"routine": bool(plan["routine"]),
		"push": push,
		"dice": dice,
		"check": check.to_dict(),
		"modifier_raw": plan["modifier_raw"],
		"modifier_applied": plan["modifier_applied"],
		"modifier_lines": plan["modifier_lines"],
		"target_explanation": plan["target_explanation"],
		"base": base,
		"evaluation": base,
		"resolve_available": bool(plan["resolve_available"]),
		"tool_substitution": substitution,
		"second_look": second_look,
		"helper_id": plan["helper_id"],
		"objective_id": plan["objective_id"],
		"fingerprint": plan["fingerprint"],
		"lock_key": plan["lock_key"],
		"scene_id": staged.scene_id,
		"choices": [],
		"decision": {},
		"commit_ops": txn.ops.duplicate(true),
		"resource_deltas": deltas,
		"visibility": "public",
	}
	var entries: Array = []
	var commit_entry := _stage_entry(staged, entries, "check.commit", event_id, txn.ops, {"actor_id": actor_id, "action_id": plan["action_id"], "approach_id": record["approach_id"], "dice": dice, "push": push, "routine": record["routine"]})
	record["before_revision"] = commit_entry["before_revision"]
	record["after_revision"] = commit_entry["after_revision"]
	record["decision"] = _next_decision(record, staged)
	var pending := {}
	var new_events := {}
	if record["decision"].is_empty():
		var final := _finalize_check(record, staged, entries)
		if not final.ok:
			_dice.set_state(rng_before)
			return final
		record = final.value
		new_events[event_id] = record
	else:
		pending = record
	return _persist_entries(staged, entries, pending, new_events, request_id, payload, record, counter, rng_before)


## Records a choice for the pending decision. Finalizes atomically when no
## decisions remain.
func choose(event_id: String, decision_id: String, option_id: String, request_id: String) -> FacetsReply:
	if request_id.is_empty():
		return FacetsReply.fail(FacetsError.MISSING_REQUEST_ID, "choose needs a request_id.", "request_id")
	var payload := {"command": "choose", "event_id": event_id, "decision_id": decision_id, "option_id": option_id}
	var duplicate := _idempotent(request_id, payload)
	if duplicate != null:
		return duplicate
	var check_pending := _require_pending(event_id)
	if not check_pending.ok:
		return check_pending
	var record: Dictionary = _pending.duplicate(true)
	var decision: Dictionary = record["decision"]
	if str(decision.get("decision_id", "")) != decision_id:
		return FacetsReply.fail(FacetsError.INVALID_DECISION, "That decision is not open.", "decision_id")
	if not FacetsPendingDecision.from_dict(decision).option_ids().has(option_id):
		return FacetsReply.fail(FacetsError.INVALID_DECISION, "That option was not offered.", "option_id")
	_advance(record, option_id, false)
	return _settle(record, request_id, payload)


## Abandons a pending event: declines Resolve and costly success (failure for
## an unaccepted costly band), never refunds Push, and picks only a
## predeclared safe default benefit. Otherwise the event stays pending.
func abandon(event_id: String, request_id: String) -> FacetsReply:
	if request_id.is_empty():
		return FacetsReply.fail(FacetsError.MISSING_REQUEST_ID, "abandon needs a request_id.", "request_id")
	var payload := {"command": "abandon", "event_id": event_id}
	var duplicate := _idempotent(request_id, payload)
	if duplicate != null:
		return duplicate
	var check_pending := _require_pending(event_id)
	if not check_pending.ok:
		return check_pending
	var record: Dictionary = _pending.duplicate(true)
	while not record["decision"].is_empty():
		var decision: Dictionary = record["decision"]
		var option_id := ""
		match str(decision["kind"]):
			FacetsPendingDecision.KIND_RESOLVE, FacetsPendingDecision.KIND_COST:
				option_id = "decline"
			FacetsPendingDecision.KIND_IDENTITY:
				option_id = "reject"
			FacetsPendingDecision.KIND_BENEFIT:
				var safe := str(record["action"].get("default_benefit_id", ""))
				if safe.is_empty() or not FacetsPendingDecision.from_dict(decision).option_ids().has(safe):
					return FacetsReply.fail(FacetsError.DECISION_REQUIRED, "This benefit needs an explicit choice; it stays pending.", "decision_id")
				option_id = safe
		_advance(record, option_id, true)
	return _settle(record, request_id, payload)


func _require_pending(event_id: String) -> FacetsReply:
	if has_pending() and str(_pending["event_id"]) == event_id:
		return FacetsReply.success(true)
	if _events.has(event_id):
		return FacetsReply.fail(FacetsError.NOT_PENDING, "That decision has already been resolved.", "event_id")
	return FacetsReply.fail(FacetsError.UNKNOWN_ID, "Unknown event.", "event_id")


func _advance(record: Dictionary, option_id: String, abandoned: bool) -> void:
	var decision: Dictionary = record["decision"]
	var choice := {"decision_id": decision["decision_id"], "kind": decision["kind"], "option_id": option_id}
	if abandoned:
		choice["abandoned"] = true
	record["choices"].append(choice)
	if str(decision["kind"]) == FacetsPendingDecision.KIND_BENEFIT:
		record["benefit_selected"] = decision["frozen_options"][option_id]
	record["decision"] = {}
	if str(record["kind"]) == "check":
		record["decision"] = _next_decision(record, _world)
		record["evaluation"] = _current_evaluation(record)


## Persists an updated pending record, or finalizes when no decision remains.
func _settle(record: Dictionary, request_id: String, payload: Dictionary) -> FacetsReply:
	if not record["decision"].is_empty():
		return _persist_entries(_world, [], record, {}, request_id, payload, record, _event_counter, null)
	var staged := _world.copy()
	var entries: Array = []
	var final: FacetsReply
	if str(record["kind"]) == "identity":
		final = _finalize_identity(record, staged, entries)
	else:
		final = _finalize_check(record, staged, entries)
	if not final.ok:
		return final
	var final_record: Dictionary = final.value
	return _persist_entries(staged, entries, {}, {final_record["event_id"]: final_record}, request_id, payload, final_record, _event_counter, null)


func _choice(record: Dictionary, kind: String) -> String:
	for choice in record.get("choices", []):
		if str(choice.get("kind", "")) == kind:
			return str(choice.get("option_id", ""))
	return ""


func _current_evaluation(record: Dictionary) -> Dictionary:
	if bool(record.get("routine", false)):
		return record["base"].duplicate(true)
	var check := FacetsCheckInput.from_dict(record["check"])
	var dice := Vector2i(int(record["dice"][0]), int(record["dice"][1]))
	var spent := _choice(record, FacetsPendingDecision.KIND_RESOLVE) == "spend"
	return FacetsResolver.evaluate_with_sum(check, dice, int(record["modifier_raw"]), bool(record["push"]), spent).to_dict()


func _final_band(record: Dictionary) -> String:
	var band := str(_current_evaluation(record)["band"])
	if band == FacetsRules.BAND_COSTLY_OFFER:
		return FacetsRules.BAND_SUCCESS_WITH_COST if _choice(record, FacetsPendingDecision.KIND_COST).begins_with("accept:") else FacetsRules.BAND_FAILURE
	return band


## Decision order: Resolve (when legal and it could matter), then the costly
## offer, then a strong-benefit selection. Each decision is frozen.
func _next_decision(record: Dictionary, world: FacetsWorldSnapshot) -> Dictionary:
	if bool(record.get("routine", false)):
		return {}
	var event_id := str(record["event_id"])
	var evaluation := _current_evaluation(record)
	var band := str(evaluation["band"])
	var actor := world.actor(str(record["actor_id"]))
	var action: Dictionary = record["action"]
	if _choice(record, FacetsPendingDecision.KIND_RESOLVE).is_empty() and bool(record["resolve_available"]) and actor.resolve >= FacetsRules.RESOLVE_COST and band != FacetsRules.BAND_STRONG:
		var check := FacetsCheckInput.from_dict(record["check"])
		var upgraded := FacetsResolver.evaluate_with_sum(check, Vector2i(int(record["dice"][0]), int(record["dice"][1])), int(record["modifier_raw"]), bool(record["push"]), true)
		var changes := upgraded.band != band
		return {
			"event_id": event_id,
			"decision_id": "%s:resolve" % event_id,
			"kind": FacetsPendingDecision.KIND_RESOLVE,
			"prompt": "Total %d vs %d (%s). Spend 1 Resolve for +2? %s" % [int(evaluation["total"]), int(evaluation["target"]), _band_label(band), ("It would become %s." % _band_label(upgraded.band)) if changes else "It would not change the result."],
			"options": [
				{"id": "spend", "label": "Spend 1 Resolve: total %d, %s" % [upgraded.total, _band_label(upgraded.band)], "band_after": upgraded.band, "changes_band": changes},
				{"id": "decline", "label": "Keep Resolve: total %d, %s" % [int(evaluation["total"]), _band_label(band)], "band_after": band, "changes_band": false},
			],
		}
	if band == FacetsRules.BAND_COSTLY_OFFER and _choice(record, FacetsPendingDecision.KIND_COST).is_empty():
		var options: Array = []
		for cost in action.get("costly_options", []):
			options.append({"id": "accept:%s" % cost["id"], "label": "Accept: %s" % cost.get("label", cost["id"]), "band_after": FacetsRules.BAND_SUCCESS_WITH_COST})
		var failure_text := str(action.get("stakes", {}).get("failure", "")).strip_edges()
		options.append({"id": "decline", "label": "Decline: fail%s" % ((" (%s)" % failure_text) if not failure_text.is_empty() else ""), "band_after": FacetsRules.BAND_FAILURE})
		return {
			"event_id": event_id,
			"decision_id": "%s:cost" % event_id,
			"kind": FacetsPendingDecision.KIND_COST,
			"prompt": "Near miss (margin %d). Succeed at a cost, or fail?" % int(evaluation["margin"]),
			"options": options,
		}
	if band == FacetsRules.BAND_STRONG and _choice(record, FacetsPendingDecision.KIND_BENEFIT).is_empty() and not record.has("benefit_selected"):
		var frozen := {}
		var options: Array = []
		var all: Array = action.get("strong_benefits", []).duplicate(true)
		all.append_array(FacetsTalents.benefit_options(registry, world, actor, action, str(record["approach"]["skill"])))
		for option in all:
			frozen[str(option["id"])] = option
			options.append({"id": str(option["id"]), "label": str(option.get("label", option["id"])), "requires_consent": bool(option.get("requires_consent", false))})
		if options.is_empty():
			return {}
		if options.size() == 1 and not bool(options[0]["requires_consent"]):
			record["benefit_selected"] = frozen[options[0]["id"]]
			record["choices"].append({"decision_id": "%s:benefit" % event_id, "kind": FacetsPendingDecision.KIND_BENEFIT, "option_id": options[0]["id"], "auto": true})
			return {}
		return {
			"event_id": event_id,
			"decision_id": "%s:benefit" % event_id,
			"kind": FacetsPendingDecision.KIND_BENEFIT,
			"prompt": "Strong success. Choose one benefit.",
			"options": options,
			"frozen_options": frozen,
		}
	return {}


static func _band_label(band: String) -> String:
	match band:
		FacetsRules.BAND_FAILURE:
			return "failure"
		FacetsRules.BAND_COSTLY_OFFER:
			return "costly-success offer"
		FacetsRules.BAND_SUCCESS_WITH_COST:
			return "success with cost"
		FacetsRules.BAND_SUCCESS:
			return "success"
		FacetsRules.BAND_STRONG:
			return "strong success"
	return band


## Validates and applies every effect to the staged world, then records the
## finalize entry. Any rejection leaves the live state and pending record
## untouched.
func _finalize_check(record: Dictionary, staged: FacetsWorldSnapshot, entries: Array) -> FacetsReply:
	var txn := FacetsTxn.begin(staged)
	var actor_id := str(record["actor_id"])
	var action: Dictionary = record["action"]
	var band := _final_band(record)
	var evaluation := _current_evaluation(record)
	var request: Dictionary = record["request"]
	var context := FacetsOpContext.make(staged, registry, actor_id)
	context.event_id = str(record["event_id"])
	for item in request.get("target_ids", []):
		context.target_ids.append(str(item))
	for item in request.get("tool_ids", []):
		context.tool_ids.append(str(item))
	if not str(record.get("helper_id", "")).is_empty():
		context.helper_ids.append(str(record["helper_id"]))
	context.tags = {"fear": bool(action.get("fear", false))}
	var deltas: Dictionary = record.get("resource_deltas", {}).duplicate(true)
	if _choice(record, FacetsPendingDecision.KIND_RESOLVE) == "spend":
		deltas["resolve"] = txn.add_resolve(actor_id, -FacetsRules.RESOLVE_COST)
	var labels: Array[String] = []
	var notes: Array = []
	var effect_groups: Array = []
	if FacetsRules.is_success_band(band):
		var success_tags := context.tags.duplicate()
		if not record.get("tool_substitution", {}).is_empty():
			success_tags["expires"] = "scene_end"
			notes.append({"talent_id": record["tool_substitution"]["talent_id"], "note": "Improvised repair expires at scene end."})
		effect_groups.append([action.get("success_effects", []), success_tags])
	if band == FacetsRules.BAND_SUCCESS_WITH_COST:
		var cost_id := _choice(record, FacetsPendingDecision.KIND_COST).trim_prefix("accept:")
		for cost in action.get("costly_options", []):
			if str(cost["id"]) == cost_id:
				effect_groups.append([cost.get("effects", []), context.tags])
	if band == FacetsRules.BAND_STRONG and record.has("benefit_selected"):
		var benefit: Dictionary = record["benefit_selected"]
		effect_groups.append([benefit.get("effects", []), context.tags])
		if benefit.has("talent_id"):
			txn.increment_usage(actor_id, FacetsTalents.usage_key(str(benefit["talent_id"]), staged.scene_id))
			notes.append({"talent_id": benefit["talent_id"], "note": str(benefit.get("label", ""))})
	if band == FacetsRules.BAND_FAILURE:
		effect_groups.append([action.get("failure_effects", []), context.tags])
	for group in effect_groups:
		context.tags = group[1]
		for ref in group[0]:
			if not registry.operations.apply_effect(ref, context, txn):
				return FacetsReply.failure(FacetsError.make(FacetsError.EFFECT_REJECTED, "An effect could not be applied; nothing changed.", "", false).with_detail(str(txn.error)))
			if not str(ref.get("label", "")).is_empty():
				labels.append(str(ref["label"]))
	if FacetsRules.is_success_band(band):
		var trail := FacetsTalents.trail_reader(registry, txn, actor_id, action, str(record["approach"]["skill"]))
		if not trail.is_empty():
			notes.append(trail)
	if band == FacetsRules.BAND_FAILURE and str(action.get("retry_policy", "")) == "lock_until_change":
		txn.set_lock(str(record["lock_key"]), {"actor_id": actor_id, "objective_id": record["objective_id"], "approach_id": record["approach_id"], "fingerprint": record["fingerprint"], "event_id": record["event_id"]})
	if txn.failed():
		return FacetsReply.failure(FacetsError.make(FacetsError.EFFECT_REJECTED, "An effect could not be applied; nothing changed.").with_detail(str(txn.error)))
	var entry := _stage_entry(staged, entries, "check.finalize", str(record["event_id"]), txn.ops, {"band": band, "choices": record["choices"]})
	var final := record.duplicate(true)
	final["status"] = FacetsResolutionEvent.STATUS_FINAL
	final["final_band"] = band
	final["evaluation"] = evaluation
	final["effect_labels"] = labels
	final["talent_notes"] = notes
	final["finalize_ops"] = txn.ops.duplicate(true)
	final["resource_deltas"] = deltas
	final["after_revision"] = entry["after_revision"]
	final["decision"] = {}
	return FacetsReply.success(final)


# --- Identity triggers --------------------------------------------------------

## Host offers an authored identity trigger. The player accepts (material
## disadvantage applied, then at most 1 Resolve per actor per scene) or
## rejects (nothing happens).
func offer_identity_trigger(actor_id: String, trigger_id: String, principal: FacetsPrincipal = null, request_id: String = "") -> FacetsReply:
	var who := _principal(principal)
	if not who.is_host():
		return FacetsReply.fail(FacetsError.NOT_AUTHORIZED, "Only the host can offer an identity trigger.", "principal")
	var payload := {"command": "offer_identity_trigger", "actor_id": actor_id, "trigger_id": trigger_id}
	if not request_id.is_empty():
		var duplicate := _idempotent(request_id, payload)
		if duplicate != null:
			return duplicate
	if has_pending():
		return FacetsReply.fail(FacetsError.PENDING_DECISION, "Resolve the pending choice first.", "", true)
	var actor := _world.actor(actor_id)
	if actor == null:
		return FacetsReply.fail(FacetsError.UNKNOWN_ID, "Unknown character.", "actor_id")
	var trigger := {}
	for item in actor.identity_triggers:
		if str(item.get("id", "")) == trigger_id:
			trigger = item
	if trigger.is_empty():
		return FacetsReply.fail(FacetsError.UNKNOWN_ID, "Unknown identity trigger.", "trigger_id")
	var counter := _event_counter + 1
	var event_id := "evt-%06d" % counter
	var record := {
		"event_id": event_id,
		"kind": "identity",
		"status": FacetsResolutionEvent.STATUS_PENDING,
		"actor_id": actor_id,
		"trigger_id": trigger_id,
		"trigger": trigger.duplicate(true),
		"scene_id": _world.scene_id,
		"choices": [],
		"before_revision": _world.revision,
		"after_revision": _world.revision,
		"visibility": "public",
		"decision": {
			"event_id": event_id,
			"decision_id": "%s:identity" % event_id,
			"kind": FacetsPendingDecision.KIND_IDENTITY,
			"prompt": str(trigger.get("description", trigger.get("display_name", trigger_id))),
			"options": [
				{"id": "accept", "label": "Accept: %s" % trigger.get("disadvantage_label", "")},
				{"id": "reject", "label": "Decline"},
			],
		},
	}
	return _persist_entries(_world, [], record, {}, request_id, payload, record, counter, null)


func _finalize_identity(record: Dictionary, staged: FacetsWorldSnapshot, entries: Array) -> FacetsReply:
	var txn := FacetsTxn.begin(staged)
	var actor_id := str(record["actor_id"])
	var accepted := _choice(record, FacetsPendingDecision.KIND_IDENTITY) == "accept"
	var amount := 0
	var award_key := ""
	var material := false
	if accepted:
		var context := FacetsOpContext.make(staged, registry, actor_id)
		context.event_id = str(record["event_id"])
		for ref in record["trigger"].get("disadvantage_effects", []):
			if not registry.operations.apply_effect(ref, context, txn):
				return FacetsReply.failure(FacetsError.make(FacetsError.EFFECT_REJECTED, "The disadvantage could not be applied; nothing changed.").with_detail(str(txn.error)))
		for op in txn.ops:
			if str(op.get("op", "")) != "note":
				material = true
		award_key = "identity:%s:%s" % [actor_id, record["scene_id"]]
		if material and not staged.actor(actor_id).awards.has(award_key):
			amount = txn.add_resolve(actor_id, FacetsRules.IDENTITY_RESOLVE_AWARD)
			txn.record_award(actor_id, award_key, amount)
	if txn.failed():
		return FacetsReply.failure(txn.error)
	var entry := _stage_entry(staged, entries, "identity.resolved", str(record["event_id"]), txn.ops, {"accepted": accepted, "award_key": award_key, "amount": amount})
	var final := record.duplicate(true)
	final["status"] = FacetsResolutionEvent.STATUS_FINAL
	final["accepted"] = accepted
	final["material"] = material
	final["disadvantage"] = record["trigger"].get("disadvantage_label", "")
	final["award_key"] = award_key
	final["amount"] = amount
	final["resource_deltas"] = {"resolve": amount}
	final["finalize_ops"] = txn.ops.duplicate(true)
	final["after_revision"] = entry["after_revision"]
	final["decision"] = {}
	return FacetsReply.success(final)


# --- Recovery, scenes and host authority -------------------------------------

## Host authorizes a recovery opportunity (breather or secure_rest) or a safe
## checkpoint between consequential scenes. Client text cannot do this.
func grant_opportunity(opportunity_id: String, kind: String, principal: FacetsPrincipal = null, request_id: String = "") -> FacetsReply:
	return _host_command("host.opportunity", principal, request_id, {"opportunity_id": opportunity_id, "kind": kind}, func(staged: FacetsWorldSnapshot, txn: FacetsTxn) -> FacetsReply:
		if not ["breather", "secure_rest", "checkpoint"].has(kind):
			return FacetsReply.fail(FacetsError.INVALID_FIELD, "Opportunity kind must be breather, secure_rest or checkpoint.", "kind")
		if staged.opportunities.has(opportunity_id):
			return FacetsReply.fail(FacetsError.DUPLICATE, "Opportunity already exists.", "opportunity_id")
		txn.set_path(["opportunities", opportunity_id], {"kind": kind, "scene_id": staged.scene_id, "used_by": []})
		return FacetsReply.success({"opportunity_id": opportunity_id, "opportunity_kind": kind}))


## A breather removes 2 strain once per actor per authorized opportunity.
func take_breather(actor_id: String, opportunity_id: String, principal: FacetsPrincipal = null, request_id: String = "") -> FacetsReply:
	return _actor_command("recovery.breather", actor_id, principal, request_id, {"opportunity_id": opportunity_id}, func(staged: FacetsWorldSnapshot, txn: FacetsTxn) -> FacetsReply:
		var opportunity := _usable_opportunity(staged, opportunity_id, actor_id, ["breather", "secure_rest"])
		if not opportunity.ok:
			return opportunity
		var delta := txn.add_strain(actor_id, -FacetsRules.BREATHER_STRAIN)
		txn.append(["opportunities", opportunity_id, "used_by"], actor_id)
		return FacetsReply.success({"opportunity_id": opportunity_id, "resource_deltas": {"strain": delta}}))


## Full secure rest resets strain and removes 2 harm.
func full_rest(actor_id: String, opportunity_id: String, principal: FacetsPrincipal = null, request_id: String = "") -> FacetsReply:
	return _actor_command("recovery.rest", actor_id, principal, request_id, {"opportunity_id": opportunity_id}, func(staged: FacetsWorldSnapshot, txn: FacetsTxn) -> FacetsReply:
		var opportunity := _usable_opportunity(staged, opportunity_id, actor_id, ["secure_rest"])
		if not opportunity.ok:
			return opportunity
		var strain_delta := txn.set_strain(actor_id, 0)
		var harm_delta := txn.add_harm(actor_id, -FacetsRules.REST_HARM_REMOVED)
		txn.sync_harm_conditions(actor_id)
		txn.append(["opportunities", opportunity_id, "used_by"], actor_id)
		return FacetsReply.success({"opportunity_id": opportunity_id, "resource_deltas": {"strain": strain_delta, "harm": harm_delta}}))


func _usable_opportunity(staged: FacetsWorldSnapshot, opportunity_id: String, actor_id: String, kinds: Array) -> FacetsReply:
	var opportunity: Variant = staged.opportunities.get(opportunity_id)
	if not opportunity is Dictionary or not kinds.has(str(opportunity.get("kind", ""))):
		return FacetsReply.fail(FacetsError.NOT_AUTHORIZED, "No such recovery opportunity has been authorized.", "opportunity_id")
	if opportunity.get("used_by", []).has(actor_id):
		return FacetsReply.fail(FacetsError.ALREADY_USED, "This opportunity was already used.", "opportunity_id")
	return FacetsReply.success(opportunity)


func start_scene(scene_id: String, chapter_id: String = "", principal: FacetsPrincipal = null, request_id: String = "") -> FacetsReply:
	return _host_command("scene.start", principal, request_id, {"scene_id": scene_id, "chapter_id": chapter_id}, func(staged: FacetsWorldSnapshot, txn: FacetsTxn) -> FacetsReply:
		if scene_id.is_empty():
			return FacetsReply.fail(FacetsError.MISSING_FIELD, "scene_id is required.", "scene_id")
		var expired := _expire_scene_effects(staged, txn)
		txn.set_path(["scene_id"], scene_id)
		if not chapter_id.is_empty():
			txn.set_path(["chapter_id"], chapter_id)
		return FacetsReply.success({"scene_id": scene_id, "chapter_id": staged.chapter_id, "expired": expired}))


func end_scene(principal: FacetsPrincipal = null, request_id: String = "") -> FacetsReply:
	return _host_command("scene.end", principal, request_id, {}, func(staged: FacetsWorldSnapshot, txn: FacetsTxn) -> FacetsReply:
		return FacetsReply.success({"scene_id": staged.scene_id, "expired": _expire_scene_effects(staged, txn)}))


func _expire_scene_effects(staged: FacetsWorldSnapshot, txn: FacetsTxn) -> int:
	var remaining: Array = []
	var expired := 0
	for entry in staged.expiring.duplicate(true):
		if str(entry.get("scope", "")) == "scene_end":
			txn.set_path(entry["path"], entry.get("value"))
			expired += 1
		else:
			remaining.append(entry)
	if expired > 0:
		txn.set_path(["expiring"], remaining)
	return expired


func complete_chapter(chapter_id: String, principal: FacetsPrincipal = null, request_id: String = "") -> FacetsReply:
	return _host_command("chapter.complete", principal, request_id, {"chapter_id": chapter_id}, func(staged: FacetsWorldSnapshot, txn: FacetsTxn) -> FacetsReply:
		if staged.completed_chapters.has(chapter_id):
			return FacetsReply.fail(FacetsError.ALREADY_USED, "Chapter already completed.", "chapter_id")
		txn.append(["completed_chapters"], chapter_id)
		return FacetsReply.success({"chapter_id": chapter_id}))


## Host-authorized meaningful change (new route, evidence, tool or
## consequential time) for an objective. This, not a revision bump, unlocks
## retries.
func authorize_meaningful_change(objective_id: String, reason: String, principal: FacetsPrincipal = null, request_id: String = "") -> FacetsReply:
	return _host_command("host.meaningful_change", principal, request_id, {"objective_id": objective_id, "reason": reason}, func(staged: FacetsWorldSnapshot, txn: FacetsTxn) -> FacetsReply:
		txn.set_path(["objective_epochs", objective_id], int(staged.objective_epochs.get(objective_id, 0)) + 1)
		return FacetsReply.success({"objective_id": objective_id, "reason": reason}))


## Milestones award 1 (small) or 3 (chapter) Growth. Unique milestone keys,
## and never both sizes for the same underlying event.
func award_milestone(actor_id: String, milestone_id: String, size: String, event_key: String, principal: FacetsPrincipal = null, request_id: String = "") -> FacetsReply:
	return _host_command("progression.milestone", principal, request_id, {"actor_id": actor_id, "milestone_id": milestone_id, "size": size, "event_key": event_key}, func(staged: FacetsWorldSnapshot, txn: FacetsTxn) -> FacetsReply:
		var actor := staged.actor(actor_id)
		if actor == null:
			return FacetsReply.fail(FacetsError.UNKNOWN_ID, "Unknown character.", "actor_id")
		var amount := 0
		match size:
			"small":
				amount = FacetsRules.MILESTONE_SMALL
			"chapter":
				amount = FacetsRules.MILESTONE_CHAPTER
			_:
				return FacetsReply.fail(FacetsError.INVALID_FIELD, "Milestone size must be small or chapter.", "size")
		if milestone_id.is_empty() or event_key.is_empty():
			return FacetsReply.fail(FacetsError.MISSING_FIELD, "Milestones need a milestone ID and an underlying event key.", "milestone_id")
		var milestone_key := "milestone:%s" % milestone_id
		var event_award := "milestone_event:%s" % event_key
		if actor.awards.has(milestone_key) or actor.awards.has(event_award):
			return FacetsReply.fail(FacetsError.ALREADY_USED, "That milestone or its underlying event was already awarded.", "milestone_id")
		txn.add_growth(actor_id, amount)
		txn.record_award(actor_id, milestone_key, amount)
		txn.record_award(actor_id, event_award, amount)
		return FacetsReply.success({"actor_id": actor_id, "milestone_id": milestone_id, "size": size, "event_key": event_key, "amount": amount, "resource_deltas": {"growth": amount}}))


## Steady Voice: spend an action to remove strain from a willing,
## communicating ally after a fear setback this scene. Once per scene.
func use_steady_voice(actor_id: String, ally_id: String, principal: FacetsPrincipal = null, request_id: String = "") -> FacetsReply:
	return _actor_command("talent.steady_voice", actor_id, principal, request_id, {"ally_id": ally_id}, func(staged: FacetsWorldSnapshot, txn: FacetsTxn) -> FacetsReply:
		var actor := staged.actor(actor_id)
		var talent_id := FacetsTalents.find(registry, actor, "steady_voice")
		if talent_id.is_empty():
			return FacetsReply.fail(FacetsError.NOT_APPLICABLE, "Steady Voice is not equipped.", "talent_id")
		if FacetsCheckPlanner.restricted(registry, actor, FacetsRules.RESTRICTION_CANNOT_ACT):
			return FacetsReply.fail(FacetsError.INELIGIBLE, "%s cannot act right now." % actor.display_name, "actor_id")
		var ally := staged.actor(ally_id)
		if ally == null or ally_id == actor_id:
			return FacetsReply.fail(FacetsError.UNKNOWN_ID, "Steady Voice needs an ally.", "ally_id")
		if bool(ally.flags.get("unwilling", false)):
			return FacetsReply.fail(FacetsError.INELIGIBLE, "%s is not willing to listen." % ally.display_name, "ally_id")
		if FacetsCheckPlanner.restricted(registry, actor, FacetsRules.RESTRICTION_CANNOT_COMMUNICATE) or FacetsCheckPlanner.restricted(registry, ally, FacetsRules.RESTRICTION_CANNOT_COMMUNICATE):
			return FacetsReply.fail(FacetsError.INELIGIBLE, "You cannot reach each other.", "ally_id")
		if str(ally.flags.get("fear_setback_scene", "")) != staged.scene_id or staged.scene_id.is_empty():
			return FacetsReply.fail(FacetsError.NOT_APPLICABLE, "Steady Voice answers a fear setback in this scene.", "ally_id")
		if FacetsTalents.uses_left(registry, actor, talent_id, staged.scene_id) <= 0:
			return FacetsReply.fail(FacetsError.USAGE_LIMIT, "Steady Voice was already used this scene.", "talent_id")
		var amount := int(FacetsTalents.params(registry, talent_id).get("strain_removed", 2))
		var delta := txn.add_strain(ally_id, -amount)
		txn.increment_usage(actor_id, FacetsTalents.usage_key(talent_id, staged.scene_id))
		txn.increment_usage(actor_id, "actions:%s" % staged.scene_id)
		return FacetsReply.success({"talent_id": talent_id, "ally_id": ally_id, "consumes_action": true, "resource_deltas": {"ally_strain": delta}}))


## WorldPort atomic effect batch from the host (scripted scene consequences).
## Every effect is validated against the operation registry; all or nothing.
func apply_host_effects(actor_id: String, effects: Array, label: String, principal: FacetsPrincipal = null, request_id: String = "") -> FacetsReply:
	return _host_command("host.effects", principal, request_id, {"actor_id": actor_id, "effects": effects, "label": label}, func(staged: FacetsWorldSnapshot, txn: FacetsTxn) -> FacetsReply:
		var errors := registry.operations.validate_list(FacetsOperations.KIND_EFFECT, effects, "effects")
		if not errors.is_empty():
			return FacetsReply.failures(errors)
		var context := FacetsOpContext.make(staged, registry, actor_id)
		for ref in effects:
			if not registry.operations.apply_effect(ref, context, txn):
				return FacetsReply.failure(txn.error)
		return FacetsReply.success({"label": label}))


## Admits a new actor (from an accepted admission proposal or a definition).
func add_actor(state: FacetsActorState, principal: FacetsPrincipal = null, request_id: String = "") -> FacetsReply:
	return _host_command("host.add_actor", principal, request_id, {"actor": state.to_dict()}, func(_staged: FacetsWorldSnapshot, txn: FacetsTxn) -> FacetsReply:
		var errors := FacetsValidator.validate_progressed(state.build, registry, "build")
		if not errors.is_empty():
			return FacetsReply.failures(errors)
		txn.add_actor(state.copy())
		return FacetsReply.success({"actor_id": state.actor_id}))


func grant_training(actor_id: String, skill_id: String, principal: FacetsPrincipal = null, request_id: String = "") -> FacetsReply:
	return _host_command("progression.training", principal, request_id, {"actor_id": actor_id, "skill_id": skill_id}, func(staged: FacetsWorldSnapshot, txn: FacetsTxn) -> FacetsReply:
		var actor := staged.actor(actor_id)
		if actor == null or not registry.has_skill(skill_id):
			return FacetsReply.fail(FacetsError.UNKNOWN_ID, "Unknown character or skill.", "skill_id")
		if not actor.trained_skills.has(skill_id):
			txn.append(["actors", actor_id, "trained_skills"], skill_id)
		return FacetsReply.success({"actor_id": actor_id, "skill_id": skill_id}))


## Buys a skill rank, talent or facet at a host-authorized safe checkpoint.
func purchase(actor_id: String, item: Dictionary, checkpoint_id: String, principal: FacetsPrincipal = null, request_id: String = "") -> FacetsReply:
	return _actor_command("progression.purchase", actor_id, principal, request_id, {"purchase": item, "checkpoint_id": checkpoint_id}, func(staged: FacetsWorldSnapshot, txn: FacetsTxn) -> FacetsReply:
		var checkpoint := _usable_checkpoint(staged, checkpoint_id)
		if not checkpoint.ok:
			return checkpoint
		var quote := FacetsProgression.quote(registry, staged, staged.actor(actor_id), item)
		if not quote.ok:
			return quote
		FacetsProgression.apply_purchase(txn, actor_id, quote.value, _sequence + 1)
		if txn.failed():
			return FacetsReply.failure(txn.error)
		return FacetsReply.success({"purchase": quote.value, "resource_deltas": {"growth": -int(quote.value["cost"])}}))


## Refunds recorded purchases at their actual paid cost, invalidates
## dependent talents and reapplies admission constraints. Identity editing is
## separate. [param entry_indices] empty means every purchase.
func respec(actor_id: String, checkpoint_id: String, entry_indices: Array = [], principal: FacetsPrincipal = null, request_id: String = "") -> FacetsReply:
	return _actor_command("progression.respec", actor_id, principal, request_id, {"checkpoint_id": checkpoint_id, "entries": entry_indices}, func(staged: FacetsWorldSnapshot, txn: FacetsTxn) -> FacetsReply:
		var checkpoint := _usable_checkpoint(staged, checkpoint_id)
		if not checkpoint.ok:
			return checkpoint
		var plan := FacetsProgression.plan_respec(registry, staged.actor(actor_id), entry_indices)
		if not plan.ok:
			return plan
		FacetsProgression.apply_respec(txn, actor_id, plan.value)
		if txn.failed():
			return FacetsReply.failure(txn.error)
		return FacetsReply.success({"respec": plan.value, "resource_deltas": {"growth": int(plan.value["refund"])}}))


func _usable_checkpoint(staged: FacetsWorldSnapshot, checkpoint_id: String) -> FacetsReply:
	var opportunity: Variant = staged.opportunities.get(checkpoint_id)
	if not opportunity is Dictionary or str(opportunity.get("kind", "")) != "checkpoint":
		return FacetsReply.fail(FacetsError.NOT_AUTHORIZED, "Progression happens only at a host-authorized safe checkpoint.", "checkpoint_id")
	return FacetsReply.success(opportunity)


## Clears only the journey fields declared by the policy; profile
## accomplishments always survive.
func reset_journey(actor_id: String, policy: FacetsAdmissionPolicy = null, principal: FacetsPrincipal = null, request_id: String = "") -> FacetsReply:
	var reset_policy := policy if policy != null else registry.policy()
	return _host_command("journey.reset", principal, request_id, {"actor_id": actor_id, "fields": reset_policy.reset_fields}, func(staged: FacetsWorldSnapshot, txn: FacetsTxn) -> FacetsReply:
		var actor := staged.actor(actor_id)
		if actor == null:
			return FacetsReply.fail(FacetsError.UNKNOWN_ID, "Unknown character.", "actor_id")
		var defaults := {"strain": 0, "resolve": FacetsRules.START_RESOLVE, "growth": 0, "harm": 0, "conditions": [], "usage": {}, "awards": {}, "known_facts": [], "flags": {}}
		for field in reset_policy.reset_fields:
			if field == "profile" or not defaults.has(field):
				continue
			txn.set_path(["actors", actor_id, field], defaults[field])
		return FacetsReply.success({"actor_id": actor_id, "fields": reset_policy.reset_fields}))


# --- Command plumbing -------------------------------------------------------------

func _principal(principal: FacetsPrincipal) -> FacetsPrincipal:
	return principal if principal != null else default_principal


func _host_command(kind: String, principal: FacetsPrincipal, request_id: String, payload: Dictionary, body: Callable) -> FacetsReply:
	if not _principal(principal).is_host():
		return FacetsReply.fail(FacetsError.NOT_AUTHORIZED, "Only the host can do that.", "principal")
	return _run(kind, request_id, payload, body)


func _actor_command(kind: String, actor_id: String, principal: FacetsPrincipal, request_id: String, payload: Dictionary, body: Callable) -> FacetsReply:
	if not _principal(principal).can_act_for(actor_id):
		return FacetsReply.fail(FacetsError.NOT_AUTHORIZED, "You cannot act for that character.", "actor_id")
	if _world.actor(actor_id) == null:
		return FacetsReply.fail(FacetsError.UNKNOWN_ID, "Unknown character.", "actor_id")
	var with_actor := payload.duplicate(true)
	with_actor["actor_id"] = actor_id
	return _run(kind, request_id, with_actor, body)


## One journaled, durable transaction for a non-check command.
func _run(kind: String, request_id: String, payload: Dictionary, body: Callable) -> FacetsReply:
	var full_payload := payload.duplicate(true)
	full_payload["command"] = kind
	if not request_id.is_empty():
		var duplicate := _idempotent(request_id, full_payload)
		if duplicate != null:
			return duplicate
	if has_pending():
		return FacetsReply.fail(FacetsError.PENDING_DECISION, "Resolve the pending choice first.", "", true)
	var staged := _world.copy()
	var txn := FacetsTxn.begin(staged)
	var result: FacetsReply = body.call(staged, txn)
	if not result.ok:
		return result
	if txn.failed():
		return FacetsReply.failure(txn.error)
	var counter := _event_counter + 1
	var event_id := "evt-%06d" % counter
	var entries: Array = []
	var actor_id := str(payload.get("actor_id", ""))
	var entry := _stage_entry(staged, entries, kind, event_id, txn.ops, FacetsJson.clone(result.value))
	var record: Dictionary = FacetsJson.clone(result.value)
	record["event_id"] = event_id
	record["kind"] = kind
	record["status"] = FacetsResolutionEvent.STATUS_FINAL
	record["actor_id"] = actor_id
	record["scene_id"] = _world.scene_id
	record["ops"] = txn.ops.duplicate(true)
	record["before_revision"] = entry["before_revision"]
	record["after_revision"] = entry["after_revision"]
	record["visibility"] = "public"
	return _persist_entries(staged, entries, {}, {event_id: record}, request_id, full_payload, record, counter, null)


func _stage_entry(staged: FacetsWorldSnapshot, entries: Array, kind: String, event_id: String, ops: Array, data: Dictionary) -> Dictionary:
	var before := staged.revision
	staged.revision = before + 1
	var entry := {
		"format": JOURNAL_FORMAT,
		"sequence": _sequence + entries.size() + 1,
		"kind": kind,
		"event_id": event_id,
		"before_revision": before,
		"after_revision": staged.revision,
		"ops": ops.duplicate(true),
		"data": FacetsJson.clone(data),
	}
	entries.append(entry)
	return entry


## Same request_id and payload returns the prior response; a different
## payload under the same request_id is an IDEMPOTENCY_CONFLICT.
func _idempotent(request_id: String, payload: Dictionary) -> FacetsReply:
	if not _requests.has(request_id):
		return null
	var prior: Dictionary = _requests[request_id]
	if str(prior["digest"]) != FacetsJson.digest(payload):
		return FacetsReply.fail(FacetsError.IDEMPOTENCY_CONFLICT, "This request ID was already used for a different request.", "request_id")
	return FacetsReply.success(FacetsResolutionEvent.from_record(prior["response"]))


func _persist_entries(staged: FacetsWorldSnapshot, entries: Array, pending: Dictionary, new_events: Dictionary, request_id: String, payload: Dictionary, response: Dictionary, counter: int, rng_before: Variant) -> FacetsReply:
	var journal := _journal.duplicate(true)
	journal.append_array(entries)
	var events := _events.duplicate(true)
	for event_id in new_events:
		events[event_id] = new_events[event_id]
	var requests := _requests.duplicate(true)
	if not request_id.is_empty():
		requests[request_id] = {"digest": FacetsJson.digest(payload), "response": FacetsJson.clone(response)}
	var sequence := _sequence + entries.size()
	if _store != null:
		var data := _save_dict(staged, _checkpoint, journal, sequence, pending, events, requests, counter)
		var written := _store.write_save(data)
		if not written.ok:
			if rng_before is Dictionary:
				_dice.set_state(rng_before)
			return FacetsReply.failure(FacetsError.make(FacetsError.PERSISTENCE_FAILED, "The change could not be saved; nothing was committed. Try again.", "", true).with_detail(str(written.error)))
	_world = staged
	_journal = journal
	_sequence = sequence
	_pending = pending
	_events = events
	_requests = requests
	_event_counter = counter
	var event := FacetsResolutionEvent.from_record(response)
	_publish(event)
	return FacetsReply.success(event)


func _publish(event: FacetsResolutionEvent) -> void:
	published.emit(event)
	for port in _ports:
		port.call("present", event)


# --- Save, restore, replay --------------------------------------------------------

func to_save_dict() -> Dictionary:
	return _save_dict(_world, _checkpoint, _journal, _sequence, _pending, _events, _requests, _event_counter)


func _save_dict(world: FacetsWorldSnapshot, checkpoint_data: Dictionary, journal: Array, sequence: int, pending: Dictionary, events: Dictionary, requests: Dictionary, counter: int) -> Dictionary:
	return {
		"schema_version": FacetsRules.SCHEMA_VERSION,
		"save_kind": SAVE_KIND,
		"ruleset_id": registry.ruleset_id,
		"ruleset_version": registry.ruleset_version,
		"session_id": session_id,
		"packs": registry.pack_versions(),
		"checkpoint": checkpoint_data.duplicate(true),
		"journal": journal.duplicate(true),
		"last_sequence": sequence,
		"revision": world.revision,
		"state_digest": world.digest(),
		"pending": pending.duplicate(true),
		"events": events.duplicate(true),
		"requests": requests.duplicate(true),
		"rng": _dice.get_state(),
		"event_counter": counter,
	}


## Writes the complete session to [param target]. Reports failure; never
## claims durability from an in-memory success.
func save(target: FacetsSessionStore) -> FacetsReply:
	return target.write_save(to_save_dict())


## Compacts the journal into a new checkpoint (host only, no pending choice).
func checkpoint(principal: FacetsPrincipal = null) -> FacetsReply:
	if not _principal(principal).is_host():
		return FacetsReply.fail(FacetsError.NOT_AUTHORIZED, "Only the host can checkpoint.", "principal")
	if has_pending():
		return FacetsReply.fail(FacetsError.PENDING_DECISION, "Resolve the pending choice first.", "", true)
	var new_checkpoint := {"sequence": _sequence, "state": _world.to_dict()}
	if _store != null:
		var written := _store.write_save(_save_dict(_world, new_checkpoint, [], _sequence, _pending, _events, _requests, _event_counter))
		if not written.ok:
			return written
	_checkpoint = new_checkpoint
	_journal = []
	return FacetsReply.success(_sequence)


## Rebuilds a session from a store: validates versions and pinned packs,
## replays the journal from the checkpoint with recorded ops (never dice) and
## verifies the state digest. Options: "dice" (override), "store" (attach a
## different store; default is the one read from).
static func restore(source: FacetsSessionStore, p_registry: FacetsRegistry, options: Dictionary = {}) -> FacetsReply:
	var read := source.read_save()
	if not read.ok:
		return read
	var merged := options.duplicate()
	if not merged.has("store"):
		merged["store"] = source
	return from_save_dict(read.value, p_registry, merged)


static func from_save_dict(source: Dictionary, p_registry: FacetsRegistry, options: Dictionary = {}) -> FacetsReply:
	var migrated := FacetsMigrations.migrate(source)
	if not migrated.ok:
		return migrated
	var data: Dictionary = migrated.value["data"]
	if str(data.get("save_kind", "")) != SAVE_KIND:
		return FacetsReply.fail(FacetsError.MALFORMED, "Not a FACETS session save.", "save_kind")
	var packs: Dictionary = data.get("packs", {})
	var available := p_registry.pack_versions()
	for pack_id in packs:
		if str(available.get(pack_id, "")) != str(packs[pack_id]):
			return FacetsReply.fail(FacetsError.UNSUPPORTED_VERSION, "Save requires pack %s@%s." % [pack_id, packs[pack_id]], "packs.%s" % pack_id)
	var checkpoint_data: Dictionary = data.get("checkpoint", {})
	var replayed := replay(checkpoint_data.get("state", {}), data.get("journal", []), int(checkpoint_data.get("sequence", 0)))
	if not replayed.ok:
		return replayed
	var world: FacetsWorldSnapshot = replayed.value
	if world.digest() != str(data.get("state_digest", "")):
		return FacetsReply.fail(FacetsError.REPLAY_CORRUPT, "Replayed state does not match the saved digest.", "state_digest")
	var journal: Array = data.get("journal", [])
	var last := int(checkpoint_data.get("sequence", 0)) if journal.is_empty() else int(journal[journal.size() - 1]["sequence"])
	if last != int(data.get("last_sequence", -1)):
		return FacetsReply.fail(FacetsError.REPLAY_CORRUPT, "Journal does not end at the saved sequence.", "last_sequence")
	var session := FacetsSession.new()
	session.registry = p_registry
	session.session_id = str(data.get("session_id", "session"))
	session._world = world
	session._checkpoint = checkpoint_data.duplicate(true)
	session._journal = journal.duplicate(true)
	session._sequence = last
	session._event_counter = int(data.get("event_counter", 0))
	session._pending = data.get("pending", {}).duplicate(true)
	session._events = data.get("events", {}).duplicate(true)
	session._requests = data.get("requests", {}).duplicate(true)
	if options.get("dice") is FacetsDiceSource:
		session._dice = options["dice"]
	else:
		session._dice = FacetsDiceSource.seeded(0)
		session._dice.set_state(data.get("rng", {}))
	if options.get("store") is FacetsSessionStore:
		session._store = options["store"]
	return FacetsReply.success(session)


## Applies journal entries after [param checkpoint_sequence] to the
## checkpoint state using recorded ops only. Stops with an actionable error on
## sequence gaps, revision mismatches, unknown formats or unknown ops.
static func replay(checkpoint_state: Dictionary, journal: Array, checkpoint_sequence: int) -> FacetsReply:
	var world := FacetsWorldSnapshot.from_dict(checkpoint_state)
	var expected := checkpoint_sequence + 1
	for index in journal.size():
		var entry: Variant = journal[index]
		if not entry is Dictionary:
			return FacetsReply.fail(FacetsError.REPLAY_CORRUPT, "Journal entry %d is not an object." % index, "journal[%d]" % index)
		var sequence := int(entry.get("sequence", -1))
		if sequence <= checkpoint_sequence:
			continue
		if int(entry.get("format", 0)) != JOURNAL_FORMAT:
			return FacetsReply.fail(FacetsError.UNSUPPORTED_VERSION, "Journal entry %d uses unknown format %s." % [sequence, entry.get("format")], "journal[%d].format" % index)
		if sequence != expected:
			return FacetsReply.fail(FacetsError.REPLAY_CORRUPT, "Journal sequence gap: expected %d, found %d." % [expected, sequence], "journal[%d].sequence" % index)
		if int(entry.get("before_revision", -1)) != world.revision:
			return FacetsReply.fail(FacetsError.REPLAY_CORRUPT, "Journal entry %d starts at revision %s but the state is at %d." % [sequence, entry.get("before_revision"), world.revision], "journal[%d].before_revision" % index)
		var applied := FacetsReducer.apply_ops(world, entry.get("ops", []))
		if not applied.ok:
			var error := applied.error
			error.field_path = "journal[%d].%s" % [index, error.field_path]
			return FacetsReply.failure(error)
		world.revision = int(entry.get("after_revision", world.revision))
		expected += 1
	return FacetsReply.success(world)
