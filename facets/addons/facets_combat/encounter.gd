@tool
class_name FacetsEncounter
extends RefCounted
## Optional zone combat (rules source section 7).
##
## Initiative is Agility + Sense descending, ties by actor ID. Each turn has
## one move and one action; the action may become a second move. One
## reaction per round, available from the first round. Close defense is
## 7 + Agility + Fighting; ranged defense 7 + Agility + Athletics; cover and
## Defend each add +2 once, within the +/-3 cap. Standard strikes have no
## costly success. Harm: light 1, standard 2, heavy 3, +1 on a strong hit,
## minus armor 0-2 (minimum 0). Harm 3 gives Injured, 6 Incapacitated.
## Death only under a declared lethal journey policy.
##
## The encounter works on copies of the actors' journey state. When it ends,
## [method journey_effects] returns allowlisted effects (harm and strain) for
## the host to apply to the session as one atomic batch.

const SUPPLIES: Array[String] = ["item.med_kit"]
const MEDICINE_TARGET := 11
const DEFEND_BONUS := 2
const COVER_BONUS := 2

var registry: FacetsRegistry
var zones: FacetsZoneMap
var dice: FacetsDiceSource
var world: FacetsWorldSnapshot
var combatants: Dictionary = {}
var order: Array[String] = []
var round: int = 0
var turn_index: int = -1
var lethal: bool = false
var ended: bool = false
var log: Array = []
var _start := {}


## [param setup]: actor_id -> {zone, weapon (FacetsWeaponResource.to_dict()), armor, ammo: {type: count}}.
## Options: "lethal" (bool, declared journey policy), "scene_id".
static func create(p_registry: FacetsRegistry, p_zones: FacetsZoneMap, actors: Array, setup: Dictionary, p_dice: FacetsDiceSource, options: Dictionary = {}) -> FacetsReply:
	var encounter := FacetsEncounter.new()
	encounter.registry = p_registry
	encounter.zones = p_zones
	encounter.dice = p_dice
	encounter.lethal = bool(options.get("lethal", false))
	encounter.world = FacetsWorldSnapshot.new()
	encounter.world.scene_id = str(options.get("scene_id", "encounter"))
	for state in actors:
		var copy: FacetsActorState = state.copy()
		var config: Dictionary = setup.get(copy.actor_id, {})
		if not p_zones.has_zone(str(config.get("zone", ""))):
			return FacetsReply.fail(FacetsError.UNKNOWN_ID, "%s needs a starting zone." % copy.display_name, "setup.%s.zone" % copy.actor_id)
		var armor := int(config.get("armor", 0))
		if armor < 0 or armor > FacetsCombat.ARMOR_MAX:
			return FacetsReply.fail(FacetsError.OUT_OF_RANGE, "Armor must be 0..2.", "setup.%s.armor" % copy.actor_id)
		encounter.world.add_actor(copy)
		encounter._start[copy.actor_id] = {"harm": copy.harm, "strain": copy.strain}
		encounter.combatants[copy.actor_id] = {
			"zone": str(config["zone"]),
			"weapon": config.get("weapon", {}).duplicate(true),
			"armor": armor,
			"ammo": config.get("ammo", {}).duplicate(),
			"reaction_available": true,
			"defending": false,
			"moves": 0,
			"action_used": false,
			"moved": false,
			"attacked_heavy": false,
			"last_reserve_active": false,
			"medicine_received": false,
			"stabilized": false,
			"dead": false,
		}
	encounter.order = initiative_order(encounter.world)
	encounter.round = 1
	encounter.turn_index = -1
	encounter._advance_to_next_actor()
	return FacetsReply.success(encounter)


## Agility + Sense descending; ties broken by actor ID ascending.
static func initiative_order(p_world: FacetsWorldSnapshot) -> Array[String]:
	var ids: Array[String] = []
	for actor_id in p_world.actors:
		ids.append(str(actor_id))
	ids.sort_custom(func(a: String, b: String) -> bool:
		var sa := p_world.actor(a).build.facet("agility") + p_world.actor(a).build.facet("sense")
		var sb := p_world.actor(b).build.facet("agility") + p_world.actor(b).build.facet("sense")
		if sa != sb:
			return sa > sb
		return a < b)
	return ids


