@tool
class_name FacetsCheckPlanner
extends RefCounted
## Builds the validated plan behind a preview: authority, knowledge, tools,
## requirements, approach, retry lock, modifiers, target, push/Resolve
## availability, stakes and exact odds. Read-only: never spends, never rolls.

const TIER_NAMES := {9: "favorable", 11: "standard pressure", 13: "demanding", 15: "severe", 17: "extreme", 19: "legendary"}


static func build(registry: FacetsRegistry, world: FacetsWorldSnapshot, request: FacetsActionRequest, principal: FacetsPrincipal) -> FacetsReply:
	var shape := FacetsActionRequest.validate_dict(request.to_dict())
	if not shape.ok:
		return shape
	if request.expected_revision >= 0 and request.expected_revision != world.revision:
		return FacetsReply.fail(FacetsError.STALE_PREVIEW, "The world changed; preview again.", "expected_revision", true)
	if principal == null or not principal.can_act_for(request.actor_id):
		return FacetsReply.fail(FacetsError.NOT_AUTHORIZED, "You cannot act for that character.", "actor_id")
	var actor := world.actor(request.actor_id)
	if actor == null:
		return FacetsReply.fail(FacetsError.UNKNOWN_ID, "Unknown character.", "actor_id")
	if not registry.has_action(request.action_id):
		return FacetsReply.fail(FacetsError.UNKNOWN_ID, "Unknown action.", "action_id")
	var action := registry.get_action(request.action_id)
	var approach := {}
	for item in action.get("approaches", []):
		if str(item.get("id", "")) == request.approach_id:
			approach = item
	if approach.is_empty():
		return FacetsReply.fail(FacetsError.UNKNOWN_ID, "That approach is not allowed for this action.", "approach_id")
	if restricted(registry, actor, FacetsRules.RESTRICTION_CANNOT_ACT):
		return FacetsReply.fail(FacetsError.INELIGIBLE, "%s cannot act right now." % actor.display_name, "actor_id")
	for target_id in request.target_ids:
		if not world.has_actor(target_id) and not world.objects.has(target_id):
			return FacetsReply.fail(FacetsError.UNKNOWN_ID, "Unknown target.", "target_ids")

	var context := FacetsOpContext.make(world, registry, actor.actor_id)
	context.target_ids = request.target_ids.duplicate()
	context.tool_ids = request.tool_ids.duplicate()
	context.helper_ids = request.helper_ids.duplicate()
	var reasons: Array[String] = []

	# Tools: carried, required, or substituted by Field Engineer.
	for tool_id in request.tool_ids:
		if actor.item_count(tool_id) <= 0:
			return FacetsReply.fail(FacetsError.INELIGIBLE, "You are not carrying that tool.", "tool_ids")
	var substitution := {}
	for tool_id in action.get("required_tools", []):
		if request.tool_ids.has(tool_id):
			continue
		var substitute := FacetsTalents.field_engineer_substitution(registry, world, actor, action, str(approach["skill"]), tool_id, request.tool_ids)
		if substitute.is_empty() or not substitution.is_empty():
			reasons.append("Requires %s." % tool_id)
		else:
			substitution = substitute

	# Requirements. Secret requirements fail without naming themselves.
	var visible_requirements: Array[String] = []
	for ref in action.get("requirements", []):
		var met := registry.operations.check(ref, context)
		var secret := bool(ref.get("secret", false))
		var label := str(ref.get("label", ""))
		if not secret and not label.is_empty():
			visible_requirements.append(label)
		if not met:
			reasons.append("This approach is not available right now." if secret or label.is_empty() else label)
	if not reasons.is_empty():
		var unique: Array[String] = []
		for reason in reasons:
			if not unique.has(reason):
				unique.append(reason)
		return FacetsReply.fail(FacetsError.INELIGIBLE, " ".join(unique), "action_id")

	# Helper: at most one eligible helper with the relevant skill who accepts the risk.
	var helper_id := ""
	if request.helper_ids.size() > 1:
		return FacetsReply.fail(FacetsError.INELIGIBLE, "Only one helper may assist.", "helper_ids")
	if request.helper_ids.size() == 1:
		helper_id = request.helper_ids[0]
		var helper := world.actor(helper_id)
		if not bool(action.get("allow_assistance", true)):
			return FacetsReply.fail(FacetsError.INELIGIBLE, "This action cannot be assisted.", "helper_ids")
		if helper == null or helper_id == actor.actor_id:
			return FacetsReply.fail(FacetsError.UNKNOWN_ID, "Unknown helper.", "helper_ids")
		if helper.build.skill(str(approach["skill"])) < 1:
			return FacetsReply.fail(FacetsError.INELIGIBLE, "%s lacks the relevant skill to help." % helper.display_name, "helper_ids")
		if bool(helper.flags.get("refuses_assistance", false)) or restricted(registry, helper, FacetsRules.RESTRICTION_CANNOT_ACT):
			return FacetsReply.fail(FacetsError.INELIGIBLE, "%s will not take that risk." % helper.display_name, "helper_ids")

	# Retry lock: actor + objective + approach + relevant-state fingerprint.
	var objective_id := str(action.get("objective_id", action.get("id", "")))
	var fingerprint := relevant_fingerprint(world, action, objective_id, request.tool_ids, helper_id)
	var lock_key := retry_lock_key(actor.actor_id, objective_id, request.approach_id, fingerprint)
	var locked := str(action.get("retry_policy", "lock_until_change")) == "lock_until_change" and world.retry_locks.has(lock_key)
	var second_look := {}
	if request.talent_ids.has("core.second_look") or not request.evidence_id.is_empty():
		if not locked:
			return FacetsReply.fail(FacetsError.NOT_APPLICABLE, "Second Look applies only after a failed attempt.", "talent_ids")
		var result := FacetsTalents.second_look(registry, world, actor, action, str(approach["skill"]), request.evidence_id, objective_id)
		if not bool(result["ok"]):
			return FacetsReply.failure(result["error"])
		second_look = result["plan"]
	elif locked:
		return FacetsReply.fail(FacetsError.RETRY_LOCKED, "Nothing relevant has changed since the last attempt; the same approach gets no new roll.", "approach_id")
	for talent_id in request.talent_ids:
		if talent_id != "core.second_look":
			return FacetsReply.fail(FacetsError.NOT_APPLICABLE, "That talent is not declared this way.", "talent_ids")

	# Modifiers.
	var facet_id := str(approach["facet"])
	var skill_id := str(approach["skill"])
	var modifiers: Array[FacetsModifier] = []
	for item in action.get("modifiers", []):
		var when: Variant = item.get("when", null)
		if when is Dictionary and not registry.operations.check(when, context):
			continue
		modifiers.append(FacetsModifier.from_dict(item))
	modifiers.append_array(condition_modifiers(registry, actor, facet_id))
	if not helper_id.is_empty():
		modifiers.append(FacetsModifier.make(helper_id, "assistance", FacetsModifier.SCOPE_ASSISTANCE, 1, "Help from %s" % world.actor(helper_id).display_name))
	var relationship: Dictionary = action.get("relationship", {})
	if not relationship.is_empty():
		var bond := actor.bond_value(str(relationship["other_id"]), str(relationship["dimension"]))
		if bond != 0:
			var value := 1 if bond > 0 else -1
			modifiers.append(FacetsModifier.make("bond:%s" % relationship["other_id"], "relationship:%s" % relationship["other_id"], FacetsModifier.SCOPE_RELATIONSHIP, value, "Relationship (%s)" % relationship["dimension"]))
	var defense_modifiers: Array[FacetsModifier] = FacetsModifiers.from_dicts(action.get("difficulty", {}).get("defense_modifiers", []))
	var modifier_errors := FacetsModifiers.validate(modifiers, defense_modifiers)
	if not modifier_errors.is_empty():
		return FacetsReply.failures(modifier_errors)
	var aggregate := FacetsModifiers.aggregate(modifiers)

	# Target.
	var difficulty: Dictionary = action.get("difficulty", {})
	var kind := str(difficulty.get("kind", "fixed"))
	var target := int(difficulty.get("target", FacetsRules.TARGETS["standard"]))
	var explanation: Array[String] = []
	if kind == "opposed":
		var defender_id := str(difficulty.get("defender_id", ""))
		if defender_id.is_empty() and not request.target_ids.is_empty():
			defender_id = request.target_ids[0]
		var defender := world.actor(defender_id)
		if defender == null:
			return FacetsReply.fail(FacetsError.INELIGIBLE, "There is no one to oppose this.", "target_ids")
		var defense_facet := defender.build.facet(str(difficulty["defense_facet"]))
		var defense_skill := defender.build.skill(str(difficulty["defense_skill"]))
		var defense_sum := int(FacetsModifiers.aggregate(defense_modifiers)["raw"])
		target = FacetsRules.opposed_target(defense_facet, defense_skill, defense_sum)
		if defender.controller == "npc":
			explanation.append("Opposed by %s: target %d. The defender does not roll." % [defender.display_name, target])
		else:
			explanation.append("Opposed by %s: 7 + %s %d + %s %d + defense %d = %d. The defender does not roll." % [defender.display_name, difficulty["defense_facet"], defense_facet, difficulty["defense_skill"], defense_skill, FacetsRules.clamp_modifier(defense_sum), target])
	else:
		explanation.append("Target %d%s." % [target, (" (%s)" % TIER_NAMES[target]) if TIER_NAMES.has(target) else ""])
	var routine := kind == "routine"
	var routine_requirements: Array = action.get("routine_requirements", [])
	if not routine and not routine_requirements.is_empty():
		routine = routine_requirements.all(func(ref: Variant) -> bool: return registry.operations.check(ref, context))
	if routine:
		explanation = ["Routine: succeeds without a roll."]

	# Push and Resolve availability.
	var push_available := false
	var push_note := ""
	if routine:
		push_note = "Routine actions do not roll."
	elif not bool(action.get("allow_push", true)):
		push_note = "This action cannot be pushed."
	elif actor.is_overwhelmed() or restricted(registry, actor, FacetsRules.RESTRICTION_NO_PUSH):
		push_note = "Overwhelmed characters cannot push."
	elif not push_allowed(actor.strain, actor.strain_capacity()):
		push_note = "Pushing would bring strain to capacity."
	else:
		push_available = true
		push_note = "Take %d strain for +%d." % [FacetsRules.PUSH_STRAIN, FacetsRules.PUSH_BONUS]
	var resolve_available := not routine and bool(action.get("allow_resolve", true)) and actor.resolve >= FacetsRules.RESOLVE_COST
	var allows_costly: bool = bool(action.get("allows_costly_success", false)) and not action.get("costly_options", []).is_empty()

	# Odds per fixed scenario.
	var check := FacetsCheckInput.make(actor.build.facet(facet_id), actor.build.skill(skill_id), target, allows_costly)
	check.facet_id = facet_id
	check.skill_id = skill_id
	var odds: Array = []
	if routine:
		odds.append(FacetsProbability.routine_odds().to_dict())
	else:
		for scenario in FacetsProbability.scenarios(check, FacetsAdjustments.make(modifiers), push_available, resolve_available):
			odds.append(scenario.to_dict())

	var plan := {
		"request": request.to_dict(),
		"actor_id": actor.actor_id,
		"action_id": str(action["id"]),
		"action_name": str(action.get("display_name", action["id"])),
		"action_version": int(action.get("version", 1)),
		"action_digest": registry.action_digest(str(action["id"])),
		"approach": approach.duplicate(true),
		"facet_id": facet_id,
		"facet_rating": check.facet,
		"skill_id": skill_id,
		"skill_rank": check.skill,
		"target": target,
		"target_kind": kind,
		"target_explanation": explanation,
		"modifiers": FacetsModifiers.to_dicts(modifiers),
		"modifier_lines": aggregate["lines"],
		"modifier_raw": int(aggregate["raw"]),
		"modifier_applied": int(aggregate["applied"]),
		"routine": routine,
		"push_available": push_available,
		"push_note": push_note,
		"resolve_available": resolve_available,
		"allows_costly_success": allows_costly,
		"requirements": visible_requirements,
		"stakes": action.get("stakes", {}).duplicate(true),
		"cost_options": _labels(action.get("costly_options", [])),
		"benefit_options": _labels(action.get("strong_benefits", [])) + _labels(FacetsTalents.benefit_options(registry, world, actor, action, skill_id)),
		"failure_effects": _labels(action.get("failure_effects", [])),
		"odds": odds,
		"tool_substitution": substitution,
		"second_look": second_look,
		"helper_id": helper_id,
		"objective_id": objective_id,
		"fingerprint": fingerprint,
		"lock_key": lock_key,
		"revision": world.revision,
		"scene_id": world.scene_id,
		"advanced_build": check.facet > FacetsRules.CREATION_FACET_CAP or check.skill > FacetsRules.CREATION_SKILL_CAP,
	}
	return FacetsReply.success(plan)


