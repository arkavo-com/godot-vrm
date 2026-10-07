@tool
class_name FacetsModifiers
extends RefCounted
## Validation and aggregation of situational modifiers.
##
## Aggregation order: validate, combine per-scope limits (one assistance at
## most +1, one relationship at most +/-1, worst numeric condition only and no
## lower than -2), sum, then clamp the sum to +/-3. Push and Resolve bonuses
## are outside this cap and never pass through here.


## Validates attacker-side and defense-side modifiers together.
static func validate(modifiers: Array[FacetsModifier], defense_modifiers: Array[FacetsModifier] = []) -> Array[FacetsError]:
	var errors: Array[FacetsError] = []
	var seen_factors := {}
	var all: Array[FacetsModifier] = []
	all.append_array(modifiers)
	all.append_array(defense_modifiers)
	for index in all.size():
		var modifier := all[index]
		var side := "modifiers" if index < modifiers.size() else "defense_modifiers"
		var local_index := index if index < modifiers.size() else index - modifiers.size()
		var path := "%s[%d]" % [side, local_index]
		if modifier.source_id.is_empty():
			errors.append(FacetsError.make(FacetsError.MISSING_FIELD, "Modifier needs a source_id.", path + ".source_id"))
		if modifier.factor_id.is_empty():
			errors.append(FacetsError.make(FacetsError.MISSING_FIELD, "Modifier needs a factor_id.", path + ".factor_id"))
		if not FacetsModifier.SCOPES.has(modifier.scope):
			errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Unknown modifier scope '%s'." % modifier.scope, path + ".scope"))
		if not modifier.factor_id.is_empty():
			if seen_factors.has(modifier.factor_id):
				errors.append(FacetsError.make(FacetsError.DUPLICATE_FACTOR, "Factor '%s' is already applied." % modifier.factor_id, path + ".factor_id"))
			seen_factors[modifier.factor_id] = true
	errors.append_array(_validate_side(modifiers, "modifiers"))
	errors.append_array(_validate_side(defense_modifiers, "defense_modifiers"))
	return errors


static func _validate_side(modifiers: Array[FacetsModifier], side: String) -> Array[FacetsError]:
	var errors: Array[FacetsError] = []
	var assistance_count := 0
	var relationship_count := 0
	for index in modifiers.size():
		var modifier := modifiers[index]
		var path := "%s[%d].value" % [side, index]
		match modifier.scope:
			FacetsModifier.SCOPE_ASSISTANCE:
				assistance_count += 1
				if modifier.value < 0 or modifier.value > FacetsRules.ASSISTANCE_MAX:
					errors.append(FacetsError.make(FacetsError.MODIFIER_LIMIT, "Assistance adds at most +1.", path))
				if assistance_count > 1:
					errors.append(FacetsError.make(FacetsError.MODIFIER_LIMIT, "Only one helper may assist.", path))
			FacetsModifier.SCOPE_RELATIONSHIP:
				relationship_count += 1
				if absi(modifier.value) > FacetsRules.RELATIONSHIP_MAX:
					errors.append(FacetsError.make(FacetsError.MODIFIER_LIMIT, "A relationship contributes at most +/-1.", path))
				if relationship_count > 1:
					errors.append(FacetsError.make(FacetsError.MODIFIER_LIMIT, "Only one relationship modifier may apply.", path))
			FacetsModifier.SCOPE_CONDITION:
				if modifier.value > 0:
					errors.append(FacetsError.make(FacetsError.MODIFIER_LIMIT, "Condition modifiers are penalties.", path))
	return errors


## Aggregates already validated modifiers.
## Returns {"raw": int, "applied": int, "lines": Array[Dictionary]}.
static func aggregate(modifiers: Array[FacetsModifier]) -> Dictionary:
	var lines: Array = []
	var sum := 0
	var worst_condition := 0
	var worst_index := -1
	for index in modifiers.size():
		var modifier := modifiers[index]
		if modifier.scope == FacetsModifier.SCOPE_CONDITION:
			if modifier.value < worst_condition:
				worst_condition = modifier.value
				worst_index = index
	for index in modifiers.size():
		var modifier := modifiers[index]
		var contribution := modifier.value
		var counted := true
		var note := ""
		match modifier.scope:
			FacetsModifier.SCOPE_CONDITION:
				counted = index == worst_index
				contribution = maxi(modifier.value, FacetsRules.CONDITION_PENALTY_FLOOR) if counted else 0
				if not counted:
					note = "not the worst condition penalty"
				elif modifier.value < FacetsRules.CONDITION_PENALTY_FLOOR:
					note = "condition penalty capped at -2"
			FacetsModifier.SCOPE_ASSISTANCE:
				contribution = clampi(modifier.value, 0, FacetsRules.ASSISTANCE_MAX)
			FacetsModifier.SCOPE_RELATIONSHIP:
				contribution = clampi(modifier.value, -FacetsRules.RELATIONSHIP_MAX, FacetsRules.RELATIONSHIP_MAX)
		sum += contribution
		var line := modifier.to_dict()
		line["counted"] = counted
		line["contribution"] = contribution
		line["note"] = note
		lines.append(line)
	return {"raw": sum, "applied": FacetsRules.clamp_modifier(sum), "lines": lines}


static func applied_sum(modifiers: Array[FacetsModifier]) -> int:
	return int(aggregate(modifiers)["applied"])


static func from_dicts(items: Array) -> Array[FacetsModifier]:
	var result: Array[FacetsModifier] = []
	for item in items:
		if item is Dictionary:
			result.append(FacetsModifier.from_dict(item))
	return result


static func to_dicts(modifiers: Array[FacetsModifier]) -> Array:
	var result: Array = []
	for modifier in modifiers:
		result.append(modifier.to_dict())
	return result
