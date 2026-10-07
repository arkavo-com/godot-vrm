@tool
class_name FacetsCheckInput
extends RefCounted
## Validated arithmetic inputs for one check. Contains no state or randomness.

var facet: int = 0
var skill: int = 0
var target: int = FacetsRules.TARGETS["standard"]
var allows_costly_success: bool = false
## Optional labels for explanations.
var facet_id: String = ""
var skill_id: String = ""


static func make(p_facet: int, p_skill: int, p_target: int, p_allows_costly: bool = false) -> FacetsCheckInput:
	var check := FacetsCheckInput.new()
	check.facet = p_facet
	check.skill = p_skill
	check.target = p_target
	check.allows_costly_success = p_allows_costly
	return check


func to_dict() -> Dictionary:
	return {
		"facet": facet,
		"skill": skill,
		"target": target,
		"allows_costly_success": allows_costly_success,
		"facet_id": facet_id,
		"skill_id": skill_id,
	}


static func from_dict(data: Dictionary) -> FacetsCheckInput:
	var check := make(int(data.get("facet", 0)), int(data.get("skill", 0)), int(data.get("target", 11)), bool(data.get("allows_costly_success", false)))
	check.facet_id = str(data.get("facet_id", ""))
	check.skill_id = str(data.get("skill_id", ""))
	return check
