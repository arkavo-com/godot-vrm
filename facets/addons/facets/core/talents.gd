@tool
class_name FacetsTalents
extends RefCounted
## Behavior of the six noncombat core talent hooks. Each hook reads only its
## typed parameters and the pinned action definition; none can introduce an
## effect that the operation registry does not allow.


static func usage_key(talent_id: String, scene_id: String) -> String:
	return "talent:%s:scene:%s" % [talent_id, scene_id]


static func uses_left(registry: FacetsRegistry, actor: FacetsActorState, talent_id: String, scene_id: String) -> int:
	var definition := registry.get_talent(talent_id)
	var params: Dictionary = definition.get("parameters", {})
	var allowed := int(params.get("uses_per_scene", definition.get("uses", 1)))
	return allowed - int(actor.usage.get(usage_key(talent_id, scene_id), 0))


## First equipped talent using [param hook_id], or "".
static func find(registry: FacetsRegistry, actor: FacetsActorState, hook_id: String) -> String:
	var found := registry.talents_with_hook(actor.build, hook_id)
	return found[0] if not found.is_empty() else ""


static func params(registry: FacetsRegistry, talent_id: String) -> Dictionary:
	return registry.get_talent(talent_id).get("parameters", {})


static func applies_to_skill(registry: FacetsRegistry, talent_id: String, skill_id: String) -> bool:
	var skills: Variant = params(registry, talent_id).get("skills", [])
	return skills is Array and skills.has(skill_id)


## Field Engineer: an authored consumable listed on the action may stand in for
## a missing required tool. Returns {} when no substitution applies.
static func field_engineer_substitution(registry: FacetsRegistry, world: FacetsWorldSnapshot, actor: FacetsActorState, action: Dictionary, skill_id: String, missing_tool: String, tool_ids: Array[String]) -> Dictionary:
	var talent_id := find(registry, actor, "field_engineer")
	if talent_id.is_empty() or not applies_to_skill(registry, talent_id, skill_id):
		return {}
	if uses_left(registry, actor, talent_id, world.scene_id) <= 0:
		return {}
	for consumable_id in action.get("consumable_substitutes", []):
		if tool_ids.has(consumable_id) and actor.item_count(consumable_id) > 0:
			return {"talent_id": talent_id, "required_tool": missing_tool, "consumable_id": consumable_id}
	return {}


## Second Look: retry a locked objective once per scene with an alternate
## authored evidence source and an extra interval. Returns {"ok": bool,
## "error": FacetsError, "plan": {...}}.
static func second_look(registry: FacetsRegistry, world: FacetsWorldSnapshot, actor: FacetsActorState, action: Dictionary, skill_id: String, evidence_id: String, objective_id: String) -> Dictionary:
	var talent_id := find(registry, actor, "second_look")
	if talent_id.is_empty():
		return {"ok": false, "error": FacetsError.make(FacetsError.NOT_APPLICABLE, "Second Look is not equipped.", "talent_ids")}
	if not applies_to_skill(registry, talent_id, skill_id):
		return {"ok": false, "error": FacetsError.make(FacetsError.NOT_APPLICABLE, "Second Look does not apply to this approach.", "talent_ids")}
	if uses_left(registry, actor, talent_id, world.scene_id) <= 0:
		return {"ok": false, "error": FacetsError.make(FacetsError.USAGE_LIMIT, "Second Look was already used this scene.", "talent_ids")}
	var sources: Array = action.get("alternate_evidence_sources", [])
	if evidence_id.is_empty() or not sources.has(evidence_id):
		return {"ok": false, "error": FacetsError.make(FacetsError.NOT_APPLICABLE, "Second Look needs an alternate evidence source for this objective.", "evidence_id")}
	var evidence_key := "evidence:%s:%s" % [objective_id, evidence_id]
	if actor.usage.has(evidence_key):
		return {"ok": false, "error": FacetsError.make(FacetsError.ALREADY_USED, "That evidence has already been examined.", "evidence_id")}
	var interval := int(params(registry, talent_id).get("interval", 1))
	return {"ok": true, "plan": {"talent_id": talent_id, "evidence_id": evidence_id, "evidence_key": evidence_key, "interval": interval}}


## Extra benefit options granted by talents on a strong success:
## Quiet Hands (its own quiet benefit) and Bargain Maker (the action's listed
## lesser concessions). Each replaces, never adds to, the strong benefit.
static func benefit_options(registry: FacetsRegistry, world: FacetsWorldSnapshot, actor: FacetsActorState, action: Dictionary, skill_id: String) -> Array:
	var options: Array = []
	var quiet := find(registry, actor, "quiet_hands")
	if not quiet.is_empty() and applies_to_skill(registry, quiet, skill_id) and uses_left(registry, actor, quiet, world.scene_id) > 0:
		var quiet_params := params(registry, quiet)
		options.append({
			"id": str(quiet_params.get("benefit_id", "quiet_hands")),
			"label": str(quiet_params.get("label", "Quiet Hands")),
			"effects": quiet_params.get("effects", []).duplicate(true),
			"requires_consent": false,
			"talent_id": quiet,
		})
	var bargain := find(registry, actor, "bargain_maker")
	if not bargain.is_empty() and applies_to_skill(registry, bargain, skill_id) and uses_left(registry, actor, bargain, world.scene_id) > 0:
		for concession in action.get("lesser_concessions", []):
			var option: Dictionary = concession.duplicate(true)
			option["id"] = "bargain:%s" % concession.get("id", "")
			option["label"] = "Bargain Maker: %s" % concession.get("label", "")
			option["talent_id"] = bargain
			options.append(option)
	return options


## Trail Reader: on success, reveal the first permitted, evidence-supported
## fact listed on the action that the actor does not already know.
static func trail_reader(registry: FacetsRegistry, txn: FacetsTxn, actor_id: String, action: Dictionary, skill_id: String) -> Dictionary:
	var actor := txn.world.actor(actor_id)
	var talent_id := find(registry, actor, "trail_reader")
	if talent_id.is_empty() or not applies_to_skill(registry, talent_id, skill_id):
		return {}
	if uses_left(registry, actor, talent_id, txn.world.scene_id) <= 0:
		return {}
	for fact_id in action.get("revealable_facts", []):
		var fact: Variant = txn.world.facts.get(fact_id)
		if not fact is Dictionary:
			continue
		if str(fact.get("evidence_id", "")).is_empty() or not bool(fact.get("trail_permitted", true)):
			continue
		if actor.knows(fact_id):
			continue
		txn.reveal_fact(actor_id, fact_id)
		txn.increment_usage(actor_id, usage_key(talent_id, txn.world.scene_id))
		return {"talent_id": talent_id, "fact_id": fact_id}
	return {}
