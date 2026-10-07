@tool
class_name FacetsCostOption
extends Resource
## Authored cost offered in the near-miss band. Accepting it turns the
## provisional result into success_with_cost; declining is failure.

@export var id: String = ""
@export var label: String = ""
@export var effects: Array[FacetsOperationRef] = []


static func make(p_id: String, p_label: String, p_effects: Array[FacetsOperationRef]) -> FacetsCostOption:
	var option := FacetsCostOption.new()
	option.id = p_id
	option.label = p_label
	option.effects = p_effects.duplicate()
	return option


func to_dict() -> Dictionary:
	return {"id": id, "label": label, "effects": FacetsOperationRef.list_to_dicts(effects)}


static func from_dict(data: Dictionary) -> FacetsCostOption:
	return make(str(data.get("id", "")), str(data.get("label", "")), FacetsOperationRef.list_from_dicts(data.get("effects", [])))
