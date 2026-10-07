@tool
class_name FacetsOdds
extends RefCounted
## Exact 36-outcome band counts for one fixed adjustment scenario.

const OUTCOMES := 36

var counts := {
	FacetsRules.BAND_FAILURE: 0,
	FacetsRules.BAND_COSTLY_OFFER: 0,
	FacetsRules.BAND_SUCCESS: 0,
	FacetsRules.BAND_STRONG: 0,
}
var allows_costly_success: bool = false
## Scenario label, e.g. "base", "push", "resolve", "push+resolve".
var scenario: String = "base"
var routine: bool = false


func count(band: String) -> int:
	return int(counts.get(band, 0))


func fraction(band: String) -> String:
	return "%d/%d" % [count(band), OUTCOMES]


## Percentage rounded to two decimals. Independently rounded rows may not
## total exactly 100.
func percent(band: String) -> float:
	return snappedf(100.0 * float(count(band)) / float(OUTCOMES), 0.01)


func percent_text(band: String) -> String:
	return "%.2f%%" % percent(band)


func success_or_better() -> int:
	return count(FacetsRules.BAND_SUCCESS) + count(FacetsRules.BAND_STRONG)


func to_dict() -> Dictionary:
	var rows := {}
	for band in FacetsRules.ODDS_BANDS:
		rows[band] = {"count": count(band), "fraction": fraction(band), "percent": percent_text(band)}
	return {
		"scenario": scenario,
		"routine": routine,
		"allows_costly_success": allows_costly_success,
		"outcomes": OUTCOMES,
		"bands": rows,
	}
