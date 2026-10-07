@tool
class_name FacetsMigrations
extends RefCounted
## Explicit version migrations. Separate version domains:
##   schema_version  (portable JSON shape, currently 1)
##   ruleset_id / ruleset_version  ("facets.core" / "0.1.0")
## The source sample "gom.facets.core@0.1.0" is accepted only as an explicit
## legacy alias and rewritten to facets.core 0.1.0. Unrecognized versions are
## rejected; future schemas fail clearly instead of loading lossily.
## Migrations never change balance silently.

const LEGACY_ALIASES := {
	"gom.facets.core@0.1.0": ["facets.core", "0.1.0"],
}


## Returns FacetsReply with {"data": migrated copy, "notes": [String]}.
static func migrate(data: Dictionary) -> FacetsReply:
	var migrated: Dictionary = FacetsJson.clone(data)
	var notes: Array[String] = []
	if not migrated.has("schema_version"):
		return FacetsReply.fail(FacetsError.MISSING_FIELD, "schema_version is required.", "schema_version")
	var schema: Variant = migrated["schema_version"]
	if not schema is int:
		return FacetsReply.fail(FacetsError.INVALID_FIELD, "schema_version must be an integer.", "schema_version")
	if schema > FacetsRules.SCHEMA_VERSION:
		return FacetsReply.fail(FacetsError.FUTURE_SCHEMA, "This data uses schema version %d; this build reads up to %d. Update FACETS to load it." % [schema, FacetsRules.SCHEMA_VERSION], "schema_version")
	if schema < 1:
		return FacetsReply.fail(FacetsError.UNSUPPORTED_VERSION, "Schema version %d is not supported." % schema, "schema_version")
	if migrated.has("ruleset"):
		var alias := str(migrated["ruleset"])
		if not LEGACY_ALIASES.has(alias):
			return FacetsReply.fail(FacetsError.UNSUPPORTED_VERSION, "Unrecognized ruleset '%s'." % alias, "ruleset")
		migrated.erase("ruleset")
		migrated["ruleset_id"] = LEGACY_ALIASES[alias][0]
		migrated["ruleset_version"] = LEGACY_ALIASES[alias][1]
		notes.append("Legacy ruleset alias %s migrated to %s@%s." % [alias, LEGACY_ALIASES[alias][0], LEGACY_ALIASES[alias][1]])
	var combined := "%s@%s" % [migrated.get("ruleset_id", ""), migrated.get("ruleset_version", "")]
	if LEGACY_ALIASES.has(combined):
		migrated["ruleset_id"] = LEGACY_ALIASES[combined][0]
		migrated["ruleset_version"] = LEGACY_ALIASES[combined][1]
		notes.append("Legacy ruleset alias %s migrated to %s@%s." % [combined, LEGACY_ALIASES[combined][0], LEGACY_ALIASES[combined][1]])
	if str(migrated.get("ruleset_id", "")) != FacetsRules.RULESET_ID:
		return FacetsReply.fail(FacetsError.UNSUPPORTED_VERSION, "Unrecognized ruleset '%s'." % migrated.get("ruleset_id", ""), "ruleset_id")
	if str(migrated.get("ruleset_version", "")) != FacetsRules.RULESET_VERSION:
		return FacetsReply.fail(FacetsError.UNSUPPORTED_VERSION, "Unsupported ruleset version '%s'." % migrated.get("ruleset_version", ""), "ruleset_version")
	return FacetsReply.success({"data": migrated, "notes": notes})
