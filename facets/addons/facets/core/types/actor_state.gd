@tool
class_name FacetsActorState
extends RefCounted
## Session-owned live state for one actor. Created by explicit factories that
## copy from definitions; never shares nested data with a Resource.

var actor_id: String = ""
var display_name: String = ""
## "player" or "npc".
var controller: String = "player"
var identity: Dictionary = {}
var build: FacetsBuild = FacetsBuild.new()
## Admitted build before any purchases; the respec baseline.
var base_build: Dictionary = {}
## Identity trigger definitions copied from the character.
var identity_triggers: Array = []
var strain: int = FacetsRules.START_STRAIN
var resolve: int = FacetsRules.START_RESOLVE
var growth: int = FacetsRules.START_GROWTH
var harm: int = 0
var conditions: Array[String] = []
## item_id -> count (tools and consumables).
var items: Dictionary = {}
## other_id -> {trust, affinity, obligations, shared_events}
var bonds: Dictionary = {}
var known_facts: Array[String] = []
## Skills with host-confirmed practice or instruction.
var trained_skills: Array[String] = []
## Usage counters, e.g. "talent:core.second_look:scene:market".
var usage: Dictionary = {}
## Award ledger keyed by unique award key -> amount actually awarded.
var awards: Dictionary = {}
## Purchase ledger entries with actual paid costs.
var ledger: Array = []
var flags: Dictionary = {}
## Profile accomplishments survive journey resets.
var profile: Dictionary = {"accomplishments": []}
var zone_id: String = ""
## Imported memories stay source-labeled references until admitted.
var memories: Array = []


func strain_capacity() -> int:
	return build.strain_capacity()


func has_condition(condition_id: String) -> bool:
	return conditions.has(condition_id)


func is_overwhelmed() -> bool:
	return conditions.has(FacetsRules.CONDITION_OVERWHELMED)


func knows(fact_id: String) -> bool:
	return known_facts.has(fact_id)


func item_count(item_id: String) -> int:
	return int(items.get(item_id, 0))


func bond_value(other_id: String, dimension: String) -> int:
	var bond: Variant = bonds.get(other_id, {})
	if bond is Dictionary:
		return int(bond.get(dimension, 0))
	return 0


func to_dict() -> Dictionary:
	return {
		"actor_id": actor_id,
		"display_name": display_name,
		"controller": controller,
		"identity": identity.duplicate(true),
		"build": build.to_dict(),
		"base_build": base_build.duplicate(true),
		"identity_triggers": identity_triggers.duplicate(true),
		"strain": strain,
		"resolve": resolve,
		"growth": growth,
		"harm": harm,
		"conditions": conditions.duplicate(),
		"items": items.duplicate(true),
		"bonds": bonds.duplicate(true),
		"known_facts": known_facts.duplicate(),
		"trained_skills": trained_skills.duplicate(),
		"usage": usage.duplicate(true),
		"awards": awards.duplicate(true),
		"ledger": ledger.duplicate(true),
		"flags": flags.duplicate(true),
		"profile": profile.duplicate(true),
		"zone_id": zone_id,
		"memories": memories.duplicate(true),
	}


static func from_dict(source: Dictionary) -> FacetsActorState:
	var data: Dictionary = FacetsJson.normalize(source)
	var state := FacetsActorState.new()
	state.actor_id = str(data.get("actor_id", ""))
	state.display_name = str(data.get("display_name", ""))
	state.controller = str(data.get("controller", "player"))
	state.identity = data.get("identity", {}).duplicate(true)
	state.build = FacetsBuild.from_dict(data.get("build", {}))
	state.base_build = data.get("base_build", {}).duplicate(true)
	state.identity_triggers = data.get("identity_triggers", []).duplicate(true)
	state.strain = int(data.get("strain", 0))
	state.resolve = int(data.get("resolve", FacetsRules.START_RESOLVE))
	state.growth = int(data.get("growth", 0))
	state.harm = int(data.get("harm", 0))
	for item in data.get("conditions", []):
		state.conditions.append(str(item))
	state.items = data.get("items", {}).duplicate(true)
	state.bonds = data.get("bonds", {}).duplicate(true)
	for item in data.get("known_facts", []):
		state.known_facts.append(str(item))
	for item in data.get("trained_skills", []):
		state.trained_skills.append(str(item))
	state.usage = data.get("usage", {}).duplicate(true)
	state.awards = data.get("awards", {}).duplicate(true)
	state.ledger = data.get("ledger", []).duplicate(true)
	state.flags = data.get("flags", {}).duplicate(true)
	state.profile = data.get("profile", {"accomplishments": []}).duplicate(true)
	state.zone_id = str(data.get("zone_id", ""))
	state.memories = data.get("memories", []).duplicate(true)
	return state


func copy() -> FacetsActorState:
	return from_dict(to_dict())


## Explicit factory: copies primitive and nested values out of a definition.
static func from_character(character: FacetsCharacterResource) -> FacetsActorState:
	var state := FacetsActorState.new()
	state.actor_id = character.id
	state.display_name = character.display_name
	state.controller = character.controller
	state.identity = character.identity_dict()
	state.build = character.build()
	state.base_build = state.build.to_dict()
	for trigger in character.identity_triggers:
		if trigger != null:
			state.identity_triggers.append(trigger.to_dict())
	for item_id in character.items:
		state.items[str(item_id)] = int(character.items[item_id])
	for bond in character.bonds:
		if bond != null:
			state.bonds[bond.other_id] = {
				"trust": bond.trust,
				"affinity": bond.affinity,
				"obligations": Array(bond.obligations),
				"shared_events": Array(bond.shared_event_refs),
			}
	return state
