@tool
class_name FacetsResolutionEvent
extends RefCounted
## Typed view over a pending or final event record: pinned definitions,
## dice, arithmetic, choices, applied effects and resource deltas.

const STATUS_PENDING := "pending"
const STATUS_FINAL := "final"

var event_id: String = ""
## "check", "identity", "breather", "rest", "milestone", "talent", ...
var kind: String = ""
var status: String = STATUS_PENDING
var actor_id: String = ""
var action_id: String = ""
var approach_id: String = ""
var routine: bool = false
var push: bool = false
## Empty for routine actions and non-check events.
var dice: Array = []
## Arithmetic at commit (FacetsEvaluation.to_dict()).
var base: Dictionary = {}
## Arithmetic after choices (e.g. with Resolve).
var evaluation: Dictionary = {}
var final_band: String = ""
var choices: Array = []
var effect_labels: Array[String] = []
var resource_deltas: Dictionary = {}
var before_revision: int = 0
var after_revision: int = 0
var pending_decision: FacetsPendingDecision = FacetsPendingDecision.new()
## Full canonical record, including pinned definitions and state ops.
var record: Dictionary = {}


func is_pending() -> bool:
	return status == STATUS_PENDING


func is_final() -> bool:
	return status == STATUS_FINAL


func to_dict() -> Dictionary:
	return record.duplicate(true)


static func from_record(source: Dictionary) -> FacetsResolutionEvent:
	var data: Dictionary = FacetsJson.normalize(source)
	var event := FacetsResolutionEvent.new()
	event.record = data
	event.event_id = str(data.get("event_id", ""))
	event.kind = str(data.get("kind", ""))
	event.status = str(data.get("status", STATUS_PENDING))
	event.actor_id = str(data.get("actor_id", ""))
	event.action_id = str(data.get("action_id", ""))
	event.approach_id = str(data.get("approach_id", ""))
	event.routine = bool(data.get("routine", false))
	event.push = bool(data.get("push", false))
	event.dice = data.get("dice", []).duplicate()
	event.base = data.get("base", {}).duplicate(true)
	event.evaluation = data.get("evaluation", data.get("base", {})).duplicate(true)
	event.final_band = str(data.get("final_band", ""))
	event.choices = data.get("choices", []).duplicate(true)
	for label in data.get("effect_labels", []):
		event.effect_labels.append(str(label))
	event.resource_deltas = data.get("resource_deltas", {}).duplicate(true)
	event.before_revision = int(data.get("before_revision", 0))
	event.after_revision = int(data.get("after_revision", 0))
	var decision: Variant = data.get("decision", {})
	if decision is Dictionary and not decision.is_empty() and event.is_pending():
		event.pending_decision = FacetsPendingDecision.from_dict(decision)
	return event
