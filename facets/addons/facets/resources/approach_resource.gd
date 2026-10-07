@tool
class_name FacetsApproachResource
extends Resource
## One whitelisted facet/skill pairing for an action. Requests select an
## approach ID; callers never pick arbitrary best stats.

@export var id: String = ""
@export var facet: String = "cunning"
@export var skill: String = "investigation"
@export var label: String = ""


static func make(p_id: String, p_facet: String, p_skill: String, p_label: String = "") -> FacetsApproachResource:
	var approach := FacetsApproachResource.new()
	approach.id = p_id
	approach.facet = p_facet
	approach.skill = p_skill
	approach.label = p_label
	return approach


func to_dict() -> Dictionary:
	return {"id": id, "facet": facet, "skill": skill, "label": label}


static func from_dict(data: Dictionary) -> FacetsApproachResource:
	return make(str(data.get("id", "")), str(data.get("facet", "")), str(data.get("skill", "")), str(data.get("label", "")))
