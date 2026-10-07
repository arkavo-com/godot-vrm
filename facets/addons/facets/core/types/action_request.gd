@tool
class_name FacetsActionRequest
extends RefCounted
## A request to attempt an action. It names an approach; it never names a
## difficulty, dice, stats or effects. Authority comes from the principal.

const FIELDS: Array[String] = [
	"actor_id", "action_id", "approach_id", "target_ids", "tool_ids", "helper_ids",
	"expected_revision", "talent_ids", "evidence_id",
]

var actor_id: String = ""
var action_id: String = ""
var approach_id: String = ""
## Ordered: the first target is the primary target.
var target_ids: Array[String] = []
var tool_ids: Array[String] = []
var helper_ids: Array[String] = []
## -1 means "current revision"; otherwise previews fail when it differs.
var expected_revision: int = -1
## Talents the actor declares for this attempt (e.g. core.second_look).
var talent_ids: Array[String] = []
## Alternate evidence source for Second Look.
var evidence_id: String = ""


static func make(p_actor_id: String, p_action_id: String, p_approach_id: String) -> FacetsActionRequest:
	var request := FacetsActionRequest.new()
	request.actor_id = p_actor_id
	request.action_id = p_action_id
	request.approach_id = p_approach_id
	return request


func with_tools(p_tool_ids: Array) -> FacetsActionRequest:
	tool_ids.clear()
	for item in p_tool_ids:
		tool_ids.append(str(item))
	return self


func with_helpers(p_helper_ids: Array) -> FacetsActionRequest:
	helper_ids.clear()
	for item in p_helper_ids:
		helper_ids.append(str(item))
	return self


func with_targets(p_target_ids: Array) -> FacetsActionRequest:
	target_ids.clear()
	for item in p_target_ids:
		target_ids.append(str(item))
	return self


func with_talents(p_talent_ids: Array, p_evidence_id: String = "") -> FacetsActionRequest:
	talent_ids.clear()
	for item in p_talent_ids:
		talent_ids.append(str(item))
	evidence_id = p_evidence_id
	return self


## Canonical form: unordered sets are sorted, target order is preserved.
func to_dict() -> Dictionary:
	var tools := tool_ids.duplicate()
	tools.sort()
	var helpers := helper_ids.duplicate()
	helpers.sort()
	var talents := talent_ids.duplicate()
	talents.sort()
	return {
		"actor_id": actor_id,
		"action_id": action_id,
		"approach_id": approach_id,
		"target_ids": target_ids.duplicate(),
		"tool_ids": tools,
		"helper_ids": helpers,
		"expected_revision": expected_revision,
		"talent_ids": talents,
		"evidence_id": evidence_id,
	}


static func from_dict(data: Dictionary) -> FacetsActionRequest:
	var request := make(str(data.get("actor_id", "")), str(data.get("action_id", "")), str(data.get("approach_id", "")))
	request.with_targets(data.get("target_ids", []))
	request.with_tools(data.get("tool_ids", []))
	request.with_helpers(data.get("helper_ids", []))
	request.expected_revision = int(data.get("expected_revision", -1))
	request.with_talents(data.get("talent_ids", []), str(data.get("evidence_id", "")))
	return request


## Strict shape validation for untrusted dictionaries.
static func validate_dict(data: Variant) -> FacetsReply:
	if not data is Dictionary:
		return FacetsReply.fail(FacetsError.MALFORMED, "Request must be an object.")
	var errors: Array[FacetsError] = []
	for key in data:
		if not FIELDS.has(str(key)):
			errors.append(FacetsError.make(FacetsError.UNKNOWN_FIELD, "Field '%s' is not allowed in a request." % key, str(key)))
	for key in ["actor_id", "action_id", "approach_id"]:
		if not data.get(key) is String or str(data.get(key)).is_empty():
			errors.append(FacetsError.make(FacetsError.MISSING_FIELD, "Field '%s' is required." % key, key))
	for key in ["target_ids", "tool_ids", "helper_ids", "talent_ids"]:
		if data.has(key):
			var items: Variant = data[key]
			if not items is Array:
				errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Field '%s' must be a list of IDs." % key, key))
			else:
				for item in items:
					if not item is String:
						errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Field '%s' must contain string IDs." % key, key))
						break
	if data.has("expected_revision") and not (data["expected_revision"] is int or data["expected_revision"] is float):
		errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "expected_revision must be an integer.", "expected_revision"))
	if data.has("evidence_id") and not data["evidence_id"] is String:
		errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "evidence_id must be a string.", "evidence_id"))
	if not errors.is_empty():
		return FacetsReply.failures(errors)
	return FacetsReply.success(from_dict(data))
