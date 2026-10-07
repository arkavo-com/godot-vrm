@tool
class_name FacetsOperationRef
extends Resource
## Reference to an allowlisted requirement or effect operation with
## parameters. Content never embeds scripts; [member op] must name an
## operation registered in [FacetsOperations].

@export var op: String = ""
@export var params: Dictionary = {}
## Player-facing description of the requirement or stake.
@export var label: String = ""
## Requirements only: when true, an unmet requirement is reported without
## revealing what it is.
@export var secret: bool = false


static func make(p_op: String, p_params: Dictionary = {}, p_label: String = "", p_secret: bool = false) -> FacetsOperationRef:
	var ref := FacetsOperationRef.new()
	ref.op = p_op
	ref.params = p_params.duplicate(true)
	ref.label = p_label
	ref.secret = p_secret
	return ref


func to_dict() -> Dictionary:
	var result := {"op": op, "params": params.duplicate(true), "label": label}
	if secret:
		result["secret"] = true
	return result


static func from_dict(data: Dictionary) -> FacetsOperationRef:
	var params_value: Variant = data.get("params", {})
	return make(str(data.get("op", "")), params_value if params_value is Dictionary else {}, str(data.get("label", "")), bool(data.get("secret", false)))


static func list_to_dicts(refs: Array) -> Array:
	var result: Array = []
	for ref in refs:
		if ref is FacetsOperationRef:
			result.append(ref.to_dict())
	return result


static func list_from_dicts(items: Array) -> Array[FacetsOperationRef]:
	var result: Array[FacetsOperationRef] = []
	for item in items:
		if item is Dictionary:
			result.append(from_dict(item))
	return result
