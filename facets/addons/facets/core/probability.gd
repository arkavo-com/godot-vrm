@tool
class_name FacetsProbability
extends RefCounted
## Exact odds by enumerating all 36 ordered 2d6 pairs. Uses no RNG.


static func enumerate(check: FacetsCheckInput, adjustments: FacetsAdjustments) -> FacetsOdds:
	var raw := int(FacetsModifiers.aggregate(adjustments.modifiers)["raw"])
	var odds := enumerate_sum(check, raw, adjustments.push, adjustments.resolve)
	odds.scenario = scenario_name(adjustments.push, adjustments.resolve)
	return odds


static func enumerate_sum(check: FacetsCheckInput, modifier_raw: int, push: bool, resolve: bool) -> FacetsOdds:
	var odds := FacetsOdds.new()
	odds.allows_costly_success = check.allows_costly_success
	odds.scenario = scenario_name(push, resolve)
	for die_1 in range(1, 7):
		for die_2 in range(1, 7):
			var evaluation := FacetsResolver.evaluate_with_sum(check, Vector2i(die_1, die_2), modifier_raw, push, resolve)
			odds.counts[evaluation.band] = int(odds.counts[evaluation.band]) + 1
	return odds


## Routine actions succeed without dice: all outcomes are success, none strong.
static func routine_odds() -> FacetsOdds:
	var odds := FacetsOdds.new()
	odds.routine = true
	odds.scenario = "routine"
	odds.counts[FacetsRules.BAND_SUCCESS] = FacetsOdds.OUTCOMES
	return odds


## Fixed scenarios shown separately: never assumes the player spends Resolve.
## Unavailable toggles are omitted rather than shown as options.
static func scenarios(check: FacetsCheckInput, adjustments: FacetsAdjustments, push_available: bool, resolve_available: bool) -> Array[FacetsOdds]:
	var base := adjustments.with_push(false).with_resolve(false)
	var result: Array[FacetsOdds] = [enumerate(check, base)]
	if push_available:
		result.append(enumerate(check, base.with_push(true)))
	if resolve_available:
		result.append(enumerate(check, base.with_resolve(true)))
	if push_available and resolve_available:
		result.append(enumerate(check, base.with_push(true).with_resolve(true)))
	return result


static func scenario_name(push: bool, resolve: bool) -> String:
	if push and resolve:
		return "push+resolve"
	if push:
		return "push"
	if resolve:
		return "resolve"
	return "base"


## Number of ordered 2d6 pairs that sum to [param total].
static func ways_to_roll(total: int) -> int:
	if total < 2 or total > 12:
		return 0
	return 6 - absi(total - 7)
