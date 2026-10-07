@tool
class_name FacetsTalentHooks
extends RefCounted
## Registry of typed talent hooks. A talent definition names a hook and gives
## typed parameters; the behavior lives in trusted code (core session hooks
## or an optional package such as combat), never in portable content.
##
## Parameter schema types: "int", "bool", "string", "string_list",
## "effect_list" (validated against the operation registry). A trailing "?"
## marks an optional parameter.

var _hooks := {}


static func with_core() -> FacetsTalentHooks:
	var hooks := FacetsTalentHooks.new()
	hooks.register("second_look", "core", {"skills": "string_list", "uses_per_scene": "int", "interval": "int"},
		"After a failed attempt, retry once per scene using an alternate authored evidence source and an extra interval.")
	hooks.register("quiet_hands", "core", {"skills": "string_list", "benefit_id": "string", "label": "string", "effects": "effect_list"},
		"On a strong success with a listed skill, a quiet benefit may replace the strong benefit.")
	hooks.register("field_engineer", "core", {"skills": "string_list", "uses_per_scene": "int"},
		"Substitute an authored consumable for a required tool; the repair expires at scene end.")
	hooks.register("steady_voice", "core", {"strain_removed": "int", "uses_per_scene": "int"},
		"Spend an action to remove strain from a willing, communicating ally after a fear setback, once per scene.")
	hooks.register("bargain_maker", "core", {"skills": "string_list", "uses_per_scene": "int"},
		"On a strong success with a listed skill, a listed lesser concession may replace the benefit.")
	hooks.register("trail_reader", "core", {"skills": "string_list", "uses_per_scene": "int"},
		"On success with a listed skill, reveal one permitted evidence-supported fact.")
	return hooks


func register(hook_id: String, package: String, param_schema: Dictionary, description: String) -> void:
	_hooks[hook_id] = {"package": package, "params": param_schema.duplicate(), "description": description}


func has_hook(hook_id: String) -> bool:
	return _hooks.has(hook_id)


func hook_ids() -> Array[String]:
	var ids: Array[String] = []
	for hook_id in _hooks:
		ids.append(hook_id)
	ids.sort()
	return ids


func describe(hook_id: String) -> Dictionary:
	return _hooks.get(hook_id, {}).duplicate(true)


func validate_parameters(hook_id: String, params: Variant, operations: FacetsOperations, path: String) -> Array[FacetsError]:
	var errors: Array[FacetsError] = []
	if not has_hook(hook_id):
		errors.append(FacetsError.make(FacetsError.UNKNOWN_ID, "Unknown talent hook '%s'." % hook_id, "hook_id"))
		return errors
	if not params is Dictionary:
		errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Talent parameters must be an object.", path))
		return errors
	var schema: Dictionary = _hooks[hook_id]["params"]
	for name in schema:
		var type_name := str(schema[name])
		var optional := type_name.ends_with("?")
		type_name = type_name.trim_suffix("?")
		var field := "%s.%s" % [path, name]
		if not params.has(name):
			if not optional:
				errors.append(FacetsError.make(FacetsError.MISSING_FIELD, "Missing talent parameter '%s'." % name, field))
			continue
		var value: Variant = params[name]
		match type_name:
			"int":
				if not (value is int or (value is float and value == floorf(value))):
					errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Parameter '%s' must be an integer." % name, field))
			"bool":
				if not value is bool:
					errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Parameter '%s' must be true or false." % name, field))
			"string":
				if not value is String:
					errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Parameter '%s' must be text." % name, field))
			"string_list":
				if not value is Array or value.any(func(item: Variant) -> bool: return not item is String):
					errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Parameter '%s' must be a list of IDs." % name, field))
			"effect_list":
				errors.append_array(operations.validate_list(FacetsOperations.KIND_EFFECT, value, field))
	for name in params:
		if not schema.has(name):
			errors.append(FacetsError.make(FacetsError.UNKNOWN_FIELD, "Unknown talent parameter '%s'." % name, "%s.%s" % [path, name]))
	return errors
