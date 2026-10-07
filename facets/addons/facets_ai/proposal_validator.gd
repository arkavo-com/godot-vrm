@tool
class_name FacetsProposalValidator
extends RefCounted
## Converts untrusted provider output into a FacetsActionRequest. Only actor,
## action, approach, target, tool and helper references plus optional display
## text are allowed. Difficulty, dice, stat changes, resource grants,
## arbitrary effects, new object IDs and private facts are rejected.
## Authority is checked separately by the session from the host principal.

const ALLOWED: Array[String] = ["actor_id", "action_id", "approach_id", "target_ids", "tool_ids", "helper_ids", "display_text"]
const MAX_BYTES := 8192
const MAX_DEPTH := 4
const MAX_DISPLAY := 280
const MAX_IDS := 8


## Returns FacetsReply with {"request": FacetsActionRequest, "display_text": String}.
## Errors carry actionable clarification messages and never echo hidden data.
static func validate(raw: Variant, observation: Dictionary) -> FacetsReply:
	var data: Variant = raw
	if raw is String:
		var parsed := FacetsJson.parse(raw, MAX_BYTES, MAX_DEPTH)
		if not parsed.ok:
			return FacetsReply.fail(parsed.error.code, "I couldn't read that as an action proposal. Please name one action and approach from the list.")
		data = parsed.value
	if not data is Dictionary:
		return FacetsReply.fail(FacetsError.MALFORMED, "A proposal must be a single JSON object naming an action and approach.")
	var errors: Array[FacetsError] = []
	for key in data:
		if not ALLOWED.has(str(key)):
			errors.append(FacetsError.make(FacetsError.UNKNOWN_FIELD, "Proposals may only name actor, action, approach, targets, tools and helpers; '%s' is not allowed." % key, str(key)))
	if not errors.is_empty():
		return FacetsReply.failures(errors)
	var actor: Dictionary = observation.get("actor", {})
	var actor_id := str(data.get("actor_id", ""))
	if actor_id != str(actor.get("id", "")):
		return FacetsReply.fail(FacetsError.NOT_AUTHORIZED, "You can only propose actions for %s." % actor.get("name", "your character"), "actor_id")
	var action_id := str(data.get("action_id", ""))
	var approach_id := str(data.get("approach_id", ""))
	if action_id.is_empty() or approach_id.is_empty():
		return FacetsReply.fail(FacetsError.MISSING_FIELD, "Which action and approach? Choose one from the available list.", "action_id")
	var entry := {}
	for item in observation.get("catalog", []):
		if str(item.get("action_id", "")) == action_id and str(item.get("approach_id", "")) == approach_id:
			entry = item
	if entry.is_empty():
		return FacetsReply.fail(FacetsError.UNKNOWN_ID, "That action or approach isn't available here. Choose one from the list.", "action_id")
	var visible := {}
	for item in observation.get("visible_actors", []):
		visible[str(item["id"])] = true
	for item in observation.get("visible_objects", []):
		visible[str(item["id"])] = true
	var carried := {}
	for item_id in actor.get("items", {}):
		carried[str(item_id)] = true
	var request := FacetsActionRequest.make(actor_id, action_id, approach_id)
	var lists := {"target_ids": visible, "tool_ids": carried, "helper_ids": visible}
	for key in lists:
		var items: Variant = data.get(key, [])
		if not items is Array or items.size() > MAX_IDS:
			return FacetsReply.fail(FacetsError.INVALID_FIELD, "%s must be a short list of IDs." % key, key)
		var ids: Array[String] = []
		for item in items:
			if not item is String or not lists[key].has(item):
				return FacetsReply.fail(FacetsError.UNKNOWN_ID, "%s mentions something that isn't available. Use only the listed IDs." % key, key)
			ids.append(item)
		match key:
			"target_ids":
				request.with_targets(ids)
			"tool_ids":
				request.with_tools(ids)
			"helper_ids":
				request.with_helpers(ids)
	var display: Variant = data.get("display_text", "")
	if not display is String or str(display).length() > MAX_DISPLAY:
		return FacetsReply.fail(FacetsError.INVALID_FIELD, "Keep display text under %d characters." % MAX_DISPLAY, "display_text")
	return FacetsReply.success({"request": request, "display_text": str(display)})
