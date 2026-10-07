@tool
class_name FacetsCharacterCodec
extends RefCounted
## Portable character codec. Imported character data is parsed as JSON into
## allowlisted fields only; it is never passed to load() or instantiated as a
## Resource. Field errors carry JSON paths.

const TOP_FIELDS: Array[String] = [
	"schema_version", "ruleset_id", "ruleset_version", "ruleset", "character_id", "identity",
	"preferred_build", "memories", "extensions", "growth", "equipment", "accomplishments",
]
const IDENTITY_FIELDS: Array[String] = ["name", "drive", "code", "hindrance", "tell", "appearance_refs"]
const BUILD_FIELDS: Array[String] = ["facets", "skills", "talents", "capabilities"]
const MEMORY_FIELDS: Array[String] = ["id", "source", "text"]
## Sanity bounds for imported preferences (advanced builds are allowed).
const MAX_PREFERRED_RATING := 10


static func encode(character: FacetsPortableCharacter) -> String:
	return FacetsJson.canonical(character.to_dict())


static func decode(json_text: String, registry: FacetsRegistry, limits: FacetsImportLimits = null) -> FacetsReply:
	var bounds := limits if limits != null else FacetsImportLimits.standard()
	var parsed := FacetsJson.parse(json_text, bounds.max_bytes, bounds.max_depth)
	if not parsed.ok:
		return parsed
	return decode_dict(parsed.value, registry, bounds)


static func decode_dict(source: Variant, registry: FacetsRegistry, limits: FacetsImportLimits = null) -> FacetsReply:
	var bounds := limits if limits != null else FacetsImportLimits.standard()
	if not source is Dictionary:
		return FacetsReply.fail(FacetsError.MALFORMED, "A character must be a JSON object.")
	var migrated := FacetsMigrations.migrate(source)
	if not migrated.ok:
		return migrated
	var data: Dictionary = migrated.value["data"]
	var errors: Array[FacetsError] = []
	for key in data:
		if not TOP_FIELDS.has(str(key)):
			errors.append(FacetsError.make(FacetsError.UNKNOWN_FIELD, "Unknown field '%s'." % key, str(key)))
	var character := FacetsPortableCharacter.new()
	for note in migrated.value["notes"]:
		character.migration_notes.append(str(note))
	character.character_id = _id(data.get("character_id"), "character_id", errors, bounds)

	# Identity: narrative only.
	var identity: Variant = data.get("identity")
	if not identity is Dictionary:
		errors.append(FacetsError.make(FacetsError.MISSING_FIELD, "identity is required.", "identity"))
	else:
		for key in identity:
			if not IDENTITY_FIELDS.has(str(key)):
				errors.append(FacetsError.make(FacetsError.UNKNOWN_FIELD, "Unknown identity field '%s'." % key, "identity.%s" % key))
		for key in ["name", "drive", "code", "hindrance", "tell"]:
			if identity.has(key):
				character.identity[key] = _text(identity[key], "identity.%s" % key, errors, bounds)
		if str(character.identity.get("name", "")).is_empty():
			errors.append(FacetsError.make(FacetsError.MISSING_FIELD, "identity.name is required.", "identity.name"))
		if identity.has("appearance_refs"):
			character.identity["appearance_refs"] = _string_list(identity["appearance_refs"], "identity.appearance_refs", errors, bounds)

	# Preferred build.
	var build: Variant = data.get("preferred_build")
	if not build is Dictionary:
		errors.append(FacetsError.make(FacetsError.MISSING_FIELD, "preferred_build is required.", "preferred_build"))
	else:
		for key in build:
			if not BUILD_FIELDS.has(str(key)):
				errors.append(FacetsError.make(FacetsError.UNKNOWN_FIELD, "Unknown build field '%s'." % key, "preferred_build.%s" % key))
		var facets: Variant = build.get("facets", {})
		if not facets is Dictionary:
			errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "facets must be an object.", "preferred_build.facets"))
		else:
			for facet_id in facets:
				var path := "preferred_build.facets.%s" % facet_id
				if not FacetsRules.FACETS.has(str(facet_id)):
					errors.append(FacetsError.make(FacetsError.UNKNOWN_ID, "Unknown facet '%s'." % facet_id, path))
					continue
				character.preferred_build.facets[str(facet_id)] = _rating(facets[facet_id], path, errors)
			for facet_id in FacetsRules.FACETS:
				if not facets.has(facet_id):
					errors.append(FacetsError.make(FacetsError.MISSING_FIELD, "Facet '%s' is missing." % facet_id, "preferred_build.facets.%s" % facet_id))
		var skills: Variant = build.get("skills", {})
		if not skills is Dictionary:
			errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "skills must be an object.", "preferred_build.skills"))
		elif skills.size() > bounds.max_list:
			return FacetsReply.fail(FacetsError.TOO_LARGE, "At most %d skills." % bounds.max_list, "preferred_build.skills")
		else:
			for skill_id in skills:
				var path := "preferred_build.skills.%s" % skill_id
				if not registry.has_skill(str(skill_id)):
					errors.append(FacetsError.make(FacetsError.UNKNOWN_ID, "Unknown skill '%s'." % skill_id, path))
					continue
				character.preferred_build.skills[str(skill_id)] = _rating(skills[skill_id], path, errors)
		var talents := _string_list(build.get("talents", []), "preferred_build.talents", errors, bounds)
		for index in talents.size():
			if not registry.has_talent(talents[index]):
				errors.append(FacetsError.make(FacetsError.UNKNOWN_ID, "Unknown talent '%s'." % talents[index], "preferred_build.talents[%d]" % index))
		character.preferred_build.talents = talents
		var capabilities := _string_list(build.get("capabilities", []), "preferred_build.capabilities", errors, bounds)
		for index in capabilities.size():
			if not capabilities[index].contains("."):
				errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Capability IDs must be namespaced.", "preferred_build.capabilities[%d]" % index))
		character.preferred_build.capabilities = capabilities

	# Memories: source-labeled references only.
	var memories: Variant = data.get("memories", [])
	if not memories is Array:
		errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "memories must be a list.", "memories"))
	elif memories.size() > bounds.max_list:
		return FacetsReply.fail(FacetsError.TOO_LARGE, "At most %d memories." % bounds.max_list, "memories")
	else:
		for index in memories.size():
			var memory: Variant = memories[index]
			var path := "memories[%d]" % index
			if not memory is Dictionary:
				errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Memory must be an object.", path))
				continue
			for key in memory:
				if not MEMORY_FIELDS.has(str(key)):
					errors.append(FacetsError.make(FacetsError.UNKNOWN_FIELD, "Unknown memory field '%s'." % key, "%s.%s" % [path, key]))
			var entry := {"source": _text(memory.get("source", ""), path + ".source", errors, bounds), "text": _text(memory.get("text", ""), path + ".text", errors, bounds)}
			if memory.has("id"):
				entry["id"] = _text(memory["id"], path + ".id", errors, bounds)
			if str(entry["source"]).is_empty():
				errors.append(FacetsError.make(FacetsError.MISSING_FIELD, "Memories must name their source.", path + ".source"))
			character.memories.append(entry)

	# Extensions: namespaced, inert.
	var extensions: Variant = data.get("extensions", {})
	if not extensions is Dictionary:
		errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "extensions must be an object.", "extensions"))
	else:
		for key in extensions:
			if not str(key).contains(".") or str(key).begins_with("facets.") or str(key).begins_with("core."):
				errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Extension keys must be vendor-namespaced (e.g. 'vendor.key').", "extensions.%s" % key))
		character.extensions = extensions.duplicate(true)

	if data.has("growth"):
		var growth: Variant = data["growth"]
		if not growth is int or growth < 0:
			errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "growth must be a non-negative integer.", "growth"))
		else:
			character.growth = growth
	character.equipment = _string_list(data.get("equipment", []), "equipment", errors, bounds)
	character.accomplishments = _string_list(data.get("accomplishments", []), "accomplishments", errors, bounds)
	if not errors.is_empty():
		return FacetsReply.failures(errors)
	return FacetsReply.success(character)


