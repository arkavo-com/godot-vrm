@tool
class_name FacetsIdentityResource
extends Resource
## Narrative identity. Mechanics are never inferred from this prose.

@export var name: String = "":
	set(value):
		name = value
		emit_changed()
@export_multiline var drive: String = "":
	set(value):
		drive = value
		emit_changed()
@export_multiline var code: String = "":
	set(value):
		code = value
		emit_changed()
@export_multiline var hindrance: String = "":
	set(value):
		hindrance = value
		emit_changed()
@export_multiline var tell: String = "":
	set(value):
		tell = value
		emit_changed()
@export var appearance_refs: Array[String] = []:
	set(value):
		appearance_refs = value
		emit_changed()


func to_dict() -> Dictionary:
	return {
		"name": name,
		"drive": drive,
		"code": code,
		"hindrance": hindrance,
		"tell": tell,
		"appearance_refs": appearance_refs.duplicate(),
	}


static func from_dict(data: Dictionary) -> FacetsIdentityResource:
	var identity := FacetsIdentityResource.new()
	identity.name = str(data.get("name", ""))
	identity.drive = str(data.get("drive", ""))
	identity.code = str(data.get("code", ""))
	identity.hindrance = str(data.get("hindrance", ""))
	identity.tell = str(data.get("tell", ""))
	for item in data.get("appearance_refs", []):
		identity.appearance_refs.append(str(item))
	return identity
