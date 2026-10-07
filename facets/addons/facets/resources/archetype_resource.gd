@tool
class_name FacetsArchetypeResource
extends Resource
## Editable creation preset (courier, investigator, mediator, protector,
## tinkerer). Applying a preset copies values; it never links definitions.

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var facets: Dictionary = {}
@export var skills: Dictionary = {}
@export var talents: Array[String] = []


func build() -> FacetsBuild:
	return FacetsBuild.from_dict({"facets": facets, "skills": skills, "talents": talents})


func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"description": description,
		"build": build().to_dict(),
	}


static func from_dict(data: Dictionary) -> FacetsArchetypeResource:
	var archetype := FacetsArchetypeResource.new()
	archetype.id = str(data.get("id", ""))
	archetype.display_name = str(data.get("display_name", ""))
	archetype.description = str(data.get("description", ""))
	var build_data: Dictionary = data.get("build", {})
	archetype.facets = build_data.get("facets", {}).duplicate()
	archetype.skills = build_data.get("skills", {}).duplicate()
	for talent_id in build_data.get("talents", []):
		archetype.talents.append(str(talent_id))
	return archetype
