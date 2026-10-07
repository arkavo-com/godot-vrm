@tool
class_name FacetsError
extends RefCounted
## Structured error carried by every FACETS reply.
##
## Visible messages must never disclose hidden facts; callers that need a
## debugging detail put it in [member detail], which is not shown to players.

const INVALID_FIELD := "INVALID_FIELD"
const MISSING_FIELD := "MISSING_FIELD"
const UNKNOWN_FIELD := "UNKNOWN_FIELD"
const UNKNOWN_ID := "UNKNOWN_ID"
const OUT_OF_RANGE := "OUT_OF_RANGE"
const BUDGET := "BUDGET"
const DUPLICATE := "DUPLICATE"
const DUPLICATE_FACTOR := "DUPLICATE_FACTOR"
const MODIFIER_LIMIT := "MODIFIER_LIMIT"
const PREREQUISITE := "PREREQUISITE"
const NOT_AUTHORIZED := "NOT_AUTHORIZED"
const INELIGIBLE := "INELIGIBLE"
const RETRY_LOCKED := "RETRY_LOCKED"
const PUSH_NOT_ALLOWED := "PUSH_NOT_ALLOWED"
const STALE_PREVIEW := "STALE_PREVIEW"
const UNKNOWN_PREVIEW := "UNKNOWN_PREVIEW"
const PENDING_DECISION := "PENDING_DECISION"
const IDEMPOTENCY_CONFLICT := "IDEMPOTENCY_CONFLICT"
const MISSING_REQUEST_ID := "MISSING_REQUEST_ID"
const NOT_PENDING := "NOT_PENDING"
const INVALID_DECISION := "INVALID_DECISION"
const DECISION_REQUIRED := "DECISION_REQUIRED"
const PERSISTENCE_FAILED := "PERSISTENCE_FAILED"
const EFFECT_REJECTED := "EFFECT_REJECTED"
const UNKNOWN_OPERATION := "UNKNOWN_OPERATION"
const REPLAY_CORRUPT := "REPLAY_CORRUPT"
const UNSUPPORTED_VERSION := "UNSUPPORTED_VERSION"
const FUTURE_SCHEMA := "FUTURE_SCHEMA"
const MALFORMED := "MALFORMED"
const TOO_LARGE := "TOO_LARGE"
const ALREADY_USED := "ALREADY_USED"
const USAGE_LIMIT := "USAGE_LIMIT"
const INSUFFICIENT := "INSUFFICIENT"
const NOT_APPLICABLE := "NOT_APPLICABLE"
const TIMEOUT := "TIMEOUT"
const CANCELLED := "CANCELLED"
const DICE_UNAVAILABLE := "DICE_UNAVAILABLE"

var code: String = ""
var message: String = ""
var field_path: String = ""
var retryable: bool = false
## Developer-only diagnostic. Never rendered to players or AI providers.
var detail: String = ""


static func make(p_code: String, p_message: String, p_field_path: String = "", p_retryable: bool = false) -> FacetsError:
	var error := FacetsError.new()
	error.code = p_code
	error.message = p_message
	error.field_path = p_field_path
	error.retryable = p_retryable
	return error


func with_detail(p_detail: String) -> FacetsError:
	detail = p_detail
	return self


func to_dict() -> Dictionary:
	return {
		"code": code,
		"message": message,
		"field_path": field_path,
		"retryable": retryable,
	}


static func from_dict(data: Dictionary) -> FacetsError:
	return make(str(data.get("code", "")), str(data.get("message", "")), str(data.get("field_path", "")), bool(data.get("retryable", false)))


func _to_string() -> String:
	if field_path.is_empty():
		return "%s: %s" % [code, message]
	return "%s at %s: %s" % [code, field_path, message]