func current_actor() -> String:
	if ended or turn_index < 0 or turn_index >= order.size():
		return ""
	return order[turn_index]


func actor(actor_id: String) -> FacetsActorState:
	return world.actor(actor_id)


func state(actor_id: String) -> Dictionary:
	return combatants.get(actor_id, {})


func _restricted(actor_id: String, restriction: String) -> bool:
	return FacetsCheckPlanner.restricted(registry, world.actor(actor_id), restriction)


func can_act(actor_id: String) -> bool:
	return not _restricted(actor_id, FacetsRules.RESTRICTION_CANNOT_ACT) and not bool(state(actor_id).get("dead", false))


func can_react(actor_id: String) -> bool:
	return bool(state(actor_id).get("reaction_available", false)) and can_act(actor_id) and not _restricted(actor_id, FacetsRules.RESTRICTION_NO_REACTIONS)


## Overwhelmed actors get a move or an action, not both, unless Last Reserve.
func _limited(actor_id: String) -> bool:
	return _restricted(actor_id, FacetsRules.RESTRICTION_LIMITED_TURN) and not bool(state(actor_id)["last_reserve_active"])


func _require_turn(actor_id: String) -> FacetsReply:
	if ended:
		return FacetsReply.fail(FacetsError.NOT_APPLICABLE, "The encounter has ended.")
	if actor_id != current_actor():
		return FacetsReply.fail(FacetsError.NOT_AUTHORIZED, "It is not %s's turn." % (world.actor(actor_id).display_name if world.has_actor(actor_id) else actor_id), "actor_id")
	if not can_act(actor_id):
		return FacetsReply.fail(FacetsError.INELIGIBLE, "%s cannot act." % world.actor(actor_id).display_name, "actor_id")
	return FacetsReply.success(true)


func _require_action(actor_id: String) -> FacetsReply:
	var c: Dictionary = combatants[actor_id]
	if bool(c["action_used"]):
		return FacetsReply.fail(FacetsError.ALREADY_USED, "Already acted this turn.", "action")
	if _limited(actor_id) and int(c["moves"]) > 0:
		return FacetsReply.fail(FacetsError.INELIGIBLE, "Overwhelmed: move or act this turn, not both.", "action")
	return FacetsReply.success(true)


# --- Turn flow ------------------------------------------------------------------------

func move(actor_id: String, zone_id: String) -> FacetsReply:
	var turn := _require_turn(actor_id)
	if not turn.ok:
		return turn
	var c: Dictionary = combatants[actor_id]
	if _restricted(actor_id, "no_move"):
		return FacetsReply.fail(FacetsError.INELIGIBLE, "Cannot move.", "zone_id")
	if not zones.adjacent(str(c["zone"]), zone_id):
		return FacetsReply.fail(FacetsError.INELIGIBLE, "That zone is not adjacent.", "zone_id")
	if bool(c["attacked_heavy"]):
		return FacetsReply.fail(FacetsError.INELIGIBLE, "Heavy weapon: no moving in the turn you attack.", "zone_id")
	var limited := _limited(actor_id)
	if limited and (int(c["moves"]) > 0 or bool(c["action_used"])):
		return FacetsReply.fail(FacetsError.INELIGIBLE, "Overwhelmed: move or act this turn, not both.", "zone_id")
	if int(c["moves"]) == 0:
		c["moves"] = 1
	elif not bool(c["action_used"]):
		c["moves"] = 2
		c["action_used"] = true
	else:
		return FacetsReply.fail(FacetsError.ALREADY_USED, "No movement left this turn.", "zone_id")
	var from: String = c["zone"]
	c["zone"] = zone_id
	c["moved"] = true
	return _log({"kind": "move", "actor_id": actor_id, "from": from, "to": zone_id, "uses_action": int(c["moves"]) == 2})


