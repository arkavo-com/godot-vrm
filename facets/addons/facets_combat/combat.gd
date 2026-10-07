@tool
class_name FacetsCombat
extends RefCounted
## Entry point of the optional combat package. Core never depends on it.

const PACK_PATH := "res://addons/facets_combat/content/combat_pack.tres"
const HARM := {"light": 1, "standard": 2, "heavy": 3}
const ARMOR_MAX := 2


## Registers the combat talent hooks (Bodyguard, Last Reserve).
static func register_hooks(registry: FacetsRegistry) -> void:
	if not registry.hooks.has_hook("bodyguard"):
		registry.hooks.register("bodyguard", "combat", {"uses_per_round": "int"},
			"Use your reaction to take a hit meant for a same-zone ally along a clear path; your armor applies.")
	if not registry.hooks.has_hook("last_reserve"):
		registry.hooks.register("last_reserve", "combat", {"uses_per_scene": "int"},
			"While Overwhelmed, take one normal turn once per scene; no reaction restored, never while Incapacitated.")


## Registers hooks and the combat pack (two talents), completing all eight
## source talents.
static func register(registry: FacetsRegistry) -> FacetsReply:
	register_hooks(registry)
	if registry.pack_versions().has("facets.combat"):
		return FacetsReply.success("facets.combat")
	var pack := load(PACK_PATH) as FacetsRulesPack
	if pack == null:
		return FacetsReply.fail(FacetsError.UNKNOWN_ID, "Combat pack missing.", "pack")
	return registry.register_pack(pack)


static func harm_for(harm_class: String) -> int:
	return int(HARM.get(harm_class, 0))