static func _id(value: Variant, path: String, errors: Array[FacetsError], bounds: FacetsImportLimits) -> String:
	if not value is String or str(value).is_empty():
		errors.append(FacetsError.make(FacetsError.MISSING_FIELD, "%s is required." % path, path))
		return ""
	if str(value).length() > 128 or str(value).contains(" "):
		errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "%s must be a stable ID without spaces." % path, path))
	return _text(value, path, errors, bounds)


static func _text(value: Variant, path: String, errors: Array[FacetsError], bounds: FacetsImportLimits) -> String:
	if not value is String:
		errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "%s must be text." % path, path))
		return ""
	if str(value).length() > bounds.max_text:
		errors.append(FacetsError.make(FacetsError.TOO_LARGE, "%s exceeds %d characters." % [path, bounds.max_text], path))
		return ""
	return str(value)


static func _rating(value: Variant, path: String, errors: Array[FacetsError]) -> int:
	if not value is int:
		errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "%s must be an integer." % path, path))
		return 0
	if value < 0 or value > MAX_PREFERRED_RATING:
		errors.append(FacetsError.make(FacetsError.OUT_OF_RANGE, "%s must be 0..%d." % [path, MAX_PREFERRED_RATING], path))
		return 0
	return value


static func _string_list(value: Variant, path: String, errors: Array[FacetsError], bounds: FacetsImportLimits) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "%s must be a list." % path, path))
		return result
	if value.size() > bounds.max_list:
		errors.append(FacetsError.make(FacetsError.TOO_LARGE, "%s has more than %d entries." % [path, bounds.max_list], path))
		return result
	for index in value.size():
		result.append(_text(value[index], "%s[%d]" % [path, index], errors, bounds))
	return result
