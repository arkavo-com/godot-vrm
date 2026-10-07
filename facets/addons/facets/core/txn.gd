@tool
class_name FacetsTxn
extends RefCounted
## Staged transaction: applies low-level ops to a staged world copy as they
## are produced and records them for the journal. Nothing reaches the live
## session state until the session swaps the staged world in after a
## successful durable write.

var world: FacetsWorldSnapshot
var ops: Array = []
var error: FacetsError = null


static func begin(staged_world: FacetsWorldSnapshot) -> FacetsTxn:
	var txn := FacetsTxn.new()
	txn.world = staged_world
	return txn


func failed() -> bool:
	return error != null


func fail(p_error: FacetsError) -> bool:
	if error == null:
		error = p_error
	return false


func _apply(op: Dictionary) -> bool:
	if failed():
		return false
	var op_error := FacetsReducer.apply_op(world, op)
	if op_error != null:
		return fail(op_error)
	ops.append(op)
	return true


func read(path: Array) -> Variant:
	return FacetsReducer.read_path(world, path)


func set_path(path: Array, after: Variant) -> bool:
	var before: Variant = read(path)
	if FacetsJson.equal(before, after):
		return true
	return _apply(FacetsReducer.set_op(path, before, after))


func append(path: Array, value: Variant) -> bool:
	return _apply(FacetsReducer.append_op(path, value))


func remove(path: Array, value: Variant) -> bool:
	return _apply(FacetsReducer.remove_op(path, value))


func note(kind: String, data: Dictionary = {}) -> void:
	if not failed():
		ops.append(FacetsReducer.note_op(kind, data))


func _actor(actor_id: String) -> FacetsActorState:
	var state := world.actor(actor_id)
	if state == null:
		fail(FacetsError.make(FacetsError.UNKNOWN_ID, "Unknown actor.", "actor_id").with_detail(actor_id))
	return state


# --- World -----------------------------------------------------------------

func ensure_object(object_id: String) -> bool:
	if world.objects.has(object_id):
		return true
	return set_path(["objects", object_id], {})


func set_object_flag(object_id: String, key: String, value: Variant) -> bool:
	if not ensure_object(object_id):
		return false
	return set_path(["objects", object_id, key], value)


func set_fact(fact_id: String, value: Variant, visibility: String = "public", label: String = "") -> bool:
	var current: Variant = world.facts.get(fact_id)
	var record: Dictionary = current.duplicate(true) if current is Dictionary else {"visibility": visibility, "label": label}
	record["value"] = value
	if not current is Dictionary:
		record["visibility"] = visibility
	return set_path(["facts", fact_id], record)


func add_counter(counter_id: String, amount: int) -> bool:
	return set_path(["counters", counter_id], int(world.counters.get(counter_id, 0)) + amount)


func advance_clock(amount: int) -> bool:
	if amount == 0:
		return true
	return set_path(["clock"], world.clock + amount)


func set_lock(lock_key: String, value: Variant) -> bool:
	return set_path(["retry_locks", lock_key], value)


func record_world_award(key: String, value: Variant) -> bool:
	return set_path(["awards", key], value)


# --- Actors ----------------------------------------------------------------

## Adds (or removes, if negative) strain, clamped to 0..capacity, and keeps
## Overwhelmed in sync. Returns the applied delta.
func add_strain(actor_id: String, amount: int, scene_id: String = "", fear: bool = false) -> int:
	var state := _actor(actor_id)
	if state == null:
		return 0
	var capacity := state.strain_capacity()
	var after := clampi(state.strain + amount, 0, capacity)
	var delta := after - state.strain
	set_path(["actors", actor_id, "strain"], after)
	sync_overwhelmed(actor_id)
	if fear and amount > 0 and not scene_id.is_empty():
		set_actor_flag(actor_id, "fear_setback_scene", scene_id)
	return delta


func set_strain(actor_id: String, value: int) -> int:
	var state := _actor(actor_id)
	if state == null:
		return 0
	return add_strain(actor_id, value - state.strain)


## At capacity apply Overwhelmed; below capacity remove it.
func sync_overwhelmed(actor_id: String) -> void:
	var state := _actor(actor_id)
	if state == null:
		return
	var at_capacity := state.strain >= state.strain_capacity()
	if at_capacity and not state.is_overwhelmed():
		add_condition(actor_id, FacetsRules.CONDITION_OVERWHELMED)
	elif not at_capacity and state.is_overwhelmed():
		remove_condition(actor_id, FacetsRules.CONDITION_OVERWHELMED)


