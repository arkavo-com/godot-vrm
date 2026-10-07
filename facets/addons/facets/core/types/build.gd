@tool
class_name FacetsBuild
extends RefCounted
## Mechanical build: facet ratings, skill ranks, talents and capabilities.
## Missing known skills mean rank 0.

var facets: Dictionary = {}
var skills: Dictionary = {}
var talents: Array[String] = []
var capabilities: Array[String] = []


static func baseline() -> FacetsBuild:
	var build := FacetsBuild.new()
	for facet_id in FacetsRules.FACETS:
		build.facets[facet_id] = FacetsRules.FACET_BASELINE
	return build


func facet(facet_id: String) -> int:
	return int(facets.get(facet_id, 0))


func skill(skill_id: String) -> int:
	return int(skills.get(skill_id, 0))


func has_talent(talent_id: String) -> bool:
	return talents.has(talent_id)


func facet_total() -> int:
	var total := 0
	for facet_id in FacetsRules.FACETS:
		total += facet(facet_id)
	return total


func skill_total() -> int:
	var total := 0
	for skill_id in skills:
		total += int(skills[skill_id])
	return total


func strain_capacity() -> int:
	return FacetsRules.strain_capacity(facet("tenacity"))


func copy() -> FacetsBuild:
	return from_dict(to_dict())


## Canonical form: facets in FACETS order, only nonzero skills, talents in
## chosen order (order is meaningful for admission preferences).
func to_dict() -> Dictionary:
	var facet_dict := {}
	for facet_id in facets:
		facet_dict[facet_id] = int(facets[facet_id])
	var skill_dict := {}
	for skill_id in skills:
		if int(skills[skill_id]) != 0:
			skill_dict[skill_id] = int(skills[skill_id])
	return {
		"facets": facet_dict,
		"skills": skill_dict,
		"talents": talents.duplicate(),
		"capabilities": capabilities.duplicate(),
	}


static func from_dict(data: Dictionary) -> FacetsBuild:
	var build := FacetsBuild.new()
	var facet_data: Variant = data.get("facets", {})
	if facet_data is Dictionary:
		for facet_id in facet_data:
			build.facets[str(facet_id)] = int(facet_data[facet_id])
	var skill_data: Variant = data.get("skills", {})
	if skill_data is Dictionary:
		for skill_id in skill_data:
			build.skills[str(skill_id)] = int(skill_data[skill_id])
	for talent_id in data.get("talents", []):
		build.talents.append(str(talent_id))
	for capability_id in data.get("capabilities", []):
		build.capabilities.append(str(capability_id))
	return build
