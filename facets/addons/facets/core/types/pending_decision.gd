@tool
class_name FacetsPendingDecision
extends RefCounted
## A frozen decision awaiting the player's choice. Option IDs never change
## once offered; the decision survives save/load.

const KIND_RESOLVE := "resolve"
const KIND_COST := "cost"
const KIND_BENEFIT := "benefit"
const KIND_IDENTITY := "identity"

var event_id: String = ""
var decision_id: String = ""
var kind: String = ""
var prompt: String = ""
## [{id, label, band_after?, requires_consent?}]
var options: Array = []


func is_empty() -> bool:
	return decision_id.is_empty()


func option_ids() -> Array[String]:
	var ids: Array[String] = []
	for option in options:
		ids.append(str(option.get("id", "")))
	return ids


func to_dict() -> Dictionary:
	return {"event_id": event_id, "decision_id": decision_id, "kind": kind, "prompt": prompt, "options": options.duplicate(true)}


static func from_dict(data: Dictionary) -> FacetsPendingDecision:
	var decision := FacetsPendingDecision.new()
	decision.event_id = str(data.get("event_id", ""))
	decision.decision_id = str(data.get("decision_id", ""))
	decision.kind = str(data.get("kind", ""))
	decision.prompt = str(data.get("prompt", ""))
	decision.options = data.get("options", []).duplicate(true)
	return decision