func defend(actor_id: String) -> FacetsReply:
	var turn := _require_turn(actor_id)
	if not turn.ok:
		return turn
	var action := _require_action(actor_id)
	if not action.ok:
		return action
	combatants[actor_id]["action_used"] = true
	combatants[actor_id]["defending"] = true
	return _log({"kind": "defend", "actor_id": actor_id})


func end_turn(actor_id: String) -> FacetsReply:
	if actor_id != current_actor():
		return FacetsReply.fail(FacetsError.NOT_AUTHORIZED, "It is not that actor's turn.", "actor_id")
	_advance_to_next_actor()
	return _log({"kind": "end_turn", "actor_id": actor_id, "next": current_actor(), "round": round})


func _advance_to_next_actor() -> void:
	for attempt in order.size() + 1:
		turn_index += 1
		if turn_index >= order.size():
			turn_index = 0
			round += 1
		if turn_index == 0:
			# One reaction per round, refreshed at the top of every round.
			for actor_id in combatants:
				combatants[actor_id]["reaction_available"] = true
		var actor_id := order[turn_index]
		var c: Dictionary = combatants[actor_id]
		c["defending"] = false
		c["moves"] = 0
		c["action_used"] = false
		c["moved"] = false
		c["attacked_heavy"] = false
		c["last_reserve_active"] = false
		if can_act(actor_id):
			return
		log.append({"kind": "skip", "actor_id": actor_id, "round": round, "reason": "cannot act"})
	turn_index = -1


## Last Reserve: while Overwhelmed, take one normal turn once per scene. It
## does not restore the reaction and cannot be used while Incapacitated.
func use_last_reserve(actor_id: String) -> FacetsReply:
	var turn := _require_turn(actor_id)
	if not turn.ok:
		return turn
	var talent_id := FacetsTalents.find(registry, world.actor(actor_id), "last_reserve")
	if talent_id.is_empty():
		return FacetsReply.fail(FacetsError.NOT_APPLICABLE, "Last Reserve is not equipped.", "talent_id")
	if not world.actor(actor_id).is_overwhelmed():
		return FacetsReply.fail(FacetsError.NOT_APPLICABLE, "Last Reserve is for Overwhelmed characters.", "talent_id")
	var c: Dictionary = combatants[actor_id]
	if int(c["moves"]) > 0 or bool(c["action_used"]):
		return FacetsReply.fail(FacetsError.NOT_APPLICABLE, "Declare Last Reserve at the start of your turn.", "talent_id")
	if FacetsTalents.uses_left(registry, world.actor(actor_id), talent_id, world.scene_id) <= 0:
		return FacetsReply.fail(FacetsError.USAGE_LIMIT, "Last Reserve was already used this scene.", "talent_id")
	FacetsTxn.begin(world).increment_usage(actor_id, FacetsTalents.usage_key(talent_id, world.scene_id))
	c["last_reserve_active"] = true
	return _log({"kind": "last_reserve", "actor_id": actor_id})


# --- Attacks -------------------------------------------------------------------------

