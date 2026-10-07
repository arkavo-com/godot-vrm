@tool
class_name FacetsRules
extends RefCounted
## FACETS core rule constants (rules draft v0.1). Pure, side-effect free.

const SCHEMA_VERSION := 1
const RULESET_ID := "facets.core"
const RULESET_VERSION := "0.1.0"

const FACETS: Array[String] = ["force", "agility", "cunning", "empathy", "tenacity", "sense"]
const CORE_SKILLS: Array[String] = [
	"athletics", "fighting", "marksmanship", "stealth", "sleight", "investigation",
	"survival", "technology", "craft", "medicine", "influence", "performance",
]
## Facets used by checks the rules call "physical" (implementation decision D-012).
const PHYSICAL_FACETS: Array[String] = ["force", "agility"]

const FACET_BASELINE := 2
const CREATION_FACET_POINTS := 6
const CREATION_FACET_CAP := 4
const CREATION_FACET_TOTAL := 18
const PROGRESSED_FACET_CAP := 5

const CREATION_SKILL_POINTS := 12
const CREATION_SKILL_CAP := 2
const SKILL_MIN := 0
const SKILL_MAX := 4

const STARTING_TALENTS := 2
const MAX_EQUIPPED_TALENTS := 6

const STRAIN_BASE := 4
const START_STRAIN := 0
const START_RESOLVE := 1
const START_GROWTH := 0
const RESOLVE_MIN := 0
const RESOLVE_MAX := 3

const BOND_MIN := -2
const BOND_MAX := 2

const MODIFIER_CAP := 3
const CONDITION_PENALTY_FLOOR := -2
const ASSISTANCE_MAX := 1
const RELATIONSHIP_MAX := 1

const PUSH_STRAIN := 2
const PUSH_BONUS := 1
const RESOLVE_COST := 1
const RESOLVE_BONUS := 2
const BREATHER_STRAIN := 2
const OVERWHELMED_PENALTY := -1
const IDENTITY_RESOLVE_AWARD := 1

const OPPOSED_BASE := 7

const MILESTONE_SMALL := 1
const MILESTONE_CHAPTER := 3
const SKILL_COST_PER_RANK := 2
const TALENT_COST := 5
const FACET_COST := 8

const TARGETS := {
	"favorable": 9,
	"standard": 11,
	"demanding": 13,
	"severe": 15,
	"extreme": 17,
	"legendary": 19,
}

const BAND_FAILURE := "failure"
const BAND_COSTLY_OFFER := "costly_offer"
const BAND_SUCCESS_WITH_COST := "success_with_cost"
const BAND_SUCCESS := "success"
const BAND_STRONG := "strong_success"

## Probability-inspector bands, in display order.
const ODDS_BANDS: Array[String] = [BAND_FAILURE, BAND_COSTLY_OFFER, BAND_SUCCESS, BAND_STRONG]

const CONDITION_OVERWHELMED := "core.overwhelmed"
const CONDITION_INJURED := "core.injured"
const CONDITION_INCAPACITATED := "core.incapacitated"
const INJURED_HARM := 3
const INCAPACITATED_HARM := 6
const REST_HARM_REMOVED := 2

const RESTRICTION_NO_PUSH := "no_push"
const RESTRICTION_NO_REACTIONS := "no_reactions"
const RESTRICTION_CANNOT_ACT := "cannot_act"
const RESTRICTION_LIMITED_TURN := "limited_turn"
const RESTRICTION_CANNOT_COMMUNICATE := "cannot_communicate"


static func strain_capacity(tenacity: int) -> int:
	return STRAIN_BASE + tenacity


static func clamp_modifier(value: int) -> int:
	return clampi(value, -MODIFIER_CAP, MODIFIER_CAP)


## Base band for a margin. The near-miss band is a provisional offer only when
## the action supports a costly success; otherwise it is failure.
static func band_for_margin(margin: int, allows_costly_success: bool) -> String:
	if margin >= 4:
		return BAND_STRONG
	if margin >= 0:
		return BAND_SUCCESS
	if margin >= -2:
		return BAND_COSTLY_OFFER if allows_costly_success else BAND_FAILURE
	return BAND_FAILURE


static func band_rank(band: String) -> int:
	match band:
		BAND_FAILURE:
			return 0
		BAND_COSTLY_OFFER, BAND_SUCCESS_WITH_COST:
			return 1
		BAND_SUCCESS:
			return 2
		BAND_STRONG:
			return 3
	return -1


static func is_success_band(band: String) -> bool:
	return band == BAND_SUCCESS or band == BAND_STRONG or band == BAND_SUCCESS_WITH_COST


static func target_for_tier(tier: String) -> int:
	return int(TARGETS.get(tier, 0))


static func opposed_target(defending_facet: int, defending_skill: int, defense_modifier_sum: int) -> int:
	return OPPOSED_BASE + defending_facet + defending_skill + clamp_modifier(defense_modifier_sum)


static func facet_index(facet_id: String) -> int:
	return FACETS.find(facet_id)
