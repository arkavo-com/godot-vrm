@tool
class_name FacetsValidator
extends RefCounted
## Validation for builds and authored definitions. Pure functions: no state,
## no RNG, no file access. Used by runtime import, sessions and the editor.

const USAGE_SCOPES: Array[String] = ["passive", "per_check", "per_scene", "per_round", "per_encounter"]
const RETRY_POLICIES: Array[String] = ["lock_until_change", "repeatable"]
const DIFFICULTY_KINDS: Array[String] = ["fixed", "opposed", "routine"]
const RESTRICTIONS: Array[String] = ["no_push", "no_reactions", "cannot_act", "limited_turn", "cannot_communicate", "no_move"]
const MIN_TARGET := 2
const MAX_TARGET := 30


# --- Builds ----------------------------------------------------------------

## Standard creation: facets start at 2, six points, cap 4, total 18; skills
## spend exactly 12 points with at most 2 per skill; exactly two talents.
static func validate_creation(build: FacetsBuild, registry: FacetsRegistry, path: String = "build") -> Array[FacetsError]:
	return validate_policy_build(build, registry, FacetsAdmissionPolicy.standard(), path)


## Creation-style validation against an admission policy's ranges.
static func validate_policy_build(build: FacetsBuild, registry: FacetsRegistry, policy: FacetsAdmissionPolicy, path: String = "build") -> Array[FacetsError]:
	var errors: Array[FacetsError] = []
	errors.append_array(_validate_facets(build, policy.facet_min, policy.facet_cap, path))
	if build.facet_total() != policy.facet_total and _facets_complete(build):
		errors.append(FacetsError.make(FacetsError.BUDGET, "Facets must total %d (baseline %d each plus %d points); found %d." % [policy.facet_total, FacetsRules.FACET_BASELINE, policy.facet_total - FacetsRules.FACET_BASELINE * FacetsRules.FACETS.size(), build.facet_total()], path + ".facets"))
	errors.append_array(_validate_skills(build, registry, 0, policy.skill_cap, path))
	if build.skill_total() != policy.skill_points:
		errors.append(FacetsError.make(FacetsError.BUDGET, "Skills must spend exactly %d points; found %d." % [policy.skill_points, build.skill_total()], path + ".skills"))
	errors.append_array(_validate_talents(build, registry, path))
	if build.talents.size() != policy.talent_count:
		errors.append(FacetsError.make(FacetsError.BUDGET, "Choose exactly %d talents; found %d." % [policy.talent_count, build.talents.size()], path + ".talents"))
	for index in build.capabilities.size():
		if not policy.allowed_capabilities.has(build.capabilities[index]):
			errors.append(FacetsError.make(FacetsError.NOT_AUTHORIZED, "Capability '%s' is not admitted by this policy." % build.capabilities[index], "%s.capabilities[%d]" % [path, index]))
	return errors


## Progressed builds: facets 2..5, skills 0..4, at most six talents.
static func validate_progressed(build: FacetsBuild, registry: FacetsRegistry, path: String = "build") -> Array[FacetsError]:
	var errors: Array[FacetsError] = []
	errors.append_array(_validate_facets(build, FacetsRules.FACET_BASELINE, FacetsRules.PROGRESSED_FACET_CAP, path))
	errors.append_array(_validate_skills(build, registry, FacetsRules.SKILL_MIN, FacetsRules.SKILL_MAX, path))
	errors.append_array(_validate_talents(build, registry, path))
	if build.talents.size() > FacetsRules.MAX_EQUIPPED_TALENTS:
		errors.append(FacetsError.make(FacetsError.BUDGET, "At most %d talents may be equipped." % FacetsRules.MAX_EQUIPPED_TALENTS, path + ".talents"))
	return errors


static func _facets_complete(build: FacetsBuild) -> bool:
	for facet_id in FacetsRules.FACETS:
		if not build.facets.has(facet_id):
			return false
	return true


