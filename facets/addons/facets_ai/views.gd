@tool
class_name FacetsAiViews
extends RefCounted
## Builds what a provider may see. Observations pass through a witness and
## perception policy: the observer's own sheet, visible actors and objects,
## public facts and facts the observer already knows, and the legal action
## catalog. Private facts, NPC internals and hidden objects are never
## included. Narration views are built only from committed events.

const BAND_LABELS := {
	"failure": "a failure",
	"costly_offer": "a near miss",
	"success_with_cost": "a success at a cost",
	"success": "a success",
	"strong_success": "a strong success",
}


static func observation(session: FacetsSession, actor_id: String, principal: FacetsPrincipal = null) -> Dictionary:
	var world := session.snapshot()
	var actor := world.actor(actor_id)
	if actor == null:
		return {}
	var known: Array = []
	for fact_id in actor.known_facts:
		var fact: Variant = world.facts.get(fact_id, {})
		known.append({"id": fact_id, "label": str(fact.get("label", fact_id)) if fact is Dictionary else fact_id})
	var public_facts: Array = []
	var fact_ids := world.facts.keys()
	fact_ids.sort()
	for fact_id in fact_ids:
		var fact: Dictionary = world.facts[fact_id]
		if str(fact.get("visibility", "public")) == "public":
			public_facts.append({"id": fact_id, "label": str(fact.get("label", fact_id)), "value": fact.get("value")})
	var visible_actors: Array = []
	var actor_ids := world.actors.keys()
	actor_ids.sort()
	for other_id in actor_ids:
		var other: FacetsActorState = world.actors[other_id]
		if other_id == actor_id or bool(other.flags.get("hidden", false)):
			continue
		visible_actors.append({"id": other_id, "name": other.display_name, "kind": other.controller})
	var visible_objects: Array = []
	var object_ids := world.objects.keys()
	object_ids.sort()
	for object_id in object_ids:
		var flags: Dictionary = world.objects[object_id]
		if bool(flags.get("hidden", false)):
			continue
		var shown := {}
		for key in flags:
			if not str(key).begins_with("_") and not str(key).begins_with("secret"):
				shown[key] = flags[key]
		visible_objects.append({"id": object_id, "flags": shown})
	var catalog: Array = []
	for entry in session.catalog(actor_id, principal):
		catalog.append({
			"action_id": entry["action_id"],
			"approach_id": entry["approach_id"],
			"label": entry["label"],
			"available": entry["available"],
			"reason": entry["reason"],
			"suggested_tools": entry["request"]["tool_ids"],
		})
	return {
		"observer": actor_id,
		"actor": {
			"id": actor_id,
			"name": actor.display_name,
			"identity": _narrative(actor.identity),
			"strain": actor.strain,
			"strain_capacity": actor.strain_capacity(),
			"resolve": actor.resolve,
			"conditions": Array(actor.conditions),
			"items": actor.items.duplicate(),
			"talents": Array(actor.build.talents),
			"known_facts": known,
		},
		"scene": {"scene_id": world.scene_id, "chapter_id": world.chapter_id, "clock": world.clock},
		"visible_actors": visible_actors,
		"visible_objects": visible_objects,
		"public_facts": public_facts,
		"catalog": catalog,
	}


static func _narrative(identity: Dictionary) -> Dictionary:
	var result := {}
	for key in ["name", "drive", "code", "hindrance", "tell"]:
		if identity.has(key):
			result[key] = identity[key]
	return result


## Cache key: observer plus the perception-relevant state, not the revision.
static func observation_key(observation: Dictionary) -> String:
	return FacetsJson.digest(observation)


static func narration_view(session: FacetsSession, event: FacetsResolutionEvent, observer_id: String) -> Dictionary:
	var world := session.snapshot()
	var record := event.to_dict()
	var actor := world.actor(event.actor_id)
	var action: Dictionary = record.get("action", {})
	var approach: Dictionary = record.get("approach", {})
	var band := event.final_band if event.is_final() else str(event.base.get("band", ""))
	var view := {
		"event_id": event.event_id,
		"kind": event.kind,
		"status": event.status,
		"observer": observer_id,
		"actor_id": event.actor_id,
		"actor_name": actor.display_name if actor != null else event.actor_id,
		"action_name": str(action.get("display_name", record.get("trigger", {}).get("display_name", event.kind))),
		"approach": ("%s + %s" % [approach.get("facet", ""), approach.get("skill", "")]) if not approach.is_empty() else "",
		"dice": event.dice.duplicate(),
		"total": int(event.evaluation.get("total", 0)),
		"target": int(event.evaluation.get("target", 0)),
		"band": band,
		"band_label": BAND_LABELS.get(band, band),
		"routine": event.routine,
		"push": event.push,
		"choices": event.choices.map(func(choice: Dictionary) -> String: return str(choice.get("option_id", ""))),
		"effects": Array(event.effect_labels),
	}
	if event.kind == "identity":
		view["accepted"] = bool(record.get("accepted", false))
	if observer_id == event.actor_id:
		view["notes"] = record.get("talent_notes", []).duplicate(true)
	return view


## Deterministic narration from a committed event view; used whenever a
## provider fails, times out or is absent.
static func fallback_narration(view: Dictionary) -> String:
	var parts: Array[String] = []
	if str(view.get("kind", "")) == "check":
		if bool(view.get("routine", false)):
			parts.append("%s: %s (routine, no roll needed)." % [view["actor_name"], view["action_name"]])
		else:
			var dice: Array = view.get("dice", [])
			parts.append("%s attempts %s (%s): %s, total %d against %d - %s." % [
				view["actor_name"], str(view["action_name"]).to_lower(), view["approach"],
				"+".join(dice.map(func(d: Variant) -> String: return str(d))) if not dice.is_empty() else "no roll",
				view["total"], view["target"], view["band_label"],
			])
	elif str(view.get("kind", "")) == "identity":
		parts.append("%s %s: %s." % [view.get("actor_name", ""), "accepts" if bool(view.get("accepted", false)) else "declines", view.get("action_name", "")])
	else:
		parts.append("%s: %s." % [view.get("actor_name", ""), str(view.get("action_name", view.get("kind", ""))).replace(".", " ")])
	var effects: Array = view.get("effects", [])
	if not effects.is_empty():
		parts.append("%s." % "; ".join(effects))
	return " ".join(parts)
