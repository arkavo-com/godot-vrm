@tool
class_name FacetsActionResource
extends Resource
## Authored action definition. Converted to an immutable pinned dictionary
## when registered; sessions never mutate this Resource.

@export var id: String = ""
@export var version: int = 1
@export var display_name: String = ""
@export_multiline var description: String = ""
## Retry locks key on actor, objective, approach and relevant state.
@export var objective_id: String = ""
@export var tags: Array[String] = []

@export_group("Approaches and requirements")
@export var approaches: Array[FacetsApproachResource] = []
@export var requirements: Array[FacetsOperationRef] = []
## When every routine requirement is met the action succeeds without dice.
@export var routine_requirements: Array[FacetsOperationRef] = []
@export var required_tools: Array[String] = []
@export var useful_tools: Array[String] = []
## Authored consumables Field Engineer may substitute for a required tool.
@export var consumable_substitutes: Array[String] = []

@export_group("Difficulty")
@export_enum("fixed", "opposed", "routine") var difficulty_kind: String = "fixed"
@export_range(2, 30) var target: int = 11
@export var defender_id: String = ""
@export var defense_facet: String = ""
@export var defense_skill: String = ""
@export var defense_modifiers: Array[Dictionary] = []
## Conditional situational modifiers: {source_id, factor_id, scope, value, label, when?: {op, params}}.
@export var modifiers: Array[Dictionary] = []
## Optional single authored relationship factor: {other_id, dimension: "trust"|"affinity"}.
@export var relationship: Dictionary = {}

@export_group("Push, Resolve and help")
@export var allow_push: bool = true
@export var allow_resolve: bool = true
@export var allow_assistance: bool = true
## Advanced on commit (time spent attempting).
@export var clock_cost: int = 0

@export_group("Outcomes")
@export var allows_costly_success: bool = false
@export var costly_options: Array[FacetsCostOption] = []
@export var success_effects: Array[FacetsOperationRef] = []
## Declared consequence on failure (also applied when a cost is declined).
@export var failure_effects: Array[FacetsOperationRef] = []
@export var strong_benefits: Array[FacetsBenefitOption] = []
## Predeclared safe default used if a benefit choice is abandoned.
@export var default_benefit_id: String = ""
## Listed lesser concessions Bargain Maker may take in place of a benefit.
@export var lesser_concessions: Array[FacetsBenefitOption] = []
@export_multiline var success_stakes: String = ""
@export_multiline var failure_stakes: String = ""
## Setbacks from this action count as fear setbacks (Steady Voice).
@export var fear: bool = false

@export_group("Retry and evidence")
@export_enum("lock_until_change", "repeatable") var retry_policy: String = "lock_until_change"
## Alternate authored evidence sources that Second Look may use.
@export var alternate_evidence_sources: Array[String] = []
## Evidence-supported facts Trail Reader may reveal.
@export var revealable_facts: Array[String] = []


func to_dict() -> Dictionary:
	var approach_list: Array = []
	for approach in approaches:
		if approach != null:
			approach_list.append(approach.to_dict())
	var cost_list: Array = []
	for option in costly_options:
		if option != null:
			cost_list.append(option.to_dict())
	return {
		"id": id,
		"version": version,
		"display_name": display_name,
		"description": description,
		"objective_id": objective_id if not objective_id.is_empty() else id,
		"tags": tags.duplicate(),
		"approaches": approach_list,
		"requirements": FacetsOperationRef.list_to_dicts(requirements),
		"routine_requirements": FacetsOperationRef.list_to_dicts(routine_requirements),
		"required_tools": required_tools.duplicate(),
		"useful_tools": useful_tools.duplicate(),
		"consumable_substitutes": consumable_substitutes.duplicate(),
		"difficulty": {
			"kind": difficulty_kind,
			"target": target,
			"defender_id": defender_id,
			"defense_facet": defense_facet,
			"defense_skill": defense_skill,
			"defense_modifiers": defense_modifiers.duplicate(true),
		},
		"modifiers": modifiers.duplicate(true),
		"relationship": relationship.duplicate(true),
		"allow_push": allow_push,
		"allow_resolve": allow_resolve,
		"allow_assistance": allow_assistance,
		"clock_cost": clock_cost,
		"allows_costly_success": allows_costly_success,
		"costly_options": cost_list,
		"success_effects": FacetsOperationRef.list_to_dicts(success_effects),
		"failure_effects": FacetsOperationRef.list_to_dicts(failure_effects),
		"strong_benefits": FacetsBenefitOption.list_to_dicts(strong_benefits),
		"default_benefit_id": default_benefit_id,
		"lesser_concessions": FacetsBenefitOption.list_to_dicts(lesser_concessions),
		"stakes": {"success": success_stakes, "failure": failure_stakes},
		"fear": fear,
		"retry_policy": retry_policy,
		"alternate_evidence_sources": alternate_evidence_sources.duplicate(),
		"revealable_facts": revealable_facts.duplicate(),
	}


