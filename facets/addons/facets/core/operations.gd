@tool
class_name FacetsOperations
extends RefCounted
## OperationRegistry: allowlisted requirements and effects with parameter
## schemas and deterministic evaluation. Content references operations by ID;
## unknown operations or parameters fail validation.
##
## Parameter schema types: "string", "int", "bool", "scalar" (string, int or
## bool), "string_list". A trailing "?" marks an optional parameter.

const KIND_REQUIREMENT := "requirement"
const KIND_EFFECT := "effect"

var _ops := {}


static func with_core() -> FacetsOperations:
	var operations := FacetsOperations.new()
	operations._register_core_requirements()
	operations._register_core_effects()
	return operations


func register(kind: String, op_id: String, version: int, param_schema: Dictionary, fn: Callable, description: String = "") -> void:
	_ops[op_id] = {
		"kind": kind,
		"version": version,
		"params": param_schema.duplicate(),
		"fn": fn,
		"description": description,
	}


func has_op(kind: String, op_id: String) -> bool:
	return _ops.has(op_id) and _ops[op_id]["kind"] == kind


func op_ids(kind: String) -> Array[String]:
	var result: Array[String] = []
	for op_id in _ops:
		if _ops[op_id]["kind"] == kind:
			result.append(op_id)
	result.sort()
	return result


func describe(op_id: String) -> Dictionary:
	if not _ops.has(op_id):
		return {}
	var entry: Dictionary = _ops[op_id]
	return {"id": op_id, "kind": entry["kind"], "version": entry["version"], "params": entry["params"].duplicate(), "description": entry["description"]}


func op_version(op_id: String) -> int:
	return int(_ops.get(op_id, {}).get("version", 0))


## Validates one operation reference dictionary ({op, params, label, secret}).
func validate_ref(kind: String, ref: Variant, path: String) -> Array[FacetsError]:
	var errors: Array[FacetsError] = []
	if not ref is Dictionary:
		errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Operation must be an object.", path))
		return errors
	var op_id := str(ref.get("op", ""))
	if not has_op(kind, op_id):
		errors.append(FacetsError.make(FacetsError.UNKNOWN_OPERATION, "Unknown %s operation '%s'." % [kind, op_id], path + ".op"))
		return errors
	for key in ref:
		if not ["op", "params", "label", "secret"].has(key):
			errors.append(FacetsError.make(FacetsError.UNKNOWN_FIELD, "Unknown operation field '%s'." % key, "%s.%s" % [path, key]))
	var params: Variant = ref.get("params", {})
	if not params is Dictionary:
		errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "params must be an object.", path + ".params"))
		return errors
	var schema: Dictionary = _ops[op_id]["params"]
	for name in schema:
		var type_name := str(schema[name])
		var optional := type_name.ends_with("?")
		type_name = type_name.trim_suffix("?")
		if not params.has(name):
			if not optional:
				errors.append(FacetsError.make(FacetsError.MISSING_FIELD, "Missing parameter '%s'." % name, "%s.params.%s" % [path, name]))
			continue
		if not _type_matches(type_name, params[name]):
			errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Parameter '%s' must be %s." % [name, type_name], "%s.params.%s" % [path, name]))
	for name in params:
		if not schema.has(name):
			errors.append(FacetsError.make(FacetsError.UNKNOWN_FIELD, "Unknown parameter '%s'." % name, "%s.params.%s" % [path, name]))
	return errors


func validate_list(kind: String, refs: Variant, path: String) -> Array[FacetsError]:
	var errors: Array[FacetsError] = []
	if not refs is Array:
		errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Expected a list of operations.", path))
		return errors
	for index in refs.size():
		errors.append_array(validate_ref(kind, refs[index], "%s[%d]" % [path, index]))
	return errors


static func _type_matches(type_name: String, value: Variant) -> bool:
	match type_name:
		"string":
			return value is String
		"int":
			return value is int or (value is float and value == floorf(value))
		"bool":
			return value is bool
		"scalar":
			return value is String or value is bool or value is int or (value is float and value == floorf(value))
		"string_list":
			if not value is Array:
				return false
			for item in value:
				if not item is String:
					return false
			return true
	return false


## Evaluates a validated requirement. Unknown operations are never met.
func check(ref: Dictionary, context: FacetsOpContext) -> bool:
	var op_id := str(ref.get("op", ""))
	if not has_op(KIND_REQUIREMENT, op_id):
		return false
	var fn: Callable = _ops[op_id]["fn"]
	return bool(fn.call(context, FacetsJson.normalize(ref.get("params", {}))))


