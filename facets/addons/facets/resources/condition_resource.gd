@tool
class_name FacetsConditionResource
extends Resource
## Condition definition. Numeric penalties do not stack: a check takes only
## the worst applicable penalty, capped at -2. Restrictions apply
## independently of the numeric penalty.

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Tags such as "checks", "physical" or "combat".
@export var applicability_tags: Array[String] = ["checks"]
## Facets whose checks take the penalty; empty means every facet.
@export var applies_to_facets: Array[String] = []
@export_range(-2, 0) var penalty: int = 0
## Restriction IDs, e.g. no_push, no_reactions, cannot_act, limited_turn.
@export var restrictions: Array[String] = []
## How the condition ends, e.g. strain_below_capacity, medicine, rest, scene_end, manual.
@export var removal_operation: String = "manual"


func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"description": description,
		"applicability_tags": applicability_tags.duplicate(),
		"applies_to_facets": applies_to_facets.duplicate(),
		"penalty": penalty,
		"restrictions": restrictions.duplicate(),
		"removal_operation": removal_operation,
	}


static func from_dict(data: Dictionary) -> FacetsConditionResource:
	var condition := FacetsConditionResource.new()
	condition.id = str(data.get("id", ""))
	condition.display_name = str(data.get("display_name", ""))
	condition.description = str(data.get("description", ""))
	condition.applicability_tags.clear()
	for tag in data.get("applicability_tags", []):
		condition.applicability_tags.append(str(tag))
	for facet_id in data.get("applies_to_facets", []):
		condition.applies_to_facets.append(str(facet_id))
	condition.penalty = int(data.get("penalty", 0))
	for restriction in data.get("restrictions", []):
		condition.restrictions.append(str(restriction))
	condition.removal_operation = str(data.get("removal_operation", "manual"))
	return condition