static func _validate_facets(build: FacetsBuild, minimum: int, maximum: int, path: String) -> Array[FacetsError]:
	var errors: Array[FacetsError] = []
	for facet_id in FacetsRules.FACETS:
		var field := "%s.facets.%s" % [path, facet_id]
		if not build.facets.has(facet_id):
			errors.append(FacetsError.make(FacetsError.MISSING_FIELD, "Facet '%s' is missing." % facet_id, field))
			continue
		var value := build.facet(facet_id)
		if value < minimum:
			errors.append(FacetsError.make(FacetsError.OUT_OF_RANGE, "Facet '%s' cannot be below %d; lowering a facet refunds nothing." % [facet_id, minimum], field))
		elif value > maximum:
			errors.append(FacetsError.make(FacetsError.OUT_OF_RANGE, "Facet '%s' cannot exceed %d." % [facet_id, maximum], field))
	for facet_id in build.facets:
		if not FacetsRules.FACETS.has(facet_id):
			errors.append(FacetsError.make(FacetsError.UNKNOWN_ID, "Unknown facet '%s'." % facet_id, "%s.facets.%s" % [path, facet_id]))
	return errors


static func _validate_skills(build: FacetsBuild, registry: FacetsRegistry, minimum: int, maximum: int, path: String) -> Array[FacetsError]:
	var errors: Array[FacetsError] = []
	var skill_ids := build.skills.keys()
	skill_ids.sort()
	for skill_id in skill_ids:
		var field := "%s.skills.%s" % [path, skill_id]
		if not registry.has_skill(skill_id):
			errors.append(FacetsError.make(FacetsError.UNKNOWN_ID, "Unknown skill '%s'." % skill_id, field))
			continue
		var rank := build.skill(skill_id)
		if rank < minimum:
			errors.append(FacetsError.make(FacetsError.OUT_OF_RANGE, "Skill '%s' cannot be negative." % skill_id, field))
		elif rank > maximum:
			errors.append(FacetsError.make(FacetsError.OUT_OF_RANGE, "Skill '%s' cannot exceed %d." % [skill_id, maximum], field))
	return errors


static func _validate_talents(build: FacetsBuild, registry: FacetsRegistry, path: String) -> Array[FacetsError]:
	var errors: Array[FacetsError] = []
	var seen := {}
	for index in build.talents.size():
		var talent_id := build.talents[index]
		var field := "%s.talents[%d]" % [path, index]
		if not registry.has_talent(talent_id):
			errors.append(FacetsError.make(FacetsError.UNKNOWN_ID, "Unknown talent '%s'." % talent_id, field))
			continue
		var definition := registry.get_talent(talent_id)
		if seen.has(talent_id) and not bool(definition.get("repeatable", false)):
			errors.append(FacetsError.make(FacetsError.DUPLICATE, "Talent '%s' is not repeatable." % talent_id, field))
		seen[talent_id] = true
		for error in prerequisite_errors(definition, build, field):
			errors.append(error)
	return errors


static func prerequisite_errors(talent_def: Dictionary, build: FacetsBuild, path: String) -> Array[FacetsError]:
	var errors: Array[FacetsError] = []
	var prerequisites: Dictionary = talent_def.get("prerequisites", {})
	var facets: Dictionary = prerequisites.get("facets", {})
	for facet_id in facets:
		if build.facet(facet_id) < int(facets[facet_id]):
			errors.append(FacetsError.make(FacetsError.PREREQUISITE, "%s needs %s %d." % [talent_def.get("display_name", talent_def.get("id")), facet_id, int(facets[facet_id])], path))
	var skills: Dictionary = prerequisites.get("skills", {})
	for skill_id in skills:
		if build.skill(skill_id) < int(skills[skill_id]):
			errors.append(FacetsError.make(FacetsError.PREREQUISITE, "%s needs %s %d." % [talent_def.get("display_name", talent_def.get("id")), skill_id, int(skills[skill_id])], path))
	for required in prerequisites.get("talents", []):
		if not build.has_talent(str(required)):
			errors.append(FacetsError.make(FacetsError.PREREQUISITE, "%s needs talent %s." % [talent_def.get("display_name", talent_def.get("id")), required], path))
	return errors


static func prerequisites_met(talent_def: Dictionary, build: FacetsBuild) -> bool:
	return prerequisite_errors(talent_def, build, "").is_empty()


# --- Authored definitions ------------------------------------------------------

static func validate_skill(definition: Dictionary, path: String = "skill") -> Array[FacetsError]:
	var errors: Array[FacetsError] = []
	if not _is_id(definition.get("id")):
		errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Skill needs a stable ID.", path + ".id"))
	return errors


