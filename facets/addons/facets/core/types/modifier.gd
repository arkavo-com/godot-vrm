@tool
class_name FacetsModifier
extends RefCounted
## One situational contribution to a check or a defense.
##
## Every modifier names where it came from ([member source_id]), which
## real-world factor it represents ([member factor_id]) and how it aggregates
## ([member scope]). The same factor may not be applied twice, even when one
## copy sits on the attacker and another on the defender.

const SCOPE_SITUATIONAL := "situational"
const SCOPE_ASSISTANCE := "assistance"
const SCOPE_RELATIONSHIP := "relationship"
const SCOPE_CONDITION := "condition"
const SCOPE_EQUIPMENT := "equipment"
const SCOPE_COVER := "cover"
const SCOPE_DEFEND := "defend"
const SCOPE_TALENT := "talent"

const SCOPES: Array[String] = [
	SCOPE_SITUATIONAL, SCOPE_ASSISTANCE, SCOPE_RELATIONSHIP, SCOPE_CONDITION,
	SCOPE_EQUIPMENT, SCOPE_COVER, SCOPE_DEFEND, SCOPE_TALENT,
]

var source_id: String = ""
var factor_id: String = ""
var scope: String = SCOPE_SITUATIONAL
var value: int = 0
## Player-facing explanation. Must not reveal private facts.
var label: String = ""


static func make(p_source_id: String, p_factor_id: String, p_scope: String, p_value: int, p_label: String = "") -> FacetsModifier:
	var modifier := FacetsModifier.new()
	modifier.source_id = p_source_id
	modifier.factor_id = p_factor_id
	modifier.scope = p_scope
	modifier.value = p_value
	modifier.label = p_label
	return modifier


func to_dict() -> Dictionary:
	return {
		"source_id": source_id,
		"factor_id": factor_id,
		"scope": scope,
		"value": value,
		"label": label,
	}


static func from_dict(data: Dictionary) -> FacetsModifier:
	return make(str(data.get("source_id", "")), str(data.get("factor_id", "")), str(data.get("scope", SCOPE_SITUATIONAL)), int(data.get("value", 0)), str(data.get("label", "")))
