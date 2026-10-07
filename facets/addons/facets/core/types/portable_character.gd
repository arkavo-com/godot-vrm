@tool
class_name FacetsPortableCharacter
extends RefCounted
## Portable character envelope: identity plus a preferred build. It never
## authorizes importing live journey state. Imported Growth, equipment and
## capabilities are carried only so admission can report what it excludes.

var schema_version: int = FacetsRules.SCHEMA_VERSION
var ruleset_id: String = FacetsRules.RULESET_ID
var ruleset_version: String = FacetsRules.RULESET_VERSION
var character_id: String = ""
## name, drive, code, hindrance, tell, appearance_refs
var identity: Dictionary = {}
var preferred_build: FacetsBuild = FacetsBuild.new()
## [{source, text, id?}] source-labeled references, never local facts.
var memories: Array = []
## Namespaced inert JSON ("vendor.key" -> value), round-tripped untouched.
var extensions: Dictionary = {}
## Imported accumulated Growth (dropped by standard admission).
var growth: int = 0
## Imported equipment IDs (dropped unless the policy admits them).
var equipment: Array[String] = []
## Profile accomplishments from the source (labels only).
var accomplishments: Array[String] = []
## Notes from migrations applied while decoding.
var migration_notes: Array[String] = []


func to_dict() -> Dictionary:
	var result := {
		"schema_version": schema_version,
		"ruleset_id": ruleset_id,
		"ruleset_version": ruleset_version,
		"character_id": character_id,
		"identity": identity.duplicate(true),
		"preferred_build": preferred_build.to_dict(),
		"memories": memories.duplicate(true),
		"extensions": extensions.duplicate(true),
	}
	if growth != 0:
		result["growth"] = growth
	if not equipment.is_empty():
		result["equipment"] = equipment.duplicate()
	if not accomplishments.is_empty():
		result["accomplishments"] = accomplishments.duplicate()
	return result


static func from_resource(character: FacetsCharacterResource) -> FacetsPortableCharacter:
	var portable := FacetsPortableCharacter.new()
	portable.character_id = character.id
	portable.identity = character.identity_dict()
	portable.preferred_build = FacetsBuild.from_dict(character.preferred_build_dict())
	for item_id in character.items:
		portable.equipment.append(str(item_id))
	portable.equipment.sort()
	return portable