static func push_allowed(strain: int, capacity: int) -> bool:
	return strain + FacetsRules.PUSH_STRAIN < capacity


static func restricted(registry: FacetsRegistry, actor: FacetsActorState, restriction: String) -> bool:
	for condition_id in actor.conditions:
		var definition := registry.get_condition(condition_id)
		if definition.get("restrictions", []).has(restriction):
			return true
	return false


## Numeric condition penalties that apply to a check with [param facet_id].
## Aggregation later keeps only the worst one.
static func condition_modifiers(registry: FacetsRegistry, actor: FacetsActorState, facet_id: String) -> Array[FacetsModifier]:
	var result: Array[FacetsModifier] = []
	for condition_id in actor.conditions:
		var definition := registry.get_condition(condition_id)
		var penalty := int(definition.get("penalty", 0))
		if penalty >= 0 or not definition.get("applicability_tags", []).has("checks"):
			continue
		var facets: Array = definition.get("applies_to_facets", [])
		if not facets.is_empty() and not facets.has(facet_id):
			continue
		result.append(FacetsModifier.make(condition_id, "condition:%s" % condition_id, FacetsModifier.SCOPE_CONDITION, penalty, str(definition.get("display_name", condition_id))))
	return result


## Relevant state for retry locks: tools the action cares about, the helper
## and the host-authorized objective epoch. World revision is deliberately
## excluded; unrelated changes never unlock a retry.
static func relevant_fingerprint(world: FacetsWorldSnapshot, action: Dictionary, objective_id: String, tool_ids: Array[String], helper_id: String) -> String:
	var relevant: Array = []
	var cares: Array = action.get("required_tools", []) + action.get("useful_tools", []) + action.get("consumable_substitutes", [])
	for tool_id in tool_ids:
		if cares.has(tool_id) and not relevant.has(tool_id):
			relevant.append(tool_id)
	relevant.sort()
	return FacetsJson.digest({"tools": relevant, "helper": helper_id, "epoch": int(world.objective_epochs.get(objective_id, 0))})