## Applies a validated effect through [param txn]. Returns false (with
## txn.error set) when the effect is rejected.
func apply_effect(ref: Dictionary, context: FacetsOpContext, txn: FacetsTxn) -> bool:
	var op_id := str(ref.get("op", ""))
	if not has_op(KIND_EFFECT, op_id):
		return txn.fail(FacetsError.make(FacetsError.UNKNOWN_OPERATION, "Unknown effect operation '%s'." % op_id))
	var param_errors := validate_ref(KIND_EFFECT, ref, "effect")
	if not param_errors.is_empty():
		return txn.fail(FacetsError.make(FacetsError.EFFECT_REJECTED, "Effect '%s' has invalid parameters." % op_id).with_detail(str(param_errors)))
	var fn: Callable = _ops[op_id]["fn"]
	var ok := bool(fn.call(context, txn, FacetsJson.normalize(ref.get("params", {}))))
	if not ok and not txn.failed():
		txn.fail(FacetsError.make(FacetsError.EFFECT_REJECTED, "Effect '%s' was rejected." % op_id))
	return ok and not txn.failed()


# --- Core requirements -----------------------------------------------------

func _register_core_requirements() -> void:
	register(KIND_REQUIREMENT, "require.object_flag", 1, {"object_id": "string", "key": "string", "value": "scalar", "negate": "bool?"}, _req_object_flag, "World object flag equals a value.")
	register(KIND_REQUIREMENT, "require.accessible_controller", 1, {"object_id": "string"}, _req_accessible_controller, "Controller is accessible and not locked.")
	register(KIND_REQUIREMENT, "require.fact", 1, {"fact_id": "string", "value": "scalar?", "negate": "bool?"}, _req_fact, "World fact has a value.")
	register(KIND_REQUIREMENT, "require.knows_fact", 1, {"fact_id": "string"}, _req_knows_fact, "Actor knows a fact.")
	register(KIND_REQUIREMENT, "require.item", 1, {"item_id": "string", "count": "int?"}, _req_item, "Actor carries an item.")
	register(KIND_REQUIREMENT, "require.actor_zone", 1, {"zone_id": "string"}, _req_actor_zone, "Actor is in a zone.")
	register(KIND_REQUIREMENT, "require.no_condition", 1, {"condition_id": "string"}, _req_no_condition, "Actor lacks a condition.")
	register(KIND_REQUIREMENT, "require.skill_min", 1, {"skill_id": "string", "rank": "int"}, _req_skill_min, "Actor has a minimum skill rank.")
	register(KIND_REQUIREMENT, "require.counter_max", 1, {"counter_id": "string", "max": "int"}, _req_counter_max, "World counter is at most a value.")
	register(KIND_REQUIREMENT, "require.clock_max", 1, {"max": "int"}, _req_clock_max, "World clock is at most a value.")
	register(KIND_REQUIREMENT, "require.not_refused", 1, {"npc_id": "string", "topic": "string"}, _req_not_refused, "NPC has no hard refusal on a topic.")
	register(KIND_REQUIREMENT, "require.capability", 1, {"capability_id": "string"}, _req_capability, "Actor has an admitted capability.")
	register(KIND_REQUIREMENT, "require.scene", 1, {"scene_id": "string"}, _req_scene, "Current scene matches.")


func _req_object_flag(context: FacetsOpContext, params: Dictionary) -> bool:
	var matches := FacetsJson.equal(context.world.object_flag(params["object_id"], params["key"]), params["value"])
	return matches != bool(params.get("negate", false))


func _req_accessible_controller(context: FacetsOpContext, params: Dictionary) -> bool:
	var object_id: String = params["object_id"]
	return context.world.object_flag(object_id, "accessible", false) == true and context.world.object_flag(object_id, "locked", false) != true


func _req_fact(context: FacetsOpContext, params: Dictionary) -> bool:
	var matches := FacetsJson.equal(context.world.fact_value(params["fact_id"]), params.get("value", true))
	return matches != bool(params.get("negate", false))


func _req_knows_fact(context: FacetsOpContext, params: Dictionary) -> bool:
	var state := context.actor()
	return state != null and state.knows(params["fact_id"])


func _req_item(context: FacetsOpContext, params: Dictionary) -> bool:
	var state := context.actor()
	return state != null and state.item_count(params["item_id"]) >= int(params.get("count", 1))


func _req_actor_zone(context: FacetsOpContext, params: Dictionary) -> bool:
	var state := context.actor()
	return state != null and state.zone_id == params["zone_id"]


func _req_no_condition(context: FacetsOpContext, params: Dictionary) -> bool:
	var state := context.actor()
	return state != null and not state.has_condition(params["condition_id"])


func _req_skill_min(context: FacetsOpContext, params: Dictionary) -> bool:
	var state := context.actor()
	return state != null and state.build.skill(params["skill_id"]) >= int(params["rank"])


