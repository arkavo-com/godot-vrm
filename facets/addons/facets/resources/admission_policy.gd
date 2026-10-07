@tool
class_name FacetsAdmissionPolicy
extends Resource
## Admission policy. The standard policy proposes a legal 18-facet,
## 12-skill, 2-talent build and drops Growth and unadmitted equipment/powers.

@export var id: String = "core.standard_admission"
@export_enum("standard", "custom") var kind: String = "standard"
@export var facet_min: int = 2
@export var facet_cap: int = 4
@export var facet_total: int = 18
@export var skill_points: int = 12
@export var skill_cap: int = 2
@export var talent_count: int = 2
@export var allowed_capabilities: Array[String] = []
@export var allowed_equipment: Array[String] = []
## Journey fields cleared by a reset under this policy. Profile
## accomplishments are never in this list.
@export var reset_fields: Array[String] = ["strain", "resolve", "growth", "conditions", "harm", "usage", "awards", "known_facts", "flags"]


func to_dict() -> Dictionary:
	return {
		"id": id,
		"kind": kind,
		"facet_min": facet_min,
		"facet_cap": facet_cap,
		"facet_total": facet_total,
		"skill_points": skill_points,
		"skill_cap": skill_cap,
		"talent_count": talent_count,
		"allowed_capabilities": allowed_capabilities.duplicate(),
		"allowed_equipment": allowed_equipment.duplicate(),
		"reset_fields": reset_fields.duplicate(),
	}


static func standard() -> FacetsAdmissionPolicy:
	return FacetsAdmissionPolicy.new()


static func from_dict(data: Dictionary) -> FacetsAdmissionPolicy:
	var policy := FacetsAdmissionPolicy.new()
	policy.id = str(data.get("id", policy.id))
	policy.kind = str(data.get("kind", "standard"))
	policy.facet_min = int(data.get("facet_min", 2))
	policy.facet_cap = int(data.get("facet_cap", 4))
	policy.facet_total = int(data.get("facet_total", 18))
	policy.skill_points = int(data.get("skill_points", 12))
	policy.skill_cap = int(data.get("skill_cap", 2))
	policy.talent_count = int(data.get("talent_count", 2))
	policy.allowed_capabilities.clear()
	for item in data.get("allowed_capabilities", []):
		policy.allowed_capabilities.append(str(item))
	policy.allowed_equipment.clear()
	for item in data.get("allowed_equipment", []):
		policy.allowed_equipment.append(str(item))
	if data.has("reset_fields"):
		policy.reset_fields.clear()
		for item in data.get("reset_fields", []):
			policy.reset_fields.append(str(item))
	return policy
