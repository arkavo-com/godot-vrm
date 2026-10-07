@tool
class_name FacetsFakeProvider
extends FacetsAiProvider
## Deterministic offline provider for tests and the demo.
##
## Proposals: returns the next scripted raw reply if any, otherwise picks the
## first available catalog entry (stable order). Narration: a fixed template.
## [member delay_ticks] simulates latency; [member hang] never answers (for
## timeout handling); [member fail_narration] simulates narration errors.

var scripted: Array = []
var delay_ticks: int = 0
var hang: bool = false
var fail_narration: bool = false
var observations: Array = []
var narration_views: Array = []
var _queue: Array = []


func request_proposal(ticket: FacetsAiTicket, observation: Dictionary, adapter: Object) -> void:
	observations.append(observation.duplicate(true))
	if hang:
		return
	var reply: Variant
	if not scripted.is_empty():
		reply = scripted.pop_front()
	else:
		reply = _choose(observation)
	_schedule(ticket, adapter, reply, false)


func request_narration(ticket: FacetsAiTicket, view: Dictionary, adapter: Object) -> void:
	narration_views.append(view.duplicate(true))
	if hang:
		return
	if fail_narration:
		_schedule(ticket, adapter, "narration provider unavailable", true)
		return
	var text := "%s tries %s and the result is %s." % [view.get("actor_name", "Someone"), str(view.get("action_name", "something")).to_lower(), str(view.get("band_label", "unclear"))]
	_schedule(ticket, adapter, text, false)


func _choose(observation: Dictionary) -> String:
	for entry in observation.get("catalog", []):
		if bool(entry.get("available", false)):
			return JSON.stringify({
				"actor_id": observation["actor"]["id"],
				"action_id": entry["action_id"],
				"approach_id": entry["approach_id"],
				"tool_ids": entry.get("suggested_tools", []),
				"display_text": "I'll try to %s." % str(entry.get("label", entry["action_id"])).to_lower(),
			})
	return "{\"display_text\": \"I wait.\"}"


func _schedule(ticket: FacetsAiTicket, adapter: Object, payload: Variant, failure: bool) -> void:
	if delay_ticks <= 0:
		if failure:
			adapter.call("fail", ticket, str(payload))
		else:
			adapter.call("deliver", ticket, payload)
		return
	_queue.append({"ticket": ticket, "adapter": adapter, "payload": payload, "failure": failure, "ticks": delay_ticks})


## Advances simulated latency; the adapter calls this from its tick.
func pump() -> void:
	var remaining: Array = []
	for item in _queue:
		item["ticks"] -= 1
		if item["ticks"] > 0:
			remaining.append(item)
		elif item["failure"]:
			item["adapter"].call("fail", item["ticket"], str(item["payload"]))
		else:
			item["adapter"].call("deliver", item["ticket"], item["payload"])
	_queue = remaining


func cancel(ticket: FacetsAiTicket) -> void:
	_queue = _queue.filter(func(item: Dictionary) -> bool: return item["ticket"] != ticket)
