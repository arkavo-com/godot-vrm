@tool
class_name FacetsProbabilityTable
extends RefCounted
## Data for the probability inspector: all 36 dice pairs in four bands with
## exact fractions and rounded percentages, one table per fixed scenario.
## The second band is an offer, not a guaranteed success; when the action
## has no costly success it is merged into failure.

const LABELS := {
	FacetsRules.BAND_FAILURE: "Failure",
	FacetsRules.BAND_COSTLY_OFFER: "Costly-success offer",
	FacetsRules.BAND_SUCCESS: "Success",
	FacetsRules.BAND_STRONG: "Strong success",
}


static func build(facet: int, skill: int, target: int, modifier_sum: int, allows_costly: bool, push_available: bool, resolve_available: bool) -> Dictionary:
	var check := FacetsCheckInput.make(facet, skill, target, allows_costly)
	var scenarios: Array = []
	var options := [[false, false]]
	if push_available:
		options.append([true, false])
	if resolve_available:
		options.append([false, true])
	if push_available and resolve_available:
		options.append([true, true])
	for option in options:
		var odds := FacetsProbability.enumerate_sum(check, modifier_sum, option[0], option[1])
		var rows: Array = []
		for band in FacetsRules.ODDS_BANDS:
			if band == FacetsRules.BAND_COSTLY_OFFER and not allows_costly:
				continue
			rows.append({"band": band, "label": LABELS[band], "count": odds.count(band), "fraction": odds.fraction(band), "percent": odds.percent_text(band)})
		scenarios.append({"scenario": odds.scenario, "title": _title(odds.scenario), "rows": rows})
	var notes: Array[String] = []
	if facet > FacetsRules.CREATION_FACET_CAP or skill > FacetsRules.CREATION_SKILL_CAP:
		notes.append("Advanced build: facet %d / skill %d exceed standard creation values." % [facet, skill])
	if modifier_sum != FacetsRules.clamp_modifier(modifier_sum):
		notes.append("Situational modifiers capped from %+d to %+d." % [modifier_sum, FacetsRules.clamp_modifier(modifier_sum)])
	notes.append("Percentages are rounded independently and may not total exactly 100%.")
	return {"facet": facet, "skill": skill, "target": target, "modifier_sum": modifier_sum, "allows_costly_success": allows_costly, "scenarios": scenarios, "notes": notes}


static func _title(scenario: String) -> String:
	match scenario:
		"push":
			return "With Push (+1, 2 strain)"
		"resolve":
			return "If 1 Resolve is spent after the roll (+2)"
		"push+resolve":
			return "Push and Resolve"
	return "Base"


static func as_text(table: Dictionary) -> String:
	var lines: Array[String] = []
	for scenario in table["scenarios"]:
		lines.append(scenario["title"])
		for row in scenario["rows"]:
			lines.append("  %-22s %6s  %7s" % [row["label"], row["fraction"], row["percent"]])
	for note in table["notes"]:
		lines.append(note)
	return "\n".join(lines)