static func validate_condition(definition: Dictionary, path: String = "condition") -> Array[FacetsError]:
	var errors: Array[FacetsError] = []
	if not _is_id(definition.get("id")):
		errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Condition needs a stable ID.", path + ".id"))
	var penalty := int(definition.get("penalty", 0))
	if penalty > 0 or penalty < FacetsRules.CONDITION_PENALTY_FLOOR:
		errors.append(FacetsError.make(FacetsError.OUT_OF_RANGE, "Condition penalty must be between -2 and 0.", path + ".penalty"))
	for restriction in definition.get("restrictions", []):
		if not RESTRICTIONS.has(str(restriction)):
			errors.append(FacetsError.make(FacetsError.UNKNOWN_ID, "Unknown restriction '%s'." % restriction, path + ".restrictions"))
	for facet_id in definition.get("applies_to_facets", []):
		if not FacetsRules.FACETS.has(str(facet_id)):
			errors.append(FacetsError.make(FacetsError.UNKNOWN_ID, "Unknown facet '%s'." % facet_id, path + ".applies_to_facets"))
	return errors


static func validate_talent(definition: Dictionary, registry: FacetsRegistry, path: String = "talent") -> Array[FacetsError]:
	var errors: Array[FacetsError] = []
	if not _is_id(definition.get("id")):
		errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Talent needs a stable ID.", path + ".id"))
	if int(definition.get("version", 0)) < 1:
		errors.append(FacetsError.make(FacetsError.OUT_OF_RANGE, "Talent version must be at least 1.", path + ".version"))
	var hook_id := str(definition.get("hook_id", ""))
	if not registry.hooks.has_hook(hook_id):
		errors.append(FacetsError.make(FacetsError.UNKNOWN_ID, "Unknown talent hook '%s'." % hook_id, path + ".hook_id"))
	else:
		for error in registry.hooks.validate_parameters(hook_id, definition.get("parameters", {}), registry.operations, path + ".parameters"):
			errors.append(error)
	if not USAGE_SCOPES.has(str(definition.get("usage_scope", ""))):
		errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Unknown usage scope.", path + ".usage_scope"))
	if int(definition.get("uses", 0)) < 0:
		errors.append(FacetsError.make(FacetsError.OUT_OF_RANGE, "Uses cannot be negative.", path + ".uses"))
	var prerequisites: Variant = definition.get("prerequisites", {})
	if prerequisites is Dictionary:
		for facet_id in prerequisites.get("facets", {}):
			if not FacetsRules.FACETS.has(str(facet_id)):
				errors.append(FacetsError.make(FacetsError.UNKNOWN_ID, "Unknown facet '%s'." % facet_id, path + ".prerequisite_facets"))
		for skill_id in prerequisites.get("skills", {}):
			if not registry.has_skill(str(skill_id)):
				errors.append(FacetsError.make(FacetsError.UNKNOWN_ID, "Unknown skill '%s'." % skill_id, path + ".prerequisite_skills"))
	return errors


