@tool
class_name FacetsCharacterSheet
extends RefCounted
## Read-only summary of a character definition for the inspector: creation
## budgets, derived strain capacity, talent eligibility and validation errors.


static func summarize(character: FacetsCharacterResource, registry: FacetsRegistry) -> Dictionary:
	var build := character.build()
	var baseline := FacetsRules.FACET_BASELINE * FacetsRules.FACETS.size()
	var errors: Array = []
	for error in FacetsValidator.validate_character(character, registry):
		errors.append(error.to_dict())
	var advanced := false
	for facet_id in FacetsRules.FACETS:
		if build.facet(facet_id) > FacetsRules.CREATION_FACET_CAP:
			advanced = true
	for skill_id in build.skills:
		if build.skill(skill_id) > FacetsRules.CREATION_SKILL_CAP:
			advanced = true
	return {
		"facet_total": build.facet_total(),
		"facet_points_used": build.facet_total() - baseline,
		"facet_points_budget": FacetsRules.CREATION_FACET_POINTS,
		"skill_points_used": build.skill_total(),
		"skill_points_budget": FacetsRules.CREATION_SKILL_POINTS,
		"talent_count": build.talents.size(),
		"talent_budget": FacetsRules.STARTING_TALENTS,
		"strain_capacity": build.strain_capacity(),
		"advanced": advanced,
		"errors": errors,
	}


static func budget_text(summary: Dictionary) -> String:
	return "Facets %d/%d points (total %d) | Skills %d/%d | Talents %d/%d | Strain capacity %d" % [
		summary["facet_points_used"], summary["facet_points_budget"], summary["facet_total"],
		summary["skill_points_used"], summary["skill_points_budget"],
		summary["talent_count"], summary["talent_budget"], summary["strain_capacity"],
	]


## [{id, name, eligible, reason}] for every registered talent.
static func talent_choices(character: FacetsCharacterResource, registry: FacetsRegistry) -> Array:
	var build := character.build()
	var result: Array = []
	for talent_id in registry.talent_ids():
		var definition := registry.get_talent(talent_id)
		var reasons: Array[String] = []
		for error in FacetsValidator.prerequisite_errors(definition, build, ""):
			reasons.append(error.message)
		result.append({"id": talent_id, "name": str(definition.get("display_name", talent_id)), "eligible": reasons.is_empty(), "reason": " ".join(reasons)})
	return result
