@tool
class_name FacetsRulesPack
extends Resource
## Versioned content pack: skills, talents, conditions, actions, archetypes
## and an admission policy, with explicit dependency versions.

@export var pack_id: String = ""
@export var version: String = "0.1.0"
@export var ruleset_id: String = FacetsRules.RULESET_ID
@export var ruleset_version: String = FacetsRules.RULESET_VERSION
## pack_id -> exact version string.
@export var dependencies: Dictionary = {}
@export var compatibility: String = ""
@export var skills: Array[FacetsSkillResource] = []
@export var talents: Array[FacetsTalentResource] = []
@export var conditions: Array[FacetsConditionResource] = []
@export var actions: Array[FacetsActionResource] = []
@export var archetypes: Array[FacetsArchetypeResource] = []
@export var admission_policy: FacetsAdmissionPolicy


func to_dict() -> Dictionary:
	return {
		"schema_version": FacetsRules.SCHEMA_VERSION,
		"pack_id": pack_id,
		"version": version,
		"ruleset_id": ruleset_id,
		"ruleset_version": ruleset_version,
		"dependencies": dependencies.duplicate(),
		"compatibility": compatibility,
		"skills": _dicts(skills),
		"talents": _dicts(talents),
		"conditions": _dicts(conditions),
		"actions": _dicts(actions),
		"archetypes": _dicts(archetypes),
		"admission_policy": admission_policy.to_dict() if admission_policy != null else {},
	}


static func _dicts(items: Array) -> Array:
	var result: Array = []
	for item in items:
		if item != null:
			result.append(item.to_dict())
	return result


static func from_dict(data: Dictionary) -> FacetsRulesPack:
	var pack := FacetsRulesPack.new()
	pack.pack_id = str(data.get("pack_id", ""))
	pack.version = str(data.get("version", "0.1.0"))
	pack.ruleset_id = str(data.get("ruleset_id", FacetsRules.RULESET_ID))
	pack.ruleset_version = str(data.get("ruleset_version", FacetsRules.RULESET_VERSION))
	var deps: Variant = data.get("dependencies", {})
	pack.dependencies = deps.duplicate() if deps is Dictionary else {}
	pack.compatibility = str(data.get("compatibility", ""))
	for item in data.get("skills", []):
		pack.skills.append(FacetsSkillResource.from_dict(item))
	for item in data.get("talents", []):
		pack.talents.append(FacetsTalentResource.from_dict(item))
	for item in data.get("conditions", []):
		pack.conditions.append(FacetsConditionResource.from_dict(item))
	for item in data.get("actions", []):
		pack.actions.append(FacetsActionResource.from_dict(item))
	for item in data.get("archetypes", []):
		pack.archetypes.append(FacetsArchetypeResource.from_dict(item))
	var policy: Variant = data.get("admission_policy", {})
	if policy is Dictionary and not policy.is_empty():
		pack.admission_policy = FacetsAdmissionPolicy.from_dict(policy)
	return pack