## Returns the applied delta after clamping Resolve to 0..3.
func add_resolve(actor_id: String, amount: int) -> int:
	var state := _actor(actor_id)
	if state == null:
		return 0
	var after := clampi(state.resolve + amount, FacetsRules.RESOLVE_MIN, FacetsRules.RESOLVE_MAX)
	var delta := after - state.resolve
	set_path(["actors", actor_id, "resolve"], after)
	return delta


func add_growth(actor_id: String, amount: int) -> bool:
	var state := _actor(actor_id)
	if state == null:
		return false
	if state.growth + amount < 0:
		return fail(FacetsError.make(FacetsError.INSUFFICIENT, "Not enough Growth.", "growth"))
	return set_path(["actors", actor_id, "growth"], state.growth + amount)


func add_harm(actor_id: String, amount: int) -> int:
	var state := _actor(actor_id)
	if state == null:
		return 0
	var after := maxi(0, state.harm + amount)
	var delta := after - state.harm
	set_path(["actors", actor_id, "harm"], after)
	return delta


## Harm 3+ gives Injured, 6+ Incapacitated; both clear below the threshold.
func sync_harm_conditions(actor_id: String) -> void:
	var state := _actor(actor_id)
	if state == null:
		return
	if state.harm >= FacetsRules.INJURED_HARM:
		add_condition(actor_id, FacetsRules.CONDITION_INJURED)
	else:
		remove_condition(actor_id, FacetsRules.CONDITION_INJURED)
	if state.harm >= FacetsRules.INCAPACITATED_HARM:
		add_condition(actor_id, FacetsRules.CONDITION_INCAPACITATED)
	else:
		remove_condition(actor_id, FacetsRules.CONDITION_INCAPACITATED)


func add_actor(state: FacetsActorState) -> bool:
	if world.has_actor(state.actor_id):
		return fail(FacetsError.make(FacetsError.DUPLICATE, "Actor already exists.", "actor_id"))
	return _apply({"op": "add_actor", "actor": state.to_dict()})


func add_condition(actor_id: String, condition_id: String) -> bool:
	var state := _actor(actor_id)
	if state == null or state.has_condition(condition_id):
		return state != null
	return append(["actors", actor_id, "conditions"], condition_id)


func remove_condition(actor_id: String, condition_id: String) -> bool:
	var state := _actor(actor_id)
	if state == null or not state.has_condition(condition_id):
		return state != null
	return remove(["actors", actor_id, "conditions"], condition_id)


func reveal_fact(actor_id: String, fact_id: String) -> bool:
	var state := _actor(actor_id)
	if state == null or state.knows(fact_id):
		return state != null
	return append(["actors", actor_id, "known_facts"], fact_id)


func add_item(actor_id: String, item_id: String, amount: int) -> bool:
	var state := _actor(actor_id)
	if state == null:
		return false
	var after := state.item_count(item_id) + amount
	if after < 0:
		return fail(FacetsError.make(FacetsError.INSUFFICIENT, "Item is not available.", "items.%s" % item_id))
	return set_path(["actors", actor_id, "items", item_id], after if after > 0 else null)


func increment_usage(actor_id: String, key: String, amount: int = 1) -> bool:
	var state := _actor(actor_id)
	if state == null:
		return false
	return set_path(["actors", actor_id, "usage", key], int(state.usage.get(key, 0)) + amount)


func record_award(actor_id: String, key: String, amount: int) -> bool:
	return set_path(["actors", actor_id, "awards", key], amount)


func set_actor_flag(actor_id: String, key: String, value: Variant) -> bool:
	return set_path(["actors", actor_id, "flags", key], value)


func ensure_bond(actor_id: String, other_id: String) -> bool:
	var state := _actor(actor_id)
	if state == null:
		return false
	if state.bonds.has(other_id):
		return true
	return set_path(["actors", actor_id, "bonds", other_id], {"trust": 0, "affinity": 0, "obligations": [], "shared_events": []})


func adjust_bond(actor_id: String, other_id: String, dimension: String, amount: int) -> bool:
	if dimension != "trust" and dimension != "affinity":
		return fail(FacetsError.make(FacetsError.INVALID_FIELD, "Bond dimension must be trust or affinity.", "dimension"))
	if not ensure_bond(actor_id, other_id):
		return false
	var current := world.actor(actor_id).bond_value(other_id, dimension)
	return set_path(["actors", actor_id, "bonds", other_id, dimension], clampi(current + amount, FacetsRules.BOND_MIN, FacetsRules.BOND_MAX))


func add_obligation(actor_id: String, other_id: String, obligation: String) -> bool:
	if not ensure_bond(actor_id, other_id):
		return false
	return append(["actors", actor_id, "bonds", other_id, "obligations"], obligation)