static func validate_action(definition: Dictionary, registry: FacetsRegistry, path: String = "action") -> Array[FacetsError]:
	var errors: Array[FacetsError] = []
	var operations := registry.operations
	if not _is_id(definition.get("id")):
		errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Action needs a stable ID.", path + ".id"))
	if int(definition.get("version", 0)) < 1:
		errors.append(FacetsError.make(FacetsError.OUT_OF_RANGE, "Action version must be at least 1.", path + ".version"))
	var approaches: Variant = definition.get("approaches", [])
	if not approaches is Array or approaches.is_empty():
		errors.append(FacetsError.make(FacetsError.MISSING_FIELD, "Action needs at least one approach.", path + ".approaches"))
	else:
		var approach_ids := {}
		for index in approaches.size():
			var approach: Dictionary = approaches[index] if approaches[index] is Dictionary else {}
			var field := "%s.approaches[%d]" % [path, index]
			var approach_id := str(approach.get("id", ""))
			if not _is_id(approach_id):
				errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Approach needs an ID.", field + ".id"))
			elif approach_ids.has(approach_id):
				errors.append(FacetsError.make(FacetsError.DUPLICATE, "Duplicate approach '%s'." % approach_id, field + ".id"))
			approach_ids[approach_id] = true
			if not FacetsRules.FACETS.has(str(approach.get("facet", ""))):
				errors.append(FacetsError.make(FacetsError.UNKNOWN_ID, "Unknown facet '%s'." % approach.get("facet", ""), field + ".facet"))
			if not registry.has_skill(str(approach.get("skill", ""))):
				errors.append(FacetsError.make(FacetsError.UNKNOWN_ID, "Unknown skill '%s'." % approach.get("skill", ""), field + ".skill"))
	errors.append_array(operations.validate_list(FacetsOperations.KIND_REQUIREMENT, definition.get("requirements", []), path + ".requirements"))
	errors.append_array(operations.validate_list(FacetsOperations.KIND_REQUIREMENT, definition.get("routine_requirements", []), path + ".routine_requirements"))
	errors.append_array(operations.validate_list(FacetsOperations.KIND_EFFECT, definition.get("success_effects", []), path + ".success_effects"))
	errors.append_array(operations.validate_list(FacetsOperations.KIND_EFFECT, definition.get("failure_effects", []), path + ".failure_effects"))
	var difficulty: Dictionary = definition.get("difficulty", {}) if definition.get("difficulty", {}) is Dictionary else {}
	var kind := str(difficulty.get("kind", ""))
	if not DIFFICULTY_KINDS.has(kind):
		errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Difficulty must be fixed, opposed or routine.", path + ".difficulty_kind"))
	elif kind == "fixed":
		var target := int(difficulty.get("target", 0))
		if target < MIN_TARGET or target > MAX_TARGET:
			errors.append(FacetsError.make(FacetsError.OUT_OF_RANGE, "Target must be between %d and %d." % [MIN_TARGET, MAX_TARGET], path + ".target"))
	elif kind == "opposed":
		if not FacetsRules.FACETS.has(str(difficulty.get("defense_facet", ""))):
			errors.append(FacetsError.make(FacetsError.UNKNOWN_ID, "Opposed actions need a defending facet.", path + ".defense_facet"))
		if not registry.has_skill(str(difficulty.get("defense_skill", ""))):
			errors.append(FacetsError.make(FacetsError.UNKNOWN_ID, "Opposed actions need a defending skill.", path + ".defense_skill"))
	var defense_modifiers := _modifier_list(difficulty.get("defense_modifiers", []), path + ".defense_modifiers", operations, errors)
	var modifiers := _modifier_list(definition.get("modifiers", []), path + ".modifiers", operations, errors)
	for error in FacetsModifiers.validate(modifiers, defense_modifiers):
		error.field_path = path + "." + error.field_path
		errors.append(error)
	var relationship: Variant = definition.get("relationship", {})
	if relationship is Dictionary and not relationship.is_empty():
		if not _is_id(relationship.get("other_id")):
			errors.append(FacetsError.make(FacetsError.MISSING_FIELD, "Relationship needs other_id.", path + ".relationship"))
		if not ["trust", "affinity"].has(str(relationship.get("dimension", ""))):
			errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Relationship dimension must be trust or affinity.", path + ".relationship"))
	var costly: Variant = definition.get("costly_options", [])
	if bool(definition.get("allows_costly_success", false)) and (not costly is Array or costly.is_empty()):
		errors.append(FacetsError.make(FacetsError.MISSING_FIELD, "Costly success needs at least one authored cost.", path + ".costly_options"))
	errors.append_array(_option_list(costly, path + ".costly_options", operations))
	var benefits: Variant = definition.get("strong_benefits", [])
	errors.append_array(_option_list(benefits, path + ".strong_benefits", operations))
	errors.append_array(_option_list(definition.get("lesser_concessions", []), path + ".lesser_concessions", operations))
	var default_benefit := str(definition.get("default_benefit_id", ""))
	if not default_benefit.is_empty():
		var found := false
		for option in benefits:
			if option is Dictionary and str(option.get("id", "")) == default_benefit:
				found = true
				if bool(option.get("requires_consent", false)):
					errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "A safe default benefit cannot require consent.", path + ".default_benefit_id"))
		if not found:
			errors.append(FacetsError.make(FacetsError.UNKNOWN_ID, "Default benefit is not one of the strong benefits.", path + ".default_benefit_id"))
	if not RETRY_POLICIES.has(str(definition.get("retry_policy", ""))):
		errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Unknown retry policy.", path + ".retry_policy"))
	if int(definition.get("clock_cost", 0)) < 0:
		errors.append(FacetsError.make(FacetsError.OUT_OF_RANGE, "Clock cost cannot be negative.", path + ".clock_cost"))
	return errors


