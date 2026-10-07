@tool
class_name FacetsBondResource
extends Resource
## A bond stores trust and affinity separately (each -2..+2), plus
## obligations and shared-event references. There is no additive bond bonus.

@export var other_id: String = ""
@export_range(-2, 2) var trust: int = 0
@export_range(-2, 2) var affinity: int = 0
@export var obligations: Array[String] = []
@export var shared_event_refs: Array[String] = []


func to_dict() -> Dictionary:
	return {
		"other_id": other_id,
		"trust": trust,
		"affinity": affinity,
		"obligations": obligations.duplicate(),
		"shared_event_refs": shared_event_refs.duplicate(),
	}


static func from_dict(data: Dictionary) -> FacetsBondResource:
	var bond := FacetsBondResource.new()
	bond.other_id = str(data.get("other_id", ""))
	bond.trust = int(data.get("trust", 0))
	bond.affinity = int(data.get("affinity", 0))
	for item in data.get("obligations", []):
		bond.obligations.append(str(item))
	for item in data.get("shared_event_refs", []):
		bond.shared_event_refs.append(str(item))
	return bond
