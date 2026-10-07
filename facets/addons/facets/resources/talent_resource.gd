@tool
class_name FacetsTalentResource
extends Resource
## Talent definition. Behavior comes from a registered typed hook
## ([member hook_id]) with typed [member parameters]; content cannot embed
## executable effect scripts.

@export var id: String = ""
@export var version: int = 1
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var hook_id: String = ""
@export var parameters: Dictionary = {}
@export var prerequisite_facets: Dictionary = {}
@export var prerequisite_skills: Dictionary = {}
@export var prerequisite_talents: Array[String] = []
@export_enum("passive", "per_check", "per_scene", "per_round", "per_encounter") var usage_scope: String = "per_scene"
@export var uses: int = 1
@export var repeatable: bool = false
## Owning package: "core" or "combat".
@export var package: String = "core"


func to_dict() -> Dictionary:
	return {
		"id": id,
		"version": version,
		"display_name": display_name,
		"description": description,
		"hook_id": hook_id,
		"parameters": parameters.duplicate(true),
		"prerequisites": {
			"facets": prerequisite_facets.duplicate(),
			"skills": prerequisite_skills.duplicate(),
			"talents": prerequisite_talents.duplicate(),
		},
		"usage_scope": usage_scope,
		"uses": uses,
		"repeatable": repeatable,
		"package": package,
	}


static func from_dict(data: Dictionary) -> FacetsTalentResource:
	var talent := FacetsTalentResource.new()
	talent.id = str(data.get("id", ""))
	talent.version = int(data.get("version", 1))
	talent.display_name = str(data.get("display_name", ""))
	talent.description = str(data.get("description", ""))
	talent.hook_id = str(data.get("hook_id", ""))
	var params_value: Variant = data.get("parameters", {})
	talent.parameters = params_value.duplicate(true) if params_value is Dictionary else {}
	var prerequisites: Dictionary = data.get("prerequisites", {}) if data.get("prerequisites", {}) is Dictionary else {}
	talent.prerequisite_facets = prerequisites.get("facets", {}).duplicate()
	talent.prerequisite_skills = prerequisites.get("skills", {}).duplicate()
	for talent_id in prerequisites.get("talents", []):
		talent.prerequisite_talents.append(str(talent_id))
	talent.usage_scope = str(data.get("usage_scope", "per_scene"))
	talent.uses = int(data.get("uses", 1))
	talent.repeatable = bool(data.get("repeatable", false))
	talent.package = str(data.get("package", "core"))
	return talent
