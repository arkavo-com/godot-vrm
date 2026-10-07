@tool
class_name FacetsIdentityTriggerResource
extends Resource
## Authored identity trigger: accepting its material disadvantage awards
## 1 Resolve at most once per actor per scene.

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var disadvantage_label: String = ""
@export var disadvantage_effects: Array[FacetsOperationRef] = []


func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"description": description,
		"disadvantage_label": disadvantage_label,
		"disadvantage_effects": FacetsOperationRef.list_to_dicts(disadvantage_effects),
	}


static func from_dict(data: Dictionary) -> FacetsIdentityTriggerResource:
	var trigger := FacetsIdentityTriggerResource.new()
	trigger.id = str(data.get("id", ""))
	trigger.display_name = str(data.get("display_name", ""))
	trigger.description = str(data.get("description", ""))
	trigger.disadvantage_label = str(data.get("disadvantage_label", ""))
	trigger.disadvantage_effects = FacetsOperationRef.list_from_dicts(data.get("disadvantage_effects", []))
	return trigger
