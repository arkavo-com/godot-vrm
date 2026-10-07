@tool
class_name FacetsBenefitOption
extends Resource
## Bounded benefit selectable on a strong success (or a listed lesser
## concession). Benefits that need another party's consent never auto-select.

@export var id: String = ""
@export var label: String = ""
@export var effects: Array[FacetsOperationRef] = []
@export var requires_consent: bool = false


static func make(p_id: String, p_label: String, p_effects: Array[FacetsOperationRef], p_requires_consent: bool = false) -> FacetsBenefitOption:
	var option := FacetsBenefitOption.new()
	option.id = p_id
	option.label = p_label
	option.effects = p_effects.duplicate()
	option.requires_consent = p_requires_consent
	return option


func to_dict() -> Dictionary:
	return {"id": id, "label": label, "effects": FacetsOperationRef.list_to_dicts(effects), "requires_consent": requires_consent}


static func from_dict(data: Dictionary) -> FacetsBenefitOption:
	return make(str(data.get("id", "")), str(data.get("label", "")), FacetsOperationRef.list_from_dicts(data.get("effects", [])), bool(data.get("requires_consent", false)))


static func list_to_dicts(options: Array) -> Array:
	var result: Array = []
	for option in options:
		if option is FacetsBenefitOption:
			result.append(option.to_dict())
	return result


static func list_from_dicts(items: Array) -> Array[FacetsBenefitOption]:
	var result: Array[FacetsBenefitOption] = []
	for item in items:
		if item is Dictionary:
			result.append(from_dict(item))
	return result
