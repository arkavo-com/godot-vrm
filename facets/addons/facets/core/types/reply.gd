@tool
class_name FacetsReply
extends RefCounted
## Typed reply: either [member ok] with a [member value], or a structured
## [member error] (plus any further [member errors] from multi-field validation).

var ok: bool = false
var value: Variant = null
var error: FacetsError = null
var errors: Array[FacetsError] = []


static func success(p_value: Variant) -> FacetsReply:
	var reply := FacetsReply.new()
	reply.ok = true
	reply.value = p_value
	return reply


static func failure(p_error: FacetsError) -> FacetsReply:
	var reply := FacetsReply.new()
	reply.ok = false
	reply.error = p_error
	reply.errors = [p_error]
	return reply


static func fail(code: String, message: String, field_path: String = "", retryable: bool = false) -> FacetsReply:
	return failure(FacetsError.make(code, message, field_path, retryable))


static func failures(p_errors: Array[FacetsError]) -> FacetsReply:
	assert(not p_errors.is_empty(), "failures() needs at least one error")
	var reply := FacetsReply.new()
	reply.ok = false
	reply.error = p_errors[0]
	reply.errors = p_errors.duplicate()
	return reply


## Returns success(value) when [param p_errors] is empty, otherwise the failures.
static func from_errors(p_errors: Array[FacetsError], p_value: Variant) -> FacetsReply:
	if p_errors.is_empty():
		return success(p_value)
	return failures(p_errors)


func error_codes() -> Array[String]:
	var codes: Array[String] = []
	for item in errors:
		codes.append(item.code)
	return codes


func _to_string() -> String:
	if ok:
		return "FacetsReply(ok)"
	return "FacetsReply(%s)" % ", ".join(errors.map(func(e: FacetsError) -> String: return str(e)))
