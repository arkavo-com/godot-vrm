@tool
class_name FacetsAuthoring
extends RefCounted
## Authoring mutations routed through undo/redo.
##
## Works with the editor's EditorUndoRedoManager or a plain UndoRedo (used by
## the headless tests): only create_action, add_do_property,
## add_undo_property and commit_action are called, which both APIs share.
## Sub-resources stored in their own files are copied before editing
## (copy-on-write), so editing one character never mutates another
## character's shared definition by accident.

var undo: Object


static func make(p_undo: Object) -> FacetsAuthoring:
	var authoring := FacetsAuthoring.new()
	authoring.undo = p_undo
	return authoring


## True when [param resource] lives in its own file and may be shared.
static func is_shared_file(resource: Resource) -> bool:
	return resource != null and not resource.resource_path.is_empty() and not resource.resource_path.contains("::")


static func _copy(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value


func _commit(action_name: String, changes: Array) -> void:
	undo.create_action(action_name)
	for change in changes:
		var object: Object = change[0]
		var property: String = change[1]
		undo.add_do_property(object, property, _copy(change[2]))
		undo.add_undo_property(object, property, _copy(object.get(property)))
	undo.commit_action()


func set_facet(character: FacetsCharacterResource, facet_id: String, value: int) -> void:
	if not FacetsRules.FACETS.has(facet_id):
		return
	var facet_set := character.facet_set
	if facet_set == null or is_shared_file(facet_set):
		var copy := FacetsFacetSet.from_dict(facet_set.to_dict() if facet_set != null else {})
		copy.set_rating(facet_id, value)
		_commit("Set %s" % facet_id, [[character, "facet_set", copy]])
		return
	_commit("Set %s" % facet_id, [[facet_set, facet_id, value]])


func set_skill(character: FacetsCharacterResource, skill_id: String, rank: int) -> void:
	var skills := character.skills.duplicate()
	if rank == 0:
		skills.erase(skill_id)
	else:
		skills[skill_id] = rank
	_commit("Set skill %s" % skill_id, [[character, "skills", skills]])


func set_talent(character: FacetsCharacterResource, slot: int, talent_id: String) -> void:
	var talents: Array[String] = character.talents.duplicate()
	while talents.size() <= slot:
		talents.append("")
	talents[slot] = talent_id
	var cleaned: Array[String] = []
	for item in talents:
		if not item.is_empty():
			cleaned.append(item)
	_commit("Set talent", [[character, "talents", cleaned]])


func set_identity_field(character: FacetsCharacterResource, field: String, value: String) -> void:
	if not ["name", "drive", "code", "hindrance", "tell"].has(field):
		return
	var identity := character.identity
	if identity == null or is_shared_file(identity):
		var copy := FacetsIdentityResource.from_dict(identity.to_dict() if identity != null else {})
		copy.set(field, value)
		_commit("Set %s" % field, [[character, "identity", copy]])
		return
	_commit("Set %s" % field, [[identity, field, value]])


func set_bond(character: FacetsCharacterResource, index: int, trust: int, affinity: int) -> void:
	if index < 0 or index >= character.bonds.size() or character.bonds[index] == null:
		return
	var bond := character.bonds[index]
	trust = clampi(trust, FacetsRules.BOND_MIN, FacetsRules.BOND_MAX)
	affinity = clampi(affinity, FacetsRules.BOND_MIN, FacetsRules.BOND_MAX)
	if is_shared_file(bond):
		var copy := FacetsBondResource.from_dict(bond.to_dict())
		copy.trust = trust
		copy.affinity = affinity
		var bonds: Array[FacetsBondResource] = character.bonds.duplicate()
		bonds[index] = copy
		_commit("Set bond", [[character, "bonds", bonds]])
		return
	_commit("Set bond", [[bond, "trust", trust], [bond, "affinity", affinity]])


## Applies an editable preset by copying its values. The preset Resource is
## never linked into the character.
func apply_preset(character: FacetsCharacterResource, archetype: Dictionary) -> void:
	var build := FacetsBuild.from_dict(archetype.get("build", {}))
	var facet_set := FacetsFacetSet.from_dict(build.facets)
	var talents: Array[String] = build.talents.duplicate()
	_commit("Apply preset %s" % archetype.get("display_name", archetype.get("id", "")), [
		[character, "facet_set", facet_set],
		[character, "skills", build.skills.duplicate()],
		[character, "talents", talents],
	])


## Appends an allowlisted operation reference to an action list property
## (requirements, success_effects, failure_effects, ...).
func add_operation(action: FacetsActionResource, property: String, op_id: String, operations: FacetsOperations) -> bool:
	var kind := FacetsOperations.KIND_REQUIREMENT if property.contains("requirement") else FacetsOperations.KIND_EFFECT
	if not operations.has_op(kind, op_id):
		return false
	var current: Variant = action.get(property)
	if not current is Array:
		return false
	var refs: Array[FacetsOperationRef] = []
	for ref in current:
		refs.append(ref)
	refs.append(FacetsOperationRef.make(op_id, template_params(operations, op_id)))
	_commit("Add %s" % op_id, [[action, property, refs]])
	return true


## Default parameters for an operation: empty strings, zeros and false.
static func template_params(operations: FacetsOperations, op_id: String) -> Dictionary:
	var params := {}
	var schema: Dictionary = operations.describe(op_id).get("params", {})
	for name in schema:
		var type_name := str(schema[name])
		if type_name.ends_with("?"):
			continue
		match type_name:
			"int":
				params[name] = 0
			"bool":
				params[name] = false
			"string_list":
				params[name] = []
			"scalar":
				params[name] = true
			_:
				params[name] = ""
	return params


func set_talent_hook(talent: FacetsTalentResource, hook_id: String, hooks: FacetsTalentHooks) -> bool:
	if not hooks.has_hook(hook_id):
		return false
	var params := {}
	var schema: Dictionary = hooks.describe(hook_id).get("params", {})
	for name in schema:
		var type_name := str(schema[name]).trim_suffix("?")
		match type_name:
			"int":
				params[name] = 1 if name.begins_with("uses") else 0
			"bool":
				params[name] = false
			"string_list", "effect_list":
				params[name] = []
			_:
				params[name] = ""
	_commit("Set talent hook", [[talent, "hook_id", hook_id], [talent, "parameters", params]])
	return true