func _req_counter_max(context: FacetsOpContext, params: Dictionary) -> bool:
	return int(context.world.counters.get(params["counter_id"], 0)) <= int(params["max"])


func _req_clock_max(context: FacetsOpContext, params: Dictionary) -> bool:
	return context.world.clock <= int(params["max"])


func _req_not_refused(context: FacetsOpContext, params: Dictionary) -> bool:
	var topics: Variant = context.world.refusals.get(params["npc_id"], [])
	return not (topics is Array and topics.has(params["topic"]))


func _req_capability(context: FacetsOpContext, params: Dictionary) -> bool:
	var state := context.actor()
	return state != null and state.build.capabilities.has(params["capability_id"])


func _req_scene(context: FacetsOpContext, params: Dictionary) -> bool:
	return context.world.scene_id == params["scene_id"]


# --- Core effects ----------------------------------------------------------

func _register_core_effects() -> void:
	register(KIND_EFFECT, "object.set_flag", 1, {"object_id": "string", "key": "string", "value": "scalar"}, _eff_object_set_flag, "Set a world object flag (open target, lock controller).")
	register(KIND_EFFECT, "world.counter_add", 1, {"counter_id": "string", "amount": "int"}, _eff_counter_add, "Add to a world counter (advance patrol).")
	register(KIND_EFFECT, "world.clock_advance", 1, {"amount": "int"}, _eff_clock_advance, "Advance the scene clock.")
	register(KIND_EFFECT, "world.mark_trace", 1, {"trace_id": "string", "label": "string?"}, _eff_mark_trace, "Mark a public trace fact.")
	register(KIND_EFFECT, "fact.set", 1, {"fact_id": "string", "value": "scalar", "visibility": "string?", "label": "string?"}, _eff_fact_set, "Set a world fact.")
	register(KIND_EFFECT, "fact.reveal", 1, {"fact_id": "string", "target": "string?"}, _eff_fact_reveal, "An actor learns a fact.")
	register(KIND_EFFECT, "actor.strain", 1, {"amount": "int", "target": "string?"}, _eff_actor_strain, "Add or remove strain.")
	register(KIND_EFFECT, "actor.condition_add", 1, {"condition_id": "string", "target": "string?"}, _eff_condition_add, "Apply a condition.")
	register(KIND_EFFECT, "actor.condition_remove", 1, {"condition_id": "string", "target": "string?"}, _eff_condition_remove, "Remove a condition.")
	register(KIND_EFFECT, "actor.item_add", 1, {"item_id": "string", "amount": "int", "target": "string?"}, _eff_item_add, "Add or consume items.")
	register(KIND_EFFECT, "actor.zone", 1, {"zone_id": "string", "target": "string?"}, _eff_actor_zone, "Move an actor to a zone.")
	register(KIND_EFFECT, "actor.flag", 1, {"key": "string", "value": "scalar", "target": "string?"}, _eff_actor_flag, "Set an actor flag.")
	register(KIND_EFFECT, "bond.adjust", 1, {"other_id": "string", "dimension": "string", "amount": "int", "target": "string?"}, _eff_bond_adjust, "Adjust bond trust or affinity (-2..+2).")
	register(KIND_EFFECT, "bond.add_obligation", 1, {"other_id": "string", "obligation": "string", "target": "string?"}, _eff_bond_obligation, "Record an obligation.")
	register(KIND_EFFECT, "npc.grant", 1, {"npc_id": "string", "topic": "string"}, _eff_npc_grant, "An NPC grants a request unless it is a hard refusal.")
	register(KIND_EFFECT, "npc.disposition", 1, {"npc_id": "string", "key": "string", "value": "scalar"}, _eff_npc_disposition, "Change an NPC's disposition; never a player's beliefs.")


func _targets(context: FacetsOpContext, txn: FacetsTxn, params: Dictionary) -> Array[String]:
	var targets := context.resolve_targets(str(params.get("target", "self")))
	for actor_id in targets:
		if not context.world.has_actor(actor_id):
			txn.fail(FacetsError.make(FacetsError.EFFECT_REJECTED, "Effect targets an unknown actor.").with_detail(actor_id))
			return [] as Array[String]
	return targets


func _eff_object_set_flag(context: FacetsOpContext, txn: FacetsTxn, params: Dictionary) -> bool:
	var object_id: String = params["object_id"]
	var key: String = params["key"]
	var previous: Variant = context.world.object_flag(object_id, key)
	if not txn.set_object_flag(object_id, key, params["value"]):
		return false
	if str(context.tags.get("expires", "")) == "scene_end":
		var entry := {"scope": "scene_end", "path": ["objects", object_id, key], "value": previous, "event_id": context.event_id}
		return txn.append(["expiring"], entry)
	return true


