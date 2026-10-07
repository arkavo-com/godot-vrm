@tool
class_name FacetsResolver
extends RefCounted
## Pure check arithmetic.
##
## total  = die_1 + die_2 + facet + skill + clamp(modifier_sum, -3, 3) + push_bonus + resolve_bonus
## margin = total - target
## No natural criticals: the dice only ever contribute their face values.


## Evaluates already validated inputs. No state mutation, no RNG.
static func evaluate(check: FacetsCheckInput, dice: Vector2i, adjustments: FacetsAdjustments) -> FacetsEvaluation:
	assert(dice.x >= 1 and dice.x <= 6 and dice.y >= 1 and dice.y <= 6, "dice must be in 1..6")
	var aggregate := FacetsModifiers.aggregate(adjustments.modifiers)
	return evaluate_with_sum(check, dice, int(aggregate["raw"]), adjustments.push, adjustments.resolve, aggregate["lines"])


## Arithmetic core shared by the resolver, probability and session.
static func evaluate_with_sum(check: FacetsCheckInput, dice: Vector2i, modifier_raw: int, push: bool, resolve: bool, lines: Array = []) -> FacetsEvaluation:
	var evaluation := FacetsEvaluation.new()
	evaluation.die_1 = dice.x
	evaluation.die_2 = dice.y
	evaluation.facet = check.facet
	evaluation.skill = check.skill
	evaluation.modifier_raw = modifier_raw
	evaluation.modifier_applied = FacetsRules.clamp_modifier(modifier_raw)
	evaluation.push_bonus = FacetsRules.PUSH_BONUS if push else 0
	evaluation.resolve_bonus = FacetsRules.RESOLVE_BONUS if resolve else 0
	evaluation.total = dice.x + dice.y + check.facet + check.skill + evaluation.modifier_applied + evaluation.push_bonus + evaluation.resolve_bonus
	evaluation.target = check.target
	evaluation.margin = evaluation.total - check.target
	evaluation.allows_costly_success = check.allows_costly_success
	evaluation.band = FacetsRules.band_for_margin(evaluation.margin, check.allows_costly_success)
	evaluation.modifier_lines = lines
	return evaluation


## Validating wrapper for untrusted inputs.
static func evaluate_checked(check: FacetsCheckInput, dice: Vector2i, adjustments: FacetsAdjustments) -> FacetsReply:
	var errors: Array[FacetsError] = []
	if dice.x < 1 or dice.x > 6:
		errors.append(FacetsError.make(FacetsError.OUT_OF_RANGE, "Die 1 must be 1..6.", "dice[0]"))
	if dice.y < 1 or dice.y > 6:
		errors.append(FacetsError.make(FacetsError.OUT_OF_RANGE, "Die 2 must be 1..6.", "dice[1]"))
	errors.append_array(FacetsModifiers.validate(adjustments.modifiers))
	if not errors.is_empty():
		return FacetsReply.failures(errors)
	return FacetsReply.success(evaluate(check, dice, adjustments))
