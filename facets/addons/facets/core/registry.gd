@tool
class_name FacetsRegistry
extends RefCounted
## Pinned content catalog: skills, talents, conditions, actions, archetypes,
## the operation allowlist and typed talent hooks.
##
## Definitions are stored as immutable canonical dictionaries copied out of
## authoring Resources. Getters return deep copies, so callers cannot mutate
## the catalog or a shared .tres during play.

const CORE_PACK_PATH := "res://addons/facets/content/core/core_pack.tres"

var ruleset_id: String = FacetsRules.RULESET_ID
var ruleset_version: String = FacetsRules.RULESET_VERSION
var operations: FacetsOperations
var hooks: FacetsTalentHooks
var admission_policy: Dictionary = FacetsAdmissionPolicy.standard().to_dict()

var _skills := {}
var _talents := {}
var _conditions := {}
var _actions := {}
var _archetypes := {}
var _packs := {}


## Empty registry with core operations and hooks but no content.
static func create() -> FacetsRegistry:
	var registry := FacetsRegistry.new()
	registry.operations = FacetsOperations.with_core()
	registry.hooks = FacetsTalentHooks.with_core()
	return registry


## Registry with the core rules pack (twelve skills, six noncombat talents,
## standard conditions, archetypes and the standard admission policy).
static func core() -> FacetsRegistry:
	var registry := create()
	var pack := load(CORE_PACK_PATH) as FacetsRulesPack
	if pack == null:
		push_error("FACETS: core pack missing at %s" % CORE_PACK_PATH)
		return registry
	var reply := registry.register_pack(pack)
	if not reply.ok:
		push_error("FACETS: core pack invalid: %s" % str(reply))
	return registry


func register_pack(pack: FacetsRulesPack) -> FacetsReply:
	return register_pack_dict(pack.to_dict())


## Registers a pack atomically: on any validation error nothing is added.
func register_pack_dict(source: Dictionary) -> FacetsReply:
	var data: Dictionary = FacetsJson.normalize(source)
	var errors: Array[FacetsError] = []
	var pack_id := str(data.get("pack_id", ""))
	if pack_id.is_empty():
		errors.append(FacetsError.make(FacetsError.MISSING_FIELD, "Pack needs a pack_id.", "pack_id"))
	if _packs.has(pack_id):
		errors.append(FacetsError.make(FacetsError.DUPLICATE, "Pack '%s' is already registered." % pack_id, "pack_id"))
	if str(data.get("ruleset_id", "")) != ruleset_id or str(data.get("ruleset_version", "")) != ruleset_version:
		errors.append(FacetsError.make(FacetsError.UNSUPPORTED_VERSION, "Pack targets %s@%s; this registry runs %s@%s." % [data.get("ruleset_id", "?"), data.get("ruleset_version", "?"), ruleset_id, ruleset_version], "ruleset_version"))
	var dependencies: Dictionary = data.get("dependencies", {}) if data.get("dependencies", {}) is Dictionary else {}
	for dependency in dependencies:
		if str(_packs.get(dependency, "")) != str(dependencies[dependency]):
			errors.append(FacetsError.make(FacetsError.UNSUPPORTED_VERSION, "Pack depends on %s@%s, which is not registered." % [dependency, dependencies[dependency]], "dependencies.%s" % dependency))
	if not errors.is_empty():
		return FacetsReply.failures(errors)
	# Stage into a copy so a failure part-way through changes nothing.
	var staged := _clone_catalog()
	for index in data.get("skills", []).size():
		errors.append_array(staged._add("skill", data["skills"][index], "skills[%d]" % index))
	for index in data.get("conditions", []).size():
		errors.append_array(staged._add("condition", data["conditions"][index], "conditions[%d]" % index))
	for index in data.get("talents", []).size():
		errors.append_array(staged._add("talent", data["talents"][index], "talents[%d]" % index))
	for index in data.get("actions", []).size():
		errors.append_array(staged._add("action", data["actions"][index], "actions[%d]" % index))
	for index in data.get("archetypes", []).size():
		errors.append_array(staged._add("archetype", data["archetypes"][index], "archetypes[%d]" % index))
	if not errors.is_empty():
		return FacetsReply.failures(errors)
	_skills = staged._skills
	_conditions = staged._conditions
	_talents = staged._talents
	_actions = staged._actions
	_archetypes = staged._archetypes
	var policy: Variant = data.get("admission_policy", {})
	if policy is Dictionary and not policy.is_empty():
		admission_policy = policy.duplicate(true)
	_packs[pack_id] = str(data.get("version", ""))
	return FacetsReply.success(pack_id)