## Options: "push" (bool), "interceptor_id" (a Bodyguard declared by the
## defending side; it takes the hit only if the attack lands).
func attack(attacker_id: String, target_id: String, approach_id: String, options: Dictionary = {}) -> FacetsReply:
	var turn := _require_turn(attacker_id)
	if not turn.ok:
		return turn
	var action := _require_action(attacker_id)
	if not action.ok:
		return action
	if not combatants.has(target_id) or target_id == attacker_id:
		return FacetsReply.fail(FacetsError.UNKNOWN_ID, "Unknown target.", "target_id")
	var c: Dictionary = combatants[attacker_id]
	var t: Dictionary = combatants[target_id]
	var weapon: Dictionary = c["weapon"]
	var approach := {}
	for item in weapon.get("approaches", []):
		if str(item.get("id", "")) == approach_id:
			approach = item
	if approach.is_empty():
		return FacetsReply.fail(FacetsError.UNKNOWN_ID, "That weapon has no such approach.", "approach_id")
	var range_band := str(weapon.get("range_band", "close"))
	var distance := zones.band(str(c["zone"]), str(t["zone"]))
	var in_range := false
	match range_band:
		"close":
			in_range = distance == "same"
		"ranged":
			in_range = distance != "distant" and zones.visible(str(c["zone"]), str(t["zone"]))
		"long":
			in_range = zones.visible(str(c["zone"]), str(t["zone"]))
	if not in_range:
		return FacetsReply.fail(FacetsError.INELIGIBLE, "Target is out of range or out of sight.", "target_id")
	var ammo_type := str(weapon.get("ammo_type", ""))
	if not ammo_type.is_empty() and int(c["ammo"].get(ammo_type, 0)) <= 0:
		return FacetsReply.fail(FacetsError.INELIGIBLE, "No compatible ammunition.", "weapon")
	var heavy := str(weapon.get("harm_class", "")) == "heavy"
	if heavy and bool(c["moved"]):
		return FacetsReply.fail(FacetsError.INELIGIBLE, "Heavy weapon: no attacking after moving this turn.", "weapon")
	var attacker := world.actor(attacker_id)
	var push := bool(options.get("push", false))
	if push and (attacker.is_overwhelmed() or _restricted(attacker_id, FacetsRules.RESTRICTION_NO_PUSH) or not FacetsCheckPlanner.push_allowed(attacker.strain, attacker.strain_capacity())):
		return FacetsReply.fail(FacetsError.PUSH_NOT_ALLOWED, "Cannot push this attack.", "push")
	var interceptor_id := str(options.get("interceptor_id", ""))
	if not interceptor_id.is_empty():
		var eligible := bodyguard_eligible(interceptor_id, target_id, attacker_id)
		if not eligible.ok:
			return eligible

	# Defense: the defender never rolls.
	var target := world.actor(target_id)
	var defense_skill := "fighting" if range_band == "close" else "athletics"
	var defense_modifiers: Array[FacetsModifier] = []
	if range_band != "close" and zones.has_cover(str(t["zone"])):
		defense_modifiers.append(FacetsModifier.make("zone:%s" % t["zone"], "cover", FacetsModifier.SCOPE_COVER, COVER_BONUS, "Cover"))
	if bool(t["defending"]):
		defense_modifiers.append(FacetsModifier.make(target_id, "defend", FacetsModifier.SCOPE_DEFEND, DEFEND_BONUS, "Defending"))
	var attack_modifiers := FacetsCheckPlanner.condition_modifiers(registry, attacker, str(approach["facet"]))
	var modifier_errors := FacetsModifiers.validate(attack_modifiers, defense_modifiers)
	if not modifier_errors.is_empty():
		return FacetsReply.failures(modifier_errors)
	var defense_sum := int(FacetsModifiers.aggregate(defense_modifiers)["raw"])
	var target_number := FacetsRules.opposed_target(target.build.facet("agility"), target.build.skill(defense_skill), defense_sum)
	var check := FacetsCheckInput.make(attacker.build.facet(str(approach["facet"])), attacker.build.skill(str(approach["skill"])), target_number, false)
	var pair := dice.roll_pair()
	if pair == Vector2i.ZERO:
		return FacetsReply.fail(FacetsError.DICE_UNAVAILABLE, "No dice are available.", "", true)
	var txn := FacetsTxn.begin(world)
	if push:
		txn.add_strain(attacker_id, FacetsRules.PUSH_STRAIN)
	var evaluation := FacetsResolver.evaluate_with_sum(check, pair, int(FacetsModifiers.aggregate(attack_modifiers)["raw"]), push, false)
	c["action_used"] = true
	if heavy:
		c["attacked_heavy"] = true
	var hit := evaluation.band == FacetsRules.BAND_SUCCESS or evaluation.band == FacetsRules.BAND_STRONG
	var entry := {
		"kind": "attack", "actor_id": attacker_id, "target_id": target_id, "weapon": weapon.get("id", ""),
		"dice": [pair.x, pair.y], "total": evaluation.total, "defense": target_number,
		"defense_modifier": FacetsRules.clamp_modifier(defense_sum), "band": evaluation.band, "hit": hit,
		"recipient_id": "", "harm": 0, "armor": 0, "applied": 0, "intercepted_by": "",
	}
	if hit:
		var recipient_id := target_id
		if not interceptor_id.is_empty():
			# One interception per hit; the interceptor cannot be intercepted in turn.
			recipient_id = interceptor_id
			combatants[interceptor_id]["reaction_available"] = false
			var talent_id := FacetsTalents.find(registry, world.actor(interceptor_id), "bodyguard")
			txn.increment_usage(interceptor_id, "talent:%s:round:%d" % [talent_id, round])
			entry["intercepted_by"] = interceptor_id
		var harm := FacetsCombat.harm_for(str(weapon.get("harm_class", "standard"))) + (1 if evaluation.band == FacetsRules.BAND_STRONG else 0)
		var armor := int(combatants[recipient_id]["armor"])
		var applied := maxi(0, harm - armor)
		txn.add_harm(recipient_id, applied)
		txn.sync_harm_conditions(recipient_id)
		entry["recipient_id"] = recipient_id
		entry["harm"] = harm
		entry["armor"] = armor
		entry["applied"] = applied
	if txn.failed():
		return FacetsReply.failure(txn.error)
	return _log(entry)


