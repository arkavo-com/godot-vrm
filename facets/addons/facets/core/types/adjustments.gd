@tool
class_name FacetsAdjustments
extends RefCounted
## Adjustments applied to a check: situational modifiers (capped at +/-3 in
## total) plus Push and Resolve, which sit outside the cap.

var modifiers: Array[FacetsModifier] = []
var push: bool = false
var resolve: bool = false


static func make(p_modifiers: Array[FacetsModifier] = [], p_push: bool = false, p_resolve: bool = false) -> FacetsAdjustments:
	var adjustments := FacetsAdjustments.new()
	adjustments.modifiers = p_modifiers.duplicate()
	adjustments.push = p_push
	adjustments.resolve = p_resolve
	return adjustments


func with_push(p_push: bool) -> FacetsAdjustments:
	return make(modifiers, p_push, resolve)


func with_resolve(p_resolve: bool) -> FacetsAdjustments:
	return make(modifiers, push, p_resolve)


func push_bonus() -> int:
	return FacetsRules.PUSH_BONUS if push else 0


func resolve_bonus() -> int:
	return FacetsRules.RESOLVE_BONUS if resolve else 0


func to_dict() -> Dictionary:
	return {
		"modifiers": FacetsModifiers.to_dicts(modifiers),
		"push": push,
		"resolve": resolve,
	}


static func from_dict(data: Dictionary) -> FacetsAdjustments:
	return make(FacetsModifiers.from_dicts(data.get("modifiers", [])), bool(data.get("push", false)), bool(data.get("resolve", false)))