static func from_dict(data: Dictionary) -> FacetsActionResource:
	var action := FacetsActionResource.new()
	action.id = str(data.get("id", ""))
	action.version = int(data.get("version", 1))
	action.display_name = str(data.get("display_name", ""))
	action.description = str(data.get("description", ""))
	action.objective_id = str(data.get("objective_id", ""))
	action.tags = _strings(data.get("tags", []))
	for item in data.get("approaches", []):
		if item is Dictionary:
			action.approaches.append(FacetsApproachResource.from_dict(item))
	action.requirements = FacetsOperationRef.list_from_dicts(data.get("requirements", []))
	action.routine_requirements = FacetsOperationRef.list_from_dicts(data.get("routine_requirements", []))
	action.required_tools = _strings(data.get("required_tools", []))
	action.useful_tools = _strings(data.get("useful_tools", []))
	action.consumable_substitutes = _strings(data.get("consumable_substitutes", []))
	var difficulty: Dictionary = data.get("difficulty", {}) if data.get("difficulty", {}) is Dictionary else {}
	action.difficulty_kind = str(difficulty.get("kind", "fixed"))
	action.target = int(difficulty.get("target", 11))
	action.defender_id = str(difficulty.get("defender_id", ""))
	action.defense_facet = str(difficulty.get("defense_facet", ""))
	action.defense_skill = str(difficulty.get("defense_skill", ""))
	for item in difficulty.get("defense_modifiers", []):
		if item is Dictionary:
			action.defense_modifiers.append(item.duplicate(true))
	for item in data.get("modifiers", []):
		if item is Dictionary:
			action.modifiers.append(item.duplicate(true))
	var relationship_value: Variant = data.get("relationship", {})
	action.relationship = relationship_value.duplicate(true) if relationship_value is Dictionary else {}
	action.allow_push = bool(data.get("allow_push", true))
	action.allow_resolve = bool(data.get("allow_resolve", true))
	action.allow_assistance = bool(data.get("allow_assistance", true))
	action.clock_cost = int(data.get("clock_cost", 0))
	action.allows_costly_success = bool(data.get("allows_costly_success", false))
	for item in data.get("costly_options", []):
		if item is Dictionary:
			action.costly_options.append(FacetsCostOption.from_dict(item))
	action.success_effects = FacetsOperationRef.list_from_dicts(data.get("success_effects", []))
	action.failure_effects = FacetsOperationRef.list_from_dicts(data.get("failure_effects", []))
	action.strong_benefits = FacetsBenefitOption.list_from_dicts(data.get("strong_benefits", []))
	action.default_benefit_id = str(data.get("default_benefit_id", ""))
	action.lesser_concessions = FacetsBenefitOption.list_from_dicts(data.get("lesser_concessions", []))
	var stakes: Dictionary = data.get("stakes", {}) if data.get("stakes", {}) is Dictionary else {}
	action.success_stakes = str(stakes.get("success", ""))
	action.failure_stakes = str(stakes.get("failure", ""))
	action.fear = bool(data.get("fear", false))
	action.retry_policy = str(data.get("retry_policy", "lock_until_change"))
	action.alternate_evidence_sources = _strings(data.get("alternate_evidence_sources", []))
	action.revealable_facts = _strings(data.get("revealable_facts", []))
	return action


static func _strings(items: Variant) -> Array[String]:
	var result: Array[String] = []
	if items is Array:
		for item in items:
			result.append(str(item))
	return result