## Bodyguard: once per round, using the reaction, from the target's zone
## along a clear path. Overwhelmed or Incapacitated interceptors cannot react.
func bodyguard_eligible(interceptor_id: String, target_id: String, attacker_id: String) -> FacetsReply:
	if not combatants.has(interceptor_id) or interceptor_id == target_id or interceptor_id == attacker_id:
		return FacetsReply.fail(FacetsError.UNKNOWN_ID, "Unknown interceptor.", "interceptor_id")
	var interceptor := world.actor(interceptor_id)
	var talent_id := FacetsTalents.find(registry, interceptor, "bodyguard")
	if talent_id.is_empty():
		return FacetsReply.fail(FacetsError.NOT_APPLICABLE, "%s does not have Bodyguard." % interceptor.display_name, "interceptor_id")
	if not can_react(interceptor_id):
		return FacetsReply.fail(FacetsError.INELIGIBLE, "%s has no reaction available." % interceptor.display_name, "interceptor_id")
	if str(combatants[interceptor_id]["zone"]) != str(combatants[target_id]["zone"]):
		return FacetsReply.fail(FacetsError.INELIGIBLE, "Bodyguard must share the target's zone.", "interceptor_id")
	if _restricted(interceptor_id, "no_move") or zones.zones.get(str(combatants[target_id]["zone"]), {}).get("blocked_paths", []).has(interceptor_id):
		return FacetsReply.fail(FacetsError.INELIGIBLE, "No clear path to the target.", "interceptor_id")
	var allowed := int(FacetsTalents.params(registry, talent_id).get("uses_per_round", 1))
	if int(interceptor.usage.get("talent:%s:round:%d" % [talent_id, round], 0)) >= allowed:
		return FacetsReply.fail(FacetsError.USAGE_LIMIT, "Bodyguard was already used this round.", "interceptor_id")
	return FacetsReply.success(true)


# --- Medicine ------------------------------------------------------------------------

