@tool
class_name FacetsSkillResource
extends Resource
## Skill definition. Genre skills share the creation budget with core skills.

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var genre: bool = false


func to_dict() -> Dictionary:
	return {"id": id, "display_name": display_name, "description": description, "genre": genre}


static func from_dict(data: Dictionary) -> FacetsSkillResource:
	var skill := FacetsSkillResource.new()
	skill.id = str(data.get("id", ""))
	skill.display_name = str(data.get("display_name", ""))
	skill.description = str(data.get("description", ""))
	skill.genre = bool(data.get("genre", false))
	return skill