func _clone_catalog() -> FacetsRegistry:
	var staged := FacetsRegistry.new()
	staged.operations = operations
	staged.hooks = hooks
	staged._skills = _skills.duplicate(true)
	staged._conditions = _conditions.duplicate(true)
	staged._talents = _talents.duplicate(true)
	staged._actions = _actions.duplicate(true)
	staged._archetypes = _archetypes.duplicate(true)
	return staged


func _add(kind: String, definition: Variant, path: String) -> Array[FacetsError]:
	var errors: Array[FacetsError] = []
	if not definition is Dictionary:
		errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Definition must be an object.", path))
		return errors
	var data: Dictionary = FacetsJson.normalize(definition)
	var item_id := str(data.get("id", ""))
	var table: Dictionary
	match kind:
		"skill":
			errors = FacetsValidator.validate_skill(data, path)
			table = _skills
		"condition":
			errors = FacetsValidator.validate_condition(data, path)
			table = _conditions
		"talent":
			errors = FacetsValidator.validate_talent(data, self, path)
			table = _talents
		"action":
			errors = FacetsValidator.validate_action(data, self, path)
			table = _actions
		"archetype":
			table = _archetypes
	if errors.is_empty() and table.has(item_id):
		errors.append(FacetsError.make(FacetsError.DUPLICATE, "Duplicate %s '%s'." % [kind, item_id], path + ".id"))
	if errors.is_empty():
		table[item_id] = data
	return errors


func add_skill(definition: Dictionary) -> FacetsReply:
	return FacetsReply.from_errors(_add("skill", definition, "skill"), definition.get("id", ""))


func add_condition(definition: Dictionary) -> FacetsReply:
	return FacetsReply.from_errors(_add("condition", definition, "condition"), definition.get("id", ""))


func add_talent(definition: Dictionary) -> FacetsReply:
	return FacetsReply.from_errors(_add("talent", definition, "talent"), definition.get("id", ""))


func add_action(definition: Dictionary) -> FacetsReply:
	return FacetsReply.from_errors(_add("action", definition, "action"), definition.get("id", ""))


func add_action_resource(action: FacetsActionResource) -> FacetsReply:
	return add_action(action.to_dict())


func add_archetype(definition: Dictionary) -> FacetsReply:
	return FacetsReply.from_errors(_add("archetype", definition, "archetype"), definition.get("id", ""))


func has_skill(skill_id: String) -> bool:
	return _skills.has(skill_id)


func has_talent(talent_id: String) -> bool:
	return _talents.has(talent_id)


func has_condition(condition_id: String) -> bool:
	return _conditions.has(condition_id)


func has_action(action_id: String) -> bool:
	return _actions.has(action_id)


func skill_ids() -> Array[String]:
	return _sorted_keys(_skills)


func talent_ids() -> Array[String]:
	return _sorted_keys(_talents)


func condition_ids() -> Array[String]:
	return _sorted_keys(_conditions)


func action_ids() -> Array[String]:
	return _sorted_keys(_actions)


func archetype_ids() -> Array[String]:
	return _sorted_keys(_archetypes)


func get_skill(skill_id: String) -> Dictionary:
	return _skills.get(skill_id, {}).duplicate(true)


func get_talent(talent_id: String) -> Dictionary:
	return _talents.get(talent_id, {}).duplicate(true)


func get_condition(condition_id: String) -> Dictionary:
	return _conditions.get(condition_id, {}).duplicate(true)


func get_action(action_id: String) -> Dictionary:
	return _actions.get(action_id, {}).duplicate(true)


func get_archetype(archetype_id: String) -> Dictionary:
	return _archetypes.get(archetype_id, {}).duplicate(true)


## Digest pinned into previews and events; any definition change makes
## outstanding previews stale.
func action_digest(action_id: String) -> String:
	return FacetsJson.digest(_actions.get(action_id, {}))


func talent_hook(talent_id: String) -> String:
	return str(_talents.get(talent_id, {}).get("hook_id", ""))


## Talent IDs in [param build] that use [param hook_id].
func talents_with_hook(build: FacetsBuild, hook_id: String) -> Array[String]:
	var result: Array[String] = []
	for talent_id in build.talents:
		if talent_hook(talent_id) == hook_id and not result.has(talent_id):
			result.append(talent_id)
	return result


func pack_versions() -> Dictionary:
	return _packs.duplicate()


func policy() -> FacetsAdmissionPolicy:
	return FacetsAdmissionPolicy.from_dict(admission_policy)


static func _sorted_keys(table: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key in table:
		keys.append(str(key))
	keys.sort()
	return keys