static func retry_lock_key(actor_id: String, objective_id: String, approach_id: String, fingerprint: String) -> String:
	return "lock:%s" % FacetsJson.digest({"actor": actor_id, "objective": objective_id, "approach": approach_id, "fingerprint": fingerprint}).substr(0, 32)


static func _labels(options: Array) -> Array:
	var result: Array = []
	for option in options:
		if option is Dictionary:
			result.append({"id": str(option.get("id", "")), "label": str(option.get("label", "")), "requires_consent": bool(option.get("requires_consent", false))})
	return result


## Typed preview from a plan.
static func to_preview(plan: Dictionary, token: String) -> FacetsCheckPreview:
	var preview := FacetsCheckPreview.new()
	preview.token = token
	preview.revision = int(plan["revision"])
	preview.actor_id = plan["actor_id"]
	preview.action_id = plan["action_id"]
	preview.action_name = plan["action_name"]
	preview.approach_id = str(plan["approach"]["id"])
	preview.facet_id = plan["facet_id"]
	preview.facet_rating = int(plan["facet_rating"])
	preview.skill_id = plan["skill_id"]
	preview.skill_rank = int(plan["skill_rank"])
	preview.target = int(plan["target"])
	for line in plan["target_explanation"]:
		preview.target_explanation.append(str(line))
	for line in plan["modifier_lines"]:
		preview.modifiers.append({"label": line.get("label", ""), "value": line.get("value", 0), "contribution": line.get("contribution", 0), "counted": line.get("counted", true), "note": line.get("note", "")})
	preview.modifier_raw = int(plan["modifier_raw"])
	preview.modifier_applied = int(plan["modifier_applied"])
	preview.routine = bool(plan["routine"])
	preview.push_available = bool(plan["push_available"])
	preview.push_note = str(plan["push_note"])
	preview.resolve_available = bool(plan["resolve_available"])
	preview.allows_costly_success = bool(plan["allows_costly_success"])
	for label in plan["requirements"]:
		preview.requirements.append(str(label))
	preview.stakes = plan["stakes"].duplicate(true)
	preview.stakes["failure_effects"] = plan["failure_effects"].duplicate(true)
	preview.cost_options = plan["cost_options"].duplicate(true)
	preview.benefit_options = plan["benefit_options"].duplicate(true)
	for item in plan["odds"]:
		var odds := FacetsOdds.new()
		odds.scenario = str(item["scenario"])
		odds.routine = bool(item["routine"])
		odds.allows_costly_success = bool(item["allows_costly_success"])
		for band in item["bands"]:
			odds.counts[band] = int(item["bands"][band]["count"])
		preview.odds.append(odds)
	preview.advanced_build = bool(plan["advanced_build"])
	return preview