func _eff_counter_add(_context: FacetsOpContext, txn: FacetsTxn, params: Dictionary) -> bool:
	return txn.add_counter(params["counter_id"], int(params["amount"]))


func _eff_clock_advance(_context: FacetsOpContext, txn: FacetsTxn, params: Dictionary) -> bool:
	return txn.advance_clock(int(params["amount"]))


func _eff_mark_trace(_context: FacetsOpContext, txn: FacetsTxn, params: Dictionary) -> bool:
	return txn.set_fact(params["trace_id"], true, "public", str(params.get("label", "")))


func _eff_fact_set(_context: FacetsOpContext, txn: FacetsTxn, params: Dictionary) -> bool:
	return txn.set_fact(params["fact_id"], params["value"], str(params.get("visibility", "public")), str(params.get("label", "")))


func _eff_fact_reveal(context: FacetsOpContext, txn: FacetsTxn, params: Dictionary) -> bool:
	for actor_id in _targets(context, txn, params):
		txn.reveal_fact(actor_id, params["fact_id"])
	return not txn.failed()


func _eff_actor_strain(context: FacetsOpContext, txn: FacetsTxn, params: Dictionary) -> bool:
	for actor_id in _targets(context, txn, params):
		txn.add_strain(actor_id, int(params["amount"]), context.world.scene_id, bool(context.tags.get("fear", false)))
	return not txn.failed()


func _eff_condition_add(context: FacetsOpContext, txn: FacetsTxn, params: Dictionary) -> bool:
	var condition_id: String = params["condition_id"]
	if context.registry != null and not context.registry.has_condition(condition_id):
		return txn.fail(FacetsError.make(FacetsError.EFFECT_REJECTED, "Unknown condition.").with_detail(condition_id))
	for actor_id in _targets(context, txn, params):
		txn.add_condition(actor_id, condition_id)
	return not txn.failed()


func _eff_condition_remove(context: FacetsOpContext, txn: FacetsTxn, params: Dictionary) -> bool:
	for actor_id in _targets(context, txn, params):
		txn.remove_condition(actor_id, params["condition_id"])
	return not txn.failed()


func _eff_item_add(context: FacetsOpContext, txn: FacetsTxn, params: Dictionary) -> bool:
	for actor_id in _targets(context, txn, params):
		txn.add_item(actor_id, params["item_id"], int(params["amount"]))
	return not txn.failed()


func _eff_actor_zone(context: FacetsOpContext, txn: FacetsTxn, params: Dictionary) -> bool:
	for actor_id in _targets(context, txn, params):
		txn.set_path(["actors", actor_id, "zone_id"], params["zone_id"])
	return not txn.failed()


func _eff_actor_flag(context: FacetsOpContext, txn: FacetsTxn, params: Dictionary) -> bool:
	for actor_id in _targets(context, txn, params):
		txn.set_actor_flag(actor_id, params["key"], params["value"])
	return not txn.failed()


func _eff_bond_adjust(context: FacetsOpContext, txn: FacetsTxn, params: Dictionary) -> bool:
	for actor_id in _targets(context, txn, params):
		txn.adjust_bond(actor_id, params["other_id"], params["dimension"], int(params["amount"]))
	return not txn.failed()


func _eff_bond_obligation(context: FacetsOpContext, txn: FacetsTxn, params: Dictionary) -> bool:
	for actor_id in _targets(context, txn, params):
		txn.add_obligation(actor_id, params["other_id"], params["obligation"])
	return not txn.failed()


## A hard refusal survives every dice outcome: the grant is recorded as
## refused and changes nothing.
func _eff_npc_grant(context: FacetsOpContext, txn: FacetsTxn, params: Dictionary) -> bool:
	var npc_id: String = params["npc_id"]
	var topic: String = params["topic"]
	var topics: Variant = context.world.refusals.get(npc_id, [])
	if topics is Array and topics.has(topic):
		txn.note("refused", {"npc_id": npc_id, "topic": topic})
		return true
	return txn.set_path(["grants", "%s:%s" % [npc_id, topic]], true)


## Social outcomes change NPC dispositions only. Player characters' beliefs
## are never written by another party's check.
func _eff_npc_disposition(context: FacetsOpContext, txn: FacetsTxn, params: Dictionary) -> bool:
	var npc := context.world.actor(params["npc_id"])
	if npc == null or npc.controller != "npc":
		return txn.fail(FacetsError.make(FacetsError.EFFECT_REJECTED, "Disposition effects may only target NPCs.", "npc_id"))
	return txn.set_actor_flag(npc.actor_id, "disposition.%s" % params["key"], params["value"])