static func _modifier_list(items: Variant, path: String, operations: FacetsOperations, errors: Array[FacetsError]) -> Array[FacetsModifier]:
	var result: Array[FacetsModifier] = []
	if not items is Array:
		errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Expected a list of modifiers.", path))
		return result
	for index in items.size():
		var item: Variant = items[index]
		if not item is Dictionary:
			errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Modifier must be an object.", "%s[%d]" % [path, index]))
			continue
		if item.has("when"):
			errors.append_array(operations.validate_ref(FacetsOperations.KIND_REQUIREMENT, item["when"], "%s[%d].when" % [path, index]))
		result.append(FacetsModifier.from_dict(item))
	return result


static func _option_list(items: Variant, path: String, operations: FacetsOperations) -> Array[FacetsError]:
	var errors: Array[FacetsError] = []
	if not items is Array:
		errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Expected a list of options.", path))
		return errors
	var seen := {}
	for index in items.size():
		var option: Variant = items[index]
		var field := "%s[%d]" % [path, index]
		if not option is Dictionary:
			errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Option must be an object.", field))
			continue
		var option_id := str(option.get("id", ""))
		if not _is_id(option_id):
			errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Option needs an ID.", field + ".id"))
		elif seen.has(option_id):
			errors.append(FacetsError.make(FacetsError.DUPLICATE, "Duplicate option '%s'." % option_id, field + ".id"))
		seen[option_id] = true
		errors.append_array(operations.validate_list(FacetsOperations.KIND_EFFECT, option.get("effects", []), field + ".effects"))
	return errors


## Validates an authoring character Resource. Field paths use Resource
## property names so the editor dock can navigate to them.
static func validate_character(character: FacetsCharacterResource, registry: FacetsRegistry) -> Array[FacetsError]:
	var errors: Array[FacetsError] = []
	if not _is_id(character.id):
		errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Character needs a stable ID.", "id"))
	if character.facet_set == null:
		errors.append(FacetsError.make(FacetsError.MISSING_FIELD, "Character needs a facet set.", "facet_set"))
	if character.identity == null:
		errors.append(FacetsError.make(FacetsError.MISSING_FIELD, "Character needs an identity.", "identity"))
	for error in validate_creation(character.build(), registry, "build"):
		error.field_path = _character_field(error.field_path)
		errors.append(error)
	for index in character.bonds.size():
		var bond := character.bonds[index]
		if bond == null:
			continue
		if bond.trust < FacetsRules.BOND_MIN or bond.trust > FacetsRules.BOND_MAX or bond.affinity < FacetsRules.BOND_MIN or bond.affinity > FacetsRules.BOND_MAX:
			errors.append(FacetsError.make(FacetsError.OUT_OF_RANGE, "Bond trust and affinity must be -2..+2.", "bonds[%d]" % index))
	for index in character.identity_triggers.size():
		var trigger := character.identity_triggers[index]
		if trigger == null:
			continue
		var trigger_dict := trigger.to_dict()
		if not _is_id(trigger.id):
			errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Identity trigger needs an ID.", "identity_triggers[%d].id" % index))
		errors.append_array(registry.operations.validate_list(FacetsOperations.KIND_EFFECT, trigger_dict["disadvantage_effects"], "identity_triggers[%d].disadvantage_effects" % index))
		if trigger.disadvantage_effects.is_empty():
			errors.append(FacetsError.make(FacetsError.MISSING_FIELD, "An identity trigger needs a material disadvantage.", "identity_triggers[%d].disadvantage_effects" % index))
	for item_id in character.items:
		if int(character.items[item_id]) < 0:
			errors.append(FacetsError.make(FacetsError.OUT_OF_RANGE, "Item counts cannot be negative.", "items.%s" % item_id))
	return errors


static func _character_field(field_path: String) -> String:
	if field_path.begins_with("build.facets."):
		return "facet_set." + field_path.trim_prefix("build.facets.")
	if field_path == "build.facets":
		return "facet_set"
	if field_path.begins_with("build."):
		return field_path.trim_prefix("build.")
	return field_path


static func _is_id(value: Variant) -> bool:
	return value is String and not str(value).is_empty() and str(value).length() <= 128 and not str(value).contains(" ")