## Medicine vs 11 with supplies and an action on a willing patient in the
## same zone: success removes 1 harm, strong 2; no costly success; one
## benefit per patient per encounter. An Incapacitated patient treated
## successfully is stabilized but stays unable to act until the encounter
## ends with harm below 6.
func medicine(healer_id: String, patient_id: String, facet_id: String = "sense") -> FacetsReply:
	var turn := _require_turn(healer_id)
	if not turn.ok:
		return turn
	var action := _require_action(healer_id)
	if not action.ok:
		return action
	if not combatants.has(patient_id):
		return FacetsReply.fail(FacetsError.UNKNOWN_ID, "Unknown patient.", "patient_id")
	if not ["sense", "cunning"].has(facet_id):
		return FacetsReply.fail(FacetsError.INVALID_FIELD, "Medicine uses Sense or Cunning.", "facet_id")
	var healer := world.actor(healer_id)
	var patient := world.actor(patient_id)
	if not SUPPLIES.any(func(item_id: String) -> bool: return healer.item_count(item_id) > 0):
		return FacetsReply.fail(FacetsError.INELIGIBLE, "Medicine needs supplies.", "items")
	if str(combatants[healer_id]["zone"]) != str(combatants[patient_id]["zone"]):
		return FacetsReply.fail(FacetsError.INELIGIBLE, "The patient must be in your zone.", "patient_id")
	if bool(patient.flags.get("unwilling", false)):
		return FacetsReply.fail(FacetsError.INELIGIBLE, "%s refuses treatment." % patient.display_name, "patient_id")
	if bool(combatants[patient_id]["medicine_received"]):
		return FacetsReply.fail(FacetsError.ALREADY_USED, "%s already benefited from medicine this encounter." % patient.display_name, "patient_id")
	var pair := dice.roll_pair()
	if pair == Vector2i.ZERO:
		return FacetsReply.fail(FacetsError.DICE_UNAVAILABLE, "No dice are available.", "", true)
	var check := FacetsCheckInput.make(healer.build.facet(facet_id), healer.build.skill("medicine"), MEDICINE_TARGET, false)
	var evaluation := FacetsResolver.evaluate_with_sum(check, pair, int(FacetsModifiers.aggregate(FacetsCheckPlanner.condition_modifiers(registry, healer, facet_id))["raw"]), false, false)
	combatants[healer_id]["action_used"] = true
	var removed := 0
	var stabilized := false
	if evaluation.band == FacetsRules.BAND_SUCCESS or evaluation.band == FacetsRules.BAND_STRONG:
		var txn := FacetsTxn.begin(world)
		var was_incapacitated := patient.has_condition(FacetsRules.CONDITION_INCAPACITATED)
		removed = -txn.add_harm(patient_id, -(2 if evaluation.band == FacetsRules.BAND_STRONG else 1))
		if was_incapacitated:
			combatants[patient_id]["stabilized"] = true
			stabilized = true
		else:
			txn.sync_harm_conditions(patient_id)
		combatants[patient_id]["medicine_received"] = true
	return _log({"kind": "medicine", "actor_id": healer_id, "patient_id": patient_id, "dice": [pair.x, pair.y], "total": evaluation.total, "target": MEDICINE_TARGET, "band": evaluation.band, "harm_removed": removed, "stabilized": stabilized})


# --- End -------------------------------------------------------------------------------

## Ends the encounter. Incapacitated actors with harm below 6 recover the
## ability to act; under a lethal journey policy, unstabilized actors still
## at 6+ harm die. Returns per-actor outcomes.
func end_encounter() -> FacetsReply:
	if ended:
		return FacetsReply.fail(FacetsError.ALREADY_USED, "The encounter already ended.")
	ended = true
	var outcomes := {}
	var txn := FacetsTxn.begin(world)
	for actor_id in combatants:
		var state_actor := world.actor(actor_id)
		txn.sync_harm_conditions(actor_id)
		var dead := lethal and state_actor.harm >= FacetsRules.INCAPACITATED_HARM and not bool(combatants[actor_id]["stabilized"])
		combatants[actor_id]["dead"] = dead
		outcomes[actor_id] = {"harm": state_actor.harm, "strain": state_actor.strain, "conditions": Array(state_actor.conditions), "dead": dead}
	_log({"kind": "end", "outcomes": outcomes})
	return FacetsReply.success(outcomes)


## Allowlisted effects that write this encounter's harm and strain back to
## the session's journey state (apply with session.apply_host_effects).
func journey_effects(actor_id: String) -> Array:
	var effects: Array = []
	var start: Dictionary = _start.get(actor_id, {})
	var current := world.actor(actor_id)
	if current == null:
		return effects
	var harm_delta := current.harm - int(start.get("harm", 0))
	if harm_delta != 0:
		effects.append({"op": "actor.harm", "params": {"amount": harm_delta}, "label": "Combat harm"})
	var strain_delta := current.strain - int(start.get("strain", 0))
	if strain_delta != 0:
		effects.append({"op": "actor.strain", "params": {"amount": strain_delta}, "label": "Combat strain"})
	return effects


func _log(entry: Dictionary) -> FacetsReply:
	entry["round"] = round
	log.append(entry)
	return FacetsReply.success(entry)
