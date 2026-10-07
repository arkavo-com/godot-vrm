@tool
class_name FacetsCheckPreview
extends RefCounted
## Immutable, player-visible preview of a legal check: requirements, target,
## modifier explanation, stakes, choices, exact odds and an opaque token
## bound to the actor, canonical request, definition versions and revision.
## Contains no internal objects and no secret prerequisite details.

var token: String = ""
var revision: int = 0
var actor_id: String = ""
var action_id: String = ""
var action_name: String = ""
var approach_id: String = ""
var facet_id: String = ""
var facet_rating: int = 0
var skill_id: String = ""
var skill_rank: int = 0
var target: int = 0
var target_explanation: Array[String] = []
## Visible modifier lines: {label, value, contribution, counted, note}.
var modifiers: Array = []
var modifier_raw: int = 0
var modifier_applied: int = 0
var routine: bool = false
var push_available: bool = false
var push_note: String = ""
var resolve_available: bool = false
var allows_costly_success: bool = false
var requirements: Array[String] = []
var stakes: Dictionary = {}
var cost_options: Array = []
var benefit_options: Array = []
var odds: Array[FacetsOdds] = []
## True when the build exceeds standard creation values (facet 5, skill 3+).
var advanced_build: bool = false


func odds_for(scenario: String) -> FacetsOdds:
	for item in odds:
		if item.scenario == scenario:
			return item
	return null


func to_dict() -> Dictionary:
	var odds_dicts: Array = []
	for item in odds:
		odds_dicts.append(item.to_dict())
	return {
		"token": token,
		"revision": revision,
		"actor_id": actor_id,
		"action_id": action_id,
		"action_name": action_name,
		"approach_id": approach_id,
		"facet_id": facet_id,
		"facet_rating": facet_rating,
		"skill_id": skill_id,
		"skill_rank": skill_rank,
		"target": target,
		"target_explanation": target_explanation.duplicate(),
		"modifiers": modifiers.duplicate(true),
		"modifier_raw": modifier_raw,
		"modifier_applied": modifier_applied,
		"routine": routine,
		"push_available": push_available,
		"push_note": push_note,
		"resolve_available": resolve_available,
		"allows_costly_success": allows_costly_success,
		"requirements": requirements.duplicate(),
		"stakes": stakes.duplicate(true),
		"cost_options": cost_options.duplicate(true),
		"benefit_options": benefit_options.duplicate(true),
		"odds": odds_dicts,
		"advanced_build": advanced_build,
	}
