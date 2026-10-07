@tool
class_name FacetsEvaluation
extends RefCounted
## Arithmetic result of one check for one dice pair. Applies no effects.

var die_1: int = 0
var die_2: int = 0
var facet: int = 0
var skill: int = 0
var modifier_raw: int = 0
var modifier_applied: int = 0
var push_bonus: int = 0
var resolve_bonus: int = 0
var total: int = 0
var target: int = 0
var margin: int = 0
## One of failure, costly_offer, success, strong_success. costly_offer is
## provisional until the costly-success choice is resolved.
var band: String = FacetsRules.BAND_FAILURE
var allows_costly_success: bool = false
var modifier_lines: Array = []


func is_provisional() -> bool:
	return band == FacetsRules.BAND_COSTLY_OFFER


func dice() -> Vector2i:
	return Vector2i(die_1, die_2)


func to_dict() -> Dictionary:
	return {
		"dice": [die_1, die_2],
		"facet": facet,
		"skill": skill,
		"modifier_raw": modifier_raw,
		"modifier_applied": modifier_applied,
		"push_bonus": push_bonus,
		"resolve_bonus": resolve_bonus,
		"total": total,
		"target": target,
		"margin": margin,
		"band": band,
		"allows_costly_success": allows_costly_success,
	}
